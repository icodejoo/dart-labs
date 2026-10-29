import 'package:dioman/src/diagnostics.dart';
import '../support/constants.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

/// 客户端生命周期与取消边界。
void main() {
  test('[Dioman.send] 同时取消不掩盖中间件程序异常和原始栈', () async {
    final bug = StateError(pipelineTestBug);
    final stack = StackTrace.fromString(pipelineTestOriginalStack);
    final api = testClient(plugins: [
      TestPlugin('cancel-then-bug', handler: (ctx, _) {
        ctx.cancelToken.cancel();
        Error.throwWithStackTrace(bug, stack);
      })
    ]);
    try {
      await api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath);
      fail('必须抛出程序异常');
    } catch (e, s) {
      expect(e, same(bug));
      expect(s.toString(), stack.toString());
    }
    expect(api.pending, 0);
  });
  test('[Dioman.cancelAll] 逻辑计数、重复取消、用户取消联动及 pending 清理', () async {
    final entered = Completer<void>();
    final api = testClient(plugins: [
      TestPlugin(pipelineTestWait, handler: (ctx, _) async {
        if (!entered.isCompleted) entered.complete();
        await ctx.wait(Completer<void>().future);
        return ctx.cancelled()!;
      })
    ]);
    final first = api.send<Object?>(pipelineTestGetMethod, '/one');
    final second = api.send<Object?>(pipelineTestGetMethod, '/two');
    await entered.future;
    expect(api.pending, 2);
    expect(api.cancellationSubscriptions, 2);
    expect(api.cancelAll('stop'), 2);
    expect(api.cancelAll(), 0);
    expect((await first).kind, DiomanKind.cancel);
    expect((await second).kind, DiomanKind.cancel);
    expect(api.pending, 0);
    final token = CancelToken();
    final third = api.send<Object?>(pipelineTestGetMethod, '/three',
        call: DiomanCall(cancelToken: token));
    token.cancel('user');
    expect((await third).kind, DiomanKind.cancel);
    final already = CancelToken()..cancel();
    expect(
        (await api.send<Object?>(pipelineTestGetMethod, '/four',
                call: DiomanCall(cancelToken: already)))
            .kind,
        DiomanKind.cancel);
    expect(api.pending, 0);
    expect(api.cancelAll(), 0);
  });

  test('[Dioman.pending] 登记后 compose/上下文构造抛错仍注销并解除用户订阅', () async {
    final api = testClient();
    final token = CancelToken();
    await expectLater(
        api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath,
            call: _BadCall(token)),
        throwsStateError);
    await expectLater(
        api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath,
            call: _BadContextCall(token)),
        throwsStateError);
    expect(api.pending, 0);
    expect(api.cancellationSubscriptions, 0);
    token.cancel();
    await flush();
    expect(await api.get<String>('/next'), pipelineTestOk);
  });

  test('[Dioman.use] 重名和保留前缀先拒绝 setup，安装失败原链不变', () async {
    final api = testClient(plugins: [TestPlugin(pipelineTestA)]);
    final duplicate = TestPlugin(pipelineTestA);
    expect(() => api.use(duplicate), throwsArgumentError);
    expect(duplicate.setups, 0);
    final reserved = TestPlugin(pipelineTestDiomanUnknown);
    expect(() => api.use(reserved), throwsArgumentError);
    expect(reserved.setups, 0);
    final bad = TestPlugin(pipelineTestBad,
        onSetup: () => throw StateError(pipelineTestSetup));
    expect(() => api.use(bad), throwsStateError);
    expect(api.inspect().map((e) => e.$2), [pipelineTestA]);
    final disabled = TestPlugin(pipelineTestDisabled, enabled: false);
    api.use(disabled);
    expect(disabled.setups, 0);
    api.use(TestPlugin(pipelineTestSetupOnly, setupOnly: true));
    expect(api.inspect().length, 1);
    expect(api.eject('absent'), isFalse);
    expect(api.eject(pipelineTestDisabled), isTrue);
    expect(api.eject(pipelineTestA), isTrue);
    expect(api.plugin<TestInstance>(), isNull);
    expect(await api.get<String>(pipelineTestRootPath), pipelineTestOk);
  });

  test(
      '[DiomanEnforce.pre][DiomanStage.outer]'
      '[Dioman.eject]'
      '[Dioman.inspect] 内置按名定位和在途保留链快照', () async {
    final gate = Completer<void>();
    var calls = 0;
    final api = testClient(plugins: [
      TestPlugin('gate', stage: DiomanStage.outer, enforce: DiomanEnforce.pre,
          handler: (ctx, next) async {
        await gate.future;
        return next();
      }),
      TestPlugin(pipelineTestDiomanCache, stage: DiomanStage.outer,
          handler: (_, next) {
        calls++;
        return next();
      }),
    ]);
    expect(api.inspect().last, (DiomanStage.source, pipelineTestDiomanCache));
    final pending =
        api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath);
    expect(api.eject(pipelineTestDiomanCache), isTrue);
    api.use(TestPlugin(pipelineTestNewValue));
    gate.complete();
    await pending;
    expect(calls, 1);
    await api.get<Object?>(pipelineTestRootPath);
    expect(calls, 1);
    expect(() => api.inspect().clear(), throwsUnsupportedError);
  });

  test('[Dioman.extend] 重新 setup，配置深拷贝和实例状态隔离', () async {
    final p = TestPlugin('state');
    final api = testClient(plugins: [p]);
    final parentExtras = api.dio.options.extra;
    parentExtras[pipelineTestNested] = {
      pipelineTestList: [1]
    };
    final child = api.extend();
    child.dio.httpClientAdapter = api.dio.httpClientAdapter;
    expect(p.setups, 2);
    await api.get<Object?>(pipelineTestRootPath);
    expect(api.plugin<TestInstance>()!.count, 1);
    expect(child.plugin<TestInstance>()!.count, 0);
    final childExtras = child.dio.options.extra;
    ((childExtras[pipelineTestNested] as Map)[pipelineTestList] as List).add(2);
    expect((parentExtras[pipelineTestNested] as Map)[pipelineTestList], [1]);
    final overridden = api.extend(
        options: BaseOptions(baseUrl: pipelineTestHttpsOtherTest), plugins: []);
    expect(overridden.dio.options.baseUrl, pipelineTestHttpsOtherTest);
    expect(overridden.inspect(), isEmpty);
    child.dispose();
    api.dispose();
    overridden.dispose();
  });

  test(
      '[DiomanPluginInstance.dispose]'
      '[DiomanPluginInstance.handle]'
      '[Dioman.dispose] 先取消，再逆序尽力释放，抛首错且拒绝后续请求', () async {
    final order = <String>[];
    final first = StateError(pipelineTestFirst);
    final api = testClient(plugins: [
      TestPlugin(pipelineTestA, onDispose: () {
        order.add(pipelineTestA);
        throw StateError('last');
      }),
      TestPlugin(pipelineTestB, onDispose: () {
        order.add(pipelineTestB);
        throw first;
      }),
      TestPlugin(pipelineTestWait,
          handler: (ctx, _) async {
            await ctx.wait(Completer<void>().future);
            return ctx.cancelled()!;
          },
          onDispose: () => order.add(pipelineTestWait)),
    ]);
    final pending =
        api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath);
    expect(() => api.dispose(), throwsA(same(first)));
    expect(order, [pipelineTestWait, pipelineTestB, pipelineTestA]);
    expect((await pending).kind, DiomanKind.cancel);
    api.dispose();
    await expectLater(
        api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath),
        throwsStateError);
    expect(() => api.use(TestPlugin(pipelineTestNewValue)), throwsStateError);
    expect(() => api.extend(), throwsStateError);
    expect(api.pending, 0);
  });

  test('[Dioman.new] 无效 debug、构造前重名验证和失败 setup 释放已安装实例', () {
    expect(() => testClient(debug: 3), throwsArgumentError);
    final p = TestPlugin(pipelineTestA);
    expect(() => testClient(plugins: [p, p]), throwsArgumentError);
    expect(p.setups, 0);
    final events = <String>[];
    expect(
        () => testClient(plugins: [
              TestPlugin(pipelineTestDisabled, enabled: false),
              TestPlugin(pipelineTestOk, onDispose: () {
                events.add(pipelineTestDispose);
                throw StateError('cleanup');
              }),
              TestPlugin(pipelineTestSetupOnly, setupOnly: true),
              TestPlugin(pipelineTestBad,
                  onSetup: () => throw ArgumentError(pipelineTestOriginal))
            ]),
        throwsArgumentError);
    expect(events, [pipelineTestDispose]);
    testClient().dispose();
  });
}

/// 在请求登记后模拟配置 getter 抛错。
class _BadCall extends DiomanCall {
  /// 先提供可联动用户令牌。
  _BadCall(CancelToken token) : super(cancelToken: token);

  /// 在 compose 前抛错。
  @override
  Map<String, dynamic>? get headers => throw StateError('construct');
}

/// 在请求视图构造时才抛错，覆盖登记后的上下文构造边界。
class _BadContextCall extends DiomanCall {
  /// 提供可解除的用户取消联动。
  _BadContextCall(CancelToken token) : super(cancelToken: token);

  /// 在不可变调用选项快照构造时抛错。
  @override
  Map<DiomanOptionKey, Object?> get options =>
      throw StateError('context construction');
}
