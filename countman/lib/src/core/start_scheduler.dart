import 'package:flutter/scheduler.dart';

/// Frame-based batch scheduler for widget animation starts.
///
/// When many widgets start animating simultaneously (e.g. a grid triggered
/// by one setState), each startup work unit (Handle creation + paragraph
/// cache cold-start) can easily exceed the 16ms frame budget.
///
/// Enqueue each start callback with a [batchSize]; the scheduler drains
/// [batchSize] items per frame via [SchedulerBinding.scheduleFrameCallback],
/// spreading the cost across multiple frames.
///
/// Always pair [enqueue] with [cancel] in [State.dispose] to remove stale
/// closures that would otherwise keep the State alive in memory.
///
/// Usage:
/// ```dart
/// // In _startAnimation():
/// StartScheduler.instance.enqueue(
///   () { if (mounted) _launch(); },
///   batchSize: widget.batch,
///   tag: this,          // identity key for cancellation
/// );
///
/// // In dispose():
/// StartScheduler.instance.cancel(this);
/// ```
class StartScheduler {
  StartScheduler._();
  static final instance = StartScheduler._();

  final _queue = <_Item>[];
  bool _scheduled = false;

  /// Enqueue [fn].
  ///
  /// [batchSize] == 0 runs [fn] immediately without queuing.
  ///
  /// [tag] is an identity key used by [cancel]. Pass the owning object
  /// (typically `this` in a State) so the item can be removed before it runs.
  void enqueue(void Function() fn, {int batchSize = 0, Object? tag}) {
    if (batchSize <= 0) {
      fn();
      return;
    }
    _queue.add(_Item(fn, batchSize, tag));
    _scheduleIfNeeded();
  }

  /// Remove all queued items tagged with [owner] before they execute.
  ///
  /// Call this from [State.dispose] to:
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

    // Use the batch size of the first pending item.
    // In practice, one "wave" (from a single setState) shares the same size.
    final n = _queue.first.batchSize;
    final end = n < _queue.length ? n : _queue.length;
    final batch = _queue.sublist(0, end);
    _queue.removeRange(0, end);

    for (final item in batch) {
      item.fn();
    }

    _scheduleIfNeeded();
  }

  /// Discard all pending items (e.g. when the owning plugin is destroyed).
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
