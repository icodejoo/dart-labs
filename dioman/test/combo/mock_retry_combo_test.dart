// ignore_for_file: avoid_relative_lib_imports
// 组合层：mock_retry
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group('share end/race 窄组合（已知限制 #1 #2 #3）', () {
    test(
        '[DiomanMock.enabled × DiomanRetry.share] key → share → mock → retry：mock 短路的 500 不被 retry 恢复，leader 与 follower 一致',
        () async {
      final gate = Completer<void>();
      final mock = DiomanMock(enabled: true)
        ..add(tkGETM, (o) async {
          await gate.future;
          return jsonBody({tkE: 1}, 500);
        });
      final adapter = RecordingAdapter((o, n) async => jsonBody({tkV: n}, 200));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          mock: mock,
          retry: testRetry());

      /// call 的测试辅助入口。
      Future<Object> call() => dio
          .get<dynamic>(tkM)
          .then<Object>((r) => r, onError: (Object e) => e);
      final a = call();
      final b = call();
      await settleAsync();
      gate.complete(); // follower 已加入，mock 才返回 500
      final rs = await Future.wait([a, b]).timeout(timeout);

      // mock 短路的 500 以响应形式交付；两者必须都是原结果，而不是一个被重试成 200。
      for (final r in rs) {
        expect(r, isA<Response<dynamic>>(), reason: 'leader 与 follower 必须一致');
        expect((r as Response).statusCode, 500);
        expect(r.data, {tkE: 1});
      }
      expect(adapter.calls, 0, reason: 'mock 短路的结果不应被 retry 当作可恢复失败重放');
    });
  });
}
