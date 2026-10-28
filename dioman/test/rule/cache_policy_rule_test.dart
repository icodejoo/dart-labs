// ignore_for_file: avoid_relative_lib_imports
// 规则层：cache / policy
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group('DiomanCache cachePolicy', () {
    test(
        '[DiomanCachePolicy.none][DiomanClonePolicy.none] none (default): never caches at all, neither layer touched',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(persist: persist));

      await dio.get<void>(tkData2);
      await dio.get<void>(tkData2);
      expect(calls, 2, reason: 'cachePolicy.none never caches at all');
      expect(persist.store, isEmpty);
    });
    test(
        '[DiomanCache.persist][DiomanCachePolicy.memo] memo: memory-only, persist untouched',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.memo),
      );

      await dio.get<void>(tkData2);
      await dio.get<void>(tkData2);
      expect(calls, 1, reason: 'second call still hits the memory store');
      expect(persist.store, isEmpty,
          reason: 'cachePolicy.memo never touches persist');
    });
    test(
        '[DiomanCache.persist][DiomanCachePolicy.persist] persist: the in-memory store is never read or written — every '
        'hit/miss goes straight through persist', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      final cache = DiomanCache(
        persist: persist,
        cachePolicy: DiomanCachePolicy.persist,
      );
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(cache);

      await dio.get<void>(tkData2);
      expect(persist.store, isNotEmpty, reason: 'write went to persist');

      await dio.get<void>(tkData2);
      expect(calls, 1, reason: 'second call is served from persist directly');

      // Prove memory was never populated: wiping persist alone (nothing left
      // in memory to fall back on) must cause a real miss.
      persist.store.clear();
      await dio.get<void>(tkData2);
      expect(calls, 2,
          reason: 'with persist wiped and memory never in play, this is a '
              'real network miss');
    });
    test(
        '[DiomanCache.persist][DiomanCachePolicy.both] both: a write syncs to memory AND persist; a fresh DiomanCache '
        'instance (simulating a restart) still hits because it rehydrates '
        'from persist and backfills its own memory store', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      final cache1 =
          DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(cache1);

      await dio.get<void>(tkData2);
      expect(persist.store, isNotEmpty);

      await dio.get<void>(tkData2); // still cache1 — a memory hit
      expect(calls, 1, reason: 'cache1 serves this from its own memory');

      // Simulate a process restart: swap in a brand new DiomanCache (empty
      // `_store`) backed by the SAME persist instance.
      dio.interceptors.removeLast();
      final cache2 =
          DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
      dio.interceptors.add(cache2);

      await dio.get<void>(tkData2);
      expect(calls, 1,
          reason: 'served from persist, never reaching the network — cache2 '
              'had no memory of its own yet');

      // Prove the persist hit backfilled cache2's own memory: wipe persist
      // and confirm cache2 STILL serves a hit, purely from its now-backfilled
      // memory store.
      persist.store.clear();
      await dio.get<void>(tkData2);
      expect(calls, 1,
          reason: 'still a hit with persist wiped — the earlier persist read '
              "backfilled cache2's memory store");
    });
    test(
        '[DiomanCache.cachePolicy][DiomanCacheOptions.cachePolicy] cachePolicy is overridable per request via DiomanCacheOptions',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      final cache =
          DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.memo);
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(cache);

      await dio.get<void>(tkData2,
          options: Options(extra: {
            tkDiomanCache2: const DiomanCacheOptions(
                cachePolicy: DiomanCachePolicy.persist),
          }));
      expect(persist.store, isNotEmpty,
          reason: 'per-request override routed this write to persist');

      // Prove memory was bypassed: a follow-up call using the plugin's
      // DEFAULT policy (memo) never sees the persist-only entry.
      await dio.get<void>(tkData2);
      expect(calls, 2,
          reason: 'default-policy call misses — memory was never populated '
              'by the persist-only override');
    });
    test(
        '[DiomanCachePersist.read][DiomanCache.cachePolicy] DiomanCachePersist.read may be async (a real Future, not just a '
        'sync value) — DiomanCache awaits it before deciding hit/miss',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = AsyncOnlyCachePersist();
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist),
      );

      await dio.get<void>(tkData2);
      await dio.get<void>(tkData2);
      expect(calls, 1,
          reason: 'second call is a hit even though read() only resolves '
              'after a real async gap');
    });
  });

  test(
      '[DiomanCachePolicy.none][DiomanClonePolicy.none] none cache skips decisions and bookkeeping',
      () async {
    final cache = DiomanCache(
        persist: ControlledPersist(),
        shouldCache: (_) => throw StateError('must not run'));
    final options = cacheOptions();
    final handler = RecordingRequestHandler();
    cache.onRequest(options, handler);
    await pumpEvents();
    expect(handler.calls, 1);
    expect(handler.error, isNull);
    expect(options.extra, {kKey: cacheKey});
  });
}
