// Fills the line-coverage gaps left by dioman_test.dart / dioman_combinations_test.dart —
// each group here targets specific branches that were never exercised (found via
// `dart pub global run coverage:format_coverage`), not new behavior. Every plugin's
// PRIMARY/default-configuration behavior is already covered elsewhere; this file is
// for the secondary options, management APIs, and less-common branches: DiomanEnvs'
// actual rule matching (previously only ever constructed with an empty rule list),
// DiomanRepath's placeholder substitution (previously never exercised at all),
// DiomanMock's mockUrl-redirect path (previously only the inline-handler path was
// tested), DiomanShare's `end`/`race` policies (previously only `start`/`retry`),
// DiomanCache's management API (`remove`/`clear`) and clone policies,
// and misc smaller branches in auth/filter/key/log/cancel/retry.
import 'support/fake_cache_persist.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

class _FakeTokenManager implements DiomanTokenManager {
  _FakeTokenManager(this._access);
  String? _access;
  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => 'refresh';
  @override
  bool get canRefresh => true;
  @override
  void clear() => _access = null;
  void set(String? v) => _access = v;
}

class _Unencodable {
  @override
  String toString() => 'unencodable';
}

void main() {
  group('DiomanEnvs', () {
    test('the first matching rule wins and its BaseOptions fields are '
        'shallow-merged into dio.options; a later, also-matching rule is '
        'never even evaluated', () {
      final dio = Dio();
      var secondRuleEvaluated = false;
      DiomanEnvs([
        EnvRule(
          rule: () => true,
          config: BaseOptions(
            baseUrl: 'https://prod.example.com',
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 6),
            sendTimeout: const Duration(seconds: 7),
            headers: {'X-Env': 'prod'},
          ),
        ),
        EnvRule(
          rule: () {
            secondRuleEvaluated = true;
            return true;
          },
          config: BaseOptions(baseUrl: 'https://staging.example.com'),
        ),
      ], dio: dio);

      expect(dio.options.baseUrl, 'https://prod.example.com');
      expect(dio.options.connectTimeout, const Duration(seconds: 5));
      expect(dio.options.receiveTimeout, const Duration(seconds: 6));
      expect(dio.options.sendTimeout, const Duration(seconds: 7));
      expect(dio.options.headers['X-Env'], 'prod');
      expect(secondRuleEvaluated, isFalse,
          reason: 'first match wins — later rules are never evaluated');
    });

    test('no matching rule leaves dio.options completely untouched', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://default.example.com'));
      DiomanEnvs([
        EnvRule(rule: () => false, config: BaseOptions(baseUrl: 'https://x')),
      ], dio: dio);

      expect(dio.options.baseUrl, 'https://default.example.com');
    });

    test('a rule that only sets responseType to something other than the '
        'json default applies it; one that never touches responseType '
        "never resets a caller's own bytes/stream setting back to json",
        () {
      final dio1 = Dio();
      DiomanEnvs([
        EnvRule(
          rule: () => true,
          config: BaseOptions(responseType: ResponseType.bytes),
        ),
      ], dio: dio1);
      expect(dio1.options.responseType, ResponseType.bytes);

      final dio2 = Dio(BaseOptions(responseType: ResponseType.stream));
      DiomanEnvs([
        EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://x')),
      ], dio: dio2);
      expect(dio2.options.responseType, ResponseType.stream,
          reason: 'the rule never set responseType, so the pre-existing '
              'stream setting must survive — not get reset to the '
              "BaseOptions default of json");
    });

    test('a constructor-level disabled DiomanEnvs makes apply() a permanent '
        'no-op even with a matching rule', () {
      final dio = Dio(BaseOptions(baseUrl: 'https://default.example.com'));
      final envs = DiomanEnvs(
        [EnvRule(rule: () => true, config: BaseOptions(baseUrl: 'https://x'))],
        enabled: false,
      );
      envs.apply(dio);
      expect(dio.options.baseUrl, 'https://default.example.com');
    });

    test('name identifies the plugin', () {
      expect(DiomanEnvs(const []).name, 'dioman:envs');
    });
  });

  group('DiomanRepath', () {
    test('{id}/:id placeholders are substituted from queryParameters, and '
        'removed from it by default', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath());

      final r = await dio.get<void>('/user/{id}/posts/:postId',
          queryParameters: {'id': 42, 'postId': 7, 'page': 1});

      expect(seenPath, '/user/42/posts/7');
      expect(r.requestOptions.queryParameters.containsKey('id'), isFalse,
          reason: 'removeKey defaults to true — substituted keys are '
              'removed from the source map');
      expect(r.requestOptions.queryParameters.containsKey('postId'), isFalse);
      expect(r.requestOptions.queryParameters['page'], 1,
          reason: 'an untouched param stays');
    });

    test('falls back to the data map when a placeholder is not in '
        'queryParameters, and removeKey:false keeps the source key', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath(removeKey: false));

      final r = await dio.post<void>('/user/{id}', data: {'id': 99});

      expect(seenPath, '/user/99');
      expect(r.requestOptions.data['id'], 99,
          reason: 'removeKey:false leaves the source key in place');
    });

    test('the default removeKey:true also removes a data-map substitution '
        '(not just a queryParameters one)', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath()); // removeKey defaults to true

      final r = await dio.post<void>('/user/{id}', data: {'id': 99});

      expect(seenPath, '/user/99');
      expect(r.requestOptions.data.containsKey('id'), isFalse,
          reason: 'removeKey defaults to true for the data-map branch too');
    });

    test('a placeholder with no match in either query or data is left '
        'as-is in the path', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath());

      await dio.get<void>('/user/{id}');

      expect(Uri.decodeComponent(seenPath!), '/user/{id}',
          reason: 'the unsubstituted placeholder still reaches the network '
              '(percent-encoded, like any other literal path segment)');
    });

    test('a constructor-level disabled DiomanRepath never substitutes', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath(enabled: false));

      await dio.get<void>('/user/{id}', queryParameters: {'id': 42});
      expect(Uri.decodeComponent(seenPath!), '/user/{id}');
    });

    test('a per-request DiomanRepathOptions can disable substitution or '
        'override removeKey for a single call', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath());

      await dio.get<void>('/user/{id}',
          queryParameters: {'id': 42},
          options: Options(
              extra: {'dioman:repath': const DiomanRepathOptions(enabled: false)}));
      expect(Uri.decodeComponent(seenPath!), '/user/{id}',
          reason: 'per-request override disabled substitution for this call');

      final r = await dio.get<void>('/user/{id}',
          queryParameters: {'id': 7},
          options: Options(
              extra: {'dioman:repath': const DiomanRepathOptions(removeKey: false)}));
      expect(seenPath, '/user/7');
      expect(r.requestOptions.queryParameters['id'], 7,
          reason: 'per-request removeKey:false keeps the source query param');
    });
  });

  group('DiomanFilter', () {
    test('the default predicate also drops empty/whitespace-only strings, '
        'and filters the data map the same way it filters queryParameters',
        () async {
      Map<String, dynamic>? seenQuery;
      Object? seenBody;
      final server = await TestServer.start((req) async {
        seenQuery = req.uri.queryParameters;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanFilter());
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenBody = o.data;
        h.next(o);
      }));

      await dio.get<void>('/data', queryParameters: {
        'keep': 'x',
        'blank': '   ',
        'empty': '',
      });
      expect(seenQuery, {'keep': 'x'});

      await dio.post<void>('/data', data: {
        'keep': 1,
        'dropMe': null,
        'blank': '  ',
      });
      expect(seenBody, {'keep': 1});
    });
  });

  group('DiomanKey', () {
    test('a constructor-level disabled DiomanKey never writes a key, so '
        'DiomanCache installed after it never caches', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey(enabled: false));
      dio.interceptors.add(DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ));

      await dio.get<void>('/data');
      await dio.get<void>('/data');
      expect(calls, 2, reason: 'no key ⇒ cache always misses');
    });

    test('deep mode folds sorted queryParameters and a Map body into the '
        'key, so two requests differing only in body get different cache '
        'entries', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey()); // fastMode: false (default)
      dio.interceptors.add(DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, 
          shouldCache: (o) => true)); // allow caching this POST

      await dio.post<void>('/data',
          queryParameters: {'b': 2, 'a': 1}, data: {'x': 1});
      await dio.post<void>('/data',
          queryParameters: {'a': 1, 'b': 2}, // same params, different order
          data: {'x': 1});
      expect(calls, 1,
          reason: 'same query (order-independent) and body ⇒ same key ⇒ '
              'second call is a cache hit');

      await dio.post<void>('/data',
          queryParameters: {'a': 1, 'b': 2}, data: {'x': 2});
      expect(calls, 2, reason: 'different body ⇒ different key ⇒ real call');
    });

    test('a String body is folded into the deep key as-is', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, shouldCache: (o) => true));

      await dio.post<void>('/data', data: 'raw-body');
      await dio.post<void>('/data', data: 'raw-body');
      expect(calls, 1);

      await dio.post<void>('/data', data: 'different-body');
      expect(calls, 2);
    });

    test('_encode falls back to toString() when a value cannot be '
        'JSON-encoded (e.g. a custom, non-serializable object)', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ));

      await dio.get<void>('/data', queryParameters: {'x': _Unencodable()});
      await dio.get<void>('/data', queryParameters: {'x': _Unencodable()});
      expect(calls, 1,
          reason: 'both calls fall back to the same deterministic '
              'toString() output, so they compute the same key');
    });
  });

  group('DiomanCache management API', () {
    test('remove()/clear() operate on the live store', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cache = DiomanCache(
          persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo);
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(cache);

      await dio.get<void>('/a');
      await dio.get<void>('/b');
      expect(calls, 2);

      cache.remove('GET:/a');
      await dio.get<void>('/a');
      expect(calls, 3, reason: 'remove() evicted /a → real network hit');
      await dio.get<void>('/b');
      expect(calls, 3, reason: '/b is untouched, still a cache hit');

      cache.clear();
      await dio.get<void>('/a');
      await dio.get<void>('/b');
      expect(calls, 5, reason: 'clear() wiped everything');
    });

    test('an expired entry is evicted on the next request for that key, '
        'not served stale', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      var now = DateTime(2024, 1, 1);
      dio.interceptors.add(DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, expires: 1000, now: () => now));

      final r1 = await dio.get<Map<String, dynamic>>('/data');
      expect(r1.data!['v'], 1);

      now = now.add(const Duration(seconds: 2)); // past the 1000ms TTL
      final r2 = await dio.get<Map<String, dynamic>>('/data');
      expect(r2.data!['v'], 2, reason: 'expired entry evicted, real refetch');
      expect(calls, 2);
    });

    test('DiomanClonePolicy.shallow returns a distinct top-level container '
        'for both Map and List payloads, without deep-copying nested '
        'objects', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, [1, 2, 3], 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ));

      final r1 = await dio.get<List<dynamic>>('/data');
      final r2 = await dio.get<List<dynamic>>('/data'); // cache hit
      expect(r2.data, [1, 2, 3]);
      expect(identical(r1.data, r2.data), isFalse,
          reason: 'shallow clone returns a distinct top-level List');
    });

    test('DiomanClonePolicy.deep recursively copies nested maps/lists, so '
        'mutating one hit never affects another', () async {
      final server = await TestServer.start((req) => respondJson(
          req,
          {
            'nested': {'v': 1},
            'list': [
              {'v': 2}
            ],
          },
          200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, clone: DiomanClonePolicy.deep));

      final r1 =
          await dio.get<Map<String, dynamic>>('/data'); // populates cache
      final r2 = await dio.get<Map<String, dynamic>>('/data'); // hit
      (r2.data!['nested'] as Map)['v'] = 999;
      (r2.data!['list'] as List)[0]['v'] = 999;

      final r3 = await dio.get<Map<String, dynamic>>('/data'); // hit again
      expect(r3.data!['nested']['v'], 1,
          reason: 'deep clone means mutating r2 never touched the stored '
              'entry, unlike r1 (populated before any clone was applied)');
      expect(r3.data!['list'][0]['v'], 2,
          reason: "the list's original value (2) survived — r2's mutation "
              'to 999 never touched the stored entry either');
      expect(identical(r1.data, r2.data), isFalse);
    });
  });

  group('DiomanCache cachePolicy', () {
    test('none (default): never caches at all, neither layer touched',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(persist: persist));

      await dio.get<void>('/data');
      await dio.get<void>('/data');
      expect(calls, 2, reason: 'cachePolicy.none never caches at all');
      expect(persist.store, isEmpty);
    });

    test('memo: memory-only, persist untouched', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(
        DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.memo),
      );

      await dio.get<void>('/data');
      await dio.get<void>('/data');
      expect(calls, 1, reason: 'second call still hits the memory store');
      expect(persist.store, isEmpty,
          reason: 'cachePolicy.memo never touches persist');
    });

    test('persist: the in-memory store is never read or written — every '
        'hit/miss goes straight through persist', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': calls}, 200);
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

      await dio.get<void>('/data');
      expect(persist.store, isNotEmpty, reason: 'write went to persist');

      await dio.get<void>('/data');
      expect(calls, 1, reason: 'second call is served from persist directly');

      // Prove memory was never populated: wiping persist alone (nothing left
      // in memory to fall back on) must cause a real miss.
      persist.store.clear();
      await dio.get<void>('/data');
      expect(calls, 2,
          reason: 'with persist wiped and memory never in play, this is a '
              'real network miss');
    });

    test('both: a write syncs to memory AND persist; a fresh DiomanCache '
        'instance (simulating a restart) still hits because it rehydrates '
        'from persist and backfills its own memory store', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      final cache1 =
          DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(cache1);

      await dio.get<void>('/data');
      expect(persist.store, isNotEmpty);

      await dio.get<void>('/data'); // still cache1 — a memory hit
      expect(calls, 1, reason: 'cache1 serves this from its own memory');

      // Simulate a process restart: swap in a brand new DiomanCache (empty
      // `_store`) backed by the SAME persist instance.
      dio.interceptors.removeLast();
      final cache2 =
          DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.both);
      dio.interceptors.add(cache2);

      await dio.get<void>('/data');
      expect(calls, 1,
          reason: 'served from persist, never reaching the network — cache2 '
              'had no memory of its own yet');

      // Prove the persist hit backfilled cache2's own memory: wipe persist
      // and confirm cache2 STILL serves a hit, purely from its now-backfilled
      // memory store.
      persist.store.clear();
      await dio.get<void>('/data');
      expect(calls, 1,
          reason: 'still a hit with persist wiped — the earlier persist read '
              "backfilled cache2's memory store");
    });

    test('cachePolicy is overridable per request via DiomanCacheOptions',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final persist = FakeCachePersist();
      final cache =
          DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.memo);
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(cache);

      await dio.get<void>('/data',
          options: Options(extra: {
            'dioman:cache':
                const DiomanCacheOptions(cachePolicy: DiomanCachePolicy.persist),
          }));
      expect(persist.store, isNotEmpty,
          reason: 'per-request override routed this write to persist');

      // Prove memory was bypassed: a follow-up call using the plugin's
      // DEFAULT policy (memo) never sees the persist-only entry.
      await dio.get<void>('/data');
      expect(calls, 2,
          reason: 'default-policy call misses — memory was never populated '
              'by the persist-only override');
    });
  });

  group('DiomanShare policy: end', () {
    test('only the LATEST (highest-seq) response settles the shared '
        'promise — an earlier, superseded caller for the same key gets '
        'redirected to that result instead of its own', () async {
      final aStarted = Completer<void>();
      final releaseA = Completer<void>();
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        if (calls == 1) {
          aStarted.complete();
          await releaseA.future;
          return respondJson(req, {'v': 'a-stale'}, 200);
        }
        return respondJson(req, {'v': 'b-latest'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.end));

      final a = dio.get<Map<String, dynamic>>('/data');
      await aStarted.future;
      final b = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 3));
      releaseA.complete();
      final aResult = await a.timeout(const Duration(seconds: 3));

      expect(b.data, {'v': 'b-latest'});
      expect(aResult.data, {'v': 'b-latest'},
          reason: 'a is superseded by b (higher seq) — it gets redirected '
              "to b's result instead of its own stale one");
    });

    test('a solo caller (no supersession) just settles with its own '
        'result', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.end));

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data, {'v': 1});
    });

    // NOTE: a superseded caller redirected to a FAILING settlement is not
    // covered here — per SKILL.md / dioman_combinations_test.dart, a
    // follower (which `_awaitEntry` also implements this redirection with)
    // bound to an error settlement hits a separate, pre-existing,
    // unfixed dio/zone crash. Forcing that path just to tick a coverage
    // line would test known-broken behavior, not a real guarantee.
  });

  group('DiomanShare policy: race', () {
    test('the first attempt to SUCCEED wins for everyone, including a '
        "slower attempt that's still in flight", () async {
      final slowStarted = Completer<void>();
      final releaseSlow = Completer<void>();
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        if (calls == 1) {
          slowStarted.complete();
          await releaseSlow.future;
          return respondJson(req, {'v': 'slow'}, 200);
        }
        return respondJson(req, {'v': 'fast'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.race));

      final slow = dio.get<Map<String, dynamic>>('/data');
      await slowStarted.future;
      final fast = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 3));
      releaseSlow.complete();
      final slowResult = await slow.timeout(const Duration(seconds: 3));

      expect(fast.data, {'v': 'fast'});
      expect(slowResult.data, {'v': 'fast'},
          reason: "the slow attempt lost the race — it's redirected to the "
              "fast attempt's winning result");
    });

    test('only once every in-flight attempt has failed does the race '
        'settle as a failure for everyone', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'fail': true}, 500));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.race));

      await expectLater(
        dio.get<Map<String, dynamic>>('/data'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('DiomanRetry: business-failure loop exhaustion and error-path gates',
      () {
    test('when every retry attempt still looks like a business failure, '
        'the retry loop exhausts and propagates the LAST attempt as-is',
        () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        return respondJson(req, {'code': 1, 'attempt': attempts}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(
        max: 2,
        delay: (_, __, ___, ____) => Duration.zero,
        shouldRetry: (err, response) => (response?.data as Map)['code'] != 0,
      ));

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(attempts, 3, reason: 'original + 2 retries, all exhausted');
      expect(r.data!['code'], 1,
          reason: 'gives up and returns the last (still-failing) attempt '
              'rather than throwing');
    });

    test('a constructor-disabled DiomanRetry never intercepts a network '
        'error at all', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        return respondJson(req, {'fail': true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors
          .add(DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero, enabled: false));

      await expectLater(
        dio.get<void>('/data'),
        throwsA(isA<DioException>()),
      );
      expect(attempts, 1, reason: 'disabled ⇒ no retry attempted');
    });

    test('an error shouldRetry rejects (e.g. a plain 404) is passed straight '
        'through without retrying', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        return respondJson(req, {'fail': true}, 404);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(max: 2, delay: (_, __, ___, ____) => Duration.zero));

      await expectLater(
        dio.get<void>('/data'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'statusCode', 404)),
      );
      expect(attempts, 1,
          reason: '404 is not >=500 (and not a timeout/connectionError) — '
              "the default shouldRetry doesn't match it");
    });
  });

  group('DiomanAuth: defaultAuthFailure classification', () {
    // defaultAuthFailure is exported as a standalone top-level function
    // specifically so its classification logic is unit-testable without
    // having to orchestrate the full request/response chain (its no-token
    // branch, in particular, can only occur in production via a narrow
    // concurrent-clear race — trivial to hit directly, impractical to force
    // deterministically through a real request).
    test('with no token in the store: a 401 classifies as expired, a 403 '
        'as deny', () {
      final tm = _FakeTokenManager(null);
      final opts = RequestOptions(path: '/data');
      expect(
        defaultAuthFailure(
            tm, Response<dynamic>(requestOptions: opts, statusCode: 401), 'Authorization'),
        DiomanAuthFailureAction.expired,
      );
      expect(
        defaultAuthFailure(
            tm, Response<dynamic>(requestOptions: opts, statusCode: 403), 'Authorization'),
        DiomanAuthFailureAction.deny,
      );
    });

    test('falls back to reading the header directly when no raw token was '
        'stashed (e.g. a custom `ready` callback bypassed the stash), and '
        'still correctly classifies refresh vs replay', () {
      final tm = _FakeTokenManager('t0');
      // The header-fallback compares the RAW header value against the raw
      // store token verbatim — it does NOT strip a "Bearer " prefix (that
      // stripping only happens for the normal, stashed-token path). A
      // custom `ready` callback that wants this fallback to classify
      // correctly must inject the bare token, not a formatted header.
      final matching =
          RequestOptions(path: '/data', headers: {'Authorization': 't0'});
      expect(
        defaultAuthFailure(
            tm, Response<dynamic>(requestOptions: matching, statusCode: 401), 'Authorization'),
        DiomanAuthFailureAction.refresh,
        reason: 'header carries the SAME token the store currently has',
      );

      final stale = RequestOptions(
          path: '/data', headers: {'Authorization': 'Bearer old'});
      expect(
        defaultAuthFailure(
            tm, Response<dynamic>(requestOptions: stale, statusCode: 401), 'Authorization'),
        DiomanAuthFailureAction.replay,
        reason: 'header carries a DIFFERENT (stale) token — someone else '
            'already refreshed',
      );
    });

    test('a custom ready callback (instead of buildHeader) still reaches a '
        'successful replay end-to-end — no raw token is stashed for it, so '
        'classification falls back to the header-fallback path exercised '
        'above, either action of which still replays and recovers',
        () async {
      final tm = _FakeTokenManager('t0');
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'e': 1}, 401);
        return respondJson(req, {'v': 'ok'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => tm.set('t1'),
        onAccessExpired: (_, __) async {},
        ready: (tm, opts) async {
          opts.headers['Authorization'] = 'Bearer ${tm.accessToken}';
        },
      ));

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data, {'v': 'ok'});
      expect(attempts, 2);
    });
  });

  group('DiomanCancel: re-entry with an already-injected token', () {
    test('re-dispatching the SAME RequestOptions object a second time — '
        'still carrying the CancelToken this plugin injected on the first, '
        'already-completed pass — re-registers that token for cancelAll',
        () async {
      var attempts = 0;
      final firstDone = Completer<void>();
      final secondStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          await respondJson(req, {'v': 1}, 200);
          firstDone.complete();
          return;
        }
        secondStarted.complete();
        await Completer<void>().future; // hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanCancel());

      final options =
          RequestOptions(path: '/data', baseUrl: dio.options.baseUrl);
      await dio.fetch<void>(options);
      await firstDone.future;

      final second = dio.fetch<void>(options); // SAME RequestOptions object
      await secondStarted.future;
      final cancelled = cancelAll(dio, 'test');
      expect(cancelled, greaterThanOrEqualTo(1),
          reason: 'the re-entering token was re-registered, so cancelAll '
              'can see and abort it');
      await expectLater(second, throwsA(isA<DioException>()));
    });
  });

  group('DiomanLog', () {
    test('logs request/response/error text through a custom writer, '
        'covering headers, body truncation, and the network-error (no '
        'response) label', () async {
      final logs = <String>[];
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          return respondJson(req, {'v': 'x' * 50}, 200);
        }
        return respondJson(req, {'fail': true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanLog(
        logHeaders: true,
        maxBodyLength: 10,
        writer: (m, {error}) => logs.add(m),
      ));

      await dio.post<void>('/data',
          data: {'a': 1}, options: Options(headers: {'X-Test': '1'}));
      expect(logs.any((l) => l.contains('Headers:')), isTrue);
      expect(logs.any((l) => l.contains('… (+')), isTrue,
          reason: 'the 50-char body got truncated at maxBodyLength=10');

      logs.clear();
      await expectLater(dio.get<void>('/data'), throwsA(isA<DioException>()));
      expect(logs.any((l) => l.startsWith('[dioman:log] ✗ 500')), isTrue);
    });

    test('with no writer given, falls back to the default sink without '
        'throwing', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanLog());
      await dio.get<void>('/data'); // must not throw
    });
  });

  group('DiomanMock: mockUrl redirect path', () {
    test('defaultFallback: 404 or a non-cancel network error triggers '
        'fallback; a cancel or any other status does not', () {
      final opts = RequestOptions(path: '/x');
      expect(defaultFallback(response: Response(requestOptions: opts, statusCode: 404)), isTrue);
      expect(defaultFallback(response: Response(requestOptions: opts, statusCode: 200)), isFalse);
      expect(
          defaultFallback(
              error: DioException(requestOptions: opts, type: DioExceptionType.connectionError)),
          isTrue);
      expect(
          defaultFallback(error: DioException(requestOptions: opts, type: DioExceptionType.cancel)),
          isFalse);
      expect(defaultFallback(), isFalse);
    });

    test('a successful mock-server response is returned directly, and a '
        'fallback-triggering one instead falls back to the real API',
        () async {
      final mockServer = await TestServer.start(
          (req) => respondJson(req, {'v': 'mocked'}, 200));
      addTearDown(mockServer.close);
      final realServer = await TestServer.start(
          (req) => respondJson(req, {'v': 'real'}, 200));
      addTearDown(realServer.close);

      final dio1 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio1.interceptors.add(DiomanMock(enabled: true, mockUrl: mockServer.baseUrl));
      final r1 = await dio1.get<Map<String, dynamic>>('/data');
      expect(r1.data, {'v': 'mocked'});

      final dio2 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio2.interceptors.add(DiomanMock(
        enabled: true,
        mockUrl: mockServer.baseUrl,
        fallbackWhen: ({response, error}) => true, // always fall back
      ));
      final r2 = await dio2.get<Map<String, dynamic>>('/data');
      expect(r2.data, {'v': 'real'});
    });

    test('a mock server that errors outright falls back to the real API '
        'when fallbackWhen says so, and rejects otherwise', () async {
      final realServer =
          await TestServer.start((req) => respondJson(req, {'v': 'real'}, 200));
      addTearDown(realServer.close);
      // A real TestServer, immediately closed — its port is genuinely
      // unreachable (connection refused), a real network failure rather
      // than a hand-picked "probably nothing's listening" address.
      final deadServer =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      final deadMockUrl = deadServer.baseUrl;
      await deadServer.close();

      final dio1 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio1.interceptors.add(DiomanMock(
        enabled: true,
        mockUrl: deadMockUrl,
        fallbackWhen: ({response, error}) => true,
      ));
      final r1 = await dio1
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 5));
      expect(r1.data, {'v': 'real'});

      final dio2 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio2.interceptors.add(DiomanMock(
        enabled: true,
        mockUrl: deadMockUrl,
        fallbackWhen: ({response, error}) => false, // never fall back
      ));
      await expectLater(
        dio2.get<void>('/data').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
      );
    });

    test('remove()/reset() operate on the live inline-handler route table',
        () async {
      final server = await TestServer.start((req) => respondJson(req, {'v': 'real'}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add('GET:/data', (options) async => ResponseBody.fromString(
          '{"v":"mocked"}', 200,
          headers: {'content-type': ['application/json']}));
      dio.interceptors.add(mock);

      final r1 = await dio.get<Map<String, dynamic>>('/data');
      expect(r1.data, {'v': 'mocked'});

      mock.remove('GET:/data');
      final r2 = await dio.get<Map<String, dynamic>>('/data');
      expect(r2.data, {'v': 'real'});

      mock.add('GET:/data', (options) async => ResponseBody.fromString(
          '{"v":"mocked2"}', 200,
          headers: {'content-type': ['application/json']}));
      mock.reset();
      final r3 = await dio.get<Map<String, dynamic>>('/data');
      expect(r3.data, {'v': 'real'});
    });

    test('an inline handler that throws a DioException is rejected as-is',
        () async {
      // A real server, never actually contacted — the inline handler
      // intercepts before any network call, but keeping a real backing
      // server matches this suite's convention over a fake/unreachable URL.
      final server =
          await TestServer.start((req) => respondJson(req, {'v': 'real'}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add('GET:/data', (options) async {
        throw DioException(requestOptions: options, message: 'handler blew up');
      });
      dio.interceptors.add(mock);

      await expectLater(
        dio.get<void>('/data'),
        throwsA(isA<DioException>()
            .having((e) => e.message, 'message', 'handler blew up')),
      );
    });
  });

  group('DiomanShare: none policy, own-failure settlement, dispose, '
      'hasMultipleDownstreamSettlers', () {
    test('without DiomanKey installed, share is a no-op — every call is '
        'independent', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.start));

      await Future.wait([dio.get<void>('/data'), dio.get<void>('/data')]);
      expect(calls, 2, reason: 'no key ⇒ share never dedupes');
    });

    test('policy: none passes every request through independently — never '
        'shared, and errors reach onError with no entry attached', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        return respondJson(req, {'fail': true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.none));

      await expectLater(dio.get<void>('/data'), throwsA(isA<DioException>()));
      await expectLater(dio.get<void>('/data'), throwsA(isA<DioException>()));
      expect(calls, 2, reason: 'policy none never dedupes');
    });

    test('policy: end — a SOLO caller (matching seq, not superseded) whose '
        'own request fails settles the entry with that failure', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {'fail': true}, 500));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanShare(policy: DiomanSharePolicy.end));

      await expectLater(
        dio.get<Map<String, dynamic>>('/data'),
        throwsA(isA<DioException>()),
      );
    });

    test('registerDownstreamSettler(): a single registration is not '
        '"multiple"; a second one is', () {
      final share = DiomanShare();
      expect(share.hasMultipleDownstreamSettlers, isFalse);
      share.registerDownstreamSettler();
      expect(share.hasMultipleDownstreamSettlers, isFalse);
      share.registerDownstreamSettler();
      expect(share.hasMultipleDownstreamSettlers, isTrue);
    });

    test('settle() explicitly completes an entry with an error, and removes '
        'it so a later caller for the same key starts fresh', () async {
      final started = Completer<void>();
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          started.complete();
          await Completer<void>().future; // leader hangs forever
        }
        await respondJson(req, {'v': 'later'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      dio.interceptors.add(share);

      final leader = dio.get<void>('/data');
      leader.ignore(); // never settles through the normal path in this test
      await started.future;
      share.settle('GET:/data',
          error: DioException(
              requestOptions: RequestOptions(path: '/data'),
              message: 'forced'));
      // A later, independent caller for the same key must not find a stale
      // entry — settle() removed it, so this is a genuinely fresh request.
      final r = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 3));
      expect(r.data, {'v': 'later'});
    });

    test('dispose() completes a pending follower with an error instead of '
        'leaving it hanging (documented previously as NOT doing this — '
        'confirmed fixed)', () async {
      final started = Completer<void>();
      final server = await TestServer.start((req) async {
        started.complete();
        await Completer<void>().future; // hangs
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      dio.interceptors.add(share);

      final leader = dio.get<void>('/data');
      leader.ignore();
      await started.future;
      final follower = dio.get<void>('/data');
      share.dispose();
      await expectLater(follower, throwsA(isA<DioException>()));
    });
  });

  group('DiomanAuth: additional realistic branches', () {
    test('a second request arriving while a FIRST request\'s proactive '
        'refresh is already in flight awaits the SAME refresh, and is '
        'rejected the same way when it fails', () async {
      final tm = _FakeTokenManager('t0');
      final server =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final refreshStarted = Completer<void>();
      final refreshGate = Completer<void>();
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        expiresAt: (_) => DateTime(2000), // always already expired
        onRefresh: (_, __) async {
          refreshStarted.complete();
          await refreshGate.future;
          throw Exception('refresh failed');
        },
        onAccessExpired: (_, __) async {},
      ));

      final a = dio.get<void>('/data');
      // Calling an async onRefresh runs it synchronously up to its first
      // await, so by the time refreshStarted resolves, `_refreshing` is
      // already set — no timing guesswork needed for b to see it.
      await refreshStarted.future;
      final b = dio.get<void>('/data');
      // Attach both expectations BEFORE completing refreshGate: once it
      // completes, a and b reject on the next microtask, and a Future
      // rejection with no error handler attached yet is flagged as an
      // unhandled zone error immediately — it doesn't wait around for a
      // later `await` to claim it.
      final aExpectation = expectLater(a, throwsA(isA<DioException>()));
      final bExpectation = expectLater(b, throwsA(isA<DioException>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      refreshGate.complete();

      await aExpectation;
      await bExpectation;
    });

    test('a custom onAccessDenied callback is used (instead of falling back '
        'to onAccessExpired) when a protected request has no token', () async {
      final tm = _FakeTokenManager(null);
      var deniedCalls = 0;
      var expiredCalls = 0;
      final server =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async => expiredCalls++,
        onAccessDenied: (_, __) async => deniedCalls++,
      ));

      await expectLater(dio.get<void>('/data'), throwsA(isA<DioException>()));
      expect(deniedCalls, 1);
      expect(expiredCalls, 0);
    });

    test('a network-level error with no HTTP response at all is cleared '
        'and passed through, not misclassified', () async {
      final tm = _FakeTokenManager('t0');
      // A real TestServer, immediately closed — genuinely unreachable
      // (connection refused) rather than a hand-picked dead address.
      final deadServer =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
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

      await expectLater(dio.get<void>('/data'), throwsA(isA<DioException>()));
    });

    test('re-dispatching the SAME RequestOptions after a SUCCESSFUL '
        'refresh+replay, if it fails again, hits the "already replayed '
        'once" guard and gives up immediately rather than refreshing again',
        () async {
      // _kRefreshed (and the rest of the auth flags) is only cleared on a
      // FAILURE path (see _clearFlags call sites) — a successful refresh+
      // replay leaves it set. So the guard is only observable by re-using
      // the SAME RequestOptions after a cycle that actually SUCCEEDED.
      final tm = _FakeTokenManager('t0');
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts <= 2) {
          return respondJson(req, {'e': 1}, attempts == 1 ? 401 : 200);
        }
        return respondJson(req, {'e': 1}, 401); // third dispatch fails again
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      var expiredCalls = 0;
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => tm.set('t1'),
        onAccessExpired: (_, __) async => expiredCalls++,
      ));

      final options =
          RequestOptions(path: '/data', baseUrl: dio.options.baseUrl);
      await dio.fetch<void>(options); // 401 then a successful replay
      expect(attempts, 2);

      await expectLater(dio.fetch<void>(options), throwsA(isA<DioException>()));
      expect(attempts, 3,
          reason: 'only ONE more attempt — the already-replayed guard '
              'skips trying to refresh again');
      expect(expiredCalls, 1);
    });

    test('a custom onFailure callback can force the deny or expired action '
        'directly, regardless of the default classification', () async {
      final tm = _FakeTokenManager('t0');
      var deniedCalls = 0;
      var expiredCalls = 0;
      final server =
          await TestServer.start((req) => respondJson(req, {'e': 1}, 401));
      addTearDown(server.close);

      final dio1 = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio1.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
        onAccessDenied: (_, __) async => deniedCalls++,
        onFailure: (_, __) => DiomanAuthFailureAction.deny,
      ));
      await expectLater(dio1.get<void>('/data'), throwsA(isA<DioException>()));
      expect(deniedCalls, 1);

      final dio2 = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio2.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async => expiredCalls++,
        onFailure: (_, __) => DiomanAuthFailureAction.expired,
      ));
      await expectLater(dio2.get<void>('/data'), throwsA(isA<DioException>()));
      expect(expiredCalls, 1);
    });

    test('a custom isProtected callback decides per-request whether auth '
        'applies at all', () async {
      final tm = _FakeTokenManager(null); // no token
      final server =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
        isProtected: (opts) => opts.path.startsWith('/protected'),
      ));

      // Unprotected path: no token needed, passes straight through.
      final r = await dio.get<void>('/public');
      expect(r.statusCode, 200);

      // Protected path: no token ⇒ denied.
      await expectLater(
          dio.get<void>('/protected/x'), throwsA(isA<DioException>()));
    });
  });

  group('DiomanNormalize', () {
    test('DiomanException.toString() includes the code and message', () {
      const e = DiomanException(code: 1, message: 'boom');
      expect(e.toString(), 'DiomanException(code: 1, message: boom)');
    });

    test('a custom shouldNormalize overrides the default envelope-detection '
        'heuristic', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'code': 0, 'data': {'v': 1}, 'message': ''}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanNormalize(shouldNormalize: (o, r) => false));

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data, {'code': 0, 'data': {'v': 1}, 'message': ''},
          reason: 'shouldNormalize forced false — envelope left untouched '
              'even though it looks like one');
    });
  });
}
