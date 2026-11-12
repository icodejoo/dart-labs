// 自定义番茄钟插件示例的契约测试：tick 返回唤醒微秒数、阶段推进、暂停与恢复。

import 'package:countman/countman.dart';
import 'package:example/pomodoro_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一秒的微秒数。
const _second = 1000000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ManualCountmanClock clock;
  late PomodoroPlugin plugin;
  late List<PomodoroSnapshot> snapshots;
  late PomodoroHandle handle;

  /// 手动驱动一帧并返回插件给调度器的唤醒微秒数。
  int tick() => plugin.tick(Duration.zero, Duration.zero);

  setUp(() {
    clock = ManualCountmanClock();
    plugin = PomodoroPlugin(name: 'test-pomodoro', clockOverride: clock);
    Countman.use(plugin);
    snapshots = [];
    handle = plugin.start(
      phases: const [
        PomodoroPhase('专注', Duration(seconds: 10)),
        PomodoroPhase('休息', Duration(seconds: 5)),
      ],
      rounds: 2,
      onChange: snapshots.add,
    );
  });

  tearDown(Countman.destroy);

  test('首帧推送初值，并让调度器睡到下一个整秒', () {
    expect(tick(), _second);
    expect(snapshots.single.phase.label, '专注');
    expect(snapshots.single.remainingSeconds, 10);
  });

  test('tick 返回距下一个显示秒变化的微秒数，且不逐帧推送', () {
    tick();
    clock.advance(const Duration(milliseconds: 1500));
    // 剩 8.5 秒：显示由 10 变 9，下一次变化在 0.5 秒后。
    expect(tick(), 500000);
    expect(snapshots.last.remainingSeconds, 9);
    final updates = snapshots.length;
    // 同一显示秒内再次 tick 不重复推送。
    clock.advance(const Duration(milliseconds: 100));
    tick();
    expect(snapshots.length, updates);
  });

  test('阶段到点顺延到下一个阶段，全部走完后结束并返回 idle', () {
    tick();
    clock.advance(const Duration(seconds: 10));
    expect(tick(), _second);
    expect(snapshots.last.phase.label, '休息');
    expect(snapshots.last.phaseNumber, 2);
    clock.advance(const Duration(seconds: 20));
    expect(tick(), CountmanPlugin.idle);
    expect(snapshots.last.finished, isTrue);
    expect(plugin.activeTaskCount, 0);
  });

  test('暂停后冻结剩余时间，恢复后接着走', () {
    tick();
    clock.advance(const Duration(seconds: 4));
    tick();
    handle.pause();
    expect(handle.isPaused, isTrue);
    clock.advance(const Duration(seconds: 30));
    expect(tick(), CountmanPlugin.idle);
    handle.resume();
    tick();
    expect(snapshots.last.phase.label, '专注');
    expect(snapshots.last.remainingSeconds, 6);
  });

  test('结束后 restart 重新入队', () {
    tick();
    clock.advance(const Duration(seconds: 40));
    tick();
    handle.restart();
    snapshots.clear();
    tick();
    expect(snapshots.single.phase.label, '专注');
    expect(snapshots.single.remainingSeconds, 10);
  });
}
