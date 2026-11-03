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
  /// [onChanged] 按相等回调共享计数；[delay] 与 [delayClose] 控制边沿延迟。
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

/// 按相等回调跨客户端共享显示周期，内层重发不重复计数。
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

  /// 建立本客户端占用与窗口时钟。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Loading<R>(
      client.clock,
      DiomanLoadingOptions(
          onChanged: onChanged, delay: delay, delayClose: delayClose));
}

/// 按 == 合并回调，支持实例方法 tear-off。
final _displays = <void Function(bool), _Display>{};

/// 共享显示资源诊断，不从公开入口导出。
abstract final class DiomanLoadingDiagnostics {
  /// 仍有占用或待执行窗口的条目数。
  static int get entries => _displays.length;
}

/// 一个共享回调的显示与窗口状态。
class _Display {
  /// 保存可隔离的通知日志器。
  _Display(this.log);

  /// 通知日志器。
  final DiomanLogger log;

  /// 全部客户端占用数。
  int count = 0;

  /// 是否已通知显示。
  bool shown = false;

  /// 延迟显示窗口。
  Timer? showTimer;

  /// 延迟隐藏窗口。
  Timer? hideTimer;

  /// 隐藏窗口归属方，接入新请求时转移。
  Object? owner;

  /// 取消全部边沿窗口。
  void clear() {
    showTimer?.cancel();
    hideTimer?.cancel();
    showTimer = null;
    hideTimer = null;
  }
}

/// 每客户端的占用与管理接口。
class _Loading<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> implements DiomanLoadingApi {
  /// 保存时钟与配置。
  _Loading(this.clock, this.base);

  /// 窗口安排方的时钟。
  final DiomanClock clock;

  /// 预合并配置。
  final DiomanLoadingOptions base;

  /// 本客户端按相等回调记录的占用。
  final holdings = <void Function(bool), int>{};

  /// 是否已卸载。
  bool disposed = false;

  /// 只计算本客户端占用，卸载后为零。
  @override
  int get activeCount => holdings.values.fold(0, (sum, count) => sum + count);

  /// 更新状态后通知，异常不影响配对。
  void schedule(
      void Function(bool) fn, _Display state, bool visible, Duration delay) {
    /// 发出边沿并释放无需保留的共享条目。
    void fire() {
      state.showTimer = null;
      state.hideTimer = null;
      state.shown = visible;
      if (!visible) _displays.remove(fn);
      try {
        fn(visible);
      } catch (e, s) {
        state.log('[${DiomanLoading.pluginName}] 通知回调失败: $e\n$s');
      }
    }

    state.owner = this;
    // 使用安排窗口的客户端时钟；窗口交接后新窗口使用新归属方的时钟。
    if (delay > Duration.zero) {
      final timer = clock.createTimer(delay, fire);
      if (visible) {
        state.showTimer = timer;
      } else {
        state.hideTimer = timer;
      }
    } else {
      fire();
    }
  }

  /// 释放最后占用时取消显示窗口并安排隐藏。
  void release(void Function(bool) fn, _Display state, Duration delay) {
    if (state.count != 0) return;
    state.clear();
    if (state.shown) {
      schedule(fn, state, false, delay);
    } else {
      _displays.remove(fn);
    }
  }

  /// 每个逻辑请求只登记和释放一次本客户端占用。
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
    final state =
        _displays.putIfAbsent(fn, () => _Display(ctx.client.logError));
    holdings.update(fn, (count) => count + 1, ifAbsent: () => 1);
    if (++state.count == 1) {
      state.clear();
      state.owner = this;
      if (!state.shown) schedule(fn, state, true, o.delay!);
    }
    try {
      final result = await next();
      final cancelled = ctx.cancelled();
      return result.kind == DiomanKind.internal ? result : cancelled ?? result;
    } finally {
      // dispose 已释放本实例全部占用，迟到 finally 不再扣减或通知。
      if (!disposed) {
        final remaining = holdings[fn]! - 1;
        if (remaining == 0) {
          holdings.remove(fn);
        } else {
          holdings[fn] = remaining;
        }
        state.count--;
        release(fn, state, o.delayClose!);
      }
    }
  }

  /// 只释放本客户端占用；归属窗口无人占用时立即补齐 false。
  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    for (final entry in _displays.entries.toList()) {
      final state = entry.value;
      final count = holdings[entry.key] ?? 0;
      state.count -= count;
      if (count > 0 || state.owner == this) {
        release(entry.key, state, Duration.zero);
      }
    }
    holdings.clear();
  }
}
