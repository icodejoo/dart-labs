import 'dart:async';
import 'dart:typed_data';

import 'package:media_kit/generated/libmpv/bindings.dart' as generated;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../report/stats_probe.dart';
import '../standby/standby.dart';
import 'kernel.dart';
import 'mpv_defaults.dart';
import 'mpv_event_backend.dart';
import 'mpv_event_pump.dart';
import 'mpv_keyvalue.dart';
import 'player_mute.dart';
import 'source_options_kernel.dart';
import 'standby_kernel.dart';

/// 弱客户端后端工厂函数定义。
typedef MovaMpvEventBackendFactory = MovaMpvEventBackend Function(NativePlayer native, int handleAddress);

/// 视频控制器工厂：为给定播放器创建 [VideoController]（测试可替换）。
typedef MovaVideoControllerFactory = VideoController Function(Player player);

/// 视频控制器就绪探针：完成即表示渲染面（render context/纹理）已可用（测试可替换）。
typedef MovaVideoReadyProbe = Future<void> Function(VideoController controller);

/// "让出一帧"钩子：完成即表示当前帧已结束（由平台层用 Flutter 调度器实现，core 不依赖 flutter）。
typedef MovaMountYield = Future<void> Function();

/// 等待渲染面就绪的最长时间，超时后不再阻塞 `open()`。
const Duration kVideoReadyTimeout = Duration(seconds: 3);

/// lazy 模式下 `open()` 等待"同帧挂载的视频组件"出现的最长时间（帧停摆时的兜底）。
const Duration kMountGrace = Duration(milliseconds: 250);

/// mpv 的视频轨选择属性名。
const String _kVid = 'vid';

/// 视频轨被关闭时 `vid` 的取值。
const String _kVidOff = 'no';

/// 让 mpv 自动选视频轨的取值。
const String _kVidAuto = 'auto';

/// A [MovaKernel] implementation backed by media_kit's `Player`.
///
/// This is the one file in the core layer allowed to depend on
/// `package:media_kit`; every other file under `lib/src/core/` must stay
/// engine-agnostic. It also implements [MovaStatsProbe] — the QoE layer's
/// optional capability for libmpv's own statistics — since that
/// implementation can only live here too. It also implements
/// [MovaStandbyKernel] (hold a hidden stream with video/sound off).
///
/// 基于 media_kit `Player` 实现的 [MovaKernel]。
///
/// 这是核心层中唯一允许依赖 `package:media_kit` 的文件；`lib/src/core/` 下
/// 其余所有文件都必须与具体引擎无关。它同时实现 [MovaStatsProbe]——QoE 层用来
/// 拿 libmpv 自身统计量的可选能力——因为这个实现同样只能落在这里。同时实现
/// [MovaStandbyKernel]（在隐藏时关画面/关声音维持流）。
class MovaMpvKernel
    implements MovaKernel, MovaStatsProbe, MovaStandbyKernel, MovaPlayerMute, MovaSourceOptionsKernel {
  /// Creates a media_kit-backed kernel.
  ///
  /// [player] lets the caller inject an existing `Player` (e.g. for testing
  /// or custom configuration); a new `Player()` is created if omitted
  /// (its protocol whitelist is media_kit's default plus `dtls`, see
  /// [movaProtocolWhitelist]; an injected player is left untouched).
  ///
  /// [audioOnly] signifies skipping `VideoController` creation entirely.
  /// media_kit's `Player` defaults to mpv's `--vid=no` until the moment
  /// `VideoController.create()` turns it back to `vid=auto` (media_kit 1.2.6,
  /// see `player/native/player/real.dart`'s `_create()` and
  /// `video_controller/native_video_controller/real.dart`), so bypassing it
  /// truly leaves libmpv decoding only audio: no decode framebuffers, no GPU
  /// textures, no Flutter `Texture` registration. These three are the entirety
  /// of the video-side memory footprint, which becomes zero, not just smaller,
  /// in audio-only mode.
  ///
  /// This "default `--vid=no`" premise must be re-verified upon upgrading
  /// media_kit.
  ///
  /// [observeQoeSignals] controls whether to perform the extra native
  /// `paused-for-cache` property observation and the native event subscription
  /// ([playbackRestarts]/[endFiles]) — all three exist exclusively for the QoE
  /// layer. Callers without a [MovaReporter] should pass `false` so the
  /// constructor completely skips these FFI round-trips, ensuring the "zero cost
  /// if no reporter" promise holds true down at this level (it previously only
  /// applied one layer up in [MovaQoeCollector]).
  ///
  /// [backendFactory] provides a factory for the native event backend.
  ///
  /// 创建基于 media_kit 的内核。
  ///
  /// [player] 允许调用者注入一个已存在的 `Player`（如用于测试或自定义配置）；
  /// 省略时会创建一个新的 `Player()`（协议白名单为 media_kit 默认项加 `dtls`，见
  /// [movaProtocolWhitelist]；注入的 player 不受影响）。
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
  /// [observeQoeSignals] 控制要不要做额外的原生 `paused-for-cache` 属性观察和
  /// 原生事件订阅（[playbackRestarts]/[endFiles]）——这三者全部
  /// 只服务 QoE 层。没有配置 [MovaReporter] 的调用方应传 `false`，让构造期
  /// 完全跳过这几次 FFI 往返，使"没有 reporter 就零开销"这条承诺在这一层
  /// 也成立（此前它只在上一层的 [MovaQoeCollector] 里成立）。
  ///
  /// [observeNativeEvents] 单独控制原生事件订阅（[playbackRestarts]/[endFiles]）：
  /// 为 `null`（默认）时跟随 [observeQoeSignals]，既有调用点行为不变；显式传 `true`
  /// 可在不开 QoE 的情况下只订阅原生事件（例如为了精确首帧信号）。
  ///
  /// [observeRestarts] 只在原生事件订阅开启时有意义：为 `false` 时丢弃 `PLAYBACK_RESTART`，
  /// [playbackRestarts] 不再发事件，只保留 [endFiles]（例如仅为恢复机制的"坏地址秒判"订阅
  /// END_FILE，而不改变首帧判定）。默认 `true`。
  ///
  /// [backendFactory] 为原生事件提供获取后端的工厂。
  ///
  /// [videoControllerFactory] / [videoReady] 仅供测试注入：分别替换 `VideoController`
  /// 的创建与"渲染面就绪"的探测，省略时用 media_kit 真实实现。
  /// [realtimeFormats] / [liveProbeInterval] 仅供测试注入：分别替换实时格式集合与兜底探测的采样间隔。
  /// [mountYield] 仅 [lazyVideo] 生效：`open()` 在控制器尚未创建时先调用它让出一帧，
  /// 使同帧挂载的视频组件能先建好渲染面；省略则不让出（平台层传 `movaFrameYield`）。
  ///
  /// [tlsVerify] turns on strict TLS certificate verification (mpv
  /// `tls-verify=yes`): expired / self-signed / hostname-mismatched HTTPS
  /// streams are rejected. Default `false` sends no TLS property at all
  /// (libmpv's own default applies; on Android that means no verification).
  /// [tlsCaFile] is an absolute path to a PEM CA bundle sent as `tls-ca-file`;
  /// only used when [tlsVerify] is true. Android's mbedtls backend has no
  /// system trust store, so verification there needs this file.
  ///
  /// [tlsVerify] 开启严格 TLS 证书校验（mpv `tls-verify=yes`）：过期/自签/域名不符
  /// 的 HTTPS 流会被拒绝。默认 `false`，不下发任何 TLS 属性（沿用 libmpv 自身默认，
  /// Android 上即不校验）。[tlsCaFile] 为 PEM 格式 CA 证书包的绝对路径，以
  /// `tls-ca-file` 下发，仅在 [tlsVerify] 为 true 时生效。Android 的 mbedtls 后端
  /// 没有系统信任库，要校验就需要这个文件。
  MovaMpvKernel({
    Player? player,
    this.audioOnly = false,
    this.lazyVideo = false,
    bool observeQoeSignals = true,
    bool? observeNativeEvents,
    bool observeRestarts = true,
    MovaMpvEventBackendFactory? backendFactory,
    this.tlsVerify = false,
    this.tlsCaFile,
    MovaVideoControllerFactory? videoControllerFactory,
    MovaVideoReadyProbe? videoReady,
    this.mountYield,
    this.realtimeFormats = kRealtimeFileFormats,
    this.liveProbeInterval = kLiveProbeInterval,
  })
    : _player = player ?? Player(configuration: PlayerConfiguration(protocolWhitelist: movaProtocolWhitelist())),
      _observeRestarts = observeRestarts, // ignore: prefer_initializing_formals
      _backendFactory = backendFactory,
      _videoControllerFactory = videoControllerFactory ?? VideoController.new,
      _videoReadyProbe = videoReady ?? ((c) => c.platform.future) {
    _applyTls();
    if (!audioOnly && !lazyVideo) {
      _attachController();
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
    final wantNative = (observeNativeEvents ?? observeQoeSignals) && backendFactory != null;
    if (!observeQoeSignals && !wantNative) return;
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
      var setup = Future<void>.value();
      if (observeQoeSignals) {
        setup = native
            .observeProperty('paused-for-cache', (value) async {
              if (_stallingController.isClosed) return;
              _stallingController.add(value == 'yes');
            })
            .catchError((_) {
              // 静默降级：这次会话就是没有原生卡顿信号，QoE 层退回旧的
              // `buffering` 判据，其余上报功能不受影响。
            });
      }
      if (wantNative) setup = setup.then((_) => _observeNativeEvents(native));
      _observeSetup = setup;
    }
  }

  /// 命中即限制后向缓冲的 `file-format` 集合，默认 [kRealtimeFileFormats]（仅供测试注入）。
  final Set<String> realtimeFormats;

  /// 兜底探测（不可 seek 且时长随时间增长）的采样间隔，默认 [kLiveProbeInterval]（仅供测试注入）。
  final Duration liveProbeInterval;

  /// Whether strict TLS verification was requested.
  ///
  /// 是否请求了严格 TLS 校验。
  final bool tlsVerify;

  /// CA bundle path sent as `tls-ca-file` when [tlsVerify] is on.
  ///
  /// [tlsVerify] 开启时以 `tls-ca-file` 下发的 CA 证书包路径。
  final String? tlsCaFile;

  /// Pending TLS property writes; [open] waits on it. `null` when off.
  ///
  /// 尚未落地的 TLS 属性写入，[open] 会等它；未开启时为 `null`。
  Future<void>? _tlsSetup;

  /// 限制前读到的缓冲原值（后向字节数/可 seek 缓存）；非空即已下发"实时源缓冲限制"，切源时还原。
  ({String back, String seekable})? _savedCache;

  /// 每次 [open] 自增，用于丢弃已被新 open 取代的格式判断。
  int _openSeq = 0;

  /// 本次 open 是否还在等"文件加载完成后判断格式"。
  bool _formatProbePending = false;

  /// 监听 track-list 变化的订阅；首次 [open] 时才建立。
  StreamSubscription<Tracks>? _tracksSub;

  /// 首次 [open] 时挂上 track-list 监听：文件加载完成后 mpv 才给出真实轨道，
  /// 以此作为"可以读 `file-format`"的信号。
  void _watchLoaded() {
    _tracksSub ??= _player.stream.tracks.listen(_onTracks);
  }

  /// track-list 刷新：出现真实轨道且本次 open 尚未判断时读 `file-format`。
  /// 命中 [realtimeFormats] 直接限制；否则走兜底 [_probeUnseekableLive]。
  /// 空轨道（切源重置）直接忽略。
  Future<void> _onTracks(Tracks t) async {
    if (!_formatProbePending || !_hasRealTrack(t)) return;
    _formatProbePending = false;
    final seq = _openSeq;
    final format = await _readNativeProperty(kFileFormat) ?? '';
    if (seq != _openSeq) return;
    final live = realtimeFormats.contains(format) ||
        (!kPlaylistFileFormats.contains(format) && await _probeUnseekableLive(seq));
    if (!live || seq != _openSeq || _disposed) return;
    await _limitLiveCache();
    // 限制落地期间若已换源，立即还原，避免残留。
    if (seq != _openSeq) await _restoreLiveCache();
  }

  /// 兜底判断：间隔 [liveProbeInterval] 采样两次，两次都 `seekable=no`，且时长两次都读不到、
  /// 或第二次比第一次至少多 间隔 x [kLiveDurationGrowthRatio] 秒，才认为是实时流。
  /// 可 seek 的点播、时长恒定的源、中途换源/销毁，一律返回 false（宁可漏限制，不误限制）。
  Future<bool> _probeUnseekableLive(int seq) async {
    Future<(String, double?)?> sample() async {
      await Future<void>.delayed(liveProbeInterval);
      if (seq != _openSeq || _disposed) return null;
      // 两次读取互不依赖，并行发起。
      final r = await Future.wait([_readNativeProperty(kSeekable), _readNativeProperty(kDuration)]);
      return (r[0] ?? '', double.tryParse(r[1] ?? ''));
    }

    final a = await sample();
    if (a == null || a.$1 != kNotSeekable) return false;
    final b = await sample();
    if (b == null || b.$1 != kNotSeekable) return false;
    final (da, db) = (a.$2, b.$2);
    if (da == null || db == null) return da == db;
    return db - da >= liveProbeInterval.inMilliseconds / 1000 * kLiveDurationGrowthRatio;
  }

  /// [t] 里是否有 auto/no 之外的真实轨道。
  static bool _hasRealTrack(Tracks t) {
    bool real(String id) => id != _kVidAuto && id != _kVidOff;
    return t.video.any((e) => real(e.id)) || t.audio.any((e) => real(e.id));
  }

  /// 记下原值后收紧后向缓冲；失败被吞掉，不影响播放。
  Future<void> _limitLiveCache() async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    try {
      final back = await _readNativeProperty(kDemuxerMaxBackBytes) ?? kVodMaxBackBytes;
      final seekable = await _readNativeProperty(kDemuxerSeekableCache) ?? kVodSeekableCache;
      await native.setProperty(kDemuxerMaxBackBytes, kLiveMaxBackBytes);
      await native.setProperty(kDemuxerSeekableCache, kLiveSeekableCache);
      _savedCache = (back: back, seekable: seekable);
    } catch (_) {}
  }

  /// 若当前处于限制状态，写回限制前的原值（读不到时已是兜底常量）；失败被吞掉。
  Future<void> _restoreLiveCache() async {
    final saved = _savedCache;
    if (saved == null) return;
    final native = _player.platform;
    if (native is! NativePlayer) return;
    _savedCache = null;
    try {
      await native.setProperty(kDemuxerMaxBackBytes, saved.back);
      await native.setProperty(kDemuxerSeekableCache, saved.seekable);
    } catch (_) {}
  }

  /// Sends `tls-verify` (and `tls-ca-file`) to mpv; no-op unless [tlsVerify].
  /// Failures are swallowed so a property error never breaks playback.
  ///
  /// 把 `tls-verify`（及 `tls-ca-file`）下发给 mpv；未开启 [tlsVerify] 时什么都不做。
  /// 失败被吞掉，属性错误不影响播放。
  void _applyTls() {
    if (!tlsVerify) return;
    final native = _player.platform;
    if (native is! NativePlayer) return;
    final ca = tlsCaFile;
    _tlsSetup = () async {
      try {
        if (ca != null) await native.setProperty('tls-ca-file', ca);
        await native.setProperty('tls-verify', 'yes');
      } catch (_) {}
    }();
  }

  /// 标识内核是否已销毁。
  bool _disposed = false;

  /// 用于事件抽水的泵实例。
  MovaMpvEventPump? _pump;

  /// 后端工厂函数，用于创建 MovaMpvEventBackend。
  final MovaMpvEventBackendFactory? _backendFactory;

  /// 是否转发原生 `PLAYBACK_RESTART`；为 false 时只转发 END_FILE。
  final bool _observeRestarts;

  /// 全局单调递增计数器，为每个事件泵生成唯一名字。
  static int _pumpNameCounter = 0;

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
  /// `MPV_EVENT_END_FILE` 提供原生的会话结束原因。通过自建弱客户端及
  /// [MovaMpvEventPump] 订阅，避免依赖被舍弃的 media_kit `observeEvent`。
  Future<void> _observeNativeEvents(NativePlayer native) async {
    int addr;
    try {
      addr = await native.handle;
    } catch (_) {
      return;
    }
    
    if (_disposed) return;
    if (_backendFactory == null) return;

    MovaMpvEventBackend backend;
    try {
      backend = _backendFactory(native, addr);
    } catch (_) {
      return;
    }

    final pumpName = 'mova_qoe_${_pumpNameCounter++}';
    final pump = MovaMpvEventPump(
      backend,
      name: pumpName,
      onRestart: () {
        if (_observeRestarts && !_restartController.isClosed) {
          _restartController.add(null);
        }
      },
      onEndFile: (reason) {
        if (!_endFileController.isClosed) {
          final mapped = _mapEndFileReason(reason);
          if (mapped != null) {
            _endFileController.add(mapped);
          }
        }
      },
    );

    _pump = pump;
    await pump.start(Future.value());
    
    if (_disposed) {
      await pump.dispose();
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

  /// Whether the [VideoController] is created on first read of [renderHandle]
  /// (i.e. when a video widget actually mounts) instead of at construction.
  /// A controller that is created but never attached to a surface keeps
  /// `Player.dispose()` waiting for it (real-device: 3/6 disposes hit an 8s
  /// timeout on Windows, 4/5 on Android), so engines that may never be shown
  /// should be lazy. Ignored when [audioOnly].
  ///
  /// 是否把 [VideoController] 推迟到第一次读取 [renderHandle]（即视频组件真正挂上
  /// 时）才创建，而不是构造时创建。创建了却从未挂到渲染面的控制器会让
  /// `Player.dispose()` 一直等它（真机：Windows 上 3/6 次 dispose 撞 8s 超时，
  /// Android 上 4/5 次），所以可能从不展示的引擎应设为懒创建。[audioOnly] 时忽略。
  final bool lazyVideo;

  /// The video controller used to attach this kernel to a video widget;
  /// `null` when [audioOnly].
  ///
  /// 用于把该内核挂接到视频组件上的控制器；[audioOnly] 时为 `null`。
  VideoController? _controller;

  /// 视频控制器工厂。
  final MovaVideoControllerFactory _videoControllerFactory;

  /// 渲染面就绪探针。
  final MovaVideoReadyProbe _videoReadyProbe;

  /// lazy 模式下 `open()` 让出一帧的钩子；`null` 表示不让出。
  final MovaMountYield? mountYield;

  /// 当前控制器的"渲染面就绪并已补选视频轨"收尾 Future；无控制器时为 `null`。
  Future<void>? _videoPrepared;

  /// Creates the [VideoController] and starts its readiness follow-up.
  ///
  /// media_kit's controller flips `vid=auto` *before* its render context
  /// exists; a file that opens in that window fails VO init ("No render
  /// context set") and mpv drops the video track for good (`vid=no`, audio
  /// only). Once the surface is ready this re-selects the track.
  ///
  /// 创建 [VideoController] 并启动就绪后的补选逻辑。
  ///
  /// media_kit 的控制器在渲染上下文建好**之前**就把 `vid` 设成 `auto`；文件恰在
  /// 这个窗口打开会因 "No render context set" 初始化 VO 失败，mpv 随即永久丢掉视频轨
  /// （`vid=no`，只出声不出画）。渲染面就绪后在此补选一次视频轨。
  VideoController _attachController() {
    final c = _videoControllerFactory(_player);
    _controller = c;
    _videoPrepared = _prepareVideo(c);
    return c;
  }

  /// Lets one frame pass so a video widget mounting in the same frame can
  /// create the controller before the file opens (it is ready-awaited right
  /// after). Never creates a controller itself, so never-shown engines keep
  /// the lazy benefit; a stalled frame loop only costs [kMountGrace].
  ///
  /// 让出一帧，使同帧挂载的视频组件能先创建控制器（随后会等它就绪）再开文件。
  /// 自己绝不创建控制器，所以从不展示的引擎仍保持懒创建收益；帧停摆时最多等 [kMountGrace]。
  Future<void> _yieldForMount() async {
    final y = mountYield;
    if (y == null) return;
    try {
      await y().timeout(kMountGrace);
    } on Object {
      // 钩子失败或帧停摆：不等了
    }
  }

  /// Waits for the surface, then restores `vid=auto` if mpv turned it off.
  ///
  /// 等渲染面就绪，若 mpv 已把 `vid` 关掉则恢复为 `auto`。失败静默（仅退化为旧行为）。
  Future<void> _prepareVideo(VideoController c) async {
    try {
      await _videoReadyProbe(c);
      if (_disposed) return;
      final native = _player.platform;
      if (native is! NativePlayer) return;
      if (await native.getProperty(_kVid) == _kVidOff) {
        // 运行期读到 no 时选项值其实仍是 auto，直接再设 auto 是空操作；先写 no 制造变化再写 auto。
        await native.setProperty(_kVid, _kVidOff);
        await native.setProperty(_kVid, _kVidAuto);
      }
    } on Object {
      // 就绪失败或属性读写失败：不影响播放，保持旧行为
    }
  }

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

  /// 暂存、待下一次 [open] 应用的按源选项；[open] 一开头就取走并清空。
  Map<String, String> _stagedOptions = const {};

  /// 已下发的按源选项在下发前的原值（属性名 → 原值）；非空即有待还原项，下次 [open] 先还原。
  final Map<String, String> _appliedOptions = {};

  /// 已下发的键值列表选项：选项名 → 本源加入的键及其原值（`null` 表示原来没有该键）。
  /// 还原时只删这些键、把有原值的补回去，不碰列表里别的项。
  final Map<String, Map<String, String?>> _appliedLists = {};

  @override
  void stageSourceOptions(Map<String, String> options) => _stagedOptions = Map.of(options);

  /// 把上一个源下发过的属性写回原值；写入失败被吞掉。
  Future<void> _restoreSourceOptions() async {
    if (_appliedOptions.isEmpty && _appliedLists.isEmpty) return;
    final native = _player.platform;
    final saved = Map.of(_appliedOptions);
    final savedLists = Map.of(_appliedLists);
    _appliedOptions.clear();
    _appliedLists.clear();
    if (native is! NativePlayer) return;
    for (final e in saved.entries) {
      try {
        await native.setProperty(e.key, e.value);
      } catch (_) {}
    }
    for (final list in savedLists.entries) {
      for (final key in list.value.entries) {
        try {
          await native.command(['change-list', list.key, 'remove', key.key]);
          final original = key.value;
          if (original != null) await native.command(['change-list', list.key, 'append', '${key.key}=$original']);
        } catch (_) {}
      }
    }
  }

  /// 把键值列表选项 [name] 的 [value] 并入现有列表（`change-list add`，不覆盖别的项），
  /// 并记下这些键的原值供还原；值不合法或写入失败就整项跳过。
  Future<void> _applyListOption(NativePlayer native, String name, String value) async {
    final entries = parseMpvKeyValueList(value);
    if (entries == null || entries.isEmpty) return;
    final printed = await _readNativeProperty(name) ?? '';
    final originals = <String, String?>{for (final e in entries) e.key: lookupMpvKeyValue(printed, e.key)};
    try {
      await native.command(['change-list', name, 'add', value]);
      _appliedLists.putIfAbsent(name, () => {}).addAll(originals);
    } catch (_) {}
  }

  /// 记下原值后逐项下发 [options]；某项写入失败只跳过该项，不影响播放。
  Future<void> _applySourceOptions(Map<String, String> options) async {
    final native = _player.platform;
    if (options.isEmpty || native is! NativePlayer) return;
    for (final e in options.entries) {
      if (kMpvKeyValueListOptions.contains(e.key)) {
        await _applyListOption(native, e.key, e.value);
        continue;
      }
      final original = await _readNativeProperty(e.key) ?? '';
      try {
        await native.setProperty(e.key, e.value);
        _appliedOptions[e.key] = original;
      } catch (_) {}
    }
  }

  @override
  Future<void> open(String uri, {bool play = true}) async {
    // 同步取走暂存项：它只属于紧随其后的这一次 open，不被后来的 open 误用。
    final options = _stagedOptions;
    _stagedOptions = const {};
    await _tlsSetup;
    final seq = ++_openSeq;
    _formatProbePending = false;
    // 每次切源先还原；是否为 WHEP 要等文件打开后按真实格式判断。
    await _restoreLiveCache();
    // A newer open() (or dispose) superseded this one while it was waiting.
    //
    // 等待期间已被更新的 open()（或 dispose）取代。
    if (seq != _openSeq || _disposed) return;
    // 先还原上一个源的按源选项，再下发本源的：选项不跨源泄漏。
    await _restoreSourceOptions();
    if (seq != _openSeq || _disposed) return;
    await _applySourceOptions(options);
    if (seq != _openSeq || _disposed) return;
    if (_player.platform is NativePlayer) {
      _watchLoaded();
      _formatProbePending = true;
    }
    if (lazyVideo && !audioOnly && _controller == null) await _yieldForMount();
    if (seq != _openSeq || _disposed) return;
    // 控制器已存在时，先等渲染面就绪再开文件，避开"vid=auto 先于 render context"的窗口。
    final prepared = _videoPrepared;
    if (prepared != null) {
      await prepared.timeout(kVideoReadyTimeout, onTimeout: () {});
      if (seq != _openSeq || _disposed) return;
    }
    try {
      await _player.open(Media(uri), play: play);
    } catch (_) {
      if (seq == _openSeq) _formatProbePending = false;
      rethrow;
    }
  }

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
      audioOnly || _controller == null ? null : _player.screenshot(format: 'image/jpeg');

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _widthSub?.cancel();
    await _heightSub?.cancel();
    await _tracksSub?.cancel();
    await _sizeController.close();
    await _stallingController.close();
    await _restartController.close();
    await _endFileController.close();
    // 必须等构造期发起的原生观察者注册落地，才能销毁 _player——见
    // _observeSetup 的文档注释。
    // 因为 observeProperty 自身也 await 同一个初始化 future，如果
    // handle 挂起会拖死 dispose，因此加一个 5 秒的超时。
    try {
      await _observeSetup?.timeout(const Duration(seconds: 5));
    } catch (_) {
      // 超时或抛错吞掉继续销毁
    }
    await _pump?.dispose();
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
  Stream<Object> get error => _player.stream.error.where((e) => !isBenignMpvError(e));

  @override
  Object? get renderHandle {
    if (audioOnly || _disposed) return _controller;
    return _controller ?? _attachController();
  }

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
  // 不转发 RESTART 时不能声称有信号，否则首帧闸门会白等宽限。
  bool get nativeRestartAvailable => _observeRestarts && (_pump?.isActive ?? false);

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
      _tryStringProperty(kFileFormat),
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

  // ---------------------------------------------------------------------
  // MovaStandbyKernel — hold the stream with video/sound off. Only `mute`
  // and `vid` are touched, saved first and restored verbatim; never
  // `volume` (a system-volume port may own it), `vo`/`wid` (media_kit's
  // Android widListener owns them) or the VideoController.
  //
  // MovaStandbyKernel——关掉画面/声音维持流。只碰 `mute` 与 `vid`，先保存、再原样还原；
  // 绝不碰 `volume`（可能归系统音量端口管）、`vo`/`wid`（归 media_kit 的 Android
  // widListener 管）以及 VideoController。
  // ---------------------------------------------------------------------

  /// Upper bound for one standby property read/write.
  ///
  /// 单次待机属性读写的上限。
  static const Duration _standbyOpTimeout = Duration(seconds: 2);

  /// Values saved by [enterStandby]; null when not in standby.
  ///
  /// [enterStandby] 保存的原值；不在待机时为 null。
  Map<String, String>? _standbySaved;

  /// Original mute before warm-up; standby's saved mute follows this ownership.
  ///
  /// 预热前的原始静音；待机保存的静音随此所有权调整。
  String? _warmMuteSaved;

  /// Applies player-local warm-up mute in the same queue as standby.
  /// While both own mute, standby saves `yes`; releasing warm-up replaces that
  /// saved value with the original, so either release order preserves the other.
  ///
  /// 在与待机相同的队列里应用播放器预热静音。
  /// 两者都持有静音时，待机保存 yes；释放预热时将该保存值改回原值，保证任意退出顺序都保留另一方。
  ///
  /// [on] acquires/releases mute; returns success / [on] 获取或释放静音；返回是否成功。
  /// Example / 示例：`await kernel.setWarmMute(true);`
  @override
  Future<bool> setWarmMute(bool on) => _standbySerial(() async {
        final native = _player.platform;
        if (_disposed || native is! NativePlayer) return false;
        if (on == (_warmMuteSaved != null)) return true;
        try {
          if (on) {
            final saved = _standbySaved?['mute'] ??
                await native.getProperty('mute').timeout(_standbyOpTimeout);
            await native.setProperty('mute', 'yes').timeout(_standbyOpTimeout);
            _warmMuteSaved = saved;
            if (_standbySaved != null) _standbySaved!['mute'] = 'yes';
          } else {
            final saved = _warmMuteSaved!;
            if (_standbySaved != null) {
              _standbySaved!['mute'] = saved;
            } else {
              await native.setProperty('mute', saved).timeout(_standbyOpTimeout);
            }
            _warmMuteSaved = null;
          }
          return true;
        } on Object {
          return false;
        }
      });

  /// Serializes enter/exit so property writes never interleave.
  ///
  /// 串行化进入/退出，使属性写入永不交错。
  Future<void> _standbyQueue = Future<void>.value();

  /// Runs [step] after every earlier standby step has settled.
  ///
  /// 在之前所有待机步骤落定后执行 [step]。
  Future<T> _standbySerial<T>(Future<T> Function() step) {
    final next = _standbyQueue.then((_) => step());
    _standbyQueue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<MovaStandbyMedia> inspectStandby() async {
    final format = await _readNativeProperty('file-format');
    try {
      final s = _player.state;
      final audio = movaAudioPresence(
        audioIds: s.tracks.audio.map((t) => t.id),
        videoIds: s.tracks.video.map((t) => t.id),
        selectedAudio: s.track.audio.id,
        sampleRate: s.audioParams.sampleRate,
      );
      return MovaStandbyMedia(audio: audio, format: format);
    } on Object {
      return MovaStandbyMedia(audio: MovaAudioPresence.unknown, format: format);
    }
  }

  @override
  Future<bool> enterStandby(MovaStandbyMode mode) => _standbySerial(() async {
        if (_disposed) return false;
        if (_standbySaved != null) return true; // 幂等
        final native = _player.platform;
        if (native is! NativePlayer) return false;
        try {
          final mute = await native.getProperty('mute').timeout(_standbyOpTimeout);
          final vid = mode == MovaStandbyMode.muted
              ? await native.getProperty('vid').timeout(_standbyOpTimeout)
              : null;
          final saved = <String, String>{'mute': mute};
          if (vid != null) saved['vid'] = vid;
          _standbySaved = saved;
          await native.setProperty('mute', 'yes').timeout(_standbyOpTimeout);
          if (vid != null && vid != 'no') {
            await native.setProperty('vid', 'no').timeout(_standbyOpTimeout);
          }
          return true;
        } on Object {
          await _restoreStandby(native);
          return false;
        }
      });

  @override
  Future<bool> exitStandby() => _standbySerial(() async {
        final native = _player.platform;
        if (_disposed || native is! NativePlayer) {
          _standbySaved = null;
          return false;
        }
        return _restoreStandby(native);
      });

  /// Writes back whatever [_standbySaved] holds, video first; best effort.
  /// Returns whether `vid` went from `no` back to a real value.
  ///
  /// 把 [_standbySaved] 里的值写回，先视频后声音；尽力而为。返回 `vid` 是否从 `no` 恢复成了实际值。
  Future<bool> _restoreStandby(NativePlayer native) async {
    final saved = _standbySaved;
    _standbySaved = null;
    if (saved == null) return false;
    var restarted = false;
    final vid = saved['vid'];
    if (vid != null && vid != 'no') {
      try {
        await native.setProperty('vid', vid).timeout(_standbyOpTimeout);
        restarted = true;
      } on Object {
        // 尽力而为：写不回去就让后续的 mute 继续还原。
      }
    }
    final mute = saved['mute'];
    if (mute != null) {
      try {
        await native.setProperty('mute', mute).timeout(_standbyOpTimeout);
      } on Object {
        // 尽力而为。
      }
    }
    return restarted;
  }
}
