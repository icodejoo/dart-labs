import '../support/constants.dart';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 请求补丁及统一请求选项解析的规则测试。
void main() {
  test(
      '[DiomanRequest.baseUrl][DiomanRequest.cancelToken][DiomanRequest.connectTimeout][DiomanRequest.data][DiomanRequest.extra][DiomanRequest.headers][DiomanRequest.method][DiomanRequest.new(options)][DiomanRequest.patch][DiomanRequest.path][DiomanRequest.query][DiomanRequest.receiveTimeout][DiomanRequest.sendTimeout][DiomanRequest.silent][DiomanRequest.toRequestOptions][DiomanRequest.uri][RequestPatch.connectTimeout][RequestPatch.data][RequestPatch.extra][RequestPatch.method][RequestPatch.query][RequestPatch.receiveTimeout][RequestPatch.removeHeaders][RequestPatch.removeQuery]'
      '[RequestPatch] 合并、大小写删除、null 替换与完整有效配置保留', () {
    final token = CancelToken();
    final original = RequestOptions(
        path: '/old',
        baseUrl: pipelineTestHttpsExampleTest,
        method: pipelineTestPOST,
        data: {pipelineTestXValue: 1},
        headers: {pipelineTestXA: 1, 'X-B': 2},
        queryParameters: {pipelineTestA: 1, pipelineTestB: 2},
        extra: {pipelineTestA: 1},
        connectTimeout: const Duration(seconds: 1),
        sendTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 3),
        cancelToken: token,
        followRedirects: false,
        maxRedirects: 7,
        responseType: ResponseType.bytes,
        persistentConnection: false,
        listFormat: ListFormat.csv,
        onSendProgress: (_, __) {},
        onReceiveProgress: (_, __) {});
    final optionKey = DiomanOptionKey<int>(pipelineTestN);
    final r = DiomanRequest(original,
        call: DiomanCall(silent: true, options: {optionKey: 3}));
    final p = r.patch(const RequestPatch(
        headers: {pipelineTestXAValue: 4, pipelineTestNull: null},
        removeHeaders: {'x-b'},
        query: {pipelineTestB: null, pipelineTestC: 3},
        removeQuery: {pipelineTestA},
        extra: {pipelineTestB: 2},
        data: null,
        method: pipelineTestPUT,
        path: pipelineTestNew,
        connectTimeout: null,
        sendTimeout: null,
        receiveTimeout: null,
        cancelToken: null));
    expect(p.headers, {pipelineTestXAValue: 4, pipelineTestNull: null});
    expect(p.query, {pipelineTestB: null, pipelineTestC: 3});
    expect(p.extra, {pipelineTestA: 1, pipelineTestB: 2});
    expect(p.data, isNull);
    expect([p.path, p.method, p.baseUrl],
        [pipelineTestNew, pipelineTestPUT, original.baseUrl]);
    expect([p.connectTimeout, p.sendTimeout, p.receiveTimeout, p.cancelToken],
        everyElement(isNull));
    expect(r.headers[pipelineTestXA], 1);
    expect(r.cancelToken, same(token));
    expect(r.silent, isTrue);
    expect(r.call.options[optionKey], 3);
    expect(() => r.headers[pipelineTestXValue] = 1, throwsUnsupportedError);
    expect(() => r.query[pipelineTestXValue] = 1, throwsUnsupportedError);
    final extras = r.extra;
    expect(() => extras[pipelineTestXValue] = 1, throwsUnsupportedError);
    expect(() => r.call.options[optionKey] = 1, throwsUnsupportedError);
    final unchanged = r.patch(const RequestPatch());
    expect(unchanged.data, same(r.data));
    expect(unchanged.uri, r.uri);
    final wire = p.toRequestOptions();
    expect(wire.followRedirects, isFalse);
    expect(wire.responseType, ResponseType.bytes);
    expect(wire.maxRedirects, 7);
    expect(wire.onSendProgress, same(original.onSendProgress));
    expect(wire.onReceiveProgress, same(original.onReceiveProgress));
    wire.headers.clear();
    expect(p.headers, isNotEmpty);
    final replacement = CancelToken();
    final changed = r.patch(RequestPatch(
        data: [2],
        cancelToken: replacement,
        connectTimeout: Duration.zero,
        sendTimeout: Duration.zero,
        receiveTimeout: Duration.zero));
    expect(changed.cancelToken, same(replacement));
    expect(changed.data, [2]);
    expect(
        [changed.connectTimeout, changed.sendTimeout, changed.receiveTimeout],
        everyElement(Duration.zero));
  });

  test('[DiomanOptionKey.description]' '[resolveOption] 四种写法、简写、optIn 和未知类型',
      () {
    final base = <int>[1];
    List<int> merge(List<int> a, List<int> b) => [...a, ...b];
    for (final value in [null, true]) {
      expect(resolveOption<List<int>>(value, base: base, merge: merge),
          same(base));
    }
    expect(resolveOption<List<int>>(false, base: base, merge: merge), isNull);
    expect(
        resolveOption<List<int>>(null, base: base, merge: merge, optIn: true),
        isNull);
    expect(
        resolveOption<List<int>>(true, base: base, merge: merge, optIn: true),
        same(base));
    expect(resolveOption<List<int>>([2], base: base, merge: merge), [1, 2]);
    expect(
        resolveOption<List<int>>(3,
            base: base, merge: merge, shorthand: (v) => v is int ? [v] : null),
        [1, 3]);
    expect(
        () =>
            resolveOption<List<int>>(pipelineTestBad, base: base, merge: merge),
        throwsArgumentError);
    expect(
        () => resolveOption<List<int>>(pipelineTestBad,
            base: base, merge: merge, shorthand: (_) => null),
        throwsArgumentError);
    expect(
        identical(DiomanOptionKey<int>(pipelineTestXValue),
            DiomanOptionKey<int>(pipelineTestXValue)),
        isFalse);
    expect(DiomanOptionKey<int>(pipelineTestXValue).description,
        pipelineTestXValue);
  });
}
