---
name: layerman
description: >-
  Work on layerman — the headless Flutter overlay QUEUE orchestrator (serial one-at-a-time
  slots, priority/replace/affix/overlap, conditions + cooldown, resolve, beforeClose,
  pause, Future<T?> results, two-phase close) that renders NOTHING itself and instead
  schedules overlays rendered through a caller-supplied `present:` backend (showDialog /
  GetX / bot_toast / a self-managed OverlayEntry) via the Present/PresentedOverlay adapter,
  plus auto route-awareness via LayermanNavigatorObserver and pauseOnRoutes "no-overlay
  zones". Read BEFORE modifying lib/src/, the tests, or the example. Covers the engine
  architecture, the non-obvious invariants tests depend on, the present-backend rules of
  engagement, and the verify workflow (unit + real-device Windows integration). Triggers
  on: overlay, dialog queue, Layerman, present, PresentedOverlay, replace, affix,
  overlap, cooldown, setContext, dismissWhenUnmet, resolve, beforeClose, Get.dialog,
  Get.snackbar, bot_toast, pauseAll, pauseOnRoutes, LayermanNavigatorObserver, currentRoute,
  deep link, route guard.
---

# layerman (dart-labs)

`D:/workspaces/dart-labs/layerman` — a **headless Flutter overlay queue orchestrator**,
the Flutter sibling of the headless TS package `@codejoo/overlaymanager`
(`D:/workspaces/codejoo/apps/overlay-manager`). Same orchestration semantics, and since
0.2.0 the same philosophy too: the manager decides *when*/*which* overlay shows but
**renders nothing itself** — every overlay goes through a caller-supplied `present:`
backend (`showDialog`, GetX, `bot_toast`, a self-managed `OverlayEntry`, …), and
`open<T>()` returns `Future<T?>` like `showDialog`. The core imports no
`package:flutter/widgets.dart` and owns no `Overlay` layer.

> **0.2.0 breaking change**: the earlier `builder:` render path, `OverlayHandle`,
> `OverlayPhase`, `OverlayManagerScope` and `attach`/`detach`/`isAttached` are all gone —
> `present:` is the sole rendering hook now. See the README's "Why there is no `builder:`"
> section and the CHANGELOG for the full list and migration recipe. Don't reintroduce any
> of these; that's the whole point of the refactor.

Engine is one file: `lib/src/overlay_manager.dart` (~1250 lines) — no more
`overlay_manager_scope.dart` (deleted with `OverlayManagerScope`). `lib/src/overlay_navigator_observer.dart`
is the auto route-awareness `NavigatorObserver` (unaffected by the headless refactor — it
only feeds `route` into `setContext`, never renders). Tests: `test/layerman_test.dart`.
Example app + real-device integration: `example/`.

> **The public show method is `open<T>()`** (renamed from `show` at 0.0.1 — `show` no longer
> exists). Published to pub.dev as **`layerman`** (pub.dev rejected `overlaymanager` as too
> similar to the existing `overlay_manager`), versioned from **0.1.0** (MIT). The barrel file
> is `lib/layerman.dart`. The repo folder and skill are now `layerman` too (renamed
> 2026-07-05 to match the pub.dev identity).

## Architecture map (lib/src/overlay_manager.dart)

- **`_Slot`** per named slot: `active` (0..1 occupant: resolving/open/closing), `queue`,
  gap/delay/cooldown timers, `gapPending`. `_overlaps` = concurrent stack; `_pendingOverlaps`
  = held while paused; `_byId` = single source of truth.
- **Ordering `_cmp`**: `entry.replace` (an immutable per-entry field) front-bands FIRST, then
  priority desc, then FIFO `seq` — needed so a replacer that got queued (blocked by an
  `affix`ed current) still shows ahead of already-waiting normal entries.
- **Eligibility** = `_conditionsPass` (`when` sole authority; else `route`(String|List|RegExp)
  AND `requiresAuth` against `_context` set by `setContext`) + `_cooldownPass`.
- **`_schedule(slot)`**: paused → return; slot occupied/`gapPending`/a `delayTimer` pending/
  queue empty → return; pick the first ELIGIBLE entry from the sorted queue (ineligible
  entries WAIT — `_armCooldownWake` arms a wake-up timer if the only thing blocking is a
  time-based cooldown); honor the entry's `delay` unless `skipGap`; `_activate`.
- **`_activate`**: occupies the slot; `resolveData != null` → phase `resolving` (committed —
  later arrivals can't preempt while resolving), `null` result skips WITHOUT counting
  cooldown (`_onResolved`); otherwise `_open` → records cooldown, calls
  `entry.presentBackend()` (invokes the caller's `present:` exactly once and wires
  `externalDismiss` to the returned `PresentedOverlay.dismiss`), starts the `duration` timer.
  There is no other rendering path — `presentBackend` is the only way an overlay ever
  becomes visible.
- **Two-phase close**: `close` → `beforeClose` guard (false/throw cancels; an async guard's
  continuation re-checks `_closable`/`_isCurrent` at resolution time, since the entry may
  have been removed while it was pending) → `_doClose` → phase `closing` + settle the result
  → calls `entry.externalDismiss(result)` (skipped if the backend already reported done) →
  its `dismissed` future firing drives `_onExternalDismissed`, which applies the optional
  `exitDuration` grace before `_remove`. `_remove` advances the slot (gap-aware) only when it
  freed a serial `active` occupant.
- **`present:` backend** (the sole rendering hook — see the README's "Why there is no
  `builder:`" section for the rationale): `open(present: (ctx) => PresentedOverlay(dismissed:,
  dismiss:))` — `dismissed` completes on ANY close path and becomes the result; `dismiss` is
  the targeted orchestrator-driven close. `externalDone` guards re-entry (a late `dismissed`
  signal after we already force-closed must not re-drive removal); `_dismissBackendBestEffort`
  fires on replace/clear/remove of a still-showing entry.
- **CooldownStore**: hydrate-once (`await manager.ready()`), sync reads, fire-and-forget
  write-through to pluggable `OverlayCooldownStorage` (default memory; README shows a
  shared_preferences adapter). Local calendar buckets for day/hour/minute; rolling `minGap`;
  `session` in memory. Injectable `now` for tests.
- **pause**: `pauseAll` = FULL freeze (no activation, `replace` won't discard the current
  occupant, overlaps held in `_pendingOverlaps`, durations frozen with remaining time via
  `now`); `resumeAll` releases + re-schedules. `pause(id)/resume(id)` freeze one duration
  countdown. Internally `pauseAll`/`resumeAll` only flip `_manualPaused`; the effective
  `_paused` getter is `_manualPaused || _routeZonePaused`, and `_applyFreeze`/`_applyRelease`
  (extracted bodies) are shared with `_updateRouteZone` (see below) — neither side undoes the
  other.
- **`pauseOnRoutes`** (constructor param, `String`/`List<String>`/`RegExp` patterns): a
  "no-overlay zone". `setContext` calls `_updateRouteZone()` on every invocation, which
  matches `_context['route']` against the patterns and flips `_routeZonePaused`, calling
  `_applyFreeze`/`_applyRelease` only when the EFFECTIVE `_paused` actually changes.
- **`LayermanNavigatorObserver`** (`overlay_navigator_observer.dart`): a `NavigatorObserver`
  that overrides ONLY `didChangeTop` (NOT the legacy `didPush`/`didPop`/`didRemove`/`didReplace`
  quartet — code review round 2 found `didRemove`/`didReplace` report the route AT THE POSITION
  THAT CHANGED, not necessarily the topmost/displayed one, if the change targeted a route buried
  in history; `didChangeTop` is the hook Flutter documents as always giving the true current top,
  and it also covers cold start and declarative `Navigator(pages:)` rebuilds — go_router's model —
  that don't map cleanly onto the legacy four at all). Maps `topRoute` to
  `manager.setContext({'route': path})` (path via `route.settings.name`, overridable with
  `pathOf`). Router-agnostic — GetX/go_router/vanilla Navigator all surface the same
  `NavigatorObserver` API underneath. Deferred to `WidgetsBinding.instance.addPostFrameCallback`
  (some routers trigger this mid-build; `setContext` mutating the Overlay tree then would throw)
  — **and it explicitly calls `WidgetsBinding.instance.scheduleFrame()` right after registering**,
  not just `addPostFrameCallback` alone. Without that explicit `scheduleFrame()`, a postFrameCallback
  registered when nothing else is dirty can sit forever unflushed — caught by a `flutter test`
  unit test (bare `pump()`/`pumpAndSettle()` under `AutomatedTestWidgetsFlutterBinding` do NOT
  force a frame when nothing is scheduled; a real device's `IntegrationTestWidgetsFlutterBinding`
  usually masks this since navigation transition animations schedule frames on their own).
  Guarded by `manager.isDisposed` both before scheduling and inside the deferred callback (an
  app-level restart that disposes+swaps the manager between a nav event and the next frame must
  not call `notifyListeners()` on a disposed `ChangeNotifier`). A throwing `pathOf` is caught and
  reported via `FlutterError.reportError` — never propagates out of the observer callback, and
  the route is treated as unresolvable (`null`) rather than left stale.
- **`Layerman.currentRoute`** — reads `_context['route']` back; lets a host avoid
  keeping its own separate route mirror (the demo used to keep `routeLabel`, now gone).

## Non-obvious invariants — do NOT break

1. **Replace front band** in `_cmp` (real bug caught on-device pre-0.2.0: a preemptor must
   outrank earlier-queued normal entries) — `entry.replace` is immutable and read directly by
   `_cmp`, nothing mutates it post-construction. **Replace also skips a pending gap/delay**
   (cancels `gapTimer`/`delayTimer`). **Since 0.2.0, replace ALWAYS discards the preempted
   entry via `_discardActive`** — settles its result `null`, best-effort `dismiss`es its
   backend, detaches it from `slot.active` — it is **never** re-queued or resumed. This
   deliberately dropped the pre-0.2.0 "displace + resume" machinery (`_displace`,
   `wasDisplaced`, `replaceBand`, the `resolved`-flag-for-resumed-entries dance): once
   rendering moved to a caller-supplied `present:` backend, a dismissed backend can no longer
   be faithfully re-presented (that would re-run its side effects), so "send it back to the
   queue and re-show later" stopped being a sound semantics — see the CHANGELOG's 0.2.0 entry
   and the README's replace description. Same-id reopen and closing actives are still
   `_discardActive`d. `clear()` cancels `slot.cooldownTimer` (like `pauseAll`/`dispose`).
2. **Replace only preempts when the replacer is itself eligible** (TS 5b) and the manager
   is not paused; an `affix`ed current blocks preemption (the replacer keeps its front-band
   ordering and shows next once the slot frees up). Duplicate-id self-update (`open` with an
   active id) is NOT blocked by affix.
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
6. **Every entry is presented through `present:`** — there is no manager-level wiring step
   (no `attach`/`detach`, no `OverlayState`) to forget. `exitDuration` means post-dismissed
   grace (route futures complete when the exit animation STARTS, not when it finishes);
   `externalDone` must be set before best-effort dismiss so a late `dismissed` signal can't
   re-drive removal.
7. **`resolve` is committed once resolving** (slot held); `null` skip does not count
   cooldown; `_onResolved` guards `_byId[id] == e && phase == resolving`.
8. **`update(id, patch)`** shallow-merges Map-into-Map (else replaces) via `setData`, then
   calls `notifyListeners()` — that's it. The manager owns no widgets, so it cannot
   `markNeedsBuild` anything itself; a `present:` backend that wants to reflect the new
   `data` must rebuild off that notification (or read `ctx.data` next time it builds).
9. **No `stackIndex/isTopmost`** (deliberate TS difference, unchanged by the headless
   refactor): layer/z-order is entirely up to whichever `present:` backend renders the
   overlay — the queue itself tracks and exposes none of it. No cross-isolate cooldown sync
   (share a storage backend).
10. **`LayermanNavigatorObserver` must `scheduleFrame()` after `addPostFrameCallback`** — do not
    "simplify" this away. Registering the callback alone is not enough; without an explicit
    frame request, navigation that happens to coincide with an otherwise-idle frame can leave
    the route update pending indefinitely (real risk in production, not just a test artifact —
    found via a `flutter test` unit test failing while the real-device integration test passed).
11. **`pauseOnRoutes`/manual `pauseAll` compose via OR, never overwrite each other** — leaving a
    route zone while manually paused must NOT call `_applyRelease`; a manual `resumeAll` while
    still inside a zone must NOT call it either. Always check the effective `_paused` (both
    before AND after flipping the specific flag) before calling `_applyFreeze`/`_applyRelease`
    (extracted into the shared `_applyPauseTransition(before)` helper — 3 independent code-review
    agents converged on the same duplication, worth trusting that signal).
12. **`LayermanNavigatorObserver` overrides `didChangeTop`, NOT the legacy quartet** — do not add
    back `didPush`/`didPop`/`didRemove`/`didReplace` overrides "for completeness"; `didRemove`/
    `didReplace` report the route at the position that changed, which can be buried under a
    still-topmost different route, corrupting `route` context. `didChangeTop` is Flutter's own
    documented "always the true current top" signal and is a strict superset for this purpose
    (verified empirically: fires on cold start with `previousTopRoute == null`, and on every
    push/pop). Existing unit tests call `observer.didChangeTop(...)` directly, not the legacy
    methods — if you see a test calling `.didPush(...)` on this class, it's stale, fix the test.
13. **`LayermanNavigatorObserver` must check `manager.isDisposed`** both before scheduling the
    post-frame callback AND inside it — a manager can be disposed (app-level restart swapping
    managers) between a navigation event firing and the deferred callback running; without the
    guard, `setContext`'s `notifyListeners()` throws on a disposed `ChangeNotifier`.
14. **A throwing `pathOf` must be caught, not left to propagate** — it runs synchronously inside
    the `NavigatorObserver` callback (before the defer), and an uncaught throw there propagates
    straight out through Flutter's Navigator internals. Report via `FlutterError.reportError`
    and treat the route as unresolvable (`null`), same as an anonymous route.
15. **`MaterialApp.home`'s implicit route is named `'/'`** (Flutter's own
    `Navigator.defaultRouteName`), never `null` and never `'/home'` — confirmed empirically with
    a throwaway `flutter_test`. The demo used to silently rely on the wrong assumption (manual
    `setContext({'route': '/home'})` got clobbered to `'/'` on the very first frame once the
    observer was wired in); fixed by giving the demo's home page a real name via
    `initialRoute`/`routes` instead of `home:`. Document this for consumers, don't try to paper
    over it in the engine — it's correct Flutter behavior, not a bug to "fix" generically.
16. **A route-backed dialog (the `showDialog`/`Get.dialog` external-presenter recipe) pushed on
    the SAME `Navigator` the observer watches genuinely IS the topmost route while shown** — its
    synthetic `RouteSettings(name: 'om://$id')` will show up in `route` for that window. This is
    correct per Flutter's own model, not a bug; don't add filtering logic to hide it (that would
    silently break an app that legitimately wants to gate on dialog routes) — document it instead.

## Considered and deferred: `WidgetsBindingObserver` for OS-level deep links

`LayermanNavigatorObserver` only sees IN-APP `Navigator` state changes (any trigger — vanilla,
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
independently via this reasoning and via the `LayermanNavigatorObserver` design work above).

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
cd D:/workspaces/dart-labs/layerman
flutter analyze                                   # must be clean
flutter test                                      # 72 widget tests — the unit gate

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
- **Never call `setContext` from `initState`/`dispose` directly** — it notifies listeners
  (and may synchronously trigger a `present:` backend's own dismiss) during build →
  `markNeedsBuild during build`. The demo no longer
  needs this workaround at all: `PromoPage`/`NoOverlayZonePage` are plain `StatelessWidget`s
  with zero lifecycle code — `LayermanNavigatorObserver` (wired into `navigatorObservers` in
  `AppRoot`) feeds route context automatically, deferred safely inside the observer itself.
- **Testing `LayermanNavigatorObserver` (or anything relying on its deferred update) in a plain
  `flutter test` widget test**: `pumpAndSettle()`/bare `pump()` DO flush it correctly — but
  only because the observer calls `scheduleFrame()` itself (invariant #10 above). If you ever
  call `manager.setContext(...)` from your OWN deferred callback without a matching
  `scheduleFrame()`, the exact same class of unit test will hang silently on `pump()`/
  `pumpAndSettle()` with no exception, just a `findsNothing` where you expected `findsOneWidget`.
- The demo supports **in-app restart** (`btn-restart` → `_AppRootState._doRestart()`:
  `setState` disposes `om`, builds a fresh one, bumps a generation key so `DemoShell`
  remounts via `ValueKey(_gen)`). Do NOT re-`runApp` for restart — a second
  `GetMaterialApp`/`BotToastInit` is init-once and silently no-ops (that was the
  "重启没反应" bug). There's no Scope to re-attach anymore — the manager is headless, so
  restart is just reassigning the mutable global `om` and remounting the subtree that reads
  it; async callbacks guard with `identical(m, om)` before touching it.
- **A HomePage button is unreachable once a pushed page covers it** (`btn-goto-zone`
  pushes `NoOverlayZonePage`, which covers `HomePage` — `btn-queue-in-zone` lives on
  `HomePage`). To exercise "queue something while on `/zone`" from an integration test,
  call `app.om.open(...)`/`app.om.close(...)` directly rather than trying to tap a button
  that's no longer in the tree — same trick as the earlier tests that read `app.om.*`
  state directly instead of only driving the UI.

When changing behavior: add/adjust a unit test AND (if observable) an integration test,
run both gates, update README + CHANGELOG, bump pubspec version.
