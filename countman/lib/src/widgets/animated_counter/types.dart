// Copied from flip_counter_plus (MIT) with namespace renames.
// Original: https://github.com/Itsxhadi/flip_counter_plus

import 'package:flutter/foundation.dart';

/// The direction in which the stagger effect propagates across digits.
enum StaggerDirection {
  /// Animations start from the leftmost digit (most significant) and move right.
  leftToRight,

  /// Animations start from the rightmost digit (least significant) and move left.
  rightToLeft,
}

/// Predefined numeral systems for internationalization.
enum NumeralSystem {
  latin,
  easternArabic,
  persian,
  devanagari,
  bengali,
}

/// Primary per-digit movement for [CounterTransition]. Exactly one applies;
/// [CounterTransition.scale] / `.fade` / `.blur` layer on top of it.
///
/// [CounterTransition] 的逐位主运动。只取其一；[CounterTransition.scale] /
/// `.fade` / `.blur` 叠加其上。
enum CounterMotion {
  /// No movement — the digit swaps in place (pair with `fade`/`scale`).
  ///
  /// 无位移——原地切换（配 `fade`/`scale` 用）。
  none,

  /// Odometer vertical/horizontal scroll (GPU-composited translate + clip).
  ///
  /// 里程表式垂直/水平滚动（GPU 合成的位移 + 裁剪）。
  slide,

  /// 2-D rotation of the outgoing/incoming digit around the cell center.
  ///
  /// 离场/入场数位绕单元中心的 2D 旋转。
  rotate,

  /// 3-D flip around the X axis (perspective) — one face shown at a time.
  ///
  /// 绕 X 轴的 3D 翻转（透视）——同一时刻只显示一面。
  flip,
}

/// Composable digit transition: pick one [motion] and layer independent
/// [scale] / [fade] / [blur] modifiers — any combination, no enum explosion.
/// Named presets ([slide], [fade], [scale], [rotate], [flip], [flipFade],
/// [slideScale], [blur]) cover the common looks.
///
/// 可组合的数位过渡：选一个 [motion]，叠加相互独立的 [scale] / [fade] / [blur]
/// 修饰——任意组合，无枚举爆炸。命名预设（[slide]、[fade]、[scale]、[rotate]、
/// [flip]、[flipFade]、[slideScale]、[blur]）覆盖常见外观。
@immutable
class CounterTransition {
  /// Creates a transition. Defaults to [motion] = slide with a cross-fade.
  ///
  /// 创建一个过渡。默认 [motion] = slide 且带交叉淡入。
  const CounterTransition({
    this.motion = CounterMotion.slide,
    this.fade = true,
    this.scale = false,
    this.blur = false,
  });

  /// Primary movement (see [CounterMotion]).
  ///
  /// 主运动（见 [CounterMotion]）。
  final CounterMotion motion;

  /// Cross-fade the outgoing digit out and the incoming digit in.
  ///
  /// 让离场数位淡出、入场数位淡入。
  final bool fade;

  /// Scale the outgoing digit down to nothing / the incoming digit up from it.
  ///
  /// 离场数位缩小消失 / 入场数位由无放大。
  final bool scale;

  /// Motion-blur the column while it transitions (GPU `saveLayer` — avoid many
  /// simultaneous instances in production).
  ///
  /// 过渡期间对该列做运动模糊（GPU `saveLayer`——生产中避免大量并发实例）。
  final bool blur;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  CounterTransition copyWith({
    CounterMotion? motion,
    bool? fade,
    bool? scale,
    bool? blur,
  }) =>
      CounterTransition(
        motion: motion ?? this.motion,
        fade: fade ?? this.fade,
        scale: scale ?? this.scale,
        blur: blur ?? this.blur,
      );

  @override
  bool operator ==(Object other) =>
      other is CounterTransition &&
      other.motion == motion &&
      other.fade == fade &&
      other.scale == scale &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(motion, fade, scale, blur);

  // ── presets ─────────────────────────────────────────────────────────────────
  // Common motion combos as named presets. Pure-modifier looks are one-liner
  // constructors: fade = `CounterTransition(motion: CounterMotion.none)`,
  // scale = `CounterTransition(motion: CounterMotion.none, scale: true)`,
  // blur  = `CounterTransition(blur: true)`. (No `fade`/`scale`/`blur` static
  // presets — they'd clash with the same-named bool fields.)
  //
  // 常见运动组合的命名预设。纯修饰外观用一行构造：fade / scale / blur 见上。
  // （不设 `fade`/`scale`/`blur` 静态预设——会与同名 bool 字段冲突。）

  /// Odometer slide with cross-fade (the default look).
  static const CounterTransition slide =
      CounterTransition(motion: CounterMotion.slide, fade: true);

  /// Slide while scaling — the digit shrinks out and grows in as it scrolls.
  static const CounterTransition slideScale =
      CounterTransition(motion: CounterMotion.slide, scale: true, fade: true);

  /// Slide with motion blur.
  static const CounterTransition slideBlur =
      CounterTransition(motion: CounterMotion.slide, fade: true, blur: true);

  /// 2-D rotation with cross-fade.
  static const CounterTransition rotate =
      CounterTransition(motion: CounterMotion.rotate, fade: true);

  /// 3-D flip, no fade (each face fully opaque).
  static const CounterTransition flip =
      CounterTransition(motion: CounterMotion.flip, fade: false);

  /// 3-D flip with a cross-fade on each face.
  static const CounterTransition flipFade =
      CounterTransition(motion: CounterMotion.flip, fade: true);
}

// ignore: library_private_types_in_public_api
const Map<NumeralSystem, List<String>> numeralSystemDigits = {
  NumeralSystem.latin:         ['0','1','2','3','4','5','6','7','8','9'],
  NumeralSystem.easternArabic: ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'],
  NumeralSystem.persian:       ['۰','۱','۲','۳','۴','۵','۶','۷','۸','۹'],
  NumeralSystem.devanagari:    ['०','१','२','३','४','५','६','७','८','९'],
  NumeralSystem.bengali:       ['০','১','২','৩','৪','৫','৬','৭','৮','৯'],
};

/// Resolves the odometer triple a single digit column renders THIS frame,
/// shared by the painter fast-path ([CounterPainter.resolveColumnPhase]) and
/// the widget-tree path ([DigitColumn]) so the trajectory + end-of-roll
/// ghost-prevention math lives in ONE tested place instead of being mirrored.
///
/// 解析单个数位列本帧渲染的三元组，由 painter 快路径
/// （[CounterPainter.resolveColumnPhase]）与组件树路径（[DigitColumn]）共用，
/// 使滚动轨迹与滚动末尾防幻影逻辑集中于一处、不再镜像重复。
///
/// @param fast Fast mode: a single step [fastFrom] → [fastTo] with [position]
///   as the 0–1 progress; off = a continuous odometer where [position] is the
///   cumulative place value, monotonic in [increasing].
///
///   快速模式：从 [fastFrom] 单步到 [fastTo]，[position] 为 0–1 进度；关闭 =
///   连续里程表，[position] 为累计位值，沿 [increasing] 方向单调。
///
/// @param fastFrom int — the digit this column starts on (fast mode).
///
///   本列起始数位（快速模式）。
///
/// @param fastTo int — the digit this column ends on / its target digit.
///
///   本列终止数位 / 目标数位。
///
/// @param position double — animation position (progress or cumulative value).
///
///   动画位置（进度或累计值）。
///
/// @param increasing bool — true when the value is growing (roll up).
///
///   值增长（向上滚）时为 true。
///
/// @param targetDigit int — this place's target digit, for ghost-prevention.
///
///   本位的目标数位，用于防幻影。
///
/// @param target double — this place's cumulative target value.
///
///   本位的累计目标值。
///
/// @param hasTarget bool — whether [targetDigit]/[target] are known; when false
///   the end-of-roll snap is skipped (unit tests / custom painters).
///
///   [targetDigit]/[target] 是否已知；为 false 时跳过滚动末尾吸附
///   （单元测试 / 自定义 painter）。
///
/// @param eps double — approach tolerance for the ghost-prevention snap.
///
///   防幻影吸附的接近容差。
///
/// @returns Record `(int cur, int nxt, double p)` — the digit being left, the
///   digit arriving, and the 0–1 roll phase from cur → nxt.
///
///   记录 `(int cur, int nxt, double p)` —— 离开位、到来位，以及 cur → nxt 的
///   0–1 滚动相位。
(int cur, int nxt, double p) resolveDigitPhase({
  required bool fast,
  required int fastFrom,
  required int fastTo,
  required double position,
  required bool increasing,
  required int targetDigit,
  required double target,
  required bool hasTarget,
  double eps = 1e-3,
}) {
  if (fast) {
    // Unchanged digit → stay static (progress 0) instead of sliding X→X.
    //
    // 数位不变 → 保持静止（进度 0），而非从 X 滑到 X。
    final p = fastFrom == fastTo ? 0.0 : position.clamp(0.0, 1.0);
    return (fastFrom, fastTo, p);
  }
  if (increasing) {
    // Monotonic upward: floor is the digit being left, next is +1 (mod 10).
    //
    // 单调向上：floor 为正在离开的位，下一位为 +1（对 10 取模）。
    final fl = position.floor();
    final cur = (fl % 10 + 10) % 10;
    var p = (position - fl).clamp(0.0, 1.0);
    // Within one step of the target and already on the target digit → rest, so
    // this place doesn't roll on while faster lower places finish then snap
    // back. Bounded to the APPROACH (position <= target) so a bounce overshoot
    // still rolls.
    //
    // 距目标不足一步且已在目标数位 → 停住，避免在更快低位收尾时继续滚动再弹回。
    // 限定“接近阶段”（position <= target），故 bounce 越过仍会滚动。
    if (hasTarget && cur == targetDigit && position >= target - 1.0 && position <= target + eps) {
      p = 0.0;
    }
    return (cur, (cur + 1) % 10, p);
  }
  // Monotonic downward: ceil is the digit being left, next is −1 (mod 10).
  // ceil keeps the roll phase right across the 0/9 wrap and for the negative
  // positions a wrapped decrease produces.
  //
  // 单调向下：ceil 为正在离开的位，下一位为 −1（对 10 取模）。ceil 可在跨 0/9
  // 环绕及递减环绕产生的负位置时保持滚动相位正确。
  final cl = position.ceil();
  final cur = (cl % 10 + 10) % 10;
  var p = (cl - position).clamp(0.0, 1.0);
  if (hasTarget && cur == targetDigit && position <= target + 1.0 && position >= target - eps) {
    p = 0.0;
  }
  return (cur, (cur - 1 + 10) % 10, p);
}

