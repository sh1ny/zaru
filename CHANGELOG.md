# Changelog

## Unreleased

- Record the observed M1 conformance result: **358 / 781** jq tests passing
  (11 failed, 412 unsupported, 0 not run, 0 skipped) and **352 / 352** M1
  acceptance cases. The 423 non-passing cases are all
  `explicit-deferred-dependency`: 412 are unsupported constructs (builtins
  beyond M1, update operators, `@format`, `$__loc__`, `import`, `$ENV`) and 11
  are module/`_strindices` programs rejected with an undefined-name compile
  error. `test/conformance/floor.json` now lists the 358 passing IDs, so
  `mise run conformance-gate` rejects any lost pass. README, AGENTS.md and
  docs/compat.md carry the new numerator and the remaining gaps.

- Connect the conformance harness to the engine. `mise run conformance` verifies
  the frozen reference baseline (digests, provenance, the 781 IDs), compiles and
  runs every case with the real engine through `runJson`, compares with the
  fixture oracle and the census's typed termination, and writes
  `build/conformance-report.json`; it fails while any case fails. The new
  `mise run conformance-gate` passes only when every M1-classified case and
  every ID in the committed floor (`test/conformance/floor.json`, currently
  empty) passes, and never accepts a stale report or needs jq. CI splits the
  corpus out of `checks` into the `conformance-gate` and `full-conformance` jobs.
  Browser-safe decision logic lives in `test/support/conformance_*.dart` with
  unit tests; `reference_verify` now shares the baseline verification. The
  README's published `0 / 781` is not changed by this entry.

- Add the M1 helper set and recursive descent: `..`, `recurse/0,1,2`,
  `range/1,2,3`, `while`, `until`, `limit`, `skip`, `first/0,1`, `last/0,1`,
  `nth/1,2`, `repeat`, `tostring` and `error/1`/`select` as the jq definitions.
  The jq-coded ones are the verbatim `src/builtin.jq` text of jq 1.8.2 (commit
  `34f7186b86743a083a589741b6cea95293524108`, MIT) hosted by the compiler and
  lowered only when referenced; `empty`, `not`, `error/0`, `tostring`, `range/2`
  and `last/1` are native. Million-step recursive helpers and `..` over a
  10001-deep array run in constant host stack on the VM, dart2js and dart2wasm.
  Every other jq builtin, `@format`, `$__loc__`, assignment and modules remain
  unsupported. The `0 / 781` baseline is unchanged because the harness is not
  connected.

- Add lexical functions and control flow to the core engine: `def` with filter
  and `$value` parameters (recursion, shadowing, closures over the call site,
  tail calls that keep constant continuation state), `reduce` and `foreach`
  (two- and three-clause, multiple initial states), array/object destructuring
  with `?//` alternatives, and `label`/`break` with a fresh identity per
  activation. Compile diagnostics follow jq's units (a function body and a
  call's filter argument are checked only when the enclosing code is clean;
  unused definitions are dropped; a definitions-only program is
  `Top-level program not given`). Documented divergence: `try`/`?` never catch a
  `break` (jq 1.8.2 does). `..` and the jq-defined builtins remain unsupported.
  The `0 / 781` baseline is unchanged because the harness is not connected.

- Add the core expression engine: `Zaru.compile`, `ZaruFilter.run` / `runJson`,
  and the public `ZaruCompileError`, `ZaruRuntimeError` and
  `ZaruMissingArgumentError`. It evaluates identity, field/index/slice/iterate
  (with `?`), literals, array/object construction, `|`, `,`, arithmetic,
  comparison, `and`/`or`, `//`, `if`, `try`/`catch`, string interpolation,
  single-variable `as` bindings, external variables, and `empty`, `error`,
  `not`, `select`, on an explicit-continuation backtracking machine with lazy,
  independent iterators, iterative native ingestion and node-owned immutable
  projections. `..`, other builtins, assignment and `@format` fail compilation
  as unsupported (functions, `reduce`/`foreach`, `label` and destructuring were
  unsupported when this entry was written and are now implemented, see above). Adds
  `example/zaru_example.dart` and `mise run example`. The conformance harness is
  not connected, so the `0 / 781` baseline is unchanged.
- Add the public `ZaruNumber` (exact finite jq number with canonical text) and
  `Zaru.toJson` (jq-compatible compact/indented printing, sorted keys, depth
  truncation marker).
- Add private iterative jq-compatible number, JSON decoding, and Unicode
  normalization layers, and a browser-safe exact fixture oracle for tests that
  is separate from runtime equality. The conformance baseline is unchanged.

- Add an internal jq lexer, parser and diagnostic renderer (`lib/src/syntax`):
  UTF-8 byte spans, a syntax tree, Bison-style error recovery and jq's
  excerpt/caret rendering, constant object-key and module-metadata checks, and
  explicit `unsupported` records for deferred syntax. Checked against captured
  jq 1.8.2 output. The parser itself is internal; the baseline is unchanged.

## 0.0.0 — M0 bootstrap

- Establish a pure-Dart package with no runtime package dependencies and a
  version-only CLI. jq parsing and evaluation are not implemented.
- Pin the jq 1.8.2 upstream test corpus: 781 cases, including 19 compile-error
  cases, with original fixtures, provenance, and upstream license notices.
- Add conformance infrastructure and an honest 0 / 781 baseline. Normal tests
  cover infrastructure; the separate conformance task intentionally remains red.
- Define mise tasks and CI for analysis, formatting, tests, conformance,
  Linux/macOS/Windows CLI compilation, and browser-safe Chrome tests.
- Record parser and lazy-evaluation architecture decisions, numeric fidelity
  constraints, compatibility policy, and the future API direction.
- Configure official Dart SDK MCP contributor tooling and install official Dart
  skills. No zaru MCP product server or benchmark is implemented.
- Isolate the SDK MCP installation cache per project to avoid cross-project
  executable-lock failures on Windows.
