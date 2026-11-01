import 'package:test/test.dart';
import 'package:zaru/src/syntax/diagnostic.dart';
import 'package:zaru/src/syntax/source_text.dart';
import 'package:zaru/src/syntax/span.dart';
import 'package:zaru/zaru.dart';

int _totalLength(Iterable<String> blocks) =>
    blocks.fold(0, (sum, block) => sum + block.length);

ZaruCompileError _compileError(String source) {
  try {
    Zaru.compile(source);
  } on ZaruCompileError catch (error) {
    return error;
  }
  throw StateError('expected a ZaruCompileError');
}

DiagnosticReport _manyDiagnostics(SourceText source, int count) =>
    DiagnosticReport(source, [
      for (var i = 0; i < count; i++)
        Diagnostic(DiagnosticKind.semantic, 'x', Span(i * 7, i * 7 + 5)),
    ]);

final _omitted = RegExp(r'^zaru: error: (\d+) more diagnostics omitted$');

/// Asserts the budget contract for a report of [total] diagnostics.
void _expectBounded(List<String> blocks, int total) {
  final summary = _omitted.firstMatch(blocks.last);
  expect(summary, isNotNull, reason: 'the last block is the summary');
  final omitted = int.parse(summary!.group(1)!);
  final shown = blocks.length - 1;
  expect(omitted, greaterThan(0));
  expect(shown + omitted, total);
  expect(
    _totalLength(blocks.take(shown)),
    lessThanOrEqualTo(maxRenderedDiagnosticBytes),
  );
}

void main() {
  group('rendered diagnostic budget', () {
    test('10000 unsupported \$ENV uses in a 70 KB line stay bounded', () {
      final source = '{${List.filled(10000, r'a:$ENV').join(',')}}';
      expect(source.length, greaterThan(60000));
      final error = _compileError(source);
      expect(error.isUnsupported, isTrue);
      _expectBounded(error.diagnostics, 10000);
      expect(error.diagnostics.first, startsWith('zaru: unsupported: '));
    });

    test('10000 undefined names in a 70 KB line stay bounded', () {
      final source = '{${List.filled(10000, r'a:$nope').join(',')}}';
      final error = _compileError(source);
      expect(error.isUnsupported, isFalse);
      expect(error.message, r'$nope is not defined');
      _expectBounded(error.diagnostics, 10000);
      expect(error.diagnostics.first, startsWith('jq: error: '));
    });

    test('the structured diagnostic list stays complete', () {
      final source = SourceText(List.filled(3000, r'$nope, ').join());
      final report = _manyDiagnostics(source, 3000);
      expect(report.diagnostics, hasLength(3000));
      expect(report.rendered.last, matches(_omitted));
    });

    test('a report that fits the budget has no summary', () {
      final error = _compileError(r'$a, $b, $c');
      expect(error.diagnostics, hasLength(3));
      expect(error.diagnostics.any(_omitted.hasMatch), isFalse);
    });

    test('lastJqError ignores the summary block', () {
      final report = _manyDiagnostics(
        SourceText(List.filled(3000, r'$nope, ').join()),
        3000,
      );
      expect(report.rendered.last, matches(_omitted));
      expect(report.lastJqError, startsWith('jq: error: '));
      expect(report.lastJqError, isNot(matches(_omitted)));
    });
  });

  group('excerpt window', () {
    test('a line of exactly maxExcerptBytes is rendered whole', () {
      final line = '.' * (maxExcerptBytes - 1);
      final source = SourceText('$line)');
      final block = renderDiagnostic(
        source,
        Diagnostic(
          DiagnosticKind.syntax,
          'syntax error',
          Span(maxExcerptBytes - 1, maxExcerptBytes),
        ),
      );
      final lines = block.split('\n');
      expect(lines[1], '    $line)');
      expect(lines[2], '    ${' ' * (maxExcerptBytes - 1)}^');
    });

    test('a long line is windowed around the span, carets aligned', () {
      final source = '"${'a' * 3000}" | \$nope | "${'b' * 3000}"';
      final error = _compileError(source);
      final lines = error.diagnostics.single.split('\n');
      expect(lines, hasLength(3));
      expect(lines[0], startsWith('jq: error: \$nope is not defined at '));
      final excerpt = lines[1];
      expect(excerpt, startsWith('    ...'));
      expect(excerpt, endsWith('...'));
      expect(excerpt.length, lessThan(maxExcerptBytes + 20));
      expect(lines[2].indexOf('^'), excerpt.indexOf(r'$nope'));
      expect(lines[2].replaceAll(' ', ''), '^^^^^');
    });

    test('a long line with the span near its start has only a tail marker', () {
      final source = '\$nope | "${'a' * 3000}"';
      final lines = _compileError(source).diagnostics.single.split('\n');
      expect(lines[1], startsWith('    \$nope | "aaa'));
      expect(lines[1], endsWith('...'));
      expect(lines[2], '    ^^^^^');
    });

    test('a long line with the span near its end has only a head marker', () {
      final source = '"${'a' * 3000}" | \$nope';
      final lines = _compileError(source).diagnostics.single.split('\n');
      expect(lines[1], startsWith('    ...'));
      expect(lines[1], endsWith(r'$nope'));
      expect(lines[2].indexOf('^'), lines[1].indexOf(r'$nope'));
    });

    test('a very long span is not drawn in full', () {
      final source = '{(${'"a"+' * 3000}"a"):1}';
      final block = renderDiagnostic(
        SourceText(source),
        Diagnostic(DiagnosticKind.semantic, 'long', Span(0, source.length)),
      );
      final lines = block.split('\n');
      expect(lines[1].length, lessThan(maxExcerptBytes + 20));
      expect(lines[2].length, lessThan(maxExcerptBytes + 20));
    });
  });
}
