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
/// **2. Per-group override** — each [Countup] instance can override
/// for its own tasks:
/// ```dart
/// final vipPlugin = Countup();
/// StartScheduler.instance.groupBatchSize[vipPlugin] = 10;
/// ```
///
/// Resolution order: per-group > global > 0 (run immediately).
///
/// Always pair [enqueue] with [cancel] in [State.dispose] to avoid memory
/// leaks — the closure holds a reference to the State.
class StartScheduler {
  StartScheduler._();
  static final instance = StartScheduler._();

  /// Global default. 0 = run immediately (no batching).
  int defaultBatchSize = 0;

  /// Per-group overrides. Key: any object that identifies the group
  /// (e.g. a [Countup] instance).
  final Map<Object, int> groupBatchSize = {};

  final _queue = <_Item>[];
  bool _scheduled = false;

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
    _queue.add(_Item(fn, bs, tag));
    _scheduleIfNeeded();
  }

  /// Remove all queued items tagged with [owner] before they execute.
  ///
  /// Call from [State.dispose] to:
  /// - prevent the callback from running on a disposed widget, and
  /// - release the closure's reference to the State so it can be GC'd.
  void cancel(Object owner) {
    _queue.removeWhere((item) => identical(item.tag, owner));
  }

  void _scheduleIfNeeded() {
    if (_scheduled || _queue.isEmpty) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(_drain);
  }

  void _drain(Duration _) {
    _scheduled = false;
    if (_queue.isEmpty) return;

    final n = _queue.first.batchSize;
    final end = n < _queue.length ? n : _queue.length;
    final batch = _queue.sublist(0, end);
    _queue.removeRange(0, end);

    for (final item in batch) {
      item.fn();
    }

    _scheduleIfNeeded();
  }

  /// Discard all pending items.
  void clear() {
    _queue.clear();
    _scheduled = false;
  }
}

class _Item {
  const _Item(this.fn, this.batchSize, this.tag);
  final void Function() fn;
  final int batchSize;
  final Object? tag;
}
