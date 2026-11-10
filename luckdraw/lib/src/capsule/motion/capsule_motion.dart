import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/easing/easing.dart';
import '../../core/foundation/constants.dart';
import '../../core/game/frame.dart';
import '../../core/kinematics/swirl_mixer.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/motion_options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/result.dart';
import '../../core/motion/timebase.dart';
import '../layout/capsule_layout.dart';
import '../model/capsule_config.dart';
import '../model/capsule_parts.dart';

/// 旋钮相对搅拌角的传动比例，来自 T5.3。
const double _knobRatio = 0.25;

/// 差分速度的毫秒间隔，来自 T5.3。
const double _differenceMs = 1;

/// 扭蛋机细分阶段；收尾阶段均属于 LuckyPhase.decelerating。
enum CapsuleStage {
  /// 静止堆积。
  resting,

  /// 加速或匀速搅拌。
  mixing,

  /// 搅拌减速归位。
  settlingMix,

  /// 胶囊沿滑道掉落。
  dropping,

  /// 展开奖品卡。
  revealing,

  /// 正常结束。
  done,
}

/// 复用的扭蛋机帧，调用方只读。
final class CapsuleFrame extends LuckyFrame {
  /// 创建静止帧。
  CapsuleFrame();

  /// 累计搅拌角，单位度。
  double swirlDeg = 0;

  /// 搅拌强度，范围零至一。
  double mix = 0;

  /// 旋钮角，单位度。
  double knobDeg = 0;

  /// 当前细分阶段。
  CapsuleStage stage = CapsuleStage.resting;

  /// 本局目标奖品下标，未选中为负一。
  int targetPrize = -1;

  /// 掉落的胶囊下标，尚未选中为负一。
  int droppedCapsule = -1;

  /// 掉落弧长进度，范围零至一。
  double dropProgress = 0;

  /// 开蛋卡片缩放进度，范围零至一。
  double revealProgress = 0;

  /// 胶囊横坐标，相对球心。
  Float64List x = Float64List(0);

  /// 胶囊纵坐标，相对球心。
  Float64List y = Float64List(0);

  /// 胶囊自转角，单位弧度。
  Float64List angle = Float64List(0);
}

/// 确定性扭蛋机动画；先 configure，再 start 与 tick。
final class CapsuleMotion extends LuckyMotion<CapsuleConfig, CapsuleLayout,
    CapsuleFrame, LuckyResult<CapsulePrize>> {
  /// 创建动画；选奖由控制器处理。
  CapsuleMotion();

  /// 跨帧复用的快照。
  @override
  final CapsuleFrame frame = CapsuleFrame();

  /// 当前配置。
  CapsuleConfig _config = const CapsuleConfig();

  /// 已应用配置，供控制器构造选奖上下文。
  CapsuleConfig get config => _config;

  /// 当前是否接受停止命令。
  bool get acceptsStop =>
      phase == LuckyPhase.accelerating || phase == LuckyPhase.cruising;

  /// 当前几何。
  CapsuleLayout? _layout;

  /// 实例持有的搅拌器。
  LuckySwirlMixer? _mixer;

  /// 已移出容器的胶囊标记。
  List<bool> _excluded = [];

  /// 当前段有效毫秒数。
  double _elapsed = 0;

  /// 减速起始搅拌角。
  double _stopSwirl = 0;

  /// 从待机慢转接入时保留的初速度。
  double _startSpeed = 0;

  /// 当前加速或减速段使用的参数快照。
  LuckyMotionOptions _activeMotion = const CapsuleOptions().motion;

  /// 当前收尾使用的时长与开蛋策略快照。
  CapsuleOptions _tailOptions = const CapsuleOptions();

  /// 加速期有效帧数，用于 frame 时间基准采样。
  int _frameCount = 0;

  /// 加速期平均有效帧间隔。
  double _sampledFrameMs = kLuckyReferenceFrameMs;

  /// 减速开始时冻结的帧间隔，避免帧率波动改变整段位移。
  double _stopFrameMs = kLuckyReferenceFrameMs;

  /// 待处理奖品下标。
  int? _pending;

  /// 一次性结果。
  LuckyResult<CapsulePrize>? _result;

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 本玩法不发条目经过事件。
  @override
  int get passedReel => 0;

  /// 本玩法不发条目经过事件。
  @override
  int get passedIndex => -1;

  /// 当前配置的单帧上限。
  @override
  Duration get maxFrameDelta => _config.options.motion.maxFrameDelta;

  /// 应用配置；缺少非空几何或胶囊时拒绝开始。
  @override
  void configure(CapsuleConfig config, CapsuleLayout? layout) {
    _config = config;
    if (identical(layout, _layout)) return;
    _layout = layout;
    if (layout == null) {
      _mixer = null;
      return;
    }
    _mixer = LuckySwirlMixer(
        rest: layout.rest,
        containerRadius: layout.globeRadius,
        bodyRadius: layout.capsuleRadius);
    frame.x = _mixer!.x;
    frame.y = _mixer!.y;
    frame.angle = _mixer!.angle;
    _excluded = List.filled(layout.rest.length, false);
    if (layout.rest.isEmpty ||
        config.prizes.isEmpty ||
        frame.droppedCapsule >= layout.rest.length ||
        frame.targetPrize >= config.prizes.length) {
      final report = phase.isMoving && phase != LuckyPhase.idleSpinning;
      reset();
      if (report) _result = const LuckyResult.cancelled();
    }
    if (_pending != null && config.prizes.isNotEmpty) {
      _pending = _pending! % config.prizes.length;
    }
    if (frame.droppedCapsule >= 0 &&
        frame.droppedCapsule < _excluded.length &&
        (frame.stage == CapsuleStage.dropping ||
            frame.stage == CapsuleStage.revealing ||
            frame.stage == CapsuleStage.done)) {
      _excluded[frame.droppedCapsule] = true;
    }
    _update();
  }

  /// 有奖品、有胶囊且非零尺寸时才能开始。
  bool get _ready =>
      _layout != null &&
      !_layout!.isEmpty &&
      _layout!.capsules.isNotEmpty &&
      _config.prizes.isNotEmpty;

  /// 开始本局；运动中拒绝，待机慢转可转入加速。
  @override
  bool start() {
    if (!_ready || !phase.acceptsStart) return false;
    _startSpeed = phase == LuckyPhase.idleSpinning
        ? _config.options.motion.idleSpinSpeed
        : 0;
    _clear();
    _activeMotion = _config.options.motion;
    _frameCount = 0;
    _sampledFrameMs = kLuckyReferenceFrameMs;
    frame.phase = LuckyPhase.accelerating;
    frame.stage = CapsuleStage.mixing;
    return true;
  }

  /// 从静止或结算后进入待机慢转。
  @override
  bool idleSpin() {
    if (!_ready || phase != LuckyPhase.idle && phase != LuckyPhase.settled) {
      return false;
    }
    _clear();
    frame.phase = LuckyPhase.idleSpinning;
    frame.stage = CapsuleStage.mixing;
    return true;
  }

  /// 请求停止；空或负下标作废，正下标按奖品数取余，减速时拒绝。
  bool requestStop(int? index) {
    if (!acceptsStop) return false;
    if (index == null || index < 0) return cancel();
    _pending = index % _config.prizes.length;
    return true;
  }

  /// 作废加速或匀速；待机慢转取消不产生结果，减速取消无效。
  @override
  bool cancel() {
    if (!phase.isMoving || phase == LuckyPhase.decelerating) return false;
    final report = phase != LuckyPhase.idleSpinning;
    reset();
    if (report) _result = const LuckyResult.cancelled();
    return true;
  }

  /// 恢复静止并清除结果与移出标记。
  @override
  void reset() {
    _clear();
    frame.swirlDeg = 0;
    frame.knobDeg = 0;
    frame.phase = LuckyPhase.idle;
    frame.stage = CapsuleStage.resting;
    _update();
  }

  /// 清空本局收尾状态，保留搅拌角以支持待机启动。
  void _clear() {
    _elapsed = 0;
    _pending = null;
    _result = null;
    frame.targetPrize = -1;
    frame.droppedCapsule = -1;
    frame.dropProgress = 0;
    frame.revealProgress = 0;
    frame.mix = 0;
    _excluded.fillRange(0, _excluded.length, false);
    _update();
  }

  /// 在目标配色中取静止位置离出口最近的胶囊；缺配色时退到任意胶囊。
  void _beginStop() {
    final l = _layout!;
    frame.targetPrize = _pending! % _config.prizes.length;
    _pending = null;
    var best = double.infinity;
    final hasTarget = l.capsules.contains(frame.targetPrize);
    for (var i = 0; i < l.rest.length; i++) {
      if (hasTarget && l.capsules[i] != frame.targetPrize) continue;
      final dx = l.rest[i].dx + l.globeCenter.dx - l.exit.dx;
      final dy = l.rest[i].dy + l.globeCenter.dy - l.exit.dy;
      final distance = dx * dx + dy * dy;
      if (distance < best) {
        best = distance;
        frame.droppedCapsule = i;
      }
    }
    _elapsed = 0;
    _stopSwirl = frame.swirlDeg;
    _tailOptions = _config.options;
    _activeMotion = _tailOptions.motion;
    _stopFrameMs = _activeMotion.timebase == LuckyTimebase.frame
        ? _sampledFrameMs
        : kLuckyReferenceFrameMs;
    frame.phase = LuckyPhase.decelerating;
    frame.stage = CapsuleStage.settlingMix;
  }

  /// 按有效时间推进；直接调用时亦钳制长间隔，避免后台跳变。
  @override
  int tick(double tMs, double dtMs) {
    if (!phase.isMoving || !_ready) return LuckyMotionEvents.none;
    final before = phase;
    final dt = dtMs
        .clamp(0,
            maxFrameDelta.inMicroseconds / Duration.microsecondsPerMillisecond)
        .toDouble();
    if (phase == LuckyPhase.cruising && _pending != null) {
      _beginStop();
    } else {
      _elapsed += dt;
    }
    final m = phase == LuckyPhase.idleSpinning
        ? _config.options.motion
        : _activeMotion;
    if (phase == LuckyPhase.accelerating ||
        phase == LuckyPhase.cruising ||
        phase == LuckyPhase.idleSpinning) {
      var speed = m.speed;
      if (phase == LuckyPhase.idleSpinning) speed = m.idleSpinSpeed;
      if (phase == LuckyPhase.accelerating) {
        if (dt > 0) {
          _frameCount++;
          _sampledFrameMs = _elapsed / _frameCount;
        }
        speed = m.accelerationEasing.easeIn(
            math.min(_elapsed, m.accelerationMs),
            _startSpeed,
            m.speed - _startSpeed,
            m.accelerationMs);
        if (_elapsed >= m.accelerationMs) frame.phase = LuckyPhase.cruising;
      }
      frame.swirlDeg += speed *
          (m.timebase == LuckyTimebase.frame
              ? (dt > 0 ? 1 : 0)
              : dt / kLuckyReferenceFrameMs);
      frame.mix = m.speed == 0 ? 0 : (speed / m.speed).clamp(0, 1);
    } else if (frame.stage == CapsuleStage.settlingMix) {
      final end = math.min(_elapsed, m.decelerationMs);
      final unit = m.decelerationEasing.easeOut(
          math.min(_stopFrameMs, m.decelerationMs), 0, 1, m.decelerationMs);
      final c = unit == 0 ? 0.0 : m.speed / unit;
      frame.swirlDeg =
          m.decelerationEasing.easeOut(end, _stopSwirl, c, m.decelerationMs);
      final next = math.min(end + _differenceMs, m.decelerationMs);
      final velocity =
          m.decelerationEasing.easeOut(next, 0, c, m.decelerationMs) -
              m.decelerationEasing.easeOut(end, 0, c, m.decelerationMs);
      frame.mix =
          m.speed == 0 ? 0 : (velocity * _stopFrameMs / m.speed).clamp(0, 1);
      if (_elapsed >= m.decelerationMs) {
        frame.mix = 0;
        frame.stage = CapsuleStage.dropping;
        _elapsed = 0;
        _excluded[frame.droppedCapsule] = true;
      }
    } else if (frame.stage == CapsuleStage.dropping) {
      final duration = math.max(
          1.0,
          _tailOptions.dropTime.inMicroseconds /
              Duration.microsecondsPerMillisecond);
      frame.dropProgress = LuckyEasings.quad
          .easeIn(math.min(_elapsed, duration), 0, 1, duration);
      if (_elapsed >= duration) {
        _elapsed = 0;
        if (_tailOptions.revealOnSettle) {
          frame.stage = CapsuleStage.revealing;
        } else {
          _finish();
        }
      }
    } else if (frame.stage == CapsuleStage.revealing) {
      final duration = math.max(
          1.0,
          _tailOptions.revealTime.inMicroseconds /
              Duration.microsecondsPerMillisecond);
      frame.revealProgress = LuckyEasings.cubic
          .easeOut(math.min(_elapsed, duration), 0, 1, duration);
      if (_elapsed >= duration) _finish();
    }
    frame.knobDeg = frame.swirlDeg * _knobRatio;
    _update();
    return LuckyMotionEvents.repaint |
        (before != phase ? LuckyMotionEvents.phaseChanged : 0) |
        (phase == LuckyPhase.settled ? LuckyMotionEvents.settled : 0);
  }

  /// 完成收尾，保留帧展示并提供一次性结果。
  void _finish() {
    frame.stage = CapsuleStage.done;
    frame.phase = LuckyPhase.settled;
    _result = LuckyResult(
        index: frame.targetPrize, prize: _config.prizes[frame.targetPrize]);
  }

  /// 写入复用缓冲；掉落按预计算弧长插值，不创建临时坐标对象。
  void _update() {
    _mixer?.update(frame.swirlDeg, frame.mix, excluded: _excluded);
    final i = frame.droppedCapsule, l = _layout;
    if (l == null || i < 0 || i >= _excluded.length || !_excluded[i]) return;
    var remaining = l.dropLength * frame.dropProgress;
    for (var segment = 0; segment < l.lengths.length; segment++) {
      final length = l.lengths[segment];
      if (remaining <= length || segment == l.lengths.length - 1) {
        final ratio = length == 0 ? 0.0 : (remaining / length).clamp(0, 1);
        final a = l.dropPath[segment], b = l.dropPath[segment + 1];
        frame.x[i] = a.dx + (b.dx - a.dx) * ratio - l.globeCenter.dx;
        frame.y[i] = a.dy + (b.dy - a.dy) * ratio - l.globeCenter.dy;
        break;
      }
      remaining -= length;
    }
  }

  /// 取走一次性结果；后续调用返回空。
  @override
  LuckyResult<CapsulePrize>? takeResult() {
    final result = _result;
    _result = null;
    return result;
  }
}
