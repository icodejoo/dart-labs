// ignore_for_file: avoid_relative_lib_imports
// 组合层：retry_share / recovery
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
        '[DiomanRetry.share × DiomanSharePolicy.retry] 移除 retry 后 share 不再等它结算，不悬挂；旧 setter 重复调用无副作用',
        () async {
      final gate = Completer<void>();
      final adapter = RecordingAdapter((o, n) async {
        await gate.future;
        return jsonBody({tkV: n}, 200);
      });
      final dio = fakeDio(adapter);
      final share = DiomanShare();
      final retry = testRetry();
      final handle = Dioman.install(dio,
          key: const DiomanKey(), share: share, retry: retry);
      // ignore: deprecated_member_use_from_same_package
      retry.share = share;
      // ignore: deprecated_member_use_from_same_package
      retry.share = share;
      handle.remove<DiomanRetry>();

      final a = dio.get<dynamic>(tkX);
      final b = dio.get<dynamic>(tkX);
      await settleAsync();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);
      expect(rs.map((r) => r.data), [
        {tkV: 1},
        {tkV: 1}
      ]);
    });
  });

  group('follower 拿到独立的 Response（#6）', () {
    test(
        '[DiomanRetry.max × DiomanShare.onRequest] follower 不会对 leader 已耗尽的重试再重试一轮',
        () async {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody(failureEnvelope(), 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          retry: testRetry(max: 2, shouldRetry: retryBusinessFailure));

      final rs = await Future.wait([
        dio.get<dynamic>(tkX),
        dio.get<dynamic>(tkX),
      ]).timeout(timeout);

      expect(rs[0].data, failureEnvelope());
      expect(rs[1].data, failureEnvelope());
      expect(adapter.calls, 3, reason: '1 次首发 + 2 次重试，follower 不额外重试');
    });
  });

  group(tkRetry13, () {
    test(
        '[DiomanRetry.share × DiomanShare.onError] 错误阶段 shouldRetry 抛异常：转成 DioException，且 share 的 follower 不悬挂',
        () async {
      final gate = Completer<void>();
      final adapter = RecordingAdapter((o, n) async {
        await gate.future;
        return jsonBody({}, 500);
      });
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          retry: testRetry(shouldRetry: (_, __) => throw StateError(tkBoom)));

      final a = dio
          .get<dynamic>(tkX)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      final b = dio
          .get<dynamic>(tkX)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      await settleAsync();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      for (final r in rs) {
        expect(r, isA<DioException>());
      }
      expect((rs[0] as DioException).error, isA<StateError>());
    });
  });

  group('下游 reject 的传播标志（review2 #6）', () {
    /// 在链尾追加：onResponse 里 reject 的拦截器，以及统计 onError 次数的探针。
    /// tail 的测试辅助入口。
    ({Interceptor rejecter, Interceptor spy, List<int> errorCalls}) tail(
        {required bool callFollowing}) {
      final errorCalls = <int>[];
      final rejecter = InterceptorsWrapper(
        onResponse: (r, h) => h.reject(
          DioException(requestOptions: r.requestOptions, message: tkDownstream),
          callFollowing,
        ),
      );
      final spy = InterceptorsWrapper(onError: (e, h) {
        errorCalls.add(1);
        h.next(e);
      });
      return (rejecter: rejecter, spy: spy, errorCalls: errorCalls);
    }

    for (final recovery in [tkRetry, tkAuth]) {
      for (final following in [false, true]) {
        test(
            '[DiomanRetry.cancel × DiomanShare.onError] $recovery 恢复后下游 reject(callFollowing=$following)：'
            '${following ? "后续错误拦截器继续执行" : "直接终止，后续错误拦截器不再执行"}', () async {
          final adapter = RecordingAdapter((o, n) async => n == 1
              ? jsonBody({}, recovery == tkRetry ? 500 : 401)
              : jsonBody(successEnvelope(), 200));
          final dio = fakeDio(adapter);
          final cancel = DiomanCancel();
          Dioman.install(dio,
              key: const DiomanKey(),
              share: DiomanShare(),
              cancel: cancel,
              auth: recovery == tkAuth ? testAuth(TestTokens(tkT0)) : null,
              retry: recovery == tkRetry ? testRetry() : null);
          final t = tail(callFollowing: following);
          dio.interceptors
            ..add(t.rejecter)
            ..add(t.spy);

          await expectLater(
            dio.get<dynamic>(tkX).timeout(timeout),
            throwsA(isA<DioException>()
                .having((e) => e.message, tkMessage, tkDownstream)),
          );
          expect(t.errorCalls.length, following ? 1 : 0);
          expect(adapter.calls, 2, reason: '后续错误拦截器不会再触发额外恢复');
          expect(cancelAll(dio), 0, reason: '认领已释放，token 已注销');
          // share registry 归零：同 key 的新请求不悬挂。
          adapter.calls = 0;
          await dio
              .get<dynamic>(tkX)
              .then((_) {}, onError: (_) {})
              .timeout(timeout);
        });
      }
    }
  });

  group('pairwise: share + retry', () {
// FIXED (see share_plugin.dart / retry_plugin.dart): passing the SAME
// DiomanShare instance to DiomanRetry's `share` setter registers retry
// as the entry's settler. DiomanShare then defers its own onError
// settlement, so a concurrent follower stays bound to the (not yet
// completed) shared completer instead of being delivered the pre-retry
// failure — and DiomanRetry explicitly completes it once IT reaches the
// true final outcome.
    test(
        '[DiomanRetry.delay × DiomanSharePolicy.retry] FIX: a concurrent follower now receives the RETRIED result, not '
        "the leader's pre-retry failure", () async {
      var attempts = 0;
      final followerJoined = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          // Hold the leader's 500 open until the follower has definitely
          // attached — with a zero backoff delay, the leader's whole
          // fail→retry→succeed cycle could otherwise complete (settling
          // and removing the entry) before the follower even reaches
          // DiomanShare.onRequest.
          await followerJoined.future;
          return respondJson(req, {tkFail: true}, 500);
        }
        return respondJson(req, {tkV: tkRetried}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      installStateful(dio, share: share);
      dio.interceptors.add(DiomanRetry(
        max: 1,
        delay: (_, __, ___, ____) => Duration.zero,
      )..share = share);

      final leader = dio.get<Map<String, dynamic>>(tkData2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final follower = dio.get<Map<String, dynamic>>(tkData2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      followerJoined.complete();

      final leaderResult = await leader.timeout(const Duration(seconds: 3));
      final followerResult = await follower.timeout(const Duration(seconds: 3));
      expect(leaderResult.data, {tkV: tkRetried});
      expect(followerResult.data, {tkV: tkRetried},
          reason: "previously this follower would have been stuck with the "
              'pre-retry 500 (or hung, per the unrelated dio-zone quirk '
              'noted below) — now it correctly observes the retry');
      expect(attempts, 2);
    });
  });

  group('DiomanShare + DiomanRetry', () {
// DiomanRetry's re-issue goes through an interceptor-less Dio (see
// retry_plugin.dart) — it never re-enters DiomanShare.onRequest. Instead
// DiomanRetry registers its settlement responsibility on each request in
// onRequest, so DiomanShare keeps the entry open until the retry's true
// final outcome is known — no manual wiring needed.
    test(
        '[DiomanRetry.delay × DiomanSharePolicy.retry] a NEW caller arriving while the retry is in flight dedupes against '
        'it — the shared entry stays open until the retry settles, without '
        'any manual wiring', () async {
      final retryInFlight = Completer<void>();
      var attempts = 0;
      final server = await TestServer.start((req) async {
        final n = ++attempts;
        if (n == 1) {
          await respondJson(req, {tkFail: true}, 500);
          return;
        }
        if (!retryInFlight.isCompleted) retryInFlight.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await respondJson(req, {tkFrom: tkRetry}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.start),
      ]);
      dio.interceptors
          .add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final a = dio.get<Map<String, dynamic>>(tkData2);
      await retryInFlight.future; // A's retry is mid-flight

      final c = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 3));
      expect(c.data, {tkFrom: tkRetry});
      expect(attempts, 2,
          reason: "C joined A's still-open entry — no third request");

      final aResult = await a.timeout(const Duration(seconds: 3));
      expect(aResult.data, {tkFrom: tkRetry},
          reason: 'A gets its own correct retried result');
    });
  });

  group('pairwise: share + retry', () {
    test(
        '[DiomanRetry.share × DiomanShare.policy] '
        "FIX: a THIRD caller arriving while the retry is still in flight "
        'still dedupes against it (no 3rd network call) — the reentry-skip '
        "marker doesn't disturb DiomanShare's normal dedup for genuinely "
        'new callers', () async {
      var attempts = 0;
      final retryInFlight = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkFail: true}, 500);
        retryInFlight.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return respondJson(req, {tkV: tkRetried}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      installStateful(dio, share: share);
      dio.interceptors.add(DiomanRetry(
        max: 1,
        delay: (_, __, ___, ____) => Duration.zero,
      )..share = share);

      final a = dio.get<Map<String, dynamic>>(tkData2);
      await retryInFlight.future;
      final c = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 3));
      expect(c.data, {tkV: tkRetried});
      expect(attempts, 2, reason: 'C deduped against the in-flight retry');
      expect(
          (await a.timeout(const Duration(seconds: 3))).data, {tkV: tkRetried});
    });
  });
}
