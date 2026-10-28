// ignore_for_file: avoid_relative_lib_imports
// 边界层：offline
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/offline_plugin.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的边界层用例。
void main() {
  group(tkDiomanOffline, () {
    /// Matcher for a DioException wrapping a DiomanOfflineException of [reason].
    /// offlineError 的测试辅助入口。
    Matcher offlineError(DiomanOfflineReason reason) =>
        isA<DioException>().having(
            (e) => e.error,
            tkError,
            isA<DiomanOfflineException>()
                .having((x) => x.reason, tkReason, reason));
    test(
        '[DiomanOffline.pending][DiomanOffline.new(isOnline)] dispose rejects every pending request (no perma-hang)',
        () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: conn.stream,
      );
      dio.interceptors.add(offline);

      final f = dio.get<dynamic>(tkX);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(offline.pending, 1);

      offline.dispose();
      await expectLater(f, throwsA(offlineError(DiomanOfflineReason.disposed)));
      expect(offline.pending, 0);
    });
  });

  test(
      '[DiomanOffline.flush][DiomanOffline.new(isOnline)] offline flush checks cancellation before cancellation listener runs',
      () {
    final offline = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: const Stream<bool>.empty());
    final token = CancelToken();
    final handler = RecordingRequestHandler();
    offline.onRequest(
        RequestOptions(path: fixturePath, cancelToken: token), handler);
    token.cancel();
    offline.flush();
    expect(handler.calls, 1);
    expect(handler.error?.type, DioExceptionType.cancel);
    offline.dispose();
  });

  test(
      '[DiomanOffline.maxWait][DiomanOffline.new(isOnline)] offline cancellation immediately removes queued request',
      () async {
    final offline = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: const Stream<bool>.empty(),
        maxWait: const Duration(hours: 1));
    final token = CancelToken();
    final handler = RecordingRequestHandler();
    offline.onRequest(
        RequestOptions(path: fixturePath, cancelToken: token), handler);
    expect(offline.pending, 1);
    token.cancel();
    await pumpEvents();
    expect(offline.pending, 0);
    expect(handler.error?.type, DioExceptionType.cancel);
    offline.flush();
    offline.dispose();
    expect(handler.calls, 1);
  });

  group(tkDiomanOffline, () {
    /// Matcher for a DioException wrapping a DiomanOfflineException of [reason].
    /// offlineError 的测试辅助入口。
    Matcher offlineError(DiomanOfflineReason reason) =>
        isA<DioException>().having(
            (e) => e.error,
            tkError,
            isA<DiomanOfflineException>()
                .having((x) => x.reason, tkReason, reason));
    test(
        '[DiomanOfflineReason.queueFull][DiomanOffline.maxQueueSize] queue full evicts the oldest with a queueFull rejection',
        () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      var online = false;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => online,
        onConnectivityChanged: conn.stream,
        maxQueueSize: 2,
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      final f1 = dio.get<dynamic>('/1');
      final f2 = dio.get<dynamic>('/2');
      final f3 = dio.get<dynamic>('/3');
      // f3 enqueuing evicts f1 (oldest).
      await expectLater(
          f1, throwsA(offlineError(DiomanOfflineReason.queueFull)));
      expect(offline.pending, 2);

      // Drain the survivors so no future is left dangling.
      online = true;
      conn.add(true);
      await Future.wait([f2, f3]);
      expect(offline.pending, 0);
    });
  });
}
