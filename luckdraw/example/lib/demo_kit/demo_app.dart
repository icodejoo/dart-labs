import 'package:flutter/material.dart';
import 'i18n.dart';

/// 在 MaterialApp 之前接收浏览器历史，避免被普通 Navigator 当作命名路由处理。
class DemoRouteObserver extends ChangeNotifier with WidgetsBindingObserver {
  /// 最近一次来自浏览器的路由；初始路由由骨架读取 Uri.base。
  Uri? uri;

  /// 接收浏览器前进或后退，并将路由交给骨架。
  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    uri = routeInformation.uri;
    notifyListeners();
    return true;
  }
}

/// 向骨架传递浏览器历史变更。
class DemoRouteScope extends InheritedNotifier<DemoRouteObserver> {
  /// 创建浏览器路由作用域。
  const DemoRouteScope({
    super.key,
    required DemoRouteObserver observer,
    required super.child,
  }) : super(notifier: observer);

  /// 读取历史事件，建立重建依赖。
  static Uri? routeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DemoRouteScope>()
      ?.notifier
      ?.uri;

  /// 同步应用内部导航，避免语言或主题重建读取过期的历史路由。
  static void record(BuildContext context, Uri uri) {
    context.getInheritedWidgetOfExactType<DemoRouteScope>()?.notifier?.uri =
        uri;
  }
}

/// 跨项目共用的尺寸与字体约定。
abstract final class DemoTokens {
  /// 卡片和网格的紧凑间距。
  static const double gap = 12;

  /// 紧凑控件之间的间距。
  static const double smallGap = 8;

  /// 标题和说明之间的间距。
  static const double tinyGap = 4;

  /// 演示卡片的最大宽度。
  static const double cardMaxWidth = 420;

  /// 卡片标题和摘要的最小区域高度。
  static const double cardHeaderHeight = 64;

  /// 手机与平板的内容宽度分界。
  static const double tabletBreakpoint = 600;

  /// 平板与桌面的内容宽度分界。
  static const double desktopBreakpoint = 1000;

  /// 超宽网格的内容宽度分界。
  static const double wideBreakpoint = 1500;

  /// 代码与辅助说明的字号。
  static const double captionSize = 13;

  /// 页面水平内边距。
  static const double padding = 16;

  /// 分区之间的留白。
  static const double sectionGap = 24;

  /// 圆角半径。
  static const double radius = 16;

  /// 所有交互按钮的最小边长。
  static const double controlSize = 44;

  /// 主内容最大宽度。
  static const double maxWidth = 1200;

  /// 导航布局切换阈值。
  static const double sidebarBreakpoint = 900;

  /// 拉丁与中文的系统字体回退列表。
  static const fonts = [
    'Segoe UI',
    'Noto Sans SC',
    'Microsoft YaHei',
    'PingFang SC',
    'sans-serif',
  ];
}

/// 演示应用的主题控制器作用域。
class DemoAppearance extends InheritedWidget {
  /// 创建外观控制作用域。
  const DemoAppearance({
    super.key,
    required this.mode,
    required this.toggle,
    required super.child,
  });

  /// 当前主题模式。
  final ThemeMode mode;

  /// 切换明暗主题的回调。
  final VoidCallback toggle;

  /// 获取外观控制器。
  static DemoAppearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoAppearance>()!;

  /// 判断主题状态是否变化。
  @override
  bool updateShouldNotify(DemoAppearance oldWidget) => oldWidget.mode != mode;
}

/// 自包含的 Material 3 演示应用，不依赖任何具体项目。
class DemoApp extends StatefulWidget {
  /// 创建应用；传入项目标题、种子色和页面骨架。
  const DemoApp({
    super.key,
    required this.title,
    required this.seedColor,
    required this.home,
    this.locale,
  });

  /// 系统任务栏与网页标题。
  final String title;

  /// 项目主题种子色。
  final Color seedColor;

  /// 页面骨架。
  final Widget home;

  /// 可选的外部语言状态，由调用者管理生命周期。
  final DemoLocale? locale;

  /// 创建主题状态。
  @override
  State<DemoApp> createState() => _DemoAppState();
}

/// 管理应用语言与手动主题覆盖。
class _DemoAppState extends State<DemoApp> {
  /// 在内部 Navigator 之前注册的路由观察器。
  final DemoRouteObserver _routes = DemoRouteObserver();

  /// 提前注册路由观察器以接收浏览器历史。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_routes);
  }

  /// 本次应用使用的语言状态。
  late final DemoLocale _locale = widget.locale ?? DemoLocale();

  /// 默认跟随系统的主题模式。
  ThemeMode _mode = ThemeMode.system;

  /// 根据当前实际亮度切换主题。
  void _toggle() => setState(() {
        final dark = _mode == ThemeMode.dark ||
            (_mode == ThemeMode.system &&
                WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                    Brightness.dark);
        _mode = dark ? ThemeMode.light : ThemeMode.dark;
      });

  /// 构造统一字体与尺寸的主题。
  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: widget.seedColor,
          brightness: brightness,
        ),
        fontFamilyFallback: DemoTokens.fonts,
        visualDensity: VisualDensity.standard,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize:
                const Size(DemoTokens.controlSize, DemoTokens.controlSize),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize:
                const Size(DemoTokens.controlSize, DemoTokens.controlSize),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize:
                const Size(DemoTokens.controlSize, DemoTokens.controlSize),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize:
                const Size(DemoTokens.controlSize, DemoTokens.controlSize),
          ),
        ),
        textTheme: const TextTheme(
          bodySmall: TextStyle(fontSize: DemoTokens.captionSize),
          bodyMedium: TextStyle(fontSize: 14),
        ),
      );

  /// 释放内部创建的语言状态。
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_routes);
    _routes.dispose();
    if (widget.locale == null) _locale.dispose();
    super.dispose();
  }

  /// 构建会随语言与主题变化更新的应用。
  @override
  Widget build(BuildContext context) => DemoRouteScope(
        observer: _routes,
        child: DemoLocaleScope(
          locale: _locale,
          child: ListenableBuilder(
            listenable: _locale,
            builder: (context, _) => DemoAppearance(
              mode: _mode,
              toggle: _toggle,
              child: MaterialApp(
                initialRoute: '/',
                title: widget.title,
                debugShowCheckedModeBanner: false,
                theme: _theme(Brightness.light),
                darkTheme: _theme(Brightness.dark),
                themeMode: _mode,
                home: widget.home,
              ),
            ),
          ),
        ),
      );
}
