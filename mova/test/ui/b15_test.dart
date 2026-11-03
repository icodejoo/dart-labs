import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/platform/ports.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/platform_impl/wiring.dart';
import 'package:mova/src/ui/components/bottom_bar.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/scope/selector.dart';
import 'package:mova/src/ui/skins/skin.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/slot.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';
import '../support/fake_kernel.dart';

/// 统计组件定义与叶子构建次数的皮肤。
class _Skin implements MovaSkin {
  /// 组件定义调用次数。
  int definitions = 0;

  /// 叶子构建次数。
  int builds = 0;

  /// 返回可观察的叶子组件。
  @override
  List<MovaComponent> components() {
    definitions++;
    return [_Leaf(this)];
  }

  /// 将画面和测试叶子装配为层叠布局。
  @override
  Widget assemble(BuildContext context, MovaSlotBundle slots, Widget video) =>
      Stack(children: [video, ...slots[MovaSlot.top]]);
}

/// 读取主题以检查缓存仍响应 inherited 依赖。
class _Leaf extends MovaComponent {
  /// 创建关联计数器的叶子。
  _Leaf(this.skin);

  /// 所属计数皮肤。
  final _Skin skin;

  /// 返回测试路径名。
  @override
  String get name => 'leaf';

  /// 返回测试槽位。
  @override
  MovaSlot get slot => MovaSlot.top;

  /// 计数并读取当前主题，返回主题颜色文本。
  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    skin.builds++;
    return Text('${Theme.of(context).brightness}');
  }
}

void main() {
  testWidgets('B15 位置标签同秒不重建，跨秒和后退仍更新', (t) async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    var builds = 0;
    await t.pumpWidget(MaterialApp(home: MovaScope(api: api, child: Builder(builder: (context) {
      final select = MovaPositionLabelComponent().build(context, api, []) as MovaProgSelect<int>;
      return MovaProgSelect<int>(selector: select.selector, builder: (context, value) {
        builds++;
        return select.builder(context, value);
      });
    }))));
    api.pushProgress(const MovaProg(position: Duration(milliseconds: 1100)));
    await t.pumpAndSettle();
    final baseline = builds;
    for (final ms in [1200, 1400, 1800]) {
      api.pushProgress(MovaProg(position: Duration(milliseconds: ms)));
      await t.pumpAndSettle();
    }
    expect(builds, baseline);
    expect(find.text('00:01'), findsOneWidget);
    for (final seconds in [2, 0]) {
      api.pushProgress(MovaProg(position: Duration(seconds: seconds)));
      await t.pumpAndSettle();
      expect(find.text('00:0$seconds'), findsOneWidget);
    }
    expect(builds, baseline + 2);
  });

  testWidgets('B15 无关宿主重建复用皮肤树，surface 改变只重建装配', (t) async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    final skin = _Skin();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: skin)));
    final baseline = skin.builds;
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: skin)));
    expect(skin.definitions, 1);
    expect(skin.builds, baseline);
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, skin: skin, surface: const Text('新画面'))));
    expect(skin.definitions, 1);
    expect(find.text('新画面'), findsOneWidget);
  });

  testWidgets('B15 换 api 或 skin 刷新定义，主题依赖仍更新', (t) async {
    final a = FakeMovaApi();
    final b = FakeMovaApi();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final skin = _Skin();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: a, skin: skin)));
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: b, skin: skin)));
    expect(skin.definitions, 2);
    final next = _Skin();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: b, skin: next)));
    expect(next.definitions, 1);
    await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: MovaPlayer(api: b, skin: next)));
    await t.pumpAndSettle();
    expect(find.text('Brightness.dark'), findsOneWidget);
    expect(next.definitions, 1);
  });

  test('B15 重复 setter 保留写入但不重复发送标量镜像事件', () async {
    final engine = createMovaEngine(kernel: FakeKernel(), brightness: MovaFallbackBrightnessPort(),
        pip: MovaNoopPipPort(), orientation: MovaNoopOrientationPort());
    addTearDown(engine.dispose);
    final events = <MovaEvent>[];
    engine.events.listen(events.add);
    for (var i = 0; i < 2; i++) {
      await engine.setFit(MovaFit.cover);
      await engine.setZoom(2);
      await engine.setLocked(true);
      await engine.setRate(2);
      await engine.setVolume(25);
      await engine.setBrightness(0.25);
      await engine.setFullscreen(true);
      await engine.setOrientation(MovaOrientation.landscape);
    }
    await Future<void>.delayed(Duration.zero);
    for (final type in [MovaFitChange, MovaZoomChange, MovaLockChange, MovaRateChange,
      MovaVolumeChange, MovaBrightChange, MovaFullScreenChange, MovaOrientationChange]) {
      expect(events.where((e) => e.runtimeType == type), hasLength(1), reason: '$type');
    }
  });

  test('B15 内核重复镜像值只发一次，真实边沿仍发事件', () async {
    final kernel = FakeKernel();
    final engine = createMovaEngine(kernel: kernel, pip: MovaNoopPipPort());
    addTearDown(engine.dispose);
    final events = <MovaEvent>[];
    engine.events.listen(events.add);
    for (var i = 0; i < 2; i++) {
      kernel.emitPlaying(true);
      kernel.emitBuffering(true);
      kernel.emitDuration(const Duration(seconds: 20));
      kernel.emitSize(640, 360);
      kernel.emitCompleted(true);
      await Future<void>.delayed(Duration.zero);
    }
    for (final type in [MovaPlay, MovaBufferChange, MovaDurationChange, MovaSizeChange, MovaDone]) {
      expect(events.where((e) => e.runtimeType == type), hasLength(1), reason: '$type');
    }
    kernel.emitPlaying(false);
    kernel.emitBuffering(false);
    kernel.emitCompleted(false);
    await Future<void>.delayed(Duration.zero);
    kernel.emitCompleted(true);
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<MovaPause>(), hasLength(1));
    expect(events.whereType<MovaBufferChange>(), hasLength(2));
    expect(events.whereType<MovaDone>(), hasLength(2));
  });

  test('B15 dispose 返回 Future 前即取消 HUD 与控制条计时器', () {
    fakeAsync((clock) {
      final engine = createMovaEngine(kernel: FakeKernel(), pip: MovaNoopPipPort());
      clock.flushMicrotasks();
      engine.showControls();
      engine.showHud(MovaHud.volume);
      expect(clock.nonPeriodicTimerCount, 2);
      unawaited(engine.dispose());
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(seconds: 4));
      clock.flushMicrotasks();
    });
  });
}
