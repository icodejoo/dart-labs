import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/cutover/cutover_engine.dart';
import 'package:mova/src/core/cutover/ctl.dart';
import 'package:mova/src/core/cutover/plan.dart';
import 'package:mova/src/core/cutover/trigger.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';

import '../../support/fake_api.dart';
import '../../support/gated.dart';

/// 让流事件与异步动词结算，不等待真实媒体或设备。
Future<void> settleOperations() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 使用 S01 命令日志与门控替身运行真实切换代理。
class OperationRig {
  /// 创建启用切换的测试环境；所有影子保留在工厂记录中。
  OperationRig({void Function(DetachGatedApi engine)? configure}) {
    api = MovaCutoverEngine(
      engineFactory: () {
        final engine = DetachGatedApi(
          options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)),
          commandLog: factory.log,
        );
        configure?.call(engine);
        factory.engines.add(engine);
        return engine;
      },
    );
    factory.engines.first.push(factory.engines.first.state.copyWith(playbackIntent: true));
  }

  /// S01 脚手架提供跨实例日志与释放记录。
  final GatedEngineFactory factory = GatedEngineFactory();

  /// 被测的真实代理。
  late final MovaCutoverEngine api;

  /// 当前所有替身。
  List<FakeMovaApi> get engines => factory.engines;

  /// 令指定影子达到默认连续两次的就绪判据。
  Future<void> ready(FakeMovaApi shadow) async {
    const tick = MovaProg(position: Duration(seconds: 1), buffer: Duration(seconds: 10));
    shadow.pushProgress(tick);
    await settleOperations();
    shadow.pushProgress(tick);
    await settleOperations();
  }

  /// 立即预热指定源并返回影子；可选等待就绪后返回。
  Future<FakeMovaApi> warm(String name, {bool readyNow = true, bool hold = false}) async {
    await api.prepare(
      MovaSource('https://host/$name.mp4'),
      plan: MovaWarmPlan(trigger: const MovaEagerWarm(), pauseWhenReady: hold),
    );
    final shadow = engines.last;
    if (readyNow) await ready(shadow);
    return shadow;
  }
}

/// 在真实转发订阅取消处设置门闩，不替换切换逻辑。
class DetachGatedApi extends FakeMovaApi {
  /// 沿用共享日志与选项。
  DetachGatedApi({super.options, super.commandLog});

  /// 转发状态订阅取消时等待的门闩。
  Completer<void>? detachGate;

  /// 可选的释放错误，用于验证代理最终关闭全部流。
  bool throwOnDispose = false;

  /// 用可等待的取消回调暴露 detach 的 await 点。
  @override
  Stream<MovaState> get states => Stream<MovaState>.multi((controller) {
    final sub = super.states.listen(controller.add, onDone: controller.close);
    controller.onCancel = () async {
      await sub.cancel();
      await detachGate?.future;
    };
  });

  /// 先释放资源，再模拟内核释放错误。
  @override
  Future<void> dispose() async {
    await super.dispose();
    if (throwOnDispose) throw StateError('dispose failed');
  }
}

/// Verifies commit interleavings with newer loads, warm-ups and disposal.
///
/// 验证提交事务与较新的加载、预热和销毁之间的交错。
void main() {
  late OperationRig rig;
  setUp(() => rig = OperationRig());
  tearDown(() async {
    await rig.api.dispose();
    await settleOperations();
  });

  for (final point in ['pause', 'holding', 'play', 'detach']) {
    for (final releaseCFirst in [true, false]) {
      test('F1 提交独占 $point，C 门闩先释放=$releaseCFirst', () async {
        final old = rig.engines.first as DetachGatedApi;
        old.pushPlayingOnVerbs = true;
        await old.play();
        final a = await rig.warm('A', readyNow: false, hold: point == 'holding');
        a.pushPlayingOnVerbs = true;
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        if (point == 'pause') old.pauseGate = gate;
        if (point == 'holding') a.pauseGate = gate;
        await rig.ready(a);
        if (point == 'play') a.playGate = gate;
        if (point == 'detach') old.detachGate = gate;
        final first = rig.api.commit();
        await settleOperations();
        final c = await rig.warm('C');
        c.pushPlayingOnVerbs = true;
        final cGate = c.playGate = Completer<void>();
        addTearDown(() {
          if (!cGate.isCompleted) cGate.complete();
        });
        var cFinished = false;
        final second = rig.api.commit().then((ok) {
          cFinished = true;
          return ok;
        });
        if (releaseCFirst) cGate.complete();
        await settleOperations();
        expect(cFinished, isFalse, reason: 'C 不得越过 A 的换指事务');
        gate.complete();
        expect(await first, isTrue);
        if (!releaseCFirst) cGate.complete();
        expect(await second, isTrue);
        await settleOperations();
        expect(rig.api.active, same(c));
        expect(rig.api.cutoverPhase, MovaCutoverPhase.idle);
        expect(old.disposeCount, 1);
        expect(a.disposeCount, 1);
        expect(c.disposeCount, 0);
        expect(rig.engines.where((e) => !e.disposed && e.state.playing), [c]);
        c.push(c.state.copyWith(volume: 23));
        c.pushProgress(const MovaProg(position: Duration(seconds: 7)));
        await settleOperations();
        expect(rig.api.state.volume, 23);
        expect(rig.api.progressValue.position, const Duration(seconds: 7));
      });
    }
  }

  for (final pauseAfterExpiry in [false, true]) {
    test('F-M 被 cutoverTo 取代后继承意图，随后显式暂停=$pauseAfterExpiry', () async {
      final old = rig.engines.first;
      final x = await rig.warm('X');
      final gate = x.playGate = Completer<void>();
      addTearDown(() { if (!gate.isCompleted) gate.complete(); });
      final first = rig.api.commit();
      await settleOperations();
      expect(old.state.playbackIntent, isFalse, reason: '内部 pause 已发生');
      final second = rig.api.cutoverTo(const MovaSource('https://host/Y.mp4'));
      await settleOperations();
      final y = rig.engines.last;
      if (!pauseAfterExpiry) await rig.ready(y);
      gate.complete();
      expect(await first, isFalse);
      if (pauseAfterExpiry) {
        await rig.api.pause();
        await rig.ready(y);
      }
      expect(await second, isTrue);
      expect(rig.api.active, same(y));
      expect(y.state.playbackIntent, !pauseAfterExpiry);
      expect(y.calls, contains(pauseAfterExpiry ? 'pause' : 'play'));
    });
  }

  test('F6 cutoverTo 的 open 挂起时 prepare 换槽，只回落自己的源', () async {
    final gate = Completer<void>();
    var count = 0;
    final local = OperationRig(
      configure: (engine) {
        if (count++ == 1) engine.openGate = gate;
      },
    );
    final switching = local.api.cutoverTo(const MovaSource('https://host/X.mp4'));
    await settleOperations();
    final x = local.engines.last;
    final c = await local.warm('C');
    gate.complete();
    expect(await switching, isFalse);
    expect(local.api.active, same(local.engines.first));
    expect(local.engines.first.source!.uri, 'https://host/X.mp4');
    expect(c.calls.where((v) => v == 'play'), isEmpty);
    expect(x.disposeCount, 1);
    await local.api.dispose();
    expect(c.disposeCount, 1);
  });

  for (final point in ['pause', 'seek']) {
    for (final ending in ['commit', 'abandon', 'dispose']) {
      test('F3 holding $point 抛错不阻断 $ending 和释放', () async {
        final shadow = await rig.warm('A', readyNow: false, hold: true);
        final gate = Completer<void>();
        if (point == 'pause') shadow.pauseGate = gate;
        if (point == 'seek') shadow.seekGate = gate;
        await rig.ready(shadow);
        gate.completeError(StateError('holding failed'));
        await settleOperations();
        if (ending == 'commit') {
          expect(await rig.api.commit(), isTrue);
          await rig.api.dispose();
        } else if (ending == 'abandon') {
          await rig.api.abandon();
          expect(rig.api.cutoverPhase, MovaCutoverPhase.idle);
          await rig.api.dispose();
        } else {
          await rig.api.dispose();
        }
        expect(shadow.disposeCount, 1);
        expect(rig.engines.first.disposeCount, 1);
        await rig.api.dispose();
      });
    }
  }

  test('F3 槽释放抛错仍释放 active 并关闭全部流', () async {
    final shadow = await rig.warm('A') as DetachGatedApi;
    shadow.throwOnDispose = true;
    final closed = <String>[];
    final subscriptions = [
      rig.api.states.listen((_) {}, onDone: () => closed.add('state')),
      rig.api.uiStates.listen((_) {}, onDone: () => closed.add('ui')),
      rig.api.progress.listen((_) {}, onDone: () => closed.add('progress')),
      rig.api.events.listen((_) {}, onDone: () => closed.add('events')),
      rig.api.cutoverPhases.listen((_) {}, onDone: () => closed.add('phases')),
    ];
    await expectLater(rig.api.dispose(), throwsStateError);
    await settleOperations();
    expect(rig.engines.first.disposeCount, 1);
    expect(shadow.disposeCount, 1);
    expect(closed, hasLength(5));
    for (final sub in subscriptions) {
      await sub.cancel();
    }
  });

  for (final command in ['open', 'reload', 'dispose']) {
    test('commit 卡在旧 pause 时 $command 作废认领，影子只释放一次', () async {
      final shadow = await rig.warm('A');
      final old = rig.engines.first;
      old.pauseGate = Completer<void>();
      final committing = rig.api.commit();
      await settleOperations();
      if (command == 'open') {
        await rig.api.open(const MovaSource('https://host/B.mp4'));
      } else if (command == 'reload') {
        await rig.api.reload();
      } else {
        await rig.api.dispose();
      }
      old.pauseGate!.complete();
      expect(await committing, isFalse);
      expect(shadow.disposeCount, 1);
      expect(rig.api.active, same(old));
      if (command == 'open') expect(old.source!.uri, 'https://host/B.mp4');
    });
  }

  test('旧 commit 完成后保留 prepare C 的计划、相位与订阅', () async {
    final a = await rig.warm('A');
    rig.engines.first.pauseGate = Completer<void>();
    final committing = rig.api.commit();
    await settleOperations();
    final c = await rig.warm('C', readyNow: false);
    rig.engines.first.pauseGate!.complete();
    expect(await committing, isTrue);
    expect(rig.api.active, same(a));
    expect(rig.api.cutoverPhase, MovaCutoverPhase.warming);
    await rig.ready(c);
    expect(rig.api.cutoverPhase, MovaCutoverPhase.ready);
    expect(await rig.api.commit(), isTrue);
    expect(rig.api.active, same(c));
    await settleOperations();
    expect(a.disposeCount, 1);
  });

  test('提交影子 play 挂起时新 prepare 不被收尾释放', () async {
    final a = await rig.warm('A');
    a.playGate = Completer<void>();
    final committing = rig.api.commit();
    await settleOperations();
    final c = await rig.warm('C');
    a.playGate!.complete();
    expect(await committing, isTrue);
    expect(rig.api.cutoverPhase, MovaCutoverPhase.ready);
    await rig.api.dispose();
    expect(c.disposeCount, 1);
    expect(a.disposeCount, 1);
  });

  test('影子 play 挂起时 open B 禁止旧换指', () async {
    final a = await rig.warm('A');
    a.playGate = Completer<void>();
    final committing = rig.api.commit();
    await settleOperations();
    await rig.api.open(const MovaSource('https://host/B.mp4'));
    a.playGate!.complete();
    expect(await committing, isFalse);
    expect(a.disposeCount, 1);
    expect(rig.engines.first.source!.uri, 'https://host/B.mp4');
  });

  test('等待 holding 时 open B 只释放旧槽', () async {
    final a = await rig.warm('A', readyNow: false, hold: true);
    a.pauseGate = Completer<void>();
    await rig.ready(a);
    final committing = rig.api.commit();
    await settleOperations();
    await rig.api.open(const MovaSource('https://host/B.mp4'));
    a.pauseGate!.complete();
    expect(await committing, isFalse);
    expect(a.disposeCount, 1);
    expect(a.calls.where((c) => c == 'play'), isEmpty);
  });

  test('并发 cutoverTo X/Y 只有 Y 换指，X 不回落抢源', () async {
    final x = rig.api.cutoverTo(const MovaSource('https://host/X.mp4'));
    await settleOperations();
    final firstShadow = rig.engines.last;
    final y = rig.api.cutoverTo(const MovaSource('https://host/Y.mp4'));
    await settleOperations();
    final lastShadow = rig.engines.last;
    await rig.ready(lastShadow);
    expect(await x, isFalse);
    expect(await y, isTrue);
    expect(rig.api.active, same(lastShadow));
    expect(firstShadow.disposeCount, 1);
    expect(rig.engines.first.calls.where((c) => c == 'open'), isEmpty);
  });

  test('等待 ready 的两个 commit 被 open B 同时唤醒', () async {
    final a = await rig.warm('A', readyNow: false);
    final first = rig.api.commit(waitForReady: true);
    final second = rig.api.commit(waitForReady: true);
    await rig.api.open(const MovaSource('https://host/B.mp4'));
    expect(await first, isFalse);
    expect(await second, isFalse);
    await settleOperations();
    expect(a.disposeCount, 1);
  });

  test('影子 open 挂起时 open B，迟到 prepare 不再装订阅', () async {
    // 在工厂创建影子后、open 返回前挂门闩。
    final gate = Completer<void>();
    final shadow = FakeMovaApi(options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)))
      ..openGate = gate;
    final active = FakeMovaApi(options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
    var calls = 0;
    final api = MovaCutoverEngine(engineFactory: () => calls++ == 0 ? active : shadow);
    final preparing = api.prepare(
      const MovaSource('https://host/A.mp4'),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    await settleOperations();
    await api.open(const MovaSource('https://host/B.mp4'));
    gate.complete();
    await preparing;
    await settleOperations();
    expect(api.cutoverPhase, MovaCutoverPhase.idle);
    expect(shadow.disposeCount, 1);
    await api.dispose();
  });

  test('同一 ready 影子只能被一个 commit 认领', () async {
    final a = await rig.warm('A');
    final results = await Future.wait([rig.api.commit(), rig.api.commit()]);
    expect(results.where((r) => r), hasLength(1));
    expect(rig.api.active, same(a));
    expect(rig.api.state.renderEpoch, 1);
    expect(a.disposeCount, 0);
  });

  test('cutoverTo 等 ready 时 dispose 不回落 open', () async {
    final switching = rig.api.cutoverTo(const MovaSource('https://host/A.mp4'));
    await settleOperations();
    final a = rig.engines.last;
    await rig.api.dispose();
    expect(await switching, isFalse);
    expect(a.disposeCount, 1);
    expect(rig.engines.first.calls.where((c) => c == 'open'), isEmpty);
  });
}
