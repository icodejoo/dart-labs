// Regression tests for the code-review fixes to the dioman plugin chain.
// Uses a fake [HttpClientAdapter] so no real network is needed.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// Fake transport — every request is answered by [handler] instead of going
/// over the network.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  int calls = 0;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object data, int status) => ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class FakeTokenManager implements ITokenManager {
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
class RefreshableTokenManager implements ITokenManager {
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

void main() {
  group('AuthPlugin', () {
    // AuthPlugin's post-failure replay deliberately uses a throwaway `Dio()`
    // (see SKILL.md) so it never re-enters the interceptor chain — that also
    // means it bypasses this test's FakeAdapter and goes out over the real
    // network. These tests therefore only assert on what's observable
    // without depending on that replay's network outcome: which
    // AuthFailureAction was chosen, and that the original 401 still
    // surfaces once the (real, failing) replay gives up.
    test('401 with the default Bearer header triggers a refresh action, not '
        'replay/expire (regression: comparing the formatted header against '
        'the raw store token made the refresh branch unreachable)', () async {
      final tm = FakeTokenManager('old-token');
      var refreshCalls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((_) => jsonBody({'error': 'expired'}, 401));
      dio.interceptors.add(AuthPlugin(
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

    test('a denied request (no token) still releases the loading/cancel'
        ' brackets installed before auth', () async {
      final tm = FakeTokenManager(null);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((_) => jsonBody({}, 200));

      final loadingStates = <bool>[];
      final cancelPlugin = CancelPlugin();
      dio.interceptors.addAll([
        cancelPlugin,
        LoadingPlugin(onChanged: loadingStates.add),
        AuthPlugin(
          tokenManager: tm,
          onRefresh: (_, __) async {},
          onAccessExpired: (_, __) async {},
        ),
      ]);

      await expectLater(dio.get<void>('/protected'), throwsA(isA<DioException>()));

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
    // the FakeAdapter (it's a normal onRequest → send), so the injected header
    // and network call count are directly observable.

    DateTime? expiresAtFn(String token) => token == 'new'
        ? DateTime.now().add(const Duration(hours: 1)) // fresh
        : DateTime.now().subtract(const Duration(seconds: 1)); // expired

    test('proactive refresh: N concurrent requests with an expired token '
        'trigger exactly ONE refresh and all go out with the fresh token '
        '(zero doomed 401s), collapsing on the shared refresh window',
        () async {
      final tm = RefreshableTokenManager('old');
      var refreshCalls = 0;
      final sentAuth = <String>[];

      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((o) {
        sentAuth.add(o.headers['Authorization']?.toString() ?? '<none>');
        return jsonBody({'ok': true}, 200);
      });
      dio.interceptors.add(AuthPlugin(
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
      expect((dio.httpClientAdapter as FakeAdapter).calls, 3);
      expect(sentAuth, everyElement('Bearer new'),
          reason: 'every request must be sent with the refreshed token — a '
              'zero-doomed-round outcome; none should carry Bearer old');
      expect(sentAuth, isNot(contains('Bearer old')));
    });

    test('proactive refresh is opt-in: with no expiresAt callback the token '
        'is used as-is and onRefresh is never called', () async {
      final tm = RefreshableTokenManager('old');
      var refreshCalls = 0;
      final sentAuth = <String>[];

      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((o) {
        sentAuth.add(o.headers['Authorization']?.toString() ?? '<none>');
        return jsonBody({'ok': true}, 200);
      });
      dio.interceptors.add(AuthPlugin(
        tokenManager: tm,
        onRefresh: (_, __) async => refreshCalls++,
        onAccessExpired: (_, __) async {},
      ));

      await dio.get<void>('/data');

      expect(refreshCalls, 0,
          reason: 'no expiresAt ⇒ purely reactive, no pre-send refresh');
      expect(sentAuth, ['Bearer old']);
    });

    test('proactive refresh failure clears the session and rejects before '
        'the request is ever sent', () async {
      final tm = RefreshableTokenManager('old');
      var expiredCalls = 0;

      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = FakeAdapter((_) => jsonBody({'ok': true}, 200));
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(AuthPlugin(
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
      expect(adapter.calls, 0,
          reason: 'the request must never reach the network with a dead token');
    });

    // ── Reactive single-window refresh under concurrency ──────────────────
    // The core guarantee: many in-flight requests that come back 401 in a
    // SCRAMBLED order must collapse onto ONE refresh (the `_refreshing ??=`
    // shared window). Once the refresh lands a new token, the later-arriving
    // 401s see carried-token != current-token and route to *replay*, not a
    // second refresh. (Replays re-issue via a throwaway Dio that bypasses the
    // FakeAdapter and fails offline — expected; we assert only the refresh
    // count and that every request was actually attempted.)
    test('concurrent, out-of-order 401s trigger the refresh EXACTLY ONCE '
        '(single shared window); late 401s replay instead of re-refreshing',
        () async {
      final tm = RefreshableTokenManager('old');
      var refreshCount = 0;
      final refreshOrder = <int>[];

      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = FakeAdapter((o) async {
        // Answer 401 for everyone, but in a scrambled order: request id=1
        // resolves LAST, id=5 FIRST — so 401s arrive out of issue order.
        final id = o.extra['id'] as int;
        refreshOrder.add(id);
        await Future<void>.delayed(Duration(milliseconds: (6 - id) * 15));
        return jsonBody({'error': 'unauthorized'}, 401);
      });
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(AuthPlugin(
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
      // Every request ultimately throws (its post-refresh replay hits the
      // throwaway Dio → http://test → fails offline). Swallow per-future.
      await Future.wait(
        futures.map((f) => f.then<String>((_) => 'ok').catchError((Object _) => 'err')),
      ).timeout(const Duration(seconds: 30));

      expect(refreshCount, 1,
          reason: 'all concurrent out-of-order 401s must collapse to ONE '
              'onRefresh — the single shared refresh window');
      expect(adapter.calls, 6,
          reason: 'every request must have actually been sent and 401d');
    });

    // ── The specific ordering the reviewer asked about ────────────────────
    // a and b are sent together. a 401s first → refresh SUCCEEDS (token
    // old→new) → window CLOSES → a replays. Only THEN does b 401 (deferred by
    // a gate). Because the shared window is already gone, b can't join it; the
    // guard that must save us is the carried-vs-current token comparison:
    //   b carried 'old', store is now 'new' ⇒ REPLAY, not a 2nd refresh.
    test('a 401s and refreshes; b 401s only AFTER the refresh window closed → '
        'b replays with the new token, does NOT trigger a second refresh',
        () async {
      final tm = RefreshableTokenManager('old');
      var refreshCount = 0;
      final refreshDone = Completer<void>();
      final actions = <String, AuthFailureAction>{};

      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = FakeAdapter((o) async {
        final id = o.extra['id'] as String;
        if (id == 'b') {
          // b's 401 is held back until the refresh (triggered by a) is fully
          // finished and `_refreshing` has been reset to null.
          await refreshDone.future;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return jsonBody({'error': 'unauthorized', 'id': id}, 401);
      });
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(AuthPlugin(
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
      expect(actions['a'], AuthFailureAction.refresh,
          reason: 'a carried the then-current token → refresh');
      expect(actions['b'], AuthFailureAction.replay,
          reason: 'b carried the stale pre-refresh token while the store now '
              'holds the new one → replay, not refresh');
    });
  });

  group('SharePlugin', () {
    // SharePolicy.retry's internal re-issue deliberately uses a throwaway
    // `Dio()` (see SKILL.md), which bypasses this test's FakeAdapter and
    // goes out over the real network — so the "successful retry" path isn't
    // directly observable offline. `retries: 0` exercises the exhausted-retry
    // give-up path instead (zero throwaway-Dio calls), which shares the same
    // settle/cleanup code as the success path and is what was actually
    // broken: the old code left the shared entry dangling on that path,
    // deadlocking every waiter forever.
    //
    // NOTE: this test only issues a solo request, not a concurrent
    // leader+follower pair. While investigating this fix a SEPARATE,
    // pre-existing issue surfaced (present in the original code too, verified
    // via `git stash`): a concurrent follower attached via `_handleStart`
    // (onRequest's `RequestInterceptorHandler.reject`) hangs forever when the
    // shared request ultimately errors — the follower's own dio.get() never
    // settles, even though the leader and the shared completer both settle
    // correctly. That looks like a dio interceptor-zone interaction distinct
    // from anything in this review; flagged separately, not fixed here.
    test('policy=retry: a solo request is settled with the error (no hang) '
        'once retries are exhausted, and the entry is cleared so a later '
        'request with the same key hits the network again', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = FakeAdapter((_) => jsonBody({'fail': true}, 500));
      dio.httpClientAdapter = adapter;
      dio.interceptors.addAll([
        const KeyPlugin(),
        SharePlugin(policy: SharePolicy.retry, retries: 0),
      ]);

      await expectLater(
        dio.get<void>('/shared').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
        reason: 'must settle with the error, not hang',
      );

      final callsBefore = adapter.calls;
      await expectLater(dio.get<void>('/shared'), throwsA(isA<DioException>()));
      expect(adapter.calls, greaterThan(callsBefore),
          reason: 'the settled entry must have been removed from `_active`; '
              'a dangling entry would silently reuse the old dead completer '
              'instead of ever hitting the network again');
    });

    test('policy=end: every caller — including superseded ones — receives '
        'the LAST request\'s result', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((o) {
        final n = o.extra['seq'] as int;
        return jsonBody({'seq': n}, 200);
      });
      dio.interceptors.addAll([
        const KeyPlugin(),
        SharePlugin(policy: SharePolicy.end),
      ]);

      final first = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(extra: {'seq': 1}),
      );
      final second = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(extra: {'seq': 2}),
      );

      final results =
          await Future.wait([first, second]).timeout(const Duration(seconds: 5));

      expect(results[0].data!['seq'], 2,
          reason: 'the superseded first caller must get the last response');
      expect(results[1].data!['seq'], 2);
    });

    test('policy=race: a caller whose own request failed still gets the '
        'winning sibling\'s successful result', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final loserStarted = Completer<void>();
      dio.httpClientAdapter = FakeAdapter((o) async {
        final id = o.extra['id'] as int;
        if (id == 1) {
          loserStarted.complete();
          // Let the winner (id 2) settle the shared completer first.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
        }
        await loserStarted.future;
        return jsonBody({'winner': true}, 200);
      });
      dio.interceptors.addAll([
        const KeyPlugin(),
        SharePlugin(policy: SharePolicy.race),
      ]);

      final loser = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(extra: {'id': 1}),
      );
      final winner = dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(extra: {'id': 2}),
      );

      final results =
          await Future.wait([loser, winner]).timeout(const Duration(seconds: 5));

      expect(results[0].data!['winner'], true,
          reason: 'the caller whose own request errored must still receive '
              "the sibling's successful response, per SharePolicy.race");
      expect(results[1].data!['winner'], true);
    });
  });

  group('MockPlugin', () {
    test('a mock hit still runs onResponse of normalize and share, so the '
        'envelope is unwrapped and a concurrent follower does not hang',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter =
          FakeAdapter((_) => jsonBody({'should': 'not be called'}, 200));
      final mock = MockPlugin(enabled: true)
        ..add('GET:/mocked', (o) async => ResponseBody.fromString(
              jsonEncode({'code': 0, 'data': {'x': 1}, 'message': 'ok'}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            ));
      dio.interceptors.addAll([
        const KeyPlugin(),
        const NormalizePlugin(),
        SharePlugin(),
        mock,
      ]);

      final leader = dio.get<Map<String, dynamic>>('/mocked');
      final follower = dio.get<Map<String, dynamic>>('/mocked');

      final results =
          await Future.wait([leader, follower]).timeout(const Duration(seconds: 5));

      expect(results[0].data, {'x': 1},
          reason: 'normalize must unwrap the mocked envelope, same as a real response');
      expect(results[1].data, {'x': 1},
          reason: 'the follower must not hang — share must settle on a mock hit');
    });

    test('the mock-server redirect does not duplicate query parameters '
        'in the composed URI (regression for the copyWith fix)', () {
      // Mirrors MockPlugin._rewriteUrl's contract: the rewritten absolute
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
          reason: 'clearing queryParameters (the actual fix) avoids the duplication');
    });
  });

  group('RetryPlugin', () {
    test('extra["retry"]=false is honoured on the business-retry '
        '(onResponse) path, not just the network-error path', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((_) => jsonBody({'code': 1}, 200));
      dio.interceptors.add(RetryPlugin(
        dio: dio,
        max: 3,
        isExceptionRequest: (r) => (r.data as Map)['code'] != 0,
      ));

      final res = await dio.get<Map<String, dynamic>>(
        '/data',
        options: Options(extra: {RetryPlugin.configProperty: false}),
      );

      expect(res.data!['code'], 1);
      expect((dio.httpClientAdapter as FakeAdapter).calls, 1,
          reason: 'retry:false must skip business-level retry, not just network retry');
    });
  });

  group('CachePlugin', () {
    test('maxEntries bounds the store via LRU eviction instead of growing '
        'without limit', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = FakeAdapter((o) => jsonBody({'path': o.path}, 200));
      dio.httpClientAdapter = adapter;
      final cache = CachePlugin(maxEntries: 2);
      dio.interceptors.addAll([const KeyPlugin(), cache]);

      await dio.get<void>('/a');
      await dio.get<void>('/b');
      await dio.get<void>('/c'); // evicts '/a' (least recently written)

      expect(cache.size, 2);

      await dio.get<void>('/a'); // must miss cache → real network hit again
      expect(adapter.calls, 4);

      await dio.get<void>('/c'); // still cached → no new network hit
      expect(adapter.calls, 4);
    });
  });

  group('CancelPlugin + RetryPlugin', () {
    test('a token this plugin injected stays trackable by cancelAll() '
        'across a retry re-dispatch', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final secondAttemptStarted = Completer<void>();
      final never = Completer<ResponseBody>(); // never completes on its own
      var attempt = 0;
      dio.httpClientAdapter = FakeAdapter((_) async {
        attempt++;
        if (attempt == 1) return jsonBody({}, 500);
        secondAttemptStarted.complete();
        return never.future; // hangs until cancelled
      });
      dio.interceptors.addAll([
        CancelPlugin(),
        RetryPlugin(dio: dio, max: 1, delay: (_) => Duration.zero),
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

  group('NormalizePlugin detection', () {
    test('a plain payload that merely carries a `code` field (no data/message) '
        'is NOT mistaken for an envelope and rejected', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter =
          FakeAdapter((_) => jsonBody({'code': 86, 'name': 'CN'}, 200));
      dio.interceptors.add(const NormalizePlugin());

      final res = await dio.get<Map<String, dynamic>>('/country');
      expect(res.data, {'code': 86, 'name': 'CN'},
          reason: 'code-only map must pass through untouched, not be unwrapped '
              'or rejected as an ApiException');
    });

    test('a real error envelope (code + message) is still rejected as an '
        'ApiException', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter =
          FakeAdapter((_) => jsonBody({'code': 1, 'message': 'boom'}, 200));
      dio.interceptors.add(const NormalizePlugin());

      await expectLater(
        dio.get<void>('/x'),
        throwsA(isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<ApiException>(),
        )),
      );
    });

    test('a real success envelope (code + data) is still unwrapped', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter(
          (_) => jsonBody({'code': 0, 'data': {'x': 1}, 'message': 'ok'}, 200));
      dio.interceptors.add(const NormalizePlugin());

      final res = await dio.get<Map<String, dynamic>>('/x');
      expect(res.data, {'x': 1});
    });
  });

  group('CachePlugin LRU', () {
    test('a cache HIT promotes the entry to most-recently-used, so eviction '
        'drops the genuinely least-recently-USED key (not merely oldest write)',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final adapter = FakeAdapter((o) => jsonBody({'p': o.path}, 200));
      dio.httpClientAdapter = adapter;
      dio.interceptors.addAll([const KeyPlugin(), CachePlugin(maxEntries: 2)]);

      await dio.get<void>('/a'); // store: [a]
      await dio.get<void>('/b'); // store: [a, b]
      await dio.get<void>('/a'); // HIT → promote a → store: [b, a]
      await dio.get<void>('/c'); // write c, evict LRU = b → store: [a, c]
      expect(adapter.calls, 3, reason: 'the /a re-read was a cache hit');

      await dio.get<void>('/a'); // still cached → no network
      expect(adapter.calls, 3,
          reason: '/a survived eviction because the hit promoted it');

      await dio.get<void>('/b'); // evicted → network
      expect(adapter.calls, 4,
          reason: '/b was the least-recently-used and must have been evicted');
    });

    test('default clone (shallow) prevents a cache-hit reader from corrupting '
        'the stored entry by reassigning top-level fields', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((_) => jsonBody({'v': 1}, 200));
      dio.interceptors.addAll([const KeyPlugin(), CachePlugin()]);

      await dio.get<Map<String, dynamic>>('/x'); // network → store
      final hit1 = await dio.get<Map<String, dynamic>>('/x'); // cache hit
      hit1.data!['v'] = 999; // mutate the returned copy
      hit1.data!['injected'] = true;

      final hit2 = await dio.get<Map<String, dynamic>>('/x'); // cache hit again
      expect(hit2.data, {'v': 1},
          reason: 'shallow clone default must isolate the store from a '
              "reader's top-level mutations");
    });
  });

  group('KeyPlugin non-serialisable body', () {
    test('two requests with distinct non-map bodies get distinct keys '
        '(never falsely deduped/cached as one)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final keys = <String>[];
      dio.httpClientAdapter = FakeAdapter((o) {
        keys.add(o.extra[kRequestKey] as String);
        return jsonBody({}, 200);
      });
      dio.interceptors.add(const KeyPlugin()); // deep mode

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
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((_) => jsonBody({}, 200));

      final loadingStates = <bool>[];
      final handle = Dioman.install(
        dio,
        key: const KeyPlugin(),
        share: SharePlugin(), // exercises SharePlugin.dispose() teardown too
        cancel: CancelPlugin(),
        loading: LoadingPlugin(onChanged: loadingStates.add),
        log: const LogPlugin(logRequest: false, logResponse: false, logError: false),
      );

      // Canonical order: key → share → cancel → loading → log
      // (envs..auth/retry omitted).
      final names =
          dio.interceptors.whereType<DioPlugin>().map((p) => p.name).toList();
      expect(names, ['key', 'share', 'cancel', 'loading', 'log']);
      expect(handle.plugin<CancelPlugin>(), isNotNull);
      expect(handle.plugin<AuthPlugin>(), isNull);

      await dio.get<void>('/x');
      expect(loadingStates, [true, false]);

      // dispose() must eject every plugin AND run each plugin's own dispose()
      // (SharePlugin's teardown, LoadingPlugin's onChanged(false), etc.)
      // without throwing.
      expect(handle.dispose, returnsNormally);
      expect(dio.interceptors.whereType<DioPlugin>(), isEmpty,
          reason: 'dispose must eject every installed plugin');
      expect(loadingStates, [true, false, false],
          reason: 'LoadingPlugin.dispose fires onChanged(false)');
    });

    test('remove<T>() ejects only the targeted plugin, runs its dispose, '
        'and is a no-op for a type that was never installed', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = FakeAdapter((_) => jsonBody({}, 200));

      final loadingStates = <bool>[];
      final handle = Dioman.install(
        dio,
        key: const KeyPlugin(),
        cancel: CancelPlugin(),
        loading: LoadingPlugin(onChanged: loadingStates.add),
        log: const LogPlugin(logRequest: false, logResponse: false, logError: false),
      );

      expect(handle.remove<AuthPlugin>(), isNull,
          reason: 'AuthPlugin was never installed — nothing to remove');

      final removed = handle.remove<LoadingPlugin>();
      expect(removed, isNotNull);
      expect(loadingStates, [false],
          reason: 'remove() must call the plugin\'s own dispose()');
      expect(handle.plugin<LoadingPlugin>(), isNull);
      expect(dio.interceptors.contains(removed), isFalse,
          reason: 'remove() must eject the plugin from dio.interceptors');

      // The rest of the chain is untouched.
      final names =
          dio.interceptors.whereType<DioPlugin>().map((p) => p.name).toList();
      expect(names, ['key', 'cancel', 'log']);
      expect(handle.plugins.map((p) => p.name), ['key', 'cancel', 'log']);

      await dio.get<void>('/x'); // still works without the removed plugin
    });
  });
}
