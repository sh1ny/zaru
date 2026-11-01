// Executes one fixture with the real compiler and engine and judges it.
//
// Browser-safe: no dart:io, no native jq. The judgement mirrors the pinned
// `src/jq_test.c` where jq decides acceptance, and is stricter exactly where
// the frozen census records a typed termination.
import 'dart:convert';

import 'package:zaru/zaru.dart';

import '../conformance/fixtures.dart';
import 'conformance_baseline.dart';
import 'fixture_oracle.dart';

/// The outcome class of one case.
enum CaseStatus { passed, failed, unsupported, notRun }

/// An observed verdict for one case.
final class CaseVerdict {
  const CaseVerdict(this.status, this.termination, [this.reason, this.detail]);

  final CaseStatus status;
  final Termination termination;

  /// Stable reason code for every non-pass.
  final String? reason;

  /// Human-readable evidence for a non-pass.
  final String? detail;
}

/// jq_test.c's `struct err_data` holds 4096 bytes including the terminator.
const _errorBufferBytes = 4095;

/// The message jq_test.c's `test_err_cb` would have retained: the last
/// diagnostic block starting with `jq: error`, cut to its 4096-byte buffer.
///
/// A cut that would split a UTF-8 sequence drops the partial character.
String? selectJqError(Iterable<String> diagnostics) {
  String? selected;
  for (final block in diagnostics) {
    if (block.startsWith('jq: error')) selected = block;
  }
  if (selected == null) return null;
  final bytes = utf8.encode(selected);
  if (bytes.length <= _errorBufferBytes) return selected;
  var end = _errorBufferBytes;
  // Back up over continuation bytes so the cut lands on a character boundary.
  while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}

/// jq_test.c's expected-line policy: each expected line must be a byte prefix
/// of what remains of the actual message, after which at most one newline is
/// consumed; nothing may remain at the end.
bool diagnosticMatches(List<String> expectedLines, String? actual) {
  final bytes = utf8.encode(actual ?? '');
  var position = 0;
  for (final line in expectedLines) {
    final expected = utf8.encode(line);
    if (position + expected.length > bytes.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (bytes[position + i] != expected[i]) return false;
    }
    position += expected.length;
    if (position < bytes.length && bytes[position] == 0x0A) position++;
  }
  return position == bytes.length;
}

CaseVerdict _failed(
  String reason,
  String detail, [
  Termination termination = Termination.notObserved,
]) => CaseVerdict(CaseStatus.failed, termination, reason, _clip(detail));

String _clip(String text) =>
    text.length <= 400 ? text : '${text.substring(0, 400)}...';

/// Compiles and runs [fixture] and compares it with [expectation].
///
/// Never throws: every host failure of the engine is a recorded non-pass.
CaseVerdict runFixture(JqFixture fixture, ReferenceExpectation expectation) {
  if (!fixture.isRunnable) {
    return _failed(
      'nonRunnableFixture',
      fixture.problems.map((problem) => problem.name).join(', '),
    );
  }
  if (fixture.kind != expectation.kind) {
    return _failed(
      'baselineMismatch',
      'fixture is ${fixture.kind.name}, reference is ${expectation.kind.name}',
    );
  }
  final ZaruFilter filter;
  try {
    filter = Zaru.compile(fixture.program);
  } on ZaruCompileError catch (error) {
    return _compileFailure(fixture, error);
  } on Object catch (error) {
    return _failed('hostException', 'compile: $error');
  }
  if (fixture.kind == FixtureKind.compileError) {
    return _failed(
      'compiledSuccessfully',
      'the program compiled but jq rejects it',
    );
  }
  return _execute(fixture, expectation, filter);
}

CaseVerdict _compileFailure(JqFixture fixture, ZaruCompileError error) {
  if (error.isUnsupported) {
    // An unsupported construct never satisfies an expected compile error,
    // whatever the fixture's message policy.
    return CaseVerdict(
      CaseStatus.unsupported,
      Termination.compileError,
      'unsupportedConstruct',
      _clip(error.diagnostics.join('\n')),
    );
  }
  if (fixture.kind != FixtureKind.compileError) {
    return _failed(
      'compileError',
      error.diagnostics.join('\n'),
      Termination.compileError,
    );
  }
  if (fixture.checkDiagnostic) {
    final selected = selectJqError(error.diagnostics);
    if (!diagnosticMatches(fixture.diagnostics, selected)) {
      return _failed(
        'diagnosticMismatch',
        'expected ${fixture.diagnostics.join(' / ')} but zaru reported '
            '${selected ?? error.diagnostics.join(' / ')}',
        Termination.compileError,
      );
    }
  }
  return const CaseVerdict(CaseStatus.passed, Termination.compileError);
}

CaseVerdict _execute(
  JqFixture fixture,
  ReferenceExpectation expectation,
  ZaruFilter filter,
) {
  final iterator = filter.runJson(fixture.input!).iterator;
  var emitted = 0;
  while (true) {
    final bool more;
    try {
      more = iterator.moveNext();
    } on ZaruRuntimeError catch (error) {
      return _runtimeError(fixture, expectation, emitted, error);
    } on FormatException catch (error) {
      return _failed('inputDecodeError', error.message);
    } on Object catch (error) {
      return _failed('hostException', 'run: $error');
    }
    if (!more) {
      if (emitted < fixture.outputs.length) {
        return _failed(
          'missingExpectedOutput',
          'expected ${fixture.outputs.length} outputs but got $emitted',
          Termination.exhausted,
        );
      }
      if (expectation.terminal == Termination.runtimeError) {
        return _failed(
          'missingRuntimeError',
          'the reference ends in a runtime error; zaru exhausted instead',
          Termination.exhausted,
        );
      }
      return const CaseVerdict(CaseStatus.passed, Termination.exhausted);
    }
    if (emitted >= fixture.outputs.length) {
      // Stop at the first surplus result; the rest is not pulled.
      return _failed(
        'surplusOutput',
        'output ${emitted + 1} has no expected value',
      );
    }
    final expected = fixture.outputs[emitted];
    switch (compareExpected(expected, iterator.current)) {
      case OracleVerdict.match:
        break;
      case OracleVerdict.mismatch:
        return _failed(
          'outputMismatch',
          'output ${emitted + 1} differs from expected $expected: '
              '${Zaru.toJson(iterator.current)}',
        );
      case OracleVerdict.malformedExpectation:
        return _failed('malformedExpectation', 'expected $expected');
    }
    emitted++;
  }
}

CaseVerdict _runtimeError(
  JqFixture fixture,
  ReferenceExpectation expectation,
  int emitted,
  ZaruRuntimeError error,
) {
  if (emitted < fixture.outputs.length) {
    return _failed(
      'missingExpectedOutput',
      'runtime error ${error.message} after $emitted of '
          '${fixture.outputs.length} expected outputs',
      Termination.runtimeError,
    );
  }
  if (expectation.terminal != Termination.runtimeError) {
    return _failed(
      'unexpectedRuntimeError',
      error.message,
      Termination.runtimeError,
    );
  }
  if (!oracleEquals(expectation.errorValue, error.value)) {
    return _failed(
      'errorValueMismatch',
      'the reference error differs from ${Zaru.toJson(error.value)}',
      Termination.runtimeError,
    );
  }
  return const CaseVerdict(CaseStatus.passed, Termination.runtimeError);
}
