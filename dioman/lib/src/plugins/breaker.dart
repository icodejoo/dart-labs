import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';

/// 熔断桶的状态。
enum DiomanBreakerState {
  /// 正常放行。
  closed,

  /// 冷却期间拒绝。
  open,

  /// 限流探测恢复。
  halfOpen,
}

/// 自定义失败计数；null 回退内置规则。
typedef DiomanShouldTrip = bool? Function(DiomanResponse<dynamic> result);

/// 经 `api.plugin<DiomanBreakerApi>()` 获取客户端熔断状态。
abstract interface class DiomanBreakerApi {
  /// 清除全部桶；旧窗口的在途结果不会写入新桶。
  void reset();

  /// 返回 key 桶当前状态；不存在时为 closed。
  DiomanBreakerState stateOf(String key);

  /// 按 [request] 生效的 keyBuilder（含请求级覆盖）返回桶键。
  /// 不建桶、不改变状态；熔断选项关闭时仍按配置计算键。
  /// 例如 `api.plugin<DiomanBreakerApi>()!.keyOf(r.request)`。
  String keyOf(DiomanRequest request);

  /// 返回 [key] 桶的 openedAt 加开启时生效的 resetDuration。
  /// 不存在或非 open 时返回 null；只读，冷却到期也不触发状态迁移。
  /// 例如 `api.plugin<DiomanBreakerApi>()!.retryableAt(api.plugin<DiomanBreakerApi>()!.keyOf(r.request))`。
  DateTime? retryableAt(String key);

  /// 返回请求当前是否会因冷却或名额不足被拒绝。
  bool isOpen(DiomanRequest request);

  /// 当前保留桶数，包含不能安全回收的桶。
  int get bucketCount;
}

/// 请求级覆盖；null 字段继承插件配置。
class DiomanBreakerOptions {
  /// 指定本次覆盖，例如 `DiomanBreakerOptions(enabled: false)`。
  const DiomanBreakerOptions(
      {this.enabled,
      this.failureThreshold,
      this.resetDuration,
      this.halfOpenMaxCalls,
      this.shouldTrip,
      this.keyBuilder});

  /// 安装或请求级开关。
  final bool? enabled;

  /// 连续失败达到此值时打开。
  final int? failureThreshold;

  /// 打开后的冷却时间。
  final Duration? resetDuration;

  /// 半开窗口最大并发探测数。
  final int? halfOpenMaxCalls;

  /// 自定义失败判定，null 回退内置规则。
  final DiomanShouldTrip? shouldTrip;

  /// 分桶键，默认 METHOD:path。
  final String Function(DiomanRequest request)? keyBuilder;
}

/// 每客户端独立的熔断桶管理。
class DiomanBreaker<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// 创建插件；请求级使用 option 键覆盖，状态由 setup 隔离。
  /// 例如 `DiomanBreaker(enabled: false)` 可关闭安装。
  const DiomanBreaker(
      {this.enabled = true,
      this.failureThreshold = defaultFailureThreshold,
      this.resetDuration = defaultResetDuration,
      this.halfOpenMaxCalls = defaultHalfOpenMaxCalls,
      this.shouldTrip,
      this.keyBuilder,
      this.idleTtl = defaultIdleTtl,
      this.maxBuckets = defaultMaxBuckets,
      this.clock,
      this.onStateChange});

  /// 安装或请求级开关。
  @override
  final bool enabled;

  /// 连续失败达到此值时打开。
  final int failureThreshold;

  /// 打开后的冷却时间。
  final Duration resetDuration;

  /// 半开窗口最大并发探测数。
  final int halfOpenMaxCalls;

  /// 自定义失败判定，null 回退内置规则。
  final DiomanShouldTrip? shouldTrip;

  /// 分桶键，默认 METHOD:path。
  final String Function(DiomanRequest request)? keyBuilder;

  /// 默认连续失败阈值。
  static const defaultFailureThreshold = 10;

  /// 默认冷却时间。
  static const defaultResetDuration = Duration(seconds: 30);

  /// 默认半开并发数。
  static const defaultHalfOpenMaxCalls = 3;

  /// 默认闲置回收时间。
  static const defaultIdleTtl = Duration(hours: 1);

  /// 默认桶软上限，安全桶不足时允许超出。
  static const defaultMaxBuckets = 1000;

  /// 闲置时间超过此值的安全桶可以删除。
  final Duration idleTtl;

  /// 桶数量软上限；只回收没有状态的安全桶。
  final int maxBuckets;

  /// 可选时钟覆盖；省略时使用客户端时钟。
  final DateTime Function()? clock;

  /// 状态迁移通知，异常隔离并记日志。
  final void Function(
          String key, DiomanBreakerState from, DiomanBreakerState to)?
      onStateChange;

  /// 稳定插件名称。
  static const pluginName = 'dioman:breaker';

  /// 请求级选项键。
  static final option = DiomanOptionKey<DiomanBreakerOptions>(pluginName);

  /// 返回固定名称。
  @override
  String get name => pluginName;

  /// 固定管线阶段。
  @override
  DiomanStage get stage => DiomanStage.attempt;

  /// 预合并配置并建立客户端独立实例。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Breaker<R>(
      this,
      DiomanBreakerOptions(
          failureThreshold: failureThreshold,
          resetDuration: resetDuration,
          halfOpenMaxCalls: halfOpenMaxCalls,
          shouldTrip: shouldTrip,
          keyBuilder: keyBuilder));
}

/// 合并请求覆盖。
DiomanBreakerOptions _merge(DiomanBreakerOptions a, DiomanBreakerOptions b) =>
    DiomanBreakerOptions(
        enabled: b.enabled,
        failureThreshold: b.failureThreshold ?? a.failureThreshold,
        resetDuration: b.resetDuration ?? a.resetDuration,
        halfOpenMaxCalls: b.halfOpenMaxCalls ?? a.halfOpenMaxCalls,
        shouldTrip: b.shouldTrip ?? a.shouldTrip,
        keyBuilder: b.keyBuilder ?? a.keyBuilder);

/// 桶状态只属于一个客户端。
class _Bucket {
  /// 初始化最后访问时间。
  _Bucket(this.lastUsed);

  /// 当前窗口状态。
  DiomanBreakerState state = DiomanBreakerState.closed;

  /// 连续失败数。
  int failures = 0;

  /// 全部在途名额。
  int inFlight = 0;

  /// 当前半开窗口的在途名额。
  int probes = 0;

  /// 状态窗口身份，隔离旧窗口的迟到结果。
  int generation = 0;

  /// 打开时间。
  DateTime? openedAt;

  /// 最近开启时生效的冷却时长。
  late Duration resetDuration;

  /// 最近访问时间。
  DateTime lastUsed;

  /// 只有无状态且没有在途请求的桶可回收。
  bool get disposable =>
      state == DiomanBreakerState.closed && inFlight == 0 && failures == 0;
}

/// 放行、结算与管理 API 共用一份桶表。
class _Breaker<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> implements DiomanBreakerApi {
  /// 保存配置。
  _Breaker(this.config, this.base);

  /// 插件配置。
  final DiomanBreaker<R> config;

  /// 预合并配置。
  final DiomanBreakerOptions base;

  /// 每键独立的窗口。
  final _buckets = <String, _Bucket>{};

  /// 从请求解析选项。
  DiomanBreakerOptions? _options(DiomanRequest r) =>
      resolveOption<DiomanBreakerOptions>(r.call.options[DiomanBreaker.option],
          base: base, merge: _merge);

  /// 计算桶键。
  String _key(DiomanRequest r, DiomanBreakerOptions o) =>
      o.keyBuilder?.call(r) ?? '${r.method.toUpperCase()}:${r.path}';

  /// 使用插件覆盖或客户端时钟。
  DateTime _now(DiomanContext<R> ctx) =>
      config.clock?.call() ?? ctx.clock.now();

  /// 保存最近的客户端时钟，供只读管理 API 使用。
  DateTime Function()? _clientNow;

  /// 当前桶数。
  @override
  int get bucketCount => _buckets.length;

  /// 清除管理表，不干扰旧请求归还它持有的名额。
  @override
  void reset() => _buckets.clear();

  /// 不触发状态变化的当前状态查询。
  @override
  DiomanBreakerState stateOf(String key) =>
      _buckets[key]?.state ?? DiomanBreakerState.closed;

  /// 只解析请求配置并计算键，不访问桶表。
  @override
  String keyOf(DiomanRequest request) =>
      _key(request, _options(request) ?? base);

  /// 只读取开启窗口保存的截止时间，不推进窗口。
  @override
  DateTime? retryableAt(String key) {
    final b = _buckets[key];
    if (b == null || b.state != DiomanBreakerState.open) return null;
    return b.openedAt!.add(b.resetDuration);
  }

  /// 不申请名额，返回请求当前是否会被拒绝。
  @override
  bool isOpen(DiomanRequest request) {
    final o = _options(request);
    if (o == null || o.enabled == false) return false;
    final b = _buckets[_key(request, o)];
    if (b == null) return false;
    if (b.state == DiomanBreakerState.halfOpen) {
      return b.probes >= o.halfOpenMaxCalls!;
    }
    if (b.state != DiomanBreakerState.open) return false;
    return (config.clock ?? _clientNow!)().difference(b.openedAt!) <
        o.resetDuration!;
  }

  /// 改变窗口身份后安全通知。
  void _transition(
      DiomanContext<R> ctx, String key, _Bucket b, DiomanBreakerState to) {
    final from = b.state;
    b.state = to;
    b.generation++;
    b.probes = 0;
    try {
      config.onStateChange?.call(key, from, to);
    } catch (e, s) {
      ctx.client.logError('[${DiomanBreaker.pluginName}] 状态通知失败: $e\n$s');
    }
  }

  /// 惰性删除安全桶，状态桶不受软上限强制淘汰。
  void _collect(DateTime now) {
    _buckets.removeWhere(
        (_, b) => b.disposable && now.difference(b.lastUsed) > config.idleTtl);
    final excess = _buckets.length - config.maxBuckets + 1;
    if (excess <= 0) return;
    final victims = _buckets.entries.where((e) => e.value.disposable).toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final e in victims.take(excess)) {
      _buckets.remove(e.key);
    }
  }

  /// 一次实际放行对应一次结算；取消只归还名额。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = _options(ctx.request);
    if (o == null || o.enabled == false) return next();
    _clientNow = ctx.clock.now;
    final key = _key(ctx.request, o);
    final now = _now(ctx);
    var b = _buckets[key];
    if (b == null) {
      _collect(now);
      b = _buckets[key] = _Bucket(now);
    }
    b.lastUsed = now;
    if (b.state == DiomanBreakerState.open &&
        now.difference(b.openedAt!) >= o.resetDuration!) {
      _transition(ctx, key, b, DiomanBreakerState.halfOpen);
    }
    if (b.state == DiomanBreakerState.open ||
        b.state == DiomanBreakerState.halfOpen &&
            b.probes >= o.halfOpenMaxCalls!) {
      return ctx
          .fail(const DiomanFailure(kind: DiomanKind.breaker, reason: 'open'));
    }
    final generation = b.generation;
    final probe = b.state == DiomanBreakerState.halfOpen;
    b.inFlight++;
    if (probe) b.probes++;
    final r = await next();
    final cancelled = ctx.cancelled();
    b.inFlight--;
    if (generation != b.generation) {
      return r.kind == DiomanKind.internal ? r : cancelled ?? r;
    }
    if (probe) b.probes--;
    if (r.kind == DiomanKind.internal) return r;
    if (cancelled != null || r.kind == DiomanKind.cancel) return cancelled ?? r;
    final failed = o.shouldTrip?.call(r) ??
        (r.kind == DiomanKind.network ||
            r.kind == DiomanKind.timeout ||
            r.status >= 500 ||
            r.status == 429);
    if (failed) {
      b.failures++;
      if (probe || b.failures >= o.failureThreshold!) {
        b.openedAt = _now(ctx);
        b.resetDuration = o.resetDuration!;
        _transition(ctx, key, b, DiomanBreakerState.open);
      }
    } else {
      b.failures = 0;
      if (probe) _transition(ctx, key, b, DiomanBreakerState.closed);
    }
    return r;
  }

  /// 释放管理表；在途闭包仍能安全归还自己的桶名额。
  @override
  void dispose() => _buckets.clear();
}
