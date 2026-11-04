import 'package:flutter/widgets.dart';

/// [SystemClock] 墙钟的底层时间源，默认 [DateTime.now]。
/// 放在 `core/` 里，引擎之间不必为读时钟互相依赖。
///
/// 测试里可替换它来推进时间；新代码更推荐给引擎注入 [ManualCountmanClock]：
/// ```dart
/// var fakeNow = DateTime(2024);
/// countdownClock = () => fakeNow;
/// fakeNow = fakeNow.add(const Duration(seconds: 3));
/// ```
// ignore: prefer_function_declarations_over_variables
DateTime Function() countdownClock = DateTime.now;

// 秒表使用单调时间，避免系统校时导致累计时间跳变。
final Stopwatch _elapsedWatch = Stopwatch()..start();

/// [SystemClock] 单调钟的底层时间源；测试结束后应恢复原函数。
// ignore: prefer_function_declarations_over_variables
Duration Function() elapsedClock = () => _elapsedWatch.elapsed;

/// 微秒精度的墙钟与单调钟抽象，供倒计时与正计时引擎读取时间。
/// 相对时长（`duration`）按单调钟锚定，绝对截止（`deadline`）按墙钟锚定。
/// 可用 `Countdown(clock: ManualCountmanClock())` 注入确定性时钟。
abstract class CountmanClock {
  /// 全局默认时钟，未显式指定 clock 的引擎每次读取时都会解析它；
  /// 测试可整体替换，结束后应恢复为原实例。
  static CountmanClock system = SystemClock();

  /// 返回 Unix epoch 墙钟微秒，允许系统校时改变数值。
  int wallMicros();

  /// 返回含后台深睡补偿的单调微秒，用于相对时长。
  int monotonicMicros();
}

/// 后台恢复校准；仅补偿墙钟比单调钟多走超过一秒的部分。
class _ResumeCalibration {
  /// 消除时钟采样误差与短暂停顿的校准门槛。
  static const int _toleranceMicros = Duration.microsecondsPerSecond;

  /// 后台入口的墙钟快照；null 表示当前未进入后台。
  int? _wall;

  /// 后台入口的原始单调钟快照。
  int _monotonic = 0;

  /// 累计补上的深睡微秒。
  int offset = 0;

  /// 只记录第一次后台入口，hidden 后的 paused 不覆盖起点。
  void pause(int wall, int monotonic) {
    if (_wall != null) return;
    _wall = wall;
    _monotonic = monotonic;
  }

  /// 恢复时补偿正差值；后台手动校时也可能被视为深睡。
  void resume(int wall, int monotonic) {
    final previous = _wall;
    if (previous == null) return;
    final missing = (wall - previous) - (monotonic - _monotonic);
    if (missing > _toleranceMicros) offset += missing;
    _wall = null;
  }
}

/// 系统时钟；底层保留 countdownClock/elapsedClock 注入点。
/// 首次读取时懒注册生命周期监听；前台墙钟跳变不会补到单调钟。
class SystemClock implements CountmanClock {
  /// 创建独立的校准时钟，例如 `final clock = SystemClock()`。
  SystemClock();

  /// 后台恢复的累计补偿状态。
  final _calibration = _ResumeCalibration();

  /// 懒注册且每实例只保留一个监听器。
  AppLifecycleListener? _listener;

  /// 首次读钟时接入生命周期；若已在后台，也记录当前入口。
  void _listen() {
    if (_listener != null) return;
    _listener = AppLifecycleListener(onStateChange: _lifecycle);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) _lifecycle(state);
  }

  /// 使用原始双钟采样校准，避免重复叠加已补偿的偏移。
  void _lifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _calibration.pause(countdownClock().microsecondsSinceEpoch,
          elapsedClock().inMicroseconds);
    } else if (state == AppLifecycleState.resumed) {
      _calibration.resume(countdownClock().microsecondsSinceEpoch,
          elapsedClock().inMicroseconds);
    }
  }

  /// 返回底层墙钟微秒，并确保恢复监听已注册。
  @override
  int wallMicros() {
    _listen();
    return countdownClock().microsecondsSinceEpoch;
  }

  /// 返回底层单调微秒加深睡偏移。
  @override
  int monotonicMicros() {
    _listen();
    return elapsedClock().inMicroseconds + _calibration.offset;
  }

  /// 释放自行创建实例的监听；默认全局实例通常无需调用。
  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}

/// 仅偏移墙钟的包装器，适用于服务器校时。
class OffsetClock implements CountmanClock {
  /// [base] 为基础时钟，[offset] 可正可负；单调钟始终透传。
  /// 例如 `OffsetClock(CountmanClock.system, Duration(seconds: 2))`。
  OffsetClock(this.base, Duration offset) : _offsetMicros = offset.inMicroseconds;

  /// 基础时钟实例。
  final CountmanClock base;

  /// 墙钟偏移微秒。
  final int _offsetMicros;

  /// 返回基础墙钟加偏移。
  @override
  int wallMicros() => base.wallMicros() + _offsetMicros;

  /// 返回基础单调钟，服务器校时不影响相对任务。
  @override
  int monotonicMicros() => base.monotonicMicros();
}

/// 可手动推进的时钟，供业务模拟和测试使用，无需真实等待。
class ManualCountmanClock implements CountmanClock {
  /// [wallTime] 默认 Unix epoch，[monotonic] 默认零。
  /// 例如 `ManualCountmanClock(wallTime: DateTime(2026))`。
  ManualCountmanClock({DateTime? wallTime, Duration monotonic = Duration.zero})
      : _wallMicros = wallTime?.microsecondsSinceEpoch ?? 0,
        _monotonicMicros = monotonic.inMicroseconds;

  /// 原始墙钟微秒。
  int _wallMicros;

  /// 原始单调微秒。
  int _monotonicMicros;

  /// 与系统时钟共用的恢复校准规则。
  final _calibration = _ResumeCalibration();

  /// 当前墙钟微秒。
  @override
  int wallMicros() => _wallMicros;

  /// 当前单调微秒，包含模拟深睡补偿。
  @override
  int monotonicMicros() => _monotonicMicros + _calibration.offset;

  /// 同时推进双钟；[duration] 必须非负，例如 `advance(Duration(seconds: 1))`。
  void advance(Duration duration) {
    assert(!duration.isNegative);
    _wallMicros += duration.inMicroseconds;
    _monotonicMicros += duration.inMicroseconds;
  }

  /// 只跳变墙钟；[duration] 可正可负，用于模拟前台系统校时。
  void jumpWall(Duration duration) => _wallMicros += duration.inMicroseconds;

  /// 模拟 paused→resumed，期间只有墙钟推进；使用系统的超过一秒校准规则。
  void suspend(Duration duration) {
    assert(!duration.isNegative);
    _calibration.pause(_wallMicros, _monotonicMicros);
    _wallMicros += duration.inMicroseconds;
    _calibration.resume(_wallMicros, _monotonicMicros);
  }
}
