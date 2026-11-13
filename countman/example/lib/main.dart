import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'advanced_page.dart';
import 'benchmark_demo_page.dart';
import 'digit_test_page.dart';
import 'perf_page.dart';
import 'stress_page.dart';
import 'card_demo_page.dart';
import 'counter_page.dart';
import 'countdown_page.dart';
import 'elapsed_page.dart';
import 'provider_page.dart';
import 'demo_kit/demo_kit.dart';
import 'bench_entry_stub.dart' if (dart.library.io) 'bench_entry_native.dart';

/// 兼容现有桌面基准脚本传入的路由。
const initialDemoRoute = String.fromEnvironment(
  'INITIAL_ROUTE',
  defaultValue: '/',
);

/// 原生开发入口默认关闭，旧脚本路由仍可显式启用。
const benchEnabled =
    bool.fromEnvironment('COUNTMAN_BENCH') || initialDemoRoute == '/benchmark';

/// 压测导航分组英文标题。
const _benchmarksEn = 'Benchmarks';

/// 压测导航分组中文标题。
const _benchmarksZh = '压测';

/// 启动线上演示或显式启用的原生基准入口。
void main() => runApp(
  !kIsWeb && benchEnabled
      ? buildBenchApp(initialDemoRoute)
      : const CountmanDemoApp(),
);

/// 基于通用 demo_kit 的 countman 当前版本演示。
class CountmanDemoApp extends StatelessWidget {
  /// 创建应用，可注入初始 hash 和语言以便验证。
  const CountmanDemoApp({super.key, this.initialFragment, this.locale});

  /// 可选初始页面 hash。
  final String? initialFragment;

  /// 可选外部管理的语言状态。
  final DemoLocale? locale;

  /// 构建功能示例、压测页面与统一骨架。
  @override
  Widget build(BuildContext context) => DemoApp(
    title: 'countman',
    seedColor: const Color(0xFF4263EB),
    locale: locale,
    home: DemoShell(
      project: 'countman',
      version: '0.3.3',
      pubUrl: 'https://pub.dev/packages/countman',
      githubUrl: 'https://github.com/icodejoo/dart-labs/tree/main/countman',
      readmeUrl:
          'https://github.com/icodejoo/dart-labs/blob/main/countman/README.md',
      initialFragment: initialFragment,
      destinations: [
        DemoDestination(
          id: 'counter',
          en: 'Counter',
          zh: '计数器',
          icon: Icons.numbers_rounded,
          builder: (_) => const CounterPage(),
        ),
        DemoDestination(
          id: 'countdown',
          en: 'Countdown',
          zh: '倒计时',
          icon: Icons.hourglass_empty_rounded,
          builder: (_) => const CountdownPage(),
        ),
        DemoDestination(
          id: 'elapsed',
          en: 'Elapsed',
          zh: '正计时',
          icon: Icons.timer_outlined,
          builder: (_) => const ElapsedPage(),
        ),
        DemoDestination(
          id: 'renderers',
          en: 'Card & dial',
          zh: '卡片与表盘',
          icon: Icons.style_outlined,
          builder: (_) => const CardDemoPage(),
        ),
        DemoDestination(
          id: 'advanced',
          en: 'Advanced',
          zh: '进阶能力',
          icon: Icons.tune_rounded,
          sectionEn: 'Under the hood',
          sectionZh: '深入了解',
          builder: (_) => const AdvancedPage(),
        ),
        DemoDestination(
          id: 'providers',
          en: 'Providers & theme',
          zh: '作用域与主题',
          icon: Icons.layers_outlined,
          sectionEn: 'Under the hood',
          sectionZh: '深入了解',
          builder: (_) => const ProviderPage(),
        ),
        DemoDestination(
          id: 'stress',
          en: 'Stress test',
          zh: '并发压测',
          icon: Icons.speed_rounded,
          sectionEn: _benchmarksEn,
          sectionZh: _benchmarksZh,
          builder: (_) => const StressPage(),
        ),
        DemoDestination(
          id: 'perf',
          en: 'Performance',
          zh: '性能对照',
          icon: Icons.monitor_heart_outlined,
          sectionEn: _benchmarksEn,
          sectionZh: _benchmarksZh,
          builder: (_) => const PerfPage(),
        ),
        DemoDestination(
          id: 'digit-test',
          en: 'Digit debug',
          zh: '数字诊断',
          icon: Icons.bug_report_outlined,
          sectionEn: _benchmarksEn,
          sectionZh: _benchmarksZh,
          builder: (_) => const DigitTestPage(),
        ),
        DemoDestination(
          id: 'benchmark',
          en: 'Native benchmark',
          zh: '原生基准',
          icon: Icons.desktop_windows_outlined,
          sectionEn: _benchmarksEn,
          sectionZh: _benchmarksZh,
          builder: (_) => const BenchmarkDemoPage(),
        ),
      ],
    ),
  );
}
