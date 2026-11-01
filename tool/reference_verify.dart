import 'dart:convert';
import 'dart:io';

import '../test/conformance/conformance_io.dart';
import '../test/support/conformance_baseline.dart';
import 'sha256.dart';

const _integrityFormat = 'zaru-jq-reference-integrity-v1';

/// Verifies the frozen reference baseline without starting jq.
///
/// The checks themselves are shared with the conformance commands
/// (`verifyBaseline`): payload digests, pinned provenance, exactly the 781
/// stable IDs and every case's facts. This tool adds the explicit `--record`
/// freeze step and the check that the recorded artifact paths are the ones
/// requested.
void main(List<String> args) {
  try {
    _verify(args);
  } on BaselineFailure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('reference_verify_failed: $error');
    exitCode = 1;
  }
}

void _verify(List<String> args) {
  var integrityPath = defaultIntegrityPath;
  var censusPath = defaultCensusPath;
  var classificationPath = defaultClassificationPath;
  var record = false;
  for (var index = 0; index < args.length; index++) {
    final option = args[index];
    if (option == '--record') {
      record = true;
      continue;
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw BaselineFailure('reference_verify_usage', '$option needs a path');
    }
    final path = args[++index];
    switch (option) {
      case '--integrity':
        integrityPath = path;
      case '--census':
        censusPath = path;
      case '--classification':
        classificationPath = path;
      default:
        throw BaselineFailure(
          'reference_verify_usage',
          'unknown option $option',
        );
    }
  }
  if (record) {
    // Explicit freeze step: record digests of the reviewed artifacts, then
    // verify them below exactly like an ordinary check.
    final contents = <String, Object?>{
      'format': _integrityFormat,
      'census': <String, Object?>{
        'path': _normalized(censusPath),
        'sha256': sha256Hex(readBytes(censusPath)),
      },
      'classification': <String, Object?>{
        'path': _normalized(classificationPath),
        'sha256': sha256Hex(readBytes(classificationPath)),
      },
    };
    File(integrityPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(contents)}\n',
    );
  }
  _verifyRecordedPaths(integrityPath, censusPath, classificationPath);
  loadVerifiedBaseline(
    BaselinePaths(
      integrity: integrityPath,
      census: censusPath,
      classification: classificationPath,
    ),
  );
}

void _verifyRecordedPaths(
  String integrityPath,
  String censusPath,
  String classificationPath,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(readBytes(integrityPath)));
  } on FormatException catch (error) {
    throw BaselineFailure(
      'reference_integrity_invalid',
      '$integrityPath: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw BaselineFailure(
      'reference_integrity_invalid',
      '$integrityPath is not an object',
    );
  }
  final integrity = decoded;
  String recorded(String name) {
    final entry = integrity[name];
    final path = entry is Map<String, Object?> ? entry['path'] : null;
    if (path is! String) {
      throw BaselineFailure(
        'reference_integrity_invalid',
        '$name.path is not a string',
      );
    }
    return _normalized(path);
  }

  if (integrity['format'] == _integrityFormat &&
      (recorded('census') != _normalized(censusPath) ||
          recorded('classification') != _normalized(classificationPath))) {
    throw const BaselineFailure(
      'reference_integrity_invalid',
      'integrity paths do not match requested artifacts',
    );
  }
}

String _normalized(String value) => value.replaceAll('\\', '/');
