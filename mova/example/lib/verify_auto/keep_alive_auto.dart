// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

import 'auto_kit.dart';

/// Scripted AUTORUN mode of `main_keep_alive_verify.dart` (plan
/// doc/plans/2026-10-23-standby-mode.md, Task 10). Covers the items that do not
/// need Android: S1-S6, S13, S14, S15, S16 and the TickerMode/source-change part
/// of S17, each [autoRuns] times. S7, S8, S8B are opt-in (`ONLY=S7` ...) and meant for Android
/// (S8/S8B wait for an operator at the printed `WAIT_*` markers); S9-S12 are not scripted here.
///
/// Every duration comes from real events: `MovaKeepAliveResume.elapsed` (taken by the
/// engine at the wake-up call and at the landing), `MovaFirstFrame.sinceOpen`,
/// event arrival on one monotonic clock and kernel property reads. No seek goes
/// near EOF and every open appends `?t=<microseconds>`. CPU and traffic are not
/// measurable from inside the page: the script prints `PHASE <name> begin/end`
/// lines (wall-clock stamped) so an external sampler can be lined up, and the
/// source server logs bytes per connection.
///
/// 低功耗待机验证页（计划 Task 10）的脚本化 AUTORUN 模式。覆盖不需要 Android 的项：
/// S1–S6、S13、S14、S15、S16，以及 S17 里 TickerMode/隐藏期间换源的部分，各跑 [autoRuns] 次。
/// S7–S9、S11 需要 Android；S10/S12 计划里不实现。
///
/// 所有耗时都来自真实事件：`MovaKeepAliveResume.elapsed`（引擎在唤醒调用与落地处取时）、
/// `MovaFirstFrame.sinceOpen`、同一单调时钟上的事件到达、内核属性读取。不 seek 到临近 EOF，
/// 每次打开都追加 `?t=<微秒>`。CPU 与流量在页面内测不了：脚本打印 `PHASE <name> begin/end`
/// 行（带墙钟时间，仅用于和外部采样器对齐），流量由源服务器按连接记录。
///
/// Example / 示例:
/// ```text
/// flutter run -d windows --release -t lib/main_keep_alive_verify.dart \
///   --dart-define=AUTORUN=true --dart-define=BASE=http://127.0.0.1:18080 \
///   --dart-define=HLS_URL=http://127.0.0.1:18081/live.m3u8 --dart-define=LOG_FILE=C:/tmp/keepAlive.log
/// ```

/// Base URL of the local source server (`/live.flv?gop=&audio=`).
///
/// 本地源服务器基地址（`/live.flv?gop=&audio=`）。
const String kBase = String.fromEnvironment('BASE', defaultValue: 'http://127.0.0.1:18080');

/// HLS live source.
///
/// HLS 直播源。
const String kHlsUrl = String.fromEnvironment('HLS_URL', defaultValue: 'http://127.0.0.1:18081/live.m3u8');

/// GOP sizes (frames at 25 fps) swept by S1: 25/50/100 = 1s/2s/4s.
///
/// S1 扫描的 GOP（25fps 下的帧数）：25/50/100 即 1s/2s/4s。
const String kGops = String.fromEnvironment('GOPS', defaultValue: '25,50,100');

/// Hold durations in seconds swept by S1.
///
/// S1 扫描的待机时长（秒）。
const String kHolds = String.fromEnvironment('HOLDS', defaultValue: '10,30');

/// S3 hold seconds.
///
/// S3 的待机秒数。
const int kS3Seconds = int.fromEnvironment('S3_SECONDS', defaultValue: 30);

/// Seconds of each mode window in S4.
///
/// S4 每个模式窗口的秒数。
const int kS4Seconds = int.fromEnvironment('S4_SECONDS', defaultValue: 30);

/// S5 hold seconds.
///
/// S5 的待机秒数。
const int kS5Seconds = int.fromEnvironment('S5_SECONDS', defaultValue: 60);

/// Delays in ms after open at which S16 asks for keepAlive.
///
/// S16 在打开后多少毫秒请求待机。
const String kS16Delays = String.fromEnvironment('S16_DELAYS', defaultValue: '500,1000,2000,3000');

/// Exit the process when the script is done (default true).
///
/// 脚本跑完后退出进程（默认 true）。
const bool kAutoExit = bool.fromEnvironment('AUTOEXIT', defaultValue: true);

/// Cycles of S7 (`vid` switched off and on again).
///
/// S7 的 `vid` 关/开循环次数。
const int kS7Cycles = int.fromEnvironment('S7_CYCLES', defaultValue: 20);

/// Seconds the marker-driven scenarios (S8, S8B) wait for the operator (adb) to act.
///
/// 靠日志标记驱动的场景（S8、S8B）等待操作者（adb）动手的秒数。
const int kWaitS = int.fromEnvironment('WAIT_S', defaultValue: 600);

/// Parses a comma separated int list.
///
/// 解析逗号分隔的整数列表。
///
/// - [raw]: e.g. `25,50,100` / 如 `25,50,100`
///
/// Returns the ints (bad items dropped) / 返回整数列表（丢弃非法项）。
List<int> parseInts(String raw) => [
  for (final s in raw.split(',')) ?int.tryParse(s.trim()),
];

/// One engine configuration of the script.
///
/// 脚本里的一组引擎配置。
class _Cfg {
  const _Cfg({
    required this.source,
    this.keepAlive = const MovaKeepAliveConfig(maxDuration: Duration(seconds: 300)),
    this.guard = false,
  });

  final MovaSource source;
  final MovaKeepAliveConfig keepAlive;
  final bool guard;
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

  /// Runs only when named in `ONLY`.
  ///
  /// 只有 `ONLY` 点名时才跑。
  final bool optIn;
}

/// The scripted page.
///
/// 脚本化页面。
class KeepAliveAutoPage extends StatefulWidget {
  /// Creates the page and starts the script after the first frame.
  ///
  /// 创建页面，首帧之后开始跑脚本。
  const KeepAliveAutoPage({super.key});

  @override
  State<KeepAliveAutoPage> createState() => _KeepAliveAutoPageState();
}

class _KeepAliveAutoPageState extends State<KeepAliveAutoPage> with WidgetsBindingObserver {
  final AutoLog _out = AutoLog('[STANDBY]');
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
  Player? _player;
  MovaMpvKernel? _kernel;
  EventRecorder<MovaEvent>? _ev;
  EventRecorder<MovaProg>? _pg;
  Duration _openAt = Duration.zero;

  String _live({int gop = 50, bool audio = true}) => '$kBase/live.flv?gop=$gop&audio=${audio ? 1 : 0}';

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

  /// Logs one line (page + stdout/logcat + file); the wall-clock prefix is for lining up external samplers only.
  void _log(String msg) {
    final line = _out.line('${DateTime.now().toIso8601String().substring(11, 23)} ${_clock.elapsedMilliseconds.toString().padLeft(7)}ms $msg');
    if (mounted) setState(() => _lines.insert(0, line));
  }

  /// Marks the start/end of a measurement window for external CPU/traffic samplers.
  void _phase(String name, {required bool begin}) => _log('PHASE $name ${begin ? 'begin' : 'end'}');

  void _verdict(String id, bool ok, String note) {
    (ok ? _pass : _fail).update(id, (v) => v + 1, ifAbsent: () => 1);
    _log('VERDICT $id ${ok ? 'PASS' : 'FAIL'} $note');
  }

  MovaSource _src(String url) {
    final uri = Uri.parse(url);
    final stamped = uri
        .replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().microsecondsSinceEpoch}'})
        .toString();
    return MovaSource(stamped, type: MovaStreamType.live);
  }

  /// Builds the engine on a kernel we hold, so mpv properties and stats can be read.
  MovaApi _makeEngine(MovaOpts options) {
    final player = Player();
    final kernel = MovaMpvKernel(
      player: player,
      lazyVideo: true,
      observeQoeSignals: true,
      observeNativeEvents: true,
      backendFactory: (native, addr) => createFfiMpvEventBackend(native, addr, pollInDebug: kDebugMode),
    );
    _player = player;
    _kernel = kernel;
    return createMovaEngine(kernel: kernel, options: options, preciseFirstFrame: true);
  }

  void _onEngine(MovaApi api) {
    _api = api;
    _ev = EventRecorder<MovaEvent>(api.events, clock: _clock);
    _pg = EventRecorder<MovaProg>(api.progress, clock: _clock);
    _openAt = _clock.elapsed;
    _engineReady?.complete();
  }

  Future<void> _stop() async {
    if (_cfg == null) return;
    await _ev?.dispose();
    await _pg?.dispose();
    _ev = null;
    _pg = null;
    _api = null;
    _kernel = null;
    _player = null;
    setState(() {
      _cfg = null;
      _tickerOn = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  Future<void> _start(_Cfg cfg) async {
    await _stop();
    _engineReady = Completer<void>();
    setState(() {
      _cfg = cfg;
      _epoch++;
    });
    await _engineReady!.future.timeout(const Duration(seconds: 10));
  }

  Future<Stamped<MovaFirstFrame>?> _firstFrame({int from = 0}) =>
      _ev!.wait<MovaFirstFrame>(from: from, timeout: const Duration(seconds: 20));

  /// Starts [cfg], waits for the first frame and lets the audio decoder settle.
  Future<bool> _play(_Cfg cfg, {Duration settle = const Duration(seconds: 3)}) async {
    await _start(cfg);
    if (await _firstFrame() == null) return false;
    await Future<void>.delayed(settle);
    return true;
  }

  Future<String> _prop(String name) async {
    final native = _player?.platform;
    if (native is! NativePlayer) return 'n/a';
    try {
      return await native.getProperty(name);
    } on Object catch (e) {
      return 'ERR($e)';
    }
  }

  Future<MovaKeepAlivePhase> _keepAlive(bool on) => (_api! as MovaKeepAlive).setKeepAlive(on);

  MovaProg? get _lastProg => _pg!.log.lastOrNull?.event;

  /// Enters keepAlive, waits [hold], wakes, and returns what the resume event reported (null on timeout)
  /// plus [decodedMs]: ms from the wake call until mpv reports video-out params again (a kernel
  /// property polled every 30 ms, so it is the first decoded frame as the decoder sees it, independent
  /// of the engine's own landing signal; null when the video never came back within 8 s).
  Future<({MovaKeepAlivePhase phase, MovaKeepAliveChange? entered, Stamped<MovaKeepAliveResume>? resume, int? decodedMs})> _cycle(Duration hold) async {
    final m0 = _ev!.mark;
    final phase = await _keepAlive(true);
    await Future<void>.delayed(const Duration(milliseconds: 100)); // events reach the recorder a tick after the call returns
    final entered = _ev!.all<MovaKeepAliveChange>(from: m0).where((c) => c.event.phase == MovaKeepAlivePhase.holding || c.event.phase == MovaKeepAlivePhase.fallback).firstOrNull?.event;
    await Future<void>.delayed(hold);
    final duringHold = await _prop('video-out-params/w');
    final m1 = _ev!.mark;
    final t0 = _clock.elapsed;
    await _keepAlive(false);
    int? decodedMs;
    while (_clock.elapsed - t0 < const Duration(seconds: 8)) {
      final w = int.tryParse(await _prop('video-out-params/w'));
      if (w != null && w > 0) {
        decodedMs = msBetween(t0, _clock.elapsed);
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    final resume = await _ev!.wait<MovaKeepAliveResume>(from: m1, timeout: const Duration(seconds: 12));
    _log('cycle sanity: video-out-params/w during hold = "$duringHold" (must be empty/error/0 for decodedMs to mean anything)');
    return (phase: phase, entered: entered, resume: resume, decodedMs: decodedMs);
  }

  // ---- scenarios -----------------------------------------------------------------------------

  /// S1/S15: wake-up time of B (muted + vid off) per GOP and hold time, plus the signal distribution.
  Future<void> _s1(int run) async {
    for (final gop in parseInts(kGops)) {
      if (!await _play(_Cfg(source: _src(_live(gop: gop))))) {
        _verdict('S1', false, 'gop=$gop never rendered');
        continue;
      }
      for (final hold in parseInts(kHolds)) {
        final r = await _cycle(Duration(seconds: hold));
        final res = r.resume;
        final sig = res?.event.signal?.name ?? (res == null ? 'timeout' : 'null');
        final ms = res?.event.elapsed.inMilliseconds;
        if (ms != null) _samples.add('S1.gop=$gop.hold=${hold}s.elapsedMs', ms);
        if (r.decodedMs != null) _samples.add('S1.gop=$gop.hold=${hold}s.decodedPropMs', r.decodedMs!);
        _samples.add('S15.signal.$sig', 1);
        _log('S1 gop=${gop}f(${gop / 25}s) hold=${hold}s phase=${r.phase.name} mode=${r.entered?.mode?.name} resume=${ms}ms signal=$sig from=${res?.event.from?.name} decodedProp=${r.decodedMs}ms vid=${await _prop('vid')} mute=${await _prop('mute')}');
        _verdict('S1', r.phase == MovaKeepAlivePhase.holding && res != null && sig != 'grace' && sig != 'timeout', 'gop=$gop hold=${hold}s signal=$sig decodedProp=${r.decodedMs}ms');
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// S2: can HLS be held (allowHls), what `file-format` reads, does the hold keep the playlist moving.
  Future<void> _s2(int run) async {
    for (final allow in <bool>[false, true]) {
      final cfg = _Cfg(source: _src(kHlsUrl), keepAlive: MovaKeepAliveConfig(maxDuration: const Duration(seconds: 300), allowHls: allow));
      if (!await _play(cfg)) {
        _verdict('S2', false, 'allowHls=$allow never rendered');
        continue;
      }
      final media = await _kernel!.inspectKeepAlive();
      final snap = await _kernel!.sample();
      _log('S2 allowHls=$allow inspect.format=${media.format} inspect.audio=${media.audio.name} sample.fileFormat=${snap?.fileFormat} hwdec=${snap?.hwdec}');
      _phase('S2.allowHls=$allow.hold', begin: true);
      final r = await _cycle(const Duration(seconds: 10));
      _phase('S2.allowHls=$allow.hold', begin: false);
      final res = r.resume;
      final ms = res?.event.elapsed.inMilliseconds;
      if (allow && ms != null) _samples.add('S2.allowHls.resumeMs', ms);
      if (allow && r.decodedMs != null) _samples.add('S2.allowHls.decodedPropMs', r.decodedMs!);
      _log('S2 allowHls=$allow phase=${r.phase.name} reason=${r.entered?.reason.name} mode=${r.entered?.mode?.name} resume=${ms}ms signal=${res?.event.signal?.name} from=${res?.event.from?.name} decodedProp=${r.decodedMs}ms');
      _verdict('S2', allow ? r.phase == MovaKeepAlivePhase.holding : (r.phase == MovaKeepAlivePhase.fallback && r.entered?.reason == MovaKeepAliveReason.hls), 'allowHls=$allow phase=${r.phase.name} reason=${r.entered?.reason.name}');
    }
  }

  /// S3: C (no audio, keepDecoding): wake-up must be immediate with signal null.
  Future<void> _s3(int run) async {
    if (!await _play(_Cfg(source: _src(_live(audio: false))))) return _verdict('S3', false, 'never rendered');
    final media = await _kernel!.inspectKeepAlive();
    _phase('S3.hold', begin: true);
    final r = await _cycle(const Duration(seconds: kS3Seconds));
    _phase('S3.hold', begin: false);
    final res = r.resume;
    final ms = res?.event.elapsed.inMilliseconds;
    if (ms != null) _samples.add('S3.resumeMs', ms);
    _log('S3 audio=${media.audio.name} phase=${r.phase.name} mode=${r.entered?.mode?.name} resume=${ms}ms signal=${res?.event.signal?.name} from=${res?.event.from?.name} vid=${await _prop('vid')} mute=${await _prop('mute')}');
    _verdict('S3', r.entered?.mode == MovaKeepAliveMode.decodeOnly && res != null && res.event.signal == null && ms! < 50, 'mode=${r.entered?.mode?.name} signal=${res?.event.signal?.name} resume=${ms}ms');
  }

  /// S4: windows of normal playback / B / C / pause (D) for an external CPU + traffic comparison.
  Future<void> _s4(int run) async {
    for (final mode in <String>['normal', 'B', 'C', 'D']) {
      final silent = mode == 'C';
      if (!await _play(_Cfg(source: _src(_live(audio: !silent))))) {
        _verdict('S4', false, '$mode never rendered');
        continue;
      }
      final label = 'S4.$mode.run$run';
      final p0 = await _prop('time-pos');
      _phase(label, begin: true);
      switch (mode) {
        case 'B' || 'C':
          final phase = await _keepAlive(true);
          _log('S4 $mode phase=${phase.name}');
        case 'D':
          await _api!.pause();
        default:
          break;
      }
      await Future<void>.delayed(const Duration(seconds: kS4Seconds));
      final p1 = await _prop('time-pos');
      _phase(label, begin: false);
      _log('S4 $mode window=${kS4Seconds}s time-pos $p0 -> $p1');
      _verdict('S4', true, '$mode recorded (see PHASE lines + external CPU/traffic)');
    }
  }

  /// S5: position drift across one long hold (`|dPosition - dTime| < 1 s`).
  Future<void> _s5(int run) async {
    if (!await _play(_Cfg(source: _src(_live())))) return _verdict('S5', false, 'never rendered');
    final p1 = _lastProg!;
    final c1 = _pg!.log.last.at;
    final r = await _cycle(const Duration(seconds: kS5Seconds));
    await Future<void>.delayed(const Duration(seconds: 2));
    final p2 = _lastProg!;
    final c2 = _pg!.log.last.at;
    final dPos = (p2.position - p1.position).inMilliseconds;
    final dTime = msBetween(c1, c2);
    final drift = dPos - dTime;
    _samples.add('S5.driftMs', drift.abs());
    // Position minus elapsed time, every ~5 s of arrival time: a constant offset that appears at one
    // point (a jump) looks different from a slope (playing fast).
    final trace = <String>[];
    var nextAt = Duration.zero;
    for (final e in _pg!.log) {
      final rel = e.at - c1;
      if (rel < nextAt) continue;
      nextAt = rel + const Duration(seconds: 5);
      trace.add('+${rel.inSeconds}s:${(e.event.position - p1.position).inMilliseconds - rel.inMilliseconds}');
    }
    _log('S5 (position-advance minus elapsed, ms) trace=$trace');
    _log('S5 hold=${kS5Seconds}s resume=${r.resume?.event.elapsed.inMilliseconds}ms dPosition=${dPos}ms dTime=${dTime}ms drift=${drift}ms (positions ${p1.position.inMilliseconds} -> ${p2.position.inMilliseconds})');
    _verdict('S5', drift.abs() < 1000, 'drift=${drift}ms');
  }

  /// S5C: the same drift measurement with no keepAlive at all (control for S5; same total duration).
  Future<void> _s5c(int run) async {
    if (!await _play(_Cfg(source: _src(_live())))) return _verdict('S5C', false, 'never rendered');
    final p1 = _lastProg!;
    final c1 = _pg!.log.last.at;
    await Future<void>.delayed(const Duration(seconds: kS5Seconds + 7));
    final p2 = _lastProg!;
    final c2 = _pg!.log.last.at;
    final dPos = (p2.position - p1.position).inMilliseconds;
    final dTime = msBetween(c1, c2);
    final drift = dPos - dTime;
    _samples.add('S5C.driftMs', drift.abs());
    _log('S5C control (no keepAlive) dPosition=${dPos}ms dTime=${dTime}ms drift=${drift}ms (positions ${p1.position.inMilliseconds} -> ${p2.position.inMilliseconds})');
    _verdict('S5C', true, 'control drift=${drift}ms');
  }

  /// S6: no-audio detection, and what a forced B does to a stream without audio (position should stop).
  Future<void> _s6(int run) async {
    if (!await _play(_Cfg(source: _src(_live(audio: false))))) return _verdict('S6', false, 'never rendered');
    final media = await _kernel!.inspectKeepAlive();
    final a0 = _lastProg!.position;
    await Future<void>.delayed(const Duration(seconds: 3));
    final normalAdvance = (_lastProg!.position - a0).inMilliseconds;
    final ok = await _kernel!.enterKeepAlive(MovaKeepAliveMode.muted);
    final mark = _ev!.mark;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final b0 = _lastProg!.position;
    final trace = <String>[];
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      trace.add('${_lastProg!.position.inMilliseconds}/eof=${await _prop('eof-reached')}/idle=${await _prop('core-idle')}');
    }
    final forcedAdvance = (_lastProg!.position - b0).inMilliseconds;
    final names = _ev!.log.skip(mark).map((e) => e.event.runtimeType.toString()).where((n) => n != 'MovaProg').toList();
    final restarted = await _kernel!.exitKeepAlive();
    _log('S6 forced-B trace(position/eof-reached/core-idle every 500ms)=$trace eventsDuringForcedB=$names');
    _log('S6 audio=${media.audio.name} format=${media.format} entered=$ok normal3sAdvance=${normalAdvance}ms forcedB4sAdvance=${forcedAdvance}ms exitRestartedVideo=$restarted');
    _verdict('S6', media.audio == MovaAudioPresence.absent && ok && forcedAdvance.abs() < 500, 'audio=${media.audio.name} forcedAdvance=${forcedAdvance}ms');
  }

  /// S7 (opt-in via `ONLY=S7`): `vid` off/on cycles, the plan check for `mediacodec-copy` on Android.
  /// Each cycle prints `S7 SHOT <i>` once the picture should be back (an external script may screenshot there).
  Future<void> _s7(int run) async {
    if (!await _play(_Cfg(source: _src(_live())))) return _verdict('S7', false, 'never rendered');
    final snap = await _kernel!.sample();
    _log('S7 hwdec=${snap?.hwdec} cycles=$kS7Cycles');
    var back = 0;
    var landed = 0;
    for (var i = 1; i <= kS7Cycles; i++) {
      final r = await _cycle(const Duration(seconds: 3));
      final res = r.resume;
      final sig = res?.event.signal?.name ?? (res == null ? 'timeout' : 'null');
      if (r.decodedMs != null) back++;
      if (sig == 'size' || sig == 'restart') landed++;
      _log('S7 cycle=$i phase=${r.phase.name} resume=${res?.event.elapsed.inMilliseconds}ms signal=$sig decodedProp=${r.decodedMs}ms');
      _log('S7 SHOT $i');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    _log('S7 videoCameBack=$back/$kS7Cycles signalLanded(size|restart)=$landed/$kS7Cycles');
    _verdict('S7', back == kS7Cycles, 'videoCameBack=$back/$kS7Cycles signalLanded=$landed/$kS7Cycles');
  }

  /// Waits for the operator to send the app away and back, and returns the lifecycle states seen
  /// (and whether it went away at all).
  Future<({List<String> states, bool away})> _awayAndBack(String id) async {
    final lm = _lifeRec.mark;
    _log('$id WAIT_HOME send the app to the background now (waiting up to ${kWaitS}s)');
    final away = await _lifeRec.wait<AppLifecycleState>(
      from: lm,
      where: (s) => s == AppLifecycleState.hidden || s == AppLifecycleState.paused,
      timeout: const Duration(seconds: kWaitS),
    );
    if (away == null) return (states: <String>[], away: false);
    _log('$id WAIT_FOREGROUND bring the app back now (waiting up to ${kWaitS}s)');
    await _lifeRec.wait<AppLifecycleState>(
      from: _lifeRec.mark,
      where: (s) => s == AppLifecycleState.resumed,
      timeout: const Duration(seconds: kWaitS),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return (states: _lifeRec.all<AppLifecycleState>(from: lm).map((e) => e.event.name).toList(), away: true);
  }

  /// S8 (Android; opt-in via `ONLY=S8`): guard in keepAlive mode, app sent to the background and back
  /// (the operator picks 5s / 60s / 5min). Plan: a `MovaPause` before leaving, `reloadEdge` on return.
  Future<void> _s8(int run) async {
    if (!await _play(_Cfg(source: _src(_live()), guard: true))) return _verdict('S8', false, 'never rendered');
    final m = _ev!.mark;
    final r = await _awayAndBack('S8');
    if (!r.away) return _verdict('S8', false, 'never went to the background');
    await Future<void>.delayed(const Duration(seconds: 6));
    final names = _ev!.log
        .skip(m)
        .map((e) => e.event)
        .where((e) => e is MovaKeepAliveChange || e is MovaKeepAliveResume || e is MovaPause || e is MovaPlay || e is MovaLiveEdgeReach || e is MovaFirstFrame || e is MovaPlayFailure)
        .map((e) => e is MovaKeepAliveChange ? 'KeepAlive(${e.phase.name},${e.reason.name})' : e.runtimeType.toString())
        .toList();
    final p0 = _lastProg;
    await Future<void>.delayed(const Duration(seconds: 3));
    final advance = (_lastProg!.position - p0!.position).inMilliseconds;
    _log('S8 lifecycle=${r.states} events=$names state.keepAlivePhase=${_api!.state.keepAlivePhase.name} playing=${_api!.state.playing} rendered=${_api!.state.rendered} positionAdvanceOver3s=${advance}ms');
    _verdict('S8', _api!.state.playing && advance > 2000, 'fact: playing=${_api!.state.playing} advance=${advance}ms');
  }

  /// S8B (Android; opt-in via `ONLY=S8B`): imperative `setKeepAlive(true)` (no guard), app sent away and back:
  /// records what `vid`, `mute`, position and the phase actually are on return (a fact, not a pass/fail).
  Future<void> _s8b(int run) async {
    if (!await _play(_Cfg(source: _src(_live())))) return _verdict('S8B', false, 'never rendered');
    final phase = await _keepAlive(true);
    _log('S8B holding=${phase.name} vid=${await _prop('vid')} mute=${await _prop('mute')} time-pos=${await _prop('time-pos')}');
    final r = await _awayAndBack('S8B');
    if (!r.away) return _verdict('S8B', false, 'never went to the background');
    for (final wait in <int>[0, 3]) {
      await Future<void>.delayed(Duration(seconds: wait));
      _log('S8B +${wait}s after return: keepAlive=${_api!.state.keepAlivePhase.name} playing=${_api!.state.playing} vid=${await _prop('vid')} mute=${await _prop('mute')} time-pos=${await _prop('time-pos')} lifecycle=${r.states}');
    }
    _verdict('S8B', true, 'fact recorded');
  }

  /// S13: a reload path (`backToLiveEdge`) during B keeps video off, sound muted and the phase.
  Future<void> _s13(int run) async {
    if (!await _play(_Cfg(source: _src(_live())))) return _verdict('S13', false, 'never rendered');
    final phase = await _keepAlive(true);
    final before = '${await _prop('vid')}/${await _prop('mute')}';
    final m = _ev!.mark;
    await _api!.backToLiveEdge();
    await Future<void>.delayed(const Duration(seconds: 4));
    final after = '${await _prop('vid')}/${await _prop('mute')}';
    final stillHolding = _api!.state.keepAlivePhase == MovaKeepAlivePhase.holding;
    final names = _ev!.log.skip(m).map((s) => s.event.runtimeType.toString()).where((n) => n != 'MovaProg').toList();
    await _keepAlive(false);
    final resume = await _ev!.wait<MovaKeepAliveResume>(from: m, timeout: const Duration(seconds: 12));
    _log('S13 phase=${phase.name} vid/mute before=$before after backToLiveEdge=$after stillHolding=$stillHolding wake=${resume?.event.elapsed.inMilliseconds}ms signal=${resume?.event.signal?.name} eventsDuringReload=$names');
    _verdict('S13', phase == MovaKeepAlivePhase.holding && after == 'no/yes' && stillHolding && resume != null, 'after=$after stillHolding=$stillHolding');
  }

  /// S14: what the window shows while only the kernel hides video (`vid=no`), no cover on top.
  /// An external script screenshots on the `S14 SHOT` lines.
  Future<void> _s14(int run) async {
    if (!await _play(_Cfg(source: _src(_live())))) return _verdict('S14', false, 'never rendered');
    _log('S14 SHOT normal');
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final ok = await _kernel!.enterKeepAlive(MovaKeepAliveMode.muted);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _log('S14 SHOT holding1 entered=$ok vid=${await _prop('vid')}');
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    _log('S14 SHOT holding2 vid=${await _prop('vid')}');
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await _kernel!.exitKeepAlive();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    _log('S14 SHOT restored vid=${await _prop('vid')}');
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    _verdict('S14', ok, 'screenshots taken by the external script (normal / holding1 / holding2 / restored)');
  }

  /// S16: how long after open the audio parameters are known: ask for keepAlive at several delays.
  Future<void> _s16(int run) async {
    for (final delay in parseInts(kS16Delays)) {
      await _start(_Cfg(source: _src(_live())));
      final left = Duration(milliseconds: delay) - (_clock.elapsed - _openAt);
      if (left > Duration.zero) await Future<void>.delayed(left);
      final asked = _clock.elapsed - _openAt;
      final media = await _kernel!.inspectKeepAlive();
      final m = _ev!.mark;
      final phase = await _keepAlive(true);
      await Future<void>.delayed(const Duration(milliseconds: 100)); // events reach the recorder a tick after the call returns
      final change = _ev!.all<MovaKeepAliveChange>(from: m).lastOrNull?.event;
      _log('S16 delay=${delay}ms askedAt=${asked.inMilliseconds}ms audio=${media.audio.name} phase=${phase.name} reason=${change?.reason.name} mode=${change?.mode?.name}');
      _samples.add('S16.delay=${delay}ms.holding', phase == MovaKeepAlivePhase.holding ? 1 : 0);
      await _keepAlive(false);
      await Future<void>.delayed(const Duration(seconds: 1));
      _verdict('S16', true, 'fact delay=${delay}ms phase=${phase.name} reason=${change?.reason.name}');
    }
    // Fact-finding second part: poll until the audio is reported present.
    await _start(_Cfg(source: _src(_live())));
    Duration? ready;
    while (_clock.elapsed - _openAt < const Duration(seconds: 8)) {
      final media = await _kernel!.inspectKeepAlive();
      if (media.audio == MovaAudioPresence.present) {
        ready = _clock.elapsed - _openAt;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (ready != null) _samples.add('S16.audioPresentAfterOpenMs(100ms poll)', ready.inMilliseconds);
    _log('S16 audio reported present after ${ready?.inMilliseconds}ms (polled every 100ms)');
  }

  /// S17 (the part this page can drive): guard keepAlive via TickerMode, and a source change while hidden.
  Future<void> _s17(int run) async {
    final cfg = _Cfg(source: _src(_live()), guard: true, keepAlive: const MovaKeepAliveConfig(maxDuration: Duration(seconds: 300)));
    if (!await _play(cfg)) return _verdict('S17', false, 'never rendered');
    var m = _ev!.mark;
    setState(() => _tickerOn = false);
    final hold = await _ev!.wait<MovaKeepAliveChange>(from: m, where: (c) => c.phase == MovaKeepAlivePhase.holding, timeout: const Duration(seconds: 6));
    _log('S17 hide -> holding=${hold != null} reason=${hold?.event.reason.name} mode=${hold?.event.mode?.name} state=${_api!.state.keepAlivePhase.name}');
    await Future<void>.delayed(const Duration(seconds: 2));
    m = _ev!.mark;
    setState(() => _tickerOn = true);
    final back = await _ev!.wait<MovaKeepAliveResume>(from: m, timeout: const Duration(seconds: 12));
    _log('S17 show -> resume=${back?.event.elapsed.inMilliseconds}ms signal=${back?.event.signal?.name} state=${_api!.state.keepAlivePhase.name}');
    await Future<void>.delayed(const Duration(seconds: 1));
    // Q9: hidden, source changes, show again, hide again.
    m = _ev!.mark;
    setState(() => _tickerOn = false);
    await _ev!.wait<MovaKeepAliveChange>(from: m, where: (c) => c.phase == MovaKeepAlivePhase.holding, timeout: const Duration(seconds: 6));
    final m2 = _ev!.mark;
    setState(() => _cfg = _Cfg(source: _src(_live(gop: 25)), guard: true, keepAlive: cfg.keepAlive));
    await Future<void>.delayed(const Duration(seconds: 4));
    final during = _ev!.log.skip(m2).map((s) => s.event).whereType<MovaEvent>().where((e) => e is MovaKeepAliveChange || e is MovaKeepAliveResume || e is MovaFirstFrame || e is MovaPlay || e is MovaPause).map((e) => e is MovaKeepAliveChange ? 'KeepAlive(${e.phase.name},${e.reason.name})' : e.runtimeType.toString()).toList();
    _log('S17 hidden source change: state=${_api!.state.keepAlivePhase.name} playing=${_api!.state.playing} events=$during');
    final m3 = _ev!.mark;
    setState(() => _tickerOn = true);
    await Future<void>.delayed(const Duration(seconds: 5));
    final shown = _ev!.log.skip(m3).map((s) => s.event).where((e) => e is MovaKeepAliveChange || e is MovaKeepAliveResume || e is MovaFirstFrame || e is MovaPlay).map((e) => e is MovaKeepAliveChange ? 'KeepAlive(${e.phase.name},${e.reason.name})' : e.runtimeType.toString()).toList();
    _log('S17 show after source change: state=${_api!.state.keepAlivePhase.name} playing=${_api!.state.playing} rendered=${_api!.state.rendered} events=$shown');
    m = _ev!.mark;
    setState(() => _tickerOn = false);
    final again = await _ev!.wait<MovaKeepAliveChange>(from: m, where: (c) => c.phase == MovaKeepAlivePhase.holding, timeout: const Duration(seconds: 6));
    _log('S17 hide again -> holding=${again != null} state=${_api!.state.keepAlivePhase.name}');
    setState(() => _tickerOn = true);
    await Future<void>.delayed(const Duration(seconds: 3));
    _verdict('S17', hold != null && hold.event.reason == MovaKeepAliveReason.requested && back != null && again != null, 'holding=${hold != null} resume=${back != null} holdAgain=${again != null}');
  }

  // ---- driver --------------------------------------------------------------------------------

  Future<void> _runAll() async {
    final only = parseOnly(autoOnlyRaw());
    final runs = autoRuns();
    final scenarios = <_Scenario>[
      _Scenario('S16', 'audio-params readiness', _s16),
      _Scenario('S1', 'B wake-up time by GOP', _s1),
      _Scenario('S2', 'HLS hold', _s2),
      _Scenario('S3', 'C (no audio) wake-up', _s3),
      _Scenario('S6', 'silent stream detection', _s6),
      _Scenario('S13', 'reload during B', _s13),
      _Scenario('S17', 'guard end-to-end (TickerMode)', _s17),
      _Scenario('S5', 'edge keeping over a long hold', _s5),
      _Scenario('S5C', 'S5 control without keepAlive', _s5c, optIn: true),
      _Scenario('S4', 'CPU/traffic windows', _s4),
      _Scenario('S14', 'window while vid=no (screenshots)', _s14, single: true, optIn: true),
      _Scenario('S7', 'vid off/on cycles (mediacodec-copy on Android)', _s7, single: true, optIn: true),
      _Scenario('S8', 'guard keepAlive across background (Android, marker-driven)', _s8, single: true, optIn: true),
      _Scenario('S8B', 'imperative holding across background (Android, marker-driven)', _s8b, single: true, optIn: true),
    ];
    _log('AUTORUN start runs=$runs base=$kBase hls=$kHlsUrl gops=$kGops holds=$kHolds only=${only.isEmpty ? 'default' : only.join(',')} mode=${const bool.fromEnvironment('dart.vm.product') ? 'release' : const bool.fromEnvironment('dart.vm.profile') ? 'profile' : 'debug'} os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
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
      appBar: AppBar(title: const Text('keepAlive AUTORUN')),
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
                  fit: MovaFit.cover,
                  poster: const ColoredBox(color: Color(0xFF223344), child: Center(child: Text('POSTER'))),
                  skin: const MovaMinimalSkin(),
                  options: MovaOpts(recovery: const MovaRecoveryConfig(enabled: true), keepAlive: cfg.keepAlive),
                  autoPause: cfg.guard ? const MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.keepAlive) : null,
                  engineFactory: _makeEngine,
                  onEngine: _onEngine,
                  onOpenError: (e, s) => _log('openError $e'),
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
