import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// One process-wide ticker with staggered subscriber sampling.
/// 全进程唯一 ticker，按订阅者相位错开采样。
final class SharedAnimationClock {
  /// Creates the shared clock. / 创建共享时钟。
  SharedAnimationClock._();

  /// Shared clock instance. / 共享时钟实例。
  static final instance = SharedAnimationClock._();

  /// The sole active ticker. / 唯一的活动 ticker。
  Ticker? _ticker;

  /// Latest global ticker time. / 最近的全局 ticker 时间。
  Duration _elapsed = Duration.zero;

  /// Active controller subscriptions. / 活动控制器订阅。
  final _subscriptions = <ClockSubscription>[];

  /// Display-frame sequence. / 显示帧序号。
  int _tickCount = 0;

  /// Monotonic phase allocator. / 单调递增的相位分配器。
  int _nextPhase = 0;

  /// Latest global time since the last idle state. / 最近一次空闲后的全局时间。
  Duration get elapsed => _elapsed;

  /// Active subscribers, rather than attached widgets. / 活动订阅者数，而非挂载控件数。
  int get subscriberCount => _subscriptions.length;

  /// Registers a callback; the first tick always establishes its baseline.
  /// 注册回调；首个 tick 始终送达，以建立精确基线。
  ClockSubscription subscribe(
    ValueChanged<Duration> onTick, {
    required int Function(int concurrency) frameDivisor,
  }) {
    final subscription = ClockSubscription._(
      onTick,
      frameDivisor,
      _nextPhase++,
    );
    _subscriptions.add(subscription);
    _ticker ??= Ticker(_onTick)..start();
    return subscription;
  }

  /// Removes a subscription and releases an idle ticker.
  /// 移除订阅，并释放空闲 ticker。
  void unsubscribe(ClockSubscription subscription) {
    subscription._active = false;
    _subscriptions.remove(subscription);
    if (_subscriptions.isNotEmpty) return;
    _ticker?.dispose();
    _ticker = null;
    _elapsed = Duration.zero;
    _tickCount = 0;
  }

  /// Delivers eligible ticks from a mutation-safe snapshot.
  /// 使用可安全增删订阅的快照派发符合条件的 tick。
  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    final tick = ++_tickCount;
    final concurrency = _subscriptions.length;
    for (final subscription in List<ClockSubscription>.of(_subscriptions)) {
      if (!subscription._active) continue;
      final divisor = subscription.frameDivisor(concurrency);
      if (!subscription._first &&
          divisor > 1 &&
          (tick + subscription.phase) % divisor != 0) {
        continue;
      }
      subscription._first = false;
      subscription.onTick(elapsed);
    }
  }
}

/// A controller's registration with the shared clock.
/// 控制器在共享时钟上的注册记录。
final class ClockSubscription {
  /// Creates an active registration. / 创建活动注册。
  ClockSubscription._(this.onTick, this.frameDivisor, this.phase);

  /// Callback for sampled global time. / 采样的全局时间回调。
  final ValueChanged<Duration> onTick;

  /// Live frame divisor at current concurrency. / 当前并发下的实时跳帧除数。
  final int Function(int concurrency) frameDivisor;

  /// Staggering phase. / 错帧相位。
  final int phase;

  /// Whether this registration remains subscribed. / 此记录是否仍在订阅。
  bool _active = true;

  /// Whether the next delivery anchors the local clock. / 下次派发是否锚定本地时钟。
  bool _first = true;
}
