import 'dart:async';

import '../api.dart';
import '../model/fit.dart';
import '../model/source.dart';

/// Creates one fully-wired player for [MovaFeedPool] to own.
///
/// Hosts pass `createMova` here; tests pass a fake factory. The pool
/// calls this at most [MovaFeedPool.size] times over its whole lifetime
/// and disposes every player it created.
///
/// 为 [MovaFeedPool] 创建一个已完整装配的播放器。
///
/// 宿主传 `createMova`，测试传假工厂。整个生命周期内池最多调用它
/// [MovaFeedPool.size] 次，并负责释放自己创建的每个播放器。
///
/// Returns a fresh player, never a shared one.
///
/// 返回一个全新的播放器，绝不能是共享实例。
/// Feed 与 Cutover 共用同一工厂类型 [MovaFactory]。
/// 示例：`MovaFactory make = createMova`，每次调用返回全新播放器。
typedef MovaFactory = IMovaApi Function();

/// A pool player currently bound to one feed index, plus whether its media
/// has finished opening.
///
/// [ready] is `false` between [MovaFeedPool.bind] being called and its
/// `open()` resolving with acceptance — the window during which the UI should paint a
/// placeholder instead of the video surface. It is *not* a "first frame has
/// been rendered" signal: media_kit exposes no repeatable event for that
/// (`VideoController.waitUntilFirstFrameRendered` is a one-shot `Completer`
/// that never re-fires when a pooled player is reused for a later item).
/// Opening is not a screenshot-readiness guarantee either.
///
/// 池中一个当前绑定到某个 feed 索引的播放器，以及它的媒体是否已打开完毕。
///
/// 从调用 [MovaFeedPool.bind] 到其 `open()` 接受并 resolve 之间，[ready] 为
/// `false`——这段窗口内 UI 应绘制占位而非视频画面。它*不是*"首帧已渲染"信号：
/// media_kit 没有暴露可重复触发的首帧事件
/// （`VideoController.waitUntilFirstFrameRendered` 是一次性 `Completer`，
/// 池化播放器被复用于后续条目时不会再次触发）。open 接受也不保证截图可读；
/// 暂停画面需要确定截图结果时，可探测 IMovaFrameCapture 并等待其非空返回。
class MovaFeedSlot {
  /// Creates a slot snapshot.
  ///
  /// 创建一个 slot 快照。
  ///
  /// - [api]: the player bound to this feed index / 绑定到该 feed 索引的播放器
  /// - [ready]: whether its `open()` has resolved / 其 `open()` 是否已完成
  const MovaFeedSlot({required this.api, required this.ready});

  /// The player bound to this feed index.
  ///
  /// 绑定到该 feed 索引的播放器。
  final IMovaApi api;

  /// Whether this slot's media open was accepted and has resolved.
  ///
  /// 该 slot 的媒体打开是否已被接受并完成。
  final bool ready;
}

/// One player's current binding inside [MovaFeedPool]; mutable internal
/// bookkeeping behind the immutable [MovaFeedSlot] snapshots handed out.
///
/// [MovaFeedPool] 内部某个播放器的当前绑定；是对外发放的不可变
/// [MovaFeedSlot] 快照背后的可变簿记。
class _Binding {
  /// Creates a binding for [api] pointing at [source].
  ///
  /// 为 [api] 创建一个指向 [source] 的绑定。
  ///
  /// - [api]: the player holding this binding / 持有该绑定的播放器
  /// - [source]: 本绑定打开的完整媒体规格
  _Binding({required this.api, required this.source});

  /// The player holding this binding.
  ///
  /// 持有该绑定的播放器。
  final IMovaApi api;

  /// 已打开的完整规格，以 sameAs 判断是否可复用。
  final MovaSource source;

  /// 首次打开操作；重复绑定共享结果，不提前播放旧画面。
  late final Future<void> opening;

  /// Whether `open()` for this binding has resolved.
  ///
  /// 该绑定的 `open()` 是否已完成。
  bool ready = false;
}

/// A fixed-size pool of players that a vertical feed swaps between,
/// so each page owns its own decoder and render surface instead of every
/// page sharing one.
///
/// Why a pool rather than one shared, repeatedly-`open()`ed player — and the
/// two artifacts (black flash / stale frame) that decision used to cause —
/// is recorded in doc/SPEC.md's "预设 UI 套件：bilibili 点播 / 抖音风 feed"
/// section; do not revert to a single player without reading that first.
///
/// Never allocates more than [size] players. Recycling unbinds a player and
/// returns it to the idle list rather than disposing it — re-creating a
/// native surface per swipe would give back exactly the cost this design
/// exists to avoid.
///
/// Not a Flutter object: plain, testable core logic. The UI layer owns the
/// pool's lifetime and passes [onChanged] to rebuild.
///
/// 一个固定大小的播放器池，纵向 feed 在其中来回切换，使每一页拥有自己的
/// 解码器与渲染画面，而非所有页共用一个。
///
/// 为什么用池而非一个反复 `open()` 的共享播放器——以及那个决策曾导致的两个瑕疵
/// （黑屏一闪 / 残留旧帧）——记录在 doc/SPEC.md「预设 UI 套件：bilibili 点播 /
/// 抖音风 feed」一节；改回单播放器前务必先读那一节。
///
/// 播放器数永不超过 [size]。回收只是解绑并把播放器放回空闲列表，而非释放它——
/// 每次上滑都重建一次原生画面，等于把这套设计想省掉的开销又还回去。
///
/// 不是 Flutter 对象：纯粹、可测试的 core 逻辑。UI 层持有池的生命周期，并
/// 传入 [onChanged] 来触发重建。
class MovaFeedPool {
  /// Creates a player pool.
  ///
  /// 创建一个播放器池。
  ///
  /// - [movaFactory]: creates each player; called at most [size] times /
  ///   创建每个播放器，最多被调用 [size] 次
  /// - [size]: how many players may exist at once; clamped to at least 1.
  ///   3 is recommended — `PageView` mounts the current page plus one on
  ///   each side, so 3 covers every mounted page and both swipe directions.
  ///   2 still works (forward swipes stay seamless, swiping back falls to
  ///   the placeholder), and 1 degrades to the old single-player behaviour /
  ///   同时最多存在多少个播放器，下限钳到 1。推荐 3——`PageView` 会挂载当前页
  ///   及其前后各一页，3 个刚好覆盖所有已挂载页与两个滑动方向。2 也能用
  ///   （向前滑无缝，往回滑会落到占位），1 则退化为旧的单播放器行为
  /// - [fit]: applied once to every player as it is created / 每个播放器创建时
  ///   对其应用一次的填充模式
  /// - [onChanged]: fired whenever any slot's binding or [MovaFeedSlot.ready]
  ///   flag changes, so the UI can rebuild / 任一 slot 的绑定或
  ///   [MovaFeedSlot.ready] 标志变化时触发，供 UI 重建
  MovaFeedPool({
    required MovaFactory movaFactory,
    int size = 3,
    this.fit,
    this.onChanged,
  }) : _factory = movaFactory,
       size = size < 1 ? 1 : size;

  /// Creates each player.
  ///
  /// 创建每个播放器。
  final MovaFactory _factory;

  /// How many players may exist at once.
  ///
  /// 同时最多存在多少个播放器。
  final int size;

  /// Applied once to every player as it is created.
  ///
  /// 每个播放器创建时对其应用一次的填充模式。
  final MovaFit? fit;

  /// Fired whenever any slot's binding or ready flag changes.
  ///
  /// 任一 slot 的绑定或就绪标志变化时触发。
  final void Function()? onChanged;

  /// Players created but not currently bound to any feed index.
  ///
  /// Every player the pool has created is, at rest, in exactly one of [_idle]
  /// or [_bound] — a player is created only inside [_acquire] and bound in the
  /// same synchronous step, and [_release] only ever moves players between the
  /// two. So `_idle.length + _bound.length` is the live player count; no
  /// separate "all players" list is kept.
  ///
  /// 已创建但当前未绑定到任何 feed 索引的播放器。
  ///
  /// 本池创建过的每个播放器，静止时都恰好在 [_idle] 或 [_bound] 其一——播放器只在
  /// [_acquire] 内创建、并在同一次同步步骤里被绑定，[_release] 也只在两者间搬动。
  /// 因此 `_idle.length + _bound.length` 就是存活播放器数，不再单独维护一份"全部
  /// 播放器"列表。
  final List<IMovaApi> _idle = <IMovaApi>[];

  /// Current bindings, keyed by feed index.
  ///
  /// 当前绑定，按 feed 索引存放。
  final Map<int, _Binding> _bound = <int, _Binding>{};

  /// Whether [dispose] has run; every mutating method no-ops afterwards so a
  /// late-resolving `open()` can't resurrect a torn-down pool.
  ///
  /// [dispose] 是否已执行；此后所有会改动状态的方法都变为空操作，避免一个
  /// 迟到 resolve 的 `open()` 把已拆除的池又救活。
  bool _disposed = false;

  /// How many players currently exist; for tests and diagnostics.
  ///
  /// 当前存在多少个播放器；供测试与诊断使用。
  int get movaCount => _idle.length + _bound.length;

  /// The feed indices currently bound to a player.
  ///
  /// 当前已绑定播放器的 feed 索引集合。
  Iterable<int> get boundIndices => _bound.keys;

  /// Returns the slot bound to [index], or `null` if no player currently
  /// holds it.
  ///
  /// Synchronous, so the UI can decide between the video surface and the
  /// placeholder inside `build` without awaiting anything.
  ///
  /// 返回绑定到 [index] 的 slot；若当前没有播放器持有它则为 `null`。
  ///
  /// 同步方法，使 UI 能在 `build` 内无需等待即可在视频画面与占位之间抉择。
  ///
  /// - [index]: the feed index to look up / 要查询的 feed 索引
  MovaFeedSlot? slotFor(int index) {
    final binding = _bound[index];
    if (binding == null) return null;
    return MovaFeedSlot(api: binding.api, ready: binding.ready);
  }

  /// Binds a player to [index] and opens [source] on it.
  ///
  /// Reuses the existing binding when [index] already holds a sameAs source, so
  /// re-activating a page the viewer swiped back to costs nothing. Otherwise
  /// takes an idle player, creating a new one only while the pool is below
  /// [size], and evicting the binding farthest from [index] once it is full.
  ///
  /// 把一个播放器绑定到 [index] 并在其上打开 [source]。
  ///
  /// 若 [index] 已经绑定着 sameAs 相同的媒体规格 则直接复用，使观众往回滑到某页时不产生
  /// 任何开销。否则取一个空闲播放器；仅在池未满时才新建，池满时淘汰离 [index]
  /// 最远的那个绑定。
  ///
  /// - [index]: the feed index to bind / 要绑定的 feed 索引
  /// - [source]: the media to open on the bound player / 在被绑定播放器上打开的
  ///   媒体
  /// - [autoPlay]: whether the player starts playing; `false` parks it on its
  ///   first frame, which is what preloading a neighbour page wants /
  ///   播放器是否立即开始播放；`false` 会让它停在首帧，这正是预加载相邻页所需
  ///
  /// Returns a future completing once `open()` has resolved (or immediately
  /// when the binding was reused).
  ///
  /// 返回一个在 `open()` 完成后（或复用绑定时立即）完成的 Future。
  Future<void> bind(
    int index,
    MovaSource source, {
    bool autoPlay = false,
  }) async {
    if (_disposed) return;

    final existing = _bound[index];
    if (existing != null && existing.source.sameAs(source)) {
      await existing.opening;
      if (!_disposed &&
          identical(_bound[index], existing) &&
          existing.ready &&
          autoPlay) {
        await existing.api.play();
      }
      return;
    }

    // Rebinding an occupied index: recycle its player first, otherwise
    // `_bound[index] = ...` below would overwrite (leak) it.
    //
    // 重绑已占用的索引：先回收旧播放器，否则下面的 `_bound[index] = ...` 会把它覆盖（泄漏）。
    if (existing != null) _release(index);

    final api = _acquire(index);
    final binding = _Binding(api: api, source: source);
    _bound[index] = binding;
    binding.opening = _openBinding(index, binding, autoPlay: autoPlay);
    _notify();
    await binding.opening;
  }

  /// 打开 [binding]，仅当前绑定可认领接受结果；失败撤销绑定后保留错误给调用方。
  Future<void> _openBinding(
    int index,
    _Binding binding, {
    required bool autoPlay,
  }) async {
    bool accepted;
    try {
      accepted = await binding.api.open(binding.source, autoPlay: autoPlay);
    } on Object {
      if (!_disposed && identical(_bound[index], binding)) {
        _release(index);
        _notify();
      }
      rethrow;
    }

    // The binding may have been evicted or replaced while `open()` was in
    // flight (a fast swipe can retain a new window mid-open). Marking a
    // superseded binding ready would tell the UI to show a surface that is
    // no longer this index's.
    //
    // `open()` 进行期间该绑定可能已被淘汰或替换（快速上滑会在 open 中途
    // retain 一个新窗口）。把已被取代的绑定标记为就绪，等于告诉 UI 去显示
    // 一个已经不属于该索引的画面。
    if (_disposed || _bound[index] != binding) return;
    if (accepted) {
      binding.ready = true;
    } else {
      _release(index);
    }
    _notify();
  }

  /// Plays the player bound to [index] and pauses every other bound player,
  /// so exactly one item is ever audible.
  ///
  /// A no-op for [index] itself if nothing is bound to it.
  ///
  /// 播放绑定到 [index] 的播放器，并暂停其余所有已绑定播放器，使任何时刻只有
  /// 一条条目发得出声音。
  ///
  /// 若 [index] 上没有绑定，则针对它本身是空操作。
  ///
  /// - [index]: the feed index that should be the only one playing /
  ///   应当是唯一在播放的那个 feed 索引
  Future<void> focus(int index) async {
    if (_disposed) return;
    // Iterate a snapshot: this awaits between players, and a neighbour
    // warm-up left over from a previous activation can bind (mutating
    // `_bound`) inside that window — iterating the live map would throw
    // ConcurrentModificationError.
    //
    // 迭代快照：这里在各播放器之间 await，而上一次激活遗留的邻居预热可能在这个
    // 窗口内完成绑定（改动 `_bound`）——直接迭代活的 map 会抛
    // ConcurrentModificationError。
    // The bound players are independent native instances; fire their
    // play/pause concurrently and await the slowest rather than paying
    // (N-1) serial native round-trips on every swipe (this is the feed's
    // hottest path).
    //
    // 各绑定播放器是彼此独立的 native 实例；并发发起 play/pause、只等最慢的一个，
    // 而不是每次上滑都串行付出 (N-1) 次原生往返（这是 feed 最热的路径）。
    await Future.wait(
      _bound.entries.toList().map(
        (e) => e.key == index && e.value.ready
            ? e.value.api.play()
            : e.value.api.pause(),
      ),
    );
  }

  /// Unbinds every index outside [window], pausing those players and
  /// returning them to the idle list for reuse.
  ///
  /// Called before binding a new active page so a player is free to take.
  ///
  /// 解绑 [window] 之外的所有索引，暂停对应播放器并把它们放回空闲列表以供复用。
  ///
  /// 在绑定新的活跃页之前调用，好腾出一个可取用的播放器。
  ///
  /// - [window]: the feed indices worth keeping warm / 值得继续保持热态的
  ///   feed 索引
  void retain(Iterable<int> window) {
    if (_disposed) return;
    final keep = window.toSet();
    final drop = _bound.keys.where((i) => !keep.contains(i)).toList();
    if (drop.isEmpty) return;
    for (final index in drop) {
      _release(index);
    }
    _notify();
  }

  /// Disposes every player and clears all bookkeeping; the pool is unusable
  /// afterwards.
  ///
  /// 释放所有播放器并清空全部簿记；此后该池不可再用。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final movas = <IMovaApi>[..._idle, ..._bound.values.map((b) => b.api)];
    _bound.clear();
    _idle.clear();
    // Concurrent, best-effort teardown. Independent native resources, so
    // release them in parallel; the per-player catchError keeps one failure
    // from stranding the others (nothing else holds a reference to free them).
    //
    // 并发、尽力而为地拆除。彼此独立的原生资源，故并发释放；逐播放器的
    // catchError 保证某个失败不会把其它播放器晾在那（除此之外没有任何东西
    // 持有它们的引用可供释放）。
    await Future.wait(
      movas.map((mova) => mova.dispose().catchError((Object _) {})),
    );
  }

  /// Returns a player free to bind to [index]: an idle one, a newly created
  /// one while the pool is below [size], or the one held by the binding
  /// farthest from [index] once it is full.
  ///
  /// Distance-based eviction (not least-recently-used) because a feed's
  /// access pattern is spatial, not temporal: the page just swiped away from
  /// is the *most* recently used yet the likeliest to be needed again, and
  /// LRU would evict exactly the wrong one.
  ///
  /// 返回一个可绑定到 [index] 的空闲播放器：优先取空闲的；池未满时新建；池满
  /// 时淘汰离 [index] 最远的那个绑定并取用它的播放器。
  ///
  /// 按距离淘汰（而非 LRU），因为 feed 的访问模式是空间局部性而非时间局部性：
  /// 刚划走的那页是*最近*使用过的，却也是最可能马上又要用的，LRU 恰好会淘汰
  /// 错的那个。
  ///
  /// - [index]: the feed index the caller is about to bind / 调用方即将绑定的
  ///   feed 索引
  /// Reuses [movaCount] and computes each eviction distance once.
  /// 复用 [movaCount]，每个淘汰候选的距离只计算一次。
  IMovaApi _acquire(int index) {
    if (_idle.isNotEmpty) return _idle.removeLast();

    if (movaCount < size) {
      final mova = _factory();
      final f = fit;
      if (f != null) unawaited(mova.setFit(f));
      return mova;
    }

    // Farthest first; ties broken toward the page behind, since a feed's
    // next swipe is far more often forward than back.
    //
    // 先淘汰最远的；距离相同时优先淘汰后方那页，因为 feed 的下一次上滑绝大
    // 多数是往前而非往回。
    var victim = _bound.keys.first;
    var victimDistance = (victim - index).abs();
    for (final candidate in _bound.keys) {
      final distance = (candidate - index).abs();
      final better =
          distance > victimDistance ||
          (distance == victimDistance && candidate < victim);
      if (better) {
        victim = candidate;
        victimDistance = distance;
      }
    }
    _release(victim);
    return _idle.removeLast();
  }

  /// Unbinds [index], pauses its player and parks it in the idle list.
  ///
  /// Does not notify — callers batch a single [_notify] after releasing.
  ///
  /// 解绑 [index]，暂停其播放器并把它放进空闲列表。
  ///
  /// 不发出通知——调用方在释放完成后统一发一次 [_notify]。
  ///
  /// - [index]: the feed index to unbind / 要解绑的 feed 索引
  void _release(int index) {
    final binding = _bound.remove(index);
    if (binding == null) return;
    unawaited(binding.api.pause().catchError((Object _) {}));
    _idle.add(binding.api);
  }

  /// Fires [onChanged] if the pool is still alive.
  ///
  /// 若池仍存活则触发 [onChanged]。
  void _notify() {
    if (_disposed) return;
    onChanged?.call();
  }
}

/// Returns the feed indices worth keeping bound for a viewer sitting on
/// [center], for a pool holding [size] players.
///
/// Expands outward from [center], forward first (`[c, c+1, c-1, c+2, …]`),
/// because a feed is swiped forward far more often than back — with an odd
/// [size] the window ends up symmetric, with an even one the extra player
/// goes ahead. Negative indices are skipped, so near the top of the feed the
/// window is short and a spare player simply stays idle.
///
/// 返回观众停留在 [center] 时、容量为 [size] 的播放器池值得保持绑定的 feed
/// 索引。
///
/// 从 [center] 向外展开，向前优先（`[c, c+1, c-1, c+2, …]`），因为 feed 往前
/// 滑远多于往回滑——[size] 为奇数时窗口对称，为偶数时多出来的那个播放器放在
/// 前方。负索引会被跳过，因此在 feed 顶部窗口会短一些，多余的播放器就闲置。
///
/// - [center]: the active feed index / 当前活跃的 feed 索引
/// - [size]: how many players the pool holds / 播放器池容量
///
/// Returns the indices in warm-up priority order, [center] first.
///
/// 按预热优先级顺序返回索引，[center] 排在最前。
List<int> movaFeedWindow(int center, int size) {
  final window = <int>[center];
  var ahead = 1;
  var behind = 1;
  var forward = true;
  while (window.length < size) {
    if (forward) {
      window.add(center + ahead);
      ahead++;
    } else {
      final index = center - behind;
      behind++;
      // Skipped rather than clamped: index -1 isn't a feed page, and the
      // loop still terminates because the forward branch always adds one.
      //
      // 跳过而非钳位：-1 不是一个 feed 页；由于向前分支必定会加入一个，
      // 循环仍会终止。
      if (index >= 0) window.add(index);
    }
    forward = !forward;
  }
  return window;
}
