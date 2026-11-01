/// A compiled, reusable jq filter and its lazy result streams.
library;

import 'dart:collection';

import 'engine/compiler.dart';
import 'engine/machine.dart';
import 'engine/values.dart';
import 'errors.dart';
import 'json_decoder.dart';

/// A compiled jq filter.
///
/// A filter is immutable and reusable. Every call to [run] or [runJson]
/// returns a lazy [Iterable]; nothing is evaluated until it is iterated, and
/// each `iterator` owns its complete execution state, so iterators over the
/// same filter (or the same iterable) never share variables, continuations or
/// results. A result stream is pulled: stopping early never evaluates the rest.
///
/// A jq data error is thrown by `moveNext` as a [ZaruRuntimeError] after the
/// results that preceded it; the iterator that threw reports `false` from then
/// on. A declared variable without a value throws
/// [ZaruMissingArgumentError] from the first `moveNext`; a value or input the
/// engine cannot interpret throws [ArgumentError]; malformed `runJson` text
/// throws [FormatException]. All of these precede any filter output.
final class ZaruFilter {
  ZaruFilter.internal(this._program);

  final CompiledProgram _program;

  /// Runs the filter on a native JSON-shaped [input].
  ///
  /// [input] and the values of [args] may be `null`, `bool`, `String`, `num`,
  /// [ZaruNumber]-compatible numbers, `List`s and `Map`s with `String` keys.
  /// The engine reads them lazily and never changes them. A value that is
  /// already public-compatible (including every container whose subtree is) is
  /// passed through by reference, so a result may be the very object the
  /// caller supplied; mutating caller data while a stream is being consumed
  /// is not a supported way to observe different results.
  Iterable<Object?> run(
    Object? input, {
    Map<String, Object?> args = const {},
  }) => _Results(_program, input, args, isJson: false);

  /// Runs the filter on exactly one JSON value given as [text].
  ///
  /// The text is decoded with jq's rules when the first `moveNext` occurs,
  /// keeping the literal precision of every number for the whole run.
  Iterable<Object?> runJson(
    String text, {
    Map<String, Object?> args = const {},
  }) => _Results(_program, text, args, isJson: true);
}

final class _Results extends IterableBase<Object?> {
  _Results(this._program, this._input, this._args, {required this.isJson});

  final CompiledProgram _program;
  final Object? _input;
  final Map<String, Object?> _args;
  final bool isJson;

  @override
  Iterator<Object?> get iterator =>
      _ResultIterator(_program, _input, _args, isJson: isJson);
}

final class _ResultIterator implements Iterator<Object?> {
  _ResultIterator(
    this._program,
    this._input,
    this._args, {
    required this.isJson,
  });

  final CompiledProgram _program;
  final Object? _input;
  final Map<String, Object?> _args;
  final bool isJson;

  Machine? _machine;
  bool _done = false;
  Object? _current;

  @override
  Object? get current => _current;

  @override
  bool moveNext() {
    if (_done) return false;
    try {
      final machine = _machine ??= _start();
      if (machine.advance()) {
        _current = exportValue(machine.output);
        return true;
      }
    } on Object {
      _finish();
      rethrow;
    }
    _finish();
    return false;
  }

  void _finish() {
    _done = true;
    _current = null;
    _machine = null;
  }

  Machine _start() {
    Env? env;
    for (final name in _program.declared) {
      if (!_args.containsKey(name)) throw ZaruMissingArgumentError(name);
    }
    final values = [for (final name in _program.declared) ingest(_args[name])];
    final input = isJson ? decodeJqJson(_input! as String) : ingest(_input);
    for (final value in values) {
      env = Env(value, env);
    }
    return Machine(_program.root, input, env);
  }
}
