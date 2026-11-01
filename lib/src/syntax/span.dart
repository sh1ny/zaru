/// A half-open range of UTF-8 byte offsets within a [SourceText].
///
/// Positions are byte offsets, as in jq's `location` records: [start] is
/// inclusive and [end] is exclusive. An empty span has `start == end`.
final class Span {
  const Span(this.start, this.end);

  /// A span that starts and ends at [offset].
  const Span.at(int offset) : start = offset, end = offset;

  /// Sentinel for a diagnostic without a source location.
  static const Span unknown = Span(-1, -1);

  final int start;
  final int end;

  int get length => end - start;

  bool get isUnknown => start == -1;

  /// The smallest span containing both this span and [other].
  Span cover(Span other) => Span(
    start < other.start ? start : other.start,
    end > other.end ? end : other.end,
  );

  @override
  bool operator ==(Object other) =>
      other is Span && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start, $end)';
}
