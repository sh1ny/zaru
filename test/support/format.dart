import 'dart:io';

Future<void> main(List<String> arguments) async {
  final check = arguments.contains('--check');
  if (arguments.any((argument) => argument != '--check')) {
    stderr.writeln('Usage: mise run format [--check]');
    exitCode = 2;
    return;
  }
  final result = await Process.start(Platform.resolvedExecutable, [
    'format',
    if (check) ...['--output=none', '--set-exit-if-changed'],
    'lib',
    'bin',
    'test',
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await result.exitCode;
}
