import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import '../main_coverage_api.dart' as c;
import 's00d_native.dart' as n;
import 's00e_trace.dart';
import 's00d_resources.dart' show DisposeFrames;

final pending = <String, Completer<Map<String, Object?>>>{};
int sequence = 0;
void acknowledge(String token, String? sample) {
  final waiter = pending[token];
  if (waiter == null || waiter.isCompleted || sample == null) return;
  waiter.complete(Map<String, Object?>.from(jsonDecode(sample) as Map));
}

Future<Map<String, Object?>> host(String phase) async {
  final token = '$phase-${sequence++}';
  final waiter = Completer<Map<String, Object?>>(); pending[token] = waiter;
  c.mark('S00E_HOST_REQUEST', {'token': token, 'phase': phase});
  try { return await waiter.future.timeout(const Duration(seconds: 30)); }
  on TimeoutException { return {}; }
  finally { pending.remove(token); }
}

void check(String id, Map<String, Object?> numbers, bool? pass) =>
    c.mark('CHECK', {'id': id, 'origin': 's00e-native', 'numbers': numbers, 'pass': pass});

Future<void> drag(Offset start, Offset delta) async {
  final id = sequence++ + 30000;
  final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
  GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: id, position: start, viewId: view.viewId));
  var previous = start;
  for (var i = 1; i <= 8; i++) {
    final position = start + delta * (i / 8);
    GestureBinding.instance.handlePointerEvent(PointerMoveEvent(pointer: id,
      position: position, delta: position - previous, viewId: view.viewId));
    previous = position;
    await WidgetsBinding.instance.endOfFrame;
  }
  GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: id, position: previous, viewId: view.viewId));
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> locks() async {
  final a = createMovaEngine();
  try {
    await n.mount(a); await a.open(c.source()); await c.until(() => a.state.rendered);
    final player = n.elements((w) => w is MovaPlayer).single.findRenderObject() as RenderBox;
    for (final locked in [false, true, false]) {
      await a.setLocked(locked); await a.setVolume(30); await a.setBrightness(.3);
      await WidgetsBinding.instance.endOfFrame;
      final before = await host('lock-$locked-before');
      await drag(player.localToGlobal(Offset(player.size.width * .2, player.size.height * .7)),
        Offset(0, -player.size.height * .3));
      await drag(player.localToGlobal(Offset(player.size.width * .8, player.size.height * .7)),
        Offset(0, -player.size.height * .3));
      final after = await host('lock-$locked-after');
      final known = ['brightness', 'appBrightness', 'volume'].every((k) => before[k] is num && after[k] is num);
      check('A13.native.$locked', {'before': before, 'after': after, 'locked': a.state.locked},
        !known ? null : locked
          ? before['brightness'] == after['brightness'] && before['appBrightness'] == after['appBrightness'] && before['volume'] == after['volume']
          : before['brightness'] == after['brightness'] && (after['appBrightness'] as num) > (before['appBrightness'] as num) && (after['volume'] as num) > (before['volume'] as num));
    }
  } finally { await n.release(a); }
}

Future<void> lateFiles() async {
  final a = createMovaEngine(preciseFirstFrame: true);
  final events = <MovaEvent>[];
  final sub = a.events.listen(events.add);
  try {
    final native = await n.mount(a);
    for (var iteration = 0; iteration < 12; iteration++) {
      final old = c.source('s00e-missing-$iteration.mp4');
      // First establish a real old-file failure. An immediate second open
      // before the old request reached mpv would be a vacuous isolation test.
      final oldStart = events.length;
      try { await a.open(old); } on Object { /* Retain events below. */ }
      await c.until(() => events.skip(oldStart).whereType<MovaErrorEvent>().isNotEmpty ||
        events.skip(oldStart).whereType<MovaPlayFailure>().isNotEmpty);
      final oldFailures = events.skip(oldStart).where((e) => e is MovaErrorEvent || e is MovaPlayFailure).length;
      final boundary = events.length;
      final fresh = c.source();
      final accepted = await a.open(fresh);
      await c.until(() => a.state.rendered && a.state.playing);
      final positions = <String>[];
      final states = <Map<String, Object?>>[];
      for (var i = 0; i < 10; i++) {
        positions.add(await native.getProperty('time-pos'));
        states.add({'error': a.state.error?.toString(), 'playing': a.state.playing,
          'epoch': a.state.renderEpoch, 'path': await native.getProperty('path')});
        await WidgetsBinding.instance.endOfFrame;
      }
      final failures = events.skip(boundary).whereType<MovaPlayFailure>().map((e) => e.fail.kind.name).toList();
      check('N12.native.isolation', {'iteration': iteration, 'oldUri': old.uri, 'freshUri': fresh.uri,
        'accepted': accepted, 'oldFailures': oldFailures, 'paths': states.map((s) => s['path']).toList(),
        'errors': states.map((s) => s['error']).toList(), 'playing': states.map((s) => s['playing']).toList(),
        'failures': failures, 'positions': positions, 'sampleCount': states.length},
        accepted && states.every((s) => s['error'] == null && s['playing'] == true && s['path'] == fresh.uri) && failures.isEmpty);
    }
  } finally { await sub.cancel(); await n.release(a); }
}

Future<void> lazyVideo() async {
  for (final audio in [true, false]) {
    final start = videoCalls.length;
    final a = createMovaEngine(audioOnly: audio);
    // Never read renderHandle before this snapshot: reading it is the
    // attachment request and would invalidate the lazy-allocation experiment.
    await a.open(c.source(), autoPlay: false);
    final beforeMount = videoCalls.skip(start).where((r) => r['method'] == 'VideoOutputManager.Create').length;
    c.screen.value = a; await WidgetsBinding.instance.endOfFrame; await WidgetsBinding.instance.endOfFrame;
    if (!audio) { await c.until(() => videoCalls.skip(start).any((r) => r['replied'] == true)); }
    final mounted = videoCalls.skip(start).where((r) => r['method'] == 'VideoOutputManager.Create').length;
    await n.release(a);
    final calls = videoCalls.skip(start).toList();
    final released = calls.where((r) => r['method'] == 'VideoOutputManager.Dispose' && r['replied'] == true).length;
    check('N13.video.$audio', {'beforeMount': beforeMount, 'mounted': mounted, 'released': released,
      'calls': calls, 'binding': WidgetsBinding.instance.runtimeType.toString()},
      WidgetsBinding.instance is! S00eBinding ? null : beforeMount == 0 && mounted == (audio ? 0 : 1) && released == mounted);
  }
}

Future<void> seekTrace() async {
  final a = createMovaEngine(preciseFirstFrame: true);
  final logs = <Map<String, Object?>>[];
  StreamSubscription<PlayerLog>? sub;
  try {
    final native = await n.mount(a);
    final video = a.renderHandle as VideoController;
    sub = video.player.stream.log.listen((v) => logs.add({'prefix': v.prefix, 'level': v.level, 'text': v.text}));
    // The media_kit subscription may filter trace messages. In that case
    // commandTrace stays empty and this CHECK deliberately remains BLOCKED.
    await native.setProperty('msg-level', 'all=trace');
    await a.open(c.source('master.m3u8'), autoPlay: false);
    await c.until(() => a.state.rendered);
    logs.clear();
    final samples = <Map<String, Object?>>[];
    await a.seek(const Duration(seconds: 12));
    for (var i = 0; i < 120; i++) {
      samples.add({'seeking': await native.getProperty('seeking'), 'position': await native.getProperty('time-pos')});
      await WidgetsBinding.instance.endOfFrame;
    }
    final trace = logs.where((r) => RegExp(r'Run command: seek\b').hasMatch('${r['text']}')).toList();
    final positions = samples.map((s) => double.tryParse('${s['position']}')).toList();
    check('A7.native.trace', {'commandTrace': trace, 'callCount': trace.length, 'samples': samples,
      'finalPosition': positions.last, 'target': 12, 'maxCalls': 3}, trace.isEmpty || positions.last == null
        ? null : trace.length <= 3 && (positions.last! - 12).abs() <= .5);
  } finally { await sub?.cancel(); await n.release(a); }
}

Future<void> run() async {
  for (final work in [locks, ownership, nativeLifecycle, boundedPool, nativeIsolation, lateFiles, lazyVideo, seekTrace]) {
    try { await work(); }
    on Object catch (error, stack) { c.mark('S00E_SCRIPT_ERROR', {'error': '$error', 'stack': '$stack'}); }
  }
  c.mark('S00E_PLATFORM', {'platform': Platform.operatingSystem});
}

Future<void> show(Widget? widget) async {
  c.probeTree.value = widget;
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
}

Map<String, Object?> textureReceipt(int start) {
  final calls = videoCalls.skip(start).map((v) => Map<String, Object?>.of(v)).toList();
  return {'calls': calls, 'created': calls.where((r) => r['method'] == 'VideoOutputManager.Create' && r['replied'] == true).length,
    'released': calls.where((r) => r['method'] == 'VideoOutputManager.Dispose' && r['replied'] == true).length,
    'textureIds': n.elements((w) => w is Texture).map((e) => (e.widget as Texture).textureId).toList(),
    'binding': WidgetsBinding.instance.runtimeType.toString()};
}

Future<void> ownership() async {
  c.screen.value = null; c.widgetMode.value = false;
  final borrowed = createMovaEngine();
  var start = videoCalls.length;
  try {
    await show(MovaPlayer(api: borrowed, surface: const Center(child: Text('S00E custom surface'))));
    await borrowed.open(c.source());
    check('U1.native.surface', {...textureReceipt(start),
      'customLabels': n.elements((w) => w is Text && w.data == 'S00E custom surface').length},
      n.elements((w) => w is Text && w.data == 'S00E custom surface').length == 1);
    await show(MovaPlayer(api: borrowed));
    await c.until(() => borrowed.state.rendered && n.elements((w) => w is Texture).isNotEmpty);
    final mounted = textureReceipt(start);
    check('U1.native.player.mounted', mounted, mounted['created'] == 1 && mounted['released'] == 0 && (mounted['textureIds'] as List).isNotEmpty);
    await show(null);
    final accepted = await borrowed.open(c.source(), autoPlay: false);
    check('U1.native.borrowed', {...textureReceipt(start), 'acceptedAfterUnmount': accepted}, accepted);
  } finally {
    await show(null); await borrowed.dispose();
    final disposed = textureReceipt(start);
    check('U1.native.player.disposed', disposed, disposed['created'] == 1 && disposed['released'] == 1 && (disposed['textureIds'] as List).isEmpty);
  }

  start = videoCalls.length;
  final sources = ValueNotifier<MovaSource?>(null);
  final ticker = ValueNotifier(true);
  final created = <MovaApi>[];
  final routeObserver = RouteObserver<ModalRoute<dynamic>>();
  final nav = GlobalKey<NavigatorState>();
  final view = ValueListenableBuilder<bool>(valueListenable: ticker, builder: (_, enabled, child) => TickerMode(enabled: enabled, child: child!),
    child: ValueListenableBuilder<MovaSource?>(valueListenable: sources, builder: (_, src, _) => MovaView(
      source: src, onEngine: created.add, autoPause: const MovaAutoPauseConfig(), routeObservers: [routeObserver])));
  try {
    await show(Navigator(key: nav, observers: [routeObserver], onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => view)));
    check('U1.native.view.lazy', {'engines': created.length, ...textureReceipt(start)}, created.isEmpty);
    final one = c.source(); sources.value = one;
    await c.until(() => created.isNotEmpty && created.last.state.rendered);
    final a = created.single;
    final native = ((a.renderHandle as VideoController).player.platform as NativePlayer);
    final texture = textureReceipt(start);
    final two = c.source('ad.mp4'); sources.value = two;
    await c.until(() => a.state.rendered && a.state.sourceTitle == two.title);
    check('U1.native.view.source', {'engines': created.length, 'path': await native.getProperty('path'),
      'expectedPath': two.uri, 'before': texture, 'after': textureReceipt(start)}, created.length == 1);
    ticker.value = false; await c.until(() => !a.state.playing);
    final paused = a.state.playing;
    ticker.value = true; await c.until(() => a.state.playing);
    check('U9.native.ticker', {'hiddenPlaying': paused, 'visiblePlaying': a.state.playing,
      'path': await native.getProperty('path'), 'expectedPath': two.uri}, !paused && a.state.playing);
    unawaited(nav.currentState!.push(PageRouteBuilder<void>(opaque: false, pageBuilder: (_, _, _) => const SizedBox.expand())));
    await c.until(() => !a.state.playing);
    final routePaused = a.state.playing;
    nav.currentState!.pop(); await c.until(() => a.state.playing);
    check('U9.native.route', {'hiddenPlaying': routePaused, 'visiblePlaying': a.state.playing,
      'path': await native.getProperty('path'), 'expectedPath': two.uri}, !routePaused && a.state.playing);
    await show(null);
    await c.until(() => videoCalls.skip(start).any((r) => r['method'] == 'VideoOutputManager.Dispose' && r['replied'] == true));
    final accepts = await a.open(one);
    check('U1.native.view.disposed', {...textureReceipt(start), 'acceptedAfterUnmount': accepts}, !accepts);
  } finally { await show(null); for (final a in created) { await a.dispose(); } sources.dispose(); ticker.dispose(); }

  start = videoCalls.length;
  final feedEngines = <MovaApi>[];
  try {
    await show(MovaFeedPlayer(poolSize: 1, prefetchDepth: 0,
      engineFactory: () { final a = createMovaEngine(); feedEngines.add(a); return a; },
      loader: (i) async => i < 0 || i > 4 ? null : MovaFeedItem(source: MovaSource(c.source().uri, title: 'S00E feed $i'))));
    await c.until(() => feedEngines.isNotEmpty && feedEngines.single.state.rendered);
    final first = textureReceipt(start);
    final page = n.elements((w) => w is PageView).single.widget as PageView;
    page.controller!.jumpToPage(2);
    await c.until(() => feedEngines.single.state.sourceTitle == 'S00E feed 2' && feedEngines.single.state.rendered);
    final mounted = textureReceipt(start);
    await show(null);
    await c.until(() => videoCalls.skip(start).any((r) => r['method'] == 'VideoOutputManager.Dispose' && r['replied'] == true));
    final accepts = <bool>[]; for (final a in feedEngines) { accepts.add(await a.open(c.source())); }
    check('U1.native.feed', {'engines': feedEngines.length, 'first': first, 'mounted': mounted,
      'disposed': textureReceipt(start), 'accepts': accepts}, feedEngines.length == 1 && accepts.every((v) => !v));
  } finally { await show(null); for (final a in feedEngines) { await a.dispose(); } }
}

Future<void> boundedPool() async {
  final baseline = await host('pool-baseline');
  final made = <MovaApi>[];
  final pool = MovaFeedEnginePool(size: 3, engineFactory: () { final a = createMovaEngine(audioOnly: true); made.add(a); return a; });
  final feed = MovaFeed(pool: pool, loader: (i) async => MovaFeedItem(source: c.source('vod.mp4?pool=$i')));
  Map<String, Object?>? warm;
  try {
    for (var i = 0; i <= 100; i++) {
      await feed.activate(i);
      if (i == 20) { warm = await host('pool-warm'); }
      if (i >= 40 && i % 20 == 0) {
        final after = await host('pool-$i');
        bounded('F13.bounded.$i', warm ?? {}, after, created: made.length, engines: pool.engineCount);
      }
    }
  } finally {
    feed.dispose(); await DisposeFrames().run(pool.dispose);
    final after = await host('pool-disposed');
    bounded('F13.bounded.disposed', baseline, after, created: made.length, engines: pool.engineCount, disposed: true);
  }
}

void bounded(String id, Map<String, Object?> before, Map<String, Object?> after,
    {required int created, required int engines, bool disposed = false}) {
  // Explicit fixed acceptance budgets, measured from the warmed 3-engine pool
  // (or clean process for disposal). They are limits, never measured values.
  final budget = {'rss': disposed ? 67108864 : 33554432, 'threads': disposed ? 4 : 2, 'handles': disposed ? 16 : 8};
  final ceilings = <String, num?>{for (final k in budget.keys) k: before[k] is num ? (before[k] as num) + budget[k]! : null};
  final known = budget.keys.every((k) => before[k] is num && after[k] is num);
  check(id, {'before': before, 'after': after, 'budget': budget, 'ceilings': ceilings,
    'created': created, 'engines': engines}, !known ? null : created <= 3 && engines <= (disposed ? 0 : 3) && budget.keys.every((k) => (after[k] as num) <= ceilings[k]!));
}

Future<void> nativeLifecycle() async {
  for (final exemption in ['none', 'pip', 'mini']) {
    final a = createMovaEngine();
    final positions = <int>[];
    final sub = a.progress.listen((v) => positions.add(v.position.inMilliseconds));
    try {
      await show(MovaAutoPause(api: a, child: MovaPlayer(api: a)));
      await a.open(c.source('live.flv?gop=50&audio=1'));
      await c.until(() => a.state.rendered && a.state.playing);
      final native = (a.renderHandle as VideoController).player.platform as NativePlayer;
      bool? supported;
      if (exemption == 'pip') { supported = await a.enterPip(); }
      if (exemption == 'mini') { await c.mini.show(a); }
      final miniVisible = c.mini.isShowing(a);
      final background = await host('guard-$exemption-background');
      if (exemption == 'none') { await c.until(() => !a.state.playing); }
      else {
        positions.clear(); await c.until(() => positions.length >= 6);
      }
      final hidden = {'playing': a.state.playing, 'intent': a.state.playbackIntent,
        'pip': a.state.pip, 'mini': a.state.mini, 'pause': await native.getProperty('pause'),
        'positions': List.of(positions)};
      await host('guard-$exemption-foreground');
      await c.until(() => a.state.playing);
      check('U9.native.lifecycle.$exemption', {'background': background, 'hidden': hidden,
        'visiblePlaying': a.state.playing, 'miniVisible': miniVisible, 'pipAccepted': supported},
        exemption == 'pip' && (supported != true || background['pinned'] == null) ? null :
        hidden['playing'] == (exemption != 'none') && a.state.playing);
    } finally {
      await host('guard-$exemption-foreground');
      await c.mini.hide(); await a.setMini(false); await sub.cancel(); await show(null); await a.dispose();
    }
  }
}

Future<void> nativeIsolation() async {
  final engines = [for (var i = 0; i < 3; i++) createMovaEngine(preciseFirstFrame: true)];
  final events = [for (var i = 0; i < 3; i++) <MovaEvent>[]];
  final subs = [for (var i = 0; i < 3; i++) engines[i].events.listen(events[i].add)];
  final start = videoCalls.length;
  final native = <NativePlayer>[];
  try {
    await show(Row(children: [for (final a in engines) Expanded(child: MovaPlayer(api: a))]));
    for (final a in engines) {
      await a.open(c.source('live.flv?gop=50&audio=1'));
      await c.until(() => a.state.rendered);
      native.add((a.renderHandle as VideoController).player.platform as NativePlayer);
    }
    final before = [for (final n0 in native) await n.clients(n0)];
    final first = [for (final n0 in native) double.tryParse(await n0.getProperty('time-pos'))];
    final boundary = [for (final rows in events) rows.length];
    try { await engines.first.open(c.source('s00e-native-isolation-404.mp4')); } on Object { /* actual failure retained */ }
    await c.until(() => events.first.skip(boundary.first).any((e) => e is MovaErrorEvent || e is MovaPlayFailure));
    final after = [for (final n0 in native) double.tryParse(await n0.getProperty('time-pos'))];
    final errors = [for (var i = 1; i < 3; i++) events[i].skip(boundary[i]).where((e) => e is MovaErrorEvent || e is MovaPlayFailure).length];
    check('F13.native.isolation', {'clients': before, 'first': first, 'after': after,
      'failedEvents': events.first.skip(boundary.first).where((e) => e is MovaErrorEvent || e is MovaPlayFailure).length,
      'healthyErrors': errors, 'healthyPlaying': engines.skip(1).map((a) => a.state.playing).toList()},
      errors.every((v) => v == 0) && engines.skip(1).every((a) => a.state.playing));
  } finally {
    await show(null);
    for (final a in engines) { await a.dispose(); }
    for (final sub in subs) { await sub.cancel(); }
    final receipt = textureReceipt(start);
    final accepts = [for (final a in engines) await a.open(c.source())];
    check('F14.native.teardown', {...receipt, 'accepts': accepts},
      receipt['created'] == 3 && receipt['released'] == 3 && accepts.every((v) => !v));
  }
}
