import 'package:screen_brightness/screen_brightness.dart';

import '../core/platform/ports.dart';

/// A [MovaBrightPort] implementation backed by the `screen_brightness`
/// plugin. Reads the app's current screen brightness and applies changes to
/// it; any plugin error falls back to a brightness of `1.0`.
///
/// 基于 `screen_brightness` 插件实现的 [MovaBrightPort]。读取应用当前屏幕
/// 亮度并应用变更；插件出现任何异常时兜底为亮度 `1.0`。
class MovaScreenBrightnessPort implements MovaBrightPort, MovaBrightRestore {
  /// 进入播放器前是否已有应用亮度覆盖；读取失败时不猜测宿主控制权。
  bool? _hadApplicationOverride;

  @override
  Future<double> get() async {
    try {
      _hadApplicationOverride ??= await ScreenBrightness().hasApplicationScreenBrightnessChanged;
      return await ScreenBrightness().application;
    } catch (_) {
      _hadApplicationOverride = null;
      return 1.0;
    }
  }

  @override
  Future<void> set(double value) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (_) {
      // Ignore failures — brightness control is best-effort.
      //
      // 忽略失败——亮度控制是尽力而为。
    }
  }

  /// 按 [initialBrightness] 恢复原有应用覆盖，否则交还系统控制；返回完成通知。
  ///
  /// 示例：`await port.restore(0.5)`。
  @override
  Future<void> restore(double initialBrightness) async {
    try {
      if (_hadApplicationOverride == true) {
        await ScreenBrightness().setApplicationScreenBrightness(initialBrightness);
      } else if (_hadApplicationOverride == false) {
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
    } catch (_) {
      // 平台不可用时忽略还原失败。
    }
  }
}
