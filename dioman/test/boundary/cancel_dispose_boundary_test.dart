import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 在途请求的路径，服务端会挂起到测试放行。
const _path = '/inflight';

/// 移除插件时传给在途请求的取消原因。
const _reason = 'plugin ejected';

/// 注册移除取消插件时的在途请求测试。
void main() {
  test(
      '[DiomanCancel.dispose][DiomanCancel.dispose#inflight] 移除插件以 plugin ejected 取消仍追踪的在途请求，服务端看到连接中止',
      () async {
    final arrived = Completer<void>();
    // H1b：取消后服务端要能看到连接被断开（底层请求真的被中止、连接释放）。
    // 用原始 ServerSocket：只读不回，客户端一断开 socket 就收到 EOF，这是能确定
    // 观察到的信号（HttpServer 在 handler 不读写时不一定感知对端关闭）。
    final serverSawAbort = Completer<void>();
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    raw.listen((socket) {
      socket.listen((_) {
        if (!arrived.isCompleted) arrived.complete();
      }, onDone: () {
        if (!serverSawAbort.isCompleted) serverSawAbort.complete();
      }, onError: (_) {
        if (!serverSawAbort.isCompleted) serverSawAbort.complete();
      });
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${raw.port}'));
    final cancel = DiomanCancel();
    final handle = Dioman.install(dio, cancel: cancel);
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await raw.close();
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
    // 服务端一侧：响应还没写，连接已被客户端中止。
    await serverSawAbort.future.timeout(const Duration(seconds: 2),
        onTimeout: () => fail('取消后服务端没有观察到连接中止（H1b）'));
    expect(cancel.cancelAll(), 0);
    expect(dio.interceptors.whereType<DiomanCancel>(), isEmpty);
  });
}
