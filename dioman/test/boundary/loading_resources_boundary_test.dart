import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';

/// 测试共用的方法。
const _method = 'GET';

/// 测试共用的路径。
const _path = '/loading';

/// 测试共用的路由。
const _route = 'GET:/loading';

/// 测试用共享显示控制器。
class _Spinner {
  /// 显示边沿序列。
  final events = <bool>[];

  /// 用相等的实例方法 tear-off 接收通知。
  void toggle(bool visible) => events.add(visible);
}

/// 验证共享回调、占用和窗口归属。
void main() {
  const tick = Duration(seconds: 1);
  for (final disposeFirst in [false, true]) {
    test(
        '[DiomanLoading.onChanged][DiomanLoadingApi.activeCount] 跨客户端共享 disposeFirst=$disposeFirst',
        () async {
      final spinner = _Spinner();
      final aGate = Completer<void>();
      final bGate = Completer<void>();
      final a = testClient(
          network: FakeNetwork()
            ..routes[_route] = [FakeReply(gate: aGate.future)],
          plugins: [DiomanLoading(onChanged: spinner.toggle)]);
      final b = testClient(
          network: FakeNetwork()
            ..routes[_route] = [FakeReply(gate: bGate.future)],
          plugins: [DiomanLoading(onChanged: spinner.toggle)]);
      final first = a.send<Object?>(_method, _path);
      final second = b.send<Object?>(_method, _path,
          call: DiomanCall(options: {
            DiomanLoading.option:
                DiomanLoadingOptions(onChanged: spinner.toggle),
          }));
      await flush();
      expect(a.plugin<DiomanLoadingApi>()!.activeCount, 1);
      expect(b.plugin<DiomanLoadingApi>()!.activeCount, 1);
      expect(spinner.events, [true]);
      if (disposeFirst) a.dispose();
      aGate.complete();
      await first;
      expect(a.plugin<DiomanLoadingApi>()!.activeCount, 0);
      expect(spinner.events, [true]);
      bGate.complete();
      await second;
      expect(spinner.events, [true, false]);
    });
  }
  test('[DiomanLoadingOptions.onChanged] 同客户端请求级 tear-off 共用占用', () async {
    final spinner = _Spinner();
    final gate = Completer<void>();
    final api = testClient(
        network: FakeNetwork()..routes[_route] = [FakeReply(gate: gate.future)],
        plugins: [DiomanLoading(onChanged: spinner.toggle)]);
    final a = api.send<Object?>(_method, _path);
    final b = api.send<Object?>(_method, _path,
        call: DiomanCall(options: {
          DiomanLoading.option: DiomanLoadingOptions(onChanged: spinner.toggle),
        }));
    await flush();
    expect(api.plugin<DiomanLoadingApi>()!.activeCount, 2);
    expect(spinner.events, [true]);
    gate.complete();
    await Future.wait([a, b]);
    expect(spinner.events, [true, false]);
  });
  test('[DiomanLoading.delayClose][Dioman.dispose] 隐藏窗口交接并使用新归属方时钟', () async {
    final spinner = _Spinner();
    final aClock = FakeClock();
    final bClock = FakeClock();
    final a = testClient(
        clock: aClock,
        plugins: [DiomanLoading(onChanged: spinner.toggle, delayClose: tick)]);
    final b = testClient(
        clock: bClock,
        plugins: [DiomanLoading(onChanged: spinner.toggle, delayClose: tick)]);
    await a.send<Object?>(_method, _path);
    expect(aClock.pendingTimers, 1);
    await b.send<Object?>(_method, _path);
    expect(aClock.pendingTimers, 0);
    expect(bClock.pendingTimers, 1);
    a.dispose();
    expect(spinner.events, [true]);
    aClock.elapse(tick);
    expect(spinner.events, [true]);
    bClock.elapse(tick);
    expect(spinner.events, [true, false]);
    b.dispose();
    SharedResourceProbe.assertEmpty();
  });
  test('[DiomanLoading.delayClose][Dioman.dispose] 窗口归属方卸载补发 false', () async {
    final spinner = _Spinner();
    final clock = FakeClock();
    final api = testClient(
        clock: clock,
        plugins: [DiomanLoading(onChanged: spinner.toggle, delayClose: tick)]);
    await api.send<Object?>(_method, _path);
    final instance =
        api.plugin<DiomanLoadingApi>() as DiomanPluginInstance<Result>;
    instance.dispose();
    instance.dispose();
    api.dispose();
    expect(clock.pendingTimers, 0);
    expect(spinner.events, [true, false]);
    clock.elapse(tick);
    expect(spinner.events, [true, false]);
    SharedResourceProbe.assertEmpty();
  });
}
