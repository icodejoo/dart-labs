// ignore_for_file: avoid_relative_lib_imports
// 组合层：auth_retry
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/client.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  test(
      '[DiomanAuth.new(onAccessExpired) × DiomanRetry.delay] 重试遇到 401 交回原 auth 刷新，恢复数据只归一化一次',
      () async {
    var hits = 0;
    var refreshes = 0;
    final server = await TestServer.start((r) async {
      hits++;
      final status = hits == 1
          ? 500
          : r.headers.value(tkAuthorization2) == tkBearerFresh
              ? 200
              : 401;
      await respondJson(
          r,
          {
            tkCode: status == 200 ? 0 : status,
            tkData: {tkValue: 7}
          },
          status);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final tm = Tokens()..replace(tkOld, tkRefresh);
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async {
              refreshes++;
              tm.replace(tkFresh2, tkRefresh);
            },
            onAccessExpired: (_, __) async {}),
        retry: DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero),
        normalize: const DiomanNormalize());
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    expect((await dio.get<dynamic>(tkPrivate)).data, {tkValue: 7});
    expect(hits, 3);
    expect(refreshes, 1);
  });

  group('3-way: share + retry + auth', () {
// Unlike the old same-dio design, DiomanAuth does NOT get a chance to
// re-inject/refresh the token on DiomanRetry's re-issue (bare dio, no
// interceptors) — the re-issue just carries whatever header the
// ORIGINAL attempt already had. That's fine for what DiomanRetry is
// actually for (network-level failures, business-level failures) —
// neither implies the token specifically went bad; if it truly expired
// mid-flight, that's DiomanAuth's own reactive 401 handling to catch on
// a LATER request, not something the retry needs to solve.
    test(
        '[DiomanAuthFailureAction.refresh × DiomanRetry.delay] the retry re-issue carries the SAME auth header the original '
        "attempt had — auth's own token refresh never gets a chance to run "
        'again for it, but the combo still works correctly end to end',
        () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final headersSeen = <String?>[];
      final server = await TestServer.start((req) async {
        attempts++;
        headersSeen.add(req.headers.value(tkAuthorization2));
        if (attempts == 1) return respondJson(req, {tkFail: true}, 500);
        return respondJson(req, {tkV: tkOk}, 200);
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
      dio.interceptors
          .add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data![tkV], tkOk);
      expect(attempts, 2);
      expect(headersSeen, [tkBearerT0, tkBearerT0],
          reason: "both attempts carry the SAME header — auth's onRequest "
              "never ran again for the retry's re-issue to refresh it, "
              'even though `tm` would have handed out a different token');
    });
  });

  test(
      '[DiomanAuth.new(onAccessExpired) × DiomanRetry.delay] retry 的 auth 桥接回调抛非 Dio 异常时保留原因并完成请求',
      () async {
    var hits = 0;
    final server = await TestServer.start(
        (request) => respondJson(request, {}, ++hits == 1 ? 500 : 401));
    final tokens = Tokens()..replace(replayField, replayFailure);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
            tokenManager: tokens,
            onRefresh: (_, __) async {},
            onAccessExpired: (_, __) async {},
            onFailure: (_, response) {
              if (response.statusCode == 401) {
                throw const FormatException(replayFailure);
              }
              return DiomanAuthFailureAction.others;
            }),
        retry: DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));
    try {
      await expectLater(
          dio.get<dynamic>(replayPath),
          throwsA(isA<DioException>().having(
              (error) => error.error, replayFailure, isA<FormatException>())));
      expect(hits, 2);
    } finally {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    }
  });
}
