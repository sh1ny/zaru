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
  final prefix = diagnostic.kind == DiagnosticKind.unsupported
      ? 'zaru: unsupported: '
      : 'jq: error: ';
  final span = diagnostic.span;
  if (span.isUnknown) return '$prefix${diagnostic.message}';
  final line = source.lineOf(span.start);
  final lineStart = source.lineStart(line);
  final lineEnd = source.lineEnd(line);
  final limit = lineEnd > span.start + 1 ? lineEnd : span.start + 1;
  final end = span.end < limit ? span.end : limit;
  final carets = '^' * (end - span.start);
  return '$prefix${diagnostic.message} at ${source.name}, '
      'line ${line + 1}, column ${span.start - lineStart + 1}:\n'
      '    ${source.slice(lineStart, lineEnd)}\n'
      '    ${carets.padLeft(end - lineStart)}';
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
    rendered = List.unmodifiable([
      for (final diagnostic in this.diagnostics)
        renderDiagnostic(source, diagnostic),
    ]);
  }

  final SourceText source;
  final List<Diagnostic> diagnostics;

  /// Every diagnostic rendered as a jq block, in report order.
  late final List<String> rendered;

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
