import 'package:zaru/src/syntax/ast.dart';

/// Renders [node] as a compact S-expression so tests can assert tree shape,
/// associativity and precedence in one comparison.
String show(Node? node) {
  if (node == null) return '_';
  return switch (node) {
    Group(:final inner) => show(inner),
    Identity() => '.',
    RecurseDefault() => '..',
    LiteralConstant(:final value) => '$value',
    NumberLiteral(:final text) => text,
    StringLiteral() => _string(node),
    FormatFilter(:final name) => '(fmt $name)',
    Variable(:final name, :final isPrivateLoad) =>
      isPrivateLoad ? r'$$$$' + name : '\$$name',
    LocationLiteral() => r'$__loc__',
    Call(:final name, :final arguments) =>
      arguments.isEmpty ? name : '($name ${arguments.map(show).join(' ')})',
    Break(:final label) => '(break \$$label)',
    Index(:final target, :final key, :final optional) =>
      '(index${optional ? '?' : ''} ${show(target)} ${show(key)})',
    Slice(:final target, :final from, :final to, :final optional) =>
      '(slice${optional ? '?' : ''} ${show(target)} ${show(from)} ${show(to)})',
    Iterate(:final target, :final optional) =>
      '(each${optional ? '?' : ''} ${show(target)})',
    Try(:final body, :final handler, :final postfix) =>
      postfix
          ? '(? ${show(body)})'
          : handler == null
          ? '(try ${show(body)})'
          : '(try ${show(body)} ${show(handler)})',
    Negate(:final operand) => '(neg ${show(operand)})',
    ArrayConstructor(:final body) =>
      body == null ? '(array)' : '(array ${show(body)})',
    ObjectConstructor(:final entries) =>
      '(object${entries.map((e) => ' (${show(e.key)} ${show(e.value)})').join()})',
    Binary(:final operator, :final left, :final right) =>
      '(${operator.symbol} ${show(left)} ${show(right)})',
    Assign(:final operator, :final left, :final right) =>
      '(${operator.symbol} ${show(left)} ${show(right)})',
    And(:final left, :final right) => '(and ${show(left)} ${show(right)})',
    Or(:final left, :final right) => '(or ${show(left)} ${show(right)})',
    Alternative(:final left, :final right) =>
      '(// ${show(left)} ${show(right)})',
    Pipe(:final left, :final right) => '(| ${show(left)} ${show(right)})',
    Comma(:final left, :final right) => '(, ${show(left)} ${show(right)})',
    If(:final condition, :final then, :final otherwise) =>
      otherwise == null
          ? '(if ${show(condition)} ${show(then)})'
          : '(if ${show(condition)} ${show(then)} ${show(otherwise)})',
    Reduce(:final source, :final patterns, :final init, :final update) =>
      '(reduce ${show(source)} ${_patterns(patterns)} '
          '${show(init)} ${show(update)})',
    Foreach(
      :final source,
      :final patterns,
      :final init,
      :final update,
      :final extract,
    ) =>
      '(foreach ${show(source)} ${_patterns(patterns)} ${show(init)} '
          '${show(update)}${extract == null ? '' : ' ${show(extract)}'})',
    Bind(:final source, :final patterns, :final body) =>
      '(as ${show(source)} ${_patterns(patterns)} ${show(body)})',
    Label(:final name, :final body) => '(label \$$name ${show(body)})',
    DefineIn(:final definition, :final rest) =>
      '${showDefinition(definition)} ${show(rest)}',
  };
}

String showDefinition(FunctionDefinition d) {
  final params = d.parameters
      .map((p) => p.isValue ? '\$${p.name}' : p.name)
      .join(' ');
  return '(def ${d.name} ($params) ${show(d.body)})';
}

String _string(StringLiteral s) {
  final format = s.format == null ? '' : '@${s.format} ';
  if (s.isConstant && s.format == null) return '"${s.constantValue}"';
  final parts = s.parts
      .map(
        (p) => switch (p) {
          TextPart(:final value) => '"${value ?? '<invalid>'}"',
          InterpolationPart(:final query) => '\\(${show(query)})',
        },
      )
      .join(' ');
  return '(str $format$parts)';
}

String _patterns(List<BindingPattern> patterns) =>
    '<${patterns.map(showPattern).join(' ?// ')}>';

String showPattern(BindingPattern p) => switch (p) {
  VariablePattern(:final name) => '\$$name',
  ArrayPattern(:final elements) => '[${elements.map(showPattern).join(' ')}]',
  ObjectPattern(:final entries) =>
    '{${entries.map((e) {
      final key = e.bindsKey != null ? '\$${e.bindsKey}=${show(e.key)}' : show(e.key);
      return e.value == null ? key : '$key: ${showPattern(e.value!)}';
    }).join(' ')}}',
};
