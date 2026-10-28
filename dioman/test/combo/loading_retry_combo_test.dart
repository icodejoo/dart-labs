// ignore_for_file: avoid_relative_lib_imports
// 组合层：loading_retry
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('pairwise: loading + retry', () {
// FIXED as a side effect of DiomanRetry's bare-dio redesign (see
// retry_plugin.dart's class doc) — the retry re-issue never re-enters
// DiomanLoading.onRequest/onError at all anymore, so there's nothing
// left to cause the flicker this test used to demonstrate.
    test(
        "[DiomanLoading.delay × DiomanRetry.delay] the loading counter stays steady at 1 across a retry — the "
        "re-issue never touches DiomanLoading, so there's no 0→1 flicker "
        'mid-retry', () async {
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkFail: true}, 500);
        return respondJson(req, {tkV: tkOk}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(dio, loading: DiomanLoading(onChanged: states.add));
      dio.interceptors
          .add(DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero));

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data, {tkV: tkOk});
      expect(states, [true, false],
          reason: 'a single 0→1→0 edge for the whole logical request — the '
              'retry, on its own throwaway Dio, never bumps the counter '
              'again mid-flight');
    });
  });
}
