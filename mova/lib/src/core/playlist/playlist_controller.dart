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
/// **Composing with ads:** both this controller and a `MovaAdCtrl` react to
/// [MovaDone]; do not enable both against one player at once. Set
/// [MovaPlistConfig.autoPlayNext] to `false` and drive [next] from
/// `MovaAdCtrl.contentEnded` instead so ads and content-advance don't race.
///
/// **与广告组合：** 本控制器与 `MovaAdCtrl` 都响应 [MovaDone]；不要在同一
/// 播放器上同时启用二者的自动行为。应把 [MovaPlistConfig.autoPlayNext] 设为
/// `false`，改由 `MovaAdCtrl.contentEnded` 驱动 [next]，避免广告与换集争抢。
class MovaPlistCtrl {
  /// Creates a controller bound to [api], seeded from [MovaOpts.playlist].
  ///
  /// 创建绑定到 [api] 的控制器，初值取自 [MovaOpts.playlist]。
  ///
  /// - [api]: the player capability surface to drive / 要驱动的播放器能力面
  ///
  /// Example / 示例:
  /// ```dart
  /// final playlist = MovaPlistCtrl(api);
  /// await playlist.jumpTo(0); // open the first item
  /// ```
  MovaPlistCtrl(this._api)
      : _items = _api.options.playlist.items,
        _autoPlayNext = _api.options.playlist.autoPlayNext {
    final start = _api.options.playlist.initialIndex;
    _index = _items.isEmpty ? 0 : start.clamp(0, _items.length - 1);
    _sub = _api.events.listen(_onEvent);
  }

  final MovaApi _api;
  final List<MovaPlistItem> _items;
  final bool _autoPlayNext;
  late int _index;
  StreamSubscription<MovaEvent>? _sub;
  final StreamController<int> _indexChanges = StreamController<int>.broadcast();

  /// The items this controller navigates.
  ///
  /// 该控制器导航的项列表。
  List<MovaPlistItem> get items => _items;

  /// The index currently playing.
  ///
  /// 当前正在播放的下标。
  int get currentIndex => _index;

  /// The item currently playing, or null when the list is empty.
  ///
  /// 当前正在播放的项；列表为空时为 null。
  MovaPlistItem? get currentItem => _at(_index);

  /// The item that [next] would open, or null when at the end.
  ///
  /// [next] 将打开的项；已在末尾时为 null。
  MovaPlistItem? get nextItem => _at(_index + 1);

  /// The item that [previous] would open, or null when at the start.
  ///
  /// [previous] 将打开的项；已在开头时为 null。
  MovaPlistItem? get previousItem => _at(_index - 1);

  /// Whether a next item exists.
  ///
  /// 是否存在下一项。
  bool get hasNext => _index + 1 < _items.length;

  /// Whether a previous item exists.
  ///
  /// 是否存在上一项。
  bool get hasPrevious => _index - 1 >= 0;

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
  Future<void> next() => hasNext ? jumpTo(_index + 1) : Future<void>.value();

  /// Goes back to the previous item, if any.
  ///
  /// 回到上一项（若有）。
  ///
  /// Returns once the open request has been issued (no-op at the start).
  ///
  /// 在打开请求发出后返回（已在开头时为空操作）。
  Future<void> previous() =>
      hasPrevious ? jumpTo(_index - 1) : Future<void>.value();

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
    if (index < 0 || index >= _items.length) return;
    await _api.open(_items[index].source);
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
  MovaPlistItem? _at(int i) =>
      (i >= 0 && i < _items.length) ? _items[i] : null;

  /// Releases the event subscription and closes the index stream; call once
  /// when the host tears the controller down.
  ///
  /// 释放事件订阅并关闭下标流；宿主销毁控制器时调用一次。
  Future<void> dispose() async {
    await _sub?.cancel();
    await _indexChanges.close();
  }
}
