import 'package:flutter/material.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

import '../demo_kit/demo_kit.dart';
import '../demo_session.dart';
import '../demo_settings.dart';
import '../demo_widgets.dart';

/// 连接生命周期及可选的真实 broker 设置。
class ConnectionPage extends StatelessWidget {
  /// 创建连接页。
  const ConnectionPage({super.key});

  /// 当前 API 的生命周期示例，不插入用户凭据。
  static const _code =
      '''final socket = Stompsocket(
  url: '${DemoSettings.brokerUrl}',
  connectionTimeout: const Duration(seconds: 10),
  beforeConnect: () async => {'Authorization': 'Bearer \${await getToken()}'},
  onStateChanged: (state) => updateStatus(state),
  onConnected: (_) => resyncSnapshot(),
);
socket.activate();
socket.dispose(keepSubscriptions: true);
socket.activate();
socket.forceReconnect();
socket.dispose();''';

  /// 构建首屏可操作的连接卡片与独立静态说明。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    return DemoPage(
      title: tr(context, DemoCopy.connectionEn, DemoCopy.connectionZh),
      description: tr(
        context,
        'Explore the lifecycle offline, then connect your own STOMP broker.',
        '先离线体验状态变化，再连接自己的 STOMP broker。',
      ),
      sections: [
        DemoSection(
          title: tr(context, 'Start a session', '开始会话'),
          code: _code,
          child: DemoGrid(
            children: [
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Connection lifecycle', '连接生命周期'),
                  description: tr(
                    context,
                    'Replay cancels timers and starts a fresh session, clearing subscriptions and outbox.',
                    '重放取消计时并创建全新会话，清空订阅与缓冲。',
                  ),
                  onReplay: session.reset,
                  child: const _ConnectionControls(),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Broker settings', 'Broker 设置'),
                  description: tr(
                    context,
                    'Optional network access. Switching modes discards the old session.',
                    '按需连接网络；切换模式会清理旧会话。',
                  ),
                  onReplay: session.reset,
                  child: const _BrokerSettings(),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Reconnect contract', '重连约定'),
                  description: tr(
                    context,
                    'Current behavior; preview timings are illustrative.',
                    '当前行为；预览用时仅为示意。',
                  ),
                  replayable: false,
                  child: Text(
                    tr(
                      context,
                      'Default retry: 5s. Subscriptions restore before onConnected. Refresh a snapshot there. dispose is reversible; forceReconnect only acts while awaiting connection.',
                      '默认每 5 秒重试，恢复订阅后才调用 onConnected，可在此刷新快照。dispose 可恢复；forceReconnect 仅在等待连接时生效。',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        InfoNote(
          text: tr(
            context,
            'Preview does not open a socket. Real mode needs a STOMP endpoint, not a plain WebSocket echo server. On HTTPS use wss://; browser WebSocket upgrade headers and pingInterval are unavailable.',
            '预览不创建网络连接。真实模式需要 STOMP 端点，普通 WebSocket 回声服务不适用。HTTPS 页面请用 wss://；浏览器不支持自定义 WebSocket 握手头与 pingInterval。',
          ),
        ),
        const SessionLog(),
      ],
    );
  }
}

/// 使用外部会话控制连接，不在重建时创建额外计时器。
class _ConnectionControls extends StatelessWidget {
  /// 创建生命周期按钮组。
  const _ConnectionControls();

  /// 根据状态限制重复连接与无意义重连。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    final running =
        session.connection == StompConnectionState.connected ||
        session.connection == StompConnectionState.connecting ||
        session.connection == StompConnectionState.reconnecting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SessionStatus(),
        const SizedBox(height: DemoTokens.smallGap),
        Text(
          tr(
            context,
            'Set up a real broker in the next card. Preview connects in 0.5s.',
            '真实 broker 请在下一张卡配置；预览在 0.5 秒后连接。',
          ),
        ),
        const SizedBox(height: DemoTokens.smallGap),
        Wrap(
          spacing: DemoTokens.smallGap,
          runSpacing: DemoTokens.smallGap,
          children: [
            if (!session.realMode)
              FilledButton(
                onPressed: running
                    ? null
                    : () => session.connect(DemoSettings.brokerUrl),
                child: Text(
                  tr(context, DemoCopy.connectEn, DemoCopy.connectionZh),
                ),
              ),
            OutlinedButton(
              onPressed: running ? session.stop : null,
              child: Text(tr(context, 'Stop', '停止')),
            ),
            OutlinedButton(
              onPressed: session.realMode
                  ? (running &&
                            session.connection != StompConnectionState.connected
                        ? session.reconnect
                        : null)
                  : (session.connection == StompConnectionState.connected
                        ? session.reconnect
                        : null),
              child: Text(tr(context, 'Reconnect', '重连')),
            ),
          ],
        ),
      ],
    );
  }
}

/// 保存可重放的 broker 表单，不把密码插入日志或代码。
class _BrokerSettings extends StatefulWidget {
  /// 创建设置表单。
  const _BrokerSettings();

  /// 创建文本控制器状态。
  @override
  State<_BrokerSettings> createState() => _BrokerSettingsState();
}

/// 输入在页面卸载或重放时释放。
class _BrokerSettingsState extends State<_BrokerSettings> {
  /// broker 地址输入。
  final _url = TextEditingController(text: DemoSettings.brokerUrl);

  /// CONNECT login 输入。
  final _login = TextEditingController();

  /// CONNECT passcode 输入。
  final _passcode = TextEditingController();

  /// 释放表单控制器。
  @override
  void dispose() {
    _url.dispose();
    _login.dispose();
    _passcode.dispose();
    super.dispose();
  }

  /// 构建按需展开的真实模式设置。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    final hasSocket = session.socket != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(tr(context, 'Use real broker', '使用真实 broker')),
          value: session.realMode,
          onChanged: session.changeMode,
        ),
        if (!session.realMode)
          Text(
            tr(
              context,
              'No server required. Subscriptions and sends use a labeled preview.',
              '无需服务器；订阅和发送均有明确的预览标记。',
            ),
          ),
        if (session.realMode) ...[
          TextField(
            key: const ValueKey('broker-url'),
            controller: _url,
            enabled: !hasSocket,
            decoration: InputDecoration(
              labelText: tr(context, 'Broker URL', 'Broker 地址'),
            ),
          ),
          TextField(
            controller: _login,
            enabled: !hasSocket,
            decoration: InputDecoration(
              labelText: tr(context, 'Login (optional)', 'Login（可选）'),
            ),
          ),
          TextField(
            controller: _passcode,
            enabled: !hasSocket,
            obscureText: true,
            decoration: InputDecoration(
              labelText: tr(context, 'Passcode (optional)', 'Passcode（可选）'),
            ),
          ),
          const SizedBox(height: DemoTokens.smallGap),
          FilledButton(
            onPressed:
                session.connection == StompConnectionState.connected ||
                    session.connection == StompConnectionState.connecting ||
                    session.connection == StompConnectionState.reconnecting
                ? null
                : () => session.connect(
                    _url.text,
                    login: _login.text,
                    passcode: _passcode.text,
                  ),
            child: Text(
              hasSocket
                  ? tr(context, 'Resume', '恢复')
                  : tr(context, DemoCopy.connectEn, DemoCopy.connectionZh),
            ),
          ),
          Text(
            tr(
              context,
              'Replay to change credentials or endpoint.',
              '修改地址或凭据前请重放。',
            ),
          ),
        ],
      ],
    );
  }
}
