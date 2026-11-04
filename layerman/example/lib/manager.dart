import 'package:flutter/widgets.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Layerman om = _fresh();

Layerman _fresh() => Layerman(
      gap: const Duration(milliseconds: 300),
      dismissTimeout: const Duration(seconds: 2),
      resolveTimeout: const Duration(seconds: 2),
      pauseOnRoutes: const [RouteMatcher.exact('/zone')],
    );

Layerman createFreshManager() => _fresh();

/// 当前 manager 绑定的前后台监听器；重启换 manager 时由 AppRoot 重新登记。
///
/// 演示页和集成测试通过它的 `didChangeAppLifecycleState` 模拟前后台切换。
/// 不要用 `WidgetsBinding.handleAppLifecycleStateChanged(paused)` 模拟：
/// 它会把整个应用的出帧关掉，真机上界面会失去响应。
LayermanLifecycle? appLifecycle;

void Function()? _restartCb;
void registerRestartCallback(void Function() cb) => _restartCb = cb;
void restartApp() => _restartCb?.call();

/// GlobalKey for the [ShadSonner] inserted in the builder chain.
/// Allows present-callbacks (which have no BuildContext) to show shadcn/ui
/// toasts without needing [ShadSonner.of(context)].
final GlobalKey<ShadSonnerState> shadSonnerKey = GlobalKey<ShadSonnerState>();
