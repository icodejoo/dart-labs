// ignore_for_file: avoid_relative_lib_imports
// 组合层：normalize_share
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';

/// 注册本文件的组合层用例。
void main() {
  const timeout = Duration(seconds: 3);

  group('follower 拿到独立的 Response（#6）', () {
    test(
        '[DiomanNormalize.onResponse × DiomanShare.onRequest] Response 不同实例、绑定各自的 RequestOptions，嵌套信封只解一层',
        () async {
      final gate = Completer<void>();
      final nested = {tkCode: 0, tkData: successEnvelope(), tkMessage: tkEmpty};
      final adapter = RecordingAdapter((o, n) async {
        await gate.future;
        return jsonBody(nested, 200);
      });
      final dio = fakeDio(adapter);
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(),
          normalize: const DiomanNormalize());

      final a = dio.get<dynamic>(tkX, options: Options(extra: {tkWho: tkL}));
      final b = dio.get<dynamic>(tkX, options: Options(extra: {tkWho: tkF}));
      await settleAsync();
      gate.complete();
      final rs = await Future.wait([a, b]).timeout(timeout);

      expect(identical(rs[0], rs[1]), isFalse);
      expect(rs[0].requestOptions.extra[tkWho], tkL);
      expect(rs[1].requestOptions.extra[tkWho], tkF);
      expect(rs[0].data, successEnvelope());
      expect(rs[1].data, successEnvelope(), reason: '每人各解一层，不会被多次解包');
    });
  });

  group('恢复成功后的结果要经过后续处理（#8）', () {
    test(
        '[DiomanNormalize.onResponse × DiomanShare.policy] share policy=retry 内部重试成功：结果被 normalize 解包，loading 计数归零',
        () async {
      final adapter = RecordingAdapter((o, n) async =>
          n == 1 ? jsonBody({}, 500) : jsonBody(successEnvelope(), 200));
      final dio = fakeDio(adapter);
      final loading = DiomanLoading(onChanged: (_) {});
      Dioman.install(dio,
          key: const DiomanKey(),
          share: DiomanShare(policy: DiomanSharePolicy.retry, retries: 1),
          loading: loading,
          normalize: const DiomanNormalize());

      final r = await dio.get<dynamic>(tkX).timeout(timeout);
      expect(r.data, {tkV: 1});
      expect(loading.activeCount, 0);
    });
  });

  group('错误恢复成功后 follower 只处理一次（review2 #1）', () {
    final nested = {tkCode: 0, tkData: successEnvelope(), tkMessage: tkEmpty};

    /// 首发 500（卡在 gate 上，让 follower 先加入），之后返回嵌套信封。
    /// failThenNested 的测试辅助入口。
    RecordingAdapter failThenNested(Completer<void> gate,
            {int failStatus = 500}) =>
        RecordingAdapter((o, n) async {
          if (n == 1) {
            await gate.future;
            return jsonBody({}, failStatus);
          }
          return jsonBody(nested, 200);
        });
    for (final via in [tkRetry, tkAuth, tkShareRetry]) {
      test(
          '[DiomanNormalize.onResponse × DiomanShare.policy] share + $via + normalize：leader 恢复后 follower 只解一层信封',
          () async {
        final gate = Completer<void>();
        final adapter =
            failThenNested(gate, failStatus: via == tkAuth ? 401 : 500);
        final dio = fakeDio(adapter);
        Dioman.install(dio,
            key: const DiomanKey(),
            share: DiomanShare(
                policy: via == tkShareRetry
                    ? DiomanSharePolicy.retry
                    : DiomanSharePolicy.start,
                retries: 1),
            auth: via == tkAuth ? testAuth(TestTokens(tkT0)) : null,
            retry: via == tkRetry ? testRetry() : null,
            normalize: const DiomanNormalize());

        final a = dio.get<dynamic>(tkX);
        final b = dio.get<dynamic>(tkX);
        await settleAsync();
        gate.complete();
        final rs = await Future.wait([a, b]).timeout(timeout);

        expect(rs[0].data, successEnvelope());
        expect(rs[1].data, successEnvelope(), reason: 'follower 不能把已解包的结果再解一层');
        expect(adapter.calls, 2);
      });
    }
  });
}
