import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/context.dart' show DiomanContextInternal;
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/b3_helpers.dart' show b3Turn;
import '../support/invariant_harness.dart';

/// 共享用例的路径、方法和退避头。
const _path = '/native-share', _method = 'GET', _retryAfter = 'retry-after';

/// 等待可观察状态，避免依赖 Dio 的事件队列层数。
Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await b3Turn();
  }
  expect(ready(), isTrue);
}

/// 共享结果保留小事实，不共享原生槽。
void main() {
  test(
      '[DiomanRetry.respectRetryAfter][DiomanShare][DiomanCall.raw] 跟随者遵守头等待且不借用首发原生数据',
      () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final network = FakeNetwork()
      ..routes['$_method:$_path'] = [
        FakeReply(status: 503, gate: gate.future),
        const FakeReply()
      ];
    final api = testClient(
        network: network,
        clock: clock,
        plugins: [const DiomanRetry(max: 1), const DiomanShare()]);
    api.dio.interceptors.add(InterceptorsWrapper(onResponse: (r, h) {
      if (r.statusCode == 503) r.headers.set(_retryAfter, '2');
      h.next(r);
    }));
    final call = DiomanCall(raw: true, options: {DiomanShare.option: true});
    final first = api.send<Object?>(_method, _path, call: call);
    await _until(() => network.sends.isNotEmpty);
    final follower = api.send<Object?>(_method, _path, call: call);
    await b3Turn();
    gate.complete();
    await _until(() => clock.pendingTimers == 2);
    expect(network.sends.length, 1);
    clock.elapse(const Duration(milliseconds: 1999));
    await b3Turn();
    expect(network.sends.length, 1);
    clock.elapse(const Duration(milliseconds: 1));
    await b3Turn();
    final results = await Future.wait([first, follower]);
    expect(network.sends.length, 2);
    expect(results.every((r) => r.ok), isTrue);
    expect(results.where((r) => r.raw != null).length, 1);
    expect(results.last.raw, isNull);
    expect(results.last.error, isNull);
    expect(results.first.request, same(results.last.request));
  });

  test('[DiomanContext.native][DiomanSharePolicy.start] 首发落定后共享传输完成不能重写槽',
      () async {
    final gate = Completer<void>();
    final network = FakeNetwork()
      ..routes['$_method:$_path'] = [FakeReply(gate: gate.future)];
    final token = CancelToken();
    final contexts = <DiomanContext<Result>>[];
    final api = testClient(network: network, plugins: [
      const DiomanShare(),
      TestPlugin('capture', stage: DiomanStage.outer,
          handler: (ctx, next) async {
        contexts.add(ctx);
        return next();
      })
    ]);
    final first = api.send<Object?>(_method, _path,
        call: DiomanCall(
            raw: true,
            cancelToken: token,
            options: {DiomanShare.option: true}));
    await _until(() => network.sends.isNotEmpty);
    final follower = api.send<Object?>(_method, _path,
        call: DiomanCall(raw: true, options: {DiomanShare.option: true}));
    await b3Turn();
    token.cancel('leader-only');
    expect(failureOf(await first)!.kind, DiomanFailureKind.cancel);
    NativeSlotProbe.assertClosed(contexts.first);
    expect(contexts.first.state.nativeClosed, isTrue);
    gate.complete();
    expect((await follower).raw, isNull);
    await b3Turn();
    for (final ctx in contexts) {
      NativeSlotProbe.assertClosed(ctx);
    }
    expect(api.pending, 0);
  });

  test('[DiomanMock.mockUrl][DiomanContext.native] mock 探测走真实传输时仍有自身槽',
      () async {
    final network = FakeNetwork();
    final api = testClient(
        network: network,
        plugins: [const DiomanMock(mockUrl: 'https://mock.test')]);
    final result = await api.send<Object?>(_method, _path,
        call: const DiomanCall(raw: true));
    expect(result.raw, isNotNull);
    expect(network.sends.length, 1);
  });
  test(
      '[DiomanMock.routes][DiomanRetry.respectRetryAfter] 内联 mock 响应保留服务器等待事实且没有原生槽',
      () async {
    final clock = FakeClock();
    var calls = 0;
    final api = testClient(clock: clock, plugins: [
      const DiomanRetry(max: 1),
      DiomanMock(routes: {
        '$_method:$_path': (request) {
          calls++;
          return Response<dynamic>(
              requestOptions: request.toRequestOptions(),
              statusCode: calls == 1 ? 503 : 200,
              headers: Headers.fromMap({
                _retryAfter: ['2']
              }));
        }
      })
    ]);
    final pending =
        api.send<Object?>(_method, _path, call: const DiomanCall(raw: true));
    await _until(() => clock.pendingTimers == 1);
    clock.elapse(const Duration(milliseconds: 1999));
    await b3Turn();
    expect(calls, 1);
    clock.elapse(const Duration(milliseconds: 1));
    final result = await pending;
    expect(calls, 2);
    expect(result.ok, isTrue);
    expect(result.raw, isNull);
  });
}
