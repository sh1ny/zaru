@TestOn('vm')
@Tags(['reference'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late Directory temporaryDirectory;
  late Map<String, Object?> payload;
  late Map<String, Object?> cases;
  var sequence = 0;

  Future<ProcessResult> runReference(List<String> arguments) => Process.run(
    'mise',
    <String>['run', 'reference-census', '--', ...arguments],
    runInShell: Platform.isWindows,
  );

  Map<String, Object?> primary(String id) =>
      _object(_object(cases[id])['primary']);

  Future<Map<String, Object?>> probe(String program, String input) async {
    final stem = '${temporaryDirectory.path}/probe-${sequence++}';
    final request = File('$stem-request.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{'program': program, 'input': input}),
      );
    final output = File('$stem-result.json');
    final result = await runReference(<String>[
      '--probe',
      request.path,
      '--output',
      output.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return _object(jsonDecode(output.readAsStringSync()));
  }

  Future<void> expectRejected(
    Map<String, Object?> request,
    List<String> options,
    String errorCode,
  ) async {
    final stem = '${temporaryDirectory.path}/rejected-${sequence++}';
    final input = File('$stem-request.json')
      ..writeAsStringSync(jsonEncode(request));
    final output = File('$stem-result.json');
    final result = await runReference(<String>[
      '--probe',
      input.path,
      '--output',
      output.path,
      ...options,
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains(errorCode));
    expect(
      output.existsSync(),
      isFalse,
      reason: 'An uncertain capture must not publish an output.',
    );
  }

  setUpAll(() async {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'zaru-reference-census-',
    );
    final output = File('${temporaryDirectory.path}/census.json');
    final result = await runReference(<String>['--output', output.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    payload = _object(jsonDecode(output.readAsStringSync()));
    cases = _object(payload['cases']);
  });

  tearDownAll(() => temporaryDirectory.deleteSync(recursive: true));

  test('Census covers exactly the pinned stable fixture IDs', () {
    final expected = <String>[
      for (final source in <String>['jq.test', 'man.test'])
        for (final fixture in parseFixtures(
          File('test/conformance/$source').readAsStringSync(),
          source: source,
        ))
          fixture.id,
    ]..sort();
    final actual = cases.keys.toList()..sort();
    expect(expected, hasLength(781));
    expect(actual, expected);
    expect(payload['total'], expected.length);
  });

  test('Census observes destructuring error values rather than comments', () {
    for (final id in <String>[
      'jq.test:945',
      'jq.test:949',
      'jq.test:953',
      'jq.test:957',
    ]) {
      final fact = primary(id);
      expect(fact['outputPrefix'], isEmpty, reason: id);
      expect(fact['terminal'], 'runtimeError', reason: id);
      expect(
        fact['errorValue'],
        'Cannot index array with string ("a")',
        reason: id,
      );
    }
  });

  test('Census retains actual caught outputs and normal termination', () {
    final fact = primary('jq.test:1448');
    expect(fact['outputPrefix'], <String>[
      r'["foo","Cannot index number with string (\"a\")",3]',
    ]);
    expect(fact['terminal'], 'exhausted');
  });

  test('Census retains the original diagnostic source and caret span', () {
    final fixture = parseFixtures(
      File('test/conformance/jq.test').readAsStringSync(),
      source: 'jq.test',
    ).singleWhere((fixture) => fixture.id == 'jq.test:63');
    final fact = primary(fixture.id);
    expect(fact['terminal'], 'compileError');
    final diagnostics = (fact['diagnostics']! as List<Object?>).cast<String>();
    final lastError = diagnostics.lastWhere(
      (message) => message.startsWith('jq: error'),
    );
    expect(lastError.trimRight(), fixture.diagnostics.join('\n'));
  });

  test('Census resolves the complete pinned module environment', () {
    final fact = primary('jq.test:1900');
    expect(fact['outputPrefix'], <String>['["a","b","c","a"]']);
    expect(fact['terminal'], 'exhausted');
  });

  test('Probe retains output before an uncaught error', () async {
    final fact = _object((await probe('1, error("bad")', 'null'))['primary']);
    expect(fact['outputPrefix'], <String>['1']);
    expect(fact['terminal'], 'runtimeError');
    expect(fact['errorValue'], 'bad');
  });

  test(
    'Probe distinguishes null error payload from normal exhaustion',
    () async {
      final failed = _object((await probe('error(null)', 'null'))['primary']);
      final empty = _object((await probe('empty', 'null'))['primary']);
      expect(failed['terminal'], 'runtimeError');
      expect(failed.containsKey('errorValue'), isTrue);
      expect(failed['errorValue'], isNull);
      expect(empty['terminal'], 'exhausted');
      expect(empty.containsKey('errorValue'), isFalse);
    },
  );

  test('Probe preserves typed non-string error payloads', () async {
    final fact = _object(
      (await probe(
        'error({code: 7, detail: [false, null]})',
        'null',
      ))['primary'],
    );
    expect(fact['terminal'], 'runtimeError');
    expect(fact['errorValue'], <String, Object?>{
      'code': 7,
      'detail': <Object?>[false, null],
    });
  });

  test('Probe records nonfinite number kinds before printing', () async {
    final fact = _object(
      (await probe('nan, null, infinite', 'null'))['primary'],
    );
    expect(fact['outputPrefix'], <String>[
      'null',
      'null',
      '1.7976931348623157e+308',
    ]);
    expect(fact['outputKinds'], <String>['number', 'null', 'number']);
    expect(fact['outputNumberKinds'], <Object?>[
      'nan',
      null,
      'positiveInfinity',
    ]);
  });

  test('Probe does not narrow raw input numeric literals', () async {
    final fact = _object(
      (await probe('.', '12345678909876543212345'))['primary'],
    );
    expect(fact['outputPrefix'], <String>['12345678909876543212345']);
    expect(fact['terminal'], 'exhausted');
  });

  test('Probe preserves finite decimal origin beyond binary64 range', () async {
    final fact = _object((await probe('.', '1e1000'))['primary']);
    expect(fact['outputPrefix'], <String>['1E+1000']);
    expect(fact['outputNumberKinds'], <String>['literal']);
    final wire = (fact['outputWire']! as List<Object?>).single! as String;
    expect(jsonDecode(wire), <String>['number', 'literal', '1E+1000']);
  });

  test('Probe retains nested nonfinite and exact error numbers', () async {
    final fact = _object(
      (await probe(
        'error({n: nan, precise: 12345678909876543212345})',
        'null',
      ))['primary'],
    );
    expect(fact['terminal'], 'runtimeError');
    expect(fact['errorValueKind'], 'object');
    expect(jsonDecode(fact['errorWire']! as String), <Object?>[
      'object',
      <Object?>[
        <Object?>[
          'n',
          <String>['number', 'nan'],
        ],
        <Object?>[
          'precise',
          <String>['number', 'literal', '12345678909876543212345'],
        ],
      ],
    ]);
  });

  test('Missing pinned modules cannot manufacture a capture', () async {
    await expectRejected(
      <String, Object?>{'program': 'import "a" as a; a::a', 'input': 'null'},
      <String>['--modules', '${temporaryDirectory.path}/missing-modules'],
      'reference_modules_missing',
    );
  });

  test('Unverified executable cannot publish reference facts', () async {
    final binary = File('${temporaryDirectory.path}/unverified-jq')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    await expectRejected(
      <String, Object?>{'program': '.', 'input': 'null'},
      <String>['--jq', binary.path],
      'reference_binary_hash_mismatch',
    );
  });

  test('Changed pinned source cannot publish reference facts', () async {
    final source = Directory('${temporaryDirectory.path}/changed-source');
    _copyDirectory(Directory('.dart_tool/reference/jq-1.8.2'), source);
    File('${source.path}/src/parser.y').writeAsStringSync(
      '\n/* deliberately changed reference input */\n',
      mode: FileMode.append,
    );
    await expectRejected(
      <String, Object?>{'program': '.', 'input': 'null'},
      <String>['--source', source.path],
      'reference_source_hash_mismatch',
    );
  });

  test('Capture prefix mismatch fails before publication', () async {
    await expectRejected(
      <String, Object?>{
        'program': '1, error("bad")',
        'input': 'null',
        'expectedPrefix': <String>['999'],
      },
      const <String>[],
      'reference_capture_mismatch',
    );
  });
}

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  final pending = <(Directory, Directory)>[(source, destination)];
  while (pending.isNotEmpty) {
    final (from, to) = pending.removeLast();
    for (final entity in from.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      final target = '${to.path}/$name';
      if (entity is File) {
        entity.copySync(target);
      } else if (entity is Directory) {
        final child = Directory(target)..createSync();
        pending.add((entity, child));
      } else {
        throw StateError('Unexpected reference source link: ${entity.path}');
      }
    }
  }
}
