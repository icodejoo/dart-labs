import 'package:flutter/material.dart';
import 'pages/queue_page.dart';
import 'pages/replace_affix_page.dart';
import 'pages/overlap_page.dart';
import 'pages/barrier_page.dart';
import 'pages/timing_page.dart';
import 'pages/conditions_page.dart';
import 'pages/cooldown_page.dart';
import 'pages/lifecycle_page.dart';
import 'pages/pause_page.dart';
import 'pages/external_page.dart';
import 'pages/mixed_page.dart';
import 'pages/setup_page.dart';
import 'widgets/om_state_bar.dart';

// ── Destination manifest ─────────────────────────────────────────────────────

class _Dest {
  const _Dest(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _destinations = [
  _Dest('Queue Basics', Icons.queue_outlined),
  _Dest('Replace & Affix', Icons.swap_horiz),
  _Dest('Overlap', Icons.layers_outlined),
  _Dest('Barrier & Close', Icons.blur_on_outlined),
  _Dest('Timing', Icons.timer_outlined),
  _Dest('Conditions', Icons.filter_alt_outlined),
  _Dest('Cooldown', Icons.hourglass_empty),
  _Dest('Lifecycle', Icons.recycling_outlined),
  _Dest('Pause & Resume', Icons.pause_circle_outline),
  _Dest('External Presenters', Icons.open_in_new_outlined),
  _Dest('Mixed UI Libraries', Icons.auto_awesome_outlined),
  _Dest('Setup & Restart', Icons.settings_outlined),
];

const _pages = [
  QueuePage(),
  ReplaceAffixPage(),
  OverlapPage(),
  BarrierPage(),
  TimingPage(),
  ConditionsPage(),
  CooldownPage(),
  LifecyclePage(),
  PausePage(),
  ExternalPage(),
  MixedPage(),
  SetupPage(),
];

// ── Shell ────────────────────────────────────────────────────────────────────

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  int _selected = 0;

  Widget _navList(BuildContext ctx) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('layerman',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('All APIs demoed',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600])),
            ],
          ),
        ),
        for (var i = 0; i < _destinations.length; i++)
          Builder(
            builder: (tileCtx) => ListTile(
              leading: Icon(_destinations[i].icon, size: 20),
              title: Text(_destinations[i].label,
                  style: const TextStyle(fontSize: 13)),
              selected: _selected == i,
              selectedTileColor: Theme.of(ctx)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.6),
              selectedColor: Theme.of(ctx).colorScheme.onPrimaryContainer,
              onTap: () {
                setState(() => _selected = i);
                Scaffold.maybeOf(tileCtx)?.closeDrawer();
              },
              dense: true,
            ),
          ),
      ],
    );
  }

  Widget _body(bool wide, BuildContext ctx) {
    final content = Column(
      children: [
        Expanded(
          child: IndexedStack(index: _selected, children: _pages),
        ),
        const Divider(height: 1),
        const OmStateBar(),
      ],
    );

    if (wide) {
      return Row(
        children: [
          SizedBox(
            width: 210,
            child: Material(
              elevation: 1,
              child: _navList(ctx),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: content),
        ],
      );
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final wide = constraints.maxWidth >= 700;
        return Scaffold(
          appBar: AppBar(
            title: Text('layerman — ${_destinations[_selected].label}'),
            centerTitle: false,
          ),
          drawer: wide ? null : Drawer(child: _navList(ctx)),
          body: _body(wide, ctx),
        );
      },
    );
  }
}
