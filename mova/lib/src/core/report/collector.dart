import 'dart:async';

import '../events/events.dart';
import '../model/source.dart';
import '../options/report_config.dart';
import 'error_policy.dart';
import 'report.dart';
import 'session.dart';
import 'stall.dart';
import 'stats_probe.dart';
import 'translator.dart';
import 'truncation.dart';
import 'ttff.dart';

/// How close in wall-clock time a `MovaErrorEvent` and a [MovaLogLine] must
/// land to be treated as the same underlying error, letting the collector
/// recover the mpv subsystem prefix media_kit's own `error` stream throws
/// away.
///
/// `MovaErrorEvent` 与一条 [MovaLogLine] 在墙钟时间上需要多接近才会被视为同一
/// 个错误——由此拿回 media_kit 自己的 `error` 流丢弃的 mpv 子系统 prefix。
const _errorLogPairWindow = Duration(milliseconds: 200);

/// Owns one playback session's QoE state and turns raw signals into report
/// events. Constructed by `MovaEngine` only when a reporter is present;
/// `MovaReportConfig.qoe == false` makes it a pure passthrough that behaves
/// byte-for-byte like the old `MovaReportTranslator` (whitelist translation
/// only, no `sessionId`, legacy error shape).
///
/// 持有一次播放会话的 QoE 状态，把原始信号转成上报事件。仅当存在 reporter 时
/// 由 `MovaEngine` 构造；`MovaReportConfig.qoe` 为 `false` 时它退化为纯直通
/// （只做白名单转换，没有 `sessionId`，错误维持旧形状），行为与旧的
/// `MovaReportTranslator` 逐字节一致。
class MovaQoeCollector {
  /// Subscribes to [events] (and, when [config].qoe is on, to [probe]'s
  /// streams) and forwards standardized report events to [reporter].
  ///
  /// 订阅 [events]（[config].qoe 开启时还订阅 [probe] 的流），把标准化后的
  /// 上报事件转发给 [reporter]。
  MovaQoeCollector({
    required Stream<MovaEvent> events,
    required MovaReporter reporter,
    required MovaReportConfig config,
    MovaStatsProbe? probe,
    DateTime Function() now = DateTime.now,
  })  : _reporter = reporter, // ignore: prefer_initializing_formals
        _config = config, // ignore: prefer_initializing_formals
        _probe = probe,
        _now = now { // ignore: prefer_initializing_formals
    _sub = events.listen(_onEvent);
    final p = probe;
    if (_config.qoe && p != null) {
      _stallSub = p.stalling.listen(_onStalling);
      _logSub = p.logs.listen(_onLog);
      // 2026-09-29 架构更新：优先用原生事件做 TTFF 终点/会话结束原因，见
      // doc/plans/2026-09-29-telemetry-enhancement.md「新架构决策」。两条订阅
      // 都是可选能力——kernel 侧订阅失败时这两个流保持空，此处订阅本身不会
      // 抛出（MovaMpvKernel._observeNativeEvents 已吞掉失败）。
      _restartSub = p.playbackRestarts.listen((_) => _onRestart());
      _endFileSub = p.endFiles.listen(_onEndFile);
    }
  }

  final MovaReporter _reporter;
  final MovaReportConfig _config;
  final MovaStatsProbe? _probe;
  final DateTime Function() _now;

  late final StreamSubscription<MovaEvent> _sub;
  StreamSubscription<bool>? _stallSub;
  StreamSubscription<MovaLogLine>? _logSub;
  StreamSubscription<void>? _restartSub;
  StreamSubscription<MovaEndFileReason>? _endFileSub;

  String? _sessionId;
  MovaStallPolicy? _stallPolicy;
  final MovaTtffTracker _ttff = MovaTtffTracker();
  final MovaSessionTally _tally = MovaSessionTally();
  MovaErrorPolicy get _errorPolicy => _config.effectiveErrorPolicy;

  MovaStreamType _streamType = MovaStreamType.vod;
  bool _audioOnly = false;
  bool _swapEnabled = false;
  bool _fatalSeen = false;
  bool _completed = false;
  bool _sessionOpen = false;
  int _stallIndex = 0;
  bool _lastStalled = false;
  bool _playing = false;
  Timer? _heartbeatTimer;

  /// The most recent native `MPV_EVENT_END_FILE` reason for the current
  /// session, or `null` when none has arrived yet (or the kernel doesn't
  /// support `observeEvent`) — fed to [resolveSessionEndNative].
  ///
  /// 当前会话最近一次原生 `MPV_EVENT_END_FILE` 原因；尚未到达（或内核不支持
  /// `observeEvent`）时为 `null`——喂给 [resolveSessionEndNative]。
  MovaEndFileReason? _lastEndFileReason;

  /// The most recent unpaired error-level log line, kept for
  /// [_errorLogPairWindow]-based pairing with the next `MovaErrorEvent`.
  ///
  /// 最近一条尚未配对的 error 级日志行，供与下一次 `MovaErrorEvent` 做
  /// [_errorLogPairWindow] 时间窗内的配对。
  MovaLogLine? _pendingLog;
  DateTime? _pendingLogAt;

  /// Furthest position seen after the first frame landed (excludes the
  /// previous clip's residual positions that arrive right after `open()`).
  ///
  /// 首帧落地后见到的最远位置（排除 `open()` 后紧跟的上一素材残留位置）。
  int _validMaxPositionMs = 0;

  /// When the latest ffmpeg-prefixed error log arrived this session.
  ///
  /// 本会话最近一条 ffmpeg 前缀错误日志的到达时间。
  DateTime? _lastFfmpegErrorAt;

  /// Whether an ffmpeg error log landed within [movaTruncationLogWindow]
  /// before `MovaDone`.
  ///
  /// `MovaDone` 之前 [movaTruncationLogWindow] 内是否出现过 ffmpeg 错误日志。
  bool _ffmpegErrorBeforeDone = false;

  /// Marks the start of a new session; called from the first line of
  /// `MovaEngine.open`.
  ///
  /// 标记一次新会话的开始；由 `MovaEngine.open` 的第一行调用。
  ///
  /// - [source]: the source being opened / 正在打开的源
  /// - [autoPlay]: whether playback starts immediately / 是否立即开始播放
  /// - [audioOnly]: whether this engine has no video pipeline / 该引擎是否无
  ///   视频管线
  /// - [swapEnabled]: whether seamless engine-swapping is on / 是否启用了
  ///   无缝引擎切换
  void onOpen(
    MovaSource source, {
    required bool autoPlay,
    bool audioOnly = false,
    bool swapEnabled = false,
  }) {
    final at = _now();
    _sessionOpen = true;
    _streamType = source.type;
    _audioOnly = audioOnly;
    _swapEnabled = swapEnabled;
    _fatalSeen = false;
    _completed = false;
    _stallIndex = 0;
    _lastStalled = false;
    _playing = false;
    _lastEndFileReason = null;
    _validMaxPositionMs = 0;
    _lastFfmpegErrorAt = null;
    _ffmpegErrorBeforeDone = false;
    _tally.setPlaying(false);
    _tally.setStalled(false);
    _stallPolicy = _config.newStallPolicy();
    _ttff.reset();
    _ttff.arm(at, autoPlay: autoPlay);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (!_config.qoe) return;
    final sessionId = _config.effectiveSessionIdFactory();
    _sessionId = sessionId;
    unawaited(_emitSessionStart(source, at, sessionId));
    final interval = _config.heartbeat;
    if (interval != null) {
      _heartbeatTimer = Timer.periodic(interval, (_) => _emitHeartbeat());
    }
  }

  /// Emits a periodic `heartbeat` snapshot; a no-op while paused (nothing new
  /// to say) or once the session has ended.
  ///
  /// 发出一次周期性 `heartbeat` 快照；暂停期间（没有新信息）或会话已结束时为
  /// 空操作。
  void _emitHeartbeat() {
    if (!_sessionOpen || !_playing) return;
    // Captured here, before the `await` below, so a session boundary crossed
    // mid-flight (a new open()/teardown while the probe sample is pending)
    // can never leak the wrong (or reset-to-null) sessionId onto this event
    // — the same reasoning applies to _emitSessionStart/_enrichAndEmit.
    //
    // 在下面的 `await` 之前先捕获——这样即便探针取样期间跨越了会话边界（新的
    // open()/teardown 恰好插进来），也不会把错误的（或已被重置为 null 的）
    // sessionId 泄漏到这条事件上——_emitSessionStart/_enrichAndEmit 同理。
    unawaited(_emitHeartbeatAsync(_sessionId));
  }

  Future<void> _emitHeartbeatAsync(String? sessionId) async {
    final at = _now();
    final params = <String, dynamic>{
      'watchedMs': _tally.watchedMs,
      'positionMs': _tally.maxPositionMs,
      'stallCount': _tally.stallCount,
      'stallMs': _tally.stallMs,
    };
    final snapshot = await _probe?.sample();
    if (snapshot?.videoBps != null) params['videoBps'] = snapshot!.videoBps;
    if (snapshot?.inputBps != null) params['inputBps'] = snapshot!.inputBps;
    if (!_sessionOpen) return;
    _emit(MovaReportEvent(
      kind: MovaReportKind.event,
      name: MovaReportName.heartbeat,
      params: params,
      priority: MovaReportPriority.batched,
      at: at,
      sessionId: sessionId,
    ));
  }

  /// Builds and emits `sessionStart`, filling in the optional
  /// `hwdec`/`viaNetwork`/`fileFormat` keys from a probe sample when
  /// available. [sessionId] is captured by the caller before the `await`
  /// inside here, not read from the mutable [_sessionId] field — otherwise a
  /// teardown racing the pending probe sample would leak the *next*
  /// session's id (or `null`) onto this `sessionStart`.
  ///
  /// 构建并发出 `sessionStart`，探针可用时补上可选的
  /// `hwdec`/`viaNetwork`/`fileFormat` 键。[sessionId] 由调用方在本函数内的
  /// `await` 之前捕获传入，而非在这里读取可变的 [_sessionId] 字段——否则一次与
  /// 探针取样竞速的 teardown 会把*下一个*会话的 id（或 `null`）泄漏到这条
  /// `sessionStart` 上。
  Future<void> _emitSessionStart(MovaSource source, DateTime at, String? sessionId) async {
    final params = <String, dynamic>{
      'uri': source.uri,
      'streamType': _streamType == MovaStreamType.live ? 'live' : 'vod',
      'audioOnly': _audioOnly,
      'swapEnabled': _swapEnabled,
      if (source.title != null) 'title': source.title,
    };
    final snapshot = await _probe?.sample();
    if (snapshot != null) {
      if (snapshot.hwdec != null) params['hwdec'] = snapshot.hwdec;
      if (snapshot.viaNetwork != null) params['viaNetwork'] = snapshot.viaNetwork;
      if (snapshot.fileFormat != null) params['fileFormat'] = snapshot.fileFormat;
    }
    _emit(MovaReportEvent(
      kind: MovaReportKind.event,
      name: MovaReportName.sessionStart,
      params: params,
      priority: MovaReportPriority.batched,
      at: at,
      sessionId: sessionId,
    ));
  }

  /// Terminates the current session (new `open()` or `dispose()`); emits
  /// `sessionEnd` (or `startupFail` when the first frame never landed) when
  /// [MovaReportConfig.qoe] is on.
  ///
  /// 终结当前会话（新的 `open()` 或 `dispose()`）；[MovaReportConfig.qoe]
  /// 开启时发出 `sessionEnd`（若首帧从未落地则发 `startupFail`）。
  void onTeardown() {
    if (!_sessionOpen) return;
    _sessionOpen = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final at = _now();
    _tally.tick(at);
    if (!_config.qoe) return;
    if (_ttff.wasArmed && !_ttff.landed) {
      final armedAt = _ttff.armedAt;
      _emit(MovaReportEvent(
        kind: MovaReportKind.error,
        name: MovaReportName.startupFail,
        params: {
          'reason': _fatalSeen ? 'failed' : 'abandoned',
          'waitedMs': armedAt == null ? 0 : at.difference(armedAt).inMilliseconds,
        },
        priority: MovaReportPriority.immediate,
        at: at,
        sessionId: _sessionId,
      ));
    }
    _emitSessionEnd(at);
    _sessionId = null;
  }

  void _emitSessionEnd(DateTime at) {
    // 2026-09-29 架构更新：优先用原生 `MPV_EVENT_END_FILE` 原因佐证（未到达时
    // 严格退化为旧的 resolveSessionEnd 行为，见 resolveSessionEndNative 文档）。
    final baseReason = resolveSessionEndNative(
      nativeReason: _lastEndFileReason,
      fatalSeen: _fatalSeen,
      completed: _completed,
      firstFrame: _ttff.landed,
    );
    var reason = baseReason;
    if (baseReason == MovaSessionEnd.ended &&
        resolveTruncated(
          threshold: _config.truncatedBelow,
          durationMs: _tally.durationMs,
          validPositionMs: _validMaxPositionMs,
          isLiveSource: _streamType == MovaStreamType.live,
          ffmpegErrorBeforeEof: _ffmpegErrorBeforeDone,
        )) {
      // EOF 但没播够：服务端静默断流，改记 failed + truncated。
      reason = MovaSessionEnd.failed;
      final durationMs = _tally.durationMs;
      _emit(MovaReportEvent(
        kind: MovaReportKind.error,
        name: MovaReportName.error,
        params: {
          'error': durationMs > 0
              ? 'truncated: EOF at $_validMaxPositionMs/$durationMs ms'
              : 'truncated: EOF after ffmpeg error',
          'fatal': true,
          'code': movaTruncatedCode,
        },
        priority: MovaReportPriority.immediate,
        at: at,
        sessionId: _sessionId,
      ));
    }
    final params = <String, dynamic>{
      'reason': reason.name,
      'watchedMs': _tally.watchedMs,
      'stallCount': _tally.stallCount,
      'stallMs': _tally.stallMs,
      'rebufferRate': _tally.rebufferRate,
    };
    final completion = _tally.completionPercent;
    if (completion != null) params['completionPercent'] = completion;
    _emit(MovaReportEvent(
      kind: MovaReportKind.event,
      name: MovaReportName.sessionEnd,
      params: params,
      priority: MovaReportPriority.immediate,
      at: at,
      sessionId: _sessionId,
    ));
  }

  /// Feeds a continuous position update; used for [MovaSessionTally]'s
  /// completion percentage. Not a `MovaEvent` — `MovaEngine` calls this
  /// directly from its position subscription, since position updates are not
  /// otherwise observable on the event bus.
  ///
  /// 输入一次连续的位置更新，供 [MovaSessionTally] 计算完成度。它不是
  /// `MovaEvent`——`MovaEngine` 直接从其 position 订阅调用本方法，因为位置更新
  /// 本就不会出现在事件总线上。
  void onPosition(Duration position) {
    if (!_sessionOpen || !_config.qoe) return;
    _tally.recordPosition(position);
    if (_ttff.landed && position.inMilliseconds > _validMaxPositionMs) {
      _validMaxPositionMs = position.inMilliseconds;
    }
    if (_nativeRestartLive) return;
    final at = _now();
    final elapsed = _ttff.onProgress(position, at);
    if (elapsed != null) _emitFirstFrame(elapsed, at, signal: 'progress');
  }

  void _onEvent(MovaEvent event) {
    if (event is MovaErrorEvent) {
      _onError(event);
      return;
    }
    if (_config.qoe) {
      _trackForQoe(event);
    }
    if (event is MovaQualityChange) {
      _onQualityChange(event);
      return;
    }
    if (event is MovaAbrDownShift) {
      _onAbrDownShift(event);
      return;
    }
    final base = translateMovaEvent(event, now: _now);
    if (base == null) return;
    _emit(_withSessionId(base));
  }

  /// The most recently sampled video bitrate, kept so the *next* quality
  /// switch can report `fromBps` without needing a pre-switch sample (which
  /// would require hooking `switchQuality` itself, not just its event).
  ///
  /// 最近一次采样到的视频码率，留存下来使*下一次*换档能上报 `fromBps`，而无需
  /// 在换档前专门取样（那需要挂接 `switchQuality` 本身，而非仅其事件）。
  int? _lastVideoBps;

  void _onQualityChange(MovaQualityChange event) {
    final at = _now();
    if (!_config.qoe) {
      // qoe:off 分支复用 translateMovaEvent 已有的 MovaQualityChange case，
      // 不重新手写一份形状相同的 MovaReportEvent——避免两处各自维护同一条
      // 转换规则、日后改字段容易漏改一边。
      final base = translateMovaEvent(event, now: () => at);
      if (base != null) _emit(_withSessionId(base));
      return;
    }
    final params = <String, dynamic>{'quality': event.quality.label, 'reason': 'manual'};
    if (event.quality.width != null) params['width'] = event.quality.width;
    if (event.quality.height != null) params['height'] = event.quality.height;
    _emitQualityReport(MovaReportName.qualityChange, params, at);
  }

  void _onAbrDownShift(MovaAbrDownShift event) {
    final at = _now();
    if (!_config.qoe) {
      // 同 _onQualityChange：复用 translateMovaEvent 的 MovaAbrDownShift case。
      final base = translateMovaEvent(event, now: () => at);
      if (base != null) _emit(_withSessionId(base));
      return;
    }
    final params = <String, dynamic>{'from': event.from.label, 'to': event.to.label, 'reason': 'abr'};
    if (event.to.width != null) params['width'] = event.to.width;
    if (event.to.height != null) params['height'] = event.to.height;
    _emitQualityReport(MovaReportName.abrDownShift, params, at);
  }

  /// Emits a quality-related report, enriching it with `fromBps`/`toBps`
  /// asynchronously when a probe is wired (Task 9); emits synchronously
  /// without those keys otherwise.
  ///
  /// 发出一条清晰度相关的上报；接了探针时异步补上 `fromBps`/`toBps`
  /// （Task 9）；否则同步发出、不带这些键。
  void _emitQualityReport(MovaReportName name, Map<String, dynamic> params, DateTime at) {
    final probe = _probe;
    if (probe == null) {
      _emit(_reportEvent(name, params, at, _sessionId));
      return;
    }
    // Captured before the `await` inside _enrichAndEmit — see
    // _emitHeartbeat's doc comment for why this must not read the mutable
    // _sessionId field after an async gap.
    //
    // 在 _enrichAndEmit 内部的 `await` 之前捕获——为何不能在异步间隙之后读取
    // 可变的 _sessionId 字段，见 _emitHeartbeat 的文档注释。
    unawaited(_enrichAndEmit(name, params, at, probe, _sessionId));
  }

  Future<void> _enrichAndEmit(
    MovaReportName name,
    Map<String, dynamic> params,
    DateTime at,
    MovaStatsProbe probe,
    String? sessionId,
  ) async {
    final fromBps = _lastVideoBps;
    final snapshot = await probe.sample();
    final toBps = snapshot?.videoBps;
    if (toBps != null) _lastVideoBps = toBps;
    if (fromBps != null) params['fromBps'] = fromBps;
    if (toBps != null) params['toBps'] = toBps;
    _emit(_reportEvent(name, params, at, sessionId));
  }

  MovaReportEvent _reportEvent(MovaReportName name, Map<String, dynamic> params, DateTime at, String? sessionId) =>
      MovaReportEvent(
        kind: MovaReportKind.event,
        name: name,
        params: params,
        priority: MovaReportPriority.batched,
        at: at,
        sessionId: sessionId,
      );

  /// Internal-only tracking for events that never produce a report of their
  /// own (buffering flaps, duration/quality changes) but feed the QoE
  /// aggregates.
  ///
  /// 部分事件自身从不产出上报（缓冲抖动、时长/清晰度变化），但要喂给 QoE 聚合器
  /// ——这部分内部记账逻辑在此处理。
  void _trackForQoe(MovaEvent event) {
    final at = _now();
    switch (event) {
      case MovaPlay():
        _tally.tick(at);
        // 首帧落地前不计观看时长：失败/迟迟起不来的源 playing 意图为 true，但没在看。
        _playing = true;
        _syncPlaying();
      case MovaPause():
        _tally.tick(at);
        _tally.setPlaying(false);
        _playing = false;
      case MovaDone():
        _completed = true;
        final errAt = _lastFfmpegErrorAt;
        _ffmpegErrorBeforeDone = errAt != null && at.difference(errAt) <= movaTruncationLogWindow;
      case MovaDurationChange(:final duration):
        _tally.setDuration(duration);
      case MovaQualityChange():
        // A manual/ABR variant switch reloads the kernel, which causes its
        // own transient buffering burst — not evidence of a real rebuffer,
        // so the stall tally/index restart here (mirrors MovaEngine's own
        // `_abrPolicy.reset()` on the same transition).
        //
        // 手动/ABR 换档会重载内核，随之而来的短暂缓冲是重载自身的代价，不是
        // 真实卡顿的证据，故在此重启卡顿计数/index（与 MovaEngine 自己在同一
        // 转变点上的 `_abrPolicy.reset()` 同构）。
        _stallPolicy = _config.newStallPolicy();
        _stallIndex = 0;
      case MovaBufferChange(:final buffering):
        // buffering 的下降沿同时是 TTFF 的退化落地信号（当原生
        // MPV_EVENT_PLAYBACK_RESTART 不可达时）——两者都喂，谁先落地谁生效
        // （见 MovaTtffTracker 的 isArmed 守卫，不会重复上报）。
        _onBufferingForTtff(buffering, at);
        // Only used as the degraded rebuffer signal when no MovaStatsProbe
        // is wired; a real probe's `stalling` stream is authoritative and
        // this branch is then redundant but harmless (see _onStalling's
        // dedup via _lastStalled).
        //
        // 仅在未接 MovaStatsProbe 时作为降级的卡顿信号；接了真实探针时其
        // `stalling` 流才是权威来源，这里的分支会变得多余但无害（见
        // _onStalling 借助 _lastStalled 去重）。
        if (_probe == null) _onStallObservation(buffering, at, signal: 'buffering');
      default:
        break;
    }
  }

  /// Falls back to the `buffering`-edge TTFF heuristic (§D1) — used whenever
  /// the native `MPV_EVENT_PLAYBACK_RESTART` signal hasn't landed it first
  /// (see [_onRestart]); [MovaTtffTracker.isArmed] makes whichever signal
  /// arrives first win without double-reporting.
  ///
  /// 退化到 `buffering` 边沿的 TTFF 启发式判定（§D1）——仅在原生
  /// `MPV_EVENT_PLAYBACK_RESTART` 信号尚未先行落地时生效（见 [_onRestart]）；
  /// [MovaTtffTracker.isArmed] 保证无论哪个信号先到都不会重复上报。
  void _onBufferingForTtff(bool buffering, DateTime at) {
    if (!_config.qoe || _nativeRestartLive) return;
    final elapsed = _ttff.onBuffering(buffering, at);
    if (elapsed == null) return;
    _emitFirstFrame(elapsed, at, signal: 'buffering');
  }

  /// Handles a native `MPV_EVENT_PLAYBACK_RESTART` — the precise TTFF landing
  /// signal (2026-09-29 update to §D1).
  ///
  /// 处理一次原生 `MPV_EVENT_PLAYBACK_RESTART`——精确的 TTFF 落地信号（§D1 的
  /// 2026-09-29 更新）。
  void _onRestart() {
    if (!_config.qoe) return;
    final at = _now();
    final elapsed = _ttff.onNativeRestart(at);
    if (elapsed == null) return;
    _emitFirstFrame(elapsed, at, signal: 'restart');
  }

  /// Feeds the tally's playing flag: watch time only accrues once the first
  /// frame has landed (a failing/never-starting source has a `playing` intent
  /// but isn't being watched).
  ///
  /// 同步 tally 的播放态：首帧落地后才计观看时长（失败/起不来的源有 playing
  /// 意图，但并没有在看）。
  /// 原生 RESTART 订阅在工作时，TTFF 只认它（buffering/位置兜底更早但更粗）。
  bool get _nativeRestartLive => _probe?.nativeRestartAvailable ?? false;

  void _syncPlaying() => _tally.setPlaying(_playing && _ttff.landed);

  void _emitFirstFrame(Duration elapsed, DateTime at, {required String signal}) {
    _tally.tick(at);
    _syncPlaying();
    _emit(MovaReportEvent(
      kind: MovaReportKind.event,
      name: MovaReportName.firstFrame,
      params: {
        'ttffMs': elapsed.inMilliseconds,
        'audioOnly': _audioOnly,
        'streamType': _streamType == MovaStreamType.live ? 'live' : 'vod',
        'signal': signal,
      },
      priority: MovaReportPriority.immediate,
      at: at,
      sessionId: _sessionId,
    ));
  }

  /// Handles a native `MPV_EVENT_END_FILE` reason — recorded for
  /// [resolveSessionEndNative] (2026-09-29 update to §D3); an `error` reason
  /// also corroborates [_fatalSeen] directly, in case the paired
  /// `MovaErrorEvent`/log-line classification (§D4) missed it.
  ///
  /// 处理一次原生 `MPV_EVENT_END_FILE` 原因——记录下来供
  /// [resolveSessionEndNative] 使用（§D3 的 2026-09-29 更新）；`error` 原因还
  /// 会直接佐证 [_fatalSeen]，以防配对的 `MovaErrorEvent`/日志行分类
  /// （§D4）漏判。
  void _onEndFile(MovaEndFileReason reason) {
    _lastEndFileReason = reason;
    if (reason == MovaEndFileReason.error) _fatalSeen = true;
  }

  void _onStalling(bool stalled) => _onStallObservation(stalled, _now(), signal: 'cache');

  void _onStallObservation(bool stalled, DateTime at, {required String signal}) {
    if (stalled == _lastStalled) return;
    _lastStalled = stalled;
    if (!_config.qoe) return;
    // Stalls before the first frame are startup latency, not rebuffering —
    // counted by TTFF instead, never both (see §D2).
    //
    // 首帧之前的卡顿属于起播耗时，不是卡顿——由 TTFF 计费，绝不重复计费
    // （见 §D2）。
    if (!_ttff.landed) return;
    _tally.tick(at);
    _tally.setStalled(stalled);
    final policy = _stallPolicy;
    final stall = policy?.onStall(stalled, at);
    if (stall == null) return;
    _stallIndex++;
    _tally.addStall();
    _emit(MovaReportEvent(
      kind: MovaReportKind.event,
      name: MovaReportName.rebuffer,
      params: {
        'durationMs': stall.duration.inMilliseconds,
        'positionMs': _tally.maxPositionMs,
        'index': _stallIndex,
        'signal': signal,
      },
      priority: MovaReportPriority.batched,
      at: at,
      sessionId: _sessionId,
    ));
  }

  void _onLog(MovaLogLine line) {
    if (line.prefix == 'ffmpeg') _lastFfmpegErrorAt = _now();
    _pendingLog = line;
    _pendingLogAt = _now();
  }

  void _onError(MovaErrorEvent event) {
    final at = _now();
    if (!_config.qoe) {
      // Legacy shape: no fatal/code classification, always immediate — this
      // is the byte-for-byte-unchanged path for qoe:false.
      //
      // 旧形状：不做 fatal/code 判定，恒 immediate——这是 qoe:false 时逐字节
      // 不变的路径。
      _emit(MovaReportEvent(
        kind: MovaReportKind.error,
        name: MovaReportName.error,
        params: {'error': event.error.toString()},
        priority: MovaReportPriority.immediate,
        at: at,
      ));
      return;
    }
    String? subsystem;
    final pendingAt = _pendingLogAt;
    final pending = _pendingLog;
    if (pending != null && pendingAt != null && at.difference(pendingAt).abs() <= _errorLogPairWindow) {
      subsystem = pending.prefix;
    }
    _pendingLog = null;
    _pendingLogAt = null;
    final verdict = _errorPolicy.classify(event.error, subsystem: subsystem, afterFirstFrame: _ttff.landed);
    if (verdict.fatal) _fatalSeen = true;
    _emit(MovaReportEvent(
      kind: MovaReportKind.error,
      name: MovaReportName.error,
      params: {'error': event.error.toString(), 'fatal': verdict.fatal, 'code': verdict.code},
      priority: verdict.fatal ? MovaReportPriority.immediate : MovaReportPriority.batched,
      at: at,
      sessionId: _sessionId,
    ));
  }

  MovaReportEvent _withSessionId(MovaReportEvent base) {
    if (!_config.qoe) return base;
    return MovaReportEvent(
      kind: base.kind,
      name: base.name,
      params: base.params,
      priority: base.priority,
      at: base.at,
      sessionId: _sessionId,
    );
  }

  void _emit(MovaReportEvent event) => _reporter.onReport(event);

  /// Cancels every subscription this collector owns.
  ///
  /// 取消该 collector 持有的所有订阅。
  Future<void> cancel() async {
    _heartbeatTimer?.cancel();
    await _sub.cancel();
    await _stallSub?.cancel();
    await _logSub?.cancel();
    await _restartSub?.cancel();
    await _endFileSub?.cancel();
  }
}
