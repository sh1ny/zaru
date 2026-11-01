# zaru Roadmap

Strategy: `openspec/strategy.md` · Architecture: `openspec/architecture.md`

<!-- Status is derived: a change is done when archived; a milestone is done when its changes are done and its exit criteria pass. Do not add status checkboxes for changes. -->

## Now: M2 - Library completeness

**Outcome:** `Zaru.compile` runs the whole jq 1.8.2 language except modules,
`$ENV`/`env` and CLI-only behavior. That covers every builtin, path
expressions, assignment and update operators, regular expressions, `@format`
strings, date and time builtins, `$__loc__`, and the input, debug and halt
builtins (through ADR 0004 capabilities). `try` catches `break` as jq does.
A Dart program, including a browser build, can run real-world jq filters
in-process.

**Exit criteria:**
- `mise run conformance` passes every pinned case except those that need
  modules, `$ENV`/`env` or CLI-only behavior. Each remaining case is listed in
  `docs/compat.md` with that reason, and none is skipped. (agent)
- The upstream suites M2's builtins need (`onig.test`, `manonig.test`,
  `base64.test`, `uri.test`, `optional.test`) are vendored byte-for-byte
  with provenance and a frozen census. Each of their cases passes or is
  listed with a specific reason. (agent)
- `mise run conformance-gate` passes with an M2 acceptance classification, and
  `test/conformance/floor.json` holds every measured pass. (agent)
- `docs/compat.md` no longer lists the `break` divergence, and the regex-engine
  ADR is accepted. (agent)
- `checks`, `core-dart2js`, `core-dart2wasm`, `conformance-gate` and the three
  `Compile CLI` contexts are green on the last M2 PR. (agent)
- `docs/api.md`, the README and `example/zaru_example.dart` describe the M2
  surface, and the user has run some of their own jq filters through the
  library with the expected results. (user)

**Changes** (in order; each about one PR):
1. `catchable-break` - Let `try` and `?` catch `break` exactly as jq 1.8.2
   does, without catching `halt`. This modifies the filter-execution
   requirement and removes the divergence from `docs/compat.md`.
2. `core-builtins` - Add the non-path, non-regex, non-date builtins:
   - length, keys/keys_unsorted, has and type tests;
   - map, add, any/all, flatten, to_entries/from_entries/with_entries,
     sort/group/unique/min/max;
   - string, number and math builtins;
   - tojson/fromjson and limit-style helpers;
   - the capability predicates (reconciled per the strategy).

   It also extends the frozen classification and `conformance-gate` with an
   M2 acceptance class, which later M2 changes grow.
3. `path-expressions` - Add the path-tracking evaluation mode (ADR 0002):
   `path(f)`, `paths`, `getpath`/`setpath`/`delpaths`, `del`, `pick`,
   `tostream`/`fromstream`, and path errors. Needs `core-builtins`,
   because jq's `paths` and `del` use `length` and friends.
4. `assignment-operators` - Add `=`, `|=`, the arithmetic update operators and
   `//=` with jq's update semantics over the path mode. Needs
   `path-expressions`.
5. `regex-builtins` - Record the regex-engine ADR (Oniguruma-compatible
   semantics on every target, zero dependencies). Implement test, match,
   capture, scan, splits, sub and gsub. Vendor `onig.test` and
   `manonig.test`.
6. `formats-time-and-host-builtins` - Add the `@format` strings, the date and
   time builtins, `$__loc__`, and input/inputs, debug, stderr,
   input_filename, input_line_number and halt/halt_error through the ADR 0004
   capabilities. Vendor `base64.test`, `uri.test` and `optional.test`, which
   tests the date builtins.

## Next: M3 - jq-compatible CLI

A native `zaru` executable for Windows, macOS and Linux that behaves like
`jq` 1.8.2. It covers the documented options, JSON input streams (including
`--slurp`, `--null-input`, `--raw-input` and `--seq`), `--arg`, `--argjson`,
`--slurpfile`, `--rawfile` and `--args`, the output formatting flags, and jq's
exit codes and stdout/stderr split. `$ENV`/`env` work from the process
environment. The main risk it retires is host integration: streaming large
inputs without slurping, literal-preserving `--argjson`/`--slurpfile` through
the private decoder path (ADR 0003), and byte-exact output across platforms.
Its oracle is recorded jq output, including `tests/shtest`.

## Later

- M4 - Modules and 1.0: `import`/`include` through the caller-supplied resolver
  (ADR 0005), vendoring upstream `tests/modules`, the documented 1.0
  divergence-gate mechanism, a semver-stable API review, and the zaru 1.0.0
  release on pub.dev.

## Done

- M0 - Bootstrap - 2026-10-31 - Tooling, CI and an honest 0 / 781 baseline. A
  native jq reference census was needed before any engine work could be judged.
- M1 - Core language - 2026-11-01 - The lazy closure-tree engine and exact
  numbers pass all 352 core cases (358 / 781 overall). Resource bounds on
  untrusted filter text and the D3 `break` decision were found during review;
  the latter is reversed in M2.
