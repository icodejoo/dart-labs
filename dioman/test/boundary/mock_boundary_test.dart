// ignore_for_file: avoid_relative_lib_imports
// 边界层：mock
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/mock_plugin.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group('DiomanMock: mockUrl redirect path', () {
    test(
        '[DiomanMock.enabled][DiomanMockOptions.enabled] an inline handler that throws a DioException is rejected as-is',
        () async {
      // A real server, never actually contacted — the inline handler
      // intercepts before any network call, but keeping a real backing
      // server matches this suite's convention over a fake/unreachable URL.
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: tkReal}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final mock = DiomanMock(enabled: true);
      mock.add(tkGETData, (options) async {
        throw DioException(requestOptions: options, message: tkHandlerBlewUp);
      });
      dio.interceptors.add(mock);

      await expectLater(
        dio.get<void>(tkData2),
        throwsA(isA<DioException>()
            .having((e) => e.message, tkMessage, tkHandlerBlewUp)),
      );
    });
  });

  group(tkDiomanMock, () {
    test(
        '[DiomanMock.onRequest] the mock-server redirect does not duplicate query parameters '
        'in the composed URI (regression for the copyWith fix)', () {
      // Mirrors DiomanMock._rewriteUrl's contract: the rewritten absolute
      // path already folds in the original query string, so the
      // queryParameters map handed to the redirect request must be cleared —
      // otherwise dio's RequestOptions.uri appends the same params again.
      final withoutFix = RequestOptions(
        path: tkHttpMockLocalPetsTypeCat,
        queryParameters: {tkType: 'cat'},
      );
      expect(withoutFix.uri.query, 'type=cat&type=cat',
          reason: 'demonstrates the bug: query kept alongside an '
              'already-query-bearing rewritten path duplicates it');

      final withFix = RequestOptions(
        path: tkHttpMockLocalPetsTypeCat,
        queryParameters: {},
      );
      expect(withFix.uri.query, 'type=cat',
          reason:
              'clearing queryParameters (the actual fix) avoids the duplication');
    });
  });

  test(
      '[DiomanMock.enabled][DiomanMock.new(routes)] mock ordinary failure rejects once',
      () async {
    final mock = DiomanMock(
        enabled: true,
        routes: {mockRoute: (_) async => throw StateError('mock failure')});
    final handler = RecordingRequestHandler();
    mock.onRequest(cacheOptions(), handler);
    await pumpEvents();
    expect(handler.calls, 1);
    expect(handler.error?.error, isA<StateError>());
  });
}
