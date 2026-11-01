// Direct tests of Zaru.toJson and the private printer.
//
// Rows phrased as `runJson`/identity-filter runs are driven here through the
// private decoder and printer; group 4 re-points them at the public API.
import 'package:test/test.dart';
import 'package:zaru/src/json_decoder.dart';
import 'package:zaru/src/json_printer.dart';
import 'package:zaru/src/number.dart';
import 'package:zaru/src/value.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

/// Builds `[[...[leaf]...]]` with [depth] arrays, iteratively.
Object? nestedLists(int depth, Object? leaf) {
  Object? value = leaf;
  for (var i = 0; i < depth; i++) {
    value = <Object?>[value];
  }
  return value;
}

Object? nestedMaps(int depth, Object? leaf) {
  Object? value = leaf;
  for (var i = 0; i < depth; i++) {
    value = <String, Object?>{'a': value};
  }
  return value;
}

void main() {
  group('numbers', () {
    test('Integer-preserving printing', () {
      expect(Zaru.toJson(1.0), '1');
      expect(Zaru.toJson(1), '1');
      expect(Zaru.toJson(-3.0), '-3');
      expect(Zaru.toJson(100.0), '100');
      expect(Zaru.toJson(1.5), '1.5');
      expect(Zaru.toJson([1.0, 2, 3.25]), '[1,2,3.25]');
      expect(Zaru.toJson(<String, Object?>{'a': 10.0}), '{"a":10}');
      expect(Zaru.toJson(JqNumber.computed(1.0)), '1');
      expect(Zaru.toJson(123456789012345680.0), '123456789012345680');
      expect(Zaru.toJson(0.1 + 0.2), '0.30000000000000004');
    });

    test('Large literal pass-through', () {
      final n = ZaruNumber.parse('12345678909876543212345');
      expect(Zaru.toJson(n), '12345678909876543212345');
      expect(
        Zaru.toJson(<String, Object?>{'id': n}),
        '{"id":12345678909876543212345}',
      );
      expect(
        Zaru.toJson([n, n]),
        '[12345678909876543212345,12345678909876543212345]',
      );
      // The same digits survive the private decoder with no host double.
      expect(
        printJson(decodeJqJson('{"id":12345678909876543212345}')),
        '{"id":12345678909876543212345}',
      );
    });

    test('Preserve literal form but not computed float spelling', () {
      expect(Zaru.toJson(ZaruNumber.parse('1.00')), '1.00');
      expect(Zaru.toJson(1.0), '1');
      expect(Zaru.toJson(ZaruNumber.parse('1E+2')), '1E+2');
      expect(Zaru.toJson(ZaruNumber.parse('100e-2')), '1.00');
      expect(Zaru.toJson(ZaruNumber.parse('-0.0')), '-0.0');
      expect(Zaru.toJson(ZaruNumber.parse('1e1000')), '1E+1000');
      expect(Zaru.toJson(ZaruNumber.parse('0e1000000000')), '0E+999999999');
    });

    test('Lossless input decoding', () {
      const text = '{"id":12345678909876543212345,"a":[1.00,1e2,0.5,-0,1]}';
      expect(
        printJson(decodeJqJson(text)),
        '{"id":12345678909876543212345,"a":[1.00,1E+2,0.5,-0,1]}',
      );
    });

    test('computed number spelling follows jvp_dtoa_fmt', () {
      final expected = <(double, String)>[
        (0.00001, '1e-05'),
        (1.5e-7, '1.5e-07'),
        (1e16, '1e+16'),
        (1e15, '1000000000000000'),
        (1e17, '1e+17'),
        (1e23, '1e+23'),
        (1e300, '1e+300'),
        (5e-324, '5e-324'),
        (1.7976931348623157e308, '1.7976931348623157e+308'),
        (123456789012345680.0, '123456789012345680'),
        (0.30000000000000004, '0.30000000000000004'),
        (100.0, '100'),
        (1.5, '1.5'),
        (-2.5, '-2.5'),
        (1e21, '1e+21'),
        (12345678901234567890.0, '12345678901234567000'),
        (0.0001, '0.0001'),
        (0.00012345, '0.00012345'),
        (1.2345e-5, '1.2345e-05'),
        (123456789012345.6, '123456789012345.6'),
        (1e-7, '1e-07'),
        (4.5e15, '4500000000000000'),
        (1234567890123456.7, '1234567890123456.8'),
        (12345678.9e10, '123456789000000000'),
        (0.1, '0.1'),
        (123456.789e3, '123456789'),
        (1e22, '1e+22'),
        (4.35, '4.35'),
        (0.5, '0.5'),
        (1e-5, '1e-05'),
        (1.0e-4, '0.0001'),
      ];
      for (final (value, text) in expected) {
        expect(formatComputedNumber(value), text, reason: '$value');
        expect(Zaru.toJson(value), text, reason: '$value');
      }
    });

    test('negative zero, nonfinite numbers and clamping', () {
      expect(Zaru.toJson(-0.0), '-0');
      expect(Zaru.toJson(0.0), '0');
      expect(Zaru.toJson(double.nan), 'null');
      expect(Zaru.toJson(double.infinity), '1.7976931348623157e+308');
      expect(Zaru.toJson(double.negativeInfinity), '-1.7976931348623157e+308');
      expect(
        Zaru.toJson([double.nan, double.infinity, double.negativeInfinity]),
        '[null,1.7976931348623157e+308,-1.7976931348623157e+308]',
      );
    });
  });

  group('structure and options', () {
    test('scalars, containers and compact form', () {
      expect(Zaru.toJson(null), 'null');
      expect(Zaru.toJson(true), 'true');
      expect(Zaru.toJson(false), 'false');
      expect(Zaru.toJson('a"b\\c'), r'"a\"b\\c"');
      expect(Zaru.toJson(<Object?>[]), '[]');
      expect(Zaru.toJson(<String, Object?>{}), '{}');
      expect(
        Zaru.toJson({
          'b': [1, null, true],
          'a': {'c': 'x'},
          'e': <Object?>[],
          'f': <String, Object?>{},
        }),
        '{"b":[1,null,true],"a":{"c":"x"},"e":[],"f":{}}',
      );
    });

    test('indented and tab output match jq pretty printing', () {
      final value = {
        'a': [1, 2],
        'b': {'c': null},
        'd': <Object?>[],
        'e': <String, Object?>{},
      };
      expect(
        Zaru.toJson(value, compact: false),
        '{\n'
        '  "a": [\n'
        '    1,\n'
        '    2\n'
        '  ],\n'
        '  "b": {\n'
        '    "c": null\n'
        '  },\n'
        '  "d": [],\n'
        '  "e": {}\n'
        '}',
      );
      expect(
        Zaru.toJson(
          [
            1,
            [2],
          ],
          compact: false,
          indent: '\t',
        ),
        '[\n\t1,\n\t[\n\t\t2\n\t]\n]',
      );
      expect(Zaru.toJson([1], compact: false, indent: ''), '[\n1\n]');
    });

    test('sorted keys use code point order, insertion order otherwise', () {
      final value = {
        'b': 1,
        'a': 2,
        'B': 3,
        'é': 4,
        'z': {'y': 1, 'x': 2},
      };
      expect(Zaru.toJson(value), '{"b":1,"a":2,"B":3,"é":4,"z":{"y":1,"x":2}}');
      expect(
        Zaru.toJson(value, sortKeys: true),
        '{"B":3,"a":2,"b":1,"z":{"x":2,"y":1},"é":4}',
      );
    });

    test('escapes follow jvp_dump_string', () {
      expect(
        Zaru.toJson('\b\t\n\f\r\u0000\u0001\u001f\u007f/ é😀'),
        r'"\b\t\n\f\r\u0000\u0001\u001f\u007f/'
        ' é😀"',
      );
    });

    test('lone surrogates normalize to U+FFFD only where visited', () {
      expect(Zaru.toJson('a\uD800b'), '"a�b"');
      expect(Zaru.toJson('\uDC00'), '"�"');
      expect(Zaru.toJson('😀'), '"\u{1F600}"');
      expect(Zaru.toJson('\uDE00\uD83D'), '"��"');
      expect(Zaru.toJson({'k\uD800': 1}), '{"k�":1}');
      // Keys that normalize to the same text collapse: first position, last value.
      expect(Zaru.toJson({'\uD800': 1, 'x': 2, '�': 3}), '{"�":3,"x":2}');
    });

    test('unsupported data remains an error', () {
      expect(() => Zaru.toJson(Object()), throwsArgumentError);
      expect(() => Zaru.toJson(DateTime(2020)), throwsArgumentError);
      expect(() => Zaru.toJson(#sym), throwsArgumentError);
      expect(() => Zaru.toJson(<Object?>[1, Object()]), throwsArgumentError);
      expect(() => Zaru.toJson(<Object?, Object?>{1: 2}), throwsArgumentError);
      expect(() => Zaru.toJson({'a': BigInt.one}), throwsArgumentError);
      expect(() => Zaru.toJson(() {}), throwsArgumentError);
      expect(() => Zaru.toJson({1, 2}), throwsArgumentError);
    });

    test('private containers print like public ones', () {
      final value = JqObject({
        'a': JqArray([JqNumber.computed(1), 'x', null]),
        'b': JqObject({}),
      });
      expect(printJson(value), '{"a":[1,"x",null],"b":{}}');
      expect(Zaru.toJson(value), '{"a":[1,"x",null],"b":{}}');
    });
  });

  group('depth', () {
    test('Printer depth boundary is jq truncation', () {
      // Root is depth zero; a value deeper than 10000 is replaced.
      final ok = Zaru.toJson(nestedLists(10000, null));
      expect(ok.length, 10000 + 4 + 10000);
      expect(ok.endsWith('null${']' * 10000}'), isTrue);
      expect(ok.startsWith('['), isTrue);
      expect(ok.contains('<skipped'), isFalse);

      final over = Zaru.toJson(nestedLists(10001, null));
      const marker = '<skipped: too deep>';
      expect(over.length, 10001 + marker.length + 10001);
      expect(over.startsWith('${'[' * 10001}$marker'), isTrue);
      expect(over.endsWith(']' * 10001), isTrue);
      expect(over.contains('null'), isFalse);
      // The marker is unquoted: the text is deliberately not valid JSON.
      expect(over.contains('"'), isFalse);
    });

    test('keyed objects and subtree beyond the limit are not visited', () {
      final over = Zaru.toJson(nestedMaps(10001, null));
      expect(over.startsWith('{"a":' * 10001), isTrue);
      expect(over.contains('<skipped: too deep>'), isTrue);
      expect(over.contains('null'), isFalse);

      // Pretty output also truncates at the same place.
      final pretty = Zaru.toJson(
        nestedLists(10001, 7),
        compact: false,
        indent: '',
      );
      expect(pretty.contains('<skipped: too deep>'), isTrue);
      expect(pretty.contains('7'), isFalse);
    });

    test('a subtree below the limit is never normalized or validated', () {
      // The over-depth leaf is not visited, so an unsupported object there is
      // never inspected.
      final deep = nestedLists(10001, Object());
      expect(Zaru.toJson(deep), startsWith('['));
      // A subtree that is visited is validated.
      expect(
        () => Zaru.toJson(nestedLists(10000, Object())),
        throwsArgumentError,
      );
    });
  });

  group('printing computed and literal results', () {
    test('Integer-preserving printing', () {
      // A computed result equal to 1.0 prints as the integer.
      expect(Zaru.toJson(Zaru.compile('1.0 + 0').run(null).single), '1');
      expect(jsonOutputs('1.0 + 0', 'null'), ['1']);
      expect(jsonOutputs('. * 1', '3.0'), ['3']);
      expect(jsonOutputs('.', '3.0'), ['3.0']);
    });

    test('Large literal pass-through', () {
      expect(jsonOutputs('.', '12345678909876543212345'), [
        '12345678909876543212345',
      ]);
      expect(jsonOutputs('12345678909876543212345', 'null'), [
        '12345678909876543212345',
      ]);
      expect(jsonOutputs('[.[]]', '[100000000000000000000000000000001]'), [
        '[100000000000000000000000000000001]',
      ]);
    });

    test('Preserve literal form but not computed float spelling', () {
      expect(jsonOutputs('1.00', 'null'), ['1.00']);
      expect(Zaru.toJson(Zaru.compile('.').run(1.0).single), '1');
      expect(jsonOutputs('., . + 0', '1.00'), ['1.00', '1']);
    });

    test('Lossless input decoding', () {
      expect(jsonOutputs('.', '{"id":12345678909876543212345}'), [
        '{"id":12345678909876543212345}',
      ]);
      expect(jsonOutputs('.id', '{"id":12345678909876543212345}'), [
        '12345678909876543212345',
      ]);
      final result =
          Zaru.compile('.').runJson('{"id":12345678909876543212345}').single!
              as Map<String, Object?>;
      expect(result['id'], isA<ZaruNumber>());
    });
  });
}
