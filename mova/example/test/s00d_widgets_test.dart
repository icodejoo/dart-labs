// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderAnimatedOpacity;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';

void measured(
  String id,
  Object? actual,
  Object? expected, {
  Map<String, Object?>? numbers,
}) {
  final pass = jsonEncode(actual) == jsonEncode(expected);
  print(
    'MATRIX_RECORD ${jsonEncode({'kind': 'CHECK', 'id': id, 'pass': pass, 'origin': 'public-widget-tree', 'expected': expected, 'actual': actual, 'numbers': numbers})}',
  );
  expect(actual, expected, reason: id);
}

Future<void> drain(WidgetTester t, [int ms = 0]) async {
  await t.pump(Duration(milliseconds: ms));
  // Kernel controllers live outside fake async; widgets live inside it.
  // Drain both queues, including sequential public disposal awaits.
  for (var i = 0; i < 40; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump();
  }
}

Future<Mova> make(
  WidgetTester t, {
  MovaOpts options = const MovaOpts(),
  IMovaPip? pip,
  IMovaHttpFetch? fetcher,
}) async => (await t.runAsync(
  () async => createMova(options: options, pip: pip, fetcher: fetcher),
))!;
Future<void> component(WidgetTester t, IMovaApi a, MovaComponent c) async {
  await t.pumpWidget(
    MaterialApp(
      key: ValueKey('${identityHashCode(a)}:${c.name}'),
      home: Scaffold(
        body: MovaScope(
          api: a,
          child: SizedBox(
            width: 400,
            height: 240,
            child: Builder(builder: (context) => c.build(context, a, [])),
          ),
        ),
      ),
    ),
  );
  await drain(t);
}

Future<void> unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await drain(t);
}

Future<void> dispose(WidgetTester t, IMovaApi a) async {
  await t.runAsync(a.dispose);
}

class SupportedPip implements IMovaPip {
  int enters = 0;
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<bool> enter({int? width, int? height}) async {
    enters++;
    return true;
  }
}

class MasterFetch implements IMovaHttpFetch {
  @override
  Future<Uint8List?> get(Uri url) async => Uint8List.fromList(
    utf8.encode(
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=640x360\nlow.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720\nhigh.m3u8\n'
          .replaceAll(r'\n', '\n'),
    ),
  );
  @override
  Future<void> close() async {}
}

void main() {
  setUp(MovaTesting.useTestKernels);
  tearDown(MovaTesting.reset);
  // Only coverage_s00d_offline.py may publish a completed evidence artifact;
  // tearDownAll also runs after failed tests and must not emit DONE.

  testWidgets('controls: startup, reset, sticky, off and explicit hide', (
    t,
  ) async {
    for (final auto in [true, false]) {
      for (final start in [true, false]) {
        final a = await make(
          t,
          options: MovaOpts(
            controls: MovaCtrlsOpts(
              autoHide: auto,
              showOnStart: start,
              autoHideDelay: const Duration(milliseconds: 100),
              fadeDuration: const Duration(milliseconds: 140),
            ),
          ),
        );
        await t.pumpWidget(MaterialApp(home: MovaPlayer(api: a)));
        await a.open(const MovaSource('s00d://controls'));
        await drain(t);
        measured('C5.start.$auto.$start', a.uiState.controlsVisible, start);
        a.showControls();
        await drain(t, 60);
        a.showControls();
        await drain(t, 60);
        measured('C5.reset.$auto.$start', a.uiState.controlsVisible, true);
        await drain(t, 60);
        measured('C5.auto.$auto.$start', a.uiState.controlsVisible, !auto);
        a.showControls(sticky: true);
        await drain(t, 200);
        measured('C5.sticky.$auto.$start', a.uiState.controlsVisible, true);
        a.hideControls();
        await drain(t, 200);
        measured('C5.hide.$auto.$start', a.uiState.controlsVisible, false);
        final fades = t
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .toList();
        measured(
          'C5.paint.$auto.$start',
          fades.isNotEmpty &&
              fades.every(
                (w) => w.opacity == 0 && w.duration.inMilliseconds == 140,
              ),
          true,
          numbers: {
            'durations': fades.map((w) => w.duration.inMilliseconds).toList(),
            'opacities': fades.map((w) => w.opacity).toList(),
          },
        );
        await unmount(t);

        await dispose(t, a);
      }
    }
    const d = MovaCtrlsOpts();
    measured(
      'C5.defaults',
      [
        d.autoHide,
        d.showOnStart,
        d.autoHideDelay.inMilliseconds,
        d.fadeDuration.inMilliseconds,
        d == const MovaCtrlsOpts(),
      ],
      [true, true, 3000, 200, true],
    );
  });

  testWidgets('danmaku: disabled, tracks, moving, unique, retirement', (
    t,
  ) async {
    for (final enabled in [false, true]) {
      final a = await make(
        t,
        options: MovaOpts(
          danmaku: MovaDanmakuOpts(
            enabled: enabled,
            trackCount: 2,
            crossDuration: const Duration(seconds: 2),
            items: const [
              MovaDanmakuItem(
                text: 'S00D bullet A',
                time: Duration(seconds: 1),
              ),
              MovaDanmakuItem(
                text: 'S00D bullet B',
                time: Duration(seconds: 1),
              ),
            ],
          ),
        ),
      );
      final k = MovaTesting.lastKernel!;
      await a.open(const MovaSource('s00d://danmaku'));
      await component(t, a, MovaDanmakuTrackComponent());
      k.emitPosition(const Duration(seconds: 1));
      await drain(t, 250);
      measured(
        'C6.spawn.$enabled',
        [
          find.text('S00D bullet A').evaluate().length,
          find.text('S00D bullet B').evaluate().length,
          find.byType(TextField).evaluate().length,
        ],
        [enabled ? 1 : 0, enabled ? 1 : 0, 0],
      );
      if (enabled) {
        final before = t.getTopLeft(find.text('S00D bullet A'));
        final by = t.getTopLeft(find.text('S00D bullet B'));
        await drain(t, 500);
        final after = t.getTopLeft(find.text('S00D bullet A'));
        measured(
          'C6.scroll',
          [after.dx < before.dx, by.dy > before.dy],
          [true, true],
          numbers: {
            'beforeX': before.dx,
            'afterX': after.dx,
            'trackA': before.dy,
            'trackB': by.dy,
          },
        );
        k.emitPosition(const Duration(milliseconds: 1100));
        await drain(t, 250);
        measured('C6.unique', find.text('S00D bullet A').evaluate().length, 1);
        await drain(t, 2000);
        measured('C6.retired', find.text('S00D bullet A').evaluate().length, 0);
      }
      await unmount(t);
      await dispose(t, a);
    }
  });

  testWidgets('playlist auto advance and NextUp dismiss/play now', (t) async {
    for (final auto in [false, true]) {
      final a = await make(
        t,
        options: MovaOpts(
          playlist: MovaPlaylistOpts(
            enabled: true,
            autoPlayNext: auto,
            nextUpLeadTime: const Duration(seconds: 5),
            items: const [
              MovaPlaylistItem(
                source: MovaSource('s00d://ep1'),
                title: 'episode 1',
              ),
              MovaPlaylistItem(
                source: MovaSource('s00d://ep2'),
                title: 'S00D next',
              ),
            ],
          ),
        ),
      );
      final k = MovaTesting.lastKernel!;
      final p = MovaPlaylist(a);
      await p.jumpTo(0);
      await component(t, a, MovaNextUpComponent(p));
      k.emitDuration(const Duration(seconds: 20));
      k.emitPosition(const Duration(seconds: 17));
      await drain(t, 250);
      measured('C8.card.$auto', find.text('S00D next').evaluate().length, 1);
      await t.tap(find.text(a.options.strings.cancel));
      await drain(t);
      measured(
        'C8.cancel.$auto',
        [find.text('S00D next').evaluate().length, p.currentIndex],
        [0, 0],
      );
      k.emitCompleted(true);
      await drain(t);
      measured('C8.auto.$auto', p.currentIndex, auto ? 1 : 0);
      await unmount(t);
      await t.runAsync(p.dispose);
      await dispose(t, a);
    }
    final a = await make(
      t,
      options: const MovaOpts(
        playlist: MovaPlaylistOpts(
          enabled: true,
          items: [
            MovaPlaylistItem(source: MovaSource('s00d://one')),
            MovaPlaylistItem(
              source: MovaSource('s00d://two'),
              title: 'S00D now',
            ),
          ],
        ),
      ),
    );
    final k = MovaTesting.lastKernel!;
    final p = MovaPlaylist(a);
    await p.jumpTo(0);
    await component(t, a, MovaNextUpComponent(p));
    k.emitDuration(const Duration(seconds: 20));
    k.emitPosition(const Duration(seconds: 18));
    await drain(t, 250);
    await t.tap(find.text(a.options.strings.playNow));
    await drain(t);
    measured('C8.now', [p.currentIndex, k.lastUri], [1, 's00d://two']);
    await unmount(t);
    await t.runAsync(p.dispose);
    await dispose(t, a);
  });

  testWidgets('View ownership, sameAs, null, options, error and disposal', (
    t,
  ) async {
    final movas = <IMovaApi>[];
    final errors = <Object>[];
    final ready = [
      await make(t),
      await make(
        t,
        options: const MovaOpts(controls: MovaCtrlsOpts(autoHide: false)),
      ),
    ];
    IMovaApi factory(MovaOpts o) {
      final a = ready.removeAt(0);
      movas.add(a);
      return a;
    }

    Widget view(MovaSource? s, {MovaOpts o = const MovaOpts()}) => MaterialApp(
      home: MovaView(
        source: s,
        options: o,
        movaFactory: factory,
        autoLoadQualities: false,
        onOpenError: (e, st) => errors.add(e),
        poster: const Text('S00D poster'),
      ),
    );
    await t.pumpWidget(view(null));
    await drain(t);
    measured(
      'N17.lazy',
      [movas.length, find.text('S00D poster').evaluate().length],
      [0, 1],
    );
    await t.pumpWidget(view(const MovaSource('s00d://view', title: 'old')));
    await drain(t);
    final first = MovaTesting.kernels.first;
    measured('N17.owned', [movas.length, first.lastUri], [1, 's00d://view']);
    await t.pumpWidget(view(const MovaSource('s00d://view', title: 'new')));
    await drain(t);
    measured('N17.same', first.calls.where((s) => s == 'open').length, 1);
    await t.pumpWidget(
      view(const MovaSource('s00d://view', alternatives: ['s00d://backup'])),
    );
    await drain(t);
    measured(
      'N17.alternatives',
      first.calls.where((s) => s == 'open').length,
      2,
    );
    await t.pumpWidget(view(null));
    await drain(t);
    measured('N17.null', first.calls.where((s) => s == 'pause').length, 1);
    await t.pumpWidget(
      view(
        const MovaSource('s00d://second'),
        o: const MovaOpts(controls: MovaCtrlsOpts(autoHide: false)),
      ),
    );
    await drain(t);
    measured(
      'N17.options',
      [
        movas.length,
        first.calls.contains('dispose'),
        MovaTesting.lastKernel!.lastUri,
      ],
      [2, true, 's00d://second'],
    );
    final second = MovaTesting.lastKernel!;
    second.openError = StateError('S00D open fault');
    await t.pumpWidget(
      view(
        const MovaSource('s00d://throw'),
        o: const MovaOpts(controls: MovaCtrlsOpts(autoHide: false)),
      ),
    );
    await drain(t);
    measured(
      'N17.error',
      [errors.length, t.takeException() == null],
      [1, true],
    );
    await unmount(t);
    measured(
      'N17.dispose',
      MovaTesting.kernels
          .map((k) => k.calls.where((s) => s == 'dispose').length)
          .toList(),
      [1, 1],
    );
  });

  testWidgets('borrowed player, declared fit once and source options', (
    t,
  ) async {
    final a = await make(t);
    final k = MovaTesting.lastKernel!;
    final fits = <String>[];
    final sub = a.events
        .where((e) => e is MovaFitChange)
        .listen((e) => fits.add((e as MovaFitChange).fit.name));
    Widget player() => MaterialApp(
      home: MovaPlayer(
        api: a,
        fit: MovaFit.cover,
        surface: const Text('S00D surface'),
        uiKit: const MovaMinimalUiKit(),
      ),
    );
    await t.pumpWidget(player());
    await drain(t);
    measured(
      'A11.declared',
      [a.state.fit.name, fits],
      [
        'cover',
        ['cover'],
      ],
    );
    await a.setFit(MovaFit.fill);
    await drain(t);
    await t.pumpWidget(player());
    await drain(t);
    measured(
      'A11.once',
      [a.state.fit.name, fits],
      [
        'fill',
        ['cover', 'fill'],
      ],
    );
    measured('U1.surface', find.text('S00D surface').evaluate().length, 1);
    await unmount(t);
    measured('U1.borrowed', k.calls.where((s) => s == 'dispose').length, 0);
    await a.open(
      const MovaSource(
        's00d://options',
        mpvOptions: {'http-header-fields': 'X-S00D: one'},
      ),
    );
    await a.open(const MovaSource('s00d://options2'));
    measured('N21.staged', k.stagedSourceOptions, [
      {'http-header-fields': 'X-S00D: one'},
      <String, String>{},
    ]);
    await t.runAsync(sub.cancel);
    await dispose(t, a);
  });

  testWidgets('poster reset, fade attributes and audio-size cover', (t) async {
    final a = await make(t);
    final k = MovaTesting.lastKernel!;
    await a.open(const MovaSource('s00d://poster'));
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(
          api: a,
          poster: const Text('S00D poster'),
          uiKit: const MovaMinimalUiKit(),
        ),
      ),
    );
    await drain(t);
    AnimatedOpacity opacity() => t.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('S00D poster'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    measured('N15.cover', opacity().opacity, 1.0);
    k.emitSize(640, 360);
    k.emitBuffering(true);
    await drain(t);
    k.emitBuffering(false);
    k.emitPosition(const Duration(seconds: 1));
    await drain(t, 250);
    measured(
      'N15.fade',
      [a.state.rendered, opacity().opacity, opacity().duration.inMilliseconds],
      [true, 0.0, 300],
    );
    final fadeFinder = find
        .ancestor(
          of: find.text('S00D poster'),
          matching: find.byType(AnimatedOpacity),
        )
        .first;
    await t.pump(const Duration(milliseconds: 150));
    final mid = t.renderObject<RenderAnimatedOpacity>(fadeFinder).opacity.value;
    measured(
      'N15.renderFade',
      mid > 0 && mid < 1,
      true,
      numbers: {'opacity': mid},
    );
    await t.pump(const Duration(milliseconds: 160));
    measured(
      'N15.renderFadeDone',
      t.renderObject<RenderAnimatedOpacity>(fadeFinder).opacity.value,
      0.0,
    );

    await a.open(const MovaSource('s00d://poster2'));
    await drain(t);
    measured(
      'N15.recover',
      [a.state.rendered, opacity().opacity, opacity().duration.inMilliseconds],
      [false, 1.0, 0],
    );
    k.emitPosition(const Duration(seconds: 1));
    await drain(t, 250);
    measured(
      'N15.noSize',
      [a.state.width, a.state.height, opacity().opacity],
      [0, 0, 1.0],
    );
    await unmount(t);
    await dispose(t, a);
  });

  testWidgets('play, speed buttons and concrete HUDs', (t) async {
    final a = await make(t);
    final k = MovaTesting.lastKernel!;
    await component(t, a, MovaPlayPauseComponent());
    await t.tap(find.byIcon(Icons.play_circle_filled_rounded));
    await drain(t);
    measured('U5.play', k.calls.where((s) => s == 'play').length, 1);
    k.emitPlaying(true);
    await drain(t);
    await t.tap(find.byIcon(Icons.pause_circle_filled_rounded));
    await drain(t);
    measured('U5.pause', k.calls.where((s) => s == 'pause').length, 1);
    await component(t, a, MovaSpeedButtonComponent());
    final rates = <double>[];
    for (var i = 0; i < 6; i++) {
      await t.tap(find.byType(MovaIconButton));
      await drain(t);
      rates.add(a.state.rate);
    }
    measured('U5.rates', rates, [1.25, 1.5, 2.0, 0.5, 0.75, 1.0]);
    await a.setVolume(37);
    a.showHud(MovaHud.volume);
    await component(t, a, MovaVolumeHudComponent());
    measured('U5.volume', find.text('37%').evaluate().length, 1);
    await a.setBrightness(.42);
    a.showHud(MovaHud.brightness);
    await component(t, a, MovaBrightnessHudComponent());
    measured('U5.brightness', find.text('42%').evaluate().length, 1);
    a.showHud(MovaHud.seek, text: '00:17');
    await component(t, a, MovaSeekHudComponent());
    measured('U5.seek', find.text('00:17').evaluate().length, 1);
    await a.setZoom(2.3);
    a.showHud(MovaHud.zoom);
    await component(t, a, MovaZoomHudComponent());
    measured(
      'U5.zoom',
      find.text('2.3${a.options.strings.zoomSuffix}').evaluate().length,
      1,
    );
    await unmount(t);
    await dispose(t, a);
  });
  testWidgets(
    'mini: default off, mounting modes, drag, snap, fling, resize, close',
    (t) async {
      final mini = MovaMini();
      var closed = 0;
      var tapped = 0;
      mini.onClosed = (_) {
        closed++;
      };
      mini.onTapContent = (_) {
        tapped++;
      };
      final off = await make(t);
      await t.pumpWidget(
        MaterialApp(
          builder: (c, w) => MovaMiniHost(mini: mini, child: w!),
          home: const Scaffold(body: Text('S00D host')),
        ),
      );
      await drain(t);
      await t.runAsync(() => mini.show(off));
      await drain(t);
      measured(
        'C12.defaultOff',
        find.byType(MovaMiniWindow).evaluate().length,
        0,
      );
      await t.runAsync(mini.hide);
      await dispose(t, off);
      final a = await make(
        t,
        options: const MovaOpts(
          mini: MovaMiniOpts(
            enabled: true,
            width: 160,
            margin: 12,
            settleDuration: Duration.zero,
          ),
        ),
      );
      await t.runAsync(() => mini.show(a));
      await drain(t);
      measured(
        'A26.persistent',
        [
          mini.isShowing(a),
          mini.mount.name,
          find.byType(MovaMiniWindow).evaluate().length,
        ],
        [true, 'persistent', 1],
      );
      final window = find.byKey(const ValueKey('movaMiniWindowGesture'));
      final before = t.getTopLeft(window);
      final drag = await t.startGesture(t.getCenter(window));
      await drag.moveBy(const Offset(-250, -150));
      await drag.moveBy(const Offset(-20, -20));
      await drain(t);
      final after = t.getTopLeft(window);
      measured(
        'U8.drag',
        [after.dx != before.dx, after.dy != before.dy],
        [true, true],
        numbers: {
          'beforeX': before.dx,
          'beforeY': before.dy,
          'afterX': after.dx,
          'afterY': after.dy,
        },
      );
      await drag.up();
      await drain(t);
      final surface = t.getSize(find.byType(MovaMiniHost));
      final rect = t.getRect(window);
      measured(
        'U8.snap',
        [
          rect.left == 12 || rect.right == surface.width - 12,
          rect.top >= 12,
          rect.bottom <= surface.height - 12,
        ],
        [true, true, true],
      );
      await t.fling(window, const Offset(-350, -120), 3000);
      await drain(t);
      measured('U8.fling', [mini.isShowing(a), closed], [true, 0]);
      final old = t.getRect(window);
      await t.binding.setSurfaceSize(const Size(600, 800));
      await drain(t);
      final expected = clampToBounds(
        remapProportionally(
          MovaMiniRect(
            left: old.left,
            top: old.top,
            width: old.width,
            height: old.height,
          ),
          oldBounds: MovaMiniRect(
            left: 0,
            top: 0,
            width: surface.width,
            height: surface.height,
          ),
          newBounds: const MovaMiniRect(
            left: 0,
            top: 0,
            width: 600,
            height: 800,
          ),
        ),
        bounds: const MovaMiniRect(left: 0, top: 0, width: 600, height: 800),
        insets: const MovaMiniInsets(),
        margin: 12,
      );
      final rotated = t.getRect(window);
      measured(
        'U8.resize',
        [rotated.left, rotated.top, rotated.width, rotated.height],
        [expected.left, expected.top, expected.width, expected.height],
      );
      await t.tapAt(
        t.getTopLeft(window) + Offset(10, t.getSize(window).height - 10),
      );
      await drain(t);
      measured('A26.tap', tapped, 1);
      await t.runAsync(
        () => mini.showInPage(t.element(find.text('S00D host')), a),
      );
      await drain(t);
      measured(
        'A26.page',
        [mini.mount.name, find.byType(MovaMiniWindow).evaluate().length],
        ['page', 1],
      );
      mini.setRect(
        const MovaMiniRect(left: 12, top: 12, width: 160, height: 90),
      );
      await drain(t);
      measured('A26.setRect', [mini.rect?.left, mini.rect?.top], [12.0, 12.0]);
      await t.runAsync(mini.hide);
      await drain(t);
      measured('A26.hide', [mini.isShowing(a), closed], [false, 0]);
      await t.runAsync(() => mini.show(a));
      await drain(t);
      await t.runAsync(mini.close);
      await drain(t);
      measured(
        'A26.close',
        [mini.isShowing(a), closed, a.state.mini],
        [false, 1, false],
      );
      await unmount(t);
      await dispose(t, a);
      mini.dispose();
      await t.binding.setSurfaceSize(null);
    },
  );

  testWidgets('top buttons title, fit cycle and fullscreen', (t) async {
    final a = await make(t);
    await a.open(const MovaSource('s00d://title', title: 'S00D title'));
    await component(t, a, MovaTitleComponent());
    measured('U3.title', find.text('S00D title').evaluate().length, 1);
    await component(t, a, MovaPipButtonComponent());
    measured('U3.pipHidden', find.byType(MovaIconButton).evaluate().length, 0);
    await component(t, a, MovaFitButtonComponent());
    final fits = <String>[];
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byType(MovaIconButton));
      await drain(t);
      fits.add(a.state.fit.name);
    }
    measured('U3.fit', fits, ['cover', 'fill', 'contain']);
    await component(t, a, MovaFullscreenButtonComponent());
    await t.tap(find.byType(MovaIconButton));
    await drain(t);
    measured('U3.fullscreenOn', a.state.fullscreen, true);
    await t.tap(find.byType(MovaIconButton));
    await drain(t);
    measured('U3.fullscreenOff', a.state.fullscreen, false);
    await unmount(t);
    await dispose(t, a);
  });

  testWidgets('seekbar: disabled, preview on drag, commit on release', (
    t,
  ) async {
    final a = await make(t);
    final k = MovaTesting.lastKernel!;
    await a.open(const MovaSource('s00d://seekbar'));
    await component(t, a, MovaSeekBarComponent());
    measured(
      'U4.disabled',
      t.widget<Slider>(find.byType(Slider)).onChanged == null,
      true,
    );
    k.emitDuration(const Duration(seconds: 100));
    await drain(t, 250);
    final slider = t.widget<Slider>(find.byType(Slider));
    measured('U4.enabled', slider.onChanged != null, true);
    slider.onChanged!(35000);
    await drain(t);
    measured(
      'U4.drag',
      [
        a.uiState.dragging,
        a.uiState.previewAt?.inMilliseconds,
        k.calls.where((v) => v == 'seek').length,
      ],
      [true, 35000, 0],
    );
    slider.onChangeEnd!(35000);
    await drain(t);
    measured(
      'U4.commit',
      [a.uiState.dragging, k.lastSeek?.inMilliseconds],
      [false, 35000],
    );
    k.emitPosition(const Duration(seconds: 35));
    await drain(t, 250);
    await component(t, a, MovaPositionLabelComponent());
    k.emitPosition(const Duration(seconds: 36));
    await drain(t, 250);
    measured('U4.label', find.text('00:36').evaluate().length, 1);
    await unmount(t);
    await dispose(t, a);
  });

  testWidgets('gestures: taps, seek, axes, remapping, pinch and lock', (
    t,
  ) async {
    for (final remap in [false, true]) {
      final a = await make(
        t,
        options: MovaOpts(
          gesture: MovaGestureOpts(
            maxZoom: 2,
            leftVertical: remap
                ? MovaGestureAction.volume
                : MovaGestureAction.brightness,
            rightVertical: remap
                ? MovaGestureAction.brightness
                : MovaGestureAction.volume,
          ),
        ),
      );
      final k = MovaTesting.lastKernel!;
      await a.open(const MovaSource('s00d://gesture'));
      k.emitDuration(const Duration(seconds: 100));
      k.emitPosition(const Duration(seconds: 30));
      await a.setBrightness(.5);
      await a.setVolume(50);
      await drain(t, 250);
      await component(t, a, MovaGestureLayerComponent());
      final region = find
          .byType(SizedBox)
          .last; // Scope's component fills 400x240.
      final box = find.byType(Scaffold);
      final origin = t.getTopLeft(box);
      final initial = a.uiState.controlsVisible;
      await t.tapAt(origin + const Offset(200, 100));
      await drain(t, 400);
      measured('U6.tap.$remap', a.uiState.controlsVisible, !initial);
      final left = origin + const Offset(70, 150);
      final right = origin + const Offset(330, 150);
      await t.dragFrom(left, const Offset(0, -90));
      await drain(t);
      measured(
        'C3.left.$remap',
        remap ? a.state.volume > 50 : a.state.brightness > .5,
        true,
      );
      await a.setBrightness(.5);
      await a.setVolume(50);
      await drain(t);
      await t.dragFrom(right, const Offset(0, -90));
      await drain(t);
      measured(
        'C3.right.$remap',
        remap ? a.state.brightness > .5 : a.state.volume > 50,
        true,
      );
      await a.seek(const Duration(seconds: 30));
      k.emitPosition(const Duration(seconds: 30));
      await drain(t, 250);
      await t.tapAt(right);
      await t.pump(const Duration(milliseconds: 60));
      await t.tapAt(right);
      await drain(t, 350);
      measured('U6.doubleRight.$remap', k.lastSeek?.inMilliseconds, 40000);
      k.emitPosition(const Duration(seconds: 40));
      await drain(t, 250);
      await t.tapAt(left);
      await t.pump(const Duration(milliseconds: 60));
      await t.tapAt(left);
      await drain(t, 350);
      measured('U6.doubleLeft.$remap', k.lastSeek?.inMilliseconds, 30000);
      k.emitPosition(const Duration(seconds: 30));
      await drain(t, 250);
      await t.dragFrom(origin + const Offset(100, 100), const Offset(80, 0));
      await drain(t);
      measured(
        'U6.horizontal.$remap',
        (k.lastSeek?.inMilliseconds ?? 0) > 30000,
        true,
      );
      final one = await t.startGesture(
        origin + const Offset(160, 120),
        pointer: 1,
      );
      final two = await t.startGesture(
        origin + const Offset(240, 120),
        pointer: 2,
      );
      await one.moveBy(const Offset(-80, 0));
      await two.moveBy(const Offset(80, 0));
      await t.pump();
      await one.moveBy(const Offset(-80, 0));
      await two.moveBy(const Offset(80, 0));
      await drain(t);
      await one.up();
      await two.up();
      await drain(t);
      measured('U6.pinch.$remap', a.state.zoom, 2.0);
      await t.longPressAt(origin + const Offset(200, 120));
      await drain(t);
      measured('U6.longPress.$remap', a.state.rate, 1.0);
      // Lock enforcement belongs to the real UI kit, not the standalone leaf.
      await t.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 400, height: 240, child: MovaPlayer(api: a)),
        ),
      );
      await drain(t);
      await a.setLocked(true);
      await drain(t);
      final calls = k.calls.length;
      final brightness = a.state.brightness;
      final volume = a.state.volume;
      await t.dragFrom(const Offset(100, 150), const Offset(0, -90));
      await drain(t);
      measured(
        'A13.lock.$remap',
        [
          a.state.locked,
          a.state.brightness,
          a.state.volume,
          k.calls.length - calls,
        ],
        [true, brightness, volume, 0],
      );
      await a.setLocked(false);
      await drain(t);
      measured('A13.unlock.$remap', a.state.locked, false);
      // Ensure the gesture region existed (no silent zero-sized probe).
      measured('U6.region.$remap', region.evaluate().isNotEmpty, true);
      await unmount(t);
      await dispose(t, a);
    }
  });

  testWidgets('topbar selectable quality, supported PiP and mobile direction', (
    t,
  ) async {
    final pip = SupportedPip();
    final a = await make(t, pip: pip, fetcher: MasterFetch());
    final k = MovaTesting.lastKernel!;
    await a.open(const MovaSource('https://s00d.invalid/master.m3u8'));
    await a.loadQualities();
    await drain(t);
    await component(t, a, MovaQualityButtonComponent());
    measured('U3.qualityCount', a.state.qualities.length, 3);
    final selected = a.state.qualities.last;
    await t.tap(find.byType(MovaIconButton));
    await drain(t, 350);
    await t.pumpAndSettle();
    measured(
      'U3.qualityMenu',
      a.state.qualities
          .map((q) => find.text(q.label).evaluate().isNotEmpty)
          .toList(),
      [true, true, true],
    );
    await t.ensureVisible(find.text(selected.label).last);
    await t.pumpAndSettle();
    await t.tap(find.text(selected.label).last);
    await drain(t, 350);
    await t.pumpAndSettle();
    k.emitDuration(const Duration(seconds: 100));
    k.emitRestart();
    await drain(t);
    measured(
      'U3.qualitySelect',
      [a.state.currentQuality?.uri, k.lastUri],
      [selected.uri, selected.uri],
    );
    await component(t, a, MovaPipButtonComponent());
    await t.tap(find.byType(MovaIconButton));
    await drain(t);
    measured('U3.pipClick', [pip.enters, a.state.pip], [1, true]);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await component(t, a, MovaOrientButtonComponent());
    measured(
      'U3.directionDesktop',
      find.byType(MovaIconButton).evaluate().length,
      0,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await component(t, a, MovaOrientButtonComponent());
    measured(
      'U3.directionMobile',
      find.byType(MovaIconButton).evaluate().length,
      1,
    );
    await t.tap(find.byType(MovaIconButton));
    await drain(t);
    measured('U3.direction1', a.state.orient.name, 'landscape');
    await t.tap(find.byType(MovaIconButton));
    await drain(t);
    measured('U3.direction2', a.state.orient.name, 'portrait');
    debugDefaultTargetPlatformOverride = null;
    await unmount(t);
    await dispose(t, a);
  });

  testWidgets('Feed poster reset and owned pool disposal', (t) async {
    final a = await make(t);
    final k = MovaTesting.lastKernel!;
    var creates = 0;
    await t.pumpWidget(
      MaterialApp(
        home: MovaFeedPlayer(
          poolSize: 1,
          prefetchDepth: 0,
          movaFactory: () {
            creates++;
            return a;
          },
          posterUntilFirstFrame: true,
          placeholderBuilder: (c, item) => Text(
            'S00D feed poster ${Uri.parse(item.source.uri).pathSegments.last}',
          ),
          loader: (i) async => i >= 0 && i < 2
              ? MovaFeedItem(source: MovaSource('s00d://feed/$i'))
              : null,
        ),
      ),
    );
    await drain(t);
    measured('U1.feedOwned', [creates, k.lastUri], [1, 's00d://feed/0']);
    AnimatedOpacity opacity(int i) => t.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('S00D feed poster $i'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    measured('N15.feedCover', opacity(0).opacity, 1.0);
    k.emitSize(640, 360);
    k.emitRestart();
    await drain(t);
    measured('N15.feedFade', opacity(0).opacity, 0.0);
    await t.drag(find.byType(PageView), const Offset(0, -550));
    await drain(t, 500);
    await t.pumpAndSettle();
    await drain(t);
    measured('U1.feedSource', k.lastUri, 's00d://feed/1');
    measured(
      'N15.feedRecover',
      [a.state.rendered, opacity(1).opacity],
      [false, 1.0],
    );
    await unmount(t);
    measured('U1.feedDispose', k.calls.where((v) => v == 'dispose').length, 1);
  });
}
