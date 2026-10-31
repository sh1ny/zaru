# Changelog

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
