// ignore_for_file: avoid_relative_lib_imports
// 组合层：auth_cancel
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

  group(tkCancelAll10, () {
    test(
        '[DiomanAuth.cancel × DiomanCancel.cancelAll] auth 刷新等待期间 cancelAll 能取消',
        () async {
      final refreshGate = Completer<void>();
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 401));
      final dio = fakeDio(adapter);
      final tm = TestTokens(tkT0);
      Dioman.install(dio,
          cancel: DiomanCancel(),
          auth: testAuth(tm, onRefresh: (_, __) async {
            await refreshGate.future;
            tm.set(tkT1);
          }));

      final result = dio
          .get<dynamic>(tkX)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      await settleAsync(80);
      expect(cancelAll(dio, tkBye), 1);
      final r = await result.timeout(const Duration(seconds: 2));
      expect(r, isA<DioException>());
      expect((r as DioException).type, DioExceptionType.cancel);
      refreshGate.complete(); // 收尾，不留悬挂的 Future
    });
  });

  group('取消时释放刷新等待中的认领（review2 #4）', () {
    test(
        '[DiomanAuth.cancel × DiomanCancel.onError] 请求入口等共享刷新时被取消：立刻结束并注销 token 登记',
        () async {
      final refreshStarted = Completer<void>();
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 401));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          cancel: DiomanCancel(),
          auth: testAuth(TestTokens(tkT0), onRefresh: (_, __) {
            if (!refreshStarted.isCompleted) refreshStarted.complete();
            return Completer<void>().future; // 永不完成
          }));

      final a = dio
          .get<dynamic>(tkA3)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      await refreshStarted.future.timeout(timeout);
      final token = CancelToken();
      final b = dio
          .get<dynamic>(tkB, cancelToken: token)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      await settleAsync();
      token.cancel('stop b');
      final rb = await b.timeout(timeout);
      expect((rb as DioException).type, DioExceptionType.cancel);
      await settleAsync();
      expect(cancelAll(dio, tkBye), 1, reason: 'b 的认领已注销，只剩 a 在登记');
      await a.timeout(timeout);
    });
  });

  group('pairwise: cancel + auth', () {
// Now automatable with a real server: the replay genuinely reaches
// this TestServer, so we can deterministically wait for it to actually
// be in flight instead of guessing with a fixed delay.
    test(
        '[DiomanAuth.cancel × DiomanCancel.cancelAll] FIX: passing the same DiomanCancel instance to DiomanAuth lets '
        'cancelAll abort a request currently being replayed', () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final replayStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkError: 1}, 401);
        replayStarted.complete();
        await Completer<void>().future; // replay hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cancel = DiomanCancel();
      installStateful(
        dio,
        cancel: cancel,
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set(tkT1),
          onAccessExpired: (_, __) async {},
        )..cancel = cancel,
      );

      final call = dio.get<void>(tkData2);
      await replayStarted.future; // the replay is now genuinely in flight

      final cancelled = cancelAll(dio, tkTest);
      expect(cancelled, 1,
          reason: 'the replay\'s token is now tracked — cancelAll aborts it');
      await expectLater(
        call.timeout(const Duration(seconds: 2)),
        throwsA(isA<DioException>()
            .having((e) => e.type, tkType, DioExceptionType.cancel)),
      );
    });
  });

  group(tkDiomanAuth, () {
// DiomanAuth's post-failure replay deliberately uses a throwaway `Dio()`
// (see SKILL.md) so it never re-enters the interceptor chain. Against a
// real TestServer that throwaway Dio's `.fetch()` still lands on our
// test server (RequestOptions carries its own already-resolved
// baseUrl), so the replay path is now genuinely observable end-to-end
// instead of only via which AuthFailureAction was chosen.
    test(
        '[DiomanAuth.cancel × DiomanCancel.onRequest] a denied request (no token) still releases the loading/cancel'
        ' brackets installed before auth', () async {
      final tm = TestTokens(null);
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final loadingStates = <bool>[];
      final cancelPlugin = DiomanCancel();
      dio.interceptors.addAll([
        cancelPlugin,
        DiomanLoading(onChanged: loadingStates.add),
        DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
      ]);

      await expectLater(
          dio.get<void>(tkProtected), throwsA(isA<DioException>()));

      expect(loadingStates, [true, false],
          reason: 'loading bracket must release even though auth denied '
              'the request before the network call, or the spinner sticks');
      expect(cancelAll(dio), 0,
          reason: 'the cancel token injected for the denied request must '
              'already be released, not leaked in the registry');
    });
  });

  group('pairwise: cancel + auth', () {
    test(
        '[DiomanAuth.onRequest × DiomanCancel.cancelAll] '
        'without any manual wiring, cancelAll still aborts a request '
        'DiomanAuth is currently replaying — DiomanAuth holds the request, '
        'so DiomanCancel keeps tracking its token for the whole logical '
        'request', () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final replayStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkError: 1}, 401);
        replayStarted.complete();
        await Completer<void>().future; // replay hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(
        dio,
        cancel: DiomanCancel(),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set(tkT1),
          onAccessExpired: (_, __) async {},
          // NOTE: no `cancel` setter needed any more.
        ),
      );

      final call = dio.get<void>(tkData2);
      call.ignore(); // it never settles in this test — the replay hangs

      await replayStarted.future; // the replay is now genuinely in flight

      final cancelled = cancelAll(dio, tkTest);
      expect(cancelled, 1,
          reason: 'the token stays tracked while auth holds the request');
    });
  });
}
