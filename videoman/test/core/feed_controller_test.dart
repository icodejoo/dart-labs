import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/videoman.dart';

import '../support/fake_api.dart';

/// A [VmFeedPrefetcher] test double recording every primed source.
///
/// 记录每次被预热的源的 [VmFeedPrefetcher] 测试替身。
class _RecordingPrefetcher implements VmFeedPrefetcher {
  final List<String> primed = <String>[];

  @override
  Future<void> prime(VmSource source) async {
    primed.add(source.uri);
  }
}

/// Hands out [FakeVmApi] instances as a [VmEngineFactory] would, keeping each
/// one so tests can assert which engine ended up on which feed page.
///
/// 像 [VmEngineFactory] 一样发放 [FakeVmApi] 实例，并保留每一个，供测试断言
/// 哪个引擎落到了哪一页 feed 上。
class _Fleet {
  /// Every engine handed out, in creation order.
  ///
  /// 已发放的所有引擎，按创建顺序排列。
  final List<FakeVmApi> created = <FakeVmApi>[];

  /// Creates and records one engine; pass this as the pool's factory.
  ///
  /// 创建并记录一个引擎；把它作为池的工厂传入。
  ///
  /// Returns the newly created fake engine.
  ///
  /// 返回新创建的假引擎。
  FakeVmApi make() {
    final api = FakeVmApi();
    created.add(api);
    return api;
  }
}

void main() {
  group('VmFeedController', () {
    late _Fleet fleet;

    setUp(() => fleet = _Fleet());

    /// Builds a controller over a pool of [size] fake engines.
    ///
    /// 基于一个含 [size] 个假引擎的池构建控制器。
    ///
    /// - [loader]: item resolver under test / 被测的条目解析器
    /// - [size]: pool capacity / 池容量
    /// - [prefetchDepth]: network prefetch depth / 网络预取深度
    /// - [prefetcher]: network warm-up double / 网络预热替身
    ///
    /// Returns the controller and the pool backing it.
    ///
    /// 返回控制器及其背后的池。
    (VmFeedController, VmFeedEnginePool) build(
      VmFeedLoader loader, {
      int size = 3,
      int prefetchDepth = 1,
      VmFeedPrefetcher? prefetcher,
    }) {
      final pool = VmFeedEnginePool(engineFactory: fleet.make, size: size);
      final controller = VmFeedController(
        pool: pool,
        loader: loader,
        prefetchDepth: prefetchDepth,
        prefetcher: prefetcher,
      );
      return (controller, pool);
    }

    test('activate opens the item on its own engine, plays it, and caches it', () async {
      final (controller, pool) = build((i) async => VmFeedItem(source: VmSource('https://h/$i.mp4')));

      await controller.activate(0);

      final slot = pool.slotFor(0);
      expect(slot, isNotNull);
      expect(slot!.ready, isTrue);
      expect((slot.api as FakeVmApi).source?.uri, 'https://h/0.mp4');
      expect((slot.api as FakeVmApi).lastAutoPlay, isTrue);
      expect(controller.activeIndex, 0);
      expect(controller.peek(0)?.source.uri, 'https://h/0.mp4');
      await pool.dispose();
    });

    test('activate does nothing when the loader signals the feed ended', () async {
      final (controller, pool) = build((i) async => null);

      await controller.activate(0);

      expect(fleet.created, isEmpty);
      expect(controller.activeIndex, isNull);
      await pool.dispose();
    });

    test('neighbours in the window get their own engine, opened but parked — '
        'this is what makes a swipe land on a live surface instead of a black '
        'flash or the previous item\'s stale last frame', () async {
      final (controller, pool) = build(
        (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4')),
        size: 3,
      );

      await controller.activate(5);
      // Neighbour warm-up is fire-and-forget; drain the microtask queue.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(pool.boundIndices.toSet(), {4, 5, 6});
      final active = pool.slotFor(5)!.api as FakeVmApi;
      final ahead = pool.slotFor(6)!.api as FakeVmApi;
      final behind = pool.slotFor(4)!.api as FakeVmApi;
      expect(active, isNot(same(ahead)));
      expect(ahead, isNot(same(behind)));
      expect(active.lastAutoPlay, isTrue);
      expect(ahead.lastAutoPlay, isFalse, reason: 'a preloaded neighbour must park, not play');
      expect(behind.lastAutoPlay, isFalse);
      await pool.dispose();
    });

    test('only the active page is left playing — a neighbour warmed by an '
        'earlier activation must not keep its audio going underneath', () async {
      final (controller, pool) = build(
        (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4')),
        size: 3,
      );

      await controller.activate(0);
      await Future<void>.delayed(Duration.zero);
      await controller.activate(1);
      await Future<void>.delayed(Duration.zero);

      final playing = pool.slotFor(1)!.api as FakeVmApi;
      final neighbour = pool.slotFor(0)!.api as FakeVmApi;
      expect(playing.calls.last, 'play');
      expect(neighbour.calls.last, 'pause');
      await pool.dispose();
    });

    test('swiping back to a page still in the window reuses its warm engine '
        'instead of reopening it', () async {
      final (controller, pool) = build(
        (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4')),
        size: 3,
      );

      await controller.activate(0);
      await Future<void>.delayed(Duration.zero);
      final engineForZero = pool.slotFor(0)!.api as FakeVmApi;
      await controller.activate(1);
      await Future<void>.delayed(Duration.zero);
      await controller.activate(0);
      await Future<void>.delayed(Duration.zero);

      expect(pool.slotFor(0)!.api, same(engineForZero));
      expect(engineForZero.calls.where((c) => c == 'open').length, 1);
      await pool.dispose();
    });

    test('network prefetch skips indices the pool already opens and only warms '
        'the ones further out', () async {
      final prefetcher = _RecordingPrefetcher();
      final (controller, pool) = build(
        (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4')),
        size: 3,
        prefetchDepth: 2,
        prefetcher: prefetcher,
      );

      await controller.activate(5);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(prefetcher.primed, contains('https://h/7.mp4'));
      expect(prefetcher.primed, isNot(contains('https://h/6.mp4')),
          reason: 'index 6 is in the engine window — a duplicate ranged GET buys nothing');
      expect(prefetcher.primed, isNot(contains('https://h/4.mp4')));
      await pool.dispose();
    });

    test('overlapping activate calls never race the pool — both resolve once '
        'the latest requested index actually settles (regression: a lagging '
        'activate(N) could finish binding after a newer activate(N+1) already '
        'moved the chrome on, and could evict the engine the newer one just '
        'took)', () async {
      final completers = <int, Completer<VmFeedItem?>>{};
      final (controller, pool) = build((i) => (completers[i] = Completer<VmFeedItem?>()).future);

      // activate(0) starts resolving its item asynchronously (the loader
      // hasn't been completed yet); activate(1) lands before that resolves —
      // exactly the overlap window a fast second swipe produces in real use.
      // It only records index 1 as the newer target for the already-running
      // loop to pick up; `loader(1)` isn't called yet, so `completers[1]`
      // doesn't exist until the loop actually gets there.
      final first = controller.activate(0);
      final second = controller.activate(1);

      completers[0]!.complete(VmFeedItem(source: const VmSource('https://h/0.mp4')));
      // Let the loop resume from `ensure(0)`, see index 1 is now wanted, skip
      // binding item 0 entirely, and call `ensure(1)`.
      await Future<void>.delayed(Duration.zero);
      completers[1]!.complete(VmFeedItem(source: const VmSource('https://h/1.mp4')));

      await first;
      await second;

      expect(controller.activeIndex, 1);
      expect((pool.slotFor(1)!.api as FakeVmApi).source?.uri, 'https://h/1.mp4');
      // Index 0 was already stale by the time its `ensure` resolved, so it
      // never reached the pool as an *active* page. Exactly one engine has
      // been asked to play.
      expect(fleet.created.where((a) => a.lastAutoPlay == true).length, 1);
      await pool.dispose();
    });

    test('ensure retries after a failed load instead of caching the failure '
        'forever (regression: a stuck _pending entry blocked all retries)', () async {
      var attempt = 0;
      final (controller, pool) = build((i) async {
        attempt++;
        if (attempt == 1) throw Exception('boom');
        return VmFeedItem(source: const VmSource('https://h/0.mp4'));
      });

      await expectLater(controller.ensure(0), throwsException);
      final second = await controller.ensure(0);

      expect(attempt, 2);
      expect(second, isNotNull);
      await pool.dispose();
    });

    test('ensure caches so a second call for the same index does not reload', () async {
      var loadCount = 0;
      final (controller, pool) = build((i) async {
        loadCount++;
        return VmFeedItem(source: VmSource('https://h/$i.mp4'));
      });

      await controller.ensure(3);
      await controller.ensure(3);

      expect(loadCount, 1);
      await pool.dispose();
    });

    test('toggleLike flips liked/count and persists across peek', () async {
      final (controller, pool) = build((i) async => VmFeedItem(
            source: const VmSource('https://h/0.mp4'),
            initialLiked: false,
            initialLikeCount: 10,
          ));
      await controller.ensure(0);

      final first = controller.toggleLike(0);
      expect(first.liked, isTrue);
      expect(first.count, 11);
      expect(controller.peek(0)?.initialLiked, isTrue);
      expect(controller.peek(0)?.initialLikeCount, 11);

      final second = controller.toggleLike(0);
      expect(second.liked, isFalse);
      expect(second.count, 10);
      await pool.dispose();
    });

    test('toggleLike fires onLikeChanged with the new state', () async {
      bool? likedSeen;
      int? countSeen;
      final (controller, pool) = build((i) async => VmFeedItem(
            source: const VmSource('https://h/0.mp4'),
            initialLikeCount: 4,
            onLikeChanged: (liked, count) {
              likedSeen = liked;
              countSeen = count;
            },
          ));
      await controller.ensure(0);

      controller.toggleLike(0);

      expect(likedSeen, isTrue);
      expect(countSeen, 5);
      await pool.dispose();
    });

    test('toggleLike on an unresolved index is a no-op', () async {
      final (controller, pool) = build((i) async => null);
      final result = controller.toggleLike(99);
      expect(result.liked, isFalse);
      expect(result.count, 0);
      await pool.dispose();
    });
  });
}
