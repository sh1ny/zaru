// Lazy result streams over the core expression set. The helper-based rows of
// this file (limit/range/first/repeat) arrive with the stack-safe helpers.
import 'package:test/test.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

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
  });
}
