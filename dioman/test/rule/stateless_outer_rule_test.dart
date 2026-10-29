import '../support/b2_constants.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/invariant_harness.dart';

/// 外层规则使用的请求路径。
const outerPath = '/outer';

/// 外层规则的网络路由。
const outerRoute = '$b2Get:$outerPath';

/// 防闪烁窗口。
const outerTick = Duration(seconds: 1);

/// 验证 loading 与 notify 的逻辑请求契约。
void main() {
  test('[DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对', () async {
    final net = FakeNetwork();
    final clock = FakeClock();
    final h = InvariantHarness(net, clock);
    final own = <bool>[];
    final gate = Completer<void>();
    net.routes[outerRoute] = [FakeReply(gate: gate.future)];
    final api = testClient(
        network: net,
        clock: clock,
        plugins: [h.loadingPlugin(), ...h.probes()]);
    final a = h.track(1, api.send<Object?>(b2Get, outerPath));
    final b = h.track(
        2,
        api.send<Object?>(b2Get, outerPath,
            call: DiomanCall(options: {
              DiomanLoading.option: DiomanLoadingOptions(onChanged: own.add)
            })));
    final c = h.track(3, api.send<Object?>(b2Get, outerPath));
    await flush();
    expect(api.plugin<DiomanLoadingApi>()!.activeCount, 3);
    expect(h.loading.values.single, [true]);
    expect(own, [true]);
    gate.complete();
    await Future.wait([a, b, c]);
    expect(api.plugin<DiomanLoadingApi>()!.activeCount, 0);
    expect(own, [true, false]);
    h.assertAll(api);
  });

  test(
      '[DiomanLoading.enabled][DiomanLoadingOptions.enabled]'
      '[DiomanLoading.option] 四种写法、字段继承与请求开关', () async {
    final events = <bool>[];
    final clock = FakeClock();
    final api = testClient(
        clock: clock, plugins: [DiomanLoading(onChanged: events.add)]);
    for (final option in [null, true, const DiomanLoadingOptions()]) {
      await api.send<Object?>(b2Get, outerPath,
          call: DiomanCall(options: {DiomanLoading.option: option}));
    }
    expect(events, [true, false, true, false, true, false]);
    events.clear();
    for (final option in [false, const DiomanLoadingOptions(enabled: false)]) {
      await api.send<Object?>(b2Get, outerPath,
          call: DiomanCall(options: {DiomanLoading.option: option}));
    }
    expect(events, isEmpty);
    await api.send<Object?>(b2Get, outerPath,
        call: DiomanCall(options: {
          DiomanLoading.option: const DiomanLoadingOptions(
              delay: outerTick, delayClose: outerTick)
        }));
    clock.elapse(outerTick);
    expect(events, isEmpty);
    expect(clock.pendingTimers, 0);
  });

  test(
      '[DiomanLoadingOptions.delay][DiomanLoadingOptions.delayClose]'
      '[DiomanLoadingOptions.onChanged] 独占回调替代默认且两个延迟都生效', () async {
    final own = <bool>[];
    final clock = FakeClock();
    final gate = Completer<void>();
    final net = FakeNetwork()
      ..routes[outerRoute] = [FakeReply(gate: gate.future)];
    final api = testClient(network: net, clock: clock, plugins: [
      DiomanLoading(
          onChanged: (_) => fail('default callback'),
          delay: outerTick,
          delayClose: outerTick)
    ]);
    final pending = api.send<Object?>(b2Get, outerPath,
        call: DiomanCall(options: {
          DiomanLoading.option: DiomanLoadingOptions(onChanged: own.add)
        }));
    await flush();
    expect(own, isEmpty);
    clock.elapse(outerTick);
    expect(own, [true]);
    gate.complete();
    await pending;
    expect(own, [true]);
    clock.elapse(outerTick);
    expect(own, [true, false]);
    expect(clock.pendingTimers, 0);
  });

  test(
      '[DiomanCall.silent]'
      '[DiomanNotify.defaultStringify]'
      '[DiomanResponse.message]'
      '[DiomanNotify.stringify] 默认忽略成功、取消和 silent，失败消息与空消息回退', () async {
    final net = FakeNetwork();
    final messages = <String>[];
    final results = <Result>[];
    final api = testClient(network: net, plugins: [
      DiomanNotify(notify: (m, r) {
        messages.add(m);
        results.add(r);
      })
    ]);
    await api.send<Object?>(b2Get, outerPath);
    net.routes[outerRoute] = [const FakeReply(status: 500, body: {})];
    final failed = await api.send<Object?>(b2Get, outerPath);
    expect(messages, ['http 500']);
    expect(results.single, same(failed));
    net.routes[outerRoute] = [
      const FakeReply(body: {'code': 401, 'message': 'denied'})
    ];
    await api.send<Object?>(b2Get, outerPath);
    expect(messages.last, 'denied');
    await api.send<Object?>(b2Get, outerPath,
        call: const DiomanCall(silent: true));
    await api.send<Object?>(b2Get, outerPath,
        call: DiomanCall(options: {DiomanNotify.option: false}));
    expect(messages.length, 2);
    final gate = Completer<void>();
    net.routes[outerRoute] = [FakeReply(gate: gate.future)];
    final pending = api.send<Object?>(b2Get, outerPath);
    await flush();
    api.cancelAll();
    expect((await pending).kind, DiomanKind.cancel);
    gate.complete();
    expect(messages.length, 2);
  });

  test('[DiomanNotify.option] true 开启、自定义 stringify 与空串关闭，I4 按 ctx.id 记录',
      () async {
    final net = FakeNetwork();
    final clock = FakeClock();
    final h = InvariantHarness(net, clock);
    net.routes[outerRoute] = [const FakeReply(status: 500)];
    final api = testClient(
        network: net, clock: clock, plugins: [h.notifyPlugin(), ...h.probes()]);
    for (var id = 1; id <= 3; id++) {
      await h.track(
          id,
          api.send<Object?>(b2Get, outerPath,
              call: DiomanCall(options: {DiomanNotify.option: true})));
    }
    expect(h.notifications, {1: 1, 2: 1, 3: 1});
    h.assertAll(api);
    final quiet = testClient(plugins: [
      DiomanNotify(
          stringify: (_, ctx) => b2Empty,
          notify: (_, r) => fail('empty message'))
    ]);
    await quiet.send<Object?>(b2Get, outerPath);
  });
}
