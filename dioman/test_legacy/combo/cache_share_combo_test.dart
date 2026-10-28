// ignore_for_file: avoid_relative_lib_imports
// 组合层：cache_share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fake_cache_persist.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('pairwise: cache + share', () {
    test(
        '[DiomanCache.onRequest × DiomanShare.onRequest] a cache hit resolves before DiomanShare.onRequest ever runs — no '
        'dedup needed once the answer is already known', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio,
          cache: DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
          ),
          share: DiomanShare(policy: DiomanSharePolicy.start));

      await dio.get<void>(tkData2);
      expect(calls, 1);

      // Second call: cache hit — never reaches share at all.
      await dio.get<void>(tkData2);
      expect(calls, 1, reason: 'cache hit short-circuits before share');
    });
    test(
        '[DiomanCache.cachePolicy × DiomanShare.policy] two concurrent callers before anything is cached still dedupe via '
        'share, and the single real response gets cached for a third, '
        'later caller', () async {
      var calls = 0;
      final server = await TestServer.start((req) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio,
          cache: DiomanCache(
            persist: FakeCachePersist(),
            cachePolicy: DiomanCachePolicy.memo,
          ),
          share: DiomanShare(policy: DiomanSharePolicy.start));

      final a = dio.get<Map<String, dynamic>>(tkData2);
      final b = dio.get<Map<String, dynamic>>(tkData2);
      final results =
          await Future.wait([a, b]).timeout(const Duration(seconds: 3));
      expect(calls, 1, reason: 'b deduped onto a via share');
      expect(results[0].data, results[1].data);

      await dio.get<void>(tkData2);
      expect(calls, 1, reason: 'third caller hits the now-populated cache');
    });
  });
}
