import 'constants.dart';
import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'fake_clock.dart';
import 'fake_network.dart';

/// 测试共用结果类型。
typedef Result = DiomanResponse<dynamic>;

/// 测试中间件回调。
typedef Handler = Future<Result> Function(
    DiomanContext<Result>, DiomanNext<Result>);

/// 可观察 setup 和 dispose 的插件配置。
class TestPlugin extends DiomanPlugin<Result> {
  /// 创建测试插件。
  TestPlugin(this.name,
      {this.handler,
      this.stage = DiomanStage.attempt,
      this.enforce = DiomanEnforce.post,
      this.enabled = true,
      this.onSetup,
      this.onDispose,
      this.setupOnly = false});

  /// 唯一名称。
  @override
  final String name;

  /// 挂载阶段。
  @override
  final DiomanStage stage;

  /// 阶段内位置。
  @override
  final DiomanEnforce enforce;

  /// 开关。
  @override
  final bool enabled;

  /// 中间件。
  final Handler? handler;

  /// 安装观察器。
  final void Function()? onSetup;

  /// 释放观察器。
  final void Function()? onDispose;

  /// 是否只有 setup。
  final bool setupOnly;

  /// 安装次数。
  int setups = 0;

  /// 创建隔离状态实例。
  @override
  TestInstance? setup(Dioman<Result> client) {
    setups++;
    onSetup?.call();
    return setupOnly ? null : TestInstance(handler, onDispose);
  }
}

/// 独立测试实例，counter 可用于证明 extend 无共享状态。
class TestInstance extends DiomanPluginInstance<Result> {
  /// 保存回调。
  TestInstance(this.handler, this.onDispose);

  /// 执行处理器。
  final Handler? handler;

  /// 生命周期回调。
  final void Function()? onDispose;

  /// 当前实例执行数。
  int count = 0;

  /// 执行或直通。
  @override
  Future<Result> handle(DiomanContext<Result> ctx, DiomanNext<Result> next) {
    count++;
    return handler == null ? next() : handler!(ctx, next);
  }

  /// 释放本实例。
  @override
  void dispose() => onDispose?.call();
}

/// 创建使用假网络的客户端。
Dioman<Result> testClient(
        {FakeNetwork? network,
        List<DiomanPlugin<Result>> plugins = const [],
        DiomanResponseFactory<Result>? response,
        Object? debug,
        FakeClock? clock,
        Object Function(Result)? reject,
        DiomanKeyOptions key = const DiomanKeyOptions()}) =>
    Dioman<Result>(
        dio: Dio(BaseOptions(baseUrl: pipelineTestHttpsExampleTest))
          ..httpClientAdapter = network ?? FakeNetwork(),
        plugins: plugins,
        response: response,
        debug: debug,
        reject: reject,
        key: key,
        clock: clock ?? FakeClock());

/// 创建纯单元上下文，不执行客户端发送。
DiomanContext<Result> testContext(
        {CancelToken? token,
        FakeClock? clock,
        DiomanRequest? request,
        DiomanResponseFactory<Result>? factory,
        DiomanKeyOptions key = const DiomanKeyOptions(),
        DiomanLogger? log}) =>
    DiomanContext(
        id: 1,
        client: testClient(),
        request:
            request ?? DiomanRequest(RequestOptions(path: pipelineTestUnit)),
        state: DiomanContextState(token ?? CancelToken()),
        factory: factory ?? const DiomanResponseFactory<Result>(),
        keyService: DiomanKeyService(key),
        clock: clock ?? FakeClock(),
        log: log ?? (_) {});

/// 清空微任务队列，用于等待 Dio 到达假 adapter，不推进真实时钟。
Future<void> flush() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.value();
  }
}
