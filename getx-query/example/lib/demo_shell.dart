import 'package:flutter/material.dart';
import 'pages/query_page.dart';
import 'pages/mutation_page.dart';
import 'pages/infinite_page.dart';
import 'pages/queries_page.dart';
import 'pages/viewmodel_page.dart';

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});
  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.cloud_download, label: 'useQuery'),
    (icon: Icons.edit, label: 'useMutation'),
    (icon: Icons.expand_more, label: 'Infinite'),
    (icon: Icons.widgets, label: 'useQueries'),
    (icon: Icons.architecture, label: 'ViewModel'),
  ];

  static const _pages = [
    QueryPage(),
    MutationPage(),
    InfinitePage(),
    QueriesPage(),
    ViewModelPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _pages[_index]),
          ],
        ),
      );
    }
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: [
          for (final d in _destinations)
            BottomNavigationBarItem(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
