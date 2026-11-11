import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/core/render/stir_arms.dart';

import '../../support/recording_canvas.dart';

/// 验证拨杆绘制器的绘制调用契约。
void main() {
  final arms = LuckyStirArms(containerRadius: 100, bodyRadius: 11);

  test('拨杆数量为零或啮合度不为正时不产生任何绘制调用', () {
    for (final (count, engaged) in [
      (0, 1.0),
      (2, 0.0),
      (2, -1.0),
      (2, double.nan)
    ]) {
      final canvas = TestRecordingCanvas();
      arms.paint(canvas, Offset.zero, 30, count, engaged);
      expect(canvas.invocations, isEmpty, reason: 'count=$count e=$engaged');
    }
  });

  test('绘制一个轮毂与每根拨杆一个圆角矩形，保存恢复平衡且不用 saveLayer', () {
    final canvas = TestRecordingCanvas();
    arms.paint(canvas, const Offset(50, 60), 30, 3, 0.5);
    expect(canvas.countCalls(#drawCircle), 1);
    expect(canvas.countCalls(#drawRRect), 3);
    expect(canvas.countCalls(#rotate), 4);
    canvas.expectBalancedWithoutSaveLayer();
  });

  test('半宽按啮合度缩放且啮合度超过一时按一处理', () {
    double lastScale(double engaged) {
      final canvas = TestRecordingCanvas();
      arms.paint(canvas, Offset.zero, 0, 1, engaged);
      final scale = canvas.invocations
          .where((r) => r.invocation.memberName == #scale)
          .last
          .invocation
          .positionalArguments;
      return scale[1] as double;
    }

    expect(lastScale(0.25), 0.25);
    expect(lastScale(1), 1);
    expect(lastScale(3), 1);
  });
}
