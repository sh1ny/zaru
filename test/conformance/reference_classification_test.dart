@TestOn('vm')
@Tags(['reference'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/reference_classification.dart' show classifyFixture;
import 'fixtures.dart';

void main() {
  late Map<String, Map<String, Object?>> classifications;

  setUpAll(() {
    final fixtures = <JqFixture>[
      for (final source in ['jq.test', 'man.test'])
        ...parseFixtures(
          File('test/conformance/$source').readAsStringSync(),
          source: source,
        ),
    ];
    classifications = <String, Map<String, Object?>>{
      for (final fixture in fixtures) fixture.id: classifyFixture(fixture),
    };
  });

  test('assignment is deferred while equality remains core', () {
    final assignment = classifyFixture(_fixture('.message = "goodbye"'));
    final equality = classifyFixture(_fixture('.message == "goodbye"'));

    expect(assignment['classification'], 'explicit-deferred-dependency');
    expect((assignment['forms'] as List<Object?>), contains('assignment'));
    expect(equality['classification'], 'M1-core-candidate');
    expect((equality['forms'] as List<Object?>), contains('=='));
  });

  test('keyword object keys do not imply module syntax', () {
    final keywordKeys = classifications['jq.test:2042']!;
    final actualImport = classifications['jq.test:1900']!;
    final syntheticKeys = classifyFixture(
      _fixture('{import: .import, foo: .foo}'),
    );

    expect(keywordKeys['classification'], 'M1-core-candidate');
    expect(actualImport['classification'], 'explicit-deferred-dependency');
    expect((keywordKeys['objectKeys'] as List<Object?>), contains('import'));
    expect(syntheticKeys['classification'], 'M1-core-candidate');
    expect(syntheticKeys['objectKeys'], containsAll(<String>['import', 'foo']));
    expect(syntheticKeys['moduleDependencyNames'], isEmpty);
    expect(syntheticKeys['builtins'], isEmpty);
  });

  test('only the approved helper set is an M1 builtin dependency', () {
    final range = classifications['jq.test:2005']!;
    final sort = classifications['jq.test:1673']!;
    final jsonRoundTrip = classifications['jq.test:106']!;
    final approved = _builtin(range, 'range');

    expect(approved['m1'], 'M1-candidate');
    expect(sort['classification'], 'explicit-deferred-dependency');
    expect(_builtin(sort, 'sort')['m1'], 'deferred-builtin');
    expect(jsonRoundTrip['classification'], 'explicit-deferred-dependency');
    expect(_builtin(jsonRoundTrip, 'tojson')['m1'], 'deferred-builtin');
    expect(_builtin(jsonRoundTrip, 'fromjson')['m1'], 'deferred-builtin');
  });

  test('nested and escaped interpolation preserve filter boundaries', () {
    final nested = classifyFixture(
      _fixture(r'"prefix \(.outer | first(nested(.inner)) | needed) suffix"'),
    );
    final escaped = classifyFixture(_fixture(r'"literal \\(notAFilter)"'));

    expect(nested['sourceNames'], containsAll(<String>['nested', 'needed']));
    expect(escaped['sourceNames'], isEmpty);
    expect(escaped['classification'], 'M1-core-candidate');
  });

  test('function-local bindings do not escape into the outer filter', () {
    final validShadow = classifyFixture(
      _fixture(r'. as $x | def f($x): $x; f(2)'),
    );
    final leakedLocal = classifyFixture(_fixture(r'def f: . as $x | $x; $x'));

    expect(validShadow['unboundCoreVariables'], isEmpty);
    expect(leakedLocal['classification'], 'core-undefined-name-diagnostic');
    expect(leakedLocal['unboundCoreVariables'], contains('x'));
  });
  test('multi-parameter definitions keep filter parameters in scope', () {
    for (final id in <String>[
      'jq.test:794',
      'jq.test:808',
      'man.test:945',
      'man.test:952',
    ]) {
      expect(
        classifications[id]!['classification'],
        'M1-core-candidate',
        reason: id,
      );
      expect(classifications[id]!['unknownCoreNames'], isEmpty, reason: id);
      expect(classifications[id]!['unboundCoreVariables'], isEmpty, reason: id);
    }
    expect(
      _builtin(classifications['man.test:952']!, 'empty')['m1'],
      'M1-candidate',
    );
    final scoped = classifyFixture(
      _fixture('def f(length; generator): generator; length'),
    );

    expect(scoped['classification'], 'explicit-deferred-dependency');
    expect(scoped['unboundCoreVariables'], isEmpty);
    expect(_builtin(scoped, 'length')['m1'], 'deferred-builtin');
    expect(scoped['unknownCoreNames'], isEmpty);
  });

  test('comma-separated filter names remain builtin dependencies', () {
    final row = classifyFixture(_fixture('0, length, 1'));
    final withEmpty = classifyFixture(_fixture('0, length, empty'));
    final builtins = row['builtins'] as List<Map<String, Object?>>;

    expect(
      builtins,
      contains(
        predicate<Map<String, Object?>>(
          (builtin) =>
              builtin['name'] == 'length' &&
              builtin['m1'] == 'deferred-builtin',
        ),
      ),
    );
    expect(row['objectKeys'], isEmpty);
    expect(row['classification'], 'explicit-deferred-dependency');
    expect(withEmpty['objectKeys'], isEmpty);
    expect(withEmpty['classification'], 'explicit-deferred-dependency');
    expect(_builtin(withEmpty, 'length')['m1'], 'deferred-builtin');
    expect(_builtin(withEmpty, 'empty')['m1'], 'M1-candidate');
  });

  test('object shorthand context retains real builtin uses', () {
    for (final (id, name) in <(String, String)>[
      ('man.test:324', 'empty'),
      ('man.test:329', 'empty'),
      ('jq.test:754', 'empty'),
      ('jq.test:2241', 'tostring'),
      ('man.test:907', 'last'),
    ]) {
      expect(
        classifications[id]!['builtins'],
        contains(
          predicate<Map<String, Object?>>((builtin) {
            return builtin['name'] == name;
          }),
        ),
        reason: '$id must retain the $name dependency',
      );
    }
  });

  test('interpolation records its implicit text-format dependencies', () {
    for (final id in <String>['jq.test:68', 'man.test:710']) {
      final row = classifications[id]!;
      expect(row['forms'], contains('interpolation'), reason: id);
      _expectBuiltin(row, 'format', 'M1-candidate');
      _expectBuiltin(row, 'tostring', 'M1-candidate');
    }
    final synthetic = classifyFixture(_fixture(r'"value: \(.value)"'));

    expect(synthetic['classification'], 'M1-core-candidate');
    expect(
      _builtin(synthetic, 'format')['dependencies'],
      contains('tostring/0'),
    );
    expect(_builtin(synthetic, 'tostring')['callArities'], <int>[0]);
  });

  test('recursive descent records the recurse dependency', () {
    for (final id in <String>['jq.test:187', 'man.test:146']) {
      final row = classifications[id]!;
      _expectBuiltin(row, 'recurse', 'M1-candidate');
    }
  });

  test('helper dependencies follow the selected builtin overload', () {
    final bareFirst = classifyFixture(_fixture('first'));
    final generatorFirst = classifyFixture(_fixture('first(.)'));
    final mixedFirst = classifyFixture(_fixture('first, first(.)'));
    final bareLast = classifyFixture(_fixture('last'));
    final bytecodedLast = classifyFixture(_fixture('last(.)'));
    final indexedNth = classifyFixture(_fixture('nth(5)'));
    final generatorNth = classifyFixture(_fixture('nth(5; .[])'));

    expect(_builtin(bareFirst, 'first')['callArities'], <int>[0]);
    expect(_builtin(bareFirst, 'first')['dependencies'], isEmpty);
    expect(_builtin(generatorFirst, 'first')['callArities'], <int>[1]);
    expect(
      _builtin(generatorFirst, 'first')['dependencies'],
      containsAll(<String>['label', 'break']),
    );
    expect(_builtin(mixedFirst, 'first')['callArities'], <int>[0, 1]);
    expect(_builtin(mixedFirst, 'first')['m1'], 'M1-candidate');
    expect(
      _builtin(mixedFirst, 'first')['dependencies'],
      containsAll(<String>['label', 'break']),
    );
    expect(_builtin(mixedFirst, 'first')['overloads'], hasLength(2));
    expect(_builtin(bareLast, 'last')['callArities'], <int>[0]);
    expect(_builtin(bareLast, 'last')['dependencies'], isEmpty);
    expect(_builtin(bytecodedLast, 'last')['callArities'], <int>[1]);
    expect(_builtin(bytecodedLast, 'last')['origin'], contains('bytecoded'));
    expect(_builtin(indexedNth, 'nth')['callArities'], <int>[1]);
    expect(_builtin(indexedNth, 'nth')['dependencies'], isEmpty);
    expect(_builtin(generatorNth, 'nth')['callArities'], <int>[2]);
    expect(
      _builtin(generatorNth, 'nth')['dependencies'],
      containsAll(<String>['skip/2', 'first/1', 'error/1']),
    );
  });

  test(
    'value and filter parameters do not shadow builtin callables globally',
    () {
      final valueBinding = classifyFixture(_fixture(r'. as $length | length'));
      final filterParameter = classifyFixture(
        _fixture('def f(length): length; length'),
      );

      _expectBuiltin(valueBinding, 'length', 'deferred-builtin');
      _expectBuiltin(filterParameter, 'length', 'deferred-builtin');
    },
  );

  test('direct non-text format calls stay deferred', () {
    final directFormat = classifyFixture(_fixture('format("html")'));

    expect(_builtin(directFormat, 'format')['m1'], 'deferred-builtin');
    expect(directFormat['classification'], 'explicit-deferred-dependency');
  });

  test('unused definitions do not add callable dependencies', () {
    final unused = classifyFixture(_fixture('def unused: length; .'));
    final used = classifyFixture(_fixture('def used: length; used'));

    expect(unused['classification'], 'M1-core-candidate');
    expect(unused['builtins'], isEmpty);
    expect(used['classification'], 'explicit-deferred-dependency');
    expect(_builtin(used, 'length')['callArities'], <int>[0]);
    expect(_builtin(used, 'length')['m1'], 'deferred-builtin');
  });

  test(
    'unrecognized names remain core undefined names, not deferred builtins',
    () {
      final row = classifyFixture(_fixture('unrecognized_core_name'));

      expect(row['classification'], 'core-undefined-name-diagnostic');
      expect(row['unknownCoreNames'], <String>['unrecognized_core_name']);
      expect(row['builtins'], isEmpty);
    },
  );
}

void _expectBuiltin(Map<String, Object?> row, String name, String status) {
  final builtins = row['builtins'] as List<Map<String, Object?>>;
  expect(
    builtins,
    contains(
      predicate<Map<String, Object?>>(
        (builtin) => builtin['name'] == name && builtin['m1'] == status,
      ),
    ),
    reason: 'Expected $name to be recorded as $status.',
  );
}

Map<String, Object?> _builtin(Map<String, Object?> row, String name) {
  final builtins = row['builtins'] as List<Object?>;
  return builtins.cast<Map<String, Object?>>().singleWhere(
    (builtin) => builtin['name'] == name,
  );
}

JqFixture _fixture(String program) => JqFixture(
  source: 'classifier-test',
  line: 1,
  program: program,
  kind: FixtureKind.evaluation,
  origin: FixtureOrigin.upstreamTests,
  rawLines: <String>[program],
  markers: const <String>[],
  input: 'null',
  outputs: const <String>[],
  diagnostics: const <String>[],
  checkDiagnostic: false,
  problems: const <FixtureProblem>[],
);
