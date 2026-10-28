// ignore_for_file: avoid_relative_lib_imports
// 组合层：breaker_retry
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  test(
      '[DiomanBreaker.failureThreshold × DiomanRetry.breaker] 重试的每次失败计入熔断，不重复记最终失败',
      () async {
    var hits = 0;
    final server = await TestServer.start((r) async {
      hits++;
      await respondJson(r, {tkCode: 500}, 500);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final breaker = DiomanBreaker(failureThreshold: 3);
    final handle = Dioman.install(dio,
        retry: DiomanRetry(max: 5, delay: (_, __, ___, ____) => Duration.zero),
        breaker: breaker);
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await expectLater(
        dio.get<dynamic>('/failure'), throwsA(isA<DioException>()));
    expect(hits, 3);
    expect(breaker.stateOf('GET:/failure'), DiomanBreakerState.open);
  });

  test(
      '[DiomanBreaker.failureThreshold × DiomanRetry.max] Stream body 不可重放：一次真实 500 只记一次，阈值 2 不熔断',
      () async {
    var hits = 0;
    final server = await TestServer.start((r) async {
      hits++;
      await r.drain<void>();
      await respondJson(r, {tkCode: 500}, 500);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final breaker = DiomanBreaker(failureThreshold: 2);
    final handle = Dioman.install(dio,
        retry: DiomanRetry(max: 3, delay: (_, __, ___, ____) => Duration.zero),
        breaker: breaker);
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await expectLater(
        dio.put<dynamic>('/stream',
            data: Stream<List<int>>.fromIterable([
              [1, 2, 3]
            ]),
            options: Options(headers: {Headers.contentLengthHeader: 3})),
        throwsA(isA<DioException>()));
    expect(hits, 1, reason: 'Stream body 不可重放，只发一次');
    expect(breaker.stateOf('PUT:/stream'), DiomanBreakerState.closed,
        reason: '一次真实失败只记一次');
  });

  group(tkDiomanBreaker, () {
    test(
        '[DiomanBreakerState.open × DiomanRetry.breaker] with DiomanRetry: an open breaker stops the retry storm',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {tkOk: false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      // 所有请求共用一个桶；阈值 1 表示第一次真实尝试失败就熔断。
      final breaker = DiomanBreaker(
        failureThreshold: 1,
        resetDuration: const Duration(seconds: 10),
        keyBuilder: (_) => tkBucket,
      );
      final retry = DiomanRetry(
        max: 3,
        delay: (_, __, ___, ____) => Duration.zero,
      );
      final handle = Dioman.install(dio, retry: retry, breaker: breaker);
      addTearDown(handle.dispose);

      // 第一次真实尝试失败即打开熔断，重试循环必须立即停止。
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(hits, 1);
      expect(breaker.stateOf(tkBucket), DiomanBreakerState.open);

      // Request 2: breaker open → rejected fast, and DiomanRetry does NOT
      // retry the breaker-open rejection. Zero extra hits.
      DioException? caught;
      try {
        await dio.get<dynamic>(tkX);
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught?.error, isA<DiomanBreakerOpenException>());
      expect(hits, 1, reason: '熔断打开后不再发出真实尝试');
    });
  });
}
