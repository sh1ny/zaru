// The jq conformance commands.
//
//   dart run tool/conformance.dart          full corpus; nonzero for any failure
//   dart run tool/conformance.dart --gate   M1 acceptance gate
//
// Both verify the frozen reference baseline (digests, provenance, exactly 781
// IDs), then freshly execute every case with the real zaru engine. Neither
// starts jq or regenerates the baseline, and neither reads an earlier report.
//
// Exit codes: 0 success, 1 a conformance failure, 2 an unusable baseline,
// floor, or invocation (nothing was evaluated against it).
import 'dart:io';

import '../test/conformance/conformance_io.dart';
import '../test/support/conformance_accounting.dart';
import '../test/support/conformance_baseline.dart';
import '../test/support/conformance_run.dart';

void main(List<String> args) {
  try {
    exitCode = _run(args);
  } on BaselineFailure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 2;
  } on _Usage catch (usage) {
    stderr.writeln('conformance_usage: ${usage.message}');
    exitCode = 2;
  }
}

int _run(List<String> args) {
  var gate = false;
  var reportPath = defaultReportPath;
  var floorPath = defaultFloorPath;
  var integrity = defaultIntegrityPath;
  var census = defaultCensusPath;
  var classification = defaultClassificationPath;
  for (var index = 0; index < args.length; index++) {
    final option = args[index];
    if (option == '--gate') {
      gate = true;
      continue;
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw _Usage('$option needs a value');
    }
    final value = args[++index];
    switch (option) {
      case '--report':
        reportPath = value;
      case '--floor':
        floorPath = value;
      case '--integrity':
        integrity = value;
      case '--census':
        census = value;
      case '--classification':
        classification = value;
      default:
        throw _Usage('unknown option $option');
    }
  }

  // A report from an earlier run can never be consumed: remove it before
  // anything else, so a failed verification leaves none behind either.
  final previous = File(reportPath);
  if (previous.existsSync()) previous.deleteSync();

  final baseline = loadVerifiedBaseline(
    BaselinePaths(
      integrity: integrity,
      census: census,
      classification: classification,
    ),
  );
  final floor = gate ? loadFloor(floorPath, baseline.ids) : <String>{};

  final runId = newRunId();
  final verdicts = executeCorpus(baseline);
  final report = buildReport(
    runId: runId,
    mode: gate ? 'gate' : 'full',
    baseline: baseline,
    verdicts: verdicts,
  );
  final verdict = gate
      ? evaluateGate(
          report: report,
          baseline: baseline,
          floor: floor,
          expectedRunId: runId,
        )
      : null;
  writeReport(reportPath, report.toJson(gate: verdict, floor: floor));

  _summarize(report, verdict, reportPath);
  return verdict == null ? fullExitCode(report) : gateExitCode(verdict);
}

void _summarize(
  ConformanceReport report,
  GateVerdict? verdict,
  String reportPath,
) {
  final passed = report.count(CaseStatus.passed);
  final required = report.cases.where((result) => result.acceptance).toList();
  final requiredPassed = required
      .where((result) => result.status == CaseStatus.passed)
      .length;
  print(
    '$passed / ${report.cases.length} jq tests passing '
    '(${report.count(CaseStatus.failed)} failed, '
    '${report.count(CaseStatus.unsupported)} unsupported, '
    '${report.count(CaseStatus.notRun)} not run, 0 skipped)',
  );
  print('M1 acceptance cases passing: $requiredPassed / ${required.length}');
  final reasons = <String, int>{};
  for (final result in report.cases) {
    if (result.status != CaseStatus.passed) {
      reasons.update(
        '${result.status.name}:${result.reason}',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }
  for (final entry in reasons.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))) {
    print('  ${entry.value.toString().padLeft(4)}  ${entry.key}');
  }
  print('Conformance report: $reportPath');
  if (verdict == null) return;
  print(
    'Remaining non-gating failures: ${verdict.remainingFailures.length}',
  );
  if (verdict.passed) {
    print('conformance-gate: PASS');
    return;
  }
  for (final problem in verdict.problems) {
    print('conformance-gate: ${problem.code}: ${problem.detail}');
  }
  final byId = {for (final result in report.cases) result.id: result};
  final listed = {...verdict.requiredFailures, ...verdict.floorRegressions};
  var shown = 0;
  for (final id in listed) {
    if (shown++ == 40) {
      print('  ... ${listed.length - 40} more in the report');
      break;
    }
    final result = byId[id]!;
    final detail = (result.detail ?? '').replaceAll('\n', ' / ');
    print(
      '  $id ${result.status.name} ${result.reason}: '
      '${detail.length > 140 ? '${detail.substring(0, 140)}...' : detail}',
    );
  }
  print('conformance-gate: FAIL');
}

final class _Usage implements Exception {
  const _Usage(this.message);
  final String message;
}
