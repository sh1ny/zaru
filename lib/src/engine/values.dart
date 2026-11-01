/// Value semantics of the core engine: kinds, ordering, equality, merge,
/// arithmetic, indexing, native ingestion and public projection.
///
/// An engine value is `null`, `bool`, `String`, a [JqNumber], a [JqArray], a
/// [JqObject], or a *public-compatible native value* passed by reference: a
/// `num` that binary64 holds exactly, or a `List`/`Map` whose whole subtree is
/// public-compatible (see [ingest]). Everything that walks nested data here
/// is iterative, so nesting depth never consumes host stack.
library;

import 'dart:collection';

import '../json_printer.dart';
import '../number.dart';
import '../syntax/ast.dart' show BinaryOperator;
import '../syntax/constants.dart' show dumpTruncated;
import '../unicode.dart';
import '../value.dart';

/// jq's `MAX_OBJECT_MERGE_DEPTH`, and the depth of its equality/order guards.
const int maxDepth = 10000;

/// A jq data error in flight. [value] is the engine-private error value.
final class JqError implements Exception {
  const JqError(this.value);

  final Object? value;
}

// ---------------------------------------------------------------------------
// Kinds.

bool isArray(Object? v) => v is JqArray || v is List<Object?>;

bool isObject(Object? v) => v is JqObject || v is Map<Object?, Object?>;

bool isNumber(Object? v) => v is num || v is JqNumber;

List<Object?> arrayItems(Object? v) =>
    v is JqArray ? v.items : v! as List<Object?>;

Map<Object?, Object?> objectEntries(Object? v) =>
    v is JqObject ? v.entries : v! as Map<Object?, Object?>;

bool isTruthy(Object? v) => v != null && v != false;

double numberValue(Object? v) =>
    v is JqNumber ? v.value : (v! as num).toDouble();

/// jq's kind names, as used in error messages.
String kindOf(Object? v) {
  if (v == null) return 'null';
  if (v is bool) return 'boolean';
  if (v is String) return 'string';
  if (isNumber(v)) return 'number';
  if (isArray(v)) return 'array';
  return 'object';
}

/// `KIND (DUMP)` with jq's 30-byte truncated dump.
String describe(Object? v) => '${kindOf(v)} (${dumpTruncated(v)})';

/// null < false < true < numbers < strings < arrays < objects.
int rank(Object? v) {
  if (v == null) return 0;
  if (v is bool) return v ? 2 : 1;
  if (isNumber(v)) return 3;
  if (v is String) return 4;
  if (isArray(v)) return 5;
  return 6;
}

JqNumber computed(double value) => JqNumber.computed(value);

// ---------------------------------------------------------------------------
// Ordering and equality.

/// `jv_cmp` for numbers: NaN orders as null (below every number).
int compareNumbers(Object? a, Object? b) {
  if (a is JqNumber && b is JqNumber) {
    if (a.isNan) return -1;
    if (b.isNan) return 1;
    return JqNumber.compare(a, b);
  }
  final x = numberValue(a);
  final y = numberValue(b);
  if (x.isNaN) return -1;
  if (y.isNaN) return 1;
  return x < y ? -1 : (x == y ? 0 : 1);
}

final class _OrderFrame {
  _OrderFrame(this.xs, this.ys, this.tail);

  final List<Object?> xs;
  final List<Object?> ys;

  /// What the frame's container pair compares as once every common element
  /// compared equal: the length order for arrays, zero for objects.
  final int tail;
  int index = 0;
}

List<String> _sortedKeys(Map<Object?, Object?> map) {
  final keys = [for (final key in map.keys) key! as String];
  keys.sort(compareUtf8Order);
  return keys;
}

/// `jv_cmp`: the total order of jq values. Throws a [JqError] when a value
/// pair sits deeper than [maxDepth] containers.
int compareValues(Object? a, Object? b) {
  final stack = <_OrderFrame>[];
  var x = a;
  var y = b;
  while (true) {
    if (stack.length > maxDepth) throw const JqError('Comparison too deep');
    var result = 0;
    final rx = rank(x);
    final ry = rank(y);
    if (rx != ry) {
      result = rx < ry ? -1 : 1;
    } else if (rx == 3) {
      result = compareNumbers(x, y);
    } else if (rx == 4) {
      result = compareUtf8Order(x! as String, y! as String);
    } else if (rx == 5) {
      final xs = arrayItems(x);
      final ys = arrayItems(y);
      final n = xs.length < ys.length ? xs.length : ys.length;
      final tail = xs.length.compareTo(ys.length);
      if (n > 0) {
        stack.add(_OrderFrame(xs, ys, tail));
        x = xs[0];
        y = ys[0];
        continue;
      }
      result = tail;
    } else if (rx == 6) {
      final mx = objectEntries(x);
      final my = objectEntries(y);
      final kx = _sortedKeys(mx);
      final ky = _sortedKeys(my);
      final n = kx.length < ky.length ? kx.length : ky.length;
      for (var i = 0; i < n && result == 0; i++) {
        result = compareUtf8Order(kx[i], ky[i]);
      }
      if (result == 0) result = kx.length.compareTo(ky.length);
      if (result == 0 && kx.isNotEmpty) {
        stack.add(
          _OrderFrame(
            [for (final key in kx) mx[key]],
            [for (final key in ky) my[key]],
            0,
          ),
        );
        x = stack.last.xs[0];
        y = stack.last.ys[0];
        continue;
      }
    }
    // The pair is decided; climb until a frame has another element.
    while (true) {
      if (result != 0 || stack.isEmpty) return result;
      final frame = stack.last;
      frame.index++;
      if (frame.index < frame.xs.length && frame.index < frame.ys.length) {
        x = frame.xs[frame.index];
        y = frame.ys[frame.index];
        break;
      }
      result = frame.tail;
      stack.removeLast();
    }
  }
}

bool _isContainer(Object? v) => isArray(v) || isObject(v);

/// `jv_equal`. The same container is equal to itself without a walk; any
/// other pair deeper than [maxDepth] is a [JqError].
bool equalValues(Object? a, Object? b) {
  if (identical(a, b) && _isContainer(a)) return true;
  final xs = <Object?>[a];
  final ys = <Object?>[b];
  final depths = <int>[0];
  while (xs.isNotEmpty) {
    final x = xs.removeLast();
    final y = ys.removeLast();
    final depth = depths.removeLast();
    if (identical(x, y) && _isContainer(x)) continue;
    if (depth > maxDepth) throw const JqError('Equality check too deep');
    final r = rank(x);
    if (r != rank(y)) return false;
    if (r == 3) {
      if (compareNumbers(x, y) != 0) return false;
    } else if (r == 4) {
      if (x != y) return false;
    } else if (r == 5) {
      final ax = arrayItems(x);
      final ay = arrayItems(y);
      if (ax.length != ay.length) return false;
      for (var i = ax.length - 1; i >= 0; i--) {
        xs.add(ax[i]);
        ys.add(ay[i]);
        depths.add(depth + 1);
      }
    } else if (r == 6) {
      final mx = objectEntries(x);
      final my = objectEntries(y);
      if (mx.length != my.length) return false;
      final keys = mx.keys.toList();
      for (var i = keys.length - 1; i >= 0; i--) {
        final key = keys[i];
        if (!my.containsKey(key)) return false;
        xs.add(mx[key]);
        ys.add(my[key]);
        depths.add(depth + 1);
      }
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// Recursive object merge (`*`).

final class _MergeFrame {
  _MergeFrame(this.right, this.result) : it = right.entries.iterator;

  final Map<Object?, Object?> right;
  final Map<String, Object?> result;
  final Iterator<MapEntry<Object?, Object?>> it;
  String? pending;
}

/// Deep merge of two objects; the right side wins. Iterative, with jq's depth
/// limit (root is depth zero).
JqObject mergeDeep(Object? a, Object? b) {
  final stack = <_MergeFrame>[];
  _MergeFrame open(Object? left, Object? right) {
    if (stack.length > maxDepth) throw const JqError('Object merge too deep');
    final frame = _MergeFrame(objectEntries(right), {
      for (final e in objectEntries(left).entries) e.key! as String: e.value,
    });
    stack.add(frame);
    return frame;
  }

  open(a, b);
  while (true) {
    final frame = stack.last;
    if (frame.it.moveNext()) {
      final key = frame.it.current.key! as String;
      final value = frame.it.current.value;
      final existing = frame.result[key];
      if (isObject(existing) && isObject(value)) {
        frame.pending = key;
        open(existing, value);
      } else {
        frame.result[key] = value;
      }
      continue;
    }
    final done = JqObject(frame.result);
    stack.removeLast();
    if (stack.isEmpty) return done;
    final parent = stack.last;
    parent.result[parent.pending!] = done;
  }
}

// ---------------------------------------------------------------------------
// Arithmetic.

JqError _binaryError(Object? a, Object? b, String verb) =>
    JqError('${describe(a)} and ${describe(b)} cannot be $verb');

/// Applies an arithmetic or comparison operator.
Object? applyBinary(BinaryOperator op, Object? a, Object? b) {
  switch (op) {
    case BinaryOperator.add:
      return add(a, b);
    case BinaryOperator.subtract:
      return subtract(a, b);
    case BinaryOperator.multiply:
      return multiply(a, b);
    case BinaryOperator.divide:
      return divide(a, b);
    case BinaryOperator.modulo:
      return modulo(a, b);
    case BinaryOperator.equal:
      return equalValues(a, b);
    case BinaryOperator.notEqual:
      return !equalValues(a, b);
    case BinaryOperator.less:
      return compareValues(a, b) < 0;
    case BinaryOperator.greater:
      return compareValues(a, b) > 0;
    case BinaryOperator.lessOrEqual:
      return compareValues(a, b) <= 0;
    case BinaryOperator.greaterOrEqual:
      return compareValues(a, b) >= 0;
  }
}

Object? add(Object? a, Object? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (isNumber(a) && isNumber(b)) {
    return computed(numberValue(a) + numberValue(b));
  }
  if (a is String && b is String) return a + b;
  if (isArray(a) && isArray(b)) {
    return JqArray([...arrayItems(a), ...arrayItems(b)]);
  }
  if (isObject(a) && isObject(b)) {
    final merged = <String, Object?>{
      for (final e in objectEntries(a).entries) e.key! as String: e.value,
    };
    for (final e in objectEntries(b).entries) {
      merged[e.key! as String] = e.value;
    }
    return JqObject(merged);
  }
  throw _binaryError(a, b, 'added');
}

Object? subtract(Object? a, Object? b) {
  if (isNumber(a) && isNumber(b)) {
    return computed(numberValue(a) - numberValue(b));
  }
  if (isArray(a) && isArray(b)) {
    final remove = arrayItems(b);
    return JqArray([
      for (final x in arrayItems(a))
        if (!remove.any((y) => equalValues(x, y))) x,
    ]);
  }
  throw _binaryError(a, b, 'subtracted');
}

/// The number of UTF-8 bytes of a normalized string.
int utf8Length(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit < 0x80) {
      n += 1;
    } else if (unit < 0x800) {
      n += 2;
    } else if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) {
      n += 4;
      i++;
    } else {
      n += 3;
    }
  }
  return n;
}

/// jq's integer limit: a repeated string whose UTF-8 length reaches it fails.
const int _intMax32 = 2147483647;

Object? multiply(Object? a, Object? b) {
  if (isNumber(a) && isNumber(b)) {
    return computed(numberValue(a) * numberValue(b));
  }
  if ((a is String && isNumber(b)) || (isNumber(a) && b is String)) {
    final text = a is String ? a : b! as String;
    final d = numberValue(a is String ? b : a);
    if (d.isNaN || d < 0) return null;
    final n = d > _intMax32 ? _intMax32 : d.toInt();
    // `len * n` never overflows a 64-bit integer; a double holds it exactly
    // enough for the comparison below on every target.
    if (utf8Length(text) * n >= _intMax32) {
      throw const JqError('Repeat string result too long');
    }
    if (n == 0 || text.isEmpty) return '';
    return text * n;
  }
  if (isObject(a) && isObject(b)) return mergeDeep(a, b);
  throw _binaryError(a, b, 'multiplied');
}

Object? divide(Object? a, Object? b) {
  if (isNumber(a) && isNumber(b)) {
    final y = numberValue(b);
    if (y == 0) {
      throw _binaryError(a, b, 'divided because the divisor is zero');
    }
    return computed(numberValue(a) / y);
  }
  if (a is String && b is String) {
    if (a.isEmpty) return JqArray(<Object?>[]);
    if (b.isEmpty) {
      return JqArray(<Object?>[
        for (final rune in a.runes) String.fromCharCode(rune),
      ]);
    }
    return JqArray(<Object?>[...a.split(b)]);
  }
  throw _binaryError(a, b, 'divided');
}

final BigInt _int64Max = BigInt.parse('9223372036854775807');
final BigInt _int64Min = BigInt.parse('-9223372036854775808');

/// jq's `dtoi`: clamp to the int64 range, truncating toward zero.
BigInt _dtoi(double n) {
  if (n < -9223372036854775808.0) return _int64Min;
  if (-n <= -9223372036854775808.0) return _int64Max;
  return BigInt.from(n.truncate());
}

Object? modulo(Object? a, Object? b) {
  if (!isNumber(a) || !isNumber(b)) {
    throw _binaryError(a, b, 'divided (remainder)');
  }
  final x = numberValue(a);
  final y = numberValue(b);
  if (x.isNaN || y.isNaN) return computed(double.nan);
  final divisor = _dtoi(y);
  if (divisor == BigInt.zero) {
    throw _binaryError(a, b, 'divided (remainder) because the divisor is zero');
  }
  if (divisor == BigInt.from(-1)) return computed(0);
  return computed(_dtoi(x).remainder(divisor).toDouble());
}

Object? negate(Object? v) {
  if (v is JqNumber) return v.negate();
  if (v is num) return computed(-v.toDouble());
  throw JqError('${describe(v)} cannot be negated');
}

// ---------------------------------------------------------------------------
// Indexing and slicing.

String _codePointSlice(String s, int start, int end) {
  // Fast path: no surrogate pairs, so code points are code units.
  var simple = true;
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDFFF) {
      simple = false;
      break;
    }
  }
  if (simple) {
    final length = s.length;
    return s.substring(
      start > length ? length : start,
      end > length ? length : end,
    );
  }
  final runes = s.runes.toList();
  final length = runes.length;
  final from = start > length ? length : start;
  final to = end > length ? length : end;
  return String.fromCharCodes(runes.sublist(from, to));
}

int _codePointCount(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) i++;
    n++;
  }
  return n;
}

({int start, int end}) _sliceBounds(int length, Object? from, Object? to) {
  if ((from != null && !isNumber(from)) || (to != null && !isNumber(to))) {
    throw const JqError('Array/string slice indices must be integers');
  }
  // Mirrors parse_slice in pinned jq 1.8.2 src/jv_aux.c: the start rounds
  // down, a still-negative end collapses to the integer start, and the end
  // rounds up only below the length.
  var dstart = from == null ? 0.0 : numberValue(from);
  var dend = to == null ? length.toDouble() : numberValue(to);
  if (dstart.isNaN) dstart = 0;
  if (dstart < 0) dstart += length;
  if (dstart < 0) dstart = 0;
  if (dstart > length) dstart = length.toDouble();
  final start = dstart.toInt();
  if (dend.isNaN) dend = length.toDouble();
  if (dend < 0) dend += length;
  if (dend < 0) dend = start.toDouble();
  var end = dend > length ? length : dend.toInt();
  if (end < length && end < dend) end++;
  if (end < start) end = start;
  return (start: start, end: end);
}

Object? _arrayIndexes(Object? a, Object? b) {
  final xs = arrayItems(a);
  final ys = arrayItems(b);
  final result = <Object?>[];
  for (var ai = 0; ai < xs.length; ai++) {
    var idx = -1;
    for (var bi = 0; bi < ys.length; bi++) {
      final other = ai + bi;
      if (other >= xs.length || !equalValues(xs[other], ys[bi])) {
        idx = -1;
      } else if (bi == 0 && idx == -1) {
        idx = ai;
      }
    }
    if (idx > -1) result.add(computed(idx.toDouble()));
  }
  return JqArray(result);
}

/// `jv_get`: `t[k]` for every key kind jq supports, including the slice
/// object `{"start": s, "end": e}` that the `.[s:e]` form builds.
Object? indexValue(Object? t, Object? k) {
  if (isObject(t) && k is String) return objectEntries(t)[k];
  if (isArray(t) && isNumber(k)) {
    final items = arrayItems(t);
    var d = numberValue(k);
    if (d.isNaN) return null;
    if (d < -2147483648) d = -2147483648;
    if (d > 2147483647) d = 2147483647;
    var index = d.truncate();
    if (index < 0) index += items.length;
    return index >= 0 && index < items.length ? items[index] : null;
  }
  if ((isArray(t) || t is String) && isObject(k)) {
    final map = objectEntries(k);
    if (!map.containsKey('start') || !map.containsKey('end')) {
      throw const JqError('Array/string slice indices must be integers');
    }
    final from = map['start'];
    final to = map['end'];
    if (t is String) {
      final length = _codePointCount(t);
      final bounds = _sliceBounds(length, from, to);
      return _codePointSlice(t, bounds.start, bounds.end);
    }
    final items = arrayItems(t);
    final bounds = _sliceBounds(items.length, from, to);
    return JqArray(items.sublist(bounds.start, bounds.end));
  }
  if (isArray(t) && isArray(k)) return _arrayIndexes(t, k);
  if (t == null && (k is String || isNumber(k) || isObject(k))) return null;
  throw JqError('Cannot index ${kindOf(t)} with ${describe(k)}');
}

// ---------------------------------------------------------------------------
// Strings.

/// `tostring`: a string is itself, anything else its compact JSON text.
String stringify(Object? v) => v is String ? v : printJson(v);

// ---------------------------------------------------------------------------
// Native ingestion.

bool _isExactNative(num value) =>
    value is! int || (value >= -9007199254740992 && value <= 9007199254740992);

final class _IngestFrame {
  _IngestFrame.array(this.source, this.list) : isObject = false, entries = null;

  _IngestFrame.object(this.source, Map<Object?, Object?> map)
    : isObject = true,
      list = null,
      entries = map.entries.toList();

  final Object source;
  final bool isObject;
  final List<Object?>? list;
  final List<MapEntry<Object?, Object?>>? entries;
  int index = 0;

  /// Rebuilt children, created at the first changed child.
  List<Object?>? rebuiltItems;
  Map<String, Object?>? rebuiltMap;

  /// For an object: the normalized key of the child being processed.
  String? pendingKey;

  int get length => isObject ? entries!.length : list!.length;
}

/// Converts a caller's public value into an engine value.
///
/// Public-compatible subtrees (nothing but `null`, `bool`, normalized strings,
/// exactly representable `num`, and containers of those) are returned by
/// reference. A subtree that has to change, because it contains a
/// `ZaruNumber`, a string or key with a lone surrogate, a map key collision
/// after normalization, or an integer binary64 cannot hold, is rebuilt along
/// the changed path only into an owned [JqArray]/[JqObject]. Unsupported data
/// throws [ArgumentError].
Object? ingest(Object? root) {
  final stack = <_IngestFrame>[];

  // Scalars return the (possibly replaced) value; containers push a frame and
  // return the [_pending] marker.
  Object? start(Object? v) {
    if (v == null || v is bool) return v;
    if (v is String) return normalizeString(v);
    if (v is num) {
      if (_isExactNative(v)) return v;
      final n = JqNumber.fromNative(v);
      return n.isLiteral ? n : v;
    }
    if (v is ZaruNumber) return JqNumber.fromZaru(v);
    if (v is List<Object?>) {
      stack.add(_IngestFrame.array(v, v));
      return _pending;
    }
    if (v is Map<Object?, Object?>) {
      stack.add(_IngestFrame.object(v, v));
      return _pending;
    }
    throw ArgumentError.value(
      v,
      'value',
      'Not a JSON-shaped value (${v.runtimeType})',
    );
  }

  var result = start(root);
  if (!identical(result, _pending)) return result;
  while (true) {
    final frame = stack.last;
    if (frame.index == frame.length) {
      stack.removeLast();
      final Object? finished;
      if (frame.isObject) {
        final rebuilt = frame.rebuiltMap;
        finished = rebuilt == null ? frame.source : JqObject(rebuilt);
      } else {
        final rebuilt = frame.rebuiltItems;
        finished = rebuilt == null ? frame.source : JqArray(rebuilt);
      }
      if (stack.isEmpty) return finished;
      _accept(stack.last, finished);
      continue;
    }
    final i = frame.index++;
    final Object? child;
    if (frame.isObject) {
      final entry = frame.entries![i];
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(
          key,
          'value',
          'Object keys must be strings (${key.runtimeType})',
        );
      }
      final normalized = normalizeString(key);
      frame.pendingKey = normalized;
      if (!identical(normalized, key) && frame.rebuiltMap == null) {
        _beginMap(frame, i);
      }
      child = entry.value;
    } else {
      child = frame.list![i];
    }
    final value = start(child);
    if (!identical(value, _pending)) _accept(frame, value);
  }
}

const Object _pending = _Pending();

final class _Pending {
  const _Pending();
}

void _beginMap(_IngestFrame frame, int upTo) {
  final rebuilt = <String, Object?>{};
  for (var j = 0; j < upTo; j++) {
    final e = frame.entries![j];
    rebuilt[e.key! as String] = e.value;
  }
  frame.rebuiltMap = rebuilt;
}

/// Records [value], the result for the child at `frame.index - 1`.
void _accept(_IngestFrame frame, Object? value) {
  final i = frame.index - 1;
  if (frame.isObject) {
    final changed = !identical(value, frame.entries![i].value);
    var rebuilt = frame.rebuiltMap;
    if (rebuilt == null && changed) {
      _beginMap(frame, i);
      rebuilt = frame.rebuiltMap;
    }
    rebuilt?[frame.pendingKey!] = value;
  } else {
    final changed = !identical(value, frame.list![i]);
    var rebuilt = frame.rebuiltItems;
    if (rebuilt == null && changed) {
      rebuilt = frame.list!.sublist(0, i);
      frame.rebuiltItems = rebuilt;
    }
    rebuilt?.add(value);
  }
}

// ---------------------------------------------------------------------------
// Public projection.

final class _ExportFrame {
  _ExportFrame(this.node, this.isObject, this.length, this.keys);

  final Object node;
  final bool isObject;
  final int length;
  final List<String>? keys;
  final List<Object?> out = [];
  int index = 0;
}

/// Narrows an engine value to the public JSON-shaped domain.
///
/// Numbers become `int`, `double` or `ZaruNumber` per `JqNumber.export`.
/// Each owned container creates its immutable public projection once and
/// remembers it on the node, so a repeated subtree exports to the identical
/// object; unchanged native containers pass through by reference.
Object? exportValue(Object? value) {
  if (value is JqNumber) return value.export();
  if (value is! JqArray && value is! JqObject) return value;
  final cached = value is JqArray
      ? value.projection
      : (value as JqObject).projection;
  if (cached != null) return cached;

  _ExportFrame open(Object node) {
    if (node is JqArray) return _ExportFrame(node, false, node.length, null);
    final object = node as JqObject;
    return _ExportFrame(
      object,
      true,
      object.length,
      object.entries.keys.toList(),
    );
  }

  final stack = <_ExportFrame>[open(value!)];
  Object? finished;
  while (true) {
    final frame = stack.last;
    if (frame.index == frame.length) {
      final node = frame.node;
      if (node is JqArray) {
        finished = node.projection = UnmodifiableListView<Object?>(frame.out);
      } else {
        final object = node as JqObject;
        final map = <String, Object?>{};
        for (var i = 0; i < frame.length; i++) {
          map[frame.keys![i]] = frame.out[i];
        }
        finished = object.projection = UnmodifiableMapView<String, Object?>(
          map,
        );
      }
      stack.removeLast();
      if (stack.isEmpty) return finished;
      stack.last.out.add(finished);
      continue;
    }
    final i = frame.index++;
    final child = frame.isObject
        ? (frame.node as JqObject).entries[frame.keys![i]]
        : (frame.node as JqArray).items[i];
    if (child is JqNumber) {
      frame.out.add(child.export());
    } else if (child is JqArray || child is JqObject) {
      final memo = child is JqArray
          ? child.projection
          : (child as JqObject).projection;
      if (memo != null) {
        frame.out.add(memo);
      } else {
        stack.add(open(child!));
      }
    } else {
      frame.out.add(child);
    }
  }
}
