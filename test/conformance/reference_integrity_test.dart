@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Frozen reference baseline checks. These never start jq or the native
/// driver; they only hash and inspect the checked-in artifacts.
void main() {
  late Directory temporary;

  setUp(
    () => temporary = Directory.systemTemp.createTempSync('zaru-integrity-'),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  Future<ProcessResult> verify(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    <String>['run', 'tool/reference_verify.dart', ...arguments],
  );

  /// Copies the frozen artifacts, applies [mutate] to the census, records
  /// integrity for the copy when [record] is set, and verifies it.
  Future<ProcessResult> verifyCopy(
    void Function(Map<String, Object?> census) mutate, {
    required bool record,
  }) async {
    final census = File('${temporary.path}/census.json');
    final classification = File('${temporary.path}/classification.json');
    final integrity = File('${temporary.path}/integrity.json');
    File(
      'test/conformance/reference/classification.json',
    ).copySync(classification.path);
    final paths = <String>[
      '--integrity',
      integrity.path,
      '--census',
      census.path,
      '--classification',
      classification.path,
    ];
    census.writeAsStringSync(
      File('test/conformance/reference/census.json').readAsStringSync(),
    );
    if (!record) {
      final recorded = await verify(<String>[...paths, '--record']);
      expect(recorded.exitCode, 0, reason: '${recorded.stderr}');
    }
    final decoded =
        jsonDecode(census.readAsStringSync()) as Map<String, Object?>;
    mutate(decoded);
    census.writeAsStringSync(jsonEncode(decoded));
    return verify(<String>[...paths, if (record) '--record']);
  }

  test('Frozen census and classification match recorded integrity', () async {
    final result = await verify(const <String>[]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('Tampered census payload fails its recorded hash', () async {
    final result = await verifyCopy(
      (census) => census['tampered'] = true,
      record: false,
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('reference_integrity_mismatch'));
  });

  test('Missing stable ID is rejected even with a fresh hash', () async {
    final result = await verifyCopy(
      (census) =>
          (census['cases']! as Map<String, Object?>).remove('jq.test:63'),
      record: true,
    );
    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('reference_census_invalid'));
  });

  test('Changed terminal fact is rejected even with a fresh hash', () async {
    final result = await verifyCopy((census) {
      final cases = census['cases']! as Map<String, Object?>;
      final primary =
          (cases['jq.test:63']! as Map<String, Object?>)['primary']!
              as Map<String, Object?>;
      primary['terminal'] = 'exhausted';
    }, record: true);
    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('reference_census_invalid'));
  });
}
