// ignore_for_file: avoid_relative_lib_imports
// 组合层：cache_retry
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('pairwise: cache + retry', () {
// DiomanRetry's re-issue goes through a throwaway, interceptor-less Dio
// (see retry_plugin.dart) — it never re-enters DiomanCache at all, in
// either direction. Two consequences, both by design:
    test(
        "[DiomanCache.onResponse × DiomanRetry.onResponse] a retried response is NOT cached — the retry re-issue never "
        "reaches DiomanCache.onResponse", () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkFail: true}, 500);
        return respondJson(req, {tkV: tkRetried}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio,
          cache: DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
          ));
      dio.interceptors
          .add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final r1 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r1.data, {tkV: tkRetried});
      expect(attempts, 2);

      final r2 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r2.data, {tkV: tkRetried});
      expect(attempts, 3,
          reason: 'NOT a cache hit — the retried response was never '
              'written to the cache, so this second call goes to the '
              'network again. A real trade-off (see retry_plugin.dart\'s '
              'class doc): it also means the business-level cache-poisoning '
              'bug this used to have (a failed 200 getting cached, then '
              "read straight back by the retry itself) can't happen "
              'anymore — there is no `cache:` param on DiomanRetry at all, '
              'because there is nothing for it to coordinate with.');
    });
// The ORIGINAL attempt (unlike the retry re-issue) is still a normal
// pass through the full chain — DiomanCache still writes its 200
// response, business failure or not, exactly as before.
//
// A LATER caller hitting that entry gets it back as-is: the cache hit
// short-circuits before DiomanRetry.onRequest, so retry never admitted the
// request and does not recover or rewrite it (it only recovers requests its
// own onRequest let through). The stale failure is therefore the cache
// layer's responsibility (e.g. `shouldStore`, or DiomanNormalize wired by
// Dioman.install, which keeps business failures out of the cache).
    test(
        "[DiomanCache.cachePolicy × DiomanRetry.delay] a cache hit is NOT rewritten by DiomanRetry — a later caller "
        "hitting the entry the ORIGINAL failed attempt poisoned gets it back as-is "
        '(retry only recovers requests its own onRequest admitted)', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          return respondJson(
              req, {tkCode: 1, tkData: null, tkMessage: tkFail}, 200);
        }
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
      final cache = DiomanCache(
        persist: FakeCachePersist(),
        cachePolicy: DiomanCachePolicy.memo,
      );
      installStateful(dio, cache: cache);
      var retries = 0;
      dio.interceptors.add(DiomanRetry(
        max: 1,
        delay: (_, __, ___, ____) => Duration.zero,
        shouldRetry: (err, response) => (response?.data as Map)[tkCode] != 0,
        onRetry: (_) => retries++,
      ));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data![tkCode], 0,
          reason: 'the caller for THIS request still correctly gets the '
              "retried, successful result — the retry's own re-issue "
              'reached the network directly, never consulting the cache');
      expect(attempts, 2);
      expect(retries, 1);

      final later = await dio.get<Map<String, dynamic>>(tkData2);
      expect(later.data![tkCode], 1,
          reason: 'the cache hit short-circuits before DiomanRetry.onRequest, '
              'so retry never admitted it: the poisoned failure comes back '
              'as-is instead of being recovered');
      expect(attempts, 2,
          reason: 'no network call at all — neither the cache hit nor a '
              'retry re-issue');
      expect(retries, 1, reason: 'onRetry is not called for a cache hit');
    });
  });
}
