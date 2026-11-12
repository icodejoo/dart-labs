import 'package:flutter/material.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

import '../demo_kit/demo_kit.dart';
import '../demo_session.dart';
import '../demo_settings.dart';
import '../demo_widgets.dart';

/// 使用当前 ParsedMessage 与 AckControl API 的订阅演示。
class SubscribePage extends StatelessWidget {
  /// 创建订阅页。
  const SubscribePage({super.key});

  /// 使用手动模式保存句柄；自动模式可忽略第二参。
  static const _code =
      '''AckControl? pending;
final sub = socket.subscribe(
  '${DemoSettings.topic}',
  (ParsedMessage payload, AckControl ack) {
    render(payload);
    pending = ack;
  },
  ack: AckMode.manual,
  ordered: true,
  onParseError: ParseFailureAck.nack,
);
pending?.ack();
sub.unsubscribe();
socket.unsubscribe(id: sub.id);
socket.unsubscribe(destination: '${DemoSettings.topic}');
socket.clear();''';

  /// 构建注册、接收和类型说明三张卡片。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    return DemoPage(
      title: tr(context, DemoCopy.subscriptionsEn, DemoCopy.subscriptionsZh),
      description: tr(
        context,
        'Register callbacks, receive messages and acknowledge outside the callback.',
        '登记回调、接收消息，并在回调外手动确认。',
      ),
      sections: [
        DemoSection(
          title: tr(context, 'Register & receive', '登记与接收'),
          code: _code,
          child: DemoGrid(
            children: [
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Register callback', '登记回调'),
                  description: tr(
                    context,
                    'Replay clears all subscriptions and resets this form.',
                    '重放清空全部订阅并恢复表单。',
                  ),
                  onReplay: session.clearSubscriptions,
                  child: const _SubscribeEditor(),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Delivery & ACK', '消息与确认'),
                  description: tr(
                    context,
                    'Each callback keeps its registered ACK mode. Replay removes all callbacks.',
                    '每个回调保留注册时的确认模式；重放移除全部回调。',
                  ),
                  onReplay: session.clearSubscriptions,
                  child: const _Deliveries(),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'ParsedMessage', 'ParsedMessage 类型'),
                  description: tr(
                    context,
                    'JSON values and raw text are supported.',
                    '支持任意 JSON 值与原始文本。',
                  ),
                  replayable: false,
                  child: Text(
                    tr(
                      context,
                      'Map, List, string, number, bool and JSON null are delivered. Invalid JSON arrives as raw text. Binary decoding failures use onParseError. ordered defaults to true; equivalent options share one wire subscription.',
                      '可收到 Map、List、字符串、数字、布尔值及 JSON null。非法 JSON 作为原始文本交给回调。二进制解码失败按 onParseError 处理。ordered 默认 true；相同订阅选项共享一条 wire 订阅。',
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
            'Smart mode ACKs only after all synchronous callbacks succeed; any throw causes NACK. Use manual for asynchronous work. Old-session ACK handles become no-ops after reconnect.',
            'Smart 模式在全部同步回调成功后 ACK，任一回调抛错就 NACK；异步处理请用 manual。重连后旧会话确认句柄失效。',
          ),
        ),
        const SessionLog(),
      ],
    );
  }
}

/// 保存目的地和确认模式的卡片内部状态。
class _SubscribeEditor extends StatefulWidget {
  /// 创建可重放表单。
  const _SubscribeEditor();

  /// 创建编辑状态。
  @override
  State<_SubscribeEditor> createState() => _SubscribeEditorState();
}

/// 释放目的地控制器并保留模式选择。
class _SubscribeEditorState extends State<_SubscribeEditor> {
  /// 接收目的地。
  final _destination = TextEditingController(text: DemoSettings.topic);

  /// 下次注册使用的模式。
  AckMode _mode = AckMode.auto;

  /// 释放输入资源。
  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  /// 构建紧凑注册表单，协议枚举值作为代码展示。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _destination,
          decoration: InputDecoration(
            labelText: tr(
              context,
              DemoCopy.destinationEn,
              DemoCopy.destinationZh,
            ),
          ),
        ),
        DropdownButtonFormField<AckMode>(
          initialValue: _mode,
          decoration: InputDecoration(
            labelText: tr(context, 'ACK mode', '确认模式'),
          ),
          items: [
            for (final mode in AckMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.name)),
          ],
          onChanged: (value) => setState(() => _mode = value!),
        ),
        const SizedBox(height: DemoTokens.smallGap),
        FilledButton(
          onPressed: () => session.subscribe(_destination.text, _mode),
          child: Text(tr(context, 'Subscribe', DemoCopy.subscriptionsZh)),
        ),
        Text(
          tr(
            context,
            'Demo limit: ${DemoSettings.subscriptionLimit} callbacks.',
            '演示上限：${DemoSettings.subscriptionLimit} 个回调。',
          ),
        ),
      ],
    );
  }
}

/// 可取消的回调和回调外手动确认按钮。
class _Deliveries extends StatelessWidget {
  /// 创建接收面板。
  const _Deliveries();

  /// 翻译消息确认状态。
  String _status(BuildContext context, DeliveryStatus status) =>
      switch (status) {
        DeliveryStatus.waiting => tr(context, 'Waiting for a message', '等待消息'),
        DeliveryStatus.delivered => tr(context, 'Delivered', '已交付'),
        DeliveryStatus.pending => tr(context, 'Awaiting manual ACK', '等待手动确认'),
        DeliveryStatus.acked => tr(context, 'ACK requested', '已请求 ACK'),
        DeliveryStatus.nacked => tr(context, 'NACK requested', '已请求 NACK'),
      };

  /// 构建消息列表，列表增长不撑满整个页面。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SessionStatus(),
        if (!session.realMode)
          OutlinedButton(
            onPressed: session.subscriptions.isEmpty
                ? null
                : session.deliverPreview,
            child: Text(tr(context, 'Deliver preview', '投递预览消息')),
          ),
        if (session.subscriptions.isEmpty)
          Text(tr(context, 'No registered callbacks.', '暂无登记的回调。')),
        if (session.subscriptions.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView(
              children: [
                for (final entry in session.subscriptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DemoTokens.smallGap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${entry.destination} · ${entry.mode.name}'),
                        Text(
                          '${_status(context, entry.status)} · ${entry.received}',
                        ),
                        if (entry.payload.isNotEmpty)
                          Text(
                            entry.payload,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Wrap(
                          spacing: DemoTokens.smallGap,
                          children: [
                            if (entry.status == DeliveryStatus.pending) ...[
                              TextButton(
                                onPressed: () =>
                                    session.acknowledge(entry, accept: true),
                                child: const Text('ACK'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    session.acknowledge(entry, accept: false),
                                child: const Text('NACK'),
                              ),
                            ],
                            TextButton(
                              onPressed: () => session.unsubscribe(entry),
                              child: Text(tr(context, 'Unsubscribe', '取消订阅')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (session.subscriptions.isNotEmpty)
          OutlinedButton(
            onPressed: session.clearSubscriptions,
            child: Text(tr(context, 'Clear all', '全部清空')),
          ),
      ],
    );
  }
}
