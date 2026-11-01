// Report accounting and the binary M1 gate.
//
// Browser-safe: pure decisions over observed verdicts. The gate recomputes its
// decision from the fresh report it is handed and refuses any report that
// does not belong to the current run and verified baseline.
import '../conformance/fixtures.dart';
import 'conformance_baseline.dart';
import 'conformance_run.dart';

/// One accounted case.
final class CaseResult {
  const CaseResult({
    required this.id,
    required this.source,
    required this.line,
    required this.kind,
    required this.classification,
    required this.acceptance,
    required this.status,
    required this.termination,
    this.reason,
    this.detail,
  });

  final String id;
  final String source;
  final int line;
  final FixtureKind kind;
  final String classification;

  /// Whether the frozen classification makes the case part of M1 acceptance.
  final bool acceptance;
  final CaseStatus status;
  final Termination termination;
  final String? reason;
  final String? detail;

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'line': line,
    'kind': kind.name,
    'classification': classification,
    'm1Required': acceptance,
    'status': status.name,
    'termination': termination.name,
    'reason': ?reason,
    'detail': ?detail,
  };

  static CaseResult fromJson(Object? json) {
    if (json is! Map<String, Object?>) _invalid('case is not an object');
    return CaseResult(
      id: _string(json, 'id'),
      source: _string(json, 'source'),
      line: _int(json, 'line'),
      kind: _enum(FixtureKind.values, _string(json, 'kind')),
      classification: _string(json, 'classification'),
      acceptance: json['m1Required'] == true,
      status: _enum(CaseStatus.values, _string(json, 'status')),
      termination: _enum(Termination.values, _string(json, 'termination')),
      reason: json['reason'] as String?,
      detail: json['detail'] as String?,
    );
  }
}

/// A complete (or deliberately incomplete) accounting of one execution.
final class ConformanceReport {
  const ConformanceReport({
    required this.runId,
    required this.mode,
    required this.censusSha256,
    required this.classificationSha256,
    required this.cases,
  });

  /// Identity of the execution that produced the observations.
  final String runId;

  /// `full` or `gate`.
  final String mode;
  final String censusSha256;
  final String classificationSha256;
  final List<CaseResult> cases;

  int count(CaseStatus status) =>
      cases.where((result) => result.status == status).length;

  Map<String, Object?> toJson({GateVerdict? gate, Set<String>? floor}) {
    final required = cases.where((result) => result.acceptance);
    return {
      'schemaVersion': 2,
      'upstreamTag': 'jq-1.8.2',
      'upstreamCommit': '34f7186b86743a083a589741b6cea95293524108',
      'milestone': 'M1',
      'runId': runId,
      'mode': mode,
      'baseline': {
        'censusSha256': censusSha256,
        'classificationSha256': classificationSha256,
        'total': cases.length,
      },
      'counts': {
        'total': cases.length,
        'passed': count(CaseStatus.passed),
        'failed': count(CaseStatus.failed),
        'unsupported': count(CaseStatus.unsupported),
        'notRun': count(CaseStatus.notRun),
        'skipped': 0,
      },
      'm1': {
        'required': required.length,
        'passed': required
            .where((result) => result.status == CaseStatus.passed)
            .length,
      },
      'sources': {
        for (final source in {for (final result in cases) result.source})
          source: cases.where((result) => result.source == source).length,
      },
      'gate': ?(gate == null
          ? null
          : {
              'passed': gate.passed,
              'problems': [
                for (final problem in gate.problems)
                  {
                    'code': problem.code,
                    'detail': problem.detail,
                    'ids': problem.ids,
                  },
              ],
              'requiredFailures': gate.requiredFailures,
              'floorRegressions': gate.floorRegressions,
              'remainingFailureCount': gate.remainingFailures.length,
              'floorSize': floor?.length,
            }),
      'cases': [for (final result in cases) result.toJson()],
    };
  }

  /// Reads a report back, for example one left over from an earlier run.
  static ConformanceReport fromJson(Map<String, Object?> json) {
    final baseline = json['baseline'];
    final cases = json['cases'];
    if (baseline is! Map<String, Object?> || cases is! List<Object?>) {
      _invalid('report lacks a baseline or cases');
    }
    return ConformanceReport(
      runId: _string(json, 'runId'),
      mode: _string(json, 'mode'),
      censusSha256: _string(baseline, 'censusSha256'),
      classificationSha256: _string(baseline, 'classificationSha256'),
      cases: [for (final entry in cases) CaseResult.fromJson(entry)],
    );
  }
}

/// Accounts every baseline case: a case without a verdict is `notRun`, and a
/// verdict for an ID the baseline does not contain is rejected.
ConformanceReport buildReport({
  required String runId,
  required String mode,
  required Baseline baseline,
  required Map<String, CaseVerdict> verdicts,
}) {
  final unknown = verdicts.keys.where((id) => !baseline.ids.contains(id));
  if (unknown.isNotEmpty) {
    _invalid('verdict for unknown stable ID ${unknown.first}');
  }
  final acceptance = baseline.acceptanceIds;
  return ConformanceReport(
    runId: runId,
    mode: mode,
    censusSha256: baseline.censusSha256,
    classificationSha256: baseline.classificationSha256,
    cases: List.unmodifiable([
      for (final fixture in baseline.fixtures)
        _result(
          fixture,
          baseline.classifications[fixture.id]!,
          acceptance.contains(fixture.id),
          verdicts[fixture.id],
        ),
    ]),
  );
}

CaseResult _result(
  JqFixture fixture,
  String classification,
  bool acceptance,
  CaseVerdict? verdict,
) => CaseResult(
  id: fixture.id,
  source: fixture.source,
  line: fixture.line,
  kind: fixture.kind,
  classification: classification,
  acceptance: acceptance,
  status: verdict?.status ?? CaseStatus.notRun,
  termination: verdict?.termination ?? Termination.notObserved,
  reason: verdict == null ? 'notRun' : verdict.reason,
  detail: verdict?.detail,
);

/// A reason the gate refuses acceptance.
final class GateProblem {
  const GateProblem(this.code, this.ids, this.detail);

  final String code;
  final List<String> ids;
  final String detail;
}

/// The binary decision plus the evidence behind it.
final class GateVerdict {
  const GateVerdict({
    required this.problems,
    required this.requiredFailures,
    required this.floorRegressions,
    required this.remainingFailures,
  });

  final List<GateProblem> problems;

  /// M1-classified cases that are not passing.
  final List<String> requiredFailures;

  /// Floor IDs that are not passing.
  final List<String> floorRegressions;

  /// Non-passing cases that are neither M1-required nor in the floor: the
  /// expected baseline failures of later milestones.
  final List<String> remainingFailures;

  bool get passed => problems.isEmpty;
}

/// Decides M1 acceptance for [report], which must come from the current run
/// ([expectedRunId]) and the verified [baseline].
///
/// The gate requires complete accounting of every baseline ID, every
/// M1-classified case passing, and every [floor] ID still passing. Failing
/// non-M1, non-floor cases are reported but do not fail the gate.
GateVerdict evaluateGate({
  required ConformanceReport report,
  required Baseline baseline,
  required Set<String> floor,
  required String expectedRunId,
}) {
  final problems = <GateProblem>[];
  if (report.runId != expectedRunId ||
      report.censusSha256 != baseline.censusSha256 ||
      report.classificationSha256 != baseline.classificationSha256) {
    problems.add(
      GateProblem(
        'staleReport',
        const [],
        'the report belongs to run ${report.runId} and another baseline '
            'identity, not the current run $expectedRunId',
      ),
    );
  }

  final seen = <String>{};
  final duplicates = <String>[];
  for (final result in report.cases) {
    if (!seen.add(result.id)) duplicates.add(result.id);
  }
  final baselineIds = baseline.ids;
  final missing = [
    for (final id in baselineIds)
      if (!seen.contains(id)) id,
  ];
  final extra = [
    for (final id in seen)
      if (!baselineIds.contains(id)) id,
  ];
  final notRun = [
    for (final result in report.cases)
      if (result.status == CaseStatus.notRun) result.id,
  ];
  if (missing.isNotEmpty ||
      extra.isNotEmpty ||
      duplicates.isNotEmpty ||
      notRun.isNotEmpty) {
    problems.add(
      GateProblem(
        'incompleteRun',
        [...missing, ...extra, ...duplicates, ...notRun],
        'baseline IDs must be accounted exactly once with an observation: '
            '${missing.length} missing, ${extra.length} unknown, '
            '${duplicates.length} duplicated, ${notRun.length} not run',
      ),
    );
  }

  final acceptance = baseline.acceptanceIds;
  final requiredFailures = <String>[];
  final floorRegressions = <String>[];
  final remainingFailures = <String>[];
  for (final result in report.cases) {
    if (result.status == CaseStatus.passed) continue;
    final required = acceptance.contains(result.id);
    final inFloor = floor.contains(result.id);
    if (required) requiredFailures.add(result.id);
    if (inFloor) floorRegressions.add(result.id);
    if (!required && !inFloor) remainingFailures.add(result.id);
  }
  final unknownFloor = [
    for (final id in floor)
      if (!baselineIds.contains(id)) id,
  ];
  if (unknownFloor.isNotEmpty) {
    problems.add(
      GateProblem(
        'floorUnknownId',
        unknownFloor,
        'the floor names IDs outside the baseline',
      ),
    );
  }
  if (requiredFailures.isNotEmpty) {
    problems.add(
      GateProblem(
        'requiredCaseFailed',
        requiredFailures,
        '${requiredFailures.length} M1-classified cases are not passing',
      ),
    );
  }
  if (floorRegressions.isNotEmpty) {
    problems.add(
      GateProblem(
        'floorRegression',
        floorRegressions,
        '${floorRegressions.length} previously passing cases are not passing',
      ),
    );
  }
  return GateVerdict(
    problems: List.unmodifiable(problems),
    requiredFailures: List.unmodifiable(requiredFailures),
    floorRegressions: List.unmodifiable(floorRegressions),
    remainingFailures: List.unmodifiable(remainingFailures),
  );
}

/// Exit code of the full-corpus command: zero only if every case passed.
int fullExitCode(ConformanceReport report) =>
    report.cases.isNotEmpty &&
        report.cases.every((result) => result.status == CaseStatus.passed)
    ? 0
    : 1;

/// Exit code of the gate command.
int gateExitCode(GateVerdict verdict) => verdict.passed ? 0 : 1;

Never _invalid(String detail) =>
    throw BaselineFailure('conformance_report_invalid', detail);

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  _invalid('$key is not a string');
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  _invalid('$key is not an integer');
}

T _enum<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  _invalid('unknown value $name');
}
