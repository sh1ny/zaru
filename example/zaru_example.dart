// A runnable tour of the core engine: compile once, run many times, stream
// results lazily, pass external variables, and read jq errors.
//
// Run it with `mise run example`.
import 'package:zaru/zaru.dart';

void main() {
  // 1. Compile once; the filter is immutable and reusable.
  final names = Zaru.compile('.items[] | select(.active) | .name');

  // 2. runJson keeps every number exactly as written in the JSON text.
  const text =
      '{"items":[{"name":"ann","active":true},'
      '{"name":"bob","active":false},{"name":"cy","active":true}]}';
  print('active names: ${names.runJson(text).toList()}');

  // 3. run takes ordinary Dart values (null, bool, String, num, List, Map).
  final native = {
    'items': [
      {'name': 'dee', 'active': 1},
    ],
  };
  print('native input: ${names.run(native).toList()}');

  // 4. Results are lazy: only what you pull is evaluated.
  final forever = Zaru.compile('(1, 2, 3) | if . == 3 then error("boom") else . end');
  print('first two (no error yet): ${forever.run(null).take(2).toList()}');

  // 5. A jq error is raised after the results that precede it.
  try {
    forever.run(null).toList();
  } on ZaruRuntimeError catch (error) {
    print('runtime error: ${error.message}');
  }

  // 6. try/catch and the alternative operator behave as in jq.
  final safe = Zaru.compile(r'[.[] | try error("bad \(.)") catch .]');
  print('caught: ${Zaru.toJson(safe.run([1, 2]).single)}');
  print('alternative: ${Zaru.toJson(Zaru.compile('.a // "none"').run({}).single)}');

  // 6b. Definitions, reduce, foreach, destructuring and label/break run too.
  final tally = Zaru.compile(
    r'def total(f): reduce .[] as $x (0; . + ($x | f)); '
    r'[total(.a), (foreach .[] as {a: $a} (0; . + $a)), '
    r'(label $stop | .[] | if .a > 1 then break $stop else .a end)]',
  );
  print(
    'definitions and loops: '
    '${Zaru.toJson(tally.run([{'a': 1}, {'a': 2}, {'a': 3}]).single)}',
  );

  // 6c. The jq-coded helpers (range, limit, first, recurse, repeat, ...) are
  // jq's own definitions, and stay lazy: a huge generator is fine as long as
  // only a prefix is pulled.
  final prefix = Zaru.compile('[limit(5; range(0; 1e18; 3))]');
  print('huge range prefix: ${Zaru.toJson(prefix.run(null).single)}');
  final descent = Zaru.compile('[.. | select(. == 2)]');
  print('recursive descent: ${Zaru.toJson(descent.run([1, [2, {'a': 2}]]).single)}');
  final million = Zaru.compile(r'last(range(0; 1000000; 1))');
  print('a million-step recursion: ${Zaru.toJson(million.run(null).single)}');

  // 7. Declare external variables at compile time; bind them for each run.
  final above = Zaru.compile(r'[.[] | select(. > $min)]', variables: {'min'});
  print('above 1: ${Zaru.toJson(above.run([1, 2, 3], args: {'min': 1}).single)}');
  print('above 2: ${Zaru.toJson(above.run([1, 2, 3], args: {'min': 2}).single)}');

  // 8. Large and high-precision numbers survive when they come from JSON text.
  final id = Zaru.compile('.id');
  print('exact id: ${Zaru.toJson(id.runJson('{"id":12345678909876543212345}').single)}');

  // 9. Invalid source is a compile-time error with jq's diagnostics.
  try {
    Zaru.compile('. as [] | null');
  } on ZaruCompileError catch (error) {
    print('compile error at line ${error.line}, column ${error.col}:');
    print(error.diagnostics.first);
  }

  // 10. Valid jq that this release does not implement is reported distinctly.
  try {
    Zaru.compile('map(. + 1)');
  } on ZaruCompileError catch (error) {
    print('unsupported (not a jq error): ${error.isUnsupported}');
  }
}
