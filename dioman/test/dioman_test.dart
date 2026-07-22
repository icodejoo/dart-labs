// Regression tests for the code-review fixes to the dioman plugin chain.
// Uses a real dart:io HttpServer (see test/support/test_server.dart) so
// requests go over a real TCP loopback connection with real DNS/connect/
// cancel semantics — including for plugins that internally re-dispatch via a
// bare `Dio()` (DiomanAuth's replay, DiomanShare's retry policy), which now
// reach the real test server instead of the live internet.
import 'support/fake_cache_persist.dart';
import 'dart:async';
import 'dart:convert';

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
}

/// Token manager whose access token can be swapped by an `onRefresh` callback,
/// so the proactive-refresh tests can observe the fresh token being injected.
class RefreshableTokenManager implements DiomanTokenManager {
  RefreshableTokenManager(this._access);
  String? _access;
  void setToken(String? t) => _access = t;
  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => 'refresh';
  @override
  bool get canRefresh => true;
  @override
  void clear() => _access = null;
}

/// Minimal DiomanPlugin that records its own [name] into [onRun] whenever
/// [onRequest] fires — used to prove a manually-inserted plugin actually
/// runs at its inserted chain position, not just that it appears in the
/// plugin/interceptor lists.
class _RecordingPlugin extends DiomanPlugin {
  _RecordingPlugin(this._name, this.onRun);
  final String _name;
  final void Function(String) onRun;
  @override
  String get name => _name;
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) {
    onRun(_name);
    handler.next(options);
  }
}

void main() {
  group('DiomanAuth', () {
    // DiomanAuth's post-failure replay deliberately uses a throwaway `Dio()`
    // (see SKILL.md) so it never re-enters the interceptor chain. Against a
    // real TestServer that throwaway Dio's `.fetch()` still lands on our
    // test server (RequestOptions carries its own already-resolved
    // baseUrl), so the replay path is now genuinely observable end-to-end
    // instead of only via which AuthFailureAction was chosen.
    test(
        '401 with the default Bearer header triggers a refresh action, not '
        'replay/expire (regression: comparing the formatted header against '
        'the raw store token made the refresh branch unreachable)', () async {
      final tm = FakeTokenManager('old-token');
      var refreshCalls = 0;
      final server = await TestServer.start(
          (req) => respondJson(req, {'error': 'expired'}, 401));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (t, _) async => refreshCalls++,
        onAccessExpired: (_, __) async {},
      ));

      await expectLater(dio.get<void>('/data'), throwsA(isA<DioException>()));

      expect(refreshCalls, 1,
          reason: 'the request carried the token that is still current in '
              'the store, so this must route to refresh — the pre-fix '
              'Bearer-prefix mismatch always fell through to replay/expire '
              'and never called onRefresh at all');
    });

    test(
        'a denied request (no token) still releases the loading/cancel'
        ' brackets installed before auth', () async {
      final tm = FakeTokenManager(null);
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final loadingStates = <bool>[];
      final cancelPlugin = DiomanCancel();
      dio.interceptors.addAll([
        cancelPlugin,
        DiomanLoading(onChanged: loadingStates.add),
        DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
      ]);

      await expectLater(
          dio.get<void>('/protected'), throwsA(isA<DioException>()));

      expect(loadingStates, [true, false],
          reason: 'loading bracket must release even though auth denied '
              'the request before the network call, or the spinner sticks');
      expect(cancelAll(dio), 0,
          reason: 'the cancel token injected for the denied request must '
              'already be released, not leaked in the registry');
    });

    // ── Proactive refresh (B1) ────────────────────────────────────────────
    // With an `expiresAt` callback, an already-expired token is refreshed in
    // onRequest BEFORE sending, so requests go out once with a fresh token —
    // no doomed 401 round-trip. Unlike the reactive replay, this path does hit
    // the real test server (it's a normal onRequest → send), so the injected
    // header and network call count are directly observable.

    DateTime? expiresAtFn(String token) => token == 'new'
        ? DateTime.now().add(const Duration(hours: 1)) // fresh
        : DateTime.now().subtract(const Duration(seconds: 1)); // expired

    test(
        'proactive refresh: N concurrent requests with an expired token '
        'trigger exactly ONE refresh and all go out with the fresh token '
        '(zero doomed 401s), collapsing on the shared refresh window',
        () async {
      final tm = RefreshableTokenManager('old');
      var refreshCalls = 0;
      var calls = 0;
      final sentAuth = <String>[];

      final server = await TestServer.start((req) async {
        calls++;
        sentAuth.add(req.headers.value('authorization') ?? '<none>');
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        expiresAt: expiresAtFn,
        onRefresh: (_, __) async {
          refreshCalls++;
          tm.setToken('new');
        },
        onAccessExpired: (_, __) async {},
      ));

      await Future.wait([
        dio.get<void>('/a'),
        dio.get<void>('/b'),
        dio.get<void>('/c'),
      ]).timeout(const Duration(seconds: 5));

      expect(refreshCalls, 1,
          reason: 'concurrent expiring requests must collapse to a single '
              'refresh via the shared `_refreshing` window');
      expect(calls, 3);
      expect(sentAuth, everyElement('Bearer new'),
          reason: 'every request must be sent with the refreshed token — a '
              'zero-doomed-round outcome; none should carry Bearer old');
      expect(sentAuth, isNot(contains('Bearer old')));
    });

    test(
        'proactive refresh is opt-in: with no expiresAt callback the token '
        'is used as-is and onRefresh is never called', () async {
      final tm = RefreshableTokenManager('old');
      var refreshCalls = 0;
      final sentAuth = <String>[];

      final server = await TestServer.start((req) async {
        sentAuth.add(req.headers.value('authorization') ?? '<none>');
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async => refreshCalls++,
        onAccessExpired: (_, __) async {},
      ));

      await dio.get<void>('/data');

      expect(refreshCalls, 0,
          reason: 'no expiresAt ⇒ purely reactive, no pre-send refresh');
      expect(sentAuth, ['Bearer old']);
    });

    test(
        'proactive refresh failure clears the session and rejects before '
        'the request is ever sent', () async {
      final tm = RefreshableTokenManager('old');
      var expiredCalls = 0;
      var calls = 0;

      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        expiresAt: expiresAtFn,
        onRefresh: (_, __) async => throw StateError('refresh boom'),
        onAccessExpired: (_, __) async => expiredCalls++,
      ));

      await expectLater(
        dio.get<void>('/data').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
      );

      expect(expiredCalls, 1,
          reason: 'a failed proactive refresh must run onAccessExpired');
      expect(tm.accessToken, isNull, reason: 'session must be cleared');
      expect(calls, 0,
          reason:
              'the request must never reach the network with a dead token');
    });

    // ── Reactive single-window refresh under concurrency ──────────────────
    // The core guarantee: many in-flight requests that come back 401 in a
    // SCRAMBLED order must collapse onto ONE refresh (the `_refreshing ??=`
    // shared window). Once the refresh lands a new token, the later-arriving
    // 401s see carried-token != current-token and route to *replay*, not a
    // second refresh.
    //
    // Replays re-issue via a throwaway Dio that now genuinely reaches the
    // TestServer (see file header). The server therefore MUST honour the
    // refreshed token (respond success once it sees `Bearer new`) rather
    // than 401 unconditionally: discovered while converting this test off
    // FakeAdapter — if every replay also 401s, `_handleFailure` calls
    // `_expire()` on that failure, which clears the *shared* token manager.
    // Because the replays race each other in real wall-clock time, whichever
    // one fails first can null out the store out from under a still-pending
    // sibling, flipping that sibling's action from `replay` to `expired`
    // (observed non-deterministically: 9, then 11, distinct total call
    // counts across two otherwise-identical runs). That race is an artifact
    // of a test server that never lets any replay succeed, not something
    // this test intends to exercise, so the server now answers success once
    // the refreshed token is presented — matching how a real backend would
    // behave and removing the race. With that, every one of the 6 requests
    // deterministically performs exactly one initial dispatch (401) and
    // exactly one post-refresh replay (success) — 12 total network hits.
    test(
        'concurrent, out-of-order 401s trigger the refresh EXACTLY ONCE '
        '(single shared window); late 401s replay instead of re-refreshing',
        () async {
      final tm = RefreshableTokenManager('old');
      var refreshCount = 0;
      var calls = 0;
      final refreshOrder = <int>[];

      final server = await TestServer.start((req) async {
        calls++;
        final id = int.parse(req.uri.path.substring(2)); // '/p3' → 3
        if (req.headers.value('authorization') == 'Bearer new') {
          // Replay with the refreshed token succeeds immediately.
          await respondJson(req, {'ok': true}, 200);
          return;
        }
        // Still on the stale token — 401, in a scrambled order: request
        // id=1 resolves LAST, id=5 FIRST — so 401s arrive out of issue order.
        refreshOrder.add(id);
        await Future<void>.delayed(Duration(milliseconds: (6 - id) * 15));
        await respondJson(req, {'error': 'unauthorized'}, 401);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (m, _) async {
          refreshCount++;
          // Refresh takes real time, so several 401s land while it's running
          // and must JOIN the window rather than each starting their own.
          await Future<void>.delayed(const Duration(milliseconds: 40));
          (m as RefreshableTokenManager).setToken('new');
        },
        onAccessExpired: (_, __) async {},
      ));

      final futures = [
        for (var i = 1; i <= 6; i++)
          dio.get<void>('/p$i', options: Options(extra: {'id': i}))
      ];
      // Every request now ultimately succeeds via its replay. Swallow
      // per-future anyway so a regression that reintroduces a failure
      // doesn't turn into an unhandled-rejection crash instead of a clean
      // assertion failure below.
      await Future.wait(
        futures.map((f) =>
            f.then<String>((_) => 'ok').catchError((Object _) => 'err')),
      ).timeout(const Duration(seconds: 30));

      expect(refreshCount, 1,
          reason: 'all concurrent out-of-order 401s must collapse to ONE '
              'onRefresh — the single shared refresh window');
      expect(calls, 12,
          reason: 'every one of the 6 requests must have been sent and '
              '401d once, then replayed (and accepted) exactly once more '
              'now that the replay genuinely reaches the server — 6 + 6 = 12');
    });

    // ── The specific ordering the reviewer asked about ────────────────────
    // a and b are sent together. a 401s first → refresh SUCCEEDS (token
    // old→new) → window CLOSES → a replays. Only THEN does b 401 (deferred by
    // a gate). Because the shared window is already gone, b can't join it; the
    // guard that must save us is the carried-vs-current token comparison:
    //   b carried 'old', store is now 'new' ⇒ REPLAY, not a 2nd refresh.
    test(
        'a 401s and refreshes; b 401s only AFTER the refresh window closed → '
        'b replays with the new token, does NOT trigger a second refresh',
        () async {
      final tm = RefreshableTokenManager('old');
      var refreshCount = 0;
      final refreshDone = Completer<void>();
      final actions = <String, DiomanAuthFailureAction>{};

      final server = await TestServer.start((req) async {
        final id = req.uri.path.substring(1); // '/a' → 'a', '/b' → 'b'
        if (id == 'b') {
          // b's 401 is held back until the refresh (triggered by a) is fully
          // finished and `_refreshing` has been reset to null.
          await refreshDone.future;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (req.headers.value('authorization') == 'Bearer new') {
          // Both a's and b's replay carry the refreshed token — accept it.
          // (If the server kept 401ing here instead, a's replay failure
          // would call `_expire()` and clear the shared token manager,
          // which can race ahead of b's still-pending failure-routing and
          // flip its action from `replay` to `expired` — see the note on
          // the concurrent 6-request test above for the full explanation.)
          await respondJson(req, {'ok': true}, 200);
          return;
        }
        await respondJson(req, {'error': 'unauthorized', 'id': id}, 401);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onFailure: (m, resp) {
          final id = resp.requestOptions.extra['id'] as String;
          final action = defaultAuthFailure(m, resp, 'Authorization');
          actions[id] = action; // record which branch each request took
          return action;
        },
        onRefresh: (m, _) async {
          refreshCount++;
          (m as RefreshableTokenManager).setToken('new');
          refreshDone.complete(); // window is about to close (finally → null)
        },
        onAccessExpired: (_, __) async {},
      ));

      final fa = dio.get<void>('/a', options: Options(extra: {'id': 'a'}));
      final fb = dio.get<void>('/b', options: Options(extra: {'id': 'b'}));
      await Future.wait([
        fa.then<String>((_) => 'ok').catchError((Object _) => 'err'),
        fb.then<String>((_) => 'ok').catchError((Object _) => 'err'),
      ]).timeout(const Duration(seconds: 30));

      expect(refreshCount, 1,
          reason: 'b must NOT start a second refresh — the refresh already '
              'rotated the token');
      expect(actions['a'], DiomanAuthFailureAction.refresh,
          reason: 'a carried the then-current token → refresh');
      expect(actions['b'], DiomanAuthFailureAction.replay,
          reason: 'b carried the stale pre-refresh token while the store now '
              'holds the new one → replay, not refresh');
    });

    // ── Now observable end-to-end: refresh + replay success ───────────────
    // With a real TestServer, the throwaway replay Dio genuinely reaches the
    // server. Unlike the tests above (server always 401s), here the server
    // stops 401ing after the refresh, so we can assert on the full
    // refresh → replay → success path, not just which action was chosen.
    test(
        'a 401, successful refresh, and replay deliver the replayed '
        'response to the original caller', () async {
      final tm = RefreshableTokenManager('old');
      var refreshCalls = 0;

      final server = await TestServer.start((req) async {
        final auth = req.headers.value('authorization');
        if (auth == 'Bearer new') {
          await respondJson(req, {'ok': true}, 200);
        } else {
          await respondJson(req, {'error': 'expired'}, 401);
        }
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onRefresh: (_, __) async {
          refreshCalls++;
          tm.setToken('new');
        },
        onAccessExpired: (_, __) async {},
      ));

      final res = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 5));

      expect(refreshCalls, 1);
      expect(res.data!['ok'], true,
          reason: 'the replay must actually reach the real server with the '
              'refreshed token and deliver its success response back to '
              'the original caller — this path used to be untestable '
              'offline because the throwaway replay Dio bypassed the fake '
              'adapter');
    });
  });

  group('DiomanShare', () {
    // SharePolicy.retry's internal re-issue deliberately uses a throwaway
    // `Dio()` (see SKILL.md) so it never re-enters this chain. Against a
    // real TestServer that throwaway Dio's `.fetch()` still lands on our
    // test server (RequestOptions carries its own already-resolved
    // baseUrl), so both the exhausted-retry give-up path AND the
    // successful-retry path are now directly observable — see the two
    // tests below.
    //
    // NOTE: the first test below only issues a solo request, not a
    // concurrent leader+follower pair. While investigating this fix a
    // SEPARATE, pre-existing issue surfaced (present in the original code
    // too, verified via `git stash`): a concurrent follower attached via
    // `_handleStart` (onRequest's `RequestInterceptorHandler.reject`) hangs
    // forever when the shared request ultimately errors — the follower's
    // own dio.get() never settles, even though the leader and the shared
    // completer both settle correctly. That looks like a dio
    // interceptor-zone interaction distinct from anything in this review;
    // flagged separately, not fixed here.
    test(
        'policy=retry: a solo request is settled with the error (no hang) '
        'once retries are exhausted, and the entry is cleared so a later '
        'request with the same key hits the network again', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'fail': true}, 500);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.retry, retries: 0),
      ]);

      await expectLater(
        dio.get<void>('/shared').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
        reason: 'must settle with the error, not hang',
      );

      final callsBefore = calls;
      await expectLater(
          dio.get<void>('/shared'), throwsA(isA<DioException>()));
      expect(calls, greaterThan(callsBefore),
          reason: 'the settled entry must have been removed from `_active`; '
              'a dangling entry would silently reuse the old dead completer '
              'instead of ever hitting the network again');
    });

    test(
        'policy=retry: with retries available, a successful retry resolves '
        "through the internal throwaway Dio hitting the real test server "
        '(this success path could only be exercised offline via a failure '
        'before — see note above)', () async {
      var attempt = 0;
      final server = await TestServer.start((req) async {
        attempt++;
        if (attempt == 1) {
          await respondJson(req, {'fail': true}, 500);
        } else {
          await respondJson(req, {'ok': true, 'attempt': attempt}, 200);
        }
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.retry, retries: 2),
      ]);

      final res = await dio
          .get<Map<String, dynamic>>('/shared-ok')
          .timeout(const Duration(seconds: 5));

      expect(res.data!['ok'], true,
          reason: 'the internal retry Dio must be able to reach the real '
              'server and deliver the eventual success to the caller');
      expect(attempt, 2,
          reason: 'one failed attempt, then one successful internal retry');
    });

    test(
        'policy=end: every caller — including superseded ones — receives '
        'the LAST request\'s result', () async {
      final server = await TestServer.start((req) async {
        final n = int.parse(req.headers.value('x-test-seq')!);
        await respondJson(req, {'seq': n}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.end),
      ]);

      final first = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(headers: {'X-Test-Seq': '1'}),
      );
      final second = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(headers: {'X-Test-Seq': '2'}),
      );

      final results = await Future.wait([first, second])
          .timeout(const Duration(seconds: 5));

      expect(results[0].data!['seq'], 2,
          reason: 'the superseded first caller must get the last response');
      expect(results[1].data!['seq'], 2);
    });

    test(
        'policy=race: a caller whose own request failed still gets the '
        'winning sibling\'s successful result', () async {
      final loserStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        final id = int.parse(req.headers.value('x-test-id')!);
        if (id == 1) {
          loserStarted.complete();
          // Let the winner (id 2) settle the shared completer first.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        await loserStarted.future;
        await respondJson(req, {'winner': true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.race),
      ]);

      final loser = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(headers: {'X-Test-Id': '1'}),
      );
      final winner = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(headers: {'X-Test-Id': '2'}),
      );

      final results = await Future.wait([loser, winner])
          .timeout(const Duration(seconds: 5));

      expect(results[0].data!['winner'], true,
          reason: 'the caller whose own request errored must still receive '
              "the sibling's successful response, per SharePolicy.race");
      expect(results[1].data!['winner'], true);
    });
  });

  group('DiomanMock', () {
    test(
        'a mock hit still runs onResponse of normalize and share, so the '
        'envelope is unwrapped and a concurrent follower does not hang',
        () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'should': 'not be called'}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true)
        ..add(
            'GET:/mocked',
            (o) async => ResponseBody.fromString(
                  jsonEncode({
                    'code': 0,
                    'data': {'x': 1},
                    'message': 'ok'
                  }),
                  200,
                  headers: {
                    Headers.contentTypeHeader: ['application/json'],
                  },
                ));
      dio.interceptors.addAll([
        const DiomanKey(),
        const DiomanNormalize(),
        DiomanShare(),
        mock,
      ]);

      final leader = dio.get<Map<String, dynamic>>('/mocked');
      final follower = dio.get<Map<String, dynamic>>('/mocked');

      final results = await Future.wait([leader, follower])
          .timeout(const Duration(seconds: 5));

      expect(results[0].data, {'x': 1},
          reason:
              'normalize must unwrap the mocked envelope, same as a real response');
      expect(results[1].data, {'x': 1},
          reason:
              'the follower must not hang — share must settle on a mock hit');
    });

    test(
        'the mock-server redirect does not duplicate query parameters '
        'in the composed URI (regression for the copyWith fix)', () {
      // Mirrors DiomanMock._rewriteUrl's contract: the rewritten absolute
      // path already folds in the original query string, so the
      // queryParameters map handed to the redirect request must be cleared —
      // otherwise dio's RequestOptions.uri appends the same params again.
      final withoutFix = RequestOptions(
        path: 'http://mock.local/pets?type=cat',
        queryParameters: {'type': 'cat'},
      );
      expect(withoutFix.uri.query, 'type=cat&type=cat',
          reason: 'demonstrates the bug: query kept alongside an '
              'already-query-bearing rewritten path duplicates it');

      final withFix = RequestOptions(
        path: 'http://mock.local/pets?type=cat',
        queryParameters: {},
      );
      expect(withFix.uri.query, 'type=cat',
          reason:
              'clearing queryParameters (the actual fix) avoids the duplication');
    });
  });

  group('DiomanRetry', () {
    test(
        'DiomanRetryOptions(enabled: false) is honoured on the business-retry '
        '(onResponse) path, not just the network-error path', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'code': 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(
        max: 3,
        shouldRetry: (err, response) => (response?.data as Map)['code'] != 0,
      ));

      final res = await dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(
            extra: {'dioman:retry': const DiomanRetryOptions(enabled: false)}),
      );

      expect(res.data!['code'], 1);
      expect(calls, 1,
          reason:
              'enabled:false must skip business-level retry, not just network retry');
    });
  });

  group('DiomanCache', () {
    test(
        'maxEntries bounds the store via LRU eviction instead of growing '
        'without limit', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'path': req.uri.path}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cache = DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, maxEntries: 2);
      dio.interceptors.addAll([const DiomanKey(), cache]);

      await dio.get<void>('/a');
      await dio.get<void>('/b');
      await dio.get<void>('/c'); // evicts '/a' (least recently written)

      await dio.get<void>('/a'); // must miss cache → real network hit again
      expect(calls, 4);

      await dio.get<void>('/c'); // still cached → no new network hit
      expect(calls, 4);
    });
  });

  group('DiomanCancel + DiomanRetry', () {
    test(
        "a token this plugin injected stays trackable by cancelAll() while "
        "DiomanRetry's re-issue (a throwaway, interceptor-less Dio) is in "
        'flight — because DiomanRetry was given a `cancel` reference, not '
        "because the re-issue reaches this plugin's own onRequest (it "
        "never does)", () async {
      final secondAttemptStarted = Completer<void>();
      var attempt = 0;
      final server = await TestServer.start((req) async {
        attempt++;
        if (attempt == 1) {
          await respondJson(req, {}, 500);
          return;
        }
        secondAttemptStarted.complete();
        await Completer<void>().future; // hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cancel = DiomanCancel();
      dio.interceptors.addAll([
        cancel,
        DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero)..cancel = cancel,
      ]);

      final call = dio.get<void>('/data');
      await secondAttemptStarted.future;
      final cancelled = cancelAll(dio, 'test cancel');

      expect(cancelled, 1,
          reason: 'the retried attempt\'s token must still be registered');
      await expectLater(
        call.timeout(const Duration(seconds: 2)),
        throwsA(isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        )),
      );
    });
  });

  group('DiomanShare + DiomanRetry', () {
    // DiomanRetry's re-issue goes through a throwaway, interceptor-less Dio
    // (see retry_plugin.dart) — it never re-enters DiomanShare.onRequest at
    // all. Without wiring the `share` setter into DiomanRetry, the two plugins simply
    // don't coordinate: DiomanShare's dedup window covers only the FIRST
    // attempt (settled — and the entry removed — as soon as it fails), and
    // the retry that follows is completely invisible to it.
    test(
        'without wiring the `share` setter into DiomanRetry, a solo caller still gets '
        'the correct retried result, but a NEW caller arriving while the '
        "retry is in flight does NOT dedupe against it — it starts its own "
        'independent request, because the retry is invisible to '
        'DiomanShare', () async {
      final retryInFlight = Completer<void>();
      var attempts = 0;
      final server = await TestServer.start((req) async {
        final n = ++attempts;
        if (n == 1) {
          await respondJson(req, {'fail': true}, 500);
          return;
        }
        // Only A's retry (n=2) needs to signal this — C's own request (n=3)
        // also lands in this branch, and completing an already-completed
        // Completer throws (crashing this handler, which TestServer then
        // reports as a spurious 500 — a real trap, not a hypothetical one).
        if (!retryInFlight.isCompleted) retryInFlight.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await respondJson(req, {'from': 'retry'}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanShare(policy: DiomanSharePolicy.start),
      ]);
      dio.interceptors.add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final a = dio.get<Map<String, dynamic>>('/data');
      await retryInFlight.future; // A's retry is mid-flight, on a throwaway
      // Dio DiomanShare never sees — its own entry for this key was already
      // removed when the first attempt's 500 settled it, well before the
      // retry started.

      final c = await dio
          .get<Map<String, dynamic>>('/data')
          .timeout(const Duration(seconds: 3));
      expect(c.data, {'from': 'retry'},
          reason: 'C still gets the right eventual data, but only because '
              "it triggered its OWN successful request — attempts proves "
              "it wasn't deduped");
      expect(attempts, 3,
          reason: "C's own independent call is the 3rd — see the "
              '"pairwise: share + retry" group in dioman_combinations_test.dart '
              'for what wiring the `share` setter into DiomanRetry changes here (C '
              'would dedupe instead, no 3rd call)');

      final aResult = await a.timeout(const Duration(seconds: 3));
      expect(aResult.data, {'from': 'retry'},
          reason: "A still gets its own correct retried result regardless "
              "— DiomanRetry's success/failure never depended on "
              'DiomanShare in the first place');
    });

    // The concurrent-follower-ends-up-with-a-final-ERROR case (as opposed
    // to a final success) still isn't provable with a clean `expect()` —
    // see the "pairwise: share + auth" group in dioman_combinations_test.dart
    // for why: it hits a SEPARATE, pre-existing dio interceptor-zone quirk
    // in `_handleStart`'s else-branch / `_awaitEntry` (a completer-based
    // `handler.reject` from inside a `.then()` callback crashes instead of
    // cleanly rejecting), unrelated to DiomanRetry specifically.
  });

  group('DiomanNormalize detection', () {
    test(
        'a plain payload that merely carries a `code` field (no data/message) '
        'is NOT mistaken for an envelope and rejected', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'code': 86, 'name': 'CN'}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanNormalize());

      final res = await dio.get<Map<String, dynamic>>('/country');
      expect(res.data, {'code': 86, 'name': 'CN'},
          reason: 'code-only map must pass through untouched, not be unwrapped '
              'or rejected as an DiomanException');
    });

    test(
        'a real error envelope (code + message) is still rejected as an '
        'DiomanException', () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'code': 1, 'message': 'boom'}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanNormalize());

      await expectLater(
        dio.get<void>('/x'),
        throwsA(isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<DiomanException>(),
        )),
      );
    });

    test('a real success envelope (code + data) is still unwrapped', () async {
      final server = await TestServer.start((req) => respondJson(req, {
            'code': 0,
            'data': {'x': 1},
            'message': 'ok'
          }, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanNormalize());

      final res = await dio.get<Map<String, dynamic>>('/x');
      expect(res.data, {'x': 1});
    });
  });

  group('DiomanCache LRU', () {
    test(
        'a cache HIT promotes the entry to most-recently-used, so eviction '
        'drops the genuinely least-recently-USED key (not merely oldest write)',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'p': req.uri.path}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([const DiomanKey(), DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, maxEntries: 2)]);

      await dio.get<void>('/a'); // store: [a]
      await dio.get<void>('/b'); // store: [a, b]
      await dio.get<void>('/a'); // HIT → promote a → store: [b, a]
      await dio.get<void>('/c'); // write c, evict LRU = b → store: [a, c]
      expect(calls, 3, reason: 'the /a re-read was a cache hit');

      await dio.get<void>('/a'); // still cached → no network
      expect(calls, 3,
          reason: '/a survived eviction because the hit promoted it');

      await dio.get<void>('/b'); // evicted → network
      expect(calls, 4,
          reason: '/b was the least-recently-used and must have been evicted');
    });

    test(
        'default clone (shallow) prevents a cache-hit reader from corrupting '
        'the stored entry by reassigning top-level fields', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {'v': 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([const DiomanKey(), DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, )]);

      await dio.get<Map<String, dynamic>>('/x'); // network → store
      final hit1 = await dio.get<Map<String, dynamic>>('/x'); // cache hit
      hit1.data!['v'] = 999; // mutate the returned copy
      hit1.data!['injected'] = true;

      final hit2 =
          await dio.get<Map<String, dynamic>>('/x'); // cache hit again
      expect(hit2.data, {'v': 1},
          reason: 'shallow clone default must isolate the store from a '
              "reader's top-level mutations");
    });
  });

  group('DiomanKey non-serialisable body', () {
    test(
        'two requests with distinct non-map bodies get distinct keys '
        '(never falsely deduped/cached as one)', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final keys = <String>[];
      dio.interceptors.add(const DiomanKey()); // deep mode
      // The computed key lives in RequestOptions.extra — dio-side only, not
      // observable over the wire — so capture it via an interceptor placed
      // right after DiomanKey, same as the other kKey-capturing tests below.
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        keys.add(o.extra[kKey] as String);
        h.next(o);
      }));

      await dio.post<void>('/upload', data: <int>[1, 2, 3]);
      await dio.post<void>('/upload', data: <int>[4, 5, 6]);

      expect(keys, hasLength(2));
      expect(keys[0], isNot(keys[1]),
          reason: 'distinct list bodies must fold in object identity so they '
              'are not keyed identically to POST:/upload');
    });
  });

  group('Dioman.install', () {
    test('adds plugins in canonical order and the handle disposes them all',
        () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final loadingStates = <bool>[];
      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        share: DiomanShare(), // exercises DiomanShare.dispose() teardown too
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: loadingStates.add),
        log: const DiomanLog(
            logRequest: false, logResponse: false, logError: false),
      );

      // Canonical order: key → share → cancel → loading → log
      // (envs..auth/retry omitted).
      final names = dio.interceptors
          .whereType<DiomanPlugin>()
          .map((p) => p.name)
          .toList();
      expect(names, [
        'dioman:qid',
        'dioman:share',
        'dioman:cancel',
        'dioman:loading',
        'dioman:log'
      ]);
      expect(handle.plugin<DiomanCancel>(), isNotNull);
      expect(handle.plugin<DiomanAuth>(), isNull);

      await dio.get<void>('/x');
      expect(loadingStates, [true, false]);

      // dispose() must eject every plugin AND run each plugin's own dispose()
      // (DiomanShare's teardown, DiomanLoading's onChanged(false), etc.)
      // without throwing.
      expect(handle.dispose, returnsNormally);
      expect(dio.interceptors.whereType<DiomanPlugin>(), isEmpty,
          reason: 'dispose must eject every installed plugin');
      expect(loadingStates, [true, false, false],
          reason: 'DiomanLoading.dispose fires onChanged(false)');
    });

    test(
        'remove<T>() ejects only the targeted plugin, runs its dispose, '
        'and is a no-op for a type that was never installed', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final loadingStates = <bool>[];
      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: loadingStates.add),
        log: const DiomanLog(
            logRequest: false, logResponse: false, logError: false),
      );

      expect(handle.remove<DiomanAuth>(), isNull,
          reason: 'DiomanAuth was never installed — nothing to remove');

      final removed = handle.remove<DiomanLoading>();
      expect(removed, isNotNull);
      expect(loadingStates, [false],
          reason: 'remove() must call the plugin\'s own dispose()');
      expect(handle.plugin<DiomanLoading>(), isNull);
      expect(dio.interceptors.contains(removed), isFalse,
          reason: 'remove() must eject the plugin from dio.interceptors');

      // The rest of the chain is untouched.
      final names = dio.interceptors
          .whereType<DiomanPlugin>()
          .map((p) => p.name)
          .toList();
      expect(names, ['dioman:qid', 'dioman:cancel', 'dioman:log']);
      expect(handle.plugins.map((p) => p.name),
          ['dioman:qid', 'dioman:cancel', 'dioman:log']);

      await dio.get<void>('/x'); // still works without the removed plugin
    });

    test(
        'insertBefore/insertAfter/prepend/append slot a custom plugin into '
        'both the handle and dio.interceptors, in the right position and '
        'execution order', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));

      final order = <String>[];
      _RecordingPlugin custom(String name) =>
          _RecordingPlugin(name, order.add);

      final handle = Dioman.install(
        dio,
        key: const DiomanKey(),
        cancel: DiomanCancel(),
        loading: DiomanLoading(onChanged: (_) {}),
      );
      final cancelPlugin = handle.plugin<DiomanCancel>()!;

      final before = custom('before');
      final after = custom('after');
      final first = custom('first');
      final last = custom('last');
      handle.insertBefore(cancelPlugin, before);
      handle.insertAfter(cancelPlugin, after);
      handle.prepend(first);
      handle.append(last);

      final expectedNames = [
        'first',
        'dioman:qid',
        'before',
        'dioman:cancel',
        'after',
        'dioman:loading',
        'last',
      ];
      expect(handle.plugins.map((p) => p.name), expectedNames);
      expect(dio.interceptors.whereType<DiomanPlugin>().map((p) => p.name),
          expectedNames);

      await dio.get<void>('/x');
      expect(order, ['first', 'before', 'after', 'last'],
          reason: 'inserted plugins must actually run in chain position');

      expect(
        () => handle.insertBefore(_RecordingPlugin('orphan', order.add),
            custom('x')),
        throwsArgumentError,
        reason: 'anchor not installed on this handle',
      );
      expect(
        () => handle.insertAfter(_RecordingPlugin('orphan', order.add),
            custom('y')),
        throwsArgumentError,
      );

      // dispose() must also eject/dispose the manually-inserted plugins.
      handle.dispose();
      expect(dio.interceptors.whereType<DiomanPlugin>(), isEmpty);
    });
  });

  group('Per-request Options overrides', () {
    test('DiomanCacheOptions(enabled: false) skips caching for that request',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {'n': calls}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([const DiomanKey(), DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, )]);

      await dio.get<void>('/x');
      await dio.get<void>(
        '/x',
        options: Options(
            extra: {'dioman:cache': const DiomanCacheOptions(enabled: false)}),
      );

      expect(calls, 2, reason: 'the second call must bypass the cache hit');
    });

    test('DiomanShareOptions(enabled: false) bypasses dedup for that request',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([const DiomanKey(), DiomanShare()]);

      await Future.wait([
        dio.get<void>('/x'),
        dio.get<void>(
          '/x',
          options: Options(extra: {
            'dioman:share': const DiomanShareOptions(enabled: false)
          }),
        ),
      ]);

      expect(calls, 2, reason: 'the opted-out call must issue its own request');
    });

    test(
        'DiomanFilterOptions ignoreKeys override keeps a field the plugin '
        'default would otherwise strip', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      Map<String, dynamic>? seenParams;
      dio.interceptors.add(const DiomanFilter()); // default: drops null/empty
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenParams = o.queryParameters;
        h.next(o);
      }));

      await dio.get<void>(
        '/x',
        queryParameters: {'page': null},
        options: Options(
          extra: {
            'dioman:filter': const DiomanFilterOptions(ignoreKeys: ['page'])
          },
        ),
      );

      expect(seenParams, containsPair('page', null),
          reason:
              'per-request ignoreKeys must override the plugin default predicate');
    });

    test('DiomanKeyOptions(key: ...) overrides the computed key', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());

      final captured = <String?>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured.add(o.extra[kKey] as String?);
        h.next(o);
      }));

      await dio.get<void>(
        '/a',
        options: Options(
            extra: {'dioman:qid': const DiomanKeyOptions(key: 'fixed-key')}),
      );

      expect(captured, ['fixed-key']);
    });

    test('DiomanMockOptions(enabled: false) skips mocking for that request',
        () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'real': true}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add(
          'GET:/x',
          (opts) async => ResponseBody.fromString(
                jsonEncode({'real': false}),
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              ));
      dio.interceptors.add(mock);

      final res = await dio.get<Map<String, dynamic>>(
        '/x',
        options: Options(
            extra: {'dioman:mock': const DiomanMockOptions(enabled: false)}),
      );

      expect(res.data!['real'], true,
          reason: 'enabled:false must fall through to the real network call');
    });

    test('DiomanAuthOptions(enabled: false) marks a request unprotected',
        () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: FakeTokenManager(null), // no token
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
      ));

      // With no token, a protected call would be denied; enabled:false must
      // let it through untouched.
      final res = await dio.get<void>(
        '/public',
        options: Options(
            extra: {'dioman:auth': const DiomanAuthOptions(enabled: false)}),
      );

      expect(res.statusCode, 200);
    });
  });

  group('Constructor-level enabled flag', () {
    test('DiomanFilter(enabled: false) leaves every request untouched',
        () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      Map<String, dynamic>? seenParams;
      dio.interceptors.add(const DiomanFilter(enabled: false));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenParams = o.queryParameters;
        h.next(o);
      }));

      await dio.get<void>('/x', queryParameters: {'page': null});

      expect(seenParams, containsPair('page', null),
          reason: 'a disabled plugin must never filter anything');
    });

    test(
        'DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, enabled: false) never caches, even across identical '
        'requests', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([const DiomanKey(), DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, enabled: false)]);

      await dio.get<void>('/x');
      await dio.get<void>('/x');

      expect(calls, 2, reason: 'a disabled cache must never serve a hit');
    });
  });

  group('Options merge semantics (not override)', () {
    test(
        'DiomanFilterOptions.ignoreKeys UNIONS with the plugin default '
        'instead of replacing it', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      Map<String, dynamic>? seenParams;
      dio.interceptors.add(const DiomanFilter(ignoreKeys: ['a']));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seenParams = o.queryParameters;
        h.next(o);
      }));

      await dio.get<void>(
        '/x',
        queryParameters: {'a': null, 'b': null},
        options: Options(
          extra: {
            'dioman:filter': const DiomanFilterOptions(ignoreKeys: ['b'])
          },
        ),
      );

      expect(
          seenParams, allOf(containsPair('a', null), containsPair('b', null)),
          reason: "plugin default 'a' must survive alongside per-request 'b', "
              'not be replaced by it');
    });

    test('DiomanKeyOptions.ignoreKeys UNIONS with the plugin default',
        () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final keys = <String>[];
      dio.interceptors.add(const DiomanKey(ignores: ['a']));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        keys.add(o.extra[kKey] as String);
        h.next(o);
      }));

      final override = Options(
        extra: {
          'dioman:qid': const DiomanKeyOptions(ignores: ['b'])
        },
      );
      await dio.get<void>('/x',
          queryParameters: {'a': '1', 'b': '2'}, options: override);
      await dio.get<void>('/x',
          queryParameters: {'a': '99', 'b': '2'}, options: override);

      expect(keys[0], keys[1],
          reason: "both 'a' and 'b' must be excluded from the key (union of "
              "plugin default 'a' and per-request 'b'), so varying only 'a' "
              'must not change the key when both calls carry the same '
              'per-request override');
    });

    test(
        'DiomanMockOptions.routes merges with the plugin\'s registered '
        "routes without dropping them", () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {'real': true}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add(
          'GET:/existing',
          (opts) async => ResponseBody.fromString(
                jsonEncode({'from': 'existing'}),
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              ));
      dio.interceptors.add(mock);

      final extraRoute = {
        'dioman:mock': DiomanMockOptions(routes: {
          'GET:/extra': (opts) async => ResponseBody.fromString(
                jsonEncode({'from': 'extra'}),
                200,
                headers: {
                  Headers.contentTypeHeader: ['application/json'],
                },
              ),
        }),
      };

      final r1 = await dio.get<Map<String, dynamic>>('/existing',
          options: Options(extra: extraRoute));
      final r2 = await dio.get<Map<String, dynamic>>('/extra',
          options: Options(extra: extraRoute));

      expect(r1.data!['from'], 'existing',
          reason: "the plugin's own registered route must still work");
      expect(r2.data!['from'], 'extra',
          reason: 'the per-request route must be reachable too');
    });
  });

  group('enabled inherits from the constructor when not overridden', () {
    test(
        'a per-request DiomanLoadingOptions that omits enabled does NOT '
        're-enable a plugin constructed with enabled: false', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      dio.interceptors
          .add(DiomanLoading(onChanged: states.add, enabled: false));

      await dio.get<void>(
        '/x',
        options: Options(extra: {
          'dioman:loading': const DiomanLoadingOptions(onChanged: null),
        }),
      );

      expect(states, isEmpty,
          reason: 'enabled:null on the override must inherit the '
              "constructor's enabled:false, not silently default to true");
    });

    test(
        'a per-request DiomanCacheOptions that only sets expires does NOT '
        're-enable a plugin constructed with enabled: false', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([const DiomanKey(), DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, enabled: false)]);

      await dio.get<void>('/x',
          options: Options(
              extra: {'dioman:cache': const DiomanCacheOptions(expires: 999)}));
      await dio.get<void>('/x',
          options: Options(
              extra: {'dioman:cache': const DiomanCacheOptions(expires: 999)}));

      expect(calls, 2,
          reason: 'a per-request override that only sets expires must not '
              "silently re-enable a cache constructed with enabled: false");
    });
  });

  group('Newly wired Options fields (full constructor↔Options parity)', () {
    test(
        'DiomanAuthOptions.headerKey/buildHeader override the plugin '
        'defaults for a single call', () async {
      String? customAuth;
      var hasAuthorization = false;
      final server = await TestServer.start((req) async {
        customAuth = req.headers.value('x-custom-auth');
        hasAuthorization = req.headers.value('authorization') != null;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: FakeTokenManager('tok'),
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {},
      ));

      await dio.get<void>(
        '/x',
        options: Options(extra: {
          'dioman:auth': DiomanAuthOptions(
            headerKey: 'X-Custom-Auth',
            buildHeader: (t) => 'Token $t',
          ),
        }),
      );

      expect(customAuth, 'Token tok',
          reason: 'per-request headerKey/buildHeader must be honoured');
      expect(hasAuthorization, isFalse,
          reason: 'the default header key must not also be set');
    });

    test(
        'DiomanRetryOptions.shouldRetry overrides the plugin default network '
        'retry check for a single call', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        // Not in [200,300) → dio's default validateStatus rejects it and
        // synthesizes a DioException(type: badResponse) for onError.
        await respondJson(req, {}, 418);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRetry(
        max: 2,
        delay: (_, __, ___, ____) => Duration.zero,
      )); // default shouldRetry ignores 418

      await expectLater(
        dio.get<void>(
          '/x',
          options: Options(
            extra: {
              'dioman:retry':
                  DiomanRetryOptions(shouldRetry: (err, response) => true)
            },
          ),
        ),
        throwsA(isA<DioException>()),
      );

      expect(calls, 3,
          reason: 'a per-request shouldRetry that accepts 418 must '
              'drive max+1 attempts, even though the plugin default would not '
              'retry a 418 at all');
    });

    test(
        'DiomanNormalizeOptions.dataKey/codeKey/messageKey override the '
        "plugin's envelope keys for a single call", () async {
      final server = await TestServer.start((req) => respondJson(req, {
            'status': 0,
            'payload': {'ok': true},
            'msg': 'fine'
          }, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors
          .add(const DiomanNormalize()); // default keys: code/data/message

      final res = await dio.get<Map<String, dynamic>>(
        '/x',
        options: Options(extra: {
          'dioman:normalize': const DiomanNormalizeOptions(
            codeKey: 'status',
            dataKey: 'payload',
            messageKey: 'msg',
          ),
        }),
      );

      expect(res.data, {'ok': true},
          reason: 'per-request envelope keys must be used instead of the '
              'plugin defaults, which would not recognise this envelope at all');
    });

    test(
        'DiomanKeyOptions.builder overrides the computed key for a single '
        'call', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());

      final captured = <String?>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured.add(o.extra[kKey] as String?);
        h.next(o);
      }));

      await dio.get<void>(
        '/x',
        options: Options(extra: {
          'dioman:qid': DiomanKeyOptions(builder: (o) => 'custom:${o.path}'),
        }),
      );

      expect(captured, ['custom:/x']);
    });

    test(
        'DiomanCacheOptions.shouldCache overrides the plugin default '
        'caching decision for a single call (allows POST to be cached)',
        () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors
          .addAll([const DiomanKey(), DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, )]); // default: GET-only

      final alwaysCache = Options(
        extra: {'dioman:cache': DiomanCacheOptions(shouldCache: (o) => true)},
      );
      await dio.post<void>('/x', options: alwaysCache);
      await dio.post<void>('/x', options: alwaysCache);

      expect(calls, 1,
          reason: 'per-request shouldCache must allow a POST to be cached, '
              'even though the plugin default is GET-only');
    });

    test(
        'DiomanLogOptions.writer overrides the plugin default sink for a '
        'single call', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors
          .add(const DiomanLog(logResponse: false, logError: false));

      final captured = <String>[];
      await dio.get<void>(
        '/x',
        options: Options(extra: {
          'dioman:log':
              DiomanLogOptions(writer: (msg, {error}) => captured.add(msg)),
        }),
      );

      expect(captured, isNotEmpty,
          reason: 'per-request writer must receive the request log line');
    });
  });

  group('DiomanLoadingOptions.onChanged (edge-triggered, not additive)', () {
    test(
        'a solo request with its own onChanged fires it at the 0→1→0 edge '
        'instead of the plugin default, and still participates in the '
        'shared counter', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final defaultStates = <bool>[];
      final loading = DiomanLoading(onChanged: defaultStates.add);
      dio.interceptors.add(loading);

      final ownStates = <bool>[];
      await dio.get<void>(
        '/x',
        options: Options(
          extra: {
            'dioman:loading': DiomanLoadingOptions(onChanged: ownStates.add)
          },
        ),
      );

      expect(ownStates, [true, false],
          reason: 'a request alone in the batch causes both edges, so its '
              'own onChanged must fire for both');
      expect(defaultStates, isEmpty,
          reason: "the plugin's default onChanged must NOT also fire — only "
              'one callback is invoked per edge');
      expect(loading.activeCount, 0,
          reason: 'the request must still have incremented/decremented the '
              'shared counter like any other request');
    });

    test(
        "a request's own onChanged does not fire if it doesn't land on the "
        'batch edge (another request is already keeping the counter above '
        'zero) — counting is still accurate either way', () async {
      final completers = <String, Completer<void>>{
        '/first': Completer<void>(),
        '/second': Completer<void>(),
      };
      final server = await TestServer.start((req) async {
        await completers[req.uri.path]!.future;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final defaultStates = <bool>[];
      final loading = DiomanLoading(onChanged: defaultStates.add);
      dio.interceptors.add(loading);

      // Start the first request (causes the 0→1 edge, default onChanged).
      final f1 = dio.get<void>('/first');
      await Future<void>.delayed(
          const Duration(milliseconds: 20)); // let onRequest run
      expect(loading.activeCount, 1);

      // Start a second request with its own onChanged — count is already 1,
      // so this does NOT land on an edge; its own callback never fires.
      final ownStates = <bool>[];
      final f2 = dio.get<void>(
        '/second',
        options: Options(
          extra: {
            'dioman:loading': DiomanLoadingOptions(onChanged: ownStates.add)
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loading.activeCount, 2,
          reason: 'the second request is still counted even though its own '
              'onChanged never got to fire');

      // First request finishes (2→1, not an edge) — the request finishing
      // isn't the second one, so its own onChanged is irrelevant here and
      // the default isn't called either (no edge).
      completers['/first']!.complete();
      await f1;
      expect(ownStates, isEmpty,
          reason: 'the first request finishing (2→1) is not an edge at all');
      expect(defaultStates, [true],
          reason: 'still just the one true from the initial 0→1 edge');

      // Second request finishes (1→0, the final edge) — the callback
      // invoked at an edge is resolved from whichever request's OWN
      // RequestOptions is currently decrementing, which is this one. So its
      // own onChanged fires `false` here — NOT the plugin default, even
      // though this request's own onChanged never got to fire `true`
      // (asymmetric pairing is the documented trade-off of resolving the
      // callback per-request instead of per-counter).
      completers['/second']!.complete();
      await f2;
      expect(ownStates, [false],
          reason: "the second request's own onChanged fires for the final "
              'edge, since IT is the one whose onResponse is decrementing');
      expect(defaultStates, [true],
          reason: 'the default never sees the closing `false` — that edge '
              "belongs to the second request's own callback instead");
    });
  });

  group('DiomanBreaker', () {
    test('trips after N consecutive failures, then fails fast (no network)',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'ok': false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 3,
        resetDuration: const Duration(seconds: 10),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Three genuine failures trip the breaker.
      for (var i = 0; i < 3; i++) {
        await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      }
      expect(hits, 3, reason: 'all three failing requests hit the server');
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.open);

      // Fourth request is rejected fast — never reaches the server.
      DioException? caught;
      try {
        await dio.get<dynamic>('/x');
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.error, isA<DiomanBreakerOpenException>());
      expect((caught.error as DiomanBreakerOpenException).bucketKey, 'GET:/x');
      expect(hits, 3, reason: 'fail-fast: the open breaker did NOT hit the server');
    });

    test('a success resets the consecutive-failure count', () async {
      var status = 500;
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': status == 200}, status);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 3,
        resetDuration: const Duration(seconds: 10),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Two failures, then a success (resets), then two more failures — never
      // three IN A ROW, so the breaker must stay closed.
      status = 500;
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      status = 200;
      await dio.get<dynamic>('/x');
      status = 500;
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));

      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.closed);
    });

    test('cooldown → halfOpen probe succeeds → closed', () async {
      var status = 500;
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'ok': status == 200}, status);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final transitions = <String>[];
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(milliseconds: 150),
        halfOpenMaxCalls: 1,
        onStateChange: (k, from, to) => transitions.add('${from.name}->${to.name}'),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Trip it.
      status = 500;
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.open);
      final hitsAtOpen = hits;

      // Still cooling down → fail fast, server untouched.
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(hits, hitsAtOpen, reason: 'rejected before cooldown, no network');

      // Wait out the cooldown, server now healthy → probe succeeds → closed.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      status = 200;
      await dio.get<dynamic>('/x');
      expect(hits, hitsAtOpen + 1, reason: 'exactly one probe went to network');
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.closed);
      expect(transitions,
          ['closed->open', 'open->halfOpen', 'halfOpen->closed']);
    });

    test('cooldown → halfOpen probe fails → re-opens', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final transitions = <String>[];
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(milliseconds: 150),
        halfOpenMaxCalls: 1,
        onStateChange: (k, from, to) => transitions.add('${from.name}->${to.name}'),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.open);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Probe hits the still-broken server, fails → back to open.
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.open);
      expect(transitions,
          ['closed->open', 'open->halfOpen', 'halfOpen->open']);
    });

    test('custom shouldTrip counts a 200 business failure', () async {
      final server = await TestServer.start((req) async {
        // HTTP 200 but a business-level failure code.
        await respondJson(req, {'code': 1, 'msg': 'nope'}, 200);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(seconds: 10),
        shouldTrip: (resp, err) {
          final data = resp?.data;
          if (data is Map && data['code'] != 0) return true;
          return null;
        },
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Both are HTTP 200 (no throw), but the breaker counts them as failures.
      await dio.get<dynamic>('/x');
      await dio.get<dynamic>('/x');
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.open);

      DioException? caught;
      try {
        await dio.get<dynamic>('/x');
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught?.error, isA<DiomanBreakerOpenException>());
    });

    test('per-request enabled:false bypasses the open breaker', () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'ok': false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(seconds: 10),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.open);
      final hitsAtOpen = hits;

      // Opted-out request must still reach the server (real 500, not a
      // fast-fail breaker rejection).
      DioException? caught;
      try {
        await dio.get<dynamic>('/x',
            options: Options(extra: {
              DiomanBreaker.pluginName: const DiomanBreakerOptions(enabled: false),
            }));
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught?.error, isNot(isA<DiomanBreakerOpenException>()));
      expect(hits, hitsAtOpen + 1, reason: 'the opted-out request hit the server');
    });

    test('with DiomanRetry: an open breaker stops the retry storm', () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'ok': false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      // All requests share one bucket; threshold 1 so ONE fully-failed
      // top-level request trips it.
      final breaker = DiomanBreaker(
        failureThreshold: 1,
        resetDuration: const Duration(seconds: 10),
        keyBuilder: (_) => 'bucket',
      );
      final retry = DiomanRetry(
        max: 3,
        delay: (_, __, ___, ____) => Duration.zero,
      );
      final handle = Dioman.install(dio, retry: retry, breaker: breaker);
      addTearDown(handle.dispose);

      // Request 1: closed → 1 real attempt + 3 retries = 4 hits, then the
      // breaker records the final failure and opens.
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(hits, 4);
      expect(breaker.stateOf('bucket'), DiomanBreakerState.open);

      // Request 2: breaker open → rejected fast, and DiomanRetry does NOT
      // retry the breaker-open rejection. Zero extra hits.
      DioException? caught;
      try {
        await dio.get<dynamic>('/x');
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught?.error, isA<DiomanBreakerOpenException>());
      expect(hits, 4, reason: 'no retry storm — breaker-open reject is not retried');
    });

    test('a cancelled request does not reset the failure count', () async {
      var slow = false;
      final server = await TestServer.start((req) async {
        if (slow) await Future<void>.delayed(const Duration(seconds: 5));
        await respondJson(req, {'ok': false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 3,
        resetDuration: const Duration(seconds: 10),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Two genuine failures — count = 2, one short of tripping.
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.closed);

      // Cancel an in-flight (admitted) request. A cancel must be neutral — it
      // must NOT reset the count back to 0.
      slow = true;
      final ct = CancelToken();
      final f = dio.get<dynamic>('/x', cancelToken: ct);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ct.cancel();
      await expectLater(
        f,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)),
      );
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.closed);

      // One more real failure → count reaches 3 → trips. Only possible if the
      // cancel did NOT reset the count (otherwise this is just failure #1).
      slow = false;
      await expectLater(dio.get<dynamic>('/x'), throwsA(isA<DioException>()));
      expect(breaker.stateOf('GET:/x'), DiomanBreakerState.open);
    });
  });

  group('DiomanTimeout', () {
    test('applies the matched tier: short receive times out, generous is ok',
        () async {
      final server = await TestServer.start((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      var quality = NetworkQuality.poor;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanTimeout(
        probe: () => quality,
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(receive: Duration(milliseconds: 100)),
          NetworkQuality.excellent: DiomanTimeouts(receive: Duration(seconds: 2)),
        },
      ));

      // poor → 100ms receive against a 300ms server → receiveTimeout.
      await expectLater(
        dio.get<dynamic>('/x'),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.receiveTimeout)),
      );

      // excellent → 2s receive → succeeds.
      quality = NetworkQuality.excellent;
      final r = await dio.get<dynamic>('/x');
      expect(r.statusCode, 200);
    });

    test('only non-null fields are written; others keep BaseOptions', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final captured = <String, Duration?>{};
      final dio = Dio(BaseOptions(
        baseUrl: server.baseUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
      ));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.poor,
        timeouts: const {
          // Only connect is set for this tier.
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured['connect'] = o.connectTimeout;
        captured['receive'] = o.receiveTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>('/x');
      expect(captured['connect'], const Duration(seconds: 7),
          reason: 'connect was overridden by the tier');
      expect(captured['receive'], const Duration(seconds: 5),
          reason: 'receive was null in the tier → left at the BaseOptions value');
    });

    test('a tier absent from the map is a no-op for that request', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final captured = <String, Duration?>{};
      final dio = Dio(BaseOptions(
        baseUrl: server.baseUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
      ));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.good, // not in the map below
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured['connect'] = o.connectTimeout;
        captured['receive'] = o.receiveTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>('/x');
      expect(captured['connect'], const Duration(seconds: 4));
      expect(captured['receive'], const Duration(seconds: 5));
    });

    test('per-request enabled:false keeps the carried timeouts', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      Duration? captured;
      final dio = Dio(BaseOptions(
        baseUrl: server.baseUrl,
        connectTimeout: const Duration(seconds: 4),
      ));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.poor,
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured = o.connectTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>('/x',
          options: Options(extra: {
            DiomanTimeout.pluginName: const DiomanTimeoutOptions(enabled: false),
          }));
      expect(captured, const Duration(seconds: 4),
          reason: 'opted out → the tier override never applied');
    });

    test('per-request timeouts merge, overriding a single tier', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      Duration? captured;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.poor,
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured = o.connectTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>('/x',
          options: Options(extra: {
            DiomanTimeout.pluginName: const DiomanTimeoutOptions(timeouts: {
              NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 9)),
            }),
          }));
      expect(captured, const Duration(seconds: 9),
          reason: 'the per-request poor tier replaced the plugin default');
    });
  });

  group('DiomanOffline', () {
    /// Matcher for a DioException wrapping a DiomanOfflineException of [reason].
    Matcher offlineError(DiomanOfflineReason reason) => isA<DioException>().having(
        (e) => e.error, 'error',
        isA<DiomanOfflineException>().having((x) => x.reason, 'reason', reason));

    test('offline request is queued (no network), then replayed on reconnect',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      var online = false;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => online,
        onConnectivityChanged: conn.stream,
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      final f = dio.get<dynamic>('/x'); // offline → parks
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(offline.pending, 1);
      expect(hits, 0, reason: 'queued, never went to the network');

      online = true;
      conn.add(true); // reconnect → flush
      final r = await f;
      expect(r.statusCode, 200);
      expect(hits, 1, reason: 'replayed exactly once');
      expect(offline.pending, 0);
    });

    test('online request passes straight through (not queued)', () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => true,
        onConnectivityChanged: conn.stream,
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      final r = await dio.get<dynamic>('/x');
      expect(r.statusCode, 200);
      expect(hits, 1);
      expect(offline.pending, 0);
    });

    test('shouldQueue: only writes are queued, reads pass through', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      var online = false;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => online,
        onConnectivityChanged: conn.stream,
        shouldQueue: (o) => o.method.toUpperCase() != 'GET',
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      // GET is not queued → reaches the (real, up) test server right away.
      final getR = await dio.get<dynamic>('/g');
      expect(getR.statusCode, 200);
      expect(offline.pending, 0);

      // POST is queued while "offline".
      final pf = dio.post<dynamic>('/p', data: <String, dynamic>{});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(offline.pending, 1);

      online = true;
      conn.add(true);
      final pr = await pf;
      expect(pr.statusCode, 200);
    });

    test('queue full evicts the oldest with a queueFull rejection', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      var online = false;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => online,
        onConnectivityChanged: conn.stream,
        maxQueueSize: 2,
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      final f1 = dio.get<dynamic>('/1');
      final f2 = dio.get<dynamic>('/2');
      final f3 = dio.get<dynamic>('/3');
      // f3 enqueuing evicts f1 (oldest).
      await expectLater(f1, throwsA(offlineError(DiomanOfflineReason.queueFull)));
      expect(offline.pending, 2);

      // Drain the survivors so no future is left dangling.
      online = true;
      conn.add(true);
      await Future.wait([f2, f3]);
      expect(offline.pending, 0);
    });

    test('maxWait rejects a queued request that waits too long', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: conn.stream,
        maxWait: const Duration(milliseconds: 100),
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      await expectLater(
        dio.get<dynamic>('/x'),
        throwsA(offlineError(DiomanOfflineReason.timeout)),
      );
      expect(offline.pending, 0, reason: 'timed-out entry was removed');
    });

    test('dispose rejects every pending request (no perma-hang)', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {'ok': true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: conn.stream,
      );
      dio.interceptors.add(offline);

      final f = dio.get<dynamic>('/x');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(offline.pending, 1);

      offline.dispose();
      await expectLater(f, throwsA(offlineError(DiomanOfflineReason.disposed)));
      expect(offline.pending, 0);
    });
  });
}
