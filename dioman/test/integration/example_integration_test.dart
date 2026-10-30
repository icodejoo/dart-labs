import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

/// 用真实回环 HTTP 执行完整 CLI 示例，避免只编译而漏掉落定语义变化。
void main() {
  test('[INV-example] 示例遇到预期 404 后继续完成覆盖与释放断言', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final match = RegExp(r'^/todos/(\d+)$').firstMatch(request.uri.path);
      final id = match == null ? null : int.parse(match[1]!);
      request.response.headers.contentType = ContentType.json;
      if (id == null || id == 999999) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      } else {
        request.response.write(jsonEncode({'id': id}));
      }
      await request.response.close();
    });
    try {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        '--define=DIOMAN_EXAMPLE_BASE=http://127.0.0.1:${server.port}',
        'example/real_run.dart',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('ALL CHECKS PASSED'));
    } finally {
      await server.close(force: true);
    }
  });
}
