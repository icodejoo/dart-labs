## 1.0.0

**Breaking**

| 0.x | 1.0.0 |
| --- | --- |
| `replace: true` | `mode: OverlayMode.replace` |
| `overlap: true` | `mode: OverlayMode.overlap` |
| Both omitted / false | Omit `mode` or use `mode: OverlayMode.queue` |
| `replace: true, overlap: true` | No equivalent: select exactly one mode. |
| `route: '/home'` | `route: const RouteMatcher.exact('/home')` |
| `route: ['/home', '/promo']` | `route: const RouteMatcher.anyOf(['/home', '/promo'])` |
| `route: RegExp(r'^/promo')` | `route: RouteMatcher.regex(RegExp(r'^/promo'))` |
| `pauseOnRoutes: ['/checkout', RegExp(r'^/pay')]` | `pauseOnRoutes: [const RouteMatcher.exact('/checkout'), RouteMatcher.regex(RegExp(r'^/pay'))]` |
| A list pattern inside `pauseOnRoutes` | Wrap that pattern with `RouteMatcher.anyOf(...)`. |
| `record.phase == 'open'` | `record.phase == OverlayPhase.open` |

* `open` and `submit` replace the `replace` / `overlap` booleans with `mode`
  (default `OverlayMode.queue`). `affix` remains independent.
* `route` is now `RouteMatcher?`; `pauseOnRoutes` is `List<RouteMatcher>`.
  Choose `exact`, `anyOf` or `regex`; weakly typed patterns are no longer accepted.
* `OverlayRecord.phase` is now `OverlayPhase`, with `pending`, `resolving`,
  `open` and `closing` values, instead of strings.

**Fixed**

* Request backend `dismiss` at most once per entry. Randomized sequence tests
  found that `close` followed by `remove`, `clear` or a dismiss timeout could
  request dismissal again. Non-idempotent backends such as `popUntil` or
  `Get.back()` could then close another overlay. The `dismissRequested` guard
  prevents retries, including after a failing dismiss; targeted handles remain required.
* `open` during `build()` defers presentation and manager notifications until
  after the frame instead of presenting and notifying synchronously.
* Batch manager notifications per public operation so listeners see completed
  synchronous changes rather than multiple intermediate notifications.
* Reclaim empty runtime slots once they have no occupant, queued entries,
  pending gap or gap/delay/cooldown timers.

**Added**

* `cooldownStatus` returning `OverlayCooldownStatus`, `resetCooldown` and
  `clearCooldowns` for inspecting and resetting session and persisted counters.
* Copied, read-only `tags` on records and `clearTag` for grouped removal.
* `OverlayMode`, `RouteMatcher` and `OverlayPhase` typed public contracts.
* Randomized sequence invariant tests (`test/fuzz_invariants_test.dart`),
  regression coverage for batched notifications, build deferral and slot reclamation.
* Example demonstrations for the new modes, route matchers, cooldown inspection
  and reset, tags and build-time submission.

## 0.3.0

**Fixed**

* Reopening an active serial id takes over its slot when eligible and unpaused,
  instead of losing it to a higher-priority queued entry. Old results settle as
  `null` (`superseded`); old tickets cannot affect the new submission.
* `PresentContext.dataListenable` makes `update()` data available to backends;
  `data` remains a presentation-time snapshot.
* Queue insertion now preserves replace / priority / FIFO ordering;
  `queuedIds` reflects that order within each slot. Predicate context views are cached.

**Changed (behavior)**

* **`LayermanNavigatorObserver` now tracks only `PageRoute` by default.**
  Dialogs and bottom sheets no longer overwrite page context, dismiss their own
  route-gated overlays, or release no-overlay zones. To restore 0.2.x tracking of
  every route, pass `routeFilter: (r) => true`. Use `contextKey` for nested navigators;
  `route:` and `pauseOnRoutes` still read only the default `route` key.
* **Exhausted `session` / `total` caps discard serial entries** when checked by
  scheduling, completing with `null` (`capped`) instead of waiting forever.
  Use time-based caps for retryable waits, or a new id for a new campaign.
* **Waiting is bounded by default:** `dismissTimeout` is 10 seconds and
  `resolveTimeout` is 30 seconds. Constructor `null` disables either limit;
  per-entry `resolveTimeout: null` inherits, and `Duration.zero` disables that
  entry's resolve limit. Timeouts report errors and free the slot; a dismiss
  timeout preserves the already-delivered outcome. Backend work is not cancelled.
* Route recipes now recommend **`DialogManager`**, created once with a navigator
  key, instead of a hand-written shared dialog helper. Bind `manager:` to route
  builder close calls through `beforeClose`; custom routes/pages use `presentRoute`.

**Added**

* `DialogManager`, `BottomSheetManager` and `presentRoute`: targeted Route
  presenters waiting for exit completion; per-call configuration overrides.
* `submit<T>()` returning `OverlayTicket<T>` with typed close, update, removal,
  live data, result and outcome; `OverlayOutcome`, `OverlayEndReason`, and async
  broadcast `events` (`OverlayEvent`, `OverlayEventType`).
* `resolvingIds`, `records`, `recordOf` for complete entry inspection.
* Independent pause tokens via `hold()` / `OverlayHold`, `holdCount`, and
  `LayermanLifecycle` for automatic background pause.
* Serial queue expiration via `expireAfter` and per-slot `OverlaySlotOptions`
  (`gap`, `maxQueued`), with `queueExpired` / `queueFull` outcomes.
* `.pubignore` excludes `CLAUDE.md` and `.claude/` from the published package.
* Example Android platform and a “v0.3 Features” demo page. The 26 example
  integration tests pass on a real phone (Huawei STG-AL00, Android 12); the 199
  unit tests pass on Flutter 3.47 and on the minimum supported Flutter 3.27.4.

## 0.2.2

**Fixed**

* `close(id, result)` with a `result` that isn't a `T?` of its `open<T>()` used
  to throw a `TypeError` halfway through the close and leave the `open()` future
  pending forever. It now throws an `ArgumentError` before touching any state,
  so the overlay can still be closed normally afterwards.
* Cooldown hydration race: an entry gated on a persisted cap (`total` / `day` /
  `hour` / `minute` / `minGap`) opened before `ready()` was checked against empty
  counters, and its write-back overwrote every other id's counters in storage
  (hydration then overwrote the new count). Such entries now wait until the
  store has hydrated (an `overlap` one is held, not dropped); hydration merges
  instead of overwriting; writes are serialized (one in flight, then the latest
  snapshot); read/write failures are reported via `FlutterError.reportError`
  instead of being swallowed. `ready()` now completes after the queue has been
  re-scheduled, and awaiting it before `open()` is no longer required. A
  persisted-cap `replace` that arrives before hydration therefore queues at the
  front instead of preempting.
* An async `beforeClose` guard no longer runs twice when `close()` / `dismiss()`
  is called again while it is pending; the repeated calls are ignored.
* A throwing `when` predicate no longer escapes `open()` / `setContext()` /
  timer callbacks: it is reported once per overlay and treated as unmet.
* `open()` after `dispose()` no longer presents the overlay: it asserts in debug
  and returns `null` in release. Every other mutator is a no-op after
  `dispose()`.

**Changed**

* `cooldown` without an explicit `id` now asserts in debug — counters are keyed
  by id, and an auto-generated id changes on every open, so the cap never
  applied.
* README route recipes now push a `Route` object, use `route.completed`
  (completes after the exit animation, carrying the pop result) as `dismissed`,
  and close it with `pop` when on top or `removeRoute` when buried. The previous
  name-based `popUntil` / `Get.until` recipes silently did nothing when the
  dialog wasn't the topmost route (e.g. under an `overlap` dialog), leaving the
  entry stuck in `closing`. Also corrected the docs on `update()`, `activeIds` /
  `isShowing`, and `replace` preempting a resolving entry.
* Minimum SDK is now Dart 3.6 / Flutter 3.27 — the first release with
  `NavigatorObserver.didChangeTop`. The previous `flutter: ">=1.17.0"` bound was
  wrong, and `sdk: ^3.12.2` was needlessly high.
* `ARCHITECTURE.md` / `ARCHITECTURE.svg` rewritten from the actual code.

## 0.2.1

**Fixed**

* A throwing `present` / `dismiss` no longer wedges the queue: the error is
  reported via `FlutterError.reportError`, the entry is dropped (result `null`,
  no cooldown counted) and the queue advances.
* `duration` expiry bypasses `beforeClose` (it gates only an explicit `close()`).
* `resolve` now also runs for `overlap: true` entries; a `resolve` that finishes
  while paused is held until `resumeAll` (resolver is not re-run).
* Reopening the same id from a listener while the old entry is closing no longer
  unregisters the new entry; moving an id to another slot (or to `overlap`)
  re-schedules the slot it vacated.
* `clearWhere` removes everything before advancing, so a matching queued entry is
  never briefly shown; `clear()` also resets a pending transition gap / delay.
* Day/hour/minute cooldown wake-ups use calendar boundaries (DST-safe).

**Changed**

* Internal engine simplified (dead code removed); the example's `presentShadToast`
  now owns the toast lifetime (hide timer, completes on `hide()`), so hover or a
  late exit animation can't advance the queue under a visible toast.

## 0.2.0

**Breaking — the manager is now headless (UI-agnostic).** The self-rendering
`builder:` path is gone; `present:` is the sole rendering hook. The core no
longer owns an `Overlay`, imports no `package:flutter/widgets.dart`, and mirrors
the headless TS sister package.

Why: the whole point is an orchestrator that doesn't care what renders. As long
as `builder:` existed, the manager had to own an `Overlay` layer and be attached
to an `OverlayState` — that *is* a UI responsibility, and it contradicted the
goal. The `present:`/`PresentedOverlay` handle model is a strict superset: a
backend that owns its own `OverlayEntry` covers everything `builder:` did, so
nothing is lost. See the README's "Why there is no `builder:`" section for the
migration recipe.

**Renamed** (to match the package name)

* `OverlayManager` → `Layerman`; `OverlayNavigatorObserver` → `LayermanNavigatorObserver`.
* Everything else keeps its `Overlay*` name on purpose — `OverlayPredicate`,
  `OverlayCooldown`, `OverlayCooldownStorage`, `OverlayRecord`,
  `PresentedOverlay` describe the overlay *being managed*, not the manager
  itself, so renaming those to `Layerman*` would misdescribe what they are
  (e.g. `PresentedOverlay` is "the overlay that got presented", not "a
  presented orchestrator").

**Removed**

* `open(builder: ...)` and the `OverlayContentBuilder` typedef — use
  `open(present: ...)`.
* `OverlayManagerScope`, `Layerman.attach` / `detach` / `isAttached` — the
  manager attaches to nothing now.
* `OverlayHandle`, `OverlayPhase`, and the handle's `phase` /  `phaseListenable`
  / `isClosing` — `open()` returns its `Future<T?>` directly; a backend drives
  its own exit animation and reports completion via `PresentedOverlay.dismissed`.
* `barrierColor` / `barrierDismissible` on `open()` — the backend renders its
  own barrier.
* `Layerman(exitDuration:)` constructor default — `exitDuration` is now a
  per-`open()` grace only (null ⇒ advance immediately).

**Behavior**

* `replace` now always **closes** the preempted overlay (result `null`); it is
  never sent back to the queue to re-show. A dismissed backend can't be
  faithfully re-presented (that would re-run its side effects), so the old
  self-rendered "displace + resume" semantics no longer applied and were
  dropped along with their `wasDisplaced` / `replaceBand` machinery.

**Unchanged**: slots, priority, `affix`, `overlap`, conditions (`when` / `route`
/ `requiresAuth` / `setContext` / `dismissWhenUnmet`), cooldown (+ pluggable
storage), `resolve`, `beforeClose`, `duration`, `delay`, `gap`, `pauseAll` /
`resumeAll` / `pause` / `resume`, `update`, `clearWhere`, `LayermanNavigatorObserver`,
`currentRoute`, `pauseOnRoutes`.


## 0.1.1

Docs only — no code changes.

* README now links the live interactive demo.

## 0.1.0

* **`OverlayNavigatorObserver`** — a `NavigatorObserver` that feeds real
  navigation into `setContext`'s `route` key automatically (deferred to a
  post-frame callback, safe even if navigation happens mid-build). Works
  under vanilla `Navigator`, GetX and go_router alike; purely observational,
  never touches navigation itself. Removes the need to call
  `setContext({'route': ...})` by hand in every page's lifecycle.
* **`OverlayManager.currentRoute`** — reads the tracked `route` context value
  back, so hosts don't need to maintain their own route mirror.
* **`OverlayManager({pauseOnRoutes: [...]})`** — declares "no-overlay zone"
  route patterns: entering a match freezes the whole queue (like `pauseAll`),
  leaving resumes it (like `resumeAll`). Composes correctly with manual
  `pauseAll`/`resumeAll` — neither one overrides the other; the queue only
  actually thaws once both are clear.
* README: new "Auto route awareness" section and a "navigated page as a queue
  entry" recipe (wrapping `Navigator.push` in `present:` — a page route is
  just another external presenter, no `builder:` needed).

## 0.0.1

Initial public release.

A Flutter-native overlay **queue** manager that renders real `OverlayEntry`s and
can also orchestrate overlays rendered by other libraries (`showDialog`, GetX,
`bot_toast`, `fluttertoast`, …).

**Core**

* `OverlayManager` — serial one-at-a-time queueing per named `slot`, with an
  optional `gap`; `open<T>()` returns a `Future<T?>` (like `showDialog`).
* Ordering: `priority` (desc, FIFO ties), `replace` (preempt the current
  overlay — which is sent **back to the queue** and re-shows after the replacer
  closes; front-bands ahead of queued entries; skips a pending gap), `affix`
  (protect the current overlay from `replace`), `overlap` (bypass the queue and
  stack immediately, now-or-never).
* Two-phase close (`OverlayPhase.open` → `closing` → removed) for exit
  animations, driven by `OverlayHandle.phaseListenable`.
* Per-overlay `delay` / `duration` (auto-close) and an optional modal barrier
  (`barrierColor` / `barrierDismissible`).

**Conditions & cooldown**

* Conditions: `when(ctx)` predicate (sole authority), `route`
  (String/List/RegExp) + `requiresAuth` sugar, `setContext({...})` push-model
  re-evaluation, and `dismissWhenUnmet` (default true) auto-dismissal.
* Cooldown: `OverlayCooldown(session/total/day/hour/minute/minGap)` — AND
  semantics, counts on real open, local calendar buckets, rolling `minGap`;
  persisted via a pluggable `OverlayCooldownStorage` (default
  `MemoryCooldownStorage`); `ready()` awaits hydration; injectable `now`. A
  time-based cap (`minGap` / bucket rollover) auto-shows the queued entry the
  moment it expires.

**Lifecycle & data**

* Backend-driven `resolve` (fetch payload only when granted; `null` skips
  without counting cooldown; slot committed while resolving).
* `beforeClose` guard (sync/async; `false` or throw vetoes `close`;
  `remove`/`clear` bypass it).
* `pauseAll`/`resumeAll` full freeze and per-id `pause`/`resume`.
* `update(id, patch)` (shallow-merge + rebuild) and `clearWhere(test)`
  (selective mass removal over `OverlayRecord`s).
* Introspection: `activeIds`, `queuedIds`, `isShowing`, `isPaused`,
  `isAttached`; `OverlayManager` is a `ChangeNotifier`.

**Rendering & orchestration**

* `OverlayManagerScope` — a dedicated `Overlay` layer above your app
  (independent of the `Navigator`), with `of` / `maybeOf` and automatic
  re-attach when the manager is swapped. Or `attach`/`detach` an ambient
  `Overlay` yourself.
* External presenter: `open(present: ...)` with `Present` / `PresentContext` /
  `PresentedOverlay` — one queue over `showDialog` / GetX (dialog + snackbar) /
  `bot_toast` / `fluttertoast`. README has copy-paste recipes and the
  orchestration rules of engagement.

Zero third-party runtime dependencies.
