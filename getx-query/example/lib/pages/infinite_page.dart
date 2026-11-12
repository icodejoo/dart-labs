import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 加载更多的英文标签。
const _loadMoreEn = 'Load more';

/// 加载更多的中文标签。
const _loadMoreZh = '加载更多';

/// 当前无限查询 API 的有限数据集演示。
class InfinitePage extends StatelessWidget {
  /// 创建分页页面。
  const InfinitePage({super.key});

  /// 构建可重放分页和边界说明。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: 'useInfiniteQuery',
    description: tr(
      context,
      'Accumulate three local pages, two posts at a time.',
      '每次加载两篇文章，累积三页本地数据。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Page accumulation', '分页累积'),
        code:
            "final feed = useInfiniteQuery<List<int>, int>(\n  client: client,\n  queryKey: ['posts'],\n  initialPageParam: 1,\n  queryFn: (context) => repository.page(context.pageParam),\n  nextPageParamBuilder: (data) => data.pages.length < 3\n      ? data.pages.length + 1 : null,\n);\nfeed.fetchNextPage();\n// Read feed.pages and feed.hasNextPage inside Obx.\n// Call feed.dispose() when removed.",
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: tr(context, _loadMoreEn, _loadMoreZh),
                description: tr(
                  context,
                  'Replay discards all pages and fetches page one.',
                  '重放清空所有页，再从第一页加载。',
                ),
                child: const InfiniteDemo(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'A finite feed', '有边界的数据流'),
                description: tr(
                  context,
                  'Stop when nextPageParamBuilder returns null.',
                  'nextPageParamBuilder 返回 null 时停止。',
                ),
                replayable: false,
                child: InfoNote(
                  text: tr(
                    context,
                    'hasNextPage disables the button at the end. isFetchingNextPage distinguishes pagination from a background refetch.',
                    '到达末页后 hasNextPage 禁用按钮；isFetchingNextPage 用于区分翻页和后台重新请求。',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// 持有无限查询的可重挂载主体。
class InfiniteDemo extends StatefulWidget {
  /// 创建分页主体。
  const InfiniteDemo({super.key});

  /// 创建分页状态。
  @override
  State<InfiniteDemo> createState() => _InfiniteDemoState();
}

/// 管理页累积和客户端资源。
class _InfiniteDemoState extends DemoClientState<InfiniteDemo> {
  /// 当前分页结果。
  late final InfiniteQueryResult<List<int>, int> _feed;

  /// 挂载分页订阅并声明有限末页。
  @override
  void initState() {
    super.initState();
    _feed = useInfiniteQuery<List<int>, int>(
      client: client,
      gcDuration: GcDuration.zero,
      queryKey: [postsKey],
      initialPageParam: 1,
      queryFn: (context) async {
        final page = context.pageParam;
        await Future<void>.delayed(demoDelay);
        return demoItems()
            .skip((page - 1) * demoPageSize)
            .take(demoPageSize)
            .toList();
      },
      nextPageParamBuilder: (data) =>
          data.pages.length < demoItemCount ~/ demoPageSize
          ? data.pages.length + 1
          : null,
    );
  }

  /// 先释放订阅，再清空客户端。
  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  /// 显示页数、累积内容与翻页状态。
  @override
  Widget build(BuildContext context) => Obx(
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DemoQueryStatus(
          fetching: _feed.isFetching,
          error: _feed.isError,
          message: tr(
            context,
            'Pages: ${_feed.pages.length}',
            '已加载页数：${_feed.pages.length}',
          ),
        ),
        for (final page in _feed.pages)
          Padding(
            padding: const EdgeInsets.only(bottom: DemoTokens.smallGap),
            child: Text(
              page.map((id) => itemLabel(context, id)).join(demoSeparator),
            ),
          ),
        FilledButton(
          onPressed: _feed.isFetching || !_feed.hasNextPage
              ? null
              : _feed.fetchNextPage,
          child: Text(
            _feed.hasNextPage
                ? tr(context, _loadMoreEn, _loadMoreZh)
                : tr(context, 'End of feed', '已到末页'),
          ),
        ),
      ],
    ),
  );
}
