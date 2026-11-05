import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show internal;

import '../core/clock.dart';
import '../core/plugin_base.dart';
import '../counter/plugin.dart';
import '../counter/types.dart';

/// 所有卡片共用的惰性任务组；destroy 后自动重建。
final _cardMotion = LazyDefault<Counter>(_CardMotion.new);

/// 卡片在入队时已有初值；从启动时刻计时，休眠首帧不丢时间。
class _CardMotion extends Counter {
  _CardMotion() : super(name: '_countman.cardMotion');

  @override
  void enqueue(CounterTask task) {
    task.started = true;
    task.startFired = true;
    task.frameClockMicros = CountmanClock.system.monotonicMicros();
    super.enqueue(task);
  }
}

/// 共享 Counter 驱动的线性翻牌进度；曲线由常驻 painter 应用。
@internal
class CardProgress extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  /// 每段时长可变；calendar 的往返由状态监听器串接。
  CardProgress({required this.duration});

  /// 下一段使用的完整时长，修改时不重启当前任务。
  Duration duration;

  /// 当前进度、状态与任务句柄；无任务时保持最后的位置。
  double _value = 0;
  AnimationStatus _status = AnimationStatus.dismissed;

  /// 方向与已派发状态分开，保证值监听器先看到终态，再发送状态通知。
  AnimationStatus _direction = AnimationStatus.forward;
  AnimationStatus _reportedStatus = AnimationStatus.dismissed;
  CounterHandle? _handle;
  double? _fps;
  bool _disposed = false;
  int _revision = 0;

  /// 常驻 tear-off，任务更新热路径不创建闭包。
  late final void Function(double) _update = _onUpdate;
  late final void Function(double) _complete = _onComplete;

  @override
  double get value => _value;
  @override
  AnimationStatus get status => _status;
  @override
  bool get isAnimating =>
      (_status == AnimationStatus.forward ||
          _status == AnimationStatus.reverse) &&
      (_handle?.isAnimating ?? false);

  /// 动态同步解析后的上限；null 由引擎继续继承全局。
  set fps(double? value) {
    if (_fps == value) return;
    _fps = value;
    _handle?.fps = value;
  }

  /// 正向到 1，剩余路程按完整时长等比例缩短。
  void forward({double? from}) {
    assert(!_disposed);
    _direction = AnimationStatus.forward;
    if (from != null) _setValue(from);
    _animateTo(1);
  }

  /// 从当前位置反向到 0。
  void reverse() {
    assert(!_disposed);
    _direction = AnimationStatus.reverse;
    _animateTo(0);
  }

  /// 停止推进并保留当前位置和方向状态。
  void stop() {
    _revision++;
    final handle = _handle;
    _handle = null;
    handle?.cancel();
  }

  /// 取消任务、清零并通知 dismissed，用于隐藏或重新配置时落定。
  void reset() => _setValue(0);

  /// 设置静止值；通知顺序与 AnimationController.value 一致。
  void _setValue(double value) {
    stop();
    _value = value.clamp(0.0, 1.0);
    _status = _value == 0
        ? AnimationStatus.dismissed
        : _value == 1
        ? AnimationStatus.completed
        : _direction;
    notifyListeners();
    _checkStatusChanged();
  }

  /// 启动一程；零时长同步到终点，卡片调用位于倒计时任务边界内。
  void _animateTo(double to) {
    assert(!_disposed);
    stop();
    final revision = _revision;
    final micros = (duration.inMicroseconds * (to - _value).abs()).round();
    if (micros <= 0) {
      if (_value != to) {
        _value = to;
        notifyListeners();
      }
      if (!_disposed && revision == _revision) _onComplete(to);
      return;
    }
    _handle = _cardMotion.instance.add(
      CounterOptions(
        from: _value,
        to: to,
        duration: Duration(microseconds: micros),
        curve: Curves.linear,
        fps: _fps,
        onUpdate: _update,
        onComplete: _complete,
      ),
    );
    _status = _direction;
    _checkStatusChanged();
  }

  /// 只写数值并通知；终点监听器已能读到 completed/dismissed 和非运动态。
  void _onUpdate(double value) {
    _value = value;
    if (_direction == AnimationStatus.forward && value == 1) {
      _status = AnimationStatus.completed;
    } else if (_direction == AnimationStatus.reverse && value == 0) {
      _status = AnimationStatus.dismissed;
    }
    notifyListeners();
  }

  /// 先解除旧句柄，再允许 completed 监听器启动反程。
  void _onComplete(double value) {
    _handle = null;
    _status = value == 1
        ? AnimationStatus.completed
        : AnimationStatus.dismissed;
    _checkStatusChanged();
  }

  /// 仅在状态改变时派发；回调可重入启动下一程。
  void _checkStatusChanged() {
    if (_reportedStatus == _status) return;
    _reportedStatus = _status;
    notifyStatusListeners(_status);
  }

  /// 本进度源不需要订阅外部 Listenable。
  @override
  void didRegisterListener() {}
  @override
  void didUnregisterListener() {}

  /// 中途销毁取消任务并释放监听者。
  void dispose() {
    stop();
    _disposed = true;
    clearListeners();
    clearStatusListeners();
  }
}
