import 'dart:math' as math;

import '../../core/easing/easing.dart';
import '../../core/foundation/angles.dart';
import '../../core/foundation/constants.dart';
import '../../core/foundation/unit_range.dart';
import '../../core/game/frame.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/motion_options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/motion/stop_solver.dart';
import '../../core/motion/timebase.dart';
import '../layout/number_wheel_layout.dart';
import '../model/number_wheel_config.dart';

/// 数字转盘的复用帧，角度为从正上方起顺时针的度数。
final class NumberWheelFrame extends LuckyFrame {
  /// 创建静止帧。
  NumberWheelFrame();

  /// 圆盘累计角度。
  double discDeg = 0;

  /// 小球累计角度。
  double ballDeg = 0;

  /// 小球圆心到盘心距离。
  double ballRadius = 0;

  /// 小球当前所在格子。
  int ballPocket = 0;

  /// 目标签下标，未选中时为负一。
  int targetIndex = -1;
}

/// 圆盘与小球反向运动；减速使用随盘坐标系求解落袋位置。
final class NumberWheelMotion extends LuckyMotion<NumberWheelConfig,
    NumberWheelLayout, NumberWheelFrame, LuckyResult<NumberWheelPocket>> {
  /// 创建独立状态机。
  NumberWheelMotion();

  /// 跨帧复用的输出。
  @override
  final NumberWheelFrame frame = NumberWheelFrame();

  /// 已应用配置。
  NumberWheelConfig _config = const NumberWheelConfig(pockets: []);

  /// 运动中待应用的结构配置。
  NumberWheelConfig? _queuedConfig;

  /// 待应用配置对应的几何。
  NumberWheelLayout? _queuedLayout;

  /// 当前布局。
  NumberWheelLayout? _layout;

  /// 本阶段经过毫秒。
  double _elapsed = 0;

  /// 待停止目标。
  int _pending = -1;

  /// 减速初始盘角。
  double _disc0 = 0;

  /// 减速初始相对角。
  double _psi0 = 0;

  /// 减速盘位移。
  double _discChange = 0;

  /// 减速相对位移。
  double _psiChange = 0;

  /// 帧基准下加速期累计时长。
  double _accTime = 0;

  /// 帧基准下加速期帧数。
  int _accFrames = 0;

  /// 最近一次结果。
  LuckyResult<NumberWheelPocket>? _result;

  /// 已应用的运动参数。
  LuckyMotionOptions get _options => _config.options.motion;

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 最大有效帧间隔。
  @override
  Duration get maxFrameDelta => _options.maxFrameDelta;

  /// 最近经过的格子。
  @override
  int get passedIndex => frame.ballPocket;

  /// 提供控制器使用的当前配置。
  NumberWheelConfig get config => _config;

  /// 配置参数；改变条目数时取消运动，缺布局不能开始。
  @override
  void configure(NumberWheelConfig config, NumberWheelLayout? layout) {
    assert(config.options.motion.accelerationTime > Duration.zero);
    assert(config.options.motion.decelerationTime > Duration.zero);
    if (phase.isMoving &&
        _config.pockets.length == config.pockets.length &&
        _config.options.offsetDegree != config.options.offsetDegree) {
      _queuedConfig = config;
      _queuedLayout = layout;
      return;
    }
    if (_config.pockets.length != config.pockets.length && phase.isMoving) {
      final report = phase != LuckyPhase.idleSpinning;
      reset();
      if (report) _result = const LuckyResult.cancelled();
    }
    final oldOffset = _config.options.offsetDegree;
    _config = config;
    _layout = layout;
    if (frame.targetIndex >= config.pockets.length) reset();
    if (!phase.isMoving) {
      frame.ballRadius = phase == LuckyPhase.settled
          ? layout?.pocketRadius ?? 0
          : layout?.trackRadius ?? 0;
      if (phase == LuckyPhase.settled) {
        frame.ballDeg += config.options.offsetDegree - oldOffset;
      }
    }
  }

  /// 开始本局；无格子、空布局或运动中返回 false。
  @override
  bool start() {
    if (!phase.canPlay || _layout == null || _layout!.isEmpty) {
      return false;
    }
    frame.phase = LuckyPhase.accelerating;
    frame.targetIndex = -1;
    frame.ballRadius = _layout!.trackRadius;
    _pending = -1;
    _elapsed = _accTime = 0;
    _accFrames = 0;
    _result = null;
    return true;
  }

  /// 开始待机慢转，缺少有效布局时拒绝。
  @override
  bool idleSpin() {
    if (!phase.canPlay ||
        phase == LuckyPhase.idleSpinning ||
        _layout == null ||
        _layout!.isEmpty) {
      return false;
    }
    frame.phase = LuckyPhase.idleSpinning;
    return true;
  }

  /// 请求按下标停止；负数作废，正数按格子数取余，减速时拒绝。
  bool stop(int index) {
    if (!phase.canStop) {
      return false;
    }
    if (index < 0) return cancel();
    _pending = index % _config.pockets.length;
    return true;
  }

  /// 取消加速或匀速中的一局；待机取消不产生结果。
  @override
  bool cancel() => cancelWith((report) {
        reset();
        if (report) _result = const LuckyResult.cancelled();
      });

  /// 回到原点，清除待停止请求和结果。
  @override
  void reset() {
    frame.phase = LuckyPhase.idle;
    frame.discDeg = frame.ballDeg = 0;
    frame.ballRadius = _layout?.trackRadius ?? 0;
    frame.ballPocket = 0;
    frame.targetIndex = _pending = -1;
    _elapsed = 0;
    _result = null;
    _queuedConfig = null;
    _queuedLayout = null;
  }

  /// 只在进入减速时求解一次位移。
  void _beginStop() {
    frame.phase = LuckyPhase.decelerating;
    frame.targetIndex = _pending;
    _elapsed = 0;
    _disc0 = frame.discDeg;
    _psi0 = frame.ballDeg - frame.discDeg;
    final o = _config.options;
    final frameMs = _options.timebase == LuckyTimebase.frame && _accFrames > 0
        ? _accTime / _accFrames
        : kLuckyReferenceFrameMs;
    final unit = _options.decelerationEasing
        .easeOut(frameMs, 0, 1, _options.decelerationMs);
    _discChange = unit == 0 ? 0 : _options.speed * o.discSpeedRatio / unit;
    final target =
        _pending * kLuckyFullTurnDeg / _config.pockets.length + o.offsetDegree;
    final base = -luckyWrap(_psi0 - target, kLuckyFullTurnDeg);
    _psiChange = _options.stopSolver.solve(LuckyStopProblem(
        start: _psi0,
        candidate: (i) => base - kLuckyFullTurnDeg * (i - 1),
        cruiseSpeed: _options.speed * (1 + o.discSpeedRatio),
        frameMs: frameMs,
        decelerationMs: _options.decelerationMs,
        easing: _options.decelerationEasing,
        direction: -1,
        selection: LuckyStopSelection.nearest));
  }

  /// 推进有效时间并返回阶段、经过格子及绘制事件位。
  @override
  int tick(double tMs, double dtMs) {
    if (!phase.isMoving) return LuckyMotionEvents.none;
    final before = phase;
    final pocket = frame.ballPocket;
    final dt = dtMs.isFinite ? math.max(0.0, dtMs) : 0.0;
    var events = LuckyMotionEvents.repaint;
    if (phase == LuckyPhase.cruising && _pending >= 0) _beginStop();
    _elapsed += dt;
    if (phase == LuckyPhase.decelerating) {
      final o = _config.options;
      final p = luckyUnit(_elapsed / _options.decelerationMs);
      frame.discDeg = _options.decelerationEasing
          .easeOut(_elapsed, _disc0, _discChange, _options.decelerationMs);
      frame.ballDeg = frame.discDeg +
          _options.decelerationEasing
              .easeOut(_elapsed, _psi0, _psiChange, _options.decelerationMs);
      final fraction = o.dropFraction.clamp(0.000001, 1.0);
      final q = luckyUnit((p - (1 - fraction)) / fraction);
      final eased = LuckyEasings.quad.easeIn(q, 0, 1, 1);
      frame.ballRadius = _layout!.trackRadius +
          (_layout!.pocketRadius - _layout!.trackRadius) * eased +
          (_config.options.pocketOuterFactor -
                  _config.options.pocketInnerFactor) *
              _layout!.radius *
              o.bounceAmplitudeFactor *
              (1 - q) *
              math.sin(math.pi * o.bounceCount * q).abs();
      if (p == 1) {
        frame.phase = LuckyPhase.settled;
        frame.ballRadius = _layout!.pocketRadius;
        _result = LuckyResult(
            index: frame.targetIndex,
            prize: _config.pockets[frame.targetIndex]);
        events |= LuckyMotionEvents.settled;
      }
    } else {
      final k = _options.timebase == LuckyTimebase.frame
          ? 1.0
          : dt / kLuckyReferenceFrameMs;
      var speed = phase == LuckyPhase.idleSpinning
          ? _options.idleSpinSpeed
          : _options.speed;
      if (phase == LuckyPhase.accelerating) {
        _accTime += dt;
        _accFrames++;
        speed = _options.accelerationEasing.easeIn(
            _elapsed,
            _options.idleSpinSpeed,
            _options.speed - _options.idleSpinSpeed,
            _options.accelerationMs);
        if (_elapsed >= _options.accelerationMs) {
          frame.phase = LuckyPhase.cruising;
        }
      }
      frame.discDeg += speed * _config.options.discSpeedRatio * k;
      frame.ballDeg -= speed * k;
    }
    final pocketWidth = kLuckyFullTurnDeg / _config.pockets.length;
    frame.ballPocket = (luckyWrap(
                    frame.ballDeg -
                        frame.discDeg -
                        _config.options.offsetDegree +
                        pocketWidth / kLuckyHalfDivisor,
                    kLuckyFullTurnDeg) /
                pocketWidth)
            .floor() %
        _config.pockets.length;
    if (frame.ballPocket != pocket) events |= LuckyMotionEvents.itemPassed;
    if (phase == LuckyPhase.settled && _queuedConfig != null) {
      final queued = _queuedConfig!;
      final layout = _queuedLayout;
      _queuedConfig = null;
      _queuedLayout = null;
      configure(queued, layout);
    }
    if (before != phase) events |= LuckyMotionEvents.phaseChanged;
    return events;
  }

  /// 取走一次性结果；随后调用返回 null。
  @override
  LuckyResult<NumberWheelPocket>? takeResult() {
    final result = _result;
    _result = null;
    return result;
  }
}
