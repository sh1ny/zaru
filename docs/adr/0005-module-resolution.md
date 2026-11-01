# ADR 0005: Caller-supplied module resolution

Status: accepted (2026-11-01)
Date: 2026-11-01
Supersedes: none

## Context

jq 1.8.2 links modules at compile time:

- `import "path" as name;` and `include "path";` load jq source.
  `import "path" as $name;` loads JSON data.
- A directive may carry metadata; jq uses only its `search` key.
- Names are resolved only after linking, which is why M1 reports any program
  with a directive as unsupported as a whole.

The search rules (`src/linker.c`, `src/main.c`, the manual's Modules section):

- Paths given with `-L` replace the default search list. The default list is
  `~/.jq`, `$ORIGIN/../lib/jq`, `$ORIGIN/../lib`.
- In each search directory the candidates are, in order:
  1. `<rel>.jq` (`<rel>.json` for data)
  2. `<rel>/jq/main.jq`
  3. `<rel>/<basename>.jq`
- A directive without `search` metadata searches `.` followed by the global
  list. A directive with `search` metadata searches only that list (a string
  is a one-element list), and the global list is not appended. `modulemeta`
  searches only the global list, without `.` and without rebasing. These are
  the pinned code's rules. The manual says metadata paths are prefixed to the
  global list; `docs/compat.md` records that discrepancy when M4 lands.
- Each entry is expanded:
  - `~/` becomes the home directory. With no home directory the entry is
    skipped. jq's `Could not expand ...` message appears only as the suffix
    of `module not found: <path> (...)`, and only when no other entry finds
    the module.
  - `$ORIGIN/` becomes the jq origin.
  - Exactly `.` becomes the working directory.
  - Any other relative entry (from `search` metadata, including `./x`, or from
    a global list a library caller passes) is resolved against the importing
    module's directory, or the program origin for the main program. `-L`
    entries are not rebased: jq's `main.c` resolves each `-L` argument against
    the working directory with `realpath` when it parses the option, and an
    entry that doesn't exist stays as given.
  - A null entry ends the search, and non-string or empty entries are skipped.
- A `~/.jq` *file* is imported automatically as the optional library `""`.
- Module paths are validated: no `\`, no `..` component, no equal consecutive
  components and no NUL byte.
- A code module is loaded once per resolved path, and importing one that is
  still loading reports `circular import`. Data modules are loaded per import.
- At run time, `modulemeta` loads the module named by its input, and
  `get_search_list`, `get_jq_origin` and `get_prog_origin` report the search
  state.

A browser build has no filesystem, and ADR 0004 keeps `lib/` pure, so module
bytes have to come from the caller.

## Decision

- The library defines a synchronous `ZaruModuleResolver` contract. jq's
  path-resolution rules above are implemented once in pure Dart and ask the
  resolver only for the bytes at a candidate path. The resolver answers with
  the content (jq source or JSON text) or "not found". The home directory,
  working directory, jq origin and program origin are explicit inputs to
  resolution, never read from the host.
- Every candidate path is normalised lexically before the resolver is asked
  for it: `.` and empty components are removed and `..` is collapsed. The
  normalised path is the key for load-once and cycle detection, and the path
  shown in diagnostics. jq also resolves symlinks through `realpath`. A
  content-only resolver can't, so a module reached through two different
  symlinked paths loads twice, unlike in jq. M4 records this as an intentional
  divergence in `docs/compat.md`, unless its design lets the resolver return
  a canonical path.
- The library applies the `~/.jq` auto-import only when the caller supplies a
  home directory, using the same candidate rules as any other import. The CLI
  supplies the home directory as jq does (`HOME`, and on Windows the fallbacks
  `USERPROFILE` and then `HOMEDRIVE`+`HOMEPATH`), and skips the auto-import when
  none is set.
- `Zaru.compile` takes an optional resolver, search list and origins. When the
  caller passes no search list, the library uses an empty global list, as
  libjq does. Without a resolver, a program that imports or includes a module
  fails with jq's own module-not-found compile error, and is no longer
  reported as unsupported. A lone `module {...};` directive is accepted, as in
  jq.
- Linking loads each resolved code module once, and reports an import cycle
  with jq's `circular import` error before any recursion could exhaust the host
  stack. Linked modules compile into the same immutable program as the main
  filter, and errors render jq's diagnostics for the module source.
- The compiled `ZaruFilter` keeps the resolver, the effective search list and
  the origins. `modulemeta`, `get_search_list`, `get_jq_origin` and
  `get_prog_origin` use them during iteration.
- An exception thrown by the resolver propagates unchanged, from `compile` or
  from the iterator. It is never treated as "not found" and never turned into a
  jq result.
- The package ships an in-memory resolver in `lib/`. Callers with asynchronous
  sources (HTTP, Flutter assets) load the modules first and pass an in-memory
  resolver, so compilation stays synchronous.
- The CLI supplies a filesystem resolver in `bin/`. It resolves each `-L`
  entry against the working directory, as jq's `main.c` does, and passes
  those entries, or jq's default search list, as the global list.

## Rejected alternative

An asynchronous `Zaru.compileAsync` with a `Future`-returning resolver. It
would give every caller two compile entry points and make the compiler
asynchronous throughout, for a need that preloading already covers. A
filesystem-only resolver in `lib/` was also rejected, because it breaks ADR 0004
and the browser targets.

## Reversal cost

Medium. The resolver contract and the new `compile` parameters are public API
from M4 and semver bound at 1.0. An async variant can still be added later
without breaking the synchronous one.

## Consequences

The library, the browser builds and the CLI all link modules with one shared
path-resolution implementation, and only the byte source differs.

Callers must know up front every module their directives import. `modulemeta`
on a name the resolver doesn't have fails as it does in jq.

Module cases need upstream `tests/modules` vendored byte-for-byte under
`test/conformance`, with provenance entries. The in-memory fixture resolver
reproduces the `tests/modules/...` display paths recorded by the census, so the
conformance harness exercises the library path. Upstream `tests/shtest` is the
oracle for CLI-level module behavior, such as `-L` and cycles.
