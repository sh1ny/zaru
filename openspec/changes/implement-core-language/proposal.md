# Proposal

## Why

M0 established an executable, honest baseline of 0 / 781 jq cases, but `package:zaru` cannot execute even the identity filter. M1 must implement the core jq language, advance every pinned `jq.test` case using only that language, and expose reusable compilation with lazy multi-result evaluation on VM and browsers.

## What Changes

- Add a source-located lexer, Pratt/recursive-descent parser, AST, compiler, lexical environments, typed errors, and lazy closure-tree execution, following ADRs 0001 and 0002.
- Implement identity, access/indexing/slicing/optional access, iteration, pipe/comma/grouping, literals/constructors, arithmetic/comparison/boolean/alternative operators, conditionals, bindings/destructuring, reduction/foreach, functions/filter parameters/recursion, recursive descent, interpolation, error handling, and lexical labels/break.
- Supply the M1 generator/control functions `empty`, `select`, `not`, `error`, `limit`, `first`, `last`, `nth`, `until`, `while`, `repeat`, and `range`; preserve upstream jq definitions where applicable.
- Expose `Zaru.compile`, compiled-filter `run(input, args: ...)`, `Zaru.toJson`, typed errors, and the approved narrow `ZaruNumber` boundary. Add lossless `Zaru.fromJson` decoding so precision is retained before evaluation.
- Replace M0's deliberate per-case failure with execution and strict result comparison, retain all 781 cases in the denominator, and record a non-regressing passed-case floor. Define the core-only acceptance set without skipping remaining cases.

## Capabilities

### New Capabilities

- `filter-compilation`: Source-located jq compilation, lexical binding resolution, reusable filters, and compile diagnostics.
- `filter-execution`: Lazy jq streams, core expressions/control/functions, JSON-shaped inputs, printing, and typed runtime/control-flow behavior.
- `conformance-accounting`: Pinned upstream execution, exact stream comparison, core-only acceptance coverage, and monotonic pass accounting.

### Modified Capabilities

None. The repository has no main capability specifications yet.

## Impact

Implement the existing empty library entrypoint and add code under `lib/src/{lexer,parser,ast,compiler,runtime,builtins,format}`; extend `test/unit`, the existing conformance runner, API/compatibility docs, changelog, and a runnable library example. Keep `lib/` pure Dart and core runtime dependencies at zero. The version-only CLI remains unchanged until M3; non-core builtins, module loading, CLI flags, product MCP server, and benchmarks remain outside M1. The user approved a narrow exact-number type after a Dart smoke check demonstrated that native numbers lose upstream literal digits; ordinary values remain plain Dart.
