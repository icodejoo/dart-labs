import 'package:flutter/material.dart';
import 'package:getx_query/getx_query.dart';
import 'demo_kit/demo_kit.dart';

/// 本地异步演示延迟，便于观察加载状态。
const demoDelay = Duration(milliseconds: 600);

/// 本地数据条数，分页和删除演示共用。
const demoItemCount = 6;

/// 每页的数据条数。
const demoPageSize = 2;

/// 演示查询使用的缓存键。
const postsKey = 'posts';

/// 模拟失败的内部错误标识，界面使用双语错误文案。
const demoFailure = 'demo';

/// 数据条目之间的统一分隔符。
const demoSeparator = ' · ';

/// 资源尚未就绪时的中性占位符。
const demoPending = '…';

/// 显示本地条目的双语名称。
String itemLabel(BuildContext context, int id) =>
    tr(context, 'Post $id', '文章 $id');

/// 返回示例用的稳定编号集合。
List<int> demoItems() => List.generate(demoItemCount, (index) => index + 1);

/// 为每张卡片提供独立客户端，重放时同时销毁缓存。
abstract class DemoClientState<T extends StatefulWidget> extends State<T> {
  /// 仅执行本地任务，不依赖浏览器网络或第三方服务。
  final QueryClient client = QueryClient(
    connectivityChanges: Stream.value(true),
    defaultQueryOptions: DefaultQueryOptions(
      networkMode: NetworkMode.always,
      retry: (_, _) => null,
    ),
  );

  /// 在各子类释放订阅后清理缓存计时器。
  @override
  void dispose() {
    client.clear();
    super.dispose();
  }
}

/// 统一显示加载、失败或就绪状态，保留正文布局空间。
class DemoQueryStatus extends StatelessWidget {
  /// 创建状态行，可传入额外的成功信息。
  const DemoQueryStatus({
    super.key,
    required this.fetching,
    required this.error,
    this.message,
  });

  /// 是否正在执行异步任务。
  final bool fetching;

  /// 是否处于错误状态。
  final bool error;

  /// 成功后的可选双语消息。
  final String? message;

  /// 用图标与文本共同表达状态。
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DemoTokens.smallGap),
    child: Row(
      children: [
        if (fetching)
          SizedBox.square(
            dimension: DemoTokens.padding,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: tr(context, 'Loading', '加载中'),
            ),
          )
        else
          Icon(
            error ? Icons.error_outline : Icons.check_circle_outline,
            size: DemoTokens.padding,
          ),
        const SizedBox(width: DemoTokens.smallGap),
        Expanded(
          child: Text(
            fetching
                ? tr(context, 'Loading…', '加载中…')
                : error
                ? tr(context, 'Simulated failure', '模拟失败')
                : message ?? tr(context, 'Ready', '已就绪'),
          ),
        ),
      ],
    ),
  );
}
