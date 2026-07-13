import 'package:flutter/material.dart';
import 'package:layerman/layerman.dart';
import '../helpers.dart';
import '../manager.dart';

class LifecyclePage extends StatefulWidget {
  const LifecyclePage({super.key});

  @override
  State<LifecyclePage> createState() => _LifecyclePageState();
}

class _LifecyclePageState extends State<LifecyclePage> {
  bool _allowClose = false;
  int _updN = 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Lifecycle',
              'data carries the initial payload, resolve fetches it async before '
              'the overlay appears, update() merges a patch live, beforeClose guards '
              'close attempts. OverlayHandle exposes id, data, and phase.'),
          pageSection(
            context,
            'data — initial payload on the handle',
            [
              demoButton('btn-data-map', 'data: {label: "hello"}', () {
                om.open(
                    id: 'dat',
                    data: const {'label': 'hello'},
                    builder: (c, h) {
                      final d = h.data as Map;
                      return buildCard('DATA: ${d["label"]}', h,
                          hint: 'data is accessible in builder via handle.data');
                    });
              }),
              demoButton('btn-data-str', 'data: "a string"', () {
                om.open(
                    id: 'dat-str',
                    data: 'a string payload',
                    builder: (c, h) =>
                        buildCard('DATA: ${h.data}', h, hint: 'data can be any Object?'));
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
                    builder: (c, h) =>
                        buildCard('RESOLVED v=${(h.data as Map)["v"]}', h,
                            hint: 'resolve() called when slot granted. '
                                'null result skips overlay (no cooldown counted).'));
              }),
              demoButton('btn-resolve-null', 'resolve: returns null (skipped)', () {
                om.open(
                    id: 'rsv-null',
                    resolve: () async => null,
                    builder: (c, h) => buildCard('NEVER SHOWS', h,
                        hint: 'resolve returning null skips activation'));
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
                om.open(
                    id: 'guard',
                    data: const {'locked': true},
                    beforeClose: () => _allowClose,
                    builder: (c, h) => buildCard(
                          (h.data as Map)['locked'] == true ? 'GUARD 🔒' : 'GUARD 🔓',
                          h,
                          hint: 'close() is vetoed while locked.\nTap "unlock" below first.',
                        ));
              }),
              demoButton('btn-unlock', 'unlock guard', () {
                _allowClose = true;
                om.update('guard', {'locked': false});
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
                    builder: (c, h) {
                      final d = h.data as Map;
                      return buildCard('n = ${d["n"]}', h,
                          hint: 'handle.data updates live via update(id, patch)');
                    });
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
                'Map patches are shallow-merged into the existing data Map. '
                'Non-Map data is replaced outright. '
                'The builder re-runs automatically via markNeedsBuild().',
          ),
          pageSection(
            context,
            'OverlayHandle — id, data, phase',
            [
              demoButton('btn-handle-inspect', 'open handle-inspect overlay', () {
                om.open(
                    id: 'hinsp',
                    data: {'info': 'see the handle'},
                    builder: (c, h) {
                      return ValueListenableBuilder<OverlayPhase>(
                        valueListenable: h.phaseListenable,
                        builder: (context, phase, _) => buildCard(
                          'id: ${h.id}',
                          h,
                          hint: 'phase: $phase\ndata: ${h.data}',
                        ),
                      );
                    });
              }),
            ],
            subtitle:
                'handle.id is the resolved id string. '
                'handle.data is the current (possibly patched) payload. '
                'handle.phaseListenable notifies on phase transitions: '
                'queued → open → closing.',
          ),
          pageSection(
            context,
            'open<T>() result — Future<T?>',
            [
              demoButton('btn-result', 'open overlay that returns "hello"', () async {
                final messenger = ScaffoldMessenger.of(context);
                final result = await om.open<String>(
                    id: 'res',
                    builder: (c, h) => Center(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('What should I return?'),
                                  const SizedBox(height: 8),
                                  FilledButton(
                                    onPressed: () => h.close('hello'),
                                    child: const Text('return "hello"'),
                                  ),
                                  TextButton(
                                    onPressed: () => h.close(),
                                    child: const Text('return null'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ));
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
