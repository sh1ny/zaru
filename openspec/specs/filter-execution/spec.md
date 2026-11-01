# filter-execution Specification

## Purpose

Execute compiled jq filters as ordered lazy streams over JSON-shaped Dart data, preserving jq control flow, errors, and output fidelity across VM and browser targets.

## Requirements

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

#### Scenario: Failed iterator is terminal
- **WHEN** an iterator has thrown an uncaught `ZaruRuntimeError` and its consumer calls `moveNext` again
- **THEN** `moveNext` returns false without replaying values, work, or the exception

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
- **WHEN** an identity filter uses runJson on an object containing `12345678909876543212345`
- **THEN** the printed ID retains every original digit on VM and web rather than first rounding during JSON decoding

### Requirement: Preserve operation-specific numeric semantics
Unary negation SHALL preserve literal precision. Binary arithmetic SHALL use jq's literal conversion: decimal64-context reduction with 17 significant digits and half-even rounding, then correctly rounded binary64 conversion. Literal/literal comparison SHALL use decimal values; computed/mixed operands SHALL follow jq's double fallback. This SHALL remain separate from the fixture oracle.

#### Scenario: Negate large literal without rounding
- **WHEN** `-.` runs on losslessly decoded `13911860366432393` and `-0.12345678901234567890123456789`
- **THEN** their printed results are `-13911860366432393` and `0.12345678901234567890123456789`

#### Scenario: Mixed comparison after arithmetic rounding
- **WHEN** `. as $n | $n + 0 | [., . == $n]` runs on losslessly decoded `13911860366432393`
- **THEN** it yields `[13911860366432392, true]` as jq does, not an arbitrary-precision sum or an exact-decimal mixed comparison

#### Scenario: Two-step rounding at a binary midpoint
- **WHEN** `9007199254740993.00000000001 + 0` is evaluated on VM, dart2js, and wasm
- **THEN** it yields `9007199254740992`, not the direct-binary-parse result `9007199254740994`

#### Scenario: Decimal context exponent edges
- **WHEN** literals `0e1000000000`, `1e-1000000000`, and `1e1000` are preserved, converted or used in arithmetic
- **THEN** their canonical text is `0E+999999999`, `1E-1000000000`, and `1E+1000` without exponent-sized padding; the latter is a finite ZaruNumber with infinite toDouble, and adding zero prints `1.7976931348623157e+308`

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
- **WHEN** two identical objects formed by nesting key `a` around an empty-object leaf are multiplied at nesting depths 10000 and 10001
- **THEN** the first operation completes and the second raises the jq error value `Object merge too deep`

#### Scenario: Excessive structural equality
- **WHEN** distinct arrays nested to depth 10001 are compared as in jq.test:2616
- **THEN** evaluation raises the catchable error value `Equality check too deep` rather than a host stack overflow

#### Scenario: Identity shortcut does not recurse through the same value
- **WHEN** a single 10001-deep array is bound as `$x` and `$x == $x` is evaluated
- **THEN** equality yields true without descending through the identical shared value; this shortcut does not apply to ordering

#### Scenario: Oversized repeated string
- **WHEN** `"abc" * 1000000000` is evaluated
- **THEN** it raises the catchable error value `Repeat string result too long` without allocating the requested multi-gigabyte result

#### Scenario: Repetition truncates counts and preserves jq null cases
- **WHEN** `"a"` is multiplied by negative, NaN, zero, and positive fractional counts below one
- **THEN** negative and NaN counts yield null while zero and positive fractional counts below one yield the empty string

### Requirement: Classify exceptional literal numbers consistently
For literal outputs C is pinned canonical text and D jq conversion. Export SHALL use ZaruNumber when C differs from computed printing of D or integer magnitude exceeds 9007199254740991; otherwise safe integers except negative zero SHALL export as int and other literals as double. Arithmetic results SHALL be double on VM/wasm; compatible native pass-through SHALL retain num subtype/storage. Only dart2js has subtype overlap. Classification SHALL be target-independent.

#### Scenario: Ordinary number remains plain
- **WHEN** an identity filter's runJson consumes `42` or `0.5`
- **THEN** each result is plain num, with 42 as int and 0.5 as double on VM/wasm and no portable subtype promise on dart2js; literal origin remains internal until export

#### Scenario: Precision and scale require a wrapper
- **WHEN** literals `1.00`, `1.0`, `1e2`, `100e-2`, `9007199254740993`, and `9E+999999999` cross the public output boundary
- **THEN** all return `ZaruNumber` on every target, with canonical literal text `1.00`, `1.0`, `1E+2`, `1.00`, `9007199254740993`, and `9E+999999999` respectively

#### Scenario: Literal negative zero follows jq canonicalization
- **WHEN** an identity filter's runJson consumes `-0`
- **THEN** it emits plain negative-zero double, toJson prints `-0` on every target, and jq equality with zero is true; this is distinct from the compiled filter expression `-0`, which jq folds to positive zero

### Requirement: Define the exact-number public API
Immutable final `ZaruNumber` SHALL expose `parse(String)`, canonical `literal`, `toDouble()`, `toString()`, value equality, and hashCode. Parse SHALL accept exactly one finite jq numeric token and reject malformed/nonfinite results with FormatException. ToString SHALL equal literal; toDouble SHALL use jq's two-step conversion. No implicit num subtype, Comparable, or lossy native conversion SHALL be supplied.

#### Scenario: Explicit construction and canonical text
- **WHEN** `ZaruNumber.parse("100e-2")` is constructed
- **THEN** literal and toString are `1.00`, toDouble is 1, and the object is not a Dart num

#### Scenario: Invalid exact-number construction
- **WHEN** parse receives `NaN`, `Infinity`, a numeric token normalized to infinity by jq, or `1x`
- **THEN** it throws FormatException instead of constructing a finite exact-number object

### Requirement: Define exact-number equality and acceptance
ZaruNumber equality/hash SHALL use exact mathematical decimal value, ignoring equivalent scale/exponent spelling and zero sign. Equality SHALL compare only ZaruNumber instances; it SHALL be false against native num. Exact values SHALL be accepted as root/nested run inputs and argument values. Ordinary automatic output classification still applies; Dart object identity across evaluation SHALL NOT be guaranteed.

#### Scenario: Equal numbers can have distinct preserved spellings
- **WHEN** `ZaruNumber.parse("1.00")` and `ZaruNumber.parse("1.0")` are compared
- **THEN** they are equal with identical hash codes but retain distinct literal text, and neither equals native 1

#### Scenario: Exact input survives nested and argument boundaries
- **WHEN** a nested ID and an external argument contain a ZaruNumber larger than the common exact integer range
- **THEN** filters can access and emit both without rounding or rejecting the type

### Requirement: Interpret native numeric input independently of platform spelling
Native finite values exactly representable as binary64 SHALL enter as jq computed numbers and export as plain num under identity, preserving signed zero. Only integers that fail exact binary64 round-trip SHALL enter with exact literal origin. This decision SHALL be numeric, not based on Dart spelling, VM int capacity, or int-versus-double subtype. Already-rounded caller values SHALL NOT be repaired; runJson or explicit ZaruNumber supplies literal origin.

#### Scenario: Integral native doubles have no source scale
- **WHEN** numerically identical native values 1 and 1.0 are run through identity on VM and web
- **THEN** both produce computed-origin plain numeric 1 without inventing a `.0` source scale

#### Scenario: Unsafe native input cannot recover missing digits
- **WHEN** a JavaScript-backed caller has already rounded 9007199254740993 to 9007199254740992 before calling run
- **THEN** zaru evaluates the supplied 9007199254740992 as a computed number; callers needing the original use runJson or ZaruNumber.parse

#### Scenario: Ordinary native doubles stay plain
- **WHEN** identity runs on native `0.00001`, `1.5e-7`, `1e16`, `1e23`, and `1e300` on each target
- **THEN** each output is an equal plain num, never ZaruNumber, and toJson uses jq's computed spelling rather than an expanded integer coefficient

#### Scenario: Native large-double comparison uses fallback
- **WHEN** `. == 1e23` runs on native double `1e23`
- **THEN** it yields true through jq's computed/literal double comparison, not false through an invented exact decimal coefficient

#### Scenario: Native nonrepresentable integer retains exactness
- **WHEN** a caller supplies an integer whose exact binary64 round-trip fails, such as 9007199254740993 where the host can represent it
- **THEN** it enters as an exact literal and identity emits ZaruNumber with that coefficient; a host that already rounded the input cannot take this branch for the lost value

#### Scenario: Native signed zero survives identity
- **WHEN** identity runs on native negative-zero double and the result is printed
- **THEN** it remains a plain num whose JSON text is `-0` and whose numeric equality with zero is true

### Requirement: Decode and print jq numeric extensions
The runJson decoder SHALL follow pinned jv_parse, including BOM and accepted nonfinite numeric tokens. Nonfinite values SHALL map to native NaN/infinity at export. Printing NaN SHALL produce null and computed infinities SHALL clamp to jq's signed maximum finite double; finite literal wrappers SHALL retain canonical text. Unsupported caller data SHALL remain errors. Negative zero SHALL print `-0`, not `0`, on every target.

#### Scenario: BOM and nonfinite inputs
- **WHEN** an identity filter's runJson consumes a BOM-prefixed `[NaN,Infinity,-Infinity,-NaN]`
- **THEN** it returns the corresponding native nonfinite values and toJson prints `[null,1.7976931348623157e+308,-1.7976931348623157e+308,null]` in compact mode

#### Scenario: Numeric input grammar is jq grammar
- **WHEN** identity uses runJson on the single tokens `+1`, `01`, `.5`, and `1.`
- **THEN** their compact outputs are `1`, `1`, `0.5`, and `1` respectively, rather than rejecting them solely because RFC-only JSON excludes those forms

#### Scenario: Invalid JSON and escaped surrogate errors remain errors
- **WHEN** runJson receives trailing extra values, malformed numeric input, or a lone high-surrogate escape such as `"\\ud800"`
- **THEN** its first moveNext throws FormatException and the iterator becomes terminal instead of yielding a successful null value

### Requirement: Match jq Unicode slicing and ordering
String slicing SHALL use Unicode code points; numeric string indexing SHALL raise jq runtime errors, not return characters. Comparisons/sorted printing SHALL use unsigned UTF-8 order. Native and raw unescaped lone surrogates SHALL normalize to U+FFFD without caller mutation. JSON escapes SHALL follow jv_parse separately: lone high escapes are invalid and lone low escapes normalize to U+FFFD.

#### Scenario: Astral code point slice
- **WHEN** `. [1:]` is evaluated on `"😀abc"`
- **THEN** it yields `"abc"` without splitting a surrogate pair

#### Scenario: String and sorted-key order
- **WHEN** U+FFFD and 😀 are compared or used as keys in sorted printing
- **THEN** U+FFFD sorts before 😀 as in jq, not in Dart UTF-16 code-unit order

#### Scenario: Numeric string indexing is an error
- **WHEN** `.[1]`, `.[1]?`, and `.[1:2]` run on `"😀abc"`
- **THEN** numeric indexing raises ZaruRuntimeError carrying `Cannot index string with number (1)`, optional indexing yields nothing, and slicing yields `"a"`

#### Scenario: Fractional and negative string slice bounds
- **WHEN** `.[1.5:2.7]` and `.[-1:]` run on `"😀abc"`
- **THEN** they yield `"ab"` and `"c"` respectively, using jq's floored start, ceiled end, and negative-bound handling in code-point positions

#### Scenario: Native and JSON-text surrogate boundaries
- **WHEN** a native string or raw unescaped runJson string contains an unpaired high surrogate, JSON text has an escaped lone low surrogate, or JSON text has an escaped lone high surrogate
- **THEN** the first three cases normalize to U+FFFD and the escaped-high case is a FormatException, matching their distinct ingestion boundaries

### Requirement: Keep recursive generators stack-safe in tail positions
Comma RHS, pipe RHS, and conditional result branches SHALL support tail calls without retaining a frame per completed step when no sibling work remains. Deferred alternatives SHALL retain only their genuinely pending state. Recursive descent SHALL use traversal-depth storage rather than host recursion; no hidden result cap SHALL alter jq semantics.

#### Scenario: Million-step recursive helpers
- **WHEN** a consumer counts `limit(1000000; repeat(1))` and consumes `last(range(0; 1000000; 1))` on VM and Chrome
- **THEN** the first stream contains exactly 1000000 ones and the second yields 999999 without host-stack growth per step

#### Scenario: Deep descent is not structural equality
- **WHEN** `(reduce range(10001) as $_ ([]; [.])) | ..` is run on null, constructing the deep value inside the filter rather than parsing it as JSON text
- **THEN** it emits all 10002 array nodes ending in the empty array without applying equality's depth guard or overflowing the host stack

### Requirement: Execute JSON text without discarding literal origin
Compiled filters SHALL expose runJson(String, {Map<String, Object?> args = const {}}) as lazy Iterable<Object?>. First moveNext SHALL decode one origin-bearing value before evaluation/export. Empty, whitespace-only, malformed or extra input SHALL throw FormatException with original source, zero-based UTF-16 offset and a message containing jq line/UTF-8-byte column where applicable; the iterator then terminates. M1 SHALL NOT expose public fromJson.

#### Scenario: Literal origin survives before public narrowing
- **WHEN** `. == 42.0000000000000001` uses runJson on `42`, and separately run on native 42
- **THEN** JSON-text evaluation yields false while native computed evaluation yields true, matching jq's literal/literal versus computed/literal rules without boxing ordinary public 42

#### Scenario: JSON text errors are lazy and terminal
- **WHEN** runJson is called with malformed text and its iterable and iterator are created
- **THEN** those creations succeed; first moveNext throws FormatException and subsequent moveNext returns false

#### Scenario: Empty JSON text is not an input stream
- **WHEN** runJson receives empty or whitespace-only text
- **THEN** first moveNext throws FormatException for a missing single value, while the later CLI must treat its own empty stdin as an empty stream rather than reuse this single-value API contract

### Requirement: Handle deep JSON boundaries iteratively
Decode/export/printing SHALL be iterative on VM/dart2js/wasm. Decoder SHALL reject a container opening at >=10000 pending parser slots (containers plus object-key slots), raising FormatException with `Exceeds depth limit for parsing`. Printer SHALL start at depth zero and emit unquoted `<skipped: too deep>` at depth above 10000; such output is not valid JSON. Native/constructed values SHALL NOT inherit the parser's input budget.

#### Scenario: Array parsing depth boundary
- **WHEN** runJson consumes 10000 and 10001 nested arrays around zero
- **THEN** the first emits its full nested value; the second throws FormatException with original source, offset 10000 and message containing `Exceeds depth limit for parsing at line 1, column 10001`, without host-stack failure

#### Scenario: Object keys consume parser stack slots
- **WHEN** runJson consumes 5000 and 5001 nested objects each using key a around a zero leaf
- **THEN** the first succeeds and the second raises the parsing-depth FormatException because pending object keys also consume stack slots

#### Scenario: Printer depth boundary is jq truncation
- **WHEN** toJson compactly prints native values constructed as 10000 and 10001 nested arrays around null
- **THEN** the first contains the null leaf and no marker, while the second replaces the leaf with unquoted `<skipped: too deep>` and keeps all surrounding brackets, matching jq rather than returning valid substitute JSON

### Requirement: Reuse immutable public projections
Export SHALL iteratively memoize a public projection on each immutable engine container node. Each node SHALL create at most one immutable List/Map projection, reused by repeated yields and sharing. No run/global strong-key cache SHALL retain completed stream nodes. Caller-owned mutable containers SHALL NOT be memoized or frozen. Scalar ZaruNumber identity SHALL remain unspecified.

#### Scenario: Repeated subtree yields reuse one projection
- **WHEN** `.x, .x` uses runJson on an object containing an array subtree with preserved numeric literals
- **THEN** both results are the identical immutable public List with correctly narrowed elements, rather than independently rebuilt copies

#### Scenario: Changed containers do not alias projections
- **WHEN** `., . + [2]` uses runJson on `[1]`
- **THEN** it yields distinct immutable Lists `[1]` and `[1,2]`, and creating the second projection cannot change the first

### Requirement: Normalize native projection-changing paths once
Native ingestion SHALL iteratively rebuild any caller container path whose public projection differs into immutable engine nodes, retaining numeric origin until evaluation. This includes narrowable wrappers, exact-origin integers and normalized strings/keys. Unchanged public-compatible storage SHALL be reused, not memoized or frozen. Rebuilt engine nodes SHALL use the normal projection memo. Caller data SHALL remain unchanged.

#### Scenario: Native narrowing paths become owned once
- **WHEN** `., ., (.[0] == 42.0000000000000001)` runs on a caller list containing ZaruNumber.parse("42")
- **THEN** the first two results are the identical immutable List containing plain integer 42, the final result is false because internal literal origin survives, and the mutable caller list still contains its original wrapper

#### Scenario: Public-compatible native storage remains shared
- **WHEN** identity runs on a caller list containing native 42 and `"a"` with no normalization or scalar narrowing needed
- **THEN** it returns that caller list by reference without freezing it or converting its native number subtype; caller mutation remains caller-input mutation rather than engine-state mutation
