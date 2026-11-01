jq for Dart.
0 / 781 jq tests passing (the conformance harness is not connected to the
engine yet, so the baseline is unchanged; see [compatibility](docs/compat.md)).

zaru is bootstrapping a pure-Dart jq-compatible library and command-line tool.
The core is designed for the Dart VM and browsers, with no `dart:io` imports and
zero runtime package dependencies. **The library now evaluates a small core of
jq (listed below); it is not a complete jq.** Most builtins, paths and
assignment are not implemented, and they fail at compile time instead of
pretending to work.

## What is available

- A package and CLI scaffold; the CLI supports `--version` only.
- `Zaru.compile(source, {variables})` returns a reusable `ZaruFilter`;
  `run(input, {args})` takes native Dart JSON-shaped values and `runJson(text,
  {args})` takes one JSON text. Results are lazy `Iterable`s with independent
  iterators. Supported jq: identity, `.name`, `.[expr]`, slices, `.[]` and the
  `?` forms, literals (numbers keep their exact text), array and object
  construction, `|` and `,`, arithmetic, comparison, `and`/`or`/`not`, `//`,
  `if`/`elif`/`else`, `try`/`catch`, string interpolation, `expr as pattern |
  ...` with destructuring and `?//`, `def` with filter and `$value` parameters,
  `reduce`, `foreach`, `label`/`break`, external `$variables`, and the builtins
  `empty`, `error`, `error(f)`, `not` and `select(f)`.
- Not yet available: `..`, every other builtin (`map`, `length`, `range`,
  ...), assignment and update operators, `@format`, `$__loc__`, `$ENV` and
  modules. Compiling any of them throws `ZaruCompileError` with
  `isUnsupported` set, never a result. See `example/zaru_example.dart`
  (`mise run example`).
- A pinned jq 1.8.2 corpus with 781 cases, its provenance and license, and a
  conformance harness that exposes the unimplemented baseline honestly.
- Normal infrastructure tests, VM/browser and native-compile CI tasks, and
  architecture decisions for the future implementation.

There is no benchmark implementation or MCP product server. The conformance run
still scores every case as unimplemented because it does not call the engine.
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
mise run example
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
- [API: implemented surface and planned direction](docs/api.md)
- [Parser strategy](docs/adr/0001-parser-strategy.md)
- [Evaluation and numeric model](docs/adr/0002-evaluation-model.md)
- [Contributor and agent rules](AGENTS.md)
- [Changes](CHANGELOG.md)

The API compiles a filter once and lazily yields plain Dart JSON-shaped values.
Numeric literal fidelity across VM and browser targets requires explicit care;
silent loss of large integer precision is not an acceptable shortcut.

zaru is licensed under [MIT](LICENSE), copyright Nikolay (sh1ny). Vendored jq
fixtures retain their own [upstream notice](test/conformance/COPYING).
