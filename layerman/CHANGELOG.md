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
