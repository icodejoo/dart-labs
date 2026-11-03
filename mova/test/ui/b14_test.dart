import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/ui/components/common.dart';
import 'package:mova/src/ui/components/gesture_layer.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/skins/default_skin.dart';
import 'package:mova/src/ui/slots/patch.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  for (final left in [true, false]) {
    testWidgets('B14 vSensitivity 对${left ? '亮度' : '音量'}增量生效', (t) async {
      final values = <double>[];
      for (final sensitivity in [0.5, 1.0, 2.0]) {
        final api = FakeMovaApi(options: MovaOpts(gesture: MovaGestureConfig(vSensitivity: sensitivity)));
        addTearDown(api.dispose);
        api.push(const MovaState(volume: 20, brightness: 0.2));
        await t.pumpWidget(const SizedBox.shrink());
        await pumpComponent(t, api, MovaGestureLayerComponent());
        await t.dragFrom(Offset(left ? 200 : 600, 300), const Offset(0, -80));
        await t.pumpAndSettle();
        values.add((left ? api.lastBrightness! - 0.2 : (api.lastVolume! - 20) / 100));
      }
      expect(values[1], closeTo(values[0] * 2, 0.001));
      expect(values[2], closeTo(values[0] * 4, 0.001));
    });
  }

  testWidgets('B14 横轴音量不受竖滑灵敏度影响', (t) async {
    final values = <double>[];
    for (final sensitivity in [1.0, 3.0]) {
      final api = FakeMovaApi(options: MovaOpts(gesture: MovaGestureConfig(
        horizontal: MovaGestureAction.volume, vSensitivity: sensitivity,
      )));
      addTearDown(api.dispose);
      api.push(const MovaState(volume: 20));
      await t.pumpWidget(const SizedBox.shrink());
      await pumpComponent(t, api, MovaGestureLayerComponent());
      await t.dragFrom(const Offset(400, 300), const Offset(100, 0));
      await t.pumpAndSettle();
      values.add(api.lastVolume!);
    }
    expect(values[0], greaterThan(20));
    expect(values[0], values[1]);
  });

  testWidgets('B14 allowWhenLive 关闭仍允许音量和亮度', (t) async {
    final api = FakeMovaApi(options: const MovaOpts(gesture: MovaGestureConfig(allowWhenLive: false)));
    addTearDown(api.dispose);
    api.push(const MovaState(type: MovaStreamType.live, volume: 20, brightness: 0.2));
    await pumpComponent(t, api, MovaGestureLayerComponent());
    await t.dragFrom(const Offset(200, 300), const Offset(0, -80));
    await t.dragFrom(const Offset(600, 300), const Offset(0, -80));
    await t.pumpAndSettle();
    expect(api.lastBrightness, greaterThan(0.2));
    expect(api.lastVolume, greaterThan(20));
    expect(api.calls, isNot(contains('seek')));
  });

  test('B14 各类 patch 诊断完整路径并按前一个补丁后的树检查', () {
    for (final patch in [
      const MovaPatch.remove('topBar/missing'),
      MovaPatch.replace('topBar/missing', MovaGestureLayerComponent()),
      MovaPatch.insertAfter('topBar/missing', MovaGestureLayerComponent()),
      const MovaPatch.remove('topBar/'),
    ]) {
      expect(() => MovaDefaultSkin(patches: [patch]).components(), throwsAssertionError);
    }
    expect(() => const MovaDefaultSkin(patches: [
      MovaPatch.remove('topBar'), MovaPatch.remove('topBar/pipButton'),
    ]).components(), throwsAssertionError);
    expect(() => const MovaDefaultSkin(patches: [
      MovaPatch.remove('topBar/pipButton'), MovaPatch.remove('topBar'),
    ]).components(), returnsNormally);
  });

  testWidgets('B14 锁定按钮可从组件树移除', (t) async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: const MovaDefaultSkin(
      patches: [MovaPatch.remove(MovaLockToggleComponent.componentName)],
    ))));
    expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
    api.push(const MovaState(locked: true));
    await t.pump();
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets('B14 锁定入口随控制条隐藏，解锁保持可达，PiP 和 mini 隐藏', (t) async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    api.pushUi(const MovaUiState(controlsVisible: false));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.lock_open_rounded).hitTestable(), findsNothing);
    api.push(const MovaState(locked: true));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.lock_rounded).hitTestable(), findsOneWidget);
    for (final state in [const MovaState(locked: true, pip: true), const MovaState(locked: true, mini: true)]) {
      api.push(state);
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    }
  });

  testWidgets('B14 长选项列表可以滚动并选择末项', (t) async {
    var picked = -1;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      return TextButton(onPressed: () => showMovaOptionSheet(context, const MovaTheme(), [
        for (var i = 0; i < 40; i++) MovaSheetItem(label: '选项$i', checked: false, onSelected: () => picked = i),
      ]), child: const Text('打开'));
    }))));
    await t.tap(find.text('打开'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('选项39'), 300);
    await t.tap(find.text('选项39'));
    await t.pumpAndSettle();
    expect(picked, 39);
  });
}
