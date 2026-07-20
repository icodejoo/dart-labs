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
