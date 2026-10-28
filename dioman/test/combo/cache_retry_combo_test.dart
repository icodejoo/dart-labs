// ignore_for_file: avoid_relative_lib_imports
// 组合层：cache_retry
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
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
// FIXED (cache_plugin.dart): a cache hit's resolve now passes
// callFollowingResponseInterceptor: true, so it still runs onResponse of
// everything installed after cache — including DiomanRetry. That means
// a DIFFERENT, later caller who hits the poisoned entry no longer just
// gets the stale failure back silently: DiomanRetry's own onResponse
// (if the caller configured shouldRetry, as here) sees it, judges
// it a business failure, and retries it via its own bare-Dio re-issue —
// same recovery a live request would get. The poisoned entry itself is
// still never evicted/overwritten (retry's re-issue doesn't write back
// to cache, same as the original attempt's own retry above), so every
// future caller repeats this recovery dance rather than getting a fast
// cache hit — but every caller now ends up with the CORRECT data instead
// of the stale failure.
    test(
        "[DiomanCache.cachePolicy × DiomanRetry.delay] FIXED: a cache hit landing on the entry the ORIGINAL failed attempt "
        "poisoned still gets a chance to recover via DiomanRetry — a "
        'DIFFERENT, later caller for the same key ends up with the correct '
        'data, not the stale failure', () async {
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
      dio.interceptors.add(DiomanRetry(
        max: 1,
        delay: (_, __, ___, ____) => Duration.zero,
        shouldRetry: (err, response) => (response?.data as Map)[tkCode] != 0,
      ));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data![tkCode], 0,
          reason: 'the caller for THIS request still correctly gets the '
              "retried, successful result — the retry's own re-issue "
              'reached the network directly, never consulting the cache');
      expect(attempts, 2);

      final later = await dio.get<Map<String, dynamic>>(tkData2);
      expect(later.data![tkCode], 0,
          reason: 'FIXED: the cache hit ran onResponse of DiomanRetry too, '
              "which caught the poisoned entry's business failure and "
              "recovered it via its own re-issue — this caller gets the "
              'correct data instead of the stale failure');
      expect(attempts, 3,
          reason: 'the cache hit itself made no network call, but '
              "DiomanRetry's recovery re-issue for it did — one more real "
              'attempt than before');
    });
  });
}
