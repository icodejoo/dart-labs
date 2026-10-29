import 'package:dio/dio.dart';
import '../cache_store.dart';
import '../client.dart';
import '../clock.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';
import 'mock.dart';

part 'cache_internal.dart';

/// 响应数据的克隆策略；也可直接提供自定义函数。
enum DiomanClonePolicy {
  /// 返回只读引用。
  none,

  /// 复制顶层 Map/List。
  shallow,

  /// 递归复制 Map/List。
  deep,
}

/// 缓存存储层；关闭缓存使用请求级 false。
enum DiomanCachePolicy {
  /// 仅内存。
  memo,

  /// 仅持久化。
  persist,

  /// 两层，持久化命中后提升到内存。
  both,
}

/// 请求级缓存覆盖；null 字段沿用插件级值。
class DiomanCacheOptions {
  /// 例如 `DiomanCacheOptions(expires: Duration(seconds: 10))`。
  const DiomanCacheOptions(
      {this.enabled,
      this.expires,
      this.clone,
      this.shouldCache,
      this.shouldStore,
      this.cachePolicy});

  /// 本次开关。
  final bool? enabled;

  /// 有效期，非正数表示立即过期。
  final Duration? expires;

  /// DiomanClonePolicy 或 Object? Function(Object?)。
  final Object? clone;

  /// 请求缓存判定；抛错按 bug 处理。
  final bool Function(DiomanRequest)? shouldCache;

  /// 结果写入判定；默认 r.ok，抛错按 bug 处理。
  final bool Function(DiomanResponse<dynamic>)? shouldStore;

  /// 存储层覆盖。
  final DiomanCachePolicy? cachePolicy;
}

/// 缓存管理能力；通过 `api.plugin<DiomanCacheApi>()` 获取。
abstract interface class DiomanCacheApi {
  /// 删除 [key] 并作废该键在途写入；等待持久化删除完成。
  Future<void> remove(String key);

  /// 清空缓存并立即作废所有在途写入；返回持久化清理完成信号。
  Future<void> clear();
}

/// 按请求开启的缓存；命中不触网，业务失败默认不存储。
class DiomanCache<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// 默认 memo、一分钟、浅克隆、GET/HEAD；例如选项 `{DiomanCache.option: true}`。
  const DiomanCache(
      {this.persist,
      this.maxEntries = 500,
      this.cachePolicy = DiomanCachePolicy.memo,
      this.expires = const Duration(minutes: 1),
      this.clone = DiomanClonePolicy.shallow,
      this.clock,
      this.shouldCache,
      this.shouldStore,
      this.enabled = true});

  /// 内存 LRU 上限，非正数不限；请求级不支持覆盖。
  final int maxEntries;

  /// 可选持久化存储；persist/both 策略要求提供。
  final DiomanCachePersist? persist;

  /// 默认存储层。
  final DiomanCachePolicy cachePolicy;

  /// 默认有效期。
  final Duration expires;

  /// 默认克隆策略或自定义函数。
  final Object clone;

  /// 默认请求判定，缺省 GET/HEAD。
  final bool Function(DiomanRequest)? shouldCache;

  /// 默认写入判定，缺省 r.ok。
  final bool Function(DiomanResponse<dynamic>)? shouldStore;

  /// 可选 TTL 时钟；默认客户端 DiomanClock，请求级不支持覆盖。
  final DiomanClock? clock;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 稳定名称。
  static const pluginName = 'dioman:cache';

  /// 请求级 bool、Duration 或配置键。
  static final option = DiomanOptionKey<DiomanCacheOptions>(pluginName);

  /// 名称。
  @override
  String get name => pluginName;

  /// 结果来源阶段。
  @override
  DiomanStage get stage => DiomanStage.source;

  /// 状态按客户端隔离，时钟统一使用客户端时钟。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Cache<R>(
      persist,
      maxEntries,
      clock ?? client.clock,
      DiomanCacheOptions(
          cachePolicy: cachePolicy,
          expires: expires,
          clone: clone,
          shouldCache: shouldCache,
          shouldStore: shouldStore));
}

/// 内存缓存条目。
class _Entry {
  /// 保存响应及绝对到期时刻。
  _Entry(this.response, this.expiresAt);

  /// 来源响应。
  final DiomanResponse<dynamic> response;

  /// epoch 毫秒。
  final int expiresAt;
}

/// 在途期间的已写入顺序屏障。
class _Barrier {
  /// 当前在途数量。
  int pending = 0;

  /// 已发布的最大序号。
  int latest = 0;
}

/// 每客户端内存和串行持久化通道。
class _Cache<R extends DiomanResponse<dynamic>> extends DiomanPluginInstance<R>
    implements DiomanCacheApi {
  /// 保存存储与配置。
  _Cache(this.persist, this.maxEntries, this.clock, this.base);

  /// TTL 时钟。
  final DiomanClock clock;

  /// 内存容量。
  final int maxEntries;

  /// 外部持久化后端。
  final DiomanCachePersist? persist;

  /// 基础选项。
  final DiomanCacheOptions base;

  /// 内存条目。
  final entries = <String, _Entry>{};

  /// 只在在途期间存在的屏障。
  final barriers = <String, _Barrier>{};

  /// 单调请求序号。
  int sequence = 0;

  /// 最近 clear 的失效下界。
  int floor = 0;

  /// 所有落盘变更串行，clear 不会被旧 write 越过。
  Future<void> tail = Future<void>.value();

  /// 数据字段名，兼容旧存储。
  static const dataField = 'data';

  /// 到期字段名。
  static const expiresField = 'expiresAt';

  /// 新格式保存归一化元信息，旧格式仍按原始 HTTP 200 读取。
  static const resultField = 'result';

  /// 结果类别字段。
  static const kindField = 'kind';

  /// 逻辑状态字段。
  static const statusField = 'status';

  /// 原始 HTTP 状态字段。
  static const httpField = 'httpStatus';

  /// 业务码字段。
  static const codeField = 'code';

  /// 消息字段。
  static const messageField = 'message';

  /// 细分原因字段。
  static const reasonField = 'reason';

  /// 从新格式恢复归一化结果，老格式继续交给工厂识别信封。
  DiomanResponse<dynamic> restore(DiomanContext<R> ctx, Map saved) {
    final meta = saved[resultField];
    if (meta is! Map) {
      return ctx.factory.normalize(ctx.request,
          raw: Response<dynamic>(
              requestOptions: ctx.request.toRequestOptions(),
              statusCode: 200,
              data: saved[dataField]));
    }
    final kind = DiomanKind.values.byName(meta[kindField] as String);
    final init = DiomanResponse<dynamic>(
        ok: kind == DiomanKind.ok,
        kind: kind,
        status: meta[statusField] as int,
        httpStatus: meta[httpField] as int,
        code: meta[codeField],
        message: meta[messageField] as String,
        reason: meta[reasonField] as String?,
        data: meta[dataField],
        request: ctx.request);
    return ctx.factory.derive(init, init.data);
  }

  /// 写入并按最近使用顺序淘汰，屏障不随淘汰删除。
  void put(String key, _Entry entry) {
    entries.remove(key);
    entries[key] = entry;
    if (maxEntries > 0) {
      while (entries.length > maxEntries) {
        entries.remove(entries.keys.first);
      }
    }
  }

  /// 入队持久化变更；异常交给调用方，同时保持通道可继续使用。
  Future<void> enqueue(Future<void> Function() action) {
    final pending = tail.then((_) => action());
    tail = pending.then((_) {}, onError: (Object _, StackTrace __) {});
    return pending;
  }

  /// 删除也抬高本键屏障，阻止旧响应复活。
  @override
  Future<void> remove(String key) {
    entries.remove(key);
    barriers[key]?.latest = ++sequence;
    return persist == null
        ? Future<void>.value()
        : enqueue(() => persist!.remove(key));
  }

  /// 同步失效，随后串行清理后端。
  @override
  Future<void> clear() {
    floor = sequence;
    entries.clear();
    return persist == null
        ? Future<void>.value()
        : enqueue(() => persist!.erase());
  }

  /// 递归复制 Map/List；其余载荷按引用保留。
  Object? deep(Object? data) {
    if (data is Map) return data.map((k, v) => MapEntry(k, deep(v)));
    if (data is List) return data.map(deep).toList();
    return data;
  }

  /// 数据副本经扩展工厂创建，保留所有响应元信息。
  DiomanResponse<dynamic> clone(
      DiomanContext<R> ctx, DiomanResponse<dynamic> r, Object strategy) {
    if (strategy == DiomanClonePolicy.none) return r;
    final data = r.data;
    Object? copied;
    if (strategy is Object? Function(Object?)) {
      copied = strategy(data);
    } else if (strategy == DiomanClonePolicy.deep) {
      copied = deep(data);
    } else if (strategy == DiomanClonePolicy.shallow) {
      copied = data is Map
          ? Map.of(data)
          : data is List
              ? List.of(data)
              : data;
    } else {
      throw ArgumentError.value(strategy, 'clone');
    }
    return ctx.factory.derive(r, copied);
  }

  /// 查缓存、登记屏障、只写入仍新鲜的结果，并在 finally 回收。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = resolveOption<DiomanCacheOptions>(
        ctx.request.call.options[DiomanCache.option],
        base: base,
        optIn: true,
        shorthand: (v) => v is Duration ? DiomanCacheOptions(expires: v) : null,
        merge: (a, b) => DiomanCacheOptions(
            enabled: b.enabled,
            expires: b.expires ?? a.expires,
            clone: b.clone ?? a.clone,
            shouldCache: b.shouldCache ?? a.shouldCache,
            shouldStore: b.shouldStore ?? a.shouldStore,
            cachePolicy: b.cachePolicy ?? a.cachePolicy));
    if (o == null || o.enabled == false || ctx.get(sourceProbe) == true) {
      return next();
    }
    if (!(o.shouldCache?.call(ctx.request) ??
        sourceSafeMethods.contains(ctx.request.method))) {
      return next();
    }
    final key = ctx.key();
    if (key == null) return next();
    final memo = o.cachePolicy != DiomanCachePolicy.persist;
    final disk = o.cachePolicy != DiomanCachePolicy.memo;
    if (disk && persist == null) throw StateError('persist/both 策略需要 persist');
    final barrier = barriers.putIfAbsent(key, _Barrier.new);
    barrier.pending++;
    final ticket = ++sequence;
    bool valid() => ticket > floor && ticket > barrier.latest;
    try {
      var hit = memo ? entries[key] : null;
      if (hit != null && hit.expiresAt <= clock.now().millisecondsSinceEpoch) {
        entries.remove(key);
        hit = null;
      }
      if (hit == null && disk) {
        await ctx.wait(tail);
        final cancel = ctx.cancelled();
        if (cancel != null) return cancel;
        final saved = await ctx.wait(Future.sync(() => persist!.read(key)));
        final cancelled = ctx.cancelled();
        if (cancelled != null) return cancelled;
        if (saved is Map && saved[expiresField] is int) {
          final expiry = saved[expiresField] as int;
          if (expiry > clock.now().millisecondsSinceEpoch && valid()) {
            hit = _Entry(restore(ctx, saved), expiry);
            if (memo) put(key, hit);
          } else {
            await ctx.wait(enqueue(() async {
              if (valid()) await persist!.remove(key);
            }));
            final cancel = ctx.cancelled();
            if (cancel != null) return cancel;
          }
        }
      }
      if (hit != null) {
        if (memo) put(key, hit);
        return clone(ctx, hit.response, o.clone!);
      }
      final r = await next();
      final cancel = ctx.cancelled();
      if (cancel != null) return cancel;
      var stored = false;
      if (valid() && (o.shouldStore?.call(r) ?? r.ok)) {
        stored = true;
        barrier.latest = ticket;
        final entry = _Entry(clone(ctx, r, o.clone!),
            clock.now().add(o.expires!).millisecondsSinceEpoch);
        if (memo) put(key, entry);
        if (disk) {
          await ctx.wait(enqueue(() => persist!.write(key, {
                dataField: r.raw?.data ?? r.data,
                expiresField: entry.expiresAt,
                resultField: {
                  kindField: r.kind.name,
                  statusField: r.status,
                  httpField: r.httpStatus,
                  codeField: r.code,
                  messageField: r.message,
                  reasonField: r.reason,
                  dataField: entry.response.data
                }
              })));
          final cancel = ctx.cancelled();
          if (cancel != null) return cancel;
        }
      }
      return r.ok || stored ? clone(ctx, r, o.clone!) : r;
    } finally {
      if (--barrier.pending == 0) barriers.remove(key);
    }
  }

  /// 作废在途写入并清空自有内存，外部持久化后端不归插件销毁。
  @override
  void dispose() {
    floor = sequence;
    entries.clear();
  }
}
