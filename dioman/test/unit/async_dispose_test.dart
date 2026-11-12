import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import '../support/helpers.dart';
import '../support/fake_network.dart';

/// 被移除插件的测试名称。
const _diomanEjectedName = 'ejected';

/// 可异步清理的插件工厂。
class _DiomanCleanupPlugin extends DiomanPlugin<Result> {
  /// 保存名称与清理回调。
  _DiomanCleanupPlugin(this.name, this.cleanup);

  /// 插件名称。
  @override
  final String name;

  /// 清理动作。
  final FutureOr<void> Function() cleanup;

  /// 创建异步实例。
  @override
  DiomanPluginInstance<Result> setup(Dioman<Result> client) =>
      _DiomanCleanup(cleanup);
}

/// 直通请求并支持异步清理的实例。
class _DiomanCleanup extends DiomanPluginInstance<Result> {
  /// 保存清理动作。
  _DiomanCleanup(this.cleanup);

  /// 清理动作。
  final FutureOr<void> Function() cleanup;

  /// 请求直通。
  @override
  Future<Result> handle(DiomanContext<Result> ctx, DiomanNext<Result> next) =>
      next();

  /// 返回清理完成信号。
  @override
  FutureOr<void> dispose() => cleanup();
}

/// 客户端异步销毁的最低层契约。
void main() {
  for (final fails in [false, true]) {
    test('[Dioman.eject][Dioman.dispose] 跟踪已移除实例的异步清理 fails=$fails', () async {
      final gate = Completer<void>();
      final bug = StateError('ejected cleanup failure');
      final stack = StackTrace.fromString('ejected original stack');
      var cleanups = 0;
      final api = Dioman<Result>(dio: Dio(), plugins: [
        _DiomanCleanupPlugin(_diomanEjectedName, () async {
          cleanups++;
          await gate.future;
          if (fails) Error.throwWithStackTrace(bug, stack);
        }),
      ]);
      expect(api.eject(_diomanEjectedName), isTrue);
      expect(api.inspect(), isEmpty);
      if (fails) {
        gate.complete();
        await flush();
      }
      final done = api.dispose();
      var finished = false;
      final observed = done.then((_) {
        finished = true;
      }, onError: (Object error, StackTrace trace) {
        expect(error, same(bug));
        expect(trace.toString(), stack.toString());
        finished = true;
      });
      expect(() => api.eject(_diomanEjectedName), throwsStateError);
      if (!fails) {
        await flush();
        expect(finished, isFalse);
        gate.complete();
      }
      await observed;
      expect(finished, isTrue);
      expect(cleanups, 1);
    });
  }

  test('[DiomanPluginInstance.dispose] 安装回滚保留 setup 原错并隔离异步清理错误', () async {
    final bug = StateError('setup failure');
    var cleaned = false;
    expect(
        () => Dioman<Result>(dio: Dio(), plugins: [
              _DiomanCleanupPlugin('async-cleanup', () async {
                await Future<void>.value();
                cleaned = true;
                throw StateError('ignored cleanup failure');
              }),
              TestPlugin('bad-setup', onSetup: () => throw bug),
            ]),
        throwsA(same(bug)));
    await flush();
    expect(cleaned, isTrue);
  });

  test('[Dioman.dispose][DiomanPluginInstance.dispose] 立即取消和拒绝，逆序等待，重复同一信号',
      () async {
    final gate = Completer<void>();
    final networkGate = Completer<void>();
    final events = <int>[];
    final api = Dioman<Result>(
        dio: Dio()
          ..httpClientAdapter = (FakeNetwork()
            ..routes['GET:/pending'] = [FakeReply(gate: networkGate.future)]),
        plugins: [
          _DiomanCleanupPlugin('first', () {
            events.add(1);
          }),
          _DiomanCleanupPlugin('last', () async {
            events.add(2);
            await gate.future;
            events.add(3);
          }),
        ]);
    final pending = api.send<Object?>('GET', '/pending');
    await flush();
    final done = api.dispose();
    var finished = false;
    final observed = done.then((_) {
      finished = true;
    });
    expect(api.dispose(), same(done));
    await expectLater(api.get<Object?>('/new'), throwsStateError);
    expect(failureOf(await pending)?.kind, DiomanFailureKind.cancel);
    expect(networkGate.isCompleted, isFalse);
    expect(events, [2]);
    expect(finished, isFalse);
    gate.complete();
    await observed;
    expect(events, [2, 3, 1]);
    expect(api.pending, 0);
    expect(api.dispose(), same(done));
    networkGate.complete();
  });

  test('[Dioman.dispose][DiomanPluginInstance.dispose] 尽力清理全部并原栈抛首个同步或异步错误',
      () async {
    for (final asyncFirst in [false, true]) {
      final bug = StateError('first cleanup error');
      final stack = StackTrace.fromString('original cleanup stack');
      final events = <int>[];
      final api = Dioman<Result>(dio: Dio(), plugins: [
        _DiomanCleanupPlugin('one', () {
          events.add(1);
        }),
        _DiomanCleanupPlugin('two', () {
          events.add(2);
          throw StateError('later');
        }),
        _DiomanCleanupPlugin('three', () {
          events.add(3);
          if (asyncFirst) return Future<void>.error(bug, stack);
          Error.throwWithStackTrace(bug, stack);
        }),
        TestPlugin('setup-only', setupOnly: true),
      ]);
      final done = api.dispose();
      try {
        await done;
        fail('应抛清理错误');
      } catch (e, s) {
        expect(e, same(bug));
        expect(s.toString(), stack.toString());
      }
      expect(events, [3, 2, 1]);
      expect(api.dispose(), same(done));
    }
  });
}
