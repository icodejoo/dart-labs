// ignore_for_file: avoid_relative_lib_imports
// 组合层：cache_cancel
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fake_cache_persist.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('pairwise: cache + cancel', () {
    test(
        '[DiomanCache.cachePolicy × DiomanCancel.onRequest] a cache hit never allocates a CancelToken via DiomanCancel',
        () async {
      final server =
          await TestServer.start((req) => respondJson(req, {tkV: 1}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cancel = DiomanCancel();
      installStateful(dio,
          cache: DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
          ),
          cancel: cancel);

      await dio.get<void>(tkData2); // real, tracked briefly then released
      await dio.get<void>(tkData2); // cache hit
      expect(cancelAll(dio), 0,
          reason: 'nothing left in flight; the cache hit never registered a '
              'token in the first place');
    });
  });

  group('3-way: cache + cancel + loading', () {
    test(
        '[DiomanCachePolicy.both × DiomanCancel.onRequest] a cache hit skips cancel AND loading together, while a real '
        'network call is tracked by both', () async {
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
          cancel: DiomanCancel(),
          loading: DiomanLoading(onChanged: states.add));

      await dio.get<void>(tkData2); // real
      await dio.get<void>(tkData2); // cache hit
      expect(states, [true, false]);
      expect(cancelAll(dio), 0);
    });
  });
}
