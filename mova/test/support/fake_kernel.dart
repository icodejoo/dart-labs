import 'dart:async';
import 'dart:typed_data';

import 'package:mova/src/core/kernel/kernel.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';
import 'package:mova/src/core/keep_alive/keep_alive.dart';
import 'package:mova/src/core/report/stats_probe.dart';

/// A test double for [MovaKernel] that records every call it receives and lets
/// tests push arbitrary state into its streams.
///
/// Used across the test suite (this task and later ones) as the single
/// shared fake kernel implementation.
///
/// [MovaKernel] 的测试替身：记录收到的每次调用，并允许测试向其流中主动推送状态。
///
/// 在整个测试套件中（本任务及后续任务）作为唯一共享的假内核实现。
class FakeKernel implements MovaKernel {
  /// Creates a fake kernel.
  ///
  /// 创建一个假内核。
  ///
  /// - [renderHandle]: the handle this fake reports; defaults to a fresh
  ///   opaque object, pass `null` to emulate an audio-only kernel /
  ///   该假对象对外报告的句柄；默认是一个新建的不透明对象，传 `null` 可模拟
  ///   仅音频内核
  ///
  /// Example / 示例:
  /// ```dart
  /// final k = FakeKernel(renderHandle: null); // audio-only / 仅音频
  /// ```
  FakeKernel({Object? renderHandle = _unset})
      : _renderHandle = identical(renderHandle, _unset) ? Object() : renderHandle,
        _audioOnly = false;

  /// Creates a fake kernel emulating an audio-only one: no render handle and
  /// no screenshot, every other verb unchanged.
  ///
  /// 创建一个模拟仅音频形态的假内核：无渲染句柄、不支持截图，其余动词行为不变。
  ///
  /// Example / 示例:
  /// ```dart
  /// final engine = MovaEngine(kernel: FakeKernel.audioOnly());
  /// expect(engine.renderHandle, isNull);
  /// ```
  FakeKernel.audioOnly()
      : _renderHandle = null,
        _audioOnly = true;

  /// Whether this fake emulates an audio-only kernel.
  ///
  /// 该假对象是否在模拟仅音频内核。
  final bool _audioOnly;

  /// Sentinel marking "caller passed nothing", so that an explicit
  /// `renderHandle: null` stays null instead of being replaced by the default.
  ///
  /// 用于区分"调用者没传"的哨兵值，使显式传入的 `renderHandle: null` 保持为
  /// null，而不会被默认值顶替。
  static const Object _unset = Object();

  /// The stable handle this fake reports; stable identity matters because
  /// `_RenderSurface` keys itself by handle identity.
  ///
  /// 该假对象报告的稳定句柄；身份稳定很重要，因为 `_RenderSurface` 正是按句柄
  /// 身份做 key。
  final Object? _renderHandle;

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _buffering = StreamController<bool>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<Duration> _position = StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration = StreamController<Duration>.broadcast();
  final StreamController<Duration> _buffer = StreamController<Duration>.broadcast();
  final StreamController<MovaSize> _size = StreamController<MovaSize>.broadcast();
  final StreamController<Object> _error = StreamController<Object>.broadcast();

  /// The ordered list of method names invoked on this fake, e.g.
  /// `['open', 'play', 'seek']`.
  ///
  /// 在该假对象上被调用的方法名有序列表，例如 `['open', 'play', 'seek']`。
  final List<String> calls = <String>[];

  /// Whether [dispose] has run on this fake.
  ///
  /// 该假对象的 [dispose] 是否已执行。
  bool isDisposed = false;

  /// Every call this fake received after [dispose], in order; a correct engine
  /// leaves it empty.
  ///
  /// 该假对象在 [dispose] 之后收到的每次调用，按顺序；行为正确的引擎应让它保持为空。
  final List<String> callsAfterDispose = <String>[];

  /// When true, a call after [dispose] throws `AssertionError('has been disposed')`
  /// like a real media_kit `Player` does; off by default (the call is still
  /// recorded in [callsAfterDispose]).
  ///
  /// 为 true 时，[dispose] 之后的调用会像真实 media_kit `Player` 那样抛
  /// `AssertionError('has been disposed')`；默认关闭（调用仍会记入 [callsAfterDispose]）。
  bool throwWhenDisposed = false;

  /// Records [name] into [calls], and into [callsAfterDispose] (throwing when
  /// [throwWhenDisposed]) if the fake was already disposed.
  ///
  /// 把 [name] 记入 [calls]；若假对象已销毁，同时记入 [callsAfterDispose]
  /// （[throwWhenDisposed] 时抛出）。
  void recordCall(String name) {
    calls.add(name);
    if (!isDisposed) return;
    callsAfterDispose.add(name);
    if (throwWhenDisposed) throw AssertionError('[Player] has been disposed');
  }

  /// The position argument of the most recent [seek] call, or `null` if
  /// [seek] has never been called.
  ///
  /// 最近一次 [seek] 调用的位置参数；若从未调用过 [seek] 则为 `null`。
  Duration? lastSeek;

  /// The rate argument of the most recent [setRate] call, or `null` if
  /// [setRate] has never been called.
  ///
  /// 最近一次 [setRate] 调用的倍速参数；若从未调用过则为 `null`。
  double? lastRate;

  /// When true, [seek] answers by itself like mpv does: it echoes the target
  /// position, or [staleEcho] for each seek still counted by [dropNextSeeks].
  /// Off by default, so existing tests keep driving positions by hand.
  ///
  /// 为 true 时 [seek] 像 mpv 一样自行回声：回声目标位置；[dropNextSeeks] 尚未
  /// 用完的那几次 seek 则回声 [staleEcho]。默认关闭，既有测试仍手动推位置。
  bool echoSeeks = false;

  /// How many of the next seeks mpv "discards" (needs [echoSeeks]); each is
  /// recorded in [droppedSeeks] and echoes [staleEcho] instead of the target.
  ///
  /// 接下来有几次 seek 被 mpv"丢弃"（需开启 [echoSeeks]）；每次记入
  /// [droppedSeeks]，回声 [staleEcho] 而不是目标位置。
  int dropNextSeeks = 0;

  /// The stale position a discarded seek echoes (the ~23 ms seen on device).
  ///
  /// 被丢弃的 seek 回声的旧位置（真机上见到的约 23 ms）。
  Duration staleEcho = const Duration(milliseconds: 23);

  /// Targets of the seeks the fake discarded, in order.
  ///
  /// 假内核丢弃掉的 seek 目标，按顺序。
  final List<Duration> droppedSeeks = <Duration>[];

  /// Targets of the seeks the fake accepted while [echoSeeks] was on, in order.
  ///
  /// 开启 [echoSeeks] 期间假内核接受的 seek 目标，按顺序。
  final List<Duration> honoredSeeks = <Duration>[];

  /// The URI argument of the most recent [open] call, or `null` if [open]
  /// has never been called.
  ///
  /// 最近一次 [open] 调用的 URI 参数；若从未调用过 [open] 则为 `null`。
  String? lastUri;

  /// The `play` argument of the most recent [open] call, or `null` if
  /// [open] has never been called.
  ///
  /// 最近一次 [open] 调用的 `play` 参数；若从未调用过 [open] 则为 `null`。
  bool? lastPlay;

  /// The bytes returned by [screenshot]; settable by tests, defaults to
  /// `null`.
  ///
  /// [screenshot] 返回的字节数据；可由测试赋值，默认为 `null`。
  Uint8List? fakeShot;

  /// When non-null, [open] records its call and then waits for this completer,
  /// simulating a kernel load that is still in flight.
  ///
  /// 非空时，[open] 先记录调用再等待该 completer，用来模拟内核加载仍在途。
  Completer<void>? openGate;

  /// When non-null, [open] records its call and then throws this object,
  /// simulating a kernel that cannot load the address.
  ///
  /// 非空时，[open] 先记录调用再抛出该对象，用来模拟内核加载不了该地址。
  Object? openError;

  /// The URI of every [open] call, in order.
  ///
  /// 每次 [open] 调用的 URI，按调用顺序。
  final List<String> openedUris = <String>[];

  @override
  Future<void> open(String uri, {bool play = true}) async {
    recordCall('open');
    lastUri = uri;
    lastPlay = play;
    openedUris.add(uri);
    final gate = openGate;
    if (gate != null) await gate.future;
    final err = openError;
    if (err != null) throw err;
  }

  @override
  Future<void> play() async {
    recordCall('play');
  }

  @override
  Future<void> pause() async {
    recordCall('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    recordCall('seek');
    lastSeek = position;
    if (!echoSeeks) return;
    // Real mpv: an accepted seek echoes the target as `time-pos`; a discarded
    // one (HLS variant reload, RESTART near 23 ms) only echoes the old spot.
    //
    // 真实 mpv：被接受的 seek 会把目标值当 `time-pos` 回声；被丢弃的只会回声旧位置
    // （HLS 档位重载、RESTART 后约 23 ms 处）。
    final dropped = dropNextSeeks > 0;
    if (dropped) {
      dropNextSeeks--;
      droppedSeeks.add(position);
    } else {
      honoredSeeks.add(position);
    }
    final echo = dropped ? staleEcho : position;
    scheduleMicrotask(() {
      if (!_position.isClosed) _position.add(echo);
    });
  }

  @override
  Future<void> setVolume(double volume) async {
    recordCall('setVolume');
  }

  @override
  Future<void> setRate(double rate) async {
    recordCall('setRate');
    lastRate = rate;
  }

  @override
  Future<Uint8List?> screenshot() async {
    recordCall('screenshot');
    return _audioOnly ? null : fakeShot;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    isDisposed = true;
    await _playing.close();
    await _buffering.close();
    await _completed.close();
    await _position.close();
    await _duration.close();
    await _buffer.close();
    await _size.close();
    await _error.close();
  }

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<bool> get buffering => _buffering.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<Duration> get buffer => _buffer.stream;

  @override
  Stream<MovaSize> get size => _size.stream;

  @override
  Stream<Object> get error => _error.stream;

  @override
  Object? get renderHandle => _renderHandle;

  /// Pushes a playing/paused state into [playing].
  ///
  /// 向 [playing] 推送一个播放/暂停状态。
  void emitPlaying(bool value) => _playing.add(value);

  /// Pushes a buffering state into [buffering].
  ///
  /// 向 [buffering] 推送一个缓冲状态。
  void emitBuffering(bool value) => _buffering.add(value);

  /// Pushes a completed state into [completed].
  ///
  /// 向 [completed] 推送一个播放完成状态。
  void emitCompleted(bool value) => _completed.add(value);

  /// Pushes a position into [position].
  ///
  /// 向 [position] 推送一个播放进度。
  void emitPosition(Duration value) => _position.add(value);

  /// Pushes a duration into [duration].
  ///
  /// 向 [duration] 推送一个总时长。
  void emitDuration(Duration value) => _duration.add(value);

  /// Pushes a buffered position into [buffer].
  ///
  /// 向 [buffer] 推送一个已缓冲进度。
  void emitBuffer(Duration value) => _buffer.add(value);

  /// Pushes a video frame size into [size].
  ///
  /// 向 [size] 推送一个视频帧尺寸。
  void emitSize(int width, int height) => _size.add(MovaSize(width: width, height: height));

  /// Pushes an error into [error].
  ///
  /// 向 [error] 推送一个错误。
  void emitError(Object value) => _error.add(value);
}

/// Shared [MovaStatsProbe] test-double state — the four backing
/// `StreamController`s, their "ever listened to" flags, and `sample()`'s
/// settable result — factored out so [FakeStatsProbe] (standalone) and
/// [FakeStatsKernel] (mixed into [FakeKernel]) don't each carry their own
/// copy that has to stay in sync by hand.
///
/// [MovaStatsProbe] 测试替身的共享状态——四个底层 `StreamController`、各自的
/// "是否曾被监听"标记、以及 `sample()` 的可设置返回值——抽出来共用，这样
/// [FakeStatsProbe]（独立类）与 [FakeStatsKernel]（混入 [FakeKernel]）不用
/// 各自维护一份、靠手工保持同步。
mixin StatsProbeStub implements MovaStatsProbe {
  /// Constructs the controllers' `onListen` hooks. Mixins can't have their
  /// own constructor body, so this must be called once by each user (both
  /// current users do it as their first constructor-body statement).
  ///
  /// 挂上各控制器的 `onListen` 钩子。mixin 不能有自己的构造函数体，所以每个
  /// 使用方必须自行调用一次（当前两个使用方都在自己构造函数体的第一句调用）。
  void initStatsProbeStub() {
    stallingController.onListen = () => stallingSubscribed = true;
    logsController.onListen = () => logsSubscribed = true;
    restartsController.onListen = () => playbackRestartsSubscribed = true;
    endFilesController.onListen = () => endFilesSubscribed = true;
  }

  /// Backing value for [nativeRestartAvailable]; flip in a test to simulate the
  /// native RESTART subscription being live.
  ///
  /// [nativeRestartAvailable] 的底层值；测试里改它来模拟原生 RESTART 订阅已生效。
  @override
  bool nativeRestartAvailable = false;

  /// Backing controller for [stalling]; push via `add`.
  ///
  /// [stalling] 的底层控制器；用 `add` 推送。
  final StreamController<bool> stallingController = StreamController<bool>.broadcast();

  /// Backing controller for [logs]; push via `add`.
  ///
  /// [logs] 的底层控制器；用 `add` 推送。
  final StreamController<MovaLogLine> logsController = StreamController<MovaLogLine>.broadcast();

  /// Backing controller for [playbackRestarts]; push via `add`.
  ///
  /// [playbackRestarts] 的底层控制器；用 `add` 推送。
  final StreamController<void> restartsController = StreamController<void>.broadcast();

  /// Backing controller for [endFiles]; push via `add`.
  ///
  /// [endFiles] 的底层控制器；用 `add` 推送。
  final StreamController<MovaEndFileReason> endFilesController = StreamController<MovaEndFileReason>.broadcast();

  /// Whether [stalling] has ever been listened to.
  ///
  /// [stalling] 是否曾被监听过。
  bool stallingSubscribed = false;

  /// Whether [logs] has ever been listened to.
  ///
  /// [logs] 是否曾被监听过。
  bool logsSubscribed = false;

  /// Whether [playbackRestarts] has ever been listened to.
  ///
  /// [playbackRestarts] 是否曾被监听过。
  bool playbackRestartsSubscribed = false;

  /// Whether [endFiles] has ever been listened to.
  ///
  /// [endFiles] 是否曾被监听过。
  bool endFilesSubscribed = false;

  /// The value [sample] resolves to; settable by tests, defaults to `null`.
  ///
  /// [sample] 的返回值；可由测试赋值，默认 `null`。
  MovaStatsSnapshot? sampleResult;

  @override
  Stream<bool> get stalling => stallingController.stream;

  @override
  Stream<MovaLogLine> get logs => logsController.stream;

  @override
  Stream<void> get playbackRestarts => restartsController.stream;

  @override
  Stream<MovaEndFileReason> get endFiles => endFilesController.stream;

  @override
  Future<MovaStatsSnapshot?> sample() async => sampleResult;

  /// Closes all four backing controllers; call from the user's own
  /// `dispose()`/teardown.
  ///
  /// 关闭全部四个底层控制器；从使用方自己的 `dispose()`/收尾逻辑里调用。
  Future<void> disposeStatsProbeStub() async {
    await stallingController.close();
    await logsController.close();
    await restartsController.close();
    await endFilesController.close();
  }
}

/// A [FakeKernel] that also implements [MovaStatsProbe] — the shape
/// `MovaMpvKernel` has in production — so QoE-layer engine tests can drive
/// `stalling`/`logs`/`sample()` without a real mpv instance.
///
/// 同时实现 [MovaStatsProbe] 的 [FakeKernel]——与生产环境的 `MovaMpvKernel`
/// 同构——使 QoE 层的 engine 测试无需真实 mpv 实例即可驱动
/// `stalling`/`logs`/`sample()`。
class FakeStatsKernel extends FakeKernel with StatsProbeStub {
  FakeStatsKernel() {
    initStatsProbeStub();
  }

  /// Pushes a stalling observation.
  ///
  /// 推送一次卡顿观测。
  void emitStalling(bool value) => stallingController.add(value);

  /// Pushes a log line.
  ///
  /// 推送一条日志行。
  void emitLog(MovaLogLine line) => logsController.add(line);

  /// Pushes a native `MPV_EVENT_PLAYBACK_RESTART` observation.
  ///
  /// 推送一次原生 `MPV_EVENT_PLAYBACK_RESTART` 观测。
  void emitRestart() => restartsController.add(null);

  /// Pushes a native `MPV_EVENT_END_FILE` reason.
  ///
  /// 推送一次原生 `MPV_EVENT_END_FILE` 原因。
  void emitEndFile(MovaEndFileReason reason) => endFilesController.add(reason);

  @override
  Future<void> dispose() async {
    await disposeStatsProbeStub();
    await super.dispose();
  }
}

/// Scriptable [MovaKeepAliveKernel] behavior shared by the keepAlive fakes;
/// records `inspectKeepAlive`/`enterKeepAlive:<mode>`/`exitKeepAlive` into [calls].
///
/// 待机假内核共享的可编程行为；把 `inspectKeepAlive`/`enterKeepAlive:<mode>`/`exitKeepAlive` 记进 [calls]。
mixin KeepAliveKernelStub on FakeKernel implements MovaKeepAliveKernel {
  /// What [inspectKeepAlive] reports; settable by tests.
  ///
  /// [inspectKeepAlive] 报告的事实；可由测试赋值。
  MovaKeepAliveMedia media = const MovaKeepAliveMedia(audio: MovaAudioPresence.present, format: 'flv');

  /// What [enterKeepAlive] returns; false simulates a failed property write.
  ///
  /// [enterKeepAlive] 的返回值；false 模拟属性写入失败。
  bool enterResult = true;

  /// Whether [exitKeepAlive] reports that video decoding restarted (muted holds only).
  ///
  /// [exitKeepAlive] 是否报告视频解码重启了（仅 muted 待机）。
  bool exitRestartsVideo = true;

  /// The mode currently held, or null.
  ///
  /// 当前持有的待机组合；没有则为 null。
  MovaKeepAliveMode? heldMode;

  /// What the kernel pushes by itself after a muted hold wakes. The default,
  /// [FakeWakeSignal.none], is what Android and Windows really do: `vid` flips
  /// back and video decodes again, yet neither a size change nor a native
  /// RESTART follows (H42), so the resume gate can only end on its timeout.
  ///
  /// 静音待机唤醒后内核自己会推什么。默认 [FakeWakeSignal.none] 就是 Android 与
  /// Windows 的真实行为：`vid` 切回、视频重新解码，但既没有尺寸变化也没有原生
  /// RESTART（H42），恢复闸门只能靠超时收尾。
  FakeWakeSignal wakeSignal = FakeWakeSignal.none;

  /// The size pushed when [wakeSignal] is [FakeWakeSignal.size].
  ///
  /// [wakeSignal] 为 [FakeWakeSignal.size] 时推送的尺寸。
  (int, int) wakeSize = (1280, 720);

  @override
  Future<MovaKeepAliveMedia> inspectKeepAlive() async {
    recordCall('inspectKeepAlive');
    return media;
  }

  @override
  Future<bool> enterKeepAlive(MovaKeepAliveMode mode) async {
    recordCall('enterKeepAlive:${mode.name}');
    if (enterResult) heldMode = mode;
    return enterResult;
  }

  @override
  Future<bool> exitKeepAlive() async {
    recordCall('exitKeepAlive');
    final was = heldMode;
    heldMode = null;
    final restarted = was == MovaKeepAliveMode.muted && exitRestartsVideo;
    if (restarted) _pushWakeSignal();
    return restarted;
  }

  void _pushWakeSignal() {
    final signal = wakeSignal;
    if (signal == FakeWakeSignal.none) return;
    scheduleMicrotask(() {
      if (signal == FakeWakeSignal.size) {
        if (!_size.isClosed) emitSize(wakeSize.$1, wakeSize.$2);
      } else {
        final Object self = this;
        if (self is FakeStatsKernel && !self.restartsController.isClosed) self.emitRestart();
      }
    });
  }
}

/// The signal a [KeepAliveKernelStub] pushes by itself right after a muted hold
/// wakes.
///
/// [KeepAliveKernelStub] 在静音待机唤醒后自行推送的信号。
enum FakeWakeSignal {
  /// Nothing at all (the real Android / Windows behavior).
  ///
  /// 什么都不推（Android / Windows 的真实行为）。
  none,

  /// A fresh `size` report (what a reopen — S13 — produces).
  ///
  /// 一次新的 `size` 上报（重开路径 S13 会产生的信号）。
  size,

  /// A native RESTART (needs a [FakeStatsKernel]).
  ///
  /// 一次原生 RESTART（需要 [FakeStatsKernel]）。
  restart,
}

/// A [FakeKernel] that also has the keepAlive capability.
///
/// 同时具备待机能力的 [FakeKernel]。
class FakeKeepAliveKernel extends FakeKernel with KeepAliveKernelStub {}

/// A [FakeStatsKernel] that also has the keepAlive capability.
///
/// 同时具备待机能力的 [FakeStatsKernel]。
class FakeKeepAliveStatsKernel extends FakeStatsKernel with KeepAliveKernelStub {}
