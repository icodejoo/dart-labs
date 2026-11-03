// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import 's00d_widgets_test.dart' as d;

Widget tree(BuildContext context, MovaApi a, MovaComponent c) =>
    c.build(context, a, [for (final child in c.children) tree(context, a, child)]);

Future<void> mount(WidgetTester t, MovaApi a, MovaComponent c) async {
  await t.pumpWidget(MaterialApp(home: Scaffold(body: MovaScope(api: a,
    child: Center(child: SizedBox(width: 400, height: 240,
      child: Builder(builder: (context) => tree(context, a, c))))))));
  await d.drain(t);
}

List<String?> texts(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((v) => v.data).toList();

class Cues extends MovaNoopSttEngine {
  final output = StreamController<MovaSttCue>.broadcast();
  @override
  List<String> get languages => ['zh'];
  @override
  Stream<MovaSttCue> get cues => output.stream;
  @override
  Future<void> dispose() => output.close();
}

void main() {
  setUp(MovaTesting.useTestKernels);
  tearDown(MovaTesting.reset);

  testWidgets('fit and quality HUD deliberately render no badge', (t) async {
    final a = await d.make(t);
    await mount(t, a, MovaHudLayerComponent());
    for (final kind in [MovaHud.fit, MovaHud.quality]) {
      a.showHud(kind, text: 'S00E sentinel');
      await d.drain(t);
      d.measured('U5.${kind.name}.contract', texts(t), <String>[]);
    }
    await d.unmount(t); await d.dispose(t, a);
  });

  testWidgets('horizontal mappings and live/disabled combinations use real pointers', (t) async {
    for (final action in MovaGestureAction.values) {
      for (final live in [false, true]) {
        for (final allowed in [false, true]) {
          final a = await d.make(t, options: MovaOpts(gesture: MovaGestureConfig(
            horizontal: action, allowWhenLive: allowed, doubleTapSeek: false, pinchZoom: false)));
          final k = MovaTesting.lastKernel!;
          await a.open(MovaSource('s00e://gesture', type: live ? MovaStreamType.live : MovaStreamType.vod));
          k.emitDuration(const Duration(seconds: 100));
          await a.setVolume(25); await a.setBrightness(.25);
          await mount(t, a, MovaGestureLayerComponent());
          final before = [a.state.volume, a.state.brightness, k.calls.where((v) => v == 'seek').length];
          final center = t.getCenter(find.byType(MovaScope));
          await t.tapAt(center); await t.pump(const Duration(milliseconds: 60)); await t.tapAt(center); await d.drain(t);
          d.measured('U6.disabled.double.${action.name}.$live.$allowed', k.calls.where((v) => v == 'seek').length, before[2]);
          final zoomBefore = a.state.zoom;
          final p1 = await t.startGesture(center - const Offset(20, 0), pointer: 10);
          final p2 = await t.startGesture(center + const Offset(20, 0), pointer: 11);
          await p1.moveBy(const Offset(-60, 0)); await p2.moveBy(const Offset(60, 0)); await t.pump();
          await p1.up(); await p2.up(); await d.drain(t);
          d.measured('U6.disabled.pinch.${action.name}.$live.$allowed', a.state.zoom, zoomBefore);
          final pointer = await t.startGesture(center - const Offset(100, 0));
          await pointer.moveBy(const Offset(30, 0)); await t.pump();
          await pointer.moveBy(const Offset(70, 0)); await t.pump();
          await pointer.up(); await d.drain(t);
          // allowWhenLive gates seek only; volume and brightness stay available.
          final expected = [
            action == MovaGestureAction.volume,
            action == MovaGestureAction.brightness,
            !live && action == MovaGestureAction.seek,
          ];
          d.measured('U6.map.${action.name}.$live.$allowed', [
            a.state.volume > (before[0] as double),
            a.state.brightness > (before[1] as double),
            k.calls.where((v) => v == 'seek').length > (before[2] as int),
          ], expected, numbers: {'before': before, 'after': [a.state.volume, a.state.brightness,
            k.calls.where((v) => v == 'seek').length], 'live': live, 'allowWhenLive': allowed});
          await d.unmount(t); await d.dispose(t, a); await t.pump(const Duration(seconds: 1));
        }
      }
    }
  });

  testWidgets('Douyin has independent tap like and no drag controls; social callbacks render', (t) async {
    final a = await d.make(t); final k = MovaTesting.lastKernel!;
    var likes = 0; var comments = 0; var shares = 0; var avatars = 0; var follows = 0;
    final item = MovaFeedItem(source: const MovaSource('s00e://feed'), initialLikeCount: 5,
      commentCount: 42, shareCount: 7, authorName: 'S00E',
      onLikeChanged: (_, _) => likes++, onComment: () => comments++, onShare: () => shares++,
      onAvatarTap: () => avatars++, onFollowTap: () => follows++);
    final pool = MovaFeedEnginePool(engineFactory: () => a, size: 1);
    final feed = MovaFeed(pool: pool, loader: (_) async => item);
    await feed.ensure(0); await a.open(item.source); k.emitPlaying(true);
    final notifier = ValueNotifier(feed.likeStateOf(0));
    await mount(t, a, MovaDouyinGestureLayerComponent(controller: feed, index: 0, likeNotifier: notifier));
    final center = t.getCenter(find.byType(MovaScope));
    await t.tapAt(center); await d.drain(t, 350);
    d.measured('U6.douyin.tap', k.calls.where((v) => v == 'pause').length, 1);
    await t.tapAt(center); await t.pump(const Duration(milliseconds: 60)); await t.tapAt(center); await t.pump();
    d.measured('U6.douyin.double', [notifier.value.liked, notifier.value.count, likes,
      find.byIcon(Icons.favorite_rounded).evaluate().length], [true, 6, 1, 1]);
    final before = List<String>.of(k.calls);
    await t.dragFrom(center, const Offset(100, 0)); await t.dragFrom(center, const Offset(0, -80));
    await t.pump();
    d.measured('U6.douyin.drag', k.calls, before);
    await mount(t, a, MovaLikeButtonComponent(controller: feed, index: 0, likeNotifier: notifier));
    d.measured('U7.like.render', texts(t), ['6']);
    await t.tap(find.byIcon(Icons.favorite_rounded)); await t.pump();
    d.measured('U7.like.click', [notifier.value.liked, notifier.value.count, likes], [false, 5, 2]);
    await mount(t, a, MovaCommentButtonComponent(item: item));
    d.measured('U7.comment.render', texts(t), ['42']);
    await t.tap(find.byIcon(Icons.chat_bubble_rounded));
    await mount(t, a, MovaShareButtonComponent(item: item));
    d.measured('U7.share.render', texts(t), ['7']);
    await t.tap(find.byIcon(Icons.reply_rounded));
    await mount(t, a, MovaAvatarComponent(item: item));
    await t.tap(find.byIcon(Icons.person_rounded)); await t.tap(find.byIcon(Icons.add_circle_rounded));
    d.measured('U7.social.clicks', [comments, shares, avatars, follows], [1, 1, 1, 1]);
    await mount(t, a, MovaFeedInfoComponent(item: item));
    d.measured('U7.info', texts(t), ['@S00E']);
    await d.unmount(t); notifier.dispose(); feed.dispose(); await t.runAsync(pool.dispose); await d.dispose(t, a); await t.pump(const Duration(seconds: 1));
  });

  testWidgets('subtitle cues render and expire via the engine progress stream', (t) async {
    final cues = Cues();
    final a = await d.make(t, options: MovaOpts(stt: MovaSttConfig(enabled: true, engine: cues)));
    final k = MovaTesting.lastKernel!;
    await a.open(const MovaSource('s00e://subtitle'));
    await mount(t, a, MovaSubtitleOverlayComponent());
    d.measured('U7.subtitle.empty', texts(t), <String>[]);
    cues.output.add(const MovaSttCue(text: 'S00E 字幕', start: Duration.zero, end: Duration(seconds: 2)));
    await d.drain(t);
    d.measured('U7.subtitle.cue', texts(t), ['S00E 字幕']);
    k.emitPosition(const Duration(seconds: 5)); await d.drain(t, 250);
    d.measured('U7.subtitle.expired', texts(t), <String>[]);
    await mount(t, a, MovaSubtitleButtonComponent());
    await t.tap(find.byIcon(Icons.subtitles_off_rounded)); await t.pumpAndSettle();
    await t.tap(find.text('zh')); await t.pumpAndSettle();
    d.measured('U7.subtitle.start', [a.stt.isRunning, find.byIcon(Icons.subtitles_rounded).evaluate().length], [true, 1]);
    await t.tap(find.byIcon(Icons.subtitles_rounded)); await t.pumpAndSettle();
    await t.tap(find.text(a.options.strings.subtitleOff)); await t.pumpAndSettle();
    d.measured('U7.subtitle.stop', [a.stt.isRunning, find.byIcon(Icons.subtitles_off_rounded).evaluate().length], [false, 1]);
    await d.unmount(t); await d.dispose(t, a);
  });

  testWidgets('ad countdown uses media position then click skip returns content', (t) async {
    final events = <MovaAdEvent>[];
    final a = await d.make(t, options: MovaOpts(ads: MovaAdConfig(enabled: true,
      onAdEvent: events.add, breaks: const [MovaAdBreak(kind: MovaAdBreakKind.pre,
        source: MovaSource('s00e://ad'), skippableAfter: Duration(seconds: 5),
        clickThroughUrl: 'https://s00e.invalid/click')])));
    final k = MovaTesting.lastKernel!;
    final ads = MovaAds(a);
    await ads.load(const MovaSource('s00e://content'));
    await mount(t, a, MovaAdOverlayComponent(ads));
    d.measured('U7.ad.countdown', texts(t), ['广告', '5']);
    k.emitPosition(const Duration(seconds: 2)); await d.drain(t, 250);
    d.measured('U7.ad.remaining', texts(t), ['广告', '3']);
    await t.tapAt(t.getCenter(find.byType(MovaScope))); await d.drain(t);
    d.measured('U7.ad.click', events.where((v) => v.type == MovaAdEventType.clicked)
      .map((v) => v.adBreak.clickThroughUrl).toList(), ['https://s00e.invalid/click']);
    k.emitPosition(const Duration(seconds: 6)); await d.drain(t, 250);
    d.measured('U7.ad.skippable', texts(t), ['广告', a.options.strings.skipAd]);
    await t.tap(find.text(a.options.strings.skipAd)); await d.drain(t);
    d.measured('U7.ad.skipped', [ads.isShowingAd, k.lastUri, texts(t)], [false, 's00e://content', <String>[]]);
    await d.unmount(t); await t.runAsync(ads.dispose); await d.dispose(t, a);
  });

  testWidgets('live bottom bar distinguishes nonseekable and DVR edge and behind', (t) async {
    for (final dvr in [false, true]) {
      final a = await d.make(t, options: MovaOpts(live: MovaLiveConfig(
        seekMode: dvr ? MovaLiveSeekMode.dvr : MovaLiveSeekMode.off,
        dvrWindow: const Duration(seconds: 300))));
      final k = MovaTesting.lastKernel!;
      await a.open(const MovaSource('s00e://live', type: MovaStreamType.live));
      k.emitDuration(const Duration(seconds: 300)); k.emitPosition(const Duration(seconds: 300));
      await mount(t, a, MovaBottomBarComponent());
      d.measured('U4.live.$dvr.edge', [find.text(a.options.strings.live).evaluate().length,
        find.byType(Slider).evaluate().length], [1, dvr ? 1 : 0]);
      if (dvr) {
        d.measured('U4.live.span', t.widget<Slider>(find.byType(Slider)).max, 300000.0);
        await a.seek(const Duration(seconds: 235)); k.emitPosition(const Duration(seconds: 235));
        await d.drain(t, 250);
        d.measured('U4.live.behind', [find.text(a.options.strings.timeshift).evaluate().length,
          find.text('-01:05').evaluate().length], [1, 1]);
        await t.tap(find.byIcon(Icons.sync_rounded)); await d.drain(t);
        d.measured('U4.live.back', k.lastSeek?.inMilliseconds, 300000);
      }
      await d.unmount(t); await d.dispose(t, a);
    }
  });

  testWidgets('preview bubble has real placeholder geometry and timestamp; clears on release', (t) async {
    final a = await d.make(t);
    await a.open(const MovaSource('s00e://preview')); MovaTesting.lastKernel!.emitDuration(const Duration(seconds: 100));
    await mount(t, a, MovaPreviewComponent());
    a.setDragging(true, previewAt: const Duration(seconds: 25)); await d.drain(t);
    final holder = find.byKey(const ValueKey('movaPrevHolder'));
    final size = t.getSize(holder);
    d.measured('U4.preview.render', [find.text('00:25').evaluate().length, size.width, size.height],
      [1, a.options.preview.frameWidth.toDouble(), a.options.preview.frameWidth * 9 / 16]);
    a.setDragging(false); await d.drain(t);
    d.measured('U4.preview.release', [holder.evaluate().length, find.byType(Text).evaluate().length], [0, 0]);
    await d.unmount(t); await d.dispose(t, a);
  });

  testWidgets('position label keeps first and final values across throttle window', (t) async {
    // Construct and subscribe in the widget test zone so Timer dispatch is
    // deterministic. Clock advancement schedules events, it is not evidence.
    final a = createMovaEngine(); final k = MovaTesting.lastKernel!;
    await a.open(const MovaSource('s00e://throttle'));
    await mount(t, a, MovaPositionLabelComponent());
    k.emitPosition(const Duration(seconds: 11)); await t.pump(); await t.pump();
    final first = texts(t);
    k.emitPosition(const Duration(seconds: 12)); k.emitPosition(const Duration(seconds: 13));
    await t.pump(); await t.pump(const Duration(milliseconds: 100));
    final pending = texts(t);
    await t.pump(const Duration(milliseconds: 101)); await t.pump();
    d.measured('U4.throttle.window', [first, pending, texts(t)], [['00:11'], ['00:11'], ['00:13']]);
    await t.pumpWidget(const SizedBox());
    var disposed = false; unawaited(a.dispose().then((_) => disposed = true));
    await d.drain(t, 1000);
    expect(disposed, true);
  });

  testWidgets('preview decodes real PNG bytes into RenderImage', (t) async {
    final cache = MovaMemoryThumbCache();
    // Existing 1x1 transparent PNG fixture, decoded by Flutter's real codec.
    final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==');
    await cache.write('s00e', bytes);
    final a = await d.make(t, options: MovaOpts(preview: MovaPreviewConfig(cache: cache,
      cacheKeyBuilder: (_, _, _) => 's00e', sources: const [], debounce: Duration.zero)));
    await a.open(const MovaSource('s00e://real-preview'));
    await mount(t, a, MovaPreviewComponent());
    a.setDragging(true, previewAt: const Duration(seconds: 25)); await d.drain(t);
    await t.runAsync(() async {
      final image = t.widget<Image>(find.byType(Image));
      await precacheImage(image.image, t.element(find.byType(Image)));
    });
    await d.drain(t);
    final raw = t.widget<RawImage>(find.byType(RawImage));
    d.measured('U4.preview.image', [raw.image?.width, raw.image?.height,
      find.text('00:25').evaluate().length, t.getSize(find.byType(Image)).width], [1, 1, 1, 160.0]);
    a.setDragging(false); await d.drain(t);
    d.measured('U4.preview.imageReleased', find.byType(RawImage).evaluate().length, 0);
    await d.unmount(t); await d.dispose(t, a);
  });

  testWidgets('DVR gestures obey allowWhenLive across seek axes and double tap', (t) async {
    for (final allowed in [false, true]) {
      final a = await d.make(t, options: MovaOpts(live: const MovaLiveConfig(
        seekMode: MovaLiveSeekMode.dvr, dvrWindow: Duration(seconds: 300)),
        gesture: MovaGestureConfig(allowWhenLive: allowed)));
      final k = MovaTesting.lastKernel!;
      await a.open(const MovaSource('s00e://dvr', type: MovaStreamType.live));
      k.emitDuration(const Duration(seconds: 300)); k.emitPosition(const Duration(seconds: 100));
      await mount(t, a, MovaGestureLayerComponent());
      final center = t.getCenter(find.byType(MovaScope));
      await t.tapAt(center + const Offset(100, 0)); await t.pump(const Duration(milliseconds: 60));
      await t.tapAt(center + const Offset(100, 0)); await d.drain(t);
      final doubled = k.calls.where((v) => v == 'seek').length;
      await t.dragFrom(center - const Offset(100, 0), const Offset(100, 0)); await d.drain(t);
      d.measured('U6.dvr.$allowed', [doubled, k.calls.where((v) => v == 'seek').length], allowed ? [1, 2] : [0, 0]);
      await d.unmount(t); await d.dispose(t, a); await t.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('guard combines route ticker inactive intent and PiP/mini exemptions', (t) async {
    for (final exemption in ['none', 'pip', 'mini']) {
      final a = await d.make(t, pip: d.SupportedPip()); final k = MovaTesting.lastKernel!;
      await a.open(const MovaSource('s00e://guard')); await a.play(); k.emitPlaying(true);
      if (exemption == 'pip') { await a.enterPip(); }
      if (exemption == 'mini') { await a.setMini(true); }
      final ticker = ValueNotifier(true); final nav = GlobalKey<NavigatorState>();
      final observer = RouteObserver<ModalRoute<dynamic>>();
      final reasons = <List<String>>[];
      await t.pumpWidget(MaterialApp(navigatorKey: nav, navigatorObservers: [observer],
        home: Scaffold(body: ValueListenableBuilder<bool>(valueListenable: ticker,
          builder: (_, on, child) => TickerMode(enabled: on, child: child!),
          child: MovaAutoPause(api: a, routeObservers: [observer],
            onChanged: (v) => reasons.add(v.map((v) => v.name).toList()..sort()),
            child: const SizedBox(width: 400, height: 240))))));
      await d.drain(t); k.calls.clear();
      ticker.value = false; await d.drain(t);
      final hiddenCalls = List<String>.of(k.calls);
      ticker.value = true; await d.drain(t);
      d.measured('U9.ticker.$exemption', [hiddenCalls.where((v) => v == 'pause').length,
        k.calls.where((v) => v == 'play').length], exemption == 'none' ? [1, 1] : [0, 0],
        numbers: {'reasons': List.of(reasons), 'pip': a.state.pip, 'mini': a.state.mini});
      k.calls.clear(); k.emitPlaying(true); await d.drain(t);
      nav.currentState!.push(PageRouteBuilder<void>(opaque: false,
        pageBuilder: (_, _, _) => const SizedBox.expand()));
      await t.pumpAndSettle();
      final covered = List<String>.of(k.calls);
      nav.currentState!.pop(); await t.pumpAndSettle();
      d.measured('U9.route.$exemption', [covered.where((v) => v == 'pause').length,
        k.calls.where((v) => v == 'play').length], exemption == 'none' ? [1, 1] : [0, 0],
        numbers: {'reasons': List.of(reasons)});
      k.calls.clear(); k.emitPlaying(true); await d.drain(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      k.emitPlaying(false); await d.drain(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await d.drain(t);
      d.measured('U9.inactive.$exemption', k.calls.where((v) => v == 'play').length,
        exemption == 'none' ? 1 : 0, numbers: {'calls': List.of(k.calls), 'reasons': reasons});
      await d.unmount(t); ticker.dispose(); await a.setMini(false); await d.dispose(t, a);
    }
  });
}

