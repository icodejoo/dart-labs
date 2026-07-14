import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

import '../stomp_state.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  bool _realMode = false;
  final _urlController = TextEditingController(text: 'wss://your-broker/ws');
  final _loginController = TextEditingController();
  final _passcodeController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _loginController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  void _simConnect() {
    if (stateNotifier.value != StompConnectionState.idle &&
        stateNotifier.value != StompConnectionState.disconnected) {
      return;
    }
    stateNotifier.value = StompConnectionState.connecting;
    addLog('[sim] Connecting...');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (stateNotifier.value == StompConnectionState.connecting) {
        stateNotifier.value = StompConnectionState.connected;
        addLog('[sim] Connected');
      }
    });
  }

  void _simDisconnect() {
    stateNotifier.value = StompConnectionState.idle;
    addLog('[sim] Disconnected');
  }

  void _simReconnect() {
    if (stateNotifier.value != StompConnectionState.connected) return;
    stateNotifier.value = StompConnectionState.reconnecting;
    addLog('[sim] Reconnecting...');
    Future.delayed(const Duration(seconds: 2), () {
      if (stateNotifier.value == StompConnectionState.reconnecting) {
        stateNotifier.value = StompConnectionState.connected;
        addLog('[sim] Reconnected');
      }
    });
  }

  void _realConnect() {
    activeSocket?.dispose();
    final url = _urlController.text.trim();
    final login = _loginController.text.trim();
    final passcode = _passcodeController.text.trim();
    final headers = <String, String>{};
    if (login.isNotEmpty) headers['login'] = login;
    if (passcode.isNotEmpty) headers['passcode'] = passcode;

    final socket = Stompsocket(
      url: url,
      reconnectDelay: const Duration(seconds: 5),
      queueWhileDisconnected: true,
      maxQueuedMessages: 100,
      debug: true,
      connectHeaders: headers.isEmpty ? null : headers,
      onStateChanged: (s) {
        stateNotifier.value = s;
        addLog('[real] State: ${s.name}');
      },
      onConnected: (frame) => addLog('[real] CONNECTED frame received'),
      onDisconnected: (frame) => addLog('[real] DISCONNECTED frame received'),
      onStompError: (frame) => addLog('[real] STOMP ERROR: ${frame.body}'),
      onWebSocketError: (e) => addLog('[real] WS error: $e'),
    );
    activeSocket = socket;
    addLog('[real] activate() called for $url');
    socket.activate();
  }

  void _realDisconnect() {
    activeSocket?.dispose();
    activeSocket = null;
    addLog('[real] dispose() called');
  }

  void _realForceReconnect() {
    activeSocket?.forceReconnect();
    addLog('[real] forceReconnect() called');
  }

  String get _codeSnippet {
    if (!_realMode) {
      return '''// Simulation mode
final socket = Stompsocket(
  url: 'wss://broker/ws',
  reconnectDelay: Duration(seconds: 5),
  onStateChanged: (s) => print(s),
  onConnected: (frame) => print('connected'),
);
socket.activate();     // start
socket.forceReconnect(); // skip delay
socket.dispose();      // stop''';
    }
    final url = _urlController.text.trim();
    final login = _loginController.text.trim();
    return '''final socket = Stompsocket(
  url: '$url',
  reconnectDelay: Duration(seconds: 5),
  queueWhileDisconnected: true,
  maxQueuedMessages: 100,
  debug: true,${login.isNotEmpty ? "\n  connectHeaders: {'login': '$login', 'passcode': '...'}," : ''}
  onStateChanged: (s) => print(s.name),
  onConnected: (frame) => print('connected'),
  onStompError: (frame) => print(frame.body),
);
socket.activate();''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Text('Real Server Mode'),
              const SizedBox(width: 8),
              Switch(
                value: _realMode,
                onChanged: (v) => setState(() => _realMode = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_realMode) ...[
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Broker URL (ws:// or wss://)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(
                labelText: 'Login (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passcodeController,
              decoration: const InputDecoration(
                labelText: 'Passcode (optional)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: _realConnect, child: const Text('Connect')),
                OutlinedButton(onPressed: _realDisconnect, child: const Text('Disconnect')),
                OutlinedButton(
                    onPressed: _realForceReconnect, child: const Text('Force Reconnect')),
              ],
            ),
          ] else ...[
            _StateChip(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                    onPressed: _simConnect, child: const Text('Connect (simulated)')),
                OutlinedButton(onPressed: _simDisconnect, child: const Text('Disconnect')),
                OutlinedButton(
                    onPressed: _simReconnect, child: const Text('Simulate Reconnect')),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _CodeCard(code: _codeSnippet),
          const SizedBox(height: 20),
          _LogPanel(),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StompConnectionState>(
      valueListenable: stateNotifier,
      builder: (context, state, _) {
        final color = switch (state) {
          StompConnectionState.idle => Colors.grey,
          StompConnectionState.connecting => Colors.orange,
          StompConnectionState.connected => Colors.green,
          StompConnectionState.reconnecting => Colors.yellow.shade700,
          StompConnectionState.disconnected => Colors.red,
        };
        return Chip(
          avatar: CircleAvatar(backgroundColor: color, radius: 6),
          label: Text('State: ${state.name}'),
        );
      },
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  const _CodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code Preview', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: messageLog,
      builder: (context, logs, _) {
        if (logs.isEmpty) return const SizedBox.shrink();
        final recent = logs.reversed.take(20).toList();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Log', style: Theme.of(context).textTheme.labelMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () => messageLog.value = [],
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                ...recent.map((l) => Text(l,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
              ],
            ),
          ),
        );
      },
    );
  }
}
