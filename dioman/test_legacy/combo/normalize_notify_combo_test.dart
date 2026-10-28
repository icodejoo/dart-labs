// ignore_for_file: avoid_relative_lib_imports
// 组合层：normalize_notify
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  test(
      '[DiomanNotify.ordering × DiomanNormalize.ordering] notify 始终排在 normalize 前，读取解包前的业务错误',
      () async {
    final messages = <String>[];
    final notify = DiomanNotify<dynamic>(
        notify: messages.add,
        stringify: (data, message, status, options) =>
            data is Map && data[tkCode] != 0 ? tkFailure : tkEmpty);
    final server = await TestServer.start(
        (r) => respondJson(r, {tkCode: 1001, tkData: null}, 200));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final handle = Dioman.install(dio,
        normalize: const DiomanNormalize(), plugins: [notify]);
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await expectLater(
        dio.get<dynamic>('/business'), throwsA(isA<DioException>()));
    expect(messages, [tkFailure]);
  });
}
