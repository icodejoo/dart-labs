import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/diagnostics.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/invariant_harness.dart';

/// 测试共用的方法。
const _method = 'GET';

/// 测试共用的路径。
const _path = '/session';

/// 测试共用的路由。
const _route = 'GET:/session';

/// 验证共享会话在卸载和登录之间的边界。
void main() {
  for (final keepOwner in [false, true]) {
    test('[DiomanAuth.onRefresh][Dioman.dispose] 迟到失败 keepOwner=$keepOwner',
        () async {
      final tokens = TestTokens();
      final gate = Completer<void>();
      final started = Completer<void>();
      var notices = 0;
      final network = FakeNetwork()
        ..routes[_route] = [const FakeReply(status: 401)];
      final parent = testClient(network: network, plugins: [
        DiomanAuth<Result>(
            tokenManager: tokens,
            onRefresh: (_, __) {
              started.complete();
              return gate.future;
            },
            onAccessExpired: (_, __) {
              notices++;
            }),
      ]);
      final child = keepOwner ? parent.extend() : null;
      child?.dio.httpClientAdapter = network;
      final first = parent.send<Object?>(_method, _path);
      await started.future;
      final second = child?.send<Object?>(_method, _path);
      await b3Turn();
      expect(DiomanAuthDiagnostics.sessions, 1);
      expect(DiomanAuthDiagnostics.owners, keepOwner ? 2 : 1);
      final instance = parent.plugin<DiomanPluginInstance<Result>>()!;
      parent.dispose();
      instance.dispose();
      gate.completeError(StateError('刷新失败'));
      await b3Turn();
      await first;
      if (second != null) await second;
      expect(tokens.clears, keepOwner ? 1 : 0);
      expect(notices, keepOwner ? 1 : 0);
      child?.dispose();
      SharedResourceProbe.assertEmpty();
    });
  }
  test('[DiomanAuth.onAccessDenied] 无凭证并发只通知一次，登录后复位', () async {
    final tokens = TestTokens(null);
    var notices = 0;
    final api = testClient(plugins: [
      DiomanAuth<Result>(
          tokenManager: tokens,
          onRefresh: (_, __) {},
          onAccessExpired: (_, __) {
            notices++;
          })
    ]);
    await Future.wait(
        List.generate(8, (_) => api.send<Object?>(_method, _path)));
    expect(notices, 1);
    tokens.setTokens(accessToken: b3Fresh);
    expect((await api.send<Object?>(_method, _path)).ok, isTrue);
    tokens.clear();
    await Future.wait(
        List.generate(8, (_) => api.send<Object?>(_method, _path)));
    expect(notices, 2);
  });
  test('[DiomanAuth.onRefresh][Dioman.dispose] 旧窗口不影响重新安装的会话', () async {
    final tokens = TestTokens();
    final gate = Completer<void>();
    final started = Completer<void>();
    var notices = 0;
    final config = DiomanAuth<Result>(
        tokenManager: tokens,
        onRefresh: (_, __) {
          started.complete();
          return gate.future;
        },
        onAccessExpired: (_, __) {
          notices++;
        });
    final old = testClient(
        network: FakeNetwork()..routes[_route] = [const FakeReply(status: 401)],
        plugins: [config]);
    final request = old.send<Object?>(_method, _path);
    await started.future;
    old.dispose();
    final fresh = testClient(plugins: [config]);
    gate.completeError(StateError('旧窗口失败'));
    await b3Turn();
    await request;
    expect(tokens.clears, 0);
    expect(notices, 0);
    expect((await fresh.send<Object?>(_method, _path)).ok, isTrue);
  });
}
