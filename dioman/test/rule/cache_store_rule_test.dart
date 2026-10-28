// ignore_for_file: avoid_relative_lib_imports
// 规则层：cache / store
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group('DiomanCache management API', () {
    test(
        '[DiomanCache.clear][DiomanCache.remove] remove()/clear() operate on the live store',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cache = DiomanCache(
          persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo);
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(cache);

      final first = await dio.get<void>(tkA3);
      await dio.get<void>(tkB);
      expect(calls, 2);

      await cache.remove(first.requestOptions.extra[kKey] as String);
      await dio.get<void>(tkA3);
      expect(calls, 3, reason: 'remove() evicted /a → real network hit');
      await dio.get<void>(tkB);
      expect(calls, 3, reason: '/b is untouched, still a cache hit');

      await cache.clear();
      await dio.get<void>(tkA3);
      await dio.get<void>(tkB);
      expect(calls, 5, reason: 'clear() wiped everything');
    });
    test(
        '[DiomanCache.cachePolicy][DiomanCache.expires] an expired entry is evicted on the next request for that key, '
        'not served stale', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      var now = DateTime(2024, 1, 1);
      dio.interceptors.add(DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
          expires: 1000,
          now: () => now));

      final r1 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r1.data![tkV], 1);

      now = now.add(const Duration(seconds: 2)); // past the 1000ms TTL
      final r2 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r2.data![tkV], 2, reason: 'expired entry evicted, real refetch');
      expect(calls, 2);
    });
  });

  group(tkDiomanCache, () {
    test(
        '[DiomanCache.maxEntries][DiomanCacheOptions.maxEntries] maxEntries bounds the store via LRU eviction instead of growing '
        'without limit', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkPath: req.uri.path}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cache = DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
          maxEntries: 2);
      dio.interceptors.addAll([const DiomanKey(), cache]);

      await dio.get<void>(tkA3);
      await dio.get<void>(tkB);
      await dio.get<void>(tkC2); // evicts '/a' (least recently written)

      await dio.get<void>(tkA3); // must miss cache → real network hit again
      expect(calls, 4);

      await dio.get<void>(tkC2); // still cached → no new network hit
      expect(calls, 4);
    });
  });

  group('DiomanCache LRU', () {
    test(
        '[DiomanCachePersist.write][DiomanCache.cachePolicy] a cache HIT promotes the entry to most-recently-used, so eviction '
        'drops the genuinely least-recently-USED key (not merely oldest write)',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'p': req.uri.path}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
            maxEntries: 2)
      ]);

      await dio.get<void>(tkA3); // store: [a]
      await dio.get<void>(tkB); // store: [a, b]
      await dio.get<void>(tkA3); // HIT → promote a → store: [b, a]
      await dio.get<void>(tkC2); // write c, evict LRU = b → store: [a, c]
      expect(calls, 3, reason: 'the /a re-read was a cache hit');

      await dio.get<void>(tkA3); // still cached → no network
      expect(calls, 3,
          reason: '/a survived eviction because the hit promoted it');

      await dio.get<void>(tkB); // evicted → network
      expect(calls, 4,
          reason: '/b was the least-recently-used and must have been evicted');
    });
  });

  group(tkPerRequestOptionsOverrides, () {
    test(
        '[DiomanCache.enabled][DiomanCacheOptions.enabled] DiomanCacheOptions(enabled: false) skips caching for that request',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'n': calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
        )
      ]);

      await dio.get<void>(tkX);
      await dio.get<void>(
        tkX,
        options: Options(
            extra: {tkDiomanCache2: const DiomanCacheOptions(enabled: false)}),
      );

      expect(calls, 2, reason: 'the second call must bypass the cache hit');
    });
  });

  group(tkConstructorLevelEnabledFlag, () {
    test(
        '[DiomanCache.cachePolicy][DiomanCache.enabled] DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, enabled: false) never caches, even across identical '
        'requests', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
            enabled: false)
      ]);

      await dio.get<void>(tkX);
      await dio.get<void>(tkX);

      expect(calls, 2, reason: 'a disabled cache must never serve a hit');
    });
  });

  group(tkEnabledInheritsFromTheConstructorWhenNotOverridden, () {
    test(
        '[DiomanCache.enabled][DiomanCache.expires] a per-request DiomanCacheOptions that only sets expires does NOT '
        "re-enable a plugin constructed with enabled: false", () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
            enabled: false)
      ]);

      await dio.get<void>(tkX,
          options: Options(
              extra: {tkDiomanCache2: const DiomanCacheOptions(expires: 999)}));
      await dio.get<void>(tkX,
          options: Options(
              extra: {tkDiomanCache2: const DiomanCacheOptions(expires: 999)}));

      expect(calls, 2,
          reason: 'a per-request override that only sets expires must not '
              "silently re-enable a cache constructed with enabled: false");
    });
  });

  group(tkNewlyWiredOptionsFieldsFullConstructorOptionsParity, () {
    test(
        '[DiomanCache.new(shouldCache)][DiomanCacheOptions.shouldCache] DiomanCacheOptions.shouldCache overrides the plugin default '
        'caching decision for a single call (allows POST to be cached)',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
        )
      ]); // default: GET-only

      final alwaysCache = Options(
        extra: {tkDiomanCache2: DiomanCacheOptions(shouldCache: (o) => true)},
      );
      await dio.post<void>(tkX, options: alwaysCache);
      await dio.post<void>(tkX, options: alwaysCache);

      expect(calls, 1,
          reason: 'per-request shouldCache must allow a POST to be cached, '
              'even though the plugin default is GET-only');
    });
  });
}
