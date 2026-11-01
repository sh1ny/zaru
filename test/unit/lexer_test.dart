import 'package:test/test.dart';
import 'package:zaru/src/syntax/diagnostic.dart';
import 'package:zaru/src/syntax/lexer.dart';
import 'package:zaru/src/syntax/span.dart';
import 'package:zaru/src/syntax/token.dart';

/// Expands `@u` to a backslash followed by `u`, so that this file never
/// contains a literal unicode escape in a place where tooling might decode it.
String esc(String s) => s.replaceAll('@u', r'\u');

List<TokenKind> kinds(String source) => [
  for (final token in lex(source).tokens) token.kind,
];

List<String> labels(String source) => [
  for (final token in lex(source).tokens)
    '${token.kind.name}@${token.span.start}-${token.span.end}',
];

void main() {
  group('spans', () {
    test('token spans are UTF-8 byte ranges with exclusive ends', () {
      expect(labels('.a | .b'), [
        'field@0-2',
        'pipe@3-4',
        'field@5-7',
        'eof@5-7',
      ]);
    });

    test('multi-byte text widens spans by bytes, not UTF-16 units', () {
      // U+00E9 is two bytes; U+1F600 is four bytes (two UTF-16 units).
      final result = lex('"é😀" | .');
      expect(
        [for (final t in result.tokens) (t.kind, t.span.start, t.span.end)],
        [
          (TokenKind.stringStart, 0, 1),
          (TokenKind.stringText, 1, 7),
          (TokenKind.stringEnd, 7, 8),
          (TokenKind.pipe, 9, 10),
          (TokenKind.dot, 11, 12),
          (TokenKind.eof, 11, 12),
        ],
      );
      expect(result.tokens[1].value, 'é😀');
    });

    test('line breaks keep absolute byte offsets', () {
      expect(labels('1\n  +\r\n2'), [
        'literal@0-1',
        'plus@4-5',
        'literal@7-8',
        'eof@7-8',
      ]);
    });
  });

  group('longest match and rule order', () {
    test('multi-character operators win over their prefixes', () {
      expect(
        kinds(
          '//= // / /= ?// ? |= | == = != <= >= < > .. . %= % += + -= - *= *',
        ),
        [
          TokenKind.setDefinedOr,
          TokenKind.definedOr,
          TokenKind.slash,
          TokenKind.setDiv,
          TokenKind.alternation,
          TokenKind.question,
          TokenKind.setPipe,
          TokenKind.pipe,
          TokenKind.eq,
          TokenKind.assign,
          TokenKind.neq,
          TokenKind.lessEq,
          TokenKind.greaterEq,
          TokenKind.less,
          TokenKind.greater,
          TokenKind.recurse,
          TokenKind.dot,
          TokenKind.setMod,
          TokenKind.percent,
          TokenKind.setPlus,
          TokenKind.plus,
          TokenKind.setMinus,
          TokenKind.minus,
          TokenKind.setMult,
          TokenKind.star,
          TokenKind.eof,
        ],
      );
    });

    test('alternation is lexed greedily even without spaces', () {
      expect(kinds('.a?//1'), [
        TokenKind.field,
        TokenKind.alternation,
        TokenKind.literal,
        TokenKind.eof,
      ]);
    });

    test('numbers keep their original lexeme', () {
      final tokens = lex(
        '12345678909876543212345 1.0 .5 1. 1e3 1.e+3 01 1e',
      ).tokens;
      expect(
        [
          for (final t in tokens)
            if (t.kind == TokenKind.literal) t.text,
        ],
        [
          '12345678909876543212345',
          '1.0',
          '.5',
          '1.',
          '1e3',
          '1.e+3',
          '01',
          '1',
        ],
      );
      // The trailing "e" is not part of a number without exponent digits.
      expect(tokens[tokens.length - 2].kind, TokenKind.ident);
    });

    test('fields, identifiers, bindings, formats and keywords', () {
      final tokens = lex(
        r'.foo .if if iffy a::b::c $x $a::b $__loc__ $__loc__x @base64',
      ).tokens;
      expect(
        [for (final t in tokens) '${t.kind.name}:${t.text}'],
        [
          'field:foo',
          'field:if',
          'ifKeyword:',
          'ident:iffy',
          'ident:a::b::c',
          'binding:x',
          'binding:a::b',
          'loc:',
          'binding:__loc__x',
          'format:base64',
          'eof:',
        ],
      );
    });

    test('a dangling :: is two colons, not part of the identifier', () {
      expect(kinds('a::'), [
        TokenKind.ident,
        TokenKind.colon,
        TokenKind.colon,
        TokenKind.eof,
      ]);
    });

    test('lone special characters are invalid characters', () {
      expect(kinds('! @ & `'), [
        TokenKind.invalidCharacter,
        TokenKind.invalidCharacter,
        TokenKind.invalidCharacter,
        TokenKind.invalidCharacter,
        TokenKind.eof,
      ]);
    });

    test('each byte of an unexpected multi-byte character is invalid', () {
      expect(labels('é'), [
        'invalidCharacter@0-1',
        'invalidCharacter@1-2',
        'eof@1-2',
      ]);
    });
  });

  group('delimiters', () {
    test('closers must match the innermost opener', () {
      expect(kinds('( ] ) ] }'), [
        TokenKind.leftParen,
        TokenKind.invalidCharacter,
        TokenKind.rightParen,
        TokenKind.invalidCharacter,
        TokenKind.invalidCharacter,
        TokenKind.eof,
      ]);
    });

    test('an unmatched closer does not pop', () {
      expect(kinds('[ ) ]'), [
        TokenKind.leftBracket,
        TokenKind.invalidCharacter,
        TokenKind.rightBracket,
        TokenKind.eof,
      ]);
    });

    test('closers with no opener are invalid', () {
      expect(kinds(') ] }'), [
        TokenKind.invalidCharacter,
        TokenKind.invalidCharacter,
        TokenKind.invalidCharacter,
        TokenKind.eof,
      ]);
    });
  });

  group('comments', () {
    test('a comment runs to the end of the line', () {
      expect(kinds('1 # one\n2'), [
        TokenKind.literal,
        TokenKind.literal,
        TokenKind.eof,
      ]);
    });

    test('an odd number of backslashes continues the comment', () {
      // The backslash-newline pair is part of the comment, so `2` stays in it.
      expect(kinds('1 # one \\\n 2\n3'), [
        TokenKind.literal,
        TokenKind.literal,
        TokenKind.eof,
      ]);
      expect(lex('1 # one \\\n 2\n3').tokens[1].text, '3');
    });

    test('an escaped backslash does not continue the comment', () {
      expect(lex('1 # one \\\\\n2').tokens[1].text, '2');
    });

    test('CRLF after a continuation backslash continues the comment', () {
      expect(lex('1 # a \\\r\n 2\r\n3').tokens[1].text, '3');
    });

    test('hash inside a string is text', () {
      final tokens = lex('"a#b"').tokens;
      expect(tokens[1].value, 'a#b');
    });
  });

  group('end-of-file location', () {
    test('reuses the span of the last matched rule', () {
      expect(lex('1 +').tokens.last.span, const Span(2, 3));
    });

    test('trailing whitespace is the last matched rule', () {
      expect(lex('1 +  ').tokens.last.span, const Span(3, 5));
    });

    test('each comment character is its own match', () {
      expect(lex('1 + # foo').tokens.last.span, const Span(8, 9));
    });

    test('a continuation backslash piece is the last match', () {
      expect(lex('1 + # foo\\').tokens.last.span, const Span(9, 10));
    });

    test('an unterminated string ends at its last piece', () {
      expect(lex('"abc').tokens.last.span, const Span(1, 4));
    });
  });

  group('strings', () {
    test('an escape run is decoded as one token', () {
      final tokens = lex(esc(r'"x\t@u00e9@ud83d@ude00y"')).tokens;
      expect(
        [
          for (final t in tokens)
            if (t.kind == TokenKind.stringText) t.value,
        ],
        [
          'x',
          '\t'
              '\u{e9}'
              '\u{1F600}',
          'y',
        ],
      );
    });

    test('an escaped backslash before parentheses is not interpolation', () {
      final tokens = lex(r'"\\(x)"').tokens;
      expect(
        [for (final t in tokens) t.kind],
        [
          TokenKind.stringStart,
          TokenKind.stringText,
          TokenKind.stringText,
          TokenKind.stringEnd,
          TokenKind.eof,
        ],
      );
      expect(tokens[1].value, r'\');
      expect(tokens[2].value, '(x)');
    });

    test('nested interpolation uses its own delimiter stack', () {
      expect(kinds(r'"a\(1 + "b\(2)c")d"'), [
        TokenKind.stringStart,
        TokenKind.stringText,
        TokenKind.interpStart,
        TokenKind.literal,
        TokenKind.plus,
        TokenKind.stringStart,
        TokenKind.stringText,
        TokenKind.interpStart,
        TokenKind.literal,
        TokenKind.interpEnd,
        TokenKind.stringText,
        TokenKind.stringEnd,
        TokenKind.interpEnd,
        TokenKind.stringText,
        TokenKind.stringEnd,
        TokenKind.eof,
      ]);
    });

    test('brackets inside an interpolation must balance before its close', () {
      expect(kinds(r'"\([1)]"'), [
        TokenKind.stringStart,
        TokenKind.interpStart,
        TokenKind.leftBracket,
        TokenKind.literal,
        TokenKind.invalidCharacter,
        TokenKind.rightBracket,
        // Still inside the interpolation, so the final quote opens a string.
        TokenKind.stringStart,
        TokenKind.eof,
      ]);
    });

    test('raw newlines and non-ASCII are text', () {
      final tokens = lex('"a\n€"').tokens;
      expect(tokens[1].value, 'a\n€');
    });

    test('a backslash at end of input is an invalid character', () {
      expect(kinds('"\\'), [
        TokenKind.stringStart,
        TokenKind.invalidCharacter,
        TokenKind.eof,
      ]);
    });
  });

  group('invalid escapes', () {
    test(r'Lexical diagnostic preserves span and message for "\v"', () {
      final result = lex(r'"u\vw"');
      expect(result.diagnostics, [
        const Diagnostic(
          DiagnosticKind.lexical,
          r'''Invalid escape at line 1, column 4 (while parsing '"\v"')''',
          Span(2, 4),
        ),
      ]);
      final text = result.tokens[2];
      expect(text.kind, TokenKind.stringText);
      expect(text.value, isNull);
      expect(text.span, const Span(2, 4));
    });

    test('jq JSON-string escape messages are reproduced', () {
      String message(String source) => lex(source).diagnostics.single.message;
      expect(
        message(r'"\x"'),
        r'''Invalid escape at line 1, column 4 (while parsing '"\x"')''',
      );
      expect(
        message(r'"\u12"'),
        r'''Invalid \uXXXX escape at line 1, column 6 (while parsing '"\u12"')''',
      );
      expect(
        message(r'"\uZZZZ"'),
        r'''Invalid characters in \uXXXX escape at line 1, column 8 (while parsing '"\uZZZZ"')''',
      );
      expect(
        message(r'"\ud800"'),
        r'''Invalid \uXXXX\uXXXX surrogate pair escape at line 1, column 8 (while parsing '"\ud800"')''',
      );
      expect(
        message(esc(r'"@ud800@u0041"')),
        esc(
          r'''Invalid @uXXXX@uXXXX surrogate pair escape at line 1, column 14 (while parsing '"@ud800@u0041"')''',
        ),
      );
    });

    test('a lone low surrogate becomes U+FFFD', () {
      final tokens = lex(esc(r'"@udc00"')).tokens;
      expect(tokens[1].value, '\u{FFFD}');
    });

    test('the JSON column restarts after an escaped newline', () {
      // `\<newline>` is an invalid escape; jq's JSON parser then reports the
      // position after the closing quote on its second line.
      final result = lex('"\\\nx"');
      expect(
        result.diagnostics.single.message,
        'Invalid escape at line 2, '
        'column 1 (while parsing \'"\\\n"\')',
      );
      expect(result.diagnostics.single.span, const Span(1, 3));
    });
  });
}
