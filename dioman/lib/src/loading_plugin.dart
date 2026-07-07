// ignore_for_file: prefer_initializing_formals
import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// Per-request override for [DiomanLoading], read from `extra['dioman:loading']`.
///
/// [DiomanLoading]的单请求覆盖，从`extra['dioman:loading']`读取。
class DiomanLoadingOptions {
  const DiomanLoadingOptions({this.enabled, this.onChanged});

  /// `false` opts this request out of the loading counter entirely — it
  /// never increments/decrements [DiomanLoading.activeCount] and never
  /// triggers any `onChanged`. `null` (default) inherits the plugin's own
  /// [DiomanLoading.enabled].
  ///
  /// `false`表示本次请求完全不计入loading计数器——不会增减
  /// [DiomanLoading.activeCount]，也不会触发任何`onChanged`。`null`（默认）
  /// 沿用插件自身的[DiomanLoading.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default `onChanged` for this request only.
  /// `onChanged` is a pure callback — just "notify with this bool" — it has
  /// no counting logic of its own. The shared 0↔1 edge-triggered counter
  /// still runs exactly the same for this request; only *which* callback it
  /// invokes at that edge changes. If this happens to be the request that
  /// starts/ends the whole in-flight batch, this callback fires instead of
  /// the plugin's own `onChanged` — e.g. disable a button for the request
  /// that starts the batch, alongside a global spinner driven by the
  /// default for every other request.
  ///
  /// 仅本次请求覆盖插件默认的`onChanged`。`onChanged`是纯回调——只负责
  /// "用这个bool通知一下"，自己不带任何计数逻辑。共享的0↔1边缘触发计数器
  /// 对这次请求照常运行，完全一样；变的只是边缘触发时*调用哪一个*回调。
  /// 如果这次请求恰好是让整批在途请求从0变1（或从1变0）的那一个，触发的
  /// 就是这个回调而不是插件默认的`onChanged`——比如在默认回调给其它请求
  /// 驱动全局spinner的同时，给触发批次边缘的这次请求单独禁用一个按钮。
  final void Function(bool loading)? onChanged;
}

/// Tracks in-flight requests and notifies via a callback.
///
/// 追踪在途请求数并通过回调通知。
///
/// Calls [onChanged](true) when the first request starts, and
/// [onChanged](false) when the last one completes. This makes it trivial
/// to drive a global loading indicator without any Rx dependency.
///
/// 第一个请求开始时调用[onChanged](true)，最后一个结束时调用
/// [onChanged](false)。这样驱动全局loading指示器不需要任何Rx依赖。
///
/// Per-request opt-out: `options.extra['dioman:loading'] = const DiomanLoadingOptions(enabled: false)`.
/// Per-request `onChanged` override: `options.extra['dioman:loading'] = DiomanLoadingOptions(onChanged: (loading) => setState(() => _buttonDisabled = loading))`.
///
/// ```dart
/// final loading = DiomanLoading(
///   onChanged: (active) => setState(() => _loading = active),
/// );
/// dio.interceptors.add(loading);
/// ```
class DiomanLoading extends DiomanPlugin {
  DiomanLoading({required void Function(bool loading) onChanged, this.enabled = true})
      : _onChanged = onChanged;

  static const _name = 'dioman:loading';
  static const _kBracketed = '$_name:bracketed';
  static const _kOnChanged = '$_name:onChanged';

  /// `false` disables the plugin entirely — every request passes through
  /// untouched and the counter never moves.
  ///
  /// `false`时插件整体失效——所有请求原样通过，计数器永不变动。
  final bool enabled;

  /// The default callback used at the counter's 0↔1 edge, for any request
  /// that doesn't carry its own [DiomanLoadingOptions.onChanged].
  ///
  /// 计数器0↔1边缘默认使用的回调，用于没有携带自己
  /// [DiomanLoadingOptions.onChanged]的请求。
  final void Function(bool loading) _onChanged;

  /// Current in-flight count. Every request not opted out via
  /// [DiomanLoadingOptions.enabled] is counted here — this is unaffected by
  /// a per-request `onChanged` override, which only changes which callback
  /// fires at the edge, never whether the request is counted.
  ///
  /// 当前在途请求数。只要没被[DiomanLoadingOptions.enabled]排除，每个请求
  /// 都计入这里——单请求的`onChanged`覆盖只改变边缘触发时调用哪个回调，
  /// 从不影响这个请求是否被计数。
  int _count = 0;

  /// Number of requests currently in-flight.
  ///
  /// 当前在途请求数。
  int get activeCount => _count;

  @override
  String get name => _name;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final override = options.extra[name];
    final o = override is DiomanLoadingOptions ? override : null;
    if (!(o?.enabled ?? enabled)) return handler.next(options);

    // Resolve once: this request's own onChanged if it has one, else the
    // plugin's default. Stashed so the matching onResponse/onError uses the
    // SAME callback for this request's decrement, whatever else is
    // concurrently in-flight by then.
    // 只解析一次：这次请求自己的onChanged（若有），否则用插件默认的。
    // 暂存起来，保证对应的onResponse/onError在做这次请求的减计数时用的是
    // 同一个回调，不受届时其它并发请求状态影响。
    final $onChanged = o?.onChanged ?? _onChanged;
    options.extra[_kOnChanged] = $onChanged;

    options.extra[_kBracketed] = true;
    if (_count++ == 0) $onChanged(true);
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _decrement(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _decrement(err.requestOptions);
    handler.next(err);
  }

  // Only decrement for a request this plugin actually incremented for. An
  // earlier interceptor's onRequest can short-circuit (cache/share/mock hit)
  // before this plugin's onRequest ever runs — if that resolve is later
  // propagated with `callFollowingResponseInterceptor: true`, this onResponse
  // still fires and, without this guard, would decrement a counter it never
  // incremented (stealing a slot from an unrelated in-flight request).
  //
  // 只对本插件真正加过计数的请求做减计数。更早的拦截器可能在onRequest阶段就
  // 短路了（cache/share/mock命中），本插件的onRequest根本没跑到；若那次
  // resolve带着`callFollowingResponseInterceptor: true`传播，这里的onResponse
  // 仍会触发——没有这个判断就会去减一个自己从未加过的计数（顶掉了另一个真实
  // 在途请求的名额）。
  void _decrement(RequestOptions options) {
    if (options.extra.remove(_kBracketed) == true) {
      final $onChanged =
          options.extra.remove(_kOnChanged) as void Function(bool)? ?? _onChanged;
      if (_count > 0 && --_count == 0) $onChanged(false);
    }
  }

  @override
  void dispose() {
    _count = 0;
    _onChanged(false);
  }
}
