import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/b3_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 验证凭证、逻辑状态与鉴权路由。
void main() {
  test(
      '[DiomanTokenManager.accessToken]'
      '[DiomanTokenManager.clear]'
      '[DiomanTokenManager.setTokens]'
      '[DiomanTokenManager] setTokens 与 clear 管理原始凭证，不提供 canRefresh', () {
    final tm = TestTokens(null);
    expect(tm.accessToken, isNull);
    expect(tm.refreshToken, isNull);
    tm.setTokens(accessToken: b3Old, refreshToken: b3Fresh);
    expect(tm.accessToken, b3Old);
    expect(tm.refreshToken, b3Fresh);
    tm.setTokens(accessToken: b3Fresh);
    expect(tm.refreshToken, isNull);
    tm.clear();
    expect(tm.accessToken, isNull);
    expect(tm.clears, 1);
  });
  test(
      '[DiomanAuthFailureAction.deny][DiomanAuthFailureAction.expired][DiomanAuthFailureAction.others][DiomanAuthFailureAction.refresh]'
      '[defaultAuthFailure] 默认判定覆盖无 token、旧 token、逻辑 401 403 与其它失败', () async {
    for (final current in <String?>[null, b3ValueEmpty, b3Old, b3Fresh]) {
      final tm = TestTokens(current);
      final api = testClient();
      final request = (await api.send<Object?>(b3ValueGet, b3Path)).request;
      for (final status in [401, 403, 500]) {
        final r = DiomanResponse<dynamic>(
            ok: false,
            kind: DiomanKind.biz,
            status: status,
            httpStatus: 200,
            data: null,
            request: request);
        expect(
            defaultAuthFailure(r, tm, b3Old),
            status == 403
                ? DiomanAuthFailureAction.deny
                : status == 500
                    ? DiomanAuthFailureAction.others
                    : current == null || current.isEmpty
                        ? DiomanAuthFailureAction.expired
                        : current == b3Old
                            ? DiomanAuthFailureAction.refresh
                            : DiomanAuthFailureAction.replay);
      }
      api.dispose();
    }
  });
  test(
      '[DiomanAuth.defaultBuildHeader]'
      '[DiomanAuth.name]'
      '[DiomanAuth.pluginName]'
      '[DiomanAuth.onRefresh] HTTP 与 business 401 默认 Bearer 刷新重放一次，非鉴权失败原样',
      () async {
    for (final business in [false, true]) {
      for (final finalStatus in [200, 401, 403, 500]) {
        final net = FakeNetwork()
          ..routes[b3Route] = [
            FakeReply(
                status: business ? 200 : 401,
                body: {b3ValueCode: business ? 401 : 0, b3ValueData: null}),
            FakeReply(status: business ? 200 : finalStatus, body: {
              b3ValueCode: business && finalStatus != 200 ? finalStatus : 0,
              b3ValueData: b3ValueResult
            })
          ];
        final tm = TestTokens();
        var refresh = 0;
        var expired = 0;
        var denied = 0;
        final api = testClient(network: net, plugins: [
          b3Auth(tm, refresh: (t, r) {
            refresh++;
            t.setTokens(accessToken: b3Fresh);
          }, expired: (t, r) {
            expired++;
          }, denied: (t, r) {
            denied++;
          })
        ]);
        final r = await api.send<Object?>(b3ValueGet, b3Path);
        expect(refresh, 1);
        expect(net.sends.length, 2);
        expect(net.sends.first.options.headers[b3Header], 'Bearer $b3Old');
        expect(net.sends.last.options.headers[b3Header], 'Bearer $b3Fresh');
        expect(r.ok, finalStatus == 200);
        expect(expired, finalStatus == 401 ? 1 : 0);
        expect(denied, finalStatus == 403 ? 1 : 0);
        expect(tm.accessToken, finalStatus == 401 ? null : b3Fresh);
        api.dispose();
      }
    }
  });
  test('[DiomanAuth.onAccessDenied] 本地无 token 每请求通知一次，空串等价未登录，默认回退 expired',
      () async {
    for (final empty in <String?>[null, b3ValueEmpty]) {
      for (final own in [false, true]) {
        final tm = TestTokens(empty);
        final net = FakeNetwork();
        var notices = 0;
        final api = testClient(network: net, plugins: [
          b3Auth(tm,
              expired: own
                  ? (t, r) => fail('unexpected')
                  : (t, r) {
                      notices++;
                    },
              denied: own
                  ? (t, r) {
                      notices++;
                    }
                  : null)
        ]);
        for (var i = 0; i < 2; i++) {
          final r = await api.send<Object?>(b3ValueGet, b3Path);
          expect(r.reason, b3ValueUnauthenticated);
        }
        expect(notices, 2);
        expect(net.sends, isEmpty);
        expect(tm.clears, 0);
        api.dispose();
      }
    }
  });
  test('[DiomanAuth.onFailure] 自定义五动作、仅重放一次和非鉴权结果返回', () async {
    for (final action in DiomanAuthFailureAction.values) {
      final tm = TestTokens();
      var notices = 0;
      var calls = 0;
      final net = FakeNetwork()
        ..routes[b3Route] = [const FakeReply(status: 401)];
      final api = testClient(network: net, plugins: [
        b3Auth(tm, failure: (r, t) {
          calls++;
          return action;
        }, expired: (t, r) {
          notices++;
        })
      ]);
      final r = await api.send<Object?>(b3ValueGet, b3Path);
      final repeats = action == DiomanAuthFailureAction.refresh ||
          action == DiomanAuthFailureAction.replay;
      expect(net.sends.length, repeats ? 2 : 1);
      expect(calls, repeats ? 2 : 1);
      expect(notices, action == DiomanAuthFailureAction.others ? 0 : 1);
      expect(
          r.kind,
          action == DiomanAuthFailureAction.others
              ? DiomanKind.http
              : DiomanKind.auth);
      api.dispose();
    }
  });
  test(
      '[DiomanAuth.new(refreshLeeway)][DiomanAuthOptions.expiresAt][DiomanAuthOptions.onAccessExpired][DiomanAuthOptions.refreshLeeway]'
      '[DiomanAuth.expiresAt] 主动刷新只一次、空过期时间不刷新、提前量请求覆盖', () async {
    for (final mode in [
      b3ValueDue,
      b3ValueFuture,
      b3ValueNull,
      b3ValueFailure
    ]) {
      final tm = TestTokens();
      final clock = FakeClock();
      final net = FakeNetwork();
      var refresh = 0;
      final api = testClient(clock: clock, network: net, plugins: [
        DiomanAuth(
            tokenManager: tm,
            onRefresh: (t, r) {
              refresh++;
              if (mode == b3ValueFailure) throw StateError(b3ValueRefresh);
              t.setTokens(accessToken: b3Fresh);
            },
            onAccessExpired: (t, r) {},
            expiresAt: (t) =>
                mode == b3ValueNull ? null : clock.now().add(b3Tick))
      ]);
      final r = await api.send<Object?>(b3ValueGet, b3Path,
          call: DiomanCall(options: {
            DiomanAuth.option: DiomanAuthOptions(
                refreshLeeway: mode == b3ValueFuture ? Duration.zero : b3Tick)
          }));
      expect(refresh, [b3ValueDue, b3ValueFailure].contains(mode) ? 1 : 0);
      expect(net.sends.length, mode == b3ValueFailure ? 0 : 1);
      expect(r.reason, mode == b3ValueFailure ? b3ValueExpired : null);
      api.dispose();
    }
  });
  test(
      '[DiomanAuth.new(isProtected)][DiomanAuthOptions.isProtected][DiomanAuthOptions.onAccessDenied][DiomanAuthOptions.ready]'
      '[DiomanAuth.option] 四种写法、请求覆盖、公开路径和安装禁用', () async {
    for (final option in <Object?>[
      null,
      true,
      false,
      const DiomanAuthOptions(enabled: false),
      const DiomanAuthOptions(isProtected: _public),
      b3ValueBad
    ]) {
      final api = testClient(plugins: [b3Auth(TestTokens(null))]);
      final p = api.send<Object?>(b3ValueGet, b3Path,
          call: DiomanCall(options: {DiomanAuth.option: option}));
      if (option == b3ValueBad) {
        await expectLater(p, throwsArgumentError);
      } else {
        expect((await p).ok, option == false || option is DiomanAuthOptions);
      }
      api.dispose();
    }
    final tm = TestTokens();
    var protected = 0;
    var denied = 0;
    final net = FakeNetwork()..routes[b3Route] = [const FakeReply(status: 403)];
    final api = testClient(network: net, plugins: [b3Auth(tm)]);
    await api.send<Object?>(b3ValueGet, b3Path,
        call: DiomanCall(options: {
          DiomanAuth.option: DiomanAuthOptions(
              isProtected: (r) {
                protected++;
                return true;
              },
              onAccessDenied: (t, r) {
                denied++;
              },
              onAccessExpired: (t, r) => fail(b3ValueExpired),
              onFailure: (r, t) => DiomanAuthFailureAction.deny,
              ready: (t, r) =>
                  const RequestPatch(headers: {b3ValueCustom: b3ValueYes}),
              expiresAt: (t) => null,
              refreshLeeway: b3Tick,
              headerKey: 'X',
              buildHeader: (t) => 'raw $t')
        }));
    expect(protected, 1);
    expect(denied, 1);
    expect(net.sends.single.options.headers[b3ValueCustom], b3ValueYes);
    api.dispose();
    final disabled = testClient(plugins: [
      DiomanAuth(
          tokenManager: tm,
          onRefresh: (t, r) {},
          onAccessExpired: (t, r) {},
          enabled: false)
    ]);
    expect(disabled.inspect(), isEmpty);
    disabled.dispose();
  });
}

/// 公开请求谓词。
bool _public(DiomanRequest request) => false;
