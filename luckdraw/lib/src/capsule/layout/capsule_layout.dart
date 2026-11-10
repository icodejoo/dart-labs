import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/game/layout.dart';
import '../../core/kinematics/swirl_mixer.dart';
import '../../core/render/perf_trace.dart';
import '../../core/text/text_line.dart';
import '../model/capsule_config.dart';

/// 布局比例，来自 IMPLEMENTATION_GUIDE T5.2。
const double _half = 0.5;

/// 球体距顶部的高度比例。
const double _top = 0.04;

/// 球体半径占高度上限。
const double _maxRadius = 0.3;

/// 机身半宽倍数。
const double _bodyWidth = 1.1;

/// 机身起点相对球心的半径倍数。
const double _bodyTop = 0.85;

/// 托盘高度比例。
const double _trayHeight = 0.16;

/// 旋钮半径比例。
const double _knobRadius = 0.22;

/// 球体出口纵向比例。
const double _exitY = 0.92;

/// 卡片宽度比例。
const double _cardWidth = 0.8;

/// 卡片高度比例。
const double _cardHeight = 0.36;

/// 扭蛋机不可变几何；圆内位置相对球心，掉落折线为盒子坐标。
@immutable
final class CapsuleLayout extends LuckyLayout {
  /// 创建布局；集合在构造时冻结，调用者不可修改。
  CapsuleLayout(
      {required super.size,
      required this.globeCenter,
      required this.globeRadius,
      required this.capsuleRadius,
      required List<int> capsules,
      required List<Offset> rest,
      required this.body,
      required this.knobCenter,
      required this.knobRadius,
      required this.exit,
      required List<Offset> dropPath,
      required this.tray,
      required this.card,
      required List<List<LuckyTextLine>> cardTexts})
      : cardCenter = card.center,
        dropLength = _pathLength(dropPath),
        capsules = List.unmodifiable(capsules),
        rest = List.unmodifiable(rest),
        dropPath = List.unmodifiable(dropPath),
        cardTexts =
            List.unmodifiable(cardTexts.map(List<LuckyTextLine>.unmodifiable)),
        lengths = List.unmodifiable(List.generate(
            math.max(0, dropPath.length - 1),
            (i) => (dropPath[i + 1] - dropPath[i]).distance));

  /// 球体圆心。
  final Offset globeCenter;

  /// 球体半径。
  final double globeRadius;

  /// 胶囊半径。
  final double capsuleRadius;

  /// 每个胶囊的奖品下标。
  final List<int> capsules;

  /// 静止堆积的圆心相对坐标。
  final List<Offset> rest;

  /// 机身区域。
  final Rect body;

  /// 旋钮圆心。
  final Offset knobCenter;

  /// 旋钮半径。
  final double knobRadius;

  /// 球体出口。
  final Offset exit;

  /// 掉落折线，包含首尾四点。
  final List<Offset> dropPath;

  /// 折线各段弧长。
  final List<double> lengths;

  /// 预计算的掉落总弧长。
  final double dropLength;

  /// 预计算的卡片缩放中心，帧绘制不创建 Offset。
  final Offset cardCenter;

  /// 托盘区域。
  final Rect tray;

  /// 奖品卡区域。
  final Rect card;

  /// 各奖品卡预先测量的文字行。
  final List<List<LuckyTextLine>> cardTexts;

  /// 零尺寸布局没有可绘制内容。
  @override
  bool get isEmpty => size.isEmpty;

  /// 按弧长返回掉落位置；[progress] 钳到零至一。
  Offset dropPosition(double progress) {
    if (dropPath.isEmpty) return Offset.zero;
    var distance = lengths.fold(0.0, (a, b) => a + b) * progress.clamp(0, 1);
    for (var i = 0; i < lengths.length; i++) {
      if (distance <= lengths[i] && lengths[i] > 0) {
        return dropPath[i] +
            (dropPath[i + 1] - dropPath[i]) * (distance / lengths[i]);
      }
      distance -= lengths[i];
    }
    return dropPath.last;
  }
}

/// 在布局阶段累计掉落弧长。
double _pathLength(List<Offset> points) {
  var result = 0.0;
  for (var i = 1; i < points.length; i++) {
    result += (points[i] - points[i - 1]).distance;
  }
  return result;
}

/// 计算确定性几何；零尺寸返回空布局，负胶囊数量按零处理，无效奖品下标忽略。
CapsuleLayout computeCapsuleLayout(
    CapsuleConfig config, LuckyLayoutInput input) {
  luckyTraceStart('luckdraw.capsule.layout');
  try {
    final size = input.size.isEmpty ? Size.zero : input.size;
    final w = size.width, h = size.height;
    final radius = math.min(
        w * config.options.globeRadiusFactor.clamp(0, _half), h * _maxRadius);
    final rc = radius * config.options.capsuleRadiusFactor.clamp(0, 1);
    final center = Offset(w * _half, h * _top + radius);
    final body = Rect.fromLTRB(
        math.max(0, w * _half - _bodyWidth * radius),
        center.dy + _bodyTop * radius,
        math.min(w, w * _half + _bodyWidth * radius),
        h * (1 - _trayHeight));
    final tray = Rect.fromLTWH(0, h * (1 - _trayHeight), w, h * _trayHeight);
    final exit = center + Offset(0, radius * _exitY);
    final card = Rect.fromLTWH(w * (1 - _cardWidth) * _half,
        tray.top - h * _cardHeight, w * _cardWidth, h * _cardHeight);
    final capsules = config.capsules
            ?.where((i) => i >= 0 && i < config.prizes.length)
            .toList() ??
        [
          for (var i = 0; i < config.prizes.length; i++)
            for (var j = 0; j < math.max(0, config.capsulesPerPrize); j++) i
        ];
    return CapsuleLayout(
        size: size,
        globeCenter: center,
        globeRadius: radius,
        capsuleRadius: rc,
        capsules: capsules,
        rest: packCirclesInCircle(
            count: capsules.length, containerRadius: radius, bodyRadius: rc),
        body: body,
        knobCenter: body.center,
        knobRadius: radius * _knobRadius,
        exit: exit,
        dropPath: [
          exit,
          Offset(body.center.dx + radius * _half, body.center.dy),
          Offset(body.right - rc, body.bottom - rc),
          tray.center
        ],
        tray: tray,
        card: card,
        cardTexts: [
          for (final prize in config.prizes)
            [
              for (final text in prize.texts)
                ...layoutLuckyTextLines(
                    text: text,
                    defaults: config.style.text,
                    override: config.style.card.text,
                    measurer: input.measurer,
                    box: card,
                    leftBase: card.width,
                    topBase: card.height,
                    maxWidthOf: (_, __) => card.width)
            ]
        ]);
  } finally {
    luckyTraceEnd();
  }
}
