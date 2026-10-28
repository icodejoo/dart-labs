import '../support/pipeline/constants.dart';
import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/helpers.dart';

/// 取消等待的各个终局及逻辑状态共享。
void main() {
  test('[DiomanContext.wait] 替换传输令牌隔离外层取消，逻辑状态仍共享', () async {
    final root = testContext();
    final token = CancelToken();
    final inner = root.derive(RequestPatch(cancelToken: token));
    final gate = Completer<int>();
    final waiting = inner.wait(gate.future);
    root.state.cancel();
    await flush();
    expect(root.isCancelled, isTrue);
    expect(inner.isCancelled, isFalse);
    expect(inner.cancellationSubscriptions, 1);
    gate.complete(7);
    expect(await waiting, 7);
    expect(inner.cancellationSubscriptions, 0);
    token.cancel();
    await flush();
    expect(inner.isCancelled, isTrue);
  });
  test('[DiomanContext.wait] 正常值、异常、超时、取消均清理且忽略迟到结果', () async {
    for (final outcome in [
      pipelineTestValue,
      pipelineTestError,
      pipelineTestTimeout,
      pipelineTestCancel
    ]) {
      final clock = FakeClock();
      final ctx = testContext(clock: clock);
      final input = Completer<int>();
      final result =
          ctx.wait(input.future, timeout: const Duration(seconds: 1));
      expect(ctx.cancellationSubscriptions, 1);
      expect(clock.pendingTimers, 1);
      switch (outcome) {
        case pipelineTestValue:
          input.complete(7);
          expect(await result, 7);
        case pipelineTestError:
          input.completeError(StateError(pipelineTestWait));
          await expectLater(result, throwsStateError);
        case pipelineTestTimeout:
          clock.elapse(const Duration(seconds: 1));
          expect(await result, isNull);
          expect(ctx.cancelled(), isNull);
        case pipelineTestCancel:
          ctx.state.cancel();
          expect(await result, isNull);
          expect(ctx.cancelled()!.kind, DiomanKind.cancel);
      }
      expect(ctx.cancellationSubscriptions, 0);
      expect(clock.pendingTimers, 0);
      if (!input.isCompleted) input.completeError(StateError(pipelineTestLate));
      clock.elapse(const Duration(days: 1));
      await flush();
      ctx.state.dispose();
    }
  });

  test('[DiomanContext.wait] 已取消立即返回且不登记，无超时、多等待和替换令牌', () async {
    final token = CancelToken()..cancel();
    final clock = FakeClock();
    final ctx = testContext(token: token, clock: clock);
    expect(await ctx.wait(Future.value(1), timeout: Duration.zero), isNull);
    expect(ctx.cancellationSubscriptions, 0);
    expect(clock.pendingTimers, 0);
    final late = Completer<int>();
    expect(await ctx.wait(late.future), isNull);
    late.completeError(StateError(pipelineTestLate));
    final active = testContext();
    expect(await active.wait(Future.value(2)), 2);
    final one = active.wait(Completer<int>().future);
    final two = active.wait(Completer<int>().future);
    active.state.token.cancel();
    expect(await one, isNull);
    expect(await two, isNull);
    final custom = CancelToken();
    final derived = testContext().derive(RequestPatch(cancelToken: custom));
    final pending = derived.wait(Completer<int>().future);
    custom.cancel();
    expect(await pending, isNull);
    expect(derived.isCancelled, isTrue);
    expect(derived.cancellationSubscriptions, 0);
    final done = testContext();
    final finishing = done.wait(Completer<int>().future);
    done.state.dispose();
    expect(await finishing, isNull);
    await flush();
  });

  test('[DiomanContext.key] 每请求缓存、派生重算、类型状态共享及按身份隔离', () {
    var calls = 0;
    final ctx = testContext(key: DiomanKeyOptions(builder: (o) {
      calls++;
      return o.path;
    }));
    final key = StateKey<int>(pipelineTestSame);
    final other = StateKey<int>(pipelineTestSame);
    expect(ctx.get(key), isNull);
    ctx.set(key, 4);
    expect(ctx.key(), pipelineTestUnit);
    expect(ctx.key(), pipelineTestUnit);
    expect(calls, 1);
    final inner = ctx.derive(const RequestPatch(path: pipelineTestInner));
    expect(inner.id, ctx.id);
    expect(inner.client, same(ctx.client));
    expect(inner.get(key), 4);
    expect(inner.get(other), isNull);
    expect(key.description, pipelineTestSame);
    inner.set(key, 5);
    expect(ctx.get(key), 5);
    expect(inner.key(), pipelineTestInner);
    expect(calls, 2);
    expect(ctx.replayable, isFalse);
    inner.markReplayable();
    expect(ctx.replayable, isTrue);
    final noKey = ctx.derive(const RequestPatch());
    expect(noKey.key(), pipelineTestUnit);
  });
}
