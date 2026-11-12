import 'package:flutter/material.dart';

import '../demo_kit/demo_kit.dart';
import '../demo_settings.dart';
import '../demo_widgets.dart';

/// 当前公开参数的双语说明。
class _Option {
  /// 保存 API 名、默认值和双语契约。
  const _Option(this.name, this.value, this.en, this.zh);

  /// 公开参数或方法名。
  final String name;

  /// 默认值或返回值。
  final String value;

  /// 英文说明。
  final String en;

  /// 中文说明。
  final String zh;
}

/// 与当前 lib 构造器和公开方法逐项对照的参考页。
class ConfigPage extends StatelessWidget {
  /// 创建参考页。
  const ConfigPage({super.key});

  /// 可选参数的空默认值。
  static const _none = 'null';

  /// 布尔启用默认值。
  static const _enabled = 'true';

  /// 布尔关闭默认值。
  static const _disabled = 'false';

  /// 默认心跳与重试时长。
  static const _fiveSeconds = '5s';

  /// 无返回值的方法签名。
  static const _void = 'void';

  /// 连接参数；浏览器能力限制明确列出。
  static const _connection = [
    _Option(
      'url',
      'required',
      'STOMP ws:// or wss:// endpoint.',
      'STOMP 的 ws:// 或 wss:// 端点。',
    ),
    _Option(
      'reconnectDelay',
      _fiveSeconds,
      'Fixed retry interval; zero disables retries.',
      '固定重试间隔；零关闭自动重试。',
    ),
    _Option(
      'connectionTimeout',
      'Duration.zero',
      'No timeout by default; demo uses 10s.',
      '默认不限时；演示设为 10 秒。',
    ),
    _Option(
      'connectHeaders',
      _none,
      'Headers in the STOMP CONNECT frame.',
      'STOMP CONNECT 帧的协议头。',
    ),
    _Option(
      'beforeConnect',
      _none,
      'Async preparation; non-null result replaces CONNECT headers each attempt.',
      '每次连接前异步准备；非空返回值替换 CONNECT 头。',
    ),
    _Option(
      'webSocketConnectHeaders',
      _none,
      'HTTP upgrade headers; unavailable in browsers.',
      'HTTP 握手头；浏览器不支持。',
    ),
    _Option(
      'useSockJS',
      _disabled,
      'Select SockJS transport for a compatible endpoint.',
      '为兼容的端点选择 SockJS 传输。',
    ),
  ];

  /// 心跳参数。
  static const _heartbeat = [
    _Option(
      'heartbeatIncoming',
      _fiveSeconds,
      'Requested incoming heartbeat interval.',
      '期望接收的心跳间隔。',
    ),
    _Option(
      'heartbeatOutgoing',
      _fiveSeconds,
      'Requested outgoing heartbeat interval.',
      '期望发送的心跳间隔。',
    ),
    _Option(
      'pingInterval',
      _none,
      'WebSocket ping; unavailable in browsers.',
      'WebSocket ping 间隔；浏览器不支持。',
    ),
  ];

  /// 可靠性与解析参数。
  static const _reliability = [
    _Option(
      'queueWhileDisconnected',
      _enabled,
      'Buffer sends while disconnected.',
      '未连接时缓冲出站消息。',
    ),
    _Option(
      'maxQueuedMessages',
      '${DemoSettings.queueLimit}',
      'Drop oldest on overflow; non-positive disables buffering.',
      '超限丢最旧；非正值关闭缓冲。',
    ),
    _Option(
      'resumeOnForeground',
      _enabled,
      'Reconnect when resumed and disconnected; requires Flutter binding.',
      '回到前台且未连接时重连；需要 Flutter binding。',
    ),
    _Option(
      'binaryDecoder',
      _none,
      'Returns ParsedMessage; use top-level/static for large native payloads.',
      '返回 ParsedMessage；原生大包需顶层或静态函数。',
    ),
    _Option(
      'debug',
      _disabled,
      'Enable internal logs and frame traces.',
      '启用内部日志和帧流水。',
    ),
    _Option(
      'onLog',
      _none,
      'Custom internal log sink when debug is true.',
      'debug 为 true 时接管内部日志。',
    ),
  ];

  /// 全部公开回调。
  static const _callbacks = [
    _Option(
      'onConnected',
      _none,
      'After subscriptions restore and the outbox flushes.',
      '恢复订阅并补发缓冲之后调用。',
    ),
    _Option(
      'onDisconnected',
      _none,
      'On STOMP DISCONNECT; use stateListenable for current state.',
      '收到 STOMP DISCONNECT 时调用；当前状态请监听 stateListenable。',
    ),
    _Option(
      'onStateChanged',
      _none,
      'Every connection state transition.',
      '每次连接状态变化。',
    ),
    _Option('onStompError', _none, 'Broker ERROR frame.', 'Broker 的 ERROR 帧。'),
    _Option('onWebSocketError', _none, 'Transport error.', '传输错误。'),
    _Option('onWebSocketDone', _none, 'Transport closed.', '传输已关闭。'),
    _Option(
      'onDebugMessage',
      _none,
      'Raw upstream frame trace, independent of the internal log sink.',
      '底层帧流水，独立于内部日志接收器。',
    ),
    _Option(
      'onParseFailure',
      _none,
      'Binary decoding failure; exceptions here do not change ACK policy.',
      '二进制解码失败；此回调抛错不改变确认策略。',
    ),
    _Option(
      'onUnhandledFrame / onUnhandledMessage / onUnhandledReceipt',
      _none,
      'Unmatched frames, messages or receipts.',
      '未匹配的帧、消息或回执。',
    ),
  ];

  /// 生命周期与订阅的公开方法及默认值。
  static const _methods = [
    _Option('activate()', _void, 'Start or resume this instance.', '启动或恢复此实例。'),
    _Option(
      'dispose(keepSubscriptions: false)',
      _void,
      'Reversible stop; always retains outbox.',
      '可逆停止；始终保留待发缓冲。',
    ),
    _Option(
      'forceReconnect()',
      _void,
      'Only reconnects while disconnected and still wanting a connection.',
      '仅在未连接且仍期望连接时重连。',
    ),
    _Option(
      'copyWith(...)',
      'Stompsocket',
      'Fresh idle client; null inherits, so cannot clear nullable options.',
      '返回全新未连接客户端；null 表示继承，不能清空可空选项。',
    ),
    _Option(
      'subscribe(destination, callback)',
      'StompSubscription',
      'Defaults: ordered:true, ack:auto, onParseError:nack; optional id.',
      '默认 ordered:true、ack:auto、onParseError:nack；可指定 id。',
    ),
    _Option(
      'unsubscribe(id: / destination:)',
      'int',
      'Remove by id or destination; id takes priority.',
      '按 id 或目的地取消；id 优先，返回移除数量。',
    ),
    _Option(
      'clear()',
      _void,
      'Remove every subscription, not the outbox.',
      '取消全部订阅，不清空待发缓冲。',
    ),
    _Option(
      'send(destination, body:, headers:)',
      _void,
      'String, JSON values, Uint8List or null.',
      '支持 String、JSON 值、Uint8List 或 null。',
    ),
    _Option(
      'state / stateListenable / connected / client',
      'getters',
      'Current state, reactive state, connected flag and underlying client.',
      '当前状态、响应式状态、连接标记与底层客户端。',
    ),
  ];

  /// 可复制的配置示例，显式写出当前默认值。
  static const _code =
      '''final socket = Stompsocket(
  url: '${DemoSettings.brokerUrl}',
  reconnectDelay: const Duration(seconds: 5),
  heartbeatIncoming: const Duration(seconds: 5),
  heartbeatOutgoing: const Duration(seconds: 5),
  connectionTimeout: const Duration(seconds: 10),
  queueWhileDisconnected: true,
  maxQueuedMessages: ${DemoSettings.queueLimit},
  resumeOnForeground: true,
  onParseFailure: (frame, error) => report(error),
);
final independent = socket.copyWith(url: 'wss://other.example.com/ws');
independent.activate();
independent.dispose();''';

  /// 将一组参考项放进静态卡片，不添加重放按钮。
  DemoGridItem _card(
    BuildContext context,
    String en,
    String zh,
    List<_Option> options,
  ) => DemoGridItem(
    child: DemoCard(
      title: tr(context, en, zh),
      description: tr(
        context,
        'Current public API · package defaults',
        '当前公开 API · 包默认值',
      ),
      replayable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: DemoTokens.gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    option.name,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: DemoTokens.captionSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    option.value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(tr(context, option.en, option.zh)),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  /// 构建按主题分组的参考网格，长代码占整行。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.referenceEn, DemoCopy.referenceZh),
    description: tr(
      context,
      'Defaults verified against the current public constructor and methods.',
      '已逐项对照当前公开构造器与方法核验默认值。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Constructor', '构造参数'),
        code: _code,
        child: DemoGrid(
          children: [
            _card(
              context,
              DemoCopy.connectionEn,
              DemoCopy.connectionZh,
              _connection,
            ),
            _card(context, 'Heartbeats', '心跳', _heartbeat),
            _card(context, 'Reliability & parsing', '可靠性与解析', _reliability),
          ],
        ),
      ),
      DemoSection(
        title: tr(context, 'Callbacks & methods', '回调与方法'),
        child: DemoGrid(
          children: [
            _card(context, 'Callbacks', '回调', _callbacks),
            _card(context, 'Lifecycle & subscriptions', '生命周期与订阅', _methods),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Text parsing accepts every JSON value; malformed JSON remains raw text. Native large payloads use compute; on Web compute stays on the current event loop.',
          '文本解析接受任意 JSON 值，非法 JSON 保留为原始文本。原生大包使用 compute；Web 的 compute 仍在当前事件循环执行。',
        ),
      ),
    ],
  );
}
