// ignore_for_file: avoid_relative_lib_imports
// 组合层：full_stack
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('full stateful stack (all 6): cache+share+cancel+loading+auth+retry',
      () {
// Deliberately uses a NETWORK-level (500) failure, not a business-level
// one — the "pairwise: cache + retry" business-level test above covers
// that combo's (narrower, now) remaining caveat. A network-level
// failure never reaches cache.onResponse at all (it's routed through
// onError, not onResponse), so there's nothing to poison here either
// way.
    test(
        '[Dioman.install] a network-level failure (500) still retries and eventually '
        'succeeds through the entire stack — cleanly, since DiomanRetry\'s '
        'bare-dio re-issue never touches cache/share/cancel/loading/auth/log '
        'along the way', () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkFail: true}, 500);
        return respondJson(
            req,
            {
              tkCode: 0,
              tkData: {tkV: tkOk},
              tkMessage: tkEmpty
            },
            200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(
        dio,
        cache: DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
        ),
        share: DiomanShare(policy: DiomanSharePolicy.start),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: states.add),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set(tkT1),
          onAccessExpired: (_, __) async {},
        ),
        retry: DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero),
      );

      final r = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 3));
      expect(r.data![tkCode], 0);
      expect(attempts, 2);
      expect(cancelAll(dio), 0, reason: 'nothing left in flight');
      expect(states, [true, false],
          reason: 'a single steady 0→1→0 edge — the bare-dio re-issue never '
              'touches DiomanLoading, so there\'s no flicker mid-retry, even '
              'with the rest of the stack installed');

      // A later, independent call is NOT a cache hit — the retried
      // response never reached DiomanCache.onResponse (bare-dio re-issue),
      // and the original 500 never reached it either (errors route through
      // onError, not onResponse). This is a real, deliberate trade-off —
      // see retry_plugin.dart's class doc.
      final r2 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r2.data![tkCode], 0);
      expect(attempts, 3, reason: 'a fresh network hit, not a cache hit');
    });
  });

  group('full 13-plugin stack via Dioman.install', () {
    test(
        '[Dioman.install] a plain successful request round-trips through all 13 plugins '
        'without crashing, and DiomanNormalize correctly unwraps the '
        'envelope', () async {
      final server = await TestServer.start((req) => respondJson(
          req,
          {
            tkCode: 0,
            tkData: {tkV: tkOk},
            tkMessage: tkEmpty
          },
          200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final tm = TestTokens(tkT0);
      final states = <bool>[];
      final logs = <String>[];

      final handle = Dioman.install(
        dio,
        envs: DiomanEnvs([]),
        repath: DiomanRepath(),
        filter: const DiomanFilter(),
        key: const DiomanKey(),
        normalize: const DiomanNormalize(),
        cache: DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
        ),
        share: DiomanShare(policy: DiomanSharePolicy.start),
        mock: DiomanMock(enabled: false),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: states.add),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
        retry: DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero),
        log: DiomanLog(writer: (m, {error}) => logs.add(m)),
      );

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data, {tkV: tkOk}, reason: 'normalize unwrapped the envelope');
      expect(states, [true, false]);
      expect(logs, isNotEmpty, reason: 'log plugin observed the round trip');

      handle.dispose();
      expect(dio.interceptors.whereType<DiomanPlugin>(), isEmpty,
          reason: 'every dioman plugin was ejected; dio\'s own built-in '
              'interceptors (e.g. ImplyContentTypeInterceptor) are '
              'untouched, as they should be');
    });
  });
}
