// 组合层：auth_retry / cancel / share（认证恢复期间取消，#1）
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 服务端已收到的请求数。
int _hits = 0;

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 5);

  /// 起一个按请求序号应答的服务：第 1 次 [firstStatus]，第 2 次 401，之后 200。
  Future<TestServer> startServer(int firstStatus, Object firstBody) =>
      TestServer.start((HttpRequest r) async {
        final n = ++_hits;
        if (n == 1) return respondJson(r, firstBody, firstStatus);
        if (n == 2) return respondJson(r, {'e': 'auth'}, 401);
        return respondJson(r, {'ok': true}, 200);
      });

  /// 首发带 token，follower 不带；首发在重试遇 401、等刷新期间被取消，
  /// 取消之后才放行刷新。返回 follower 的结果。
  Future<Response<dynamic>> followerAfterLeaderCancelledInRecovery(
    int firstStatus,
    Object firstBody, {
    DiomanShouldRetry? shouldRetry,
  }) async {
    _hits = 0;
    final server = await startServer(firstStatus, firstBody);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final gate = Completer<void>();
    final started = Completer<void>();
    final tm = TestTokens('t0');
    final handle = Dioman.install(dio,
        key: const DiomanKey(),
        share: DiomanShare(),
        auth: testAuth(tm, onRefresh: (m, _) async {
          if (!started.isCompleted) started.complete();
          await gate.future;
          tm.set('t1');
        }),
        retry: testRetry(max: 2, shouldRetry: shouldRetry));
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    final token = CancelToken();
    final leader = dio.get<dynamic>('/x', cancelToken: token);
    leader.ignore();
    await settleAsync();
    final follower = dio.get<dynamic>('/x');
    follower.ignore();
    await started.future.timeout(timeout);
    token.cancel('user');
    await settleAsync();
    // 取消之后才让刷新完成：auth 此时返回 null，retry 不能把原 401 当结果。
    gate.complete();
    await expectLater(
        leader,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    return follower.timeout(timeout);
  }

  group('认证恢复期间取消（#1）', () {
    test(
        '[DiomanRetry.max × DiomanAuth.new(onRefresh) × DiomanShare.policy] 错误阶段：首发在重试等刷新时被取消，follower 不拿到 401',
        () async {
      final r =
          await followerAfterLeaderCancelledInRecovery(500, {'e': 'boom'});
      expect(r.data, {'ok': true});
    });

    test(
        '[DiomanRetry.shouldRetry × DiomanAuth.new(onRefresh) × DiomanShare.policy] 响应阶段：业务失败重试等刷新时被取消，follower 不拿到原业务失败',
        () async {
      final r = await followerAfterLeaderCancelledInRecovery(200, {'code': 1},
          shouldRetry: retryBusinessFailure);
      expect(r.data, {'ok': true});
    });
  });
}
