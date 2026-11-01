import 'package:test/test.dart';
import 'package:zaru/src/syntax/diagnostic.dart';
import 'package:zaru/src/syntax/parse_result.dart';
import 'package:zaru/src/syntax/parser.dart';
import 'package:zaru/src/syntax/span.dart';

import 'diagnostic_snapshots.dart';
import 'syntax_support.dart';

/// jq_test.c's comparison for `%%FAIL` fixtures: every expected line must be
/// a prefix of what remains of the actual message, consuming one newline
/// after each, and the actual message must be exhausted at the end.
bool jqTestRuleAccepts(List<String> expectedLines, String actual) {
  var rest = actual;
  for (final line in expectedLines) {
    if (!rest.startsWith(line)) return false;
    rest = rest.substring(line.length);
    if (rest.startsWith('\n')) rest = rest.substring(1);
  }
  return rest.isEmpty;
}

/// The retained message of a failed parse: jq_test.c keeps the last
/// `jq: error` block, which is what a harness must compare.
String lastBlock(String source, {String name = '<top-level>'}) {
  final result = parseProgram(source, name: name);
  expect(result.program, isNull, reason: '$source should not parse');
  return result.report!.lastJqError!;
}

/// A compile-error fixture whose diagnostics come from the parser alone.
final class Fixture {
  const Fixture(this.id, this.source, this.expectedLines);

  /// The jq.test line of the program, as in the pinned reference census.
  final String id;
  final String source;
  final List<String> expectedLines;
}

const parserLevelFixtures = <Fixture>[
  Fixture('jq.test:127', '{(0):1}', [
    'jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 3:',
    '    {(0):1}',
    '      ^',
  ]),
  Fixture('jq.test:133', '{1+2:3}', [
    'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:',
    '    {1+2:3}',
    '     ^^^',
  ]),
  Fixture('jq.test:139', '{non_const:., (0):1}', [
    'jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 16:',
    '    {non_const:., (0):1}',
    '                   ^',
  ]),
  Fixture('jq.test:1934', 'module (.+1); 0', [
    'jq: error: Module metadata must be constant at <top-level>, line 1, column 8:',
    '    module (.+1); 0',
    '           ^^^^^',
  ]),
  Fixture('jq.test:1940', 'module []; 0', [
    'jq: error: Module metadata must be an object at <top-level>, line 1, column 8:',
    '    module []; 0',
    '           ^^',
  ]),
  Fixture('jq.test:1946', 'include "a" (.+1); 0', [
    'jq: error: Module metadata must be constant at <top-level>, line 1, column 13:',
    '    include "a" (.+1); 0',
    '                ^^^^^',
  ]),
  Fixture('jq.test:1952', 'include "a" []; 0', [
    'jq: error: Module metadata must be an object at <top-level>, line 1, column 13:',
    '    include "a" []; 0',
    '                ^^',
  ]),
  Fixture('jq.test:1958', r'include "\ "; 0', [
    r'''jq: error: Invalid escape at line 1, column 4 (while parsing '"\ "') at <top-level>, line 1, column 10:''',
    r'    include "\ "; 0',
    '             ^^',
  ]),
  Fixture('jq.test:1964', r'include "\(a)"; 0', [
    'jq: error: Import path must be constant at <top-level>, line 1, column 9:',
    r'    include "\(a)"; 0',
    '            ^^^^^^',
  ]),
  Fixture('jq.test:1988', '%::wat', [
    "jq: error: syntax error, unexpected '%', expecting end of file at <top-level>, line 1, column 1:",
    '    %::wat',
    '    ^',
  ]),
  Fixture('jq.test:2075', '{', [
    'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 1:',
    '    {',
    '    ^',
  ]),
  Fixture('jq.test:2081', '}', [
    'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:',
    '    }',
    '    ^',
  ]),
  Fixture('jq.test:548', '. as [] | null', [
    "jq: error: syntax error, unexpected ']', expecting BINDING or '[' or '{' at <top-level>, line 1, column 7:",
    '    . as [] | null',
    '          ^',
  ]),
  Fixture('jq.test:554', '. as {} | null', [
    "jq: error: syntax error, unexpected '}' at <top-level>, line 1, column 7:",
    '    . as {} | null',
    '          ^',
  ]),
  Fixture('jq.test:566', '. as {(true):\$foo} | \$foo', [
    'jq: error: Cannot use boolean (true) as object key at <top-level>, line 1, column 8:',
    '    . as {(true):\$foo} | \$foo',
    '           ^^^^',
  ]),
  Fixture('jq.test:63', r'"u\vw"', [
    r'''jq: error: Invalid escape at line 1, column 4 (while parsing '"\v"') at <top-level>, line 1, column 3:''',
    r'    "u\vw"',
    '      ^^',
  ]),
];

void main() {
  group('Preserve jq compile diagnostics', () {
    test('Successful source has no diagnostics', () {
      final result = parseProgram('.');
      expect(result.diagnostics, isEmpty);
      expect(result.report, isNull);
      expect(result.isValid, isTrue);
      expect(result.program, isNotNull);
      expect(result.unsupported, isEmpty);
    });

    test('Lexical diagnostic preserves span and excerpt', () {
      // jq.test:62 -- the invalid escape sequence in a string.
      final result = parseProgram(r'"u\vw"');
      expect(result.program, isNull);
      final report = result.report!;
      expect(report.diagnostics, hasLength(1));
      expect(report.first.kind, DiagnosticKind.lexical);
      expect(
        report.message,
        r'''Invalid escape at line 1, column 4 (while parsing '"\v"')''',
      );
      expect((report.line, report.column), (1, 3));
      expect((report.endLine, report.endColumn), (1, 5));
      expect(report.first.span, const Span(2, 4));
      expect(report.rendered, [
        r'''jq: error: Invalid escape at line 1, column 4 (while parsing '"\v"') at <top-level>, line 1, column 3:'''
            '\n'
            r'    "u\vw"'
            '\n'
            '      ^^',
      ]);
    });

    test('Grammar-derived syntax diagnostics', () {
      // jq.test:547, jq.test:2074 and jq.test:2080.
      final binding = parseProgram('. as [] | null').report!;
      expect(binding.first.kind, DiagnosticKind.syntax);
      expect(
        binding.message,
        "syntax error, unexpected ']', expecting BINDING or '[' or '{'",
      );
      expect((binding.line, binding.column, binding.endColumn), (1, 7, 8));
      expect(
        binding.rendered.single,
        '''
jq: error: syntax error, unexpected ']', expecting BINDING or '[' or '{' at <top-level>, line 1, column 7:
    . as [] | null
          ^'''
            .replaceAll('\r', ''),
      );

      final eof = parseProgram('{').report!;
      expect(eof.message, 'syntax error, unexpected end of file');
      expect((eof.line, eof.column, eof.endLine, eof.endColumn), (1, 1, 1, 2));
      expect(eof.rendered.single, '''
jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 1:
    {
    ^''');

      final invalid = parseProgram('}').report!;
      expect(
        invalid.message,
        'syntax error, unexpected INVALID_CHARACTER, expecting end of file',
      );
      expect((invalid.line, invalid.column), (1, 1));
    });

    test('Diagnostics are not keyed to fixtures', () {
      // The same grammar errors at different offsets, lines and byte widths:
      // names, columns and carets come from the new source text.
      expect(lastBlock('.x | . as [] | null'), '''
jq: error: syntax error, unexpected ']', expecting BINDING or '[' or '{' at <top-level>, line 1, column 12:
    .x | . as [] | null
               ^''');
      expect(lastBlock('.a |\n  . as [] | null'), '''
jq: error: syntax error, unexpected ']', expecting BINDING or '[' or '{' at <top-level>, line 2, column 9:
      . as [] | null
            ^''');
      // Columns are UTF-8 byte offsets: the string is 11 bytes long.
      final utf8 = parseProgram('"é€😀" | . as [] | null').report!;
      expect((utf8.line, utf8.column), (1, 21));
      expect(utf8.rendered.single.split('\n').last, '    ${' ' * 20}^');
      expect(
        lastBlock('   {   '),
        'jq: error: syntax error, unexpected end of file at <top-level>, '
        'line 1, column 5:\n'
        '       {   \n'
        '        ^^^',
      );
    });

    test('a named source appears in the location', () {
      expect(
        lastBlock('wat;', name: 'tests/modules/syntaxerror/syntaxerror.jq'),
        '''
jq: error: syntax error, unexpected ';', expecting end of file at tests/modules/syntaxerror/syntaxerror.jq, line 1, column 4:
    wat;
       ^''',
      );
    });

    test('rendered diagnostics are ordered and the harness takes the last', () {
      final report = parseProgram('{1+2:3}').report!;
      expect(report.diagnostics.map((d) => d.kind), [
        DiagnosticKind.syntax,
        DiagnosticKind.syntax,
      ]);
      expect(report.rendered, hasLength(2));
      expect(
        report.rendered.first,
        startsWith('jq: error: syntax error, unexpected LITERAL'),
      );
      expect(report.lastJqError, report.rendered.last);
      // Typed fields describe the first diagnostic only.
      expect(report.message, 'syntax error, unexpected LITERAL');
      expect(
        (report.line, report.column, report.endLine, report.endColumn),
        (1, 2, 1, 3),
      );
    });
  });

  group('Reject statically invalid object keys during compilation', () {
    test('Valid dynamic key', () {
      final result = parseProgram('{(.key): .value}');
      expect(result.diagnostics, isEmpty);
      expect(
        show(result.program!.body),
        '(object ((index . "key") (index . "value")))',
      );
    });

    test('dynamic keys that may be strings are never rejected statically', () {
      for (final source in [
        '{("a", "b"): 1}',
        '{("a" + "b"): 1}',
        '{(-1): 1}',
        '{(1 + "a"): 1}',
        '{([1, (2, 3)]): 1}',
        '{(0, 1): 2}',
        '{([] | length): 1}',
        '{(.a): 1}',
      ]) {
        expect(parseProgram(source).diagnostics, isEmpty, reason: source);
      }
    });

    test('Constant invalid key is not catchable', () {
      final result = parseProgram('try {(0):1} catch .');
      expect(result.program, isNull);
      final report = result.report!;
      expect(report.first.kind, DiagnosticKind.semantic);
      expect(report.message, 'Cannot use number (0) as object key');
      expect((report.line, report.column, report.endColumn), (1, 7, 8));
      expect(report.rendered.single, '''
jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 7:
    try {(0):1} catch .
          ^''');
    });

    test('constant folding decides which keys are constant', () {
      String message(String source) => parseProgram(source).report!.message;
      expect(message('{(1+2*3): 1}'), 'Cannot use number (7) as object key');
      expect(message('{((0)): 1}'), 'Cannot use number (0) as object key');
      expect(message('{(null): 1}'), 'Cannot use null (null) as object key');
      expect(message('{(1.0): 1}'), 'Cannot use number (1.0) as object key');
      expect(message('{(1e2): 1}'), 'Cannot use number (1E+2) as object key');
      expect(
        message('{([1,2,3]): 1}'),
        'Cannot use array ([1,2,3]) as object key',
      );
      expect(
        message('{({a: 1, b: [1, 2]}): 1}'),
        'Cannot use object ({"a":1,"b":[1,2]}) as object key',
      );
    });

    test('long constants are truncated like jq_dump_string_trunc', () {
      expect(
        parseProgram(
          '{({"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":1}): 1}',
        ).report!.message,
        'Cannot use object ({"aaaaaaaaaaaaaaaaaaaaaaa...}) as object key',
      );
    });

    test('every constant key is reported, in source order', () {
      final report = parseProgram('{a:1, (true):2, (false):3}').report!;
      expect(report.diagnostics.map((d) => d.message), [
        'Cannot use boolean (true) as object key',
        'Cannot use boolean (false) as object key',
      ]);
      expect(report.diagnostics.map((d) => d.kind).toSet(), {
        DiagnosticKind.semantic,
      });
    });

    test('Missing key parentheses', () {
      final result = parseProgram('{1+2:3}');
      expect(result.program, isNull);
      expect(result.report!.rendered, [
        '''
jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 2:
    {1+2:3}
     ^''',
        '''
jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:
    {1+2:3}
     ^^^''',
      ]);
    });

    test('object patterns share the key rules', () {
      expect(
        parseProgram('. as {(1): \$x} | 1').report!.message,
        'Cannot use number (1) as object key',
      );
      expect(parseProgram('. as {1+2: \$x} | 1').report!.rendered.last, '''
jq: error: May need parentheses around object key expression at <top-level>, line 1, column 7:
    . as {1+2: \$x} | 1
          ^^^^^^^''');
    });
  });

  group('error recovery follows the Bison grammar', () {
    List<String> messages(String source) => [
      for (final d in parseProgram(source).diagnostics) d.message,
    ];

    test('parentheses and brackets recover silently', () {
      expect(messages('(1 + ) + 2'), ["syntax error, unexpected ')'"]);
      expect(messages('(((1 +)))'), ["syntax error, unexpected ')'"]);
      expect(messages('[1 + ] | .'), ["syntax error, unexpected ']'"]);
    });

    test('later errors are reported once three tokens have been shifted', () {
      expect(messages('[1 + ], 2 +'), [
        "syntax error, unexpected ']'",
        'syntax error, unexpected end of file',
      ]);
    });

    test('object entries recover to the next colon', () {
      expect(messages('{a:1,,b:2}'), [
        "syntax error, unexpected ','",
        'May need parentheses around object key expression',
      ]);
      expect(messages('{(1 +): 2}'), [
        "syntax error, unexpected ')'",
        'May need parentheses around object key expression',
      ]);
    });

    test('if and try report their unterminated hints after the error', () {
      expect(messages('if 1 then 2'), [
        'syntax error, unexpected end of file',
        "Possibly unterminated 'if' statement",
      ]);
      expect(messages('try 1 catch'), [
        'syntax error, unexpected end of file',
        "Possibly unterminated 'try' statement",
      ]);
    });

    test('dot and break have their own hints', () {
      expect(messages('. 1'), [
        'syntax error, unexpected LITERAL',
        'try .["field"] instead of .field for unusually named fields',
      ]);
      expect(messages('break'), [
        'syntax error, unexpected end of file, expecting BINDING',
        'break requires a label to break to',
      ]);
    });

    test('recovery diagnostics carry the span of the discarded tokens', () {
      final report = parseProgram('{a:1 b:2}').report!;
      expect(report.diagnostics.last.span, const Span(1, 6));
    });
  });

  group('deferred syntax is not a jq diagnostic', () {
    test('an unsupported construct renders outside the jq error channel', () {
      final result = parseProgram('import "a" as b; .');
      expect(result.diagnostics, isEmpty);
      final unsupported = result.unsupported.single;
      expect(unsupported.kind, UnsupportedKind.importDirective);
      final rendered = renderDiagnostic(
        result.source,
        unsupported.toDiagnostic(),
      );
      expect(rendered, startsWith('zaru: unsupported: '));
      expect(rendered, isNot(startsWith(jqErrorPrefix)));
      expect(
        DiagnosticReport(result.source, [
          unsupported.toDiagnostic(),
        ]).lastJqError,
        isNull,
      );
    });

    test('fixtures that need later groups parse here', () {
      // jq.test:323 and :559 fail only on an undefined label or variable;
      // jq.test:1981 imports a module. None may report a parse diagnostic.
      expect(parseProgram(r'. as $foo | break $foo').diagnostics, isEmpty);
      expect(parseProgram(r'. as $foo | [$foo, $bar]').diagnostics, isEmpty);
      final module = parseProgram('import "syntaxerror" as e; .');
      expect(module.diagnostics, isEmpty);
      expect(module.unsupported.single.kind, UnsupportedKind.importDirective);
    });
  });

  group('pinned compile-error fixtures', () {
    for (final fixture in parserLevelFixtures) {
      test('${fixture.id} ${fixture.source}', () {
        final actual = lastBlock(fixture.source);
        expect(
          jqTestRuleAccepts(fixture.expectedLines, actual),
          isTrue,
          reason:
              'expected ${fixture.expectedLines.join('\n')}\nactual:\n$actual',
        );
      });
    }

    test('the module fixture text reports against its own file name', () {
      // jq.test:1981 loads tests/modules/syntaxerror/syntaxerror.jq.
      final actual = lastBlock(
        'wat;',
        name: 'tests/modules/syntaxerror/syntaxerror.jq',
      );
      expect(
        jqTestRuleAccepts([
          "jq: error: syntax error, unexpected ';', expecting end of file at tests/modules/syntaxerror/syntaxerror.jq, line 1, column 4:",
          '    wat;',
          '       ^',
        ], actual),
        isTrue,
      );
    });
  });

  group('jq 1.8.2 parser snapshots', () {
    for (final (source, blocks) in jqParseErrorSnapshots) {
      test('rejects ${_label(source)}', () {
        final result = parseProgram(source);
        expect(result.program, isNull, reason: 'program should be rejected');
        expect(result.report!.rendered, blocks);
      });
    }

    for (final source in jqParseAcceptedSnapshots) {
      test('accepts ${_label(source)}', () {
        final result = parseProgram(source);
        expect(result.diagnostics, isEmpty);
        expect(result.program, isNotNull);
      });
    }
  });
}

String _label(String source) =>
    source.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
