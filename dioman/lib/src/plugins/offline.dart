import 'dart:async';
import 'dart:collection';
import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';

/// 销毁出口的稳定原因。
const _disposedReason = 'disposed';

/// 队列满的稳定原因。
const _queueFullReason = 'queueFull';

/// 等待超时的稳定原因。
const _timeoutReason = 'timeout';

/// 所有销毁出口使用同一个离线失败值。
const _disposedFailure =
    DiomanFailure(kind: DiomanKind.offline, reason: _disposedReason);

/// 离线请求级配置；省略字段沿用插件级值。
class DiomanOfflineOptions {
  /// 例如 `DiomanOfflineOptions(maxWait: Duration(seconds: 10))`。
  const DiomanOfflineOptions(
      {this.enabled, this.shouldQueue, this.maxQueueSize, this.maxWait});

  /// 本次开关。
  final bool? enabled;

  /// 是否排队；false 直接放行，异常按 bug 处理。
  final bool Function(DiomanRequest)? shouldQueue;

  /// 入队时上限，0 表示不限。
  final int? maxQueueSize;

  /// 最长排队时间，null 沿用默认值。
  final Duration? maxWait;
}

/// 通过 `api.plugin<DiomanOfflineApi>()` 获取离线管理能力。
abstract interface class DiomanOfflineApi {
  /// 当前排队数。
  int get pending;

  /// 立即恢复全部排队请求，不重复查询在线状态。
  void flush();
}

/// source 最内层的离线队列；缓存命中时不会到达这里。
class DiomanOffline<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// 宿主提供 [isOnline] 与连通流；默认最多排队 50 条，例如恢复时流发送 true。
  const DiomanOffline(
      {required this.isOnline,
      required this.onConnectivityChanged,
      this.shouldQueue,
      this.maxQueueSize = defaultMaxQueueSize,
      this.maxWait,
      this.enabled = true});

  /// 在线状态判定；异常按 bug 处理。
  final bool Function() isOnline;

  /// true 事件自动 flush；流错误隔离并记日志。
  final Stream<bool> onConnectivityChanged;

  /// 默认全部排队，false 放行。
  final bool Function(DiomanRequest)? shouldQueue;

  /// 队列上限，非正数不限；满时挤出最早条目。
  final int maxQueueSize;

  /// 默认无最长等待。
  final Duration? maxWait;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 默认上限。
  static const defaultMaxQueueSize = 50;

  /// 稳定名称。
  static const pluginName = 'dioman:offline';

  /// 请求级 bool 或配置键。
  static final option = DiomanOptionKey<DiomanOfflineOptions>(pluginName);

  /// 名称。
  @override
  String get name => pluginName;

  /// 来源阶段最内层。
  @override
  DiomanStage get stage => DiomanStage.source;

  /// 每客户端独立队列和流订阅。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Offline<R>(this, client);
}

/// 队列条目，null 信号表示恢复，其余为离线失败原因。
class _Queued {
  /// 恰好完成一次的出队信号。
  final ready = Completer<String?>();
}

/// 客户端专属 FIFO 队列。
class _Offline<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> implements DiomanOfflineApi {
  /// 订阅宿主连通流，流错误归通知类隔离。
  _Offline(this.config, Dioman<R> client) {
    subscription = config.onConnectivityChanged.listen((online) {
      if (online) flush();
    }, onError: (Object error, StackTrace stack) {
      client.logError('[offline] 连通通知失败: $error');
    });
    base = DiomanOfflineOptions(
        shouldQueue: config.shouldQueue,
        maxQueueSize: config.maxQueueSize,
        maxWait: config.maxWait);
  }

  /// 安装配置。
  final DiomanOffline<R> config;

  /// 预合并请求默认值。
  late final DiomanOfflineOptions base;

  /// 宿主订阅。
  late final StreamSubscription<bool> subscription;

  /// 按入队顺序排列。
  final queue = ListQueue<_Queued>();

  /// 是否已释放，dispose 的原因优先于客户端同时发出的取消。
  bool disposed = false;

  /// 当前排队数量。
  @override
  int get pending => queue.length;

  /// 清队列后发信号，保证重入安全。
  void drain(String? reason) {
    final entries = queue.toList();
    queue.clear();
    for (final entry in entries) {
      entry.ready.complete(reason);
    }
  }

  /// 手动或流通知恢复。
  @override
  void flush() => drain(null);

  /// 离线等待统一使用 ctx.wait，finally 摘掉队列条目。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = resolveOption<DiomanOfflineOptions>(
        ctx.request.call.options[DiomanOffline.option],
        base: base,
        merge: (a, b) => DiomanOfflineOptions(
            enabled: b.enabled,
            shouldQueue: b.shouldQueue ?? a.shouldQueue,
            maxQueueSize: b.maxQueueSize ?? a.maxQueueSize,
            maxWait: b.maxWait ?? a.maxWait));
    if (o == null ||
        o.enabled == false ||
        config.isOnline() ||
        !(o.shouldQueue?.call(ctx.request) ?? true)) {
      return next();
    }
    if (disposed) {
      ctx.set(cancellationFailure, _disposedFailure);
      return ctx.fail(_disposedFailure);
    }
    final cancel = ctx.cancelled();
    if (cancel != null) return cancel;
    final max = o.maxQueueSize!;
    if (max > 0) {
      while (queue.length >= max) {
        queue.removeFirst().ready.complete(_queueFullReason);
      }
    }
    final entry = _Queued();
    queue.add(entry);
    try {
      final ready = await ctx.wait(
          entry.ready.future.then((reason) => (reason,)),
          timeout: o.maxWait);
      if (disposed) {
        ctx.set(cancellationFailure, _disposedFailure);
        return ctx.fail(_disposedFailure);
      }
      final cancel = ctx.cancelled();
      if (cancel != null) return cancel;
      if (ready == null) {
        return ctx.fail(const DiomanFailure(
            kind: DiomanKind.offline, reason: _timeoutReason));
      }
      final reason = ready.$1;
      return reason == null
          ? await next()
          : ctx.fail(DiomanFailure(kind: DiomanKind.offline, reason: reason));
    } finally {
      queue.remove(entry);
    }
  }

  /// 排队请求以 disposed 结束，退订宿主流。
  @override
  void dispose() {
    disposed = true;
    unawaited(subscription.cancel());
    drain(_disposedReason);
  }
}
