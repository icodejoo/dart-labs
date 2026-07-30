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

  out = StreamController<T>(
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
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return out.stream;
}
