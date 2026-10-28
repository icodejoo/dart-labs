// ignore_for_file: avoid_relative_lib_imports
// 边界层：auth / replay
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/client.dart' show Tokens;
import '../../test/accept/lib/client.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group(tk9, () {
    test('[DiomanAuth.onError][DiomanAuth.onRequest] FormData 请求体在 auth 刷新后也能重放', () async {
      final adapter = RecordingAdapter(
          (o, n) async => n == 1 ? jsonBody({}, 401) : jsonBody({tkV: n}, 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio, auth: testAuth(TestTokens(tkT0)));

      final r = await dio
          .post<dynamic>(tkUp, data: FormData.fromMap({tkA2: tk1}))
          .timeout(timeout);
      expect(r.data, {tkV: 2});
      expect(adapter.seen.last.headers[tkAuthorization], tkBearerT1);
    });
    test('[DiomanAuth.onError][DiomanAuth.onRequest] Stream 请求体 401：auth 刷新后也不重放，且不清会话', () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 401));
      final dio = fakeDio(adapter);
      final tm = TestTokens(tkT0);
      var expired = 0;
      Dioman.install(dio, auth: testAuth(tm, onExpired: () => expired++));

      await expectLater(
        dio
            .post<dynamic>(tkUp,
                data: Stream.fromIterable([
                  Uint8List.fromList([1])
                ]),
                options: Options(headers: {Headers.contentLengthHeader: 1}))
            .timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, tkStatus, 401)),
      );
      expect(adapter.calls, 1);
      expect(tm.accessToken, tkT1, reason: '刷新成功，只是请求体无法重放');
      expect(expired, 0);
    });
  });

  group('刷新成功后的重放失败（#11）', () {
    test('[DiomanAuth.onRequest] 清会话前校验 token generation：别人已刷新出新 token 就不清',
        () async {
      final tm = TestTokens(tkT0);
      final adapter = RecordingAdapter((o, n) async {
        if (n == 1) return jsonBody({}, 401);
        tm.set(tkT2); // 重放进行中，别的请求又刷新出了新会话
        return jsonBody({}, 401);
      });
      final dio = fakeDio(adapter);
      var expired = 0;
      Dioman.install(dio, auth: testAuth(tm, onExpired: () => expired++));

      await expectLater(
          dio.get<dynamic>(tkX).timeout(timeout), throwsA(isA<DioException>()));
      expect(tm.accessToken, tkT2);
      expect(expired, 0);
    });
  });

  group('DiomanAuth: defaultAuthFailure classification', () {
    test(
        '[defaultAuthFailure][DiomanAuthFailureAction.refresh][DiomanAuthFailureAction.replay] falls back to reading the header directly when no raw token was '
        'stashed (e.g. a custom `ready` callback bypassed the stash), and '
        'still correctly classifies refresh vs replay', () {
      final tm = TestTokens(tkT0);
      // The header-fallback compares the RAW header value against the raw
      // store token verbatim — it does NOT strip a "Bearer " prefix (that
      // stripping only happens for the normal, stashed-token path). A
      // custom `ready` callback that wants this fallback to classify
      // correctly must inject the bare token, not a formatted header.
      final matching =
          RequestOptions(path: tkData2, headers: {tkAuthorization: tkT0});
      expect(
        defaultAuthFailure(
            tm,
            Response<dynamic>(requestOptions: matching, statusCode: 401),
            tkAuthorization),
        DiomanAuthFailureAction.refresh,
        reason: 'header carries the SAME token the store currently has',
      );

      final stale = RequestOptions(
          path: tkData2, headers: {tkAuthorization: tkBearerOld});
      expect(
        defaultAuthFailure(
            tm,
            Response<dynamic>(requestOptions: stale, statusCode: 401),
            tkAuthorization),
        DiomanAuthFailureAction.replay,
        reason: 'header carries a DIFFERENT (stale) token — someone else '
            'already refreshed',
      );
    });
  });

  group('DiomanAuth: additional realistic branches', () {
    test(
        '[DiomanAuth.new(onAccessExpired)][DiomanAuth.new(onRefresh)] a network-level error with no HTTP response at all is cleared '
        'and passed through, not misclassified', () async {
      final tm = TestTokens(tkT0);
      // A real TestServer, immediately closed — genuinely unreachable
      // (connection refused) rather than a hand-picked dead address.
      final deadServer =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      final deadBaseUrl = deadServer.baseUrl;
      await deadServer.close();
      final dio = Dio(BaseOptions(
        baseUrl: deadBaseUrl,
        connectTimeout: const Duration(milliseconds: 500),
      ));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
      ));

      await expectLater(dio.get<void>(tkData2), throwsA(isA<DioException>()));
    });
    test(
        '[DiomanAuthFailureAction.refresh][DiomanAuthFailureAction.replay] re-dispatching the SAME RequestOptions after a SUCCESSFUL '
        'refresh+replay, if it fails again, hits the "already replayed '
        'once" guard and gives up immediately rather than refreshing again',
        () async {
      // _kRefreshed (and the rest of the auth flags) is only cleared on a
      // FAILURE path (see _clearFlags call sites) — a successful refresh+
      // replay leaves it set. So the guard is only observable by re-using
      // the SAME RequestOptions after a cycle that actually SUCCEEDED.
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts <= 2) {
          return respondJson(req, {tkE: 1}, attempts == 1 ? 401 : 200);
        }
        return respondJson(req, {tkE: 1}, 401); // third dispatch fails again
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      var expiredCalls = 0;
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => tm.set(tkT1),
        onAccessExpired: (_, __) async => expiredCalls++,
      ));

      final options =
          RequestOptions(path: tkData2, baseUrl: dio.options.baseUrl);
      await dio.fetch<void>(options); // 401 then a successful replay
      expect(attempts, 2);

      await expectLater(dio.fetch<void>(options), throwsA(isA<DioException>()));
      expect(attempts, 3,
          reason: 'only ONE more attempt — the already-replayed guard '
              'skips trying to refresh again');
      expect(expiredCalls, 1);
    });
  });

  test(
      '[DiomanAuth.new(buildHeader)][DiomanAuth.new(onAccessExpired)] auth 重放注入回调抛异常时释放认领且保留原因',
      () async {
    final server =
        await TestServer.start((request) => respondJson(request, {}, 401));
    final tokens = Tokens()..replace(replayField, replayFailure);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    var headers = 0;
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
          tokenManager: tokens,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
          buildHeader: (token) {
            if (++headers > 1) throw StateError(replayFailure);
            return token;
          },
          onFailure: (_, __) => DiomanAuthFailureAction.replay,
        ));
    try {
      await expectLater(
          dio.get<dynamic>(replayPath),
          throwsA(isA<DioException>().having(
              (error) => error.error, replayFailure, isA<StateError>())));
    } finally {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    }
  });
}
