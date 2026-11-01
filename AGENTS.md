# Contributor and agent instructions

## Project boundary

zaru is a pure-Dart jq compatibility project. M0 provided tooling, a version-only
CLI, and an honest failing conformance baseline. M1 (`implement-core-language`,
in progress) adds a real compiler and lazy evaluator for the jq core subset;
the conformance runner executes it and the README numerator is the measured
`358 / 781` of the latest full run (all 352 M1 acceptance cases pass).
Claim only behavior that unit tests exercise or that the conformance runner
measures, and change the numerator only from a fresh `mise run conformance`. Never implement a fake evaluator, turn missing features
into successful tests, or add benchmark scaffolding or an MCP product server.

Keep runtime dependencies at zero. Only `test` and `lints` are development
package dependencies. `lib/` must remain free of `dart:io`, native bindings,
subprocess dependencies, and platform-specific runtime imports. I/O belongs in
`bin/`, test infrastructure, or development tooling, never the reusable core.
Use ordinary Dart JSON-shaped values at the public boundary; preserve numeric
literal fidelity and never silently round large integers for browser support.

## Repository map

- `lib/zaru.dart`: public library entrypoint: `Zaru.compile`, `ZaruFilter`, the error types and `ZaruNumber`.
- `lib/src/engine/`: immutable operation tree, execution machine, value semantics and compiler of the core subset.
- `example/zaru_example.dart`: runnable usage tour (`mise run example`).
- `bin/zaru.dart`: CLI entrypoint; `--version` only at M0.
- `test/unit/`: browser-safe core and infrastructure tests.
- `test/conformance/`: corpus parser, VM file wrappers (`conformance_io.dart`), the committed passed-ID floor (`floor.json`), reference integrity and gate-process tests, and explicit skip policy.
- `test/support/conformance_{baseline,run,accounting}.dart`: browser-safe baseline verification, per-case execution/comparison and report/gate decisions (no `dart:io`, no jq).
- `tool/conformance.dart`: the `conformance` and `conformance-gate` commands.
- `test/conformance/{jq.test,man.test,VERSION,COPYING,PROVENANCE.json}`: pinned corpus and attribution.
- `build/conformance-report.json`: generated conformance report, not source.
- `docs/api.md`: public API; it marks which declarations are implemented and which remain planned.
- `docs/compat.md`: compatibility baseline and intentional-divergence policy.
- `docs/adr/`: parser and evaluator architecture decisions.
- `mise.toml`: toolchain and task definitions; the command interface for work.
- `.github/workflows/ci.yml`: checks, cross-platform compile, and Chrome jobs.
- `.agents/skills/`: installed official Dart skills and workflow guidance.
- `.omp/mcp.json`: Dart SDK MCP tooling configuration.

## Task interface

Run repository commands through the existing mise tasks. Install dependencies
through `mise run pub`, not a separate package-manager invocation. Do not add
another task runner or advertise bare SDK commands in docs or CI.

| Command | Purpose |
| --- | --- |
| `mise run pub` | Install package dependencies. |
| `mise run analyze` | Run strict static analysis. |
| `mise run format` | Format Dart sources. |
| `mise run format --check` | Check formatting without changing sources. |
| `mise run test` | Run normal tests, excluding tagged conformance and native-reference tests. |
| `mise run conformance` | Verify the frozen baseline, execute all 781 pinned cases with zaru and write `build/conformance-report.json`; fails while any case fails. Never runs jq. |
| `mise run conformance-gate` | M1 acceptance: verify the frozen baseline, execute freshly, and pass only if every M1-classified case and every ID in `test/conformance/floor.json` passes. Never runs jq or reads an old report. |
| `mise run reference-classification` | Regenerate source-only grammar/builtin classifications; does not run jq. |
| `mise run reference-setup` | Verify the pinned jq 1.8.2 source and build jq, libjq, and the capture driver (WSL on Windows). |
| `mise run reference-census` | Explicitly regenerate the native jq reference census; never run by tests or CI. |
| `mise run reference-verify` | Verify frozen census/classification integrity and facts without running jq. |
| `mise run reference-freeze` | Record digests for a reviewed regenerated baseline, then verify it. |
| `mise run reference-test` | Run opt-in VM tests that generate a native jq reference census. |
| `mise run classification-test` | Run opt-in VM source-only grammar/builtin classification regressions. |
| `mise run web-test` | Run browser-safe tests in Chrome. |
| `mise run web-test-wasm` | Run browser-safe tests in Chrome using dart2wasm. |
| `mise run compile` | Compile the CLI on the current host. |
| `mise run example` | Run `example/zaru_example.dart`, the core-engine tour. |
| `mise run cli -- --version` | Show the M0 package version. |

`mise run web-test` explicitly selects `dart2js`; `mise run web-test-wasm`
selects `dart2wasm`. Both run the browser-safe `test/unit` suite in Chrome.
The locked package:test Chrome runner supports both compilers. Use a compatible
browser (currently Chrome 137+ for wasm); `dart = "latest"` is not an SDK pin.
The task-1.6 scaffold run used mise-resolved Dart 3.13.7 and Chromium
147.0.7727.117; both commands passed
27 tests, with the requested compiler selected in each run. This is observed
verification evidence, not a toolchain pin.

### Milestone CI contexts

The implement-core-language milestone defines exact check-run contexts:
`checks`, `core-dart2js`, `core-dart2wasm`, `conformance-gate`, and
`full-conformance`. The browser contexts use the mise tasks above; the gate
(`mise run conformance-gate`) runs core acceptance without jq;
`full-conformance` (`mise run conformance`) covers both corpora, is not masked
by `continue-on-error`, and stays red while any case fails. Acceptance requires
every context except `full-conformance`. These names and roles are milestone
requirements, not a claim of GitHub enforcement. Preserve the existing CLI
contexts (`Compile CLI (ubuntu-latest)`, `Compile CLI (macos-latest)`, and
`Compile CLI (windows-latest)`). The `checks` job (analyze, format check, normal
tests) no longer runs conformance: the group-7 split moved it into the
`conformance-gate` and `full-conformance` jobs. The actual GitHub check-run
names are verified after a push, not from the workflow text.

Live policy was checked read-only before adding these contexts: the main
branch-protection endpoint returned 404 and the active branch-rules list was
empty. No protection or ruleset was changed or claimed.

Follow the assignment's verification scope. A delegated worker must not run
builds, tests, analysis, or formatters unless explicitly assigned to do so; the
integrating agent runs verification after all edits land. Never commit unless
asked. A normal green test run does not imply conformance success.

## Skills and SDK MCP

Before relevant Dart work, read the matching official skill under
`.agents/skills/`, including its `SKILL.md`. Use the documentation, testing,
analysis, and CLI skills when their subjects match the task. Keep existing
workflow setup intact; M0 does not require new OpenSpec artifacts.

`.omp/mcp.json` launches the SDK's stdio MCP server with command `dart` and
arguments `["mcp-server", "--enable=run_tests,dart_format,dart_fix"]`. The
`mcp-server` subcommand is the official SDK server; the explicit enable flag opts
in to tools disabled by default in the current server version. This protocol
process configuration is the deliberate exception to the task-command rule.
Launch the coding agent from the mise-managed project environment so the process
resolves the project's Dart toolchain. Discover the actual advertised MCP tools
rather than assuming that every SDK version supports the same tools. The SDK
server assists contributors; it is not a zaru runtime dependency or a zaru MCP
product server.
The server uses `DART_DATA_HOME=.dart_tool/dart-data` for a project-local SDK
installation cache. This avoids Windows executable-lock conflicts with SDK MCP
servers already running for other projects, without changing `LOCALAPPDATA` or
browser discovery. The cache is ignored, not committed.

## Compatibility discipline

Retain the pinned upstream fixtures byte-for-byte, with their copyright notices
and provenance. Count every case, including expected compile errors. Do not
skip unsupported syntax or behavior to inflate the pass rate. Document any
intentional divergence separately from an implementation gap, with a specific
reason for every skip. Keep README's measured numerator (`358 / 781` after M1) and generated reports
honest as implementation progresses.

Future parser/evaluator changes must follow the ADRs, update affected callers,
tests, and docs together, and preserve lazy result ordering, backtracking, path
semantics, and typed error contracts. The API sketch in `docs/api.md` remains
unavailable until genuinely implemented end to end.
