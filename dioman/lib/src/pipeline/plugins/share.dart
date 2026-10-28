import 'dart:async';
import 'package:dio/dio.dart';
import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';
import 'mock.dart';

/// 同 key 并发结果归属策略；关闭使用请求级 false。
enum DiomanSharePolicy {
  /// 首发共享一次传输。
  start,

  /// 最新发起的结果胜出。
  end,

  /// 首个成功胜出，全部失败取最后一个。
  race,

  /// 首发在内部重试，共享最终结果。
  retry,
}

/// 共享活动表诊断；例如 `api.plugin<DiomanShareApi>()!.activeEntries`。
abstract interface class DiomanShareApi {
  /// 四种策略当前活动轮次总数，结束或销毁后为零。
  int get activeEntries;
}

/// 请求级共享配置；null 字段沿用插件配置。
class DiomanShareOptions {
  /// 例如 `DiomanShareOptions(policy: DiomanSharePolicy.race)`。
  const DiomanShareOptions(
      {this.enabled, this.policy, this.retries, this.interval, this.methods});

  /// 本次开关。
  final bool? enabled;

  /// 归属策略。
  final DiomanSharePolicy? policy;

  /// 内部重试次数。
  final int? retries;

  /// 内部重试间隔。
  final Duration? interval;

  /// 允许共享的方法。
  final Set<String>? methods;
}

/// 请求级开启的共享插件；跟随者得到同一个只读结果。
class DiomanShare<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// 默认 start、GET/HEAD；例如调用选项 `{DiomanShare.option: true}`。
  const DiomanShare(
      {this.policy = DiomanSharePolicy.start,
      this.retries = 3,
      this.interval = Duration.zero,
      this.methods = sourceSafeMethods,
      this.enabled = true});

  /// 默认策略。
  final DiomanSharePolicy policy;

  /// retry 策略的额外次数。
  final int retries;

  /// retry 策略的等待间隔。
  final Duration interval;

  /// 方法硬白名单。
  final Set<String> methods;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 稳定名称。
  static const pluginName = 'dioman:share';

  /// 请求级 bool、策略枚举或配置键。
  static final option = DiomanOptionKey<DiomanShareOptions>(pluginName);

  /// 名称。
  @override
  String get name => pluginName;

  /// 结果来源阶段。
  @override
  DiomanStage get stage => DiomanStage.source;

  /// 每客户端独立建表。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) =>
      _Share<R>(DiomanShareOptions(
          policy: policy,
          retries: retries,
          interval: interval,
          methods: Set.of(methods)));
}

/// 一轮共享，不含逻辑请求的结算登记。
class _Shared {
  /// 保留与客户端工厂一致的销毁结果。
  _Shared(this.cancelled);

  /// 销毁时发布给尚在等待的订阅者。
  final DiomanResponse<dynamic> cancelled;

  /// 共享结果。
  final result = Completer<DiomanResponse<dynamic>>();

  /// 首发或 retry 的独立传输令牌。
  final token = CancelToken();

  /// 共享传输使用独立令牌并关闭 Dio 阶段超时，由订阅者各自限时。
  RequestPatch get transportPatch => RequestPatch(
      cancelToken: token,
      connectTimeout: Duration.zero,
      receiveTimeout: Duration.zero,
      sendTimeout: Duration.zero);

  /// 订阅者数。
  int subscribers = 0;

  /// 发起序号。
  int sequence = 0;

  /// 未结束的传输数。
  int pending = 0;
}

/// 每客户端按策略隔离的活动表。
class _Share<R extends DiomanResponse<dynamic>> extends DiomanPluginInstance<R>
    implements DiomanShareApi {
  /// 保存配置。
  _Share(this.base);

  /// 预合并配置。
  final DiomanShareOptions base;

  /// 每种策略一张表。
  final tables = {
    for (final p in DiomanSharePolicy.values) p: <String, _Shared>{}
  };

  /// 活动轮次总数。
  @override
  int get activeEntries =>
      tables.values.fold(0, (n, table) => n + table.length);

  /// 仅移除仍属于本轮的条目。
  void detach(Map<String, _Shared> table, String key, _Shared entry) {
    if (identical(table[key], entry)) table.remove(key);
  }

  /// 结果发布前先摘表，外层 retry 可立即重新入表。
  void finish(Map<String, _Shared> table, String key, _Shared entry,
      DiomanResponse<dynamic> r) {
    if (entry.result.isCompleted) return;
    detach(table, key, entry);
    entry.result.complete(r);
  }

  /// 订阅者整体上限为连接与接收之和；有请求体时再加发送阶段。
  /// 任一参与阶段为 null 或非正数时不限时，不模拟 Dio 的阶段进度。
  Duration? timeout(DiomanRequest request) {
    var total = Duration.zero;
    for (final stage in [
      request.connectTimeout,
      request.receiveTimeout,
      if (request.data != null) request.sendTimeout
    ]) {
      if (stage == null || stage <= Duration.zero) return null;
      total += stage;
    }
    return total;
  }

  /// 首发传输脱离首发调用方，最后一个订阅者离开才取消。
  Future<void> run(
      DiomanContext<R> ctx,
      DiomanNext<R> next,
      DiomanShareOptions o,
      Map<String, _Shared> table,
      String key,
      _Shared entry) async {
    final shared = ctx.derive(entry.transportPatch);
    ctx.state.retain();
    try {
      var r = await next(entry.transportPatch);
      if (o.policy == DiomanSharePolicy.retry) {
        for (var i = 0;
            i < o.retries! &&
                !r.ok &&
                r.kind != DiomanKind.internal &&
                !shared.isCancelled;
            i++) {
          if (o.interval! > Duration.zero) {
            await shared.wait(Completer<void>().future, timeout: o.interval);
          }
          if (shared.isCancelled) break;
          r = await next(entry.transportPatch);
        }
      }
      finish(table, key, entry, r);
    } catch (error, stack) {
      finish(
          table,
          key,
          entry,
          ctx.fail(DiomanFailure(
              kind: DiomanKind.internal, error: error, errorStack: stack)));
    } finally {
      ctx.state.release();
    }
  }

  /// end/race 的底层请求各自独立，订阅者离开不会取消其它传输。
  Future<void> compete(
      DiomanContext<R> ctx,
      DiomanNext<R> next,
      DiomanShareOptions o,
      Map<String, _Shared> table,
      String key,
      _Shared entry) async {
    final sequence = ++entry.sequence;
    entry.pending++;
    ctx.state.retain();
    try {
      final r = await next();
      entry.pending--;
      if (o.policy == DiomanSharePolicy.end
          ? sequence == entry.sequence
          : r.ok || entry.pending == 0) {
        finish(table, key, entry, r);
      }
    } finally {
      ctx.state.release();
    }
  }

  /// 解析 optIn 后订阅；wait 自行清理取消监听和计时器。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = resolveOption<DiomanShareOptions>(
        ctx.request.call.options[DiomanShare.option],
        base: base,
        optIn: true,
        shorthand: (v) =>
            v is DiomanSharePolicy ? DiomanShareOptions(policy: v) : null,
        merge: (a, b) => DiomanShareOptions(
            enabled: b.enabled,
            policy: b.policy ?? a.policy,
            retries: b.retries ?? a.retries,
            interval: b.interval ?? a.interval,
            methods: b.methods ?? a.methods));
    if (o == null ||
        o.enabled == false ||
        ctx.get(sourceProbe) == true ||
        !o.methods!.contains(ctx.request.method)) {
      return next();
    }
    final cancel = ctx.cancelled();
    if (cancel != null) return cancel;
    final key = ctx.key();
    if (key == null) return next();
    final table = tables[o.policy]!;
    final existing = table[key];
    final entry = existing ??
        (table[key] =
            _Shared(ctx.fail(const DiomanFailure(kind: DiomanKind.cancel))));
    final shared = o.policy == DiomanSharePolicy.start ||
        o.policy == DiomanSharePolicy.retry;
    entry.subscribers++;
    if (shared) {
      if (existing == null) {
        if (o.policy == DiomanSharePolicy.retry) ctx.markReplayable();
        unawaited(run(ctx, next, o, table, key, entry));
      }
    } else {
      unawaited(compete(ctx, next, o, table, key, entry));
    }
    try {
      final r =
          await ctx.wait(entry.result.future, timeout: timeout(ctx.request));
      return ctx.cancelled() ??
          r ??
          ctx.fail(const DiomanFailure(kind: DiomanKind.timeout));
    } finally {
      if (--entry.subscribers == 0) {
        detach(table, key, entry);
        if (shared && !entry.result.isCompleted) entry.token.cancel();
      }
    }
  }

  /// 清空所有策略表并取消共享底层传输。
  @override
  void dispose() {
    for (final table in tables.values) {
      for (final entry in table.values) {
        entry.token.cancel();
        if (!entry.result.isCompleted) entry.result.complete(entry.cancelled);
      }
      table.clear();
    }
  }
}
