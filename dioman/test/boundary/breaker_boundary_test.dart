// ignore_for_file: avoid_relative_lib_imports
// 边界层：breaker
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/breaker_plugin.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group('DiomanBreaker bucket GC', () {
    late BucketAdapter adapter;
    late Dio dio;
    late DateTime now;

    /// make 的测试辅助入口。
    DiomanBreaker make({
      int failureThreshold = 2,
      Duration idleTtl = const Duration(minutes: 10),
      int maxBuckets = 1000,
    }) {
      final b = DiomanBreaker(
        failureThreshold: failureThreshold,
        resetDuration: const Duration(seconds: 30),
        idleTtl: idleTtl,
        maxBuckets: maxBuckets,
        clock: () => now,
      );
      dio.interceptors.add(b);
      addTearDown(b.dispose);
      return b;
    }

    /// hit 的测试辅助入口。
    Future<void> hit(String path) async {
      try {
        await dio.get<dynamic>(path);
      } on DioException {
        // 失败请求也算一次访问
      }
    }

    /// 让出若干事件循环，使挂起的请求推进到适配器。
    /// settle 的测试辅助入口。
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    setUp(() {
      adapter = BucketAdapter();
      now = DateTime(2026, 1, 1);
      dio = Dio(BaseOptions(baseUrl: tkHttpFake))..httpClientAdapter = adapter;
    });
    test('[DiomanBreaker.idleTtl] 未超过 idleTtl 的桶保留', () async {
      final b = make();
      await hit(tkA3);
      now = now.add(const Duration(minutes: 5));
      await hit(tkB);
      expect(b.bucketCount, 2);
    });
    test('[DiomanBreakerState.open] open 桶不被回收，即使空闲很久', () async {
      final b = make();
      adapter.statuses[tkBad2] = 500;
      await hit(tkBad2);
      await hit(tkBad2);
      expect(b.stateOf(tkGETBad), DiomanBreakerState.open);

      now = now.add(const Duration(hours: 5));
      await hit(tkOther);
      // /bad 仍是 open 状态（若被回收会变成 closed）
      expect(b.stateOf(tkGETBad), DiomanBreakerState.open);
      expect(b.bucketCount, 2);
    });
    test('[DiomanBreakerState.halfOpen] halfOpen 桶（含在途探测）不被回收', () async {
      final b = make();
      adapter.statuses[tkBad2] = 500;
      await hit(tkBad2);
      await hit(tkBad2);
      now = now.add(const Duration(seconds: 31));

      // 冷却已过：下个请求进入 halfOpen 并挂起为在途探测
      final gate = adapter.gates[tkBad2] = Completer<void>();
      final probe = hit(tkBad2);
      await settle();
      expect(b.stateOf(tkGETBad), DiomanBreakerState.halfOpen);

      now = now.add(const Duration(hours: 5));
      await hit(tkOther);
      expect(b.stateOf(tkGETBad), DiomanBreakerState.halfOpen);

      gate.complete();
      await probe;
    });
    test('[DiomanBreakerState.closed] closed 但有在途请求的桶不被回收', () async {
      final b = make();
      final gate = adapter.gates[tkSlow] = Completer<void>();
      final pending = hit(tkSlow);
      await settle();
      expect(b.bucketCount, 1);

      now = now.add(const Duration(hours: 5));
      await hit(tkOther);
      expect(b.bucketCount, 2, reason: '/slow 在途，不能回收');

      gate.complete();
      await pending;
    });
    test(
        '[DiomanBreakerState.closed][DiomanBreaker.failureThreshold] closed 但连续失败计数非 0 的桶不被回收',
        () async {
      final b = make(failureThreshold: 3);
      adapter.statuses[tkFlaky] = 500;
      await hit(tkFlaky); // 计数 1，未熔断
      now = now.add(const Duration(hours: 5));
      await hit(tkOther);
      expect(b.bucketCount, 2);

      // 计数仍在：再失败两次应熔断（若被回收则要三次）
      await hit(tkFlaky);
      await hit(tkFlaky);
      expect(b.stateOf('GET:/flaky'), DiomanBreakerState.open);
    });
    test('[DiomanBreaker.maxBuckets] maxBuckets 达到但无安全桶可淘汰时允许暂时超出，不丢熔断状态',
        () async {
      final b = make(maxBuckets: 2);
      adapter.statuses[tkX] = 500;
      adapter.statuses[tkY2] = 500;
      for (final p in [tkX, tkY2]) {
        await hit(p);
        await hit(p);
      }
      expect(b.stateOf(tkGETX), DiomanBreakerState.open);
      expect(b.stateOf(tkGETY), DiomanBreakerState.open);

      await hit('/z');
      expect(b.bucketCount, 3);
      expect(b.stateOf(tkGETX), DiomanBreakerState.open);
      expect(b.stateOf(tkGETY), DiomanBreakerState.open);
    });
    test(
        '[DiomanBreakerState.closed][DiomanBreaker.failureThreshold] 回收后同键请求从 closed 重新开始',
        () async {
      final b = make(failureThreshold: 2);
      await hit(tkA3);
      now = now.add(const Duration(minutes: 11));
      await hit(tkB); // 回收 /a
      expect(b.bucketCount, 1);

      adapter.statuses[tkA3] = 500;
      await hit(tkA3);
      expect(b.stateOf(tkGETA), DiomanBreakerState.closed);
      await hit(tkA3);
      expect(b.stateOf(tkGETA), DiomanBreakerState.open);
    });
    test('[DiomanBreaker.onRequest] 回收不影响半开 generation：旧窗口在途结果不改新窗口', () async {
      final b = make();
      adapter.statuses[tkG] = 500;
      await hit(tkG);
      await hit(tkG);
      now = now.add(const Duration(seconds: 31));

      // 探测请求挂起，期间做一次回收扫描，然后让探测失败
      final gate = adapter.gates[tkG] = Completer<void>();
      final probe = hit(tkG);
      await settle();
      now = now.add(const Duration(hours: 5));
      await hit(tkOther);
      expect(b.stateOf(tkGETG), DiomanBreakerState.halfOpen);

      gate.complete();
      await probe;
      // 探测失败 → 回到 open，说明凭据仍指向同一个桶
      expect(b.stateOf(tkGETG), DiomanBreakerState.open);
    });
  });

  group(tkDiomanBreaker, () {
    test(
        '[DiomanBreaker.reset][DiomanBreaker.failureThreshold] a cancelled request does not reset the failure count',
        () async {
      var slow = false;
      final server = await TestServer.start((req) async {
        if (slow) await Future<void>.delayed(const Duration(seconds: 5));
        await respondJson(req, {tkOk: false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 3,
        resetDuration: const Duration(seconds: 10),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Two genuine failures — count = 2, one short of tripping.
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.closed);

      // Cancel an in-flight (admitted) request. A cancel must be neutral — it
      // must NOT reset the count back to 0.
      slow = true;
      final ct = CancelToken();
      final f = dio.get<dynamic>(tkX, cancelToken: ct);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ct.cancel();
      await expectLater(
        f,
        throwsA(isA<DioException>()
            .having((e) => e.type, tkType, DioExceptionType.cancel)),
      );
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.closed);

      // One more real failure → count reaches 3 → trips. Only possible if the
      // cancel did NOT reset the count (otherwise this is just failure #1).
      slow = false;
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.open);
    });
  });

  test(
      '[DiomanBreaker.failureThreshold][DiomanBreaker.halfOpenMaxCalls] stale breaker probe cannot close or consume a new window',
      () {
    final breaker = DiomanBreaker(
        failureThreshold: 1, resetDuration: Duration.zero, halfOpenMaxCalls: 2);

    /// 记录一次依赖失败。
    /// fail 的测试辅助入口。
    void fail(RequestOptions options) => breaker.onError(
        DioException(
            requestOptions: options, type: DioExceptionType.connectionError),
        IgnoringErrorHandler());
    final initial = cacheOptions();
    breaker.onRequest(initial, RecordingRequestHandler());
    fail(initial);
    final old = cacheOptions();
    final failingProbe = cacheOptions();
    breaker.onRequest(old, RecordingRequestHandler());
    breaker.onRequest(failingProbe, RecordingRequestHandler());
    fail(failingProbe);
    final fresh = cacheOptions();
    breaker.onRequest(fresh, RecordingRequestHandler());
    breaker.onResponse(
        Response(requestOptions: old), RecordingResponseHandler());
    expect(breaker.stateOf(mockRoute), DiomanBreakerState.halfOpen);
    breaker.onError(
        DioException(requestOptions: old, type: DioExceptionType.cancel),
        IgnoringErrorHandler());
    breaker.onRequest(cacheOptions(), RecordingRequestHandler());
    expect(breaker.isOpen(cacheOptions()), isTrue);
    breaker.onResponse(
        Response(requestOptions: fresh), RecordingResponseHandler());
    expect(breaker.stateOf(mockRoute), DiomanBreakerState.closed);
  });

  test(
      '[DiomanBreakerState.open][DiomanBreaker.failureThreshold] breaker cancellation returns half-open slot',
      () {
    final breaker = DiomanBreaker(
        failureThreshold: 1, resetDuration: Duration.zero, halfOpenMaxCalls: 1);
    final failed = cacheOptions();
    breaker.onRequest(failed, RecordingRequestHandler());
    breaker.onError(
        DioException(
            requestOptions: failed, type: DioExceptionType.connectionError),
        IgnoringErrorHandler());
    final probe = cacheOptions();
    breaker.onRequest(probe, RecordingRequestHandler());
    breaker.onError(
        DioException(requestOptions: probe, type: DioExceptionType.cancel),
        IgnoringErrorHandler());
    expect(breaker.isOpen(cacheOptions()), isFalse);
  });
}
