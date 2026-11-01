# Review

## Metadata

- **Round:** 3
- **Prior round:** Round 2 returned APPROVE_WITH_CHANGES with 3 required changes: search-chain construction and entry expansion in ADR 0005 with the working directory as an explicit input (M1), lexical normalisation as the load-once/cycle key plus the matching bounds row (M2), and strategy measure 1 / the vendored-suites assumption reaching the 1.0 gate (M3).
- **Reviewer:** fresh-context subagent (Claude Agent SDK, specwright-reviewer role), baseline mode
- **Reviewed:** openspec/strategy.md, openspec/architecture.md (working tree), docs/adr/0004-pure-core-host-edges.md, docs/adr/0005-module-resolution.md, openspec/architecture-review.md (rounds 1-2); context: AGENTS.md, mise.toml, lib/ file tree, lib/src/engine/compiler.dart, openspec/changes/archive/2026-11-01-implement-core-language/design.md (D3), tool/reference_census.dart, test/conformance/jq.test and man.test, openspec/schemas/specwright/schema.yaml and templates/review.md, pinned jq 1.8.2 source (.dart_tool/reference/jq-1.8.2: src/linker.c, src/main.c, src/util.c, src/builtin.c, src/builtin.jq, src/execute.c, tests/jqtest, tests/shtest, tests/modules/). Applicable project skills: none named.

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

Round-2 required changes, checked:

1. **Applied.** ADR 0005:25-39 now states the chain construction exactly as linker.c does it: no metadata means `.` followed by the global list (`default_search`, linker.c:240-249). Metadata means only that list, with a string as a one-element list. `modulemeta` uses only the global list and no rebasing (`load_module_meta`, linker.c:409-411). The manual discrepancy goes to `docs/compat.md`. Expansion of `$ORIGIN/` and exact `.` matches linker.c:71-75, and null/non-string/empty handling matches linker.c:177-185. ADR 0005:57-59 lists the working directory as an explicit input. Two of the expansion bullets copied from the round-2 text were still wrong against the pinned code. That error was round 2's, not the author's, and M1 below covers it.
2. **Applied.** ADR 0005:60-64 makes the lexically normalised path the load-once/cycle key and the display path, and gives symlinks to the resolver. architecture.md:111 has the new bounds cell word for word. Normalisation also handles the fixture's `{search:"./../lib/jq"}` (tests/modules/c/c.jq:5-6). See S1 for whether the contract lets the resolver own symlinks.
3. **Applied.** strategy.md:39-43 covers every vendored case and treats non-passing cases as listed, reasoned divergences under an M4-defined 1.0 gate mechanism that are still reported and never skipped. strategy.md:71-75 adds vendored suites "to the conformance denominator and the 1.0 gate". All five named suites exist upstream (tests/{onig,manonig,base64,uri,optional}.test).

Round-2 suggestions taken, checked:

- **S1 (proposed markers):** taken. architecture.md:22, 27-30, 62, 63 and 93 and strategy.md:27 all say "proposed". The "Proposed ADRs" table (architecture.md:115-122) is separate from the in-force table. The acceptance edit still has to drop those markers and move both rows (Supersedes "—").
- **S2 (clock, catchable error, census environment):** taken. ADR 0004:32-34 makes `DateTime` the default and states the browser-safe reason. ADR 0004:39-41 makes a missing capability without a jq fallback a catchable `ZaruRuntimeError`. ADR 0004:42-43 has the harness supply the census environment (`LC_ALL=C`, `PAGER=less`, reference_census.dart:14). The named fallbacks match jq: `input` gives `"break"` (builtin.c:1459-1470, builtin.jq:189). `debug`/`stderr` pass through silently (builtin.c:1472-1488). `input_filename`/`input_line_number` give jq's "Unknown input filename/line number" errors (util.c:374-394).
- **S3 (auto-import):** taken. ADR 0005:65-68 uses the shared candidate rules, as linker.c:449-459 does (relpath `""`, `optional`, `search: home`), and skips the import silently with no home (linker.c:460-462). One detail was too broad (S3 below).
- **S4 (shtest):** taken in ADR 0005:113-114.

Verified, no finding: the user decisions are applied consistently. M2 is library completeness with `catchable-break` first (architecture.md:6-8 marks D3's break rule as non-binding, and D3 at design.md:42 is the rule being reversed). M3 is the CLI (architecture.md:24, 62, 94, 112). M4 is modules and pub.dev 1.0 (strategy measure 4, ADR 0005 Reversal cost). The resolver is injected and caller-supplied (ADR 0005 Decision). `try` catches `break` like jq, while `halt` stays uncatchable (ADR 0004:44-48). The component paths match the lib/ tree. M1's "directive programs are unsupported" claim matches compiler.dart:88-99 (import/include only). The CI context names match AGENTS.md. ADR 0004's halt contract matches f_halt/f_halt_error (builtin.c:1307-1320). The census runs with `env -i` and `-L` (reference_census.dart:267-281, tests/jqtest), so no `~/` entry reaches the global list in pinned cases.

## Changes applied (verified)

Re-checked docs/adr/0005-module-resolution.md (working tree; `git status` shows no other file changed) against the pinned jq 1.8.2 source. The line numbers below refer to the revised file:

1. **Required Change 1, applied.** ADR 0005:32-35 now says an entry whose `~/` cannot be expanded is skipped, and that the `Could not expand ...` message appears only as the suffix of `module not found` when no other entry finds the module. This matches linker.c:64-69 and 223-229.
2. **Required Change 2, applied.** ADR 0005:38-43 now rebases only `search` metadata entries (including `./x`) and relative entries a library caller passes in the global list. `-L` entries are not rebased, because `main.c` applies `realpath` to each `-L` argument against the working directory when it parses the option, and a missing entry stays as given. This matches main.c:411 and 417 and linker.c:76-80. Under these rules the shtest:384-398 check resolves.
3. **Required Change 3, applied.** ADR 0005:97-99 has the CLI resolve each `-L` entry against the working directory and pass those entries, or jq's default list, as the global list. This matches main.c:571-577.

The extra edits introduce no new problem:
- **S1** (ADR 0005:68-72) records the symlink load-twice behaviour as an M4 intentional divergence unless the M4 design lets the resolver return a canonical path. That is accurate for a content-only contract.
- **S2** (ADR 0005:78-80) gives an empty default global list, matching `jq_get_lib_dirs` (execute.c:1272-1275). `default_search` still prepends `.` (linker.c:240-249).
- **S3** (ADR 0005:74-77) uses `HOME`, then, on Windows only, `USERPROFILE` and then `HOMEDRIVE`+`HOMEPATH`, matching util.c:102-125.
- **S5** (ADR 0005:80-83) narrows the rule to "a program that imports or includes a module" and accepts a lone `module {...};` directive.

S2's note about `get_search_list` reporting the list as given (builtin.c:1322-1325) is still open: ADR 0005:88 says "effective search list". It stays a suggestion for the M4 design.

## Findings

### Critical (blocking)

None.

### Moderate

**M1. Two entry-expansion rules in ADR 0005 were wrong about the pinned code. Following them fails module lookups that jq 1.8.2 resolves, including one of upstream shtest's own regression checks.** (Fixed; see "Changes applied (verified)".)

ADR 0005's Context calls these "the pinned code's rules", and M4 implements them once in `lib/` as semver-bound behaviour.

- **Relative `-L` entries are not rebased per importer.** The ADR said "Any other relative entry (from metadata, `-L` or `./x` alike) is resolved against the importing module's directory". jq's `main.c` applies `jq_realpath` to every `-L` argument when it parses the option (main.c:411, 417), so `-L` entries reach the linker already absolute against the working directory. An entry whose realpath fails, such as a nonexistent path, stays as given. Only `search` metadata entries, and relative entries that a libjq caller puts in `JQ_LIBRARY_PATH`, are rebased by `build_lib_search_chain` (linker.c:76-80). Concrete break: shtest:384-398 runs `cd "$JQBASEDIR"; jq -L tests/modules -ne 'import "test_bind_order" as check; ...'`. Under the old rule, the main import finds `<base>/tests/modules/test_bind_order.jq`. That module's own imports (`test_bind_order0`..`2`, with no metadata) then search `.` = `<base>` and the rebased `<base>/tests/modules/tests/modules`, and both miss, so the result is `module not found`. jq passes.
- **An unexpandable `~/` entry is skipped, not raised.** The ADR said "With no home directory, jq raises its `Could not expand` error." In `build_lib_search_chain`, a failed `expand_path` records the message and drops the entry (linker.c:64-69). The message only appears as the suffix of `module not found: <rel> (Could not expand ...)` when no other entry finds the module (linker.c:223-229). Concrete break: jq's default global list starts with `~/.jq` (main.c:573-575). With the old rule, every import fails whenever no home is supplied, even when the module sits in `.` or `$ORIGIN/../lib`.

### Suggestions

- **S1. The contract gives the resolver no way to resolve symlinks.** The resolver only answers "content or not found", while the library keys load-once, cycle detection and display paths on its own lexical path, so a resolver cannot affect identity. Either let its answer carry an optional canonical path that becomes the key and display path, or document the divergence. Shape the answer as a result type, not a nullable string, so the field can be added later without a break. (Taken: the ADR now records it as an M4 divergence unless the M4 design lets the resolver return a canonical path.)
- **S2. Library defaults were unspecified.** libjq's default global list is empty (`jq_get_lib_dirs`, execute.c:1272-1275), and jq's `~/.jq`/`$ORIGIN` default is a `main.c` (CLI) choice. Absent inputs should make the matching entries skip, consistent with the M1 skip rule. `get_search_list` returns the stored global list unexpanded (builtin.c:1322-1325), so "effective search list" should mean "as given". (The empty default list is taken; the `get_search_list` wording is still open.)
- **S3. The home fallback differs by platform.** In `get_home`, jq falls back from `HOME` to `USERPROFILE`, then to `HOMEDRIVE`+`HOMEPATH`, and only on Windows (util.c:102-125). On POSIX there is no fallback. (Taken.)
- **S4. The conformance harness needs a pinned time zone.** The census runs under `env -i` and so in UTC. With `DateTime` as the default time zone (ADR 0004:32-34), any local-time case would follow the contributor's zone, so the harness should pin UTC alongside the other census environment. Only a few pinned cases depend on it today, but the M2 date-builtin design should state it.
- **S5. "Program with directives" was too broad.** A program with only a `module {...};` metadata directive and no import or include links fine in jq (jq.test:1934-1940 shows its validation errors). (Taken.)
- **S6 (carried from round 2, S5).** The mise.toml `bench` description, "Reserved until M3 is complete", still contradicts strategy.md:68-70. Align it when mise.toml is next touched.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. **ADR 0005 Context, `~/` bullet (M1).** Replace "`~/` becomes the home directory. With no home directory, jq raises its `Could not expand` error." with: "`~/` becomes the home directory. With no home directory the entry is skipped; jq's `Could not expand ...` message appears only as the suffix of `module not found: <path> (...)` when no other entry finds the module."
2. **ADR 0005 Context, relative-entry bullet (M1).** Replace "Any other relative entry (from metadata, `-L` or `./x` alike) is resolved against the importing module's directory, or the program origin for the main program." with: "Any other relative entry (from `search` metadata, including `./x`, or from a global list a library caller passes) is resolved against the importing module's directory, or the program origin for the main program. `-L` entries are not rebased: jq's `main.c` resolves each `-L` argument against the working directory with `realpath` when it parses the option, and an entry that does not exist stays as given."
3. **ADR 0005 Decision, CLI bullet (M1).** Replace "The CLI supplies a filesystem resolver in `bin/` and maps `-L` and jq's default search list onto it." with: "The CLI supplies a filesystem resolver in `bin/`, resolves each `-L` entry against the working directory as jq's `main.c` does, and passes those entries, or jq's default search list, as the global list."

CHANGES_APPLIED: yes

## Rebuttals
