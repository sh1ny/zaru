import 'dart:collection';

import 'number.dart';

/// Private jq value domain shared by the decoder, printer and (later) engine.
///
/// A private value is exactly one of: `null`, `bool`, `String`, [JqNumber],
/// [JqArray] or [JqObject]. Numbers carry their literal/computed origin until
/// public export. Containers are immutable; a decoder or engine builds a
/// growable collection once, hands it over, and never touches it again.
/// Strings are already normalized: they never contain lone UTF-16 surrogates.
final class JqArray {
  /// Takes ownership of [items]; the caller must not mutate it afterwards.
  JqArray(List<Object?> items) : items = UnmodifiableListView(items);

  final List<Object?> items;

  /// The lazily created immutable public projection of this node, owned by
  /// the node (never by a run or a global table). See `exportValue`.
  Object? projection;

  int get length => items.length;
}

/// An immutable jq object with insertion-ordered, unique string keys.
final class JqObject {
  /// Takes ownership of [entries]; the caller must not mutate it afterwards.
  JqObject(Map<String, Object?> entries)
    : entries = UnmodifiableMapView(entries);

  final Map<String, Object?> entries;

  /// The lazily created immutable public projection of this node.
  Object? projection;

  int get length => entries.length;
}
