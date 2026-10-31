# Review — round 3 (fresh independent Claude pass)

## Metadata

- **Target:** `implement-core-language` (M1 core language) in the same checkout `F:/Dev/Orca/Workspace/zaru`: parent `d4a10cf75f51c0aaade6f86d9fbb4a2f7742577f` plus the current uncommitted revisions of `proposal.md`, `design.md`, `tasks.md` and the three delta specs, read from the filesystem.
- **Reviewer:** Claude, dispatched through Orca (task `task_bbd940f8395a`, dispatch `ctx_1245fc6f36c3`).
- **Model:** `claude-opus-5-5`, as stated by the runtime system context. **Effort:** unknown.
- **Mode:** Read-only plan review. This report is the only file I created. I changed no other repository file, branch, bookmark or setting. I ran no Dart tests, builds, analyzer or formatters, and implemented nothing. I did not read authoring transcripts.
- **Order:** I did my own pass first, then compared against `review-claude.md` and `review-claude-round-2.md`. `review.md` (older Codex approval) is stale and was not relied on.
- **Read in full:** `proposal.md`, `design.md`, `tasks.md`, `specs/{filter-compilation,filter-execution,conformance-accounting}/spec.md`, both earlier Claude reports, `AGENTS.md`.
- **Repository context:** `test/conformance/{jq.test,man.test,PROVENANCE.json}`, `.github/workflows/ci.yml`, `mise.toml`.
- **Pinned upstream sources:** A read-only copy of jq commit `34f7186b…` outside the repository (`%TEMP%/jqsrc`): `jv_parse.c`, `jv_print.c`, `jq_test.c`, `builtin.jq`, `builtin.c`. I did not re-verify that copy's hashes.
- **Native probes:** Read-only probes with the locally installed `jq-1.8.2` (scoop), run from `%TEMP%`, outside the checkout. Its provenance against the pinned commit was not verified beyond `--version`.
- **Mechanical check:** A throwaway shell comparison of spec scenarios with test-map rows. It found 88 scenarios and 88 rows, and every row's requirement, scenario and test name match exactly (17 compilation, 48 execution, 23 accounting).

## Independent assessment

The revised plan holds together. The round-3 changes are coherent, and I verified them against jq 1.8.2:

- **`runJson` keeps literal origin.**
  - Probes: `echo 42 | jq '. == 42.0000000000000001'` gives `false`, while `(.+0) == 42.0000000000000001` gives `true`.
  - `run` treats native numbers as computed and `runJson` treats them as literal. Both feed the same evaluator and narrow only at export. That reproduces jq's literal/literal and computed/literal rules, and ordinary public 42 is not boxed.
  - Removing the public `fromJson` decoder is the right fix. That decoder would have narrowed to plain `num` before evaluation and lost the origin. No new value hierarchy is introduced.
- **Native `1e23`.** It is computed, so it stays plain. Probe: `(1e23+0) == 1e23` gives `true`, which matches the scenario "Native large-double comparison uses fallback".
- **Negative zero.**
  - Probes: `echo -0 | jq -c .` gives `-0`. `jq -n '-0'` gives `0`. `echo 0 | jq -- '-.'` and `echo -0 | jq -- '-.'` both give `0`. `(0+0)|-.` gives `-0`.
  - The classification rule gives C = P(D) = `-0`, so the value is plain. D4 ("negating literal zero yields positive zero; computed negation follows binary64") matches the probes exactly.
- **Surrogates.**
  - Escaped `"\ud800"` is rejected ("Invalid \uXXXX\uXXXX surrogate pair escape").
  - `"\udc00"` becomes U+FFFD.
  - Raw invalid UTF-8 for a surrogate (`ED A0 80`) becomes one U+FFFD.
  - All three match D7 and the surrogate scenario.
- **Census anchors.** `jq.test:945` outputs nothing, and jq exits 5 with `Cannot index array with string ("a")`. That confirms the anchor and the incorrect `"c"` comment.
- **Diagnostics.**
  - `{1+2:3}` emits `unexpected LITERAL` and then `May need parentheses…`.
  - `.\n]` emits a line-2 error and then a line-1 error.
  - `"éé" | $x` reports column 10, a UTF-8 byte column.
  - The first-diagnostic and last-`jq: error`-block policy (D3, the "Missing key parentheses" scenario, the "callback" scenario) is consistent with `jq_test.c`.
- **Tail recursion.** In the pinned `builtin.jq`, `repeat` recurses in the comma RHS (`:185`). `while` recurses in the pipe RHS inside `if` (`:135-138`). `range/3` is defined over `while` (`:152-155`). So the million-step rows exercise all three tail positions D2 names. Probe: a 10⁶-deep `def f: if . > 0 then .-1|f else . end` completes.
- **Conformance oracle.** The non-finite oracle rule agrees with `jq_test.c:208` (`jv_equal` on the parsed expectation, with no printing).
- **N3.** The native-tool-managed reference census and the jq-free fresh zaru conformance/gate commands are now cleanly separated (D6, the gate requirement, task 7.3, the `gate_process_test.dart` row).

Three moderate gaps remain. They come from boundaries the round-3 changes newly made public (`runJson` and `toJson` at depth, export narrowing) and from the existing CI shape.

## Findings

### Critical (blocking)

None.

### Moderate

**R1 — `runJson`, export and `toJson` have no specified depth behavior or stack-safety contract, although pinned jq defines both limits and the corpus tests them.**

- **Upstream evidence.**
  - `jv_parse.c:14-15,161,167` sets `MAX_PARSING_DEPTH (10000)` and returns `Exceeds depth limit for parsing`. Probe: 10000 nested `[` parse, and 10001 fail with that message.
  - `jv_print.c:20-21,227-228` sets `MAX_PRINT_DEPTH (10000)` and emits `<skipped: too deep>`.
  - `jq.test:2563` and `jq.test:2568` assert both behaviors through `tojson`/`fromjson`, which share the decoder and printer that M1 builds and exposes publicly.
- **What the plan says.** D7 says only "pinned jv_parse grammar". The printer requirement says "jq-compatible". The Resource Bounds table and the structural-limits requirement cover equality, ordering, merge, descent and native normalization, but not the `runJson` decoder, export narrowing, or `toJson`.
- **Consequences.**
  - A natural recursive Dart decoder or printer overflows on Chrome/dart2js well below 10000 levels. A host `StackOverflowError`/`RangeError` would then escape where jq succeeds or raises a parse error. That violates D3's "host exceptions are never translated" and the VM/dart2js/wasm parity goal.
  - `runJson` would accept depths that jq rejects.
  - The public `toJson` behavior beyond 10000 levels would be frozen by accident before M2's `tojson` has to match `jq.test:2568`.
  - The "Deep descent is not structural equality" scenario does not say how its 10002-node input is built. Given through `runJson`, jq would reject it.
- **Correction.**
  1. Specify that the `runJson` decoder enforces jq's 10000 parsing depth and raises `FormatException` carrying jq's message at depth 10001. Add rows at 10000 and 10001.
  2. Decide explicitly how `toJson` behaves beyond `MAX_PRINT_DEPTH`. Either reproduce `<skipped: too deep>`, or record an intentional divergence in `docs/compat.md` with a reason and a typed error. Add a row either way.
  3. Require the decoder, the export narrowing and `toJson` to be iterative (no host recursion) on all three targets, and add them to Resource Bounds.
  4. Pin the descent scenario's input to `reduce range(10001) as $_ ([]; [.])`, or to a native value, and not to `runJson`. Probe: `[..] | length` gives `10002`.

**R2 — Export narrowing has no cost bound, and as written it contradicts "no per-yield deep copying".**

- **The conflict.**
  - D4 keeps literal origin in private number objects until "final public export".
  - Every container produced by `runJson`, by literal templates, or by a caller `ZaruNumber` holds such objects, so it needs a public form in which they are replaced by plain `num` or `ZaruNumber`.
  - Flow & State Gaps (design.md:175) promises "Immutable engine values can be shared without per-yield deep copying".
  - Resource Bounds has no export row.
- **Consequence.** A straightforward export rebuilds the whole subtree on every yield. Examples are `limit(n; repeat(.))`, `.,.`, `foreach` emitting a shared accumulator, and `..` (which exports each nested node again). Over a large `runJson` document the cost is O(yields × size) in time and memory, and for `..` it is quadratic. That hidden cost conflicts with the plan's own laziness and resource claims.
- **Correction.**
  1. State the export strategy and its bound: either memoize per immutable internal node, or use lazy unmodifiable views that narrow on access, so each shared subtree is converted at most once per run.
  2. Keep export iterative (see R1).
  3. Add a Resource Bounds row.
  4. Add a test row, for example: two yields of the same unchanged `runJson` subtree export to the identical immutable container, while scalar `ZaruNumber` identity remains unpromised.

**R3 — The full-corpus step stays inside the `checks` job, so the job holding analyze/format/tests can never be green or required.**

- **The CI shape today.** `.github/workflows/ci.yml:11-31` runs analyze, format, normal tests and `mise run conformance` as steps of one `checks` job.
- **What the plan says.** D6 and task 7.3 add a separate required gate job and say "the all-corpus job stays honestly red". However, no task moves the full-corpus step into its own job.
- **Consequence.** After M1, `checks` is still red by design until full compatibility. Analysis, formatting and normal-test regressions therefore cannot be a required status, and the "all-corpus job" that D6 refers to does not exist.
- **Correction.** In task 7.3:
  1. Move `mise run conformance` into its own clearly non-required job.
  2. Keep `checks` (analyze/format/test) required.
  3. Add the required `conformance-gate` job.
  4. Update the M0 comment in the workflow.

### Suggestions

- **S1 — Dart type of exported plain numbers.** The plan says only "plain num". State whether computed integral results (for example `1+1`) and plain-narrowed integer literals (for example `runJson('42')`) export as `int` or `double` on the VM. Negative zero and huge computed values must be `double`. Without a stated rule, `is int` checks differ between implementations and between the VM and the web.
- **S2 — Origin across API composition and future CLI arguments.**
  - **Composition.** Passing a plain output of one filter into another filter's `run` turns a literal into a computed value. `42` then flips the result of `== 42.0000000000000001`. Note in the ADR and `docs/api.md` that `toJson` followed by `runJson` is the lossless way to chain filters.
  - **CLI arguments.** Probe: `jq --argjson x 42 '$x == 42.0000000000000001'` gives `false`, because `--argjson` values have literal origin. The `args` of `runJson` are native and therefore computed, so the M3 CLI needs a private path for literal-origin arguments. Record that in the task 1.1 ADR so M3 does not regress silently. M1 needs no change.
- **S3 — decNumber context edges.** Consider adding rows that anchor "no exponent-sized allocation" and the context clamping. Probes:
  - `0e1000000000` → `0E+999999999`.
  - `1e-1000000000` → `1E-1000000000`.
  - `1e1000` → literal `1E+1000`: a finite `ZaruNumber` whose `toDouble()` is infinity, and whose computed `.+0` prints `1.7976931348623157e+308`.

## Verification of earlier Claude findings

| Item | Status | Evidence in the current artifacts |
|---|---|---|
| C1 diagnostics | Resolved | D3 (byte spans, renderer, Bison recovery, grammar-state table, first versus last block); "Preserve jq compile diagnostics" plus 4 scenarios; key-error requirement; tasks 3.1–3.3 and 7.2. |
| C2 ZaruNumber contract | Resolved | Classification, API, equality/hash and acceptance requirements; native-ingestion requirement; task 1.1 ADR; task 1.5 `is num` caveat. |
| M1 two-step conversion | Resolved | D4 Conversion; midpoint row. |
| M2 binary gate | Resolved (CI shape: R3) | Gate requirement with 5 scenarios; task 7.3. |
| M3 pre-engine two-corpus classification | Resolved | D6; tasks 1.2/1.4/3.4; `man.test:1` scenario. |
| M4 exhaustive census | Resolved | D6 reference prerequisite; termination requirement; task 1.3. Anchor re-probed. |
| M5 equality identity versus ordering | Resolved | Resource row; identity-shortcut scenario; task 4.3. |
| M6 Unicode | Resolved | D7; 3 scenarios, re-probed. |
| M7 tail recursion | Resolved | D2; tail requirement; million-step rows cover comma, pipe and conditional through `repeat` and `while`-based `range/3`. |
| M8 unsupported causes | Resolved | Unsupported-category requirement; `jq.test:1981` in compilation and accounting; D6 "IGNORE MSG ignores only text". |
| M9 non-finite / JSON grammar | Resolved (depth: R1) | D7; decode/print requirement; `runJson` requirement. |
| Round-1 S1–S6 | Resolved | As recorded in round 2; still present. |
| Round-1 S7 `have_decnum` | Deferred by user policy | Open Questions keeps the original false request as a separate later reconciliation; not overridden. |
| N1 native origin/export | Resolved | Native requirement (binary64-representable → computed and plain; only integers that fail the round-trip become literal); rows for `0.00001`, `1.5e-7`, `1e16`, `1e23`, `1e300`, `1e23` equality and the exact-integer exception; task 1.1. Public `fromJson` removed in favor of `runJson`, with no new origin loss before evaluation (R2 concerns cost only). |
| N2 negative zero | Resolved | Literal `-0` scenario, signed-zero native row, D4/D7 zero rules. All match the probes. |
| N3 census versus fresh run | Resolved | D6 "Two zaru commands"; gate requirement; "Gate needs no native reference binary" and integrity rows; task 7.3 (no jq in CI). |
| Round-2 S1 multi-diagnostic | Resolved | "Missing key parentheses" scenario; D3; task 3.2. |
| Round-2 S2 merge leaf | Resolved | Scenario names the empty-object leaf at 10000/10001 (`jq.test:2610/2612`). |
| Round-2 S3 non-finite oracle | Resolved | Requirement text and "Nonfinite values cannot match printed substitutes". |
| Round-2 S4 raw surrogates | Resolved | D7; surrogate scenario. |
| Round-2 S5 argument timing | Resolved | D5; "Missing declaration or value" scenario. |

## Verdict

VERDICT: APPROVE_WITH_CHANGES

All earlier blocking and moderate findings (C1, C2, M1–M9, N1–N3) and the round-2 suggestions are resolved in the current artifacts. The new `runJson` literal-origin design is coherent with jq 1.8.2 probes and covers N1 without losing origin before evaluation. The remaining issues are bounded contract additions: decoder, export and printer depth and stack safety (R1); the export-narrowing cost bound (R2); and the CI job split (R3). None of them reopens the approved public boundary. Evidence limits: no Dart code exists or was run, the upstream source copy's hashes were not re-verified, and probes used one local jq 1.8.2 binary.

## Required Changes

1. **R1:** Specify the `runJson` depth limit (10000, jq's `FormatException` message), an explicit `toJson` behavior beyond `MAX_PRINT_DEPTH` (match or documented divergence), and iterative decode, export and print on all targets. Add rows, and pin the deep-descent scenario's input construction.
2. **R2:** Specify the export-narrowing strategy and its bound (each shared immutable subtree converted at most once per run, iteratively). Add a Resource Bounds row and a test row.
3. **R3:** In task 7.3, move full conformance out of the `checks` job into its own non-required job, keep `checks` required, and add the required gate job.

CHANGES_APPLIED: no
