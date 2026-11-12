import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../core/foundation/constants.dart';
import 'lever_options.dart';

/// 拉杆头半径占拉杆区宽度的比例。
const double leverKnobRadiusFactor = 0.35;

/// 可拖动行程占高度比例。
const double leverTravelFactor = 0.6;

/// 静止拉杆头中心占高度比例。
const double leverRestFactor = 0.2;

/// 监听独立回弹动画的拉杆画笔；不驱动老虎机构建。
final class LeverPainter extends CustomPainter {
  /// [progress] 在 0 到 1 之间；调用者拥有动画生命周期。
  LeverPainter(this.options, this.progress)
      : _shaftPaint = (Paint()..color = options.shaftColor),
        _knobPaint = (Paint()..color = options.knobColor),
        super(repaint: progress);

  /// 拉杆外观参数。
  final LeverOptions options;

  /// 当前拉动进度。
  final Animation<double> progress;

  /// 交互帧复用的杆身画笔。
  final Paint _shaftPaint;

  /// 交互帧复用的拉杆头画笔。
  final Paint _knobPaint;

  /// 绘制杆身、底座和圆形拉杆头。
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width * leverKnobRadiusFactor;
    final knob = Offset(size.width / kLuckyHalfDivisor,
        size.height * (leverRestFactor + leverTravelFactor * progress.value));
    final base = Offset(
        size.width / kLuckyHalfDivisor, size.height * (1 - leverRestFactor));
    _shaftPaint.strokeWidth = radius / kLuckyHalfDivisor;
    canvas.drawLine(base, knob, _shaftPaint);
    canvas.drawCircle(base, radius / kLuckyHalfDivisor, _shaftPaint);
    canvas.drawCircle(knob, radius, _knobPaint);
  }

  /// 参数或动画来源变化时重新绘制。
  @override
  bool shouldRepaint(covariant LeverPainter oldDelegate) =>
      options != oldDelegate.options || progress != oldDelegate.progress;
}
