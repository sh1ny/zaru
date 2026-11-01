/// A jq-compatible JSON decoder: a port of the pinned jq 1.8.2 `jv_parse`.
///
/// This is deliberately not RFC 8259 `jsonDecode`. It accepts a leading BOM,
/// numeric extensions such as `+1`, `01`, `.5`, `1.`, and the spellings `nan`,
/// `NaN`, `Infinity`, `-inf`, and it keeps decimal numeric literals exact
/// until export (see `JqNumber`). It is iterative: nesting is held in an
/// explicit stack, so no host recursion is involved, and it enforces jq's
/// parser budget of 10000 pending stack slots, counting both open containers
/// and pending object keys.
///
/// Errors are [FormatException]s whose `source` is the original string and
/// whose `offset` is the zero-based UTF-16 index of the character being
/// scanned when jq's parser detects the error (the length of the source for
/// errors detected at end of input). The message is jq's, including its
/// one-based line and UTF-8 byte column, e.g.
/// `Exceeds depth limit for parsing at line 1, column 10001`.
library;

import 'number.dart';
import 'value.dart';

const int _maxParsingDepth = 10000;

/// Decodes exactly one JSON value into the private value domain.
///
/// Throws [FormatException] for empty or whitespace-only input
/// (`Expected JSON value`), malformed input, and anything after the first
/// value (`Unexpected extra JSON values`). Strings are normalized: raw lone
/// UTF-16 surrogates and escaped lone low surrogates become U+FFFD, while an
/// escaped lone high surrogate is an error, as in jq.
Object? decodeJqJson(String source) {
  final parser = _Parser(source);
  if (!parser.next()) {
    throw FormatException('Expected JSON value', source, source.length);
  }
  final value = parser.takeValue();
  if (parser.next()) {
    throw FormatException(
      'Unexpected extra JSON values',
      source,
      parser.lastOffset,
    );
  }
  return value;
}

enum _State { normal, string, stringEscape }

enum _Class { literal, whitespace, structure, quote }

final class _ScanError implements Exception {
  _ScanError(this.message);

  final String message;
}

final class _ArrayFrame {
  final List<Object?> items = [];
}

final class _ObjectFrame {
  final Map<String, Object?> entries = {};
}

/// A pending object key (jq pushes the key string onto the parser stack).
final class _KeyFrame {
  _KeyFrame(this.key);

  final String key;
}

_Class _classify(int unit) {
  switch (unit) {
    case 0x20: // space
    case 0x09: // tab
    case 0x0D: // CR
    case 0x0A: // LF
      return _Class.whitespace;
    case 0x22: // "
      return _Class.quote;
    case 0x5B: // [
    case 0x2C: // ,
    case 0x5D: // ]
    case 0x7B: // {
    case 0x3A: // :
    case 0x7D: // }
      return _Class.structure;
    default:
      return _Class.literal;
  }
}

bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

int _hexValue(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
  if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10;
  return -1;
}

/// Four ASCII hex digits at [from], or -1 (`unhex4`).
int _unhex4(String s, int from) {
  if (from + 4 > s.length) return -1;
  var result = 0;
  for (var i = 0; i < 4; i++) {
    final n = _hexValue(s.codeUnitAt(from + i));
    if (n < 0) return -1;
    result = (result << 4) | n;
  }
  return result;
}

/// How many UTF-8 bytes the text from [from] occupies, capped at [cap].
int _utf8BytesFrom(String s, int from, int cap) {
  var bytes = 0;
  var i = from;
  while (i < s.length && bytes < cap) {
    final unit = s.codeUnitAt(i);
    if (unit < 0x80) {
      bytes += 1;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (_isHigh(unit) &&
        i + 1 < s.length &&
        _isLow(s.codeUnitAt(i + 1))) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
    i++;
  }
  return bytes;
}

final class _Parser {
  _Parser(this._source)
    : _pos = _source.isNotEmpty && _source.codeUnitAt(0) == 0xFEFF ? 1 : 0;

  final String _source;
  int _pos;
  bool _eof = false;

  int _line = 1;
  int _column = 0;
  bool _lowHalfPending = false;

  final List<Object> _stack = [];
  Object? _next;
  bool _hasNext = false;

  final StringBuffer _token = StringBuffer();
  _State _state = _State.normal;

  Object? _out;
  int lastOffset = 0;

  Object? takeValue() {
    final value = _out;
    _out = null;
    return value;
  }

  FormatException _error(String message, int offset) => FormatException(
    '$message at line $_line, column $_column',
    _source,
    offset,
  );

  /// `jv_parser_next`: advances to the next complete value.
  ///
  /// Returns true with the value available from [takeValue]; false when the
  /// input is exhausted with no further value. Throws on any parse error.
  bool next() {
    if (_eof) return false;
    final length = _source.length;
    while (_pos < length) {
      final at = _pos++;
      try {
        if (_scan(_source.codeUnitAt(at))) {
          lastOffset = at;
          return true;
        }
      } on _ScanError catch (e) {
        throw _error(e.message, at);
      }
    }
    _eof = true;
    if (_state != _State.normal) {
      throw FormatException(
        'Unfinished string at EOF at line $_line, column $_column',
        _source,
        length,
      );
    }
    try {
      _checkLiteral();
    } on _ScanError catch (e) {
      throw FormatException(
        '${e.message} at EOF at line $_line, column $_column',
        _source,
        length,
      );
    }
    if (_stack.isNotEmpty) {
      throw FormatException(
        'Unfinished JSON term at EOF at line $_line, column $_column',
        _source,
        length,
      );
    }
    lastOffset = length;
    if (_hasNext) {
      _out = _next;
      _next = null;
      _hasNext = false;
      return true;
    }
    return false;
  }

  int _bytesOf(int unit) {
    if (_lowHalfPending) {
      _lowHalfPending = false;
      if (_isLow(unit)) return 0;
    }
    if (unit < 0x80) return 1;
    if (unit < 0x800) return 2;
    if (_isHigh(unit) &&
        _pos < _source.length &&
        _isLow(_source.codeUnitAt(_pos))) {
      _lowHalfPending = true;
      return 4;
    }
    // BMP units, and lone surrogates, which UTF-8 input would carry as U+FFFD.
    return 3;
  }

  bool _checkDone() {
    if (_stack.isEmpty && _hasNext) {
      _out = _next;
      _next = null;
      _hasNext = false;
      return true;
    }
    return false;
  }

  /// `scan`: consumes one UTF-16 unit; true when a value just completed.
  bool _scan(int unit) {
    _column += _bytesOf(unit);
    if (unit == 0x0A) {
      _line++;
      _column = 0;
    }
    var answer = false;
    if (_state == _State.normal) {
      final cls = _classify(unit);
      if (cls != _Class.literal) {
        _checkLiteral();
        if (_checkDone()) answer = true;
      }
      switch (cls) {
        case _Class.literal:
          _token.writeCharCode(unit);
        case _Class.whitespace:
          break;
        case _Class.quote:
          _state = _State.string;
        case _Class.structure:
          _structure(unit);
      }
      if (_checkDone()) answer = true;
    } else {
      if (unit == 0x22 && _state == _State.string) {
        _foundString();
        _state = _State.normal;
        if (_checkDone()) answer = true;
      } else {
        _token.writeCharCode(unit);
        _state = unit == 0x5C && _state == _State.string
            ? _State.stringEscape
            : _State.string;
      }
    }
    return answer;
  }

  void _value(Object? value) {
    if (_hasNext) throw _ScanError('Expected separator between values');
    _next = value;
    _hasNext = true;
  }

  void _structure(int unit) {
    switch (unit) {
      case 0x5B: // [
        if (_stack.length >= _maxParsingDepth) {
          throw _ScanError('Exceeds depth limit for parsing');
        }
        if (_hasNext) throw _ScanError('Expected separator between values');
        _stack.add(_ArrayFrame());
      case 0x7B: // {
        if (_stack.length >= _maxParsingDepth) {
          throw _ScanError('Exceeds depth limit for parsing');
        }
        if (_hasNext) throw _ScanError('Expected separator between values');
        _stack.add(_ObjectFrame());
      case 0x3A: // :
        if (!_hasNext) throw _ScanError("Expected string key before ':'");
        if (_stack.isEmpty || _stack.last is! _ObjectFrame) {
          throw _ScanError("':' not as part of an object");
        }
        final key = _next;
        if (key is! String) throw _ScanError('Object keys must be strings');
        _stack.add(_KeyFrame(key));
        _next = null;
        _hasNext = false;
      case 0x2C: // ,
        if (!_hasNext) throw _ScanError("Expected value before ','");
        if (_stack.isEmpty) {
          throw _ScanError("',' not as part of an object or array");
        }
        final top = _stack.last;
        if (top is _ArrayFrame) {
          top.items.add(_next);
        } else if (top is _KeyFrame) {
          _setMember(top);
        } else {
          // Input like {"a", "b"}.
          throw _ScanError('Objects must consist of key:value pairs');
        }
        _next = null;
        _hasNext = false;
      case 0x5D: // ]
        if (_stack.isEmpty || _stack.last is! _ArrayFrame) {
          throw _ScanError("Unmatched ']'");
        }
        final array = _stack.last as _ArrayFrame;
        if (_hasNext) {
          array.items.add(_next);
        } else if (array.items.isNotEmpty) {
          // Input like [1,2,3,].
          throw _ScanError('Expected another array element');
        }
        _stack.removeLast();
        _next = JqArray(array.items);
        _hasNext = true;
      case 0x7D: // }
        if (_stack.isEmpty) throw _ScanError("Unmatched '}'");
        if (_hasNext) {
          final top = _stack.last;
          if (top is! _KeyFrame) {
            throw _ScanError('Objects must consist of key:value pairs');
          }
          _setMember(top);
        } else {
          final top = _stack.last;
          if (top is! _ObjectFrame) throw _ScanError("Unmatched '}'");
          if (top.entries.isNotEmpty) {
            throw _ScanError('Expected another key-value pair');
          }
        }
        final object = _stack.removeLast() as _ObjectFrame;
        _next = JqObject(object.entries);
        _hasNext = true;
    }
  }

  /// Stores the pending value under the key on top of the stack and pops it.
  void _setMember(_KeyFrame key) {
    final object = _stack[_stack.length - 2] as _ObjectFrame;
    object.entries[key.key] = _next;
    _stack.removeLast();
  }

  /// `check_literal`: completes the pending non-string token, if any.
  void _checkLiteral() {
    if (_token.isEmpty) return;
    final token = _token.toString();
    String? pattern;
    Object? literal;
    switch (token.codeUnitAt(0)) {
      case 0x74: // t
        pattern = 'true';
        literal = true;
      case 0x66: // f
        pattern = 'false';
        literal = false;
      case 0x27: // '
        throw _ScanError('Invalid string literal; expected ", but got \'');
      case 0x6E: // n
        // A token starting with n may still be a literal nan.
        if (token.length > 1 && token.codeUnitAt(1) == 0x75) {
          pattern = 'null';
          literal = null;
        }
    }
    if (pattern != null) {
      if (token != pattern) throw _ScanError('Invalid literal');
      _value(literal);
    } else {
      // jq hands the token to decNumber as a C string, so a NUL ends it.
      final nul = token.indexOf('\u0000');
      final text = nul < 0 ? token : token.substring(0, nul);
      final number = JqNumber.tryParseLiteral(text);
      if (number == null) throw _ScanError('Invalid numeric literal');
      _value(number);
    }
    _token.clear();
  }

  /// `found_string`: decodes the escapes of the collected string body.
  void _foundString() {
    final raw = _token.toString();
    final n = raw.length;
    final out = StringBuffer();
    var i = 0;
    while (i < n) {
      final unit = raw.codeUnitAt(i++);
      if (unit == 0x5C) {
        if (i >= n) {
          throw _ScanError('Expected escape character at end of string');
        }
        final escape = raw.codeUnitAt(i++);
        switch (escape) {
          case 0x5C:
          case 0x22:
          case 0x2F:
            out.writeCharCode(escape);
          case 0x62:
            out.writeCharCode(0x08);
          case 0x66:
            out.writeCharCode(0x0C);
          case 0x74:
            out.writeCharCode(0x09);
          case 0x6E:
            out.writeCharCode(0x0A);
          case 0x72:
            out.writeCharCode(0x0D);
          case 0x75:
            if (_utf8BytesFrom(raw, i, 4) < 4) {
              throw _ScanError(r'Invalid \uXXXX escape');
            }
            var codePoint = _unhex4(raw, i);
            if (codePoint < 0) {
              throw _ScanError(r'Invalid characters in \uXXXX escape');
            }
            i += 4;
            if (_isHigh(codePoint)) {
              if (i + 6 > n ||
                  raw.codeUnitAt(i) != 0x5C ||
                  raw.codeUnitAt(i + 1) != 0x75) {
                throw _ScanError(r'Invalid \uXXXX\uXXXX surrogate pair escape');
              }
              final low = _unhex4(raw, i + 2);
              if (!_isLow(low)) {
                throw _ScanError(r'Invalid \uXXXX\uXXXX surrogate pair escape');
              }
              i += 6;
              codePoint =
                  0x10000 + (((codePoint - 0xD800) << 10) | (low - 0xDC00));
            } else if (_isLow(codePoint)) {
              // jq encodes it as invalid UTF-8, which is then replaced.
              codePoint = 0xFFFD;
            }
            out.writeCharCode(codePoint);
          default:
            throw _ScanError('Invalid escape');
        }
      } else {
        if (unit < 0x20) {
          throw _ScanError(
            'Invalid string: control characters from U+0000 through U+001F '
            'must be escaped',
          );
        }
        if (_isHigh(unit) && i < n && _isLow(raw.codeUnitAt(i))) {
          out.writeCharCode(unit);
          out.writeCharCode(raw.codeUnitAt(i++));
        } else if (_isHigh(unit) || _isLow(unit)) {
          // A raw unpaired surrogate is invalid input; jq substitutes U+FFFD.
          out.writeCharCode(0xFFFD);
        } else {
          out.writeCharCode(unit);
        }
      }
    }
    _value(out.toString());
    _token.clear();
  }
}
