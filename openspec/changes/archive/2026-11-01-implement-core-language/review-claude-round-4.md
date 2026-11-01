# Review — round 4 (fresh independent Claude pass)

## Metadata

- **Target:** `implement-core-language` (M1 core language) in the same checkout `F:/Dev/Orca/Workspace/zaru`: parent `d4a10cf75f51c0aaade6f86d9fbb4a2f7742577f` plus the current uncommitted revisions of `proposal.md`, `design.md`, `tasks.md` and the three delta specs, read from the filesystem.
- **Reviewer:** Claude, dispatched through Orca (task `task_e05ec24f4019`, dispatch `ctx_5193e9630352`).
- **Model:** `claude-opus-5-5`, as stated by the runtime system context. **Effort:** unknown.
- **Mode:** Read-only plan review. This report is the only file I created. I changed no other repository file, branch, bookmark or setting. I ran no Dart tests, builds, analyzer or formatters, and implemented nothing. I did not read authoring transcripts.
- **Order:** I did my own pass first, then compared against `review-claude.md`, `review-claude-round-2.md` and `review-claude-round-3.md`. `review.md` (older Codex approval) is stale and was not relied on.
- **Read in full:** `proposal.md`, `design.md`, `tasks.md`, `specs/{filter-compilation,filter-execution,conformance-accounting}/spec.md`, `review-claude-round-2.md`, `review-claude-round-3.md`, `AGENTS.md`. I read `review-claude.md` at the level of its finding headings, to map C1/C2/M1–M9.
- **Repository context:** `.github/workflows/ci.yml`, `mise.toml`, `dart_test.yaml`, the `test/` layout.
- **Pinned upstream sources:** A read-only copy of jq `34f7186b…` outside the repository (`%TEMP%/jqsrc`): `jv_parse.c`, `jv_print.c` and `jv_aux.c`. I did not re-verify that copy's hashes.
- **Native probes:** Read-only probes with the local `jq-1.8.2` (scoop), run from `%TEMP%/r4probe` outside the checkout. Its provenance against the pinned commit was not verified beyond `--version`.
- **Mechanical check:** A throwaway Python comparison of spec scenarios against test-map rows. It found 94 scenarios and 94 rows, with no missing, extra or duplicate pairs, and every test name equals its scenario name.
- **Not checked:** I did not query GitHub branch-protection or ruleset state. Doing so needs authenticated `gh` access, which is out of scope here.

## Independent assessment

The round-3 corrections are now real contracts, not just mentions. I checked them against the pinned source and the native binary.

### R1: parser and printer depth

**Parser guard (`jv_parse.c:158-181`).**
- `[` and `{` are rejected when `stackpos >= MAX_PARSING_DEPTH` (`:161`, `:167`).
- `:` pushes the pending key string with **no** depth check (`:172-181`).
- So each keyed object level uses two slots, while the guard fires only when a container opens. D8's wording ("reject a new container when stackpos >= 10000, counting both container and pending object-key slots") is exact.

Probes:

| Input | Result |
|---|---|
| 10000 nested arrays around `0` | parses |
| 10001 nested arrays around `0` | `Exceeds depth limit for parsing at line 1, column 10001` |
| 5000 nested `{"a":…}` around `0` | parses |
| 5001 nested `{"a":…}` around `0` | rejected (column 25001) |

These match the "Array parsing depth boundary" and "Object keys consume parser stack slots" rows. The plan correctly does not use a uniform 10000 container cap.

**Printer (`jv_print.c:227-228,301,371,390,407`).**
- The root is dumped at `indent` 0, and each array element and object value at `indent + 1`.
- The marker is emitted when `indent > MAX_PRINT_DEPTH`, unquoted, and the subtree is not visited.

Probes:
- `reduce range(10000) as $_ (null; [.])` prints its `null` leaf.
- At 10001 levels, the leaf becomes `<skipped: too deep>` and all brackets are kept.

This matches D8, the Resource Bounds row and the "Printer depth boundary is jq truncation" row. The rows use values built inside the filter or supplied natively, not rejected JSON text, which is correct.

The deep-descent scenario now builds its input inside the filter. That avoids the parser budget. The pre-order `..` export is bounded by D8 memoization: the first projection is O(n), and each later nested node is reused in O(1).

### R2: node-owned projections

The node-owned lazy memo is coherent:
- **Lifetime.** It lives as long as the node is reachable, and no run-wide or global table holds strong keys.
- **Bounded growth.** Template projections are bounded by template size.
- **Immutability fits the ownership rules.** "Literal reuse after mutation attempt" now yields the identical immutable list across runs, which that requirement allows.
- **New values get new projections.** Changed values create new nodes, and "Changed containers do not alias projections" covers this.

One gap remains on the caller-input side (R5 below).

### R3: CI job split

- D6, the gate requirement, and tasks 7.3/8.2 now move full conformance into a standalone non-required job.
- `checks` (analyze/format/test) stays required, and a separate required `conformance-gate` is added.
- `continue-on-error` and jq installation are forbidden.
- Task 7.3 verifies actual Actions statuses, not YAML text.

The open issue is how "required" is enforced (R4 below).

### Numeric contracts, re-probed

| Probe | Result | Plan contract it confirms |
|---|---|---|
| `0e1000000000`, `1e-1000000000`, `1e1000`, `1e1000+0` | `0E+999999999`, `1E-1000000000`, `1E+1000`, `1.7976931348623157e+308` | "Decimal context exponent edges" row |
| `echo 0.00001 \| jq '., .+0'` | `0.00001`, `1e-05` | JSON-text literal C ≠ P(D), so `runJson` yields a wrapper while native input stays plain; consistent with the classification rule |
| `echo 42 \| jq '. == 42.0000000000000001'` | `false` | |
| `--argjson x 42 '$x == 42.0000000000000001'` | `false` | D4's note that the M3 CLI needs a private literal-origin argument path |
| `-0` input, then `.`, `-.`, `.==0` | `-0`, `0`, `true` | |
| `jq -n '-0'` | `0` | "Literal negative zero" scenario and D4 zero rules |

Public `fromJson` is absent with a stated reason, and the `run`/`runJson` split is consistent across the proposal, D4, the spec and tasks 1.5/2.3/4.2.

## Findings

### Critical (blocking)

None.

### Moderate

**R4 — The plan has no runnable dart2wasm test interface. "wasm parity" therefore cannot be executed through the mandated task interface, and CI never guards it.**

- **Evidence.**
  - `mise.toml` defines `web-test` as `dart test test/unit -p chrome`, which uses the test runner's default JS compiler.
  - CI's `chrome` job runs only that task.
  - The plan nevertheless requires dart2wasm verification in several places:
    - spec "Two-step rounding at a binary midpoint" ("VM, dart2js, and wasm");
    - spec "Handle deep JSON boundaries iteratively" ("iterative on VM/dart2js/wasm");
    - D8 and the Risks section;
    - tasks 2.2, 2.3 and 6.2 ("on VM, dart2js and wasm");
    - task 8.1 ("Chrome/dart2wasm").
  - No task adds a wasm mise task or CI job. `AGENTS.md` ("Run repository commands through the existing mise tasks… Do not… advertise bare SDK commands in docs or CI") then leaves an implementer two bad options: run an ad-hoc bare `dart test … --compiler dart2wasm`, or silently skip wasm.
- **Consequence.**
  - wasm's numeric model differs from dart2js: `int` and `double` are distinct 64-bit types, as on the VM.
  - The native exact-integer branch is therefore reachable on wasm, and the iterative codecs face another engine's stack limits.
  - A wasm-only regression in exactly the numeric and depth contracts this plan pins would be invisible to every required status.
- **Correction.**
  1. In group 8 (or earlier, before tasks 2.2/2.3 claim wasm verification), add a mise task that runs the browser-safe unit tests on Chrome with the dart2wasm compiler. Use the test runner's compiler selection, confirmed against the installed `package:test` version.
  2. Add a CI job (or matrix entry) that runs this task.
  3. State whether that status is required.

**R4 also covers — the "required" status mechanism is not tasked and cannot be verified from repository artifacts.**

- **Evidence.** The conformance spec says "CI SHALL keep checks and conformance-gate as separate required statuses". Task 7.3 says "update … required-status policy". Required status checks are a GitHub branch-protection or ruleset setting. They are not in `ci.yml`, and no repository document records them today (grep over `docs/` and `README.md` found none).
- **Rename risk.** The current `checks` job's status name is "Analyze, format, tests, and conformance". Renaming it when conformance moves out changes the status context that any existing protection rule refers to.
- **Consequence.**
  - An implementer can satisfy the YAML half and still claim "required" while nothing enforces it.
  - Or a rename can leave a stale required context that never reports, which blocks merges.
  - Changing repository protection is also an outward-facing action that needs explicit user authorization under the user's account rules.
- **Correction.** In task 7.3:
  1. Name the mechanism (branch protection or ruleset on `main`) and the exact job-name contexts to require.
  2. Mark the protection change as a user-authorized step.
  3. Verify the applied setting through the GitHub API after the first real run.
  4. Record the policy in a repository document, so the spec's "required" claim is checkable.

**R5 — The export bound has a hole for native caller containers whose public form differs from the caller's storage.**

- **The plan's claims.**
  - D7: native ingestion rebuilds only paths changed by UTF-16 normalization.
  - D8: unchanged public-compatible caller storage may be reused, and caller-owned mutable containers are never memoized.
  - Resource Bounds: "Repeated/deep shared results do not cause per-yield subtree copies."
- **The uncovered case.** Some caller containers are left unchanged by ingestion but are not public-compatible at export. Two such inputs are defined elsewhere in the plan:
  - a nested `ZaruNumber.parse("42")`, which narrows to `int` on output ("can narrow on output if eligible");
  - a VM `int` that fails the binary64 round-trip, which exports as `ZaruNumber`.
- **Consequence.** Export must rebuild such a caller container on every yield, and the result cannot be memoized. Examples are `limit(n; repeat(.))`, `.,.` and `..` over a large native list containing one such scalar. That reintroduces the O(yields × size) and quadratic `..` cost that R2 was meant to remove, while the Resource Bounds row says it cannot happen.
- **Correction.**
  1. Specify that native ingestion, in its single iterative pass, also rebuilds into immutable engine nodes any caller path containing a scalar whose public projection differs from the stored object. That covers narrowable wrappers, exact-origin integers and normalized strings.
  2. Then export reuses caller storage only when the storage is already its own public form.
  3. Add or extend an ownership row, for example: two yields of a native list containing `ZaruNumber.parse("42")` return the identical immutable projection, and the caller's list is unchanged.

**R6 — The Unicode requirement says "string indexing/slicing SHALL use Unicode code points". That promises character indexing, which jq does not have.**

This finding answers a coordinator follow-up during the review. I checked it independently.

- **Probes (jq 1.8.2, input `"😀abc"`).**

  | Filter | Result |
  |---|---|
  | `.[1]` | `Cannot index string with number (1)` |
  | `.[1]?` | no output |
  | `try .[1] catch .` | `"Cannot index string with number (1)"` |
  | `.[1:2]` | `"a"` |
  | `.[-1:]` | `"c"` |
  | `.[1.5:2.7]` | `"ab"` (start floored, end ceiled) |
  | `length` | `4` |

  The message comes from the generic `Cannot index %s with %s (%s)` path in pinned `jv_aux.c:154`.
- **What the plan says.** D7 says "Implement code-point access/slicing". The spec says "String indexing/slicing SHALL use Unicode code points". The only Unicode scenario is the slice `.[1:]`.
- **Consequence.** An implementer reading "access/indexing … code points" can reasonably make `"😀abc" | .[1]` return `"a"`. Then:
  - `.[1]?` yields a value instead of nothing;
  - `try` handlers no longer receive jq's error value;
  - catch fixtures fail.

  Nothing in the test map would catch this, because no row covers numeric indexing of a string.
- **Correction.**
  1. Reword D7 and the requirement: string **slicing** (including negative and fractional bounds) and `length` use code points; numeric indexing of a string is a typed runtime error carrying `Cannot index string with number (N)`.
  2. Add a scenario to "Match jq Unicode slicing and ordering" (or "Invalid access versus optional access"), with a test row covering:
     - `.[1]` on `"😀abc"` raises that error value;
     - `.[1]?` yields nothing;
     - `.[1:2]` yields `"a"`.

     Optionally, add `.[1.5:2.7]` → `"ab"`, to pin jq's bound rounding.

### Suggestions

- **S1 — dart2wasm is not "web subtype overlap".** Task 1.5 and the classification requirement describe "web subtype overlap". That holds for dart2js only. On dart2wasm, `int` and `double` are distinct, as on the VM, and the native nonrepresentable-integer branch is reachable. State this in the task 1.1 ADR and the `docs/api.md` caveat, so that consumers do not assume wasm behaves like JavaScript.
- **S2 — Empty `runJson` input.** jq with empty or whitespace-only input yields no outputs. `runJson`'s "decode exactly one value" makes the same input a `FormatException`. That is a reasonable API choice, but state it explicitly, so the M3 CLI does not inherit it by accident.
- **S3 — Position in the depth-limit error.** jq's message carries a position (` at line 1, column 10001`), and the Failure table promises "a format failure with source position". Say whether `FormatException.offset` or `message` carries that position, so the depth rows can assert it.

## Verification of earlier Claude findings

| Item | Status | Evidence in the current artifacts |
|---|---|---|
| C1 diagnostics | Resolved | D3 (UTF-8 byte spans, renderer, Bison recovery, grammar-state table, first-versus-last block); the "Preserve jq compile diagnostics" requirement with 4 scenarios; the key-error requirement; tasks 3.1–3.3 and 7.2. |
| C2 ZaruNumber contract | Resolved | Classification, API, equality/hash and acceptance requirements; native-ingestion requirement; tasks 1.1 and 1.5. |
| M1 two-step conversion | Resolved | D4 Conversion; midpoint and context-edge rows. |
| M2 binary gate | Resolved | Gate requirement with 5 scenarios; D6 "Two zaru commands"; task 7.3. Enforcement detail is R4. |
| M3 pre-engine classification of both corpora | Resolved | D6; tasks 1.2, 1.4 and 3.4; `man.test:1` scenario. |
| M4 exhaustive termination census | Resolved | D6 reference prerequisite; termination requirement; task 1.3. |
| M5 equality identity versus ordering | Resolved | Resource row (depth check, then identity, never for ordering); identity-shortcut row; task 4.3. |
| M6 Unicode | Resolved, except R6 | D7; 3 scenarios; printer normalizes only visited strings. R6 corrects the "indexing" wording and adds the missing error/optional scenario. |
| M7 tail recursion | Resolved | D2; tail requirement; million-step rows use `repeat` (comma RHS) and `range/3` via `while` (pipe RHS inside `if`); task 6.2 forbids relying on native `range/2` alone. |
| M8 unsupported causes | Resolved | Unsupported-category requirement; `jq.test:1981` in compilation and accounting; "IGNORE MSG ignores only text". |
| M9 nonfinite / JSON grammar | Resolved | D7; decode/print requirement; `runJson` requirement; nonfinite oracle row. |
| Round-1 S1–S7 | Resolved, except S7 | S1–S6 are still present. S7 (`have_decnum`) is deferred by user policy: Open Questions keeps the original false request for later reconciliation and does not override it. |
| N1 native origin/export | Resolved | Computed ingestion of binary64 values, with an exact-literal exception only for integers that fail the round-trip; rows for `0.00001`, `1.5e-7`, `1e16`, `1e23` and `1e300`, `1e23` equality, signed zero and the nonrepresentable integer. |
| N2 negative zero | Resolved | Literal and native `-0` rows and D4/D7 zero rules; re-probed. |
| N3 census versus fresh run | Resolved | D6; gate requirement; no-jq and integrity rows; `gate_process_test.dart` is VM-only. |
| Round-2 S1–S5 | Resolved | Multi-diagnostic scenario, merge leaf, nonfinite oracle, raw surrogates, and argument timing are all still present. |
| R1 deep codecs | Resolved | D8; Resource Bounds parser and printer rows; 3 depth rows; descent input pinned. Matches `jv_parse.c`/`jv_print.c` and the probes. |
| R2 export cost | Resolved for engine nodes | D8 node-owned memo; Resource Bounds and State tables; 2 projection rows; task 4.2. Native caller-container hole: R5. |
| R3 CI split | Resolved in the task plan | D6; gate requirement; tasks 7.3 and 8.2 verify actual statuses. Required-status enforcement: R4. |
| Round-3 S1 int/double | Resolved | Classification requirement and D4 plain-number types. wasm wording: S1. |
| Round-3 S2 composition and CLI args | Resolved | D4 composition paragraph; task 1.1; probe confirms `--argjson` literal origin. |
| Round-3 S3 context edges | Resolved | "Decimal context exponent edges" row; re-probed. |

## Verdict

VERDICT: APPROVE_WITH_CHANGES

Every earlier blocking and moderate finding (C1, C2, M1–M9, N1–N3, R1–R3) is resolved in the current artifacts. The new parser, printer and projection contracts match pinned `jv_parse.c`/`jv_print.c` and the jq 1.8.2 probes, and all 94 scenarios map one-to-one to named test rows. Three bounded corrections remain, and none of them reopens the approved numeric boundary:
- R4: a runnable dart2wasm task and CI job, plus an explicit, authorized and verifiable mechanism for required statuses;
- R5: closing the native-container export-cost hole;
- R6: correcting the Unicode wording that promises code-point string indexing, with an error/optional scenario.

The suggestions S1–S3 are optional.

Evidence limits: no Dart code exists or was run, the upstream source copy's hashes were not re-verified, the probes used one local jq 1.8.2 binary, and GitHub protection state was not queried.

## Required Changes

1. **R4 (wasm):** Add a mise task and a CI job that run the browser-safe unit tests on Chrome with dart2wasm. Order the task before tasks 2.2/2.3/6.2 claim wasm verification, and state whether its status is required.
2. **R4 (required statuses):** In task 7.3, name the branch-protection or ruleset mechanism and the exact job contexts. Make the change a user-authorized step, verify it through the API after a real run, and record the policy in a repository document.
3. **R5:** Specify that native ingestion rebuilds, into immutable memoizable engine nodes, every caller path whose public projection differs (narrowable wrappers, exact-origin integers, normalized strings). Add an ownership row that proves identical repeated projections for such native input.
4. **R6:** Restrict "code points" in D7 and the Unicode requirement to slicing and length. Specify that numeric string indexing raises `Cannot index string with number (N)`. Add a mapped scenario: `.[1]` raises the error, `.[1]?` yields nothing, and `.[1:2]` yields `"a"` on `"😀abc"`.

CHANGES_APPLIED: no
