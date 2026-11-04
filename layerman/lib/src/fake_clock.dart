import 'dart:async';

import 'overlay_types.dart';

/// 同时控制当前时间及单次计时器的确定性时钟，不依赖 Flutter 绑定。
/// 纯 Dart test() 中调用 advance 推进时间，再用
/// `await Future<void>.delayed(Duration.zero)` 排空 Future 微任务续体。
/// 例如 clock.advance(const Duration(seconds: 1))；pendingTimers 可检查泄漏。
class FakeOverlayClock extends OverlayClock {
  /// 从 [start] 开始，默认 DateTime(2000)。
  FakeOverlayClock([DateTime? start]) : _now = start ?? DateTime(2000);

  /// 当前模拟时间。
  DateTime _now;

  /// 尚未触发或取消的计时器，按创建顺序保存。
  final _timers = <_FakeTimer>[];

  /// 防止嵌套推进将时间倒退。
  bool _advancing = false;

  @override
  DateTime now() => _now;

  /// 尚未触发且未取消的计时器数量。
  int get pendingTimers => _timers.length;

  /// 创建单次计时器，返回可取消的 Timer。
  @override
  Timer createTimer(Duration duration, void Function() callback) {
    final timer = _FakeTimer(this,
        _now.add(duration.isNegative ? Duration.zero : duration), callback);
    _timers.add(timer);
    return timer;
  }

  /// 推进非负时长，依次触发窗口内的计时器，包含回调中新建的计时器。
  /// 同时到期按创建顺序触发；负时长抛 ArgumentError，嵌套推进抛 StateError。
  /// 回调抛错会向调用方传播，当前时间停在该计时器的到期时刻。
  void advance(Duration d) {
    if (d.isNegative) throw ArgumentError.value(d, 'd', '不能倒退时间');
    if (_advancing) throw StateError('不能嵌套推进时钟');
    _advancing = true;
    final end = _now.add(d);
    try {
      while (true) {
        _FakeTimer? next;
        for (final timer in _timers) {
          if (timer.deadline.isAfter(end)) continue;
          if (next == null || timer.deadline.isBefore(next.deadline)) {
            next = timer;
          }
        }
        if (next == null) break;
        _now = next.deadline;
        _timers.remove(next);
        next._active = false;
        next._tick = 1;
        next.callback();
      }
      _now = end;
    } finally {
      _advancing = false;
    }
  }
}

/// 实现单次 Timer 协议，触发前 tick 为零，触发后为一。
class _FakeTimer implements Timer {
  /// 绑定所属时钟、到期时刻和回调。
  _FakeTimer(this.clock, this.deadline, this.callback);

  /// 用于取消时从待触发集合移除。
  final FakeOverlayClock clock;

  /// 到期时刻。
  final DateTime deadline;

  /// 单次触发的回调。
  final void Function() callback;

  /// 是否仍等待触发。
  bool _active = true;

  /// 已触发次数。
  int _tick = 0;

  /// 是否已激活，包含解析、展示和退场。
  @override
  bool get isActive => _active;

  /// 计时器触发次数，未触发为零，触发后为一。
  @override
  int get tick => _tick;

  /// 取消本计时器，重复取消无操作。
  @override
  void cancel() {
    _active = false;
    clock._timers.remove(this);
  }
}
