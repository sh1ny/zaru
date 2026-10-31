# Spec Delta

## Purpose

Measure actual jq compatibility against the pinned upstream corpus, preserving every case and making regressions and milestone acceptance visible rather than hiding unsupported behavior.

## ADDED Requirements

### Requirement: Execute the complete pinned corpus honestly
The conformance runner SHALL execute all 781 pinned cases and report actual pass/fail/not-run/skip counts. Expected compile errors SHALL pass only after invoking the real compiler and validating the fixture's error policy. Unsupported filters SHALL fail, not silently skip. Vendored fixture bytes and stable source-line IDs SHALL remain unchanged.

#### Scenario: Identity becomes supported
- **WHEN** the compiled identity filter produces the exact expected stream for a pinned fixture
- **THEN** that case is reported as passed and contributes exactly one to the numerator

#### Scenario: Unsupported builtin remains visible
- **WHEN** a fixture depends on an unimplemented M2 builtin
- **THEN** it remains failed in the same 781-case denominator with a diagnostic reason

### Requirement: Compare observable outputs strictly
Execution SHALL match stream length/order/duplicates and losslessly compared JSON values. Finite numeric values SHALL be compared exactly independent of equivalent spelling, separately from jq's evaluator equality. Fixture-observed text SHALL match exactly. Runtime failure SHALL NOT satisfy compile failure; `%%FAIL IGNORE MSG` SHALL ignore only diagnostic text, not the requirement to fail compilation.

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

### Requirement: Enforce milestone coverage and monotonic passing cases
A checked-in acceptance manifest SHALL identify every pinned `jq.test` case using only M1 features, with explicit dependencies for excluded-from-M1 cases but no exclusion from total reporting. Every M1 acceptance case SHALL pass before M1 completes. A checked-in passed-case floor SHALL reject lost previously passing IDs; README's numerator SHALL equal the executed result and SHALL NOT decrease.

#### Scenario: Milestone complete
- **WHEN** all M1-only cases pass and every remaining case is still accounted for
- **THEN** M1's acceptance gate passes while the report still exposes remaining non-core failures

#### Scenario: Equal count hides a regression
- **WHEN** one previously passing case fails and a different case starts passing
- **THEN** the passed-case floor fails despite an unchanged total passing count

### Requirement: Account for runtime termination explicitly
The runner SHALL require normal exhaustion unless a reviewed, reference-backed side manifest specifies the expected output prefix and typed runtime error value for a stable case ID. Pinned cases jq.test:945, jq.test:949, jq.test:953, and jq.test:957 SHALL require empty output and error value `Cannot index array with string ("a")`. Comments SHALL NOT be executable directives. Early/wrong/host failures and extra outputs SHALL fail.

#### Scenario: Reference-backed runtime failure
- **WHEN** one of the four recorded destructuring cases emits no values and terminates with the exact expected typed runtime error
- **THEN** it passes, and its report retains runtime-error termination separately from normal exhaustion

#### Scenario: Missing prefix
- **WHEN** a recorded runtime expectation requires output 1 followed by error `"bad"`, but execution raises `"bad"` before yielding 1
- **THEN** the fixture fails for missing expected output

#### Scenario: Unexpected error after correct values
- **WHEN** an ordinary evaluation fixture emits all expected values and then raises an unrecorded runtime error
- **THEN** it fails rather than treating the exception as ordinary stream exhaustion
