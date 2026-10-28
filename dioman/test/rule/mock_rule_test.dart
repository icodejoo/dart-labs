// ignore_for_file: avoid_relative_lib_imports
// 规则层：mock
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/mock_plugin.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group('DiomanMock: mockUrl redirect path', () {
    test(
        '[defaultFallback][DiomanMock.onRequest] defaultFallback: 404 or a non-cancel network error triggers '
        'fallback; a cancel or any other status does not', () {
      final opts = RequestOptions(path: tkX);
      expect(
          defaultFallback(
              response: Response(requestOptions: opts, statusCode: 404)),
          isTrue);
      expect(
          defaultFallback(
              response: Response(requestOptions: opts, statusCode: 200)),
          isFalse);
      expect(
          defaultFallback(
              error: DioException(
                  requestOptions: opts,
                  type: DioExceptionType.connectionError)),
          isTrue);
      expect(
          defaultFallback(
              error: DioException(
                  requestOptions: opts, type: DioExceptionType.cancel)),
          isFalse);
      expect(defaultFallback(), isFalse);
    });
    test(
        '[DiomanMock.enabled][DiomanMock.fallbackWhen] a successful mock-server response is returned directly, and a '
        'fallback-triggering one instead falls back to the real API', () async {
      final mockServer = await TestServer.start(
          (req) => respondJson(req, {tkV: tkMocked2}, 200));
      addTearDown(mockServer.close);
      final realServer =
          await TestServer.start((req) => respondJson(req, {tkV: tkReal}, 200));
      addTearDown(realServer.close);

      final dio1 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio1.interceptors
          .add(DiomanMock(enabled: true, mockUrl: mockServer.baseUrl));
      final r1 = await dio1.get<Map<String, dynamic>>(tkData2);
      expect(r1.data, {tkV: tkMocked2});

      final dio2 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio2.interceptors.add(DiomanMock(
        enabled: true,
        mockUrl: mockServer.baseUrl,
        fallbackWhen: ({response, error}) => true, // always fall back
      ));
      final r2 = await dio2.get<Map<String, dynamic>>(tkData2);
      expect(r2.data, {tkV: tkReal});
    });
    test(
        '[DiomanMock.fallbackWhen][DiomanMockOptions.fallbackWhen] a mock server that errors outright falls back to the real API '
        'when fallbackWhen says so, and rejects otherwise', () async {
      final realServer =
          await TestServer.start((req) => respondJson(req, {tkV: tkReal}, 200));
      addTearDown(realServer.close);
      // A real TestServer, immediately closed — its port is genuinely
      // unreachable (connection refused), a real network failure rather
      // than a hand-picked "probably nothing's listening" address.
      final deadServer =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      final deadMockUrl = deadServer.baseUrl;
      await deadServer.close();

      final dio1 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio1.interceptors.add(DiomanMock(
        enabled: true,
        mockUrl: deadMockUrl,
        fallbackWhen: ({response, error}) => true,
      ));
      final r1 = await dio1
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 5));
      expect(r1.data, {tkV: tkReal});

      final dio2 = Dio(BaseOptions(baseUrl: realServer.baseUrl));
      dio2.interceptors.add(DiomanMock(
        enabled: true,
        mockUrl: deadMockUrl,
        fallbackWhen: ({response, error}) => false, // never fall back
      ));
      await expectLater(
        dio2.get<void>(tkData2).timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
      );
    });
    test(
        '[DiomanMock.remove][DiomanMock.reset] remove()/reset() operate on the live inline-handler route table',
        () async {
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: tkReal}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add(
          tkGETData,
          (options) async =>
              ResponseBody.fromString('{"v":"mocked"}', 200, headers: {
                tkContentType: [tkApplicationJson]
              }));
      dio.interceptors.add(mock);

      final r1 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r1.data, {tkV: tkMocked2});

      mock.remove(tkGETData);
      final r2 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r2.data, {tkV: tkReal});

      mock.add(
          tkGETData,
          (options) async =>
              ResponseBody.fromString('{"v":"mocked2"}', 200, headers: {
                tkContentType: [tkApplicationJson]
              }));
      mock.reset();
      final r3 = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r3.data, {tkV: tkReal});
    });
  });

  group(tkPerRequestOptionsOverrides, () {
    test(
        '[DiomanMock.enabled][DiomanMockOptions.enabled] DiomanMockOptions(enabled: false) skips mocking for that request',
        () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {tkReal: true}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add(
          tkGETX,
          (opts) async => ResponseBody.fromString(
                jsonEncode({tkReal: false}),
                200,
                headers: {
                  Headers.contentTypeHeader: [tkApplicationJson],
                },
              ));
      dio.interceptors.add(mock);

      final res = await dio.get<Map<String, dynamic>>(
        tkX,
        options: Options(
            extra: {tkDiomanMock2: const DiomanMockOptions(enabled: false)}),
      );

      expect(res.data![tkReal], true,
          reason: 'enabled:false must fall through to the real network call');
    });
  });

  group(tkOptionsMergeSemanticsNotOverride, () {
    test(
        '[DiomanMock.new(routes)][DiomanMockOptions.routes] DiomanMockOptions.routes merges with the plugin\'s registered '
        "routes without dropping them", () async {
      final server = await TestServer.start(
          (req) => respondJson(req, {tkReal: true}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add(
          'GET:/existing',
          (opts) async => ResponseBody.fromString(
                jsonEncode({tkFrom: tkExisting}),
                200,
                headers: {
                  Headers.contentTypeHeader: [tkApplicationJson],
                },
              ));
      dio.interceptors.add(mock);

      final extraRoute = {
        tkDiomanMock2: DiomanMockOptions(routes: {
          'GET:/extra': (opts) async => ResponseBody.fromString(
                jsonEncode({tkFrom: tkExtra}),
                200,
                headers: {
                  Headers.contentTypeHeader: [tkApplicationJson],
                },
              ),
        }),
      };

      final r1 = await dio.get<Map<String, dynamic>>('/existing',
          options: Options(extra: extraRoute));
      final r2 = await dio.get<Map<String, dynamic>>('/extra',
          options: Options(extra: extraRoute));

      expect(r1.data![tkFrom], tkExisting,
          reason: "the plugin's own registered route must still work");
      expect(r2.data![tkFrom], tkExtra,
          reason: 'the per-request route must be reachable too');
    });
  });
}
