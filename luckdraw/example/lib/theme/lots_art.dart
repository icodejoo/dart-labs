import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:luckdraw/lots.dart';

import 'demo_theme.dart';

/// 抽签示例的竹筒、签、签文卡与场景绘制；全部通过库的自定义 API 接入。
///
/// 例如 `LotsStyle(backgroundPainter: paintLotsScene)` 与
/// `LotsOptions(layoutAdjuster: adjustLotsLayout)`。

/// 竹筒口沿椭圆的半高占筒宽的比例。
const double _rimRatio = 0.09;

/// 签筒两道竹节相对筒高的位置。
const List<double> _nodeRatios = [0.14, 0.82];

/// 签文卡上签级大字的字号。
const double _gradeFontSize = 40;

/// 深木色，用于竹节和描边。
const Color _woodDark = Color(0xFF7A4719);

/// 朱红，用于签文卡边框、签级和印章。
const Color _cinnabar = Color(0xFFB3392F);

/// 浅金，用于卡片内线和筒沿高光。
const Color _gold = Color(0xFFF2C772);

/// 墨色，用于签诗。
const Color _ink = Color(0xFF4E261B);

/// 抽签过冲回弹缓动：升签和揭晓都带轻微回弹。
const LuckyEasing lotsSpringEasing = CurveEasing(Curves.easeOutBack);

/// 带二次谐波的摇晃波形，比纯正弦更像竹签碰撞的杂乱节奏，结果保持在 [-1, 1]。
double lotsRattleWaveform(double phaseDeg) {
  final x = phaseDeg * math.pi / 180;
  return (math.sin(x) + 0.35 * math.sin(2.7 * x)) / 1.35;
}

/// 把签文卡改成竖版并居中偏上；例如 `LotsOptions(layoutAdjuster: adjustLotsLayout)`。
LotsLayout adjustLotsLayout(LotsLayout base) {
  final w = base.size.width, h = base.size.height;
  return base.copyWith(
      card: Rect.fromLTWH(w * 0.17, h * 0.05, w * 0.66, h * 0.60));
}

/// 绘制一段文字并按给定中心水平居中；[top] 为文字顶边。
void _centerText(Canvas canvas, String text, double centerX, double top,
    TextStyle style,
    {double maxWidth = 400}) {
  final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr)
    ..layout(maxWidth: maxWidth);
  painter.paint(canvas, Offset(centerX - painter.width / 2, top));
  painter.dispose();
}

/// 示例统一的文字样式；中文字体沿用示例主题的回退列表。
TextStyle _style(double size, Color color,
        {FontWeight weight = FontWeight.w500,
        double height = 1.2,
        double spacing = 0}) =>
    TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        fontFamily: 'Microsoft YaHei',
        fontFamilyFallback: demoFontFallback);

/// 暖色纸面背景、光晕与筒底投影；静态，只录制一次。
void paintLotsScene(Canvas canvas, LotsLayout layout) {
  final rect = Offset.zero & layout.size;
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF4DC), Color(0xFFF8DDB0)])
            .createShader(rect));
  final c = layout.cylinder;
  final halo = Rect.fromCircle(
      center: Offset(c.center.dx, c.top), radius: layout.size.width * 0.55);
  canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
                colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)])
            .createShader(halo));
  canvas.restore();
  final shadow = Rect.fromCenter(
      center: Offset(c.center.dx, c.bottom + 4),
      width: c.width * 1.2,
      height: 22);
  canvas.drawOval(
      shadow,
      Paint()
        ..color = const Color(0x55401F0A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
}

/// 竹筒口的椭圆开口与内壁；画在签后面，随筒一起摇晃。
void paintLotsCylinderBack(Canvas canvas, LotsLayout layout) {
  final c = layout.cylinder;
  final ry = c.width * _rimRatio;
  final open = Rect.fromLTRB(c.left, c.top - ry, c.right, c.top + ry);
  canvas.drawOval(open.inflate(2.5), Paint()..color = const Color(0xFFE9B46B));
  canvas.drawOval(
      open,
      Paint()
        ..shader = const RadialGradient(
                colors: [Color(0xFF2A1507), Color(0xFF5B3516)], radius: 0.9)
            .createShader(open));
}

/// 竹筒前壁：圆角筒身、竹节、高光、口沿与“求签”标牌；盖在签的下半截上。
void paintLotsCylinderFront(Canvas canvas, LotsLayout layout) {
  final c = layout.cylinder;
  final ry = c.width * _rimRatio;
  final open = Rect.fromLTRB(c.left, c.top - ry, c.right, c.top + ry);
  final bottomCenterY = c.bottom - ry;
  final bottom =
      Rect.fromLTRB(c.left, bottomCenterY - ry, c.right, bottomCenterY + ry);
  final body = Path()
    ..moveTo(c.left, c.top)
    ..arcTo(open, math.pi, -math.pi, false)
    ..lineTo(c.right, bottomCenterY)
    ..arcTo(bottom, 0, math.pi, false)
    ..close();
  canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(colors: [
          Color(0xFF8E5A22),
          Color(0xFFD69A4A),
          Color(0xFFF1C277),
          Color(0xFFD9A04E),
          Color(0xFFA86B2B),
          Color(0xFF7E4A1C)
        ], stops: [
          0,
          0.18,
          0.35,
          0.6,
          0.85,
          1
        ]).createShader(c));
  canvas.save();
  canvas.clipPath(body);
  canvas.drawRect(
      c,
      Paint()
        ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x40000000)])
            .createShader(c));
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(c.left + c.width * 0.2, c.top, c.width * 0.07, c.height),
          const Radius.circular(6)),
      Paint()..color = const Color(0x38FFFFFF));
  for (final ratio in _nodeRatios) {
    final y = c.top + c.height * ratio;
    final arc = Rect.fromLTRB(c.left, y - ry, c.right, y + ry);
    final line = Path()..arcTo(arc, math.pi, -math.pi, false);
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _woodDark.withAlpha(180));
    canvas.drawPath(
        line.shift(const Offset(0, -2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x80F5D190));
  }
  canvas.restore();
  canvas.drawPath(
      Path()..arcTo(open, math.pi, -math.pi, false),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFF3CD8A));
  final tag = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(c.center.dx, c.top + c.height * 0.5),
          width: c.width * 0.46,
          height: c.height * 0.4),
      const Radius.circular(8));
  canvas.drawRRect(
      tag,
      Paint()
        ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFD94B3A), Color(0xFFA82419)])
            .createShader(tag.outerRect));
  canvas.drawRRect(
      tag.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _gold);
  _centerText(canvas, '求\n签', c.center.dx, tag.top + tag.height * 0.12,
      _style(c.width * 0.19, Colors.white, weight: FontWeight.w700, height: 1.3));
}

/// 竹签：圆头竹片；被抽中的签带朱红签头并竖排签级。[stick] 为空表示未抽中的空白签。
void paintLotsStick(Canvas canvas, Size size, LotsStick? stick) {
  final body = RRect.fromRectAndCorners(Offset.zero & size,
      topLeft: Radius.circular(size.width / 2),
      topRight: Radius.circular(size.width / 2));
  canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
                colors: [Color(0xFFE2B96E), Color(0xFFF6E1AE), Color(0xFFD8AE66)])
            .createShader(Offset.zero & size));
  canvas.drawRRect(
      body.deflate(0.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFB98A45));
  if (stick == null) return;
  const bandHeight = 36.0;
  canvas.save();
  canvas.clipRRect(body);
  canvas.drawRect(Rect.fromLTWH(0, 0, size.width, bandHeight),
      Paint()..color = _cinnabar);
  canvas.restore();
  _centerText(canvas, stick.label.split('').join('\n'), size.width / 2, 4,
      _style(8, Colors.white, weight: FontWeight.w700, height: 1.05),
      maxWidth: size.width + 8);
}

/// 竖版签文卡：宣纸底、朱红双线边框、签级大字、签诗和落款；
/// [grade] 为签级，[poem] 为两行签诗（用 `\n` 分行）。
LotsStickPainter lotsCardPainter(
        {required String grade, required String poem}) =>
    (canvas, r) {
      final paper = RRect.fromRectAndRadius(
          r.deflate(4), const Radius.circular(12));
      canvas.drawRRect(
          paper.shift(const Offset(0, 4)),
          Paint()
            ..color = const Color(0x40000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
      canvas.drawRRect(
          paper,
          Paint()
            ..shader = const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFAEC), Color(0xFFF5E2B6)])
                .createShader(paper.outerRect));
      canvas.drawRRect(
          paper,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFFD9B677));
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(12), const Radius.circular(6)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _cinnabar);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(16), const Radius.circular(3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = _gold);
      final cx = r.center.dx;
      _centerText(canvas, '灵 签', cx, r.top + 26,
          _style(11, _cinnabar, weight: FontWeight.w600, spacing: 6));
      _centerText(canvas, grade, cx, r.top + 46,
          _style(_gradeFontSize, _cinnabar, weight: FontWeight.w800),
          maxWidth: r.width - 40);
      final dividerY = r.top + 112;
      final line = Paint()
        ..strokeWidth = 1
        ..color = _gold;
      canvas.drawLine(
          Offset(r.left + 30, dividerY), Offset(cx - 8, dividerY), line);
      canvas.drawLine(
          Offset(cx + 8, dividerY), Offset(r.right - 30, dividerY), line);
      canvas.drawPath(
          Path()
            ..moveTo(cx, dividerY - 4)
            ..lineTo(cx + 4, dividerY)
            ..lineTo(cx, dividerY + 4)
            ..lineTo(cx - 4, dividerY)
            ..close(),
          Paint()..color = _cinnabar);
      _centerText(canvas, poem, cx, dividerY + 14,
          _style(17, _ink, weight: FontWeight.w600, height: 1.7),
          maxWidth: r.width - 40);
      _centerText(canvas, '诚心则灵 · 仅供娱乐', cx, r.bottom - 34,
          _style(9, const Color(0xFF9A7A52)));
      canvas.save();
      canvas.translate(r.right - 40, r.bottom - 52);
      canvas.rotate(-0.14);
      final seal = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 22, height: 22),
          const Radius.circular(3));
      canvas.drawRRect(seal, Paint()..color = _cinnabar);
      _centerText(canvas, '签', 0, -8,
          _style(13, Colors.white, weight: FontWeight.w700, height: 1));
      canvas.restore();
    };
