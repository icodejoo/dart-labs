import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/test_server.dart';

/// 验证释放确实终止转发客户端在途连接。
void main() {
  test('[DiomanMock.dispose] 释放关闭在途转发并清空客户端引用', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final mockServer = await TestServer.start((request) async {
      if (!entered.isCompleted) {
        entered.complete();
        await release.future;
      }
      await respondJson(request, 7, 200);
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    addTearDown(mockServer.close);
    final dio = Dio(BaseOptions(baseUrl: mockServer.baseUrl));
    addTearDown(() => dio.close(force: true));
    final plugin = DiomanMock(
        enabled: true,
        mockUrl: mockServer.baseUrl,
        fallbackWhen: ({response, error}) => false);
    final handle = Dioman.install(dio, mock: plugin);
    addTearDown(handle.dispose);
    const path = '/dispose';
    final pending = dio.get<dynamic>(path);
    final failed = expectLater(pending, throwsA(isA<DioException>()));
    await entered.future.timeout(const Duration(seconds: 2));
    plugin.dispose();
    await failed;
    release.complete();
    expect((await dio.get<dynamic>(path)).data, 7);
  });
}
