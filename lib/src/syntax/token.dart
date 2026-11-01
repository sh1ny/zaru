import 'span.dart';

/// jq's grammar terminals.
///
/// The declaration order is the order of pinned jq's Bison symbol numbers,
/// because Bison lists expected tokens in that order. [label] is the name
/// Bison prints in `syntax error, unexpected X, expecting Y` messages, after
/// `yytnamerr` strips the quotes from string-aliased tokens.
enum TokenKind {
  eof('end of file'),
  invalidCharacter('INVALID_CHARACTER'),
  ident('IDENT'),
  field('FIELD'),
  binding('BINDING'),
  literal('LITERAL'),
  format('FORMAT'),
  recurse('..'),
  setMod('%='),
  eq('=='),
  neq('!='),
  definedOr('//'),
  asKeyword('as'),
  defKeyword('def'),
  moduleKeyword('module'),
  importKeyword('import'),
  includeKeyword('include'),
  ifKeyword('if'),
  thenKeyword('then'),
  elseKeyword('else'),
  elifKeyword('elif'),
  reduceKeyword('reduce'),
  foreachKeyword('foreach'),
  endKeyword('end'),
  andKeyword('and'),
  orKeyword('or'),
  tryKeyword('try'),
  catchKeyword('catch'),
  labelKeyword('label'),
  breakKeyword('break'),
  loc(r'$__loc__'),
  setPipe('|='),
  setPlus('+='),
  setMinus('-='),
  setMult('*='),
  setDiv('/='),
  setDefinedOr('//='),
  lessEq('<='),
  greaterEq('>='),
  alternation('?//'),
  stringStart('QQSTRING_START'),
  stringText('QQSTRING_TEXT'),
  interpStart('QQSTRING_INTERP_START'),
  interpEnd('QQSTRING_INTERP_END'),
  stringEnd('QQSTRING_END'),
  pipe("'|'"),
  comma("','"),
  assign("'='"),
  less("'<'"),
  greater("'>'"),
  plus("'+'"),
  minus("'-'"),
  star("'*'"),
  slash("'/'"),
  percent("'%'"),
  question("'?'"),
  dot("'.'"),
  leftBracket("'['"),
  semicolon("';'"),
  colon("':'"),
  leftParen("'('"),
  rightParen("')'"),
  rightBracket("']'"),
  leftBrace("'{'"),
  rightBrace("'}'"),
  dollar(r"'$'");

  const TokenKind(this.label);

  /// Bison's display name for this terminal.
  final String label;

  /// Whether this terminal is one of jq's reserved words.
  bool get isKeyword => index >= asKeyword.index && index <= breakKeyword.index;
}

/// The reserved words that grammar `Keyword` accepts as object keys, in
/// jq's `Keyword` production order.
const Set<TokenKind> keywordKeyKinds = {
  TokenKind.asKeyword,
  TokenKind.defKeyword,
  TokenKind.moduleKeyword,
  TokenKind.importKeyword,
  TokenKind.includeKeyword,
  TokenKind.ifKeyword,
  TokenKind.thenKeyword,
  TokenKind.elseKeyword,
  TokenKind.elifKeyword,
  TokenKind.reduceKeyword,
  TokenKind.foreachKeyword,
  TokenKind.endKeyword,
  TokenKind.andKeyword,
  TokenKind.orKeyword,
  TokenKind.tryKeyword,
  TokenKind.catchKeyword,
  TokenKind.labelKeyword,
  TokenKind.breakKeyword,
};

/// A lexical token with its UTF-8 byte [span].
final class Token {
  const Token(this.kind, this.span, {this.text = '', this.value});

  final TokenKind kind;
  final Span span;

  /// Lexeme text for IDENT, FIELD (without `.`), BINDING (without `$`),
  /// LITERAL (original source digits) and FORMAT (without `@`).
  final String text;

  /// Decoded content of a QQSTRING_TEXT token; `null` when the escape
  /// sequence was invalid (a lexical diagnostic was reported).
  final String? value;

  @override
  String toString() => 'Token($kind, $span${text.isEmpty ? '' : ', $text'})';
}
