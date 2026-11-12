import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_shell.dart';
import 'manager.dart';

/// 启动当前包的双语演示。
void main() => runApp(const AppRoot());

/// 为统一骨架装配已有的 GetX、bot_toast 和 shadcn 后端。
class AppRoot extends StatelessWidget {
  /// 创建应用，可注入语言及页面供测试使用。
  const AppRoot({super.key, this.locale, this.initialFragment});

  /// 外部管理的语言状态。
  final DemoLocale? locale;

  /// 初始页面的 hash。
  final String? initialFragment;

  /// 构建唯一的根导航器及主题响应式后端。
  @override
  Widget build(BuildContext context) => DemoApp(
    title: demoProject,
    seedColor: const Color(0xFF4263EB),
    locale: locale,
    home: LayermanDemoShell(initialFragment: initialFragment),
    appBuilder: (light, dark, mode, home) {
      final toastBuilder = BotToastInit();
      return GetMaterialApp(
        title: demoProject,
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: mode,
        navigatorObservers: [BotToastNavigatorObserver()],
        builder: (context, child) => toastBuilder(
          context,
          ShadTheme(
            data: ShadThemeData(
              colorScheme: Theme.of(context).brightness == Brightness.dark
                  ? const ShadSlateColorScheme.dark()
                  : const ShadSlateColorScheme.light(),
            ),
            child: ShadSonner(key: shadSonnerKey, child: child!),
          ),
        ),
        home: home,
      );
    },
  );
}
