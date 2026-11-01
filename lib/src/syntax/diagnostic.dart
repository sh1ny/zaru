import 'source_text.dart';
import 'span.dart';

/// Why a diagnostic was produced.
///
/// The categories are deliberately distinct (design D3): an [unsupported]
/// diagnostic describes valid jq that this milestone does not implement and
/// must never be mistaken for, or satisfy, a jq compile error.
enum DiagnosticKind {
  /// A lexer-level error such as an invalid string escape.
  lexical,

  /// A grammar error reported by the parser, including recovery productions
  /// such as `May need parentheses around object key expression`.
  syntax,

  /// A jq semantic compile error with a source span, such as a constant
  /// object key of the wrong type.
  semantic,

  /// Valid jq syntax whose semantics are deferred to a later milestone.
  unsupported,

  /// A zaru resource bound was exceeded, such as the syntax depth budget.
  /// jq has no such diagnostic, so it renders with a `zaru: error:` prefix
  /// and can never match jq's `jq: error` callback filter.
  limit,
}

/// One compile diagnostic: a category, jq's message text and a byte span.
final class Diagnostic {
  const Diagnostic(this.kind, this.message, this.span);

  final DiagnosticKind kind;

  /// The message exactly as jq composes it, without the `jq: error:` prefix
  /// and without the `at <top-level>, line N, column M:` suffix.
  final String message;

  /// UTF-8 byte span with an exclusive end.
  final Span span;

  @override
  bool operator ==(Object other) =>
      other is Diagnostic &&
      other.kind == kind &&
      other.message == message &&
      other.span == span;

  @override
  int get hashCode => Object.hash(kind, message, span);

  @override
  String toString() => 'Diagnostic($kind, $message, $span)';
}

/// The most text a [DiagnosticReport] renders, as the sum of the lengths of
/// its blocks (about one megabyte of ASCII).
///
/// jq renders every diagnostic in full; with the whole source line in every
/// block, a one-line filter of 70 KB with 10000 diagnostics would retain over
/// a billion characters. After this budget the remaining diagnostics are
/// counted in one summary block instead. Reports below it render as jq does.
const int maxRenderedDiagnosticBytes = 1024 * 1024;

/// The longest source excerpt a block shows, in bytes. A longer line is cut
/// to a window of this size around the span, with `...` marking each cut end.
/// Lines up to this length are rendered whole, exactly as jq does.
const int maxExcerptBytes = 240;

/// The prefix jq's error callback looks for when it selects a diagnostic.
const String jqErrorPrefix = 'jq: error';

/// Renders [diagnostic] against [source] the way pinned jq's
/// `locfile_locate` does.
///
/// The block is `jq: error: MESSAGE at NAME, line L, column C:` followed by a
/// four-space-indented excerpt of the first line of the span and a caret line
/// whose carets cover the span's bytes on that line, with jq's `%*s`
/// right-justification. Unsupported-construct diagnostics use the
/// `zaru: unsupported:` prefix instead, so that no rendered block of that
/// category can match jq's `jq: error` callback filter.
String renderDiagnostic(SourceText source, Diagnostic diagnostic) {
  final prefix = switch (diagnostic.kind) {
    DiagnosticKind.unsupported => 'zaru: unsupported: ',
    DiagnosticKind.limit => 'zaru: error: ',
    _ => 'jq: error: ',
  };
  final span = diagnostic.span;
  if (span.isUnknown) return '$prefix${diagnostic.message}';
  final line = source.lineOf(span.start);
  final lineStart = source.lineStart(line);
  final lineEnd = source.lineEnd(line);
  final limit = lineEnd > span.start + 1 ? lineEnd : span.start + 1;
  final end = span.end < limit ? span.end : limit;
  final header =
      '$prefix${diagnostic.message} at ${source.name}, '
      'line ${line + 1}, column ${span.start - lineStart + 1}:';
  if (lineEnd - lineStart <= maxExcerptBytes) {
    final carets = '^' * (end - span.start);
    return '$header\n'
        '    ${source.slice(lineStart, lineEnd)}\n'
        '    ${carets.padLeft(end - lineStart)}';
  }

  // A long line: show a window that starts a third of its width before the
  // span, shifted left when the span is near the end of the line, and never
  // splitting a UTF-8 sequence.
  var from = span.start - maxExcerptBytes ~/ 3;
  if (from < lineStart) from = lineStart;
  var to = from + maxExcerptBytes;
  if (to > lineEnd) {
    to = lineEnd;
    from = to - maxExcerptBytes;
    if (from < lineStart) from = lineStart;
  }
  final bytes = source.bytes;
  while (from < to && (bytes[from] & 0xc0) == 0x80) {
    from++;
  }
  while (to < lineEnd && to > from && (bytes[to] & 0xc0) == 0x80) {
    to--;
  }
  final head = from > lineStart ? '...' : '';
  final tail = to < lineEnd ? '...' : '';
  final shownEnd = end < to ? end : to;
  final carets = '^' * (shownEnd - span.start);
  return '$header\n'
      '    $head${source.slice(from, to)}$tail\n'
      '    ${' ' * (head.length + span.start - from)}$carets';
}

/// An ordered, immutable list of diagnostics for one source.
///
/// The typed fields describe the **first** diagnostic. [rendered] holds every
/// block in report order; a consumer that mimics jq's test callback selects
/// the last block starting with [jqErrorPrefix].
final class DiagnosticReport {
  DiagnosticReport(this.source, Iterable<Diagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics) {
    if (this.diagnostics.isEmpty) {
      throw ArgumentError.value(
        diagnostics,
        'diagnostics',
        'must not be empty',
      );
    }
  }

  final SourceText source;
  final List<Diagnostic> diagnostics;

  /// The diagnostics rendered as jq blocks, in report order, up to the
  /// [maxRenderedDiagnosticBytes] budget; the first block is always present.
  ///
  /// When the budget runs out, rendering stops and one final
  /// `zaru: error: N more diagnostics omitted` block counts the rest. That
  /// block does not start with [jqErrorPrefix]. [diagnostics] stays complete.
  late final List<String> rendered = _render();

  List<String> _render() {
    final blocks = <String>[];
    var total = 0;
    for (var i = 0; i < diagnostics.length; i++) {
      final block = renderDiagnostic(source, diagnostics[i]);
      if (i > 0 && total + block.length > maxRenderedDiagnosticBytes) {
        blocks.add(
          'zaru: error: ${diagnostics.length - i} more diagnostics omitted',
        );
        break;
      }
      blocks.add(block);
      total += block.length;
    }
    return List.unmodifiable(blocks);
  }

  Diagnostic get first => diagnostics.first;

  /// First diagnostic's message without prefix or location.
  String get message => first.message;

  /// One-based line of the first diagnostic's start.
  int get line => source.lineNumber(first.span.start);

  /// One-based UTF-8 byte column of the first diagnostic's start.
  int get column => source.columnNumber(first.span.start);

  /// One-based line of the first diagnostic's exclusive end.
  int get endLine => source.lineNumber(first.span.end);

  /// One-based UTF-8 byte column of the first diagnostic's exclusive end.
  int get endColumn => source.columnNumber(first.span.end);

  /// The block jq's test callback retains: the last [rendered] block that
  /// starts with [jqErrorPrefix], or `null` when none does.
  String? get lastJqError {
    for (var i = rendered.length - 1; i >= 0; i--) {
      if (rendered[i].startsWith(jqErrorPrefix)) return rendered[i];
    }
    return null;
  }
}
