// 规则层：retry 的重试判定、次数、退避回调、宿主绑定与释放
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 插件名 / extra 键的期望值。
const _pluginName = 'dioman:retry';

/// 兜底超时，防止重试逻辑失效时用例挂住。
const _guard = Duration(seconds: 3);

/// 零退避，保持用例迅速。
Duration _noWait(int c, int m, Response<dynamic>? r, DioException? e) =>
    Duration.zero;

/// 带单请求覆盖的 Options。
Options _override(DiomanRetryOptions o) =>
    Options(extra: {DiomanRetry.pluginName: o});

/// 首发回 [status]、重试回 200，返回适配器收到的请求总数（没被重试就是 1）。
Future<int> _callsForStatus(
  int status, {
  List<int>? statusCodes,
  DiomanRetryOptions? override,
}) async {
  final adapter =
      RecordingAdapter((o, n) async => jsonBody({}, n == 1 ? status : 200));
  final dio = fakeDio(adapter);
  final handle = Dioman.install(dio,
      retry: DiomanRetry(max: 1, statusCodes: statusCodes, delay: _noWait));
  try {
    await dio
        .get<dynamic>('/x',
            options: override == null ? null : _override(override))
        .timeout(_guard);
  } on DioException catch (_) {
    // 没重试时错误原样抛出，由调用次数断言。
  } finally {
    handle.dispose();
  }
  return adapter.calls;
}

/// 适配器每次都回 500，返回收到的请求总数。
Future<int> _callsAlwaysFailing(
    {int pluginMax = 0, DiomanRetryOptions? override}) async {
  final adapter = RecordingAdapter((o, n) async => jsonBody({}, 500));
  final dio = fakeDio(adapter);
  final handle =
      Dioman.install(dio, retry: DiomanRetry(max: pluginMax, delay: _noWait));
  try {
    await dio
        .get<dynamic>('/x',
            options: override == null ? null : _override(override))
        .timeout(_guard);
  } on DioException catch (_) {
    // 重试耗尽后抛出最后一次错误。
  } finally {
    handle.dispose();
  }
  return adapter.calls;
}

/// 首发抛出类型为 [type] 的 DioException（没有响应），重试回 200，返回请求总数。
Future<int> _callsForNetworkFailure(DioExceptionType type,
    {List<int>? statusCodes}) async {
  final adapter = RecordingAdapter((o, n) async => n == 1
      ? throw DioException(requestOptions: o, type: type)
      : jsonBody({}, 200));
  final dio = fakeDio(adapter);
  final handle = Dioman.install(dio,
      retry: DiomanRetry(max: 1, statusCodes: statusCodes, delay: _noWait));
  try {
    await dio.get<dynamic>('/x').timeout(_guard);
  } on DioException catch (_) {
    // 不可重试的类型直接抛出。
  } finally {
    handle.dispose();
  }
  return adapter.calls;
}

/// 注册本文件的规则层用例。
void main() {
  test(
      '[DiomanRetry.name][DiomanRetry.pluginName] 插件名固定为 dioman:retry，同时是单请求覆盖的 extra 键',
      () async {
    expect(DiomanRetry.pluginName, _pluginName);
    expect(DiomanRetry().name, DiomanRetry.pluginName);

    final adapter = RecordingAdapter((o, n) async => jsonBody({}, 500));
    final dio = fakeDio(adapter);
    final handle =
        Dioman.install(dio, retry: DiomanRetry(max: 2, delay: _noWait));
    addTearDown(handle.dispose);

    // 用静态常量当 extra 键：false 关掉本次重试，整数只改次数。
    await expectLater(
        dio.get<dynamic>('/x',
            options: Options(extra: {DiomanRetry.pluginName: false})),
        throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
    await expectLater(
        dio.get<dynamic>('/x',
            options: Options(extra: {DiomanRetry.pluginName: 1})),
        throwsA(isA<DioException>()));
    expect(adapter.calls, 3, reason: '1 次重试：本次共 2 个请求');
  });

  group('状态码表 statusCodes', () {
    test(
        '[DiomanRetry.statusCodes][DiomanRetry.new(statusCodes)] 没有自定义判定时按状态码表：默认 408/429/500/502/503/504 重试，其余状态直接抛出；自定义表替换默认',
        () async {
      for (final status in [408, 429, 500, 502, 503, 504]) {
        expect(await _callsForStatus(status), 2, reason: '$status 在默认表里');
      }
      for (final status in [400, 401, 404, 418]) {
        expect(await _callsForStatus(status), 1, reason: '$status 不在默认表里');
      }
      expect(await _callsForStatus(418, statusCodes: [418]), 2);
      expect(await _callsForStatus(500, statusCodes: [418]), 1,
          reason: '自定义表是替换，500 不再被重试');
    });

    test(
        '[DiomanRetry.statusCodes][DiomanRetry.new(statusCodes)] 没有 HTTP 状态的网络失败按异常类型判断：超时与连接错误重试，其余类型不重试（与状态码表无关）',
        () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(await _callsForNetworkFailure(type), 2, reason: '$type 应当重试');
        expect(await _callsForNetworkFailure(type, statusCodes: [418]), 2,
            reason: '$type 没有状态码，自定义状态码表不影响它');
      }
      for (final type in [
        DioExceptionType.badCertificate,
        DioExceptionType.unknown,
      ]) {
        expect(await _callsForNetworkFailure(type), 1, reason: '$type 不重试');
      }
    });

    test(
        '[DiomanRetryOptions.statusCodes][DiomanRetryOptions.new(statusCodes)] 单请求覆盖可重试状态码表',
        () async {
      expect(
          await _callsForStatus(418,
              override: const DiomanRetryOptions(statusCodes: [418])),
          2,
          reason: '覆盖后 418 可重试');
      expect(
          await _callsForStatus(500,
              override: const DiomanRetryOptions(statusCodes: [418])),
          1,
          reason: '覆盖是替换：默认可重试的 500 这次不重试');
    });
  });

  group('次数与退避回调', () {
    test(
        '[DiomanRetryOptions.max][DiomanRetryOptions.new(max)] 单请求覆盖最大重试次数，0 表示这次不重试',
        () async {
      expect(await _callsAlwaysFailing(), 1, reason: '插件 max=0，不重试');
      expect(
          await _callsAlwaysFailing(override: const DiomanRetryOptions(max: 2)),
          3,
          reason: '覆盖成 2：首发 + 2 次重试');
      expect(
          await _callsAlwaysFailing(
              pluginMax: 3, override: const DiomanRetryOptions(max: 1)),
          2,
          reason: '覆盖成 1 压过插件的 3');
      expect(
          await _callsAlwaysFailing(
              pluginMax: 3, override: const DiomanRetryOptions(max: 0)),
          1,
          reason: '覆盖成 0 关掉本次重试');
    });

    test(
        '[DiomanRetryOptions.delay][DiomanRetryOptions.new(delay)] 单请求的退避函数取代插件的，并拿到 (当前次数, 最大次数, 响应, 错误)',
        () async {
      final pluginArgs = <int>[];
      final seen = <({int current, int max, int? status, bool hasErr})>[];
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 500));
      final dio = fakeDio(adapter);
      final handle = Dioman.install(dio,
          retry: DiomanRetry(
              max: 2,
              delay: (c, m, r, e) {
                pluginArgs.add(c);
                return Duration.zero;
              }));
      addTearDown(handle.dispose);

      await expectLater(
          dio.get<dynamic>('/x',
              options: _override(DiomanRetryOptions(delay: (c, m, r, e) {
            seen.add((
              current: c,
              max: m,
              status: (r ?? e?.response)?.statusCode,
              hasErr: e != null
            ));
            return Duration.zero;
          }))),
          throwsA(isA<DioException>()));

      expect(pluginArgs, isEmpty, reason: '单请求的函数取代插件的，插件的不会被调用');
      expect(seen, [
        (current: 1, max: 2, status: 500, hasErr: true),
        (current: 2, max: 2, status: 500, hasErr: true),
      ]);
    });
  });

  group('错误阶段 onError', () {
    test('[DiomanRetry.onError] 可重试的错误按退避重放，重试成功的响应当作最终结果交给调用方；耗尽后抛出最后一次错误',
        () async {
      final attempts = <int>[];
      final adapter = RecordingAdapter((o, n) async =>
          n == 1 ? jsonBody({'n': n}, 500) : jsonBody({'n': n}, 200));
      final dio = fakeDio(adapter);
      final handle = Dioman.install(dio,
          retry: DiomanRetry(max: 2, delay: _noWait, onRetry: attempts.add));
      addTearDown(handle.dispose);

      final res = await dio.get<dynamic>('/x').timeout(_guard);
      expect(res.data, {'n': 2}, reason: '拿到的是重试成功的那次响应');
      expect(attempts, [1]);
      expect(adapter.calls, 2);

      // 耗尽：每次都失败，最后一次错误（503）原样抛出。
      final statuses = [500, 502, 503];
      final failing =
          RecordingAdapter((o, n) async => jsonBody({}, statuses[n - 1]));
      final dio2 = fakeDio(failing);
      final handle2 =
          Dioman.install(dio2, retry: DiomanRetry(max: 2, delay: _noWait));
      addTearDown(handle2.dispose);
      await expectLater(
          dio2.get<dynamic>('/x').timeout(_guard),
          throwsA(isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', 503)));
      expect(failing.calls, 3);
    });

    test('[DiomanRetry.onError] 重放时请求体原样重发（POST + JSON body，methods 放行 POST）',
        () async {
      final bodies = <String>[];
      final server = await TestServer.start((req) async {
        bodies.add(await utf8.decoder.bind(req).join());
        await respondJson(req, {'ok': true}, bodies.length == 1 ? 500 : 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final handle = Dioman.install(dio,
          retry: DiomanRetry(max: 1, methods: ['POST'], delay: _noWait));
      addTearDown(handle.dispose);

      final res =
          await dio.post<dynamic>('/x', data: {'k': 'v'}).timeout(_guard);

      expect(res.statusCode, 200);
      expect(bodies, ['{"k":"v"}', '{"k":"v"}'], reason: '两次到达服务端的请求体一致');
    });
  });

  group('宿主绑定 dio 与释放 dispose', () {
    /// 宿主 Dio 的适配器奇数次回 500、偶数次回 200；基址指向 [server]。
    (Dio, RecordingAdapter, CountingTransformer) hostFor(TestServer server) {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody({}, n.isOdd ? 500 : 200));
      final transformer = CountingTransformer();
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl))
        ..httpClientAdapter = adapter
        ..transformer = transformer;
      return (dio, adapter, transformer);
    }

    test('[DiomanRetry.dio] 绑定宿主后重发借用宿主的 adapter 与 transformer；解绑后退回独立传输层',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'real': true}, 200);
      });
      addTearDown(server.close);
      final (dio, adapter, transformer) = hostFor(server);
      final retry = DiomanRetry(max: 1, delay: _noWait);
      addTearDown(retry.dispose);
      dio.interceptors.add(retry);

      retry.dio = dio; // 手动绑定，不经 Dioman.install
      final bound = await dio.get<dynamic>('/x').timeout(_guard);
      expect(bound.statusCode, 200);
      expect(adapter.calls, 2, reason: '首发和重试都走宿主适配器');
      expect(transformer.responses, 2, reason: '重试复用宿主 transformer');
      expect(hits, 0, reason: '没有流量落到真实服务');

      retry.dio = null; // 解绑：重发改用独立的裸 Dio，直连真实服务
      final unbound = await dio.get<dynamic>('/x').timeout(_guard);
      expect(unbound.data, {'real': true});
      expect(adapter.calls, 3, reason: '首发仍走宿主适配器（失败），重试没有');
      expect(hits, 1);
    });

    test('[DiomanRetry.dispose] 释放后不再借用宿主传输层，重发改走独立传输层；重复释放安全', () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {'real': true}, 200);
      });
      addTearDown(server.close);
      final (dio, adapter, _) = hostFor(server);
      final retry = DiomanRetry(max: 1, delay: _noWait);
      dio.interceptors.add(retry);
      retry.dio = dio;

      await dio.get<dynamic>('/x').timeout(_guard);
      expect(adapter.calls, 2);
      expect(hits, 0);

      retry.dispose();
      retry.dispose(); // 幂等
      final after = await dio.get<dynamic>('/x').timeout(_guard);
      expect(after.data, {'real': true}, reason: '重试结果来自真实服务');
      expect(adapter.calls, 3);
      expect(hits, 1, reason: '释放后重发不再经过宿主适配器');
    });
  });
}
