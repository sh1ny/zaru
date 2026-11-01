// reduce, foreach, label/break and destructuring through the real compiler.
// Expected values were probed against the pinned jq 1.8.2 unless a comment
// names a fixture.
import 'package:test/test.dart';
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

Object? failure(String filter, String input) {
  try {
    jsonOutputs(filter, input);
  } on ZaruRuntimeError catch (error) {
    return error.value;
  }
  fail('expected $filter to fail at runtime');
}

void main() {
  group('reduce and foreach', () {
    test('Reduction and extraction', () {
      expect(jsonOutputs(r'reduce .[] as $x (0; . + $x)', '[1,2,3]'), ['6']);
      expect(jsonOutputs(r'foreach .[] as $x (0; . + $x; .)', '[1,2,3]'), [
        '1',
        '3',
        '6',
      ]);
      // The two-argument foreach extracts the state itself.
      expect(jsonOutputs(r'foreach .[] as $x (0; . + $x)', '[1,2,3]'), [
        '1',
        '3',
        '6',
      ]);
      expect(
        jsonOutputs(r'foreach .[] as $x (0; . + $x; [$x, .])', '[1,2,3]'),
        ['[1,1]', '[2,3]', '[3,6]'],
      );
    });

    test('the source sees the input, the update sees the state', () {
      // jq.test:924
      expect(jsonOutputs(r'[reduce .[] / .[] as $i (0; . + $i)]', '[1,2]'), [
        '[4.5]',
      ]);
      expect(
        jsonOutputs(r'reduce .a[] as $x (.b; . + $x)', '{"a":[1,2],"b":10}'),
        ['13'],
      );
      // An empty source yields the initial state.
      expect(jsonOutputs(r'reduce empty as $x (7; . + 1)', 'null'), ['7']);
      expect(jsonOutputs(r'[foreach empty as $x (7; . + 1)]', 'null'), ['[]']);
    });

    test('every initial state runs the loop in turn', () {
      expect(jsonOutputs(r'[reduce (1, 2) as $x ((0, 100); . + $x)]', 'null'), [
        '[3,103]',
      ]);
      expect(
        jsonOutputs(
          r'[foreach (1, 2, 3) as $x ((0, 100); . + $x; [$x, .])]',
          'null',
        ),
        ['[[1,1],[2,3],[3,6],[1,101],[2,103],[3,106]]'],
      );
      expect(jsonOutputs(r'[reduce empty as $x (empty; .)]', 'null'), ['[]']);
    });

    test('reduce keeps the last update output, or null for none', () {
      expect(jsonOutputs(r'reduce (1, 2, 3) as $x (0; (., 10) + $x)', 'null'), [
        '13',
      ]);
      expect(jsonOutputs(r'reduce (1, 2, 3) as $x (0; empty)', 'null'), [
        'null',
      ]);
      // An update that is empty once resets the state to null.
      expect(
        jsonOutputs(
          r'reduce (1, 2, 3) as $x (0; if $x == 2 then empty else . + 1 end)',
          'null',
        ),
        ['1'],
      );
    });

    test('foreach emits every extraction and keeps the last update', () {
      expect(
        jsonOutputs(
          r'[foreach (1, 2, 3) as $x (0; (. + $x, . * 10); ., "e")]',
          'null',
        ),
        ['[1,"e",0,"e",2,"e",0,"e",3,"e",0,"e"]'],
      );
      expect(jsonOutputs(r'[foreach (1, 2, 3) as $x (0; empty; .)]', 'null'), [
        '[]',
      ]);
      expect(jsonOutputs(r'[foreach (1, 2) as $x (0; .; empty)]', 'null'), [
        '[]',
      ]);
    });

    test('nested and chained reductions', () {
      expect(
        jsonOutputs(
          r'reduce .[] as $row (0; reduce $row[] as $x (.; . + $x))',
          '[[1,2],[3],[4,5]]',
        ),
        ['15'],
      );
      // jq.test:921
      expect(jsonOutputs(r'[-reduce -.[] as $x (0; . + $x)]', '[1,2,3]'), [
        '[6]',
      ]);
      // jq.test:930
      expect(
        jsonOutputs(r'reduce .[] as $x (0; . + $x) as $x | $x', '[1,2,3]'),
        ['6'],
      );
      // jq.test:934: the source of a reduce may be the input itself.
      expect(jsonOutputs(r'reduce . as $n (.; .)', 'null'), ['null']);
      expect(
        jsonOutputs(r'[.[] | reduce .[] as $x (0; . + $x)]', '[[1,2],[3]]'),
        ['[3,3]'],
      );
    });

    test('reduce and foreach inside definitions and closures', () {
      expect(
        jsonOutputs(
          r'def sum(f): reduce .[] as $x (0; . + ($x | f)); sum(. * 2)',
          '[1,2,3]',
        ),
        ['12'],
      );
      expect(
        jsonOutputs(
          r'def running: foreach .[] as $x (0; . + $x); [running]',
          '[1,2,3]',
        ),
        ['[1,3,6]'],
      );
      // The update closure sees the variables bound around the reduce.
      expect(
        jsonOutputs(r'10 as $k | reduce .[] as $x (0; . + $x * $k)', '[1,2]'),
        ['30'],
      );
    });

    test('errors in reduce and foreach propagate with prior outputs', () {
      final iterator = Zaru.compile(
        r'foreach (1, 2, 3) as $x (0; if $x == 2 then error("bad") else . + $x end)',
      ).run(null).iterator;
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, 1);
      expect(
        () => iterator.moveNext(),
        throwsA(isA<ZaruRuntimeError>().having((e) => e.value, 'v', 'bad')),
      );
      expect(iterator.moveNext(), isFalse);
      expect(
        jsonOutputs(r'try reduce (1, 2) as $x (0; error("r")) catch .', 'null'),
        ['"r"'],
      );
      expect(
        failure(r'reduce .[] as $x (0; . + $x)', '[1,"a"]'),
        'number (1) and string ("a") cannot be added',
      );
    });

    test('reduce and foreach report undefined names in jq order', () {
      expect(
        compileError(
          r'reduce $a as $x ($b; $c)',
        ).diagnostics.map((d) => d.split('\n').first),
        [
          r'jq: error: $b is not defined at <top-level>, line 1, column 18:',
          r'jq: error: $a is not defined at <top-level>, line 1, column 8:',
          r'jq: error: $c is not defined at <top-level>, line 1, column 22:',
        ],
      );
      expect(
        compileError(
          r'foreach $a as $x ($b; $c; $d)',
        ).diagnostics.map((d) => d.split('\n').first),
        [
          r'jq: error: $b is not defined at <top-level>, line 1, column 19:',
          r'jq: error: $a is not defined at <top-level>, line 1, column 9:',
          r'jq: error: $c is not defined at <top-level>, line 1, column 23:',
          r'jq: error: $d is not defined at <top-level>, line 1, column 27:',
        ],
      );
      // The loop variable is not visible in the source or the initial state.
      expect(
        compileError(r'reduce $x as $x (0; .)').message,
        r'$x is not defined',
      );
      expect(
        compileError(r'reduce (1) as $x ($x; .)').message,
        r'$x is not defined',
      );
    });
  });

  group('label and break', () {
    test('Lexically targeted break', () {
      expect(
        jsonOutputs(
          r'[label $here | .[] | if . > 1 then break $here else . end]',
          '[0,2,1]',
        ),
        ['[0]'],
      );
      // jq.test:315: the label ends only its own body.
      expect(
        jsonOutputs(
          r'[(label $here | .[] | if . > 1 then break $here else . end), "hi!"]',
          '[0,1,2,3,4]',
        ),
        ['[0,1,"hi!"]'],
      );
      // jq.test:2285, with a generator in place of range.
      expect(
        jsonOutputs(
          r'[ label $if | (0, 1, 2, 3, 4, 5, 6, 7) | ., (select(. == 5) | break $if) ]',
          'null',
        ),
        ['[0,1,2,3,4,5]'],
      );
    });

    test('break stops the body and resumes the code around the label', () {
      expect(jsonOutputs(r'[label $a | (1, 2, 3) | ., break $a]', 'null'), [
        '[1]',
      ]);
      expect(jsonOutputs(r'[(label $a | 1, break $a, 2), 3]', 'null'), [
        '[1,3]',
      ]);
      expect(
        jsonOutputs(r'[(1, 2) as $x | label $a | $x, break $a, 9]', 'null'),
        ['[1,2]'],
      );
      // Output before the break stays; nothing after it in the body runs.
      expect(
        jsonOutputs(
          r'[label $a | (1, error("not reached")) | ., break $a]',
          'null',
        ),
        ['[1]'],
      );
    });

    test('labels nest and shadow by lexical position', () {
      expect(jsonOutputs(r'[label $a | label $b | (1, break $a, 2)]', 'null'), [
        '[1]',
      ]);
      expect(
        jsonOutputs(r'[label $a | (label $b | (1, break $b, 2)), 3]', 'null'),
        ['[1,3]'],
      );
      expect(
        jsonOutputs(r'[label $a | (label $a | (1, break $a, 2)), 3]', 'null'),
        ['[1,3]'],
      );
      expect(
        jsonOutputs(r'[label $a | (label $b | (1, break $a, 2)), 3]', 'null'),
        ['[1]'],
      );
    });

    test('a break inside a function reaches the label around its definition', () {
      expect(
        jsonOutputs(
          r'[label $out | def stop: break $out; (1, 2, 3) | if . == 2 then stop else . end]',
          'null',
        ),
        ['[1]'],
      );
      // The same label expression is a fresh activation at every call.
      expect(
        jsonOutputs(
          r'def first(f): label $out | f | ., break $out; [first(1, 2), first(3, 4)]',
          'null',
        ),
        ['[1,3]'],
      );
      // A recursive call breaks only its own activation.
      expect(
        jsonOutputs(
          r'def f: label $x | (1, (if . < 2 then (. + 1 | f) else empty end), 9) | if . == 9 then break $x else . end; [0 | f]',
          'null',
        ).length,
        1,
      );
    });

    test('a break passes through a closure argument', () {
      expect(
        jsonOutputs(
          r'def each(f): (1, 2, 3) | f; [label $out | each(if . == 2 then break $out else . end)]',
          'null',
        ),
        ['[1]'],
      );
    });

    test('break is not an error: try, ? and // do not see it', () {
      expect(
        jsonOutputs(
          r'[label $x | try (1, break $x, 2) catch "caught"]',
          'null',
        ),
        ['[1]'],
      );
      expect(jsonOutputs(r'[label $x | (1, (break $x)?, 2)]', 'null'), ['[1]']);
      expect(jsonOutputs(r'[label $x | (break $x) // 5, 6]', 'null'), ['[]']);
      expect(jsonOutputs(r'[label $x | try break $x catch error]', 'null'), [
        '[]',
      ]);
      // A real error is still caught around a label.
      expect(
        jsonOutputs(r'try (label $x | error("e"), break $x) catch .', 'null'),
        ['"e"'],
      );
    });

    test('break runs the rest of the stream only through the label', () {
      final iterator = Zaru.compile(
        r'label $a | (1, 2, break $a, error("never"))',
      ).run(null).iterator;
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, 1);
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, 2);
      expect(iterator.moveNext(), isFalse);
      expect(iterator.moveNext(), isFalse);
    });
  });

  group('destructuring', () {
    test('array and object patterns', () {
      expect(jsonOutputs(r'. as [$a, $b] | {$a, $b}', '[1,2,3]'), [
        '{"a":1,"b":2}',
      ]);
      expect(
        jsonOutputs(r'. as {a: $x, b: [$y]} | [$x, $y]', '{"a":1,"b":[2]}'),
        ['[1,2]'],
      );
      // jq.test:938
      expect(
        jsonOutputs(
          r'. as {$a, b: [$c, {$d}]} | [$a, $c, $d]',
          '{"a":1,"b":[2,{"d":3}]}',
        ),
        ['[1,2,3]'],
      );
      // jq.test:942: `$b:` binds the value and destructures it.
      expect(
        jsonOutputs(
          r'. as {$a, $b:[$c, $d]}| [$a, $b, $c, $d]',
          '{"a":1,"b":[2,{"d":3}]}',
        ),
        ['[1,[2,{"d":3}],2,{"d":3}]'],
      );
      expect(jsonOutputs(r'. as [$a, [$b]] | [$a, $b]', '[1,[2]]'), ['[1,2]']);
      expect(jsonOutputs(r'.[] as [$a, $b] | {$a, $b}', '[[1,2],[3]]'), [
        '{"a":1,"b":2}',
        '{"a":3,"b":null}',
      ]);
      expect(jsonOutputs(r'. as {"a": $x, "b": $y} | [$x, $y]', '{"a":1}'), [
        '[1,null]',
      ]);
    });

    test('missing parts are null and the wrong kind is an error', () {
      expect(jsonOutputs(r'. as [$a] | $a', 'null'), ['null']);
      expect(jsonOutputs(r'. as {a: $a} | $a', 'null'), ['null']);
      expect(
        failure(r'. as [$a] | $a', '"x"'),
        'Cannot index string with number (0)',
      );
      expect(
        failure(r'. as {a: $a} | $a', '1'),
        'Cannot index number with string ("a")',
      );
      expect(
        failure(r'. as [$a] | $a', '{"a":1}'),
        'Cannot index object with number (0)',
      );
    });

    test(
      'key expressions are generators evaluated against the matched value',
      () {
        expect(jsonOutputs(r'. as {("a","b"): $v} | $v', '{"a":1,"b":2}'), [
          '1',
          '2',
        ]);
        expect(jsonOutputs(r'. as {(.k): $v} | $v', '{"k":"a","a":5}'), ['5']);
        expect(
          jsonOutputs(r'"b" as $key | . as {($key): $v} | $v', '{"b":9}'),
          ['9'],
        );
        expect(
          failure(r'. as {(.k): $v} | $v', '{"k":1}'),
          'Cannot index object with number (1)',
        );
        // A constant key of the wrong type is rejected at compile time.
        expect(
          compileError(r'. as {(1): $v} | $v').message,
          'Cannot use number (1) as object key',
        );
        // jq: pattern variables are not visible in key expressions.
        expect(
          compileError(r'. as {a: $k, ($k): $v} | 1').message,
          r'$k is not defined',
        );
        expect(
          compileError(
            r'$a as {($b): $x} | $c',
          ).diagnostics.map((d) => d.split('\n').first),
          [
            r'jq: error: $a is not defined at <top-level>, line 1, column 1:',
            r'jq: error: $b is not defined at <top-level>, line 1, column 9:',
            r'jq: error: $c is not defined at <top-level>, line 1, column 20:',
          ],
        );
      },
    );

    test('a repeated name keeps the first binding in code order', () {
      // Array elements are matched last to first, as jq compiles them.
      expect(jsonOutputs(r'. as [$a, $a] | $a', '[1,2]'), ['2']);
      expect(jsonOutputs(r'. as {a: $x, b: $x} | $x', '{"a":1,"b":2}'), ['1']);
      expect(jsonOutputs(r'. as [$a, $a] ?// $b | $a', '[1,2]'), ['1']);
    });

    test('alternatives bind every name, null where unused', () {
      // jq.test:949
      expect(
        jsonOutputs(
          r'.[] | . as {$a, b: [$c, {$d}]} ?// [$a, {$b}, $e] ?// $f | [$a, $b, $c, $d, $e, $f]',
          '[{"a":1, "b":[2,{"d":3}]}, [4, {"b":5, "c":6}, 7, 8, 9], "foo"]',
        ),
        [
          '[1,null,2,3,null,null]',
          '[4,5,null,null,7,null]',
          '[null,null,null,null,null,"foo"]',
        ],
      );
      expect(jsonOutputs(r'.[] as [$a] ?// $a | $a', '[[3], 4]'), ['3', '4']);
    });

    test('an error in the body selects the next alternative', () {
      // The manual's example.
      expect(
        jsonOutputs(
          r'.[] as [$a] ?// [$b] | if $a != null then error("err: \($a)") else {$a,$b} end',
          '[[3]]',
        ),
        ['{"a":null,"b":3}'],
      );
      expect(
        jsonOutputs(r'.[] as {a:$a} ?// {a:$a} ?// $a | $a', '[[3],[4],[5],6]'),
        ['[3]', '[4]', '[5]', '6'],
      );
      // An error after the match is still handled by the pattern, even when
      // raised downstream of the whole expression.
      expect(
        jsonOutputs(
          r'[([[1]] | .[] as [$a] ?// $a | $a) | if . == 1 then error("down") else . end]',
          'null',
        ),
        ['[[1]]'],
      );
      // The last alternative's error is the filter's error.
      expect(failure(r'.[] as [$a] ?// $a | error("x")', '[1]'), 'x');
    });

    test('reference-recorded destructuring failures', () {
      // jq.test:945, :949, :953, :957 end with the last alternative's
      // error before any output.
      for (final source in [
        r'.[] | . as {a:$a} ?// {a:$a} ?// {a:$a} | $a',
        r'.[] as {a:$a} ?// {a:$a} ?// {a:$a} | $a',
      ]) {
        final results = Zaru.compile(source).runJson('[[3],[4],[5],6]');
        final seen = outputsAndError(results);
        expect(seen.values, isEmpty, reason: source);
        expect(
          seen.error,
          isA<ZaruRuntimeError>().having(
            (e) => e.value,
            'value',
            'Cannot index array with string ("a")',
          ),
        );
      }
      for (final source in [
        r'[[3],[4],[5],6][] | . as {a:$a} ?// {a:$a} ?// {a:$a} | $a',
        r'[[3],[4],[5],6] | .[] as {a:$a} ?// {a:$a} ?// {a:$a} | $a',
      ]) {
        final seen = outputsAndError(Zaru.compile(source).runJson('null'));
        expect(seen.values, isEmpty, reason: source);
        expect(
          (seen.error! as ZaruRuntimeError).value,
          'Cannot index array with string ("a")',
        );
      }
    });

    test('reduce and foreach take patterns and alternatives', () {
      // jq.test:900
      expect(
        jsonOutputs(
          r'reduce .[] as [$i, {j:$j}] (0; . + $i - $j)',
          '[[2,{"j":1}], [5,{"j":3}], [6,{"j":4}]]',
        ),
        ['5'],
      );
      // jq.test:908
      expect(
        jsonOutputs(
          r'reduce [[1,2,10], [3,4,10]][] as [$i,$j] (0; . + $i * $j)',
          'null',
        ),
        ['14'],
      );
      expect(
        jsonOutputs(
          r'[foreach .[] as [$a, $b] (0; . + $a; [., $b])]',
          '[[1,"x"],[2,"y"]]',
        ),
        ['[[1,"x"],[3,"y"]]'],
      );
      expect(
        jsonOutputs(r'[foreach .[] as [$a] ?// $a (0; . + $a; .)]', '[[1],2]'),
        ['[1,3]'],
      );
    });
  });
}
