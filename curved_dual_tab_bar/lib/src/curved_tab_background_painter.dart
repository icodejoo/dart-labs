part of 'curved_dual_tab_bar.dart';

/// Draws all three background layers (base fill, resting pill, S-curve
/// split) in a single [BoxPainter.paint] call, so [CurvedTabBackground] only
/// needs one `Container(decoration: ...)` instead of a `ClipRRect` +
/// `Stack` of `ColoredBox`/`DecoratedBox`/`CustomPaint` children.
///
/// 在一次 [BoxPainter.paint] 里画完三层背景（底色、静态底板、S 曲线分割），
/// 这样 [CurvedTabBackground] 只需要一个 `Container(decoration: ...)`，
/// 不用再叠 `ClipRRect` + `Stack`（`ColoredBox`/`DecoratedBox`/`CustomPaint` 一堆子节点）。
class _CurvedTabBackgroundDecoration extends Decoration {
  const _CurvedTabBackgroundDecoration({
    required this.borderRadius,
    required this.leanAmplitude,
    required this.backgroundColor,
    required this.unselectedTopInset,
    required this.unselectedColor,
    required this.unselectedBorderColor,
    required this.unselectedBorderWidth,
    required this.leanSign,
    required this.leftColor,
    required this.rightColor,
    this.leftGradient,
    this.rightGradient,
    this.dividerColor,
    this.dividerWidth = 1.5,
    this.dividerGradient,
    this.dividerCap = StrokeCap.butt,
    this.dividerShadow,
    this.topControlOffset = Offset.zero,
    this.bottomControlOffset = Offset.zero,
    this.leftBorderColor,
    this.rightBorderColor,
    this.splitBorderWidth = 1.5,
  });

  final double borderRadius;
  final double leanAmplitude;
  final Color backgroundColor;
  final double unselectedTopInset;
  final Color unselectedColor;
  final Color unselectedBorderColor;
  final double unselectedBorderWidth;
  final double leanSign;
  final Color leftColor;
  final Color rightColor;
  final LinearGradient? leftGradient;
  final LinearGradient? rightGradient;
  final Color? dividerColor;
  final double dividerWidth;
  final Gradient? dividerGradient;
  final StrokeCap dividerCap;
  final BoxShadow? dividerShadow;
  final Offset topControlOffset;
  final Offset bottomControlOffset;
  final Color? leftBorderColor;
  final Color? rightBorderColor;
  final double splitBorderWidth;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _CurvedTabBackgroundPainter(this);
}

class _CurvedTabBackgroundPainter extends BoxPainter {
  _CurvedTabBackgroundPainter(this.decoration);

  final _CurvedTabBackgroundDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final topRadius = Radius.circular(decoration.borderRadius);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRRect(
      RRect.fromRectAndCorners(
        Offset.zero & size,
        topLeft: topRadius,
        topRight: topRadius,
      ),
    );

    // Layer 1: base fill.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = decoration.backgroundColor,
    );

    // Layer 2: static resting pill, inset from the top, unaffected by
    // selection.
    //
    // 第 2 层：静态底板，从顶部缩进，不受选中态影响。
    final pillRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        0,
        decoration.unselectedTopInset,
        size.width,
        size.height - decoration.unselectedTopInset,
      ),
      topLeft: topRadius,
      topRight: topRadius,
    );
    canvas.drawRRect(pillRRect, Paint()..color = decoration.unselectedColor);
    if (decoration.unselectedBorderWidth > 0) {
      canvas.drawRRect(
        pillRRect.deflate(decoration.unselectedBorderWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = decoration.unselectedBorderWidth
          ..color = decoration.unselectedBorderColor,
      );
    }

    // Layer 3: full-height S-curve split. Control points share their
    // endpoint's y-coordinate but sit at the horizontal center, giving a
    // flat (horizontal) tangent right at the top/bottom edges — the curve
    // grazes them like a wave crest/trough instead of meeting them at a
    // right angle, then does all its leaning in the middle third.
    //
    // 第 3 层：贯穿整个高度的 S 曲线分割。控制点与对应端点共享 y 坐标，
    // 落在水平方向的中心——这让曲线在顶/底边处的切线是水平的（平的），
    // 像波峰/波谷一样贴着边缘过渡，而不是跟边缘成直角对接，倾斜全部发生在
    // 中段。
    final centerX = size.width / 2;
    final leanOffset =
        size.width * decoration.leanAmplitude * decoration.leanSign;
    final topPoint = Offset(centerX + leanOffset, 0);
    final bottomPoint = Offset(centerX - leanOffset, size.height);
    final controlTop =
        Offset(centerX, topPoint.dy) + decoration.topControlOffset;
    final controlBottom =
        Offset(centerX, bottomPoint.dy) + decoration.bottomControlOffset;

    final curvePath = Path()
      ..moveTo(topPoint.dx, topPoint.dy)
      ..cubicTo(
        controlTop.dx,
        controlTop.dy,
        controlBottom.dx,
        controlBottom.dy,
        bottomPoint.dx,
        bottomPoint.dy,
      );

    // Both regions bake their own outer top corner into the path (instead
    // of relying on the enclosing `clipRRect` to round a sharp corner) —
    // otherwise a stroked border along the path gets cut off wherever the
    // clip trims that corner.
    //
    // 两块区域各自把外侧顶部圆角画进路径本身（而不是靠外层 `clipRRect`
    // 去裁一个直角）——不然沿路径描边的边框会在圆角处被裁掉。
    final leftPath = Path()
      ..moveTo(0, topRadius.x)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(topRadius.x, topRadius.x),
          radius: topRadius.x,
        ),
        math.pi,
        math.pi / 2,
        false,
      )
      ..lineTo(topPoint.dx, topPoint.dy)
      ..cubicTo(
        controlTop.dx,
        controlTop.dy,
        controlBottom.dx,
        controlBottom.dy,
        bottomPoint.dx,
        bottomPoint.dy,
      )
      ..lineTo(0, size.height)
      ..close();
    final rightPath = Path()
      ..moveTo(size.width - topRadius.x, 0)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(size.width - topRadius.x, topRadius.x),
          radius: topRadius.x,
        ),
        math.pi * 1.5,
        math.pi / 2,
        false,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(bottomPoint.dx, bottomPoint.dy)
      ..cubicTo(
        controlBottom.dx,
        controlBottom.dy,
        controlTop.dx,
        controlTop.dy,
        topPoint.dx,
        topPoint.dy,
      )
      ..lineTo(size.width - topRadius.x, 0)
      ..close();

    canvas.drawPath(
      leftPath,
      _resolvePaint(decoration.leftColor, decoration.leftGradient, size),
    );
    canvas.drawPath(
      rightPath,
      _resolvePaint(decoration.rightColor, decoration.rightGradient, size),
    );

    // Each side's own full outline (top/side/bottom edges plus its half of
    // the curve), independent of the seam-only stroke below.
    //
    // 每一侧自己的整体轮廓（顶/侧/底边加上它那一半曲线），跟下面那条
    // 只描分界线的 stroke 是两回事。
    final leftBorderColor = decoration.leftBorderColor;
    if (leftBorderColor != null) {
      canvas.drawPath(
        leftPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = decoration.splitBorderWidth
          ..color = leftBorderColor,
      );
    }
    final rightBorderColor = decoration.rightBorderColor;
    if (rightBorderColor != null) {
      canvas.drawPath(
        rightPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = decoration.splitBorderWidth
          ..color = rightBorderColor,
      );
    }

    // The seam's own stroke, drawn on top of both fills so it reads clearly
    // regardless of whether leftColor/rightColor actually differ.
    // [dividerGradient] overrides [dividerColor] the same way
    // leftGradient/rightGradient override the fill colors. An optional
    // [dividerShadow] is stroked once first, offset/blurred/widened per its
    // own fields, as a soft glow/shadow sitting behind the crisp seam.
    //
    // 分界线自己的描边，画在两块填充之上，不管 leftColor/rightColor
    // 是否真的不同都能看得清楚。[dividerGradient] 覆盖 [dividerColor] 的
    // 方式跟 leftGradient/rightGradient 覆盖填充色一样。可选的
    // [dividerShadow] 会先描一遍（按自己的 offset/blur/宽度），作为叠在
    // 清晰描边下面的柔和阴影/发光。
    final dividerColor = decoration.dividerColor;
    final dividerGradient = decoration.dividerGradient;
    if (dividerColor != null || dividerGradient != null) {
      final dividerShadow = decoration.dividerShadow;
      if (dividerShadow != null) {
        canvas.save();
        canvas.translate(dividerShadow.offset.dx, dividerShadow.offset.dy);
        canvas.drawPath(
          curvePath,
          dividerShadow.toPaint()
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                decoration.dividerWidth + dividerShadow.spreadRadius * 2
            ..strokeCap = decoration.dividerCap,
        );
        canvas.restore();
      }

      final paint = dividerGradient != null
          ? (Paint()..shader = dividerGradient.createShader(Offset.zero & size))
          : (Paint()..color = dividerColor!);
      canvas.drawPath(
        curvePath,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = decoration.dividerWidth
          ..strokeCap = decoration.dividerCap,
      );
    }

    canvas.restore();
  }

  Paint _resolvePaint(Color color, LinearGradient? gradient, Size size) {
    if (gradient == null) return Paint()..color = color;
    return Paint()..shader = gradient.createShader(Offset.zero & size);
  }
}
