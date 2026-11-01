/// Compiles jq source into the immutable operation tree of the engine.
///
/// The pipeline has three outcomes, in this order of precedence:
///
/// 1. the parser reports a jq error (lexical, grammar, or a constant object
///    key of the wrong type): a jq compile error;
/// 2. name resolution finds an undefined variable, function or label: a jq
///    semantic compile error, reported in the order jq compiles the
///    expression (an index reports its key before its target);
/// 3. the source is valid jq but uses a construct or builtin this release does
///    not implement: an *unsupported* error, whose blocks start with
///    `zaru: unsupported:` and so can never be mistaken for a jq diagnostic.
///
/// Only when all three are clear is an operation tree produced. A jq builtin
/// that is not natively implemented is never treated as defined.
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
CompiledProgram compileSource(String source, Set<String> variables) {
  final parsed = parseProgram(source);
  final parseReport = parsed.report;
  if (parseReport != null) throw _error(parseReport, unsupported: false);

  final declared = variables.toList(growable: false);
  final lowering = _Lowering(declared);
  lowering.unsupported.addAll(parsed.unsupported);
  final program = parsed.program!;
  Scope scope = const Scope.root();
  for (final name in declared) {
    scope = scope.withVariable(name);
  }
  final Op root = lowering.lowerProgram(program, scope);

  if (lowering.semantic.isNotEmpty) {
    throw _error(
      DiagnosticReport(parsed.source, lowering.semantic),
      unsupported: false,
    );
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

/// The lexical scope at a point of the source: an immutable list of bindings.
final class Scope {
  const Scope.root()
    : parent = null,
      _kind = null,
      name = '',
      arity = 0,
      variableCount = 0;

  const Scope._(
    this.parent,
    this._kind,
    this.name,
    this.arity,
    this.variableCount,
  );

  final Scope? parent;
  final _Kind? _kind;
  final String name;
  final int arity;

  /// Variables bound at or below this entry.
  final int variableCount;

  Scope withVariable(String variable) =>
      Scope._(this, _Kind.variable, variable, 0, variableCount + 1);

  Scope withFunction(String function, int parameters) =>
      Scope._(this, _Kind.function, function, parameters, variableCount);

  Scope withLabel(String label) =>
      Scope._(this, _Kind.label, label, 0, variableCount);

  /// Hops from the current environment to the variable [variable], or null.
  int? variableHops(String variable) {
    for (var s = this; s._kind != null; s = s.parent!) {
      if (s._kind == _Kind.variable && s.name == variable) {
        return variableCount - s.variableCount;
      }
    }
    return null;
  }

  bool hasFunction(String function, int parameters) {
    for (var s = this; s._kind != null; s = s.parent!) {
      if (s._kind == _Kind.function &&
          s.name == function &&
          s.arity == parameters) {
        return true;
      }
    }
    return false;
  }

  bool hasLabel(String label) {
    for (var s = this; s._kind != null; s = s.parent!) {
      if (s._kind == _Kind.label && s.name == label) return true;
    }
    return false;
  }
}

const Op _identity = IdentityOp();
const Op _placeholder = ConstOp(null);

final class _Lowering {
  _Lowering(this.declared);

  final List<String> declared;
  final List<Diagnostic> semantic = [];
  final List<UnsupportedConstruct> unsupported = [];

  void _undefined(String what, Span span) =>
      semantic.add(Diagnostic(DiagnosticKind.semantic, what, span));

  Op _defer(UnsupportedKind kind, Span span, [String? detail]) {
    unsupported.add(UnsupportedConstruct(kind, span, detail));
    return _placeholder;
  }

  Op lowerProgram(Program program, Scope scope) {
    for (final definition in program.definitions) {
      _lowerDefinition(definition, scope);
    }
    final body = program.body;
    if (program.definitions.isNotEmpty && body == null) return _placeholder;
    return body == null ? _identity : lower(body, scope);
  }

  void _lowerDefinition(FunctionDefinition definition, Scope scope) {
    _defer(
      UnsupportedKind.functionDefinition,
      definition.span,
      definition.name,
    );
    var inner = scope.withFunction(
      definition.name,
      definition.parameters.length,
    );
    for (final parameter in definition.parameters) {
      inner = inner.withFunction(parameter.name, 0);
      if (parameter.isValue) inner = inner.withVariable(parameter.name);
    }
    lower(definition.body, inner);
  }

  Op lower(Node node, Scope scope) {
    switch (node) {
      case Group(:final inner):
        return lower(inner, scope);
      case Identity():
        return _identity;
      case RecurseDefault():
        return _defer(UnsupportedKind.recursiveDescent, node.span);
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
        if (!scope.hasLabel(label)) {
          _undefined('\$*label-$label is not defined', node.span);
          return _placeholder;
        }
        return _defer(UnsupportedKind.label, node.span);
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
      case Pipe(:final left, :final right):
        final leftOp = lower(left, scope);
        return PipeOp(leftOp, lower(right, scope));
      case Comma(:final left, :final right):
        final leftOp = lower(left, scope);
        return CommaOp(leftOp, lower(right, scope));
      case If(:final condition, :final then, :final otherwise):
        final conditionOp = lower(condition, scope);
        final thenOp = lower(then, scope);
        final elseOp = otherwise == null ? _identity : lower(otherwise, scope);
        return IfOp(conditionOp, thenOp, elseOp);
      case Reduce(:final source, :final patterns, :final init, :final update):
        lower(source, scope);
        lower(init, scope);
        lower(update, _bindPatterns(patterns, scope));
        return _defer(UnsupportedKind.reduce, node.span);
      case Foreach(
        :final source,
        :final patterns,
        :final init,
        :final update,
        :final extract,
      ):
        lower(source, scope);
        lower(init, scope);
        final inner = _bindPatterns(patterns, scope);
        lower(update, inner);
        if (extract != null) lower(extract, inner);
        return _defer(UnsupportedKind.foreach, node.span);
      case Bind(:final source, :final patterns, :final body):
        final sourceOp = lower(source, scope);
        final inner = _bindPatterns(patterns, scope);
        final bodyOp = lower(body, inner);
        if (patterns.length == 1 && patterns.single is VariablePattern) {
          return BindOp(sourceOp, bodyOp);
        }
        return _defer(UnsupportedKind.destructuring, node.span);
      case Label(:final name, :final body):
        lower(body, scope.withLabel(name));
        return _defer(UnsupportedKind.label, node.span);
      case DefineIn(:final definition, :final rest):
        _lowerDefinition(definition, scope);
        lower(
          rest,
          scope.withFunction(definition.name, definition.parameters.length),
        );
        return _placeholder;
    }
  }

  /// Extends [scope] with every variable that [patterns] bind, resolving
  /// the key expressions inside them against the extended scope.
  Scope _bindPatterns(List<BindingPattern> patterns, Scope scope) {
    var inner = scope;
    final keys = <Node>[];
    final names = <String>[];
    void collect(BindingPattern pattern) {
      switch (pattern) {
        case VariablePattern(:final name):
          names.add(name);
        case ArrayPattern(:final elements):
          elements.forEach(collect);
        case ObjectPattern(:final entries):
          for (final entry in entries) {
            keys.add(entry.key);
            final bound = entry.bindsKey;
            if (bound != null) names.add(bound);
            final value = entry.value;
            if (value != null) collect(value);
          }
      }
    }

    patterns.forEach(collect);
    for (final name in names) {
      inner = inner.withVariable(name);
    }
    for (final key in keys) {
      lower(key, inner);
    }
    return inner;
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

  Op _lowerCall(Call node, Scope scope) {
    final name = node.name;
    final arity = node.arguments.length;
    final signature = '$name/$arity';
    final nameSpan = Span(
      node.span.start,
      node.span.start + utf8.encode(name).length,
    );
    if (scope.hasFunction(name, arity)) {
      for (final argument in node.arguments) {
        lower(argument, scope);
      }
      return _defer(UnsupportedKind.functionDefinition, nameSpan, signature);
    }
    switch (signature) {
      case 'empty/0':
        return const EmptyOp();
      case 'not/0':
        return const NotOp();
      case 'error/0':
        return const ErrorOp(null);
      case 'error/1':
        return ErrorOp(lower(node.arguments.single, scope));
      case 'select/1':
        return SelectOp(lower(node.arguments.single, scope));
    }
    if (jqBuiltinNames.contains(signature)) {
      for (final argument in node.arguments) {
        lower(argument, scope);
      }
      return _defer(UnsupportedKind.builtin, nameSpan, signature);
    }
    _undefined('$signature is not defined', nameSpan);
    for (final argument in node.arguments) {
      lower(argument, scope);
    }
    return _placeholder;
  }
}
