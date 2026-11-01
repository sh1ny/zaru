# Changelog

## Unreleased

- Add the public `ZaruNumber` (exact finite jq number with canonical text) and
  `Zaru.toJson` (jq-compatible compact/indented printing, sorted keys, depth
  truncation marker). No filter, `run`, `runJson`, or `fromJson` API exists.
- Add private iterative jq-compatible number, JSON decoding, and Unicode
  normalization layers, and a browser-safe exact fixture oracle for tests that
  is separate from runtime equality. No jq filter is evaluated and the
  conformance baseline is unchanged.

- Add an internal jq lexer, parser and diagnostic renderer (`lib/src/syntax`):
  UTF-8 byte spans, a syntax tree, Bison-style error recovery and jq's
  excerpt/caret rendering, constant object-key and module-metadata checks, and
  explicit `unsupported` records for deferred syntax. Checked against captured
  jq 1.8.2 output. Nothing is exported or evaluated; the baseline is unchanged.

## 0.0.0 — M0 bootstrap

- Establish a pure-Dart package with no runtime package dependencies and a
  version-only CLI. jq parsing and evaluation are not implemented.
- Pin the jq 1.8.2 upstream test corpus: 781 cases, including 19 compile-error
  cases, with original fixtures, provenance, and upstream license notices.
- Add conformance infrastructure and an honest 0 / 781 baseline. Normal tests
  cover infrastructure; the separate conformance task intentionally remains red.
- Define mise tasks and CI for analysis, formatting, tests, conformance,
  Linux/macOS/Windows CLI compilation, and browser-safe Chrome tests.
- Record parser and lazy-evaluation architecture decisions, numeric fidelity
  constraints, compatibility policy, and the future API direction.
- Configure official Dart SDK MCP contributor tooling and install official Dart
  skills. No zaru MCP product server or benchmark is implemented.
- Isolate the SDK MCP installation cache per project to avoid cross-project
  executable-lock failures on Windows.
