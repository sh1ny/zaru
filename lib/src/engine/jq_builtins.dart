/// jq-coded builtins hosted by the compiler, copied verbatim from jq's own
/// `src/builtin.jq`.
///
/// Provenance: jq 1.8.2, commit `34f7186b86743a083a589741b6cea95293524108`
/// (<https://github.com/jqlang/jq/blob/34f7186b86743a083a589741b6cea95293524108/src/builtin.jq>),
/// MIT license, Copyright (c) 2012 Stephen Dolan. The text of each definition
/// is unchanged, including whitespace; the line numbers name where it appears
/// in that file. See `docs/compatibility/builtin-provenance.md`.
///
/// Only the M1 callable set and its minimal transitive dependencies appear
/// here. The natives they stand on (`empty`, `not`, `error/0`, `tostring`,
/// the bytecoded `range/2` and `last/1`) are operations of the machine, not
/// definitions. Every other jq builtin remains unsupported.
library;

/// The definition source of each hosted builtin, keyed by `name/arity`.
const Map<String, String> jqCodedBuiltins = {
  // builtin.jq line 2.
  'error/1': r'''def error(msg): msg|error;''',
  // builtin.jq line 4.
  'select/1': r'''def select(f): if f then . else empty end;''',
  // builtin.jq line 37.
  'recurse/1': r'''def recurse(f): def r: ., (f | r); r;''',
  // builtin.jq line 38.
  'recurse/2':
      r'''def recurse(f; cond): def r: ., (f | select(cond) | r); r;''',
  // builtin.jq line 39.
  'recurse/0': r'''def recurse: recurse(.[]?);''',
  // builtin.jq line 73.
  'range/1': r'''def range($x): range(0;$x);''',
  // builtin.jq lines 135-138.
  'while/2': r'''def while(cond; update):
     def _while:
         if cond then ., (update | _while) else empty end;
     _while;''',
  // builtin.jq lines 139-142.
  'until/2': r'''def until(cond; next):
     def _until:
         if cond then . else (next|_until) end;
     _until;''',
  // builtin.jq lines 143-146.
  'limit/2': r'''def limit($n; expr):
  if $n > 0 then label $out | foreach expr as $item ($n; . - 1; $item, if . <= 0 then break $out else empty end)
  elif $n == 0 then empty
  else error("limit doesn't support negative count") end;''',
  // builtin.jq lines 147-150.
  'skip/2': r'''def skip($n; expr):
  if $n > 0 then foreach expr as $item ($n; . - 1; if . < 0 then $item else empty end)
  elif $n == 0 then expr
  else error("skip doesn't support negative count") end;''',
  // builtin.jq lines 152-155.
  'range/3': r'''def range($init; $upto; $by):
    if $by > 0 then $init|while(. < $upto; . + $by)
  elif $by < 0 then $init|while(. > $upto; . + $by)
  else empty end;''',
  // builtin.jq line 156.
  'first/1': r'''def first(g): label $out | g | ., break $out;''',
  // builtin.jq lines 164-166.
  'nth/2': r'''def nth($n; g):
  if $n < 0 then error("nth doesn't support negative indices")
  else first(skip($n; g)) end;''',
  // builtin.jq line 167.
  'first/0': r'''def first: .[0];''',
  // builtin.jq line 168.
  'last/0': r'''def last: .[-1];''',
  // builtin.jq line 169.
  'nth/1': r'''def nth($n): .[$n];''',
  // builtin.jq lines 185-188.
  'repeat/1': r'''def repeat(exp):
     def _repeat:
         exp, _repeat;
     _repeat;''',
};
