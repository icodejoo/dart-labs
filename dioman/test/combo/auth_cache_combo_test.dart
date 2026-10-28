// ignore_for_file: avoid_relative_lib_imports
// 组合层：auth_cache
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/client.dart';
import '../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  test(
      '[DiomanAuth.new(buildHeader) × DiomanCache.cachePolicy] auth 恢复成功的原始信封写回上游缓存',
      () async {
    var hits = 0;
    final server = await TestServer.start((r) async {
      hits++;
      final ok = r.headers.value(tkAuthorization2) == tkBearerFresh;
      await respondJson(
          r,
          {
            tkCode: ok ? 0 : 401,
            tkData: {tkValue: 7}
          },
          ok ? 200 : 401);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final tm = Tokens()..replace(tkOld, tkRefresh);
    final handle = Dioman.install(dio,
        key: const DiomanKey(),
        cache: DiomanCache(
            persist: MemoryPersist(), cachePolicy: DiomanCachePolicy.memo),
        auth: DiomanAuth(
            tokenManager: tm,
            buildHeader: (t) => 'Bearer $t',
            onRefresh: (_, __) async {
              tm.replace(tkFresh2, tkRefresh);
            },
            onAccessExpired: (_, __) async {}),
        normalize: const DiomanNormalize());
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    expect((await dio.get<dynamic>(tkPrivate)).data, {tkValue: 7});
    expect((await dio.get<dynamic>(tkPrivate)).data, {tkValue: 7});
    expect(hits, 2);
  });

  group('pairwise: cache + auth', () {
    test(
        '[DiomanAuth.new(onAccessExpired) × DiomanCache.cachePolicy] a cache hit bypasses DiomanAuth entirely — a protected endpoint '
        "cached response is served even after the caller's token is "
        'cleared', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final tm = TestTokens(tkT0);
      installStateful(
        dio,
        cache: DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
        ),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
      );

      await dio.get<void>(tkData2); // real, authenticated, cached
      tm.clear(); // token now gone
      final r =
          await dio.get<Map<String, dynamic>>(tkData2); // still a cache hit
      expect(r.data, {tkV: 1},
          reason: 'cache sits before auth in the canonical chain, so a hit '
              "never reaches auth's protection check — same limitation as "
              'cache+loading/cache+cancel above, documented behavior of a '
              'response cache, not a bug');
    });
  });
}
