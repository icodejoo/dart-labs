// ignore_for_file: avoid_relative_lib_imports
// 规则层：auth / options
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group('DiomanAuth: defaultAuthFailure classification', () {
// defaultAuthFailure is exported as a standalone top-level function
// specifically so its classification logic is unit-testable without
// having to orchestrate the full request/response chain (its no-token
// branch, in particular, can only occur in production via a narrow
// concurrent-clear race — trivial to hit directly, impractical to force
// deterministically through a real request).
    test(
        '[DiomanAuthFailureAction.deny][DiomanAuthFailureAction.expired] with no token in the store: a 401 classifies as expired, a 403 '
        'as deny', () {
      final tm = TestTokens(null);
      final opts = RequestOptions(path: tkData2);
      expect(
        defaultAuthFailure(
            tm,
            Response<dynamic>(requestOptions: opts, statusCode: 401),
            tkAuthorization),
        DiomanAuthFailureAction.expired,
      );
      expect(
        defaultAuthFailure(
            tm,
            Response<dynamic>(requestOptions: opts, statusCode: 403),
            tkAuthorization),
        DiomanAuthFailureAction.deny,
      );
    });
    test(
        '[DiomanAuth.new(ready)][DiomanAuthOptions.ready] a custom ready callback (instead of buildHeader) still reaches a '
        'successful replay end-to-end — no raw token is stashed for it, so '
        'classification falls back to the header-fallback path exercised '
        'above, either action of which still replays and recovers', () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkE: 1}, 401);
        return respondJson(req, {tkV: tkOk}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => tm.set(tkT1),
        onAccessExpired: (_, __) async {},
        ready: (tm, opts) async {
          opts.headers[tkAuthorization] = 'Bearer ${tm.accessToken}';
        },
      ));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data, {tkV: tkOk});
      expect(attempts, 2);
    });
  });

  group('DiomanAuth: additional realistic branches', () {
    test(
        '[DiomanAuth.new(onAccessDenied)][DiomanAuth.new(onAccessExpired)] a custom onAccessDenied callback is used (instead of falling back '
        'to onAccessExpired) when a protected request has no token', () async {
      final tm = TestTokens(null);
      var deniedCalls = 0;
      var expiredCalls = 0;
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async => expiredCalls++,
        onAccessDenied: (_, __) async => deniedCalls++,
      ));

      await expectLater(dio.get<void>(tkData2), throwsA(isA<DioException>()));
      expect(deniedCalls, 1);
      expect(expiredCalls, 0);
    });
    test(
        '[DiomanAuth.new(onFailure)][DiomanAuthOptions.onFailure] a custom onFailure callback can force the deny or expired action '
        'directly, regardless of the default classification', () async {
      final tm = TestTokens(tkT0);
      var deniedCalls = 0;
      var expiredCalls = 0;
      final server =
          await TestServer.start((req) => respondJson(req, {tkE: 1}, 401));
      addTearDown(server.close);

      final dio1 = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio1.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
        onAccessDenied: (_, __) async => deniedCalls++,
        onFailure: (_, __) => DiomanAuthFailureAction.deny,
      ));
      await expectLater(dio1.get<void>(tkData2), throwsA(isA<DioException>()));
      expect(deniedCalls, 1);

      final dio2 = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio2.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async => expiredCalls++,
        onFailure: (_, __) => DiomanAuthFailureAction.expired,
      ));
      await expectLater(dio2.get<void>(tkData2), throwsA(isA<DioException>()));
      expect(expiredCalls, 1);
    });
    test(
        '[DiomanAuth.new(isProtected)][DiomanAuthOptions.isProtected] a custom isProtected callback decides per-request whether auth '
        'applies at all', () async {
      final tm = TestTokens(null); // no token
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
        isProtected: (opts) => opts.path.startsWith(tkProtected),
      ));

      // Unprotected path: no token needed, passes straight through.
      final r = await dio.get<void>(tkPublic);
      expect(r.statusCode, 200);

      // Protected path: no token ⇒ denied.
      await expectLater(
          dio.get<void>('/protected/x'), throwsA(isA<DioException>()));
    });
  });

  group(tkPerRequestOptionsOverrides, () {
    test(
        '[DiomanAuth.enabled][DiomanAuthOptions.enabled] DiomanAuthOptions(enabled: false) marks a request unprotected',
        () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: TestTokens(null), // no token
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
      ));

      // With no token, a protected call would be denied; enabled:false must
      // let it through untouched.
      final res = await dio.get<void>(
        tkPublic,
        options: Options(
            extra: {tkDiomanAuth2: const DiomanAuthOptions(enabled: false)}),
      );

      expect(res.statusCode, 200);
    });
  });

  group(tkNewlyWiredOptionsFieldsFullConstructorOptionsParity, () {
    test(
        '[DiomanAuth.new(buildHeader)][DiomanAuth.new(headerKey)] DiomanAuthOptions.headerKey/buildHeader override the plugin '
        'defaults for a single call', () async {
      String? customAuth;
      var hasAuthorization = false;
      final server = await TestServer.start((req) async {
        customAuth = req.headers.value('x-custom-auth');
        hasAuthorization = req.headers.value(tkAuthorization2) != null;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: TestTokens('tok'),
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
      ));

      await dio.get<void>(
        tkX,
        options: Options(extra: {
          tkDiomanAuth2: DiomanAuthOptions(
            headerKey: 'X-Custom-Auth',
            buildHeader: (t) => 'Token $t',
          ),
        }),
      );

      expect(customAuth, 'Token tok',
          reason: 'per-request headerKey/buildHeader must be honoured');
      expect(hasAuthorization, isFalse,
          reason: 'the default header key must not also be set');
    });
  });
}
