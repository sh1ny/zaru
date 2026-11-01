// String literals, escapes and interpolation through the real compiler.
import 'package:test/test.dart';
import 'package:zaru/zaru.dart';

import 'run_support.dart';

ZaruCompileError _compileError(String source) {
  try {
    Zaru.compile(source);
  } on ZaruCompileError catch (error) {
    return error;
  }
  throw StateError('expected a ZaruCompileError for $source');
}

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

    test('interpolation runs helper generators and nests escapes', () {
      expect(jsonOutputs(r'"\(limit(2; range(5)))-\(first(10, 20))"', 'null'), [
        '"0-10"',
        '"1-10"',
      ]);
      expect(jsonOutputs(r'"a\("b\("c\(1+1)")")"', 'null'), ['"abc2"']);
      expect(jsonOutputs(r'"\("\\(1)")"', 'null'), [r'"\\(1)"']);
      expect(jsonOutputs(r'"\("\(1)")"', 'null'), ['"1"']);
      expect(jsonOutputs(r'"x\([range(3)] | tostring)"', 'null'), [
        '"x[0,1,2]"',
      ]);
      expect(jsonOutputs(r'"é\(1)😀"', 'null'), ['"é1😀"']);
      expect(jsonOutputs(r'"\(select(false))a"', 'null'), isEmpty);
      expect(jsonOutputs(r'"a\(try error("x") catch .)b"', 'null'), ['"axb"']);
      expect(jsonOutputs(r'"\(label $f | 1, break $f)"', 'null'), ['"1"']);
      expect(jsonOutputs(r'"\(.)"', 'null'), ['"null"']);
    });

    test('an interpolated error stops the string, and stays catchable', () {
      expect(
        runtimeErrorValue(Zaru.compile(r'"a\(error("x"))b"').run(null)),
        'x',
      );
      expect(jsonOutputs(r'try "a\(error("x"))b" catch .', 'null'), ['"x"']);
    });

    test('interpolation is the only use of format in M1', () {
      for (final source in [
        r'@text "x\(1)"',
        r'@base64 "x"',
        r'format("text")',
      ]) {
        final error = _compileError(source);
        expect(error.isUnsupported, isTrue, reason: source);
      }
    });
  });
}
