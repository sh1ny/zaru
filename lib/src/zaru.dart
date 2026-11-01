import 'json_printer.dart';

abstract final class Zaru {
  static String toJson(
    Object? value, {
    bool compact = true,
    bool sortKeys = false,
    String indent = '  ',
  }) => printJson(value, compact: compact, sortKeys: sortKeys, indent: indent);
}
