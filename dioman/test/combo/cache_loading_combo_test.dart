// ignore_for_file: avoid_relative_lib_imports
// 组合层：cache_loading
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('pairwise: cache + loading', () {
    test(
        '[DiomanCache.cachePolicy × DiomanLoading.new(onChanged)] a cache hit never increments the loading counter',
        () async {
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(dio,
          cache: DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
          ),
          loading: DiomanLoading(onChanged: states.add));

      await dio.get<void>(tkData2); // real: true then false
      await dio.get<void>(tkData2); // cache hit: loading.onRequest never runs
      expect(states, [true, false],
          reason: 'the cache-hit call never touches the loading counter at '
              'all — cache sits before loading in the chain and resolves '
              'before loading.onRequest is reached');
    });
  });

  test(
      '[DiomanCache.cachePolicy × DiomanLoading.onRequest] persistence errors reach Dio caller and release loading bracket',
      () async {
    final persist = ControlledPersist();
    final loading = DiomanLoading(onChanged: (_) {});
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.addAll([
      const DiomanKey(),
      DiomanCache(persist: persist, cachePolicy: DiomanCachePolicy.persist),
      loading,
      InterceptorsWrapper(onRequest: (options, handler) {
        persist.fails = true;
        handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: 1), true);
      }),
    ]);
    await expectLater(
        dio.get<dynamic>(fixturePath),
        throwsA(isA<DioException>()
            .having((error) => error.error, tkCause, isA<StateError>())));
    expect(loading.activeCount, 0);
  });
}
