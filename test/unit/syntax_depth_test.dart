import 'package:test/test.dart';
import 'package:zaru/src/engine/compiler.dart';
import 'package:zaru/src/syntax/parser.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

/// One way to nest a program. `build(k)` wraps a leaf in [k] levels, so the
/// program is `k + 1` levels deep; `expected(k)` is the output list for the
/// input `7`.
final class _Shape {
  const _Shape(
    this.name,
    this.build,
    this.expected, {
    this.input = '7',
    this.step = 1,
    this.args,
  });

  final String name;
  final String input;

  /// How many levels one wrapper adds; `build` gets the wrapper count.
  final int step;

  /// Values for the external variable `$x`, when the shape uses it.
  final Map<String, Object?>? args;
  final String Function(int k) build;
  final List<String> Function(int k) expected;
}

String _repeat(String text, int count) => List.filled(count, text).join();

final _shapes = <_Shape>[
  _Shape(
    'nested parentheses',
    (k) => '${_repeat('(', k)}.${_repeat(')', k)}',
    (k) => ['7'],
  ),
  _Shape(
    'nested arrays',
    (k) => '${_repeat('[', k)}1${_repeat(']', k)}',
    (k) => ['${_repeat('[', k)}1${_repeat(']', k)}'],
  ),
  _Shape(
    'nested objects',
    (k) => '${_repeat('{"a":', k)}1${_repeat('}', k)}',
    (k) => ['${_repeat('{"a":', k)}1${_repeat('}', k)}'],
  ),
  _Shape('plus chain', (k) => '${_repeat('1+', k)}1', (k) => ['${k + 1}']),
  _Shape('and chain', (k) => '${_repeat('true and ', k)}true', (k) => ['true']),
  _Shape(
    'alternative chain',
    (k) => '${_repeat('null // ', k)}5',
    (k) => ['5'],
  ),
  _Shape(
    'field chain',
    (k) => _repeat('.a', k),
    (k) => ['null'],
    input: 'null',
  ),
  _Shape(
    'index chain',
    (k) => _repeat('.[0]', k),
    (k) => ['null'],
    input: 'null',
  ),
  _Shape(
    'bracket key nesting',
    (k) => '${_repeat('.[', k)}0${_repeat(']', k)}',
    (k) => ['0'],
    input: '[0]',
  ),
  _Shape(
    'string key nesting',
    (k) => '${_repeat(r'$x."\(', k)}"a"${_repeat(')"', k)}',
    (k) => ['"a"'],
    step: 2,
    args: {
      'x': {'a': 'a'},
    },
  ),
  _Shape(
    'if nesting',
    (k) => '${_repeat('if . then ', k)}1${_repeat(' else 2 end', k)}',
    (k) => ['1'],
  ),
  _Shape(
    'reduce nesting',
    (k) => '${_repeat(r'reduce 1 as $x (0; ', k)}7${_repeat(')', k)}',
    (k) => ['7'],
  ),
  _Shape(
    'binding chain',
    (k) => '${_repeat(r'1 as $x | ', k)}\$x',
    (k) => ['1'],
  ),
  _Shape(
    'nested interpolation',
    (k) => '${_repeat(r'"\(', k)}1${_repeat(')"', k)}',
    (k) => ['"1"'],
  ),
];

List<String> _run(String filter, [String input = '7']) =>
    jsonOutputs(filter, input);

String _commas(int count, String item) =>
    List.generate(count, (i) => item.replaceAll('#', '$i')).join(',');

void main() {
  group('wide programs do not use the depth budget', () {
    test('a 10000-element array literal', () {
      final source = '[${_commas(10000, '#')}]';
      expect(_run('$source | reduce .[] as \$x (0; .+1)'), ['10000']);
      expect(_run('$source | last(.[])'), ['9999']);
    });

    test('a 300-element array literal of strings', () {
      expect(_run('[${_commas(300, '"s#"')}] | .[0]'), ['"s0"']);
    });

    test('a 10000-element comma chain yields every result', () {
      final results = _run(_commas(10000, '.'));
      expect(results, hasLength(10000));
      expect(results.toSet(), {'7'});
    });

    test('a 10000-element comma chain inside an array constructor', () {
      expect(_run('[${_commas(10000, '.')}] | reduce .[] as \$x (0; .+\$x)'), [
        '70000',
      ]);
    });

    test('a 10000-step pipe chain is the identity', () {
      expect(_run(List.filled(10001, '.').join('|')), ['7']);
    });

    test('a 10000-step pipe chain that computes', () {
      expect(_run(List.filled(10000, '.+1').join('|')), ['10007']);
    });

    test('a 10000-step pipe chain as an object value', () {
      expect(_run('{"a": ${List.filled(10001, '.').join('|')}}'), ['{"a":7}']);
    });

    test('a 10000-entry object constructor', () {
      final source = '{${_commas(10000, '"k#":#')}}';
      expect(_run('$source | reduce .[] as \$x (0; .+1)'), ['10000']);
      expect(_run('{${_commas(10000, '"k#":.')}} | .k9999'), ['7']);
    });

    test('a 300-step select chain', () {
      final chain = List.generate(300, (i) => 'select(. != $i)').join(' | ');
      expect(_run(chain, '1000'), ['1000']);
      expect(_run(chain, '5'), isEmpty);
    });

    test('a 300-step assignment chain is unsupported, not too deep', () {
      final chain = List.generate(300, (i) => '.a$i = $i').join(' | ');
      Object? caught;
      try {
        Zaru.compile(chain);
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isA<ZaruCompileError>());
      expect((caught! as ZaruCompileError).isUnsupported, isTrue);
    });

    test(
      'a wide chain of deep-enough pieces still counts only the nesting',
      () {
        final piece = '${'(' * 200}.${')' * 200}';
        expect(_run(List.filled(500, piece).join('|')), ['7']);
        expect(_run(List.filled(500, piece).join(',')), hasLength(500));
      },
    );
  });

  group('syntax depth budget', () {
    test('the budget is large enough for ordinary programs', () {
      expect(maxSyntaxDepth, greaterThanOrEqualTo(200));
      // Every shape's wrapper count must make the rejected case exactly one
      // level too deep.
      for (final shape in _shapes) {
        expect(maxSyntaxDepth % shape.step, 0, reason: shape.name);
      }
    });

    for (final shape in _shapes) {
      group(shape.name, () {
        test('depth maxSyntaxDepth compiles and runs', () {
          final k = (maxSyntaxDepth - 1) ~/ shape.step;
          final args = shape.args;
          expect(
            jsonOutputs(
              shape.build(k),
              shape.input,
              variables: {...?args?.keys},
              args: args ?? const {},
            ),
            shape.expected(k),
          );
        });

        for (final depth in [maxSyntaxDepth + 1, 100000]) {
          test('depth $depth is a typed compile error', () {
            Object? caught;
            try {
              Zaru.compile(
                shape.build((depth - 1) ~/ shape.step),
                variables: {...?shape.args?.keys},
              );
            } on Object catch (error) {
              caught = error;
            }
            expect(caught, isA<ZaruCompileError>());
            final error = caught! as ZaruCompileError;
            expect(error.isUnsupported, isFalse);
            expect(
              error.message,
              'program nests deeper than $maxSyntaxDepth levels',
            );
            expect(error.line, 1);
            expect(error.diagnostics, hasLength(1));
            expect(
              error.diagnostics.single,
              startsWith(
                'zaru: error: program nests deeper than $maxSyntaxDepth '
                'levels at <top-level>, line 1, column ',
              ),
            );
            expect(error.diagnostics.single, isNot(startsWith('jq: error')));
          });
        }
      });
    }

    test('the diagnostic text is stable', () {
      expect(
        () => Zaru.compile('${_repeat('(', 2000)}.${_repeat(')', 2000)}'),
        throwsA(
          isA<ZaruCompileError>().having(
            (e) => e.diagnostics.single.split('\n').first,
            'first line',
            'zaru: error: program nests deeper than $maxSyntaxDepth levels '
                'at <top-level>, line 1, column ${maxSyntaxDepth + 1}:',
          ),
        ),
      );
    });

    // dart2wasm cannot recover from a stack overflow: the browser hangs
    // instead of raising StackOverflowError, so only the depth budget (not
    // the safety net below) protects it, and this test cannot run there.
    test('a stack overflow while compiling becomes a typed compile error', () {
      int recurse(int n) => recurse(n + 1) + 1;
      Object? caught;
      try {
        guardCompileStack(() => recurse(0));
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isA<ZaruCompileError>());
      final error = caught! as ZaruCompileError;
      expect(error.isUnsupported, isFalse);
      expect(
        error.diagnostics.single,
        'zaru: error: program is too deeply nested to compile',
      );
    }, testOn: 'vm || js');
  });
}
