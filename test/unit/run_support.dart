import 'package:zaru/zaru.dart';

/// Compiles [filter], runs it on JSON [input] text with `runJson`, and prints
/// every result compactly. Evaluation errors propagate.
List<String> jsonOutputs(
  String filter,
  String input, {
  Set<String> variables = const {},
  Map<String, Object?> args = const {},
}) => [
  for (final value in Zaru.compile(
    filter,
    variables: variables,
  ).runJson(input, args: args))
    Zaru.toJson(value),
];

/// Like [jsonOutputs] but over a native [input] value.
List<String> nativeOutputs(
  String filter,
  Object? input, {
  Set<String> variables = const {},
  Map<String, Object?> args = const {},
}) => [
  for (final value in Zaru.compile(
    filter,
    variables: variables,
  ).run(input, args: args))
    Zaru.toJson(value),
];

/// The outputs before the first error, and the error (if any) that ended
/// the stream.
({List<String> values, Object? error}) outputsAndError(
  Iterable<Object?> results,
) {
  final values = <String>[];
  try {
    for (final value in results) {
      values.add(Zaru.toJson(value));
    }
  } on Object catch (error) {
    return (values: values, error: error);
  }
  return (values: values, error: null);
}

/// The error value of the first runtime error, or fail.
Object? runtimeErrorValue(Iterable<Object?> results) {
  try {
    for (final _ in results) {}
  } on ZaruRuntimeError catch (error) {
    return error.value;
  }
  throw StateError('expected a ZaruRuntimeError');
}
