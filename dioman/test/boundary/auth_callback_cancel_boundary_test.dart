import '../support/response_contract.dart';
import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test(
      '[DiomanContext.wait] 取消未完成的 ready onFailure denied expired 回调立即收尾，迟到异常被消费',
      () async {
    for (final mode in [
      b3ValueReady,
      b3ValueFailure,
      b3ValueDenied,
      b3ValueExpired
    ]) {
      final gate = Completer<void>();
      final started = Completer<void>();
      final tokens = TestTokens(mode == b3ValueDenied ? null : b3Old);
      final api = testClient(plugins: [
        b3Auth(tokens,
            ready: mode == b3ValueReady
                ? (t, r) async {
                    started.complete();
                    await gate.future;
                    return const RequestPatch();
                  }
                : null,
            failure: mode == b3ValueFailure
                ? (r, t) async {
                    started.complete();
                    await gate.future;
                    return DiomanAuthFailureAction.deny;
                  }
                : mode == b3ValueExpired
                    ? (r, t) => DiomanAuthFailureAction.expired
                    : null, denied: (t, r) async {
          started.complete();
          await gate.future;
        }, expired: (t, r) async {
          started.complete();
          await gate.future;
        }),
        TestPlugin(b3ValueResult,
            stage: DiomanStage.source,
            handler: (ctx, next) async =>
                scriptedResult(ctx, diomanTestHttp, status: 401)),
      ]);
      final pending = api.send<Object?>(b3ValueGet, b3Path);
      await started.future;
      expect(api.cancelAll(), 1);
      expect(outcomeOf((await pending)), diomanTestCancel);
      expect(api.pending, 0);
      expect(api.cancellationSubscriptions, 0);
      gate.completeError(StateError('late callback'));
      await b3Turn();
      api.dispose();
    }
  });
  test(
      '[DiomanFailure.reason]'
      '[DiomanNext] 下游返回前取消不路由，过期通知并发去重且取消后以 cancel 结束', () async {
    var notices = 0;
    final started = Completer<void>();
    final gate = Completer<void>();
    final tm = TestTokens();
    var sent = 0;
    final api = testClient(plugins: [
      b3Auth(tm,
          expired: (t, r) async {
            notices++;
            started.complete();
            await gate.future;
          },
          failure: (r, t) => DiomanAuthFailureAction.expired),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        sent++;
        if (sent == 1) {
          await gate.future;
          ctx.state.cancel();
        }
        return scriptedResult(ctx, diomanTestHttp, status: 401);
      })
    ]);
    final first = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    final second = api.send<Object?>(b3ValueGet, b3Path);
    await started.future;
    gate.complete();
    expect(outcomeOf((await first)), diomanTestCancel);
    expect(failureOf((await second))?.reason, b3ValueExpired);
    expect(notices, 1);
    api.dispose();
  });
  test(
      '[DiomanResponse.status]'
      '[DiomanAuth.onAccessExpired] 同会话多个在途 expired 只清理通知一次', () async {
    final gates = List.generate(2, (_) => Completer<void>());
    var sent = 0;
    var notices = 0;
    final tm = TestTokens();
    final api = testClient(plugins: [
      b3Auth(tm,
          failure: (r, t) => DiomanAuthFailureAction.expired,
          expired: (t, r) {
            notices++;
          }),
      TestPlugin(b3ValueResult, stage: DiomanStage.source,
          handler: (ctx, next) async {
        final index = sent++;
        await gates[index].future;
        return scriptedResult(ctx, diomanTestHttp, status: 401);
      })
    ]);
    final a = api.send<Object?>(b3ValueGet, b3Path);
    final b = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    gates[0].complete();
    await a;
    gates[1].complete();
    await b;
    expect(tm.clears, 1);
    expect(notices, 1);
    api.dispose();
  });
  test('[DiomanAuth.expiresAt] 主动刷新等待取消也不终止共享刷新', () async {
    final tm = TestTokens();
    final gate = Completer<void>();
    final started = Completer<void>();
    final api = testClient(plugins: [
      b3Auth(tm,
          expiresAt: (t) => DateTime.fromMillisecondsSinceEpoch(0),
          refresh: (t, r) async {
            started.complete();
            await gate.future;
            t.setTokens(accessToken: b3Fresh);
          })
    ]);
    final p = api.send<Object?>(b3ValueGet, b3Path);
    await started.future;
    api.cancelAll();
    expect(outcomeOf((await p)), diomanTestCancel);
    gate.complete();
    await b3Turn();
    expect(tm.accessToken, b3Fresh);
    api.dispose();
  });
}
