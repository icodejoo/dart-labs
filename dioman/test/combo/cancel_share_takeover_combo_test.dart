// 组合层：cancel_share（首发取消后 follower 重新入链接手，#2 #3 #4）
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 一次测试的环境：真实服务、已装配的 dio、服务端请求计数。
class _Env {
  _Env(this.server, this.dio, this.handle);

  /// 真实本地服务。
  final TestServer server;

  /// 已装配插件的客户端。
  final Dio dio;

  /// 插件装配句柄。
  final DiomanHandle handle;

  /// 服务端已收到的请求数。
  int hits = 0;

  /// 服务端仍卡在处理中的请求数（客户端断开后会回落）。
  int open = 0;
}

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 5);
  final releases = <Completer<void>>[];

  tearDown(() {
    for (final c in releases) {
      if (!c.isCompleted) c.complete();
    }
    releases.clear();
  });

  /// 让服务端处理器挂住，客户端断开或测试结束才放行。
  Future<void> hang(HttpRequest r) async {
    final gate = Completer<void>();
    releases.add(gate);
    // 摘下底层 socket 监听断开：客户端取消后连接关闭，借此统计"仍在途"的传输。
    final socket = await r.response.detachSocket(writeHeaders: false);
    socket.listen((_) {}, onDone: () {
      if (!gate.isCompleted) gate.complete();
    }, onError: (Object _) {
      if (!gate.isCompleted) gate.complete();
    });
    await gate.future;
    socket.destroy();
  }

  /// 起服务并装配 key+share+cancel(+auth+retry)。[respond] 按请求序号（从 1
  /// 起）应答。
  Future<_Env> setup(
    Future<void> Function(HttpRequest r, int n) respond, {
    bool auth = false,
    bool retry = false,
    void Function()? onRefresh,
  }) async {
    late _Env env;
    final server = await TestServer.start((HttpRequest r) async {
      final n = ++env.hits;
      env.open++;
      try {
        await respond(r, n);
      } finally {
        env.open--;
      }
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final tm = TestTokens('t0');
    final handle = Dioman.install(dio,
        key: const DiomanKey(),
        share: DiomanShare(),
        cancel: DiomanCancel(),
        auth: auth
            ? testAuth(tm, onRefresh: (_, __) async {
                onRefresh?.call();
                tm.set('t1');
              })
            : null,
        retry: retry ? testRetry(max: 2) : null);
    env = _Env(server, dio, handle);
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    return env;
  }

  /// 等服务端收到至少 [n] 个请求。
  Future<void> waitHits(_Env env, int n) async {
    final end = DateTime.now().add(timeout);
    while (env.hits < n) {
      if (DateTime.now().isAfter(end)) fail('服务端只收到 ${env.hits} 个请求');
      await settleAsync(5);
    }
  }

  /// 发起 GET，并避免未处理异常。
  Future<Response<dynamic>> get(Dio dio, {CancelToken? token}) {
    final f = dio.get<dynamic>('/x', cancelToken: token);
    f.ignore();
    return f;
  }

  final isCancel = throwsA(isA<DioException>()
      .having((e) => e.type, 'type', DioExceptionType.cancel));

  group('首发取消后 follower 重新入链接手（#2 #3 #4）', () {
    test(
        '[DiomanShare.onRequest × DiomanAuth.onRefresh] 接手请求遇 401：auth 刷新并重放成功，首发仍拿到取消',
        () async {
      var refreshed = 0;
      final env = await setup((r, n) async {
        if (n == 1) return hang(r);
        if (n == 2) return respondJson(r, {'e': 'auth'}, 401);
        return respondJson(r, {'ok': true}, 200);
      }, auth: true, onRefresh: () => refreshed++);
      final token = CancelToken();
      final leader = get(env.dio, token: token);
      await waitHits(env, 1);
      final follower = get(env.dio);
      await settleAsync();
      token.cancel('user');

      await expectLater(leader, isCancel);
      final r = await follower.timeout(timeout);
      expect(r.data, {'ok': true});
      expect(refreshed, 1);
    });

    test('[DiomanShare.onRequest × DiomanRetry.max] 接手请求遇可重试 500：retry 重试成功',
        () async {
      final env = await setup((r, n) async {
        if (n == 1) return hang(r);
        if (n == 2) return respondJson(r, {'e': 'boom'}, 500);
        return respondJson(r, {'ok': true}, 200);
      }, retry: true);
      final token = CancelToken();
      final leader = get(env.dio, token: token);
      await waitHits(env, 1);
      final follower = get(env.dio);
      await settleAsync();
      token.cancel('user');

      await expectLater(leader, isCancel);
      final r = await follower.timeout(timeout);
      expect(r.data, {'ok': true});
      expect(env.hits, 3);
    });

    test(
        '[DiomanShare.onRequest × DiomanCancel.cancelAll] 首发与 follower 都不带 token：接手请求受 cancelAll 控制，不残留在途传输',
        () async {
      final env = await setup((r, n) => hang(r));
      final leader = get(env.dio);
      await waitHits(env, 1);
      final follower = get(env.dio);
      await settleAsync();

      // 第一次 cancelAll 只能取消首发（follower 还没过 cancel 插件）。
      cancelAll(env.dio, 'first');
      await expectLater(leader, isCancel);
      await waitHits(env, 2); // follower 接手，已带着 cancel 注入的 token 发出
      // 第二次 cancelAll 必须能停掉接手请求。
      cancelAll(env.dio, 'second');
      await expectLater(follower.timeout(timeout), isCancel);
      final end = DateTime.now().add(timeout);
      while (env.open > 0 && DateTime.now().isBefore(end)) {
        await settleAsync(10);
      }
      expect(env.open, 0, reason: '取消后服务端不应还有在途传输');
    });

    test(
        '[DiomanShare.onRequest × DiomanCancel.cancelAll] multipart FormData 共享：首发取消后 follower 用自己未消费的 FormData 成功',
        () async {
      String? received;
      final env = await setup((r, n) async {
        if (n == 1) return hang(r);
        received = r.headers.contentType?.mimeType;
        await r.drain<void>();
        return respondJson(r, {'ok': true}, 200);
      });
      Future<Response<dynamic>> post(CancelToken? t) {
        final f = env.dio.post<dynamic>('/x',
            data: FormData.fromMap({'a': '1'}), cancelToken: t);
        f.ignore();
        return f;
      }

      final token = CancelToken();
      final leader = post(token);
      await waitHits(env, 1);
      final follower = post(null);
      await settleAsync();
      token.cancel('user');

      await expectLater(leader, isCancel);
      final r = await follower.timeout(timeout);
      expect(r.data, {'ok': true});
      expect(received, 'multipart/form-data');
    });

    test(
        '[DiomanShare.onRequest × DiomanCancel.cancelAll] 全部调用方依次取消：逐个接手后 entry 结算，不悬挂，同 key 新请求重新开始',
        () async {
      final env = await setup((r, n) async {
        if (n <= 3) return hang(r);
        return respondJson(r, {'ok': true}, 200);
      });
      final t0 = CancelToken(), t1 = CancelToken(), t2 = CancelToken();
      final c0 = get(env.dio, token: t0);
      await waitHits(env, 1);
      final c1 = get(env.dio, token: t1);
      final c2 = get(env.dio, token: t2);
      await settleAsync();

      t0.cancel('0');
      await waitHits(env, 2); // c1 接手
      t1.cancel('1');
      await waitHits(env, 3); // c2 接手
      t2.cancel('2');

      await expectLater(c0, isCancel);
      await expectLater(c1.timeout(timeout), isCancel);
      await expectLater(c2.timeout(timeout), isCancel);
      // entry 已摘除：新请求是全新首发，不会挂在残留 entry 上。
      final r = await get(env.dio).timeout(timeout);
      expect(r.data, {'ok': true});
      expect(env.hits, 4);
    });
  });
}
