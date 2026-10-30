import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

/// 本地服务的统计字段。
const _total = 'total';

/// 本地服务的在途统计字段。
const _inflight = 'inflight';

/// JSON 信封数据字段。
const _data = 'data';

/// 探针隔离标记头。
const _runHeader = 'X-Test-Run';

/// 探针输出的调用方错误列表字段。
const _errors = 'errors';

/// 在真实回环 HTTP 上运行完整独立探针，不读取外部验收服务。
void main() {
  test('[INV-source-diagnostics] 独立共享探针两种风格均首次发送后在重放克隆失败', () async {
    final root = Directory.current.absolute.path;
    final fixture = Directory('.dart_tool').createTempSync('share-probe-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final totals = <String, int>{};
    final inflight = <String, int>{};
    var deleted = 0;
    final requests = <Future<void>>[];
    Future<void> serve(HttpRequest request) async {
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (path == '/proxies') {
        await request.drain<void>();
        request.response
            .write(jsonEncode({'id': 'local', 'port': server.port}));
      } else if (path.startsWith('/proxies/')) {
        deleted++;
        request.response.write('{}');
      } else if (path.startsWith('/t/runs/')) {
        final run = path.split('/').last;
        request.response.write(jsonEncode({
          _data: {_total: totals[run] ?? 0, _inflight: inflight[run] ?? 0}
        }));
      } else {
        final run = request.headers.value(_runHeader)!;
        totals.update(run, (n) => n + 1, ifAbsent: () => 1);
        inflight.update(run, (n) => n + 1, ifAbsent: () => 1);
        await request.drain<void>();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (request.headers.value('X-Test-Style') == 'http') {
          request.response.statusCode = HttpStatus.internalServerError;
        }
        request.response.write(jsonEncode({
          'code': 500,
          _data: {'reason': 'injected'}
        }));
        inflight[run] = inflight[run]! - 1;
      }
      await request.response.close();
    }

    server.listen((request) => requests.add(serve(request)));
    try {
      final base = 'http://127.0.0.1:${server.port}';
      final result = await Process.run(
          Platform.resolvedExecutable,
          [
            '--packages=${File('.dart_tool/package_config.json').absolute.path}',
            File('test/accept/bin/share_prepare_probe.dart').absolute.path,
          ],
          workingDirectory: fixture.absolute.path,
          environment: {'TESTKIT_SERVER': base, 'TESTKIT_NETEM': base});
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final artifact =
          File('${fixture.path}/coverage/accept/share-prepare-real.json');
      final report = jsonDecode(artifact.readAsStringSync()) as Map;
      final results = report['results'] as List;
      expect(results, hasLength(2));
      expect(totals.values, everyElement(1));
      expect(inflight.values, everyElement(0));
      expect(deleted, 2);
      for (final row in results.cast<Map>()) {
        expect(row[_errors], hasLength(2));
        expect(row[_errors],
            everyElement(contains('multipart replay clone failed')));
      }
    } finally {
      await server.close(force: true);
      await Future.wait(requests);
      // 仅删除本测试在工作区内创建的隔离目录。
      expect(
          fixture.absolute.path
              .startsWith('$root${Platform.pathSeparator}.dart_tool'),
          isTrue);
      fixture.deleteSync(recursive: true);
    }
  });
}
