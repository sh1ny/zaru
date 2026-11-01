# Review (independent Claude pass)

## Metadata

- **Target:** `implement-core-language` (M1 core language) at commit `d4a10cf75f51c0aaade6f86d9fbb4a2f7742577f`, same checkout `F:/Dev/Orca/Workspace/zaru`.
- **Reviewer:** Claude, dispatched through Orca (task `task_9cb87848c174`, dispatch `ctx_00f1e73d9a56`).
- **Model:** `claude-opus-5-5`, as stated by the runtime system context. **Effort:** unknown.
- **Mode:** Read-only architecture and design review. I modified no repository file other than this one. I ran no builds, tests, analyzer, formatter, implementation, or reference `jq` executable. I did not read authoring transcripts. I did my own pass first and only then read `review.md` (round 2, codex) to avoid repeating resolved findings. None of the findings below repeat a finding that review resolved.
- **Change artifacts reviewed (in full):**
  - `openspec/changes/implement-core-language/proposal.md`
  - `openspec/changes/implement-core-language/design.md`
  - `openspec/changes/implement-core-language/specs/filter-compilation/spec.md`
  - `openspec/changes/implement-core-language/specs/filter-execution/spec.md`
  - `openspec/changes/implement-core-language/specs/conformance-accounting/spec.md`
  - `openspec/changes/implement-core-language/tasks.md`
  - `openspec/changes/implement-core-language/review.md` (after my independent pass)
- **Repository context reviewed:** `docs/adr/0001-parser-strategy.md`, `docs/adr/0002-evaluation-model.md`, `lib/zaru.dart`, `docs/api.md`, `pubspec.yaml`, `mise.toml`, `AGENTS.md`, `.github/workflows/ci.yml`, `test/conformance/{fixtures.dart,runner_test.dart,jq.test,man.test,PROVENANCE.json,VERSION,skip.txt}`, and `.agents/skills/{dart-add-unit-test,dart-write-documentation}/SKILL.md`.
- **Pinned upstream sources inspected:** I downloaded these read-only to a temp directory outside the repository, from `raw.githubusercontent.com/jqlang/jq/34f7186b86743a083a589741b6cea95293524108/`: `src/jq_test.c`, `src/jv.c`, `src/jv_aux.c`, `src/jv_print.c`, `src/jv_parse.c`, `src/builtin.c`, `src/builtin.jq`, `src/parser.y`, `src/lexer.l`.
- **Static fixture scans:** Two throwaway Python scripts, kept outside the repository, read `jq.test` and `man.test` without executing jq:
  - The first lists every evaluation case that has no expected outputs.
  - The second lists every expected numeric output that does not round-trip through an IEEE double.
- **Evidence limits:** No zaru engine exists at M0, so I treated the current empty library and the deliberately failing runner as baseline, not as defects. I did not run jq 1.8.2 probes. Claims about jq behavior come from the pinned C/jq sources and fixtures cited inline.

## Findings

### Critical (blocking)

**C1 — `%%FAIL` diagnostic-text conformance is required by the specs but undesigned, untasked, and unrepresentable by the planned error type.**

- **Upstream behavior.** In `src/jq_test.c:150-167`, under `%%FAIL` the runner matches every expected diagnostic line against jq's captured `jq: error...` text as a running prefix (`strncmp(buf, err_buf, strlen(buf))`). Any unconsumed remainder fails as an "extra message".
- **What the fixtures expect.** The fixture text is jq's full rendered diagnostic: message, `at <top-level>, line L, column C:`, a four-space source excerpt, and a caret line whose width is the error span. Examples:
  - `jq.test:62-66`: `Invalid escape at line 1, column 4 (while parsing '"\v"') at <top-level>, line 1, column 3:` followed by `      ^^`.
  - `jq.test:323-327`: `$*label-foo is not defined ...`, with a 10-caret span.
  - `jq.test:547-550`: Bison text `syntax error, unexpected ']', expecting BINDING or '[' or '{'`.
  - `jq.test:2074-2077`: `unexpected end of file`, reported at column 1 rather than at end of input.
  - `jq.test:2080-2083`: `unexpected INVALID_CHARACTER, expecting end of file`.
- **The specs require this.** D6 and `conformance-accounting` say "`%%FAIL IGNORE MSG` SHALL ignore only diagnostic text", so plain `%%FAIL` checks text. The acceptance requirement then makes "every pinned `jq.test` case using only M1 features" mandatory.
- **M1-only cases affected.** At least 11 cases use only M1 syntax and check text: `jq.test:62, 126, 132, 138, 323, 547, 553, 559, 565, 2074, 2080`.
- **No artifact plans for it:**
  - D3 promises only "one-based line/column and source diagnostics".
  - The compile scenario asserts only line, column, and a non-empty message.
  - The planned `ZaruCompileError(line, col, message)` in `docs/api.md:131` carries no span end, so the caret width cannot be rendered.
  - Tasks 3.1/3.2 and 7.x contain no jq-format diagnostic renderer or message catalogue.
  - The design's Risks section ("Diagnostic text differs from jq C output") gives no decision.
- **Missing semantic compile errors.** Several of these cases are compile-time semantic errors that the spec's compile-error list omits:
  - Constant non-string object keys: `{(0):1}` at `jq.test:126`, `{non_const:., (0):1}` at column 16 (`jq.test:138`), and `. as {(true):$foo}` (`jq.test:565`).
  - The error production `{1+2:3}` → `May need parentheses around object key expression` (`jq.test:132`).

  If these are evaluated as runtime errors, then besides failing the fixtures, `try {(0):1} catch .` would yield a caught value where jq refuses to compile.
- **Consequence.** As written, the M1 gate cannot be met without work no task owns. The cheapest path for an implementer is to weaken the `%%FAIL` comparison or reclassify these cases as non-M1, which is exactly the inflation AGENTS.md forbids.
- **Correction.** Decide explicitly in D3/D6 and the specs:
  1. Add a requirement that compile diagnostics carry a source span (start and end line/column). Also require that the conformance runner render jq's `jq: error: <message> at <top-level>, line L, column C:\n    <source line>\n    <carets>` format, so `%%FAIL` compares like upstream.
  2. Add compile-time constant-key validation and the `May need parentheses` production to `filter-compilation`, with jq's messages.
  3. For Bison-generated syntax messages, either commit to a jq-compatible message table for the token/expectation sets the corpus observes, with tasks in 3.x, or classify those specific IDs (`547, 553, 2074, 2080`, and `1987` once `%` is reachable) as a documented intentional divergence in `docs/compat.md`. Such IDs stay failing in the report and outside the M1 acceptance set, with that reason recorded.

  Either way, extend `ZaruCompileError` with a span before task 2/3 exports it.

**C2 — The approved `ZaruNumber` boundary has no specified public contract, even though the design rates its reversal cost High.**

The approval itself is not in question. The gap is that the artifacts do not specify the type that the approval covers:

- `filter-execution` mentions it only as "the approved narrow exact-number type when native numbers lose precision or jq-preserved literal form" (`spec.md`, requirement "Preserve JSON values and printed forms").
- D4 explicitly defers "precise normalization and classification rules" to parity probes "before export".
- Task 2.2 nevertheless exports it.

No requirement or test-map row defines any of the following:

- **Classification predicate.** Which untouched literals become `ZaruNumber`. Examples: `1.00`, `1.0`, `1E+2`/`1e2`, `100e-2` (printed `1.00` per `man.test:21-23`), `-0`, the 2^53 < |n| < 2^63 integers, and `jq.test:661`'s `9E+999999999`. D4 also requires platform-independent classification, which forces `9007199254740993` to be a `ZaruNumber` on the VM too. That consequence is never stated.
- **API surface.** Constructors (is it caller-constructible, for example from a JSON numeric string?), accessors (canonical text, `toDouble()` with jq's conversion, exact integer access), `==`/`hashCode` (spelling-sensitive or value-based; is `ZaruNumber('1.00') == ZaruNumber('1.0')`?), `toString`, and `Comparable`.
- **Input acceptance.** Whether `ZaruNumber` is accepted as `run` input and as `args` values, including nested in caller collections.
- **Consumer pitfall.** Dart's `int`/`double`/`num` cannot be implemented by user classes, so consumer code that tests `value is num` silently skips these values. This needs documentation.
- **Native-ingestion origin.** D4 says ingestion "reconstruct[s] the JSON literal represented by the native number's normalized spelling", but Dart's spelling is platform-dependent (`1.0.toString()` is `1.0` on the VM and `1` on dart2js). Whether a native number enters with literal or computed origin changes evaluator results. For example, VM `int` `9007199254740993` with filter `. == 9007199254740992` is `false` under literal-literal decimal comparison and `true` under double comparison (`jv.c:769-802`).

**Correction.** Before task 2.2, add a `filter-execution` requirement, plus test-map rows, that pins:

1. The classification predicate: untouched literal whose jq canonical text differs from the jq printing of its double conversion, or that exceeds the platform-independent exact range.
2. The constructor/accessor/equality/hash/`toString` contract.
3. Acceptance as input and arguments.
4. A platform-independent origin rule for native `int`/`double` inputs, defined numerically rather than via `toString()`.
5. Documented `is num` behavior.

Fold the same rules into task 1.1's superseding ADR.

### Moderate

**M1 — jq's literal-to-double conversion is two-step, which the design does not record.**

- **Upstream behavior.** `jvp_literal_number_to_double` (`jv.c:601-621`) first applies `decNumberReduce` in a decimal64-derived context with `digits = 17` (`DEC_NUMBER_DOUBLE_PRECISION`, `jv.c:209`), then `jvp_strtod`s the 17-digit string. This is double rounding, not the correctly rounded parse of Dart's `double.parse`.
- **Example.** The literal `9007199254740993.00000000001` reduces to `9007199254740993.0`, an exact binary midpoint, so jq ties to even and gets `9007199254740992`. A correctly rounded parse gives `9007199254740994`. The difference is observable via `. + 0`, or via mixed comparison against a computed value.
- **Why it matters.** D4 says binary arithmetic "uses jq's double conversion" without defining it.
- **Correction.** State the rule in D4 and the new ADR: round to 17 significant digits, half-even, then convert correctly rounded. Add a parity row (VM, dart2js, wasm) for a >17-digit literal adjacent to a midpoint.

**M2 — The milestone gate and the passed-ID floor have no executable pass/fail signal.**

- `mise run conformance` (`mise.toml:15-16`) runs all 781 cases. After M1, all non-M1 cases still fail, so the command and the CI `checks` job (`.github/workflows/ci.yml`, "Run jq conformance") stay red indefinitely.
- The `conformance-accounting` requirement says the floor "SHALL reject lost previously passing IDs" and that every M1 case "SHALL pass". However, tasks 7.3/7.4 specify no command, test, or exit status that distinguishes "acceptable red baseline" from "regression or unmet gate".
- If the gate is evaluated inside the same red run, for example in `tearDownAll`, a lost pass is indistinguishable from the expected baseline failures.
- **Correction.** Specify a separate mise task or tagged test, for example `mise run conformance-gate`. It should succeed only when every M1 acceptance ID passes and no floor ID is lost, and it should be wired as a required CI step. Keep the full-corpus run as reporting, with its expected-red status made explicit rather than masking the gate.

**M3 — The acceptance set is classified after the engine exists, and it ignores `man.test`.**

- Task 7.3 classifies `jq.test` cases into M1 or non-M1 only after 7.2 has run the real engine. That ordering lets the acceptance set be fitted to observed failures, which the design's own risk bullet warns about.
- The `conformance-accounting` requirement classifies only `jq.test`. That excludes 231 `man.test` cases from the M1 gate, although many use only core syntax (for example `man.test:1` `.`, `man.test:5` `.`, and `man.test:90` `.[]`).
- **Correction.** Classify both corpora from parser-level syntax and builtin dependencies before task 4, and freeze the manifest. Require that any later move of a case out of M1 cite a concrete non-M1 dependency in the diff.

**M4 — The runtime-termination manifest is not proven exhaustive.**

- Upstream accepts any invalid `jq_next` after the expected outputs (`jq_test.c:205-245`; the superfluous check at 232-240 tests only `jv_is_valid`).
- D6 lists four observed cases and then requires normal exhaustion everywhere else. My scan confirms that `945/949/953/957` are 4 of only 7 empty-output evaluation cases. The others are `jq.test:2071`, `jq.test:2086`, and `man.test:90`.
- However, no task scans the corpus with jq 1.8.2 for non-empty cases that also end in an error. Any such case would fail a faithful zaru engine.
- The planned remedy, manifest additions "reviewed" during 7.4 while the same implementer is fixing failures, is reactive and blurs the line between bug and expectation.
- **Correction.** Add a task before 7.2: run the pinned jq once over all runnable cases, record terminal kind and error value per ID with provenance (jq version and command), and derive the manifest only from that artifact.

**M5 — Structural equality must reproduce jq's identity shortcut; ordering must not.**

- `jvp_equal` (`jv.c:2087-2100`) returns equal for identical allocations before descending or checking depth at each level. `jvp_cmp` (`jv_aux.c:618-623`) has no such shortcut.
- So in jq, `(reduce range(10001) as $_ ([]; [.])) as $x | $x == $x` is `true`. Meanwhile `[$x, $x] | sort` raises `Comparison too deep` (`jq.test:2620`), and two distinct deep values raise `Equality check too deep` (`jq.test:2616`).
- The design's "Structural equality and ordering" resource row treats them alike. A plain iterative depth-checked equality would raise where jq returns `true`.
- **Correction.** Specify an `identical()` short-circuit at every node of equality, though not of ordering, and add the `$x == $x` scenario. This is natural because engine values are shared immutably.

**M6 — String slicing and ordering use code points and UTF-8 bytes, not Dart UTF-16.**

- jq slices strings by code point (`jv_string_slice`, `jv.c:1486-1511`) and orders strings by UTF-8 bytes (`string_cmp`, `jv_aux.c:561-569`). Ordering also sorts object keys for comparison and `sortKeys` printing.
- Dart's `substring`/`compareTo` use UTF-16 code units. For example, `"\uFFFD" < "😀"` is `true` in jq, but Dart's `compareTo` orders `0xFFFD` after the lead surrogate `0xD83D`. Likewise `"😀abc" | .[1:]` yields `"abc"` in jq but a broken surrogate under naive slicing.
- jq's parser replaces invalid sequences with U+FFFD (`jv_parse.c:493`). The handling of lone surrogates in caller strings is unspecified.
- The spec requires slice and comparison parity but no artifact names this host mismatch. Task 4.3 already uses UTF-8 lengths for repetition, so the knowledge exists but is not applied.
- **Correction.** Add a requirement and rows for code-point slicing, UTF-8 order in `<`/sort-keys printing, and the policy for lone surrogates from native input.

**M7 — Comma- and pipe-tail recursion through ported helpers has no spec or test coverage.**

- The ported `repeat` (`builtin.jq:185-188`, `exp, _repeat`), `while` (`builtin.jq:135-138`, `., (update | _while)`), `range/3` (via `while`, `builtin.jq:152-155`), `until`, and `recurse`/`..` (`builtin.jq:37-39`) recurse in the right operand of comma and pipe.
- The design asserts "Tail calls reuse continuation positions", and task 5.2 mentions deep tail recursion. However, no requirement defines tail positions or bounds retained frames. The only huge-prefix scenario uses natively implemented `range/2`.
- With nested Dart iterators, `[limit(1000000; repeat(1))] | length` or `last(range(0; 1000000; 1))` can exhaust the host stack, notably on dart2js. jq handles these with a heap stack.
- **Correction.** Add `filter-execution` scenarios and test-map rows (VM and Chrome) for 10^6-step `repeat` and `range/3` consumption and for `..` over 10,001-deep nesting. Define tail positions as the comma RHS, pipe RHS, and `if`/`elif`/`else` branches, with O(1) retained frames per step.

**M8 — `%%FAIL IGNORE MSG` can pass because a feature is unsupported.**

- `jq.test:1981` (`import "syntaxerror" as e; .`) expects compile failure because the imported module has a syntax error.
- M1 has no module loading, so zaru would reject `import` for an unrelated reason and the case would count as passed. It would then enter the passed-ID floor.
- The spec's "invoking the real compiler" does not prevent this.
- **Correction.** Introduce an internal "unsupported construct" compile-failure category that never satisfies `%%FAIL`/`%%FAIL IGNORE MSG`, or explicitly force `jq.test:1981` to fail until module loading lands. Record the reason in the report.

**M9 — Non-finite input and output behavior conflicts with the design's failure table and is unspecified for `fromJson`.**

- jq prints NaN as `null` and clamps ±infinity to `±1.7976931348623157e+308` (`jv_print.c:255-273`). Its parser accepts `nan`/`NaN`/`Infinity` tokens: `jq.test:1307` has input `[1,null,Infinity,-Infinity,NaN,-NaN]`, and PROVENANCE `protocol.json` notes these.
- Two artifacts point the other way:
  - The design's Failure table: "Printer | ... invalid number cannot be silently substituted → explicit error".
  - Task 2.1: "invalid JSON" tests with no stated grammar.

  Together they could lead to rejecting jq-accepted inputs or erroring on output that jq prints.
- **Correction.** Specify `Zaru.fromJson`'s accepted grammar as `jv_parse`'s, including BOM and the non-finite tokens, and their public mapping (`double.nan`, `double.infinity`). Specify printer output for non-finite numbers exactly as `jv_print`. Reserve explicit printer errors for non-JSON caller objects.

### Suggestions

- **S1.** Name the literal canonicalization algorithm in D4/ADR: decNumber `to-scientific-string` without trimming (`jv.c:680-700`). The corpus anchors it: `100e-2` → `1.00`, `1e2` → `1E+2`, `0.000000001E-999999990` → `1E-999999999`, `9999999999E999999990` → `9.999999999E+999999999` (`jq.test:661-666`, `man.test:21-23`).
- **S2.** State that the oracle converts a computed double to its exact-decimal form via jq's shortest round-trip printing (`jvp_dtoa_fmt`), not via the binary expansion. My scan found that every expected numeric output in the corpus round-trips through a double, except the literal outputs at `jq.test:661`, `jq.test:2267` (abs preserves the literal, `builtin.jq:13`), and `man.test:5`. With that conversion, the exact oracle therefore agrees with upstream `jv_equal` mixed comparison on this corpus.
- **S3.** Inventory M1 grammar from `parser.y` and assign each production to M1 or to an explicit non-M1 reason. Productions to cover: `$__loc__` (`jq.test:1499, 2304`), `@format "..."` strings (`jq.test:102`), optional `else`, keyword-named fields/keys, `?//`, `reduce`/`foreach` arities, and parse-only `module`/`import`/`include`.
- **S4.** The test map places `conformance_accounting_test.dart` and `conformance_comparison_test.dart` in `test/unit/`, which `mise run web-test` runs in Chrome (`mise.toml:31-32`; AGENTS.md "browser-safe"). Keep them free of `dart:io` fixture and manifest reads, or tag them VM-only.
- **S5.** Specify iterator behavior after a thrown `ZaruRuntimeError`. Subsequent `moveNext` should return `false`, matching the Failed terminal state in the T2 diagram.
- **S6.** Add string-repetition edge rows from `builtin.c:341-344`/`jv.c:1376-1388`: negative or NaN count → `null`, and 0 ≤ n < 1 → `""` after truncation.
- **S7.** Record that zaru emulates a `USE_DECNUM` jq build. When `have_decnum`/`have_literal_numbers` (`builtin.c:2041-2042`) arrive, they must return `true`. Otherwise the numeric fixtures at `jq.test:2195-2232` and `man.test:9-26` exercise the wrong branch.

## Verdict

VERDICT: REVISE

The architecture, per-iterator ownership, lexical control-signal separation, structural limits, and runtime-termination policy are coherent with ADRs 0001/0002, and I did not reopen the approved `ZaruNumber` exception. Two blocking gaps remain:

- The conformance contract demands jq-exact `%%FAIL` diagnostics, which no requirement, task, or error type can produce.
- The durable public `ZaruNumber` boundary has no specified contract.

Nine moderate gaps would let a faithful implementation fail cases that jq passes (M1, M5, M6, M7, M9), or let the accounting overstate or mask progress (M2, M3, M4, M8).

## Required Changes

1. **C1:** Decide on and specify diagnostic rendering:
   - A span-bearing `ZaruCompileError`.
   - jq's `jq: error: ... at <top-level>, line L, column C:` excerpt-and-caret format in the runner.
   - Compile-time constant-key and `May need parentheses` errors.
   - Either a jq-compatible syntax-message table with tasks, or a documented divergence that keeps the Bison-text IDs failing and outside the M1 set.
2. **C2:** Add a `ZaruNumber` requirement and test rows covering the classification predicate, constructor/accessors/equality/hash/`toString`, acceptance as input and `args`, the numeric (not `toString`-based) native-ingestion origin rule, and documented `is num` behavior. Mirror these in the task 1.1 ADR before task 2.2 exports anything.
3. **M1:** Specify jq's two-step literal-to-double conversion and add a midpoint parity row.
4. **M2:** Add a separate, binary conformance-gate command and CI step for the M1 acceptance set and the passed-ID floor.
5. **M3:** Move classification before task 4, include `man.test`, and freeze it with justified-only reclassification.
6. **M4:** Add a reference scan task that derives the runtime-termination manifest from one recorded jq 1.8.2 run over the whole corpus.
7. **M5:** Specify the identity shortcut for equality (not ordering), with a `$x == $x` deep scenario.
8. **M6:** Specify code-point slicing, UTF-8 byte ordering, and the lone-surrogate policy, with rows.
9. **M7:** Define tail positions and add 10^6-step `repeat`/`range/3` and deep `..` rows on VM and Chrome.
10. **M8:** Prevent unsupported-construct rejection from satisfying `%%FAIL IGNORE MSG` (`jq.test:1981`).
11. **M9:** Specify the `fromJson` grammar as `jv_parse`'s, including non-finite tokens and BOM, and specify jq's non-finite printing. Restrict printer errors to non-JSON caller objects.

CHANGES_APPLIED: n/a
