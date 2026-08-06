import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/feed_item.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/ui/feed_player.dart';

import '../support/fake_api.dart';

/// A [FakeMovaApi] whose [open] takes [openDelay] before resolving — used to
/// hold a feed page in its not-yet-ready state long enough to assert on the
/// placeholder.
///
/// 一个 [open] 会等待 [openDelay] 才 resolve 的 [FakeMovaApi]——用于把某页 feed
/// 停在"尚未就绪"状态足够久，以便对占位进行断言。
class _SlowOpenApi extends FakeMovaApi {
  /// How long [open] waits before resolving.
  ///
  /// [open] 在 resolve 前等待多久。
  Duration openDelay = Duration.zero;

  @override
  Future<void> open(MovaSource source, {bool autoPlay = true}) async {
    await Future<void>.delayed(openDelay);
    await super.open(source, autoPlay: autoPlay);
  }
}

/// Hands out fake engines to [MovaFeedPlayer] and keeps every one, so tests can
/// assert on how many the pool built and what it did with them.
///
/// 向 [MovaFeedPlayer] 发放假引擎并保留每一个，供测试断言池建了多少个引擎、
/// 对它们做了什么。
class _Fleet {
  /// Creates a fleet whose engines each delay [openDelay] before their
  /// `open()` resolves.
  ///
  /// 创建一个 fleet，其每个引擎的 `open()` 都会延迟 [openDelay] 才完成。
  ///
  /// - [openDelay]: per-engine open latency / 每个引擎的打开延迟
  _Fleet({this.openDelay = Duration.zero});

  /// Per-engine open latency.
  ///
  /// 每个引擎的打开延迟。
  final Duration openDelay;

  /// Every engine handed out, in creation order.
  ///
  /// 已发放的所有引擎，按创建顺序排列。
  final List<_SlowOpenApi> created = <_SlowOpenApi>[];

  /// Creates and records one engine; pass this as `engineFactory`.
  ///
  /// 创建并记录一个引擎；把它作为 `engineFactory` 传入。
  ///
  /// Returns the newly created fake engine.
  ///
  /// 返回新创建的假引擎。
  _SlowOpenApi make() {
    final api = _SlowOpenApi()..openDelay = openDelay;
    created.add(api);
    return api;
  }
}

void main() {
  testWidgets('defaults to cover fit so switching items never letterbox-jumps', (t) async {
    final fleet = _Fleet();
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(
        engineFactory: fleet.make,
        loader: (i) async => MovaFeedItem(source: MovaSource('https://h/$i.mp4')),
      ),
    ));
    await t.pumpAndSettle();

    expect(fleet.created, isNotEmpty);
    expect(fleet.created.every((a) => a.lastFit == MovaFit.cover), isTrue);
  });

  testWidgets('honors an explicit fit override', (t) async {
    final fleet = _Fleet();
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(
        engineFactory: fleet.make,
        loader: (i) async => MovaFeedItem(source: MovaSource('https://h/$i.mp4')),
        fit: MovaFit.contain,
      ),
    ));
    await t.pumpAndSettle();

    expect(fleet.created.first.lastFit, MovaFit.contain);
  });

  testWidgets('activates the first page on mount', (t) async {
    final fleet = _Fleet();
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(
        engineFactory: fleet.make,
        loader: (i) async =>
            MovaFeedItem(source: MovaSource('https://h/$i.mp4'), authorName: 'author$i'),
      ),
    ));
    await t.pumpAndSettle();

    expect(fleet.created.first.source?.uri, 'https://h/0.mp4');
    expect(fleet.created.first.lastAutoPlay, isTrue);
    expect(find.text('@author0'), findsOneWidget);
  });

  testWidgets('each page gets its own engine, the neighbour parked rather than '
      'playing — the whole point of the pool: swiping lands on a surface that '
      'is already live instead of a black flash or the previous page\'s stale '
      'last frame', (t) async {
    final fleet = _Fleet();
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(
        engineFactory: fleet.make,
        loader: (i) async => MovaFeedItem(source: MovaSource('https://h/$i.mp4')),
      ),
    ));
    await t.pumpAndSettle();

    final uris = fleet.created.map((a) => a.source?.uri).toSet();
    expect(uris, containsAll(<String>['https://h/0.mp4', 'https://h/1.mp4']));
    expect(fleet.created.length, greaterThan(1), reason: 'the neighbour must have its own engine');
    final neighbour = fleet.created.firstWhere((a) => a.source?.uri == 'https://h/1.mp4');
    expect(neighbour.lastAutoPlay, isFalse);
  });

  testWidgets('swiping up activates the next page on the engine already warmed '
      'for it', (t) async {
    final fleet = _Fleet();
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(
        engineFactory: fleet.make,
        loader: (i) async =>
            MovaFeedItem(source: MovaSource('https://h/$i.mp4'), authorName: 'author$i'),
      ),
    ));
    await t.pumpAndSettle();
    final warmed = fleet.created.firstWhere((a) => a.source?.uri == 'https://h/1.mp4');
    final openCountBefore = warmed.calls.where((c) => c == 'open').length;

    await t.fling(find.byType(PageView), const Offset(0, -400), 1000);
    await t.pumpAndSettle();

    expect(warmed.calls.where((c) => c == 'open').length, openCountBefore,
        reason: 'the page swiped onto was already open — reopening it would be the '
            'cold path this design exists to avoid');
    expect(warmed.calls.last, 'play');
    expect(find.text('@author1'), findsOneWidget);
  });

  testWidgets('a page whose engine has not finished opening shows the '
      'placeholder under its normal chrome, then swaps to the video surface', (t) async {
    final fleet = _Fleet(openDelay: const Duration(milliseconds: 300));
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(
        engineFactory: fleet.make,
        loader: (i) async =>
            MovaFeedItem(source: MovaSource('https://h/$i.mp4'), authorName: 'author$i'),
        placeholderBuilder: (context, item) =>
            const ColoredBox(key: Key('feedPlaceholder'), color: Color(0xFF123456)),
      ),
    ));
    // Long enough for the item to load, not for the engine to finish opening.
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('feedPlaceholder')), findsWidgets);
    expect(find.text('@author0'), findsOneWidget, reason: 'chrome renders over the placeholder');

    // Advance the clock explicitly rather than with `pumpAndSettle`: the
    // engines' open latency is a timer nothing schedules a frame for, so
    // `pumpAndSettle` would return without ever reaching it. Neighbours are
    // warmed one after another, hence enough headroom for several opens.
    //
    // 显式推进时钟而非用 `pumpAndSettle`：引擎的打开延迟是一个不会驱动任何
    // 帧调度的定时器，`pumpAndSettle` 会在还没走到它之前就返回。邻居是逐个
    // 预热的，因此要留出够几次 open 的余量。
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }

    expect(find.byKey(const Key('feedPlaceholder')), findsNothing);
  });

  testWidgets('an ended feed (loader returns null) shows a black placeholder '
      'without crashing or allocating an engine', (t) async {
    final fleet = _Fleet();
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(engineFactory: fleet.make, loader: (i) async => null),
    ));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(fleet.created, isEmpty);
  });

  testWidgets('disposes every pooled engine when the feed is torn down — the '
      'host never sees these engines, so nothing else can free them', (t) async {
    final fleet = _Fleet();
    await t.pumpWidget(MaterialApp(
      home: MovaFeedPlayer(
        engineFactory: fleet.make,
        loader: (i) async => MovaFeedItem(source: MovaSource('https://h/$i.mp4')),
      ),
    ));
    await t.pumpAndSettle();
    expect(fleet.created, isNotEmpty);

    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    await t.pumpAndSettle();

    expect(fleet.created.every((a) => a.calls.contains('dispose')), isTrue);
  });
}
