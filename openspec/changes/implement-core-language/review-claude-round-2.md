# Review — round 2 (fresh independent Claude pass)

## Metadata

- **Target:** `implement-core-language` (M1 core language) in the same checkout `F:/Dev/Orca/Workspace/zaru`: parent commit `d4a10cf75f51c0aaade6f86d9fbb4a2f7742577f` plus the current uncommitted revisions to `proposal.md`, `design.md`, `tasks.md` and the three delta specs (read from the filesystem, not from git).
- **Reviewer:** Claude, dispatched through Orca (task `task_647089843a5d`, dispatch `ctx_ddf8dbd8795a`).
- **Model:** `claude-opus-5-5`, as stated by the runtime system context. **Effort:** unknown.
- **Mode:** Read-only plan review. The only file I created is this report. I changed no other repository file, branch, bookmark or setting. I ran no Dart tests, builds, analyzer or formatters, and implemented nothing. I did not read authoring transcripts.
- **Order:** I did my own pass over the revised artifacts first. Only then did I compare against `review-claude.md` (previous Claude REVISE). I treated `review.md` (older Codex approval) as stale and did not rely on it.
- **Artifacts read in full:** `proposal.md`, `design.md`, `tasks.md`, `specs/filter-compilation/spec.md`, `specs/filter-execution/spec.md`, `specs/conformance-accounting/spec.md`, `review-claude.md`.
- **Repository context:** `AGENTS.md`, `test/conformance/{jq.test,man.test,PROVENANCE.json}`, `.github/workflows/ci.yml`, `mise.toml`.
- **Pinned upstream sources:** A previously downloaded read-only copy of jq commit `34f7186b86743a083a589741b6cea95293524108`, outside the repository (`%TEMP%/jqsrc`). I consulted `jq_test.c`, `jv.c` and `builtin.jq`. I did not re-verify the hashes of that copy.
- **Native probes:** I ran read-only probes with the locally installed `jq-1.8.2` (scoop build; `1e2` printing `1E+2` shows that decNumber is enabled) from a temporary directory outside the checkout. Every jq behavior quoted below as "probe" was observed with this binary. That binary's provenance against the pinned commit was not verified beyond `--version`.

## Independent assessment

The revised plan is substantially stronger:

- Diagnostics are now a span-bearing, rendered, grammar-derived contract.
- The census and the classification of both corpora are frozen before the engine exists.
- The gate is a separate binary command and CI job.
- Tail positions, the structural limits, Unicode handling and non-finite handling are pinned with concrete scenarios.

I verified these scenarios against jq 1.8.2 probes and they hold exactly:

- `(false, null, 0, "") // 9` → `0, ""`.
- The label/break `[0]` case.
- `-.` on `13911860366432393` and on `-0.12345678901234567890123456789`.
- `[13911860366432392,true]` for the mixed comparison.
- `9007199254740993.00000000001 + 0` → `9007199254740992` (the two-step rounding).
- The nonfinite output `[null,1.7976931348623157e+308,-1.7976931348623157e+308,null]`, including with a BOM.
- `+1`, `01`, `.5`, `1.` → `1, 1, 0.5, 1`.
- `1e2` → `1E+2`, `100e-2` → `1.00`, `9E+999999999` preserved, and `1e1000000000` normalized to infinity.
- `"\ud800"` rejected while `"\udc00"` becomes U+FFFD.
- `"abc" * 1000000000` → `Repeat string result too long`; `"a" * (-1, nan, 0, 0.5)` → `null, null, "", ""`.
- Equality: `$x == $x` at depth 10001 → `true`; distinct values → `Equality check too deep`; sort → `Comparison too deep`.
- `..` over 10001 levels emits 10002 nodes.
- Merge: `{}`-leaf nesting 10000 succeeds and 10001 → `Object merge too deep`.
- `[limit(1000000; repeat(1))] | length` → 1000000; `last(range(0;1000000;1))` → 999999.
- U+FFFD < 😀, and `"😀abc"[1:]` → `"abc"`.
- Diagnostics: `$*label-foo is not defined`, `Cannot use number (0) as object key` (not catchable), and UTF-8 *byte* columns (`"éé" | $x` reports column 10).

`jvp_equal` (`jv.c:2087-2100`) checks depth first and then the identity shortcut, which is the order the design adopts. `jvp_object_merge_recursive` (`jv.c:1918-1930`) matches the merge row. In 1.8.2, `repeat` is `def _repeat: exp, _repeat;` (`builtin.jq:185-188`), so recursion sits in the comma RHS, which the plan's tail definition covers. The scenario/test-map coverage is complete: 17/17 compilation, 42/42 execution and 20/20 accounting scenarios each have a row.

Two contract defects and one ambiguity remain.

## Findings

### Critical (blocking)

**N1 — The native-number ingestion rule, combined with automatic export classification, wraps ordinary native doubles in `ZaruNumber` and invents spellings no jq input produces.**

The two rules that combine:

- `filter-execution`, "Interpret native numeric input independently of platform spelling": finite native numbers enter with *literal origin*. Integral values use their *exact represented integer coefficient*; fractional values use jq's shortest round-trip decimal.
- "Classify exceptional literal numbers consistently": *automatic literal outputs* become `ZaruNumber` when C ≠ P(D), or when the integer magnitude exceeds 2^53−1.

Applied to plain caller doubles under the identity filter:

| Native input | Result under the plan | Why, with probe evidence |
|---|---|---|
| `0.00001` or `1.5e-7` | `ZaruNumber` | C is the decNumber canonical form, `0.00001` / `1.5E-7`. P(D) is jq's computed form, `1e-05` / `1.5e-07`. Probe: `jq -n '1e-5'` → `0.00001`, `jq -n '0.00001+0'` → `1e-05`, `1.5e-7` → `1.5E-7` versus `1.5e-07`. So C ≠ P(D) and the value is wrapped. |
| `1e16` (an ordinary JavaScript number) | `ZaruNumber` | It enters as literal origin above 2^53, so the magnitude rule wraps it. |
| `1e23` | `ZaruNumber("99999999999999991611392")` | Its exact binary coefficient becomes the literal. jq prints that value as `1E+23` (JSON-text literal) or `1e+23` (computed); never as this digit string. |
| `1e300` | A 301-digit literal | Same mechanism. |

Two consequences follow.

**Evaluator equality diverges from jq.** Native `1e23` against the filter literal `1e23` becomes a literal/literal *decimal* comparison: `99999999999999991611392` versus `1E+23`, which is `false`. jq gives `true` for the same JSON input `1e23`. Probe: `1e23 == 99999999999999991611392` → `false`. So data that came through `jsonDecode` changes filter results.

**The rule contradicts the user-approved boundary.** "Ordinary values remain plain Dart" is violated: common doubles come back wrapped, and `is num` consumers silently skip them. The design rates this contract's reversal cost High, and task 2.2 exports it.

The test-map row "Integral native doubles have no source scale" (1/1.0) does not detect this.

**Correction:**

1. Restate native ingestion so that a native finite value exactly representable as binary64 behaves as a jq *computed* number (`jv_number`). That means double-fallback comparison with literals, P(D) printing, and automatic export as plain `num`.
2. Give an exact literal integer origin only to native integers that binary64 cannot represent. That is VM-only, decided numerically: `v.toDouble()` does not round-trip. Such values then follow the >2^53 wrapper rule identically on every target, because the web cannot produce them.
3. Alternatively, pick any other numerically defined rule that guarantees all of the following:
   - Identity over any binary64 native returns a plain `num` equal to the input.
   - Native `1e23 == 1e23` (filter literal) is `true`.
   - No native value is printed in a spelling that neither jq's literal nor its computed printer produces.
4. Add rows for native `0.00001`, `1e23` and `1e300` under identity/equality, and mirror the rule in task 1.1's ADR.
5. Keep the existing rule that already-rounded caller values are not repaired.

### Moderate

**N2 — The `-0` scenario asserts behavior that contradicts both jq and the plan's own classification rule.**

- **The scenario.** "Literal negative zero follows jq canonicalization" says `Zaru.fromJson('-0')` yields a canonical value whose printing is plain integer `0`.
- **What jq does.** Probe: `echo -0 | jq -c .` → `-0`, and the computed `0 * -1` also prints `-0`.
- **What the plan's own rule gives.** C = `-0` and P(D) = `-0`, so the classification yields plain `-0.0` printed `-0`.
- **Related inconsistency.** D4 and the native rule ("Zero SHALL normalize to literal 0", "normalized zero") also drop the sign of a native `-0.0`, which jq's computed printer keeps.
- **Consequence.** An implementer satisfying the scenario has to special-case away a jq-observable sign. On dart2js, plain `int` cannot carry `-0`, so the scenario also forces a type choice that the rule never states.
- **Correction:** Change the scenario so that `fromJson('-0')` returns plain `-0.0`, `toJson` prints `-0`, and it compares equal to `0`. Specify that the printer emits `-0` for negative zero on every target, and make the native-zero rule keep the sign. Wrapper equality may still ignore the zero sign, as specified.

**N3 — "Fresh full census" is used both for the pinned-jq reference capture and for the zaru conformance/gate run, which leaves it unspecified whether the gate requires native jq.**

- **The two uses.** D6 and the "Account for runtime termination" requirement define the *census* as the exhaustive pinned-jq reference capture, recorded once before the engine exists. D6 "Two commands" and the gate requirement then say that `conformance` and `conformance-gate` each "perform a fresh full census". The gate requirement adds that missing reference coverage, binary or environment blocks it ("Incomplete reference environment blocks acceptance").
- **Reading 1: the gate re-runs jq.** CI then needs the verified pinned jq 1.8.2 binary and its module assets. No task installs these, and the current CI has none (`.github/workflows/ci.yml:12-31`). A re-captured reference could also drift from the frozen, reviewed baseline, which undermines the freeze.
- **Reading 2: the gate only re-runs zaru.** The reference-environment scenario then has no meaning at gate time.
- **Correction:** Use distinct terms. The reference census is the pinned-jq capture, regenerated only through its own command. A fresh zaru run is real decode/compile/evaluate over all 781 IDs against the checked-in frozen census, with an integrity check (for example a recorded hash or ID completeness). State that `conformance-gate` and the CI job need no native jq. If the intent is the opposite, add the jq installation, verification and asset tasks to 7.3 instead.

### Suggestions

- **S1 — Multi-diagnostic selection.** Probes show that jq's Bison error recovery emits several diagnostics, and `jq_test.c:82-88`'s `test_err_cb` keeps only the *last* message prefixed `jq: error`.
  - `{1+2:3}` emits `syntax error, unexpected LITERAL` first and then `May need parentheses…` (`jq.test:132` expects the latter).
  - `.\n]` emits the line-2 syntax error first and then a line-1 `try .["field"]…` diagnostic.

  D3/D6 say "callback selection", but the "Missing key parentheses" scenario reads as if that message is the compile error's first diagnostic. Name the Bison `error` recovery productions in task 3.2. State that `ZaruCompileError.message` is the first diagnostic, while the runner compares the last `jq: error` block.
- **S2 — Merge-depth scenario leaf.** The merge-depth scenario should name its leaf. With a scalar leaf, 10001 nested levels merge successfully and 10002 fail. With the `{}` leaf of `jq.test:2612`, 10000 succeeds and 10001 fails.
- **S3 — Nonfinite values in the fixture oracle.** The oracle row covers only *finite* values. State that an actual NaN or infinity never matches an expected JSON `null` or `1.7976931348623157e+308` by printing first (upstream `jv_equal` compares kinds and doubles). Otherwise a zaru bug that yields NaN where jq yields `null` would count as a pass.
- **S4 — Raw lone surrogates in `fromJson` text.** State the policy for a *raw* (unescaped) lone surrogate code unit inside a Dart `String` passed to `fromJson`. Presumably it should normalize to U+FFFD, matching jq's invalid-UTF-8 replacement, as distinct from an escaped `\ud800`.
- **S5 — Missing external argument timing.** Say whether the missing-external-argument error is raised at `run()` or at the first `moveNext`. The lazy contract makes either observable.

## Verification of the previous Claude review (`review-claude.md`)

| Item | Status | Evidence in revised artifacts |
|---|---|---|
| C1 diagnostics | Resolved | D3 (spans, renderer, Bison table, callback/prefix policy); compilation requirement "Preserve jq compile diagnostics" plus 4 scenarios; constant-key and key-parentheses requirement; tasks 3.1–3.3, 7.2. S1 above is a refinement, not a reopening. |
| C2 ZaruNumber contract | Resolved, except N1 | Classification (C/P(D)/2^53), API, equality/hash, acceptance, and the `is num` documentation task 1.5 are specified. N1 is a defect in the newly specified native rule. |
| M1 two-step conversion | Resolved | D4 Conversion; midpoint scenario confirmed by probe. |
| M2 binary gate | Resolved, with N3 | D6 "Two commands"; gate requirement; task 7.3 adds a separate CI job without continue-on-error. |
| M3 pre-engine classification of both corpora | Resolved | D6; tasks 1.2/1.4 before any evaluator; scenario `man.test:1`; reclassification needs a dependency. |
| M4 exhaustive termination census | Resolved | D6 reference prerequisite; tasks 1.3/1.4; nonempty-prefix and incomplete-environment scenarios. |
| M5 equality identity versus ordering | Resolved | Resource row and task 4.3, matching `jv.c:2087-2100`; scenario confirmed by probe. |
| M6 Unicode | Resolved | D7; Unicode requirement and 3 scenarios, confirmed by probe. |
| M7 tail recursion | Resolved | D2; tail requirement (comma RHS / pipe RHS / conditional); million-step and deep-descent rows on VM and Chrome; task 6.2. |
| M8 unsupported construct | Resolved | Unsupported-category requirement and `jq.test:1981` scenarios in both compilation and accounting. |
| M9 nonfinite / `fromJson` grammar | Resolved | D7; decode/print requirement; BOM/extension/surrogate scenarios confirmed by probe. |
| S1–S6 | Resolved | D4 canonicalization; D4 "Three comparisons"; task 1.2 inventory; test-map VM/browser split; failed-iterator scenario; repetition-edge scenario. |
| S7 `have_decnum` | Deferred by explicit user policy | Design "Open Questions" keeps the original false request as a separate deferred decision. Not overridden here. |

## Verdict

VERDICT: REVISE

Every blocking and moderate item from the previous round is resolved in substance, and the probe-checked scenarios match jq 1.8.2. The newly pinned native-number ingestion rule (N1), however, would export ordinary native doubles as `ZaruNumber` and change jq equality results. That is a High-reversal-cost public contract that contradicts the user-approved narrow boundary. The `-0` scenario (N2) and the overloaded "census" term (N3) also need correction before implementation.

## Required Changes

1. **N1:** Redefine native numeric ingestion and export so that binary64-representable natives behave as jq computed numbers and round-trip as plain `num`. Only binary64-unrepresentable integers (VM-only, tested numerically) take exact literal origin. Add rows for native `0.00001`, `1e23` and `1e300`, and mirror the rule in the task 1.1 ADR.
2. **N2:** Correct the `-0` scenario and the native-zero rule to keep jq's `-0` printing and sign. Specify `-0` printing on every target.
3. **N3:** Separate the pinned-jq "reference census" from the fresh zaru conformance run. State whether `conformance-gate` and its CI job need native jq, and task the CI installation and verification if they do.

CHANGES_APPLIED: n/a
