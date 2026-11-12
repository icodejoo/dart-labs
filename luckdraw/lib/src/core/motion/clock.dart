import 'package:flutter/scheduler.dart';

/// 可注入的动画原始时间源。
abstract interface class LuckyClock {
  /// 开始回调；已经运行时只替换回调。
  void start(void Function(Duration raw) onTick);

  /// 停止回调，允许再次开始。
  void stop();

  /// 是否正在运行。
  bool get isTicking;

  /// 释放时间源。
  void dispose();
}

/// 使用宿主提供的 vsync，自动跟随 TickerMode。
final class TickerLuckyClock implements LuckyClock {
  /// 创建时钟；宿主负责在销毁时调用 [dispose]。
  TickerLuckyClock(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  /// 底层 ticker。
  late final Ticker _ticker;

  /// 当前回调。
  void Function(Duration raw)? _callback;

  /// 转交原始时间。
  void _tick(Duration raw) => _callback?.call(raw);

  /// 替换回调并在需要时启动。
  @override
  void start(void Function(Duration raw) onTick) {
    _callback = onTick;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  /// 停止 ticker。
  @override
  void stop() => _ticker.stop();

  /// ticker 是否活跃。
  @override
  bool get isTicking => _ticker.isActive;

  /// 清空回调并释放 ticker。
  @override
  void dispose() {
    _callback = null;
    _ticker.dispose();
  }
}
