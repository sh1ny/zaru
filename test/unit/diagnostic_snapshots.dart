// Captured from pinned jq 1.8.2 (`jq -n -- PROGRAM`, stderr). These are
// reference observations, not generated output of zaru: the parser tests
// compare zaru's ordered rendered diagnostic blocks to them verbatim, so
// expected-token lists, caret widths, UTF-8 columns and error-recovery
// diagnostics are checked against jq without any fixture-ID lookup.

/// Programs jq rejects at parse level, with every `jq: error` block it
/// printed, in order.
const List<(String, List<String>)> jqParseErrorSnapshots = [
  (
    '1 2',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 3:\n    1 2\n      ^',
    ],
  ),
  (
    '1 +',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 +\n      ^',
    ],
  ),
  (
    '1 + )',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 5:\n    1 + )\n        ^',
    ],
  ),
  (
    '(1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 2:\n    (1\n     ^',
    ],
  ),
  (
    '(1 2',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 4:\n    (1 2\n       ^',
    ],
  ),
  (
    ')',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    )\n    ^',
    ],
  ),
  (
    ']',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    ]\n    ^',
    ],
  ),
  (
    '}',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    }\n    ^',
    ],
  ),
  (
    '.[',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 2:\n    .[\n     ^',
    ],
  ),
  (
    '.[1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \':\' or \']\' at <top-level>, line 1, column 3:\n    .[1\n      ^',
    ],
  ),
  (
    '.[1:',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 4:\n    .[1:\n       ^',
    ],
  ),
  (
    '.[1:2',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 5:\n    .[1:2\n        ^',
    ],
  ),
  (
    '.[:',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    .[:\n      ^',
    ],
  ),
  (
    '.[1 2]',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \':\' or \']\' at <top-level>, line 1, column 5:\n    .[1 2]\n        ^',
    ],
  ),
  (
    '.[1;2]',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \':\' or \']\' at <top-level>, line 1, column 4:\n    .[1;2]\n       ^',
    ],
  ),
  (
    '.a[',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    .a[\n      ^',
    ],
  ),
  (
    '.a[1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \':\' or \']\' at <top-level>, line 1, column 4:\n    .a[1\n       ^',
    ],
  ),
  (
    '.a.',
    [
      'jq: error: syntax error, unexpected end of file, expecting FORMAT or QQSTRING_START or \'[\' at <top-level>, line 1, column 3:\n    .a.\n      ^',
    ],
  ),
  (
    '.a b',
    [
      'jq: error: syntax error, unexpected IDENT, expecting end of file at <top-level>, line 1, column 4:\n    .a b\n       ^',
    ],
  ),
  (
    '.a.b.c.',
    [
      'jq: error: syntax error, unexpected end of file, expecting FORMAT or QQSTRING_START or \'[\' at <top-level>, line 1, column 7:\n    .a.b.c.\n          ^',
    ],
  ),
  (
    '..a',
    [
      'jq: error: syntax error, unexpected IDENT, expecting end of file at <top-level>, line 1, column 3:\n    ..a\n      ^',
    ],
  ),
  (
    '. a',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    . a\n      ^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 1:\n    . a\n    ^^^',
    ],
  ),
  (
    '. a b',
    [
      'jq: error: syntax error, unexpected IDENT at <top-level>, line 1, column 5:\n    . a b\n        ^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 1:\n    . a b\n    ^^^^^',
    ],
  ),
  (
    '. 1',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 3:\n    . 1\n      ^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 1:\n    . 1\n    ^^^',
    ],
  ),
  (
    '. )',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 3:\n    . )\n      ^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 1:\n    . )\n    ^^^',
    ],
  ),
  (
    '.a. ',
    [
      'jq: error: syntax error, unexpected end of file, expecting FORMAT or QQSTRING_START or \'[\' at <top-level>, line 1, column 4:\n    .a. \n       ^',
    ],
  ),
  (
    '1 as',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 3:\n    1 as\n      ^^',
    ],
  ),
  (
    '1 as \$x',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' at <top-level>, line 1, column 6:\n    1 as \$x\n         ^^',
    ],
  ),
  (
    '1 as \$x |',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 9:\n    1 as \$x |\n            ^',
    ],
  ),
  (
    '. as [] | null',
    [
      'jq: error: syntax error, unexpected \']\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 7:\n    . as [] | null\n          ^',
    ],
  ),
  (
    '. as {} | null',
    [
      'jq: error: syntax error, unexpected \'}\' at <top-level>, line 1, column 7:\n    . as {} | null\n          ^',
    ],
  ),
  (
    '. as {a} | 1',
    [
      'jq: error: syntax error, unexpected \'}\', expecting \':\' at <top-level>, line 1, column 8:\n    . as {a} | 1\n           ^',
    ],
  ),
  (
    '. as {a:\$x, b} | 1',
    [
      'jq: error: syntax error, unexpected \'}\', expecting \':\' at <top-level>, line 1, column 14:\n    . as {a:\$x, b} | 1\n                 ^',
    ],
  ),
  (
    '. as {"a" \$x} | 1',
    [
      'jq: error: syntax error, unexpected BINDING, expecting \':\' at <top-level>, line 1, column 11:\n    . as {"a" \$x} | 1\n              ^^',
    ],
  ),
  (
    '. as {1+2:\$x} | 1',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 7:\n    . as {1+2:\$x} | 1\n          ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 7:\n    . as {1+2:\$x} | 1\n          ^^^^^^',
    ],
  ),
  (
    '. as {(1):\$x} | 1',
    [
      'jq: error: Cannot use number (1) as object key at <top-level>, line 1, column 8:\n    . as {(1):\$x} | 1\n           ^',
    ],
  ),
  (
    '. as {(true):\$foo} | \$foo',
    [
      'jq: error: Cannot use boolean (true) as object key at <top-level>, line 1, column 8:\n    . as {(true):\$foo} | \$foo\n           ^^^^',
    ],
  ),
  (
    '. as {\$a:} | 1',
    [
      'jq: error: syntax error, unexpected \'}\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 10:\n    . as {\$a:} | 1\n             ^',
    ],
  ),
  (
    '. as [\$a ?// ] | 1',
    [
      'jq: error: syntax error, unexpected ?//, expecting \',\' or \']\' at <top-level>, line 1, column 10:\n    . as [\$a ?// ] | 1\n             ^^^',
    ],
  ),
  (
    '. as [\$a, \$b | 1',
    [
      'jq: error: syntax error, unexpected \'|\', expecting \',\' or \']\' at <top-level>, line 1, column 14:\n    . as [\$a, \$b | 1\n                 ^',
    ],
  ),
  (
    '. as (\$x) | 1',
    [
      'jq: error: syntax error, unexpected \'(\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 6:\n    . as (\$x) | 1\n         ^',
    ],
  ),
  (
    '. as \$x ?// | 1',
    [
      'jq: error: syntax error, unexpected \'|\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 13:\n    . as \$x ?// | 1\n                ^',
    ],
  ),
  (
    'if 1 then 2',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 11:\n    if 1 then 2\n              ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2\n    ^^^^^^^^^^^',
    ],
  ),
  (
    'if 1 then 2 else',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 13:\n    if 1 then 2 else\n                ^^^^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2 else\n    ^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    'if 1 then 2 else 3',
    [
      'jq: error: syntax error, unexpected end of file, expecting end or \'|\' or \',\' at <top-level>, line 1, column 18:\n    if 1 then 2 else 3\n                     ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2 else 3\n    ^^^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    'if 1 then else 3 end',
    [
      'jq: error: syntax error, unexpected else at <top-level>, line 1, column 11:\n    if 1 then else 3 end\n              ^^^^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then else 3 end\n    ^^^^^^^^^^^^^^',
    ],
  ),
  (
    'if 1 2 then 3 end',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting then or \'|\' or \',\' at <top-level>, line 1, column 6:\n    if 1 2 then 3 end\n         ^',
    ],
  ),
  (
    'if 1 then 2 elif then 4 end',
    [
      'jq: error: syntax error, unexpected then at <top-level>, line 1, column 18:\n    if 1 then 2 elif then 4 end\n                     ^^^^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2 elif then 4 end\n    ^^^^^^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    'if 1 then 2 elif 3 then 4',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 25:\n    if 1 then 2 elif 3 then 4\n                            ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2 elif 3 then 4\n    ^^^^^^^^^^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    'if',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 1:\n    if\n    ^^',
    ],
  ),
  (
    'if 1',
    [
      'jq: error: syntax error, unexpected end of file, expecting then or \'|\' or \',\' at <top-level>, line 1, column 4:\n    if 1\n       ^',
    ],
  ),
  (
    'if 1 then',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 6:\n    if 1 then\n         ^^^^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then\n    ^^^^^^^^^',
    ],
  ),
  (
    'if . then 1 else 2 end end',
    [
      'jq: error: syntax error, unexpected end, expecting end of file at <top-level>, line 1, column 24:\n    if . then 1 else 2 end end\n                           ^^^',
    ],
  ),
  (
    'try',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 1:\n    try\n    ^^^',
    ],
  ),
  (
    'try catch',
    [
      'jq: error: syntax error, unexpected catch at <top-level>, line 1, column 5:\n    try catch\n        ^^^^^',
    ],
  ),
  (
    'try 1 catch',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 7:\n    try 1 catch\n          ^^^^^',
      'jq: error: Possibly unterminated \'try\' statement at <top-level>, line 1, column 1:\n    try 1 catch\n    ^^^^^^^^^^^',
    ],
  ),
  (
    'try 1 catch 2 catch 3',
    [
      'jq: error: syntax error, unexpected catch, expecting end of file at <top-level>, line 1, column 15:\n    try 1 catch 2 catch 3\n                  ^^^^^',
    ],
  ),
  (
    'try 1 catch ]',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 13:\n    try 1 catch ]\n                ^',
      'jq: error: Possibly unterminated \'try\' statement at <top-level>, line 1, column 1:\n    try 1 catch ]\n    ^^^^^^^^^^^^^',
    ],
  ),
  (
    'reduce',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 1:\n    reduce\n    ^^^^^^',
    ],
  ),
  (
    'reduce . as \$x',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'(\' at <top-level>, line 1, column 13:\n    reduce . as \$x\n                ^^',
    ],
  ),
  (
    'reduce . as \$x (0',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \';\' at <top-level>, line 1, column 17:\n    reduce . as \$x (0\n                    ^',
    ],
  ),
  (
    'reduce . as \$x (0;',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 18:\n    reduce . as \$x (0;\n                     ^',
    ],
  ),
  (
    'reduce . as \$x (0; 1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 20:\n    reduce . as \$x (0; 1\n                       ^',
    ],
  ),
  (
    'reduce . as \$x (0; 1; 2)',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 21:\n    reduce . as \$x (0; 1; 2)\n                        ^',
    ],
  ),
  (
    'reduce . as \$x 0',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'(\' at <top-level>, line 1, column 16:\n    reduce . as \$x 0\n                   ^',
    ],
  ),
  (
    'reduce . (0;1)',
    [
      'jq: error: syntax error, unexpected \'(\' at <top-level>, line 1, column 10:\n    reduce . (0;1)\n             ^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 8:\n    reduce . (0;1)\n           ^^^',
    ],
  ),
  (
    'reduce . as',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 10:\n    reduce . as\n             ^^',
    ],
  ),
  (
    'foreach . as \$x (0;1;2;3)',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 23:\n    foreach . as \$x (0;1;2;3)\n                          ^',
    ],
  ),
  (
    'foreach . as \$x (0;1;2;3;4)',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 23:\n    foreach . as \$x (0;1;2;3;4)\n                          ^',
    ],
  ),
  (
    'foreach . as \$x',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'(\' at <top-level>, line 1, column 14:\n    foreach . as \$x\n                 ^^',
    ],
  ),
  (
    'foreach . as \$x (0',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \';\' at <top-level>, line 1, column 18:\n    foreach . as \$x (0\n                     ^',
    ],
  ),
  (
    'foreach . as \$x (0;1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \';\' or \')\' at <top-level>, line 1, column 20:\n    foreach . as \$x (0;1\n                       ^',
    ],
  ),
  (
    'def f: 1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \';\' at <top-level>, line 1, column 8:\n    def f: 1\n           ^',
    ],
  ),
  (
    'def f(: 1; .',
    [
      'jq: error: syntax error, unexpected \':\', expecting IDENT or BINDING at <top-level>, line 1, column 7:\n    def f(: 1; .\n          ^',
    ],
  ),
  (
    'def',
    [
      'jq: error: syntax error, unexpected end of file, expecting IDENT at <top-level>, line 1, column 1:\n    def\n    ^^^',
    ],
  ),
  (
    'def f',
    [
      'jq: error: syntax error, unexpected end of file, expecting \':\' or \'(\' at <top-level>, line 1, column 5:\n    def f\n        ^',
    ],
  ),
  (
    'def f(a) 1; 1',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \':\' at <top-level>, line 1, column 10:\n    def f(a) 1; 1\n             ^',
    ],
  ),
  (
    'def f(1): 1; 1',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting IDENT or BINDING at <top-level>, line 1, column 7:\n    def f(1): 1; 1\n          ^',
    ],
  ),
  (
    'def f(a;): 1; 1',
    [
      'jq: error: syntax error, unexpected \')\', expecting IDENT or BINDING at <top-level>, line 1, column 9:\n    def f(a;): 1; 1\n            ^',
    ],
  ),
  (
    'def f: ; 1',
    [
      'jq: error: syntax error, unexpected \';\' at <top-level>, line 1, column 8:\n    def f: ; 1\n           ^',
    ],
  ),
  (
    'def f: 1; def',
    [
      'jq: error: syntax error, unexpected end of file, expecting IDENT at <top-level>, line 1, column 11:\n    def f: 1; def\n              ^^^',
    ],
  ),
  (
    'label',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING at <top-level>, line 1, column 1:\n    label\n    ^^^^^',
    ],
  ),
  (
    'label \$x',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' at <top-level>, line 1, column 7:\n    label \$x\n          ^^',
    ],
  ),
  (
    'label \$x |',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 10:\n    label \$x |\n             ^',
    ],
  ),
  (
    'label 1',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting BINDING at <top-level>, line 1, column 7:\n    label 1\n          ^',
    ],
  ),
  (
    'break',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING at <top-level>, line 1, column 1:\n    break\n    ^^^^^',
      'jq: error: break requires a label to break to at <top-level>, line 1, column 1:\n    break\n    ^^^^^',
    ],
  ),
  (
    'break 1',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting BINDING at <top-level>, line 1, column 7:\n    break 1\n          ^',
      'jq: error: break requires a label to break to at <top-level>, line 1, column 1:\n    break 1\n    ^^^^^^^',
    ],
  ),
  (
    '@',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    @\n    ^',
    ],
  ),
  (
    '@ base64',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    @ base64\n    ^',
    ],
  ),
  (
    '"abc',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 2:\n    "abc\n     ^^^',
    ],
  ),
  (
    '"\\(1',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_INTERP_END or \'|\' or \',\' at <top-level>, line 1, column 4:\n    "\\(1\n       ^',
    ],
  ),
  (
    '"\\(1 +"',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 7:\n    "\\(1 +"\n          ^',
    ],
  ),
  (
    '"\\(1;2)"',
    [
      'jq: error: syntax error, unexpected \';\', expecting QQSTRING_INTERP_END or \'|\' or \',\' at <top-level>, line 1, column 5:\n    "\\(1;2)"\n        ^',
    ],
  ),
  (
    '"\\()"',
    [
      'jq: error: syntax error, unexpected QQSTRING_INTERP_END at <top-level>, line 1, column 4:\n    "\\()"\n       ^',
    ],
  ),
  (
    '"\\("',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 4:\n    "\\("\n       ^',
    ],
  ),
  (
    ' "',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 2:\n     "\n     ^',
    ],
  ),
  (
    '"abc\\"',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 5:\n    "abc\\"\n        ^^',
    ],
  ),
  (
    '"\\x"',
    [
      'jq: error: Invalid escape at line 1, column 4 (while parsing \'"\\x"\') at <top-level>, line 1, column 2:\n    "\\x"\n     ^^',
    ],
  ),
  (
    '"\\u12"',
    [
      'jq: error: Invalid \\uXXXX escape at line 1, column 6 (while parsing \'"\\u12"\') at <top-level>, line 1, column 2:\n    "\\u12"\n     ^^^^',
    ],
  ),
  (
    '"\\uZZZZ"',
    [
      'jq: error: Invalid characters in \\uXXXX escape at line 1, column 8 (while parsing \'"\\uZZZZ"\') at <top-level>, line 1, column 2:\n    "\\uZZZZ"\n     ^^^^^^',
    ],
  ),
  (
    '"\\ud800"',
    [
      'jq: error: Invalid \\uXXXX\\uXXXX surrogate pair escape at line 1, column 8 (while parsing \'"\\ud800"\') at <top-level>, line 1, column 2:\n    "\\ud800"\n     ^^^^^^',
    ],
  ),
  (
    '"u\\vw" | "\\q"',
    [
      'jq: error: Invalid escape at line 1, column 4 (while parsing \'"\\v"\') at <top-level>, line 1, column 3:\n    "u\\vw" | "\\q"\n      ^^',
      'jq: error: Invalid escape at line 1, column 4 (while parsing \'"\\q"\') at <top-level>, line 1, column 11:\n    "u\\vw" | "\\q"\n              ^^',
    ],
  ),
  (
    '"\\q" 1 "\\z"',
    [
      'jq: error: Invalid escape at line 1, column 4 (while parsing \'"\\q"\') at <top-level>, line 1, column 2:\n    "\\q" 1 "\\z"\n     ^^',
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 6:\n    "\\q" 1 "\\z"\n         ^',
    ],
  ),
  (
    '{a:1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'}\' at <top-level>, line 1, column 4:\n    {a:1\n       ^',
    ],
  ),
  (
    '{a',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'}\' at <top-level>, line 1, column 2:\n    {a\n     ^',
    ],
  ),
  (
    '{a:',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    {a:\n      ^',
    ],
  ),
  (
    '{(1)',
    [
      'jq: error: syntax error, unexpected end of file, expecting \':\' at <top-level>, line 1, column 4:\n    {(1)\n       ^',
    ],
  ),
  (
    '{(1) 2}',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \':\' at <top-level>, line 1, column 6:\n    {(1) 2}\n         ^',
    ],
  ),
  (
    '{a:1 b}',
    [
      'jq: error: syntax error, unexpected IDENT, expecting \'}\' at <top-level>, line 1, column 6:\n    {a:1 b}\n         ^',
    ],
  ),
  (
    '{a:1,,b:2}',
    [
      'jq: error: syntax error, unexpected \',\' at <top-level>, line 1, column 6:\n    {a:1,,b:2}\n         ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 6:\n    {a:1,,b:2}\n         ^^',
    ],
  ),
  (
    '{,}',
    [
      'jq: error: syntax error, unexpected \',\' at <top-level>, line 1, column 2:\n    {,}\n     ^',
    ],
  ),
  (
    '{a b}',
    [
      'jq: error: syntax error, unexpected IDENT, expecting \'}\' at <top-level>, line 1, column 4:\n    {a b}\n       ^',
    ],
  ),
  (
    '{"a" b}',
    [
      'jq: error: syntax error, unexpected IDENT, expecting \'}\' at <top-level>, line 1, column 6:\n    {"a" b}\n         ^',
    ],
  ),
  (
    '{a:}',
    [
      'jq: error: syntax error, unexpected \'}\' at <top-level>, line 1, column 4:\n    {a:}\n       ^',
    ],
  ),
  (
    '{:1}',
    [
      'jq: error: syntax error, unexpected \':\' at <top-level>, line 1, column 2:\n    {:1}\n     ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {:1}\n     ^',
    ],
  ),
  (
    '{1:2}',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 2:\n    {1:2}\n     ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {1:2}\n     ^',
    ],
  ),
  (
    '{1+2:3}',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 2:\n    {1+2:3}\n     ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {1+2:3}\n     ^^^',
    ],
  ),
  (
    '{(0):1}',
    [
      'jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 3:\n    {(0):1}\n      ^',
    ],
  ),
  (
    '{(1+2):3}',
    [
      'jq: error: Cannot use number (3) as object key at <top-level>, line 1, column 3:\n    {(1+2):3}\n      ^^^',
    ],
  ),
  (
    '{(null):1}',
    [
      'jq: error: Cannot use null (null) as object key at <top-level>, line 1, column 3:\n    {(null):1}\n      ^^^^',
    ],
  ),
  (
    '{([1,2]):1}',
    [
      'jq: error: Cannot use array ([1,2]) as object key at <top-level>, line 1, column 3:\n    {([1,2]):1}\n      ^^^^^',
    ],
  ),
  (
    '{({}):1}',
    [
      'jq: error: Cannot use object ({}) as object key at <top-level>, line 1, column 3:\n    {({}):1}\n      ^^',
    ],
  ),
  (
    '{({"a":1}):1}',
    [
      'jq: error: Cannot use object ({"a":1}) as object key at <top-level>, line 1, column 3:\n    {({"a":1}):1}\n      ^^^^^^^',
    ],
  ),
  (
    '{(1.0):1}',
    [
      'jq: error: Cannot use number (1.0) as object key at <top-level>, line 1, column 3:\n    {(1.0):1}\n      ^^^',
    ],
  ),
  (
    '{(1e2):1}',
    [
      'jq: error: Cannot use number (1E+2) as object key at <top-level>, line 1, column 3:\n    {(1e2):1}\n      ^^^',
    ],
  ),
  (
    '{non_const:., (0):1}',
    [
      'jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 16:\n    {non_const:., (0):1}\n                   ^',
    ],
  ),
  (
    '{a:1, (true):2, (false):3}',
    [
      'jq: error: Cannot use boolean (true) as object key at <top-level>, line 1, column 8:\n    {a:1, (true):2, (false):3}\n           ^^^^',
      'jq: error: Cannot use boolean (false) as object key at <top-level>, line 1, column 18:\n    {a:1, (true):2, (false):3}\n                     ^^^^^',
    ],
  ),
  (
    '{1 2}',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 2:\n    {1 2}\n     ^',
    ],
  ),
  (
    '[1,]',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 4:\n    [1,]\n       ^',
    ],
  ),
  (
    '[,1]',
    [
      'jq: error: syntax error, unexpected \',\' at <top-level>, line 1, column 2:\n    [,1]\n     ^',
    ],
  ),
  (
    '[1 2]',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 4:\n    [1 2]\n       ^',
    ],
  ),
  (
    '[1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 2:\n    [1\n     ^',
    ],
  ),
  (
    '[1,',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    [1,\n      ^',
    ],
  ),
  (
    '[|1]',
    [
      'jq: error: syntax error, unexpected \'|\' at <top-level>, line 1, column 2:\n    [|1]\n     ^',
    ],
  ),
  (
    '1 < 2 < 3',
    [
      'jq: error: syntax error, unexpected \'<\' at <top-level>, line 1, column 7:\n    1 < 2 < 3\n          ^',
    ],
  ),
  (
    '1 = 2 = 3',
    [
      'jq: error: syntax error, unexpected \'=\' at <top-level>, line 1, column 7:\n    1 = 2 = 3\n          ^',
    ],
  ),
  (
    '1 == 2 != 3',
    [
      'jq: error: syntax error, unexpected != at <top-level>, line 1, column 8:\n    1 == 2 != 3\n           ^^',
    ],
  ),
  (
    '1 < 2 == 3',
    [
      'jq: error: syntax error, unexpected == at <top-level>, line 1, column 7:\n    1 < 2 == 3\n          ^^',
    ],
  ),
  (
    '1 + 2 < 3 < 4',
    [
      'jq: error: syntax error, unexpected \'<\' at <top-level>, line 1, column 11:\n    1 + 2 < 3 < 4\n              ^',
    ],
  ),
  (
    'f(',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 2:\n    f(\n     ^',
    ],
  ),
  (
    'f(1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \';\' or \')\' at <top-level>, line 1, column 3:\n    f(1\n      ^',
    ],
  ),
  (
    'f(1;',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 4:\n    f(1;\n       ^',
    ],
  ),
  (
    'f(1;)',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 5:\n    f(1;)\n        ^',
    ],
  ),
  (
    'f(;)',
    [
      'jq: error: syntax error, unexpected \';\' at <top-level>, line 1, column 3:\n    f(;)\n      ^',
    ],
  ),
  (
    'f(1 2)',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \';\' or \')\' at <top-level>, line 1, column 5:\n    f(1 2)\n        ^',
    ],
  ),
  (
    'f(1;2',
    [
      'jq: error: syntax error, unexpected end of file, expecting \';\' or \')\' at <top-level>, line 1, column 5:\n    f(1;2\n        ^',
    ],
  ),
  (
    'f(if)',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 5:\n    f(if)\n        ^',
    ],
  ),
  (
    'f(,)',
    [
      'jq: error: syntax error, unexpected \',\' at <top-level>, line 1, column 3:\n    f(,)\n      ^',
    ],
  ),
  (
    '? ',
    [
      'jq: error: syntax error, unexpected \'?\', expecting end of file at <top-level>, line 1, column 1:\n    ? \n    ^',
    ],
  ),
  (
    '...',
    [
      'jq: error: syntax error, unexpected end of file, expecting FORMAT or QQSTRING_START or \'[\' at <top-level>, line 1, column 3:\n    ...\n      ^',
    ],
  ),
  (
    '.. ..)',
    [
      'jq: error: syntax error, unexpected .., expecting end of file at <top-level>, line 1, column 4:\n    .. ..)\n       ^^',
    ],
  ),
  (
    '\$',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'\$\' at <top-level>, line 1, column 1:\n    \$\n    ^',
    ],
  ),
  (
    '\$\$',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'\$\' at <top-level>, line 1, column 2:\n    \$\$\n     ^',
    ],
  ),
  (
    '\$\$\$',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING at <top-level>, line 1, column 3:\n    \$\$\$\n      ^',
    ],
  ),
  (
    '\$\$\$\$',
    [
      'jq: error: syntax error, unexpected \'\$\', expecting BINDING at <top-level>, line 1, column 4:\n    \$\$\$\$\n       ^',
    ],
  ),
  (
    '%::wat',
    [
      'jq: error: syntax error, unexpected \'%\', expecting end of file at <top-level>, line 1, column 1:\n    %::wat\n    ^',
    ],
  ),
  (
    'a::',
    [
      'jq: error: syntax error, unexpected \':\', expecting end of file at <top-level>, line 1, column 2:\n    a::\n     ^',
    ],
  ),
  (
    '{\n',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 2:\n    {\n     ^',
    ],
  ),
  (
    '}\n',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    }\n    ^',
    ],
  ),
  (
    '1 +\n  # comment\n  ',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 3, column 1:\n      \n    ^^',
    ],
  ),
  (
    '.a |\n  .b |\n  ]\n',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 3, column 3:\n      ]\n      ^',
    ],
  ),
  (
    '[\n  1,\n  2\n  3\n]',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \']\' at <top-level>, line 4, column 3:\n      3\n      ^',
    ],
  ),
  (
    '.a\n| .b\n| (1\n',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \')\' at <top-level>, line 3, column 5:\n    | (1\n        ^',
    ],
  ),
  (
    'import "a" as b',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 15:\n    import "a" as b\n                  ^',
    ],
  ),
  (
    'import "a";',
    [
      'jq: error: syntax error, unexpected \';\', expecting as at <top-level>, line 1, column 11:\n    import "a";\n              ^',
    ],
  ),
  (
    'include "a"',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 11:\n    include "a"\n              ^',
    ],
  ),
  (
    'include a;',
    [
      'jq: error: syntax error, unexpected IDENT, expecting FORMAT or QQSTRING_START at <top-level>, line 1, column 9:\n    include a;\n            ^',
    ],
  ),
  (
    'module {}',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \';\' at <top-level>, line 1, column 9:\n    module {}\n            ^',
    ],
  ),
  (
    'module {}; import',
    [
      'jq: error: syntax error, unexpected end of file, expecting FORMAT or QQSTRING_START at <top-level>, line 1, column 12:\n    module {}; import\n               ^^^^^^',
    ],
  ),
  (
    'import "a" as',
    [
      'jq: error: syntax error, unexpected end of file, expecting IDENT or BINDING at <top-level>, line 1, column 12:\n    import "a" as\n               ^^',
    ],
  ),
  (
    'import "a" as 1; .',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting IDENT or BINDING at <top-level>, line 1, column 15:\n    import "a" as 1; .\n                  ^',
    ],
  ),
  (
    'module (.+1); 0',
    [
      'jq: error: Module metadata must be constant at <top-level>, line 1, column 8:\n    module (.+1); 0\n           ^^^^^',
    ],
  ),
  (
    'module []; 0',
    [
      'jq: error: Module metadata must be an object at <top-level>, line 1, column 8:\n    module []; 0\n           ^^',
    ],
  ),
  (
    'include "a" (.+1); 0',
    [
      'jq: error: Module metadata must be constant at <top-level>, line 1, column 13:\n    include "a" (.+1); 0\n                ^^^^^',
    ],
  ),
  (
    'include "a" []; 0',
    [
      'jq: error: Module metadata must be an object at <top-level>, line 1, column 13:\n    include "a" []; 0\n                ^^',
    ],
  ),
  (
    'include "\\ "; 0',
    [
      'jq: error: Invalid escape at line 1, column 4 (while parsing \'"\\ "\') at <top-level>, line 1, column 10:\n    include "\\ "; 0\n             ^^',
    ],
  ),
  (
    'include "\\(a)"; 0',
    [
      'jq: error: Import path must be constant at <top-level>, line 1, column 9:\n    include "\\(a)"; 0\n            ^^^^^^',
    ],
  ),
  (
    '1 | import "a" as b; .',
    [
      'jq: error: syntax error, unexpected import at <top-level>, line 1, column 5:\n    1 | import "a" as b; .\n        ^^^^^^',
    ],
  ),
  (
    'def f: 1; import "a" as b; .',
    [
      'jq: error: syntax error, unexpected import, expecting end of file at <top-level>, line 1, column 11:\n    def f: 1; import "a" as b; .\n              ^^^^^^',
    ],
  ),
  (
    '[.[] | if . then 1 else 2 end]]',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 31:\n    [.[] | if . then 1 else 2 end]]\n                                  ^',
    ],
  ),
  (
    '[.[] | (1,2]',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 12:\n    [.[] | (1,2]\n               ^',
    ],
  ),
  (
    '{a: (1}',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 7:\n    {a: (1}\n          ^',
    ],
  ),
  (
    '{(1}',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 4:\n    {(1}\n       ^',
    ],
  ),
  (
    '.[(1]',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 5:\n    .[(1]\n        ^',
    ],
  ),
  (
    '"\\([1)]"',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 6:\n    "\\([1)]"\n         ^',
    ],
  ),
  (
    '(1 | 2',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 6:\n    (1 | 2\n         ^',
    ],
  ),
  (
    '((1)',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 4:\n    ((1)\n       ^',
    ],
  ),
  (
    '(1))',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 4:\n    (1))\n       ^',
    ],
  ),
  (
    '(((1 +)))',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 7:\n    (((1 +)))\n          ^',
    ],
  ),
  (
    '(1 + )',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 6:\n    (1 + )\n         ^',
    ],
  ),
  (
    '(1 + ) + 2',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 6:\n    (1 + ) + 2\n         ^',
    ],
  ),
  (
    '[1 + ]',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 6:\n    [1 + ]\n         ^',
    ],
  ),
  (
    '[1 + ] | .',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 6:\n    [1 + ] | .\n         ^',
    ],
  ),
  (
    '{a: 1 + }',
    [
      'jq: error: syntax error, unexpected \'}\' at <top-level>, line 1, column 9:\n    {a: 1 + }\n            ^',
    ],
  ),
  (
    '{(1 +): 2}',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 6:\n    {(1 +): 2}\n         ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {(1 +): 2}\n     ^^^^^',
    ],
  ),
  (
    '[1 + ], 2 +',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 6:\n    [1 + ], 2 +\n         ^',
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 11:\n    [1 + ], 2 +\n              ^',
    ],
  ),
  (
    '(1 + ), (2 +',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 6:\n    (1 + ), (2 +\n         ^',
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 12:\n    (1 + ), (2 +\n               ^',
    ],
  ),
  (
    '.a[1 +]',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 7:\n    .a[1 +]\n          ^',
    ],
  ),
  (
    '.a[1 + ]?',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 8:\n    .a[1 + ]?\n           ^',
    ],
  ),
  (
    '.a[1:2:3]',
    [
      'jq: error: syntax error, unexpected \':\', expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 7:\n    .a[1:2:3]\n          ^',
    ],
  ),
  (
    '1 as \$x | 2 as',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 13:\n    1 as \$x | 2 as\n                ^^',
    ],
  ),
  (
    '1 as \$x | )',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 11:\n    1 as \$x | )\n              ^',
    ],
  ),
  (
    'def f: ); 1',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 8:\n    def f: ); 1\n           ^',
    ],
  ),
  (
    'def f(x): ]; 1',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 11:\n    def f(x): ]; 1\n              ^',
    ],
  ),
  (
    'if 1 then ) else 2 end',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 11:\n    if 1 then ) else 2 end\n              ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then ) else 2 end\n    ^^^^^^^^^^^',
    ],
  ),
  (
    'if ) then 2 end',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 4:\n    if ) then 2 end\n       ^',
    ],
  ),
  (
    'try ) catch 2',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 5:\n    try ) catch 2\n        ^',
    ],
  ),
  (
    'try 1 catch )',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 13:\n    try 1 catch )\n                ^',
      'jq: error: Possibly unterminated \'try\' statement at <top-level>, line 1, column 1:\n    try 1 catch )\n    ^^^^^^^^^^^^^',
    ],
  ),
  (
    'reduce ) as \$x (0; 1)',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 8:\n    reduce ) as \$x (0; 1)\n           ^',
    ],
  ),
  (
    'reduce . as \$x ()',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 17:\n    reduce . as \$x ()\n                    ^',
    ],
  ),
  (
    'foreach . as \$x (0;)',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 20:\n    foreach . as \$x (0;)\n                       ^',
    ],
  ),
  (
    'if 1 then 2 else ) end',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 18:\n    if 1 then 2 else ) end\n                     ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2 else ) end\n    ^^^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    'label \$x | )',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 12:\n    label \$x | )\n               ^',
    ],
  ),
  (
    '. as [\$a, ) ] | 1',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 11:\n    . as [\$a, ) ] | 1\n              ^',
    ],
  ),
  (
    '. as {a: ) } | 1',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 10:\n    . as {a: ) } | 1\n             ^',
    ],
  ),
  (
    '{a: )}',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 5:\n    {a: )}\n        ^',
    ],
  ),
  (
    '{(1): )}',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 7:\n    {(1): )}\n          ^',
    ],
  ),
  (
    '"\\() "',
    [
      'jq: error: syntax error, unexpected QQSTRING_INTERP_END at <top-level>, line 1, column 4:\n    "\\() "\n       ^',
    ],
  ),
  (
    '"\\(1 2)"',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting QQSTRING_INTERP_END or \'|\' or \',\' at <top-level>, line 1, column 6:\n    "\\(1 2)"\n         ^',
    ],
  ),
  (
    '@base64 1',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 9:\n    @base64 1\n            ^',
    ],
  ),
  (
    '{a: 1 as \$x | 2}',
    [
      'jq: error: syntax error, unexpected as, expecting \'}\' at <top-level>, line 1, column 7:\n    {a: 1 as \$x | 2}\n          ^^',
    ],
  ),
  (
    '.a.[1:2]',
    [
      'jq: error: syntax error, unexpected \':\', expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 6:\n    .a.[1:2]\n         ^',
    ],
  ),
  (
    '.a.[1:2]?',
    [
      'jq: error: syntax error, unexpected \':\', expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 6:\n    .a.[1:2]?\n         ^',
    ],
  ),
  (
    '. as {\$__loc__} | 1',
    [
      'jq: error: syntax error, unexpected \$__loc__ at <top-level>, line 1, column 7:\n    . as {\$__loc__} | 1\n          ^^^^^^^^',
    ],
  ),
  (
    '-',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 1:\n    -\n    ^',
    ],
  ),
  (
    '- )',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER at <top-level>, line 1, column 3:\n    - )\n      ^',
    ],
  ),
  (
    '1 -',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 -\n      ^',
    ],
  ),
  (
    '1 *',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 *\n      ^',
    ],
  ),
  (
    '1 and',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 and\n      ^^^',
    ],
  ),
  (
    '1 or',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 or\n      ^^',
    ],
  ),
  (
    '1 //',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 //\n      ^^',
    ],
  ),
  (
    '1 ==',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 ==\n      ^^',
    ],
  ),
  (
    '1 |=',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    1 |=\n      ^^',
    ],
  ),
  (
    '. |',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    . |\n      ^',
    ],
  ),
  (
    '. ,',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    . ,\n      ^',
    ],
  ),
  (
    '. as \$x | . as',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 13:\n    . as \$x | . as\n                ^^',
    ],
  ),
  (
    'def f: 1; 2 def',
    [
      'jq: error: syntax error, unexpected def, expecting end of file at <top-level>, line 1, column 13:\n    def f: 1; 2 def\n                ^^^',
    ],
  ),
  (
    ';',
    [
      'jq: error: syntax error, unexpected \';\', expecting end of file at <top-level>, line 1, column 1:\n    ;\n    ^',
    ],
  ),
  (
    '1;2',
    [
      'jq: error: syntax error, unexpected \';\', expecting end of file at <top-level>, line 1, column 2:\n    1;2\n     ^',
    ],
  ),
  (
    '1 ; 2',
    [
      'jq: error: syntax error, unexpected \';\', expecting end of file at <top-level>, line 1, column 3:\n    1 ; 2\n      ^',
    ],
  ),
  (
    ':',
    [
      'jq: error: syntax error, unexpected \':\', expecting end of file at <top-level>, line 1, column 1:\n    :\n    ^',
    ],
  ),
  (
    ',',
    [
      'jq: error: syntax error, unexpected \',\', expecting end of file at <top-level>, line 1, column 1:\n    ,\n    ^',
    ],
  ),
  (
    '|',
    [
      'jq: error: syntax error, unexpected \'|\', expecting end of file at <top-level>, line 1, column 1:\n    |\n    ^',
    ],
  ),
  (
    '1 | | 2',
    [
      'jq: error: syntax error, unexpected \'|\' at <top-level>, line 1, column 5:\n    1 | | 2\n        ^',
    ],
  ),
  (
    '1 , , 2',
    [
      'jq: error: syntax error, unexpected \',\' at <top-level>, line 1, column 5:\n    1 , , 2\n        ^',
    ],
  ),
  (
    '= 1',
    [
      'jq: error: syntax error, unexpected \'=\', expecting end of file at <top-level>, line 1, column 1:\n    = 1\n    ^',
    ],
  ),
  (
    'as',
    [
      'jq: error: syntax error, unexpected as, expecting end of file at <top-level>, line 1, column 1:\n    as\n    ^^',
    ],
  ),
  (
    'then',
    [
      'jq: error: syntax error, unexpected then, expecting end of file at <top-level>, line 1, column 1:\n    then\n    ^^^^',
    ],
  ),
  (
    'end',
    [
      'jq: error: syntax error, unexpected end, expecting end of file at <top-level>, line 1, column 1:\n    end\n    ^^^',
    ],
  ),
  (
    'elif',
    [
      'jq: error: syntax error, unexpected elif, expecting end of file at <top-level>, line 1, column 1:\n    elif\n    ^^^^',
    ],
  ),
  (
    'else',
    [
      'jq: error: syntax error, unexpected else, expecting end of file at <top-level>, line 1, column 1:\n    else\n    ^^^^',
    ],
  ),
  (
    'catch',
    [
      'jq: error: syntax error, unexpected catch, expecting end of file at <top-level>, line 1, column 1:\n    catch\n    ^^^^^',
    ],
  ),
  (
    'and',
    [
      'jq: error: syntax error, unexpected and, expecting end of file at <top-level>, line 1, column 1:\n    and\n    ^^^',
    ],
  ),
  (
    'or',
    [
      'jq: error: syntax error, unexpected or, expecting end of file at <top-level>, line 1, column 1:\n    or\n    ^^',
    ],
  ),
  (
    'foreach',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 1:\n    foreach\n    ^^^^^^^',
    ],
  ),
  (
    '1 and and 2',
    [
      'jq: error: syntax error, unexpected and at <top-level>, line 1, column 7:\n    1 and and 2\n          ^^^',
    ],
  ),
  (
    'if 1 then 2 else 3 end 4',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 24:\n    if 1 then 2 else 3 end 4\n                           ^',
    ],
  ),
  (
    '{} {}',
    [
      'jq: error: syntax error, unexpected \'{\', expecting end of file at <top-level>, line 1, column 4:\n    {} {}\n       ^',
    ],
  ),
  (
    '"a" "b"',
    [
      'jq: error: syntax error, unexpected QQSTRING_START, expecting end of file at <top-level>, line 1, column 5:\n    "a" "b"\n        ^',
    ],
  ),
  (
    '.a \$x',
    [
      'jq: error: syntax error, unexpected BINDING, expecting end of file at <top-level>, line 1, column 4:\n    .a \$x\n       ^^',
    ],
  ),
  (
    '\$x \$y',
    [
      'jq: error: syntax error, unexpected BINDING, expecting end of file at <top-level>, line 1, column 4:\n    \$x \$y\n       ^^',
    ],
  ),
  (
    'f g',
    [
      'jq: error: syntax error, unexpected IDENT, expecting end of file at <top-level>, line 1, column 3:\n    f g\n      ^',
    ],
  ),
  (
    'f(1) g(2)',
    [
      'jq: error: syntax error, unexpected IDENT, expecting end of file at <top-level>, line 1, column 6:\n    f(1) g(2)\n         ^',
    ],
  ),
  (
    '1 as \$x | \$x \$x',
    [
      'jq: error: syntax error, unexpected BINDING, expecting end of file at <top-level>, line 1, column 14:\n    1 as \$x | \$x \$x\n                 ^^',
    ],
  ),
  (
    '1 as [\$a,] | 2',
    [
      'jq: error: syntax error, unexpected \']\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 10:\n    1 as [\$a,] | 2\n             ^',
    ],
  ),
  (
    '1 as [,\$a] | 2',
    [
      'jq: error: syntax error, unexpected \',\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 7:\n    1 as [,\$a] | 2\n          ^',
    ],
  ),
  (
    '1 as {} | 2',
    [
      'jq: error: syntax error, unexpected \'}\' at <top-level>, line 1, column 7:\n    1 as {} | 2\n          ^',
    ],
  ),
  (
    '1 as [] | 2',
    [
      'jq: error: syntax error, unexpected \']\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 7:\n    1 as [] | 2\n          ^',
    ],
  ),
  (
    '1 as \$x \$y | 2',
    [
      'jq: error: syntax error, unexpected BINDING, expecting \'|\' at <top-level>, line 1, column 9:\n    1 as \$x \$y | 2\n            ^^',
    ],
  ),
  (
    '1 as \$x | | 2',
    [
      'jq: error: syntax error, unexpected \'|\' at <top-level>, line 1, column 11:\n    1 as \$x | | 2\n              ^',
    ],
  ),
  (
    '1 as | 2',
    [
      'jq: error: syntax error, unexpected \'|\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 6:\n    1 as | 2\n         ^',
    ],
  ),
  (
    '1 as 1 | 2',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 6:\n    1 as 1 | 2\n         ^',
    ],
  ),
  (
    '1 as . | 2',
    [
      'jq: error: syntax error, unexpected \'.\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 6:\n    1 as . | 2\n         ^',
    ],
  ),
  (
    '.x | . as [] | null',
    [
      'jq: error: syntax error, unexpected \']\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 12:\n    .x | . as [] | null\n               ^',
    ],
  ),
  (
    '.a |\n  . as [] | null',
    [
      'jq: error: syntax error, unexpected \']\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 2, column 9:\n      . as [] | null\n            ^',
    ],
  ),
  (
    '"é€😀" | . as [] | null',
    [
      'jq: error: syntax error, unexpected \']\', expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 21:\n    "é€😀" | . as [] | null\n                        ^',
    ],
  ),
  (
    '   {   ',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 5:\n       {   \n        ^^^',
    ],
  ),
  (
    '  }  ',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 3:\n      }  \n      ^',
    ],
  ),
  (
    '[1,\n 2,\n {(0): 1}]',
    [
      'jq: error: Cannot use number (0) as object key at <top-level>, line 3, column 4:\n     {(0): 1}]\n       ^',
    ],
  ),
  (
    '{a: 1} | {(1.5): 2}',
    [
      'jq: error: Cannot use number (1.5) as object key at <top-level>, line 1, column 12:\n    {a: 1} | {(1.5): 2}\n               ^^^',
    ],
  ),
  (
    '{"a": 1, (null): 2}',
    [
      'jq: error: Cannot use null (null) as object key at <top-level>, line 1, column 11:\n    {"a": 1, (null): 2}\n              ^^^^',
    ],
  ),
  (
    '.[] | {(true): .}',
    [
      'jq: error: Cannot use boolean (true) as object key at <top-level>, line 1, column 9:\n    .[] | {(true): .}\n            ^^^^',
    ],
  ),
  (
    '{(1e1000): 1}',
    [
      'jq: error: Cannot use number (1E+1000) as object key at <top-level>, line 1, column 3:\n    {(1e1000): 1}\n      ^^^^^^',
    ],
  ),
  (
    '{((0)): 1}',
    [
      'jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 3:\n    {((0)): 1}\n      ^^^',
    ],
  ),
  (
    '{(1+2*3): 1}',
    [
      'jq: error: Cannot use number (7) as object key at <top-level>, line 1, column 3:\n    {(1+2*3): 1}\n      ^^^^^',
    ],
  ),
  (
    '{([1,2,3]): 1}',
    [
      'jq: error: Cannot use array ([1,2,3]) as object key at <top-level>, line 1, column 3:\n    {([1,2,3]): 1}\n      ^^^^^^^',
    ],
  ),
  (
    '{({a:1,b:[1,2]}): 1}',
    [
      'jq: error: Cannot use object ({"a":1,"b":[1,2]}) as object key at <top-level>, line 1, column 3:\n    {({a:1,b:[1,2]}): 1}\n      ^^^^^^^^^^^^^',
    ],
  ),
  (
    '{({"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":1}): 1}',
    [
      'jq: error: Cannot use object ({"aaaaaaaaaaaaaaaaaaaaaaa...}) as object key at <top-level>, line 1, column 3:\n    {({"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":1}): 1}\n      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    '{("é"): 1, (null): 2}',
    [
      'jq: error: Cannot use null (null) as object key at <top-level>, line 1, column 14:\n    {("é"): 1, (null): 2}\n                 ^^^^',
    ],
  ),
  (
    '{(1): 1, (2): 2}',
    [
      'jq: error: Cannot use number (1) as object key at <top-level>, line 1, column 3:\n    {(1): 1, (2): 2}\n      ^',
      'jq: error: Cannot use number (2) as object key at <top-level>, line 1, column 11:\n    {(1): 1, (2): 2}\n              ^',
    ],
  ),
  (
    '{a: {(3): 4}}',
    [
      'jq: error: Cannot use number (3) as object key at <top-level>, line 1, column 7:\n    {a: {(3): 4}}\n          ^',
    ],
  ),
  (
    '. as {(1): \$x, (null): \$y} | 1',
    [
      'jq: error: Cannot use number (1) as object key at <top-level>, line 1, column 8:\n    . as {(1): \$x, (null): \$y} | 1\n           ^',
      'jq: error: Cannot use null (null) as object key at <top-level>, line 1, column 17:\n    . as {(1): \$x, (null): \$y} | 1\n                    ^^^^',
    ],
  ),
  (
    '{1: 2, 3: 4}',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 2:\n    {1: 2, 3: 4}\n     ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {1: 2, 3: 4}\n     ^',
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 8:\n    {1: 2, 3: 4}\n           ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 8:\n    {1: 2, 3: 4}\n           ^',
    ],
  ),
  (
    '{a:1, 2}',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 7:\n    {a:1, 2}\n          ^',
    ],
  ),
  (
    '{a:1 b:2}',
    [
      'jq: error: syntax error, unexpected IDENT, expecting \'}\' at <top-level>, line 1, column 6:\n    {a:1 b:2}\n         ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {a:1 b:2}\n     ^^^^^',
    ],
  ),
  (
    '{(1)}',
    [
      'jq: error: syntax error, unexpected \'}\', expecting \':\' at <top-level>, line 1, column 5:\n    {(1)}\n        ^',
    ],
  ),
  (
    '[1, 2',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 5:\n    [1, 2\n        ^',
    ],
  ),
  (
    '{"a": [1, 2}',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 12:\n    {"a": [1, 2}\n               ^',
    ],
  ),
  (
    '(1, 2',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 5:\n    (1, 2\n        ^',
    ],
  ),
  (
    '"abc\\(1)',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 8:\n    "abc\\(1)\n           ^',
    ],
  ),
  (
    'if true then 1 else',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 16:\n    if true then 1 else\n                   ^^^^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if true then 1 else\n    ^^^^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    '1 +\n 2 +\n',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 2, column 5:\n     2 +\n        ^',
    ],
  ),
  (
    '1 +\r\n',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 4:\n    1 +\r\n       ^',
    ],
  ),
  (
    'def f(a b): 1; 1',
    [
      'jq: error: syntax error, unexpected IDENT, expecting \';\' or \')\' at <top-level>, line 1, column 9:\n    def f(a b): 1; 1\n            ^',
    ],
  ),
  (
    'def f(;): 1; 1',
    [
      'jq: error: syntax error, unexpected \';\', expecting IDENT or BINDING at <top-level>, line 1, column 7:\n    def f(;): 1; 1\n          ^',
    ],
  ),
  (
    '.a.b.[',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 6:\n    .a.b.[\n         ^',
    ],
  ),
  (
    '.a[1,]',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 6:\n    .a[1,]\n         ^',
    ],
  ),
  (
    '.[]?[',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 5:\n    .[]?[\n        ^',
    ],
  ),
  (
    'reduce . as {a: \$x} (0; 1;)',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 26:\n    reduce . as {a: \$x} (0; 1;)\n                             ^',
    ],
  ),
  (
    'label \$x | break',
    [
      'jq: error: syntax error, unexpected end of file, expecting BINDING at <top-level>, line 1, column 12:\n    label \$x | break\n               ^^^^^',
      'jq: error: break requires a label to break to at <top-level>, line 1, column 12:\n    label \$x | break\n               ^^^^^',
    ],
  ),
  (
    'break \$',
    [
      'jq: error: syntax error, unexpected \'\$\', expecting BINDING at <top-level>, line 1, column 7:\n    break \$\n          ^',
      'jq: error: break requires a label to break to at <top-level>, line 1, column 1:\n    break \$\n    ^^^^^^^',
    ],
  ),
  (
    '1 2 3',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 3:\n    1 2 3\n      ^',
    ],
  ),
  (
    ']]',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    ]]\n    ^',
    ],
  ),
  (
    '. as [\$a, {b: [\$c, }] | 1',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 20:\n    . as [\$a, {b: [\$c, }] | 1\n                       ^',
    ],
  ),
  (
    '{a: (1 +), b: [2 *], c: 3 +}',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 9:\n    {a: (1 +), b: [2 *], c: 3 +}\n            ^',
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 19:\n    {a: (1 +), b: [2 *], c: 3 +}\n                      ^',
      'jq: error: syntax error, unexpected \'}\' at <top-level>, line 1, column 28:\n    {a: (1 +), b: [2 *], c: 3 +}\n                               ^',
    ],
  ),
  (
    '1 # comment\n )',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 2, column 2:\n     )\n     ^',
    ],
  ),
  (
    '!1',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    !1\n    ^',
    ],
  ),
  (
    '1 ! 2',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 3:\n    1 ! 2\n      ^',
    ],
  ),
  (
    'a & b',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 3:\n    a & b\n      ^',
    ],
  ),
  (
    '`',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    `\n    ^',
    ],
  ),
  (
    '~1',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 1:\n    ~1\n    ^',
    ],
  ),
  (
    '1 \\ 2',
    [
      'jq: error: syntax error, unexpected INVALID_CHARACTER, expecting end of file at <top-level>, line 1, column 3:\n    1 \\ 2\n      ^',
    ],
  ),
  (
    '{(1 +): 2, (3 +): 4}',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 6:\n    {(1 +): 2, (3 +): 4}\n         ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {(1 +): 2, (3 +): 4}\n     ^^^^^',
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 16:\n    {(1 +): 2, (3 +): 4}\n                   ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 12:\n    {(1 +): 2, (3 +): 4}\n               ^^^^^',
    ],
  ),
  (
    '{a: 1, (2 +): 3, b}',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 12:\n    {a: 1, (2 +): 3, b}\n               ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 8:\n    {a: 1, (2 +): 3, b}\n           ^^^^^',
    ],
  ),
  (
    '{a: [1 +], b: 2 +}',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 9:\n    {a: [1 +], b: 2 +}\n            ^',
      'jq: error: syntax error, unexpected \'}\' at <top-level>, line 1, column 18:\n    {a: [1 +], b: 2 +}\n                     ^',
    ],
  ),
  (
    '((1 +) 2)',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 6:\n    ((1 +) 2)\n         ^',
    ],
  ),
  (
    '[(1 +) 2]',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 6:\n    [(1 +) 2]\n         ^',
    ],
  ),
  (
    '(1 2) 3',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 4:\n    (1 2) 3\n       ^',
    ],
  ),
  (
    '[1 2] 3',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 4:\n    [1 2] 3\n       ^',
    ],
  ),
  (
    '[[1 2] 3]',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 5:\n    [[1 2] 3]\n        ^',
    ],
  ),
  (
    '{a: [1 2]}',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 8:\n    {a: [1 2]}\n           ^',
    ],
  ),
  (
    '.[1 +] 3',
    [
      'jq: error: syntax error, unexpected \']\' at <top-level>, line 1, column 6:\n    .[1 +] 3\n         ^',
    ],
  ),
  (
    'if 1 then (2 +) else 3 end',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 15:\n    if 1 then (2 +) else 3 end\n                  ^',
    ],
  ),
  (
    'if 1 then 2 3 else 4 end',
    [
      'jq: error: syntax error, unexpected LITERAL at <top-level>, line 1, column 13:\n    if 1 then 2 3 else 4 end\n                ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2 3 else 4 end\n    ^^^^^^^^^^^^^',
    ],
  ),
  (
    'if 1 then 2 else 3 4 end',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end or \'|\' or \',\' at <top-level>, line 1, column 20:\n    if 1 then 2 else 3 4 end\n                       ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 1:\n    if 1 then 2 else 3 4 end\n    ^^^^^^^^^^^^^^^^^^^^',
    ],
  ),
  (
    'try (1 +) catch 2',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 9:\n    try (1 +) catch 2\n            ^',
    ],
  ),
  (
    'try 1 catch (2 +)',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 17:\n    try 1 catch (2 +)\n                    ^',
    ],
  ),
  (
    'try 1 catch 2 3',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 15:\n    try 1 catch 2 3\n                  ^',
    ],
  ),
  (
    '1 as [\$a \$b] | 2',
    [
      'jq: error: syntax error, unexpected BINDING, expecting \',\' or \']\' at <top-level>, line 1, column 10:\n    1 as [\$a \$b] | 2\n             ^^',
    ],
  ),
  (
    '1 as {a \$x} | 2',
    [
      'jq: error: syntax error, unexpected BINDING, expecting \':\' at <top-level>, line 1, column 9:\n    1 as {a \$x} | 2\n            ^^',
    ],
  ),
  (
    '1 as {a: \$x \$y} | 2',
    [
      'jq: error: syntax error, unexpected BINDING, expecting \',\' or \'}\' at <top-level>, line 1, column 13:\n    1 as {a: \$x \$y} | 2\n                ^^',
    ],
  ),
  (
    '. as {a: 1} | 2',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 10:\n    . as {a: 1} | 2\n             ^',
    ],
  ),
  (
    '. as {"a": 1} | 2',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting BINDING or \'[\' or \'{\' at <top-level>, line 1, column 12:\n    . as {"a": 1} | 2\n               ^',
    ],
  ),
  (
    '. as {("a")} | 2',
    [
      'jq: error: syntax error, unexpected \'}\', expecting \':\' at <top-level>, line 1, column 12:\n    . as {("a")} | 2\n               ^',
    ],
  ),
  (
    '. as [\$a, \$b ?// \$c] | 2',
    [
      'jq: error: syntax error, unexpected ?//, expecting \',\' or \']\' at <top-level>, line 1, column 14:\n    . as [\$a, \$b ?// \$c] | 2\n                 ^^^',
    ],
  ),
  (
    'reduce . as \$x (0; 1; 2; 3)',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 21:\n    reduce . as \$x (0; 1; 2; 3)\n                        ^',
    ],
  ),
  (
    'foreach . as \$x (0)',
    [
      'jq: error: syntax error, unexpected \')\', expecting \'|\' or \',\' or \';\' at <top-level>, line 1, column 19:\n    foreach . as \$x (0)\n                      ^',
    ],
  ),
  (
    'foreach . as \$x (0; 1; 2; 3)',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 25:\n    foreach . as \$x (0; 1; 2; 3)\n                            ^',
    ],
  ),
  (
    'foreach . as \$x (0; 1; 2) 3',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 27:\n    foreach . as \$x (0; 1; 2) 3\n                              ^',
    ],
  ),
  (
    'def f: 1 def g: 2; 3',
    [
      'jq: error: syntax error, unexpected def, expecting \'|\' or \',\' or \';\' at <top-level>, line 1, column 10:\n    def f: 1 def g: 2; 3\n             ^^^',
    ],
  ),
  (
    'def f(a: 1; 2',
    [
      'jq: error: syntax error, unexpected \':\', expecting \';\' or \')\' at <top-level>, line 1, column 8:\n    def f(a: 1; 2\n           ^',
    ],
  ),
  (
    'def f(\$a \$b): 1; 2',
    [
      'jq: error: syntax error, unexpected BINDING, expecting \';\' or \')\' at <top-level>, line 1, column 10:\n    def f(\$a \$b): 1; 2\n             ^^',
    ],
  ),
  (
    'def f(a;; b): 1; 2',
    [
      'jq: error: syntax error, unexpected \';\', expecting IDENT or BINDING at <top-level>, line 1, column 9:\n    def f(a;; b): 1; 2\n            ^',
    ],
  ),
  (
    'def 1: 2; 3',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting IDENT at <top-level>, line 1, column 5:\n    def 1: 2; 3\n        ^',
    ],
  ),
  (
    'def f: 1; def 2: 3; 4',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting IDENT at <top-level>, line 1, column 15:\n    def f: 1; def 2: 3; 4\n                  ^',
    ],
  ),
  (
    '1 | def f: 2; | 3',
    [
      'jq: error: syntax error, unexpected \'|\' at <top-level>, line 1, column 15:\n    1 | def f: 2; | 3\n                  ^',
    ],
  ),
  (
    'label |',
    [
      'jq: error: syntax error, unexpected \'|\', expecting BINDING at <top-level>, line 1, column 7:\n    label |\n          ^',
    ],
  ),
  (
    'break \$x \$y',
    [
      'jq: error: syntax error, unexpected BINDING, expecting end of file at <top-level>, line 1, column 10:\n    break \$x \$y\n             ^^',
    ],
  ),
  (
    '@base64 @base64',
    [
      'jq: error: syntax error, unexpected FORMAT, expecting end of file at <top-level>, line 1, column 9:\n    @base64 @base64\n            ^^^^^^^',
    ],
  ),
  (
    '@base64 "a" "b"',
    [
      'jq: error: syntax error, unexpected QQSTRING_START, expecting end of file at <top-level>, line 1, column 13:\n    @base64 "a" "b"\n                ^',
    ],
  ),
  (
    '. @base64',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_START at <top-level>, line 1, column 3:\n    . @base64\n      ^^^^^^^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 1:\n    . @base64\n    ^^^^^^^^^',
    ],
  ),
  (
    '{@base64}',
    [
      'jq: error: syntax error, unexpected \'}\', expecting QQSTRING_START at <top-level>, line 1, column 9:\n    {@base64}\n            ^',
    ],
  ),
  (
    '{@base64: 1}',
    [
      'jq: error: syntax error, unexpected \':\', expecting QQSTRING_START at <top-level>, line 1, column 9:\n    {@base64: 1}\n            ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {@base64: 1}\n     ^^^^^^^^',
    ],
  ),
  (
    '"a" @base64',
    [
      'jq: error: syntax error, unexpected FORMAT, expecting end of file at <top-level>, line 1, column 5:\n    "a" @base64\n        ^^^^^^^',
    ],
  ),
  (
    '"\\("\\(1")"',
    [
      'jq: error: syntax error, unexpected QQSTRING_START, expecting QQSTRING_INTERP_END or \'|\' or \',\' at <top-level>, line 1, column 8:\n    "\\("\\(1")"\n           ^',
    ],
  ),
  (
    '"\\(1 | )"',
    [
      'jq: error: syntax error, unexpected QQSTRING_INTERP_END at <top-level>, line 1, column 8:\n    "\\(1 | )"\n           ^',
    ],
  ),
  (
    '"\\("a" "b")"',
    [
      'jq: error: syntax error, unexpected QQSTRING_START, expecting QQSTRING_INTERP_END or \'|\' or \',\' at <top-level>, line 1, column 8:\n    "\\("a" "b")"\n           ^',
    ],
  ),
  (
    '"x" | "\\("',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 10:\n    "x" | "\\("\n             ^',
    ],
  ),
  (
    '. ..',
    [
      'jq: error: syntax error, unexpected .. at <top-level>, line 1, column 3:\n    . ..\n      ^^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 1:\n    . ..\n    ^^^^',
    ],
  ),
  (
    '.. .',
    [
      'jq: error: syntax error, unexpected end of file, expecting FORMAT or QQSTRING_START or \'[\' at <top-level>, line 1, column 4:\n    .. .\n       ^',
    ],
  ),
  (
    '.a."b',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 5:\n    .a."b\n        ^',
    ],
  ),
  (
    '.a."b" 1',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 8:\n    .a."b" 1\n           ^',
    ],
  ),
  (
    '\$x[1 2]',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting \'|\' or \',\' or \':\' or \']\' at <top-level>, line 1, column 6:\n    \$x[1 2]\n         ^',
    ],
  ),
  (
    '\$__loc__ \$__loc__',
    [
      'jq: error: syntax error, unexpected \$__loc__, expecting end of file at <top-level>, line 1, column 10:\n    \$__loc__ \$__loc__\n             ^^^^^^^^',
    ],
  ),
  (
    '{\$__loc__: 1}',
    [
      'jq: error: syntax error, unexpected \':\', expecting \'}\' at <top-level>, line 1, column 10:\n    {\$__loc__: 1}\n             ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {\$__loc__: 1}\n     ^^^^^^^^^',
    ],
  ),
  (
    '\$__loc__:',
    [
      'jq: error: syntax error, unexpected \':\', expecting end of file at <top-level>, line 1, column 9:\n    \$__loc__:\n            ^',
    ],
  ),
  (
    '- -',
    [
      'jq: error: syntax error, unexpected end of file at <top-level>, line 1, column 3:\n    - -\n      ^',
    ],
  ),
  (
    '-(1',
    [
      'jq: error: syntax error, unexpected end of file, expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 3:\n    -(1\n      ^',
    ],
  ),
  (
    '1 ? ? 2',
    [
      'jq: error: syntax error, unexpected LITERAL, expecting end of file at <top-level>, line 1, column 7:\n    1 ? ? 2\n          ^',
    ],
  ),
  (
    '? ? ?',
    [
      'jq: error: syntax error, unexpected \'?\', expecting end of file at <top-level>, line 1, column 1:\n    ? ? ?\n    ^',
    ],
  ),
  (
    '1 // // 2',
    [
      'jq: error: syntax error, unexpected // at <top-level>, line 1, column 6:\n    1 // // 2\n         ^^',
    ],
  ),
  (
    '1 //= 2 //= 3',
    [
      'jq: error: syntax error, unexpected //= at <top-level>, line 1, column 9:\n    1 //= 2 //= 3\n            ^^^',
    ],
  ),
  (
    '1 |= 2 |= 3',
    [
      'jq: error: syntax error, unexpected |= at <top-level>, line 1, column 8:\n    1 |= 2 |= 3\n           ^^',
    ],
  ),
  (
    '1 += 2 -= 3',
    [
      'jq: error: syntax error, unexpected -= at <top-level>, line 1, column 8:\n    1 += 2 -= 3\n           ^^',
    ],
  ),
  (
    '.a = .b |= .c',
    [
      'jq: error: syntax error, unexpected |= at <top-level>, line 1, column 9:\n    .a = .b |= .c\n            ^^',
    ],
  ),
  (
    'def f: 1; ; 2',
    [
      'jq: error: syntax error, unexpected \';\', expecting end of file at <top-level>, line 1, column 11:\n    def f: 1; ; 2\n              ^',
    ],
  ),
  (
    'def f: 1; 2; 3',
    [
      'jq: error: syntax error, unexpected \';\', expecting end of file at <top-level>, line 1, column 12:\n    def f: 1; 2; 3\n               ^',
    ],
  ),
  (
    'def f(a): a; f(1;)',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 18:\n    def f(a): a; f(1;)\n                     ^',
    ],
  ),
  (
    'def f(a): a; f(;1)',
    [
      'jq: error: syntax error, unexpected \';\' at <top-level>, line 1, column 16:\n    def f(a): a; f(;1)\n                   ^',
    ],
  ),
  (
    'def f(a): a; f()',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 16:\n    def f(a): a; f()\n                   ^',
    ],
  ),
  (
    'f(1;;2)',
    [
      'jq: error: syntax error, unexpected \';\' at <top-level>, line 1, column 5:\n    f(1;;2)\n        ^',
    ],
  ),
  (
    'f(1; 2; )',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 9:\n    f(1; 2; )\n            ^',
    ],
  ),
  (
    'f((1; 2))',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \')\' at <top-level>, line 1, column 5:\n    f((1; 2))\n        ^',
    ],
  ),
  (
    'f([1; 2])',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'|\' or \',\' or \']\' at <top-level>, line 1, column 5:\n    f([1; 2])\n        ^',
    ],
  ),
  (
    'f({a: 1; b: 2})',
    [
      'jq: error: syntax error, unexpected \';\', expecting \'}\' at <top-level>, line 1, column 8:\n    f({a: 1; b: 2})\n           ^',
      'jq: error: May need parentheses around object key expression at <top-level>, line 1, column 4:\n    f({a: 1; b: 2})\n       ^^^^^^^',
    ],
  ),
  (
    'f(1 as \$x)',
    [
      'jq: error: syntax error, unexpected \')\', expecting \'|\' at <top-level>, line 1, column 10:\n    f(1 as \$x)\n             ^',
    ],
  ),
  (
    'f(if 1 then 2)',
    [
      'jq: error: syntax error, unexpected \')\' at <top-level>, line 1, column 14:\n    f(if 1 then 2)\n                 ^',
      'jq: error: Possibly unterminated \'if\' statement at <top-level>, line 1, column 3:\n    f(if 1 then 2)\n      ^^^^^^^^^^^^',
    ],
  ),
  (
    'f(reduce . as \$x (0; 1)',
    [
      'jq: error: syntax error, unexpected end of file, expecting \';\' or \')\' at <top-level>, line 1, column 23:\n    f(reduce . as \$x (0; 1)\n                          ^',
    ],
  ),
  (
    'f(reduce . as \$x (0; 1)) g',
    [
      'jq: error: syntax error, unexpected IDENT, expecting end of file at <top-level>, line 1, column 26:\n    f(reduce . as \$x (0; 1)) g\n                             ^',
    ],
  ),
  (
    '{a:1,,}',
    [
      'jq: error: syntax error, unexpected \',\' at <top-level>, line 1, column 6:\n    {a:1,,}\n         ^',
    ],
  ),
  (
    '."a',
    [
      'jq: error: syntax error, unexpected end of file, expecting QQSTRING_TEXT or QQSTRING_INTERP_START or QQSTRING_END at <top-level>, line 1, column 3:\n    ."a\n      ^',
      'jq: error: try .["field"] instead of .field for unusually named fields at <top-level>, line 1, column 1:\n    ."a\n    ^^^',
    ],
  ),
  (
    '{"x"*0}',
    [
      'jq: error: syntax error, unexpected \'*\', expecting \'}\' at <top-level>, line 1, column 5:\n    {"x"*0}\n        ^',
    ],
  ),
  (
    '{(["ééééééééééééééééééééé"]): 1}',
    [
      'jq: error: Cannot use array (["ééééééééééé...]) as object key at <top-level>, line 1, column 3:\n    {(["ééééééééééééééééééééé"]): 1}\n      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^',
    ],
  ),
];

/// Programs jq's parser accepts. jq itself may still reject them later with
/// a semantic error (an undefined name, a missing module, a missing main
/// program) or at run time; those later checks belong to the compiler.
const List<String> jqParseAcceptedSnapshots = [
  'def f(a; \$b): a; f(1)',
  'break \$x',
  '"a\\(1)b"',
  '{("a"+1):3}',
  '{(.a):1}',
  '{("a"):1}',
  '{if:1, then:2}',
  '{if}',
  '{\$x}',
  '{\$__loc__}',
  '1 // 2 // 3',
  '1 = 2 // 3',
  '1 ?',
  '\$\$\$\$x',
  'a::b',
  '1 as \$a::b | 1',
  'import "a" as b;',
  'import "a" as \$b; 1',
  'include "a" {};',
  'module {a:1}; 0',
  'import "a" as b {}; .',
  '.a[ ]',
  '@base64 "x\\(1)"',
  '{@base64 "a": 1}',
  '{"a\\(1)": 1}',
  '{"a": 1, "b"}',
  '{a: 1 | 2}',
  '{a: 1, b: 2 | 3, c}',
  '.a."b"',
  '.a."b"?',
  '."a"',
  '."a\\(1)"?',
  '.a.[1]',
  '.a.[]',
  '.a.[1]?',
  '.a.[]?',
  '.. | .a?',
  '. as [\$a, [\$b, {c: \$d}]] ?// {e: \$f} | \$a',
  '. as {\$a, \$b: [\$c]} | 1',
  '. as {("a"): \$x} | 1',
  '. as {"a": \$x} | 1',
  '. as {if: \$x} | 1',
  '. as {a: \$x, b: \$y} ?// [\$x, \$y] | 1',
  'reduce range(3) as \$x (0; . + \$x)',
  'foreach range(3) as \$x (0; . + \$x; [\$x, .])',
  '1 as \$x | 2 as \$y | [\$x, \$y]',
  'def f(g): g | g; def h(\$x): \$x; f(h(1))',
  'if . then 1 elif . then 2 elif . then 3 else 4 end',
  'label \$f | 1, break \$f',
  'try (try error catch .) catch .',
  '.a? // .b?',
  '-1 | -(.a)',
  '- - 1',
  '-.a',
  '1 as \$x | -\$x',
  'def f: def g: 1; g; f',
  'def f: def g: 1; g;',
  'def f: 1; def g: 2;',
  '[1] [2]',
  '.a .b',
  '\$x.a',
  '\$x[0]',
  '\$x?',
  '1 ? ?',
  '.?',
  '.a??',
  '.[]??',
  '..?',
  '.a?.b?[]?',
  '1 as [\$a] | 2',
  '1 as [[\$a]] | 2',
  '1 as {a: [\$a]} | 2',
  '1 as {a: {b: \$b}} | 2',
  '{("a", "b"): 1}',
  '{(0,1): 2}',
  '{([]|length): 1}',
  '{("a"+"b"): 1}',
  '{(1+"a"): 1}',
  '{(-1): 1}',
  '{("x"*0): 1}',
  '{([1,(2,3)]): 1}',
  'reduce . as [\$a, \$b] (0; .)',
  'import "a" as foo; import "b" as \$bar; include "c"; .',
  '...a',
  '..[]',
  '..[0]',
  '. []',
  '.. []',
  '\$__loc__.file',
  '-\$__loc__',
  '--1',
  '1 - -1',
  '1 -- 1',
  '1 --1',
  '1 ?? ??',
  '.a ? .b',
  '1 //= 2 // 3',
  '1 // 2 //= 3',
  '1 = 2 == 3',
  '1 == 2 = 3',
  '1 and 2 = 3',
  '1 = 2 and 3',
  '1 < 2 = 3',
  '.a |= (.b |= 1)',
  '1 , 2 | 3 , 4',
  '1 | 2 , 3 | 4',
  '1 as \$x | \$x as \$y | \$y',
  '1 as \$x | 2 , 3 as \$y | 4',
  '(1 as \$x | \$x) , 2',
  '1 , (2 as \$x | 3 | \$x)',
  'def f: 1; def g: f; g',
  'def f: 1;',
  '[f(1; 2)]',
  '{a: f(1; 2)}',
  'f(def g: 1; g)',
  'f(label \$x | 1)',
  'f(1 as \$x | \$x)',
  'f(reduce . as \$x (0; 1))',
  '{a:1,}',
  '. "a"',
  '[.[]?]',
  '.a?.b?',
  '[.[] | select(. > 1)] | length',
  '1 as [\$a] ?// \$a | \$a',
  'try error("x") catch .',
  'def f(x): x; f(.)',
  '{a:1} | .a as \$x | {\$x}',
  '-1 as \$x | \$x',
  'reduce . as \$x (0; . + 1) | -.',
];
