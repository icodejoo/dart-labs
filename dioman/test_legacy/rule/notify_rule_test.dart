import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 通知用例的请求路径。
const _path = '/notify';

/// 通知文本样例，同时作为错误消息使用。
const _text = 'notification';

/// 标记同一请求已通知过的 extra 键。
const _sent = 'dioman:notify:sent';

/// 验证通知转换、去重和新一次分发。
void main() {
  test(
      '[DiomanNotify.name][DiomanNotify.pluginName][DiomanNotify.notify][DiomanNotify.stringify] 回调保存且仅通知非空文本',
      () async {
    final notices = <String>[];
    final notify = notices.add;
    var text = '';
    final calls = <(dynamic, String, int, RequestOptions)>[];

    /// 记录响应转换入参并返回受控通知文本。
    String stringify(
        dynamic data, String message, int status, RequestOptions options) {
      calls.add((data, message, status, options));
      return text;
    }

    final plugin = DiomanNotify<dynamic>(notify: notify, stringify: stringify);
    expect(DiomanNotify.pluginName, 'dioman:notify');
    expect(plugin.name, DiomanNotify.pluginName);
    expect(plugin.notify, same(notify));
    expect(plugin.stringify, same(stringify));
    final server = await TestServer.start((req) => respondJson(req, 7, 200));
    addTearDown(server.close);
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    addTearDown(dio.close);
    final handle = Dioman.installPlugins(dio, [plugin]);
    addTearDown(handle.dispose);
    await dio.get<dynamic>(_path);
    expect(notices, isEmpty);
    text = _text;
    final response = await dio.get<dynamic>(_path);
    expect(notices, [_text]);
    expect(calls.last.$1, 7);
    expect(calls.last.$2, isNotEmpty);
    expect(calls.last.$3, 200);
    expect(calls.last.$4, same(response.requestOptions));
  });

  test(
      '[DiomanNotify.onResponse][DiomanNotify.onError][DiomanNotify.onRequest] 同请求成功错误只通知一次且新分发清除标记',
      () async {
    for (final errorFirst in [false, true]) {
      final notices = <String>[];
      var conversions = 0;
      final options = RequestOptions(path: _path);
      final response = Response<dynamic>(
          requestOptions: options,
          data: 9,
          statusCode: 409,
          statusMessage: _text);
      final error = DioException(
          requestOptions: options, response: response, message: _text);
      final plugin = DiomanNotify<int>(
          notify: notices.add,
          stringify: (data, message, status, request) {
            conversions++;
            expect(data, 9);
            expect(message, _text);
            expect(status, 409);
            expect(request, same(options));
            return _text;
          });

      /// 在同一请求上模拟两个出口以验证去重。
      void dispatch() {
        if (errorFirst) {
          plugin.onError(error, IgnoringErrorHandler());
          plugin.onResponse(response, RecordingResponseHandler());
        } else {
          plugin.onResponse(response, RecordingResponseHandler());
          plugin.onError(error, IgnoringErrorHandler());
        }
      }

      dispatch();
      expect(notices, [_text]);
      expect(conversions, 1);
      expect(options.extra[_sent], isTrue);
      final handler = RecordingRequestHandler();
      plugin.onRequest(options, handler);
      expect(handler.calls, 1);
      expect(options.extra.containsKey(_sent), isFalse);
      dispatch();
      expect(notices, [_text, _text]);
      expect(conversions, 2);
    }
  });
}
