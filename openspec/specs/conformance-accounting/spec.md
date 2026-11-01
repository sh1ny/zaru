# conformance-accounting Specification

## Purpose

Measure actual jq compatibility against the pinned upstream corpus, preserving every case and making regressions and milestone acceptance visible rather than hiding unsupported behavior.

## Requirements

### Requirement: Execute the complete pinned corpus honestly
The conformance runner SHALL execute all 781 pinned cases and report actual pass/fail/not-run/skip counts. Expected compile errors SHALL pass only after invoking the real compiler and validating the fixture's error policy. Unsupported filters SHALL fail, not silently skip. Vendored fixture bytes and stable source-line IDs SHALL remain unchanged.

#### Scenario: Identity becomes supported
- **WHEN** the compiled identity filter produces the exact expected stream for a pinned fixture
- **THEN** that case is reported as passed and contributes exactly one to the numerator

#### Scenario: Unsupported builtin remains visible
- **WHEN** a fixture depends on an unimplemented M2 builtin
- **THEN** it remains failed in the same 781-case denominator with a diagnostic reason

### Requirement: Compare observable outputs strictly
Execution SHALL match stream length/order/duplicates and losslessly compared JSON values. Finite numbers SHALL compare exactly independent of spelling, separately from evaluator equality. Nonfinite actual values SHALL NOT become matching null/finite values through printing. Observed text SHALL match exactly. Runtime failures SHALL NOT satisfy compile failures; `%%FAIL IGNORE MSG` SHALL ignore only diagnostic text.

#### Scenario: Duplicate outputs are significant
- **WHEN** the expected stream contains two identical values but execution yields only one
- **THEN** the fixture fails

#### Scenario: Rounded large integer is different
- **WHEN** expected output is `12345678909876543212345` but actual output is `12345678909876543000000`
- **THEN** the fixture fails even if a host double conversion would equate them

#### Scenario: Equivalent numeric spelling
- **WHEN** actual JSON output is `2` and the fixture expects the JSON number `2.0`
- **THEN** value comparison passes, without imposing a textual equality check absent from that fixture

#### Scenario: Text is not numeric normalization
- **WHEN** a `tojson` fixture expects the string `"1.00"` but receives `"1"`
- **THEN** the fixture fails even though the represented numbers are mathematically equal

#### Scenario: Compile failure caused by unsupported syntax is not a pass
- **WHEN** an unsupported import rejects jq.test:1981 before the imported module's intended syntax error is reached
- **THEN** the fixture stays failed with an unsupported-feature reason even under `%%FAIL IGNORE MSG`

#### Scenario: Rendered diagnostics follow upstream callback policy
- **WHEN** a `%%FAIL` fixture has expected source excerpts and carets
- **THEN** it compares the last compiler-produced block prefixed `jq: error` using pinned line-prefix matching, while the public error retains its first diagnostic and all ordered rendered blocks

#### Scenario: Nonfinite values cannot match printed substitutes
- **WHEN** execution produces NaN where JSON null is expected, or infinity where a finite maximum-double value is expected
- **THEN** both cases fail value comparison rather than passing after NaN-to-null or infinity-clamping serialization

### Requirement: Enforce milestone coverage and monotonic passing cases
A frozen pre-engine manifest SHALL classify all jq.test and man.test cases by grammar/builtin dependencies, not by observed zaru success. Every M1-only case SHALL pass before M1 completes; non-M1 cases remain in the full report. A passed-ID floor SHALL reject lost prior passes, even at equal counts. README's numerator SHALL equal actual execution and SHALL NOT decrease. Reclassification SHALL cite a concrete dependency in a reviewed diff.

#### Scenario: Milestone complete
- **WHEN** all M1-only cases pass and every remaining case is still accounted for
- **THEN** M1's acceptance gate passes while the report still exposes remaining non-core failures

#### Scenario: Equal count hides a regression
- **WHEN** one previously passing case fails and a different case starts passing
- **THEN** the passed-case floor fails despite an unchanged total passing count

#### Scenario: Manual core case participates in acceptance
- **WHEN** the core identity case man.test:1 is classified before the engine exists
- **THEN** it is required by the M1 gate even though its source is man.test rather than jq.test

#### Scenario: Classification cannot be fitted to a failing engine
- **WHEN** an M1-classified case fails after engine implementation without any new non-M1 dependency evidence
- **THEN** the gate fails and its classification is not weakened to make the run pass

### Requirement: Account for runtime termination explicitly
Before engine execution, an exhaustive pinned-jq reference census SHALL record all 781 cases' output/diagnostics, termination and runtime error values with source/environment provenance. Checked-in census payloads SHALL have integrity hashes and complete IDs. Regeneration SHALL be explicit, never triggered by zaru failures. Zaru runs SHALL validate frozen baseline integrity/coverage and match prefix/termination/value without invoking native jq.

#### Scenario: Reference-backed runtime failure
- **WHEN** one of the four recorded destructuring cases emits no values and terminates with the exact expected typed runtime error
- **THEN** it passes, and its report retains runtime-error termination separately from normal exhaustion

#### Scenario: Missing prefix
- **WHEN** a recorded runtime expectation requires output 1 followed by error `"bad"`, but execution raises `"bad"` before yielding 1
- **THEN** the fixture fails for missing expected output

#### Scenario: Unexpected error after correct values
- **WHEN** an ordinary evaluation fixture emits all expected values and then raises an unrecorded runtime error
- **THEN** it fails rather than treating the exception as ordinary stream exhaustion

#### Scenario: Reference census covers nonempty error prefixes
- **WHEN** pinned jq emits expected values before a terminal runtime error for any case, including cases with nonempty expected output
- **THEN** the pre-engine census records both the complete prefix and error value and the runtime manifest derives that expectation

#### Scenario: Incomplete reference environment blocks acceptance
- **WHEN** reference generation lacks a required module asset, driver environment, reference result, or binary/version check
- **THEN** it reports the missing prerequisite and cannot publish a complete baseline; the gate rejects a missing/incomplete baseline, not the absence of jq on the later gate machine

### Requirement: Expose an independently actionable conformance gate
Conformance commands SHALL freshly execute all 781 IDs against verified frozen references without jq/regeneration. Gate success SHALL require complete accounting and all M1/floor passes; full conformance SHALL fail for any failure. CI SHALL isolate checks, JS/wasm core tests, CLI compile, gate and full-corpus jobs. M1 SHALL require all except full-corpus green, without masking failures. This milestone policy SHALL NOT claim or authorize GitHub branch protection.

#### Scenario: Gate can pass while the full corpus remains red
- **WHEN** every M1 and floor case passes but unimplemented non-M1 cases fail
- **THEN** conformance-gate returns zero and reports all remaining failures, while conformance returns nonzero

#### Scenario: Regression is distinguishable from expected baseline failures
- **WHEN** a previously passing ID or required M1 case fails
- **THEN** conformance-gate returns nonzero even if the full command was already red

#### Scenario: Stale reports cannot satisfy a gate
- **WHEN** a previous build report says all required cases passed but current engine execution fails one
- **THEN** the fresh gate invocation fails instead of accepting the previous report

#### Scenario: Gate needs no native reference binary
- **WHEN** the checked-in reference baseline passes hash/ID/provenance validation and every M1/floor case passes on a machine without jq
- **THEN** conformance-gate returns zero after actual zaru execution without spawning a reference process

#### Scenario: Changed baseline payload fails integrity
- **WHEN** a checked-in reference payload is changed without its recorded integrity hash being updated
- **THEN** both conformance commands reject the baseline instead of evaluating against an unverified reference
