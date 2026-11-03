import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/cutover/cutover_engine.dart';
import 'package:mova/src/core/cutover/ctl.dart';
import 'package:mova/src/core/cutover/plan.dart';
import 'package:mova/src/core/cutover/trigger.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';

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
  OperationRig() {
    api = MovaCutoverEngine(
      engineFactory: () {
        final engine = FakeMovaApi(
          options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)),
          commandLog: factory.log,
        );
        factory.engines.add(engine);
        return engine;
      },
    );
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

/// 验证提交事务与较新的加载、预热和销毁之间的交错。
void main() {
  late OperationRig rig;
  setUp(() => rig = OperationRig());
  tearDown(() async {
    await rig.api.dispose();
    await settleOperations();
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
    expect(a.calls.where((c) => c == 'play'), hasLength(1));
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
