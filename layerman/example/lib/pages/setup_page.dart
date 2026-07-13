import 'package:flutter/material.dart';
import 'package:layerman/layerman.dart';
import '../helpers.dart';
import '../manager.dart';

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pageHeader(context, 'Setup & Restart',
              'How to wire up OverlayManagerScope, OverlayNavigatorObserver, '
              'and custom cooldown storage. Also covers manager properties '
              'and the in-app restart pattern.'),
          pageSection(
            context,
            'OverlayManagerScope — attaches the manager to an OverlayState',
            [
              demoButton('btn-isattached', 'check om.isAttached', () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('om.isAttached = ${om.isAttached}')),
                );
              }),
            ],
            subtitle:
                'OverlayManagerScope(manager: om, child: child) wraps the widget tree '
                'and calls om.attach(overlayState) after the first frame. '
                'isAttached is true once an OverlayState is connected. '
                '\n\nSetup:\n'
                '  builder: (ctx, child) => OverlayManagerScope(manager: om, child: child!)',
          ),
          pageSection(
            context,
            'OverlayNavigatorObserver — auto route tracking',
            [
              demoButton('btn-current-route', 'om.currentRoute', () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('om.currentRoute = ${om.currentRoute}')),
                );
              }),
            ],
            subtitle:
                'OverlayNavigatorObserver(om) wired into navigatorObservers: [...] '
                'calls om.setContext({"route": routeName}) on every route change. '
                'Overrides didChangeTop — the only Flutter hook that always reports '
                'the true topmost route, including go_router\'s declarative pages.\n\n'
                'Setup:\n'
                '  navigatorObservers: [OverlayNavigatorObserver(om)]',
          ),
          pageSection(
            context,
            'Manager properties',
            [
              demoButton('btn-props', 'print all properties', () {
                final msg =
                    'isPaused: ${om.isPaused}\n'
                    'isAttached: ${om.isAttached}\n'
                    'isDisposed: ${om.isDisposed}\n'
                    'currentRoute: ${om.currentRoute}\n'
                    'activeIds: ${om.activeIds}\n'
                    'queuedIds: ${om.queuedIds}';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
                );
              }),
            ],
          ),
          pageSection(
            context,
            'MemoryCooldownStorage — default in-memory storage',
            [
              demoButton('btn-mem-storage', 'open with default storage', () {
                om.open(
                    id: 'mem-cd',
                    cooldown: const OverlayCooldown(session: 2),
                    builder: (c, h) => buildCard('MEM STORAGE', h,
                        hint: 'Uses MemoryCooldownStorage (default). '
                            'Counts reset on restart.'));
              }),
            ],
            subtitle:
                'OverlayManager defaults to MemoryCooldownStorage — no persistence. '
                'For cross-session persistence:\n'
                '  OverlayManager(cooldownStorage: MySharedPrefsStorage())\n\n'
                'OverlayCooldownStorage interface:\n'
                '  Future<Map<String,dynamic>> read(String key)\n'
                '  Future<void> write(String key, Map<String,dynamic> data)',
          ),
          pageSection(
            context,
            'storageKey — namespace cooldown storage',
            [],
            subtitle:
                'OverlayManager(storageKey: "my_app:cooldown") namespaces the storage. '
                'Useful when multiple OverlayManagers share one storage backend.',
          ),
          pageSection(
            context,
            'pauseOnRoutes — constructor param',
            [],
            subtitle:
                'OverlayManager(pauseOnRoutes: ["/zone", RegExp(r"^/auth")]) '
                'specifies patterns where the queue auto-freezes. '
                'Accepts String, List<String>, or RegExp — same as the route condition.',
          ),
          pageSection(
            context,
            'In-app restart — dispose + fresh manager',
            [
              demoButton('btn-restart', '⟳ restart app', () {
                restartApp();
              }),
            ],
            subtitle:
                'restartApp() calls setState on AppRoot:\n'
                '  om.dispose()  // clears all overlays\n'
                '  om = createFreshManager()\n'
                '  _gen++  // ValueKey remounts HomePage\n\n'
                'Do NOT call runApp() again — a second GetMaterialApp/BotToastInit '
                'is init-once and silently no-ops. '
                'OverlayManagerScope re-attaches via didUpdateWidget.',
          ),
          pageSection(
            context,
            'dispose() — clean up the manager',
            [
              demoButton('btn-isdisposed', 'om.isDisposed (before dispose)', () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('om.isDisposed = ${om.isDisposed}')),
                );
              }),
            ],
            subtitle:
                'Call om.dispose() when the manager\'s lifetime ends (e.g. restart). '
                'After dispose, isDisposed = true; further open() calls are no-ops. '
                'OverlayNavigatorObserver checks isDisposed before setContext() '
                'to avoid ChangeNotifier-after-dispose crashes.',
          ),
        ],
      ),
    );
  }
}
