// String literals, escapes and interpolation through the real compiler.
import 'package:test/test.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

void main() {
  group('string literals', () {
    test('Escaped interpolation marker', () {
      // An escaped backslash followed by parentheses is literal text, not an
      // interpolation opener.
      expect(Zaru.compile(r'"\\(1)"').run(null).single, r'\(1)');
      expect(jsonOutputs(r'"\\(1)"', 'null'), [r'"\\(1)"']);
      expect(jsonOutputs(r'"a\\\(1)"', 'null'), [r'"a\\1"']);
      // The embedded text is never compiled: this would not resolve.
      expect(
        Zaru.compile(r'"\\(nonexistent)"').run(null).single,
        r'\(nonexistent)',
      );
    });

    test('jq escapes and unicode', () {
      expect(Zaru.compile(r'"é😀"').run(null).single, 'é😀');
      expect(Zaru.compile(r'"a\tb\n"').run(null).single, 'a\tb\n');
      expect(jsonOutputs(r'"a\tb\n"', 'null'), [r'"a\tb\n"']);
    });

    test('interpolation converts with tostring and nests', () {
      expect(jsonOutputs(r'"x\(1+2)y"', 'null'), ['"x3y"']);
      expect(jsonOutputs(r'"\(null) \([1,"a"]) \("s")"', 'null'), [
        r'"null [1,\"a\"] s"',
      ]);
      expect(jsonOutputs(r'"a\("b\(1)")c"', 'null'), ['"ab1c"']);
      expect(jsonOutputs(r'"\(.a) and \(.b)"', '{"a":1,"b":[2]}'), [
        '"1 and [2]"',
      ]);
      // A literal keeps its source spelling inside an interpolated value.
      expect(jsonOutputs(r'"\({"a":1.0})"', 'null'), [r'"{\"a\":1.0}"']);
    });

    test('interpolation products vary the last placeholder slowest', () {
      expect(jsonOutputs(r'"\(1,2) and \(3,4)"', 'null'), [
        '"1 and 3"',
        '"2 and 3"',
        '"1 and 4"',
        '"2 and 4"',
      ]);
      expect(jsonOutputs(r'"\(empty)x"', 'null'), isEmpty);
    });
  });
}
