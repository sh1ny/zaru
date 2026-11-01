# Architecture index

This index points to the accepted and planned architecture decisions for zaru. OpenSpec change decisions constrain implementation only where the corresponding change is active; this index does not claim that planned behavior is implemented.

## Accepted decisions

- [ADR 0001: Parser strategy](../docs/adr/0001-parser-strategy.md) — source-located lexer, Pratt parsing, recursive-descent grammar, and source-preserved literals.
- [ADR 0002: Lazy closure-tree evaluation](../docs/adr/0002-evaluation-model.md) — lazy evaluation, per-traversal state, path-aware evaluation, and the M0 numeric proposal. Its numeric proposal is superseded by ADR 0003; the rest remains in force.
- [ADR 0003: Exact numbers at the jq boundary](../docs/adr/0003-numeric-boundary.md) — approved narrow public `ZaruNumber` exception, origin-aware private values, native and `runJson` ingestion, arithmetic/comparison distinction, and target-specific numeric boundaries.

## Active implementation design

The [implement-core-language OpenSpec design](changes/implement-core-language/design.md) contains the binding detailed decisions for this milestone. Numeric semantics and their relationships to Unicode and deep codec/projection behavior are in D4, D7, and D8. Pre-engine reference census and strict accounting are in D6; cross-target test and CI policy is in D9. Consult those decision sections rather than duplicating their full limits and examples in an ADR.
