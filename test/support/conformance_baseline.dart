// The frozen reference baseline as the conformance runner consumes it.
//
// Browser-safe: it validates bytes and text it is given and never reads files
// or starts jq. The IO wrappers live in tool/ and test/conformance/.
import 'dart:convert';

import 'package:zaru/src/json_decoder.dart';

import '../../tool/sha256.dart';
import '../conformance/fixtures.dart';

/// The classification values that make a case part of M1 acceptance: grammar
/// and builtin dependencies inside the core subset, including the core
/// undefined-name diagnostics (design D6, reference-inventory.md "Task 3.4").
const m1AcceptanceClassifications = <String>{
  'M1-core-candidate',
  'core-undefined-name-diagnostic',
};

/// Every classification value the frozen manifest may contain.
const knownClassifications = <String>{
  'M1-core-candidate',
  'core-undefined-name-diagnostic',
  'explicit-deferred-dependency',
};

/// How a case ended, separately for normal exhaustion and failure kinds.
enum Termination { exhausted, runtimeError, compileError, notObserved }

/// A baseline, floor or report that cannot be trusted.
final class BaselineFailure implements Exception {
  const BaselineFailure(this.code, this.detail);

  /// Stable machine-readable prefix, for example `reference_integrity_mismatch`.
  final String code;
  final String detail;

  String get message => '$code: $detail';

  @override
  String toString() => message;
}

/// What the pinned jq reference recorded for one case.
final class ReferenceExpectation {
  const ReferenceExpectation({
    required this.kind,
    required this.terminal,
    this.errorValue,
  });

  final FixtureKind kind;

  /// [Termination.exhausted], [Termination.runtimeError] or
  /// [Termination.compileError].
  final Termination terminal;

  /// The recorded jq error value (private value domain) when [terminal] is
  /// [Termination.runtimeError]; `null` is a legitimate error value.
  final Object? errorValue;
}

/// A verified baseline.
final class Baseline {
  const Baseline({
    required this.fixtures,
    required this.expectations,
    required this.classifications,
    required this.censusSha256,
    required this.classificationSha256,
  });

  /// Every fixture in corpus order.
  final List<JqFixture> fixtures;
  final Map<String, ReferenceExpectation> expectations;
  final Map<String, String> classifications;
  final String censusSha256;
  final String classificationSha256;

  Set<String> get ids => {for (final fixture in fixtures) fixture.id};

  /// The M1 acceptance set, derived only from the frozen classification.
  Set<String> get acceptanceIds => {
    for (final entry in classifications.entries)
      if (m1AcceptanceClassifications.contains(entry.value)) entry.key,
  };
}

const _integrityFormat = 'zaru-jq-reference-integrity-v1';
const _censusFormat = 'zaru-jq-reference-census-v1';
const _classificationFormat = 'zaru-reference-classification-v1';
const _floorFormat = 'zaru-conformance-floor-v1';
const _jqVersion = 'jq-1.8.2';
const _jqCommit = '34f7186b86743a083a589741b6cea95293524108';
const _archiveSha256 =
    '332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c';
final _digestPattern = RegExp(r'^[0-9a-f]{64}$');

/// Verifies the frozen artifacts and derives a [Baseline].
///
/// Checks, without any native tool: the recorded SHA-256 of both payloads, the
/// pinned jq provenance, exactly [expectedTotal] stable fixture IDs in each
/// artifact (no duplicates, no extras), every case's facts against its
/// fixture, and that each classification is a reviewed value. Fixtures are
/// parsed from [corpus] (source name to text, in corpus order).
Baseline verifyBaseline({
  required List<int> integrityBytes,
  required List<int> censusBytes,
  required List<int> classificationBytes,
  required Map<String, String> corpus,
  int expectedTotal = 781,
}) {
  final integrity = _object(
    _decode(integrityBytes, 'integrity', 'reference_integrity_invalid'),
    'integrity',
    'reference_integrity_invalid',
  );
  if (integrity['format'] != _integrityFormat) {
    throw const BaselineFailure(
      'reference_integrity_invalid',
      'unknown format',
    );
  }
  final censusDigest = _checkDigest(integrity, 'census', censusBytes);
  final classificationDigest = _checkDigest(
    integrity,
    'classification',
    classificationBytes,
  );

  final census = _object(
    _decode(censusBytes, 'census', 'reference_census_invalid'),
    'census',
    'reference_census_invalid',
  );
  if (census['format'] != _censusFormat || census['total'] != expectedTotal) {
    throw const BaselineFailure(
      'reference_census_invalid',
      'format or total differs',
    );
  }
  final cases = _object(census['cases'], 'cases', 'reference_census_invalid');
  final fixtures = <JqFixture>[
    for (final entry in corpus.entries)
      ...parseFixtures(
        entry.value,
        source: entry.key,
        origin: entry.key == 'man.test'
            ? FixtureOrigin.generatedManual
            : FixtureOrigin.upstreamTests,
      ),
  ];
  final expectedIds = {for (final fixture in fixtures) fixture.id};
  _verifyProvenance(
    _object(census['provenance'], 'provenance', 'reference_census_invalid'),
  );
  if (expectedIds.length != expectedTotal ||
      fixtures.length != expectedTotal ||
      cases.length != expectedTotal ||
      !cases.keys.toSet().containsAll(expectedIds) ||
      !expectedIds.containsAll(cases.keys)) {
    throw const BaselineFailure(
      'reference_census_invalid',
      'stable fixture IDs differ',
    );
  }
  final expectations = <String, ReferenceExpectation>{};
  for (final fixture in fixtures) {
    final entry = _object(
      cases[fixture.id],
      fixture.id,
      'reference_census_invalid',
    );
    expectations[fixture.id] = _expectation(
      fixture,
      _object(
        entry['primary'],
        '${fixture.id}.primary',
        'reference_census_invalid',
      ),
    );
  }

  final classification = _object(
    _decode(
      classificationBytes,
      'classification',
      'reference_classification_invalid',
    ),
    'classification',
    'reference_classification_invalid',
  );
  final rows = classification['cases'];
  final classes = <String, String>{};
  var wellFormed =
      classification['format'] == _classificationFormat &&
      classification['total'] == expectedTotal &&
      rows is List<Object?> &&
      rows.length == expectedTotal;
  if (wellFormed) {
    for (final row in rows) {
      final id = row is Map<String, Object?> ? row['id'] : null;
      final value = row is Map<String, Object?> ? row['classification'] : null;
      if (id is! String ||
          value is! String ||
          !knownClassifications.contains(value) ||
          classes.containsKey(id)) {
        wellFormed = false;
        break;
      }
      classes[id] = value;
    }
  }
  if (!wellFormed ||
      classes.length != expectedTotal ||
      !classes.keys.toSet().containsAll(expectedIds)) {
    throw const BaselineFailure(
      'reference_classification_invalid',
      'stable fixture IDs or classification values differ',
    );
  }
  return Baseline(
    fixtures: List.unmodifiable(fixtures),
    expectations: Map.unmodifiable(expectations),
    classifications: Map.unmodifiable(classes),
    censusSha256: censusDigest,
    classificationSha256: classificationDigest,
  );
}

/// Parses the committed passed-ID floor: a sorted, duplicate-free list of
/// stable IDs, all of which exist in the baseline.
Set<String> parseFloor(String text, Set<String> knownIds) {
  const code = 'conformance_floor_invalid';
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const BaselineFailure(code, 'not JSON');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['format'] != _floorFormat ||
      decoded['passed'] is! List<Object?>) {
    throw const BaselineFailure(code, 'unknown format');
  }
  final ids = <String>[];
  for (final id in decoded['passed']! as List<Object?>) {
    if (id is! String) throw const BaselineFailure(code, 'ID is not a string');
    if (!knownIds.contains(id)) {
      throw BaselineFailure(code, 'unknown stable ID $id');
    }
    if (ids.isNotEmpty && ids.last.compareTo(id) >= 0) {
      throw BaselineFailure(code, 'IDs are not sorted and unique at $id');
    }
    ids.add(id);
  }
  return Set.unmodifiable(ids);
}

Object? _decode(List<int> bytes, String name, String code) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw BaselineFailure(code, '$name: ${error.message}');
  }
}

Map<String, Object?> _object(Object? value, String name, String code) {
  if (value is Map<String, Object?>) return value;
  throw BaselineFailure(code, '$name is not an object');
}

String _checkDigest(
  Map<String, Object?> integrity,
  String name,
  List<int> bytes,
) {
  final entry = _object(integrity[name], name, 'reference_integrity_invalid');
  final recorded = entry['sha256'];
  if (recorded is! String || !_digestPattern.hasMatch(recorded)) {
    throw BaselineFailure(
      'reference_integrity_invalid',
      'malformed digest for $name',
    );
  }
  if (sha256Hex(bytes) != recorded) {
    throw BaselineFailure('reference_integrity_mismatch', name);
  }
  return recorded;
}

void _verifyProvenance(Map<String, Object?> provenance) {
  const code = 'reference_census_invalid';
  if (provenance['jqVersion'] != _jqVersion ||
      provenance['jqCommit'] != _jqCommit ||
      provenance['archiveSha256'] != _archiveSha256) {
    throw const BaselineFailure(code, 'pinned provenance differs');
  }
  for (final key in const ['jq', 'driver', 'library', 'driverSource']) {
    final artifact = _object(provenance[key], 'provenance.$key', code);
    final digest = artifact['sha256'];
    if (digest is! String || !_digestPattern.hasMatch(digest)) {
      throw BaselineFailure(code, 'provenance.$key digest');
    }
  }
}

/// Checks one primary observation against its fixture kind and derives the
/// expectation zaru must meet. Never starts jq.
ReferenceExpectation _expectation(
  JqFixture fixture,
  Map<String, Object?> fact,
) {
  Never fail(String what) =>
      throw BaselineFailure('reference_census_invalid', '${fixture.id} $what');
  final terminal = fact['terminal'];
  final compiled = fact['compiled'];
  final prefix = fact['outputPrefix'];
  if (terminal is! String || compiled is! bool || prefix is! List<Object?>) {
    fail('facts');
  }
  final compileError = fixture.kind == FixtureKind.compileError;
  if (compileError != (terminal == 'compileError') ||
      compiled == compileError) {
    fail('facts');
  }
  if (!const {'exhausted', 'runtimeError', 'compileError'}.contains(terminal)) {
    fail('facts');
  }
  final hasError = fact.containsKey('errorWire');
  if (hasError != (terminal == 'runtimeError')) fail('facts');
  if (compileError && prefix.isNotEmpty) fail('facts');
  final diagnostics = fact['diagnostics'];
  if (diagnostics is! List<Object?> || (compileError && diagnostics.isEmpty)) {
    fail('facts');
  }
  if (!compileError &&
      (fact['fixtureOutputsMatch'] != true ||
          prefix.length != fixture.outputs.length)) {
    fail('facts');
  }
  if (compileError) {
    return ReferenceExpectation(
      kind: fixture.kind,
      terminal: Termination.compileError,
    );
  }
  if (terminal == 'exhausted') {
    return ReferenceExpectation(
      kind: fixture.kind,
      terminal: Termination.exhausted,
    );
  }
  // The error value is compared as parsed JSON text so a null error and a
  // numeric error keep their exact form; the wire tag is only evidence.
  final text = fact['errorValueText'];
  if (text is! String) fail('lacks a recorded error value');
  final Object? value;
  try {
    value = decodeJqJson(text);
  } on FormatException {
    fail('has an unreadable error value');
  }
  return ReferenceExpectation(
    kind: fixture.kind,
    terminal: Termination.runtimeError,
    errorValue: value,
  );
}
