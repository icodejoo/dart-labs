import 'dart:async';

/// 可注入的时间服务；测试可实现本接口并推进时间。
abstract class DiomanClock {
  /// 使用系统时钟，例如 `const DiomanClock.system()`。
  const factory DiomanClock.system() = _SystemClock;

  /// 返回当前时间。
  DateTime now();

  /// 在 [duration] 后调用 [callback]，返回可取消的计时器。
  Timer createTimer(Duration duration, void Function() callback);
}

/// 系统时间与可取消计时器的实现。
class _SystemClock implements DiomanClock {
  /// 创建无状态时钟。
  const _SystemClock();

  /// 返回系统时间。
  @override
  DateTime now() => DateTime.now();

  /// 创建单次计时器。
  @override
  Timer createTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}
