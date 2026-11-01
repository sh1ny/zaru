/// The backtracking execution machine and the immutable operation tree.
///
/// A compiled filter is a tree of immutable [Op]s. Each run owns one
/// [Machine]: the registers (current operation, input, lexical [Env], pending
/// continuation [Frame]s), a stack of [Choice]s that hold every alternative
/// still to be explored, and the error-unwinding state. Nothing recurses on
/// the host stack: a pipe, a generator or a thousand nested expressions grow
/// only the continuation list and the choice stack, and the right-hand side
/// of a pipe, a comma or an `if` branch runs with the continuation of the
/// whole expression (a tail position), so completed steps leave nothing
/// behind.
///
/// The machine pulls: [Machine.advance] runs until the next output and returns,
/// so an unneeded suffix is never evaluated and independent iterators never
/// share state. Operations, frames and choices carry no mutable state except
/// the one-shot cells noted at their definitions, and none of them is shared
/// between machines.
library;

import '../errors.dart';
import '../syntax/ast.dart' show BinaryOperator;
import '../value.dart';
import 'values.dart';

/// Immutable lexical environment: one cell per variable binding.
final class Env {
  const Env(this.value, this.parent);

  final Object? value;
  final Env? parent;
}

Object? _lookup(Env? env, int hops) {
  var cell = env!;
  for (var i = 0; i < hops; i++) {
    cell = cell.parent!;
  }
  return cell.value;
}

const int _eval = 0;
const int _ret = 1;
const int _fail = 2;
const int _raise = 3;

/// Work still to be done with a value, when the value arrives.
abstract base class Frame {
  const Frame(this.next);

  /// The continuation below this frame; the machine's `k` already points
  /// here when [resume] runs.
  final Frame? next;

  void resume(Machine m, Object? value);
}

/// A saved alternative that backtracking resumes.
abstract base class Choice {
  const Choice();

  /// Continues execution from this alternative (the choice is already popped).
  void resume(Machine m);

  /// Called while an error unwinds the choice stack. Returns whether the
  /// error was handled (the machine then continues in whatever mode this
  /// choice set).
  bool onRaise(Machine m) => false;
}

/// An executable node.
abstract base class Op {
  const Op();

  /// Runs one step with the machine's registers (`op`, `input`, `env`, `k`).
  void exec(Machine m);
}

/// A node that needs no machine step: its value follows from the input and
/// the environment alone.
abstract base class PureOp extends Op {
  const PureOp();

  Object? valueOf(Object? input, Env? env);

  @override
  void exec(Machine m) => m.emit(valueOf(m.input, m.env));
}

final class Machine {
  Machine(this.op, this.input, this.env);

  Op op;
  Object? input;
  Env? env;
  Frame? k;

  /// The value being returned to [k] while in return mode.
  Object? value;

  /// The latest output, valid after [advance] returned true.
  Object? output;

  /// The error value while unwinding, and how many `try` bodies' completed
  /// exits the unwinding error has passed through (see [_PassThrough]).
  Object? error;
  int wraps = 0;

  int mode = _eval;
  bool finished = false;
  final List<Choice> choices = [];

  void emit(Object? v) {
    value = v;
    mode = _ret;
  }

  void fail() => mode = _fail;

  void evalOp(Op next, Object? nextInput, Env? nextEnv, Frame? nextK) {
    op = next;
    input = nextInput;
    env = nextEnv;
    k = nextK;
    mode = _eval;
  }

  /// Runs until the next output (returns true) or until every alternative is
  /// exhausted (returns false). An error nobody catches throws a
  /// [ZaruRuntimeError] and ends the machine.
  bool advance() {
    if (finished) return false;
    while (true) {
      try {
        while (true) {
          switch (mode) {
            case _eval:
              op.exec(this);
            case _ret:
              final frame = k;
              if (frame == null) {
                output = value;
                mode = _fail;
                return true;
              }
              k = frame.next;
              frame.resume(this, value);
            case _fail:
              if (choices.isEmpty) {
                finished = true;
                return false;
              }
              choices.removeLast().resume(this);
            default:
              if (!_unwind()) {
                finished = true;
                throw ZaruRuntimeError(exportValue(error));
              }
          }
        }
      } on JqError catch (e) {
        error = e.value;
        wraps = 0;
        mode = _raise;
      }
    }
  }

  bool _unwind() {
    while (choices.isNotEmpty) {
      if (choices.removeLast().onRaise(this)) return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Leaf operations.

final class IdentityOp extends PureOp {
  const IdentityOp();

  @override
  Object? valueOf(Object? input, Env? env) => input;
}

final class ConstOp extends PureOp {
  const ConstOp(this.value);

  final Object? value;

  @override
  Object? valueOf(Object? input, Env? env) => value;
}

final class VarOp extends PureOp {
  const VarOp(this.hops);

  final int hops;

  @override
  Object? valueOf(Object? input, Env? env) => _lookup(env, hops);
}

final class EmptyOp extends Op {
  const EmptyOp();

  @override
  void exec(Machine m) => m.fail();
}

final class NotOp extends PureOp {
  const NotOp();

  @override
  Object? valueOf(Object? input, Env? env) => !isTruthy(input);
}

/// `error` (the input is the error) and `error(f)` (each output of `f`).
final class ErrorOp extends Op {
  const ErrorOp(this.message);

  final Op? message;

  @override
  void exec(Machine m) {
    final f = message;
    if (f == null) throw JqError(m.input);
    m.k = _ErrorFrame(m.k);
    m.op = f;
  }
}

final class _ErrorFrame extends Frame {
  const _ErrorFrame(super.next);

  @override
  void resume(Machine m, Object? value) => throw JqError(value);
}

// ---------------------------------------------------------------------------
// Sequencing: pipe, comma, binding.

final class PipeOp extends Op {
  const PipeOp(this.left, this.right);

  final Op left;
  final Op right;

  @override
  void exec(Machine m) {
    m.k = _PipeFrame(right, m.env, m.k);
    m.op = left;
  }
}

final class _PipeFrame extends Frame {
  const _PipeFrame(this.right, this.env, super.next);

  final Op right;
  final Env? env;

  @override
  void resume(Machine m, Object? value) => m.evalOp(right, value, env, next);
}

final class CommaOp extends Op {
  const CommaOp(this.left, this.right);

  final Op left;
  final Op right;

  @override
  void exec(Machine m) {
    m.choices.add(_AltChoice(right, m.input, m.env, m.k));
    m.op = left;
  }
}

final class _AltChoice extends Choice {
  const _AltChoice(this.op, this.input, this.env, this.k);

  final Op op;
  final Object? input;
  final Env? env;
  final Frame? k;

  @override
  void resume(Machine m) => m.evalOp(op, input, env, k);
}

/// `source as $x | body`: the body sees the original input and one more
/// variable per source output.
final class BindOp extends Op {
  const BindOp(this.source, this.body);

  final Op source;
  final Op body;

  @override
  void exec(Machine m) {
    m.k = _BindFrame(body, m.input, m.env, m.k);
    m.op = source;
  }
}

final class _BindFrame extends Frame {
  const _BindFrame(this.body, this.input, this.env, super.next);

  final Op body;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) =>
      m.evalOp(body, input, Env(value, env), next);
}

// ---------------------------------------------------------------------------
// Access.

/// `target[key]`, `.name`, and their `?` forms. The key (evaluated against the
/// original input) varies slowest; the target varies fastest.
final class IndexOp extends Op {
  const IndexOp(this.target, this.key, {required this.optional});

  final Op target;
  final Op key;
  final bool optional;

  @override
  void exec(Machine m) {
    final keyOp = key;
    if (keyOp is PureOp) {
      _afterKey(m, keyOp.valueOf(m.input, m.env));
      return;
    }
    m.k = _IndexKeyFrame(this, m.input, m.env, m.k);
    m.op = keyOp;
  }

  void _afterKey(Machine m, Object? keyValue) {
    final t = target;
    if (t is PureOp) {
      _apply(m, t.valueOf(m.input, m.env), keyValue);
      return;
    }
    m.k = _IndexTargetFrame(this, keyValue, m.k);
    m.op = t;
  }

  void _apply(Machine m, Object? t, Object? keyValue) {
    if (!optional) {
      m.emit(indexValue(t, keyValue));
      return;
    }
    try {
      m.emit(indexValue(t, keyValue));
    } on JqError {
      m.fail();
    }
  }
}

final class _IndexKeyFrame extends Frame {
  const _IndexKeyFrame(this.index, this.input, this.env, super.next);

  final IndexOp index;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) {
    m.input = input;
    m.env = env;
    m.mode = _eval;
    index._afterKey(m, value);
  }
}

final class _IndexTargetFrame extends Frame {
  const _IndexTargetFrame(this.index, this.key, super.next);

  final IndexOp index;
  final Object? key;

  @override
  void resume(Machine m, Object? value) => index._apply(m, value, key);
}

/// `target[from:to]`: `from` varies slowest, then `to`, then the target.
final class SliceOp extends Op {
  const SliceOp(this.target, this.from, this.to, {required this.optional});

  final Op target;
  final Op? from;
  final Op? to;
  final bool optional;

  @override
  void exec(Machine m) {
    final f = from;
    if (f == null) {
      _afterFrom(m, null, m.input, m.env, m.k);
      return;
    }
    m.k = _SliceFromFrame(this, m.input, m.env, m.k);
    m.op = f;
  }

  void _afterFrom(
    Machine m,
    Object? fromValue,
    Object? input,
    Env? env,
    Frame? next,
  ) {
    final t = to;
    if (t == null) {
      _afterTo(m, fromValue, null, input, env, next);
      return;
    }
    m.evalOp(t, input, env, _SliceToFrame(this, fromValue, input, env, next));
  }

  void _afterTo(
    Machine m,
    Object? fromValue,
    Object? toValue,
    Object? input,
    Env? env,
    Frame? next,
  ) {
    m.evalOp(
      target,
      input,
      env,
      _SliceTargetFrame(this, fromValue, toValue, next),
    );
  }
}

final class _SliceFromFrame extends Frame {
  const _SliceFromFrame(this.slice, this.input, this.env, super.next);

  final SliceOp slice;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) =>
      slice._afterFrom(m, value, input, env, next);
}

final class _SliceToFrame extends Frame {
  const _SliceToFrame(
    this.slice,
    this.fromValue,
    this.input,
    this.env,
    super.next,
  );

  final SliceOp slice;
  final Object? fromValue;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) =>
      slice._afterTo(m, fromValue, value, input, env, next);
}

final class _SliceTargetFrame extends Frame {
  const _SliceTargetFrame(this.slice, this.fromValue, this.toValue, super.next);

  final SliceOp slice;
  final Object? fromValue;
  final Object? toValue;

  @override
  void resume(Machine m, Object? value) {
    final key = JqObject(<String, Object?>{'start': fromValue, 'end': toValue});
    if (!slice.optional) {
      m.emit(indexValue(value, key));
      return;
    }
    try {
      m.emit(indexValue(value, key));
    } on JqError {
      m.fail();
    }
  }
}

/// `target[]` and `target[]?`.
final class IterateOp extends Op {
  const IterateOp(this.target, {required this.optional});

  final Op target;
  final bool optional;

  @override
  void exec(Machine m) {
    final t = target;
    if (t is PureOp) {
      _iterate(m, t.valueOf(m.input, m.env));
      return;
    }
    m.k = _IterateFrame(this, m.k);
    m.op = t;
  }

  void _iterate(Machine m, Object? v) {
    if (isArray(v)) {
      final items = arrayItems(v);
      if (items.isEmpty) {
        m.fail();
        return;
      }
      if (items.length > 1) m.choices.add(_ArrayIterChoice(items, m.k));
      m.emit(items[0]);
    } else if (isObject(v)) {
      final it = objectEntries(v).values.iterator;
      if (!it.moveNext()) {
        m.fail();
        return;
      }
      m.choices.add(_ObjectIterChoice(it, m.k));
      m.emit(it.current);
    } else if (optional) {
      m.fail();
    } else {
      throw JqError('Cannot iterate over ${describe(v)}');
    }
  }
}

final class _IterateFrame extends Frame {
  const _IterateFrame(this.iterate, super.next);

  final IterateOp iterate;

  @override
  void resume(Machine m, Object? value) => iterate._iterate(m, value);
}

/// Resumes iteration at the next array element. The one-shot [index] is
/// advanced in place and the choice pushed again while elements remain.
final class _ArrayIterChoice extends Choice {
  _ArrayIterChoice(this.items, this.k);

  final List<Object?> items;
  final Frame? k;
  int index = 1;

  @override
  void resume(Machine m) {
    final i = index;
    if (i >= items.length) {
      m.fail();
      return;
    }
    index = i + 1;
    if (index < items.length) m.choices.add(this);
    m.k = k;
    m.emit(items[i]);
  }
}

final class _ObjectIterChoice extends Choice {
  _ObjectIterChoice(this.it, this.k);

  final Iterator<Object?> it;
  final Frame? k;

  @override
  void resume(Machine m) {
    if (!it.moveNext()) {
      m.fail();
      return;
    }
    m.choices.add(this);
    m.k = k;
    m.emit(it.current);
  }
}

// ---------------------------------------------------------------------------
// Construction.

/// `[body]`: collects every output of the body, then yields the array once
/// the body is exhausted. An error inside the body discards the partial
/// array with the choice that would have yielded it.
final class ArrayOp extends Op {
  const ArrayOp(this.body);

  final Op body;

  @override
  void exec(Machine m) {
    final items = <Object?>[];
    m.choices.add(_ArrayDoneChoice(items, m.k));
    m.k = _ArrayAppendFrame(items);
    m.op = body;
  }
}

final class _ArrayAppendFrame extends Frame {
  const _ArrayAppendFrame(this.items) : super(null);

  final List<Object?> items;

  @override
  void resume(Machine m, Object? value) {
    items.add(value);
    m.fail();
  }
}

final class _ArrayDoneChoice extends Choice {
  const _ArrayDoneChoice(this.items, this.k);

  final List<Object?> items;
  final Frame? k;

  @override
  void resume(Machine m) {
    m.k = k;
    m.emit(JqArray(items));
  }
}

final class ObjectEntryOp {
  const ObjectEntryOp(this.key, this.value);

  final Op key;
  final Op value;
}

/// `{k: v, ...}`: the first entry varies slowest; within an entry the key
/// varies slower than the value.
final class ObjectOp extends Op {
  const ObjectOp(this.entries);

  final List<ObjectEntryOp> entries;

  @override
  void exec(Machine m) => _begin(m, 0, null, m.input, m.env, m.k);

  void _begin(
    Machine m,
    int index,
    _Pair? pairs,
    Object? input,
    Env? env,
    Frame? next,
  ) {
    if (index == entries.length) {
      final map = <String, Object?>{};
      final ordered = <_Pair>[];
      for (var p = pairs; p != null; p = p.previous) {
        ordered.add(p);
      }
      for (var i = ordered.length - 1; i >= 0; i--) {
        map[ordered[i].key] = ordered[i].value;
      }
      m.k = next;
      m.emit(JqObject(map));
      return;
    }
    final entry = entries[index];
    final keyOp = entry.key;
    if (keyOp is ConstOp && keyOp.value is String) {
      m.evalOp(
        entry.value,
        input,
        env,
        _ObjectValueFrame(
          this,
          index,
          keyOp.value! as String,
          pairs,
          input,
          env,
          next,
        ),
      );
      return;
    }
    m.evalOp(
      keyOp,
      input,
      env,
      _ObjectKeyFrame(this, index, pairs, input, env, next),
    );
  }
}

final class _Pair {
  const _Pair(this.key, this.value, this.previous);

  final String key;
  final Object? value;
  final _Pair? previous;
}

final class _ObjectKeyFrame extends Frame {
  const _ObjectKeyFrame(
    this.object,
    this.index,
    this.pairs,
    this.input,
    this.env,
    super.next,
  );

  final ObjectOp object;
  final int index;
  final _Pair? pairs;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) {
    if (value is! String) {
      throw JqError('Cannot use ${describe(value)} as object key');
    }
    m.evalOp(
      object.entries[index].value,
      input,
      env,
      _ObjectValueFrame(object, index, value, pairs, input, env, next),
    );
  }
}

final class _ObjectValueFrame extends Frame {
  const _ObjectValueFrame(
    this.object,
    this.index,
    this.key,
    this.pairs,
    this.input,
    this.env,
    super.next,
  );

  final ObjectOp object;
  final int index;
  final String key;
  final _Pair? pairs;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) =>
      object._begin(m, index + 1, _Pair(key, value, pairs), input, env, next);
}

/// A string with interpolation. [parts] holds `String` text and [Op]
/// placeholders; the last placeholder varies slowest, as jq builds the string
/// with right-nested additions.
final class InterpolateOp extends Op {
  const InterpolateOp(this.parts);

  final List<Object> parts;

  @override
  void exec(Machine m) => _step(m, parts.length - 1, null, m.input, m.env, m.k);

  void _step(
    Machine m,
    int index,
    _Chunk? chunks,
    Object? input,
    Env? env,
    Frame? next,
  ) {
    var i = index;
    var collected = chunks;
    while (i >= 0) {
      final part = parts[i];
      if (part is String) {
        collected = _Chunk(part, collected);
        i--;
        continue;
      }
      m.evalOp(
        part as Op,
        input,
        env,
        _InterpolateFrame(this, i, collected, input, env, next),
      );
      return;
    }
    final out = StringBuffer();
    for (var c = collected; c != null; c = c.next) {
      out.write(c.text);
    }
    m.k = next;
    m.emit(out.toString());
  }
}

final class _Chunk {
  const _Chunk(this.text, this.next);

  final String text;
  final _Chunk? next;
}

final class _InterpolateFrame extends Frame {
  const _InterpolateFrame(
    this.op,
    this.index,
    this.chunks,
    this.input,
    this.env,
    super.next,
  );

  final InterpolateOp op;
  final int index;
  final _Chunk? chunks;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) => op._step(
    m,
    index - 1,
    _Chunk(stringify(value), chunks),
    input,
    env,
    next,
  );
}

// ---------------------------------------------------------------------------
// Operators.

final class NegateOp extends Op {
  const NegateOp(this.operand);

  final Op operand;

  @override
  void exec(Machine m) {
    m.k = _NegateFrame(m.k);
    m.op = operand;
  }
}

final class _NegateFrame extends Frame {
  const _NegateFrame(super.next);

  @override
  void resume(Machine m, Object? value) => m.emit(negate(value));
}

/// Arithmetic and comparison: the right operand varies slowest.
final class BinaryOp extends Op {
  const BinaryOp(this.operator, this.left, this.right);

  final BinaryOperator operator;
  final Op left;
  final Op right;

  @override
  void exec(Machine m) {
    final r = right;
    if (r is PureOp) {
      _afterRight(m, r.valueOf(m.input, m.env), m.input, m.env, m.k);
      return;
    }
    m.k = _BinaryRightFrame(this, m.input, m.env, m.k);
    m.op = r;
  }

  void _afterRight(
    Machine m,
    Object? rightValue,
    Object? input,
    Env? env,
    Frame? next,
  ) {
    final l = left;
    if (l is PureOp) {
      m.k = next;
      m.emit(applyBinary(operator, l.valueOf(input, env), rightValue));
      return;
    }
    m.evalOp(l, input, env, _BinaryLeftFrame(operator, rightValue, next));
  }
}

final class _BinaryRightFrame extends Frame {
  const _BinaryRightFrame(this.binary, this.input, this.env, super.next);

  final BinaryOp binary;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) =>
      binary._afterRight(m, value, input, env, next);
}

final class _BinaryLeftFrame extends Frame {
  const _BinaryLeftFrame(this.operator, this.rightValue, super.next);

  final BinaryOperator operator;
  final Object? rightValue;

  @override
  void resume(Machine m, Object? value) =>
      m.emit(applyBinary(operator, value, rightValue));
}

/// `and` / `or`: the left operand varies slowest, and the right operand is
/// evaluated only when the left does not decide the result.
final class LogicOp extends Op {
  const LogicOp(this.left, this.right, {required this.isAnd});

  final Op left;
  final Op right;
  final bool isAnd;

  @override
  void exec(Machine m) {
    m.k = _LogicFrame(this, m.input, m.env, m.k);
    m.op = left;
  }
}

final class _LogicFrame extends Frame {
  const _LogicFrame(this.logic, this.input, this.env, super.next);

  final LogicOp logic;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) {
    if (isTruthy(value) != logic.isAnd) {
      m.emit(!logic.isAnd);
      return;
    }
    m.evalOp(logic.right, input, env, _TruthFrame(next));
  }
}

final class _TruthFrame extends Frame {
  const _TruthFrame(super.next);

  @override
  void resume(Machine m, Object? value) => m.emit(isTruthy(value));
}

/// `if c then t else e end`; a missing `else` is the identity.
final class IfOp extends Op {
  const IfOp(this.condition, this.then, this.otherwise);

  final Op condition;
  final Op then;
  final Op otherwise;

  @override
  void exec(Machine m) {
    m.k = _IfFrame(this, m.input, m.env, m.k);
    m.op = condition;
  }
}

final class _IfFrame extends Frame {
  const _IfFrame(this.branch, this.input, this.env, super.next);

  final IfOp branch;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) => m.evalOp(
    isTruthy(value) ? branch.then : branch.otherwise,
    input,
    env,
    next,
  );
}

/// `select(f)`: the input, once for every truthy output of `f`.
final class SelectOp extends Op {
  const SelectOp(this.predicate);

  final Op predicate;

  @override
  void exec(Machine m) {
    m.k = _SelectFrame(m.input, m.k);
    m.op = predicate;
  }
}

final class _SelectFrame extends Frame {
  const _SelectFrame(this.input, super.next);

  final Object? input;

  @override
  void resume(Machine m, Object? value) {
    if (isTruthy(value)) {
      m.emit(input);
    } else {
      m.fail();
    }
  }
}

/// `left // right`: every truthy output of `left`; `right` only when `left`
/// finishes without one. Errors in `left` are not suppressed.
final class AlternativeOp extends Op {
  const AlternativeOp(this.left, this.right);

  final Op left;
  final Op right;

  @override
  void exec(Machine m) {
    final found = _Found();
    m.choices.add(_FallbackChoice(right, m.input, m.env, m.k, found));
    m.k = _AlternativeFrame(found, m.k);
    m.op = left;
  }
}

/// One-shot flag of a single `//` activation.
final class _Found {
  bool value = false;
}

final class _AlternativeFrame extends Frame {
  const _AlternativeFrame(this.found, super.next);

  final _Found found;

  @override
  void resume(Machine m, Object? value) {
    if (isTruthy(value)) {
      found.value = true;
      m.emit(value);
    } else {
      m.fail();
    }
  }
}

final class _FallbackChoice extends Choice {
  const _FallbackChoice(this.op, this.input, this.env, this.k, this.found);

  final Op op;
  final Object? input;
  final Env? env;
  final Frame? k;
  final _Found found;

  @override
  void resume(Machine m) {
    if (found.value) {
      m.fail();
    } else {
      m.evalOp(op, input, env, k);
    }
  }
}

// ---------------------------------------------------------------------------
// try / catch.

/// `try body catch handler`, `try body`, and the postfix `?`.
///
/// A [_TryMarker] sits on the choice stack below everything the body leaves
/// there. Each output of the body pushes a [_PassThrough] above it, which
/// stays until the machine backtracks into the body. An error raised while
/// the body runs reaches the marker with no pass-through in between and is
/// handled; an error raised downstream of an output crosses the pass-through
/// first, which marks it so the marker lets it continue, exactly as jq's
/// `TRY_END` protects the code after a `try`.
final class TryOp extends Op {
  const TryOp(this.body, this.handler);

  final Op body;
  final Op? handler;

  @override
  void exec(Machine m) {
    m.choices.add(_TryMarker(handler, m.env, m.k));
    m.k = _TryExitFrame(m.k);
    m.op = body;
  }
}

final class _TryExitFrame extends Frame {
  const _TryExitFrame(super.next);

  @override
  void resume(Machine m, Object? value) {
    m.choices.add(const _PassThrough());
    m.emit(value);
  }
}

final class _PassThrough extends Choice {
  const _PassThrough();

  @override
  void resume(Machine m) => m.fail();

  @override
  bool onRaise(Machine m) {
    m.wraps++;
    return false;
  }
}

final class _TryMarker extends Choice {
  const _TryMarker(this.handler, this.env, this.k);

  final Op? handler;
  final Env? env;
  final Frame? k;

  @override
  void resume(Machine m) => m.fail();

  @override
  bool onRaise(Machine m) {
    if (m.wraps > 0) {
      m.wraps--;
      return false;
    }
    final h = handler;
    if (h == null) {
      m.fail();
    } else {
      m.evalOp(h, m.error, env, k);
    }
    return true;
  }
}
