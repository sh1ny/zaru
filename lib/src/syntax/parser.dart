import '../value.dart';
import 'ast.dart';
import 'ast_depth.dart';
import 'constants.dart';
import 'diagnostic.dart';
import 'lexer.dart';
import 'parse_result.dart';
import 'source_text.dart';
import 'span.dart';
import 'token.dart';

/// Parses one jq program. [name] is how diagnostics name the source.
///
/// The parser is a hand-written precedence-climbing / recursive-descent
/// reading of pinned jq 1.8.2's `parser.y`. It does not stop at the first
/// error: it reproduces Bison's error recovery (the `error` productions, the
/// three-shift suppression window and EOF abort) so the ordered diagnostics
/// match jq's. See `docs/compat.md` for the supported subset.
/// The deepest syntax nesting the parser accepts.
///
/// Pinned jq runs out of Bison stack ("memory exhausted") at 10000 nested
/// parentheses or 5000 pipe steps. zaru bounds the depth far lower because
/// parsing and lowering recurse on the host stack, which is small in
/// browsers, and dart2wasm hangs instead of raising a stack overflow. The
/// value is measured: the worst shape (nested string interpolation) parses,
/// lowers and runs up to about 400 levels on dart2wasm, 600 to 800 on
/// dart2js and 800 to 1000 on the VM, so 256 leaves headroom on all three,
/// and every pinned fixture program is at most 12 levels deep.
///
/// A program is `k` levels deep when its syntax tree has height `k`: `((.))`
/// is 3 levels, and so are `.|.|.`, `.,.,.` and `.a.b`. Anything deeper is
/// rejected with a typed [DiagnosticKind.limit] diagnostic, never a host
/// stack overflow. See `docs/compat.md`.
const int maxSyntaxDepth = 256;

/// The message of the diagnostic raised when [maxSyntaxDepth] is exceeded.
const String syntaxDepthMessage =
    'program nests deeper than $maxSyntaxDepth levels';

ParseResult parseProgram(String source, {String name = '<top-level>'}) =>
    _Parser(SourceText(source, name: name)).run();

/// Thrown when the parser gives up, like Bison's `YYABORT` after the stack
/// has no state that can shift `error`.
final class _Abort implements Exception {
  const _Abort();
}

/// A syntax error in flight. It unwinds to the innermost construct that has
/// a recovery production, just as Bison pops states until one shifts `error`.
final class _Signal implements Exception {
  const _Signal(this.start, this.end);

  /// The offending token's span: `yylloc` at the time of the error.
  final int start;
  final int end;
}

/// The syntax depth budget was exhausted. Unlike [_Signal] it is not a
/// recoverable syntax error: it unwinds the whole parse.
final class _TooDeep implements Exception {
  const _TooDeep(this.span);

  final Span span;
}

/// Where a recovery region began: the shift count (to know whether any
/// symbol was pushed above the recovery state) and the byte offset of its
/// first token.
final class _Mark {
  const _Mark(this.shifts, this.start);

  final int shifts;
  final int start;
}

/// Tokens that can follow a complete term in some LALR(1) lookahead set.
/// After `.` any other token enters the `'.' error` recovery production.
const Set<TokenKind> _termFollow = {
  TokenKind.eof,
  TokenKind.field,
  TokenKind.setMod,
  TokenKind.eq,
  TokenKind.neq,
  TokenKind.definedOr,
  TokenKind.asKeyword,
  TokenKind.thenKeyword,
  TokenKind.elseKeyword,
  TokenKind.elifKeyword,
  TokenKind.endKeyword,
  TokenKind.andKeyword,
  TokenKind.orKeyword,
  TokenKind.catchKeyword,
  TokenKind.setPipe,
  TokenKind.setPlus,
  TokenKind.setMinus,
  TokenKind.setMult,
  TokenKind.setDiv,
  TokenKind.setDefinedOr,
  TokenKind.lessEq,
  TokenKind.greaterEq,
  TokenKind.alternation,
  TokenKind.interpEnd,
  TokenKind.pipe,
  TokenKind.comma,
  TokenKind.assign,
  TokenKind.less,
  TokenKind.greater,
  TokenKind.plus,
  TokenKind.minus,
  TokenKind.star,
  TokenKind.slash,
  TokenKind.percent,
  TokenKind.question,
  TokenKind.dot,
  TokenKind.leftBracket,
  TokenKind.semicolon,
  TokenKind.colon,
  TokenKind.rightParen,
  TokenKind.rightBracket,
  TokenKind.rightBrace,
};

/// Tokens that begin a Term.
const Set<TokenKind> _termStart = {
  TokenKind.dot,
  TokenKind.recurse,
  TokenKind.breakKeyword,
  TokenKind.field,
  TokenKind.literal,
  TokenKind.format,
  TokenKind.stringStart,
  TokenKind.minus,
  TokenKind.leftParen,
  TokenKind.leftBracket,
  TokenKind.leftBrace,
  TokenKind.reduceKeyword,
  TokenKind.foreachKeyword,
  TokenKind.ifKeyword,
  TokenKind.tryKeyword,
  TokenKind.dollar,
  TokenKind.binding,
  TokenKind.loc,
  TokenKind.ident,
};

enum _Assoc { left, right, none }

final class _Operator {
  const _Operator(this.level, this.assoc);

  final int level;
  final _Assoc assoc;
}

const _Operator _alternativeOp = _Operator(3, _Assoc.right);
const _Operator _assignOp = _Operator(4, _Assoc.none);
const _Operator _orOp = _Operator(5, _Assoc.left);
const _Operator _andOp = _Operator(6, _Assoc.left);
const _Operator _compareOp = _Operator(7, _Assoc.none);
const _Operator _additiveOp = _Operator(8, _Assoc.left);
const _Operator _multiplicativeOp = _Operator(9, _Assoc.left);

_Operator? _operatorOf(TokenKind kind) => switch (kind) {
  TokenKind.definedOr => _alternativeOp,
  TokenKind.assign ||
  TokenKind.setPipe ||
  TokenKind.setPlus ||
  TokenKind.setMinus ||
  TokenKind.setMult ||
  TokenKind.setDiv ||
  TokenKind.setMod ||
  TokenKind.setDefinedOr => _assignOp,
  TokenKind.orKeyword => _orOp,
  TokenKind.andKeyword => _andOp,
  TokenKind.eq ||
  TokenKind.neq ||
  TokenKind.less ||
  TokenKind.greater ||
  TokenKind.lessEq ||
  TokenKind.greaterEq => _compareOp,
  TokenKind.plus || TokenKind.minus => _additiveOp,
  TokenKind.star || TokenKind.slash || TokenKind.percent => _multiplicativeOp,
  _ => null,
};

BinaryOperator? _binaryOperator(TokenKind kind) => switch (kind) {
  TokenKind.plus => BinaryOperator.add,
  TokenKind.minus => BinaryOperator.subtract,
  TokenKind.star => BinaryOperator.multiply,
  TokenKind.slash => BinaryOperator.divide,
  TokenKind.percent => BinaryOperator.modulo,
  TokenKind.eq => BinaryOperator.equal,
  TokenKind.neq => BinaryOperator.notEqual,
  TokenKind.less => BinaryOperator.less,
  TokenKind.greater => BinaryOperator.greater,
  TokenKind.lessEq => BinaryOperator.lessOrEqual,
  TokenKind.greaterEq => BinaryOperator.greaterOrEqual,
  _ => null,
};

AssignOperator? _assignOperator(TokenKind kind) => switch (kind) {
  TokenKind.assign => AssignOperator.assign,
  TokenKind.setPipe => AssignOperator.update,
  TokenKind.setPlus => AssignOperator.add,
  TokenKind.setMinus => AssignOperator.subtract,
  TokenKind.setMult => AssignOperator.multiply,
  TokenKind.setDiv => AssignOperator.divide,
  TokenKind.setMod => AssignOperator.modulo,
  TokenKind.setDefinedOr => AssignOperator.alternative,
  _ => null,
};

const List<TokenKind> _pipeComma = [TokenKind.pipe, TokenKind.comma];

final class _Parser {
  _Parser(this.source) {
    _lexer = Lexer(source, _diagnostics.add);
  }

  final SourceText source;
  late final Lexer _lexer;
  final List<Diagnostic> _diagnostics = [];
  final List<UnsupportedConstruct> _unsupported = [];

  Token? _look;

  /// Bison's `yyerrstatus`: 0 outside recovery; 3 right after an error; each
  /// shifted token counts down. Errors are only reported at 0.
  int _errStatus = 0;

  /// Number of tokens shifted so far.
  int _shifts = 0;

  /// Current nesting depth; at most [maxSyntaxDepth].
  int _depth = 0;

  /// End offset of the most recently shifted token.
  int _lastEnd = 0;

  // -------------------------------------------------------------------------
  // Token access

  /// The lookahead, lexed lazily so diagnostics keep Bison's order.
  Token get look => _look ??= _lexer.next();

  _Mark _mark() => _Mark(_shifts, look.span.start);

  Token _shift() {
    final token = look;
    _look = null;
    _shifts++;
    _lastEnd = token.span.end;
    if (_errStatus > 0) _errStatus--;
    return token;
  }

  /// Runs [parse] one nesting level deeper, or abandons the parse when that
  /// would pass [maxSyntaxDepth]. Every construct that can recurse without
  /// bound (the right-recursive chains and everything that opens a bracket)
  /// goes through here, so the host stack stays proportional to the budget.
  T _nest<T>(T Function() parse) {
    if (_depth >= maxSyntaxDepth) throw _TooDeep(look.span);
    _depth++;
    try {
      return parse();
    } finally {
      _depth--;
    }
  }

  // -------------------------------------------------------------------------
  // Diagnostics and recovery

  void _fail(DiagnosticKind kind, String message, Span span) {
    _diagnostics.add(Diagnostic(kind, message, span));
  }

  void _unsupportedConstruct(
    UnsupportedKind kind,
    Span span, [
    String? detail,
  ]) {
    _unsupported.add(UnsupportedConstruct(kind, span, detail));
  }

  static String _message(Token token, List<TokenKind>? expected) {
    final buffer = StringBuffer('syntax error, unexpected ${token.kind.label}');
    if (expected != null) {
      final sorted = expected.toSet().toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      // Bison names at most four expected tokens; more means none are listed.
      if (sorted.isNotEmpty && sorted.length <= 4) {
        buffer.write(', expecting ${sorted.map((k) => k.label).join(' or ')}');
      }
    }
    return buffer.toString();
  }

  /// Detects a syntax error at the lookahead: reports it unless a recent
  /// recovery is still suppressing messages, and returns the signal that
  /// unwinds to a recovery point. [expected] is the token list Bison would
  /// print in the state that detects this error, or `null` when it is too
  /// long to print.
  _Signal _unexpected(List<TokenKind>? expected) {
    final token = look;
    if (_errStatus == 0) {
      _fail(DiagnosticKind.syntax, _message(token, expected), token.span);
    } else if (_errStatus == 3) {
      // Right after an error the offending token is thrown away; at the end
      // of input there is nothing left to recover with.
      if (token.kind == TokenKind.eof) throw const _Abort();
      _look = null;
    }
    _errStatus = 3;
    return _Signal(token.span.start, token.span.end);
  }

  /// Shifts a token of [kind], or raises the error Bison reports with
  /// [expected].
  Token _expect(TokenKind kind, [List<TokenKind>? expected]) {
    if (look.kind != kind) throw _unexpected(expected ?? [kind]);
    return _shift();
  }

  /// Pops to a recovery state that shifts `error` and then discards tokens
  /// until one in [accept] arrives. Returns the span Bison gives the `error`
  /// symbol: from the first popped symbol (or the offending token) to the
  /// last discarded one.
  Span _recover(_Signal signal, _Mark mark, Set<TokenKind> accept) {
    final start = _shifts > mark.shifts ? mark.start : signal.start;
    var end = signal.end;
    while (true) {
      final token = look;
      if (accept.contains(token.kind)) return Span(start, end);
      if (token.kind == TokenKind.eof) throw const _Abort();
      _look = null;
      end = token.span.end;
    }
  }

  // -------------------------------------------------------------------------
  // Entry point

  ParseResult run() {
    Program? program;
    try {
      program = _topLevel();
      if (_diagnostics.isEmpty) {
        // Left-leaning chains (`.,.,.`, `1+1+1`, `.a.b.c`) add depth without
        // parser recursion, but lowering recurses over the tree they build.
        final deep = firstNodeBeyondDepth(program, maxSyntaxDepth);
        if (deep != null) throw _TooDeep(Span(deep.start, deep.start + 1));
      }
    } on _Abort {
      program = null;
    } on _Signal {
      program = null;
    } on _TooDeep catch (tooDeep) {
      _fail(DiagnosticKind.limit, syntaxDepthMessage, tooDeep.span);
      program = null;
    }
    return ParseResult(
      source: source,
      program: _diagnostics.isEmpty ? program : null,
      diagnostics: _diagnostics,
      unsupported: _unsupported,
    );
  }

  Program _topLevel() {
    final startOffset = look.span.start;
    ModuleDirective? module;
    if (look.kind == TokenKind.moduleKeyword) {
      final start = _shift();
      final metadata = _query();
      _expect(TokenKind.semicolon, [
        TokenKind.pipe,
        TokenKind.comma,
        TokenKind.semicolon,
      ]);
      _checkMetadata(metadata);
      final span = Span(start.span.start, _lastEnd);
      module = ModuleDirective(span, metadata);
      _unsupportedConstruct(UnsupportedKind.moduleDirective, span);
    }
    final imports = <ImportDirective>[];
    while (look.kind == TokenKind.importKeyword ||
        look.kind == TokenKind.includeKeyword) {
      imports.add(_import());
    }

    Node? body;
    var definitions = <FunctionDefinition>[];
    if (look.kind == TokenKind.eof) {
      // An empty program (or only directives).
    } else if (look.kind == TokenKind.defKeyword) {
      final leading = <FunctionDefinition>[];
      while (look.kind == TokenKind.defKeyword) {
        leading.add(_functionDefinition());
      }
      if (look.kind == TokenKind.eof) {
        definitions = leading;
      } else if (_termStart.contains(look.kind) ||
          look.kind == TokenKind.labelKeyword) {
        var rest = _query();
        for (final definition in leading.reversed) {
          rest = DefineIn(
            Span(definition.span.start, rest.span.end),
            definition,
            rest,
          );
        }
        body = rest;
      } else {
        // Bison reduces FuncDefs by default, so the error is found at the
        // accept state.
        throw _unexpected([TokenKind.eof]);
      }
    } else if (_termStart.contains(look.kind) ||
        look.kind == TokenKind.labelKeyword) {
      body = _query();
    } else {
      throw _unexpected([TokenKind.eof]);
    }
    if (look.kind != TokenKind.eof) throw _unexpected([TokenKind.eof]);
    return Program(
      span: Span(startOffset, look.span.end),
      module: module,
      imports: imports,
      definitions: definitions,
      body: body,
    );
  }

  void _checkMetadata(Node metadata) {
    final value = constantOf(metadata);
    if (identical(value, notConstant)) {
      _fail(
        DiagnosticKind.semantic,
        'Module metadata must be constant',
        metadata.span,
      );
    } else if (value is! JqObject) {
      _fail(
        DiagnosticKind.semantic,
        'Module metadata must be an object',
        metadata.span,
      );
    }
  }

  ImportDirective _import() {
    final start = _shift();
    final isInclude = start.kind == TokenKind.includeKeyword;
    final path = _importFrom();
    String? alias;
    var isData = false;
    if (!isInclude) {
      _expect(TokenKind.asKeyword);
      if (look.kind == TokenKind.binding) {
        isData = true;
      } else if (look.kind != TokenKind.ident) {
        throw _unexpected([TokenKind.ident, TokenKind.binding]);
      }
      alias = _shift().text;
    }
    Node? metadata;
    if (look.kind != TokenKind.semicolon) {
      metadata = _query();
    }
    _expect(
      TokenKind.semicolon,
      metadata == null
          ? null
          : [TokenKind.pipe, TokenKind.comma, TokenKind.semicolon],
    );
    if (metadata != null) _checkMetadata(metadata);
    final span = Span(start.span.start, _lastEnd);
    _unsupportedConstruct(
      isInclude
          ? UnsupportedKind.includeDirective
          : UnsupportedKind.importDirective,
      span,
    );
    return ImportDirective(
      span,
      path,
      alias: alias,
      isData: isData,
      isInclude: isInclude,
      metadata: metadata,
    );
  }

  StringLiteral _importFrom() {
    if (look.kind != TokenKind.format && look.kind != TokenKind.stringStart) {
      throw _unexpected([TokenKind.format, TokenKind.stringStart]);
    }
    final string = _string();
    if (!string.isConstant) {
      _fail(
        DiagnosticKind.semantic,
        'Import path must be constant',
        string.span,
      );
    }
    return string;
  }

  // -------------------------------------------------------------------------
  // Queries

  /// Query: pipes and commas over [_queryPrimary] items.
  ///
  /// Comma binds tighter than pipe, and `|` is right-associative. Both chains
  /// are read with loops, so a long chain is wide rather than deep: it uses no
  /// host recursion and no syntax depth (an intentional improvement on jq's
  /// right-recursive grammar). The pipe tree is still built right-nested.
  Node _query() {
    final stages = <Node>[];
    while (true) {
      var stage = _queryPrimary();
      while (look.kind == TokenKind.comma) {
        _shift();
        final right = _queryPrimary();
        stage = Comma(_cover(stage, right), stage, right);
      }
      if (look.kind != TokenKind.pipe) {
        return _pipeChain(stages, stage);
      }
      _shift();
      stages.add(stage);
    }
  }

  /// `stages[0] | stages[1] | ... | last`, nested to the right.
  Node _pipeChain(List<Node> stages, Node last) {
    var result = last;
    for (var i = stages.length - 1; i >= 0; i--) {
      result = Pipe(_cover(stages[i], result), stages[i], result);
    }
    return result;
  }

  Span _cover(Node a, Node b) => Span(a.span.start, b.span.end);

  /// The query forms that swallow everything to their right, or an Expr.
  Node _queryPrimary() {
    switch (look.kind) {
      case TokenKind.defKeyword:
        final definition = _functionDefinition();
        final rest = _nest(_query);
        return DefineIn(
          Span(definition.span.start, rest.span.end),
          definition,
          rest,
        );
      case TokenKind.labelKeyword:
        final start = _shift();
        final name = _expect(TokenKind.binding).text;
        _expect(TokenKind.pipe);
        final body = _nest(_query);
        return Label(Span(start.span.start, body.span.end), name, body);
      default:
        final expression = _expr(0);
        if (look.kind != TokenKind.asKeyword) return expression;
        _shift();
        final patterns = _patterns(TokenKind.pipe);
        _expect(TokenKind.pipe);
        final body = _nest(_query);
        return Bind(_cover(expression, body), expression, patterns, body);
    }
  }

  FunctionDefinition _functionDefinition() {
    final start = _shift();
    final name = _expect(TokenKind.ident).text;
    final parameters = <Parameter>[];
    if (look.kind == TokenKind.leftParen) {
      _shift();
      while (true) {
        final token = look;
        if (token.kind != TokenKind.ident && token.kind != TokenKind.binding) {
          throw _unexpected([TokenKind.ident, TokenKind.binding]);
        }
        _shift();
        parameters.add(
          Parameter(
            token.span,
            token.text,
            isValue: token.kind == TokenKind.binding,
          ),
        );
        if (look.kind == TokenKind.semicolon) {
          _shift();
          continue;
        }
        _expect(TokenKind.rightParen, [
          TokenKind.semicolon,
          TokenKind.rightParen,
        ]);
        break;
      }
      _expect(TokenKind.colon);
    } else if (look.kind == TokenKind.colon) {
      _shift();
    } else {
      throw _unexpected([TokenKind.colon, TokenKind.leftParen]);
    }
    final body = _nest(_query);
    _expect(TokenKind.semicolon, [
      TokenKind.pipe,
      TokenKind.comma,
      TokenKind.semicolon,
    ]);
    return FunctionDefinition(
      Span(start.span.start, _lastEnd),
      name,
      parameters,
      body,
    );
  }

  // -------------------------------------------------------------------------
  // Expressions

  /// Expr: binary operators over terms, by precedence climbing. The
  /// non-associative groups (assignments, comparisons) reject a second
  /// operator of the same group.
  Node _expr(int minLevel) {
    var left = _term();
    int? lastNonAssociative;
    while (true) {
      final kind = look.kind;
      final operator = _operatorOf(kind);
      if (operator == null || operator.level < minLevel) return left;
      if (operator.assoc == _Assoc.none &&
          lastNonAssociative == operator.level) {
        throw _unexpected(null);
      }
      final token = _shift();
      final right = _nest(
        () => _expr(
          operator.assoc == _Assoc.right ? operator.level : operator.level + 1,
        ),
      );
      final span = _cover(left, right);
      final assign = _assignOperator(kind);
      left = switch (kind) {
        TokenKind.definedOr => Alternative(span, left, right),
        TokenKind.orKeyword => Or(span, left, right),
        TokenKind.andKeyword => And(span, left, right),
        _ when assign != null => _assignment(token, span, assign, left, right),
        _ => Binary(span, _binaryOperator(kind)!, left, right),
      };
      lastNonAssociative = operator.assoc == _Assoc.none
          ? operator.level
          : null;
    }
  }

  Node _assignment(
    Token token,
    Span span,
    AssignOperator operator,
    Node left,
    Node right,
  ) {
    _unsupportedConstruct(
      UnsupportedKind.assignment,
      token.span,
      operator.symbol,
    );
    return Assign(span, operator, left, right);
  }

  // -------------------------------------------------------------------------
  // Terms

  Node _term() {
    var node = _primary();
    while (true) {
      switch (look.kind) {
        case TokenKind.field:
          final token = _shift();
          node = _fieldIndex(node, token);
        case TokenKind.dot:
          _shift();
          node = _dottedPostfix(node);
        case TokenKind.leftBracket:
          node = _bracketPostfix(node, dotted: false);
        case TokenKind.question:
          final token = _shift();
          node = Try(
            Span(node.span.start, token.span.end),
            node,
            null,
            postfix: true,
          );
        default:
          return node;
      }
    }
  }

  Node _fieldIndex(Node target, Token field) {
    _noteQualified(field.text, field.span);
    final key = StringLiteral(field.span, [TextPart(field.text)]);
    var end = field.span.end;
    var optional = false;
    if (look.kind == TokenKind.question) {
      end = _shift().span.end;
      optional = true;
    }
    return Index(Span(target.span.start, end), target, key, optional: optional);
  }

  /// After `Term '.'`: a string key or a bracket form.
  Node _dottedPostfix(Node target) {
    switch (look.kind) {
      case TokenKind.format:
      case TokenKind.stringStart:
        // Unlike `_dot`, no enclosing primary counts this string's nesting.
        final key = _nest(_string);
        var end = key.span.end;
        var optional = false;
        if (look.kind == TokenKind.question) {
          end = _shift().span.end;
          optional = true;
        }
        return Index(
          Span(target.span.start, end),
          target,
          key,
          optional: optional,
        );
      case TokenKind.leftBracket:
        return _bracketPostfix(target, dotted: true);
      default:
        throw _unexpected([
          TokenKind.format,
          TokenKind.stringStart,
          TokenKind.leftBracket,
        ]);
    }
  }

  /// `Term '[' ... ']' ['?']`, with `Term '[' error ']'` recovery for the
  /// undotted form. The dotted form has no slice and no recovery production.
  Node _bracketPostfix(Node target, {required bool dotted}) {
    _shift();
    final mark = _mark();
    Node build() {
      Node? from;
      Node? to;
      var isSlice = false;
      var iterate = false;
      if (look.kind == TokenKind.rightBracket) {
        iterate = true;
      } else if (look.kind == TokenKind.colon && !dotted) {
        _shift();
        isSlice = true;
        to = _query();
      } else {
        from = _query();
        if (look.kind == TokenKind.colon && !dotted) {
          _shift();
          isSlice = true;
          if (look.kind != TokenKind.rightBracket) to = _query();
        }
      }
      _expect(TokenKind.rightBracket, [
        ..._pipeComma,
        if (!dotted && !isSlice && !iterate) TokenKind.colon,
        TokenKind.rightBracket,
      ]);
      var end = _lastEnd;
      var optional = false;
      if (look.kind == TokenKind.question) {
        end = _shift().span.end;
        optional = true;
      }
      final span = Span(target.span.start, end);
      if (iterate) return Iterate(span, target, optional: optional);
      if (isSlice) {
        return Slice(span, target, from, to, optional: optional);
      }
      return Index(span, target, from!, optional: optional);
    }

    if (dotted) return _nest(build);
    try {
      return _nest(build);
    } on _Signal catch (signal) {
      _recover(signal, mark, {TokenKind.rightBracket});
      _shift();
      return target;
    }
  }

  /// [_nest] written out: every bracketed construct passes through here, so
  /// it must not add closure frames to the host stack.
  Node _primary() {
    if (_depth >= maxSyntaxDepth) throw _TooDeep(look.span);
    _depth++;
    try {
      return _primaryBody();
    } finally {
      _depth--;
    }
  }

  Node _primaryBody() {
    final token = look;
    switch (token.kind) {
      case TokenKind.dot:
        return _dot();
      case TokenKind.recurse:
        _shift();
        return RecurseDefault(token.span);
      case TokenKind.breakKeyword:
        return _break();
      case TokenKind.field:
        _shift();
        return _fieldIndex(
          Identity(Span(token.span.start, token.span.start)),
          token,
        );
      case TokenKind.literal:
        _shift();
        return NumberLiteral(token.span, token.text);
      case TokenKind.format:
        _shift();
        _unsupportedConstruct(
          UnsupportedKind.format,
          token.span,
          '@${token.text}',
        );
        if (look.kind == TokenKind.stringStart) {
          return _stringBody(token, format: token.text);
        }
        return FormatFilter(token.span, token.text);
      case TokenKind.stringStart:
        return _string();
      case TokenKind.minus:
        _shift();
        final operand = _term();
        return Negate(Span(token.span.start, operand.span.end), operand);
      case TokenKind.leftParen:
        return _parenthesized();
      case TokenKind.leftBracket:
        return _arrayConstructor();
      case TokenKind.leftBrace:
        return _objectConstructor();
      case TokenKind.reduceKeyword:
        return _reduce();
      case TokenKind.foreachKeyword:
        return _foreach();
      case TokenKind.ifKeyword:
        return _if();
      case TokenKind.tryKeyword:
        return _try();
      case TokenKind.dollar:
        return _privateLoad();
      case TokenKind.binding:
        _shift();
        _noteQualified(token.text, token.span, variable: true);
        return Variable(token.span, token.text);
      case TokenKind.loc:
        _shift();
        _unsupportedConstruct(UnsupportedKind.locationBinding, token.span);
        return LocationLiteral(token.span);
      case TokenKind.ident:
        return _identifier();
      default:
        throw _unexpected(null);
    }
  }

  void _noteQualified(String name, Span span, {bool variable = false}) {
    if (name.contains('::')) {
      _unsupportedConstruct(
        UnsupportedKind.qualifiedName,
        span,
        variable ? '\$$name' : name,
      );
    }
  }

  /// `.`, `. String`, and the `'.' error` / `'.' IDENT error` recovery.
  Node _dot() {
    final dot = _shift();
    try {
      switch (look.kind) {
        case TokenKind.format:
        case TokenKind.stringStart:
          final key = _string();
          var end = key.span.end;
          var optional = false;
          if (look.kind == TokenKind.question) {
            end = _shift().span.end;
            optional = true;
          }
          return Index(
            Span(dot.span.start, end),
            Identity(Span(dot.span.start, dot.span.start)),
            key,
            optional: optional,
          );
        case TokenKind.ident:
          // `'.' IDENT` can only continue with the error production.
          _shift();
          throw _unexpected(null);
        default:
          if (_termFollow.contains(look.kind)) return Identity(dot.span);
          throw _unexpected(null);
      }
    } on _Signal catch (signal) {
      _fail(
        DiagnosticKind.syntax,
        'try .["field"] instead of .field for unusually named fields',
        Span(dot.span.start, signal.end),
      );
      return Identity(dot.span);
    }
  }

  Node _break() {
    final start = _shift();
    try {
      final label = _expect(TokenKind.binding);
      return Break(Span(start.span.start, label.span.end), label.text);
    } on _Signal catch (signal) {
      _fail(
        DiagnosticKind.syntax,
        'break requires a label to break to',
        Span(start.span.start, signal.end),
      );
      return Identity(start.span);
    }
  }

  Node _parenthesized() {
    final open = _shift();
    final mark = _mark();
    try {
      final inner = _query();
      final close = _expect(TokenKind.rightParen, [
        ..._pipeComma,
        TokenKind.rightParen,
      ]);
      return Group(Span(open.span.start, close.span.end), inner);
    } on _Signal catch (signal) {
      _recover(signal, mark, {TokenKind.rightParen});
      final close = _shift();
      return Identity(Span(open.span.start, close.span.end));
    }
  }

  Node _arrayConstructor() {
    final open = _shift();
    final mark = _mark();
    try {
      Node? body;
      if (look.kind != TokenKind.rightBracket) body = _query();
      final close = _expect(TokenKind.rightBracket, [
        ..._pipeComma,
        TokenKind.rightBracket,
      ]);
      return ArrayConstructor(Span(open.span.start, close.span.end), body);
    } on _Signal catch (signal) {
      _recover(signal, mark, {TokenKind.rightBracket});
      final close = _shift();
      return Identity(Span(open.span.start, close.span.end));
    }
  }

  Node _identifier() {
    final name = _shift();
    if (look.kind == TokenKind.leftParen) {
      _shift();
      _noteQualified(name.text, name.span);
      final arguments = <Node>[_query()];
      while (look.kind == TokenKind.semicolon) {
        _shift();
        arguments.add(_query());
      }
      final close = _expect(TokenKind.rightParen, [
        TokenKind.semicolon,
        TokenKind.rightParen,
      ]);
      return Call(Span(name.span.start, close.span.end), name.text, arguments);
    }
    switch (name.text) {
      case 'null':
        return LiteralConstant(name.span, null);
      case 'true':
        return LiteralConstant(name.span, true);
      case 'false':
        return LiteralConstant(name.span, false);
      default:
        _noteQualified(name.text, name.span);
        return Call(name.span, name.text, const []);
    }
  }

  Node _privateLoad() {
    final start = _shift();
    _expect(TokenKind.dollar);
    _expect(TokenKind.dollar);
    final name = _expect(TokenKind.binding);
    return Variable(
      Span(start.span.start, name.span.end),
      name.text,
      isPrivateLoad: true,
    );
  }

  Node _try() {
    final start = _shift();
    final body = _term();
    if (look.kind != TokenKind.catchKeyword) {
      return Try(Span(start.span.start, body.span.end), body, null);
    }
    _shift();
    try {
      final handler = _term();
      return Try(Span(start.span.start, handler.span.end), body, handler);
    } on _Signal catch (signal) {
      _fail(
        DiagnosticKind.syntax,
        "Possibly unterminated 'try' statement",
        Span(start.span.start, signal.end),
      );
      return body;
    }
  }

  Node _if() {
    final start = _shift();
    final condition = _query();
    _expect(TokenKind.thenKeyword, [TokenKind.thenKeyword, ..._pipeComma]);
    try {
      final then = _query();
      final (otherwise, end) = _elseBody();
      return If(Span(start.span.start, end), condition, then, otherwise);
    } on _Signal catch (signal) {
      _fail(
        DiagnosticKind.syntax,
        "Possibly unterminated 'if' statement",
        Span(start.span.start, signal.end),
      );
      return condition;
    }
  }

  /// ElseBody: returns the else branch (null for a bare `end`) and the end
  /// offset of the closing `end`.
  (Node?, int) _elseBody() {
    switch (look.kind) {
      case TokenKind.elifKeyword:
        final start = _shift();
        final condition = _query();
        _expect(TokenKind.thenKeyword, [TokenKind.thenKeyword, ..._pipeComma]);
        final then = _query();
        final (otherwise, end) = _nest(_elseBody);
        return (
          If(Span(start.span.start, end), condition, then, otherwise),
          end,
        );
      case TokenKind.elseKeyword:
        _shift();
        final body = _query();
        _expect(TokenKind.endKeyword, [TokenKind.endKeyword, ..._pipeComma]);
        return (body, _lastEnd);
      case TokenKind.endKeyword:
        final end = _shift();
        return (null, end.span.end);
      default:
        throw _unexpected([
          TokenKind.elseKeyword,
          TokenKind.elifKeyword,
          TokenKind.endKeyword,
          ..._pipeComma,
        ]);
    }
  }

  Node _reduce() {
    final start = _shift();
    final target = _expr(0);
    if (look.kind != TokenKind.asKeyword) throw _unexpected(null);
    _shift();
    final patterns = _patterns(TokenKind.leftParen);
    _expect(TokenKind.leftParen);
    final init = _query();
    _expect(TokenKind.semicolon, [..._pipeComma, TokenKind.semicolon]);
    final update = _query();
    final close = _expect(TokenKind.rightParen, [
      ..._pipeComma,
      TokenKind.rightParen,
    ]);
    return Reduce(
      Span(start.span.start, close.span.end),
      target,
      patterns,
      init,
      update,
    );
  }

  Node _foreach() {
    final start = _shift();
    final target = _expr(0);
    if (look.kind != TokenKind.asKeyword) throw _unexpected(null);
    _shift();
    final patterns = _patterns(TokenKind.leftParen);
    _expect(TokenKind.leftParen);
    final init = _query();
    _expect(TokenKind.semicolon, [..._pipeComma, TokenKind.semicolon]);
    final update = _query();
    Node? extract;
    if (look.kind == TokenKind.semicolon) {
      _shift();
      extract = _query();
    } else if (look.kind != TokenKind.rightParen) {
      throw _unexpected([
        ..._pipeComma,
        TokenKind.semicolon,
        TokenKind.rightParen,
      ]);
    }
    final close = _expect(TokenKind.rightParen, [
      ..._pipeComma,
      TokenKind.rightParen,
    ]);
    return Foreach(
      Span(start.span.start, close.span.end),
      target,
      patterns,
      init,
      update,
      extract,
    );
  }

  // -------------------------------------------------------------------------
  // Strings

  StringLiteral _string() {
    if (look.kind == TokenKind.format) {
      final format = _shift();
      _unsupportedConstruct(
        UnsupportedKind.format,
        format.span,
        '@${format.text}',
      );
      return _stringBody(format, format: format.text);
    }
    return _stringBody(look, format: null);
  }

  /// The string proper, starting at QQSTRING_START; [first] is the token the
  /// literal's span starts at (the format when there is one).
  StringLiteral _stringBody(Token first, {required String? format}) {
    _expect(TokenKind.stringStart);
    final parts = <StringPart>[];
    while (true) {
      switch (look.kind) {
        case TokenKind.stringText:
          parts.add(TextPart(_shift().value));
        case TokenKind.interpStart:
          _shift();
          final query = _query();
          _expect(TokenKind.interpEnd, [TokenKind.interpEnd, ..._pipeComma]);
          parts.add(InterpolationPart(query));
        case TokenKind.stringEnd:
          final end = _shift();
          return StringLiteral(
            Span(first.span.start, end.span.end),
            parts,
            format: format,
          );
        default:
          throw _unexpected([
            TokenKind.stringText,
            TokenKind.interpStart,
            TokenKind.stringEnd,
          ]);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Object constructors

  Node _objectConstructor() {
    final open = _shift();
    final entries = <ObjectEntry>[];
    final braceMark = _mark();
    var first = true;
    while (true) {
      // The state at the start of a pair: after `{` or after `,`.
      if (look.kind == TokenKind.rightBrace) {
        final close = _shift();
        return ObjectConstructor(
          Span(open.span.start, close.span.end),
          entries,
        );
      }
      final pairMark = _mark();
      try {
        entries.add(_dictPair());
      } on _Signal catch (signal) {
        final accept = {TokenKind.colon, if (first) TokenKind.rightBrace};
        final range = _recover(signal, pairMark, accept);
        if (look.kind == TokenKind.rightBrace) {
          final close = _shift();
          return Identity(Span(open.span.start, close.span.end));
        }
        entries.add(_recoveredPair(range));
      }
      // After a complete pair Bison has reduced to `'{' DictPairs . '}'`.
      while (true) {
        if (look.kind == TokenKind.comma) {
          _shift();
          first = false;
          break;
        }
        if (look.kind == TokenKind.rightBrace) {
          final close = _shift();
          return ObjectConstructor(
            Span(open.span.start, close.span.end),
            entries,
          );
        }
        final signal = _unexpected([TokenKind.rightBrace]);
        final range = _recover(signal, braceMark, {
          TokenKind.colon,
          TokenKind.rightBrace,
        });
        if (look.kind == TokenKind.rightBrace) {
          final close = _shift();
          return Identity(Span(open.span.start, close.span.end));
        }
        entries.add(_recoveredPair(range));
      }
    }
  }

  /// `error ':' DictExpr` once recovery has accepted the colon.
  ObjectEntry _recoveredPair(Span errorSpan) {
    _shift();
    final value = _dictExpression();
    _fail(
      DiagnosticKind.syntax,
      'May need parentheses around object key expression',
      errorSpan,
    );
    return ObjectEntry(
      Span(errorSpan.start, value.span.end),
      Identity(errorSpan),
      value,
    );
  }

  ObjectEntry _dictPair() {
    final token = look;
    switch (token.kind) {
      case TokenKind.ident:
        _shift();
        _noteQualified(token.text, token.span);
        return _namedPair(token, token.text);
      case TokenKind.binding:
        _shift();
        _noteQualified(token.text, token.span, variable: true);
        final variable = Variable(token.span, token.text);
        if (look.kind == TokenKind.colon) {
          _shift();
          final value = _dictExpression();
          return ObjectEntry(_cover(variable, value), variable, value);
        }
        return ObjectEntry(
          token.span,
          StringLiteral(token.span, [TextPart(token.text)]),
          variable,
        );
      case TokenKind.loc:
        _shift();
        _unsupportedConstruct(UnsupportedKind.locationBinding, token.span);
        return ObjectEntry(
          token.span,
          StringLiteral(token.span, const [TextPart('__loc__')]),
          LocationLiteral(token.span),
        );
      case TokenKind.format:
      case TokenKind.stringStart:
        final key = _string();
        if (look.kind == TokenKind.colon) {
          _shift();
          final value = _dictExpression();
          return ObjectEntry(_cover(key, value), key, value);
        }
        return ObjectEntry(
          key.span,
          key,
          Index(key.span, Identity(Span(key.span.start, key.span.start)), key),
        );
      case TokenKind.leftParen:
        _shift();
        final query = _query();
        _expect(TokenKind.rightParen, [..._pipeComma, TokenKind.rightParen]);
        _expect(TokenKind.colon);
        final value = _dictExpression();
        _checkObjectKey(query);
        return ObjectEntry(
          Span(token.span.start, value.span.end),
          query,
          value,
        );
      default:
        if (keywordKeyKinds.contains(token.kind)) {
          _shift();
          return _namedPair(token, token.kind.label);
        }
        throw _unexpected(null);
    }
  }

  /// `IDENT` or a keyword as a key: `name: value`, or the `{name}` shorthand.
  ObjectEntry _namedPair(Token token, String name) {
    final key = StringLiteral(token.span, [TextPart(name)]);
    if (look.kind == TokenKind.colon) {
      _shift();
      final value = _dictExpression();
      return ObjectEntry(_cover(key, value), key, value);
    }
    return ObjectEntry(
      token.span,
      key,
      Index(
        token.span,
        Identity(Span(token.span.start, token.span.start)),
        key,
      ),
    );
  }

  /// DictExpr: Expr values joined by `|`, read with a loop like [_query].
  Node _dictExpression() {
    final stages = <Node>[];
    while (true) {
      final stage = _expr(0);
      if (look.kind != TokenKind.pipe) return _pipeChain(stages, stage);
      _shift();
      stages.add(stage);
    }
  }

  void _checkObjectKey(Node key) {
    final value = constantOf(key);
    if (identical(value, notConstant) || value is String) return;
    _fail(
      DiagnosticKind.semantic,
      'Cannot use ${kindName(value)} (${dumpTruncated(value)}) as object key',
      key.span,
    );
  }

  // -------------------------------------------------------------------------
  // Patterns

  /// Patterns: one pattern, or `?//` alternatives. [follow] is the token that
  /// must come next; Bison reports only it after a complete pattern.
  List<BindingPattern> _patterns(TokenKind follow) {
    final patterns = [_pattern()];
    while (look.kind == TokenKind.alternation) {
      _shift();
      patterns.add(_pattern());
    }
    if (look.kind != follow) throw _unexpected([follow]);
    return patterns;
  }

  static const List<TokenKind> _patternStart = [
    TokenKind.binding,
    TokenKind.leftBracket,
    TokenKind.leftBrace,
  ];

  BindingPattern _pattern() => _nest(_patternBody);

  BindingPattern _patternBody() {
    final token = look;
    switch (token.kind) {
      case TokenKind.binding:
        _shift();
        _noteQualified(token.text, token.span, variable: true);
        return VariablePattern(token.span, token.text);
      case TokenKind.leftBracket:
        _shift();
        final elements = <BindingPattern>[_pattern()];
        while (look.kind == TokenKind.comma) {
          _shift();
          elements.add(_pattern());
        }
        final close = _expect(TokenKind.rightBracket, [
          TokenKind.comma,
          TokenKind.rightBracket,
        ]);
        return ArrayPattern(Span(token.span.start, close.span.end), elements);
      case TokenKind.leftBrace:
        return _objectPattern();
      default:
        throw _unexpected(_patternStart);
    }
  }

  BindingPattern _objectPattern() {
    final open = _shift();
    final entries = <ObjectPatternEntry>[];
    final braceMark = _mark();
    while (true) {
      final entryMark = _mark();
      try {
        entries.add(_objectPatternEntry());
      } on _Signal catch (signal) {
        entries.add(
          _recoveredPatternEntry(
            _recover(signal, entryMark, {TokenKind.colon}),
          ),
        );
      }
      while (true) {
        if (look.kind == TokenKind.comma) {
          _shift();
          break;
        }
        if (look.kind == TokenKind.rightBrace) {
          final close = _shift();
          return ObjectPattern(Span(open.span.start, close.span.end), entries);
        }
        final signal = _unexpected([TokenKind.comma, TokenKind.rightBrace]);
        entries.add(
          _recoveredPatternEntry(
            _recover(signal, braceMark, {TokenKind.colon}),
          ),
        );
      }
    }
  }

  /// `error ':' Pattern` once recovery has accepted the colon.
  ObjectPatternEntry _recoveredPatternEntry(Span errorSpan) {
    _shift();
    final value = _pattern();
    _fail(
      DiagnosticKind.syntax,
      'May need parentheses around object key expression',
      Span(errorSpan.start, value.span.end),
    );
    return ObjectPatternEntry(
      Span(errorSpan.start, value.span.end),
      Identity(errorSpan),
      value,
    );
  }

  ObjectPatternEntry _objectPatternEntry() {
    final token = look;
    switch (token.kind) {
      case TokenKind.binding:
        _shift();
        _noteQualified(token.text, token.span, variable: true);
        final key = StringLiteral(token.span, [TextPart(token.text)]);
        if (look.kind == TokenKind.colon) {
          _shift();
          final value = _pattern();
          return ObjectPatternEntry(
            Span(token.span.start, value.span.end),
            key,
            value,
            bindsKey: token.text,
          );
        }
        return ObjectPatternEntry(token.span, key, null, bindsKey: token.text);
      case TokenKind.ident:
        _shift();
        return _patternPair(
          token,
          StringLiteral(token.span, [TextPart(token.text)]),
        );
      case TokenKind.format:
      case TokenKind.stringStart:
        final key = _string();
        return _patternPair(token, key);
      case TokenKind.leftParen:
        _shift();
        final query = _query();
        _expect(TokenKind.rightParen, [..._pipeComma, TokenKind.rightParen]);
        _expect(TokenKind.colon);
        final value = _pattern();
        _checkObjectKey(query);
        return ObjectPatternEntry(
          Span(token.span.start, value.span.end),
          query,
          value,
        );
      default:
        if (keywordKeyKinds.contains(token.kind)) {
          _shift();
          return _patternPair(
            token,
            StringLiteral(token.span, [TextPart(token.kind.label)]),
          );
        }
        throw _unexpected(null);
    }
  }

  ObjectPatternEntry _patternPair(Token first, Node key) {
    _expect(TokenKind.colon);
    final value = _pattern();
    return ObjectPatternEntry(
      Span(first.span.start, value.span.end),
      key,
      value,
    );
  }
}
