// setRunState 是包内接口（@internal），测试需要直接调用。
// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用于验证 mixin 的最小控制器。
class _Controller with CountmanRunStateNotifier {}

/// 验证控制器运行状态基础设施：初始值、通知语义与释放。
void main() {
  test('初始状态为 idle，枚举覆盖四种状态', () {
    final c = _Controller();
    expect(c.runState, CountmanRunState.idle);
    expect(c.runStateListenable.value, CountmanRunState.idle);
    expect(CountmanRunState.values, [
      CountmanRunState.idle,
      CountmanRunState.running,
      CountmanRunState.paused,
      CountmanRunState.completed,
    ]);
    c.disposeRunState();
  });

  test('状态变化时通知监听者并更新 runState', () {
    final c = _Controller();
    final seen = <CountmanRunState>[];
    c.runStateListenable.addListener(() => seen.add(c.runState));
    c.setRunState(CountmanRunState.running);
    c.setRunState(CountmanRunState.paused);
    c.setRunState(CountmanRunState.completed);
    expect(seen, [
      CountmanRunState.running,
      CountmanRunState.paused,
      CountmanRunState.completed,
    ]);
    expect(c.runState, CountmanRunState.completed);
    c.disposeRunState();
  });

  test('状态不变时不通知', () {
    final c = _Controller();
    var notified = 0;
    c.runStateListenable.addListener(() => notified++);
    c.setRunState(CountmanRunState.idle);
    expect(notified, 0);
    c.setRunState(CountmanRunState.running);
    c.setRunState(CountmanRunState.running);
    expect(notified, 1);
    c.disposeRunState();
  });

  test('移除监听后不再收到通知，两个控制器互不影响', () {
    final a = _Controller();
    final b = _Controller();
    var notified = 0;
    void listener() => notified++;
    a.runStateListenable.addListener(listener);
    a.setRunState(CountmanRunState.running);
    a.runStateListenable.removeListener(listener);
    a.setRunState(CountmanRunState.paused);
    b.setRunState(CountmanRunState.completed);
    expect(notified, 1);
    expect(a.runState, CountmanRunState.paused);
    expect(b.runState, CountmanRunState.completed);
    a.disposeRunState();
    b.disposeRunState();
  });

  test('disposeRunState 之后不能再监听', () {
    final c = _Controller()..disposeRunState();
    expect(() => c.runStateListenable.addListener(() {}), throwsFlutterError);
  });
}
