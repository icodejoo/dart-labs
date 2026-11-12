import 'dart:async';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'scenario_runtime.dart';
import 'scenarios.dart';

/// 将一组场景显示为响应式网格和整行折叠代码。
class ScenarioPage extends StatelessWidget {
  /// 创建指定分组的演示页面。
  const ScenarioPage({super.key, required this.group});

  /// 当前导航分组。
  final DemoGroup group;

  /// 构建首屏可操作的网格及共享使用说明。
  @override
  Widget build(BuildContext context) => DemoPage(
        title: group.title.resolve(context),
        description: group.description.resolve(context),
        sections: [
          DemoSection(
            title: tr(context, 'Live scenarios', '交互演示'),
            code: group.scenarios
                .map((s) => '// ${s.title.en}\n${s.code}')
                .join('\n\n'),
            child: DemoGrid(children: [
              for (final scenario in group.scenarios)
                DemoGridItem(
                    child: DemoCard(
                  key: ValueKey(scenario.id),
                  title: scenario.title.resolve(context),
                  description: scenario.description.resolve(context),
                  replayable: scenario.replayable,
                  child: ScenarioView(scenario: scenario),
                )),
            ]),
          ),
          InfoNote(
              text: tr(
                  context,
                  'Each replay creates a fresh client. Logs translate live; API names and payloads stay unchanged. Snippets assume a configured api; always await api.dispose() and close the Dio you own.',
                  '每次重放都创建新客户端；日志随语言切换，API 名称和载荷保持原样。代码片段假设已有配置好的 api；结束后须 await api.dispose() 并关闭自己持有的 Dio。')),
        ],
      );
}

/// 自动执行一轮演示，由 DemoCard 重新挂载实现真正重放。
class ScenarioView extends StatefulWidget {
  /// 创建独立执行与日志主体。
  const ScenarioView({super.key, required this.scenario});

  /// 当前执行场景。
  final DemoScenario scenario;

  /// 创建本轮运行状态。
  @override
  State<ScenarioView> createState() => _ScenarioViewState();
}

/// 将双语日志和资源绑定到卡片挂载周期。
class _ScenarioViewState extends State<ScenarioView> {
  /// 当前日志，不在切换语言时丢失。
  final List<DemoText> _logs = [];

  /// 本轮会话，销毁时立即取消。
  late final DemoSession _session;

  /// 是否仍在执行演示。
  bool _running = true;

  /// 是否发生非预期错误。
  bool _failed = false;

  /// 挂载后执行，避开构建期的日志通知。
  @override
  void initState() {
    super.initState();
    _session = DemoSession(_emit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  /// 接收当前轮日志，忽略销毁后的异步输出。
  void _emit(DemoText text) {
    if (mounted) setState(() => _logs.add(text));
  }

  /// 执行并确保异常和正常结束都释放客户端。
  Future<void> _run() async {
    try {
      await widget.scenario.run(_session);
    } catch (error) {
      if (mounted) {
        _failed = true;
        _session.log('Unexpected demo error', '演示发生非预期错误', error);
      }
    } finally {
      await _session.close();
      if (mounted) setState(() => _running = false);
    }
  }

  /// 重放或离页时取消旧轮，防止迟到日志污染新卡片。
  @override
  void dispose() {
    unawaited(_session.close());
    super.dispose();
  }

  /// 构建紧凑状态和独立滚动的日志面板。
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(
                _running
                    ? Icons.hourglass_top_rounded
                    : _failed
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                size: 18,
                color: _failed
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary),
            const SizedBox(width: DemoTokens.smallGap),
            Text(_running
                ? tr(context, 'Running', '运行中')
                : _failed
                    ? tr(context, 'Failed', '失败')
                    : tr(context, 'Completed', '已完成')),
          ]),
          const SizedBox(height: DemoTokens.smallGap),
          SizedBox(
              height: 108,
              child: SingleChildScrollView(
                key: ValueKey('log-${widget.scenario.id}'),
                child: Text(
                    _logs.map((line) => line.resolve(context)).join('\n'),
                    style: const TextStyle(
                        fontSize: DemoTokens.captionSize, height: 1.4)),
              )),
        ]),
      );
}
