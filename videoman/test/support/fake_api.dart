import 'dart:async';

import 'package:videoman/src/core/api.dart';
import 'package:videoman/src/core/bus/bus.dart';
import 'package:videoman/src/core/events/events.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/model/orientation.dart';
import 'package:videoman/src/core/model/quality.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/preview/api.dart';
import 'package:videoman/src/core/preview/models.dart';
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
  final VmBus<VmState> _state = VmBus<VmState>(const VmState(pipSupported: true));

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

  /// The argument of the most recent [setOrientation] call, or `null` if
  /// never called.
  ///
  /// 最近一次 [setOrientation] 调用的参数；若从未调用过则为 `null`。
  VmOrientation? lastOrientation;

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

  /// The `hud` argument of the most recent [showHud] call, or `null` if
  /// never called.
  ///
  /// 最近一次 [showHud] 调用的 `hud` 参数；若从未调用过则为 `null`。
  VmHud? lastHud;

  /// The `text` argument of the most recent [showHud] call, or `null` if
  /// never called (or that call passed no text).
  ///
  /// 最近一次 [showHud] 调用的 `text` 参数；若从未调用过（或该次调用未传
  /// 文本）则为 `null`。
  String? lastHudText;

  /// Whether this fake reports pip support; mirrored into
  /// [VmState.pipSupported] so `..pipSupported = false` also flips what any
  /// `VmSelector` on state sees.
  ///
  /// 该假对象是否报告支持画中画；会镜像进 [VmState.pipSupported]，因此
  /// `..pipSupported = false` 同时也会翻转状态上任何 `VmSelector` 看到的值。
  @override
  bool get pipSupported => state.pipSupported;

  /// Sets [pipSupported] by pushing a new state snapshot.
  ///
  /// 通过推送新状态快照来设置 [pipSupported]。
  ///
  /// - [value]: whether pip is supported / 是否支持画中画
  set pipSupported(bool value) => push(state.copyWith(pipSupported: value));

  /// A fake render handle exposed to widgets under test; `null` by default,
  /// in which case `VmPlayer` renders a placeholder instead of a real
  /// video surface.
  ///
  /// 供被测组件使用的假渲染句柄；默认 `null`，此时 `VmPlayer` 渲染占位符
  /// 而非真实视频画面。
  @override
  Object? renderHandle;

  /// The preview test double this fake exposes.
  ///
  /// 该假对象暴露的预览测试替身。
  @override
  final FakePreviewApi preview = FakePreviewApi();

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

  /// The source currently "open" on this fake, recorded for tests that want
  /// to assert on it; also drives [VmState.sourceTitle] via [open], which
  /// pushes it into [state] the same way the real engine does.
  ///
  /// 该假对象当前"已打开"的源，供测试断言使用；也通过 [open] 驱动
  /// [VmState.sourceTitle]（与真实 engine 一样推入 [state]）。
  VmSource? source;

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
    push(state.copyWith(
      type: source.type,
      sourceTitle: source.title,
      clearSourceTitle: source.title == null,
    ));
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
  Future<void> setOrientation(VmOrientation o) async {
    calls.add('setOrientation');
    lastOrientation = o;
    push(state.copyWith(orientation: o));
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
  void showHud(VmHud hud, {String? text}) {
    calls.add('showHud');
    lastHud = hud;
    lastHudText = text;
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
    await preview.dispose();
  }
}

/// A test double for [VmPreviewApi] that records requests and lets tests push
/// thumbnails into the stream.
///
/// [VmPreviewApi] 的测试替身：记录请求，并允许测试向流中推送缩略图。
class FakePreviewApi implements VmPreviewApi {
  /// Backing controller for [thumbs].
  ///
  /// [thumbs] 的底层控制器。
  final StreamController<VmThumb?> _thumbs = StreamController<VmThumb?>.broadcast();

  /// Ordered method names invoked on this fake.
  ///
  /// 在该替身上被调用的方法名有序列表。
  final List<String> calls = <String>[];

  /// The argument of the most recent [requestAt] call.
  ///
  /// 最近一次 [requestAt] 调用的参数。
  Duration? lastRequestedAt;

  /// The value [peekAt] returns; settable by tests, defaults to null.
  ///
  /// [peekAt] 的返回值；可由测试赋值，默认 null。
  VmThumb? peekResult;

  /// The thumbnail most recently pushed via [push].
  ///
  /// 最近一次通过 [push] 推送的缩略图。
  VmThumb? _current;

  @override
  Stream<VmThumb?> get thumbs => _thumbs.stream;

  @override
  VmThumb? get current => _current;

  @override
  VmThumb? peekAt(Duration position) {
    calls.add('peekAt');
    return peekResult;
  }

  @override
  void requestAt(Duration position) {
    calls.add('requestAt');
    lastRequestedAt = position;
  }

  @override
  void cancel() => calls.add('cancel');

  @override
  Future<void> clear() async => calls.add('clear');

  /// Pushes [thumb] to [thumbs] and makes it the [current] value.
  ///
  /// 把 [thumb] 推送到 [thumbs] 并设为 [current]。
  ///
  /// - [thumb]: the thumbnail to publish, or null to hide / 要发布的缩略图，
  ///   null 表示隐藏
  void push(VmThumb? thumb) {
    _current = thumb;
    _thumbs.add(thumb);
  }

  /// Closes the backing stream.
  ///
  /// 关闭底层流。
  Future<void> dispose() => _thumbs.close();
}
