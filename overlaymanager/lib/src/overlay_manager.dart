import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Rendering phase of an active overlay.
///
/// Two-phase close: an overlay first moves to [closing] (so it can play an exit
/// animation) and is only physically removed afterwards, which then advances
/// the queue.
enum OverlayPhase {
  /// The overlay is fully shown.
  open,

  /// The overlay has been asked to close and is playing its exit animation.
  closing,
}

/// Builds the content widget of an overlay.
///
/// [handle] lets the widget read its own [OverlayHandle.phase] (for exit
/// animations), deliver a result and close itself.
typedef OverlayContentBuilder<T> = Widget Function(
  BuildContext context,
  OverlayHandle<T> handle,
);

/// Condition predicate; receives the manager's context map (see
/// [OverlayManager.setContext]). When provided it is the SOLE authority —
/// `route` / `requiresAuth` sugar is ignored (TS parity).
typedef OverlayPredicate = bool Function(Map<String, Object?> context);

/// Frequency-capping configuration. All present fields must pass (AND), and
/// counts increment when the overlay actually opens (TS parity).
///
/// * [session] — at most N times per manager instance (in memory).
/// * [total] — at most N times ever (persisted).
/// * [day]/[hour]/[minute] — at most N times per LOCAL calendar day/hour/minute
///   (persisted).
/// * [minGap] — a rolling minimum interval since the last open (persisted).
class OverlayCooldown {
  const OverlayCooldown({
    this.session,
    this.total,
    this.day,
    this.hour,
    this.minute,
    this.minGap,
  });

  final int? session;
  final int? total;
  final int? day;
  final int? hour;
  final int? minute;
  final Duration? minGap;

  bool get _needsPersistence =>
      total != null ||
      day != null ||
      hour != null ||
      minute != null ||
      minGap != null;
}

/// Pluggable persistence for [OverlayCooldown] counters. The default is
/// [MemoryCooldownStorage]; back it with `shared_preferences` (or anything
/// else) in real apps:
///
/// ```dart
/// class PrefsCooldownStorage implements OverlayCooldownStorage {
///   Future<String?> read(String key) async =>
///       (await SharedPreferences.getInstance()).getString(key);
///   Future<void> write(String key, String value) async =>
///       (await SharedPreferences.getInstance()).setString(key, value);
/// }
/// ```
abstract class OverlayCooldownStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// In-memory [OverlayCooldownStorage] (per-process; survives manager
/// re-creation when the same instance is shared).
class MemoryCooldownStorage implements OverlayCooldownStorage {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;
}

/// A lightweight view of one managed entry, handed to [OverlayManager.clearWhere].
class OverlayRecord {
  const OverlayRecord._(this.id, this.slot, this.data, this.active, this.phase);

  final String id;
  final String slot;
  final Object? data;

  /// Whether the entry currently occupies a slot / overlaps (vs queued).
  final bool active;

  /// `pending` / `resolving` / `open` / `closing`.
  final String phase;
}

/// A live handle to one shown overlay.
///
/// Returned indirectly via the [Future] from [OverlayManager.open], and passed
/// to the [OverlayContentBuilder] so the widget can drive its own lifecycle.
class OverlayHandle<T> {
  OverlayHandle._(this.id, this._data);

  /// Unique id of the overlay (queue tracking / imperative close).
  final String id;

  Object? _data;

  /// Opaque payload handed to [OverlayManager.open] (or produced by its
  /// `resolve` callback, or merged by [OverlayManager.update]).
  Object? get data => _data;

  final Completer<T?> _completer = Completer<T?>();
  final ValueNotifier<OverlayPhase> _phase =
      ValueNotifier<OverlayPhase>(OverlayPhase.open);

  // Wired by the manager once the entry is created.
  late void Function(T? result) _requestClose;

  /// Completes when the overlay is closed. Carries the result passed to
  /// [close]/[OverlayManager.close], or `null` when dismissed.
  Future<T?> get result => _completer.future;

  /// Current phase; rebuilds that listen to [phaseListenable] update on change.
  OverlayPhase get phase => _phase.value;

  /// Listenable phase, for `ValueListenableBuilder` driven exit animations.
  ValueListenable<OverlayPhase> get phaseListenable => _phase;

  /// Whether the overlay is playing its exit animation.
  bool get isClosing => _phase.value == OverlayPhase.closing;

  /// Request a two-phase close, optionally delivering [result].
  void close([T? result]) => _requestClose(result);

  void _settle(T? value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void _dispose() => _phase.dispose();
}

/// Context handed to a [Present] callback when the queue grants permission to
/// show an externally rendered overlay.
class PresentContext {
  const PresentContext._(this.id, this.slot, this.data);

  /// Unique id of the queue entry (same as [OverlayHandle.id]).
  final String id;

  /// The serial slot this entry was queued in.
  final String slot;

  /// Opaque payload handed to [OverlayManager.open] (post-`resolve` if any).
  final Object? data;
}

/// Bidirectional handle returned by a [Present] callback.
///
/// Adapts an external overlay system (showDialog / GetX / bot_toast / ...) to
/// the orchestrator:
///
/// * [dismissed] — the backend's completion signal. It must complete when the
///   overlay is closed **through any path** (user tap, barrier, back button,
///   timeout, programmatic close). Its value becomes the result of
///   [OverlayManager.open].
/// * [dismiss] — lets the orchestrator close the backend (replace/preemption/
///   [OverlayManager.close]). Must target **this** overlay specifically (e.g.
///   pop by unique route name, `SnackbarController.close()`, `CancelFunc`) —
///   never "pop whatever is on top".
class PresentedOverlay<T> {
  PresentedOverlay({required this.dismissed, this.dismiss});

  /// Completes when the backend overlay is fully closed.
  final Future<T?> dismissed;

  /// Gracefully close the backend overlay, optionally delivering [result].
  /// When null the orchestrator cannot preempt this overlay; [OverlayManager.close]
  /// then only detaches it from the queue (the backend keeps its own lifecycle).
  final Future<void> Function([T? result])? dismiss;
}

/// Presents an overlay through an external system when the queue grants
/// permission. Called at most once per queue entry.
typedef Present<T> = PresentedOverlay<T> Function(PresentContext context);

enum _EntryPhase { pending, resolving, open, closing }

/// Internal, generic-erased queue/active record.
class _Entry {
  _Entry({
    required this.id,
    required this.slot,
    required this.priority,
    required this.seq,
    required this.overlap,
    required this.replace,
    required this.affix,
    required this.delay,
    required this.duration,
    required this.exitDuration,
    required this.barrierColor,
    required this.barrierDismissible,
    required this.when,
    required this.route,
    required this.requiresAuth,
    required this.dismissWhenUnmet,
    required this.cooldown,
    required this.beforeClose,
    required this.resolveData,
    required this.phaseListenable,
    required this.build,
    required this.settle,
    required this.setPhase,
    required this.getData,
    required this.setData,
    required this.disposeHandle,
    this.presentExternal,
  });

  final String id;
  final String slot;
  final int priority;
  int seq;
  final bool overlap;
  final bool replace;
  final bool affix;
  final Duration? delay;
  final Duration? duration;
  final Duration? exitDuration;
  final Color? barrierColor;
  final bool barrierDismissible;

  final OverlayPredicate? when;
  final Object? route;
  final bool? requiresAuth;
  final bool dismissWhenUnmet;
  final OverlayCooldown? cooldown;
  final FutureOr<bool> Function()? beforeClose;

  /// Backend-driven data resolution (generic-erased); null skips the overlay.
  final Future<Object?> Function()? resolveData;

  final ValueListenable<OverlayPhase> phaseListenable;

  /// Builds the widget for builtin (self-rendered) entries; null for external.
  final Widget Function(BuildContext context)? build;

  /// Invokes the user's [Present] callback and wires the returned handle
  /// (generic-erased); null for builtin entries.
  final void Function()? presentExternal;

  /// Graceful backend close, wired by [presentExternal] once presented.
  Future<void> Function(Object? result)? externalDismiss;

  /// Whether the backend reported (or was told) it is fully closed.
  bool externalDone = false;

  bool get isExternal => presentExternal != null;

  /// Complete the result future exactly once (typed cast lives in the closure).
  final void Function(Object? result) settle;

  /// Flip the public [OverlayHandle.phase].
  final void Function(OverlayPhase phase) setPhase;

  /// Live payload accessors (backing the handle's mutable data).
  final Object? Function() getData;
  final void Function(Object? data) setData;

  /// Dispose the handle's notifier.
  final void Function() disposeHandle;

  _EntryPhase phase = _EntryPhase.pending;
  bool skipGap = false;
  bool delayConsumed = false;
  bool settled = false;
  bool paused = false;

  /// Whether this entry currently belongs to the `replace` front band (a
  /// pending preemptor). Starts equal to [replace]; cleared when the entry is
  /// displaced back to the queue — a displaced overlay is a resumer, not a
  /// preemptor, so it must not out-band the replacer that displaced it.
  late bool replaceBand = replace;

  /// True while this entry sits in the queue AFTER having been shown and
  /// displaced by a `replace` (a "resumer"). Drives three things at once: (1)
  /// lets a still-held handle's `close()` take effect (remove + settle)
  /// instead of being silently dropped and re-showing later; (2) exempts the
  /// re-show from its `cooldown` — it already counted (and passed) that
  /// cooldown on the first open, so the resume must neither re-count NOR be
  /// re-blocked by it (mirrors the TS `exemptCooldown`, and keeps a
  /// one-shot-cooldown entry from being stranded in the queue forever).
  bool wasDisplaced = false;

  /// Set once a `resolve` callback has successfully produced data. A resumed
  /// (displaced-then-re-shown) entry skips re-resolving and reopens with the
  /// already-fetched payload instead of invoking the backend again.
  bool resolved = false;

  OverlayEntry? overlayEntry;
  Timer? durationTimer;
  DateTime? durationDeadline;
  Duration? durationRemaining;
  Timer? removeTimer;

  bool get isActive =>
      phase == _EntryPhase.open ||
      phase == _EntryPhase.closing ||
      phase == _EntryPhase.resolving;

  bool get isShown =>
      phase == _EntryPhase.open || phase == _EntryPhase.closing;

  String get phaseName => switch (phase) {
        _EntryPhase.pending => 'pending',
        _EntryPhase.resolving => 'resolving',
        _EntryPhase.open => 'open',
        _EntryPhase.closing => 'closing',
      };
}

/// Per-slot serial state.
class _Slot {
  _Entry? active;
  final List<_Entry> queue = <_Entry>[];
  Timer? gapTimer;
  Timer? delayTimer;
  Timer? cooldownTimer;
  bool gapPending = false;
}

/// Persisted per-id cooldown counters.
class _CooldownRecord {
  _CooldownRecord({
    this.total = 0,
    this.dayBucket = '',
    this.dayCount = 0,
    this.hourBucket = '',
    this.hourCount = 0,
    this.minuteBucket = '',
    this.minuteCount = 0,
    this.lastShownMs,
  });

  factory _CooldownRecord.fromJson(Map<String, Object?> json) =>
      _CooldownRecord(
        total: (json['t'] as num?)?.toInt() ?? 0,
        dayBucket: json['db'] as String? ?? '',
        dayCount: (json['dc'] as num?)?.toInt() ?? 0,
        hourBucket: json['hb'] as String? ?? '',
        hourCount: (json['hc'] as num?)?.toInt() ?? 0,
        minuteBucket: json['mb'] as String? ?? '',
        minuteCount: (json['mc'] as num?)?.toInt() ?? 0,
        lastShownMs: (json['ls'] as num?)?.toInt(),
      );

  int total;
  String dayBucket;
  int dayCount;
  String hourBucket;
  int hourCount;
  String minuteBucket;
  int minuteCount;
  int? lastShownMs;

  Map<String, Object?> toJson() => <String, Object?>{
        't': total,
        'db': dayBucket,
        'dc': dayCount,
        'hb': hourBucket,
        'hc': hourCount,
        'mb': minuteBucket,
        'mc': minuteCount,
        'ls': lastShownMs,
      };
}

String _two(int n) => n < 10 ? '0$n' : '$n';
String _dayBucketOf(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
String _hourBucketOf(DateTime t) => '${_dayBucketOf(t)}T${_two(t.hour)}';
String _minuteBucketOf(DateTime t) => '${_hourBucketOf(t)}:${_two(t.minute)}';

/// Hydrate-once cooldown store: reads run synchronously after [hydrate];
/// writes are fire-and-forget write-through.
class _CooldownStore {
  _CooldownStore(this._storage, this._key);

  final OverlayCooldownStorage _storage;
  final String _key;
  final Map<String, _CooldownRecord> _persisted = <String, _CooldownRecord>{};
  final Map<String, int> _session = <String, int>{};

  Future<void> hydrate() async {
    try {
      final raw = await _storage.read(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      decoded.forEach((id, value) {
        if (value is Map<String, Object?>) {
          _persisted[id] = _CooldownRecord.fromJson(value);
        } else if (value is Map) {
          _persisted[id] =
              _CooldownRecord.fromJson(value.cast<String, Object?>());
        }
      });
    } catch (_) {
      // Corrupt or unavailable storage degrades to empty counters.
    }
  }

  void _flush() {
    final json = <String, Object?>{
      for (final e in _persisted.entries) e.key: e.value.toJson(),
    };
    // Fire and forget; persistence failures must not break scheduling.
    // Called directly (not wrapped in Future()) so synchronous storages
    // commit immediately and no timer is left pending.
    try {
      unawaited(
        _storage.write(_key, jsonEncode(json)).catchError((Object _) {}),
      );
    } catch (_) {
      // Synchronous storage failure — ignore.
    }
  }

  // Equivalent to (and implemented via) `timeUntilEligible(...) ==
  // Duration.zero`: null (session/total block) and any positive wait both mean
  // "not yet", only an exact zero wait means every cap currently passes.
  bool canShow(String id, OverlayCooldown cd, DateTime now) =>
      timeUntilEligible(id, cd, now) == Duration.zero;

  /// How long until [id] could next pass [cd] on its **time-based** caps
  /// (`minGap` + day/hour/minute bucket rollover), or `null` if a cap that
  /// never auto-clears (`session`/`total`) currently blocks it. `Duration.zero`
  /// means the cooldown already passes (any remaining block is not time-based).
  /// Used to wake a queued entry exactly when its cooldown expires.
  Duration? timeUntilEligible(String id, OverlayCooldown cd, DateTime now) {
    if (cd.session != null && (_session[id] ?? 0) >= cd.session!) return null;
    final rec = _persisted[id];
    if (cd.total != null && (rec?.total ?? 0) >= cd.total!) return null;
    var wait = Duration.zero;
    void bump(Duration d) {
      if (d > wait) wait = d;
    }

    if (cd.day != null) {
      final c =
          rec != null && rec.dayBucket == _dayBucketOf(now) ? rec.dayCount : 0;
      if (c >= cd.day!) {
        final next = DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 1));
        bump(next.difference(now));
      }
    }
    if (cd.hour != null) {
      final c = rec != null && rec.hourBucket == _hourBucketOf(now)
          ? rec.hourCount
          : 0;
      if (c >= cd.hour!) {
        final next = DateTime(now.year, now.month, now.day, now.hour)
            .add(const Duration(hours: 1));
        bump(next.difference(now));
      }
    }
    if (cd.minute != null) {
      final c = rec != null && rec.minuteBucket == _minuteBucketOf(now)
          ? rec.minuteCount
          : 0;
      if (c >= cd.minute!) {
        final next = DateTime(now.year, now.month, now.day, now.hour, now.minute)
            .add(const Duration(minutes: 1));
        bump(next.difference(now));
      }
    }
    if (cd.minGap != null && rec?.lastShownMs != null) {
      final remain = cd.minGap!.inMilliseconds -
          (now.millisecondsSinceEpoch - rec!.lastShownMs!);
      if (remain > 0) bump(Duration(milliseconds: remain));
    }
    return wait;
  }

  void record(String id, OverlayCooldown cd, DateTime now) {
    if (cd.session != null) _session[id] = (_session[id] ?? 0) + 1;
    if (!cd._needsPersistence) return;
    final rec = _persisted.putIfAbsent(id, _CooldownRecord.new);
    rec.total += 1;
    final dayB = _dayBucketOf(now);
    rec.dayCount = rec.dayBucket == dayB ? rec.dayCount + 1 : 1;
    rec.dayBucket = dayB;
    final hourB = _hourBucketOf(now);
    rec.hourCount = rec.hourBucket == hourB ? rec.hourCount + 1 : 1;
    rec.hourBucket = hourB;
    final minB = _minuteBucketOf(now);
    rec.minuteCount = rec.minuteBucket == minB ? rec.minuteCount + 1 : 1;
    rec.minuteBucket = minB;
    rec.lastShownMs = now.millisecondsSinceEpoch;
    _flush();
  }
}

/// A Flutter-native overlay **queue** manager.
///
/// Unlike a headless orchestrator, this class embraces Flutter: it inserts and
/// removes real [OverlayEntry]s in an attached [OverlayState] (or drives an
/// external overlay system through a [Present] callback). It provides:
///
/// * **serial one-at-a-time** queueing per named [slot] (default slot `''`),
///   with an optional [gap] between successive overlays;
/// * **priority** (higher shows first; FIFO within a priority);
/// * **replace** (preempt the current overlay of a slot), **affix** (protect
///   the current overlay from `replace`) and **overlap** (bypass the queue and
///   stack immediately);
/// * **conditions** (`when` / `route` / `requiresAuth` against [setContext],
///   with `dismissWhenUnmet` auto-dismissal) and **cooldown** frequency caps;
/// * backend-driven **`resolve`** data loading and a **`beforeClose`** guard;
/// * imperative **`Future<T?>` results** (like `showDialog`);
/// * **two-phase close** so widgets can play an exit animation;
/// * **pauseAll/resumeAll** full freeze and per-id **pause/resume** for
///   `duration` timers.
///
/// Attach it to an [OverlayState] via [attach] (or use `OverlayManagerScope`).
class OverlayManager extends ChangeNotifier {
  OverlayManager({
    this.gap = Duration.zero,
    this.exitDuration = const Duration(milliseconds: 200),
    OverlayCooldownStorage? cooldownStorage,
    String storageKey = 'overlaymanager:cooldown',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _cooldowns =
        _CooldownStore(cooldownStorage ?? MemoryCooldownStorage(), storageKey);
    _ready = _cooldowns.hydrate();
  }

  /// Delay inserted between one overlay closing and the next one showing.
  final Duration gap;

  /// Default time an overlay stays in [OverlayPhase.closing] before removal.
  final Duration exitDuration;

  final DateTime Function() _now;
  late final _CooldownStore _cooldowns;
  late final Future<void> _ready;

  OverlayState? _overlay;
  final Map<String, _Slot> _slots = <String, _Slot>{};
  final List<_Entry> _overlaps = <_Entry>[];
  final List<_Entry> _pendingOverlaps = <_Entry>[];
  final Map<String, _Entry> _byId = <String, _Entry>{};
  final Map<String, Object?> _context = <String, Object?>{};
  int _seqCounter = 0;
  bool _paused = false;

  /// Completes when persisted cooldown counters have been hydrated. Await it
  /// before relying on `total`/`day`/... caps across restarts.
  Future<void> ready() => _ready;

  /// Whether an [OverlayState] is currently attached.
  bool get isAttached => _overlay != null;

  /// Whether [pauseAll] is in effect.
  bool get isPaused => _paused;

  /// Ids currently waiting in any queue (observability/debugging).
  List<String> get queuedIds => <String>[
        for (final slot in _slots.values)
          for (final e in slot.queue) e.id,
        for (final e in _pendingOverlaps) e.id,
      ];

  /// Ids currently shown (open or closing), across serial slots and overlaps.
  List<String> get activeIds => <String>[
        for (final slot in _slots.values)
          if (slot.active != null && slot.active!.isShown) slot.active!.id,
        for (final e in _overlaps)
          if (e.isShown) e.id,
      ];

  /// Whether [id] is currently shown.
  bool isShowing(String id) {
    final e = _byId[id];
    return e != null && e.isShown;
  }

  /// Attach the manager to an [OverlayState]. Pending/queued overlays that were
  /// requested before attach are scheduled now.
  void attach(OverlayState overlay) {
    if (_overlay == overlay) return;
    _overlay = overlay;
    for (final slot in _slots.keys.toList()) {
      _schedule(slot);
    }
  }

  /// Detach from the current [OverlayState] without settling anything (the
  /// entries are removed from the old overlay). Used when the host unmounts.
  void detach() {
    if (_overlay == null) return;
    for (final slot in _slots.values) {
      final active = slot.active;
      if (active != null) _detachOverlayEntry(active);
    }
    for (final e in _overlaps) {
      _detachOverlayEntry(e);
    }
    _overlay = null;
  }

  void _detachOverlayEntry(_Entry e) {
    e.overlayEntry?.remove();
    e.overlayEntry = null;
  }

  /// Unhooks [e] from `slot.active` / `_overlaps` / `_pendingOverlaps`
  /// tracking. Returns whether it was occupying its slot's serial `active`
  /// position (callers that need to advance the queue check this).
  bool _detachFromActive(_Entry e) {
    final s = _slots[e.slot];
    final wasActive = s != null && s.active == e;
    if (wasActive) s.active = null;
    _overlaps.remove(e);
    _pendingOverlaps.remove(e);
    return wasActive;
  }

  /// Merge [partial] into the condition context and re-evaluate:
  /// * shown overlays whose conditions no longer pass are auto-dismissed
  ///   (unless they opted out via `dismissWhenUnmet: false`);
  /// * queued overlays that became eligible get a chance to show.
  ///
  /// Reserved keys used by the built-in sugar: `route` (String) and `auth`
  /// (bool). Everything else is free-form for `when` predicates.
  void setContext(Map<String, Object?> partial) {
    _context.addAll(partial);
    final shown = <_Entry>[
      for (final s in _slots.values)
        if (s.active != null) s.active!,
      ..._overlaps,
    ];
    for (final e in shown) {
      if (e.isActive && e.dismissWhenUnmet && !_conditionsPass(e)) {
        _remove(e);
      }
    }
    for (final slot in _slots.keys.toList()) {
      _schedule(slot);
    }
    notifyListeners();
  }

  /// Freeze everything: no new activation (serial, overlap, replace) and all
  /// running `duration` timers pause. Explicit [close]/[remove]/[clear] still
  /// work. [resumeAll] releases held overlaps and re-schedules.
  void pauseAll() {
    if (_paused) return;
    _paused = true;
    for (final s in _slots.values) {
      _cancelCooldownTimer(s);
    }
    for (final e in _byId.values) {
      _freezeDuration(e);
    }
    notifyListeners();
  }

  /// Undo [pauseAll]: release overlaps held while paused (if still eligible),
  /// thaw `duration` timers and re-schedule every slot.
  void resumeAll() {
    if (!_paused) return;
    _paused = false;
    final held = List<_Entry>.of(_pendingOverlaps);
    _pendingOverlaps.clear();
    for (final e in held) {
      if (!_isCurrent(e)) continue;
      if (_eligible(e)) {
        _openOverlap(e);
      } else {
        _byId.remove(e.id);
        _finalize(e);
      }
    }
    for (final e in _byId.values) {
      _thawDuration(e);
    }
    for (final slot in _slots.keys.toList()) {
      _schedule(slot);
    }
    notifyListeners();
  }

  /// Freeze [id]'s `duration` countdown (the overlay stays shown).
  void pause(String id) {
    final e = _byId[id];
    if (e == null || e.paused) return;
    e.paused = true;
    _freezeDuration(e);
  }

  /// Resume [id]'s `duration` countdown with the remaining time.
  void resume(String id) {
    final e = _byId[id];
    if (e == null || !e.paused) return;
    e.paused = false;
    _thawDuration(e);
  }

  /// Merge [patch] into [id]'s `data` in place (map-into-map merges shallowly,
  /// anything else replaces) and rebuild — without any queue change.
  void update(String id, Object? patch) {
    final e = _byId[id];
    if (e == null) return;
    final current = e.getData();
    if (current is Map && patch is Map) {
      e.setData(<Object?, Object?>{...current, ...patch});
    } else {
      e.setData(patch);
    }
    e.overlayEntry?.markNeedsBuild();
    notifyListeners();
  }

  /// Enqueue (or immediately show) an overlay.
  ///
  /// Returns a [Future] that completes when the overlay closes: with the value
  /// passed to [OverlayHandle.close] / [close], or `null` when dismissed.
  ///
  /// Provide **exactly one** of [builder] (self-rendered into the attached
  /// [OverlayState]) or [present] (rendered by an external system — showDialog,
  /// GetX, bot_toast, ... — which is invoked only when the queue grants
  /// permission; see [Present]/[PresentedOverlay]).
  ///
  /// * [id] — unique key; if omitted an auto id is generated. Reusing an id
  ///   that is currently shown replaces it; reusing a queued id overrides it.
  /// * [slot] — independent serial queue (default `''`).
  /// * [priority] — higher shows first; ties break FIFO.
  /// * [delay] — wait before this overlay appears (overrides [gap] for itself).
  /// * [duration] — auto-close this long after opening.
  /// * [replace] — preempt the slot's current overlay, show immediately
  ///   (unless the current one is [affix]ed, or the replacer is not eligible).
  /// * [affix] — protect this overlay from `replace` (explicit [close]/
  ///   [remove]/[clear] still work; duplicate-id self-update is not blocked).
  /// * [overlap] — bypass the queue and stack on top immediately. Conditions/
  ///   cooldown act as a fire-gate: not eligible ⇒ dropped (result `null`).
  /// * [when]/[route]/[requiresAuth] — conditions against [setContext]
  ///   (`when` overrides the sugar); [dismissWhenUnmet] (default true)
  ///   auto-dismisses a shown overlay whose conditions stop holding.
  /// * [cooldown] — frequency caps; counts on real open.
  /// * [resolve] — backend-driven payload: called when the entry is granted
  ///   the slot; `null` skips the overlay, otherwise the value becomes `data`.
  /// * [beforeClose] — close guard: returning `false` cancels a [close].
  /// * [barrierColor] / [barrierDismissible] — optional modal barrier
  ///   (builtin [builder] entries only).
  /// * [exitDuration] — builtin: per-overlay override of
  ///   [OverlayManager.exitDuration]. External: extra grace between the
  ///   backend's dismissed signal and queue advance.
  Future<T?> open<T>({
    OverlayContentBuilder<T>? builder,
    Present<T>? present,
    String? id,
    Object? data,
    String slot = '',
    int priority = 0,
    Duration? delay,
    Duration? duration,
    bool replace = false,
    bool affix = false,
    bool overlap = false,
    OverlayPredicate? when,
    Object? route,
    bool? requiresAuth,
    bool dismissWhenUnmet = true,
    OverlayCooldown? cooldown,
    Future<T?> Function()? resolve,
    FutureOr<bool> Function()? beforeClose,
    Color? barrierColor,
    bool barrierDismissible = false,
    Duration? exitDuration,
  }) {
    assert(
      (builder == null) != (present == null),
      'Provide exactly one of builder or present',
    );
    assert(
      route == null || route is String || route is List<String> || route is RegExp,
      'route must be a String, List<String> or RegExp',
    );
    final resolvedId = id ?? 'overlay:${++_seqCounter}';
    final handle = OverlayHandle<T>._(resolvedId, data);

    late final _Entry entry;
    entry = _Entry(
      id: resolvedId,
      slot: slot,
      priority: priority,
      seq: ++_seqCounter,
      overlap: overlap,
      replace: replace,
      affix: affix,
      delay: delay,
      duration: duration,
      exitDuration: exitDuration,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      when: when,
      route: route,
      requiresAuth: requiresAuth,
      dismissWhenUnmet: dismissWhenUnmet,
      cooldown: cooldown,
      beforeClose: beforeClose,
      resolveData: resolve == null ? null : () async => await resolve(),
      phaseListenable: handle.phaseListenable,
      build: builder == null ? null : (context) => builder(context, handle),
      settle: (Object? r) => handle._settle(r as T?),
      setPhase: (p) => handle._phase.value = p,
      getData: () => handle._data,
      setData: (v) => handle._data = v,
      disposeHandle: handle._dispose,
      presentExternal: present == null
          ? null
          : () {
              final presented = present(
                PresentContext._(resolvedId, slot, handle._data),
              );
              final dismiss = presented.dismiss;
              entry.externalDismiss = dismiss == null
                  ? null
                  : (Object? r) => dismiss(r as T?);
              presented.dismissed.then(
                (T? r) => _onExternalDismissed(entry, r),
                onError: (Object _) => _onExternalDismissed(entry, null),
              );
            },
    );
    handle._requestClose = (r) => _close(entry, r);

    // Handle id reuse.
    final existing = _byId[resolvedId];
    if (existing != null) {
      if (existing.isActive) {
        _discardActive(existing); // replaced in place; old result -> null
        entry.skipGap = true;
      } else {
        _removeFromQueue(existing);
        _pendingOverlaps.remove(existing);
        _byId.remove(existing.id);
        _finalize(existing);
      }
    }
    _byId[resolvedId] = entry;

    if (overlap) {
      // Conditions/cooldown are a one-shot fire-gate for overlaps (TS rule:
      // "now or never") — but a paused manager holds them for resumeAll.
      if (!_eligible(entry)) {
        _byId.remove(entry.id);
        _finalize(entry);
      } else if (_paused) {
        _pendingOverlaps.add(entry);
      } else {
        _openOverlap(entry);
      }
      notifyListeners();
      return handle.result;
    }

    final s = _slotFor(slot);
    // A replace only displaces the current overlay when the replacer itself is
    // eligible right now (TS invariant 5b) and the manager is not paused; an
    // affixed current blocks displacement but the replacer keeps its front-band
    // ordering and shows next.
    if (replace && !_paused && _eligible(entry)) {
      entry.skipGap = true;
      final cur = s.active;
      if (cur != null && cur.isActive && !cur.affix) {
        // Only a builtin overlay that is actually SHOWN (phase open) is
        // displaced BACK to the queue to re-show later (mirrors the TS
        // `displace`). A `resolving` entry has nothing on screen and still has
        // an in-flight resolver — displacing it would double-run the resolver
        // and could open with stale data — so it (like closing/external
        // entries) is discarded instead.
        if (!cur.isExternal && cur.phase == _EntryPhase.open) {
          _displace(cur);
        } else {
          _discardActive(cur);
        }
      }
      // TS-parity: a replace arriving during the transition gap means
      // "show me NOW" — skip the remaining gap.
      if (s.gapPending) {
        s.gapTimer?.cancel();
        s.gapTimer = null;
        s.gapPending = false;
      }
    }
    s.queue.add(entry);
    _schedule(slot);
    notifyListeners();
    return handle.result;
  }

  /// Two-phase close [id], optionally delivering [result]. A `beforeClose`
  /// guard returning `false` cancels the close.
  void close(String id, [Object? result]) {
    final e = _byId[id];
    if (e == null) return;
    _close(e, result);
  }

  /// Dismiss [id] (close with a `null` result).
  void dismiss(String id) => close(id);

  /// Immediately remove [id] with no exit animation (settles `null` if it had
  /// not been settled by a prior [close]). Bypasses `beforeClose`.
  void remove(String id) {
    final e = _byId[id];
    if (e == null) return;
    _remove(e);
  }

  /// Remove everything: queued and active, across all slots and overlaps.
  /// Unsettled results resolve `null`. Bypasses `beforeClose`.
  void clear() {
    for (final s in _slots.values) {
      _cancelCooldownTimer(s);
    }
    final all = _byId.values.toList();
    for (final e in all) {
      _remove(e, advance: false);
    }
    notifyListeners();
  }

  /// Selectively remove every entry (queued or shown) matching [test].
  /// "Close all of group X" is `clearWhere((r) => (r.data as MyData?)?.group == 'x')`.
  void clearWhere(bool Function(OverlayRecord record) test) {
    final selected = <_Entry>[
      for (final e in _byId.values.toList())
        if (test(OverlayRecord._(
          e.id,
          e.slot,
          e.getData(),
          e.isActive,
          e.phaseName,
        )))
          e,
    ];
    for (final e in selected) {
      _remove(e);
    }
  }

  // ── internals ──────────────────────────────────────────────────────────

  _Slot _slotFor(String slot) => _slots.putIfAbsent(slot, () => _Slot());

  void _removeFromQueue(_Entry e) {
    final s = _slots[e.slot];
    s?.queue.remove(e);
  }

  int _cmp(_Entry a, _Entry b) {
    // Replace entries form a front band: a preemptor must show before anything
    // that was already waiting (mirrors the TS package's replace-jumped rule).
    // A displaced entry has left the band (replaceBand=false), so the replacer
    // that displaced it still shows first even if the displaced entry has an
    // older seq / was itself a replace.
    if (a.replaceBand != b.replaceBand) return a.replaceBand ? -1 : 1;
    if (a.priority != b.priority) return b.priority - a.priority;
    return a.seq - b.seq;
  }

  bool _eligible(_Entry e) => _conditionsPass(e) && _cooldownPass(e);

  bool _conditionsPass(_Entry e) {
    final when = e.when;
    if (when != null) return when(Map<String, Object?>.unmodifiable(_context));
    if (e.route != null && !_routeMatches(e.route!, _context['route'])) {
      return false;
    }
    if (e.requiresAuth != null && e.requiresAuth != (_context['auth'] == true)) {
      return false;
    }
    return true;
  }

  static bool _routeMatches(Object pattern, Object? current) {
    if (current is! String) return false;
    if (pattern is String) return pattern == current;
    if (pattern is List<String>) return pattern.contains(current);
    if (pattern is RegExp) return pattern.hasMatch(current);
    return false;
  }

  bool _cooldownPass(_Entry e) {
    // A displaced entry already showed once under this cooldown; let it resume
    // regardless of the cap (else a `session:1`/`total:1` displaced entry could
    // never re-show and its result future would hang forever).
    if (e.wasDisplaced) return true;
    final cd = e.cooldown;
    if (cd == null) return true;
    return _cooldowns.canShow(e.id, cd, _now());
  }

  void _cancelCooldownTimer(_Slot s) {
    s.cooldownTimer?.cancel();
    s.cooldownTimer = null;
  }

  void _schedule(String slot) {
    if (_paused) return;
    final s = _slotFor(slot);
    _cancelCooldownTimer(s);
    if (s.active != null) return; // slot occupied
    if (s.gapPending) return; // waiting out the transition gap
    if (s.queue.isEmpty) return;

    final sorted = s.queue.toList()..sort(_cmp);
    _Entry? front;
    for (final e in sorted) {
      if (_eligible(e)) {
        front = e;
        break;
      }
    }
    if (front == null) {
      // Nothing eligible now. Entries blocked purely by a time-based cooldown
      // (minGap / bucket rollover) have a known expiry — wake the slot then so
      // they don't wait in the queue forever (cooldown expiry is otherwise not
      // a scheduling trigger).
      _armCooldownWake(slot, s);
      return; // ineligible entries WAIT
    }

    // Only builtin (self-rendered) entries need an attached OverlayState;
    // external entries are rendered by their own backend.
    if (!front.isExternal && _overlay == null) return;

    // Per-overlay appear delay.
    if (!front.skipGap &&
        !front.delayConsumed &&
        front.delay != null &&
        front.delay! > Duration.zero) {
      front.delayConsumed = true;
      s.delayTimer?.cancel();
      s.delayTimer = Timer(front.delay!, () {
        s.delayTimer = null;
        _schedule(slot);
      });
      return;
    }
    _activate(front);
  }

  /// Arm a one-shot timer to re-run [_schedule] when the soonest time-based
  /// cooldown among the slot's otherwise-eligible queued entries expires.
  void _armCooldownWake(String slot, _Slot s) {
    Duration? soonest;
    for (final e in s.queue) {
      final cd = e.cooldown;
      if (cd == null) continue;
      if (e.wasDisplaced) continue; // resumer: not cooldown-gated
      if (!_conditionsPass(e)) continue; // conditions are event-driven, not timed
      final w = _cooldowns.timeUntilEligible(e.id, cd, _now());
      if (w == null || w <= Duration.zero) continue;
      if (soonest == null || w < soonest) soonest = w;
    }
    if (soonest == null) return;
    // Small cushion so the timer fires strictly after the cap has cleared.
    s.cooldownTimer = Timer(soonest + const Duration(milliseconds: 16), () {
      s.cooldownTimer = null;
      _schedule(slot);
      notifyListeners();
    });
  }

  void _activate(_Entry e) {
    final s = _slotFor(e.slot);
    _removeFromQueue(e);
    s.active = e;
    final resolver = e.resolveData;
    // A resume (displaced-then-re-shown entry) already resolved successfully
    // once — reuse that payload instead of re-invoking the backend (avoids a
    // duplicate fetch / duplicate side effect, and avoids a second resolve
    // silently discarding an already-shown overlay if it now returns null).
    if (resolver != null && !e.resolved) {
      // Backend-driven payload: the slot is committed while resolving (not
      // interrupted by later arrivals); null ⇒ skip without opening.
      e.phase = _EntryPhase.resolving;
      notifyListeners();
      resolver().then(
        (data) => _onResolved(e, data),
        onError: (Object _) => _onResolved(e, null),
      );
      return;
    }
    _open(e);
  }

  void _onResolved(_Entry e, Object? data) {
    if (!_isCurrent(e) || e.phase != _EntryPhase.resolving) return;
    if (data == null) {
      // Backend said "don't show": skip without counting cooldown.
      final s = _slots[e.slot];
      if (s != null && s.active == e) s.active = null;
      _byId.remove(e.id);
      _finalize(e);
      notifyListeners();
      _schedule(e.slot);
      return;
    }
    e.setData(data);
    e.resolved = true;
    _open(e);
  }

  void _open(_Entry e) {
    e.phase = _EntryPhase.open;
    final cd = e.cooldown;
    if (cd != null && !e.wasDisplaced) _cooldowns.record(e.id, cd, _now());
    e.wasDisplaced = false; // now shown again: normal close path applies
    if (e.isExternal) {
      e.presentExternal!();
    } else {
      _insert(e);
    }
    _startDuration(e);
    notifyListeners();
  }

  void _openOverlap(_Entry e) {
    _overlaps.add(e);
    _open(e);
  }

  void _insert(_Entry e) {
    final overlay = _overlay;
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<OverlayPhase>(
        valueListenable: e.phaseListenable,
        builder: (context, _, _) {
          final content = e.build!(context);
          final hasBarrier = e.barrierColor != null || e.barrierDismissible;
          if (!hasBarrier) return content;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: e.barrierDismissible ? () => _close(e, null) : null,
                  child: ColoredBox(
                    color: e.barrierColor ?? const Color(0x00000000),
                  ),
                ),
              ),
              content,
            ],
          );
        },
      ),
    );
    e.overlayEntry = entry;
    overlay.insert(entry);
  }

  void _startDuration(_Entry e) {
    // A displaced entry carries its REMAINING time (frozen in `_displace`); a
    // fresh open uses the full `duration`. Either way, don't re-arm the full
    // window on a re-show.
    final d = e.durationRemaining ?? e.duration;
    if (d == null) {
      e.durationRemaining = null;
      return;
    }
    if (_paused || e.paused) {
      e.durationRemaining = d; // already d if this was a resume; harmless if so
      return;
    }
    e.durationRemaining = null;
    e.durationDeadline = _now().add(d);
    e.durationTimer = Timer(d, () => _close(e, null));
  }

  void _freezeDuration(_Entry e) {
    final timer = e.durationTimer;
    if (timer == null) return;
    timer.cancel();
    e.durationTimer = null;
    final deadline = e.durationDeadline;
    var remaining =
        deadline == null ? Duration.zero : deadline.difference(_now());
    if (remaining < Duration.zero) remaining = Duration.zero;
    e.durationRemaining = remaining;
  }

  void _thawDuration(_Entry e) {
    if (_paused || e.paused) return;
    final remaining = e.durationRemaining;
    if (remaining == null || e.phase != _EntryPhase.open) return;
    e.durationRemaining = null;
    e.durationDeadline = _now().add(remaining);
    e.durationTimer = Timer(remaining, () => _close(e, null));
  }

  // A displaced overlay is back in the queue but the caller may still hold its
  // handle: `close()` should honor that (remove + settle with the result)
  // instead of dropping it and letting the overlay silently re-show. A normal
  // never-shown queued entry is untouched (`_isDisplacedPending` is false).
  /// Whether [e] is still the live, tracked entry for its id — false once it's
  /// been removed/replaced-in-place (a stale async callback from an entry no
  /// longer in `_byId` must not act on it).
  bool _isCurrent(_Entry e) => _byId[e.id] == e;

  bool _isDisplacedPending(_Entry e) =>
      e.phase == _EntryPhase.pending && e.wasDisplaced;

  /// Whether [e] can still be meaningfully closed: either actually shown
  /// (`open`) or a displaced resumer waiting in the queue to re-show.
  bool _closable(_Entry e) =>
      e.phase == _EntryPhase.open || _isDisplacedPending(e);

  void _close(_Entry e, Object? result) {
    if (!_closable(e)) return;

    final guard = e.beforeClose;
    if (guard == null) {
      _finishClose(e, result);
      return;
    }
    final FutureOr<bool> verdict;
    try {
      verdict = guard();
    } catch (_) {
      return; // a throwing guard cancels the close
    }
    if (verdict is bool) {
      if (verdict) _finishClose(e, result);
      return;
    }
    verdict.then(
      (ok) {
        // Re-check current state at resolution time — a replace may have
        // displaced this entry (or re-shown it) while the guard was pending;
        // honor an already-approved close against whichever state it's in.
        if (ok && _isCurrent(e) && _closable(e)) _finishClose(e, result);
      },
      onError: (Object _) {
        // A failing guard cancels the close.
      },
    );
  }

  void _finishClose(_Entry e, Object? result) {
    if (_isDisplacedPending(e)) {
      _settle(e, result);
      _remove(e);
    } else {
      _doClose(e, result);
    }
  }

  void _doClose(_Entry e, Object? result) {
    e.durationTimer?.cancel();
    e.durationTimer = null;
    e.durationRemaining = null;
    _settle(e, result);
    e.phase = _EntryPhase.closing;
    e.setPhase(OverlayPhase.closing);
    notifyListeners();
    if (e.isExternal) {
      final dismiss = e.externalDismiss;
      if (dismiss == null || e.externalDone) {
        // Backend already closed, or cannot be closed by us: just detach.
        _remove(e);
      } else {
        // Graceful backend close; its dismissed signal drives removal
        // (plus the optional exitDuration grace) in _onExternalDismissed.
        dismiss(result);
      }
      return;
    }
    final exit = e.exitDuration ?? exitDuration;
    if (exit <= Duration.zero) {
      _remove(e);
    } else {
      e.removeTimer = Timer(exit, () => _remove(e));
    }
  }

  /// The external backend reported it is fully closed (user tap, barrier,
  /// back button, timeout, or our own dismiss). Settle and advance the queue.
  void _onExternalDismissed(_Entry e, Object? result) {
    e.externalDone = true;
    _settle(e, result);
    if (!_isCurrent(e)) return; // already removed / replaced in place
    if (e.phase == _EntryPhase.open) {
      // Closed directly by the backend (not via our close()).
      e.phase = _EntryPhase.closing;
      e.setPhase(OverlayPhase.closing);
      notifyListeners();
    }
    final grace = e.exitDuration;
    if (grace != null && grace > Duration.zero) {
      e.removeTimer?.cancel();
      e.removeTimer = Timer(grace, () => _remove(e));
    } else {
      _remove(e);
    }
  }

  /// Remove an active/queued entry from the world. When [advance] is true and
  /// it occupied a serial slot, the queue is advanced (after [gap]).
  void _remove(_Entry e, {bool advance = true}) {
    e.durationTimer?.cancel();
    e.removeTimer?.cancel();
    e.durationTimer = null;
    e.removeTimer = null;

    _byId.remove(e.id);
    _detachOverlayEntry(e);
    _dismissBackendBestEffort(e);

    final wasSerialActive = _detachFromActive(e);
    _removeFromQueue(e);

    _finalize(e);

    if (advance && wasSerialActive) {
      final s = _slotFor(e.slot);
      if (gap > Duration.zero) {
        s.gapPending = true;
        s.gapTimer?.cancel();
        s.gapTimer = Timer(gap, () {
          s.gapPending = false;
          s.gapTimer = null;
          _schedule(e.slot);
          notifyListeners();
        });
      } else {
        _schedule(e.slot);
      }
    }
    notifyListeners();
  }

  /// A `replace` preempted this still-open builtin entry: send it BACK to the
  /// queue instead of dropping it, so it shows again once the replacer closes.
  /// Its result future stays pending; it keeps its id/data. Only reachable for
  /// `phase == open` — a `resolving` entry is `_discardActive`d instead (its
  /// in-flight resolver can't be safely re-presented; see the replace branch).
  void _displace(_Entry e) {
    // Freeze (don't discard) the duration so the re-show resumes the REMAINING
    // time rather than a fresh full window.
    _freezeDuration(e);
    e.removeTimer?.cancel();
    e.removeTimer = null;
    _detachOverlayEntry(e);
    _detachFromActive(e);
    e.phase = _EntryPhase.pending;
    e.skipGap = false;
    e.delayConsumed = true; // don't replay the appear delay on re-show
    e.replaceBand = false; // a resumer, not a preemptor
    // Only reached for a phase==open entry (see the replace branch): it already
    // counted AND passed its cooldown, so the re-show is exempt from both; this
    // flag is also what lets a still-held handle's close() take effect below.
    e.wasDisplaced = true;
    _slotFor(e.slot).queue.add(e);
  }

  // Deliberately NOT `_remove(e, advance: false)`: that also calls
  // `notifyListeners()`, which would fire mid-`open()` with transient state
  // (this entry gone, the new one not yet enqueued) — the caller's own
  // trailing `notifyListeners()` is the only one that should fire here.
  void _discardActive(_Entry e) {
    e.durationTimer?.cancel();
    e.removeTimer?.cancel();
    _byId.remove(e.id);
    _detachOverlayEntry(e);
    _dismissBackendBestEffort(e);
    _detachFromActive(e);
    _finalize(e);
  }

  /// When an external entry leaves the queue while its backend may still be
  /// showing (replace/clear/remove), ask the backend to close, fire-and-forget.
  void _dismissBackendBestEffort(_Entry e) {
    if (!e.isExternal || e.externalDone) return;
    e.externalDone = true; // its dismissed signal must not re-drive removal
    e.externalDismiss?.call(null);
  }

  void _finalize(_Entry e) {
    _settle(e, null);
    e.disposeHandle();
  }

  void _settle(_Entry e, Object? result) {
    if (e.settled) return;
    e.settled = true;
    e.settle(result);
  }

  @override
  void dispose() {
    for (final s in _slots.values) {
      s.gapTimer?.cancel();
      s.delayTimer?.cancel();
      s.cooldownTimer?.cancel();
    }
    clear();
    super.dispose();
  }
}
