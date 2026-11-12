import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:getx_query/getx_query.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// ViewModel 自动释放与轻量作用域的并列示例。
class ViewModelPage extends StatelessWidget {
  /// 创建生命周期页面。
  const ViewModelPage({super.key});

  /// 构建两种生命周期所有权的交互示例。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Lifecycle ownership', '生命周期归属'),
    description: tr(
      context,
      'Let a GetX controller or a QueryScope own subscriptions.',
      '让 GetX 控制器或 QueryScope 管理订阅的创建与释放。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Automatic cleanup', '自动清理'),
        code:
            "class PostsViewModel extends GetBaseViewModel {\n  PostsViewModel(QueryClient client) : super(client: client);\n  late final QueryResult<List<int>> posts;\n  @override\n  void onInit() {\n    super.onInit();\n    posts = this.useQuery<List<int>>(\n      queryKey: ['posts'], queryFn: (_) => repository.posts(),\n    );\n  }\n}\n// Get.put registers; Get.delete calls onClose and disposes tracked hooks.\n\nfinal scope = QueryScope(client: client);\nfinal posts = scope.watch<List<int>>(\n  queryKey: ['posts'], queryFn: (_) => repository.posts(),\n);\n// scope.dispose() releases every watched query.",
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: 'GetBaseViewModel',
                description: tr(
                  context,
                  'Delete locally, invalidate, then reload the list.',
                  '本地删除后失效查询，重新加载列表。',
                ),
                child: const ViewModelDemo(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: 'QueryScope',
                description: tr(
                  context,
                  'Group subscriptions without a controller.',
                  '无需控制器，将多条订阅统一释放。',
                ),
                child: const ScopeDemo(),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Replay disposes the old controller or scope, clears its private cache and mounts a fresh instance. BaseViewModel supports constructor injection with manual init/dispose.',
          '重放会释放旧控制器或作用域、清空独立缓存，再挂载新实例。BaseViewModel 也支持构造注入，由调用方手动 init/dispose。',
        ),
      ),
    ],
  );
}

/// 管理本地文章列表并自动跟踪查询及变更。
class PostsViewModel extends GetBaseViewModel {
  /// 注入独立客户端，避免全局服务耦合。
  PostsViewModel(QueryClient client) : super(client: client);

  /// 模拟服务端持久化的本地数据。
  final List<int> _items = demoItems();

  /// 自动释放的查询结果。
  late final QueryResult<List<int>> posts;

  /// 自动释放的删除结果。
  late final MutationResult<int, int> deletePost;

  /// 创建真实的查询、变更和失效回调。
  @override
  void onInit() {
    super.onInit();
    posts = this.useQuery<List<int>>(
      gcDuration: GcDuration.zero,
      queryKey: [postsKey],
      queryFn: (_) async {
        await Future<void>.delayed(demoDelay);
        return List<int>.of(_items);
      },
    );
    deletePost = this.useMutation<int, int>((id, _) async {
      await Future<void>.delayed(demoDelay);
      _items.remove(id);
      return id;
    }, onSuccess: (_, _, _, _) => invalidateQueries(queryKey: [postsKey]));
  }
}

/// 在卡片挂载期间注册一个 GetX 控制器。
class ViewModelDemo extends StatefulWidget {
  /// 创建控制器演示主体。
  const ViewModelDemo({super.key});

  /// 创建控制器所有者。
  @override
  State<ViewModelDemo> createState() => _ViewModelDemoState();
}

/// 以唯一 tag 隔离新旧重放代次的控制器。
class _ViewModelDemoState extends DemoClientState<ViewModelDemo> {
  /// 当前代次的注册标识。
  final String _tag = UniqueKey().toString();

  /// 当前自动释放模型。
  late final PostsViewModel _vm;

  /// 注册并初始化模型。
  @override
  void initState() {
    super.initState();
    _vm = Get.put(PostsViewModel(client), tag: _tag);
  }

  /// 触发 onClose 清理模型跟踪的所有订阅。
  @override
  void dispose() {
    Get.delete<PostsViewModel>(tag: _tag);
    super.dispose();
  }

  /// 将删除反馈直接呈现在卡片中，不创建遮挡页面的弹层。
  @override
  Widget build(BuildContext context) => Obx(
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DemoQueryStatus(
          fetching: _vm.posts.isFetching || _vm.deletePost.isPending,
          error: _vm.posts.isError || _vm.deletePost.isError,
          message: _vm.deletePost.isSuccess
              ? tr(
                  context,
                  'Deleted post ${_vm.deletePost.data}',
                  '已删除文章 ${_vm.deletePost.data}',
                )
              : null,
        ),
        Text(
          (_vm.posts.data ?? [])
              .map((id) => itemLabel(context, id))
              .join(demoSeparator),
        ),
        const SizedBox(height: DemoTokens.smallGap),
        FilledButton.icon(
          onPressed:
              _vm.posts.isFetching ||
                  _vm.deletePost.isPending ||
                  (_vm.posts.data?.isEmpty ?? true)
              ? null
              : () => _vm.deletePost.mutate(_vm.posts.data!.first),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr(context, 'Delete first', '删除首篇')),
        ),
      ],
    ),
  );
}

/// 展示不依赖完整模型的订阅分组。
class ScopeDemo extends StatefulWidget {
  /// 创建作用域示例。
  const ScopeDemo({super.key});

  /// 创建作用域所有者。
  @override
  State<ScopeDemo> createState() => _ScopeDemoState();
}

/// 在挂载与移除之间管理轻量作用域。
class _ScopeDemoState extends DemoClientState<ScopeDemo> {
  /// 本卡片的查询作用域。
  late final QueryScope _scope;

  /// 作用域跟踪的结果。
  late final QueryResult<int> _count;

  /// 模拟服务端版本。
  int _revision = 0;

  /// 通过作用域挂载查询。
  @override
  void initState() {
    super.initState();
    _scope = QueryScope(client: client);
    _count = _scope.watch<int>(
      gcDuration: GcDuration.zero,
      queryKey: [postsKey],
      queryFn: (_) async {
        await Future<void>.delayed(demoDelay);
        return ++_revision;
      },
    );
  }

  /// 统一释放作用域内的查询。
  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  /// 显示重新请求后递增的版本号。
  @override
  Widget build(BuildContext context) => Obx(
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DemoQueryStatus(
          fetching: _count.isFetching,
          error: _count.isError,
          message: tr(
            context,
            'Revision: ${_count.data ?? 0}',
            '数据版本：${_count.data ?? 0}',
          ),
        ),
        FilledButton(
          onPressed: _count.isFetching
              ? null
              : () => _scope.invalidateQueries(queryKey: [postsKey]),
          child: Text(tr(context, 'Invalidate scope', '失效作用域查询')),
        ),
      ],
    ),
  );
}
