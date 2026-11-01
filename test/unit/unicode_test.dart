// Direct tests of jq's Unicode string boundary: normalization and ordering.
//
// Rows that need indexing, slicing or `run` (astral slices, numeric string
// indexing, slice bounds) belong to group 4; this file covers the private
// string helpers and the printer/decoder boundaries.
import 'package:test/test.dart';
import 'package:zaru/src/json_decoder.dart';
import 'package:zaru/src/json_printer.dart';
import 'package:zaru/src/unicode.dart';
import 'package:zaru/src/value.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

void main() {
  group('ordering', () {
    test('String and sorted-key order', () {
      // Dart's UTF-16 code-unit order puts the astral character first; jq's
      // unsigned UTF-8 order puts U+FFFD first.
      expect('\u{1F600}'.compareTo('�'), lessThan(0));
      expect(compareUtf8Order('�', '\u{1F600}'), lessThan(0));
      expect(compareUtf8Order('\u{1F600}', '�'), greaterThan(0));
      expect(
        Zaru.toJson({'\u{1F600}': 1, '�': 2}, sortKeys: true),
        '{"�":2,"\u{1F600}":1}',
      );
      expect(
        printJson({'\u{1F600}': 1, '�': 2}, sortKeys: true),
        '{"�":2,"\u{1F600}":1}',
      );
    });

    test('code point comparison helper', () {
      int sign(int v) => v.sign;
      final ordered = [
        '',
        'A',
        'AB',
        'B',
        'a',
        'z',
        '\u007f',
        '\u0080',
        'é',
        '߿',
        'ࠀ',
        '퟿',
        '',
        '�',
        '￿',
        '\u{10000}',
        '\u{1F600}',
        '\u{1F601}',
        '\u{10FFFF}',
      ];
      for (var i = 0; i < ordered.length; i++) {
        for (var j = 0; j < ordered.length; j++) {
          expect(
            sign(compareUtf8Order(ordered[i], ordered[j])),
            i.compareTo(j),
            reason:
                '${ordered[i].runes.toList()} vs ${ordered[j].runes.toList()}',
          );
        }
      }
      expect(compareUtf8Order('same', 'same'), 0);
      expect(compareUtf8Order('a\u{1F600}b', 'a\u{1F600}c'), lessThan(0));
    });

    test('keys sort by code point after normalization', () {
      final value = {'b': 1, '': 2, '\u{10000}': 3, 'a': 4};
      expect(
        Zaru.toJson(value, sortKeys: true),
        '{"a":4,"b":1,"":2,"\u{10000}":3}',
      );
    });
  });

  group('lone surrogates', () {
    test('normalizeString replaces only unpaired units', () {
      expect(hasLoneSurrogate('plain'), isFalse);
      expect(hasLoneSurrogate('\u{1F600}'), isFalse);
      expect(hasLoneSurrogate('\uD800'), isTrue);
      expect(hasLoneSurrogate('\uDC00'), isTrue);
      expect(hasLoneSurrogate('x\uD83D'), isTrue);
      expect(hasLoneSurrogate('\uD83Dx'), isTrue);
      expect(normalizeString('plain'), 'plain');
      expect(identical(normalizeString('plain'), 'plain'), isTrue);
      expect(normalizeString('a\uD800b'), 'a�b');
      expect(normalizeString('\uDC00\uD800'), '��');
      expect(normalizeString('😀\uD83D'), '\u{1F600}�');
    });

    test('Native and JSON-text surrogate boundaries', () {
      // A native string with an unpaired high surrogate.
      expect(Zaru.toJson('\uD83D'), '"�"');
      // Raw unescaped lone units in JSON text.
      expect(printJson(decodeJqJson('"\uD83D"')), '"�"');
      expect((decodeJqJson('"\uD83D"') as String), '�');
      // An escaped lone low surrogate.
      expect(decodeJqJson(r'"\ude00"'), '�');
      // An escaped lone high surrogate is a FormatException.
      expect(() => decodeJqJson(r'"\ud83d"'), throwsFormatException);
      expect(() => decodeJqJson(r'"\ud83dA"'), throwsFormatException);
      // A valid escaped pair is one astral character.
      expect(decodeJqJson(r'"😀"'), '\u{1F600}');
      expect((decodeJqJson(r'"😀"') as String).runes.length, 1);
    });

    test('decoded and constructed values never carry lone surrogates', () {
      final value = decodeJqJson('["\uD800",{"\uDC00":"\uD83D"}]') as JqArray;
      expect(value.items[0], '�');
      final object = value.items[1] as JqObject;
      expect(object.entries.keys.single, '�');
      expect(object.entries['�'], '�');
    });
  });

  group('through compiled filters', () {
    test('Astral code point slice', () {
      expect(jsonOutputs('.[1:]', '"😀abc"'), ['"abc"']);
      expect(Zaru.compile('.[1:]').run('😀abc').single, 'abc');
      expect(jsonOutputs('.[:1]', '"😀abc"'), ['"😀"']);
      expect(jsonOutputs('.[0:2]', '"😀abc"'), ['"😀a"']);
      expect(jsonOutputs('.[2:]', '"é€😀x"'), ['"😀x"']);
    });

    test('String and sorted-key order', () {
      expect(jsonOutputs('"\\ufffd" < "😀"', 'null'), ['true']);
      expect(jsonOutputs('"😀" < "\\ufffd"', 'null'), ['false']);
      expect(jsonOutputs('"\\ufffd" == "�"', 'null'), ['true']);
      // Arrays of strings and objects compare by the same order.
      expect(jsonOutputs('["\\ufffd"] < ["😀"]', 'null'), ['true']);
      expect(jsonOutputs('{"\\ufffd":1} < {"😀":1}', 'null'), ['true']);
      final object = Zaru.compile(
        '{"😀": 1, "\\ufffd": 2, "a": 3}',
      ).run(null).single;
      expect(Zaru.toJson(object, sortKeys: true), '{"a":3,"�":2,"😀":1}');
      expect(Zaru.toJson(object), '{"😀":1,"�":2,"a":3}');
    });

    test('Numeric string indexing is an error', () {
      final filter = Zaru.compile('.[1]');
      expect(
        () => filter.runJson('"😀abc"').toList(),
        throwsA(
          isA<ZaruRuntimeError>().having(
            (e) => e.value,
            'value',
            'Cannot index string with number (1)',
          ),
        ),
      );
      expect(Zaru.compile('.[1]?').runJson('"😀abc"').toList(), isEmpty);
      expect(jsonOutputs('.[1:2]', '"😀abc"'), ['"a"']);
    });

    test('Fractional and negative string slice bounds', () {
      expect(jsonOutputs('.[1.5:2.7]', '"😀abc"'), ['"ab"']);
      expect(jsonOutputs('.[-1:]', '"😀abc"'), ['"c"']);
      expect(jsonOutputs('.[:-1]', '"😀abc"'), ['"😀ab"']);
      expect(jsonOutputs('.[-2:-1]', '"😀abc"'), ['"b"']);
      expect(jsonOutputs('.[10:]', '"😀abc"'), ['""']);
      expect(jsonOutputs('.[3:1]', '"😀abc"'), ['""']);
      expect(jsonOutputs('.[-10:2]', '"😀abc"'), ['"😀a"']);
    });

    test('Slice end below zero collapses to the rounded-down start', () {
      // Probed on pinned jq 1.8.2 (parse_slice in src/jv_aux.c).
      expect(
        jsonOutputs(
          '[.[1.7:-4294967296], .[1.2:-20], .[2.5:-9], .[1.5:1.2], '
              '.[-0.5:1e1000], .[3:-1e1000]]',
          '[0,1,2,3,4,5,6,7,8,9]',
        ),
        ['[[],[],[],[1],[9],[]]'],
      );
      expect(jsonOutputs('[.[1.7:-100], .[1.5:-4.5]]', '"abcdef"'), [
        '["","b"]',
      ]);
    });

    test('Native and JSON-text surrogate boundaries', () {
      // A native lone high surrogate normalizes to U+FFFD ...
      expect(Zaru.compile('.').run('a\uD800b').single, 'a�b');
      expect(Zaru.compile('.').run('\uDC00').single, '�');
      // ... and a valid pair is untouched.
      expect(Zaru.compile('.').run('\u{1F600}').single, '\u{1F600}');
      // A raw lone surrogate in JSON text, and an escaped low surrogate,
      // normalize; an escaped lone high surrogate is a format error.
      expect(Zaru.compile('.').runJson('"a\uD800b"').single, 'a�b');
      expect(Zaru.compile('.').runJson(r'"\udc00"').single, '�');
      expect(
        () => Zaru.compile('.').runJson(r'"\ud800"').toList(),
        throwsFormatException,
      );
      // The same normalization applies to keys.
      final map =
          Zaru.compile('.').run({'k\uD800': 1}).single! as Map<String, Object?>;
      expect(map.keys, ['k�']);
    });
  });
}
