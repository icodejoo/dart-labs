import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';

const _bad = 'bad';
const _true = 'true';
const _json = 'json';
const _empty = 'empty';
const _get = 'GET';
const _path = '/decode';
const _html = '<html>gateway</html>';

void main() {
  for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
    test('[DiomanShare.policy] B8 真实阶段超时不会污染其他订阅者 $policy', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var hits = 0;
      server.listen((request) async {
        final hit = ++hits;
        await Future<void>.delayed(Duration(
            milliseconds: hit == 1
                ? (policy == DiomanSharePolicy.race ? 50 : 700)
                : 900));
        request.response.statusCode = 500;
        request.response.write('{}');
        await request.response.close();
      });
      final api = Dioman<Result>(
          dio: Dio(BaseOptions(
              baseUrl: 'http://${server.address.address}:${server.port}')),
          plugins: [DiomanShare<Result>(policy: policy)]);
      try {
        final first = api.send<dynamic>(_get, _path,
            call: DiomanCall(
                connectTimeout: const Duration(seconds: 2),
                receiveTimeout: const Duration(seconds: 2),
                options: {DiomanShare.option: true}));
        final latest = api.send<dynamic>(_get, _path,
            call: DiomanCall(
                connectTimeout: const Duration(milliseconds: 100),
                receiveTimeout: const Duration(milliseconds: 100),
                options: {DiomanShare.option: true}));
        expect((await latest).kind, DiomanKind.timeout);
        final r = await first;
        expect([r.kind, r.status], [DiomanKind.http, 500]);
        expect(api.pending, 0);
      } finally {
        api.dispose();
        api.dio.close(force: true);
        await server.close(force: true);
      }
    });
  }
  test(
      '[DiomanResponseFactory.expectJson][DiomanResponseFactory.normalize] B8 真实坏 JSON 与 HTML 解码口径',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bad = request.uri.queryParameters[_bad] == _true;
      final json = request.uri.queryParameters[_json] == _true;
      final empty = request.uri.queryParameters[_empty] == _true;
      request.response.statusCode = bad ? 502 : 200;
      request.response.headers.contentType =
          json ? ContentType.json : ContentType.html;
      request.response.write(empty
          ? ''
          : bad
              ? '{broken'
              : _html);
      await request.response.close();
    });
    try {
      for (final strict in [false, true]) {
        final api = Dioman<Result>(
            dio: Dio(BaseOptions(
                baseUrl: 'http://${server.address.address}:${server.port}')),
            response: DiomanResponseFactory<Result>(expectJson: strict));
        final bad = await api
            .send<dynamic>(_get, _path, query: {_bad: true, _json: true});
        expect([bad.kind, bad.status, bad.httpStatus],
            [DiomanKind.parse, 502, 502]);
        final html = await api.send<dynamic>(_get, _path);
        expect(html.kind, strict ? DiomanKind.parse : DiomanKind.ok);
        expect(html.data, _html);
        // 声明 JSON 的 HTML 在 Dio 解码时就失败，两种工厂配置均归 parse。
        final advertised =
            await api.send<dynamic>(_get, _path, query: {_json: true});
        expect(advertised.kind, DiomanKind.parse);
        final empty = await api
            .send<dynamic>(_get, _path, query: {_json: true, _empty: true});
        expect(empty.data, isNull);
        api.dio.options.responseDecoder = (_, __, ___) => null;
        final decoded = await api.send<dynamic>(_get, _path);
        expect(decoded.data, isNull);
        api.dispose();
        api.dio.close(force: true);
      }
    } finally {
      await server.close(force: true);
    }
  });
}
