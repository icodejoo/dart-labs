import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/components/overlays.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/skins/minimal_skin.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Pushes [s] and pumps twice: once for the stream delivery, once for the rebuild.
///
/// 推送 [s] 并 pump 两次：一次等流投递，一次等重建。
Future<void> _push(WidgetTester t, FakeMovaApi api, MovaState s) async {
  api.push(s);
  await t.pump();
  await t.pump();
}

void main() {
  test('components(): buffering by default, none when disabled, error on request', () {
    expect(const MovaMinimalSkin().components().map((c) => c.name), [MovaBufferingComponent.componentName]);
    expect(const MovaMinimalSkin(showBuffering: false).components(), isEmpty);
    expect(
      const MovaMinimalSkin(showError: true).components().map((c) => c.name),
      contains(MovaErrorComponent.componentName),
    );
  });

  testWidgets('mounts without any gesture layer, slider or bars', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: const MovaMinimalSkin())));
    await t.pump();
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    await api.dispose();
  });

  testWidgets('the spinner follows state.buffering', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: const MovaMinimalSkin())));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await _push(t, api, const MovaState(buffering: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _push(t, api, const MovaState());
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await api.dispose();
  });

  testWidgets('theme size, stroke width and color reach the spinner', (t) async {
    final api = FakeMovaApi(
      options: const MovaOpts(
        theme: MovaTheme(bufferingSize: 24, bufferingStrokeWidth: 2, bufferingColor: 0xFFFFFFFF),
      ),
    );
    api.push(const MovaState(buffering: true));
    await pumpComponent(t, api, MovaBufferingComponent());
    final box = t.widget<SizedBox>(find.ancestor(
      of: find.byType(CircularProgressIndicator),
      matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 24),
    ));
    expect(box.height, 24);
    final indicator = t.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(indicator.strokeWidth, 2);
    expect(indicator.color, const Color(0xFFFFFFFF));
    await api.dispose();
  });

  testWidgets('default theme: accent color and no SizedBox wrapper (default skin unchanged)', (t) async {
    final api = FakeMovaApi();
    api.push(const MovaState(buffering: true));
    await pumpComponent(t, api, MovaBufferingComponent());
    final indicator = t.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(indicator.color, Color(const MovaTheme().accentColor));
    expect(indicator.strokeWidth, isNull);
    expect(
      find.byWidgetPredicate((w) => w is Center && w.child is CircularProgressIndicator),
      findsOneWidget,
    );
    await api.dispose();
  });

  test('MovaTheme: new buffering fields default to null and take part in ==/hashCode', () {
    const base = MovaTheme();
    expect(base.bufferingSize, isNull);
    expect(base.bufferingStrokeWidth, isNull);
    expect(base.bufferingColor, isNull);
    expect(const MovaTheme(bufferingSize: 24), isNot(equals(base)));
    expect(const MovaTheme(bufferingStrokeWidth: 2), isNot(equals(base)));
    expect(const MovaTheme(bufferingColor: 0xFFFFFFFF), isNot(equals(base)));
    expect(const MovaTheme(bufferingSize: 24), equals(const MovaTheme(bufferingSize: 24)));
    expect(const MovaTheme(bufferingSize: 24).hashCode, const MovaTheme(bufferingSize: 24).hashCode);
    expect(const MovaTheme(bufferingSize: 24).hashCode, isNot(base.hashCode));
  });

  testWidgets('taps fall through to an outer GestureDetector', (t) async {
    final api = FakeMovaApi();
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: GestureDetector(
        onTap: () => taps++,
        child: MovaPlayer(api: api, skin: const MovaMinimalSkin()),
      ),
    ));
    await t.pump();
    await t.tapAt(const Offset(200, 200));
    expect(taps, 1);
    await api.dispose();
  });
}
