# layerman

🎮 [Live demo](https://icodejoo.github.io/dart-labs/layerman/)

A **headless overlay queue manager** for dialogs, modals, bottom-sheets, toasts
and banners. It owns *when* / *which* overlay is shown — a serial one-at-a-time
queue with named slots, priority, `replace`, `affix` and `overlap` — but never
renders anything itself: every overlay is shown through a `present:` backend
you supply (`showDialog`, GetX, `bot_toast`, a self-managed `OverlayEntry`, …).
Overlays return an imperative `Future<T?>` result (like `showDialog`) and
support a two-phase close so your backend can play its own exit animation.

It orchestrates overlays rendered by other libraries — native `showDialog`,
GetX (`Get.dialog` / `Get.snackbar`), `bot_toast`, `fluttertoast`, … — through
one small adapter (`present:`), so a single queue governs every overlay system
in your app.

> Design note: this is the Flutter sibling of the framework-agnostic headless TS
> package `@codejoo/overlaymanager`. It now shares that package's headless
> design too: the core imports no `package:flutter/widgets.dart` and owns no
> `Overlay` layer — it keeps only the orchestration semantics.

- [Features](#features)
- [Install](#install)
- [Getting started](#getting-started)
- [Why there is no `builder:`](#why-there-is-no-builder)
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
  preempted overlay is **closed** (result `null`) — a dismissed backend can't
  be faithfully re-presented, so it never re-shows.
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
- **Two-phase close** — `close()` settles the result immediately, then waits
  for your backend's `dismissed` signal plus an optional per-`open()`
  `exitDuration` grace before the queue advances, so a backend can play its own
  exit animation first.
- **`pauseAll`/`resumeAll`** — full freeze (nothing new shows; running
  `duration` countdowns pause); per-id `pause`/`resume` freeze one countdown.
- **Auto route awareness** — `LayermanNavigatorObserver` feeds real navigation
  into `route` conditions automatically (router-agnostic: vanilla `Navigator`,
  GetX, go_router); `pauseOnRoutes` declares "no-overlay zone" routes that
  freeze/resume the queue on entry/exit, composing cleanly with manual
  `pauseAll`/`resumeAll`. `currentRoute` reads the tracked value back.
- **`update(id, patch)`** — shallow-merge into a shown overlay's `data` and
  rebuild, without any queue change; **`clearWhere(test)`** — selective mass
  removal (e.g. "close everything of group X").
- **Per-overlay `delay` and `duration`** (auto-close).
- **Orchestrates external overlay systems** — one queue over `showDialog`,
  GetX, `bot_toast`, `fluttertoast`, or anything you can show/close.

## Install

```yaml
dependencies:
  layerman: ^0.2.0
```

```dart
import 'package:layerman/layerman.dart';
```

The package has **zero third-party runtime dependencies** (only the Flutter
SDK). The example app pulls in `get` and `bot_toast` only to demonstrate the
external adapter.

## Getting started

`Layerman` is a plain object — it mounts nothing and needs no widget
above your app. Create one and keep a reference to it however you already
share state in this app (a singleton, a GetX binding, a `Provider`, DI, …):

```dart
final manager = Layerman(gap: const Duration(milliseconds: 300));
```

Reach it from wherever you call `open()`/`close()`, and give it a `present:`
backend at the call site — see [Usage](#usage) below and the next section for
why there's no scope/attach step to wire up.

### Why there is no `builder:`

`layerman` is a **queue orchestrator, not a renderer.** It decides *when* and *which* overlay shows — it never owns a widget or an `Overlay` layer. Every overlay is shown through a `present:` backend you supply.

Earlier versions had a `builder:` that returned a `Widget` the manager mounted into its own `Overlay`. That forced the manager to *be* UI — own an `OverlayState`, stay attached to the tree, ship an `OverlayManagerScope`. It contradicted the one thing the package is for.

`present:` is a strict superset. Inside it you build any UI — `showDialog`, `Get.dialog`, `BotToast.show`, `Navigator.push`, or an `OverlayEntry` you insert yourself — and hand back a `PresentedOverlay(dismissed, dismiss)` handle. Anything `builder:` could render, a `present:` backend that owns its own `OverlayEntry` renders too — so nothing is lost, and the core is now headless (no `flutter/widgets` import), matching the headless TS sister package.

```dart
// before (0.1.x): the manager mounts your widget
manager.open(builder: (context, handle) => MyCard(onOk: () => handle.close('ok')));

// after (0.2.0): you mount it, and hand back a close signal
manager.open(present: (ctx) {
  final done = Completer<String?>();
  final cancel = BotToast.showWidget(
    toastBuilder: (_) => MyCard(onOk: () => done.complete('ok')),
  );
  done.future.whenComplete(cancel);
  return PresentedOverlay(dismissed: done.future, dismiss: ([r]) async => cancel());
});
```

For `showDialog` / `Get.dialog`, `dismissed` is just the route future and `dismiss` is a `Navigator.pop` / `Get.back` that targets *this* overlay's own route — see the recipes below.

## Usage

### A shared `present:` helper for these examples

Every example below shows the overlay through `showDialog`, wrapped in a tiny
helper that targets *this* overlay's own route for a close (the same pattern
the [full recipes](#native-showdialog) use, just factored out for brevity):

```dart
Present<T> dialog<T>(Widget child) => (ctx) {
  final name = 'om://${ctx.id}';
  final future = showDialog<T>(
    context: navigatorKey.currentContext!, // e.g. a GlobalKey<NavigatorState>
    routeSettings: RouteSettings(name: name),
    builder: (_) => child,
  );
  return PresentedOverlay<T>(
    dismissed: future, // barrier / back button / pop complete it
    dismiss: ([r]) async => Navigator.of(navigatorKey.currentContext!)
        .popUntil((rt) => rt.settings.name != name),
  );
};
```

### Open and await a result

```dart
final ok = await manager.open<bool>(
  id: 'confirm-delete',
  present: dialog(Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(navigatorKey.currentContext!, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(navigatorKey.currentContext!, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    ),
  )),
);
if (ok == true) doDelete(); // dismissed (barrier tap) -> ok == null
```

`open()` returns immediately with a `Future<T?>`; the overlay may show now or
wait in the queue. The future resolves when it is finally closed.

### Queue, priority, replace, affix, overlap

```dart
// These queue behind one another (serial, one at a time):
manager.open(id: 'welcome', present: dialog(const WelcomeSheet()));
manager.open(id: 'promo', priority: 10, present: dialog(const PromoCard())); // jumps ahead

// Preempt whatever is currently showing in the default slot (it is closed,
// result null — a dismissed backend can't be faithfully re-presented):
manager.open(id: 'session-expired', replace: true, present: dialog(const ExpiredDialog()));

// Protect the current overlay so a replace cannot cover it:
manager.open(id: 'critical', affix: true, present: dialog(const CriticalDialog()));

// Ignore the queue and stack on top right now:
manager.open(id: 'net-error', overlap: true, present: dialog(const ErrorBanner()));

// Independent serial queues that run in parallel:
manager.open(id: 't1', slot: 'toast', present: dialog(const Toast('Saved')));
```

### Conditions (`when` / `route` / `requiresAuth` / `setContext`)

Overlays can gate on an app-wide context you push with `setContext`. A queued
overlay whose conditions don't hold simply **waits**; a *shown* overlay whose
conditions stop holding is auto-dismissed unless `dismissWhenUnmet: false`.

```dart
// Feed your real navigation / auth state into the manager:
manager.setContext({'route': '/promo', 'auth': true});

// Sugar: show only on a route (String, List<String> or RegExp) ...
manager.open(id: 'promo', route: '/promo', present: dialog(const PromoCard()));
// ... only when authenticated ...
manager.open(id: 'inbox', requiresAuth: true, present: dialog(const InboxHint()));
// ... or an arbitrary predicate (sole authority when given):
manager.open(
  id: 'vip',
  when: (ctx) => ctx['tier'] == 'gold' && ctx['route'] == '/home',
  present: dialog(const VipCard()),
);
```

`route` reserves the context key `route`; `requiresAuth` reserves `auth`.
Everything else is free-form for `when` predicates.

### Auto route awareness (`LayermanNavigatorObserver` + `pauseOnRoutes`)

Feeding `route` into `setContext` by hand (in every navigable page's lifecycle)
is boilerplate. `LayermanNavigatorObserver` does it for you — add it to
`navigatorObservers` and it works under vanilla `Navigator`, GetX and
go_router alike, since all three ultimately drive a real Flutter `Navigator`
and this is a standard `NavigatorObserver`. It's purely observational: it
never pushes, pops, or otherwise touches navigation.

```dart
MaterialApp(
  navigatorObservers: [LayermanNavigatorObserver(manager)],
  ...
);
```

Once attached, treat it as the sole writer of the `route` context key — a
manual `setContext({'route': ...})` call is just overwritten by the next
navigation event. Read the tracked value back with `manager.currentRoute`
instead of maintaining your own mirror. Path defaults to
`route.settings.name`; pass `pathOf` if your router stores it elsewhere. A
route with no resolvable path (an anonymous `MaterialPageRoute` with no
`settings.name`) reports `null` — conditions simply don't match `null`,
Flutter gives us no other notion of "path" for anonymous routes.

Two things Flutter itself does that are easy to miss:

- **`MaterialApp.home`'s implicit route is named `'/'`**, not `null` and not
  `'/home'` — that's Flutter's own `Navigator.defaultRouteName`. If you want
  to gate on the home page by a specific string, give it one explicitly via
  `initialRoute`/`routes` (or a named `RouteSettings`) instead of `home:`.
- **A route-backed dialog pushed onto the same `Navigator`** (the
  `showDialog`/`Get.dialog` recipe above needs a unique route name for
  targeted close) genuinely *is* the topmost route while it's shown, so
  `route` reflects its name for that window — not a bug, just worth knowing
  if you combine route-backed dialogs with `route`-gated overlays elsewhere.

`pauseOnRoutes` builds a "no-overlay zone" on top of this: entering a matching
route freezes the whole queue (exactly like `pauseAll()` — nothing new
activates); leaving it resumes (like `resumeAll()`). It composes with manual
`pauseAll`/`resumeAll` rather than fighting them — leaving the zone doesn't
override an unrelated manual pause, and a manual `resumeAll()` doesn't
override an active zone.

```dart
final manager = Layerman(pauseOnRoutes: ['/checkout']);
// While the tracked route is '/checkout', no new overlay shows — queued ones
// wait and activate the moment the route changes away.
```

Whether an *already-shown* overlay should close when you navigate into a zone
is deliberately not a blanket rule — use the same `route`/`when` +
`dismissWhenUnmet` conditions covered above (they work the same no matter which
`present:` backend is rendering the overlay), or lean on a specific backend's
own navigation-aware close option if it has one.

### Cooldown (frequency caps + persistence)

```dart
manager.open(
  id: 'rate-us',
  cooldown: const OverlayCooldown(
    total: 3,                        // at most 3 times ever
    day: 1,                          // at most once per local day
    minGap: Duration(hours: 6),      // and at least 6h apart
  ),
  present: dialog(const RateUsCard()),
);
```

All present caps must pass (AND); a cap counts when the overlay actually opens.
`session` lives in memory; the rest persist. Back the store with real storage
and await hydration before your first show:

```dart
final manager = Layerman(
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
  present: (ctx) {
    final name = 'om://${ctx.id}';
    final future = showDialog<void>(
      context: navigatorKey.currentContext!,
      routeSettings: RouteSettings(name: name),
      builder: (_) => OfferCard(offer: ctx.data as Offer),
    );
    return PresentedOverlay<void>(
      dismissed: future,
      dismiss: ([_]) async => Navigator.of(navigatorKey.currentContext!)
          .popUntil((rt) => rt.settings.name != name),
    );
  },
);
```

`ctx.data` carries the resolved payload — `PresentContext.data` is the value
`resolve` returned (or the plain `data:` you passed, when there's no `resolve`).

### `beforeClose` guard

```dart
manager.open(
  id: 'editor',
  beforeClose: () async => await confirmDiscard(), // false vetoes the close
  present: dialog(const EditorSheet()),
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

manager.update('cart', {'count': 3}); // shallow-merge into data, notify listeners, no re-queue

// Selective mass removal (data is your opaque payload):
manager.clearWhere((r) => (r.data as Map?)?['group'] == 'promo');
```

`update` doesn't re-render anything itself (the manager owns no widgets) — it
just notifies listeners; a `present:` backend that wants to reflect the new
`data` should rebuild off that notification (or read `data` the next time it
builds).

### Two-phase close / exit animation

`close()` settles the result and asks your backend to close; the queue only
advances once the backend's `dismissed` future completes, plus an optional
`exitDuration` grace on top. The exit animation itself is entirely your
backend's job now — play it however you like before completing `dismissed`:

```dart
manager.open<void>(
  id: 'sheet',
  exitDuration: const Duration(milliseconds: 250), // grace after dismissed, before the queue advances
  present: (ctx) {
    final done = Completer<void>();
    var closing = false;
    late OverlayEntry entry;
    void requestClose() {
      if (closing) return;
      closing = true;
      entry.markNeedsBuild(); // rebuild with your own "closing" visual state
      Future.delayed(const Duration(milliseconds: 250), () {
        entry.remove();
        done.complete();
      });
    }

    entry = OverlayEntry(
      builder: (_) => AnimatedOpacity(
        opacity: closing ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: const MySheet(),
      ),
    );
    Overlay.of(navigatorKey.currentContext!).insert(entry);
    return PresentedOverlay<void>(
      dismissed: done.future,
      dismiss: ([_]) async => requestClose(),
    );
  },
);

manager.close('sheet'); // -> dismiss() -> requestClose() plays the fade, then settles
```

### Imperative control & introspection

```dart
manager.close('sheet', someResult); // two-phase close with a result
manager.dismiss('sheet');           // close with null
manager.remove('sheet');            // remove immediately, no exit grace
manager.clear();                    // remove everything (queued + active)

manager.isShowing('sheet'); // bool — active (resolving/open/closing)
manager.activeIds;          // currently shown ids
manager.queuedIds;          // ids waiting in queues
manager.isPaused;           // bool
```

`Layerman` is a `ChangeNotifier`, so `addListener` / `AnimatedBuilder`
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
- `exitDuration` is a **post-dismiss grace period** before
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

### A navigated page as a queue entry

A pushed `Route` is just another external presenter — `Navigator.push`
returns a `Future<T?>` that completes on pop, exactly like `showDialog`. Wrap
it the same way to make the page participate in the queue (occupy a slot,
respect `priority`/`replace`, block other overlays while it's up) — the push
itself only happens once the queue grants the slot:

```dart
manager.open<void>(
  id: 'checkout',
  present: (ctx) {
    final future = navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/checkout'),
      builder: (_) => const CheckoutPage(),
    ));
    return PresentedOverlay<void>(
      dismissed: future,
      dismiss: ([_]) async => navigatorKey.currentState!.pop(),
    );
  },
);
```

(`navigatorKey` is a `GlobalKey<NavigatorState>` passed to `MaterialApp`,
needed because `present`'s callback only gets a [`PresentContext`](#full-api-reference),
not a `BuildContext` — the same requirement every `present:` recipe above has.)

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
   back-button stays with each backend. Z-order is entirely your `present:`
   backend's call — insert your own `OverlayEntry` at whatever depth you need
   if you want explicit control over it.

## Full API reference

Every exported symbol is listed here.

### `Layerman` (a `ChangeNotifier`)

```dart
Layerman({
  Duration gap = Duration.zero,
  OverlayCooldownStorage? cooldownStorage, // default MemoryCooldownStorage
  String storageKey = 'layerman:cooldown',
  DateTime Function()? now,                // injectable clock (tests)
  List<Object> pauseOnRoutes = const [],   // String / List<String> / RegExp patterns
})
```

| Member | Description |
| --- | --- |
| `final Duration gap` | Delay inserted between one overlay closing and the next showing. |
| `Future<void> ready()` | Completes when the cooldown store has hydrated. Await before the first cooldown-gated open. |
| `Object? get currentRoute` | The `route` context key last set via `setContext` (`null` if never set). |
| `bool get isPaused` | Whether the queue is frozen — via `pauseAll` or a matching `pauseOnRoutes` pattern. |
| `bool get isDisposed` | Whether `dispose()` has been called — lets a deferred callback avoid calling into a torn-down manager. |
| `List<String> get activeIds` | Ids currently shown (resolving/open/closing), serial + overlaps. |
| `List<String> get queuedIds` | Ids waiting in queues. |
| `bool isShowing(String id)` | Whether `id` is currently active. |
| `Future<T?> open<T>({...})` | Enqueue/show an overlay through your `present:` backend; returns its result future. See below. |
| `void close(String id, [Object? result])` | Two-phase close, delivering `result` (runs `beforeClose`). |
| `void dismiss(String id)` | `close(id)` with a `null` result. |
| `void remove(String id)` | Remove immediately, no exit grace; bypasses `beforeClose`. |
| `void clear()` | Remove everything (queued + active); pending results resolve `null`. |
| `void clearWhere(bool Function(OverlayRecord) test)` | Selectively remove matching entries. |
| `void update(String id, Object? patch)` | Merge `patch` into `data` (map-into-map shallow-merge, else replace) and notify listeners; no queue change. |
| `void setContext(Map<String, Object?> partial)` | Merge into the condition context and re-evaluate. |
| `void pauseAll()` / `void resumeAll()` | Full freeze / release + re-schedule. |
| `void pause(String id)` / `void resume(String id)` | Freeze / thaw one overlay's `duration` countdown. |
| `void dispose()` | Cancel timers, clear entries, dispose the notifier. |

Inherited from `ChangeNotifier`: `addListener` / `removeListener` /
`notifyListeners` (fired on every state transition).

#### `open<T>` parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `Present<T> present` | required | Renders (and later closes) the overlay through your UI backend — see [integration section](#integrating-other-overlay-libraries-the-present-adapter). |
| `String? id` | auto | Unique id. Reusing an *active* id replaces it in place; reusing a *queued* id overrides that entry. |
| `Object? data` | `null` | Opaque payload, read via `PresentContext.data` / `OverlayRecord.data`. |
| `String slot` | `''` | Named serial queue (independent lanes run in parallel). |
| `int priority` | `0` | Higher shows first; ties break FIFO. |
| `Duration? delay` | `null` | Appear delay before this overlay shows. |
| `Duration? duration` | `null` | Auto-close after this long once shown. |
| `bool replace` | `false` | Preempt the slot's current overlay — it is **closed** (result `null`), never re-queued — and show now. |
| `bool affix` | `false` | Protect the current overlay from being `replace`d. |
| `bool overlap` | `false` | Bypass the queue and stack immediately (now-or-never). |
| `OverlayPredicate? when` | `null` | Condition predicate; sole authority when present. |
| `Object? route` | `null` | Route gate sugar: `String`, `List<String>` or `RegExp` vs `context['route']`. |
| `bool? requiresAuth` | `null` | Auth gate sugar vs `context['auth']`. |
| `bool dismissWhenUnmet` | `true` | Auto-dismiss a *shown* overlay whose conditions stop holding. |
| `OverlayCooldown? cooldown` | `null` | Frequency cap (see `OverlayCooldown`). |
| `Future<T?> Function()? resolve` | `null` | Fetch the payload when granted; `null` skips without counting cooldown. |
| `FutureOr<bool> Function()? beforeClose` | `null` | Close guard; `false`/throw vetoes `close`. |
| `Duration? exitDuration` | `null` | Grace between your backend's `dismissed` signal and the queue advancing (lets a shared exit animation finish); `null` advances immediately. |

### `LayermanNavigatorObserver` (a `NavigatorObserver`)

```dart
LayermanNavigatorObserver(
  Layerman manager, {
  String? Function(Route<dynamic> route)? pathOf, // default: route.settings.name
})
```

Add to `navigatorObservers`; listens to `didChangeTop` (the current topmost
route — covers cold start, push, pop, replace and declarative
`Navigator(pages:)` rebuilds in one signal, unlike the legacy push/pop/
replace/remove callbacks) and feeds it into `manager.setContext({'route':
...})` automatically. Deferred to a post-frame callback (safe even if
navigation happens mid-build) and guarded by `manager.isDisposed` both before
scheduling and inside the callback. A throwing `pathOf` is reported via
`FlutterError.reportError` instead of propagating; the route is then treated
as unresolvable (`null`). Router-agnostic — works under vanilla `Navigator`,
GetX and go_router.

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

### `OverlayPredicate`

```dart
typedef OverlayPredicate = bool Function(Map<String, Object?> context);
```

## Deliberate differences from the TS package

- **`stackIndex`/`isTopmost` are N/A** — layer/z-order is entirely up to
  whichever `present:` backend renders the overlay (its own `Overlay`/route
  stack), not something the queue tracks or exposes.
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
the `present:` adapter, and phase transitions. The `example/` app is a full
real-device demo orchestrating GetX + bot_toast + native `showDialog` through
the manager.

## License

MIT — see [LICENSE](LICENSE).

---

# 中文文档

**layerman** 是一个 **headless(无渲染)浮层(overlay)队列管理器**,统一编排
dialog、modal、bottom-sheet、toast、banner:它掌管「**何时 / 展示哪个**」浮层——
带具名 slot、优先级、`replace`、`affix`、`overlap` 的**串行单显**队列——但自己从不
渲染任何东西:每个浮层都通过你提供的 `present:` 后端来显示(`showDialog`、GetX、
`bot_toast`、自行管理的 `OverlayEntry`……)。每个浮层返回命令式的 `Future<T?>` 结果
(像 `showDialog`),并支持**两阶段关闭**,让你的后端能播放自己的退场动画。

它编排**由其它库渲染的浮层**——原生 `showDialog`、GetX(`Get.dialog` /
`Get.snackbar`)、`bot_toast`、`fluttertoast` 等——通过一个小小的适配器
(`present:`),从而用**同一条队列**统管 App 里所有浮层系统。

> 设计说明:本包是框架无关的 headless TS 包 `@codejoo/overlaymanager` 的 Flutter
> 姊妹版。现在它连 headless 这一点也跟对方一致了:核心不 import
> `package:flutter/widgets.dart`,也不持有任何 `Overlay` 层——只保留编排语义。

## 特性

- **串行队列**:每个 slot 一次只显示一个,当前移除后下一个才显示,可设 `gap` 间隔。
- **具名 slot**:相互独立、可并行的多条串行队列(如 `toast` 与 `dialog`)。
- **优先级**:高者先显示,同级 FIFO。
- **`replace`**:抢占当前浮层立即显示(跳过待定 gap;排在已入队项之前);被顶掉的
  浮层会被**关闭**(结果为 `null`)——一个已被 dismiss 的后端没法被如实地重新呈现,
  所以它不会再次显示。
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
- **两阶段关闭**:`close()` 立即兑现结果,然后等待你的后端发出的 `dismissed` 信号,
  外加一个可选的按次 `exitDuration` 宽限,队列才会推进——让后端先播完自己的退场动画。
- **`pauseAll`/`resumeAll`**:整体冻结(不再显示新浮层,`duration` 倒计时暂停);
  以及按 id 的 `pause`/`resume`。
- **自动路由感知**:`LayermanNavigatorObserver` 自动把真实导航喂进 `route` 条件
  (router 无关:vanilla Navigator/GetX/go_router 都行);`pauseOnRoutes` 声明"免打扰区"
  路由,进入自动冻结队列、离开自动恢复,与手动 `pauseAll`/`resumeAll` 干净组合。
  `currentRoute` 读回追踪到的值。
- **`update(id, patch)`**:向已显示浮层的 `data` 浅合并并重建,不改队列;
  **`clearWhere(test)`**:按条件批量移除(如「关闭所有 X 组」)。
- **每浮层的 `delay` 与 `duration`**(自动关闭)。
- **编排外部浮层系统**:一条队列统管 `showDialog`、GetX、`bot_toast`、
  `fluttertoast` 或任何你能显示/关闭的东西。

## 安装

```yaml
dependencies:
  layerman: ^0.2.0
```

```dart
import 'package:layerman/layerman.dart';
```

主包**零第三方运行时依赖**(仅依赖 Flutter SDK)。example 里引入 `get` / `bot_toast`
只是为了演示外部适配器。

## 快速开始

`Layerman` 是一个纯对象——它不挂载任何东西,也不需要在 App 上方包一层
widget。创建一个,用这个项目本来管理共享状态的方式持有它(单例、GetX binding、
`Provider`、DI……都行):

```dart
final manager = Layerman(gap: const Duration(milliseconds: 300));
```

在调用 `open()`/`close()` 的地方拿到它,在调用点给它一个 `present:` 后端——见下面的
[基础用法](#基础用法),下一节讲了为什么这里不再需要挂 scope / attach 这一步。

### 为什么没有 `builder:`

`layerman` 是**队列编排器,不是渲染器**。它只决定*什么时候*、*哪个*浮层显示,从不持有 widget 或 `Overlay` 层。每个浮层都通过你提供的 `present:` 后端来显示。

早先版本有个 `builder:`,返回一个由 manager 挂进它自有 `Overlay` 的 `Widget`。这逼着 manager 自己*变成* UI——要持有 `OverlayState`、要挂在树上、还得配一个 `OverlayManagerScope`,跟这个包存在的唯一意义相悖。

`present:` 是它的严格超集。你在里面构造任意 UI——`showDialog`、`Get.dialog`、`BotToast.show`、`Navigator.push`,或自己插一个 `OverlayEntry`——再返回一个 `PresentedOverlay(dismissed, dismiss)` 句柄。`builder:` 能渲染的,一个自己持有 `OverlayEntry` 的 `present:` 后端照样能渲染——所以什么都没丢,而核心从此 headless(不 import `flutter/widgets`),跟 headless 的 TS 姊妹包对齐。

```dart
// 之前 (0.1.x):manager 挂你的 widget
manager.open(builder: (context, handle) => MyCard(onOk: () => handle.close('ok')));

// 现在 (0.2.0):你自己挂,把关闭信号交回来
manager.open(present: (ctx) {
  final done = Completer<String?>();
  final cancel = BotToast.showWidget(
    toastBuilder: (_) => MyCard(onOk: () => done.complete('ok')),
  );
  done.future.whenComplete(cancel);
  return PresentedOverlay(dismissed: done.future, dismiss: ([r]) async => cancel());
});
```

`showDialog` / `Get.dialog` 场景下,`dismissed` 就是路由 future,`dismiss` 就是针对*本*浮层自己那条路由的 `Navigator.pop` / `Get.back`——见下方 recipe。

## 基础用法

### 给下面这些例子用的共享 `present:` helper

下面每个例子都用 `showDialog` 来显示浮层,包了一层小 helper,关闭时精准定向到*本*
浮层自己那条路由(和[完整 recipe](#原生-showdialog)是同一套模式,这里只是抽出来
方便复用):

```dart
Present<T> dialog<T>(Widget child) => (ctx) {
  final name = 'om://${ctx.id}';
  final future = showDialog<T>(
    context: navigatorKey.currentContext!, // 比如一个 GlobalKey<NavigatorState>
    routeSettings: RouteSettings(name: name),
    builder: (_) => child,
  );
  return PresentedOverlay<T>(
    dismissed: future, // 遮罩点击 / 返回键 / pop 都会兑现它
    dismiss: ([r]) async => Navigator.of(navigatorKey.currentContext!)
        .popUntil((rt) => rt.settings.name != name),
  );
};
```

### 打开并等待结果

```dart
final ok = await manager.open<bool>(
  id: 'confirm-delete',
  present: dialog(Center(
    child: TextButton(
      onPressed: () => Navigator.pop(navigatorKey.currentContext!, true), // 结果 = true
      child: const Text('删除'),
    ),
  )),
);
if (ok == true) doDelete(); // 点遮罩 dismiss -> ok == null
```

`open()` 立即返回一个 `Future<T?>`;浮层可能马上显示,也可能在队列里等待,future 在
它最终关闭时兑现。

### 队列 / 优先级 / replace / affix / overlap

```dart
manager.open(id: 'welcome', present: dialog(const WelcomeSheet()));
manager.open(id: 'promo', priority: 10, present: dialog(const PromoCard())); // 插队靠前

// 抢占当前浮层(它会被关闭,结果 null——已被 dismiss 的后端没法如实重新呈现):
manager.open(id: 'session-expired', replace: true, present: dialog(const ExpiredDialog()));

// 固定当前浮层,replace 顶不掉它:
manager.open(id: 'critical', affix: true, present: dialog(const CriticalDialog()));

// 绕过队列,立刻叠加:
manager.open(id: 'net-error', overlap: true, present: dialog(const ErrorBanner()));

// 并行的独立串行队列:
manager.open(id: 't1', slot: 'toast', present: dialog(const Toast('已保存')));
```

### 条件(`when` / `route` / `requiresAuth` / `setContext`)

排队项若条件不满足只会**等待**;已显示项若条件不再满足会被自动撤下(除非
`dismissWhenUnmet: false`)。

```dart
manager.setContext({'route': '/promo', 'auth': true}); // 把真实导航/登录态喂进来

manager.open(id: 'promo', route: '/promo', present: dialog(const PromoCard()));
manager.open(id: 'inbox', requiresAuth: true, present: dialog(const InboxHint()));
manager.open(
  id: 'vip',
  when: (ctx) => ctx['tier'] == 'gold', // 存在 when 时它是唯一权威
  present: dialog(const VipCard()),
);
```

`route` 保留上下文键 `route`;`requiresAuth` 保留 `auth`;其余键随你在 `when` 里用。

### 自动路由感知(`LayermanNavigatorObserver` + `pauseOnRoutes`)

手动在每个可导航页面的生命周期里写 `setContext({'route': ...})` 是样板代码。
`LayermanNavigatorObserver` 自动帮你做:塞进 `navigatorObservers` 就行,GetX/
go_router/vanilla Navigator 都能用(三者底层最终都是同一个 Flutter Navigator,
这就是标准 `NavigatorObserver`)。纯观察,不 push、不 pop、不碰导航本身。

```dart
MaterialApp(
  navigatorObservers: [LayermanNavigatorObserver(manager)],
  ...
);
```

装上之后,把它当作 `route` 这个上下文键的**唯一写入方**——手动 `setContext({'route': ...})`
只会被下一次导航覆盖掉。想读当前追踪到的路由,用 `manager.currentRoute`,不用自己
再维护一份镜像。path 默认取 `route.settings.name`;路由库存法不同就传 `pathOf` 覆盖。
匿名路由(没设 `settings.name`)会上报 `null`——条件天然匹配不到 `null`,这是 Flutter
对匿名路由没有"path"概念的结构性限制,不是我们的能力缺陷。

两个容易踩的 Flutter 自身行为:

- **`MaterialApp.home` 的隐式路由名字是 `'/'`**,不是 `null`,也不是 `'/home'`——这是
  Flutter 自己的 `Navigator.defaultRouteName`。想让首页按某个特定字符串匹配条件,得用
  `initialRoute`/`routes`(或带名字的 `RouteSettings`)显式命名,别指望 `home:`。
- **推到同一个 `Navigator` 上的路由型弹窗**(上面 `showDialog`/`Get.dialog` 的 recipe
  为了定向关闭需要一个唯一路由名)在它显示期间**确实**是最顶层路由,`route` 会短暂反映
  它的名字——这不是 bug,只是如果你同时用了路由型弹窗和别处的 `route` 条件门控,值得
  知道这个交互。

`pauseOnRoutes` 在这基础上加了个"免打扰区":进入匹配路由会冻结整条队列(和
`pauseAll()` 效果一样,不激活新的);离开会恢复(和 `resumeAll()` 一样)。它跟手动
`pauseAll`/`resumeAll` 是**组合**关系不是互斥——离开免打扰区不会顶掉一次无关的手动
暂停,手动 `resumeAll()` 也不会顶掉一次仍生效的免打扰区。

```dart
final manager = Layerman(pauseOnRoutes: ['/checkout']);
// 追踪到的路由是 '/checkout' 期间,不会有新浮层显示——排队的等着,
// 路由一变就立刻激活。
```

进入免打扰区时"已经在显示的浮层"要不要自动关——**刻意不做统一规则**,用上面同一套
`route`/`when` + `dismissWhenUnmet`(不管哪个 `present:` 后端在渲染这个浮层,规则都
一样),或者依赖某个具体后端自己的路由感知关闭能力。

### 冷却(频次上限 + 持久化)

```dart
manager.open(
  id: 'rate-us',
  cooldown: const OverlayCooldown(total: 3, day: 1, minGap: Duration(hours: 6)),
  present: dialog(const RateUsCard()),
);
```

所有上限按 AND 通过才显示,真正打开时计数。`session` 存内存,其余持久化。生产中接真实
存储并在首次显示前等待 hydrate:

```dart
final manager = Layerman(cooldownStorage: SharedPrefsCooldownStorage());
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
  present: (ctx) {
    final name = 'om://${ctx.id}';
    final future = showDialog<void>(
      context: navigatorKey.currentContext!,
      routeSettings: RouteSettings(name: name),
      builder: (_) => OfferCard(offer: ctx.data as Offer),
    );
    return PresentedOverlay<void>(
      dismissed: future,
      dismiss: ([_]) async => Navigator.of(navigatorKey.currentContext!)
          .popUntil((rt) => rt.settings.name != name),
    );
  },
);
```

`ctx.data` 就是 `resolve` 取回的数据——`PresentContext.data` 是 `resolve` 返回的值
(没写 `resolve` 时,就是你传的那个 `data:`)。

### `beforeClose` 守卫

```dart
manager.open(
  id: 'editor',
  beforeClose: () async => await confirmDiscard(), // 返回 false 否决关闭
  present: dialog(const EditorSheet()),
);
```

`beforeClose` 只拦 `close()`/`dismiss()`;`remove`/`clear`/自动撤下会绕过。

### pause / resume / update / clearWhere

```dart
manager.pauseAll();  manager.resumeAll();   // 整体冻结 / 释放并重排
manager.pause('sheet'); manager.resume('sheet'); // 冻结/恢复单个 duration 倒计时

manager.update('cart', {'count': 3});       // 浅合并进 data,通知监听者,不重排队列
manager.clearWhere((r) => (r.data as Map?)?['group'] == 'promo'); // 按条件批量清
```

`update` 自己不会重建任何东西(manager 不持有任何 widget)——它只是通知监听者;
想反映新 `data` 的 `present:` 后端得靠这个通知自己重建(或者下次构建时读 `data`)。

### 两阶段关闭 / 退场动画

`close()` 兑现结果,并请求你的后端关闭;队列只有在后端的 `dismissed` future
完成后才会推进,外加一个可选的 `exitDuration` 宽限。退场动画完全是你后端自己的事——
在完成 `dismissed` 之前想怎么播就怎么播:

```dart
manager.open<void>(
  id: 'sheet',
  exitDuration: const Duration(milliseconds: 250), // dismissed 之后、队列推进之前的宽限
  present: (ctx) {
    final done = Completer<void>();
    var closing = false;
    late OverlayEntry entry;
    void requestClose() {
      if (closing) return;
      closing = true;
      entry.markNeedsBuild(); // 用你自己的"关闭中"视觉状态重建
      Future.delayed(const Duration(milliseconds: 250), () {
        entry.remove();
        done.complete();
      });
    }

    entry = OverlayEntry(
      builder: (_) => AnimatedOpacity(
        opacity: closing ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: const MySheet(),
      ),
    );
    Overlay.of(navigatorKey.currentContext!).insert(entry);
    return PresentedOverlay<void>(
      dismissed: done.future,
      dismiss: ([_]) async => requestClose(),
    );
  },
);

manager.close('sheet'); // -> dismiss() -> requestClose() 播完淡出再兑现
```

### 命令式控制与内省

```dart
manager.close('sheet', someResult); // 带结果的两阶段关闭
manager.dismiss('sheet');           // 以 null 关闭
manager.remove('sheet');            // 立即移除,无退场宽限
manager.clear();                    // 移除全部(排队 + 活跃)

manager.isShowing('sheet'); manager.activeIds; manager.queuedIds;
manager.isPaused;
```

`Layerman` 是 `ChangeNotifier`,可 `addListener` / `AnimatedBuilder` 在每次
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
- `exitDuration` 是「**dismiss 之后**、队列推进之前」的宽限期(路由 future
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

### 把导航到的页面也塞进队列

一个被 push 的 `Route`本质上就是另一种外部 presenter——`Navigator.push` 本来就
返回一个 pop 时 resolve 的 `Future<T?>`,跟 `showDialog` 一模一样。用同样的方式包
一层,就能让这个页面参与队列(占 slot、受 `priority`/`replace` 管辖、显示期间挡住
其它浮层)——push 这个动作只有轮到才会真正执行:

```dart
manager.open<void>(
  id: 'checkout',
  present: (ctx) {
    final future = navigatorKey.currentState!.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/checkout'),
      builder: (_) => const CheckoutPage(),
    ));
    return PresentedOverlay<void>(
      dismissed: future,
      dismiss: ([_]) async => navigatorKey.currentState!.pop(),
    );
  },
);
```

(`navigatorKey` 是传给 `MaterialApp` 的 `GlobalKey<NavigatorState>`——`present`
回调拿到的是 `PresentContext`,不是 `BuildContext`,跟上面所有 `present:` recipe
的要求一样。)

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
   `Navigator` 之上的 `Stack` 里);返回键归各后端。z 序完全由你的 `present:` 后端
   决定——想要明确控制,就在你自己的 `OverlayEntry` 里插到你要的深度。

## 完整 API 参考

见上文英文的 [Full API reference](#full-api-reference) 表格,列出了所有导出符号:
`Layerman`(构造 + 全部方法/getter,含 `pauseOnRoutes`/`currentRoute`)、
`open<T>` 的每个参数、`LayermanNavigatorObserver`、`OverlayCooldown`、
`OverlayCooldownStorage` / `MemoryCooldownStorage`、`OverlayRecord`、
`Present` / `PresentContext` / `PresentedOverlay`、`OverlayPredicate`。

## 与 TS 版的刻意差异

- **不做 `stackIndex`/`isTopmost`**:层/z 序完全交给渲染这个浮层的 `present:` 后端
  (它自己的 `Overlay`/路由栈),队列本身不追踪也不暴露这个概念。
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
pause/resume、`update`/`clearWhere`、`present:` 适配器、相位切换。`example/` 是一个
完整的真机 demo,通过管理器编排 GetX + bot_toast + 原生 `showDialog`。

## 许可

MIT —— 见 [LICENSE](LICENSE)。
