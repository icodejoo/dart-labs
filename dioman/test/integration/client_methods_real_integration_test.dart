import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// B7 共用字面量。
const _b7Literal0 = 'GET';

/// B7 共用字面量。
const _b7Literal1 = 'HEAD';

/// B7 共用字面量。
const _b7Literal2 = 'OPTIONS';

/// 真实回环中成功与失败都使用的路径。
const _path = '/methods';

/// 失败查询字段。
const _fail = 'fail';

/// 公开入口必须实际调用，不能用 send 的证据代替便捷方法。
void main() {
  test(
      '[Dioman.get][Dioman.post][Dioman.put][Dioman.patch][Dioman.delete]'
      '[Dioman.head][Dioman.request][Dioman.send] 真实 IO 成功、失败和资源释放', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <String>[];
    var inflight = 0;
    server.listen((request) async {
      inflight++;
      try {
        received.add(request.method);
        final failed = request.uri.queryParameters.containsKey(_fail);
        request.response.statusCode = failed ? 500 : 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'code': failed ? 500 : 0,
          'data': request.method,
        }));
        await request.response.close();
      } finally {
        inflight--;
      }
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
    final api = Dioman(dio: dio);
    final methods = <String, Future<Object?> Function(Map<String, dynamic>)>{
      _b7Literal0: (query) => api.get<Object?>(_path, query: query),
      'POST': (query) => api.post<Object?>(_path, query: query),
      'PUT': (query) => api.put<Object?>(_path, query: query),
      'PATCH': (query) => api.patch<Object?>(_path, query: query),
      'DELETE': (query) => api.delete<Object?>(_path, query: query),
      _b7Literal1: (query) => api.head<Object?>(_path, query: query),
      _b7Literal2: (query) =>
          api.request<Object?>(_b7Literal2, _path, query: query),
    };
    try {
      for (final method in methods.entries) {
        expect(await method.value({}),
            method.key == _b7Literal1 ? isNull : method.key);
        await expectLater(
            method.value({_fail: true}),
            throwsA(
                isA<DiomanResponse>().having((r) => r.status, 'status', 500)));
        expect(api.pending, 0);
      }
      final success = await api.send<Object?>(_b7Literal0, _path);
      expect(success.ok, isTrue);
      final failure =
          await api.send<Object?>(_b7Literal0, _path, query: {_fail: true});
      expect(failure.kind, DiomanKind.http);
      expect(failure.status, 500);
      expect(received, [
        for (final method in methods.keys) ...[method, method],
        _b7Literal0,
        _b7Literal0
      ]);
      expect(api.pending, 0);
      while (inflight != 0) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(inflight, 0);
    } finally {
      api.dispose();
      dio.close(force: true);
      await server.close(force: true);
    }
  });
}
