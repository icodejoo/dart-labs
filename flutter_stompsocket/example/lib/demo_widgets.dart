import 'package:flutter/material.dart';

import 'demo_kit/demo_kit.dart';
import 'demo_session.dart';
import 'demo_settings.dart';

/// 跨页共用的双语文案，导航、页面标题与表单复用同一份常量。
abstract final class DemoCopy {
  /// 连接页面的英文标题。
  static const connectionEn = 'Connection';

  /// 连接页面及动作的中文名称。
  static const connectionZh = '连接';

  /// 连接按钮的英文文案。
  static const connectEn = 'Connect';

  /// 订阅页面的英文标题。
  static const subscriptionsEn = 'Subscriptions';

  /// 订阅页面及动作的中文名称。
  static const subscriptionsZh = '订阅';

  /// 发送页面的英文标题。
  static const sendEn = 'Send & buffer';

  /// 发送页面的中文标题。
  static const sendZh = '发送与缓冲';

  /// 配置页面的英文标题。
  static const referenceEn = 'API reference';

  /// 配置页面的中文标题。
  static const referenceZh = '配置参考';

  /// 目的地输入的英文标签。
  static const destinationEn = 'Destination';

  /// 目的地输入的中文标签。
  static const destinationZh = '目的地';
}

/// 显示当前模式与连接状态，保留文字以免只靠颜色识别。
class SessionStatus extends StatelessWidget {
  /// 创建跨页状态条。
  const SessionStatus({super.key});

  /// 根据会话变化更新双语状态。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    return Wrap(
      spacing: DemoTokens.smallGap,
      runSpacing: DemoTokens.smallGap,
      children: [
        Chip(
          label: Text(
            session.realMode
                ? tr(context, 'Real broker', '真实 broker')
                : tr(context, 'Offline preview', '离线预览'),
          ),
        ),
        Chip(label: Text(session.stateLabel(context))),
      ],
    );
  }
}

/// 合并原来三页重复的日志面板；重放清空外部日志状态。
class SessionLog extends StatelessWidget {
  /// 创建占整行的紧凑日志卡片。
  const SessionLog({super.key});

  /// 呈现最近事件，切换语言后同时翻译历史说明。
  @override
  Widget build(BuildContext context) {
    final session = DemoSessionScope.of(context);
    return DemoCard(
      title: tr(context, 'Session log', '会话日志'),
      description: tr(
        context,
        'Last ${DemoSettings.logLimit} events. Replay clears the log.',
        '最近 ${DemoSettings.logLimit} 条事件；重放清空日志。',
      ),
      onReplay: session.clearLog,
      child: SizedBox(
        width: double.infinity,
        height: 140,
        child: session.events.isEmpty
            ? Text(
                tr(
                  context,
                  'No events yet. Try an action above.',
                  '暂无事件，试试上方操作。',
                ),
              )
            : ListView.separated(
                itemCount: session.events.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: DemoTokens.smallGap),
                itemBuilder: (context, index) {
                  final event = session.events[index];
                  return Text(
                    '${tr(context, event.en, event.zh)}${event.data.isEmpty ? '' : '\n${event.data}'}',
                    style: const TextStyle(fontSize: DemoTokens.captionSize),
                  );
                },
              ),
      ),
    );
  }
}
