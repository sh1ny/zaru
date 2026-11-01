# filter-compilation Specification

## Purpose

Compile jq source into reusable filters with lexical scoping and actionable source-located diagnostics, without platform-specific runtime dependencies.

## Requirements

### Requirement: Compile core jq syntax
The library SHALL compile the complete M1 grammar: access/index/slice/optional/iteration, pipe/comma/grouping, JSON literals and constructors, arithmetic/comparison/boolean/alternative operators, conditionals, bindings/destructuring, reduce/foreach, definitions/parameters/recursion, recursive descent, interpolation, try/catch, and label/break. Invalid source SHALL raise a typed compile error before input evaluation.

#### Scenario: Compound reusable filter
- **WHEN** `.items[] | select(.active) | .name` is compiled once and run against two distinct JSON inputs
- **THEN** each run yields only the corresponding active names and shares no per-run iteration state

#### Scenario: Invalid source location
- **WHEN** source contains an unexpected `]` as the first token on line two
- **THEN** compilation raises `ZaruCompileError` with line 2, column 1, and a nonempty syntax diagnostic without evaluating input

### Requirement: Resolve lexical bindings and function parameters
Compilation SHALL distinguish value bindings, filter parameters, function arity, recursive definitions, and lexical labels. `$param` function-parameter sugar SHALL match jq. Undefined names, invalid arities, and out-of-scope break targets SHALL be compile errors rather than runtime fallbacks.

#### Scenario: Filter and value parameters
- **WHEN** `def twice(f): f | f; def plus($x): . + $x; twice(plus(2))` is compiled and run on 1
- **THEN** the output stream is `[5]`

#### Scenario: Lexical break validation
- **WHEN** `. as $foo | break $foo` is compiled without a surrounding `label $foo`
- **THEN** compilation raises a typed compile error for the undefined label rather than treating `$foo` as the label

### Requirement: Preserve literal source fidelity
Compilation SHALL preserve number spellings and string/interpolation boundaries without prematurely rounding through binary floating point. jq escapes, Unicode strings, comments, operator precedence, and nested interpolation SHALL remain jq syntax rather than host-language syntax.

#### Scenario: Large integer source
- **WHEN** `12345678909876543212345` is compiled
- **THEN** its complete source digits remain available for untouched jq output on VM and web targets

#### Scenario: Escaped interpolation marker
- **WHEN** a jq string contains an escaped backslash followed by parentheses rather than an interpolation opener
- **THEN** it remains literal string content rather than executing an embedded filter

### Requirement: Declare external argument names at compilation
The compiler SHALL accept external variable declarations independently from per-run values. Declared variables SHALL resolve during compilation and receive values from `run` or `runJson` arguments. Undeclared references SHALL remain compile errors. Missing declared values SHALL raise a typed runtime error on the iterator's first moveNext, before any filter output, rather than at run/iterator creation or by silently binding null.

#### Scenario: Rebind a compiled external variable
- **WHEN** `. > $min` is compiled with external variable `min` declared and run on 5 with `min` equal to 3 and then 7
- **THEN** the separate runs yield true and false respectively

#### Scenario: Missing declaration or value
- **WHEN** `$min` has no lexical or external declaration, or a declared `min` has no supplied run value
- **THEN** the first case fails compilation; for the second, run and iterator creation succeed but the first moveNext raises the typed missing-argument error before yielding

### Requirement: Preserve jq compile diagnostics
Compile errors SHALL retain one-based UTF-8-byte source spans, including exclusive ends, and ordered jq-rendered diagnostic blocks. `ZaruCompileError` SHALL expose first-diagnostic line/col/endLine/endCol/message and immutable rendered `diagnostics`. Rendering SHALL follow pinned jq's excerpts, caret widths, token names, expected-token messages, and EOF locations; corpus IDs SHALL NOT select compiler behavior.

#### Scenario: Successful source has no diagnostics
- **WHEN** a valid identity filter is compiled
- **THEN** compilation succeeds without emitting or retaining an error diagnostic

#### Scenario: Lexical diagnostic preserves span and excerpt
- **WHEN** the invalid escape source in jq.test:62 is compiled
- **THEN** the error contains the pinned jq message, reported start coordinates, source excerpt, and two-caret width from its source span

#### Scenario: Grammar-derived syntax diagnostics
- **WHEN** the binding, unexpected-EOF, and invalid-character sources in jq.test:547, jq.test:2074, and jq.test:2080 are compiled
- **THEN** their rendered diagnostics match the pinned fixture blocks, including expected tokens and jq's EOF location convention

#### Scenario: Diagnostics are not keyed to fixtures
- **WHEN** an invalid constant-key expression is moved within a filter or a bound variable is renamed
- **THEN** the diagnostic names and span are derived from the new source rather than copied from a fixture-ID lookup

### Requirement: Reject statically invalid object keys during compilation
Constant non-string object keys and invalid unparenthesized key expressions SHALL fail compilation with jq's semantic diagnostic and span. They SHALL NOT be deferred into catchable runtime errors. Dynamic key expressions that can yield strings SHALL remain executable and receive runtime key-type checks.

#### Scenario: Valid dynamic key
- **WHEN** `{(.key): .value}` is compiled and run on `{"key":"a","value":2}`
- **THEN** it yields `{"a":2}`

#### Scenario: Constant invalid key is not catchable
- **WHEN** `try {(0):1} catch .` is compiled
- **THEN** compilation fails with jq's `Cannot use number (0) as object key` diagnostic instead of yielding a caught runtime value

#### Scenario: Missing key parentheses
- **WHEN** `{1+2:3}` is compiled
- **THEN** ordered diagnostics contain the initial unexpected-LITERAL syntax error followed by jq's `May need parentheses around object key expression` block with its pinned span; message exposes the first error, while the conformance callback selects the last jq-error block

### Requirement: Distinguish unsupported constructs from semantic compile failures
Known deferred syntax such as module/import/include and non-M1 format operations SHALL be recognized or classified explicitly, not misrepresented as a supported semantic failure. Unsupported-construct failures SHALL carry an internal category usable by the conformance runner and SHALL never satisfy an expected compile-error fixture.

#### Scenario: Core undefined variable remains a semantic error
- **WHEN** an undeclared core variable is compiled without deferred syntax
- **THEN** the compiler reports the jq-compatible undefined-variable diagnostic eligible for its corresponding compile-error fixture

#### Scenario: Unsupported import cannot manufacture conformance
- **WHEN** jq.test:1981 is compiled before module loading is implemented
- **THEN** it remains an unsupported-construct failure, not a passing `%%FAIL IGNORE MSG` case
