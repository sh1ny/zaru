import 'dart:convert';

import '../json_printer.dart';
import '../number.dart';
import '../value.dart';
import 'ast.dart';

/// Marks a node that jq's parser would not leave as a single constant
/// instruction.
const Object notConstant = _NotConstant();

final class _NotConstant {
  const _NotConstant();

  @override
  String toString() => 'notConstant';
}

/// The constant value jq's `block_is_const` would see for [node], in the
/// private value domain (null, bool, String, [JqNumber], [JqArray],
/// [JqObject]), or [notConstant].
///
/// jq folds as it parses, so the answer depends on the exact shape that the
/// grammar produces:
///
/// * literals, `null`/`true`/`false` and strings without interpolation are
///   constants (a format prefix only affects interpolations);
/// * a binary arithmetic or comparison operator over two constants is folded
///   immediately, and a fold that would fail at run time is not a constant;
/// * `[...]` is constant when its elements form a left-nested comma chain of
///   constants (`gen_const_array`);
/// * `{...}` is constant when every key is a constant string and every value
///   is constant (`gen_const_object`);
/// * parentheses are transparent, while unary minus, pipes, `and`/`or`,
///   `//`, calls and variables never are.
Object? constantOf(Node node) {
  switch (node) {
    case Group(:final inner):
      return constantOf(inner);
    case LiteralConstant(:final value):
      return value;
    case NumberLiteral(:final text):
      return JqNumber.tryParseLiteral(text) ?? notConstant;
    case StringLiteral():
      return node.isConstant ? node.constantValue : notConstant;
    case ArrayConstructor(:final body):
      if (body == null) return JqArray(<Object?>[]);
      final items = <Object?>[];
      return _collectElements(body, items) ? JqArray(items) : notConstant;
    case ObjectConstructor(:final entries):
      final map = <String, Object?>{};
      for (final entry in entries) {
        final key = constantOf(entry.key);
        if (key is! String) return notConstant;
        final value = constantOf(entry.value);
        if (identical(value, notConstant)) return notConstant;
        map[key] = value;
      }
      return JqObject(map);
    case Binary(:final operator, :final left, :final right):
      final a = constantOf(left);
      if (identical(a, notConstant)) return notConstant;
      final b = constantOf(right);
      if (identical(b, notConstant)) return notConstant;
      return _fold(operator, a, b);
    default:
      return notConstant;
  }
}

/// jq's `gen_const_array` accepts `FORK (...) LOADK JUMP LOADK ...`: the comma
/// chain must lean left, and each right operand must itself be a constant
/// element rather than another chain.
bool _collectElements(Node body, List<Object?> out) {
  var node = body;
  while (node is Group) {
    node = node.inner;
  }
  if (node is Comma) {
    if (!_collectElements(node.left, out)) return false;
    var right = node.right;
    while (right is Group) {
      right = right.inner;
    }
    if (right is Comma) return false;
    final value = constantOf(right);
    if (identical(value, notConstant)) return false;
    out.add(value);
    return true;
  }
  final value = constantOf(node);
  if (identical(value, notConstant)) return false;
  out.add(value);
  return true;
}

/// jq's kind names, as in `Cannot use KIND (...) as object key`.
String kindName(Object? value) => switch (value) {
  null => 'null',
  bool() => 'boolean',
  JqNumber() => 'number',
  String() => 'string',
  JqArray() => 'array',
  JqObject() => 'object',
  _ => throw ArgumentError.value(value, 'value'),
};

/// `jv_dump_string_trunc` with jq's 30-byte buffer: compact text that is cut
/// before the last four or five bytes, then `...` and the closing delimiter
/// (`"`, `]` or `}`) of a string, array or object, never splitting a UTF-8
/// sequence.
String dumpTruncated(Object? value) {
  const bufferSize = 30;
  final bytes = utf8.encode(printJson(value));
  if (bytes.length <= bufferSize - 1) return utf8.decode(bytes);
  final delimiter = switch (bytes.first) {
    0x22 => 0x22,
    0x5b => 0x5d,
    0x7b => 0x7d,
    _ => 0,
  };
  var length = bufferSize - (delimiter != 0 ? 5 : 4);
  // jvp_utf8_backtrack: do not end inside a multi-byte sequence.
  var lead = length;
  while (lead > 0 && (bytes[lead] & 0xc0) == 0x80) {
    lead--;
  }
  if (lead != length && length - lead < 4) length = lead;
  final out = [...bytes.sublist(0, length), 0x2e, 0x2e, 0x2e];
  if (delimiter != 0) out.add(delimiter);
  return utf8.decode(out, allowMalformed: true);
}

// ---------------------------------------------------------------------------
// Folding, following src/builtin.c's binop_* functions.

/// The longest string a folded repetition may build. Beyond it the fold is
/// abandoned (treated as non-constant); the result kind of a repetition is
/// a string either way.
const int _maxFoldedLength = 1 << 20;

Object? _fold(BinaryOperator op, Object? a, Object? b) {
  switch (op) {
    case BinaryOperator.add:
      return _plus(a, b);
    case BinaryOperator.subtract:
      return _minus(a, b);
    case BinaryOperator.multiply:
      return _multiply(a, b);
    case BinaryOperator.divide:
      return _divide(a, b);
    case BinaryOperator.modulo:
      return _modulo(a, b);
    case BinaryOperator.equal:
      return _compare(a, b) == 0;
    case BinaryOperator.notEqual:
      return _compare(a, b) != 0;
    case BinaryOperator.less:
      return _compare(a, b) < 0;
    case BinaryOperator.greater:
      return _compare(a, b) > 0;
    case BinaryOperator.lessOrEqual:
      return _compare(a, b) <= 0;
    case BinaryOperator.greaterOrEqual:
      return _compare(a, b) >= 0;
  }
}

Object? _number(double value) => JqNumber.computed(value);

Object? _plus(Object? a, Object? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (a is JqNumber && b is JqNumber) return _number(a.value + b.value);
  if (a is String && b is String) return a + b;
  if (a is JqArray && b is JqArray) {
    return JqArray([...a.items, ...b.items]);
  }
  if (a is JqObject && b is JqObject) {
    return JqObject({...a.entries, ...b.entries});
  }
  return notConstant;
}

Object? _minus(Object? a, Object? b) {
  if (a is JqNumber && b is JqNumber) return _number(a.value - b.value);
  if (a is JqArray && b is JqArray) {
    return JqArray([
      for (final x in a.items)
        if (!b.items.any((y) => _compare(x, y) == 0)) x,
    ]);
  }
  return notConstant;
}

Object? _multiply(Object? a, Object? b) {
  if (a is JqNumber && b is JqNumber) return _number(a.value * b.value);
  if ((a is String && b is JqNumber) || (a is JqNumber && b is String)) {
    final text = a is String ? a : b as String;
    final d = (a is JqNumber ? a : b as JqNumber).value;
    if (d.isNaN || d < 0) return null;
    final count = d > 2147483647 ? 2147483647 : d.truncate();
    if (count == 0) return '';
    if (text.length * count > _maxFoldedLength) return notConstant;
    return text * count;
  }
  if (a is JqObject && b is JqObject) return _mergeDeep(a, b);
  return notConstant;
}

JqObject _mergeDeep(JqObject a, JqObject b) {
  final merged = <String, Object?>{...a.entries};
  b.entries.forEach((key, value) {
    final existing = merged[key];
    merged[key] = existing is JqObject && value is JqObject
        ? _mergeDeep(existing, value)
        : value;
  });
  return JqObject(merged);
}

Object? _divide(Object? a, Object? b) {
  if (a is JqNumber && b is JqNumber) {
    if (b.value == 0.0) return notConstant;
    return _number(a.value / b.value);
  }
  if (a is String && b is String) {
    if (a.isEmpty) return JqArray(<Object?>[]);
    if (b.isEmpty) {
      return JqArray([for (final rune in a.runes) String.fromCharCode(rune)]);
    }
    return JqArray(a.split(b));
  }
  return notConstant;
}

final BigInt _intMax = BigInt.parse('9223372036854775807');
final BigInt _intMin = BigInt.parse('-9223372036854775808');

/// `dtoi`: clamp a double to the intmax_t range and truncate toward zero.
BigInt _toIntMax(double n) {
  if (n < -9223372036854775808.0) return _intMin;
  if (-n <= -9223372036854775808.0) return _intMax;
  return BigInt.from(n.truncate());
}

Object? _modulo(Object? a, Object? b) {
  if (a is! JqNumber || b is! JqNumber) return notConstant;
  final na = a.value;
  final nb = b.value;
  if (na.isNaN || nb.isNaN) return _number(double.nan);
  final divisor = _toIntMax(nb);
  if (divisor == BigInt.zero) return notConstant;
  if (divisor == BigInt.from(-1)) return _number(0);
  return _number(_toIntMax(na).remainder(divisor).toDouble());
}

/// `jv_cmp`: null < false < true < numbers < strings < arrays < objects.
int _compare(Object? a, Object? b) {
  final ra = _rank(a);
  final rb = _rank(b);
  if (ra != rb) return ra < rb ? -1 : 1;
  if (a is JqNumber && b is JqNumber) {
    if (a.value.isNaN) return -1;
    return JqNumber.compare(a, b);
  }
  if (a is String && b is String) return _compareRunes(a, b);
  if (a is JqArray && b is JqArray) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final c = _compare(a.items[i], b.items[i]);
      if (c != 0) return c;
    }
    return a.length.compareTo(b.length);
  }
  if (a is JqObject && b is JqObject) {
    final ka = a.entries.keys.toList()..sort(_compareRunes);
    final kb = b.entries.keys.toList()..sort(_compareRunes);
    final keys = _compare(JqArray(ka), JqArray(kb));
    if (keys != 0) return keys;
    for (final key in ka) {
      final c = _compare(a.entries[key], b.entries[key]);
      if (c != 0) return c;
    }
  }
  return 0;
}

int _rank(Object? v) => switch (v) {
  null => 0,
  false => 1,
  true => 2,
  JqNumber() => 3,
  String() => 4,
  JqArray() => 5,
  _ => 6,
};

/// Orders strings by code point, which is jq's UTF-8 byte order.
int _compareRunes(String a, String b) {
  final ra = a.runes.iterator;
  final rb = b.runes.iterator;
  while (true) {
    final ha = ra.moveNext();
    final hb = rb.moveNext();
    if (!ha || !hb) return ha == hb ? 0 : (ha ? 1 : -1);
    if (ra.current != rb.current) return ra.current < rb.current ? -1 : 1;
  }
}
