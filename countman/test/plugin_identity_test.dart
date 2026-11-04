import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证按实例挂载、诊断冲突和可逆注销。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Countman.destroy);

  test('同名实例在 debug 注册时立即给出迁移提示', () {
    final first = Counter(name: 'same');
    final second = Counter(name: 'same');
    Countman.use(first);
    expect(
      () => Countman.use(second),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.message.toString(),
          '提示',
          contains('唯一 name'),
        ),
      ),
    );
    expect(Countman.pluginCount, 1);
    expect(Countman.unuse(second), isFalse);
  });

  test('unuse(dispose: false) 保留任务且下次 add 重新挂载', () {
    final plugin = Counter(name: 'reusable');
    var updates = 0;
    plugin.add(CounterOptions(to: 10, onUpdate: (_) => updates++));
    expect(Countman.unuse(plugin, dispose: false), isTrue);
    expect(Countman.isRunning, isFalse);
    expect(plugin.activeTaskCount, 1);
    plugin.add(CounterOptions(to: 20, onUpdate: (_) => updates++));
    expect(Countman.pluginCount, 1);
    expect(plugin.tick(Duration.zero, Duration.zero), CountmanPlugin.nextFrame);
    expect(updates, 2);
  });

  test('重复注册实例幂等，默认注销仍永久销毁', () {
    final plugin = Counter();
    Countman.use(plugin);
    Countman.use(plugin);
    expect(Countman.pluginCount, 1);
    expect(Countman.unuse(plugin), isTrue);
    expect(() => plugin.add(CounterOptions(to: 1)), throwsStateError);
  });
}
