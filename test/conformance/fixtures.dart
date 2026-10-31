import 'dart:convert';

/// The provenance of an upstream fixture file.
enum FixtureOrigin { upstreamTests, generatedManual }

/// The behavior requested by a fixture, independent of evaluator support.
enum FixtureKind { evaluation, compileError, unsupportedDirective }

/// A structural or input-data problem that prevents running a fixture.
enum FixtureProblem {
  missingProgram,
  missingInput,
  invalidInput,
  invalidOutput,
  missingDiagnostic,
  unsupportedDirective,
}

/// An upstream test, retaining source text rather than rounded Dart JSON values.
final class JqFixture {
  JqFixture({
    required this.source,
    required this.line,
    required this.program,
    required this.kind,
    required this.origin,
    required this.rawLines,
    required this.markers,
    required this.input,
    required this.outputs,
    required this.diagnostics,
    required this.checkDiagnostic,
    required this.problems,
  });

  final String source;
  final int line;
  final String program;
  final FixtureKind kind;
  final FixtureOrigin origin;
  final List<String> rawLines;
  final List<String> markers;
  final String? input;
  final List<String> outputs;
  final List<String> diagnostics;
  final bool checkDiagnostic;
  final List<FixtureProblem> problems;

  /// The stable file-and-program-line identifier, including malformed cases.
  String get id => '$source:$line';

  /// Whether fixture infrastructure can run this case once an evaluator exists.
  bool get isRunnable => problems.isEmpty;
}

/// Reads the jq 1.8.2 `src/jq_test.c` physical-line fixture protocol.
///
/// Only `%%FAIL` and `%%FAIL IGNORE MSG` are upstream directives. Comments and
/// blank lines are ignored while seeking a program, but terminate output or
/// diagnostic blocks. The input is the very next physical line, even if blank
/// or a comment. Programs and JSON values have no fixture-level continuation
/// syntax. Conditional and version checks inside programs are not skip rules.
/// Unknown `%%`/`!!` directives are retained as non-runnable cases, not aliases.
/// Raw JSON is retained to preserve jq decimal precision and non-finite values.
List<JqFixture> parseFixtures(
  String text, {
  required String source,
  FixtureOrigin origin = FixtureOrigin.upstreamTests,
}) {
  final lines = const LineSplitter().convert(text);
  final fixtures = <JqFixture>[];
  final pendingMarkers = <String>[];
  var index = 0;
  var markerLine = 0;

  while (index < lines.length) {
    final lineIndex = index++;
    final program = lines[lineIndex];
    if (_isBoundary(program)) continue;

    // jq's marker comparison includes the terminating newline.
    final terminated = lineIndex < lines.length - 1 || text.endsWith('\n');
    if (terminated && (program == '%%FAIL' || program == '%%FAIL IGNORE MSG')) {
      if (pendingMarkers.isEmpty) markerLine = lineIndex + 1;
      pendingMarkers.add(program);
      continue;
    }

    final markers = List<String>.unmodifiable(pendingMarkers);
    pendingMarkers.clear();
    final compileError = markers.isNotEmpty;
    final unknown =
        !compileError && (program.startsWith('%%') || program.startsWith('!!'));
    final kind = unknown
        ? FixtureKind.unsupportedDirective
        : compileError
        ? FixtureKind.compileError
        : FixtureKind.evaluation;
    final problems = <FixtureProblem>[];
    final rawLines = <String>[...markers, program];
    String? input;
    final outputs = <String>[];
    final diagnostics = <String>[];
    final checkDiagnostic = compileError && markers.last == '%%FAIL';

    if (unknown) {
      problems.add(FixtureProblem.unsupportedDirective);
    } else if (!compileError) {
      if (index == lines.length) {
        problems.add(FixtureProblem.missingInput);
      } else {
        input = lines[index++];
        rawLines.add(input);
        if (!_isJqJson(input)) problems.add(FixtureProblem.invalidInput);
      }
    }

    while (index < lines.length) {
      final line = lines[index++];
      if (_isBoundary(line)) break;
      rawLines.add(line);
      if (compileError) {
        diagnostics.add(line);
      } else {
        outputs.add(line);
        if (!unknown && !_isJqJson(line)) {
          problems.add(FixtureProblem.invalidOutput);
        }
      }
    }
    if (checkDiagnostic && diagnostics.isEmpty) {
      problems.add(FixtureProblem.missingDiagnostic);
    }
    fixtures.add(
      JqFixture(
        source: source,
        line: lineIndex + 1,
        program: program,
        kind: kind,
        origin: origin,
        rawLines: List.unmodifiable(rawLines),
        markers: markers,
        input: input,
        outputs: List.unmodifiable(outputs),
        diagnostics: List.unmodifiable(diagnostics),
        checkDiagnostic: checkDiagnostic,
        problems: List.unmodifiable(problems),
      ),
    );
  }

  // Unlike the C runner, report dangling directives rather than losing them.
  if (pendingMarkers.isNotEmpty) {
    fixtures.add(
      JqFixture(
        source: source,
        line: markerLine,
        program: '',
        kind: FixtureKind.compileError,
        origin: origin,
        rawLines: List.unmodifiable(pendingMarkers),
        markers: List.unmodifiable(pendingMarkers),
        input: null,
        outputs: const [],
        diagnostics: const [],
        checkDiagnostic: pendingMarkers.last == '%%FAIL',
        problems: const [FixtureProblem.missingProgram],
      ),
    );
  }
  return List.unmodifiable(fixtures);
}

bool _isBoundary(String line) {
  var index = 0;
  while (index < line.length &&
      (line.codeUnitAt(index) == 32 || line.codeUnitAt(index) == 9)) {
    index++;
  }
  return index == line.length || line.codeUnitAt(index) == 35;
}

// Validate JSON shape without materializing the values in the fixture model.
// jq accepts a leading BOM and non-finite numeric literals that Dart rejects.
// Substitute only whole non-string tokens for validation; never change raw data.
bool _isJqJson(String raw) {
  final text = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
  final normalized = StringBuffer();
  var index = 0;
  var inString = false;
  var escaped = false;
  while (index < text.length) {
    final character = text[index];
    if (inString) {
      normalized.write(character);
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (character == '"') {
        inString = false;
      }
      index++;
    } else if (character == '"') {
      inString = true;
      normalized.write(character);
      index++;
    } else if ('[]{}:, \t\r\n'.contains(character)) {
      normalized.write(character);
      index++;
    } else {
      final start = index++;
      while (index < text.length && !'[]{}:, \t\r\n"'.contains(text[index])) {
        index++;
      }
      final token = text.substring(start, index);
      final unsigned = token.startsWith('-') ? token.substring(1) : token;
      final lower = unsigned.toLowerCase();
      normalized.write(
        lower == 'nan' || lower == 'inf' || lower == 'infinity' ? '0' : token,
      );
    }
  }
  try {
    jsonDecode(normalized.toString());
    return true;
  } on FormatException {
    return false;
  }
}
