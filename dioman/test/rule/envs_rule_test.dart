import '../support/pipeline/b2_constants.dart';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/helpers.dart';

/// 环境地址模板。
const envUrl = 'https://env.example.test';

/// 显式覆盖地址。
const overrideUrl = 'https://override.example.test';

/// 环境超时。
const envTime = Duration(seconds: 3);

/// 环境容器中的字段名。
const envNested = b2Nested;

/// 核对安装期配置契约。
void main() {
  test('[DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链', () async {
    final visits = <int>[];
    final rules = [
      for (var i = 0; i < 3; i++)
        EnvRule(
            rule: () {
              visits.add(i);
              return i > 0;
            },
            config: BaseOptions(
                baseUrl: envUrl,
                connectTimeout: envTime,
                receiveTimeout: envTime,
                sendTimeout: envTime,
                headers: {b2Env: i},
                queryParameters: {b2Env: i},
                extra: {b2Env: i},
                responseType: ResponseType.bytes))
    ];
    final plugin = DiomanEnvs<Result>(rules);
    expect(plugin.rules, same(rules));
    expect(plugin.config.enabled, isTrue);
    final api = testClient(plugins: [plugin]);
    final options = api.dio.options;
    expect(visits, [0, 1]);
    expect(options.baseUrl, envUrl);
    expect(options.connectTimeout, envTime);
    expect(options.receiveTimeout, envTime);
    expect(options.sendTimeout, envTime);
    expect(options.headers[b2Env], 1);
    expect(options.queryParameters[b2Env], 1);
    expect(options.extra[b2Env], 1);
    expect(options.responseType, ResponseType.bytes);
    expect(api.inspect(), isEmpty);
    options.headers.remove(b2Env);
    await api.send<Object?>(b2Get, b2EnvPath);
    await api.send<Object?>(b2Get, b2EnvPath);
    expect(visits, [0, 1]);
    expect(options.headers, isNot(contains(b2Env)));
    api.eject(DiomanEnvs.pluginName);
    api.dispose();
    expect(options.baseUrl, envUrl);
  });

  test('[EnvRule.config] 空地址、默认 json 保留宿主，未命中与禁用完全不修改', () {
    for (final rules in <List<EnvRule>>[
      [],
      [EnvRule(rule: () => false, config: BaseOptions(baseUrl: envUrl))]
    ]) {
      final api = testClient();
      final base = api.dio.options;
      api.use(DiomanEnvs(rules));
      expect(api.dio.options, same(base));
    }
    final api = testClient();
    api.dio.options.responseType = ResponseType.stream;
    final original = api.dio.options.baseUrl;
    api.use(DiomanEnvs([EnvRule(rule: () => true, config: BaseOptions())]));
    expect(api.dio.options.baseUrl, original);
    expect(api.dio.options.responseType, ResponseType.stream);
    expect(const DiomanEnvsOptions(enabled: false).enabled, isFalse);
  });
}
