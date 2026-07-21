/// Data store (live refresh).
///
/// Manages the current shoe's round results, exposing three update paths:
/// [RoadmapStore.setResults] / [RoadmapStore.append] / [RoadmapStore.patch].
/// Only append triggers animation semantics; setResults and patch refresh
/// directly. Multiple appends within the same microtask are coalesced into
/// a single notification (to prevent a notification storm).
/// Ported from `src/core/store.ts`.
library;

import 'dart:async';

import 'emitter.dart';
import 'types.dart';

/// Update kind.
enum UpdateKind {
  /// Full replacement (polling / reconnect reconciliation).
  full,

  /// Append a round (the normal push path; the only entry point that triggers animation).
  append,

  /// Correct a historical round.
  patch,
}

/// Store change event payload.
class ChangeEvent {
  /// Update kind.
  final UpdateKind kind;

  /// Current full results list (read-only snapshot).
  final List<RawResult> results;

  /// The newly appended round when kind is append; null for other kinds.
  final RawResult? appended;

  const ChangeEvent({required this.kind, required this.results, this.appended});
}

/// Out-of-order / gap callback (caller should pull the full data and reconcile via [RoadmapStore.setResults]).
typedef OutOfSyncCallback = void Function(int expected, int actual);

/// Data store.
class RoadmapStore {
  List<RawResult> _results = [];
  final _emitter = Emitter<ChangeEvent>();
  final OutOfSyncCallback? _onOutOfSync;

  bool _pendingFlush = false;
  RawResult? _pendingLastAppended;

  RoadmapStore({OutOfSyncCallback? onOutOfSync}) : _onOutOfSync = onOutOfSync;

  /// Fully replaces the results (polling / reconnect reconciliation). No animation, refreshes directly.
  void setResults(List<RawResult> results) {
    _results = List.of(results);
    _snapshot = null;
    _emitter.emit(ChangeEvent(kind: UpdateKind.full, results: List.of(_results)));
  }

  /// Appends a round (the normal push path; the only entry point that triggers the insertion animation).
  ///
  /// Requires `result.no == last.no + 1`; otherwise the result is not
  /// stored and [OutOfSyncCallback] is invoked instead.
  /// Multiple appends within the same microtask are coalesced into a single notification.
  void append(RawResult result) {
    final last = _results.isNotEmpty ? _results.last : null;
    final expected = last != null ? last.no + 1 : 1;
    if (result.no != expected) {
      _onOutOfSync?.call(expected, result.no);
      return;
    }
    _results = [..._results, result];
    _snapshot = null;
    _scheduleFlush(result);
  }

  /// Corrects a historical round (no animation).
  void patch(int no, RawResult result) {
    final idx = _results.indexWhere((r) => r.no == no);
    if (idx == -1) return;
    _results = [..._results.sublist(0, idx), result, ..._results.sublist(idx + 1)];
    _snapshot = null;
    _emitter.emit(ChangeEvent(kind: UpdateKind.patch, results: List.of(_results)));
  }

  /// Read-only snapshot cache: [getResults] returns the same instance when
  /// data hasn't changed — reference stability is what lets
  /// `Engine.compute`'s reference-based memoization hit when the UI side
  /// re-renders for unrelated reasons.
  List<RawResult>? _snapshot;

  /// Gets a read-only snapshot of the current results list (returns the same instance when data hasn't changed, safe to compare by reference).
  List<RawResult> getResults() => _snapshot ??= List.unmodifiable(_results);

  /// Subscribes to data changes, returning an unsubscribe function.
  void Function() subscribe(Listener<ChangeEvent> cb) => _emitter.on(cb);

  /// Schedules a microtask flush (skipped if one is already scheduled; runs once on the next microtask).
  void _scheduleFlush(RawResult appended) {
    _pendingLastAppended = appended;
    if (_pendingFlush) return;
    _pendingFlush = true;
    scheduleMicrotask(() {
      _pendingFlush = false;
      final last = _pendingLastAppended;
      _pendingLastAppended = null;
      _emitter.emit(ChangeEvent(kind: UpdateKind.append, results: List.of(_results), appended: last));
    });
  }
}

/// Creates a data store instance.
///
/// ```dart
/// final store = createStore(onOutOfSync: (exp, act) => print('out of sync $exp $act'));
/// store.subscribe((e) { if (e.kind == UpdateKind.append) playAnimation(e.appended!); });
/// store.setResults(shoe.results);
/// ```
RoadmapStore createStore({OutOfSyncCallback? onOutOfSync}) => RoadmapStore(onOutOfSync: onOutOfSync);
