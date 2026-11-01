import 'engine/compiler.dart';
import 'filter.dart';
import 'json_printer.dart';

/// Entry points of the zaru jq engine.
abstract final class Zaru {
  /// Compiles jq [source] into a reusable [ZaruFilter].
  ///
  /// [variables] declares the external variables (`$name`, written without the
  /// `$`) the filter may reference; their values are supplied per run through
  /// `args`. Throws a `ZaruCompileError` for invalid jq, for an undefined
  /// variable, function or label, and (with `isUnsupported` set) for valid jq
  /// that this release does not implement.
  static ZaruFilter compile(
    String source, {
    Set<String> variables = const {},
  }) => ZaruFilter.internal(compileSource(source, variables));

  /// Prints [value] as jq-compatible JSON text. See `printJson`.
  static String toJson(
    Object? value, {
    bool compact = true,
    bool sortKeys = false,
    String indent = '  ',
  }) => printJson(value, compact: compact, sortKeys: sortKeys, indent: indent);
}
