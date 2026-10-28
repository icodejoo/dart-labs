import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/fake_cache_persist.dart';
import '../../test/support/test_server.dart';

/// 缓存命中用例的请求路径。
const _path = '/cached';

/// 验证缓存短路先于离线队列和加载括号。
void main() {
  test('[INV-20] 缓存命中在离线判定前返回且不产生加载括号', () async {
    var hits = 0;
    var probes = 0;
    var online = true;
    final server = await TestServer.start((req) {
      hits++;
      return respondJson(req, 7, 200);
    });
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    final states = <bool>[];
    final loading = DiomanLoading(onChanged: states.add);
    final offline = DiomanOffline(
        isOnline: () {
          probes++;
          return online;
        },
        onConnectivityChanged: const Stream<bool>.empty());
    final handle = Dioman.install(dio,
        key: const DiomanKey(),
        cache: DiomanCache(
            persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo),
        offline: offline,
        loading: loading);
    addTearDown(handle.dispose);
    expect((await dio.get<dynamic>(_path)).data, 7);
    expect(states, [true, false]);
    expect(probes, 1);
    states.clear();
    online = false;
    final response =
        await dio.get<dynamic>(_path).timeout(const Duration(seconds: 2));
    expect(response.data, 7);
    expect(response.statusMessage, contains('cached'));
    expect(hits, 1);
    expect(probes, 1);
    expect(offline.pending, 0);
    expect(loading.activeCount, 0);
    expect(states, isEmpty);
  });
}
