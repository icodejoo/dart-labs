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

- **Don't show again** — result-based `suppress`, permanent or timed, for submissions with `cooldown`.
- **Cross-slot blocking** — `OverlaySlotOptions.blockedBy` holds new activations while another slot is occupied.

- **1.0 typed contracts** — `mode: OverlayMode.queue/replace/overlap`, `RouteMatcher`
  and `OverlayPhase` eliminate ambiguous options and string phase comparisons.
- **Inspection and grouping** — `cooldownStatus` (`OverlayCooldownStatus`),
  `resetCooldown` / `clearCooldowns`, and copied `tags` / `clearTag`.
- **Frame-safe submission** — `open` defers presentation and notifications during
  `build()`; manager notifications are batched per operation; unused slots are reclaimed.

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
- **`overlap`** — bypass the queue and stack on top (global alerts,
  blocking loaders). After `delay`, conditions/cooldown act as a now-or-never fire-gate.
- **Conditions** — the AND of `route`, `auth(ctx)` and `when(ctx)`, driven by `setContext({...})`; a shown
  overlay whose conditions stop holding is auto-dismissed (`dismissWhenUnmet`,
  default true — queued entries just wait).
- **Cooldown** — `OverlayCooldown(session:, total:, day:, hour:, minute:,
  minGap:)`, all present caps AND together and count on real open; persisted
  through a pluggable `OverlayCooldownStorage` (default in-memory; back it with
  `shared_preferences` in real apps). A **time-based** cap (`minGap` + bucket
  rollover) auto-shows the queued entry the moment it expires.
- **Backend-driven `resolve`** — fetch the payload only when the overlay is
  granted the slot; returning `null` skips it. The slot is committed while
  resolving; ordinary arrivals wait, but `replace` can preempt and discard it.
- **`beforeClose` guard** — return `false` (sync or async) to veto a `close()`
  (unsaved-changes confirmations); `remove`/`clear` bypass it.
- **`Future<T?>` results** — `open()` returns a future that resolves with the
  value you close with, or `null` when dismissed.
- **Two-phase close** — `close()` settles the result immediately, then waits
  for your backend's `dismissed` signal (bounded by `dismissTimeout`) plus an optional per-`open()`
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
  notify listeners, without rendering or changing the queue. `PresentContext.data`
  is a snapshot at presentation; `dataListenable` supplies live values.
  **`clearWhere(test)`** — selective mass
  removal (e.g. "close everything of group X").
- **Per-overlay `delay` and `duration`** (auto-close).
- **Orchestrates external overlay systems** — one queue over `showDialog`,
  GetX, `bot_toast`, `fluttertoast`, or anything you can show/close.

- **Route presenters** — reusable `DialogManager`, `BottomSheetManager`, and `presentRoute`.
- **Tickets and events** — typed `submit<T>`, outcomes with reasons, asynchronous events.
- **Independent pause sources** — `hold()` and automatic `LayermanLifecycle` binding.
- **Bounded waiting** — resolve/dismiss timeouts, `expireAfter`, per-slot `gap` / `maxQueued`.
- **Live data and diagnostics** — `dataListenable`, `resolvingIds`, `records`, `recordOf`.

## Install

```yaml
dependencies:
  layerman: ^1.0.0
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

`present:` is a strict superset. Inside it you build any UI — `showDialog`, `Get.dialog`, `BotToast.show`, `Navigator.push`, or an `OverlayEntry` you insert yourself — and hand back a `PresentedOverlay(visible: ..., dismissed: ..., dismiss: ...)` handle. Anything `builder:` could render, a `present:` backend that owns its own `OverlayEntry` renders too — so nothing is lost, and the core is now headless (no `flutter/widgets` import), matching the headless TS sister package.

```dart
manager.open(present: (ctx) {
  final visible = Completer<void>();
  final done = Completer<String?>();
  final cancel = BotToast.showWidget(
    toastBuilder: (_) => OverlayVisibility(
      visible: visible,
      child: MyCard(onOk: () => done.complete('ok')),
    ),
  );
  done.future.whenComplete(cancel);
  return PresentedOverlay<String>(
    visible: visible.future,
    dismissed: done.future,
    dismiss: ([r]) async {
      cancel();
      if (!done.isCompleted) done.complete(r);
    },
  );
});
```

For route-based dialogs, use `DialogManager` or retain your own Route object: use `route.completed`
for `dismissed` and close that exact route through its own navigator — see the recipes below.

## Usage

### Shared route presenters

Create these once alongside `manager`. Pass the same `navigatorKey` to your app;
call `open` after that Navigator is mounted. The examples use `dialogs((ctx, close) => widget)`.

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final dialogs = DialogManager(navigatorKey);
final sheets = BottomSheetManager(navigatorKey);

// Mount this once in your app:
final app = MaterialApp(navigatorKey: navigatorKey, home: const Scaffold());
```

### Open and await a result

```dart
final ok = await manager.open<bool>(
  id: 'confirm-delete',
  present: dialogs((ctx, close) => Center(
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

### Migrating from 0.x

See the [1.0.0 migration table in CHANGELOG](CHANGELOG.md#100) for every breaking change.

### Building overlays during `build()`

`open` automatically defers `present` and manager notifications until after the
frame when invoked during `build()`. Submission still returns its future immediately;
queued entries retain ordering, and pause/conditions/hydration are checked before
presentation. Guard repeated builds so they do not submit repeatedly:

```dart
class PromoTrigger extends StatefulWidget {
  const PromoTrigger({super.key, required this.manager, required this.present});
  final Layerman manager;
  final Present<void> present;

  @override
  State<PromoTrigger> createState() => _PromoTriggerState();
}

class _PromoTriggerState extends State<PromoTrigger> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    if (!_submitted) {
      _submitted = true;
      widget.manager.open<void>(id: 'build-promo', present: widget.present);
    }
    return const SizedBox.shrink();
  }
}
```

### Notifications are batched per operation

A public operation emits at most one manager notification after its synchronous
changes finish. Async continuations form separate batches. Calls during build are
coalesced after the frame; `dataListenable` and async `events` remain separate channels.

### Tags

`tags` defaults to an empty set and is copied at submission into read-only
`OverlayRecord.tags`. `clearTag(tag)` removes matching pending, resolving, open
and closing entries with `removed`, bypassing `beforeClose`.

```dart
manager.open<void>(id: 'campaign', tags: {'promo', 'home'},
  present: dialogs<void>((ctx, close) => const Text('Campaign')));
final record = manager.recordOf('campaign');
if (record?.phase == OverlayPhase.open) {
  manager.clearTag('promo');
}
```

### Queue, priority, replace, affix, overlap

`mode` selects exactly one `OverlayMode`: `queue` (default), `replace` or `overlap`.
`affix` is independent; replace and overlap cannot be combined.

```dart
// These queue behind one another (serial, one at a time):
manager.open(id: 'welcome', present: dialogs((ctx, close) => const WelcomeSheet()));
manager.open(id: 'promo', priority: 10, present: dialogs((ctx, close) => const PromoCard())); // jumps ahead

// Preempt whatever is currently showing in the default slot (it is closed,
// result null — a dismissed backend can't be faithfully re-presented):
manager.open(id: 'session-expired', mode: OverlayMode.replace, present: dialogs((ctx, close) => const ExpiredDialog()));

// Protect the current overlay so a replace cannot cover it:
manager.open(id: 'critical', affix: true, present: dialogs((ctx, close) => const CriticalDialog()));

// Bypass the queue; judge eligibility after the delay:
manager.open(id: 'net-error', mode: OverlayMode.overlap, delay: const Duration(seconds: 1), present: dialogs((ctx, close) => const Text('Network error')));

// Independent serial queues that run in parallel:
manager.open(id: 't1', slot: 'toast', present: dialogs((ctx, close) => const Toast('Saved')));
```

`RouteMatcher.exact('/promo')` matches one path;
`const RouteMatcher.anyOf(['/promo', '/home'])` matches any listed path;
`RouteMatcher.regex(RegExp(r'^/promo/'))` uses `hasMatch`. Null and non-string
context routes never match.


Overlap honors `delay`: it waits first, then applies the now-or-never eligibility
check. Remove, clear, same-id reopen and dispose cancel the waiting entry.
Pause and pending hydration can hold it further; it never joins a serial slot.

### Conditions (`when` / `route` / `auth` / `setContext`)

Overlays can gate on an app-wide context you push with `setContext`. A queued
overlay whose conditions don't hold simply **waits**; a *shown* overlay whose
conditions stop holding is auto-dismissed unless `dismissWhenUnmet: false`.

```dart
// Feed your real navigation / auth state into the manager:
manager.setContext({'route': '/promo', 'auth': true});

// Sugar: show only on a route (RouteMatcher.exact / anyOf / regex) ...
manager.open(id: 'promo', route: const RouteMatcher.exact('/promo'), present: dialogs((ctx, close) => const PromoCard()));
// ... only when authenticated ...
manager.open(id: 'inbox', auth: (ctx) => ctx['auth'] == true, present: dialogs((ctx, close) => const InboxHint()));
// Additional conditions are combined with route and auth using AND:
manager.open(
  id: 'vip',
  when: (ctx) => ctx['tier'] == 'gold' && ctx['route'] == '/home',
  present: dialogs((ctx, close) => const VipCard()),
);
```

`route`, `auth` and `when` are combined with **AND**; omitted conditions pass.
Only `route` reads a reserved key (`route`). `auth` and `when` read any keys you
push with `setContext`; the engine never reads an `auth` key on its own.
A throwing `auth` or `when` is reported once per entry and treated as unmet.
Conditions are push-driven: external state changes require `setContext`, even
`setContext({})`, or another scheduling trigger. They do not wake on time alone.

Judgment callbacks (`when`, `auth`, and the test passed to `clearWhere`) are read-only.
Any manager mutation, ticket/context operation, hold release or dispose during them throws
`StateError` (“判断函数内不能修改 Layerman”) before changing state. Condition errors are
reported once per entry and treated as unmet; `clearWhere` test errors propagate. Getters remain available.

### Login and roles (`auth:` predicate)

```dart
manager.setContext({'signedIn': true, 'role': 'admin', 'route': '/admin'});
manager.open<void>(
  id: 'admin-hint',
  route: const RouteMatcher.exact('/admin'),
  auth: (ctx) => ctx['signedIn'] == true && ctx['role'] == 'admin',
  when: (ctx) => ctx['maintenance'] != true,
  present: dialogs<void>((ctx, close) => const Text('Admin')),
);
```

To migrate `requiresAuth: true`, use `auth: (ctx) => ctx['auth'] == true`;
for the former guest-only `requiresAuth: false`, use `auth: (ctx) => ctx['auth'] != true`.
Your app chooses the keys and role/permission policy.

### Auto route awareness (`LayermanNavigatorObserver` + `pauseOnRoutes`)

Feeding `route` into `setContext` by hand (in every navigable page's lifecycle)
is boilerplate. `LayermanNavigatorObserver` does it for you — add it to
`navigatorObservers` and it works under vanilla `Navigator`, GetX and
go_router alike, since all three ultimately drive a real Flutter `Navigator`
and this is a standard `NavigatorObserver`. It's purely observational: it
never pushes, pops, or otherwise touches navigation.

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  navigatorObservers: [LayermanNavigatorObserver(manager)],
  home: const Scaffold(),
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
- **Since 0.3.0 only `PageRoute` is tracked by default.** Dialogs, bottom
  sheets and menus leave the last accepted page path intact, so route-gated
  dialogs no longer dismiss themselves and popups cannot release a no-overlay zone.
  To restore 0.2.x behavior, pass `routeFilter: (r) => true`.
- Use `contextKey: 'tabRoute'` for a nested Navigator and read it in `when`.
  `route:` and `pauseOnRoutes` still read only the default `route` key.

`pauseOnRoutes` builds a "no-overlay zone" on top of this: entering a matching
route freezes the whole queue (exactly like `pauseAll()` — nothing new
activates); leaving it resumes (like `resumeAll()`). It composes with manual
`pauseAll`/`resumeAll` rather than fighting them — leaving the zone doesn't
override an unrelated manual pause, and a manual `resumeAll()` doesn't
override an active zone.

```dart
final manager = Layerman(pauseOnRoutes: const [RouteMatcher.exact('/checkout')]);
// While the tracked route is '/checkout', no new overlay shows — queued ones
// wait and activate the moment the route changes away.
```

Whether an *already-shown* overlay should close when you navigate into a zone
is deliberately not a blanket rule — use the same `route`/`when` +
`dismissWhenUnmet` conditions covered above (they work the same no matter which
`present:` backend is rendering the overlay), or lean on a specific backend's
own navigation-aware close option if it has one.

### `DialogManager` / `BottomSheetManager`

Create once with the app's `navigatorKey`; only configuration is retained, each
presentation owns its Route. The builder's `close([result])` always delegates to
`ctx.close` and runs `beforeClose`. Instances can be reused across managers.
Back, barrier and drag dismissals are backend paths and bypass the guard.
Per-call non-null options override constructor defaults:

```dart
manager.open<bool>(
  present: sheets<bool>(
    (ctx, close) => TextButton(onPressed: () => close(true), child: const Text('Done')),
    isScrollControlled: true,
    barrierDismissible: false,
  ),
);
```

Both default to `barrierDismissible: true`, `useSafeArea: true` and
`routeNamePrefix: 'layerman://'`. Colors fall back to the theme (dialogs finally
use `Colors.black54`). Sheets also default to `isScrollControlled: false`,
`enableDrag: true`, `showDragHandle: null`, `backgroundColor: null`.
Use `presentRoute` for pages or custom Route construction; see the manual recipe below.

### Outcome / tickets / events

`submit<T>` accepts exactly the same arguments as `open<T>`, returning an
`OverlayTicket<T>`. `result` is `Future<T?>`; `outcome` is
`Future<OverlayOutcome<T>>` with `value` and the first `reason`. Settlement precedes
exit animation completion. Typed `ticket.close([T? result])` honors the guard;
`remove()` bypasses it, `update(patch)` updates data, and `data` is a
`ValueListenable<Object?>`. Old tickets cannot control a newer submission with the
same id. `isActive` includes pending/resolving/closing while still tracked.
`events` is an asynchronous broadcast stream: `queued`, `shown`, `ended`
(`OverlayEventType`), with `id`, `slot`, `type` and optional `reason`; subscribe
before submitting (no replay). `ended` means first settlement, not animation end.

```dart
final subscription = manager.events.listen((event) {
  debugPrint('${event.id}: ${event.type} ${event.reason}');
});
final ticket = manager.submit<bool>(
  id: 'decision',
  present: dialogs<bool>((ctx, close) => AlertDialog(
    actions: [TextButton(onPressed: () => close(true), child: const Text('OK'))],
  )),
);
ticket.update({'count': 1});
final outcome = await ticket.outcome;
debugPrint('${outcome.value}: ${outcome.reason}');
await subscription.cancel();
```

For each submission, events follow queued → shown → ended, even when `present` closes the
entry synchronously; a presentation that throws emits no shown event, only ended (`failed`).

### Pause sources: `hold` and `LayermanLifecycle`

Manual pause, `pauseOnRoutes` and unreleased holds combine with OR. `hold(reason)`
returns an `OverlayHold`; `release()` is idempotent, `holdCount` counts holds only.
Releasing one source never cancels another. `LayermanLifecycle` acquires a hold
on `AppLifecycleState.paused` or `hidden` by default (`pauseOn` overrides the set),
and releases it on other states. `attach()` synchronizes immediately; `detach()`
unregisters and releases. Both are idempotent; detach when replacing the owner.

```dart
final lifecycle = LayermanLifecycle(manager)..attach();
final hold = manager.hold('payment');
try {
  await Future<void>.delayed(const Duration(milliseconds: 100));
} finally {
  hold.release();
}
// When the app owner is disposed or the manager is replaced:
lifecycle.detach();
```

### Timeouts, `expireAfter` and per-slot options

`dismissTimeout` defaults to 10 seconds after requesting backend dismissal;
`resolveTimeout` defaults to 30 seconds. Both constructor options accept `null`
for no timeout. A per-entry `resolveTimeout: null` inherits; `Duration.zero`
disables that entry's resolve timeout. Zero at constructor level schedules an
immediate timeout; it does not disable it. Timeouts report `TimeoutException`
through `FlutterError.reportError` and release the slot. Resolve timeout ends as
`skipped`; dismiss timeout preserves the already-settled result/reason. Neither
cancels the backend's underlying work or guarantees removal of its UI.
`expireAfter` counts serial waiting time before activation, including pauses;
it does not apply to overlap or active entries (`queueExpired`). Slot `gap`
overrides global `gap`; positive `maxQueued` excludes active entries and evicts
the sorted queue tail (`queueFull`), which may be the newly submitted entry.
These deadlines keep running during pause; only `duration` freezes.

```dart
final bounded = Layerman(
  dismissTimeout: const Duration(seconds: 10),
  resolveTimeout: const Duration(seconds: 30),
  slots: const {
    'notice': OverlaySlotOptions(gap: Duration(milliseconds: 200), maxQueued: 3),
  },
);
final boundedDialogs = DialogManager(navigatorKey);
bounded.open<String>(
  slot: 'notice',
  expireAfter: const Duration(minutes: 1),
  resolveTimeout: Duration.zero,
  resolve: () async => 'Ready',
  present: boundedDialogs<String>((ctx, close) => Text(ctx.data as String)),
);
// The owner eventually calls bounded.dispose().
```

Serial `delay` waits after the slot gap; `replace` and same-id active takeover skip it.
The delay belongs to its waiting entry: removing or overwriting that entry cancels the old
wait and reschedules the slot. `maxQueued` is enforced after activation decisions, including
post-frame scheduling during build; entries waiting for gap, delay, conditions, cooldown or
blockedBy still count, and the submitted entry can still be evicted.

#### Cross-slot blocking (`blockedBy`)

```dart
final manager = Layerman(slots: {
  'toast': OverlaySlotOptions(blockedBy: {'modal'}),
  'banner': OverlaySlotOptions(blockedBy: {'modal'}),
});
```

`OverlaySlotOptions.blockedBy` is a `Set<String>`, empty by default. While a listed slot
is occupied, this slot activates no new entries. Occupied means a serial active entry
(resolving/open/closing, including `exitDuration` grace), or an active overlap in that slot.
Gap, appear delay, cooldown waits, queues and waiting overlaps **do not count**.
Entries can therefore appear between two blocker entries. **Already activated entries
keep showing and their duration continues**: a toast visible before a modal stays visible.

Blocked serial entries queue; `expireAfter` and `maxQueued` still apply. Replace does not
preempt while blocked and keeps its front-band order after release. Same-id serial reopen
queues with takeover precedence when eligible. Overlaps that pass initial eligibility are
held, then rechecked now-or-never on release.
Release happens at the outermost operation batch end, so replace's remove-old/activate-new
transition cannot let another slot slip through. Only slots actually waiting for unblock
and held overlaps are reconsidered; this adds no condition trigger for other slots.
Cycles follow first activation without fairness guarantees. A nonexistent slot name has
no effect; self-blocking triggers a debug assertion.

### Live data (`dataListenable`)

`PresentContext.data` is a snapshot; listen to `dataListenable` for `update`
and resolved values. `ticket.data` exposes the same channel, retaining its last
value after settlement. The manager deliberately does not dispose this listenable,
so listeners can detach after exit animations; remove manually registered listeners
when your backend is disposed.

```dart
manager.open<void>(
  id: 'cart',
  data: {'count': 1},
  present: dialogs<void>((ctx, close) => ValueListenableBuilder<Object?>(
    valueListenable: ctx.dataListenable,
    builder: (_, value, __) => Text('${(value as Map)['count']}'),
  )),
);
manager.update('cart', {'count': 2});
```

When both the current data and the patch are string-keyed Maps (`Map<String, Object?>` /
`Map<String, dynamic>`), the shallow merge keeps `Map<String, Object?>`, so a backend cast such as
`value as Map<String, dynamic>` keeps working; other Map combinations merge into a generic Map.

### Cooldown (frequency caps + persistence)

```dart
manager.open(
  id: 'rate-us',
  cooldown: const OverlayCooldown(
    total: 3,                        // at most 3 times ever
    day: 1,                          // at most once per local day
    minGap: Duration(hours: 6),      // and at least 6h apart
  ),
  present: dialogs((ctx, close) => const RateUsCard()),
);
```

**1.0.0 completion of the 0.3.0 behavior:** exhausted `session` / `total` caps
settle serial submissions as `null` (`capped`) immediately at submission, and
queued entries are checked again after hydration, even while the slot is occupied
or the manager paused. Use time-based caps for retryable waits or a new id for a new campaign.

All present caps must pass (AND); a cap counts when the overlay actually opens.
Counters are keyed by `id`, so a cooldown needs an explicit `id` (asserted in
debug — an auto-generated id changes on every open). `session` lives in memory;
the rest persist. Back the store with real storage:

```dart
final manager = Layerman(
  cooldownStorage: SharedPrefsCooldownStorage(), // your OverlayCooldownStorage
  storageKey: 'layerman:cooldown',
);
await manager.ready(); // optional: counters loaded + queue re-scheduled
```

Until the store has hydrated, **every submission with `cooldown`** waits, including
session-only and empty configurations, because suppression is persisted. Serial entries
queue; overlaps are held rather than dropped. Submissions without `cooldown` are unaffected.
Migration: session-only entries that previously appeared before `ready()` now wait for
one storage read. Opening before `ready()` remains safe. A failed read or write is
reported via `FlutterError.reportError` and never blocks scheduling.

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

`cooldownStatus(id, cooldown)` returns `OverlayCooldownStatus`: `canShow` means
all caps and suppression pass; `permanentlyBlocked` means session/total exhaustion or permanent suppression. `wait` is
`Duration.zero` when eligible, the longest remaining time wait otherwise, or
`null` when permanently blocked or awaiting cooldown-store hydration.
`suppressed` reports an unexpired timed or permanent suppression. Before hydration,
`canShow` is false and `wait` is null; `permanentlyBlocked` and `suppressed` still
reflect known in-memory state (including exhausted session or locally set permanent suppression).
`resetCooldown(id)` clears that id's session/persisted counters and suppression;
`clearCooldowns()` clears all counters and suppression. Both re-evaluate waiting entries and
persist the reset. Resetting cannot restore entries already ended as `capped` or `suppressed`.

```dart
const cap = OverlayCooldown(session: 2, minGap: Duration(minutes: 5));
final status = manager.cooldownStatus('promo', cap);
if (status.canShow) {
  manager.open<void>(id: 'promo', cooldown: cap,
    present: dialogs<void>((ctx, close) => const Text('Promo')));
}
manager.resetCooldown('promo');
manager.clearCooldowns();
```

Day / hour / minute caps follow the local calendar even when the clock returns UTC (for example
server time). A malformed stored record is reported and skipped; its raw value is written back
unchanged until a valid record for the same id replaces it or `resetCooldown` / `clearCooldowns`
removes it, so other ids keep their counts and suppressions.

#### Don't show again (`suppress`)

The card closes with `'never'`, `'later'` or `null`; suppress according to that result.
`const OverlayCooldown()` sets no count limits and only honors suppression:

```dart
Future<void> showPromo(Layerman manager, Present<String> present) async {
  final r = await manager.open<String>(
    id: 'promo',
    cooldown: const OverlayCooldown(),
    present: present,
  );
  if (r == 'never') manager.suppress('promo');
  if (r == 'later') {
    manager.suppress('promo', duration: const Duration(days: 3));
  }
}

// e.g. a settings switch: shown while suppressed; resetCooldown('promo') re-enables.
bool promoSuppressed(Layerman manager) =>
    manager.cooldownStatus('promo', const OverlayCooldown()).suppressed;
```

`Layerman.suppress(String id, {Duration? duration})` suppresses from now for a
positive `duration`; null means forever. It **only gates submissions with `cooldown:`**.
A manual open without cooldown remains available, for example “View campaign” in settings.
Already activated entries are unaffected. Suppression shares the counter record (JSON key
`su`); `resetCooldown(id)` / `clearCooldowns()` also clear it.
Repeated calls keep the later expiry, with forever winning: suppression only extends.
Thus “suppress three days on any close, then forever on never” works in either order.
Shortening requires a reset, which also clears counters.

Permanent suppression immediately ends queued serial entries with `OverlayEndReason.suppressed`,
even while paused, occupied or awaiting hydration. Timed suppression leaves serial entries
waiting and self-wakes at expiry (or a later time-based cap); `expireAfter` can bound that wait.
Overlap checks at its delay deadline or release and discards as suppressed when suppression
blocks its cooldown. Cooldown rejection reasons take precedence as `suppressed > capped > dropped`;
a failed route/auth/when condition still yields `dropped`.
Permanent suppression gives `permanentlyBlocked: true, wait: null`; timed suppression's
`wait` is the maximum of remaining suppression and other time-based waits (unless permanently
blocked or awaiting hydration).

### Backend-driven `resolve`

Fetch data only when granted the slot. `resolve` has type `Future<T?> Function()?`,
using the same `T` as the result. Returning `null` skips without counting cooldown.
Ordinary arrivals wait while resolving; `replace` can preempt and discard it.
`ctx.data` contains the resolved value.

```dart
manager.open<String>(
  id: 'offer',
  resolve: () async => 'Today’s offer',
  present: dialogs<String>((ctx, close) => AlertDialog(
    content: Text(ctx.data as String),
    actions: [TextButton(onPressed: () => close('accepted'), child: const Text('OK'))],
  )),
);
```

### Closing from inside a backend (`ctx.close`)

`PresentContext<T>.close([T? result])` closes its own submission through
`beforeClose`. It binds entry identity: an old callback cannot close a reopened
entry with the same id. Non-open entries and pending guards ignore close calls.
Backend-driven barrier/back dismissal still bypasses the guard.

```dart
manager.open<bool>(
  beforeClose: () => true,
  present: (ctx) => presentRoute<bool>(
    navigatorKey.currentState!,
    DialogRoute<bool>(
      context: navigatorKey.currentContext!,
      builder: (_) => TextButton(
        onPressed: () => ctx.close(true),
        child: const Text('Done'),
      ),
    ),
  ),
);
```

### `beforeClose` guard

```dart
manager.open(
  id: 'editor',
  beforeClose: () async => await confirmDiscard(), // false vetoes the close
  present: dialogs((ctx, close) => const EditorSheet()),
);
```

`beforeClose` gates `close()`/`dismiss()` only — `remove`/`clear`/auto-dismiss
bypass it. While an async guard is pending, further `close()`/`dismiss()` calls
for that overlay are ignored, so a double tap doesn't ask twice.

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

`update` shallow-merges Maps (otherwise replaces), notifies `dataListenable`
and manager listeners, and leaves the queue alone. Read live values through
`PresentContext.dataListenable`; `PresentContext.data` remains the presentation snapshot.

### Two-phase close / exit animation

`close()` settles the result and asks your backend to close; the queue only
advances after backend `dismissed` plus optional `exitDuration` grace,
or when the `dismissTimeout` watchdog releases the entry. The exit animation itself is entirely your
backend's job. Route backends use `route.completed`, which completes after the
exit animation with the pop result; the future returned by `showDialog` or
`Navigator.push` completes when pop starts. Reserve `exitDuration` for backends
without an animation-end signal. A custom backend can complete `dismissed` itself:

```dart
manager.open<void>(
  id: 'sheet',
  present: (ctx) {
    final visible = Completer<void>();
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
        child: OverlayVisibility(visible: visible, child: const MySheet()),
      ),
    );
    navigatorKey.currentState!.overlay!.insert(entry);
    return PresentedOverlay<void>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([_]) async => requestClose(),
    );
  },
);

manager.close('sheet'); // settles now; dismiss() plays the fade before the slot advances
```

`resolvingIds` lists resolving entries (also overlaps); `records` includes every
managed phase and `recordOf(id)` returns one snapshot or `null`. `queuedIds` follows
actual replace/priority/FIFO order within each slot, followed by held overlaps;
independent slots have no global display order.

### Imperative control & introspection

```dart
manager.close('sheet', someResult); // two-phase close with a result
manager.dismiss('sheet');           // close with null
manager.remove('sheet');            // remove immediately, no exit grace
manager.clear();                    // remove everything (queued + active)

manager.isShowing('sheet'); // bool — open/closing only
manager.activeIds;          // open/closing ids (serial + overlaps)
manager.queuedIds;          // pending ids, ordered within each slot
manager.resolvingIds;
manager.records;
manager.recordOf('sheet');
manager.isPaused;           // bool
```

A resolving entry is listed in `resolvingIds` and `records`, while excluded from
`activeIds` / `queuedIds`; `isShowing` is false until it opens.

`Layerman` is a `ChangeNotifier`, so `addListener` / `AnimatedBuilder`
can rebuild UI (e.g. a debug HUD) on every transition.

## Integrating other overlay libraries (the `Present` adapter)

A project rarely has just one overlay system. `open(present: ...)` lets the
manager **schedule** overlays that are **rendered by another library**: the
`present` callback runs only when the queue grants permission, and returns a
bidirectional handle:

```dart
PresentedOverlay<T>(
  visible: firstPaintVisible,       // Future<void>: successful first visible frame
  // Waiting visible uses phase=open and occupies its slot; duration already runs.
  // visible error => failed; an earlier end keeps its reason and has no shown.
  // Only visible success while still open records cooldown and emits shown.
  dismissed: someFuture,            // the backend's "fully closed" signal (any path)
  dismiss: ([T? result]) async {},  // orchestrator-driven, targeted close
)
```

- `await open(...)` resolves with the `result` passed to `close(id, result)`
  when the manager closes it, otherwise with the value **`dismissed`**
  completes with — so complete `dismissed` on *every* close path (user tap,
  barrier, back button, timeout, your `dismiss`).
- `close` / `replace` / `clear` / `remove` drive **`dismiss`** to close the
  backend on the manager's behalf.
- Route backends use **`route.completed`** for `dismissed`: it waits for the
  exit animation and carries the pop result. `showDialog` / `Navigator.push`
  futures complete when pop starts. Reserve `exitDuration` (a post-`dismissed`
  grace period) for backends without an animation-end signal.

The whole point: a single serial queue (plus priority / replace / cooldown /
conditions) now governs dialogs, snackbars and toasts from different libraries
uniformly.

### Native `showDialog`

Prefer `DialogManager` for dialogs. Hand-written Route recipe for custom control:
`presentRoute` pushes your route, waits for `route.completed`, and targets that
exact route when closing. No `exitDuration` estimate is needed. A top route is
popped with the result only when it has no internal history; a covered route uses `removeRoute(route)` without a result
for Flutter 3.27 compatibility. `manager.close` still delivers its requested result.
Closing a covered route directly through the returned handle yields `null`.

A route with internal history (for example an open Drawer or persistent bottom sheet) also
uses `removeRoute`; its result follows the same rules as a covered route.

```dart
manager.open<bool>(
  id: 'confirm',
  present: (ctx) {
    final navigator = navigatorKey.currentState!;
    final route = DialogRoute<bool>(
      context: navigator.context,
      settings: RouteSettings(name: 'layerman://${ctx.id}'),
      builder: (_) => const AlertDialog(content: Text('Confirm?')),
    );
    return presentRoute(navigator, route);
  },
);
```

### GetX dialog / bottom sheet

`Get.dialog` / `Get.bottomSheet` do not expose their Route objects. Push a
`DialogRoute` directly on the same Navigator (`Get.key.currentState!`):

```dart
manager.open<bool>(
  id: 'confirm',
  present: (ctx) {
    final navigator = Get.key.currentState!;
    final route = DialogRoute<bool>(
      context: navigator.context,
      settings: RouteSettings(name: 'om://${ctx.id}'),
      builder: (_) => const ConfirmDialog(),
    );
    // 成功构建、挂载且位于栈顶的首帧才确认可见。
    return presentRoute(navigator, route);
  },
);
```

For a bottom sheet, replace only the `route` construction above; keep the same
push, `route.completed`, and targeted dismiss logic. `isScrollControlled` is required:

```dart
final route = ModalBottomSheetRoute<bool>(
  settings: RouteSettings(name: 'om://${ctx.id}'),
  builder: (_) => const ConfirmDialog(),
  isScrollControlled: false,
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
    final visible = Completer<void>();
    final c = Get.snackbar('Saved', 'Your changes are safe.',
      messageText: OverlayVisibility(visible: visible, child: const Text('Your changes are safe.')),
    );
    return PresentedOverlay<void>(visible: visible.future,
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

Use `presentRoute` with a `TransitionRoute<T>` for pages. The push happens only
when the queue grants the slot; the page occupies it until its exit completes.

```dart
manager.open<bool>(
  id: 'checkout',
  present: (_) => presentRoute(
    navigatorKey.currentState!,
    MaterialPageRoute<bool>(
      settings: const RouteSettings(name: '/checkout'),
      builder: (_) => const Scaffold(body: Text('Checkout')),
    ),
  ),
);
```

### bot_toast

Disarm its own competing semantics: `onlyOne: false` and a dedicated
`groupKey`; `onClose` is the single "fully closed" signal; the `CancelFunc`
plays its exit animation.

```dart
manager.open<void>(
  id: 'tip',
  slot: 'toast',
  present: (ctx) {
    final visible = Completer<void>();
    final done = Completer<void>();
    final cancel = BotToast.showCustomText(
      toastBuilder: (_) => OverlayVisibility(visible: visible, child: Card(child: Text('Copied to clipboard'))),
      onlyOne: false,               // replace decisions belong to the manager
      onClose: () => done.complete(), // fires after the exit animation
    );
    return PresentedOverlay<void>(visible: visible.future,
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
    // 原生 showToast 没有可见回报；使用可确认首帧的 FToast widget。
    final visible = Completer<void>();
    final done = Completer<void>();
    final toast = FToast()..init(navigatorKey.currentContext!); // 已挂载页面中、Overlay 下的 context。
    toast.showToast(
      child: OverlayVisibility(visible: visible, child: const Card(child: Text('Copied'))),
      toastDuration: const Duration(seconds: 2),
    );
    final timer = Timer(const Duration(seconds: 2), () {
      if (!done.isCompleted) done.complete();
    });
    return PresentedOverlay<void>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([_]) async {
        timer.cancel();
        toast.removeCustomToast();
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
2. Return `PresentedOverlay(visible:, dismissed:, dismiss:)`.
3. **`dismissed`** must complete on *every* close path (user, timeout, your
   `dismiss`). For routes use `route.completed` (after the exit animation).
   Otherwise use `onClose`, or synthesize a signal if none exists.
4. **`dismiss`** must close *that specific* overlay via its own handle — never
   "close whatever is on top".
5. Give it a `slot` if it should run in its own lane. Reserve `exitDuration`
   for backends without an animation-end signal; routes use `route.completed`.

### Rules of engagement (from GetX / bot_toast issue history)

1. The manager owns the truth — never poll `Get.isDialogOpen` /
   `Get.isSnackbarOpen` etc.
2. Close only via each overlay's own handle (the captured Route object,
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
  Map<String, OverlaySlotOptions> slots = const {},
  Duration? dismissTimeout = const Duration(seconds: 10),
  Duration? resolveTimeout = const Duration(seconds: 30),
  OverlayCooldownStorage? cooldownStorage, // default MemoryCooldownStorage
  String storageKey = 'layerman:cooldown',
  OverlayClock clock = OverlayClock.system, // time and timers share one source
  List<RouteMatcher> pauseOnRoutes = const [],   // typed route matchers
})
```

| Member | Description |
| --- | --- |
| `OverlayClock clock` | Default `OverlayClock.system`; shared time/timer source. |
| `OverlayClock` | `DateTime now()`; `Timer createTimer(Duration duration, void Function() callback)`; `static const system`. |
| `FakeOverlayClock([DateTime? start])` | Import `package:layerman/testing.dart`; default DateTime(2000); `advance(Duration d)`, `pendingTimers`, inherited clock methods. |
| `PresentContext<T>.close([T? result])` | Identity-bound close through beforeClose. |
| `void debugCheckInvariants()` | Explicit invariant validation; automatic in debug after outermost batch. |
| `final Map<String, OverlaySlotOptions> slots` | Immutable slot configuration. |
| `final Duration? dismissTimeout` / `final Duration? resolveTimeout` | Constructor timeouts; `null` disables. |
| `Stream<OverlayEvent> get events` | Async broadcast, no replay. |
| `int get holdCount` | Number of unreleased holds. |
| `OverlayHold hold([Object? reason])` | Acquire an independent pause source. |
| `List<String> get resolvingIds` | Resolving serial and overlap ids. |
| `List<OverlayRecord> get records` | All managed entry snapshots. |
| `OverlayRecord? recordOf(String id)` | One snapshot or `null`. |
| `OverlayTicket<T> submit<T>({...})` | Same parameters as `open<T>`, returns a ticket. |
| `final Duration gap` | Delay inserted between one overlay closing and the next showing. |
| `Future<void> ready()` | Completes once the cooldown store has hydrated and the queue has been re-scheduled. Optional: all entries with `cooldown` wait for hydration automatically. |
| `Object? get currentRoute` | The `route` context key last set via `setContext` (`null` if never set). |
| `bool get isPaused` | Whether the queue is frozen — via manual pause, a route zone, or unreleased holds. |
| `bool get isDisposed` | True from the moment `dispose()` starts — lets a deferred callback avoid calling into a torn-down manager. |
| `List<String> get activeIds` | Ids in open/closing, serial + overlaps; excludes resolving. |
| `List<String> get queuedIds` | Pending ids in per-slot display order plus held overlaps; excludes resolving. |
| `bool isShowing(String id)` | Whether `id` is open/closing; false while resolving. |
| `Future<T?> open<T>({...})` | Enqueue/show an overlay through your `present:` backend; returns its result future. See below. |
| `void close(String id, [Object? result])` | Closes open entries only; queued/resolving entries are unaffected (cancel with `remove`). Two-phase close, delivering `result` (runs `beforeClose`; repeated calls while an async guard is pending are ignored). Throws `ArgumentError` — leaving the overlay untouched — if `result` isn't a `T?` of its `open<T>()`. |
| `void dismiss(String id)` | `close(id)` with a `null` result; open entries only, cancel queued/resolving entries with `remove`. |
| `void remove(String id)` | Remove immediately, no exit grace; bypasses `beforeClose`. |
| `void suppress(String id, {Duration? duration})` | Suppress submissions with cooldown; null forever, positive duration from now; only extends. |
| `OverlayCooldownStatus cooldownStatus(String id, OverlayCooldown cooldown)` | Inspect eligibility without incrementing counters. |
| `void resetCooldown(String id)` | Reset session/persisted counters and suppression for one id and re-schedule. |
| `void clearCooldowns()` | Reset all cooldown counters and suppression and re-schedule. |
| `void clearTag(String tag)` | Remove all entries with this tag, bypass guards; outcome `removed`. |
| `int get debugSlotCount` | Testing-only runtime slot count, excludes configuration. |
| `void clear()` | Remove everything (queued + active); pending results resolve `null`. |
| `void clearWhere(bool Function(OverlayRecord) test)` | Selectively remove matching entries. |
| `void update(String id, Object? patch)` | Merge `patch` into `data` (map-into-map shallow-merge, else replace) and notify listeners; no queue change. |
| `void setContext(Map<String, Object?> partial)` | Merge into the condition context and re-evaluate. |
| `void pauseAll()` / `void resumeAll()` | Full freeze / release + re-schedule. |
| `void pause(String id)` / `void resume(String id)` | Freeze / thaw one overlay's `duration` countdown. |
| `void dispose()` | Cancel timers, clear entries, dispose the notifier. Afterwards `open()` asserts in debug (returns `null` without presenting in release) and every other mutator is a no-op. While disposing, a backend callback that re-enters `open` / `submit` settles it as `disposed`; other mutators do nothing. |

Inherited from `ChangeNotifier`: `addListener` / `removeListener` /
`notifyListeners` (manager notifications are batched per operation).

#### `open<T>` / `submit<T>` parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `Present<T> present` | required | Renders (and later closes) the overlay through your UI backend — see [integration section](#integrating-other-overlay-libraries-the-present-adapter). |
| `String? id` | auto | Unique id. Reusing an *active* id replaces it in place; reusing a *queued* id overrides that entry. |
| `Object? data` | `null` | Opaque payload, read via `PresentContext.data` / `OverlayRecord.data`. |
| `Set<String>? tags` | `null` (empty set) | Copied into an immutable set, exposed by `OverlayRecord.tags`; select entries with `clearTag`. |
| `String slot` | `''` | Named serial queue (independent lanes run in parallel). |
| `int priority` | `0` | Higher shows first; ties break FIFO. |
| `Duration? delay` | `null` | Serial delay follows gap; replace and same-id active takeover skip it. Overlap waits before checking now-or-never eligibility. |
| `Duration? expireAfter` | `null` | Maximum serial wait before activation; includes pauses, ignores overlap. |
| `Duration? resolveTimeout` | `null` (inherit) | Per-entry resolve timeout; `Duration.zero` disables. |
| `Duration? duration` | `null` | Auto-close after this long once shown. |
| `OverlayMode mode` | `OverlayMode.queue` | `queue`: serial; `replace`: preempt and discard the current entry (result `null`, never re-queued); `overlap`: bypass the queue, now-or-never. |
| `bool affix` | `false` | Protect the current overlay from being `replace`d. |
| `OverlayPredicate? when` | `null` | Condition predicate; AND with route and auth. |
| `RouteMatcher? route` | `null` | Typed matcher against `context['route']`; AND with auth and when. |
| `OverlayPredicate? auth` | `null` | Login/role/permission predicate; AND with route and when; no reserved auth key. |
| `bool dismissWhenUnmet` | `true` | Auto-dismiss a *shown* overlay whose conditions stop holding. |
| `OverlayCooldown? cooldown` | `null` | Frequency cap (see `OverlayCooldown`); requires an explicit `id`. |
| `Future<T?> Function()? resolve` | `null` | Fetch the payload when granted; `null` skips without counting cooldown. |
| `FutureOr<bool> Function()? beforeClose` | `null` | Close guard; `false`/throw vetoes `close`. |
| `Duration? exitDuration` | `null` | Grace between your backend's `dismissed` signal and the queue advancing (lets a shared exit animation finish); `null` advances immediately. |

### `LayermanNavigatorObserver` (a `NavigatorObserver`)

```dart
LayermanNavigatorObserver(
  Layerman manager, {
  String? Function(Route<dynamic> route)? pathOf, // default: route.settings.name
  bool Function(Route<dynamic> route)? routeFilter, // default: route is PageRoute
  String contextKey = 'route',
})
```

Public fields: `final Layerman manager`, `final String contextKey`.
Rejected routes do not extract a path or schedule an update. Accepted routes write
to `contextKey`; `route:` / `pauseOnRoutes` read only `route`.

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

### `OverlayMode` / `RouteMatcher` / `OverlayPhase` / `OverlayCooldownStatus`

| Type | Contract |
| --- | --- |
| `OverlayMode` | `queue`, `replace`, `overlap`; `mode` defaults to `queue`. |
| `RouteMatcher` | `const RouteMatcher.exact(String path)`, `const RouteMatcher.anyOf(List<String> paths)`, `RouteMatcher.regex(RegExp pattern)`; `bool matches(Object? route)`. Do not mutate the `anyOf` input list. |
| `OverlayPhase` | `pending`, `resolving`, `open`, `closing`; used by `OverlayRecord.phase`. |
| `OverlayCooldownStatus.suppressed` | `final bool`; true while suppression is active; constructor default false. |
| `OverlayCooldownStatus` | `const OverlayCooldownStatus({required bool canShow, required bool permanentlyBlocked, required Duration? wait, bool suppressed = false})`; final fields of the same names; `suppressed` reports current suppression. |

### `OverlayCooldownStorage` / `MemoryCooldownStorage`

```dart
abstract class OverlayCooldownStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}
```

`MemoryCooldownStorage` is the default in-memory implementation; sharing the same
instance preserves counters across manager recreation, but not process restart. Provide your own (e.g. `shared_preferences`) for persistence.

### `OverlayRecord`

Read-only snapshot handed to `clearWhere`. Fields: `final String id`,
`final String slot`, `final Object? data`, `final bool active`,
`final OverlayPhase phase`, `final Set<String> tags` (copied, read-only).
Compare phases with `OverlayPhase.pending` / `resolving` / `open` / `closing`.

### `Present<T>` / `PresentContext<T>` / `PresentedOverlay<T>`

```dart
typedef Present<T> = PresentedOverlay<T> Function(PresentContext<T> context);
```

`PresentContext<T>` (given to your `present` callback) — fields: `final String id`,
`final String slot`, `final Object? data`, `final ValueListenable<Object?> dataListenable`.

```dart
class PresentedOverlay<T> {
  PresentedOverlay({required this.visible, required this.dismissed, this.dismiss});
  final Future<void> visible;                         // successful first visible frame
  final Future<T?> dismissed;                          // backend "closed" signal
  final Future<void> Function([T? result])? dismiss;   // orchestrator close
}
```

### `OverlayPredicate`

```dart
typedef OverlayPredicate = bool Function(Map<String, Object?> context);
```

### Tickets, outcomes, events and holds

| Type / signature | Contract |
| --- | --- |
| `OverlayTicket<T>` | `final String id`, `final String slot`; `Future<T?> get result`, `Future<OverlayOutcome<T>> get outcome`, `bool get isActive`, `ValueListenable<Object?> get data`; `void close([T? result])`, `void remove()`, `void update(Object? patch)`. No public constructor. |
| `const OverlayOutcome<T>(T? value, OverlayEndReason reason)` | `final T? value`, `final OverlayEndReason reason`; first settlement wins. |
| `OverlayEndReason` | `closed`, `dismissedByBackend`, `expired`, `replaced`, `superseded`, `removed`, `unmet`, `skipped`, `dropped`, `capped`, `suppressed`, `queueFull`, `queueExpired`, `failed`, `disposed`. |
| `OverlayEventType` | `queued`, `shown`, `ended`. |
| `const OverlayEvent({required OverlayEventType type, required String id, required String slot, OverlayEndReason? reason})` | Fields have the same types and are final; `reason` only on `ended`. |
| `OverlayHold` | `final Object? reason`, `bool get isReleased`, `void release()`; no public constructor, release is idempotent. |
| `const OverlaySlotOptions({Duration? gap, int? maxQueued, Set<String> blockedBy = const <String>{}})` | Final fields: nullable gap/maxQueued; omitted gap inherits, omitted maxQueued is unlimited; supplied maxQueued must be positive. `blockedBy` defaults empty and gates activation on other slots. |

### Route presenters and lifecycle binding

| Constructor / call | Parameters and defaults |
| --- | --- |
| `DialogManager(GlobalKey<NavigatorState> navigatorKey, {...})` | `bool barrierDismissible = true`, `Color? barrierColor`, `bool useSafeArea = true`, `String routeNamePrefix = 'layerman://'`. |
| `BottomSheetManager(GlobalKey<NavigatorState> navigatorKey, {...})` | Same constructor parameters as `DialogManager`, plus `bool isScrollControlled = false`, `Color? backgroundColor`, `bool enableDrag = true`, `bool? showDragHandle`. |
| `Present<T> DialogManager.call<T>(Widget Function(PresentContext<T> ctx, void Function([T? result]) close) builder, {...})` | `bool? barrierDismissible`, `Color? barrierColor`, `bool? useSafeArea`; non-null values override constructor defaults. |
| `Present<T> BottomSheetManager.call<T>(Widget Function(PresentContext<T> ctx, void Function([T? result]) close) builder, {...})` | Same call parameters, plus `bool? isScrollControlled`, `Color? backgroundColor`, `bool? enableDrag`, `bool? showDragHandle`. |
| `PresentedOverlay<T> presentRoute<T>(NavigatorState navigator, TransitionRoute<T> route, {Future<void>? visible})` | Push and retain the route, await its completed future, target that route for dismissal. |
| `LayermanLifecycle(Layerman manager, {Set<AppLifecycleState> pauseOn = const <AppLifecycleState>{AppLifecycleState.paused, AppLifecycleState.hidden}})` | `final Layerman manager`, `bool get isAttached`, `void attach()`, `void detach()`, `void didChangeAppLifecycleState(AppLifecycleState state)`; attach/detach are idempotent. |

## Deliberate differences from the TS package

- **`stackIndex`/`isTopmost` are N/A** — layer/z-order is entirely up to
  whichever `present:` backend renders the overlay (its own `Overlay`/route
  stack), not something the queue tracks or exposes.
- **Cross-tab/cross-isolate cooldown sync is not built in** — share one
  `OverlayCooldownStorage` backend if you need it.
- **Time-based cooldown auto-wakes** — unlike the headless TS core (which
  re-qualifies only on the next scheduling trigger), a Flutter entry blocked by
  a `minGap` or a bucket rollover arms a timer and shows itself the moment the
  window elapses. Exhausted `session`/`total` caps discard the entry with
  a `null` result and `OverlayEndReason.capped`.

### Testing without a Flutter binding (`FakeOverlayClock`)

Add `test` to your app's dev dependencies. This uses ordinary `test()`, with no
`flutter_test` binding. The package still requires a Flutter SDK for dependencies.
`OverlayClock` supplies both `now()` and `createTimer`; injecting only a date
callback is no longer supported. Fake timers run on `advance`; drain Future
continuations separately when checking backend completion.

```dart
import 'dart:async';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';
import 'package:test/test.dart';

void main() {
  test('注入时钟控制展示时长', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final dismissed = Completer<bool?>();
    final result = manager.open<bool>(
      duration: const Duration(seconds: 1),
      present: (_) => PresentedOverlay<bool>(
        visible: Future<void>.value(), // headless test: immediate visibility
        dismissed: dismissed.future,
        dismiss: ([value]) async { dismissed.complete(value); },
      ),
    );
    clock.advance(const Duration(seconds: 1));
    expect(await result, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(manager.activeIds, isEmpty);
    expect(clock.pendingTimers, 0);
  });
}
```

### Debug invariant checks

In debug, every outermost operation batch automatically calls
`debugCheckInvariants()` to validate container identity, phases, ordering, timers
and disposal. Tests can call it explicitly (including in release); violations
throw `StateError`. These checks and randomized tests reduce refactoring risk;
they do not replace a future Gate or explicit state-machine refactor.

## Testing

```bash
flutter test                                                   # unit (widget) tests
cd example && flutter test integration_test/orchestration_test.dart -d <serial>        # real-device orchestration
```

The unit suite uses `WidgetTester` to cover serial queueing, close-advances,
priority, `Future` results, `replace`/`affix`/`overlap`, conditions, cooldown
(incl. auto-wake), `resolve`, `beforeClose`, pause/resume, `update`/`clearWhere`,
the `present:` adapter, and phase transitions. The `example/` app is a full
real-device demo orchestrating GetX + bot_toast + native `showDialog` through
the manager. Android phone validation was reported on Huawei STG-AL00 / Android 12.
Windows desktop runs take focus; do not run them unattended.

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

- **不再提示**：按结果调用 `suppress`，永久或限时抑制带 `cooldown` 的提交。
- **跨槽位阻塞**：`OverlaySlotOptions.blockedBy` 在其他 slot 占用时阻止新条目激活。

- **串行队列**:每个 slot 一次只显示一个,当前移除后下一个才显示,可设 `gap` 间隔。
- **具名 slot**:相互独立、可并行的多条串行队列(如 `toast` 与 `dialog`)。
- **优先级**:高者先显示,同级 FIFO。
- **1.0 类型契约**：`mode: OverlayMode.queue/replace/overlap`、`RouteMatcher`、`OverlayPhase`。
- **查询与分组**：`cooldownStatus`（`OverlayCooldownStatus`）、`resetCooldown` / `clearCooldowns`、复制的 `tags` / `clearTag`。
- **帧安全提交**：`build()` 期间 `open` 推迟展示与通知；管理器通知按操作合并，空闲 slot 自动回收。
- **`replace`**:抢占当前浮层立即显示(跳过待定 gap;排在已入队项之前);被顶掉的
  浮层会被**关闭**(结果为 `null`)——一个已被 dismiss 的后端没法被如实地重新呈现,
  所以它不会再次显示。
- **`affix`**:保护当前浮层不被 `replace` 顶掉(被挡的抢占者在队首等待)。
- **`overlap`**:绕过队列,等待 `delay` 后叠加显示(全局告警、阻塞式 loading);条件/冷却对
  overlap 是「此刻不满足即丢弃」的一次性发射门。
- **条件**:`route`、`auth(ctx)`、`when(ctx)` 三者 AND,
  由 `setContext({...})` 驱动;已显示的浮层若条件不再满足会被自动撤下
  (`dismissWhenUnmet`,默认 true;排队项只是等待)。
- **冷却**:`OverlayCooldown(session / total / day / hour / minute / minGap)`,多个
  上限按 AND 生效、真正打开时才计数;通过可插拔的 `OverlayCooldownStorage` 持久化
  (默认内存;生产用 `shared_preferences`)。**时间型**上限(`minGap` 与自然桶滚动)
  到期时会**自动**把排队项弹出。
- **后端驱动 `resolve`**:仅当浮层获得 slot 时才取数据;返回 `null` 则跳过。取数
  期间 slot 已被占用；普通后来者等待，但 `replace` 可以抢占并丢弃取数中的条目。
- **`beforeClose` 守卫**:返回 `false`(同步或异步)可否决一次 `close()`(如未保存
  确认);`remove`/`clear` 会绕过它。
- **`Future<T?>` 结果**:`open()` 返回的 future 以你关闭时传入的值兑现,dismiss 则为
  `null`。
- **两阶段关闭**:`close()` 立即兑现结果,然后等待你的后端发出的 `dismissed` 信号（由 `dismissTimeout` 限时）,
  外加一个可选的按次 `exitDuration` 宽限,队列才会推进——让后端先播完自己的退场动画。
- **`pauseAll`/`resumeAll`**:整体冻结(不再显示新浮层,`duration` 倒计时暂停);
  以及按 id 的 `pause`/`resume`。
- **自动路由感知**:`LayermanNavigatorObserver` 自动把真实导航喂进 `route` 条件
  (router 无关:vanilla Navigator/GetX/go_router 都行);`pauseOnRoutes` 声明"免打扰区"
  路由,进入自动冻结队列、离开自动恢复,与手动 `pauseAll`/`resumeAll` 干净组合。
  `currentRoute` 读回追踪到的值。
- **`update(id, patch)`**:向已显示浮层的 `data` 浅合并并通知监听者，不渲染、不改队列。
  `PresentContext.data` 是 present 时的快照；实时 UI 通过 `dataListenable` 读取。
  **`clearWhere(test)`**:按条件批量移除(如「关闭所有 X 组」)。
- **每浮层的 `delay` 与 `duration`**(自动关闭)。
- **编排外部浮层系统**:一条队列统管 `showDialog`、GetX、`bot_toast`、
  `fluttertoast` 或任何你能显示/关闭的东西。

- **路由 presenter**：可复用的 `DialogManager`、`BottomSheetManager`、`presentRoute`。
- **票据和事件**：类型化 `submit<T>`、带原因的结果、异步事件流。
- **独立暂停来源**：`hold()` 与自动 `LayermanLifecycle` 绑定。
- **有界等待**：解析/关闭超时、`expireAfter`、槽位 `gap` / `maxQueued`。
- **实时数据与诊断**：`dataListenable`、`resolvingIds`、`records`、`recordOf`。

## 安装

```yaml
dependencies:
  layerman: ^1.0.0
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

`present:` 是它的严格超集。你在里面构造任意 UI——`showDialog`、`Get.dialog`、`BotToast.show`、`Navigator.push`,或自己插一个 `OverlayEntry`——再返回一个 `PresentedOverlay(visible: ..., dismissed: ..., dismiss: ...)` 句柄。`builder:` 能渲染的,一个自己持有 `OverlayEntry` 的 `present:` 后端照样能渲染——所以什么都没丢,而核心从此 headless(不 import `flutter/widgets`),跟 headless 的 TS 姊妹包对齐。

```dart
manager.open(present: (ctx) {
  final visible = Completer<void>();
  final done = Completer<String?>();
  final cancel = BotToast.showWidget(
    toastBuilder: (_) => OverlayVisibility(
      visible: visible,
      child: MyCard(onOk: () => done.complete('ok')),
    ),
  );
  done.future.whenComplete(cancel);
  return PresentedOverlay<String>(
    visible: visible.future,
    dismissed: done.future,
    dismiss: ([r]) async {
      cancel();
      if (!done.isCompleted) done.complete(r);
    },
  );
});
```

路由弹窗优先用 `DialogManager`，或自行保存 Route 对象：`dismissed` 使用 `route.completed`，
关闭时通过路由自己的 navigator 精准关闭这一条——见下方配方。

## 基础用法

### 共享路由 presenter

在 `manager` 旁全局建一次，将同一个 `navigatorKey` 传给应用；Navigator 挂载后再调用
`open`。下面的例子使用 `dialogs((ctx, close) => widget)`。

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final dialogs = DialogManager(navigatorKey);
final sheets = BottomSheetManager(navigatorKey);

// Mount this once in your app:
final app = MaterialApp(navigatorKey: navigatorKey, home: const Scaffold());
```

### 打开并等待结果

```dart
final ok = await manager.open<bool>(
  id: 'confirm-delete',
  present: dialogs((ctx, close) => Center(
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

### 从 0.x 迁移

所有破坏性改动见 [CHANGELOG 的 1.0.0 迁移表](CHANGELOG.md#100)。

### 在 `build()` 期间打开浮层（Building overlays during `build()`）

`open` 在 `build()` 期间自动将 `present` 与管理器通知推迟到帧后，仍立即返回 Future。
排队保持顺序，展示前重新检查暂停、条件与 hydrate。请防止重复 build 导致重复提交：

```dart
class PromoTrigger extends StatefulWidget {
  const PromoTrigger({super.key, required this.manager, required this.present});
  final Layerman manager;
  final Present<void> present;

  @override
  State<PromoTrigger> createState() => _PromoTriggerState();
}

class _PromoTriggerState extends State<PromoTrigger> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    if (!_submitted) {
      _submitted = true;
      widget.manager.open<void>(id: 'build-promo', present: widget.present);
    }
    return const SizedBox.shrink();
  }
}
```

### 通知按操作合并（Notifications are batched per operation）

一次公开操作在同步变更完成后最多通知一次管理器监听者；异步续体是独立批次。
build 期间的通知合并到帧后；`dataListenable` 与异步 `events` 是独立通道。

### 标签（Tags）

`tags` 默认空集合，提交时复制为只读的 `OverlayRecord.tags`。
`clearTag(tag)` 移除含该标签的 pending、resolving、open、closing 条目，
绕过 `beforeClose`，结束原因为 `removed`。

```dart
manager.open<void>(id: 'campaign', tags: {'promo', 'home'},
  present: dialogs<void>((ctx, close) => const Text('Campaign')));
final record = manager.recordOf('campaign');
if (record?.phase == OverlayPhase.open) {
  manager.clearTag('promo');
}
```

### 队列 / 优先级 / replace / affix / overlap

`mode` 只选择一种 `OverlayMode`：`queue`（默认）、`replace` 或 `overlap`。
`affix` 独立设置；replace 与 overlap 不能组合。

```dart
manager.open(id: 'welcome', present: dialogs((ctx, close) => const WelcomeSheet()));
manager.open(id: 'promo', priority: 10, present: dialogs((ctx, close) => const PromoCard())); // 插队靠前

// 抢占当前浮层(它会被关闭,结果 null——已被 dismiss 的后端没法如实重新呈现):
manager.open(id: 'session-expired', mode: OverlayMode.replace, present: dialogs((ctx, close) => const ExpiredDialog()));

// 固定当前浮层,replace 顶不掉它:
manager.open(id: 'critical', affix: true, present: dialogs((ctx, close) => const CriticalDialog()));

// 绕过队列，延迟结束后判资格并叠加：
manager.open(id: 'net-error', mode: OverlayMode.overlap, delay: const Duration(seconds: 1), present: dialogs((ctx, close) => const Text('Network error')));

// 并行的独立串行队列:
manager.open(id: 't1', slot: 'toast', present: dialogs((ctx, close) => const Toast('已保存')));
```

`RouteMatcher.exact('/promo')` 匹配单一路径；
`const RouteMatcher.anyOf(['/promo', '/home'])` 匹配列表任一路径；
`RouteMatcher.regex(RegExp(r'^/promo/'))` 使用 `hasMatch`。上下文路由为 null 或非字符串时不匹配。


overlap 的 `delay` 生效：先等待，再按「现在或永不」判断资格。
remove、clear、同 id 重开、dispose 均取消等待；暂停和 hydrate 可继续挂起，且不占串行 slot。

### 条件(`when` / `route` / `auth` / `setContext`)

排队项若条件不满足只会**等待**;已显示项若条件不再满足会被自动撤下(除非
`dismissWhenUnmet: false`)。

```dart
manager.setContext({'route': '/promo', 'auth': true}); // 把真实导航/登录态喂进来

manager.open(id: 'promo', route: const RouteMatcher.exact('/promo'), present: dialogs((ctx, close) => const PromoCard()));
manager.open(id: 'inbox', auth: (ctx) => ctx['auth'] == true, present: dialogs((ctx, close) => const InboxHint()));
manager.open(
  id: 'vip',
  when: (ctx) => ctx['tier'] == 'gold', // 与 route / auth 按 AND 组合
  present: dialogs((ctx, close) => const VipCard()),
);
```

`route`、`auth`、`when` 按 **AND** 组合，未提供的条件视为通过。
只有 `route` 读取保留键 `route`；`auth` / `when` 读取 `setContext` 推进来的任意键，
引擎不自行读取 `auth` 键。判断函数抛错按条目上报一次并视为未满足。
条件是推模式：外部状态变化后需调用 `setContext`（可用 `setContext({})`）或等待其他调度触发，
不会仅因时间流逝自动重判。

判断回调（`when`、`auth`、`clearWhere` 的 test）只能读取状态。期间调用管理器写操作、
票据 / context 操作、hold.release 或 dispose，均在状态变化前抛出包含“判断函数内不能修改 Layerman”
的 StateError。条件异常每条目仅上报一次并视为不满足；clearWhere 的 test 异常向外传播，只读 getter 不受限制。

### 登录与角色（`auth:` 判断函数）

```dart
manager.setContext({'signedIn': true, 'role': 'admin', 'route': '/admin'});
manager.open<void>(
  id: 'admin-hint',
  route: const RouteMatcher.exact('/admin'),
  auth: (ctx) => ctx['signedIn'] == true && ctx['role'] == 'admin',
  when: (ctx) => ctx['maintenance'] != true,
  present: dialogs<void>((ctx, close) => const Text('Admin')),
);
```

旧 `requiresAuth: true` 等价迁移为 `auth: (ctx) => ctx['auth'] == true`；
旧的仅游客 `requiresAuth: false` 等价迁移为 `auth: (ctx) => ctx['auth'] != true`。
键名以及角色、权限策略由业务决定。

### 自动路由感知(`LayermanNavigatorObserver` + `pauseOnRoutes`)

手动在每个可导航页面的生命周期里写 `setContext({'route': ...})` 是样板代码。
`LayermanNavigatorObserver` 自动帮你做:塞进 `navigatorObservers` 就行,GetX/
go_router/vanilla Navigator 都能用(三者底层最终都是同一个 Flutter Navigator,
这就是标准 `NavigatorObserver`)。纯观察,不 push、不 pop、不碰导航本身。

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  navigatorObservers: [LayermanNavigatorObserver(manager)],
  home: const Scaffold(),
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
- **0.3.0 起默认只跟踪 `PageRoute`。** 对话框、底部弹层和菜单保留最近接受的页面路径，
  带路由条件的弹窗不会把自己关闭，无关弹窗也不会解除免打扰区。
  要恢复 0.2.x 行为，传 `routeFilter: (r) => true`。
- 嵌套 Navigator 可用 `contextKey: 'tabRoute'`，在 `when` 中读取；
  `route:` 与 `pauseOnRoutes` 仍只读取默认 `route` 键。

`pauseOnRoutes` 在这基础上加了个"免打扰区":进入匹配路由会冻结整条队列(和
`pauseAll()` 效果一样,不激活新的);离开会恢复(和 `resumeAll()` 一样)。它跟手动
`pauseAll`/`resumeAll` 是**组合**关系不是互斥——离开免打扰区不会顶掉一次无关的手动
暂停,手动 `resumeAll()` 也不会顶掉一次仍生效的免打扰区。

```dart
final manager = Layerman(pauseOnRoutes: const [RouteMatcher.exact('/checkout')]);
// 追踪到的路由是 '/checkout' 期间,不会有新浮层显示——排队的等着,
// 路由一变就立刻激活。
```

进入免打扰区时"已经在显示的浮层"要不要自动关——**刻意不做统一规则**,用上面同一套
`route`/`when` + `dismissWhenUnmet`(不管哪个 `present:` 后端在渲染这个浮层,规则都
一样),或者依赖某个具体后端自己的路由感知关闭能力。

### `DialogManager` / `BottomSheetManager`

用应用的 `navigatorKey` 全局建一次；实例只保存配置，每次展示独立持有 Route。
builder 的 `close([result])` 总是委托 `ctx.close`，经过 `beforeClose`；实例可跨管理器复用。
返回键、遮罩和拖动属于后端关闭，绕过守卫。单次调用的非 null 选项覆盖构造默认值：

```dart
manager.open<bool>(
  present: sheets<bool>(
    (ctx, close) => TextButton(onPressed: () => close(true), child: const Text('Done')),
    isScrollControlled: true,
    barrierDismissible: false,
  ),
);
```

两者默认 `barrierDismissible: true`、`useSafeArea: true`、`routeNamePrefix: 'layerman://'`。
颜色回退到主题，对话框最终回退 `Colors.black54`。底部弹层还默认
`isScrollControlled: false`、`enableDrag: true`、`showDragHandle: null`、`backgroundColor: null`。
页面或自定义 Route 使用 `presentRoute`，见下方手写配方。

### 结果 / 票据 / 事件（Outcome / tickets / events）

`submit<T>` 与 `open<T>` 参数完全相同，返回 `OverlayTicket<T>`。`result` 是 `Future<T?>`；
`outcome` 是 `Future<OverlayOutcome<T>>`，包含 `value` 和首次结束的 `reason`。
兑现早于退场动画结束。类型化 `ticket.close([T? result])` 遵守守卫，`remove()` 绕过守卫，
`update(patch)` 更新数据，`data` 为 `ValueListenable<Object?>`。旧票不能操作同 id 的新提交。
`isActive` 包括仍受管的 pending/resolving/closing。
`events` 是异步广播流，`OverlayEventType` 有 `queued`、`shown`、`ended`；事件含
`id`、`slot`、`type`、可空 `reason`。提交前订阅，无历史重放；`ended` 表示首次兑现，非动画结束。

```dart
final subscription = manager.events.listen((event) {
  debugPrint('${event.id}: ${event.type} ${event.reason}');
});
final ticket = manager.submit<bool>(
  id: 'decision',
  present: dialogs<bool>((ctx, close) => AlertDialog(
    actions: [TextButton(onPressed: () => close(true), child: const Text('OK'))],
  )),
);
ticket.update({'count': 1});
final outcome = await ticket.outcome;
debugPrint('${outcome.value}: ${outcome.reason}');
await subscription.cancel();
```

同一提交的事件按 queued → shown → ended 顺序发出，present 内同步关闭也是如此；present 抛错时没有 shown，
只有 ended（`failed`）。

### 暂停来源：`hold` 与 `LayermanLifecycle`

手动暂停、`pauseOnRoutes`、未释放的 holds 按 OR 组合。`hold(reason)` 返回 `OverlayHold`，
`release()` 幂等，`holdCount` 只统计 holds。释放一个来源不会撤销其他来源。
`LayermanLifecycle` 默认在 `AppLifecycleState.paused`、`hidden` 获取 hold，其他状态释放；
`pauseOn` 可覆盖集合。`attach()` 立即同步当前状态，`detach()` 解除监听并释放，均幂等。
更换所有者时解除绑定。

```dart
final lifecycle = LayermanLifecycle(manager)..attach();
final hold = manager.hold('payment');
try {
  await Future<void>.delayed(const Duration(milliseconds: 100));
} finally {
  hold.release();
}
// When the app owner is disposed or the manager is replaced:
lifecycle.detach();
```

### 超时、`expireAfter` 与槽位选项

请求后端关闭后 `dismissTimeout` 默认 10 秒，`resolveTimeout` 默认 30 秒。
构造时两者可传 `null` 不限时；单条 `resolveTimeout: null` 表示继承，`Duration.zero` 关闭
该条解析超时。构造时传零则立即超时，不是禁用。超时通过 `FlutterError.reportError` 上报
`TimeoutException` 并释放槽位；解析超时原因为 `skipped`，关闭超时保留已兑现结果与原因。
超时不会取消底层异步工作，也不保证后端 UI 已移除。
`expireAfter` 只计算激活前的串行等待时间（含暂停），不适用于 overlap 或已激活条目，
到期原因为 `queueExpired`。槽位 `gap` 覆盖全局间隔；正数 `maxQueued` 不含活跃项，
超限淘汰有序队尾（`queueFull`），可能就是新提交项。
这些截止计时不随暂停冻结，只有 `duration` 冻结。

```dart
final bounded = Layerman(
  dismissTimeout: const Duration(seconds: 10),
  resolveTimeout: const Duration(seconds: 30),
  slots: const {
    'notice': OverlaySlotOptions(gap: Duration(milliseconds: 200), maxQueued: 3),
  },
);
final boundedDialogs = DialogManager(navigatorKey);
bounded.open<String>(
  slot: 'notice',
  expireAfter: const Duration(minutes: 1),
  resolveTimeout: Duration.zero,
  resolve: () async => 'Ready',
  present: boundedDialogs<String>((ctx, close) => Text(ctx.data as String)),
);
// The owner eventually calls bounded.dispose().
```

串行 `delay` 在 gap 之后再等，replace 与同 id 活跃接管跳过；overlap 先等待再判定资格。
delay 归等待它的条目所有：移除或覆盖该条目会取消旧等待并重新调度。maxQueued 在激活判定之后
才约束仍在等待的条目，build 期间连同容量检查一起推迟到帧后调度完成；等待 gap、delay、条件、冷却或
blockedBy 的条目仍计数，本次提交也可能被淘汰。

#### 跨槽位阻塞（`blockedBy`）

```dart
final manager = Layerman(slots: {
  'toast': OverlaySlotOptions(blockedBy: {'modal'}),
  'banner': OverlaySlotOptions(blockedBy: {'modal'}),
});
```

`OverlaySlotOptions.blockedBy` 类型为 `Set<String>`，默认空。列出的 slot 占用期间，本 slot
不激活新条目。占用指串行 active（resolving / open / closing，含 `exitDuration` 宽限），
或者该 slot 的 overlap 已激活。gap、appear delay、冷却等待、排队、等待中的 overlap **都不算占用**，
因此被阻塞的条目可能在 blocker 的两个条目之间出场。**已激活条目继续显示，duration 照常走**：
modal 出场前已显示的 toast 不会被关闭或暂停。

被阻塞的串行条目继续排队，`expireAfter` / `maxQueued` 照常生效；replace 不抢占，解除后保留
最前排带；合格的同 id 串行重开排队并保留接管优先权。初次资格通过的 overlap 被持有，解除后
再做一次“现在或永不”判定。
解除统一在最外层操作批次末尾处理，避免 replace 移走旧项、激活新项之间让其他 slot 插队。
仅重判确实等待解除的 slot 和被持有的 overlap，不给其他 slot 增加条件重判触发点。
环按先激活者占用，不保证公平；不存在的 slot 名无效果；自阻塞触发 debug 断言。

### 实时数据（`dataListenable`）

`PresentContext.data` 为快照，`dataListenable` 通知 `update` 和解析值的变化。
`ticket.data` 是同一通道，结束后保留最后值。manager 刻意不 dispose 此通道，
便于退场动画结束后解除监听；后端销毁时移除自行注册的监听者。

```dart
manager.open<void>(
  id: 'cart',
  data: {'count': 1},
  present: dialogs<void>((ctx, close) => ValueListenableBuilder<Object?>(
    valueListenable: ctx.dataListenable,
    builder: (_, value, __) => Text('${(value as Map)['count']}'),
  )),
);
manager.update('cart', {'count': 2});
```

当前数据与 patch 都是字符串键 Map（`Map<String, Object?>` / `Map<String, dynamic>`）时，浅合并结果保持
`Map<String, Object?>`，后端 `value as Map<String, dynamic>` 之类的转换继续可用；其他 Map 组合合并为通用 Map。

### 冷却(频次上限 + 持久化)

```dart
manager.open(
  id: 'rate-us',
  cooldown: const OverlayCooldown(total: 3, day: 1, minGap: Duration(hours: 6)),
  present: dialogs((ctx, close) => const RateUsCard()),
);
```

所有上限按 AND 通过才显示,真正打开时计数。计数按 `id` 记,所以带冷却必须传显式 `id`
(debug 下断言——自动生成的 id 每次都变)。`session` 存内存,其余持久化。生产中接真实存储:

```dart
final manager = Layerman(cooldownStorage: SharedPrefsCooldownStorage());
await manager.ready(); // 可选:计数已加载、队列已重新调度
```

存储 hydrate 完成前，**所有带 `cooldown` 的提交**都等待，包括仅设 session 和空配置，
因为抑制状态需要持久化读取。串行排队，overlap 挂起而不丢弃；不带 `cooldown` 的提交不受影响。
迁移：依赖 session-only 条目在 `ready()` 前出场的代码，现在会晚一个存储读取的时间。
在 `ready()` 之前 open 仍然安全。读或写失败
都会经 `FlutterError.reportError` 上报,不会卡住调度。

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

**1.0.0 补完 0.3.0 行为：** `session` / `total` 耗尽的串行条目在提交时立即以
`null`（`capped`）结束；hydrate 完成时再次检查队列，不受 slot 占用或暂停阻挡。
需要可重试的等待请使用时间型冷却，新活动使用新 id。

`cooldownStatus(id, cooldown)` 返回 `OverlayCooldownStatus`：`canShow` 表示全部上限与抑制检查通过，
`permanentlyBlocked` 表示 session/total 耗尽或永久抑制。`wait` 可展示时为 `Duration.zero`，
时间冷却时为最长剩余等待，永久受阻或等待冷却存储 hydrate 时为 `null`。
`suppressed` 表示当前有限时或永久抑制。hydrate 前 `canShow: false, wait: null`，
但 `permanentlyBlocked` / `suppressed` 仍反映内存已知状态（含 session 耗尽、本会话已设置的永久抑制）。
`resetCooldown(id)` 清除该 id 的 session、持久化计数及抑制，`clearCooldowns()` 清除全部计数及抑制；
两者都会重判等待条目并持久化重置，但不会复活已以 `capped` 或 `suppressed` 结束的条目。

```dart
const cap = OverlayCooldown(session: 2, minGap: Duration(minutes: 5));
final status = manager.cooldownStatus('promo', cap);
if (status.canShow) {
  manager.open<void>(id: 'promo', cooldown: cap,
    present: dialogs<void>((ctx, close) => const Text('Promo')));
}
manager.resetCooldown('promo');
manager.clearCooldowns();
```

日 / 小时 / 分钟上限按本地日历计算，时钟返回 UTC（例如服务器时间）时同样如此。存储中单条记录损坏时
上报并跳过，原值写回时保持不变，直到同 id 写入新的有效记录或 `resetCooldown` / `clearCooldowns` 删除它；
其他 id 的计数与抑制不受影响。

#### 不再提示（`suppress`）

卡片关闭时返回 `'never'`、`'later'` 或 `null`，按结果决定抑制。
`const OverlayCooldown()` 不设次数上限，只遵守 suppress：

```dart
Future<void> showPromo(Layerman manager, Present<String> present) async {
  final r = await manager.open<String>(
    id: 'promo',
    cooldown: const OverlayCooldown(),
    present: present,
  );
  if (r == 'never') manager.suppress('promo');
  if (r == 'later') {
    manager.suppress('promo', duration: const Duration(days: 3));
  }
}

// 例如设置页的开关：被抑制时显示，调用 resetCooldown('promo') 恢复提示。
bool promoSuppressed(Layerman manager) =>
    manager.cooldownStatus('promo', const OverlayCooldown()).suppressed;
```

`Layerman.suppress(String id, {Duration? duration})` 从现在起抑制正数 `duration` 这段时间，
null 表示永久。**只约束带 `cooldown:` 的提交**；不带 cooldown 的手动打开不受影响，
例如用户在设置页主动点“查看活动”。已激活条目不受影响。抑制与计数共用一条持久化记录
（JSON 键 `su`），`resetCooldown(id)` / `clearCooldowns()` 会一起清除。
多次调用取更晚到期时间，永久优先，只延长不缩短；所以“任何关闭抑制三天，再对不再提示永久抑制”
的调用顺序不影响结果。缩短只能 reset，而 reset 会同时清掉计数。

永久抑制立即以 `OverlayEndReason.suppressed` 结束排队的串行条目，即使暂停中、slot 被占用或
hydrate 未完成也一样。限时抑制让串行条目继续等待，到期自唤醒（其他时间型上限可能更晚）；
可用 `expireAfter` 限定等待。overlap 在 delay 到点或释放时判断，抑制阻止冷却通过则以 suppressed 丢弃。
冷却丢弃原因优先级为 `suppressed > capped > dropped`；route/auth/when 条件失败仍为 `dropped`。
永久抑制时 `permanentlyBlocked: true, wait: null`；限时抑制的 `wait` 取剩余抑制时间与其他时间型
等待的较大者（永久受阻或等 hydrate 时仍为 null）。

### 后端驱动 `resolve`

获得槽位后才取数据。`resolve` 类型为 `Future<T?> Function()?`，与结果共用 `T`。
返回 `null` 跳过且不记冷却。解析期间普通条目等待；`replace` 可以抢占并丢弃它。
`ctx.data` 是解析后的值。

```dart
manager.open<String>(
  id: 'offer',
  resolve: () async => 'Today’s offer',
  present: dialogs<String>((ctx, close) => AlertDialog(
    content: Text(ctx.data as String),
    actions: [TextButton(onPressed: () => close('accepted'), child: const Text('OK'))],
  )),
);
```

### 在后端内部关闭（`ctx.close`）

`PresentContext<T>.close([T? result])` 经 `beforeClose` 关闭本次提交，绑定条目身份；
同 id 重开后旧回调不能关掉新条目。非 open 或守卫未决时无操作。
后端自身的遮罩、返回键关闭仍绕过守卫。

```dart
manager.open<bool>(
  beforeClose: () => true,
  present: (ctx) => presentRoute<bool>(
    navigatorKey.currentState!,
    DialogRoute<bool>(
      context: navigatorKey.currentContext!,
      builder: (_) => TextButton(
        onPressed: () => ctx.close(true),
        child: const Text('Done'),
      ),
    ),
  ),
);
```

### `beforeClose` 守卫

```dart
manager.open(
  id: 'editor',
  beforeClose: () async => await confirmDiscard(), // 返回 false 否决关闭
  present: dialogs((ctx, close) => const EditorSheet()),
);
```

`beforeClose` 只拦 `close()`/`dismiss()`;`remove`/`clear`/自动撤下会绕过。异步守卫
未决期间,同一浮层后续的 `close()`/`dismiss()` 会被忽略,连点两下不会问两次。

### pause / resume / update / clearWhere

```dart
manager.pauseAll();  manager.resumeAll();   // 整体冻结 / 释放并重排
manager.pause('sheet'); manager.resume('sheet'); // 冻结/恢复单个 duration 倒计时

manager.update('cart', {'count': 3});       // 浅合并进 data,通知监听者,不重排队列
manager.clearWhere((r) => (r.data as Map?)?['group'] == 'promo'); // 按条件批量清
```

`update` 对 Map 浅合并，其余值替换；通知 `dataListenable` 和 manager 监听者，不改变队列。
实时值读取 `PresentContext.dataListenable`；`PresentContext.data` 仍为展示时的快照。

### 两阶段关闭 / 退场动画

`close()` 兑现结果,并请求你的后端关闭;队列只有在后端的 `dismissed` future
完成并经过可选 `exitDuration` 宽限后推进；`dismissTimeout` 到期也会释放条目。退场动画完全是你后端自己的事——
路由后端使用 `route.completed`，它在退场动画结束后携带 pop 结果完成；
`showDialog` / `Navigator.push` 返回的 future 在 pop 开始时就完成。
`exitDuration` 留给没有「动画结束」信号的后端。自定义后端也可以自行完成 `dismissed`：

```dart
manager.open<void>(
  id: 'sheet',
  present: (ctx) {
    final visible = Completer<void>();
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
        child: OverlayVisibility(visible: visible, child: const MySheet()),
      ),
    );
    navigatorKey.currentState!.overlay!.insert(entry);
    return PresentedOverlay<void>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([_]) async => requestClose(),
    );
  },
);

manager.close('sheet'); // 立即兑现；dismiss() 播完淡出后推进槽位
```

`resolvingIds` 含解析中条目（含 overlap）；`records` 覆盖所有受管阶段，`recordOf(id)`
返回单条快照或 `null`。`queuedIds` 在每个槽位内按 replace/优先级/FIFO 的真实顺序排列，
后接挂起的 overlap；独立槽位之间没有全局出场顺序。

### 命令式控制与内省

```dart
manager.close('sheet', someResult); // 带结果的两阶段关闭
manager.dismiss('sheet');           // 以 null 关闭
manager.remove('sheet');            // 立即移除,无退场宽限
manager.clear();                    // 移除全部(排队 + 活跃)

manager.isShowing('sheet'); // 仅 open/closing 为 true
manager.activeIds;          // open/closing 的 id（串行 + overlap）
manager.queuedIds;          // 槽位内按出场顺序的 pending id
manager.resolvingIds;
manager.records;
manager.recordOf('sheet');
manager.isPaused;
```

resolving 条目在 `resolvingIds` 和 `records` 中，不在 `activeIds` / `queuedIds` 中；
打开前 `isShowing` 为 false。

`Layerman` 是 `ChangeNotifier`,可 `addListener` / `AnimatedBuilder` 在每次
状态变化时刷新 UI。

## 接入其它浮层库(`Present` 适配器)

项目里往往不止一套浮层系统。`open(present: ...)` 让管理器去**调度**由**其它库渲染**的
浮层:`present` 回调只在队列许可时被调用一次,返回一个双向句柄:

```dart
PresentedOverlay<T>(
  visible: firstPaintVisible,       // Future<void>: successful first visible frame
  // Waiting visible uses phase=open and occupies its slot; duration already runs.
  // visible error => failed; an earlier end keeps its reason and has no shown.
  // Only visible success while still open records cooldown and emits shown.
  dismissed: someFuture,            // 后端「已完全关闭」的信号(任意关闭路径)
  dismiss: ([T? result]) async {},  // 由编排器发起的定向关闭
)
```

- `await open(...)` 的结果:由管理器 `close(id, result)` 关闭时就是那个 `result`,否则是
  **`dismissed`** 完成时带的值——所以 `dismissed` 必须在**每一条**关闭路径上完成
  (用户点击、遮罩、返回键、超时、你的 `dismiss`)。
- `close` / `replace` / `clear` / `remove` 会调用 **`dismiss`** 代表管理器关闭后端。
- 路由后端的 `dismissed` 使用 **`route.completed`**：退场动画结束后携带 pop 结果
  完成。`showDialog` / `Navigator.push` 的 future 在 pop 开始时就完成。
  `exitDuration` 是 `dismissed` 之后的宽限，留给没有「动画结束」信号的后端。

核心价值:一条串行队列(叠加优先级 / replace / 冷却 / 条件)统一治理来自不同库的
dialog、snackbar、toast。

### 原生 `showDialog`

对话框优先用 `DialogManager`。想自己控制时可手写 Route 配方：`presentRoute` 推入路由，
用 `route.completed` 等退场结束，并定向关闭这一条路由，无需估计 `exitDuration`。
栈顶且无内部历史时 pop 携带结果；被覆盖时用不带结果的 `removeRoute(route)` 兼容 Flutter 3.27。
`manager.close` 仍交付指定结果；直接用返回句柄关闭被覆盖或带内部历史的路由时结果为 `null`。

带内部历史的页面（如打开的 Drawer、持久底部面板）也使用 removeRoute，结果规则与被覆盖时相同。

```dart
manager.open<bool>(
  id: 'confirm',
  present: (ctx) {
    final navigator = navigatorKey.currentState!;
    final route = DialogRoute<bool>(
      context: navigator.context,
      settings: RouteSettings(name: 'layerman://${ctx.id}'),
      builder: (_) => const AlertDialog(content: Text('Confirm?')),
    );
    return presentRoute(navigator, route);
  },
);
```

### GetX dialog / bottom sheet

`Get.dialog` / `Get.bottomSheet` 不交出 Route 对象。改为在同一个
Navigator（`Get.key.currentState!`）上直接 push `DialogRoute`：

```dart
manager.open<bool>(
  id: 'confirm',
  present: (ctx) {
    final navigator = Get.key.currentState!;
    final route = DialogRoute<bool>(
      context: navigator.context,
      settings: RouteSettings(name: 'om://${ctx.id}'),
      builder: (_) => const ConfirmDialog(),
    );
    // 成功构建、挂载且位于栈顶的首帧才确认可见。
    return presentRoute(navigator, route);
  },
);
```

底部弹层只需把上面的 `route` 构造替换为以下代码；其余 push、
`route.completed` 和定向关闭逻辑相同。`isScrollControlled` 是必填参数：

```dart
final route = ModalBottomSheetRoute<bool>(
  settings: RouteSettings(name: 'om://${ctx.id}'),
  builder: (_) => const ConfirmDialog(),
  isScrollControlled: false,
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
    final visible = Completer<void>();
    final c = Get.snackbar('已保存', '你的修改已安全保存',
      messageText: OverlayVisibility(visible: visible, child: const Text('你的修改已安全保存')),
    );
    return PresentedOverlay<void>(visible: visible.future, dismissed: c.future, dismiss: ([_]) => c.close());
  },
);
```

> 提示:放在**独立 slot** 的 toast/snackbar 会**故意**与主 dialog 队列并行(这是常见
> UX)。若要严格排在 dialog 之后,把它放到**默认 slot**。

### 把导航到的页面也塞进队列

页面使用 `presentRoute` 适配 `TransitionRoute<T>`；获得槽位才 push，直到退场结束才释放槽位。

```dart
manager.open<bool>(
  id: 'checkout',
  present: (_) => presentRoute(
    navigatorKey.currentState!,
    MaterialPageRoute<bool>(
      settings: const RouteSettings(name: '/checkout'),
      builder: (_) => const Scaffold(body: Text('Checkout')),
    ),
  ),
);
```

### bot_toast

缴械它自带的竞争语义:`onlyOne: false` + 专属 `groupKey`;`onClose` 是唯一的「已完全
关闭」信号;`CancelFunc` 播放退场动画。

```dart
manager.open<void>(
  id: 'tip',
  slot: 'toast',
  present: (ctx) {
    final visible = Completer<void>();
    final done = Completer<void>();
    final cancel = BotToast.showCustomText(
      toastBuilder: (_) => OverlayVisibility(visible: visible, child: Card(child: Text('已复制'))),
      onlyOne: false,               // replace 决策归管理器
      onClose: () => done.complete(),
    );
    return PresentedOverlay<void>(visible: visible.future, dismissed: done.future, dismiss: ([_]) async => cancel());
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
    // 原生 showToast 没有可见回报；使用可确认首帧的 FToast widget。
    final visible = Completer<void>();
    final done = Completer<void>();
    final toast = FToast()..init(navigatorKey.currentContext!); // 已挂载页面中、Overlay 下的 context。
    toast.showToast(
      child: OverlayVisibility(visible: visible, child: const Card(child: Text('Copied'))),
      toastDuration: const Duration(seconds: 2),
    );
    final timer = Timer(const Duration(seconds: 2), () {
      if (!done.isCompleted) done.complete();
    });
    return PresentedOverlay<void>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([_]) async {
        timer.cancel();
        toast.removeCustomToast();
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
2. 返回 `PresentedOverlay(visible:, dismissed:, dismiss:)`。
3. **`dismissed`** 必须在**每一条**关闭路径上完成；路由使用退场动画后的
   `route.completed`，其它后端使用 `onClose`，没有信号时再自行合成。
4. **`dismiss`** 必须通过**那一条**浮层自己的句柄关闭它——绝不「关掉栈顶那个」。
5. 需要独立车道就给 `slot`；`exitDuration` 留给没有「动画结束」信号的后端，
   路由使用 `route.completed`。

### 编排纪律(源自 GetX / bot_toast 的 issue 史)

1. 管理器自持真相——**绝不**去读 `Get.isDialogOpen` / `Get.isSnackbarOpen`。
2. 只用各浮层自己的句柄关闭（保存的 Route 对象、`SnackbarController`、
   `CancelFunc`)——绝不「关掉栈顶」。
3. 缴械后端自带的编排(`onlyOne`、`crossPage`、GetX 的 snackbar 队列)——replace /
   dismiss 决策归管理器;**禁用** `Get.closeAllSnackbars()`(会悬挂已入队 future)。
4. 管理器统一的是**时序**而非 **z 序**:`bot_toast` 永远画在路由之上(它在
   `Navigator` 之上的 `Stack` 里);返回键归各后端。z 序完全由你的 `present:` 后端
   决定——想要明确控制,就在你自己的 `OverlayEntry` 里插到你要的深度。

## 完整 API 参考

| 1.0 成员 / 类型 | 契约 |
| --- | --- |
| `OverlayPredicate? auth` | 默认 null，与 route / when 按 AND；读取任意业务键。 |
| `OverlayClock clock` | 默认 `OverlayClock.system`；`now()` 与 `createTimer(Duration, callback)` 同源。 |
| `OverlayClock` / `FakeOverlayClock([DateTime? start])` | 测试时钟从 `package:layerman/testing.dart` 导入，默认 DateTime(2000)；`advance(Duration d)`、`pendingTimers`。 |
| `PresentContext<T>.close([T? result])` | 绑定本次提交并经过 beforeClose；仅作用于 open 条目。 |
| `void close(String id, [Object? result])` / `void dismiss(String id)` | 仅关闭已展示的 open 条目，排队中和解析中的条目不受影响，取消请用 remove；close 可携带结果，dismiss 使用 null。 |
| `void dispose()` / `bool get isDisposed` | dispose 一开始 isDisposed 即为 true；销毁中后端回调重入 open / submit 立即以 disposed 结束，其余修改无操作。 |
| `debugCheckInvariants()` | 显式检查不变量；debug 最外层批次结束自动执行。 |
| `OverlayMode mode` | 默认 `OverlayMode.queue`；可选 `replace` / `overlap`，不能同时选择。 |
| `RouteMatcher? route` / `List<RouteMatcher> pauseOnRoutes` | 默认 null / 空列表；使用 `exact` / `anyOf` / `regex`；null 或非字符串路由不匹配，`anyOf` 的输入列表不可修改。 |
| `OverlayPhase` / `OverlayRecord.phase` | `pending` / `resolving` / `open` / `closing`，使用枚举比较。 |
| `void suppress(String id, {Duration? duration})` | 只抑制带 cooldown 的提交；null 永久，正时长从现在起计，只延长。 |
| `OverlayCooldownStatus cooldownStatus(String id, OverlayCooldown cooldown)` | 查询 `canShow`、`permanentlyBlocked`、`wait`、`suppressed`（构造默认 false），不增加计数。 |
| `OverlayCooldownStatus.suppressed` | `final bool`，当前是否处于抑制中；构造参数默认 false。 |
| `void resetCooldown(String id)` / `void clearCooldowns()` | 重置单 id / 全部 session、持久化计数及抑制并重调度。 |
| `Set<String>? tags` / `OverlayRecord.tags` | 参数默认 null（空集合）；提交时复制为只读集合。 |
| `void clearTag(String tag)` | 批量移除带标签条目，绕过守卫，原因 `removed`。 |


见上文英文的 [Full API reference](#full-api-reference) 表格,列出了所有导出符号:
`Layerman`(构造 + 全部方法/getter,含 `pauseOnRoutes`/`currentRoute`)、
`open<T>` 的每个参数、`LayermanNavigatorObserver`、`OverlayCooldown`、
`OverlayCooldownStorage` / `MemoryCooldownStorage`、`OverlayRecord`、
`Present` / `PresentContext` / `PresentedOverlay`、`OverlayPredicate`。

新增类型的完整签名与默认值见上方 [Full API reference](#full-api-reference)，中英文共用同一份签名表。

| 成员 / 类型 | 契约 |
| --- | --- |
| `submit<T>` / `OverlayTicket<T>` | 参数与 `open<T>` 相同；`id`、`slot`、`result`、`outcome`、`isActive`、`data`；`close([T? result])`、`remove()`、`update(Object? patch)`。 |
| `OverlayOutcome<T>` / `OverlayEndReason` | `value` 与首次 `reason`；新增 `OverlayEndReason.suppressed` 表示抑制丢弃；全部原因及含义见 [架构生命周期表](ARCHITECTURE.md#4-条目生命周期)。 |
| `events` / `OverlayEvent` / `OverlayEventType` | 异步广播；事件有 `type`、`id`、`slot`、`reason`；类型为 `queued` / `shown` / `ended`。 |
| `hold([Object? reason])` / `OverlayHold` | 独立暂停；`reason`、`isReleased`、`release()`，`holdCount` 统计未释放数量。 |
| `OverlaySlotOptions` | `Duration? gap`、`int? maxQueued`、`Set<String> blockedBy`（默认空）；未提供前两项则继承全局间隔 / 不限队列长度；blockedBy 按其他槽占用门控激活。 |
| `dismissTimeout` / `resolveTimeout` / `expireAfter` | 默认关闭 10 秒、解析 30 秒、排队不限时；单条解析零时长禁用，构造参数 null 禁用。 |
| `resolvingIds` / `records` / `recordOf(String id)` | 解析中 id / 全部条目快照 / 单条快照或 null。 |
| `PresentContext.dataListenable` | `ValueListenable<Object?>`，实时数据；`data` 为快照。 |
| `DialogManager` / `BottomSheetManager` / `presentRoute` | Route 型 presenter；构造配置、单次覆盖、签名见英文完整表。 |
| `LayermanLifecycle` | `manager`、`isAttached`、`attach()`、`detach()`、`didChangeAppLifecycleState`；`pauseOn` 默认 paused / hidden。 |
| `LayermanNavigatorObserver` | `pathOf`、`routeFilter`、`contextKey`；默认 PageRoute 过滤与 route 键。 |

## 与 TS 版的刻意差异

- **不做 `stackIndex`/`isTopmost`**:层/z 序完全交给渲染这个浮层的 `present:` 后端
  (它自己的 `Overlay`/路由栈),队列本身不追踪也不暴露这个概念。
- **不内建跨标签页/跨 isolate 冷却同步**:如需,共享同一个 `OverlayCooldownStorage`
  后端即可。
- **时间型冷却会自唤醒**:与 headless TS 内核(仅在下一次调度触发时才重新评估)不同,
  被 `minGap` 或桶滚动挡住的 Flutter 条目会自行武装定时器,到期即自动显示;
  `session`/`total` 耗尽后丢弃条目，结果为 null。

### 脱离 Flutter 绑定测试（`FakeOverlayClock`）

应用的 dev_dependencies 加入 `test`，即可用普通 `test()` 测引擎，无需 flutter_test 绑定；
依赖解析仍需要 Flutter SDK。`OverlayClock` 的 `now()` 和 `createTimer` 必须同源，
不再单独注入日期回调。`advance` 触发虚拟计时器，Future 续体需另行排空。

```dart
import 'dart:async';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';
import 'package:test/test.dart';

void main() {
  test('注入时钟控制展示时长', () async {
    final clock = FakeOverlayClock();
    final manager = Layerman(clock: clock);
    addTearDown(manager.dispose);
    final dismissed = Completer<bool?>();
    final result = manager.open<bool>(
      duration: const Duration(seconds: 1),
      present: (_) => PresentedOverlay<bool>(
        visible: Future<void>.value(), // headless test: immediate visibility
        dismissed: dismissed.future,
        dismiss: ([value]) async { dismissed.complete(value); },
      ),
    );
    clock.advance(const Duration(seconds: 1));
    expect(await result, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(manager.activeIds, isEmpty);
    expect(clock.pendingTimers, 0);
  });
}
```

### debug 不变量检查

debug 下每个最外层操作批次结束自动运行 `debugCheckInvariants()`，检查容器身份、阶段、
排序、计时器与销毁状态。测试可显式调用（release 也可），违反契约抛 `StateError`。
不变量断言和随机序列测试降低重构风险，不能替代尚未完成的 Gate / 显式状态机。

## 测试

```bash
flutter test                                            # 单元(widget)测试
cd example && flutter test integration_test/orchestration_test.dart -d <serial> # 真机编排测试
```

单元测试用 `WidgetTester` 覆盖:串行队列、关闭推进、优先级、`Future` 结果、
`replace`/`affix`/`overlap`、条件、冷却(含自唤醒)、`resolve`、`beforeClose`、
pause/resume、`update`/`clearWhere`、`present:` 适配器、相位切换。`example/` 是一个
完整的真机 demo,通过管理器编排 GetX + bot_toast + 原生 `showDialog`。
手机验证设备为华为 STG-AL00 / Android 12（实现任务报告）；Windows 桌面会抢焦点，不无人值守运行。

## 许可

MIT —— 见 [LICENSE](LICENSE)。
