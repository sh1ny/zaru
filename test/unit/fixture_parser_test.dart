import 'package:test/test.dart';

import '../conformance/fixtures.dart';

List<JqFixture> parse(String text) =>
    parseFixtures(text, source: 'sample.test');

void main() {
  group('jq fixture protocol', () {
    test('retains separate outputs in order, including duplicate values', () {
      final fixture = parse('.[]\n[1,1,2]\n1\n1\n2\n\n').single;
      expect(fixture.input, '[1,1,2]');
      expect(fixture.outputs, ['1', '1', '2']);
      expect(fixture.kind, FixtureKind.evaluation);
      expect(fixture.isRunnable, isTrue);
    });

    test('empty output is a valid zero-result expectation', () {
      final fixtures = parse('empty\nnull\n\n.\n42\n42\n');
      expect(fixtures, hasLength(2));
      expect(fixtures.first.outputs, isEmpty);
      expect(fixtures.first.isRunnable, isTrue);
      expect(fixtures.last.input, '42');
    });

    test(
      'comments and blank lines are boundaries, not arbitrary whitespace',
      () {
        final fixtures = parse(
          '# heading\n \t\n.\n1\n1\n\t# boundary\n.\n2\n2\n',
        );
        expect(fixtures.map((fixture) => fixture.id), [
          'sample.test:3',
          'sample.test:7',
        ]);
        expect(fixtures.map((fixture) => fixture.outputs), [
          ['1'],
          ['2'],
        ]);
      },
    );

    test('the input is the next physical line, even a comment', () {
      final fixture = parse('.\n# not input\n1\n\n').single;
      expect(fixture.input, '# not input');
      expect(fixture.outputs, ['1']);
      expect(fixture.problems, [FixtureProblem.invalidInput]);
      expect(fixture.rawLines, ['.', '# not input', '1']);
    });

    test('blank input is malformed rather than silently skipped', () {
      final fixture = parse('.\n\n1\n\n').single;
      expect(fixture.input, '');
      expect(fixture.outputs, ['1']);
      expect(fixture.problems, [FixtureProblem.invalidInput]);
    });

    test('compile errors retain multiline diagnostics verbatim', () {
      final fixture = parse(
        '%%FAIL\n{\njq: error: unexpected EOF\n    {\n    ^\n\n',
      ).single;
      expect(fixture.kind, FixtureKind.compileError);
      expect(fixture.input, isNull);
      expect(fixture.outputs, isEmpty);
      expect(fixture.diagnostics, [
        'jq: error: unexpected EOF',
        '    {',
        '    ^',
      ]);
      expect(fixture.checkDiagnostic, isTrue);
      expect(fixture.isRunnable, isTrue);
      expect(fixture.line, 2);
    });

    test('IGNORE MSG still expects a compile failure and retains its text', () {
      final fixture = parse(
        '%%FAIL IGNORE MSG\nwat;\nany diagnostic\n\n',
      ).single;
      expect(fixture.kind, FixtureKind.compileError);
      expect(fixture.checkDiagnostic, isFalse);
      expect(fixture.diagnostics, ['any diagnostic']);
      expect(fixture.isRunnable, isTrue);
    });

    test('IGNORE MSG allows no diagnostic lines', () {
      final fixture = parse('%%FAIL IGNORE MSG\nwat;\n\n').single;
      expect(fixture.diagnostics, isEmpty);
      expect(fixture.isRunnable, isTrue);
    });

    test('checked compile errors without diagnostics are malformed', () {
      final fixture = parse('%%FAIL\nwat;\n\n').single;
      expect(fixture.problems, [FixtureProblem.missingDiagnostic]);
    });

    test('successive markers follow upstream last-marker-wins behavior', () {
      final fixture = parse(
        '%%FAIL\n# comment\n%%FAIL IGNORE MSG\nwat;\n\n',
      ).single;
      expect(fixture.markers, ['%%FAIL', '%%FAIL IGNORE MSG']);
      expect(fixture.checkDiagnostic, isFalse);
      expect(fixture.line, 4);
    });

    test('conditional and version checks remain programs, not skip rules', () {
      const program = 'if have_decnum then . else error("jq version") end';
      final fixture = parse('$program\n1\n1\n\n').single;
      expect(fixture.program, program);
      expect(fixture.outputs, ['1']);
      expect(fixture.isRunnable, isTrue);
    });

    test('preprocessor-looking comments do not conditionally drop cases', () {
      final fixtures = parse(
        '#if jq-9.0\n.\n1\n1\n\n#else\n.\n2\n2\n\n#endif\n',
      );
      expect(fixtures, hasLength(2));
      expect(fixtures.map((fixture) => fixture.input), ['1', '2']);
    });

    test('!!FAIL is not an invented alias for upstream %%FAIL', () {
      final fixture = parse('!!FAIL\nwat;\nerror text\n\n').single;
      expect(fixture.kind, FixtureKind.unsupportedDirective);
      expect(fixture.problems, [FixtureProblem.unsupportedDirective]);
      expect(fixture.rawLines, ['!!FAIL', 'wat;', 'error text']);
    });

    test('unknown version markers remain visible and non-runnable', () {
      final fixtures = parse('%%VERSION 9\n.\nnull\nnull\n\n.\n1\n1');
      expect(fixtures, hasLength(2));
      expect(fixtures.first.kind, FixtureKind.unsupportedDirective);
      expect(fixtures.first.rawLines, ['%%VERSION 9', '.', 'null', 'null']);
      expect(fixtures.last.outputs, ['1']);
    });

    test('malformed input and output remain in the case census', () {
      final fixtures = parse('.\n{broken\n[1,]\n\n.\nnull\nnull\n');
      expect(fixtures, hasLength(2));
      expect(fixtures.first.problems, [
        FixtureProblem.invalidInput,
        FixtureProblem.invalidOutput,
      ]);
      expect(fixtures.first.input, '{broken');
      expect(fixtures.first.outputs, ['[1,]']);
      expect(fixtures.last.isRunnable, isTrue);
    });

    test('BOM and jq non-finite literals are retained without conversion', () {
      final fixture = parse(
        '.\n\uFEFF[Infinity,-Infinity,NaN,-NaN,nan]\n[null]\n',
      ).single;
      expect(fixture.input, '\uFEFF[Infinity,-Infinity,NaN,-NaN,nan]');
      expect(fixture.isRunnable, isTrue);
    });

    test('large decimal literals retain every source digit', () {
      const number = '1234567890123456789012345678901234567890.000';
      final fixture = parse('.\n$number\n$number\n').single;
      expect(fixture.input, number);
      expect(fixture.outputs, [number]);
      expect(fixture.isRunnable, isTrue);
    });

    test(
      'non-finite normalization does not alter strings or accept payloads',
      () {
        final fixtures = parse('.\n"NaN"\n"-Infinity"\n\n.\nNaN100\nnull\n');
        expect(fixtures.first.input, '"NaN"');
        expect(fixtures.first.outputs, ['"-Infinity"']);
        expect(fixtures.first.isRunnable, isTrue);
        expect(fixtures.last.problems, [FixtureProblem.invalidInput]);
      },
    );

    test('EOF closes outputs without requiring a trailing blank line', () {
      final fixture = parse('.[]\n[1,2]\n1\n2').single;
      expect(fixture.outputs, ['1', '2']);
      expect(fixture.isRunnable, isTrue);
    });

    test('EOF after input represents empty output', () {
      final fixture = parse('empty\nnull').single;
      expect(fixture.outputs, isEmpty);
      expect(fixture.isRunnable, isTrue);
    });

    test('EOF after a program retains a missing-input case', () {
      final fixture = parse('.').single;
      expect(fixture.input, isNull);
      expect(fixture.problems, [FixtureProblem.missingInput]);
    });

    test('dangling newline-terminated failure markers are not discarded', () {
      final fixture = parse('%%FAIL\n# EOF comment\n').single;
      expect(fixture.problems, [FixtureProblem.missingProgram]);
      expect(fixture.rawLines, ['%%FAIL']);
      expect(fixture.id, 'sample.test:1');
    });

    test('an unterminated marker is not recognized by upstream', () {
      final fixture = parse('%%FAIL').single;
      expect(fixture.kind, FixtureKind.unsupportedDirective);
      expect(fixture.rawLines, ['%%FAIL']);
    });

    test('backslashes do not join physical program or input lines', () {
      final fixture = parse('. \\\nnull\n1\n').single;
      expect(fixture.program, '. \\');
      expect(fixture.input, 'null');
      expect(fixture.outputs, ['1']);
      final multiline = parse('.\n[1,\\\n2]\n\n').single;
      expect(multiline.input, '[1,\\');
      expect(multiline.outputs, ['2]']);
      expect(multiline.problems, [
        FixtureProblem.invalidInput,
        FixtureProblem.invalidOutput,
      ]);
    });

    test('CRLF has the same physical-line boundaries', () {
      final fixture = parse('%%FAIL\r\nwat;\r\nmessage\r\n\r\n').single;
      expect(fixture.program, 'wat;');
      expect(fixture.diagnostics, ['message']);
      expect(fixture.isRunnable, isTrue);
    });

    test('generated manual cases are runnable data, not discarded recipes', () {
      final fixture = parseFixtures(
        '.\nnull\nnull\n',
        source: 'man.test',
        origin: FixtureOrigin.generatedManual,
      ).single;
      expect(fixture.origin, FixtureOrigin.generatedManual);
      expect(fixture.isRunnable, isTrue);
      expect(fixture.outputs, ['null']);
    });

    test('commented-out generated recipes are not active upstream cases', () {
      expect(parse('# program | eval\n# null\n# true\n'), isEmpty);
    });
  });
}
