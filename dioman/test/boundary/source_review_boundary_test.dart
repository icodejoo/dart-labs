import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/b4_helpers.dart';
import '../support/fake_clock.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

/// 自审问题的独立回归。
void main() {
  test('[DiomanMock.mockUrl] 自审：path 内嵌 query 和独立 query 均保留', () async {
    final net = FakeNetwork();
    final api = testClient(
        network: net,
        plugins: [const DiomanMock<Result>(mockUrl: b4LiteralHttpsMockTest)]);
    await api.send<Object?>(b4Get, '$b4Path?inline=yes',
        query: {b4LiteralSeparate: b4LiteralAlso});
    expect(net.sends.single.options.uri.queryParameters,
        {'inline': 'yes', b4LiteralSeparate: b4LiteralAlso});
  });
  test(
      '[DiomanCachePolicy.persist]'
      '[DiomanCachePersist.read] 自审：显式缓存失败重读仍保留 kind status code reason',
      () async {
    for (final reply in [
      const FakeReply(status: 503, body: 'unavailable'),
      const FakeReply(
          body: {b4LiteralCode: 401, b4LiteralData: null, 'message': 'denied'})
    ]) {
      final store = B4Persist();
      final net = FakeNetwork()..routes[b4Route] = [reply];
      final api = testClient(network: net, plugins: [
        DiomanCache<Result>(
            persist: store,
            cachePolicy: DiomanCachePolicy.persist,
            shouldStore: (_) => true,
            clone: DiomanClonePolicy.none)
      ]);
      final first =
          await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      final second =
          await api.send<Object?>(b4Get, b4Path, call: b4Call(cache: true));
      expect([
        second.ok,
        second.kind,
        second.httpStatus,
        second.status,
        second.code,
        second.reason,
        second.message,
        second.data
      ], [
        first.ok,
        first.kind,
        first.httpStatus,
        first.status,
        first.code,
        first.reason,
        first.message,
        first.data
      ]);
      expect(net.sends.length, 1);
    }
  });
  test(
      '[Dioman.dispose × DiomanOfflineApi.pending] 自审：旧链晚到请求以 disposed 结束，不再排队',
      () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final gate = Completer<void>();
    final net = FakeNetwork();
    final api = testClient(network: net, plugins: [
      TestPlugin('gate', handler: (ctx, next) async {
        await ctx.wait(gate.future);
        return next();
      }),
      DiomanOffline<Result>(
          isOnline: () => false, onConnectivityChanged: stream.stream)
    ]);
    final offline = api.plugin<DiomanOfflineApi>()!;
    final pending = api.send<Object?>(b4Get, b4Path);
    await b4Turn();
    api.eject(DiomanOffline.pluginName);
    gate.complete();
    expect((await pending).reason, b4LiteralDisposed);
    expect(offline.pending, 0);
    expect(net.sends, isEmpty);
  });
  test(
      '[DiomanShare.interval][INV-source-diagnostics]'
      '[DiomanSharePolicy.retry] 内部等待时钟异常经工厂发布，所有跟随者按 bug 收尾', () async {
    final net = FakeNetwork()..routes[b4Route] = [const FakeReply(status: 500)];
    final api = testClient(
        network: net,
        clock: _ThrowClock(),
        plugins: [const DiomanShare<Result>(interval: b4Tick)]);
    final a = api.send<Object?>(b4Get, b4Path,
        call: b4Call(share: DiomanSharePolicy.retry));
    final b = api.send<Object?>(b4Get, b4Path,
        call: b4Call(share: DiomanSharePolicy.retry));
    await Future.wait(
        [expectLater(a, throwsStateError), expectLater(b, throwsStateError)]);
    expect(api.plugin<DiomanShareApi>()!.activeEntries, 0);
  });
}

/// 注入共享内部计时失败，验证脱离调用方的任务仍发布结果。
class _ThrowClock extends FakeClock {
  /// 内部重试计时抛错。
  @override
  Timer createTimer(Duration duration, void Function() callback) =>
      throw StateError('clock');
}
