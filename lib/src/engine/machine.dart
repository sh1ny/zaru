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

/// Immutable lexical environment: one cell per binding.
///
/// A cell holds a variable's value, a [Closure] (a filter parameter), the
/// identity of a `label` activation, or nothing at all for a function
/// definition, whose cell only marks where its body's scope begins.
final class Env {
  const Env(this.value, this.parent);

  final Object? value;
  final Env? parent;
}

Env _cell(Env? env, int hops) {
  var cell = env!;
  for (var i = 0; i < hops; i++) {
    cell = cell.parent!;
  }
  return cell;
}

Object? _lookup(Env? env, int hops) => _cell(env, hops).value;

/// A lexical break: unwinds to the `label` activation it names and is never
/// seen by `try`, `?` or `//`. It is deliberately not a [JqError].
final class JqBreak implements Exception {
  const JqBreak(this.label);

  /// The unique identity of the `label` activation the break targets.
  final Object label;
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

  /// The label identity of the break being unwound, or null when the unwinding
  /// signal is a data error.
  Object? breaking;

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
                if (breaking != null) {
                  throw StateError('a break escaped its label');
                }
                throw ZaruRuntimeError(exportValue(error));
              }
          }
        }
      } on JqError catch (e) {
        error = e.value;
        breaking = null;
        wraps = 0;
        mode = _raise;
      } on JqBreak catch (e) {
        error = null;
        breaking = e.label;
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

/// `tostring`: strings as they are, everything else as compact JSON text.
final class TostringOp extends PureOp {
  const TostringOp();

  @override
  Object? valueOf(Object? input, Env? env) => stringify(input);
}

/// The bytecoded `range(start; end)`: the start value itself, then every
/// successor by one, while it is below the end. The start varies slowest.
final class RangeOp extends Op {
  const RangeOp(this.from, this.to);

  final Op from;
  final Op to;

  @override
  void exec(Machine m) {
    m.k = _RangeFromFrame(to, m.input, m.env, m.k);
    m.op = from;
  }
}

final class _RangeFromFrame extends Frame {
  const _RangeFromFrame(this.to, this.input, this.env, super.next);

  final Op to;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? start) =>
      m.evalOp(to, input, env, _RangeToFrame(start, next));
}

final class _RangeToFrame extends Frame {
  const _RangeToFrame(this.start, super.next);

  final Object? start;

  @override
  void resume(Machine m, Object? end) {
    if (!isNumber(start) || !isNumber(end)) {
      throw const JqError('Range bounds must be numeric');
    }
    final first = numberValue(start);
    final limit = numberValue(end);
    if (first >= limit) {
      m.fail();
      return;
    }
    m.choices.add(_RangeChoice(first + 1, limit, next));
    m.emit(start);
  }
}

/// The remaining counter of one `range` activation, advanced in place and
/// pushed again for as long as the stream is pulled.
final class _RangeChoice extends Choice {
  _RangeChoice(this.current, this.limit, this.k);

  double current;
  final double limit;
  final Frame? k;

  @override
  void resume(Machine m) {
    final value = current;
    if (value >= limit) {
      m.fail();
      return;
    }
    current = value + 1;
    m.choices.add(this);
    m.k = k;
    m.emit(computed(value));
  }
}

/// The bytecoded `last(f)`: the final output of `f`, or no output at all when
/// `f` has none.
final class LastOp extends Op {
  const LastOp(this.body);

  final Op body;

  @override
  void exec(Machine m) {
    final state = _LastState();
    m.choices.add(_LastDoneChoice(state, m.k));
    m.k = _LastStoreFrame(state);
    m.op = body;
  }
}

final class _LastState {
  bool found = false;
  Object? value;
}

final class _LastStoreFrame extends Frame {
  const _LastStoreFrame(this.state) : super(null);

  final _LastState state;

  @override
  void resume(Machine m, Object? value) {
    state.found = true;
    state.value = value;
    m.fail();
  }
}

final class _LastDoneChoice extends Choice {
  const _LastDoneChoice(this.state, this.k);

  final _LastState state;
  final Frame? k;

  @override
  void resume(Machine m) {
    if (!state.found) {
      m.fail();
      return;
    }
    m.k = k;
    m.emit(state.value);
  }
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
    // A break is control flow, not an error: it is never caught here.
    if (m.breaking != null) return false;
    final h = handler;
    if (h == null) {
      m.fail();
    } else {
      m.evalOp(h, m.error, env, k);
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Functions: definitions, closures and calls.

/// A filter argument: the expression and the environment of its call site.
final class Closure {
  const Closure(this.op, this.env);

  final Op op;
  final Env? env;
}

/// The body of one `def`, shared by every call. The compiler assigns [body]
/// exactly once, before any machine runs (a body refers back to its own
/// definition, so it cannot be built first).
final class FunctionDef {
  FunctionDef(this.name);

  final String name;
  late Op body;
}

/// `def f: ...; rest`: pushes the definition's cell and continues with the
/// rest of the expression. The cell is the lexical anchor of the body: a call
/// evaluates the body in the environment that starts at this cell.
final class DefineOp extends Op {
  const DefineOp(this.rest);

  final Op rest;

  @override
  void exec(Machine m) {
    m.env = Env(null, m.env);
    m.op = rest;
  }
}

/// A call of a defined function. The arguments become closures over the
/// call-site environment; the body runs in the definition's environment plus
/// one cell per argument, with the caller's input and continuation, so a call
/// in tail position leaves nothing behind.
final class CallOp extends Op {
  const CallOp(this.hops, this.function, this.arguments);

  final int hops;
  final FunctionDef function;
  final List<Op> arguments;

  @override
  void exec(Machine m) {
    final caller = m.env;
    m.env = _withArguments(_cell(caller, hops), caller, arguments);
    m.op = function.body;
  }
}

Env? _withArguments(Env? base, Env? caller, List<Op> arguments) {
  var env = base;
  for (final argument in arguments) {
    // A parameter passed on as it is keeps its closure, so recursion that
    // forwards its arguments does not nest a closure per level.
    env = Env(
      argument is ParamCallOp
          ? _lookup(caller, argument.hops)
          : Closure(argument, caller),
      env,
    );
  }
  return env;
}

/// The anchor cell of every hosted builtin: a builtin refers to nothing of the
/// program it is called from, so all calls share this one cell.
const Env _builtinBase = Env(null, null);

/// A call of a builtin defined in jq (see `jq_builtins.dart`). The body runs
/// in [_builtinBase] plus one cell per argument, a tail call like [CallOp].
final class BuiltinCallOp extends Op {
  const BuiltinCallOp(this.function, this.arguments);

  final FunctionDef function;
  final List<Op> arguments;

  @override
  void exec(Machine m) {
    m.env = _withArguments(_builtinBase, m.env, arguments);
    m.op = function.body;
  }
}

/// A use of a filter parameter: its closure runs with the current input.
final class ParamCallOp extends Op {
  const ParamCallOp(this.hops);

  final int hops;

  @override
  void exec(Machine m) {
    final closure = _lookup(m.env, hops)! as Closure;
    m.env = closure.env;
    m.op = closure.op;
  }
}

// ---------------------------------------------------------------------------
// label / break.

/// `label $name | body`: every activation has its own identity.
final class LabelOp extends Op {
  const LabelOp(this.body);

  final Op body;

  @override
  void exec(Machine m) {
    final identity = Object();
    m.choices.add(_LabelMarker(identity));
    m.env = Env(identity, m.env);
    m.op = body;
  }
}

/// Sits on the choice stack below everything the body leaves there, so that a
/// break to this activation discards the body's remaining alternatives and
/// backtracks into whatever was pending around the label.
final class _LabelMarker extends Choice {
  const _LabelMarker(this.identity);

  final Object identity;

  @override
  void resume(Machine m) => m.fail();

  @override
  bool onRaise(Machine m) {
    if (!identical(m.breaking, identity)) return false;
    m.breaking = null;
    m.fail();
    return true;
  }
}

/// `break $name`.
final class BreakOp extends Op {
  const BreakOp(this.hops);

  final int hops;

  @override
  void exec(Machine m) => throw JqBreak(_lookup(m.env, hops)!);
}

// ---------------------------------------------------------------------------
// Destructuring.

const Object _unset = _Unset();

final class _Unset {
  const _Unset();
}

/// A compiled destructuring pattern. Variables are numbered slots shared by
/// every alternative of one binder.
sealed class Matcher {
  const Matcher();
}

final class VarMatcher extends Matcher {
  const VarMatcher(this.slot);

  final int slot;
}

final class ArrayMatcher extends Matcher {
  const ArrayMatcher(this.elements);

  final List<Matcher> elements;
}

/// `key: sub`, `$name` (binds [bindSlot]) or `$name: sub` (both).
final class ObjectEntryMatcher {
  const ObjectEntryMatcher(this.key, {this.bindSlot, this.sub});

  final Op key;
  final int? bindSlot;
  final Matcher? sub;
}

final class ObjectMatcher extends Matcher {
  const ObjectMatcher(this.entries);

  final List<ObjectEntryMatcher> entries;
}

sealed class _Task {
  const _Task(this.next);

  final _Task? next;
}

final class _ValueTask extends _Task {
  const _ValueTask(this.matcher, this.value, super.next);

  final Matcher matcher;
  final Object? value;
}

final class _ElementTask extends _Task {
  const _ElementTask(this.matcher, this.parent, this.index, super.next);

  final Matcher matcher;
  final Object? parent;
  final int index;
}

final class _EntryTask extends _Task {
  const _EntryTask(this.entry, this.parent, super.next);

  final ObjectEntryMatcher entry;
  final Object? parent;
}

/// Matches a value against one pattern, or against `?//` alternatives, and
/// hands the variable values to the frame it was started with.
///
/// The match is a persistent list of pending tasks, so a key expression that
/// generates several values backtracks to an unchanged state. Array elements
/// are matched last to first, as jq compiles them. Without alternatives the
/// first assignment to a repeated name wins; with them every alternative
/// writes the same slot, starting from null, and the last write wins. With
/// alternatives, an error raised anywhere after the match began (in the
/// pattern, the body, or downstream of the whole expression) retries the
/// next alternative; the error of the last alternative is the real one.
final class Binder {
  const Binder(this.alternatives, this.slotCount);

  final List<Matcher> alternatives;
  final int slotCount;

  bool get _isAlternation => alternatives.length > 1;

  /// Starts matching [value]; key expressions run in [env]. The slot values
  /// (a `List<Object?>`) are delivered to [k].
  void start(Machine m, Object? value, Env? env, Frame? k) =>
      _begin(m, 0, value, env, k);

  void _begin(Machine m, int index, Object? value, Env? env, Frame? k) {
    if (index < alternatives.length - 1) {
      m.choices.add(_RetryChoice(this, index + 1, value, env, k));
    }
    final slots = List<Object?>.filled(
      slotCount,
      _isAlternation ? null : _unset,
      growable: false,
    );
    _run(m, _ValueTask(alternatives[index], value, null), slots, env, k);
  }

  List<Object?> _assign(List<Object?> slots, int slot, Object? value) {
    if (!_isAlternation && !identical(slots[slot], _unset)) return slots;
    final copy = List<Object?>.of(slots, growable: false);
    copy[slot] = value;
    return copy;
  }

  void _run(
    Machine m,
    _Task? first,
    List<Object?> slotsIn,
    Env? env,
    Frame? k,
  ) {
    var tasks = first;
    var slots = slotsIn;
    while (tasks != null) {
      final task = tasks;
      tasks = task.next;
      final Matcher matcher;
      final Object? value;
      switch (task) {
        case _ValueTask():
          matcher = task.matcher;
          value = task.value;
        case _ElementTask():
          matcher = task.matcher;
          value = indexValue(task.parent, task.index);
        case _EntryTask():
          final keyOp = task.entry.key;
          if (keyOp is ConstOp) {
            final picked = indexValue(task.parent, keyOp.value);
            (tasks, slots) = _picked(task.entry, picked, tasks, slots);
            continue;
          }
          m.evalOp(
            keyOp,
            task.parent,
            env,
            _KeyFrame(this, task, tasks, slots, env, k),
          );
          return;
      }
      switch (matcher) {
        case VarMatcher(:final slot):
          slots = _assign(slots, slot, value);
        case ArrayMatcher(:final elements):
          for (var i = 0; i < elements.length; i++) {
            tasks = _ElementTask(elements[i], value, i, tasks);
          }
        case ObjectMatcher(:final entries):
          for (var i = entries.length - 1; i >= 0; i--) {
            tasks = _EntryTask(entries[i], value, tasks);
          }
      }
    }
    m.k = k;
    m.emit(slots);
  }

  (_Task?, List<Object?>) _picked(
    ObjectEntryMatcher entry,
    Object? picked,
    _Task? tasks,
    List<Object?> slots,
  ) {
    var nextSlots = slots;
    var nextTasks = tasks;
    final slot = entry.bindSlot;
    if (slot != null) nextSlots = _assign(nextSlots, slot, picked);
    final sub = entry.sub;
    if (sub != null) nextTasks = _ValueTask(sub, picked, nextTasks);
    return (nextTasks, nextSlots);
  }
}

final class _KeyFrame extends Frame {
  const _KeyFrame(
    this.binder,
    this.task,
    this.tasks,
    this.slots,
    this.env,
    this.k,
  ) : super(null);

  final Binder binder;
  final _EntryTask task;
  final _Task? tasks;
  final List<Object?> slots;
  final Env? env;
  final Frame? k;

  @override
  void resume(Machine m, Object? key) {
    final picked = indexValue(task.parent, key);
    final (nextTasks, nextSlots) = binder._picked(
      task.entry,
      picked,
      tasks,
      slots,
    );
    binder._run(m, nextTasks, nextSlots, env, k);
  }
}

final class _RetryChoice extends Choice {
  const _RetryChoice(this.binder, this.index, this.value, this.env, this.k);

  final Binder binder;
  final int index;
  final Object? value;
  final Env? env;
  final Frame? k;

  @override
  void resume(Machine m) => m.fail();

  @override
  bool onRaise(Machine m) {
    // A break is not an error and passes through.
    if (m.breaking != null) return false;
    binder._begin(m, index, value, env, k);
    return true;
  }
}

Env? _extend(Env? env, List<Object?> slots) {
  var extended = env;
  for (final value in slots) {
    extended = Env(value, extended);
  }
  return extended;
}

/// `source as pattern | body` for anything but a single plain variable.
final class DestructureOp extends Op {
  const DestructureOp(this.source, this.binder, this.body);

  final Op source;
  final Binder binder;
  final Op body;

  @override
  void exec(Machine m) {
    m.k = _DestructureSourceFrame(this, m.input, m.env, m.k);
    m.op = source;
  }
}

final class _DestructureSourceFrame extends Frame {
  const _DestructureSourceFrame(this.op, this.input, this.env, super.next);

  final DestructureOp op;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) => op.binder.start(
    m,
    value,
    env,
    _DestructureBodyFrame(op.body, input, env, next),
  );
}

final class _DestructureBodyFrame extends Frame {
  const _DestructureBodyFrame(this.body, this.input, this.env, super.next);

  final Op body;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? slots) =>
      m.evalOp(body, input, _extend(env, slots! as List<Object?>), next);
}

// ---------------------------------------------------------------------------
// reduce and foreach.

/// The one mutable cell of a reduction: the accumulator of a single
/// activation. It is private to the machine that created it; the values it
/// holds are immutable engine values.
final class _Accumulator {
  _Accumulator(this.value);

  Object? value;
}

/// `reduce source as pattern (init; update)`: for every output of `init`,
/// feeds each source output through `update` (the accumulator becomes the
/// last output of the update, or null when there is none) and yields the final
/// accumulator once the source is exhausted.
final class ReduceOp extends Op {
  const ReduceOp(this.source, this.binder, this.init, this.update);

  final Op source;
  final Binder binder;
  final Op init;
  final Op update;

  @override
  void exec(Machine m) => m.evalOp(
    init,
    m.input,
    m.env,
    _ReduceInitFrame(this, m.input, m.env, m.k),
  );
}

final class _ReduceInitFrame extends Frame {
  const _ReduceInitFrame(this.op, this.input, this.env, super.next);

  final ReduceOp op;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) {
    final state = _Accumulator(value);
    m.choices.add(_ReduceDoneChoice(state, next));
    m.evalOp(op.source, input, env, _ReduceItemFrame(op, state, env));
  }
}

final class _ReduceItemFrame extends Frame {
  const _ReduceItemFrame(this.op, this.state, this.env) : super(null);

  final ReduceOp op;
  final _Accumulator state;
  final Env? env;

  @override
  void resume(Machine m, Object? value) =>
      op.binder.start(m, value, env, _ReduceBodyFrame(op, state, env));
}

final class _ReduceBodyFrame extends Frame {
  const _ReduceBodyFrame(this.op, this.state, this.env) : super(null);

  final ReduceOp op;
  final _Accumulator state;
  final Env? env;

  @override
  void resume(Machine m, Object? slots) {
    // jq moves the accumulator out: an update without output leaves null.
    final accumulator = state.value;
    state.value = null;
    m.evalOp(
      op.update,
      accumulator,
      _extend(env, slots! as List<Object?>),
      _ReduceStoreFrame(state),
    );
  }
}

final class _ReduceStoreFrame extends Frame {
  const _ReduceStoreFrame(this.state) : super(null);

  final _Accumulator state;

  @override
  void resume(Machine m, Object? value) {
    state.value = value;
    m.fail();
  }
}

final class _ReduceDoneChoice extends Choice {
  const _ReduceDoneChoice(this.state, this.k);

  final _Accumulator state;
  final Frame? k;

  @override
  void resume(Machine m) {
    m.k = k;
    m.emit(state.value);
  }
}

/// `foreach source as pattern (init; update; extract)`: for every output of
/// `init`, feeds each source output through `update`, keeps the last update
/// output as the next state, and yields every output of `extract` for each
/// update output. A missing extract is the state itself.
final class ForeachOp extends Op {
  const ForeachOp(
    this.source,
    this.binder,
    this.init,
    this.update,
    this.extract,
  );

  final Op source;
  final Binder binder;
  final Op init;
  final Op update;
  final Op? extract;

  @override
  void exec(Machine m) => m.evalOp(
    init,
    m.input,
    m.env,
    _ForeachInitFrame(this, m.input, m.env, m.k),
  );
}

final class _ForeachInitFrame extends Frame {
  const _ForeachInitFrame(this.op, this.input, this.env, super.next);

  final ForeachOp op;
  final Object? input;
  final Env? env;

  @override
  void resume(Machine m, Object? value) {
    final state = _Accumulator(value);
    m.evalOp(op.source, input, env, _ForeachItemFrame(op, state, env, next));
  }
}

final class _ForeachItemFrame extends Frame {
  const _ForeachItemFrame(this.op, this.state, this.env, super.next);

  final ForeachOp op;
  final _Accumulator state;
  final Env? env;

  @override
  void resume(Machine m, Object? value) =>
      op.binder.start(m, value, env, _ForeachBodyFrame(op, state, env, next));
}

final class _ForeachBodyFrame extends Frame {
  const _ForeachBodyFrame(this.op, this.state, this.env, super.next);

  final ForeachOp op;
  final _Accumulator state;
  final Env? env;

  @override
  void resume(Machine m, Object? slots) {
    final accumulator = state.value;
    state.value = null;
    final bodyEnv = _extend(env, slots! as List<Object?>);
    m.evalOp(
      op.update,
      accumulator,
      bodyEnv,
      _ForeachExtractFrame(op, state, bodyEnv, next),
    );
  }
}

final class _ForeachExtractFrame extends Frame {
  const _ForeachExtractFrame(this.op, this.state, this.env, super.next);

  final ForeachOp op;
  final _Accumulator state;
  final Env? env;

  @override
  void resume(Machine m, Object? value) {
    state.value = value;
    final extract = op.extract;
    if (extract == null) {
      m.emit(value);
    } else {
      m.evalOp(extract, value, env, next);
    }
  }
}
