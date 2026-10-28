// ignore_for_file: avoid_relative_lib_imports
// 边界层：auth / concurrent
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/client.dart' show Tokens;
import '../../accept/lib/client.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  test(
      '[DiomanAuth.new(onAccessExpired)][DiomanAuth.new(onRefresh)] 刷新后仍为 401 的所有并发请求均返回稳定过期标识',
      () async {
    final server =
        await TestServer.start((r) => respondJson(r, {tkCode: 401}, 401));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final tm = Tokens()..replace(tkOld, tkRefresh);
    var expired = 0;
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              tm.replace(tkFresh2, 'next');
            },
            onAccessExpired: (_, __) async {
              expired++;
            }));
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await Future.wait(List.generate(8, (_) async {
      await expectLater(
          dio.get<dynamic>(tkPrivate),
          throwsA(isA<DioException>()
              .having((e) => e.message, '过期标识', contains('session expired'))));
    }));
    expect(expired, 1);
  });

  test(
      '[DiomanAuth.new(onAccessExpired)][DiomanAuth.new(onRefresh)] 同会话并发过期仅通知一次，重新登录后允许再次通知',
      () async {
    final server =
        await TestServer.start((r) async => respondJson(r, {tkCode: 401}, 401));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final tm = Tokens()..replace(tkOld, tkRefresh);
    var expired = 0;
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              throw StateError('invalid refresh');
            },
            onAccessExpired: (_, __) async {
              expired++;
            }));
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    for (var wave = 0; wave < 2; wave++) {
      if (wave > 0) tm.replace(tkNew, 'refresh-new');
      await Future.wait(List.generate(8, (_) async {
        await expectLater(
            dio.get<dynamic>(tkPrivate), throwsA(isA<DioException>()));
      }));
      expect(expired, wave + 1);
    }
  });

  group('DiomanAuth: additional realistic branches', () {
    test(
        '[DiomanAuthFailureAction.refresh][DiomanAuth.new(expiresAt)] a second request arriving while a FIRST request\'s proactive '
        'refresh is already in flight awaits the SAME refresh, and is '
        'rejected the same way when it fails', () async {
      final tm = TestTokens(tkT0);
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
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
          throw Exception(tkRefreshFailed);
        },
        onAccessExpired: (_, __) async {},
      ));

      final a = dio.get<void>(tkData2);
      // Calling an async onRefresh runs it synchronously up to its first
      // await, so by the time refreshStarted resolves, `_refreshing` is
      // already set — no timing guesswork needed for b to see it.
      await refreshStarted.future;
      final b = dio.get<void>(tkData2);
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
  });

  group(tkDiomanAuth, () {
// ── Proactive refresh (B1) ────────────────────────────────────────────
// With an `expiresAt` callback, an already-expired token is refreshed in
// onRequest BEFORE sending, so requests go out once with a fresh token —
// no doomed 401 round-trip. Unlike the reactive replay, this path does hit
// the real test server (it's a normal onRequest → send), so the injected
// header and network call count are directly observable.
    /// expiresAtFn 的测试辅助入口。
    DateTime? expiresAtFn(String token) => token == tkNew
        ? DateTime.now().add(const Duration(hours: 1)) // fresh
        : DateTime.now().subtract(const Duration(seconds: 1));
// expired
    test(
        '[DiomanAuthFailureAction.expired][DiomanAuthFailureAction.refresh] proactive refresh: N concurrent requests with an expired token '
        'trigger exactly ONE refresh and all go out with the fresh token '
        '(zero doomed 401s), collapsing on the shared refresh window',
        () async {
      final tm = TestTokens(tkOld);
      var refreshCalls = 0;
      var calls = 0;
      final sentAuth = <String>[];

      final server = await TestServer.start((req) async {
        calls++;
        sentAuth.add(req.headers.value(tkAuthorization2) ?? tkNone2);
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        expiresAt: expiresAtFn,
        onRefresh: (_, __) async {
          refreshCalls++;
          tm.setToken(tkNew);
        },
        onAccessExpired: (_, __) async {},
      ));

      await Future.wait([
        dio.get<void>(tkA3),
        dio.get<void>(tkB),
        dio.get<void>(tkC2),
      ]).timeout(const Duration(seconds: 5));

      expect(refreshCalls, 1,
          reason: 'concurrent expiring requests must collapse to a single '
              'refresh via the shared `_refreshing` window');
      expect(calls, 3);
      expect(sentAuth, everyElement(tkBearerNew),
          reason: 'every request must be sent with the refreshed token — a '
              'zero-doomed-round outcome; none should carry Bearer old');
      expect(sentAuth, isNot(contains(tkBearerOld)));
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
        '[DiomanAuthFailureAction.refresh][DiomanAuthFailureAction.replay] concurrent, out-of-order 401s trigger the refresh EXACTLY ONCE '
        '(single shared window); late 401s replay instead of re-refreshing',
        () async {
      final tm = TestTokens(tkOld);
      var refreshCount = 0;
      var calls = 0;
      final refreshOrder = <int>[];

      final server = await TestServer.start((req) async {
        calls++;
        final id = int.parse(req.uri.path.substring(2)); // '/p3' → 3
        if (req.headers.value(tkAuthorization2) == tkBearerNew) {
          // Replay with the refreshed token succeeds immediately.
          await respondJson(req, {tkOk: true}, 200);
          return;
        }
        // Still on the stale token — 401, in a scrambled order: request
        // id=1 resolves LAST, id=5 FIRST — so 401s arrive out of issue order.
        refreshOrder.add(id);
        await Future<void>.delayed(Duration(milliseconds: (6 - id) * 15));
        await respondJson(req, {tkError: tkUnauthorized}, 401);
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
          (m as TestTokens).setToken(tkNew);
        },
        onAccessExpired: (_, __) async {},
      ));

      final futures = [
        for (var i = 1; i <= 6; i++)
          dio.get<void>('/p$i', options: Options(extra: {tkId: i}))
      ];
      // Every request now ultimately succeeds via its replay. Swallow
      // per-future anyway so a regression that reintroduces a failure
      // doesn't turn into an unhandled-rejection crash instead of a clean
      // assertion failure below.
      await Future.wait(
        futures.map(
            (f) => f.then<String>((_) => tkOk).catchError((Object _) => tkErr)),
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
        '[DiomanAuthFailureAction.refresh][DiomanAuth.new(onAccessExpired)] a 401s and refreshes; b 401s only AFTER the refresh window closed → '
        'b replays with the new token, does NOT trigger a second refresh',
        () async {
      final tm = TestTokens(tkOld);
      var refreshCount = 0;
      final refreshDone = Completer<void>();
      final actions = <String, DiomanAuthFailureAction>{};

      final server = await TestServer.start((req) async {
        final id = req.uri.path.substring(1); // '/a' → 'a', '/b' → 'b'
        if (id == tkB2) {
          // b's 401 is held back until the refresh (triggered by a) is fully
          // finished and `_refreshing` has been reset to null.
          await refreshDone.future;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (req.headers.value(tkAuthorization2) == tkBearerNew) {
          // Both a's and b's replay carry the refreshed token — accept it.
          // (If the server kept 401ing here instead, a's replay failure
          // would call `_expire()` and clear the shared token manager,
          // which can race ahead of b's still-pending failure-routing and
          // flip its action from `replay` to `expired` — see the note on
          // the concurrent 6-request test above for the full explanation.)
          await respondJson(req, {tkOk: true}, 200);
          return;
        }
        await respondJson(req, {tkError: tkUnauthorized, tkId: id}, 401);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanAuth(
        tokenManager: tm,
        onFailure: (m, resp) {
          final id = resp.requestOptions.extra[tkId] as String;
          final action = defaultAuthFailure(m, resp, tkAuthorization);
          actions[id] = action; // record which branch each request took
          return action;
        },
        onRefresh: (m, _) async {
          refreshCount++;
          (m as TestTokens).setToken(tkNew);
          refreshDone.complete(); // window is about to close (finally → null)
        },
        onAccessExpired: (_, __) async {},
      ));

      final fa = dio.get<void>(tkA3, options: Options(extra: {tkId: tkA2}));
      final fb = dio.get<void>(tkB, options: Options(extra: {tkId: tkB2}));
      await Future.wait([
        fa.then<String>((_) => tkOk).catchError((Object _) => tkErr),
        fb.then<String>((_) => tkOk).catchError((Object _) => tkErr),
      ]).timeout(const Duration(seconds: 30));

      expect(refreshCount, 1,
          reason: 'b must NOT start a second refresh — the refresh already '
              'rotated the token');
      expect(actions[tkA2], DiomanAuthFailureAction.refresh,
          reason: 'a carried the then-current token → refresh');
      expect(actions[tkB2], DiomanAuthFailureAction.replay,
          reason: 'b carried the stale pre-refresh token while the store now '
              'holds the new one → replay, not refresh');
    });
  });
}
