import 'package:fake_async/fake_async.dart';
import 'package:mova/mova.dart';

import 'fake_kernel.dart';

/// A PiP port that always succeeds, to put the engine in system PiP.
///
/// 永远成功的画中画端口，用来让引擎进入系统画中画。
class YesPip implements MovaPipPort {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> enter({int? width, int? height}) async => true;
}

/// An engine over a fake kernel for keepAlive tests: the control bar's auto-hide
/// is off (the only timers left are keepAlive's own), the keepAlive clock follows
/// `fakeAsync`, and every event is recorded.
///
/// 待机测试用的"假内核 + 引擎"夹具：关掉控制条自动隐藏（剩余计时器只可能来自待机本身），
/// 待机时钟跟随 `fakeAsync`，并记录所有事件。
class KeepAliveRig {
  /// Creates the rig inside a `fakeAsync` zone.
  ///
  /// 在 `fakeAsync` 区域内创建夹具。
  ///
  /// - [async]: the surrounding fake clock / 外层的假时钟
  /// - [kernel]: the fake kernel to drive / 被驱动的假内核
  /// - [options]: base options; the controls section is overridden / 基础配置；控制条一节会被覆盖
  /// - [keepAlive]: replaces the keepAlive section when given / 给定时替换待机一节
  /// - [recovery]: replaces the recovery section when given / 给定时替换恢复一节
  /// - [pip]: an optional PiP port / 可选的画中画端口
  KeepAliveRig(
    this.async,
    this.kernel, {
    MovaOpts options = const MovaOpts(),
    MovaKeepAliveConfig? keepAlive,
    MovaRecoveryConfig? recovery,
    MovaPipPort? pip,
  }) : engine = MovaEngine(
         kernel: kernel,
         pip: pip,
         options: options.copyWith(
           keepAlive: keepAlive,
           recovery: recovery,
           controls: const MovaCtrlsConfig(autoHide: false),
         ),
       ) {
    final origin = DateTime(2026, 10, 24);
    engine.debugClock = () => origin.add(async.elapsed);
    engine.events.listen(events.add);
  }

  /// The surrounding fake clock.
  ///
  /// 外层的假时钟。
  final FakeAsync async;

  /// The fake kernel.
  ///
  /// 假内核。
  final FakeKernel kernel;

  /// The engine under test.
  ///
  /// 被测引擎。
  final MovaEngine engine;

  /// Every event the engine emitted, in order.
  ///
  /// 引擎发出的全部事件，按顺序。
  final List<MovaEvent> events = [];

  /// The keepAlive phase-change events.
  ///
  /// 待机阶段变化事件。
  List<MovaKeepAliveChange> get changes => events.whereType<MovaKeepAliveChange>().toList();

  /// The keepAlive resume events.
  ///
  /// 待机恢复事件。
  List<MovaKeepAliveResume> get resumes => events.whereType<MovaKeepAliveResume>().toList();

  /// The `(phase, reason)` pairs of [changes], for compact sequence checks.
  ///
  /// [changes] 的 `(阶段, 原因)` 对，便于紧凑地检查序列。
  List<String> get trail => changes.map((c) => '${c.phase.name}/${c.reason.name}').toList();

  /// Opens a live source and, when [autoPlay], reports the kernel as playing.
  ///
  /// 打开一条直播源，[autoPlay] 为真时让内核报告在播。
  void playLive({
    bool autoPlay = true,
    MovaStreamType type = MovaStreamType.live,
    String uri = 'https://h/a.flv',
  }) {
    engine.open(MovaSource(uri, type: type), autoPlay: autoPlay);
    async.flushMicrotasks();
    if (autoPlay) kernel.emitPlaying(true);
    async.flushMicrotasks();
  }

  /// Calls `setKeepAlive` and lets microtasks settle; returns the settled phase.
  ///
  /// 调用 `setKeepAlive` 并让微任务落定；返回落定后的阶段。
  MovaKeepAlivePhase? keepAlive(bool on) {
    MovaKeepAlivePhase? result;
    engine.setKeepAlive(on).then((p) => result = p);
    async.flushMicrotasks();
    return result;
  }

  /// Lets microtasks settle.
  ///
  /// 让微任务落定。
  void settle() => async.flushMicrotasks();

  /// Lands the first frame through the buffering falling edge (kernel without a
  /// native restart signal).
  ///
  /// 经 buffering 下降沿让首帧落地（内核没有原生 RESTART 信号时）。
  void land() {
    kernel.emitBuffering(true);
    kernel.emitBuffering(false);
    settle();
  }
}
