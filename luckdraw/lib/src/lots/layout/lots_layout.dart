import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/angles.dart';
import '../../core/foundation/constants.dart';
import '../../core/game/layout.dart';
import '../../core/render/perf_trace.dart';
import '../model/lots_config.dart';

/// T5.7 签筒宽度比例。
const double _cylinderWidth = 0.42;

/// T5.7 签筒高度比例。
const double _cylinderHeight = 0.55;

/// T5.7 签筒底部留白比例。
const double _bottomGap = 0.08;

/// T5.7 签槽最大扇形角。
const double _fanAngle = 24;

/// T5.7 签长确定性种子。
const double _lengthSeed = 0.618;

/// T5.7 签长起始比例。
const double _lengthBase = 0.6;

/// T5.7 签长变化比例。
const double _lengthRange = 0.4;

/// 签长相对盒高比例。
const double _stickLength = 0.36;

/// 签宽相对盒宽比例。
const double _stickWidth = 0.035;

/// T5.7 升签距离相对盒高比例。
const double _rise = 0.35;

/// 展示卡水平留白比例。
const double _cardMargin = 0.08;

/// 展示卡高度比例。
const double _cardHeight = 0.32;

/// 抽签不可变几何；槽位坐标以盒子左上角为原点。
@immutable
final class LotsLayout extends LuckyLayout {
  /// 指定签筒、转轴、签槽和展示卡。
  const LotsLayout(
      {required super.size,
      required this.cylinder,
      required this.pivot,
      required this.sticks,
      required this.angles,
      required this.riseDistance,
      required this.card});

  /// 签筒前壁边界。
  final Rect cylinder;

  /// 底边中点，摇动转轴。
  final Offset pivot;

  /// 各槽位未旋转的签矩形。
  final List<Rect> sticks;

  /// 各槽位扇形旋转角，单位为弧度。
  final List<double> angles;

  /// 目标签上升距离。
  final double riseDistance;

  /// 上半区展示卡。
  final Rect card;

  /// 返回只替换非空参数的布局；列表在使用期间不可修改。
  ///
  /// sticks.length 必须等于 angles.length，pivot 通常取 cylinder.bottomCenter。
  /// 例如 `base.copyWith(cylinder: rect, pivot: rect.bottomCenter)`。
  LotsLayout copyWith(
          {Size? size,
          Rect? cylinder,
          Offset? pivot,
          List<Rect>? sticks,
          List<double>? angles,
          double? riseDistance,
          Rect? card}) =>
      LotsLayout(
          size: size ?? this.size,
          cylinder: cylinder ?? this.cylinder,
          pivot: pivot ?? this.pivot,
          sticks: sticks ?? this.sticks,
          angles: angles ?? this.angles,
          riseDistance: riseDistance ?? this.riseDistance,
          card: card ?? this.card);

  /// 零尺寸或无签槽时不可绘制。
  @override
  bool get isEmpty => size.isEmpty || sticks.isEmpty;

  /// 返回升起后目标签未旋转的矩形；[slot] 必须是有效槽位。
  Rect raisedStick(int slot) => sticks[slot].shift(Offset(0, -riseDistance));
}

/// 计算签筒与确定性扇形签槽；零尺寸或无候选签返回空布局。
LotsLayout computeLotsLayout(LotsConfig config, LuckyLayoutInput input) {
  luckyTraceStart('luckdraw.lots.layout');
  try {
    final w = math.max(0.0, input.size.width),
        h = math.max(0.0, input.size.height);
    final cylinder = Rect.fromLTWH(
        w * (1 - _cylinderWidth) / kLuckyHalfDivisor,
        h * (1 - _bottomGap - _cylinderHeight),
        w * _cylinderWidth,
        h * _cylinderHeight);
    final count = w > 0 && h > 0 && config.sticks.isNotEmpty
        ? math.max(1, config.options.visibleSticks)
        : 0;
    final sticks = <Rect>[], angles = <double>[];
    for (var slot = 0; slot < count; slot++) {
      final length = h *
          _stickLength *
          (_lengthBase + _lengthRange * (_lengthSeed * (slot + 1) % 1));
      sticks.add(Rect.fromLTWH(
          w / kLuckyHalfDivisor - w * _stickWidth / kLuckyHalfDivisor,
          cylinder.top - length,
          w * _stickWidth,
          length + cylinder.height * _lengthRange));
      angles.add(luckyDegToRad(count == 1
          ? 0
          : -_fanAngle + kLuckyHalfDivisor * _fanAngle * slot / (count - 1)));
    }
    final base = LotsLayout(
        size: input.size,
        cylinder: cylinder,
        pivot: cylinder.bottomCenter,
        sticks: List.unmodifiable(sticks),
        angles: List.unmodifiable(angles),
        riseDistance: h * _rise,
        card: Rect.fromLTWH(w * _cardMargin, h * _cardMargin,
            w * (1 - kLuckyHalfDivisor * _cardMargin), h * _cardHeight));
    final layout = config.options.layoutAdjuster?.call(base) ?? base;
    assert(layout.isEmpty || layout.sticks.length == layout.angles.length);
    return layout;
  } finally {
    luckyTraceEnd();
  }
}
