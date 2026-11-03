import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/fake_clock.dart';

/// 本文件共用的测试值。
const _diomanLiteral0 = 'GET';

/// 本文件共用的测试值。
const _diomanLiteral1 = '/shared';

/// 共享重试必须使用传输补丁的取消作用域。
void main() {
  test('[DiomanSharePolicy.retry][DiomanNext] 首发取消后仍为跟随者重试', () async {
    final clock = FakeClock();
    final gate = Completer<void>();
    final token = CancelToken();
    var sends = 0;
    final api = testClient(clock: clock, plugins: [
      const DiomanShare(
          policy: DiomanSharePolicy.retry,
          retries: 1,
          interval: Duration(milliseconds: 1)),
      TestPlugin('source', stage: DiomanStage.source,
          handler: (ctx, next) async {
        sends++;
        if (sends == 1) await gate.future;
        return DiomanResponse<dynamic>(
            ok: sends > 1, status: sends > 1 ? 200 : 500, request: ctx.request);
      })
    ]);
    final first = api.send<Object?>(_diomanLiteral0, _diomanLiteral1,
        call: DiomanCall(
            cancelToken: token, options: {DiomanShare.option: true}));
    await flush();
    final follower = api.send<Object?>(_diomanLiteral0, _diomanLiteral1,
        call: DiomanCall(options: {DiomanShare.option: true}));
    await flush();
    token.cancel('leader-only');
    expect(failureOf(await first)?.kind, DiomanFailureKind.cancel);
    gate.complete();
    await flush();
    clock.elapse(const Duration(milliseconds: 1));
    await flush();
    final result = await follower;
    expect(result.ok, isTrue);
    expect(failureOf(result), isNull);
    expect(sends, 2);
    expect(api.pending, 0);
  });
}
