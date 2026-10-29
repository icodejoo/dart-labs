import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/helpers.dart';

/// 回环成功响应。
const _body = '{"code":0,"data":"source"}';

/// 真实 Dio 的转发、共享取消与超时、缓存命中。
void main() {
  test(
      '[Dioman.dio][Dioman.response]'
      '[DiomanMock.mockUrl × DiomanCache.option] 回环转发保留方法路径查询，回落后缓存零触网',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var probes = 0;
    var real = 0;
    server.listen((r) async {
      if (r.uri.path.startsWith('/mock')) {
        probes++;
        expect(r.uri.queryParameters[b4LiteralQ], b4LiteralValue);
        r.response.statusCode = 404;
      } else {
        real++;
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(_body);
      await r.response.close();
    });
    final url = 'http://${server.address.address}:${server.port}';
    final dio = Dio(BaseOptions(baseUrl: url));
    addTearDown(() => dio.close(force: true));
    final api = Dioman<Result>(dio: dio, plugins: [
      DiomanMock<Result>(mockUrl: '$url/mock'),
      const DiomanCache<Result>()
    ]);
    for (var i = 0; i < 2; i++) {
      expect(
          (await api.send<Object?>(b4Get, b4Path,
                  query: {b4LiteralQ: b4LiteralValue},
                  call: b4Call(cache: true)))
              .ok,
          isTrue);
    }
    expect(probes, 2);
    expect(real, 1);
  });
  test(
      '[INV-context-lifecycle][Dioman.key][Dioman.plugin]'
      '[DiomanSharePolicy.start] 回环首发取消及订阅者超时不终止共享 Dio', () async {
    for (final cancel in [true, false]) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final gate = Completer<void>();
      final arrived = Completer<void>();
      var hits = 0;
      server.listen((r) async {
        hits++;
        arrived.complete();
        await gate.future;
        r.response.headers.contentType = ContentType.json;
        r.response.write(_body);
        await r.response.close();
      });
      final dio = Dio(BaseOptions(
          baseUrl: 'http://${server.address.address}:${server.port}'));
      final api =
          Dioman<Result>(dio: dio, plugins: [const DiomanShare<Result>()]);
      final token = CancelToken();
      final a = api.send<Object?>(b4Get, b4Path,
          call: DiomanCall(
              key: b4Key,
              cancelToken: token,
              receiveTimeout: const Duration(milliseconds: 250),
              sendTimeout: const Duration(seconds: 1),
              connectTimeout: const Duration(seconds: 2),
              options: {DiomanShare.option: true}));
      await arrived.future;
      final b = api.send<Object?>(b4Get, b4Path,
          call: DiomanCall(
              key: b4Key,
              receiveTimeout: const Duration(seconds: 5),
              options: {DiomanShare.option: true}));
      await b4Turn();
      if (cancel) {
        token.cancel();
      }
      expect((await a).kind, cancel ? DiomanKind.cancel : DiomanKind.timeout);
      gate.complete();
      expect((await b).ok, isTrue);
      expect(hits, 1);
      expect(api.cancellationSubscriptions, 0);
      expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
      api.dispose();
      dio.close(force: true);
      await server.close(force: true);
    }
  });
}
