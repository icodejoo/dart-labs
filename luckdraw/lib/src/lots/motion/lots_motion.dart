import 'dart:math' as math;

import '../../core/foundation/constants.dart';
import '../../core/foundation/duration_ms.dart';
import '../../core/game/frame.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/motion_options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/motion/timebase.dart';
import '../layout/lots_layout.dart';
import '../model/lots_config.dart';
import '../model/lots_parts.dart';

/// 抽签的细分展示阶段，全部收尾阶段属于 LuckyPhase.decelerating。
enum LotsStage {
  /// 静止。
  resting,

  /// 加速或匀速摇动。
  shaking,

  /// 阻尼停摇。
  damping,

  /// 目标签升起。
  rising,

  /// 展示签文卡。
  revealing,

  /// 完成。
  done,
}

/// 抽签复用帧；升签和展示进度均在零至一之间。
final class LotsFrame extends LuckyFrame {
  /// 创建静止帧。
  LotsFrame();

  /// 摇动累计相位，单位为度。
  double shakePhaseDeg = 0;

  /// 当前签筒摇动角度，单位为度。
  double shakeDeg = 0;

  /// 当前细分阶段。
  LotsStage stage = LotsStage.resting;

  /// 目标候选签下标，未选择时为负一。
  int targetIndex = -1;

  /// 目标签展示槽位，未选择时为负一。
  int targetSlot = -1;

  /// 升签进度。
  double riseProgress = 0;

  /// 展示卡进度。
  double revealProgress = 0;
}

/// 摇动、阻尼、升签和展示状态机，不包含传感器触发。
final class LotsMotion extends LuckyMotion<LotsConfig, LotsLayout, LotsFrame,
    LuckyResult<LotsStick>> {
  /// 创建独立状态机。
  LotsMotion();

  /// 跨帧复用快照。
  @override
  final LotsFrame frame = LotsFrame();

  /// 当前配置。
  LotsConfig _config = const LotsConfig();

  /// 当前布局。
  LotsLayout? _layout;

  /// 本阶段经过毫秒。
  double _elapsed = 0;

  /// 待停止下标。
  int _pending = -1;

  /// 尚未取走的结果。
  LuckyResult<LotsStick>? _result;

  /// 当前配置只读视图。
  LotsConfig get config => _config;

  /// 运动参数。
  LuckyMotionOptions get _options => _config.options.motion;

  /// 当前统一阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 时间轴单帧上限。
  @override
  Duration get maxFrameDelta => _options.maxFrameDelta;

  /// 应用配置；签数变化时尝试取消本局。
  @override
  void configure(LotsConfig config, LotsLayout? layout) {
    assert(config.options.motion.accelerationTime > Duration.zero);
    assert(config.options.motion.decelerationTime > Duration.zero);
    if (_config.sticks.length != config.sticks.length && phase.isMoving) {
      final report = phase != LuckyPhase.idleSpinning;
      reset();
      if (report) _result = const LuckyResult.cancelled();
    }
    _config = config;
    _layout = layout;
    if (frame.targetIndex >= config.sticks.length) {
      reset();
    } else if (frame.targetIndex >= 0) {
      final count = layout?.sticks.length ?? 0;
      frame.targetSlot = count == 0 ? -1 : frame.targetIndex % count;
    }
  }

  /// 开始摇动；空布局或运动中拒绝。
  @override
  bool start() {
    if (!phase.canPlay || _layout == null || _layout!.isEmpty) {
      return false;
    }
    frame.phase = LuckyPhase.accelerating;
    frame.stage = LotsStage.shaking;
    frame.targetIndex = frame.targetSlot = _pending = -1;
    frame.riseProgress = frame.revealProgress = _elapsed = 0;
    _result = null;
    return true;
  }

  /// 开始低速待机摇动。
  @override
  bool idleSpin() {
    if (!phase.canPlay ||
        phase == LuckyPhase.idleSpinning ||
        _layout == null ||
        _layout!.isEmpty) {
      return false;
    }
    frame.phase = LuckyPhase.idleSpinning;
    frame.stage = LotsStage.shaking;
    return true;
  }

  /// 按下标请求停止；负数取消，正数按签数取余。
  bool stop(int index) {
    if (!phase.canStop) {
      return false;
    }
    if (index < 0) return cancel();
    _pending = index % _config.sticks.length;
    return true;
  }

  /// 取消加速或匀速；待机取消不产生结果，减速时拒绝。
  @override
  bool cancel() => cancelWith((report) {
        reset();
        if (report) _result = const LuckyResult.cancelled();
      });

  /// 回到静止并清除本局数据。
  @override
  void reset() {
    frame.phase = LuckyPhase.idle;
    frame.stage = LotsStage.resting;
    frame.shakePhaseDeg = frame.shakeDeg =
        frame.riseProgress = frame.revealProgress = _elapsed = 0;
    frame.targetIndex = frame.targetSlot = _pending = -1;
    _result = null;
  }

  /// 推进有效时间；大帧间隔也可跨过全部收尾阶段。
  @override
  int tick(double tMs, double dtMs) {
    if (!phase.isMoving || _layout == null || _layout!.isEmpty) {
      return LuckyMotionEvents.none;
    }
    final before = phase;
    final dt = dtMs.isFinite ? math.max(0.0, dtMs) : 0.0;
    final k = _options.timebase == LuckyTimebase.frame
        ? 1.0
        : dt / kLuckyReferenceFrameMs;
    if (phase == LuckyPhase.cruising && _pending >= 0) {
      frame.phase = LuckyPhase.decelerating;
      frame.stage = LotsStage.damping;
      frame.targetIndex = _pending;
      frame.targetSlot = _pending % _layout!.sticks.length;
      _elapsed = 0;
    }
    _elapsed += dt;
    final idle = phase == LuckyPhase.idleSpinning;
    frame.shakePhaseDeg += (idle ? _options.idleSpinSpeed : _options.speed) * k;
    var amplitude = _config.options.maxShakeDeg;
    var events = LuckyMotionEvents.repaint;
    if (phase == LuckyPhase.accelerating) {
      amplitude *= _options.accelerationEasing
          .easeIn(_elapsed, 0, 1, _options.accelerationMs);
      if (_elapsed >= _options.accelerationMs) {
        frame.phase = LuckyPhase.cruising;
      }
    } else if (phase == LuckyPhase.decelerating) {
      final damping = _options.decelerationMs;
      final rise = math.max(1.0, luckyMs(_config.options.riseTime));
      final reveal = math.max(1.0, luckyMs(_config.options.revealTime));
      amplitude *=
          1 - _options.decelerationEasing.easeOut(_elapsed, 0, 1, damping);
      if (_elapsed >= damping) {
        frame.stage = LotsStage.rising;
        frame.riseProgress =
            _config.options.riseEasing.easeOut(_elapsed - damping, 0, 1, rise);
      }
      if (_elapsed >= damping + rise) {
        frame.stage = LotsStage.revealing;
        if (_config.options.revealOnSettle) {
          frame.revealProgress = _config.options.revealEasing
              .easeOut(_elapsed - damping - rise, 0, 1, reveal);
        }
      }
      if (_elapsed >=
          damping + rise + (_config.options.revealOnSettle ? reveal : 0)) {
        frame.phase = LuckyPhase.settled;
        frame.stage = LotsStage.done;
        _result = LuckyResult(
            index: frame.targetIndex, prize: _config.sticks[frame.targetIndex]);
        events |= LuckyMotionEvents.settled;
      }
    }
    frame.shakeDeg =
        amplitude * _config.options.shakeWaveform(frame.shakePhaseDeg);
    if (before != phase) events |= LuckyMotionEvents.phaseChanged;
    return events;
  }

  /// 取走一次性结果，无结果返回 null。
  @override
  LuckyResult<LotsStick>? takeResult() {
    final result = _result;
    _result = null;
    return result;
  }
}
