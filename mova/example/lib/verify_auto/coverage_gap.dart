// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:media_kit_video/media_kit_video.dart' show VideoController;
import 'package:mova/mova.dart';
// Device instrumentation intentionally reads the real kernel and FFI backend.
// ignore: implementation_imports
import 'package:mova/src/core/kernel/mpv_kernel.dart';
// ignore: implementation_imports
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

final gapScreen = ValueNotifier<MovaApi?>(null);
final gapMini = MovaMini();
final gapSurfaces = ValueNotifier<List<MovaApi>>([]);
final gap = GapRunner();

/// Extra case groups registered by other verification files (e.g. `skin`).
/// 其它验证文件注册的附加分组（如 skin）；runGroup 对未知分组查此表。
final gapGroups = <String, Future<void> Function(Map<String, String> args)>{};

/// Only the bad-source probe needs an overridden kernel open. No VideoController
/// is created for these headless engines. The actual super.open is unchanged.
class GapOpenKernel extends MovaMpvKernel {
  GapOpenKernel(this.player)
    : super(
        player: player,
        audioOnly: true,
        observeNativeEvents: true,
        backendFactory: (n, h) =>
            createFfiMpvEventBackend(n, h, pollInDebug: false),
      );
  final Player player;
  @override
  Future<void> open(String uri, {bool play = true}) => gap.call(
    'MovaMpvKernel.open',
    {'uri': uri, 'play': play},
    () => super.open(uri, play: play),
  );
}

class GapBlocked implements Exception {
  GapBlocked(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class GapRunner {
  String run = 'setup', current = 'gap:HARNESS.setup', phase = 'idle';
  String origin = 'http://127.0.0.1:18085';
  int count = 3;
  final rows = <Map<String, Object?>>[];
  final events = <MovaEvent>[];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final marks = <String>{};

  /// 本用例是否进过系统画中画；为真时用例结束必须先把 App 拉回前台。
  bool pipSeen = false;

  /// 拉回前台失败后置位；此后所有用例记 BLOCKED，宿主也不再截图。
  bool foregroundLost = false;
  int _foregroundSeq = 0;
  MovaApi? api;
  NativePlayer? headlessNative;
  String? pendingEvidence;
  Object? lastApiError;
  MovaProg progress = const MovaProg();

  void log(String kind, Object? data) {
    final time = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
    rows.add({
      'time': time,
      'run': run,
      'case': current,
      'kind': kind,
      'data': data,
    });
    print(
      '[MOVA-COV] $time <run=$run> <case=$current> $kind ${jsonEncode(data)}',
    );
  }

  Map<String, Object?> state() {
    final a = api;
    if (a == null) return {'engine': null};
    final s = a.state;
    return {
      'position': progress.position.inMilliseconds,
      'duration': s.duration.inMilliseconds,
      'playing': s.playing,
      'buffering': s.buffering,
      'rendered': s.rendered,
      'size': '${s.width}x${s.height}',
      'volume': s.volume,
      'rate': s.rate,
      'fit': s.fit.name,
      'zoom': s.zoom,
      'locked': s.locked,
      'fullscreen': s.fullscreen,
      'pip': s.pip,
      'mini': s.mini,
      'keepAlivePhase': s.keepAlivePhase.name,
      'renderEpoch': s.renderEpoch,
      'sourceIndex': s.sourceIndex,
      'playbackIntent': s.playbackIntent,
      'error': '${s.error}',
    };
  }

  Future<T> call<T>(
    String name,
    Object? args,
    FutureOr<T> Function() action,
  ) async {
    await evidence();
    log('STATE', {'edge': 'before', 'call': name, ...state()});
    log('STEP', {'call': name, 'args': args});
    log('CALL', {'method': name, 'args': args});
    try {
      final result = await Future<T>.sync(
        action,
      ).timeout(const Duration(seconds: 45));
      log('RET', {'method': name, 'value': '$result'});
      return result;
    } catch (e, s) {
      lastApiError=e;
      log('RET', {
        'method': name,
        'exception': '${e.runtimeType}: $e',
        'stack': '$s',
      });
      rethrow;
    } finally {
      log('STATE', {'edge': 'after', 'call': name, ...state()});
    }
  }

  void verdict(bool ok, Object expected, Object actual, {String? blocked}) {
    log('EXPECT', expected);
    log('ACTUAL', actual);
    final token = !ok && blocked == null ? 'failure-${rows.length}' : null;
    log('VERDICT', {
      'status': blocked != null
          ? 'BLOCKED'
          : ok
          ? 'PASS'
          : 'FAIL',
      'reason': blocked,
      'difference': ok ? null : actual,
      'evidenceToken': token,
    });
    if (token != null) pendingEvidence = token;
    if (!ok && blocked == null) {
      log('EVENT', {
        'recent50': rows
            .where((r) => r['kind'] == 'EVENT')
            .toList()
            .reversed
            .take(50)
            .toList(),
      });
    }
  }

  /// 请宿主 `am start` 把本 App 拉回前台（退出画中画）并等确认；失败则置 [foregroundLost]。
  Future<bool> restoreForeground(String why) async {
    final seq = ++_foregroundSeq;
    log('STEP', {'restoreForeground': seq, 'why': why});
    var ok = false;
    try {
      await until(
        () =>
            marks.contains('foreground-ok-$seq') ||
            marks.contains('foreground-failed-$seq'),
        seconds: 40,
      );
      ok = marks.contains('foreground-ok-$seq');
    } on TimeoutException {
      ok = false;
    }
    if (ok) {
      pipSeen = false;
    } else {
      foregroundLost = true;
    }
    log('STATE', {'edge': 'foreground', 'restored': ok, ...state()});
    return ok;
  }

  Future<void> evidence() async {
    final token = pendingEvidence;
    if (token == null) return;
    await until(() => marks.contains(token));
    pendingEvidence = null;
  }

  Future<void> until(
    FutureOr<bool> Function() predicate, {
    int seconds = 25,
  }) async {
    final watch = Stopwatch()..start();
    while (!await predicate()) {
      if (watch.elapsed.inSeconds >= seconds) {
        throw TimeoutException('observed condition absent');
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  /// 构造带防缓存时间戳的源；[live] 为 true 时按直播类型声明（待机 hold 只对直播生效）。
  MovaSource source(String path, {bool live = false}) => MovaSource(
    '$origin/$path${path.contains('?') ? '&' : '?'}t=${DateTime.now().microsecondsSinceEpoch}',
    type: live ? MovaStreamType.live : MovaStreamType.vod,
  );
  void observe(MovaApi a) {
    subscriptions.add(
      a.progress.listen((p) {
        progress = p;
        log('STATE', state());
      }),
    );
    subscriptions.add(a.states.listen((s) => log('STATE', state())));
    subscriptions.add(
      a.events.listen((e) {
        events.add(e);
        if (e is MovaPipChange && e.value) pipSeen = true;
        log('EVENT', {
          'type': '${e.runtimeType}',
          'payload': payload(e),
          'state': state(),
        });
      }),
    );
  }

  Map<String, Object?> payload(MovaEvent e) => switch (e) {
    MovaSourceChange() => {'uri': e.source.uri},
    MovaSeek() => {'target': e.target.inMilliseconds},
    MovaSeeked() => {'position': e.position.inMilliseconds},
    MovaBufferChange() => {'buffering': e.buffering},
    MovaDurationChange() => {'duration': e.duration.inMilliseconds},
    MovaFirstFrame() => {
      'sinceOpen': e.sinceOpen.inMilliseconds,
      'signal': e.signal.name,
    },
    MovaSizeChange() => {'width': e.width, 'height': e.height},
    MovaVolumeChange() => {'value': e.value},
    MovaBrightChange() => {'value': e.value},
    MovaRateChange() => {'value': e.value},
    MovaFitChange() => {'fit': e.fit.name},
    MovaZoomChange() => {'zoom': e.zoom},
    MovaLockChange() => {'value': e.value},
    MovaFullScreenChange() => {'value': e.value},
    MovaOrientationChange() => {'orientation': e.orientation.name},
    MovaMiniChange() => {'mini': e.mini},
    MovaPipChange() => {'value': e.value},
    MovaQualityListChange() => {
      'qualities': e.qualities.map((q) => '${q.label}:${q.uri}').toList(),
    },
    MovaQualityChange() => {'quality': e.quality.label},
    MovaAbrDownShift() => {'from': e.from.label, 'to': e.to.label},
    MovaCutoverChange() => {'phase': e.phase.name},
    MovaPreviewBlock() => {'reason': e.reason.name},
    MovaSttBlock() => {'reason': e.reason.name},
    MovaErrorEvent() => {'error': '${e.error}', 'stack': '${e.stack}'},
    MovaPlayFailure() => {
      'kind': e.fail.kind.name,
      'action': '${e.action}',
      'attempt': e.fail.attempt,
      'isLive': e.fail.isLive,
      'sourceIndex': e.fail.sourceIndex,
    },
    MovaRecovered() => {'attempts': e.attempts},
    MovaFailover() => {'from': e.from, 'to': e.to, 'uri': e.uri},
    MovaTimeShiftChange() => {'behind': e.behind.inMilliseconds},
    MovaKeepAliveChange() => {
      'phase': e.phase.name,
      'reason': e.reason.name,
      'mode': '${e.mode}',
    },
    MovaKeepAliveResume() => {
      'elapsed': e.elapsed.inMilliseconds,
      'signal': '${e.signal}',
      'from': '${e.from}',
    },
    _ => <String, Object?>{},
  };
  Future<MovaApi> engine({
    bool precise = false,
    bool cutover = false,
    bool recovery = false,
  }) async {
    MovaEngine factory() {
      final e = !precise && !cutover && !recovery
          ? createMovaEngine()
          : createMovaEngine(
              preciseFirstFrame: precise,
              options: MovaOpts(
                recovery: MovaRecoveryConfig(enabled: recovery),
                cutover: MovaCutoverConfig(enabled: cutover),
              ),
            );
      // Cutover prewarm reads renderHandle before commit. Mount every factory
      // engine, including the shadow, to avoid an unattached video pipeline.
      gapSurfaces.value = [...gapSurfaces.value, e];
      return e;
    }

    final a = await call<MovaApi>('createMovaEngine', {
      'preciseFirstFrame': precise,
      'cutover': cutover,
      'recovery': recovery,
    }, () => cutover ? MovaCutoverEngine(engineFactory: factory) : factory());
    api = a;
    observe(a);
    gapScreen.value = a;
    await WidgetsBinding.instance.endOfFrame;
    return a;
  }

  Future<String> native(String key) => call(
    'NativePlayer.getProperty',
    {'name': key},
    () async {
      if (headlessNative != null) return headlessNative!.getProperty(key);
      final h = api!.renderHandle;
      if (h is! VideoController) throw GapBlocked('no mounted VideoController');
      return (h.player.platform as NativePlayer).getProperty(key);
    },
  );
  Future<int> pos() async =>
      ((double.tryParse(await optionalNative('time-pos')) ?? -1) * 1000).round();
  Future<String> optionalNative(String key) async {
    try {
      return await native(key);
    } catch (e) {
      return 'unavailable: $e';
    }
  }

  Future<void> open(MovaApi a, String path) async {
    final s = source(path);
    await call('open', {'uri': s.uri}, () => a.open(s));
    await until(() => a.state.duration.inSeconds >= 40 && !a.state.buffering);
    await until(() async => await pos() > 500);
  }

  Future<void> seek(MovaApi a, int ms) =>
      call('seek', {'ms': ms}, () => a.seek(Duration(milliseconds: ms)));
  Future<void> dispose() async {
    final a = api;
    if (a == null) return;
    await call('dispose', {}, a.dispose);
    for (final s in subscriptions) {
      await s.cancel();
    }
    subscriptions.clear();
    gapScreen.value = null;
    gapSurfaces.value = [];
    api = null;
    headlessNative = null;
    progress = const MovaProg();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> caseOf(
    String id,
    List<String> refs,
    Future<void> Function() body,
  ) async {
    current = 'gap:$id';
    events.clear();
    lastApiError=null;
    log('BEGIN', {'matrixAndHypotheses': refs});
    if (foregroundLost) {
      // 前面的 PiP 没能拉回前台：不再跑任何用例，避免宿主截到别的 App。
      verdict(
        false,
        'app is foreground before the case',
        'foreground not restored after system PiP',
        blocked: 'foreground lost after PiP; precondition unmet',
      );
      log('END', {'case': current});
      return;
    }
    try {
      await body();
    } on GapBlocked catch (e) {
      verdict(false, 'prerequisites available', '$e', blocked: '$e');
    } on TimeoutException catch (e) {
      verdict(false, 'real state/event before watchdog', '$e');
    } catch (e, s) {
      if(identical(e,lastApiError)) {
        verdict(false,'API completes without unexpected exception',{'exception':'${e.runtimeType}: $e','stack':'$s'});
      } else {
        log('ERROR', {'kind': 'HARNESS', 'error': '$e', 'stack': '$s'});
        verdict(false, 'valid harness', '$e', blocked: 'HARNESS');
      }
    } finally {
      try {
        await evidence();
      } catch (e, s) {
        log('ERROR', {'kind': 'HARNESS', 'evidence': '$e', 'stack': '$s'});
      }
      pendingEvidence = null;
      try {
        await dispose();
      } catch (e, s) {
        log('ERROR', {'kind': 'HARNESS', 'cleanup': '$e', 'stack': '$s'});
      }
      if (pipSeen) {
        // 任何进过画中画的用例（含皮肤里的 PiP 按钮）结束都要拉回前台再进下一个。
        try {
          await restoreForeground('caseOf:$id');
        } catch (e, s) {
          foregroundLost = true;
          log('ERROR', {'kind': 'HARNESS', 'foreground': '$e', 'stack': '$s'});
        }
      }
      log('END', {'case': current});
    }
  }

  Future<void> switches(bool precise, String mode) async {
    final a = await engine(precise: precise, cutover: mode == 'cutover');
    await open(a, 'master.m3u8');
    await call('loadQualities', {}, a.loadQualities);
    await until(() => a.state.qualities.where((q) => !q.isAuto).length >= 2);
    final qs = a.state.qualities.where((q) => !q.isAuto).toList();
    final samples = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      await seek(a, 12000);
      await until(() async => (await pos() - 12000).abs() < 500);
      if (mode == 'paused') await call('pause', {}, a.pause);
      final target = await pos(), q = qs[i % qs.length];
      await call('switchQuality', {
        'uri': q.uri,
        'targetMs': target,
        'iteration': i,
      }, () => a.switchQuality(q));
      await until(
        () async =>
            await native('path') == q.uri &&
            (await pos() - target).abs() <= 500,
      );
      final landed = await pos();
      if (mode != 'paused') await until(() async => await pos() > landed + 300);
      final actual = {
        'iteration': i,
        'targetMs': target,
        'landedMs': landed,
        'deltaMs': landed - target,
        'pause': await native('pause'),
        'path': await native('path'),
      };
      samples.add(actual);
      verdict(
        (landed - target).abs() <= 500 &&
            (mode != 'paused' || actual['pause'] == 'yes'),
        {'toleranceMs': 500, 'paused': mode == 'paused'},
        actual,
      );
    }
    log('ACTUAL', {'allSamples': samples, 'count': samples.length});
  }

  Future<void> parked(bool shadow) async {
    final a = await engine(cutover: shadow);
    if (shadow) {
      await open(a, 'long.mp4');
      final p = a as MovaCutoverEngine;
      final s = source('delayed/master.m3u8');
      await call(
        'prepare',
        {'uri': s.uri, 'atMs': 12000},
        () => p.prepare(
          s,
          at: const Duration(seconds: 12),
          plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
        ),
      );
      final committed = await call('commit', {
        'waitForReady': true,
      }, () => p.commit(waitForReady: true));
      verdict(committed, 'HLS shadow becomes ready and commits', {
        'committed': committed,
      });
    } else {
      final s = source('delayed/master.m3u8');
      final pending = call('open', {'uri': s.uri}, () => a.open(s));
      verdict(
        a.state.duration == Duration.zero,
        'seek before readiness',
        state(),
      );
      await seek(a, 12000);
      await pending;
    }
    await until(() async => (await pos() - 12000).abs() <= 500);
    final landed = await pos();
    await until(() async => await pos() > landed + 400);
    verdict(
      true,
      {'targetMs': 12000, 'toleranceMs': 500, 'progress': 'continues'},
      {'landedMs': landed, 'deltaMs': landed - 12000, 'afterMs': await pos()},
    );
  }

  Future<void> stale() async {
    final k = GapOpenKernel(Player());
    final a = await call('createMovaEngine', {
      'audioOnly': true,
      'kernel': 'GapOpenKernel',
    }, () => createMovaEngine(kernel: k, audioOnly: true));
    api = a;
    headlessNative = k.player.platform as NativePlayer;
    observe(a);
    var goodIssued = false;
    final late = <String>[];
    subscriptions.add(
      k.endFiles.listen((r) {
        log('EVENT', {
          'native': 'END_FILE',
          'reason': r.name,
          'goodOpenIssued': goodIssued,
          'state': state(),
        });
        if (goodIssued && r.name == 'error') late.add(r.name);
      }),
    );
    final bad = source('late-error');
    final first = call('open.bad', {'uri': bad.uri}, () => a.open(bad));
    final good = source('long.mp4');
    goodIssued = true;
    final start = events.length;
    final second = call('open.good', {'uri': good.uri}, () => a.open(good));
    await Future.wait([first, second]);
    try {
      await until(() => marks.contains('late-error-sent'));
    } on TimeoutException {
      throw GapBlocked(
        'old HTTP request cancelled before late response; no error race',
      );
    }
    final p = await pos();
    await until(() async => await pos() > p + 1200);
    final errors = events
        .skip(start)
        .where((e) => e is MovaPlayFailure || e is MovaErrorEvent)
        .toList();
    verdict(
      errors.isEmpty && a.state.error == null,
      'good source progresses after old HTTP error',
      {'errors': '$errors', 'path': await native('path'), 'state': state()},
    );
    verdict(
      late.isNotEmpty && errors.isEmpty,
      'late native END_FILE(error) does not fail new open',
      {
        'lateNativeErrors': late,
        'newSourceErrors': '$errors',
        'path': await native('path'),
      },
      blocked: late.isEmpty
          ? 'libmpv cancelled old request without late END_FILE(error); race prerequisite absent'
          : null,
    );
  }

  Future<void> abr() async {
    final a = await engine();
    await open(a, 'master.m3u8');
    await call('loadQualities', {}, a.loadQualities);
    await until(() => a.state.qualities.where((q) => !q.isAuto).length >= 2);
    final variants=a.state.qualities.where((q)=>!q.isAuto).toList()
      ..sort((x,y)=>(y.bandwidth??0).compareTo(x.bandwidth??0));
    final q = variants.first;
    await call('switchQuality', {'uri': q.uri}, () => a.switchQuality(q));
    for (final paused in [false, true]) {
      if (paused) await call('pause', {}, a.pause);
      final start = events.length;
      for (final t in [12000, 23000, 8000, 31000, 15000, 26000]) {
        await seek(a, t);
        await until(() async => (await pos() - t).abs() <= 500);
      }
      await until(() => !a.state.buffering);
      final down = events.skip(start).whereType<MovaAbrDownShift>().toList();
      final bufferEdges=events.skip(start).whereType<MovaBufferChange>().where((e)=>e.buffering).length;
      verdict(down.isEmpty, 'manual quality: zero ABR downshifts', {
        'paused': paused,
        'downshifts': '$down',
        'quality': a.state.currentQuality?.uri,
        'bufferingTrueEdges':bufferEdges,
      });
      if(bufferEdges<3)verdict(false,'at least three seek buffering edges',{'edges':bufferEdges},blocked:'seek buffering threshold not reached; ABR stress precondition absent');
    }
  }

  Future<void> echo(String path) async {
    final a = await engine();
    await open(a, path);
    for (final t in [7990, 16010, 23990]) {
      await seek(a, t);
      await until(() async=>await native('seeking')=='no' && !a.state.buffering);
      final landed = await pos();
      await until(() => progress.position.inMilliseconds > t + 1200);
      final n = await pos(), p = progress.position.inMilliseconds;
      verdict(
        (n - p).abs() < 1000,
        'position echo resumes with coarse landing',
        {
          'targetMs': t,
          'landingMs': landed,
          'landingDeltaMs': landed - t,
          'nativeMs': n,
          'progressMs': p,
          'deltaMs': n - p,
        },
      );
      if ((landed - t).abs() <= 500) {
        verdict(
          false,
          'landing deviation >500ms',
          {'deltaMs': landed - t},
          blocked:
              'decoder did not produce coarse landing; H17 branch unexercised',
        );
      }
    }
  }

  Future<void> errors(String path, bool recovery) async {
    final k = GapOpenKernel(Player());
    final a = await call(
      'createMovaEngine',
      {'audioOnly': true, 'recovery': recovery, 'kernel': 'GapOpenKernel'},
      () => createMovaEngine(
        kernel: k,
        audioOnly: true,
        options: MovaOpts(recovery: MovaRecoveryConfig(enabled: recovery)),
      ),
    );
    api = a;
    headlessNative = k.player.platform as NativePlayer;
    observe(a);
    subscriptions.add(
      k.endFiles.listen(
        (r) => log('EVENT', {
          'native': 'END_FILE',
          'reason': '$r',
          'state': state(),
        }),
      ),
    );
    final s = path.startsWith('http')
        ? MovaSource('$path?t=${DateTime.now().microsecondsSinceEpoch}')
        : source(path);
    Object? thrown, returned;
    try {
      returned = await call('open', {
        'uri': s.uri,
        'recovery': recovery,
      }, () => a.open(s));
    } catch (e) {
      thrown = '${e.runtimeType}: $e';
    }
    await until(
      () =>
          thrown != null ||
          events.any((e) => e is MovaErrorEvent || e is MovaPlayFailure),
    );
    verdict(
      true,
      'record open return/throw separately from async native error',
      {
        'returned': returned,
        'thrown': thrown,
        'recovery': recovery,
        'errors': events
            .where((e) => e is MovaErrorEvent || e is MovaPlayFailure)
            .map((e) => '${e.runtimeType}')
            .toList(),
      },
    );
  }

  Future<void> pip() async {
    final a = await engine();
    await open(a, 'long.mp4');
    await call('MovaMini.show', {}, () => gapMini.show(a));
    await until(() => a.state.mini);
    if (!a.state.pipSupported) throw GapBlocked('PiP unsupported');
    if (!await call('enterPip', {}, a.enterPip)) {
      throw GapBlocked('system refused PiP');
    }
    pipSeen = true;
    await until(() => a.state.pip && !a.state.mini);
    // 先取画中画期间的状态，拉回前台后再发 verdict，FAIL 现场截图才不会落在别的 App 上。
    final removed = !gapMini.isShowing(a);
    final inPip = state();
    await call('dispose.first', {}, a.dispose);
    await call('dispose.second', {}, a.dispose);
    final restored = await restoreForeground('A15.miniPip');
    verdict(removed, 'MiniHost removed when PiP active', inPip);
    verdict(true, 'second dispose returns without exception', state());
    if (!restored) {
      verdict(
        false,
        'app is foreground again after PiP',
        'host could not bring the app back',
        blocked: 'foreground not restored after PiP; later cases blocked',
      );
    }
  }

  Future<void> keepAlive() async {
    final a = await engine(precise: true);
    // 待机 hold 只对 live 类型生效（VOD 一律 fallback(vod)，永远没有唤醒事件）：
    // 这里把渐进式 mp4 声明成 live 来走 B 路径；live 不支持 seek，改为等进度走过基准点，
    // 同时留足 audio-params 就绪时间（就绪前请求待机会回落为 mediaUnknown）。
    final live = source('long.mp4', live: true);
    await call('open', {'uri': live.uri, 'type': 'live'}, () => a.open(live));
    await until(() async => await pos() > 3000);
    final samples = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      final base = await pos();
      await until(() async => await pos() > base + 1500);
      log('SHOT', {'name': 'before-hold-$i'});
      await until(() => marks.contains('before-shot-$i'));
      final entered = await call('setKeepAlive', {
        'on': true,
      }, () => (a as MovaKeepAlive).setKeepAlive(true));
      if ('$entered' != '${MovaKeepAlivePhase.holding}') {
        // 没进入 hold 就没有 B 唤醒可测：按前提不满足记 BLOCKED，并给出真实阶段与回落原因。
        verdict(
          false,
          'setKeepAlive(true) enters holding on a live source',
          {'iteration': i, 'phase': '$entered', 'keepAlivePhase': a.state.keepAlivePhase.name},
          blocked: 'keepAlive fell back instead of holding; B wake path unexercised',
        );
        return;
      }
      log('SHOT', {
        'name': 'keepalive-$i',
        'manual': 'black/frozen comparison',
      });
      await until(() => marks.contains('shot-$i'));
      final start = events.length;
      await call('setKeepAlive', {
        'on': false,
      }, () => (a as MovaKeepAlive).setKeepAlive(false));
      await until(
        () => events.skip(start).whereType<MovaKeepAliveResume>().isNotEmpty,
      );
      final e = events.skip(start).whereType<MovaKeepAliveResume>().first;
      samples.add({
        'iteration': i,
        'signal': '${e.signal}',
        'elapsedMs': e.elapsed.inMilliseconds,
      });
    }
    verdict(true, 'record all native wake signals and event elapsed samples', {
      'samples': samples,
      'meanMs':
          samples.map((s) => s['elapsedMs'] as int).reduce((a, b) => a + b) /
          samples.length,
    });
    verdict(
      false,
      'classify standby as black/frozen',
      'PNG pairs collected',
      blocked: 'manual screenshot comparison required',
    );
  }

  Future<void> local(String kind) async {
    final a = await engine();
    final bytes = await call('rootBundle.load', {
      'asset': 'assets/test_video.mp4',
    }, () => rootBundle.load('assets/test_video.mp4'));
    final file = File('${Directory.systemTemp.path}/coverage-gap-local.mp4');
    await call(
      'File.writeAsBytes',
      {'path': file.path},
      () => file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    final uri = kind == 'asset'
        ? 'asset:///assets/test_video.mp4'
        : kind == 'file'
        ? file.uri.toString()
        : file.path;
    await call('open', {'uri': uri}, () => a.open(MovaSource(uri)));
    await until(() async => await pos() > 1000);
    verdict(true, 'local source produces native progress', {
      'kind': kind,
      'uri': uri,
      'nativeMs': await pos(),
    });
  }

  Future<void> format(
    String path,
    bool supported, {
    bool software = false,
  }) async {
    final a = await engine();
    final base = source(path);
    final s = software
        ? MovaSource(base.uri, mpvOptions: const {'hwdec': 'no'})
        : base;
    Object? thrown;
    try {
      await call('open', {
        'uri': s.uri,
        'supported': supported,
      }, () => a.open(s));
    } catch (e) {
      thrown = '$e';
    }
    if (supported) {
      await until(() async => await pos() > 1000);
      // 再留 1.2s：解码器打不开的 vd/ad 错误常在首帧之后才冒出来；
      // 仅凭 time-pos 前进不能证明视频被解出（音频/时钟照走也会前进）。
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final errs = events
          .where((e) => e is MovaErrorEvent || e is MovaPlayFailure)
          .map((e) => '${e.runtimeType}: ${payload(e)}')
          .toList();
      verdict(errs.isEmpty, 'retained format decodes with no decoder error', {
        'file': path,
        'nativeMs': await pos(),
        'errors': errs,
        'video-format': await optionalNative('video-format'),
        'audio-codec-name': await optionalNative('audio-codec-name'),
        'video-params/w': await optionalNative('video-params/w'),
        'decoder-frame-drop-count':
            await optionalNative('decoder-frame-drop-count'),
        // 视频是否真被解码并送显：有帧率、输出参数且丢帧不涨，才说明错误日志只是回落噪声。
        'estimated-vf-fps': await optionalNative('estimated-vf-fps'),
        'frame-drop-count': await optionalNative('frame-drop-count'),
        'video-out-params/w': await optionalNative('video-out-params/w'),
        'stateError': '${a.state.error}',
        'hwdec-current': await optionalNative('hwdec-current'),
        'file-format': await optionalNative('file-format'),
        'seekable': await optionalNative('seekable'),
        'demuxer-max-back-bytes': await optionalNative('demuxer-max-back-bytes'),
        'softwareForced': software,
      });
    } else {
      await until(
        () =>
            thrown != null ||
            events.any((e) => e is MovaErrorEvent || e is MovaPlayFailure),
      );
      verdict(true, 'excluded format explicitly errors', {
        'file': path,
        'throw': thrown,
        'events': events.map((e) => '${e.runtimeType}').toList(),
      });
    }
  }

  /// 记录型：读回 libmpv 实际编入的解码器清单，用来核对瘦身裁剪面（与格式用例的错误互相印证）。
  Future<void> decoders() async {
    final a = await engine();
    await open(a, 'long.mp4');
    final raw = await optionalNative('decoder-list');
    const wanted = [
      'h264', 'hevc', 'av1', 'libdav1d', 'libaom-av1', 'vp8', 'vp9', 'libvpx',
      'libvpx-vp9', 'mpeg4', 'wmv2', 'ac3', 'eac3', 'aac', 'mp3', 'flac',
      'vorbis', 'opus',
    ];
    final present = <String, String>{};
    var total = -1;
    try {
      final list = jsonDecode(raw) as List<Object?>;
      total = list.length;
      for (final item in list.whereType<Map<String, Object?>>()) {
        final codec = '${item['codec']}', driver = '${item['driver']}';
        if (wanted.contains(codec) || wanted.contains(driver)) {
          present['$codec/$driver'] = '${item['description']}';
        }
      }
    } catch (e) {
      present['parseError'] = '$e (raw length ${raw.length})';
    }
    verdict(true, 'record compiled decoder list', {
      'total': total,
      'wantedPresent': present,
    });
  }

  Future<void> random(int seed, int actions) async {
    final rng = Random(seed);
    var a = await engine();
    // 事件按引擎隔离：重建引擎后，上一个引擎遗留的 fullscreen/mini/rate 事件不能参与对账。
    var base = events.length;
    await open(a, 'master.m3u8');
    for (var i = 0; i < actions; i++) {
      final action = rng.nextInt(9);
      log('STATE', {'edge': 'before-action', ...state()});
      log('STEP', {'seed': seed, 'index': i, 'action': action});
      switch (action) {
        case 0:
          await open(a, 'master.m3u8');
        case 1:
          await call('play', {}, a.play);
        case 2:
          await call('pause', {}, a.pause);
        case 3:
          await seek(a, 8000 + rng.nextInt(24000));
        case 4:
          await call('loadQualities', {}, a.loadQualities);
          final qs = a.state.qualities.where((q) => !q.isAuto).toList();
          if (qs.isNotEmpty) {
            await call('switchQuality', {
              'index': i,
            }, () => a.switchQuality(qs[rng.nextInt(qs.length)]));
          }
        case 5:
          await call('setFullscreen', {
            'value': !a.state.fullscreen,
          }, () => a.setFullscreen(!a.state.fullscreen));
        case 6:
          await call('setMini', {
            'value': !a.state.mini,
          }, () => a.setMini(!a.state.mini));
        case 7:
          await dispose();
          a = await engine();
          base = events.length;
          await open(a, 'master.m3u8');
        case 8:
          await seek(a, 12000);
          await call('play', {}, a.play);
      }
      await WidgetsBinding.instance.endOfFrame;
      log('STATE', {'edge': 'after-action', ...state()});
      final fs = events.skip(base).whereType<MovaFullScreenChange>().lastOrNull;
      final mini = events.skip(base).whereType<MovaMiniChange>().lastOrNull;
      final rate = events.skip(base).whereType<MovaRateChange>().lastOrNull;
      verdict(
        a.state.sourceIndex >= 0 &&
            a.state.rate > 0 &&
            (fs == null || fs.value == a.state.fullscreen) &&
            (mini == null || mini.mini == a.state.mini) &&
            (rate == null || rate.value == a.state.rate),
        'valid state and latest fullscreen/mini/rate event agree after random action',
        {'seed': seed, 'index': i, 'state': state()},
      );
    }
    await call('play', {}, a.play);
    final p = await pos();
    await until(() async => await pos() > p + 500);
    verdict(true, 'sequence remains responsive with native progress', {
      'seed': seed,
      'actions': actions,
      'nativeMs': await pos(),
    });
  }

  Future<void> system(String mode) async {
    final a = await engine(recovery:mode=='network');
    if (mode == 'network') {
      const url = String.fromEnvironment('GAP_NETWORK_URL');
      if (url.isEmpty) {
        throw GapBlocked(
          'GAP_NETWORK_URL required; adb reverse cannot test network switching',
        );
      }
      await call(
        'open',
        {'uri': url},
        () => a.open(
          MovaSource(
            '$url${url.contains('?') ? '&' : '?'}t=${DateTime.now().microsecondsSinceEpoch}',
          ),
        ),
      );
    } else {
      await open(a, 'long.mp4');
    }
    await until(() async => await pos() > 1000);
    final before = await pos();
    final audioBefore = await optionalNative('audio-pts');
    log('STATE', {'edge': 'before-system-action', ...state()});
    log('STEP', {'hostAction': mode, 'beforeNativeMs': before});
    await until(() => marks.contains('$mode-active'), seconds: 90);
    var continuous = false;
    if (mode == 'screen') {
      try {
        await until(() async => await pos() > before + 1200, seconds: 10);
        continuous = true;
      } on TimeoutException {
        continuous = false;
      }
    }
    final during = await pos();
    log('ACTUAL', {
      'phase': 'active',
      'nativeMs': during,
      'pause': await native('pause'),
      'aid': await native('aid'),
      'audioBefore': audioBefore,
      'audioDuring': await optionalNative('audio-pts'),
      'audio-out-params': await optionalNative('audio-out-params'),
      'state': state(),
    });
    marks.add('$mode-sampled');
    await until(() => marks.contains('$mode-restored'), seconds: 90);
    log('STATE', {'edge': 'after-system-action', ...state()});
    if (mode == 'screen') {
      verdict(
        true,
        'determine whether native audio timeline continues or pauses while OFF/locked',
        {
          'beforeMs': before,
          'lockedMs': during,
          'deltaMs': during - before,
          'aid': await native('aid'),
          'audioContinuous': continuous,
          'conclusion': continuous
              ? 'audio timeline continued'
              : 'audio timeline paused/stalled',
        },
      );
    }
    if (mode == 'focus') {
      verdict(
        false,
        'focus pause/duck and restoration',
        'native state/audio dumps retained',
        blocked: 'manual focus owner and audible output correlation required',
      );
    }
    if (mode == 'network') {
      final p = await pos();
      await until(() async => await pos() > p + 600);
      verdict(true, 'native playback advances after network restoration', {
        'beforeMs': before,
        'duringMs': during,
        'afterMs': await pos(),
      });
    }
  }

  Future<void> runGroup(String group, Map<String, String> args) async {
    run = args['run'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    count = max(3, int.tryParse(args['iterations'] ?? '3') ?? 3);
    origin = args['origin'] ?? origin;
    marks.clear();
    phase = 'running';
    try {
      if (group == 'assumptions') {
        for (final precise in [false, true]) {
          for (final mode in ['playing', 'paused', 'cutover']) {
            await caseOf('H28.${precise ? 'precise' : 'default'}.$mode', [
              'H28',
              'F3',
              'A17',
            ], () => switches(precise, mode));
          }
        }
        for (final shadow in [false, true]) {
          await caseOf('${shadow ? 'H50' : 'H20'}.hlsSeek', [
            'H20',
            'H50',
            'A7',
            'F4',
          ], () => parked(shadow));
        }
        await caseOf('H7.lateError', ['H7', 'A5'], stale);
        await caseOf('H14.manualSeek', ['H14', 'H26', 'A7', 'A17', 'F3'], abr);
        for (final path in ['long.mp4', 'master.m3u8']) {
          await caseOf('H17.${path.split('.').last}', [
            'H17',
            'A7',
          ], () => echo(path));
        }
        for (final recovery in [false, true]) {
          for (final path in [
            'missing',
            'http://127.0.0.1:1/refused',
            'http://mova-gap.invalid/dns',
          ]) {
            await caseOf(
              'H33.${recovery ? 'recovery' : 'direct'}.${path == 'missing'
                  ? '404'
                  : path.contains('invalid')
                  ? 'dns'
                  : 'refused'}',
              ['H33', 'A5'],
              () => errors(path, recovery),
            );
          }
        }
      } else if (group == 'lifecycle') {
        await caseOf('H37.dispose', ['H37', 'A23'], () async {
          final a = await engine();
          await open(a, 'long.mp4');
          await call('dispose.first', {}, a.dispose);
          await call('dispose.second', {}, a.dispose);
          verdict(true, 'second dispose succeeds', state());
        });
        await caseOf('H42.wake', ['H42', 'H43', 'A25', 'F6', 'N20'], keepAlive);
        // 必须放最后：enterPip 会把 Activity 留在系统画中画里，后面的用例会在小窗里跑，
        // 宿主截图也会抓到前台的别的 App（含第三方内容），H43 判图因此失效。
        await caseOf('A15.miniPip', ['A15', 'A18', 'A23', 'F5', 'H56', 'H37'], pip);
      } else if (group == 'local') {
        for (final kind in ['file', 'asset', 'sandbox']) {
          await caseOf('G3.1.$kind', ['G3.1'], () => local(kind));
        }
        await caseOf('G3.1.content', ['G3.1'], () async {
          throw GapBlocked(
            'requires SAF URI grant and provider; no Android provider edits permitted',
          );
        });
      } else if (group == 'formats') {
        await caseOf('G3.2.decoders', ['G3.2', 'H31'], decoders);
        await caseOf('G3.2.hevcSoftware', [
          'G3.2',
          'C17',
          'H39',
        ], () => format('hevc.mp4', true, software: true));
        for (final path in [
          'long.mp4',
          'sample.mkv',
          'sample.webm',
          'sample.ts',
          'sample.mp3',
          'sample.aac',
          'sample.flac',
          'sample.ogg',
          'hevc.mp4',
          'tenbit.mkv',
          'vp9.webm',
          'av1.mkv',
          'uhd.mp4',
        ]) {
          await caseOf('G3.2.$path', [
            'G3.2',
            'H39',
            'H63',
          ], () => format(path, true));
        }
        for (final path in [
          'excluded.avi',
          'excluded.wmv',
          'vp8.webm',
          'sample.ac3',
          'sample.eac3',
        ]) {
          await caseOf('G3.2.$path', ['G3.2', 'H31'], () => format(path, false));
        }
      } else if (group == 'random') {
        await caseOf(
          'G4.1.seed',
          ['G4.1'],
          () => random(
            int.tryParse(args['seed'] ?? '20261028') ?? 20261028,
            int.tryParse(args['actions'] ?? '80') ?? 80,
          ),
        );
      } else if (group == 'focus-gsm') {
        await caseOf('G2.1.emulatorCall', ['G2.1'], () => system('focus'));
      } else if (['screen', 'focus', 'network'].contains(group)) {
        await caseOf(
          'G2.${group == 'focus'
              ? '1'
              : group == 'network'
              ? '2'
              : '3'}.$group',
          [
            'G2.${group == 'focus'
                ? '1'
                : group == 'network'
                ? '2'
                : '3'}',
            if (group == 'screen') 'H60',
          ],
          () => system(group),
        );
      } else if (gapGroups.containsKey(group)) {
        await gapGroups[group]!(args);
      } else {
        throw GapBlocked('unknown group $group');
      }
    } catch (e, s) {
      log('ERROR', {'kind': 'HARNESS', 'error': '$e', 'stack': '$s'});
    }
    phase = 'done';
  }
}

Future<void> serveGap() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18086);
  await for (final req in server) {
    if (req.uri.path == '/run' && gap.phase != 'running') {
      unawaited(
        gap.runGroup(
          req.uri.queryParameters['group'] ?? 'assumptions',
          req.uri.queryParameters,
        ),
      );
    }
    if (req.uri.path == '/mark') {
      gap.marks.add(req.uri.queryParameters['name'] ?? '');
    }
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'phase': gap.phase,
        'rows': req.uri.path == '/mark'
            ? []
            : gap.rows
                  .skip(
                    int.tryParse(req.uri.queryParameters['since'] ?? '0') ?? 0,
                  )
                  .toList(),
        'marks': gap.marks.toList(),
        'state': gap.state(),
      }),
    );
    await req.response.close();
  }
}
