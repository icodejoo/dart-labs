import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:test/test.dart';
import '../support/pipeline/b4_helpers.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';

/// 探测取消必须在回落判定前收尾。
void main() {
  test('[DiomanMock.routes] 内联处理器异常原样抛出，不触发回落且外层收尾', () async {
    final boom = StateError(b4LiteralEmpty);
    var fallbacks = 0;
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      DiomanMock<Result>(
          routes: {b4Route: (_) => throw boom},
          fallbackWhen: (_) {
            fallbacks++;
            return true;
          })
    ]);
    await expectLater(api.send<Object?>(b4Get, b4Path), throwsA(same(boom)));
    expect(fallbacks, 0);
    expect(net.sends, isEmpty);
    expect(api.pending, 0);
  });
  test('[DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误', () async {
    final gate = Completer<void>();
    final net = FakeNetwork()
      ..routes['GET:https://mock.test$b4Path'] = [
        FakeReply(status: 404, gate: gate.future)
      ];
    var decisions = 0;
    final api = testClient(network: net, plugins: [
      DiomanMock<Result>(
          mockUrl: b4LiteralHttpsMockTest,
          fallbackWhen: (_) {
            decisions++;
            return true;
          })
    ]);
    final pending = api.send<Object?>(b4Get, b4Path);
    await b4Turn();
    api.cancelAll();
    expect((await pending).kind, DiomanKind.cancel);
    expect(decisions, 0);
    gate.complete();
    await b4Turn();
    expect(net.sends.length, 1);
    final inline = Completer<Object?>();
    final client = testClient(plugins: [
      DiomanMock<Result>(routes: {b4Route: (_) => inline.future})
    ]);
    final waiting = client.send<Object?>(b4Get, b4Path);
    await b4Turn();
    client.cancelAll();
    expect((await waiting).kind, DiomanKind.cancel);
    inline.completeError(StateError('late'));
    await b4Turn();
    expect(client.cancellationSubscriptions, 0);
  });
}
