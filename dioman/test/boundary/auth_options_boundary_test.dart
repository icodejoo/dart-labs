import '../support/response_contract.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 请求级自定义头名称。
const _customHeader = 'X-Access';
/// 请求级自定义头前缀。
const _customPrefix = 'raw';

/// 验证对应主题的行为与边界。
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
    expect(
        results.every((r) => failureOf(r)?.reason == b3ValueExpired), isTrue);
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
          return scriptedResult(ctx, diomanTestHttp, status: 401);
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
      expect(failureOf(r)?.reason,
          option is DiomanAuthOptions ? b3ValueUnauthenticated : null);
      expect(protected, option is DiomanAuthOptions ? 0 : 1);
      api.dispose();
    }
  });
  test(
      '[DiomanAuth.new(headerKey)][DiomanAuthOptions.buildHeader][DiomanAuthOptions.onFailure]'
      '[DiomanAuthOptions.headerKey] 自定义头和格式、ready 优先，过期通知与 expiresAt 请求覆盖',
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
    expect(failureOf(r)?.reason, b3ValueExpired);
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
      expect(
          results.every(
              (r) => success ? r.ok : failureOf(r)?.reason == b3ValueExpired),
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
  test(
      '[DiomanAuth.new(buildHeader)][DiomanAuth.new(tokenManager)]'
      '[DiomanAuth.ready] buildHeader expiresAt 在首发和重放抛错均原样且收尾', () async {
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
}

/// 读取刷新凭证即报错，证明 auth 只调用使用者的刷新契约。
class _UnreadRefreshTokens extends TestTokens {
  /// 使用默认初始访问凭证。
  _UnreadRefreshTokens();

  /// 刷新凭证只允许 onRefresh 的实现自行访问。
  @override
  String? get refreshToken => throw StateError(b3ValueRefresh);
}
