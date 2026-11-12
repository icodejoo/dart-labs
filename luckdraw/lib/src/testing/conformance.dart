import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../core/control/controller.dart';
import '../core/easing/easing.dart';
import '../core/game/frame.dart';
import '../core/game/game.dart';
import '../core/game/layout.dart';
import '../core/motion/phase.dart';
import '../core/motion/result.dart';
import '../grid/control/grid_controller.dart';
import '../grid/grid_game.dart';
import '../grid/model/grid_config.dart';
import '../lots/control/lots_controller.dart';
import '../lots/layout/lots_layout.dart';
import '../lots/lots_game.dart';
import '../lots/model/lots_config.dart';
import '../lots/motion/lots_motion.dart';
import '../slot/control/slot_controller.dart';
import '../slot/layout/slot_layout.dart';
import '../slot/model/slot_config.dart';
import '../slot/motion/slot_motion.dart';
import '../slot/slot_game.dart';
import '../wheel/control/wheel_controller.dart';
import '../wheel/model/wheel_config.dart';
import '../wheel/wheel_game.dart';
import 'manual_clock.dart';

/// 默认无头画布。
const Size _defaultSize = Size(300, 300);

/// 缓动检查的默认毫秒时长。
const double _defaultDuration = 1000;

/// 数值比较容差。
const double _tolerance = 1e-9;

/// 缓动等距采样的区间数。
const int _samples = 100;

/// 每个目标最多推进约 160 秒原始时间。
const int _maxSteps = 10000;

/// 无头驱动的固定步长。
const Duration _step = Duration(milliseconds: 16);

/// 实验性（可能调整）：一致性问题的级别。
enum LuckyConformanceSeverity {
  /// 违反端点、有限性或落点契约。
  error,

  /// 曲线合法但非单调，可能影响停止求解。
  warning,
}

/// 实验性（可能调整）：一条可供调用方断言、打印的问题。
final class LuckyConformanceProblem {
  /// 保存本次检查的上下文和文本诊断。
  const LuckyConformanceProblem._(this.game, this.index, this.expected,
      this.actual, this.reason, this.severity);

  /// 实验性（可能调整）：玩法名，或 easing.easeIn / easing.easeOut。
  final String game;

  /// 实验性（可能调整）：目标奖品下标；缓动为采样下标，全局检查为 null。
  final int? index;

  /// 实验性（可能调整）：期望值文本。
  final String expected;

  /// 实验性（可能调整）：实际值文本。
  final String actual;

  /// 实验性（可能调整）：失败原因或警告说明。
  final String reason;

  /// 实验性（可能调整）：错误或警告级别。
  final LuckyConformanceSeverity severity;

  /// 实验性（可能调整）：返回包含级别、玩法、下标和期望/实际值的诊断。
  @override
  String toString() =>
      '${severity.name} $game[$index]: $reason; expected=$expected, actual=$actual';
}

/// 实验性（可能调整）：一致性检查报告；例如 `expect(report.isOk, true, reason: '$report')`。
final class LuckyConformanceReport {
  /// 固化问题列表，避免调用方修改检查结果。
  LuckyConformanceReport._(List<LuckyConformanceProblem> problems)
      : problems = List.unmodifiable(problems);

  /// 实验性（可能调整）：不可修改的问题列表，包含 error 与 warning。
  final List<LuckyConformanceProblem> problems;

  /// 实验性（可能调整）：没有 error 时为 true；warning 不使检查失败。
  bool get isOk => problems
      .every((problem) => problem.severity != LuckyConformanceSeverity.error);

  /// 实验性（可能调整）：返回检查状态及逐条诊断，适合作为断言失败原因。
  @override
  String toString() => [
        'LuckyConformanceReport(${isOk ? 'OK' : 'FAIL'})',
        ...problems
      ].join('\n');
}

/// 实验性（可能调整）：不依赖 flutter_test 的同步无头一致性检查。
///
/// 固定 16ms 推进，单目标上限 10000 步；超时或驱动抛错记录为 error。
/// indices 省略时检查全部未禁用奖品，显式传入时也跳过禁用奖品；越界记录 error。
/// 每个目标从 reset 状态开始。只验证帧/布局/命中契约，不验证自定义绘制的像素。
/// capsule / number_wheel / lotto 后续补充。
abstract final class LuckyConformance {
  /// 实验性（可能调整）：检查 [easing] 的两个方法，返回含端点/有限性错误、单调性警告的报告。
  ///
  /// [duration] 为正且有限的毫秒数，否则抛 ArgumentError。
  /// 使用非零起点和正变化量，在 `[0, duration]` 等距采样 101 点；端点容差 1e-9。
  /// 采样不能证明采样点之间的性质；例如 `LuckyConformance.checkEasing(LuckyEasings.quad)`。
  static LuckyConformanceReport checkEasing(LuckyEasing easing,
      {double duration = _defaultDuration}) {
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(duration, 'duration', '必须为正且有限');
    }
    final problems = <LuckyConformanceProblem>[];
    const begin = 2.0;
    const change = 3.0;
    final methods = {'easeIn': easing.easeIn, 'easeOut': easing.easeOut};
    for (final entry in methods.entries) {
      var previous = begin;
      var warned = false;
      var nonFinite = false;
      for (var sample = 0; sample <= _samples; sample++) {
        final value =
            entry.value(duration * sample / _samples, begin, change, duration);
        final game = 'easing.${entry.key}';
        if (!value.isFinite && !nonFinite) {
          _problem(problems, game, sample, 'finite', '$value', '采样值非有限');
          nonFinite = true;
        }
        if (sample == 0 || sample == _samples) {
          final expected = sample == 0 ? begin : begin + change;
          if (!value.isFinite || (value - expected).abs() > _tolerance) {
            _problem(problems, game, sample, '$expected', '$value', '端点不精确');
          }
        }
        if (sample > 0 &&
            value.isFinite &&
            previous.isFinite &&
            value < previous - _tolerance &&
            !warned) {
          _problem(problems, game, sample, '>= $previous', '$value',
              '采样非单调不减；回弹/过冲缓动合法，但可能影响停止求解',
              severity: LuckyConformanceSeverity.warning);
          warned = true;
        }
        previous = value;
      }
    }
    return LuckyConformanceReport._(problems);
  }

  /// 实验性（可能调整）：用 [config]、[size] 检查 [indices] 的结果与指针落点，返回报告。
  ///
  /// wheel 仅支持按钮命中，跳过奖品命中检查；随机停止偏移使用固定种子。
  /// 例如 `LuckyConformance.checkWheel(config, indices: [0])`；参数规则见类注释。
  static LuckyConformanceReport checkWheel(WheelConfig config,
      {Size size = _defaultSize, List<int>? indices}) {
    final controller = WheelController(random: math.Random(0));
    return _check(
        'wheel',
        config,
        const WheelGame(),
        controller,
        controller.stop,
        [for (final prize in config.prizes) prize.disabled],
        size,
        indices,
        (layout, frame) => [frame.pointerIndex]);
  }

  /// 实验性（可能调整）：用 [config]、[size] 检查 [indices] 的结果、高亮与奖品中心命中。
  ///
  /// 返回报告；例如 `LuckyConformance.checkGrid(config)`；参数规则见类注释。
  static LuckyConformanceReport checkGrid(GridConfig config,
      {Size size = _defaultSize, List<int>? indices}) {
    final controller = GridController();
    return _check(
        'grid',
        config,
        const GridGame(),
        controller,
        controller.stop,
        [for (final prize in config.prizes) prize.disabled],
        size,
        indices,
        (layout, frame) => [frame.activeIndex],
        center: (layout, frame, index) => layout.hitRect(index).center);
  }

  /// 实验性（可能调整）：各列 stop 到 [indices] 中同一奖品，核对结果与实际条带停位。
  ///
  /// 使用 [config]、[size] 返回报告；自定义 winPredicate 仍须返回指定奖品下标。
  /// slot 没有奖品命中，跳过该项；例如 `LuckyConformance.checkSlot(config)`。
  /// 参数规则见类注释；实际停位由 scroll 反算，不使用 targets 作为画面落点。
  static LuckyConformanceReport checkSlot(SlotConfig config,
      {Size size = _defaultSize, List<int>? indices}) {
    final controller = SlotController();
    return _check(
        'slot',
        config,
        const SlotGame(),
        controller,
        controller.stop,
        [for (final prize in config.prizes) prize.disabled],
        size,
        indices,
        _slotPositions);
  }

  /// 实验性（可能调整）：用 [config]、[size] 检查 [indices] 的结果、目标签与升签中心命中。
  ///
  /// 返回报告；例如 `LuckyConformance.checkLots(config)`；参数规则见类注释。
  static LuckyConformanceReport checkLots(LotsConfig config,
      {Size size = _defaultSize, List<int>? indices}) {
    final controller = LotsController();
    return _check(
        'lots',
        config,
        const LotsGame(),
        controller,
        controller.stop,
        [for (final stick in config.sticks) stick.disabled],
        size,
        indices,
        (layout, frame) => [frame.targetIndex],
        center: (layout, frame, index) => _lotsCenter(layout, frame));
  }
}

/// 记录文本诊断，默认视为错误。
void _problem(List<LuckyConformanceProblem> problems, String game, int? index,
    String expected, String actual, String reason,
    {LuckyConformanceSeverity severity = LuckyConformanceSeverity.error}) {
  problems.add(LuckyConformanceProblem._(
      game, index, expected, actual, reason, severity));
}

/// 从真实滚动量反算各列中心停位；非整格停点同样视为不一致。
List<int> _slotPositions(SlotLayout layout, SlotFrame frame) {
  final indices = <int>[];
  for (var reel = 0; reel < layout.reels.length; reel++) {
    final position = frame.scroll[reel] / layout.cellAndSpacing;
    final nearest = position.round();
    final order = layout.reels[reel].stripPrizes;
    indices.add((position - nearest).abs() > _tolerance
        ? -1
        : order[nearest % order.length]);
  }
  return indices;
}

/// 将升签中心绕筒口旋转到实际布局坐标。
Offset _lotsCenter(LotsLayout layout, LotsFrame frame) {
  final mouth = layout.cylinder.topCenter;
  final delta = layout.raisedStick(frame.targetSlot).center - mouth;
  final angle = layout.angles[frame.targetSlot];
  return mouth +
      Offset(delta.dx * math.cos(angle) - delta.dy * math.sin(angle),
          delta.dx * math.sin(angle) + delta.dy * math.cos(angle));
}

/// 共用无头驱动、超时和结果比较；玩法只提供落点和可选命中中心。
LuckyConformanceReport _check<C extends Object, L extends LuckyLayout,
        F extends LuckyFrame, R extends LuckyResult<Object?>>(
    String name,
    C config,
    LuckyGame<C, L, F, R> game,
    LuckyController<C, L, F, R> controller,
    bool Function(int) stop,
    List<bool> disabled,
    Size size,
    List<int>? indices,
    List<int> Function(L, F) positions,
    {Offset Function(L, F, int)? center}) {
  final problems = <LuckyConformanceProblem>[];
  final clock = ManualLuckyClock();
  final input = LuckyLayoutInput.headless(size);
  try {
    final layout = game.computeLayout(config, input);
    controller.attachHeadless(clock: clock, config: config, layout: layout);
    for (final index
        in indices ?? List<int>.generate(disabled.length, (index) => index)) {
      if (index < 0 || index >= disabled.length) {
        _problem(problems, name, index, '0 <= index < ${disabled.length}',
            '$index', '目标下标越界');
        continue;
      }
      if (disabled[index]) continue;
      try {
        controller.reset();
        final accepted = controller.play() && stop(index);
        if (!accepted) {
          _problem(problems, name, index, 'true', '$accepted', 'play/stop 未接受');
          continue;
        }
        for (var step = 0;
            step < _maxSteps && controller.phase.value != LuckyPhase.settled;
            step++) {
          clock.advance(_step);
        }
        if (controller.phase.value != LuckyPhase.settled) {
          _problem(problems, name, index, 'settled',
              controller.phase.value.name, '超过 $_maxSteps 步仍未结算');
          continue;
        }
        if (controller.lastResult?.index != index) {
          _problem(problems, name, index, '$index',
              '${controller.lastResult?.index}', 'result.index 不一致');
        }
        final actual = positions(layout, controller.frame);
        if (actual.any((value) => value != index)) {
          _problem(problems, name, index, '$index', '$actual', '画面最终落点不一致');
        }
        if (center != null) {
          final hits = game.hitTestAll(config, layout, controller.frame,
              center(layout, controller.frame, index));
          if (!hits.any(
              (hit) => hit.kind == LuckyHitKind.item && hit.index == index)) {
            _problem(
                problems,
                name,
                index,
                'item($index)',
                '${[for (final hit in hits) '${hit.kind.name}(${hit.index})']}',
                '奖品几何中心未命中目标');
          }
        }
      } on Object catch (error) {
        _problem(problems, name, index, '正常结算', '$error', '无头驱动抛错');
      }
    }
  } finally {
    controller.dispose();
    clock.dispose();
    input.measurer.dispose();
  }
  return LuckyConformanceReport._(problems);
}
