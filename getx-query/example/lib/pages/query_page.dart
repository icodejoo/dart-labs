import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 查询、响应式参数与错误恢复的交互页面。
class QueryPage extends StatelessWidget {
  /// 创建查询页面。
  const QueryPage({super.key});

  /// 构建两种独立且可重放的查询状态。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'useQuery',
    description: tr(
      context,
      'Local async data, real query observers. Change a key or retry a failed request.',
      '本地异步数据，真实查询订阅。切换查询键，或重试失败请求。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Fetch & recover', '加载与恢复'),
        code:
            "final filter = 0.obs;\nfinal enabled = true.obs;\nfinal result = useQuery<List<int>>(\n  client: client,\n  queryKey: ['posts', filter],\n  queryFn: (_) => repository.load(filter.value),\n  enabled: enabled,\n  refetchOnResume: RefetchOnResume.stale,\n);\n// Render result.data / result.isFetching inside Obx.\n// Call result.dispose() when the widget is removed.",
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Reactive key', '响应式查询键'),
                description: tr(
                  context,
                  'Rx parameters switch cache entries automatically.',
                  'Rx 参数变化时自动切换缓存条目。',
                ),
                child: const QueryDemo(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Error → retry', '失败 → 重试'),
                description: tr(
                  context,
                  'The first request fails; retry succeeds. Replay starts over.',
                  '首次请求失败，重试成功；重放恢复首次请求。',
                ),
                child: const QueryDemo(failFirst: true),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Each card uses an isolated QueryClient and 600 ms local tasks. No HTTP requests. On foreground resume, each query follows its own stale / always / never policy (0.1.1).',
          '每张卡片使用独立 QueryClient 和 600 毫秒本地任务，无 HTTP 请求。恢复前台时，各查询遵循自己的 stale / always / never 策略（0.1.1）。',
        ),
      ),
    ],
  );
}

/// 演示响应式筛选和可控的首次失败。
class QueryDemo extends StatefulWidget {
  /// 首次失败模式用来展示手动重试。
  const QueryDemo({super.key, this.failFirst = false});

  /// 是否让首次请求失败。
  final bool failFirst;

  /// 创建局部订阅与筛选状态。
  @override
  State<QueryDemo> createState() => _QueryDemoState();
}

/// 管理查询结果与响应式参数，重放后从空缓存开始。
class _QueryDemoState extends DemoClientState<QueryDemo> {
  /// 筛选编号，零表示全部。
  final RxInt _filter = 0.obs;

  /// 是否自动执行查询。
  final RxBool _enabled = true.obs;

  /// 已发起的请求次数。
  int _attempts = 0;

  /// 当前查询结果。
  late final QueryResult<List<int>> _result;

  /// 挂载时订阅当前公开的命名参数 API。
  @override
  void initState() {
    super.initState();
    _result = useQuery<List<int>>(
      client: client,
      gcDuration: GcDuration.zero,
      queryKey: [postsKey, _filter],
      queryFn: _fetch,
      enabled: _enabled,
      refetchOnResume: RefetchOnResume.stale,
    );
  }

  /// 执行本地请求，捕获开始时的筛选值以模拟真实请求快照。
  Future<List<int>> _fetch(QueryFunctionContext context) async {
    final filter = _filter.value;
    final fails = widget.failFirst && _attempts++ == 0;
    await Future<void>.delayed(demoDelay);
    if (fails) throw StateError(demoFailure);
    return demoItems().where((id) => filter == 0 || id.isEven).toList();
  }

  /// 释放结果及响应式参数。
  @override
  void dispose() {
    _result.dispose();
    _filter.close();
    _enabled.close();
    super.dispose();
  }

  /// 构建紧凑控件和本地化的请求状态。
  @override
  Widget build(BuildContext context) => Obx(
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.failFirst) ...[
          Wrap(
            spacing: DemoTokens.smallGap,
            children: [
              ChoiceChip(
                label: Text(tr(context, 'All', '全部')),
                selected: _filter.value == 0,
                onSelected: (_) => _filter.value = 0,
              ),
              ChoiceChip(
                label: Text(tr(context, 'Even IDs', '偶数编号')),
                selected: _filter.value == 1,
                onSelected: (_) => _filter.value = 1,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: Text(tr(context, 'Auto fetch', '自动请求'))),
              Switch(
                value: _enabled.value,
                onChanged: (value) => _enabled.value = value,
              ),
            ],
          ),
        ],
        DemoQueryStatus(
          fetching: _result.isFetching,
          error: _result.isError,
          message: tr(
            context,
            'Loaded ${_result.data?.length ?? 0} posts',
            '已加载 ${_result.data?.length ?? 0} 篇文章',
          ),
        ),
        if (_result.data != null)
          Text(
            _result.data!
                .map((id) => itemLabel(context, id))
                .join(demoSeparator),
          ),
        const SizedBox(height: DemoTokens.smallGap),
        FilledButton.icon(
          onPressed: _result.isFetching ? null : _result.refetch,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(
            _result.isError
                ? tr(context, 'Retry', '重试')
                : tr(context, 'Refetch', '重新请求'),
          ),
        ),
      ],
    ),
  );
}
