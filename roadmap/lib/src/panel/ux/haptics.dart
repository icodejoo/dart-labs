/// 触觉反馈封装，默认关闭。
///
/// 移植自 `src/panel/ux/haptics.ts`。TS 版本包一层 `navigator.vibrate`；Flutter
/// 用 `HapticFeedback`（无振动时长参数，`vibrate()` 因此只对应一次轻触反馈，
/// 这是移动平台 API 本身的差异，不是本移植遗漏）。
library;

import 'package:flutter/services.dart';

/// 触觉反馈选项。
class HapticsOptions {
  /// 是否默认开启，默认 false（大多数场景下触觉反馈应是用户主动选择的）。
  final bool enabled;

  const HapticsOptions({this.enabled = false});
}

/// 触觉反馈效果控制器。
class HapticsEffect {
  bool enabled;

  HapticsEffect({this.enabled = false});

  /// 切换开关。
  void toggle(bool on) => enabled = on;

  /// 触发一次轻触反馈（[ms] 参数保留用于 API 对齐，Flutter 侧不区分时长）。
  void vibrate([int ms = 50]) {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }
}

/// 创建触觉反馈效果控制器。
HapticsEffect createHapticsEffect({HapticsOptions options = const HapticsOptions()}) =>
    HapticsEffect(enabled: options.enabled);
