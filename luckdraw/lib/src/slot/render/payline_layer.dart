import 'package:flutter/rendering.dart';

import '../../core/render/layer.dart';
import '../layout/slot_layout.dart';
import '../model/payline.dart';
import '../model/slot_parts.dart';
import '../model/slot_result.dart';
import '../motion/slot_motion.dart';

/// 中奖赔付线的静态前景层；例如传入本局结果与配置中的 paylines。
final class SlotPaylineLayer extends LuckyLayer<SlotLayout, SlotFrame> {
  /// [result] 为 null 时不绘制；[paylines]、[mode] 应与老虎机配置一致。
  const SlotPaylineLayer(
      {required this.result,
      this.paylines = const [],
      this.mode = SlotMode.vertical})
      : super(isStatic: true);

  /// 当前局结果；无结果时不显示高亮。
  final SlotResult? result;

  /// 赔付线定义，结果的 winningPaylines 是本列表下标。
  final List<SlotPayline> paylines;

  /// 决定偏移沿纵轴还是横轴。
  final SlotMode mode;

  /// 将中奖线连接到对应行的格子中心；无效定义跳过。
  @override
  void paint(Canvas canvas, LuckyLayerContext<SlotLayout, SlotFrame> context) {
    final layout = context.layout;
    for (final index in result?.winningPaylines ?? const <int>[]) {
      if (index < 0 || index >= paylines.length) continue;
      final line = paylines[index];
      if (line.rowOffsets.length != layout.reels.length ||
          layout.reels.isEmpty) {
        continue;
      }
      final path = Path();
      for (var r = 0; r < layout.reels.length; r++) {
        final center = layout.reels[r].clipRect.center;
        final offset = line.rowOffsets[r] * layout.cellAndSpacing;
        final x = center.dx + (mode == SlotMode.horizontal ? offset : 0);
        final y = center.dy + (mode == SlotMode.vertical ? offset : 0);
        if (r == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = line.color
            ..strokeWidth = line.width
            ..style = PaintingStyle.stroke);
    }
  }

  /// 结果、定义或方向变化时重录高亮。
  @override
  bool shouldRepaint(covariant SlotPaylineLayer oldLayer) =>
      result != oldLayer.result ||
      paylines != oldLayer.paylines ||
      mode != oldLayer.mode;
}
