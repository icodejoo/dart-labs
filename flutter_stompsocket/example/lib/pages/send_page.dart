import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../demo_kit/demo_kit.dart';
import '../demo_session.dart';
import '../demo_settings.dart';
import '../demo_widgets.dart';

/// 当前 send 支持的四种载荷类别。
enum SendBodyKind {
  /// 原始文本。
  text,

  /// 任意合法 JSON 值。
  json,

  /// 不发送消息体。
  empty,

  /// UTF-8 编码的二进制内容。
  binary,
}

/// 发送编码与离线缓冲演示。
class SendPage extends StatelessWidget {
  /// 创建发送页。
  const SendPage({super.key});

  /// 展示实际支持的载荷与停止后发送行为。
  static const _code =
      '''socket.send('${DemoSettings.destination}', body: 'hello');
socket.send('${DemoSettings.destination}', body: {'message': 'hello'});
socket.send('${DemoSettings.destination}', body: [1, 2, 3]);
socket.send('${DemoSettings.destination}', body: Uint8List.fromList([1, 2, 3]));
socket.send('${DemoSettings.destination}');
socket.dispose(keepSubscriptions: true);
socket.send('${DemoSettings.destination}', body: 'queued while stopped');
socket.activate();''';

  /// 构建可操作编辑器、缓冲状态与静态编码说明。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    return DemoPage(
      title: tr(context, DemoCopy.sendEn, DemoCopy.sendZh),
      description: tr(
        context,
        'Try each body type and send while disconnected.',
        '尝试不同消息体，并在断开期间发送。',
      ),
      sections: [
        DemoSection(
          title: tr(context, 'Compose a message', '编写消息'),
          code: _code,
          child: DemoGrid(
            children: [
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Send message', '发送消息'),
                  description: tr(
                    context,
                    'Replay resets the form and starts a fresh session.',
                    '重放恢复表单并创建全新会话。',
                  ),
                  onReplay: session.reset,
                  child: const _SendEditor(),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Offline buffer', '离线缓冲'),
                  description: tr(
                    context,
                    'Replay discards the entire old session, including its outbox.',
                    '重放销毁整个旧会话，包括待发缓冲。',
                  ),
                  onReplay: session.reset,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SessionStatus(),
                      Text(
                        tr(
                          context,
                          'Send attempts: ${session.sendAttempts}',
                          '发送请求：${session.sendAttempts} 次',
                        ),
                      ),
                      const SizedBox(height: DemoTokens.smallGap),
                      Text(
                        session.realMode
                            ? tr(
                                context,
                                'The library exposes no queue count. Offline sends still call socket.send().',
                                '库没有公开缓冲计数；离线期间仍会调用 socket.send()。',
                              )
                            : tr(
                                context,
                                'Preview queued: ${session.previewQueued}',
                                '预览待发：${session.previewQueued} 条',
                              ),
                      ),
                      Text(
                        tr(
                          context,
                          'Default capacity: ${DemoSettings.queueLimit}. Oldest is dropped when full; non-positive capacity disables buffering.',
                          '默认容量 ${DemoSettings.queueLimit} 条，满后丢最旧；非正容量关闭缓冲。',
                        ),
                      ),
                      if (!session.realMode)
                        FilledButton(
                          onPressed: () =>
                              session.connect(DemoSettings.brokerUrl),
                          child: Text(
                            tr(context, 'Connect & flush preview', '连接并补发预览'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Body encoding', '消息体编码'),
                  description: tr(
                    context,
                    'Transport data is shown as code, without translation.',
                    '传输数据作为代码展示，不翻译。',
                  ),
                  replayable: false,
                  child: Text(
                    tr(
                      context,
                      'String: unchanged. Map/List and other non-string JSON values: JSON encoding with application/json. Uint8List: binary bytes. null: no body. A JSON string uses the String path; JSON null uses the no-body path.',
                      'String 原样发送；Map/List 等非字符串 JSON 值自动编码并添加 application/json；Uint8List 发送二进制；null 不带消息体。JSON 字符串走 String 路径，JSON null 走无消息体路径。',
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
            'True queuing is owned by the library. dispose retains the outbox; creating a new instance discards it. A send request is not a delivery receipt.',
            '真实缓冲由库管理。dispose 保留待发队列，创建新实例才丢弃；发送请求不等于投递回执。',
          ),
        ),
        const SessionLog(),
      ],
    );
  }
}

/// 发送表单的局部状态，重放会重新挂载并恢复默认值。
class _SendEditor extends StatefulWidget {
  /// 创建消息编辑器。
  const _SendEditor();

  /// 创建输入控制器。
  @override
  State<_SendEditor> createState() => _SendEditorState();
}

/// 验证 JSON 并将所有受支持的类型交给真实 send API。
class _SendEditorState extends State<_SendEditor> {
  /// 发送目的地。
  final _destination = TextEditingController(text: DemoSettings.destination);

  /// 原始消息输入。
  final _body = TextEditingController(text: DemoSettings.jsonBody);

  /// 选择的载荷类别。
  SendBodyKind _kind = SendBodyKind.json;

  /// 是否显示 JSON 格式错误。
  bool _invalid = false;

  /// 翻译类别标签。
  String _label(BuildContext context, SendBodyKind kind) => switch (kind) {
    SendBodyKind.text => tr(context, 'Text', '文本'),
    SendBodyKind.json => 'JSON',
    SendBodyKind.empty => tr(context, 'No body', '无消息体'),
    SendBodyKind.binary => tr(context, 'Binary (UTF-8)', '二进制（UTF-8）'),
  };

  /// 解析成功后再发送，格式错误时保留输入并显示双语提示。
  void _send() {
    Object? body;
    try {
      body = switch (_kind) {
        SendBodyKind.text => _body.text,
        SendBodyKind.json => jsonDecode(_body.text),
        SendBodyKind.empty => null,
        SendBodyKind.binary => Uint8List.fromList(utf8.encode(_body.text)),
      };
    } on FormatException {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    DemoSessionScope.of(context).send(_destination.text, body);
  }

  /// 释放输入资源。
  @override
  void dispose() {
    _destination.dispose();
    _body.dispose();
    super.dispose();
  }

  /// 构建带就地错误提示的紧凑表单。
  @override
  Widget build(BuildContext context) => Column(
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
      DropdownButtonFormField<SendBodyKind>(
        initialValue: _kind,
        decoration: InputDecoration(
          labelText: tr(context, 'Body type', '消息体类型'),
        ),
        items: [
          for (final kind in SendBodyKind.values)
            DropdownMenuItem(value: kind, child: Text(_label(context, kind))),
        ],
        onChanged: (value) => setState(() {
          _kind = value!;
          _invalid = false;
        }),
      ),
      if (_kind != SendBodyKind.empty)
        TextField(
          key: const ValueKey('send-body'),
          controller: _body,
          minLines: 1,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: tr(context, 'Body', '消息体'),
            errorText: _invalid
                ? tr(context, 'Enter valid JSON.', '请输入合法 JSON。')
                : null,
          ),
        ),
      const SizedBox(height: DemoTokens.smallGap),
      FilledButton(onPressed: _send, child: Text(tr(context, 'Send', '发送'))),
    ],
  );
}
