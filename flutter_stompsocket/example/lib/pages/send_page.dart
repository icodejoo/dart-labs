import 'dart:convert';

import 'package:flutter/material.dart';

import '../stomp_state.dart';

enum _BodyType { string, json, none }

class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final _destController = TextEditingController(text: '/app/message');
  final _bodyController = TextEditingController(text: '{"text": "hello"}');
  _BodyType _bodyType = _BodyType.json;

  void _send() {
    final dest = _destController.text.trim();
    if (dest.isEmpty) {
      addLog('[send] Destination is empty');
      return;
    }

    Object? body;
    String bodyDesc;
    switch (_bodyType) {
      case _BodyType.string:
        body = _bodyController.text;
        bodyDesc = 'String: "${_bodyController.text}"';
      case _BodyType.json:
        try {
          body = jsonDecode(_bodyController.text) as Map<String, dynamic>;
          bodyDesc = 'JSON: ${_bodyController.text}';
        } catch (e) {
          addLog('[send] Invalid JSON: $e');
          return;
        }
      case _BodyType.none:
        body = null;
        bodyDesc = 'null';
    }

    if (activeSocket == null) {
      addLog('[sim] send($dest, body: $bodyDesc)');
      return;
    }

    if (!activeSocket!.connected) {
      if (activeSocket!.queueWhileDisconnected) {
        addLog('[real] Not connected — queued: send($dest)');
      } else {
        addLog('[real] Not connected & queueWhileDisconnected=false — dropped');
      }
      return;
    }

    activeSocket!.send(dest, body: body);
    addLog('[real] Sent to $dest — $bodyDesc');
  }

  String get _codeSnippet {
    final dest = _destController.text.trim();
    return switch (_bodyType) {
      _BodyType.string =>
        'socket.send(\n  \'$dest\',\n  body: \'${_bodyController.text}\',\n);',
      _BodyType.json =>
        'socket.send(\n  \'$dest\',\n  // Map/List → auto JSON encoded\n  // content-type: application/json added\n  body: ${_bodyController.text},\n);',
      _BodyType.none => 'socket.send(\n  \'$dest\',\n  // no body\n);',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _destController,
            decoration: const InputDecoration(
              labelText: 'Destination (e.g. /app/message)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_BodyType>(
            initialValue: _bodyType,
            decoration: const InputDecoration(
              labelText: 'Body type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: _BodyType.string, child: Text('String')),
              DropdownMenuItem(value: _BodyType.json, child: Text('JSON object')),
              DropdownMenuItem(value: _BodyType.none, child: Text('null (no body)')),
            ],
            onChanged: (v) => setState(() => _bodyType = v!),
          ),
          if (_bodyType != _BodyType.none) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: InputDecoration(
                labelText: _bodyType == _BodyType.json ? 'JSON body' : 'String body',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          _QueueStatus(),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _send,
            icon: const Icon(Icons.send),
            label: const Text('Send'),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Code Preview', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  SelectableText(_codeSnippet,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _BodyHelp(type: _bodyType),
          const SizedBox(height: 16),
          _LogPanel(),
        ],
      ),
    );
  }
}

class _QueueStatus extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isReal = activeSocket != null;
    final queued = isReal && activeSocket!.queueWhileDisconnected;
    return Row(
      children: [
        Icon(queued || !isReal ? Icons.check_circle : Icons.cancel,
            size: 16, color: queued || !isReal ? Colors.green : Colors.orange),
        const SizedBox(width: 6),
        Text(
          isReal
              ? 'queueWhileDisconnected: ${activeSocket!.queueWhileDisconnected}'
              : 'Simulation mode — sends logged only',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BodyHelp extends StatelessWidget {
  final _BodyType type;
  const _BodyHelp({required this.type});

  @override
  Widget build(BuildContext context) {
    final desc = switch (type) {
      _BodyType.string => 'String body is sent as-is with no content-type header added.',
      _BodyType.json =>
        'Map/List body is auto JSON-encoded. content-type: application/json is added automatically.',
      _BodyType.none => 'Null body sends a SEND frame with no body bytes.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Body Encoding', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(desc, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            const SelectableText(
              '// Offline queuing\n'
              '// queueWhileDisconnected: true  → buffered, sent on reconnect\n'
              '// queueWhileDisconnected: false → dropped with a log warning\n'
              '// maxQueuedMessages: 100 → oldest dropped when full',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
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
                Text('Send Log', style: Theme.of(context).textTheme.labelMedium),
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
