import 'package:flutter/widgets.dart';

import '../core/model/fit.dart';
import 'fit_ext.dart';

/// Computes the rect (relative to [container]) that the video content
/// actually occupies once centered and scaled by [fit] — i.e. the letterboxed
/// picture area, excluding any black bars.
///
/// Pure function (no BuildContext/Widget dependency) so it is unit-testable
/// in isolation.
///
/// - [container]: the available layout size (e.g. the whole player) /
///   可用布局尺寸（例如整个播放器）
/// - [videoSize]: the video's raw frame size; `null` or a zero-sized value
///   means "unknown", and the whole [container] is returned as a fallback /
///   视频原始帧尺寸；为 `null` 或任一边为 0 视为未知，退化返回整个 [container]
/// - [fit]: the fill mode applied to the video surface / 视频画面的填充模式
///
/// Returns the video content's rect, relative to [container]'s origin.
///
/// 计算视频内容居中并按 [fit] 缩放后，实际占据的矩形（相对 [container]）——
/// 也就是去掉黑边后的画面区域。
///
/// 纯函数（不依赖 BuildContext/Widget），便于单独做单元测试。
///
/// 返回视频内容矩形，坐标相对 [container] 的原点。
///
/// ```dart
/// final rect = computeVideoContentRect(
///   container: const Size(400, 800),
///   videoSize: const Size(1920, 1080),
///   fit: MovaFit.contain,
/// );
/// // rect == Rect.fromLTWH(0, 325, 400, 225) — letterboxed, centered.
/// ```
Rect computeVideoContentRect({
  required Size container,
  required Size? videoSize,
  required MovaFit fit,
}) {
  if (videoSize == null ||
      videoSize.width <= 0 ||
      videoSize.height <= 0 ||
      container.width <= 0 ||
      container.height <= 0) {
    return Offset.zero & container;
  }
  final destSize = applyBoxFit(movaBoxFit(fit), videoSize, container).destination;
  final dx = (container.width - destSize.width) / 2;
  final dy = (container.height - destSize.height) / 2;
  return (Offset(dx, dy) & destSize);
}
