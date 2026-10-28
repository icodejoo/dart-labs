import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/test_server.dart';

/// 环境切换用例的请求路径。
const _path = '/env';

/// 环境规则写入、服务端回读的请求头名。
const _header = 'x-environment';

/// 规则命中后写入请求头的值。
const _value = 'selected';

/// 验证安装期配置和请求期透传的区别。
void main() {
  test('[DiomanEnvs.config][DiomanEnvsOptions.enabled] 保存启用配置并控制规则应用', () {
    expect(const DiomanEnvsOptions().enabled, isTrue);
    expect(const DiomanEnvsOptions(enabled: false).enabled, isFalse);
    for (final enabled in [true, false]) {
      final dio = Dio();
      addTearDown(dio.close);
      final plugin = DiomanEnvs([
        EnvRule(
            rule: () => true, config: BaseOptions(headers: {_header: _value})),
      ], enabled: enabled);
      expect(plugin.config.enabled, enabled);
      plugin.apply(dio);
      expect(dio.options.headers[_header], enabled ? _value : isNull);
    }
  });

  test('[DiomanEnvs.rules] 保存规则列表并按输入顺序短路求值', () {
    final evaluated = <int>[];
    final rules = [
      for (var i = 0; i < 3; i++)
        EnvRule(
            rule: () {
              evaluated.add(i);
              return i > 0;
            },
            config: BaseOptions(headers: {_header: i})),
    ];
    final plugin = DiomanEnvs(rules);
    expect(plugin.rules, same(rules));
    final dio = Dio();
    addTearDown(dio.close);
    plugin.apply(dio);
    expect(evaluated, [0, 1]);
    expect(dio.options.headers[_header], 1);
  });

  test('[EnvRule.config] 空地址和默认 json 保留宿主配置', () {
    const origin = 'https://environment.example';
    final dio =
        Dio(BaseOptions(baseUrl: origin, responseType: ResponseType.bytes));
    addTearDown(dio.close);
    final config = BaseOptions();
    final rule = EnvRule(rule: () => true, config: config);
    expect(rule.config, same(config));
    DiomanEnvs([rule], dio: dio);
    expect(dio.options.baseUrl, origin);
    expect(dio.options.responseType, ResponseType.bytes);
  });

  test('[DiomanEnvs.onRequest] 请求只放行且不重新求值规则', () async {
    final server = await TestServer.start((req) => respondJson(req, {}, 200));
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    var evaluations = 0;
    final plugin = DiomanEnvs([
      EnvRule(
          rule: () {
            evaluations++;
            return true;
          },
          config: BaseOptions(headers: {_header: _value})),
    ]);
    final handle = Dioman.install(dio, envs: plugin);
    addTearDown(handle.dispose);
    plugin.apply(dio);
    expect(evaluations, 1);
    dio.options.headers.remove(_header);
    for (var i = 0; i < 2; i++) {
      final response = await dio.get<dynamic>(_path);
      expect(response.statusCode, 200);
      expect(response.requestOptions.headers[_header], isNull);
    }
    expect(evaluations, 1);
  });
}
