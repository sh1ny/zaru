import 'span.dart';

/// A parsed jq expression with its UTF-8 byte [span].
///
/// The tree mirrors pinned jq's grammar closely enough that no information
/// the compiler needs is lost: number lexemes stay as source text, string
/// segments keep their boundaries, optional (`?`) index forms are distinct
/// from the general `try`, and deferred syntax (formats, updates, `$__loc__`,
/// modules) is represented explicitly rather than lowered.
sealed class Node {
  const Node(this.span);

  final Span span;
}

/// A parenthesized query. jq's source locations include the parentheses
/// (`(.+1)` spans five bytes), so the tree keeps the group to preserve
/// those spans for diagnostics; evaluation ignores it.
final class Group extends Node {
  const Group(super.span, this.inner);

  final Node inner;
}

/// `.`
final class Identity extends Node {
  const Identity(super.span);
}

/// `..`
final class RecurseDefault extends Node {
  const RecurseDefault(super.span);
}

/// `null`, `true` or `false`, which jq's grammar parses as identifiers.
final class LiteralConstant extends Node {
  const LiteralConstant(super.span, this.value);

  /// `null`, `true` or `false`.
  final Object? value;
}

/// A numeric literal. [text] is the original source lexeme, so every digit
/// remains available (no conversion through `double`).
final class NumberLiteral extends Node {
  const NumberLiteral(super.span, this.text);

  final String text;
}

/// One piece of a string literal.
sealed class StringPart {
  const StringPart();
}

/// Literal text, with escapes already decoded. `null` marks text whose
/// escape sequence was invalid (a lexical diagnostic was reported).
final class TextPart extends StringPart {
  const TextPart(this.value);

  final String? value;
}

/// `\(query)`
final class InterpolationPart extends StringPart {
  const InterpolationPart(this.query);

  final Node query;
}

/// A string literal, possibly prefixed by a format (`@base64 "..."`).
///
/// With no [format], interpolated values use jq's implicit `text` format.
final class StringLiteral extends Node {
  const StringLiteral(super.span, this.parts, {this.format});

  final List<StringPart> parts;

  /// The format name without `@`, or `null` for a plain string.
  final String? format;

  /// Whether the string has no interpolation.
  bool get isConstant => parts.every((part) => part is TextPart);

  /// Concatenated text when [isConstant]; `null` otherwise.
  String? get constantValue {
    if (!isConstant) return null;
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer.write((part as TextPart).value ?? '');
    }
    return buffer.toString();
  }
}

/// A bare `@format` used as a filter.
final class FormatFilter extends Node {
  const FormatFilter(super.span, this.name);

  final String name;
}

/// `$name`, or jq's private `$$$$name` form when [isPrivateLoad] is set.
final class Variable extends Node {
  const Variable(super.span, this.name, {this.isPrivateLoad = false});

  final String name;
  final bool isPrivateLoad;
}

/// `$__loc__`
final class LocationLiteral extends Node {
  const LocationLiteral(super.span);
}

/// `name` or `name(arg; ...)`.
final class Call extends Node {
  const Call(super.span, this.name, this.arguments);

  final String name;
  final List<Node> arguments;
}

/// `break $name`
final class Break extends Node {
  const Break(super.span, this.label);

  final String label;
}

/// Field/key access: `.name`, `."str"`, `.[expr]`, `term.name`, `term[expr]`.
final class Index extends Node {
  const Index(super.span, this.target, this.key, {this.optional = false});

  /// Receiver; [Identity] for a leading `.name` or `.[...]`.
  final Node target;

  /// Key expression, evaluated against the original input.
  final Node key;

  /// Whether a trailing `?` was written, using jq's `INDEX_OPT` form.
  final bool optional;
}

/// `term[from:to]` with either bound optional.
final class Slice extends Node {
  const Slice(
    super.span,
    this.target,
    this.from,
    this.to, {
    this.optional = false,
  });

  final Node target;
  final Node? from;
  final Node? to;
  final bool optional;
}

/// `term[]` / `term[]?`
final class Iterate extends Node {
  const Iterate(super.span, this.target, {this.optional = false});

  final Node target;
  final bool optional;
}

/// `try body catch handler`, `try body`, or postfix `term?`.
final class Try extends Node {
  const Try(super.span, this.body, this.handler, {this.postfix = false});

  final Node body;

  /// `null` when errors are simply suppressed.
  final Node? handler;

  /// Whether this came from the generic postfix `?` rather than `try`.
  final bool postfix;
}

/// Unary minus applied to a term.
final class Negate extends Node {
  const Negate(super.span, this.operand);

  final Node operand;
}

/// `[query]` or `[]`.
final class ArrayConstructor extends Node {
  const ArrayConstructor(super.span, this.body);

  final Node? body;
}

/// One `key: value` pair of an object constructor.
///
/// Shorthand forms are expanded as jq does: `{a}` becomes key `"a"` with
/// value `.a`; `{$x}` becomes key `"x"` with value `$x`; `{"s"}` has the key
/// string and value `.["s"]`; `{$__loc__}` has key `"__loc__"`.
final class ObjectEntry {
  const ObjectEntry(this.span, this.key, this.value);

  final Span span;
  final Node key;
  final Node value;
}

/// `{ ... }`
final class ObjectConstructor extends Node {
  const ObjectConstructor(super.span, this.entries);

  final List<ObjectEntry> entries;
}

/// Binary operators with arithmetic or comparison semantics.
enum BinaryOperator {
  add('+'),
  subtract('-'),
  multiply('*'),
  divide('/'),
  modulo('%'),
  equal('=='),
  notEqual('!='),
  less('<'),
  greater('>'),
  lessOrEqual('<='),
  greaterOrEqual('>=');

  const BinaryOperator(this.symbol);

  final String symbol;
}

/// Assignment and update operators; all are deferred past M1.
enum AssignOperator {
  assign('='),
  update('|='),
  add('+='),
  subtract('-='),
  multiply('*='),
  divide('/='),
  modulo('%='),
  alternative('//=');

  const AssignOperator(this.symbol);

  final String symbol;
}

final class Binary extends Node {
  const Binary(super.span, this.operator, this.left, this.right);

  final BinaryOperator operator;
  final Node left;
  final Node right;
}

/// An assignment or update; recognized syntax, deferred semantics.
final class Assign extends Node {
  const Assign(super.span, this.operator, this.left, this.right);

  final AssignOperator operator;
  final Node left;
  final Node right;
}

final class And extends Node {
  const And(super.span, this.left, this.right);

  final Node left;
  final Node right;
}

final class Or extends Node {
  const Or(super.span, this.left, this.right);

  final Node left;
  final Node right;
}

/// `left // right`
final class Alternative extends Node {
  const Alternative(super.span, this.left, this.right);

  final Node left;
  final Node right;
}

/// `left | right`
final class Pipe extends Node {
  const Pipe(super.span, this.left, this.right);

  final Node left;
  final Node right;
}

/// `left , right`
final class Comma extends Node {
  const Comma(super.span, this.left, this.right);

  final Node left;
  final Node right;
}

/// `if c then t [elif ...] [else e] end`; an `elif` is a nested [If] in
/// [otherwise]. A missing `else` leaves [otherwise] `null`.
final class If extends Node {
  const If(super.span, this.condition, this.then, this.otherwise);

  final Node condition;
  final Node then;
  final Node? otherwise;
}

/// `reduce source as patterns (init; update)`
final class Reduce extends Node {
  const Reduce(super.span, this.source, this.patterns, this.init, this.update);

  final Node source;
  final List<BindingPattern> patterns;
  final Node init;
  final Node update;
}

/// `foreach source as patterns (init; update [; extract])`
final class Foreach extends Node {
  const Foreach(
    super.span,
    this.source,
    this.patterns,
    this.init,
    this.update,
    this.extract,
  );

  final Node source;
  final List<BindingPattern> patterns;
  final Node init;
  final Node update;

  /// `null` for the two-argument form.
  final Node? extract;
}

/// `source as patterns | body`; several [patterns] form a `?//` alternation.
final class Bind extends Node {
  const Bind(super.span, this.source, this.patterns, this.body);

  final Node source;
  final List<BindingPattern> patterns;
  final Node body;
}

/// `label $name | body`
final class Label extends Node {
  const Label(super.span, this.name, this.body);

  final String name;
  final Node body;
}

/// A function parameter: `name` (filter) or `$name` (value).
final class Parameter {
  const Parameter(this.span, this.name, {required this.isValue});

  final Span span;
  final String name;
  final bool isValue;
}

/// `def name(params): body;`
final class FunctionDefinition {
  const FunctionDefinition(this.span, this.name, this.parameters, this.body);

  final Span span;
  final String name;
  final List<Parameter> parameters;
  final Node body;
}

/// `def ...; rest` — the definition scopes over [rest].
final class DefineIn extends Node {
  const DefineIn(super.span, this.definition, this.rest);

  final FunctionDefinition definition;
  final Node rest;
}

/// A destructuring pattern.
sealed class BindingPattern {
  const BindingPattern(this.span);

  final Span span;
}

/// `$name`
final class VariablePattern extends BindingPattern {
  const VariablePattern(super.span, this.name);

  final String name;
}

/// `[p1, p2, ...]`
final class ArrayPattern extends BindingPattern {
  const ArrayPattern(super.span, this.elements);

  final List<BindingPattern> elements;
}

/// One entry of an object pattern.
///
/// [key] is the key expression. [bindsKey] is set when the key is `$name`,
/// which also binds the variable `name` to the looked-up value; [value] is
/// the sub-pattern (absent for plain `$name`).
final class ObjectPatternEntry {
  const ObjectPatternEntry(this.span, this.key, this.value, {this.bindsKey});

  final Span span;
  final Node key;
  final BindingPattern? value;
  final String? bindsKey;
}

/// `{k: p, $v, ...}`
final class ObjectPattern extends BindingPattern {
  const ObjectPattern(super.span, this.entries);

  final List<ObjectPatternEntry> entries;
}

/// A module-system directive. Parsed so that diagnostics match jq, then
/// flagged unsupported.
sealed class Directive {
  const Directive(this.span);

  final Span span;
}

/// `module metadata;`
final class ModuleDirective extends Directive {
  const ModuleDirective(super.span, this.metadata);

  final Node metadata;
}

/// `import "path" as name [metadata];` or `include "path" [metadata];`
final class ImportDirective extends Directive {
  const ImportDirective(
    super.span,
    this.path, {
    required this.alias,
    required this.isData,
    required this.isInclude,
    this.metadata,
  });

  final Node path;

  /// `null` for `include`.
  final String? alias;

  /// `import ... as $name` (data) rather than `as name` (code).
  final bool isData;
  final bool isInclude;
  final Node? metadata;
}

/// A complete parsed program.
///
/// A program with only definitions (jq's library form) has a `null` [body].
final class Program {
  const Program({
    required this.span,
    this.module,
    this.imports = const [],
    this.definitions = const [],
    this.body,
  });

  final Span span;
  final ModuleDirective? module;
  final List<ImportDirective> imports;

  /// Definitions of a definitions-only program.
  final List<FunctionDefinition> definitions;

  /// The main expression, with its own leading `def`s inside [DefineIn].
  final Node? body;
}
