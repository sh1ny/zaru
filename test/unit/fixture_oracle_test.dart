// The exact fixture oracle: finite numbers compare as exact decimals,
// separately from the evaluator's jq equality, and nonfinite values are
// compared before any printing could turn them into null or a finite maximum.
//
// This file is browser-safe: no dart:io, no native jq.
import 'package:test/test.dart';
import 'package:zaru/src/json_decoder.dart';
import 'package:zaru/src/number.dart';
import 'package:zaru/src/value.dart';

import '../support/fixture_oracle.dart';

JqNumber lit(String token) => JqNumber.tryParseLiteral(token)!;

JqNumber computed(double v) => JqNumber.computed(v);

void expectMatch(String expected, Object? actual) {
  expect(
    compareExpected(expected, actual),
    OracleVerdict.match,
    reason: 'expected $expected',
  );
}

void expectMismatch(String expected, Object? actual) {
  expect(
    compareExpected(expected, actual),
    OracleVerdict.mismatch,
    reason: 'expected $expected',
  );
}

Object? decode(String json) => decodeJqJson(json);

Object? nestedLists(int depth, Object? leaf) {
  Object? value = leaf;
  for (var i = 0; i < depth; i++) {
    value = <Object?>[value];
  }
  return value;
}

void main() {
  group('finite numbers', () {
    test('Equivalent numeric spelling', () {
      expectMatch('2.0', computed(2));
      expectMatch('2', computed(2));
      expectMatch('2', lit('2.00'));
      expectMatch('1.00', lit('1.0'));
      expectMatch('1E+2', lit('100'));
      expectMatch('100e-2', lit('1'));
      expectMatch('0', lit('-0'));
      expectMatch('-0', computed(0));
      expectMatch('0.0', computed(-0.0));
      expectMatch('[1,2.5]', decode('[1.0,2.50]'));
      expectMatch('10', ZaruNumber.parse('1e1'));
      expectMatch('10', 10);
      expectMatch('0.5', 0.5);
    });

    test('Rounded large integer is different', () {
      expectMismatch('12345678909876543212345', lit('12345678909876543000000'));
      expectMatch('12345678909876543212345', lit('12345678909876543212345'));
      expectMatch(
        '12345678909876543212345',
        ZaruNumber.parse('12345678909876543212345'),
      );
      // A computed double is judged by its shortest round-trip decimal.
      expectMismatch(
        '12345678909876543212345',
        computed(1.2345678909876543e22),
      );
      expectMismatch('13911860366432393', computed(13911860366432392));
      expectMatch('13911860366432392', computed(13911860366432392));
      expectMismatch('9007199254740993', computed(9007199254740992));
    });

    test('computed doubles use the shortest round-trip decimal', () {
      expectMatch('0.1', computed(0.1));
      expectMatch('0.30000000000000004', computed(0.1 + 0.2));
      expectMismatch('0.3', computed(0.1 + 0.2));
      expectMatch('1e23', computed(1e23));
      expectMatch('100000000000000000000000', computed(1e23));
      // The binary expansion of the double is not what jq prints.
      expectMismatch('99999999999999991611392', computed(1e23));
      expectMatch('5e-324', computed(5e-324));
      expectMismatch('4.9406564584124654e-324', computed(5e-324));
      expectMatch('1.7976931348623157e308', computed(1.7976931348623157e308));
      expectMatch('1e300', computed(1e300));
      expectMatch('123456789012345680', computed(123456789012345680.0));
      expectMismatch('123456789012345678', computed(123456789012345680.0));
      expectMatch('-2.5', -2.5);
      expectMatch('[1e-7]', [1e-7]);
    });

    test('it is not the evaluator comparison', () {
      final number = computed(42);
      final literal = lit('42.0000000000000001');
      // jq's runtime equality falls back to doubles for mixed origins...
      expect(JqNumber.compare(number, literal), 0);
      // ...but the oracle sees two different numbers.
      expectMismatch('42.0000000000000001', number);
      expectMismatch('42', literal);
      expectMatch('42.0000000000000001', literal);
    });

    test('huge exponents compare without expanding them', () {
      expectMatch('1e999999999', lit('10e999999998'));
      expectMatch('9E+999999999', lit('9e999999999'));
      expectMismatch('9E+999999999', lit('8e999999999'));
      expectMatch('1e-1000000000', lit('0.1e-999999999'));
      expectMismatch('1e-1000000000', lit('1e-999999999'));
      expectMatch('0e1000000000', computed(0));
      expectMatch('1e1000', ZaruNumber.parse('1E+1000'));
      expectMismatch('1e1000', lit('1e1001'));
      expectMismatch('1e1000', computed(double.infinity));
      expectMismatch('1e1000', computed(1.7976931348623157e308));
      expectMismatch('1e-1000', computed(0));
      expectMatch('1e-1000', lit('1e-1000'));
    });
  });

  group('nonfinite numbers', () {
    test('Nonfinite values cannot match printed substitutes', () {
      // NaN would print as null; infinity would clamp to the finite maximum.
      expectMismatch('null', computed(double.nan));
      expectMismatch('1.7976931348623157e+308', computed(double.infinity));
      expectMismatch(
        '-1.7976931348623157e+308',
        computed(double.negativeInfinity),
      );
      expectMismatch('[null]', [double.nan]);
      expectMismatch('[1.7976931348623157e308]', [double.infinity]);
      expectMismatch('{"a":null}', {'a': double.nan});
      expectMismatch('1.7976931348623157e+308', lit('Infinity'));
      expectMismatch('null', lit('NaN'));
      expectMismatch('null', JqNumber.fromNative(double.nan));
      // The reverse direction is equally strict.
      expectMismatch('NaN', 0);
      expectMismatch('Infinity', computed(1.7976931348623157e308));
      expectMismatch('null', 0);
    });

    test('infinities match only identical infinities', () {
      expectMatch('Infinity', computed(double.infinity));
      expectMatch('-Infinity', computed(double.negativeInfinity));
      expectMatch('1e1000000000', computed(double.infinity));
      expectMatch('-1e1000000000', double.negativeInfinity);
      expectMatch('Infinity', lit('1e1000000000'));
      expectMismatch('Infinity', computed(double.negativeInfinity));
      expectMismatch('-Infinity', computed(double.infinity));
      expectMatch('[Infinity,-Infinity]', decode('[Infinity,-Infinity]'));
    });

    test('NaN follows jv_equal: it never equals anything', () {
      expectMismatch('NaN', computed(double.nan));
      expectMismatch('[nan]', [double.nan]);
      expectMismatch('NaN', lit('NaN'));
    });
  });

  group('structure and text', () {
    test('Text is not numeric normalization', () {
      expectMismatch('"1.00"', '1');
      expectMatch('"1.00"', '1.00');
      expectMismatch('"1"', '1.00');
      expectMismatch('1', '1');
      expectMismatch('"1"', 1);
      expectMatch('"1E+1000"', '1E+1000');
      expectMismatch('"1E+1000"', '1e+1000');
      expectMatch('"é"', 'é');
      expectMatch(r'"é"', 'é');
      expectMismatch('"a"', 'b');
      expectMatch(r'"😀"', '😀');
      // Lone surrogates normalize on both sides before comparison.
      expectMatch('"\uD800"', '�');
    });

    test('Duplicate outputs are significant at the value level', () {
      expectMismatch('[1,1]', [1]);
      expectMatch('[1,1]', [1, 1]);
      expectMismatch('[1]', [1, 1]);
      expectMismatch('[1,2]', [2, 1]);
      expectMatch('[]', <Object?>[]);
      expectMismatch('[]', <Object?>[null]);
    });

    test('objects ignore key order but not key sets', () {
      expectMatch('{"a":1,"b":[true,null]}', {
        'b': [true, null],
        'a': 1,
      });
      expectMatch('{"a":1,"b":2}', decode('{"b":2,"a":1}'));
      expectMismatch('{"a":1}', {'a': 1, 'b': 2});
      expectMismatch('{"a":1,"b":2}', {'a': 1});
      expectMismatch('{"a":1}', {'b': 1});
      expectMismatch('{"a":1}', {'a': 2});
      expectMatch('{}', <String, Object?>{});
    });

    test('kinds never cross', () {
      expectMismatch('null', false);
      expectMismatch('false', null);
      expectMismatch('true', 1);
      expectMismatch('[]', <String, Object?>{});
      expectMismatch('{}', <Object?>[]);
      expectMismatch('0', false);
      expectMismatch('""', null);
      expectMatch('null', null);
      expectMatch('true', true);
      expectMatch('false', false);
    });

    test('public and private value domains compare alike', () {
      const expected = '{"a":[1.00,"x",null],"b":12345678909876543212345}';
      expectMatch(expected, decode(expected));
      expectMatch(expected, {
        'a': [ZaruNumber.parse('1.00'), 'x', null],
        'b': ZaruNumber.parse('12345678909876543212345'),
      });
      expectMatch(
        expected,
        JqObject({
          'a': JqArray([lit('1.0'), 'x', null]),
          'b': lit('12345678909876543212345'),
        }),
      );
      expectMismatch(expected, {
        'a': [1, 'x', null],
        'b': 12345678909876543212345.0,
      });
    });

    test('unsupported actual values and map keys never match', () {
      expectMismatch('null', Object());
      expectMismatch('[1]', [Object()]);
      expectMismatch('{"1":1}', <Object?, Object?>{1: 1});
      expectMismatch('"x"', #x);
    });

    test('comparison is iterative', () {
      final text = '${'[' * 10000}0${']' * 10000}';
      expectMatch(text, nestedLists(10000, 0));
      expectMatch(text, decode(text));
      expectMismatch(text, nestedLists(10000, 1));
      expectMismatch(text, nestedLists(9999, 0));
      // The actual side is not subject to the parser's depth budget.
      expectMismatch(text, nestedLists(12000, 0));
      expect(
        compareExpected(
          '${'[' * 10001}${']' * 10001}',
          nestedLists(10001, null),
        ),
        OracleVerdict.malformedExpectation,
      );
    });
  });

  group('malformed expectations', () {
    test('are reported, never matched or treated as a mismatch', () {
      const malformed = [
        '',
        '  ',
        '[1,',
        '{"a":}',
        'nul',
        '1 2',
        '[1,]',
        '0x10',
        'NaN1',
        r'"\ud800"',
        "{'a':1}",
        '"unterminated',
      ];
      for (final text in malformed) {
        expect(
          compareExpected(text, null),
          OracleVerdict.malformedExpectation,
          reason: text,
        );
        expect(
          () => parseExpectation(text),
          throwsFormatException,
          reason: text,
        );
      }
      expect(compareExpected('null', null), OracleVerdict.match);
    });

    test('use jq grammar: extensions are valid expectations', () {
      expectMatch('+1', 1);
      expectMatch('.5', 0.5);
      expectMatch('01', 1);
      expectMatch('1.', 1);
      expectMatch('﻿[1]', [1]);
    });
  });

  group('direct oracle', () {
    test('oracleEquals compares already parsed values', () {
      expect(oracleEquals(decode('[1.0]'), [1]), isTrue);
      expect(oracleEquals(decode('[1.0]'), [1.5]), isFalse);
      expect(oracleEquals(null, null), isTrue);
    });
  });
}
