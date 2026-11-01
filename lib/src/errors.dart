/// Public error types of the compile and run APIs.
library;

import 'json_printer.dart';

/// A filter could not be compiled.
///
/// The scalar fields describe the **first** diagnostic. [line], [col],
/// [endLine] and [endCol] are one-based and count UTF-8 bytes, with an
/// exclusive end, exactly as jq reports locations. [diagnostics] holds every
/// rendered block in report order: a `jq: error: ...` line that names the
/// location as `at <top-level>, line L, column C:`, followed by a
/// four-space-indented excerpt and carets. A consumer that mimics jq's test
/// callback keeps the last block that starts with `jq: error`.
///
/// An error with [isUnsupported] set is not a jq compile error: the source is
/// valid jq (or uses a built-in jq defines) that this release does not
/// implement yet. Its blocks start with `zaru: unsupported:`, so they can
/// never be mistaken for a jq diagnostic or satisfy an expected compile error.
final class ZaruCompileError implements Exception {
  ZaruCompileError({
    required this.message,
    required this.line,
    required this.col,
    required this.endLine,
    required this.endCol,
    required Iterable<String> diagnostics,
    this.isUnsupported = false,
  }) : diagnostics = List.unmodifiable(diagnostics);

  /// The first diagnostic's message, without prefix or location.
  final String message;

  /// One-based line of the first diagnostic's start (0 when unlocated).
  final int line;

  /// One-based UTF-8 byte column of the first diagnostic's start.
  final int col;

  /// One-based line of the first diagnostic's exclusive end.
  final int endLine;

  /// One-based UTF-8 byte column of the first diagnostic's exclusive end.
  final int endCol;

  /// Every diagnostic rendered as jq would, in report order.
  final List<String> diagnostics;

  /// Whether the failure is an unimplemented construct rather than a jq
  /// compile error.
  final bool isUnsupported;

  @override
  String toString() => 'ZaruCompileError: ${diagnostics.join('\n')}';
}

/// A jq data error raised while a result stream was being consumed.
///
/// [value] is the jq error value (the argument of `error`); it is `null` for
/// `error(null)`. Results yielded before the failure stay observed, and the
/// iterator that threw is terminal afterwards.
final class ZaruRuntimeError implements Exception {
  ZaruRuntimeError(this.value);

  /// The jq error value in its public form.
  final Object? value;

  /// The text jq prints after `jq: error (at <unknown>):`.
  String get message {
    final v = value;
    if (v is String) return v;
    return '${printJson(v)} (not a string)';
  }

  @override
  String toString() => 'ZaruRuntimeError: $message';
}

/// A declared external variable had no value in the `args` of a run.
///
/// Raised on the iterator's first `moveNext`, before any filter output.
final class ZaruMissingArgumentError implements Exception {
  ZaruMissingArgumentError(this.name);

  /// The declared variable name, without `$`.
  final String name;

  @override
  String toString() =>
      'ZaruMissingArgumentError: no value was supplied for the declared '
      'variable \$$name';
}
