import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 展示命令式变更及错误反馈。
class MutationPage extends StatelessWidget {
  /// 创建变更页面。
  const MutationPage({super.key});

  /// 构建成功和失败两种变更卡片。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'useMutation',
    description: tr(
      context,
      'Submit a local post and inspect idle → pending → success / error.',
      '提交本地文章，观察空闲 → 提交中 → 成功或失败。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Explicit writes', '显式提交'),
        code:
            "final create = useMutation<String, String>(\n  (title, context) => repository.create(title),\n  client: client,\n  onSuccess: (data, variables, onMutateResult, context) {\n    client.invalidateQueries(queryKey: ['posts']);\n  },\n);\ncreate.mutate('Hello');\n// Observe create.isPending / isSuccess / isError in Obx.\ncreate.reset(); // idle\n// Call create.dispose() when removed.",
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Create a post', '创建文章'),
                description: tr(
                  context,
                  'Submit a title; reset returns the result to idle.',
                  '输入标题并提交，重置让结果回到空闲。',
                ),
                child: const MutationDemo(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Handle an error', '处理错误'),
                description: tr(
                  context,
                  'A controlled failure preserves your input.',
                  '可控失败保留输入，便于检查错误反馈。',
                ),
                child: const MutationDemo(fail: true),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Writes are in memory. Replay clears the form and result. The Lifecycle page demonstrates a write followed by query invalidation.',
          '提交仅保存在内存。重放清空表单和结果；生命周期页演示变更后失效并重新加载查询。',
        ),
      ),
    ],
  );
}

/// 由局部状态管理的变更表单。
class MutationDemo extends StatefulWidget {
  /// 可选择固定失败场景。
  const MutationDemo({super.key, this.fail = false});

  /// 是否模拟提交失败。
  final bool fail;

  /// 创建表单和变更订阅。
  @override
  State<MutationDemo> createState() => _MutationDemoState();
}

/// 管理输入和可重置的变更结果。
class _MutationDemoState extends DemoClientState<MutationDemo> {
  /// 文章标题输入控制器。
  final TextEditingController _title = TextEditingController();

  /// 当前变更订阅。
  late final MutationResult<String, String> _create;

  /// 挂载变更函数。
  @override
  void initState() {
    super.initState();
    _create = useMutation<String, String>((title, _) async {
      await Future<void>.delayed(demoDelay);
      if (widget.fail) throw StateError(demoFailure);
      return title;
    }, client: client);
  }

  /// 提交非空标题。
  void _submit() {
    final title = _title.text.trim();
    if (title.isNotEmpty) _create.mutate(title);
  }

  /// 释放输入和订阅。
  @override
  void dispose() {
    _create.dispose();
    _title.dispose();
    super.dispose();
  }

  /// 显示提交按钮、输入约束和状态。
  @override
  Widget build(BuildContext context) => Obx(
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          decoration: InputDecoration(
            labelText: tr(context, 'Post title', '文章标题'),
            helperText: tr(context, 'Required · local data only', '必填 · 仅本地数据'),
            border: const OutlineInputBorder(),
          ),
        ),
        DemoQueryStatus(
          fetching: _create.isPending,
          error: _create.isError,
          message: _create.isIdle
              ? tr(context, 'Idle', '空闲')
              : tr(context, 'Created: ${_create.data}', '已创建：${_create.data}'),
        ),
        Wrap(
          spacing: DemoTokens.smallGap,
          runSpacing: DemoTokens.smallGap,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _title,
              builder: (context, value, _) => FilledButton(
                onPressed: _create.isPending || value.text.trim().isEmpty
                    ? null
                    : _submit,
                child: Text(tr(context, 'Submit', '提交')),
              ),
            ),
            OutlinedButton(
              onPressed: _create.isIdle || _create.isPending
                  ? null
                  : _create.reset,
              child: Text(tr(context, 'Reset', '重置')),
            ),
          ],
        ),
      ],
    ),
  );
}
