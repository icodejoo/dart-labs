// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

import 'auto_kit.dart';

/// Scripted AUTORUN mode of `main_host_ergonomics_verify.dart` (plan
/// doc/plans/2026-10-23-host-ergonomics.md, Task 16). Runs V1-V8, V10, V12 in a
/// fixed order, each `RUNS` times, and prints a summary. V9 (background) and V11
/// (PiP) are opt-in via `ONLY=V9` / `ONLY=V11`: they need an operator (adb) at the
/// printed `WAIT_*` markers and are meant for Android.
///
/// Every duration comes from real events (`MovaFirstFrame.sinceOpen`, event
/// arrival on one monotonic clock); nothing is estimated from wall-clock time,
/// and no seek goes near EOF. Every open appends `?t=<microseconds>` against caches.
///
/// 宿主易用性验证页（计划 Task 16）的脚本化 AUTORUN 模式：按固定顺序各跑 V1–V8、V10、V12
/// 共 `RUNS` 次并打印汇总。V9（进后台）与 V11（PiP）用 `ONLY=V9` / `ONLY=V11` 点名才跑：需要操作者（adb）在打印出的
/// `WAIT_*` 标记处动手，面向 Android。
///
/// 所有耗时都来自真实事件（`MovaFirstFrame.sinceOpen`、同一单调时钟上的事件到达），不用
/// 墙钟估算，也不 seek 到临近 EOF。每次打开都追加 `?t=<微秒>` 防缓存。
///
/// Example / 示例:
/// ```text
/// flutter run -d windows --profile -t lib/main_host_ergonomics_verify.dart \
///   --dart-define=AUTORUN=true --dart-define=RUNS=3 --dart-define=BASE=http://127.0.0.1:18080 \
///   --dart-define=LOG_FILE=C:/tmp/he.log
/// ```

/// Base URL of the local source server (`live_server.py`: /live.flv /hang /stall.mp4 /vod.mp4).
///
/// 本地源服务器的基地址（`live_server.py`：/live.flv /hang /stall.mp4 /vod.mp4）。
const String kBase = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18080');

/// An address nothing listens on (connection refused).
///
/// 没人监听的地址（拒连）。
const String kRefused = String.fromEnvironment('REFUSED_URL', defaultValue: 'http://127.0.0.1:9/x.flv');

/// GOP in frames (25 fps) of the live source.
///
/// 直播源的 GOP（帧数，25fps）。
const int kGop = int.fromEnvironment('GOP', defaultValue: 50);

/// Repetitions of V4 (stale RESTART race); the plan asks for 20.
///
/// V4（陈旧 RESTART 竞态）的重复次数；计划要求 20。
const int kV4Reps = int.fromEnvironment('V4_REPS', defaultValue: 20);

/// `startTimeout` in seconds used by the recovery scenarios.
///
/// recovery 场景使用的 `startTimeout`（秒）。
const int kStartTimeoutS = int.fromEnvironment('START_TIMEOUT_S', defaultValue: 4);

/// `stallTimeout` in seconds used by V6.
///
/// V6 使用的 `stallTimeout`（秒）。
const int kStallTimeoutS = int.fromEnvironment('STALL_TIMEOUT_S', defaultValue: 4);

/// Exit the process when the script is done (default true).
///
/// 脚本跑完后退出进程（默认 true）。
const bool kAutoExit = bool.fromEnvironment('AUTOEXIT', defaultValue: true);

/// Seconds the marker-driven scenarios (V9, V11) wait for the operator (adb) to act.
///
/// 靠日志标记驱动的场景（V9、V11）等待操作者（adb）动手的秒数。
const int kWaitS = int.fromEnvironment('WAIT_S', defaultValue: 90);

/// One engine configuration of the script.
///
/// 脚本里的一组引擎配置。
class _Cfg {
  const _Cfg({
    required this.source,
    this.options = const MovaOpts(),
    this.precise = true,
    this.autoPlay = true,
    this.guard = false,
    this.reporter,
  });

  final MovaSource source;
  final MovaOpts options;
  final bool precise;
  final bool autoPlay;
  final bool guard;
  final MovaReporter? reporter;

  _Cfg withSource(MovaSource s) =>
      _Cfg(source: s, options: options, precise: precise, autoPlay: autoPlay, guard: guard, reporter: reporter);
}

/// A scripted scenario.
///
/// 一个脚本化场景。
class _Scenario {
  const _Scenario(this.id, this.title, this.run, {this.single = false, this.optIn = false});
  final String id;
  final String title;
  final Future<void> Function(int run) run;

  /// Runs once instead of `RUNS` times (the scenario repeats inside itself).
  ///
  /// 只跑一次而不是 `RUNS` 次（场景内部自带重复）。
  final bool single;

  /// Runs only when named in `ONLY` (not part of the default sequence).
  ///
  /// 只有 `ONLY` 点名时才跑（不在默认序列里）。
  final bool optIn;
}

/// The scripted page.
///
/// 脚本化页面。
class HeAutoPage extends StatefulWidget {
  /// Creates the page and starts the script after the first frame.
  ///
  /// 创建页面，首帧之后开始跑脚本。
  const HeAutoPage({super.key});

  @override
  State<HeAutoPage> createState() => _HeAutoPageState();
}

class _HeAutoPageState extends State<HeAutoPage> with WidgetsBindingObserver {
  final AutoLog _out = AutoLog('[MOVA-HE]');
  final Stopwatch _clock = Stopwatch()..start();
  final Samples _samples = Samples();
  final Map<String, int> _pass = <String, int>{};
  final Map<String, int> _fail = <String, int>{};
  final List<String> _lines = <String>[];

  final StreamController<AppLifecycleState> _life = StreamController<AppLifecycleState>.broadcast();
  late final EventRecorder<AppLifecycleState> _lifeRec = EventRecorder<AppLifecycleState>(_life.stream, clock: _clock);

  _Cfg? _cfg;
  int _epoch = 0;
  bool _tickerOn = true;
  Completer<void>? _engineReady;
  MovaApi? _api;
  EventRecorder<MovaEvent>? _ev;
  EventRecorder<MovaState>? _st;
  EventRecorder<MovaProg>? _pg;
  Duration _openAt = Duration.zero;
  final List<Object> _openErrors = <Object>[];

  /// Source URLs.
  String get _liveUrl => '$kBase/live.flv?gop=$kGop&audio=1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifeRec; // start recording lifecycle states from the very beginning
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runAll()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_lifeRec.dispose());
    unawaited(_life.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('LIFECYCLE ${state.name}');
    _life.add(state);
  }

  /// Logs one line (page + stdout/logcat + file), prefixed with a wall-clock stamp for correlation only.
  void _log(String msg) {
    final line = _out.line('${DateTime.now().toIso8601String().substring(11, 23)} $msg');
    if (mounted) setState(() => _lines.insert(0, line));
  }

  /// Records a PASS/FAIL verdict for [id].
  void _verdict(String id, bool ok, String note) {
    (ok ? _pass : _fail).update(id, (v) => v + 1, ifAbsent: () => 1);
    _log('VERDICT $id ${ok ? 'PASS' : 'FAIL'} $note');
  }

  /// Source with a fresh cache-busting `t=`.
  MovaSource _src(String url, {MovaStreamType type = MovaStreamType.live, List<String> alts = const []}) {
    String stamp(String u) {
      final uri = Uri.parse(u);
      return uri
          .replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().microsecondsSinceEpoch}'})
          .toString();
    }

    return MovaSource(stamp(url), type: type, alternatives: [for (final a in alts) stamp(a)]);
  }

  MovaSource get _live => _src(_liveUrl);
  MovaSource get _vod => _src('$kBase/vod.mp4', type: MovaStreamType.vod);

  MovaOpts _recovery({int? stallS}) => MovaOpts(
    recovery: MovaRecoveryConfig(
      enabled: true,
      startTimeout: const Duration(seconds: kStartTimeoutS),
      stallTimeout: stallS == null ? null : Duration(seconds: stallS),
    ),
  );

  /// Engine just created by `MovaView`: attach recorders before its `open()` starts.
  void _onEngine(MovaApi api) {
    _api = api;
    _ev = EventRecorder<MovaEvent>(api.events, clock: _clock);
    _st = EventRecorder<MovaState>(api.states, clock: _clock);
    _pg = EventRecorder<MovaProg>(api.progress, clock: _clock);
    _openAt = _clock.elapsed;
    _engineReady?.complete();
  }

  /// Tears the current view/engine down.
  Future<void> _stop() async {
    if (_cfg == null) return;
    await _ev?.dispose();
    await _st?.dispose();
    await _pg?.dispose();
    _ev = _st = null;
    _pg = null;
    _api = null;
    setState(() {
      _cfg = null;
      _tickerOn = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  /// Builds a fresh `MovaView` (hence a fresh engine) for [cfg] and waits until it exists.
  Future<void> _start(_Cfg cfg) async {
    await _stop();
    _openErrors.clear();
    _engineReady = Completer<void>();
    setState(() {
      _cfg = cfg;
      _epoch++;
    });
    await _engineReady!.future.timeout(const Duration(seconds: 10));
  }

  Future<Stamped<MovaFirstFrame>?> _firstFrame({int from = 0, Duration timeout = const Duration(seconds: 15)}) =>
      _ev!.wait<MovaFirstFrame>(from: from, timeout: timeout);

  /// Ms of [s] since the engine was created (the `open()` of the first source starts right then).
  int _sinceStart(Stamped<Object> s) => msBetween(_openAt, s.at);

  // ---- scenarios -----------------------------------------------------------------------------

  /// V1: first-frame precision, precise on/off, against the QoE `ttffMs`.
  Future<void> _v1(int run) async {
    for (final precise in <bool>[true, false]) {
      final qoe = <int>[];
      final cfg = _Cfg(
        source: _live,
        precise: precise,
        options: precise ? const MovaOpts(report: MovaReportConfig(qoe: true)) : const MovaOpts(),
        reporter: precise
            ? MovaCallbackReporter((e) {
                if (e.name == MovaReportName.firstFrame) qoe.add(e.params['ttffMs'] as int);
              })
            : null,
      );
      await _start(cfg);
      final ff = await _firstFrame();
      if (ff == null) {
        _verdict('V1', false, 'precise=$precise no MovaFirstFrame');
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final ms = ff.event.sinceOpen.inMilliseconds;
      final sig = ff.event.signal.name;
      _samples.add('V1.precise=$precise.sinceOpenMs', ms);
      if (precise) {
        final q = qoe.isEmpty ? null : qoe.first;
        _log('V1 precise=true signal=$sig sinceOpen=${ms}ms qoeTtff=${q}ms');
        if (q != null) _samples.add('V1.precise=true.diffToQoeMs', (ms - q).abs());
        _verdict('V1', sig == 'restart' && q != null && (ms - q).abs() < 50, 'precise=true signal=$sig diff=${q == null ? 'n/a' : (ms - q).abs()}ms');
      } else {
        _log('V1 precise=false signal=$sig sinceOpen=${ms}ms');
        _verdict('V1', sig != 'restart', 'precise=false signal=$sig');
      }
    }
  }

  /// V2: does a paused open still get a RESTART?
  Future<void> _v2(int run) async {
    await _start(_Cfg(source: _live, autoPlay: false));
    final ff = await _firstFrame(timeout: const Duration(seconds: 10));
    final sig = ff?.event.signal.name ?? 'none';
    _log('V2 autoPlay=false signal=$sig sinceOpen=${ff?.event.sinceOpen.inMilliseconds}ms');
    if (ff != null) _samples.add('V2.sinceOpenMs', ff.event.sinceOpen.inMilliseconds);
    _samples.add('V2.signal.$sig', 1);
    _verdict('V2', ff != null, 'fact signal=$sig');
  }

  /// V3: source change resets `rendered` and yields a new first frame.
  Future<void> _v3(int run) async {
    await _start(_Cfg(source: _live));
    if (await _firstFrame() == null) return _verdict('V3', false, 'A never rendered');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final evMark = _ev!.mark;
    final stMark = _st!.mark;
    final swapAt = _clock.elapsed;
    setState(() => _cfg = _cfg!.withSource(_live));
    final reset = await _st!.wait<MovaState>(from: stMark, where: (s) => !s.rendered, timeout: const Duration(seconds: 5));
    final ff = await _firstFrame(from: evMark);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final count = _ev!.all<MovaFirstFrame>(from: evMark).length;
    final resetMs = reset == null ? null : msBetween(swapAt, reset.at);
    _log('V3 renderedFalseAfter=${resetMs}ms newFirstFrame=${ff?.event.sinceOpen.inMilliseconds}ms signal=${ff?.event.signal.name} firstFrameEvents=$count renderedNow=${_api!.state.rendered}');
    if (resetMs != null) _samples.add('V3.renderedFalseDelayMs', resetMs);
    if (ff != null) _samples.add('V3.sinceOpenMs', ff.event.sinceOpen.inMilliseconds);
    _verdict('V3', reset != null && ff != null && count == 1 && _api!.state.rendered, 'reset=${reset != null} ff=${ff != null} events=$count');
  }

  /// V4: stale RESTART race: seek on A, then open B within <=50 ms; B's first frame must not be < 100 ms.
  Future<void> _v4(int run) async {
    await _start(_Cfg(source: _vod));
    final api = _api!;
    var tooEarly = 0;
    var missing = 0;
    final sinces = <int>[];
    for (var i = 0; i < kV4Reps; i++) {
      if (i == 0) {
        if (await _firstFrame() == null) return _verdict('V4', false, 'A never rendered');
      } else {
        final m = _ev!.mark;
        await api.open(_vod);
        if (await _firstFrame(from: m) == null) {
          missing++;
          continue;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      unawaited(api.seek(Duration(seconds: 5 + i % 5)));
      final gapMs = 10 + (i % 5) * 10;
      await Future<void>.delayed(Duration(milliseconds: gapMs));
      final m2 = _ev!.mark;
      await api.open(_live);
      final ff = await _firstFrame(from: m2);
      if (ff == null) {
        missing++;
        continue;
      }
      final ms = ff.event.sinceOpen.inMilliseconds;
      sinces.add(ms);
      _samples.add('V4.sinceOpenMs', ms);
      if (ms < 100) tooEarly++;
      _log('V4 rep=$i seekToOpenGap=${gapMs}ms B.sinceOpen=${ms}ms signal=${ff.event.signal.name}');
    }
    _verdict('V4', tooEarly == 0 && missing == 0, 'reps=$kV4Reps tooEarly(<100ms)=$tooEarly missing=$missing min=${sinces.isEmpty ? 'n/a' : Stats(sinces).min}ms');
  }

  /// V5: start timeout against a server that accepts and never answers.
  Future<void> _v5(int run) async {
    await _start(_Cfg(source: _src('$kBase/hang'), options: _recovery()));
    final giveUp = await _ev!.wait<MovaErrorEvent>(
      where: (e) => e.error is MovaGiveUpError,
      timeout: Duration(seconds: kStartTimeoutS * 3 + 10),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    final fails = _ev!.all<MovaPlayFailure>();
    final gaveUps = _ev!.all<MovaErrorEvent>(where: (e) => e.error is MovaGiveUpError).length;
    for (final f in fails) {
      _log('V5 PlayFailure kind=${f.event.fail.kind.name} attempt=${f.event.fail.attempt} action=${f.event.action.name} at=${_sinceStart(f)}ms waited=${f.event.fail.waited.inMilliseconds}ms');
    }
    if (fails.isEmpty) return _verdict('V5', false, 'no PlayFailure; giveUp=${giveUp != null}');
    final first = _sinceStart(fails.first);
    final dev = (first - kStartTimeoutS * 1000).abs();
    _samples.add('V5.firstFailureDeviationMs', dev);
    _log('V5 firstFailure=${first}ms startTimeout=${kStartTimeoutS * 1000}ms deviation=${dev}ms failures=${fails.length} retries=${fails.where((f) => f.event.action == MovaRecoveryAction.retry).length} giveUpEvents=$gaveUps state.error=${_api!.state.error}');
    _verdict('V5', dev < 300 && gaveUps == 1 && fails.first.event.fail.kind == MovaPlayFailKind.startTimeout, 'deviation=${dev}ms giveUps=$gaveUps');
  }

  /// Tells the source server to stop stalling this source (`/release?t=<key>`).
  Future<void> _release(String uri) async {
    final key = Uri.parse(uri).queryParameters['t'] ?? '';
    final c = HttpClient();
    try {
      final r = await (await c.getUrl(Uri.parse('$kBase/release?t=$key'))).close();
      await r.drain<void>();
    } finally {
      c.close(force: true);
    }
  }

  /// V6: stall timeout then resume near the failed position. The server stalls every connection of
  /// this source after ~10% of the file until the page releases it on the `PlayFailure` event
  /// (mpv reconnects by itself within seconds, so a one-shot stall would heal on its own).
  Future<void> _v6(int run) async {
    final src = _src('$kBase/stall.mp4', type: MovaStreamType.vod);
    await _start(_Cfg(source: src, options: _recovery(stallS: kStallTimeoutS)));
    final ff = await _firstFrame();
    if (ff == null) return _verdict('V6', false, 'never rendered');
    final m = _ev!.mark;
    final buf = await _ev!.wait<MovaBufferChange>(from: m, where: (e) => e.buffering, timeout: const Duration(seconds: 30));
    final pf = await _ev!.wait<MovaPlayFailure>(from: m, timeout: Duration(seconds: kStallTimeoutS + 20));
    if (buf == null || pf == null) return _verdict('V6', false, 'buffering=${buf != null} failure=${pf != null}');
    final stAtFail = _api!.state;
    _log('V6 stateAtFailure type=${stAtFail.type.name} rendered=${stAtFail.rendered} duration=${stAtFail.duration.inMilliseconds}ms buffering=${stAtFail.buffering}');
    await _release(src.uri);
    final before = _pg!.all<MovaProg>().where((p) => p.at <= pf.at).lastOrNull;
    final afterFf = await _firstFrame(from: _ev!.log.indexOf(pf) + 1, timeout: const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 5500));
    // The retry reloads from 0 and then seeks to the failed position, so the first samples after its
    // first frame are near 0. Resume is judged on whether a sample near the failed position shows up
    // within 1.5 s of that first frame (playing on from 0 could not get there that fast).
    final window = afterFf == null
        ? <Stamped<MovaProg>>[]
        : _pg!.all<MovaProg>().where((p) => p.at >= afterFf.at && msBetween(afterFf.at, p.at) <= 5000).toList();
    final posBefore = before?.event.position.inMilliseconds;
    final jumped = posBefore == null ? null : window.where((p) => (p.event.position.inMilliseconds - posBefore).abs() < 500).firstOrNull;
    final near = jumped != null && msBetween(afterFf!.at, jumped.at) <= 1500 ? jumped : null;
    final posAfter = jumped?.event.position.inMilliseconds ?? window.lastOrNull?.event.position.inMilliseconds;
    final posDiff = posBefore == null || posAfter == null ? null : (posAfter - posBefore).abs();
    final lag = msBetween(buf.at, pf.at) - kStallTimeoutS * 1000;
    _samples.add('V6.failureMinusBufferingMinusTimeoutMs', lag);
    if (posDiff != null) _samples.add('V6.resumePositionDiffMs', posDiff);
    final seq = window.where((p) => window.indexOf(p) % 4 == 0).take(10).map((p) => '+${msBetween(afterFf!.at, p.at)}ms:${p.event.position.inMilliseconds}').join(' ');
    _log('V6 kind=${pf.event.fail.kind.name} bufferingTrueToFailure=${msBetween(buf.at, pf.at)}ms (stallTimeout=${kStallTimeoutS * 1000}ms, offset=${lag}ms) posBefore=${posBefore}ms posAfterRetry=${posAfter}ms diff=${posDiff}ms recovered=${_ev!.all<MovaRecovered>().length} samplesAfterRetryFirstFrame=[$seq]');
    _verdict('V6', pf.event.fail.kind == MovaPlayFailKind.stallTimeout && lag.abs() < 500 && near != null, 'offset=${lag}ms posDiff=${posDiff}ms');
  }

  /// V7: failover (bad primary + good alternate) and give-up (both bad).
  Future<void> _v7(int run) async {
    await _start(_Cfg(source: _src(kRefused, alts: [_liveUrl]), options: _recovery()));
    final fo = await _ev!.wait<MovaFailover>(timeout: const Duration(seconds: 30));
    final ff = await _firstFrame(timeout: const Duration(seconds: 30));
    _log('V7a failover=${fo == null ? null : '${fo.event.from}->${fo.event.to}'} firstFrame=${ff?.event.sinceOpen.inMilliseconds}ms sourceIndex=${_api!.state.sourceIndex} atFailover=${fo == null ? null : _sinceStart(fo)}ms');
    _verdict('V7', fo != null && fo.event.from == 0 && fo.event.to == 1 && ff != null && _api!.state.sourceIndex == 1, 'a: bad->good');
    await _start(_Cfg(source: _src('$kBase/missing404.flv', alts: [kRefused]), options: _recovery()));
    final g = await _ev!.wait<MovaErrorEvent>(where: (e) => e.error is MovaGiveUpError, timeout: const Duration(seconds: 40));
    final last = g == null ? null : (g.event.error as MovaGiveUpError).last;
    _log('V7b giveUp=${g != null} last.sourceIndex=${last?.sourceIndex} last.kind=${last?.kind.name} failures=${_ev!.all<MovaPlayFailure>().length} at=${g == null ? null : _sinceStart(g)}ms');
    _verdict('V7', last != null && last.sourceIndex == 1, 'b: bad->bad');
  }

  /// V8: how fast a bad address is judged (before the start timeout).
  Future<void> _v8(int run) async {
    for (final url in <String>[kRefused, '$kBase/missing404.flv']) {
      await _start(_Cfg(
        source: _src(url),
        options: const MovaOpts(recovery: MovaRecoveryConfig(enabled: true, startTimeout: Duration(seconds: 15))),
      ));
      final pf = await _ev!.wait<MovaPlayFailure>(timeout: const Duration(seconds: 20));
      final tag = url == kRefused ? 'refused' : '404';
      if (pf == null) {
        _verdict('V8', false, '$tag no failure within 20s');
        continue;
      }
      final ms = _sinceStart(pf);
      _samples.add('V8.$tag.failureMs', ms);
      _log('V8 $tag kind=${pf.event.fail.kind.name} at=${ms}ms waited=${pf.event.fail.waited.inMilliseconds}ms openErrors=${_openErrors.length}');
      _verdict('V8', ms < 15000, '$tag kind=${pf.event.fail.kind.name} ${ms}ms');
    }
  }

  /// V10 (the parts this page can drive): a covering route and `TickerMode` pause and resume playback.
  /// [route] / [ticker] pick the parts, [guard] turns the auto-pause guard on. The sub-ids V10A/V10B/V10C
  /// (opt-in via `ONLY`) isolate one part each; a log line before every action survives a native crash.
  Future<void> _v10Parts(String id, {required bool route, required bool ticker, bool guard = true}) async {
    final nav = Navigator.of(context);
    await _start(_Cfg(source: _live, guard: guard));
    if (await _firstFrame() == null) return _verdict(id, false, 'never rendered');
    await Future<void>.delayed(const Duration(seconds: 1));
    var ok = true;
    var m = _ev!.mark;
    if (route) {
      _log('$id action: push covering route');
      final pushed = _clock.elapsed;
      unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('covering page'))))));
      final pause = await _ev!.wait<MovaPause>(from: m, timeout: const Duration(seconds: 5));
      _log('$id route covered; pause=${pause != null}');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      m = _ev!.mark;
      _log('$id action: pop covering route');
      final popped = _clock.elapsed;
      nav.pop();
      final play = await _ev!.wait<MovaPlay>(from: m, timeout: const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(seconds: 1));
      final pauseMs = pause == null ? null : msBetween(pushed, pause.at);
      final playMs = play == null ? null : msBetween(popped, play.at);
      if (pauseMs != null) _samples.add('$id.route.pauseMs', pauseMs);
      if (playMs != null) _samples.add('$id.route.playMs', playMs);
      _log('$id route: pauseAfter=${pauseMs}ms playAfter=${playMs}ms');
      ok = ok && pause != null && play != null;
    }
    if (ticker) {
      m = _ev!.mark;
      _log('$id action: TickerMode off');
      final off = _clock.elapsed;
      setState(() => _tickerOn = false);
      final pause2 = await _ev!.wait<MovaPause>(from: m, timeout: const Duration(seconds: 5));
      _log('$id ticker off; pause=${pause2 != null}');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      m = _ev!.mark;
      _log('$id action: TickerMode on');
      final on = _clock.elapsed;
      setState(() => _tickerOn = true);
      final play2 = await _ev!.wait<MovaPlay>(from: m, timeout: const Duration(seconds: 8));
      final tPause = pause2 == null ? null : msBetween(off, pause2.at);
      final tPlay = play2 == null ? null : msBetween(on, play2.at);
      if (tPause != null) _samples.add('$id.ticker.pauseMs', tPause);
      if (tPlay != null) _samples.add('$id.ticker.playMs', tPlay);
      _log('$id tickerMode: pauseAfter=${tPause}ms playAfter=${tPlay}ms liveEdgeReach=${_ev!.all<MovaLiveEdgeReach>().length}');
      ok = ok && pause2 != null && play2 != null;
    }
    _verdict(id, ok, 'route=$route ticker=$ticker guard=$guard');
  }

  Future<void> _v10(int run) => _v10Parts('V10', route: true, ticker: true);
  Future<void> _v10a(int run) => _v10Parts('V10A', route: true, ticker: false);
  Future<void> _v10b(int run) => _v10Parts('V10B', route: false, ticker: true);
  Future<void> _v10c(int run) => _v10Parts('V10C', route: true, ticker: false, guard: false);

  /// V9 (Android; opt-in via `ONLY=V9`): playing live with the guard on; the operator sends the app to the
  /// background (`adb shell input keyevent KEYCODE_HOME`) and back (`adb shell am start -n <pkg>/.MainActivity`)
  /// when the page prints `V9 WAIT_HOME` / `V9 WAIT_FOREGROUND`. Logs the lifecycle sequence, the guard's
  /// `MovaPause`, the foreground `MovaPlay` / `MovaLiveEdgeReach`, and whether the position advances again.
  Future<void> _v9(int run) async {
    await _start(_Cfg(source: _live, guard: true));
    if (await _firstFrame() == null) return _verdict('V9', false, 'never rendered');
    await Future<void>.delayed(const Duration(seconds: 1));
    final m = _ev!.mark;
    final lm = _lifeRec.mark;
    final marker = _clock.elapsed;
    _log('V9 WAIT_HOME send the app to the background now (waiting up to ${kWaitS}s)');
    final pause = await _ev!.wait<MovaPause>(from: m, timeout: Duration(seconds: kWaitS));
    if (pause == null) return _verdict('V9', false, 'no MovaPause after going to the background');
    _log('V9 guard MovaPause ${msBetween(marker, pause.at)}ms after the marker');
    final m2 = _ev!.mark;
    _log('V9 WAIT_FOREGROUND bring the app back now (waiting up to ${kWaitS}s)');
    final play = await _ev!.wait<MovaPlay>(from: m2, timeout: Duration(seconds: kWaitS));
    final edge = await _ev!.wait<MovaLiveEdgeReach>(from: m2, timeout: const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(seconds: 3)); // let a reload to the live edge get going
    final p0 = _lastProg;
    await Future<void>.delayed(const Duration(seconds: 3));
    final p1 = _lastProg;
    final advance = p0 == null || p1 == null ? null : (p1.position - p0.position).inMilliseconds;
    final life = _lifeRec.all<AppLifecycleState>(from: lm).map((e) => e.event.name).join(',');
    _log('V9 lifecycle=[$life] play=${play != null} liveEdgeReach=${edge != null} positionAdvanceOver3s=${advance}ms rendered=${_api!.state.rendered} playing=${_api!.state.playing}');
    _verdict('V9', play != null && advance != null && advance > 2000, 'play=${play != null} advance=${advance}ms (needs no manual play tap)');
  }

  /// V11 (Android; opt-in via `ONLY=V11`): entering system PiP must not trigger the guard's pause.
  /// Prints `V11 WAIT_RESTORE` after the check; bring the app back to full screen to continue.
  Future<void> _v11(int run) async {
    await _start(_Cfg(source: _live, guard: true));
    if (await _firstFrame() == null) return _verdict('V11', false, 'never rendered');
    final api = _api!;
    if (!api.pipSupported) return _verdict('V11', true, 'n/a: pipSupported=false on this platform');
    await Future<void>.delayed(const Duration(seconds: 1));
    final m = _ev!.mark;
    final entered = await api.enterPip();
    await Future<void>.delayed(const Duration(seconds: 6));
    final pauses = _ev!.all<MovaPause>(from: m).length;
    final changes = _ev!.all<MovaPipChange>(from: m).map((e) => e.event.value).toList();
    _log('V11 enterPip=$entered pipChange=$changes pauseEvents=$pauses state.pip=${api.state.pip} playing=${api.state.playing}');
    _verdict('V11', entered && pauses == 0, 'enterPip=$entered pauseEvents=$pauses');
    _log('V11 WAIT_RESTORE bring the app back to full screen (waiting up to ${kWaitS}s)');
    await _ev!.wait<MovaPipChange>(from: m, where: (e) => !e.value, timeout: Duration(seconds: kWaitS));
  }

  MovaProg? get _lastProg => _pg!.log.lastOrNull?.event;

  /// V12: default parameters: only the first-frame event is new, no recovery/standby events, `open()` failures still throw.
  Future<void> _v12(int run) async {
    await _start(_Cfg(source: _vod, precise: false));
    if (await _firstFrame() == null) return _verdict('V12', false, 'never rendered');
    final api = _api!;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await api.pause();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await api.seek(const Duration(seconds: 3));
    await api.play();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    var threw = false;
    try {
      await api.open(_src(kRefused, type: MovaStreamType.vod));
      await Future<void>.delayed(const Duration(seconds: 3));
    } catch (e) {
      threw = true;
    }
    final names = _ev!.log.map((s) => s.event.runtimeType.toString()).toList();
    final foreign = names.where((n) => const {'MovaPlayFailure', 'MovaRecovered', 'MovaFailover', 'MovaStandbyChange', 'MovaStandbyResume'}.contains(n)).toList();
    _log('V12 events=${names.join(',')}');
    _log('V12 badOpenThrew=$threw errorEvents=${names.where((n) => n == 'MovaErrorEvent').length} state.standby=${api.state.standby.name}');
    _verdict('V12', foreign.isEmpty && api.state.standby == MovaStandbyPhase.off, 'foreignEvents=$foreign');
  }

  // ---- driver --------------------------------------------------------------------------------

  Future<void> _runAll() async {
    final only = parseOnly(autoOnlyRaw());
    final runs = autoRuns();
    final scenarios = <_Scenario>[
      _Scenario('V1', 'first-frame precision', _v1),
      _Scenario('V2', 'paused open signal', _v2),
      _Scenario('V3', 'source change reset', _v3),
      _Scenario('V4', 'stale RESTART race', _v4, single: true),
      _Scenario('V5', 'start timeout', _v5),
      _Scenario('V6', 'stall timeout + resume', _v6),
      _Scenario('V7', 'failover / give up', _v7),
      _Scenario('V8', 'bad address verdict', _v8),
      _Scenario('V12', 'closed-state regression', _v12),
      // V10 last: a native crash there (see the plan's Windows results) must not hide the other scenarios.
      _Scenario('V10', 'route + TickerMode pause', _v10),
      _Scenario('V9', 'background / foreground (Android, marker-driven)', _v9, optIn: true),
      _Scenario('V11', 'system PiP is not paused (Android)', _v11, optIn: true),
      _Scenario('V10A', 'route cover only (guard on)', _v10a, optIn: true),
      _Scenario('V10B', 'TickerMode only (guard on)', _v10b, optIn: true),
      _Scenario('V10C', 'route cover only (guard off)', _v10c, optIn: true),
    ];
    _log('AUTORUN start runs=$runs base=$kBase gop=$kGop startTimeout=${kStartTimeoutS}s stallTimeout=${kStallTimeoutS}s only=${only.isEmpty ? 'all' : only.join(',')} mode=${const bool.fromEnvironment('dart.vm.product') ? 'release' : const bool.fromEnvironment('dart.vm.profile') ? 'profile' : 'debug'} os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    for (final s in scenarios) {
      if (only.isNotEmpty ? !only.contains(s.id) : s.optIn) continue;
      final n = s.single ? 1 : runs;
      for (var run = 1; run <= n; run++) {
        _log('--- ${s.id} ${s.title} run $run/$n');
        try {
          await s.run(run);
        } catch (e, st) {
          _verdict(s.id, false, 'script error: $e\n$st');
        }
      }
      await _stop();
    }
    _log('=== SUMMARY (samples in ms) ===');
    for (final l in _samples.summary()) {
      _log('SUMMARY $l');
    }
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
    final cfg = _cfg;
    return Scaffold(
      appBar: AppBar(title: const Text('host ergonomics AUTORUN')),
      body: Column(
        children: [
          if (cfg != null)
            TickerMode(
              enabled: _tickerOn,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: MovaView(
                  key: ValueKey<int>(_epoch),
                  source: cfg.source,
                  autoPlay: cfg.autoPlay,
                  fit: MovaFit.cover,
                  poster: const ColoredBox(color: Color(0xFF223344), child: Center(child: Text('POSTER'))),
                  skin: const MovaMinimalSkin(),
                  options: cfg.options,
                  autoPause: cfg.guard ? const MovaAutoPauseConfig() : null,
                  engineFactory: (o) => createMovaEngine(options: o, preciseFirstFrame: cfg.precise, reporter: cfg.reporter),
                  onEngine: _onEngine,
                  onOpenError: (e, s) {
                    _openErrors.add(e);
                    _log('openError $e');
                  },
                ),
              ),
            ),
          Expanded(
            child: ListView(children: [for (final l in _lines.take(60)) Text(l, style: const TextStyle(fontSize: 11))]),
          ),
        ],
      ),
    );
  }
}
