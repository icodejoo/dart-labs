import 'package:flutter/foundation.dart';

/// Shared storage exposed by Xvg.fps. / 由 Xvg.fps 公开的共享存储。
@internal
final ValueNotifier<double?> xvgFpsNotifier = ValueNotifier<double?>(null);

/// FPS validation contract. / 帧率校验契约。
@internal
const fpsValidationMessage = 'fps must be non-negative and not NaN';

/// Resolves instance over global; null/infinity means unlimited, zero freezes.
/// Negative values and NaN assert in debug.
/// 实例优先于全局；null/infinity 表示不限速，0 表示冻结；负数和 NaN 触发调试断言。
@internal
double? resolveFps({required double? instance, required double? global}) {
  assert(instance == null || instance >= 0, fpsValidationMessage);
  assert(global == null || global >= 0, fpsValidationMessage);
  final effective = instance ?? global;
  return effective == double.infinity ? null : effective;
}
