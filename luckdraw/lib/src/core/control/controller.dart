import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../foundation/duration_ms.dart';
import '../game/frame.dart';
import '../game/layout.dart';
import '../motion/clock.dart';
import '../motion/motion.dart';
import '../motion/phase.dart';
import '../motion/result.dart';
import '../motion/timeline.dart';
import '../picker/prize_picker.dart';

/// 控制器宿主，负责时间源与面向界面的事件。
abstract interface class LuckyControllerHost<R extends LuckyResult<Object?>> {
  /// 宿主拥有的时间源。
  LuckyClock get clock;

  /// 阶段变化。
  void handlePhaseChanged(LuckyPhase phase);

  /// 正常或作废结果。
  void handleResult(R result);

  /// 越过条目的列和下标。
  void handleItemPassed(int reel, int index);

  /// play 被接受。
  void handleStarted();
}

/// 通用命令与时间轴；玩法子类补充类型化 stop 和 playUntil。
///
/// 可以 attachHeadless 注入时钟；同一时刻最多挂接一个宿主。
abstract class LuckyController<C extends Object, L extends LuckyLayout,
    F extends LuckyFrame, R extends LuckyResult<Object?>> {
  /// 创建控制器；不传 [random] 时使用独立的随机源。
  LuckyController(
      {required this.motion,
      this.picker = const WeightedPrizePicker(),
      math.Random? random})
      : random = random ?? math.Random();

  /// 无下标停止时使用的策略。
  final PrizePicker picker;

  /// 选奖与停止偏移共用的随机源。
  final math.Random random;

  /// 玩法状态机。
  @protected
  final LuckyMotion<C, L, F, R> motion;

  /// 当前阶段通知器。
  final ValueNotifier<LuckyPhase> _phase = ValueNotifier(LuckyPhase.idle);

  /// 帧重绘通知器。
  final LuckyFrameNotifier _frames = LuckyFrameNotifier();

  /// 惰性阶段事件流。
  StreamController<LuckyPhase>? _stream;

  /// 有效时间轴。
  final LuckyTimeline _timeline = LuckyTimeline();

  /// 当前宿主。
  LuckyControllerHost<R>? _host;

  /// 最近一次结果。
  R? _lastResult;

  /// 等待本局结果的调用。
  Completer<R>? _pending;

  /// 达到最短时间后执行的停止命令。
  VoidCallback? _pendingStop;

  /// 等待停止的有效时间。
  double _stopAtMs = 0;

  /// 减速期间排队的最新结构配置与布局。
  ({C config, L? layout})? _queued;

  /// 是否已经释放。
  bool _disposed = false;

  /// 阶段通知期间重入的命令交由外层按最新阶段继续派发。
  bool _dispatchingPhase = false;

  /// 当前阶段，只读监听；例如 `controller.phase.value`。
  ValueListenable<LuckyPhase> get phase => _phase;

  /// 同步广播阶段变化；首次访问才创建流。
  Stream<LuckyPhase> get phaseChanges =>
      (_stream ??= StreamController<LuckyPhase>.broadcast(sync: true)).stream;

  /// 绘制监听器，稳态帧不触发 Widget 构建。
  Listenable get frameListenable => _frames;

  /// 复用的当前帧，不可由用户修改。
  F get frame => motion.frame;

  /// 最近一次正常或作废结果。
  R? get lastResult => _lastResult;

  /// 是否有宿主。
  bool get isAttached => _host != null;

  /// 用户暂停或生命周期暂停是否生效。
  bool get isPaused => _timeline.isPaused;

  /// 开始本局，运动中返回 false。
  bool play() {
    if (_disposed) return false;
    final started = motion.start();
    if (started) {
      _lastResult = null;
    }
    final accepted = commitCommand(started);
    if (accepted && !_disposed) {
      _host?.handleStarted();
    }
    return accepted;
  }

  /// 作废本局；减速阶段是否接受由玩法决定。
  bool cancel() {
    if (_disposed) return false;
    final fromIdle = motion.phase == LuckyPhase.idleSpinning;
    return commitCommand(motion.cancel(), fromIdle: fromIdle);
  }

  /// 开始待机慢转，返回是否接受。
  bool idleSpin() => !_disposed && commitCommand(motion.idleSpin());

  /// 用户暂停；只有运动且尚未用户暂停时接受。
  bool pause() {
    if (_disposed || !motion.phase.isMoving || _userPaused) return false;
    _userPaused = true;
    _timeline.pauseUser();
    _host?.clock.stop();
    return true;
  }

  /// 是否有用户暂停请求。
  bool _userPaused = false;

  /// 恢复用户暂停；生命周期暂停解除后才恢复时间源。
  bool resume() {
    if (_disposed || !_userPaused) return false;
    _userPaused = false;
    _timeline.resumeUser();
    _syncClock();
    return true;
  }

  /// 重置到原点；运动中（含待机慢转）按取消报告策略作废本局。
  void reset() {
    if (_disposed) return;
    final cancelled = motion.phase.isMoving;
    final fromIdle = motion.phase == LuckyPhase.idleSpinning;
    final pending = _pending;
    motion.reset();
    _timeline.resumeUser();
    _userPaused = false;
    _afterCommand(cancelled ? createCancelledResult() : null, pending,
        fromIdle: fromIdle);
  }

  /// 挂接宿主；已有宿主时抛出 StateError。
  void attach(LuckyControllerHost<R> host) {
    if (_disposed || _host != null) throw StateError('控制器已释放或已挂接宿主');
    _host = host;
    _syncClock();
  }

  /// 无头驱动；时钟归调用者所有，控制器只启停它。
  void attachHeadless(
      {required LuckyClock clock, required C config, L? layout}) {
    attach(_HeadlessHost<R>(clock));
    configure(config, layout);
  }

  /// 解除挂接并停止原宿主时钟；未决本局以作废结果完成。
  void detach() {
    _host?.clock.stop();
    _host = null;
    _timeline.rebase();
    _completePending(createCancelledResult());
  }

  /// 应用配置；减速中的结构变化排队，结算后应用最新一份。
  void configure(C config, L? layout, {bool structural = false}) {
    if (_disposed) return;
    if (_queued != null ||
        structural && motion.phase == LuckyPhase.decelerating) {
      _queued = (config: config, layout: layout);
    } else {
      motion.configure(config, layout);
      _afterConfigure();
    }
  }

  /// 应用配置后收尾：motion 在配置中取消本局时同步阶段、交付结果并完成未决调用。
  void _afterConfigure() {
    final result = motion.takeResult();
    if (result != null || _phase.value != motion.phase) {
      _afterCommand(result, _pending, fromIdle: false);
    } else {
      _syncClock();
    }
  }

  /// 生命周期暂停，与用户暂停独立。
  void pauseForLifecycle() {
    if (_disposed) return;
    _timeline.pauseLifecycle();
    _host?.clock.stop();
  }

  /// 解除生命周期暂停，用户仍暂停时保持停止。
  void resumeForLifecycle() {
    if (_disposed) return;
    _timeline.resumeLifecycle();
    _syncClock();
  }

  /// 子类执行类型化命令后调用，统一同步阶段、结果和时间源。
  ///
  /// [fromIdle] 表示命令发出时处于待机慢转，供取消上报策略判断。
  @protected
  bool commitCommand(bool accepted, {bool fromIdle = false}) {
    if (_disposed || !accepted) return false;
    _afterCommand(motion.takeResult(), _pending, fromIdle: fromIdle);
    return true;
  }

  /// 命令生效后的统一收尾：释放未决、同步阶段、交付结果、重绘并校准时钟。
  void _afterCommand(R? result, Completer<R>? pending,
      {required bool fromIdle}) {
    if (result != null) _releasePending(pending);
    _syncPhase();
    if (result != null) _finish(result, pending, fromIdle: fromIdle);
    if (!_disposed) _frames.notify();
    _syncClock();
  }

  /// play 后获取目标并等待最短有效时间，再应用停止命令。
  ///
  /// resolve 抛错会尝试作废并以该错误结束；dispose 会以作废结果结束。
  @protected
  Future<R> runPlayUntil<T>(FutureOr<T> Function() resolve, Duration minSpin,
      bool Function(T target) applyStop) {
    if (_disposed || _pending != null) {
      return Future<R>.error(StateError('当前不能开始抽奖'));
    }
    final pending = Completer<R>();
    _pending = pending;
    _stopAtMs = _timeline.nowMs + luckyMs(minSpin);
    if (!play()) {
      _pending = null;
      pending.completeError(StateError('当前不能开始抽奖'));
    } else if (identical(_pending, pending)) {
      unawaited(_resolveTarget(resolve, applyStop, pending));
    }
    return pending.future;
  }

  /// 获取异步目标；回调身份用于隔离已经结束的局次。
  Future<void> _resolveTarget<T>(FutureOr<T> Function() resolve,
      bool Function(T target) applyStop, Completer<R> pending) async {
    try {
      final target = await resolve();
      if (_disposed || !identical(_pending, pending)) return;
      _pendingStop = () {
        if (!applyStop(target)) {
          if (identical(_pending, pending)) {
            _completePending(createCancelledResult());
          }
        }
      };
      _applyPendingStop();
    } on Object catch (error, stack) {
      _failPending(pending, error, stack);
    }
  }

  /// 有效时间达到门限时取走待执行命令，防止重入重复执行。
  void _applyPendingStop() {
    if (_timeline.nowMs < _stopAtMs) return;
    final stop = _pendingStop;
    final pending = _pending;
    _pendingStop = null;
    try {
      stop?.call();
    } on Object catch (error, stack) {
      if (pending != null) _failPending(pending, error, stack);
    }
  }

  /// 停止或取目标抛错时仅结束所属局次，再作废其运动。
  void _failPending(Completer<R> pending, Object error, StackTrace stack) {
    if (!identical(_pending, pending)) return;
    _releasePending(pending);
    pending.completeError(error, stack);
    cancel();
  }

  /// 是否把作废结果交给宿主；上游老虎机覆写为 false。
  @protected
  bool get shouldReportCancelled => true;

  /// 待机慢转被取消或重置时是否上报作废结果；九宫格覆写为 false。
  @protected
  bool get reportsIdleCancellation => true;

  /// 子类提供类型化的作废结果。
  @protected
  R createCancelledResult();

  /// 同步阶段，只在变化时通知。
  void _syncPhase() {
    if (_disposed || _dispatchingPhase) return;
    _dispatchingPhase = true;
    try {
      while (!_disposed && _phase.value != motion.phase) {
        final phase = motion.phase;
        _phase.value = phase;
        if (_disposed) break;
        if (motion.phase != phase) continue;
        _host?.handlePhaseChanged(phase);
        if (_disposed) break;
        if (motion.phase != phase) continue;
        _stream?.add(phase);
      }
    } finally {
      _dispatchingPhase = false;
    }
  }

  /// 按当前运动与暂停状态启停时钟。
  void _syncClock() {
    final clock = _host?.clock;
    if (clock == null || _disposed) return;
    if ((motion.phase.isMoving || motion.isSimulating) && !_timeline.isPaused) {
      if (!clock.isTicking) {
        _timeline.rebase();
        clock.start(_onTick);
      }
    } else {
      clock.stop();
    }
  }

  /// 帧热路径只推进时间、更新快照和派发事件，不构造对象。
  void _onTick(Duration raw) {
    if (_disposed || _timeline.isPaused) return;
    _timeline.maxFrameDelta = motion.maxFrameDelta;
    _timeline.advance(raw);
    final events = motion.tick(_timeline.nowMs, _timeline.lastDeltaMs);
    if (_disposed) return;
    final pending = _pending;
    final result = motion.takeResult();
    if (result != null) _releasePending(pending);
    if (events & LuckyMotionEvents.repaint != 0) {
      _frames.notify();
    }
    if (!_disposed && events & LuckyMotionEvents.itemPassed != 0) {
      final host = _host;
      if (host != null) motion.drainPassed(host.handleItemPassed);
    }
    if (!_disposed && events & LuckyMotionEvents.phaseChanged != 0) {
      _syncPhase();
    }
    if (result != null) {
      _finish(result, pending);
    }
    if (_disposed) return;
    _applyPendingStop();
    _syncClock();
  }

  /// 保存结果、应用排队配置并完成本局。
  void _finish(R result, Completer<R>? pending, {bool fromIdle = false}) {
    _lastResult = result;
    final queued = _queued;
    if (queued != null) {
      _queued = null;
      motion.configure(queued.config, queued.layout);
    }
    pending?.complete(result);
    final reported = !result.cancelled ||
        shouldReportCancelled && (!fromIdle || reportsIdleCancellation);
    if (!_disposed && reported) _host?.handleResult(result);
  }

  /// 完成并清空未决调用。
  void _completePending(R result) {
    final pending = _pending;
    _releasePending(pending);
    pending?.complete(result);
  }

  /// 取走给定局次的待停命令，不触及回调中新建的局次。
  void _releasePending(Completer<R>? pending) {
    if (identical(_pending, pending)) {
      _pending = null;
      _pendingStop = null;
    }
  }

  /// 停止时钟、关闭通知并以作废结果结束未决 Future；不触发宿主回调。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    detach();
    // 监听者可在同步派发中 dispose，资源关闭必须等通知栈退出。
    scheduleMicrotask(() {
      _phase.dispose();
      _frames.dispose();
      final stream = _stream;
      if (stream != null) unawaited(stream.close());
    });
  }
}

/// 无头驱动的空回调宿主。
final class _HeadlessHost<R extends LuckyResult<Object?>>
    implements LuckyControllerHost<R> {
  /// 包装调用者拥有的时钟。
  _HeadlessHost(this.clock);

  /// 注入时钟。
  @override
  final LuckyClock clock;

  /// 无头驱动不处理阶段。
  @override
  void handlePhaseChanged(LuckyPhase phase) {}

  /// 无头驱动不处理结果。
  @override
  void handleResult(R result) {}

  /// 无头驱动不处理条目。
  @override
  void handleItemPassed(int reel, int index) {}

  /// 无头驱动不处理开始。
  @override
  void handleStarted() {}
}
