// try/catch, `?` and uncaught runtime errors over the core runtime.
import 'package:test/test.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

void main() {
  group('runtime errors', () {
    test('Catch after an earlier result', () {
      expect(jsonOutputs('try (1, error("bad")) catch .', 'null'), [
        '1',
        '"bad"',
      ]);
    });

    test('Error without catch', () {
      final iterator = Zaru.compile('(1, error("bad"))').run(null).iterator;
      expect(iterator.moveNext(), isTrue);
      expect(iterator.current, 1);
      expect(
        () => iterator.moveNext(),
        throwsA(isA<ZaruRuntimeError>().having((e) => e.value, 'value', 'bad')),
      );
    });

    test('Failed iterator is terminal', () {
      final iterator = Zaru.compile('(1, error("bad"), 3)').run(null).iterator;
      expect(iterator.moveNext(), isTrue);
      expect(() => iterator.moveNext(), throwsA(isA<ZaruRuntimeError>()));
      // No replay of values, work or the exception.
      expect(iterator.moveNext(), isFalse);
      expect(iterator.moveNext(), isFalse);
      // A fresh iterator over the same filter starts over.
      final again = Zaru.compile('(1, error("bad"), 3)').run(null).iterator;
      expect(again.moveNext(), isTrue);
      expect(again.current, 1);
    });

    test('error carries any value, including null', () {
      expect(jsonOutputs('try error(null) catch .', 'null'), ['null']);
      expect(jsonOutputs('try error({a: 1}) catch .', 'null'), ['{"a":1}']);
      expect(jsonOutputs('try error catch .', '"in"'), ['"in"']);
      expect(jsonOutputs('.[] | try error catch .', '[1,"a",null]'), [
        '1',
        '"a"',
        'null',
      ]);
      expect(jsonOutputs(r'try error("\(1)") catch .', 'null'), ['"1"']);
      final iterator = Zaru.compile('error(null)').run(null).iterator;
      expect(
        () => iterator.moveNext(),
        throwsA(
          isA<ZaruRuntimeError>()
              .having((e) => e.value, 'value', isNull)
              .having((e) => e.message, 'message', 'null (not a string)'),
        ),
      );
      // error(f) raises each output of f against the input.
      expect(jsonOutputs('try error(.a, .b) catch .', '{"a":1,"b":2}'), ['1']);
      expect(jsonOutputs('[.[] | try error(.) catch .]', '[1,2]'), ['[1,2]']);
    });

    test('try without catch and the postfix ? suppress and stop', () {
      expect(jsonOutputs('[try error("x")]', 'null'), ['[]']);
      expect(jsonOutputs('[(1, error("x"), 3)?]', 'null'), ['[1]']);
      expect(jsonOutputs('[try error(null)]', 'null'), ['[]']);
      // A caught error abandons the rest of the body.
      expect(jsonOutputs('try ((1, 2) | error) catch .', 'null'), ['1']);
      expect(jsonOutputs('[.[] | (try error("x" + .) catch .)]', '["a","b"]'), [
        '["xa","xb"]',
      ]);
    });

    test('try catches its body, not the rest of the pipeline', () {
      final iterator = Zaru.compile(
        'try (1, 2) catch "c" | error("down")',
      ).run(null).iterator;
      expect(
        () => iterator.moveNext(),
        throwsA(isA<ZaruRuntimeError>().having((e) => e.value, 'v', 'down')),
      );
      expect(
        jsonOutputs(
          'try ((try (1, 2) catch "inner") | error("down")) catch .',
          'null',
        ),
        ['"down"'],
      );
      // Errors from the handler itself are not caught by the same try.
      final handler = Zaru.compile('try error("a") catch error("b")');
      expect(
        () => handler.run(null).toList(),
        throwsA(isA<ZaruRuntimeError>().having((e) => e.value, 'v', 'b')),
      );
      expect(
        jsonOutputs(
          'try (try error("a") catch error("b")) catch ("outer " + .)',
          'null',
        ),
        ['"outer b"'],
      );
    });

    test('catch handlers can be generators', () {
      expect(jsonOutputs('try error("x") catch (., "y")', 'null'), [
        '"x"',
        '"y"',
      ]);
      expect(jsonOutputs('[(1, 2) | try error("x") catch .]', 'null'), [
        '["x","x"]',
      ]);
    });

    test('errors inside a collected array end the array', () {
      expect(
        () => Zaru.compile('[1, error("x")]').run(null).toList(),
        throwsA(isA<ZaruRuntimeError>()),
      );
      expect(jsonOutputs('try [1, error("x")] catch .', 'null'), ['"x"']);
    });
  });
}
