import '../support/constants.dart';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 最外层落定规则及用户配置合并。
void main() {
  test(
      '[DiomanKind.offline][DiomanResponseFactory.fail]'
      '[INV-context-lifecycle]'
      '[DiomanResponseFactory.create] debug 派生工厂抛错不进入 reject，原栈抛出', () async {
    final bug = StateError('debug factory');
    var rejected = 0;
    final api = testClient(
        debug: true,
        response: DiomanResponseFactory(create: (r) {
          if (r.callSite != null) throw bug;
          return r;
        }),
        reject: (r) {
          rejected++;
          return r;
        },
        plugins: [
          TestPlugin('failure',
              handler: (ctx, _) async =>
                  ctx.fail(const DiomanFailure(kind: DiomanKind.offline)))
        ]);
    await expectLater(
        api.get<Object?>(pipelineTestRootPath), throwsA(same(bug)));
    expect(rejected, 0);
    expect(api.pending, 0);
  });
  for (final debug in [false, true, pipelineTestLogger]) {
    for (final kind in [DiomanKind.ok, DiomanKind.http, DiomanKind.internal]) {
      test(
          '[DiomanResponse.errorStack]'
          '[Dioman.send] 九格落定 debug=$debug kind=$kind', () async {
        final bug = StateError(pipelineTestOriginal);
        final stack = StackTrace.fromString(pipelineTestOriginalStack);
        var rejected = 0;
        final api = testClient(
            debug: debug == pipelineTestLogger ? (String _) {} : debug,
            reject: (r) {
              rejected++;
              return r;
            },
            plugins: [
              TestPlugin('result',
                  handler: (ctx, _) async => ctx.fail(DiomanFailure(
                      kind: kind,
                      status: kind == DiomanKind.http ? 503 : 200,
                      data: kind == DiomanKind.ok ? 7 : null,
                      error: bug,
                      errorStack: stack)))
            ]);
        if (kind == DiomanKind.internal) {
          for (final pending in [
            api.send<int>(pipelineTestGetMethod, pipelineTestX),
            api.get<int>(pipelineTestX)
          ]) {
            try {
              await pending;
              fail('必须抛出 bug');
            } catch (e, s) {
              expect(e, same(bug));
              expect(s.toString(), contains(pipelineTestOriginalStack));
            }
          }
          expect(rejected, 0);
        } else {
          final r = await api.send<int>(pipelineTestGetMethod, pipelineTestX);
          expect(r.kind, kind);
          expect(r.callSite != null, kind != DiomanKind.ok && debug != false);
          if (kind == DiomanKind.ok) {
            expect(await api.get<int>(pipelineTestX), 7);
            expect(rejected, 0);
          } else {
            await expectLater(
                api.get<int>(pipelineTestX), throwsA(isA<DiomanResponse>()));
            expect(rejected, 1);
          }
        }
        expect(api.pending, 0);
      });
    }
  }
  test(
      '[Dioman.delete]'
      '[Dioman.head]'
      '[Dioman.patch]'
      '[Dioman.post]'
      '[Dioman.put]'
      '[Dioman.request] 所有动词、一次合并、Dio 拦截器和 HTTP 全放行', () async {
    final network = FakeNetwork();
    final api = testClient(network: network);
    api.dio.options.headers[pipelineTestBase] = 1;
    api.dio.options.queryParameters[pipelineTestBase] = 2;
    api.dio.options.connectTimeout = const Duration(seconds: 3);
    var intercepts = 0;
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      intercepts++;
      h.next(o);
    }));
    final call = DiomanCall(
        headers: {pipelineTestCall: 3},
        connectTimeout: const Duration(seconds: 4),
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6));
    final verbs = <Future<Object?> Function(String,
        {Map<String, dynamic>? query, Object? data, DiomanCall? call})>[
      api.get,
      api.post,
      api.put,
      api.patch,
      api.delete,
      api.head,
    ];
    for (final verb in verbs) {
      expect(
          await verb(pipelineTestR,
              query: {pipelineTestLocal: 4}, data: 'body', call: call),
          pipelineTestOk);
    }
    expect(intercepts, 6);
    expect(network.sends.map((s) => s.options.method), [
      pipelineTestGetMethod,
      pipelineTestPOST,
      pipelineTestPUT,
      'PATCH',
      'DELETE',
      'HEAD'
    ]);
    for (final send in network.sends) {
      expect(send.options.headers[pipelineTestBase], 1);
      expect(send.options.headers[pipelineTestCall], 3);
      expect(send.options.queryParameters,
          {pipelineTestBase: 2, pipelineTestLocal: 4});
      expect(send.options.connectTimeout, const Duration(seconds: 4));
      expect(send.options.validateStatus(503), isTrue);
      expect(send.options.cancelToken, isNotNull);
    }
    network.routes['GET:/fail'] = [const FakeReply(status: 503)];
    final failed = await api.send<int>(pipelineTestGetMethod, pipelineTestFail);
    expect(failed.kind, DiomanKind.http);
    expect(failed.raw!.statusCode, 503);
  });
  test('[Dioman.reject] 仅动词可预期失败转换，send 保持结果，debug 不修改原对象', () async {
    Result? shared;
    final converted = ArgumentError('converted');
    final api = testClient(debug: true, reject: (_) => converted, plugins: [
      TestPlugin('shared',
          handler: (ctx, _) async =>
              shared ??= ctx.fail(const DiomanFailure(kind: DiomanKind.biz))),
    ]);
    expect(
        (await api.send<Object?>(pipelineTestGetMethod, pipelineTestRootPath))
            .callSite,
        isNotNull);
    expect(shared!.callSite, isNull);
    await expectLater(
        api.get<Object?>(pipelineTestRootPath), throwsA(same(converted)));
    final plain = testClient(plugins: [
      TestPlugin('fail',
          handler: (ctx, _) async =>
              ctx.fail(const DiomanFailure(kind: DiomanKind.biz)))
    ]);
    await expectLater(plain.get<Object?>(pipelineTestRootPath),
        throwsA(isA<DiomanResponse>()));
  });
}
