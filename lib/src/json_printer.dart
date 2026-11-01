/// The jq-compatible JSON printer behind `Zaru.toJson`.
///
/// Iterative, so nesting never consumes host stack. Like jq's `jv_dump`, the
/// root is at depth zero and a value deeper than 10000 is not visited: the
/// unquoted text `<skipped: too deep>` is printed in its place. That output
/// is deliberately not valid JSON.
library;

import 'number.dart';
import 'unicode.dart';
import 'value.dart';

const int _maxPrintDepth = 10000;
const String _tooDeep = '<skipped: too deep>';

/// Prints [value] as JSON text.
///
/// Accepts the public JSON-shaped domain (null, bool, String, int, double,
/// `ZaruNumber`, List, and Map with String keys) as well as the private value
/// domain. Anything else throws [ArgumentError], as does a map with a
/// non-String key; only visited values are inspected.
String printJson(
  Object? value, {
  bool compact = true,
  bool sortKeys = false,
  String indent = '  ',
}) {
  final out = StringBuffer();
  final stack = <_Frame>[];

  void newline(int depth) {
    out.write('\n');
    for (var i = 0; i < depth; i++) {
      out.write(indent);
    }
  }

  // Begins a value; containers push a frame, scalars are written at once.
  void begin(Object? v) {
    if (stack.length > _maxPrintDepth) {
      out.write(_tooDeep);
      return;
    }
    if (v == null) {
      out.write('null');
    } else if (v is bool) {
      out.write(v ? 'true' : 'false');
    } else if (v is String) {
      _writeString(out, v);
    } else if (v is num) {
      out.write(nativeNumberText(v));
    } else if (v is JqNumber) {
      out.write(v.text);
    } else if (v is ZaruNumber) {
      out.write(v.literal);
    } else if (v is JqArray) {
      _openArray(out, stack, v.items);
    } else if (v is List<Object?>) {
      _openArray(out, stack, v);
    } else if (v is JqObject) {
      _openObject(out, stack, v.entries, sortKeys);
    } else if (v is Map<Object?, Object?>) {
      _openObject(out, stack, v, sortKeys);
    } else {
      throw ArgumentError.value(
        v,
        'value',
        'Not a JSON-shaped value (${v.runtimeType})',
      );
    }
  }

  begin(value);
  while (stack.isNotEmpty) {
    final frame = stack.last;
    if (frame.index == frame.count) {
      stack.removeLast();
      if (frame.count > 0 && !compact) newline(stack.length);
      out.write(frame.isObject ? '}' : ']');
      continue;
    }
    if (frame.index > 0) out.write(',');
    if (!compact) newline(stack.length);
    final i = frame.index++;
    if (frame.isObject) {
      _writeString(out, frame.keys![i]);
      out.write(compact ? ':' : ': ');
    }
    begin(frame.values[i]);
  }
  return out.toString();
}

final class _Frame {
  _Frame.array(this.values) : isObject = false, keys = null;

  _Frame.object(this.keys, this.values) : isObject = true;

  final bool isObject;
  final List<String>? keys;
  final List<Object?> values;
  int index = 0;

  int get count => values.length;
}

void _openArray(StringBuffer out, List<_Frame> stack, List<Object?> items) {
  out.write('[');
  stack.add(_Frame.array(items));
}

void _openObject(
  StringBuffer out,
  List<_Frame> stack,
  Map<Object?, Object?> source,
  bool sortKeys,
) {
  out.write('{');
  // Keys that normalize to the same text collapse: first position, last value.
  final merged = <String, Object?>{};
  for (final entry in source.entries) {
    final key = entry.key;
    if (key is! String) {
      throw ArgumentError.value(
        key,
        'value',
        'Object keys must be strings (${key.runtimeType})',
      );
    }
    merged[normalizeString(key)] = entry.value;
  }
  final keys = merged.keys.toList();
  if (sortKeys) keys.sort(compareUtf8Order);
  stack.add(_Frame.object(keys, [for (final key in keys) merged[key]]));
}

const String _hex = '0123456789abcdef';

void _writeString(StringBuffer out, String s) {
  out.write('"');
  final n = s.length;
  var start = 0;
  for (var i = 0; i < n; i++) {
    final unit = s.codeUnitAt(i);
    String? replacement;
    switch (unit) {
      case 0x22:
        replacement = r'\"';
      case 0x5C:
        replacement = r'\\';
      case 0x08:
        replacement = r'\b';
      case 0x09:
        replacement = r'\t';
      case 0x0A:
        replacement = r'\n';
      case 0x0C:
        replacement = r'\f';
      case 0x0D:
        replacement = r'\r';
      default:
        if (unit < 0x20 || unit == 0x7F) {
          replacement = '\\u00${_hex[(unit >> 4) & 0xF]}${_hex[unit & 0xF]}';
        } else if (unit >= 0xD800 && unit <= 0xDFFF) {
          if (unit <= 0xDBFF &&
              i + 1 < n &&
              s.codeUnitAt(i + 1) >= 0xDC00 &&
              s.codeUnitAt(i + 1) <= 0xDFFF) {
            i++;
            continue;
          }
          replacement = '�';
        }
    }
    if (replacement != null) {
      out.write(s.substring(start, i));
      out.write(replacement);
      start = i + 1;
    }
  }
  out.write(s.substring(start));
  out.write('"');
}
