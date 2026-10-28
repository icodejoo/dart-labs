import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/test_server.dart';

/// Mock 用例的请求路径。
const _path = '/mock';

/// 上面路径对应的 mock 路由键（GET 方法）。
const _route = 'GET:$_path';

/// 验证路由替换、转发地址覆盖及释放后重新创建转发客户端。
void main() {
  test('[defaultFallback] 未显式传 response 时任意非取消错误都回落', () {
    final options = RequestOptions(path: _path);
    final response =
        Response<dynamic>(requestOptions: options, statusCode: 500);
    final error = DioException(
        requestOptions: options,
        response: response,
        type: DioExceptionType.badResponse);
    expect(defaultFallback(error: error), isTrue);
    expect(defaultFallback(response: response, error: error), isFalse);
  });

  test('[DiomanMock.add] 同键注册覆盖旧处理器', () async {
    var hits = 0;
    final server = await TestServer.start((req) {
      hits++;
      return respondJson(req, 0, 200);
    });
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    final plugin = DiomanMock(enabled: true);
    final handle = Dioman.install(dio, mock: plugin);
    addTearDown(handle.dispose);
    for (final value in [1, 2]) {
      final text = value.toString();
      plugin.add(_route, (_) async => ResponseBody.fromString(text, 200));
      final response = await dio.get<String>(_path,
          options: Options(responseType: ResponseType.plain));
      expect(response.data, text);
    }
    expect(hits, 0);
  });

  test(
      '[DiomanMock.mockUrl][DiomanMockOptions.mockUrl][DiomanMock.dispose][DiomanMock.name][DiomanMock.pluginName] 转发地址继承覆盖且释放后可重新转发',
      () async {
    expect(DiomanMock().mockUrl, isNull);
    expect(const DiomanMockOptions().mockUrl, isNull);
    final real = await TestServer.start((req) => respondJson(req, 0, 200));
    final primary = await TestServer.start((req) => respondJson(req, 1, 200));
    final override = await TestServer.start((req) => respondJson(req, 2, 200));
    addTearDown(real.close);
    addTearDown(primary.close);
    addTearDown(override.close);
    final dio = Dio(BaseOptions(baseUrl: real.baseUrl));
    addTearDown(dio.close);
    final plugin = DiomanMock(enabled: true, mockUrl: primary.baseUrl);
    expect(plugin.mockUrl, primary.baseUrl);
    expect(DiomanMock.pluginName, 'dioman:mock');
    expect(plugin.name, DiomanMock.pluginName);
    final handle = Dioman.install(dio, mock: plugin);
    addTearDown(handle.dispose);
    final option = DiomanMockOptions(mockUrl: override.baseUrl);
    expect(option.mockUrl, override.baseUrl);
    for (final config in [
      const DiomanMockOptions(),
      option,
      const DiomanMockOptions()
    ]) {
      final response = await dio.get<dynamic>(_path,
          options: Options(extra: {DiomanMock.pluginName: config}));
      expect(response.data, config.mockUrl == null ? 1 : 2);
      // dispose 关闭旧客户端并清空引用；下一次必须创建可用的新实例。
      plugin.dispose();
      plugin.dispose();
    }
  });
}
