import '../support/response_contract.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

const _retry = 'retry';
const _auth = diomanTestAuth;
const _mock = 'mock';
const _share = 'share';
const _path = '/b8';
const _put = 'PUT';
const _route = '$_put:$_path';

/// 验证对应主题的行为与边界。
void main() {
  for (final body in [
    Uint8List.fromList([1, 2]),
    <int>[1, 2]
  ]) {
    test('[DiomanContext.markReplayable] B8 字节体重放保留类型 ${body.runtimeType}',
        () async {
      final net = FakeNetwork();
      final api = testClient(statusOf: businessStatus, network: net, plugins: [
        TestPlugin('bytes', handler: (ctx, next) async {
          ctx.markReplayable();
          await next();
          return next();
        })
      ]);
      await api.send<dynamic>(_put, _path, data: body);
      expect(net.sends.length, 2);
      for (final send in net.sends) {
        expect(send.options.data, isA<List<int>>());
        expect(send.options.data, [1, 2]);
        if (body is Uint8List) expect(send.options.data, isA<Uint8List>());
      }
      api.dispose();
    });
  }
  for (final mode in [_retry, _auth, _mock, _share]) {
    test('[DiomanContext.canReplay] B8 一次性体 $mode 只发送一次', () async {
      final net = FakeNetwork()
        ..routes[_route] = [const FakeReply(status: 503)];
      final clock = FakeClock();
      final api = testClient(
          statusOf: businessStatus,
          network: net,
          clock: clock,
          plugins: [
            if (mode == _retry)
              DiomanRetry<Result>(max: 2, delay: (_, __, ___) => Duration.zero),
            if (mode == _auth)
              b3Auth(TestTokens(),
                  failure: (_, __) => DiomanAuthFailureAction.refresh),
            if (mode == _mock)
              DiomanMock<Result>(
                  mockUrl: 'https://mock.test', fallbackWhen: (_) => true),
            if (mode == _share)
              const DiomanShare<Result>(
                  policy: DiomanSharePolicy.retry, methods: {_put})
          ]);
      final body = Stream<Uint8List>.value(Uint8List.fromList([1, 2]));
      final pending = api.send<dynamic>(_put, _path,
          data: body,
          call: DiomanCall(key: 'stream', options: {DiomanShare.option: true}));
      await b3Finish(pending, clock);
      expect(net.sends.length, 1);
      api.dispose();
    });
  }
}
