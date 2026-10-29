import '../support/b2_constants.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../rule/stateless_outer_rule_test.dart'
    show outerPath, outerTick, outerRoute;

/// 验证显示时序、释放与通知回调隔离。
void main() {
  test('[Dioman.logError] debug 关闭仍记录通知错误，默认输出抛错也隔离', () async {
    for (final brokenOutput in [false, true]) {
      final messages = <String>[];
      await runZoned(() async {
        final api = testClient(plugins: [
          DiomanLoading(onChanged: (_) {
            throw StateError(b2NoticeFailure);
          }),
          DiomanNotify(
              stringify: (_, ctx) => b2NoticeFailure,
              notify: (_, r) => throw StateError(b2NoticeFailure))
        ]);
        expect((await api.send<Object?>('GET', outerPath)).ok, isTrue);
      }, zoneSpecification:
          ZoneSpecification(print: (_, parent, zone, message) {
        messages.add(message);
        if (brokenOutput) throw StateError('output failed');
      }));
      expect(messages.length, 3);
    }
  });
  test('[DiomanLoading.delay] 显示前结束、延迟到期和 0→1 决定窗口', () async {
    final events = <bool>[];
    final clock = FakeClock();
    final net = FakeNetwork();
    final api = testClient(
        network: net,
        clock: clock,
        plugins: [DiomanLoading(onChanged: events.add, delay: outerTick)]);
    await api.send<Object?>(b2Get, outerPath);
    clock.elapse(outerTick);
    expect(events, isEmpty);
    final gate = Completer<void>();
    net.routes[outerRoute] = [FakeReply(gate: gate.future)];
    final a = api.send<Object?>(b2Get, outerPath);
    final b = api.send<Object?>(b2Get, outerPath,
        call: DiomanCall(options: {
          DiomanLoading.option:
              const DiomanLoadingOptions(delay: Duration(days: 1))
        }));
    await flush();
    clock.elapse(outerTick);
    expect(events, [true]);
    gate.complete();
    await Future.wait([a, b]);
    expect(events, [true, false]);
    expect(clock.pendingTimers, 0);
  });

  test('[DiomanLoading.delayClose] 新请求取消隐藏窗口，1→0 请求决定关闭延迟', () async {
    final events = <bool>[];
    final clock = FakeClock();
    final api = testClient(
        clock: clock,
        plugins: [DiomanLoading(onChanged: events.add, delayClose: outerTick)]);
    await api.send<Object?>(b2Get, outerPath);
    expect(events, [true]);
    await api.send<Object?>(b2Get, outerPath);
    expect(events, [true]);
    clock.elapse(outerTick);
    expect(events, [true, false]);
    final gate = Completer<void>();
    final net = api.dio.httpClientAdapter as FakeNetwork;
    net.routes[outerRoute] = [FakeReply(gate: gate.future)];
    final a = api.send<Object?>(b2Get, outerPath,
        call: DiomanCall(options: {
          DiomanLoading.option:
              const DiomanLoadingOptions(delayClose: Duration(days: 1))
        }));
    final b = api.send<Object?>(b2Get, outerPath,
        call: DiomanCall(options: {
          DiomanLoading.option:
              const DiomanLoadingOptions(delayClose: Duration.zero)
        }));
    await flush();
    gate.complete();
    await Future.wait([a, b]);
    expect(events, [true, false, true, false]);
    expect(clock.pendingTimers, 0);
  });

  test('[DiomanLoadingApi] dispose 取消显示/隐藏、立即配对，在途及旧链不再通知', () async {
    for (final delayed in [true, false]) {
      final events = <bool>[];
      final clock = FakeClock();
      final net = FakeNetwork();
      final gate = Completer<void>();
      net.routes[outerRoute] = [FakeReply(gate: gate.future)];
      final api = testClient(network: net, clock: clock, plugins: [
        DiomanLoading(
            onChanged: events.add,
            delay: delayed ? outerTick : Duration.zero,
            delayClose: outerTick)
      ]);
      final control = api.plugin<DiomanLoadingApi>()!;
      final pending = api.send<Object?>(b2Get, outerPath);
      await flush();
      expect(control.activeCount, 1);
      api.dispose();
      api.dispose();
      expect(control.activeCount, 0);
      expect((await pending).kind, DiomanKind.cancel);
      gate.complete();
      clock.elapse(outerTick * 2);
      expect(events, delayed ? isEmpty : [true, false]);
      expect(clock.pendingTimers, 0);
    }
    final events = <bool>[];
    final clock = FakeClock();
    final api = testClient(
        clock: clock,
        plugins: [DiomanLoading(onChanged: events.add, delayClose: outerTick)]);
    await api.send<Object?>(b2Get, outerPath);
    api.eject(DiomanLoading.pluginName);
    clock.elapse(outerTick);
    expect(events, [true, false]);
    // 固定旧链等待至插件已卸载，随后 loading.handle 必须直通。
    final gate = Completer<void>();
    final old = testClient(plugins: [
      TestPlugin('hold', stage: DiomanStage.outer, enforce: DiomanEnforce.pre,
          handler: (ctx, next) async {
        await gate.future;
        return next();
      }),
      DiomanLoading(onChanged: (_) => fail('disposed layer'))
    ]);
    final pending = old.send<Object?>(b2Get, outerPath);
    old.eject(DiomanLoading.pluginName);
    gate.complete();
    await pending;
  });

  test(
      '[DiomanLoading.pluginName]'
      '[DiomanLoading.onChanged] 通知抛错隔离、日志记录且计数仍归零', () async {
    final logs = <String>[];
    final events = <bool>[];
    final api = testClient(debug: logs.add, plugins: [
      DiomanLoading(onChanged: (v) {
        events.add(v);
        throw StateError('loading callback');
      })
    ]);
    expect((await api.send<Object?>(b2Get, outerPath)).ok, isTrue);
    expect(events, [true, false]);
    expect(logs.length, 2);
    expect(logs.every((s) => s.contains(DiomanLoading.pluginName)), isTrue);
    expect(api.plugin<DiomanLoadingApi>()!.activeCount, 0);
  });

  test(
      '[DiomanNotify.pluginName]'
      '[DiomanNotify.notify] stringify 与 notify 的错误均隔离并记日志', () async {
    for (final brokenStringify in [false, true]) {
      final logs = <String>[];
      final api = testClient(debug: logs.add, plugins: [
        DiomanNotify(
            stringify: (r, ctx) {
              if (brokenStringify) throw StateError('stringify');
              return 'notice';
            },
            notify: (_, r) => throw StateError(b2NotifyLabel))
      ]);
      expect((await api.send<Object?>(b2Get, outerPath)).ok, isTrue);
      expect(logs.single, contains(DiomanNotify.pluginName));
    }
  });

  test('[DiomanNotify] internal 优先于取消且 loading finally 仍完成', () async {
    final events = <bool>[];
    Result? notified;
    final bug = StateError('internal');
    final api = testClient(plugins: [
      DiomanLoading(onChanged: events.add),
      DiomanNotify(notify: (_, r) => notified = r),
      TestPlugin('bug', handler: (ctx, _) async {
        ctx.client.cancelAll();
        throw bug;
      })
    ]);
    await expectLater(api.send<Object?>(b2Get, outerPath), throwsA(same(bug)));
    expect(notified, isNull);
    expect(events, [true, false]);
  });
}
