import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 验证整体预算覆盖已经开始接收的真实响应体。
void main() {
  test('[DiomanCall.deadline] 回环传输响应体中途到期', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final started = Completer<void>();
    final release = Completer<void>();
    final serving = server.forEach((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"code":0,"data":"');
      await request.response.flush();
      started.complete();
      await release.future;
      try {
        request.response.write('done"}');
        await request.response.close();
      } on IOException {/* 客户端到期会关闭连接。 */}
    });
    final api = Dioman(
        dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}')));
    try {
      final pending = api.send<Object?>('GET', '/',
          call: const DiomanCall(deadline: Duration(seconds: 2)));
      await started.future;
      final result = await pending;
      expect(failureOf(result)?.kind, DiomanFailureKind.timeout);
      expect(failureOf(result)?.reason, 'deadline');
      expect(isDiomanCancel(result), isFalse);
      expect(api.pending, 0);
    } finally {
      release.complete();
      await api.dispose();
      api.dio.close(force: true);
      await server.close(force: true);
      await serving;
    }
  });
}
