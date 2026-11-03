import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 本文件共用的测试字面量。
const _r2aLiteral0 = '/contract';

/// 本文件共用的测试字面量。
const _r2aLiteral1 = 'detail';

/// 本文件共用的测试字面量。
const _r2aLiteral2 = 'data';

/// 本文件共用的测试字面量。
const _r2aLiteral3 = 'message';

/// 本文件共用的测试字面量。
const _r2aLiteral4 = 'code';

/// 本文件共用的测试字面量。
const _r2aLiteral5 = '';

/// 本文件共用的测试字面量。
const _r2aLiteral6 = '0';

/// 本文件共用的测试字面量。
const _r2aLiteral7 = 'm';

/// R2a 纯响应契约，不创建客户端。
void main() {
  test(
      '[failureOf][DiomanResponse.ok][DiomanResponseFactory.create] create 的成功值不能覆盖内核失败，派生均保留标记',
      () async {
    final request = DiomanRequest(RequestOptions(path: _r2aLiteral0));
    final factory = DiomanResponseFactory(
        create: (r) => DiomanResponse<dynamic>(
            ok: true,
            status: r.status,
            request: r.request,
            callSite: r.callSite));
    for (final kind in DiomanFailureKind.values) {
      final result = factory.fail(request, kind, reason: _r2aLiteral1);
      for (final copy in [
        result,
        result.copy<int>(),
        factory.derive(result, null)
      ]) {
        expect(copy.ok, isFalse);
        expect(failureOf(copy)?.kind, kind);
        expect(failureOf(copy)?.reason, _r2aLiteral1);
      }
    }
  });
  test(
      '[DiomanParsed][DiomanParsed.new][DiomanParsed.code][DiomanParsed.data][DiomanParsed.message][DiomanResponseFactory.parse] 默认解析门槛、缺省值与成功规则',
      () {
    final request = DiomanRequest(RequestOptions(path: _r2aLiteral0));
    const factory = DiomanResponseFactory();
    DiomanResponse<dynamic> parse(Object? body, [int status = 200]) =>
        factory.normalize(request,
            raw: Response<dynamic>(
                requestOptions: request.toRequestOptions(),
                statusCode: status,
                data: body));
    for (final body in [
      null,
      {_r2aLiteral2: 7},
      {_r2aLiteral3: 'plain'},
      {_r2aLiteral4: 401},
      [1],
      'text'
    ]) {
      final result = parse(body);
      expect(result.data, same(body));
      expect(result.code, 0);
      expect(result.message, _r2aLiteral5);
      expect(result.ok, isTrue);
      expect(failureOf(result), isNull);
    }
    for (final code in [0, _r2aLiteral6, 1, '0000', 'other']) {
      final result = parse({_r2aLiteral4: code, _r2aLiteral2: 7});
      expect(result.data, 7);
      expect(result.code, code);
      expect(result.ok, code == 0 || code == _r2aLiteral6);
      expect(failureOf(result), isNull);
      expect(parse({_r2aLiteral4: code, _r2aLiteral3: _r2aLiteral7}).message,
          _r2aLiteral7);
      expect(parse({_r2aLiteral4: code, _r2aLiteral2: 7}, 500).ok, isFalse);
    }
    expect(parse({_r2aLiteral4: null, _r2aLiteral2: null}).code, 0);
    expect(parse({_r2aLiteral4: 0, _r2aLiteral3: null}).data, isNull);
    final result =
        DiomanResponse<dynamic>(ok: true, status: 200, request: request);
    expect([result.code, result.message, result.data], [0, _r2aLiteral5, null]);
  });

  test('[isDiomanCancel] 无标记与非取消失败不能伪装取消', () {
    final request = DiomanRequest(RequestOptions(path: _r2aLiteral0));
    const factory = DiomanResponseFactory();
    expect(isDiomanCancel(factory.fail(request, DiomanFailureKind.cancel)),
        isTrue);
    expect(isDiomanCancel(factory.fail(request, DiomanFailureKind.timeout)),
        isFalse);
    expect(
        isDiomanCancel(DiomanResponse(ok: false, status: 0, request: request)),
        isFalse);
  });
  test(
      '[DiomanResponseFactory.create][DiomanResponse.error][DiomanResponse.errorStack] create 不能丢弃首次 internal 异常与栈',
      () {
    final request = DiomanRequest(RequestOptions(path: _r2aLiteral0));
    final error = StateError('original');
    final stack = StackTrace.fromString('original-stack');
    for (final keepError in [false, true]) {
      final factory = DiomanResponseFactory(
          create: (r) => DiomanResponse<dynamic>(
              ok: true,
              status: r.status,
              request: r.request,
              error: keepError ? r.error : null));
      final result = factory.normalize(request, error: error, stack: stack);
      expect(result.ok, isFalse);
      expect(failureOf(result)?.kind, DiomanFailureKind.internal);
      expect(result.error, same(error));
      expect(result.errorStack, same(stack));
    }
  });
}
