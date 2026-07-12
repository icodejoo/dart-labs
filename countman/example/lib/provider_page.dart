import 'package:flutter/material.dart';
import 'package:countman/countman.dart';

/// Demonstrates the provider layer: the aggregate [CountmanProvider] that
/// configures all three families at once, and the standalone
/// [CountdownCardProvider] that also shares a glyph cache across cards.
///
/// 演示 provider 层：一次配置三家族的聚合 [CountmanProvider]，以及独立的、还共享
/// 字形缓存的 [CountdownCardProvider]。
class ProviderPage extends StatelessWidget {
  const ProviderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Providers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            title: 'CountmanProvider (aggregate)',
            description:
                'One provider sets shared defaults (textStyle / color / trackColor / '
                'duration / curve / formatter) for the counter, countdown AND '
                'elapsed families below — no per-widget style needed.',
            child: _AggregateDemo(),
          ),
          SizedBox(height: 16),
          _Section(
            title: 'CountdownCardProvider',
            description:
                'Cascades card visuals (cardColor / textStyle / transitionType) and '
                'shares one glyph cache across every CountdownCard in scope.',
            child: _CardProviderDemo(),
          ),
        ],
      ),
    );
  }
}

/// All three families under a single [CountmanProvider]; each descendant is
/// declared with NO local style and inherits the shared defaults.
///
/// 三家族置于同一 [CountmanProvider] 下；每个后代都不带本地样式，继承共享默认值。
class _AggregateDemo extends StatelessWidget {
  const _AggregateDemo();

  @override
  Widget build(BuildContext context) {
    return CountmanProvider(
      textStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      color: const Color(0xFF7E57C2),
      trackColor: const Color(0x337E57C2),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      formatter: CountdownFormat.hms,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CounterText (inherits textStyle + duration + curve):'),
          const SizedBox(height: 6),
          const CounterText(to: 2048),
          const SizedBox(height: 16),
          const Text('CounterRing (inherits color + trackColor):'),
          const SizedBox(height: 6),
          const CounterRing(to: 100, center: CounterText(to: 100, suffix: '%')),
          const SizedBox(height: 16),
          const Text('CountdownText (inherits textStyle + formatter=hms):'),
          const SizedBox(height: 6),
          CountdownText(to: const Duration(minutes: 90)),
          const SizedBox(height: 16),
          const Text('ElapsedText (inherits textStyle + formatter=hms):'),
          const SizedBox(height: 6),
          const ElapsedText(),
        ],
      ),
    );
  }
}

/// Two cards sharing one [CountdownCardProvider] — same look, one glyph cache.
///
/// 两张卡共用一个 [CountdownCardProvider]——外观一致，共享字形缓存。
class _CardProviderDemo extends StatelessWidget {
  const _CardProviderDemo();

  @override
  Widget build(BuildContext context) {
    return CountdownCardProvider(
      cardColor: const Color(0xFF00695C),
      textStyle: const TextStyle(
          fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
      transitionType: CountdownType.flip,
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          CountdownCard(to: const Duration(minutes: 5)),
          CountdownCard(to: const Duration(hours: 1, minutes: 30)),
        ],
      ),
    );
  }
}

/// A titled card wrapping one demo block.
///
/// 带标题、包裹单个 demo 块的卡片。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.description, required this.child});

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
