# Compatibility baseline

The conformance baseline is **0 / 781 jq tests passing**. The core engine
(`Zaru.compile`, `run`, `runJson`; see [the API](api.md)) now evaluates a small
subset of jq, but the conformance harness is **not connected to it yet**, so
every case is still scored as unimplemented and the number is unchanged. It is
an honest unmeasured baseline, not an assertion that the upstream suite has
been satisfied, and it does not claim that any particular fixture passes. An
unavailable evaluator is a failure, never a skip or a fabricated successful
result.

## Pinned upstream corpus

The checked-in fixtures come from [jq 1.8.2](https://github.com/jqlang/jq/tree/jq-1.8.2),
commit `34f7186b86743a083a589741b6cea95293524108`:

| Fixture | Cases |
| --- | ---: |
| `test/conformance/jq.test` | 550 |
| `test/conformance/man.test` | 231 |
| Total | 781 |

The total includes 19 compile-error cases. `man.test` is a tracked upstream file;
its historical generation from jq documentation does not mean these fixtures
were regenerated locally. The upstream `COPYING`, `VERSION`, and
`PROVENANCE.json` beside the fixtures record license and provenance information.
The zaru MIT license does not replace upstream notices.

The harness reads the upstream block format and counts cases independently of
whether zaru implements them. Infrastructure tests can pass while all semantic
cases fail. The `conformance` task is deliberately separate from the normal test
task and is expected to exit unsuccessfully until the harness is connected to the
engine and the engine is complete.

```sh
mise run test
mise run conformance
```

## Implementation gaps, not intentional divergences

Implemented (core engine, covered by `test/unit` and checked against captured
jq 1.8.2 output, not by conformance cases): identity, field/index/slice/iterate
and their `?` forms, literals, array and object construction, `|`, `,`,
arithmetic, comparison, `and`/`or`/`not`, `//`, `if`/`elif`/`else`,
`try`/`catch`, string interpolation, single-variable `as` bindings, external
variables, and the builtins `empty`, `error`, `error(f)`, `not` and `select(f)`.
Their error messages, generator order and the depth/size limits (equality,
ordering and merge at depth 10000; string repetition below 2147483647 UTF-8
bytes) follow the pinned jq. Known behavior to keep in mind: errors in the left
side of `//` are not suppressed (as in the pinned jq), and a slice or index
with a fractional or out-of-range bound follows jq's clamping and truncation.

Not implemented, and therefore compile-time *unsupported* errors rather than
results: function definitions and calls, `reduce`, `foreach`, `label`/`break`
semantics, destructuring and `?//`, `..`, every builtin other than the five
above (jq's own `builtins` list is embedded only to tell these apart from
undefined names), assignment and update operators, `@format`, `$__loc__`,
`$ENV`, path expressions, modules, input/output builtins, and the CLI. None of
these gaps is an intentional change to jq semantics. An unsupported source can
never satisfy a compile-error fixture: its diagnostics start with
`zaru: unsupported:`.

The number, JSON-text decoding, and printing layers are an exception to the
"not implemented" list only as library building blocks: `ZaruNumber`,
`Zaru.toJson`, and an internal jq-compatible decoder exist and are covered by
direct unit tests, not by conformance cases. They do not make any jq filter
work by themselves and do not change the `0 / 781` baseline. Known limitation: a numeric
literal with more than 147483648 coefficient digits is not rounded to jq's
decimal context precision. The tests' fixture oracle compares finite numbers as
exact decimals; that is a test-infrastructure judgment, distinct from jq's
runtime equality.

The syntax layer is a second exception, again only as an internal building
block (`lib/src/syntax`, not exported). It lexes and parses jq programs into a
tree and reports jq's parse-time diagnostics; no filter is compiled or run, so
it changes no conformance result and the `0 / 781` baseline stands. What it does:

- Positions are one-based UTF-8 byte offsets with exclusive ends. An excerpt
  shows the first line of a span, with carets right-justified like jq's
  `locfile_locate`. The end-of-file location is the last lexer piece.
- Syntax errors name the unexpected token and, when Bison would, up to four
  expected tokens in jq's symbol order. The parser reproduces Bison's error
  recovery (the `error` productions, suppression of messages for the next three
  shifts, abort at end of input), so one program can yield several ordered
  diagnostics, including `May need parentheses around object key expression`,
  `try .["field"] instead of .field ...`, `break requires a label ...` and
  `Possibly unterminated 'if'/'try' statement`.
- Constant non-string object keys (`{(0): 1}`, also in destructuring patterns),
  non-constant or non-object module metadata and non-constant import paths are
  reported with jq's messages, using a constant folder that follows jq's
  `block_is_const`/`constant_fold` for literals, arrays, objects, arithmetic
  and comparisons. Fold results that would fail at run time are not constants.
- `@format`, assignment and update operators, `$__loc__`, `module`, `import`,
  `include` and `ns::name` parse, and are recorded as `unsupported` constructs.
  They are a distinct category: never a jq error, never a pass for a
  compile-error fixture.
- Expected-token lists and recovery spans were verified differentially against
  403 rejected and 129 accepted programs captured from the pinned jq 1.8.2
  (`test/unit/diagnostic_snapshots.dart`), not derived from Bison's tables, so
  an input outside that sample may still differ.
- Not produced at parse level: errors that jq finds only after a clean parse
  (undefined `$name`, `f/N is not defined`, unknown label, a missing main
  program, module lookup). `Zaru.compile` reports the first three after the
  parser, as semantic errors; the rest are not diagnosed. Invalid numeric
  literals are not diagnosed. The
  folder caps a folded string repetition at 1 MiB and treats larger ones as
  non-constant.

A compile-error fixture does not pass merely because M0 rejects all execution:
it must eventually produce the expected compiler behavior. Unsupported behavior
stays in the denominator. Skips require a specific documented reason in
`test/conformance/skip.txt`; missing implementation is not a reason to skip.

## Deliberate scope boundaries

The product is intended to be a pure-Dart library and CLI with zero runtime
package dependencies. Its library must not import `dart:io`; CLI and test tooling
may use I/O. The planned API uses ordinary Dart JSON-shaped values, with explicit
handling of numeric precision boundaries rather than silent browser/VM rounding.
See [the API direction](api.md) and [ADR 0002](adr/0002-evaluation-model.md).

The CLI supports `--version` only. There is no benchmark or MCP product server,
and the evaluator covers only the subset above. These are scope statements, not claims of jq compatibility. No
intentional jq-language semantic divergence has been established in M0; any future
one must be documented explicitly and kept distinguishable from implementation
gaps. The selected corpus measures that pinned baseline, not every possible jq
program or all releases of jq.
