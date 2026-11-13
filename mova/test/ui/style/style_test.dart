import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/ui/style/style.dart';
import '../../support/fake_api.dart';

Future<void> probe(
  WidgetTester t,
  void Function(BuildContext) check, {
  MovaOpts? options,
  MovaPlayerStyle? local,
  MovaPlayerStyle? themed,
  bool bare = false,
}) async {
  Widget child = Builder(
    builder: (c) {
      check(c);
      return const SizedBox();
    },
  );
  child = MovaStyleScope(local: local, child: child);
  if (!bare) {
    child = MovaScope(
      api: FakeMovaApi(options: options ?? const MovaOpts()),
      child: child,
    );
  }
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [?themed]),
      home: child,
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('defaults work with and without API scope', (t) async {
    for (final bare in [false, true]) {
      await probe(t, (c) {
        expect(MovaPlayerStyle.themeOf(c), const MovaTheme());
        expect(MovaPlayerStyle.stringsOf(c), const MovaStrs());
        expect(MovaPlayerStyle.gestureOf(c), const MovaGestureOpts());
        expect(MovaPlayerStyle.controlsOf(c), const MovaCtrlsOpts());
        expect(MovaPlayerStyle.danmakuOf(c), const MovaDanmakuStyle());
      }, bare: bare);
    }
  });
  testWidgets('legacy options supply all five sections', (t) async {
    const o = MovaOpts(
      theme: MovaTheme(accentColor: 1),
      strings: MovaStrs(live: 'old'),
      gesture: MovaGestureOpts(pinchZoom: false),
      controls: MovaCtrlsOpts(shortcuts: true),
      danmaku: MovaDanmakuOpts(fontSize: 20),
    );
    await probe(t, (c) {
      expect(MovaPlayerStyle.themeOf(c), o.theme);
      expect(MovaPlayerStyle.stringsOf(c), o.strings);
      expect(MovaPlayerStyle.gestureOf(c), o.gesture);
      expect(MovaPlayerStyle.controlsOf(c), o.controls);
      expect(MovaPlayerStyle.danmakuOf(c).fontSize, 20);
    }, options: o);
  });
  testWidgets('theme overrides legacy with independent section fallback', (
    t,
  ) async {
    await probe(
      t,
      (c) {
        expect(MovaPlayerStyle.themeOf(c).accentColor, 2);
        expect(MovaPlayerStyle.stringsOf(c).live, 'legacy');
      },
      options: const MovaOpts(
        theme: MovaTheme(accentColor: 1),
        strings: MovaStrs(live: 'legacy'),
      ),
      themed: const MovaPlayerStyle(theme: MovaTheme(accentColor: 2)),
    );
  });
  testWidgets('local wins and omitted local sections fall through', (t) async {
    await probe(
      t,
      (c) {
        expect(MovaPlayerStyle.themeOf(c).accentColor, 3);
        expect(MovaPlayerStyle.stringsOf(c).live, 'theme');
      },
      local: const MovaPlayerStyle(theme: MovaTheme(accentColor: 3)),
      themed: const MovaPlayerStyle(
        theme: MovaTheme(accentColor: 2),
        strings: MovaStrs(live: 'theme'),
      ),
    );
  });
  testWidgets('sections replace as a whole', (t) async {
    await probe(
      t,
      (c) {
        expect(MovaPlayerStyle.themeOf(c).accentColor, 4);
        expect(
          MovaPlayerStyle.themeOf(c).textColor,
          const MovaTheme().textColor,
        );
      },
      options: const MovaOpts(theme: MovaTheme(textColor: 9)),
      themed: const MovaPlayerStyle(theme: MovaTheme(accentColor: 4)),
    );
  });
  test('copy equality hash and discrete lerp', () {
    const a = MovaPlayerStyle(theme: MovaTheme(accentColor: 1));
    final b = a.copyWith(strings: const MovaStrs(play: 'Play'));
    expect(b.theme, a.theme);
    expect(b.strings!.play, 'Play');
    expect(a.copyWith(), a);
    expect(a.copyWith().hashCode, a.hashCode);
    expect(b, isNot(a));
    expect(a.lerp(b, 0.3), same(a));
    expect(a.lerp(b, 0.7), same(b));
    expect(a.lerp(null, 1), same(a));
  });
  test(
    'danmaku extraction applies five fields and preserves data identity',
    () {
      final items = <MovaDanmakuItem>[];
      final data = MovaDanmakuOpts(enabled: true, items: items);
      const opts = MovaDanmakuOpts(
        trackCount: 2,
        trackHeight: 44,
        fontSize: 30,
        opacity: 0.4,
        crossDuration: Duration(seconds: 3),
      );
      final style = MovaDanmakuStyle.fromOpts(opts);
      final result = style.applyTo(data);
      expect(MovaDanmakuStyle.fromOpts(result), style);
      expect(result.trackCount, 2);
      expect(result.trackHeight, 44);
      expect(result.fontSize, 30);
      expect(result.opacity, 0.4);
      expect(result.crossDuration, const Duration(seconds: 3));
      expect(result.items, same(items));
      expect(result.enabled, isTrue);
      expect(style.hashCode, MovaDanmakuStyle.fromOpts(opts).hashCode);
    },
  );
  test('danmaku rejects zero tracks', () {
    expect(() => MovaDanmakuStyle(trackCount: 0), throwsAssertionError);
  });
}
