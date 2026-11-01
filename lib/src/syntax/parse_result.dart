import 'ast.dart';
import 'diagnostic.dart';
import 'source_text.dart';
import 'span.dart';

/// Valid jq syntax whose semantics are not part of the current milestone.
enum UnsupportedKind {
  /// `module metadata;`
  moduleDirective('module directive'),

  /// `import "path" as name;`
  importDirective('import directive'),

  /// `include "path";`
  includeDirective('include directive'),

  /// An explicit `@format` filter or format-prefixed string.
  format('format operation'),

  /// `$__loc__`
  locationBinding(r'$__loc__'),

  /// `=`, `|=`, `+=`, `-=`, `*=`, `/=`, `%=` or `//=`.
  assignment('assignment or update operator'),

  /// A module-qualified name such as `ns::name` or `$ns::name`.
  qualifiedName('module-qualified name'),

  /// `..`
  recursiveDescent('recursive descent'),

  /// A builtin that jq defines and this release does not implement yet.
  builtin('jq builtin'),

  /// `$ENV`
  environment(r'$ENV');

  const UnsupportedKind(this.description);

  final String description;
}

/// A recognized-but-deferred construct and where it occurs.
///
/// This is not a jq compile error: it must never satisfy an expected
/// compile-error fixture, and it is reported distinctly from semantic
/// failures.
final class UnsupportedConstruct {
  const UnsupportedConstruct(this.kind, this.span, [this.detail]);

  final UnsupportedKind kind;
  final Span span;

  /// The offending operator, format or name, when there is one.
  final String? detail;

  /// A message that names the construct.
  String get message =>
      'unsupported ${kind.description}${detail == null ? '' : ' $detail'}';

  /// The construct as a [DiagnosticKind.unsupported] diagnostic.
  Diagnostic toDiagnostic() =>
      Diagnostic(DiagnosticKind.unsupported, message, span);
}

/// The outcome of parsing one jq program.
///
/// [program] is present only when no jq error was reported. Recognized
/// deferred syntax appears in [unsupported] regardless of [program].
final class ParseResult {
  ParseResult({
    required this.source,
    required this.program,
    required List<Diagnostic> diagnostics,
    required List<UnsupportedConstruct> unsupported,
  }) : diagnostics = List.unmodifiable(diagnostics),
       unsupported = List.unmodifiable(unsupported);

  final SourceText source;
  final Program? program;

  /// jq compile errors in report order; empty when the source parsed.
  final List<Diagnostic> diagnostics;
  final List<UnsupportedConstruct> unsupported;

  bool get isValid => diagnostics.isEmpty;

  /// Ordered rendered diagnostics and first-diagnostic fields, or `null`
  /// when the source parsed without a jq error.
  DiagnosticReport? get report =>
      diagnostics.isEmpty ? null : DiagnosticReport(source, diagnostics);
}
