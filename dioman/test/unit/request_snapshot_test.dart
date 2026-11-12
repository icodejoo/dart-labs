import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 请求快照在入口、派生与传输之间保持隔离。
void main() {
  const header = 'x-snapshot';
  const field = 'snapshot';
  const url = 'https://snapshot.invalid';
  test('[DiomanRequest.patch][DiomanRequest.uri] 多次派生和导出不污染基准快照', () {
    final options = RequestOptions(
        baseUrl: url,
        path: '/before',
        headers: {header: 1},
        queryParameters: {field: 1},
        extra: {field: 1},
        responseType: ResponseType.bytes,
        listFormat: ListFormat.csv);
    final original = DiomanRequest(options);
    final first = original.patch(const RequestPatch(
        path: '/after',
        headers: {header: 2},
        query: {field: 2},
        extra: {field: 2}));
    final second = first.patch(const RequestPatch(query: {field: 3}));
    options.path = '/mutated';
    options.headers.clear();
    options.queryParameters.clear();
    options.extra.clear();
    for (final request in [original, first, second]) {
      final before = request.uri;
      final wire = request.toRequestOptions();
      wire.path = '/wire';
      wire.headers.clear();
      wire.queryParameters.clear();
      wire.extra.clear();
      expect(request.uri, before);
      expect(request.headers, isNotEmpty);
      expect(request.extra, isNotEmpty);
      expect(request.toRequestOptions().responseType, ResponseType.bytes);
      expect(request.toRequestOptions().listFormat, ListFormat.csv);
    }
    expect(original.uri, Uri.parse('$url/before?$field=1'));
    expect(first.uri, Uri.parse('$url/after?$field=2'));
    expect(second.uri, Uri.parse('$url/after?$field=3'));
    expect(original.headers[header], 1);
    expect(first.headers[header], 2);
  });

  test('[DiomanResponseFactory.expectJson] 严格判定读取快照且不受外部选项修改影响', () {
    for (final type in ResponseType.values) {
      final options = RequestOptions(responseType: type);
      final request = DiomanRequest(options);
      options.responseType =
          type == ResponseType.json ? ResponseType.plain : ResponseType.json;
      final wire = request.toRequestOptions();
      wire.responseType = options.responseType;
      final result = const DiomanResponseFactory(expectJson: true).normalize(
          request,
          raw: Response<dynamic>(
              requestOptions: wire, statusCode: 200, data: 'snapshot text'));
      expect(failureOf(result)?.kind,
          type == ResponseType.json ? DiomanFailureKind.parse : null);
      expect(result.ok, type != ResponseType.json);
    }
  });
}
