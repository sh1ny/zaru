# jq 1.8.2 reference grammar and builtin inventory

This inventory is derived from the commit-pinned jq 1.8.2 release source:

- Upstream: <https://github.com/jqlang/jq/tree/34f7186b86743a083a589741b6cea95293524108>
- Commit: `34f7186b86743a083a589741b6cea95293524108`
- Grammar and lexer: `src/parser.y`, `src/lexer.l`
- jq-coded builtins: `src/builtin.jq` (embedded as `src/builtin.inc`)
- Native and bytecoded builtins: `src/builtin.c`, `src/libm.h`
- Fixture parser/driver: `src/jq_test.c`

The local evidence was fetched from the official jq 1.8.2 release source archive; its SHA-256 is `332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c`. The fixture bytes in this repository remain the primary test inputs; this source inventory is not regenerated from, or conditioned on, execution results.

## Grammar productions

`src/parser.y` defines these productions (including error alternatives) and no implicit extension syntax:

| Production | Scope |
| --- | --- |
| `TopLevel`, `Module`, `Imports`, `Import`, `ImportWhat`, `ImportFrom` | Top-level query/function/module/import forms |
| `FuncDefs`, `FuncDef`, `Params`, `Param` | Definitions and semicolon-separated filter/value parameters |
| `Query`, `Expr`, `Term` | Query composition, operators, access, construction, control, and calls |
| `StringStart`, `String`, `QString` | Format prefixes, string segments, and interpolation |
| `ElseBody` | `elif`, optional `else`, `end` |
| `Args`, `Arg` | Semicolon-separated filter arguments |
| `RepPatterns`, `Patterns`, `Pattern`, `ArrayPats`, `ObjPats`, `ObjPat`, `Keyword` | Binding/destructuring, `?//`, keyword object keys |
| `DictPairs`, `DictPair`, `DictExpr` | Object construction and keyed value expressions |

The production details that are easy to misclassify are part of the source contract: `foreach` accepts both `(init; update)` and `(init; update; extract)` forms; `reduce` has `(init; update)`; `if` uses `ElseBody`, whose `end` alternative makes `else` optional; object keys may be identifiers, keywords, strings, bindings, `($__loc__)`, or parenthesized expressions; the `?//` alternative applies to destructuring patterns. `$$$$name` is a private literal-argument binding form used inside jq's own `_modify`; the grammar source explicitly says not to use it in user filters. `$__loc__`, imports, module declarations, and the update operators are present in jq's grammar, not evidence that they are M1-supported.

## Lexer inventory

`src/lexer.l` recognizes, in addition to whitespace and comments:

- Reserved words: `as`, `import`, `include`, `module`, `def`, `if`, `then`, `else`, `elif`, `and`, `or`, `end`, `reduce`, `foreach`, `try`, `catch`, `label`, `break`.
- Multi-character operators/tokens: `!=`, `==`, `//`, `|=`, `+=`, `-=`, `*=`, `/=`, `%=`, `//=`, `<=`, `>=`, `..`, `?//`.
- Single-character punctuation/operators: `.`, `?`, `=`, `;`, `,`, `:`, `|`, `+`, `-`, `*`, `/`, `%`, `$`, `<`, `>`; balanced `[]`, `{}`, `()` are state-checked.
- Literal/name token classes: `LITERAL` for JSON-number syntax; `QQSTRING_START`, `QQSTRING_TEXT`, `QQSTRING_INTERP_START`, `QQSTRING_INTERP_END`, and `QQSTRING_END` for quoted strings and `\\(...)`; `FORMAT` for `@format`; `IDENT` for qualified identifiers (`ns::name`); `FIELD` for `.name`; `BINDING` for `$name`; `LOC` for `$__loc__`; and `INVALID_CHARACTER` for invalid characters or unmatched delimiters.

The grammar additionally treats `as`, `def`, `module`, `import`, `include`, `if`, `then`, `else`, `elif`, `reduce`, `foreach`, `end`, `and`, `or`, `try`, `catch`, `label`, and `break` as `Keyword` in object-key positions. `true`, `false`, and `null` are parsed as identifiers and converted to literals by the grammar action.

## Builtin source classes and classification rules

jq's callable names have three distinct source origins. The compiler must not label an unknown name M2 just because it is absent from one builtin list:

1. **jq-coded definitions**: `src/builtin.jq`, included as `src/builtin.inc` at build time. Its definitions are `halt_error`, `error`, `map`, `select`, `sort_by`, `group_by`, `unique_by`, `max_by`, `min_by`, `add`, `del`, `abs`, `_assign`, `_modify`, `map_values`, `recurse`, `to_entries`, `from_entries`, `with_entries`, `reverse`, `indices`, `index`, `rindex`, `paths`, `isfinite`, `arrays`, `objects`, `iterables`, `booleans`, `numbers`, `normals`, `finites`, `strings`, `nulls`, `values`, `scalars`, `join`, `_flatten`, `flatten`, `range`, `fromdateiso8601`, `todateiso8601`, `fromdate`, `todate`, `ltrimstr`, `rtrimstr`, `trimstr`, `match`, `test`, `capture`, `scan`, `splits`, `split`, `sub`, `gsub`, `while`, `until`, `limit`, `skip`, `first`, `isempty`, `all`, `any`, `nth`, `last`, `combinations`, `transpose`, `in`, `inside`, `repeat`, `inputs`, `ascii_downcase`, `ascii_upcase`, `truncate_stream`, `fromstream`, `tostream`, `walk`, `pick`, `debug`, `INDEX`, `JOIN`, and `IN`. The overloads are significant: `add/0,1`, `recurse/0,1,2`, `paths/0,1`, `range/1,2,3`, `fromdate/todate`, `match/test/capture/scan/splits/split/sub/gsub`, `while/until/limit/skip/first/nth`, `all/any`, `combinations/0,1`, `isempty/1`, and `INDEX/JOIN/IN` have multiple definitions. jq-coded private helpers include `_assign`, `_modify`, `_flatten`, `_match_impl`, and implementation helpers ending in `_impl`.
2. **Native C definitions**: `src/builtin.c`'s `function_list`, including `_negate`; the `_plus`, `_minus`, `_multiply`, `_divide`, `_mod`, `_equal`, `_notequal`, `_less`, `_greater`, `_lesseq`, `_greatereq` operator bindings; `tojson`, `fromjson`, `tonumber`, `toboolean`, `tostring`, `keys`, `keys_unsorted`, `startswith`, `endswith`, `split`, `explode`, `implode`, `_strindices`, `trim`, `ltrim`, `rtrim`, `setpath`, `getpath`, `delpaths`, `has`, `contains`, `length`, `utf8bytelength`, `type`, `isinfinite`, `isnan`, `isnormal`, `infinite`, `nan`, `sort`, `_sort_by_impl`, `_group_by_impl`, `unique`, `_unique_by_impl`, `bsearch`, `min`, `max`, `_min_by_impl`, `_max_by_impl`, `error`, `format`, `env`, `halt`, `halt_error`, `get_search_list`, `get_prog_origin`, `get_jq_origin`, `_match_impl`, `modulemeta`, `input`, `debug`, `stderr`, `strptime`, `strftime`, `strflocaltime`, `mktime`, `gmtime`, `localtime`, `now`, `input_filename`, `input_line_number`, `have_decnum`, and `have_literal_numbers`. Arity is explicit in each `CFUNC` registration; the public jq-coded wrappers and private helper names are distinct entries.
3. **Platform/build-dependent math C names**: names supplied by `src/libm.h` (`acos`, `acosh`, `asin`, `asinh`, `atan`, `atan2`, `atanh`, `cbrt`, `cos`, `cosh`, `exp`, `exp2`, `floor`, `hypot`, `j0`, `j1`, `log`, `log10`, `log2`, `pow`, `remainder`, `sin`, `sinh`, `sqrt`, `tan`, `tanh`, `tgamma`, `y0`, `y1`, `jn`, `yn`, `ceil`, `copysign`, `drem`, `erf`, `erfc`, `exp10`, `expm1`, `fabs`, `fdim`, `fma`, `fmax`, `fmin`, `fmod`, `gamma`, `lgamma`, `log1p`, `logb`, `nearbyint`, `nextafter`, `nexttoward`, `rint`, `round`, `scalb`, `scalbln`, `significand`, `trunc`, `ldexp`, `modf`, `frexp`, `lgamma_r`). Availability can depend on configure-time feature macros; the names must not be treated as portable M1 merely because they appear in the source.

`empty`, `not`, `path`, `last`, and `range` also have jq-compiler bytecoded definitions in `src/builtin.c`. The `builtins` builtin is added after the source list is bound. These origins must remain distinguishable from the jq-coded and ordinary C registries.

M1-supported filter constructs and builtins are those explicitly specified by the change's filter-compilation and filter-execution deltas and its design. The source-derived M1 callable set is `empty`, `not`, `error`, `format`, `tostring`, `select`, `recurse`, `range`, `while`, `until`, `limit`, `skip`, `first`, `last`, `nth`, and `repeat`; `format` is allowed only as the implicit text-format dependency of interpolation, not as an arbitrary public formatter. The checked classification manifest records the selected public arity, source origin, and dependency evidence.

The supporting closure follows pinned `src/builtin.jq`:
- `error/1` is jq-defined as `msg | error`, calling native `error/0` (line 2). C registry arities include the implicit input; manifest arities do not.
- `select/1` uses `empty/0` (line 4).
- `recurse/0` calls `recurse/1`; `recurse/1` has an independent local recursive `r/0`; `recurse/2` has its own local `r/0` and calls `select/1`, hence `empty/0` (lines 37–39).
- `range/1` calls bytecoded `range/2` (line 73). Separately, `range/3` uses `while/2` and `empty/0` (lines 150–154).
- `while/2`, `until/2`, and `repeat/1` use their local recursive `_while`, `_until`, and `_repeat` helpers. `while/2` also uses `empty/0`.
- `limit/2` uses `foreach`, `label`/`break`, `empty/0`, and `error/1`; `skip/2` uses `foreach`, `empty/0`, and `error/1` (lines 143–149).
- `nth/2` composes `skip/2`, `first/1`, and `error/1`; `first/1` uses `label`/`break`. Bare `first/0`, `last/0`, and `nth/1` use indexing (lines 155–174). Generator `last/1` is bytecoded in `src/builtin.c`.

The bytecoded `path` entry is not part of this callable allowlist. Formats (`@format`), `$__loc__`, update assignment/operators, imports/modules, and other non-core dependencies remain explicitly deferred where the plan says so. A fixture involving these remains in the fixed 781-case denominator and must have its own source-based classification; diagnostic-message fixtures are not excluded on difficulty. Inventory labels describe required language/dependency surface, not observed engine or jq output.

## Corpus accounting

The stable identifier is `<source>:<program-line>` (`jq.test:<line>` or `man.test:<line>`), as exposed by `JqFixture.id`. The corpus is 550 active cases in `jq.test` plus 231 in `man.test`, 781 total; commented-out and generated-only examples are not active fixture IDs. Classification must enumerate every parsed active fixture ID, including compile-error and unsupported-directive kinds, and retain every case in that denominator. The generated per-ID classification is maintained separately from this source inventory in `test/conformance/reference/classification.json`. It records one source-backed row for every active stable ID: fixture kind, the original program and program line, grammar forms, object keys, bindings, direct names, builtin source origin, and the M1/deferred/core-undefined classification. Module-qualified names and `$ENV`/`$ARGS` remain explicit deferred dependencies; a name absent from the pinned registries is recorded as a core undefined-name case, never presumed to be an M2 builtin. Compile-error fixtures remain in the same denominator.

Regenerate only with `mise run reference-classification`. The command verifies the unchanged fixture SHA-256 values and the pinned parser/lexer/builtin source hashes from `.dart_tool/reference/jq-1.8.2` before writing the manifest. It is source-only and does not invoke jq or zaru. The generated rows and source lists are evidence for classification, not observations of evaluator behavior; later reclassification requires reviewed grammar/builtin-source evidence and a diff, not a zaru failure.

## Task 3.4 parser cross-check

All 781 frozen `sourceEvidence.program` strings were parsed by the group-3
parser and compared with their annotations without editing the frozen
classification. No evaluation case is rejected by the parser; every deferred
form (`@format`, assignment/update operators, `$__loc__`, `import`, `include`,
`module`) matches its unsupported record, and no `M1-core-candidate` case
contains deferred syntax. Sixteen compile-error programs fail at parse level.

One annotation is imprecise: `jq.test:1988` (`%::wat`) is labelled
`core-undefined-name-diagnostic` with `unknownCoreNames: ["wat"]`, but the pinned
diagnostic is `syntax error, unexpected '%', expecting end of file`; no name
lookup occurs. Both labels are core (non-deferred) classes, so the case stays in
the core acceptance set either way. The source-only token scan has no grammar
rule that could distinguish this case without consulting runtime evidence, so
the frozen row is retained rather than re-fitted; the census remains the
authority for its expected diagnostic.
