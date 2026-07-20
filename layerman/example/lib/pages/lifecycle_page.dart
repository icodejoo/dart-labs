import 'package:flutter/material.dart';
import '../helpers.dart';
import '../manager.dart';

class LifecyclePage extends StatefulWidget {
  const LifecyclePage({super.key});

  @override
  State<LifecyclePage> createState() => _LifecyclePageState();
}

class _LifecyclePageState extends State<LifecyclePage> {
  bool _allowClose = false;

  // Local live-update sources for the "beforeClose" / "update" demo cards.
  // The manager stores `data` only for `resolve()` and the `PresentContext`
  // snapshot handed to `present` when the entry activates — once presented
  // there is no public "read the current data of id" API, since the manager
  // never re-renders anything itself. A backend that needs its card to
  // reflect later `update(id, patch)` calls has to mirror the value in its
  // own notifier, same as any other headless-orchestrator backend would.
  final ValueNotifier<bool> _guardLocked = ValueNotifier<bool>(true);
  final ValueNotifier<int> _updN = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Lifecycle',
              'data carries the initial payload (read via PresentContext.data '
              'when present() is invoked), resolve fetches it async before the '
              'overlay appears, update() merges a patch and notifies listeners, '
              'beforeClose guards close attempts.'),
          pageSection(
            context,
            'data — initial payload via PresentContext',
            [
              demoButton('btn-data-map', 'data: {label: "hello"}', () {
                om.open(
                  id: 'dat',
                  data: const {'label': 'hello'},
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => buildCard(
                        'DATA: ${(ctx.data as Map)["label"]}', close,
                        hint: 'ctx.data is the payload at present() time'),
                  ),
                );
              }),
              demoButton('btn-data-str', 'data: "a string"', () {
                om.open(
                  id: 'dat-str',
                  data: 'a string payload',
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => buildCard('DATA: ${ctx.data}', close,
                        hint: 'data can be any Object?'),
                  ),
                );
              }),
            ],
          ),
          pageSection(
            context,
            'resolve — async data loading before activation',
            [
              demoButton('btn-resolve', 'resolve: fetch {v: 42} after 300ms', () {
                om.open(
                  id: 'rsv',
                  resolve: () async {
                    await Future<void>.delayed(const Duration(milliseconds: 300));
                    return const {'v': 42};
                  },
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => buildCard(
                        'RESOLVED v=${(ctx.data as Map)["v"]}', close,
                        hint: 'resolve() called when slot granted. '
                            'null result skips overlay (no cooldown counted).'),
                  ),
                );
              }),
              demoButton('btn-resolve-null', 'resolve: returns null (skipped)', () {
                om.open(
                  id: 'rsv-null',
                  resolve: () async => null,
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => buildCard('NEVER SHOWS', close,
                        hint: 'resolve returning null skips activation'),
                  ),
                );
              }),
            ],
            subtitle:
                'resolve is committed once the slot is granted — '
                'later arrivals cannot preempt a resolving entry.',
          ),
          pageSection(
            context,
            'beforeClose — close guard',
            [
              demoButton('btn-guard', 'open locked overlay', () {
                _allowClose = false;
                _guardLocked.value = true;
                om.open(
                  id: 'guard',
                  beforeClose: () => _allowClose,
                  // presentEntry (non-modal), not presentCard (a modal
                  // showDialog): the "unlock" button below lives on THIS same
                  // page, behind the card -- a modal barrier would block it
                  // from ever being reachable while the card is showing.
                  present: (ctx) => presentEntry(
                    // beforeClose only guards om.close()/dismiss() -- the raw
                    // `close` callback pops directly (right for every other
                    // demo's organic dismissal), which would bypass the guard
                    // entirely. This card's button must go through
                    // om.close(id) instead so the veto has something to
                    // intercept.
                    (close) => ValueListenableBuilder<bool>(
                      valueListenable: _guardLocked,
                      builder: (context, locked, _) => buildCard(
                        locked ? 'GUARD 🔒' : 'GUARD 🔓',
                        ([Object? r]) => om.close('guard', r),
                        hint: 'close() is vetoed while locked.\n'
                            'Tap "unlock" below first.',
                      ),
                    ),
                  ),
                );
              }),
              demoButton('btn-unlock', 'unlock guard', () {
                _allowClose = true;
                _guardLocked.value = false;
              }),
            ],
            subtitle:
                'beforeClose: () => bool — returning false cancels the close attempt. '
                'Async guards (Future<bool>) are also supported. '
                'clear()/remove() bypass beforeClose by design.',
          ),
          pageSection(
            context,
            'update(id, patch) — live data patch',
            [
              demoButton('btn-upd-show', 'open counter overlay (n=0)', () {
                _updN.value = 0;
                om.open(
                  id: 'upd',
                  data: const {'n': 0},
                  // presentEntry (non-modal), not presentCard -- btn-update/
                  // btn-upd-map below live on this SAME page, and a modal
                  // showDialog barrier would block them from ever being
                  // reachable while the card is showing.
                  present: (ctx) => presentEntry(
                    (close) => ValueListenableBuilder<int>(
                      valueListenable: _updN,
                      builder: (context, n, _) => buildCard('n = $n', close,
                          hint: 'card mirrors update(id, patch) via a local notifier'),
                    ),
                  ),
                );
              }),
              demoButton('btn-update', 'update n++', () {
                _updN.value++;
                om.update('upd', {'n': _updN.value});
              }),
              demoButton('btn-upd-map', 'update with full Map merge', () {
                om.update('upd', {'n': _updN.value, 'extra': 'merged!'});
              }),
            ],
            subtitle:
                'update(id, patch) shallow-merges Map patches into the entry\'s '
                'data and calls notifyListeners() — the manager itself never '
                'rebuilds anything, so this card listens to its own ValueNotifier '
                'in step with each update() call.',
          ),
          pageSection(
            context,
            'PresentContext — id, slot, data snapshot',
            [
              demoButton('btn-handle-inspect', 'open handle-inspect overlay', () {
                om.open(
                  id: 'hinsp',
                  data: const {'info': 'see PresentContext'},
                  present: (ctx) => presentCard(
                    ctx,
                    (c, close) => buildCard(
                      'id: ${ctx.id}',
                      close,
                      hint: 'slot: "${ctx.slot}"\ndata: ${ctx.data}',
                    ),
                  ),
                );
              }),
            ],
            subtitle:
                'ctx.id/ctx.slot/ctx.data are a one-time snapshot handed to present() '
                'when the queue grants the slot — there is no OverlayPhase/handle '
                'anymore; a backend reports its own close via PresentedOverlay.dismissed '
                'and can grace its exit with exitDuration (see the Timing page).',
          ),
          pageSection(
            context,
            'open<T>() result — Future<T?>',
            [
              demoButton('btn-result', 'open overlay that returns "hello"', () async {
                final messenger = ScaffoldMessenger.of(context);
                final result = await om.open<String>(
                  id: 'res',
                  present: (ctx) => presentCard<String>(
                    ctx,
                    (c, close) => Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('What should I return?'),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: () => close('hello'),
                                child: const Text('return "hello"'),
                              ),
                              TextButton(
                                onPressed: () => close(),
                                child: const Text('return null'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('open() returned: $result')),
                  );
                }
              }),
            ],
            subtitle:
                'om.open<T>() returns Future<T?>. '
                'close(result) completes the future; close() with no arg → null.',
          ),
        ],
      ),
    );
  }
}
