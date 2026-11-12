import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 测试共用的方法。
const _method = 'GET';

/// 测试共用的路径。
const _path = '/session';

/// 测试共用的配置值。
const _initialRefresh = 'refresh-old';

/// 验证父子客户端对同一会话资源的共享。
void main() {
  test('[DiomanAuth.onRefresh × Dioman.extend] 轮换刷新凭证只刷新一次且不登出', () async {
    final tokens = TestTokens()..refreshToken = _initialRefresh;
    final gate = Completer<void>();
    var refreshes = 0;
    var notices = 0;
    final network = FakeNetwork()
      ..routes['GET:/session'] = [
        const FakeReply(status: 401),
        const FakeReply(status: 401),
        const FakeReply(),
      ];
    final parent = testClient(network: network, plugins: [
      DiomanAuth<Result>(
          tokenManager: tokens,
          onRefresh: (tm, _) async {
            final credential = tm.refreshToken;
            if (++refreshes > 1 || credential != _initialRefresh) {
              throw StateError('轮换后的刷新凭证已经失效');
            }
            await gate.future;
            tm.setTokens(accessToken: b3Fresh, refreshToken: 'refresh-new');
          },
          onAccessExpired: (_, __) {
            notices++;
          }),
    ]);
    final child = parent.extend();
    child.dio.httpClientAdapter = network;
    try {
      final first = parent.send<Object?>(_method, _path);
      final second = child.send<Object?>(_method, _path);
      await b3Turn();
      await b3Turn();
      final clearedBeforeSuccess = tokens.clears;
      gate.complete();
      final results = await Future.wait([first, second]);
      expect(clearedBeforeSuccess, 0);
      expect(refreshes, 1);
      expect(results.every((result) => result.ok), isTrue);
      expect(tokens.clears, 0);
      expect(notices, 0);
      expect(tokens.accessToken, b3Fresh);
    } finally {
      parent.dispose();
      child.dispose();
    }
  });
}
