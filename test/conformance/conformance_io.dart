// File-system wrappers around the browser-safe conformance logic.
//
// This library reads checked-in files and writes the generated report. It
// starts no process: neither jq nor the reference driver is ever invoked.
import 'dart:convert';
import 'dart:io';

import '../support/conformance_baseline.dart';
import '../support/conformance_run.dart';

const defaultIntegrityPath = 'test/conformance/reference/integrity.json';
const defaultCensusPath = 'test/conformance/reference/census.json';
const defaultClassificationPath =
    'test/conformance/reference/classification.json';
const defaultFloorPath = 'test/conformance/floor.json';
const defaultReportPath = 'build/conformance-report.json';

/// The pinned corpus files, in corpus order.
const corpusPaths = <String, String>{
  'jq.test': 'test/conformance/jq.test',
  'man.test': 'test/conformance/man.test',
};

/// Locations of the frozen reference artifacts.
final class BaselinePaths {
  const BaselinePaths({
    this.integrity = defaultIntegrityPath,
    this.census = defaultCensusPath,
    this.classification = defaultClassificationPath,
  });

  final String integrity;
  final String census;
  final String classification;
}

/// Reads [path] as bytes or fails as a missing baseline artifact.
List<int> readBytes(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw BaselineFailure('reference_integrity_missing', path);
  }
  return file.readAsBytesSync();
}

/// Reads and verifies the frozen baseline against the pinned corpus.
Baseline loadVerifiedBaseline([BaselinePaths paths = const BaselinePaths()]) =>
    verifyBaseline(
      integrityBytes: readBytes(paths.integrity),
      censusBytes: readBytes(paths.census),
      classificationBytes: readBytes(paths.classification),
      corpus: {
        for (final entry in corpusPaths.entries)
          entry.key: utf8.decode(readBytes(entry.value)),
      },
    );

/// Reads the committed floor.
Set<String> loadFloor(String path, Set<String> knownIds) {
  final file = File(path);
  if (!file.existsSync()) {
    throw BaselineFailure('conformance_floor_invalid', 'missing $path');
  }
  return parseFloor(file.readAsStringSync(), knownIds);
}

/// Executes every fixture of [baseline] with the real engine.
Map<String, CaseVerdict> executeCorpus(
  Baseline baseline, {
  void Function(int done, int total)? progress,
}) {
  final verdicts = <String, CaseVerdict>{};
  var done = 0;
  for (final fixture in baseline.fixtures) {
    verdicts[fixture.id] = runFixture(
      fixture,
      baseline.expectations[fixture.id]!,
    );
    progress?.call(++done, baseline.fixtures.length);
  }
  return verdicts;
}

/// A run identity no earlier report can share.
String newRunId() => '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';

/// Writes the generated report, creating its directory.
void writeReport(String path, Map<String, Object?> json) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}
