import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show internal, visibleForTesting;

/// 测试覆盖屏幕刷新率；null 恢复平台值并清除缓存。
@visibleForTesting
double? get debugRefreshRateHz => _debugRefreshRateHz;
set debugRefreshRateHz(double? value) {
  _debugRefreshRateHz = value;
  _cachedVsyncPeriodMicros = null;
}

/// 平台刷新率与测试覆盖的缓存状态，热路径只读整数。
double? _debugRefreshRateHz;
int? _cachedVsyncPeriodMicros;

/// 首个 view 的 vsync 周期；无有效刷新率时回退 60Hz，添加任务时刷新。
@internal
int vsyncPeriodMicros({bool refresh = false}) {
  final cached = _cachedVsyncPeriodMicros;
  if (!refresh && cached != null) return cached;
  var hz = _debugRefreshRateHz;
  if (hz == null) {
    final views = PlatformDispatcher.instance.views;
    if (views.isNotEmpty) hz = views.first.display.refreshRate;
  }
  if (hz == null || hz <= 0 || !hz.isFinite) hz = 60;
  final micros = (1000000 / hz).clamp(1, 9007199254740991).round();
  _cachedVsyncPeriodMicros = micros;
  return micros;
}

/// 校验帧率；release 把非法值视为 null，以便继续向上回退。
@internal
double? validFps(double? value) {
  assert(value == null || (value > 0 && value.isFinite), 'fps 必须为有限正数');
  return value != null && value > 0 && value.isFinite ? value : null;
}

/// 帧率换算为安全的整数微秒；极低帧率钳到 Web 可精确表示的范围。
@internal
int fpsIntervalMicros(double? value) {
  if (value == null) return 0;
  final micros = 1000000 / value;
  if (micros >= 9007199254740991) return 9007199254740991;
  return micros < 1 ? 1 : micros.round();
}
