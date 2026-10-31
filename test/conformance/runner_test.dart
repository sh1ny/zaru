@TestOn('vm')
@Tags(['conformance'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final fixtures = <JqFixture>[
    for (final name in ['jq.test', 'man.test'])
      ...parseFixtures(
        File('test/conformance/$name').readAsStringSync(),
        source: name,
        origin: name == 'man.test'
            ? FixtureOrigin.generatedManual
            : FixtureOrigin.upstreamTests,
      ),
  ];
  final results = <String, String>{
    for (final fixture in fixtures) fixture.id: 'notRun',
  };

  tearDownAll(() {
    final failed = results.values.where((status) => status == 'failed').length;
    final report = <String, Object?>{
      'schemaVersion': 1,
      'upstreamTag': 'jq-1.8.2',
      'upstreamCommit': '34f7186b86743a083a589741b6cea95293524108',
      'milestone': 'M0',
      'passed': 0,
      'total': fixtures.length,
      'failed': failed,
      'notRun': fixtures.length - failed,
      'skipped': 0,
      'runnable': fixtures.where((fixture) => fixture.isRunnable).length,
      'nonRunnable': fixtures.where((fixture) => !fixture.isRunnable).length,
      'sources': {
        for (final source in ['jq.test', 'man.test'])
          source: fixtures.where((fixture) => fixture.source == source).length,
      },
      'cases': [
        for (final fixture in fixtures)
          {
            'id': fixture.id,
            'source': fixture.source,
            'line': fixture.line,
            'kind': fixture.kind.name,
            'origin': fixture.origin.name,
            'runnable': fixture.isRunnable,
            'problems': [for (final problem in fixture.problems) problem.name],
            'status': results[fixture.id],
            'reason': fixture.isRunnable
                ? 'evaluatorNotImplemented'
                : 'nonRunnableFixture',
          },
      ],
    };
    // Keep the census visible even if writing the report itself fails.
    try {
      Directory('build').createSync(recursive: true);
      File('build/conformance-report.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    } finally {
      print(
        '0 / ${fixtures.length} jq tests passing '
        '($failed failed, ${fixtures.length - failed} not run, 0 skipped)',
      );
      print('Conformance report: build/conformance-report.json');
    }
  });

  for (final fixture in fixtures) {
    test(fixture.id, () {
      results[fixture.id] = 'failed';
      if (!fixture.isRunnable) {
        fail(
          '${fixture.id}: non-runnable fixture: '
          '${fixture.problems.map((problem) => problem.name).join(', ')}. '
          'Retained in the denominator; not skipped or passed.',
        );
      }
      fail(
        '${fixture.id}: no jq evaluator exists at M0. '
        '${fixture.kind.name} is unimplemented; '
        'an expected compile error is not evidence of conformance.',
      );
    });
  }
}
