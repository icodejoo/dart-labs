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

  // 关闭守卫使用本地状态；卡片数据由管理器的实时通道提供。
  final ValueNotifier<bool> _guardLocked = ValueNotifier<bool>(true);
  int _updN = 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(
            context,
            'Lifecycle',
            'data carries the initial payload (read via PresentContext.data '
                'when present() is invoked), resolve fetches it async before the '
                'overlay appears, update() merges a patch and notifies listeners, '
                'beforeClose guards close attempts.',
          ),
          pageSection(context, 'data — initial payload via PresentContext', [
            demoButton('btn-data-map', 'data: {label: "hello"}', () {
              om.open(
                id: 'dat',
                data: const {'label': 'hello'},
                present: (ctx) => presentCard(
                  ctx,
                  (c, close) => buildCard(
                    'DATA: ${(ctx.data as Map)["label"]}',
                    close,
                    hint: 'ctx.data is the payload at present() time',
                  ),
                ),
              );
            }),
            demoButton('btn-data-str', 'data: "a string"', () {
              om.open(
                id: 'dat-str',
                data: 'a string payload',
                present: (ctx) => presentCard(
                  ctx,
                  (c, close) => buildCard(
                    'DATA: ${ctx.data}',
                    close,
                    hint: 'data can be any Object?',
                  ),
                ),
              );
            }),
          ]),
          pageSection(
            context,
            'resolve — async data loading before activation',
            [
              demoButton(
                'btn-resolve',
                'resolve: fetch {v: 42} after 300ms',
                () {
                  om.open(
                    id: 'rsv',
                    resolve: () async {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 300),
                      );
                      return const {'v': 42};
                    },
                    present: (ctx) => presentCard(
                      ctx,
                      (c, close) => buildCard(
                        'RESOLVED v=${(ctx.data as Map)["v"]}',
                        close,
                        hint: 'resolve() called when slot granted. '
                            'null result skips overlay (no cooldown counted).',
                      ),
                    ),
                  );
                },
              ),
              demoButton(
                'btn-resolve-null',
                'resolve: returns null (skipped)',
                () {
                  om.open(
                    id: 'rsv-null',
                    resolve: () async => null,
                    present: (ctx) => presentCard(
                      ctx,
                      (c, close) => buildCard(
                        'NEVER SHOWS',
                        close,
                        hint: 'resolve returning null skips activation',
                      ),
                    ),
                  );
                },
              ),
            ],
            subtitle: 'resolve is committed once the slot is granted — '
                'ordinary arrivals wait; OverlayMode.replace can preempt a resolving entry.',
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
                    // ctx.close 绑定条目身份并经过 beforeClose，避免后端直接关闭绕过守卫。
                    (close) => ValueListenableBuilder<bool>(
                      valueListenable: _guardLocked,
                      builder: (context, locked, _) => buildCard(
                        locked ? 'GUARD 🔒' : 'GUARD 🔓',
                        ([Object? r]) => ctx.close(r),
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
                _updN = 0;
                om.open(
                  id: 'upd',
                  data: const {'n': 0},
                  // presentEntry (non-modal), not presentCard -- btn-update/
                  // btn-upd-map below live on this SAME page, and a modal
                  // showDialog barrier would block them from ever being
                  // reachable while the card is showing.
                  present: (ctx) => presentEntry(
                    (close) => ValueListenableBuilder<Object?>(
                      // 直接监听管理器数据，update 未写入时卡片不会变化。
                      valueListenable: ctx.dataListenable,
                      builder: (context, data, _) => buildCard(
                        'n = ${(data as Map)['n']}',
                        close,
                        hint: 'ctx.dataListenable reflects update(id, patch)',
                      ),
                    ),
                  ),
                );
              }),
              demoButton('btn-update', 'update n++', () {
                _updN++;
                om.update('upd', {'n': _updN});
              }),
              demoButton('btn-upd-map', 'update with full Map merge', () {
                om.update('upd', {'n': _updN, 'extra': 'merged!'});
              }),
            ],
            subtitle:
                'update(id, patch) shallow-merges Map patches into the entry\'s '
                'data. Since 0.3.0, ctx.dataListenable provides live values; '
                'ValueListenableBuilder rebuilds this card from that channel.',
          ),
          pageSection(
            context,
            'PresentContext — id, slot, data snapshot',
            [
              demoButton(
                'btn-handle-inspect',
                'open handle-inspect overlay',
                () {
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
                },
              ),
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
              demoButton(
                'btn-result',
                'open overlay that returns "hello"',
                () async {
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
                },
              ),
            ],
            subtitle: 'om.open<T>() returns Future<T?>. '
                'close(result) completes the future; close() with no arg → null.',
          ),
        ],
      ),
    );
  }
}
