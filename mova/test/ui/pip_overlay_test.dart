import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/ui/components/pip_overlay.dart';

import '../support/fake_api.dart';

void main() {
  Future<BuildContext> pumpHost(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })));
    await t.pump();
    return ctx;
  }

  testWidgets('show inserts the overlay with a close button; hide removes it', (t) async {
    final api = FakeMovaApi();
    final ctx = await pumpHost(t);

    MovaPipOverlay.show(ctx, api: api, video: const ColoredBox(color: Colors.red));
    await t.pump();
    expect(MovaPipOverlay.isShown, isTrue);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    MovaPipOverlay.hide();
    await t.pump();
    expect(MovaPipOverlay.isShown, isFalse);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    await api.dispose();
  });

  testWidgets('show is a no-op while already shown (single overlay instance)', (t) async {
    final api = FakeMovaApi();
    final ctx = await pumpHost(t);

    MovaPipOverlay.show(ctx, api: api, video: const ColoredBox(color: Colors.red));
    MovaPipOverlay.show(ctx, api: api, video: const ColoredBox(color: Colors.blue));
    await t.pump();
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    MovaPipOverlay.hide();
    await t.pump();
    await api.dispose();
  });

  testWidgets('tapping the close button closes the overlay', (t) async {
    final api = FakeMovaApi();
    final ctx = await pumpHost(t);

    MovaPipOverlay.show(ctx, api: api, video: const ColoredBox(color: Colors.red));
    await t.pump();
    expect(MovaPipOverlay.isShown, isTrue);

    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump();
    expect(MovaPipOverlay.isShown, isFalse);

    await api.dispose();
  });

  testWidgets('dragging the overlay body repositions it within the viewport', (t) async {
    final api = FakeMovaApi();
    final ctx = await pumpHost(t);

    MovaPipOverlay.show(ctx, api: api, video: const ColoredBox(color: Colors.red));
    await t.pump();

    final before = t.getTopLeft(find.byIcon(Icons.close_rounded));
    // The full-screen host also builds a `ColoredBox` (Scaffold's background),
    // so `.first` would grab that instead of the overlay's video — pick the
    // one whose center falls inside the (much smaller) floating window.
    //
    // 全屏宿主自身也会构建一个 `ColoredBox`（Scaffold 背景），所以 `.first`
    // 会取到那个而非悬浮窗里的视频——取中心点落在（小得多的）悬浮窗内的那个。
    final center = t.getCenter(find.byType(ColoredBox).last);
    final gesture = await t.startGesture(center);
    await gesture.moveBy(const Offset(-40, -40));
    await t.pump();
    await gesture.up();
    await t.pump();
    final after = t.getTopLeft(find.byIcon(Icons.close_rounded));
    expect(after, isNot(equals(before)));

    MovaPipOverlay.hide();
    await api.dispose();
  });
}
