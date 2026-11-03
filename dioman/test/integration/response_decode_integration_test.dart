import '../support/response_contract.dart';
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

/// 验证对应主题的行为与边界。
void main() {
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
        expect([outcomeOf(bad), bad.status, bad.status],
            [diomanTestParse, 502, 502]);
        final html = await api.send<dynamic>(_get, _path);
        expect(outcomeOf(html), strict ? diomanTestParse : diomanTestOk);
        expect(html.data, _html);
        // 声明 JSON 的 HTML 在 Dio 解码时就失败，两种工厂配置均归 parse。
        final advertised =
            await api.send<dynamic>(_get, _path, query: {_json: true});
        expect(outcomeOf(advertised), diomanTestParse);
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
