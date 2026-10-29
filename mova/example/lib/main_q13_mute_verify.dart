// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

import 'verify_auto/auto_kit.dart';

/// Q13 acceptance page (plan doc/plans/2026-10-23-standby-mode.md, Q13): while a cutover shadow engine is
/// warming, ONLY that shadow is muted (through mpv `mute`), the playing engine keeps its sound, the
/// system media volume is never written, and committing the cutover un-mutes just the warm hold. Also
/// checks the overlap with keepAlive (both hold the mute, either may leave first).
///
/// Self-running: no manual clicking. Content is a local live FLV (440 Hz tone), the ad a local VOD
/// (880 Hz tone), so by ear "ad = high tone, content = low tone". Every step prints a
/// `[Q13] MARK <name>` line (an external script can sample `adb shell dumpsys audio` there) followed by
/// `[Q13] PROPS <name> ...` with the mpv `mute`/`vid` of every engine created so far (k0 = the first
/// engine, which plays the ad; k1 = the shadow warming the content; after the commit k1 is the live
/// one and k0 is gone). The properties are read straight from the media_kit players, so this part is
/// platform independent; the system volume and what you hear are what only a device can tell.
///
/// Q13 验收页（计划 Q13）：cutover 影子引擎预热期间，**只有影子**经 mpv `mute` 静音，正在播的引擎声音不变，系统媒体音量
/// 从不被写，提交后只撤销预热静音；并检查与 keepAlive 的叠加（两方都持有静音，谁先退出都不漏声）。
///
/// 自动跑，不用手点。正片是本地直播 FLV（440Hz 音调），广告是本地点播（880Hz），所以耳朵听"高音 = 广告、低音 = 正片"。
/// 每一步打印 `[Q13] MARK <名>`（外部脚本可在这里采样 `adb shell dumpsys audio`），随后打印 `[Q13] PROPS <名> ...`，
/// 内容是迄今创建过的每个引擎的 mpv `mute`/`vid`（k0 = 第一个引擎，播广告；k1 = 影子，预热正片；提交后 k1 是在播的，k0 已销毁）。
/// 属性直接从 media_kit 播放器读取，所以这部分与平台无关；系统音量和听感只有真机能判断。
///
/// 跑法（本地源见 `example/tool/verify_sources/`）:
/// `flutter run -t lib/main_q13_mute_verify.dart --dart-define=BASE=http://127.0.0.1:18080 --dart-define=LOG_FILE=<路径>`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _Q13Page()));
}

/// Base URL of the local source server.
///
/// 本地源服务器基地址。
const String kBase = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18080');

/// Exit the process when done (default true).
///
/// 跑完后退出进程（默认 true）。
const bool kAutoExit = bool.fromEnvironment('AUTOEXIT', defaultValue: true);

/// The Q13 page.
///
/// Q13 页面。
class _Q13Page extends StatefulWidget {
  const _Q13Page();

  @override
  State<_Q13Page> createState() => _Q13PageState();
}

class _Q13PageState extends State<_Q13Page> {
  final AutoLog _out = AutoLog('[Q13]');
  final Stopwatch _clock = Stopwatch()..start();
  final List<String> _lines = <String>[];
  final Map<String, int> _pass = <String, int>{};
  final Map<String, int> _fail = <String, int>{};

  MovaCutoverEngine? _cutover;
  MovaAds? _ads;

  /// Kept for the whole scenario: the existing seamless-cutover test also listens to the engine's streams
  /// throughout, and the ad flow was only seen to start with a listener attached.
  StreamSubscription<MovaProg>? _progSub;

  /// Every media_kit player created so far, in creation order (k0, k1, ...).
  final List<Player> _players = <Player>[];

  /// Latest position seen on the proxy's progress stream (used as the warm target estimate in DIAG).
  ///
  /// 代理进度流上最近一次位置（DIAG 里用作预热目标估计）。
  Duration _lastPos = Duration.zero;

  /// Bumped to stop the previous DIAG sampler.
  ///
  /// 递增即停止上一个 DIAG 采样器。
  int _diagToken = 0;

  /// Summary of the latest warm-up, filled by the DIAG sampler.
  ///
  /// 最近一次预热的摘要，由 DIAG 采样器填写。
  String _diagSummary = 'none';

  /// Content plays this long before the ad is inserted (ms); scenario ids with suffix S / L change it.
  ///
  /// 插广告前正片先播多久（毫秒）；场景编号后缀 S / L 会改它。
  int _contentDelayMs = 3000;

  /// True: content is a VOD (local vod.mp4) instead of the live FLV; used by the Q13V regression scenario.
  ///
  /// 为真时正片用点播（本地 vod.mp4）而不是直播 FLV；Q13V 回归场景用。
  bool _vod = false;

  /// Epoch whose progress is tracked into [_trackPos] (Q13V: content position at the ad takeover).
  ///
  /// 被跟踪进度的 epoch，其位置写入 [_trackPos]（Q13V：广告接管时刻的正片位置）。
  int _trackEpoch = -1;
  Duration _trackPos = Duration.zero;
  Duration? _resumePos;
  int _resumeEpoch = -1;

  void _log(String msg) {
    final line = _out.line('${DateTime.now().toIso8601String().substring(11, 23)} ${_clock.elapsedMilliseconds.toString().padLeft(7)}ms $msg');
    if (mounted) setState(() => _lines.insert(0, line));
  }

  void _verdict(String id, bool ok, String note) {
    (ok ? _pass : _fail).update(id, (v) => v + 1, ifAbsent: () => 1);
    _log('VERDICT $id ${ok ? 'PASS' : 'FAIL'} $note | DIAGSUM contentDelay=${_contentDelayMs}ms $_diagSummary');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runAll()));
  }

  MovaSource _content() => _vod
      ? MovaSource(_stamp('$kBase/vod.mp4'), title: 'content')
      : MovaSource(_stamp('$kBase/live.flv?gop=50&audio=1&freq=440'), type: MovaStreamType.live, title: 'content');

  MovaAdBreak _adBreak() => MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: MovaSource(_stamp('$kBase/ad.mp4'), title: 'ad'),
    skippableAfter: Duration.zero,
  );

  String _stamp(String url) {
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().microsecondsSinceEpoch}'}).toString();
  }

  /// A fresh cutover engine + ad controller; every underlying engine is built on a kernel whose player we keep.
  Future<void> _newRig() async {
    await _disposeRig();
    _players.clear();
    final opts = const MovaOpts(
      ads: MovaAdConfig(enabled: true),
      cutover: MovaCutoverConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final cutover = MovaCutoverEngine(
      engineFactory: () {
        final player = Player();
        _players.add(player);
        return createMovaEngine(kernel: MovaMpvKernel(player: player, lazyVideo: true, observeQoeSignals: false), options: opts);
      },
    );
    _cutover = cutover;
    _progSub = cutover.progress.listen((p) {
      _lastPos = p.position;
      final ep = cutover.state.renderEpoch;
      if (ep == _trackEpoch) _trackPos = p.position;
      if (_resumeEpoch >= 0 && ep == _resumeEpoch && _resumePos == null) _resumePos = p.position;
    });
    _ads = MovaAds(cutover, cutover: cutover);
    if (mounted) setState(() {});
  }

  Future<void> _disposeRig() async {
    final ads = _ads;
    final cutover = _cutover;
    _ads = null;
    _cutover = null;
    await _progSub?.cancel();
    _progSub = null;
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    ads?.dispose();
    await cutover?.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  /// DIAG sampler: every 300ms after the ad insert, logs the newest (shadow) player's native buffer readings,
  /// the cutover phase and the `MovaBufferWarm` inputs derivable from them; records when the phase turns
  /// `ready` and when the shadow disappears (ready timer abandon). Read-only, touches no engine state.
  ///
  /// DIAG 采样器：插广告后每 300ms 记录最新（影子）播放器的原生缓冲读数、cutover 阶段，以及据此可推的
  /// `MovaBufferWarm` 输入；记录阶段何时变 `ready`、影子何时消失（就绪计时器放弃）。只读，不碰引擎状态。
  Future<void> _diag(String tag, int token, int t0, Duration target) async {
    int? tPos, tReady, tGone;
    var last = '';
    var shadowIdx = -1;
    while (token == _diagToken && _cutover != null) {
      if (_players.length - 1 != shadowIdx) {
        shadowIdx = _players.length - 1;
        tPos = tReady = tGone = null;
        _log('DIAG $tag newest player is now k$shadowIdx +${_clock.elapsedMilliseconds - t0}ms');
      }
      final p = _players[shadowIdx];
      final now = _clock.elapsedMilliseconds - t0;
      final pos = await _prop(p, 'time-pos');
      final cache = await _prop(p, 'demuxer-cache-time');
      final pfc = await _prop(p, 'paused-for-cache');
      final idle = await _prop(p, 'core-idle');
      final phase = _cutover?.cutoverPhase.name ?? 'n/a';
      if (pos == 'gone' && tGone == null) tGone = now;
      final posS = double.tryParse(pos);
      if (posS != null && posS > 0 && tPos == null) tPos = now;
      if (phase == 'ready' && tReady == null) tReady = now;
      final arrived = posS != null && posS * 1000 >= target.inMilliseconds - 800;
      final cacheS = double.tryParse(cache);
      final ahead = (cacheS != null && posS != null) ? (cacheS - posS) : null;
      last = 'shadow k$shadowIdx t=${now}ms pos=$pos cache=$cache ahead=${ahead?.toStringAsFixed(2)} pfc=$pfc idle=$idle phase=$phase arrived=$arrived(target=${target.inMilliseconds}ms)';
      _log('DIAG $tag $last');
      _diagSummary = 'target=${target.inMilliseconds}ms firstPos=${tPos}ms ready=${tReady}ms gone=${tGone}ms';
      if (tGone != null || now > 20000) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    _log('DIAG-END $tag $_diagSummary last=[$last]');
  }

  /// Waits until the engine really plays (position moving, not buffering).
  Future<bool> _waitPlaying() async {
    final cutover = _cutover!;
    final done = Completer<bool>();
    late final StreamSubscription<MovaProg> sub;
    sub = cutover.progress.listen((p) {
      if (p.position > Duration.zero && !cutover.state.buffering && !done.isCompleted) done.complete(true);
    });
    final ok = await done.future.timeout(const Duration(seconds: 25), onTimeout: () => false);
    await sub.cancel();
    return ok;
  }

  Future<bool> _waitEpoch(int from) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (_cutover!.state.renderEpoch != from) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<String> _prop(Player p, String name) async {
    final native = p.platform;
    if (native is! NativePlayer) return 'n/a';
    try {
      return await native.getProperty(name).timeout(const Duration(seconds: 1), onTimeout: () => 'timeout');
    } on Object {
      return 'gone';
    }
  }

  /// Indices of the players that are still alive (not disposed).
  Future<List<int>> _alive() async {
    final out = <int>[];
    for (var i = 0; i < _players.length; i++) {
      if (await _prop(_players[i], 'mute') != 'gone') out.add(i);
    }
    return out;
  }

  /// Prints the `MARK` and `PROPS` lines and returns `mute` of every engine ('gone' once disposed).
  Future<List<String>> _snapshot(String name) async {
    _log('MARK $name');
    final mutes = <String>[];
    final parts = <String>[];
    for (var i = 0; i < _players.length; i++) {
      final mute = await _prop(_players[i], 'mute');
      mutes.add(mute);
      parts.add('k$i(mute=$mute vid=${await _prop(_players[i], 'vid')} pause=${await _prop(_players[i], 'pause')})');
    }
    _log('PROPS $name renderEpoch=${_cutover!.state.renderEpoch} keepAlive=${_cutover!.state.keepAlivePhase.name} ${parts.join(' ')}');
    return mutes;
  }

  /// Polls the newest player until its media is loaded (`vid` is no longer `auto`) and logs `mute`/`pause`
  /// at that first moment (50 ms granularity): a shadow that is loaded but not yet muted would leak sound.
  Future<bool> _waitShadowLoaded(String tag) async {
    final created = _clock.elapsedMilliseconds;
    final idx = _players.length - 1;
    final deadline = DateTime.now().add(const Duration(seconds: 14));
    while (DateTime.now().isBefore(deadline)) {
      final vid = await _prop(_players[idx], 'vid');
      if (vid != 'auto' && vid != 'gone' && vid != 'timeout') {
        _log('$tag shadow k$idx loaded ${_clock.elapsedMilliseconds - created}ms after the wait began: vid=$vid mute=${await _prop(_players[idx], 'mute')} pause=${await _prop(_players[idx], 'pause')} (first sight, 50ms poll)');
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _log('$tag shadow k$idx never loaded within 14s');
    return false;
  }

  /// Content live, ad inserted: returns once the ad engine is the active one and its shadow (the content) is loaded.
  Future<bool> _enterAd(String tag) async {
    final ads = _ads!;
    await ads.load(_content());
    if (!await _waitPlaying()) {
      _log('$tag content never played');
      return false;
    }
    await Future<void>.delayed(Duration(milliseconds: _contentDelayMs));
    final e0 = _cutover!.state.renderEpoch;
    final tPlay = _clock.elapsedMilliseconds;
    final target = _lastPos;
    final token = ++_diagToken;
    final cutoverEvents = _cutover!.events.listen((e) {
      if (e is MovaCutoverChange) _log('EVT $tag cutover phase=${e.phase.name} +${_clock.elapsedMilliseconds - tPlay}ms');
    });
    unawaited(Future<void>.delayed(const Duration(seconds: 25), cutoverEvents.cancel));
    unawaited(_diag(tag, token, tPlay, target));
    await ads.playAdNow(_adBreak());
    _log('$tag playAdNow returned after ${_clock.elapsedMilliseconds - tPlay}ms epoch=${_cutover!.state.renderEpoch} showingAd=${ads.isShowingAd} players=${_players.length}');
    if (!await _waitEpoch(e0)) {
      _log('$tag the ad never became the active engine');
      return false;
    }
    if (!await _waitPlaying()) {
      _log('$tag ad never played');
      return false;
    }
    if (!await _waitShadowLoaded(tag)) return false;
    await Future<void>.delayed(const Duration(seconds: 1));
    return true;
  }

  /// Content live, ad inserted, shadow warms, ad skipped, cutover commits.
  Future<void> _scenarioPlain() async {
    await _newRig();
    final ads = _ads!;
    if (!await _enterAd('A')) return _verdict('Q13A', false, 'could not reach the warming state');
    final warming = await _snapshot('A-ad-playing-shadow-warming');
    final alive = await _alive();
    final epoch = _cutover!.state.renderEpoch;
    _log('A skipping the ad now');
    ads.skip();
    final swapped = await _waitEpoch(epoch);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final committed = await _snapshot('A-committed');
    final newest = _players.length - 1;
    final ok = alive.length >= 2 &&
        warming[alive.first] == 'no' &&
        warming[alive.last] == 'yes' &&
        swapped &&
        committed[newest] == 'no';
    _verdict('Q13A', ok, 'warming: active(k${alive.first}).mute=${warming[alive.first]} shadow(k${alive.last}).mute=${warming[alive.last]} swapped=$swapped committed(live k$newest).mute=${committed[newest]}');
  }

  /// Like [_scenarioPlain] but keepAlive is requested while warming; [wakeBeforeCommit] picks which side leaves first.
  Future<void> _scenarioKeepAlive({required bool wakeBeforeCommit}) async {
    final id = wakeBeforeCommit ? 'Q13C' : 'Q13B';
    final tag = wakeBeforeCommit ? 'C' : 'B';
    await _newRig();
    final ads = _ads!;
    final cutover = _cutover!;
    if (!await _enterAd(tag)) return _verdict(id, false, 'could not reach the warming state');
    final phase = await cutover.setKeepAlive(true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final warmed = await _snapshot('$tag-keepAlive-requested-while-warming (active phase=${phase.name})');
    final alive = await _alive();
    final shadow = alive.last;
    var ok = alive.length >= 2 && warmed[shadow] == 'yes';
    var extra = '';
    if (wakeBeforeCommit) {
      await cutover.setKeepAlive(false);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final mid = await _snapshot('$tag-woke-before-commit');
      ok = ok && mid[shadow] == 'yes';
      extra = ' shadow.mute after wake=${mid[shadow]}';
    }
    final epoch = cutover.state.renderEpoch;
    _log('$tag skipping the ad now');
    ads.skip();
    final swapped = await _waitEpoch(epoch);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final committed = await _snapshot('$tag-committed');
    final newest = _players.length - 1;
    ok = ok && swapped;
    if (wakeBeforeCommit) {
      ok = ok && committed[newest] == 'no';
    } else {
      final vid = await _prop(_players[newest], 'vid');
      ok = ok && committed[newest] == 'yes' && vid == 'no' && cutover.state.keepAlivePhase == MovaKeepAlivePhase.holding;
      extra = ' live.vid=$vid keepAlive=${cutover.state.keepAlivePhase.name}';
      await cutover.setKeepAlive(false);
      await Future<void>.delayed(const Duration(seconds: 7));
      final w = await _snapshot('$tag-woken-after-commit');
      ok = ok && w[newest] == 'no';
      extra = '$extra afterWake.mute=${w[newest]}';
    }
    _verdict(id, ok, 'shadow.mute while warming=${warmed[shadow]} swapped=$swapped committed(live k$newest).mute=${committed[newest]}$extra');
  }

  /// VOD regression: content VOD, ad inserted and skipped; the shadow (content) must still wait to reach the
  /// target position, and the resume position error is logged (content position at ad takeover vs first
  /// position after the commit).
  ///
  /// 点播回归：正片点播，插广告再跳过；影子仍须追到目标位置才就绪，并记录续播落点误差。
  Future<void> _scenarioVod() async {
    _vod = true;
    try {
      await _newRig();
      final ads = _ads!;
      _trackPos = Duration.zero;
      _resumePos = null;
      _resumeEpoch = -1;
      _trackEpoch = 0;
      final tStart = _clock.elapsedMilliseconds;
      if (!await _enterAd('V')) return _verdict('Q13V', false, 'could not reach the warming state');
      final epoch = _cutover!.state.renderEpoch;
      final contentAtTakeover = _trackPos;
      _trackEpoch = -1;
      _resumeEpoch = epoch + 1;
      _log('V skipping the ad now; content position at takeover=${contentAtTakeover.inMilliseconds}ms');
      final tSkip = _clock.elapsedMilliseconds;
      ads.skip();
      final swapped = await _waitEpoch(epoch);
      final tCommit = _clock.elapsedMilliseconds;
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final committed = await _snapshot('V-committed');
      final newest = _players.length - 1;
      final resume = _resumePos;
      final err = resume == null ? null : resume.inMilliseconds - contentAtTakeover.inMilliseconds;
      final ok = swapped && committed[newest] == 'no' && err != null && err.abs() < 500;
      _verdict('Q13V', ok, 'swapped=$swapped contentAtTakeover=${contentAtTakeover.inMilliseconds}ms resumeFirstPos=${resume?.inMilliseconds}ms resumeErr=${err}ms skipToCommit=${tCommit - tSkip}ms sinceStart=${tCommit - tStart}ms committed(k$newest).mute=${committed[newest]}');
    } finally {
      _vod = false;
      _trackEpoch = -1;
      _resumeEpoch = -1;
    }
  }

  Future<void> _runAll() async {
    final only = parseOnly(autoOnlyRaw());
    final runs = autoRuns();
    final scenarios = <(String, String, Future<void> Function())>[
      ('Q13A', 'plain warm and commit', _scenarioPlain),
      ('Q13B', 'keepAlive requested while warming, commit while holding, then wake', () => _scenarioKeepAlive(wakeBeforeCommit: false)),
      ('Q13C', 'keepAlive requested while warming, wake before commit', () => _scenarioKeepAlive(wakeBeforeCommit: true)),
      ('Q13V', 'VOD content cutover regression (resume position error)', _scenarioVod),
    ];
    _log('AUTORUN start runs=$runs base=$kBase only=${only.isEmpty ? 'all' : only.join(',')} os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    // Variants for the warm-up timing study: suffix S = content plays 500ms before the ad, L = 7000ms.
    final variants = <String, (String, int)>{
      'Q13AS': ('Q13A', 500), 'Q13BS': ('Q13B', 500), 'Q13CS': ('Q13C', 500),
      'Q13AL': ('Q13A', 7000), 'Q13BL': ('Q13B', 7000), 'Q13CL': ('Q13C', 7000),
      'Q13AX': ('Q13A', 15000), 'Q13BX': ('Q13B', 15000), 'Q13CX': ('Q13C', 15000),
      'Q13AY': ('Q13A', 30000), 'Q13BY': ('Q13B', 30000), 'Q13CY': ('Q13C', 30000),
    };
    for (final v in only.where(variants.containsKey)) {
      final (base, delay) = variants[v]!;
      final src = scenarios.firstWhere((e) => e.$1 == base);
      scenarios.add((v, '${src.$2} (content delay ${delay}ms)', () async {
        _contentDelayMs = delay;
        try {
          await src.$3();
        } finally {
          _contentDelayMs = 3000;
        }
      }));
    }
    for (final (id, title, run) in scenarios) {
      if (only.isNotEmpty && !only.contains(id)) continue;
      for (var i = 1; i <= runs; i++) {
        _log('--- $id $title run $i/$runs');
        try {
          await run();
        } catch (e, st) {
          _verdict(id, false, 'script error: $e\n$st');
        }
      }
    }
    await _disposeRig();
    final ids = {..._pass.keys, ..._fail.keys}.toList()..sort();
    for (final id in ids) {
      _log('SUMMARY $id pass=${_pass[id] ?? 0} fail=${_fail[id] ?? 0}');
    }
    _log('AUTORUN DONE');
    if (kAutoExit) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cutover = _cutover;
    return Scaffold(
      appBar: AppBar(title: const Text('Q13 mute verify')),
      body: Column(
        children: [
          if (cutover != null) AspectRatio(aspectRatio: 16 / 9, child: MovaPlayer(api: cutover, skin: const MovaMinimalSkin())),
          Expanded(child: ListView(children: [for (final l in _lines.take(60)) Text(l, style: const TextStyle(fontSize: 11))])),
        ],
      ),
    );
  }
}
