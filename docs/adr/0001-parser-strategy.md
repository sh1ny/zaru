# ADR 0001: Hand-written jq parser

Status: accepted architecture; not implemented in M0.

## Context

jq is an expression language, not a sequence of JSON lookups. Its grammar includes
pipes, comma generators, precedence-sensitive operators, function definitions,
bindings, conditionals, reduction, interpolation, and update assignments. A parser
must retain source locations and numeric spellings without making the pure-Dart
library depend on code generation or runtime packages.

## Decision

Use a hand-written lexer and parser. Use Pratt parsing for expression precedence
and associativity, and recursive descent for grammar productions such as
`def`, `if`, `try`, `reduce`, `foreach`, patterns, and argument lists. Keep the
binding-power table explicit and test ambiguities against the pinned jq corpus.
Do not parse jq by splitting strings or translating it into Dart expressions.

Tokens carry source spans. Numeric tokens retain their original lexeme rather
than immediately converting through `double`; interpolation is parsed as jq
expressions with correctly nested string boundaries. The parser produces an
internal syntax tree, not executable host-language source. Syntax diagnostics
will identify the source span and expected construct.

## Consequences

This keeps precedence, diagnostics, and source fidelity under project control,
with no generated-parser toolchain or runtime dependency. The cost is maintaining
the grammar and precedence table ourselves. Focused lexer/parser tests and the
upstream conformance corpus are required before claiming syntax support.

Parser generators remain a rejected alternative for now: their extra toolchain
and generated output do not remove the need to model jq-specific grammar and
literal semantics. A single Pratt loop is also insufficient for jq's structured
forms; recursive descent handles those explicitly.

M0 only establishes this decision and the conformance baseline. There is no
lexer, parser, compilation API, or supported filter syntax yet. Evaluation and
number-representation boundaries are covered in [ADR 0002](0002-evaluation-model.md).
