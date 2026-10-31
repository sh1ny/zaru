# Spec Delta

## Purpose

Compile jq source into reusable filters with lexical scoping and actionable source-located diagnostics, without platform-specific runtime dependencies.

## ADDED Requirements

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
The compiler SHALL accept optional external variable declarations independently from per-run values. Declared variables SHALL resolve during compilation and receive their values from `run(..., args: ...)`. Undeclared variable references SHALL remain compile errors; missing declared values SHALL raise a typed runtime error rather than silently bind null.

#### Scenario: Rebind a compiled external variable
- **WHEN** `. > $min` is compiled with external variable `min` declared and run on 5 with `min` equal to 3 and then 7
- **THEN** the separate runs yield true and false respectively

#### Scenario: Missing declaration or value
- **WHEN** `$min` has no lexical or external declaration, or a declared `min` has no supplied run value
- **THEN** the first case fails compilation and the second fails evaluation with a typed missing-argument error
