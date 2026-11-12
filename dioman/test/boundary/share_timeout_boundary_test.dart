import '../support/response_contract.dart';
import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/source_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test('[DiomanShare.option] 连接五秒接收三十秒的跟随者在传输十秒完成时成功', () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final net = FakeNetwork()..routes[b4Route] = [FakeReply(gate: gate.future)];
    final api = testClient(
        clock: clock, network: net, plugins: [const DiomanShare<Result>()]);
    final leader = api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
    await b4Turn();
    var settled = false;
    final follower = api
        .send<Object?>(b4Get, b4Path,
            call: DiomanCall(
                key: b4Key,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 30),
                options: {DiomanShare.option: true}))
        .then((r) {
      settled = true;
      return r;
    });
    await b4Turn();
    expect(clock.pendingTimers, 1);
    clock.elapse(const Duration(seconds: 10));
    await b4Turn();
    expect(settled, isFalse);
    gate.complete();
    expect((await leader).ok, isTrue);
    expect((await follower).ok, isTrue);
    expect(net.sends.length, 1);
    expect(clock.pendingTimers, 0);
    expect(api.cancellationSubscriptions, 0);
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
    api.dispose();
  });
  test('[DiomanShare.option] 连接接收或有请求体的发送阶段为无限时则整体不限时', () async {
    for (final stage in [
      (connect: null, receive: b4Tick, send: b4Tick, body: false),
      (connect: b4Tick, receive: null, send: b4Tick, body: false),
      (connect: Duration.zero, receive: b4Tick, send: b4Tick, body: false),
      (connect: b4Tick, receive: Duration.zero, send: b4Tick, body: false),
      (connect: b4Tick, receive: b4Tick, send: null, body: true),
      (connect: b4Tick, receive: b4Tick, send: Duration.zero, body: true),
    ]) {
      final clock = FakeClock();
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[b4Route] = [FakeReply(gate: gate.future)];
      final api = testClient(
          clock: clock, network: net, plugins: [const DiomanShare<Result>()]);
      final leader =
          api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
      await b4Turn();
      final follower = api.send<Object?>(b4Get, b4Path,
          data: stage.body ? {} : null,
          call: DiomanCall(
              key: b4Key,
              connectTimeout: stage.connect,
              receiveTimeout: stage.receive,
              sendTimeout: stage.send,
              options: {DiomanShare.option: true}));
      await b4Turn();
      expect(clock.pendingTimers, 0);
      clock.elapse(const Duration(days: 1));
      gate.complete();
      expect((await leader).ok, isTrue);
      expect((await follower).ok, isTrue);
      expect(net.sends.length, 1);
      expect(api.cancellationSubscriptions, 0);
      expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
      api.dispose();
    }
  });
  test('[DiomanShare.option] 请求体非空时累计发送超时且无请求体时忽略发送阶段', () async {
    for (final withBody in [false, true]) {
      final clock = FakeClock();
      final gate = Completer<void>();
      final net = FakeNetwork()
        ..routes[b4Route] = [FakeReply(gate: gate.future)];
      final api = testClient(
          clock: clock, network: net, plugins: [const DiomanShare<Result>()]);
      final leader =
          api.send<Object?>(b4Get, b4Path, call: b4Call(share: true));
      await b4Turn();
      var settled = false;
      final follower = api
          .send<Object?>(b4Get, b4Path,
              data: withBody ? {} : null,
              call: DiomanCall(
                  key: b4Key,
                  connectTimeout: b4Tick * 2,
                  receiveTimeout: b4Tick * 3,
                  sendTimeout: b4Tick * 4,
                  options: {DiomanShare.option: true}))
          .then((r) {
        settled = true;
        return r;
      });
      await b4Turn();
      clock.elapse(b4Tick * 5);
      await b4Turn();
      expect(settled, !withBody);
      if (withBody) {
        expect(clock.pendingTimers, 1);
        clock.elapse(b4Tick * 4);
      }
      expect(outcomeOf((await follower)), diomanTestTimeout);
      expect(net.sends.single.options.cancelToken!.isCancelled, isFalse);
      gate.complete();
      expect((await leader).ok, isTrue);
      expect(clock.pendingTimers, 0);
      expect(api.cancellationSubscriptions, 0);
      api.dispose();
    }
  });
}
