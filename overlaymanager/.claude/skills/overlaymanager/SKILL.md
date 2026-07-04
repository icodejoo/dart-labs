---
name: overlaymanager
description: >-
  Work on overlaymanager — the Flutter-native overlay QUEUE manager (serial one-at-a-time
  slots, priority/replace/affix/overlap, conditions + cooldown, resolve, beforeClose,
  pause, Future<T?> results, two-phase close) that renders real OverlayEntrys AND can
  orchestrate external overlay systems (showDialog / GetX / bot_toast) through the
  Present/PresentedOverlay adapter, plus auto route-awareness via OverlayNavigatorObserver
  and pauseOnRoutes "no-overlay zones". Read BEFORE modifying lib/src/, the tests, or the
  example. Covers the engine architecture, the non-obvious invariants tests depend on,
  the external-presenter rules of engagement, and the verify workflow (unit + real-device
  Windows integration). Triggers on: overlay, dialog queue, OverlayManager, OverlayManagerScope,
  replace, affix, overlap, cooldown, setContext, dismissWhenUnmet, resolve, beforeClose,
  PresentedOverlay, Get.dialog, Get.snackbar, bot_toast, barrier, pauseAll, pauseOnRoutes,
  OverlayNavigatorObserver, currentRoute, deep link, route guard.
---

# overlaymanager (dart-labs)

`D:/workspaces/dart-labs/overlaymanager` — a **Flutter-native overlay queue manager**,
the Flutter sibling of the headless TS package `@codejoo/overlaymanager`
(`D:/workspaces/codejoo/apps/overlay-manager`). Same orchestration semantics; different
philosophy: **it embraces Flutter** — inserts real `OverlayEntry`s into an attached
`OverlayState` (via `OverlayManagerScope`'s own `Overlay` layer, independent of the
Navigator), and `open<T>()` returns `Future<T?>` like `showDialog`.

Engine is one file: `lib/src/overlay_manager.dart` (~1150 lines). `lib/src/overlay_manager_scope.dart`
is the host widget (`of`/`maybeOf`, post-frame `attach`). `lib/src/overlay_navigator_observer.dart`
is the auto route-awareness `NavigatorObserver`. Tests: `test/overlaymanager_test.dart`
(79 widget tests). Example app + real-device integration: `example/` (17 tests on Windows).

> **The public show method is `open<T>()`** (renamed from `show` at 0.0.1 — `show` no longer
> exists). Published to pub.dev as **`layerman`** (pub.dev rejected `overlaymanager` as too
> similar to the existing `overlay_manager`), versioned from **0.1.0** (MIT). The barrel file
> is `lib/layerman.dart` (renamed to match); the repo folder/skill name stay `overlaymanager` —
> only the pub.dev package identity changed.

## Architecture map (lib/src/overlay_manager.dart)

- **`_Slot`** per named slot: `active` (0..1 occupant: resolving/open/closing), `queue`,
  gap/delay timers, `gapPending`. `_overlaps` = concurrent stack; `_pendingOverlaps` = held
  while paused; `_byId` = single source of truth.
- **Ordering `_cmp`**: replace front-band FIRST, then priority desc, then FIFO `seq`.
- **Eligibility** = `_conditionsPass` (`when` sole authority; else `route`(String|List|RegExp)
  AND `requiresAuth` against `_context` set by `setContext`) + `_cooldownPass`.
- **`_schedule(slot)`**: paused → return; slot occupied/gapPending/empty → return; pick first
  ELIGIBLE from sorted queue (ineligible entries WAIT); builtin front needs `_overlay`
  attached, external does not; honor `delay` unless `skipGap`; `_activate`.
- **`_activate`**: occupies slot; `resolveData != null` → phase `resolving` (committed; later
  arrivals can't preempt), `null` result skips WITHOUT counting cooldown; else `_open` →
  count cooldown, `_insert` (builtin: OverlayEntry with ValueListenableBuilder + optional
  barrier Stack) or `presentExternal()` (external), start duration.
- **Two-phase close**: `close` → `beforeClose` guard (false/throw cancels; async awaited) →
  `_doClose` → phase `closing` + settle → builtin: `exitDuration` timer → `_remove`;
  external: call `externalDismiss`, its `dismissed` signal drives `_onExternalDismissed`
  (+`exitDuration` as post-dismiss grace). `_remove` advances (gap-aware) only when it freed
  a serial slot.
- **External presenter**: `open(present: (ctx) => PresentedOverlay(dismissed:, dismiss:))` —
  `dismissed` completes on ANY close path and becomes the result; `dismiss` is the targeted
  orchestrator close. `externalDone` guards re-entry; `_dismissBackendBestEffort` fires on
  replace/clear/remove of a still-showing external entry.
- **CooldownStore**: hydrate-once (`await manager.ready()`), sync reads, fire-and-forget
  write-through to pluggable `OverlayCooldownStorage` (default memory; README shows a
  shared_preferences adapter). Local calendar buckets for day/hour/minute; rolling `minGap`;
  `session` in memory. Injectable `now` for tests.
- **pause**: `pauseAll` = FULL freeze (no activation, replace won't displace, overlaps held
  in `_pendingOverlaps`, durations frozen with remaining time via `now`); `resumeAll`
  releases + re-schedules. `pause(id)/resume(id)` freeze one duration countdown.
  Internally `pauseAll`/`resumeAll` only flip `_manualPaused`; the effective `_paused` getter
  is `_manualPaused || _routeZonePaused`, and `_applyFreeze`/`_applyRelease` (extracted bodies)
  are shared with `_updateRouteZone` (see below) — neither side undoes the other.
- **`pauseOnRoutes`** (constructor param, `String`/`List<String>`/`RegExp` patterns): a
  "no-overlay zone". `setContext` calls `_updateRouteZone()` on every invocation, which
  matches `_context['route']` against the patterns and flips `_routeZonePaused`, calling
  `_applyFreeze`/`_applyRelease` only when the EFFECTIVE `_paused` actually changes.
- **`OverlayNavigatorObserver`** (`overlay_navigator_observer.dart`): a `NavigatorObserver`
  that maps `didPush`/`didPop`/`didRemove`/`didReplace` to `manager.setContext({'route': path})`
  (path via `route.settings.name`, overridable with `pathOf`). Router-agnostic — GetX/
  go_router/vanilla Navigator all surface the same `NavigatorObserver` API underneath.
  Deferred to `WidgetsBinding.instance.addPostFrameCallback` (some routers trigger
  didPush mid-build; `setContext` mutating the Overlay tree then would throw) — **and it
  explicitly calls `WidgetsBinding.instance.scheduleFrame()` right after registering**, not
  just `addPostFrameCallback` alone. Without that explicit `scheduleFrame()`, a postFrameCallback
  registered when nothing else is dirty can sit forever unflushed — caught by a `flutter test`
  unit test (bare `pump()`/`pumpAndSettle()` under `AutomatedTestWidgetsFlutterBinding` do NOT
  force a frame when nothing is scheduled; a real device's `IntegrationTestWidgetsFlutterBinding`
  usually masks this since navigation transition animations schedule frames on their own).
- **`OverlayManager.currentRoute`** — reads `_context['route']` back; lets a host avoid
  keeping its own separate route mirror (the demo used to keep `routeLabel`, now gone).

## Non-obvious invariants — do NOT break

1. **Replace front band** in `_cmp` (real bug caught on-device: a preemptor must outrank
   earlier-queued normal entries). **Replace also skips a pending gap** (cancels gapTimer).
   **A displaced BUILTIN entry goes BACK to the queue (`_displace`), not dropped** (the old
   `_discardActive`-for-both was the bug behind "replace后旧弹窗不回来"): result stays pending,
   keeps id/data, re-shows once the replacer closes. Code-review hardening (all tested):
     - **Only `phase==open` is displaced.** A `resolving` cur is `_discardActive`d — displacing
       it would double-run the in-flight resolver and could open with stale data.
     - **`wasDisplaced` is one flag doing three jobs** (cleanup pass collapsed a separate
       `exemptNextCooldown` into it — they were always set/reset at the exact same two sites, so
       keeping them apart was pure duplication): (a) `_cooldownPass`/`_armCooldownWake` bypass the
       cooldown gate entirely (not just `record`) — else a `session:1`/`total:1` displaced entry
       is never re-eligible and its future hangs forever; (b) lets a held handle's `close()` take
       effect on a displaced (pending) entry (settle+remove) instead of being dropped and silently
       re-showing — a normal never-shown queued entry's `close()` is still a no-op; (c) `_open`
       resets it, ending both behaviors once the entry is actually shown again.
     - **`replaceBand` (mutable, init `=replace`) drives `_cmp`, not `replace`.** `_displace`
       sets it false so a resumer can't out-band the replacer that displaced it (two
       `replace:true` would otherwise invert by seq).
     - `_close` runs `beforeClose` for the displaced-pending path too (2nd round of review caught
       it bypassing the guard entirely) via a shared `_closable(e)`/`_finishClose(e, result)` pair
       instead of a per-call `proceed()` closure; the async-guard continuation re-checks
       `_closable(e)` at resolution time so an already-approved close still lands even if a
       replace displaced the entry mid-guard.
     - **`resolved` flag stops a resumed `resolve`-backed entry from re-fetching** — `_activate`
       only calls the resolver when `!e.resolved`; a resumed entry reopens with its previously
       fetched `data` (2nd round: re-fetching on every resume risked a duplicate side effect and
       could silently discard an already-shown overlay if the 2nd fetch returned null).
     - **`_displace` freezes duration (`_freezeDuration`)**; `_startDuration` resumes
       `durationRemaining ?? duration`, so a re-show gets the REMAINING time, not a fresh window.
   Same-id reopen and external/closing actives are still `_discardActive`d. `clear()` cancels
   `slot.cooldownTimer` (like `pauseAll`/`dispose`).
2. **Replace only displaces when the replacer is itself eligible** (TS 5b) and the manager
   is not paused; an `affix`ed current blocks displacement (replacer keeps band ordering).
   Duplicate-id self-update (`open` with an active id) is NOT blocked by affix.
3. **Ineligible queued entries WAIT; ineligible `overlap` is DROPPED** (now-or-never,
   result null). **A TIME-based cooldown (`minGap` + day/hour/minute rollover) DOES self-wake**:
   when `_schedule` finds nothing eligible it arms `slot.cooldownTimer` for the soonest
   `_cooldowns.timeUntilEligible` (so a queued card can't hang forever — that was the
   "minGap 进队列但永不弹" bug). `session`/`total` never auto-clear ⇒ no wake; they still
   re-qualify only on a scheduling trigger (show/close/`setContext`). Cancel/re-arm the
   timer at the top of every `_schedule`; also cancel it in `pauseAll`/`dispose`.
4. **`_CooldownStore._flush` must call `storage.write` DIRECTLY** — wrapping in
   `Future(...)` leaves a pending Timer that explodes flutter_test's fake async.
5. **`beforeClose` gates only `close()`** — `remove`/`clear`/auto-dismiss bypass it.
6. **External entries**: never require `attach`; `exitDuration` means post-dismissed grace
   (route futures complete when the exit animation STARTS); `externalDone` must be set
   before best-effort dismiss so the late `dismissed` signal can't re-drive removal.
7. **`resolve` is committed once resolving** (slot held); `null` skip does not count
   cooldown; `_onResolved` guards `_byId[id] == e && phase == resolving`.
8. **`update(id, patch)`** shallow-merges Map-into-Map (else replaces) and must call
   `overlayEntry?.markNeedsBuild()` — builders read `handle.data` at build time.
9. **No `stackIndex/isTopmost`** (deliberate TS difference): self-rendering means z-order IS
   Overlay insertion order. No cross-isolate cooldown sync (share a storage backend).
10. **`OverlayNavigatorObserver` must `scheduleFrame()` after `addPostFrameCallback`** — do not
    "simplify" this away. Registering the callback alone is not enough; without an explicit
    frame request, navigation that happens to coincide with an otherwise-idle frame can leave
    the route update pending indefinitely (real risk in production, not just a test artifact —
    found via a `flutter test` unit test failing while the real-device integration test passed).
11. **`pauseOnRoutes`/manual `pauseAll` compose via OR, never overwrite each other** — leaving a
    route zone while manually paused must NOT call `_applyRelease`; a manual `resumeAll` while
    still inside a zone must NOT call it either. Always check the effective `_paused` (both
    before AND after flipping the specific flag) before calling `_applyFreeze`/`_applyRelease`.

## Considered and deferred: `WidgetsBindingObserver` for OS-level deep links

`OverlayNavigatorObserver` only sees IN-APP `Navigator` state changes (any trigger — vanilla,
GetX, go_router — but only once Flutter's own Navigator has already processed the change).
`WidgetsBindingObserver` gives two DIFFERENT, narrower hooks that are genuine pre-navigation
interception points, evaluated during this feature's brainstorm and NOT built (out of scope
for this round, not a technical dead end — pick this up if "real OS deep link" support is
ever requested):
- **`didPushRouteInformation`** (née `didPushRoute`) — fires when the OS/platform hands Flutter
  a route request (URL scheme / universal link cold- or warm-starting the app, or a Flutter Web
  address-bar change) BEFORE Flutter's own router processes it. You can inspect the target path
  and choose not to forward it — genuine veto, but ONLY for platform-originated requests; a
  button calling `Navigator.push`/`Get.to`/`context.go` from already-running app code never goes
  through this path at all.
- **`didPopRoute`** — fires on a SYSTEM-triggered pop request (Android hardware back / predictive
  back gesture); returning `true` vetoes the default pop. Only for system-triggered pops, not
  `Navigator.pop()` called from app code.
Neither hook solves "intercept arbitrary in-app navigation, regardless of trigger, without
changing call sites" — that combination remains structurally impossible in Flutter (confirmed
independently via this reasoning and via the `OverlayNavigatorObserver` design work above).

## External backends — rules of engagement (issue-history-proven)

1. Manager owns the truth — never poll `Get.isDialogOpen`/`isSnackbarOpen`.
2. Close only via the overlay's OWN handle: unique `RouteSettings(name: 'om://$id')` +
   `Get.until((rt) => rt.settings.name != name)` for route dialogs; `SnackbarController.close()`;
   bot_toast `CancelFunc`. NEVER bare `Get.back()`/pop-top (snackbar steals it).
3. Disarm backend orchestration: bot_toast `onlyOne: false` + dedicated groupKey + `onClose`
   as the single completion signal; GetX's internal snackbar queue is bypassed by our
   serialization; never `Get.closeAllSnackbars()` (hangs queued futures).
4. The manager unifies SEQUENCING, not z-order (bot_toast is a Stack ABOVE the Navigator,
   always on top); back-button stays with each backend. README has the three recipes.

## Verify workflow

```bash
cd D:/workspaces/dart-labs/overlaymanager
flutter analyze                                   # must be clean
flutter test                                      # 79 widget tests — the unit gate

cd example
flutter test integration_test/orchestration_test.dart -d windows   # 17 tests, REAL window
flutter run -d windows                            # interactive demo (25 buttons + state line)
```

Integration-test gotchas (learned the hard way):
- Tests share ONE app process: `setUp` does `om.resumeAll(); om.clear();`. Session cooldown
  counters live in the MANAGER and persist across tests — a later test must not assume a
  fresh counter (the restart test exhausts-if-needed before asserting the reset).
- `pumpAndSettle` rides GetSnackBar's whole entrance→auto-close→exit lifecycle (duration
  timer arms at INSERT) — pump fixed real durations to catch the visible plateau.
- Overlap/replace/affix assertions use 2+ overlays driven from buttons INSIDE overlays
  (in-card `_card(actions: ...)`); barrier(mask)-close via `tapAt` far from the card.
- After a queue advance: `pump(700ms)` (exit 200 + gap 300) then `pumpAndSettle`.
- **Never call `setContext` from `initState`/`dispose` directly** — it notifies and may
  insert OverlayEntries during build → `markNeedsBuild during build`. The demo no longer
  needs this workaround at all: `PromoPage`/`NoOverlayZonePage` are plain `StatelessWidget`s
  with zero lifecycle code — `OverlayNavigatorObserver` (wired into `navigatorObservers` in
  `AppRoot`) feeds route context automatically, deferred safely inside the observer itself.
- **Testing `OverlayNavigatorObserver` (or anything relying on its deferred update) in a plain
  `flutter test` widget test**: `pumpAndSettle()`/bare `pump()` DO flush it correctly — but
  only because the observer calls `scheduleFrame()` itself (invariant #10 above). If you ever
  call `manager.setContext(...)` from your OWN deferred callback without a matching
  `scheduleFrame()`, the exact same class of unit test will hang silently on `pump()`/
  `pumpAndSettle()` with no exception, just a `findsNothing` where you expected `findsOneWidget`.
- The demo supports **in-app restart** (`btn-restart` → `_AppRootState.restart()`:
  `setState` disposes `om`, builds a fresh one, bumps a generation key so `HomePage`
  remounts). Do NOT re-`runApp` for restart — a second `GetMaterialApp`/`BotToastInit`
  is init-once and silently no-ops (that was the "重启没反应" bug). The Scope re-attaches
  to the new manager via `didUpdateWidget`. `om` is a mutable global; async callbacks
  guard with `identical(m, om)` before touching it.
- **A HomePage button is unreachable once a pushed page covers it** (`btn-goto-zone`
  pushes `NoOverlayZonePage`, which covers `HomePage` — `btn-queue-in-zone` lives on
  `HomePage`). To exercise "queue something while on `/zone`" from an integration test,
  call `app.om.open(...)`/`app.om.close(...)` directly rather than trying to tap a button
  that's no longer in the tree — same trick as the earlier tests that read `app.om.*`
  state directly instead of only driving the UI.

When changing behavior: add/adjust a unit test AND (if observable) an integration test,
run both gates, update README + CHANGELOG, bump pubspec version.
