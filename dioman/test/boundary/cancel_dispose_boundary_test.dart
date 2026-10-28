import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/test_server.dart';

/// 在途请求的路径，服务端会挂起到测试放行。
const _path = '/inflight';

/// 移除插件时传给在途请求的取消原因。
const _reason = 'plugin ejected';

/// 注册移除取消插件时的在途请求测试。
void main() {
  test('[DiomanCancel.dispose] 移除插件以 plugin ejected 取消仍追踪的在途请求', () async {
    final arrived = Completer<void>();
    final release = Completer<void>();
    final server = await TestServer.start((r) async {
      arrived.complete();
      await release.future;
      await respondJson(r, {}, 200);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final cancel = DiomanCancel();
    final handle = Dioman.install(dio, cancel: cancel);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    final request = dio.get<void>(_path);
    final checked = expectLater(
        request,
        throwsA(isA<DioException>()
            .having((e) => e.type, '类型', DioExceptionType.cancel)
            .having((e) => e.error, '原因', _reason)));
    await arrived.future;
    expect(handle.remove<DiomanCancel>(), same(cancel));
    await checked;
    expect(cancel.cancelAll(), 0);
    expect(dio.interceptors.whereType<DiomanCancel>(), isEmpty);
    release.complete();
  });
}
