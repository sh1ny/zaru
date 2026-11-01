// Accounting, baseline-integrity and gate decisions of the conformance
// harness, exercised with the real compiler and engine on small synthetic
// baselines. The frozen 781-ID files are covered by the VM tests.
//
// Browser-safe: no dart:io, no native jq.
import 'dart:convert';

import 'package:test/test.dart';

import '../support/conformance_accounting.dart';
import '../support/conformance_baseline.dart';
import '../support/conformance_run.dart';
import 'conformance_support.dart';

const deferred = 'explicit-deferred-dependency';

Matcher failureCode(String code) => throwsA(
  isA<BaselineFailure>().having((failure) => failure.code, 'code', code),
);

/// Runs every fixture of [baseline] with the real engine and accounts it.
ConformanceReport executeAll(Baseline baseline, {String runId = 'run-1'}) =>
    buildReport(
      runId: runId,
      mode: 'full',
      baseline: baseline,
      verdicts: {
        for (final fixture in baseline.fixtures)
          fixture.id: runFixture(fixture, baseline.expectations[fixture.id]!),
      },
    );

const passedVerdict = CaseVerdict(CaseStatus.passed, Termination.exhausted);
const failedVerdict = CaseVerdict(
  CaseStatus.failed,
  Termination.notObserved,
  'outputMismatch',
  'handcrafted',
);

/// A report with the given verdict per ID.
ConformanceReport handcrafted(
  Baseline baseline,
  Map<String, CaseVerdict> verdicts, {
  String runId = 'run-1',
}) => buildReport(
  runId: runId,
  mode: 'gate',
  baseline: baseline,
  verdicts: verdicts,
);

Map<String, CaseVerdict> allPassing(Baseline baseline) => {
  for (final id in baseline.ids) id: passedVerdict,
};

/// Three-case baseline: a, b are M1, c is deferred.
Baseline threeCases() => synthetic(
  {
    'jq.test': '.\n1\n1\n\n.[]\n[2]\n2\n\nltrimstr("a")\n"ab"\n"b"\n',
    'man.test': '',
  },
  classes: {'jq.test:9': deferred},
).verify();

void main() {
  group('execution accounting', () {
    test('Identity becomes supported', () {
      final baseline = synthetic({'jq.test': '.\n1\n1\n'}).verify();
      final report = executeAll(baseline);
      expect(report.cases.single.status, CaseStatus.passed);
      expect(report.count(CaseStatus.passed), 1);
      expect(report.cases, hasLength(1));
      expect(fullExitCode(report), 0);
    });

    test('Unsupported builtin remains visible', () {
      final baseline = synthetic(
        {'jq.test': '.\n1\n1\n\nltrimstr("a")\n"ab"\n"b"\n'},
        classes: {'jq.test:5': deferred},
      ).verify();
      final report = executeAll(baseline);
      final unsupported = report.cases.last;
      expect(unsupported.id, 'jq.test:5');
      expect(unsupported.status, CaseStatus.unsupported);
      expect(unsupported.reason, 'unsupportedConstruct');
      expect(unsupported.detail, isNotEmpty);
      // Same denominator; the numerator still counts only the identity case.
      expect(report.cases, hasLength(2));
      expect(report.count(CaseStatus.passed), 1);
      expect(report.count(CaseStatus.unsupported), 1);
      expect(fullExitCode(report), isNot(0));
    });

    test('a case without a verdict is accounted as not run', () {
      final baseline = threeCases();
      final report = handcrafted(baseline, {'jq.test:1': passedVerdict});
      expect(report.cases, hasLength(3));
      expect(report.count(CaseStatus.notRun), 2);
      expect(fullExitCode(report), isNot(0));
      final verdict = evaluateGate(
        report: report,
        baseline: baseline,
        floor: const {},
        expectedRunId: 'run-1',
      );
      expect(verdict.passed, isFalse);
      expect(verdict.problems.map((p) => p.code), contains('incompleteRun'));
    });

    test('a verdict for an unknown ID is rejected', () {
      final baseline = threeCases();
      expect(
        () => handcrafted(baseline, {'jq.test:99': passedVerdict}),
        failureCode('conformance_report_invalid'),
      );
    });
  });

  group('termination', () {
    test('Reference-backed runtime failure', () {
      const fixture =
          '.[] as {a:\$a} ?// {a:\$a} ?// {a:\$a} | \$a\n[[3],[4],[5],6]\n';
      final verdict = runOne(
        fixture,
        fact: runtimeErrorFact('Cannot index array with string ("a")'),
      );
      expect(verdict.status, CaseStatus.passed, reason: '${verdict.detail}');
      // Retained separately from ordinary exhaustion.
      expect(verdict.termination, Termination.runtimeError);

      // The same stream with the wrong recorded value is not a pass.
      final wrong = runOne(fixture, fact: runtimeErrorFact('something else'));
      expect(wrong.status, CaseStatus.failed);
      expect(wrong.reason, 'errorValueMismatch');
      // Recorded as exhausted, the runtime error is unexpected.
      final exhausted = runOne(fixture);
      expect(exhausted.status, CaseStatus.failed);
      expect(exhausted.reason, 'unexpectedRuntimeError');
    });

    test('Missing prefix', () {
      final verdict = runOne(
        'error("bad")\nnull\n1\n',
        fact: runtimeErrorFact('bad'),
      );
      expect(verdict.status, CaseStatus.failed);
      expect(verdict.reason, 'missingExpectedOutput');
      expect(verdict.termination, Termination.runtimeError);
    });

    test('Unexpected error after correct values', () {
      final verdict = runOne('1, error("x")\nnull\n1\n');
      expect(verdict.status, CaseStatus.failed);
      expect(verdict.reason, 'unexpectedRuntimeError');
      expect(verdict.termination, Termination.runtimeError);
      // The ordinary-exhaustion expectation does not absorb a missing error.
      final missing = runOne('1\nnull\n1\n', fact: runtimeErrorFact('bad'));
      expect(missing.status, CaseStatus.failed);
      expect(missing.reason, 'missingRuntimeError');
    });

    test('Reference census covers nonempty error prefixes', () {
      final built = synthetic(
        {'jq.test': '1, error("bad")\nnull\n1\n'},
        facts: {
          'jq.test:1': {
            ...runtimeErrorFact('bad'),
            'outputPrefix': ['1'],
          },
        },
      );
      final baseline = built.verify();
      final expectation = baseline.expectations['jq.test:1']!;
      expect(expectation.terminal, Termination.runtimeError);
      expect(expectation.errorValue, 'bad');
      // The expectation passes only for prefix then the same error.
      expect(
        runFixture(baseline.fixtures.single, expectation).status,
        CaseStatus.passed,
      );
      // A census prefix that disagrees with the fixture's outputs is rejected.
      expect(
        () => synthetic(
          {'jq.test': '1, error("bad")\nnull\n1\n'},
          facts: {
            'jq.test:1': {
              ...runtimeErrorFact('bad'),
              'outputPrefix': <Object?>[],
            },
          },
        ).verify(),
        failureCode('reference_census_invalid'),
      );
      // A runtime-error terminal without its recorded error wire is rejected.
      expect(
        () => synthetic(
          {'jq.test': '1, error("bad")\nnull\n1\n'},
          facts: {
            'jq.test:1': {
              'terminal': 'runtimeError',
              'outputPrefix': ['1'],
            },
          },
        ).verify(),
        failureCode('reference_census_invalid'),
      );
    });

    test('Incomplete reference environment blocks acceptance', () {
      final built = synthetic({'jq.test': '.\n1\n1\n'});
      // Missing driver digest in the provenance.
      final noDriver =
          jsonDecode(jsonEncode(built.census)) as Map<String, Object?>;
      (noDriver['provenance']! as Map<String, Object?>).remove('driver');
      expect(
        () => built.verify(censusPayload: utf8.encode(jsonEncode(noDriver))),
        failureCode('reference_integrity_mismatch'),
      );
      // Even with fresh integrity it is not a complete baseline.
      final rebuilt = SyntheticBaseline(
        corpus: built.corpus,
        census: noDriver,
        classification: built.classification,
      );
      expect(rebuilt.verify, failureCode('reference_census_invalid'));
      // A different pinned binary identity is not the pinned reference either.
      final wrongVersion =
          jsonDecode(jsonEncode(built.census)) as Map<String, Object?>;
      (wrongVersion['provenance']! as Map<String, Object?>)['jqVersion'] =
          'jq-1.7';
      expect(
        SyntheticBaseline(
          corpus: built.corpus,
          census: wrongVersion,
          classification: built.classification,
        ).verify,
        failureCode('reference_census_invalid'),
      );
      // A missing reference result for a case is rejected.
      final missingCase =
          jsonDecode(jsonEncode(built.census)) as Map<String, Object?>;
      (missingCase['cases']! as Map<String, Object?>).remove('jq.test:1');
      expect(
        SyntheticBaseline(
          corpus: built.corpus,
          census: missingCase,
          classification: built.classification,
        ).verify,
        failureCode('reference_census_invalid'),
      );
      // The complete baseline is accepted with nothing but its own bytes: no
      // jq binary is consulted anywhere.
      expect(built.verify().ids, {'jq.test:1'});
    });
  });

  group('baseline integrity', () {
    test('Changed baseline payload fails integrity', () {
      final built = synthetic({'jq.test': '.\n1\n1\n'});
      final recorded = built.integrityFor(
        built.censusBytes,
        built.classificationBytes,
      );
      final tamperedCensus =
          jsonDecode(jsonEncode(built.census)) as Map<String, Object?>;
      tamperedCensus['note'] = 'edited';
      expect(
        () => built.verify(
          integrity: recorded,
          censusPayload: utf8.encode(jsonEncode(tamperedCensus)),
        ),
        failureCode('reference_integrity_mismatch'),
      );
      final tamperedClassification =
          jsonDecode(jsonEncode(built.classification)) as Map<String, Object?>;
      tamperedClassification['note'] = 'edited';
      expect(
        () => built.verify(
          integrity: recorded,
          classificationPayload: utf8.encode(
            jsonEncode(tamperedClassification),
          ),
        ),
        failureCode('reference_integrity_mismatch'),
      );
      // Malformed recorded digest and missing integrity are also rejected.
      expect(
        () => built.verify(integrity: utf8.encode('{}')),
        failureCode('reference_integrity_invalid'),
      );
      expect(built.verify().ids, {'jq.test:1'});
    });

    test('Baseline covers exactly the corpus IDs', () {
      final built = synthetic({
        'jq.test': '.\n1\n1\n\n.\n2\n2\n',
        'man.test': '.\n3\n3\n',
      });
      expect(built.verify().ids, {'jq.test:1', 'jq.test:5', 'man.test:1'});
      // The frozen total is part of the contract.
      expect(
        () => built.verify(expectedTotal: 781),
        failureCode('reference_census_invalid'),
      );

      SyntheticBaseline edited(
        void Function(Map<String, Object?> census, Map<String, Object?> cls)
        mutate,
      ) {
        final census =
            jsonDecode(jsonEncode(built.census)) as Map<String, Object?>;
        final classification =
            jsonDecode(jsonEncode(built.classification))
                as Map<String, Object?>;
        mutate(census, classification);
        return SyntheticBaseline(
          corpus: built.corpus,
          census: census,
          classification: classification,
        );
      }

      // Extra, missing, duplicate and unclassified IDs are all rejected even
      // when the recorded hashes are fresh.
      expect(
        edited((census, _) {
          (census['cases']! as Map<String, Object?>)['jq.test:99'] = {
            'primary': <String, Object?>{},
          };
        }).verify,
        failureCode('reference_census_invalid'),
      );
      expect(
        edited((census, _) {
          (census['cases']! as Map<String, Object?>).remove('man.test:1');
        }).verify,
        failureCode('reference_census_invalid'),
      );
      expect(
        edited((_, cls) {
          final cases = cls['cases']! as List<Object?>;
          cases[1] = cases[0];
        }).verify,
        failureCode('reference_classification_invalid'),
      );
      expect(
        edited((_, cls) {
          (cls['cases']! as List<Object?>).removeLast();
        }).verify,
        failureCode('reference_classification_invalid'),
      );
      // A changed terminal fact is not a valid reference observation.
      expect(
        edited((census, _) {
          final primary =
              ((census['cases']! as Map<String, Object?>)['jq.test:1']!
                      as Map<String, Object?>)['primary']!
                  as Map<String, Object?>;
          primary['terminal'] = 'compileError';
        }).verify,
        failureCode('reference_census_invalid'),
      );
    });
  });

  group('milestone gate', () {
    test('Milestone complete', () {
      final baseline = threeCases();
      final report = handcrafted(baseline, {
        'jq.test:1': passedVerdict,
        'jq.test:5': passedVerdict,
        'jq.test:9': failedVerdict,
      });
      final verdict = evaluateGate(
        report: report,
        baseline: baseline,
        floor: const {'jq.test:1'},
        expectedRunId: 'run-1',
      );
      expect(verdict.passed, isTrue, reason: '${verdict.problems.length}');
      // The remaining non-core failure is still exposed.
      expect(verdict.remainingFailures, ['jq.test:9']);
      expect(report.count(CaseStatus.failed), 1);
    });

    test('Equal count hides a regression', () {
      // a and b are deferred, so only the floor can notice the swap.
      final baseline = synthetic(
        {'jq.test': '.\n1\n1\n\n.\n2\n2\n'},
        classes: {'jq.test:1': deferred, 'jq.test:5': deferred},
      ).verify();
      final before = handcrafted(baseline, {
        'jq.test:1': passedVerdict,
        'jq.test:5': failedVerdict,
      });
      final after = handcrafted(baseline, {
        'jq.test:1': failedVerdict,
        'jq.test:5': passedVerdict,
      });
      expect(after.count(CaseStatus.passed), before.count(CaseStatus.passed));
      final verdict = evaluateGate(
        report: after,
        baseline: baseline,
        floor: const {'jq.test:1'},
        expectedRunId: 'run-1',
      );
      expect(verdict.passed, isFalse);
      expect(verdict.floorRegressions, ['jq.test:1']);
      expect(gateExitCode(verdict), isNot(0));
      // Without the swap the same floor is satisfied.
      expect(
        evaluateGate(
          report: before,
          baseline: baseline,
          floor: const {'jq.test:1'},
          expectedRunId: 'run-1',
        ).passed,
        isTrue,
      );
    });

    test('Manual core case participates in acceptance', () {
      final baseline = synthetic({
        'jq.test': '.\n1\n1\n',
        'man.test': '.\n"Hello"\n"Hello"\n',
      }).verify();
      expect(baseline.acceptanceIds, contains('man.test:1'));
      final verdict = evaluateGate(
        report: handcrafted(baseline, {
          'jq.test:1': passedVerdict,
          'man.test:1': failedVerdict,
        }),
        baseline: baseline,
        floor: const {},
        expectedRunId: 'run-1',
      );
      expect(verdict.passed, isFalse);
      expect(verdict.requiredFailures, ['man.test:1']);
    });

    test('Classification cannot be fitted to a failing engine', () {
      final built = synthetic(
        {'jq.test': '.\n1\n1\n\n.\n2\n2\n'},
        classes: {'jq.test:5': deferred},
      );
      final baseline = built.verify();
      expect(baseline.acceptanceIds, {'jq.test:1'});
      // An M1-classified failure fails the gate, whatever else passes.
      final failing = handcrafted(baseline, {
        'jq.test:1': failedVerdict,
        'jq.test:5': passedVerdict,
      });
      final verdict = evaluateGate(
        report: failing,
        baseline: baseline,
        floor: const {},
        expectedRunId: 'run-1',
      );
      expect(verdict.passed, isFalse);
      expect(verdict.requiredFailures, ['jq.test:1']);
      // Weakening the classification changes the frozen payload, so both
      // commands reject the baseline instead of accepting the weaker set.
      final weakened =
          jsonDecode(jsonEncode(built.classification)) as Map<String, Object?>;
      for (final entry in weakened['cases']! as List<Object?>) {
        (entry! as Map<String, Object?>)['classification'] = deferred;
      }
      expect(
        () => built.verify(
          classificationPayload: utf8.encode(jsonEncode(weakened)),
        ),
        failureCode('reference_integrity_mismatch'),
      );
      // The acceptance set only knows reviewed classification values.
      weakened['cases'] = [
        {'id': 'jq.test:1', 'classification': 'passes-today'},
        {'id': 'jq.test:5', 'classification': deferred},
      ];
      expect(
        SyntheticBaseline(
          corpus: built.corpus,
          census: built.census,
          classification: weakened,
        ).verify,
        failureCode('reference_classification_invalid'),
      );
    });

    test('Gate can pass while the full corpus remains red', () {
      final baseline = threeCases();
      final report = handcrafted(baseline, {
        'jq.test:1': passedVerdict,
        'jq.test:5': passedVerdict,
        'jq.test:9': failedVerdict,
      });
      final verdict = evaluateGate(
        report: report,
        baseline: baseline,
        floor: const {'jq.test:1', 'jq.test:5'},
        expectedRunId: 'run-1',
      );
      expect(gateExitCode(verdict), 0);
      expect(fullExitCode(report), isNot(0));
      expect(verdict.remainingFailures, ['jq.test:9']);
    });

    test('Regression is distinguishable from expected baseline failures', () {
      final baseline = threeCases();
      // Case 5 (M1) fails and case 1 (floor) fails; case 9 fails as expected.
      final report = handcrafted(baseline, {
        'jq.test:1': failedVerdict,
        'jq.test:5': failedVerdict,
        'jq.test:9': failedVerdict,
      });
      final verdict = evaluateGate(
        report: report,
        baseline: baseline,
        floor: const {'jq.test:1'},
        expectedRunId: 'run-1',
      );
      expect(fullExitCode(report), isNot(0));
      expect(gateExitCode(verdict), isNot(0));
      expect(verdict.floorRegressions, ['jq.test:1']);
      expect(verdict.requiredFailures, ['jq.test:1', 'jq.test:5']);
      expect(verdict.remainingFailures, ['jq.test:9']);
      expect(
        verdict.problems.map((problem) => problem.code),
        containsAll(<String>['requiredCaseFailed', 'floorRegression']),
      );
    });

    test('Stale reports cannot satisfy a gate', () {
      final baseline = threeCases();
      final stale = handcrafted(baseline, {
        for (final id in baseline.ids) id: passedVerdict,
      }, runId: 'yesterday');
      // Even a perfectly green stale report is refused.
      final staleVerdict = evaluateGate(
        report: stale,
        baseline: baseline,
        floor: const {},
        expectedRunId: 'today',
      );
      expect(staleVerdict.passed, isFalse);
      expect(staleVerdict.problems.map((p) => p.code), ['staleReport']);

      // The fresh execution fails one required case: the gate fails.
      final fresh = handcrafted(baseline, {
        'jq.test:1': passedVerdict,
        'jq.test:5': failedVerdict,
        'jq.test:9': failedVerdict,
      }, runId: 'today');
      final freshVerdict = evaluateGate(
        report: fresh,
        baseline: baseline,
        floor: const {},
        expectedRunId: 'today',
      );
      expect(freshVerdict.passed, isFalse);
      expect(freshVerdict.requiredFailures, ['jq.test:5']);

      // A report read back from disk keeps its identity and is still stale.
      final reread = ConformanceReport.fromJson(
        jsonDecode(jsonEncode(stale.toJson())) as Map<String, Object?>,
      );
      expect(reread.runId, 'yesterday');
      expect(
        evaluateGate(
          report: reread,
          baseline: baseline,
          floor: const {},
          expectedRunId: 'today',
        ).passed,
        isFalse,
      );

      // A report produced against a different baseline is stale too.
      final other = ConformanceReport(
        runId: 'today',
        mode: 'gate',
        censusSha256: 'f' * 64,
        classificationSha256: fresh.classificationSha256,
        cases: fresh.cases,
      );
      expect(
        evaluateGate(
          report: other,
          baseline: baseline,
          floor: const {},
          expectedRunId: 'today',
        ).problems.map((p) => p.code),
        contains('staleReport'),
      );
    });

    test('the floor must name known IDs in sorted order', () {
      const known = {'jq.test:1', 'jq.test:5'};
      expect(
        parseFloor(
          '{"format":"zaru-conformance-floor-v1","passed":["jq.test:1"]}',
          known,
        ),
        {'jq.test:1'},
      );
      expect(
        parseFloor('{"format":"zaru-conformance-floor-v1","passed":[]}', known),
        isEmpty,
      );
      for (final bad in [
        '{"format":"zaru-conformance-floor-v1","passed":["jq.test:99"]}',
        '{"format":"zaru-conformance-floor-v1","passed":["jq.test:5","jq.test:1"]}',
        '{"format":"zaru-conformance-floor-v1","passed":["jq.test:1","jq.test:1"]}',
        '{"format":"other","passed":[]}',
        'not json',
      ]) {
        expect(
          () => parseFloor(bad, known),
          failureCode('conformance_floor_invalid'),
          reason: bad,
        );
      }
    });
  });
}
