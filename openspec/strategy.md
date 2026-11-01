# zaru Strategy

## Purpose

zaru gives Dart programs the real jq 1.8.2 filter language, in-process and
without a native jq. Dart and Flutter code, including browser builds, can run
jq filters over ordinary JSON-shaped values with jq's exact results, errors and
number handling, and a native `zaru` command offers the same language from a
shell.

## Users

- **Dart and Flutter developers (primary).** They embed jq filters, often user-
  or configuration-supplied, in apps that run on the VM, on Flutter, or on the
  web (dart2js and dart2wasm). They need jq-identical output, typed errors,
  lazy multi-result streams and no platform dependencies.
- **Command-line users (secondary).** They want a jq-compatible binary built
  from the Dart toolchain for Windows, macOS and Linux.

## Boundaries

- The pinned jq 1.8.2 is the specification: the upstream corpus and the native
  reference census decide behavior. Any difference is either an implementation
  gap or a documented intentional divergence with a specific reason.
- The library is pure Dart with zero runtime package dependencies. `lib/` never
  imports `dart:io`, native bindings, subprocesses or platform-specific runtime
  libraries, and host I/O lives in `bin/` and tooling (ADR 0004).
- Public values are ordinary Dart JSON-shaped values, with the one narrow
  `ZaruNumber` exception (ADR 0003). Numeric literal fidelity is never traded
  for convenience, and large integers are never silently rounded.
- Honest accounting: every one of the 781 pinned cases is counted, with no skips
  that inflate the pass rate and no fake evaluator paths. The README numerator
  only changes from a fresh `mise run conformance`.
- Not in scope: an MCP product server, benchmark scaffolding, a jq C binding,
  and following jq versions newer than 1.8.2 before 1.0.

## Success measures

1. `mise run conformance` passes every vendored case: the 781 pinned cases plus
   every upstream suite vendored later. Any case that doesn't pass must be an
   intentional divergence. Each divergence is listed in `docs/compat.md`
   with its reason and accounted for by a documented 1.0 gate mechanism, which
   M4 defines. The full run keeps reporting them; they are never skipped.
2. The checks, core-dart2js, core-dart2wasm, conformance-gate and three Compile
   CLI CI contexts are green on main, and the passed-ID floor never loses an ID.
3. The CLI's documented jq 1.8.2 options, exit codes and stdout/stderr split
   are verified by VM tests against recorded jq reference output.
4. zaru 1.0.0 is published on pub.dev with the library and the `zaru`
   executable, and its public API is documented in `docs/api.md`.

## Tracks

- **Language and builtins:** the jq grammar, evaluator semantics and builtin
  catalogue.
- **Conformance accounting:** the frozen reference census, the classification,
  the floor and the gates.
- **Public API and fidelity:** the Dart API, numbers, Unicode, errors and
  resource bounds.
- **CLI:** the jq-compatible command line, input streams and host integration.
- **Packaging and release:** pub.dev metadata, versioning and release notes.

## Assumptions

- The original brief asks for jq's capability predicates (`have_decnum`,
  `have_literal_numbers`) to report false. The change that implements them must
  reconcile those values with zaru's preserved-literal semantics explicitly,
  not by choosing whichever fixture branch passes.
- Performance is not a goal until a measured problem exists, and no benchmark
  harness is added before then. The `bench` mise task stays a placeholder that
  exits with an error.
- The pinned corpus is `jq.test` and `man.test` only. The upstream suites
  `onig.test`, `manonig.test`, `base64.test`, `uri.test` and `optional.test`
  are not vendored yet. M2 vendors the ones its builtins need, byte-for-byte
  with provenance and a census, and adds them to the conformance denominator
  and the 1.0 gate.
  M2 also records the regex engine choice as an ADR: Oniguruma-compatible
  semantics on every target, with no runtime dependency, versus Dart `RegExp`,
  which differs between the VM and the web targets.
- The CLI implements the jq 1.8.2 options that the man page documents. It
  matches jq's exit codes and stdout/stderr split, and builds as a native
  executable on all three desktop platforms.
- The public API is semver-stable from 1.0.0. Before 1.0 it may change, but
  only together with `docs/api.md` and the CHANGELOG.
