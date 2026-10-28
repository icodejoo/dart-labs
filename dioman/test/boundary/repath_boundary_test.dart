// ignore_for_file: avoid_relative_lib_imports
// 边界层：repath
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/repath_plugin.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group(tkDiomanRepath, () {
    test(
        '[DiomanRepath.onRequest] a placeholder with no match in either query or data is left '
        'as-is in the path', () async {
      String? seenPath;
      final server = await TestServer.start((req) async {
        seenPath = req.uri.path;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanRepath());

      await dio.get<void>(tkUserId);

      expect(Uri.decodeComponent(seenPath!), tkUserId,
          reason: 'the unsubstituted placeholder still reaches the network '
              '(percent-encoded, like any other literal path segment)');
    });
  });

  test(
      '[DiomanRepath.onRequest] repath snapshots repeated placeholders and encodes segments',
      () {
    const value = 'a/b?#';
    final options = RequestOptions(
        path: '/{id}/{id}', data: const {tkId: value, keepField: 1});
    DiomanRepath().onRequest(options, RecordingRequestHandler());
    final encoded = Uri.encodeComponent(value);
    expect(options.path, '/$encoded/$encoded');
    expect(options.data, {keepField: 1});
  });

  test(
      '[DiomanRepath.pattern][DiomanRepathOptions.pattern] repath 自定义模式的可选捕获组均为空时保留匹配',
      () {
    final options = RequestOptions(path: replayPath);
    DiomanRepath(pattern: RegExp(r'(a)?(b)?(c)?review'))
        .onRequest(options, RequestInterceptorHandler());
    expect(options.path, replayPath);
  });
}
