import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';

/// 恢复由 auth 插件完成的模式（失败为 401）。
const _authMode = 'auth';

/// 恢复由 retry 插件完成的模式（失败为 500）。
const _retryMode = 'retry';

/// 首个会失败的请求路径，用于触发恢复。
const _failurePath = '/failure';

/// 恢复后用于检查连接是否串线的请求路径。
const _successPath = '/success';

/// 响应体里的标记字段名。
const _marker = 'response-marker';

/// 失败响应的标记值。
const _failure = 'failed-response-body';

/// 后续成功响应的标记值。
const _success = 'later-success-body';

/// 在实际复用的本地连接上验证恢复失败后的下一次响应隔离；依赖 H4。
void main() {
  test('[INV-18] keep-alive 下 auth 和 retry 恢复失败不污染后续响应', () async {
    for (final mode in [_authMode, _retryMode]) {
      final ports = <int>[];
      final paths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        ports.add(request.connectionInfo!.remotePort);
        paths.add(request.uri.path);
        await request.drain<void>();
        final failed = request.uri.path == _failurePath;
        final body =
            utf8.encode(jsonEncode({_marker: failed ? _failure : _success}));
        request.response.statusCode =
            failed ? (mode == _authMode ? 401 : 500) : 200;
        request.response.persistentConnection = true;
        request.response.headers.contentType = ContentType.json;
        request.response.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
      addTearDown(() => dio.close(force: true));
      var refreshes = 0;
      final tokens = TestTokens('initial-token');
      final handle = Dioman.install(dio,
          auth: mode == _authMode
              ? DiomanAuth(
                  tokenManager: tokens,
                  onRefresh: (_, __) async {
                    refreshes++;
                    tokens.set('renewed');
                  },
                  onAccessExpired: (_, __) async {})
              : null,
          retry: mode == _retryMode
              ? DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero)
              : null,
          normalize: const DiomanNormalize());
      addTearDown(handle.dispose);
      await expectLater(
          dio.get<dynamic>(_failurePath),
          throwsA(isA<DioException>()
              .having((e) => e.response?.statusCode, '失败状态',
                  mode == _authMode ? 401 : 500)
              .having((e) => e.response?.data, '失败响应体', {_marker: _failure})));
      tokens.set('next-request-token');
      final response = await dio.get<dynamic>(_successPath);
      expect(response.statusCode, 200);
      expect(response.data, {_marker: _success});
      expect(paths, [_failurePath, _failurePath, _successPath]);
      expect(ports.toSet(), hasLength(1), reason: '必须确实复用同一 TCP 连接');
      expect(refreshes, mode == _authMode ? 1 : 0);
    }
  });
}
