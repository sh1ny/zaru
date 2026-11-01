// Ownership of engine-created containers and the public projection memo.
import 'package:test/test.dart';
import 'package:zaru/zaru.dart';

void main() {
  group('engine-created collections', () {
    test('Read an engine-created collection normally', () {
      final result = Zaru.compile('[1, {a: 2}]').run(null).single;
      expect(result, isA<List<Object?>>());
      final list = result! as List<Object?>;
      expect(list, hasLength(2));
      expect(list[0], 1);
      final map = list[1]! as Map<String, Object?>;
      expect(map['a'], 2);
      expect(map.keys, ['a']);
      expect(list, [
        1,
        {'a': 2},
      ]);
      expect([for (final entry in map.entries) entry.key], ['a']);
    });

    test('Literal reuse after mutation attempt', () {
      final filter = Zaru.compile('[1]');
      final first = filter.run(null).single! as List<Object?>;
      expect(() => first.add(2), throwsUnsupportedError);
      expect(() => first[0] = 9, throwsUnsupportedError);
      expect(() => first.clear(), throwsUnsupportedError);
      expect(filter.run(null).single, [1]);
      // Nested literal containers are frozen too, and objects as well.
      final nested =
          Zaru.compile('[{"a": [1]}]').run(null).single! as List<Object?>;
      final map = nested[0]! as Map<String, Object?>;
      expect(() => map['b'] = 1, throwsUnsupportedError);
      expect(() => (map['a']! as List<Object?>).add(2), throwsUnsupportedError);
      expect(() => map.remove('a'), throwsUnsupportedError);
      expect(Zaru.compile('[{"a": [1]}]').run(null).single, [
        {
          'a': [1],
        },
      ]);
    });

    test('constructed values are fresh per evaluation but immutable', () {
      final filter = Zaru.compile('[., .]');
      final a = filter.run(1).single! as List<Object?>;
      final b = filter.run(2).single! as List<Object?>;
      expect(a, [1, 1]);
      expect(b, [2, 2]);
      expect(() => a.add(3), throwsUnsupportedError);
      // Each yield is a separate immutable list.
      final results = Zaru.compile(
        '[.[]] , [.[] | . + 1]',
      ).run([1, 2]).toList();
      expect(results, [
        [1, 2],
        [2, 3],
      ]);
      expect(identical(results[0], results[1]), isFalse);
    });
  });

  group('projection memo', () {
    test('Repeated subtree yields reuse one projection', () {
      final results = Zaru.compile(
        '.x, .x',
      ).runJson('{"x":[1.0, 2, 3.50, 12345678909876543212345]}').toList();
      expect(results, hasLength(2));
      expect(identical(results[0], results[1]), isTrue);
      final list = results[0]! as List<Object?>;
      expect(list[0], isA<ZaruNumber>());
      expect((list[0]! as ZaruNumber).literal, '1.0');
      expect(list[1], 2);
      expect(list[1], isA<num>());
      expect((list[2]! as ZaruNumber).literal, '3.50');
      expect((list[3]! as ZaruNumber).literal, '12345678909876543212345');
      expect(() => list.add(1), throwsUnsupportedError);
      // The whole document projects once as well.
      final whole = Zaru.compile('., .').runJson('{"x":[1.0]}').toList();
      expect(identical(whole[0], whole[1]), isTrue);
      expect(
        () => (whole[0]! as Map<String, Object?>)['y'] = 1,
        throwsUnsupportedError,
      );
    });

    test('Changed containers do not alias projections', () {
      final results = Zaru.compile('., . + [2]').runJson('[1]').toList();
      expect(results, [
        [1],
        [1, 2],
      ]);
      final first = results[0]! as List<Object?>;
      final second = results[1]! as List<Object?>;
      expect(identical(first, second), isFalse);
      expect(() => first.add(5), throwsUnsupportedError);
      expect(() => second.add(5), throwsUnsupportedError);
      expect(first, [1]);
      expect(second, [1, 2]);
      // A projection taken first is not changed by creating a later one.
      final again = Zaru.compile('., . + [2], .').runJson('[1]').toList();
      expect(identical(again[0], again[2]), isTrue);
      expect(again[0], [1]);
    });
  });

  group('native inputs', () {
    test('Native narrowing paths become owned once', () {
      final wrapper = ZaruNumber.parse('42');
      final input = <Object?>[wrapper];
      final results = Zaru.compile(
        '., ., (.[0] == 42.0000000000000001)',
      ).run(input).toList();
      expect(results, hasLength(3));
      expect(identical(results[0], results[1]), isTrue);
      expect(identical(results[0], input), isFalse);
      final owned = results[0]! as List<Object?>;
      expect(owned, [42]);
      expect(owned[0], isA<num>());
      expect(owned[0], isNot(isA<ZaruNumber>()));
      expect(() => owned.add(1), throwsUnsupportedError);
      // The private literal origin survived: literal 42 differs from
      // 42.0000000000000001 even though the plain output is an ordinary 42.
      expect(results[2], isFalse);
      // The caller's list is untouched and still mutable.
      expect(identical(input[0], wrapper), isTrue);
      input.add('later');
      expect(input, hasLength(2));
    });

    test('Public-compatible native storage remains shared', () {
      final input = <Object?>[42, 'a'];
      final result = Zaru.compile('.').run(input).single;
      expect(identical(result, input), isTrue);
      // Not frozen, memoized or converted: caller mutation stays the caller's.
      input.add(1.5);
      expect(input, [42, 'a', 1.5]);
      expect(identical(Zaru.compile('.').run(input).single, input), isTrue);
      final map = <String, Object?>{
        'k': [1, 2],
        'z': null,
      };
      expect(identical(Zaru.compile('.').run(map).single, map), isTrue);
      // A compatible child of an owned container is still shared.
      final inner = <Object?>[1, 2];
      final shared = Zaru.compile(
        '.[1]',
      ).run(<Object?>[ZaruNumber.parse('1.50'), inner]).single;
      expect(identical(shared, inner), isTrue);
    });

    test('lone surrogates and key collisions normalize on an owned path', () {
      final input = <String, Object?>{'a\uD800': 1, 'a�': 2};
      final result =
          Zaru.compile('.').run(input).single! as Map<String, Object?>;
      // Both keys normalize to the same text: first position, last value.
      expect(result, {'a�': 2});
      expect(identical(result, input), isFalse);
      expect(input.length, 2);
    });

    test('unsupported caller data is an argument error, not a jq error', () {
      final iterator = Zaru.compile('.').run(Object()).iterator;
      expect(() => iterator.moveNext(), throwsArgumentError);
      expect(iterator.moveNext(), isFalse);
      expect(
        () => Zaru.compile('.').run({1: 2}).iterator.moveNext(),
        throwsArgumentError,
      );
    });
  });
}
