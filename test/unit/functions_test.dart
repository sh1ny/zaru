// Function definitions, parameters, closures, recursion and name resolution,
// through the real compiler and the lazy iterators it produces. Every
// expected value was probed against the pinned jq 1.8.2.
import 'package:test/test.dart';
import 'package:zaru/src/engine/compiler.dart';
import 'package:zaru/src/engine/machine.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

ZaruCompileError compileError(String source) {
  try {
    Zaru.compile(source);
  } on ZaruCompileError catch (error) {
    return error;
  }
  fail('expected $source to fail compilation');
}

List<String> headers(ZaruCompileError error) => [
  for (final block in error.diagnostics) block.split('\n').first,
];

void main() {
  group('filter and value parameters', () {
    test('Filter and value parameters', () {
      expect(
        jsonOutputs(
          'def twice(f): f | f; def plus(\$x): . + \$x; twice(plus(2))',
          '1',
        ),
        ['5'],
      );
    });

    test('a value parameter is also a filter parameter', () {
      expect(jsonOutputs(r'def f($a): [a + $a]; f(1,2)', 'null'), [
        '[2,3]',
        '[3,4]',
      ]);
    });

    test('value parameters multiply in jq order', () {
      // The first value parameter varies slowest.
      expect(jsonOutputs(r'def f($a; $b): [$a, $b]; f(1,2; 3,4)', 'null'), [
        '[1,3]',
        '[1,4]',
        '[2,3]',
        '[2,4]',
      ]);
      expect(jsonOutputs(r'def f(a; $b): [a + $b]; f(1,2; 10,20)', 'null'), [
        '[11,12]',
        '[21,22]',
      ]);
      expect(jsonOutputs(r'def f($a; $b): $a + $b; f(1; 2)', 'null'), ['3']);
    });

    test('a filter parameter is re-run at every use', () {
      expect(jsonOutputs('def f(x): [x, x]; f(1, 2)', 'null'), ['[1,2,1,2]']);
      expect(jsonOutputs('def f(x): x | x; [3 | f(. * 2)]', 'null'), ['[12]']);
      expect(jsonOutputs(r'def f(x): x as $v | 1; [f(1, 2)]', 'null'), [
        '[1,1]',
      ]);
    });

    test('arguments are evaluated against the input at each use', () {
      expect(jsonOutputs(r'[1,2] | def f($x): $x; [.[] | f(.)]', 'null'), [
        '[1,2]',
      ]);
      expect(jsonOutputs('def f(g): [.[] | g]; f(. + 1)', '[1,2]'), ['[2,3]']);
    });

    test('a filter argument can fail only when it is used', () {
      expect(jsonOutputs('def f(g): 7; f(error("never"))', 'null'), ['7']);
      expect(jsonOutputs('def f(g): try g catch "c"; f(error("x"))', 'null'), [
        '"c"',
      ]);
      expect(jsonOutputs(r'def f($g): 7; try f(error("x")) catch .', 'null'), [
        '"x"',
      ]);
    });
  });

  group('definitions and scope', () {
    test('recursive and shadowed definitions', () {
      expect(
        jsonOutputs(
          'def fac: if . <= 1 then 1 else . * (. - 1 | fac) end; 10 | fac',
          'null',
        ),
        ['3628800'],
      );
      expect(jsonOutputs('def f: 1; def g: f; def f: 2; g, f', 'null'), [
        '1',
        '2',
      ]);
      expect(jsonOutputs('def g: def f: 1; f; def f: 2; g, f', 'null'), [
        '1',
        '2',
      ]);
      expect(jsonOutputs('def f: 3; def f: f + 1; 0', 'null'), ['0']);
    });

    test('a definition sees itself, not a later one', () {
      expect(
        jsonOutputs(
          'def down(n): if n > 0 then n, down(n - 1) else empty end; '
              '[down(3)]',
          'null',
        ),
        ['[3,2,1]'],
      );
      expect(
        compileError('def f: g; def g: 1; f').message,
        'g/0 is not defined',
      );
    });

    test('functions of different arity coexist', () {
      expect(
        jsonOutputs(
          'def f: 1; def f(a): 2; def f(a; b): 3; [f, f(0), f(0; 0)]',
          'null',
        ),
        ['[1,2,3]'],
      );
      expect(compileError('def f(a): a; f').message, 'f/0 is not defined');
      expect(compileError('def f: 1; f(1)').message, 'f/1 is not defined');
      expect(
        compileError('def f(a): a; f(1; 2)').message,
        'f/2 is not defined',
      );
    });

    test('closures capture the call site, definitions their own scope', () {
      expect(jsonOutputs(r'1 as $x | def f(g): 2 as $x | g; f($x)', 'null'), [
        '1',
      ]);
      expect(jsonOutputs(r'1 as $x | def f: $x; 2 as $x | f', 'null'), ['1']);
      expect(jsonOutputs(r'(1, 2) as $x | def f: $x * 10; f', 'null'), [
        '10',
        '20',
      ]);
      expect(jsonOutputs('def a(f): def b(g): f + g; b(10); a(1)', 'null'), [
        '11',
      ]);
      expect(jsonOutputs('def f(x): def g: x; [g, g]; f(1, 2)', 'null'), [
        '[1,2,1,2]',
      ]);
    });

    test('parameters shadow definitions and one another', () {
      expect(jsonOutputs('def f(g): def g: 5; g; f(1)', 'null'), ['5']);
      expect(jsonOutputs('def f(f): f; f(3)', 'null'), ['3']);
      expect(jsonOutputs(r'1 as $a | def f($a): $a; [f(2), $a]', 'null'), [
        '[2,1]',
      ]);
    });

    test('a definition can be used inside an expression', () {
      expect(jsonOutputs('def f: . + 1; f | f', '1'), ['3']);
      expect(jsonOutputs('1 | def f: . + 1; f | f', 'null'), ['3']);
      expect(jsonOutputs('[.[] | def f: . * 2; f]', '[1,2]'), ['[2,4]']);
      expect(jsonOutputs('def f: def g: 3; g * 2; f', 'null'), ['6']);
    });

    test('external variables are visible inside definitions', () {
      expect(
        jsonOutputs(
          r'def f: $ext + 1; f',
          'null',
          variables: {'ext'},
          args: {'ext': 41},
        ),
        ['42'],
      );
    });

    test('a definitions-only program is a jq compile error', () {
      final error = compileError('def f: 1;');
      expect(error.isUnsupported, isFalse);
      expect(error.diagnostics, [
        'jq: error: Top-level program not given (try ".")',
      ]);
    });
  });

  group('name resolution of definitions', () {
    test('Lexical break validation', () {
      final error = compileError(r'. as $foo | break $foo');
      expect(error.isUnsupported, isFalse);
      expect(error.diagnostics, [
        '''
jq: error: \$*label-foo is not defined at <top-level>, line 1, column 13:
    . as \$foo | break \$foo
                ^^^^^^^^^^''',
      ]);
      // A label is lexical: it does not reach a function defined outside it,
      // nor code after the labeled expression.
      expect(
        compileError(r'def f: break $x; label $x | f').message,
        r'$*label-x is not defined',
      );
      expect(
        compileError(r'(label $a | 1) | break $a').message,
        r'$*label-a is not defined',
      );
      // A label does not provide a variable of the same name.
      expect(compileError(r'label $a | $a').message, r'$a is not defined');
    });

    test('undefined names inside a used definition are reported', () {
      final error = compileError(r'def f: $a; f');
      expect(error.diagnostics, [
        '''
jq: error: \$a is not defined at <top-level>, line 1, column 8:
    def f: \$a; f
           ^^''',
      ]);
      expect(headers(compileError(r'def f($p): $q + p; f($r)')), [
        r'jq: error: $q is not defined at <top-level>, line 1, column 12:',
        r'jq: error: $r is not defined at <top-level>, line 1, column 22:',
      ]);
    });

    test('jq drops definitions nothing uses', () {
      expect(jsonOutputs(r'def f: $undefined; 1', 'null'), ['1']);
      expect(jsonOutputs(r'def f: nosuchfunction; def g: f; 2', 'null'), ['2']);
      // A definition that only another used definition needs is kept.
      expect(
        compileError(r'def g: $b; def f: g; f').message,
        r'$b is not defined',
      );
    });

    test('errors of the enclosing code come first, bodies only after', () {
      expect(headers(compileError(r'def f: 1; def g: $a; $b')), [
        r'jq: error: $b is not defined at <top-level>, line 1, column 22:',
      ]);
      expect(headers(compileError(r'def f: $a; def g: $b; f, g')), [
        r'jq: error: $a is not defined at <top-level>, line 1, column 8:',
        r'jq: error: $b is not defined at <top-level>, line 1, column 19:',
      ]);
      // A filter argument is a unit of its own, after the definitions.
      expect(headers(compileError(r'def f(g): $a; f($b)')), [
        r'jq: error: $a is not defined at <top-level>, line 1, column 11:',
        r'jq: error: $b is not defined at <top-level>, line 1, column 17:',
      ]);
      // Neither the arguments of an unresolved call nor anything nested in
      // a unit that already failed are checked.
      expect(headers(compileError(r'foo($x)')), [
        'jq: error: foo/1 is not defined at <top-level>, line 1, column 1:',
      ]);
      expect(headers(compileError(r'$x | map($y)')), [
        r'jq: error: $x is not defined at <top-level>, line 1, column 1:',
      ]);
    });

    test('a parameter is not callable with arguments', () {
      expect(
        compileError('def f(g): g(1); f(2)').message,
        'g/1 is not defined',
      );
    });
  });

  group('tail calls and frames', () {
    test('a million tail calls through a pipe', () {
      expect(
        jsonOutputs(
          'def f: if . < 1000000 then . + 1 | f else . end; 0 | f',
          'null',
        ),
        ['1000000'],
      );
    });

    test('non-tail recursion nests on the heap, not the host stack', () {
      expect(
        jsonOutputs(
          'def f: if . == 0 then 0 else (. - 1 | f) + 1 end; 100000 | f',
          'null',
        ),
        ['100000'],
      );
    });

    test('tail positions keep a constant continuation and choice stack', () {
      // A recursive generator: comma right-hand side and conditional branch
      // are tail positions, so no frame or choice accumulates per output.
      for (final source in [
        'def f: ., (. + 1 | f); 0 | f',
        'def g: if . % 2 == 0 then ., (. + 1 | g) else (. + 1 | g) end; 0 | g',
        'def h(x): x, (. + 1 | h(x)); 0 | h(.)',
      ]) {
        final program = compileSource(source, const {});
        final machine = Machine(program.root, null, null);
        var frames = 0;
        var choices = 0;
        for (var i = 0; i < 20000; i++) {
          expect(machine.advance(), isTrue, reason: source);
          if (i > 100) {
            var depth = 0;
            for (var f = machine.k; f != null; f = f.next) {
              depth++;
            }
            frames = depth > frames ? depth : frames;
            choices = machine.choices.length > choices
                ? machine.choices.length
                : choices;
          }
        }
        expect(frames, lessThan(4), reason: source);
        expect(choices, lessThan(4), reason: source);
      }
    });
  });
}
