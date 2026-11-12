import 'dart:typed_data';

import '../../core/foundation/constants.dart';
import '../../core/foundation/duration_ms.dart';
import '../../core/game/frame.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/stop_solver.dart';
import '../../core/motion/timebase.dart';
import '../layout/slot_layout.dart';
import '../model/slot_config.dart';
import '../model/slot_result.dart';

/// 每列单帧最多派发的边界事件数，限制异常速度下的工作量。
const int _maxPassedPerReel = 4096;

/// 复用的帧缓冲，调用方只读；每列数值单位为逻辑像素。
final class SlotFrame extends LuckyFrame {
  /// 创建空快照，配置布局时按列数分配。
  SlotFrame();

  /// 每列滚动量，负向运行保留 JS 取余的符号。
  Float64List scroll = Float64List(0);

  /// 各列目标奖品下标；未确定为 −1。
  Int32List targets = Int32List(0);
}

/// 多列老虎机动画；例如 configure 后 start，再以有效毫秒调用 tick。
final class SlotMotion
    extends LuckyMotion<SlotConfig, SlotLayout, SlotFrame, SlotResult> {
  /// 创建独立的状态机与缓冲。
  SlotMotion();

  /// 已应用的配置。
  SlotConfig _config = const SlotConfig();

  /// 当前配置，排队中的配置不在此列。
  SlotConfig get config => _config;

  /// 当前几何。
  SlotLayout? _layout;

  /// 当前帧。
  @override
  final SlotFrame frame = SlotFrame();

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 当前配置的时间轴上限。
  @override
  Duration get maxFrameDelta => _config.options.motion.maxFrameDelta;

  /// 每列减速起点。
  Float64List stopScroll = Float64List(0);

  /// 每列减速变化量，保持上游 endScroll 命名。
  Float64List endScroll = Float64List(0);

  /// 每列开始减速的有效时间，未开始为 NaN。
  Float64List _reelStart = Float64List(0);

  /// 本帧跨格子的列缓冲。
  Int32List _passed = Int32List(0);

  /// 与跨格列对应的奖品下标。
  Int32List _passedIndices = Int32List(0);

  /// 已写入跨格事件数。
  int _passedCount = 0;

  /// 最近跨格列。
  @override
  int passedReel = 0;

  /// 最近跨格奖品。
  @override
  int passedIndex = -1;

  /// 是否等待下一帧确定起始时间。
  bool _pendingStart = false;

  /// 本局起点时间。
  double _startTime = 0;

  /// 整体减速起点，未开始为 NaN。
  double _endTime = double.nan;

  /// 参考首帧时间。
  double _fps = kLuckyInitialFps;

  /// 本局已推进帧数。
  int _num = 0;

  /// 待机进入加速时的基速。
  double _base = 0;

  /// 是否已收到各列目标。
  bool _hasTargets = false;

  /// 待取走的结果。
  SlotResult? _result;

  /// 应用布局；格距变化按比例缩放三个滚动缓冲。
  @override
  void configure(SlotConfig config, SlotLayout? layout) {
    final replan = phase == LuckyPhase.decelerating &&
        slotStructureChanged(_config, config);
    final oldSpacing = _layout?.cellAndSpacing ?? 0;
    _config = config;
    _layout = layout;
    final count = config.reels.length;
    if (frame.scroll.length != count) {
      frame.scroll = Float64List(count);
      frame.targets = Int32List(count)..fillRange(0, count, -1);
      stopScroll = Float64List(count);
      endScroll = Float64List(count);
      _reelStart = Float64List(count)..fillRange(0, count, double.nan);
      _passed = Int32List(count * _maxPassedPerReel);
      _passedIndices = Int32List(_passed.length);
      _passedCount = 0;
      if (phase.isMoving) {
        final report = phase != LuckyPhase.idleSpinning;
        reset();
        if (report) _result = const SlotResult.cancelled();
      }
    } else if (layout != null && oldSpacing > 0) {
      final ratio = layout.cellAndSpacing / oldSpacing;
      for (var r = 0; r < count; r++) {
        frame.scroll[r] *= ratio;
        stopScroll[r] *= ratio;
        endScroll[r] *= ratio;
      }
    }
    if (replan) {
      _endTime = double.nan;
      _reelStart.fillRange(0, _reelStart.length, double.nan);
    }
    if (_config.prizes.isEmpty && phase.isMoving) {
      final report = phase != LuckyPhase.idleSpinning;
      reset();
      if (report) _result = const SlotResult.cancelled();
    } else if (_config.prizes.isNotEmpty) {
      for (var r = 0; r < frame.targets.length; r++) {
        if (frame.targets[r] >= 0) frame.targets[r] %= _config.prizes.length;
      }
    }
  }

  /// 几何可用且非运动时开始；从待机慢转继承基速。
  @override
  bool start() {
    if (!phase.canPlay || _layout == null || _layout!.isEmpty) return false;
    _base = phase == LuckyPhase.idleSpinning
        ? _config.options.motion.idleSpinSpeed.abs()
        : 0;
    frame.phase = LuckyPhase.accelerating;
    _pendingStart = true;
    _hasTargets = false;
    _result = null;
    _endTime = double.nan;
    _fps = kLuckyInitialFps;
    frame.targets.fillRange(0, frame.targets.length, -1);
    _reelStart.fillRange(0, _reelStart.length, double.nan);
    return true;
  }

  /// 空闲或已结算时开始慢转。
  @override
  bool idleSpin() {
    if ((phase != LuckyPhase.idle && phase != LuckyPhase.settled) ||
        _layout == null ||
        _layout!.isEmpty) {
      return false;
    }
    frame.phase = LuckyPhase.idleSpinning;
    return true;
  }

  /// 每列填写奖品下标；长度错误抛 ArgumentError，null 或任意负数作废。
  bool requestStop(List<int>? indices) {
    if (indices != null && indices.length != _config.reels.length) {
      throw ArgumentError.value(indices, 'indices', '需要每列一个下标');
    }
    if (!phase.canStop) {
      return false;
    }
    if (indices == null || indices.any((i) => i < 0)) return cancel();
    if (_config.prizes.isEmpty) return cancel();
    for (var r = 0; r < indices.length; r++) {
      frame.targets[r] = indices[r] % _config.prizes.length;
    }
    _hasTargets = true;
    return true;
  }

  /// 加速、匀速和慢转可取消；减速忽略取消。
  @override
  bool cancel() => cancelWith((report) {
        frame.phase = LuckyPhase.idle;
        _hasTargets = false;
        if (report) _result = const SlotResult.cancelled();
      });

  /// 清空目标、位置和未取结果，回到空闲。
  @override
  void reset() {
    frame.phase = LuckyPhase.idle;
    frame.scroll.fillRange(0, frame.scroll.length, 0);
    frame.targets.fillRange(0, frame.targets.length, -1);
    stopScroll.fillRange(0, stopScroll.length, 0);
    endScroll.fillRange(0, endScroll.length, 0);
    _hasTargets = false;
    _result = null;
  }

  /// 取走结果，仅返回一次。
  @override
  SlotResult? takeResult() {
    final result = _result;
    _result = null;
    return result;
  }

  /// 将本帧全部列的跨格事件转给宿主；避免核心单事件槽丢失其它列。
  void dispatchPassed(void Function(int reel, int index) callback) {
    for (var i = 0; i < _passedCount; i++) {
      final r = _passed[i];
      callback(r, _passedIndices[i]);
    }
  }

  /// 派发本帧全部列的跨格事件。
  @override
  void drainPassed(void Function(int reel, int index) emit) =>
      dispatchPassed(emit);

  /// 根据各列顺序、目标位置与行偏移推导线上符号；洞或无效线不中奖。
  bool _winsPayline(int lineIndex, List<int> indices) {
    final line = _config.paylines[lineIndex];
    final layout = _layout!;
    if (line.rowOffsets.length != indices.length || indices.isEmpty) {
      return false;
    }
    final symbols = <int>[];
    for (var r = 0; r < indices.length; r++) {
      final order = layout.reels[r].stripPrizes;
      final target = order.indexOf(indices[r]);
      if (order.isEmpty || target < 0) return false;
      var pos = (target + line.rowOffsets[r]).remainder(order.length);
      if (pos < 0) pos += order.length;
      final symbol = order[pos];
      if (symbol < 0) return false;
      symbols.add(symbol);
    }
    return _config.paylinePredicate(symbols);
  }

  /// 按上游共享旧阶段推进所有列；无有效布局时保持静止。
  @override
  int tick(double tMs, double dtMs) {
    final layout = _layout;
    if (!phase.isMoving || layout == null || layout.isEmpty) {
      return LuckyMotionEvents.none;
    }
    if (_pendingStart) {
      _startTime = tMs;
      _pendingStart = false;
      _num = 0;
    }
    final oldPhase = phase;
    final o = _config.options.motion;
    final elapsed = tMs - _startTime;
    final k =
        o.timebase == LuckyTimebase.frame ? 1.0 : dtMs / kLuckyReferenceFrameMs;
    _passedCount = 0;
    var allDone = true;
    if (oldPhase == LuckyPhase.decelerating && _endTime.isNaN) _endTime = tMs;
    for (var r = 0; r < frame.scroll.length; r++) {
      final reel = layout.reels[r];
      if (reel.period <= 0 || reel.stripPrizes.isEmpty) continue;
      final spec = _config.reels[r];
      final speed = (spec.speed ?? o.speed).abs();
      final dir = spec.direction ?? _config.options.direction;
      final prev = frame.scroll[r];
      double s;
      var delta = 0.0;
      if (oldPhase == LuckyPhase.idleSpinning) {
        delta = o.idleSpinSpeed * dir * k;
        s = (prev + delta).remainder(reel.period);
      } else if (oldPhase == LuckyPhase.accelerating ||
          elapsed < o.accelerationMs) {
        if (o.timebase == LuckyTimebase.frame && _num > 0) {
          _fps = elapsed / _num;
        }
        final current = o.accelerationEasing
            .easeIn(elapsed, _base, speed - _base, o.accelerationMs);
        if (current == speed) frame.phase = LuckyPhase.cruising;
        delta = current * dir * k;
        s = (prev + delta).remainder(reel.period);
      } else if (oldPhase == LuckyPhase.cruising) {
        delta = speed * dir * k;
        s = (prev + delta).remainder(reel.period);
        if (_hasTargets) frame.phase = LuckyPhase.decelerating;
      } else {
        final delay = luckyMs(spec.stopDelay);
        if (tMs < _endTime + delay) {
          delta = speed * dir * k;
          s = (prev + delta).remainder(reel.period);
          allDone = false;
        } else {
          if (_reelStart[r].isNaN) {
            _reelStart[r] = tMs;
            stopScroll[r] = prev;
            final order = spec.order ??
                List<int>.generate(_config.prizes.length, (i) => i);
            final orderIndex = order.indexOf(frame.targets[r]);
            endScroll[r] = o.stopSolver.solve(LuckyStopProblem(
                start: prev,
                candidate: (i) =>
                    layout.cellAndSpacing * orderIndex +
                    (reel.period * i * dir) -
                    prev,
                cruiseSpeed: spec.speed ?? o.speed,
                frameMs: o.timebase == LuckyTimebase.frame
                    ? _fps
                    : kLuckyReferenceFrameMs,
                decelerationMs: o.decelerationMs,
                easing: o.decelerationEasing,
                selection: LuckyStopSelection.firstExceeding,
                direction: dir));
          }
          final interval = tMs - _reelStart[r];
          s = interval >= o.decelerationMs
              ? stopScroll[r] + endScroll[r]
              : o.decelerationEasing.easeOut(
                  interval, stopScroll[r], endScroll[r], o.decelerationMs);
          // IMP-05：首减速帧始终保留停止起点，包括 strictUpstream。
          delta = s - prev;
          if (interval < o.decelerationMs) allDone = false;
        }
      }
      frame.scroll[r] = s;
      final from = (prev / layout.cellAndSpacing).floor();
      final to = ((prev + delta) / layout.cellAndSpacing).floor();
      final direction = to >= from ? 1 : -1;
      final crossings = (to - from).abs().clamp(0, _maxPassedPerReel);
      for (var crossing = 1; crossing <= crossings; crossing++) {
        passedReel = r;
        passedIndex = reel.stripPrizes[
            (from + crossing * direction) % reel.stripPrizes.length];
        _passed[_passedCount] = r;
        _passedIndices[_passedCount++] = passedIndex;
      }
    }
    _num++;
    var events = LuckyMotionEvents.repaint;
    if (oldPhase == LuckyPhase.decelerating && allDone) {
      frame.phase = LuckyPhase.settled;
      final indices = List<int>.unmodifiable(frame.targets);
      final index = _config.winPredicate(indices, _config);
      _result = SlotResult(
          indices: indices,
          winningPaylines: [
            for (var i = 0; i < _config.paylines.length; i++)
              if (_winsPayline(i, indices)) i
          ],
          index: index,
          prize: index != null && index >= 0 && index < _config.prizes.length
              ? _config.prizes[index]
              : null);
      events |= LuckyMotionEvents.settled;
    }
    if (_passedCount > 0) events |= LuckyMotionEvents.itemPassed;
    if (oldPhase != phase) events |= LuckyMotionEvents.phaseChanged;
    return events;
  }
}
