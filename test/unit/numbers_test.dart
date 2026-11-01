// Direct tests of the private number layer and the public ZaruNumber API.
//
// Several rows of the change's test map are phrased as filter runs ("identity
// filter", "-.", "+ 0"). Until group 4 provides the compiler these tests drive
// the same private operations the evaluator will call (decode, negate,
// convert, compare, export); they do not claim any filter works.
import 'package:test/test.dart';
import 'package:zaru/src/json_decoder.dart';
import 'package:zaru/src/json_printer.dart';
import 'package:zaru/src/number.dart';
import 'package:zaru/src/value.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

/// dart2js is the only target where int and double overlap.
final bool overlappingNumbers = identical(1, 1.0);

JqNumber lit(String token) {
  final number = JqNumber.tryParseLiteral(token);
  if (number == null) fail('expected a valid jq numeric token: $token');
  return number;
}

JqNumber decodeNumber(String json) => decodeJqJson(json) as JqNumber;

void main() {
  group('ZaruNumber public API', () {
    test('Explicit construction and canonical text', () {
      final n = ZaruNumber.parse('100e-2');
      expect(n.literal, '1.00');
      expect(n.toString(), '1.00');
      expect(n.toDouble(), 1.0);
      expect((n as Object) is num, isFalse);
      expect((n as Object) is Comparable<Object?>, isFalse);

      const canonical = {
        '+1': '1',
        '.5': '0.5',
        '1.': '1',
        '-.5': '-0.5',
        '00012': '12',
        '1E5': '1E+5',
        '1e+05': '1E+5',
        '1.50': '1.50',
        '-0.0': '-0.0',
        '0.00000': '0.00000',
        '-0e-5': '-0.00000',
        '0e-7': '0E-7',
        '12e-7': '0.0000012',
        '12e-8': '1.2E-7',
        '5.E3': '5E+3',
        '123456789012345678901234567890': '123456789012345678901234567890',
        '1234.5e1': '12345',
        '1234.5e-1': '123.45',
        '100': '100',
        '0': '0',
      };
      canonical.forEach((input, expected) {
        expect(ZaruNumber.parse(input).literal, expected, reason: input);
      });
    });

    test('Invalid exact-number construction', () {
      const invalid = [
        'NaN',
        '-NaN',
        'nan',
        'sNaN',
        'Infinity',
        '-Infinity',
        'inf',
        '+INF',
        // Normalized to infinity by the pinned decimal context.
        '1e1000000000',
        '-1e1000000000',
        '1e99999999999',
        '1x',
        '',
        ' 1',
        '1 ',
        '--1',
        '+-1',
        '.',
        '-',
        'e5',
        '1e',
        '1e+',
        '1.2.3',
        '0x10',
        '1_0',
        'true',
        '١',
      ];
      for (final text in invalid) {
        expect(
          () => ZaruNumber.parse(text),
          throwsA(
            isA<FormatException>().having((e) => e.source, 'source', text),
          ),
          reason: 'parse(${text.isEmpty ? "<empty>" : text})',
        );
      }
    });

    test('Equal numbers can have distinct preserved spellings', () {
      final a = ZaruNumber.parse('1.00');
      final b = ZaruNumber.parse('1.0');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.literal, '1.00');
      expect(b.literal, '1.0');
      expect(a == (1 as Object), isFalse);
      expect((1 as Object) == a, isFalse);
      expect(a == (1.0 as Object), isFalse);
      expect(a == ZaruNumber.parse('1.01'), isFalse);

      // Scale, exponent spelling and zero sign are not part of the value.
      expect(ZaruNumber.parse('1E+2'), ZaruNumber.parse('100'));
      expect(
        ZaruNumber.parse('1E+2').hashCode,
        ZaruNumber.parse('100.000').hashCode,
      );
      final zeros = ['0', '-0', '0.00', '-0.0', '0E+5', '0e-1000000000'];
      for (final z in zeros) {
        expect(ZaruNumber.parse(z), ZaruNumber.parse('0'), reason: z);
        expect(
          ZaruNumber.parse(z).hashCode,
          ZaruNumber.parse('0').hashCode,
          reason: z,
        );
      }
      expect(ZaruNumber.parse('-1'), isNot(ZaruNumber.parse('1')));
      expect(
        ZaruNumber.parse('9007199254740993'),
        isNot(ZaruNumber.parse('9007199254740992')),
      );
      // No exponent-sized allocation to compare or hash extreme exponents.
      expect(
        ZaruNumber.parse('1e999999999'),
        isNot(ZaruNumber.parse('9e999999999')),
      );
      expect(ZaruNumber.parse('10e999999998'), ZaruNumber.parse('1e999999999'));
      expect(
        ZaruNumber.parse('10e999999998').hashCode,
        ZaruNumber.parse('1e999999999').hashCode,
      );
      expect(
        ZaruNumber.parse('1e-1000000000'),
        isNot(ZaruNumber.parse('1e-999999999')),
      );
    });
  });

  group('literal canonicalization and decimal context (private layer)', () {
    test('Decimal context exponent edges', () {
      expect(ZaruNumber.parse('0e1000000000').literal, '0E+999999999');
      expect(ZaruNumber.parse('1e-1000000000').literal, '1E-1000000000');
      final big = ZaruNumber.parse('1e1000');
      expect(big.literal, '1E+1000');
      expect(big.toDouble(), double.infinity);
      // Adding zero converts to a computed double, which prints clamped.
      expect(
        printJson(JqNumber.computed(big.toDouble() + 0)),
        '1.7976931348623157e+308',
      );
      expect(
        printJson(JqNumber.computed(-ZaruNumber.parse('1e1000').toDouble())),
        '-1.7976931348623157e+308',
      );

      // Exact edges of the pinned decimal context.
      expect(ZaruNumber.parse('9E+999999999').literal, '9E+999999999');
      expect(ZaruNumber.parse('1e999999999').literal, '1E+999999999');
      expect(ZaruNumber.parse('0e1999999999').literal, '0E+999999999');
      expect(ZaruNumber.parse('0.0e1999999998').literal, '0E+999999999');
      expect(ZaruNumber.parse('0e-1200000000').literal, '0E-1147483646');
      expect(ZaruNumber.parse('0e99999999999').literal, '0E+999999999');
      expect(ZaruNumber.parse('1e-1147483646').literal, '1E-1147483646');
      expect(ZaruNumber.parse('12e-1147483646').literal, '1.2E-1147483645');
      // Below the smallest exponent, digits are rounded half up.
      expect(ZaruNumber.parse('5e-1147483647').literal, '1E-1147483646');
      expect(ZaruNumber.parse('4e-1147483647').literal, '0E-1147483646');
      expect(ZaruNumber.parse('-4e-1147483647').literal, '-0E-1147483646');
      expect(ZaruNumber.parse('5e-1147483648').literal, '0E-1147483646');
      expect(ZaruNumber.parse('15e-1147483647').literal, '2E-1147483646');
      expect(ZaruNumber.parse('14e-1147483647').literal, '1E-1147483646');
      expect(ZaruNumber.parse('95e-1147483647').literal, '1.0E-1147483645');
      expect(ZaruNumber.parse('1e-99999999999').literal, '0E-1147483646');
      // Overflow is infinite: the finite-only wrapper rejects it, the token
      // stays a literal-origin infinity in the private layer.
      final infinite = lit('1e1000000000');
      expect(infinite.isLiteral, isTrue);
      expect(infinite.value, double.infinity);
      expect(lit('-1e1000000000').value, double.negativeInfinity);
      expect(lit('12e999999999').value, double.infinity);
      expect(printJson(lit('1e1000000000')), '1.7976931348623157e+308');
      expect(printJson(lit('-1e1000000000')), '-1.7976931348623157e+308');
      // Context exponent limits never allocate an exponent-sized string.
      final sw = Stopwatch()..start();
      for (final t in ['1e999999999', '1e-1147483646', '0e-1147483646']) {
        final n = lit(t);
        n.value;
        n.text;
        n.negate().text;
        JqNumber.compare(n, lit('1'));
      }
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('Two-step rounding at a binary midpoint', () {
      // Direct binary parsing would round this to ...994; jq first reduces the
      // decimal to 17 significant digits (half-even), then converts.
      final n = lit('9007199254740993.00000000001');
      expect(n.value, 9007199254740992.0);
      expect(printJson(JqNumber.computed(n.value + 0)), '9007199254740992');
      expect(lit('9007199254740993').value, 9007199254740992.0);
      expect(lit('9007199254740995').value, 9007199254740996.0);
      // 17-digit reduction: halfway between 1 and 1 + 2^-52 is not reached.
      expect(
        lit('1.00000000000000011102230246251565404236316680908203125').value,
        1.0,
      );
      expect(
        lit('1.00000000000000011102230246251565404236316680908203126').value,
        1.0,
      );
      expect(lit('0.1').value, 0.1);
      expect(lit('1.2345678901234567890123').value, 1.2345678901234567);
      expect(lit('8.5000000000000001e0').value, 8.5);
      expect(lit('123456789012345678').value, 123456789012345680.0);
      expect(lit('-0.30000000000000004441').value, -0.30000000000000004);
      // Range extremes.
      expect(lit('1.7976931348623157e308').value, 1.7976931348623157e308);
      expect(lit('1.7976931348623158e308').value, 1.7976931348623157e308);
      expect(lit('1.7976931348623159e308').value, double.infinity);
      expect(lit('1e309').value, double.infinity);
      expect(lit('4.9e-324').value, 5e-324);
      expect(lit('2.4703282292062327e-324').value, 0.0);
      expect(lit('2.4703282292062328e-324').value, 5e-324);
      expect(lit('1e-400').value, 0.0);
      expect(lit('-1e-400').value.isNegative, isTrue);
      expect(lit('1e-1000000000').value, 0.0);
      expect(lit('0e1000000000').value, 0.0);
      expect(lit('-0').value.isNegative, isTrue);
      expect(lit('-0.0').value.isNegative, isTrue);
      expect(lit('0').value.isNegative, isFalse);
    });

    test('Negate large literal without rounding', () {
      expect(
        decodeNumber('13911860366432393').negate().text,
        '-13911860366432393',
      );
      expect(
        printJson(decodeNumber('13911860366432393').negate()),
        '-13911860366432393',
      );
      expect(
        printJson(decodeNumber('-0.12345678901234567890123456789').negate()),
        '0.12345678901234567890123456789',
      );
      expect(lit('1.00').negate().text, '-1.00');
      expect(lit('-1E+1000').negate().text, '1E+1000');
      expect(lit('1e1000000000').negate().value, double.negativeInfinity);
      // Negation keeps literal origin; computed negation stays computed.
      expect(lit('5').negate().isLiteral, isTrue);
      expect(JqNumber.computed(5).negate().isLiteral, isFalse);
    });

    test('Mixed comparison after arithmetic rounding', () {
      final n = decodeNumber('13911860366432393');
      // `. as $n | $n + 0 | [., . == $n]`
      final sum = JqNumber.computed(n.value + 0);
      expect(printJson(sum), '13911860366432392');
      expect(JqNumber.compare(sum, n), 0);
      expect(JqNumber.compare(n, sum), 0);
      // An exact-decimal comparison (the fixture oracle's rule) differs.
      expect(
        ZaruNumber.parse('13911860366432392') ==
            ZaruNumber.parse('13911860366432393'),
        isFalse,
      );
    });

    test(
      'literal/literal comparison is decimal, anything else uses doubles',
      () {
        expect(JqNumber.compare(lit('42'), lit('42.0000000000000001')), -1);
        expect(JqNumber.compare(lit('42.0000000000000001'), lit('42')), 1);
        expect(JqNumber.compare(lit('1.0'), lit('1.00')), 0);
        expect(JqNumber.compare(lit('1E+2'), lit('100')), 0);
        expect(JqNumber.compare(lit('-0'), lit('0')), 0);
        expect(JqNumber.compare(lit('-1'), lit('-0.5')), -1);
        expect(JqNumber.compare(lit('-2'), lit('-10')), 1);
        expect(JqNumber.compare(lit('123'), lit('1234')), -1);
        expect(JqNumber.compare(lit('1e999999999'), lit('9e999999998')), 1);
        expect(JqNumber.compare(lit('1e-1000000000'), lit('0')), 1);
        expect(JqNumber.compare(lit('-1e-1000000000'), lit('0')), -1);
        expect(JqNumber.compare(lit('1e1000000000'), lit('1e999999999')), 1);
        expect(JqNumber.compare(lit('1e1000000000'), lit('Infinity')), 0);
        expect(JqNumber.compare(lit('-Infinity'), lit('-1e999999999')), -1);
        // computed 42 against literal 42.0000000000000001 falls back to doubles.
        expect(
          JqNumber.compare(JqNumber.computed(42), lit('42.0000000000000001')),
          0,
        );
        expect(
          JqNumber.compare(lit('42.0000000000000001'), JqNumber.computed(42)),
          0,
        );
        expect(JqNumber.compare(JqNumber.computed(41), lit('42')), -1);
        expect(JqNumber.compare(JqNumber.computed(double.nan), lit('1')), 1);
      },
    );
  });

  group('public output classification (private layer)', () {
    test('Ordinary number remains plain', () {
      final i = decodeNumber('42').export();
      final d = decodeNumber('0.5').export();
      expect(i, isA<num>());
      expect(i, 42);
      expect(d, isA<num>());
      expect(d, 0.5);
      if (!overlappingNumbers) {
        expect(i, isA<int>());
        expect(d, isA<double>());
      }
      expect(lit('-7').export(), -7);
      expect(lit('1000').export(), 1000);
      expect(lit('9007199254740991').export(), 9007199254740991.0);
      expect(lit('-9007199254740991').export(), -9007199254740991.0);
      expect(lit('0.25').export(), 0.25);
      expect(lit('-0.5').export(), -0.5);
      expect(lit('123.456').export(), 123.456);
      expect(lit('0.0001').export(), isA<double>());
      for (final t in ['42', '0.5', '-7', '1000', '123.456', '0.0001']) {
        expect(lit(t).export(), isNot(isA<ZaruNumber>()), reason: t);
      }
    });

    test('Precision and scale require a wrapper', () {
      const expected = {
        '1.00': '1.00',
        '1.0': '1.0',
        '1e2': '1E+2',
        '100e-2': '1.00',
        '9007199254740993': '9007199254740993',
        '9E+999999999': '9E+999999999',
      };
      expected.forEach((input, text) {
        final out = lit(input).export();
        expect(out, isA<ZaruNumber>(), reason: input);
        expect((out as ZaruNumber).literal, text, reason: input);
      });
      // Beyond the safe-integer range, even exactly printable integers wrap.
      expect(lit('9007199254740992').export(), isA<ZaruNumber>());
      expect(lit('-9007199254740992').export(), isA<ZaruNumber>());
      expect(lit('90071992547409920').export(), isA<ZaruNumber>());
      expect(lit('12345678909876543212345').export(), isA<ZaruNumber>());
      // Spelling that differs from the computed spelling of the converted
      // value wraps, in either direction.
      expect(lit('1e-7').export(), isA<ZaruNumber>());
      expect(lit('1E+1000').export(), isA<ZaruNumber>());
      expect(lit('0.10').export(), isA<ZaruNumber>());
      expect(lit('0E+5').export(), isA<ZaruNumber>());
      expect(lit('-0.0').export(), isA<ZaruNumber>());
      expect(lit('0.0').export(), isA<ZaruNumber>());
    });

    test('Literal negative zero follows jq canonicalization', () {
      final n = decodeNumber('-0');
      final out = n.export();
      expect(out, isA<double>());
      expect((out as double).isNegative, isTrue);
      expect(out, 0.0);
      expect(printJson(n), '-0');
      expect(JqNumber.compare(n, lit('0')), 0);
      expect(JqNumber.compare(n, JqNumber.computed(0)), 0);
      // The compiled filter expression `-0` is a different path: negating a
      // literal zero yields positive zero, whatever the sign or scale.
      expect(lit('0').negate().text, '0');
      expect(lit('-0').negate().text, '0');
      expect(lit('0e5').negate().text, '0E+5');
      expect(lit('-0e5').negate().text, '0E+5');
      expect(lit('-0.0').negate().text, '0.0');
      expect(lit('0.0').negate().text, '0.0');
      // Computed negation follows binary64.
      expect(JqNumber.computed(0).negate().value.isNegative, isTrue);
      expect(printJson(JqNumber.computed(0).negate()), '-0');
      expect(JqNumber.computed(-0.0).negate().value.isNegative, isFalse);
      expect(printJson(JqNumber.computed(-0.0).negate()), '0');
    });
  });

  group('native numeric input (private layer)', () {
    test('Integral native doubles have no source scale', () {
      for (final native in <num>[1, 1.0]) {
        final n = JqNumber.fromNative(native);
        expect(n.isLiteral, isFalse);
        expect(n.value, 1.0);
        expect(n.text, '1');
        expect(n.export(), 1);
        expect(n.export(), isNot(isA<ZaruNumber>()));
      }
      expect(JqNumber.fromNative(100.0).text, '100');
      expect(JqNumber.fromNative(-3.0).text, '-3');
    });

    test('Unsafe native input cannot recover missing digits', () {
      // A host that already rounded 9007199254740993 supplies ...992, which is
      // exactly representable: computed origin, no recovered digits.
      final n = JqNumber.fromNative(9007199254740992.0);
      expect(n.isLiteral, isFalse);
      expect(n.text, '9007199254740992');
      expect(n.export(), 9007199254740992.0);
      final big = JqNumber.fromNative(1e22);
      expect(big.isLiteral, isFalse);
      expect(big.export(), 1e22);
    });

    test('Ordinary native doubles stay plain', () {
      const values = [0.00001, 1.5e-7, 1e16, 1e23, 1e300, 5e-324, 1.5, -2.5];
      for (final v in values) {
        final n = JqNumber.fromNative(v);
        expect(n.isLiteral, isFalse, reason: '$v');
        final out = n.export();
        expect(out, isA<num>(), reason: '$v');
        expect(out, isNot(isA<ZaruNumber>()), reason: '$v');
        expect(out, v, reason: '$v');
      }
      // Computed spelling, never an expanded integer coefficient.
      expect(printJson(1e23), '1e+23');
      expect(printJson(1e300), '1e+300');
      expect(printJson(1e16), '1e+16');
      expect(printJson(0.00001), '1e-05');
      expect(printJson(1.5e-7), '1.5e-07');
    });

    test('Native large-double comparison uses fallback', () {
      // `. == 1e23` on native 1e23: computed/literal compares as doubles.
      expect(JqNumber.compare(JqNumber.fromNative(1e23), lit('1e23')), 0);
      expect(
        JqNumber.compare(
          JqNumber.fromNative(1e23),
          lit('100000000000000000000000'),
        ),
        0,
      );
    });

    test('Native nonrepresentable integer retains exactness', () {
      if (overlappingNumbers) {
        markTestSkipped('dart2js cannot hold the unrounded integer');
        return;
      }
      // int.parse avoids a compile-time literal that dart2js rejects.
      final x = int.parse('9007199254740993');
      final n = JqNumber.fromNative(x);
      expect(n.isLiteral, isTrue);
      expect(n.text, '9007199254740993');
      final out = n.export();
      expect(out, isA<ZaruNumber>());
      expect((out as ZaruNumber).literal, '9007199254740993');
      final min = JqNumber.fromNative(int.parse('-9223372036854775807'));
      expect(min.text, '-9223372036854775807');
      final max = JqNumber.fromNative(int.parse('9223372036854775807'));
      expect(max.isLiteral, isTrue);
      expect(max.text, '9223372036854775807');
      // Exactly representable large integers remain computed.
      expect(
        JqNumber.fromNative(int.parse('9007199254740992')).isLiteral,
        isFalse,
      );
      expect(
        JqNumber.fromNative(int.parse('4611686018427387904')).isLiteral,
        isFalse,
      );
      expect(
        JqNumber.fromNative(int.parse('-9223372036854775808')).isLiteral,
        isFalse,
      );
      expect(printJson(x), '9007199254740993');
    });

    test('Native signed zero survives identity', () {
      final n = JqNumber.fromNative(-0.0);
      expect(n.isLiteral, isFalse);
      final out = n.export();
      expect(out, isA<num>());
      expect((out as num).isNegative, isTrue);
      expect(out, 0);
      expect(printJson(out), '-0');
      expect(JqNumber.compare(n, JqNumber.fromNative(0)), 0);
      expect(printJson(0.0), '0');
      expect(JqNumber.fromNative(double.nan).isNan, isTrue);
      expect(JqNumber.fromNative(double.infinity).value, double.infinity);
    });
  });

  group('literal tokens accepted by jv_parse', () {
    test('numeric extensions and nonfinite spellings', () {
      expect(lit('+1').text, '1');
      expect(lit('01').text, '1');
      expect(lit('.5').text, '0.5');
      expect(lit('1.').text, '1');
      expect(lit('NaN').isNan, isTrue);
      expect(lit('-nan').isNan, isTrue);
      expect(lit('sNaN').isNan, isTrue);
      expect(lit('NaN000').isNan, isTrue);
      expect(lit('Infinity').value, double.infinity);
      expect(lit('-infinity').value, double.negativeInfinity);
      expect(lit('+INF').value, double.infinity);
      expect(lit('iNf').value, double.infinity);
      for (final bad in [
        'NaN1',
        'NaN10',
        'sNaN12',
        'Infinit',
        'Infinityx',
        '.inf',
        'infin ity',
        '1e',
        '1e+',
        '++1',
        '1.2.3',
        '0x1',
        '',
        '.',
        '-',
        '1,',
        '1 ',
        'e1',
        '1e1.5',
        'true',
        'nul',
        '١٢',
      ]) {
        expect(JqNumber.tryParseLiteral(bad), isNull, reason: bad);
      }
    });

    test('exponent digit counting saturates like the pinned context', () {
      expect(lit('1e1999999999').value, double.infinity);
      expect(lit('1e-1999999999').text, '0E-1147483646');
      expect(lit('1e00000000000000000000000000005').text, '1E+5');
      expect(lit('1e99999999999999999999999').value, double.infinity);
      expect(lit('1e-99999999999999999999999').text, '0E-1147483646');
      expect(lit('0e99999999999999999999999').text, '0E+999999999');
    });
  });

  group('JqArray/JqObject', () {
    test('containers expose unmodifiable storage', () {
      final array = JqArray([1, 2]);
      expect(() => array.items.add(3), throwsUnsupportedError);
      final object = JqObject({'a': 1});
      expect(() => object.entries['b'] = 2, throwsUnsupportedError);
    });
  });

  group('through compiled filters', () {
    Object? one(String filter, String json) =>
        Zaru.compile(filter).runJson(json).single;

    test('Large integer source', () {
      final filter = Zaru.compile('12345678909876543212345');
      final result = filter.run(null).single;
      expect(result, isA<ZaruNumber>());
      expect((result! as ZaruNumber).literal, '12345678909876543212345');
      expect(Zaru.toJson(result), '12345678909876543212345');
      expect(jsonOutputs('[12345678909876543212345, 1.000]', 'null'), [
        '[12345678909876543212345,1.000]',
      ]);
    });

    test('Exact input survives nested and argument boundaries', () {
      final big = ZaruNumber.parse('12345678909876543212345');
      final filter = Zaru.compile(
        r'.id, $big, [.id, $big]',
        variables: {'big'},
      );
      final results = filter.run({'id': big}, args: {'big': big}).toList();
      expect(results[0], big);
      expect(results[1], big);
      expect(results[2], [big, big]);
      expect(results.map(Zaru.toJson).toList(), [
        '12345678909876543212345',
        '12345678909876543212345',
        '[12345678909876543212345,12345678909876543212345]',
      ]);
      // The wrapper at the root, as well.
      expect(Zaru.compile('.').run(big).single, big);
    });

    test('Negate large literal without rounding', () {
      expect(jsonOutputs('-.', '13911860366432393'), ['-13911860366432393']);
      expect(jsonOutputs('-.', '-0.12345678901234567890123456789'), [
        '0.12345678901234567890123456789',
      ]);
      expect(jsonOutputs('-.', '1.00'), ['-1.00']);
    });

    test('Mixed comparison after arithmetic rounding', () {
      expect(
        jsonOutputs(r'. as $n | $n + 0 | [., . == $n]', '13911860366432393'),
        ['[13911860366432392,true]'],
      );
    });

    test('Two-step rounding at a binary midpoint', () {
      expect(jsonOutputs('9007199254740993.00000000001 + 0', 'null'), [
        '9007199254740992',
      ]);
    });

    test('Decimal context exponent edges', () {
      expect(jsonOutputs('.', '0e1000000000'), ['0E+999999999']);
      expect(jsonOutputs('.', '1e-1000000000'), ['1E-1000000000']);
      final huge = one('.', '1e1000');
      expect(huge, isA<ZaruNumber>());
      expect((huge! as ZaruNumber).literal, '1E+1000');
      expect((huge as ZaruNumber).toDouble(), double.infinity);
      expect(jsonOutputs('. + 0', '1e1000'), ['1.7976931348623157e+308']);
      expect(jsonOutputs('. + 0', '1e-1000000000'), ['0']);
      // The same spellings inside a filter literal.
      expect(jsonOutputs('1e1000', 'null'), ['1E+1000']);
    });

    test('Ordinary number remains plain', () {
      final i = one('.', '42');
      final d = one('.', '0.5');
      expect(i, isA<num>());
      expect(i, 42);
      expect(d, isA<num>());
      expect(d, 0.5);
      if (!overlappingNumbers) {
        expect(i, isA<int>());
        expect(d, isA<double>());
      }
      expect(one('.', '-7'), -7);
      expect(one('.', '9007199254740991'), 9007199254740991);
      expect(one('.', '2.5e-3'), 2.5e-3);
    });

    test('Precision and scale require a wrapper', () {
      const expected = {
        '1.00': '1.00',
        '1.0': '1.0',
        '1e2': '1E+2',
        '100e-2': '1.00',
        '9007199254740993': '9007199254740993',
        '9E+999999999': '9E+999999999',
      };
      expected.forEach((source, literal) {
        final result = one('.', source);
        expect(result, isA<ZaruNumber>(), reason: source);
        expect((result! as ZaruNumber).literal, literal, reason: source);
        expect(Zaru.toJson(result), literal, reason: source);
      });
    });

    test('Literal negative zero follows jq canonicalization', () {
      final result = one('.', '-0');
      expect(result, isA<double>());
      expect((result! as double).isNegative, isTrue);
      expect(Zaru.toJson(result), '-0');
      expect(jsonOutputs('. == 0', '-0'), ['true']);
      // The compiled expression -0 folds to a positive zero.
      final folded = Zaru.compile('-0').run(null).single;
      expect(folded, 0);
      expect((folded! as num).isNegative, isFalse);
      expect(Zaru.toJson(folded), '0');
      expect(jsonOutputs('-.', '-0'), ['0']);
      expect(jsonOutputs('-.', '0'), ['0']);
      // Computed negation of zero follows binary64.
      expect(jsonOutputs('(. + 0) | -.', '0'), ['-0']);
    });

    test('Integral native doubles have no source scale', () {
      for (final native in <num>[1, 1.0]) {
        final result = Zaru.compile('.').run(native).single;
        expect(result, isA<num>());
        expect(result, isNot(isA<ZaruNumber>()));
        expect(result, 1);
        expect(Zaru.toJson(result), '1');
      }
      // Both enter as computed numbers, so literal precision never appears.
      expect(nativeOutputs('. == 1.0000000000000001', 1), ['true']);
      expect(nativeOutputs('. == 1.0000000000000001', 1.0), ['true']);
    });

    test('Unsafe native input cannot recover missing digits', () {
      // A JavaScript caller has already rounded 9007199254740993.
      final result = Zaru.compile('.').run(9007199254740992.0).single;
      expect(result, 9007199254740992.0);
      expect(result, isNot(isA<ZaruNumber>()));
      expect(Zaru.toJson(result), '9007199254740992');
      // The original digits are recoverable through runJson or ZaruNumber.
      expect(jsonOutputs('.', '9007199254740993'), ['9007199254740993']);
    });

    test('Ordinary native doubles stay plain', () {
      const values = [0.00001, 1.5e-7, 1e16, 1e23, 1e300];
      const spelling = ['1e-05', '1.5e-07', '1e+16', '1e+23', '1e+300'];
      for (var i = 0; i < values.length; i++) {
        final result = Zaru.compile('.').run(values[i]).single;
        expect(result, isA<num>(), reason: '${values[i]}');
        expect(result, isNot(isA<ZaruNumber>()), reason: '${values[i]}');
        expect(result, values[i]);
        expect(Zaru.toJson(result), spelling[i]);
      }
    });

    test('Native large-double comparison uses fallback', () {
      expect(nativeOutputs('. == 1e23', 1e23), ['true']);
      expect(nativeOutputs('. == 100000000000000000000000', 1e23), ['true']);
    });

    test('Native nonrepresentable integer retains exactness', () {
      if (overlappingNumbers) {
        markTestSkipped('dart2js cannot hold the unrounded integer');
        return;
      }
      final exact = int.parse('9007199254740993');
      final result = Zaru.compile('.').run(exact).single;
      expect(result, isA<ZaruNumber>());
      expect((result! as ZaruNumber).literal, '9007199254740993');
      // It enters with exact literal origin, so it differs from ...992.
      expect(nativeOutputs('. == 9007199254740993', exact), ['true']);
      expect(nativeOutputs('. == 9007199254740992', exact), ['false']);
    });

    test('Native signed zero survives identity', () {
      final result = Zaru.compile('.').run(-0.0).single;
      expect(result, isA<num>());
      expect((result! as num).isNegative, isTrue);
      expect(result, 0);
      expect(Zaru.toJson(result), '-0');
      expect(nativeOutputs('. == 0', -0.0), ['true']);
    });
  });
}
