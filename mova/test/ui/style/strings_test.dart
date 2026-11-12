import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../../support/fake_api.dart';

String _join(String action, String value) => '$action: $value';
Future<FakeMovaApi> mount(
  WidgetTester t, {
  MovaStrs strings = const MovaStrs(),
  MovaQuality? quality,
  MovaSkin skin = const MovaDefaultSkin(),
}) async {
  final api = FakeMovaApi();
  final q = quality ?? MovaQuality.auto();
  api.push(MovaState(pipSupported: true, qualities: [q], currentQuality: q));
  await t.pumpWidget(
    MaterialApp(
      home: MovaPlayer(
        api: api,
        skin: skin,
        style: MovaPlayerStyle(strings: strings),
      ),
    ),
  );
  await t.pump();
  addTearDown(api.dispose);
  return api;
}

void main() {
  testWidgets('default semantics and quality menu keep exact copy', (t) async {
    await mount(t);
    for (final label in ['画中画', '清晰度：自动', '画面比例：适应', '进入全屏', '锁定控制']) {
      expect(
        find.byWidgetPredicate((w) => w is MovaIconButton && w.label == label),
        findsOneWidget,
      );
    }
    await t.tap(find.byIcon(Icons.high_quality_rounded));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '自动'), findsOneWidget);
  });
  testWidgets('localized explicit labels and auto menu preserve core label', (
    t,
  ) async {
    await mount(
      t,
      strings: const MovaStrs(
        pip: 'PiP',
        auto: 'Auto',
        quality: 'Quality',
        lock: 'Lock',
        labelWithValue: _join,
      ),
    );
    for (final label in ['PiP', 'Quality: Auto', 'Lock']) {
      expect(
        find.byWidgetPredicate((w) => w is MovaIconButton && w.label == label),
        findsOneWidget,
      );
    }
    expect(MovaQuality.auto().label, '自动');
    await t.tap(find.byIcon(Icons.high_quality_rounded));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Auto'), findsOneWidget);
  });
  testWidgets('unknown quality localizes while host labels survive', (t) async {
    for (final label in ['未知', '超清']) {
      await mount(
        t,
        strings: const MovaStrs(unknownQuality: 'Unknown'),
        quality: MovaQuality(label: label, uri: label),
      );
      expect(find.text(label == '未知' ? 'Unknown' : '超清'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
  });
  testWidgets('label formatter controls action value punctuation', (t) async {
    await mount(
      t,
      strings: const MovaStrs(
        aspectRatio: 'Aspect ratio',
        fitContain: 'Fit',
        labelWithValue: _join,
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is MovaIconButton && w.label == 'Aspect ratio: Fit',
      ),
      findsOneWidget,
    );
  });
  testWidgets('center and mini close use view copy', (t) async {
    final api = await mount(
      t,
      strings: const MovaStrs(play: 'Play', pause: 'Pause', closeMini: 'Close'),
      skin: const MovaMiniSkin(),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Play',
      ),
      findsOneWidget,
    );
    api.push(const MovaState(playing: true));
    await t.pump();
    await t.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Pause',
      ),
      findsOneWidget,
    );
  });
}
