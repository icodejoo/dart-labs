import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/constants.dart';
import '../support/fake_network.dart';

/// 工厂子类在调用端和 debug 派生时保留扩展字段。
void main() {
  test(
      '[Dioman.get]'
      '[DiomanContext.factory]'
      '[DiomanResponseFactory.create] send<T> 保留类型匹配的子类和扩展字段', () async {
    final network = FakeNetwork();
    network.routes['GET:/typed'] = [
      const FakeReply(body: {pipelineTestCode: 0, pipelineTestData: 7}),
      const FakeReply(body: {pipelineTestCode: 401, pipelineTestData: null}),
    ];
    var creates = 0;
    final api = Dioman<_ExtendedResult<int>>(
        dio: Dio(BaseOptions(baseUrl: pipelineTestHttpsExampleTest))
          ..httpClientAdapter = network,
        debug: true,
        response: DiomanResponseFactory(create: (r) {
          creates++;
          return _ExtendedResult<int>(r);
        }),
        reject: (r) {
          expect(r.label, pipelineTestYes);
          return r;
        });
    final result =
        await api.send<int>(pipelineTestGetMethod, pipelineTestTypedPath);
    expect(result, isA<_ExtendedResult<int>>());
    expect((result as _ExtendedResult<int>).label, pipelineTestYes);
    expect(result.data, 7);
    final failed =
        await api.send<int>(pipelineTestGetMethod, pipelineTestTypedPath);
    expect(failed, isA<_ExtendedResult<int>>());
    expect(failed.callSite.toString(),
        contains('response_extension_rule_test.dart'));
    expect(creates, 3);
    await expectLater(api.get<int>(pipelineTestTypedPath),
        throwsA(isA<_ExtendedResult<int>>()));
    expect(api.pending, 0);
  });
}

/// 带类型化数据及额外标量的扩展响应。
class _ExtendedResult<T> extends DiomanResponse<T> {
  /// 工厂从初值创建强类型结果。
  _ExtendedResult(DiomanResponse<dynamic> r)
      : super(
            ok: r.ok,
            kind: r.kind,
            status: r.status,
            httpStatus: r.httpStatus,
            data: r.data as T?,
            request: r.request,
            callSite: r.callSite);

  /// 示例扩展字段。
  String get label => pipelineTestYes;
}
