import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'cp3_harness.dart';
import 'cp3_headers_criteria.dart';

const _delay = Duration(milliseconds: 600);
Future<void> _sleep([int ms = 600]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _open(Cp3Harness h) async {
  final a = createMova();
  await h.mount(a);
  await a.open(h.source('a'));
  await h.until(() => a.state.rendered);
  await h.waitPosition(1000);
}

Future<void> runFullscreen(Cp3Harness h) async {
  h.fullscreenRoute = true;
  await _open(h);
  final a = h.api!;
  for (var i = 0; i < 5; i++) {
    await a.setFullscreen(true);
    await _sleep();
    final before = h.snapshot();
    await h.host('back.$i', 'back');
    await _sleep();
    final after = h.snapshot();
    h.check('back.$i', {
      'before': before,
      'after': after,
      'host': h.hostData['back.$i'],
    }, pass: before['fullscreen'] == true && !a.state.fullscreen && h.mounted);
    await a.setFullscreen(true);
    await a.setLocked(true);
    await _sleep();
    final locked = h.snapshot();
    if (!h.mounted) return;
    ScaffoldMessenger.of(h.context).clearSnackBars();
    await h.host('locked.$i', 'back');
    await _sleep(200);
    final prompt = h.elements().any(
      (e) =>
          e.widget is Text &&
          (e.widget as Text).data == a.options.strings.unlock,
    );
    h.check('locked.$i', {
      'before': locked,
      'after': h.snapshot(),
      'host': h.hostData['locked.$i'],
      'unlockVisible': prompt,
    }, pass: a.state.fullscreen && a.state.locked && prompt);
    await a.setLocked(false);
    await a.setFullscreen(false);
    await _sleep();
  }
}

Future<void> runTheme(Cp3Harness h) async {
  await _open(h);
  final a = h.api!;
  final session = MovaSession(a);
  h.cleanup.add(session.dispose);
  await session.load(h.source('a'));
  await h.until(() => a.state.rendered);
  await h.waitPosition(1000);
  final sessionId = identityHashCode(session);
  for (var i = 0; i < 10; i++) {
    final before = await h.native();
    final epoch = a.state.renderEpoch;
    final marker = i.isEven ? 'PLAY' : '播放';
    final color = i.isEven ? 0xff00ff00 : 0xffff0000;
    h.playerTheme = ThemeData(
      extensions: [
        MovaPlayerStyle(
          theme: MovaTheme(accentColor: color),
          strings: MovaStrs(play: marker),
        ),
      ],
    );
    h.refresh();
    await _sleep(250);
    final after = await h.native();
    // Read the resolved values inside the actual player scope.
    final ctx = h.elements().where((e) => e.widget is MovaPlayer).first;
    final observed =
        MovaPlayerStyle.stringsOf(ctx).play == marker &&
        MovaPlayerStyle.themeOf(ctx).accentColor == color;
    final delta = (after['timePosMs'] as int) - (before['timePosMs'] as int);
    h.check(
      'switch.$i',
      {
        'before': before,
        'after': after,
        'sessionBefore': sessionId,
        'sessionAfter': identityHashCode(session),
        'styleObserved': observed,
        'renderEpoch': epoch,
      },
      pass:
          delta >= 0 &&
          delta < 1500 &&
          a.state.renderEpoch == epoch &&
          before['mova'] == after['mova'] &&
          identityHashCode(session) == sessionId &&
          observed,
    );
  }
}

Future<Map<String, dynamic>> _stats() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:18194/stats'),
    );
    return jsonDecode(await utf8.decoder.bind(await request.close()).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<void> runHeaders(Cp3Harness h) async {
  // R4 expands only the native paths; the original 15 CHECKs stay intact.
  const r4 = bool.fromEnvironment('CP3_HEADERS_R4');
  // 新 APK 显式开启：独立冷实例从 bind 返回立即走有界截图能力。
  const captureReady = bool.fromEnvironment('CP3_HEADERS_READY');
  // 原生抽帧和暂停预热使用独立正负对照，不把 open 接受当解码完成。
  Future<Map<String, Object?>> nativePath(String path, int run) async {
    final observations = <String, Object?>{};
    Future<bool> attempt(bool auth) async {
      final source = MovaSource(
        'http://127.0.0.1:18194/a.mp4?case=$path-$run-${auth ? 'yes' : 'no'}',
        headers: auth
            ? const {'Referer': 'https://cp3.example/authorized'}
            : const {},
      );
      if (path == 'extract') {
        final clock = Stopwatch()..start();
        final thumb = MovaPullerThumbSource(extractor: MovaFrameExtractor());
        try {
          final frame = await thumb
              .thumbAt(source, const Duration(seconds: 1))
              .timeout(const Duration(seconds: 20));
          // 不自动重试覆盖第一次失败；保存空帧、耗时和鉴权归属。
          observations[auth ? 'authorized' : 'denied'] = {
            'targetMs': 1000,
            'elapsedMs': clock.elapsedMilliseconds,
            'outcome': frame == null
                ? 'null'
                : frame.bytes.isEmpty
                ? 'empty'
                : 'frame',
            'bytes': frame?.bytes.length,
            'retrySeekCount': null,
            'retryVisibility': 'hidden player has no public retry counter',
          };
          return frame != null && frame.bytes.isNotEmpty;
        } on Object catch (error) {
          observations[auth ? 'authorized' : 'denied'] = {
            'targetMs': 1000,
            'elapsedMs': clock.elapsedMilliseconds,
            'error': '$error',
            'errorType': error.runtimeType.toString(),
          };
          return false;
        } finally {
          await thumb.dispose();
        }
      }
      final IMovaApi mova = path == 'pool-ready-cutover'
          ? MovaCutover(
              movaFactory: () => createMova(preciseFirstFrame: true),
            )
          : createMova(preciseFirstFrame: true);
      final signals = <String>[];
      final frameSub = mova.events.listen((event) {
        if (event is MovaFirstFrame) signals.add(event.signal.name);
      });
      final pool = MovaFeedPool(movaFactory: () => mova, size: 1);
      try {
        await h.mount(mova, raw: true);
        final pauseClock = Stopwatch()..start();
        await pool.bind(1, source).timeout(const Duration(seconds: 20));
        final bindReturnedMs = pauseClock.elapsedMilliseconds;
        final accepted = pool.slotFor(1)?.ready == true;
        if (path.startsWith('pool-ready')) {
          final at = pauseClock.elapsedMilliseconds;
          final image = await (mova as IMovaFrameCapture).screenshot();
          final returnedMs = pauseClock.elapsedMilliseconds;
          var decoded = false;
          if (image != null && image.isNotEmpty) {
            final codec = await ui.instantiateImageCodec(image);
            try {
              final frame = await codec.getNextFrame();
              decoded = frame.image.width > 0 && frame.image.height > 0;
              frame.image.dispose();
            } finally {
              codec.dispose();
            }
          }
          observations[auth ? 'authorized' : 'denied'] = {
            'accepted': accepted,
            'decoded': decoded,
            'null': image == null,
            'imageBytes': image?.length,
            'bindReturnedMs': bindReturnedMs,
            'captureAtMs': at,
            'captureReturnedMs': returnedMs,
            'captureWaitMs': returnedMs - at,
            'paused': !mova.state.playing,
            'firstFrameSignals': signals,
            'state': h.snapshot(mova),
            'readySignal': 'nonempty screenshot result',
          };
          return accepted && decoded && !mova.state.playing;
        }

        await h.until(
          () =>
              mova.state.error != null ||
              (mova.state.rendered &&
                  mova.state.duration > Duration.zero &&
                  mova.state.width > 0 &&
                  mova.state.height > 0),
          seconds: 20,
        );
        final mediaReady =
            mova.state.error == null &&
            mova.state.rendered &&
            mova.state.duration > Duration.zero &&
            !mova.state.playing;
        // 首帧 gate 可由 size/grace 兜底；实际采到图像才认领解码预热成功。
        final controller = mova.renderHandle as VideoController;
        final shots = <Map<String, Object?>>[];
        var renderedFutureReady = false;
        if (r4 && mediaReady) {
          unawaited(
            controller.waitUntilFirstFrameRendered
                .then((_) {
                  renderedFutureReady = true;
                })
                .catchError((Object _) {}),
          );
        }
        final firstShotAtMs = pauseClock.elapsedMilliseconds;
        final image = mediaReady
            ? await (mova.renderHandle as VideoController).player
                  .screenshot(format: 'image/jpeg')
                  .timeout(const Duration(seconds: 10))
            : null;
        final decoded = mediaReady && image != null && image.isNotEmpty;
        shots.add({
          'phase': 'original-gate',
          'atMs': firstShotAtMs,
          'returnedMs': pauseClock.elapsedMilliseconds,
          'bytes': image?.length,
          'null': image == null,
          'firstFrameRenderedFuture': renderedFutureReady,
        });
        if (r4 && mediaReady) {
          // Same paused instance: retain the original result, then compare an
          // explicit renderer-first-frame gate and timed shots without play/seek.
          final gateStart = pauseClock.elapsedMilliseconds;
          var gateReady = false;
          try {
            await controller.waitUntilFirstFrameRendered.timeout(
              const Duration(seconds: 2),
            );
            gateReady = true;
          } on Object {
            /* retain timeout as evidence */
          }
          final at = pauseClock.elapsedMilliseconds;
          final gated = await controller.player
              .screenshot(format: 'image/jpeg')
              .timeout(const Duration(seconds: 10));
          shots.add({
            'phase': 'renderer-first-frame-gate',
            'atMs': at,
            'returnedMs': pauseClock.elapsedMilliseconds,
            'bytes': gated?.length,
            'null': gated == null,
            'gateReady': gateReady,
            'gateWaitMs': at - gateStart,
            'firstFrameRenderedFuture': renderedFutureReady,
          });
          for (final delay in [100, 300, 1000]) {
            await _sleep(delay);
            final at = pauseClock.elapsedMilliseconds;
            final later = await controller.player
                .screenshot(format: 'image/jpeg')
                .timeout(const Duration(seconds: 10));
            shots.add({
              'phase': 'additional-wait-$delay',
              'atMs': at,
              'returnedMs': pauseClock.elapsedMilliseconds,
              'bytes': later?.length,
              'null': later == null,
              'firstFrameRenderedFuture': renderedFutureReady,
            });
          }
        }
        observations[auth ? 'authorized' : 'denied'] = {
          'accepted': accepted,
          'decoded': decoded,
          'state': h.snapshot(mova),
          'firstFrameSignals': signals,
          'imageBytes': image?.length,
          'bindReturnedMs': bindReturnedMs,
          'shots': shots,
          'clockOrigin': 'immediately before pool.bind(play:false)',
          if (decoded) 'native': await h.native(),
        };
        return accepted && decoded;
      } on Object catch (error) {
        observations[auth ? 'authorized' : 'denied'] = {
          'error': '$error',
          'state': h.snapshot(mova),
        };
        return false;
      } finally {
        await pool.dispose();
        await frameSub.cancel();
        await h.release(disposeMova: false);
      }
    }

    final positive = await attempt(true);
    final negative = await attempt(false);
    final requests = ((await _stats())['requests'] as List)
        .cast<Map<String, dynamic>>()
        .where((r) => (r['query'] as String).startsWith('case=$path-$run-'))
        .toList();
    final good = requests
        .where((r) => (r['query'] as String).endsWith('-yes'))
        .toList();
    final bad = requests
        .where((r) => (r['query'] as String).endsWith('-no'))
        .toList();
    return {
      'positive': positive,
      'negative': negative,
      'requests': requests,
      'observations': observations,
      'pass':
          positive &&
          !negative &&
          good.isNotEmpty &&
          bad.isNotEmpty &&
          good.every(
            (r) =>
                r['status'] == 200 &&
                r['referer'] == 'https://cp3.example/authorized',
          ) &&
          bad.every((r) => r['status'] == 403),
    };
  }

  for (final variant in ['quality', 'thumb', 'prefetch']) {
    for (var i = 0; i < 5; i++) {
      final token = '$variant-$i';
      final path = variant == 'quality' ? 'master.m3u8' : 'a.mp4';
      MovaSource source(bool auth) => MovaSource(
        'http://127.0.0.1:18194/$path?case=$token-${auth ? 'yes' : 'no'}',
        headers: auth
            ? const {'Referer': 'https://cp3.example/authorized'}
            : const {},
      );
      final qualityObservations = <String, Object?>{};
      Future<bool> attempt(bool auth) async {
        final s = source(auth);
        if (variant == 'quality') {
          final a = createMova();
          await h.mount(a);
          try {
            try {
              await a.open(s);
            } on Object {
              /* negative control may reject open */
            }
            await a.loadQualities();
            final qualities = a.state.qualities
                .map(
                  (q) => <String, Object?>{
                    'auto': q.isAuto,
                    'label': q.label,
                    'uri': q.uri,
                    'height': q.height,
                    'bandwidth': q.bandwidth,
                  },
                )
                .toList();
            final observation = <String, Object?>{
              'qualities': qualities,
              'currentQuality': a.state.currentQuality?.label,
            };
            qualityObservations[auth ? 'authorized' : 'denied'] = observation;
            // 拒绝对照保留非空列表即失败的语义，不能用选档失败掩盖泄漏。
            if (!auth) return qualities.isNotEmpty;
            final expected = Uri.parse(
              s.uri,
            ).replace(path: '/index.m3u8').toString();
            String? selectedPath;
            try {
              final variants = a.state.qualities.where((q) => !q.isAuto);
              if (variants.isNotEmpty) {
                await a.switchQuality(variants.first);
                await h.until(() async {
                  final read = await h.native();
                  observation['selectedNative'] = read;
                  // mova 给带头网络源追加 #mova-load=N 隔离进程级缓存，比较时去掉。
                  selectedPath = (read['path'] as String?)?.split('#').first;
                  return selectedPath == expected;
                }, seconds: 10);
              }
            } on Object catch (error) {
              observation['selectionError'] = '$error';
            }
            observation['expectedUri'] = expected;
            observation['selectedPath'] = selectedPath;
            return cp3HeadersQualityPass(qualities, expected, selectedPath);
          } finally {
            await h.release();
          }
        }
        if (variant == 'thumb') {
          final vtt = MovaVttThumbSource(fetcher: MovaIoHttpFetcher());
          try {
            final thumb = await vtt.thumbAt(s, Duration.zero);
            if (thumb == null) return false;
            final codec = await ui.instantiateImageCodec(thumb.bytes);
            try {
              final frame = await codec.getNextFrame();
              final valid = frame.image.width > 0 && frame.image.height > 0;
              frame.image.dispose();
              return valid;
            } finally {
              codec.dispose();
            }
          } finally {
            await vtt.dispose();
          }
        }
        await const MovaNetworkWarmFeedPrefetcher().prime(s);
        return true; // Actual success is decided by server receipts below.
      }

      final positive = await attempt(true);
      final negative = await attempt(false);
      final requests = ((await _stats())['requests'] as List)
          .cast<Map<String, dynamic>>()
          .where((r) => (r['query'] as String).startsWith('case=$token-'))
          .toList();
      final good = requests
          .where((r) => (r['query'] as String).endsWith('-yes'))
          .toList();
      final bad = requests
          .where((r) => (r['query'] as String).endsWith('-no'))
          .toList();
      final allowed =
          good.isNotEmpty &&
          good.every(
            (r) =>
                r['status'] == 200 &&
                r['referer'] == 'https://cp3.example/authorized',
          );
      final denied = bad.isNotEmpty && bad.every((r) => r['status'] == 403);
      final resources =
          variant != 'thumb' || good.any((r) => r['path'] == '/sprite.png');
      final range =
          variant != 'prefetch' || good.any((r) => r['range'] != null);
      final nativePaths = <String, Map<String, Object?>>{};
      if (variant == 'quality') {
        for (final path in [
          'extract',
          'pool',
          if (captureReady) 'pool-ready',
          if (captureReady) 'pool-ready-cutover',
        ]) {
          nativePaths[path] = await nativePath(path, i);
          if (r4 || path.startsWith('pool-ready')) {
            final samples = <Map<String, Object?>>[nativePaths[path]!];
            final count = path == 'extract' ? 12 : 6;
            for (var extra = 1; extra < count; extra++) {
              samples.add(await nativePath(path, i + extra * 5));
            }
            nativePaths[path] = {
              ...nativePaths[path]!,
              'samples': samples,
              if (path.startsWith('pool-ready')) ...{
                'sampleCount': samples.length,
                'authorizedNullCount': samples
                    .where(
                      (s) =>
                          ((s['observations'] as Map)['authorized']
                              as Map)['null'] ==
                          true,
                    )
                    .length,
                'authorizedReadyCount': samples
                    .where(
                      (s) =>
                          ((s['observations'] as Map)['authorized']
                              as Map)['decoded'] ==
                          true,
                    )
                    .length,
                'criterion':
                    'authorized null=0 and decoded=all; denied decoded=0; paused throughout',
              },
              'pass': samples.every((s) => s['pass'] == true),
            };
          }
        }
      }
      h.check(
        '$variant.$i',
        {
          'positive': positive,
          'negative': negative,
          'requests': requests,
          'nativePaths': nativePaths,
          if (variant == 'quality') ...{
            'qualityObservations': qualityObservations,
            'captureReady': captureReady,
            'poolCriterion': captureReady
                ? 'pool-ready and pool-ready-cutover; pool diagnostic only'
                : 'legacy pool',
          },
        },
        pass:
            positive &&
            (variant == 'prefetch' || !negative) &&
            allowed &&
            denied &&
            resources &&
            range &&
            (variant != 'quality' ||
                cp3HeadersNativePathsPass(
                  nativePaths,
                  captureReady: captureReady,
                )),
      );
    }
  }
}

Future<void> runFeedplayer(Cp3Harness h) async {
  final ctrl = MovaFeedPlayerCtrl();
  var failures = 0;
  final feed = MovaFeedPlayer(
    ctrl: ctrl,
    movaFactory: createMova,
    prefetchDepth: 0,
    loader: (index) async {
      if (index == 2) throw StateError('CP3 deliberate loader failure');
      return index < 3
          ? MovaFeedItem(source: h.source(index == 0 ? 'a' : 'b'))
          : null;
    },
    errorBuilder: (context, index, error, retry) {
      failures++;
      return const Center(child: Text('CP3 PAGE FAILURE'));
    },
  );
  h.customSurface = feed;
  h.refresh();
  await h.frame();
  await h.until(() => ctrl.activeApi?.state.rendered ?? false);
  h.api = ctrl.activeApi;
  h.observe(h.api!);
  for (var i = 0; i < 5; i++) {
    final before = h.snapshot();
    ctrl.jumpToPage(i.isEven ? 1 : 0);
    await h.until(
      () =>
          ctrl.activeIndex == (i.isEven ? 1 : 0) &&
          (ctrl.activeApi?.state.rendered ?? false),
    );
    h.api = ctrl.activeApi;
    await ctrl.pause();
    await _sleep(150);
    final paused = !(ctrl.activeApi?.state.playing ?? true);
    await ctrl.play();
    await h.until(() => ctrl.activeApi!.state.playing);
    h.check('ctrl.$i', {
      'before': before,
      'after': h.snapshot(),
      'observed': {'index': ctrl.activeIndex, 'paused': paused},
    }, pass: paused);
    final visible = h.snapshot();
    h.tickerEnabled = false;
    h.refresh();
    await _sleep();
    final hidden = h.snapshot();
    final stopped = !ctrl.activeApi!.state.playing;
    h.tickerEnabled = true;
    h.refresh();
    await h.until(() => ctrl.activeApi!.state.playing);
    h.check('autoPause.$i', {
      'before': visible,
      'after': hidden,
      'observed': h.snapshot(),
    }, pass: stopped);
    final start = failures;
    ctrl.jumpToPage(2);
    await _sleep();
    final errorVisible = h.elements().any(
      (e) => e.widget is Text && (e.widget as Text).data == 'CP3 PAGE FAILURE',
    );
    h.check('failure.$i', {
      'before': {'failures': start},
      'after': {'failures': failures},
      'observed': errorVisible,
    }, pass: errorVisible && failures > start);
    ctrl.jumpToPage(0);
    await h.until(
      () => ctrl.activeIndex == 0 && (ctrl.activeApi?.state.rendered ?? false),
    );
    h.api = ctrl.activeApi;
  }
  // Feed owns all players. Detach before generic harness cleanup.
  h.api = null;
  h.customSurface = const SizedBox();
  h.refresh();
  await h.frame();
  ctrl.dispose();
}

Future<void> runC04chrome(Cp3Harness h) async {
  final chrome = MovaChrome();
  h.chrome = chrome;
  h.style = const MovaPlayerStyle(
    controls: MovaCtrlsOpts(autoHideDelay: _delay),
  );
  await _open(h);
  for (var i = 0; i < 5; i++) {
    chrome.show();
    final start = h.clock.elapsedMilliseconds;
    final before = chrome.value.controlsVisible;
    await _sleep(300);
    final early = chrome.value.controlsVisible;
    await _sleep(550);
    h.check('hide.$i', {
      'before': before,
      'after': chrome.value.controlsVisible,
      'elapsedMs': h.clock.elapsedMilliseconds - start,
    }, pass: early && !chrome.value.controlsVisible);
    chrome.setDragging(true);
    await _sleep(850);
    final dragging = chrome.value.controlsVisible && chrome.value.dragging;
    chrome.setDragging(false);
    await _sleep(850);
    h.check('drag.$i', {
      'before': dragging,
      'after': chrome.value.controlsVisible,
      'elapsedMs': 1700,
    }, pass: dragging && !chrome.value.controlsVisible);
    chrome.show();
    await _sleep(250);
    h.style = MovaPlayerStyle(
      theme: MovaTheme(accentColor: i.isEven ? 0xff00ff00 : 0xffff0000),
      controls: const MovaCtrlsOpts(autoHideDelay: _delay),
    );
    h.refresh();
    await _sleep(600);
    h.check('style.$i', {
      'before': true,
      'after': chrome.value.controlsVisible,
      'elapsedMs': 850,
    }, pass: !chrome.value.controlsVisible);
    chrome.showHud(MovaHud.volume, text: 'CP3');
    final shown = chrome.value.hud == MovaHud.volume;
    await _sleep(1800);
    h.check('hud.$i', {
      'before': shown,
      'after': chrome.value.hud.name,
      'elapsedMs': 1800,
    }, pass: shown && chrome.value.hud == MovaHud.none);
  }
  await h.release();
  chrome.dispose();
}

class _BottomMarker extends MovaComponent {
  @override
  String get name => 'cp3Marker';
  @override
  MovaSlot get slot => MovaSlot.bottom;
  @override
  Widget build(BuildContext context, IMovaApi api, List<Widget> children) =>
      const Text('CP3 BOTTOM');
}

Future<void> runCp1gap(Cp3Harness h) async {
  final a = createMova(
    options: const MovaOpts(
      live: MovaLiveOpts(
        seekMode: MovaLiveSeekMode.dvr,
        dvrWindow: Duration(minutes: 2),
      ),
    ),
  );
  await h.mount(a);
  await a.open(h.source('a'));
  await h.until(() => a.state.rendered);
  for (var i = 0; i < 5; i++) {
    final observations = <Map<String, Object?>>[];
    var passed = true;
    for (final name in [
      'positionLabel',
      'liveBadge',
      'seekBar',
      'timeshift',
      'durationLabel',
      'backToLive',
    ]) {
      // 直播叶子必须在真实直播/DVR 布局中挂载，不能拿 VOD 的隐藏节点作锚点。
      final live = !['positionLabel', 'durationLabel'].contains(name);
      final type = live ? MovaStreamType.live : MovaStreamType.vod;
      if (a.state.type != type) {
        await a.open(h.source(live ? 'live' : 'a', live: live));
        await h.until(
          () => a.state.rendered && (!live || a.state.liveSeekable),
        );
      }
      for (final remove in [true, false]) {
        h.customSurface = MovaPlayer(
          api: a,
          uiKit: MovaDefaultUiKit(
            patches: [
              remove
                  ? MovaPatch.remove('bottomBar/$name')
                  : MovaPatch.insertAfter('bottomBar/$name', _BottomMarker()),
            ],
          ),
        );
        h.refresh();
        await h.frame();
        await h.frame();
        final built = h
            .elements()
            .where((e) => e.widget is MovaBuiltChild)
            .map((e) => (e.widget as MovaBuiltChild).name)
            .toList();
        final marker = h.elements().any(
          (e) => e.widget is Text && (e.widget as Text).data == 'CP3 BOTTOM',
        );
        final ok = remove
            ? !built.contains(name)
            : built.contains(name) && marker;
        passed = passed && ok;
        observations.add({
          'name': name,
          'type': a.state.type.name,
          'liveSeekable': a.state.liveSeekable,
          'remove': remove,
          'built': built,
          'marker': marker,
          'pass': ok,
        });
      }
    }
    h.check('bottomPatch.$i', {
      'before': await h.native(),
      'after': observations,
      'observed': passed,
    }, pass: passed);
  }
  h.customSurface = null;
}
