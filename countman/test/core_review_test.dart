import 'package:countman/countman.dart';
import 'support/manual_clock.dart';
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

  test('Bug #19: 墙钟变化不影响秒表与相对倒计时，只影响绝对截止倒计时', () {
    // 改写理由：相对时长改走单调钟，只有 deadline 倒计时才跟随系统改时间。
    final clock = installManualClock();
    final elapsedPlugin = Elapsed(interval: 0, clock: clock);
    elapsedPlugin.onAttach(CountmanContext(requestFrame: () {}));
    final handle = elapsedPlugin.add(const ElapsedOptions());
    final countdownPlugin = Countdown(interval: 0, clock: clock);
    countdownPlugin.onAttach(CountmanContext(requestFrame: () {}));
    final relative = countdownPlugin.add(
      const CountdownOptions(duration: Duration(hours: 2)),
    );
    final absolute = countdownPlugin.add(
      CountdownOptions(deadline: kTestWallStart.add(const Duration(hours: 2))),
    );

    clock.jumpWall(const Duration(hours: 1));
    clock.advance(const Duration(seconds: 3));
    expect(handle.elapsed, const Duration(seconds: 3));
    expect(relative.remaining, const Duration(hours: 2) - const Duration(seconds: 3));
    expect(absolute.remaining, const Duration(hours: 1) - const Duration(seconds: 3));
    clock.jumpWall(const Duration(hours: -3));
    expect(handle.elapsed, const Duration(seconds: 3));
    expect(relative.remaining, const Duration(hours: 2) - const Duration(seconds: 3));
    expect(absolute.remaining, const Duration(hours: 4) - const Duration(seconds: 3));
  });
}
