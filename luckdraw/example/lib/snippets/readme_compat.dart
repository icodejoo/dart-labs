import 'package:flutter/widgets.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/wheel.dart';

/// 将 [json] 转成转盘 Widget；例如 `migratedWheel(json)` 返回迁移结果。
Widget migratedWheel(Map<String, Object?> json) {
  final converted = wheelFromLuckyCanvasConfig(json,
      options: LuckyCanvasCompatOptions.strictUpstream());
  for (final warning in converted.warnings) {
    debugPrint(warning.toString());
  }
  return LuckyWheel(
      config: converted.config,
      width: converted.width,
      height: converted.height,
      alignment: Alignment.topLeft);
}
