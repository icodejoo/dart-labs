import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame-based batch scheduler for widget animation starts.
///
/// When many widgets start animating simultaneously (e.g. a dense grid
/// triggered by one setState), each startup work unit can easily exceed the
/// 16ms frame budget. The scheduler spreads starts across frames.
///
/// ## Two ways to control batch size
///
/// **1. Global default** — set once before the triggering setState:
/// ```dart
/// StartScheduler.instance.defaultBatchSize = 5;
/// setState(() => _target = 999);
/// ```
///
/// **2. Per-group override** — each [Counter] instance can override
/// for its own tasks:
/// ```dart
/// final vipPlugin = Counter();
/// StartScheduler.instance.groupBatchSize[vipPlugin] = 10;
/// ```
///
/// Resolution order: per-group > global > 0 (run immediately).
///
/// Always pair [enqueue] with [cancel] in [State.dispose] to avoid memory
/// leaks — the closure holds a reference to the State.
/// 分帧启动调度器；批内任务可取消，异常不影响后续启动。
class StartScheduler {
  StartScheduler._();
  static final instance = StartScheduler._();

  /// Global default. 0 = run immediately (no batching).
  int defaultBatchSize = 0;

  /// Per-group overrides. Key: any object that identifies the group
  /// (e.g. a [Counter] instance).
  final Map<Object, int> groupBatchSize = {};

  final _queue = <_Item>[];
  bool _scheduled = false;

  /// 当前已出队批次，允许回调取消批内尚未执行的项。
  List<_Item>? _activeBatch;

  /// Resolve effective batch size for [group].
  /// Priority: groupBatchSize[group] > defaultBatchSize.
  int batchSizeFor(Object? group) {
    if (group != null && groupBatchSize.containsKey(group)) {
      return groupBatchSize[group]!;
    }
    return defaultBatchSize;
  }

  /// Enqueue [fn].
  ///
  /// [tag] — identity key for [cancel]; pass `this` from the owning State.
  /// [group] — optional group identity for per-group batch size lookup.
  void enqueue(void Function() fn, {required Object tag, Object? group}) {
    final bs = batchSizeFor(group);
    if (bs <= 0) {
      fn();
      return;
    }
    _queue.add(_Item(fn, bs, tag, group));
    _scheduleIfNeeded();
  }

  /// Remove all queued items tagged with [owner] before they execute.
  ///
  /// Call from [State.dispose] to:
  /// - prevent the callback from running on a disposed widget, and
  /// - release the closure's reference to the State so it can be GC'd.
  /// 同时取消排队项与当前批内尚未执行的 owner 项。
  void cancel(Object owner) {
    for (final item in _activeBatch ?? const <_Item>[]) {
      if (identical(item.tag, owner)) item.cancelled = true;
    }
    _queue.removeWhere((item) => identical(item.tag, owner));
  }

  /// Release a group's configuration and pending starts.
  /// 插件注销时同时释放分组配置与待启动闭包。
  /// 释放分组配置并取消排队项和当前批内的分组项。
  void removeGroup(Object group) {
    for (final item in _activeBatch ?? const <_Item>[]) {
      if (identical(item.group, group)) item.cancelled = true;
    }
    groupBatchSize.remove(group);
    _queue.removeWhere((item) => identical(item.group, group));
  }

  void _scheduleIfNeeded() {
    if (_scheduled || _queue.isEmpty) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_drain);
  }

  /// 隔离每项异常，并在批次收尾时继续调度剩余启动。
  void _drain(Duration _) {
    _scheduled = false;
    if (_queue.isEmpty) return;

    // Only batch the leading run that shares the first item's batchSize, so
    // items enqueued by a different group (with its own batchSize) aren't
    // swept up under the wrong size — they get their own batch next frame.
    //
    // 只批处理与队首 batchSize 相同的前导连续段，使不同 group（各有自己 batchSize）
    // 入队的项不被按错误大小一起处理——它们下一帧各自成批。
    final n = _queue.first.batchSize;
    var end = 0;
    while (end < _queue.length && end < n && _queue[end].batchSize == n) {
      end++;
    }
    final batch = _queue.sublist(0, end);
    _queue.removeRange(0, end);

    _activeBatch = batch;
    try {
      for (final item in batch) {
        if (item.cancelled) continue;
        try {
          item.fn();
        } catch (error, stack) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'countman',
            context: ErrorDescription('StartScheduler 批启动回调异常'),
          ));
        }
      }
    } finally {
      _activeBatch = null;
      _scheduleIfNeeded();
    }
  }

  /// Discard all pending items.
  /// 清空排队项并取消当前批内尚未执行的启动。
  void clear() {
    for (final item in _activeBatch ?? const <_Item>[]) {
      item.cancelled = true;
    }
    _queue.clear();
    _scheduled = false;
  }
}

/// 可取消的批启动项。
class _Item {
  /// 保存启动回调与所属 owner、分组。
  _Item(this.fn, this.batchSize, this.tag, this.group);

  /// 已被 owner、分组或清空操作取消。
  bool cancelled = false;
  final void Function() fn;
  final int batchSize;
  final Object? tag;
  final Object? group;
}
