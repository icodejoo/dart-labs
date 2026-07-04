# layerman

A **Flutter-native overlay queue manager** for dialogs, modals, bottom-sheets,
toasts and banners. It owns *when* / *which* overlay is shown — a serial
one-at-a-time queue with named slots, priority, `replace`, `affix` and
`overlap` — and, unlike a headless orchestrator, it actually **renders** by
inserting real `OverlayEntry`s into an attached `OverlayState`. Overlays return
an imperative `Future<T?>` result (like `showDialog`) and support a two-phase
close so widgets can play an exit animation.

It can also **orchestrate overlays rendered by other libraries** — native
`showDialog`, GetX (`Get.dialog` / `Get.snackbar`), `bot_toast`, `fluttertoast`,
… — through one small adapter (`present:`), so a single queue governs every
overlay system in your app.

> Design note: this is the Flutter sibling of the framework-agnostic headless TS
> package `@codejoo/overlaymanager`. It keeps that package's *orchestration
> semantics* but embraces Flutter's own `Overlay`/`OverlayEntry` for rendering.

- [Features](#features)
- [Install](#install)
- [Getting started](#getting-started)
- [Usage](#usage)
- [Integrating other overlay libraries](#integrating-other-overlay-libraries-the-present-adapter)
- [Full API reference](#full-api-reference)
- [Deliberate differences from the TS package](#deliberate-differences-from-the-ts-package)
- [中文文档](#中文文档)

## Features

- **Serial queue** — one overlay at a time per slot; the next shows when the
  current is removed, with an optional `gap` between them.
- **Named slots** — independent serial queues (e.g. `toast` vs `dialog`) that
  run in parallel.
- **Priority** — higher priority shows first; ties break FIFO.
- **`replace`** — preempt the current overlay of a slot and show immediately
  (skips a pending gap; front-bands ahead of already-queued entries). The
  preempted overlay is **sent back to the queue** and re-shows once the
  replacer closes.
- **`affix`** — protect the current overlay from `replace` (the blocked
  replacer waits at the queue front instead).
- **`overlap`** — bypass the queue and stack on top right now (global alerts,
  blocking loaders). Conditions/cooldown act as a now-or-never fire-gate.
- **Conditions** — a `when(ctx)` predicate (sole authority when present) or the
  `route` / `requiresAuth` sugar, driven by `setContext({...})`; a shown
  overlay whose conditions stop holding is auto-dismissed (`dismissWhenUnmet`,
  default true — queued entries just wait).
- **Cooldown** — `OverlayCooldown(session:, total:, day:, hour:, minute:,
  minGap:)`, all present caps AND together and count on real open; persisted
  through a pluggable `OverlayCooldownStorage` (default in-memory; back it with
  `shared_preferences` in real apps). A **time-based** cap (`minGap` + bucket
  rollover) auto-shows the queued entry the moment it expires.
- **Backend-driven `resolve`** — fetch the payload only when the overlay is
  granted the slot; returning `null` skips it. The slot is committed while
  resolving (later arrivals cannot preempt it).
- **`beforeClose` guard** — return `false` (sync or async) to veto a `close()`
  (unsaved-changes confirmations); `remove`/`clear` bypass it.
- **`Future<T?>` results** — `open()` returns a future that resolves with the
  value you close with, or `null` when dismissed.
- **Two-phase close** — an overlay moves to `OverlayPhase.closing` first (play
  your exit animation), then is removed (which advances the queue).
- **`pauseAll`/`resumeAll`** — full freeze (nothing new shows; running
  `duration` countdowns pause); per-id `pause`/`resume` freeze one countdown.
- **`update(id, patch)`** — shallow-merge into a shown overlay's `data` and
  rebuild, without any queue change; **`clearWhere(test)`** — selective mass
  removal (e.g. "close everything of group X").
- **Per-overlay `delay` and `duration`** (auto-close), and an optional modal
  **barrier** (`barrierColor` / `barrierDismissible`).
- **Orchestrates external overlay systems** — one queue over `showDialog`,
  GetX, `bot_toast`, `fluttertoast`, or anything you can show/close.

## Install

```yaml
dependencies:
  layerman: ^0.0.1
```

```dart
import 'package:layerman/layerman.dart';
```

The package has **zero third-party runtime dependencies** (only the Flutter
SDK). The example app pulls in `get` and `bot_toast` only to demonstrate the
external adapter.

## Getting started

Mount an `OverlayManagerScope` once near the app root. It owns a dedicated
`Overlay` layer above `child`, so managed overlays are independent of the
`Navigator` route stack.

```dart
final manager = OverlayManager(gap: const Duration(milliseconds: 300));

MaterialApp(
  builder: (context, child) =>
      OverlayManagerScope(manager: manager, child: child!),
  home: const HomePage(),
);
```

Reach the manager from anywhere below the scope with
`OverlayManagerScope.of(context)` (or keep your own reference, as above).

You can also drive an ambient `Overlay` yourself with
`manager.attach(Overlay.of(context))` instead of using the dedicated layer.

## Usage

### Open and await a result

```dart
final ok = await manager.open<bool>(
  id: 'confirm-delete',
  barrierColor: const Color(0x88000000),
  barrierDismissible: true,
  builder: (context, handle) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => handle.close(false), // result = false
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => handle.close(true), // result = true
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    ),
  ),
);
if (ok == true) doDelete(); // dismissed (barrier tap) -> ok == null
```

`open()` returns immediately with a `Future<T?>`; the overlay may show now or
wait in the queue. The future resolves when it is finally closed.

### Queue, priority, replace, affix, overlap

```dart
// These queue behind one another (serial, one at a time):
manager.open(id: 'welcome', builder: (c, h) => const WelcomeSheet());
manager.open(id: 'promo', priority: 10, builder: (c, h) => const PromoCard()); // jumps ahead

// Preempt whatever is currently showing in the default slot (it goes back to
// the queue and re-shows after the replacer closes):
manager.open(id: 'session-expired', replace: true, builder: (c, h) => const ExpiredDialog());

// Protect the current overlay so a replace cannot cover it:
manager.open(id: 'critical', affix: true, builder: (c, h) => const CriticalDialog());

// Ignore the queue and stack on top right now:
manager.open(id: 'net-error', overlap: true, builder: (c, h) => const ErrorBanner());

// Independent serial queues that run in parallel:
manager.open(id: 't1', slot: 'toast', builder: (c, h) => const Toast('Saved'));
```

### Conditions (`when` / `route` / `requiresAuth` / `setContext`)

Overlays can gate on an app-wide context you push with `setContext`. A queued
overlay whose conditions don't hold simply **waits**; a *shown* overlay whose
conditions stop holding is auto-dismissed unless `dismissWhenUnmet: false`.

```dart
// Feed your real navigation / auth state into the manager:
manager.setContext({'route': '/promo', 'auth': true});

// Sugar: show only on a route (String, List<String> or RegExp) ...
manager.open(id: 'promo', route: '/promo', builder: (c, h) => const PromoCard());
// ... only when authenticated ...
manager.open(id: 'inbox', requiresAuth: true, builder: (c, h) => const InboxHint());
// ... or an arbitrary predicate (sole authority when given):
manager.open(
  id: 'vip',
  when: (ctx) => ctx['tier'] == 'gold' && ctx['route'] == '/home',
  builder: (c, h) => const VipCard(),
);
```

`route` reserves the context key `route`; `requiresAuth` reserves `auth`.
Everything else is free-form for `when` predicates.

### Cooldown (frequency caps + persistence)

```dart
manager.open(
  id: 'rate-us',
  cooldown: const OverlayCooldown(
    total: 3,                        // at most 3 times ever
    day: 1,                          // at most once per local day
    minGap: Duration(hours: 6),      // and at least 6h apart
  ),
  builder: (c, h) => const RateUsCard(),
);
```

All present caps must pass (AND); a cap counts when the overlay actually opens.
`session` lives in memory; the rest persist. Back the store with real storage
and await hydration before your first show:

```dart
final manager = OverlayManager(
  cooldownStorage: SharedPrefsCooldownStorage(), // your OverlayCooldownStorage
  storageKey: 'layerman:cooldown',
);
await manager.ready(); // hydrate persisted counters
```

A minimal `shared_preferences` adapter:

```dart
class SharedPrefsCooldownStorage implements OverlayCooldownStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
```

### Backend-driven `resolve`

Fetch the payload only when the slot is granted (avoids loading data for an
overlay that may never show). Returning `null` skips it without counting
cooldown; the slot is committed while resolving, so later arrivals cannot
preempt it.

```dart
manager.open<void>(
  id: 'offer',
  resolve: () async => api.fetchOfferOrNull(), // null -> skip silently
  builder: (c, handle) => OfferCard(offer: handle.data as Offer),
);
```

### `beforeClose` guard

```dart
manager.open(
  id: 'editor',
  beforeClose: () async => await confirmDiscard(), // false vetoes the close
  builder: (c, h) => const EditorSheet(),
);
```

`beforeClose` gates `close()`/`dismiss()` only — `remove`/`clear`/auto-dismiss
bypass it.

### pause / resume / update / clearWhere

```dart
manager.pauseAll();   // full freeze: nothing new shows, duration timers pause
manager.resumeAll();  // release + re-schedule
manager.pause('sheet');   // freeze one overlay's duration countdown
manager.resume('sheet');

manager.update('cart', {'count': 3}); // shallow-merge data + rebuild, no re-queue

// Selective mass removal (data is your opaque payload):
manager.clearWhere((r) => (r.data as Map?)?['group'] == 'promo');
```

### Two-phase close / exit animation

`close()` moves the overlay to `OverlayPhase.closing`, waits `exitDuration`
(default 200 ms, overridable per overlay), then removes it. Drive your exit
animation off `handle.phaseListenable`:

```dart
manager.open(
  id: 'sheet',
  exitDuration: const Duration(milliseconds: 250),
  builder: (context, handle) => ValueListenableBuilder<OverlayPhase>(
    valueListenable: handle.phaseListenable,
    builder: (context, phase, _) => AnimatedOpacity(
      opacity: phase == OverlayPhase.open ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: const MySheet(),
    ),
  ),
);
```

### Imperative control & introspection

```dart
manager.close('sheet', someResult); // two-phase close with a result
manager.dismiss('sheet');           // close with null
manager.remove('sheet');            // remove immediately, no exit animation
manager.clear();                    // remove everything (queued + active)

manager.isShowing('sheet'); // bool — active (resolving/open/closing)
manager.activeIds;          // currently shown ids
manager.queuedIds;          // ids waiting in queues
manager.isPaused;           // bool
manager.isAttached;         // bool — has an OverlayState
```

`OverlayManager` is a `ChangeNotifier`, so `addListener` / `AnimatedBuilder`
can rebuild UI (e.g. a debug HUD) on every transition.

## Integrating other overlay libraries (the `Present` adapter)

A project rarely has just one overlay system. `open(present: ...)` lets the
manager **schedule** overlays that are **rendered by another library**: the
`present` callback runs only when the queue grants permission, and returns a
bidirectional handle:

```dart
PresentedOverlay<T>(
  dismissed: someFuture,            // the backend's "fully closed" signal (any path)
  dismiss: ([T? result]) async {},  // orchestrator-driven, targeted close
)
```

- `await open(...)` resolves through **`dismissed`** — complete it on *every*
  close path (user tap, barrier, back button, timeout, your `dismiss`).
- `close` / `replace` / `clear` / `remove` drive **`dismiss`** to close the
  backend on the manager's behalf.
- External entries **don't need an attached `OverlayState`** — the backend
  renders them.
- For external entries `exitDuration` is a **post-dismiss grace period** before
  the queue advances (route futures often complete when the exit animation
  *starts*).

The whole point: a single serial queue (plus priority / replace / cooldown /
conditions) now governs dialogs, snackbars and toasts from different libraries
uniformly.

### Native `showDialog`

```dart
manager.open<bool>(
  id: 'confirm',
  exitDuration: const Duration(milliseconds: 200),
  present: (ctx) {
    final name = 'om://${ctx.id}';
    final future = showDialog<bool>(
      context: rootNavigatorContext, // e.g. navigatorKey.currentContext!
      useRootNavigator: true,
      routeSettings: RouteSettings(name: name),
      builder: (_) => const ConfirmDialog(),
    );
    return PresentedOverlay<bool>(
      dismissed: future, // barrier / back button / pop complete it
      // Targeted close by route name — never a bare pop of "whatever is on top":
      dismiss: ([r]) async =>
          Navigator.of(rootNavigatorContext).popUntil((rt) => rt.settings.name != name),
    );
  },
);
```

### GetX dialog / bottom sheet

```dart
manager.open<bool>(
  id: 'confirm',
  exitDuration: const Duration(milliseconds: 200),
  present: (ctx) {
    final name = 'om://${ctx.id}';
    final future = Get.dialog<bool>( // or Get.bottomSheet(...)
      const ConfirmDialog(),
      routeSettings: RouteSettings(name: name),
    );
    return PresentedOverlay<bool>(
      dismissed: future,
      // Never bare Get.back()/pop-top (a snackbar could steal it):
      dismiss: ([r]) async => Get.until((rt) => rt.settings.name != name),
    );
  },
);
```

### GetX snackbar

`SnackbarController.future` completes after the exit animation — the cleanest
signal. GetX's internal snackbar queue is naturally bypassed because the
manager serializes for you.

```dart
manager.open<void>(
  id: 'saved',
  slot: 'snack', // a dedicated lane so a toast can coexist with a modal dialog
  present: (ctx) {
    final c = Get.snackbar('Saved', 'Your changes are safe.');
    return PresentedOverlay<void>(
      dismissed: c.future,
      dismiss: ([_]) => c.close(),
    );
  },
);
```

> Tip: a toast/snackbar on its **own slot** intentionally runs in parallel with
> your main dialog queue (that is the usual UX). Put it on the **default slot**
> instead if you want it strictly serialized behind dialogs.

### bot_toast

Disarm its own competing semantics: `onlyOne: false` and a dedicated
`groupKey`; `onClose` is the single "fully closed" signal; the `CancelFunc`
plays its exit animation.

```dart
manager.open<void>(
  id: 'tip',
  slot: 'toast',
  present: (ctx) {
    final done = Completer<void>();
    final cancel = BotToast.showText(
      text: 'Copied to clipboard',
      onlyOne: false,               // replace decisions belong to the manager
      onClose: () => done.complete(), // fires after the exit animation
    );
    return PresentedOverlay<void>(
      dismissed: done.future,
      dismiss: ([_]) async => cancel(),
    );
  },
);
```

### fluttertoast

`fluttertoast`'s `Fluttertoast.showToast` is fire-and-forget: it has **no
per-toast "closed" callback** and only a global `Fluttertoast.cancel()`. So you
**synthesize** the `dismissed` signal with a timer matching the toast length.

```dart
manager.open<void>(
  id: 'copied',
  slot: 'toast',
  present: (ctx) {
    final done = Completer<void>();
    Fluttertoast.showToast(
      msg: 'Copied',
      toastLength: Toast.LENGTH_SHORT, // ~2s on Android
    );
    // No native "closed" event — approximate it so the queue advances.
    final timer = Timer(const Duration(seconds: 2), () {
      if (!done.isCompleted) done.complete();
    });
    return PresentedOverlay<void>(
      dismissed: done.future,
      dismiss: ([_]) async {
        timer.cancel();
        await Fluttertoast.cancel(); // coarse: cancels all toasts
        if (!done.isCompleted) done.complete();
      },
    );
  },
);
```

> For a custom-widget toast with a proper per-toast handle, use the `FToast`
> API (`showToast` + `removeCustomToast`) and complete `dismissed` from your
> own removal — same shape as the bot_toast recipe.

### Writing your own adapter — checklist

For any library you can *show* and *close*:

1. Call the library's show API inside `present`.
2. Return `PresentedOverlay(dismissed:, dismiss:)`.
3. **`dismissed`** must complete on *every* close path (user, timeout, your
   `dismiss`). If the library has no "closed" event, synthesize it (timer /
   `onClose` / route future).
4. **`dismiss`** must close *that specific* overlay via its own handle — never
   "close whatever is on top".
5. Give it a `slot` if it should run in its own lane; set `exitDuration` as the
   grace before the queue advances.

### Rules of engagement (from GetX / bot_toast issue history)

1. The manager owns the truth — never poll `Get.isDialogOpen` /
   `Get.isSnackbarOpen` etc.
2. Close only via each overlay's own handle (unique `RouteSettings.name`,
   `SnackbarController`, `CancelFunc`) — never "pop whatever is on top".
3. Disarm backend-side orchestration (`onlyOne`, `crossPage`, GetX's snackbar
   queue) — replace / dismiss decisions belong to the manager. Never
   `Get.closeAllSnackbars()` (it hangs queued futures).
4. The manager unifies **sequencing**, not **z-order**: `bot_toast` always
   paints above routes (it lives in a `Stack` over the `Navigator`); the
   back-button stays with each backend. For real z-order control, render
   through the builtin `builder` path instead.

## Full API reference

Every exported symbol is listed here.

### `OverlayManager` (a `ChangeNotifier`)

```dart
OverlayManager({
  Duration gap = Duration.zero,
  Duration exitDuration = const Duration(milliseconds: 200),
  OverlayCooldownStorage? cooldownStorage, // default MemoryCooldownStorage
  String storageKey = 'layerman:cooldown',
  DateTime Function()? now,                // injectable clock (tests)
})
```

| Member | Description |
| --- | --- |
| `final Duration gap` | Delay inserted between one overlay closing and the next showing. |
| `final Duration exitDuration` | Default time in `closing` before removal (per-overlay overridable). |
| `Future<void> ready()` | Completes when the cooldown store has hydrated. Await before the first cooldown-gated open. |
| `bool get isAttached` | Whether an `OverlayState` is attached (builtin rendering). |
| `bool get isPaused` | Whether `pauseAll` is in effect. |
| `List<String> get activeIds` | Ids currently shown (resolving/open/closing), serial + overlaps. |
| `List<String> get queuedIds` | Ids waiting in queues. |
| `bool isShowing(String id)` | Whether `id` is currently active. |
| `void attach(OverlayState overlay)` | Wire to an overlay (done for you by `OverlayManagerScope`). |
| `void detach()` | Detach from the overlay (entries removed from it; not settled). |
| `Future<T?> open<T>({...})` | Enqueue/show an overlay; returns its result future. See below. |
| `void close(String id, [Object? result])` | Two-phase close, delivering `result` (runs `beforeClose`). |
| `void dismiss(String id)` | `close(id)` with a `null` result. |
| `void remove(String id)` | Remove immediately, no exit animation; bypasses `beforeClose`. |
| `void clear()` | Remove everything (queued + active); pending results resolve `null`. |
| `void clearWhere(bool Function(OverlayRecord) test)` | Selectively remove matching entries. |
| `void update(String id, Object? patch)` | Merge `patch` into `data` (map-into-map shallow-merge, else replace) and rebuild; no queue change. |
| `void setContext(Map<String, Object?> partial)` | Merge into the condition context and re-evaluate. |
| `void pauseAll()` / `void resumeAll()` | Full freeze / release + re-schedule. |
| `void pause(String id)` / `void resume(String id)` | Freeze / thaw one overlay's `duration` countdown. |
| `void dispose()` | Cancel timers, clear entries, dispose the notifier. |

Inherited from `ChangeNotifier`: `addListener` / `removeListener` /
`notifyListeners` (fired on every state transition).

#### `open<T>` parameters

Exactly **one** of `builder` or `present` is required.

| Parameter | Default | Description |
| --- | --- | --- |
| `OverlayContentBuilder<T>? builder` | — | Self-rendered content (manager inserts an `OverlayEntry`). |
| `Present<T>? present` | — | External-rendered adapter (see integration section). |
| `String? id` | auto | Unique id. Reusing an *active* id replaces it in place; reusing a *queued* id overrides that entry. |
| `Object? data` | `null` | Opaque payload, read via `handle.data` / `OverlayRecord.data`. |
| `String slot` | `''` | Named serial queue (independent lanes run in parallel). |
| `int priority` | `0` | Higher shows first; ties break FIFO. |
| `Duration? delay` | `null` | Appear delay before this overlay shows. |
| `Duration? duration` | `null` | Auto-close after this long once shown. |
| `bool replace` | `false` | Preempt the slot's current overlay (it returns to the queue) and show now. |
| `bool affix` | `false` | Protect the current overlay from being `replace`d. |
| `bool overlap` | `false` | Bypass the queue and stack immediately (now-or-never). |
| `OverlayPredicate? when` | `null` | Condition predicate; sole authority when present. |
| `Object? route` | `null` | Route gate sugar: `String`, `List<String>` or `RegExp` vs `context['route']`. |
| `bool? requiresAuth` | `null` | Auth gate sugar vs `context['auth']`. |
| `bool dismissWhenUnmet` | `true` | Auto-dismiss a *shown* overlay whose conditions stop holding. |
| `OverlayCooldown? cooldown` | `null` | Frequency cap (see `OverlayCooldown`). |
| `Future<T?> Function()? resolve` | `null` | Fetch the payload when granted; `null` skips without counting cooldown. |
| `FutureOr<bool> Function()? beforeClose` | `null` | Close guard; `false`/throw vetoes `close`. |
| `Color? barrierColor` | `null` | Modal barrier color (builtin only). |
| `bool barrierDismissible` | `false` | Tap the barrier to dismiss (builtin only). |
| `Duration? exitDuration` | manager default | Builtin: exit-animation time. External: post-dismiss grace. |

### `OverlayHandle<T>`

Passed to your `builder`; also lets you close/observe the overlay.

| Member | Description |
| --- | --- |
| `final String id` | The overlay's id. |
| `Object? get data` | Opaque payload (post-`resolve`, post-`update`). |
| `Future<T?> get result` | Completes when closed, with the close result or `null`. |
| `OverlayPhase get phase` | Current phase (`open` / `closing`). |
| `ValueListenable<OverlayPhase> get phaseListenable` | Drive exit animations off this. |
| `bool get isClosing` | Whether the phase is `closing`. |
| `void close([T? result])` | Request a two-phase close, optionally with a result. |

### `OverlayManagerScope` (a `StatefulWidget`)

| Member | Description |
| --- | --- |
| `OverlayManagerScope({Key?, required OverlayManager manager, required Widget child})` | Hosts a dedicated `Overlay` layer above `child` and provides the manager to descendants. Swapping `manager` re-attaches automatically. |
| `final OverlayManager manager` | The hosted manager. |
| `final Widget child` | Your app subtree (rendered under the overlay layer). |
| `static OverlayManager of(BuildContext)` | Nearest manager (asserts if absent). |
| `static OverlayManager? maybeOf(BuildContext)` | Nearest manager or `null`. |

### `OverlayPhase` (enum)

`open` — fully shown · `closing` — asked to close, playing its exit animation.

### `OverlayCooldown`

```dart
const OverlayCooldown({int? session, int? total, int? day, int? hour, int? minute, Duration? minGap})
```

All non-null caps must pass (AND) and count on real open. `session` (per app
run) is in memory; `total` / `day` / `hour` / `minute` (local calendar buckets)
and `minGap` (rolling minimum spacing) are persisted. Fields: `session`,
`total`, `day`, `hour`, `minute`, `minGap`.

### `OverlayCooldownStorage` / `MemoryCooldownStorage`

```dart
abstract class OverlayCooldownStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
```

`MemoryCooldownStorage` is the default in-memory implementation (counters reset
on restart). Provide your own (e.g. `shared_preferences`) for persistence.

### `OverlayRecord`

Read-only snapshot handed to `clearWhere`. Fields: `final String id`,
`final String slot`, `final Object? data`, `final bool active`,
`final String phase` (`'pending'` / `'resolving'` / `'open'` / `'closing'`).

### `Present<T>` / `PresentContext` / `PresentedOverlay<T>`

```dart
typedef Present<T> = PresentedOverlay<T> Function(PresentContext context);
```

`PresentContext` (given to your `present` callback) — fields: `final String id`,
`final String slot`, `final Object? data`.

```dart
class PresentedOverlay<T> {
  PresentedOverlay({required Future<T?> dismissed, Future<void> Function([T? result])? dismiss});
  final Future<T?> dismissed;                          // backend "closed" signal
  final Future<void> Function([T? result])? dismiss;   // orchestrator close
}
```

### `OverlayContentBuilder<T>` / `OverlayPredicate`

```dart
typedef OverlayContentBuilder<T> = Widget Function(BuildContext context, OverlayHandle<T> handle);
typedef OverlayPredicate = bool Function(Map<String, Object?> context);
```

## Deliberate differences from the TS package

- **`stackIndex`/`isTopmost` are N/A** — the TS core is headless and hands the
  host layer-order metadata; this package renders real `OverlayEntry`s, so
  z-order *is* the insertion order in the `Overlay`.
- **Cross-tab/cross-isolate cooldown sync is not built in** — share one
  `OverlayCooldownStorage` backend if you need it.
- **Time-based cooldown auto-wakes** — unlike the headless TS core (which
  re-qualifies only on the next scheduling trigger), a Flutter entry blocked by
  a `minGap` or a bucket rollover arms a timer and shows itself the moment the
  window elapses. `session`/`total` never expire, so they still wait for a
  trigger.

## Testing

```bash
flutter test                                                   # unit (widget) tests
cd example && flutter test integration_test -d <device>        # real-device orchestration
```

The unit suite uses `WidgetTester` to cover serial queueing, close-advances,
priority, `Future` results, `replace`/`affix`/`overlap`, conditions, cooldown
(incl. auto-wake), `resolve`, `beforeClose`, pause/resume, `update`/`clearWhere`,
the external presenter, and phase transitions. The `example/` app is a full
real-device demo orchestrating GetX + bot_toast + builtin overlays.

## License

MIT — see [LICENSE](LICENSE).

---

# 中文文档

**layerman** 是一个 **Flutter 原生的浮层（overlay）队列管理器**,统一编排
dialog、modal、bottom-sheet、toast、banner:它掌管「**何时 / 展示哪个**」浮层——
带具名 slot、优先级、`replace`、`affix`、`overlap` 的**串行单显**队列——并且不同于
无渲染(headless)编排器,它会真正把 `OverlayEntry` 插入到已挂载的 `OverlayState`
里**负责渲染**。每个浮层返回命令式的 `Future<T?>` 结果(像 `showDialog`),并支持
**两阶段关闭**以播放退场动画。

它还能通过一个小小的适配器(`present:`)**编排由其它库渲染的浮层**——原生
`showDialog`、GetX(`Get.dialog` / `Get.snackbar`)、`bot_toast`、`fluttertoast`
等——从而用**同一条队列**统管 App 里所有浮层系统。

> 设计说明:本包是框架无关的 headless TS 包 `@codejoo/overlaymanager` 的 Flutter
> 姊妹版,沿用其编排语义,但拥抱 Flutter 自己的 `Overlay`/`OverlayEntry` 来渲染。

## 特性

- **串行队列**:每个 slot 一次只显示一个,当前移除后下一个才显示,可设 `gap` 间隔。
- **具名 slot**:相互独立、可并行的多条串行队列(如 `toast` 与 `dialog`)。
- **优先级**:高者先显示,同级 FIFO。
- **`replace`**:抢占当前浮层立即显示(跳过待定 gap;排在已入队项之前);被顶掉的
  浮层会**退回队列**,待抢占者关闭后再次显示。
- **`affix`**:保护当前浮层不被 `replace` 顶掉(被挡的抢占者在队首等待)。
- **`overlap`**:绕过队列,立刻叠加显示(全局告警、阻塞式 loading);条件/冷却对
  overlap 是「此刻不满足即丢弃」的一次性发射门。
- **条件**:`when(ctx)` 谓词(存在时唯一权威),或 `route` / `requiresAuth` 语法糖,
  由 `setContext({...})` 驱动;已显示的浮层若条件不再满足会被自动撤下
  (`dismissWhenUnmet`,默认 true;排队项只是等待)。
- **冷却**:`OverlayCooldown(session / total / day / hour / minute / minGap)`,多个
  上限按 AND 生效、真正打开时才计数;通过可插拔的 `OverlayCooldownStorage` 持久化
  (默认内存;生产用 `shared_preferences`)。**时间型**上限(`minGap` 与自然桶滚动)
  到期时会**自动**把排队项弹出。
- **后端驱动 `resolve`**:仅当浮层获得 slot 时才取数据;返回 `null` 则跳过。取数
  期间 slot 已被占用(后来者无法抢占)。
- **`beforeClose` 守卫**:返回 `false`(同步或异步)可否决一次 `close()`(如未保存
  确认);`remove`/`clear` 会绕过它。
- **`Future<T?>` 结果**:`open()` 返回的 future 以你关闭时传入的值兑现,dismiss 则为
  `null`。
- **两阶段关闭**:浮层先进入 `OverlayPhase.closing`(播放退场动画),再被移除(移除
  才推进队列)。
- **`pauseAll`/`resumeAll`**:整体冻结(不再显示新浮层,`duration` 倒计时暂停);
  以及按 id 的 `pause`/`resume`。
- **`update(id, patch)`**:向已显示浮层的 `data` 浅合并并重建,不改队列;
  **`clearWhere(test)`**:按条件批量移除(如「关闭所有 X 组」)。
- **每浮层的 `delay` 与 `duration`**(自动关闭),以及可选的模态**遮罩**
  (`barrierColor` / `barrierDismissible`)。
- **编排外部浮层系统**:一条队列统管 `showDialog`、GetX、`bot_toast`、
  `fluttertoast` 或任何你能显示/关闭的东西。

## 安装

```yaml
dependencies:
  layerman: ^0.0.1
```

```dart
import 'package:layerman/layerman.dart';
```

主包**零第三方运行时依赖**(仅依赖 Flutter SDK)。example 里引入 `get` / `bot_toast`
只是为了演示外部适配器。

## 快速开始

在 App 根部挂一次 `OverlayManagerScope`。它在 `child` 之上拥有一个独立的 `Overlay`
层,因此受管浮层独立于 `Navigator` 路由栈。

```dart
final manager = OverlayManager(gap: const Duration(milliseconds: 300));

MaterialApp(
  builder: (context, child) =>
      OverlayManagerScope(manager: manager, child: child!),
  home: const HomePage(),
);
```

在 scope 之下任意位置可用 `OverlayManagerScope.of(context)` 取到 manager(或自己持有
引用)。也可以不用独立层,自行 `manager.attach(Overlay.of(context))` 接管环境 Overlay。

## 基础用法

### 打开并等待结果

```dart
final ok = await manager.open<bool>(
  id: 'confirm-delete',
  barrierColor: const Color(0x88000000),
  barrierDismissible: true,
  builder: (context, handle) => Center(
    child: TextButton(
      onPressed: () => handle.close(true), // 结果 = true
      child: const Text('删除'),
    ),
  ),
);
if (ok == true) doDelete(); // 点遮罩 dismiss -> ok == null
```

`open()` 立即返回一个 `Future<T?>`;浮层可能马上显示,也可能在队列里等待,future 在
它最终关闭时兑现。

### 队列 / 优先级 / replace / affix / overlap

```dart
manager.open(id: 'welcome', builder: (c, h) => const WelcomeSheet());
manager.open(id: 'promo', priority: 10, builder: (c, h) => const PromoCard()); // 插队靠前

// 抢占当前浮层(它会退回队列,待抢占者关闭后再次显示):
manager.open(id: 'session-expired', replace: true, builder: (c, h) => const ExpiredDialog());

// 固定当前浮层,replace 顶不掉它:
manager.open(id: 'critical', affix: true, builder: (c, h) => const CriticalDialog());

// 绕过队列,立刻叠加:
manager.open(id: 'net-error', overlap: true, builder: (c, h) => const ErrorBanner());

// 并行的独立串行队列:
manager.open(id: 't1', slot: 'toast', builder: (c, h) => const Toast('已保存'));
```

### 条件(`when` / `route` / `requiresAuth` / `setContext`)

排队项若条件不满足只会**等待**;已显示项若条件不再满足会被自动撤下(除非
`dismissWhenUnmet: false`)。

```dart
manager.setContext({'route': '/promo', 'auth': true}); // 把真实导航/登录态喂进来

manager.open(id: 'promo', route: '/promo', builder: (c, h) => const PromoCard());
manager.open(id: 'inbox', requiresAuth: true, builder: (c, h) => const InboxHint());
manager.open(
  id: 'vip',
  when: (ctx) => ctx['tier'] == 'gold', // 存在 when 时它是唯一权威
  builder: (c, h) => const VipCard(),
);
```

`route` 保留上下文键 `route`;`requiresAuth` 保留 `auth`;其余键随你在 `when` 里用。

### 冷却(频次上限 + 持久化)

```dart
manager.open(
  id: 'rate-us',
  cooldown: const OverlayCooldown(total: 3, day: 1, minGap: Duration(hours: 6)),
  builder: (c, h) => const RateUsCard(),
);
```

所有上限按 AND 通过才显示,真正打开时计数。`session` 存内存,其余持久化。生产中接真实
存储并在首次显示前等待 hydrate:

```dart
final manager = OverlayManager(cooldownStorage: SharedPrefsCooldownStorage());
await manager.ready();
```

`shared_preferences` 适配器最小实现:

```dart
class SharedPrefsCooldownStorage implements OverlayCooldownStorage {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
```

### 后端驱动 `resolve`

仅在获得 slot 时才取数据(避免为可能永不显示的浮层白白加载);返回 `null` 静默跳过且
不计冷却。取数期间 slot 已提交,后来者无法抢占。

```dart
manager.open<void>(
  id: 'offer',
  resolve: () async => api.fetchOfferOrNull(), // null -> 跳过
  builder: (c, handle) => OfferCard(offer: handle.data as Offer),
);
```

### `beforeClose` 守卫

```dart
manager.open(
  id: 'editor',
  beforeClose: () async => await confirmDiscard(), // 返回 false 否决关闭
  builder: (c, h) => const EditorSheet(),
);
```

`beforeClose` 只拦 `close()`/`dismiss()`;`remove`/`clear`/自动撤下会绕过。

### pause / resume / update / clearWhere

```dart
manager.pauseAll();  manager.resumeAll();   // 整体冻结 / 释放并重排
manager.pause('sheet'); manager.resume('sheet'); // 冻结/恢复单个 duration 倒计时

manager.update('cart', {'count': 3});       // 浅合并 data 并重建,不重排队列
manager.clearWhere((r) => (r.data as Map?)?['group'] == 'promo'); // 按条件批量清
```

### 两阶段关闭 / 退场动画

`close()` 先把浮层切到 `OverlayPhase.closing`,等待 `exitDuration`(默认 200ms,可按
浮层覆盖)后再移除。用 `handle.phaseListenable` 驱动退场动画:

```dart
manager.open(
  id: 'sheet',
  exitDuration: const Duration(milliseconds: 250),
  builder: (context, handle) => ValueListenableBuilder<OverlayPhase>(
    valueListenable: handle.phaseListenable,
    builder: (context, phase, _) => AnimatedOpacity(
      opacity: phase == OverlayPhase.open ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: const MySheet(),
    ),
  ),
);
```

### 命令式控制与内省

```dart
manager.close('sheet', someResult); // 带结果的两阶段关闭
manager.dismiss('sheet');           // 以 null 关闭
manager.remove('sheet');            // 立即移除,无退场动画
manager.clear();                    // 移除全部(排队 + 活跃)

manager.isShowing('sheet'); manager.activeIds; manager.queuedIds;
manager.isPaused; manager.isAttached;
```

`OverlayManager` 是 `ChangeNotifier`,可 `addListener` / `AnimatedBuilder` 在每次
状态变化时刷新 UI。

## 接入其它浮层库(`Present` 适配器)

项目里往往不止一套浮层系统。`open(present: ...)` 让管理器去**调度**由**其它库渲染**的
浮层:`present` 回调只在队列许可时被调用一次,返回一个双向句柄:

```dart
PresentedOverlay<T>(
  dismissed: someFuture,            // 后端「已完全关闭」的信号(任意关闭路径)
  dismiss: ([T? result]) async {},  // 由编排器发起的定向关闭
)
```

- `await open(...)` 通过 **`dismissed`** 兑现——它必须在**每一条**关闭路径上完成
  (用户点击、遮罩、返回键、超时、你的 `dismiss`)。
- `close` / `replace` / `clear` / `remove` 会调用 **`dismiss`** 代表管理器关闭后端。
- 外部条目**无需挂载 `OverlayState`**(后端自己渲染)。
- 外部条目的 `exitDuration` 是「**dismiss 之后**、队列推进之前」的宽限期(路由 future
  往往在退场动画**开始**时就完成了)。

核心价值:一条串行队列(叠加优先级 / replace / 冷却 / 条件)统一治理来自不同库的
dialog、snackbar、toast。

### 原生 `showDialog`

```dart
manager.open<bool>(
  id: 'confirm',
  exitDuration: const Duration(milliseconds: 200),
  present: (ctx) {
    final name = 'om://${ctx.id}';
    final future = showDialog<bool>(
      context: rootNavigatorContext,
      useRootNavigator: true,
      routeSettings: RouteSettings(name: name),
      builder: (_) => const ConfirmDialog(),
    );
    return PresentedOverlay<bool>(
      dismissed: future,
      dismiss: ([r]) async => Navigator.of(rootNavigatorContext)
          .popUntil((rt) => rt.settings.name != name), // 按路由名定向关,不 pop 栈顶
    );
  },
);
```

### GetX dialog / bottom sheet

```dart
manager.open<bool>(
  id: 'confirm',
  exitDuration: const Duration(milliseconds: 200),
  present: (ctx) {
    final name = 'om://${ctx.id}';
    final future = Get.dialog<bool>(const ConfirmDialog(),
        routeSettings: RouteSettings(name: name));
    return PresentedOverlay<bool>(
      dismissed: future,
      dismiss: ([r]) async => Get.until((rt) => rt.settings.name != name), // 别裸调 Get.back()
    );
  },
);
```

### GetX snackbar

`SnackbarController.future` 在退场动画后完成,是最干净的信号;GetX 自带的 snackbar
队列会因为管理器已串行化而被自然架空。

```dart
manager.open<void>(
  id: 'saved',
  slot: 'snack', // 单独车道:让 toast 能与主 dialog 并存
  present: (ctx) {
    final c = Get.snackbar('已保存', '你的修改已安全保存');
    return PresentedOverlay<void>(dismissed: c.future, dismiss: ([_]) => c.close());
  },
);
```

> 提示:放在**独立 slot** 的 toast/snackbar 会**故意**与主 dialog 队列并行(这是常见
> UX)。若要严格排在 dialog 之后,把它放到**默认 slot**。

### bot_toast

缴械它自带的竞争语义:`onlyOne: false` + 专属 `groupKey`;`onClose` 是唯一的「已完全
关闭」信号;`CancelFunc` 播放退场动画。

```dart
manager.open<void>(
  id: 'tip',
  slot: 'toast',
  present: (ctx) {
    final done = Completer<void>();
    final cancel = BotToast.showText(
      text: '已复制',
      onlyOne: false,               // replace 决策归管理器
      onClose: () => done.complete(),
    );
    return PresentedOverlay<void>(dismissed: done.future, dismiss: ([_]) async => cancel());
  },
);
```

### fluttertoast

`Fluttertoast.showToast` 是「发了就不管」:**没有单条 toast 的关闭回调**,只有全局
`Fluttertoast.cancel()`。因此需要用一个与时长匹配的定时器**合成** `dismissed`。

```dart
manager.open<void>(
  id: 'copied',
  slot: 'toast',
  present: (ctx) {
    final done = Completer<void>();
    Fluttertoast.showToast(msg: '已复制', toastLength: Toast.LENGTH_SHORT); // 安卓约 2s
    final timer = Timer(const Duration(seconds: 2), () {
      if (!done.isCompleted) done.complete(); // 无原生关闭事件 -> 近似合成
    });
    return PresentedOverlay<void>(
      dismissed: done.future,
      dismiss: ([_]) async {
        timer.cancel();
        await Fluttertoast.cancel(); // 粗粒度:会取消所有 toast
        if (!done.isCompleted) done.complete();
      },
    );
  },
);
```

> 若需要带单条句柄的自定义 toast,用 `FToast`(`showToast` + `removeCustomToast`),
> 从你自己的移除时机去完成 `dismissed`——形状与 bot_toast 相同。

### 编写你自己的适配器 —— 清单

对任何「能显示、能关闭」的库:

1. 在 `present` 里调用该库的显示 API。
2. 返回 `PresentedOverlay(dismissed:, dismiss:)`。
3. **`dismissed`** 必须在**每一条**关闭路径上完成;若该库没有「已关闭」事件,就自己
   合成(定时器 / `onClose` / 路由 future)。
4. **`dismiss`** 必须通过**那一条**浮层自己的句柄关闭它——绝不「关掉栈顶那个」。
5. 需要独立车道就给 `slot`;用 `exitDuration` 设置队列推进前的宽限。

### 编排纪律(源自 GetX / bot_toast 的 issue 史)

1. 管理器自持真相——**绝不**去读 `Get.isDialogOpen` / `Get.isSnackbarOpen`。
2. 只用各浮层自己的句柄关闭(唯一 `RouteSettings.name`、`SnackbarController`、
   `CancelFunc`)——绝不「关掉栈顶」。
3. 缴械后端自带的编排(`onlyOne`、`crossPage`、GetX 的 snackbar 队列)——replace /
   dismiss 决策归管理器;**禁用** `Get.closeAllSnackbars()`(会悬挂已入队 future)。
4. 管理器统一的是**时序**而非 **z 序**:`bot_toast` 永远画在路由之上(它在
   `Navigator` 之上的 `Stack` 里);返回键归各后端。需要真正的 z 序控制,请走内建
   `builder` 路径渲染。

## 完整 API 参考

见上文英文的 [Full API reference](#full-api-reference) 表格,列出了所有导出符号:
`OverlayManager`(构造 + 全部方法/getter)、`open<T>` 的每个参数、`OverlayHandle<T>`、
`OverlayManagerScope`、`OverlayPhase`、`OverlayCooldown`、`OverlayCooldownStorage` /
`MemoryCooldownStorage`、`OverlayRecord`、`Present` / `PresentContext` /
`PresentedOverlay`、`OverlayContentBuilder` / `OverlayPredicate`。

## 与 TS 版的刻意差异

- **不做 `stackIndex`/`isTopmost`**:TS 内核 headless、把层序元数据交给宿主;本包自己
  渲染真实 `OverlayEntry`,z 序**就是** `Overlay` 里的插入序。
- **不内建跨标签页/跨 isolate 冷却同步**:如需,共享同一个 `OverlayCooldownStorage`
  后端即可。
- **时间型冷却会自唤醒**:与 headless TS 内核(仅在下一次调度触发时才重新评估)不同,
  被 `minGap` 或桶滚动挡住的 Flutter 条目会自行武装定时器,到期即自动显示;
  `session`/`total` 永不到期,仍需等待触发。

## 测试

```bash
flutter test                                            # 单元(widget)测试
cd example && flutter test integration_test -d <device> # 真机编排测试
```

单元测试用 `WidgetTester` 覆盖:串行队列、关闭推进、优先级、`Future` 结果、
`replace`/`affix`/`overlap`、条件、冷却(含自唤醒)、`resolve`、`beforeClose`、
pause/resume、`update`/`clearWhere`、外部 presenter、相位切换。`example/` 是一个完整
的真机 demo,编排 GetX + bot_toast + 内建浮层。

## 许可

MIT —— 见 [LICENSE](LICENSE)。
