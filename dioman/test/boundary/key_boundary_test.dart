// ignore_for_file: avoid_relative_lib_imports
// 边界层：key
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group(tkDiomanKey, () {
    test(
        '[DiomanKey.onRequest] _encode falls back to toString() when a value cannot be '
        'JSON-encoded (e.g. a custom, non-serializable object)', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(
        persist: FakeCachePersist(),
        cachePolicy: DiomanCachePolicy.memo,
      ));

      await dio.get<void>(tkData2, queryParameters: {tkX2: Unencodable()});
      await dio.get<void>(tkData2, queryParameters: {tkX2: Unencodable()});
      expect(calls, 1,
          reason: 'both calls fall back to the same deterministic '
              'toString() output, so they compute the same key');
    });
  });

  group('DiomanKey non-serialisable body', () {
    test(
        '[DiomanKey.onRequest] two requests with distinct non-map bodies get distinct keys '
        '(never falsely deduped/cached as one)', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final keys = <String>[];
      dio.interceptors.add(const DiomanKey()); // deep mode
      // The computed key lives in RequestOptions.extra — dio-side only, not
      // observable over the wire — so capture it via an interceptor placed
      // right after DiomanKey, same as the other kKey-capturing tests below.
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        keys.add(o.extra[kKey] as String);
        h.next(o);
      }));

      await dio.post<void>(tkUpload, data: <int>[1, 2, 3]);
      await dio.post<void>(tkUpload, data: <int>[4, 5, 6]);

      expect(keys, hasLength(2));
      expect(keys[0], isNot(keys[1]),
          reason: 'distinct list bodies must fold in object identity so they '
              'are not keyed identically to POST:/upload');
    });
  });

  test(
      '[DiomanKeyOptions.key] key preserves opaque body identity and merges embedded queries',
      () {
    final body = Object();
    final first = RequestOptions(
        path: 'https://example.com/leaf?a=1',
        queryParameters: {secondField: 2},
        data: body);
    final second =
        RequestOptions(path: 'https://example.com/leaf?b=2&a=1', data: body);
    expect(requestKey(first), requestKey(second));
    second.data = Object();
    expect(requestKey(first), isNot(requestKey(second)));
  });

  test('[DiomanKeyOptions.key] key 遇到不可 JSON 序列化字段时仍生成稳定键', () {
    final options =
        RequestOptions(path: replayPath, data: {replayField: Object()});
    const DiomanKey().onRequest(options, RequestInterceptorHandler());
    expect(options.extra[kKey], contains(replayField));
  });

  group(tkKeyNamespace, () {
    test(
        '[DiomanKey.builder][DiomanKey.fastMode] absent null and empty namespaces preserve exact legacy keys',
        () {
      for (final fastMode in [false, true]) {
        final legacy =
            fastMode ? mockRoute : jsonEncode([mockRoute, emptyQueryKey, null]);
        expect(namespacedKey(DiomanKey(fastMode: fastMode)), legacy);
        for (final namespace in [null, tkEmpty]) {
          final plugin =
              DiomanKey(fastMode: fastMode, namespace: () => namespace);
          expect(namespacedKey(plugin), legacy);
          expect(
              namespacedKey(plugin,
                  override: const DiomanKeyOptions(key: cacheKey)),
              cacheKey);
          expect(
              namespacedKey(plugin,
                  override: DiomanKeyOptions(builder: (_) => cacheKey)),
              cacheKey);
        }
      }
    });
    test(
        '[DiomanKey.namespace] namespace failures reject once and reach Dio without hanging',
        () async {
      final cause = StateError(accountA);
      final plugin = DiomanKey(namespace: () => throw cause);
      final handler = RecordingRequestHandler();
      plugin.onRequest(cacheOptions(), handler);
      expect(handler.calls, 1);
      expect(handler.error?.error, same(cause));
      expect(handler.error?.stackTrace, isNotNull);
      final dio = Dio()..interceptors.add(plugin);
      addTearDown(dio.close);
      await expectLater(
          dio.get<dynamic>(fixturePath).timeout(namespaceTimeout),
          throwsA(isA<DioException>()
              .having((error) => error.error, tkCause, same(cause))));
    });
  });
}
