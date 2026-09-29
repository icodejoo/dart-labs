import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../report/stats_probe.dart';
import 'kernel.dart';

/// A [MovaKernel] implementation backed by media_kit's `Player`.
///
/// This is the one file in the core layer allowed to depend on
/// `package:media_kit`; every other file under `lib/src/core/` must stay
/// engine-agnostic. It also implements [MovaStatsProbe] — the QoE layer's
/// optional capability for libmpv's own statistics — since that
/// implementation can only live here too.
///
/// 基于 media_kit `Player` 实现的 [MovaKernel]。
///
/// 这是核心层中唯一允许依赖 `package:media_kit` 的文件；`lib/src/core/` 下
/// 其余所有文件都必须与具体引擎无关。它同时实现 [MovaStatsProbe]——QoE 层用来
/// 拿 libmpv 自身统计量的可选能力——因为这个实现同样只能落在这里。
class MovaMpvKernel implements MovaKernel, MovaStatsProbe {
  /// Creates the media_kit-backed kernel.
  ///
  /// [player] lets callers inject an existing `Player` (e.g. for testing or
  /// custom configuration); when omitted a new `Player()` is created.
  ///
  /// [audioOnly] skips creating the `VideoController` entirely. media_kit's
  /// `Player` already starts with mpv's `--vid=no` and it is *only*
  /// `VideoController.create()` that flips it back to `vid=auto`
  /// (media_kit 1.2.6, `player/native/player/real.dart` `_create()` and
  /// `video_controller/native_video_controller/real.dart`), so not attaching
  /// one leaves libmpv decoding audio and nothing else: no decoded frame
  /// buffers, no GPU texture, no Flutter `Texture` registration. Those three
  /// are the whole of the video-side memory cost, and in audio-only mode they
  /// are zero rather than merely smaller.
  ///
  /// 创建基于 media_kit 的内核。
  ///
  /// [player] 允许调用者注入一个已存在的 `Player`（如用于测试或自定义配置）；
  /// 省略时会创建一个新的 `Player()`。
  ///
  /// [audioOnly] 表示完全跳过 `VideoController` 的创建。media_kit 的 `Player`
  /// 一创建就是 mpv 的 `--vid=no`，**只有** `VideoController.create()` 会把它
  /// 改回 `vid=auto`（media_kit 1.2.6，见 `player/native/player/real.dart` 的
  /// `_create()` 与 `video_controller/native_video_controller/real.dart`），
  /// 因此不挂接它就等于让 libmpv 只解音频：没有解码帧缓冲、没有 GPU 纹理、
  /// 没有 Flutter `Texture` 注册。这三项就是视频侧内存开销的全部，在仅音频
  /// 模式下它们是 0，而不只是变小。
  ///
  /// 升级 media_kit 时须重验"默认 `--vid=no`"这一条。
  ///
  /// [observeQoeSignals] gates the extra native `paused-for-cache` property
  /// observation and the two `observeEvent` registrations ([playbackRestarts]/
  /// [endFiles]) — all three exist solely for the QoE layer. Callers that
  /// never configure a [MovaReporter] pass `false` so construction skips these
  /// FFI round-trips entirely, keeping the "no reporter → zero overhead"
  /// guarantee true at this layer too (previously it only held one level up,
  /// in [MovaQoeCollector]).
  ///
  /// [observeQoeSignals] 控制要不要做额外的原生 `paused-for-cache` 属性观察和
  /// 两个 `observeEvent` 注册（[playbackRestarts]/[endFiles]）——这三者全部
  /// 只服务 QoE 层。没有配置 [MovaReporter] 的调用方应传 `false`，让构造期
  /// 完全跳过这几次 FFI 往返，使"没有 reporter 就零开销"这条承诺在这一层
  /// 也成立（此前它只在上一层的 [MovaQoeCollector] 里成立）。
  MovaMpvKernel({Player? player, this.audioOnly = false, bool observeQoeSignals = true})
    : _player = player ?? Player() {
    if (!audioOnly) {
      _controller = VideoController(_player);
    }
    _widthSub = _player.stream.width.listen((w) {
      _lastWidth = w ?? 0;
      _widthSeen = true;
      _emitSize();
    });
    _heightSub = _player.stream.height.listen((h) {
      _lastHeight = h ?? 0;
      _heightSeen = true;
      _emitSize();
    });
    if (!observeQoeSignals) return;
    // Observe mpv's own `paused-for-cache` — the *real* rebuffer signal,
    // distinct from the `buffering` stream's merge of `core-idle` +
    // `paused-for-cache` (see MovaStatsProbe.stalling doc). Only real
    // NativePlayer instances (not web) support observeProperty; anything else
    // degrades `stalling` to an empty stream rather than throwing.
    //
    // 观察 mpv 自己的 `paused-for-cache`——真正的卡顿信号，区别于 `buffering`
    // 流把 `core-idle` 与 `paused-for-cache` 合并后的产物（见
    // MovaStatsProbe.stalling 文档）。只有真实的 NativePlayer（非 web）支持
    // observeProperty；其余平台把 `stalling` 降级为空流而非抛出。
    final native = _player.platform;
    if (native is NativePlayer) {
      // 保留这两个 Future——dispose() 必须等它们落地（无论成功与否）后才能
      // 销毁 _player，否则原生注册调用可能在 mpv 句柄已销毁之后才真正发生，
      // 构成原生层的 use-after-teardown 竞态（而非仅仅是 Dart 侧订阅泄漏）。
      _observeSetup = native
          .observeProperty('paused-for-cache', (value) async {
            if (_stallingController.isClosed) return;
            _stallingController.add(value == 'yes');
          })
          .catchError((_) {
            // 静默降级：这次会话就是没有原生卡顿信号，QoE 层退回旧的
            // `buffering` 判据，其余上报功能不受影响。
          })
          .then((_) => _observeNativeEvents(native));
    }
  }

  /// Tracks the constructor's async native-observer registration so
  /// [dispose] can wait for it to settle before tearing down [_player] —
  /// otherwise a `dispose()` called immediately after construction could let
  /// `observeProperty`/`observeEvent` register against an already-destroyed
  /// mpv handle. `null` on platforms without `NativePlayer` (nothing to wait
  /// for).
  ///
  /// 追踪构造期发起的原生观察者异步注册，好让 [dispose] 能在销毁 [_player]
  /// 之前等它落地——否则构造后立即 `dispose()` 可能让
  /// `observeProperty`/`observeEvent` 在 mpv 句柄已销毁后才真正注册。非
  /// `NativePlayer` 平台上为 `null`（无需等待）。
  Future<void>? _observeSetup;

  /// Subscribes to the two raw mpv events the QoE layer wants (2026-09-29
  /// architecture update, see
  /// `doc/plans/2026-09-29-telemetry-enhancement.md` "新架构决策"):
  /// `MPV_EVENT_PLAYBACK_RESTART` for a precise TTFF landing signal, and
  /// `MPV_EVENT_END_FILE` for the native session-end reason. `observeEvent`
  /// is new media_kit API (only on the pinned git commit, not any published
  /// version) whose runtime behavior outside the one platform it was spiked
  /// on (Windows) is unverified — each subscription is wrapped so a failure
  /// degrades silently to an empty stream instead of crashing the kernel or
  /// affecting any other reporting.
  ///
  /// 订阅 QoE 层需要的两个原生 mpv 事件（2026-09-29 架构更新，见
  /// `doc/plans/2026-09-29-telemetry-enhancement.md`"新架构决策"）：
  /// `MPV_EVENT_PLAYBACK_RESTART` 提供精确的 TTFF 落地信号，
  /// `MPV_EVENT_END_FILE` 提供原生的会话结束原因。`observeEvent` 是 media_kit
  /// 新增的 API（只在锁定的 git 提交上有，任何已发布版本都没有），除了做过 spike
  /// 的那一个平台（Windows）外，其余平台的运行时行为未经验证——每个订阅都单独包了
  /// 一层，失败时静默降级为空流，不会让内核崩溃、也不影响其余上报功能。
  Future<void> _observeNativeEvents(NativePlayer native) async {
    try {
      await native.observeEvent(
        generated.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART,
        (event) async {
          if (_restartController.isClosed) return;
          _restartController.add(null);
        },
      );
    } on Object {
      // 静默降级：这次会话就是没有原生 TTFF 落地信号，QoE 层退回
      // `buffering` 边沿的启发式判定，其余上报功能不受影响。
    }
    try {
      await native.observeEvent(
        generated.mpv_event_id.MPV_EVENT_END_FILE,
        (event) async {
          if (_endFileController.isClosed) return;
          final data = event.ref.data;
          if (data == nullptr) return;
          final reason = _mapEndFileReason(data.cast<generated.mpv_event_end_file>().ref.reason);
          if (reason != null) _endFileController.add(reason);
        },
      );
    } on Object {
      // 静默降级：会话结束原因退回旧的时序推断，其余上报功能不受影响。
    }
  }

  /// Maps mpv's own `mpv_end_file_reason` to [MovaEndFileReason]; `eof` and
  /// any future/unknown values map to `null` (media_kit's `--keep-open=yes`
  /// makes a native `eof` reason unreachable in practice; see
  /// [MovaEndFileReason]'s doc for why that branch is intentionally absent).
  ///
  /// 把 mpv 自己的 `mpv_end_file_reason` 映射到 [MovaEndFileReason]；`eof`
  /// 与任何未来/未知取值一律映射为 `null`（media_kit 的 `--keep-open=yes`
  /// 使原生 `eof` 原因在实践中不可达；原因见 [MovaEndFileReason] 文档）。
  static MovaEndFileReason? _mapEndFileReason(int reason) {
    switch (reason) {
      case generated.mpv_end_file_reason.MPV_END_FILE_REASON_STOP:
        return MovaEndFileReason.stop;
      case generated.mpv_end_file_reason.MPV_END_FILE_REASON_QUIT:
        return MovaEndFileReason.quit;
      case generated.mpv_end_file_reason.MPV_END_FILE_REASON_ERROR:
        return MovaEndFileReason.error;
      case generated.mpv_end_file_reason.MPV_END_FILE_REASON_REDIRECT:
        return MovaEndFileReason.redirect;
      default:
        return null;
    }
  }

  /// One-time global media_kit init; call before creating any [MovaMpvKernel].
  ///
  /// 全局一次性 media_kit 初始化；创建任何 [MovaMpvKernel] 前调用。
  static void ensureInitialized() => MediaKit.ensureInitialized();

  /// The wrapped media_kit player instance.
  ///
  /// 被包裹的 media_kit 播放器实例。
  final Player _player;

  /// Whether this kernel was built without a video pipeline.
  ///
  /// 该内核是否在不带视频管线的形态下构造。
  final bool audioOnly;

  /// The video controller used to attach this kernel to a video widget;
  /// `null` when [audioOnly].
  ///
  /// 用于把该内核挂接到视频组件上的控制器；[audioOnly] 时为 `null`。
  VideoController? _controller;

  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;

  /// The most recently observed frame width; seeded to 0 until the first
  /// callback arrives.
  ///
  /// 最近观测到的帧宽度；首次回调到达前为 0。
  int _lastWidth = 0;

  /// The most recently observed frame height; seeded to 0 until the first
  /// callback arrives.
  ///
  /// 最近观测到的帧高度；首次回调到达前为 0。
  int _lastHeight = 0;

  /// Whether the width stream has delivered at least one value yet.
  ///
  /// 宽度流是否已至少推送过一次值。
  bool _widthSeen = false;

  /// Whether the height stream has delivered at least one value yet.
  ///
  /// 高度流是否已至少推送过一次值。
  bool _heightSeen = false;

  final StreamController<MovaSize> _sizeController = StreamController<MovaSize>.broadcast();

  /// Backing controller for [stalling]; fed from mpv's `paused-for-cache`.
  ///
  /// [stalling] 的底层控制器；由 mpv 的 `paused-for-cache` 驱动。
  final StreamController<bool> _stallingController = StreamController<bool>.broadcast();

  /// Backing controller for [playbackRestarts]; fed from
  /// `MPV_EVENT_PLAYBACK_RESTART`.
  ///
  /// [playbackRestarts] 的底层控制器；由 `MPV_EVENT_PLAYBACK_RESTART` 驱动。
  final StreamController<void> _restartController = StreamController<void>.broadcast();

  /// Backing controller for [endFiles]; fed from `MPV_EVENT_END_FILE`.
  ///
  /// [endFiles] 的底层控制器；由 `MPV_EVENT_END_FILE` 驱动。
  final StreamController<MovaEndFileReason> _endFileController =
      StreamController<MovaEndFileReason>.broadcast();

  /// Combines the latest cached width/height into a [MovaSize] and pushes it
  /// to listeners, but only once both dimensions have been observed at
  /// least once — this avoids emitting a bogus intermediate size (e.g.
  /// width-only) before media_kit has reported both.
  ///
  /// 将缓存的最新宽/高合并为 [MovaSize] 并推送给监听者；但只有当两个维度都已
  /// 被观测到至少一次时才会推送，以避免在 media_kit 尚未同时报告二者前推送
  /// 出错误的中间尺寸（如只有宽度）。
  void _emitSize() {
    if (!_widthSeen || !_heightSeen) return;
    _sizeController.add(MovaSize(width: _lastWidth, height: _lastHeight));
  }

  @override
  Future<void> open(String uri, {bool play = true}) => _player.open(Media(uri), play: play);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  /// Captures the current video frame as an encoded image, or `null` when
  /// there is no video pipeline to capture from.
  ///
  /// Short-circuiting here rather than letting mpv fail keeps the scrub-preview
  /// frame-extraction fallback (`MovaPreviewSource`) on its documented
  /// "extractor returned nothing → degrade gracefully" path instead of
  /// surfacing an mpv error to the host.
  ///
  /// 截取当前视频帧并编码为图片；没有视频管线可截时返回 `null`。
  ///
  /// 在此短路而不是让 mpv 自己失败，可以让拖动预览的抽帧兜底
  /// （`MovaPreviewSource`）走它既有的"抽帧器没给结果 → 平滑降级"路径，而不是把
  /// 一个 mpv 错误抛给宿主。
  @override
  Future<Uint8List?> screenshot() async =>
      audioOnly ? null : _player.screenshot(format: 'image/jpeg');

  @override
  Future<void> dispose() async {
    await _widthSub?.cancel();
    await _heightSub?.cancel();
    await _sizeController.close();
    await _stallingController.close();
    await _restartController.close();
    await _endFileController.close();
    // 必须等构造期发起的原生观察者注册落地，才能销毁 _player——见
    // _observeSetup 的文档注释。
    await _observeSetup;
    await _player.dispose();
  }

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get buffering => _player.stream.buffering;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<Duration> get buffer => _player.stream.buffer;

  @override
  Stream<MovaSize> get size => _sizeController.stream;

  @override
  Stream<Object> get error => _player.stream.error;

  @override
  Object? get renderHandle => _controller;

  // ---------------------------------------------------------------------
  // MovaStatsProbe — QoE layer's optional window into libmpv's own stats.
  // See doc/plans/2026-09-29-telemetry-enhancement.md Task 3 for why these
  // three members must live here rather than behind MovaKernel proper.
  //
  // MovaStatsProbe——QoE 层用来窥视 libmpv 自身统计量的可选窗口。这三个成员
  // 为何必须落在这里而非 MovaKernel 本体，见
  // doc/plans/2026-09-29-telemetry-enhancement.md Task 3。
  // ---------------------------------------------------------------------

  @override
  Stream<bool> get stalling => _stallingController.stream;

  @override
  Stream<void> get playbackRestarts => _restartController.stream;

  @override
  Stream<MovaEndFileReason> get endFiles => _endFileController.stream;

  @override
  Stream<MovaLogLine> get logs => _player.stream.log
      .where((l) => l.level == 'error')
      .map((l) => MovaLogLine(prefix: l.prefix, level: l.level, text: l.text));

  @override
  Future<MovaStatsSnapshot?> sample() async {
    // Video-side counters make no sense in audio-only mode; skip the
    // requests entirely rather than let mpv answer "unavailable" for each.
    // The seven properties are mutually independent, so fire them together
    // instead of paying seven sequential native round-trips.
    //
    // 仅音频模式下视频侧计数器毫无意义；直接跳过这些请求，而不是让 mpv 逐个
    // 回答"不可用"。这七个属性彼此独立，一起发起而不是付七次串行原生往返。
    final results = await Future.wait([
      audioOnly ? Future.value(null) : _tryIntProperty('video-bitrate'),
      audioOnly ? Future.value(null) : _tryIntProperty('frame-drop-count'),
      audioOnly ? Future.value(null) : _tryIntProperty('decoder-frame-drop-count'),
      _tryIntProperty('cache-speed'),
      audioOnly ? Future.value(null) : _tryStringProperty('hwdec-current'),
      _tryBoolProperty('demuxer-via-network'),
      _tryStringProperty('file-format'),
    ]);
    return MovaStatsSnapshot(
      videoBps: results[0] as int?,
      inputBps: results[3] as int?,
      voDrops: results[1] as int?,
      decoderDrops: results[2] as int?,
      hwdec: results[4] as String?,
      viaNetwork: results[5] as bool?,
      fileFormat: results[6] as String?,
    );
  }

  /// Reads [property] raw off the native player, swallowing any failure (mpv
  /// reports many properties as "unavailable" when there's no video/network)
  /// into `null`. Shared by [_tryIntProperty]/[_tryStringProperty]/
  /// [_tryBoolProperty] so the "not a NativePlayer / getProperty threw / empty
  /// string" guard lives in exactly one place.
  ///
  /// 从原生 player 读 [property] 的原始值，吞掉任何失败（无视频/网络时 mpv
  /// 会把不少属性报告为"不可用"），转成 `null`。被
  /// [_tryIntProperty]/[_tryStringProperty]/[_tryBoolProperty] 共用，让"不是
  /// NativePlayer / getProperty 抛出 / 空字符串"这条判空逻辑只写一处。
  Future<String?> _readNativeProperty(String property) async {
    try {
      final native = _player.platform;
      final raw = native is NativePlayer ? await native.getProperty(property) : null;
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } on Object {
      return null;
    }
  }

  /// Reads [property] as an int; see [_readNativeProperty].
  ///
  /// 把 [property] 读作 int；见 [_readNativeProperty]。
  Future<int?> _tryIntProperty(String property) async {
    final raw = await _readNativeProperty(property);
    return raw == null ? null : int.tryParse(raw);
  }

  /// Reads [property] as a string; see [_readNativeProperty].
  ///
  /// 把 [property] 读作字符串；见 [_readNativeProperty]。
  Future<String?> _tryStringProperty(String property) => _readNativeProperty(property);

  /// Reads [property] as a `yes`/`no` bool; see [_readNativeProperty].
  ///
  /// 把 [property] 读作 `yes`/`no` 布尔值；见 [_readNativeProperty]。
  Future<bool?> _tryBoolProperty(String property) async {
    final raw = await _readNativeProperty(property);
    if (raw == null) return null;
    return raw == 'yes';
  }
}
