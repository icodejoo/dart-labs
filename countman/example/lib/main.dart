import 'package:flutter/material.dart';
import 'counter_page.dart';
import 'countdown_page.dart';
import 'elapsed_page.dart';

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
            subtitle: 'CounterText · CounterBuilder · CounterOdometer\n'
                'CounterRing · CounterBar · AnimatedCounter',
            route: '/counter',
            color: const Color(0xFF5C6BC0),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.hourglass_empty_rounded,
            title: 'Countdown',
            subtitle: 'CountdownBuilder · CountdownText · CountdownRing\n'
                'CountdownBar · CountdownCard',
            route: '/countdown',
            color: const Color(0xFF26A69A),
          ),
          const SizedBox(height: 12),
          _PluginCard(
            icon: Icons.access_time_rounded,
            title: 'Elapsed',
            subtitle: 'ElapsedText · ElapsedProvider',
            route: '/elapsed',
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
