import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import '../support/fake_api.dart';
import '../support/pump.dart';

/// 提供同步快照但不重放流的宿主替身，用于验证 UI 的同步播种。
class _SnapshotApi extends FakeMovaApi implements MovaProgressSource {
  /// 创建暂停在 30 秒的替身。
  _SnapshotApi({super.options});
  @override
  MovaProg progressValue = const MovaProg(position: Duration(seconds: 30), buffer: Duration(seconds: 40));

  /// 同步记录宿主最新进度，再广播变更。
  @override
  void pushProgress(MovaProg next) {
    progressValue = next;
    super.pushProgress(next);
  }
}

void main() {
  setUp(MovaTesting.useTestKernels);
  tearDown(MovaTesting.reset);

  test('内核进度在无订阅者时仍可同步读取', () async {
    final api = createMovaEngine();
    final k = MovaTesting.lastKernel!;
    k.emitPosition(const Duration(seconds: 30));
    k.emitBuffer(const Duration(seconds: 40));
    await Future<void>.delayed(Duration.zero);
    expect(api.progressValue, const MovaProg(position: Duration(seconds: 30), buffer: Duration(seconds: 40)));
    await api.dispose();
  });

  test('暂停后每个新订阅者都收到当前进度', () async {
    final api = createMovaEngine();
    MovaTesting.lastKernel!.emitPosition(const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);
    await api.pause();
    expect((await api.progress.first).position.inSeconds, 30);
    expect((await api.progress.first).position.inSeconds, 30);
    await api.dispose();
  });

  testWidgets('暂停态重挂载标签和滑块保持当前位置', (t) async {
    final api = _SnapshotApi();
    api.push(const MovaState(duration: Duration(seconds: 100)));
    for (var i = 0; i < 2; i++) {
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
      expect(find.text('00:30'), findsOneWidget);
      expect(t.widget<Slider>(find.byType(Slider)).value, 30000);
      await t.pumpWidget(const SizedBox());
    }
    await api.dispose();
  });

  testWidgets('双击从同步快照计算目标', (t) async {
    final api = _SnapshotApi();
    await pumpComponent(t, api, MovaGestureLayerComponent());
    await t.tapAt(const Offset(700, 300));
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(const Offset(700, 300));
    await t.pumpAndSettle();
    expect(api.lastSeek, const Duration(seconds: 40));
    await api.dispose();
  });

  test('cutover 换指后同步快照及新订阅跟随影子', () async {
    final made = <FakeMovaApi>[];
    final api = MovaCutoverEngine(engineFactory: () {
      final f = _SnapshotApi(options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      made.add(f);
      return f;
    });
    await api.prepare(const MovaSource('https://test/video'), at: const Duration(seconds: 12), plan: MovaWarmPlan(trigger: const MovaEagerWarm(), policy: MovaBufferWarm(stableTicks: 1)));
    made.last.pushProgress(const MovaProg(position: Duration(seconds: 12), buffer: Duration(seconds: 30)));
    await Future<void>.delayed(Duration.zero);
    expect(await api.commit(), isTrue);
    expect(api.progressValue.position.inSeconds, 12);
    expect((await api.progress.first).position.inSeconds, 12);
    await api.dispose();
  });

  testWidgets('不具备同步能力的宿主仍可挂载', (t) async {
    final api = FakeMovaApi();
    await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
    expect(find.text('00:00'), findsWidgets);
    api.pushProgress(const MovaProg(position: Duration(seconds: 15)));
    await t.pump();
    expect(find.text('00:15'), findsOneWidget);
    await api.dispose();
  });
}

