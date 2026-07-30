import '../model/source.dart';

/// Hook points that let hosts veto or rewrite core actions.
///
/// 供宿主否决或改写内核行为的拦截点。
abstract class VmInterceptor {
  /// Base constructor.
  ///
  /// 基类构造。
  const VmInterceptor();

  /// Returns false to cancel opening [source].
  ///
  /// 返回 false 可取消打开 [source]。
  Future<bool> beforeOpen(VmSource source) async => true;

  /// Returns the (possibly rewritten) target, or null to cancel the seek.
  ///
  /// 返回（可能被改写的）目标位置；返回 null 取消本次跳转。
  Future<Duration?> beforeSeek(Duration target) async => target;

  /// Returns false to cancel starting playback.
  ///
  /// 返回 false 可取消开始播放。
  Future<bool> beforePlay() async => true;

  /// Called for every kernel or pipeline error.
  ///
  /// 内核或管线出错时回调。
  void onError(Object error, StackTrace stack) {}
}

/// Runs a list of [VmInterceptor]s in order, short-circuiting on veto/cancel.
///
/// 按顺序运行一组 [VmInterceptor]，遇到否决/取消即短路返回。
class VmInterceptorChain {
  /// The ordered interceptors to consult.
  ///
  /// 依次咨询的拦截器列表。
  final List<VmInterceptor> interceptors;

  /// Creates a chain over [interceptors], consulted in list order.
  ///
  /// 基于 [interceptors] 创建拦截链，按列表顺序依次咨询。
  const VmInterceptorChain(this.interceptors);

  /// Runs each interceptor's `beforeOpen`; returns false as soon as any does.
  ///
  /// 依次运行每个拦截器的 `beforeOpen`；任一返回 false 即立即返回 false。
  Future<bool> beforeOpen(VmSource source) async {
    for (final i in interceptors) {
      if (!await i.beforeOpen(source)) return false;
    }
    return true;
  }

  /// Threads [target] through each interceptor's `beforeSeek`; a null result
  /// cancels and stops the chain immediately.
  ///
  /// 将 [target] 依次交给每个拦截器的 `beforeSeek` 改写；任一返回 null 即立即
  /// 取消并停止遍历。
  Future<Duration?> beforeSeek(Duration target) async {
    Duration? current = target;
    for (final i in interceptors) {
      current = await i.beforeSeek(current!);
      if (current == null) return null;
    }
    return current;
  }

  /// Runs each interceptor's `beforePlay`; returns false as soon as any does.
  ///
  /// 依次运行每个拦截器的 `beforePlay`；任一返回 false 即立即返回 false。
  Future<bool> beforePlay() async {
    for (final i in interceptors) {
      if (!await i.beforePlay()) return false;
    }
    return true;
  }

  /// Calls every interceptor's `onError`, isolating each behind its own
  /// try/catch so one throwing interceptor doesn't block the others.
  ///
  /// 调用所有拦截器的 `onError`，每个都用独立 try/catch 隔离，避免某个拦截器
  /// 抛异常影响其他拦截器。
  void onError(Object error, StackTrace stack) {
    for (final i in interceptors) {
      try {
        i.onError(error, stack);
      } catch (_) {
        // Intentionally swallow: one interceptor's failure must not stop
        // the remaining ones from being notified.
        //
        // 有意吞掉异常：单个拦截器的失败不应阻止其余拦截器收到通知。
      }
    }
  }
}
