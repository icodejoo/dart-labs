// ignore_for_file: avoid_relative_lib_imports
// 规则层：offline
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/offline_plugin.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkDiomanOffline, () {
    test(
        '[DiomanOffline.new(isOnline)][DiomanOffline.new(onConnectivityChanged)] offline request is queued (no network), then replayed on reconnect',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
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
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      final f = dio.get<dynamic>(tkX); // offline → parks
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(offline.pending, 1);
      expect(hits, 0, reason: 'queued, never went to the network');

      online = true;
      conn.add(true); // reconnect → flush
      final r = await f;
      expect(r.statusCode, 200);
      expect(hits, 1, reason: 'replayed exactly once');
      expect(offline.pending, 0);
    });
    test(
        '[DiomanOffline.new(isOnline)][DiomanOffline.new(onConnectivityChanged)] online request passes straight through (not queued)',
        () async {
      var hits = 0;
      final server = await TestServer.start((req) async {
        hits++;
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      final conn = StreamController<bool>();
      addTearDown(conn.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final offline = DiomanOffline(
        isOnline: () => true,
        onConnectivityChanged: conn.stream,
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      final r = await dio.get<dynamic>(tkX);
      expect(r.statusCode, 200);
      expect(hits, 1);
      expect(offline.pending, 0);
    });
    test(
        '[DiomanOffline.new(shouldQueue)][DiomanOfflineOptions.shouldQueue] shouldQueue: only writes are queued, reads pass through',
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
        shouldQueue: (o) => o.method.toUpperCase() != tkGET,
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      // GET is not queued → reaches the (real, up) test server right away.
      final getR = await dio.get<dynamic>(tkG);
      expect(getR.statusCode, 200);
      expect(offline.pending, 0);

      // POST is queued while "offline".
      final pf = dio.post<dynamic>('/p', data: <String, dynamic>{});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(offline.pending, 1);

      online = true;
      conn.add(true);
      final pr = await pf;
      expect(pr.statusCode, 200);
    });
  });

  test(
      '[DiomanOffline.enabled][DiomanOffline.new(isOnline)] offline 单请求禁用绕过离线队列',
      () async {
    final plugin = DiomanOffline(
        isOnline: () => false,
        onConnectivityChanged: const Stream<bool>.empty());
    final options = RequestOptions(path: replayPath, extra: {
      DiomanOffline.pluginName: const DiomanOfflineOptions(enabled: false),
    });
    final handler = RequestInterceptorHandler();
    plugin.onRequest(options, handler);
    expect((await handlerCompletion(handler)).data, same(options));
    expect(plugin.pending, 0);
    plugin.dispose();
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
        '[DiomanOffline.maxWait][DiomanOfflineOptions.maxWait] maxWait rejects a queued request that waits too long',
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
        maxWait: const Duration(milliseconds: 100),
      );
      dio.interceptors.add(offline);
      addTearDown(offline.dispose);

      await expectLater(
        dio.get<dynamic>(tkX),
        throwsA(offlineError(DiomanOfflineReason.timeout)),
      );
      expect(offline.pending, 0, reason: 'timed-out entry was removed');
    });
  });
}
