# Compatibility baseline

M0 implements no jq filter behavior. The baseline is **0 / 781 jq tests passing**;
this is an honest unimplemented baseline, not an assertion that the upstream
suite has been satisfied. An unavailable evaluator is a failure, never a skip or
a fabricated successful result.

## Pinned upstream corpus

The checked-in fixtures come from [jq 1.8.2](https://github.com/jqlang/jq/tree/jq-1.8.2),
commit `34f7186b86743a083a589741b6cea95293524108`:

| Fixture | Cases |
| --- | ---: |
| `test/conformance/jq.test` | 550 |
| `test/conformance/man.test` | 231 |
| Total | 781 |

The total includes 19 compile-error cases. `man.test` is a tracked upstream file;
its historical generation from jq documentation does not mean these fixtures
were regenerated locally. The upstream `COPYING`, `VERSION`, and
`PROVENANCE.json` beside the fixtures record license and provenance information.
The zaru MIT license does not replace upstream notices.

The harness reads the upstream block format and counts cases independently of
whether zaru implements them. Infrastructure tests can pass while all semantic
cases fail. The `conformance` task is deliberately separate from the normal test
task and is expected to exit unsuccessfully at M0.

```sh
mise run test
mise run conformance
```

## Implementation gaps, not intentional divergences

Parsing, compilation, evaluation, built-ins, variable binding, streaming output,
path selection, updates, error semantics, and jq-compatible number handling are
not implemented. None of these gaps is an intentional change to jq semantics.
There is no supported filter subset, including the identity filter.

The number, JSON-text decoding, and printing layers are an exception to the
"not implemented" list only as library building blocks: `ZaruNumber`,
`Zaru.toJson`, and an internal jq-compatible decoder exist and are covered by
direct unit tests, not by conformance cases. They do not make any jq filter
work and do not change the `0 / 781` baseline. Known limitation: a numeric
literal with more than 147483648 coefficient digits is not rounded to jq's
decimal context precision. The tests' fixture oracle compares finite numbers as
exact decimals; that is a test-infrastructure judgment, distinct from jq's
runtime equality.

A compile-error fixture does not pass merely because M0 rejects all execution:
it must eventually produce the expected compiler behavior. Unsupported behavior
stays in the denominator. Skips require a specific documented reason in
`test/conformance/skip.txt`; missing implementation is not a reason to skip.

## Deliberate scope boundaries

The product is intended to be a pure-Dart library and CLI with zero runtime
package dependencies. Its library must not import `dart:io`; CLI and test tooling
may use I/O. The planned API uses ordinary Dart JSON-shaped values, with explicit
handling of numeric precision boundaries rather than silent browser/VM rounding.
See [the API direction](api.md) and [ADR 0002](adr/0002-evaluation-model.md).

M0's CLI supports `--version` only. There is no evaluator, benchmark, or MCP
product server. These are scope statements, not claims of jq compatibility. No
intentional jq-language semantic divergence has been established in M0; any future
one must be documented explicitly and kept distinguishable from implementation
gaps. The selected corpus measures that pinned baseline, not every possible jq
program or all releases of jq.
