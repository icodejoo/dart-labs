import 'package:screen_brightness/screen_brightness.dart';

import '../core/platform/ports.dart';

/// A [MovaBrightPort] implementation backed by the `screen_brightness`
/// plugin. Reads the app's current screen brightness and applies changes to
/// it; any plugin error falls back to a brightness of `1.0`.
///
/// 基于 `screen_brightness` 插件实现的 [MovaBrightPort]。读取应用当前屏幕
/// 亮度并应用变更；插件出现任何异常时兜底为亮度 `1.0`。
class ScreenBrightnessPort implements MovaBrightPort {
  @override
  Future<double> get() async {
    try {
      return await ScreenBrightness().application;
    } catch (_) {
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
}
