# ADR 0004: Pure library core, host I/O at the edges

Status: accepted (2026-11-01)
Date: 2026-11-01
Supersedes: none

## Context

zaru has to run unchanged on the Dart VM, Flutter, dart2js and dart2wasm. Several
jq features touch the host: the CLI reads files and stdin, writes stdout and
stderr, and sets exit codes. `$ENV`/`env` read the process environment.
`input`/`inputs` pull further JSON values. `debug`, `stderr` and
`input_filename` report to the host. `halt`/`halt_error` end the process, date
builtins need the local time zone, and modules come from a search path. If any
of these reached `dart:io` from `lib/`, the browser targets would break, and so
would the zero-runtime-dependency promise.

## Decision

- `lib/` stays pure Dart: no `dart:io`, `dart:ffi`, `dart:html`/`package:web`,
  subprocesses or conditional platform imports, and no runtime package
  dependencies. CI runs the unit suite in Chrome on dart2js and dart2wasm.
- Every host-dependent jq feature reaches the library through an explicit,
  synchronous capability that the caller passes at compile or run time:
  - environment values for `$ENV`/`env`;
  - an input source for `input`/`inputs`;
  - message sinks for `debug` and `stderr`;
  - the current input's filename and line number (`input_filename`,
    `input_line_number`);
  - the search list, jq origin and program origin (`get_search_list`,
    `get_jq_origin`, `get_prog_origin`);
  - a clock and time zone for the date builtins. By default these come from
    `dart:core`'s `DateTime`, which is browser-safe, so a caller supplies them
    only to override them;
  - a module resolver (ADR 0005).

  A missing capability falls back exactly as jq 1.8.2 does with no host
  callback, and `docs/api.md` names each fallback. For example, `input` with no
  source raises jq's `"break"` error, so `inputs` yields nothing. Where jq has
  no defined fallback, a missing capability raises an ordinary jq runtime error
  (`ZaruRuntimeError`, catchable by `try`). It is never a silent host fallback.
  The conformance harness supplies the environment the reference census
  recorded, such as `$ENV.PAGER`.
- `halt` and `halt_error` stop the iterator by throwing a dedicated public
  typed signal, distinct from `ZaruRuntimeError`. The signal carries the exit
  status and the halt value. As in jq, `try`, `?` and `catch` never intercept
  it, including after `break` becomes catchable, and the iterator is terminal
  afterwards. Nothing in `lib/` terminates the host process.
- `bin/zaru.dart` is the only place that binds these capabilities to
  `dart:io`: process environment, files, stdin, stdout/stderr, exit codes and
  the filesystem module resolver. Development tooling (`tool/`) and VM-only
  tests may use `dart:io` as well.

## Rejected alternative

Conditional imports (`dart.library.io`) that read the process environment or
files directly inside `lib/` when available. That gives the library different
behavior per platform and hidden ambient inputs. It also makes VM and browser
tests disagree, and it leaks `dart:io` into the package's import graph.

## Reversal cost

Medium. The capability parameters become public API at M2 or M3 and are semver
bound at 1.0. Moving to ambient host access later would change results for
existing callers, while adding a capability stays additive.

## Consequences

Library callers decide what a filter can see, so the library denies host
access by default. It does not bound a filter's CPU time or memory: callers
running untrusted filters must isolate them in an isolate or worker and own
cancellation. The CLI carries the host wiring and has its
own VM-only tests. Some jq behavior, such as reading the real environment
through `$ENV`, only appears when the caller or the CLI supplies it, and
`docs/api.md` must say so per feature.
