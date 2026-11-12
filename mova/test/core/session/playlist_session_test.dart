import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/session/registry.dart';

import '../../support/fake_api.dart';
import '../../support/gated.dart';
import '../cutover/cutover_operation_test.dart' show settleOperations;
import 'session_test.dart' show a, b, pre, done;

/// 第三集测试源。
const c = MovaSource('https://host/c.mp4');

/// 每集三十秒到期的非等待中插。
const mid = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/playlist-mid.mp4'),
  offset: Duration(seconds: 30),
  waitForReady: false,
);

/// 自动连播需要等待的后贴片。
const post = MovaAdBreak(
  kind: MovaAdBreakKind.post,
  source: MovaSource('https://host/playlist-post.mp4'),
);

/// 默认三集列表。
const episodes = [
  MovaPlaylistItem(source: a),
  MovaPlaylistItem(source: b),
  MovaPlaylistItem(source: c),
];

/// 创建共享会话的替身组合，统一登记借用关系的清理。
({FakeMovaApi api, MovaAds ads, MovaPlaylist playlist}) fixture({
  List<MovaAdBreak> breaks = const [],
  bool enabled = true,
  int initialIndex = 0,
}) {
  final api = FakeMovaApi(
    options: MovaOpts(
      ads: MovaAdConfig(enabled: true, breaks: breaks),
      playlist: MovaPlaylistConfig(
        enabled: enabled,
        items: episodes,
        initialIndex: initialIndex,
      ),
    ),
  );
  final ads = MovaAds(api);
  final playlist = MovaPlaylist(api, ads: ads);
  addTearDown(() async {
    await playlist.dispose();
    await ads.dispose();
    await api.dispose();
  });
  return (api: api, ads: ads, playlist: playlist);
}

/// 由进度触发三十秒中插并等待操作落定。
Future<void> reachMid(FakeMovaApi api) async {
  api.pushProgress(const MovaProg(position: Duration(seconds: 30)));
  await settleOperations();
}

void main() {
  for (final standalone in [false, true]) {
    test('结束通知不能覆盖节点监听器手动换集 standalone=$standalone', () async {
      final f = fixture();
      final session = standalone
          ? MovaSession(f.api, items: episodes, autoAdvance: true)
          : f.ads.session;
      if (standalone) addTearDown(session.dispose);
      await session.jumpTo(0);
      final gate = Completer<void>();
      f.api.openGate = gate;
      session.events.listen((event) {
        if (event is MovaNodeEnd &&
            event.node.kind == MovaNodeKind.content &&
            event.reason == MovaNodeEndReason.completed) {
          unawaited(session.jumpTo(2));
        }
      });
      f.api.pushEvent(const MovaDone());
      await settleOperations();
      gate.complete();
      await settleOperations();
      expect(f.api.openedUris, [a.uri, c.uri]);
      expect(session.cursor.item, 2);
    });
  }

  for (final naturalEnd in [false, true]) {
    test('公开会话换集同步列表并从会话导航 naturalEnd=$naturalEnd', () async {
      final f = fixture();
      final changes = <int>[];
      f.playlist.indexChanges.listen(changes.add);
      await f.playlist.jumpTo(0);
      await f.ads.session.jumpTo(2);
      await settleOperations();
      expect(f.playlist.currentIndex, 2);
      expect(f.playlist.currentItem, episodes[2]);
      expect(f.playlist.hasNext, isFalse);
      expect(f.playlist.previousItem, episodes[1]);
      if (naturalEnd) {
        await done(f.api);
      } else {
        await f.playlist.next();
      }
      expect(f.api.openedUris, [a.uri, c.uri]);
      expect(changes, [0, 2]);
      await f.playlist.previous();
      await settleOperations();
      expect(changes, [0, 2, 1]);
    });
  }

  test('替换列表使在途跳转失效且不提交越界下标', () async {
    final f = fixture();
    final gate = Completer<void>();
    f.api.openGate = gate;
    final events = <MovaSessionEvent>[];
    f.ads.session.events.listen(events.add);
    final loading = f.ads.session.jumpTo(2);
    await settleOperations();
    f.ads.session.setItems(const [MovaPlaylistItem(source: b)]);
    gate.complete();
    expect(await loading, MovaLoadOutcome.superseded);
    await settleOperations();
    expect(f.ads.session.cursor.item, 0);
    expect(events.whereType<MovaItemChange>(), isEmpty);
  });

  for (final entry in ['load', 'jumpTo', 'ads']) {
    test('跳过加载中的前贴片等待续播结算 $entry', () async {
      const skippable = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: c,
        skippableAfter: Duration.zero,
      );
      final f = fixture(breaks: [skippable]);
      final adGate = Completer<void>();
      final contentGate = Completer<void>();
      f.api.openGate = adGate;
      var settled = false;
      final Future<Object> loading = switch (entry) {
        'load' => f.ads.session.load(b),
        'jumpTo' => f.ads.session.jumpTo(1),
        _ => f.ads.load(b),
      };
      unawaited(
        loading.then((_) {
          settled = true;
        }),
      );
      await settleOperations();
      f.api.openGate = contentGate;
      f.ads.skip();
      await settleOperations();
      adGate.complete();
      await settleOperations();
      expect(settled, isFalse);
      contentGate.complete();
      expect(await loading, entry == 'ads' ? true : MovaLoadOutcome.accepted);
      expect(f.ads.session.cursor.phase, MovaSessionPhase.content);
      if (entry == 'jumpTo') expect(f.playlist.currentIndex, 1);
    });
  }

  test('三集自动连播，每集前贴片中插与 contentEnded 各一次', () async {
    final f = fixture(breaks: [pre, mid]);
    final starts = <MovaNodeId>[];
    var ended = 0;
    f.ads.session.events.listen((e) {
      if (e is MovaNodeStart && e.node.kind != MovaNodeKind.content) {
        starts.add(e.node);
      }
    });
    f.ads.contentEnded.listen((_) => ended++);
    await f.playlist.jumpTo(0);
    for (var i = 0; i < 3; i++) {
      expect(f.api.source, pre.source);
      await done(f.api);
      expect(f.api.source, episodes[i].source);
      await reachMid(f.api);
      expect(f.api.source, mid.source);
      await done(f.api);
      await done(f.api);
    }
    expect(starts, [
      for (var i = 0; i < 3; i++) ...[
        MovaNodeId(i, MovaNodeKind.pre, 0),
        MovaNodeId(i, MovaNodeKind.mid, 0),
      ],
    ]);
    expect(ended, 3);
    expect(f.playlist.currentIndex, 2);
    expect(f.ads.session.cursor.phase, MovaSessionPhase.idle);
  });

  test('每集重置广告簿记，同一中插第二集仍触发', () async {
    final f = fixture(breaks: [mid]);
    await f.playlist.jumpTo(0);
    await reachMid(f.api);
    await done(f.api);
    await f.playlist.next();
    await reachMid(f.api);
    expect(
      f.api.openedUris.where((uri) => uri == mid.source.uri),
      hasLength(2),
    );
    expect(f.ads.session.cursor.node, const MovaNodeId(1, MovaNodeKind.mid, 0));
  });

  test('后贴片播完才自动推进', () async {
    final f = fixture(breaks: [post]);
    await f.playlist.jumpTo(0);
    await done(f.api);
    expect(f.api.source, post.source);
    expect(f.playlist.currentIndex, 0);
    await done(f.api);
    expect(f.api.source, b);
    expect(f.playlist.currentIndex, 1);
  });

  test('中插提交 pending 时手动 next，旧提交不能播放广告', () async {
    const waiting = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/waiting.mp4'),
      offset: Duration(seconds: 30),
    );
    final factory = GatedEngineFactory();
    final api = MovaCutoverEngine(
      engineFactory: () {
        final engine = FakeMovaApi(
          commandLog: factory.log,
          options: const MovaOpts(
            ads: MovaAdConfig(enabled: true, breaks: [waiting]),
            playlist: MovaPlaylistConfig(enabled: true, items: episodes),
            cutover: MovaCutoverConfig(enabled: true, trigger: MovaEagerWarm()),
          ),
        );
        factory.engines.add(engine);
        return engine;
      },
    );
    final ads = MovaAds(api, cutover: api);
    final playlist = MovaPlaylist(api, ads: ads);
    final pause = Completer<void>();
    addTearDown(() async {
      if (!pause.isCompleted) pause.complete();
      await playlist.dispose();
      await ads.dispose();
      await api.dispose();
    });
    await playlist.jumpTo(0);
    final active = factory.engines.first..pauseGate = pause;
    await reachMid(active);
    expect(ads.isAdPending, isTrue);
    final shadow = factory.engines.last;
    expect(shadow, isNot(same(active)));
    const ready = MovaProg(
      position: Duration(seconds: 1),
      buffer: Duration(seconds: 10),
    );
    shadow.pushProgress(ready);
    await settleOperations();
    shadow.pushProgress(ready);
    await settleOperations();
    expect(active.calls.last, 'pause');
    await playlist.next();
    expect(playlist.currentIndex, 1);
    expect(api.active, same(active));
    pause.complete();
    await settleOperations();
    expect(active.source, b);
    expect(ads.isShowingAd, isFalse);
    expect(
      ads.session.cursor.node,
      const MovaNodeId(1, MovaNodeKind.content, 0),
    );
    expect(api.state.renderEpoch, 0);
    expect(shadow.calls.where((call) => call == 'dispose'), hasLength(1));
  });

  test('中插预热提交期间正片自然结束，不吞结束事件、自动连播下一集', () async {
    const waiting = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/waiting.mp4'),
      offset: Duration(seconds: 30),
    );
    final factory = GatedEngineFactory();
    final api = MovaCutoverEngine(
      engineFactory: () {
        final engine = FakeMovaApi(
          commandLog: factory.log,
          options: const MovaOpts(
            ads: MovaAdConfig(enabled: true, breaks: [waiting]),
            playlist: MovaPlaylistConfig(enabled: true, items: episodes),
            cutover: MovaCutoverConfig(enabled: true, trigger: MovaEagerWarm()),
          ),
        );
        factory.engines.add(engine);
        return engine;
      },
    );
    final ads = MovaAds(api, cutover: api);
    final playlist = MovaPlaylist(api, ads: ads);
    final pause = Completer<void>();
    addTearDown(() async {
      if (!pause.isCompleted) pause.complete();
      await playlist.dispose();
      await ads.dispose();
      await api.dispose();
    });
    await playlist.jumpTo(0);
    final active = factory.engines.first..pauseGate = pause;
    await reachMid(active);
    expect(ads.isAdPending, isTrue);
    final shadow = factory.engines.last;
    expect(shadow, isNot(same(active)));
    const ready = MovaProg(
      position: Duration(seconds: 1),
      buffer: Duration(seconds: 10),
    );
    shadow.pushProgress(ready);
    await settleOperations();
    shadow.pushProgress(ready);
    await settleOperations();
    expect(active.calls.last, 'pause');
    active.push(active.state.copyWith(duration: const Duration(seconds: 40)));
    // 换指副产物：位置还在 30s，不在片尾，MovaDone 必须继续被吞。
    await done(active);
    expect(playlist.currentIndex, 0);
    // 真正播到片尾后的 MovaDone 才是自然结束。
    active.pushProgress(const MovaProg(position: Duration(milliseconds: 39500)));
    await settleOperations();
    await done(active);
    expect(playlist.currentIndex, 1);
    pause.complete();
    await settleOperations();
    expect(active.source, b);
    expect(ads.isShowingAd, isFalse);
    expect(
      ads.session.cursor.node,
      const MovaNodeId(1, MovaNodeKind.content, 0),
    );
    expect(api.state.renderEpoch, 0);
  });

  test('open 被拒下标不动且不发 indexChanges', () async {
    final f = fixture();
    final changes = <int>[];
    f.playlist.indexChanges.listen(changes.add);
    f.api.acceptOpens = false;
    await f.playlist.jumpTo(1);
    await settleOperations();
    expect(f.playlist.currentIndex, 0);
    expect(changes, isEmpty);
  });

  test('jumpTo 被取代只有后者提交下标，销毁不销毁会话', () async {
    final f = fixture();
    final gate = Completer<void>();
    f.api.openGate = gate;
    final changes = <int>[];
    f.playlist.indexChanges.listen(changes.add);
    final old = f.playlist.jumpTo(1);
    await settleOperations();
    f.api.openGate = null;
    await f.playlist.jumpTo(2);
    gate.complete();
    await old;
    await settleOperations();
    expect(f.playlist.currentIndex, 2);
    expect(changes, [2]);
    expect(movaPlaylistSessions[f.playlist], same(f.ads.session));
    await f.playlist.dispose();
    expect(movaPlaylistSessions[f.playlist], isNull);
    expect(await f.ads.session.load(a), MovaLoadOutcome.accepted);
  });

  test('MovaAds.load 与 loadDeferred 接受为 true，拒绝失败销毁为 false', () async {
    final f = fixture();
    expect(await f.ads.load(a), isTrue);
    expect(await f.ads.loadDeferred(() async => b), isTrue);
    f.api.acceptOpens = false;
    expect(await f.ads.load(a), isFalse);
    expect(await f.ads.loadDeferred(() async => b), isFalse);
    f.api.acceptOpens = true;
    expect(
      await f.ads.loadDeferred(() async => throw StateError('resolve')),
      isFalse,
    );
    final gate = Completer<void>();
    f.api.openGate = gate;
    final old = f.ads.load(a);
    await settleOperations();
    f.api.openGate = null;
    expect(await f.ads.load(b), isTrue);
    gate.complete();
    expect(await old, isFalse);
    await f.ads.dispose();
    expect(await f.ads.load(a), isFalse);
  });

  test('ads.load 完成时机与 A22 原始调用链逐微任务一致', () async {
    final f = fixture();
    var turn = 0;
    void pulse() {
      f.api.calls.add('turn:${++turn}');
      if (turn < 12) scheduleMicrotask(pulse);
    }

    scheduleMicrotask(pulse);
    await f.ads.load(a);
    // 真实替换 A22 两个生产文件实跑所得，不靠多次排空微任务。
    expect(List<String>.of(f.api.calls), ['turn:1', 'open', 'turn:2']);
  });

  test('旧 MovaPlaylist(api) 响应 Done 且不看 enabled', () async {
    final api = FakeMovaApi(
      options: const MovaOpts(playlist: MovaPlaylistConfig(items: episodes)),
    );
    final playlist = MovaPlaylist(api);
    addTearDown(() async {
      await playlist.dispose();
      await api.dispose();
    });
    expect(movaPlaylistSessions[playlist], isNull);
    await playlist.jumpTo(0);
    await done(api);
    expect(playlist.currentIndex, 1);
    expect(api.source, b);
    await playlist.previous();
    expect(playlist.currentIndex, 0);
  });

  test('ads 路径不响应原始 Done，与后贴片没有双重推进', () async {
    final f = fixture(breaks: [post]);
    final changes = <int>[];
    f.playlist.indexChanges.listen(changes.add);
    await f.playlist.jumpTo(0);
    await done(f.api);
    expect(changes, [0]);
    expect(f.api.openedUris, [a.uri, post.source.uri]);
    await done(f.api);
    expect(changes, [0, 1]);
    expect(f.api.openedUris, [a.uri, post.source.uri, b.uri]);
  });

  test('enabled=false 的会话 next previous jumpTo 都是 no-op', () async {
    final f = fixture(enabled: false, initialIndex: 1);
    await f.playlist.next();
    await f.playlist.previous();
    await f.playlist.jumpTo(0);
    expect(f.api.calls, isEmpty);
    expect(f.playlist.currentIndex, 1);
    expect(f.ads.session.cursor.item, 1);
  });

  test('enabled=false 的会话 contentEnded 不自动下一集', () async {
    final f = fixture(enabled: false);
    await f.ads.session.jumpTo(0);
    await done(f.api);
    expect(f.api.openedUris, [a.uri]);
    expect(f.playlist.currentIndex, 0);
    expect(f.ads.session.cursor.phase, MovaSessionPhase.idle);
  });
}
