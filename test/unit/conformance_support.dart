// Builders for small synthetic frozen baselines, used by the browser-safe
// conformance comparison and accounting tests. Everything here is pure.
import 'dart:convert';

import '../../tool/sha256.dart';
import '../conformance/fixtures.dart';
import '../support/conformance_baseline.dart';
import '../support/conformance_run.dart';

const pinnedCommit = '34f7186b86743a083a589741b6cea95293524108';
const pinnedArchive =
    '332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c';
final someDigest = 'ab' * 32;

/// Raw bytes of a synthetic frozen baseline plus the corpus it describes.
final class SyntheticBaseline {
  SyntheticBaseline({
    required this.corpus,
    required this.census,
    required this.classification,
  });

  final Map<String, String> corpus;
  final Map<String, Object?> census;
  final Map<String, Object?> classification;

  int get total => parse().length;

  List<JqFixture> parse() => [
    for (final entry in corpus.entries)
      ...parseFixtures(entry.value, source: entry.key),
  ];

  List<int> get censusBytes => utf8.encode(jsonEncode(census));
  List<int> get classificationBytes => utf8.encode(jsonEncode(classification));

  /// Integrity metadata recorded for the given payload bytes.
  List<int> integrityFor(List<int> census, List<int> classification) =>
      utf8.encode(
        jsonEncode({
          'format': 'zaru-jq-reference-integrity-v1',
          'census': {'path': 'census.json', 'sha256': sha256Hex(census)},
          'classification': {
            'path': 'classification.json',
            'sha256': sha256Hex(classification),
          },
        }),
      );

  Baseline verify({
    List<int>? integrity,
    List<int>? censusPayload,
    List<int>? classificationPayload,
    int? expectedTotal,
  }) => verifyBaseline(
    integrityBytes: integrity ?? integrityFor(censusBytes, classificationBytes),
    censusBytes: censusPayload ?? censusBytes,
    classificationBytes: classificationPayload ?? classificationBytes,
    corpus: corpus,
    expectedTotal: expectedTotal ?? total,
  );
}

/// Builds a baseline for [corpus]. [facts] overrides the default primary fact
/// of an ID; [classes] overrides its classification (default M1-core).
SyntheticBaseline synthetic(
  Map<String, String> corpus, {
  Map<String, Map<String, Object?>> facts = const {},
  Map<String, String> classes = const {},
}) {
  final fixtures = [
    for (final entry in corpus.entries)
      ...parseFixtures(entry.value, source: entry.key),
  ];
  final cases = <String, Object?>{};
  for (final fixture in fixtures) {
    final compileError = fixture.kind == FixtureKind.compileError;
    final fact = <String, Object?>{
      'compiled': !compileError,
      'outputPrefix': compileError ? <Object?>[] : fixture.outputs,
      'diagnostics': compileError
          ? [fixture.diagnostics.join('\n'), 'jq: 1 compile error']
          : <Object?>[],
      'terminal': compileError ? 'compileError' : 'exhausted',
      if (!compileError) 'fixtureOutputsMatch': true,
      ...?facts[fixture.id],
    };
    cases[fixture.id] = {'primary': fact};
  }
  Map<String, Object?> artifact(String name) => {'sha256': someDigest};
  return SyntheticBaseline(
    corpus: corpus,
    census: {
      'format': 'zaru-jq-reference-census-v1',
      'total': fixtures.length,
      'cases': cases,
      'provenance': {
        'jqVersion': 'jq-1.8.2',
        'jqCommit': pinnedCommit,
        'archiveSha256': pinnedArchive,
        'jq': artifact('jq'),
        'driver': artifact('driver'),
        'library': artifact('library'),
        'driverSource': artifact('driverSource'),
      },
    },
    classification: {
      'format': 'zaru-reference-classification-v1',
      'total': fixtures.length,
      'cases': [
        for (final fixture in fixtures)
          {
            'id': fixture.id,
            'kind': fixture.kind.name,
            'classification': classes[fixture.id] ?? 'M1-core-candidate',
          },
      ],
    },
  );
}

/// The terminal fact of a recorded runtime error carrying a string value.
Map<String, Object?> runtimeErrorFact(String message) => {
  'terminal': 'runtimeError',
  'errorWire': jsonEncode(['string', message]),
  'errorValueText': jsonEncode(message),
};

/// Parses a one-fixture program and runs it against the synthetic baseline.
CaseVerdict runOne(
  String fixtureText, {
  Map<String, Object?> fact = const {},
  String source = 'jq.test',
}) {
  final baseline = synthetic(
    {source: fixtureText},
    facts: {'$source:1': fact},
  ).verify();
  final fixture = baseline.fixtures.single;
  return runFixture(fixture, baseline.expectations[fixture.id]!);
}
