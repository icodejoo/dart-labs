
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';

import '../../support/fake_kernel.dart';

/// 直播 duration 持续增长时 MovaDurationChange 的节流：变化不足 durationStep 的更新被吞掉。
void main() {
  late FakeKernel kernel;
  late MovaEngine engine;
  late List<MovaDurationChange> changes;

  Future<void> setUp0({MovaLiveConfig live = const MovaLiveConfig(), MovaStreamType type = MovaStreamType.live}) async {
    kernel = FakeKernel();
    engine = MovaEngine(kernel: kernel, options: MovaOpts(live: live));
    changes = [];
    addTearDown(engine.dispose);
    engine.events.listen((e) {
      if (e is MovaDurationChange) changes.add(e);
    });
    await engine.open(MovaSource('https://h/a', type: type));
  }

  /// 以 [stepMs] 毫秒为步长推送 [n] 次递增的 duration，起点 [startMs]。
  Future<void> grow({required int startMs, required int n, int stepMs = 100}) async {
    for (var i = 0; i < n; i++) {
      kernel.emitDuration(Duration(milliseconds: startMs + i * stepMs));
    }
    await Future<void>.delayed(Duration.zero);
  }

  test('默认 durationStep 为 2 秒；copyWith / == / hashCode 带上该字段', () {
    expect(const MovaLiveConfig().durationStep, const Duration(seconds: 2));
    const c = MovaLiveConfig();
    expect(c.copyWith(durationStep: const Duration(seconds: 5)).durationStep, const Duration(seconds: 5));
    expect(c.copyWith().durationStep, c.durationStep);
    expect(c, isNot(c.copyWith(durationStep: Duration.zero)));
    expect(c.hashCode, isNot(c.copyWith(durationStep: Duration.zero).hashCode));
  });

  test('直播：10 分钟内每 100ms 增长一次，事件数按阈值收敛而不是每次都发', () async {
    await setUp0();
    await grow(startMs: 1000, n: 6000); // 10 分钟，每 100ms 一次
    expect(changes.length, lessThan(6000 / 15), reason: '2s 阈值下最多约 300 次');
    expect(changes.length, greaterThan(100));
    // 相邻两次上报至少相差 durationStep。
    for (var i = 1; i < changes.length; i++) {
      expect((changes[i].duration - changes[i - 1].duration).abs(), greaterThanOrEqualTo(const Duration(seconds: 2)));
    }
  });

  test('直播：第一次非零 duration 立刻上报，state.duration 与事件一致', () async {
    await setUp0();
    await grow(startMs: 1500, n: 1);
    expect(changes.single.duration, const Duration(milliseconds: 1500));
    expect(engine.state.duration, const Duration(milliseconds: 1500));
    await grow(startMs: 1600, n: 5); // 仅增长 0.5s，不足阈值
    expect(changes, hasLength(1));
    expect(engine.state.duration, const Duration(milliseconds: 1500));
  });

  test('直播：回落到 0（换流重置）与反向跳变超过阈值都会上报', () async {
    await setUp0();
    await grow(startMs: 60000, n: 1);
    kernel.emitDuration(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(changes.last.duration, Duration.zero);
    await grow(startMs: 5000, n: 1);
    expect(changes.last.duration, const Duration(seconds: 5));
    await grow(startMs: 1000, n: 1); // 向下跳 4s
    expect(changes.last.duration, const Duration(seconds: 1));
  });

  test('durationStep 为 0：关闭节流，每次变化都上报', () async {
    await setUp0(live: const MovaLiveConfig(durationStep: Duration.zero));
    await grow(startMs: 1000, n: 50);
    expect(changes, hasLength(50));
  });

  test('点播：行为不变，每次 duration 回调都上报', () async {
    await setUp0(type: MovaStreamType.vod);
    await grow(startMs: 1000, n: 50);
    expect(changes, hasLength(50));
  });

  test('重新 open() 后基线清零：新源的第一次 duration 即使与旧值接近也会上报', () async {
    await setUp0();
    await grow(startMs: 60000, n: 1);
    expect(changes, hasLength(1));
    await engine.open(const MovaSource('https://h/b', type: MovaStreamType.live));
    await grow(startMs: 60500, n: 1);
    expect(changes, hasLength(2));
  });
}
