import 'dart:async';
import 'dart:math';
import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../response.dart';
import '../stages.dart';

/// 返回布尔采用自定义规则；null 回退默认规则。
typedef DiomanShouldRetry = bool? Function(
    DiomanResponse<dynamic> result, int attempt);

/// 计算第 attempt 次重试的退避，max 为重试上限。
typedef DiomanRetryDelay = Duration Function(
    int attempt, int max, DiomanResponse<dynamic> result);

/// 对计算后的退避施加抖动，负值表示沿用原值。
typedef DiomanJitter = Duration Function(Duration delay);

/// 请求级覆盖；null 字段继承插件配置。
class DiomanRetryOptions {
  /// 指定本次覆盖，例如 `DiomanRetryOptions(enabled: false)`。
  const DiomanRetryOptions(
      {this.enabled,
      this.max,
      this.methods,
      this.statusCodes,
      this.shouldRetry,
      this.delay,
      this.jitter,
      this.delayMax,
      this.respectRetryAfter,
      this.afterStatusCodes,
      this.retryAfterMax,
      this.onRetry});

  /// 安装或请求级开关。
  final bool? enabled;

  /// 最多重试次数；非正数只发送一次。
  final int? max;

  /// 允许重试的方法，忽略大小写，优先于自定义规则。
  final List<String>? methods;

  /// 触发重试的逻辑状态表。
  final List<int>? statusCodes;

  /// 自定义判定；null 回退默认规则，也接收成功响应。
  final DiomanShouldRetry? shouldRetry;

  /// 退避计算，参数为当前重试序号、上限与结果。
  final DiomanRetryDelay? delay;

  /// true 随机抖动，或 DiomanJitter 函数。
  final Object? jitter;

  /// 抖动后的退避上限；null 不封顶。
  final Duration? delayMax;

  /// 优先遵守 Retry-After。
  final bool? respectRetryAfter;

  /// 接受 Retry-After 的逻辑状态。
  final List<int>? afterStatusCodes;

  /// 服务器等待时间上限；不受 delayMax 限制。
  final Duration? retryAfterMax;

  /// 重试通知；抛错隔离并记日志。
  final void Function(int attempt)? onRetry;
}

/// 重发内层管线，每次尝试重新经过熔断与鉴权。
class DiomanRetry<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// 创建插件；请求级使用 option 键覆盖，状态由 setup 隔离。
  /// 例如 `DiomanRetry(enabled: false)` 可关闭安装。
  const DiomanRetry(
      {this.enabled = true,
      this.max = 0,
      this.methods = defaultMethods,
      this.statusCodes = defaultStatusCodes,
      this.shouldRetry,
      this.delay = defaultDelay,
      this.jitter,
      this.delayMax,
      this.respectRetryAfter = true,
      this.afterStatusCodes = defaultAfterStatusCodes,
      this.retryAfterMax = const Duration(seconds: 60),
      this.onRetry});

  /// 安装或请求级开关。
  @override
  final bool enabled;

  /// 最多重试次数；非正数只发送一次。
  final int max;

  /// 允许重试的方法，忽略大小写，优先于自定义规则。
  final List<String> methods;

  /// 触发重试的逻辑状态表。
  final List<int> statusCodes;

  /// 自定义判定；null 回退默认规则，也接收成功响应。
  final DiomanShouldRetry? shouldRetry;

  /// 退避计算，参数为当前重试序号、上限与结果。
  final DiomanRetryDelay delay;

  /// true 随机抖动，或 DiomanJitter 函数。
  final Object? jitter;

  /// 抖动后的退避上限；null 不封顶。
  final Duration? delayMax;

  /// 优先遵守 Retry-After。
  final bool respectRetryAfter;

  /// 接受 Retry-After 的逻辑状态。
  final List<int> afterStatusCodes;

  /// 服务器等待时间上限；不受 delayMax 限制。
  final Duration retryAfterMax;

  /// 重试通知；抛错隔离并记日志。
  final void Function(int attempt)? onRetry;

  /// 默认幂等方法白名单。
  static const defaultMethods = [
    'GET',
    'PUT',
    'HEAD',
    'DELETE',
    'OPTIONS',
    'TRACE'
  ];

  /// 默认逻辑失败状态。
  static const defaultStatusCodes = [408, 429, 500, 502, 503, 504];

  /// 默认接受服务器退避的状态。
  static const defaultAfterStatusCodes = [413, 429, 503];

  /// 默认固定三秒退避。
  static Duration defaultDelay(
          int attempt, int max, DiomanResponse<dynamic> result) =>
      const Duration(seconds: 3);

  /// 稳定插件名称。
  static const pluginName = 'dioman:retry';

  /// 请求级选项键。
  static final option = DiomanOptionKey<DiomanRetryOptions>(pluginName);

  /// 返回固定名称。
  @override
  String get name => pluginName;

  /// 固定管线阶段。
  @override
  DiomanStage get stage => DiomanStage.attempt;

  /// 预合并配置并建立客户端独立实例。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Retry<R>(
      this,
      DiomanRetryOptions(
          max: max,
          methods: methods,
          statusCodes: statusCodes,
          shouldRetry: shouldRetry,
          delay: delay,
          jitter: jitter,
          delayMax: delayMax,
          respectRetryAfter: respectRetryAfter,
          afterStatusCodes: afterStatusCodes,
          retryAfterMax: retryAfterMax,
          onRetry: onRetry));
}

/// 合并请求覆盖。
DiomanRetryOptions _merge(DiomanRetryOptions a, DiomanRetryOptions b) =>
    DiomanRetryOptions(
        enabled: b.enabled,
        max: b.max ?? a.max,
        methods: b.methods ?? a.methods,
        statusCodes: b.statusCodes ?? a.statusCodes,
        shouldRetry: b.shouldRetry ?? a.shouldRetry,
        delay: b.delay ?? a.delay,
        jitter: b.jitter ?? a.jitter,
        delayMax: b.delayMax ?? a.delayMax,
        respectRetryAfter: b.respectRetryAfter ?? a.respectRetryAfter,
        afterStatusCodes: b.afterStatusCodes ?? a.afterStatusCodes,
        retryAfterMax: b.retryAfterMax ?? a.retryAfterMax,
        onRetry: b.onRetry ?? a.onRetry);

/// 每客户端的退避与随机源。
class _Retry<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> {
  /// 保存预合并配置。
  _Retry(this.config, this.base);

  /// 插件配置。
  final DiomanRetry<R> config;

  /// 预合并配置。
  final DiomanRetryOptions base;

  /// 随机抖动源。
  final _random = Random();

  /// 不接受重试的失败类别。
  static const _veto = {
    DiomanKind.cancel,
    DiomanKind.auth,
    DiomanKind.internal,
    DiomanKind.parse,
    DiomanKind.breaker,
    DiomanKind.offline
  };

  /// RFC1123 日期模式。
  static final _httpDate =
      RegExp(r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$');

  /// HTTP 日期月份。
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  /// 统一裁剪负数与可选上限。
  Duration _cap(Duration value, Duration? cap) => value.isNegative
      ? Duration.zero
      : cap != null && value > cap
          ? cap
          : value;

  /// 严格按类别、自定义、网络、逻辑状态的顺序判定。
  bool _retry(DiomanRetryOptions o, DiomanResponse<dynamic> r, int attempt) {
    if (_veto.contains(r.kind)) return false;
    final custom = o.shouldRetry?.call(r, attempt);
    if (custom != null) return custom;
    return r.kind == DiomanKind.network ||
        r.kind == DiomanKind.timeout ||
        o.statusCodes!.contains(r.status);
  }

  /// 解析服务器秒数或 HTTP 日期；无效值回退普通退避。
  Duration? _after(
      DiomanContext<R> ctx, DiomanRetryOptions o, DiomanResponse<dynamic> r) {
    if (!o.respectRetryAfter! || !o.afterStatusCodes!.contains(r.status)) {
      return null;
    }
    final raw = r.raw?.headers.value('retry-after')?.trim();
    if (raw == null) return null;
    final seconds = raw.isEmpty ? 0 : num.tryParse(raw);
    if (seconds != null && seconds.isFinite) {
      return _cap(Duration(milliseconds: (seconds * 1000).round()), null);
    }
    final m = _httpDate.firstMatch(raw);
    if (m == null) return null;
    final month = _months.indexOf(m[2]!);
    if (month < 0) return null;
    final date = DateTime.utc(int.parse(m[3]!), month + 1, int.parse(m[1]!),
        int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
    return _cap(date.difference(ctx.clock.now().toUtc()), null);
  }

  /// 服务器退避优先；普通退避施加抖动后封顶。
  Duration _delay(DiomanContext<R> ctx, DiomanRetryOptions o,
      DiomanResponse<dynamic> r, int attempt) {
    final after = _after(ctx, o, r);
    if (after != null) return after;
    final raw = o.delay!(attempt, o.max!, r);
    var value = raw;
    final jitter = o.jitter;
    if (jitter == true) {
      value = Duration(
          microseconds: (raw.inMicroseconds * _random.nextDouble()).round());
    } else if (jitter is DiomanJitter) {
      final changed = jitter(raw);
      if (!changed.isNegative) value = changed;
    }
    return _cap(value, o.delayMax);
  }

  /// 从相同基准重发，只恢复本层实际放行的请求。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = resolveOption<DiomanRetryOptions>(
        ctx.request.call.options[DiomanRetry.option],
        base: base,
        merge: _merge,
        shorthand: (v) => v is int ? DiomanRetryOptions(max: v) : null);
    if (o == null || o.enabled == false) return next();
    ctx.markReplayable();
    if (!o.methods!
        .map((m) => m.toUpperCase())
        .contains(ctx.request.method.toUpperCase())) {
      return next();
    }
    var r = await next();
    var cancelled = ctx.cancelled();
    if (r.kind == DiomanKind.internal) return r;
    if (cancelled != null) return cancelled;
    for (var attempt = 1;
        attempt <= o.max! && _retry(o, r, attempt);
        attempt++) {
      if (!ctx.canReplay()) return r;
      final after = _after(ctx, o, r);
      if (after != null && after > o.retryAfterMax!) return r;
      final duration = _delay(ctx, o, r, attempt);
      // ctx.wait 自己拥有计时器，取消时即释放，无额外退避资源。
      await ctx.wait<void>(Completer<void>().future, timeout: duration);
      cancelled = ctx.cancelled();
      if (cancelled != null) return cancelled;
      try {
        o.onRetry?.call(attempt);
      } catch (e, s) {
        ctx.client.logError('[${DiomanRetry.pluginName}] 重试通知失败: $e\n$s');
      }
      cancelled = ctx.cancelled();
      if (cancelled != null) return cancelled;
      r = await next();
      cancelled = ctx.cancelled();
      if (r.kind == DiomanKind.internal) return r;
      if (cancelled != null) return cancelled;
    }
    return r;
  }
}
