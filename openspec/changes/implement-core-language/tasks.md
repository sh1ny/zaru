# Tasks

## Test map

All scenarios are new. `red` denotes unimplemented planned coverage, not a claim that these tests have already been created or executed. Use real library boundaries and deterministic values; no mock echoes, source-text assertions, or tests that merely check wiring. Each implementation task makes its own mapped rows green only after the complete behavior passes.

| Requirement | Scenario | Test file | Test name | State |
|---|---|---|---|---|
| filter-compilation → Compile core jq syntax | Compound reusable filter | test/unit/compiler_test.dart | compiled filter reuses code without sharing run state | red |
| filter-compilation → Compile core jq syntax | Invalid source location | test/unit/compiler_test.dart | reports unexpected token at line two column one | red |
| filter-compilation → Resolve lexical bindings and function parameters | Filter and value parameters | test/unit/functions_test.dart | composes filter arguments and dollar parameter sugar | red |
| filter-compilation → Resolve lexical bindings and function parameters | Lexical break validation | test/unit/compiler_test.dart | rejects a value binding as a break label | red |
| filter-compilation → Preserve literal source fidelity | Large integer source | test/unit/numbers_test.dart | compiled literal preserves all source digits | red |
| filter-compilation → Preserve literal source fidelity | Escaped interpolation marker | test/unit/strings_test.dart | escaped interpolation opener stays literal | red |
| filter-compilation → Declare external argument names at compilation | Rebind a compiled external variable | test/unit/compiler_test.dart | declared external argument is rebound per run | red |
| filter-compilation → Declare external argument names at compilation | Missing declaration or value | test/unit/compiler_test.dart | distinguishes undeclared variables and missing run arguments | red |
| filter-execution → Expose lazy reusable result streams | Stop before a later error | test/unit/generators_test.dart | first does not consume a later error | red |
| filter-execution → Expose lazy reusable result streams | Huge range prefix | test/unit/generators_test.dart | limit consumes only three values of a huge range | red |
| filter-execution → Expose lazy reusable result streams | Empty is not null | test/unit/runtime_test.dart | distinguishes empty stream from a null output | red |
| filter-execution → Match jq core expressions | Alternative suppresses false and null | test/unit/operators_test.dart | alternative retains zero and empty string | red |
| filter-execution → Match jq core expressions | Invalid access versus optional access | test/unit/access_test.dart | optional field access suppresses a numeric indexing error | red |
| filter-execution → Match lexical binding and recursive control semantics | Reduction and extraction | test/unit/control_test.dart | reduce and foreach have distinct emission behavior | red |
| filter-execution → Match lexical binding and recursive control semantics | Lexically targeted break | test/unit/control_test.dart | break stops only its lexical label | red |
| filter-execution → Distinguish runtime errors from control flow | Catch after an earlier result | test/unit/errors_test.dart | catch preserves earlier values and receives the error value | red |
| filter-execution → Distinguish runtime errors from control flow | Error without catch | test/unit/errors_test.dart | uncaught error occurs after the earlier result | red |
| filter-execution → Preserve JSON values and printed forms | Integer-preserving printing | test/unit/printer_test.dart | computed integral double prints without a decimal suffix | red |
| filter-execution → Preserve JSON values and printed forms | Large literal pass-through | test/unit/numbers_test.dart | untouched large literal prints without rounding | red |
| filter-execution → Preserve JSON values and printed forms | Preserve literal form but not computed float spelling | test/unit/printer_test.dart | distinguishes preserved literal scale from computed spelling | red |
| filter-execution → Preserve JSON values and printed forms | Lossless input decoding | test/unit/numbers_test.dart | decoder preserves nested numeric IDs through identity | red |
| filter-execution → Preserve operation-specific numeric semantics | Negate large literal without rounding | test/unit/numbers_test.dart | unary negation retains literal integer and fraction precision | red |
| filter-execution → Preserve operation-specific numeric semantics | Mixed comparison after arithmetic rounding | test/unit/numbers_test.dart | mixed equality follows jq double fallback | red |
| filter-execution → Isolate engine-created collection outputs | Read an engine-created collection normally | test/unit/ownership_test.dart | created collections expose plain Dart collection interfaces | red |
| filter-execution → Isolate engine-created collection outputs | Literal reuse after mutation attempt | test/unit/ownership_test.dart | literal mutation attempt cannot corrupt a later run | red |
| filter-execution → Isolate engine-created collection outputs | Suspended accumulator isolation | test/unit/ownership_test.dart | yielded accumulator cannot mutate suspended execution | red |
| filter-execution → Apply jq structural limits before host failure | Deep object merge boundary | test/unit/operators_test.dart | object multiplication follows the jq merge depth boundary | red |
| filter-execution → Apply jq structural limits before host failure | Excessive structural equality | test/unit/operators_test.dart | deep equality produces a catchable jq error | red |
| filter-execution → Apply jq structural limits before host failure | Oversized repeated string | test/unit/operators_test.dart | rejects oversized repetition before allocating its result | red |
| conformance-accounting → Execute the complete pinned corpus honestly | Identity becomes supported | test/unit/conformance_accounting_test.dart | real identity execution contributes one passing case | red |
| conformance-accounting → Execute the complete pinned corpus honestly | Unsupported builtin remains visible | test/unit/conformance_accounting_test.dart | unsupported builtin fails without leaving the denominator | red |
| conformance-accounting → Compare observable outputs strictly | Duplicate outputs are significant | test/unit/conformance_comparison_test.dart | missing a duplicate output is a mismatch | red |
| conformance-accounting → Compare observable outputs strictly | Rounded large integer is different | test/unit/conformance_comparison_test.dart | exact oracle rejects rounded large integers | red |
| conformance-accounting → Compare observable outputs strictly | Equivalent numeric spelling | test/unit/conformance_comparison_test.dart | exact oracle accepts equal decimal values with different scale | red |
| conformance-accounting → Compare observable outputs strictly | Text is not numeric normalization | test/unit/conformance_comparison_test.dart | serialized JSON strings are compared byte for byte | red |
| conformance-accounting → Enforce milestone coverage and monotonic passing cases | Milestone complete | test/unit/conformance_accounting_test.dart | M1 gate requires every classified core case to pass | red |
| conformance-accounting → Enforce milestone coverage and monotonic passing cases | Equal count hides a regression | test/unit/conformance_accounting_test.dart | pass floor rejects a lost case despite an equal count | red |
| conformance-accounting → Account for runtime termination explicitly | Reference-backed runtime failure | test/unit/conformance_accounting_test.dart | reference runtime policy checks error value and termination kind | red |
| conformance-accounting → Account for runtime termination explicitly | Missing prefix | test/unit/conformance_accounting_test.dart | expected runtime termination cannot omit an earlier output | red |
| conformance-accounting → Account for runtime termination explicitly | Unexpected error after correct values | test/unit/conformance_accounting_test.dart | unlisted terminal error fails after matching the expected prefix | red |

## 1. Record the approved numeric boundary

- [ ] 1.1 Write a short superseding numeric-boundary ADR for the approved public ZaruNumber exception, native/JSON input interpretation, operation-specific origin rules, and lossless decoder/printer; create openspec/architecture.md indexing the existing accepted ADRs and the new decision. Verify consistency with approved design D4 and review round 2; do not edit accepted ADR 0002 in place.
- [ ] 1.2 Update the planned API documentation to name the approved numeric boundary and external variable declarations without claiming implementation; verify every advertised symbol is explicitly marked planned until its owning implementation lands and run strict OpenSpec validation.

## 2. Implement numeric values, lossless JSON, and printing

- [ ] 2.1 Add failing number/JSON/printer behavior tests for precision, scale/exponent normalization, Unicode escaping, insertion and sorted key order, compact/default/tab indentation, invalid JSON, and nonfinite computed output. Verify failures through MCP run_tests on the relevant new unit files before implementation.
- [ ] 2.2 Implement immutable exceptional numeric values and private literal/computed origin metadata, a lossless pure-Dart JSON decoder, and jq-compatible printer. Export only genuinely implemented ZaruNumber/fromJson/toJson behavior; verify mapped printer and decoder rows on VM and Chrome, add a mise-managed wasm test task, and prove numeric parity under dart2wasm. Document native-input precision limits and formatting in docs/api.md and docs/compat.md; update CHANGELOG.md.
- [ ] 2.3 Implement separate exact JSON numeric-value comparison support for the future conformance oracle, distinct from runtime mixed-origin comparison. Verify equal scale variants, huge exponents without exponent-sized allocation, unequal rounded IDs, preserved text, and malformed inputs with focused passing tests; document the distinction alongside number semantics.

## 3. Implement the jq lexer and parser

- [ ] 3.1 Add failing lexical/parse behavior tests for source locations, longest operators, comments, numeric lexemes, string escapes and nested interpolation, Pratt precedence, comma/pipe associativity, constructor shorthand/dynamic keys, structured forms, definitions, and destructuring alternatives. Verify each uncertain syntax boundary against the pinned jq grammar/corpus rather than host syntax; run the new targeted tests to observe the failures.
- [ ] 3.2 Implement source spans, lexer, AST, and Pratt/recursive-descent parser for the complete M1 grammar without evaluator stubs or a parser dependency. Verify targeted parser/lexer tests on VM and web; document actual supported syntax and diagnostic coordinates in docs/api.md and docs/compat.md, keeping execution claims separate from parsing support.

## 4. Implement compilation and the lazy core runtime

- [ ] 4.1 Add failing compiler/runtime/access/operator tests for identity, independent/interleaved runs and iterators, literal fidelity, compile-time syntax/name failures, declared externals versus missing values, ordered pipe/comma products, fields/indices/slices/iteration/optional access, and constructors. Verify the new failures via MCP before adding execution.
- [ ] 4.2 Implement immutable compiled filters, one-based typed compile errors, per-iterator continuations/environments, external declarations, core access/constructors/operators/conditionals, and genuinely lazy output. Preserve numeric origin internally and separate jq evaluator comparison from the exact fixture oracle. Verify mapped core/compiler rows, numeric literal end-to-end rows, interleaved consumption, caller input non-mutation, and branch ordering against jq 1.8.2; update public API docs and CHANGELOG.md in this task.
- [ ] 4.3 Add failing ownership and structural-operation boundary tests, then implement immutable engine-created collection nodes, fresh-or-shared-immutable literal templates, iterative equality/order/object merge, and preallocation UTF-8 repetition checks using the approved pinned limits. Verify normal collection reads, mutation isolation, merge success/failure boundary, catchable deep equality, and oversized repetition without large allocation; document caller-owned subtree sharing and typed resource failures.
- [ ] 4.4 Add a runnable library example using the actually supported core subset and a mise task to execute it. Smoke the real compiled filter on multiple inputs and observe a partial stream before a late error; verify the example output and update README's supported-feature statement without claiming a new conformance numerator before the real runner is connected.

## 5. Implement lexical functions, reductions, and error/control flow

- [ ] 5.1 Add failing function/control/error tests covering filter parameters, dollar-parameter sugar, recursive and shadowed definitions, lexical captures, destructuring and ?// alternatives, reduce/foreach backtracking, labels/break, try/catch, optional errors, error(null), and output before failure. Observe the targeted failures and check disputed behavior with the pinned jq executable.
- [ ] 5.2 Implement lexical binding/definition resolution, function invocation, explicit recursive continuations, reductions/extraction, runtime error values, and lexical break unwinding. Verify the mapped function/control/error rows, suspended accumulator isolation, all four recorded destructuring runtime failures, and deep tail recursion without host-stack growth. Update docs/api.md, docs/compat.md, and CHANGELOG.md for the implemented contracts.

## 6. Implement generator helpers, descent, and interpolation

- [ ] 6.1 Add failing tests for huge/unbounded generator prefixes, unused late errors, empty versus null, first/last/nth arities and edges, range direction/step products, until/while/repeat, recursive descent ordering, nested/escaped interpolation, and independent iterator reuse. Verify the failures through MCP before helper implementation.
- [ ] 6.2 Port the M1 helper definitions and their minimal transitive dependencies from jq-1.8.2 src/builtin.jq with original attribution; implement only primitives jq implements natively. Complete recursive descent and interpolation through the real runtime. Verify all generator/string rows, no eager suffix evaluation, range memory independence from bound, and escaped interpolation; update builtin provenance, API/compatibility docs, example, and CHANGELOG.md.
- [ ] 6.3 Verify the compound reusable-filter scenario and the complete M1 grammar together, including constructors, precedence, binding alternatives, function parameters, and lexical error scope. Add a focused regression only where an integration edge is not already caught by mapped tests; smoke the real example through its mise task and keep docs truthful about remaining M2 features.

## 7. Execute and account for the upstream corpus

- [ ] 7.1 Add failing real-engine conformance-comparison/accounting tests for every mapped accounting scenario, expected compile failure versus runtime failure, exact values versus printed strings, duplicate/order/length mismatches, partial runtime termination, and the pass-ID floor. Observe failures before replacing the M0 failure path; keep fixture parser infrastructure tests intact.
- [ ] 7.2 Replace the M0 artificial-failure runner with actual lossless decode/compile/iterate/compare/report execution. Preserve all 781 cases and original bytes; implement the explicit four-case runtime-expectation manifest from approved D6 with reference provenance, not parsed comment directives. Verify all accounting rows and complete per-case reports using the real engine; document terminal policies and remaining failures in docs/compat.md and skip.txt without blanket skips.
- [ ] 7.3 Classify every pinned jq.test case by its actual language/builtin dependencies into the full M1 acceptance set or explicit non-M1 reasons. Implement the checked-in passed-ID floor and M1 acceptance gate, without removing any case from total reporting. Verify missing IDs, duplicate IDs, lost passes, unchanged counts hiding a regression, and unpassed M1 cases all fail their gates; document classification and comparison policy beside corpus provenance.
- [ ] 7.4 Run the full real conformance command, fix every M1-only failure without weakening comparison, and update the passed-ID floor and README numerator from observed execution. Verify no previous pass is lost, all M1 acceptance IDs pass, all 781 cases are accounted for, and each actual skip has a specific reason. Update CHANGELOG.md and compatibility gaps in the same verified milestone change.

## 8. Verify milestone integration

- [ ] 8.1 Run the complete normal suite, analysis, and formatting through the official MCP tools and mise checks, then core tests on Chrome/dart2js and Chrome/dart2wasm through mise tasks. Verify no dart:io/native dependency reaches lib/, the example executes on the VM, and the version-only CLI still compiles; these are integration checks, not deferred unit-test or documentation work.
- [ ] 8.2 Smoke compile-once/multiple-input reuse, argument rebinding, multiple outputs, a huge generator prefix, a caught error after prior output, and exact numeric input/output using the actual public library. Verify the reported conformance numerator/floor and all mapped rows match exercised results; run strict OpenSpec validation and record the evidence without claiming M2/M3 behavior.

## Workflow follow-up

- Preserve conventional task commits through the jj backend and use the recorded sh1ny run identity for publication.
- After implementation verification and review, archive/finish only through the installed workflow; implementation has not started in this planning session.
