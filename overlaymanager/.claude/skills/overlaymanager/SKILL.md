---
name: overlaymanager
description: >-
  Work on overlaymanager — the Flutter-native overlay QUEUE manager (serial one-at-a-time
  slots, priority/replace/affix/overlap, conditions + cooldown, resolve, beforeClose,
  pause, Future<T?> results, two-phase close) that renders real OverlayEntrys AND can
  orchestrate external overlay systems (showDialog / GetX / bot_toast) through the
  Present/PresentedOverlay adapter. Read BEFORE modifying lib/src/, the tests, or the
  example. Covers the engine architecture, the non-obvious invariants tests depend on,
  the external-presenter rules of engagement, and the verify workflow (unit + real-device
  Windows integration). Triggers on: overlay, dialog queue, OverlayManager, OverlayManagerScope,
  replace, affix, overlap, cooldown, setContext, dismissWhenUnmet, resolve, beforeClose,
  PresentedOverlay, Get.dialog, Get.snackbar, bot_toast, barrier, pauseAll.
---

# overlaymanager (dart-labs)

`D:/workspaces/dart-labs/overlaymanager` — a **Flutter-native overlay queue manager**,
the Flutter sibling of the headless TS package `@codejoo/overlaymanager`
(`D:/workspaces/codejoo/apps/overlay-manager`). Same orchestration semantics; different
philosophy: **it embraces Flutter** — inserts real `OverlayEntry`s into an attached
`OverlayState` (via `OverlayManagerScope`'s own `Overlay` layer, independent of the
Navigator), and `open<T>()` returns `Future<T?>` like `showDialog`.

Engine is one file: `lib/src/overlay_manager.dart` (~1100 lines). `lib/src/overlay_manager_scope.dart`
is the host widget (`of`/`maybeOf`, post-frame `attach`). Tests: `test/overlaymanager_test.dart`
(70 widget tests). Example app + real-device integration: `example/` (16 tests on Windows).

> **The public show method is `open<T>()`** (renamed from `show` at 0.0.1 — `show` no longer
> exists). Published to pub.dev as **`layerman`** (pub.dev rejected `overlaymanager` as too
> similar to the existing `overlay_manager`), versioned from **0.0.1** (MIT). The barrel file
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
flutter test                                      # 70 widget tests — the unit gate

cd example
flutter test integration_test/orchestration_test.dart -d windows   # 16 tests, REAL window
flutter run -d windows                            # interactive demo (~24 buttons + state line)
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
  insert OverlayEntries during build → `markNeedsBuild during build`. The demo's
  `PromoPage` defers via `addPostFrameCallback` (conditions ride REAL navigation: page
  enter pushes route '/promo', leave restores '/home').
- The demo supports **in-app restart** (`btn-restart` → `_AppRootState.restart()`:
  `setState` disposes `om`, builds a fresh one, bumps a generation key so `HomePage`
  remounts). Do NOT re-`runApp` for restart — a second `GetMaterialApp`/`BotToastInit`
  is init-once and silently no-ops (that was the "重启没反应" bug). The Scope re-attaches
  to the new manager via `didUpdateWidget`. `om` is a mutable global; async callbacks
  guard with `identical(m, om)` before touching it.

When changing behavior: add/adjust a unit test AND (if observable) an integration test,
run both gates, update README + CHANGELOG, bump pubspec version.
