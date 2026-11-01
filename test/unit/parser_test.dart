import 'package:test/test.dart';
import 'package:zaru/src/syntax/ast.dart';
import 'package:zaru/src/syntax/parse_result.dart';
import 'package:zaru/src/syntax/parser.dart';
import 'package:zaru/src/syntax/span.dart';

import 'syntax_support.dart';

/// Parses [source], requires success and returns the program.
Program program(String source) {
  final result = parseProgram(source);
  expect(
    result.diagnostics,
    isEmpty,
    reason: 'unexpected diagnostics for $source',
  );
  return result.program!;
}

/// The S-expression of the main body of [source].
String ast(String source) => show(program(source).body);

List<UnsupportedKind> unsupported(String source) => [
  for (final construct in parseProgram(source).unsupported) construct.kind,
];

void main() {
  group('binary operator precedence and associativity', () {
    test('multiplicative binds tighter than additive', () {
      expect(ast('1 + 2 * 3'), '(+ 1 (* 2 3))');
      expect(ast('1 * 2 + 3'), '(+ (* 1 2) 3)');
      expect(ast('1 % 2 + 3 / 4'), '(+ (% 1 2) (/ 3 4))');
    });

    test('additive and multiplicative operators are left associative', () {
      expect(ast('1 - 2 - 3'), '(- (- 1 2) 3)');
      expect(ast('8 / 4 / 2'), '(/ (/ 8 4) 2)');
      expect(ast('1 - 2 + 3'), '(+ (- 1 2) 3)');
    });

    test('comparison binds looser than arithmetic and tighter than and', () {
      expect(ast('1 + 2 < 3 + 4'), '(< (+ 1 2) (+ 3 4))');
      expect(ast('1 == 2 and 3 >= 4'), '(and (== 1 2) (>= 3 4))');
      expect(ast('1 != 2 or 3 <= 4'), '(or (!= 1 2) (<= 3 4))');
    });

    test('and binds tighter than or, both left associative', () {
      expect(ast('1 or 2 and 3'), '(or 1 (and 2 3))');
      expect(ast('1 and 2 or 3'), '(or (and 1 2) 3)');
      expect(ast('1 or 2 or 3'), '(or (or 1 2) 3)');
      expect(ast('1 and 2 and 3'), '(and (and 1 2) 3)');
    });

    test('alternative is right associative and looser than assignment', () {
      expect(ast('1 // 2 // 3'), '(// 1 (// 2 3))');
      expect(ast('.a = 1 // 2'), '(// (= (index . "a") 1) 2)');
      expect(ast('.a // .b = 1'), '(// (index . "a") (= (index . "b") 1))');
      expect(ast('1 // 2 or 3'), '(// 1 (or 2 3))');
    });

    test('pipe is right associative and looser than comma', () {
      expect(ast('1 | 2 | 3'), '(| 1 (| 2 3))');
      expect(ast('1, 2, 3'), '(, (, 1 2) 3)');
      expect(ast('1 | 2, 3'), '(| 1 (, 2 3))');
      expect(ast('1, 2 | 3'), '(| (, 1 2) 3)');
    });

    test('unary minus applies to the whole postfix term', () {
      expect(ast('-1 + 2'), '(+ (neg 1) 2)');
      expect(ast('- - 1'), '(neg (neg 1))');
      expect(ast('-.a.b'), '(neg (index (index . "a") "b"))');
      expect(ast('-(1 + 2)'), '(neg (+ 1 2))');
    });

    test('assignment operators parse as non-associative infix forms', () {
      expect(ast('.a |= . + 1'), '(|= (index . "a") (+ . 1))');
      expect(ast('.a += 1'), '(+= (index . "a") 1)');
      expect(ast('.a //= 1'), '(//= (index . "a") 1)');
      expect(ast('.a %= 2'), '(%= (index . "a") 2)');
    });
  });

  group('binding forms swallow everything to their right', () {
    test('as-binding body extends over pipes and commas', () {
      expect(ast('1 as \$x | 2 | 3'), '(as 1 <\$x> (| 2 3))');
      expect(ast('1 as \$x | \$x, 3'), '(as 1 <\$x> (, \$x 3))');
    });

    test('the source of as is a whole Expr, not just a term', () {
      expect(ast('1 + 2 as \$x | \$x'), '(as (+ 1 2) <\$x> \$x)');
    });

    test('a binding after a comma belongs to the right operand', () {
      expect(ast('1, 2 as \$x | \$x, 3'), '(, 1 (as 2 <\$x> (, \$x 3)))');
    });

    test('chained bindings nest', () {
      expect(
        ast('1 as \$x | 2 as \$y | [\$x, \$y]'),
        '(as 1 <\$x> (as 2 <\$y> (array (, \$x \$y))))',
      );
    });

    test('label scopes over the rest of the query', () {
      expect(
        ast('label \$out | 1, break \$out'),
        '(label \$out (, 1 (break \$out)))',
      );
    });
  });

  group('postfix terms', () {
    test('field, index, slice and iterate chains', () {
      expect(ast('.a.b'), '(index (index . "a") "b")');
      expect(ast('.a[0]'), '(index (index . "a") 0)');
      expect(ast('.[]'), '(each .)');
      expect(ast('.[1:2]'), '(slice . 1 2)');
      expect(ast('.[:2]'), '(slice . _ 2)');
      expect(ast('.[1:]'), '(slice . 1 _)');
      expect(ast('.a[]'), '(each (index . "a"))');
    });

    test('optional forms use the index-optional node, not a general try', () {
      expect(ast('.a?'), '(index? . "a")');
      expect(ast('.a.b?'), '(index? (index . "a") "b")');
      expect(ast('.[0]?'), '(index? . 0)');
      expect(ast('.[]?'), '(each? .)');
      expect(ast('.[1:2]?'), '(slice? . 1 2)');
    });

    test('a generic postfix question mark is a try without handler', () {
      expect(ast('1 ?'), '(? 1)');
      expect(ast('..?'), '(? ..)');
      expect(ast('.a??'), '(? (index? . "a"))');
      expect(ast('.[]??'), '(? (each? .))');
    });

    test('dotted string and bracket keys', () {
      expect(ast('."a"'), '(index . "a")');
      expect(ast('.a."b"?'), '(index? (index . "a") "b")');
      expect(ast('."a\\(1)"'), '(index . (str "a" \\(1)))');
      expect(ast('.a.[1]'), '(index (index . "a") 1)');
      expect(ast('.a.[]'), '(each (index . "a"))');
      expect(ast('.a.[1]?'), '(index? (index . "a") 1)');
    });

    test('whitespace may separate a term from its postfix', () {
      expect(ast('.a .b'), '(index (index . "a") "b")');
      expect(ast('[1] [2]'), '(index (array 1) 2)');
    });

    test('reserved words are valid field names', () {
      expect(ast('.if'), '(index . "if")');
      expect(ast('.and.or'), '(index (index . "and") "or")');
      expect(ast('.then?'), '(index? . "then")');
    });

    test('a parenthesised query is a term for postfix purposes', () {
      expect(ast('(1, 2)[0]'), '(index (, 1 2) 0)');
    });
  });

  group('try, if, reduce and foreach', () {
    test('try takes a single postfix term, catch likewise', () {
      expect(ast('try error catch .'), '(try error .)');
      expect(ast('try 1 + 2'), '(+ (try 1) 2)');
      expect(ast('try .a.b'), '(try (index (index . "a") "b"))');
      expect(ast('try error("x") catch . | 1'), '(| (try (error "x") .) 1)');
      expect(ast('try (try error catch .) catch .'), '(try (try error .) .)');
    });

    test('if with optional else and elif chains', () {
      expect(ast('if . then 1 end'), '(if . 1)');
      expect(ast('if . then 1 else 2 end'), '(if . 1 2)');
      expect(
        ast('if a then 1 elif b then 2 else 3 end'),
        '(if a 1 (if b 2 3))',
      );
      expect(ast('if a then 1 elif b then 2 end'), '(if a 1 (if b 2))');
      expect(
        ast('if . then 1 elif . then 2 elif . then 3 else 4 end'),
        '(if . 1 (if . 2 (if . 3 4)))',
      );
    });

    test('if branches are full queries', () {
      expect(
        ast('if 1, 2 then 3 | 4 else 5, 6 end'),
        '(if (, 1 2) (| 3 4) (, 5 6))',
      );
    });

    test('reduce has exactly init and update', () {
      expect(
        ast('reduce .[] as \$x (0; . + \$x)'),
        '(reduce (each .) <\$x> 0 (+ . \$x))',
      );
    });

    test('foreach has two or three arguments', () {
      expect(
        ast('foreach .[] as \$x (0; . + \$x)'),
        '(foreach (each .) <\$x> 0 (+ . \$x))',
      );
      expect(
        ast('foreach .[] as \$x (0; . + \$x; [\$x, .])'),
        '(foreach (each .) <\$x> 0 (+ . \$x) (array (, \$x .)))',
      );
    });

    test('reduce source is a full expression', () {
      expect(
        ast('reduce range(0; 3) as \$i (0; . + \$i)'),
        '(reduce (range 0 3) <\$i> 0 (+ . \$i))',
      );
      expect(ast('reduce 1 + 2 as \$i (0; .)'), '(reduce (+ 1 2) <\$i> 0 .)');
    });
  });

  group('definitions', () {
    test('a definition scopes over the rest of the query', () {
      expect(ast('def f: 1; f | g'), '(def f () 1) (| f g)');
    });

    test('filter and value parameters', () {
      expect(ast('def f(a; \$b): a; f(1; 2)'), '(def f (a \$b) a) (f 1 2)');
    });

    test('nested definitions', () {
      expect(ast('def f: def g: 1; g; f'), '(def f () (def g () 1) g) f');
    });

    test('a definition inside a comma operand', () {
      expect(ast('1, def f: 2; f'), '(, 1 (def f () 2) f)');
    });

    test('a definitions-only program has no body', () {
      final p = program('def f: 1; def g: 2;');
      expect(p.body, isNull);
      expect([for (final d in p.definitions) d.name], ['f', 'g']);
    });

    test('an empty or comment-only program is valid and has no body', () {
      expect(program('').body, isNull);
      expect(program('  # nothing here\n').body, isNull);
    });
  });

  group('constructors', () {
    test('arrays', () {
      expect(ast('[]'), '(array)');
      expect(ast('[1, 2]'), '(array (, 1 2))');
      expect(ast('[.[] | f]'), '(array (| (each .) f))');
    });

    test('object shorthand and explicit keys', () {
      expect(ast('{}'), '(object)');
      expect(ast('{a}'), '(object ("a" (index . "a")))');
      expect(ast('{a: 1}'), '(object ("a" 1))');
      expect(ast('{"a"}'), '(object ("a" (index . "a")))');
      expect(ast('{\$x}'), '(object ("x" \$x))');
      expect(ast('{\$x: 1}'), '(object (\$x 1))');
      expect(ast('{(.k): 1}'), '(object ((index . "k") 1))');
      expect(ast('{"a": 1, "b": 2}'), '(object ("a" 1) ("b" 2))');
    });

    test('keywords are valid unparenthesised keys and shorthands', () {
      expect(ast('{if: 1, then: 2}'), '(object ("if" 1) ("then" 2))');
      expect(ast('{if}'), '(object ("if" (index . "if")))');
      expect(
        ast('{and, or}'),
        '(object ("and" (index . "and")) ("or" (index . "or")))',
      );
    });

    test('object values may be piped but not comma separated', () {
      expect(ast('{a: 1 | 2}'), '(object ("a" (| 1 2)))');
      expect(
        ast('{a: 1, b: 2 | 3, c}'),
        '(object ("a" 1) ("b" (| 2 3)) ("c" (index . "c")))',
      );
    });

    test('literals true false null are identifiers parsed as constants', () {
      expect(ast('[null, true, false]'), '(array (, (, null true) false))');
    });

    test('a constant string key keeps its text', () {
      final body = program('{"a": 1}').body as ObjectConstructor;
      expect((body.entries.single.key as StringLiteral).constantValue, 'a');
    });
  });

  group('strings', () {
    test('constant and empty', () {
      expect(ast('"abc"'), '"abc"');
      expect(ast('""'), '""');
    });

    test('escapes are decoded', () {
      final body = program(r'"a\tb\né"').body as StringLiteral;
      expect(body.constantValue, 'a\tb\né');
    });

    test('interpolation and nesting', () {
      expect(ast(r'"a\(1)b"'), '(str "a" \\(1) "b")');
      expect(ast(r'"\("x\(.)")"'), '(str \\((str "x" \\(.))))');
      expect(ast(r'"\(1, 2 | 3)"'), '(str \\((| (, 1 2) 3)))');
    });

    test('a format prefix is kept on the string', () {
      expect(ast(r'@base64 "x\(1)"'), '(str @base64 "x" \\(1))');
    });
  });

  group('destructuring', () {
    test('array, object and alternative patterns', () {
      expect(
        ast(r'. as [$a, [$b, {c: $d}]] ?// {e: $f} | $a'),
        r'(as . <[$a [$b {"c": $d}]] ?// {"e": $f}> $a)',
      );
    });

    test('object pattern key forms', () {
      expect(
        ast(r'. as {$a, $b: [$c], d: $e, "f": $g, (h): $i, if: $j} | 1'),
        r'(as . <{$a="a" $b="b": [$c] "d": $e "f": $g h: $i "if": $j}> 1)',
      );
    });

    test('reduce and foreach accept alternatives', () {
      expect(
        ast(r'reduce .[] as [$a] ?// $a (0; .)'),
        r'(reduce (each .) <[$a] ?// $a> 0 .)',
      );
    });
  });

  group('names', () {
    test('calls', () {
      expect(ast('f'), 'f');
      expect(ast('f(1; 2)'), '(f 1 2)');
      expect(ast('f(1, 2)'), '(f (, 1 2))');
      expect(ast('f(g | h; 3)'), '(f (| g h) 3)');
    });

    test('variables, including the private load form', () {
      expect(ast(r'$x'), r'$x');
      expect(ast(r'$$$$x'), r'$$$$x');
    });

    test('numbers keep the original lexeme', () {
      expect(
        ast('[1, 1.0, 1e3, 100000000000000000000, .5]'),
        '(array (, (, (, (, 1 1.0) 1e3) 100000000000000000000) .5))',
      );
    });
  });

  group('source spans', () {
    test('spans are UTF-8 byte ranges with exclusive ends', () {
      final body = program('1 + 2').body!;
      expect(body.span, const Span(0, 5));
      final tree = program('"é" | .a').body as Pipe;
      expect(tree.span, const Span(0, 9));
      expect(tree.left.span, const Span(0, 4));
      expect(tree.right.span, const Span(7, 9));
    });

    test('supplementary-plane text counts four bytes', () {
      final tree = program('"😀" | .').body as Pipe;
      expect(tree.left.span, const Span(0, 6));
      expect(tree.right.span, const Span(9, 10));
    });

    test('a parenthesised query keeps its parentheses in the span', () {
      final tree = program('(1 + 2) * 3').body as Binary;
      expect(tree.left, isA<Group>());
      expect(tree.left.span, const Span(0, 7));
      expect(tree.span, const Span(0, 11));
    });

    test('postfix chains cover the whole chain', () {
      final body = program('.a.b[0]?').body!;
      expect(body.span, const Span(0, 8));
    });

    test('definitions cover their text through the end of the rest', () {
      final body = program('def f: 1; f').body as DefineIn;
      expect(body.span, const Span(0, 11));
      expect(body.definition.span, const Span(0, 9));
    });
  });

  group('deferred syntax is recognised, not evaluated', () {
    test('format filters and format-prefixed strings', () {
      expect(unsupported('@base64'), [UnsupportedKind.format]);
      expect(unsupported(r'@base64 "x\(1)"'), [UnsupportedKind.format]);
      expect(show(program('@base64').body), '(fmt base64)');
    });

    test('assignment and update operators', () {
      expect(unsupported('.a = 1'), [UnsupportedKind.assignment]);
      expect(unsupported('.a |= 1'), [UnsupportedKind.assignment]);
      expect(unsupported('.a //= 1'), [UnsupportedKind.assignment]);
      final result = parseProgram('.a += 1');
      expect(result.unsupported.single.detail, '+=');
      expect(result.unsupported.single.span, const Span(3, 5));
    });

    test('location binding', () {
      expect(unsupported(r'$__loc__'), [UnsupportedKind.locationBinding]);
      expect(unsupported(r'{$__loc__}'), [UnsupportedKind.locationBinding]);
    });

    test('module directives are parsed into the program', () {
      final source = 'module {a: 1}; import "m" as m; include "n"; .';
      final result = parseProgram(source);
      expect(result.diagnostics, isEmpty);
      expect(result.unsupported.map((u) => u.kind), [
        UnsupportedKind.moduleDirective,
        UnsupportedKind.importDirective,
        UnsupportedKind.includeDirective,
      ]);
      final p = result.program!;
      expect(p.module, isNotNull);
      expect(p.imports.map((i) => (i.alias, i.isData, i.isInclude)), [
        ('m', false, false),
        (null, false, true),
      ]);
      expect(show(p.body), '.');
    });

    test('data imports bind a variable name', () {
      final p = program(r'import "d" as $d; $d');
      expect(p.imports.single.alias, 'd');
      expect(p.imports.single.isData, isTrue);
    });

    test('qualified names', () {
      expect(unsupported('a::b'), [UnsupportedKind.qualifiedName]);
      expect(unsupported(r'$a::b'), [UnsupportedKind.qualifiedName]);
      expect(unsupported('f(1)'), isEmpty);
    });

    test('unsupported syntax never becomes a jq diagnostic', () {
      final result = parseProgram('@base64 | .a = 1');
      expect(result.diagnostics, isEmpty);
      expect(result.isValid, isTrue);
      expect(result.report, isNull);
      expect(result.unsupported, hasLength(2));
    });
  });
}
