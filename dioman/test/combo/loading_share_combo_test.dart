// ignore_for_file: avoid_relative_lib_imports
// 组合层：loading_share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group(tkEndRace5, () {
    test(
        '[DiomanLoading.new(onChanged) × DiomanShare.policy] policy=end：落败者的 loading 括号也被释放（计数归零）',
        () async {
      final gates = <Completer<void>>[];
      final adapter = RecordingAdapter((o, n) async {
        final g = Completer<void>();
        gates.add(g);
        await g.future;
        return jsonBody({tkV: n}, 200);
      });
      final dio = fakeDio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.end),
          loading: loading);

      final a = dio.get<dynamic>(tkX);
      final b = dio.get<dynamic>(tkX);
      await settleAsync();
      gates[0].complete();
      await settleAsync();
      gates[1].complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(rs[0].data, rs[1].data);
      expect(loading.activeCount, 0);
    });
  });

  group('错误阶段落败者的收尾（review2 #2）', () {
    for (final policy in [DiomanSharePolicy.end, DiomanSharePolicy.race]) {
      test(
          '[DiomanLoading.new(onChanged) × DiomanShare.policy] policy=${policy.name}：A 失败、B 成功后 loading 归零、cancel 登记清空、'
          '认领注销', () async {
        final gates = <Completer<int>>[];
        final adapter = RecordingAdapter((o, n) async {
          final g = Completer<int>();
          gates.add(g);
          final status = await g.future;
          return jsonBody({tkV: n}, status);
        });
        final dio = fakeDio(adapter);
        final loading = DiomanLoading(onChanged: (_) {});
        Dioman.install(dio,
            key: const DiomanKey(),
            share: DiomanShare(policy: policy),
            cancel: DiomanCancel(),
            loading: loading);

        final a = dio.get<dynamic>(tkX);
        final b = dio.get<dynamic>(tkX);
        await settleAsync();
        gates[0].complete(500); // A 先失败，B 还在途
        await settleAsync();
        gates[1].complete(200);
        final rs = await Future.wait([a, b]).timeout(timeout);

        expect(rs[0].data, {tkV: 2});
        expect(rs[1].data, {tkV: 2});
        expect(loading.activeCount, 0);
        expect(cancelAll(dio), 0);
      });
    }
  });

  group('pairwise: share + loading', () {
    test(
        '[DiomanLoading.onRequest × DiomanShare.onRequest] a follower is invisible to the loading counter — only the leader '
        'is counted, because a follower never reaches '
        "DiomanLoading.onRequest (share's else-branch never calls "
        'handler.next)', () async {
      final release = Completer<void>();
      final server = await TestServer.start((req) async {
        await release.future;
        await respondJson(req, {tkV: 1}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(dio,
          share: DiomanShare(policy: DiomanSharePolicy.start),
          loading: DiomanLoading(onChanged: states.add));

      final a = dio.get<void>(tkData2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final b = dio.get<void>(tkData2); // follower — never bumps the counter
      await Future<void>.delayed(const Duration(milliseconds: 10));
      release.complete();
      await Future.wait([a, b]).timeout(const Duration(seconds: 3));

      expect(states, [true, false],
          reason: 'exactly one 0→1→0 edge — the follower never incremented '
              'the counter a second time');
    });
  });
}
