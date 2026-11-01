import 'dart:convert';
import 'dart:io';

import '../test/conformance/fixtures.dart';
import 'sha256.dart';

const _manifestPath = '.dart_tool/reference/native-build.json';
const _corpusFormat = 'zaru-jq-reference-census-v1';
const _buildFormat = 'zaru-native-reference-build-v1';
const _expectedVersion = 'jq-1.8.2';
const _expectedCommit = '34f7186b86743a083a589741b6cea95293524108';
const _expectedArchiveSha256 =
    '332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c';
const _environment = <String, String>{'LC_ALL': 'C', 'PAGER': 'less'};

Future<void> main(List<String> args) async {
  try {
    await _main(args);
  } on _ReferenceFailure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('reference_capture_incomplete: $error');
    exitCode = 1;
  }
}

Future<void> _main(List<String> args) async {
  String? output;
  String? probe;
  String? jqOverride;
  String? sourceOverride;
  String? modulesOverride;
  for (var i = 0; i < args.length; i++) {
    final option = args[i];
    switch (option) {
      case '--output':
        output = _argument(args, ++i, option);
      case '--probe':
        probe = _argument(args, ++i, option);
      case '--jq':
        jqOverride = _argument(args, ++i, option);
      case '--source':
        sourceOverride = _argument(args, ++i, option);
      case '--modules':
        modulesOverride = _argument(args, ++i, option);
      default:
        throw _ReferenceFailure('reference_usage: unknown option $option');
    }
  }
  if (output == null || (args.contains('--probe') && probe == null)) {
    throw _ReferenceFailure('reference_usage: --output PATH is required');
  }

  final manifest = _loadManifest();
  final artifacts = _object(manifest['artifacts'], 'artifacts');
  final sourceRoot = sourceOverride ?? _string(manifest['sourceRoot'], 'sourceRoot');
  final modulesRoot = modulesOverride ?? _string(manifest['modulesRoot'], 'modulesRoot');
  final jqPath = jqOverride ?? _artifactPath(artifacts, 'jq');
  final driverPath = _artifactPath(artifacts, 'driver');
  final sourceHashes = _object(manifest['sourceHashes'], 'sourceHashes');

  await _verifyNativeInputs(
    artifacts,
    jqPath: jqPath,
    driverPath: driverPath,
    sourceRoot: sourceRoot,
    modulesRoot: modulesRoot,
    sourceHashes: sourceHashes,
  );

  if (probe != null) {
    final request = _readProbe(probe);
    final record = await _captureBatch(
      driverPath,
      jqPath,
      sourceRoot,
      modulesRoot,
      <_Request>[_Request(
        program: request['program']! as String,
        input: request['input']! as String,
      )],
    );
    final primary = _verifiedFact(record.single);
    final prefix = request['expectedPrefix'];
    if (prefix != null &&
        (prefix is! List<Object?> ||
            prefix.any((value) => value is! String) ||
            !_stringListsEqual(primary['outputPrefix']! as List<Object?>, prefix))) {
      throw const _ReferenceFailure('reference_capture_mismatch: expectedPrefix');
    }
    _publish(output, <String, Object?>{'primary': primary});
    return;
  }

  final fixtures = <JqFixture>[
    ...parseFixtures(
      File('test/conformance/jq.test').readAsStringSync(),
      source: 'jq.test',
    ),
    ...parseFixtures(
      File('test/conformance/man.test').readAsStringSync(),
      source: 'man.test',
    ),
  ]..sort((a, b) => a.id.compareTo(b.id));
  final ids = fixtures.map((fixture) => fixture.id).toSet();
  if (fixtures.length != 781 || ids.length != 781) {
    throw const _ReferenceFailure(
      'reference_capture_incomplete: fixture ID census is not 781 unique rows',
    );
  }
  for (final fixture in fixtures) {
    if (!fixture.isRunnable) {
      throw _ReferenceFailure(
        'reference_capture_incomplete: ${fixture.id} has ${fixture.problems}',
      );
    }
  }

  final requests = <_Request>[
    for (final fixture in fixtures)
      _Request(
        program: fixture.program,
        input: fixture.input ?? 'null',
        expected: fixture.kind == FixtureKind.evaluation ? fixture.outputs : null,
      ),
  ];
  final records = await _captureBatch(
    driverPath,
    jqPath,
    sourceRoot,
    modulesRoot,
    requests,
  );
  if (records.length != fixtures.length) {
    throw const _ReferenceFailure(
      'reference_capture_mismatch: native batch record count differs from requests',
    );
  }
  final cases = <String, Object?>{};
  var compileErrorCount = 0;
  for (var i = 0; i < fixtures.length; i++) {
    final fixture = fixtures[i];
    final fact = _verifiedFact(records[i], fixture: fixture);
    if (fixture.kind == FixtureKind.compileError) compileErrorCount++;
    cases[fixture.id] = <String, Object?>{'primary': fact};
  }
  if (compileErrorCount != 19) {
    throw _ReferenceFailure(
      'reference_capture_mismatch: expected 19 compile-error fixtures, got $compileErrorCount',
    );
  }
  _publish(output, <String, Object?>{
    'format': _corpusFormat,
    'total': cases.length,
    'cases': cases,
    'provenance': <String, Object?>{
      'jqVersion': _expectedVersion,
      'jqCommit': _expectedCommit,
      'archiveSha256': _expectedArchiveSha256,
      'buildManifest': _manifestPath,
      'sourceRoot': _portablePath(_string(manifest['sourceRoot'], 'sourceRoot')),
      'modulesRoot': _portablePath(_string(manifest['modulesRoot'], 'modulesRoot')),
      'jq': <String, Object?>{
        'path': _artifactPath(artifacts, 'jq'),
        'sha256': _artifactHash(artifacts, 'jq'),
      },
      'driver': <String, Object?>{
        'path': _artifactPath(artifacts, 'driver'),
        'sha256': _artifactHash(artifacts, 'driver'),
      },
      'library': _artifactIdentity(artifacts, 'library'),
      'driverSource': _artifactIdentity(artifacts, 'driverSource'),
      'compiler': manifest['compiler'],
      'configureFlags': manifest['configureFlags'],
      'environment': <String, String>{
        ..._environment,
        'PATH': _nativePathEnvironment,
        'JQ_LIBRARY_PATH': _portablePath(_string(manifest['modulesRoot'], 'modulesRoot')),
      },
      'command': <String>[
        'reference_capture',
        _artifactPath(artifacts, 'jq'),
        _portablePath(_string(manifest['modulesRoot'], 'modulesRoot')),
      ],
      'recordedPathRewrite': <String, String>{
        '<absolute modulesRoot>/': 'tests/modules/',
      },
      'sourceHashes': sourceHashes,
    },
  });
}

Future<List<Map<String, Object?>>> _captureBatch(
  String driverPath,
  String jqPath,
  String sourceRoot,
  String modulesPath,
  List<_Request> requests,
) async {
  // Like pinned tests/jqtest, pass an absolute module directory (relative
  // search paths resolve differently for nested imports). The host prefix is
  // then rewritten to `tests/modules/` in recorded text, so the census never
  // contains a host-specific path.
  final moduleArgument = _nativePath(modulesPath);
  final hostModulesPrefix = '$moduleArgument/';
  final input = StringBuffer();
  for (final request in requests) {
    input.writeln(jsonEncode(<String, Object?>{
      'program': request.program,
      'input': request.input,
      if (request.expected != null) 'expected': request.expected,
    }));
  }
  final process = await _runNative(
    _nativePath(driverPath),
    <String>[_nativePath(jqPath), moduleArgument],
    input: input.toString(),
    workingDirectory: Directory.current.path,
    libraryPath: moduleArgument,
  );
  if (process.exitCode != 0) {
    throw _ReferenceFailure(
      'reference_capture_mismatch: native driver exited ${process.exitCode}: '
      '${_safeDiagnostic(process.stderr)}',
    );
  }
  final stdoutText = process.stdout;
  final lines = const LineSplitter().convert(stdoutText);
  if (lines.length != requests.length) {
    throw _ReferenceFailure(
      'reference_capture_mismatch: expected ${requests.length} native records, got ${lines.length}',
    );
  }
  final records = <Map<String, Object?>>[];
  for (var index = 0; index < lines.length; index++) {
    Object? decoded;
    try {
      decoded = jsonDecode(
        lines[index].replaceAll(hostModulesPrefix, 'tests/modules/'),
      );
    } on FormatException catch (error) {
      throw _ReferenceFailure(
        'reference_capture_mismatch: invalid native record $index: $error',
      );
    }
    if (decoded is! Map<String, Object?> || decoded['ok'] != true) {
      throw _ReferenceFailure(
        'reference_capture_mismatch: native record $index is not successful',
      );
    }
    records.add(decoded);
  }
  if (!Directory(modulesPath).existsSync()) {
    throw const _ReferenceFailure('reference_modules_missing: module directory disappeared');
  }
  return records;
}

Future<_NativeProcessResult> _runNative(
  String executable,
  List<String> arguments, {
  required String input,
  required String workingDirectory,
  required String libraryPath,
}) async {
  final environment = <String, String>{
    'LC_ALL': 'C',
    'PAGER': 'less',
    'PATH': _nativePathEnvironment,
    'JQ_LIBRARY_PATH': libraryPath,
  };
  if (Platform.isWindows) {
    final root = _nativePath(workingDirectory);
    final command = <String>[
      '--cd',
      root,
      '--exec',
      '/usr/bin/env',
      '-i',
      for (final entry in environment.entries) '${entry.key}=${entry.value}',
      executable,
      ...arguments,
    ];
    final process = await Process.start(
      'wsl.exe',
      command,
      runInShell: false,
      includeParentEnvironment: true,
    );
    process.stdin.write(input);
    await process.stdin.close();
    final output = await Future.wait<String>(<Future<String>>[
      process.stdout.transform(utf8.decoder).join(),
      process.stderr.transform(utf8.decoder).join(),
    ]);
    return _NativeProcessResult(await process.exitCode, output[0], output[1]);
  }
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  process.stdin.write(input);
  await process.stdin.close();
  final output = await Future.wait<String>(<Future<String>>[
    process.stdout.transform(utf8.decoder).join(),
    process.stderr.transform(utf8.decoder).join(),
  ]);
  return _NativeProcessResult(await process.exitCode, output[0], output[1]);
}

Map<String, Object?> _verifiedFact(
  Map<String, Object?> record, {
  JqFixture? fixture,
}) {
  final terminal = _string(record['terminal'], 'terminal');
  if (!const <String>{'exhausted', 'runtimeError', 'compileError'}.contains(terminal)) {
    throw const _ReferenceFailure('reference_capture_mismatch: unknown terminal state');
  }
  final compiled = record['compiled'];
  if (compiled is! bool || compiled != (terminal != 'compileError')) {
    throw const _ReferenceFailure('reference_capture_mismatch: compile state disagrees with terminal');
  }
  final outputPrefix = _stringList(record['outputPrefix'], 'outputPrefix');
  final outputKinds = _stringList(record['outputKinds'], 'outputKinds');
  final outputNumberKinds = _nullableStringList(
    record['outputNumberKinds'],
    'outputNumberKinds',
  );
  final outputWire = _stringList(record['outputWire'], 'outputWire');
  if (outputPrefix.length != outputKinds.length ||
      outputPrefix.length != outputNumberKinds.length ||
      outputPrefix.length != outputWire.length) {
    throw const _ReferenceFailure('reference_capture_mismatch: native output arrays differ in length');
  }
  for (var i = 0; i < outputWire.length; i++) {
    final wire = _decodeWire(outputWire[i]);
    if (wire.kind != outputKinds[i] ||
        wire.numberKind != outputNumberKinds[i] ||
        !_matchesPrintedValue(outputPrefix[i], wire)) {
      throw _ReferenceFailure(
        'reference_capture_mismatch: output wire disagrees with native facts '
        '(${fixture?.id ?? 'probe'} output $i: ${outputPrefix[i]} / ${outputWire[i]})',
      );
    }
  }
  final diagnostics = _stringList(record['diagnostics'], 'diagnostics');
  final cliExitCode = record['cliExitCode'];
  if (cliExitCode is! int) {
    throw const _ReferenceFailure('reference_capture_mismatch: cliExitCode is not an integer');
  }
  final cliStdout = _string(record['cliStdout'], 'cliStdout');
  final cliStderr = _string(record['cliStderr'], 'cliStderr');
  if (!_stringListsEqual(outputPrefix, const LineSplitter().convert(cliStdout))) {
    throw _ReferenceFailure(
      'reference_capture_mismatch: C API output differs from independent CLI '
      '(${fixture?.id ?? 'probe'}: $outputPrefix / ${_safeDiagnostic(cliStdout)} '
      '/ ${_safeDiagnostic(cliStderr)})',
    );
  }
  final expectedExit = switch (terminal) {
    'exhausted' => 0,
    'compileError' => 3,
    'runtimeError' => 5,
    _ => -1,
  };
  if (cliExitCode != expectedExit) {
    throw const _ReferenceFailure('reference_capture_mismatch: terminal disagrees with CLI exit code');
  }
  if (terminal == 'compileError') {
    if (diagnostics.isEmpty || diagnostics.any((diagnostic) => !cliStderr.contains(diagnostic))) {
      throw const _ReferenceFailure('reference_capture_mismatch: compile callbacks absent from CLI stderr');
    }
  }
  if (fixture != null) {
    // jq_test.c: compile-error fixtures must fail to compile; evaluation
    // fixtures must compile, and after the expected outputs an uncaught runtime
    // error is accepted (only a superfluous valid result fails the case).
    final terminalAllowed = fixture.kind == FixtureKind.compileError
        ? terminal == 'compileError'
        : terminal != 'compileError';
    if (!terminalAllowed) {
      throw _ReferenceFailure(
        'reference_capture_mismatch: ${fixture.id} observed unexpected $terminal',
      );
    }
    if (fixture.kind == FixtureKind.evaluation && record['fixtureOutputsMatch'] != true) {
      throw _ReferenceFailure(
        'reference_capture_mismatch: native fixture output comparison failed for ${fixture.id}',
      );
    }
    if (fixture.checkDiagnostic) {
      if (!_jqTestMessageMatches(diagnostics, fixture.diagnostics)) {
        throw _ReferenceFailure(
          'reference_capture_mismatch: compile diagnostic differs from fixture ${fixture.id}',
        );
      }
    }
  }

  final fact = <String, Object?>{
    'compiled': compiled,
    'outputPrefix': outputPrefix,
    'outputKinds': outputKinds,
    'outputNumberKinds': outputNumberKinds,
    'outputWire': outputWire,
    'diagnostics': diagnostics,
    'terminal': terminal,
    'cliExitCode': cliExitCode,
    'cliStdout': cliStdout,
    'cliStderr': cliStderr,
  };
  if (record.containsKey('fixtureOutputsMatch')) {
    fact['fixtureOutputsMatch'] = record['fixtureOutputsMatch'];
  }
  if (terminal == 'runtimeError') {
    final errorWire = record['errorWire'];
    if (errorWire is! String) {
      throw const _ReferenceFailure('reference_capture_mismatch: runtime error wire missing');
    }
    final error = _decodeWire(errorWire);
    final errorText = _string(record['errorValueText'], 'errorValueText');
    final errorKind = _string(record['errorValueKind'], 'errorValueKind');
    final errorNumberKind = record['errorValueNumberKind'];
    if (error.kind != errorKind || error.numberKind != errorNumberKind ||
        !_matchesPrintedValue(errorText, error)) {
      throw const _ReferenceFailure('reference_capture_mismatch: error wire disagrees with native error facts');
    }
    fact.addAll(<String, Object?>{
      'errorWire': errorWire,
      'errorValueText': errorText,
      'errorValueKind': errorKind,
      'errorValueNumberKind': errorNumberKind,
    });
    final projection = _projectWire(error);
    if (projection.representable) fact['errorValue'] = projection.value;
  } else if (record.containsKey('errorWire') ||
      record.containsKey('errorValueText') ||
      record.containsKey('errorValueKind')) {
    throw const _ReferenceFailure('reference_capture_mismatch: error value present without runtime error');
  }
  return fact;
}

/// Mirrors pinned jq_test.c: keep the last callback message starting with
/// `jq: error` (in a 4096-byte buffer), then consume it with each expected
/// line as a byte prefix, skipping one newline after each; nothing may remain.
bool _jqTestMessageMatches(List<String> diagnostics, List<String> expected) {
  List<int>? selected;
  for (final message in diagnostics) {
    if (message.startsWith('jq: error')) selected = utf8.encode(message);
  }
  if (selected == null) return false;
  if (selected.length > 4095) selected = selected.sublist(0, 4095);
  var offset = 0;
  for (final line in expected) {
    final bytes = utf8.encode(line);
    if (offset + bytes.length > selected.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (selected[offset + i] != bytes[i]) return false;
    }
    offset += bytes.length;
    if (offset < selected.length && selected[offset] == 0x0a) offset++;
  }
  return offset == selected.length;
}

_WireValue _decodeWire(String text) {
  Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException catch (error) {
    throw _ReferenceFailure('reference_capture_mismatch: malformed tagged wire: $error');
  }
  if (value is! List<Object?> || value.isEmpty || value.first is! String) {
    throw const _ReferenceFailure('reference_capture_mismatch: malformed tagged wire node');
  }
  final tag = value[0]! as String;
  switch (tag) {
    case 'null':
      if (value.length != 1) break;
      return _WireValue('null', null);
    case 'boolean':
      if (value.length == 2 && value[1] is bool) return _WireValue('boolean', value[1]);
      break;
    case 'string':
      if (value.length == 2 && value[1] is String) return _WireValue('string', value[1]);
      break;
    case 'number':
      if (value.length == 3 && value[1] is String && value[2] is String) {
        final kind = value[1]! as String;
        if (const <String>{'literal', 'computed'}.contains(kind) &&
            (value[2]! as String).isNotEmpty) {
          return _WireValue('number', value[2], kind);
        }
      } else if (value.length == 2 &&
          const <String>{'nan', 'positiveInfinity', 'negativeInfinity'}.contains(value[1])) {
        return _WireValue('number', null, value[1]! as String);
      }
      break;
    case 'array':
      if (value.length == 2 && value[1] is List<Object?>) {
        return _WireValue(
          'array',
          (value[1]! as List<Object?>).map((child) => _decodeWire(jsonEncode(child))).toList(),
        );
      }
      break;
    case 'object':
      if (value.length == 2 && value[1] is List<Object?>) {
        final entries = <(String, _WireValue)>[];
        for (final entry in value[1]! as List<Object?>) {
          if (entry is! List<Object?> || entry.length != 2 || entry[0] is! String) break;
          entries.add((entry[0]! as String, _decodeWire(jsonEncode(entry[1]))));
        }
        if (entries.length == (value[1]! as List<Object?>).length) {
          return _WireValue('object', entries);
        }
      }
      break;
  }
  throw const _ReferenceFailure('reference_capture_mismatch: invalid tagged wire payload');
}

bool _matchesPrintedValue(String text, _WireValue wire) {
  if (wire.kind == 'null') return text == 'null';
  if (wire.kind == 'boolean') return text == (wire.value as bool ? 'true' : 'false');
  if (wire.kind == 'string') {
    try {
      return jsonDecode(text) == wire.value;
    } on FormatException {
      return false;
    }
  }
  if (wire.kind == 'number') {
    if (wire.numberKind == 'nan') return text == 'null';
    if (wire.numberKind == 'positiveInfinity') return text == '1.7976931348623157e+308';
    if (wire.numberKind == 'negativeInfinity') return text == '-1.7976931348623157e+308';
    return text == wire.value;
  }
  return true;
}

_Projection _projectWire(_WireValue wire) {
  switch (wire.kind) {
    case 'null':
      return const _Projection(true, null);
    case 'boolean':
    case 'string':
      return _Projection(true, wire.value);
    case 'number':
      if (wire.numberKind != 'literal' && wire.numberKind != 'computed') {
        return const _Projection(false, null);
      }
      final text = wire.value! as String;
      final integer = int.tryParse(text);
      if (integer != null && integer.abs() <= 9007199254740991) {
        return _Projection(true, integer);
      }
      final parsed = double.tryParse(text);
      if (parsed != null && parsed.isFinite && parsed.toString() == text) {
        return _Projection(true, parsed);
      }
      return const _Projection(false, null);
    case 'array':
      final result = <Object?>[];
      for (final child in wire.value! as List<_WireValue>) {
        final projected = _projectWire(child);
        if (!projected.representable) return const _Projection(false, null);
        result.add(projected.value);
      }
      return _Projection(true, result);
    case 'object':
      final result = <String, Object?>{};
      for (final (key, child) in wire.value! as List<(String, _WireValue)>) {
        final projected = _projectWire(child);
        if (!projected.representable) return const _Projection(false, null);
        result[key] = projected.value;
      }
      return _Projection(true, result);
  }
  return const _Projection(false, null);
}

Map<String, Object?> _loadManifest() {
  final file = File(_manifestPath);
  if (!file.existsSync()) {
    throw const _ReferenceFailure('reference_build_manifest_missing: run reference-setup first');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw _ReferenceFailure('reference_build_manifest_invalid: $error');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['format'] != _buildFormat ||
      decoded['version'] != _expectedVersion ||
      decoded['commit'] != _expectedCommit ||
      decoded['archiveSha256'] != _expectedArchiveSha256 ||
      decoded['sourceRoot'] is! String || decoded['modulesRoot'] is! String ||
      decoded['compiler'] is! String || decoded['configureFlags'] is! List<Object?> ||
      decoded['sourceHashes'] is! Map<String, Object?> ||
      decoded['artifacts'] is! Map<String, Object?>) {
    throw const _ReferenceFailure('reference_build_manifest_invalid: identity or required fields differ');
  }
  return decoded;
}

Future<void> _verifyNativeInputs(
  Map<String, Object?> artifacts, {
  required String jqPath,
  required String driverPath,
  required String sourceRoot,
  required String modulesRoot,
  required Map<String, Object?> sourceHashes,
}) async {
  for (final key in <String>['jq', 'driver', 'library', 'driverSource']) {
    _artifactIdentity(artifacts, key);
  }
  final jqHash = _artifactHash(artifacts, 'jq');
  final driverHash = _artifactHash(artifacts, 'driver');
  if (!_exists(jqPath) || _sha256(jqPath) != jqHash) {
    throw _ReferenceFailure('reference_binary_hash_mismatch: $jqPath');
  }
  if (!_exists(driverPath) || _sha256(driverPath) != driverHash) {
    throw _ReferenceFailure('reference_driver_hash_mismatch: $driverPath');
  }
  for (final key in <String>['library', 'driverSource']) {
    final artifact = _artifactIdentity(artifacts, key);
    final path = _string(artifact['path'], 'artifacts.$key.path');
    if (!_exists(path) || _sha256(path) != artifact['sha256']) {
      throw _ReferenceFailure('reference_source_hash_mismatch: $path');
    }
  }
  final version = await _runNative(
    _nativePath(jqPath),
    const <String>['--version'],
    input: '',
    workingDirectory: Directory.current.path,
    libraryPath: _nativePath(modulesRoot),
  );
  if (version.exitCode != 0 || version.stdout.trim() != _expectedVersion) {
    throw const _ReferenceFailure('reference_binary_hash_mismatch: expected jq-1.8.2');
  }
  for (final entry in sourceHashes.entries) {
    if (entry.value is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.value! as String)) {
      throw const _ReferenceFailure('reference_build_manifest_invalid: invalid source hash');
    }
    final relative = entry.key;
    if (relative.startsWith('/') ||
        relative.contains('..') ||
        relative.contains('\\')) {
      throw _ReferenceFailure('reference_build_manifest_invalid: unsafe source hash path $relative');
    }
    final sourceFile = File('$sourceRoot/$relative');
    if (!sourceFile.existsSync() || _sha256(sourceFile.path) != entry.value) {
      throw _ReferenceFailure('reference_source_hash_mismatch: $relative');
    }
  }
  final modules = Directory(modulesRoot);
  if (!modules.existsSync()) {
    throw _ReferenceFailure('reference_modules_missing: $modulesRoot');
  }
  const modulePrefix = 'tests/modules/';
  final moduleEntries = sourceHashes.keys.where((path) => path.startsWith(modulePrefix));
  if (moduleEntries.isEmpty) {
    throw const _ReferenceFailure('reference_build_manifest_invalid: module provenance is absent');
  }
  final moduleHashes = <String, String>{
    for (final path in moduleEntries)
      path.substring(modulePrefix.length): sourceHashes[path]! as String,
  };
  final recordedModuleFiles = moduleHashes.keys.toSet();
  for (final entity in modules.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      final relative = entity.path.substring(modules.path.length + 1).replaceAll('\\', '/');
      if (!recordedModuleFiles.contains(relative)) {
        throw _ReferenceFailure('reference_source_hash_mismatch: unrecorded module $relative');
      }
    }
  }
  for (final path in recordedModuleFiles) {
    final file = File('$modulesRoot/$path');
    if (!file.existsSync() || _sha256(file.path) != moduleHashes[path]) {
      throw _ReferenceFailure('reference_source_hash_mismatch: pinned module file $path');
    }
  }
}

Map<String, Object?> _artifactIdentity(Map<String, Object?> artifacts, String name) {
  final value = _object(artifacts[name], 'artifacts.$name');
  final path = _string(value['path'], 'artifacts.$name.path');
  final hash = _string(value['sha256'], 'artifacts.$name.sha256');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
    throw _ReferenceFailure('reference_build_manifest_invalid: artifacts.$name sha256');
  }
  return <String, Object?>{'path': path, 'sha256': hash};
}

String _artifactPath(Map<String, Object?> artifacts, String name) =>
    _string(_artifactIdentity(artifacts, name)['path'], 'artifacts.$name.path');

String _artifactHash(Map<String, Object?> artifacts, String name) =>
    _string(_artifactIdentity(artifacts, name)['sha256'], 'artifacts.$name.sha256');

Map<String, Object?> _readProbe(String path) {
  Object? decoded;
  try {
    decoded = jsonDecode(File(path).readAsStringSync());
  } on FormatException catch (error) {
    throw _ReferenceFailure('reference_usage: invalid probe request: $error');
  }
  if (decoded is! Map<String, Object?> ||
      decoded['program'] is! String || decoded['input'] is! String ||
      (decoded.containsKey('expectedPrefix') &&
          (decoded['expectedPrefix'] is! List<Object?> ||
              (decoded['expectedPrefix']! as List<Object?>).any((value) => value is! String)))) {
    throw const _ReferenceFailure(
      'reference_usage: request requires string program and raw JSON input',
    );
  }
  return decoded;
}

void _publish(String destinationPath, Map<String, Object?> payload) {
  final destination = File(destinationPath).absolute;
  destination.parent.createSync(recursive: true);
  final temporary = File('${destination.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}');
  try {
    temporary.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
      encoding: utf8,
      flush: true,
    );
    temporary.renameSync(destination.path);
  } on Object {
    if (temporary.existsSync()) temporary.deleteSync();
    rethrow;
  }
}

String _sha256(String path) {
  try {
    return sha256Hex(File(path).readAsBytesSync());
  } on FileSystemException {
    throw _ReferenceFailure('reference_hash_failed: $path');
  }
}

String _argument(List<String> args, int index, String option) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw _ReferenceFailure('reference_usage: $option needs a value');
  }
  return args[index];
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  throw _ReferenceFailure('reference_build_manifest_invalid: $name is not an object');
}

String _string(Object? value, String name) {
  if (value is String) return value;
  throw _ReferenceFailure('reference_capture_mismatch: $name is not a string');
}

List<String> _stringList(Object? value, String name) {
  if (value is List<Object?> && value.every((item) => item is String)) {
    return value.cast<String>();
  }
  throw _ReferenceFailure('reference_capture_mismatch: $name is not a string array');
}

List<String?> _nullableStringList(Object? value, String name) {
  if (value is List<Object?> && value.every((item) => item == null || item is String)) {
    return value.cast<String?>();
  }
  throw _ReferenceFailure('reference_capture_mismatch: $name is not a nullable string array');
}

bool _stringListsEqual(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

String _portablePath(String path) => path.replaceAll('\\', '/');

const _nativePathEnvironment = '/usr/local/bin:/usr/bin:/bin';

String _nativePath(String path) {
  if (!Platform.isWindows) return File(path).absolute.path;
  final normalized = File(path).absolute.path.replaceAll('\\', '/');
  final match = RegExp(r'^([A-Za-z]):/(.*)$').firstMatch(normalized);
  if (match == null) throw _ReferenceFailure('reference_path_invalid: $path');
  return '/mnt/${match.group(1)!.toLowerCase()}/${match.group(2)}';
}

bool _exists(String path) => File(path).existsSync();

String _safeDiagnostic(String text) => text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

final class _Request {
  const _Request({required this.program, required this.input, this.expected});
  final String program;
  final String input;
  final List<String>? expected;
}

final class _NativeProcessResult {
  const _NativeProcessResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

final class _WireValue {
  const _WireValue(this.kind, this.value, [this.numberKind]);
  final String kind;
  final Object? value;
  final String? numberKind;
}

final class _Projection {
  const _Projection(this.representable, this.value);
  final bool representable;
  final Object? value;
}

final class _ReferenceFailure implements Exception {
  const _ReferenceFailure(this.message);
  final String message;
}
