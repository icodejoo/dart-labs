import 'transition.dart';
import '../recovery/fail.dart';
import 'arbiter.dart';
import '../playback_commands.dart';
import 'dart:async';

import 'package:meta/meta.dart' show visibleForTesting;
import '../state/state.dart';
import 'ad_clock.dart';

import '../api.dart';
import '../events/events.dart';
import '../model/ad.dart';
import '../model/source.dart';
import '../options/ad_config.dart';
import '../state/progress.dart';
import '../cutover/ctl.dart';
import '../cutover/acceptance.dart';
import '../cutover/plan.dart';
import '../cutover/trigger.dart';
import '../ad/fail.dart';
import 'timeline.dart';
import 'cursor.dart';
import 'events.dart';
import '../model/playlist.dart';

/// 加载结果；接受只表示首段已接管，不保证首帧。示例：`result == MovaLoadOutcome.accepted`。
enum MovaLoadOutcome {
  /// 首段请求已接受。
  accepted,

  /// 首段请求被拒绝。
  rejected,

  /// 首段打开或解析失败。
  failed,

  /// 被更晚的加载取代。
  superseded,

  /// 会话已销毁。
  disposed,
}

/// 按旧广告入口构造，只使用显式 [cutover]，返回借用 [api] 的会话。
MovaSession movaSessionForAds(MovaApi api, MovaCutover? cutover) =>
    MovaSession._(api, cutover: cutover);

/// 广告薄适配器直接映射首段结果，不增加异步包装或 then 链。
Future<bool> movaAdsLoad(MovaSession session, MovaSource content) => session
    ._loadCore(content, null, null, (o) => o == MovaLoadOutcome.accepted);

/// 惰性广告入口共用相同调用层级与布尔结果映射。
Future<bool> movaAdsLoadDeferred(
  MovaSession session,
  MovaSourceResolver resolve,
) => session._loadCore(
  null,
  resolve,
  null,
  (o) => o == MovaLoadOutcome.accepted,
);

/// 包内结束通知携带发出时纪元，消费者须与当前游标比较。
Stream<int> movaContentEndEpochs(MovaSession session) =>
    session._endedEpochs.stream;

/// 一次广告尝试的结算与续播标记，重试同一广告也必须新建。
class _AdAttempt {
  /// 绑定本次尝试的广告位。
  _AdAttempt(this.node, this.seq, this.play, this.command);

  /// 本次加载请求的起播意图，首次打开失败也不会丢失。
  final bool play;

  /// 开始尝试时的用户播放命令代际。
  final int command;

  /// 本次尝试所属广告位。
  final MovaTimelineNode node;

  /// 本节点的尝试序号。
  final int seq;

  /// 是否已结算失败或拒绝。
  bool failed = false;

  /// 是否已开始续播，永久阻挡该尝试的重复结束信号。
  bool resumed = false;

  /// 打开已接受并落定；此前的首帧和结束属于旧媒体。
  bool opened = false;

  /// 被跳过时仍在途的续播，加载结果须等它结算。
  Future<void>? continuation;
}

/// 一次预热的包内接受结果，普通宿主实现沿用公开 prepare/commit。
class _SessionWarm {
  _SessionWarm(this.ticket, {this.accepted = true, this.owned = false});
  final MovaWarmTicket? ticket;
  final bool accepted;
  final bool owned;
}

/// 编排同一播放器的多条正片及其广告；借用播放器，销毁会话不会销毁播放器。
///
/// 示例：`final session = MovaSession(api, items: episodes); await session.jumpTo(0);`。
class MovaSession {
  /// 创建会话。[api] 为播放器，[ads] 默认取播放器配置；[items] 是条目列表，
  /// [initialIndex] 为初始下标，[autoAdvance] 默认关闭，开启后在全部后贴片结束时换集。
  /// 返回新会话；自动识别 [MovaCutover]，仍遵守其开关。
  /// 示例：`final session = MovaSession(api, items: episodes, autoAdvance: true);`。
  MovaSession(
    MovaApi api, {
    MovaAdConfig? ads,
    List<MovaPlaylistItem> items = const [],
    int initialIndex = 0,
    bool autoAdvance = false,
  }) : this._(
         api,
         ads: ads,
         items: items,
         initialIndex: initialIndex,
         autoAdvance: autoAdvance,
         cutover: api is MovaCutover ? api as MovaCutover : null,
       );

  /// 两个入口共用配置与订阅；广告适配器不自动识别切换能力。
  MovaSession._(
    this._api, {
    this._cutover,
    MovaAdConfig? ads,
    List<MovaPlaylistItem> items = const [],
    int initialIndex = 0,
    bool autoAdvance = false,
  }) : _cfg = ads ?? _api.options.ads,
       _breaks = (ads ?? _api.options.ads).breaks,
       _onAdEvent = (ads ?? _api.options.ads).onAdEvent,
       _enabled = (ads ?? _api.options.ads).enabled {
    setItems(items, initialIndex: initialIndex);
    if (autoAdvance) {
      _endSub = _endedEpochs.stream.listen((epoch) {
        if (epoch == _gen && _index + 1 < _items.length) unawaited(next());
      });
    }
    _eventSub = _api.events.listen(_onEvent);
    _progressSub = _api.progress.listen(_onProgress);
    _lastPlaying = _api.state.playing;
    _stateSub = _api.states.listen(_onState);
  }

  final MovaApi _api;
  final MovaCutover? _cutover;

  /// The ad configuration snapshot this controller runs on.
  ///
  /// 本控制器运行所依据的广告配置快照。
  final MovaAdConfig _cfg;
  List<MovaAdBreak> _breaks;
  final void Function(MovaAdEvent)? _onAdEvent;
  final bool _enabled;
  StreamSubscription<MovaEvent>? _eventSub;
  StreamSubscription<MovaProg>? _progressSub;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final StreamController<void> _contentEnded =
      StreamController<void>.broadcast();
  final StreamController<int> _endedEpochs = StreamController<int>.broadcast();
  final StreamController<Object> _contentError =
      StreamController<Object>.broadcast();

  /// The resolved content source, memoised; null until it has been resolved.
  ///
  /// 已解析的正片源缓存；解析前为 null。
  MovaSource? _content;

  /// The pending resolver for a [loadDeferred] call; null on the plain [load]
  /// path.
  ///
  /// [loadDeferred] 调用留下的待解析器；普通 [load] 路径上为 null。
  MovaSourceResolver? _resolve;

  /// The in-flight resolution, shared by every caller until it settles.
  ///
  /// 在途的解析，在其结算前由所有调用方共享。
  Future<MovaSource?>? _resolving;

  /// Load-session counter; bumped by [load]/[loadDeferred]/[dispose] so async
  /// work started by an older session can tell it is stale after an `await`.
  ///
  /// 加载会话计数；[load]/[loadDeferred]/[dispose] 时递增，使旧会话遗留的异步
  /// 任务在 `await` 之后能认出自己已过期。
  int _gen = 0;

  /// Whether [dispose] has run; late async results must then be dropped.
  ///
  /// [dispose] 是否已执行；之后到达的异步结果必须丢弃。
  bool _disposed = false;
  MovaSessionPhase _phase = MovaSessionPhase.idle;
  MovaTimelineNode? _current;
  final Set<MovaNodeId> _played = <MovaNodeId>{};
  Duration _contentResumeAt = Duration.zero;
  Duration _adPosition = Duration.zero;

  /// Whether the current ad has produced a real first frame (see
  /// [_onAdFirstFrame]); only then is the load deadline cancelled and the
  /// slot clock started.
  ///
  /// 当前广告是否已产出真正的首帧（见 [_onAdFirstFrame]）；到那时才取消加载期限、
  /// 启动广告位时钟。
  bool _adFramed = false;

  /// Last ad-side position seen, for the rising-position fallback.
  ///
  /// 广告侧最近一次位置，供"位置递增"回退判据使用。
  Duration _adLastPos = Duration.zero;

  /// Consecutive rising non-zero position ticks seen for the current ad.
  ///
  /// 当前广告上连续出现的"非零且递增"位置 tick 数。
  int _adRises = 0;

  /// The user's playback rate while content was on screen; restored after an
  /// ad on the cutover path, where the shadow engine would otherwise reset it.
  ///
  /// 正片在屏时的用户倍速；走无缝切换路径时影子引擎会把它重置，广告后据此恢复。
  double _contentRate = 1.0;

  /// The most recent content position seen on the progress stream; the resume
  /// point for a runtime-inserted ad ([playAdNow]).
  ///
  /// 进度流上最近看到的正片位置；运行时插播广告（[playAdNow]）的续播点。
  Duration _lastContentPosition = Duration.zero;

  /// Whether STT recognition was running when the current ad began, so it is
  /// restored only if the host actually had it on.
  ///
  /// 当前广告开始时 STT 识别是否在运行，以便只在宿主本就开启时才恢复。
  bool _sttWasRunning = false;

  /// Enforces [MovaAdBreak.duration] for the ad on screen; null when the
  /// current break has no fixed slot length.
  ///
  /// 为屏幕上的广告落实 [MovaAdBreak.duration]；当前广告位没有固定时长时为 null。
  late final MovaAdClock _slotClock = MovaAdClock(now: () => debugClock());

  /// 续播在途期间保护正片倍速快照；去重由每次尝试独立负责。
  bool get _resuming => _resumeDepth > 0;

  /// 当前加载代际内嵌套续播的深度，用于保护正片倍速快照。
  int _resumeDepth = 0;

  /// 当前广告尝试；异步返回只可结算自己捕获的尝试。
  _AdAttempt? _adAttempt;

  /// 打开或提交落定前，旧媒体的结束、错误、首帧和进度不归新节点所有。
  bool _landing = false;
  Future<_SessionWarm?>? _adWarm;
  Future<_SessionWarm?>? _contentWarm;
  int _supersededEpoch = -1;

  Future<_SessionWarm?> _warm(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
    bool? play,
  }) async {
    final cutover = _cutover!;
    if (cutover is MovaWarmOwner) {
      final ticket = await (cutover as MovaWarmOwner).prepareOwned(
        source,
        at: at,
        cue: cue,
        plan: plan,
        play: play,
      );
      return _SessionWarm(
        ticket,
        accepted: ticket?.rejected != true,
        owned: true,
      );
    }
    if (cutover is MovaCutoverAcceptance) {
      final accepted = await (cutover as MovaCutoverAcceptance).prepareAccepted(
        source,
        at: at,
        cue: cue,
        plan: plan,
      );
      return _SessionWarm(null, accepted: accepted);
    }
    await cutover.prepare(source, at: at, cue: cue, plan: plan);
    return _SessionWarm(null);
  }

  Future<MovaWarmCommit> _commit(_SessionWarm? warm) async {
    if (warm == null) return MovaWarmCommit.notReady;
    if (warm.owned) {
      final ticket = warm.ticket;
      if (ticket == null) return MovaWarmCommit.notReady;
      return (_cutover as MovaWarmOwner).commitOwned(
        ticket,
        waitForReady: true,
      );
    }
    return await _cutover!.commit(waitForReady: true)
        ? MovaWarmCommit.committed
        : MovaWarmCommit.notReady;
  }

  /// 宿主抢源仅使会话让位，不放弃或覆盖宿主的新影子。
  void _superseded() {
    _supersededEpoch = _gen;
    _landing = false;
    _cancelAllTimers();
    _pending = null;
    _current = null;
    _onScreen = null;
    _phase = MovaSessionPhase.idle;
    _changes.add(null);
  }

  /// The break counting down / warming up in [MovaSessionPhase.pending].
  ///
  /// [MovaSessionPhase.pending] 阶段正在倒计时 / 预热中的广告位。
  MovaTimelineNode? _pending;

  /// Fires when the pending break's [MovaAdBreak.delay] runs out; null when
  /// the pending break has no visible countdown.
  ///
  /// 待播广告位的 [MovaAdBreak.delay] 走完时触发；该广告位没有可见倒计时时为 null。
  late final MovaAdClock _delayClock = MovaAdClock(now: () => debugClock());

  /// 测试时钟，返回当前时刻；示例：`session.debugClock = () => origin;`。
  @visibleForTesting
  DateTime Function() debugClock = DateTime.now;

  /// 播放观测订阅，只按边沿控制当前阶段的时钟。
  StreamSubscription<MovaState>? _stateSub;

  /// 上次播放观测，不从播放意图推断。
  late bool _lastPlaying;

  /// 当前阶段需要控制的广告时钟。
  MovaAdClock? _clockFor() => switch (_phase) {
    MovaSessionPhase.ad => _slotClock,
    MovaSessionPhase.pending => _delayClock,
    _ => null,
  };

  /// 按播放观测的升降沿恢复或暂停当前时钟。
  void _onState(MovaState state) {
    final was = _lastPlaying;
    _lastPlaying = state.playing;
    if (was && !state.playing) {
      _clockFor()?.pause();
    } else if (!was && state.playing) {
      _clockFor()?.resume();
    }
  }

  /// 用户没有播放意图时，以暂停态起表。
  void _holdIfPaused(MovaAdClock clock) {
    if (!_api.state.playbackIntent) clock.pause();
  }

  /// Fires when the current ad produced no first frame in time.
  ///
  /// 当前广告未能及时产出首帧时触发。
  Timer? _loadTimer;

  /// Attempt counter per break, fed to [MovaAdFailPolicy]; cleared per load.
  ///
  /// 每条广告位的尝试次数计数，喂给 [MovaAdFailPolicy]；每次加载时清空。
  final Map<MovaNodeId, int> _attempts = <MovaNodeId, int>{};

  /// 返回广告是否在屏；示例：`session.isShowingAd`。
  bool get isShowingAd => _phase == MovaSessionPhase.ad;

  /// 返回在屏广告，无则 null；示例：`session.currentBreak?.source`。
  MovaAdBreak? get currentBreak => _current?.adBreak;

  /// 返回是否有待播中插；示例：`session.isAdPending`。
  bool get isAdPending => _phase == MovaSessionPhase.pending;

  /// 返回待播广告，无则 null；示例：`session.pendingBreak?.delay`。
  MovaAdBreak? get pendingBreak => _pending?.adBreak;

  /// 返回倒计时剩余，无倒计时则 null；示例：`session.delayRemaining?.inSeconds`。
  Duration? get delayRemaining {
    final b = _pending?.adBreak;
    if (b == null || b.delay <= Duration.zero) return null;
    return _delayClock.remaining ?? Duration.zero;
  }

  /// 返回广告已播位置；示例：`session.adPosition.inSeconds`。
  Duration get adPosition => _adPosition;

  /// 返回当前广告是否可跳过；示例：`if (session.canSkip) session.skip();`。
  bool get canSkip {
    final after = _current?.adBreak?.skippableAfter;
    return after != null && _adPosition >= after;
  }

  /// 返回距离可跳过的时长，无跳过能力则 null；示例：`session.skipIn?.inSeconds`。
  Duration? get skipIn {
    final after = _current?.adBreak?.skippableAfter;
    if (after == null) return null;
    final remaining = after - _adPosition;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// 返回阶段与广告变化的广播流；示例：`session.changes.listen((_) => rebuild());`。
  Stream<void> get changes => _changes.stream;

  /// 返回正片及全部后贴片结束的广播流；示例：`session.contentEnded.listen((_) => next());`。
  Stream<void> get contentEnded => _contentEnded.stream;

  /// 返回解析失败、正片 open 异常与终结错误的广播流；恢复开启时等待放弃恢复。
  /// 示例：`session.contentError.listen(showRetry);`。
  Stream<Object> get contentError => _contentError.stream;

  /// 加载 [content]，使用 [breaks] 或配置排期，返回本次首段接受结果。
  /// 接受不保证首帧；示例：`final result = await session.load(source, breaks: []);`。
  Future<MovaLoadOutcome> load(
    MovaSource content, {
    List<MovaAdBreak>? breaks,
  }) => _loadCore(content, null, breaks, (o) => o);

  /// 按需调用 [resolve] 解析正片，使用 [breaks] 或配置排期，返回首段接受结果。
  /// 示例：`await session.loadDeferred(() async => source);`。
  Future<MovaLoadOutcome> loadDeferred(
    MovaSourceResolver resolve, {
    List<MovaAdBreak>? breaks,
  }) => _loadCore(null, resolve, breaks, (o) => o);

  /// 共用原加载调用层级，在返回点映射结果，不增加 Future 转换微任务。
  Future<T> _loadCore<T>(
    MovaSource? content,
    MovaSourceResolver? resolve,
    List<MovaAdBreak>? breaks,
    T Function(MovaLoadOutcome) map, {
    int? item,
  }) async {
    if (_disposed) return map(MovaLoadOutcome.disposed);
    _endNode(MovaNodeEndReason.superseded);
    final gen = ++_gen;
    _epochItem = item ?? _index;
    _runtimeOrdinal = 0;
    _resolving = null;
    _content = content;
    _resolve = resolve;
    _breaks = List.unmodifiable(breaks ?? _cfg.breaks);
    _nodes = movaBuildNodes(_epochItem, _breaks);
    await _beginLoad();
    while (gen == _gen && !_disposed) {
      final attempt = _adAttempt;
      final continuation = attempt?.continuation;
      if (continuation == null) break;
      await continuation;
      if (identical(attempt, _adAttempt)) break;
    }
    return map(
      _disposed
          ? MovaLoadOutcome.disposed
          : gen != _gen || _supersededEpoch == gen
          ? MovaLoadOutcome.superseded
          : _acceptedEpoch == gen
          ? MovaLoadOutcome.accepted
          : _failedEpoch == gen
          ? MovaLoadOutcome.failed
          : MovaLoadOutcome.rejected,
    );
  }

  /// 当前条目列表的只读快照；示例：`session.items.length` 返回集数。
  List<MovaPlaylistItem> get items => _items;

  /// 当前游标快照；示例：`session.cursor.phase` 返回当前阶段。
  MovaCursor get cursor => MovaCursor(
    epoch: _gen,
    item: _index,
    node: _phase == MovaSessionPhase.pending ? _pending?.id : _onScreen,
    phase: _phase,
    contentResumeAt: _contentResumeAt,
  );

  /// 以 [items] 替换列表，将 [initialIndex] 夹到有效范围；不打开内容，无返回值。
  /// 示例：`session.setItems(episodes, initialIndex: 1);`。
  void setItems(List<MovaPlaylistItem> items, {int initialIndex = 0}) {
    _itemsGeneration++;
    _items = List.unmodifiable(items);
    _index = items.isEmpty ? 0 : initialIndex.clamp(0, items.length - 1);
  }

  /// 打开 [index] 条目及其排期，返回接受结果；越界返回 rejected，拒绝不改下标。
  /// 示例：`await session.jumpTo(1);`。
  Future<MovaLoadOutcome> jumpTo(int index) async {
    if (_disposed) return MovaLoadOutcome.disposed;
    if (index < 0 || index >= _items.length) return MovaLoadOutcome.rejected;
    final itemsGeneration = _itemsGeneration;
    final item = _items[index];
    final loading = _loadCore(
      item.source,
      null,
      item.adBreaks,
      (o) => o,
      item: index,
    );
    final gen = _gen;
    final outcome = await loading;
    if (itemsGeneration != _itemsGeneration) return MovaLoadOutcome.superseded;
    if (outcome == MovaLoadOutcome.accepted && gen == _gen && !_disposed) {
      _index = index;
      _sessionEvents.add(MovaItemChange(_gen, index));
      _changes.add(null);
    }
    return outcome;
  }

  /// 打开下一项，返回接受结果；末尾返回 rejected。示例：`await session.next();`。
  Future<MovaLoadOutcome> next() => jumpTo(_index + 1);

  /// 打开上一项，返回接受结果；开头返回 rejected。示例：`await session.previous();`。
  Future<MovaLoadOutcome> previous() => jumpTo(_index - 1);

  /// 返回会话节点与条目事件广播流；示例：`session.events.listen(print);`。
  Stream<MovaSessionEvent> get events => _sessionEvents.stream;

  /// 独立事件控制器与当前在屏身份。
  final StreamController<MovaSessionEvent> _sessionEvents =
      StreamController.broadcast();
  MovaNodeId? _onScreen;

  /// 当前纪元条目、排期节点与插播序号。
  int _epochItem = 0;
  int _runtimeOrdinal = 0;
  int _attemptSeq = 0;
  List<MovaTimelineNode> _nodes = const [];

  /// 记录节点开始；正片续播与广告尝试均由实际接管点调用。
  void _startNode(MovaNodeId node) {
    _onScreen = node;
    _sessionEvents.add(MovaNodeStart(_gen, node));
  }

  /// 结束在屏节点，每次开始只发一次结束。
  void _endNode(MovaNodeEndReason reason) {
    final node = _onScreen;
    if (node == null) return;
    _onScreen = null;
    _sessionEvents.add(MovaNodeEnd(_gen, node, reason));
  }

  /// 条目快照与已接受下标。
  List<MovaPlaylistItem> _items = const [];
  int _index = 0;
  int _itemsGeneration = 0;

  /// 本次已接受或失败的纪元；跨加载不复用。
  int _acceptedEpoch = -1;
  int _failedEpoch = -1;

  /// 同一纪元、节点、尝试的失败仅允许结算一次。
  final Set<(int, MovaNodeId, int)> _settled = {};
  int _contentAttempt = 0;

  /// 直接构造时可选的自动前进订阅。
  StreamSubscription<int>? _endSub;

  /// The shared start-of-playback path for [load] and [loadDeferred]: resets
  /// per-load bookkeeping, then plays the first pre-roll or the content.
  ///
  /// [load] 与 [loadDeferred] 共用的起播路径：重置每次加载的簿记，然后播放第一条
  /// 前贴片或正片。
  Future<void> _beginLoad() async {
    if (_disposed) return;
    // 换集的同步前缀先取消旧计时与影子，避免新正片提交到旧源。
    _cancelAllTimers();
    _pending = null;
    _resumeDepth = 0;
    _adAttempt = null;
    _adWarm = null;
    _contentWarm = null;
    _landing = false;
    unawaited(_cutover?.abandon());
    _played.clear();
    _attempts.clear();
    _settled.clear();
    _contentResumeAt = Duration.zero;
    _lastContentPosition = Duration.zero;
    // Fail loudly on a misconfigured schedule, on developer machines only.
    //
    // 配错的排期要大声失败，且只在开发者机器上。
    for (final b in _breaks) {
      b.assertValid();
    }
    if (_enabled) {
      final pre = _firstOfKind(MovaAdBreakKind.pre);
      if (pre != null) {
        await _playAd(pre, autoPlay: true);
        return;
      }
    }
    await _playContent(autoPlay: true);
  }

  /// Returns the content source, resolving and memoising it on first use.
  ///
  /// Returns null when there is nothing to resolve, or when the host's
  /// resolver failed — in which case the failure has already been reported on
  /// [contentError] and the lazy slot has been reset so a later
  /// [loadDeferred] can retry.
  ///
  /// 返回正片源，首次使用时解析并记忆化。
  ///
  /// 无可解析内容、或宿主的解析器失败时返回 null——后者已经把失败上报到
  /// [contentError]，并重置了惰性槽，使之后的 [loadDeferred] 能重试。
  Future<MovaSource?> _contentSource() {
    final cached = _content;
    if (cached != null) return Future<MovaSource?>.value(cached);
    final resolve = _resolve;
    if (resolve == null) return Future<MovaSource?>.value(null);
    // Share one in-flight resolution: the warm-up path calls this on every
    // progress tick, and the host's resolver must still be called exactly once.
    //
    // 共享同一次在途解析：预热路径每个进度 tick 都会调用本方法，而宿主的解析器
    // 仍必须恰好只被调用一次。
    return _resolving ??= _doResolve(resolve, _gen);
  }

  /// Runs [resolve] once, memoising the result and clearing the in-flight slot.
  ///
  /// 执行一次 [resolve]，记忆化结果并清空在途槽位。
  Future<MovaSource?> _doResolve(MovaSourceResolver resolve, int gen) async {
    try {
      final resolved = await resolve();
      // A stale session's result is dropped: it must not write [_content].
      //
      // 过期会话的结果直接丢弃，不得写入 [_content]。
      if (gen != _gen || _disposed) return null;
      _content = resolved;
      return resolved;
    } catch (e) {
      if (gen != _gen || _disposed) return null;
      _resolve = null;
      _contentUnavailable(e);
      return null;
    } finally {
      if (gen == _gen) _resolving = null;
    }
  }

  /// 在正片中插播 [ad]，返回本次打开完成的 Future；待播或广告中为空操作。
  /// 示例：`await session.playAdNow(ad);`。
  Future<void> playAdNow(MovaAdBreak ad) async {
    // A no-op while one is already queued: only one ad may be pending at a
    // time, and cancelling a queued ad is a host product decision, not the
    // player's.
    //
    // 已经有一条在排队时为空操作：同一时刻只允许一条待播广告，而取消一条已排队
    // 的广告是宿主的产品决策，不是播放器的。
    if (_phase != MovaSessionPhase.content) return;
    final node = MovaTimelineNode(
      MovaNodeId(_epochItem, switch (ad.kind) {
        MovaAdBreakKind.pre => MovaNodeKind.pre,
        MovaAdBreakKind.mid => MovaNodeKind.mid,
        MovaAdBreakKind.post => MovaNodeKind.post,
      }, --_runtimeOrdinal),
      ad,
      ad.offset,
    );
    _contentResumeAt = _lastContentPosition;
    // Snapshot the user's rate now: it is otherwise only refreshed by content
    // progress ticks, so a change made since the last tick would be lost.
    // Skipped while returning from an ad, when the engine may still be the 1x ad.
    //
    // 此刻同步快照用户倍速：它平时只由正片进度 tick 刷新，上一个 tick 之后的改动
    // 会丢。从广告返回的过渡期内活动引擎可能仍是 1x 的广告，因此跳过。
    if (!_resuming) _contentRate = _api.state.rate;
    if (ad.delay > Duration.zero || _wantsWait(ad)) {
      _beginDelay(node);
      return;
    }
    await _playAd(node);
  }

  /// 跳过可跳过的广告，无返回值；示例：`session.skip();`。
  void skip() {
    if (_phase != MovaSessionPhase.ad || !canSkip) return;
    final b = _current!;
    final seq = _adAttempt!.seq;
    _fire(MovaAdEventType.skipped, b);
    unawaited(_resumeAfterAd(b, attemptSeq: seq));
  }

  /// 通知当前广告的点击钩子，无返回值；示例：`session.notifyClicked();`。
  void notifyClicked() {
    final b = _current;
    if (b != null) _fire(MovaAdEventType.clicked, b);
  }

  /// Returns the next unplayed mid-roll inserted at the same point as the one
  /// that just finished, or null when the pod is exhausted.
  ///
  /// "The same point" means an offset at or before the current resume
  /// position — that is what makes two breaks one pod. Later mid-rolls are
  /// deliberately excluded: chaining into those would not be a pod, it would
  /// be playing the rest of the schedule back to back.
  ///
  /// 返回与刚播完那条插在同一位置的下一条未播中插；pod 已耗尽时返回 null。
  ///
  /// "同一位置"指 offset 不晚于当前续播点——这正是两条广告算作同一个 pod 的
  /// 定义。更晚的中插被刻意排除：串到那些上去就不是 pod 了，而是把剩下的排期
  /// 一口气连播完。
  MovaTimelineNode? _nextPodMid() =>
      movaDueMid(_nodes, _contentResumeAt, _played);

  /// Returns the first not-yet-played break of [kind], or null.
  ///
  /// 返回首个尚未播放的、类型为 [kind] 的广告位；没有则为 null。
  MovaTimelineNode? _firstOfKind(MovaAdBreakKind kind) => movaFirstWhere(
    _nodes,
    (n) => n.adBreak?.kind == kind && !_played.contains(n.id),
  );

  /// Whether [b] should be warmed up and cut to only once it is ready.
  ///
  /// Waiting needs somewhere to warm up in; with no cutover engine the whole
  /// question is moot and the per-kind default never even gets consulted. The
  /// three-layer override (break → injected policy → per-kind default) lives
  /// entirely inside [MovaAdConfig.waitsFor] — this controller must never
  /// branch on [MovaAdBreakKind] itself, or the host's override would become
  /// unreachable.
  ///
  /// [b] 是否应当先预热、待其就绪后才切入。
  ///
  /// 等待需要一个可供预热之处；没有切换引擎时这个问题根本不成立，按类型的
  /// 默认值压根不会被查询。三层覆盖（广告位 → 注入策略 → 按 kind 默认）完全封在
  /// [MovaAdConfig.waitsFor] 里——本控制器绝不自行对 [MovaAdBreakKind] 分支，
  /// 否则宿主的覆盖就绕不过去了。
  bool _wantsWait(MovaAdBreak b) {
    final cutover = _cutover;
    return cutover != null && cutover.cutoverEnabled && _cfg.waitsFor(b);
  }

  /// Enters [MovaSessionPhase.pending] for [b]: the content plays on while the countdown
  /// runs and/or the ad warms up in the background.
  ///
  /// [b] is marked played immediately so the countdown window cannot keep
  /// re-matching it on every tick.
  ///
  /// 为 [b] 进入 [MovaSessionPhase.pending]：倒计时走动和/或广告后台预热期间，正片继续播放。
  ///
  /// [b] 会被立刻标记为已播，使倒计时窗口内不会每个 tick 都重复命中它。
  void _beginDelay(MovaTimelineNode node) {
    final gen = _gen;
    final b = node.adBreak!;
    _phase = MovaSessionPhase.pending;
    _pending = node;
    _adWarm = null;
    _played.add(node.id);
    _cancelDelayTimer();
    _fire(MovaAdEventType.pending, node);
    _changes.add(null);
    // Only a host-configured delay produces a countdown timer. With no delay
    // the pending phase is entered and left in one go, and the readiness wait
    // (if any) happens inside [_beginAd] — so "at least the countdown, at most
    // the countdown plus the readiness timeout" holds either way.
    //
    // 只有宿主配置的 delay 才会起倒计时定时器。没有 delay 时待播阶段进入即离开，
    // 就绪等待（若有）发生在 [_beginAd] 内部——因此"至少走完倒计时、最多再加一个
    // 就绪超时"这条在两种情形下都成立。
    if (b.delay > Duration.zero) {
      _delayClock.start(b.delay, () {
        if (gen != _gen ||
            _phase != MovaSessionPhase.pending ||
            _pending?.id != node.id) {
          return;
        }
        unawaited(_beginAd(node));
      });
      _holdIfPaused(_delayClock);
    } else {
      unawaited(_beginAd(node));
    }
  }

  /// Cancels the delay countdown timer, if one is running.
  ///
  /// 取消倒计时定时器（若有）。
  void _cancelDelayTimer() {
    _delayClock.cancel();
  }

  /// Hands the screen over to [b] once its pending phase is done: commits the
  /// warmed shadow when the break waits for readiness, otherwise cuts to it
  /// the way it always has.
  ///
  /// When the commit fails (nothing was warm, or the readiness policy timed
  /// out), [MovaAdConfig.notReadyAction] decides between a hard cut — today's
  /// behaviour, which the fallback must reproduce — and dropping the break so
  /// the content is never interrupted.
  ///
  /// 待播阶段结束后把画面交给 [b]：该广告位要等待就绪时提交预热好的影子，否则
  /// 按一贯方式直接切入。
  ///
  /// 提交失败（压根没预热上，或就绪判据超时）时，由
  /// [MovaAdConfig.notReadyAction] 在硬切（今天的行为，降级必须重现它）与丢弃该
  /// 广告位（正片完全不被打断）之间裁决。
  Future<void> _beginAd(MovaTimelineNode node) async {
    final b = node.adBreak!;
    final gen = _gen;
    if (_disposed) return;
    final attempt = _adAttempt = _AdAttempt(
      node,
      ++_attemptSeq,
      _api.state.playbackIntent,
      movaPlaybackCommand(_api),
    );
    _cancelDelayTimer();
    if (!_wantsWait(b)) {
      _pending = null;
      await _playAd(node, ownedAttempt: attempt);
      if (gen != _gen || _disposed) return;
      return;
    }
    // Make sure a warm-up actually exists before committing. With a countdown
    // the progress ticks have been warming all along and this is a no-op; with
    // no countdown (the default mid-roll shape) this *is* the warm-up, and the
    // whole wait then happens inside the commit below.
    //
    // 提交之前先确保真的有一次预热存在。有倒计时时，进度 tick 一路都在预热，这里
    // 是空操作；没有倒计时时（中插的默认形态），这里*就是*那次预热，随后整段等待
    // 都发生在下面的 commit 里。
    final bool committed;
    try {
      _landing = true;
      final warm = await (_adWarm ??= _warm(
        b.source,
        plan: movaAdWarmPlan(_cfg),
      ));
      if (gen != _gen || _disposed || !identical(_adAttempt, attempt)) return;
      if (warm?.accepted == false) {
        _pending = null;
        _played.add(node.id);
        await _rejectAd(node, attempt);
        return;
      }
      final result = await _commit(warm);
      if (gen != _gen || _disposed) return;
      if (result == MovaWarmCommit.superseded) {
        _superseded();
        return;
      }
      committed = result == MovaWarmCommit.committed;
    } catch (e) {
      if (gen != _gen || _disposed) return;
      _landing = false;
      _pending = null;
      await _onAdFailure(node, MovaAdFailKind.openThrew, e, attempt);
      return;
    }
    if (gen == _gen) _landing = false;
    if (committed) {
      _pending = null;
      await _playAd(node, alreadyOnScreen: true, ownedAttempt: attempt);
      if (gen != _gen || _disposed) return;
      return;
    }
    switch (_cfg.notReadyAction) {
      case MovaAdNotReady.hardCut:
        _pending = null;
        await _playAd(node, ownedAttempt: attempt);
        if (gen != _gen || _disposed) return;
      case MovaAdNotReady.dropBreak:
        // Deliberately not routed through the failure policy: notReadyAction
        // is already the verdict at this layer, and stacking two policies here
        // would make the behaviour impossible to reason about.
        //
        // 刻意不走失败兜底策略：notReadyAction 已经是这一层的裁决，在此叠加第二层
        // 策略会让行为变得无法推理。
        _fire(MovaAdEventType.failed, node, error: MovaAdFailKind.warmFailed);
        _abandonPending();
    }
  }

  /// Drops the pending break and hands the screen back to the content, which
  /// has been playing all along.
  ///
  /// 丢弃待播广告位，把画面交还给一直在播的正片。
  void _abandonPending() {
    _cancelDelayTimer();
    _pending = null;
    _phase = MovaSessionPhase.content;
    unawaited(_cutover?.abandon());
    _changes.add(null);
  }

  /// Switches playback to ad break [b].
  ///
  /// [alreadyOnScreen] means a warmed shadow engine has just been promoted and
  /// is already showing [b], so no `open()` is issued and the shadow is not
  /// abandoned — but every piece of phase bookkeeping still runs, because
  /// taking the seamless path must never silently skip an event or a state
  /// update.
  ///
  /// 把播放切换到广告位 [b]。
  ///
  /// [alreadyOnScreen] 表示一个预热好的影子引擎刚刚转正、画面上已经是 [b]，因此
  /// 不下发 `open()`、也不拆掉该影子——但所有阶段簿记照常执行，因为走了无缝路径
  /// 绝不能悄悄漏掉任何一个事件或状态更新。
  Future<void> _playAd(
    MovaTimelineNode node, {
    bool alreadyOnScreen = false,
    bool? autoPlay,
    _AdAttempt? ownedAttempt,
  }) async {
    final b = node.adBreak!;
    final gen = _gen;
    if (_disposed) return;
    // 未指定时继承调用入口的用户播放意图。
    final play = autoPlay ?? _api.state.playbackIntent;
    final attempt = _adAttempt =
        ownedAttempt ??
        _AdAttempt(node, ++_attemptSeq, play, movaPlaybackCommand(_api));
    _landing = false;
    _contentWarm = null;

    /// 旧尝试的迟到结果不能结算或覆盖新尝试。
    bool current() =>
        gen == _gen &&
        !_disposed &&
        identical(_adAttempt, attempt) &&
        !attempt.failed &&
        !attempt.resumed;

    _cancelSlotTimer();
    _cancelLoadTimer();
    final oneShot =
        !alreadyOnScreen && _phase != MovaSessionPhase.pending && _wantsWait(b);
    // Suppress content-side STT while the ad plays; restore it on resume only
    // if the host actually had it running (attach() does not reset it). Only
    // sample `stt.isRunning` on the *first* ad of a pod (_phase isn't already
    // `ad`) — a chained ad-to-ad call (see [_resumeAfterAd]) would otherwise
    // re-read it after the previous ad already stopped STT, permanently
    // losing the "was running before the pod" flag.
    //
    // 广告播放期间抑制正片侧 STT；仅当宿主本就在运行时才在续播时恢复
    // （attach() 不会重置它）。只在 pod 的*第一条*广告上采样
    // `stt.isRunning`（`_phase` 尚不是 `ad`）——被串联调用的广告到广告
    // （见 [_resumeAfterAd]）若也重新采样，会读到上一条广告已经停掉 STT 之后的
    // 状态，永久丢失"pod 开始前是否在跑"这个标记。
    if (_phase != MovaSessionPhase.ad) {
      _sttWasRunning = _api.stt.isRunning;
      if (_sttWasRunning) unawaited(_api.stt.stop());
    }
    _phase = MovaSessionPhase.ad;
    _current = node;
    _adPosition = Duration.zero;
    _adFramed = false;
    _adLastPos = Duration.zero;
    _adRises = 0;
    _played.add(node.id);
    _changes.add(null);
    _fire(MovaAdEventType.started, node);
    _landing = !alreadyOnScreen;
    try {
      if (oneShot) {
        unawaited(_cutover!.abandon());
        final warm = await _warm(
          b.source,
          plan: movaAdWarmPlan(_cfg),
          play: movaPlaybackCommand(_api) == attempt.command
              ? play
              : _api.state.playbackIntent,
        );
        if (!current()) return;
        if (warm?.accepted == false) {
          await _rejectAd(node, attempt);
          return;
        }
        final result = await _commit(warm);
        if (!current()) return;
        if (result == MovaWarmCommit.superseded) {
          _superseded();
          return;
        }
        if (result != MovaWarmCommit.committed) {
          final accepted = await _api.open(
            b.source,
            autoPlay: movaPlaybackCommand(_api) == attempt.command
                ? play
                : _api.state.playbackIntent,
          );
          if (!current()) return;
          if (!accepted) {
            await _rejectAd(node, attempt);
            return;
          }
        }
      } else if (!alreadyOnScreen) {
        unawaited(_cutover?.abandon());
        final accepted = await _api.open(b.source, autoPlay: play);
        if (!current()) return;
        if (!accepted) {
          await _rejectAd(node, attempt);
          return;
        }
      }
    } catch (e) {
      if (!current()) return;
      _landing = false;
      await _onAdFailure(node, MovaAdFailKind.openThrew, e, attempt);
      return;
    } finally {
      if (gen == _gen && identical(_adAttempt, attempt)) _landing = false;
    }
    // Nothing on screen yet: give the ad a bounded window to produce its first
    // frame, cancelled by that frame's own progress tick.
    //
    // 画面上还什么都没有：给广告一个有界的窗口去产出首帧，该窗口由首帧自己的
    // 进度 tick 取消。
    // Ticks seen before open() settled are leftovers of the previous media.
    //
    // open() 落定之前收到的 tick 是上一段媒体的残留。
    //
    // Same for first-frame signals: while open()/prepare→commit was awaiting, the old
    // engine could still tick (phase is already `ad`) and flip [_adFramed], which
    // would make the ad's real first frame a no-op and orphan the load timer.
    // Drop that verdict (and any slot clock it started), then re-read the
    // settled state: already rendered → first frame now, else arm the deadline.
    //
    // 首帧信号同理：open()/prepare→commit 等待期间旧引擎仍可能 tick（此时阶段已是 `ad`）
    // 并把 [_adFramed] 置位，导致广告真正的首帧被忽略、加载计时器无人取消。丢弃该判定
    // （及由它起的广告位时钟），再读落定后的状态：已渲染则立即判首帧，否则起期限。
    if (!current()) return;
    _acceptedEpoch = gen;
    attempt.opened = true;
    _adRises = 0;
    _adLastPos = Duration.zero;
    _adFramed = false;
    _cancelSlotTimer();
    if (_api.state.rendered) {
      _onAdFirstFrame();
    } else {
      _armLoadTimer(node);
    }
    // An ad must not play sped up. Cutover landings already start the ad at 1x
    // (MovaWarmPlan.rate); this is the safety net for the paths that bypass it
    // — prepare/commit falling back to a plain open() on the user's engine, or a host
    // adWarmPlan without a rate.
    //
    // 广告不应变速。走无缝落地时广告已按 1x 起步（MovaWarmPlan.rate）；这里是
    // 绕过它的路径的兜底——prepare/commit 回落成在用户引擎上的普通 open()，或宿主自定义
    // 的 adWarmPlan 没带 rate。
    final cutover = _cutover;
    if (cutover != null && cutover.cutoverEnabled && _api.state.rate != 1.0) {
      unawaited(_api.setRate(1.0));
    }
    // With durationFromFirstFrame off the slot is counted from open(); with it
    // on, the first progress tick arms the timer instead.
    //
    // durationFromFirstFrame 关闭时广告位从 open() 起算；开启时改由第一个进度
    // tick 起表。
    if (!_cfg.durationFromFirstFrame) _armSlotTimer(node);
  }

  /// Starts the fixed-length slot timer for [b], if it has a
  /// [MovaAdBreak.duration] and one is not already running.
  ///
  /// The deadline is a plain [Timer]: the media timeline is never consulted
  /// and never seeked, because a large file's duration can take a long time to
  /// resolve on a real mobile network and a seek near the real EOF reliably
  /// wedges the player on device.
  ///
  /// 为 [b] 起固定时长的广告位定时器——前提是它有 [MovaAdBreak.duration] 且尚未
  /// 起表。
  ///
  /// 到期判定是一个普通 [Timer]：完全不查询、不 seek 媒体时间轴，因为大文件的
  /// 时长在真机移动网络下可能很久解析不出来，而靠近真实 EOF 的 seek 在真机上会
  /// 可靠地把播放器卡死。
  void _armSlotTimer(MovaTimelineNode node) {
    final b = node.adBreak!;
    final seq = _adAttempt!.seq;
    final d = b.duration;
    if (d == null || _slotClock.remaining != null) return;
    _slotClock.start(d, () {
      if (_phase != MovaSessionPhase.ad ||
          (_current?.id != node.id || _adAttempt?.seq != seq)) {
        return;
      }
      // The slot the advertiser bought has been delivered in full, so this is
      // a completion, not a skip.
      //
      // 广告主买下的这段时长已经足额交付，因此这是"播完"，不是"跳过"。
      _fire(MovaAdEventType.completed, node);
      unawaited(_resumeAfterAd(node, attemptSeq: seq));
    });
    _holdIfPaused(_slotClock);
  }

  /// Cancels any running slot timer.
  ///
  /// 取消正在运行的广告位定时器（若有）。
  void _cancelSlotTimer() {
    _slotClock.cancel();
  }

  /// Starts the no-first-frame deadline for [b].
  ///
  /// 为 [b] 起"始终没有首帧"的判定期限。
  void _armLoadTimer(MovaTimelineNode node) {
    final seq = _adAttempt!.seq;
    _cancelLoadTimer();
    _loadTimer = Timer(_cfg.loadTimeout, () {
      if (_phase != MovaSessionPhase.ad ||
          (_current?.id != node.id || _adAttempt?.seq != seq)) {
        return;
      }
      unawaited(_onAdFailure(node, MovaAdFailKind.loadTimeout));
    });
  }

  /// Cancels the no-first-frame deadline, if one is running.
  ///
  /// 取消"始终没有首帧"的判定期限（若有）。
  void _cancelLoadTimer() {
    _loadTimer?.cancel();
    _loadTimer = null;
  }

  /// Cancels all three timers (slot/load/delay) at once.
  ///
  /// Shared by the three call sites that always tear down every timer
  /// together ([_playContent]/[_goIdleAfterContent]/[dispose]); a lone timer
  /// may still be cancelled on its own elsewhere via its individual method.
  ///
  /// 一次性取消全部三个定时器（广告位/加载/倒计时）。
  ///
  /// 供总是同时清空全部定时器的三处调用共用（[_playContent]/
  /// [_goIdleAfterContent]/[dispose]）；其他地方仍可经各自独立方法单独取消
  /// 某一个定时器。
  void _cancelAllTimers() {
    _cancelSlotTimer();
    _cancelLoadTimer();
    _cancelDelayTimer();
  }

  /// 宿主拒绝直接跳过该广告位，和普通 open 的拒绝行为一致。
  Future<void> _rejectAd(MovaTimelineNode node, _AdAttempt attempt) async {
    if (_disposed ||
        !identical(_adAttempt, attempt) ||
        attempt.failed ||
        attempt.resumed) {
      return;
    }
    attempt.failed = true;
    _fire(MovaAdEventType.failed, node);
    await _resumeAfterAd(node, attemptSeq: attempt.seq);
  }

  /// Applies [MovaAdConfig.failPolicy] to a break that would not play.
  ///
  /// Every failure route — a throwing `open()`, a player error during the ad,
  /// and a missing first frame — converges here, so the host's policy sees one
  /// consistent stream of attempts. A retried break gets a fresh
  /// [MovaAdBreak.duration]: what the advertiser bought is that many *visible*
  /// seconds, and the failed attempt showed none of them.
  ///
  /// 对一条播不出来的广告位施加 [MovaAdConfig.failPolicy]。
  ///
  /// 每一条失败路径——open() 抛出、广告期间播放器报错、始终没有首帧——都汇流到
  /// 这里，使宿主的策略看到的是一串一致的尝试记录。重试的广告位会重新获得完整的
  /// [MovaAdBreak.duration]：广告主买的是那么多*可见*秒数，而失败的那次一秒都没
  /// 给到。
  Future<void> _onAdFailure(
    MovaTimelineNode node,
    MovaAdFailKind kind, [
    Object? error,
    _AdAttempt? ownedAttempt,
  ]) async {
    final b = node.adBreak!;
    final gen = _gen;
    final owned = ownedAttempt ?? _adAttempt;
    if (_disposed ||
        owned == null ||
        !identical(_adAttempt, owned) ||
        owned.node.id != node.id ||
        owned.failed ||
        owned.resumed) {
      return;
    }
    if (!_settled.add((gen, node.id, owned.seq))) return;
    // 同步认领失败结算，事件、抛错和超时只允许第一个入口生效。
    owned.failed = true;
    _failedEpoch = gen;
    _cancelLoadTimer();
    _cancelSlotTimer();
    final attempt = (_attempts[node.id] ?? 0) + 1;
    _attempts[node.id] = attempt;
    final verdict = movaArbitrate(
      MovaNodeFailure(
        node: node.id,
        kind: kind,
        attempt: attempt,
        fatal: true,
        error: error,
        adBreak: b,
      ),
      ads: _cfg,
      engineRecovering: _api.options.recovery.enabled,
    );
    _sessionEvents.add(MovaNodeFail(gen, node.id, verdict, error: error));
    _fire(MovaAdEventType.failed, node, error: error);
    if (gen != _gen || _disposed || !identical(_adAttempt, owned)) return;
    switch (verdict) {
      case MovaNodeFailVerdict.retryNode:
        // A retry re-announces `started`: each real attempt to put the ad on
        // screen is its own impression attempt, so the host sees
        // started → failed → started rather than a silent second try.
        //
        // 重试会再次宣告 `started`：每一次真正把广告送上屏幕的尝试都是一次独立的
        // 曝光尝试，因此宿主看到的是 started → failed → started，而不是一次静默的
        // 第二次尝试。
        await _playAd(
          node,
          autoPlay: movaPlaybackCommand(_api) == owned.command
              ? owned.play
              : _api.state.playbackIntent,
        );
        if (gen != _gen || _disposed) return;
      case MovaNodeFailVerdict.skipNode:
        await _resumeAfterAd(node, attemptSeq: owned.seq);
        if (gen != _gen || _disposed) return;
      case MovaNodeFailVerdict.abandonPod:
        _markPodPlayed(node);
        await _resumeAfterAd(node, attemptSeq: owned.seq);
        if (gen != _gen || _disposed) return;
      case MovaNodeFailVerdict.ignore:
      case MovaNodeFailVerdict.failItem:
        break;
    }
  }

  /// Marks every remaining break of [b]'s pod as played.
  ///
  /// For mid-rolls the pod is only the breaks inserted at the same point —
  /// swallowing every later mid-roll would not be "abandon the pod", it would
  /// be "turn ads off".
  ///
  /// 把 [b] 所在 pod 的所有剩余广告位标记为已播。
  ///
  /// 对中插而言，pod 仅指插在同一位置的那几条——把后面几十分钟的中插全吃掉就不是
  /// "放弃这个 pod"，而是"关掉广告"了。
  void _markPodPlayed(MovaTimelineNode node) {
    final b = node.adBreak!;
    _played.addAll(
      _nodes
          .where(
            (n) =>
                n.adBreak?.kind == b.kind &&
                (b.kind != MovaAdBreakKind.mid || n.offset <= _contentResumeAt),
          )
          .map((n) => n.id),
    );
  }

  /// Switches playback to the content, optionally resuming at [at]. Tries a
  /// seamless cutover first when [_cutover] is configured; falls back to the plain
  /// `open()`/`seek()` path when swapping is disabled, was never warmed, or
  /// failed.
  ///
  /// Uses `commit(waitForReady: true)` rather than a bare `commit()` — a bare
  /// commit would treat the shadow's common "not quite ready yet" state as an
  /// outright failure and defeat the cutover almost every time. Full rationale:
  /// doc/SPEC.md「广告编排增强」§为什么 `_playContent` 用
  /// `commit(waitForReady: true)`.
  ///
  /// 把播放切换回正片，可选地从 [at] 续播。配置了 [_cutover] 时先尝试无缝切换；
  /// 切换被禁用、从未预热过、或切换失败时回落到普通 `open()`/`seek()` 路径。
  ///
  /// 用 `commit(waitForReady: true)` 而非裸 `commit()`——裸 commit 会把影子
  /// "常见地差一点点没准备好"误判为彻底失败，导致无缝切换几乎每次都落空。
  /// 完整理由见 doc/SPEC.md「广告编排增强」§为什么 `_playContent` 用
  /// `commit(waitForReady: true)`。
  Future<void> _playContent({
    Duration at = Duration.zero,
    bool autoPlay = true,
  }) async {
    _cancelAllTimers();
    _landing = true;
    final contentAttempt = ++_contentAttempt;
    _phase = MovaSessionPhase.toContent;
    _current = null;
    _pending = null;
    _changes.add(null);
    final gen = _gen;
    final c = await _contentSource();
    if (gen != _gen || _disposed) return;
    if (c == null) {
      _contentUnavailable();
      return;
    }
    final cutover = _cutover;
    try {
      // 回正片无独立起播请求；由提交读取底层当前意图，避开代理流的转发延迟。
      final warming = _contentWarm;
      final result = warming != null
          ? await _commit(await warming)
          : cutover != null && cutover is! MovaWarmOwner
          ? await _commit(_SessionWarm(null))
          : MovaWarmCommit.notReady;
      if (gen != _gen || _disposed) return;
      _contentWarm = null;
      if (result == MovaWarmCommit.superseded) {
        _superseded();
        return;
      }
      if (result != MovaWarmCommit.committed) {
        final accepted = await _api.open(c, autoPlay: autoPlay);
        if (gen != _gen || _disposed) return;
        if (!accepted) {
          _contentUnavailable();
          return;
        }
        if (at > Duration.zero) {
          await _api.seek(at);
          if (gen != _gen || _disposed) return;
        }
      }
    } catch (e) {
      if (gen != _gen || _disposed) return;
      _contentUnavailable(e);
      return;
    } finally {
      if (gen == _gen) _landing = false;
    }
    if (_settled.contains((
      gen,
      MovaNodeId(_epochItem, MovaNodeKind.content, 0),
      contentAttempt,
    ))) {
      return;
    }
    _acceptedEpoch = gen;
    _startNode(MovaNodeId(_epochItem, MovaNodeKind.content, 0));
    _phase = MovaSessionPhase.content;
    _changes.add(null);
    // 预热携带广告前的倍速；普通打开与自定义预热计划在此兜底。
    if (cutover != null &&
        cutover.cutoverEnabled &&
        _contentRate != 1.0 &&
        _api.state.rate != _contentRate) {
      unawaited(_api.setRate(_contentRate));
    }
    // 只在正片成功接管后恢复广告前运行中的 STT。
    if (_sttWasRunning) {
      _sttWasRunning = false;
      unawaited(_api.stt.start());
    }
  }

  /// 正片未能接管时回到空闲；仅异常上报 contentError，不发 contentEnded。
  void _contentUnavailable([Object? error]) {
    _landing = false;
    if (error != null) {
      final node = MovaNodeId(_epochItem, MovaNodeKind.content, 0);
      if (!_settled.add((_gen, node, _contentAttempt))) return;
      _failedEpoch = _gen;
      _sessionEvents.add(
        MovaNodeFail(_gen, node, MovaNodeFailVerdict.failItem, error: error),
      );
      _endNode(MovaNodeEndReason.failed);
    }
    _cancelAllTimers();
    unawaited(_cutover?.abandon());
    _onScreen = null;
    _phase = MovaSessionPhase.idle;
    _changes.add(null);
    if (error != null && !_contentError.isClosed) _contentError.add(error);
  }

  /// Reacts to end-of-media: an ad completing resumes content; content
  /// completing plays a post-roll (if any) then goes idle.
  ///
  /// 响应媒体播放结束：广告播完则续播正片；正片播完则播后贴片（若有）再转空闲。
  void _onEvent(MovaEvent e) {
    if (_landing &&
        (e is MovaDone ||
            e is MovaErrorEvent ||
            e is MovaPlayFailure ||
            e is MovaFirstFrame)) {
      return;
    }
    if (e is MovaErrorEvent || e is MovaPlayFailure) {
      final giveUp =
          e is MovaPlayFailure && e.action == MovaRecoveryAction.giveUp;
      final fatal = e is MovaErrorEvent && e.fatal;
      // 非终结内核日志保持 A13 的诊断语义，不成为节点失败。
      if (!fatal && !giveUp) return;
      final error = e is MovaErrorEvent
          ? e.error
          : (e as MovaPlayFailure).fail.error;
      final playing = _current;
      if (_phase == MovaSessionPhase.ad && playing != null) {
        unawaited(_onAdFailure(playing, MovaAdFailKind.playerError, error));
      } else if (_phase == MovaSessionPhase.content ||
          _phase == MovaSessionPhase.pending ||
          _phase == MovaSessionPhase.toContent) {
        final verdict = movaArbitrate(
          MovaNodeFailure(
            node: MovaNodeId(_epochItem, MovaNodeKind.content, 0),
            kind: MovaAdFailKind.playerError,
            attempt: _contentAttempt,
            fatal: fatal,
            giveUp: giveUp,
            error: error,
          ),
          ads: _cfg,
          engineRecovering: _api.options.recovery.enabled,
        );
        if (verdict == MovaNodeFailVerdict.failItem) {
          _contentUnavailable(error ?? StateError('正片恢复已放弃'));
        }
      }
      return;
    }
    if (e is MovaFirstFrame) {
      _onAdFirstFrame();
      return;
    }
    if (e is! MovaDone) return;
    if (_phase == MovaSessionPhase.ad) {
      final finished = _current;
      final attempt = _adAttempt;
      if (finished == null ||
          attempt == null ||
          !attempt.opened ||
          attempt.resumed ||
          attempt.failed) {
        return;
      }
      _fire(MovaAdEventType.completed, finished);
      unawaited(_resumeAfterAd(finished, attemptSeq: attempt.seq));
    } else if (_phase == MovaSessionPhase.content ||
        _phase == MovaSessionPhase.pending) {
      _endNode(MovaNodeEndReason.completed);
      // The content ended while a mid-roll was queued behind it: that break is
      // scheduled *inside* the content, so with the content gone it is moot.
      //
      // 正片在一条中插排队期间播完了：那条广告位是排在正片*内部*的，正片没了
      // 它也就没有意义了。
      if (_phase == MovaSessionPhase.pending) {
        _cancelDelayTimer();
        _pending = null;
        unawaited(_cutover?.abandon());
      }
      final post = _enabled ? _firstOfKind(MovaAdBreakKind.post) : null;
      if (post != null) {
        unawaited(_playAd(post));
      } else {
        _goIdleAfterContent();
      }
    }
  }

  /// Transitions to idle after the content (and its post-rolls) finished, and
  /// signals [contentEnded] for playlist composition.
  ///
  /// 在正片（及其后贴片）播完后转入空闲，并触发 [contentEnded] 供播放列表组合使用。
  void _goIdleAfterContent() {
    _cancelAllTimers();
    unawaited(_cutover?.abandon());
    _onScreen = null;
    _phase = MovaSessionPhase.idle;
    _current = null;
    _pending = null;
    _changes.add(null);
    _endedEpochs.add(_gen);
    _contentEnded.add(null);
  }

  /// Resumes the right thing after ad [finished] ends: pre → content from the
  /// start, mid → content at the saved position, post → idle (done).
  ///
  /// 广告 [finished] 结束后续播正确内容：前贴片 → 正片从头，中插 → 正片从保存
  /// 位置，后贴片 → 空闲（结束）。
  /// [attemptSeq] 必须在发钩子之前捕获，防止钩子重载同一节点后误续播新尝试。
  Future<void> _resumeAfterAd(
    MovaTimelineNode finished, {
    required int attemptSeq,
  }) {
    final attempt = _adAttempt;
    final future = _resumeAdCore(finished, attemptSeq: attemptSeq);
    if (attempt != null && attempt.seq == attemptSeq) {
      attempt.continuation ??= future;
    }
    return future;
  }

  Future<void> _resumeAdCore(
    MovaTimelineNode finished, {
    required int attemptSeq,
  }) async {
    final resume = _api.state.playbackIntent;
    final gen = _gen;
    if (_disposed) return;
    final attempt = _adAttempt;
    if (attempt == null ||
        attempt.node.id != finished.id ||
        attempt.seq != attemptSeq ||
        attempt.resumed) {
      return;
    }
    // 守卫绑定尝试而非整个 pod：下一条同步失败仍可嵌套续播。
    attempt.resumed = true;
    _resumeDepth++;
    _cancelSlotTimer();
    _cancelLoadTimer();
    try {
      switch (finished.adBreak!.kind) {
        case MovaAdBreakKind.pre:
          // Ad pod: chain any further pre-rolls before the content starts.
          //
          // 广告 pod：正片开始前，依次连播其余前贴片。
          final nextPre = _firstOfKind(MovaAdBreakKind.pre);
          if (nextPre != null) {
            await _playAd(nextPre, autoPlay: resume);
            if (gen != _gen || _disposed) return;
          } else {
            await _playContent(autoPlay: resume);
            if (gen != _gen || _disposed) return;
          }
        case MovaAdBreakKind.mid:
          // Ad pod: chain straight into the next mid-roll inserted at the same
          // point. Without this the second break of a pod only plays after the
          // content has been resumed and ticked once — which flashes the content
          // between two ads and, now that pending exists, would pop a second
          // countdown. Only the *first* break of a pod ever goes through
          // [_beginDelay]; chained ones go straight to [_playAd].
          //
          // 广告 pod：直接串到插在同一位置的下一条中插。没有这一步，pod 的第二条
          // 要等正片被续播、再 tick 一次才播——这会在两条广告之间闪一下正片，而且
          // 在有了待播阶段之后还会再弹一次倒计时。一个 pod 里只有*第一条*会经过
          // [_beginDelay]，被串联的后续几条一律直接走 [_playAd]。
          final nextMid = _nextPodMid();
          if (nextMid != null) {
            await _playAd(nextMid, autoPlay: resume);
            if (gen != _gen || _disposed) return;
          } else {
            await _playContent(at: _contentResumeAt, autoPlay: resume);
            if (gen != _gen || _disposed) return;
          }
        case MovaAdBreakKind.post:
          // Ad pod: chain any further post-rolls before going idle.
          //
          // 广告 pod：转入空闲前，依次连播其余后贴片。
          final nextPost = _firstOfKind(MovaAdBreakKind.post);
          if (nextPost != null) {
            await _playAd(nextPost, autoPlay: resume);
            if (gen != _gen || _disposed) return;
          } else {
            _goIdleAfterContent();
          }
      }
    } finally {
      if (gen == _gen && !_disposed) _resumeDepth--;
    }
  }

  /// Marks the current ad's first frame as landed: the load deadline has been
  /// met, and with [MovaAdConfig.durationFromFirstFrame] the slot clock starts
  /// now. Idempotent per ad.
  ///
  /// 标记当前广告首帧已落地：加载期限达成；开启
  /// [MovaAdConfig.durationFromFirstFrame] 时广告位时钟从此刻起算。每条广告只生效
  /// 一次。
  void _onAdFirstFrame() {
    if (_adFramed ||
        _phase != MovaSessionPhase.ad ||
        _adAttempt?.opened != true) {
      return;
    }
    _adFramed = true;
    _cancelLoadTimer();
    final playing = _current;
    if (_cfg.durationFromFirstFrame && playing != null) {
      _armSlotTimer(playing);
    }
  }

  /// Tracks ad elapsed time, and while playing content triggers a due mid-roll,
  /// saving the content position to resume at afterwards.
  ///
  /// 跟踪广告已播时长；播放正片期间触发到期的中插，并保存正片位置以便之后续播。
  void _onProgress(MovaProg p) {
    if (_landing) return;
    if (_phase == MovaSessionPhase.ad) {
      _adPosition = p.position;
      // First rendered frame of this ad: the slot the advertiser bought is
      // *visible* seconds, so a slow load must not eat into it.
      //
      // 这条广告的首个已渲染帧：广告主买的是*可见*秒数，加载慢不应该吃掉这段时长。
      if (!_adFramed) {
        // `rendered` is the precise signal (always maintained by MovaEngine);
        // without it fall back to two consecutive rising non-zero positions —
        // a single tick may be residue of the previous media.
        //
        // `rendered` 是精确信号（MovaEngine 一直维护）；没有它时回退为"位置>0
        // 且连续两次递增"——单个 tick 可能是上一段媒体的残留。
        if (p.position > Duration.zero && p.position > _adLastPos) {
          _adRises++;
        } else if (p.position != _adLastPos) {
          _adRises = 0;
        }
        _adLastPos = p.position;
        if (_api.state.rendered || _adRises >= 2) _onAdFirstFrame();
      }
      // Ask the configured trigger whether it is time to start warming the
      // content up in the background; the trigger (not this controller)
      // decides based on how much of the ad is left and how long it is.
      //
      // 询问已配置的触发策略此刻是否该开始在后台预热正片；由触发策略（而非
      // 本控制器）根据广告剩余时长与广告总时长决定。
      final cutover = _cutover;
      if (cutover != null && cutover.cutoverEnabled) {
        final adDuration = _api.state.duration;
        unawaited(
          _warmContentBehindAd(
            cutover,
            movaContentWarmCue(
              mediaDuration: adDuration,
              adPosition: _adPosition,
              slotRemaining: _slotClock.remaining,
              slotLength: _current?.adBreak?.duration,
            ),
          ),
        );
      }
      return;
    }
    if (_phase == MovaSessionPhase.pending) {
      // The content deliberately plays on. The resume point tracks the live
      // position, so it ends up being where the ad *actually* takes over — not
      // where the countdown started. No further mid-roll may be triggered from
      // here: one pending ad at a time.
      //
      // 正片刻意继续播放。续播点跟随实时位置，因此最终取到的是广告*真正*接管
      // 那一刻的位置，而不是倒计时开始那一刻。此阶段不得再触发别的中插：
      // 同一时刻只排队一条待播广告。
      _lastContentPosition = p.position;
      _contentResumeAt = p.position;
      _contentRate = _api.state.rate;
      final waiting = _pending;
      if (waiting != null && _wantsWait(waiting.adBreak!)) {
        // Warm the ad up behind the still-playing content. The plan is the
        // content→ad one: eager (the delay window exists precisely to be spent
        // warming up) and holding at frame zero (an ad that quietly played its
        // first seconds in the shadow would be delivered with its head
        // missing). `at` is always zero — an ad always starts at its start.
        //
        // 在仍在播放的正片背后预热广告。用的是 content→ad 方向的计划：立即触发
        // （delay 窗口存在的意义就是拿来预热）、并停在第 0 帧（一条在影子里悄悄
        // 播掉了开头几秒的广告，交付出去就是缺头的）。`at` 恒为零——广告总是从
        // 自己的开头播起。
        unawaited(
          _adWarm = _warm(
            waiting.adBreak!.source,
            plan: movaAdWarmPlan(_cfg),
            cue: MovaWarmCue(
              remaining: delayRemaining,
              total: waiting.adBreak!.delay > Duration.zero
                  ? waiting.adBreak!.delay
                  : null,
            ),
          ),
        );
      }
      return;
    }
    if (_phase == MovaSessionPhase.content) {
      _lastContentPosition = p.position;
      // While returning from an ad (`_resuming`) the active engine may still be
      // the 1x ad, so its rate must not overwrite the content rate saved earlier.
      //
      // 从广告返回的过渡期（`_resuming`）内，活动引擎可能仍是 1x 的广告，其倍速
      // 不能覆盖此前保存的正片倍速。
      if (!_resuming) _contentRate = _api.state.rate;
      if (_enabled) {
        final selection = movaSnapback(_nodes, p.position, _played, _cfg.midRollSnapback);
        _played.addAll(selection.skip);
        final due = selection.play;
        if (due != null) {
          _contentResumeAt = p.position;
          // A countdown, a background warm-up, or both, put the break through
          // the pending phase first; otherwise it takes over immediately, the
          // way it always has.
          //
          // 有倒计时、有后台预热、或两者兼有时，先让该广告位走一遍待播阶段；
          // 否则立刻接管，与一贯行为相同。
          if (due.adBreak!.delay > Duration.zero || _wantsWait(due.adBreak!)) {
            _beginDelay(due);
          } else {
            unawaited(_playAd(due));
          }
        }
      }
    }
  }

  /// Warms the content up behind the currently playing ad, resolving the
  /// content source first when it was deferred.
  ///
  /// Keeps the configured trigger and readiness policy, but holds the shadow
  /// at the resume point: the content behind an ad is *paused* content, so a
  /// shadow left rolling drifts forward by however long the ad still had to
  /// run and the viewer silently loses that many seconds of the film. Measured
  /// on device (STG AL00): resume target 6006ms, actual landing 8842ms — a
  /// 2.8s hole, exactly the ad time left after the warm-up started.
  ///
  /// 在正在播放的广告背后预热正片；正片源是延迟解析的则先解析。
  ///
  /// 沿用已配置的触发策略与就绪判据，但把影子钉在续播点：广告背后的正片是
  /// *暂停*着的，影子若一路播下去，就会按广告剩余时长往前漂，用户于是无声无息
  /// 地丢掉那么多秒正片。真机实测（STG AL00）：续播目标 6006ms、实际落点
  /// 8842ms——2.8 秒的缺口，恰好等于预热开始后广告还剩的时长。
  Future<void> _warmContentBehindAd(
    MovaCutover cutover,
    MovaWarmCue cue,
  ) async {
    // 后贴片之后没有正片可返回：这是预热方向判断，与等待就绪策略无关。
    if (_current?.adBreak?.kind == MovaAdBreakKind.post) return;
    final gen = _gen;
    final content = await _contentSource();
    if (content == null || gen != _gen || _disposed) return;
    if (_phase != MovaSessionPhase.ad || _landing) return;
    final previous = _contentWarm;
    _contentWarm = () async {
      final warm = await _warm(
        content,
        at: _contentResumeAt,
        cue: cue,
        plan: movaContentWarmPlan(_contentRate),
      );
      // 触发器暂不预热时保留先前凭据，避免到期 tick 丢掉已就绪正片。
      if (warm?.owned == true && warm?.ticket == null && previous != null) {
        return await previous;
      }
      return warm;
    }();
    await _contentWarm;
  }

  /// Notifies the host hook of an ad lifecycle [type] for break [b], carrying
  /// [error] for failures.
  ///
  /// 就广告位 [b] 的生命周期 [type] 通知宿主钩子；失败时携带 [error]。
  void _fire(MovaAdEventType type, MovaTimelineNode node, {Object? error}) {
    switch (type) {
      case MovaAdEventType.started:
        _startNode(node.id);
      case MovaAdEventType.completed:
        _endNode(MovaNodeEndReason.completed);
      case MovaAdEventType.skipped:
        _endNode(MovaNodeEndReason.skipped);
      case MovaAdEventType.failed:
        if (_onScreen == node.id) _endNode(MovaNodeEndReason.failed);
      default:
        break;
    }
    _onAdEvent?.call(MovaAdEvent(type, node.adBreak!, error: error));
  }

  /// 释放会话订阅与广告计时，返回清理完成的 Future；借用的播放器仍可用。
  /// 示例：`await session.dispose();`。
  Future<void> dispose() async {
    _disposed = true;
    _gen++;
    _resolving = null;
    _cancelAllTimers();
    await _endSub?.cancel();
    await _eventSub?.cancel();
    await _progressSub?.cancel();
    await _stateSub?.cancel();
    await _cutover?.abandon();
    await _changes.close();
    await _endedEpochs.close();
    await _contentEnded.close();
    await _contentError.close();
    await _sessionEvents.close();
  }
}
