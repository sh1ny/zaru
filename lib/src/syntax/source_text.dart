import 'dart:convert';
import 'dart:typed_data';

import 'span.dart';

/// jq source text addressed by UTF-8 byte offsets.
///
/// jq's lexer, locations and diagnostics all operate on bytes, so every
/// [Span] produced by this library is a byte range of [bytes]. Lone UTF-16
/// surrogates in [text] are encoded as U+FFFD, like any other invalid scalar.
final class SourceText {
  SourceText(this.text, {this.name = '<top-level>'})
    : bytes = Uint8List.fromList(utf8.encode(text)) {
    final starts = <int>[0];
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0a) starts.add(i + 1);
    }
    _lineStarts = starts;
  }

  /// The original Dart string.
  final String text;

  /// How locations name this source (jq uses `<top-level>`).
  final String name;

  /// The UTF-8 encoding of [text].
  final Uint8List bytes;

  late final List<int> _lineStarts;

  int get length => bytes.length;

  /// Number of lines: one more than the number of `\n` bytes.
  int get lineCount => _lineStarts.length;

  /// The zero-based line containing byte [offset].
  ///
  /// Offsets at or beyond the end resolve to the last line.
  int lineOf(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// The byte offset at which zero-based [line] starts.
  int lineStart(int line) => _lineStarts[line];

  /// The byte offset just after the last content byte of [line], excluding
  /// its `\n`.
  int lineEnd(int line) =>
      line + 1 < _lineStarts.length ? _lineStarts[line + 1] - 1 : length;

  /// One-based line of [offset].
  int lineNumber(int offset) => lineOf(offset) + 1;

  /// One-based byte column of [offset] on its line.
  int columnNumber(int offset) => offset - _lineStarts[lineOf(offset)] + 1;

  /// Decodes bytes `[start, end)` leniently.
  String slice(int start, int end) =>
      utf8.decode(bytes.sublist(start, end), allowMalformed: true);
}
