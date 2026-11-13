import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

/// 无网络的预取器，可模拟宿主策略抛错。
class _Prefetcher implements IMovaFeedPrefetcher {
  /// 已发起的预取索引。
  final primed = <String>[];

  /// 记录请求；11 模拟网络故障。
  @override
  Future<void> prime(MovaSource source) async {
    primed.add(source.uri);
    if (source.uri == '11') throw StateError('prefetch');
  }
}

/// 创建索引为 [index] 的条目，[title] 用于区分同索引的新旧结果。
MovaFeedItem _item(int index, {String? title}) =>
    MovaFeedItem(source: MovaSource('$index', title: title));

/// 让后台预热的异步续体收尾。
Future<void> _drain() => Future<void>.delayed(Duration.zero);

/// B12 的滑窗、请求归属、辅助错误与网络过期回归。
void main() {
  test('连续浏览一万条后条目与请求数有界，回访窗口外条目重新加载', () async {
    final pool = MovaFeedPool(movaFactory: FakeMovaApi.new, size: 1);
    var firstLoads = 0;
    final feed = MovaFeed(
      pool: pool,
      prefetchDepth: 0,
      loader: (i) async {
        if (i == 0) firstLoads++;
        return _item(i);
      },
    );
    addTearDown(() async {
      feed.dispose();
      await pool.dispose();
    });
    for (var i = 0; i < 10000; i++) {
      await feed.activate(i);
      expect(feed.cachedItemCount, lessThanOrEqualTo(3));
      expect(feed.pendingItemCount, lessThanOrEqualTo(3));
      if (i == 0) feed.toggleLike(0);
    }
    expect(feed.peek(0), isNull);
    expect(feed.retains(0), isFalse);
    expect(pool.movaCount, 1);
    await feed.activate(0);
    expect(firstLoads, 2);
    expect(feed.likeStateOf(0).liked, isFalse);
  });
  test('窗口外迟到结果不回填，旧请求不移除同索引新请求，dispose 不复活缓存', () async {
    final old = Completer<MovaFeedItem?>();
    final fresh = Completer<MovaFeedItem?>();
    final disposed = Completer<MovaFeedItem?>();
    var zeroLoads = 0;
    final pool = MovaFeedPool(movaFactory: FakeMovaApi.new, size: 1);
    final feed = MovaFeed(
      pool: pool,
      prefetchDepth: 0,
      loader: (i) {
        if (i == 0) return ++zeroLoads == 1 ? old.future : fresh.future;
        if (i == 1) return disposed.future;
        return Future.value(_item(i));
      },
    );
    addTearDown(pool.dispose);
    final stale = feed.ensure(0);
    await feed.activate(100);
    final activation = feed.activate(0);
    final current = feed.ensure(0);
    old.complete(_item(0, title: 'old'));
    await stale;
    expect(feed.peek(0), isNull);
    expect(feed.pendingItemCount, 1);
    expect(identical(current, feed.ensure(0)), isTrue);
    fresh.complete(_item(0, title: 'new'));
    await activation;
    expect(feed.peek(0)?.source.title, 'new');
    final late = feed.ensure(1);
    feed.dispose();
    disposed.complete(_item(1));
    await late;
    expect(feed.cachedItemCount, 0);
    expect(feed.pendingItemCount, 0);
    expect(await feed.ensure(1), isNull);
  });
  test('邻居 loader 或 open 抛错只影响自己，其余邻居继续预热且失败页可重试', () async {
    for (final failLoader in [true, false]) {
      var failed = false;
      final pool = MovaFeedPool(
        movaFactory: () => FakeMovaApi()
          ..openThrows = failLoader ? null : StateError('warm open')
          ..openThrowsFor = '6'
          ..openThrowsOnce = true,
      );
      final feed = MovaFeed(
        pool: pool,
        prefetchDepth: 0,
        loader: (i) async {
          if (failLoader && i == 6 && !failed) {
            failed = true;
            throw StateError('warm loader');
          }
          return _item(i);
        },
      );
      await feed.activate(5);
      await _drain();
      expect(pool.slotFor(5)?.ready, isTrue);
      expect(pool.slotFor(6), isNull);
      expect(pool.slotFor(4)?.ready, isTrue);
      await feed.activate(6);
      expect(pool.slotFor(6)?.ready, isTrue);
      feed.dispose();
      await pool.dispose();
    }
  });
  test('预取 loader 返回后校验过期，宿主预取错误隔离后继续下一条', () async {
    final old = Completer<MovaFeedItem?>();
    final strategy = _Prefetcher();
    final pool = MovaFeedPool(movaFactory: FakeMovaApi.new, size: 1);
    final feed = MovaFeed(
      pool: pool,
      prefetchDepth: 3,
      prefetcher: strategy,
      loader: (i) => i == 1 ? old.future : Future.value(_item(i)),
    );
    addTearDown(() async {
      feed.dispose();
      await pool.dispose();
    });
    await feed.activate(0);
    await feed.activate(10);
    await _drain();
    old.complete(_item(1));
    await _drain();
    expect(strategy.primed, containsAll(['11', '12', '13']));
    expect(strategy.primed, isNot(contains('1')));
    expect(feed.peek(1), isNull);
  });
  test('原生预取在请求前、连接后和响应头后检查过期，不等待过期响应体', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    var current = true;
    server.listen((request) {
      requests++;
      current = false;
      request.response.contentLength = 10000;
      request.response.write('x');
      unawaited(request.response.flush().catchError((Object _) {}));
    });
    final source = MovaSource('http://127.0.0.1:${server.port}/video');
    const strategy = MovaNetworkWarmFeedPrefetcher();
    await strategy.primeWhileCurrent(source, () => false);
    expect(requests, 0);
    var checks = 0;
    await strategy.primeWhileCurrent(source, () => ++checks < 2);
    expect(checks, 2);
    expect(requests, 0);
    await strategy
        .primeWhileCurrent(source, () => current)
        .timeout(const Duration(seconds: 1));
    expect(requests, 1);
    expect(current, isFalse);
  });
}
