import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bug #7: rejected reuse leaves the registry unchanged', () {
    // 挂载失败不能占住插件名或污染注册表。
    Countman.destroy();
    addTearDown(Countman.destroy);
    final plugin = Counter(name: 'disposed');
    plugin.dispose();
    expect(() => Countman.use(plugin), throwsStateError);
    expect(Countman.pluginCount, 0);
    Countman.use(Counter(name: 'disposed'));
    expect(Countman.pluginCount, 1);
  });

  test('Bug #7: disposed plugins reject reuse explicitly', () {
    // 销毁后的实例终身不可复用，避免任务进入失效的调度上下文。
    final plugin = Counter();
    plugin.onAttach(CountmanContext(requestFrame: () {}));
    plugin.dispose();
    expect(() => plugin.add(const CounterOptions(to: 1)), throwsStateError);
    expect(
      () => plugin.onAttach(CountmanContext(requestFrame: () {})),
      throwsStateError,
    );
  });

  test('Bug #19: wall-clock changes do not change stopwatch elapsed', () {
    // 系统校时只影响绝对截止倒计时，不改变秒表累计时间。
    var now = DateTime(2024);
    var monotonic = Duration.zero;
    final originalClock = elapsedClock;
    elapsedClock = () => monotonic;
    addTearDown(() => elapsedClock = originalClock);
    countdownClock = () => now;
    addTearDown(() => countdownClock = DateTime.now);
    final elapsedPlugin = Elapsed(interval: 0);
    elapsedPlugin.onAttach(CountmanContext(requestFrame: () {}));
    final handle = elapsedPlugin.add(const ElapsedOptions());
    final countdownPlugin = Countdown(interval: 0);
    countdownPlugin.onAttach(CountmanContext(requestFrame: () {}));
    final countdownHandle = countdownPlugin.add(
      const CountdownOptions(duration: Duration(hours: 2)),
    );

    now = now.add(const Duration(hours: 1));
    monotonic += const Duration(seconds: 3);
    expect(handle.elapsed, const Duration(seconds: 3));
    expect(countdownHandle.remaining, const Duration(hours: 1));
    now = now.subtract(const Duration(hours: 3));
    expect(handle.elapsed, const Duration(seconds: 3));
    expect(countdownHandle.remaining, const Duration(hours: 4));
  });
}
