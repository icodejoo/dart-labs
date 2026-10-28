import 'dart:async';
import 'package:dioman/pipeline.dart';

/// 可确定推进的时钟，不使用真实睡眠。
class FakeClock implements DiomanClock {
  /// 创建起点为 Unix epoch 的时钟。
  FakeClock();

  /// 当前虚拟时间。
  DateTime _now = DateTime.fromMillisecondsSinceEpoch(0);

  /// 所有尚未触发的计时器。
  final _timers = <_FakeTimer>[];

  /// 未清理计时器数。
  int get pendingTimers => _timers.where((t) => t.isActive).length;

  /// 返回虚拟时间。
  @override
  DateTime now() => _now;

  /// 登记单次计时器。
  @override
  Timer createTimer(Duration duration, void Function() callback) {
    final timer = _FakeTimer(_now.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  /// 推进 [duration]，依到期顺序执行回调，回调可创建新计时器。
  void elapse(Duration duration) {
    final end = _now.add(duration);
    while (true) {
      final due = _timers
          .where((t) => t.isActive && !t.deadline.isAfter(end))
          .toList()
        ..sort((a, b) => a.deadline.compareTo(b.deadline));
      if (due.isEmpty) break;
      final timer = due.first;
      _now = timer.deadline;
      timer.fire();
    }
    _timers.removeWhere((t) => !t.isActive);
    _now = end;
  }
}

/// 单次虚拟计时器。
class _FakeTimer implements Timer {
  /// 保存截止时间及回调。
  _FakeTimer(this.deadline, this.callback);

  /// 截止时间。
  final DateTime deadline;

  /// 用户回调。
  final void Function() callback;

  /// 是否仍登记。
  bool _active = true;

  /// 触发次数。
  int _tick = 0;

  /// 当前活动状态。
  @override
  bool get isActive => _active;

  /// 已触发次数。
  @override
  int get tick => _tick;

  /// 取消后不再触发。
  @override
  void cancel() => _active = false;

  /// 触发一次并关闭。
  void fire() {
    _active = false;
    _tick++;
    callback();
  }
}
