# API direction

**None of the filter APIs below are available in M0.** These are the intended
public API shapes, not runnable examples or exported declarations. M0 does not
parse, compile, evaluate, or serialize jq results.

## Compile once, run lazily

- `Zaru.compile(String)` returns a compiled filter.
- `filter.run(Object?, {Map<String, Object?> args = const {}})` returns a lazy
  `Iterable<Object?>`.
- `Zaru.toJson(value, {bool compact, bool sortKeys, String indent})` serializes a
  value with the requested output formatting. Option defaults are not specified
  in M0.

Compilation will report invalid source before evaluation. A compiled filter can
be reused with different input values and variable bindings supplied through
`args`. jq output is a sequence: no results is distinct from one `null` result.
Calling `run` is not a promise that all evaluation has completed; consuming the
iterable performs work and can raise a runtime error after yielding results.

The public value boundary uses ordinary JSON-shaped Dart values: `null`, `bool`,
`String`, `num`, lists, and maps with string keys. It must not require users to
wrap every input in a custom JSON hierarchy. Inputs are not mutated by updates.
A `BigInt` is not an ordinary JSON number, and exact numeric literal handling
cannot silently round values to fit `double`. The internal representation and
VM/browser boundary are discussed in [ADR 0002](adr/0002-evaluation-model.md).

## Typed errors

- `ZaruCompileError(line, col, message)` describes invalid filter source.
- `ZaruRuntimeError(message, value)` describes a failure during evaluation and
  the associated value.

These error types are also planned, not implemented. Source coordinate conventions
and the complete serialization/error contracts will be specified alongside their
implementations rather than guessed in M0.

## Current CLI boundary

The only M0 CLI operation is:

```sh
mise run cli -- --version
```

A version response identifies the package scaffold, not a jq engine. Filter
execution, jq flags, and JSON input/output processing are unavailable. There is
no benchmark implementation or MCP product server. The Dart SDK MCP configuration
is contributor tooling, not a zaru service.
