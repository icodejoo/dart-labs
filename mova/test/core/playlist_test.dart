import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/interceptor/interceptor.dart';
import 'package:mova/src/core/model/playlist.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/playlist/playlist.dart';

import '../support/fake_api.dart';
import '../support/fake_kernel.dart';

/// A three-item playlist used across the controller tests.
///
/// 控制器测试通用的三集播放列表。
const _items = [
  MovaPlaylistItem(source: MovaSource('https://host/e1.mp4'), title: 'E1'),
  MovaPlaylistItem(source: MovaSource('https://host/e2.mp4'), title: 'E2'),
  MovaPlaylistItem(source: MovaSource('https://host/e3.mp4'), title: 'E3'),
];

void main() {
  /// Builds a controller over a fake API seeded with [items]/[initialIndex]/
  /// [autoPlayNext].
  ///
  /// 用 [items]/[initialIndex]/[autoPlayNext] 初始化的假 API 构造控制器。
  (FakeMovaApi, MovaPlaylist) build({
    List<MovaPlaylistItem> items = _items,
    int initialIndex = 0,
    bool autoPlayNext = true,
  }) {
    final api = FakeMovaApi(
      options: MovaOpts(
        playlist: MovaPlaylistConfig(
          enabled: true,
          items: items,
          initialIndex: initialIndex,
          autoPlayNext: autoPlayNext,
        ),
      ),
    );
    return (api, MovaPlaylist(api));
  }

  test('C14 disposed playlist navigation never opens media', () async {
    final (api, playlist) = build(initialIndex: 1);
    addTearDown(api.dispose);
    await playlist.dispose();
    await playlist.jumpTo(0);
    await playlist.next();
    await playlist.previous();
    expect(api.calls, isEmpty);
    expect(playlist.currentIndex, 1);
  });

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

  test('jumpTo keeps the index when open() is rejected (beforeOpen hook)', () async {
    final (api, c) = build();
    final seen = <int>[];
    final sub = c.indexChanges.listen(seen.add);
    api.acceptOpens = false;
    await c.jumpTo(2);
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 0, reason: 'the previous item is still the one playing');
    expect(seen, isEmpty);
    api.acceptOpens = true;
    await c.jumpTo(2);
    expect(c.currentIndex, 2);
    await sub.cancel();
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

  test('MovaDone auto-advances when autoPlayNext is on', () async {
    final (api, c) = build();
    api.pushEvent(const MovaDone());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 1);
    expect(api.source?.uri, 'https://host/e2.mp4');
  });

  test('MovaDone does not advance when autoPlayNext is off', () async {
    final (api, c) = build(autoPlayNext: false);
    api.pushEvent(const MovaDone());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 0);
    expect(api.calls, isEmpty);
  });

  test('MovaDone at the last item does not wrap around', () async {
    final (api, c) = build(initialIndex: 2);
    api.pushEvent(const MovaDone());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 2);
    expect(api.calls, isEmpty);
  });

  test('dispose stops reacting to completion events', () async {
    final (api, c) = build();
    await c.dispose();
    api.pushEvent(const MovaDone());
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 0);
    expect(api.calls, isEmpty);
  });

  test(
      'dispose racing an in-flight jumpTo never commits its index, and never throws '
      '(regression: jumpTo used to unconditionally commit and add to indexChanges once '
      'its open() resolved, even after dispose had already closed that stream)', () async {
    final (_, c) = build();
    // `await _api.open(...)` inside jumpTo always yields at least one
    // microtask before resuming — even against the fake's already-completed
    // Future — so this call is guaranteed still in flight, not finished,
    // by the time dispose() runs on the next line.
    //
    // jumpTo 内部的 `await _api.open(...)` 总会在恢复前让出至少一个微任务
    // ——即便针对假实现里已经完成的 Future 也一样——因此本次调用在下一行
    // dispose() 运行时，保证仍处于在途状态，尚未完成。
    final inFlight = c.jumpTo(1);
    await c.dispose();
    await inFlight; // must never surface "Bad state: Cannot add event after closing"
    expect(c.currentIndex, 0, reason: 'a jumpTo that raced dispose must not commit its index');
  });

  test('interleaved jumpTo: the stale earlier jump finishing last never overwrites the index (#21)', () async {
    final api = _GatedApi(
      options: const MovaOpts(playlist: MovaPlaylistConfig(enabled: true, items: _items)),
    );
    final c = MovaPlaylist(api);
    final seen = <int>[];
    c.indexChanges.listen(seen.add);
    final j1 = c.jumpTo(1);
    final j2 = c.jumpTo(2);
    await Future<void>.delayed(Duration.zero);
    // 后发的 jumpTo(2) 先完成，先发的 jumpTo(1) 后完成。
    api.gates[1].complete(true);
    await j2;
    api.gates[0].complete(true);
    await j1;
    await Future<void>.delayed(Duration.zero);
    expect(c.currentIndex, 2);
    expect(seen, [2]);
  });

  for (final rejectFirst in [true, false]) {
    test('later rejected jump preserves earlier accepted index rejectFirst=$rejectFirst', () async {
      final api = _GatedApi(
        options: const MovaOpts(playlist: MovaPlaylistConfig(enabled: true, items: _items)),
      );
      final playlist = MovaPlaylist(api);
      addTearDown(api.dispose);
      addTearDown(playlist.dispose);
      final seen = <int>[];
      playlist.indexChanges.listen(seen.add);
      final first = playlist.jumpTo(1);
      final later = playlist.jumpTo(2);
      if (rejectFirst) {
        api.gates[1].complete(false);
        await later;
      }
      api.gates[0].complete(true);
      await first;
      if (!rejectFirst) {
        api.gates[1].complete(false);
        await later;
      }
      await pumpEventQueue();
      expect(playlist.currentIndex, 1);
      expect(api.source, _items[1].source);
      expect(seen, [1]);
      final next = playlist.next();
      api.gates[2].complete(true);
      await next;
      expect(playlist.currentIndex, 2);
    });
  }

  test('automatic next observes open failure and keeps index', () async {
    final api = _GatedApi(
      options: const MovaOpts(playlist: MovaPlaylistConfig(enabled: true, items: _items)),
    );
    final playlist = MovaPlaylist(api);
    addTearDown(api.dispose);
    addTearDown(playlist.dispose);
    final seen = <int>[];
    playlist.indexChanges.listen(seen.add);
    api.pushEvent(const MovaDone());
    await pumpEventQueue();
    expect(api.gates, hasLength(1));
    api.gates.single.completeError(StateError('open failed'));
    await pumpEventQueue();
    expect(playlist.currentIndex, 0);
    expect(seen, isEmpty);
    expect(api.gates, hasLength(1));

    // Explicit navigation still returns its failure to the awaiting caller.
    //
    // 显式导航仍将失败交给等待调用方。
    final explicit = playlist.next();
    final assertion = expectLater(explicit, throwsStateError);
    api.gates.last.completeError(StateError('explicit open failed'));
    await assertion;
    expect(playlist.currentIndex, 0);
  });

  test('beforeOpen rejection preserves the index of an in-flight engine load', () async {
    final kernel = FakeKernel();
    final engine = MovaEngine(
      kernel: kernel,
      ownsKernel: true,
      interceptors: [_RejectLastItem()],
      options: const MovaOpts(playlist: MovaPlaylistConfig(enabled: true, items: _items)),
    );
    final playlist = MovaPlaylist(engine);
    addTearDown(engine.dispose);
    addTearDown(playlist.dispose);
    final sources = <MovaSource>[];
    engine.events.where((e) => e is MovaSourceChange).cast<MovaSourceChange>().listen((e) => sources.add(e.source));
    await engine.open(_items.first.source);
    final gate = Completer<void>();
    kernel.openGate = gate;
    final first = playlist.jumpTo(1);
    await pumpEventQueue();
    expect(kernel.lastUri, _items[1].source.uri);
    try {
      await playlist.jumpTo(2);
      expect(kernel.openedUris, [_items[0].source.uri, _items[1].source.uri]);
    } finally {
      gate.complete();
      await first;
    }
    expect(sources.last, _items[1].source);
    expect(playlist.currentIndex, 1);
  });

  test('automatic next retains engine failure diagnostics without uncaught error', () async {
    final kernel = FakeKernel();
    final engine = MovaEngine(
      kernel: kernel,
      ownsKernel: true,
      options: const MovaOpts(playlist: MovaPlaylistConfig(enabled: true, items: _items)),
    );
    final playlist = MovaPlaylist(engine);
    addTearDown(engine.dispose);
    addTearDown(playlist.dispose);
    final errors = <MovaErrorEvent>[];
    engine.events.where((e) => e is MovaErrorEvent).cast<MovaErrorEvent>().listen(errors.add);
    await engine.open(_items.first.source);
    final failure = StateError('next item failed');
    kernel.openError = failure;
    kernel.emitCompleted(true);
    await pumpEventQueue();
    expect(kernel.openedUris, [_items[0].source.uri, _items[1].source.uri]);
    expect(playlist.currentIndex, 0);
    expect(engine.state.error, same(failure));
    expect(errors.single.error, same(failure));
    expect(errors.single.fatal, isTrue);
  });
}

/// Rejects only the last item, leaving earlier engine loads undisturbed.
///
/// 仅拒绝最后一集，不干扰引擎先前的加载。
class _RejectLastItem extends MovaHook {
  /// Accepts every source except the last playlist entry.
  ///
  /// 接受列表最后一项之外的源。
  @override
  Future<bool> beforeOpen(MovaSource source) async => source != _items.last.source;
}

/// A fake whose `open` stays pending until the matching gate completes.
///
/// 假 API：`open` 挂起，直到对应 gate 完成。
class _GatedApi extends FakeMovaApi {
  _GatedApi({super.options});

  /// One gate per `open` call, in call order.
  ///
  /// 每次 `open` 调用对应一个 gate，按调用顺序排列。
  final List<Completer<bool>> gates = <Completer<bool>>[];

  /// Resolves each load with its gated acceptance result or error.
  ///
  /// 根据阻塞点给出的接受结果或异常完成每次加载。
  @override
  Future<bool> open(MovaSource source, {bool autoPlay = true}) async {
    final gate = Completer<bool>();
    gates.add(gate);
    if (!await gate.future) return false;
    return super.open(source, autoPlay: autoPlay);
  }
}
