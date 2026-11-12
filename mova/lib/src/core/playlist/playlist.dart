import '../ad/ads.dart';
import '../session/session.dart';
import '../session/events.dart';
import '../session/registry.dart';
import 'dart:async';

import '../api.dart';
import '../events/events.dart';
import '../model/playlist.dart';

/// Drives sequential playlist playback on top of a [MovaApi]: tracks the current
/// index, navigates between items by calling [MovaApi.open], and (optionally)
/// auto-advances when an item plays to the end.
///
/// Pure Dart (no Flutter dependency) so it stays unit-testable and lives in the
/// core layer. Host-constructed and injected — the engine never owns one, and
/// the "next up" card reads this controller directly rather than through
/// [MovaApi]. Seed its items/index/auto-advance from [MovaOpts.playlist]; the
/// host still performs the very first [MovaApi.open] (or calls [jumpTo]).
///
/// 在 [MovaApi] 之上驱动顺序播放列表：跟踪当前下标、通过调用 [MovaApi.open] 在项间
/// 导航，并（可选）在一项播完时自动前进。
///
/// 纯 Dart（无 Flutter 依赖），因此可单测并归属核心层。由宿主构造并注入——engine
/// 从不持有它，"下一集"卡片直接读该控制器而非经 [MovaApi]。其项/下标/自动续播取自
/// [MovaOpts.playlist]；首次 [MovaApi.open]（或调用 [jumpTo]）仍由宿主执行。
///
/// 与广告组合时传入 `ads:` 共享会话，在正片及后贴片结束后自动连播。
/// 新代码推荐直接使用 MovaSession；本类作为薄适配器长期保留。
class MovaPlaylist {
  /// Creates a controller bound to [api], seeded from [MovaOpts.playlist].
  ///
  /// 创建绑定到 [api] 的控制器，初值取自 [MovaOpts.playlist]。
  ///
  /// - [ads]: 可选广告控制器，传入后换集走共享会话并遵守 enabled。
  /// - [api]: the player capability surface to drive / 要驱动的播放器能力面
  ///
  /// Example / 示例:
  /// ```dart
  /// final playlist = MovaPlaylist(api);
  /// await playlist.jumpTo(0); // open the first item
  /// ```
  /// [ads] 非空时共享其会话，换集带广告，全部后贴片结束后自动下一集。
  /// 返回新控制器；不销毁借用的会话。示例：`MovaPlaylist(api, ads: ads)`。
  MovaPlaylist(this._api, {MovaAds? ads})
    : _items = _api.options.playlist.items,
      _autoPlayNext = _api.options.playlist.autoPlayNext,
      _enabled = _api.options.playlist.enabled,
      _session = ads?.session {
    final start = _api.options.playlist.initialIndex;
    _index = _items.isEmpty ? 0 : start.clamp(0, _items.length - 1);
    final session = _session;
    if (session == null) {
      _sub = _api.events.listen(_onEvent);
    } else {
      movaPlaylistSessions[this] = session;
      session.setItems(_items, initialIndex: _index);
      _endSub = movaContentEndEpochs(session).listen((epoch) {
        if (epoch == session.cursor.epoch &&
            _enabled &&
            _autoPlayNext &&
            hasNext) {
          unawaited(next());
        }
      });
      _itemSub = session.events.listen((event) {
        if (event is MovaItemChange && !_disposed) {
          _indexChanges.add(event.index);
        }
      });
    }
  }

  /// 会话路径遵守的播放列表开关；旧直连路径保持原行为。
  final bool _enabled;

  /// 广告适配器借出的共享会话。
  final MovaSession? _session;

  /// 会话路径只订阅全部后贴片结束信号。
  StreamSubscription<int>? _endSub;
  StreamSubscription<MovaSessionEvent>? _itemSub;

  final MovaApi _api;
  final List<MovaPlaylistItem> _items;
  final bool _autoPlayNext;
  late int _index;
  StreamSubscription<MovaEvent>? _sub;
  final StreamController<int> _indexChanges = StreamController<int>.broadcast();

  /// Set once [dispose] has run; guards [jumpTo] against completing an
  /// in-flight `open()` after the index stream has already been closed.
  ///
  /// [dispose] 跑过后置位；防止 [jumpTo] 在下标流已关闭后，仍为一次在途的
  /// `open()` 收尾。
  bool _disposed = false;

  /// Monotonic counter of [jumpTo] calls; a jump that is no longer the latest
  /// when its `open()` returns is superseded and must not commit its index.
  ///
  /// [jumpTo] 的单调调用计数；`open()` 返回时若已不是最新一次，说明被取代，
  /// 不得提交其下标。
  int _jumpGen = 0;

  /// The items this controller navigates.
  ///
  /// 该控制器导航的项列表。
  List<MovaPlaylistItem> get items => _items;

  /// The index currently playing.
  ///
  /// 当前正在播放的下标。
  int get currentIndex => _session?.cursor.item ?? _index;

  /// The item currently playing, or null when the list is empty.
  ///
  /// 当前正在播放的项；列表为空时为 null。
  MovaPlaylistItem? get currentItem => _at(currentIndex);

  /// The item that [next] would open, or null when at the end.
  ///
  /// [next] 将打开的项；已在末尾时为 null。
  MovaPlaylistItem? get nextItem => _at(currentIndex + 1);

  /// The item that [previous] would open, or null when at the start.
  ///
  /// [previous] 将打开的项；已在开头时为 null。
  MovaPlaylistItem? get previousItem => _at(currentIndex - 1);

  /// Whether a next item exists.
  ///
  /// 是否存在下一项。
  bool get hasNext => currentIndex + 1 < _items.length;

  /// Whether a previous item exists.
  ///
  /// 是否存在上一项。
  bool get hasPrevious => currentIndex - 1 >= 0;

  /// Emits the new index whenever navigation changes the current item.
  ///
  /// 每当导航改变当前项时，发出新的下标。
  Stream<int> get indexChanges => _indexChanges.stream;

  /// Advances to the next item, if any.
  ///
  /// 前进到下一项（若有）。
  ///
  /// Returns once the open request has been issued (no-op at the end).
  ///
  /// 在打开请求发出后返回（已在末尾时为空操作）。
  Future<void> next() => _session != null
      ? _navigateSession(forward: true)
      : hasNext
      ? jumpTo(_index + 1)
      : Future<void>.value();

  /// Goes back to the previous item, if any.
  ///
  /// 回到上一项（若有）。
  ///
  /// Returns once the open request has been issued (no-op at the start).
  ///
  /// 在打开请求发出后返回（已在开头时为空操作）。
  Future<void> previous() => _session != null
      ? _navigateSession(forward: false)
      : hasPrevious
      ? jumpTo(_index - 1)
      : Future<void>.value();

  Future<void> _navigateSession({required bool forward}) async {
    if (_disposed || !_enabled) return;
    if (forward) {
      await _session!.next();
    } else {
      await _session!.previous();
    }
  }

  /// Jumps to [index] and opens its source; out-of-range indices are ignored.
  ///
  /// Opens first, then commits the index and notifies [indexChanges], so a
  /// failed [MovaApi.open] leaves the current index unchanged rather than
  /// advancing to an item that never started.
  ///
  /// 跳转到 [index] 并打开其源；越界下标被忽略。
  ///
  /// 先打开、再提交下标并通知 [indexChanges]，使 [MovaApi.open] 失败时当前下标
  /// 保持不变，而非前进到一个从未起播的项。
  ///
  /// - [index]: the target item index / 目标项下标
  Future<void> jumpTo(int index) async {
    if (_disposed) return;
    final session = _session;
    if (session != null) {
      if (_disposed || !_enabled || index < 0 || index >= _items.length) return;
      await session.jumpTo(index);
      return;
    }
    if (index < 0 || index >= _items.length) return;
    final gen = ++_jumpGen;
    final accepted = await _api.open(_items[index].source);
    // A later jumpTo superseded this one: its open() is what actually plays.
    // A rejected open() (beforeOpen hook, superseded, disposed) leaves the
    // previous item playing, so the index must not move.
    //
    // 更晚的 jumpTo 已取代本次：真正在播的是它的 open()。open() 被拒绝（beforeOpen
    // 钩子、被取代、已销毁）时上一项仍在播，下标不能前进。
    if (!accepted || gen != _jumpGen) return;
    // dispose() may have closed `_indexChanges` while the open() above was in
    // flight (e.g. an auto-advance racing the host tearing the controller
    // down) — adding to a closed StreamController throws.
    //
    // dispose() 可能在上面的 open() 在途期间已经关闭了 `_indexChanges`
    // （例如自动前进撞上宿主正在拆除本控制器）——向已关闭的 StreamController
    // 添加事件会抛异常。
    if (_disposed) return;
    _index = index;
    _indexChanges.add(index);
  }

  /// Reacts to end-of-item by auto-advancing when [autoPlayNext] is on.
  ///
  /// 在一项播完时，若开启 [autoPlayNext] 则自动前进。
  void _onEvent(MovaEvent e) {
    if (e is MovaDone && _autoPlayNext && hasNext) {
      unawaited(next());
    }
  }

  /// Returns the item at [i], or null when out of range.
  ///
  /// 返回下标 [i] 处的项；越界时为 null。
  MovaPlaylistItem? _at(int i) =>
      (i >= 0 && i < _items.length) ? _items[i] : null;

  /// Releases the event subscription and closes the index stream; call once
  /// when the host tears the controller down.
  ///
  /// 释放事件订阅并关闭下标流；宿主销毁控制器时调用一次。
  Future<void> dispose() async {
    _disposed = true;
    if (_session != null) {
      await _endSub?.cancel();
      await _itemSub?.cancel();
      movaPlaylistSessions[this] = null;
    }
    await _sub?.cancel();
    await _indexChanges.close();
  }
}
