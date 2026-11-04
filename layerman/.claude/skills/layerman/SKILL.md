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
  engagement, and the verify workflow (unit + Android phone integration). Triggers
  on: overlay, dialog queue, Layerman, present, PresentedOverlay, replace, affix,
  overlap, cooldown, setContext, dismissWhenUnmet, resolve, beforeClose, Get.dialog,
  Get.snackbar, bot_toast, pauseAll, pauseOnRoutes, LayermanNavigatorObserver, currentRoute,
  deep link, route guard.
---

# layerman (dart-labs)

`dart-labs/layerman` — a **headless Flutter overlay queue orchestrator**,
the Flutter sibling of the headless TS package `@codejoo/overlaymanager`
(`D:/workspaces/codejoo/apps/overlay-manager`). Same orchestration semantics, and since
0.2.0 the same philosophy too: the manager decides *when*/*which* overlay shows but
**renders nothing itself** — every overlay goes through a caller-supplied `present:`
backend (`showDialog`, GetX, `bot_toast`, a self-managed `OverlayEntry`, …), and
`open<T>()` returns `Future<T?>` like `showDialog`. The core imports no
`package:flutter/widgets.dart` and owns no `Overlay` layer.

> **0.2.0 breaking change**: the earlier `builder:` render path, `OverlayHandle`,
> the former widget-oriented `OverlayPhase`, `OverlayManagerScope` and the old manager widget attachment methods are gone —
> `present:` is the sole rendering hook now. See the README's "Why there is no `builder:`"
> section and the CHANGELOG for the full list and migration recipe. The separate `LayermanLifecycle.attach`/`detach`/`isAttached` APIs added in 0.3.0
> manage lifecycle observation, not widget attachment. 1.0 introduces a new record-phase `OverlayPhase` enum. Don't reintroduce the old render path; that's the whole point of the refactor.

Engine: `lib/src/overlay_manager.dart`; shared types: `overlay_types.dart`;
route observation: `overlay_navigator_observer.dart`; official presenters:
`route_managers.dart`; app lifecycle: `lifecycle_binding.dart` (all under `lib/src/`).
The core uses foundation and scheduler; adapters own widgets/Material dependencies.
`ARCHITECTURE.md` (§14 limitations, §15 roadmap) is calibrated to 1.0.0.

Test inventory (executed counts, 2026-11-04): 600 tests in total, all green on Flutter 3.47
and on the minimum supported Flutter 3.27.4.

| File under `test/` | Tests | Coverage |
| --- | ---: | --- |
| `layerman_test.dart` | 81 | Core queue and backend contracts |
| `robustness_test.dart` | 15 | Hydration, guards, result validation |
| `readme_recipe_test.dart` | 5 | README Route recipes |
| `engine_v030_test.dart` | 21 | Caps, timeouts, takeover, live data, inspection |
| `engine_v030b_test.dart` | 38 | Tickets, end reasons, events, holds, expiry, slots |
| `engine_v030c_test.dart` | 30 | Build deferral, batching, reclamation, cooldown reset, tags |
| `api_v1_test.dart` | 6 | OverlayMode / RouteMatcher / OverlayPhase |
| `fuzz_invariants_test.dart` | 365 | Randomized sequence invariants and repeated-dismiss regression |
| `observer_filter_test.dart` | 11 | PageRoute filtering, contextKey |
| `route_managers_test.dart` | 22 | Route presenters |
| `lifecycle_binding_test.dart` | 6 | Lifecycle holds |

Unit acceptance total: 600; minimum Flutter 3.27.4 acceptance total: 600.
Phone integration (`example/integration_test/orchestration_test.dart`): 29 tests
(17 original + 12 v0.3/1.0 cases) on the real Huawei STG-AL00 / Android 12, serial `7NQBB23606003715`.
The fuzz file covers 300 random-operation seeds, 60 ordering seeds and the repeated-dismiss regressions.

> **The public show method is `open<T>()`** (renamed from `show` at 0.0.1 — `show` no longer
> exists). Published to pub.dev as **`layerman`** (pub.dev rejected `overlaymanager` as too
> similar to the existing `overlay_manager`), versioned from **0.1.0** (MIT). The barrel file
> is `lib/layerman.dart`. The repo folder and skill are now `layerman` too (renamed
> 2026-07-05 to match the pub.dev identity).

## Architecture map (lib/src/overlay_manager.dart)

- **`_Slot`** per named slot: `active` (0..1 occupant: resolving/open/closing), `queue`,
  gap/delay/cooldown timers, `gapPending`. `_overlaps` = concurrent stack; `_pendingOverlaps`
  = held while paused OR while waiting for cooldown hydration; `_byId` = single source of truth.
- **Ordering `_cmp`**: `entry.replace` (an immutable per-entry field) front-bands FIRST, then
  priority desc, then FIFO `seq` — needed so a replacer that got queued (blocked by an
  `affix`ed current) still shows ahead of already-waiting normal entries.
- **Eligibility** = `_conditionsPass` (`when` sole authority; else `route` (`RouteMatcher`)
  AND `requiresAuth` against `_context` set by `setContext`) + `_cooldownPass`.
- **`_schedule(slot)`**: paused → return; slot occupied/`gapPending`/a `delayTimer` pending/
  queue empty → return; pick the first ELIGIBLE entry from the ordered queue; recoverably ineligible
  entries WAIT, exhausted session/total entries settle as capped — `_armCooldownWake` arms a wake-up timer if the only thing blocking is a
  time-based cooldown); honor the entry's `delay` unless `skipGap`; `_activate`.
- **`_activate`**: occupies the slot; `resolveData != null` → phase `resolving` (committed —
  ordinary arrivals can't preempt while resolving, but a `replace` can and discards it), `null` result skips WITHOUT counting
  cooldown (`_onResolved`); otherwise `_open` → records cooldown, calls
  `entry.presentBackend()` (invokes the caller's `present:` exactly once and wires
  `externalDismiss` to the returned `PresentedOverlay.dismiss`), starts the `duration` timer.
  There is no other rendering path — `presentBackend` is the only way an overlay ever
  becomes visible.
- **Two-phase close**: `close` → `acceptsResult` type check (ArgumentError, no state change) →
  `beforeClose` guard (false/throw cancels; while an async guard is pending `closeGuardPending`
  makes repeated close/dismiss no-ops; its continuation re-checks `_closable`/`_isCurrent` at
  resolution time, since the entry may have been removed while it was pending) → `_doClose` → phase `closing` + settle the result
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
- **CooldownStore**: hydrate-once with GATING — until `hydrated`, `timeUntilEligible` returns
  `null` for persisted caps (total/day/hour/minute/minGap), so such serial entries wait and
  such overlaps are held in `_pendingOverlaps`; the constructor's hydrate continuation then
  re-schedules (via `_applyRelease` when not paused) and only then completes `ready()`.
  Hydrate MERGES into existing records; sync reads; serialized write-through (`_writing` +
  `_dirty`: one write in flight, then the latest snapshot) to pluggable
  `OverlayCooldownStorage` (default memory; README shows a shared_preferences adapter);
  read/write failures are reported via `_reportError`. Local calendar buckets for
  day/hour/minute; rolling `minGap`; `session` in memory (never gated). Counters are keyed by
  id → `cooldown` asserts an explicit `id`. Injectable `now` for tests.
- **pause**: `pauseAll` = FULL freeze (no activation, `replace` won't discard the current
  occupant, overlaps held in `_pendingOverlaps`, durations frozen with remaining time via
  `now`); `resumeAll` releases + re-schedules. `pause(id)/resume(id)` freeze one duration
  countdown. Internally `pauseAll`/`resumeAll` only flip `_manualPaused`; the effective
  `_paused` getter is `_manualPaused || _routeZonePaused || _holds.isNotEmpty`, and `_applyFreeze`/`_applyRelease`
  (extracted bodies) are shared with `_updateRouteZone` (see below) — neither side undoes the
  other.
- **`pauseOnRoutes`** (constructor param, `List<RouteMatcher>`, default empty): a
  "no-overlay zone". `setContext` calls `_updateRouteZone()` on every invocation, which
  matches `_context['route']` against the patterns and flips `_routeZonePaused`, calling
  `_applyFreeze`/`_applyRelease` only when the EFFECTIVE `_paused` actually changes.
- **`LayermanNavigatorObserver`** (`overlay_navigator_observer.dart`): a `NavigatorObserver`
  that defaults to `PageRoute` filtering and overrides ONLY `didChangeTop` (NOT the legacy `didPush`/`didPop`/`didRemove`/`didReplace`
  quartet — code review round 2 found `didRemove`/`didReplace` report the route AT THE POSITION
  THAT CHANGED, not necessarily the topmost/displayed one, if the change targeted a route buried
  in history; `didChangeTop` is the hook Flutter documents as always giving the true current top,
  and it also covers cold start and declarative `Navigator(pages:)` rebuilds — go_router's model —
  that don't map cleanly onto the legacy four at all). Maps `topRoute` to
  `manager.setContext({contextKey: path})` (path via `route.settings.name`, overridable with
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
   "minGap 进队列但永不弹" bug). `session`/`total` never auto-clear ⇒ no wake; scheduling discards exhausted entries
   as capped rather than leaving their futures pending forever (fixed in 0.3.0). Cancel/re-arm the
   timer at the top of every `_schedule`; also cancel it in `pauseAll`/`dispose`.
4. **`_CooldownStore._flush` must call `storage.write` DIRECTLY** — wrapping in
   `Future(...)` leaves a pending Timer that explodes flutter_test's fake async. The 0.2.2
   serialization (`_writing`/`_dirty`, re-flush from the write future's `.then`) uses only
   future continuations (microtasks) — keep it Timer-free, and never write before `hydrated`
   (that was the "whole-map write-back wipes other ids" bug).
5. **`beforeClose` gates only `close()`** — `remove`/`clear`/auto-dismiss/`duration` expiry
   (`_autoClose`) bypass it.
6. **Every entry is presented through `present:`** — there is no manager-level wiring step
   (no `attach`/`detach`, no `OverlayState`) to forget. `exitDuration` means post-dismissed
   grace (`showDialog`/`Navigator.push` futures complete when the exit animation STARTS; the
   README route recipes now use `TransitionRoute.completed`, which completes AFTER it, so
   they need no `exitDuration`);
   `externalDone` must be set before best-effort dismiss so a late `dismissed` signal can't
   re-drive removal.
7. **`resolve` is committed once resolving** (slot held against ordinary arrivals — only a
   `replace` can preempt and discard it; also for `overlap`; a result that
   arrives while paused is parked in `hasHeldData` and opened by `_applyRelease`); `null` skip does not count
   cooldown; `_onResolved` guards `_byId[id] == e && phase == resolving`.
8. **`update(id, patch)`** shallow-merges Map-into-Map, otherwise replaces data;
   notifies the per-entry `dataListenable` and manager listeners. `PresentContext.data`
   remains a snapshot. `OverlayTicket.data` exposes that same live channel.
   The 0.2.2 footgun (backend cannot read updated data) is fixed in 0.3.0.
9. **No `stackIndex/isTopmost`** (deliberate TS difference, unchanged by the headless
   refactor): layer/z-order is entirely up to whichever `present:` backend renders the
   overlay — the queue itself tracks and exposes none of it. No cross-isolate cooldown sync
   (share a storage backend).
10. **`LayermanNavigatorObserver` must `scheduleFrame()` after `addPostFrameCallback`** — do not
    "simplify" this away. Registering the callback alone is not enough; without an explicit
    frame request, navigation that happens to coincide with an otherwise-idle frame can leave
    the route update pending indefinitely (real risk in production, not just a test artifact —
    found via a `flutter test` unit test failing while the real-device integration test passed).
11. **`pauseOnRoutes`/manual `pauseAll`/holds compose via OR, never overwrite each other** — leaving a
    route zone while manually paused must NOT call `_applyRelease`; a manual `resumeAll` while
    still inside a zone must NOT call it either. Always check the effective `_paused` (all sources, both
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
16. **Route-dialog context footguns are FIXED in 0.3.0.** The observer defaults to
    accepting `PageRoute` only; dialogs/sheets/menus preserve the last accepted page.
    This fixes self-dismissal of route-gated dialogs and accidental release of route zones.
    Explicit `routeFilter: (r) => true` restores 0.2.x all-route behavior.
17. **`close()` validates `result` BEFORE any state change** (`acceptsResult` = `r is T?`, built
    in `open<T>()`); a mismatch throws `ArgumentError` and leaves the entry untouched.
    `_settle` sets `settled` then completes; if the typed completion still throws it reports
    and completes with `null` — a set `settled` flag must never leave the future pending.
18. **Hydration gating must not drop or misfire**: `_applyRelease` keeps overlaps that still
    `_waitingForHydrate` in `_pendingOverlaps`; `open(mode: OverlayMode.overlap)` drops immediately only when
    CONDITIONS fail (or the cooldown fails after hydration); the hydrate continuation checks
    `isDisposed` first.
19. **`closeGuardPending` must be cleared on EVERY async-guard resolution path** (true, false,
    error) — otherwise `close()` is dead for that entry forever (`remove()` still works).
20. **`when` errors are caught in `_conditionsPass`**: reported once per entry
    (`conditionErrorReported`), treated as unmet — never thrown out of `open()`/`setContext()`/
    timer callbacks.
21. **After `dispose()`**: `open()` asserts (debug) / returns `null` without presenting
    (release); every other public mutator is a silent no-op (async callbacks after an app
    restart are legitimate). `dispose()` itself must clear entries with disposed reason BEFORE setting `_disposed`.

22. **Permanently capped serial entries must settle, not wait forever.**
    `_schedule` uses `_CooldownStore.permanentlyBlocked`; hydrate gating must precede
    persisted total decisions. Keep recoverable time-window waits and their wake timers.
23. **Cancel every timeout timer on all completion/removal paths.** queueTimer stops
    at activation; resolveTimer stops on resolution; dismissTimer stops on dismissed;
    cancelTimeouts covers settlement, remove, supersede, clear, and dispose. Late async
    results must pass `_isCurrent` / phase checks. Timeout reports must not stall the slot.
24. **Same-id serial takeover precedes queued priority** when the old active frees the
    same slot and the new entry is eligible/unpaused; affix cannot prevent self-reopen.
    Cross-slot/overlap replacement must reschedule the old slot. Old tickets bind entry
    identity, not just id, so cannot close/update/remove a newer submission.
25. **Do NOT dispose `dataListenable` at settlement/removal.** Backends may still read
    or detach listeners during exit animation; the channel retains its final value.
26. **Every `_settle` call must supply an `OverlayEndReason`.** The first reason wins;
    result/outcome/ended are delivered once, including when dismiss later times out.
    An ended event is not an animation-completion notification.
27. **Holds are independent pause sources OR-composed with manual/route pause.**
    release is idempotent; only effective pause edges freeze/release. Lifecycle binding
    uses a hold, defaults to paused/hidden, and detach releases it. Changing manager
    requires detaching the old binding; duration freezes, deadlines keep running.
28. **Observer default is PageRoute filtering.** Rejected routes perform no path lookup
    or deferred update; accepted routes write contextKey (default route). Built-in route
    gates and pauseOnRoutes still read route only; nested keys use when predicates.
29. **Never pass a result to `removeRoute` at the Flutter 3.27 minimum.** That argument
    requires 3.32; official presenters pop(result) on top, removeRoute(route) when covered.
    A covered direct handle dismissal has null result; manager.close already settled it.
30. **Ordered queue insertion and capacity are scheduling contracts.** `_enqueue` preserves
    replace/priority/FIFO; maxQueued evicts the ordered tail, excludes active entries;
    expireAfter counts pre-activation serial waiting including pauses, ignores overlap.

31. **批量通知只走 `_notify`。** 公开操作、票据关闭/移除和异步续体进入 `_batch`；
    嵌套批次只标记 `_notifyPending`，最外层完成后最多通知一次。不要内部直接调用
    notifyListeners；dataListenable 与 events 是独立通道，异步续体独立成批。
32. **build 期间推迟展示与管理器通知。** `_inBuildPhase` 检查 persistentCallbacks，
    `_deferredSlots`、`_releasePending`、`_frameNotifyPending` 去重帧后回调；帧后检查
    isDisposed、暂停、条件、hydrate，保留 takeover；dispose 后回调不得复活条目。
33. **`OverlayMode` 互斥且默认 queue。** 只允许 queue / replace / overlap，affix 独立；
    内部 replace 前排带和 overlap 的 now-or-never 契约保持不变，不恢复旧公开布尔参数。
34. **`RouteMatcher` 是唯一路由参数协议。** exact / anyOf / regex；null 或非 String 不匹配，
    anyOf 调用方不得修改输入列表；when 仍独占资格判断，pauseOnRoutes 仍只读 route 键。
    record.phase 使用 OverlayPhase，禁止字符串比较。
35. **后端 dismiss 每个条目只请求一次。** 共享 `dismissRequested` 在调用后端前置位，
    同步抛错和异步失败也不重试；close 后 remove / clear / dismiss 超时不能再次请求。
    externalDone 另管晚到 dismissed 的重入，不能代替 dismissRequested。
36. **slot 回收不能删除有计时器的 slot。** 最外层批次只回收 active 空、queue 空、
    gapPending false 且 gapTimer / delayTimer / cooldownTimer 全空的运行时槽位，保留 slots 配置。
37. **冷却重置与标签保持身份语义。** resetCooldown / clearCooldowns 同时重置 session 与
    持久化计数，hydrate 不能恢复已清除计数；不复活已 capped 的条目。tags 提交时复制且只读，
    clearTag 先全部移除再推进槽位，绕过守卫，原因 removed。

## 1.0.0 decisions

路线 A 三步已完成：0.2.2 加固 → 0.3.0 增量 → 1.0 类型收口。
随机序列不变量测试 `test/fuzz_invariants_test.dart` 是 1.0 前置安全网，已发现 dismiss 重复请求。
Gate 和显式状态机有意不做：现有状态由不变量测试守住，重构收益不足以抵消回归风险。
slot 并发数/互斥、冷却记录裁剪尚未提供；旧 id 计数需永久保留 total 语义。

## 0.3.0 architecture additions

`submit → OverlayTicket(result / outcome / data)`; `_settle → events(ended)`;
`present → DialogManager / BottomSheetManager / presentRoute → PresentedOverlay`;
`LayermanLifecycle → hold → effective pause OR manual OR route zone`.
`OverlaySlotOptions` configures per-slot gap/capacity. Default resolve/dismiss
watchdogs are 30s/10s; constructor null disables, per-entry resolve null inherits
and zero disables. The former no-timeout and same-id-priority footguns are fixed.

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
2. Close only via the overlay's OWN handle: for routes, push and RETAIN the `Route` object
   (`DialogRoute` / `ModalBottomSheetRoute` / `MaterialPageRoute`, also on `Get.key.currentState!`
   for GetX — `Get.dialog` doesn't expose its route), use `route.completed` as `dismissed`, and
   in `dismiss` `pop` it if `isCurrent`, else `removeRoute(route)` with NO result argument
   (`removeRoute`'s result param only exists since Flutter 3.32; min is 3.27). Name-based
   `popUntil`/`Get.until` silently does nothing when the route isn't topmost (e.g. under an
   overlap dialog) → incorrect adapter targeting; 0.3.0 now bounds the wait with dismissTimeout,
   but cannot ensure that the orphaned UI has disappeared. Prefer DialogManager / BottomSheetManager.
   `SnackbarController.close()`; bot_toast `CancelFunc`. NEVER bare `Get.back()`/pop-top.
3. Disarm backend orchestration: bot_toast `onlyOne: false` + dedicated groupKey + `onClose`
   as the single completion signal; GetX's internal snackbar queue is bypassed by our
   serialization; never `Get.closeAllSnackbars()` (hangs queued futures).
4. The manager unifies SEQUENCING, not z-order (bot_toast is a Stack ABOVE the Navigator,
   always on top); back-button stays with each backend. README has the three recipes.

## Verify workflow

```bash
flutter analyze
flutter test  # Record the actual final total; only when the task authorizes tests.
cd example
flutter test integration_test/orchestration_test.dart -d <serial>
```

Use the Android phone (Huawei STG-AL00 / Android 12 for the reported 0.3.0 run).
`example/android/` is present; the v0.3 Features page exercises the new APIs.
The Windows desktop runner takes focus: do not run it unattended.
For Task B3 documentation acceptance, do not run flutter test at all; analyze key
README snippets in an external scratchpad and validate the SVG as XML instead.
CI remains defined in `.github/workflows/layerman-ci.yml`; do not infer a local
pass count from static declarations or a prior version's baseline.

Integration-test gotchas (learned the hard way):
- Use `tapVisible` for off-screen controls: it calls ensureVisible, pumps layout,
  then taps. The Android viewport is smaller than Windows; a finder alone does
  not prove that the tap point is visible. Keep v0.3 page controls reachable.
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

## Simulating app lifecycle on a real device — do NOT use the binding

`WidgetsBinding.handleAppLifecycleStateChanged(paused | hidden | detached)` sets
`SchedulerBinding.framesEnabled = false`. On a real device `tester.pump()` then waits forever for a
frame that never comes (the phone sits on "Test starting..."), and a manual demo button would freeze
the whole UI. Plain `flutter test` hides this (its `pump()` drives frames synthetically). Simulate
background/foreground by calling `LayermanLifecycle.didChangeAppLifecycleState(...)` on the attached
observer instead (the example exposes it as `appLifecycle`): same hold/release logic, no global side effect.
