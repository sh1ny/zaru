/// Compiles jq source into the immutable operation tree of the engine.
///
/// The pipeline has three outcomes, in this order of precedence:
///
/// 1. the parser reports a jq error (lexical, grammar, or a constant object
///    key of the wrong type): a jq compile error;
/// 2. name resolution finds an undefined variable, function or label: a jq
///    semantic compile error, reported in the order jq compiles the
///    expression (an index reports its key before its target). As in jq, the
///    body of a function and each filter argument of a call form their own
///    compilation unit: their names are checked only when the enclosing code
///    has no error, and a definition that nothing uses is dropped unchecked;
/// 3. the source is valid jq but uses a construct or builtin this release does
///    not implement: an *unsupported* error, whose blocks start with
///    `zaru: unsupported:` and so can never be mistaken for a jq diagnostic.
///
/// Only when all three are clear is an operation tree produced. A jq builtin
/// that is neither native nor hosted from `jq_builtins.dart` is never treated
/// as defined.
library;

import 'dart:convert';

import '../errors.dart';
import '../syntax/ast.dart';
import '../syntax/constants.dart';
import '../syntax/diagnostic.dart';
import '../syntax/parse_result.dart';
import '../syntax/parser.dart';
import '../syntax/span.dart';
import 'builtin_names.dart';
import 'jq_builtins.dart';
import 'machine.dart';

/// A compiled program: the operation tree and the declared external names.
final class CompiledProgram {
  const CompiledProgram(this.root, this.declared);

  final Op root;

  /// External variable names in binding order (first is outermost).
  final List<String> declared;
}

/// Compiles [source] with the external variables [variables], or throws a
/// [ZaruCompileError].
CompiledProgram compileSource(String source, Set<String> variables) =>
    guardCompileStack(() => _compile(source, variables));

/// Runs [body], turning a host stack overflow into a [ZaruCompileError].
///
/// The syntax depth budget keeps parsing and lowering well inside the host
/// stack, so this is the safety net for a shape the budget does not foresee:
/// such a program still fails with a typed error rather than crashing.
T guardCompileStack<T>(T Function() body) {
  try {
    return body();
  } on StackOverflowError {
    throw ZaruCompileError(
      message: _tooDeepToCompile,
      line: 0,
      col: 0,
      endLine: 0,
      endCol: 0,
      diagnostics: const ['zaru: error: $_tooDeepToCompile'],
    );
  }
}

const String _tooDeepToCompile = 'program is too deeply nested to compile';

CompiledProgram _compile(String source, Set<String> variables) {
  final parsed = parseProgram(source);
  final parseReport = parsed.report;
  if (parseReport != null) throw _error(parseReport, unsupported: false);

  final declared = variables.toList(growable: false);
  final lowering = _Lowering();
  lowering.unsupported.addAll(parsed.unsupported);
  final program = parsed.program!;
  Scope scope = const Scope.root();
  for (final name in declared) {
    scope = scope.withVariable(name);
  }
  final Op root = lowering.lowerProgram(program, scope);
  lowering.lowerReferencedBodies();

  // jq resolves names only after linking imported and included modules. Module
  // loading is unsupported, so any name such a program leaves undefined may be
  // one a module would supply: the program is unsupported, not a jq error.
  final loadsModules = lowering.unsupported.any(
    (construct) =>
        construct.kind == UnsupportedKind.importDirective ||
        construct.kind == UnsupportedKind.includeDirective,
  );
  final semantic = lowering.semanticDiagnostics();
  if (semantic.isNotEmpty && !loadsModules) {
    throw _error(DiagnosticReport(parsed.source, semantic), unsupported: false);
  }
  if (lowering.unsupported.isNotEmpty) {
    final ordered = [...lowering.unsupported]
      ..sort((a, b) => a.span.start.compareTo(b.span.start));
    throw _error(
      DiagnosticReport(parsed.source, [
        for (final construct in ordered) construct.toDiagnostic(),
      ]),
      unsupported: true,
    );
  }
  return CompiledProgram(root, declared);
}

ZaruCompileError _error(DiagnosticReport report, {required bool unsupported}) =>
    ZaruCompileError(
      message: report.message,
      line: report.line,
      col: report.column,
      endLine: report.endLine,
      endCol: report.endColumn,
      diagnostics: report.rendered,
      isUnsupported: unsupported,
    );

enum _Kind { variable, function, label }

/// One user definition, as the compiler tracks it.
final class FunctionInfo {
  FunctionInfo(this.definition, this.scope)
    : runtime = FunctionDef(definition.name);

  final FunctionDefinition definition;

  /// The scope the definition appears in (it does not yet contain itself).
  final Scope scope;

  /// The runtime body holder that calls point at.
  final FunctionDef runtime;

  /// The compilation unit of the body.
  late final CompilationUnit level = CompilationUnit(this);

  /// Whether code that is itself used calls this function.
  bool referenced = false;

  /// Whether the body has been lowered.
  bool lowered = false;
}

/// A compilation unit: the main program, a function body, or the argument
/// closure of a call. jq checks the names of a unit's nested units only when
/// the unit itself is free of errors.
final class CompilationUnit {
  CompilationUnit(this.function);

  /// The definition this unit is the body of, if any.
  final FunctionInfo? function;
  final List<Diagnostic> errors = [];
  final List<CompilationUnit> children = [];

  /// Whether this unit is part of the compiled program: an argument closure
  /// always is, a definition only when something uses it.
  bool get isLive => function == null || function!.referenced;
}

/// A resolved function name: how far away its cell is and, for a definition,
/// the definition (a filter parameter has none).
typedef FunctionRef = ({int hops, FunctionInfo? info});

/// The lexical scope at a point of the source: an immutable list of bindings.
///
/// Every binding occupies one cell of the runtime environment: a variable, a
/// function definition, a filter parameter or a label activation. A name
/// resolves to the number of cells between the use and its binding.
final class Scope {
  const Scope.root()
    : parent = null,
      _kind = null,
      name = '',
      arity = 0,
      depth = 0,
      function = null;

  const Scope._(
    this.parent,
    this._kind,
    this.name,
    this.arity,
    this.depth, {
    this.function,
  });

  final Scope? parent;
  final _Kind? _kind;
  final String name;
  final int arity;

  /// Cells in the environment at or below this binding.
  final int depth;

  /// The definition this function binding stands for; null for a parameter.
  final FunctionInfo? function;

  Scope withVariable(String variable) =>
      Scope._(this, _Kind.variable, variable, 0, depth + 1);

  Scope withFunction(String name, int parameters, FunctionInfo info) => Scope._(
    this,
    _Kind.function,
    name,
    parameters,
    depth + 1,
    function: info,
  );

  /// A filter parameter: a function of no parameters without a definition.
  Scope withParameter(String parameter) =>
      Scope._(this, _Kind.function, parameter, 0, depth + 1);

  Scope withLabel(String label) =>
      Scope._(this, _Kind.label, label, 0, depth + 1);

  /// Hops from the current environment to the variable [variable], or null.
  int? variableHops(String variable) {
    for (var s = this; s._kind != null; s = s.parent!) {
      if (s._kind == _Kind.variable && s.name == variable) {
        return depth - s.depth;
      }
    }
    return null;
  }

  FunctionRef? lookupFunction(String function, int parameters) {
    for (var s = this; s._kind != null; s = s.parent!) {
      if (s._kind == _Kind.function &&
          s.name == function &&
          s.arity == parameters) {
        return (hops: depth - s.depth, info: s.function);
      }
    }
    return null;
  }

  /// Hops from the current environment to the label [label], or null.
  int? labelHops(String label) {
    for (var s = this; s._kind != null; s = s.parent!) {
      if (s._kind == _Kind.label && s.name == label) return depth - s.depth;
    }
    return null;
  }
}

const Op _identity = IdentityOp();
const Op _placeholder = ConstOp(null);

final class _Lowering {
  final List<UnsupportedConstruct> unsupported = [];

  /// The unit being lowered, and the definition whose body it is (if any).
  final CompilationUnit _root = CompilationUnit(null);
  late CompilationUnit _level = _root;
  FunctionInfo? _current;

  /// Every definition met so far, in source order.
  final List<FunctionInfo> _definitions = [];

  void _undefined(String what, Span span) =>
      _level.errors.add(Diagnostic(DiagnosticKind.semantic, what, span));

  Op _defer(UnsupportedKind kind, Span span, [String? detail]) {
    unsupported.add(UnsupportedConstruct(kind, span, detail));
    return _placeholder;
  }

  Op lowerProgram(Program program, Scope scope) {
    final body = program.body;
    if (body == null) {
      if (program.definitions.isEmpty) return _identity;
      // jq's own message for a library without a main expression.
      _undefined('Top-level program not given (try ".")', Span.unknown);
      return _placeholder;
    }
    return lower(body, scope);
  }

  /// Lowers the body of every definition something uses. A body can use
  /// another definition, so this runs until no new definition becomes used.
  void lowerReferencedBodies() {
    var progress = true;
    while (progress) {
      progress = false;
      for (var i = 0; i < _definitions.length; i++) {
        final info = _definitions[i];
        if (info.referenced && !info.lowered) {
          _lowerBody(info);
          progress = true;
        }
      }
    }
  }

  /// The semantic diagnostics in jq's order: a unit's own errors first, then,
  /// only if it has none, those of its nested units in source order.
  List<Diagnostic> semanticDiagnostics() {
    final all = <Diagnostic>[];
    void collect(CompilationUnit level) {
      all.addAll(level.errors);
      if (level.errors.isNotEmpty) return;
      for (final child in level.children) {
        if (child.isLive) collect(child);
      }
    }

    collect(_root);
    return all;
  }

  FunctionInfo _define(FunctionDefinition definition, Scope scope) {
    final info = FunctionInfo(definition, scope);
    _level.children.add(info.level);
    _definitions.add(info);
    return info;
  }

  void _lowerBody(FunctionInfo info) {
    info.lowered = true;
    final savedLevel = _level;
    final savedCurrent = _current;
    _level = info.level;
    _current = info;

    final definition = info.definition;
    var inner = info.scope.withFunction(
      definition.name,
      definition.parameters.length,
      info,
    );
    for (final parameter in definition.parameters) {
      inner = inner.withParameter(parameter.name);
    }
    // `def f($a; $b): body` is `def f(a; b): a as $a | b as $b | body`, so the
    // first value parameter varies slowest.
    final bindings = <int>[];
    for (final parameter in definition.parameters) {
      if (!parameter.isValue) continue;
      bindings.add(inner.lookupFunction(parameter.name, 0)!.hops);
      inner = inner.withVariable(parameter.name);
    }
    var body = lower(definition.body, inner);
    for (var i = bindings.length - 1; i >= 0; i--) {
      body = BindOp(ParamCallOp(bindings[i]), body);
    }
    info.runtime.body = body;

    _level = savedLevel;
    _current = savedCurrent;
  }

  /// Lowers the filter argument of a call as its own compilation unit.
  Op _lowerArgument(Node argument, Scope scope) {
    final saved = _level;
    final unit = CompilationUnit(null);
    saved.children.add(unit);
    _level = unit;
    final op = lower(argument, scope);
    _level = saved;
    return op;
  }

  Op lower(Node node, Scope scope) {
    switch (node) {
      case Group(:final inner):
        return lower(inner, scope);
      case Identity():
        return _identity;
      case RecurseDefault():
        return BuiltinCallOp(_builtin('recurse/0')!.runtime, const []);
      case LiteralConstant():
      case NumberLiteral():
        return ConstOp(constantOf(node));
      case StringLiteral():
        return _lowerString(node, scope);
      case FormatFilter():
        return _defer(UnsupportedKind.format, node.span, '@${node.name}');
      case Variable():
        return _lowerVariable(node, scope);
      case LocationLiteral():
        return _defer(UnsupportedKind.locationBinding, node.span);
      case Call():
        return _lowerCall(node, scope);
      case Break(:final label):
        final hops = scope.labelHops(label);
        if (hops == null) {
          _undefined('\$*label-$label is not defined', node.span);
          return _placeholder;
        }
        return BreakOp(hops);
      case Index(:final target, :final key, :final optional):
        // jq compiles the key before the target, and reports names in that
        // order.
        final keyOp = lower(key, scope);
        final targetOp = lower(target, scope);
        return IndexOp(targetOp, keyOp, optional: optional);
      case Slice(:final target, :final from, :final to, :final optional):
        final fromOp = from == null ? null : lower(from, scope);
        final toOp = to == null ? null : lower(to, scope);
        final targetOp = lower(target, scope);
        return SliceOp(targetOp, fromOp, toOp, optional: optional);
      case Iterate(:final target, :final optional):
        return IterateOp(lower(target, scope), optional: optional);
      case Try(:final body, :final handler):
        final bodyOp = lower(body, scope);
        final handlerOp = handler == null ? null : lower(handler, scope);
        return TryOp(bodyOp, handlerOp);
      case Negate(:final operand):
        return NegateOp(lower(operand, scope));
      case ArrayConstructor(:final body):
        final constant = constantOf(node);
        if (!identical(constant, notConstant)) return ConstOp(constant);
        return ArrayOp(lower(body!, scope));
      case ObjectConstructor(:final entries):
        final constant = constantOf(node);
        if (!identical(constant, notConstant)) return ConstOp(constant);
        return ObjectOp([
          for (final entry in entries)
            ObjectEntryOp(lower(entry.key, scope), lower(entry.value, scope)),
        ]);
      case Binary(:final operator, :final left, :final right):
        final leftOp = lower(left, scope);
        final rightOp = lower(right, scope);
        return BinaryOp(operator, leftOp, rightOp);
      case Assign(:final operator, :final left, :final right):
        lower(left, scope);
        lower(right, scope);
        return _defer(UnsupportedKind.assignment, node.span, operator.symbol);
      case And(:final left, :final right):
        final leftOp = lower(left, scope);
        return LogicOp(leftOp, lower(right, scope), isAnd: true);
      case Or(:final left, :final right):
        final leftOp = lower(left, scope);
        return LogicOp(leftOp, lower(right, scope), isAnd: false);
      case Alternative(:final left, :final right):
        final leftOp = lower(left, scope);
        return AlternativeOp(leftOp, lower(right, scope));
      case Pipe():
        // A chain is flattened and built with loops: it is wide, not deep.
        final stages = <Node>[];
        Node tail = node;
        while (tail is Pipe) {
          stages.add(tail.left);
          tail = tail.right;
        }
        final ops = [for (final stage in stages) lower(stage, scope)];
        var result = lower(tail, scope);
        for (var i = ops.length - 1; i >= 0; i--) {
          result = PipeOp(ops[i], result);
        }
        return result;
      case Comma():
        final operands = <Node>[];
        Node head = node;
        while (head is Comma) {
          operands.add(head.right);
          head = head.left;
        }
        var result = lower(head, scope);
        for (final operand in operands.reversed) {
          result = CommaOp(result, lower(operand, scope));
        }
        return result;
      case If(:final condition, :final then, :final otherwise):
        final conditionOp = lower(condition, scope);
        final thenOp = lower(then, scope);
        final elseOp = otherwise == null ? _identity : lower(otherwise, scope);
        return IfOp(conditionOp, thenOp, elseOp);
      case Reduce(:final source, :final patterns, :final init, :final update):
        // jq compiles the initial state before the loop.
        final initOp = lower(init, scope);
        final sourceOp = lower(source, scope);
        final (binder, inner) = _binder(patterns, scope);
        return ReduceOp(sourceOp, binder, initOp, lower(update, inner));
      case Foreach(
        :final source,
        :final patterns,
        :final init,
        :final update,
        :final extract,
      ):
        final initOp = lower(init, scope);
        final sourceOp = lower(source, scope);
        final (binder, inner) = _binder(patterns, scope);
        final updateOp = lower(update, inner);
        final extractOp = extract == null ? null : lower(extract, inner);
        return ForeachOp(sourceOp, binder, initOp, updateOp, extractOp);
      case Bind(:final source, :final patterns, :final body):
        final sourceOp = lower(source, scope);
        if (patterns.length == 1 && patterns.single is VariablePattern) {
          final variable = (patterns.single as VariablePattern).name;
          return BindOp(sourceOp, lower(body, scope.withVariable(variable)));
        }
        final (binder, inner) = _binder(patterns, scope);
        return DestructureOp(sourceOp, binder, lower(body, inner));
      case Label(:final name, :final body):
        return LabelOp(lower(body, scope.withLabel(name)));
      case DefineIn(:final definition, :final rest):
        final info = _define(definition, scope);
        final restOp = lower(
          rest,
          scope.withFunction(
            definition.name,
            definition.parameters.length,
            info,
          ),
        );
        return DefineOp(restOp);
    }
  }

  /// Compiles the alternatives of a destructuring binding and returns them
  /// with [scope] extended by every variable they bind (one cell per distinct
  /// name, in order of first appearance).
  ///
  /// Key expressions are lowered in the scope *outside* the binding, as jq
  /// binds the pattern's variables only in the body.
  (Binder, Scope) _binder(List<BindingPattern> patterns, Scope scope) {
    final slots = <String, int>{};
    int slotOf(String name) => slots.putIfAbsent(name, () => slots.length);

    Matcher build(BindingPattern pattern) {
      switch (pattern) {
        case VariablePattern(:final name):
          return VarMatcher(slotOf(name));
        case ArrayPattern(:final elements):
          return ArrayMatcher([for (final element in elements) build(element)]);
        case ObjectPattern(:final entries):
          return ObjectMatcher([
            for (final entry in entries)
              () {
                final key = lower(entry.key, scope);
                final bound = entry.bindsKey;
                final value = entry.value;
                return ObjectEntryMatcher(
                  key,
                  bindSlot: bound == null ? null : slotOf(bound),
                  sub: value == null ? null : build(value),
                );
              }(),
          ]);
      }
    }

    final alternatives = [for (final pattern in patterns) build(pattern)];
    var inner = scope;
    for (final name in slots.keys) {
      inner = inner.withVariable(name);
    }
    return (Binder(alternatives, slots.length), inner);
  }

  Op _lowerString(StringLiteral node, Scope scope) {
    if (node.format != null) {
      return _defer(UnsupportedKind.format, node.span, '@${node.format}');
    }
    final constant = node.constantValue;
    if (constant != null) return ConstOp(constant);
    final parts = <Object>[];
    for (final part in node.parts) {
      switch (part) {
        case TextPart(:final value):
          parts.add(value ?? '');
        case InterpolationPart(:final query):
          parts.add(lower(query, scope));
      }
    }
    return InterpolateOp(parts);
  }

  Op _lowerVariable(Variable node, Scope scope) {
    if (node.isPrivateLoad) {
      return _defer(UnsupportedKind.qualifiedName, node.span, node.name);
    }
    final hops = scope.variableHops(node.name);
    if (hops != null) return VarOp(hops);
    if (node.name == 'ENV') {
      return _defer(UnsupportedKind.environment, node.span);
    }
    _undefined('\$${node.name} is not defined', node.span);
    return _placeholder;
  }

  /// The hosted jq-coded builtins met so far, lowered once per compilation.
  final Map<String, FunctionInfo> _hosted = {};

  /// The definition of the hosted builtin [signature], lowering it (and what
  /// it uses) on first use, or null when jq-coded source is not hosted for it.
  ///
  /// A builtin is closed over the other builtins only: it is lowered in the
  /// root scope, outside the program's own compilation units, so the
  /// program's definitions can neither capture nor shadow what it calls.
  FunctionInfo? _builtin(String signature) {
    final known = _hosted[signature];
    if (known != null) return known;
    final source = jqCodedBuiltins[signature];
    if (source == null) return null;
    final parsed = parseProgram('$source .');
    final definition = (parsed.program!.body! as DefineIn).definition;
    final info = FunctionInfo(definition, const Scope.root());
    _hosted[signature] = info;
    _lowerBody(info);
    return info;
  }

  Op _lowerCall(Call node, Scope scope) {
    final name = node.name;
    final arity = node.arguments.length;
    final signature = '$name/$arity';
    final nameSpan = Span(
      node.span.start,
      node.span.start + utf8.encode(name).length,
    );
    final found = scope.lookupFunction(name, arity);
    if (found != null) {
      final info = found.info;
      // A filter parameter takes no arguments, so it is a call by itself.
      if (info == null) return ParamCallOp(found.hops);
      // A definition's own body does not make it used.
      if (!identical(info, _current)) info.referenced = true;
      return CallOp(found.hops, info.runtime, [
        for (final argument in node.arguments) _lowerArgument(argument, scope),
      ]);
    }
    switch (signature) {
      case 'empty/0':
        return const EmptyOp();
      case 'not/0':
        return const NotOp();
      case 'error/0':
        return const ErrorOp(null);
      case 'tostring/0':
        return const TostringOp();
      case 'range/2':
        // The bytecoded range: jq compiles the start before the end.
        final from = _lowerArgument(node.arguments[0], scope);
        return RangeOp(from, _lowerArgument(node.arguments[1], scope));
      case 'last/1':
        return LastOp(_lowerArgument(node.arguments.single, scope));
    }
    final hosted = _builtin(signature);
    if (hosted != null) {
      return BuiltinCallOp(hosted.runtime, [
        for (final argument in node.arguments) _lowerArgument(argument, scope),
      ]);
    }
    if (jqBuiltinNames.contains(signature) ||
        jqPrivateBuiltinNames.contains(signature)) {
      for (final argument in node.arguments) {
        _lowerArgument(argument, scope);
      }
      return _defer(UnsupportedKind.builtin, nameSpan, signature);
    }
    // jq does not compile the arguments of a call it cannot resolve.
    _undefined('$signature is not defined', nameSpan);
    return _placeholder;
  }
}
