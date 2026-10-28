// ignore_for_file: avoid_relative_lib_imports
// 边界层：cancel
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group('DiomanCancel: re-entry with an already-injected token', () {
    test(
        '[DiomanCancel.cancelAll] re-dispatching the SAME RequestOptions object a second time — '
        'still carrying the CancelToken this plugin injected on the first, '
        'already-completed pass — re-registers that token for cancelAll',
        () async {
      var attempts = 0;
      final firstDone = Completer<void>();
      final secondStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) {
          await respondJson(req, {tkV: 1}, 200);
          firstDone.complete();
          return;
        }
        secondStarted.complete();
        await Completer<void>().future; // hangs until cancelled
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanCancel());

      final options =
          RequestOptions(path: tkData2, baseUrl: dio.options.baseUrl);
      await dio.fetch<void>(options);
      await firstDone.future;

      final second = dio.fetch<void>(options); // SAME RequestOptions object
      await secondStarted.future;
      final cancelled = cancelAll(dio, tkTest);
      expect(cancelled, greaterThanOrEqualTo(1),
          reason: 'the re-entering token was re-registered, so cancelAll '
              'can see and abort it');
      await expectLater(second, throwsA(isA<DioException>()));
    });
  });
}
