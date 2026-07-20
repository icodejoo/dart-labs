import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'demo_shell.dart';
import 'manager.dart';

// Re-export manager/helper symbols so integration tests can use `app.om` and
// `app.openCard(...)` via
// `import 'package:layerman_example/main.dart' as app; app.om.resumeAll()`.
export 'manager.dart' show om, restartApp, createFreshManager;
export 'helpers.dart' show openCard;

final GlobalKey<_AppRootState> _appRootKey = GlobalKey<_AppRootState>();

void main() {
  om.setContext({'route': '/home'});
  runApp(AppRoot(key: _appRootKey));
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    registerRestartCallback(_doRestart);
  }

  void _doRestart() {
    // `dispose()` synchronously pops any still-open dialog routes on the
    // CURRENT navigator (via each entry's `present`-backend dismiss) --
    // Navigator route removal schedules its own deferred focus-update
    // microtask. Doing that INSIDE the same `setState` that also swaps
    // DemoShell's key (below) raced that microtask against the very same
    // frame tearing down the old subtree, throwing "FocusManager used after
    // being disposed". Running it as a plain statement BEFORE `setState`
    // lets that microtask settle against the still-fully-mounted old tree,
    // and only then does `setState` remount with the fresh generation.
    om.dispose();
    final fresh = createFreshManager();
    fresh.setContext({'route': '/home'});
    setState(() {
      om = fresh;
      _gen++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final botToastBuilder = BotToastInit();
    return GetMaterialApp(
      title: 'layerman demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      // LayermanNavigatorObserver feeds every push/pop into om.setContext
      // automatically. BotToastNavigatorObserver maintains bot_toast's layer.
      navigatorObservers: [
        BotToastNavigatorObserver(),
        LayermanNavigatorObserver(om),
      ],
      // Layer order (top → bottom):
      //   bot_toast  >  ShadSonner toasts  >  routes
      //
      // The manager is headless now — it renders nothing itself, so there is
      // no scope/overlay layer to mount for it. `om` (see manager.dart) is a
      // plain object; every demo page presents through a real backend
      // (showDialog/Get.dialog/bot_toast/ShadSonner) that the manager only
      // sequences.
      //
      // ShadTheme must be an ancestor of all shadcn/ui widgets (ShadButton,
      // ShadDialog, ShadSheet) rendered inside present callbacks and dialogs.
      // ShadSonner is keyed so present-callbacks can reach it without context.
      builder: (context, child) => botToastBuilder(
        context,
        ShadTheme(
          data: ShadThemeData(colorScheme: const ShadSlateColorScheme.light()),
          child: ShadSonner(
            key: shadSonnerKey,
            child: child!,
          ),
        ),
      ),
      // Use initialRoute + routes so the home page has name '/home'
      // (not '/' which is Flutter's implicit defaultRouteName for home:).
      initialRoute: '/home',
      routes: {'/home': (_) => DemoShell(key: ValueKey(_gen))},
    );
  }
}
