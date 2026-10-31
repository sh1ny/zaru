import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length == 1 && arguments.single == '--version') {
    stdout.writeln('zaru-0.0.0');
    return;
  }
  stderr.writeln(
    'zaru: query execution is not available in M0; use --version.',
  );
  exitCode = 2;
}
