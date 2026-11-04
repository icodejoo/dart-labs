import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/manual_clock.dart';

/// 单步推进的帧长；与 60Hz 接近，保证多数帧之间跨不过一个整秒。
const _frame = Duration(milliseconds: 16);

/// 一秒的毫秒数。
const _msPerSecond = 1000;

/// 记录 tick 次数的倒计时，用来断言休眠期间没有出帧。
class _SpyCountdown extends Countdown {
  /// [name] 同 [Countdown]，[interval] 默认一秒。
  _SpyCountdown({super.name, super.interval});

  /// 自创建以来 tick 被调用的次数。
  int ticks = 0;

  @override
  int tick(Duration elapsed, Duration dt) {
    ticks++;
    return super.tick(elapsed, dt);
  }
}

/// 按脚本返回唤醒时间的插件，同时记录每次收到的 dt。
class _ScriptedPlugin implements CountmanPlugin {
  /// [wakes] 依次作为每次 tick 的返回值，用尽后返回 idle。
  _ScriptedPlugin(this.name, this.wakes);

  @override
  final String name;

  /// 剩余的脚本返回值。
  final List<int> wakes;

  /// 每次 tick 收到的 dt。
  final dts = <Duration>[];

  /// 注册时拿到的上下文。
  late CountmanContext ctx;

  @override
  void onAttach(CountmanContext c) => ctx = c;

  @override
  void onDetach() {}

  @override
  int tick(Duration elapsed, Duration dt) {
    dts.add(dt);
    return wakes.isEmpty ? CountmanPlugin.idle : wakes.removeAt(0);
  }

  @override
  void dispose() {}
}

/// 验证唤醒时间驱动的休眠调度：不逐 vsync 出帧、按需取消休眠、逐任务边界更新。
void main() {
  late ManualCountmanClock clock;

  setUp(() {
    clock = installManualClock();
  });
  tearDown(Countman.destroy);

  /// 同时推进手动时钟与测试的假时间，再出一帧。
  Future<void> step(WidgetTester t, Duration d) async {
    clock.advance(d);
    await t.pump(d);
  }

  group('休眠调度', () {
    testWidgets('1 秒倒计时处理一次后不再排帧而挂 Timer，约 1 秒后只出一帧', (t) async {
      final plugin = _SpyCountdown(name: 'sleepy');
      final seconds = <int>[];
      plugin.add(
        CountdownOptions(
          duration: const Duration(seconds: 10),
          onUpdate: (p) => seconds.add(p.inSeconds),
        ),
      );
      clock.advance(const Duration(milliseconds: 500)); // 首帧在剩余 9.5s
      await t.pump();
      expect(seconds, [9]);
      expect(plugin.ticks, 1);
      expect(Countman.isRunning, isTrue);
      expect(Countman.isSleeping, isTrue);
      expect(t.binding.hasScheduledFrame, isFalse);

      // 距离下一次换桶还有约 0.5s，期间任何帧都不会触达插件。
      await t.pump(const Duration(milliseconds: 250));
      await t.pump(const Duration(milliseconds: 200));
      expect(plugin.ticks, 1);
      expect(Countman.isSleeping, isTrue);

      clock.advance(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 100));
      expect(plugin.ticks, 2);
      expect(seconds, [9, 8]);
      expect(Countman.isSleeping, isTrue);
      Countman.destroy();
    });

    testWidgets('休眠期间新增任务会取消休眠并立即排帧', (t) async {
      final plugin = _SpyCountdown(name: 'wake-on-add');
      plugin.add(const CountdownOptions(duration: Duration(seconds: 10)));
      clock.advance(const Duration(milliseconds: 500));
      await t.pump();
      expect(Countman.isSleeping, isTrue);

      final added = <int>[];
      plugin.add(
        CountdownOptions(
          duration: const Duration(seconds: 5),
          onUpdate: (p) => added.add(p.inMilliseconds),
        ),
      );
      expect(Countman.isSleeping, isFalse);
      expect(t.binding.hasScheduledFrame, isTrue);
      await t.pump();
      expect(added, [5000]); // 新任务按加入时刻锚定，首帧显示完整 5s
      Countman.destroy();
    });

    testWidgets('控制器 resume 同样取消休眠', (t) async {
      final plugin = _SpyCountdown(name: 'wake-on-resume');
      final h = plugin.add(
        const CountdownOptions(duration: Duration(seconds: 10)),
      );
      clock.advance(const Duration(milliseconds: 500));
      await t.pump();
      h.pause();
      h.resume();
      expect(Countman.isSleeping, isFalse);
      expect(t.binding.hasScheduledFrame, isTrue);
      Countman.destroy();
    });

    testWidgets('取消休眠中的最后一个任务后不再挂着定时器', (t) async {
      final plugin = _SpyCountdown(name: 'cancel-last');
      final h = plugin.add(
        const CountdownOptions(duration: Duration(seconds: 10)),
      );
      clock.advance(const Duration(milliseconds: 500));
      await t.pump();
      expect(Countman.isSleeping, isTrue);
      h.cancel();
      expect(Countman.isSleeping, isFalse);
      await t.pump();
      expect(Countman.isRunning, isFalse);
    });

    testWidgets('唤醒时间不超过 20ms 时直接排帧，不挂 Timer', (t) async {
      final plugin = _SpyCountdown(name: 'short-wake');
      plugin.add(const CountdownOptions(duration: Duration(seconds: 10)));
      clock.advance(const Duration(milliseconds: 985)); // 剩余 9.015s，距换桶 15ms
      await t.pump();
      expect(Countman.isSleeping, isFalse);
      expect(t.binding.hasScheduledFrame, isTrue);
      Countman.destroy();
    });

    testWidgets('interval 为 0 时每帧都处理且从不休眠', (t) async {
      final plugin = _SpyCountdown(name: 'every-frame', interval: 0);
      plugin.add(const CountdownOptions(duration: Duration(seconds: 10)));
      await t.pump();
      for (var i = 0; i < 5; i++) {
        await step(t, _frame);
      }
      expect(plugin.ticks, 6);
      expect(Countman.isSleeping, isFalse);
      Countman.destroy();
    });

    testWidgets('全部 idle 时停表，没有残留定时器', (t) async {
      final plugin = _SpyCountdown(name: 'finish');
      var done = false;
      plugin.add(
        CountdownOptions(
          duration: const Duration(seconds: 2),
          onComplete: () => done = true,
        ),
      );
      await t.pump();
      await step(t, const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      expect(done, isTrue);
      expect(Countman.isRunning, isFalse);
      expect(Countman.isSleeping, isFalse);
    });

    testWidgets('多个插件取最小唤醒时间；休眠后的首帧 dt 为 0', (t) async {
      final slow = _ScriptedPlugin('slow', [5000000]);
      final fast = _ScriptedPlugin('fast', [100000]);
      Countman.use(slow);
      Countman.use(fast);
      fast.ctx.requestFrame();
      await t.pump();
      expect(Countman.isSleeping, isTrue);
      expect(slow.dts, hasLength(1));

      await t.pump(const Duration(milliseconds: 50));
      expect(fast.dts, hasLength(1)); // 100ms 未到
      await t.pump(const Duration(milliseconds: 60));
      expect(fast.dts, hasLength(2));
      expect(fast.dts.last, Duration.zero); // 休眠醒来的首帧，dt 视为 0
      expect(Countman.isRunning, isFalse); // 第二次两者都返回 idle
    });

    testWidgets('stop 与 destroy 都会取消休眠定时器', (t) async {
      final plugin = _SpyCountdown(name: 'stop-sleep');
      plugin.add(const CountdownOptions(duration: Duration(seconds: 10)));
      clock.advance(const Duration(milliseconds: 500));
      await t.pump();
      expect(Countman.isSleeping, isTrue);
      Countman.stop();
      expect(Countman.isSleeping, isFalse);

      plugin.add(const CountdownOptions(duration: Duration(seconds: 10)));
      clock.advance(const Duration(milliseconds: 300));
      await t.pump();
      expect(Countman.isSleeping, isTrue);
      Countman.destroy();
      expect(Countman.isSleeping, isFalse);
    });

    testWidgets('注销最后一个插件会取消休眠定时器', (t) async {
      final plugin = _SpyCountdown(name: 'unuse-sleep');
      plugin.add(const CountdownOptions(duration: Duration(seconds: 10)));
      clock.advance(const Duration(milliseconds: 500));
      await t.pump();
      expect(Countman.isSleeping, isTrue);
      Countman.unuse(plugin, dispose: false);
      expect(Countman.isSleeping, isFalse);
      expect(Countman.isRunning, isFalse);
    });

    testWidgets('Counter 有活动任务时每帧处理，不休眠', (t) async {
      final counter = Counter(name: 'busy');
      var updates = 0;
      counter.add(
        CounterOptions(
          to: 10,
          duration: const Duration(seconds: 1),
          onUpdate: (_) => updates++,
        ),
      );
      await t.pump();
      await t.pump(_frame);
      await t.pump(_frame);
      expect(updates, 3);
      expect(Countman.isSleeping, isFalse);
      Countman.destroy();
    });
  });

  group('逐任务边界', () {
    for (final offsetMs in [0, 137, 500, 999]) {
      testWidgets('加入偏移 ${offsetMs}ms 的 10 秒倒计时恰在跨过整秒的帧更新', (t) async {
        final plugin = _SpyCountdown(name: 'bucket-$offsetMs');
        // 先让一个 30 秒任务带着自己的相位跑起来。
        plugin.add(const CountdownOptions(duration: Duration(seconds: 30)));
        await t.pump();
        if (offsetMs > 0) await step(t, Duration(milliseconds: offsetMs));

        final joinedAt = clock.monotonicMicros();
        final events = <(int, int)>[]; // (已过毫秒, 显示秒)
        var completedAt = -1;
        plugin.add(
          CountdownOptions(
            duration: const Duration(seconds: 10),
            onUpdate: (p) => events.add((
              (clock.monotonicMicros() - joinedAt) ~/ 1000,
              p.inSeconds,
            )),
            onComplete: () =>
                completedAt = (clock.monotonicMicros() - joinedAt) ~/ 1000,
          ),
        );
        await step(t, _frame);
        // 首帧剩余 9.984s，随后每次换桶：9、8、…、0。
        var previousFloor = 9;
        for (var i = 0; i < 700 && completedAt < 0; i++) {
          final beforeMs = (clock.monotonicMicros() - joinedAt) ~/ 1000;
          final countBefore = events.length;
          await step(t, _frame);
          final afterMs = beforeMs + _frame.inMilliseconds;
          final remaining = 10 * _msPerSecond - afterMs;
          if (remaining <= 0) {
            // 截止所在帧：先发一次值为 0 的更新，再触发完成。
            expect(events.length, countBefore + 1);
            expect(events.last.$2, 0);
            expect(completedAt, afterMs);
            continue;
          }
          // 剩余严格小于 k 秒才换桶：9.000s 仍显示 9，8.999s 才显示 8。
          final expectedFloor = remaining ~/ _msPerSecond;
          if (expectedFloor < previousFloor) {
            expect(
              events.length,
              countBefore + 1,
              reason: '剩余 ${remaining}ms 跨过整秒的帧必须更新',
            );
            expect(events.last.$2, expectedFloor);
            previousFloor = expectedFloor;
          } else {
            expect(
              events.length,
              countBefore,
              reason: '剩余 ${remaining}ms 未跨整秒，不应更新',
            );
          }
        }
        // 截止帧：首个已过时间 ≥ 10s 的帧。
        expect(completedAt, greaterThanOrEqualTo(10 * _msPerSecond));
        expect(
          completedAt,
          lessThan(10 * _msPerSecond + _frame.inMilliseconds),
        );
        expect(events.last.$2, 0);
        Countman.destroy();
      });
    }
  });
}
