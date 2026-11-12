import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 记录减速路径是否反复构造翻转曲线。
class _TrackingCurve extends Curve {
  /// 被创建的包装对象。
  final List<Curve> flips = [];

  /// 平方曲线。
  @override
  double transformInternal(double t) => t * t;

  /// 记录 Flutter 翻转包装对象。
  @override
  Curve get flipped {
    final value = super.flipped;
    flips.add(value);
    return value;
  }
}

/// 验证重复采样不分配曲线包装，且保持 const 调用兼容。
void main() {
  test(
      'CurveEasing > repeated easeOut samples do not create flipped curve objects',
      () {
    final curve = _TrackingCurve();
    final easing = CurveEasing(curve);
    for (var t = 0; t <= 100; t++) {
      final x = t / 100;
      expect(easing.easeOut(t.toDouble(), 0, 100, 100),
          closeTo(100 * (1 - (1 - x) * (1 - x)), 0.000001));
    }
    expect(curve.flips, hasLength(lessThanOrEqualTo(1)));
    const constant = CurveEasing(Curves.easeIn);
    expect(constant.easeOut(100, 0, 100, 100), 100);
  });
}
