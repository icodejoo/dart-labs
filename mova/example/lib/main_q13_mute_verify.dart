// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

import 'verify_auto/auto_kit.dart';

/// Q13 acceptance page (plan doc/plans/2026-10-23-standby-mode.md, Q13): while a swap shadow engine is
/// warming, ONLY that shadow is muted (through mpv `mute`), the playing engine keeps its sound, the
/// system media volume is never written, and committing the swap un-mutes just the warm hold. Also
/// checks the overlap with standby (both hold the mute, either may leave first).
///
/// Self-running: no manual clicking. Content is a local live FLV (440 Hz tone), the ad a local VOD
/// (880 Hz tone), so by ear "ad = high tone, content = low tone". Every step prints a
/// `[Q13] MARK <name>` line (an external script can sample `adb shell dumpsys audio` there) followed by
/// `[Q13] PROPS <name> ...` with the mpv `mute`/`vid` of every engine created so far (k0 = the first
/// engine, which plays the ad; k1 = the shadow warming the content; after the commit k1 is the live
/// one and k0 is gone). The properties are read straight from the media_kit players, so this part is
/// platform independent; the system volume and what you hear are what only a device can tell.
///
/// Q13 验收页（计划 Q13）：swap 影子引擎预热期间，**只有影子**经 mpv `mute` 静音，正在播的引擎声音不变，系统媒体音量
/// 从不被写，提交后只撤销预热静音；并检查与 standby 的叠加（两方都持有静音，谁先退出都不漏声）。
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

  MovaSwapEngine? _swap;
  MovaAdController? _ads;

  /// Kept for the whole scenario: the existing seamless-swap test also listens to the engine's streams
  /// throughout, and the ad flow was only seen to start with a listener attached.
  StreamSubscription<MovaProg>? _progSub;

  /// Every media_kit player created so far, in creation order (k0, k1, ...).
  final List<Player> _players = <Player>[];

  void _log(String msg) {
    final line = _out.line('${DateTime.now().toIso8601String().substring(11, 23)} ${_clock.elapsedMilliseconds.toString().padLeft(7)}ms $msg');
    if (mounted) setState(() => _lines.insert(0, line));
  }

  void _verdict(String id, bool ok, String note) {
    (ok ? _pass : _fail).update(id, (v) => v + 1, ifAbsent: () => 1);
    _log('VERDICT $id ${ok ? 'PASS' : 'FAIL'} $note');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runAll()));
  }

  MovaSource _content() => MovaSource(_stamp('$kBase/live.flv?gop=50&audio=1&freq=440'), type: MovaStreamType.live, title: 'content');

  MovaAdBreak _adBreak() => MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: MovaSource(_stamp('$kBase/ad.mp4'), title: 'ad'),
    skippableAfter: Duration.zero,
  );

  String _stamp(String url) {
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().microsecondsSinceEpoch}'}).toString();
  }

  /// A fresh swap engine + ad controller; every underlying engine is built on a kernel whose player we keep.
  Future<void> _newRig() async {
    await _disposeRig();
    _players.clear();
    final opts = const MovaOpts(
      ads: MovaAdConfig(enabled: true),
      swap: MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final swap = MovaSwapEngine(
      engineFactory: () {
        final player = Player();
        _players.add(player);
        return createMovaEngine(kernel: MovaMpvKernel(player: player, lazyVideo: true, observeQoeSignals: false), options: opts);
      },
    );
    _swap = swap;
    _progSub = swap.progress.listen((_) {});
    _ads = MovaAdController(swap, swap: swap);
    if (mounted) setState(() {});
  }

  Future<void> _disposeRig() async {
    final ads = _ads;
    final swap = _swap;
    _ads = null;
    _swap = null;
    await _progSub?.cancel();
    _progSub = null;
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    ads?.dispose();
    await swap?.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  /// Waits until the engine really plays (position moving, not buffering).
  Future<bool> _waitPlaying() async {
    final swap = _swap!;
    final done = Completer<bool>();
    late final StreamSubscription<MovaProg> sub;
    sub = swap.progress.listen((p) {
      if (p.position > Duration.zero && !swap.state.buffering && !done.isCompleted) done.complete(true);
    });
    final ok = await done.future.timeout(const Duration(seconds: 25), onTimeout: () => false);
    await sub.cancel();
    return ok;
  }

  Future<bool> _waitEpoch(int from) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (_swap!.state.renderEpoch != from) return true;
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
    _log('PROPS $name renderEpoch=${_swap!.state.renderEpoch} standby=${_swap!.state.standby.name} ${parts.join(' ')}');
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
    await Future<void>.delayed(const Duration(seconds: 3));
    final e0 = _swap!.state.renderEpoch;
    final tPlay = _clock.elapsedMilliseconds;
    await ads.playAdNow(_adBreak());
    _log('$tag playAdNow returned after ${_clock.elapsedMilliseconds - tPlay}ms epoch=${_swap!.state.renderEpoch} showingAd=${ads.isShowingAd} players=${_players.length}');
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

  /// Content live, ad inserted, shadow warms, ad skipped, swap commits.
  Future<void> _scenarioPlain() async {
    await _newRig();
    final ads = _ads!;
    if (!await _enterAd('A')) return _verdict('Q13A', false, 'could not reach the warming state');
    final warming = await _snapshot('A-ad-playing-shadow-warming');
    final alive = await _alive();
    final epoch = _swap!.state.renderEpoch;
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

  /// Like [_scenarioPlain] but standby is requested while warming; [wakeBeforeCommit] picks which side leaves first.
  Future<void> _scenarioStandby({required bool wakeBeforeCommit}) async {
    final id = wakeBeforeCommit ? 'Q13C' : 'Q13B';
    final tag = wakeBeforeCommit ? 'C' : 'B';
    await _newRig();
    final ads = _ads!;
    final swap = _swap!;
    if (!await _enterAd(tag)) return _verdict(id, false, 'could not reach the warming state');
    final phase = await swap.setStandby(true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final warmed = await _snapshot('$tag-standby-requested-while-warming (active phase=${phase.name})');
    final alive = await _alive();
    final shadow = alive.last;
    var ok = alive.length >= 2 && warmed[shadow] == 'yes';
    var extra = '';
    if (wakeBeforeCommit) {
      await swap.setStandby(false);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final mid = await _snapshot('$tag-woke-before-commit');
      ok = ok && mid[shadow] == 'yes';
      extra = ' shadow.mute after wake=${mid[shadow]}';
    }
    final epoch = swap.state.renderEpoch;
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
      ok = ok && committed[newest] == 'yes' && vid == 'no' && swap.state.standby == MovaStandbyPhase.holding;
      extra = ' live.vid=$vid standby=${swap.state.standby.name}';
      await swap.setStandby(false);
      await Future<void>.delayed(const Duration(seconds: 7));
      final w = await _snapshot('$tag-woken-after-commit');
      ok = ok && w[newest] == 'no';
      extra = '$extra afterWake.mute=${w[newest]}';
    }
    _verdict(id, ok, 'shadow.mute while warming=${warmed[shadow]} swapped=$swapped committed(live k$newest).mute=${committed[newest]}$extra');
  }

  Future<void> _runAll() async {
    final only = parseOnly(autoOnlyRaw());
    final runs = autoRuns();
    final scenarios = <(String, String, Future<void> Function())>[
      ('Q13A', 'plain warm and commit', _scenarioPlain),
      ('Q13B', 'standby requested while warming, commit while holding, then wake', () => _scenarioStandby(wakeBeforeCommit: false)),
      ('Q13C', 'standby requested while warming, wake before commit', () => _scenarioStandby(wakeBeforeCommit: true)),
    ];
    _log('AUTORUN start runs=$runs base=$kBase only=${only.isEmpty ? 'all' : only.join(',')} os=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
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
    final swap = _swap;
    return Scaffold(
      appBar: AppBar(title: const Text('Q13 mute verify')),
      body: Column(
        children: [
          if (swap != null) AspectRatio(aspectRatio: 16 / 9, child: MovaPlayer(api: swap, skin: const MovaMinimalSkin())),
          Expanded(child: ListView(children: [for (final l in _lines.take(60)) Text(l, style: const TextStyle(fontSize: 11))])),
        ],
      ),
    );
  }
}
