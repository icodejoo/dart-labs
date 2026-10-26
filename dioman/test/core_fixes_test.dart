// share / auth / retry / cancel 核心结算与恢复语义的回归测试。
//
// 全部用自带的 FakeAdapter + Completer 驱动并发（不起真实服务），断言最终
// 数据、错误类型，以及 registry/计数归零（后续同key请求不悬挂、cancelAll 为 0）。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/replay_support.dart';
import 'package:test/test.dart';

/// 假适配器的处理函数：参数是请求与"第几次调用"（从1开始）。
typedef _Handler = Future<ResponseBody> Function(RequestOptions options, int n);

/// 记录调用次数、可由测试用 Completer 卡住响应的假 HttpClientAdapter。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Handler handler;

  /// 已到达适配器的请求总数。
  int calls = 0;

  /// 每次到达适配器的请求选项。
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final n = ++calls;
    seen.add(options);
    await requestStream?.drain<void>();
    return handler(options, n);
  }

  @override
  void close({bool force = false}) {}
}

/// 统计 transformResponse 调用次数，用来证明重放复用了宿主的 transformer。
class _CountingTransformer extends SyncTransformer {
  int responses = 0;

  @override
  Future<dynamic> transformResponse(
      RequestOptions options, ResponseBody responseBody) {
    responses++;
    return super.transformResponse(options, responseBody);
  }
}

/// 可变的 token 管理器。
class _Tm implements DiomanTokenManager {
  _Tm(this._access);

  String? _access;

  @override
  String? get accessToken => _access;

  @override
  String? get refreshToken => 'refresh';

  @override
  bool get canRefresh => true;

  @override
  void clear() => _access = null;

  /// 直接写入 token。
  void set(String? v) => _access = v;
}

/// 构造 JSON 响应体。
ResponseBody _json(Object body, int status) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

/// 成功信封 `{code:0, data:{v:1}}`。
Map<String, dynamic> _ok() => {
      'code': 0,
      'data': {'v': 1},
      'message': '',
    };

/// 业务失败信封。
Map<String, dynamic> _bizFail() => {'code': 1, 'data': null, 'message': 'bad'};

/// 用假适配器和同步 transformer 建一个 Dio。
Dio _dio(_FakeAdapter adapter, {Transformer? transformer}) =>
    Dio(BaseOptions(baseUrl: 'http://fake'))
      ..httpClientAdapter = adapter
      ..transformer = transformer ?? SyncTransformer();

/// 让出事件循环，等其它异步任务推进。
Future<void> _settle([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// 构造一个鉴权插件，onRefresh 默认换成 t1。
DiomanAuth _auth(
  _Tm tm, {
  Future<void> Function(DiomanTokenManager, Response<dynamic>)? onRefresh,
  void Function()? onExpired,
}) =>
    DiomanAuth(
      tokenManager: tm,
      onRefresh: onRefresh ?? (_, __) async => tm.set('t1'),
      onAccessExpired: (_, __) async => onExpired?.call(),
    );

/// 零延迟的重试插件。
DiomanRetry _retry({
  int max = 1,
  DiomanShouldRetry? shouldRetry,
  List<String>? methods,
  void Function(int)? onRetry,
}) =>
    DiomanRetry(
      max: max,
      delay: (_, __, ___, ____) => Duration.zero,
      shouldRetry: shouldRetry,
      methods: methods,
      onRetry: onRetry,
    );

/// 业务失败（code != 0）视为可重试。
bool? _bizShouldRetry(DioException? err, Response<dynamic>? r) {
  final d = r?.data;
  return d is Map && d['code'] != null && d['code'] != 0 ? true : null;
}

void main() {
  const timeout = Duration(seconds: 3);

  group('share 结算责任按请求登记（#3 #4 #7）', () {
    test('share + auth：公开（不受保护）请求不会让 follower 悬挂', () async {
      final gate = Completer<void>();
      final adapter = _FakeAdapter((o, n) async {
        await gate.future;
        return _json({'v': n}, 200);
      });
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          auth: _auth(_Tm('t0')));
      Future<Response<dynamic>> call() => dio.get<dynamic>('/pub',
          options: Options(extra: {
            DiomanAuth.pluginName: const DiomanAuthOptions(enabled: false),
          }));

      final a = call();
      final b = call();
      await _settle();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(adapter.calls, 1);
      expect(rs[0].data, {'v': 1});
      expect(rs[1].data, {'v': 1});
      // registry 归零：下一次同key请求是全新请求，不会挂在残留 entry 上。
      await call().timeout(timeout);
      expect(adapter.calls, 2);
    });

    test('share + auth：mock 在 auth 之前短路也能结算 follower，且不残留 entry',
        () async {
      final gate = Completer<void>();
      final mock = DiomanMock(enabled: true)
        ..add('GET:/m', (o) async {
          await gate.future;
          return _json({'v': 1}, 200);
        });
      final adapter = _FakeAdapter((o, n) async => _json({'real': 1}, 200));
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          mock: mock,
          auth: _auth(_Tm('t0')));

      final a = dio.get<dynamic>('/m');
      final b = dio.get<dynamic>('/m');
      await _settle();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs.map((r) => r.data), [
        {'v': 1},
        {'v': 1}
      ]);
      expect(adapter.calls, 0, reason: 'mock 命中，真实网络一次都没发');
      final c = await dio.get<dynamic>('/m').timeout(timeout);
      expect(c.data, {'v': 1});
    });

    test('share + auth + retry：业务失败由 retry 恢复后，follower 拿到最终成功，'
        '不是 auth 提前结算的业务失败', () async {
      final gate = Completer<void>();
      final adapter = _FakeAdapter((o, n) async {
        if (n == 1) {
          await gate.future;
          return _json(_bizFail(), 200);
        }
        return _json(_ok(), 200);
      });
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          auth: _auth(_Tm('t0')),
          retry: _retry(shouldRetry: _bizShouldRetry),
          normalize: const DiomanNormalize());

      final a = dio.get<dynamic>('/biz');
      final b = dio.get<dynamic>('/biz');
      await _settle();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[0].data, {'v': 1});
      expect(rs[1].data, {'v': 1}, reason: 'follower 看到的是恢复后的最终结果');
      expect(adapter.calls, 2);
    });

    test('移除 retry 后 share 不再等它结算，不悬挂；旧 setter 重复调用无副作用',
        () async {
      final gate = Completer<void>();
      final adapter = _FakeAdapter((o, n) async {
        await gate.future;
        return _json({'v': n}, 200);
      });
      final dio = _dio(adapter);
      final share = DiomanShare();
      final retry = _retry();
      final handle = Dioman.install(dio,
          key: const DiomanKey(), share: share, retry: retry);
      // ignore: deprecated_member_use_from_same_package
      retry.share = share;
      // ignore: deprecated_member_use_from_same_package
      retry.share = share;
      handle.remove<DiomanRetry>();

      final a = dio.get<dynamic>('/x');
      final b = dio.get<dynamic>('/x');
      await _settle();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);
      expect(rs.map((r) => r.data), [
        {'v': 1},
        {'v': 1}
      ]);
    });

    test('share 先于 auth/retry 被移除重装：新 share 照常结算', () async {
      final adapter = _FakeAdapter((o, n) async => _json({'v': n}, 200));
      final dio = _dio(adapter);
      final handle = Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          auth: _auth(_Tm('t0')),
          retry: _retry());
      handle.remove<DiomanShare>();
      handle.insertAfter(handle.plugin<DiomanKey>()!, DiomanShare());

      final rs = await Future.wait([
        dio.get<dynamic>('/x'),
        dio.get<dynamic>('/x'),
      ]).timeout(timeout);
      expect(rs[0].data, rs[1].data);
      expect(adapter.calls, 1);
    });
  });

  group('end / race 全部失败（#5）', () {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      test('policy=${policy.name}：所有请求都失败时每个调用方都拿到 DioException，'
          '不抛 NoSuchMethodError，registry 归零', () async {
        final gates = <Completer<void>>[];
        var fail = true;
        final adapter = _FakeAdapter((o, n) async {
          if (!fail) return _json({'v': n}, 200);
          final g = Completer<void>();
          gates.add(g);
          await g.future;
          return _json({'e': n}, 500);
        });
        final dio = _dio(adapter);
        Dioman.install(dio,
            key: const DiomanKey(), share: DiomanShare(policy: policy));

        final a = dio.get<dynamic>('/x');
        final b = dio.get<dynamic>('/x');
        final ra = a.then<Object>((_) => 'ok', onError: (Object e) => e);
        final rb = b.then<Object>((_) => 'ok', onError: (Object e) => e);
        await _settle();
        expect(adapter.calls, 2);
        gates[0].complete(); // 先失败的是旧请求/先到的竞争者，需等最终结果
        await _settle();
        gates[1].complete();

        final results = await Future.wait([ra, rb]).timeout(timeout);
        for (final r in results) {
          expect(r, isA<DioException>());
          expect((r as DioException).response?.statusCode, 500);
        }
        fail = false;
        final c = await dio.get<dynamic>('/x').timeout(timeout);
        expect(c.data, isNotNull, reason: 'registry 已归零，新请求是全新请求');
      });
    }

    test('policy=end：落败者的 loading 括号也被释放（计数归零）', () async {
      final gates = <Completer<void>>[];
      final adapter = _FakeAdapter((o, n) async {
        final g = Completer<void>();
        gates.add(g);
        await g.future;
        return _json({'v': n}, 200);
      });
      final dio = _dio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.end),
          loading: loading);

      final a = dio.get<dynamic>('/x');
      final b = dio.get<dynamic>('/x');
      await _settle();
      gates[0].complete();
      await _settle();
      gates[1].complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[0].data, rs[1].data);
      expect(loading.activeCount, 0);
    });
  });

  group('follower 拿到独立的 Response（#6）', () {
    test('Response 不同实例、绑定各自的 RequestOptions，嵌套信封只解一层',
        () async {
      final gate = Completer<void>();
      final nested = {'code': 0, 'data': _ok(), 'message': ''};
      final adapter = _FakeAdapter((o, n) async {
        await gate.future;
        return _json(nested, 200);
      });
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          normalize: const DiomanNormalize());

      final a = dio.get<dynamic>('/x', options: Options(extra: {'who': 'L'}));
      final b = dio.get<dynamic>('/x', options: Options(extra: {'who': 'F'}));
      await _settle();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(identical(rs[0], rs[1]), isFalse);
      expect(rs[0].requestOptions.extra['who'], 'L');
      expect(rs[1].requestOptions.extra['who'], 'F');
      expect(rs[0].data, _ok());
      expect(rs[1].data, _ok(), reason: '每人各解一层，不会被多次解包');
    });

    test('follower 不会对 leader 已耗尽的重试再重试一轮', () async {
      final adapter = _FakeAdapter((o, n) async => _json(_bizFail(), 200));
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          retry: _retry(max: 2, shouldRetry: _bizShouldRetry));

      final rs = await Future.wait([
        dio.get<dynamic>('/x'),
        dio.get<dynamic>('/x'),
      ]).timeout(timeout);

      expect(rs[0].data, _bizFail());
      expect(rs[1].data, _bizFail());
      expect(adapter.calls, 3, reason: '1 次首发 + 2 次重试，follower 不额外重试');
    });
  });

  group('恢复成功后的结果要经过后续处理（#8）', () {
    test('auth 刷新重放成功：结果被 normalize 解包', () async {
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 401) : _json(_ok(), 200));
      final dio = _dio(adapter);
      final tm = _Tm('t0');
      Dioman.install(dio,
          auth: _auth(tm), normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>('/x').timeout(timeout);
      expect(r.data, {'v': 1});
      expect(tm.accessToken, 't1');
    });

    test('auth 重放成功但落到业务失败：normalize 照常把它转成错误', () async {
      final adapter = _FakeAdapter(
          (o, n) async => n == 1 ? _json({}, 401) : _json(_bizFail(), 200));
      final dio = _dio(adapter);
      Dioman.install(dio,
          auth: _auth(_Tm('t0')), normalize: const DiomanNormalize());

      await expectLater(
        dio.get<dynamic>('/x').timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<DiomanException>())),
      );
    });

    test('retry 错误阶段重试成功：结果被 normalize 解包', () async {
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 500) : _json(_ok(), 200));
      final dio = _dio(adapter);
      Dioman.install(dio,
          retry: _retry(), normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>('/x').timeout(timeout);
      expect(r.data, {'v': 1});
    });

    test('retry 业务失败恢复：结果被 normalize 解包', () async {
      final adapter = _FakeAdapter(
          (o, n) async => n == 1 ? _json(_bizFail(), 200) : _json(_ok(), 200));
      final dio = _dio(adapter);
      Dioman.install(dio,
          retry: _retry(shouldRetry: _bizShouldRetry),
          normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>('/x').timeout(timeout);
      expect(r.data, {'v': 1});
    });

    test('share policy=retry 内部重试成功：结果被 normalize 解包，loading 计数归零',
        () async {
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 500) : _json(_ok(), 200));
      final dio = _dio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.retry, retries: 1),
          loading: loading,
          normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>('/x').timeout(timeout);
      expect(r.data, {'v': 1});
      expect(loading.activeCount, 0);
    });
  });

  group('重放复用宿主传输层、处理请求体（#9）', () {
    test('retry 的重试走宿主的 adapter 和 transformer', () async {
      final transformer = _CountingTransformer();
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 500) : _json({'v': n}, 200));
      final dio = _dio(adapter, transformer: transformer);
      Dioman.install(dio, retry: _retry());

      final r = await dio.get<dynamic>('/x').timeout(timeout);
      expect(r.data, {'v': 2});
      expect(adapter.calls, 2);
      expect(transformer.responses, 2);
    });

    test('auth 的重放走宿主的 adapter 和 transformer', () async {
      final transformer = _CountingTransformer();
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 401) : _json({'v': n}, 200));
      final dio = _dio(adapter, transformer: transformer);
      Dioman.install(dio, auth: _auth(_Tm('t0')));

      final r = await dio.get<dynamic>('/x').timeout(timeout);
      expect(r.data, {'v': 2});
      expect(adapter.calls, 2);
      expect(transformer.responses, 2);
    });

    test('FormData 请求体重试时被克隆，可重复发送', () async {
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 500) : _json({'v': n}, 200));
      final dio = _dio(adapter);
      Dioman.install(dio, retry: _retry(methods: ['POST']));

      final r = await dio
          .post<dynamic>('/up', data: FormData.fromMap({'a': '1'}))
          .timeout(timeout);
      expect(r.data, {'v': 2});
      expect(adapter.calls, 2);
    });

    test('FormData 请求体在 auth 刷新后也能重放', () async {
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 401) : _json({'v': n}, 200));
      final dio = _dio(adapter);
      Dioman.install(dio, auth: _auth(_Tm('t0')));

      final r = await dio
          .post<dynamic>('/up', data: FormData.fromMap({'a': '1'}))
          .timeout(timeout);
      expect(r.data, {'v': 2});
      expect(adapter.seen.last.headers['Authorization'], 'Bearer t1');
    });

    test('Stream 请求体无法重放：retry 不自动重试，原错误照常抛出', () async {
      final adapter = _FakeAdapter((o, n) async => _json({}, 500));
      final dio = _dio(adapter);
      Dioman.install(dio, retry: _retry(methods: ['POST']));

      await expectLater(
        dio
            .post<dynamic>('/up',
                data: Stream.fromIterable([
                  Uint8List.fromList([1, 2, 3])
                ]),
                options: Options(headers: {Headers.contentLengthHeader: 3}))
            .timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 500)),
      );
      expect(adapter.calls, 1);
    });

    test('Stream 请求体 401：auth 刷新后也不重放，且不清会话', () async {
      final adapter = _FakeAdapter((o, n) async => _json({}, 401));
      final dio = _dio(adapter);
      final tm = _Tm('t0');
      var expired = 0;
      Dioman.install(dio, auth: _auth(tm, onExpired: () => expired++));

      await expectLater(
        dio
            .post<dynamic>('/up',
                data: Stream.fromIterable([
                  Uint8List.fromList([1])
                ]),
                options: Options(headers: {Headers.contentLengthHeader: 1}))
            .timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 401)),
      );
      expect(adapter.calls, 1);
      expect(tm.accessToken, 't1', reason: '刷新成功，只是请求体无法重放');
      expect(expired, 0);
    });
  });

  group('cancelAll 覆盖整个逻辑请求（#10）', () {
    test('retry 退避等待期间 cancelAll 能取消，且立刻结束等待', () async {
      final adapter = _FakeAdapter((o, n) async => _json({}, 500));
      final dio = _dio(adapter);
      Dioman.install(dio,
          cancel: DiomanCancel(),
          retry: DiomanRetry(
              max: 1, delay: (_, __, ___, ____) => const Duration(seconds: 30)));

      final call = dio.get<dynamic>('/x');
      final result = call.then<Object>((_) => 'ok', onError: (Object e) => e);
      await _settle(80); // 第一次 500 已回来，retry 正在退避
      expect(adapter.calls, 1);
      expect(cancelAll(dio, 'bye'), 1);

      final r = await result.timeout(const Duration(seconds: 2));
      expect(r, isA<DioException>());
      expect((r as DioException).type, DioExceptionType.cancel);
    });

    test('auth 刷新等待期间 cancelAll 能取消', () async {
      final refreshGate = Completer<void>();
      final adapter = _FakeAdapter((o, n) async => _json({}, 401));
      final dio = _dio(adapter);
      final tm = _Tm('t0');
      Dioman.install(dio,
          cancel: DiomanCancel(),
          auth: _auth(tm, onRefresh: (_, __) async {
            await refreshGate.future;
            tm.set('t1');
          }));

      final result = dio
          .get<dynamic>('/x')
          .then<Object>((_) => 'ok', onError: (Object e) => e);
      await _settle(80);
      expect(cancelAll(dio, 'bye'), 1);
      final r = await result.timeout(const Duration(seconds: 2));
      expect(r, isA<DioException>());
      expect((r as DioException).type, DioExceptionType.cancel);
      refreshGate.complete(); // 收尾，不留悬挂的 Future
    });

    test('share policy=retry 的内部重试等待期间可被取消', () async {
      final adapter = _FakeAdapter((o, n) async => _json({}, 500));
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(
              policy: DiomanSharePolicy.retry,
              retries: 3,
              interval: const Duration(seconds: 30)),
          cancel: DiomanCancel());

      final result = dio
          .get<dynamic>('/x')
          .then<Object>((_) => 'ok', onError: (Object e) => e);
      await _settle(80);
      expect(cancelAll(dio, 'bye'), 1);
      final r = await result.timeout(const Duration(seconds: 2));
      expect(r, isA<DioException>());
      expect(adapter.calls, 1, reason: '取消后不再继续循环重试');
    });

    test('逻辑请求正常结束后 token 注销，cancelAll 为 0', () async {
      final adapter = _FakeAdapter(
          (o, n) async => n == 1 ? _json({}, 401) : (n == 2 ? _json({}, 500) : _json(_ok(), 200)));
      final dio = _dio(adapter);
      Dioman.install(dio,
          cancel: DiomanCancel(), auth: _auth(_Tm('t0')), retry: _retry());

      await dio.get<dynamic>('/x').timeout(timeout);
      expect(cancelAll(dio), 0);
    });

    test('cancellableDelay：取消时立刻结束；时间到自然结束', () async {
      final token = CancelToken();
      final sw = Stopwatch()..start();
      final f = cancellableDelay(const Duration(seconds: 30), token);
      token.cancel('x');
      await f.timeout(const Duration(seconds: 1));
      expect(sw.elapsedMilliseconds, lessThan(1000));
      await cancellableDelay(const Duration(milliseconds: 10), CancelToken());
    });
  });

  group('刷新成功后的重放失败（#11）', () {
    test('重放遇到 500：有效 token 保留、不触发过期，抛出 500 而不是旧 401',
        () async {
      final adapter =
          _FakeAdapter((o, n) async => n == 1 ? _json({}, 401) : _json({}, 500));
      final dio = _dio(adapter);
      final tm = _Tm('t0');
      var expired = 0;
      Dioman.install(dio, auth: _auth(tm, onExpired: () => expired++));

      await expectLater(
        dio.get<dynamic>('/x').timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 500)),
      );
      expect(tm.accessToken, 't1');
      expect(expired, 0);
    });

    test('重放仍是 401：明确的认证失败，清会话并触发过期', () async {
      final adapter = _FakeAdapter((o, n) async => _json({}, 401));
      final dio = _dio(adapter);
      final tm = _Tm('t0');
      var expired = 0;
      Dioman.install(dio, auth: _auth(tm, onExpired: () => expired++));

      await expectLater(
          dio.get<dynamic>('/x').timeout(timeout), throwsA(isA<DioException>()));
      expect(tm.accessToken, isNull);
      expect(expired, 1);
    });

    test('清会话前校验 token generation：别人已刷新出新 token 就不清', () async {
      final tm = _Tm('t0');
      final adapter = _FakeAdapter((o, n) async {
        if (n == 1) return _json({}, 401);
        tm.set('t2'); // 重放进行中，别的请求又刷新出了新会话
        return _json({}, 401);
      });
      final dio = _dio(adapter);
      var expired = 0;
      Dioman.install(dio, auth: _auth(tm, onExpired: () => expired++));

      await expectLater(
          dio.get<dynamic>('/x').timeout(timeout), throwsA(isA<DioException>()));
      expect(tm.accessToken, 't2');
      expect(expired, 0);
    });
  });

  group('retry 回调异常（#13）', () {
    test('错误阶段 shouldRetry 抛异常：转成 DioException，且 share 的 follower 不悬挂',
        () async {
      final gate = Completer<void>();
      final adapter = _FakeAdapter((o, n) async {
        await gate.future;
        return _json({}, 500);
      });
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          retry: _retry(shouldRetry: (_, __) => throw StateError('boom')));

      final a = dio.get<dynamic>('/x').then<Object>((_) => 'ok', onError: (Object e) => e);
      final b = dio.get<dynamic>('/x').then<Object>((_) => 'ok', onError: (Object e) => e);
      await _settle();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      for (final r in rs) {
        expect(r, isA<DioException>());
      }
      expect((rs[0] as DioException).error, isA<StateError>());
    });

    test('响应阶段 shouldRetry 抛异常：转成 DioException，handler 只完成一次',
        () async {
      final adapter = _FakeAdapter((o, n) async => _json(_ok(), 200));
      final dio = _dio(adapter);
      Dioman.install(dio,
          retry: _retry(shouldRetry: (_, __) => throw StateError('boom')));

      await expectLater(
        dio.get<dynamic>('/x').timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<StateError>())),
      );
    });

    test('onRetry 抛异常：转成 DioException', () async {
      final adapter = _FakeAdapter((o, n) async => _json({}, 500));
      final dio = _dio(adapter);
      Dioman.install(dio,
          retry: _retry(onRetry: (_) => throw StateError('boom')));

      await expectLater(
        dio.get<dynamic>('/x').timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.error, 'error', isA<StateError>())),
      );
      expect(adapter.calls, 1);
    });
  });

  group('timeout 两级查找（simplify）', () {
    test('单请求覆盖只替换对应档位，其余档位回落到插件配置', () async {
      final adapter = _FakeAdapter((o, n) async => _json({'v': 1}, 200));
      final dio = _dio(adapter);
      var quality = NetworkQuality.poor;
      Dioman.install(dio,
          timeout: DiomanTimeout(
            probe: () => quality,
            timeouts: {
              NetworkQuality.poor:
                  const DiomanTimeouts(connect: Duration(seconds: 30)),
              NetworkQuality.good:
                  const DiomanTimeouts(connect: Duration(seconds: 15)),
            },
          ));
      final override = Options(extra: {
        DiomanTimeout.pluginName: const DiomanTimeoutOptions(timeouts: {
          NetworkQuality.good: DiomanTimeouts(connect: Duration(seconds: 1)),
        }),
      });

      await dio.get<dynamic>('/x', options: override);
      expect(adapter.seen.last.connectTimeout, const Duration(seconds: 30));
      quality = NetworkQuality.good;
      await dio.get<dynamic>('/x', options: override);
      expect(adapter.seen.last.connectTimeout, const Duration(seconds: 1));
      quality = NetworkQuality.none;
      await dio.get<dynamic>('/x', options: override);
      expect(adapter.seen.last.connectTimeout, isNot(const Duration(seconds: 1)));
    });
  });

  group('下游 reject 的传播标志（review2 #6）', () {
    /// 在链尾追加：onResponse 里 reject 的拦截器，以及统计 onError 次数的探针。
    ({Interceptor rejecter, Interceptor spy, List<int> errorCalls})
        tail({required bool callFollowing}) {
      final errorCalls = <int>[];
      final rejecter = InterceptorsWrapper(
        onResponse: (r, h) => h.reject(
          DioException(requestOptions: r.requestOptions, message: 'downstream'),
          callFollowing,
        ),
      );
      final spy = InterceptorsWrapper(onError: (e, h) {
        errorCalls.add(1);
        h.next(e);
      });
      return (rejecter: rejecter, spy: spy, errorCalls: errorCalls);
    }

    for (final recovery in ['retry', 'auth']) {
      for (final following in [false, true]) {
        test('$recovery 恢复后下游 reject(callFollowing=$following)：'
            '${following ? "后续错误拦截器继续执行" : "直接终止，后续错误拦截器不再执行"}',
            () async {
          final adapter = _FakeAdapter((o, n) async =>
              n == 1 ? _json({}, recovery == 'retry' ? 500 : 401) : _json(_ok(), 200));
          final dio = _dio(adapter);
          final cancel = DiomanCancel();
          Dioman.install(dio,
              key: const DiomanKey(),
              share: DiomanShare(),
              cancel: cancel,
              auth: recovery == 'auth' ? _auth(_Tm('t0')) : null,
              retry: recovery == 'retry' ? _retry() : null);
          final t = tail(callFollowing: following);
          dio.interceptors..add(t.rejecter)..add(t.spy);

          await expectLater(
            dio.get<dynamic>('/x').timeout(timeout),
            throwsA(isA<DioException>()
                .having((e) => e.message, 'message', 'downstream')),
          );
          expect(t.errorCalls.length, following ? 1 : 0);
          expect(adapter.calls, 2, reason: '后续错误拦截器不会再触发额外恢复');
          expect(cancelAll(dio), 0, reason: '认领已释放，token 已注销');
          // share registry 归零：同 key 的新请求不悬挂。
          adapter.calls = 0;
          await dio.get<dynamic>('/x').then((_) {}, onError: (_) {}).timeout(timeout);
        });
      }
    }
  });

  group('auth 请求入口回调抛异常（review2 #5）', () {
    for (final which in ['expiresAt', 'now', 'buildHeader', 'isProtected']) {
      test('$which 抛异常：转成 DioException，不悬挂，认领与 share 条目都释放',
          () async {
        var boom = true;
        final adapter = _FakeAdapter((o, n) async => _json({'v': n}, 200));
        final dio = _dio(adapter);
        final tm = _Tm('t0');
        final cancel = DiomanCancel();
        final auth = DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set('t1'),
          onAccessExpired: (_, __) async {},
          isProtected: which == 'isProtected'
              ? (_) => boom ? throw StateError('isProtected') : true
              : null,
          expiresAt: (which == 'expiresAt' || which == 'now')
              ? (t) => boom && which == 'expiresAt'
                  ? throw StateError('expiresAt')
                  : DateTime(2999)
              : null,
          now: which == 'now'
              ? () => boom ? throw StateError('now') : DateTime(2000)
              : DateTime.now,
          buildHeader: which == 'buildHeader'
              ? (t) => boom ? throw StateError('buildHeader') : 'B $t'
              : null,
        );
        Dioman.install(dio,
            key: const DiomanKey(),
            share: DiomanShare(),
            cancel: cancel,
            auth: auth);

        final rs = await Future.wait([
          dio.get<dynamic>('/x').then<Object>((_) => 'ok', onError: (Object e) => e),
          dio.get<dynamic>('/x').then<Object>((_) => 'ok', onError: (Object e) => e),
        ]).timeout(timeout);
        for (final r in rs) {
          expect(r, isA<DioException>());
          expect((r as DioException).error, isA<StateError>());
        }
        expect(adapter.calls, 0);
        expect(cancelAll(dio), 0, reason: 'token 已注销');

        boom = false;
        final ok = await dio.get<dynamic>('/x').timeout(timeout);
        expect(ok.data, {'v': 1}, reason: 'share 条目已清，新请求是全新请求');
      });
    }
  });

  group('错误恢复成功后 follower 只处理一次（review2 #1）', () {
    final nested = {'code': 0, 'data': _ok(), 'message': ''};

    /// 首发 500（卡在 gate 上，让 follower 先加入），之后返回嵌套信封。
    _FakeAdapter failThenNested(Completer<void> gate, {int failStatus = 500}) =>
        _FakeAdapter((o, n) async {
          if (n == 1) {
            await gate.future;
            return _json({}, failStatus);
          }
          return _json(nested, 200);
        });

    for (final via in ['retry', 'auth', 'share-retry']) {
      test('share + $via + normalize：leader 恢复后 follower 只解一层信封', () async {
        final gate = Completer<void>();
        final adapter = failThenNested(gate, failStatus: via == 'auth' ? 401 : 500);
        final dio = _dio(adapter);
        Dioman.install(dio,
            key: const DiomanKey(),
            share: DiomanShare(
                policy: via == 'share-retry'
                    ? DiomanSharePolicy.retry
                    : DiomanSharePolicy.start,
                retries: 1),
            auth: via == 'auth' ? _auth(_Tm('t0')) : null,
            retry: via == 'retry' ? _retry() : null,
            normalize: const DiomanNormalize());

        final a = dio.get<dynamic>('/x');
        final b = dio.get<dynamic>('/x');
        await _settle();
        gate.complete();
        final rs = await Future.wait([a, b]).timeout(timeout);

        expect(rs[0].data, _ok());
        expect(rs[1].data, _ok(), reason: 'follower 不能把已解包的结果再解一层');
        expect(adapter.calls, 2);
      });
    }
  });

  group('错误阶段落败者的收尾（review2 #2）', () {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      test('policy=${policy.name}：A 失败、B 成功后 loading 归零、cancel 登记清空、'
          '认领注销', () async {
        final gates = <Completer<int>>[];
        final adapter = _FakeAdapter((o, n) async {
          final g = Completer<int>();
          gates.add(g);
          final status = await g.future;
          return _json({'v': n}, status);
        });
        final dio = _dio(adapter);
        final loading = DiomanLoading(onChanged: (_) {});
        Dioman.install(dio,
            key: const DiomanKey(),
            share: DiomanShare(policy: policy),
            cancel: DiomanCancel(),
            loading: loading);

        final a = dio.get<dynamic>('/x');
        final b = dio.get<dynamic>('/x');
        await _settle();
        gates[0].complete(500); // A 先失败，B 还在途
        await _settle();
        gates[1].complete(200);
        final rs = await Future.wait([a, b]).timeout(timeout);

        expect(rs[0].data, {'v': 2});
        expect(rs[1].data, {'v': 2});
        expect(loading.activeCount, 0);
        expect(cancelAll(dio), 0);
      });
    }

    test('policy=end + auth：被取代的 A 失败后，auth 认领注销，token 登记清空', () async {
      final gates = <Completer<int>>[];
      final adapter = _FakeAdapter((o, n) async {
        final g = Completer<int>();
        gates.add(g);
        final status = await g.future;
        return _json({'v': n}, status);
      });
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.end),
          cancel: DiomanCancel(),
          auth: _auth(_Tm('t0')));

      final a = dio.get<dynamic>('/x');
      final b = dio.get<dynamic>('/x');
      await _settle();
      gates[0].complete(500);
      await _settle();
      gates[1].complete(200);
      final rs = await Future.wait([a, b]).timeout(timeout);
      expect(rs.map((r) => r.data), [
        {'v': 2},
        {'v': 2}
      ]);
      expect(cancelAll(dio), 0);
    });
  });

  group('end / race 的最终仲裁（review2 #3）', () {
    test('race + retry：A 重试后仍失败而 B 尚未完成时，A 不抛错，等 B 的成功结果',
        () async {
      final gates = <Completer<void>>[];
      final adapter = _FakeAdapter((o, n) async {
        if (n <= 2) {
          final g = Completer<void>();
          gates.add(g);
          await g.future;
          return n == 1 ? _json({'e': n}, 500) : _json({'v': n}, 200);
        }
        return _json({'e': n}, 500); // A 的重试
      });
      final dio = _dio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.race),
          cancel: DiomanCancel(),
          loading: loading,
          retry: _retry());

      final a = dio.get<dynamic>('/x').then<Object>((r) => r, onError: (Object e) => e);
      final b = dio.get<dynamic>('/x').then<Object>((r) => r, onError: (Object e) => e);
      await _settle();
      gates[0].complete(); // A 首发失败，重试也失败（第 3 次调用）
      await _settle();
      gates[1].complete(); // B 成功
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[0], isA<Response<dynamic>>(), reason: 'A 不应在 B 完成前抛错');
      expect((rs[0] as Response).data, {'v': 2});
      expect((rs[1] as Response).data, {'v': 2});
      expect(loading.activeCount, 0);
      expect(cancelAll(dio), 0);
    });

    test('end + retry：A 恢复期间被 B 取代，A 返回 B 的结果而不是自己的恢复结果',
        () async {
      final adapter = _FakeAdapter((o, n) async {
        if (n == 1) return _json({'e': 1}, 500);
        return _json({'v': n}, 200);
      });
      final dio = _dio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.end),
          cancel: DiomanCancel(),
          loading: loading,
          retry: DiomanRetry(
              max: 1, delay: (_, __, ___, ____) => const Duration(milliseconds: 150)));

      final a = dio.get<dynamic>('/x');
      await _settle(50); // A 首发已失败，正在退避
      final b = dio.get<dynamic>('/x'); // B 取代 A，直接成功（第 2 次调用）
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[1].data, {'v': 2});
      expect(rs[0].data, {'v': 2}, reason: 'A 已被取代，不应返回自己的恢复结果（第 3 次调用）');
      expect(loading.activeCount, 0);
      expect(cancelAll(dio), 0);
    });
  });

  group('取消时释放刷新等待中的认领（review2 #4）', () {
    test('请求入口等共享刷新时被取消：立刻结束并注销 token 登记', () async {
      final refreshStarted = Completer<void>();
      final adapter = _FakeAdapter((o, n) async => _json({}, 401));
      final dio = _dio(adapter);
      Dioman.install(dio,
          cancel: DiomanCancel(),
          auth: _auth(_Tm('t0'), onRefresh: (_, __) {
            if (!refreshStarted.isCompleted) refreshStarted.complete();
            return Completer<void>().future; // 永不完成
          }));

      final a = dio.get<dynamic>('/a').then<Object>((_) => 'ok', onError: (Object e) => e);
      await refreshStarted.future.timeout(timeout);
      final token = CancelToken();
      final b = dio
          .get<dynamic>('/b', cancelToken: token)
          .then<Object>((_) => 'ok', onError: (Object e) => e);
      await _settle();
      token.cancel('stop b');
      final rb = await b.timeout(timeout);
      expect((rb as DioException).type, DioExceptionType.cancel);
      await _settle();
      expect(cancelAll(dio, 'bye'), 1, reason: 'b 的认领已注销，只剩 a 在登记');
      await a.timeout(timeout);
    });

    test('leader 在 auth 刷新等待时被取消：认领释放，follower 不悬挂，token 登记清空',
        () async {
      final refreshStarted = Completer<void>();
      final adapter = _FakeAdapter((o, n) async => _json({}, 401));
      final dio = _dio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          cancel: DiomanCancel(),
          auth: _auth(_Tm('t0'), onRefresh: (_, __) {
            if (!refreshStarted.isCompleted) refreshStarted.complete();
            return Completer<void>().future; // 永不完成，刻意不放行
          }));

      final a = dio.get<dynamic>('/x').then<Object>((_) => 'ok', onError: (Object e) => e);
      final b = dio.get<dynamic>('/x').then<Object>((_) => 'ok', onError: (Object e) => e);
      await refreshStarted.future.timeout(timeout);
      await _settle();
      expect(cancelAll(dio, 'bye'), 1);

      final rs = await Future.wait([a, b]).timeout(timeout);
      expect(rs[0], isA<DioException>());
      expect((rs[0] as DioException).type, DioExceptionType.cancel);
      expect(rs[1], isA<DioException>(), reason: 'follower 随 leader 结算，不挂在旧 entry 上');
      expect(cancelAll(dio), 0);
    });
  });

  group('取消类错误不等待胜出结果（取消悬挂）', () {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      for (final withAuth in [false, true]) {
        test('policy=${policy.name}${withAuth ? ' + auth' : ''}：只取消落败者 A、'
            'B 永不完成，A 以 cancel 结束并释放登记', () async {
          final never = Completer<ResponseBody>();
          final adapter = _FakeAdapter((o, n) => never.future);
          final dio = _dio(adapter);
          final loading = DiomanLoading(onChanged: (_) {});
          Dioman.install(dio,
              key: const DiomanKey(),
              share: DiomanShare(policy: policy),
              cancel: DiomanCancel(),
              loading: loading,
              auth: withAuth ? _auth(_Tm('t0')) : null);

          final token = CancelToken();
          final a = dio
              .get<dynamic>('/x', cancelToken: token)
              .then<Object>((_) => 'ok', onError: (Object e) => e);
          final b = dio.get<dynamic>('/x'); // 永不完成
          unawaited(b.then<void>((_) {}, onError: (Object _) {}));
          await _settle();
          token.cancel('bye');

          final ra = await a.timeout(timeout);
          expect(ra, isA<DioException>());
          expect((ra as DioException).type, DioExceptionType.cancel);
          expect(loading.activeCount, 1, reason: '只剩 B 在途');
          expect(cancelAll(dio), 1, reason: 'A 的登记已注销，只剩 B');
        });
      }
    }
  });
}
