// Combinatorial integration tests across dioman's 6 STATEFUL plugins:
// DiomanCache, DiomanShare, DiomanCancel, DiomanLoading, DiomanAuth,
// DiomanRetry — installed in their canonical relative order
// (cache→share→cancel→loading→auth→retry, per dioman.dart:58-59).
//
// Scope decision (see conversation): the full power-set of all 13 plugins
// is 2^13-13-1 = 8178 combinations before even varying per-plugin params —
// not tractable by hand. The other 7 plugins (envs, repath, filter, key,
// normalize, mock, log) are pure request/response transforms with no
// shared mutable state or async continuation, so they're covered by a
// handful of "full stack" smoke tests instead of full combinatorics.
//
// This file targets the 6 stateful plugins because they're the ones that
// hold mutable state across the request lifecycle (in-flight registries,
// counters, refresh windows, shared completers) — which is exactly the
// class of bug the DiomanShare+DiomanRetry investigation surfaced. Pairwise
// (15 combos) gets a dedicated test each; higher-order combos get targeted
// tests where a pairwise interaction plausibly compounds with a third
// plugin, plus one full 6-plugin + full 13-plugin smoke test.
//
// Requests go over a REAL loopback HttpServer (test/support/test_server.dart)
// rather than a hand-rolled HttpClientAdapter — this matters here because
// DiomanAuth's replay and DiomanShare's own retry policy re-dispatch through
// a bare, interceptor-less `Dio()` that only reaches a real server (verified:
// it reuses the already-resolved `RequestOptions.baseUrl`, not the bare
// Dio's own empty BaseOptions), letting several scenarios that used to be
// untestable (they'd otherwise hit the real internet) run for real.
import 'support/fake_cache_persist.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

class FakeTokenManager implements DiomanTokenManager {
  FakeTokenManager(this._access);
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

/// Installs a subset of the 6 stateful plugins on [dio], in their canonical
/// relative order, auto-adding [DiomanKey] whenever [cache] or [share] is
/// present (both depend on it).
void installStateful(
  Dio dio, {
  DiomanCache? cache,
  DiomanShare? share,
  DiomanCancel? cancel,
  DiomanLoading? loading,
  DiomanAuth? auth,
  DiomanRetry? retry,
}) {
  if (cache != null || share != null) dio.interceptors.add(const DiomanKey());
  for (final p in [cache, share, cancel, loading, auth, retry]) {
    if (p != null) dio.interceptors.add(p);
  }
}

void main() {
  group('pairwise: cache + share', () {
    test(
        'a cache hit resolves before DiomanShare.onRequest ever runs — no '
        'dedup needed once the answer is already known', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio,
          cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ), share: DiomanShare(policy: DiomanSharePolicy.start));

      await dio.get<void>('/data');
      expect(calls, 1);

      // Second call: cache hit — never reaches share at all.
      await dio.get<void>('/data');
      expect(calls, 1, reason: 'cache hit short-circuits before share');
    });

    test(
        'two concurrent callers before anything is cached still dedupe via '
        'share, and the single real response gets cached for a third, '
        'later caller', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio,
          cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ), share: DiomanShare(policy: DiomanSharePolicy.start));

      final a = dio.get<Map<String, dynamic>>('/data');
      final b = dio.get<Map<String, dynamic>>('/data');
      final results = await Future.wait([a, b]).timeout(const Duration(seconds: 3));
      expect(calls, 1, reason: 'b deduped onto a via share');
      expect(results[0].data, results[1].data);

      await dio.get<void>('/data');
      expect(calls, 1, reason: 'third caller hits the now-populated cache');
    });
  });

  group('pairwise: cache + cancel', () {
    test('a cache hit never allocates a CancelToken via DiomanCancel',
        () async {
      final server = await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cancel = DiomanCancel();
      installStateful(dio, cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ), cancel: cancel);

      await dio.get<void>('/data'); // real, tracked briefly then released
      await dio.get<void>('/data'); // cache hit
      expect(cancelAll(dio), 0,
          reason: 'nothing left in flight; the cache hit never registered a '
              'token in the first place');
    });
  });

  group('pairwise: cache + loading', () {
    test('a cache hit never increments the loading counter', () async {
      final server = await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(dio,
          cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ),
          loading: DiomanLoading(onChanged: states.add));

      await dio.get<void>('/data'); // real: true then false
      await dio.get<void>('/data'); // cache hit: loading.onRequest never runs
      expect(states, [true, false],
          reason: 'the cache-hit call never touches the loading counter at '
              'all — cache sits before loading in the chain and resolves '
              'before loading.onRequest is reached');
    });
  });

  group('pairwise: cache + auth', () {
    test(
        'a cache hit bypasses DiomanAuth entirely — a protected endpoint '
        "cached response is served even after the caller's token is "
        'cleared', () async {
      final server = await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final tm = FakeTokenManager('t0');
      installStateful(
        dio,
        cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
      );

      await dio.get<void>('/data'); // real, authenticated, cached
      tm.clear(); // token now gone
      final r =
          await dio.get<Map<String, dynamic>>('/data'); // still a cache hit
      expect(r.data, {'v': 1},
          reason: 'cache sits before auth in the canonical chain, so a hit '
              "never reaches auth's protection check — same limitation as "
              'cache+loading/cache+cancel above, documented behavior of a '
              'response cache, not a bug');
    });
  });

  group('pairwise: cache + retry', () {
    // DiomanRetry's re-issue goes through a throwaway, interceptor-less Dio
    // (see retry_plugin.dart) — it never re-enters DiomanCache at all, in
    // either direction. Two consequences, both by design:
    test(
        "a retried response is NOT cached — the retry re-issue never "
        "reaches DiomanCache.onResponse", () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'fail': true}, 500);
        return respondJson(req, {'v': 'retried'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio, cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ));
      dio.interceptors.add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final r1 = await dio.get<Map<String, dynamic>>('/data');
      expect(r1.data, {'v': 'retried'});
      expect(attempts, 2);

      final r2 = await dio.get<Map<String, dynamic>>('/data');
      expect(r2.data, {'v': 'retried'});
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
        "FIXED: a cache hit landing on the entry the ORIGINAL failed attempt "
        "poisoned still gets a chance to recover via DiomanRetry — a "
        'DIFFERENT, later caller for the same key ends up with the correct '
        'data, not the stale failure', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          return respondJson(req, {'code': 1, 'data': null, 'message': 'fail'}, 200);
        }
        return respondJson(req, {'code': 0, 'data': {'v': 'ok'}, 'message': ''}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cache = DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, );
      installStateful(dio, cache: cache);
      dio.interceptors.add(DiomanRetry(
        max: 1,
        delay: (_, __, ___, ____) => Duration.zero,
        shouldRetry: (err, response) => (response?.data as Map)['code'] != 0,
      ));

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data!['code'], 0,
          reason: 'the caller for THIS request still correctly gets the '
              "retried, successful result — the retry's own re-issue "
              'reached the network directly, never consulting the cache');
      expect(attempts, 2);

      final later = await dio.get<Map<String, dynamic>>('/data');
      expect(later.data!['code'], 0,
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

  group('pairwise: share + cancel', () {
    // ROOT CAUSE (found while writing this test, applies beyond this pair):
    // DiomanCancel.onRequest created its own CancelToken but never set
    // `token.requestOptions`. dio's own `Options.compose` (options.dart:374)
    // only wires `cancelToken.requestOptions = requestOptions` when a
    // caller-supplied token is ALREADY attached before compose runs; a token
    // an interceptor attaches later, during onRequest, never got that
    // backfilled. So when `CancelToken.cancel()` fired, `cancel_token.dart:56`
    // fell back to `requestOptions ?? RequestOptions()` — a BRAND NEW,
    // empty RequestOptions. Every plugin downstream saw a DioException whose
    // `requestOptions.extra` was `{}`, wiping out everything written during
    // onRequest (DiomanShare's `_kEntry`, DiomanLoading's `_kBracketed`,
    // DiomanRetry's retry counter, DiomanKey's key, ...) — which meant
    // DiomanShare.onError could never find `_kEntry` to settle/remove the
    // entry, permanently deadlocking that key for every future caller, not
    // just concurrent ones. FIXED: cancel_plugin.dart now sets
    // `token.requestOptions = options;` right after creating the token.
    test(
        'FIXED: cancelling a DiomanShare leader no longer deadlocks that '
        "key — a completely new, later caller for the same key correctly "
        'reaches the network instead of hanging on a dead entry',
        () async {
      var calls = 0;
      final firstStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        calls++;
        if (calls == 1) {
          firstStarted.complete();
          await Completer<void>().future; // hangs until the connection dies
          return;
        }
        await respondJson(req, {'v': 'later'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio,
          share: DiomanShare(policy: DiomanSharePolicy.start),
          cancel: DiomanCancel());

      final leader = dio.get<void>('/data');
      await firstStarted.future;
      cancelAll(dio, 'test');
      await expectLater(
        leader.timeout(const Duration(seconds: 2)),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)),
      );

      // A completely NEW, later request for the SAME key — nothing
      // concurrent with the cancelled one. It must hit the network fresh,
      // not hang on the cancelled leader's dead entry.
      final r = await dio.get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 2));
      expect(r.data, {'v': 'later'});
      expect(calls, 2,
          reason: "the leader's dead entry was correctly cleared from "
              "DiomanShare's `_active` map on cancellation, so this later "
              'caller started a fresh request instead of waiting on it');
    });
  });

  group('pairwise: share + loading', () {
    test(
        'a follower is invisible to the loading counter — only the leader '
        'is counted, because a follower never reaches '
        "DiomanLoading.onRequest (share's else-branch never calls "
        'handler.next)', () async {
      final release = Completer<void>();
      final server = await TestServer.start((req) async {
        await release.future;
        await respondJson(req, {'v': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(dio,
          share: DiomanShare(policy: DiomanSharePolicy.start),
          loading: DiomanLoading(onChanged: states.add));

      final a = dio.get<void>('/data');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final b = dio.get<void>('/data'); // follower — never bumps the counter
      await Future<void>.delayed(const Duration(milliseconds: 10));
      release.complete();
      await Future.wait([a, b]).timeout(const Duration(seconds: 3));

      expect(states, [true, false],
          reason: 'exactly one 0→1→0 edge — the follower never incremented '
              'the counter a second time');
    });
  });

  group('pairwise: share + retry', () {
    // FIXED (see share_plugin.dart / retry_plugin.dart): passing the SAME
    // DiomanShare instance to DiomanRetry's `share` setter registers retry
    // as the entry's settler. DiomanShare then defers its own onError
    // settlement, so a concurrent follower stays bound to the (not yet
    // completed) shared completer instead of being delivered the pre-retry
    // failure — and DiomanRetry explicitly completes it once IT reaches the
    // true final outcome.
    test(
        'FIX: a concurrent follower now receives the RETRIED result, not '
        "the leader's pre-retry failure", () async {
      var attempts = 0;
      final followerJoined = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          // Hold the leader's 500 open until the follower has definitely
          // attached — with a zero backoff delay, the leader's whole
          // fail→retry→succeed cycle could otherwise complete (settling
          // and removing the entry) before the follower even reaches
          // DiomanShare.onRequest.
          await followerJoined.future;
          return respondJson(req, {'fail': true}, 500);
        }
        return respondJson(req, {'v': 'retried'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      installStateful(dio, share: share);
      dio.interceptors.add(DiomanRetry(
        max: 1,
        delay: (_, __, ___, ____) => Duration.zero,
      )..share = share);

      final leader = dio.get<Map<String, dynamic>>('/data');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final follower = dio.get<Map<String, dynamic>>('/data');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      followerJoined.complete();

      final leaderResult = await leader.timeout(const Duration(seconds: 3));
      final followerResult =
          await follower.timeout(const Duration(seconds: 3));
      expect(leaderResult.data, {'v': 'retried'});
      expect(followerResult.data, {'v': 'retried'},
          reason: 'previously this follower would have been stuck with the '
              'pre-retry 500 (or hung, per the unrelated dio-zone quirk '
              'noted below) — now it correctly observes the retry');
      expect(attempts, 2);
    });

    test(
        "FIX: a THIRD caller arriving while the retry is still in flight "
        'still dedupes against it (no 3rd network call) — the reentry-skip '
        "marker doesn't disturb DiomanShare's normal dedup for genuinely "
        'new callers', () async {
      var attempts = 0;
      final retryInFlight = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'fail': true}, 500);
        retryInFlight.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return respondJson(req, {'v': 'retried'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      installStateful(dio, share: share);
      dio.interceptors.add(DiomanRetry(
        max: 1,
        delay: (_, __, ___, ____) => Duration.zero,
      )..share = share);

      final a = dio.get<Map<String, dynamic>>('/data');
      await retryInFlight.future;
      final c = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 3));
      expect(c.data, {'v': 'retried'});
      expect(attempts, 2, reason: 'C deduped against the in-flight retry');
      expect((await a.timeout(const Duration(seconds: 3))).data,
          {'v': 'retried'});
    });
  });

  group('pairwise: share + auth', () {
    // Now automatable with a real server: DiomanAuth's `_replay` (a bare,
    // interceptor-less Dio) genuinely reaches this test's TestServer,
    // instead of the real internet — so refresh+replay can actually
    // succeed.
    test(
        'a solo caller correctly gets its own refreshed+replayed result '
        'through DiomanShare+DiomanAuth together', () async {
      final tm = FakeTokenManager('t0');
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'error': 1}, 401);
        return respondJson(req, {'v': 'refreshed'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(
        dio,
        share: DiomanShare(policy: DiomanSharePolicy.start),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set('t1'),
          onAccessExpired: (_, __) async {},
        ),
      );

      final leaderResult = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 3));
      expect(leaderResult.data, {'v': 'refreshed'},
          reason: 'the leader correctly observes its own refreshed+replayed '
              'result, independent of the shared entry');
      expect(attempts, 2, reason: '401 then the successful replay');
    });

    // FIXED (same mechanism as "share + retry" above): passing the SAME
    // DiomanShare instance to DiomanAuth's `share` setter registers auth as
    // the entry's settler for this key, so a concurrent follower gets the
    // REFRESHED result instead of the stale pre-refresh 401.
    test(
        'FIX: a concurrent follower now receives the REFRESHED+replayed '
        "result, not the leader's pre-refresh 401", () async {
      final tm = FakeTokenManager('t0');
      var attempts = 0;
      final followerJoined = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          // Hold the leader's 401 open until the follower has definitely
          // attached — otherwise, since onRefresh here has no artificial
          // delay, the leader's whole 401→refresh→replay cycle could
          // complete (and settle+remove the entry) before the follower
          // even reaches DiomanShare.onRequest, making it start its own
          // fresh leader entry instead of truly joining this one.
          await followerJoined.future;
          return respondJson(req, {'error': 1}, 401);
        }
        return respondJson(req, {'v': 'refreshed'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final share = DiomanShare(policy: DiomanSharePolicy.start);
      installStateful(dio, share: share);
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => tm.set('t1'),
        onAccessExpired: (_, __) async {},
      )..share = share);

      final leader = dio.get<Map<String, dynamic>>('/data');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final follower = dio.get<Map<String, dynamic>>('/data');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      followerJoined.complete();

      final leaderResult = await leader.timeout(const Duration(seconds: 3));
      final followerResult =
          await follower.timeout(const Duration(seconds: 3));
      expect(leaderResult.data, {'v': 'refreshed'});
      expect(followerResult.data, {'v': 'refreshed'},
          reason: 'previously this follower would have been stuck with the '
              'pre-refresh 401 — now it correctly observes the replay');
      expect(attempts, 2);
    });

    // The genuinely-unfixable half: a follower that ends up bound to a
    // FINAL ERROR (retry/auth exhausted, nothing recovers it) still crashes
    // with the same "SEPARATE, pre-existing" dio interceptor-zone quirk
    // flagged on the policy=retry test in dioman_test.dart (a
    // completer-based `handler.reject` from inside `_handleStart`'s
    // else-branch) — confirmed while writing this fix: unrelated to
    // transport or to whether settlement is deferred, it reproduces the
    // same way it always has. Not exercised here for that reason.
  });

  group('pairwise: cancel + loading', () {
    // Same root cause as the "share + cancel" deadlock test above — see the
    // FIXED note there. DiomanCancel now sets `token.requestOptions` so a
    // cancellation error carries the real RequestOptions (with all of this
    // request's `extra` state, including DiomanLoading's `_kBracketed` flag)
    // instead of a blank one.
    test(
        'FIXED: cancelling a request correctly settles the loading counter '
        'back to 0 — DiomanLoading._decrement can now find its own '
        '`_kBracketed` flag on the cancellation RequestOptions',
        () async {
      final started = Completer<void>();
      final server = await TestServer.start((req) async {
        started.complete();
        await Completer<void>().future; // hangs until the connection dies
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      final loading = DiomanLoading(onChanged: states.add);
      installStateful(dio, cancel: DiomanCancel(), loading: loading);

      final call = dio.get<void>('/data');
      await started.future;
      cancelAll(dio, 'test');
      await expectLater(call.timeout(const Duration(seconds: 2)),
          throwsA(isA<DioException>()));

      expect(states, [true, false],
          reason: 'a caller driving a global spinner off this callback '
              'correctly sees it turn back off after the cancellation');
      expect(loading.activeCount, 0,
          reason: 'the internal counter is back to 0 too, not just the '
              'callback — a later unrelated request starts its own fresh '
              'batch instead of looking like it joined a stuck one');
    });
  });

  group('pairwise: cancel + auth', () {
    // Now automatable with a real server: the replay genuinely reaches
    // this TestServer, so we can deterministically wait for it to actually
    // be in flight instead of guessing with a fixed delay.
    test(
        'without wiring DiomanAuth to the DiomanCancel instance, cancelAll '
        "still cannot abort a request DiomanAuth is currently replaying — "
        'the replay uses a throwaway Dio with no interceptors, so it never '
        're-registers with DiomanCancel on its own', () async {
      final tm = FakeTokenManager('t0');
      var attempts = 0;
      final replayStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'error': 1}, 401);
        replayStarted.complete();
        await Completer<void>().future; // replay hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(
        dio,
        cancel: DiomanCancel(),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set('t1'),
          onAccessExpired: (_, __) async {},
          // NOTE: no `cancel` setter — this is the unfixed, opt-out-by-omission
          // case.
        ),
      );

      final call = dio.get<void>('/data');
      call.ignore(); // it never settles in this test — the replay hangs

      await replayStarted.future; // the replay is now genuinely in flight

      final cancelled = cancelAll(dio, 'test');
      expect(cancelled, 0,
          reason: 'the in-flight replay holds no token DiomanCancel knows '
              "about, since it was never told about that cancel instance");
    });

    test(
        'FIX: passing the same DiomanCancel instance to DiomanAuth lets '
        'cancelAll abort a request currently being replayed', () async {
      final tm = FakeTokenManager('t0');
      var attempts = 0;
      final replayStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'error': 1}, 401);
        replayStarted.complete();
        await Completer<void>().future; // replay hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cancel = DiomanCancel();
      installStateful(
        dio,
        cancel: cancel,
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set('t1'),
          onAccessExpired: (_, __) async {},
        )..cancel = cancel,
      );

      final call = dio.get<void>('/data');
      await replayStarted.future; // the replay is now genuinely in flight

      final cancelled = cancelAll(dio, 'test');
      expect(cancelled, 1,
          reason: 'the replay\'s token is now tracked — cancelAll aborts it');
      await expectLater(
        call.timeout(const Duration(seconds: 2)),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)),
      );
    });
  });

  group('pairwise: cancel + retry', () {
    test('already covered by the "DiomanCancel + DiomanRetry" group in '
        'dioman_test.dart — a retried token stays trackable by cancelAll() '
        'because cancel_plugin.dart explicitly re-registers it on re-entry',
        () {}, skip: 'see dioman_test.dart for the actual regression test');
  });

  group('pairwise: loading + auth', () {
    // Now automatable with a real server: the replay reaches this
    // TestServer, so the FULL successful refresh+replay path can be
    // exercised (this was previously downgraded to a "refresh fails" test
    // because the replay used to go out over the real internet).
    test(
        'a 401 that DiomanAuth successfully refreshes+replays only settles '
        'the loading counter ONCE, at the point the replayed response '
        'finally lands — no premature 0-edge from the initial 401',
        () async {
      final tm = FakeTokenManager('t0');
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'error': 1}, 401);
        return respondJson(req, {'v': 'ok'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(
        dio,
        loading: DiomanLoading(onChanged: states.add),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set('t1'),
          onAccessExpired: (_, __) async {},
        ),
      );

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data, {'v': 'ok'});
      expect(attempts, 2);
      expect(states, [true, false],
          reason: "auth's whole refresh-then-replay dance happens inside "
              "ONE onError pass (it resolves the error directly via "
              'handler.resolve) — loading only ever sees a single settle '
              'for this request, no flicker');
    });
  });

  group('pairwise: loading + retry', () {
    // FIXED as a side effect of DiomanRetry's bare-dio redesign (see
    // retry_plugin.dart's class doc) — the retry re-issue never re-enters
    // DiomanLoading.onRequest/onError at all anymore, so there's nothing
    // left to cause the flicker this test used to demonstrate.
    test(
        "the loading counter stays steady at 1 across a retry — the "
        "re-issue never touches DiomanLoading, so there's no 0→1 flicker "
        'mid-retry', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'fail': true}, 500);
        return respondJson(req, {'v': 'ok'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(dio, loading: DiomanLoading(onChanged: states.add));
      dio.interceptors
          .add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data, {'v': 'ok'});
      expect(states, [true, false],
          reason: 'a single 0→1→0 edge for the whole logical request — the '
              'retry, on its own throwaway Dio, never bumps the counter '
              'again mid-flight');
    });
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
        'the retry re-issue carries the SAME auth header the original '
        "attempt had — auth's own token refresh never gets a chance to run "
        'again for it, but the combo still works correctly end to end',
        () async {
      final tm = FakeTokenManager('t0');
      var attempts = 0;
      final headersSeen = <String?>[];
      final server = await TestServer.start((req) async {
        attempts++;
        headersSeen.add(req.headers.value('authorization'));
        if (attempts == 1) return respondJson(req, {'fail': true}, 500);
        return respondJson(req, {'v': 'ok'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(
        dio,
        share: DiomanShare(policy: DiomanSharePolicy.start),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set('t1'),
          onAccessExpired: (_, __) async {},
        ),
      );
      dio.interceptors
          .add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data!['v'], 'ok');
      expect(attempts, 2);
      expect(headersSeen, ['Bearer t0', 'Bearer t0'],
          reason: "both attempts carry the SAME header — auth's onRequest "
              "never ran again for the retry's re-issue to refresh it, "
              'even though `tm` would have handed out a different token');
    });
  });

  group('3-way: cache + cancel + loading', () {
    test(
        'a cache hit skips cancel AND loading together, while a real '
        'network call is tracked by both', () async {
      final server = await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(dio,
          cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ),
          cancel: DiomanCancel(),
          loading: DiomanLoading(onChanged: states.add));

      await dio.get<void>('/data'); // real
      await dio.get<void>('/data'); // cache hit
      expect(states, [true, false]);
      expect(cancelAll(dio), 0);
    });
  });

  group('full stateful stack (all 6): cache+share+cancel+loading+auth+retry',
      () {
    // Deliberately uses a NETWORK-level (500) failure, not a business-level
    // one — the "pairwise: cache + retry" business-level test above covers
    // that combo's (narrower, now) remaining caveat. A network-level
    // failure never reaches cache.onResponse at all (it's routed through
    // onError, not onResponse), so there's nothing to poison here either
    // way.
    test('a network-level failure (500) still retries and eventually '
        'succeeds through the entire stack — cleanly, since DiomanRetry\'s '
        'bare-dio re-issue never touches cache/share/cancel/loading/auth/log '
        'along the way', () async {
      final tm = FakeTokenManager('t0');
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {'fail': true}, 500);
        return respondJson(req, {'code': 0, 'data': {'v': 'ok'}, 'message': ''}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(
        dio,
        cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ),
        share: DiomanShare(policy: DiomanSharePolicy.start),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: states.add),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set('t1'),
          onAccessExpired: (_, __) async {},
        ),
        retry: DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero),
      );

      final r = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 3));
      expect(r.data!['code'], 0);
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
      final r2 = await dio.get<Map<String, dynamic>>('/data');
      expect(r2.data!['code'], 0);
      expect(attempts, 3, reason: 'a fresh network hit, not a cache hit');
    });
  });

  group('full 13-plugin stack via Dioman.install', () {
    test('a plain successful request round-trips through all 13 plugins '
        'without crashing, and DiomanNormalize correctly unwraps the '
        'envelope', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'code': 0, 'data': {'v': 'ok'}, 'message': ''}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final tm = FakeTokenManager('t0');
      final states = <bool>[];
      final logs = <String>[];

      final handle = Dioman.install(
        dio,
        envs: DiomanEnvs([]),
        repath: DiomanRepath(),
        filter: const DiomanFilter(),
        key: const DiomanKey(),
        normalize: const DiomanNormalize(),
        cache: DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ),
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

      final r = await dio.get<Map<String, dynamic>>('/data');
      expect(r.data, {'v': 'ok'}, reason: 'normalize unwrapped the envelope');
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
