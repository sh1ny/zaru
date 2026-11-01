import 'dart:convert';
import 'dart:io';

import '../test/conformance/fixtures.dart';
import 'sha256.dart';

const _integrityPath = 'test/conformance/reference/integrity.json';
const _censusPath = 'test/conformance/reference/census.json';
const _classificationPath = 'test/conformance/reference/classification.json';
const _integrityFormat = 'zaru-jq-reference-integrity-v1';
const _censusFormat = 'zaru-jq-reference-census-v1';
const _classificationFormat = 'zaru-reference-classification-v1';

void main(List<String> args) {
  try {
    _verify(args);
  } on _VerificationFailure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('reference_verify_failed: $error');
    exitCode = 1;
  }
}

void _verify(List<String> args) {
  var integrityPath = _integrityPath;
  var censusPath = _censusPath;
  var classificationPath = _classificationPath;
  var record = false;
  for (var index = 0; index < args.length; index++) {
    final option = args[index];
    if (option == '--record') {
      record = true;
      continue;
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw _VerificationFailure('reference_verify_usage: $option needs a path');
    }
    final path = args[++index];
    switch (option) {
      case '--integrity':
        integrityPath = path;
      case '--census':
        censusPath = path;
      case '--classification':
        classificationPath = path;
      default:
        throw _VerificationFailure('reference_verify_usage: unknown option $option');
    }
  }
  if (record) {
    // Explicit freeze step: record digests of the reviewed artifacts, then
    // verify them below exactly like an ordinary check.
    final contents = <String, Object?>{
      'format': _integrityFormat,
      'census': <String, Object?>{
        'path': _normalized(censusPath),
        'sha256': _digest(censusPath),
      },
      'classification': <String, Object?>{
        'path': _normalized(classificationPath),
        'sha256': _digest(classificationPath),
      },
    };
    File(integrityPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(contents)}\n',
    );
  }
  final integrity = _readObject(integrityPath);
  if (integrity['format'] != _integrityFormat) {
    throw const _VerificationFailure('reference_integrity_invalid: unknown format');
  }
  final censusEntry = _object(integrity['census'], 'census');
  final classEntry = _object(integrity['classification'], 'classification');
  final recordedCensusPath = _string(censusEntry['path'], 'census.path');
  final recordedClassificationPath = _string(
    classEntry['path'],
    'classification.path',
  );
  if (_normalized(recordedCensusPath) != _normalized(censusPath) ||
      _normalized(recordedClassificationPath) != _normalized(classificationPath)) {
    throw const _VerificationFailure(
      'reference_integrity_invalid: integrity paths do not match requested artifacts',
    );
  }
  _verifyDigest(censusPath, _string(censusEntry['sha256'], 'census.sha256'));
  _verifyDigest(
    classificationPath,
    _string(classEntry['sha256'], 'classification.sha256'),
  );

  final census = _readObject(censusPath);
  if (census['format'] != _censusFormat || census['total'] != 781) {
    throw const _VerificationFailure('reference_census_invalid: format or total differs');
  }
  final cases = _object(census['cases'], 'cases');
  final fixtures = <String, JqFixture>{
    for (final (source, path) in <(String, String)>[
      ('jq.test', 'test/conformance/jq.test'),
      ('man.test', 'test/conformance/man.test'),
    ])
      for (final fixture in parseFixtures(File(path).readAsStringSync(), source: source))
        fixture.id: fixture,
  };
  final expectedIds = fixtures.keys.toSet();
  _verifyProvenance(_object(census['provenance'], 'provenance'));
  if (expectedIds.length != 781 || cases.length != 781 ||
      !cases.keys.toSet().containsAll(expectedIds) ||
      !expectedIds.containsAll(cases.keys)) {
    throw const _VerificationFailure('reference_census_invalid: stable fixture IDs differ');
  }
  for (final id in expectedIds) {
    _verifyFact(id, fixtures[id]!, _object(_object(cases[id], id)['primary'], '$id.primary'));
  }
  final classification = _readObject(classificationPath);
  final classified = classification['cases'];
  final classifiedIds = <String>[
    if (classified is List<Object?>)
      for (final entry in classified)
        if (entry is Map<String, Object?> && entry['id'] is String) entry['id']! as String,
  ];
  if (classification['format'] != _classificationFormat ||
      classification['total'] != 781 ||
      classified is! List<Object?> ||
      classifiedIds.length != classified.length ||
      classifiedIds.length != 781 ||
      classifiedIds.toSet().length != 781 ||
      !classifiedIds.toSet().containsAll(expectedIds)) {
    throw const _VerificationFailure(
      'reference_classification_invalid: stable fixture IDs differ',
    );
  }
}

void _verifyProvenance(Map<String, Object?> provenance) {
  if (provenance['jqVersion'] != 'jq-1.8.2' ||
      provenance['jqCommit'] != '34f7186b86743a083a589741b6cea95293524108' ||
      provenance['archiveSha256'] !=
          '332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c') {
    throw const _VerificationFailure('reference_census_invalid: pinned provenance differs');
  }
  for (final key in <String>['jq', 'driver', 'library', 'driverSource']) {
    final artifact = _object(provenance[key], 'provenance.$key');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(_string(artifact['sha256'], '$key.sha256'))) {
      throw _VerificationFailure('reference_census_invalid: provenance.$key digest');
    }
  }
}

/// Checks one primary observation against its fixture kind and the
/// terminal/compile/error invariants; never re-runs jq.
void _verifyFact(String id, JqFixture fixture, Map<String, Object?> fact) {
  final terminal = fact['terminal'];
  final compiled = fact['compiled'];
  final prefix = fact['outputPrefix'];
  bool fail() => throw _VerificationFailure('reference_census_invalid: $id facts');
  if (terminal is! String || compiled is! bool || prefix is! List<Object?>) fail();
  final compileError = fixture.kind == FixtureKind.compileError;
  if (compileError != (terminal == 'compileError') || compiled == compileError) fail();
  if (!const <String>{'exhausted', 'runtimeError', 'compileError'}.contains(terminal)) fail();
  final hasError = fact.containsKey('errorWire');
  if (hasError != (terminal == 'runtimeError')) fail();
  if (compileError && (prefix as List<Object?>).isNotEmpty) fail();
  final diagnostics = fact['diagnostics'];
  if (diagnostics is! List<Object?> || (compileError && diagnostics.isEmpty)) fail();
  if (!compileError) {
    if (fact['fixtureOutputsMatch'] != true ||
        (prefix as List<Object?>).length != fixture.outputs.length) {
      fail();
    }
  }
}

String _digest(String path) {
  try {
    return sha256Hex(File(path).readAsBytesSync());
  } on FileSystemException {
    throw _VerificationFailure('reference_integrity_failed: could not hash $path');
  }
}

Map<String, Object?> _readObject(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw _VerificationFailure('reference_integrity_missing: $path');
  }
  Object? value;
  try {
    value = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw _VerificationFailure('reference_integrity_invalid: $path: $error');
  }
  return _object(value, path);
}

void _verifyDigest(String path, String expected) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
    throw _VerificationFailure('reference_integrity_invalid: malformed digest for $path');
  }
  final String digest;
  try {
    digest = sha256Hex(File(path).readAsBytesSync());
  } on FileSystemException {
    throw _VerificationFailure('reference_integrity_failed: could not hash $path');
  }
  if (digest != expected) {
    throw _VerificationFailure('reference_integrity_mismatch: $path');
  }
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  throw _VerificationFailure('reference_integrity_invalid: $name is not an object');
}

String _string(Object? value, String name) {
  if (value is String) return value;
  throw _VerificationFailure('reference_integrity_invalid: $name is not a string');
}

String _normalized(String value) => value.replaceAll('\\', '/');

final class _VerificationFailure implements Exception {
  const _VerificationFailure(this.message);
  final String message;
}
