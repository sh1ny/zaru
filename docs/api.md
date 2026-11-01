# Planned API

**Implemented so far (group 2 of `implement-core-language`): only `ZaruNumber` and `Zaru.toJson`, described under "Implemented numeric and printing surface" below. `Zaru.compile`, `run`, `runJson`, and every other declaration in this document are not available.** No `fromJson` or `runJson` stub exists.

**The filter APIs described here are planned and are not available in M0.** The library currently does not compile or execute filters. These contracts are binding for the `implement-core-language` change; they are not examples of runnable declarations.

## Compile and execute

`Zaru.compile(String source, {Set<String> variables = const {}})` will compile one reusable filter and return a compiled-filter object. It will report invalid source, undefined names, invalid arities, and out-of-scope labels at compile time. `variables` declares jq external variable names; declarations and their run-specific values are separate.

A compiled filter will expose:

```dart
Iterable<Object?> run(
  Object? input, {
  Map<String, Object?> args = const {},
});

Iterable<Object?> runJson(
  String text, {
  Map<String, Object?> args = const {},
});
```

`run` accepts JSON-shaped native Dart values and `ZaruNumber` at root, nested, and argument positions. `runJson` accepts exactly one jq JSON value as source text and decodes it directly into private origin-bearing values before evaluation. Neither call eagerly evaluates the filter: iteration performs the work. Runs and iterators have independent environments. Result order and duplicates are significant; an empty stream is not one `null` result. Stopping after a prefix does not evaluate the unused suffix. A runtime error can occur after earlier results have been observed, and it terminates that iterator; a subsequent `moveNext` returns `false` rather than replaying the failure.

Missing declared argument values fail on the first `moveNext`, before any filter result. Undeclared variable references fail compilation. Empty or whitespace-only `runJson` input is a missing single value and raises `FormatException`; it is not an input stream. A future CLI may treat empty stdin as zero inputs, but that stream behavior is separate from this API. Malformed, trailing, or multiple JSON values likewise raise `FormatException` on first iteration, with the original source, zero-based UTF-16 `offset`, and jq line/UTF-8-byte-column information where applicable. No public `fromJson` API is provided: converting JSON text to ordinary `num` before evaluation would erase literal origin.

## Public values and numbers

Ordinary public values are JSON-shaped Dart values: `null`, `bool`, `String`, `num`, lists, and string-keyed maps. `ZaruNumber` is the narrow exception for finite numeric literals whose exact value or jq-preserved canonical spelling would be lost by narrowing to `num`. It is planned as an immutable final type with `parse(String)`, `literal`, `toDouble()`, `toString()`, value equality, and `hashCode`. It is neither a `num` subtype nor `Comparable`; equality and hashing compare exact mathematical decimal value, ignoring equivalent scale and zero sign, and equality is only with another `ZaruNumber`. `parse` accepts one finite jq numeric token and throws `FormatException` for malformed input or a value jq normalizes to nonfinite.

The private engine retains literal/computed origin until evaluation completes and public output is selected. Untouched literal values are canonicalized with jq's `decNumberFromString` / `decNumberToString` behavior, without trimming or exponent-sized padding. Final output is `ZaruNumber` when canonical literal text differs from jq's computed printing of the converted value or integer magnitude exceeds `9007199254740991`; otherwise safe integral literals except negative zero narrow to `int`, and other eligible literals to `double`. This is not based on whether Dart happened to represent an input as `int` or `double`.

Native finite values exactly representable as binary64 enter as computed-origin numbers and retain signed zero. A native integer whose exact binary64 round-trip fails enters with exact literal origin; a value already rounded by its caller cannot be repaired. Compatible native pass-through values retain their original `num` subtype/storage. Arithmetic outputs are `double` on VM and wasm. VM/wasm distinguish `int` and `double`; dart2js can have overlapping numeric subtypes, so portable subtype behavior is not promised there. None of these host subtype differences changes jq semantics.

Jq arithmetic first reduces literal operands through its decimal64-derived context (17 significant digits, half-even rounding) and then converts with correctly rounded binary64 semantics. Literal/literal comparison uses decimal values; any comparison involving computed origin follows jq's double fallback. Unary negation retains literal precision and jq's canonicalization of negated literal zero to positive zero; computed negation follows binary64 signed-zero behavior. Thus numeric evaluation, public `ZaruNumber` equality, and fixture-oracle comparison are distinct operations. Re-entering a binary64-compatible public `num` through a later `run` makes it computed-origin; the exact-native-integer exception still applies, while a single compiled expression preserves origin internally. `toJson` preserves literal value and spelling where representable, not computed origin or nonfinite values. M3 options such as `--argjson` that must preserve literal origin require a private decoder-to-environment path.

For detailed canonicalization, conversion, exponent-edge, signed-zero, and native-origin rules see [D4](../openspec/changes/implement-core-language/design.md#d4-preserve-exceptional-numbers-through-an-explicit-narrow-boundary). The jq JSON and Unicode boundary is in [D7](../openspec/changes/implement-core-language/design.md#d7-specify-unicode-and-nonfinite-boundaries-explicitly); iterative codecs and native projection ownership are in [D8](../openspec/changes/implement-core-language/design.md#d8-bound-deep-codec-work-and-public-projection-reuse).

## JSON decoding and printing

The planned decoder follows pinned jq `jv_parse`, not RFC-only `jsonDecode`: it accepts a leading BOM, jq's accepted numeric extensions such as `+1`, `01`, `.5`, and `1.`, and NaN/infinity spellings. It normalizes raw lone UTF-16 units and escaped lone-low-surrogate values to U+FFFD; a lone high-surrogate escape is invalid. Native nonfinite numbers are retained as numeric kinds internally and export as native NaN/infinity.

`Zaru.toJson(value, {bool compact, bool sortKeys, String indent})` will print jq-compatible compact or indented output, optional sorted keys, and jq escaping. Exact option defaults are specified by implementation, not M0. NaN prints as `null`; computed infinities clamp to jq's signed maximum finite double; negative zero prints as `-0`. Printing starts at root depth zero; a value deeper than 10000 is replaced with the unquoted text `<skipped: too deep>` without traversing that subtree. This jq-compatible marker makes the resulting text non-JSON and is not a successful lossless encoding.

Parsing, normalization, export, and printing use explicit work stacks. The JSON parser rejects a container opening once its pending parser slots reach 10000, counting both containers and object-key slots; arrays accept depth 10000 and reject 10001, while nested keyed objects accept 5000 and reject 5001. A decoding failure raises `FormatException` on first iteration with original source and zero-based UTF-16 offset; its message includes jq's reason and one-based line/UTF-8-byte column. Native and engine-constructed containers do not inherit the parser depth budget.

Engine-created lists and maps are immutable before exposure. Each immutable internal container owns and reuses one lazily created immutable public projection, so repeated yields of that internal subtree expose identical public containers without a global strong-key cache. Changed projections are distinct. Public-compatible caller-owned container storage can pass through by reference without freezing, memoization, or num-subtype conversion; caller mutation remains caller-owned and is not a snapshot guarantee. When ingestion must normalize values or keys, it rebuilds only changed paths into owned containers while retaining private numeric origin. Scalar `ZaruNumber` identity is unspecified. These projection guarantees are governed by [D8](../openspec/changes/implement-core-language/design.md#d8-bound-deep-codec-work-and-public-projection-reuse).

## Implemented numeric and printing surface

These two declarations exist and are exported from `package:zaru/zaru.dart`:

- `final class ZaruNumber`: `ZaruNumber.parse(String)` (jq numeric grammar, no trimming; throws `FormatException` for malformed text, NaN, Infinity, or a token whose exponent overflows jq's decimal context), `String get literal` (jq canonical text, scale preserved: `100e-2` is `1.00`, `1e2` is `1E+2`), `double toDouble()` (17 significant digits half-even, then correctly rounded binary64; infinite if beyond the binary64 range), `toString()` (same as `literal`), and `==`/`hashCode` by exact decimal value regardless of scale or zero sign. It is never equal to a native number and is not `Comparable`.
- `Zaru.toJson(Object? value, {bool compact = true, bool sortKeys = false, String indent = '  '})`. Accepts `null`, `bool`, `String`, `num`, `ZaruNumber`, `List`, and `Map` with `String` keys. Anything else, including a map with a non-`String` key, throws `ArgumentError`; only visited values are inspected. Compact output has no whitespace; pretty output follows jq (`"k": v`, empty containers as `[]`/`{}`, `indent` repeated per level, any string such as `'\t'`). `sortKeys` orders keys by code point (UTF-8 byte order). Unpaired surrogates print as U+FFFD, and map keys that normalize to the same text collapse (first position, last value). Computed numbers print with jq's spelling (`1e+17`, `1e-05`, `1.5e-07`); integral doubles print without a fraction; NaN prints `null`; infinities clamp to `+-1.7976931348623157e+308`; `-0.0` prints `-0`; `ZaruNumber` and exact native integers beyond 2^53 print exactly. A value deeper than 10000 (root is depth zero) prints as the unquoted text `<skipped: too deep>`, which makes the output non-JSON.

The jq-compatible decoder (`decodeJqJson`) and fixture oracle are internal (`lib/src`, `test/support`); the decoder is reachable publicly only once `runJson` exists. `FormatException` from the decoder carries the original source, the zero-based UTF-16 `offset` of the character being scanned when jq detects the error (source length at end of input; for `Unexpected extra JSON values`, the character that completes the extra value), and a message such as `Exceeds depth limit for parsing at line 1, column 10001`. The BOM counts toward `offset` but not toward the column.

## Errors and diagnostics

`ZaruCompileError` will expose first-diagnostic `line`, `col`, `endLine`, `endCol`, and `message`, plus an immutable ordered list of rendered `diagnostics`. Coordinates and spans are one-based UTF-8-byte positions with exclusive ends, following jq conventions, including EOF handling. Diagnostics contain jq-compatible excerpts, expected-token labels, and caret widths. Multiple compiler blocks can be retained: the public scalar fields describe the first diagnostic, while the conformance adapter selects the last block prefixed `jq: error` to match jq's test callback. Diagnostics derive from grammar context and source positions, never fixture IDs or complete source-text lookups.

`ZaruRuntimeError` will carry the jq error value, including `null`; runtime failures happen during iteration. `try`/`catch` and optional access handle data errors but not compile failures or lexical `break` signals. Previously yielded values remain observable. Internal unsupported-construct classification is distinct from supported semantic compile errors; an unsupported import or format operation cannot pass a fixture that expects a compile error. M2 predicate policy remains deferred: it does not create M1 support or a conformance pass.

## Composition and ownership

Pipes within a compiled filter preserve private literal origin. Passing a public result to a later filter applies native ingestion again: binary64-compatible numbers become computed-origin, while a native integer that fails the exact binary64 round-trip takes the exact-literal exception. Use `ZaruNumber` or `runJson` when literal origin must be supplied explicitly. Container projection identity is guaranteed only for the same owned internal node; general caller-container or scalar identity is not promised. See the [architecture index](../openspec/architecture.md) and the numeric-boundary [ADR 0003](adr/0003-numeric-boundary.md).

## Current CLI boundary

The only M0 CLI operation is:

```sh
mise run cli -- --version
```

A version response identifies the package scaffold, not a jq engine. Filter execution, jq flags, and CLI JSON input/output processing are unavailable. The Dart SDK MCP configuration is contributor tooling, not a zaru service; no benchmark implementation or product MCP server is provided.
