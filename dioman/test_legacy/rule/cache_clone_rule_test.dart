// ignore_for_file: avoid_relative_lib_imports
// 规则层：cache / clone
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fake_cache_persist.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group('DiomanCache management API', () {
    test(
        '[DiomanCachePolicy.both][DiomanClonePolicy.deep] DiomanClonePolicy.shallow returns a distinct top-level container '
        'for both Map and List payloads, without deep-copying nested '
        'objects', () async {
      final server =
          await TestServer.start((req) => respondJson(req, [1, 2, 3], 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(
        persist: FakeCachePersist(),
        cachePolicy: DiomanCachePolicy.memo,
      ));

      final r1 = await dio.get<List<dynamic>>(tkData2);
      final r2 = await dio.get<List<dynamic>>(tkData2); // cache hit
      expect(r2.data, [1, 2, 3]);
      expect(identical(r1.data, r2.data), isFalse,
          reason: 'shallow clone returns a distinct top-level List');
    });
    test(
        '[DiomanClonePolicy.deep][DiomanCache.cachePolicy] DiomanClonePolicy.deep recursively copies nested maps/lists, so '
        'mutating one hit never affects another', () async {
      final server = await TestServer.start((req) => respondJson(
          req,
          {
            tkNested: {tkV: 1},
            tkList: [
              {tkV: 2}
            ],
          },
          200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey());
      dio.interceptors.add(DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
          clone: DiomanClonePolicy.deep));

      final r1 =
          await dio.get<Map<String, dynamic>>(tkData2); // populates cache
      final r2 = await dio.get<Map<String, dynamic>>(tkData2); // hit
      (r2.data![tkNested] as Map)[tkV] = 999;
      (r2.data![tkList] as List)[0][tkV] = 999;

      final r3 = await dio.get<Map<String, dynamic>>(tkData2); // hit again
      expect(r3.data![tkNested][tkV], 1,
          reason: 'deep clone means mutating r2 never touched the stored '
              'entry, unlike r1 (populated before any clone was applied)');
      expect(r3.data![tkList][0][tkV], 2,
          reason: "the list's original value (2) survived — r2's mutation "
              'to 999 never touched the stored entry either');
      expect(identical(r1.data, r2.data), isFalse);
    });
  });

  group('DiomanCache LRU', () {
    test(
        '[DiomanCache.clone][DiomanClonePolicy.shallow] default clone (shallow) prevents a cache-hit reader from corrupting '
        'the stored entry by reassigning top-level fields', () async {
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.addAll([
        const DiomanKey(),
        DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
        )
      ]);

      await dio.get<Map<String, dynamic>>(tkX); // network → store
      final hit1 = await dio.get<Map<String, dynamic>>(tkX); // cache hit
      hit1.data![tkV] = 999; // mutate the returned copy
      hit1.data!['injected'] = true;

      final hit2 = await dio.get<Map<String, dynamic>>(tkX); // cache hit again
      expect(hit2.data, {tkV: 1},
          reason: 'shallow clone default must isolate the store from a '
              "reader's top-level mutations");
    });
  });

  test(
      '[DiomanCache.clone][DiomanCacheOptions.clone] cache deep clone isolates first response',
      () async {
    final cache = DiomanCache(
        persist: ControlledPersist(),
        cachePolicy: DiomanCachePolicy.memo,
        clone: DiomanClonePolicy.deep);
    final options = cacheOptions();
    cache.onRequest(options, RecordingRequestHandler());
    await pumpEvents();
    final data = {
      nestedField: {valueField: 1}
    };
    cache.onResponse(
        Response(requestOptions: options, data: data, statusCode: 200),
        ResponseInterceptorHandler());
    data[nestedField]![valueField] = 2;
    final handler = RecordingRequestHandler();
    cache.onRequest(cacheOptions(), handler);
    await pumpEvents();
    expect(handler.response?.data, {
      nestedField: {valueField: 1}
    });
  });
}
