import 'dart:async';

/// 可暂停的一次性广告倒计时；到期由 Timer 驱动，不读取媒体位置。
/// 示例：`MovaAdClock(now: now)..start(Duration(seconds: 5), onExpire)`。
class MovaAdClock {
  /// [now] 返回当前时刻；省略时使用墙钟，测试应注入虚拟时钟。
  MovaAdClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// 剩余时长所用的时间源。
  final DateTime Function() _now;
  /// 当前到期定时器。
  Timer? _timer;
  /// 最近起表或暂停时保留的剩余时长。
  Duration? _left;
  /// 本轮开始走时的时刻；暂停时为 null。
  DateTime? _since;
  /// 到期回调，每次起表最多调用一次。
  void Function()? _onExpire;

  /// 取消旧表并计时 [length]，到期调用 [onExpire]；无返回值。
  /// 示例：`clock.start(Duration(seconds: 10), onExpire)`。
  void start(Duration length, void Function() onExpire) {
    cancel();
    _onExpire = onExpire;
    _left = length;
    _arm();
  }

  /// 暂停并保存剩余时长；重复调用无效，无返回值。示例：`clock.pause()`。
  void pause() {
    if (_since == null || _left == null) return;
    _left = remaining;
    _timer?.cancel();
    _timer = null;
    _since = null;
  }

  /// 从保存的剩余时长恢复；未暂停时无效，无返回值。示例：`clock.resume()`。
  void resume() {
    if (_since != null || _left == null) return;
    _arm();
  }

  /// 取消计时并清空剩余时长；无返回值。示例：`clock.cancel()`。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _left = null;
    _since = null;
    _onExpire = null;
  }

  /// 返回剩余时长；未起表、已取消或已到期为 null。示例：`clock.remaining`。
  Duration? get remaining {
    final left = _left;
    if (left == null) return null;
    final since = _since;
    final value = since == null ? left : left - _now().difference(since);
    return value > Duration.zero ? value : Duration.zero;
  }

  /// 返回是否正在计时。示例：`if (clock.running) clock.pause()`。
  bool get running => _since != null;

  /// 按保存的剩余时长挂到期回调。
  void _arm() {
    _since = _now();
    _timer = Timer(_left!, () {
      final callback = _onExpire;
      cancel();
      callback?.call();
    });
  }
}
