// ignore_for_file: avoid_relative_lib_imports
// 规则层：auth / flow
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/client.dart' show Tokens;
import '../accept/lib/client.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group(tk9, () {
    test('[DiomanAuth.dio][DiomanAuth.onRequest] auth 的重放走宿主的 adapter 和 transformer', () async {
      final transformer = CountingTransformer();
      final adapter = RecordingAdapter(
          (o, n) async => n == 1 ? jsonBody({}, 401) : jsonBody({tkV: n}, 200));
      final dio = fakeDio(adapter, transformer: transformer);
      Dioman.install(dio, auth: testAuth(TestTokens(tkT0)));

      final r = await dio.get<dynamic>(tkX).timeout(timeout);
      expect(r.data, {tkV: 2});
      expect(adapter.calls, 2);
      expect(transformer.responses, 2);
    });
  });

  group('刷新成功后的重放失败（#11）', () {
    test('[DiomanAuth.onRequest] 重放遇到 500：有效 token 保留、不触发过期，抛出 500 而不是旧 401',
        () async {
      final adapter = RecordingAdapter(
          (o, n) async => n == 1 ? jsonBody({}, 401) : jsonBody({}, 500));
      final dio = fakeDio(adapter);
      final tm = TestTokens(tkT0);
      var expired = 0;
      Dioman.install(dio, auth: testAuth(tm, onExpired: () => expired++));

      await expectLater(
        dio.get<dynamic>(tkX).timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, tkStatus, 500)),
      );
      expect(tm.accessToken, tkT1);
      expect(expired, 0);
    });
    test('[DiomanTokenManager.clear][DiomanAuth.onRequest] 重放仍是 401：明确的认证失败，清会话并触发过期', () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 401));
      final dio = fakeDio(adapter);
      final tm = TestTokens(tkT0);
      var expired = 0;
      Dioman.install(dio, auth: testAuth(tm, onExpired: () => expired++));

      await expectLater(
          dio.get<dynamic>(tkX).timeout(timeout), throwsA(isA<DioException>()));
      expect(tm.accessToken, isNull);
      expect(expired, 1);
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
        '[DiomanAuthFailureAction.refresh][DiomanAuthFailureAction.replay] 401 with the default Bearer header triggers a refresh action, not '
        'replay/expire (regression: comparing the formatted header against '
        'the raw store token made the refresh branch unreachable)', () async {
      final tm = TestTokens('old-token');
      var refreshCalls = 0;
      final server = await TestServer.start(
          (req) => respondJson(req, {tkError: tkExpired}, 401));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (t, _) async => refreshCalls++,
        onAccessExpired: (_, __) async {},
      ));

      await expectLater(dio.get<void>(tkData2), throwsA(isA<DioException>()));

      expect(refreshCalls, 1,
          reason: 'the request carried the token that is still current in '
              'the store, so this must route to refresh — the pre-fix '
              'Bearer-prefix mismatch always fell through to replay/expire '
              'and never called onRefresh at all');
    });
// ── Proactive refresh (B1) ────────────────────────────────────────────
// With an `expiresAt` callback, an already-expired token is refreshed in
// onRequest BEFORE sending, so requests go out once with a fresh token —
// no doomed 401 round-trip. Unlike the reactive replay, this path does hit
// the real test server (it's a normal onRequest → send), so the injected
// header and network call count are directly observable.
    /// expiresAtFn 的测试辅助入口。
    DateTime? expiresAtFn(String token) => token == tkNew
        ? DateTime.now().add(const Duration(hours: 1)) // fresh
        : DateTime.now().subtract(const Duration(seconds: 1));
    test(
        '[DiomanAuth.new(onRefresh)][DiomanAuth.new(expiresAt)] proactive refresh is opt-in: with no expiresAt callback the token '
        'is used as-is and onRefresh is never called', () async {
      final tm = TestTokens(tkOld);
      var refreshCalls = 0;
      final sentAuth = <String>[];

      final server = await TestServer.start((req) async {
        sentAuth.add(req.headers.value(tkAuthorization2) ?? tkNone2);
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => refreshCalls++,
        onAccessExpired: (_, __) async {},
      ));

      await dio.get<void>(tkData2);

      expect(refreshCalls, 0,
          reason: 'no expiresAt ⇒ purely reactive, no pre-send refresh');
      expect(sentAuth, [tkBearerOld]);
    });
    test(
        '[DiomanAuthFailureAction.refresh][DiomanAuth.new(expiresAt)] proactive refresh failure clears the session and rejects before '
        'the request is ever sent', () async {
      final tm = TestTokens(tkOld);
      var expiredCalls = 0;
      var calls = 0;

      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        expiresAt: expiresAtFn,
        onRefresh: (_, __) async => throw StateError('refresh boom'),
        onAccessExpired: (_, __) async => expiredCalls++,
      ));

      await expectLater(
        dio.get<void>(tkData2).timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
      );

      expect(expiredCalls, 1,
          reason: 'a failed proactive refresh must run onAccessExpired');
      expect(tm.accessToken, isNull, reason: 'session must be cleared');
      expect(calls, 0,
          reason: 'the request must never reach the network with a dead token');
    });
// ── Now observable end-to-end: refresh + replay success ───────────────
// With a real TestServer, the throwaway replay Dio genuinely reaches the
// server. Unlike the tests above (server always 401s), here the server
// stops 401ing after the refresh, so we can assert on the full
// refresh → replay → success path, not just which action was chosen.
    test(
        '[DiomanAuth.onError][DiomanAuthFailureAction.refresh][DiomanAuthFailureAction.replay] a 401, successful refresh, and replay deliver the replayed '
        'response to the original caller', () async {
      final tm = TestTokens(tkOld);
      var refreshCalls = 0;

      final server = await TestServer.start((req) async {
        final auth = req.headers.value(tkAuthorization2);
        if (auth == tkBearerNew) {
          await respondJson(req, {tkOk: true}, 200);
        } else {
          await respondJson(req, {tkError: tkExpired}, 401);
        }
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {
          refreshCalls++;
          tm.setToken(tkNew);
        },
        onAccessExpired: (_, __) async {},
      ));

      final res = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 5));

      expect(refreshCalls, 1);
      expect(res.data![tkOk], true,
          reason: 'the replay must actually reach the real server with the '
              'refreshed token and deliver its success response back to '
              'the original caller — this path used to be untestable '
              'offline because the throwaway replay Dio bypassed the fake '
              "adapter");
    });
  });

  test(
      '[DiomanAuthFailureAction.replay][DiomanAuth.new(onAccessExpired)] auth replay 分支传播 500 而不清掉有效会话',
      () async {
    var hits = 0;
    final server = await TestServer.start(
        (request) => respondJson(request, {}, ++hits == 1 ? 401 : 500));
    final tokens = Tokens()..replace(replayField, replayFailure);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
          tokenManager: tokens,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
          onFailure: (_, response) => response.statusCode == 401
              ? DiomanAuthFailureAction.replay
              : DiomanAuthFailureAction.others,
        ));
    try {
      await expectLater(
          dio.get<dynamic>(replayPath),
          throwsA(isA<DioException>().having(
              (error) => error.response?.statusCode, replayFailure, 500)));
      expect(tokens.accessToken, replayField);
      expect(hits, 2);
    } finally {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    }
  });

  for (final status in [401, 500]) {
    test(
        '[DiomanAuthFailureAction.expired][DiomanAuthFailureAction.replay] auth replay 分支遇到 $status 时仅认证失败结束会话',
        () async {
      final server =
          await TestServer.start((request) => respondJson(request, {}, status));
      final tokens = Tokens()..replace(replayField, replayFailure);
      var expired = 0;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final handle = Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: tokens,
            onRefresh: (_, __) async {},
            onAccessExpired: (_, __) async {
              expired++;
            },
            onFailure: (_, response) => response.statusCode == 401
                ? DiomanAuthFailureAction.replay
                : DiomanAuthFailureAction.others,
          ));
      try {
        await expectLater(
            dio.get<dynamic>(replayPath), throwsA(isA<DioException>()));
        expect(expired, status == 401 ? 1 : 0);
      } finally {
        handle.dispose();
        dio.close(force: true);
        await server.close();
      }
    });
  }
}
