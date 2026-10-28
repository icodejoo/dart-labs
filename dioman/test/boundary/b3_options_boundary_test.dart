import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';

/// 请求级自定义头名称。
const _customHeader = 'X-Access';

/// 请求级自定义头前缀。
const _customPrefix = 'raw';

/// 验证迁移清单中请求级覆盖与安全回收的边界。
void main() {
  test('[DiomanAuth.onAccessExpired] 刷新后仍为 401 的并发请求全部 expired，每会话只通知一次',
      () async {
    final tm = TestTokens();
    final net = FakeNetwork()..routes[b3Route] = [const FakeReply(status: 401)];
    var refresh = 0;
    var expired = 0;
    final api = testClient(network: net, plugins: [
      b3Auth(tm, refresh: (tokens, r) {
        refresh++;
        tokens.setTokens(accessToken: b3Fresh);
      }, expired: (tokens, r) {
        expired++;
      })
    ]);
    final results = await Future.wait(
        List.generate(5, (_) => api.send<Object?>(b3ValueGet, b3Path)));
    expect(results.every((r) => r.reason == b3ValueExpired), isTrue);
    expect(refresh, 1);
    expect(expired, 1);
    expect(tm.clears, 1);
    api.dispose();
  });
  test('[defaultAuthFailure] 刷新窗口关闭后旧请求的 401 直接重放，整轮仅刷新一次', () async {
    final tm = TestTokens();
    final late = Completer<void>();
    var sends = 0;
    var refresh = 0;
    final api = testClient(plugins: [
      b3Auth(tm, refresh: (tokens, r) {
        refresh++;
        tokens.setTokens(accessToken: b3Fresh);
      }),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        final index = ++sends;
        if (index == 2) await late.future;
        if (index <= 2) {
          return ctx
              .fail(const DiomanFailure(kind: DiomanKind.http, status: 401));
        }
        return next();
      })
    ]);
    final first = api.send<Object?>(b3ValueGet, b3Path);
    final second = api.send<Object?>(b3ValueGet, b3Path);
    expect((await first).ok, isTrue);
    late.complete();
    expect((await second).ok, isTrue);
    expect(refresh, 1);
    expect(sends, 4);
    expect(tm.accessToken, b3Fresh);
    api.dispose();
  });
  test('[DiomanTokenManager.refreshToken] auth 不直接读取刷新凭证，onRefresh 自行决定能否刷新',
      () async {
    final tokens = _UnreadRefreshTokens();
    final net = FakeNetwork()
      ..routes[b3Route] = [const FakeReply(status: 401), const FakeReply()];
    final api = testClient(network: net, plugins: [b3Auth(tokens)]);
    expect((await api.send<Object?>(b3ValueGet, b3Path)).ok, isTrue);
    expect(tokens.accessToken, b3Fresh);
    api.dispose();
  });
  test('[DiomanAuthOptions.enabled] true 强制保护优先于公开谓词，省略与 call.true 沿用谓词',
      () async {
    for (final option in [null, true, const DiomanAuthOptions(enabled: true)]) {
      var protected = 0;
      final api = testClient(plugins: [
        b3Auth(TestTokens(null), protected: (r) {
          protected++;
          return false;
        })
      ]);
      final r = await api.send<Object?>(b3ValueGet, b3Path,
          call: DiomanCall(options: {DiomanAuth.option: option}));
      expect(r.reason,
          option is DiomanAuthOptions ? b3ValueUnauthenticated : null);
      expect(protected, option is DiomanAuthOptions ? 0 : 1);
      api.dispose();
    }
  });
  test('[DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖',
      () async {
    final tokens = TestTokens();
    final net = FakeNetwork();
    var expired = 0;
    final api = testClient(network: net, plugins: [b3Auth(tokens)]);
    await api.send<Object?>(b3ValueGet, b3Path,
        call: DiomanCall(options: {
          DiomanAuth.option: DiomanAuthOptions(
              headerKey: _customHeader, buildHeader: (t) => '$_customPrefix $t')
        }));
    expect(
        net.sends.last.options.headers[_customHeader], '$_customPrefix $b3Old');
    expect(net.sends.last.options.headers.containsKey(b3Header), isFalse);
    await api.send<Object?>(b3ValueGet, b3Path,
        call: DiomanCall(options: {
          DiomanAuth.option: DiomanAuthOptions(
              expiresAt: (t) => null,
              onAccessExpired: (t, r) {
                expired++;
              },
              onFailure: (r, t) => DiomanAuthFailureAction.expired)
        }));
    net.routes[b3Route] = [const FakeReply(status: 401)];
    final r = await api.send<Object?>(b3ValueGet, b3Path,
        call: DiomanCall(options: {
          DiomanAuth.option: DiomanAuthOptions(
              onFailure: (r, t) => DiomanAuthFailureAction.expired,
              onAccessExpired: (t, r) {
                expired++;
              })
        }));
    expect(r.reason, b3ValueExpired);
    expect(expired, 1);
    expect(tokens.accessToken, isNull);
    api.dispose();
  });
  test('[DiomanAuth.expiresAt] 并发主动刷新各轮一次，无失败首发；刷新失败等待者同为 expired', () async {
    for (final success in [false, true]) {
      final tm = TestTokens();
      final gate = Completer<void>();
      final started = Completer<void>();
      var refresh = 0;
      var expired = 0;
      final net = FakeNetwork();
      final api = testClient(network: net, plugins: [
        b3Auth(tm,
            expiresAt: (t) =>
                t == b3Old ? DateTime.fromMillisecondsSinceEpoch(0) : null,
            refresh: (t, r) async {
              refresh++;
              started.complete();
              await gate.future;
              if (!success) throw StateError(b3ValueRefresh);
              t.setTokens(accessToken: b3Fresh);
            },
            expired: (t, r) {
              expired++;
            })
      ]);
      final a = api.send<Object?>(b3ValueGet, b3Path);
      await started.future;
      final b = api.send<Object?>(b3ValueGet, b3Path);
      await b3Turn();
      expect(net.sends, isEmpty);
      gate.complete();
      final results = await Future.wait([a, b]);
      expect(refresh, 1);
      expect(expired, success ? 0 : 1);
      expect(results.every((r) => success ? r.ok : r.reason == b3ValueExpired),
          isTrue);
      expect(net.sends.length, success ? 2 : 0);
      if (success) {
        expect(
            net.sends
                .every((s) => s.options.headers[b3Header] == 'Bearer $b3Fresh'),
            isTrue);
      }
      api.dispose();
    }
  });
  test('[DiomanAuth.ready] buildHeader expiresAt 在首发和重放抛错均原样且收尾', () async {
    for (final header in [false, true]) {
      for (final replay in [false, true]) {
        final tm = TestTokens();
        final bug = StateError(b3ValueInternal);
        var calls = 0;
        final net = FakeNetwork()
          ..routes[b3Route] = [const FakeReply(status: 401)];
        final api = testClient(network: net, plugins: [
          DiomanAuth(
              tokenManager: tm,
              onRefresh: (t, r) => t.setTokens(accessToken: b3Fresh),
              onAccessExpired: (t, r) {},
              buildHeader: (t) {
                if (header && ++calls > (replay ? 1 : 0)) throw bug;
                return 'Bearer $t';
              },
              expiresAt: (t) {
                if (!header && ++calls > (replay ? 1 : 0)) throw bug;
                return null;
              })
        ]);
        await expectLater(
            api.send<Object?>(b3ValueGet, b3Path), throwsA(same(bug)));
        expect(api.pending, 0);
        api.dispose();
      }
    }
  });
  test(
      '[DiomanBreaker.idleTtl] open halfOpen 与 closed 在途桶不回收，安全桶回收后同键从 closed 开始',
      () async {
    final clock = FakeClock();
    final gates = <Completer<void>>[];
    var hold = false;
    var failed = false;
    final api = testClient(clock: clock, plugins: [
      const DiomanBreaker(
          failureThreshold: 1,
          resetDuration: b3Tick,
          idleTtl: Duration.zero,
          maxBuckets: 1),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        if (hold) {
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future;
        }
        return ctx.fail(DiomanFailure(
            kind: failed ? DiomanKind.network : DiomanKind.http, status: 200));
      })
    ]);
    final m = api.plugin<DiomanBreakerApi>()!;
    await api.send<Object?>(b3ValueGet, b3Path);
    clock.elapse(b3Tick);
    await api.send<Object?>(b3ValueGet, b3ValueCustom);
    expect(m.bucketCount, 1);
    expect(m.stateOf(b3Route), DiomanBreakerState.closed);
    hold = true;
    final pending = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    hold = false;
    failed = true;
    await api.send<Object?>(b3ValueGet, b3ValueCustom);
    expect(m.bucketCount, 2);
    expect(m.stateOf('GET:custom'), DiomanBreakerState.open);
    clock.elapse(b3Tick);
    hold = true;
    final probe = api.send<Object?>(b3ValueGet, b3ValueCustom);
    await b3Turn();
    hold = false;
    await api.send<Object?>(b3ValueGet, b3ValueResult);
    expect(m.bucketCount, 3);
    expect(m.stateOf('GET:custom'), DiomanBreakerState.halfOpen);
    failed = false;
    gates[0].complete();
    gates[1].complete();
    await Future.wait([pending, probe]);
    api.dispose();
  });
  test('[DiomanBreaker.shouldTrip] Dio 连接与三种超时只计一次，成功清连续失败且非正数不钳制', () async {
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout
    ]) {
      final net = FakeNetwork()
        ..failOn[1] = DioException(
            requestOptions: RequestOptions(path: b3Path), type: type);
      final api = testClient(
          network: net, plugins: [const DiomanBreaker(failureThreshold: 2)]);
      await api.send<Object?>(b3ValueGet, b3Path);
      expect(api.plugin<DiomanBreakerApi>()!.stateOf(b3Route),
          DiomanBreakerState.closed);
      await api.send<Object?>(b3ValueGet, b3Path);
      net.failOn[3] = net.failOn[1]!;
      await api.send<Object?>(b3ValueGet, b3Path);
      expect(api.plugin<DiomanBreakerApi>()!.stateOf(b3Route),
          DiomanBreakerState.closed);
      api.dispose();
    }
    for (final value in [0, -1]) {
      final clock = FakeClock();
      final api = testClient(clock: clock, plugins: [
        DiomanBreaker(
            failureThreshold: value,
            halfOpenMaxCalls: value,
            resetDuration: Duration(seconds: value)),
        TestPlugin(b3ValueResult,
            stage: DiomanStage.source,
            handler: (ctx, next) async =>
                ctx.fail(const DiomanFailure(kind: DiomanKind.network)))
      ]);
      await api.send<Object?>(b3ValueGet, b3Path);
      expect((await api.send<Object?>(b3ValueGet, b3Path)).kind,
          DiomanKind.breaker);
      expect(api.plugin<DiomanBreakerApi>()!.stateOf(b3Route),
          DiomanBreakerState.halfOpen);
      api.dispose();
    }
  });
}

/// 读取刷新凭证即报错，证明 auth 只调用使用者的刷新契约。
class _UnreadRefreshTokens extends TestTokens {
  /// 使用默认初始访问凭证。
  _UnreadRefreshTokens();

  /// 刷新凭证只允许 onRefresh 的实现自行访问。
  @override
  String? get refreshToken => throw StateError(b3ValueRefresh);
}
