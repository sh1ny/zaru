// Lazy result streams, the M1 helper set (jq-coded builtins hosted from the
// pinned builtin.jq) and the stack-safety boundary of recursive generators.
// Every expected value was probed against the pinned jq 1.8.2 binary.
import 'package:test/test.dart';
import 'package:zaru/src/engine/compiler.dart';
import 'package:zaru/src/engine/machine.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

/// A reduction that builds an array nested [depth] levels deep around null.
String _nested(int depth) => 'reduce range($depth) as \$i (null; [.])';

/// The largest number of pending alternatives the machine holds at any output
/// of [source] over the first [outputs] outputs, and the outputs seen.
({int peak, int seen}) _peakAlternatives(String source, int outputs) {
  final machine = Machine(compileSource(source, const {}).root, null, null);
  var peak = 0;
  var seen = 0;
  while (seen < outputs && machine.advance()) {
    seen++;
    if (machine.choices.length > peak) peak = machine.choices.length;
  }
  return (peak: peak, seen: seen);
}

void main() {
  group('result streams', () {
    test('Empty is not null', () {
      final empty = Zaru.compile('empty');
      final nul = Zaru.compile('null');
      for (final input in <Object?>[
        null,
        1,
        'x',
        [1],
        {'a': 1},
      ]) {
        expect(empty.run(input).toList(), isEmpty);
        expect(nul.run(input).toList(), [null]);
      }
      expect(empty.run(null).iterator.moveNext(), isFalse);
      expect(jsonOutputs('empty, 1, empty', 'null'), ['1']);
      expect(jsonOutputs('[empty]', 'null'), ['[]']);
      expect(jsonOutputs('[null]', 'null'), ['[null]']);
    });

    test('a consumer that stops early never evaluates the suffix', () {
      final iterator = Zaru.compile('1, error("late"), 3').run(null).iterator;
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, 1);
      // Dropping the iterator here never evaluates the error branch.
      final lazy = Zaru.compile(
        '(1, 2) | if . == 2 then error("late") else . end',
      );
      expect(lazy.run(null).first, 1);
      expect(lazy.run(null).take(1).toList(), [1]);
      expect(() => lazy.run(null).toList(), throwsA(isA<ZaruRuntimeError>()));
    });

    test('products follow jq order and keep duplicates', () {
      expect(jsonOutputs('(1, 2) | (., .)', 'null'), ['1', '1', '2', '2']);
      expect(jsonOutputs('1 | (., .) | . + 1', 'null'), ['2', '2']);
      expect(jsonOutputs('[(1, 2) | (., .)]', 'null'), ['[1,1,2,2]']);
      expect(jsonOutputs('[.[] | (. , 10 * .)]', '[1,2]'), ['[1,10,2,20]']);
      expect(jsonOutputs('1, (2, 3), 4', 'null'), ['1', '2', '3', '4']);
      expect(jsonOutputs('((1, 2), (3, 4))', 'null'), ['1', '2', '3', '4']);
    });

    test('a stream is a sequence of values, not a list', () {
      final results = Zaru.compile('.[]').run([1, null, 1]);
      expect(results.toList(), [1, null, 1]);
      expect(results.length, 3);
    });

    test('Stop before a later error', () {
      expect(jsonOutputs('first(1, error("x"))', 'null'), ['1']);
      expect(jsonOutputs('[first(range(10), error("x"))]', 'null'), ['[0]']);
      expect(jsonOutputs('[limit(1; 1, error("x"))]', 'null'), ['[1]']);
      expect(jsonOutputs('[nth(1; 10, 20, error("x"))]', 'null'), ['[20]']);
      expect(jsonOutputs('[limit(0; 1, error("x"))]', 'null'), ['[]']);
      // Dropping the stream early never evaluates the failing suffix.
      final stream = Zaru.compile('limit(5; 1, 2, error("x"))').run(null);
      expect(stream.take(2).toList(), [1, 2]);
    });

    test('a consumer that needs the failing element still sees the error', () {
      final limited = outputsAndError(
        Zaru.compile('limit(2; 1, error("x"))').run(null),
      );
      expect(limited.values, ['1']);
      expect(limited.error, isA<ZaruRuntimeError>());
      expect(
        runtimeErrorValue(Zaru.compile('skip(1; 1, 2, error("x"))').run(null)),
        'x',
      );
      expect(
        runtimeErrorValue(Zaru.compile('last(1, error("x"))').run(null)),
        'x',
      );
    });

    test('Huge range prefix', () {
      expect(jsonOutputs('[limit(3; range(1e18))]', 'null'), ['[0,1,2]']);
      expect(jsonOutputs('first(range(1e18))', 'null'), ['0']);
      expect(jsonOutputs('[limit(3; range(0; 1e18; 1))]', 'null'), ['[0,1,2]']);
      expect(jsonOutputs('[limit(3; range(0; -1e18; -1))]', 'null'), [
        '[0,-1,-2]',
      ]);
      expect(jsonOutputs('[limit(3; range(1e18) | . * 2)]', 'null'), [
        '[0,2,4]',
      ]);
      expect(jsonOutputs('[limit(3; recurse(. + 1))]', '0'), ['[0,1,2]']);
      expect(jsonOutputs('[limit(3; repeat(. * 2))]', '1'), ['[2,2,2]']);
      expect(jsonOutputs('nth(5; range(1e18))', 'null'), ['5']);
    });
  });

  group('range', () {
    test('range/1 and range/2 count up by one and stop before the bound', () {
      expect(jsonOutputs('[range(3)]', 'null'), ['[0,1,2]']);
      expect(jsonOutputs('[range(0)]', 'null'), ['[]']);
      expect(jsonOutputs('[range(-1)]', 'null'), ['[]']);
      expect(jsonOutputs('[range(2.5)]', 'null'), ['[0,1,2]']);
      expect(jsonOutputs('[range(1; 4)]', 'null'), ['[1,2,3]']);
      expect(jsonOutputs('[range(1; 0)]', 'null'), ['[]']);
      expect(jsonOutputs('[range(0.5; 3)]', 'null'), ['[0.5,1.5,2.5]']);
      // The first value is the start itself, with its literal spelling.
      expect(jsonOutputs('[range(1.0; 3)]', 'null'), ['[1.0,2]']);
    });

    test('multi-valued bounds: start varies slowest', () {
      expect(jsonOutputs('[range(0, 1; 3, 4)]', 'null'), [
        '[0,1,2,0,1,2,3,1,2,1,2,3]',
      ]);
      expect(jsonOutputs('[range(0, 1)]', 'null'), ['[0]']);
    });

    test('range/3 follows the direction of the step', () {
      expect(jsonOutputs('[range(0; 10; 3)]', 'null'), ['[0,3,6,9]']);
      expect(jsonOutputs('[range(5; 0; -2)]', 'null'), ['[5,3,1]']);
      expect(jsonOutputs('[range(0; -1; -0.5)]', 'null'), ['[0,-0.5]']);
      expect(jsonOutputs('[range(0; 1; 0.3)]', 'null'), [
        '[0,0.3,0.6,0.8999999999999999]',
      ]);
      expect(jsonOutputs('[range(0; 3.0; 1.0)]', 'null'), ['[0,1,2]']);
      // A step in the wrong direction yields nothing.
      expect(jsonOutputs('[range(0; 5; -1)]', 'null'), ['[]']);
      expect(jsonOutputs('[range(5; 0; 1)]', 'null'), ['[]']);
    });

    test('a zero step is empty, not an endless stream', () {
      expect(jsonOutputs('[range(0; 1; 0)]', 'null'), ['[]']);
      expect(jsonOutputs('[limit(3; range(0; 1; 0))]', 'null'), ['[]']);
    });

    test('range/3 products: init slowest, then bound, then step', () {
      expect(jsonOutputs('[range(0, 1; 4, 5; 1, 2)]', 'null'), [
        '[0,1,2,3,0,2,0,1,2,3,4,0,2,4,1,2,3,1,3,1,2,3,4,1,3]',
      ]);
      expect(jsonOutputs('[range(1; 2; 3, 4)]', 'null'), ['[1,1]']);
      expect(jsonOutputs('[range(3; 0; -1, -2)]', 'null'), ['[3,2,1,3,1]']);
    });

    test('non-numeric bounds are runtime errors', () {
      expect(
        runtimeErrorValue(Zaru.compile('range("a")').run(null)),
        'Range bounds must be numeric',
      );
      expect(
        runtimeErrorValue(Zaru.compile('range(null; 3)').run(null)),
        'Range bounds must be numeric',
      );
      expect(
        runtimeErrorValue(Zaru.compile('range(0; "a")').run(null)),
        'Range bounds must be numeric',
      );
      expect(
        runtimeErrorValue(Zaru.compile('range(0; 3; "a")').run(null)),
        'number (0) and string ("a") cannot be added',
      );
    });
  });

  group('limit, skip, first, last and nth', () {
    test('limit takes a prefix and counts fractionally like jq', () {
      expect(jsonOutputs('[limit(3; range(10))]', 'null'), ['[0,1,2]']);
      expect(jsonOutputs('[limit(2; empty)]', 'null'), ['[]']);
      expect(jsonOutputs('[limit(5; 1, 2)]', 'null'), ['[1,2]']);
      expect(jsonOutputs('[limit(1.5; 1, 2, 3)]', 'null'), ['[1,2]']);
      expect(jsonOutputs('[limit(0.5; 1, 2, 3)]', 'null'), ['[1]']);
      expect(jsonOutputs('[limit(1, 2; 10, 20, 30)]', 'null'), ['[10,10,20]']);
    });

    test('limit rejects negative or non-comparable counts', () {
      expect(
        runtimeErrorValue(Zaru.compile('limit(-1; 1, 2)').run(null)),
        "limit doesn't support negative count",
      );
      expect(
        runtimeErrorValue(Zaru.compile('limit(null; 1, 2)').run(null)),
        "limit doesn't support negative count",
      );
      expect(
        runtimeErrorValue(Zaru.compile('limit("a"; 1, 2)').run(null)),
        'string ("a") and number (1) cannot be subtracted',
      );
    });

    test('skip drops a prefix', () {
      expect(jsonOutputs('[skip(1; 1, 2, 3)]', 'null'), ['[2,3]']);
      expect(jsonOutputs('[skip(0; 1, 2)]', 'null'), ['[1,2]']);
      expect(jsonOutputs('[skip(5; 1, 2)]', 'null'), ['[]']);
      expect(jsonOutputs('[skip(1.5; 1, 2, 3)]', 'null'), ['[2,3]']);
      expect(jsonOutputs('[skip(1, 2; 1, 2, 3)]', 'null'), ['[2,3,3]']);
      expect(
        runtimeErrorValue(Zaru.compile('skip(-1; 1, 2)').run(null)),
        "skip doesn't support negative count",
      );
    });

    test('first/1 and last/1', () {
      expect(jsonOutputs('[first(empty)]', 'null'), ['[]']);
      expect(jsonOutputs('[first(empty, 1)]', 'null'), ['[1]']);
      expect(jsonOutputs('[first(range(10; 0; -1))]', 'null'), ['[10]']);
      expect(jsonOutputs('[first(1, 2), first(3, 4)]', 'null'), ['[1,3]']);
      expect(jsonOutputs('[last(empty)]', 'null'), ['[]']);
      expect(jsonOutputs('[last(1, 2, 3)]', 'null'), ['[3]']);
      expect(jsonOutputs('[last(range(5))]', 'null'), ['[4]']);
      // A stream ending in null has the last value null, not "no output".
      expect(jsonOutputs('[last(1, null)]', 'null'), ['[null]']);
      expect(jsonOutputs('[range(5)] | [first(.[]), last(.[])]', 'null'), [
        '[0,4]',
      ]);
    });

    test('nth/2', () {
      expect(jsonOutputs('[nth(2; 10, 20, 30)]', 'null'), ['[30]']);
      expect(jsonOutputs('[nth(5; 10, 20, 30)]', 'null'), ['[]']);
      expect(jsonOutputs('[nth(0, 2; 10, 20, 30)]', 'null'), ['[10,30]']);
      expect(jsonOutputs('[nth(1.7; 10, 20, 30)]', 'null'), ['[20]']);
      expect(
        runtimeErrorValue(Zaru.compile('nth(-1; 1, 2)').run(null)),
        "nth doesn't support negative indices",
      );
    });

    test('first, last and nth/1 index their input', () {
      expect(jsonOutputs('[first, last, nth(1)]', '[1,2,3]'), ['[1,3,2]']);
      expect(jsonOutputs('[first, last, nth(0)]', '[]'), ['[null,null,null]']);
      expect(jsonOutputs('[first, last, nth(1)]', 'null'), [
        '[null,null,null]',
      ]);
      expect(jsonOutputs('nth(-1)', '[1,2]'), ['2']);
      expect(jsonOutputs('nth(1.5)', '[1,2]'), ['2']);
      expect(jsonOutputs('nth(0, 1)', '[5,6]'), ['5', '6']);
      expect(
        runtimeErrorValue(Zaru.compile('first').runJson('{"a":1}')),
        startsWith('Cannot index object with number'),
      );
      expect(
        runtimeErrorValue(Zaru.compile('last').runJson('"abc"')),
        startsWith('Cannot index string with number'),
      );
    });

    test('first/1 stays lexically scoped around user labels', () {
      expect(jsonOutputs(r'[label $f | first(1, break $f)]', 'null'), ['[1]']);
      expect(jsonOutputs(r'[label $f | (1, break $f, 2)]', 'null'), ['[1]']);
      expect(
        jsonOutputs(r'[label $out | limit(2; 1, break $out, 2)]', 'null'),
        ['[1]'],
      );
    });
  });

  group('while, until, repeat and recurse', () {
    test('while emits each state that satisfies the condition', () {
      expect(jsonOutputs('[while(. < 100; . * 2)]', '1'), [
        '[1,2,4,8,16,32,64]',
      ]);
      expect(jsonOutputs('[while(false; . * 2)]', '1'), ['[]']);
      expect(jsonOutputs('[while(. < 3; . + 1, . + 2)]', '0'), ['[0,1,2,2]']);
    });

    test('until emits the first state that satisfies the condition', () {
      expect(jsonOutputs('until(. > 100; . * 2)', '1'), ['128']);
      expect(jsonOutputs('until(true; . * 2)', '1'), ['1']);
      expect(
        jsonOutputs(r'reduce until(. > 3; . + 1, . + 2) as $x (0; . + 1)', '0'),
        ['8'],
      );
    });

    test('repeat is the pinned jq definition, applied to the same input', () {
      expect(jsonOutputs('[limit(5; repeat(. * 2))]', '1'), ['[2,2,2,2,2]']);
      expect(jsonOutputs('[limit(3; repeat(1, 2))]', 'null'), ['[1,2,1]']);
      expect(jsonOutputs('[repeat(. * 2, error)?]', '1'), ['[2]']);
      expect(jsonOutputs('def f: 1; [limit(3; repeat(f))]', 'null'), [
        '[1,1,1]',
      ]);
    });

    test('recurse/1 and recurse/2', () {
      expect(
        jsonOutputs('[recurse(if . < 20 then . * . else empty end)]', '2'),
        ['[2,4,16,256]'],
      );
      expect(jsonOutputs('[recurse(. * .; . < 100)]', '2'), ['[2,4,16]']);
      expect(jsonOutputs('[recurse(. + 1, . + 2; . < 4)]', '1'), ['[1,2,3,3]']);
      expect(jsonOutputs('[recurse(empty)]', '1'), ['[1]']);
      expect(jsonOutputs('[recurse(1; false)]', 'null'), ['[null]']);
    });

    test('recurse/0 and .. walk a value in pre-order', () {
      expect(jsonOutputs('[recurse]', '[1,[2]]'), ['[[1,[2]],1,[2],2]']);
      expect(jsonOutputs('[..]', '[1,[2]]'), ['[[1,[2]],1,[2],2]']);
      expect(jsonOutputs('[..]', '{"a":[1,{"b":2}]}'), [
        '[{"a":[1,{"b":2}]},[1,{"b":2}],1,{"b":2},2]',
      ]);
      expect(jsonOutputs('[..]', '"a"'), ['["a"]']);
      expect(jsonOutputs('[..]', 'null'), ['[null]']);
      expect(jsonOutputs('[recurse(.[])]', '[[[]]]'), ['[[[[]]],[[]],[]]']);
      expect(jsonOutputs('[.. | select(. == 2)]', '[1,[2],{"a":2}]'), [
        '[2,2]',
      ]);
      expect(jsonOutputs('..', '[]'), ['[]']);
    });

    test('a user definition shadows only the builtin it names', () {
      expect(jsonOutputs('def select(f): 7; select(true)', 'null'), ['7']);
      expect(jsonOutputs('def range(a; b): 9; [range(1; 2)]', 'null'), ['[9]']);
      expect(jsonOutputs('def limit(n; e): "mine"; limit(1; 2)', 'null'), [
        '"mine"',
      ]);
      expect(jsonOutputs('def first(f): 5; first(1, 2)', 'null'), ['5']);
      // Builtins keep using their own siblings, not the user's replacement.
      expect(jsonOutputs('def select(f): 7; [recurse(. + 1; . < 3)]', '0'), [
        '[0,1,2]',
      ]);
      expect(jsonOutputs('def empty: 1; [first(range(3))]', 'null'), ['[0]']);
      // The same name at another arity is still the builtin.
      expect(jsonOutputs('def first(f): 5; [first, first(1)]', '[8]'), [
        '[8,5]',
      ]);
    });
  });

  group('error, select and tostring', () {
    test('error/1 raises each output of its argument', () {
      expect(jsonOutputs('try error("x") catch .', 'null'), ['"x"']);
      expect(jsonOutputs('try error catch .', 'null'), ['null']);
      expect(jsonOutputs('try error(null) catch .', 'null'), ['null']);
      expect(jsonOutputs('try error catch .', '{"a":1}'), ['{"a":1}']);
      expect(jsonOutputs('[error("x")?]', 'null'), ['[]']);
    });

    test('select keeps the input once per truthy output', () {
      expect(jsonOutputs('[.[] | select(. > 1)]', '[1,2,3]'), ['[2,3]']);
      expect(jsonOutputs('[.[] | select(. > 1, . < 3)]', '[1,2,3]'), [
        '[1,2,2,3]',
      ]);
      expect(jsonOutputs('[select(1, null, 2)]', 'null'), ['[null,null]']);
      expect(jsonOutputs('[select(empty)]', '1'), ['[]']);
    });

    test('tostring keeps strings and prints everything else', () {
      expect(jsonOutputs('tostring', '[1,2]'), [r'"[1,2]"']);
      expect(jsonOutputs('tostring', '"x"'), ['"x"']);
      expect(jsonOutputs('tostring', 'null'), ['"null"']);
      expect(jsonOutputs('tostring', '{"a":1.0}'), [r'"{\"a\":1.0}"']);
      expect(jsonOutputs('tostring', '1.0'), ['"1.0"']);
      expect(jsonOutputs('tostring', '[1.50,"a"]'), [r'"[1.50,\"a\"]"']);
    });
  });

  group('integration with the core grammar', () {
    test('helpers take filter and value parameters of user definitions', () {
      expect(jsonOutputs('def f(x): [limit(2; x)]; f(range(5))', 'null'), [
        '[0,1]',
      ]);
      expect(
        jsonOutputs(r'def f($n): [limit($n; range(10))]; f(1, 3)', 'null'),
        ['[0]', '[0,1,2]'],
      );
      expect(
        jsonOutputs('def f(g): def h: g; [limit(2; h)]; f(repeat(7))', 'null'),
        ['[7,7]'],
      );
      expect(jsonOutputs('def f: def g: first(1, 2); g; f', 'null'), ['1']);
    });

    test('helpers inside constructors, bindings and optional else', () {
      expect(jsonOutputs('{a: first(1, 2), b: limit(2; 3, 4)}', 'null'), [
        '{"a":1,"b":3}',
        '{"a":1,"b":4}',
      ]);
      expect(jsonOutputs('{(limit(2; "a", "b")): 1}', 'null'), [
        '{"a":1}',
        '{"b":1}',
      ]);
      expect(jsonOutputs('[.[] | if . > 1 then first(., 9) end]', '[1,2,3]'), [
        '[1,2,3]',
      ]);
      expect(jsonOutputs(r'[limit(3; range(10)) as $x | $x * 2]', 'null'), [
        '[0,2,4]',
      ]);
      expect(jsonOutputs(r'. as [$n] | [limit($n; range(10))]', '[2]'), [
        '[0,1]',
      ]);
      expect(jsonOutputs(r'[range(3) as $i | range($i)]', 'null'), ['[0,0,1]']);
      expect(jsonOutputs('[range(2) | first(range(3; 6))]', 'null'), ['[3,3]']);
      expect(jsonOutputs(r'[.[] as $x | [$x, first($x, 2)]]', '[5,6]'), [
        '[[5,5],[6,6]]',
      ]);
      expect(jsonOutputs(r'reduce range(5) as $i ([]; . + [$i * 2])', 'null'), [
        '[0,2,4,6,8]',
      ]);
      expect(
        jsonOutputs(
          r'[foreach range(5) as $i (0; . + $i; select(. % 2 == 0))]',
          'null',
        ),
        ['[0,6,10]'],
      );
    });

    test('labels, try and optional access around helpers', () {
      expect(
        jsonOutputs(
          r'[label $l | range(10) | if . == 3 then break $l else . end]',
          'null',
        ),
        ['[0,1,2]'],
      );
      expect(jsonOutputs('try limit(-1; 1) catch .', 'null'), [
        "\"limit doesn't support negative count\"",
      ]);
      expect(jsonOutputs('[limit(2; .[]?)]', 'null'), ['[]']);
      expect(jsonOutputs('[first(.[]?)]', '5'), ['[]']);
      expect(jsonOutputs('[limit(2; .[])]', '[1,2,3]'), ['[1,2]']);
    });

    test('a compiled filter with helpers is reusable and independent', () {
      final filter = Zaru.compile('[limit(3; repeat(.))]');
      expect(filter.run(1).toList().map(Zaru.toJson), ['[1,1,1]']);
      expect(filter.run('a').toList().map(Zaru.toJson), ['["a","a","a"]']);
      final a = Zaru.compile('range(3)').run(null).iterator;
      final b = Zaru.compile('range(3)').run(null).iterator;
      expect(a.moveNext(), isTrue);
      expect(a.moveNext(), isTrue);
      expect(b.moveNext(), isTrue);
      expect([a.current, b.current], [1, 0]);
      final shared = Zaru.compile('range(3)');
      final x = shared.run(null).iterator..moveNext();
      final y = shared.run(null).iterator..moveNext();
      x.moveNext();
      expect([x.current, y.current], [1, 0]);
    });

    test('unimplemented builtins and formats stay unsupported', () {
      for (final source in [
        'map(.)',
        'length',
        'infinite',
        'range(3) | keys',
        'first(.[] | add)',
        '@base64',
        r'$__loc__',
        '.a |= 1',
      ]) {
        try {
          Zaru.compile(source);
          fail('expected an unsupported error for $source');
        } on ZaruCompileError catch (error) {
          expect(error.isUnsupported, isTrue, reason: source);
        }
      }
    });
  });

  group('stack safety', () {
    const million = '1000000';

    test('Million-step recursive helpers', () {
      // Each helper below loops a million times through a recursive jq
      // definition; a completed tail call must leave no frame behind.
      expect(jsonOutputs('last(range(0; 1000000; 1))', 'null'), ['999999']);
      expect(
        jsonOutputs(r'reduce range(0; 1000000; 1) as $i (0; . + $i)', 'null'),
        ['499999500000'],
      );
      expect(
        jsonOutputs(
          'reduce limit(1000000; repeat(1)) as \$x (0; . + 1)',
          'null',
        ),
        [million],
      );
      expect(jsonOutputs('last(while(. < 1000000; . + 1))', '0'), ['999999']);
      expect(jsonOutputs('until(. >= 1000000; . + 1)', '0'), [million]);
      expect(
        jsonOutputs(
          'last(recurse(if . < 1000000 then . + 1 else empty end))',
          '0',
        ),
        [million],
      );
      // recurse/2 keeps only states that satisfy the condition.
      expect(jsonOutputs('last(recurse(. + 1; . < 1000000))', '0'), ['999999']);
      expect(jsonOutputs('nth(999999; range(1000000))', 'null'), ['999999']);
      expect(jsonOutputs('[skip(999999; range(1000000))]', 'null'), [
        '[999999]',
      ]);
      expect(
        jsonOutputs('first(range(1000000) | select(. == 999999))', 'null'),
        ['999999'],
      );
    });

    test('tail positions of user definitions run in constant space', () {
      // Pipe right-hand side, if branch, comma right-hand side.
      expect(
        jsonOutputs(
          'def f: if . < 1000000 then (. + 1 | f) else . end; f',
          '0',
        ),
        [million],
      );
      expect(
        jsonOutputs(
          'def g: if . >= 1000000 then . else (. + 1 | g) end; g',
          '0',
        ),
        [million],
      );
      expect(
        jsonOutputs(
          'def h: ., (if . < 1000000 then (. + 1 | h) else empty end); last(h)',
          '0',
        ),
        [million],
      );
      expect(
        jsonOutputs(
          'def k: if . < 1000000 then (. + 1 | k) elif . == 1000000 then "done" '
              'else "over" end; k',
          '0',
        ),
        ['"done"'],
      );
      expect(
        jsonOutputs(
          'def m(f): if . < 1000000 then (f | m(f)) else . end; m(. + 1)',
          '0',
        ),
        [million],
      );
    });

    test('completed tails leave no pending alternative behind', () {
      // The machine pulls one output at a time; a recursive helper that kept
      // the alternative of every completed step would grow with the count.
      for (final source in [
        'repeat(1)',
        'range(0; 1000000; 1)',
        '0 | while(. < 1000000; . + 1)',
        '0 | recurse(if . < 1000000 then . + 1 else empty end)',
        '0 | recurse(. + 1; . < 1000000)',
        'def h: ., (if . < 1000000 then (. + 1 | h) else empty end); 0 | h',
        'def h: if . < 1000000 then (., (. + 1 | h)) else . end; 0 | h',
      ]) {
        final result = _peakAlternatives(source, 20000);
        expect(result.seen, 20000, reason: source);
        expect(result.peak, lessThan(8), reason: source);
      }
    });

    test('a genuinely pending alternative survives a deep tail call', () {
      expect(
        jsonOutputs(
          'def f: if . < 1000000 then (. + 1 | f) else . end; [(f, "alt"), -1]',
          '0',
        ),
        ['[1000000,"alt",-1]'],
      );
      expect(
        jsonOutputs(
          'def f: if . < 1000000 then (. + 1 | f) else . end; '
              '[limit(2; (0, 5) | f)]',
          'null',
        ),
        ['[1000000,1000000]'],
      );
      expect(
        jsonOutputs(
          'def r: if . < 100000 then (. + 1 | r) else . end; '
              '[first((0 | r), error("late"))]',
          'null',
        ),
        ['[100000]'],
      );
      // Try, label and alternation around a deep tail call stay intact.
      expect(
        jsonOutputs(
          'def f: if . < 300000 then (. + 1 | f) else error("deep") end; '
              'try f catch .',
          '0',
        ),
        ['"deep"'],
      );
      expect(
        jsonOutputs(
          'def f: if . < 300000 then (. + 1 | f) else empty end; '
              '[f // "none"]',
          '0',
        ),
        ['["none"]'],
      );
    });

    test('Deep descent is not structural equality', () {
      final build = _nested(10001);
      const count = r'reduce %s as $x (0; . + 1)';
      expect(
        jsonOutputs('$build | ${count.replaceFirst('%s', '..')}', 'null'),
        ['10002'],
      );
      // Only the innermost value is null; comparing each level to null never
      // walks the nesting.
      expect(
        jsonOutputs(
          '$build | ${count.replaceFirst('%s', '(.. | select(. == null))')}',
          'null',
        ),
        ['1'],
      );
      expect(jsonOutputs('$build | last(..)', 'null'), ['null']);
      expect(
        jsonOutputs(
          '$build | ${count.replaceFirst('%s', 'recurse(.[]?)')}',
          'null',
        ),
        ['10002'],
      );
    });
  });
}
