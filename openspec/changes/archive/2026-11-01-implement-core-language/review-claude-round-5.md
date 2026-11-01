# Review — round 5 (fresh independent Claude pass)

## Metadata

- **Target:** `implement-core-language` (M1 core language) in `F:/Dev/Orca/Workspace/zaru`. That is parent `d4a10cf75f51c0aaade6f86d9fbb4a2f7742577f` plus the current uncommitted revisions of `proposal.md`, `design.md`, `tasks.md` and the three delta specs. I read them from the filesystem.
- **Reviewer:** Claude, dispatched through Orca (task `task_2baea8b57df0`, dispatch `ctx_45c1764e9e2f`).
- **Model:** `claude-opus-5-5`, as stated by the runtime system context. **Effort:** unknown.
- **Mode:** Read-only plan review.
  - This report is the only file I created. I changed no other repository file, branch, bookmark, setting or GitHub state.
  - I ran no Dart tests, builds, analyzer or formatters, and implemented nothing.
  - I did not read authoring transcripts.
- **Order:** I did my own pass first. Then I compared it against `review-claude.md` and `review-claude-round-2.md` through `review-claude-round-4.md`. `review.md` (an older Codex approval) is stale and I did not rely on it.
- **Read in full:** `proposal.md`, `design.md`, `tasks.md`, `specs/{filter-compilation,filter-execution,conformance-accounting}/spec.md` and `review-claude-round-4.md`. For the earlier rounds I relied on the round-4 report's mapping of C1/C2/M1–M9/N1–N3/R1–R3, and I re-checked each item against the current artifacts.
- **Repository context:**
  - `mise.toml`: `dart = "latest"`, and `web-test` = `dart test test/unit -p chrome`.
  - `.github/workflows/ci.yml`: jobs `checks` ("Analyze, format, tests, and conformance"), `compile` (matrix) and `chrome` ("Chrome core tests").
  - `dart_test.yaml`, `pubspec.yaml`, `pubspec.lock`.
  - `test/conformance/{VERSION,PROVENANCE.json}`: jq-1.8.2 at `34f7186b…`.
  - `AGENTS.md`.
- **Package source check:** I read the locally cached `test_api-0.7.15` source.
  - `lib/src/backend/runtime.dart:46,56` lists `[Compiler.dart2js, Compiler.dart2wasm]` for the browser runtimes.
  - `compiler.dart:11` defines `dart2wasm`.
  - This confirms the D9 interface `dart test test/unit -p chrome --compiler dart2wasm` against the locked `test` 1.33.0 / `test_core` 0.6.21 / `test_api` 0.7.15.
- **Native probes:** I ran read-only probes with the local scoop `jq-1.8.2` from `%TEMP%/r5check`, outside the checkout. I did not verify that binary's provenance against the pinned commit beyond `--version`.
- **Mechanical check:** A throwaway Python script, run outside the checkout, compared spec scenarios against test-map rows.
  - It found 99 scenarios and 99 rows.
  - No pair was missing, extra or duplicated.
  - Every test name equals its scenario name.
- **GitHub:** I made no GitHub queries. I relied on the coordinator's stated read-only result (main not protected, 404; rules `[]`) only to judge whether the plan is coherent. I did not treat it as independent evidence.

## Independent assessment

### Whole-plan coherence

The proposal, D1–D9, the three specs and tasks 1.1–8.2 tell one consistent story:

1. Pin the numeric/codec/API contracts and an exhaustive, hash-verified reference census and two-corpus classification before any evaluator exists (group 1).
2. Build numbers/codec/oracle (group 2).
3. Build grammar and diagnostics (group 3).
4. Build the runtime (groups 4–6).
5. Replace M0's artificial failures with fresh, jq-free execution and a separate binary gate (group 7).
6. Verify integration (group 8).

Ordering is sound:
- The wasm runner (task 1.6) lands before the first group-2 wasm verification.
- End-to-end compile rows cannot turn green before group 4 (task 3.3).
- Census and classification are frozen before any engine runs (tasks 1.3/1.4, plus the cross-check in 3.4 that cannot weaken the freeze).

The resource guarantees are stated as concrete, checkable bounds, not aspirations: parser slots, printer depth, the equality versus ordering guard, merge depth, repetition byte limit, tail frames and node-owned memos.

### Probes against new or changed scenario contracts (jq 1.8.2)

| Filter / input | Observed | Plan scenario |
|---|---|---|
| `.[1]` on `"😀abc"` | `Cannot index string with number (1)`, rc 5 | "Numeric string indexing is an error" ✓ |
| `.[1]?` | no output | ✓ |
| `.[1:2]` | `"a"` | ✓ |
| `.[1.5:2.7]`, `.[-1:]` | `"ab"`, `"c"` | "Fractional and negative string slice bounds" ✓ |
| `"a" * (-1, nan, 0, 0.5, 1.5)` | `null, null, "", "", "a"` | "Repetition truncates counts…" ✓ |
| `[label $here \| .[] \| if . > 1 then break $here else . end]` on `[0,2,1]` | `[0]` | ✓ |
| empty / whitespace-only stdin | no output, rc 0 | the plan deliberately differs for single-value `runJson`, explicitly scoped away from M3 CLI ✓ |
| BOM + `[NaN,Infinity,-Infinity,-NaN]` | `[null,1.7976931348623157e+308,-1.7976931348623157e+308,null]` | ✓ |
| `+1`, `01`, `.5`, `1.` | `1`, `1`, `0.5`, `1` | ✓ |
| `42` then `. == 42.0000000000000001` | `false` | literal-origin row ✓ (computed native 42 → true by jq's double fallback) |
| `9007199254740993.00000000001 + 0` | `9007199254740992` | two-step midpoint ✓ |
| JSON `"\ud800"` / `"\udc00"` | parse error / `"�"` | surrogate boundary row ✓ |
| `try {(0):1} catch .` | compile error `Cannot use number (0) as object key` | ✓ |
| `-0` input `., -.` ; `jq -n '-0'` | `-0`, `0` ; `0` | zero canonicalization ✓ |

### R4–R6 and round-4 S1–S3 against the current artifacts

**R4, wasm.** Resolved.
- D9 and task 1.6 add `mise run web-test-wasm` with run value `dart test test/unit -p chrome --compiler dart2wasm`, and make `web-test` select dart2js explicitly.
- Both tasks run on the existing scaffold before group 2.
- CI adds `core-dart2js` and `core-dart2wasm` jobs, and VM-only reference tests stay outside them.
- The cached locked `test_api` source confirms that the flag and the Chrome compiler pairing exist.

**R4, enforcement scope.** Resolved coherently.
- The previous text implied an enforcement mechanism that does not exist. The plan now:
  - defines milestone acceptance roles and exact contexts (`checks`, `core-dart2js`, `core-dart2wasm`, `conformance-gate`, `full-conformance`, plus the three existing `Compile CLI (…)` contexts);
  - requires everything except `full-conformance` to be green;
  - records the policy in `AGENTS.md`;
  - verifies actual check-run names and results through read-only APIs.
- The spec ("SHALL NOT claim or authorize GitHub branch protection"), D9 "Authority/evidence" and tasks 7.3/8.2 all disclaim protection changes.
- They also require inspecting live policy before renaming the current `Analyze, format, tests, and conformance` and `Chrome core tests` contexts.
- The user asked for CI, not protection. I do not require external protection configuration.

**R5, native projections.** Resolved.
- D8 "Native paths" and the new requirement "Normalize native projection-changing paths once" rebuild into immutable engine nodes, in one iterative pass, every caller path whose public projection differs: narrowable wrappers, non-round-tripping integers, and normalized strings/keys.
- PRIVATE numeric origin is retained, so literal 42 is not replaced by computed 42.
- Unchanged public-compatible storage is reused as-is, with no memo, no freezing and no num-subtype conversion.
- With this, export is O(1) for both branches after the first projection, which closes the repeated-yield hole.
- The scenario `., ., (.[0] == 42.0000000000000001)` on `[ZaruNumber.parse("42")]` checks three things at once: projection identity, surviving origin (`false`, consistent with the jq literal/literal probe) and an unchanged caller list.
- The shared-storage row pins the reuse branch.
- The rows are mapped in `ownership_test.dart` under task 4.1/4.2.
- This is consistent with the State and Resource Bounds tables.

**R6, string indexing.** Resolved.
- D7 and the Unicode requirement restrict code points to slicing.
- Numeric indexing is a data error, and optional indexing suppresses it.
- Both scenarios match the probes above.
- `length` stays M2 unless the frozen inventory needs it, which is consistent with the D6 freeze.

**Round-4 S1, wasm numeric model.** Resolved. D4 "Plain-number types", the classification requirement ("Only dart2js has subtype overlap") and tasks 1.1/1.5 state that VM and wasm have distinct `int`/`double`.

**Round-4 S2, empty `runJson`.** Resolved. D8, the `runJson` requirement and the "Empty JSON text is not an input stream" row make empty input an explicit single-value error that the M3 CLI must not inherit.

**Round-4 S3, error position.** Resolved.
- D8 pins `FormatException.source` (the original string), `offset` (the zero-based UTF-16 index of the failing token) and a message carrying jq's line and UTF-8-byte column.
- The array-depth row asserts offset 10000 together with `column 10001`. That is consistent: the 10001st `[` is at UTF-16 index 10000.

## Findings

### Critical (blocking)

None.

### Moderate

None.

### Suggestions (optional; none blocks approval)

- **S1: "pinned SDK family" is not literally true.**
  - The problem: D9 ties "compatible Chrome (currently 137+)" to "the pinned SDK family". But `mise.toml` declares `dart = "latest"`, there is no `mise.lock`, and `pubspec.yaml` only lower-bounds the SDK (`^3.9.0`; the lock records `>=3.13.0`; the locally resolved SDK is 3.13.7).
  - Impact: a future floating SDK can raise the browser minimum. `core-dart2wasm` would then fail loudly rather than silently, so this is not a correctness hole.
  - Fix: reword to "the current mise-resolved SDK" and record the observed SDK version in the task 1.6 `AGENTS.md` note, or pin the SDK deliberately.
- **S2: dart2js rejects inexact integer literals at compile time.**
  - The problem: the rows "Native nonrepresentable integer retains exactness" and "Unsafe native input cannot recover missing digits" live in `test/unit/numbers_test.dart`, which `core-dart2js` compiles. A Dart integer literal such as `9007199254740993` in that file is a web-target compile error ("can't be represented exactly in JavaScript"). One such literal would stop the whole file from loading on dart2js.
  - Fix: note in task 2.1 or 4.1 that host-exact integers must be built at runtime, for example `int.parse` behind a platform check. The scenario's "where the host can represent it" already permits that guard.
- **S3: list the new mise tasks in the `AGENTS.md` task table.**
  - The new tasks are `web-test-wasm`, the reference-census command, `conformance-gate`, the split full-conformance command and the example task.
  - Why it matters: `AGENTS.md` makes that table the command interface, and it currently describes `mise run conformance` as intentionally failing at M0.
  - Tasks 1.6 and 7.3 already update `AGENTS.md` policy. Adding the table rows there keeps the documented interface truthful.

## Verification of earlier Claude findings

| Item | Status | Current evidence |
|---|---|---|
| C1 diagnostics | Resolved | D3 (UTF-8 byte spans with exclusive ends, renderer, Bison recovery, grammar-state table, first versus last block); compile-diagnostics requirement with 4 scenarios; key-error requirement with 3 scenarios; tasks 3.1–3.3 and 7.2 |
| C2 ZaruNumber contract | Resolved | Classification, API, equality/hash and acceptance requirements; native ingestion requirement; tasks 1.1/1.5/2.2 |
| M1 two-step conversion | Resolved | D4 Conversion; midpoint and context-edge rows; midpoint re-probed |
| M2 binary gate / CI | Resolved | Gate requirement with 5 scenarios; D6 "Two zaru commands"; D9 roles; tasks 7.3/8.2 |
| M3 both-corpus pre-engine freeze | Resolved | D6; tasks 1.2/1.4/3.4; `man.test:1` and "cannot be fitted" rows |
| M4 exhaustive termination census | Resolved | D6 reference prerequisite and terminal policy; termination requirement with 5 scenarios; task 1.3 |
| M5 equality identity versus ordering | Resolved | Resource Bounds equality row; identity-shortcut row; task 4.3 |
| M6 Unicode | Resolved | D7; 5 Unicode scenarios including R6's two new rows |
| M7 tail recursion | Resolved | D2 (comma RHS, pipe RHS, conditional branches); tail requirement; million-step rows; task 6.2 forbids relying only on native range/2 |
| M8 unsupported causes | Resolved | Unsupported-category requirement; `jq.test:1981` in compilation and accounting; IGNORE MSG ignores only text |
| M9 nonfinite / jq JSON grammar | Resolved | D7; decode/print requirement; nonfinite oracle row; probes match |
| Round-1 S1–S6 | Resolved | Still present |
| Round-1 S7 (`have_decnum`) | Deferred by user policy | Open Questions keeps the original false request for later explicit reconciliation, and these predicates cannot create M1 passes. Not silently overridden. |
| N1–N3 | Resolved | Native computed-origin rule and rows; zero rules; census versus fresh-run separation and no-jq gate row |
| R1 deep codecs | Resolved | D8; parser/printer Resource Bounds rows; 3 depth rows; offset contract added |
| R2 node-owned projections | Resolved | D8; State/Resource rows; 2 projection rows |
| R3 CI split | Resolved | D6/D9; tasks 7.3/8.2 |
| R4 wasm interface | Resolved | D9; task 1.6; locked package source confirms the flag |
| R4 enforcement scope | Resolved by accurate scoping | Spec, D9 and tasks disclaim protection changes and define verifiable milestone roles |
| R5 native projections | Resolved | D8 Native paths; new requirement with 2 rows; tasks 4.1/4.2 |
| R6 string indexing | Resolved | D7; requirement wording; 2 new rows; probes match |
| Round-4 S1–S3 | Resolved | See the assessment above |

## Verdict

VERDICT: APPROVE

No correction is required. All earlier blocking and moderate findings (C1, C2, M1–M9, N1–N3, R1–R6) are resolved in the current artifacts:
- The new wasm interface is confirmed against the locked `package:test` source.
- The CI policy is accurately scoped as milestone roles, without claiming branch protection.
- The native projection-ownership contract closes the repeated-export hole and keeps literal origin.
- The string-indexing and slicing contracts match jq 1.8.2 probes.
- All 99 scenarios map one-to-one to named test rows.

S1–S3 are optional improvements.

Evidence limits:
- No Dart code exists or was run.
- The probes used one local jq 1.8.2 binary, whose provenance I did not verify beyond `--version`.
- The upstream C sources were not re-read in this round; I relied on round 4's citations together with fresh probes.
- I did not independently query GitHub state.

## Required Changes

None. Optional: S1 (reword "pinned SDK family" or pin the SDK), S2 (avoid inexact integer literals in dart2js-compiled test files), and S3 (list the new mise tasks in the `AGENTS.md` table).

CHANGES_APPLIED: n/a
