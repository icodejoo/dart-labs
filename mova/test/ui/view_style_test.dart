import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

void main() {
  const changed = <String, MovaOpts>{
    'theme': MovaOpts(theme: MovaTheme(accentColor: 0xff00ff00)),
    'strings': MovaOpts(strings: MovaStrs(live: 'ON AIR')),
    'gesture': MovaOpts(gesture: MovaGestureOpts(doubleTapSeek: false)),
    'controls': MovaOpts(controls: MovaCtrlsOpts(shortcuts: true)),
    'danmaku': MovaOpts(danmaku: MovaDanmakuOpts(fontSize: 22)),
  };
  for (final entry in changed.entries) {
    testWidgets(
      'view ${entry.key} updates old options fallback without player recreation',
      (t) async {
        final made = <FakeMovaApi>[];
        IMovaApi factory(MovaOpts o) {
          final api = FakeMovaApi(options: o)
            ..push(const MovaState(buffering: true));
          made.add(api);
          return api;
        }

        Widget view(MovaOpts options) => MaterialApp(
          home: MovaView(
            source: const MovaSource('https://h/a.mp4'),
            options: options,
            movaFactory: factory,
          ),
        );
        await t.pumpWidget(view(const MovaOpts()));
        await t.pump();
        await t.pumpWidget(view(entry.value));
        await t.pump();
        expect(made, hasLength(1));
        expect(made.single.disposed, isFalse);
        expect(made.single.openCalls, 1);
        expect(
          made.single.options,
          const MovaOpts(),
          reason: 'player keeps its construction snapshot',
        );
        final context = t.element(find.byType(CircularProgressIndicator));
        expect(MovaPlayerStyle.themeOf(context), entry.value.theme);
        expect(MovaPlayerStyle.stringsOf(context), entry.value.strings);
        expect(MovaPlayerStyle.gestureOf(context), entry.value.gesture);
        expect(MovaPlayerStyle.controlsOf(context), entry.value.controls);
        expect(
          MovaPlayerStyle.danmakuOf(context),
          MovaDanmakuStyle.fromOpts(entry.value.danmaku),
        );
        expect(
          t
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .color,
          Color(entry.value.theme.accentColor),
        );
        await t.pumpWidget(const SizedBox());
        await t.pump();
      },
    );
  }
  testWidgets(
    'inline closures and new danmaku lists keep player and use latest data',
    (t) async {
      final made = <FakeMovaApi>[];
      final uiKit = MovaBilibiliUiKit();
      IMovaApi factory(MovaOpts o) {
        final api = FakeMovaApi(options: o)
          ..push(const MovaState(playing: true));
        made.add(api);
        return api;
      }

      for (var i = 0; i < 5; i++) {
        await t.pumpWidget(
          MaterialApp(
            home: MovaView(
              source: const MovaSource('https://h/a.mp4'),
              movaFactory: factory,
              uiKit: uiKit,
              options: MovaOpts(
                strings: MovaStrs(adStartingIn: (n) => '$n s'),
                danmaku: MovaDanmakuOpts(
                  enabled: true,
                  items: [
                    MovaDanmakuItem(
                      text: 'item$i',
                      time: const Duration(seconds: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pump();
      }
      expect(made, hasLength(1));
      expect(made.single.openCalls, 1);
      expect(made.single.disposed, isFalse);
      made.single.pushProgress(const MovaProg(position: Duration(seconds: 2)));
      await t.pump();
      await t.pump();
      expect(find.text('item4'), findsOneWidget);
      expect(find.text('item0'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
}
