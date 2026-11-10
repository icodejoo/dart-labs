import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/easing/easing.dart';
import '../../core/foundation/constants.dart';
import '../../core/kinematics/swirl_mixer.dart';
import '../../core/motion/motion.dart';
import '../../core/motion/motion_options.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/timebase.dart';
import '../layout/lotto_layout.dart';
import '../model/lotto_config.dart';
import 'lotto_frame.dart';

export 'lotto_frame.dart';

/// 飞行路径分段系数。
const double _half = 0.5;

/// 飞行路径的双倍时间换算。
const double _twice = 2;

/// 独立于 Widget 的摇奖状态机；例如 configure 后 start、stopWith、tick。
final class LottoMotion
    extends LuckyMotion<LottoConfig, LottoLayout, LottoFrame, LottoResult> {
  /// 创建静止状态机。
  LottoMotion();

  /// 当前配置。
  LottoConfig? _config;

  /// 已应用的配置；未配置时为空。
  LottoConfig? get config => _config;

  /// 本次加速或慢转采用的参数。
  LuckyMotionOptions? _spinOptions;

  /// 本次开奖采用的参数，避免外观更新改变正在进行的序列。
  LottoOptions? _drawOptions;

  /// 当前序列选项。
  LottoOptions get _options => _drawOptions ?? _config!.options;

  /// 当前几何。
  LottoLayout? _layout;

  /// 最新布局是否允许开始新局；临时隐藏时仍可完成已有开奖。
  bool _available = false;

  /// 每池搅拌器。
  List<LuckySwirlMixer> _mixers = const [];

  /// 每池排除的号码球。
  List<List<bool>> _excluded = const [];

  /// 待开奖的不可变号码快照。
  LottoDraw? _draw;

  /// 各次出球对应的池。
  Int32List _poolOf = Int32List(0);

  /// 各次出球对应的球下标。
  Int32List _ballOf = Int32List(0);

  /// 各次出球对应的抽出顺序槽。
  Int32List _slotOfDraw = Int32List(0);

  /// 各次出球排序后的槽。
  Int32List _sortedSlot = Int32List(0);

  /// 飞行起点横坐标。
  Float64List _fromX = Float64List(0);

  /// 飞行起点纵坐标。
  Float64List _fromY = Float64List(0);

  /// 已开始飞行的标记。
  List<bool> _started = [];

  /// 已落槽的标记。
  List<bool> _landed = [];

  /// 待通知的开奖序号；固定缓冲避免帧内分配。
  Int32List _notifications = Int32List(0);

  /// 通知写指针。
  int _written = 0;

  /// 通知读指针。
  int _read = 0;

  /// 当前加速经过的有效时间。
  double _accelerated = 0;

  /// 当前开奖经过的有效时间。
  double _drawing = 0;

  /// 上一帧的运动速度比。
  double _speedRatio = 0;

  /// 是否有未进入减速的开奖请求。
  bool _pending = false;

  /// 本局待取结果。
  LottoResult? _result;

  /// 跨帧复用快照。
  @override
  final LottoFrame frame = LottoFrame();

  /// 当前阶段。
  @override
  LuckyPhase get phase => frame.phase;

  /// 最近落槽的池号。
  @override
  int passedReel = 0;

  /// 最近落槽的号码。
  @override
  int passedIndex = 0;

  /// 有效时间轴采用当前配置的上限。
  @override
  Duration get maxFrameDelta =>
      _config?.options.motion.maxFrameDelta ?? kLuckyDefaultMaxFrameDelta;

  /// 应用配置；无布局时命令返回 false，不开始运动。
  @override
  void configure(LottoConfig config, LottoLayout? layout) {
    config.validate();
    _available = layout != null && !layout.isEmpty;
    if (!_available) {
      _config ??= config;
      return;
    }
    final changed = _config == null || !_samePools(_config!, config);
    final previousLayout = _layout;
    final oldX = frame.x;
    final oldY = frame.y;
    final oldAngle = frame.angle;
    _config = config;
    if (identical(layout, _layout) && !changed) return;
    _layout = layout;
    final geometry = layout!;
    _mixers = List.generate(geometry.drums.length, (p) {
      final drum = geometry.drums[p];
      return LuckySwirlMixer(
          rest: drum.rest,
          containerRadius: drum.radius,
          bodyRadius: drum.ballRadius);
    });
    frame.x = _mixers.map((m) => m.x).toList(growable: false);
    frame.y = _mixers.map((m) => m.y).toList(growable: false);
    frame.angle = _mixers.map((m) => m.angle).toList(growable: false);
    if (!changed && previousLayout != null && !previousLayout.isEmpty) {
      for (var p = 0; p < _mixers.length; p++) {
        final scale = geometry.drums[p].radius / previousLayout.drums[p].radius;
        for (var b = 0; b < frame.x[p].length; b++) {
          frame.x[p][b] = oldX[p][b] * scale;
          frame.y[p][b] = oldY[p][b] * scale;
          frame.angle[p][b] = oldAngle[p][b];
        }
      }
      for (var i = 0; i < _fromX.length; i++) {
        final p = _poolOf[i];
        final scale = geometry.drums[p].radius / previousLayout.drums[p].radius;
        _fromX[i] *= scale;
        _fromY[i] *= scale;
        if (phase == LuckyPhase.settled && _landed[i]) {
          final b = _ballOf[i];
          final drum = geometry.drums[p];
          final slot = drum.slots[frame.slotOf[p][b]];
          frame.x[p][b] = slot.dx - drum.center.dx;
          frame.y[p][b] = slot.dy - drum.center.dy;
        }
      }
      return;
    }
    frame.slotOf = _mixers
        .map((m) => Int32List(m.x.length)..fillRange(0, m.x.length, -1))
        .toList(growable: false);
    _excluded = _mixers
        .map((m) => List.filled(m.x.length, false))
        .toList(growable: false);
    final n = config.pools.fold<int>(0, (sum, pool) => sum + pool.count);
    frame.flight = Float64List(n);
    _poolOf = Int32List(n);
    _ballOf = Int32List(n);
    _slotOfDraw = Int32List(n);
    _sortedSlot = Int32List(n);
    _fromX = Float64List(n);
    _fromY = Float64List(n);
    _notifications = Int32List(n);
    _started = List.filled(n, false);
    _landed = List.filled(n, false);
    // 结构变化在 core 延迟到开奖后；其它阶段保留运动角度和阶段。
    if (changed) {
      _draw = null;
      _pending = false;
      _read = 0;
      _written = 0;
      frame.drawnCount = 0;
    }
  }

  /// 判断结构字段，外观变化不改变号码顺序。
  bool _samePools(LottoConfig a, LottoConfig b) {
    if (a.pools.length != b.pools.length) return false;
    for (var p = 0; p < a.pools.length; p++) {
      if (a.pools[p].min != b.pools[p].min ||
          a.pools[p].max != b.pools[p].max ||
          a.pools[p].count != b.pools[p].count) {
        return false;
      }
    }
    return true;
  }

  /// 开始抽奖，待机转动的角度与速度连续保留。
  @override
  bool start() {
    if (!phase.canPlay || !_available) {
      return false;
    }
    final idle = phase == LuckyPhase.idleSpinning;
    final angle = frame.swirlDeg;
    reset();
    if (idle) {
      frame.swirlDeg = angle;
      _speedRatio = (_config!.options.motion.idleSpinSpeed /
              _config!.options.motion.speed)
          .clamp(0.0, 1.0);
    }
    _spinOptions = _config!.options.motion;
    frame.phase = LuckyPhase.accelerating;
    return true;
  }

  /// 进入待机慢转，仅空闲或已结算阶段接受。
  @override
  bool idleSpin() {
    if (phase != LuckyPhase.idle && phase != LuckyPhase.settled ||
        !_available) {
      return false;
    }
    reset();
    _spinOptions = _config!.options.motion;
    frame.phase = LuckyPhase.idleSpinning;
    return true;
  }

  /// 按给定号码开奖；非法号码抛 ArgumentError，非加速或匀速返回 false。
  bool stopWith(LottoDraw draw) {
    if (phase != LuckyPhase.accelerating && phase != LuckyPhase.cruising ||
        _pending) {
      return false;
    }
    draw.validate(_config!);
    _draw =
        LottoDraw(List.unmodifiable(draw.numbers.map(List<int>.unmodifiable)));
    _prepareDraw(_draw!);
    _pending = true;
    return true;
  }

  /// 预计算开奖序列与排序槽，避免帧内查找或分配。
  void _prepareDraw(LottoDraw draw) {
    var i = 0;
    for (var p = 0; p < draw.numbers.length; p++) {
      final sorted = [...draw.numbers[p]]..sort();
      for (var j = 0; j < draw.numbers[p].length; j++) {
        final number = draw.numbers[p][j];
        _poolOf[i] = p;
        _ballOf[i] = number - _config!.pools[p].min;
        _slotOfDraw[i] = j;
        _sortedSlot[i] = sorted.indexOf(number);
        i++;
      }
    }
  }

  /// 作废加速或匀速；待机取消不产生结果，开奖中忽略。
  @override
  bool cancel() {
    if (!phase.isMoving || phase == LuckyPhase.decelerating) return false;
    final idle = phase == LuckyPhase.idleSpinning;
    reset();
    if (!idle) _result = const LottoResult.cancelled();
    return true;
  }

  /// 还原所有球、开奖标记与角度。
  @override
  void reset() {
    frame.phase = LuckyPhase.idle;
    frame.swirlDeg = 0;
    frame.mix = 0;
    frame.drawnCount = 0;
    frame.flight.fillRange(0, frame.flight.length, 0);
    for (var p = 0; p < _mixers.length; p++) {
      _excluded[p].fillRange(0, _excluded[p].length, false);
      frame.slotOf[p].fillRange(0, frame.slotOf[p].length, -1);
      _mixers[p].update(0, 0);
    }
    _started.fillRange(0, _started.length, false);
    _landed.fillRange(0, _landed.length, false);
    _draw = null;
    _spinOptions = null;
    _drawOptions = null;
    _result = null;
    _pending = false;
    _accelerated = 0;
    _drawing = 0;
    _speedRatio = 0;
    _written = 0;
    _read = 0;
  }

  /// 更新混合位置，已出球的球保留飞行或结果位置。
  void _mix() {
    for (var p = 0; p < _mixers.length; p++) {
      _mixers[p].update(frame.swirlDeg, frame.mix, excluded: _excluded[p]);
    }
  }

  /// 按有效时间更新；长帧的落球通知按序逐帧排空后结算。
  @override
  int tick(double tMs, double dtMs) {
    if (!phase.isMoving) return LuckyMotionEvents.none;
    final options = _options;
    final motion = _spinOptions ?? options.motion;
    final before = phase;
    final dt = math.max(0.0, dtMs);
    final step = motion.timebase == LuckyTimebase.frame
        ? 1.0
        : dt / kLuckyReferenceFrameMs;
    if (phase == LuckyPhase.idleSpinning) {
      frame.mix = (motion.idleSpinSpeed / motion.speed).clamp(0.0, 1.0);
      frame.swirlDeg += motion.idleSpinSpeed * step;
    } else if (phase == LuckyPhase.accelerating) {
      _accelerated += dt;
      final base = _speedRatio;
      final eased = motion.accelerationEasing
          .easeIn(_accelerated, 0, 1, motion.accelerationMs);
      frame.mix = base + (1 - base) * eased;
      frame.swirlDeg += motion.speed * frame.mix * step;
      if (_accelerated >= motion.accelerationMs) {
        frame.phase = LuckyPhase.cruising;
      }
    } else if (phase == LuckyPhase.cruising) {
      frame.mix = 1;
      frame.swirlDeg += motion.speed * step;
      if (_pending) {
        frame.phase = LuckyPhase.decelerating;
        _drawing = 0;
        _drawOptions = _config!.options;
      }
    } else {
      _drawing += dt;
      _advanceDrawing(dt);
    }
    _mix();
    var events = LuckyMotionEvents.repaint;
    if (phase != before) events |= LuckyMotionEvents.phaseChanged;
    if (_read < _written) {
      final index = _notifications[_read++];
      passedReel = _poolOf[index];
      passedIndex = _config!.pools[passedReel].min + _ballOf[index];
      events |= LuckyMotionEvents.itemPassed;
    }
    if (phase == LuckyPhase.decelerating &&
        _drawing >= _endMs &&
        _read == _written) {
      frame.mix = 0;
      _mix();
      frame.phase = LuckyPhase.settled;
      _result = LottoResult(draw: _draw!);
      events |= LuckyMotionEvents.phaseChanged | LuckyMotionEvents.settled;
    }
    return events;
  }

  /// 完成全部出球与可选排序的时间。
  double get _lastLandingMs =>
      _options.motion.decelerationMs +
      (frame.flight.length - 1) * _ms(_options.drawInterval) +
      _ms(_options.ballFlightTime);

  /// 全部结果展示完成的时间。
  double get _sortedMs =>
      _lastLandingMs + (_options.sortResults ? _ms(kLottoSortTime) : 0);

  /// 结束搅拌并可结算的时间。
  double get _endMs => _sortedMs + _options.motion.decelerationMs;

  /// 以连续速度衔接搅拌、飞行和排序。
  void _advanceDrawing(double dt) {
    final options = _options;
    final motion = options.motion;
    final dec = motion.decelerationMs;
    final ease = motion.decelerationEasing;
    final time = _drawing;
    final previous = math.max(0.0, time - dt);
    final c = motion.speed / ease.easeOut(kLuckyReferenceFrameMs, 0, 1, dec);
    final ramp = ease.easeOut(time, 0, 1, dec);
    final oldRamp = ease.easeOut(previous, 0, 1, dec);
    frame.mix = 1 + (options.drawMix - 1) * ramp;
    final steadyTime =
        math.min(time, _sortedMs) - math.min(previous, _sortedMs);
    final tail = math.max(0.0, time - _sortedMs);
    final oldTail = math.max(0.0, previous - _sortedMs);
    frame.swirlDeg += c * (1 - options.drawMix) * (ramp - oldRamp) +
        motion.speed * options.drawMix * steadyTime / kLuckyReferenceFrameMs +
        c *
            options.drawMix *
            (ease.easeOut(tail, 0, 1, dec) - ease.easeOut(oldTail, 0, 1, dec));
    if (time >= _sortedMs) {
      final tail = time - _sortedMs;
      frame.mix = options.drawMix * (1 - ease.easeOut(tail, 0, 1, dec));
    }
    _mix();
    for (var i = 0; i < frame.flight.length; i++) {
      final elapsed = time - dec - i * _ms(options.drawInterval);
      if (elapsed < 0) continue;
      final p = _poolOf[i];
      final b = _ballOf[i];
      final drum = _layout!.drums[p];
      if (!_started[i]) {
        _started[i] = true;
        _excluded[p][b] = true;
        _fromX[i] = frame.x[p][b];
        _fromY[i] = frame.y[p][b];
        frame.slotOf[p][b] = _slotOfDraw[i];
      }
      final progress = (elapsed / _ms(options.ballFlightTime)).clamp(0.0, 1.0);
      frame.flight[i] = progress;
      final slot = drum.slots[_slotOfDraw[i]];
      final exitX = drum.exit.dx - drum.center.dx;
      final exitY = drum.exit.dy - drum.center.dy;
      final targetX = slot.dx - drum.center.dx;
      final targetY = slot.dy - drum.center.dy;
      if (progress < _half) {
        final q = LuckyEasings.cubic.easeIn(progress * _twice, 0, 1, 1);
        frame.x[p][b] = _fromX[i] + (exitX - _fromX[i]) * q;
        frame.y[p][b] = _fromY[i] + (exitY - _fromY[i]) * q;
      } else {
        final q =
            LuckyEasings.cubic.easeOut((progress - _half) * _twice, 0, 1, 1);
        frame.x[p][b] = exitX + (targetX - exitX) * q;
        frame.y[p][b] = exitY + (targetY - exitY) * q;
      }
      if (progress == 1 && !_landed[i]) {
        _landed[i] = true;
        frame.drawnCount++;
        _notifications[_written++] = i;
      }
      if (options.sortResults) {
        final lastInPool = i - _slotOfDraw[i] + _config!.pools[p].count - 1;
        final sortStart = dec +
            lastInPool * _ms(options.drawInterval) +
            _ms(options.ballFlightTime);
        final q = ((time - sortStart) / _ms(kLottoSortTime)).clamp(0.0, 1.0);
        if (q > 0) {
          final sorted = drum.slots[_sortedSlot[i]];
          frame.x[p][b] += (sorted.dx - slot.dx) * q;
          frame.y[p][b] += (sorted.dy - slot.dy) * q;
          if (q == 1) frame.slotOf[p][b] = _sortedSlot[i];
        }
      }
    }
  }

  /// 时长换算为毫秒。
  double _ms(Duration value) =>
      value.inMicroseconds / Duration.microsecondsPerMillisecond;

  /// 取走一次性正常或作废结果。
  @override
  LottoResult? takeResult() {
    final value = _result;
    _result = null;
    return value;
  }
}
