# Compatibility baseline

The measured conformance result is **358 / 781 jq tests passing** (0 failed,
423 unsupported, 0 not run, **0 skipped**), from a fresh `mise run conformance`
at the end of M1. All 352 M1-acceptance cases pass; every one of the 423
non-passing cases is classified `explicit-deferred-dependency`. The harness
executes the real engine (`Zaru.compile`, `runJson`; see [the API](api.md)) for
every case. `mise run conformance` prints the measured count of the current tree
and writes the per-case report to `build/conformance-report.json`; the number
above is changed only from such a run, together with the committed floor
(`test/conformance/floor.json`, the 358 passing IDs). An unavailable or
unsupported behavior is a failure, never a skip or a fabricated successful
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

The harness reads the upstream block format and counts every case in the
denominator whether or not zaru implements it. Infrastructure tests can pass
while semantic cases fail, so the semantic runs are separate commands:

```sh
mise run test              # infrastructure and decision tests, no corpus verdict
mise run conformance       # the full corpus: fails while any case fails
mise run conformance-gate  # M1 acceptance: M1 cases and the passed-ID floor
```

### How a case is executed and judged

Both commands share one pipeline, `tool/conformance.dart`. They first verify the
frozen reference baseline (`test/conformance/reference/`): the recorded SHA-256
of the census and classification, the pinned jq 1.8.2 provenance, exactly the
781 stable IDs in each, and every case's recorded facts. They never run jq, never
regenerate the baseline, and delete any earlier report before doing anything
else; a stale `build/conformance-report.json` can never satisfy a run. A changed
payload, a missing or extra ID or an unknown classification exits with status 2
before anything is evaluated.

Each case is then compiled and iterated with the real engine: the fixture input
is decoded with `runJson` (no narrowing of ordinary numbers before evaluation)
and every result is compared as it is produced with the fixture oracle
(`test/support/fixture_oracle.dart`), stopping at the first mismatch or surplus
result. Outcomes are `passed`, `failed` (with a reason code such as
`outputMismatch`, `missingExpectedOutput`, `surplusOutput`,
`unexpectedRuntimeError`, `missingRuntimeError`, `errorValueMismatch`,
`diagnosticMismatch`, `compiledSuccessfully`, `compileError`), `unsupported`
(the compiler reported a valid-jq construct it does not implement; never a
pass, including under `%%FAIL IGNORE MSG`) and `notRun`. The report also records
how each case terminated: exhausted, runtime error, compile error, or not
observed when comparison abandoned a mismatching iterator.

- **Runtime termination** follows the frozen census, not jq_test.c's laxer rule:
  zaru must produce exactly the fixture's output prefix and then the recorded
  termination. An error after the right values that the census did not record
  fails, as does exhaustion where the census recorded an error (the five
  recorded runtime-error cases: the four destructuring cases
  `jq.test:945/949/953/957` and `jq.test:2359`).
- **Compile-error fixtures** pass only if the real compiler rejects the program.
  `%%FAIL` additionally compares the last diagnostic block starting with
  `jq: error` (cut to jq_test.c's 4096-byte buffer) against the expected lines
  with jq_test.c's rule: each expected line is a byte prefix of what remains,
  followed by at most one newline, and nothing may remain. `%%FAIL IGNORE MSG`
  ignores only that text. Errors are never inferred from fixture comments.
- **Nonfinite values** are compared before any printing: NaN is not `null` and
  an infinity is not the clamped maximum double.

### The M1 gate

`mise run conformance-gate` exits zero only if the freshly executed report
accounts all 781 IDs and (a) every **M1 acceptance** case passes and (b) every
ID in the committed floor, `test/conformance/floor.json`, still passes. The M1
acceptance set is read from the frozen classification: the cases classified
`M1-core-candidate` or `core-undefined-name-diagnostic` (both are core, non-
deferred classes; see `docs/compatibility/reference-inventory.md`, task 3.4).
Cases classified `explicit-deferred-dependency` stay in the full report but do
not gate. The classification is frozen before the engine and protected by its
digest: a failing M1 case fails the gate, and weakening a classification
requires a reviewed change to the frozen baseline, never a zaru result. The
floor is a sorted list of previously passing IDs; a lost ID fails the gate even
when another case starts passing and the count is unchanged. It is extended by
reviewed changes only.

The two commands agree on facts and differ in policy: the gate can pass while
`mise run conformance` stays red for later-milestone cases. Their exit codes are
0 (success), 1 (a conformance failure) and 2 (an unusable baseline, floor or
invocation). CI runs them as the `conformance-gate` and `full-conformance` jobs.

### Remaining gaps, from the observed run

Of the 423 cases that do not pass (291 in `jq.test`, 132 in `man.test`), all are
classified `explicit-deferred-dependency` in the frozen classification; none was
reclassified and none is skipped (the report records 0 skipped, 0 not run).

**423 unsupported** (the compiler rejects valid jq it does not implement; each
is a distinct `zaru: unsupported:` diagnostic, never a jq error). Counted by
the kinds of construct named; a case can name several:

| Deferred category | Cases |
| --- | ---: |
| jq builtins beyond the M1 set (106 distinct names; most frequent `map/1` 39, `contains/1` 27, `tojson/0` 16, `nan/0` 13, `indices/1` 12, `path/1` 11, `length/0` 10, `setpath/2` 10, `have_decnum/0` 10), including the private `_strindices/1` | 360 |
| Assignment and update operators (`=`, `\|=`, `+=`, `//=`, ...) | 51 |
| `@format` strings (`@text`, `@base64`, `@base64d`, `@html`, `@uri`, `@urid`, `@sh`, ...) | 11 |
| `$__loc__` | 3 |
| Module loading (`import` and `include` directives) | 10 |
| `$ENV` | 1 |

No case fails outright. Programs that import or include modules are
unsupported as a whole, because jq resolves their names only after linking the
modules; zaru does not report those names as undefined. jq's private builtins
(`_strindices`, `_match_impl`, the `_plus`-style operator bindings and the
other `_`-prefixed names that `builtins` omits) are classified the same way as
public builtins, so `jq.test:1553` and `jq.test:1557` are unsupported too.

## Implementation gaps, not intentional divergences

Implemented (core engine, covered by `test/unit` and checked against captured
jq 1.8.2 output, not by conformance cases): identity, field/index/slice/iterate
and their `?` forms, literals, array and object construction, `|`, `,`,
arithmetic, comparison, `and`/`or`/`not`, `//`, `if`/`elif`/`else`,
`try`/`catch`, string interpolation, `as` bindings with array/object
destructuring and `?//` alternatives, `reduce`, `foreach`, `def` with filter and
`$value` parameters (recursion, shadowing, closures), `label`/`break`, external
variables, `..`, and the builtins `empty`, `not`, `error/0,1`, `tostring`,
`select`, `recurse/0,1,2`, `range/1,2,3`, `while`, `until`, `limit`, `skip`,
`first/0,1`, `last/0,1`, `nth/1,2` and `repeat`. Interpolation is the only use of
the text format; `format` itself is not a public callable. The jq-coded ones run
the verbatim `builtin.jq` definitions (see
[builtin provenance](compatibility/builtin-provenance.md)), so `repeat(f)` is the
pinned `def _repeat: f, _repeat;`, which applies `f` to the same input again and
again (`1 | limit(3; repeat(. * 2))` is `2, 2, 2`).
Their error messages, generator order and the depth/size limits (equality,
ordering and merge at depth 10000; string repetition below 2147483647 UTF-8
bytes) follow the pinned jq. Known behavior to keep in mind: errors in the left
side of `//` are not suppressed (as in the pinned jq), and a slice or index
with a fractional or out-of-range bound follows jq's clamping and truncation.

Not implemented, and therefore compile-time *unsupported* errors rather than
results: every builtin outside the list above (including `map`, `length`,
`keys`, `add`, `infinite`, `isempty`, `all`, `any` and `path`; jq's own
`builtins` list is embedded only to tell these apart from undefined names),
assignment and update operators, `@format`, `$__loc__`,
`$ENV`, path expressions, modules, input/output builtins, and the CLI. None of
these gaps is an intentional change to jq semantics. An unsupported source can
never satisfy a compile-error fixture: its diagnostics start with
`zaru: unsupported:`.

The number, JSON-text decoding, and printing layers are an exception to the
"not implemented" list only as library building blocks: `ZaruNumber`,
`Zaru.toJson`, and an internal jq-compatible decoder exist and are covered by
direct unit tests, not by conformance cases. They do not make any jq filter
work by themselves. Known limitation: a numeric
literal with more than 147483648 coefficient digits is not rounded to jq's
decimal context precision. The tests' fixture oracle compares finite numbers as
exact decimals; that is a test-infrastructure judgment, distinct from jq's
runtime equality.

The syntax layer is a second exception, again only as an internal building
block (`lib/src/syntax`, not exported). It lexes and parses jq programs into a
tree and reports jq's parse-time diagnostics; no filter is compiled or run, so
it changes no conformance result by itself. What it does:

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
  program, module lookup). `Zaru.compile` reports the first four after the
  parser, as semantic errors (a program of only definitions is
  `Top-level program not given (try ".")`); module lookup is not diagnosed. Invalid numeric
  literals are not diagnosed. The
  folder caps a folded string repetition at 1 MiB and treats larger ones as
  non-constant.

A compile-error fixture does not pass merely because the compiler rejects the
program: it must produce the expected diagnostic (unless it is `IGNORE MSG`) and
an unsupported construct is never a pass. Unsupported behavior stays in the
denominator. The harness has no skip mechanism and reports zero skips; if one is
ever introduced it needs a specific documented reason in
`test/conformance/skip.txt`, and missing implementation is not a reason.

## Intentional divergences

- **`break` is not catchable.** Pinned jq 1.8.2 implements `break $x` as an
  error carrying the label, so `try` and `?` around it can catch it:
  `[label $x | try (1, break $x, 2) catch "caught"]` prints `[1,"caught"]`
  there, and `[label $x | try break $x catch .]` yields the internal label
  object `{"__jq":0}`. zaru follows the change's design decision (D3) and the
  filter-execution requirement that a lexical break is control flow, not a data
  error: the same filters yield `[1]` and `[]`. Programs that break to a label
  from outside every `try`/`?` around the label's body, which includes every
  jq-defined builtin and both fixture corpora, behave identically. This was
  observed against the pinned reference and is not hidden by a skip.
- **Syntax depth is bounded (resource bound).** zaru rejects a program whose
  syntax tree is deeper than `maxSyntaxDepth` (256) levels with a typed
  `ZaruCompileError` (`isUnsupported` false) instead of overflowing the host
  stack: `zaru: error: program nests deeper than 256 levels at <top-level>,
  line L, column C:` followed by the usual excerpt and caret. Depth counts
  genuine nesting: brackets, constructors, `if`, `reduce`, `foreach`, `try`,
  `def` bodies, function arguments, bindings, and postfix, arithmetic,
  comparison, logic and `//` chains such as `1+1+1` and `.a.b.c`: `((.))` and
  `1+1` are 3 and 2 levels. Pipe (`|`) and comma (`,`) chains do not count:
  zaru reads, lowers and evaluates them with loops, so `[0,1,...,9999]`, a
  10000-step `.|.|...` and a 10000-entry object are accepted. This is an
  intentional improvement over jq, whose grammar recurses per `|` and fails
  with `memory exhausted` at 5000 pipe steps. Pinned jq also accepts deeper
  nesting elsewhere: its Bison stack fails only at 10000 nested parentheses.
  The bound is measured, not arbitrary: parsing, lowering and running a program
  of the worst nesting shape (nested string interpolation) succeeds up to about 400
  levels on dart2wasm, 600 to 800 on dart2js and 800 to 1000 on the VM, and
  every program in both pinned corpora is at most 12 levels deep. As a safety
  net, a host stack overflow while compiling is converted to a typed
  `zaru: error: program is too deeply nested to compile` error on the VM and
  dart2js; dart2wasm cannot recover from a stack overflow, so there only the
  depth budget protects.
- **Rendered diagnostics are bounded (resource bound).** jq renders every
  diagnostic in full, each with its whole source line, so 20000 undefined names
  print over a gigabyte. zaru renders at most `maxRenderedDiagnosticBytes`
  (1 MiB) of diagnostic text per report, always including the first block, then
  stops and appends one block, `zaru: error: N more diagnostics omitted`
  (which never starts with `jq: error`, so `lastJqError` ignores it). It also
  shows at most `maxExcerptBytes` (240) bytes of a source line: a longer line
  is cut to a window around the span with `...` at each cut end and the carets
  aligned to the window. Lines that fit, and reports that fit the budget, are
  rendered exactly as jq does, byte for byte; `DiagnosticReport.diagnostics`
  stays the complete structured list.

## Deliberate scope boundaries

The product is intended to be a pure-Dart library and CLI with zero runtime
package dependencies. Its library must not import `dart:io`; CLI and test tooling
may use I/O. The planned API uses ordinary Dart JSON-shaped values, with explicit
handling of numeric precision boundaries rather than silent browser/VM rounding.
See [the API direction](api.md) and [ADR 0002](adr/0002-evaluation-model.md).

The CLI supports `--version` only. There is no benchmark or MCP product server,
and the evaluator covers only the subset above. These are scope statements, not claims of jq compatibility. The
only intentional jq-language semantic divergence is the `break` one listed
above (the two resource bounds do not change what a program means); any
future one must be documented explicitly and kept distinguishable from
implementation gaps. The selected corpus measures that pinned baseline, not every possible jq
program or all releases of jq.
