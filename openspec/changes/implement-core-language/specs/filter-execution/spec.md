# Spec Delta

## Purpose

Execute compiled jq filters as ordered lazy streams over JSON-shaped Dart data, preserving jq control flow, errors, and output fidelity across VM and browser targets.

## ADDED Requirements

### Requirement: Expose lazy reusable result streams
A compiled filter SHALL expose `run(input, args: ...)` as `Iterable<Object?>`. Iteration SHALL preserve jq result ordering, duplicates, and zero results distinctly from a null result. Runs and iterators SHALL have independent environments. Consuming a prefix SHALL not evaluate discarded suffixes or materialize unbounded generator output.

#### Scenario: Stop before a later error
- **WHEN** `first(1, error("late"))` is run on null
- **THEN** it yields exactly 1 without evaluating the error

#### Scenario: Huge range prefix
- **WHEN** `limit(3; range(0; 1000000000000))` is consumed
- **THEN** it yields 0, 1, 2 without enumerating or retaining the remaining range

#### Scenario: Empty is not null
- **WHEN** `empty` and `null` are each run on the same input
- **THEN** the former yields no results and the latter yields one null result

### Requirement: Match jq core expressions
Evaluation SHALL match jq for identity, field/index/slice access, optional access and iteration, pipe/comma/grouping, literals, array/object construction including shorthand and dynamic keys, arithmetic/comparison, `and/or/not`, `//`, and `if/elif/else/end`. Object output order SHALL follow insertion order unless sorting is requested. Only null and false SHALL be falsey.

#### Scenario: Alternative suppresses false and null
- **WHEN** `(false, null, 0, "") // 9` is evaluated
- **THEN** it yields 0 followed by the empty string, not 9

#### Scenario: Invalid access versus optional access
- **WHEN** `.a` and `.a?` are run on the number 1
- **THEN** `.a` raises a typed runtime error and `.a?` yields no results

### Requirement: Match lexical binding and recursive control semantics
Bindings, destructuring, user definitions, filter/value parameters, recursion, reduce, foreach, recursive descent, interpolation, and the M1 control functions SHALL match jq's environment, input, ordering, and backtracking behavior. The M1 functions SHALL include empty/select/not/error/limit/first/last/nth/until/while/repeat/range, porting upstream jq definitions when applicable.

#### Scenario: Reduction and extraction
- **WHEN** `reduce .[] as $x (0; . + $x)` and `foreach .[] as $x (0; . + $x; .)` run on `[1,2,3]`
- **THEN** reduce yields 6 and foreach yields 1, 3, 6

#### Scenario: Lexically targeted break
- **WHEN** `[label $here | .[] | if . > 1 then break $here else . end]` runs on `[0,2,1]`
- **THEN** it yields the single array `[0]` and does not visit the final 1

### Requirement: Distinguish runtime errors from control flow
Data failures SHALL raise `ZaruRuntimeError` during consumption and carry the error value. jq try/catch and `?` SHALL handle runtime failures, not compile failures or lexical breaks. `error(null)` SHALL raise an error carrying null, as observed in jq 1.8.2. Results emitted before a later runtime error SHALL not be erased.

#### Scenario: Catch after an earlier result
- **WHEN** `try (1, error("bad")) catch .` is consumed
- **THEN** it yields 1 followed by the string `bad`

#### Scenario: Error without catch
- **WHEN** `(1, error("bad"))` is consumed without a handler
- **THEN** the first result is 1 and subsequent consumption throws `ZaruRuntimeError` carrying `bad`

### Requirement: Preserve JSON values and printed forms
Public values SHALL be plain Dart JSON-shaped values except for the approved narrow exact-number type when native numbers lose precision or jq-preserved literal form. Inputs SHALL NOT be mutated. Printing SHALL match jq's compact/indented/tab/sorted forms and escaping; computed integral doubles SHALL print as integers. Lossless decoding SHALL preserve numeric information before evaluation. Rounding or precision errors SHALL NOT count as compatible output.

#### Scenario: Integer-preserving printing
- **WHEN** a native/computed numeric result equal to 1.0 is printed without untouched-literal metadata
- **THEN** its JSON number text is `1`, not `1.0`

#### Scenario: Large literal pass-through
- **WHEN** an untouched `12345678909876543212345` literal reaches printing on VM or web
- **THEN** its digits remain exactly `12345678909876543212345`, without binary-double rounding

#### Scenario: Preserve literal form but not computed float spelling
- **WHEN** the jq literal `1.00` and the native Dart value `1.0` are printed
- **THEN** the untouched literal retains jq's `1.00` form and the native computed-style value prints `1`

#### Scenario: Lossless input decoding
- **WHEN** `Zaru.fromJson` decodes an object containing `12345678909876543212345` and its ID passes through an identity filter
- **THEN** the printed ID retains every original digit on VM and web rather than first rounding during JSON decoding

### Requirement: Preserve operation-specific numeric semantics
Unary negation of an untouched literal SHALL preserve exact numeric precision. Binary arithmetic SHALL follow jq's double conversion. Evaluator equality/order SHALL distinguish literal/literal comparison from computed or mixed operands as jq does; this SHALL be separate from the conformance runner's lossless JSON value oracle.

#### Scenario: Negate large literal without rounding
- **WHEN** `-.` runs on losslessly decoded `13911860366432393` and `-0.12345678901234567890123456789`
- **THEN** their printed results are `-13911860366432393` and `0.12345678901234567890123456789`

#### Scenario: Mixed comparison after arithmetic rounding
- **WHEN** `. as $n | $n + 0 | [., . == $n]` runs on losslessly decoded `13911860366432393`
- **THEN** it yields `[13911860366432392, true]` as jq does, not an arbitrary-precision sum or an exact-decimal mixed comparison

### Requirement: Isolate engine-created collection outputs
Every List/Map node created by the engine SHALL be immutable before exposure, including compiled literal containers and yielded accumulator nodes. No consumer mutation SHALL change another run or a suspended iterator. Immutable engine children can share. Caller-owned input subtrees can remain shared without a snapshot; their external mutation remains caller input mutation.

#### Scenario: Read an engine-created collection normally
- **WHEN** `[1, {a: 2}]` is evaluated and its output is inspected without mutation
- **THEN** it exposes the ordinary Dart List/Map interfaces and values `[1, {a: 2}]`

#### Scenario: Literal reuse after mutation attempt
- **WHEN** a consumer tries to append to the engine-created result of `[1]` before starting another run
- **THEN** mutation raises `UnsupportedError`, and the next run still yields `[1]`

#### Scenario: Suspended accumulator isolation
- **WHEN** a consumer tries to mutate the first engine-created array yielded by `foreach .[] as $x ([]; . + [$x]; .)` on `[1,2]`
- **THEN** mutation raises `UnsupportedError`, and continued iteration yields `[1,2]` unaffected

### Requirement: Apply jq structural limits before host failure
Core equality/order, recursive object multiplication, and string repetition SHALL enforce the pinned jq structural/size limits with catchable typed runtime errors. Deep operations SHALL NOT rely on host recursion depth, and repetition SHALL check UTF-8 result size before allocation. Original inputs SHALL remain unchanged when these operations fail.

#### Scenario: Deep object merge boundary
- **WHEN** objects nested through key `a` are multiplied at depths 10000 and 10001
- **THEN** the first operation completes and the second raises the jq error value `Object merge too deep`

#### Scenario: Excessive structural equality
- **WHEN** distinct arrays nested to depth 10001 are compared as in jq.test:2616
- **THEN** evaluation raises the catchable error value `Equality check too deep` rather than a host stack overflow

#### Scenario: Oversized repeated string
- **WHEN** `"abc" * 1000000000` is evaluated
- **THEN** it raises the catchable error value `Repeat string result too long` without allocating the requested multi-gigabyte result
