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

void main() {
  group('VmFeedController', () {
    test('activate opens the item and caches it', () async {
      final api = FakeVmApi();
      final controller = VmFeedController(
        api: api,
        loader: (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4')),
      );

      await controller.activate(0);

      expect(api.calls, contains('open'));
      expect(api.source?.uri, 'https://h/0.mp4');
      expect(controller.activeIndex, 0);
      expect(controller.peek(0)?.source.uri, 'https://h/0.mp4');
    });

    test('activate does nothing when the loader signals the feed ended', () async {
      final api = FakeVmApi();
      final controller = VmFeedController(api: api, loader: (i) async => null);

      await controller.activate(0);

      expect(api.calls, isNot(contains('open')));
      expect(controller.activeIndex, isNull);
    });

    test('activate prefetches prefetchDepth items ahead, not behind', () async {
      final api = FakeVmApi();
      final prefetcher = _RecordingPrefetcher();
      final controller = VmFeedController(
        api: api,
        loader: (i) async => VmFeedItem(source: VmSource('https://h/$i.mp4')),
        prefetchDepth: 2,
        prefetcher: prefetcher,
      );

      await controller.activate(5);
      // Prefetch is fire-and-forget; pump the microtask queue.
      await Future<void>.delayed(Duration.zero);

      expect(prefetcher.primed, containsAll(['https://h/6.mp4', 'https://h/7.mp4']));
      expect(prefetcher.primed, isNot(contains('https://h/4.mp4')));
    });

    test('ensure retries after a failed load instead of caching the failure '
        'forever (regression: a stuck _pending entry blocked all retries)', () async {
      var attempt = 0;
      final controller = VmFeedController(
        api: FakeVmApi(),
        loader: (i) async {
          attempt++;
          if (attempt == 1) throw Exception('boom');
          return VmFeedItem(source: const VmSource('https://h/0.mp4'));
        },
      );

      await expectLater(controller.ensure(0), throwsException);
      final second = await controller.ensure(0);

      expect(attempt, 2);
      expect(second, isNotNull);
    });

    test('ensure caches so a second call for the same index does not reload', () async {
      var loadCount = 0;
      final controller = VmFeedController(
        api: FakeVmApi(),
        loader: (i) async {
          loadCount++;
          return VmFeedItem(source: VmSource('https://h/$i.mp4'));
        },
      );

      await controller.ensure(3);
      await controller.ensure(3);

      expect(loadCount, 1);
    });

    test('toggleLike flips liked/count and persists across peek', () async {
      final controller = VmFeedController(
        api: FakeVmApi(),
        loader: (i) async => VmFeedItem(
          source: const VmSource('https://h/0.mp4'),
          initialLiked: false,
          initialLikeCount: 10,
        ),
      );
      await controller.ensure(0);

      final first = controller.toggleLike(0);
      expect(first.liked, isTrue);
      expect(first.count, 11);
      expect(controller.peek(0)?.initialLiked, isTrue);
      expect(controller.peek(0)?.initialLikeCount, 11);

      final second = controller.toggleLike(0);
      expect(second.liked, isFalse);
      expect(second.count, 10);
    });

    test('toggleLike fires onLikeChanged with the new state', () async {
      bool? likedSeen;
      int? countSeen;
      final controller = VmFeedController(
        api: FakeVmApi(),
        loader: (i) async => VmFeedItem(
          source: const VmSource('https://h/0.mp4'),
          initialLikeCount: 4,
          onLikeChanged: (liked, count) {
            likedSeen = liked;
            countSeen = count;
          },
        ),
      );
      await controller.ensure(0);

      controller.toggleLike(0);

      expect(likedSeen, isTrue);
      expect(countSeen, 5);
    });

    test('toggleLike on an unresolved index is a no-op', () {
      final controller = VmFeedController(api: FakeVmApi(), loader: (i) async => null);
      final result = controller.toggleLike(99);
      expect(result.liked, isFalse);
      expect(result.count, 0);
    });
  });
}
