import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 错误分类用例的请求路径。
const _path = '/classification';

/// 上面路径对应的熔断桶键（GET 方法）。
const _key = 'GET:$_path';

/// 注册错误分类与观察者异常的边界测试。
void main() {
  test('[DiomanBreaker.onError] 在途半开探测取消后归还槽位且不触发状态迁移', () async {
    var hits = 0;
    final arrived = Completer<void>();
    final release = Completer<void>();
    final server = await TestServer.start((r) async {
      hits++;
      if (hits == 2) {
        arrived.complete();
        await release.future;
      }
      await respondJson(r, {}, hits == 1 ? 500 : 200);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final breaker = DiomanBreaker(
        failureThreshold: 1, resetDuration: Duration.zero, halfOpenMaxCalls: 1);
    final handle = Dioman.install(dio, breaker: breaker);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await expectLater(dio.get<void>(_path), throwsA(isA<DioException>()));
    final token = CancelToken();
    final pending = dio.get<void>(_path, cancelToken: token);
    final checked = expectLater(
        pending,
        throwsA(isA<DioException>()
            .having((e) => e.type, '取消类型', DioExceptionType.cancel)));
    await arrived.future;
    expect(breaker.stateOf(_key), DiomanBreakerState.halfOpen);
    expect(breaker.isOpen(RequestOptions(path: _path)), isTrue);
    token.cancel();
    await checked;
    expect(breaker.stateOf(_key), DiomanBreakerState.halfOpen,
        reason: '取消既不成功关闭，也不失败重开');
    expect(breaker.isOpen(RequestOptions(path: _path)), isFalse,
        reason: '探测名额已归还');
    expect((await dio.get<void>(_path)).statusCode, 200);
    expect(breaker.stateOf(_key), DiomanBreakerState.closed);
    release.complete();
  });

  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout
  ]) {
    test('[DiomanBreaker.onError] 内置分类将 $type 计为失败且同一凭据只消费一次', () {
      final breaker = DiomanBreaker(failureThreshold: 2);
      final options = RequestOptions(path: _path);
      breaker.onRequest(options, RecordingRequestHandler());
      final error = DioException(requestOptions: options, type: type);
      breaker.onError(error, IgnoringErrorHandler());
      breaker.onError(error, IgnoringErrorHandler());
      expect(breaker.isOpen(RequestOptions(path: _path)), isFalse);
      final second = RequestOptions(path: _path);
      breaker.onRequest(second, RecordingRequestHandler());
      breaker.onError(DioException(requestOptions: second, type: type),
          IgnoringErrorHandler());
      expect(breaker.stateOf(_key), DiomanBreakerState.open);
    });
  }

  test('[DiomanBreaker.onStateChange] 迁移后通知观察者，异常原样抛出且已改变状态', () {
    final failure = StateError(_path);
    final events = <(String, DiomanBreakerState, DiomanBreakerState)>[];
    expect(DiomanBreaker().onStateChange, isNull);

    /// 记录迁移并模拟观察者异常。
    void observer(String key, DiomanBreakerState from, DiomanBreakerState to) {
      events.add((key, from, to));
      throw failure;
    }

    final breaker = DiomanBreaker(failureThreshold: 1, onStateChange: observer);
    expect(breaker.onStateChange, same(observer));
    final options = RequestOptions(path: _path);
    breaker.onRequest(options, RecordingRequestHandler());
    expect(
        () => breaker.onError(
            DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError),
            IgnoringErrorHandler()),
        throwsA(same(failure)));
    expect(
        events, [(_key, DiomanBreakerState.closed, DiomanBreakerState.open)]);
    expect(breaker.stateOf(_key), DiomanBreakerState.open);
  });
}
