import 'package:dioman/src/stages.dart';
import 'package:dioman/src/pipeline.dart';
import '../support/constants.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

/// 阶段排序及每层异常边界的纯单元验证。
void main() {
  test(
      '[DiomanEnforce.post][DiomanStage.attempt]'
      '[INV-pipeline-internals]'
      '[DiomanPlugin.enforce]'
      '[DiomanPlugin.setup] 默认接口、空日志器与独立实例', () async {
    final plugin = _DefaultPlugin();
    expect(plugin.stage, DiomanStage.attempt);
    expect(plugin.enforce, DiomanEnforce.post);
    expect(plugin.enabled, isTrue);
    final api = testClient(plugins: [plugin]);
    expect(await api.get<String>(pipelineTestRootPath), pipelineTestOk);
    api.dispose();
  });
  test(
      '[INV-pipeline-internals][INV-pipeline-internals]'
      '[INV-pipeline-internals]'
      '[DiomanStage] 内置位置按名称、pre/post 稳定排序及空链', () async {
    final plugins = <TestPlugin>[
      for (final names in diomanBuiltinStages.values.toList().reversed)
        for (final name in names.reversed)
          TestPlugin(name, stage: DiomanStage.outer),
      TestPlugin(pipelineTestPost1),
      TestPlugin(pipelineTestPost2),
      TestPlugin(pipelineTestPre, enforce: DiomanEnforce.pre),
      TestPlugin(pipelineTestOuter, stage: DiomanStage.outer),
      TestPlugin(pipelineTestSetup, setupOnly: true),
    ];
    validateDiomanPlugins(plugins);
    final client = testClient();
    final layers = sortDiomanPipeline(
        plugins.map((p) => DiomanRegistration(p, p.setup(client))).toList());
    expect(layers.map((r) => r.plugin.name).toList(), [
      'dioman:loading',
      'dioman:notify',
      pipelineTestOuter,
      'dioman:repath',
      'dioman:filter',
      'dioman:timeout',
      pipelineTestPre,
      'dioman:retry',
      'dioman:breaker',
      pipelineTestPost1,
      pipelineTestPost2,
      'dioman:auth',
      'dioman:mock',
      'dioman:share',
      pipelineTestDiomanCache,
      'dioman:offline',
    ]);
    expect(
        () => validateDiomanPlugins(
            [TestPlugin(pipelineTestA), TestPlugin(pipelineTestA)]),
        throwsArgumentError);
    expect(() => validateDiomanPlugins([TestPlugin(pipelineTestDiomanUnknown)]),
        throwsArgumentError);
    final ctx = testContext();
    final result = ctx.fail(const DiomanFailure(kind: DiomanKind.offline));
    expect(await compileDiomanPipeline<Result>([], (_) async => result)(ctx),
        same(result));
  });

  test(
      '[DiomanContext.client][DiomanContext.fail][DiomanContext.request][RequestPatch.path]'
      '[DiomanNext] 无补丁复用外层，有补丁派生，第二次 next 不继承第一次补丁', () async {
    final ctx = testContext();
    final seen = <DiomanContext<Result>>[];
    final plugin = TestPlugin('twice', handler: (c, next) async {
      expect(c, same(ctx));
      await next(const RequestPatch(path: pipelineTestInner));
      return next();
    });
    final run = compileDiomanPipeline<Result>(
        [DiomanRegistration(plugin, plugin.setup(ctx.client))], (inner) async {
      seen.add(inner);
      return inner.fail(const DiomanFailure(kind: DiomanKind.ok));
    });
    await run(ctx);
    expect(seen.first, isNot(same(ctx)));
    expect(seen.first.request.path, pipelineTestInner);
    expect(seen.last, same(ctx));
    expect(seen.last.request.path, pipelineTestUnit);
  });

  for (final async in [false, true]) {
    test('[DiomanNext] ${async ? '异步' : '同步'}中间件异常转 internal，外层继续收尾', () async {
      final bug = StateError(pipelineTestBug);
      final stack = StackTrace.fromString(pipelineTestOriginalStack);
      final ctx = testContext();
      final events = <String>[];
      final plugins = [
        TestPlugin(pipelineTestOuter, handler: (ctx, next) async {
          events.add(pipelineTestPre);
          final r = await next();
          events.add(r.kind.name);
          return r;
        }),
        TestPlugin(pipelineTestBad, handler: (_, __) {
          if (async) return Future.error(bug, stack);
          Error.throwWithStackTrace(bug, stack);
        }),
      ];
      final run = compileDiomanPipeline<Result>(
          plugins
              .map((p) => DiomanRegistration(p, p.setup(ctx.client)))
              .toList(),
          (_) async => throw StateError('unreachable'));
      final r = await run(ctx);
      expect(events, [pipelineTestPre, 'internal']);
      expect(r.error, same(bug));
      expect(r.errorStack.toString(), contains(pipelineTestOriginalStack));
    });
  }
  test(
      '[DiomanKind.ok][INV-pipeline-internals][RequestPatch.sendTimeout][INV-pipeline-internals]'
      '[DiomanNext] 补丁构造异常也作为结果返回', () async {
    final ctx = testContext();
    final plugin = TestPlugin('patch',
        handler: (_, next) =>
            next(const RequestPatch(sendTimeout: pipelineTestBad)));
    final run = compileDiomanPipeline<Result>(
        [DiomanRegistration(plugin, plugin.setup(ctx.client))],
        (c) async => c.fail(const DiomanFailure(kind: DiomanKind.ok)));
    expect((await run(ctx)).kind, DiomanKind.internal);
  });
}

/// 使用基类默认配置的插件。
class _DefaultPlugin extends DiomanPlugin<Result> {
  /// 自定义名称。
  @override
  String get name => pipelineTestDefault;

  /// 创建无状态实例。
  @override
  DiomanPluginInstance<Result> setup(Dioman<Result> client) =>
      _DefaultInstance();
}

/// 使用默认 dispose 的直通实例。
class _DefaultInstance extends DiomanPluginInstance<Result> {
  /// 即使 debug 关闭也可安全调用日志。
  @override
  Future<Result> handle(DiomanContext<Result> ctx, DiomanNext<Result> next) {
    ctx.log(pipelineTestDefault);
    return next();
  }
}
