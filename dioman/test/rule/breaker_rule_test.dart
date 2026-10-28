// ignore_for_file: avoid_relative_lib_imports
// 规则层：breaker
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/breaker_plugin.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
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

    setUp(() {
      adapter = BucketAdapter();
      now = DateTime(2026, 1, 1);
      dio = Dio(BaseOptions(baseUrl: tkHttpFake))..httpClientAdapter = adapter;
    });
    test(
        '[DiomanBreaker.idleTtl][DiomanBreakerState.closed] 空闲超过 idleTtl 的 closed 桶在新桶创建时被回收',
        () async {
      final b = make();
      await hit(tkA3);
      await hit(tkB);
      expect(b.bucketCount, 2);

      now = now.add(const Duration(minutes: 11));
      await hit(tkC2);
      expect(b.bucketCount, 1, reason: '/a、/b 已过期，只剩 /c');
    });
    test('[DiomanBreaker.maxBuckets] 达到 maxBuckets 时淘汰最久未用的安全桶', () async {
      final b = make(maxBuckets: 3);
      await hit(tkA3);
      now = now.add(const Duration(seconds: 1));
      await hit(tkB);
      now = now.add(const Duration(seconds: 1));
      await hit(tkC2);
      expect(b.bucketCount, 3);

      now = now.add(const Duration(seconds: 1));
      await hit('/d'); // 未过 ttl，但已达上限 → 淘汰最旧的 /a
      expect(b.bucketCount, 3);

      // /a 被淘汰后重新建桶会再触发淘汰；用计数验证上限始终生效
      await hit('/e');
      expect(b.bucketCount, 3);
    });
  });

  group(tkDiomanBreaker, () {
    test(
        '[DiomanBreaker.failureThreshold][DiomanBreaker.resetDuration] trips after N consecutive failures, then fails fast (no network)',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
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

      // Three genuine failures trip the breaker.
      for (var i = 0; i < 3; i++) {
        await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      }
      expect(hits, 3, reason: 'all three failing requests hit the server');
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.open);

      // Fourth request is rejected fast — never reaches the server.
      DioException? caught;
      try {
        await dio.get<dynamic>(tkX);
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.error, isA<DiomanBreakerOpenException>());
      expect((caught.error as DiomanBreakerOpenException).bucketKey, tkGETX);
      expect(hits, 3,
          reason: 'fail-fast: the open breaker did NOT hit the server');
    });
    test(
        '[DiomanBreaker.failureThreshold][DiomanBreaker.resetDuration] a success resets the consecutive-failure count',
        () async {
      var status = 500;
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: status == 200}, status);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 3,
        resetDuration: const Duration(seconds: 10),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Two failures, then a success (resets), then two more failures — never
      // three IN A ROW, so the breaker must stay closed.
      status = 500;
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      status = 200;
      await dio.get<dynamic>(tkX);
      status = 500;
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));

      expect(breaker.stateOf(tkGETX), DiomanBreakerState.closed);
    });
    test(
        '[DiomanBreakerState.closed][DiomanBreakerState.halfOpen] cooldown → halfOpen probe succeeds → closed',
        () async {
      var status = 500;
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {tkOk: status == 200}, status);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final transitions = <String>[];
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(milliseconds: 150),
        halfOpenMaxCalls: 1,
        onStateChange: (k, from, to) =>
            transitions.add('${from.name}->${to.name}'),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Trip it.
      status = 500;
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.open);
      final hitsAtOpen = hits;

      // Still cooling down → fail fast, server untouched.
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(hits, hitsAtOpen, reason: 'rejected before cooldown, no network');

      // Wait out the cooldown, server now healthy → probe succeeds → closed.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      status = 200;
      await dio.get<dynamic>(tkX);
      expect(hits, hitsAtOpen + 1, reason: 'exactly one probe went to network');
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.closed);
      expect(transitions, [tkClosedOpen, tkOpenHalfOpen, 'halfOpen->closed']);
    });
    test(
        '[DiomanBreakerState.halfOpen][DiomanBreaker.failureThreshold] cooldown → halfOpen probe fails → re-opens',
        () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final transitions = <String>[];
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(milliseconds: 150),
        halfOpenMaxCalls: 1,
        onStateChange: (k, from, to) =>
            transitions.add('${from.name}->${to.name}'),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.open);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      // Probe hits the still-broken server, fails → back to open.
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.open);
      expect(transitions, [tkClosedOpen, tkOpenHalfOpen, 'halfOpen->open']);
    });
    test(
        '[DiomanBreaker.shouldTrip][DiomanBreakerOptions.shouldTrip] custom shouldTrip counts a 200 business failure',
        () async {
      final server = await TestServer.start((req) async {
        // HTTP 200 but a business-level failure code.
        await respondJson(req, {tkCode: 1, tkMsg: 'nope'}, 200);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(seconds: 10),
        shouldTrip: (resp, err) {
          final data = resp?.data;
          if (data is Map && data[tkCode] != 0) return true;
          return null;
        },
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      // Both are HTTP 200 (no throw), but the breaker counts them as failures.
      await dio.get<dynamic>(tkX);
      await dio.get<dynamic>(tkX);
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.open);

      DioException? caught;
      try {
        await dio.get<dynamic>(tkX);
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught?.error, isA<DiomanBreakerOpenException>());
    });
    test(
        '[DiomanBreaker.enabled][DiomanBreakerOptions.enabled] per-request enabled:false bypasses the open breaker',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {tkOk: false}, 500);
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final breaker = DiomanBreaker(
        failureThreshold: 2,
        resetDuration: const Duration(seconds: 10),
      );
      dio.interceptors.add(breaker);
      addTearDown(breaker.dispose);

      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      await expectLater(dio.get<dynamic>(tkX), throwsA(isA<DioException>()));
      expect(breaker.stateOf(tkGETX), DiomanBreakerState.open);
      final hitsAtOpen = hits;

      // Opted-out request must still reach the server (real 500, not a
      // fast-fail breaker rejection).
      DioException? caught;
      try {
        await dio.get<dynamic>(tkX,
            options: Options(extra: {
              DiomanBreaker.pluginName:
                  const DiomanBreakerOptions(enabled: false),
            }));
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught?.error, isNot(isA<DiomanBreakerOpenException>()));
      expect(hits, hitsAtOpen + 1,
          reason: 'the opted-out request hit the server');
    });
  });

  test(
      '[DiomanBreaker.failureThreshold][DiomanBreaker.halfOpenMaxCalls] breaker 半开达到并发预算时拒绝额外探测',
      () async {
    var now = DateTime.utc(2026);
    final plugin = DiomanBreaker(
        failureThreshold: 1,
        halfOpenMaxCalls: 1,
        resetDuration: replayTick,
        clock: () => now);
    final initial = RequestOptions(path: replayPath);
    plugin.onRequest(initial, RequestInterceptorHandler());
    final failed = ErrorInterceptorHandler();
    final failureCheck =
        expectLater(handlerCompletion(failed), throwsA(anything));
    plugin.onError(
        DioException(
            requestOptions: initial, type: DioExceptionType.connectionError),
        failed);
    await failureCheck;
    now = now.add(replayTick);
    plugin.onRequest(
        RequestOptions(path: replayPath), RequestInterceptorHandler());
    final rejected = RequestInterceptorHandler();
    final rejectCheck =
        expectLater(handlerCompletion(rejected), throwsA(anything));
    plugin.onRequest(RequestOptions(path: replayPath), rejected);
    await rejectCheck;
    expect(plugin.stateOf('GET:$replayPath'), DiomanBreakerState.halfOpen);
    plugin.dispose();
  });

  test(
      '[DiomanBreaker.shouldTrip][DiomanBreakerOptions.shouldTrip] breaker 非依赖异常视作成功并可重置全部桶',
      () async {
    final plugin = DiomanBreaker(shouldTrip: (_, __) => false);
    final options = RequestOptions(path: replayPath);
    plugin.onRequest(options, RequestInterceptorHandler());
    final handler = ErrorInterceptorHandler();
    final future = handlerCompletion(handler)..ignore();
    plugin.onError(DioException(requestOptions: options), handler);
    await expectLater(future, throwsA(anything));
    plugin.reset();
    expect(plugin.stateOf('GET:$replayPath'), DiomanBreakerState.closed);
    plugin.dispose();
  });
}
