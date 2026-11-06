import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../../support/fake_api.dart';
import '../../support/fake_kernel.dart';
import '../../support/fake_bridge_api.dart';

void main() {
  testWidgets('two views of one API have independent copy', (t) async {
    final api = FakeMovaApi()
      ..push(const MovaState(type: MovaStreamType.live, pipSupported: true));
    await t.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: MovaPlayer(
                api: api,
                style: const MovaPlayerStyle(strings: MovaStrs(live: 'ON AIR')),
              ),
            ),
            Expanded(child: MovaPlayer(api: api)),
          ],
        ),
      ),
    );
    await t.pump();
    expect(find.text('ON AIR'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await api.dispose();
  });
  testWidgets('theme updates cached skin while API and calls stay stable', (
    t,
  ) async {
    final kernel = FakeKernel();
    final api = MovaEngine(
      kernel: kernel,
      brightness: MovaFallbackBrightnessPort(),
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
    );
    var changes = 0;
    final sub = api.events.listen((e) {
      if (e is MovaSourceChange) changes++;
    });
    api.open(const MovaSource('https://h/video.mp4'));
    await t.pump();
    kernel.emitBuffering(true);
    await t.pump();
    for (var i = 1; i <= 10; i++) {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [
              MovaPlayerStyle(theme: MovaTheme(accentColor: 0xff000000 + i)),
            ],
          ),
          home: MovaPlayer(api: api, autoLoadQualities: false),
        ),
      );
      await t.pump(const Duration(milliseconds: 250));
      expect(
        t
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .color,
        Color(0xff000000 + i),
      );
    }
    expect(kernel.openedUris, hasLength(1));
    expect(changes, 1);
    expect(api.state.renderEpoch, 0);
    sub.cancel();
    await t.pump();
    await t.pumpWidget(const SizedBox());
    api.dispose();
    await t.pump();
    await t.runAsync(kernel.dispose);
  });
  testWidgets(
    'gesture override disables double tap seek with default control',
    (t) async {
      final api = FakeMovaApi();
      for (final disabled in [true, false]) {
        api.calls.clear();
        await t.pumpWidget(
          MaterialApp(
            home: MovaPlayer(
              api: api,
              style: disabled
                  ? const MovaPlayerStyle(
                      gesture: MovaGestureConfig(doubleTapSeek: false),
                    )
                  : null,
            ),
          ),
        );
        await t.pump();
        await t.tapAt(const Offset(650, 300));
        await t.pump(const Duration(milliseconds: 50));
        await t.tapAt(const Offset(650, 300));
        await t.pump(const Duration(milliseconds: 400));
        expect(api.calls.contains('seek'), !disabled);
      }
      await t.pumpWidget(const SizedBox());
      await api.dispose();
    },
  );
  testWidgets('controls style updates chrome timer without replacing it', (
    t,
  ) async {
    final api = FakeBridgeApi();
    final chrome = MovaChrome();
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(api: api, chrome: chrome),
      ),
    );
    chrome.show();
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            MovaPlayerStyle(
              controls: MovaCtrlsConfig(autoHideDelay: Duration(seconds: 1)),
            ),
          ],
        ),
        home: MovaPlayer(api: api, chrome: chrome),
      ),
    );
    await t.pump(const Duration(milliseconds: 250));
    chrome.show();
    await t.pump(const Duration(milliseconds: 999));
    expect(chrome.uiState.controlsVisible, isTrue);
    await t.pump(const Duration(milliseconds: 1));
    expect(chrome.uiState.controlsVisible, isFalse);
    await t.pumpWidget(const SizedBox());
    chrome.dispose();
    await api.dispose();
  });
  testWidgets('local controls enable focused keyboard shortcut', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(
      MaterialApp(
        home: MovaPlayer(
          api: api,
          style: const MovaPlayerStyle(
            controls: MovaCtrlsConfig(shortcuts: true),
          ),
        ),
      ),
    );
    final node = t
        .widget<Focus>(
          find.byWidgetPredicate(
            (w) => w is Focus && w.focusNode?.debugLabel == 'MovaPlayer',
          ),
        )
        .focusNode!;
    node.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(api.calls, contains('playOrPause'));
    await t.pumpWidget(const SizedBox());
    await api.dispose();
  });
}
