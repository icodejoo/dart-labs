import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_api.dart';

/// Hands out [FakeMovaApi] instances as a [MovaEngineFact] would and keeps
/// every one it created, so tests can assert on how many engines a pool
/// allocated and what happened to each.
///
/// 像 [MovaEngineFact] 一样发放 [FakeMovaApi] 实例，并保留创建过的每一个，
/// 供测试断言池分配了多少引擎、每个引擎各自经历了什么。
class _Fleet {
  /// Every engine handed out, in creation order.
  ///
  /// 已发放的所有引擎，按创建顺序排列。
  final List<FakeMovaApi> created = <FakeMovaApi>[];

  /// Creates and records one engine; pass this as the pool's factory.
  ///
  /// 创建并记录一个引擎；把它作为池的工厂传入。
  ///
  /// Returns the newly created fake engine.
  ///
  /// 返回新创建的假引擎。
  FakeMovaApi make() {
    final api = FakeMovaApi();
    created.add(api);
    return api;
  }
}

void main() {
  group('movaFeedWindow', () {
    test('expands outward from the centre, forward first', () {
      expect(movaFeedWindow(5, 1), [5]);
      expect(movaFeedWindow(5, 2), [5, 6]);
      expect(movaFeedWindow(5, 3), [5, 6, 4]);
      expect(movaFeedWindow(5, 4), [5, 6, 4, 7]);
      expect(movaFeedWindow(5, 5), [5, 6, 4, 7, 3]);
    });

    test('skips negative indices near the top of the feed instead of clamping '
        '(clamping would bind index 0 twice and waste an engine)', () {
      expect(movaFeedWindow(0, 3), [0, 1, 2]);
      expect(movaFeedWindow(1, 4), [1, 2, 0, 3]);
    });
  });

  group('MovaFeedEnginePool', () {
    test('never allocates more engines than size, no matter how many indices '
        'are bound', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 2);

      for (var i = 0; i < 6; i++) {
        await pool.bind(i, MovaSource('https://h/$i.mp4'));
      }

      expect(fleet.created.length, 2);
      expect(pool.engineCount, 2);
      await pool.dispose();
    });

    test('applies fit once to each engine as it is created', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 2, fit: MovaFit.cover);

      await pool.bind(0, const MovaSource('https://h/0.mp4'));
      await pool.bind(1, const MovaSource('https://h/1.mp4'));

      expect(fleet.created.map((a) => a.lastFit), [MovaFit.cover, MovaFit.cover]);
      await pool.dispose();
    });

    test('bind opens the source and marks the slot ready only once open resolves', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 2);

      expect(pool.slotFor(0), isNull);
      final binding = pool.bind(0, const MovaSource('https://h/0.mp4'), autoPlay: true);
      expect(pool.slotFor(0)?.ready, isFalse,
          reason: 'the slot exists immediately so the UI can scope to it, but is not ready yet');
      await binding;

      expect(pool.slotFor(0)?.ready, isTrue);
      expect(fleet.created.single.source?.uri, 'https://h/0.mp4');
      expect(fleet.created.single.lastAutoPlay, isTrue);
      await pool.dispose();
    });

    test('rebinding the same index to the same uri reuses the binding instead '
        'of reopening (swiping back to a warm page must cost nothing)', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 3);

      await pool.bind(0, const MovaSource('https://h/0.mp4'));
      await pool.bind(0, const MovaSource('https://h/0.mp4'), autoPlay: true);

      final api = fleet.created.single;
      expect(api.calls.where((c) => c == 'open').length, 1);
      expect(api.calls, contains('play'));
      await pool.dispose();
    });

    test('retain unbinds indices outside the window, pausing their engines but '
        'never disposing them (re-creating a native surface per swipe is the '
        'cost this pool exists to avoid)', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 3);
      await pool.bind(0, const MovaSource('https://h/0.mp4'));
      await pool.bind(1, const MovaSource('https://h/1.mp4'));
      await pool.bind(2, const MovaSource('https://h/2.mp4'));

      pool.retain([1, 2]);

      expect(pool.slotFor(0), isNull);
      expect(pool.slotFor(1), isNotNull);
      expect(fleet.created[0].calls, contains('pause'));
      expect(fleet.created[0].calls, isNot(contains('dispose')));
      expect(pool.engineCount, 3);
      await pool.dispose();
    });

    test('a released engine is reused for the next bind rather than a new one '
        'being created', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 2);
      await pool.bind(0, const MovaSource('https://h/0.mp4'));
      final first = fleet.created.single;

      pool.retain(const <int>[]);
      await pool.bind(9, const MovaSource('https://h/9.mp4'));

      expect(fleet.created.length, 1);
      expect(pool.slotFor(9)?.api, same(first));
      await pool.dispose();
    });

    test('a full pool evicts the binding farthest from the index being bound, '
        'not the least recently used (the page just swiped away from is the '
        'most recently used yet the likeliest to be wanted again)', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 2);
      await pool.bind(0, const MovaSource('https://h/0.mp4'));
      await pool.bind(1, const MovaSource('https://h/1.mp4'));

      await pool.bind(2, const MovaSource('https://h/2.mp4'));

      expect(pool.slotFor(0), isNull, reason: 'index 0 is farthest from 2');
      expect(pool.slotFor(1), isNotNull, reason: 'the page just left must stay warm');
      expect(pool.slotFor(2), isNotNull);
      await pool.dispose();
    });

    test('focus plays exactly one bound engine and pauses every other, so only '
        'the watched page is ever audible', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 3);
      await pool.bind(0, const MovaSource('https://h/0.mp4'), autoPlay: true);
      await pool.bind(1, const MovaSource('https://h/1.mp4'));
      await pool.bind(2, const MovaSource('https://h/2.mp4'));

      await pool.focus(1);

      expect(pool.slotFor(1)!.api, same(fleet.created[1]));
      expect(fleet.created[1].calls.last, 'play');
      expect(fleet.created[0].calls.last, 'pause');
      expect(fleet.created[2].calls.last, 'pause');
      await pool.dispose();
    });

    test('onChanged fires when a slot binds and again when it becomes ready', () async {
      final fleet = _Fleet();
      var changes = 0;
      final pool = MovaFeedEnginePool(
        engineFactory: fleet.make,
        size: 2,
        onChanged: () => changes++,
      );

      await pool.bind(0, const MovaSource('https://h/0.mp4'));

      expect(changes, 2);
      await pool.dispose();
    });

    test('a binding superseded while its open() was in flight never flips to '
        'ready (it would tell the UI to show a surface that is no longer that '
        "index's)", () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 2);

      final slow = pool.bind(0, const MovaSource('https://h/0.mp4'));
      pool.retain(const <int>[]);
      await slow;

      expect(pool.slotFor(0), isNull);
      await pool.dispose();
    });

    test('dispose releases every engine and makes further binds no-ops', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 2);
      await pool.bind(0, const MovaSource('https://h/0.mp4'));
      await pool.bind(1, const MovaSource('https://h/1.mp4'));

      await pool.dispose();

      expect(fleet.created.every((a) => a.calls.contains('dispose')), isTrue);
      await pool.bind(2, const MovaSource('https://h/2.mp4'));
      expect(fleet.created.length, 2);
      expect(pool.slotFor(2), isNull);
    });

    test('size is clamped to at least 1 so a bogus 0 cannot deadlock binding', () async {
      final fleet = _Fleet();
      final pool = MovaFeedEnginePool(engineFactory: fleet.make, size: 0);

      await pool.bind(0, const MovaSource('https://h/0.mp4'));

      expect(pool.size, 1);
      expect(pool.slotFor(0), isNotNull);
      await pool.dispose();
    });
  });
}
