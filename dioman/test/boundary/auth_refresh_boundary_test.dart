import '../support/response_contract.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';

const _result = 'result';
const _path = '/b8';
const _get = 'GET';
const _second = Duration(seconds: 1);

/// 验证对应主题的行为与边界。
void main() {
  for (final replace in [false, true]) {
    for (final override in [false, true]) {
      test(
          '[DiomanAuth.refreshTimeout][DiomanAuthOptions.refreshTimeout] B8 刷新超时 replace=$replace override=$override',
          () async {
        final clock = FakeClock();
        final tokens = TestTokens();
        var notices = 0;
        var refreshes = 0;
        final api =
            testClient(statusOf: businessStatus, clock: clock, plugins: [
          DiomanAuth<Result>(
              tokenManager: tokens,
              onRefresh: (_, __) {
                refreshes++;
                return Completer<void>().future;
              },
              onAccessExpired: (_, __) => notices++),
          TestPlugin(_result,
              stage: DiomanStage.source,
              handler: (ctx, next) async => scriptedResult(ctx, diomanTestHttp,
                  status: tokens.accessToken == b3Fresh ? 200 : 401))
        ]);
        final call = DiomanCall(options: {
          if (override)
            DiomanAuth.option: const DiomanAuthOptions(refreshTimeout: _second)
        });
        final requests = [
          api.send<dynamic>(_get, _path, call: call),
          api.send<dynamic>(_get, _path, call: call)
        ];
        for (var i = 0; i < 10 && refreshes == 0; i++) {
          await b3Turn();
        }
        expect(refreshes, 1);
        if (replace) tokens.setTokens(accessToken: b3Fresh);
        clock.elapse(override ? _second : const Duration(seconds: 30));
        final results = await Future.wait(requests);
        expect(results.map((r) => r.status), everyElement(replace ? 200 : 0));
        expect(results.map((r) => outcomeOf(r)),
            everyElement(replace ? diomanTestBiz : diomanTestAuth));
        expect(notices, replace ? 0 : 1);
        expect(clock.pendingTimers, 0);
        api.dispose();
      });
    }
  }
  test('[DiomanAuth.refreshTimeout] B8 刷新异常遇到新登录继续当前 token', () async {
    final tokens = TestTokens();
    final gate = Completer<void>();
    var notices = 0;
    final api = testClient(statusOf: businessStatus, plugins: [
      DiomanAuth<Result>(
          tokenManager: tokens,
          onRefresh: (_, __) => gate.future,
          onAccessExpired: (_, __) => notices++),
      TestPlugin(_result,
          stage: DiomanStage.source,
          handler: (ctx, next) async => scriptedResult(ctx, diomanTestHttp,
              status: tokens.accessToken == b3Fresh ? 200 : 401))
    ]);
    final pending = api.send<dynamic>(_get, _path);
    for (var i = 0; i < 5; i++) {
      await b3Turn();
    }
    tokens.setTokens(accessToken: b3Fresh);
    gate.completeError(StateError('refresh'));
    expect((await pending).status, 200);
    expect(notices, 0);
    api.dispose();
  });
}
