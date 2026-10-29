import '../support/constants.dart';
import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 工厂规则表和扩展点的纯单元验证。
void main() {
  final request = DiomanRequest(RequestOptions(path: pipelineTestR));
  DiomanResponse<dynamic> normalize(Object? body,
          {int? status = 200,
          DiomanResponseFactory factory = const DiomanResponseFactory(),
          DiomanRequest? req,
          bool json = false}) =>
      factory.normalize(req ?? request,
          raw: Response<dynamic>(
              requestOptions: request.toRequestOptions(),
              data: body,
              statusCode: status,
              headers: Headers.fromMap({
                if (json) Headers.contentTypeHeader: [Headers.jsonContentType]
              })));

  test('[DiomanResponseFactory.normalize] 分类规则逐行：取消、超时、网络、HTTP、bug', () {
    const factory = DiomanResponseFactory();
    final table = <(DioExceptionType, Object?, DiomanKind)>[
      (DioExceptionType.cancel, null, DiomanKind.cancel),
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout
      ])
        (type, null, DiomanKind.timeout),
      (DioExceptionType.connectionError, null, DiomanKind.network),
      (DioExceptionType.badCertificate, null, DiomanKind.network),
      (
        DioExceptionType.unknown,
        const SocketException('socket'),
        DiomanKind.network
      ),
      (
        DioExceptionType.unknown,
        const HttpException('http'),
        DiomanKind.network
      ),
      (DioExceptionType.unknown, const TlsException('tls'), DiomanKind.network),
      (
        DioExceptionType.unknown,
        StateError(pipelineTestBug),
        DiomanKind.internal
      ),
      (DioExceptionType.unknown, null, DiomanKind.internal),
      (DioExceptionType.badResponse, null, DiomanKind.http),
      (
        DioExceptionType.values.firstWhere((v) => v.name == 'transformTimeout'),
        null,
        DiomanKind.internal
      ),
    ];
    for (final row in table) {
      final error = DioException(
          requestOptions: request.toRequestOptions(),
          type: row.$1,
          error: row.$2,
          response: Response(
              requestOptions: request.toRequestOptions(), statusCode: 503));
      final r = factory.normalize(request, error: error);
      expect(r.kind, row.$3);
      expect(r.status, row.$1 == DioExceptionType.badResponse ? 503 : 0);
      expect(
          r.error,
          row.$1 == DioExceptionType.cancel
              ? same(error)
              : same(row.$2 ?? error));
    }
    final noResponse = DioException(
        requestOptions: request.toRequestOptions(),
        type: DioExceptionType.badResponse);
    expect(factory.normalize(request, error: noResponse).status, 0);
    expect(factory.normalize(request, cancelled: true).kind, DiomanKind.cancel);
    final bug = StateError('native');
    expect(factory.normalize(request, error: bug).errorStack, isNotNull);
    final stack = StackTrace.fromString(pipelineTestOriginal);
    final r = factory.normalize(request, error: bug, stack: stack);
    expect(r.error, same(bug));
    expect(r.errorStack, same(stack));
  });

  test(
      '[Envelope.message]'
      '[DiomanResponseFactory.new(envelope)] 终审识别、开关、业务码边界及逻辑状态', () {
    expect(normalize({pipelineTestCode: 0, pipelineTestData: 7}).data, 7);
    expect(normalize({pipelineTestCode: 0, pipelineTestData: 7}).kind,
        DiomanKind.ok);
    expect(
        normalize({pipelineTestCode: '0', pipelineTestMessage: pipelineTestOk})
            .ok,
        isTrue);
    expect(
        normalize({pipelineTestCode: null, pipelineTestData: null}).ok, isTrue);
    expect(
        normalize({pipelineTestCode: 401, pipelineTestMessage: 'expired'})
            .status,
        401);
    expect(normalize({pipelineTestCode: 'TOKEN', pipelineTestData: null}).kind,
        DiomanKind.biz);
    expect(
        normalize({pipelineTestCode: 399, pipelineTestData: null}).status, 200);
    expect(
        normalize({pipelineTestCode: 600, pipelineTestData: null}).status, 200);
    expect(
        normalize({pipelineTestCode: 599, pipelineTestData: null}).status, 599);
    expect(
        normalize({pipelineTestCode: 400, pipelineTestData: null}).status, 400);
    for (final body in [
      null,
      pipelineTestEmpty,
      'raw',
      {pipelineTestCode: 401},
      {pipelineTestData: 1},
      {pipelineTestMessage: pipelineTestXValue}
    ]) {
      expect(normalize(body).kind, DiomanKind.ok);
    }
    expect(normalize(pipelineTestXValue, status: null).kind, DiomanKind.http);
    expect(normalize(pipelineTestXValue, status: 199).kind, DiomanKind.http);
    expect(normalize(pipelineTestXValue, status: 300).kind, DiomanKind.http);
    expect(
        normalize({pipelineTestCode: 0, pipelineTestData: 1}, status: 500).kind,
        DiomanKind.http);
    final plain = DiomanRequest(request.toRequestOptions(),
        call: const DiomanCall(envelope: false));
    expect(
        normalize({pipelineTestCode: 500, pipelineTestData: 1}, req: plain).ok,
        isTrue);
    expect(
        normalize({pipelineTestCode: 500, pipelineTestData: 1},
                factory: const DiomanResponseFactory(envelope: null))
            .ok,
        isTrue);
    final custom = DiomanResponseFactory(
        envelope: const Envelope(
            code: pipelineTestSValue, data: pipelineTestD, message: 'm'),
        isEnvelope: (map) => map.containsKey(pipelineTestSValue),
        isSuccess: (code) => code == pipelineTestYes,
        logicalStatus: (r) => r.ok ? 201 : 403);
    expect(
        normalize({pipelineTestSValue: pipelineTestYes, pipelineTestD: 8},
                factory: custom)
            .status,
        201);
    expect(normalize({pipelineTestSValue: 'no'}, factory: custom).status, 403);
    expect(normalize({pipelineTestD: 1}, factory: custom).kind, DiomanKind.ok);
  });

  test(
      '[DiomanKind.http][DiomanKind.parse]'
      '[DiomanResponseFactory.new(expectJson)] 只对 2xx 非空声明 JSON 字符串判 parse',
      () {
    const factory = DiomanResponseFactory(expectJson: true);
    expect(normalize(pipelineTestBroken, factory: factory, json: true).kind,
        DiomanKind.parse);
    expect(normalize(pipelineTestEmpty, factory: factory, json: true).kind,
        DiomanKind.ok);
    expect(normalize(pipelineTestBroken, factory: factory).kind, DiomanKind.ok);
    expect(normalize({}, factory: factory, json: true).kind, DiomanKind.ok);
    expect(
        normalize(pipelineTestBroken, factory: factory, json: true, status: 500)
            .kind,
        DiomanKind.http);
  });

  test(
      '[DiomanFailure.errorStack][DiomanResponseFactory.isEnvelope][DiomanResponseFactory.isSuccess][DiomanResponseFactory.logicalStatus]'
      '[DiomanResponseFactory.create] 钩子 bug 和坏工厂回退保留首次异常', () {
    final bug = StateError(pipelineTestFirst);
    final second = StateError('second');
    final stack = StackTrace.fromString('first-stack');
    for (final factory in [
      DiomanResponseFactory(isEnvelope: (_) => throw bug),
      DiomanResponseFactory(isSuccess: (_) => throw bug),
      DiomanResponseFactory(logicalStatus: (_) => throw bug),
      DiomanResponseFactory(create: (_) => throw bug),
    ]) {
      final r = normalize({pipelineTestCode: 0, pipelineTestData: null},
          factory: factory);
      expect(r.kind, DiomanKind.internal);
      expect(r.error, same(bug));
      expect(r.errorStack, isNotNull);
    }
    final factory = DiomanResponseFactory(create: (_) => throw second);
    final r = factory.fail(
        request,
        DiomanFailure(
            kind: DiomanKind.internal, error: bug, errorStack: stack));
    expect(r.error, same(bug));
    expect(r.errorStack, same(stack));
    expect(
        factory
            .fail(request, const DiomanFailure(kind: DiomanKind.offline))
            .error,
        same(second));
    expect(
        const DiomanResponseFactory()
            .fail(request, const DiomanFailure(kind: DiomanKind.ok))
            .ok,
        isTrue);
    final expanded =
        DiomanResponseFactory<ExtraResult>(create: ExtraResult.new);
    expect(normalize(1, factory: expanded), isA<ExtraResult>());
  });

  test(
      '[DiomanResponse.callSite][DiomanResponse.code][DiomanResponse.copy][DiomanResponse.data][DiomanResponse.error][DiomanResponse.httpStatus][DiomanResponse.kind][DiomanResponse.ok][DiomanResponse.reason][DiomanResponse.request][DiomanResponse.status]'
      '[DiomanResponse.toString] 循环对象与恶意 toString 不影响描述和派生', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    final r = DiomanResponse(
        ok: false,
        kind: DiomanKind.biz,
        status: 400,
        httpStatus: 200,
        data: cycle,
        request: request,
        error: _BadString(),
        reason: 'denied',
        code: 400);
    expect(r.toString(), contains('biz'));
    final site = StackTrace.current;
    final copy = r.copy<Object?>(callSite: site);
    expect(copy.callSite, same(site));
    expect(copy.copy<Object?>().callSite, same(site));
    expect(r.callSite, isNull);
    expect(copy.data, same(cycle));
  });
}

/// 模拟不能被序列化或描述的用户异常。
class _BadString {
  /// 不允许描述原始异常。
  @override
  String toString() => throw StateError('不得调用');
}

/// 验证结果扩展点。
class ExtraResult extends DiomanResponse<dynamic> {
  /// 从工厂初值创建带扩展字段的结果。
  ExtraResult(DiomanResponse<dynamic> r)
      : super(
            ok: r.ok,
            kind: r.kind,
            status: r.status,
            httpStatus: r.httpStatus,
            data: r.data,
            request: r.request);
}
