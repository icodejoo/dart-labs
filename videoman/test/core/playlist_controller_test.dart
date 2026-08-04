import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/events/events.dart';
import 'package:videoman/src/core/model/playlist.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/playlist/playlist_controller.dart';

import '../support/fake_api.dart';

/// A three-item playlist used across the controller tests.
///
/// 控制器测试通用的三集播放列表。
const _items = [
  VmPlaylistItem(source: VmSource('https://host/e1.mp4'), title: 'E1'),
  VmPlaylistItem(source: VmSource('https://host/e2.mp4'), title: 'E2'),
  VmPlaylistItem(source: VmSource('https://host/e3.mp4'), title: 'E3'),
];

void main() {
  /// Builds a controller over a fake API seeded with [items]/[initialIndex]/
  /// [autoPlayNext].
  ///
  /// 用 [items]/[initialIndex]/[autoPlayNext] 初始化的假 API 构造控制器。
  (FakeVmApi, VmPlaylistController) build({
    List<VmPlaylistItem> items = _items,
    int initialIndex = 0,
    bool autoPlayNext = true,
  }) {
    final api = FakeVmApi(
      options: VmOptions(
        playlist: VmPlaylistConfig(
          enabled: true,
          items: items,
          initialIndex: initialIndex,
          autoPlayNext: autoPlayNext,
        ),
      ),
    );
    return (api, VmPlaylistController(api));
  }

  test('seeds index from config and clamps out-of-range initialIndex', () {
    final (_, c1) = build(initialIndex: 1);
    expect(c1.currentIndex, 1);
    final (_, c2) = build(initialIndex: 99);
    expect(c2.currentIndex, _items.length - 1);
  });

  test('next opens the next source and advances the index', () async {
    final (api, c) = build();
    await c.next();
    expect(c.currentIndex, 1);
    expect(api.source?.uri, 'https://host/e2.mp4');
    expect(api.calls, contains('open'));
  });

  test('next at the end is a no-op', () async {
    final (api, c) = build(initialIndex: 2);
    await c.next();
    expect(c.currentIndex, 2);
    expect(api.calls, isEmpty);
  });

  test('previous goes back; no-op at the start', () async {
    final (api, c) = build(initialIndex: 1);
    await c.previous();
    expect(c.currentIndex, 0);
    api.calls.clear();
    await c.previous();
    expect(c.currentIndex, 0);
    expect(api.calls, isEmpty);
  });

  test('hasNext/hasPrevious and next/previous items reflect the boundaries', () {
    final (_, c) = build(initialIndex: 1);
    expect(c.hasPrevious, isTrue);
    expect(c.hasNext, isTrue);
    expect(c.previousItem?.title, 'E1');
    expect(c.nextItem?.title, 'E3');
  });

  test('jumpTo ignores out-of-range indices', () async {
    final (api, c) = build();
    await c.jumpTo(-1);
    await c.jumpTo(3);
    expect(c.currentIndex, 0);
    expect(api.calls, isEmpty);
  });

  test('indexChanges emits on navigation', () async {
    final (_, c) = build();
    final seen = <int>[];
    final sub = c.indexChanges.listen(seen.add);
    await c.next();
    await c.next();
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2]);
    await sub.cancel();
  });

  test('VmCompleted auto-advances when autoPlayNext is on', () async {
    final (api, c) = build();
    api.pushEvent(const VmCompleted());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 1);
    expect(api.source?.uri, 'https://host/e2.mp4');
  });

  test('VmCompleted does not advance when autoPlayNext is off', () async {
    final (api, c) = build(autoPlayNext: false);
    api.pushEvent(const VmCompleted());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 0);
    expect(api.calls, isEmpty);
  });

  test('VmCompleted at the last item does not wrap around', () async {
    final (api, c) = build(initialIndex: 2);
    api.pushEvent(const VmCompleted());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 2);
    expect(api.calls, isEmpty);
  });

  test('dispose stops reacting to completion events', () async {
    final (api, c) = build();
    await c.dispose();
    api.pushEvent(const VmCompleted());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 0);
    expect(api.calls, isEmpty);
  });
}
