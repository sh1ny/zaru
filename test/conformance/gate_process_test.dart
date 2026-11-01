@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Runs the real conformance commands as subprocesses.
///
/// The child process never sees a `jq` executable: every PATH directory that
/// contains one is removed and, where scripts are executable, a tripwire named
/// `jq` records any attempt to start it. The commands must still verify the
/// frozen baseline, execute the corpus with zaru and decide.
void main() {
  late Directory temporary;

  setUp(() => temporary = Directory.systemTemp.createTempSync('zaru-gate-'));
  tearDown(() => temporary.deleteSync(recursive: true));

  final isWindows = Platform.isWindows;

  /// PATH with every directory that provides jq removed.
  String scrubbedPath(Directory tripwireDirectory) {
    final separator = isWindows ? ';' : ':';
    final names = isWindows
        ? ['jq.exe', 'jq.cmd', 'jq.bat', 'jq.ps1', 'jq']
        : ['jq'];
    final kept = <String>[
      for (final entry in (Platform.environment['PATH'] ?? '').split(separator))
        if (entry.isNotEmpty &&
            !names.any((name) => File('$entry/$name').existsSync()))
          entry,
    ];
    return [tripwireDirectory.path, ...kept].join(separator);
  }

  /// Installs a `jq` that records its invocation. Windows cannot start a
  /// script by bare name from Dart, so there only the absence is asserted.
  File? installTripwire(Directory directory) {
    if (isWindows) return null;
    final marker = File('${directory.path}/jq-was-invoked');
    final script = File('${directory.path}/jq')
      ..writeAsStringSync(
        '#!/bin/sh\necho invoked > "${marker.path}"\nexit 3\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    return marker;
  }

  Future<ProcessResult> command(
    List<String> arguments, {
    required Directory tripwireDirectory,
  }) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/conformance.dart', ...arguments],
    environment: {'PATH': scrubbedPath(tripwireDirectory)},
  );

  test('Gate needs no native reference binary', () async {
    final tripwireDirectory = Directory('${temporary.path}/bin')..createSync();
    final marker = installTripwire(tripwireDirectory);
    final reportFile = File('${temporary.path}/report.json');
    // A stale report claiming success must not survive the invocation.
    reportFile.writeAsStringSync(
      jsonEncode({
        'runId': 'stale',
        'gate': {'passed': true},
      }),
    );

    final result = await command([
      '--gate',
      '--report',
      reportFile.path,
    ], tripwireDirectory: tripwireDirectory);

    final output = '${result.stdout}\n${result.stderr}';
    // M1 is accepted: the gate passes without any jq executable.
    expect(result.exitCode, 0, reason: output);
    expect(reportFile.existsSync(), isTrue, reason: output);
    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(report['runId'], isNot('stale'));
    expect(report['mode'], 'gate');
    expect((report['cases']! as List<Object?>).length, 781);
    final gate = report['gate']! as Map<String, Object?>;
    // The exit status is exactly the fresh verdict.
    expect(gate['passed'], isTrue, reason: output);
    expect(gate['floorSize'], greaterThan(0), reason: output);
    final counts = report['counts']! as Map<String, Object?>;
    expect(
      (counts['passed']! as int) +
          (counts['failed']! as int) +
          (counts['unsupported']! as int) +
          (counts['notRun']! as int),
      781,
    );
    expect(counts['notRun'], 0);
    // No reference process: the tripwire never ran.
    if (marker != null) expect(marker.existsSync(), isFalse);
    for (final path in [
      'tool/conformance.dart',
      'test/support/conformance_baseline.dart',
      'test/support/conformance_run.dart',
      'test/support/conformance_accounting.dart',
      'test/conformance/conformance_io.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('Process.')), reason: path);
      expect(source, isNot(contains('reference_capture')), reason: path);
    }
  });

  test(
    'Both conformance commands reject a tampered baseline payload',
    () async {
      final tripwireDirectory = Directory('${temporary.path}/bin')
        ..createSync();
      final census = File('${temporary.path}/census.json');
      final decoded =
          jsonDecode(
                File(
                  'test/conformance/reference/census.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      decoded['tampered'] = true;
      census.writeAsStringSync(jsonEncode(decoded));
      for (final mode in [
        <String>[],
        ['--gate'],
      ]) {
        final reportFile = File('${temporary.path}/report-${mode.length}.json');
        final result = await command([
          ...mode,
          '--census',
          census.path,
          '--report',
          reportFile.path,
        ], tripwireDirectory: tripwireDirectory);
        expect(result.exitCode, 2, reason: '${result.stdout}${result.stderr}');
        expect(
          result.stderr.toString(),
          contains('reference_integrity_mismatch'),
        );
        // Nothing was evaluated against the unverified reference.
        expect(reportFile.existsSync(), isFalse);
      }
    },
  );

  test(
    'The full command fails while any case fails and keeps all 781 IDs',
    () async {
      final tripwireDirectory = Directory('${temporary.path}/bin')
        ..createSync();
      final reportFile = File('${temporary.path}/full.json');
      final result = await command([
        '--report',
        reportFile.path,
      ], tripwireDirectory: tripwireDirectory);
      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
      final counts = report['counts']! as Map<String, Object?>;
      expect(report['mode'], 'full');
      expect((report['cases']! as List<Object?>).length, 781);
      expect(
        result.exitCode,
        counts['passed'] == 781 ? 0 : 1,
        reason: '${result.stdout}${result.stderr}',
      );
    },
  );
}
