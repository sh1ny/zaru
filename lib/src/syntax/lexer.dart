import 'dart:convert';
import 'dart:typed_data';

import 'diagnostic.dart';
import 'source_text.dart';
import 'span.dart';
import 'token.dart';

enum _Mode { initial, paren, bracket, brace, interp, string }

/// A byte-level port of pinned jq 1.8.2's `lexer.l`.
///
/// Matching follows flex's longest-match rule with first-rule tie breaking,
/// the bracket/interpolation start-condition stack (an unmatched closing
/// delimiter is `INVALID_CHARACTER` and does not pop), Tcl-style backslash
/// comment continuation, and `\u` escape runs that are validated with the same
/// checks and messages as jq's JSON string parser.
///
/// Tokens carry UTF-8 byte spans. [lastPiece] mirrors flex's `yylloc` as seen
/// by Bison: the span of the most recent match of **any** rule (including
/// whitespace and each comment piece). The end-of-file token reuses it, which
/// is jq's EOF location convention.
final class Lexer {
  Lexer(this.source, this._report) : _bytes = source.bytes;

  final SourceText source;
  final void Function(Diagnostic) _report;
  final Uint8List _bytes;

  int _pos = 0;
  final List<_Mode> _modes = [_Mode.initial];

  /// The span of the most recently matched lexer rule.
  Span lastPiece = const Span(0, 0);

  _Mode get _mode => _modes.last;

  /// Returns the next token. After the input is exhausted every call returns
  /// an `eof` token whose span is [lastPiece].
  Token next() {
    while (true) {
      if (_pos >= _bytes.length) return Token(TokenKind.eof, lastPiece);
      if (_mode == _Mode.string) return _stringToken();
      final byte = _bytes[_pos];
      if (_isSpace(byte)) {
        final start = _pos;
        while (_pos < _bytes.length && _isSpace(_bytes[_pos])) {
          _pos++;
        }
        lastPiece = Span(start, _pos);
        continue;
      }
      if (byte == 0x23) {
        _comment();
        continue;
      }
      return _token(byte);
    }
  }

  static bool _isSpace(int b) =>
      b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d;
  static bool _isDigit(int b) => b >= 0x30 && b <= 0x39;
  static bool _isIdentStart(int b) =>
      (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a) || b == 0x5f;
  static bool _isIdentPart(int b) => _isIdentStart(b) || _isDigit(b);
  static bool _isAlnum(int b) =>
      _isDigit(b) || (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a);

  int _at(int index) => index < _bytes.length ? _bytes[index] : -1;

  void _piece(int start, int end) {
    lastPiece = Span(start, end);
    _pos = end;
  }

  /// `#` starts a comment. Each flex match inside the comment is one piece:
  /// `\\`, `\<newline>` (optionally `\r\n`) or any single non-newline byte.
  /// A bare newline ends the comment.
  void _comment() {
    _piece(_pos, _pos + 1);
    while (_pos < _bytes.length) {
      final b = _bytes[_pos];
      if (b == 0x5c) {
        final n = _at(_pos + 1);
        if (n == 0x5c || n == 0x0a) {
          _piece(_pos, _pos + 2);
        } else if (n == 0x0d && _at(_pos + 2) == 0x0a) {
          _piece(_pos, _pos + 3);
        } else {
          _piece(_pos, _pos + 1);
        }
      } else if (b == 0x0a) {
        _piece(_pos, _pos + 1);
        return;
      } else if (b == 0x0d && _at(_pos + 1) == 0x0a) {
        _piece(_pos, _pos + 2);
        return;
      } else {
        _piece(_pos, _pos + 1);
      }
    }
  }

  Token _make(TokenKind kind, int length, {String text = ''}) {
    final start = _pos;
    _piece(start, start + length);
    return Token(kind, Span(start, start + length), text: text);
  }

  Token _token(int byte) {
    final start = _pos;
    final next = _at(start + 1);
    final next2 = _at(start + 2);
    switch (byte) {
      case 0x22: // "
        _modes.add(_Mode.string);
        return _make(TokenKind.stringStart, 1);
      case 0x2e: // .
        if (next == 0x2e) return _make(TokenKind.recurse, 2);
        if (_isDigit(next)) return _number();
        if (_isIdentStart(next)) {
          var end = start + 2;
          while (_isIdentPart(_at(end))) {
            end++;
          }
          return _make(
            TokenKind.field,
            end - start,
            text: source.slice(start + 1, end),
          );
        }
        return _make(TokenKind.dot, 1);
      case 0x24: // $
        if (_isIdentStart(next)) {
          final end = _qualifiedIdentEnd(start + 1);
          final name = source.slice(start + 1, end);
          if (name == '__loc__') return _make(TokenKind.loc, end - start);
          return _make(TokenKind.binding, end - start, text: name);
        }
        return _make(TokenKind.dollar, 1);
      case 0x40: // @
        if (_isIdentPart(next)) {
          var end = start + 1;
          while (_isIdentPart(_at(end))) {
            end++;
          }
          return _make(
            TokenKind.format,
            end - start,
            text: source.slice(start + 1, end),
          );
        }
        return _make(TokenKind.invalidCharacter, 1);
      case 0x21: // !
        if (next == 0x3d) return _make(TokenKind.neq, 2);
        return _make(TokenKind.invalidCharacter, 1);
      case 0x3d: // =
        return next == 0x3d
            ? _make(TokenKind.eq, 2)
            : _make(TokenKind.assign, 1);
      case 0x2f: // /
        if (next == 0x2f) {
          return next2 == 0x3d
              ? _make(TokenKind.setDefinedOr, 3)
              : _make(TokenKind.definedOr, 2);
        }
        return next == 0x3d
            ? _make(TokenKind.setDiv, 2)
            : _make(TokenKind.slash, 1);
      case 0x7c: // |
        return next == 0x3d
            ? _make(TokenKind.setPipe, 2)
            : _make(TokenKind.pipe, 1);
      case 0x2b: // +
        return next == 0x3d
            ? _make(TokenKind.setPlus, 2)
            : _make(TokenKind.plus, 1);
      case 0x2d: // -
        return next == 0x3d
            ? _make(TokenKind.setMinus, 2)
            : _make(TokenKind.minus, 1);
      case 0x2a: // *
        return next == 0x3d
            ? _make(TokenKind.setMult, 2)
            : _make(TokenKind.star, 1);
      case 0x25: // %
        return next == 0x3d
            ? _make(TokenKind.setMod, 2)
            : _make(TokenKind.percent, 1);
      case 0x3c: // <
        return next == 0x3d
            ? _make(TokenKind.lessEq, 2)
            : _make(TokenKind.less, 1);
      case 0x3e: // >
        return next == 0x3d
            ? _make(TokenKind.greaterEq, 2)
            : _make(TokenKind.greater, 1);
      case 0x3f: // ?
        if (next == 0x2f && next2 == 0x2f) {
          return _make(TokenKind.alternation, 3);
        }
        return _make(TokenKind.question, 1);
      case 0x3b:
        return _make(TokenKind.semicolon, 1);
      case 0x2c:
        return _make(TokenKind.comma, 1);
      case 0x3a:
        return _make(TokenKind.colon, 1);
      case 0x28:
        _modes.add(_Mode.paren);
        return _make(TokenKind.leftParen, 1);
      case 0x5b:
        _modes.add(_Mode.bracket);
        return _make(TokenKind.leftBracket, 1);
      case 0x7b:
        _modes.add(_Mode.brace);
        return _make(TokenKind.leftBrace, 1);
      case 0x29:
        return _close(_Mode.paren, TokenKind.rightParen);
      case 0x5d:
        return _close(_Mode.bracket, TokenKind.rightBracket);
      case 0x7d:
        return _close(_Mode.brace, TokenKind.rightBrace);
    }
    if (_isDigit(byte)) return _number();
    if (_isIdentStart(byte)) {
      final end = _qualifiedIdentEnd(start);
      final text = source.slice(start, end);
      final keyword = _keywords[text];
      if (keyword != null) return _make(keyword, end - start);
      return _make(TokenKind.ident, end - start, text: text);
    }
    return _make(TokenKind.invalidCharacter, 1);
  }

  /// `([a-zA-Z_][a-zA-Z_0-9]*::)*[a-zA-Z_][a-zA-Z_0-9]*` from [start].
  int _qualifiedIdentEnd(int start) {
    var end = start;
    while (true) {
      while (_isIdentPart(_at(end))) {
        end++;
      }
      if (_at(end) == 0x3a &&
          _at(end + 1) == 0x3a &&
          _isIdentStart(_at(end + 2))) {
        end += 2;
      } else {
        return end;
      }
    }
  }

  /// `([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?`
  Token _number() {
    final start = _pos;
    var end = start;
    if (_at(end) == 0x2e) {
      end++;
      while (_isDigit(_at(end))) {
        end++;
      }
    } else {
      while (_isDigit(_at(end))) {
        end++;
      }
      if (_at(end) == 0x2e) {
        end++;
        while (_isDigit(_at(end))) {
          end++;
        }
      }
    }
    final e = _at(end);
    if (e == 0x65 || e == 0x45) {
      var p = end + 1;
      if (_at(p) == 0x2b || _at(p) == 0x2d) p++;
      if (_isDigit(_at(p))) {
        while (_isDigit(_at(p))) {
          p++;
        }
        end = p;
      }
    }
    return _make(
      TokenKind.literal,
      end - start,
      text: source.slice(start, end),
    );
  }

  Token _close(_Mode expected, TokenKind kind) {
    if (_mode == expected) {
      _modes.removeLast();
      return _make(kind, 1);
    }
    if (_mode == _Mode.interp && kind == TokenKind.rightParen) {
      _modes.removeLast();
      return _make(TokenKind.interpEnd, 1);
    }
    return _make(TokenKind.invalidCharacter, 1);
  }

  Token _stringToken() {
    final start = _pos;
    final byte = _bytes[start];
    if (byte == 0x22) {
      _modes.removeLast();
      return _make(TokenKind.stringEnd, 1);
    }
    if (byte == 0x5c) {
      final n = _at(start + 1);
      if (n == 0x28) {
        _modes.add(_Mode.interp);
        return _make(TokenKind.interpStart, 2);
      }
      if (n == -1) return _make(TokenKind.invalidCharacter, 1);
      return _escapeRun();
    }
    var end = start;
    while (end < _bytes.length && _bytes[end] != 0x5c && _bytes[end] != 0x22) {
      end++;
    }
    _piece(start, end);
    return Token(
      TokenKind.stringText,
      Span(start, end),
      value: source.slice(start, end),
    );
  }

  /// `(\\[^u(]|\\u[a-zA-Z0-9]{0,4})+`, validated as a JSON string.
  Token _escapeRun() {
    final start = _pos;
    var end = start;
    while (_at(end) == 0x5c) {
      final n = _at(end + 1);
      if (n == -1 || n == 0x28) break;
      if (n == 0x75) {
        end += 2;
        for (var i = 0; i < 4 && _isAlnum(_at(end)); i++) {
          end++;
        }
      } else {
        end += 2;
      }
    }
    _piece(start, end);
    final span = Span(start, end);
    final run = _bytes.sublist(start, end);
    final result = _decodeJsonStringBody(run);
    final error = result.error;
    if (error != null) {
      // jq wraps the run in quotes and hands it to its JSON parser, whose
      // position is the (line, column) after consuming the closing quote.
      final document = [0x22, ...run, 0x22];
      var line = 1;
      var column = 0;
      for (final b in document) {
        column++;
        if (b == 0x0a) {
          line++;
          column = 0;
        }
      }
      _report(
        Diagnostic(
          DiagnosticKind.lexical,
          '$error at line $line, column $column '
          "(while parsing '${utf8.decode(document, allowMalformed: true)}')",
          span,
        ),
      );
      return Token(TokenKind.stringText, span);
    }
    return Token(TokenKind.stringText, span, value: result.value);
  }

  static const Map<String, TokenKind> _keywords = {
    'as': TokenKind.asKeyword,
    'import': TokenKind.importKeyword,
    'include': TokenKind.includeKeyword,
    'module': TokenKind.moduleKeyword,
    'def': TokenKind.defKeyword,
    'if': TokenKind.ifKeyword,
    'then': TokenKind.thenKeyword,
    'else': TokenKind.elseKeyword,
    'elif': TokenKind.elifKeyword,
    'and': TokenKind.andKeyword,
    'or': TokenKind.orKeyword,
    'end': TokenKind.endKeyword,
    'reduce': TokenKind.reduceKeyword,
    'foreach': TokenKind.foreachKeyword,
    'try': TokenKind.tryKeyword,
    'catch': TokenKind.catchKeyword,
    'label': TokenKind.labelKeyword,
    'break': TokenKind.breakKeyword,
  };
}

typedef _Decoded = ({String? value, String? error});

int _hexValue(int b) {
  if (b >= 0x30 && b <= 0x39) return b - 0x30;
  if (b >= 0x61 && b <= 0x66) return b - 0x61 + 10;
  if (b >= 0x41 && b <= 0x46) return b - 0x41 + 10;
  return -1;
}

/// Ports jq's `found_string`: decodes the body of a JSON string whose
/// closing quote follows [body], with jq's exact error messages.
_Decoded _decodeJsonStringBody(Uint8List body) {
  final out = <int>[];
  var i = 0;
  int unhex4(int at) {
    var value = 0;
    for (var k = 0; k < 4; k++) {
      final h = _hexValue(body[at + k]);
      if (h < 0) return -1;
      value = value * 16 + h;
    }
    return value;
  }

  while (i < body.length) {
    final c = body[i++];
    if (c != 0x5c) {
      if (c < 0x20) {
        return (
          value: null,
          error:
              'Invalid string: control characters from U+0000 through U+001F '
              'must be escaped',
        );
      }
      out.add(c);
      continue;
    }
    if (i >= body.length) {
      return (value: null, error: 'Expected escape character at end of string');
    }
    final e = body[i++];
    switch (e) {
      case 0x5c:
      case 0x22:
      case 0x2f:
        out.add(e);
      case 0x62:
        out.add(0x08);
      case 0x66:
        out.add(0x0c);
      case 0x74:
        out.add(0x09);
      case 0x6e:
        out.add(0x0a);
      case 0x72:
        out.add(0x0d);
      case 0x75:
        if (i + 4 > body.length) {
          return (value: null, error: r'Invalid \uXXXX escape');
        }
        final hex = unhex4(i);
        if (hex < 0) {
          return (value: null, error: r'Invalid characters in \uXXXX escape');
        }
        var codePoint = hex;
        i += 4;
        if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
          if (i + 6 > body.length || body[i] != 0x5c || body[i + 1] != 0x75) {
            return (
              value: null,
              error: r'Invalid \uXXXX\uXXXX surrogate pair escape',
            );
          }
          final low = unhex4(i + 2);
          if (!(low >= 0xdc00 && low <= 0xdfff)) {
            return (
              value: null,
              error: r'Invalid \uXXXX\uXXXX surrogate pair escape',
            );
          }
          i += 6;
          codePoint = 0x10000 + (((codePoint - 0xd800) << 10) | (low - 0xdc00));
        }
        if (codePoint >= 0xd800 && codePoint <= 0xdfff) codePoint = 0xfffd;
        out.addAll(utf8.encode(String.fromCharCode(codePoint)));
      default:
        return (value: null, error: 'Invalid escape');
    }
  }
  return (value: utf8.decode(out, allowMalformed: true), error: null);
}

/// The result of lexing a whole source for inspection.
final class LexResult {
  LexResult(this.tokens, this.diagnostics);

  /// Every token including the final `eof` token.
  final List<Token> tokens;
  final List<Diagnostic> diagnostics;
}

/// Lexes [source] completely, for tests and tools. Parsing drives [Lexer]
/// lazily and interleaves its diagnostics with grammar diagnostics.
LexResult lex(String source) {
  final text = SourceText(source);
  final diagnostics = <Diagnostic>[];
  final lexer = Lexer(text, diagnostics.add);
  final tokens = <Token>[];
  while (true) {
    final token = lexer.next();
    tokens.add(token);
    if (token.kind == TokenKind.eof) break;
  }
  return LexResult(tokens, diagnostics);
}
