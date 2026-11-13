import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/orient_mode.dart';
import 'package:mova/src/core/platform/platform.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/platform_impl/wiring.dart';
import 'package:mova/src/ui/components/bottom_bar.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/scope/scope.dart';
import 'package:mova/src/ui/scope/selector.dart';
import 'package:mova/src/ui/ui_kits/ui_kit.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/slot.dart';
import 'package:mova/src/ui/slots/tree.dart';

import '../support/fake_api.dart';
import '../support/fake_kernel.dart';

/// 统计组件定义与叶子构建次数的 UI 套件。
class _UiKit implements IMovaUiKit {
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
  _Leaf(this.uiKit);

  /// 所属计数 UI 套件。
  final _UiKit uiKit;

  /// 返回测试路径名。
  @override
  String get name => 'leaf';

  /// 返回测试槽位。
  @override
  MovaSlot get slot => MovaSlot.top;

  /// 计数并读取当前主题，返回主题颜色文本。
  @override
  Widget build(BuildContext context, IMovaApi api, List<Widget> children) {
    uiKit.builds++;
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

  testWidgets('B15 无关宿主重建复用 UI 套件树，surface 改变只重建装配', (t) async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    final uiKit = _UiKit();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, uiKit: uiKit)));
    final baseline = uiKit.builds;
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, uiKit: uiKit)));
    expect(uiKit.definitions, 1);
    expect(uiKit.builds, baseline);
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, uiKit: uiKit, surface: const Text('新画面'))));
    expect(uiKit.definitions, 1);
    expect(find.text('新画面'), findsOneWidget);
  });

  testWidgets('B15 换 api 或 uiKit 刷新定义，主题依赖仍更新', (t) async {
    final a = FakeMovaApi();
    final b = FakeMovaApi();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final uiKit = _UiKit();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: a, uiKit: uiKit)));
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: b, uiKit: uiKit)));
    expect(uiKit.definitions, 2);
    final next = _UiKit();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: b, uiKit: next)));
    expect(next.definitions, 1);
    await t.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: MovaPlayer(api: b, uiKit: next)));
    await t.pumpAndSettle();
    expect(find.text('Brightness.dark'), findsOneWidget);
    expect(next.definitions, 1);
  });

  test('B15 重复 setter 保留写入但不重复发送标量镜像事件', () async {
    final mova = createMova(kernel: FakeKernel(), brightness: MovaFallbackBrightness(),
        pip: MovaNoopPip(), orient: MovaNoopOrient());
    addTearDown(mova.dispose);
    final events = <MovaEvent>[];
    mova.events.listen(events.add);
    for (var i = 0; i < 2; i++) {
      await mova.setFit(MovaFit.cover);
      await mova.setZoom(2);
      await mova.setLocked(true);
      await mova.setRate(2);
      await mova.setVolume(25);
      await mova.setBrightness(0.25);
      await mova.setFullscreen(true);
      await mova.setOrient(MovaOrientMode.landscape);
    }
    await Future<void>.delayed(Duration.zero);
    for (final type in [MovaFitChange, MovaZoomChange, MovaLockChange, MovaRateChange,
      MovaVolumeChange, MovaBrightChange, MovaFullScreenChange, MovaOrientChange]) {
      expect(events.where((e) => e.runtimeType == type), hasLength(1), reason: '$type');
    }
  });

  test('B15 内核重复镜像值只发一次，真实边沿仍发事件', () async {
    final kernel = FakeKernel();
    final mova = createMova(kernel: kernel, pip: MovaNoopPip());
    addTearDown(mova.dispose);
    final events = <MovaEvent>[];
    mova.events.listen(events.add);
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
      final mova = createMova(kernel: FakeKernel(), pip: MovaNoopPip());
      clock.flushMicrotasks();
      mova.showControls();
      mova.showHud(MovaHud.volume);
      expect(clock.nonPeriodicTimerCount, 2);
      unawaited(mova.dispose());
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(seconds: 4));
      clock.flushMicrotasks();
    });
  });
}
