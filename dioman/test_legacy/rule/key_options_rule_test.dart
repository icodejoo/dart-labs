import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/test_server.dart';

/// 构键用例的请求路径。
const _path = '/key';

/// 全局忽略项：构键时不参与的请求体字段名。
const _a = 'global-ignore';

/// 请求级忽略项：仅本次请求不参与构键的字段名。
const _b = 'request-ignore';

/// 始终参与构键的字段名。
const _c = 'retained';

/// 通过真实请求验证请求级构键配置的继承和覆盖。
void main() {
  test('[DiomanKey.name][DiomanKey.pluginName][kKey] 名称和协议槽固定且配置键能禁用构键',
      () async {
    expect(DiomanKey.pluginName, 'dioman:qid');
    expect(const DiomanKey().name, DiomanKey.pluginName);
    expect(kKey, 'dioman:key');
    final server = await TestServer.start((req) => respondJson(req, {}, 200));
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    final handle = Dioman.install(dio, key: const DiomanKey());
    addTearDown(handle.dispose);
    final response = await dio.get<dynamic>(_path);
    expect(response.requestOptions.extra[kKey], isA<String>());
    final disabled = await dio.get<dynamic>(_path,
        options: Options(extra: {
          DiomanKey.pluginName: const DiomanKeyOptions(enabled: false),
        }));
    expect(disabled.requestOptions.extra.containsKey(kKey), isFalse);
  });

  test('[DiomanKeyOptions.enabled][DiomanKeyOptions.fastMode] 空值继承而显式值覆盖构键模式',
      () async {
    const defaults = DiomanKeyOptions();
    expect(defaults.enabled, isNull);
    expect(defaults.fastMode, isNull);
    final server = await TestServer.start((req) => respondJson(req, {}, 200));
    addTearDown(server.close);
    for (final enabled in [false, true]) {
      for (final fast in [false, true]) {
        final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
        addTearDown(dio.close);
        final handle = Dioman.install(dio,
            key: DiomanKey(enabled: enabled, fastMode: fast));
        addTearDown(handle.dispose);
        for (final override in [
          defaults,
          DiomanKeyOptions(enabled: !enabled, fastMode: !fast)
        ]) {
          expect(override.enabled, override == defaults ? isNull : !enabled);
          expect(override.fastMode, override == defaults ? isNull : !fast);
          final keys = <dynamic>[];
          for (final n in [1, 2]) {
            final response = await dio.get<dynamic>(_path,
                queryParameters: {_c: n},
                options: Options(extra: {DiomanKey.pluginName: override}));
            keys.add(response.requestOptions.extra[kKey]);
          }
          if (!(override.enabled ?? enabled)) {
            expect(keys, [null, null]);
          } else if (override.fastMode ?? fast) {
            expect(keys.first, 'GET:${server.baseUrl}$_path');
            expect(keys.first, keys.last);
          } else {
            expect(keys.first, isA<String>());
            expect(keys.first, isNot(keys.last));
          }
        }
      }
    }
  });

  test('[DiomanKeyOptions.ignores] 请求忽略项与全局取并集且空值继承', () async {
    expect(const DiomanKeyOptions().ignores, isNull);
    const override = DiomanKeyOptions(ignores: [_b]);
    expect(override.ignores, [_b]);
    final server = await TestServer.start((req) => respondJson(req, {}, 200));
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    final handle = Dioman.install(dio, key: const DiomanKey(ignores: [_a]));
    addTearDown(handle.dispose);
    for (final option in [const DiomanKeyOptions(), override]) {
      final keys = <dynamic>[];
      for (final values in [(1, 1, 1), (2, 1, 1), (2, 2, 1), (2, 2, 2)]) {
        final response = await dio.post<dynamic>(_path,
            data: {_a: values.$1, _b: values.$2, _c: values.$3},
            options: Options(extra: {DiomanKey.pluginName: option}));
        keys.add(response.requestOptions.extra[kKey]);
      }
      expect(keys[0], keys[1]);
      expect(keys[1] == keys[2], option.ignores != null);
      expect(keys[2], isNot(keys[3]));
    }
  });

  test('[DiomanKey.ordering] 路径过滤先于构键且缓存共享后于构键', () {
    final order = const DiomanKey().ordering;
    expect(order.after,
        containsAll([DiomanRepath.pluginName, DiomanFilter.pluginName]));
    expect(order.before,
        containsAll([DiomanCache.pluginName, DiomanShare.pluginName]));
  });
}
