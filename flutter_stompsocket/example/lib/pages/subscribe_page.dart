import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

import '../stomp_state.dart';

class _SubEntry {
  _SubEntry({
    required this.id,
    required this.destination,
    required this.ackMode,
    this.subscription,
  });

  final String id;
  final String destination;
  final AckMode ackMode;
  final StompSubscription? subscription;
}

class SubscribePage extends StatefulWidget {
  const SubscribePage({super.key});

  @override
  State<SubscribePage> createState() => _SubscribePageState();
}

class _SubscribePageState extends State<SubscribePage> {
  final _destController = TextEditingController(text: '/topic/demo');
  AckMode _ackMode = AckMode.auto;
  final List<_SubEntry> _subs = [];
  Timer? _simTimer;
  int _simIdCounter = 0;
  int _simMsgCounter = 0;

  @override
  void dispose() {
    _simTimer?.cancel();
    _destController.dispose();
    super.dispose();
  }

  bool get _isSimMode => activeSocket == null;

  void _subscribe() {
    final dest = _destController.text.trim();
    if (dest.isEmpty) return;

    if (_isSimMode) {
      final id = 'sim-sub-${_simIdCounter++}';
      setState(() {
        _subs.add(_SubEntry(id: id, destination: dest, ackMode: _ackMode));
      });
      addLog('[sim] Subscribed: $id -> $dest (ack: ${_ackMode.name})');
      _startSimTimer();
    } else {
      final sub = activeSocket!.subscribe(
        dest,
        (json, ack) {
          addLog('[real] Received on $dest: $json');
          if (_ackMode == AckMode.manual) {
            ack.ack();
            addLog('[real] Manually ACKed');
          }
        },
        ack: _ackMode,
      );
      setState(() {
        _subs.add(_SubEntry(
          id: sub.id,
          destination: dest,
          ackMode: _ackMode,
          subscription: sub,
        ));
      });
      addLog('[real] Subscribed: ${sub.id} -> $dest (ack: ${_ackMode.name})');
    }
  }

  void _startSimTimer() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_subs.isEmpty) return;
      final entry = _subs[_simMsgCounter % _subs.length];
      final payload = {'msg': 'hello #$_simMsgCounter', 'ts': DateTime.now().toIso8601String()};
      addLog('[sim] Received on ${entry.destination}: $payload');
      if (entry.ackMode == AckMode.manual) {
        addLog('[sim] ack.ack() called (manual mode)');
      }
      _simMsgCounter++;
    });
  }

  void _unsubscribe(_SubEntry entry) {
    if (_isSimMode) {
      setState(() => _subs.remove(entry));
      addLog('[sim] Unsubscribed: ${entry.id}');
      if (_subs.isEmpty) _simTimer?.cancel();
    } else {
      entry.subscription?.unsubscribe();
      setState(() => _subs.remove(entry));
      addLog('[real] Unsubscribed: ${entry.id}');
    }
  }

  void _clearAll() {
    if (_isSimMode) {
      final count = _subs.length;
      setState(() => _subs.clear());
      _simTimer?.cancel();
      addLog('[sim] Cleared $count subscriptions');
    } else {
      final count = activeSocket?.unsubscribe(destination: _destController.text.trim()) ?? 0;
      setState(() => _subs.clear());
      addLog('[real] clear() called — $count removed');
    }
  }

  void _simulateMessage() {
    if (_subs.isEmpty) {
      addLog('[sim] No active subscriptions');
      return;
    }
    final entry = _subs.first;
    final payload = {'manual': true, 'msg': 'tapped #$_simMsgCounter'};
    addLog('[sim] Received on ${entry.destination}: $payload');
    if (entry.ackMode == AckMode.manual) addLog('[sim] ack.ack() called (manual mode)');
    _simMsgCounter++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscribe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _destController,
            decoration: const InputDecoration(
              labelText: 'Destination (e.g. /topic/demo)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AckMode>(
            initialValue: _ackMode,
            decoration: const InputDecoration(
              labelText: 'AckMode',
              border: OutlineInputBorder(),
            ),
            items: AckMode.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                .toList(),
            onChanged: (v) => setState(() => _ackMode = v!),
          ),
          const SizedBox(height: 8),
          _AckModeHelp(mode: _ackMode),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _subscribe, child: const Text('Subscribe')),
              if (_isSimMode)
                OutlinedButton(
                    onPressed: _simulateMessage,
                    child: const Text('Simulate Received Message')),
              OutlinedButton(onPressed: _clearAll, child: const Text('Clear All')),
            ],
          ),
          const SizedBox(height: 16),
          if (_subs.isEmpty)
            const Text('No active subscriptions.',
                style: TextStyle(color: Colors.grey))
          else
            ..._subs.map((e) => Card(
                  child: ListTile(
                    title: Text(e.destination),
                    subtitle: Text('id: ${e.id}  ack: ${e.ackMode.name}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _unsubscribe(e),
                      tooltip: 'Unsubscribe',
                    ),
                  ),
                )),
          const SizedBox(height: 16),
          _CodeCard(),
          const SizedBox(height: 16),
          _LogPanel(),
        ],
      ),
    );
  }
}

class _AckModeHelp extends StatelessWidget {
  final AckMode mode;
  const _AckModeHelp({required this.mode});

  @override
  Widget build(BuildContext context) {
    final desc = switch (mode) {
      AckMode.auto =>
        'auto: No ACK sent. Broker considers the message delivered immediately.',
      AckMode.smart =>
        'smart: ACK sent automatically on success, NACK on parse error. Uses client-individual.',
      AckMode.manual =>
        'manual: Callback must call ack.ack() or ack.nack() explicitly. Unacknowledged = redelivery.',
    };
    return Text(desc, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _CodeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const code = '''final sub = socket.subscribe(
  '/topic/demo',
  (json, ack) {
    print(json);           // Dictional = Map<String, dynamic>
    ack.ack();             // only needed in AckMode.manual
  },
  ack: AckMode.auto,       // auto / smart / manual
);

// Unsubscribe one callback
sub.unsubscribe();

// Remove by id or destination
socket.unsubscribe(id: sub.id);
socket.unsubscribe(destination: '/topic/demo');

// Remove all
socket.clear();''';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('subscribe() API', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SelectableText(code,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
                Text('Message Log', style: Theme.of(context).textTheme.labelMedium),
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
