import 'package:flutter/material.dart';

/// 中文内容的系统字体回退列表；不需要打包字体资源。
const demoFontFallback = ['Microsoft YaHei'];

/// 演示应用调色板；Canvas 配色与 Material 主题共用同一组颜色。
abstract final class DemoPalette {
  /// 官方演示同源的主蓝色。
  static const blue = Color(0xFF617DF2);

  /// 保证浅色按钮文字对比度的深蓝色。
  static const primary = Color(0xFF4059C7);

  /// 深色墨蓝，用于浅底奖品文字。
  static const ink = Color(0xFF25345B);

  /// 薰衣草色扇区和格子。
  static const lavender = Color(0xFFE9E8FE);

  /// 蓝紫色交替扇区。
  static const periwinkle = Color(0xFFB8C5F2);

  /// 暖色点缀与选中高亮。
  static const gold = Color(0xFFFFD68B);

  /// 暖白色奖品和机器窗口。
  static const cream = Color(0xFFFFFBF2);

  /// 珊瑚色奖品。
  static const coral = Color(0xFFE9747C);

  /// 薄荷色奖品。
  static const mint = Color(0xFF91CEBD);

  /// 深色页面底色。
  static const night = Color(0xFF141A2B);

  /// 深色卡片底色。
  static const nightCard = Color(0xFF202A42);
}

/// 页面统一间距与圆角，适合手机和窄桌面窗口。
abstract final class DemoSpace {
  /// 最小装饰间距。
  static const double xs = 4;

  /// 紧凑内容间距。
  static const double sm = 8;

  /// 控件间距。
  static const double md = 12;

  /// 卡片内边距。
  static const double lg = 16;

  /// 页面和分组间距。
  static const double xl = 24;

  /// 大标题上方留白。
  static const double xxl = 32;

  /// 普通控件圆角。
  static const double radius = 18;

  /// 玩法舞台圆角。
  static const double stageRadius = 28;

  /// 桌面端最大内容宽度。
  static const double maxWidth = 720;
}

/// 创建跟随 [brightness] 的完整示例主题；例如 `demoTheme(Brightness.dark)`。
ThemeData demoTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: DemoPalette.blue,
    brightness: brightness,
  ).copyWith(
    primary: dark ? DemoPalette.periwinkle : DemoPalette.primary,
    surface: dark ? DemoPalette.nightCard : Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    fontFamilyFallback: demoFontFallback,
    scaffoldBackgroundColor: dark ? DemoPalette.night : const Color(0xFFF5F5FC),
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: base.scaffoldBackgroundColor,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DemoSpace.radius)),
        textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontFamilyFallback: demoFontFallback,
            fontSize: 15,
            fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DemoSpace.radius)),
        side: BorderSide(color: scheme.outline.withAlpha(100)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withAlpha(90)),
  );
}

/// 统一的有边框卡片；[child] 为内容，[padding] 可覆盖默认内边距。
class DemoCard extends StatelessWidget {
  /// 创建卡片；例如 `DemoCard(child: Text('好运'))`。
  const DemoCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(DemoSpace.lg)});

  /// 卡片内容。
  final Widget child;

  /// 内容与边框之间的留白。
  final EdgeInsetsGeometry padding;

  /// 随主题构建表面、细边框和柔和阴影。
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(DemoSpace.radius),
        border: Border.all(color: scheme.outlineVariant.withAlpha(70)),
        boxShadow: [
          BoxShadow(
              color: DemoPalette.ink.withAlpha(8),
              blurRadius: 20,
              offset: const Offset(0, 6))
        ],
      ),
      child: child,
    );
  }
}

/// 按 [title] 返回玩法说明与图标；未知标题返回通用介绍。
///
/// 例如 `demoDescription('转盘')` 返回转盘说明与指南针图标。
(String, IconData) demoDescription(String title) => switch (title) {
      '转盘' => ('转动一圈，让好礼落在指针下', Icons.explore_rounded),
      '九宫格' => ('沿着八格好礼，点亮你的幸运', Icons.grid_view_rounded),
      '老虎机' => ('三列滚动，定格这一刻的惊喜', Icons.view_week_rounded),
      '拉霸机' => ('轻拉手柄，感受逐轮停下的期待', Icons.sports_esports_rounded),
      '扭蛋机' => ('转动旋钮，打开一颗小小惊喜', Icons.bubble_chart_rounded),
      '数字转盘' => ('小球与圆盘，追逐你的幸运数字', Icons.looks_6_rounded),
      '抽签' => ('轻摇签筒，收获一句美好祝愿', Icons.auto_awesome_rounded),
      '大乐透' => ('七颗彩球，依次揭晓幸运号码', Icons.confirmation_number_rounded),
      'compat 迁移' => ('熟悉的配置，焕然一新的体验', Icons.swap_horiz_rounded),
      'Widget 叠加层' => ('让奖品拥有自己的灵动时刻', Icons.layers_rounded),
      '官方示例对照' => ('官方基础与完整示例 1:1 复刻，逐项对照', Icons.compare_rounded),
      _ => ('发现更多玩法与使用方式', Icons.code_rounded),
    };

/// 在 [context] 所属导航器展示 [result]，返回的 Future 在结果卡关闭后完成。
///
/// 例如 `await showDemoResult(context, '奖品：1')`；调用方提供已结算的结果文字。
Future<void> showDemoResult(BuildContext context, String result) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(DemoSpace.stageRadius))),
      builder: (context) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(DemoSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.celebration_rounded,
              size: 48, color: DemoPalette.blue),
          const SizedBox(height: DemoSpace.lg),
          Text('好运已揭晓', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: DemoSpace.md),
          Text(result, textAlign: TextAlign.center),
          const SizedBox(height: DemoSpace.xl),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('收下好运')),
        ]),
      )),
    );
