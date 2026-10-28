import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/test_server.dart';

/// 信封归一化用例的请求路径。
const _path = '/normalize';

/// 默认的消息字段名。
const _message = 'message';

/// 请求级覆盖使用的消息字段名。
const _customMessage = 'detail';

/// 默认的数据字段名。
const _data = 'data';

/// 安装期配置使用的数据字段名。
const _customData = 'payload';

/// 业务状态码字段名，0 表示成功。
const _code = 'code';

/// 默认消息字段下的失败提示文本。
const _defaultFailure = 'default failure';

/// 自定义消息字段下的失败提示文本。
const _text = 'business failure';

/// 验证信封字段的默认值、继承、覆盖与错误文本。
void main() {
  test(
      '[DiomanNormalize.messageKey][DiomanNormalizeOptions.messageKey][DiomanNormalize.name][DiomanNormalize.pluginName] 消息键控制信封识别和错误文本',
      () async {
    expect(const DiomanNormalize().messageKey, _message);
    expect(const DiomanNormalizeOptions().messageKey, isNull);
    expect(DiomanNormalize.pluginName, 'dioman:normalize');
    expect(const DiomanNormalize().name, DiomanNormalize.pluginName);
    final server = await TestServer.start((req) => respondJson(
        req,
        {
          _code: 1,
          _message: _defaultFailure,
          _customMessage: _text,
        },
        200));
    addTearDown(server.close);
    for (final pluginKey in [_message, _customMessage]) {
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      addTearDown(dio.close);
      final plugin = DiomanNormalize(messageKey: pluginKey);
      expect(plugin.messageKey, pluginKey);
      final handle = Dioman.install(dio, normalize: plugin);
      addTearDown(handle.dispose);
      for (final key in [null, _customMessage]) {
        final config = DiomanNormalizeOptions(messageKey: key);
        expect(config.messageKey, key);
        final expected =
            (key ?? pluginKey) == _message ? _defaultFailure : _text;
        await expectLater(
            dio.get<dynamic>(_path,
                options: Options(extra: {DiomanNormalize.pluginName: config})),
            throwsA(isA<DioException>().having(
                (e) => e.error,
                '业务异常',
                isA<DiomanException>()
                    .having((e) => e.message, '提示', expected))));
      }
    }
  });

  test('[DiomanNormalizeOptions.dataKey] 空值继承插件字段而显式字段改变解包结果', () async {
    expect(const DiomanNormalizeOptions().dataKey, isNull);
    final server = await TestServer.start((req) => respondJson(
        req,
        {
          _code: 0,
          _data: 1,
          _customData: 2,
        },
        200));
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    final handle = Dioman.install(dio,
        normalize: const DiomanNormalize(dataKey: _customData));
    addTearDown(handle.dispose);
    for (final key in [null, _data]) {
      final config = DiomanNormalizeOptions(dataKey: key);
      expect(config.dataKey, key);
      final response = await dio.get<dynamic>(_path,
          options: Options(extra: {DiomanNormalize.pluginName: config}));
      expect(response.data, key == null ? 2 : 1);
    }
  });
}
