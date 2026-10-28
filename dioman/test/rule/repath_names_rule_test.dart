// 规则层：repath 的插件名与 extra 键
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// 插件名 / extra 键的期望值。
const _pluginName = 'dioman:repath';

/// 带占位符的路径。
const _template = '/user/{id}';

/// 注册本文件的规则层用例。
void main() {
  test(
      '[DiomanRepath.name][DiomanRepath.pluginName] 插件名固定为 dioman:repath，同时是单请求覆盖的 extra 键',
      () async {
    expect(DiomanRepath.pluginName, _pluginName);
    expect(DiomanRepath().name, DiomanRepath.pluginName);

    final adapter = RecordingAdapter((o, n) async => jsonBody({}, 200));
    final dio = fakeDio(adapter)..interceptors.add(DiomanRepath());

    await dio.get<dynamic>(_template, queryParameters: {'id': 7});
    expect(adapter.seen.last.path, '/user/7');

    // 用静态常量当 extra 键关掉本次替换，占位符原样保留。
    await dio.get<dynamic>(_template,
        queryParameters: {'id': 7},
        options: Options(extra: {
          DiomanRepath.pluginName: const DiomanRepathOptions(enabled: false),
        }));
    expect(adapter.seen.last.path, _template);
    expect(adapter.seen.last.queryParameters, {'id': 7});
  });
}
