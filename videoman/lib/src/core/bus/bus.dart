import 'dart:async';

/// A value-holding broadcast bus: replays the current value to new listeners
/// and drops consecutive duplicates.
///
/// 持值的广播总线：新订阅者立即收到当前值，并自动丢弃连续重复值。
class VmBus<T> {
  final StreamController<T> _controller = StreamController<T>.broadcast();

  /// The current value; updated by [emit].
  ///
  /// 当前值；由 [emit] 更新。
  T _value;

  /// Creates a bus seeded with [initial].
  ///
  /// 用 [initial] 作为初始值创建总线。
  VmBus(T initial) : _value = initial;

  /// The current value.
  ///
  /// 当前值。
  T get value => _value;

  /// Broadcast stream that starts with the current value.
  ///
  /// Uses [Stream.multi] rather than an `async*` generator so that the
  /// replayed value is delivered synchronously to each new listener,
  /// instead of being delayed by a microtask (which would race with
  /// synchronous [emit] calls made right after subscribing).
  ///
  /// 以当前值开头的广播流。
  ///
  /// 用 [Stream.multi] 而非 `async*` 生成器，让每个新订阅者同步收到重放值，
  /// 避免因微任务延迟而与订阅后紧接的同步 [emit] 调用产生竞态。
  Stream<T> get stream => Stream<T>.multi((controller) {
        controller.add(_value);
        final sub = _controller.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = sub.cancel;
      });

  /// Publishes [next]; no-op when equal to the current value.
  ///
  /// 发布 [next]；与当前值相等时不发。
  void emit(T next) {
    if (next == _value) return;
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Stream of [pick] results, emitting only when the picked value changes.
  ///
  /// [pick] 结果的流，仅在被选中的值变化时才发。
  Stream<R> select<R>(R Function(T value) pick) => stream.map(pick).distinct();

  /// Closes the underlying controller.
  ///
  /// 关闭底层控制器。
  Future<void> close() => _controller.close();
}

/// Rate-limits [source] to at most one value per [window], always emitting the
/// first value immediately and the last value of a window at its end.
///
/// 把 [source] 限流为每 [window] 最多一个值：首值立即发，窗口内的末值在窗口结束时发。
Stream<T> throttleStream<T>(Stream<T> source, Duration window) {
  StreamController<T>? out;
  StreamSubscription<T>? sub;
  Timer? timer;
  T? pending;
  var hasPending = false;

  // Flushes the pending value (if any) and restarts the window timer.
  //
  // 发出待发值（如有）并重启窗口计时器。
  void flush() {
    timer = null;
    if (!hasPending) return;
    hasPending = false;
    out!.add(pending as T);
    timer = Timer(window, flush);
  }

  // Must be a broadcast controller, not a single-subscription one: `VmEngine`
  // wraps this stream's output in `.asBroadcastStream()` so both the seek bar
  // and the gesture layer can each hold their own subscription. If the
  // listener count here ever drops to zero and rises again (e.g. a widget
  // rebuild briefly tears down and recreates a subscriber), `asBroadcastStream`
  // re-`listen()`s the underlying stream — which throws on a
  // single-subscription controller ("Stream has already been listened to"),
  // permanently killing position updates until the app restarts. A broadcast
  // controller supports being listened to across repeated zero-to-one
  // transitions, so this class of failure cannot happen.
  //
  // 必须是广播型 controller，不能是单订阅型：`VmEngine` 会把本函数的输出流再包一层
  // `.asBroadcastStream()`，让进度条与手势层各自持有独立订阅。若这里的监听数一度
  // 降到零、随后又有新订阅（例如一次 widget 重建短暂拆掉又重建了订阅者），
  // `asBroadcastStream` 会对底层流重新调用一次 `listen()`——而单订阅 controller
  // 只能被监听一次，第二次会抛出异常（"Stream has already been listened to"），
  // 导致位置更新永久断流，直到重启 app。广播型 controller 支持反复经历"零监听
  // 到有监听"的转换，从根上排除这类故障。
  out = StreamController<T>.broadcast(
    onListen: () {
      sub = source.listen(
        (v) {
          if (timer == null) {
            out!.add(v);
            timer = Timer(window, flush);
          } else {
            pending = v;
            hasPending = true;
          }
        },
        onError: (Object e, StackTrace s) => out!.addError(e, s),
        onDone: () => out!.close(),
      );
    },
    onCancel: () async {
      // Resets the whole state machine, not just the timer object: a
      // subsequent 0-to-1 listener transition calls `onListen` again and must
      // start clean. Leaving a stale non-null `timer` behind would make the
      // very first post-resubscribe event take the "already have a pending
      // flush" branch forever — queuing into `pending` with nothing left to
      // ever flush it.
      //
      // 重置整个状态机，而不只是计时器对象：后续一次监听数从 0 回到 1 的转变
      // 会再次调用 `onListen`，必须从干净状态开始。若只留下一个残留的非空
      // `timer`，重新订阅后的第一个事件就会永远走进"已有待发 flush"分支——
      // 存进 `pending` 却再也没有东西去把它发出去。
      timer?.cancel();
      timer = null;
      pending = null;
      hasPending = false;
      await sub?.cancel();
    },
  );
  return out.stream;
}
