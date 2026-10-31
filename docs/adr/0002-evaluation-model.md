# ADR 0002: Lazy closure-tree evaluation

Status: accepted architecture; not implemented in M0.

## Context

A jq filter can yield zero, one, or many results. Pipes compose generators;
backtracking explores alternatives rather than returning a single value. Update
operators additionally need the paths selected on the left-hand side, not merely
the selected values. The core must run on the Dart VM and in browsers, with no
`dart:io`, native jq dependency, or runtime package dependency.

## Decision

Compile the syntax tree into a tree of closures that produce lazy synchronous
iterables. Each traversal has its own input and lexical environment. Compose
iterators for pipes and alternatives; preserve jq's result ordering, empty output,
and backtracking without eagerly materializing intermediate streams. Runtime
errors propagate during iteration, including after earlier results have appeared.
Do not substitute a bytecode VM before measurements justify one.

Track selection paths explicitly during path-sensitive evaluation. Assignment and
update operators resolve paths against the original input and apply jq's update
semantics; values alone cannot distinguish equal values at different locations.
Updates must not mutate caller-owned lists or maps. Path tracking is an internal
execution mode, not a required wrapper around every public value.

Use ordinary Dart JSON-shaped values at the public value boundary: `null`,
`bool`, `String`, `num`, `List<Object?>`, and string-keyed maps. Keep internal
syntax, environments, paths, and number metadata private.

## Numbers and platform tradeoffs

Preserve a numeric literal's source spelling until its semantics require numeric
computation. VM integers and JavaScript-backed browser integers do not have the
same exact range, and converting a large literal to `double` can irreversibly
round it. A private numeric representation retaining the lexeme and, where needed,
an exact `BigInt` magnitude is justified; requiring a public wrapper for every
JSON value is not. `BigInt` is not itself a plain JSON number.

A future JSON-text boundary must preserve untouched literals. At a plain-Dart
boundary, values that cannot be represented exactly must produce an explicit
precision error, never silently coerce `BigInt` to `double`. Exposing any custom
numeric representation would require a further API decision justified by exact
literal preservation. jq-compatible arithmetic behavior also needs implementation
decisions and VM/browser tests; M0 promises neither.

## Consequences

Closures and lazy iterables favor a simple first implementation, but allocate
iterator state and may cost more than a dedicated VM. Path tracking adds execution
state that must be tested with nested updates and backtracking. Cross-platform
numeric fidelity takes priority over pretending Dart's `num` is identical to jq's
number model. M0 has no compiler, evaluator, update operators, or numeric engine.
