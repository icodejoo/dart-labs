import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'cp3_harness.dart';

const _delay = Duration(milliseconds: 600);
Future<void> _sleep([int ms = 600]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _open(Cp3Harness h) async {
  final a = createMovaEngine();
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
          before['engine'] == after['engine'] &&
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
      Future<bool> attempt(bool auth) async {
        final s = source(auth);
        if (variant == 'quality') {
          final a = createMovaEngine();
          await h.mount(a);
          try {
            try {
              await a.open(s);
            } on Object {
              /* negative control may reject open */
            }
            await a.loadQualities();
            return a.state.qualities.isNotEmpty;
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
      h.check(
        '$variant.$i',
        {'positive': positive, 'negative': negative, 'requests': requests},
        pass:
            positive &&
            (variant == 'prefetch' || !negative) &&
            allowed &&
            denied &&
            resources &&
            range,
      );
    }
  }
}

Future<void> runFeedplayer(Cp3Harness h) async {
  final ctl = MovaFeedPlayerController();
  var failures = 0;
  final feed = MovaFeedPlayer(
    controller: ctl,
    engineFactory: createMovaEngine,
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
  await h.until(() => ctl.activeApi?.state.rendered ?? false);
  h.api = ctl.activeApi;
  h.observe(h.api!);
  for (var i = 0; i < 5; i++) {
    final before = h.snapshot();
    ctl.jumpToPage(i.isEven ? 1 : 0);
    await h.until(
      () =>
          ctl.activeIndex == (i.isEven ? 1 : 0) &&
          (ctl.activeApi?.state.rendered ?? false),
    );
    h.api = ctl.activeApi;
    await ctl.pause();
    await _sleep(150);
    final paused = !(ctl.activeApi?.state.playing ?? true);
    await ctl.play();
    await h.until(() => ctl.activeApi!.state.playing);
    h.check('controller.$i', {
      'before': before,
      'after': h.snapshot(),
      'observed': {'index': ctl.activeIndex, 'paused': paused},
    }, pass: paused);
    final visible = h.snapshot();
    h.tickerEnabled = false;
    h.refresh();
    await _sleep();
    final hidden = h.snapshot();
    final stopped = !ctl.activeApi!.state.playing;
    h.tickerEnabled = true;
    h.refresh();
    await h.until(() => ctl.activeApi!.state.playing);
    h.check('autoPause.$i', {
      'before': visible,
      'after': hidden,
      'observed': h.snapshot(),
    }, pass: stopped);
    final start = failures;
    ctl.jumpToPage(2);
    await _sleep();
    final errorVisible = h.elements().any(
      (e) => e.widget is Text && (e.widget as Text).data == 'CP3 PAGE FAILURE',
    );
    h.check('failure.$i', {
      'before': {'failures': start},
      'after': {'failures': failures},
      'observed': errorVisible,
    }, pass: errorVisible && failures > start);
    ctl.jumpToPage(0);
    await h.until(
      () => ctl.activeIndex == 0 && (ctl.activeApi?.state.rendered ?? false),
    );
    h.api = ctl.activeApi;
  }
  // Feed owns all engines. Detach before generic harness cleanup.
  h.api = null;
  h.customSurface = const SizedBox();
  h.refresh();
  await h.frame();
  ctl.dispose();
}

Future<void> runC04chrome(Cp3Harness h) async {
  final chrome = MovaChrome();
  h.chrome = chrome;
  h.style = const MovaPlayerStyle(
    controls: MovaCtrlsConfig(autoHideDelay: _delay),
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
      controls: const MovaCtrlsConfig(autoHideDelay: _delay),
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
  Widget build(BuildContext context, MovaApi api, List<Widget> children) =>
      const Text('CP3 BOTTOM');
}

Future<void> runCp1gap(Cp3Harness h) async {
  final a = createMovaEngine(options: const MovaOpts(
    live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr, dvrWindow: Duration(minutes: 2)),
  ));
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
        await h.until(() => a.state.rendered && (!live || a.state.liveSeekable));
      }
      for (final remove in [true, false]) {
        h.customSurface = MovaPlayer(
          api: a,
          skin: MovaDefaultSkin(
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
