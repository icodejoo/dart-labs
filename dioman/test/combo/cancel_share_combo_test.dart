// ignore_for_file: avoid_relative_lib_imports
// 组合层：cancel_share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group(tkCancelAll10, () {
    test(
        '[DiomanCancel.onError × DiomanShare.policy] share policy=retry 的内部重试等待期间可被取消',
        () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({}, 500));
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(
              policy: DiomanSharePolicy.retry,
              retries: 3,
              interval: const Duration(seconds: 30)),
          cancel: DiomanCancel());

      final result = dio
          .get<dynamic>(tkX)
          .then<Object>((_) => tkOk, onError: (Object e) => e);
      await settleAsync(80);
      expect(cancelAll(dio, tkBye), 1);
      final r = await result.timeout(const Duration(seconds: 2));
      expect(r, isA<DioException>());
      expect(adapter.calls, 1, reason: '取消后不再继续循环重试');
    });
  });

  group('取消类错误不等待胜出结果（取消悬挂）', () {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      for (final withAuth in [false, true]) {
        test(
            '[DiomanCancel.onError × DiomanShare.policy] policy=${policy.name}${withAuth ? ' + auth' : tkEmpty}：只取消落败者 A、'
            'B 永不完成，A 以 cancel 结束并释放登记', () async {
          final never = Completer<ResponseBody>();
          final adapter = RecordingAdapter((o, n) => never.future);
          final dio = fakeDio(adapter);
          final loading = DiomanLoading(onChanged: (_) {});
          Dioman.install(dio,
              key: const DiomanKey(),
              share: DiomanShare(policy: policy),
              cancel: DiomanCancel(),
              loading: loading,
              auth: withAuth ? testAuth(TestTokens(tkT0)) : null);

          final token = CancelToken();
          final a = dio
              .get<dynamic>(tkX, cancelToken: token)
              .then<Object>((_) => tkOk, onError: (Object e) => e);
          final b = dio.get<dynamic>(tkX); // 永不完成
          unawaited(b.then<void>((_) {}, onError: (Object _) {}));
          await settleAsync();
          token.cancel(tkBye);

          final ra = await a.timeout(timeout);
          expect(ra, isA<DioException>());
          expect((ra as DioException).type, DioExceptionType.cancel);
          expect(loading.activeCount, 1, reason: '只剩 B 在途');
          expect(cancelAll(dio), 1, reason: 'A 的登记已注销，只剩 B');
        });
      }
    }
  });

  group('share end/race 窄组合（已知限制 #1 #2 #3）', () {
    test(
        '[DiomanCancel.cancelAll × DiomanSharePolicy.race] race：A 重试耗尽后等 B，B 永不完成；cancelAll 仍能取消等待中的 A',
        () async {
      final gates = <Completer<void>>[];
      final adapter = RecordingAdapter((o, n) async {
        if (n == 1) {
          final g = Completer<void>();
          gates.add(g);
          await g.future;
        } else if (n == 2) {
          await Completer<void>().future; // B 永不完成
        }
        return jsonBody({tkE: n}, 500);
      });
      final dio = fakeDio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.race),
          cancel: DiomanCancel(),
          loading: loading,
          retry: testRetry());

      final a = dio
          .get<dynamic>(tkX)
          .then<Object>((r) => r, onError: (Object e) => e);
      final b = dio.get<dynamic>(tkX);
      unawaited(b.then<void>((_) {}, onError: (Object _) {}));
      await settleAsync();
      gates[0].complete(); // A 失败，重试（第 3 次调用）也失败 -> 等 B
      await settleAsync(100);

      expect(cancelAll(dio, tkBye), 2, reason: '等待中的 A 与在途的 B 都应可取消');
      final ra = await a.timeout(timeout);
      expect(ra, isA<DioException>());
      expect((ra as DioException).type, DioExceptionType.cancel);
      expect(cancelAll(dio), 0);
    });
  });

  group('pairwise: share + cancel', () {
// ROOT CAUSE (found while writing this test, applies beyond this pair):
// DiomanCancel.onRequest created its own CancelToken but never set
// `token.requestOptions`. dio's own `Options.compose` (options.dart:374)
// only wires `cancelToken.requestOptions = requestOptions` when a
// caller-supplied token is ALREADY attached before compose runs; a token
// an interceptor attaches later, during onRequest, never got that
// backfilled. So when `CancelToken.cancel()` fired, `cancel_token.dart:56`
// fell back to `requestOptions ?? RequestOptions()` — a BRAND NEW,
// empty RequestOptions. Every plugin downstream saw a DioException whose
// `requestOptions.extra` was `{}`, wiping out everything written during
// onRequest (DiomanShare's `_kEntry`, DiomanLoading's `_kBracketed`,
// DiomanRetry's retry counter, DiomanKey's key, ...) — which meant
// DiomanShare.onError could never find `_kEntry` to settle/remove the
// entry, permanently deadlocking that key for every future caller, not
// just concurrent ones. FIXED: cancel_plugin.dart now sets
// `token.requestOptions = options;` right after creating the token.
    test(
        '[DiomanCancel.onRequest × DiomanShare.policy] FIXED: cancelling a DiomanShare leader no longer deadlocks that '
        "key — a completely new, later caller for the same key correctly "
        'reaches the network instead of hanging on a dead entry', () async {
      var calls = 0;
      final firstStarted = Completer<void>();
      final server = await TestServer.start((req) async {
        calls++;
        if (calls == 1) {
          firstStarted.complete();
          await Completer<void>().future; // hangs until the connection dies
          return;
        }
        await respondJson(req, {tkV: tkLater}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      installStateful(dio,
          share: DiomanShare(policy: DiomanSharePolicy.start),
          cancel: DiomanCancel());

      final leader = dio.get<void>(tkData2);
      await firstStarted.future;
      cancelAll(dio, tkTest);
      await expectLater(
        leader.timeout(const Duration(seconds: 2)),
        throwsA(isA<DioException>()
            .having((e) => e.type, tkType, DioExceptionType.cancel)),
      );

      // A completely NEW, later request for the SAME key — nothing
      // concurrent with the cancelled one. It must hit the network fresh,
      // not hang on the cancelled leader's dead entry.
      final r = await dio
          .get<Map<String, dynamic>>(tkData2)
          .timeout(const Duration(seconds: 2));
      expect(r.data, {tkV: tkLater});
      expect(calls, 2,
          reason: "the leader's dead entry was correctly cleared from "
              "DiomanShare's `_active` map on cancellation, so this later "
              'caller started a fresh request instead of waiting on it');
    });
  });
}
