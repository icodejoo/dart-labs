import 'package:flutter/material.dart';
import 'counter_page.dart';
import 'countdown_page.dart';
import 'elapsed_page.dart';
import 'provider_page.dart';
import 'card_demo_page.dart';
import 'countdown_demo_page.dart';
import 'perf_page.dart';
import 'benchmark_page.dart';
import 'digit_test_page.dart';

void main() {
  runApp(const CountmanDemoApp());
}

class CountmanDemoApp extends StatelessWidget {
  const CountmanDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Countman Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C6BC0)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C6BC0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        '/counter': (_) => const CounterPage(),
        '/countdown': (_) => const CountdownPage(),
        '/elapsed': (_) => const ElapsedPage(),
        '/providers': (_) => const ProviderPage(),
        '/card': (_) => const CardDemoPage(),
        '/countdown-demo': (_) => const CountdownDemoPage(),
        '/perf': (_) => const PerfPage(),
        '/benchmark': (_) => const BenchmarkPage(),
        '/digit-test': (_) => const DigitTestPage(),
      },
    );
  }
}

// ── Home ──────────────────────────────────────────────────────────────────────

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Countman')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PluginCard(
            icon: Icons.timer_outlined,
            title: 'Counter',
            subtitle: 'TextCounter · CounterBuilder · OdometerCounter\n'
                'RingCounter · BarCounter · AnimatedCounter',
            route: '/counter',
            color: const Color(0xFF5C6BC0),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.hourglass_empty_rounded,
            title: 'Countdown',
            subtitle: 'CountdownBuilder · TextCountdown · RingCountdown\n'
                'BarCountdown · CardCountdown',
            route: '/countdown',
            color: const Color(0xFF26A69A),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.access_time_rounded,
            title: 'Elapsed',
            subtitle: 'TextElapsed · ElapsedBuilder · ElapsedProvider',
            route: '/elapsed',
            color: const Color(0xFFEF5350),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text('进阶 / More',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          _PluginCard(
            icon: Icons.account_tree_rounded,
            title: 'Providers',
            subtitle: 'CountmanProvider (聚合三家族) · CardCountdownProvider',
            route: '/providers',
            color: const Color(0xFF7E57C2),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.style_rounded,
            title: 'CardCountdown 效果矩阵',
            subtitle: 'calendar / slide / flip · scale / opacity / perspective',
            route: '/card',
            color: const Color(0xFF26A69A),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.hourglass_bottom_rounded,
            title: 'Countdown 全家速览',
            subtitle: 'to 的四种输入 · formatter · controller · 并发',
            route: '/countdown-demo',
            color: const Color(0xFF26A69A),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.speed_rounded,
            title: '性能压测',
            subtitle: '并发 AnimatedCounter / Odometer, 0→10 亿 / 10s',
            route: '/perf',
            color: const Color(0xFF5C6BC0),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.insights_rounded,
            title: '基准对比',
            subtitle: 'countman vs slide_countdown / stop_watch_timer',
            route: '/benchmark',
            color: const Color(0xFF5C6BC0),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.bug_report_rounded,
            title: '数字调试 (onUpdate)',
            subtitle: 'AnimatedCounter / CounterBuilder 逐帧日志',
            route: '/digit-test',
            color: const Color(0xFFEF5350),
          ),
        ],
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pushNamed(context, route),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurface.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
