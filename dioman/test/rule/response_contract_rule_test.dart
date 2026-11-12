import 'package:dioman/src/response.dart' show DiomanResponseInternal;
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';
import '../support/response_contract.dart';

/// 本文件共用的测试字面量。
const _r2aLiteral0 = 'GET';

/// 本文件共用的测试字面量。
const _r2aLiteral1 = '/contract';

/// 本文件共用的测试字面量。
const _r2aLiteral2 = 'code';

/// 本文件共用的测试字面量。
const _r2aLiteral3 = 'data';

/// 本文件共用的测试字面量。
const _r2aLiteral4 = 'original-status-stack';

/// 本文件共用的测试字面量。
const _r2aLiteral5 = 'business';

/// 本文件共用的测试字面量。
const _r2aLiteral6 = '';

/// R2a 的公开契约与扩展边界。
void main() {
  test(
      '[DiomanResponse.copy][DiomanResponseFactory.create][Dioman.send] send 与 debug 副本保留内核失败',
      () async {
    final factory = DiomanResponseFactory(
        create: (r) => DiomanResponse<dynamic>(
            ok: true,
            status: r.status,
            request: r.request,
            callSite: r.callSite));
    final api = testClient(response: factory, debug: true, plugins: [
      TestPlugin('fail',
          handler: (ctx, _) async => ctx.fail(DiomanFailureKind.offline))
    ]);
    final result = await api.send<int>(_r2aLiteral0, _r2aLiteral1);
    expect(result.ok, isFalse);
    expect(failureOf(result)?.kind, DiomanFailureKind.offline);
    expect(result.callSite, isNotNull);
  });

  test(
      '[isDiomanCancel][Dioman.isCancel][DiomanContext.cancelled] 仅 cancel 标记表示取消',
      () {
    final ctx = testContext();
    for (final kind in DiomanFailureKind.values) {
      final result = ctx.fail(kind);
      expect(isDiomanCancel(result), kind == DiomanFailureKind.cancel);
      expect(ctx.client.isCancel(result), kind == DiomanFailureKind.cancel);
    }
    expect(isDiomanCancel(null), isFalse);
    expect(isDiomanCancel(StateError(diomanTestCancel)), isFalse);
    ctx.cancelToken.cancel();
    expect(isDiomanCancel(ctx.cancelled()), isTrue);
  });

  for (final configured in [false, true]) {
    test(
        '[Dioman.new(statusOf)][Dioman.statusOf][DiomanContext.statusOf][Dioman.extend] retry/auth/breaker 使用显式有效状态 configured=$configured',
        () async {
      final clock = FakeClock();
      final retryNet = FakeNetwork()
        ..routes[b3Route] = [
          const FakeReply(body: {_r2aLiteral2: 503, _r2aLiteral3: null}),
          const FakeReply()
        ];
      final retry = testClient(
          network: retryNet,
          clock: clock,
          statusOf: configured ? businessStatus : null,
          plugins: [DiomanRetry(max: 1, delay: (_, __, ___) => Duration.zero)]);
      final retried =
          await b3Finish(retry.send<Object?>(b3ValueGet, b3Path), clock);
      expect(retryNet.sends.length, configured ? 2 : 1);
      expect(retried.status, 200);
      expect(retried.ok, configured);
      final child = retry.extend();
      addTearDown(child.dispose);
      expect(child.statusOf, same(retry.statusOf));
      final tokens = TestTokens();
      var refreshes = 0;
      final authNet = FakeNetwork()
        ..routes[b3Route] = [
          const FakeReply(body: {_r2aLiteral2: 401, _r2aLiteral3: null}),
          const FakeReply()
        ];
      final auth = testClient(
          network: authNet,
          statusOf: configured ? businessStatus : null,
          plugins: [
            b3Auth(tokens, refresh: (tm, r) {
              refreshes++;
              tm.setTokens(accessToken: 'new');
            })
          ]);
      final authed = await auth.send<Object?>(b3ValueGet, b3Path);
      expect(refreshes, configured ? 1 : 0);
      expect(authed.status, 200);
      final breakerNet = FakeNetwork()
        ..routes[b3Route] = [
          const FakeReply(body: {_r2aLiteral2: 503, _r2aLiteral3: null})
        ];
      final breaker = testClient(
          network: breakerNet,
          statusOf: configured ? businessStatus : null,
          plugins: [const DiomanBreaker(failureThreshold: 1)]);
      final first = await breaker.send<Object?>(b3ValueGet, b3Path);
      expect(first.status, 200);
      expect(first.code, 503);
      final second = await breaker.send<Object?>(b3ValueGet, b3Path);
      expect(failureOf(second)?.kind,
          configured ? DiomanFailureKind.breaker : null);
      final ctx = DiomanContext(
          id: 1,
          client: breaker,
          request: first.request,
          factory: breaker.response,
          keyService: DiomanKeyService(breaker.key),
          clock: clock,
          log: (_) {});
      expect(ctx.statusOf(first), configured ? 503 : 200);
    });
  }

  test('[DiomanContext.statusOf][Dioman.send] statusOf 抛错链内 internal 且落定保留原栈',
      () async {
    final bug = StateError('status mapper');
    final stack = StackTrace.fromString(_r2aLiteral4);
    DiomanResponse<dynamic>? seen;
    final api = testClient(
        statusOf: (_) => Error.throwWithStackTrace(bug, stack),
        plugins: [
          TestPlugin('observe', stage: DiomanStage.outer,
              handler: (ctx, next) async {
            seen = await next();
            return seen!;
          }),
          const DiomanRetry(max: 1)
        ]);
    try {
      await api.send<Object?>(_r2aLiteral0, _r2aLiteral1);
      fail('必须抛出原异常');
    } catch (error, actualStack) {
      expect(error, same(bug));
      expect(actualStack.toString(), contains(_r2aLiteral4));
    }
    expect(failureOf(seen!)?.kind, DiomanFailureKind.internal);
    expect(api.pending, 0);
  });

  test(
      '[DiomanRetry.afterStatusCodes][DiomanContext.statusOf] 业务 Retry-After 读取有效状态',
      () async {
    final clock = FakeClock();
    var sends = 0;
    final api = testClient(clock: clock, statusOf: businessStatus, plugins: [
      DiomanRetry(max: 1, delay: (_, __, ___) => Duration.zero),
      TestPlugin(_r2aLiteral5, stage: DiomanStage.source,
          handler: (ctx, _) async {
        sends++;
        final result = ctx.factory.normalize(ctx.request,
            raw: Response<dynamic>(
                requestOptions: ctx.request.toRequestOptions(),
                statusCode: 200,
                data: {_r2aLiteral2: sends == 1 ? 503 : 0, _r2aLiteral3: null},
                headers: Headers.fromMap({
                  'retry-after': ['2']
                })));
        DiomanResponseInternal.setRetryAfter(result, '2');
        return result;
      })
    ]);
    final pending = api.send<Object?>(_r2aLiteral0, _r2aLiteral1);
    await b3Turn();
    clock.elapse(const Duration(seconds: 1));
    await b3Turn();
    expect(sends, 1);
    clock.elapse(const Duration(seconds: 1));
    expect((await pending).ok, isTrue);
    expect(sends, 2);
  });

  test('[DiomanNotify.defaultStringify] 默认文案读取失败类别与 HTTP 状态', () {
    final ctx = testContext();
    final request = ctx.request;
    for (final kind in DiomanFailureKind.values) {
      final result = ctx.fail(kind);
      expect(
          DiomanNotify.defaultStringify(result, ctx),
          kind == DiomanFailureKind.cancel || kind == DiomanFailureKind.internal
              ? _r2aLiteral6
              : '${kind.name} http 0');
    }
    expect(
        DiomanNotify.defaultStringify(
            DiomanResponse(ok: false, status: 503, request: request), ctx),
        'http 503');
    expect(
        DiomanNotify.defaultStringify(
            DiomanResponse(
                ok: false,
                status: 200,
                code: 1,
                message: _r2aLiteral5,
                request: request),
            ctx),
        _r2aLiteral5);
    expect(
        DiomanNotify.defaultStringify(
            DiomanResponse(ok: true, status: 200, request: request), ctx),
        _r2aLiteral6);
    final silent = ctx.derive(const RequestPatch());
    final silentCtx = testContext(
        request: DiomanRequest(silent.request.toRequestOptions(),
            call: const DiomanCall(silent: true)));
    expect(
        DiomanNotify.defaultStringify(
            silentCtx.fail(DiomanFailureKind.offline), silentCtx),
        _r2aLiteral6);
  });
}
