import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/foundation/constants.dart';
import '../../core/game/frame.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/motion_options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/motion/stop_solver.dart';
import '../../core/motion/timebase.dart';
import '../layout/grid_layout.dart';
import '../model/grid_config.dart';
import '../model/grid_parts.dart';

/// 九宫格帧快照，由状态机复用，调用方不可修改。
final class GridFrame extends LuckyFrame {
  /// 创建没有高亮的初始帧。
  GridFrame();

  /// 上游 currIndex，持续累加且不取模。
  double currIndex = 0;

  /// 当前奖品下标；初始、待机和作废后为 −1。
  int activeIndex = -1;
}

/// 九宫格动画状态机；速度单位为配置 speed / 40 格每参考帧。
final class GridMotion extends LuckyMotion<GridConfig, GridLayout, GridFrame,
    LuckyResult<GridPrize>> {
  /// 创建未配置的状态机；使用前调用 configure。
  GridMotion();

  /// 当前已应用配置。
  GridConfig _config = const GridConfig();

  /// 当前布局；无头动画不要求布局。
  GridLayout? _layout;

  /// 帧快照。
  @override
  final GridFrame frame = GridFrame();

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 单帧有效时间上限。
  @override
  Duration get maxFrameDelta => _options.maxFrameDelta;

  /// 本帧高亮变更的下标。
  @override
  int get passedIndex => frame.activeIndex;

  /// 已应用配置，供控制器选奖。
  GridConfig get config => _config;

  /// 动画配置。
  LuckyMotionOptions get _options => _step == 3
      ? _decelerationOptions ?? _config.options.motion
      : _config.options.motion;

  /// 当前减速阶段的固定参数。
  LuckyMotionOptions? _decelerationOptions;

  /// 首帧才确定起点，隔离控制器的原始时钟。
  bool _pendingStart = false;

  /// 减速首帧才求解停止位移。
  bool _pendingSolve = false;

  /// 本局加速起点。
  double _startTime = 0;

  /// 最近一帧的有效时间。
  double _now = 0;

  /// 减速起点时间。
  double _endTime = 0;

  /// 减速起点位置。
  double _stopIndex = 0;

  /// 减速位移。
  double _endIndex = 0;

  /// 加速起始速度。
  double _base = kLuckyGridAccelerationBase;

  /// 上游累计平均帧时长。
  double _fps = kLuckyInitialFps;

  /// 本局已处理帧数。
  int _num = 0;

  /// 上游阶段码：0 静止、1 加速、2 匀速或待加速完成、3 减速。
  int _step = 0;

  /// 空奖品的诊断每个状态机只报告一次。
  bool _warnedEmpty = false;

  /// 未选奖为 null，作废为 −1。
  int? _target = -1;

  /// 附加完整圈数。
  int _extraLaps = 0;

  /// 待取走的一次性结果。
  LuckyResult<GridPrize>? _result;

  /// 应用配置；非正时长在调试模式断言，运行期访问器钳到一毫秒。
  @override
  void configure(GridConfig config, GridLayout? layout) {
    assert(config.options.motion.accelerationTime > Duration.zero);
    assert(config.options.motion.decelerationTime > Duration.zero);
    if (_step == 3 && _config.prizes.length != config.prizes.length) {
      _pendingSolve = true;
    }
    _config = config;
    _layout = layout;
    if (_target != null && _target! >= 0 && config.prizes.isNotEmpty) {
      _target = _target!.remainder(config.prizes.length);
    }
    _updateActive();
  }

  /// 开始本局；运动中、零奖品或空布局返回 false。
  @override
  bool start() {
    if (_config.prizes.isEmpty) {
      if (!_warnedEmpty) {
        _warnedEmpty = true;
        debugPrint('九宫格奖品为空，无法开始抽奖');
      }
      return false;
    }
    if ((phase.isMoving && phase != LuckyPhase.idleSpinning) ||
        (_layout?.isEmpty ?? false)) {
      return false;
    }
    _base = phase == LuckyPhase.idleSpinning
        ? _options.idleSpinSpeed / kLuckyGridSpeedDivisor
        : kLuckyGridAccelerationBase;
    if (_config.options.maxStepsPerSecond != null) {
      _base = math.min(_base, _options.speed / kLuckyGridSpeedDivisor);
    }
    _target = null;
    _result = null;
    _pendingStart = true;
    _pendingSolve = false;
    _extraLaps = 0;
    _step = 1;
    frame.phase = LuckyPhase.accelerating;
    _updateActive();
    return true;
  }

  /// 开始无结果高亮的待机慢转；运动中或内容为空返回 false。
  @override
  bool idleSpin() {
    if (phase.isMoving ||
        _config.prizes.isEmpty ||
        (_layout?.isEmpty ?? false)) {
      return false;
    }
    frame.phase = LuckyPhase.idleSpinning;
    _step = 0;
    _target = -1;
    _result = null;
    _updateActive();
    return true;
  }

  /// 请求目标；null 或负下标作废，超范围取余，附加圈数钳到非负。
  ///
  /// 加速阶段保留停止请求，加速完成后的推进帧直接投影为减速。
  bool requestStop(int? index, {int extraLaps = 0}) {
    if (_step == 3) return false;
    if (!phase.canStop) {
      return false;
    }
    if (index == null || index < 0) return cancel();
    _target = index.remainder(_config.prizes.length);
    _step = 2;
    _extraLaps = math.max(0, extraLaps);
    return true;
  }

  /// 作废加速、匀速或待机；减速阶段忽略。
  @override
  bool cancel() {
    if (!phase.isMoving || _step == 3) return false;
    frame.phase = LuckyPhase.idle;
    _step = 0;
    _target = -1;
    _result = const LuckyResult.cancelled();
    _updateActive();
    return true;
  }

  /// 回到原点并清空结果和高亮。
  @override
  void reset() {
    frame.phase = LuckyPhase.idle;
    _step = 0;
    frame.currIndex = 0;
    frame.activeIndex = -1;
    _target = -1;
    _result = null;
    _pendingStart = false;
    _pendingSolve = false;
  }

  /// 按有效毫秒时间推进，返回阶段、结果和高亮变化事件。
  @override
  int tick(double tMs, double dtMs) {
    _now = tMs;
    if (!phase.isMoving) return LuckyMotionEvents.none;
    final previousPhase = phase;
    final previousActive = frame.activeIndex;
    final n = _config.prizes.length;
    if (n == 0) {
      reset();
      _result = const LuckyResult.cancelled();
      return LuckyMotionEvents.cancelled |
          LuckyMotionEvents.phaseChanged |
          (previousActive == frame.activeIndex ? 0 : LuckyMotionEvents.repaint);
    }
    if (_pendingStart) {
      _pendingStart = false;
      _startTime = tMs;
      _num = 0;
      _fps = kLuckyInitialFps;
    }
    final options = _options;
    final k = options.timebase == LuckyTimebase.frame
        ? 1.0
        : dtMs / kLuckyReferenceFrameMs;
    final speed = options.speed / kLuckyGridSpeedDivisor;
    if (phase == LuckyPhase.idleSpinning) {
      frame.currIndex = frame.currIndex +
          (options.idleSpinSpeed / kLuckyGridSpeedDivisor).remainder(n) * k;
    } else if (_step == 1 || tMs - _startTime < options.accelerationMs) {
      final interval = tMs - _startTime;
      if (options.timebase == LuckyTimebase.frame && _num > 0) {
        _fps = interval / _num;
      }
      final currentSpeed = options.accelerationEasing.easeIn(
          math.min(interval, options.accelerationMs),
          _base,
          speed - _base,
          options.accelerationMs);
      frame.currIndex = frame.currIndex + currentSpeed.remainder(n) * k;
      if (currentSpeed == speed) _step = 2;
    } else if (_step == 2) {
      frame.currIndex = frame.currIndex + speed.remainder(n) * k;
      if (_target != null && _target! >= 0) {
        frame.phase = LuckyPhase.decelerating;
        _decelerationOptions = _config.options.motion;
        _step = 3;
        _pendingSolve = true;
      }
    } else if (_step == 3) {
      if (_pendingSolve) _solve();
      final interval = tMs - _endTime;
      frame.currIndex = options.decelerationEasing.easeOut(
          math.min(interval, options.decelerationMs),
          _stopIndex,
          _endIndex,
          options.decelerationMs);
      if (interval >= options.decelerationMs) {
        frame.phase = LuckyPhase.settled;
        _step = 0;
        _result = LuckyResult(index: _target, prize: _config.prizes[_target!]);
      }
    }
    _num++;
    frame.phase = _derivePhase();
    _updateActive();
    return (previousPhase == phase ? 0 : LuckyMotionEvents.phaseChanged) |
        (phase == LuckyPhase.settled ? LuckyMotionEvents.settled : 0) |
        (previousActive == frame.activeIndex
            ? 0
            : LuckyMotionEvents.repaint | LuckyMotionEvents.itemPassed);
  }

  /// 按有效时间派生公开阶段，保留 step 的上游浮点与提前停止语义。
  LuckyPhase _derivePhase() {
    if (_step == 0) return frame.phase;
    if (_step == 3) return LuckyPhase.decelerating;
    return _pendingStart || _now - _startTime < _options.accelerationMs
        ? LuckyPhase.accelerating
        : LuckyPhase.cruising;
  }

  /// 按上游加减顺序计算候选；求解器默认保证正向位移。
  void _solve() {
    _pendingSolve = false;
    _endTime = _now;
    _stopIndex = frame.currIndex;
    final n = _config.prizes.length;
    _endIndex = _options.stopSolver.solve(LuckyStopProblem(
            start: _stopIndex,
            candidate: (i) => n * i + _target! - _stopIndex,
            cruiseSpeed: _options.speed / kLuckyGridSpeedDivisor,
            frameMs: _options.timebase == LuckyTimebase.frame
                ? _fps
                : kLuckyReferenceFrameMs,
            decelerationMs: _options.decelerationMs,
            easing: _options.decelerationEasing,
            selection: LuckyStopSelection.nearest)) +
        n * _extraLaps;
  }

  /// 只有奖品可以激活；初始、作废和待机保留无高亮。
  void _updateActive() {
    final n = _config.prizes.length;
    frame.activeIndex = (_target == null || _target! >= 0) && n > 0
        ? frame.currIndex.remainder(n).toInt()
        : -1;
  }

  /// 取走结果，后续调用返回 null。
  @override
  LuckyResult<GridPrize>? takeResult() {
    final result = _result;
    _result = null;
    return result;
  }
}
