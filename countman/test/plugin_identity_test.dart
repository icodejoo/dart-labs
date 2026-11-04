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

  test('不同名称的两个实例互不干扰，都能各自驱动任务', () {
    final first = Counter(name: 'first');
    final second = Counter(name: 'second');
    var a = 0;
    var b = 0;
    first.add(CounterOptions(to: 1, onUpdate: (_) => a++));
    second.add(CounterOptions(to: 1, onUpdate: (_) => b++));
    expect(Countman.pluginCount, 2);
    expect(first.tick(Duration.zero, Duration.zero), CountmanPlugin.nextFrame);
    expect(second.tick(Duration.zero, Duration.zero), CountmanPlugin.nextFrame);
    expect(a, 1);
    expect(b, 1);
  });

  test('注销后名称被释放，同名新实例可以注册并工作', () {
    final old = Counter(name: 'reuse-name');
    Countman.use(old);
    expect(Countman.unuse(old), isTrue);
    final fresh = Counter(name: 'reuse-name');
    var updates = 0;
    fresh.add(CounterOptions(to: 1, onUpdate: (_) => updates++));
    expect(Countman.pluginCount, 1);
    fresh.tick(Duration.zero, Duration.zero);
    expect(updates, 1);
  });

  test('destroy 之后同名实例可以重新注册', () {
    Countman.use(Counter(name: 'after-destroy'));
    Countman.destroy();
    expect(() => Countman.use(Counter(name: 'after-destroy')), returnsNormally);
    expect(Countman.pluginCount, 1);
  });

  test('unuse 与 destroy 都会调用 onDetach，且 unuse 的 dispose 参数决定是否销毁', () {
    final kept = _DetachSpy('kept');
    final dropped = _DetachSpy('dropped');
    final destroyed = _DetachSpy('destroyed');
    Countman.use(kept);
    Countman.use(dropped);
    Countman.use(destroyed);
    Countman.unuse(kept, dispose: false);
    Countman.unuse(dropped);
    expect(kept.detached, 1);
    expect(kept.disposed, 0);
    expect(dropped.detached, 1);
    expect(dropped.disposed, 1);
    Countman.destroy();
    expect(destroyed.detached, 1);
    expect(destroyed.disposed, 1);
    expect(kept.detached, 1, reason: '已注销的实例不会被 destroy 再次通知');
  });

  test('注销未注册的实例返回 false 且不触发 onDetach', () {
    final spy = _DetachSpy('never-registered');
    expect(Countman.unuse(spy), isFalse);
    expect(spy.detached, 0);
    expect(spy.disposed, 0);
  });
}

/// 记录 onDetach 与 dispose 调用次数的最小插件。
class _DetachSpy implements CountmanPlugin {
  /// [name] 为插件名称。
  _DetachSpy(this.name);

  @override
  final String name;

  /// onDetach 被调用的次数。
  int detached = 0;

  /// dispose 被调用的次数。
  int disposed = 0;

  @override
  void onAttach(CountmanContext c) {}

  @override
  void onDetach() => detached++;

  @override
  int tick(Duration elapsed, Duration dt) => CountmanPlugin.idle;

  @override
  void dispose() => disposed++;
}
