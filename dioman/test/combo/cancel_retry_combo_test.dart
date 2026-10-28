// ignore_for_file: avoid_relative_lib_imports
// 组合层：cancel_retry
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group(tkCancelAll10, () {
    test(
        '[DiomanCancel.cancelAll × DiomanRetry.cancel] retry 退避等待期间 cancelAll 能取消，且立刻结束等待',
        () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 500));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          cancel: DiomanCancel(),
          retry: DiomanRetry(
              max: 1,
              delay: (_, __, ___, ____) => const Duration(seconds: 30)));

      final call = dio.get<dynamic>(tkX);
      final result = call.then<Object>((_) => tkOk, onError: (Object e) => e);
      await settleAsync(80); // 第一次 500 已回来，retry 正在退避
      expect(adapter.calls, 1);
      expect(cancelAll(dio, tkBye), 1);

      final r = await result.timeout(const Duration(seconds: 2));
      expect(r, isA<DioException>());
      expect((r as DioException).type, DioExceptionType.cancel);
    });
  });

  group('DiomanCancel + DiomanRetry', () {
    test(
        "[DiomanCancel.cancelAll × DiomanRetry.cancel] a token this plugin injected stays trackable by cancelAll() while "
        "DiomanRetry's re-issue (a throwaway, interceptor-less Dio) is in "
        'flight — because DiomanRetry was given a `cancel` reference, not '
        "because the re-issue reaches this plugin's own onRequest (it "
        "never does)", () async {
      final secondAttemptStarted = Completer<void>();
      var attempt = 0;
      final server = await TestServer.start((req) async {
        attempt++;
        if (attempt == 1) {
          await respondJson(req, {}, 500);
          return;
        }
        secondAttemptStarted.complete();
        await Completer<void>().future; // hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final cancel = DiomanCancel();
      dio.interceptors.addAll([
        cancel,
        DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero)
          ..cancel = cancel,
      ]);

      final call = dio.get<void>(tkData2);
      await secondAttemptStarted.future;
      final cancelled = cancelAll(dio, 'test cancel');

      expect(cancelled, 1,
          reason: 'the retried attempt\'s token must still be registered');
      await expectLater(
        call.timeout(const Duration(seconds: 2)),
        throwsA(isA<DioException>().having(
          (e) => e.type,
          tkType,
          DioExceptionType.cancel,
        )),
      );
    });
  });
}
