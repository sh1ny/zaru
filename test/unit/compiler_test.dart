// Real-compiler tests: reuse, external variables, name resolution and the
// unsupported-versus-semantic distinction. Nothing here is mocked: every
// assertion goes through Zaru.compile and the lazy iterators it returns.
import 'package:test/test.dart';
import 'package:zaru/zaru.dart';

ZaruCompileError compileError(
  String source, {
  Set<String> variables = const {},
}) {
  try {
    Zaru.compile(source, variables: variables);
  } on ZaruCompileError catch (error) {
    return error;
  }
  fail('expected $source to fail compilation');
}

void main() {
  group('compile and reuse', () {
    test('Compound reusable filter', () {
      final filter = Zaru.compile('.items[] | select(.active) | .name');
      expect(
        filter.runJson('''
          {"items":[{"name":"ann","active":true},
                    {"name":"bob","active":false},
                    {"name":"cy","active":true}]}''').toList(),
        ['ann', 'cy'],
      );
      expect(
        filter.runJson('{"items":[{"name":"dee","active":true}]}').toList(),
        ['dee'],
      );
      expect(filter.runJson('{"items":[]}').toList(), isEmpty);
      // Native values go through the same filter.
      expect(
        filter.run({
          'items': [
            {'name': 'eve', 'active': 1},
            {'name': 'fay', 'active': null},
          ],
        }).toList(),
        ['eve'],
      );
    });

    test('Invalid source location', () {
      // An unexpected `]` is the first token of line two.
      final error = compileError('.a\n] | .b');
      expect(error.line, 2);
      expect(error.col, 1);
      expect(error.message, startsWith('syntax error, unexpected'));
      expect(error.isUnsupported, isFalse);
      expect(error.diagnostics.first, startsWith('jq: error: syntax error'));
      expect(
        error.diagnostics.first,
        contains('at <top-level>, line 2, column 1:'),
      );
    });

    test('compilation is eager, execution is lazy and independent', () {
      // Compile errors surface from Zaru.compile, never from a run.
      expect(() => Zaru.compile('. |'), throwsA(isA<ZaruCompileError>()));
      final failing = Zaru.compile('1, error("late")');
      // Creating the iterable and the iterator evaluates nothing.
      final iterable = failing.run(null);
      final iterator = iterable.iterator;
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, 1);
      expect(() => iterator.moveNext(), throwsA(isA<ZaruRuntimeError>()));

      // Two iterators over one iterable, and one filter, share no state.
      final each = Zaru.compile('.[]');
      final results = each.run([1, 2, 3]);
      final a = results.iterator;
      final b = results.iterator;
      expect([a.moveNext(), a.current], [true, 1]);
      expect([a.moveNext(), a.current], [true, 2]);
      expect([b.moveNext(), b.current], [true, 1]);
      final c = each.run([10, 20]).iterator;
      expect([c.moveNext(), c.current], [true, 10]);
      expect([a.moveNext(), a.current], [true, 3]);
      expect(a.moveNext(), isFalse);
      expect([b.moveNext(), b.current], [true, 2]);
      expect([c.moveNext(), c.current], [true, 20]);
      expect(c.moveNext(), isFalse);
      // Iterating again re-runs from the start.
      expect(results.toList(), [1, 2, 3]);
      expect(results.toList(), [1, 2, 3]);
    });
  });

  group('external variables', () {
    test('Rebind a compiled external variable', () {
      final filter = Zaru.compile(r'. > $min', variables: {'min'});
      expect(filter.run(5, args: {'min': 3}).toList(), [true]);
      expect(filter.run(5, args: {'min': 7}).toList(), [false]);
      expect(filter.runJson('5', args: {'min': 3}).toList(), [true]);
      // Per-run values never leak between interleaved iterators.
      final low = filter.run(5, args: {'min': 3}).iterator;
      final high = filter.run(5, args: {'min': 7}).iterator;
      expect([high.moveNext(), high.current], [true, false]);
      expect([low.moveNext(), low.current], [true, true]);
      // Several declarations, each bound independently.
      final two = Zaru.compile(r'[$a, $b, .]', variables: {'a', 'b'});
      expect(
        two.run(1, args: {'a': 'x', 'b': null}).map(Zaru.toJson).toList(),
        ['["x",null,1]'],
      );
      expect(two.run(2, args: {'b': 'y', 'a': 'z'}).map(Zaru.toJson).toList(), [
        '["z","y",2]',
      ]);
      // A local binding shadows a declaration.
      final shadow = Zaru.compile(r'1 as $min | $min', variables: {'min'});
      expect(shadow.run(null, args: {'min': 9}).toList(), [1]);
    });

    test('Missing declaration or value', () {
      final undeclared = compileError(r'$min');
      expect(undeclared.message, r'$min is not defined');
      expect(undeclared.isUnsupported, isFalse);

      final filter = Zaru.compile(r'1, $min', variables: {'min'});
      // Run and iterator creation succeed ...
      final iterator = filter.run(null).iterator;
      // ... and the first moveNext raises before the filter yields 1.
      expect(
        () => iterator.moveNext(),
        throwsA(
          isA<ZaruMissingArgumentError>().having((e) => e.name, 'name', 'min'),
        ),
      );
      expect(iterator.moveNext(), isFalse);
      // Supplying the value (even null) works.
      expect(filter.run(null, args: {'min': null}).toList(), [1, null]);
      // The same holds for runJson.
      expect(
        () => filter.runJson('null').iterator.moveNext(),
        throwsA(isA<ZaruMissingArgumentError>()),
      );
    });
  });

  group('name resolution', () {
    test('Core undefined variable remains a semantic error', () {
      // jq.test:559
      final error = compileError(r'. as $foo | [$foo, $bar]');
      expect(error.isUnsupported, isFalse);
      expect(error.message, r'$bar is not defined');
      expect(
        (error.line, error.col, error.endLine, error.endCol),
        (1, 20, 1, 24),
      );
      expect(error.diagnostics, [
        '''
jq: error: \$bar is not defined at <top-level>, line 1, column 20:
    . as \$foo | [\$foo, \$bar]
                       ^^^^''',
      ]);

      // jq.test:323: a break needs a lexically enclosing label of that name.
      final label = compileError(r'. as $foo | break $foo');
      expect(label.isUnsupported, isFalse);
      expect(label.diagnostics, [
        '''
jq: error: \$*label-foo is not defined at <top-level>, line 1, column 13:
    . as \$foo | break \$foo
                ^^^^^^^^^^''',
      ]);

      // Undefined functions report name/arity at the name.
      final call = compileError('1 | foo(1;2) | 3');
      expect(call.isUnsupported, isFalse);
      expect(call.diagnostics, [
        '''
jq: error: foo/2 is not defined at <top-level>, line 1, column 5:
    1 | foo(1;2) | 3
        ^^^''',
      ]);
      expect(compileError('foo').message, 'foo/0 is not defined');
      // The wrong arity of a real builtin is not defined either.
      expect(compileError('[1] | select').message, 'select/0 is not defined');
    });

    test('every undefined name is reported in jq order', () {
      expect(
        compileError(r'foo, $z').diagnostics.map((d) => d.split('\n').first),
        [
          'jq: error: foo/0 is not defined at <top-level>, line 1, column 1:',
          r'jq: error: $z is not defined at <top-level>, line 1, column 6:',
        ],
      );
      // An index reports its key before its target, as jq compiles it.
      expect(
        compileError(r'$a[$b]').diagnostics.map((d) => d.split('\n').first),
        [
          r'jq: error: $b is not defined at <top-level>, line 1, column 4:',
          r'jq: error: $a is not defined at <top-level>, line 1, column 1:',
        ],
      );
      // Names bound by `as` are visible only in the body.
      expect(compileError(r'$x as $y | $y').message, r'$x is not defined');
      expect(
        compileError(r'(1 as $y | $y) | $y').message,
        r'$y is not defined',
      );
    });

    test('Unsupported import cannot manufacture conformance', () {
      // jq.test:1981 is a %%FAIL IGNORE MSG case. Module loading is not
      // implemented, so compiling it must never look like jq's compile error.
      final error = compileError('import "syntaxerror" as e; .');
      expect(error.isUnsupported, isTrue);
      expect(error.diagnostics, isNotEmpty);
      for (final block in error.diagnostics) {
        expect(block, startsWith('zaru: unsupported:'));
        expect(block, isNot(startsWith('jq: error')));
      }
      expect(error.message, contains('import'));
    });

    test('deferred and not-yet-implemented constructs are never successes', () {
      for (final source in [
        r'@base64',
        r'$__loc__',
        '.a = 1',
        '.a |= 1',
        'include "x"; .',
        'def f: length; f',
        'reduce .[] as \$x (0; length)',
        'foreach .[] as \$x (0; . + \$x; length)',
        'label \$out | add',
        'map(.)',
        'length',
        'infinite',
        'range(3) | keys',
        r'. as [$a] | length',
      ]) {
        final error = compileError(source);
        expect(error.isUnsupported, isTrue, reason: source);
        for (final block in error.diagnostics) {
          expect(block, startsWith('zaru: unsupported:'), reason: source);
        }
      }
    });

    test('a real jq error wins over an unsupported construct', () {
      // The grammar error is jq's whatever else the source contains.
      final error = compileError('import "a" as b; ]');
      expect(error.isUnsupported, isFalse);
      expect(error.diagnostics.last, startsWith('jq: error: syntax error'));
    });
  });
}
