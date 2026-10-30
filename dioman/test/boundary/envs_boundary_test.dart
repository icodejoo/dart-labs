import '../support/b2_constants.dart';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../rule/envs_rule_test.dart' show envNested;

/// 核对安装错误和配置容器的引用边界。
void main() {
  test('[DiomanEnvs.config]' '[EnvRule.rule] 抛错原样中断 setup，宿主没有写入', () {
    final api = testClient();
    final base = api.dio.options;
    final error = StateError('rule sentinel');
    expect(
        () => api.use(DiomanEnvs([
              EnvRule(
                  rule: () => throw error,
                  config: BaseOptions(headers: {'bad': 1}))
            ])),
        throwsA(same(error)));
    expect(api.dio.options, same(base));
    expect(api.inspect(), isEmpty);
  });

  test('[DiomanEnvs.setup] 写前深克隆宿主和模板容器，多客户端互不污染', () {
    final template = BaseOptions(headers: {
      envNested: {
        b2List: [1]
      }
    }, queryParameters: {
      envNested: {
        b2List: [1]
      }
    }, extra: {
      envNested: {
        b2List: [1]
      }
    });
    final plugin =
        DiomanEnvs<Result>([EnvRule(rule: () => true, config: template)]);
    final first = testClient();
    final host = first.dio.options;
    final hostExtras = host.extra;
    hostExtras[b2Host] = {
      b2List: [2]
    };
    first.use(plugin);
    final second = testClient(plugins: [plugin]);
    for (final containers in [
      [first.dio.options.headers, second.dio.options.headers, template.headers],
      [
        first.dio.options.queryParameters,
        second.dio.options.queryParameters,
        template.queryParameters
      ],
      [first.dio.options.extra, second.dio.options.extra, template.extra]
    ]) {
      ((containers[0][envNested] as Map)[b2List] as List).add(3);
      expect(containers[1][envNested], {
        b2List: [1]
      });
      expect(containers[2][envNested], {
        b2List: [1]
      });
    }
    final firstExtras = first.dio.options.extra;
    ((firstExtras[b2Host] as Map)[b2List] as List).add(3);
    expect(hostExtras[b2Host], {
      b2List: [2]
    });
  });
}
