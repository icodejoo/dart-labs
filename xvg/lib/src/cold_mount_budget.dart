// A per-frame time budget that keeps XvgStatic's synchronous cold-cache
// renders from overloading a single frame when many never-before-seen SVGs
// mount at once — see the class doc on ColdMountFrameBudget for why time
// beats a fixed item count.
//
// 给 XvgStatic 同步冷缓存渲染设的单帧时间预算，避免大量从未见过的 SVG
// 同时挂载时把一帧撑爆——为什么用时间而不是固定个数，见
// ColdMountFrameBudget 的类文档。

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

/// Caps how much wall-clock time [XvgStatic] may spend on synchronous
/// cold-cache Rust parse+record work within a single frame, so that mounting
/// many never-before-seen SVGs at once (e.g. a first-ever-seen icon grid)
/// can't blow one frame's budget — the overflow spills into subsequent
/// frames, each capped the same way, until the queue drains.
///
/// A fixed item-count cap can't do this portably: how many icons fit in one
/// frame depends on both the device's speed and each SVG's own complexity,
/// neither of which this budget needs to know — it just stops admitting more
/// synchronous work once the *already-measured* time spent this frame
/// crosses [frameBudget], and lets whatever's left wait for the next frame.
/// A cache hit or the ordinary "a couple of new icons scroll into view"
/// case never touches this at all: only a genuine cold miss consumes budget.
///
/// 给 [XvgStatic] 的同步冷缓存 Rust 解析+录制工作设一个单帧墙钟时间上限，
/// 这样一次性挂载大量从未见过的 SVG（比如首次出现的图标网格）就不会把一帧的
/// 预算撑爆——超出的部分溢出到后续帧，每帧同样设限，直到队列排空。
///
/// 固定个数上限做不到这一点：一帧能装下几个图标，既取决于设备速度也取决于每个
/// SVG 自身的复杂度，而这个预算完全不需要知道这两者——它只是在**本帧已经实测
/// 花掉的时间**超过 [frameBudget] 后停止再放行同步工作，让剩下的等下一帧。
/// 缓存命中、或"滚动进来几个新图标"这种寻常场景完全不会碰到它：只有真正的
/// 冷未命中才会消耗预算。
class ColdMountFrameBudget {
  ColdMountFrameBudget._();

  /// Shared instance. / 共享单例。
  static final ColdMountFrameBudget instance = ColdMountFrameBudget._();

  /// Per-frame time budget for synchronous cold-cache renders. Half of a
  /// 60fps frame (16.7ms), leaving the other half for everything else that
  /// frame has to do (layout, other widgets' build, paint, raster). A flat
  /// constant rather than a per-device tuned value — see class doc for why.
  ///
  /// 单帧内同步冷缓存渲染的时间预算。取 60fps 一帧(16.7ms)的一半，把另一半
  /// 留给这一帧要做的其它事(布局、其它控件的 build、绘制、光栅化)。用固定常量
  /// 而非按设备调参——原因见类文档。
  static const Duration frameBudget = Duration(milliseconds: 8);

  Duration _spent = Duration.zero;
  Duration? _frameStamp;
  int _resetGeneration = 0;
  bool _resetScheduled = false;
  final Map<Object, Future<Object?>> _byKey = {};
  final Map<Object, Map<Object, bool Function()>> _activeByKey = {};
  final List<void Function()> _pending = <void Function()>[];
  bool _retryScheduled = false;

  /// True while this frame still has budget room for another synchronous
  /// cold render. [XvgStatic.build] checks this before calling
  /// [RustXvgPictureCache.getOrRender] directly; once false for the rest of
  /// the frame, further cold sources fall back to [runDeferred].
  ///
  /// 本帧是否仍有预算容纳下一次同步冷渲染。[XvgStatic.build] 在直接调用
  /// [RustXvgPictureCache.getOrRender] 之前会先查这个；一旦本帧内变为 false,
  /// 之后的冷源就转而走 [runDeferred]。
  bool get hasRoom {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle) {
      return _spent < frameBudget;
    }
    final stamp = scheduler.currentFrameTimeStamp;
    if (_frameStamp != stamp) {
      _frameStamp = stamp;
      _spent = Duration.zero;
    }
    return _spent < frameBudget;
  }

  /// Runs [work] (a synchronous cold render) and charges its wall-clock time
  /// against this frame's budget. Callers should only call this when
  /// [hasRoom] is true, else use [runDeferred] instead — widgets within one
  /// frame's build phase are processed in order by Flutter itself, so this
  /// is inherently sequential, not racy.
  ///
  /// 执行 [work](一次同步冷渲染)并把其墙钟耗时记入本帧预算。调用方只应在
  /// [hasRoom] 为 true 时调用；否则改用 [runDeferred]——一帧的 build 阶段本就
  /// 由 Flutter 按顺序处理各控件，天然有序、不存在竞态。
  T runNow<T>(T Function() work) {
    hasRoom; // 在本帧第一次记账前更新帧时间戳。
    final stopwatch = Stopwatch()..start();
    if (!_resetScheduled) {
      _resetScheduled = true;
      final generation = _resetGeneration;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (generation != _resetGeneration) return;
        _spent = Duration.zero;
        _resetScheduled = false;
      });
    }
    try {
      return work();
    } finally {
      _spent += stopwatch.elapsed;
    }
  }

  /// Queues [work] to run once a future frame has budget room again, and
  /// returns a [Future] that completes with its result then. Used by
  /// [XvgStatic.build] when [hasRoom] is already false for the current
  /// frame — the same [FutureBuilder] + placeholder scaffold already used for
  /// the `<image>`-decode path picks this up.
  ///
  /// 把 [work] 排入队列，等未来某一帧预算恢复后执行，返回一个到时完成的
  /// [Future]。在当前帧 [hasRoom] 已为 false 时由 [XvgStatic.build] 调用——
  /// 复用 `<image>` 解码路径已有的那套 [FutureBuilder] + 占位符脚手架来接住它。
  Future<T> runDeferred<T>(
    T Function() work, {
    Object? key,
    Object? owner,
    bool Function()? isActive,
  }) {
    // 同键共享队列项；每个调用方都留下存活检查，至少一个仍挂载才执行。
    if (key != null && _byKey.containsKey(key)) {
      _activeByKey[key]![owner ?? Object()] = isActive ?? () => true;
      return _byKey[key]! as Future<T>;
    }
    if (key != null) {
      _activeByKey[key] = {owner ?? Object(): isActive ?? () => true};
    }
    final completer = Completer<T>();
    if (key != null) _byKey[key] = completer.future;
    _pending.add(() {
      final active = key == null
          ? (isActive?.call() ?? true)
          : _activeByKey.remove(key)!.values.any((check) => check());
      if (key != null) _byKey.remove(key);
      // 全部卸载时丢弃闭包；FutureBuilder 也已卸载，无需发布结果。
      if (!active) return;
      try {
        completer.complete(work());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _scheduleRetry();
    return completer.future;
  }

  void _scheduleRetry() {
    if (_retryScheduled) return;
    _retryScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _drainOnNextFrame());
    // A deferred render exists, so a further frame must actually happen for
    // it to ever get its turn — the frame that deferred it doesn't guarantee
    // another one is coming (it might have been the last dirty widget in an
    // otherwise-idle app). Only reached while [_pending] is non-empty, so an
    // idle app with nothing deferred never has an extra frame forced on it —
    // see `static20_bench_screen.dart`'s `_awaitFullyPainted` doc comment for
    // why that distinction matters.
    //
    // 已经有一个渲染被推迟了，所以必须真的再来一帧它才有机会轮到——推迟它的
    // 那一帧并不保证后面还有帧（它可能是原本已空闲的 app 里最后一个脏控件）。
    // 只在 [_pending] 非空时才会走到这里，所以真正空闲、没有任何推迟工作的
    // app 不会被强行多摊一帧——为什么这点重要，见
    // `static20_bench_screen.dart` 的 `_awaitFullyPainted` 文档注释。
    SchedulerBinding.instance.scheduleFrame();
  }

  void _drainOnNextFrame() {
    _retryScheduled = false;
    _spent = Duration.zero;
    while (_pending.isNotEmpty && hasRoom) {
      final next = _pending.removeAt(0);
      runNow(next);
    }
    if (_pending.isNotEmpty) _scheduleRetry();
  }

  /// Resets all accounting and drops any queued work. Test-only — production
  /// code never needs to reset this singleton.
  ///
  /// 重置全部计数并丢弃排队中的工作。仅供测试——生产代码不需要重置这个单例。
  @visibleForTesting
  void debugReset() {
    _spent = Duration.zero;
    _frameStamp = null;
    _resetGeneration++;
    _resetScheduled = false;
    _byKey.clear();
    _activeByKey.clear();
    _pending.clear();
    _retryScheduled = false;
  }
}
