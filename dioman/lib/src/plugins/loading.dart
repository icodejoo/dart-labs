import 'dart:async';
import '../client.dart';
import '../clock.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../response.dart';
import '../stages.dart';

/// loading 请求级覆盖；null 字段继承插件配置。
class DiomanLoadingOptions {
  /// [onChanged] 按回调身份独立计数；[delay] 与 [delayClose] 控制边沿延迟。
  const DiomanLoadingOptions(
      {this.enabled, this.onChanged, this.delay, this.delayClose});

  /// false 不计入本次 loading。
  final bool? enabled;

  /// 本次显示回调。
  final void Function(bool visible)? onChanged;

  /// 0→1 延迟显示。
  final Duration? delay;

  /// 1→0 延迟隐藏。
  final Duration? delayClose;
}

/// 通过 `api.plugin<DiomanLoadingApi>()` 获取的管理接口。
abstract class DiomanLoadingApi {
  /// 当前参与 loading 的逻辑请求数，dispose 后为零。
  int get activeCount;
}

/// 按回调身份管理逻辑请求显示周期，内层重发不重复计数。
class DiomanLoading<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// [onChanged] 必填，例如 `DiomanLoading(onChanged: (visible) => print(visible))`。
  /// 延迟默认为零；通知抛错会隔离并记日志。
  const DiomanLoading(
      {required this.onChanged,
      this.delay = Duration.zero,
      this.delayClose = Duration.zero,
      this.enabled = true});

  /// 显示回调。
  final void Function(bool visible) onChanged;

  /// 显示延迟。
  final Duration delay;

  /// 关闭延迟。
  final Duration delayClose;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 稳定名称。
  static const pluginName = 'dioman:loading';

  /// 请求级 bool 或 DiomanLoadingOptions 键。
  static final option = DiomanOptionKey<DiomanLoadingOptions>(pluginName);

  /// 返回稳定名称。
  @override
  String get name => pluginName;

  /// 最外层逻辑请求阶段。
  @override
  DiomanStage get stage => DiomanStage.outer;

  /// 建立独立计数器与时钟。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Loading<R>(
      client.clock,
      DiomanLoadingOptions(
          onChanged: onChanged, delay: delay, delayClose: delayClose));
}

/// 一个回调的显示状态。
class _Display {
  /// 初始状态为未显示、无请求。
  _Display(this.log);

  /// 对应客户端的隔离日志器。
  final DiomanLogger log;

  /// 在途计数。
  int count = 0;

  /// 是否已发出 true。
  bool shown = false;

  /// 待触发的边沿定时器。
  Timer? timer;
}

/// 每客户端的计数与管理 API。
class _Loading<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> implements DiomanLoadingApi {
  /// 保存时钟和预合并配置。
  _Loading(this.clock, this.base);

  /// 时间服务。
  final DiomanClock clock;

  /// 基础配置。
  final DiomanLoadingOptions base;

  /// 回调身份独立状态。
  final states = Map<void Function(bool), _Display>.identity();

  /// 是否已销毁。
  bool disposed = false;

  /// 所有参与请求的数量，包含等待显示的请求。
  @override
  int get activeCount =>
      states.values.fold(0, (sum, state) => sum + state.count);

  /// 取消上一个边沿窗口。
  void clear(_Display state) {
    state.timer?.cancel();
    state.timer = null;
  }

  /// 先更新状态，再通知；回调异常不能破坏配对。
  void schedule(void Function(bool) fn, _Display state, bool visible,
      Duration delay, DiomanLogger log) {
    /// 发出当前显示边沿。
    void fire() {
      state.timer = null;
      state.shown = visible;
      if (!visible) states.remove(fn);
      try {
        fn(visible);
      } catch (e, s) {
        log('[${DiomanLoading.pluginName}] 通知回调失败: $e\n$s');
      }
    }

    if (delay > Duration.zero) {
      state.timer = clock.createTimer(delay, fire);
    } else {
      fire();
    }
  }

  /// 逻辑请求计数严格配对，在 finally 中释放。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = resolveOption<DiomanLoadingOptions>(
        ctx.request.call.options[DiomanLoading.option],
        base: base,
        merge: (a, b) => DiomanLoadingOptions(
            enabled: b.enabled,
            onChanged: b.onChanged ?? a.onChanged,
            delay: b.delay ?? a.delay,
            delayClose: b.delayClose ?? a.delayClose));
    if (disposed || o == null || o.enabled == false) return next();
    final fn = o.onChanged!;
    final state = states.putIfAbsent(fn, () => _Display(ctx.client.logError));
    if (++state.count == 1) {
      clear(state);
      if (!state.shown) {
        schedule(fn, state, true, o.delay!, ctx.client.logError);
      }
    }
    try {
      final result = await next();
      final cancelled = ctx.cancelled();
      return result.kind == DiomanKind.internal ? result : cancelled ?? result;
    } finally {
      if (--state.count == 0 && !disposed) {
        clear(state);
        if (state.shown) {
          schedule(fn, state, false, o.delayClose!, ctx.client.logError);
        } else {
          states.remove(fn);
        }
      }
    }
  }

  /// 取消窗口并立即关闭已显示回调，在途请求不再通知。
  @override
  void dispose() {
    disposed = true;
    for (final entry in states.entries.toList()) {
      clear(entry.value);
      if (entry.value.shown) {
        schedule(entry.key, entry.value, false, Duration.zero, entry.value.log);
      }
    }
    states.clear();
  }
}
