import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/helpers.dart';
import '../support/b3_helpers.dart' show b3Turn;
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/invariant_harness.dart';

/// 原生槽用例共用路径与请求方法。
const _path = '/native', _method = 'GET';

/// 落定路径和原始栈标记。
const _returned = 'return',
    _thrown = 'throw',
    _rejected = 'reject',
    _internal = 'internal',
    _stack = 'native-original-stack';

/// 原生槽的身份、尝试覆盖及落定契约。
void main() {
  for (final raw in [false, true]) {
    for (final status in [200, 503]) {
      test(
          '[DiomanCall.raw][DiomanCall.new(raw)][DiomanResponse.raw][DiomanResponse.error] 自身成功与失败 raw=$raw status=$status',
          () async {
        final network = FakeNetwork()
          ..routes['$_method:$_path'] = [FakeReply(status: status)];
        DiomanNative? observed;
        Result? original;
        final api = testClient(network: network, debug: true, plugins: [
          TestPlugin('native', handler: (ctx, next) async {
            original =
                await next(const RequestPatch(headers: {'x-native': 'yes'}));
            observed = ctx.native;
            return ctx.factory.derive(original!, original!.data);
          })
        ]);
        final result =
            await api.send<Object?>(_method, _path, call: DiomanCall(raw: raw));
        expect(original!.raw, isNull);
        expect(original!.error, isNull);
        expect(observed!.raw!.statusCode, status);
        expect(result.raw, raw ? same(observed!.raw) : isNull);
        expect(result.error, isNull);
        expect(result.ok, status == 200);
      });
    }
  }

  test('[DiomanResponse.error][DiomanCall.raw] 网络失败按需附自身异常', () async {
    final options = RequestOptions(path: _path);
    final error = DioException(
        requestOptions: options, type: DioExceptionType.connectionError);
    for (final raw in [false, true]) {
      final network = FakeNetwork()..failOn[1] = error;
      final api = testClient(network: network);
      final result =
          await api.send<Object?>(_method, _path, call: DiomanCall(raw: raw));
      expect(result.raw, isNull);
      expect(result.error, raw ? same(error) : isNull);
      expect(failureOf(result)!.error, isNull);
      expect(failureOf(result)!.errorStack, isNull);
    }
  });

  for (final path in [_returned, _thrown, _rejected, _internal]) {
    test(
        '[Dioman.send][Dioman.reject][DiomanFailure.error][DiomanFailure.errorStack] I11 $path 落定清空并拒绝迟到写入',
        () async {
      final network = FakeNetwork()
        ..routes['$_method:$_path'] = [
          FakeReply(status: path == _returned ? 200 : 503)
        ];
      final clock = FakeClock();
      final harness = InvariantHarness(network, clock);
      final error = StateError(_rejected);
      final stack = StackTrace.fromString(_stack);
      final api = testClient(
          network: network,
          clock: clock,
          reject: path == _rejected
              ? (result) {
                  expect(
                      harness.contexts.single.native?.response, same(result));
                  throw error;
                }
              : null,
          plugins: path == _internal
              ? [
                  TestPlugin(_internal, handler: (ctx, next) async {
                    harness.contexts.add(ctx);
                    await next();
                    Error.throwWithStackTrace(error, stack);
                  })
                ]
              : harness.probes());
      if (path == _returned) {
        await harness.track(1, api.send<Object?>(_method, _path));
      } else if (path == _internal) {
        try {
          await api.send<Object?>(_method, _path);
          fail('应抛原始异常');
        } catch (e, s) {
          expect(e, same(error));
          expect(s.toString(), contains(_stack));
        }
      } else {
        await expectLater(
            harness.track(
                1, api.get<Object?>(_path, call: const DiomanCall(raw: true))),
            throwsA(path == _rejected
                ? same(error)
                : isA<DiomanResponse>()
                    .having((r) => r.raw, 'raw', isNotNull)));
      }
      if (path != _internal) harness.assertAll(api);
      for (final ctx in harness.contexts) {
        NativeSlotProbe.assertClosed(ctx);
      }
    });
  }

  test('[DiomanContext.native][DiomanCall.raw] 重试成功清空上次异常', () async {
    final network = FakeNetwork()
      ..failOn[1] = DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError);
    final clock = FakeClock();
    final api = testClient(
        network: network, clock: clock, plugins: [const DiomanRetry(max: 1)]);
    final pending =
        api.send<Object?>(_method, _path, call: const DiomanCall(raw: true));
    for (var i = 0; i < 100 && clock.pendingTimers == 0; i++) {
      await b3Turn();
    }
    expect(clock.pendingTimers, 1);
    clock.elapse(const Duration(milliseconds: 300));
    await b3Turn();
    final result = await pending;
    expect(result.ok, isTrue);
    expect(result.raw, isNotNull);
    expect(result.error, isNull);
  });
  for (final cancelled in [false, true]) {
    test(
        '[DiomanNext][DiomanContext.native] 已传输后短路立即解除原生视图 cancelled=$cancelled',
        () async {
      final token = CancelToken();
      final api = testClient(plugins: [
        TestPlugin('short-circuit', handler: (ctx, next) async {
          await next();
          expect(ctx.native, isNotNull);
          if (cancelled) {
            token.cancel();
            await b3Turn();
          }
          final result = await next(
              cancelled ? null : const RequestPatch(sendTimeout: 'invalid'));
          expect(
              failureOf(result)!.kind,
              cancelled
                  ? DiomanFailureKind.cancel
                  : DiomanFailureKind.internal);
          expect(ctx.native, isNull);
          return ctx.fail(DiomanFailureKind.offline);
        })
      ]);
      final result = await api.send<Object?>(_method, _path,
          call: DiomanCall(cancelToken: token));
      expect(failureOf(result)!.kind,
          cancelled ? DiomanFailureKind.cancel : DiomanFailureKind.offline);
    });
  }

  for (final status in [200, 503]) {
    for (final error in [false, true]) {
      test(
          '[DiomanRetry.respectRetryAfter][DiomanResponseFactory.normalize] 多值头不把正常协议结果改为 internal status=$status error=$error',
          () async {
        final api = testClient();
        api.dio.interceptors.add(InterceptorsWrapper(onResponse: (r, h) {
          r.statusCode = status;
          r.headers.set('retry-after', ['1', '2']);
          if (error) {
            h.reject(DioException(
                requestOptions: r.requestOptions,
                response: r,
                type: DioExceptionType.badResponse));
          } else {
            h.next(r);
          }
        }));
        final result = await api.send<Object?>(_method, _path);
        expect(failureOf(result), isNull);
        expect(result.status, status);
        expect(result.ok, !error && status == 200);
      });
    }
  }
}
