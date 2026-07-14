import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _Param {
  const _Param({
    required this.name,
    required this.defaultValue,
    required this.description,
  });

  final String name;
  final String defaultValue;
  final String description;
}

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  static const _connectionParams = [
    _Param(
      name: 'url',
      defaultValue: '(required)',
      description: 'WebSocket URL — ws:// or wss://.',
    ),
    _Param(
      name: 'reconnectDelay',
      defaultValue: 'Duration(seconds: 5)',
      description: 'Fixed backoff between reconnect attempts. Zero disables auto-reconnect.',
    ),
    _Param(
      name: 'connectionTimeout',
      defaultValue: 'Duration.zero',
      description: 'Timeout for the initial STOMP CONNECT handshake. Zero = no timeout.',
    ),
    _Param(
      name: 'connectHeaders',
      defaultValue: 'null',
      description: 'Extra STOMP CONNECT frame headers (login, passcode, host, etc.).',
    ),
    _Param(
      name: 'webSocketConnectHeaders',
      defaultValue: 'null',
      description: 'HTTP upgrade headers sent when opening the WebSocket.',
    ),
    _Param(
      name: 'useSockJS',
      defaultValue: 'false',
      description: 'Use SockJS transport instead of raw WebSocket (requires stomp_dart_client SockJS support).',
    ),
    _Param(
      name: 'beforeConnect',
      defaultValue: 'null',
      description: 'Async callback called before each connect attempt — use to refresh tokens.',
    ),
  ];

  static const _heartbeatParams = [
    _Param(
      name: 'heartbeatIncoming',
      defaultValue: 'Duration(seconds: 5)',
      description: 'Minimum desired interval for heartbeats received from broker.',
    ),
    _Param(
      name: 'heartbeatOutgoing',
      defaultValue: 'Duration(seconds: 5)',
      description: 'Minimum desired interval for heartbeats sent to broker.',
    ),
    _Param(
      name: 'pingInterval',
      defaultValue: 'null',
      description: 'WebSocket-level ping interval. Null = disabled.',
    ),
  ];

  static const _reliabilityParams = [
    _Param(
      name: 'queueWhileDisconnected',
      defaultValue: 'true',
      description: 'Buffer outbound messages when not connected and flush on reconnect.',
    ),
    _Param(
      name: 'maxQueuedMessages',
      defaultValue: '100',
      description: 'Max buffered outbound messages. Oldest dropped when limit is exceeded.',
    ),
    _Param(
      name: 'resumeOnForeground',
      defaultValue: 'false',
      description: 'Force reconnect when the app returns to foreground (requires WidgetsBinding).',
    ),
    _Param(
      name: 'binaryDecoder',
      defaultValue: 'null',
      description: 'Converts incoming binary frames (Uint8List) to Dictional. Large payloads run in isolate.',
    ),
  ];

  static const _callbackParams = [
    _Param(
      name: 'onConnected',
      defaultValue: 'null',
      description: 'Called after each successful CONNECT (initial + reconnect). Subscriptions already replayed.',
    ),
    _Param(
      name: 'onDisconnected',
      defaultValue: 'null',
      description: 'Called when a STOMP DISCONNECT frame is received.',
    ),
    _Param(
      name: 'onStateChanged',
      defaultValue: 'null',
      description: 'Called on every StompConnectionState transition. Handy for GetX/Riverpod bridges.',
    ),
    _Param(
      name: 'onStompError',
      defaultValue: 'null',
      description: 'Called when the broker sends a STOMP ERROR frame (auth failure, bad destination, etc.).',
    ),
    _Param(
      name: 'onWebSocketError',
      defaultValue: 'null',
      description: 'Called on WebSocket layer errors.',
    ),
    _Param(
      name: 'onWebSocketDone',
      defaultValue: 'null',
      description: 'Called when the WebSocket closes (before reconnect attempt).',
    ),
    _Param(
      name: 'onDebugMessage',
      defaultValue: 'null',
      description: 'Raw frame-level log (>>> CONNECT, <<< CONNECTED, PING/PONG). Independent of debug flag.',
    ),
    _Param(
      name: 'onLog',
      defaultValue: 'null',
      description: 'Custom log sink used when debug=true. Falls back to dart:developer log.',
    ),
  ];

  static const _miscParams = [
    _Param(
      name: 'debug',
      defaultValue: 'false',
      description: 'Master switch for all internal logging.',
    ),
  ];

  static const _fullSnippet = '''final socket = Stompsocket(
  url: 'wss://broker.example.com/ws',
  reconnectDelay: Duration(seconds: 5),
  connectionTimeout: Duration.zero,
  connectHeaders: {
    'login': 'user',
    'passcode': 'secret',
  },
  webSocketConnectHeaders: {'Authorization': 'Bearer \$token'},
  useSockJS: false,
  beforeConnect: () async => {'login': await refreshToken()},
  heartbeatIncoming: Duration(seconds: 5),
  heartbeatOutgoing: Duration(seconds: 5),
  pingInterval: null,
  queueWhileDisconnected: true,
  maxQueuedMessages: 100,
  resumeOnForeground: false,
  binaryDecoder: myProtoDecoder,
  debug: false,
  onLog: (msg, {error, stackTrace}) => logger.d(msg),
  onConnected: (frame) => print('connected'),
  onDisconnected: (frame) => print('disconnected'),
  onStateChanged: (s) => rxState.value = s,
  onStompError: (frame) => print('error: \${frame.body}'),
  onWebSocketError: (e) => print('ws error: \$e'),
  onWebSocketDone: () => print('ws done'),
  onDebugMessage: (msg) => print(msg),
);
socket.activate();''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Config Reference')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Connection', params: _connectionParams),
          _Section(title: 'Heartbeat', params: _heartbeatParams),
          _Section(title: 'Reliability', params: _reliabilityParams),
          _Section(title: 'Callbacks', params: _callbackParams),
          _Section(title: 'Misc', params: _miscParams),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Full Constructor',
                          style: Theme.of(context).textTheme.labelMedium),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copy',
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: _fullSnippet));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied to clipboard')));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _fullSnippet,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Param> params;

  const _Section({required this.title, required this.params});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card(
          child: Column(
            children: [
              for (int i = 0; i < params.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ParamRow(param: params[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ParamRow extends StatelessWidget {
  final _Param param;
  const _ParamRow({required this.param});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(param.name,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  'default: ${param.defaultValue}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(param.description, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
