// ignore_for_file: avoid_relative_lib_imports
// 组合层：retry_share / arbitration
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group('end / race 的最终仲裁（review2 #3）', () {
    test(
        '[DiomanRetry.cancel × DiomanSharePolicy.race] race + retry：A 重试后仍失败而 B 尚未完成时，A 不抛错，等 B 的成功结果',
        () async {
      final gates = <Completer<void>>[];
      final adapter = RecordingAdapter((o, n) async {
        if (n <= 2) {
          final g = Completer<void>();
          gates.add(g);
          await g.future;
          return n == 1 ? jsonBody({tkE: n}, 500) : jsonBody({tkV: n}, 200);
        }
        return jsonBody({tkE: n}, 500); // A 的重试
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
      final b = dio
          .get<dynamic>(tkX)
          .then<Object>((r) => r, onError: (Object e) => e);
      await settleAsync();
      gates[0].complete(); // A 首发失败，重试也失败（第 3 次调用）
      await settleAsync();
      gates[1].complete(); // B 成功
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[0], isA<Response<dynamic>>(), reason: 'A 不应在 B 完成前抛错');
      expect((rs[0] as Response).data, {tkV: 2});
      expect((rs[1] as Response).data, {tkV: 2});
      expect(loading.activeCount, 0);
      expect(cancelAll(dio), 0);
    });
    test(
        '[DiomanRetry.cancel × DiomanSharePolicy.end] end + retry：A 恢复期间被 B 取代，A 返回 B 的结果而不是自己的恢复结果',
        () async {
      final adapter = RecordingAdapter((o, n) async {
        if (n == 1) return jsonBody({tkE: 1}, 500);
        return jsonBody({tkV: n}, 200);
      });
      final dio = fakeDio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.end),
          cancel: DiomanCancel(),
          loading: loading,
          retry: DiomanRetry(
              max: 1,
              delay: (_, __, ___, ____) => const Duration(milliseconds: 150)));

      final a = dio.get<dynamic>(tkX);
      await settleAsync(50); // A 首发已失败，正在退避
      final b = dio.get<dynamic>(tkX); // B 取代 A，直接成功（第 2 次调用）
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[1].data, {tkV: 2});
      expect(rs[0].data, {tkV: 2}, reason: 'A 已被取代，不应返回自己的恢复结果（第 3 次调用）');
      expect(loading.activeCount, 0);
      expect(cancelAll(dio), 0);
    });
  });

  group('share end/race 窄组合（已知限制 #1 #2 #3）', () {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      test(
          '[DiomanRetry.shouldRetry × DiomanShare.policy] policy=${policy.name}：A 的 shouldRetry 抛异常、B 随后成功，A 仍取 B 的结果',
          () async {
        final gates = <Completer<void>>[];
        final adapter = RecordingAdapter((o, n) async {
          final g = Completer<void>();
          gates.add(g);
          await g.future;
          return n == 1 ? jsonBody({tkE: n}, 500) : jsonBody({tkV: n}, 200);
        });
        final dio = fakeDio(adapter);
        final loading = DiomanLoading(onChanged: (_) {});
        Dioman.install(dio,
            key: const DiomanKey(),
            share: DiomanShare(policy: policy),
            cancel: DiomanCancel(),
            loading: loading, retry: testRetry(shouldRetry: (err, r) {
          if (err?.response?.statusCode == 500) throw StateError(tkBoom);
          return null;
        }));

        /// call 的测试辅助入口。
        Future<Object> call() => dio
            .get<dynamic>(tkX)
            .then<Object>((r) => r, onError: (Object e) => e);
        final a = call();
        final b = call();
        await settleAsync();
        // end 以后发的 B 为准；race 谁先成功谁赢。让 A（第 1 次）先失败。
        gates[0].complete();
        await settleAsync();
        gates[1].complete();
        final rs = await Future.wait([a, b]).timeout(timeout);

        for (final r in rs) {
          expect(r, isA<Response<dynamic>>(), reason: '不应把 A 的回调异常直接交给调用者');
          expect((r as Response).data, {tkV: 2});
        }
        expect(loading.activeCount, 0);
        expect(cancelAll(dio), 0);
      });
    }
    test(
        '[DiomanRetry.onRetry × DiomanSharePolicy.race] race：A 的 onRetry 抛异常、B 随后失败，A 收到 B 的失败而不是回调异常，且无未处理异步错误',
        () async {
      final gates = <Completer<void>>[];
      final adapter = RecordingAdapter((o, n) async {
        if (n <= 2) {
          final g = Completer<void>();
          gates.add(g);
          await g.future;
        }
        return jsonBody({tkE: n}, 500);
      });
      final dio = fakeDio(adapter);
      var thrown = false;
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.race),
          cancel: DiomanCancel(), retry: testRetry(onRetry: (_) {
        if (!thrown) {
          thrown = true;
          throw StateError(tkBoom); // 只有 A 的那次重试抛
        }
      }));

      /// call 的测试辅助入口。
      Future<Object> call() => dio
          .get<dynamic>(tkX)
          .then<Object>((r) => r, onError: (Object e) => e);
      final a = call();
      final b = call();
      await settleAsync();
      gates[0].complete(); // A 失败，进入重试，onRetry 抛异常
      await settleAsync();
      gates[1].complete(); // B 失败（最后一个在途）
      final rs = await Future.wait([a, b]).timeout(timeout);

      for (final r in rs) {
        expect(r, isA<DioException>());
        expect((r as DioException).error, isNot(isA<StateError>()),
            reason: 'A 应拿到胜出方 B 的失败');
        expect(r.response?.statusCode, 500);
      }
      expect(cancelAll(dio), 0);
    });
  });
}
