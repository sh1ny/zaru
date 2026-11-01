// Core expression semantics through the real compiler and runtime.
//
// Expected values were probed against the pinned jq 1.8.2 binary; none of
// these tests calls jq.
import 'package:test/test.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

/// `{a: {a: ... {}}}` with [wraps] levels of `a` around an empty object,
/// built without recursion.
Map<String, Object?> nestedObject(int wraps) {
  Object? value = <String, Object?>{};
  for (var i = 0; i < wraps; i++) {
    value = <String, Object?>{'a': value};
  }
  return value as Map<String, Object?>;
}

/// `[[ ... [] ...]]` with [wraps] levels of arrays around an empty array.
List<Object?> nestedArray(int wraps) {
  Object? value = <Object?>[];
  for (var i = 0; i < wraps; i++) {
    value = <Object?>[value];
  }
  return value as List<Object?>;
}

Object? errorValueOf(String filter, Object? input) =>
    runtimeErrorValue(Zaru.compile(filter).run(input));

void main() {
  group('alternative, access and optional forms', () {
    test('Alternative suppresses false and null', () {
      expect(jsonOutputs('(false, null, 0, "") // 9', 'null'), ['0', '""']);
      expect(jsonOutputs('(false, null) // 9', 'null'), ['9']);
      expect(jsonOutputs('empty // 9', 'null'), ['9']);
      expect(jsonOutputs('(null, false) // (3, 4)', 'null'), ['3', '4']);
      expect(jsonOutputs('(false, 1, 2) // 3', 'null'), ['1', '2']);
      // The right side is not evaluated once the left produced a value.
      expect(jsonOutputs('1 // error("never")', 'null'), ['1']);
      // An error on the left is not suppressed.
      expect(errorValueOf('(1, error("x")) // 3', null), 'x');
      expect(jsonOutputs('.a // "d"', '{"a":false}'), ['"d"']);
    });

    test('Invalid access versus optional access', () {
      final filter = Zaru.compile('.a');
      expect(
        () => filter.run(1).toList(),
        throwsA(
          isA<ZaruRuntimeError>().having(
            (e) => e.value,
            'value',
            'Cannot index number with string ("a")',
          ),
        ),
      );
      expect(Zaru.compile('.a?').run(1).toList(), isEmpty);
      expect(Zaru.compile('.[]?').run(1).toList(), isEmpty);
      expect(Zaru.compile('.[1:2]?').run(1).toList(), isEmpty);
      expect(errorValueOf('.[]', 1), 'Cannot iterate over number (1)');
      expect(errorValueOf('.[]', null), 'Cannot iterate over null (null)');
      expect(
        errorValueOf('.[0]', {'a': 1}),
        'Cannot index object with number (0)',
      );
      expect(errorValueOf('.a', [1]), 'Cannot index array with string ("a")');
      expect(
        errorValueOf('.[1:2]', 1),
        'Cannot index number with object ({"start":1,"end":2})',
      );
      expect(
        errorValueOf('.[:1]', {}),
        'Cannot index object with object ({"start":null,"end":1})',
      );
      // Only the access is optional: errors in the target still escape.
      expect(errorValueOf('(error("t")).a?', null), 't');
    });

    test('indexing, slicing and iteration', () {
      expect(jsonOutputs('.a.b', '{"a":{"b":3}}'), ['3']);
      expect(jsonOutputs('.["a"]["b"]', '{"a":{"b":3}}'), ['3']);
      expect(jsonOutputs('."a"."b"', '{"a":{"b":3}}'), ['3']);
      expect(jsonOutputs('."a b"', '{"a b":1}'), ['1']);
      expect(jsonOutputs('.a.b.c', '{}'), ['null']);
      expect(jsonOutputs('.[1]', 'null'), ['null']);
      expect(jsonOutputs('.[-1]', '[1,2,3]'), ['3']);
      expect(jsonOutputs('.[5], .[-5]', '[1,2,3]'), ['null', 'null']);
      expect(jsonOutputs('.[1.7]', '[1,2,3]'), ['2']);
      expect(jsonOutputs('.[1:]', '[1,2,3]'), ['[2,3]']);
      expect(jsonOutputs('.[:-1]', '[1,2,3]'), ['[1,2]']);
      expect(jsonOutputs('.[null:2]', '[1,2,3]'), ['[1,2]']);
      expect(jsonOutputs('.[:2][1:]', '[1,2,3]'), ['[2]']);
      expect(jsonOutputs('.[1:2]', 'null'), ['null']);
      expect(jsonOutputs('.[1,2]', '[5,6,7]'), ['6', '7']);
      expect(jsonOutputs('.[]', '{"b":1,"a":2}'), ['1', '2']);
      expect(jsonOutputs('.[][0]', '[[1,2],[3]]'), ['1', '3']);
      expect(jsonOutputs('.[[1]]', '[1,2,1]'), ['[0,2]']);
      expect(
        errorValueOf('.["a":]', [1, 2, 3]),
        'Array/string slice indices must be integers',
      );
      // The key is evaluated against the original input, not the target.
      expect(jsonOutputs('.a[.i]', '{"a":[5,6],"i":1}'), ['6']);
      // Key and slice bounds vary slowest; the target varies fastest.
      expect(jsonOutputs('(.[0], .[1])[(0, 1)]', '[[1,2],[3,4]]'), [
        '1',
        '3',
        '2',
        '4',
      ]);
      expect(jsonOutputs('.[(0, 1):(2, 3)]', '[1,2,3,4]'), [
        '[1,2]',
        '[1,2,3]',
        '[2]',
        '[2,3]',
      ]);
    });
  });

  group('constructors', () {
    test('array and object construction', () {
      expect(jsonOutputs('[]', 'null'), ['[]']);
      expect(jsonOutputs('[.[] | . * 2]', '[1,2]'), ['[2,4]']);
      expect(jsonOutputs('[(1, 2), 3]', 'null'), ['[1,2,3]']);
      expect(jsonOutputs('{}', 'null'), ['{}']);
      expect(jsonOutputs('{a: 1, b: .x}', '{"x":2}'), ['{"a":1,"b":2}']);
      expect(jsonOutputs('{a, b}', '{"a":1}'), ['{"a":1,"b":null}']);
      expect(jsonOutputs('{"a"}', '{"a":1}'), ['{"a":1}']);
      expect(jsonOutputs('1 as \$x | {\$x}', 'null'), ['{"x":1}']);
      expect(jsonOutputs('{"b\\(.a)": 2}', '{"a":1}'), ['{"b1":2}']);
      expect(jsonOutputs('{(.k): .v}', '{"k":"a","v":2}'), ['{"a":2}']);
      expect(jsonOutputs('{a: 1, a: 2}', 'null'), ['{"a":2}']);
      expect(jsonOutputs('{a: 1, b: 2, a: 3}', 'null'), ['{"a":3,"b":2}']);
      expect(jsonOutputs('{(("a", "b")): (1, 2)}', 'null'), [
        '{"a":1}',
        '{"a":2}',
        '{"b":1}',
        '{"b":2}',
      ]);
      expect(jsonOutputs('{a: (1, 2), b: (3, 4)}', 'null'), [
        '{"a":1,"b":3}',
        '{"a":1,"b":4}',
        '{"a":2,"b":3}',
        '{"a":2,"b":4}',
      ]);
      // Keyword-looking names are ordinary keys.
      expect(jsonOutputs('{if: 1, and: 2}', 'null'), ['{"if":1,"and":2}']);
    });

    test('dynamic key types are checked when the key is computed', () {
      expect(
        errorValueOf('{(.k): 1}', {'k': 1}),
        'Cannot use number (1) as object key',
      );
      expect(
        errorValueOf('{(.k): 1}', {'k': null}),
        'Cannot use null (null) as object key',
      );
      // Caught like any other data error.
      expect(jsonOutputs('try {(.k): 1} catch .', '{"k":[1]}'), [
        '"Cannot use array ([1]) as object key"',
      ]);
    });
  });

  group('arithmetic, comparison and boolean operators', () {
    test('arithmetic follows jq', () {
      expect(jsonOutputs('1 + 2', 'null'), ['3']);
      expect(jsonOutputs('null + 1, 1 + null, null + null', 'null'), [
        '1',
        '1',
        'null',
      ]);
      expect(jsonOutputs('"a" + "b"', 'null'), ['"ab"']);
      expect(jsonOutputs('[1] + [2]', 'null'), ['[1,2]']);
      expect(jsonOutputs('{a:1,b:2} + {b:3,c:4}', 'null'), [
        '{"a":1,"b":3,"c":4}',
      ]);
      expect(jsonOutputs('5 - 3, [1,2,1] - [1]', 'null'), ['2', '[2]']);
      expect(jsonOutputs('3 * 4, "ab" * 2', 'null'), ['12', '"abab"']);
      expect(jsonOutputs('{a:{b:1}} * {a:{c:2}}', 'null'), [
        '{"a":{"b":1,"c":2}}',
      ]);
      expect(jsonOutputs('{a:{b:1}} * {a:3}', 'null'), ['{"a":3}']);
      expect(jsonOutputs('7 / 2, "a,b," / ","', 'null'), [
        '3.5',
        '["a","b",""]',
      ]);
      expect(jsonOutputs('"" / ",", "abc" / ""', 'null'), [
        '[]',
        '["a","b","c"]',
      ]);
      expect(jsonOutputs('5 % -3, -5 % 3, 5.9 % 2.9', 'null'), [
        '2',
        '-2',
        '1',
      ]);
      expect(jsonOutputs('-(1, 2)', 'null'), ['-1', '-2']);
      expect(jsonOutputs('1 + 2 * 3 - 4 / 2', 'null'), ['5']);
      // The right operand is the outer loop, the left the inner.
      expect(jsonOutputs('(1, 2) + (10, 20)', 'null'), [
        '11',
        '12',
        '21',
        '22',
      ]);
    });

    test('arithmetic errors carry the pinned messages', () {
      expect(
        errorValueOf('1 + "a"', null),
        'number (1) and string ("a") cannot be added',
      );
      expect(
        errorValueOf('{} - 1', null),
        'object ({}) and number (1) cannot be subtracted',
      );
      expect(
        errorValueOf('[] * 2', null),
        'array ([]) and number (2) cannot be multiplied',
      );
      expect(
        errorValueOf('1 / 0', null),
        'number (1) and number (0) cannot be divided because the divisor is zero',
      );
      expect(
        errorValueOf('"a" / 1', null),
        'string ("a") and number (1) cannot be divided',
      );
      expect(
        errorValueOf('5 % 0', null),
        'number (5) and number (0) cannot be divided (remainder) because the '
        'divisor is zero',
      );
      expect(
        errorValueOf('"a" % 2', null),
        'string ("a") and number (2) cannot be divided (remainder)',
      );
      expect(errorValueOf('-"a"', null), 'string ("a") cannot be negated');
      // Truncated like jq_dump_string_trunc's 30-byte buffer.
      expect(
        errorValueOf('. + 1', List<Object?>.generate(20, (i) => i * 100)),
        'array ([0,100,200,300,400,500,60...]) and number (1) cannot be added',
      );
    });

    test('comparison orders by kind, then value', () {
      expect(
        jsonOutputs(
          '[null < false, false < true, true < 0, 0 < "a", "a" < [], [] < {}]',
          'null',
        ),
        ['[true,true,true,true,true,true]'],
      );
      expect(jsonOutputs('{} < []', 'null'), ['false']);
      expect(jsonOutputs('[{"a":1}] < [{"a":2}]', 'null'), ['true']);
      expect(jsonOutputs('{"a":2} < {"b":1}', 'null'), ['true']);
      expect(jsonOutputs('{"a":2} < {"a":3}', 'null'), ['true']);
      expect(jsonOutputs('[1,2] < [1,2,0], [2] < [1,2]', 'null'), [
        'true',
        'false',
      ]);
      expect(jsonOutputs('1 == 1.0, "a" == "a", [1,[2]] == [1,[2]]', 'null'), [
        'true',
        'true',
        'true',
      ]);
      expect(jsonOutputs('{"a":1,"b":2} == {"b":2,"a":1}', 'null'), ['true']);
      expect(jsonOutputs('1 != 2, 1 <= 1, 2 >= 3, 2 > 1', 'null'), [
        'true',
        'true',
        'false',
        'true',
      ]);
      // NaN is smaller than every number and unequal to itself.
      expect(
        jsonOutputs(
          '.[0] < .[0], .[0] == .[0], .[0] > .[0], .[0] < 1',
          '[NaN]',
        ),
        ['true', 'false', 'false', 'true'],
      );
      expect(jsonOutputs('(1, 2) == (1, 2)', 'null'), [
        'true',
        'false',
        'false',
        'true',
      ]);
      expect(jsonOutputs('(1, 2) < (2, 1)', 'null'), [
        'true',
        'false',
        'false',
        'false',
      ]);
    });

    test('and, or and not', () {
      expect(jsonOutputs('(true, false) and (true, false)', 'null'), [
        'true',
        'false',
        'false',
      ]);
      expect(jsonOutputs('(true, false) or (true, false)', 'null'), [
        'true',
        'true',
        'false',
      ]);
      expect(jsonOutputs('null and error("never")', 'null'), ['false']);
      expect(jsonOutputs('1 or error("never")', 'null'), ['true']);
      expect(jsonOutputs('(null, false, 0, "", [], {}) | not', 'null'), [
        'true',
        'true',
        'false',
        'false',
        'false',
        'false',
      ]);
      expect(jsonOutputs('0 and ""', 'null'), ['true']);
    });

    test('conditionals', () {
      expect(jsonOutputs('if . then "t" else "f" end', 'null'), ['"f"']);
      expect(jsonOutputs('if . then "t" end', '1'), ['"t"']);
      // A missing else is identity, not null.
      expect(jsonOutputs('if . then "t" end', 'false'), ['false']);
      expect(jsonOutputs('if empty then 1 else 2 end', 'null'), isEmpty);
      expect(
        jsonOutputs(
          'if . == 1 then "one" elif . == 2 then "two" else "many" end',
          '2',
        ),
        ['"two"'],
      );
      expect(jsonOutputs('if (true, false) then (1, 2) else 3 end', 'null'), [
        '1',
        '2',
        '3',
      ]);
      expect(jsonOutputs('[if (null, 1) then 1 else 2 end]', 'null'), [
        '[2,1]',
      ]);
      // The condition sees the original input.
      expect(jsonOutputs('if .a then .b else .c end', '{"a":1,"b":2,"c":3}'), [
        '2',
      ]);
    });

    test('bindings', () {
      expect(jsonOutputs(r'. as $x | $x + 1', '4'), ['5']);
      expect(jsonOutputs(r'1 as $x | 2 as $x | $x', 'null'), ['2']);
      expect(jsonOutputs(r'(1, 2) as $x | $x * 10', 'null'), ['10', '20']);
      expect(jsonOutputs(r'(1, 2) as $x | (3, 4) as $y | [$x, $y]', 'null'), [
        '[1,3]',
        '[1,4]',
        '[2,3]',
        '[2,4]',
      ]);
      // The body sees the original input; the bound value is separate.
      expect(jsonOutputs(r'.a as $x | .b + $x', '{"a":1,"b":2}'), ['3']);
    });

    test('Deep object merge boundary', () {
      final ok = nestedObject(10000);
      final tooDeep = nestedObject(10001);
      // 10000 wraps merge; the result equals the operand.
      expect(Zaru.compile(r'. as $x | ($x * $x) == $x').run(ok).toList(), [
        true,
      ]);
      expect(jsonOutputsNative(r'try (. as $x | $x * $x) catch .', tooDeep), [
        '"Object merge too deep"',
      ]);
      // The inputs are untouched and the failure is a catchable data error.
      expect(
        errorValueOf(r'. as $x | $x * $x', tooDeep),
        'Object merge too deep',
      );
      expect(Zaru.compile(r'. * .').run(nestedObject(10000)).length, 1);
    });

    test('Excessive structural equality', () {
      // Two distinct arrays nested 10001 times around [] (jq.test:2616).
      final input = [nestedArray(10001), nestedArray(10001)];
      expect(jsonOutputsNative('try (.[0] == .[1]) catch .', input), [
        '"Equality check too deep"',
      ]);
      expect(errorValueOf('.[0] != .[1]', input), 'Equality check too deep');
      // The same values one level shallower compare normally.
      final shallow = [nestedArray(10000), nestedArray(10000)];
      expect(nativeOutputs('.[0] == .[1]', shallow), ['true']);
      expect(nativeOutputs('.[0] == .[1]', [nestedArray(3), nestedArray(4)]), [
        'false',
      ]);
      // Ordering is guarded by its own depth check.
      expect(jsonOutputsNative('try (.[0] < .[1]) catch .', input), [
        '"Comparison too deep"',
      ]);
    });

    test('Identity shortcut does not recurse through the same value', () {
      final deep = nestedArray(10001);
      expect(nativeOutputs(r'. as $x | $x == $x', deep), ['true']);
      expect(nativeOutputs(r'. as $x | $x != $x', deep), ['false']);
      // Ordering has no such shortcut.
      expect(jsonOutputsNative(r'try (. as $x | $x < $x) catch .', deep), [
        '"Comparison too deep"',
      ]);
    });

    test('Oversized repeated string', () {
      expect(
        errorValueOf('"abc" * 1000000000', null),
        'Repeat string result too long',
      );
      expect(jsonOutputs('try ("abc" * 1000000000) catch .', 'null'), [
        '"Repeat string result too long"',
      ]);
      expect(
        errorValueOf('1000000000 * "abc"', null),
        'Repeat string result too long',
      );
      // The limit is on UTF-8 bytes: one 4-byte character times 2^29 is
      // exactly 2147483648 >= the limit, while a count below it only
      // allocates when requested.
      expect(
        errorValueOf('"😀" * 536870912', null),
        'Repeat string result too long',
      );
      expect(jsonOutputs('"😀" * 3', 'null'), ['"😀😀😀"']);
      expect(jsonOutputs('"" * 1000000000', 'null'), ['""']);
    });

    test('Repetition truncates counts and preserves jq null cases', () {
      expect(jsonOutputs('"a" * .[]', '[-1, NaN, -0.5, 0, 0.5, 1.5, 2.9]'), [
        'null',
        'null',
        'null',
        '""',
        '""',
        '"a"',
        '"aa"',
      ]);
      expect(jsonOutputs('.[] * "a"', '[-1, NaN, 0, 0.5, 1.5]'), [
        'null',
        'null',
        '""',
        '""',
        '"a"',
      ]);
    });
  });
}

/// Like [nativeOutputs] with a name that reads naturally in guard tests.
List<String> jsonOutputsNative(String filter, Object? input) =>
    nativeOutputs(filter, input);
