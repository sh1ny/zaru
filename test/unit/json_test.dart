// Direct tests of the private jq-compatible JSON decoder.
//
// Rows phrased as `runJson` runs drive `decodeJqJson` directly. Laziness, the
// terminal iterator and the filter-evaluated rows belong to group 4.
import 'package:test/test.dart';
import 'package:zaru/src/json_decoder.dart';
import 'package:zaru/src/json_printer.dart';
import 'package:zaru/src/number.dart';
import 'package:zaru/src/value.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

Matcher formatError({String? contains, int? offset, String? source}) {
  var matcher = isA<FormatException>();
  if (contains != null) {
    matcher = matcher.having(
      (e) => e.message,
      'message',
      stringContainsInOrder([contains]),
    );
  }
  if (offset != null) {
    matcher = matcher.having((e) => e.offset, 'offset', offset);
  }
  if (source != null) {
    matcher = matcher.having((e) => e.source, 'source', source);
  }
  return matcher;
}

String roundTrip(String json) => printJson(decodeJqJson(json));

/// Exports a decoded scalar to its public form.
Object? scalar(Object? v) => v is JqNumber ? v.export() : v;

/// Counts nesting of arrays of arrays, iteratively.
int arrayDepth(Object? value) {
  var depth = 0;
  var current = value;
  while (current is JqArray) {
    depth++;
    if (current.length != 1) break;
    current = current.items[0];
  }
  return depth;
}

int objectDepth(Object? value) {
  var depth = 0;
  var current = value;
  while (current is JqObject) {
    depth++;
    if (current.length != 1) break;
    current = current.entries['a'];
  }
  return depth;
}

void main() {
  group('values', () {
    test('Numeric input grammar is jq grammar', () {
      expect(roundTrip('+1'), '1');
      expect(roundTrip('01'), '1');
      expect(roundTrip('.5'), '0.5');
      expect(roundTrip('1.'), '1');
      expect(scalar(decodeJqJson('+1')), 1);
      expect(scalar(decodeJqJson('01')), 1);
      expect(scalar(decodeJqJson('.5')), 0.5);
      expect(scalar(decodeJqJson('1.')), 1);
      expect(
        roundTrip('[+1,01,.5,1.,-.5,1.e2,5.E3,00.0]'),
        '[1,1,0.5,1,-0.5,1E+2,5E+3,0.0]',
      );
      expect(roundTrip(' \t\r\n[1 , 2]\n'), '[1,2]');
      expect(roundTrip('[true,false,null,"s"]'), '[true,false,null,"s"]');
    });

    test('BOM and nonfinite inputs', () {
      final value = decodeJqJson('﻿[NaN,Infinity,-Infinity,-NaN]');
      final items = (value as JqArray).items
          .map((e) => scalar(e)! as num)
          .toList();
      expect(items[0].isNaN, isTrue);
      expect(items[1], double.infinity);
      expect(items[2], double.negativeInfinity);
      expect(items[3].isNaN, isTrue);
      expect(
        printJson(value),
        '[null,1.7976931348623157e+308,-1.7976931348623157e+308,null]',
      );
      expect(
        Zaru.toJson(items),
        '[null,1.7976931348623157e+308,-1.7976931348623157e+308,null]',
      );
      // Accepted spellings and the infinity from decimal overflow.
      expect(
        roundTrip(
          '[nan,NAN,Nan,inf,INFINITY,+Infinity,1e1000000000,-1e1000000000]',
        ),
        '[null,null,null,1.7976931348623157e+308,1.7976931348623157e+308,'
        '1.7976931348623157e+308,1.7976931348623157e+308,-1.7976931348623157e+308]',
      );
      // Only a leading BOM is skipped; a second one is not whitespace.
      expect(roundTrip('﻿ 7'), '7');
      expect(
        () => decodeJqJson('﻿﻿7'),
        throwsA(formatError(contains: 'Invalid numeric literal')),
      );
      expect(
        () => decodeJqJson('﻿'),
        throwsA(formatError(contains: 'Expected JSON value')),
      );
    });

    test('Invalid JSON and escaped surrogate errors remain errors', () {
      const cases = {
        '1 2': 'Unexpected extra JSON values',
        '[1,2] [3]': 'Unexpected extra JSON values',
        '[1,2]x': 'Invalid numeric literal at EOF at line 1, column 6',
        '[1,2]]': "Unmatched ']' at line 1, column 6",
        '0x10': 'Invalid numeric literal at EOF at line 1, column 4',
        '[0x10]': 'Invalid numeric literal at line 1, column 6',
        '1e': 'Invalid numeric literal at EOF at line 1, column 2',
        '[1.2.3]': 'Invalid numeric literal at line 1, column 7',
        'NaN1': 'Invalid numeric literal at EOF at line 1, column 4',
        r'"\ud800"':
            r'Invalid \uXXXX\uXXXX surrogate pair escape at line 1, column 8',
        r'"\ud800A"':
            r'Invalid \uXXXX\uXXXX surrogate pair escape at line 1, column 9',
        r'"\ud800x"':
            r'Invalid \uXXXX\uXXXX surrogate pair escape at line 1, column 9',
        r'"\u12"': r'Invalid \uXXXX escape at line 1, column 6',
        r'"\u12zz"': r'Invalid characters in \uXXXX escape at line 1, column 8',
        r'"\x"': 'Invalid escape at line 1, column 4',
        '"a\nb"':
            'Invalid string: control characters from U+0000 through U+001F must be escaped at line 2, column 2',
        '[1,]': 'Expected another array element at line 1, column 4',
        '{"a":1,}': 'Expected another key-value pair at line 1, column 8',
        '[1 2]': 'Expected separator between values at line 1, column 5',
        '{"a" 1}': 'Expected separator between values at line 1, column 7',
        '{1:2}': 'Object keys must be strings at line 1, column 3',
        '[:]': "Expected string key before ':' at line 1, column 2",
        '{"a":}': "Unmatched '}' at line 1, column 6",
        '}': "Unmatched '}' at line 1, column 1",
        ']': "Unmatched ']' at line 1, column 1",
        ',': "Expected value before ',' at line 1, column 1",
        '[1,,2]': "Expected value before ',' at line 1, column 4",
        '{"a"}': 'Objects must consist of key:value pairs at line 1, column 5',
        '[}': "Unmatched '}' at line 1, column 2",
        '{]': "Unmatched ']' at line 1, column 2",
        '[nul]': 'Invalid literal at line 1, column 5',
        '[tru]': 'Invalid literal at line 1, column 5',
        "['a']":
            "Invalid string literal; expected \", but got ' at line 1, column 5",
        '"abc': 'Unfinished string at EOF at line 1, column 4',
        '[1': 'Unfinished JSON term at EOF at line 1, column 2',
        '[1,': 'Unfinished JSON term at EOF at line 1, column 3',
        '{"a":1': 'Unfinished JSON term at EOF at line 1, column 6',
        '': 'Expected JSON value',
        '  \n ': 'Expected JSON value',
        '1]': "Unmatched ']' at line 1, column 2",
      };
      cases.forEach((input, message) {
        expect(
          () => decodeJqJson(input),
          throwsA(formatError(contains: message, source: input)),
          reason: 'decode(${input.replaceAll("\n", r"\n")})',
        );
      });
      // A lone low-surrogate escape normalizes instead of failing.
      expect(roundTrip(r'"\udc00"'), '"�"');
    });

    test(
      'error offsets are zero-based UTF-16 indexes of the failing character',
      () {
        expect(() => decodeJqJson('[1,2]]'), throwsA(formatError(offset: 5)));
        expect(() => decodeJqJson('[1 2]'), throwsA(formatError(offset: 4)));
        expect(() => decodeJqJson('"abc'), throwsA(formatError(offset: 4)));
        expect(() => decodeJqJson(''), throwsA(formatError(offset: 0)));
        expect(() => decodeJqJson('  '), throwsA(formatError(offset: 2)));
        // The BOM counts toward the offset but not the column.
        expect(
          () => decodeJqJson('﻿[}'),
          throwsA(formatError(offset: 2, contains: 'line 1, column 2')),
        );
        // Columns count UTF-8 bytes, offsets count UTF-16 units: é is two bytes,
        // an astral character four bytes and two units.
        expect(
          () => decodeJqJson('["é😀",]'),
          throwsA(formatError(offset: 7, contains: 'line 1, column 11')),
        );
        expect(
          () => decodeJqJson('[\n"x",\n]'),
          throwsA(formatError(offset: 7, contains: 'line 3, column 1')),
        );
      },
    );

    test('strings: escapes, raw surrogates and U+FFFD normalization', () {
      expect(scalar(decodeJqJson(r'"a\/\b\f\n\r\t\"\\"')), 'a/\b\f\n\r\t"\\');
      expect(scalar(decodeJqJson(r'"éA"')), 'éA');
      expect(scalar(decodeJqJson(r'"😀"')), '😀');
      expect(scalar(decodeJqJson(r'"😀"')), '😀');
      expect(scalar(decodeJqJson(r'"\u0000"')), '\u0000');
      // Raw unescaped lone UTF-16 units become U+FFFD like invalid UTF-8.
      expect(scalar(decodeJqJson('"a\uD800b"')), 'a�b');
      expect(scalar(decodeJqJson('"\uDC00"')), '�');
      expect(scalar(decodeJqJson('"😀"')), '😀');
      expect(scalar(decodeJqJson('"\uD83D\\udc00"')), '��');
      // Escaped lone low surrogates normalize, one replacement each.
      expect(scalar(decodeJqJson(r'"\udc00\udc00x"')), '��x');
      expect(scalar(decodeJqJson(r'"\udfff"')), '�');
      // Object keys follow the same rules; a repeated key keeps its first
      // position and takes the last value.
      expect(roundTrip(r'{"\udc00":1,"x":2,"�":3}'), '{"�":3,"x":2}');
      expect(roundTrip('{"b":1,"a":2,"b":3}'), '{"b":3,"a":2}');
    });

    test('literals keep canonical numbers; control and quirk characters', () {
      expect(roundTrip('[0.00,1E5,100e-2,-0,0e5]'), '[0.00,1E+5,1.00,-0,0E+5]');
      // jq reads the numeric token through a C string: a NUL ends it.
      expect(scalar(decodeJqJson('1\u0000 ')), 1);
      expect(() => decodeJqJson('\u00001'), throwsA(isA<FormatException>()));
      // DEL is escaped like a control character; U+0080 is printed as is.
      expect(roundTrip('"\u007f\u0080"'), '"\\u007f\u0080"');
    });
  });

  group('depth', () {
    test('Array parsing depth boundary', () {
      String text(int depth) => '${'[' * depth}${']' * depth}';
      final ok = decodeJqJson(text(10000));
      expect(arrayDepth(ok), 10000);
      expect(printJson(ok), text(10000));

      final deepText = text(10001);
      expect(
        () => decodeJqJson(deepText),
        throwsA(
          formatError(
            source: deepText,
            offset: 10000,
            contains: 'Exceeds depth limit for parsing at line 1, column 10001',
          ),
        ),
      );
      // A scalar leaf does not change the boundary.
      final leaf = '${'[' * 10000}0${']' * 10000}';
      expect(arrayDepth(decodeJqJson(leaf)), 10000);
      expect(printJson(decodeJqJson(leaf)), leaf);
    });

    test('Object keys consume parser stack slots', () {
      String text(int depth) => '${'{"a":' * depth}0${'}' * depth}';
      final ok = decodeJqJson(text(5000));
      expect(objectDepth(ok), 5000);
      expect(printJson(ok), text(5000));
      final bad = text(5001);
      expect(
        () => decodeJqJson(bad),
        throwsA(
          formatError(
            source: bad,
            contains: 'Exceeds depth limit for parsing',
            offset: 5000 * 5,
          ),
        ),
      );
      // Mixed nesting: each object costs two slots (itself and its pending
      // key), each array one; only a container opening is checked.
      String arraysThenObjects(int arrays, int objects) =>
          '${'[' * arrays}${'{"a":' * objects}0${'}' * objects}${']' * arrays}';
      // 9998 slots before the second object opens: accepted.
      final fits = arraysThenObjects(9998, 1);
      expect(printJson(decodeJqJson(fits)), fits);
      final fitsDeepKeys = arraysThenObjects(9997, 2); // opens at 9997, 9999
      expect(printJson(decodeJqJson(fitsDeepKeys)), fitsDeepKeys);
      // 9998 arrays + object + pending key = 10000 slots; the next opening fails.
      final over = arraysThenObjects(9998, 2);
      expect(
        () => decodeJqJson(over),
        throwsA(formatError(contains: 'Exceeds depth limit', offset: 9998 + 5)),
      );
      expect(
        () => decodeJqJson('${'[' * 10000}{}'),
        throwsA(formatError(contains: 'column 10001', offset: 10000)),
      );
      expect(
        printJson(decodeJqJson('${'[' * 9999}{}${']' * 9999}')),
        '${'[' * 9999}{}${']' * 9999}',
      );
    });

    test(
      'very deep valid input and sizeable arrays decode without recursion',
      () {
        final wide = '[${List.filled(50000, '1').join(',')}]';
        expect((decodeJqJson(wide) as JqArray).length, 50000);
        final big = decodeJqJson('[${'"x",' * 1000}"y"]');
        expect((big as JqArray).length, 1001);
      },
    );
  });

  group('runJson through compiled filters', () {
    test('Literal origin survives before public narrowing', () {
      final filter = Zaru.compile('. == 42.0000000000000001');
      // JSON text: literal 42 against literal 42.0000000000000001 is decimal.
      expect(filter.runJson('42').toList(), [false]);
      // Native 42 is computed, so the comparison falls back to doubles.
      expect(filter.run(42).toList(), [true]);
      // An ordinary public 42 results either way; no wrapper is boxed for it.
      expect(Zaru.compile('.').runJson('42').single, 42);
    });

    test('JSON text errors are lazy and terminal', () {
      final filter = Zaru.compile('.');
      // Creating the iterable and the iterator succeeds for malformed text.
      final iterable = filter.runJson('{"a":');
      final iterator = iterable.iterator;
      expect(
        () => iterator.moveNext(),
        throwsA(
          isA<FormatException>()
              .having((e) => e.source, 'source', '{"a":')
              .having((e) => e.offset, 'offset', isNotNull),
        ),
      );
      expect(iterator.moveNext(), isFalse);
      expect(iterator.moveNext(), isFalse);
      // A later iteration of the same iterable fails again, independently.
      expect(() => iterable.toList(), throwsFormatException);
      // The error precedes any evaluation, including a missing argument.
      final needs = Zaru.compile(r'$x', variables: {'x'});
      expect(
        () => needs.runJson('{').iterator.moveNext(),
        throwsA(anyOf(isA<FormatException>(), isA<ZaruMissingArgumentError>())),
      );
    });

    test('Empty JSON text is not an input stream', () {
      for (final text in ['', '   ', '\n\t ']) {
        final iterator = Zaru.compile('.').runJson(text).iterator;
        expect(
          () => iterator.moveNext(),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Expected JSON value'),
            ),
          ),
          reason: 'text ${text.codeUnits}',
        );
        expect(iterator.moveNext(), isFalse);
      }
    });

    test('BOM and nonfinite inputs', () {
      final results =
          Zaru.compile('.').runJson('﻿[NaN,Infinity,-Infinity,-NaN]').single!
              as List<Object?>;
      expect((results[0]! as double).isNaN, isTrue);
      expect(results[1], double.infinity);
      expect(results[2], double.negativeInfinity);
      expect((results[3]! as double).isNaN, isTrue);
      expect(
        Zaru.toJson(results),
        '[null,1.7976931348623157e+308,'
        '-1.7976931348623157e+308,null]',
      );
    });

    test('Numeric input grammar is jq grammar', () {
      expect(
        [
          for (final t in ['+1', '01', '.5', '1.']) jsonOutputs('.', t).single,
        ],
        ['1', '1', '0.5', '1'],
      );
    });

    test('Invalid JSON and escaped surrogate errors remain errors', () {
      for (final text in ['1 2', '[1,]', '1x', r'"\ud800"', '{"a" 1}']) {
        final iterator = Zaru.compile('.').runJson(text).iterator;
        expect(
          () => iterator.moveNext(),
          throwsA(isA<FormatException>()),
          reason: text,
        );
        expect(iterator.moveNext(), isFalse, reason: text);
      }
      // A lone low surrogate escape normalizes instead.
      expect(Zaru.compile('.').runJson(r'"\udc00"').single, '�');
    });

    test('Array parsing depth boundary', () {
      final ok = '${'[' * 10000}0${']' * 10000}';
      final result = Zaru.compile('.').runJson(ok).single;
      expect(Zaru.toJson(result), ok);
      final bad = '${'[' * 10001}0${']' * 10001}';
      final iterator = Zaru.compile('.').runJson(bad).iterator;
      expect(
        () => iterator.moveNext(),
        throwsA(
          isA<FormatException>()
              .having((e) => e.source, 'source', bad)
              .having((e) => e.offset, 'offset', 10000)
              .having(
                (e) => e.message,
                'message',
                contains(
                  'Exceeds depth limit for parsing at line 1, column 10001',
                ),
              ),
        ),
      );
      expect(iterator.moveNext(), isFalse);
    });

    test('Object keys consume parser stack slots', () {
      String nested(int depth) => '${'{"a":' * depth}0${'}' * depth}';
      final ok = Zaru.compile('.').runJson(nested(5000)).single;
      expect(Zaru.toJson(ok), nested(5000));
      expect(
        () => Zaru.compile('.').runJson(nested(5001)).toList(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Exceeds depth limit for parsing'),
          ),
        ),
      );
    });
  });
}
