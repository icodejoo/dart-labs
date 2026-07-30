import 'dart:async';

import 'package:videoman/src/core/api.dart';
import 'package:videoman/src/core/bus/bus.dart';
import 'package:videoman/src/core/events/events.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/model/quality.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/state/progress.dart';
import 'package:videoman/src/core/state/state.dart';
import 'package:videoman/src/core/state/ui_state.dart';

/// A test double for [VmApi] that records every capability call it receives
/// and lets tests push arbitrary state/events into its streams.
///
/// Used across the test suite (this task and later ones) as the single
/// shared fake API implementation — its public surface is depended on
/// verbatim by later tasks, so it is not to be extended casually.
///
/// [VmApi] 的测试替身：记录收到的每次能力调用，并允许测试向其流中主动推送
/// 状态/事件。
///
/// 在整个测试套件中（本任务及后续任务）作为唯一共享的假 API 实现——其公开
/// 面被后续任务逐字依赖，不应随意扩充。
class FakeVmApi implements VmApi {
  /// Creates a fake API seeded with [options] and default state/UI-state
  /// snapshots.
  ///
  /// 创建一个假 API，用 [options] 及默认状态/UI 状态快照进行初始化。
  FakeVmApi({this.options = const VmOptions()});

  /// The configuration passed at construction time.
  ///
  /// 构造时传入的配置。
  @override
  final VmOptions options;

  /// Backing bus for [state]/[states]; replays the current snapshot to new
  /// subscribers.
  ///
  /// [state]/[states] 的底层总线；向新订阅者重放当前快照。
  final VmBus<VmState> _state = VmBus<VmState>(const VmState());

  /// Backing bus for [uiState]/[uiStates]; replays the current snapshot to
  /// new subscribers.
  ///
  /// [uiState]/[uiStates] 的底层总线；向新订阅者重放当前快照。
  final VmBus<VmUiState> _uiState = VmBus<VmUiState>(const VmUiState());

  /// Backing controller for [progress]; no replay, matches production
  /// semantics of a throttled tick stream.
  ///
  /// [progress] 的底层控制器；不重放，符合生产环境节流 tick 流的语义。
  final StreamController<VmProgress> _progress = StreamController<VmProgress>.broadcast();

  /// Backing controller for [events]; no replay, matches production
  /// semantics of a discrete event stream.
  ///
  /// [events] 的底层控制器；不重放，符合生产环境离散事件流的语义。
  final StreamController<VmEvent> _events = StreamController<VmEvent>.broadcast();

  /// The ordered list of capability method names invoked on this fake,
  /// e.g. `['play', 'seek']`.
  ///
  /// 在该假对象上被调用的能力方法名有序列表，例如 `['play', 'seek']`。
  final List<String> calls = <String>[];

  /// The argument of the most recent [seek] call, or `null` if never called.
  ///
  /// 最近一次 [seek] 调用的参数；若从未调用过则为 `null`。
  Duration? lastSeek;

  /// The argument of the most recent [setVolume] call, or `null` if never
  /// called.
  ///
  /// 最近一次 [setVolume] 调用的参数；若从未调用过则为 `null`。
  double? lastVolume;

  /// The argument of the most recent [setBrightness] call, or `null` if
  /// never called.
  ///
  /// 最近一次 [setBrightness] 调用的参数；若从未调用过则为 `null`。
  double? lastBrightness;

  /// The argument of the most recent [setRate] call, or `null` if never
  /// called.
  ///
  /// 最近一次 [setRate] 调用的参数；若从未调用过则为 `null`。
  double? lastRate;

  /// The argument of the most recent [setZoom] call, or `null` if never
  /// called.
  ///
  /// 最近一次 [setZoom] 调用的参数；若从未调用过则为 `null`。
  double? lastZoom;

  /// The argument of the most recent [setFit] call, or `null` if never
  /// called.
  ///
  /// 最近一次 [setFit] 调用的参数；若从未调用过则为 `null`。
  VmFit? lastFit;

  /// The argument of the most recent [setLocked] call, or `null` if never
  /// called.
  ///
  /// 最近一次 [setLocked] 调用的参数；若从未调用过则为 `null`。
  bool? lastLocked;

  /// The argument of the most recent [setFullscreen] call, or `null` if
  /// never called.
  ///
  /// 最近一次 [setFullscreen] 调用的参数；若从未调用过则为 `null`。
  bool? lastFullscreen;

  /// The argument of the most recent [switchQuality] call, or `null` if
  /// never called.
  ///
  /// 最近一次 [switchQuality] 调用的参数；若从未调用过则为 `null`。
  VmQuality? lastQuality;

  /// The `v` argument of the most recent [setDragging] call, or `null` if
  /// never called.
  ///
  /// 最近一次 [setDragging] 调用的 `v` 参数；若从未调用过则为 `null`。
  bool? lastDragging;

  /// The `previewAt` argument of the most recent [setDragging] call, or
  /// `null` if never called (or if that call passed `null`).
  ///
  /// 最近一次 [setDragging] 调用的 `previewAt` 参数；若从未调用过（或该次
  /// 调用传的就是 `null`）则为 `null`。
  Duration? lastPreviewAt;

  /// The argument of the most recent [showHud] call, or `null` if never
  /// called.
  ///
  /// 最近一次 [showHud] 调用的参数；若从未调用过则为 `null`。
  VmHud? lastHud;

  /// The value [enterPip] returns; settable by tests, defaults to `true`.
  ///
  /// [enterPip] 的返回值；可由测试赋值，默认为 `true`。
  bool pipSupported = true;

  /// A fake render handle exposed to widgets under test; `null` by default,
  /// in which case `VmPlayer` renders a placeholder instead of a real
  /// video surface.
  ///
  /// 供被测组件使用的假渲染句柄；默认 `null`，此时 `VmPlayer` 渲染占位符
  /// 而非真实视频画面。
  Object? renderHandle;

  @override
  Stream<VmEvent> get events => _events.stream;

  @override
  Stream<VmState> get states => _state.stream;

  @override
  Stream<VmProgress> get progress => _progress.stream;

  @override
  Stream<VmUiState> get uiStates => _uiState.stream;

  @override
  VmState get state => _state.value;

  @override
  VmUiState get uiState => _uiState.value;

  /// The source currently "open" on this fake; drives [sourceTitle].
  ///
  /// Set automatically by [open] from its `source` argument, so tests that
  /// call `open()` see [sourceTitle] reflect it immediately. Also settable
  /// directly by widget tests that never call [open] and just want to seed
  /// a title.
  ///
  /// 该假对象当前"已打开"的源；驱动 [sourceTitle]。
  ///
  /// 由 [open] 根据其 `source` 参数自动设置，因此调用 `open()` 的测试能
  /// 立即在 [sourceTitle] 上看到反映；也可由从不调用 [open] 、只想直接
  /// 塞入标题的组件测试直接赋值。
  VmSource? source;

  @override
  String? get sourceTitle => source?.title;

  /// Pushes a new state snapshot, visible immediately via [state] and to
  /// any current/future [states] subscribers.
  ///
  /// 推送一个新的状态快照，[state] 及所有当前/未来的 [states] 订阅者立即
  /// 可见。
  void push(VmState next) => _state.emit(next);

  /// Pushes a new UI state snapshot, visible immediately via [uiState] and
  /// to any current/future [uiStates] subscribers.
  ///
  /// 推送一个新的 UI 状态快照，[uiState] 及所有当前/未来的 [uiStates]
  /// 订阅者立即可见。
  void pushUi(VmUiState next) => _uiState.emit(next);

  /// Pushes a progress tick to [progress] subscribers.
  ///
  /// 向 [progress] 订阅者推送一次进度 tick。
  void pushProgress(VmProgress next) => _progress.add(next);

  /// Pushes a discrete event to [events] subscribers.
  ///
  /// 向 [events] 订阅者推送一个离散事件。
  void pushEvent(VmEvent next) => _events.add(next);

  @override
  Future<void> open(VmSource source, {bool autoPlay = true}) async {
    calls.add('open');
    this.source = source;
  }

  @override
  Future<void> play() async {
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> playOrPause() async {
    calls.add('playOrPause');
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek');
    lastSeek = to;
  }

  @override
  Future<void> seekBy(Duration delta) async {
    calls.add('seekBy');
  }

  @override
  Future<void> setVolume(double v) async {
    calls.add('setVolume');
    lastVolume = v;
  }

  @override
  Future<void> setBrightness(double v) async {
    calls.add('setBrightness');
    lastBrightness = v;
  }

  @override
  Future<void> setRate(double r) async {
    calls.add('setRate');
    lastRate = r;
  }

  @override
  Future<void> setFit(VmFit f) async {
    calls.add('setFit');
    lastFit = f;
  }

  @override
  Future<void> setZoom(double z) async {
    calls.add('setZoom');
    lastZoom = z;
  }

  @override
  Future<void> setLocked(bool v) async {
    calls.add('setLocked');
    lastLocked = v;
  }

  @override
  Future<void> setFullscreen(bool v) async {
    calls.add('setFullscreen');
    lastFullscreen = v;
  }

  @override
  Future<void> loadQualities() async {
    calls.add('loadQualities');
  }

  @override
  Future<void> switchQuality(VmQuality q) async {
    calls.add('switchQuality');
    lastQuality = q;
  }

  @override
  Future<bool> enterPip() async {
    calls.add('enterPip');
    return pipSupported;
  }

  @override
  Future<void> reload() async {
    calls.add('reload');
  }

  @override
  Future<void> backToLiveEdge() async {
    calls.add('backToLiveEdge');
  }

  @override
  void showControls({bool sticky = false}) {
    calls.add('showControls');
  }

  @override
  void hideControls() {
    calls.add('hideControls');
  }

  @override
  void showHud(VmHud hud) {
    calls.add('showHud');
    lastHud = hud;
  }

  @override
  void setDragging(bool v, {Duration? previewAt}) {
    calls.add('setDragging');
    lastDragging = v;
    lastPreviewAt = previewAt;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _progress.close();
    await _events.close();
    await _state.close();
    await _uiState.close();
  }
}
