// ignore_for_file: avoid_relative_lib_imports
// 组合层：cache_key
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fake_cache_persist.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group(tkDiomanKey, () {
    test(
        '[DiomanCache.cachePolicy × DiomanKeyOptions.key] a constructor-level disabled DiomanKey never writes a key, so '
        'DiomanCache installed after it never caches', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey(enabled: false));
      dio.interceptors.add(DiomanCache(
        persist: FakeCachePersist(),
        cachePolicy: DiomanCachePolicy.memo,
      ));

      await dio.get<void>(tkData2);
      await dio.get<void>(tkData2);
      expect(calls, 2, reason: 'no key ⇒ cache always misses');
    });
    test(
        '[DiomanClonePolicy.deep × DiomanKeyOptions.key] deep mode folds sorted queryParameters and a Map body into the '
        'key, so two requests differing only in body get different cache '
        'entries', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(const DiomanKey()); // fastMode: false (default)
      dio.interceptors.add(DiomanCache(
          persist: FakeCachePersist(),
          cachePolicy: DiomanCachePolicy.memo,
          shouldCache: (o) => true)); // allow caching this POST

      await dio.post<void>(tkData2,
          queryParameters: {tkB2: 2, tkA2: 1}, data: {tkX2: 1});
      await dio.post<void>(tkData2,
          queryParameters: {tkA2: 1, tkB2: 2}, // same params, different order
          data: {tkX2: 1});
      expect(calls, 1,
          reason: 'same query (order-independent) and body ⇒ same key ⇒ '
              'second call is a cache hit');

      await dio.post<void>(tkData2,
          queryParameters: {tkA2: 1, tkB2: 2}, data: {tkX2: 2});
      expect(calls, 2, reason: 'different body ⇒ different key ⇒ real call');
    });
  });

  group(tkKeyNamespace, () {
    test(
        '[DiomanCache.cachePolicy × DiomanKey.namespace] same account hits cache and account switches retain isolated entries',
        () async {
      for (final policy in [
        DiomanCachePolicy.memo,
        DiomanCachePolicy.persist,
        DiomanCachePolicy.both,
      ]) {
        var account = accountA;
        var networkCalls = 0;
        final dio = Dio();
        addTearDown(dio.close);
        dio.interceptors.addAll([
          DiomanKey(namespace: () => account),
          DiomanCache(persist: ControlledPersist(), cachePolicy: policy),
          InterceptorsWrapper(onRequest: (options, handler) {
            networkCalls++;
            handler.resolve(
                Response(
                    requestOptions: options, statusCode: 200, data: account),
                true);
          }),
        ]);
        expect((await dio.get<String>(fixturePath)).data, accountA);
        expect((await dio.get<String>(fixturePath)).data, accountA);
        expect(networkCalls, 1);
        account = accountB;
        expect((await dio.get<String>(fixturePath)).data, accountB);
        expect((await dio.get<String>(fixturePath)).data, accountB);
        expect(networkCalls, 2);
        account = accountA;
        expect((await dio.get<String>(fixturePath)).data, accountA);
        expect(networkCalls, 2);
      }
    });
  });
}
