import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import 'package:getx_query/getx_query.dart' as gq show Placeholder;
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 并行查询、合并结果和在途计数演示。
class QueriesPage extends StatelessWidget {
  /// 创建并行页面。
  const QueriesPage({super.key});

  /// 构建并行请求和真实服务注册说明。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'useQueries',
    description: tr(
      context,
      'Two observers run together; combine derives one ready count.',
      '两个订阅并行执行，通过 combine 派生就绪数量。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Parallel work', '并行任务'),
        code:
            "final (results, combined, disposeAll) = useQueries<int>(\n  [\n    QueryOptions(['users'], (_) => repository.users(),\n      placeholder: const gq.Placeholder.value(0)),\n    QueryOptions(['posts'], (_) => repository.posts()),\n  ],\n  client: client,\n  combine: (results) => results.where((r) => r.isSuccess).length,\n);\nfinal (fetching, disposeCount) = useIsFetching(client: client);\n// Read combined() and fetching.value inside Obx.\n// On removal: disposeAll(); disposeCount();",
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Two requests', '两个请求'),
                description: tr(
                  context,
                  'Watch in-flight counts and invalidate both keys.',
                  '观察在途数量，或让两个查询键同时失效。',
                ),
                child: const QueriesDemo(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: 'QueryService',
                description: tr(
                  context,
                  'For an app-wide client with reconnect support.',
                  '为应用提供支持断线重连的共享客户端。',
                ),
                replayable: false,
                child: InfoNote(
                  text: tr(
                    context,
                    'Register QueryService with Get.put, then useQueryClient() returns its client. These isolated cards inject client explicitly so Replay cannot affect a neighboring demo.',
                    '通过 Get.put 注册 QueryService，useQueryClient() 即可取得客户端。这些卡片显式注入独立 client，重放不会影响相邻演示。',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      DemoSection(
        title: tr(context, 'Application setup', '应用接入'),
        code:
            "Get.put<QueryService>(QueryService(), permanent: true);\nfinal client = useQueryClient();\n// Default: 5 min stale, 10 min GC, exponential retries.\n// Queries respect their own refetchOnResume policy.",
        child: InfoNote(
          text: tr(
            context,
            'Production apps can share a QueryService; its defaults are configurable per option.',
            '实际应用可共享 QueryService，各项默认策略可以单独配置。',
          ),
        ),
      ),
    ],
  );
}

/// 使用真实并行查询的独立卡片主体。
class QueriesDemo extends StatefulWidget {
  /// 创建并行主体。
  const QueriesDemo({super.key});

  /// 创建合并状态。
  @override
  State<QueriesDemo> createState() => _QueriesDemoState();
}

/// 管理查询集合及计数订阅。
class _QueriesDemoState extends DemoClientState<QueriesDemo> {
  /// 用户查询的缓存键。
  static const _usersKey = 'users';

  /// 两个独立查询的结果列表。
  late final List<QueryResult> _results;

  /// 计算已完成请求数的响应式读取器。
  late final int Function() _combined;

  /// 所有查询的释放回调。
  late final VoidCallback _disposeQueries;

  /// 客户端在途查询数。
  late final RxInt _fetching;

  /// 计数订阅的释放回调。
  late final VoidCallback _disposeCount;

  /// 挂载两条不同时长的查询。
  @override
  void initState() {
    super.initState();
    final (results, combined, disposeQueries) = useQueries<int>(
      [
        QueryOptions(
          [_usersKey],
          (_) async {
            await Future<void>.delayed(demoDelay);
            return demoPageSize;
          },
          gcDuration: GcDuration.zero,
          placeholder: const gq.Placeholder.value(0),
        ),
        QueryOptions([postsKey], (_) async {
          await Future<void>.delayed(demoDelay * 2);
          return demoItemCount;
        }, gcDuration: GcDuration.zero),
      ],
      client: client,
      combine: (results) => results.where((r) => r.isSuccess).length,
    );
    _results = results;
    _combined = combined;
    _disposeQueries = disposeQueries;
    final (fetching, disposeCount) = useIsFetching(client: client);
    _fetching = fetching;
    _disposeCount = disposeCount;
  }

  /// 让本卡片两条活动查询失效并重新请求。
  void _invalidate() {
    client.invalidateQueries(queryKey: [_usersKey]);
    client.invalidateQueries(queryKey: [postsKey]);
  }

  /// 释放查询和在途计数监听。
  @override
  void dispose() {
    _disposeQueries();
    _disposeCount();
    super.dispose();
  }

  /// 展示错开结束的任务、合并状态和在途数量。
  @override
  Widget build(BuildContext context) => Obx(
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DemoQueryStatus(
          fetching: _fetching.value > 0,
          error: _results.any((result) => result.isError),
          message: tr(context, 'Both ready', '全部就绪'),
        ),
        Text(
          tr(
            context,
            'Ready: ${_combined()} / 2 · Fetching: ${_fetching.value}',
            '就绪：${_combined()} / 2 · 在途：${_fetching.value}',
          ),
        ),
        const SizedBox(height: DemoTokens.smallGap),
        Text(
          tr(
            context,
            'Users: ${_results.first.data ?? demoPending}',
            '用户数：${_results.first.data ?? demoPending}',
          ),
        ),
        Text(
          tr(
            context,
            'Posts: ${_results.last.data ?? demoPending}',
            '文章数：${_results.last.data ?? demoPending}',
          ),
        ),
        const SizedBox(height: DemoTokens.smallGap),
        FilledButton(
          onPressed: _fetching.value > 0 ? null : _invalidate,
          child: Text(tr(context, 'Invalidate both', '同时失效')),
        ),
      ],
    ),
  );
}
