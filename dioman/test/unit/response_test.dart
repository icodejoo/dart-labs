import '../support/response_contract.dart';
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
    final table = <(DioExceptionType, Object?, String)>[
      (DioExceptionType.cancel, null, diomanTestCancel),
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout
      ])
        (type, null, diomanTestTimeout),
      (DioExceptionType.connectionError, null, diomanTestNetwork),
      (DioExceptionType.badCertificate, null, diomanTestNetwork),
      (
        DioExceptionType.unknown,
        const SocketException('socket'),
        diomanTestNetwork
      ),
      (
        DioExceptionType.unknown,
        const HttpException(diomanTestHttp),
        diomanTestNetwork
      ),
      (DioExceptionType.unknown, const TlsException('tls'), diomanTestNetwork),
      (
        DioExceptionType.unknown,
        StateError(pipelineTestBug),
        diomanTestInternal
      ),
      (DioExceptionType.unknown, null, diomanTestInternal),
      (DioExceptionType.badResponse, null, diomanTestHttp),
      (
        DioExceptionType.values.firstWhere((v) => v.name == 'transformTimeout'),
        null,
        diomanTestInternal
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
      expect(outcomeOf(r), row.$3);
      expect(r.status, 503);
      expect(failureOf(r)?.error,
          row.$3 == diomanTestInternal ? same(row.$2 ?? error) : isNull);
    }
    final noResponse = DioException(
        requestOptions: request.toRequestOptions(),
        type: DioExceptionType.badResponse);
    expect(factory.normalize(request, error: noResponse).status, 0);
    expect(outcomeOf(factory.normalize(request, cancelled: true)),
        diomanTestCancel);
    final bug = StateError('native');
    expect(failureOf(factory.normalize(request, error: bug))?.errorStack,
        isNotNull);
    final stack = StackTrace.fromString(pipelineTestOriginal);
    final r = factory.normalize(request, error: bug, stack: stack);
    expect(failureOf(r)?.error, same(bug));
    expect(failureOf(r)?.errorStack, same(stack));
  });

  test(
      '[DiomanParsed.message]'
      '[DiomanResponseFactory.new(parse)] 终审识别、开关、业务码边界及逻辑状态', () {
    expect(normalize({pipelineTestCode: 0, pipelineTestData: 7}).data, 7);
    expect(outcomeOf(normalize({pipelineTestCode: 0, pipelineTestData: 7})),
        diomanTestOk);
    expect(
        normalize({pipelineTestCode: '0', pipelineTestMessage: pipelineTestOk})
            .ok,
        isTrue);
    expect(
        normalize({pipelineTestCode: null, pipelineTestData: null}).ok, isTrue);
    expect(
        normalize({pipelineTestCode: 401, pipelineTestMessage: 'expired'})
            .status,
        200);
    expect(
        outcomeOf(
            normalize({pipelineTestCode: 'TOKEN', pipelineTestData: null})),
        diomanTestBiz);
    expect(
        normalize({pipelineTestCode: 399, pipelineTestData: null}).status, 200);
    expect(
        normalize({pipelineTestCode: 600, pipelineTestData: null}).status, 200);
    expect(
        normalize({pipelineTestCode: 599, pipelineTestData: null}).status, 200);
    expect(
        normalize({pipelineTestCode: 400, pipelineTestData: null}).status, 200);
    for (final body in [
      null,
      pipelineTestEmpty,
      'raw',
      {pipelineTestCode: 401},
      {pipelineTestData: 1},
      {pipelineTestMessage: pipelineTestXValue}
    ]) {
      expect(outcomeOf(normalize(body)), diomanTestOk);
    }
    expect(
        outcomeOf(normalize(pipelineTestXValue, status: null)), diomanTestHttp);
    expect(
        outcomeOf(normalize(pipelineTestXValue, status: 199)), diomanTestHttp);
    expect(
        outcomeOf(normalize(pipelineTestXValue, status: 300)), diomanTestHttp);
    expect(
        outcomeOf(
            normalize({pipelineTestCode: 0, pipelineTestData: 1}, status: 500)),
        diomanTestHttp);
    final plain = DiomanRequest(request.toRequestOptions(),
        call: const DiomanCall(extra: {'plain': true}));
    final custom = DiomanResponseFactory(
        parse: (body, raw) => raw.requestOptions.extra['plain'] == true
            ? DiomanParsed(data: body)
            : DiomanParsed(
                code: (body as Map)[pipelineTestSValue] ?? 0,
                data: body[pipelineTestD]),
        isSuccess: (code) => code == pipelineTestYes || code == 0);
    expect(
        normalize({pipelineTestCode: 500, pipelineTestData: 1},
                req: plain, factory: custom)
            .ok,
        isTrue);
    expect(
        normalize({pipelineTestSValue: pipelineTestYes, pipelineTestD: 8},
                factory: custom)
            .data,
        8);
    expect(normalize({pipelineTestSValue: 'no'}, factory: custom).ok, isFalse);
    expect(normalize({pipelineTestD: 1}, factory: custom).ok, isTrue);
  });

  test(
      '[DiomanResponse.status][DiomanFailureKind.parse]'
      '[DiomanResponseFactory.new(expectJson)] 只对 2xx 非空声明 JSON 字符串判 parse',
      () {
    const factory = DiomanResponseFactory(expectJson: true);
    expect(
        outcomeOf(normalize(pipelineTestBroken, factory: factory, json: true)),
        diomanTestParse);
    expect(
        outcomeOf(normalize(pipelineTestEmpty, factory: factory, json: true)),
        diomanTestOk);
    expect(outcomeOf(normalize(pipelineTestBroken, factory: factory)),
        diomanTestParse);
    expect(
        outcomeOf(normalize({}, factory: factory, json: true)), diomanTestOk);
    expect(
        outcomeOf(normalize(pipelineTestBroken,
            factory: factory, json: true, status: 500)),
        diomanTestHttp);
  });

  test(
      '[DiomanFailure.errorStack][DiomanResponseFactory.parse][DiomanResponseFactory.isSuccess][Dioman.statusOf]'
      '[DiomanResponseFactory.create] 钩子 bug 和坏工厂回退保留首次异常', () {
    final bug = StateError(pipelineTestFirst);
    final second = StateError('second');
    final stack = StackTrace.fromString('first-stack');
    for (final factory in [
      DiomanResponseFactory(parse: (_, __) => throw bug),
      DiomanResponseFactory(isSuccess: (_) => throw bug),
      DiomanResponseFactory(parse: (_, __) => throw bug),
      DiomanResponseFactory(create: (_) => throw bug),
    ]) {
      final r = normalize({pipelineTestCode: 0, pipelineTestData: null},
          factory: factory);
      expect(outcomeOf(r), diomanTestInternal);
      expect(r.status, 200);
      expect(failureOf(r)?.error, same(bug));
      expect(failureOf(r)?.errorStack, isNotNull);
    }
    final factory = DiomanResponseFactory(create: (_) => throw second);
    final r = factory.normalize(request, error: bug, stack: stack);
    expect(failureOf(r)?.error, same(bug));
    expect(failureOf(r)?.errorStack, same(stack));
    expect(failureOf(factory.fail(request, DiomanFailureKind.offline))?.error,
        same(second));
    expect(
        const DiomanResponseFactory()
            .fail(request, DiomanFailureKind.offline)
            .ok,
        isFalse);
    final absent = const DiomanResponseFactory().normalize(request);
    expect(absent.status, 0);
    expect(failureOf(absent)?.kind, DiomanFailureKind.internal);
    final unknown = normalize(0,
        status: null, factory: DiomanResponseFactory(create: (_) => throw bug));
    expect(unknown.status, 0);
    final expanded =
        DiomanResponseFactory<ExtraResult>(create: ExtraResult.new);
    expect(normalize(1, factory: expanded), isA<ExtraResult>());
  });

  test(
      '[DiomanResponse.callSite][DiomanResponse.code][DiomanResponse.copy][DiomanResponse.data][DiomanResponse.error][DiomanResponse.status][failureOf][DiomanResponse.ok][DiomanFailure.reason][DiomanResponse.request][DiomanResponse.status]'
      '[DiomanResponse.toString] 循环对象与恶意 toString 不影响描述和派生', () {
    final cycle = <Object?>[];
    cycle.add(cycle);
    final r = DiomanResponse(
        ok: false,
        status: 400,
        data: cycle,
        request: request,
        error: _BadString(),
        code: 400);
    expect(r.toString(), contains('400'));
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
      : super(ok: r.ok, status: r.status, data: r.data, request: r.request);
}
