import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/helpers.dart';

/// 验证每个异步阶段的取消与窗口收尾。
void main() {
  test('[replaceOption] 标量覆盖合并返回请求值，保留布尔选项解析协议', () {
    expect(resolveOption<int>(2, base: 1, merge: replaceOption), 2);
    expect(
        resolveOption<bool>(true, base: false, merge: replaceOption), isFalse);
    expect(
        resolveOption<bool>(false, base: true, merge: replaceOption), isNull);
  });
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
            handler: (ctx, next) async => ctx
                .fail(const DiomanFailure(kind: DiomanKind.http, status: 401))),
      ]);
      final pending = api.send<Object?>(b3ValueGet, b3Path);
      await started.future;
      expect(api.cancelAll(), 1);
      expect((await pending).kind, DiomanKind.cancel);
      expect(api.pending, 0);
      expect(api.cancellationSubscriptions, 0);
      gate.completeError(StateError('late callback'));
      await b3Turn();
      api.dispose();
    }
  });
  test('[DiomanPlugin.stage] B3 固定阶段、名称和每客户端独立状态', () async {
    final retry = const DiomanRetry();
    final breaker = const DiomanBreaker();
    final auth = b3Auth(TestTokens());
    expect(retry.stage, DiomanStage.attempt);
    expect(breaker.stage, DiomanStage.attempt);
    expect(auth.stage, DiomanStage.credential);
    expect([retry.name, breaker.name, auth.name],
        ['dioman:retry', 'dioman:breaker', 'dioman:auth']);
    final a = testClient(plugins: [breaker]);
    final b = testClient(plugins: [breaker]);
    final m = a.plugin<DiomanBreakerApi>()!;
    final request = DiomanRequest(RequestOptions(path: b3Path));
    expect(m.isOpen(request), isFalse);
    expect(identical(m, b.plugin<DiomanBreakerApi>()), isFalse);
    a.dispose();
    b.dispose();
  });
  test('[DiomanNext] 重发之后 internal 原样抛出，取消禁止第三次尝试', () async {
    for (final internal in [false, true]) {
      final clock = FakeClock();
      var entered = 0;
      final bug = StateError('second');
      final api = testClient(clock: clock, plugins: [
        const DiomanRetry(max: 3),
        TestPlugin(b3ValueResult, stage: DiomanStage.source,
            handler: (ctx, next) async {
          entered++;
          if (entered == 2) {
            ctx.state.cancel();
            if (internal) throw bug;
          }
          return ctx.fail(const DiomanFailure(kind: DiomanKind.network));
        })
      ]);
      final p = b3Finish(api.send<Object?>(b3ValueGet, b3Path), clock);
      if (internal) {
        await expectLater(p, throwsA(same(bug)));
      } else {
        expect((await p).kind, DiomanKind.cancel);
      }
      expect(entered, 2);
      api.dispose();
    }
  });
  test('[DiomanNext] 下游返回前取消不路由，过期通知并发去重且取消后以 cancel 结束', () async {
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
        return ctx
            .fail(const DiomanFailure(kind: DiomanKind.http, status: 401));
      })
    ]);
    final first = api.send<Object?>(b3ValueGet, b3Path);
    await b3Turn();
    final second = api.send<Object?>(b3ValueGet, b3Path);
    await started.future;
    gate.complete();
    expect((await first).kind, DiomanKind.cancel);
    expect((await second).reason, b3ValueExpired);
    expect(notices, 1);
    api.dispose();
  });
  test('[DiomanAuth.onAccessExpired] 同会话多个在途 expired 只清理通知一次', () async {
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
        return ctx
            .fail(const DiomanFailure(kind: DiomanKind.http, status: 401));
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
    expect((await p).kind, DiomanKind.cancel);
    gate.complete();
    await b3Turn();
    expect(tm.accessToken, b3Fresh);
    api.dispose();
  });
}
