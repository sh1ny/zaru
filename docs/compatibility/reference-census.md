# Native jq reference census

The reference census is development tooling for recording observations from the
pinned jq 1.8.2 native implementation. It is not an evaluator, a compatibility
claim, or a test-time dependency. The reusable zaru library remains pure Dart;
normal unit tests, CI, and conformance runs must not invoke jq or regenerate this
census.

## Inputs and execution

`mise run reference-census` runs `dart run tool/reference_census.dart` with the
checked-in destination `test/conformance/reference/census.json`. To choose a
different destination, pass `--output PATH`. A probe captures one raw request
without changing its program or JSON input:

```json
{"program":"1, error(\"bad\")","input":"null"}
```

```sh
mise run reference-census -- --probe request.json --output result.json
```

A probe may include `expectedPrefix` as an additional exact assertion. `--jq`,
`--source`, and `--modules` are diagnostic overrides, not trust overrides: each
must continue to match the pinned manifest/provenance. A changed or missing
input, executable, driver, or module fails closed and does not publish a result.

The manifest `.dart_tool/reference/native-build.json` records the pinned source
archive and commit, compiler/configuration, project-relative input hashes, and
hashes/paths for the source-built jq executable, shared C capture driver, static
library, and driver source. On Windows, one WSL invocation executes the whole
NDJSON batch; on POSIX, the native driver runs directly. Both receive a minimal
explicit environment (`LC_ALL=C`, `PAGER=less`, a fixed system `PATH`, and the
pinned module search path). No host-private path or inherited credential is part
of recorded provenance. The driver captures C API facts and independently
executes the corresponding source-built jq CLI for every request. The census
rejects missing records, unexpected process termination, CLI/C API disagreement,
fixture-output mismatches, and inconsistent compile/runtime classifications.

Every fixture request retains the original filter and raw input/output text.
The evaluation fixture's expected values are sent as raw strings for jq's own
value-equality comparison. Compile-error fixtures are compiled from the original
filter and use `null` as their unused input; their diagnostic blocks are native
callback output, never reconstructed from fixture comments. Each stable ID is
`<fixture-file>:<program-line>`; all 550 `jq.test` and 231 `man.test` rows,
including all 19 compile-error cases, are required for a full census.

Fixture acceptance mirrors pinned `src/jq_test.c`, not a stricter local rule.
A compile-error fixture must fail compilation. When it checks its message, the
census keeps the last callback message beginning with `jq: error` (within the
4096-byte buffer), consumes it with each expected line as a byte prefix
followed by at most one newline, and rejects any remainder. An evaluation fixture
must compile and yield exactly the expected values by jq's `jv_equal`; an
uncaught runtime error after those values is accepted, as jq_test only fails a
superfluous valid result. The census records that terminal error rather than
hiding it: the first full capture observed 757 exhausted, 5 runtime-error, and
19 compile-error terminals.

Like upstream `tests/jqtest`, the driver receives an absolute module directory;
relative search paths resolve differently for nested imports. The only recorded
transformation is that the host's absolute module prefix is rewritten to
`tests/modules/` in captured text (for example, the module syntax-error location),
so the census contains no host-specific path. Provenance records this rewrite.

## Typed observations

`outputPrefix` and `outputKinds` record the C API result stream before terminal
status. `outputNumberKinds` uses `literal`, `computed`, `nan`,
`positiveInfinity`, and `negativeInfinity` (the same names as the wire tags); `outputWire` stores the complete lossless tagged representation
as JSON text, including nested kinds and numeric text. Runtime errors preserve
`errorWire`, the native printed error text, and its root kind/number-kind. The
convenience `errorValue` is present only when the tagged value can be projected
to JSON-shaped Dart values without numeric narrowing. Absence of that convenience
field does not mean the error was absent; `terminal` and `errorWire` are
authoritative, including for a `null` error payload.

## Integrity and regeneration

The census and source classification are generated evidence, not ordinary test
fixtures. A frozen revision must retain SHA-256 integrity metadata for both
artifacts, the source/build provenance, and a reviewed change showing why each
regeneration is needed. Review the full stable-ID set and output/diagnostic diff;
never update expected observations merely to make tests pass.

The frozen baseline is `test/conformance/reference/census.json` plus
`classification.json`, with their SHA-256 digests in `integrity.json`; all three
are byte-exact (`-text` in `.gitattributes`). `mise run reference-verify` checks,
without starting jq or the native driver, that both digests match, the pinned
jq version/commit/archive provenance, exactly the 781 stable IDs in each artifact
with no duplicates, and every case's facts against its fixture kind:
compile-error fixtures and only they end in `compileError` with diagnostics and
no output; runtime errors and only they carry an error wire; evaluation fixtures
yield exactly the fixture's output count with jq's own comparison passing. The
ordinary test suite runs this check and its tamper/missing-ID/changed-fact
regressions (`test/conformance/reference_integrity_test.dart`).
The `conformance` and `conformance-gate` commands run the same verification
(`verifyBaseline`, shared with this tool) before evaluating anything, so a
changed payload is rejected by every consumer. After a
reviewed regeneration, `mise run reference-freeze` records the new digests and
then runs the same verification. Classification remains source-only.

Regeneration requires the verified source archive/build and all module fixtures.
Download the release asset
`https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-1.8.2.zip` to
`.dart_tool/reference/jq-1.8.2.zip` (SHA-256
`332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c`) and extract
it under `.dart_tool/reference/`. `mise run reference-setup` verifies the archive
hash and every extracted member, then builds jq, the static library, and the
capture driver out of tree. On Windows it requires WSL with `gcc`, `make`,
`unzip`, and `sha256sum`. Setup refuses to overwrite outputs it did not record:
after changing `tool/reference_capture.c` or the toolchain, delete
`.dart_tool/reference/{build-jq-1.8.2,native-build.json,reference_capture}` and
`.dart_tool/reference/jq-1.8.2/{jq,.libs}` before rerunning it. The reference
tools hash files in process with `tool/sha256.dart`, so no platform hashing
command participates in provenance. Then run the reference census task
explicitly. Do not run either from ordinary tests, CI, or
conformance commands. The generated census is only suitable for freezing after
the integrating owner has reviewed and validated the complete output and its
separate SHA-256 metadata.
