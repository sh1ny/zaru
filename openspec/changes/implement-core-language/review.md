# Review

## Metadata

- **Round:** 2
- **Prior round:** REVISE (runtime termination, numeric operation/comparison rules, ownership, structural limits)
- **Reviewer:** cross-model CLI (codex)
- **Reviewed:**
  - `openspec/changes/implement-core-language/proposal.md`
  - `openspec/changes/implement-core-language/design.md`
  - `openspec/changes/implement-core-language/review.md`
  - `openspec/changes/implement-core-language/specs/filter-compilation/spec.md`
  - `openspec/changes/implement-core-language/specs/filter-execution/spec.md`
  - `openspec/changes/implement-core-language/specs/conformance-accounting/spec.md`
  - `docs/adr/0001-parser-strategy.md`
  - `docs/adr/0002-evaluation-model.md`
  - `test/conformance/fixtures.dart`
  - `test/conformance/runner_test.dart`
  - `test/conformance/jq.test`
  - `test/conformance/man.test`
  - `test/conformance/PROVENANCE.json`
  - `lib/zaru.dart`
  - `docs/api.md`
  - `pubspec.yaml`
  - `mise.toml`
  - `AGENTS.md`
  - `.agents/skills/dart-add-unit-test/SKILL.md`
  - `.agents/skills/dart-write-documentation/SKILL.md`
  - Upstream numeric, structural-operation, and helper definitions at pinned commit `34f7186b86743a083a589741b6cea95293524108`: `src/jv.c`, `src/jv_aux.c`, `src/builtin.c`, and `src/builtin.jq`.
  - Upstream fixture protocol in `src/jq_test.c` at tag `jq-1.8.2`. Retrieval through the commit URL failed; the release-tag source was inspected instead.

Read-only architecture review. No repository modifications, builds, tests, analysis, formatters, or authoring transcripts. Repository content was treated as evidence. No evaluator implementation exists; approval does not establish runtime correctness.

## Findings

### Critical (blocking)

None.

**C1 — Resolved: runtime termination accounting.**

D6 and the conformance specification now distinguish normal exhaustion from expected typed runtime termination. The four destructuring cases have explicit stable IDs, empty expected prefixes, and an exact error-value contract. Comments remain non-executable. Missing prefix values, surplus outputs, incorrect errors, host exceptions, and unlisted errors after correct output all fail.

This deliberately strengthens upstream accounting: the inspected release runner checks for surplus output but accepts an invalid terminal result without inspecting whether it carries an error. The manifest avoids inheriting that ambiguity. [Upstream fixture runner](https://raw.githubusercontent.com/jqlang/jq/jq-1.8.2/src/jq_test.c)

**C2 — Resolved: unary negation.**

D4, the metadata ownership row, and the execution scenarios explicitly preserve literal precision through unary negation while retaining double semantics for binary numeric arithmetic. This agrees with the pinned implementation’s separate negation and arithmetic paths. [Pinned numeric implementation](https://raw.githubusercontent.com/jqlang/jq/34f7186b86743a083a589741b6cea95293524108/src/jv.c), [pinned operators](https://raw.githubusercontent.com/jqlang/jq/34f7186b86743a083a589741b6cea95293524108/src/builtin.c)

### Moderate

None remaining.

**M1 — Resolved: numeric comparison contracts.**

The artifacts now distinguish:

- Evaluator literal/literal and mixed/computed comparisons.
- Lossless fixture numeric-value comparison independent of equivalent spelling.
- Exact textual assertions where strings or dedicated printer checks expose serialization.

The scenarios cover `2` matching expected `2.0`, distinct large integers remaining unequal in the oracle, and rounded arithmetic comparing equal to its literal operand inside evaluation. The evaluator distinction matches the pinned literal comparison path and double fallback. [Pinned numeric comparison](https://raw.githubusercontent.com/jqlang/jq/34f7186b86743a083a589741b6cea95293524108/src/jv.c)

**M2 — Resolved: collection ownership.**

The ownership table and execution specification select immutable engine-created List/Map nodes before exposure. They cover literal templates, engine-created descendants, and suspended accumulators. Consumer mutation attempts fail without altering subsequent consumption or another run.

Caller-owned subtrees have a separate, explicit sharing policy. The design therefore closes the retained-template and accumulator-mutation leaks without promising snapshots of caller input.

**M3 — Resolved: structural resource limits.**

The design now provides operation-specific limits, iterative processing, and catchable errors for equality/order, recursive object merge, and repetition. The merge boundary and oversized repetition scenarios correspond to the pinned fixtures. The stated repetition threshold follows the pinned header size and byte-length guard; merge and equality use the pinned depth limit. [Pinned structural implementation](https://raw.githubusercontent.com/jqlang/jq/34f7186b86743a083a589741b6cea95293524108/src/jv.c)

Ordering also receives an explicit depth contract and typed failure, consistent with the pinned comparator. These are implementation obligations, not claims that deep operations have already passed. [Pinned ordering implementation](https://raw.githubusercontent.com/jqlang/jq/34f7186b86743a083a589741b6cea95293524108/src/jv_aux.c)

### Suggestions

None requiring artifact changes.

The selected parser, immutable compiled program, per-iterator continuations, lexical control signals, and private path-mode seam remain coherent with the in-force ADRs. The approved narrow exact-number boundary is accepted; recording its superseding ADR during implementation is already explicit.

## Verdict

VERDICT: APPROVE

All five round 1 findings are resolved at the architecture/specification level. No concrete remaining blocking or moderate consequence was identified. Implementation and conformance evidence remain future acceptance work.

## Required Changes

None.

CHANGES_APPLIED: n/a

## Rebuttals

The exact-number type is an approved boundary, not a scope objection.

The existing empty library and deliberately failing runner are consistent with this being a planning review. Their current behavior was not treated as evidence against the proposed implementation.

The design’s reported jq probes were not independently reproduced during this read-only review. Source inspection supports the selected protocols and semantics; it does not substitute for the planned runtime verification.