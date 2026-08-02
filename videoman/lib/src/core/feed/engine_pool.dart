import 'dart:async';

import '../api.dart';
import '../model/fit.dart';
import '../model/source.dart';

/// Creates one fully-wired playback engine for [VmFeedEnginePool] to own.
///
/// Hosts pass `createVmEngine` here; tests pass a fake factory. The pool
/// calls this at most [VmFeedEnginePool.size] times over its whole lifetime
/// and disposes every engine it created.
///
/// 为 [VmFeedEnginePool] 创建一个已完整装配的播放引擎。
///
/// 宿主传 `createVmEngine`，测试传假工厂。整个生命周期内池最多调用它
/// [VmFeedEnginePool.size] 次，并负责释放自己创建的每个引擎。
///
/// Returns a fresh engine, never a shared one.
///
/// 返回一个全新的引擎，绝不能是共享实例。
typedef VmEngineFactory = VmApi Function();

/// A pool engine currently bound to one feed index, plus whether its media
/// has finished opening.
///
/// [ready] is `false` between [VmFeedEnginePool.bind] being called and its
/// `open()` resolving — the window during which the UI should paint a
/// placeholder instead of the video surface. It is *not* a "first frame has
/// been rendered" signal: media_kit exposes no repeatable event for that
/// (`VideoController.waitUntilFirstFrameRendered` is a one-shot `Completer`
/// that never re-fires when a pooled engine is reused for a later item), but
/// a cold `open()` keeps the surface blank until the frame size is known
/// anyway, so `open()` resolving is a close enough proxy.
///
/// 池中一个当前绑定到某个 feed 索引的引擎，以及它的媒体是否已打开完毕。
///
/// 从调用 [VmFeedEnginePool.bind] 到其 `open()` resolve 之间，[ready] 为
/// `false`——这段窗口内 UI 应绘制占位而非视频画面。它*不是*"首帧已渲染"信号：
/// media_kit 没有暴露可重复触发的首帧事件
/// （`VideoController.waitUntilFirstFrameRendered` 是一次性 `Completer`，
/// 池化引擎被复用于后续条目时不会再次触发），但冷 `open()` 在帧尺寸确定前
/// 本就保持画面空白，因此用 `open()` resolve 作为近似判据足够。
class VmFeedSlot {
  /// Creates a slot snapshot.
  ///
  /// 创建一个 slot 快照。
  ///
  /// - [api]: the engine bound to this feed index / 绑定到该 feed 索引的引擎
  /// - [ready]: whether its `open()` has resolved / 其 `open()` 是否已完成
  const VmFeedSlot({required this.api, required this.ready});

  /// The engine bound to this feed index.
  ///
  /// 绑定到该 feed 索引的引擎。
  final VmApi api;

  /// Whether this slot's media has finished opening.
  ///
  /// 该 slot 的媒体是否已打开完毕。
  final bool ready;
}

/// One engine's current binding inside [VmFeedEnginePool]; mutable internal
/// bookkeeping behind the immutable [VmFeedSlot] snapshots handed out.
///
/// [VmFeedEnginePool] 内部某个引擎的当前绑定；是对外发放的不可变
/// [VmFeedSlot] 快照背后的可变簿记。
class _Binding {
  /// Creates a binding for [api] pointing at [uri].
  ///
  /// 为 [api] 创建一个指向 [uri] 的绑定。
  ///
  /// - [api]: the engine holding this binding / 持有该绑定的引擎
  /// - [uri]: the source uri this binding opened / 该绑定打开的源 uri
  _Binding({required this.api, required this.uri});

  /// The engine holding this binding.
  ///
  /// 持有该绑定的引擎。
  final VmApi api;

  /// The source uri this binding opened; compared by string because
  /// [VmSource] has no value equality.
  ///
  /// 该绑定打开的源 uri；按字符串比较，因为 [VmSource] 没有值相等。
  final String uri;

  /// Whether `open()` for this binding has resolved.
  ///
  /// 该绑定的 `open()` 是否已完成。
  bool ready = false;
}

/// A fixed-size pool of playback engines that a vertical feed swaps between,
/// so each page owns its own decoder and render surface instead of every
/// page sharing one.
///
/// This replaces the original single-engine feed architecture. With one
/// shared engine, switching pages had two unavoidable artifacts: a cold
/// `open()` blanked the surface (black flash), and any in-place fast path
/// left the *previous* item's last decoded frame on screen until the new
/// one's frames arrived (stale frame). Both were bridged with a timed black
/// mask, which is a guess, not a fix. With a pool, the page the viewer is
/// swiping toward has already been opened on its own engine and parked on
/// its own surface, so there is nothing to blank and nothing stale to show.
/// The cost is memory: N engines instead of one, measured on-device before
/// this was adopted (see doc/SPEC.md's feed entry).
///
/// Never allocates more than [size] engines. Recycling unbinds an engine and
/// returns it to the idle list rather than disposing it — re-creating a
/// native surface per swipe would give back exactly the cost this design
/// exists to avoid.
///
/// Not a Flutter object: plain, testable core logic. The UI layer owns the
/// pool's lifetime and passes [onChanged] to rebuild.
///
/// 一个固定大小的播放引擎池，纵向 feed 在其中来回切换，使每一页拥有自己的
/// 解码器与渲染画面，而非所有页共用一个。
///
/// 它取代了最初的单引擎 feed 架构。共用一个引擎时，切页有两个躲不掉的瑕疵：
/// 冷 `open()` 会清空画面（黑屏一闪），而任何原地快速路径都会把*上一条*
/// 最后解码的那帧留在屏幕上，直到新一条的帧到达（残留旧帧）。两者当时都靠
/// 一层定时黑遮罩桥接——那是猜测，不是修复。有了引擎池，观众正在滑向的那页
/// 早已在自己的引擎上打开、停在自己的画面上，因此既没有需要清空的东西，也
/// 没有会露出来的旧帧。代价是内存：N 个引擎而非一个，采纳前已在真机实测
/// （见 doc/SPEC.md 的 feed 条目）。
///
/// 引擎数永不超过 [size]。回收只是解绑并把引擎放回空闲列表，而非释放它——
/// 每次上滑都重建一次原生画面，等于把这套设计想省掉的开销又还回去。
///
/// 不是 Flutter 对象：纯粹、可测试的 core 逻辑。UI 层持有池的生命周期，并
/// 传入 [onChanged] 来触发重建。
class VmFeedEnginePool {
  /// Creates an engine pool.
  ///
  /// 创建一个引擎池。
  ///
  /// - [engineFactory]: creates each engine; called at most [size] times /
  ///   创建每个引擎，最多被调用 [size] 次
  /// - [size]: how many engines may exist at once; clamped to at least 1.
  ///   3 is recommended — `PageView` mounts the current page plus one on
  ///   each side, so 3 covers every mounted page and both swipe directions.
  ///   2 still works (forward swipes stay seamless, swiping back falls to
  ///   the placeholder), and 1 degrades to the old single-engine behaviour /
  ///   同时最多存在多少个引擎，下限钳到 1。推荐 3——`PageView` 会挂载当前页
  ///   及其前后各一页，3 个刚好覆盖所有已挂载页与两个滑动方向。2 也能用
  ///   （向前滑无缝，往回滑会落到占位），1 则退化为旧的单引擎行为
  /// - [fit]: applied once to every engine as it is created / 每个引擎创建时
  ///   对其应用一次的填充模式
  /// - [onChanged]: fired whenever any slot's binding or [VmFeedSlot.ready]
  ///   flag changes, so the UI can rebuild / 任一 slot 的绑定或
  ///   [VmFeedSlot.ready] 标志变化时触发，供 UI 重建
  VmFeedEnginePool({
    required VmEngineFactory engineFactory,
    int size = 3,
    this.fit,
    this.onChanged,
  })  : _factory = engineFactory,
        size = size < 1 ? 1 : size;

  /// Creates each engine.
  ///
  /// 创建每个引擎。
  final VmEngineFactory _factory;

  /// How many engines may exist at once.
  ///
  /// 同时最多存在多少个引擎。
  final int size;

  /// Applied once to every engine as it is created.
  ///
  /// 每个引擎创建时对其应用一次的填充模式。
  final VmFit? fit;

  /// Fired whenever any slot's binding or ready flag changes.
  ///
  /// 任一 slot 的绑定或就绪标志变化时触发。
  final void Function()? onChanged;

  /// Every engine ever created by this pool; length never exceeds [size].
  ///
  /// 本池创建过的所有引擎；长度永不超过 [size]。
  final List<VmApi> _engines = <VmApi>[];

  /// Engines created but not currently bound to any feed index.
  ///
  /// 已创建但当前未绑定到任何 feed 索引的引擎。
  final List<VmApi> _idle = <VmApi>[];

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

  /// How many engines currently exist; for tests and diagnostics.
  ///
  /// 当前存在多少个引擎；供测试与诊断使用。
  int get engineCount => _engines.length;

  /// The feed indices currently bound to an engine.
  ///
  /// 当前已绑定引擎的 feed 索引集合。
  Iterable<int> get boundIndices => _bound.keys;

  /// Returns the slot bound to [index], or `null` if no engine currently
  /// holds it.
  ///
  /// Synchronous, so the UI can decide between the video surface and the
  /// placeholder inside `build` without awaiting anything.
  ///
  /// 返回绑定到 [index] 的 slot；若当前没有引擎持有它则为 `null`。
  ///
  /// 同步方法，使 UI 能在 `build` 内无需等待即可在视频画面与占位之间抉择。
  ///
  /// - [index]: the feed index to look up / 要查询的 feed 索引
  VmFeedSlot? slotFor(int index) {
    final binding = _bound[index];
    if (binding == null) return null;
    return VmFeedSlot(api: binding.api, ready: binding.ready);
  }

  /// Binds an engine to [index] and opens [source] on it.
  ///
  /// Reuses the existing binding when [index] already holds the same uri, so
  /// re-activating a page the viewer swiped back to costs nothing. Otherwise
  /// takes an idle engine, creating a new one only while the pool is below
  /// [size], and evicting the binding farthest from [index] once it is full.
  ///
  /// 把一个引擎绑定到 [index] 并在其上打开 [source]。
  ///
  /// 若 [index] 已经绑定着同一个 uri 则直接复用，使观众往回滑到某页时不产生
  /// 任何开销。否则取一个空闲引擎；仅在池未满时才新建，池满时淘汰离 [index]
  /// 最远的那个绑定。
  ///
  /// - [index]: the feed index to bind / 要绑定的 feed 索引
  /// - [source]: the media to open on the bound engine / 在被绑定引擎上打开的
  ///   媒体
  /// - [autoPlay]: whether the engine starts playing; `false` parks it on its
  ///   first frame, which is what preloading a neighbour page wants /
  ///   引擎是否立即开始播放；`false` 会让它停在首帧，这正是预加载相邻页所需
  ///
  /// Returns a future completing once `open()` has resolved (or immediately
  /// when the binding was reused).
  ///
  /// 返回一个在 `open()` 完成后（或复用绑定时立即）完成的 Future。
  Future<void> bind(int index, VmSource source, {bool autoPlay = false}) async {
    if (_disposed) return;

    final existing = _bound[index];
    if (existing != null && existing.uri == source.uri) {
      if (autoPlay) await existing.api.play();
      return;
    }

    final api = _acquire(index);
    final binding = _Binding(api: api, uri: source.uri);
    _bound[index] = binding;
    _notify();

    await api.open(source, autoPlay: autoPlay);

    // The binding may have been evicted or replaced while `open()` was in
    // flight (a fast swipe can retain a new window mid-open). Marking a
    // superseded binding ready would tell the UI to show a surface that is
    // no longer this index's.
    //
    // `open()` 进行期间该绑定可能已被淘汰或替换（快速上滑会在 open 中途
    // retain 一个新窗口）。把已被取代的绑定标记为就绪，等于告诉 UI 去显示
    // 一个已经不属于该索引的画面。
    if (_disposed || _bound[index] != binding) return;
    binding.ready = true;
    _notify();
  }

  /// Plays the engine bound to [index] and pauses every other bound engine,
  /// so exactly one item is ever audible.
  ///
  /// A no-op for [index] itself if nothing is bound to it.
  ///
  /// 播放绑定到 [index] 的引擎，并暂停其余所有已绑定引擎，使任何时刻只有
  /// 一条条目发得出声音。
  ///
  /// 若 [index] 上没有绑定，则针对它本身是空操作。
  ///
  /// - [index]: the feed index that should be the only one playing /
  ///   应当是唯一在播放的那个 feed 索引
  Future<void> focus(int index) async {
    if (_disposed) return;
    // Iterate a snapshot: this awaits between engines, and a neighbour
    // warm-up left over from a previous activation can bind (mutating
    // `_bound`) inside that window — iterating the live map would throw
    // ConcurrentModificationError.
    //
    // 迭代快照：这里在各引擎之间 await，而上一次激活遗留的邻居预热可能在这个
    // 窗口内完成绑定（改动 `_bound`）——直接迭代活的 map 会抛
    // ConcurrentModificationError。
    for (final entry in _bound.entries.toList()) {
      if (entry.key == index) {
        await entry.value.api.play();
      } else {
        await entry.value.api.pause();
      }
    }
  }

  /// Unbinds every index outside [window], pausing those engines and
  /// returning them to the idle list for reuse.
  ///
  /// Called before binding a new active page so an engine is free to take.
  ///
  /// 解绑 [window] 之外的所有索引，暂停对应引擎并把它们放回空闲列表以供复用。
  ///
  /// 在绑定新的活跃页之前调用，好腾出一个可取用的引擎。
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

  /// Disposes every engine and clears all bookkeeping; the pool is unusable
  /// afterwards.
  ///
  /// 释放所有引擎并清空全部簿记；此后该池不可再用。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bound.clear();
    _idle.clear();
    final engines = List<VmApi>.of(_engines);
    _engines.clear();
    for (final engine in engines) {
      // Per-engine: one engine failing to tear down must not strand the
      // engines after it in the list — those are native decoders and
      // surfaces, and nothing else holds a reference to free them.
      //
      // 逐个包裹：某个引擎拆除失败不能把列表里它后面的引擎晾在那——那些是
      // 原生解码器与画面，除此之外没有任何东西持有它们的引用可供释放。
      try {
        await engine.dispose();
      } on Object {
        // Best-effort teardown; nothing useful to do with the failure here.
        //
        // 尽力而为地拆除；这里对失败没有任何有意义的处理方式。
      }
    }
  }

  /// Returns an engine free to bind to [index]: an idle one, a newly created
  /// one while the pool is below [size], or the one held by the binding
  /// farthest from [index] once it is full.
  ///
  /// Distance-based eviction (not least-recently-used) because a feed's
  /// access pattern is spatial, not temporal: the page just swiped away from
  /// is the *most* recently used yet the likeliest to be needed again, and
  /// LRU would evict exactly the wrong one.
  ///
  /// 返回一个可绑定到 [index] 的空闲引擎：优先取空闲的；池未满时新建；池满
  /// 时淘汰离 [index] 最远的那个绑定并取用它的引擎。
  ///
  /// 按距离淘汰（而非 LRU），因为 feed 的访问模式是空间局部性而非时间局部性：
  /// 刚划走的那页是*最近*使用过的，却也是最可能马上又要用的，LRU 恰好会淘汰
  /// 错的那个。
  ///
  /// - [index]: the feed index the caller is about to bind / 调用方即将绑定的
  ///   feed 索引
  VmApi _acquire(int index) {
    if (_idle.isNotEmpty) return _idle.removeLast();

    if (_engines.length < size) {
      final engine = _factory();
      _engines.add(engine);
      final f = fit;
      if (f != null) unawaited(engine.setFit(f));
      return engine;
    }

    // Farthest first; ties broken toward the page behind, since a feed's
    // next swipe is far more often forward than back.
    //
    // 先淘汰最远的；距离相同时优先淘汰后方那页，因为 feed 的下一次上滑绝大
    // 多数是往前而非往回。
    var victim = _bound.keys.first;
    for (final candidate in _bound.keys) {
      final better = (candidate - index).abs() > (victim - index).abs() ||
          ((candidate - index).abs() == (victim - index).abs() && candidate < victim);
      if (better) victim = candidate;
    }
    _release(victim);
    return _idle.removeLast();
  }

  /// Unbinds [index], pauses its engine and parks it in the idle list.
  ///
  /// Does not notify — callers batch a single [_notify] after releasing.
  ///
  /// 解绑 [index]，暂停其引擎并把它放进空闲列表。
  ///
  /// 不发出通知——调用方在释放完成后统一发一次 [_notify]。
  ///
  /// - [index]: the feed index to unbind / 要解绑的 feed 索引
  void _release(int index) {
    final binding = _bound.remove(index);
    if (binding == null) return;
    unawaited(binding.api.pause());
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
/// [center], for a pool holding [size] engines.
///
/// Expands outward from [center], forward first (`[c, c+1, c-1, c+2, …]`),
/// because a feed is swiped forward far more often than back — with an odd
/// [size] the window ends up symmetric, with an even one the extra engine
/// goes ahead. Negative indices are skipped, so near the top of the feed the
/// window is short and a spare engine simply stays idle.
///
/// 返回观众停留在 [center] 时、容量为 [size] 的引擎池值得保持绑定的 feed
/// 索引。
///
/// 从 [center] 向外展开，向前优先（`[c, c+1, c-1, c+2, …]`），因为 feed 往前
/// 滑远多于往回滑——[size] 为奇数时窗口对称，为偶数时多出来的那个引擎放在
/// 前方。负索引会被跳过，因此在 feed 顶部窗口会短一些，多余的引擎就闲置。
///
/// - [center]: the active feed index / 当前活跃的 feed 索引
/// - [size]: how many engines the pool holds / 引擎池容量
///
/// Returns the indices in warm-up priority order, [center] first.
///
/// 按预热优先级顺序返回索引，[center] 排在最前。
List<int> vmFeedWindow(int center, int size) {
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
