# Hosted builtin provenance

zaru does not reimplement jq's jq-coded helpers; it hosts jq's own definitions.
`lib/src/engine/jq_builtins.dart` holds the text of each definition, copied
unchanged (including whitespace) from `src/builtin.jq` of the pinned reference:

- jq 1.8.2, upstream commit `34f7186b86743a083a589741b6cea95293524108`
  (<https://github.com/jqlang/jq/blob/34f7186b86743a083a589741b6cea95293524108/src/builtin.jq>)
- License: MIT, Copyright (c) 2012 Stephen Dolan (the pinned tree's `COPYING`)

The compiler parses a definition with zaru's own parser the first time a program
references its `name/arity`, lowers it once per compilation in a scope that
contains only other builtins, and calls it through `BuiltinCallOp`. A program's
own definitions therefore cannot capture or shadow what a builtin calls, and a
program that never mentions a helper pays nothing for it. A user `def` of the
same `name/arity` shadows the builtin for the user's code only.

| Builtin | `builtin.jq` lines | Direct dependencies |
| --- | --- | --- |
| `error/1` | 2 | native `error/0` |
| `select/1` | 4 | native `empty` |
| `recurse/1` | 37 | local `r/0` |
| `recurse/2` | 38 | local `r/0`, `select/1` |
| `recurse/0` | 39 | `recurse/1` |
| `range/1` | 73 | native `range/2` |
| `while/2` | 135-138 | `empty` |
| `until/2` | 139-142 | none |
| `limit/2` | 143-146 | `foreach`, `label`/`break`, `empty`, `error/1` |
| `skip/2` | 147-150 | `foreach`, `empty`, `error/1` |
| `range/3` | 152-155 | `while/2`, `empty` |
| `first/1` | 156 | `label`/`break` |
| `nth/2` | 164-166 | `skip/2`, `first/1`, `error/1` |
| `first/0`, `last/0`, `nth/1` | 167-169 | indexing |
| `repeat/1` | 185-188 | local `_repeat/0` |

`repeat/1` is the pinned text, `def _repeat: exp, _repeat;`. It re-applies `exp`
to the same input forever (`1 | limit(3; repeat(. * 2))` is `2, 2, 2` on the
pinned binary), not the `., (exp | _repeat)` form of other jq versions; the
verbatim text is what the pinned `jq` runs, and `man.test:654` agrees.

Native operations, matching jq's own non-jq-coded definitions:

- `empty`, `not`, and `last/1` and `range/2` (bytecoded in `src/builtin.c`,
  `gen_last_1` and the `RANGE` opcode): `last(f)` yields nothing for an empty
  `f`; `range(a; b)` yields `a` itself (keeping its literal spelling) and then
  each successor by one while it is below `b`, with the start varying slowest
  and `Range bounds must be numeric` for a non-number.
- `error/0` and `tostring` (C functions). `format` is only the implicit
  dependency of string interpolation and is not callable.

Probes against the pinned binary for the recorded behavior (range products,
fractional `limit`/`skip` counts, `nth` and `limit` negative-count messages,
`last` of an empty stream, `repeat`) are in `test/unit/generators_test.dart`.
Every other jq builtin remains unsupported.
