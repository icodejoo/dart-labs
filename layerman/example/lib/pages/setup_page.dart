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
              'The manager is headless — it never touches the widget tree, so '
              'there is no scope/overlay layer to mount. Wiring up '
              'LayermanNavigatorObserver, a UI backend for present(), and custom '
              'cooldown storage is all app.main() needs. Also covers manager '
              'properties and the in-app restart pattern.'),
          pageSection(
            context,
            'No scope to mount — the manager renders nothing',
            [],
            subtitle:
                'There used to be an OverlayManagerScope that attached the '
                'manager to an OverlayState. That is gone: the manager owns no '
                'Overlay and touches no widget tree. Every demo in this app '
                'shows its overlay through a real UI backend — showDialog, '
                'Get.dialog, a GetX snackbar, bot_toast, ShadSonner — wired '
                'through present(). See helpers.dart\'s presentCard/presentRouteDialog/'
                'presentShadDialog/presentShadToast for the adapters this app uses.\n\n'
                'Setup:\n'
                '  final om = Layerman(gap: Duration(milliseconds: 300));\n'
                '  // no scope, no attach() — just call om.open(present: ...)',
          ),
          pageSection(
            context,
            'LayermanNavigatorObserver — auto route tracking',
            [
              demoButton('btn-current-route', 'om.currentRoute', () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('om.currentRoute = ${om.currentRoute}')),
                );
              }),
            ],
            subtitle:
                'LayermanNavigatorObserver(om) wired into navigatorObservers: [...] '
                'calls om.setContext({"route": routeName}) on every route change. '
                'Overrides didChangeTop — the only Flutter hook that always reports '
                'the true topmost route, including go_router\'s declarative pages.\n\n'
                'Setup:\n'
                '  navigatorObservers: [LayermanNavigatorObserver(om)]',
          ),
          pageSection(
            context,
            'Manager properties',
            [
              demoButton('btn-props', 'print all properties', () {
                final msg =
                    'isPaused: ${om.isPaused}\n'
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
                openCard('mem-cd',
                    text: 'MEM STORAGE',
                    cooldown: const OverlayCooldown(session: 2),
                    hint: 'Uses MemoryCooldownStorage (default). '
                        'Counts reset on restart.');
              }),
            ],
            subtitle:
                'Layerman defaults to MemoryCooldownStorage — no persistence. '
                'For cross-session persistence:\n'
                '  Layerman(cooldownStorage: MySharedPrefsStorage())\n\n'
                'OverlayCooldownStorage interface:\n'
                '  Future<String?> read(String key)\n'
                '  Future<void> write(String key, String value)',
          ),
          pageSection(
            context,
            'storageKey — namespace cooldown storage',
            [],
            subtitle:
                'Layerman(storageKey: "my_app:cooldown") namespaces the storage. '
                'Useful when multiple OverlayManagers share one storage backend.',
          ),
          pageSection(
            context,
            'pauseOnRoutes — constructor param',
            [],
            subtitle:
                'Layerman(pauseOnRoutes: ["/zone", RegExp(r"^/auth")]) '
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
                'is init-once and silently no-ops.',
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
                'LayermanNavigatorObserver checks isDisposed before setContext() '
                'to avoid ChangeNotifier-after-dispose crashes.',
          ),
        ],
      ),
    );
  }
}
