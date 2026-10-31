# Contributor and agent instructions

## M0 boundary

zaru is a pure-Dart jq compatibility project. M0 provides tooling, a version-only
CLI, and an honest failing conformance baseline. Do not claim that any jq filter
works, implement a fake evaluator, turn missing features into successful tests,
or add benchmark scaffolding or an MCP product server.

Keep runtime dependencies at zero. Only `test` and `lints` are development
package dependencies. `lib/` must remain free of `dart:io`, native bindings,
subprocess dependencies, and platform-specific runtime imports. I/O belongs in
`bin/`, test infrastructure, or development tooling, never the reusable core.
Use ordinary Dart JSON-shaped values at the public boundary; preserve numeric
literal fidelity and never silently round large integers for browser support.

## Repository map

- `lib/zaru.dart`: public library entrypoint; no filter APIs are implemented M0.
- `bin/zaru.dart`: CLI entrypoint; `--version` only at M0.
- `test/unit/`: browser-safe core and infrastructure tests.
- `test/conformance/`: corpus parser, runner, and explicit skip policy.
- `test/conformance/{jq.test,man.test,VERSION,COPYING,PROVENANCE.json}`: pinned corpus and attribution.
- `build/conformance-report.json`: generated conformance report, not source.
- `docs/api.md`: planned API; not a claim of existing declarations.
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
| `mise run test` | Run normal tests, excluding tagged conformance cases. |
| `mise run conformance` | Run all pinned jq cases; intentionally fails at M0. |
| `mise run web-test` | Run browser-safe tests in Chrome. |
| `mise run compile` | Compile the CLI on the current host. |
| `mise run cli -- --version` | Show the M0 package version. |

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
reason for every skip. Keep README's `0 / 781` baseline and generated reports
honest as implementation progresses.

Future parser/evaluator changes must follow the ADRs, update affected callers,
tests, and docs together, and preserve lazy result ordering, backtracking, path
semantics, and typed error contracts. The API sketch in `docs/api.md` remains
unavailable until genuinely implemented end to end.
