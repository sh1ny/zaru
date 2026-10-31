jq for Dart.
0 / 781 jq tests passing (M0 baseline; no evaluator implemented).

zaru is bootstrapping a pure-Dart jq-compatible library and command-line tool.
The core is designed for the Dart VM and browsers, with no `dart:io` imports and
zero runtime package dependencies. **M0 is project infrastructure, not a working
jq engine.** No filter, including `.`, can be evaluated yet.

## What is available

- A package and CLI scaffold; the CLI supports `--version` only.
- A pinned jq 1.8.2 corpus with 781 cases, its provenance and license, and a
  conformance harness that exposes the unimplemented baseline honestly.
- Normal infrastructure tests, VM/browser and native-compile CI tasks, and
  architecture decisions for the future implementation.

There is no parser, evaluator, benchmark implementation, or MCP product server.
The Dart SDK MCP configuration is contributor tooling only.

## Development

Use [mise](https://mise.jdx.dev/) with the Dart toolchain declared in `mise.toml`.
Install that toolchain before running the repository tasks. Dependencies are
installed through the task wrapper, not an ad hoc package-manager command:

```sh
mise run pub
mise run cli -- --version
mise run analyze
mise run format --check
mise run test
mise run web-test
mise run compile
```

`mise run test` covers infrastructure and excludes the tagged semantic
conformance run. `mise run web-test` needs Chrome. `mise run compile` smoke-checks
the version-only CLI on the host platform; it does not add query support.

```sh
mise run conformance
```

The conformance command is **intentionally red at M0**: all 781 upstream cases
remain unimplemented. CI runs it as a real failing gate, without converting
missing functionality into successful tests or hiding it with `continue-on-error`.
A green normal test suite is not a jq-compatibility claim.

## Design and contribution

- [Compatibility baseline and corpus provenance](docs/compat.md)
- [Future API direction — unavailable in M0](docs/api.md)
- [Parser strategy](docs/adr/0001-parser-strategy.md)
- [Evaluation and numeric model](docs/adr/0002-evaluation-model.md)
- [Contributor and agent rules](AGENTS.md)
- [Changes](CHANGELOG.md)

The planned API compiles a filter once and lazily yields plain Dart JSON-shaped
values. Numeric literal fidelity across VM and browser targets requires explicit
care; silent loss of large integer precision is not an acceptable shortcut.

zaru is licensed under [MIT](LICENSE), copyright Nikolay (sh1ny). Vendored jq
fixtures retain their own [upstream notice](test/conformance/COPYING).
