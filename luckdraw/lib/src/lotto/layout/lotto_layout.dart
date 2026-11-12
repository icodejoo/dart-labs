import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/constants.dart';
import '../../core/game/layout.dart';
import '../../core/kinematics/swirl_mixer.dart';
import '../../core/render/perf_trace.dart';
import '../model/lotto_config.dart';

/// T5.9 的横向容器留白比例。
const double _drumWidth = 0.85;

/// T5.9 的容器高度上限比例。
const double _drumHeight = 0.28;

/// 结果槽行中心高度比例。
const double _resultY = 0.9;

/// 按钮中心高度比例。
const double _buttonY = 0.7;

/// 按钮半径高度比例。
const double _buttonRadius = 0.07;

/// 单池几何，坐标采用玩法盒子局部坐标。
@immutable
final class LottoDrumLayout {
  /// 创建容器与球的静止布局。
  const LottoDrumLayout(
      {required this.center,
      required this.radius,
      required this.ballRadius,
      required this.rest,
      required this.exit,
      required this.slots,
      required this.min});

  /// 容器圆心。
  final Offset center;

  /// 容器半径。
  final double radius;

  /// 号码球半径。
  final double ballRadius;

  /// 每个号码球的静止位置，相对容器圆心。
  final List<Offset> rest;

  /// 出口中心。
  final Offset exit;

  /// 按抽出顺序排列的结果槽中心。
  final List<Offset> slots;

  /// 第一颗球对应的号码。
  final int min;
}

/// 摇奖机布局；只含低频计算的几何数据。
@immutable
final class LottoLayout extends LuckyLayout {
  /// 创建布局；空尺寸应传空 drums 和 Rect.zero。
  const LottoLayout(
      {required super.size,
      required this.drums,
      required this.button,
      required this.slotRadius});

  /// 各号码池容器。
  final List<LottoDrumLayout> drums;

  /// 开始按钮命中区域。
  final Rect button;

  /// 结果槽半径。
  final double slotRadius;

  /// 是否没有可绘制内容。
  @override
  bool get isEmpty => drums.isEmpty;
}

/// 计算摇奖机布局；例如传入 headless 布局环境，零尺寸返回空布局。
LottoLayout computeLottoLayout(LottoConfig config, LuckyLayoutInput input) {
  luckyTraceStart('luckdraw.lotto.layout');
  try {
    config.validate();
    final size = input.size;
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return LottoLayout(
          size: size, drums: const [], button: Rect.zero, slotRadius: 0);
    }
    final m = config.pools.length;
    final radius = math.min(size.width / (kLuckyHalfDivisor * m) * _drumWidth,
        _drumHeight * size.height);
    final count = config.pools.fold<int>(0, (n, p) => n + p.count);
    final cell = size.width / (count + m);
    final ballRadius = math.min(radius * config.options.ballRadiusFactor,
        math.min(cell, size.height * (1 - _resultY)) / kLuckyHalfDivisor);
    final drums = <LottoDrumLayout>[];
    var slot = 0;
    for (var p = 0; p < m; p++) {
      final pool = config.pools[p];
      final center = Offset(size.width * (p + 1 / kLuckyHalfDivisor) / m,
          size.height * _drumHeight);
      final slots = List.generate(pool.count,
          (j) => Offset(cell * (slot + j + 1), size.height * _resultY));
      slot += pool.count + 1;
      drums.add(LottoDrumLayout(
          center: center,
          radius: radius,
          ballRadius: ballRadius,
          rest: List.unmodifiable(packCirclesInCircle(
              count: pool.max - pool.min + 1,
              containerRadius: radius,
              bodyRadius: ballRadius)),
          exit: center + Offset(0, radius),
          slots: List.unmodifiable(slots),
          min: pool.min));
    }
    final buttonRadius = math.min(
        size.width / (m * kLuckyHalfDivisor), size.height * _buttonRadius);
    return LottoLayout(
        size: size,
        drums: List.unmodifiable(drums),
        button: Rect.fromCircle(
            center:
                Offset(size.width / kLuckyHalfDivisor, size.height * _buttonY),
            radius: buttonRadius),
        slotRadius: ballRadius);
  } finally {
    luckyTraceEnd();
  }
}
