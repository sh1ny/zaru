// The exact fixture oracle used by conformance infrastructure.
//
// It is deliberately separate from the evaluator's jq equality
// (`JqNumber.compare`): finite numbers compare as exact decimal values, a
// computed double is judged by its shortest round-trip decimal, nonfinite
// values are compared before any printing could turn NaN into `null` or an
// infinity into the finite maximum, and NaN never equals anything.
//
// Browser-safe: no dart:io, no native jq.
import 'package:zaru/src/json_decoder.dart';
import 'package:zaru/src/number.dart';
import 'package:zaru/src/unicode.dart';
import 'package:zaru/src/value.dart';

/// The result of comparing an expected JSON text with an actual value.
enum OracleVerdict { match, mismatch, malformedExpectation }

/// Parses expected JSON text with jq's grammar into the private value domain.
///
/// Throws [FormatException] for a malformed expectation.
Object? parseExpectation(String text) => decodeJqJson(text);

/// Parses [expectedJson] and compares it with [actual].
///
/// A malformed expectation is reported as such; it is never a match and never
/// silently a mismatch.
OracleVerdict compareExpected(String expectedJson, Object? actual) {
  final Object? expected;
  try {
    expected = parseExpectation(expectedJson);
  } on FormatException {
    return OracleVerdict.malformedExpectation;
  }
  return oracleEquals(expected, actual)
      ? OracleVerdict.match
      : OracleVerdict.mismatch;
}

/// Exact structural equality of two values in either the public or the
/// private value domain. Unsupported values never match. Iterative.
bool oracleEquals(Object? expected, Object? actual) {
  final pending = <(Object?, Object?)>[(expected, actual)];
  while (pending.isNotEmpty) {
    final (e, a) = pending.removeLast();
    final en = _asNumber(e);
    final an = _asNumber(a);
    if (en != null || an != null) {
      if (en == null || an == null || !_numbersEqual(en, an)) return false;
      continue;
    }
    if (e == null || e is bool) {
      if (!identical(e, a) && e != a) return false;
      if (a != null && a is! bool) return false;
      continue;
    }
    if (e is String) {
      if (a is! String || normalizeString(e) != normalizeString(a)) {
        return false;
      }
      continue;
    }
    final el = _asList(e);
    if (el != null) {
      final al = _asList(a);
      if (al == null || al.length != el.length) return false;
      for (var i = 0; i < el.length; i++) {
        pending.add((el[i], al[i]));
      }
      continue;
    }
    final em = _asMap(e);
    if (em != null) {
      final am = _asMap(a);
      if (am == null || am.length != em.length) return false;
      for (final entry in em.entries) {
        if (!am.containsKey(entry.key)) return false;
        pending.add((entry.value, am[entry.key]));
      }
      continue;
    }
    return false;
  }
  return true;
}

/// A number as the oracle sees it: NaN, a signed infinity, or an exact decimal.
final class _OracleNumber {
  const _OracleNumber.nan() : decimal = null, infinity = 0, isNan = true;

  const _OracleNumber.infinite(this.infinity) : decimal = null, isNan = false;

  const _OracleNumber.finite(Decimal this.decimal)
    : infinity = 0,
      isNan = false;

  final Decimal? decimal;
  final int infinity;
  final bool isNan;
}

_OracleNumber? _asNumber(Object? value) {
  if (value is ZaruNumber) return _OracleNumber.finite(decimalOf(value));
  if (value is num) return _fromJq(JqNumber.fromNative(value));
  if (value is JqNumber) return _fromJq(value);
  return null;
}

_OracleNumber _fromJq(JqNumber number) {
  final decimal = number.decimal;
  if (decimal != null) {
    if (decimal.isInfinite) {
      return _OracleNumber.infinite(decimal.negative ? -1 : 1);
    }
    return _OracleNumber.finite(decimal);
  }
  final v = number.value;
  if (v.isNaN) return const _OracleNumber.nan();
  if (v.isInfinite) return _OracleNumber.infinite(v < 0 ? -1 : 1);
  return _OracleNumber.finite(Decimal.fromDouble(v));
}

bool _numbersEqual(_OracleNumber a, _OracleNumber b) {
  if (a.isNan || b.isNan) return false;
  final x = a.decimal;
  final y = b.decimal;
  if (x == null || y == null) {
    return x == null && y == null && a.infinity == b.infinity;
  }
  return Decimal.compare(x, y) == 0;
}

List<Object?>? _asList(Object? value) {
  if (value is JqArray) return value.items;
  if (value is List<Object?>) return value;
  return null;
}

/// A map with normalized String keys, or null for anything else (including
/// maps with non-String keys, which can never match).
Map<String, Object?>? _asMap(Object? value) {
  final Map<Object?, Object?> source;
  if (value is JqObject) {
    source = value.entries;
  } else if (value is Map<Object?, Object?>) {
    source = value;
  } else {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    final key = entry.key;
    if (key is! String) return null;
    result[normalizeString(key)] = entry.value;
  }
  return result;
}
