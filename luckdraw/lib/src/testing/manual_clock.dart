import '../core/motion/clock.dart';

/// 测试用默认帧步长。
const Duration _frameStep = Duration(milliseconds: 16);

/// 手动时间源；例如 `clock.advanceFrames(60)`。
final class ManualLuckyClock implements LuckyClock {
  /// 创建停止状态的时钟。
  ManualLuckyClock();

  /// 当前原始时间。
  Duration _raw = Duration.zero;

  /// 当前监听回调。
  void Function(Duration raw)? _callback;

  /// 是否正在运行。
  @override
  bool get isTicking => _callback != null;

  /// 开始或替换监听。
  @override
  void start(void Function(Duration raw) onTick) => _callback = onTick;

  /// 停止监听。
  @override
  void stop() => _callback = null;

  /// 设置原始时间，运行时发出一帧。
  void tick(Duration raw) {
    _raw = raw;
    _callback?.call(raw);
  }

  /// 增加原始时间，运行时发出一帧。
  void advance(Duration delta) => tick(_raw + delta);

  /// 按固定 [step] 推进 [frames] 帧，帧数须非负。
  void advanceFrames(int frames, {Duration step = _frameStep}) {
    assert(frames >= 0);
    for (var i = 0; i < frames; i++) {
      advance(step);
    }
  }

  /// 清除回调。
  @override
  void dispose() => stop();
}
