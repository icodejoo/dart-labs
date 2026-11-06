import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';
import '../../support/fake_bridge_api.dart';

Future<void> _mount(
  WidgetTester t,
  FakeMovaApi api, {
  MovaChrome? chrome,
}) async {
  api.push(const MovaState(duration: Duration(seconds: 100)));
  await t.pumpWidget(
    MaterialApp(
      home: MovaPlayer(api: api, chrome: chrome),
    ),
  );
  await t.pump();
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 400));
}

Finder _fit() => find.byWidgetPredicate(
  (w) => w is MovaIconButton && w.icon == Icons.aspect_ratio_rounded,
);

Future<void> _keyboardFit(WidgetTester t) async {
  final child = find
      .descendant(of: _fit(), matching: find.byType(GestureDetector))
      .first;
  Focus.of(t.element(child)).requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
}

void main() {
  for (final slider in [true, false]) {
    testWidgets('锁定卸载${slider ? "底栏" : "横滑"}拖动后恢复隐藏', (t) async {
      final api = FakeBridgeApi();
      final c = MovaChrome();
      await _mount(t, api, chrome: c);
      final start = slider
          ? t.getCenter(find.byType(Slider))
          : t.getCenter(find.byType(MovaPlayer)) + const Offset(-100, 0);
      final gesture = await t.startGesture(start);
      await gesture.moveBy(const Offset(70, 0));
      await t.pump();
      expect(c.value.dragging, isTrue);
      await api.setLocked(true);
      api.push(api.state.copyWith(locked: true));
      await t.pump();
      await t.pump();
      expect(c.value.dragging, isFalse);
      expect(c.value.previewAt, isNull);
      await api.setLocked(false);
      api.push(api.state.copyWith(locked: false));
      await t.pump();
      await gesture.up();
      await t.pump(const Duration(seconds: 3));
      expect(c.value.controlsVisible, isFalse);
      expect(t.takeException(), isNull);
      await _unmount(t);
      c.dispose();
      await api.dispose();
    });
  }
  testWidgets('拖底栏五秒保持控制条和预览，松手重新计时', (t) async {
    final api = FakeBridgeApi();
    final c = MovaChrome();
    await _mount(t, api, chrome: c);
    c.show();
    await t.pump(const Duration(seconds: 1));
    final gesture = await t.startGesture(t.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(50, 0));
    await t.pump();
    expect(c.value.dragging, isTrue);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(seconds: 1));
      expect(c.value.controlsVisible, isTrue);
      expect(c.value.previewAt, isNotNull);
      expect(find.text(formatDuration(c.value.previewAt!)), findsWidgets);
      expect(
        t
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .map((w) => w.opacity),
        everyElement(1),
      );
    }
    await gesture.up();
    await t.pump();
    expect(c.value.dragging, isFalse);
    expect(c.value.previewAt, isNull);
    await t.pump(const Duration(milliseconds: 2900));
    expect(c.value.controlsVisible, isTrue);
    await t.pump(const Duration(milliseconds: 100));
    expect(c.value.controlsVisible, isFalse);
    await _unmount(t);
    c.dispose();
    await api.dispose();
  });

  testWidgets('隐藏时横滑会唤出控制条，松手三秒后隐藏', (t) async {
    final api = FakeBridgeApi();
    final c = MovaChrome();
    await _mount(t, api, chrome: c);
    c.hide();
    await t.pump();
    final gesture = await t.startGesture(
      t.getCenter(find.byType(MovaPlayer)) + const Offset(-100, 0),
    );
    await gesture.moveBy(const Offset(120, 0));
    await t.pump();
    expect(c.value.dragging, isTrue);
    expect(c.value.controlsVisible, isTrue);
    await gesture.up();
    await t.pump(const Duration(milliseconds: 2900));
    expect(c.value.controlsVisible, isTrue);
    await t.pump(const Duration(milliseconds: 100));
    expect(c.value.controlsVisible, isFalse);
    await _unmount(t);
    c.dispose();
    await api.dispose();
  });

  testWidgets('栏按钮指针和 Enter 激活都续期自动隐藏', (t) async {
    final api = FakeBridgeApi();
    final c = MovaChrome();
    await _mount(t, api, chrome: c);
    c.show();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 2));
      expect(c.value.controlsVisible, isTrue);
      if (i == 2) {
        await _keyboardFit(t);
      } else {
        await t.tap(_fit());
        await t.pump();
      }
    }
    expect(api.calls.where((v) => v == 'setFit'), hasLength(4));
    await t.pump(const Duration(milliseconds: 2900));
    expect(c.value.controlsVisible, isTrue);
    await t.pump(const Duration(milliseconds: 100));
    expect(c.value.controlsVisible, isFalse);
    await _unmount(t);
    c.dispose();
    await api.dispose();
  });

  testWidgets('常显经过拖动和按钮激活仍不计时', (t) async {
    fakeAsync((a) {
      final c = MovaChrome()
        ..show(sticky: true)
        ..setDragging(true)
        ..setDragging(false)
        ..touch();
      expect(a.nonPeriodicTimerCount, 0);
      a.elapse(const Duration(seconds: 10));
      expect(c.value.controlsVisible, isTrue);
      c.dispose();
    });
    final api = FakeBridgeApi();
    final c = MovaChrome();
    await _mount(t, api, chrome: c);
    c.show(sticky: true);
    final gesture = await t.startGesture(t.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(50, 0));
    await gesture.up();
    await t.pump();
    await t.tap(_fit());
    await _keyboardFit(t);
    await t.pump(const Duration(seconds: 10));
    expect(c.value.controlsVisible, isTrue);
    await _unmount(t);
    c.dispose();
    await api.dispose();
  });

  testWidgets('非桥接 API 按钮不新增显示命令，拖动仍走旧接口', (t) async {
    final api = FakeMovaApi();
    await _mount(t, api);
    api.calls.clear();
    await t.tap(_fit());
    expect(api.calls, isNot(contains('showControls')));
    final child = find
        .descendant(of: _fit(), matching: find.byType(GestureDetector))
        .first;
    Focus.of(t.element(child)).requestFocus();
    await t.pump();
    // 聚焦沿用播放器原有的唤出行为，续期自身不能再写旧 API。
    final shows = api.calls.where((v) => v == 'showControls').length;
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(api.calls.where((v) => v == 'setFit'), hasLength(2));
    expect(api.calls.where((v) => v == 'showControls'), hasLength(shows));
    final gesture = await t.startGesture(t.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(50, 0));
    await t.pump();
    expect(api.lastDragging, isTrue);
    expect(api.lastPreviewAt, isNotNull);
    await gesture.up();
    await t.pump();
    expect(api.lastDragging, isFalse);
    expect(api.calls.where((v) => v == 'showControls'), hasLength(shows));
    await _unmount(t);
    await api.dispose();
  });
}
