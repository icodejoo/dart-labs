import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/angles.dart';
import '../../core/foundation/constants.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/text.dart';
import '../../core/game/layout.dart';
import '../../core/geometry/fan_path.dart';
import '../../core/geometry/image_box.dart';
import '../../core/render/perf_trace.dart';
import '../../core/text/text_line.dart';
import '../model/wheel_config.dart';
import 'wheel_angles.dart';

/// 圆环图片槽分组。
const String _blocksGroup = 'blocks';

/// 奖品图片槽分组。
const String _prizesGroup = 'prizes';

/// 按钮图片槽分组。
const String _buttonsGroup = 'buttons';

/// 转盘在零旋转角时的只读几何，内容坐标以圆心为原点。
@immutable
final class WheelLayout extends LuckyLayout {
  /// 创建布局快照；列表应为不可变集合。
  const WheelLayout(
      {required super.size,
      required this.center,
      required this.radius,
      required this.prizeRadius,
      required this.maxBtnRadius,
      required this.angles,
      required this.blocks,
      required this.sectors,
      required this.buttons,
      required this.gutter});

  /// 圆心在宿主盒子中的位置。
  final Offset center;

  /// 外半径。
  final double radius;

  /// 奖品区域半径。
  final double prizeRadius;

  /// 所有按钮的最大半径。
  final double maxBtnRadius;

  /// 与 motion 共用的角度表。
  final WheelSectorAngles angles;

  /// 从外到内排列的圆环。
  final List<WheelBlockLayout> blocks;

  /// 顺时针排列的奖品扇区。
  final List<WheelSector> sectors;

  /// 按绘制顺序排列的按钮。
  final List<WheelButtonLayout> buttons;

  /// 扇区间隙。
  final double gutter;

  /// 半径非正时没有绘制内容。
  @override
  bool get isEmpty => radius <= 0;
}

/// 奖品的预计算路径、局部坐标和内容。
@immutable
final class WheelSector {
  /// 创建扇区几何，长度单位为逻辑像素。
  const WheelSector(
      {required this.index,
      required this.middleRad,
      required this.sweepRad,
      required this.fan,
      required this.anchor,
      required this.localRotation,
      required this.prizeHeight,
      required this.shortSide,
      required this.background,
      required this.images,
      required this.texts});

  /// 奖品下标。
  final int index;

  /// 中线角，单位为弧度。
  final double middleRad;

  /// 角宽，单位为弧度。
  final double sweepRad;

  /// 以圆心为原点的扇形路径。
  final Path fan;

  /// 局部坐标原点，即外缘中点。
  final Offset anchor;

  /// 局部坐标相对圆心坐标系的旋转角。
  final double localRotation;

  /// 奖品外缘到最大按钮的高度。
  final double prizeHeight;

  /// 外缘弦长。
  final double shortSide;

  /// 实际采用的背景。
  final LuckyFill? background;

  /// 局部坐标下的图片摆放规则。
  final List<LuckyImagePlacement> images;

  /// 已过滤空行的文字布局。
  final List<LuckyTextLine> texts;
}

/// 单个圆环的预计算内容。
@immutable
final class WheelBlockLayout {
  /// 创建圆环，图片与旋转列表一一对应。
  const WheelBlockLayout(
      {required this.radius,
      required this.background,
      required this.images,
      required this.rotate});

  /// 当前圆环半径。
  final double radius;

  /// 背景。
  final LuckyFill? background;

  /// 图片摆放规则。
  final List<LuckyImagePlacement> images;

  /// 各图片是否随盘旋转。
  final List<bool> rotate;
}

/// 单个按钮的预计算内容。
@immutable
final class WheelButtonLayout {
  /// 创建按钮几何；无指针填充时 [pointerPath] 为 null。
  const WheelButtonLayout(
      {required this.radius,
      required this.background,
      required this.pointer,
      required this.pointerPath,
      required this.images,
      required this.texts});

  /// 按钮半径。
  final double radius;

  /// 背景。
  final LuckyFill? background;

  /// 配置是否开启指针。
  final bool pointer;

  /// 指针路径，无背景或未开启时为 null。
  final Path? pointerPath;

  /// 图片摆放规则。
  final List<LuckyImagePlacement> images;

  /// 保留空行的文字布局。
  final List<LuckyTextLine> texts;
}

/// 按 [config] 和环境 [input] 计算布局；例如配合无头布局输入做离屏测量。
///
/// 调用方负责释放 input.measurer；不读取时钟，也不修改配置。
WheelLayout computeWheelLayout(WheelConfig config, LuckyLayoutInput input) {
  luckyTraceStart('luckdraw.wheel.layout');
  try {
    final side = math.min(input.size.width, input.size.height);
    final radius =
        side.isFinite ? math.max(0.0, side / kLuckyHalfDivisor) : 0.0;
    final alignment = input.alignment.resolve(input.textDirection);
    final center = alignment.alongOffset(Offset(
            input.size.width - radius * kLuckyHalfDivisor,
            input.size.height - radius * kLuckyHalfDivisor)) +
        Offset(radius, radius);
    var remaining = radius;
    final blocks = <WheelBlockLayout>[];
    for (var i = 0; i < config.blocks.length; i++) {
      final block = config.blocks[i];
      final diameter = remaining * kLuckyHalfDivisor;
      blocks.add(WheelBlockLayout(
          radius: remaining,
          background: block.background,
          images: _images(block.images, _blocksGroup, i, diameter, diameter,
              diameter, diameter,
              yOffset: -remaining),
          rotate: List.unmodifiable(block.images.map((p) => p.rotate))));
      remaining = math.max(0.0, remaining - block.padding);
    }
    final prizeRadius = remaining;
    final radii =
        config.buttons.map((b) => b.radius.resolve(prizeRadius)).toList();
    final maxBtnRadius = radii.fold(0.0, math.max);
    final prizeHeight = prizeRadius - maxBtnRadius;
    final angles = WheelSectorAngles.fromConfig(config);
    final sectors = <WheelSector>[];
    for (var i = 0; i < angles.count; i++) {
      final prize = config.prizes[i];
      final sweepRad = luckyDegToRad(angles.sweepDeg(i));
      // 上游 wheel.ts:311、324：等分时保留乘法位置与求值顺序。
      final middleRad = angles.uniform
          ? luckyDegToRad(kLuckyPointerDeg +
                  angles.prizeDeg / kLuckyHalfDivisor +
                  config.options.offsetDegree) +
              i * sweepRad
          : luckyDegToRad(kLuckyPointerDeg +
              config.options.offsetDegree +
              angles.startDeg(i) +
              angles.sweepDeg(i) / kLuckyHalfDivisor);
      final shortSide = prizeRadius *
          math.sin(sweepRad / kLuckyHalfDivisor) *
          kLuckyHalfDivisor;
      sectors.add(WheelSector(
          index: i,
          middleRad: middleRad,
          sweepRad: sweepRad,
          fan: buildFanPath(
              outerRadius: prizeRadius,
              start: middleRad - sweepRad / kLuckyHalfDivisor,
              end: middleRad + sweepRad / kLuckyHalfDivisor,
              gutter: config.options.gutter),
          anchor: Offset(math.cos(middleRad) * prizeRadius,
              math.sin(middleRad) * prizeRadius),
          localRotation: middleRad + math.pi / kLuckyHalfDivisor,
          prizeHeight: prizeHeight,
          shortSide: shortSide,
          background: prize.background ?? config.style.background,
          images: _images(prize.images, _prizesGroup, i, sweepRad * prizeRadius,
              prizeHeight, shortSide, prizeHeight),
          texts: _texts(
              prize.texts,
              config,
              input,
              shortSide,
              prizeHeight,
              (text, fontY) =>
                  (text.lengthLimit ?? config.style.text.lengthLimit).resolve(
                      (prizeRadius - fontY) *
                              math.tan(sweepRad / kLuckyHalfDivisor) *
                              kLuckyHalfDivisor -
                          config.options.gutter),
              dropEmptyLines: true)));
    }
    final buttons = <WheelButtonLayout>[];
    final chord = sectors.isEmpty ? 0.0 : sectors.last.shortSide;
    for (var i = 0; i < config.buttons.length; i++) {
      final button = config.buttons[i];
      final r = radii[i];
      final pointerPath = button.pointer && button.background != null
          ? (Path()
            ..moveTo(-r, 0)
            ..lineTo(r, 0)
            ..lineTo(0, -kLuckyHalfDivisor * r)
            ..close())
          : null;
      buttons.add(WheelButtonLayout(
          radius: r,
          background: button.background,
          pointer: button.pointer,
          pointerPath: pointerPath,
          images: _images(button.images, _buttonsGroup, i,
              r * kLuckyHalfDivisor, r * kLuckyHalfDivisor, r, r),
          texts: _texts(button.texts, config, input, chord, r, (_, fontY) => 0,
              wrap: false)));
    }
    return WheelLayout(
        size: input.size,
        center: center,
        radius: radius,
        prizeRadius: prizeRadius,
        maxBtnRadius: maxBtnRadius,
        angles: angles,
        blocks: List.unmodifiable(blocks),
        sectors: List.unmodifiable(sectors),
        buttons: List.unmodifiable(buttons),
        gutter: config.options.gutter);
  } finally {
    luckyTraceEnd();
  }
}

/// 生成以横向零点居中的图片规则，上游 wheel.ts:271-290、337-346、414-423。
List<LuckyImagePlacement> _images(
        List<LuckyImage> images,
        String group,
        int index,
        double maxWidth,
        double maxHeight,
        double leftBase,
        double topBase,
        {double yOffset = 0}) =>
    List.unmodifiable([
      for (var i = 0; i < images.length; i++)
        LuckyImagePlacement(
            slot: LuckyImageSlot(group, index, i),
            image: images[i],
            box: Rect.zero,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            leftBase: leftBase,
            topBase: topBase,
            yOffset: yOffset)
    ]);

/// 按玩法给定的逐行宽度生成文字，上游 wheel.ts:317-321、348-393、425-435。
List<LuckyTextLine> _texts(
        List<LuckyText> texts,
        WheelConfig config,
        LuckyLayoutInput input,
        double leftBase,
        double topBase,
        double Function(LuckyText text, double fontY) width,
        {bool dropEmptyLines = false,
        bool wrap = true}) =>
    List.unmodifiable([
      for (final text in texts)
        ...layoutLuckyTextLines(
            text: text,
            defaults: config.style.text,
            measurer: input.measurer,
            box: Rect.zero,
            leftBase: leftBase,
            topBase: topBase,
            maxWidthOf: (_, fontY) => width(text, fontY),
            dropEmptyLines: dropEmptyLines,
            wrap: wrap)
    ]);
