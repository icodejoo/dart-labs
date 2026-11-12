import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/easing/easing.dart';
import '../../core/foundation/angles.dart';
import '../../core/foundation/fill.dart';
import '../../core/motion/motion_options.dart';
import '../layout/lots_layout.dart';

import 'lots_parts.dart';

/// T5.7 的默认摇角和可见签槽数量。
const int _defaultVisible = 12;

/// T5.7 的升签与加速时长。
const Duration _defaultRiseTime = Duration(milliseconds: 600);

/// 根据累计相位 [phaseDeg]（度）返回有限的 [-1, 1] 摇动幅度。
///
/// 例如 `LotsOptions(shakeWaveform: (phaseDeg) => phaseDeg % 360 < 180 ? 1 : -1)`。
typedef LotsShakeWaveform = double Function(double phaseDeg);

/// 默认正弦波；将 [phaseDeg] 从度转弧度后返回 [-1, 1]。
///
/// 例如 `const LotsOptions(shakeWaveform: lotsSineWaveform)`。
double lotsSineWaveform(double phaseDeg) => math.sin(luckyDegToRad(phaseDeg));

/// 在默认布局 [base] 上返回最终布局；应保持签槽与角度数量相等。
///
/// 列表在使用期间不可修改；pivot 通常取 cylinder.bottomCenter。
/// 返回布局的 isEmpty 为 true 时按空布局处理，不绘制且不能开始抽签。
/// 例如 `LotsOptions(layoutAdjuster: (base) => base.copyWith(riseDistance: 80))`。
typedef LotsLayoutAdjuster = LotsLayout Function(LotsLayout base);

/// 在布局坐标系中完整绘制一个部件，替代对应的默认填充。
///
/// [canvas] 仅在缓存首次录制时调用，配置或布局等缓存输入变化后重新录制；
/// [layout] 是调整后的最终布局。无需返回值。
/// 例如 `LotsStyle(cylinderFrontPainter: (canvas, layout) =>
/// canvas.drawOval(layout.cylinder, Paint()))`。
typedef LotsPartPainter = void Function(Canvas canvas, LotsLayout layout);

/// 完整绘制签身，替代默认填充与标签；无需返回值。
///
/// [canvas] 已平移至签矩形左上角，[size] 是实际签尺寸；[stick] 为空时为
/// 未抽中的空白签，非空时为升起的目标签。空白签按槽位、目标签按候选下标
/// 各录制一次，配置或布局等缓存输入变化后重新录制，不随动画帧调用。
/// 例如 `LotsStyle(stickPainter: (canvas, size, stick) =>
/// canvas.drawRect(Offset.zero & size, Paint()))`；可按 stick?.label 绘制文字。
typedef LotsStickBodyPainter = void Function(
    Canvas canvas, Size size, LotsStick? stick);

/// 抽签配置；签与选奖权重一一对应。
@immutable
final class LotsConfig {
  /// 创建配置；列表在使用期间不可修改。
  const LotsConfig(
      {this.sticks = const [],
      this.options = const LotsOptions(),
      this.style = const LotsStyle()});

  /// 候选签列表。
  final List<LotsStick> sticks;

  /// 运动和布局参数。
  final LotsOptions options;

  /// 签筒和展示卡样式。
  final LotsStyle style;

  /// 返回只替换非空参数的副本。
  LotsConfig copyWith(
          {List<LotsStick>? sticks, LotsOptions? options, LotsStyle? style}) =>
      LotsConfig(
          sticks: sticks ?? this.sticks,
          options: options ?? this.options,
          style: style ?? this.style);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is LotsConfig &&
      listEquals(other.sticks, sticks) &&
      other.options == options &&
      other.style == style;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([Object.hashAll(sticks), options, style]);
}

/// 抽签参数；升签与展示都属于减速收尾阶段。
@immutable
final class LotsOptions {
  /// 创建配置；列表在使用期间不可修改。
  const LotsOptions(
      {this.maxShakeDeg = _defaultVisible * 1.0,
      this.visibleSticks = _defaultVisible,
      this.riseTime = _defaultRiseTime,
      this.revealTime = const Duration(milliseconds: 400),
      this.revealOnSettle = true,
      this.riseEasing = LuckyEasings.quad,
      this.revealEasing = LuckyEasings.cubic,
      this.shakeWaveform = lotsSineWaveform,
      this.layoutAdjuster,
      this.motion = const LuckyMotionOptions(
          accelerationTime: _defaultRiseTime,
          decelerationTime: Duration(milliseconds: 900))});

  /// 最大摇动角度。
  final double maxShakeDeg;

  /// 可见签槽数量，至少一个。
  final int visibleSticks;

  /// 升签时长。
  final Duration riseTime;

  /// 展示签文时长。
  final Duration revealTime;

  /// 是否展示签文卡。
  final bool revealOnSettle;

  /// 升签缓动；调用 easeOut(elapsedMs, 0, 1, riseMs) 得到零至一进度。
  ///
  /// 例如 `const LotsOptions(riseEasing: LuckyEasings.sine)`。
  final LuckyEasing riseEasing;

  /// 翻卡缓动；调用 easeOut(elapsedMs, 0, 1, revealMs) 得到零至一进度。
  ///
  /// 例如 `const LotsOptions(revealEasing: LuckyEasings.quad)`。
  final LuckyEasing revealEasing;

  /// 摇动波形；最终角度为当前振幅乘以 shakeWaveform(shakePhaseDeg)。
  ///
  /// 参数、返回值与示例见 [LotsShakeWaveform]；闭包按引用比较。
  final LotsShakeWaveform shakeWaveform;

  /// 默认布局的可选调整器；空时保留默认布局。
  ///
  /// 契约与示例见 [LotsLayoutAdjuster]；闭包按引用比较。
  final LotsLayoutAdjuster? layoutAdjuster;

  /// 摇动相位速度、缓动和时间基准。
  final LuckyMotionOptions motion;

  /// 返回只替换非空参数的副本。
  LotsOptions copyWith(
          {double? maxShakeDeg,
          int? visibleSticks,
          Duration? riseTime,
          Duration? revealTime,
          bool? revealOnSettle,
          LuckyEasing? riseEasing,
          LuckyEasing? revealEasing,
          LotsShakeWaveform? shakeWaveform,
          LotsLayoutAdjuster? layoutAdjuster,
          LuckyMotionOptions? motion}) =>
      LotsOptions(
          maxShakeDeg: maxShakeDeg ?? this.maxShakeDeg,
          visibleSticks: visibleSticks ?? this.visibleSticks,
          riseTime: riseTime ?? this.riseTime,
          revealTime: revealTime ?? this.revealTime,
          revealOnSettle: revealOnSettle ?? this.revealOnSettle,
          riseEasing: riseEasing ?? this.riseEasing,
          revealEasing: revealEasing ?? this.revealEasing,
          shakeWaveform: shakeWaveform ?? this.shakeWaveform,
          layoutAdjuster: layoutAdjuster ?? this.layoutAdjuster,
          motion: motion ?? this.motion);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is LotsOptions &&
      other.maxShakeDeg == maxShakeDeg &&
      other.visibleSticks == visibleSticks &&
      other.riseTime == riseTime &&
      other.revealTime == revealTime &&
      other.revealOnSettle == revealOnSettle &&
      other.riseEasing == riseEasing &&
      other.revealEasing == revealEasing &&
      other.shakeWaveform == shakeWaveform &&
      other.layoutAdjuster == layoutAdjuster &&
      other.motion == motion;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        maxShakeDeg,
        visibleSticks,
        riseTime,
        revealTime,
        revealOnSettle,
        riseEasing,
        revealEasing,
        shakeWaveform,
        layoutAdjuster,
        motion
      ]);
}

/// 签筒、签和展示卡的样式。
@immutable
final class LotsStyle {
  /// 创建配置；列表在使用期间不可修改。
  const LotsStyle(
      {this.background = const LuckyFill.color(Color(0xFFF7EBD6)),
      this.cylinderFill = const LuckyFill.color(Color(0xFF9E342B)),
      this.backFill = const LuckyFill.color(Color(0xFF592820)),
      this.stickFill = const LuckyFill.color(Color(0xFFEBC582)),
      this.cardFill = const LuckyFill.color(Color(0xFFFFF8E1)),
      this.textColor = const Color(0xFF4E261B),
      this.fontSize = 18,
      this.fontFamily,
      this.backgroundPainter,
      this.cylinderBackPainter,
      this.cylinderFrontPainter,
      this.stickPainter});

  /// 盒子背景。
  final LuckyFill background;

  /// 签筒前壁填充。
  final LuckyFill cylinderFill;

  /// 签筒后壁填充。
  final LuckyFill backFill;

  /// 无字签填充。
  final LuckyFill stickFill;

  /// 签文卡填充。
  final LuckyFill cardFill;

  /// 默认文字颜色。
  final Color textColor;

  /// 默认字号。
  final double fontSize;

  /// 默认字体；空时使用平台默认字体。
  final String? fontFamily;

  /// 替代背景填充；空时沿用默认绘制，契约与示例见 [LotsPartPainter]。
  final LotsPartPainter? backgroundPainter;

  /// 替代签筒后壁填充；空时沿用默认绘制，契约见 [LotsPartPainter]。
  final LotsPartPainter? cylinderBackPainter;

  /// 替代签筒前壁填充；空时沿用默认绘制，契约见 [LotsPartPainter]。
  final LotsPartPainter? cylinderFrontPainter;

  /// 替代空白签与目标签绘制；空时沿用默认绘制，契约见 [LotsStickBodyPainter]。
  ///
  /// 这些部件绘制闭包均按引用比较；签文卡仍使用 LotsStick.painter 扩展。
  final LotsStickBodyPainter? stickPainter;

  /// 返回只替换非空参数的副本。
  LotsStyle copyWith(
          {LuckyFill? background,
          LuckyFill? cylinderFill,
          LuckyFill? backFill,
          LuckyFill? stickFill,
          LuckyFill? cardFill,
          Color? textColor,
          double? fontSize,
          String? fontFamily,
          LotsPartPainter? backgroundPainter,
          LotsPartPainter? cylinderBackPainter,
          LotsPartPainter? cylinderFrontPainter,
          LotsStickBodyPainter? stickPainter}) =>
      LotsStyle(
          background: background ?? this.background,
          cylinderFill: cylinderFill ?? this.cylinderFill,
          backFill: backFill ?? this.backFill,
          stickFill: stickFill ?? this.stickFill,
          cardFill: cardFill ?? this.cardFill,
          textColor: textColor ?? this.textColor,
          fontSize: fontSize ?? this.fontSize,
          fontFamily: fontFamily ?? this.fontFamily,
          backgroundPainter: backgroundPainter ?? this.backgroundPainter,
          cylinderBackPainter: cylinderBackPainter ?? this.cylinderBackPainter,
          cylinderFrontPainter:
              cylinderFrontPainter ?? this.cylinderFrontPainter,
          stickPainter: stickPainter ?? this.stickPainter);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is LotsStyle &&
      other.background == background &&
      other.cylinderFill == cylinderFill &&
      other.backFill == backFill &&
      other.stickFill == stickFill &&
      other.cardFill == cardFill &&
      other.textColor == textColor &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.backgroundPainter == backgroundPainter &&
      other.cylinderBackPainter == cylinderBackPainter &&
      other.cylinderFrontPainter == cylinderFrontPainter &&
      other.stickPainter == stickPainter;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        background,
        cylinderFill,
        backFill,
        stickFill,
        cardFill,
        textColor,
        fontSize,
        fontFamily,
        backgroundPainter,
        cylinderBackPainter,
        cylinderFrontPainter,
        stickPainter
      ]);
}
