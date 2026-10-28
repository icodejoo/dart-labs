import '../support/pipeline/constants.dart';
import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';
import '../support/pipeline/invariant_harness.dart';

/// 使用真实 Dio 转换器和假 adapter 验证传输边界。
void main() {
  test('[Dioman.send] Dio 拦截器 reject 的 bug 保留原始对象和原始栈', () async {
    final api = testClient();
    final bug = StateError('interceptor bug');
    final stack = StackTrace.fromString('sentinel-original-interceptor-stack');
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(
          DioException(requestOptions: options, error: bug, stackTrace: stack));
    }));
    try {
      await api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath);
      fail('必须抛出原始异常');
    } catch (e, s) {
      expect(e, same(bug));
      expect(s.toString(), stack.toString());
    }
    expect(api.pending, 0);
  });
  test('[Dioman.cancelAll] 实际 Dio 发送中取消，迟到网络结果不会恢复请求', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final network = FakeNetwork(onSend: (_) => entered.complete());
    network.routes['GET:/pending'] = [FakeReply(gate: gate.future)];
    final api = testClient(network: network);
    final pending = api.send<Object?>(pipelineTestGetMethod, '/pending');
    await entered.future;
    expect(network.sends.length, 1);
    expect(api.cancelAll(), 1);
    expect((await pending).kind, DiomanKind.cancel);
    expect(api.pending, 0);
    gate.complete();
    await flush();
    expect(api.pending, 0);
  });
  test('[DiomanContext.markReplayable] I7 嵌套请求体经原地修改 Transformer 后每次发送一致',
      () async {
    final network = FakeNetwork();
    final clock = FakeClock();
    final harness = InvariantHarness(network, clock);
    final api = testClient(network: network, clock: clock, plugins: [
      ...harness.probes(),
      TestPlugin(pipelineTestReplay, handler: (ctx, next) async {
        ctx.markReplayable();
        await next();
        return next();
      }),
    ]);
    api.dio.transformer = _MutatingTransformer();
    final data = {
      pipelineTestItems: [
        {pipelineTestN: 0}
      ]
    };
    await harness.track(
        1,
        api.post<Object?>('/replay',
            data: data,
            call: const DiomanCall(headers: {invariantRequestHeader: 'one'})));
    expect(network.sends.length, 2);
    expect(network.sends.first.body, {
      pipelineTestItems: [
        {pipelineTestN: 1}
      ]
    });
    expect(data, {
      pipelineTestItems: [
        {pipelineTestN: 0}
      ]
    });
    harness.assertAll(api);
  });

  test('[diomanTransport] FormData 克隆、不可克隆 Stream 回退并告警、debug 日志异常隔离',
      () async {
    final network = FakeNetwork();
    final logs = <String>[];
    final api = testClient(network: network, debug: logs.add, plugins: [
      TestPlugin(pipelineTestReplay, handler: (ctx, next) async {
        ctx.markReplayable();
        await next();
        return next();
      }),
    ]);
    final form = FormData.fromMap({pipelineTestA: pipelineTestB});
    await api.post<Object?>('/form', data: form);
    expect(form.isFinalized, isFalse);
    expect(network.sends.length, 2);
    expect(logs, isEmpty);
    final stream = Stream<List<int>>.fromIterable([
      [1, 2]
    ]).asBroadcastStream();
    final ctx = testContext(
        request: DiomanRequest(RequestOptions(
            path: '/stream',
            baseUrl: pipelineTestHttpsExampleTest,
            data: stream)),
        log: logs.add);
    ctx.markReplayable();
    await diomanTransport(api.dio, ctx);
    expect(logs, ['请求体无法克隆，回退原引用']);
    final throwLog = testClient(
        debug: (String _) => throw StateError(pipelineTestLog),
        plugins: [
          TestPlugin(pipelineTestLog, handler: (ctx, next) {
            ctx.log('notification');
            return next();
          })
        ]);
    expect(await throwLog.get<String>(pipelineTestRootPath), pipelineTestOk);
  });

  test('[diomanTransport] 取消前不发送、传输 bug 原栈、原始 Dio 拦截器主动 reject', () async {
    final network = FakeNetwork();
    final api = testClient(network: network);
    final token = CancelToken()..cancel();
    final ctx = testContext(token: token);
    expect((await diomanTransport(api.dio, ctx)).kind, DiomanKind.cancel);
    expect(network.sends, isEmpty);
    final bug = StateError('transformer');
    api.dio.transformer = _ThrowTransformer(bug);
    await expectLater(api.post<Object?>('/bug', data: {}), throwsA(same(bug)));
    expect(api.pending, 0);
    final rejected = testClient();
    rejected.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) => h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: o, statusCode: 418)))));
    expect(
        (await rejected.send<Object?>(
                pipelineTestGetMethod, pipelineTestRootPath))
            .status,
        418);
  });
}

/// 在嵌套结构上原地改值，避免浅拷贝掩盖重放污染。
class _MutatingTransformer extends SyncTransformer {
  /// 修改后交给 Dio 的真实编码。
  @override
  Future<String> transformRequest(RequestOptions options) async {
    final item =
        ((options.data as Map)[pipelineTestItems] as List).first as Map;
    item[pipelineTestN] = (item[pipelineTestN] as int) + 1;
    return super.transformRequest(options);
  }
}

/// 模拟用户 Transformer 的程序 bug。
class _ThrowTransformer extends SyncTransformer {
  /// 保存原异常。
  _ThrowTransformer(this.bug);

  /// 原始异常对象。
  final Object bug;

  /// 原样抛出。
  @override
  Future<String> transformRequest(RequestOptions options) => throw bug;
}
