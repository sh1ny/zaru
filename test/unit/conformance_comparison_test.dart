// Decision tests for the conformance comparison: each case runs the real
// compiler and engine on a real fixture and judges it with the fixture oracle.
//
// Browser-safe: no dart:io, no native jq.
import 'package:test/test.dart';

import '../support/conformance_run.dart';
import 'conformance_support.dart';

void expectPassed(CaseVerdict verdict) {
  expect(verdict.status, CaseStatus.passed, reason: '${verdict.detail}');
}

void expectFailed(CaseVerdict verdict, String reason) {
  expect(verdict.status, CaseStatus.failed, reason: '${verdict.detail}');
  expect(verdict.reason, reason);
}

void main() {
  group('output streams', () {
    test('Duplicate outputs are significant', () {
      expectFailed(runOne('.[]\n[1]\n1\n1\n'), 'missingExpectedOutput');
      expectPassed(runOne('.[]\n[1,1]\n1\n1\n'));
      expectFailed(runOne('.[]\n[1,1,1]\n1\n1\n'), 'surplusOutput');
    });

    test('Rounded large integer is different', () {
      expectFailed(
        runOne('.\n12345678909876543000000\n12345678909876543212345\n'),
        'outputMismatch',
      );
      // The same digits are lossless through the whole pipeline.
      expectPassed(
        runOne('.\n12345678909876543212345\n12345678909876543212345\n'),
      );
    });

    test('Equivalent numeric spelling', () {
      expectPassed(runOne('.\n2\n2.0\n'));
      expectPassed(runOne('.\n2.0\n2\n'));
      expectPassed(runOne('.\n1.000\n1\n'));
    });

    test('Text is not numeric normalization', () {
      expectFailed(runOne('tostring\n1\n"1.00"\n'), 'outputMismatch');
      expectPassed(runOne('tostring\n1.00\n"1.00"\n'));
    });

    test('Nonfinite values cannot match printed substitutes', () {
      expectFailed(runOne('.\nNaN\nnull\n'), 'outputMismatch');
      expectFailed(
        runOne('.\nInfinity\n1.7976931348623157e+308\n'),
        'outputMismatch',
      );
      expectFailed(
        runOne('.\n-Infinity\n-1.7976931348623157e+308\n'),
        'outputMismatch',
      );
      // An infinity matches only an infinity, never NaN or null.
      expectPassed(runOne('.\nInfinity\nInfinity\n'));
      expectFailed(runOne('.\nInfinity\nNaN\n'), 'outputMismatch');
    });
  });

  group('compile-error fixtures', () {
    test('Compile failure caused by unsupported syntax is not a pass', () {
      final verdict = runOne(
        '%%FAIL IGNORE MSG\nimport "syntaxerror" as e; .\n'
        "jq: error: syntax error, unexpected ';', expecting end of file "
        'at tests/modules/syntaxerror/syntaxerror.jq, line 1, column 4:\n',
      );
      expect(verdict.status, CaseStatus.unsupported);
      expect(verdict.reason, 'unsupportedConstruct');
      expect(verdict.detail, contains('zaru: unsupported'));
    });

    test('Rendered diagnostics follow upstream callback policy', () {
      const key =
          'jq: error: Cannot use number (0) as object key at <top-level>, '
          'line 1, column 3:\n';
      // Single diagnostic with excerpt and caret.
      expectPassed(runOne('%%FAIL\n{(0):1}\n$key    {(0):1}\n      ^\n'));
      // Two diagnostics: only the LAST jq error block is compared.
      expectPassed(
        runOne(
          '%%FAIL\n{1+2:3}\n'
          'jq: error: May need parentheses around object key expression '
          'at <top-level>, line 1, column 2:\n    {1+2:3}\n     ^^^\n',
        ),
      );
      // The first block is not what the callback keeps.
      expectFailed(
        runOne(
          '%%FAIL\n{1+2:3}\n'
          'jq: error: syntax error, unexpected LITERAL at <top-level>, '
          'line 1, column 2:\n    {1+2:3}\n     ^\n',
        ),
        'diagnosticMismatch',
      );
      // Wrong excerpt text and a surplus caret line both fail.
      expectFailed(
        runOne('%%FAIL\n{(0):1}\n$key    {(0):2}\n'),
        'diagnosticMismatch',
      );
      expectFailed(
        runOne('%%FAIL\n{(0):1}\n$key    {(0):1}\n'),
        'diagnosticMismatch',
      );
      // IGNORE MSG ignores only the text.
      expectPassed(runOne('%%FAIL IGNORE MSG\n{(0):1}\nanything\n'));
      // A program that compiles cannot satisfy a compile failure.
      expectFailed(runOne('%%FAIL IGNORE MSG\n.\n'), 'compiledSuccessfully');
      expectFailed(runOne('%%FAIL\n.\njq: error: x\n'), 'compiledSuccessfully');
    });

    test('a runtime error never satisfies a compile failure', () {
      expectFailed(
        runOne('%%FAIL IGNORE MSG\nerror("x")\n'),
        'compiledSuccessfully',
      );
    });
  });

  group('upstream callback helpers', () {
    test('selectJqError keeps the last block starting with jq: error', () {
      expect(
        selectJqError([
          'jq: error: a',
          'zaru: unsupported: b',
          'jq: error: c',
          'jq: 2 compile errors',
        ]),
        'jq: error: c',
      );
      expect(selectJqError(['zaru: unsupported: b']), isNull);
      expect(selectJqError(const []), isNull);
    });

    test('selectJqError truncates to the 4095-byte buffer', () {
      final selected = selectJqError(['jq: error: ${'x' * 5000}'])!;
      expect(selected.length, 4095);
      // Multi-byte text is cut on bytes, never inside a character.
      final wide = selectJqError(['jq: error: ${'é' * 3000}'])!;
      expect(wide.length, lessThan(4095));
      expect(wide.startsWith('jq: error: '), isTrue);
    });

    test('diagnosticMatches uses byte prefixes and one newline', () {
      expect(diagnosticMatches(['jq: error: a'], 'jq: error: abc'), isFalse);
      expect(diagnosticMatches(['jq: error: abc'], 'jq: error: abc'), isTrue);
      expect(diagnosticMatches(['jq: error: abc'], 'jq: error: abc\n'), isTrue);
      expect(
        diagnosticMatches(['jq: error: abc', '  ^'], 'jq: error: abc\n  ^'),
        isTrue,
      );
      // A prefix of a longer line leaves a remainder that no line consumes.
      expect(diagnosticMatches(['jq: error: ab'], 'jq: error: abc\n'), isFalse);
      // Two newlines are not consumed.
      expect(diagnosticMatches(['a', 'b'], 'a\n\nb'), isFalse);
      // A missing message never matches a nonempty expectation.
      expect(diagnosticMatches(['a'], null), isFalse);
    });
  });
}
