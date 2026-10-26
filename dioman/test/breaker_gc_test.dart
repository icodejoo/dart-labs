import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 假适配器：按路径返回状态码；路径在 [gates] 里时挂起，直到对应 Completer 完成。
class _Adapter implements HttpClientAdapter {
  final statuses = <String, int>{};
  final gates = <String, Completer<void>>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final gate = gates[options.path];
    if (gate != null) await gate.future;
    final code = statuses[options.path] ?? 200;
    return ResponseBody.fromString('{}', code, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('DiomanBreaker bucket GC', () {
    late _Adapter adapter;
    late Dio dio;
    late DateTime now;

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

    Future<void> hit(String path) async {
      try {
        await dio.get<dynamic>(path);
      } on DioException {
        // 失败请求也算一次访问
      }
    }

    /// 让出若干事件循环，使挂起的请求推进到适配器。
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    setUp(() {
      adapter = _Adapter();
      now = DateTime(2026, 1, 1);
      dio = Dio(BaseOptions(baseUrl: 'http://fake'))
        ..httpClientAdapter = adapter;
    });

    test('空闲超过 idleTtl 的 closed 桶在新桶创建时被回收', () async {
      final b = make();
      await hit('/a');
      await hit('/b');
      expect(b.bucketCount, 2);

      now = now.add(const Duration(minutes: 11));
      await hit('/c');
      expect(b.bucketCount, 1, reason: '/a、/b 已过期，只剩 /c');
    });

    test('未超过 idleTtl 的桶保留', () async {
      final b = make();
      await hit('/a');
      now = now.add(const Duration(minutes: 5));
      await hit('/b');
      expect(b.bucketCount, 2);
    });

    test('open 桶不被回收，即使空闲很久', () async {
      final b = make();
      adapter.statuses['/bad'] = 500;
      await hit('/bad');
      await hit('/bad');
      expect(b.stateOf('GET:/bad'), DiomanBreakerState.open);

      now = now.add(const Duration(hours: 5));
      await hit('/other');
      // /bad 仍是 open 状态（若被回收会变成 closed）
      expect(b.stateOf('GET:/bad'), DiomanBreakerState.open);
      expect(b.bucketCount, 2);
    });

    test('halfOpen 桶（含在途探测）不被回收', () async {
      final b = make();
      adapter.statuses['/bad'] = 500;
      await hit('/bad');
      await hit('/bad');
      now = now.add(const Duration(seconds: 31));

      // 冷却已过：下个请求进入 halfOpen 并挂起为在途探测
      final gate = adapter.gates['/bad'] = Completer<void>();
      final probe = hit('/bad');
      await settle();
      expect(b.stateOf('GET:/bad'), DiomanBreakerState.halfOpen);

      now = now.add(const Duration(hours: 5));
      await hit('/other');
      expect(b.stateOf('GET:/bad'), DiomanBreakerState.halfOpen);

      gate.complete();
      await probe;
    });

    test('closed 但有在途请求的桶不被回收', () async {
      final b = make();
      final gate = adapter.gates['/slow'] = Completer<void>();
      final pending = hit('/slow');
      await settle();
      expect(b.bucketCount, 1);

      now = now.add(const Duration(hours: 5));
      await hit('/other');
      expect(b.bucketCount, 2, reason: '/slow 在途，不能回收');

      gate.complete();
      await pending;
    });

    test('closed 但连续失败计数非 0 的桶不被回收', () async {
      final b = make(failureThreshold: 3);
      adapter.statuses['/flaky'] = 500;
      await hit('/flaky'); // 计数 1，未熔断
      now = now.add(const Duration(hours: 5));
      await hit('/other');
      expect(b.bucketCount, 2);

      // 计数仍在：再失败两次应熔断（若被回收则要三次）
      await hit('/flaky');
      await hit('/flaky');
      expect(b.stateOf('GET:/flaky'), DiomanBreakerState.open);
    });

    test('达到 maxBuckets 时淘汰最久未用的安全桶', () async {
      final b = make(maxBuckets: 3);
      await hit('/a');
      now = now.add(const Duration(seconds: 1));
      await hit('/b');
      now = now.add(const Duration(seconds: 1));
      await hit('/c');
      expect(b.bucketCount, 3);

      now = now.add(const Duration(seconds: 1));
      await hit('/d'); // 未过 ttl，但已达上限 → 淘汰最旧的 /a
      expect(b.bucketCount, 3);

      // /a 被淘汰后重新建桶会再触发淘汰；用计数验证上限始终生效
      await hit('/e');
      expect(b.bucketCount, 3);
    });

    test('maxBuckets 达到但无安全桶可淘汰时允许暂时超出，不丢熔断状态', () async {
      final b = make(maxBuckets: 2);
      adapter.statuses['/x'] = 500;
      adapter.statuses['/y'] = 500;
      for (final p in ['/x', '/y']) {
        await hit(p);
        await hit(p);
      }
      expect(b.stateOf('GET:/x'), DiomanBreakerState.open);
      expect(b.stateOf('GET:/y'), DiomanBreakerState.open);

      await hit('/z');
      expect(b.bucketCount, 3);
      expect(b.stateOf('GET:/x'), DiomanBreakerState.open);
      expect(b.stateOf('GET:/y'), DiomanBreakerState.open);
    });

    test('回收后同键请求从 closed 重新开始', () async {
      final b = make(failureThreshold: 2);
      await hit('/a');
      now = now.add(const Duration(minutes: 11));
      await hit('/b'); // 回收 /a
      expect(b.bucketCount, 1);

      adapter.statuses['/a'] = 500;
      await hit('/a');
      expect(b.stateOf('GET:/a'), DiomanBreakerState.closed);
      await hit('/a');
      expect(b.stateOf('GET:/a'), DiomanBreakerState.open);
    });

    test('回收不影响半开 generation：旧窗口在途结果不改新窗口', () async {
      final b = make();
      adapter.statuses['/g'] = 500;
      await hit('/g');
      await hit('/g');
      now = now.add(const Duration(seconds: 31));

      // 探测请求挂起，期间做一次回收扫描，然后让探测失败
      final gate = adapter.gates['/g'] = Completer<void>();
      final probe = hit('/g');
      await settle();
      now = now.add(const Duration(hours: 5));
      await hit('/other');
      expect(b.stateOf('GET:/g'), DiomanBreakerState.halfOpen);

      gate.complete();
      await probe;
      // 探测失败 → 回到 open，说明凭据仍指向同一个桶
      expect(b.stateOf('GET:/g'), DiomanBreakerState.open);
    });
  });
}
