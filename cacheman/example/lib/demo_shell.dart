import 'package:flutter/material.dart';
import 'main.dart';
import 'pages/basic_page.dart';
import 'pages/ttl_page.dart';
import 'pages/batch_page.dart';
import 'pages/namespace_page.dart';
import 'pages/advanced_page.dart';

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  int _selectedIndex = 0;

  static const _items = [
    (label: 'Basic Ops', icon: Icons.storage),
    (label: 'TTL & Expiry', icon: Icons.timer),
    (label: 'Batch & Fast', icon: Icons.list_alt),
    (label: 'Namespace', icon: Icons.folder),
    (label: 'Debug & Jsonx', icon: Icons.bug_report),
  ];

  void _refresh() => setState(() {});

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return BasicPage(onChanged: _refresh);
      case 1:
        return TtlPage(onChanged: _refresh);
      case 2:
        return BatchPage(onChanged: _refresh);
      case 3:
        return NamespacePage(onChanged: _refresh);
      case 4:
        return AdvancedPage(onChanged: _refresh);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final permanent = width >= 700;

    final nav = NavigationDrawer(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) {
        setState(() => _selectedIndex = i);
        if (!permanent) Navigator.of(context).pop();
      },
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text('cacheman demo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        for (final item in _items)
          NavigationDrawerDestination(
            icon: Icon(item.icon),
            label: Text(item.label),
          ),
      ],
    );

    final body = Column(
      children: [
        Expanded(child: _buildPage()),
        _StatusBar(),
      ],
    );

    if (permanent) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 240, child: nav),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_items[_selectedIndex].label),
      ),
      drawer: nav,
      body: body,
    );
  }
}

class _StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.storage, size: 14),
          const SizedBox(width: 4),
          Text('ls: ${cache.ls.length} keys',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 24),
          const Icon(Icons.memory, size: 14),
          const SizedBox(width: 4),
          Text('ss: ${cache.ss.length} keys',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
