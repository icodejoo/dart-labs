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
import '../../core/picker/pick_index.dart';
import '../../core/picker/prize_picker.dart';
import '../layout/wheel_angles.dart';
import '../layout/wheel_layout.dart';
import '../model/wheel_config.dart';
import '../model/wheel_parts.dart';

/// 上游静止阶段。
const int _idleStep = 0;

/// 上游加速阶段。
const int _acceleratingStep = 1;

/// 上游匀速或待停阶段。
const int _cruisingStep = 2;

/// 上游减速阶段。
const int _deceleratingStep = 3;

/// 上游未中奖或作废的下标哨兵。
const int _unknownIndex = -1;

/// 停止落点距扇区边界的角度余量。
const double _stopBoundaryEpsilon = 1e-9;

/// 转盘复用帧，角度不取模，供绘制和只读观测。
final class WheelFrame extends LuckyFrame {
  /// 创建原点处的空闲帧。
  WheelFrame();

  /// 累计旋转角度。
  double rotateDeg = 0;

  /// 当前局的目标下标，未确定时为 −1。
  int targetIndex = _unknownIndex;

  /// 指针当前所在扇区，无奖品时为 −1。
  int pointerIndex = _unknownIndex;
}

/// 上游 wheel.ts:445-555 的动画状态机，由控制器驱动。
final class WheelMotion extends LuckyMotion<WheelConfig, WheelLayout,
    WheelFrame, LuckyResult<WheelPrize>> {
  /// 创建状态机；[random] 与 [picker] 应与控制器共用。
  WheelMotion({required math.Random random, required PrizePicker picker})
      : _random = random,
        _picker = picker;

  /// 共用随机源。
  final math.Random _random;

  /// 无下标停止策略。
  final PrizePicker _picker;

  /// 当前配置。
  WheelConfig _config = const WheelConfig();

  /// 当前角度表，不依赖布局尺寸。
  late WheelSectorAngles _angles;

  /// 跨帧复用快照。
  @override
  final WheelFrame frame = WheelFrame();

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 最近一帧指针下的扇区。
  @override
  int get passedIndex => frame.pointerIndex;

  /// 当前已应用配置的时间轴上限。
  @override
  Duration get maxFrameDelta => _options.maxFrameDelta;

  /// 当前动画参数。
  LuckyMotionOptions get _options => phase == LuckyPhase.decelerating
      ? _decelerationOptions ?? _config.options.motion
      : _config.options.motion;

  /// 本次减速的参数快照，避免中途换时长导致倒退。
  LuckyMotionOptions? _decelerationOptions;

  /// 上游整数阶段。
  int _step = _idleStep;

  /// 上游中奖标记，null 表示尚未决定。
  int? _prizeFlag;

  /// 有效开始时间。
  double _startTime = 0;

  /// 减速开始时间。
  double _endTime = 0;

  /// 减速起点角度。
  double _stopDeg = 0;

  /// 减速总位移。
  double _endDeg = 0;

  /// 上游加速期间测得的帧时长。
  double _fps = kLuckyInitialFps;

  /// 当前局的帧计数。
  int _num = 0;

  /// 首帧建立开始时间。
  bool _pendingStart = false;

  /// 待机慢转标记。
  bool _idleSpinning = false;

  /// 正常结算标记。
  bool _settled = false;

  /// 零位移同样只求解一次，DEV-07。
  bool _solved = false;

  /// 加速起点速度。
  double _base = 0;

  /// 最近一次 tick 的开始时间间隔。
  double _startInterval = 0;

  /// 本次停止采样的随机值；重映射目标时复用，避免额外消耗随机序列。
  double _stopRandom = double.nan;

  /// 额外圈数。
  int _extraRevolutions = 0;

  /// 一次性结果。
  LuckyResult<WheelPrize>? _result;

  /// 应用配置；正时长在调试模式断言，运行期毫秒值至少为一。
  @override
  void configure(WheelConfig config, WheelLayout? layout) {
    assert(config.options.motion.accelerationTime > Duration.zero);
    assert(config.options.motion.decelerationTime > Duration.zero);
    final replan = phase == LuckyPhase.decelerating &&
        (_config.prizes.length != config.prizes.length ||
            _config.options.offsetDegree != config.options.offsetDegree ||
            !_sameSectorWeights(_config.prizes, config.prizes));
    _angles = WheelSectorAngles.fromConfig(config);
    _config = config;
    if (_angles.count == 0 && phase.isMoving) {
      final report = !_idleSpinning;
      reset();
      if (report) _result = const LuckyResult.cancelled();
    } else if (_prizeFlag != null && _prizeFlag! >= 0) {
      if (_angles.count == 0) {
        frame.targetIndex = _prizeFlag = _unknownIndex;
      } else {
        _prizeFlag = _prizeFlag! % _angles.count;
        frame.targetIndex = _prizeFlag!;
      }
    }
    if (replan) _solved = false;
    frame.pointerIndex =
        _angles.sectorAtPointer(frame.rotateDeg, config.options.offsetDegree);
  }

  /// 开始一局；空奖品或运动阶段返回 false，待机慢转可直接起步。
  @override
  bool start() {
    if (!phase.canPlay) return false;
    if (_config.prizes.isEmpty) {
      debugPrint('WheelMotion: 零奖品不能开始抽奖');
      return false;
    }
    _base = _idleSpinning ? _options.idleSpinSpeed : 0;
    _idleSpinning = false;
    _settled = false;
    _prizeFlag = null;
    _result = null;
    frame.targetIndex = _unknownIndex;
    _step = _acceleratingStep;
    _pendingStart = true;
    _startInterval = 0;
    _extraRevolutions = 0;
    _stopRandom = double.nan;
    _updatePhase();
    return true;
  }

  /// 开始待机慢转；只有空闲或已结算时接受。
  @override
  bool idleSpin() {
    if (phase != LuckyPhase.idle && phase != LuckyPhase.settled) return false;
    _idleSpinning = true;
    _settled = false;
    _result = null;
    frame.targetIndex = _unknownIndex;
    _updatePhase();
    return true;
  }

  /// 请求停止；null 使用 picker，负数作废，非负下标按奖品数取余。
  ///
  /// 只在加速或匀速阶段接受；额外圈数应非负，否则抛 ArgumentError。
  bool requestStop(int? index, {int extraRevolutions = 0}) {
    if (!phase.canStop) {
      return false;
    }
    if (extraRevolutions < 0) {
      throw ArgumentError.value(extraRevolutions, 'extraRevolutions');
    }
    final target = index ??
        pickIndex(_picker, _random, _config.prizes,
            weight: (p) => p.weight, disabled: (p) => p.disabled) ??
        _unknownIndex;
    if (target < 0) return cancel();
    _prizeFlag = target.remainder(_angles.count);
    frame.targetIndex = _prizeFlag!;
    _extraRevolutions = extraRevolutions;
    _step = _cruisingStep;
    _updatePhase();
    return true;
  }

  /// 两组奖品的扇区权重是否逐项相同；长度不同视为不同。
  static bool _sameSectorWeights(List<WheelPrize> a, List<WheelPrize> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].sectorWeight != b[i].sectorWeight) return false;
    }
    return true;
  }

  /// 作废当前局；减速时忽略，结束待机慢转不产生结果。
  @override
  bool cancel() => cancelWith((report) {
        _result = report ? const LuckyResult.cancelled() : null;
        _idleSpinning = false;
        _settled = false;
        _step = _idleStep;
        _prizeFlag = _unknownIndex;
        frame.targetIndex = _unknownIndex;
        _updatePhase();
      });

  /// 回到原点并清除未决结果。
  @override
  void reset() {
    _step = _idleStep;
    _prizeFlag = null;
    _pendingStart = false;
    _idleSpinning = false;
    _settled = false;
    _solved = false;
    _result = null;
    _fps = kLuckyInitialFps;
    frame.rotateDeg = 0;
    frame.targetIndex = _unknownIndex;
    frame.pointerIndex = _unknownIndex;
    _updatePhase();
  }

  /// 推进有效毫秒时间，原地更新帧并返回事件位。
  @override
  int tick(double tMs, double dtMs) {
    if (!phase.isMoving) return LuckyMotionEvents.none;
    final previous = phase;
    final previousPointer = frame.pointerIndex;
    final k = _options.timebase == LuckyTimebase.frame
        ? 1.0
        : dtMs / kLuckyReferenceFrameMs;
    var events = LuckyMotionEvents.repaint;
    if (_idleSpinning) {
      frame.rotateDeg +=
          _options.idleSpinSpeed.remainder(kLuckyFullTurnDeg) * k;
    } else {
      // 上游 wheel.ts:467-479、515-547，运算结合顺序保持不变。
      if (_pendingStart) {
        _startTime = tMs;
        _pendingStart = false;
        _num = 0;
      }
      if (_step == _deceleratingStep && !_solved) _carve(tMs);
      _startInterval = tMs - _startTime;
      final endInterval = tMs - _endTime;
      var deg = frame.rotateDeg;
      final speed = _options.speed;
      if (_step == _acceleratingStep ||
          _startInterval < _options.accelerationMs) {
        if (_options.timebase == LuckyTimebase.frame && _num > 0) {
          _fps = _startInterval / _num;
        }
        final currSpeed = _options.accelerationEasing.easeIn(
            _startInterval, _base, speed - _base, _options.accelerationMs);
        if (currSpeed == speed) _step = _cruisingStep;
        deg = deg + currSpeed.remainder(kLuckyFullTurnDeg) * k;
      } else if (_step == _cruisingStep) {
        deg = deg + speed.remainder(kLuckyFullTurnDeg) * k;
        if (_prizeFlag != null && _prizeFlag! >= 0) {
          _decelerationOptions = _config.options.motion;
          _step = _deceleratingStep;
          _stopDeg = 0;
          _endDeg = 0;
          _solved = false;
        }
      } else {
        deg = _options.decelerationEasing
            .easeOut(endInterval, _stopDeg, _endDeg, _options.decelerationMs);
        if (endInterval >= _options.decelerationMs) {
          _step = _idleStep;
          _settled = true;
          _result = LuckyResult(
              index: _prizeFlag, prize: _config.prizes[_prizeFlag!]);
          events |= LuckyMotionEvents.settled;
          // DEV-07：上游可选初始哨兵零位移，未必与目标同余；仍须结束。
          assert(_endDeg == 0 ||
              _angles.sectorAtPointer(deg, _config.options.offsetDegree) ==
                  _prizeFlag);
        }
      }
      frame.rotateDeg = deg;
      _num++;
    }
    _updatePhase();
    frame.pointerIndex =
        _angles.sectorAtPointer(frame.rotateDeg, _config.options.offsetDegree);
    if (previousPointer != frame.pointerIndex) {
      events |= LuckyMotionEvents.itemPassed;
    }
    if (previous != phase) events |= LuckyMotionEvents.phaseChanged;
    return events;
  }

  /// 上游 carveOnGunwaleOfAMovingBoat，wheel.ts:445-462；零位移只求解一次。
  void _carve(double t) {
    _endTime = t;
    _stopDeg = frame.rotateDeg;
    final rotateDeg = frame.rotateDeg;
    if (_stopRandom.isNaN) _stopRandom = _random.nextDouble();
    final r = _stopRandom;
    final sweep = _angles.sweepDeg(_prizeFlag!);
    final halfSweep = sweep / kLuckyHalfDivisor;
    final rawOffset = (r * sweep - halfSweep) * _config.options.stopRange;
    // 合法随机端点须位于半开扇区内部，普通输入保持上游运算顺序。
    final margin = math.min(_stopBoundaryEpsilon, halfSweep);
    final stopRangeOffset =
        rawOffset.clamp(-halfSweep + margin, halfSweep - margin);
    final startDeg = _angles.startDeg(_prizeFlag!);

    /// 保留上游每个加减项的位置，禁止代数化简。
    double candidate(int i) =>
        kLuckyFullTurnDeg * i -
        startDeg -
        rotateDeg -
        _config.options.offsetDegree +
        stopRangeOffset -
        sweep / kLuckyHalfDivisor;
    _endDeg = _options.stopSolver.solve(LuckyStopProblem(
            start: _stopDeg,
            candidate: candidate,
            cruiseSpeed: _options.speed,
            frameMs: _options.timebase == LuckyTimebase.frame
                ? _fps
                : kLuckyReferenceFrameMs,
            decelerationMs: _options.decelerationMs,
            easing: _options.decelerationEasing,
            selection: LuckyStopSelection.nearest)) +
        kLuckyFullTurnDeg * _extraRevolutions;
    _solved = true;
  }

  /// 用缓存的开始间隔派生阶段，不额外读取时钟。
  void _updatePhase() {
    frame.phase = _idleSpinning
        ? LuckyPhase.idleSpinning
        : _step == _idleStep
            ? (_settled ? LuckyPhase.settled : LuckyPhase.idle)
            : _step == _deceleratingStep
                ? LuckyPhase.decelerating
                : _step == _acceleratingStep ||
                        _startInterval < _options.accelerationMs
                    ? LuckyPhase.accelerating
                    : LuckyPhase.cruising;
  }

  /// 取走一次性正常或作废结果。
  @override
  LuckyResult<WheelPrize>? takeResult() {
    final result = _result;
    _result = null;
    return result;
  }
}
