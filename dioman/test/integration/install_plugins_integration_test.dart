import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 验证通用安装入口的排序、宿主绑定和熔断接线。
void main() {
  test('[Dioman.installPlugins] 先排序安装再绑定宿主和重试熔断器', () async {
    var hits = 0;
    final server = await TestServer.start((req) {
      hits++;
      return respondJson(req, hits, hits == 1 ? 500 : 200);
    });
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    final transformer = CountingTransformer();
    dio.transformer = transformer;
    final retry =
        DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero);
    final auth = DiomanAuth(
        tokenManager: TestTokens('initial-token'),
        onRefresh: (_, __) async {},
        onAccessExpired: (_, __) async {});
    final share = DiomanShare();
    final breaker = DiomanBreaker(failureThreshold: 10);
    final handle = Dioman.installPlugins(
        dio, [share, const DiomanKey(), auth, breaker, retry]);
    addTearDown(handle.dispose);
    expect(handle.plugins.map((p) => p.name), [
      DiomanKey.pluginName,
      DiomanShare.pluginName,
      DiomanAuth.pluginName,
      DiomanRetry.pluginName,
      DiomanBreaker.pluginName
    ]);
    expect(dio.interceptors.whereType<DiomanPlugin>(),
        orderedEquals(handle.plugins));
    expect(retry.breaker, same(breaker));
    final response = await dio.get<dynamic>('/install');
    expect(response.data, 2);
    expect(hits, 2);
    expect(transformer.responses, 2);
  });
}
