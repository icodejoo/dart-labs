import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:mova/mova.dart';
// ignore: implementation_imports
import 'package:mova/src/core/kernel/mpv_kernel.dart';
// ignore: implementation_imports
import 'package:mova/src/platform_impl/frame_yield.dart';
import 'coverage_gap.dart' show gap;

final perfSurfaces = ValueNotifier<List<MovaApi>>([]);
// All three feed surfaces stay mounted while the viewport scrolls between them.
final perfScroll = ScrollController();
final _perf = PerfRunner();

/// Flutter frame budget at 60 Hz in microseconds.
/// 60Hz 下单帧预算（微秒）。
const _frameBudgetMicros = 16667;

class PerfRunner {
  final natives = <NativePlayer>[];
  final engines = <MovaEngine>[];
  final previous = <NativePlayer, Map<String, double>>{};
  final subscriptions = <StreamSubscription<dynamic>>[];
  Map<String, Object?> latest = {};
  Map<String, Object?> result = {};
  bool busy = false;
  bool running = false;
  Completer<void>? finish;
  double drops = 0, decoderDrops = 0, frames = 0;

  /// Cumulative Flutter frame counters of the running scene.
  /// 当前场景内 Flutter 帧累计计数：总帧、build 超预算、raster 超预算、任一超预算。
  int uiFrames = 0, uiBuildJanky = 0, uiRasterJanky = 0, uiJanky = 0;

  /// Frame timing callback; dumpsys gfxinfo cannot see Flutter's own surface.
  /// 帧耗时回调；dumpsys gfxinfo 统计不到 Flutter 自己的 Surface。
  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds > _frameBudgetMicros;
      final raster = t.rasterDuration.inMicroseconds > _frameBudgetMicros;
      uiFrames++;
      if (build) uiBuildJanky++;
      if (raster) uiRasterJanky++;
      if (build || raster) uiJanky++;
    }
  }

  MovaEngine factory({bool audio = false, bool cutover = false}) {
    gap.log('CALL', {
      'method': 'createMovaEngine',
      'audioOnly': audio,
      'cutover': cutover,
    });
    // Inject the production kernel to retain native handles, including audioOnly.
    // Every engine still uses the production createMovaEngine wiring.
    final player = Player();
    final kernel = MovaMpvKernel(
      player: player,
      audioOnly: audio,
      lazyVideo: true,
      mountYield: movaFrameYield,
    );
    natives.add(player.platform as NativePlayer);
    final engine = createMovaEngine(
      kernel: kernel,
      audioOnly: audio,
      options: MovaOpts(
        cutover: MovaCutoverConfig(
          enabled: cutover,
          trigger: const MovaEagerWarm(),
        ),
      ),
    );
    engines.add(engine);
    gap.log('RET', {
      'method': 'createMovaEngine',
      'engine': engines.length - 1,
    });
    subscriptions.add(
      engine.events.listen(
        (e) => gap.log('EVENT', {
          'engine': engines.indexOf(engine),
          'type': '${e.runtimeType}',
          'payload': gap.payload(e),
          'state': engine.state.toString(),
        }),
      ),
    );
    subscriptions.add(
      engine.states.listen((s) {
        gap.api = engine;
        gap.log('STATE', gap.state());
      }),
    );
    return engine;
  }

  Future<void> mount(List<MovaApi> apis) async {
    perfSurfaces.value = apis;
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> sample(double elapsed) async {
    final properties = <Map<String, Object?>>[];
    var countersOk = true;
    for (final n in List<NativePlayer>.of(natives)) {
      final props = <String, Object?>{};
      for (final key in [
        'frame-drop-count',
        'decoder-frame-drop-count',
        'hwdec-current',
        'video-codec',
        'estimated-vf-fps',
        'time-pos',
      ]) {
        try {
          props[key] = await gap.call('NativePlayer.getProperty', {
            'key': key,
          }, () => n.getProperty(key).timeout(const Duration(seconds: 3)));
        } catch (e, s) {
          props[key] = null;
          gap.log('ERROR', {
            'kind': 'HARNESS',
            'property': key,
            'error': '$e',
            'stack': '$s',
          });
        }
      }
      final values = <String, double>{};
      for (final key in [
        'frame-drop-count',
        'decoder-frame-drop-count',
        'time-pos',
      ]) {
        final value = double.tryParse('${props[key]}');
        if (value != null) values[key] = value;
      }
      final old = previous[n];
      final fps = double.tryParse('${props['estimated-vf-fps']}');
      countersOk &= values.length == 3 && fps != null && fps > 0;
      if (old != null && values.length == 3 && fps != null && fps > 0) {
        double delta(String key) {
          final d = values[key]! - (old[key] ?? values[key]!);
          return d >= 0 ? d : values[key]!;
        }

        drops += delta('frame-drop-count');
        decoderDrops += delta('decoder-frame-drop-count');
        // Playback-time * measured vf fps is an estimated frame denominator.
        // Bound wrap/seek contributions; never count wall time during stalls.
        final positionDelta =
            values['time-pos']! - (old['time-pos'] ?? values['time-pos']!);
        final elapsedDelta = elapsed - (old['_elapsed'] ?? elapsed);
        if (positionDelta >= 0 && positionDelta <= elapsedDelta * 1.5 + 1) {
          frames += positionDelta * fps;
        }
      }
      previous[n] = {...values, '_elapsed': elapsed};
      properties.add(props);
    }
    // The release app cannot be inspected by adb shell; count own fds in-process.
    // release 包 shell 读不到 /proc/PID/fd，改由进程自己数（扣除遍历本身占用的 1 个）。
    // Listing races with fds closing in other threads; retry a few times.
    // 遍历时其他线程可能恰好关闭 fd 导致抛错，重试几次。
    int? fdCount;
    for (var i = 0; i < 5 && fdCount == null; i++) {
      try {
        fdCount = Directory('/proc/self/fd').listSync().length - 1;
      } catch (_) {}
    }
    latest = {
      't': elapsed,
      'fd': fdCount,
      'drops': countersOk ? drops : null,
      'decoder_drops': countersOk ? decoderDrops : null,
      'frames': countersOk ? frames : null,
      // Flutter's own frame timings feed the host's janky / gfx_frames fields.
      'janky': uiJanky,
      'gfx_frames': uiFrames,
      'ui_build_janky': uiBuildJanky,
      'ui_raster_janky': uiRasterJanky,
      'frameBudgetMicros': _frameBudgetMicros,
      'mpv': properties,
      'frameDenominator': 'positive time-pos delta * estimated-vf-fps',
    };
    gap.log('STATE', latest);
  }

  Future<void> run(Map<String, dynamic> args) async {
    running = true;
    busy = true;
    finish = Completer<void>();
    result = {};
    latest = {};
    drops = decoderDrops = frames = 0;
    uiFrames = uiBuildJanky = uiRasterJanky = uiJanky = 0;
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    previous.clear();
    final scene = args['scene'] as String;
    gap.run = args['run'] as String? ?? 'perf';
    gap.current = 'perf:$scene';
    gap.rows.clear();
    final live = scene.contains('live');
    final audio = scene == 'audio';
    final soft = scene == 'vod-sw';
    final seconds = (args['seconds'] as num).toDouble();
    final interval = (args['interval'] as num?)?.toDouble() ?? 2;
    final source = MovaSource(
      args['url'] as String,
      type: live ? MovaStreamType.live : MovaStreamType.vod,
      mpvOptions: {
        'hwdec': soft ? 'no' : 'auto-safe',
        if (!live) 'loop-file': 'inf',
      },
    );
    MovaApi? api;
    MovaFeedEnginePool? pool;
    try {
      gap.log('BEGIN', {'scene': scene});
      gap.log('STEP', {'scene': scene, 'seconds': seconds, 'url': source.uri});
      if (scene == 'feed') {
        pool = MovaFeedEnginePool(engineFactory: () => factory(), size: 3);
        for (var i = 0; i < 3; i++) {
          gap.log('CALL', {
            'method': 'pool.bind',
            'index': i,
            'url': source.uri,
          });
          final pending = pool.bind(i, source);
          await mount([for (final e in engines) e]);
          await pending;
          gap.log('RET', {'method': 'pool.bind', 'index': i});
        }
        await gap.call('pool.focus', {'index': 0}, () => pool!.focus(0));
      } else if (scene == 'cutover') {
        api = MovaCutoverEngine(engineFactory: () => factory(cutover: true));
        await mount([api]);
        await gap.call('open', {'url': source.uri}, () => api!.open(source));
        await gap.call(
          'prepare',
          {'url': source.uri},
          () => (api as MovaCutoverEngine).prepare(
            source,
            plan: const MovaWarmPlan(
              trigger: MovaEagerWarm(),
              pauseWhenReady: true,
            ),
          ),
        );
      } else {
        api = factory(audio: audio);
        if (!audio) await mount([api]);
        await gap.call('open', {'url': source.uri}, () => api!.open(source));
      }
      final watch = Stopwatch()..start();
      var nextSwipe = 5.0, index = 0;
      while (watch.elapsedMilliseconds / 1000 < seconds) {
        final t = watch.elapsedMilliseconds / 1000;
        if (pool != null && t >= nextSwipe) {
          index++;
          gap.log('CALL', {
            'method': 'pool.retain',
            'indices': [index, index + 1, index + 2],
          });
          pool.retain([index, index + 1, index + 2]);
          gap.log('RET', {'method': 'pool.retain'});
          for (var i = index; i <= index + 2; i++) {
            await gap.call('pool.bind', {
              'index': i,
              'url': source.uri,
            }, () => pool!.bind(i, source));
          }
          await gap.call('pool.focus', {
            'index': index,
          }, () => pool!.focus(index));
          await perfScroll.animateTo(
            engines.indexWhere((e) => identical(e, pool!.slotFor(index)!.api)) *
                perfScroll.position.viewportDimension,
            duration: const Duration(milliseconds: 350),
            curve: Curves.linear,
          );
          nextSwipe += 5;
        }
        await sample(t);
        if (!audio && !live && scene != 'cutover' && t > 10) {
          final hw = (latest['mpv'] as List).first['hwdec-current'];
          if (hw == null ||
              (!soft && (hw == 'no' || hw == '')) ||
              (soft && hw != 'no')) {
            throw StateError('decoder mode not satisfied: $hw');
          }
        }
        if (scene == 'cutover') {
          gap.log('STATE', {
            'phase': (api as MovaCutoverEngine).cutoverPhase.name,
            'engineCount': natives.length,
          });
          if (natives.length != 2) throw StateError('dual engine absent');
        }
        // Bound retained framework rows: stdout and host JSONL keep full evidence.
        if (gap.rows.length > 500) {
          gap.rows.removeRange(0, gap.rows.length - 250);
        }
        await Future<void>.delayed(
          Duration(milliseconds: (interval * 1000).round()),
        );
      }
      result = {'status': 'COLLECTED', 'scene': scene};
      gap.log('EXPECT', {'host': 'baseline + steady + slope + drop gates'});
      gap.log('ACTUAL', result);
      gap.log('VERDICT', {
        'status': 'BLOCKED',
        'reason': 'host-judgement-required',
      });
      // Keep the last scene mounted until host verdict/evidence capture ends.
      busy = false;
      await finish!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {},
      );
    } catch (e, s) {
      result = {
        'status': 'BLOCKED',
        'kind': 'HARNESS',
        'error': '$e',
        'stack': '$s',
      };
      gap.log('EXPECT', {'scene': 'complete uninterrupted playback'});
      gap.log('ACTUAL', result);
      gap.log('ERROR', result);
      gap.log('VERDICT', result);
    } finally {
      try {
        await mount([]);
        if (pool != null) await gap.call('pool.dispose', {}, pool.dispose);
        if (api != null) await gap.call('dispose', {}, api.dispose);
      } catch (e, s) {
        result = {
          'status': 'BLOCKED',
          'kind': 'HARNESS',
          'error': '$e',
          'stack': '$s',
        };
        gap.log('ERROR', result);
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(onTimings);
        for (final s in subscriptions) {
          await s.cancel();
        }
        subscriptions.clear();
        natives.clear();
        engines.clear();
        previous.clear();
        gap.api = null;
        busy = false;
        running = false;
        gap.log('END', result);
      }
    }
  }
}

Future<void> servePerf() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18089);
  await for (final request in server) {
    request.response.headers.contentType = ContentType.json;
    try {
      if (request.uri.path == '/start' && request.method == 'POST') {
        if (_perf.running) throw StateError('scenario busy');
        final args =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        unawaited(_perf.run(args));
      }
      if (request.uri.path == '/finish' &&
          !(_perf.finish?.isCompleted ?? true)) {
        _perf.finish!.complete();
      }
      request.response.write(
        jsonEncode({
          'busy': _perf.busy,
          'running': _perf.running,
          'pid': pid,
          'sample': _perf.latest,
          'result': _perf.result,
        }),
      );
    } catch (e) {
      request.response.statusCode = 400;
      request.response.write(jsonEncode({'error': '$e'}));
    }
    await request.response.close();
  }
}
