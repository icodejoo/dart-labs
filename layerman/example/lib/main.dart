import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'demo_shell.dart';
import 'manager.dart';

// Re-export manager symbols so integration tests can use `app.om` via
// `import 'package:layerman_example/main.dart' as app; app.om.resumeAll()`.
export 'manager.dart' show om, restartApp, createFreshManager;

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
    setState(() {
      om.dispose();
      om = createFreshManager();
      om.setContext({'route': '/home'});
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
      // OverlayNavigatorObserver feeds every push/pop into om.setContext
      // automatically. BotToastNavigatorObserver maintains bot_toast's layer.
      navigatorObservers: [
        BotToastNavigatorObserver(),
        OverlayNavigatorObserver(om),
      ],
      // Layer order (top → bottom):
      //   bot_toast  >  OverlayManagerScope  >  Navigator / routes
      builder: (context, child) => botToastBuilder(
        context,
        OverlayManagerScope(manager: om, child: child!),
      ),
      // Use initialRoute + routes so the home page has name '/home'
      // (not '/' which is Flutter's implicit defaultRouteName for home:).
      initialRoute: '/home',
      routes: {'/home': (_) => DemoShell(key: ValueKey(_gen))},
    );
  }
}
