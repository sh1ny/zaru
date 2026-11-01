/// jq's string boundary: strings are valid Unicode, ordered by code point.
///
/// Dart strings are UTF-16 and may hold unpaired surrogates. jq's strings are
/// UTF-8, so an unpaired surrogate can only arrive as invalid input and is
/// replaced by U+FFFD. These helpers define that replacement and jq's
/// unsigned-UTF-8 (equivalently, code point) ordering without allocating
/// intermediate code point lists.
library;

bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// Whether [s] contains a UTF-16 surrogate unit that is not part of a pair.
bool hasLoneSurrogate(String s) {
  final n = s.length;
  for (var i = 0; i < n; i++) {
    final unit = s.codeUnitAt(i);
    if (unit < 0xD800 || unit > 0xDFFF) continue;
    if (_isHigh(unit) && i + 1 < n && _isLow(s.codeUnitAt(i + 1))) {
      i++;
      continue;
    }
    return true;
  }
  return false;
}

/// Returns [s] with every unpaired surrogate replaced by U+FFFD.
///
/// Returns [s] itself, with no allocation, when nothing needs replacing.
String normalizeString(String s) {
  if (!hasLoneSurrogate(s)) return s;
  final n = s.length;
  final out = StringBuffer();
  for (var i = 0; i < n; i++) {
    final unit = s.codeUnitAt(i);
    if (unit < 0xD800 || unit > 0xDFFF) {
      out.writeCharCode(unit);
    } else if (_isHigh(unit) && i + 1 < n && _isLow(s.codeUnitAt(i + 1))) {
      out.writeCharCode(unit);
      out.writeCharCode(s.codeUnitAt(++i));
    } else {
      out.writeCharCode(0xFFFD);
    }
  }
  return out.toString();
}

/// Compares two normalized strings in jq's order: unsigned UTF-8 bytes, which
/// equals code point order. Dart's `compareTo` orders UTF-16 code units, which
/// sorts an astral character before U+E000..U+FFFF.
int compareUtf8Order(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = a.codeUnitAt(i);
    final y = b.codeUnitAt(i);
    if (x == y) continue;
    // A surrogate (an astral code point) is greater than any BMP unit at or
    // above U+E000; elsewhere the code unit order is the code point order.
    final xSurrogate = x >= 0xD800 && x <= 0xDFFF;
    final ySurrogate = y >= 0xD800 && y <= 0xDFFF;
    if (xSurrogate != ySurrogate) {
      if (xSurrogate && y >= 0xE000) return 1;
      if (ySurrogate && x >= 0xE000) return -1;
    }
    return x < y ? -1 : 1;
  }
  return a.length.compareTo(b.length);
}
