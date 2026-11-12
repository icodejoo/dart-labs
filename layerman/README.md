# layerman

**English** | [简体中文](README.zh-CN.md)

[Live demo](https://icodejoo.github.io/dart-labs/layerman/)

A **headless overlay queue manager** for dialogs, modals, bottom sheets, toasts
and banners. It decides *when* and *which* overlay is shown, using a serial
one-at-a-time queue with named slots, priority, `replace`, `affix` and `overlap`.
It never draws anything itself: each overlay is shown by a `present:` backend
you supply (`showDialog`, GetX, `bot_toast`, your own `OverlayEntry`, ...).
`open()` returns a `Future<T?>` with the result, like `showDialog`, and closing
has two phases so your backend can play its own exit animation.

Because `present:` is the only adapter, one queue can cover overlays from
different libraries: native `showDialog`, GetX (`Get.dialog` / `Get.snackbar`),
`bot_toast`, `fluttertoast`, and so on.

> Design note: this is the Flutter sibling of the framework-agnostic headless TS
> package `@codejoo/overlaymanager` and follows the same headless design. The
> core imports no `package:flutter/widgets.dart` and has no `Overlay` layer. It
> only keeps the orchestration rules.

- [Features](#features)
- [Install](#install)
- [Getting started](#getting-started)
- [Why there is no `builder:`](#why-there-is-no-builder)
- [Usage](#usage)
- [Integrating other overlay libraries](#integrating-other-overlay-libraries-the-present-adapter)
- [Full API reference](#full-api-reference)
- [Deliberate differences from the TS package](#deliberate-differences-from-the-ts-package)
- [简体中文文档](README.zh-CN.md)

## Features

- **Don't show again**: result-based `suppress`, permanent or timed, for submissions with `cooldown`.
- **Cross-slot blocking**: `OverlaySlotOptions.blockedBy` holds new activations while another slot is occupied.
- **Business gate**: `gate:` returns `OverlayVerdict.pass/waitUntil/drop` for eligibility checks that are not a route or login check.
- **Visible confirmation**: `PresentedOverlay.visible` completes after the first painted frame. `shown` and cooldown counting wait for it.
- **Typed options (1.0)**: `mode: OverlayMode.queue/replace/overlap`, `RouteMatcher`
  and `OverlayPhase` replace ambiguous options and string phase comparisons.
- **Inspection and grouping**: `cooldownStatus` (`OverlayCooldownStatus`),
  `resetCooldown` / `clearCooldowns`, and copied `tags` / `clearTag`.
- **Frame-safe submission**: `open` defers presentation and notifications when
  called during `build()`. Manager notifications are batched per operation, and
  unused slots are reclaimed.
- **Serial queue**: one overlay at a time per slot. The next one shows when the
  current one is removed, with an optional `gap` between them.
- **Named slots**: independent serial queues (for example `toast` and `dialog`)
  that run in parallel.
- **Priority**: higher priority shows first. Ties go first in, first out.
- **`replace`**: preempts the slot's current overlay and shows immediately. It
  skips a pending gap and goes ahead of already-queued entries. The preempted
  overlay is **closed** (result `null`) and never shown again, because a
  dismissed backend can't be re-presented faithfully.
- **`affix`**: protects the current overlay from `replace`. The blocked
  replacer waits at the front of the queue.
- **`overlap`**: skips the queue and stacks on top (global alerts, blocking
  loaders). After `delay`, conditions and cooldown are checked once: show now or never.
- **Conditions**: the AND of `route`, `auth(ctx)` and `when(ctx)`, driven by
  `setContext({...})`. A shown overlay whose conditions stop holding is
  dismissed automatically (`dismissWhenUnmet`, default true). Queued entries
  just wait.
- **Cooldown**: `OverlayCooldown(session:, total:, day:, hour:, minute:,
  minGap:)`. Every cap you set must pass, and a show counts once the overlay is
  confirmed visible. State lives in an `OverlayCooldownStorage` (default
  in-memory; back it with `shared_preferences` in real apps). A **time-based**
  cap (`minGap` and bucket rollover) shows the queued entry automatically when
  it expires.
- **Backend-driven `resolve`**: fetch the payload only when the overlay gets the
  slot. Return `null` to skip it. The slot is held while resolving. Ordinary
  arrivals wait, but `replace` can preempt and discard it.
- **`beforeClose` guard**: return `false` (sync or async) to veto a `close()`,
  for example an unsaved-changes confirmation. `remove` and `clear` bypass it.
- **`Future<T?>` results**: `open()` returns a future that resolves with the
  value you close with, or `null` if the overlay is dismissed.
- **Two-phase close**: `close()` settles the result immediately, then waits for
  your backend's `dismissed` signal (up to `dismissTimeout`) plus an optional
  per-`open()` `exitDuration` grace before the queue moves on. This gives the
  backend time to play its own exit animation.
- **`pauseAll` / `resumeAll`**: full freeze. Nothing new shows, and running
  `duration` countdowns pause. Per-id `pause` / `resume` freeze one countdown.
- **Auto route awareness**: `LayermanNavigatorObserver` feeds real navigation
  into `route` conditions (works with vanilla `Navigator`, GetX and go_router).
  `pauseOnRoutes` lists "no-overlay zone" routes: the queue freezes on entry and
  resumes on exit, alongside manual `pauseAll` / `resumeAll`. `currentRoute`
  returns the tracked value.
- **`update(id, patch)`**: shallow-merges into a shown overlay's `data` and
  notifies listeners. It doesn't render anything or change the queue.
  `PresentContext.data` is a snapshot taken at presentation; use
  `dataListenable` for live values.
- **`clearWhere(test)`**: removes entries selectively (for example, everything
  in group X).
- **Per-overlay `delay` and `duration`** (auto-close).
- **External overlay systems**: one queue over `showDialog`, GetX, `bot_toast`,
  `fluttertoast`, or anything you can show and close.
- **Route presenters**: reusable `DialogManager`, `BottomSheetManager` and `presentRoute`.
- **Tickets and events**: typed `submit<T>`, outcomes with reasons, async events.
- **Independent pause sources**: `hold()` and automatic `LayermanLifecycle` binding.
- **Bounded waiting**: resolve and dismiss timeouts, `expireAfter`, per-slot `gap` / `maxQueued`.
- **Live data and diagnostics**: `dataListenable`, `resolvingIds`, `records`, `recordOf`.

## Install

```yaml
dependencies:
  layerman: ^1.0.0
```

```dart
import 'package:layerman/layerman.dart';
```

The package has **no third-party runtime dependencies**, only the Flutter SDK.
The example app uses `get` and `bot_toast` just to show the external adapter.

## Getting started

`Layerman` is a plain object. It mounts nothing and needs no widget above your
app. Create one and keep a reference the way you already share state in this app
(a singleton, a GetX binding, a `Provider`, DI, ...):

```dart
final manager = Layerman(gap: const Duration(milliseconds: 300));
```

Use it wherever you call `open()` / `close()`, and pass a `present:` backend at
each call site. There is no scope or attach step; see [Usage](#usage) below and
the next section for why.

### Why there is no `builder:`

`layerman` is a **queue orchestrator, not a renderer.** It decides *when* and *which* overlay shows. It never owns a widget or an `Overlay` layer. Every overlay is shown through a `present:` backend you supply.

Earlier versions had a `builder:` that returned a `Widget`, which the manager mounted into its own `Overlay`. That made the manager part of the UI: it had to own an `OverlayState`, stay attached to the widget tree and ship an `OverlayManagerScope`. This went against what the package is for.

`present:` can do everything `builder:` did. Inside it you build any UI (`showDialog`, `Get.dialog`, `BotToast.show`, `Navigator.push`, or an `OverlayEntry` you insert yourself) and return a `PresentedOverlay(visible: ..., dismissed: ..., dismiss: ...)` handle. A `present:` backend that owns its own `OverlayEntry` can render anything `builder:` could, so nothing is lost. The core is headless (no `flutter/widgets` import), like the TS sister package.

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

For route-based dialogs, use `DialogManager`, or keep your own Route object: use `route.completed`
for `dismissed` and close that exact route through its own navigator. See the recipes below.

## Usage

### Shared route presenters

Create these once, next to `manager`. Pass the same `navigatorKey` to your app,
and call `open` after that Navigator is mounted. The examples use `dialogs((ctx, close) => widget)`.

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

`open()` returns a `Future<T?>` right away. The overlay may show now or wait in
the queue. The future resolves when the overlay is closed.

### Migrating from 0.x

The full list is in the [1.0.0 migration table in CHANGELOG](CHANGELOG.md#100).
The changes you are most likely to hit:

| 0.x | 1.0.0 |
| --- | --- |
| `replace: true` / `overlap: true` | `mode: OverlayMode.replace` / `mode: OverlayMode.overlap` (exactly one; default `queue`) |
| `route: '/home'`, `['/a', '/b']`, `RegExp(...)` | `RouteMatcher.exact` / `anyOf` / `regex`; same for `pauseOnRoutes` |
| `requiresAuth: true` | `auth: (ctx) => ctx['auth'] == true`; the key and policy are yours |
| `record.phase == 'open'` | `record.phase == OverlayPhase.open` |
| `Layerman(now: ...)` | `Layerman(clock: ...)` with an `OverlayClock` (`now()` + `createTimer`); tests use `FakeOverlayClock` |
| `PresentedOverlay(dismissed:, dismiss:)` | `visible:` is now **required**: complete it after the first painted frame. `shown` and cooldown counting happen only then (see [the `Present` adapter](#integrating-other-overlay-libraries-the-present-adapter)); `presentRoute` and `OverlayVisibility` provide it for you |
| `DialogManager(key, manager: manager)` | drop `manager:`; the builder's `close` goes through `ctx.close` and `beforeClose` |
| overlap ignored `delay` | overlap now waits for `delay` before its now-or-never check |

```dart
// 0.x
manager.open(id: 'expired', replace: true, requiresAuth: true, present: present);
// 1.0.0
manager.open(
  id: 'expired',
  mode: OverlayMode.replace,
  auth: (ctx) => ctx['auth'] == true,
  present: present,
);
```

### Building overlays during `build()`

When `open` is called during `build()`, it defers `present` and manager
notifications until after the frame. It still returns its future immediately.
Queued entries keep their order, and pause, conditions and hydration are checked
before presentation. Guard against repeated builds so you don't submit again and again:

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

A public operation emits at most one manager notification, after its synchronous
changes finish. Async continuations are separate batches. Calls during build are
merged into one notification after the frame. `dataListenable` and async `events` are separate channels.

### Tags

`tags` defaults to an empty set and is copied into read-only `OverlayRecord.tags`
at submission. `clearTag(tag)` removes matching pending, resolving, open and
closing entries with `removed`, and bypasses `beforeClose`.

```dart
manager.open<void>(id: 'campaign', tags: {'promo', 'home'},
  present: dialogs<void>((ctx, close) => const Text('Campaign')));
final record = manager.recordOf('campaign');
if (record?.phase == OverlayPhase.open) {
  manager.clearTag('promo');
}
```

### Queue, priority, replace, affix, overlap

`mode` picks exactly one `OverlayMode`: `queue` (default), `replace` or `overlap`.
`affix` is independent. Replace and overlap can't be combined.

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

`RouteMatcher.exact('/promo')` matches one path.
`const RouteMatcher.anyOf(['/promo', '/home'])` matches any listed path.
`RouteMatcher.regex(RegExp(r'^/promo/'))` uses `hasMatch`. Null and non-string
context routes never match.

Overlap respects `delay`: it waits first, then does the now-or-never eligibility
check. Remove, clear, same-id reopen and dispose cancel the waiting entry.
Pause and pending hydration can hold it longer. It never joins a serial slot.

### Conditions (`when` / `route` / `auth` / `setContext`)

Overlays can depend on an app-wide context you push with `setContext`. A queued
overlay whose conditions don't hold just **waits**. A *shown* overlay whose
conditions stop holding is dismissed automatically, unless `dismissWhenUnmet: false`.

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
Only `route` reads a reserved key (`route`). `auth` and `when` read whatever keys
you push with `setContext`; the engine never reads an `auth` key on its own.
A throwing `auth` or `when` is reported once per entry and treated as unmet.
Conditions are push-driven: when external state changes, call `setContext` (even
`setContext({})`) or trigger scheduling another way. They don't wake up on time alone.

Judgment callbacks (`when`, `auth`, and the test passed to `clearWhere`) are read-only.
Any manager change, ticket or context operation, hold release or dispose inside them throws
`StateError` (message: “判断函数内不能修改 Layerman”, meaning “a predicate must not mutate Layerman”) before any state changes. Condition errors are
reported once per entry and treated as unmet. `clearWhere` test errors propagate. Getters still work.

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

To migrate `requiresAuth: true`, use `auth: (ctx) => ctx['auth'] == true`.
For the old guest-only `requiresAuth: false`, use `auth: (ctx) => ctx['auth'] != true`.
Your app chooses the keys and the role/permission policy.

### Business eligibility (`gate:`)

`gate` is for eligibility that is not a route, a login check or a plain predicate.
It returns an `OverlayVerdict`. It runs after `route`, `auth` and `when` pass (AND)
and before activation, and it only gates activation: it never re-judges an overlay
that is already resolving or shown, and it never triggers `dismissWhenUnmet`.

- `OverlayVerdict.pass()` allows activation (other constraints still apply).
- `OverlayVerdict.waitUntil(retryAt)` waits and re-judges at `retryAt`, or earlier
  when `setContext` changes. Serial entries and overlaps can both wait. A past `retryAt`
  counts as pass. Compute it from `manager.clock.now()`, not `DateTime.now()`,
  otherwise `FakeOverlayClock` tests get the wrong deadline.
- `OverlayVerdict.drop()` rejects permanently; the entry ends as `OverlayEndReason.gated`.

A throwing gate is reported once per entry (shared with `when` / `auth`). Serial entries
keep waiting; overlaps end as `dropped`. Like other judgment callbacks, it is read-only
(mutating the manager inside throws `StateError`).

```dart
manager.open<void>(
  id: 'promo',
  present: dialogs<void>((ctx, close) => const Text('Promo')),
  gate: (ctx) {
    if (ctx['declined'] == true) return const OverlayVerdict.drop();
    if (ctx['ready'] == true) return const OverlayVerdict.pass();
    return OverlayVerdict.waitUntil(
      manager.clock.now().add(const Duration(minutes: 5)),
    );
  },
);
```

### Auto route awareness (`LayermanNavigatorObserver` + `pauseOnRoutes`)

Setting `route` with `setContext` by hand (in every page's lifecycle) is
boilerplate. `LayermanNavigatorObserver` does it for you. Add it to
`navigatorObservers` and it works with vanilla `Navigator`, GetX and go_router,
since all three drive a real Flutter `Navigator` and this is a standard
`NavigatorObserver`. It only observes: it never pushes, pops or otherwise touches
navigation.

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  navigatorObservers: [LayermanNavigatorObserver(manager)],
  home: const Scaffold(),
);
```

Once attached, treat it as the only writer of the `route` context key. A
manual `setContext({'route': ...})` is overwritten by the next navigation event.
Read the tracked value with `manager.currentRoute` instead of keeping your own
copy. The path defaults to `route.settings.name`; pass `pathOf` if your router
stores it elsewhere. A route with no usable path (an anonymous `MaterialPageRoute`
without `settings.name`) reports `null`, and conditions never match `null`.
Flutter has no other notion of "path" for anonymous routes.

Things Flutter does that are easy to miss:

- **`MaterialApp.home`'s implicit route is named `'/'`**, not `null` and not
  `'/home'`. That is Flutter's own `Navigator.defaultRouteName`. To gate on the
  home page by a specific string, name it explicitly via `initialRoute` /
  `routes` (or a named `RouteSettings`) instead of `home:`.
- **Since 0.3.0 only `PageRoute` is tracked by default.** Dialogs, bottom
  sheets and menus leave the last accepted page path alone, so route-gated
  dialogs no longer dismiss themselves and popups can't release a no-overlay zone.
  To get the 0.2.x behavior back, pass `routeFilter: (r) => true`.
- Use `contextKey: 'tabRoute'` for a nested Navigator and read it in `when`.
  `route:` and `pauseOnRoutes` still read only the default `route` key.

`pauseOnRoutes` builds a "no-overlay zone" on top of this. Entering a matching
route freezes the whole queue, exactly like `pauseAll()`: nothing new
activates. Leaving it resumes, like `resumeAll()`. It works alongside manual
`pauseAll` / `resumeAll`: leaving the zone doesn't override an unrelated manual
pause, and a manual `resumeAll()` doesn't override an active zone.

```dart
final manager = Layerman(pauseOnRoutes: const [RouteMatcher.exact('/checkout')]);
// While the tracked route is '/checkout', no new overlay shows — queued ones
// wait and activate the moment the route changes away.
```

Whether an *already-shown* overlay should close when you navigate into a zone
is deliberately not a blanket rule. Use the same `route` / `when` +
`dismissWhenUnmet` conditions described above (they work the same whichever
`present:` backend renders the overlay), or use a backend's own navigation-aware
close option if it has one.

### `DialogManager` / `BottomSheetManager`

Create once with the app's `navigatorKey`. Only configuration is kept; each
presentation owns its Route. The builder's `close([result])` always goes through
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
`routeNamePrefix: 'layerman://'`. Colors fall back to the theme (for dialogs, the
last fallback is `Colors.black54`). Sheets also default to `isScrollControlled: false`,
`enableDrag: true`, `showDragHandle: null`, `backgroundColor: null`.
Use `presentRoute` for pages or custom Route construction; see the manual recipe below.

### Outcome / tickets / events

`submit<T>` takes exactly the same arguments as `open<T>` and returns an
`OverlayTicket<T>`. `result` is a `Future<T?>`; `outcome` is a
`Future<OverlayOutcome<T>>` with `value` and the first `reason`. Both settle before
the exit animation finishes. Typed `ticket.close([T? result])` honors the guard;
`remove()` bypasses it, `update(patch)` updates data, and `data` is a
`ValueListenable<Object?>`. An old ticket can't control a newer submission with the
same id. `isActive` includes pending, resolving and closing entries while they are still tracked.
`events` is an asynchronous broadcast stream of `queued`, `shown` and `ended`
(`OverlayEventType`), each with `id`, `slot`, `type` and an optional `reason`.
Subscribe before submitting; there is no replay. `ended` means first settlement,
not the end of the animation.

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

For each submission, events go queued → shown → ended, even when `present` closes the
entry synchronously. A presentation that throws emits no shown event, only ended (`failed`).

### Pause sources: `hold` and `LayermanLifecycle`

Manual pause, `pauseOnRoutes` and unreleased holds combine with OR. `hold(reason)`
returns an `OverlayHold`. `release()` is idempotent, and `holdCount` counts holds only.
Releasing one source never cancels another. `LayermanLifecycle` takes a hold
on `AppLifecycleState.paused` or `hidden` by default (`pauseOn` overrides the set)
and releases it on other states. `attach()` syncs immediately; `detach()`
unregisters and releases. Both are idempotent. Detach when you replace the owner.

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

`dismissTimeout` defaults to 10 seconds, counted from the request to dismiss the
backend; `resolveTimeout` defaults to 30 seconds. Both constructor options accept
`null` for no timeout. A per-entry `resolveTimeout: null` inherits the default;
`Duration.zero` disables that entry's resolve timeout. At constructor level, zero
schedules an immediate timeout and does not disable it. Timeouts report
`TimeoutException` through `FlutterError.reportError` and release the slot. A resolve
timeout ends as `skipped`; a dismiss timeout keeps the result and reason already
settled. Neither cancels the backend's underlying work or guarantees its UI is removed.
`expireAfter` counts serial waiting time before activation, including pauses.
It doesn't apply to overlap or active entries (`queueExpired`). A slot's `gap`
overrides the global `gap`. A positive `maxQueued` excludes active entries and evicts
the tail of the sorted queue (`queueFull`), which may be the entry just submitted.
These deadlines keep running during a pause; only `duration` freezes.

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
The delay belongs to the waiting entry: removing or overwriting that entry cancels the old
wait and reschedules the slot. `maxQueued` is enforced after activation decisions, including
post-frame scheduling during build. Entries waiting for gap, delay, conditions, cooldown or
`blockedBy` still count, and the submitted entry can still be evicted.

#### Cross-slot blocking (`blockedBy`)

```dart
final manager = Layerman(slots: {
  'toast': OverlaySlotOptions(blockedBy: {'modal'}),
  'banner': OverlaySlotOptions(blockedBy: {'modal'}),
});
```

`OverlaySlotOptions.blockedBy` is a `Set<String>`, empty by default. While a listed slot
is occupied, this slot activates no new entries. Occupied means a serial active entry
(resolving, open or closing, including the `exitDuration` grace) or an active overlap in that slot.
Gap, appear delay, cooldown waits, queues and waiting overlaps **do not count**,
so entries can appear between two blocker entries. **Already activated entries
keep showing and their duration continues**: a toast visible before a modal stays visible.

Blocked serial entries queue; `expireAfter` and `maxQueued` still apply. Replace doesn't
preempt while blocked and keeps its front-band order after release. A same-id serial reopen
queues with takeover precedence when eligible. Overlaps that pass initial eligibility are
held, then re-checked now-or-never on release.
Release happens at the end of the outermost operation batch, so replace's remove-old/activate-new
step can't let another slot slip through. Only slots actually waiting for unblock
and held overlaps are reconsidered; no condition trigger is added for other slots.
Cycles follow first activation, with no fairness guarantee. A nonexistent slot name has
no effect; blocking itself triggers a debug assertion.

### Live data (`dataListenable`)

`PresentContext.data` is a snapshot. Listen to `dataListenable` for `update`
and resolved values. `ticket.data` exposes the same channel and keeps its last
value after settlement. The manager deliberately doesn't dispose this listenable,
so listeners can detach after exit animations. Remove manually registered listeners
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
`value as Map<String, dynamic>` keeps working. Other Map combinations merge into a generic Map.

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

**1.0.0 completes the 0.3.0 behavior:** when a `session` or `total` cap is used up,
serial submissions settle as `null` (`capped`) right at submission. Queued entries
are checked again after hydration, even while the slot is occupied or the manager is
paused. For a wait you can retry, use time-based caps; for a new campaign, use a new id.

All caps you set must pass (AND). A cap counts once `PresentedOverlay.visible` confirms the first painted frame.
Counters are keyed by `id`, so a cooldown needs an explicit `id` (asserted in
debug, because an auto-generated id changes on every open). `session` lives in memory;
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
queue; overlaps are held, not dropped. Submissions without `cooldown` are unaffected.
Migration: session-only entries that used to appear before `ready()` now wait for
one storage read. Opening before `ready()` is still safe. A failed read or write is
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

`cooldownStatus(id, cooldown)` returns an `OverlayCooldownStatus`. `canShow` means
all caps and suppression pass. `permanentlyBlocked` means session/total exhaustion or
permanent suppression. `wait` is `Duration.zero` when eligible, the longest remaining
time-based wait otherwise, or `null` when permanently blocked or waiting for
cooldown-store hydration. `suppressed` reports an unexpired timed or permanent suppression.
Before hydration, `canShow` is false and `wait` is null; `permanentlyBlocked` and
`suppressed` still reflect known in-memory state (including an exhausted session cap
or a locally set permanent suppression).
`resetCooldown(id)` clears that id's session and persisted counters and its suppression;
`clearCooldowns()` clears all counters and suppression. Both re-evaluate waiting entries and
persist the reset. A reset can't restore entries that already ended as `capped` or `suppressed`.

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
server time). A malformed stored record is reported and skipped. Its raw value is written back
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
A manual open without cooldown still works, for example a “View campaign” entry in settings.
Already activated entries are unaffected. Suppression shares the counter record (JSON key
`su`), so `resetCooldown(id)` / `clearCooldowns()` also clear it.
Repeated calls keep the later expiry, and forever wins: suppression only extends.
So “suppress three days on any close, then forever on never” works in either order.
To shorten it, reset, which also clears counters.

Permanent suppression immediately ends queued serial entries with `OverlayEndReason.suppressed`,
even while paused, occupied or awaiting hydration. Timed suppression leaves serial entries
waiting and wakes them at expiry (or at a later time-based cap); `expireAfter` can bound that wait.
An overlap checks at its delay deadline or on release, and is discarded as suppressed when
suppression blocks its cooldown. Cooldown rejection reasons rank `suppressed > capped > dropped`;
a failed route/auth/when condition still yields `dropped`.
Permanent suppression gives `permanentlyBlocked: true, wait: null`. For timed suppression,
`wait` is the maximum of the remaining suppression and other time-based waits (unless
permanently blocked or awaiting hydration).

### Backend-driven `resolve`

Fetch data only when the overlay is granted the slot. `resolve` has type
`Future<T?> Function()?`, using the same `T` as the result. Returning `null` skips the
overlay without counting cooldown. Ordinary arrivals wait while it resolves;
`replace` can preempt and discard it. `ctx.data` holds the resolved value.

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
`beforeClose`. It is tied to the entry's identity, so an old callback can't close a
reopened entry with the same id. Close calls are ignored for non-open entries and while
a guard is pending. Barrier and back dismissals driven by the backend still bypass the guard.

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

`beforeClose` gates `close()` / `dismiss()` only. `remove`, `clear` and auto-dismiss
bypass it. While an async guard is pending, further `close()` / `dismiss()` calls
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

`update` shallow-merges Maps (otherwise it replaces), notifies `dataListenable`
and manager listeners, and leaves the queue alone. Read live values through
`PresentContext.dataListenable`; `PresentContext.data` stays the snapshot from presentation.

### Two-phase close / exit animation

`close()` settles the result and asks your backend to close. The queue advances
only after the backend's `dismissed` plus the optional `exitDuration` grace,
or when the `dismissTimeout` watchdog releases the entry. The exit animation itself is entirely your
backend's job. Route backends use `route.completed`, which completes after the
exit animation with the pop result; the future returned by `showDialog` or
`Navigator.push` completes when the pop starts. Use `exitDuration` only for backends
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

`resolvingIds` lists resolving entries (overlaps too). `records` includes every
managed phase, and `recordOf(id)` returns one snapshot or `null`. `queuedIds` follows the
actual replace / priority / FIFO order within each slot, followed by held overlaps.
Independent slots have no global display order.

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

A resolving entry is listed in `resolvingIds` and `records` but not in
`activeIds` / `queuedIds`; `isShowing` is false until it opens.

`Layerman` is a `ChangeNotifier`, so `addListener` / `AnimatedBuilder`
can rebuild UI (for example a debug HUD) on every transition.

## Integrating other overlay libraries (the `Present` adapter)

A project rarely has just one overlay system. `open(present: ...)` lets the
manager **schedule** overlays that are **rendered by another library**. The
`present` callback runs only when the queue grants permission, and returns a
two-way handle:

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
  completes with. So complete `dismissed` on *every* close path (user tap,
  barrier, back button, timeout, your `dismiss`).
- `close` / `replace` / `clear` / `remove` call **`dismiss`** to close the
  backend for the manager.
- Route backends use **`route.completed`** for `dismissed`: it waits for the
  exit animation and carries the pop result. `showDialog` / `Navigator.push`
  futures complete when the pop starts. Use `exitDuration` (a grace period
  after `dismissed`) only for backends without an animation-end signal.

One serial queue (with priority, replace, cooldown and conditions) now governs
dialogs, snackbars and toasts from different libraries in the same way.

### Native `showDialog`

Prefer `DialogManager` for dialogs. For custom control, here is a hand-written
Route recipe: `presentRoute` pushes your route, waits for `route.completed` and
targets that exact route when closing. No `exitDuration` estimate is needed. A top
route is popped with the result only if it has no internal history. A covered route
uses `removeRoute(route)` without a result, for Flutter 3.27 compatibility.
`manager.close` still delivers its requested result. Closing a covered route
directly through the returned handle yields `null`.

A route with internal history (for example an open Drawer or persistent bottom sheet) also
uses `removeRoute`, and its result follows the same rules as a covered route.

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

`Get.dialog` / `Get.bottomSheet` don't expose their Route objects. Push a
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
    // Visibility is confirmed only on the first frame after a successful build, mount and top-of-stack.
    return presentRoute(navigator, route);
  },
);
```

For a bottom sheet, change only the `route` construction above. The push,
`route.completed` and targeted dismiss logic stay the same. `isScrollControlled` is required:

```dart
final route = ModalBottomSheetRoute<bool>(
  settings: RouteSettings(name: 'om://${ctx.id}'),
  builder: (_) => const ConfirmDialog(),
  isScrollControlled: false,
);
```

### GetX snackbar

`SnackbarController.future` completes after the exit animation, which makes it the
cleanest signal. GetX's internal snackbar queue is bypassed because the manager
does the serializing.

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

> Tip: a toast or snackbar on its **own slot** deliberately runs in parallel with
> your main dialog queue (the usual UX). Put it on the **default slot** if you
> want it strictly serialized behind dialogs.

### A navigated page as a queue entry

Use `presentRoute` with a `TransitionRoute<T>` for pages. The push happens only
when the queue grants the slot, and the page holds the slot until its exit completes.

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

Turn off its own competing behavior: `onlyOne: false` and a dedicated
`groupKey`. `onClose` is the single "fully closed" signal, and the `CancelFunc`
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
have to **synthesize** the `dismissed` signal with a timer matching the toast length.

```dart
manager.open<void>(
  id: 'copied',
  slot: 'toast',
  present: (ctx) {
    // The native showToast gives no visibility report; use the FToast widget, which confirms the first frame.
    final visible = Completer<void>();
    final done = Completer<void>();
    final toast = FToast()..init(navigatorKey.currentContext!); // A context inside a mounted page, below the Overlay.
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
> own removal. The shape is the same as the bot_toast recipe.

### Writing your own adapter — checklist

For any library you can *show* and *close*:

1. Call the library's show API inside `present`.
2. Return `PresentedOverlay(visible:, dismissed:, dismiss:)`.
3. **`dismissed`** must complete on *every* close path (user, timeout, your
   `dismiss`). For routes use `route.completed` (after the exit animation).
   Otherwise use `onClose`, or synthesize a signal if there is none.
4. **`dismiss`** must close *that specific* overlay through its own handle, never
   "close whatever is on top".
5. Give it a `slot` if it should run in its own lane. Use `exitDuration`
   only for backends without an animation-end signal; routes use `route.completed`.

### Rules of engagement (from GetX / bot_toast issue history)

1. The manager owns the truth. Never poll `Get.isDialogOpen` /
   `Get.isSnackbarOpen` etc.
2. Close only through each overlay's own handle (the captured Route object,
   `SnackbarController`, `CancelFunc`), never "pop whatever is on top".
3. Turn off backend-side orchestration (`onlyOne`, `crossPage`, GetX's snackbar
   queue). Replace and dismiss decisions belong to the manager. Never call
   `Get.closeAllSnackbars()` (it hangs queued futures).
4. The manager unifies **sequencing**, not **z-order**: `bot_toast` always
   paints above routes (it lives in a `Stack` over the `Navigator`), and the
   back button stays with each backend. Z-order is up to your `present:`
   backend. Insert your own `OverlayEntry` at the depth you need if you want
   explicit control.

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
| `bool get isPaused` | Whether the queue is frozen by a manual pause, a route zone or unreleased holds. |
| `bool get isDisposed` | True from the moment `dispose()` starts, so a deferred callback can avoid calling into a torn-down manager. |
| `List<String> get activeIds` | Ids in open/closing, serial + overlaps; excludes resolving. |
| `List<String> get queuedIds` | Pending ids in per-slot display order plus held overlaps; excludes resolving. |
| `bool isShowing(String id)` | Whether `id` is open/closing; false while resolving. |
| `Future<T?> open<T>({...})` | Enqueue/show an overlay through your `present:` backend; returns its result future. See below. |
| `void close(String id, [Object? result])` | Closes open entries only; queued/resolving entries are unaffected (cancel with `remove`). Two-phase close, delivering `result` (runs `beforeClose`; repeated calls while an async guard is pending are ignored). Throws `ArgumentError` (leaving the overlay untouched) if `result` isn't a `T?` of its `open<T>()`. |
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
| `Present<T> present` | required | Renders (and later closes) the overlay through your UI backend. See [integration section](#integrating-other-overlay-libraries-the-present-adapter). |
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
| `OverlayGate? gate` | `null` | Business eligibility returning `OverlayVerdict` (`pass` / `waitUntil` / `drop`); runs after route/auth/when; see [Business eligibility](#business-eligibility-gate). |
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

Add it to `navigatorObservers`. It listens to `didChangeTop` (the current topmost
route), which covers cold start, push, pop, replace and declarative
`Navigator(pages:)` rebuilds in one signal, unlike the legacy push/pop/
replace/remove callbacks. It feeds the route into `manager.setContext({'route': ...})`
automatically. The update is deferred to a post-frame callback (safe even if
navigation happens mid-build) and guarded by `manager.isDisposed` both before
scheduling and inside the callback. A throwing `pathOf` is reported via
`FlutterError.reportError` instead of propagating, and the route is then treated
as unresolvable (`null`). It works with vanilla `Navigator`, GetX and go_router.

### `OverlayCooldown`

```dart
const OverlayCooldown({int? session, int? total, int? day, int? hour, int? minute, Duration? minGap})
```

All non-null caps must pass (AND) and count once the overlay is confirmed visible. `session` (per app
run) is in memory. `total` / `day` / `hour` / `minute` (local calendar buckets)
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

`MemoryCooldownStorage` is the default in-memory implementation. Sharing one
instance keeps counters across manager recreation, but not across a process restart. Provide your own (for example `shared_preferences`) for persistence.

### `OverlayRecord`

Read-only snapshot handed to `clearWhere`. Fields: `final String id`,
`final String slot`, `final Object? data`, `final bool active`,
`final OverlayPhase phase`, `final Set<String> tags` (copied, read-only).
Compare phases with `OverlayPhase.pending` / `resolving` / `open` / `closing`.

### `Present<T>` / `PresentContext<T>` / `PresentedOverlay<T>`

```dart
typedef Present<T> = PresentedOverlay<T> Function(PresentContext<T> context);
```

`PresentContext<T>` (passed to your `present` callback) has these fields: `final String id`,
`final String slot`, `final Object? data`, `final ValueListenable<Object?> dataListenable`.

```dart
class PresentedOverlay<T> {
  PresentedOverlay({required this.visible, required this.dismissed, this.dismiss});
  final Future<void> visible;                         // successful first visible frame
  final Future<T?> dismissed;                          // backend "closed" signal
  final Future<void> Function([T? result])? dismiss;   // orchestrator close
}
```

### `OverlayPredicate` / `OverlayGate` / `OverlayVerdict`

```dart
typedef OverlayPredicate = bool Function(Map<String, Object?> context);
typedef OverlayGate = OverlayVerdict Function(Map<String, Object?> context);
```

`OverlayVerdict`: `const OverlayVerdict.pass()`, `const OverlayVerdict.waitUntil(DateTime retryAt)`,
`const OverlayVerdict.drop()`; fields `final DateTime? retryAt` (null unless waiting) and
`final OverlayEndReason? reason` (`gated` for drop). Use `manager.clock.now()` to compute `retryAt`.

### Tickets, outcomes, events and holds

| Type / signature | Contract |
| --- | --- |
| `OverlayTicket<T>` | `final String id`, `final String slot`; `Future<T?> get result`, `Future<OverlayOutcome<T>> get outcome`, `bool get isActive`, `ValueListenable<Object?> get data`; `void close([T? result])`, `void remove()`, `void update(Object? patch)`. No public constructor. |
| `const OverlayOutcome<T>(T? value, OverlayEndReason reason)` | `final T? value`, `final OverlayEndReason reason`; first settlement wins. |
| `OverlayEndReason` | `closed`, `dismissedByBackend`, `expired`, `replaced`, `superseded`, `removed`, `unmet`, `skipped`, `dropped`, `capped`, `suppressed`, `gated`, `queueFull`, `queueExpired`, `failed`, `disposed`. |
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

- **`stackIndex` / `isTopmost` are not available.** Layer and z-order are up to
  whichever `present:` backend renders the overlay (its own `Overlay` or route
  stack). The queue doesn't track or expose them.
- **No built-in cross-tab or cross-isolate cooldown sync.** Share one
  `OverlayCooldownStorage` backend if you need it.
- **Time-based cooldown wakes by itself.** The headless TS core re-checks only on
  the next scheduling trigger. Here, a Flutter entry blocked by a `minGap` or a
  bucket rollover sets a timer and shows itself when the window ends. Exhausted
  `session` / `total` caps discard the entry with a `null` result and
  `OverlayEndReason.capped`.

### Testing without a Flutter binding (`FakeOverlayClock`)

Add `test` to your app's dev dependencies. This uses ordinary `test()`, with no
`flutter_test` binding. The package still needs a Flutter SDK for its dependencies.
`OverlayClock` supplies both `now()` and `createTimer`; injecting only a date
callback is no longer supported. Fake timers run on `advance`; drain Future
continuations separately when checking backend completion.

```dart
import 'dart:async';
import 'package:layerman/layerman.dart';
import 'package:layerman/testing.dart';
import 'package:test/test.dart';

void main() {
  test('injected clock controls display duration', () async {
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

In debug, every outermost operation batch calls `debugCheckInvariants()`
automatically. It validates container identity, phases, ordering, timers
and disposal. Tests can call it explicitly (including in release); violations
throw `StateError`. These checks and the randomized tests lower the risk of
refactoring, but they do not replace an explicit state-machine refactor.

## Testing

```bash
flutter test                                                   # unit (widget) tests
cd example && flutter test integration_test/orchestration_test.dart -d <serial>        # real-device orchestration
```

The unit suite uses `WidgetTester` to cover serial queueing, close-advances,
priority, `Future` results, `replace` / `affix` / `overlap`, conditions, cooldown
(incl. auto-wake), `resolve`, `beforeClose`, pause/resume, `update` / `clearWhere`,
the `present:` adapter and phase transitions. The `example/` app is a full
real-device demo that runs GetX, bot_toast and native `showDialog` through
the manager. Android phone validation was done on a Huawei STG-AL00 / Android 12.
Windows desktop runs take window focus; don't run them unattended.

## License

MIT. See [LICENSE](LICENSE).
