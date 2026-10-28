// ignore_for_file: avoid_relative_lib_imports
// 边界层：retry
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的边界层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group(tk9, () {
    test(
        '[DiomanRetry.methods][DiomanRetryOptions.methods] FormData 请求体重试时被克隆，可重复发送',
        () async {
      final adapter = RecordingAdapter(
          (o, n) async => n == 1 ? jsonBody({}, 500) : jsonBody({tkV: n}, 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio, retry: testRetry(methods: [tkPOST]));

      final r = await dio
          .post<dynamic>(tkUp, data: FormData.fromMap({tkA2: tk1}))
          .timeout(timeout);
      expect(r.data, {tkV: 2});
      expect(adapter.calls, 2);
    });
    test(
        '[DiomanRetry.methods][DiomanRetryOptions.methods] Stream 请求体无法重放：retry 不自动重试，原错误照常抛出',
        () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 500));
      final dio = fakeDio(adapter);
      Dioman.install(dio, retry: testRetry(methods: [tkPOST]));

      await expectLater(
        dio
            .post<dynamic>(tkUp,
                data: Stream.fromIterable([
                  Uint8List.fromList([1, 2, 3])
                ]),
                options: Options(headers: {Headers.contentLengthHeader: 3}))
            .timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, tkStatus, 500)),
      );
      expect(adapter.calls, 1);
    });
  });

  group(tkRetry13, () {
    test(
        '[DiomanRetry.shouldRetry][DiomanRetryOptions.shouldRetry] 响应阶段 shouldRetry 抛异常：转成 DioException，handler 只完成一次',
        () async {
      final adapter =
          RecordingAdapter((o, n) async => jsonBody(successEnvelope(), 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          retry: testRetry(shouldRetry: (_, __) => throw StateError(tkBoom)));

      await expectLater(
        dio.get<dynamic>(tkX).timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.error, tkError, isA<StateError>())),
      );
    });
    test('[DiomanRetry.onRetry] onRetry 抛异常：转成 DioException', () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 500));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          retry: testRetry(onRetry: (_) => throw StateError(tkBoom)));

      await expectLater(
        dio.get<dynamic>(tkX).timeout(timeout),
        throwsA(isA<DioException>()
            .having((e) => e.error, tkError, isA<StateError>())),
      );
      expect(adapter.calls, 1);
    });
  });

  test('[DiomanRetry.delay][DiomanRetry.max] retry 响应阶段等待中取消会交付取消错误并注销认领',
      () async {
    final plugin = DiomanRetry(
        max: 1,
        shouldRetry: (_, __) => true,
        delay: (_, __, ___, ____) => replayTick);
    final token = CancelToken();
    final options = RequestOptions(path: replayPath, cancelToken: token);
    plugin.onRequest(options, RequestInterceptorHandler());
    final handler = ResponseInterceptorHandler();
    final check = expectLater(handlerCompletion(handler), throwsA(anything));
    plugin.onResponse(
        Response<dynamic>(requestOptions: options, statusCode: 200), handler);
    token.cancel(replayFailure);
    await check;
    expect(claimsOf(options)!.isFinished, isTrue);
    plugin.dispose();
  });
}
