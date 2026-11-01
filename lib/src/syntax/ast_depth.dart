import 'ast.dart';
import 'span.dart';

/// The span of the first node of [program], in pre-order, that lies deeper
/// than [limit] levels, or `null` when the whole tree fits.
///
/// The root of the program body is level 1, and each child is one level below
/// its parent. Binding patterns and the bodies of definitions count like any
/// other child. The walk uses an explicit stack, so it is safe on a tree of
/// any height: it is the check that makes the recursive lowering of the tree
/// safe on the host stack.
Span? firstNodeBeyondDepth(Program program, int limit) {
  // Entries are a [Node], a [BindingPattern] or a [FunctionDefinition],
  // followed by its level, in alternation.
  final stack = <Object>[];

  void push(Object? item, int level) {
    if (item == null) return;
    stack
      ..add(item)
      ..add(level);
  }

  final module = program.module;
  if (module != null) push(module.metadata, 1);
  for (final import in program.imports) {
    push(import.path, 1);
    push(import.metadata, 1);
  }
  for (final definition in program.definitions) {
    push(definition.body, 1);
  }
  push(program.body, 1);

  while (stack.isNotEmpty) {
    final level = stack.removeLast() as int;
    final item = stack.removeLast();
    final below = level + 1;
    // Children are pushed last-to-first so the leftmost is visited first.
    switch (item) {
      case BindingPattern():
        if (level > limit) return item.span;
        switch (item) {
          case VariablePattern():
            break;
          case ArrayPattern(:final elements):
            for (final element in elements.reversed) {
              push(element, below);
            }
          case ObjectPattern(:final entries):
            for (final entry in entries.reversed) {
              push(entry.value, below);
              push(entry.key, below);
            }
        }
      case Node():
        if (level > limit) return item.span;
        switch (item) {
          case Identity() ||
              RecurseDefault() ||
              LiteralConstant() ||
              NumberLiteral() ||
              FormatFilter() ||
              Variable() ||
              LocationLiteral() ||
              Break():
            break;
          case Group(:final inner):
            push(inner, below);
          case StringLiteral(:final parts):
            for (final part in parts.reversed) {
              if (part is InterpolationPart) push(part.query, below);
            }
          case Call(:final arguments):
            for (final argument in arguments.reversed) {
              push(argument, below);
            }
          case Index(:final target, :final key):
            push(key, below);
            push(target, below);
          case Slice(:final target, :final from, :final to):
            push(to, below);
            push(from, below);
            push(target, below);
          case Iterate(:final target):
            push(target, below);
          case Try(:final body, :final handler):
            push(handler, below);
            push(body, below);
          case Negate(:final operand):
            push(operand, below);
          case ArrayConstructor(:final body):
            push(body, below);
          case ObjectConstructor(:final entries):
            for (final entry in entries.reversed) {
              push(entry.value, below);
              push(entry.key, below);
            }
          case Binary(:final left, :final right):
            push(right, below);
            push(left, below);
          case Assign(:final left, :final right):
            push(right, below);
            push(left, below);
          case And(:final left, :final right):
            push(right, below);
            push(left, below);
          case Or(:final left, :final right):
            push(right, below);
            push(left, below);
          case Alternative(:final left, :final right):
            push(right, below);
            push(left, below);
          case Pipe():
            // A chain is one n-ary node: its links add no depth.
            final stages = <Node>[];
            Node tail = item;
            while (tail is Pipe) {
              stages.add(tail.left);
              tail = tail.right;
            }
            push(tail, below);
            for (final stage in stages.reversed) {
              push(stage, below);
            }
          case Comma():
            final operands = <Node>[];
            Node head = item;
            while (head is Comma) {
              operands.add(head.right);
              head = head.left;
            }
            for (final operand in operands) {
              push(operand, below);
            }
            push(head, below);
          case If(:final condition, :final then, :final otherwise):
            push(otherwise, below);
            push(then, below);
            push(condition, below);
          case Reduce(
            :final source,
            :final patterns,
            :final init,
            :final update,
          ):
            push(update, below);
            push(init, below);
            for (final pattern in patterns.reversed) {
              push(pattern, below);
            }
            push(source, below);
          case Foreach(
            :final source,
            :final patterns,
            :final init,
            :final update,
            :final extract,
          ):
            push(extract, below);
            push(update, below);
            push(init, below);
            for (final pattern in patterns.reversed) {
              push(pattern, below);
            }
            push(source, below);
          case Bind(:final source, :final patterns, :final body):
            push(body, below);
            for (final pattern in patterns.reversed) {
              push(pattern, below);
            }
            push(source, below);
          case Label(:final body):
            push(body, below);
          case DefineIn(:final definition, :final rest):
            push(rest, below);
            push(definition.body, below);
        }
    }
  }
  return null;
}
