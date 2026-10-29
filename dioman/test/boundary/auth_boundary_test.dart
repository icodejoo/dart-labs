import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b3_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 验证刷新窗口与异步回调期间的会话边界。
void main() {
  test(
      '[DiomanAuth.readyStableAttempts][RequestPatch.headers]'
      '[DiomanAuth.ready] ready 期间换 token 重做并记录实际注入值，最多三次', () async {
    final tm = TestTokens();
    var ready = 0;
    var refresh = 0;
    final net = FakeNetwork()
      ..routes[b3Route] = [const FakeReply(status: 401), const FakeReply()];
    final api = testClient(network: net, plugins: [
      b3Auth(tm, refresh: (t, r) {
        refresh++;
        t.setTokens(accessToken: b3Fresh);
      }, ready: (t, r) async {
        ready++;
        final captured = t.accessToken;
        await Future<void>.value();
        if (ready == 1) t.setTokens(accessToken: b3Fresh);
        return RequestPatch(headers: {b3Header: 'Bearer $captured'});
      })
    ]);
    expect((await api.send<Object?>(b3ValueGet, b3Path)).ok, isTrue);
    expect(refresh, 1);
    expect(ready, DiomanAuth.readyStableAttempts);
    expect(net.sends.first.options.headers[b3Header], 'Bearer $b3Fresh');
    api.dispose();
  });
  test(
      '[DiomanAuth.injectedToken]'
      '[DiomanAuth.ready] 三次都不稳定以最后快照发出，401 replay 不触发刷新', () async {
    for (final unauthorized in [false, true]) {
      final tm = TestTokens();
      var ready = 0;
      var refresh = 0;
      final captured = <String?>[];
      final injected = <String?>[];
      final net = FakeNetwork()
        ..routes[b3Route] = [
          FakeReply(status: unauthorized ? 401 : 200),
          const FakeReply()
        ];
      final api = testClient(network: net, plugins: [
        b3Auth(tm, refresh: (t, r) {
          refresh++;
        }, ready: (t, r) async {
          ready++;
          final snapshot = t.accessToken;
          captured.add(snapshot);
          await Future<void>.value();
          if (ready <= DiomanAuth.readyStableAttempts) {
            t.setTokens(accessToken: 'token$ready');
          }
          return RequestPatch(headers: {b3Header: 'Bearer $snapshot'});
        }),
        TestPlugin(b3ValueReady, stage: DiomanStage.source,
            handler: (ctx, next) {
          injected.add(ctx.get<String?>(DiomanAuth.injectedToken));
          return next();
        })
      ]);
      expect((await api.send<Object?>(b3ValueGet, b3Path)).ok, isTrue);
      expect(ready, DiomanAuth.readyStableAttempts + (unauthorized ? 1 : 0));
      expect(net.sends.length, unauthorized ? 2 : 1);
      expect(injected.first, captured[DiomanAuth.readyStableAttempts - 1]);
      expect(net.sends.first.options.headers[b3Header],
          'Bearer ${injected.first}');
      expect(refresh, 0);
      if (unauthorized) {
        expect(injected.last, tm.accessToken);
        expect(net.sends.last.options.headers[b3Header],
            'Bearer ${tm.accessToken}');
      }
      api.dispose();
    }
  });
  test('[DiomanContext.cancelled] ready 与 onFailure 异步返回后重查取消，不通知不进入内层',
      () async {
    for (final mode in [b3ValueReady, b3ValueFailure]) {
      final token = CancelToken();
      final gate = Completer<void>();
      var inner = 0;
      var notices = 0;
      final api = testClient(plugins: [
        b3Auth(TestTokens(), expired: (t, r) {
          notices++;
        }, denied: (t, r) {
          notices++;
        },
            ready: mode == b3ValueReady
                ? (t, r) async {
                    await gate.future;
                    return const RequestPatch();
                  }
                : null,
            failure: mode == b3ValueFailure
                ? (r, t) async {
                    await gate.future;
                    return DiomanAuthFailureAction.deny;
                  }
                : null),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          inner++;
          return ctx
              .fail(const DiomanFailure(kind: DiomanKind.http, status: 401));
        })
      ]);
      final p = api.send<Object?>(b3ValueGet, b3Path,
          call: DiomanCall(cancelToken: token));
      await b3Turn();
      token.cancel();
      gate.complete();
      expect((await p).kind, DiomanKind.cancel);
      expect(inner, mode == b3ValueReady ? 0 : 1);
      expect(notices, 0);
      api.dispose();
    }
  });
  test('[DiomanAuthFailureAction.replay] 刷新成功后登出不重放，ready 期间登出也本地拒绝', () async {
    for (final mode in [b3ValueRefresh, b3ValueReady]) {
      final tm = TestTokens();
      var denied = 0;
      var ready = 0;
      final net = FakeNetwork()
        ..routes[b3Route] = [const FakeReply(status: 401)];
      final api = testClient(network: net, plugins: [
        b3Auth(tm, denied: (t, r) {
          denied++;
        }, refresh: (t, r) {
          t.setTokens(accessToken: b3Fresh);
          t.clear();
        },
            ready: mode == b3ValueReady
                ? (t, r) async {
                    ready++;
                    t.clear();
                    return const RequestPatch();
                  }
                : null)
      ]);
      final r = await api.send<Object?>(b3ValueGet, b3Path);
      expect(r.reason, b3ValueUnauthenticated);
      expect(denied, 1);
      expect(net.sends.length, mode == b3ValueRefresh ? 1 : 0);
      expect(ready, mode == b3ValueReady ? 1 : 0);
      api.dispose();
    }
  });
  test('[DiomanAuth.onRefresh] 同步与异步抛错释放窗口，失败清会话只通知一次并可同名重登', () async {
    for (final asyncError in [false, true]) {
      final tm = TestTokens();
      var calls = 0;
      var expired = 0;
      final logs = <String>[];
      final net = FakeNetwork()
        ..routes[b3Route] = [const FakeReply(status: 401)];
      final api = testClient(network: net, debug: logs.add, plugins: [
        b3Auth(tm, refresh: (t, r) {
          calls++;
          if (asyncError) return Future<void>.error(StateError('async'));
          throw StateError('sync');
        }, expired: (t, r) {
          expired++;
        })
      ]);
      final results = await Future.wait(
          List.generate(5, (_) => api.send<Object?>(b3ValueGet, b3Path)));
      expect(results.every((r) => r.reason == b3ValueExpired), isTrue);
      expect(calls, 1);
      expect(expired, 1);
      expect(tm.clears, 1);
      tm.setTokens(accessToken: b3Old);
      expect(
          (await api.send<Object?>(b3ValueGet, b3Path)).reason, b3ValueExpired);
      expect(calls, 2);
      expect(expired, 2);
      expect(logs.where((s) => s.contains('刷新失败')), hasLength(2));
      api.dispose();
    }
  });
  test('[DiomanAuth.onRefresh] 发起者等待者取消和 cancelAll 不终止刷新，成功写 token 失败清会话',
      () async {
    for (final success in [false, true]) {
      for (final all in [false, true]) {
        final tm = TestTokens();
        final gate = Completer<void>();
        final started = Completer<void>();
        var expired = 0;
        var calls = 0;
        final net = FakeNetwork()
          ..routes[b3Route] = [const FakeReply(status: 401), const FakeReply()];
        final api = testClient(network: net, plugins: [
          b3Auth(tm, refresh: (t, r) async {
            calls++;
            started.complete();
            await gate.future;
            if (!success) throw StateError(b3ValueRefresh);
            t.setTokens(accessToken: b3Fresh);
          }, expired: (t, r) {
            expired++;
          })
        ]);
        final first = CancelToken();
        final second = CancelToken();
        final a = api.send<Object?>(b3ValueGet, b3Path,
            call: DiomanCall(cancelToken: first));
        await started.future;
        final b = api.send<Object?>(b3ValueGet, b3Path,
            call: DiomanCall(cancelToken: second));
        await b3Turn();
        if (all) {
          expect(api.cancelAll(), 2);
        } else {
          first.cancel();
          second.cancel();
        }
        expect((await a).kind, DiomanKind.cancel);
        expect((await b).kind, DiomanKind.cancel);
        expect(calls, 1);
        expect(expired, 0);
        gate.complete();
        await b3Turn();
        expect(tm.accessToken, success ? b3Fresh : null);
        expect(expired, success ? 0 : 1);
        expect(net.sends.length, 1);
        api.dispose();
      }
    }
  });
  test('[DiomanAuth.onAccessExpired] 旧请求的 expired 与刷新失败均不清新会话，迟到 401 直接 replay',
      () async {
    for (final mode in [b3ValueExpired, b3ValueRefresh, b3ValueReplay]) {
      final tm = TestTokens();
      final gate = Completer<void>();
      final entered = Completer<void>();
      var notices = 0;
      var sent = 0;
      final api = testClient(plugins: [
        b3Auth(tm,
            expired: (t, r) {
              notices++;
            },
            failure: mode == b3ValueExpired
                ? (r, t) => DiomanAuthFailureAction.expired
                : null,
            refresh: (t, r) async {
              entered.complete();
              await gate.future;
              throw StateError(b3ValueOld);
            }),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          sent++;
          if (sent == 1 && mode != b3ValueRefresh) {
            entered.complete();
            await gate.future;
          }
          if (sent > 1) return next();
          return ctx
              .fail(const DiomanFailure(kind: DiomanKind.http, status: 401));
        })
      ]);
      final p = api.send<Object?>(b3ValueGet, b3Path);
      await entered.future;
      tm.setTokens(accessToken: b3Fresh);
      gate.complete();
      final r = await p;
      expect(tm.accessToken, b3Fresh);
      expect(notices, 0);
      expect(tm.clears, 0);
      expect(r.ok, mode == b3ValueReplay);
      api.dispose();
    }
  });
  test(
      '[DiomanAuth.onFailure] internal cancel 不路由，network timeout parse 仍路由且默认 others',
      () async {
    for (final kind in [
      DiomanKind.internal,
      DiomanKind.cancel,
      DiomanKind.network,
      DiomanKind.timeout,
      DiomanKind.parse
    ]) {
      for (final custom in [false, true]) {
        var calls = 0;
        final bug = StateError('bug');
        final api = testClient(plugins: [
          b3Auth(TestTokens(),
              failure: custom
                  ? (r, t) {
                      calls++;
                      return DiomanAuthFailureAction.others;
                    }
                  : null),
          TestPlugin(b3ValueResult, stage: DiomanStage.source,
              handler: (ctx, next) async {
            return ctx.fail(DiomanFailure(
                kind: kind, error: kind == DiomanKind.internal ? bug : null));
          })
        ]);
        final p = api.send<Object?>(b3ValueGet, b3Path);
        if (kind == DiomanKind.internal) {
          await expectLater(p, throwsA(same(bug)));
        } else {
          expect((await p).kind, kind);
        }
        expect(
            calls,
            custom && kind != DiomanKind.internal && kind != DiomanKind.cancel
                ? 1
                : 0);
        api.dispose();
      }
    }
  });
  test('[DiomanAuth.onAccessExpired] 通知同步异步抛错隔离，判定和 ready 异常原样抛出', () async {
    final bug = StateError('callback');
    for (final mode in [
      b3ValueDenied,
      b3ValueExpired,
      b3ValueFailure,
      b3ValueReady,
      b3ValueProtected
    ]) {
      final logs = <String>[];
      final net = FakeNetwork()
        ..routes[b3Route] = [const FakeReply(status: 401)];
      final api = testClient(network: net, debug: logs.add, plugins: [
        b3Auth(TestTokens(mode == b3ValueDenied ? null : b3Old),
            denied: (t, r) => throw bug,
            expired: (t, r) => Future<void>.error(bug),
            refresh: (t, r) => throw bug,
            failure: mode == b3ValueFailure ? (r, t) => throw bug : null,
            ready: mode == b3ValueReady ? (t, r) => throw bug : null,
            protected: mode == b3ValueProtected ? (r) => throw bug : null)
      ]);
      final p = api.send<Object?>(b3ValueGet, b3Path);
      if ([b3ValueFailure, b3ValueReady, b3ValueProtected].contains(mode)) {
        await expectLater(p, throwsA(same(bug)));
      } else {
        expect((await p).kind, DiomanKind.auth);
        expect(logs.any((s) => s.contains('鉴权通知失败')), isTrue);
      }
      api.dispose();
    }
  });
}
