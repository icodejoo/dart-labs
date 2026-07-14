import 'package:flutter/material.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

import 'stomp_state.dart';
import 'pages/connection_page.dart';
import 'pages/subscribe_page.dart';
import 'pages/send_page.dart';
import 'pages/config_page.dart';

class DemoShell extends StatefulWidget {
  const DemoShell({super.key});

  @override
  State<DemoShell> createState() => _DemoShellState();
}

class _DemoShellState extends State<DemoShell> {
  int _selectedIndex = 0;

  static const _pages = [
    ConnectionPage(),
    SubscribePage(),
    SendPage(),
    ConfigPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StateBar(),
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.wifi), label: 'Connection'),
              NavigationDestination(
                  icon: Icon(Icons.notifications_active), label: 'Subscribe'),
              NavigationDestination(icon: Icon(Icons.send), label: 'Send'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Config'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StompConnectionState>(
      valueListenable: stateNotifier,
      builder: (context, state, _) {
        final (color, label) = switch (state) {
          StompConnectionState.idle => (Colors.grey, 'Idle'),
          StompConnectionState.connecting => (Colors.orange, 'Connecting'),
          StompConnectionState.connected => (Colors.green, 'Connected'),
          StompConnectionState.reconnecting => (Colors.yellow.shade700, 'Reconnecting'),
          StompConnectionState.disconnected => (Colors.red, 'Disconnected'),
        };
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'Connection: $label',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
