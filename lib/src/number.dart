/// jq numbers: literal-origin decimals and computed binary64 values.
///
/// This library is the whole numeric boundary of zaru's JSON layer. It ports,
/// from the pinned jq 1.8.2 sources:
///
/// * `decNumberFromString` / `decNumberToString` under jq's thread decimal
///   context (digits 147483648, exponent range -999999999..999999999), so
///   `100e-2` becomes `1.00`, `0e1000000000` becomes `0E+999999999`, and
///   tokens beyond the exponent range become infinity;
/// * `jvp_literal_number_to_double`: reduce to 17 significant digits with
///   half-even rounding, then correctly rounded binary64 conversion;
/// * `jvp_dtoa_fmt`: the shortest round-trip spelling of a computed double;
/// * literal negation (`decNumberMinus`) and comparison (`jvp_number_cmp`).
///
/// Nothing here allocates anything proportional to a decimal exponent.
library;

/// The largest exponent of an unrounded finite value (`Emax`).
const int _emax = 999999999;

/// The smallest exponent of a subnormal value (`Etiny`) for jq's context.
const int _etiny = -1147483646;

/// Parsed but not yet narrowed: tokens longer than this are invalid in jq.
const int _maxTokenLength = 999999999;

/// The greatest integer magnitude that is always exact in binary64.
const int _maxSafeInteger = 9007199254740991;

const String _maxSafeDigits = '9007199254740991';

/// jq's conversion keeps this many significant digits (`DEC_NUMBER_DOUBLE_PRECISION`).
const int _doubleDigits = 17;

/// An exact decimal: sign, coefficient digits and exponent, or an infinity.
///
/// Instances are immutable. The coefficient has no leading zeros (a zero is
/// the single digit `0`) and keeps its trailing zeros, because scale is part
/// of a literal's canonical spelling. This class is private to the package; the
/// public surface is [ZaruNumber].
final class Decimal {
  Decimal._(this.negative, this.digits, this.exponent, this.isInfinite);

  Decimal._infinity({required bool negative}) : this._(negative, '0', 0, true);

  /// Whether the sign bit is set (a negative zero is negative).
  final bool negative;

  /// Coefficient digits, most significant first; `'0'` for zero.
  final String digits;

  /// The power of ten applied to the coefficient.
  final int exponent;

  /// Whether this value is an infinity (digits and exponent are then unused).
  final bool isInfinite;

  bool get isZero => !isInfinite && digits == '0';

  /// Builds a finite value from an exact coefficient and exponent.
  ///
  /// [digits] must be decimal digits without leading zeros (or exactly `0`).
  factory Decimal.exact(String digits, int exponent, {bool negative = false}) =>
      Decimal._(negative, digits, exponent, false);

  /// The shortest-round-trip decimal of a finite computed double, exactly as
  /// jq prints it. Zeros keep their sign.
  factory Decimal.fromDouble(double value) {
    if (value == 0) return Decimal._(value.isNegative, '0', 0, false);
    final (digits, decpt) = _shortestDigits(value.abs());
    return Decimal._(value < 0, digits, decpt - digits.length, false);
  }

  /// The canonical spelling: `decNumberToString`, without trimming.
  String get canonical {
    if (isInfinite) return negative ? '-Infinity' : 'Infinity';
    final out = StringBuffer();
    if (negative) out.write('-');
    final d = digits.length;
    if (exponent == 0) {
      out.write(digits);
      return out.toString();
    }
    var pre = d + exponent;
    var e = 0;
    if (exponent > 0 || pre < -5) {
      e = exponent + d - 1;
      pre = 1;
    }
    if (pre > 0) {
      out.write(digits.substring(0, pre));
      if (pre < d) {
        out.write('.');
        out.write(digits.substring(pre));
      }
    } else {
      out.write('0.');
      for (var i = pre; i < 0; i++) {
        out.write('0');
      }
      out.write(digits);
    }
    if (e != 0) {
      out.write('E');
      out.write(e < 0 ? '-' : '+');
      out.write(e.abs());
    }
    return out.toString();
  }

  /// `decNumberMinus`: negation preserves precision and scale; negating a
  /// zero yields a positive zero of the same scale.
  Decimal negate() {
    if (isInfinite) return Decimal._infinity(negative: !negative);
    if (isZero) return Decimal._(false, digits, exponent, false);
    return Decimal._(!negative, digits, exponent, false);
  }

  // Normalized (no trailing zeros) form, used for value equality and order.
  late final (String, int) _normalized = _normalize();

  (String, int) _normalize() {
    if (isInfinite || isZero) return ('0', 0);
    var end = digits.length;
    while (end > 1 && digits.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    if (end == digits.length) return (digits, exponent);
    return (digits.substring(0, end), exponent + digits.length - end);
  }

  /// Whether the two exact values are numerically equal (scale and zero sign
  /// are not part of the value).
  bool valueEquals(Decimal other) => compare(this, other) == 0;

  /// A hash consistent with [valueEquals].
  int get valueHash {
    if (isInfinite) return Object.hash(true, negative);
    final (d, e) = _normalized;
    return Object.hash(false, isZero ? false : negative, d, e);
  }

  /// `decNumberCompare` as used by `jvp_number_cmp`: -1, 0 or 1.
  static int compare(Decimal a, Decimal b) {
    if (a.isInfinite || b.isInfinite) {
      final x = a.isInfinite ? (a.negative ? -1 : 1) : 0;
      final y = b.isInfinite ? (b.negative ? -1 : 1) : 0;
      return x.compareTo(y);
    }
    final aSign = a.isZero ? 0 : (a.negative ? -1 : 1);
    final bSign = b.isZero ? 0 : (b.negative ? -1 : 1);
    if (aSign != bSign) return aSign < bSign ? -1 : 1;
    if (aSign == 0) return 0;
    final (ad, ae) = a._normalized;
    final (bd, be) = b._normalized;
    final aAdjusted = ae + ad.length - 1;
    final bAdjusted = be + bd.length - 1;
    var magnitude = aAdjusted.compareTo(bAdjusted);
    if (magnitude == 0) {
      // Without trailing zeros, a proper prefix is the smaller magnitude.
      magnitude = ad.compareTo(bd).sign;
    }
    return aSign < 0 ? -magnitude : magnitude;
  }

  /// `jvp_literal_number_to_double`: 17 significant digits, half-even, then a
  /// correctly rounded binary64 conversion.
  double toDouble() {
    if (isInfinite) return negative ? double.negativeInfinity : double.infinity;
    if (isZero) return negative ? -0.0 : 0.0;
    var coefficient = digits;
    var exp = exponent;
    if (coefficient.length > _doubleDigits) {
      final dropped = coefficient.length - _doubleDigits;
      var kept = coefficient.substring(0, _doubleDigits);
      final first = coefficient.codeUnitAt(_doubleDigits) - 0x30;
      var up = false;
      if (first > 5) {
        up = true;
      } else if (first == 5) {
        for (var i = _doubleDigits + 1; i < coefficient.length; i++) {
          if (coefficient.codeUnitAt(i) != 0x30) {
            up = true;
            break;
          }
        }
        // An exact tie rounds to the even neighbor.
        if (!up) up = (kept.codeUnitAt(_doubleDigits - 1) - 0x30).isOdd;
      }
      exp += dropped;
      if (up) {
        kept = _increment(kept);
        if (kept.length > _doubleDigits) {
          kept = kept.substring(0, _doubleDigits);
          exp += 1;
        }
      }
      coefficient = kept;
    }
    final adjusted = exp + coefficient.length - 1;
    // Beyond these bounds the correctly rounded binary64 is infinity or zero
    // whatever the digits are; this also keeps the parsed exponent small.
    if (adjusted > 400) {
      return negative ? double.negativeInfinity : double.infinity;
    }
    if (adjusted < -400) return negative ? -0.0 : 0.0;
    final magnitude = double.parse('${coefficient}e$exp');
    return negative ? -magnitude : magnitude;
  }

  @override
  String toString() => canonical;
}

/// Adds one to a string of decimal digits.
String _increment(String digits) {
  final units = digits.codeUnits.toList();
  var i = units.length - 1;
  while (i >= 0) {
    if (units[i] == 0x39) {
      units[i] = 0x30;
      i--;
    } else {
      units[i]++;
      return String.fromCharCodes(units);
    }
  }
  return '1${String.fromCharCodes(units)}';
}

/// Shortest digits that round-trip [value] (finite, positive) and the decimal
/// point position `decpt` such that value = 0.DIGITS * 10^decpt.
(String, int) _shortestDigits(double value) {
  // The shortest exponential form has the same digits as jq's dtoa mode 0.
  final text = value.toStringAsExponential();
  final e = text.indexOf('e');
  final mantissa = text.substring(0, e);
  final exponent = int.parse(text.substring(e + 1));
  final digits = mantissa.length == 1
      ? mantissa
      : '${mantissa[0]}${mantissa.substring(2)}';
  return (digits, exponent + 1);
}

/// The greatest finite binary64, to which jq clamps printed infinities.
const double _maxDouble = 1.7976931348623157e308;

/// `jvp_dtoa_fmt`: a computed number's spelling. NaN prints as `null` and
/// infinities clamp to the largest finite double. `-0` keeps its sign.
String formatComputedNumber(double value) {
  if (value.isNaN) return 'null';
  if (value.isInfinite) value = value > 0 ? _maxDouble : -_maxDouble;
  if (value == 0) return value.isNegative ? '-0' : '0';
  final (digits, decpt) = _shortestDigits(value.abs());
  final out = StringBuffer();
  if (value < 0) out.write('-');
  final n = digits.length;
  if (decpt <= -4 || decpt > n + 15) {
    out.write(digits[0]);
    if (n > 1) {
      out.write('.');
      out.write(digits.substring(1));
    }
    out.write('e');
    final e = decpt - 1;
    out.write(e < 0 ? '-' : '+');
    final magnitude = e.abs();
    if (magnitude < 10) out.write('0');
    out.write(magnitude);
  } else if (decpt <= 0) {
    out.write('0.');
    for (var i = decpt; i < 0; i++) {
      out.write('0');
    }
    out.write(digits);
  } else if (decpt >= n) {
    out.write(digits);
    for (var i = n; i < decpt; i++) {
      out.write('0');
    }
  } else {
    out.write(digits.substring(0, decpt));
    out.write('.');
    out.write(digits.substring(decpt));
  }
  return out.toString();
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// Caseless ASCII comparison against a lowercase [word], like `decBiStr`.
bool _equalsWord(String s, int from, String word) {
  if (s.length - from != word.length) return false;
  for (var i = 0; i < word.length; i++) {
    var u = s.codeUnitAt(from + i);
    if (u >= 0x41 && u <= 0x5A) u += 0x20;
    if (u != word.codeUnitAt(i)) return false;
  }
  return true;
}

/// The result of reading one numeric token.
typedef _Token = ({Decimal? decimal, bool isNan});

/// Ports `decNumberFromString` plus the NaN checks of `jvp_literal_number_new`.
///
/// Returns null for a syntax error or a NaN with a payload. Finite values are
/// finalized under jq's context: beyond the exponent range they become
/// infinity or (below `Etiny`) are rounded half up.
_Token? _readToken(String s) {
  final n = s.length;
  if (n > _maxTokenLength) return null;
  var i = 0;
  var negative = false;
  if (n > 0) {
    final first = s.codeUnitAt(0);
    if (first == 0x2D) {
      negative = true;
      i = 1;
    } else if (first == 0x2B) {
      i = 1;
    }
  }
  final start = i;
  var dot = -1;
  var last = -1;
  var c = i;
  for (; c < n; c++) {
    final u = s.codeUnitAt(c);
    if (_isDigit(u)) {
      last = c;
    } else if (u == 0x2E && dot < 0) {
      dot = c;
    } else {
      break;
    }
  }

  if (last < 0) {
    // No digits: only an infinity or a payload-free NaN can follow.
    if (c >= n || dot >= 0) return null;
    if (_equalsWord(s, c, 'infinity') || _equalsWord(s, c, 'inf')) {
      return (decimal: Decimal._infinity(negative: negative), isNan: false);
    }
    var k = c;
    if (s.codeUnitAt(k) == 0x73 || s.codeUnitAt(k) == 0x53) k++;
    if (!_equalsWord(s.substring(k, k + 3 > n ? n : k + 3), 0, 'nan')) {
      return null;
    }
    k += 3;
    for (; k < n; k++) {
      if (s.codeUnitAt(k) != 0x30) return null;
    }
    return (decimal: null, isNan: true);
  }

  var exponent = 0;
  if (c < n) {
    final marker = s.codeUnitAt(c);
    if (marker != 0x65 && marker != 0x45) return null;
    c++;
    var negativeExponent = false;
    if (c < n && s.codeUnitAt(c) == 0x2D) {
      negativeExponent = true;
      c++;
    } else if (c < n && s.codeUnitAt(c) == 0x2B) {
      c++;
    }
    if (c >= n) return null;
    // Insignificant leading zeros are skipped, but one digit always remains.
    while (s.codeUnitAt(c) == 0x30 && c + 1 < n) {
      c++;
    }
    final firstExponent = c;
    while (c < n && _isDigit(s.codeUnitAt(c))) {
      c++;
    }
    if (c != n) return null;
    final length = c - firstExponent;
    int magnitude;
    if (length >= 10 && (length > 10 || s.codeUnitAt(firstExponent) > 0x31)) {
      // Certain overflow; the pinned parser substitutes 2 * DECNUMMAXE.
      magnitude = 1999999998;
    } else {
      magnitude = int.parse(s.substring(firstExponent, c));
    }
    exponent = negativeExponent ? -magnitude : magnitude;
  }

  var coefficient = s.substring(start, last + 1);
  if (dot >= 0) {
    coefficient = coefficient.replaceFirst('.', '');
    if (dot < last) exponent -= last - dot;
  }
  var lead = 0;
  while (lead < coefficient.length - 1 &&
      coefficient.codeUnitAt(lead) == 0x30) {
    lead++;
  }
  if (lead > 0) coefficient = coefficient.substring(lead);

  return (decimal: _finalize(negative, coefficient, exponent), isNan: false);
}

/// `decFinalize` under jq's context for a freshly read finite value.
Decimal _finalize(bool negative, String digits, int exponent) {
  if (digits == '0') {
    if (exponent > _emax) exponent = _emax;
    if (exponent < _etiny) exponent = _etiny;
    return Decimal._(negative, digits, exponent, false);
  }
  final adjusted = exponent + digits.length - 1;
  if (adjusted > _emax) return Decimal._infinity(negative: negative);
  if (exponent >= _etiny) return Decimal._(negative, digits, exponent, false);

  // Subnormal: drop digits so the exponent becomes Etiny, rounding half up.
  final adjust = _etiny - exponent;
  if (adjust > digits.length) return Decimal._(negative, '0', _etiny, false);
  final keep = digits.length - adjust;
  final roundUp = digits.codeUnitAt(keep) >= 0x35;
  var coefficient = keep == 0 ? '0' : digits.substring(0, keep);
  if (roundUp) coefficient = _increment(coefficient);
  return Decimal._(negative, coefficient, _etiny, false);
}

/// A jq number: either computed (binary64) or literal-origin (decimal).
///
/// Literal origin survives only until arithmetic: unary negation keeps it,
/// binary arithmetic, native ingestion and `-0.0`-style results produce
/// computed numbers. NaN is always computed. A literal may be an infinity
/// (a token beyond the decimal exponent range), which exports as a native
/// infinity.
final class JqNumber {
  /// A computed number.
  JqNumber.computed(double value) : _value = value, decimal = null;

  JqNumber._literal(this.decimal) : _value = null;

  /// Reads one jq numeric token (`+1`, `01`, `.5`, `1.`, `NaN`, `-Infinity`,
  /// ...). Returns null when jq's parser would call it an invalid literal.
  static JqNumber? tryParseLiteral(String token) {
    final read = _readToken(token);
    if (read == null) return null;
    if (read.isNan) return JqNumber.computed(double.nan);
    return JqNumber._literal(read.decimal!);
  }

  /// Interprets a native Dart number independently of its Dart spelling.
  ///
  /// Every finite value exactly representable as binary64 is a computed
  /// number and keeps its signed zero. Only an integer whose binary64 round
  /// trip fails takes exact literal origin.
  factory JqNumber.fromNative(num value) {
    if (value is int &&
        value.isFinite &&
        (value > _maxSafeInteger + 1 || value < -_maxSafeInteger - 1)) {
      final rounded = value.toDouble();
      if (BigInt.from(value) != BigInt.from(rounded)) {
        final text = value.toString();
        final negative = text.startsWith('-');
        return JqNumber._literal(
          Decimal._(negative, negative ? text.substring(1) : text, 0, false),
        );
      }
      return JqNumber.computed(rounded);
    }
    return JqNumber.computed(value.toDouble());
  }

  /// Gives a public [ZaruNumber] its private literal origin back.
  factory JqNumber.fromZaru(ZaruNumber number) =>
      JqNumber._literal(decimalOf(number));

  /// The exact decimal, or null for a computed number.
  final Decimal? decimal;

  double? _value;

  bool get isLiteral => decimal != null;

  bool get isNan => decimal == null && _value!.isNaN;

  /// `jv_number_value`: the binary64 value (converted once for literals).
  double get value => _value ??= decimal!.toDouble();

  /// How `jv_dump` prints this number: a finite literal prints its canonical
  /// text; anything else prints the computed spelling (NaN as `null`,
  /// infinities clamped, `-0` for negative zero).
  String get text {
    final d = decimal;
    if (d != null && !d.isInfinite) return d.canonical;
    return formatComputedNumber(value);
  }

  /// `jv_number_negate`: literals stay literals (and a literal zero becomes
  /// positive), computed numbers follow binary64.
  JqNumber negate() {
    final d = decimal;
    if (d != null) return JqNumber._literal(d.negate());
    return JqNumber.computed(-_value!);
  }

  /// `jvp_number_cmp`: decimal comparison when both are literals, otherwise
  /// the double fallback. NaN handling belongs to the caller (`jv_cmp`).
  static int compare(JqNumber a, JqNumber b) {
    final x = a.decimal;
    final y = b.decimal;
    if (x != null && y != null) return Decimal.compare(x, y);
    final da = a.value;
    final db = b.value;
    if (da < db) return -1;
    if (da == db) return 0;
    return 1;
  }

  /// Narrows to the public representation.
  ///
  /// A computed number is its binary64 value. A literal whose canonical text
  /// is not what computed printing of its converted value would produce, or
  /// whose integer magnitude exceeds 9007199254740991, is a [ZaruNumber];
  /// otherwise a safe integral literal (except negative zero) is an `int` and
  /// any other literal a `double`. Infinite literals are native infinities.
  Object export() {
    final d = decimal;
    if (d == null) return _value!;
    if (d.isInfinite) return value;
    final canonical = d.canonical;
    final converted = value;
    if (canonical != formatComputedNumber(converted)) return wrapDecimal(d);
    // Equal spellings are always plain decimal text without an exponent.
    if (canonical.contains('.')) return converted;
    final magnitude = d.negative ? canonical.substring(1) : canonical;
    if (magnitude.length > _maxSafeDigits.length ||
        (magnitude.length == _maxSafeDigits.length &&
            magnitude.compareTo(_maxSafeDigits) > 0)) {
      return wrapDecimal(d);
    }
    if (canonical == '-0') return converted;
    return converted.toInt();
  }

  @override
  String toString() => text;
}

/// The text a native number prints as: computed spelling, except for an
/// integer that cannot round-trip through binary64, which prints exactly.
String nativeNumberText(num value) {
  if (value is double) return formatComputedNumber(value);
  return JqNumber.fromNative(value).text;
}

/// An exact finite jq number, for values that a Dart [num] cannot represent
/// faithfully.
///
/// Wraps jq's canonical decimal text. Two instances are equal when they denote
/// the same mathematical value, whatever their scale or zero sign; a
/// [ZaruNumber] is never equal to a native number and is not [Comparable].
final class ZaruNumber {
  const ZaruNumber._(this._decimal);

  /// Parses exactly one finite jq numeric token.
  ///
  /// Accepts jq's grammar (`+1`, `01`, `.5`, `1.`, exponents) without any
  /// trimming and keeps scale: `100e-2` has [literal] `1.00`. Throws
  /// [FormatException] for malformed text, NaN, Infinity, or a token whose
  /// exponent exceeds jq's decimal context and therefore normalizes to
  /// infinity.
  factory ZaruNumber.parse(String text) {
    final read = _readToken(text);
    if (read == null) {
      throw FormatException('Invalid numeric literal', text);
    }
    final decimal = read.decimal;
    if (decimal == null || decimal.isInfinite) {
      throw FormatException('Not a finite numeric literal', text);
    }
    return ZaruNumber._(decimal);
  }

  final Decimal _decimal;

  /// The canonical text, following jq's `decNumberToString`.
  String get literal => _decimal.canonical;

  /// The value converted the way jq does it (17 significant digits, half-even,
  /// then correctly rounded binary64). Infinite for a finite literal beyond
  /// the binary64 range.
  double toDouble() => _decimal.toDouble();

  @override
  String toString() => literal;

  @override
  bool operator ==(Object other) =>
      other is ZaruNumber && _decimal.valueEquals(other._decimal);

  @override
  int get hashCode => _decimal.valueHash;
}

/// Wraps a finite [Decimal] for public export. Not part of the public API.
ZaruNumber wrapDecimal(Decimal decimal) => ZaruNumber._(decimal);

/// The exact decimal of a [ZaruNumber]. Not part of the public API.
Decimal decimalOf(ZaruNumber number) => number._decimal;
