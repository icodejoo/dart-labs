import 'dart:math' as math;

import 'package:flutter/painting.dart' show AxisDirection;

import 'types.dart';

/// 3D 翻转（flip）的透视系数，两条渲染路径共用。
const double kDigitFlipPerspective = 0.002;

/// 运动模糊的最大 sigma；在进度 0.5 处达到。
const double kDigitBlurMaxSigma = 8.0;

/// 低于此 sigma 视为无模糊，省掉 saveLayer / ImageFiltered。
const double kDigitBlurMinSigma = 0.1;

/// 一个数位在某一帧的运动数值，由 [resolveDigitMotion] 写入。
///
/// 画笔路径把它应用到 Canvas，组件树路径把它应用到 Transform / Opacity，两边只做
/// “应用”，不再各写一份 `switch (motion)`。调用方应复用同一个实例，热路径零分配。
///
/// 坐标约定：x 向右、y 向下；位移单位为逻辑像素，角度为弧度。
class DigitMotion {
  /// 水平位移；仅 slide 且方向为 left/right 时非零。
  double dx = 0;

  /// 垂直位移；仅 slide 且方向为 up/down 时非零。
  double dy = 0;

  /// 绕单元中心的平面旋转角；仅 rotate 时非零。
  double rotateZ = 0;

  /// 绕 X 轴的翻转角（配合 [kDigitFlipPerspective]）；仅 flip 时非零。
  double rotateX = 0;

  /// 绕单元中心的缩放比例，0–1；未启用 scale 时恒为 1。
  double scale = 1;

  /// 不透明度，0–1；未启用 fade 时恒为 1。
  double alpha = 1;

  /// 本帧是否需要绘制：不透明度 ≈ 0、缩放为 0，或 flip 的背面（同一时刻只显示一面）
  /// 时为 false。
  bool visible = true;
}

/// 把“方向无关的原始方向”折算成滚动方向：递减时取相反方向。
///
/// [raw] 为用户配置的 flipDirection；[increasing] 为数值是否在增长。
/// 例如 `effectiveRollDirection(AxisDirection.up, false) == AxisDirection.down`。
AxisDirection effectiveRollDirection(AxisDirection raw, bool increasing) {
  if (increasing) return raw;
  return switch (raw) {
    AxisDirection.up => AxisDirection.down,
    AxisDirection.down => AxisDirection.up,
    AxisDirection.left => AxisDirection.right,
    AxisDirection.right => AxisDirection.left,
  };
}

/// 滚动方向是否为水平（left / right）。
bool isHorizontalRoll(AxisDirection direction) =>
    direction == AxisDirection.left || direction == AxisDirection.right;

/// 垂直方向上“离场”一侧的符号：up/right 为 -1（向上），down/left 为 +1（向下）。
///
/// slide 的垂直位移与回弹轻推共用。[direction] 为已折算的滚动方向。
double verticalExitSign(AxisDirection direction) =>
    (direction == AxisDirection.up || direction == AxisDirection.right) ? -1.0 : 1.0;

/// 水平方向上“离场”一侧的符号：right 为 +1，left 为 -1。[direction] 为已折算的滚动方向。
double horizontalExitSign(AxisDirection direction) =>
    direction == AxisDirection.right ? 1.0 : -1.0;

/// 回弹轻推的垂直位移（逻辑像素）：沿运动方向把静止数位推 [fraction] 个数位高度。
///
/// [direction] 为已折算的滚动方向，[fraction] 为数位高度的比例，[height] 为单元高度。
double digitBounceShift(AxisDirection direction, double fraction, double height) =>
    fraction * height * verticalExitSign(direction);

/// 运动模糊的 sigma；未启用 blur 或低于 [kDigitBlurMinSigma] 时返回 0。
///
/// [p] 为 0–1 的滚动相位，进度 0.5 处最模糊。
double digitBlurSigma(CounterTransition transition, double p) {
  if (!transition.blur) return 0.0;
  final sigma = (0.5 - (p - 0.5).abs()) * kDigitBlurMaxSigma;
  return sigma >= kDigitBlurMinSigma ? sigma : 0.0;
}

/// 解算一个数位在相位 [p] 的运动数值并写入 [out]，是过渡效果的唯一来源。
///
/// 新增 [CounterMotion] 或修饰时只改这里，画笔与组件树两条路径自动一致。
///
/// - [transition]：运动 + scale / fade 修饰（blur 见 [digitBlurSigma]，不在此处理）。
/// - [direction]：已折算的滚动方向，见 [effectiveRollDirection]。
/// - [p]：从当前位到下一位的 0–1 滚动相位。
/// - [leaving]：true 为正在离开的数位（p→0 时归位），false 为正在到来的数位（p→1 归位）。
/// - [width] / [height]：单元格含 padding 的宽高，决定 slide 的位移幅度。
///
/// 示例：
/// ```dart
/// final m = DigitMotion();
/// resolveDigitMotion(m, transition: CounterTransition.slide,
///     direction: AxisDirection.up, p: 0.5, leaving: true, width: 20, height: 40);
/// // m.dy == -20，m.alpha == 0.5
/// ```
void resolveDigitMotion(
  DigitMotion out, {
  required CounterTransition transition,
  required AxisDirection direction,
  required double p,
  required bool leaving,
  required double width,
  required double height,
}) {
  // 0 = 在原位，1 = 完全移出。
  final double away = leaving ? p : 1 - p;
  out
    ..dx = 0
    ..dy = 0
    ..rotateZ = 0
    ..rotateX = 0
    ..scale = 1
    ..alpha = transition.fade ? (1 - away).clamp(0.0, 1.0) : 1.0;
  bool faceShown = true;

  // 以单元中心缩放：离场缩小、入场放大。
  if (transition.scale) out.scale = (1 - away).clamp(0.0, 1.0);

  switch (transition.motion) {
    case CounterMotion.none:
      break;
    case CounterMotion.slide:
      final double signedAway = leaving ? away : -away;
      if (isHorizontalRoll(direction)) {
        out.dx = signedAway * width * horizontalExitSign(direction);
      } else {
        out.dy = signedAway * height * verticalExitSign(direction);
      }
    case CounterMotion.rotate:
      out.rotateZ = (leaving ? -away : away) * math.pi / 2;
    case CounterMotion.flip:
      // 翻转同一时刻只显示一面：离场面在前半程，入场面在后半程。
      out.rotateX = leaving ? -p * math.pi : (1 - p) * math.pi;
      faceShown = leaving ? p < 0.5 : p >= 0.5;
  }

  out.visible = faceShown && out.alpha > 0.001 && out.scale > 0;
}
