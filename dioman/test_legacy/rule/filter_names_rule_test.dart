// 规则层：filter 的插件名与 extra 键
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../../test/support/fixtures.dart';

/// 插件名 / extra 键的期望值。
const _pluginName = 'dioman:filter';

/// 被默认谓词判定为空值的查询参数名。
const _blankKey = 'blank';

/// 注册本文件的规则层用例。
void main() {
  test(
      '[DiomanFilter.name][DiomanFilter.pluginName] 插件名固定为 dioman:filter，同时是单请求覆盖的 extra 键',
      () async {
    expect(DiomanFilter.pluginName, _pluginName);
    expect(const DiomanFilter().name, DiomanFilter.pluginName);

    final adapter = RecordingAdapter((o, n) async => jsonBody({}, 200));
    final dio = fakeDio(adapter)..interceptors.add(const DiomanFilter());

    await dio.get<dynamic>('/x', queryParameters: {_blankKey: null, 'k': 1});
    expect(adapter.seen.last.queryParameters, {'k': 1}, reason: '默认剔除 null');

    // 用静态常量当 extra 键关掉本次过滤，null 值应当保留。
    await dio.get<dynamic>('/x',
        queryParameters: {_blankKey: null, 'k': 1},
        options: Options(extra: {
          DiomanFilter.pluginName: const DiomanFilterOptions(enabled: false),
        }));
    expect(adapter.seen.last.queryParameters, {_blankKey: null, 'k': 1});
  });
}
