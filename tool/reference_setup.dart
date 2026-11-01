import 'dart:convert';
import 'dart:io';

const _archiveHash =
    '332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c';
const _version = 'jq-1.8.2';
const _commit = '34f7186b86743a083a589741b6cea95293524108';
const _format = 'zaru-native-reference-build-v1';
const _configureFlags = [
  '--disable-maintainer-mode',
  '--disable-shared',
  '--enable-static',
  '--with-oniguruma=builtin',
];
const _archive = '.dart_tool/reference/jq-1.8.2.zip';
const _source = '.dart_tool/reference/jq-1.8.2';
const _driverSource = 'tool/reference_capture.c';
const _manifest = '.dart_tool/reference/native-build.json';
const _cli = '.dart_tool/reference/jq-1.8.2/jq';
const _library = '.dart_tool/reference/jq-1.8.2/.libs/libjq.a';
const _driver = '.dart_tool/reference/reference_capture';

Future<void> main() async {
  try {
    await _setup();
  } on Object catch (error) {
    stderr.writeln('reference_setup_failed: $error');
    exitCode = 1;
  }
}

Future<void> _setup() async {
  final root = Directory.current.absolute;
  final archiveFile = File('${root.path}${Platform.pathSeparator}$_archive');
  final sourceDirectory = Directory('${root.path}${Platform.pathSeparator}$_source');
  final driverFile = File('${root.path}${Platform.pathSeparator}$_driverSource');
  final manifestFile = File('${root.path}${Platform.pathSeparator}$_manifest');

  if (!archiveFile.existsSync()) throw StateError('missing pinned source archive: $_archive');
  if (!sourceDirectory.existsSync()) throw StateError('missing task-provided source cache: $_source');
  if (!driverFile.existsSync()) throw StateError('parent native driver is not available: $_driverSource');
  final paths = await _nativePaths(root.path);
  final archiveHash = await _fileHash(paths, _archive);
  if (archiveHash != _archiveHash) {
    throw StateError('pinned source archive SHA-256 mismatch: $archiveHash');
  }
  final archiveSourceHashes = await _verifyAndHashArchive(paths);
  final driverHash = await _fileHash(paths, _driverSource);
  final compiler = await _compilerVersion(paths);
  final sourceHashes = archiveSourceHashes;

  if (await _cacheMatches(
    manifestFile,
    paths,
    root.path,
    compiler,
    sourceHashes,
    driverHash,
  )) {
    stderr.writeln('Native jq reference cache is current.');
    return;
  }

  _refuseUnownedBuildOutputs(root.path, manifestFile);
  await _runBuild(paths, sourceDirectory.path, root.path);

  final cliHash = await _requiredArtifactHash(paths, root.path, _cli);
  final libHash = await _requiredArtifactHash(paths, root.path, _library);
  final builtDriverHash = await _requiredArtifactHash(paths, root.path, _driver);
  final finalDriverHash = await _fileHash(paths, _driverSource);
  if (finalDriverHash != driverHash) {
    throw StateError('native driver source changed during build');
  }

  final manifest = <String, Object>{
    'format': _format,
    'version': _version,
    'commit': _commit,
    'archiveSha256': _archiveHash,
    'sourceRoot': _source,
    'modulesRoot': '$_source/tests/modules',
    'compiler': compiler,
    'configureFlags': _configureFlags,
    'sourceHashes': sourceHashes,
    'artifacts': {
      'jq': {'path': _cli, 'sha256': cliHash},
      'driver': {'path': _driver, 'sha256': builtDriverHash},
      'library': {'path': _library, 'sha256': libHash},
      'driverSource': {'path': _driverSource, 'sha256': driverHash},
    },
  };
  await _publishManifest(manifestFile, jsonEncode(manifest));
  stderr.writeln('Built native jq CLI, libjq, and reference driver.');
}

Future<_NativePaths> _nativePaths(String projectRoot) async {
  if (!Platform.isWindows) {
    return _NativePaths(
      windows: false,
      root: projectRoot,
    );
  }
  final root = await _wslPath(projectRoot);
  return _NativePaths(
    windows: true,
    root: root,
  );
}

Future<String> _wslPath(String path) async {
  final result = await Process.run('wsl.exe', ['--exec', 'wslpath', '-a', path]);
  if (result.exitCode != 0) {
    throw StateError('wslpath failed (${result.exitCode}): ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

Future<String> _compilerVersion(_NativePaths paths) async {
  final result = await paths.run(r'gcc --version | { IFS= read -r line; printf "%s\n" "$line"; }');
  if (result.exitCode != 0) {
    throw StateError('native gcc is unavailable: ${result.stderr}');
  }
  final line = (result.stdout as String).trim();
  if (line.isEmpty) throw StateError('native gcc returned an empty version');
  return line;
}

Future<Map<String, String>> _verifyAndHashArchive(_NativePaths paths) async {
  final script = r'''set -euo pipefail
archive=$1
source=$2
unzip -Z1 "$archive" | while IFS= read -r entry; do
  case "$entry" in */) continue ;; esac
  member=$entry
  entry=${entry#jq-1.8.2/}
  if [ ! -f "$source/$entry" ]; then
    printf 'MISSING\t%s\n' "$entry"
    exit 41
  fi
  archived=$(unzip -p "$archive" "$member" | sha256sum | cut -d ' ' -f 1)
  actual=$(sha256sum "$source/$entry" | cut -d ' ' -f 1)
  if [ "$archived" != "$actual" ]; then
    printf 'MISMATCH\t%s\n' "$entry"
    exit 42
  fi
  printf '%s\t%s\n' "$entry" "$actual"
done''';
  final result = await paths.runWithArgs(script, [
    _join(paths.root, _archive),
    _join(paths.root, _source),
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'source cache differs from pinned archive or unzip/sha256sum is unavailable '
      '(exit ${result.exitCode}): ${result.stdout}${result.stderr}',
    );
  }
  final hashes = <String, String>{};
  for (final line in const LineSplitter().convert(result.stdout as String)) {
    if (line.isEmpty) continue;
    final fields = line.split('\t');
    if (fields.length != 2 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fields[1])) {
      throw FormatException('invalid source inventory from archive verifier: $line');
    }
    hashes[fields[0]] = fields[1];
  }
  if (hashes.isEmpty) throw StateError('pinned source archive contains no files');
  return hashes;
}

String _join(String root, String relative) =>
    '${root.replaceAll(RegExp(r'[/\\]+$'), '')}/$relative';

Future<bool> _cacheMatches(
  File manifestFile,
  _NativePaths paths,
  String root,
  String compiler,
  Map<String, String> sourceHashes,
  String driverHash,
) async {
  if (!manifestFile.existsSync()) return false;
  try {
    final value = jsonDecode(await manifestFile.readAsString());
    if (value is! Map<String, dynamic> ||
        value['format'] != _format ||
        value['version'] != _version ||
        value['commit'] != _commit ||
        value['archiveSha256'] != _archiveHash ||
        value['sourceRoot'] != _source ||
        value['modulesRoot'] != '$_source/tests/modules' ||
        value['compiler'] != compiler ||
        jsonEncode(value['configureFlags']) != jsonEncode(_configureFlags) ||
        jsonEncode(value['sourceHashes']) != jsonEncode(sourceHashes)) {
      return false;
    }
    final artifacts = value['artifacts'];
    if (artifacts is! Map<String, dynamic>) return false;
    for (final entry in <String, String>{
      'jq': _cli,
      'driver': _driver,
      'library': _library,
      'driverSource': _driverSource,
    }.entries) {
      final artifact = artifacts[entry.key];
      if (artifact is! Map<String, dynamic> || artifact['path'] != entry.value) return false;
      final current = await _requiredArtifactHash(paths, root, entry.value);
      if (artifact['sha256'] != current) return false;
    }
    if (artifacts['driverSource'] is! Map<String, dynamic> ||
        (artifacts['driverSource'] as Map<String, dynamic>)['sha256'] != driverHash) {
      return false;
    }
    return true;
  } on Object {
    return false;
  }
}

void _refuseUnownedBuildOutputs(String root, File manifestFile) {
  if (manifestFile.existsSync()) {
    throw StateError(
      'existing native manifest is stale; refusing to overwrite its build outputs',
    );
  }
  for (final path in <String>[
    '.dart_tool/reference/build-jq-1.8.2',
    '$_manifest.tmp',
    '$_source/Makefile',
    '$_source/config.status',
    '$_source/config.log',
    '$_source/jq',
    _library,
    _driver,
  ]) {
    if (File('$root${Platform.pathSeparator}$path').existsSync()) {
      throw StateError('unowned build output exists; refusing to overwrite: $path');
    }
  }
}

Future<void> _runBuild(_NativePaths paths, String sourcePath, String rootPath) async {
  final wslSource = paths.windows ? await _wslPath(sourcePath) : sourcePath;
  final wslRoot = paths.windows ? paths.root : rootPath;
  const buildRelative = '.dart_tool/reference/build-jq-1.8.2';
  final buildPath = _join(wslRoot, buildRelative);
  await paths.checkedRun(r'mkdir -- "$1"', [buildPath], 'native build directory creation');
  final config = r'cd -- "$1" && env -i PATH=/usr/bin:/bin LC_ALL=C '
      r'"$2/configure" '
      '${_configureFlags.join(' ')}';
  await paths.checkedRun(config, [buildPath, wslSource], 'jq configure');
  await paths.checkedRun(
    r'cd -- "$1" && env -i PATH=/usr/bin:/bin LC_ALL=C make -j4',
    [buildPath],
    'jq and libjq build',
  );
  final version = await paths.runWithArgs(r'"$1/jq" --version', [buildPath]);
  if (version.exitCode != 0 || (version.stdout as String).trim() != _version) {
    throw StateError(
      'built jq reported ${(version.stdout as String).trim()} instead of $_version',
    );
  }
  const driverCompile = r'cd -- "$1" && env -i PATH=/usr/bin:/bin LC_ALL=C '
      r'gcc -std=c11 -O2 -Wall -Wextra -pthread -I"$2/src" -I"$2/vendor" '
      r'"$3" -o reference_capture .libs/libjq.a '
      r'vendor/oniguruma/src/.libs/libonig.a -lm -ldl -pthread';
  await paths.checkedRun(
    driverCompile,
    [buildPath, wslSource, _join(wslRoot, _driverSource)],
    'native reference driver build',
  );
  const install = r'install -m 755 "$1/jq" "$2/jq" && '
      r'mkdir -p -- "$2/.libs" && '
      r'install -m 644 "$1/.libs/libjq.a" "$2/.libs/libjq.a" && '
      r'install -m 755 "$1/reference_capture" "$3"';
  await paths.checkedRun(
    install,
    [
      buildPath,
      _join(wslRoot, _source),
      _join(wslRoot, _driver),
    ],
    'native artifact installation',
  );
}

Future<String> _requiredArtifactHash(
  _NativePaths paths,
  String projectRoot,
  String relative,
) async {
  final file = File('$projectRoot${Platform.pathSeparator}$relative');
  if (!file.existsSync()) throw StateError('native build did not produce $relative');
  return _fileHash(paths, relative);
}

Future<String> _fileHash(_NativePaths paths, String relative) async {
  final result = await paths.runWithArgs(r'sha256sum -- "$1"', [
    _join(paths.root, relative),
  ]);
  if (result.exitCode != 0) {
    throw StateError('sha256sum failed for $relative: ${result.stderr}');
  }
  final fields = (result.stdout as String).trim().split(RegExp(r'\s+'));
  if (fields.isEmpty || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fields.first)) {
    throw FormatException('invalid SHA-256 output for $relative');
  }
  return fields.first;
}

Future<void> _publishManifest(File manifest, String contents) async {
  final temporary = File('${manifest.path}.tmp');
  if (temporary.existsSync()) {
    throw StateError('unexpected temporary manifest exists: ${temporary.path}');
  }
  try {
    await temporary.writeAsString('$contents\n', flush: true);
    await temporary.rename(manifest.path);
  } on Object {
    if (temporary.existsSync()) await temporary.delete();
    rethrow;
  }
}

class _NativePaths {
  const _NativePaths({
    required this.windows,
    required this.root,
  });

  final bool windows;
  final String root;

  Future<ProcessResult> run(String script) => runWithArgs(script, const []);

  Future<ProcessResult> runWithArgs(String script, List<String> arguments) async {
    final result = await Process.run(
      windows ? 'wsl.exe' : 'bash',
      windows
          ? ['--exec', 'bash', '-c', script, 'reference-setup', ...arguments]
          : ['-c', script, 'reference-setup', ...arguments],
    );
    return result;
  }

  Future<void> checkedRun(String script, List<String> arguments, String label) async {
    stderr.writeln('Running $label...');
    final result = await runWithArgs(script, arguments);
    final out = result.stdout as String;
    final err = result.stderr as String;
    if (out.isNotEmpty) stderr.write(out);
    if (err.isNotEmpty) stderr.write(err);
    if (result.exitCode != 0) {
      throw StateError('$label failed with exit code ${result.exitCode}');
    }
  }
}
