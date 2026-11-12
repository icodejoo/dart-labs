import 'dart:math' as math;
import 'dart:ui';

import '../foundation/constants.dart';
import '../kinematics/circle_world.dart';

/// 拨杆颜色的 RGB 部分。
const int _rgb = 0x4A6B7C;

/// 拨杆完全啮合时的不透明度，零到二百五十五。
const int _maxAlpha = 0xB0;

/// 拨杆绘制器：几何与物理世界的拨杆一致，帧内只做变换，不使用离屏图层。
///
/// 拨杆是绕容器圆心旋转的圆角线段，半宽随啮合度缩放，透明度随啮合度淡入淡出。
/// 例如 `LuckyStirArms(containerRadius: 100, bodyRadius: 11)`，
/// 每帧调用 [paint] 传入圆心、角度与啮合度。
final class LuckyStirArms {
  /// 创建绘制器；[containerRadius] 与 [bodyRadius] 为布局像素，须与物理世界使用的相同。
  LuckyStirArms({required double containerRadius, required double bodyRadius})
      : _hubRadius = kLuckyStirHubRadius * containerRadius,
        _arm = RRect.fromLTRBR(
            kLuckyStirHubRadius * containerRadius,
            -kLuckyStirArmHalfWidth * bodyRadius,
            kLuckyStirArmLength * containerRadius,
            kLuckyStirArmHalfWidth * bodyRadius,
            Radius.circular(kLuckyStirArmHalfWidth * bodyRadius));

  /// 轮毂半径，像素。
  final double _hubRadius;

  /// 单根拨杆的圆角矩形，沿正横轴方向。
  final RRect _arm;

  /// 复用的画笔，每帧只改颜色。
  final Paint _paint = Paint()..style = PaintingStyle.fill;

  /// 绘制 [count] 根均分的拨杆。
  ///
  /// [center] 为容器圆心，[angleDeg] 为第一根的角度，[engaged] 为零到一的啮合度；
  /// 啮合度或数量不为正时不绘制。
  void paint(Canvas canvas, Offset center, double angleDeg, int count,
      double engaged) {
    if (count <= 0 || !(engaged > 0)) return;
    final strength = math.min(engaged, 1.0);
    _paint.color = Color(
        (((_maxAlpha * strength).round() % (kLuckyMaxAlpha8 + 1)) << 24) |
            _rgb);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angleDeg * math.pi / 180);
    canvas.drawCircle(Offset.zero, _hubRadius, _paint);
    for (var k = 0; k < count; k++) {
      canvas.save();
      canvas.rotate(k * 2 * math.pi / count);
      canvas.scale(1, strength);
      canvas.drawRRect(_arm, _paint);
      canvas.restore();
    }
    canvas.restore();
  }
}
