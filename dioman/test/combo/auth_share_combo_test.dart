// ignore_for_file: avoid_relative_lib_imports
// 组合层：auth_share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group('share 结算责任按请求登记（#3 #4 #7）', () {
    test(
        '[DiomanAuth.share × DiomanShare.enabled] share + auth：公开（不受保护）请求不会让 follower 悬挂',
        () async {
      final gate = Completer<void>();
      final adapter = RecordingAdapter((o, n) async {
        await gate.future;
        return jsonBody({tkV: n}, 200);
      });
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          auth: testAuth(TestTokens(tkT0)));

      /// call 的测试辅助入口。
      Future<Response<dynamic>> call() => dio.get<dynamic>('/pub',
          options: Options(extra: {
            DiomanAuth.pluginName: const DiomanAuthOptions(enabled: false),
          }));

      final a = call();
      final b = call();
      await settleAsync();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(adapter.calls, 1);
      expect(rs[0].data, {tkV: 1});
      expect(rs[1].data, {tkV: 1});
      // registry 归零：下一次同key请求是全新请求，不会挂在残留 entry 上。
      await call().timeout(timeout);
      expect(adapter.calls, 2);
    });
    test(
        '[DiomanAuth.share × DiomanShare.enabled] share → auth + DiomanMockAdapter：adapter 在传输层，并发请求被 share 合并成一次 mock 命中，'
        'follower 不悬挂，真实网络不碰，也不残留 share entry', () async {
      final gate = Completer<void>();
      var mockHits = 0;
      final real = RecordingAdapter((o, n) async => jsonBody({tkReal: 1}, 200));
      final dio = fakeDio(real);
      dio.httpClientAdapter = DiomanMockAdapter(inner: real, routes: {
        tkGETM: (o) async {
          mockHits++;
          await gate.future;
          return jsonBody({tkV: 1}, 200);
        }
      });
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          auth: testAuth(TestTokens(tkT0)));

      final a = dio.get<dynamic>(tkM);
      final b = dio.get<dynamic>(tkM);
      await settleAsync();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs.map((r) => r.data), [
        {tkV: 1},
        {tkV: 1}
      ]);
      expect(mockHits, 1, reason: 'adapter 在 share 之下：两个并发请求合并成一次 mock 命中');
      expect(real.calls, 0, reason: 'mock 命中，真实网络一次都没发');
      final c = await dio.get<dynamic>(tkM).timeout(timeout);
      expect(c.data, {tkV: 1});
      expect(mockHits, 2, reason: '之前的 entry 已清，新请求是全新一次命中');
    });
    test(
        '[DiomanAuth.share × DiomanSharePolicy.retry] share + auth + retry：业务失败由 retry 恢复后，follower 拿到最终成功，'
        '不是 auth 提前结算的业务失败', () async {
      final gate = Completer<void>();
      final adapter = RecordingAdapter((o, n) async {
        if (n == 1) {
          await gate.future;
          return jsonBody(failureEnvelope(), 200);
        }
        return jsonBody(successEnvelope(), 200);
      });
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          auth: testAuth(TestTokens(tkT0)),
          retry: testRetry(shouldRetry: retryBusinessFailure),
          normalize: const DiomanNormalize());

      final a = dio.get<dynamic>(tkBiz);
      final b = dio.get<dynamic>(tkBiz);
      await settleAsync();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[0].data, {tkV: 1});
      expect(rs[1].data, {tkV: 1}, reason: 'follower 看到的是恢复后的最终结果');
      expect(adapter.calls, 2);
    });
    test(
        '[DiomanAuth.share × DiomanSharePolicy.retry] share 先于 auth/retry 被移除重装：新 share 照常结算',
        () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({tkV: n}, 200));
      final dio = fakeDio(adapter);
      final handle = Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          auth: testAuth(TestTokens(tkT0)),
          retry: testRetry());
      handle.remove<DiomanShare>();
      handle.insertAfter(handle.plugin<DiomanKey>()!, DiomanShare());

      final rs = await Future.wait([
        dio.get<dynamic>(tkX),
        dio.get<dynamic>(tkX),
      ]).timeout(timeout);
      expect(rs[0].data, rs[1].data);
      expect(adapter.calls, 1);
    });
  });

  group('auth 请求入口回调抛异常（review2 #5）', () {
    for (final which in [tkExpiresAt, tkNow, tkBuildHeader, tkIsProtected]) {
      test(
          '[DiomanAuth.share × DiomanShare.onError] $which 抛异常：转成 DioException，不悬挂，认领与 share 条目都释放',
          () async {
        var boom = true;
        final adapter =
            RecordingAdapter((o, n) async => jsonBody({tkV: n}, 200));
        final dio = fakeDio(adapter);
        final tm = TestTokens(tkT0);
        final cancel = DiomanCancel();
        final auth = DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set(tkT1),
          onAccessExpired: (_, __) async {},
          isProtected: which == tkIsProtected
              ? (_) => boom ? throw StateError(tkIsProtected) : true
              : null,
          expiresAt: (which == tkExpiresAt || which == tkNow)
              ? (t) => boom && which == tkExpiresAt
                  ? throw StateError(tkExpiresAt)
                  : DateTime(2999)
              : null,
          now: which == tkNow
              ? () => boom ? throw StateError(tkNow) : DateTime(2000)
              : DateTime.now,
          buildHeader: which == tkBuildHeader
              ? (t) => boom ? throw StateError(tkBuildHeader) : 'B $t'
              : null,
        );
        Dioman.install(dio,
            key: const DiomanKey(),
            share: DiomanShare(),
            cancel: cancel,
            auth: auth);

        final rs = await Future.wait([
          dio
              .get<dynamic>(tkX)
              .then<Object>((_) => tkOk, onError: (Object e) => e),
          dio
              .get<dynamic>(tkX)
              .then<Object>((_) => tkOk, onError: (Object e) => e),
        ]).timeout(timeout);
        for (final r in rs) {
          expect(r, isA<DioException>());
          expect((r as DioException).error, isA<StateError>());
        }
        expect(adapter.calls, 0);
        expect(cancelAll(dio), 0, reason: 'token 已注销');

        boom = false;
        final ok = await dio.get<dynamic>(tkX).timeout(timeout);
        expect(ok.data, {tkV: 1}, reason: 'share 条目已清，新请求是全新请求');
      });
    }
  });

  group('错误阶段落败者的收尾（review2 #2）', () {
    test(
        '[DiomanAuth.cancel × DiomanShare.policy] policy=end + auth：被取代的 A 失败后，auth 认领注销，token 登记清空',
        () async {
      final gates = <Completer<int>>[];
      final adapter = RecordingAdapter((o, n) async {
        final g = Completer<int>();
        gates.add(g);
        final status = await g.future;
        return jsonBody({tkV: n}, status);
      });
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.end),
          cancel: DiomanCancel(),
          auth: testAuth(TestTokens(tkT0)));

      final a = dio.get<dynamic>(tkX);
      final b = dio.get<dynamic>(tkX);
      await settleAsync();
      gates[0].complete(500);
      await settleAsync();
      gates[1].complete(200);
      final rs = await Future.wait([a, b]).timeout(timeout);
      expect(rs.map((r) => r.data), [
        {tkV: 2},
        {tkV: 2}
      ]);
      expect(cancelAll(dio), 0);
    });
  });

  group('取消时释放刷新等待中的认领（review2 #4）', () {
    test(
        '[DiomanAuth.cancel × DiomanShare.onError] leader 在 auth 刷新等待时被取消：认领释放，follower 接手后仍受 cancelAll 控制，token 登记清空',
        () async {
      final refreshStarted = Completer<void>();
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 401));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          cancel: DiomanCancel(),
          auth: testAuth(TestTokens(tkT0), onRefresh: (_, __) {
            if (!refreshStarted.isCompleted) refreshStarted.complete();
            return Completer<void>().future; // 永不完成，刻意不放行
          }));

      final a = dio
          .get<dynamic>(tkX)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      final b = dio
          .get<dynamic>(tkX)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      await refreshStarted.future.timeout(timeout);
      await settleAsync();
      expect(cancelAll(dio, tkBye), 1);

      // 首发取消只结束首发；follower 重新入链接手，带着 cancel 注入的 token
      // 继续等（永不完成的）刷新——它受 cancelAll 控制，不会悬挂。
      final first = await a.timeout(timeout);
      expect(first, isA<DioException>());
      expect((first as DioException).type, DioExceptionType.cancel);
      await settleAsync();
      expect(cancelAll(dio, tkBye), 1, reason: '接手的 follower 已被 cancel 追踪');

      final second = await b.timeout(timeout);
      expect(second, isA<DioException>());
      expect((second as DioException).type, DioExceptionType.cancel);
      expect(cancelAll(dio), 0);
    });
  });

  group('share end/race 窄组合（已知限制 #1 #2 #3）', () {
    test(
        '[DiomanAuth.cancel × DiomanSharePolicy.race] race + auth：A 的 auth 回调抛异常、B 随后成功，A 仍取 B 的结果',
        () async {
      final gates = <Completer<void>>[];
      final adapter = RecordingAdapter((o, n) async {
        final g = Completer<void>();
        gates.add(g);
        await g.future;
        return n == 1 ? jsonBody({}, 401) : jsonBody({tkV: n}, 200);
      });
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.race),
          cancel: DiomanCancel(),
          auth: testAuth(TestTokens(tkT0),
              onRefresh: (_, __) => throw StateError(tkBoom)));

      /// call 的测试辅助入口。
      Future<Object> call() => dio
          .get<dynamic>(tkX)
          .then<Object>((r) => r, onError: (Object e) => e);
      final a = call();
      final b = call();
      await settleAsync();
      gates[0].complete();
      await settleAsync();
      gates[1].complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      for (final r in rs) {
        expect(r, isA<Response<dynamic>>());
        expect((r as Response).data, {tkV: 2});
      }
      expect(cancelAll(dio), 0);
    });
  });

  group('pairwise: share + auth', () {
// Now automatable with a real server: DiomanAuth's `_replay` (a bare,
// interceptor-less Dio) genuinely reaches this test's TestServer,
// instead of the real internet — so refresh+replay can actually
// succeed.
    test(
        '[DiomanAuth.share × DiomanShare.policy] a solo caller correctly gets its own refreshed+replayed result '
        'through DiomanShare+DiomanAuth together', () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkError: 1}, 401);
        return respondJson(req, {tkV: tkRefreshed}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(
        dio,
        share: DiomanShare(policy: DiomanSharePolicy.start),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set(tkT1),
          onAccessExpired: (_, __) async {},
        ),
      );

      final leaderResult = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 3));
      expect(leaderResult.data, {tkV: tkRefreshed},
          reason: 'the leader correctly observes its own refreshed+replayed '
              'result, independent of the shared entry');
      expect(attempts, 2, reason: '401 then the successful replay');
    });
// FIXED (same mechanism as "share + retry" above): passing the SAME
// DiomanShare instance to DiomanAuth's `share` setter registers auth as
// the entry's settler for this key, so a concurrent follower gets the
// REFRESHED result instead of the stale pre-refresh 401.
    test(
        '[DiomanAuth.new(now) × DiomanShare.policy] FIX: a concurrent follower now receives the REFRESHED+replayed '
        "result, not the leader's pre-refresh 401", () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final followerJoined = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          // Hold the leader's 401 open until the follower has definitely
          // attached — otherwise, since onRefresh here has no artificial
          // delay, the leader's whole 401→refresh→replay cycle could
          // complete (and settle+remove the entry) before the follower
          // even reaches DiomanShare.onRequest, making it start its own
          // fresh leader entry instead of truly joining this one.
          await followerJoined.future;
          return respondJson(req, {tkError: 1}, 401);
        }
        return respondJson(req, {tkV: tkRefreshed}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      installStateful(dio, share: share);
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => tm.set(tkT1),
        onAccessExpired: (_, __) async {},
      )..share = share);

      final leader = dio.get<Map<String, dynamic>>(tkData2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final follower = dio.get<Map<String, dynamic>>(tkData2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      followerJoined.complete();

      final leaderResult = await leader.timeout(const Duration(seconds: 3));
      final followerResult = await follower.timeout(const Duration(seconds: 3));
      expect(leaderResult.data, {tkV: tkRefreshed});
      expect(followerResult.data, {tkV: tkRefreshed},
          reason: "previously this follower would have been stuck with the "
              'pre-refresh 401 — now it correctly observes the replay');
      expect(attempts, 2);
    });
  });
}
