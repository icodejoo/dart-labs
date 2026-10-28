// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'dioman_plugin.dart';
import 'auth_plugin.dart';
import 'cache_plugin.dart';
import 'retry_plugin.dart';
import 'share_plugin.dart';
import 'plugin_order.dart';

/// Per-request override for [DiomanLoading], read from `extra['dioman:loading']`.
///
/// [DiomanLoading]的单请求覆盖，从`extra['dioman:loading']`读取。
class DiomanLoadingOptions {
  /// 创建单请求覆盖配置。
  const DiomanLoadingOptions(
      {this.enabled, this.onChanged, this.delay, this.delayClose});

  /// `false` opts this request out of the loading counter entirely — it
  /// never increments/decrements [DiomanLoading.activeCount] and never
  /// triggers any `onChanged`. `null` (default) inherits the plugin's own
  /// [DiomanLoading.enabled].
  ///
  /// `false`表示本次请求完全不计入loading计数器——不会增减
  /// [DiomanLoading.activeCount]，也不会触发任何`onChanged`。`null`（默认）
  /// 沿用插件自身的[DiomanLoading.enabled]。
  final bool? enabled;

  /// Selects the callback when this request opens a display cycle. The same
  /// callback receives `false` when that cycle ends, including disposal.
  ///
  /// 本请求开启显示周期时选择该回调；周期结束（含释放插件）时由同一回调关闭。
  final void Function(bool loading)? onChanged;

  /// Overrides the plugin's default [DiomanLoading.delay] for this request
  /// only — only takes effect if this request is the one triggering the
  /// 0→1 edge.
  ///
  /// 仅本次请求覆盖插件默认的[DiomanLoading.delay]——只有这次请求恰好是
  /// 触发0→1边缘的那一次才生效。
  final Duration? delay;

  /// Overrides the plugin's default [DiomanLoading.delayClose] for this
  /// request only — only takes effect if this request is the one
  /// triggering the 1→0 edge.
  ///
  /// 仅本次请求覆盖插件默认的[DiomanLoading.delayClose]——只有这次请求
  /// 恰好是触发1→0边缘的那一次才生效。
  final Duration? delayClose;
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
/// [delay]/[delayClose] guard against flicker, both default to
/// [Duration.zero] (immediate, matching pre-existing behavior): [delay]
/// defers `onChanged(true)` past a 0→1 edge, canceled outright if the count
/// falls back to 0 before it elapses (a request that finishes fast enough
/// never shows loading at all); [delayClose] defers `onChanged(false)` past
/// a 1→0 edge, canceled if a new request bumps the count back to 1 before
/// it elapses (back-to-back requests don't flicker the indicator off and
/// immediately back on).
///
/// [delay]/[delayClose]防闪烁，默认都是[Duration.zero]（即时，跟原有行为
/// 一致）：[delay]把`onChanged(true)`延后到0→1边缘之后才触发，期间计数回落
/// 到0则直接取消（够快结束的请求从不显示loading）；[delayClose]把
/// `onChanged(false)`延后到1→0边缘之后才触发，期间新请求把计数顶回1则取消
/// （连续请求之间不会先熄灭又立刻点亮）。
///
/// ```dart
/// final loading = DiomanLoading(
///   onChanged: (active) => setState(() => _loading = active),
///   delay: Duration(milliseconds: 200),
///   delayClose: Duration(milliseconds: 200),
/// );
/// dio.interceptors.add(loading);
/// ```
class DiomanLoading extends DiomanPlugin {
  /// 创建插件实例。
  DiomanLoading({
    required void Function(bool loading) onChanged,
    this.enabled = true,
    this.delay = Duration.zero,
    this.delayClose = Duration.zero,
  }) : _onChanged = onChanged;

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:loading';

  /// 本请求是否计入显示计数。
  static const _kBracketed = '$pluginName:bracketed';

  /// 本请求的延迟关闭配置。
  static const _kDelayClose = '$pluginName:delayClose';

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

  /// How long to wait after a 0→1 edge before actually calling
  /// `onChanged(true)` — canceled outright if the count falls back to 0
  /// first. Defaults to [Duration.zero] (immediate). Overridable per
  /// request via [DiomanLoadingOptions.delay] (only takes effect if that
  /// request is the one triggering the edge).
  ///
  /// 0→1边缘后延迟多久才真正调用`onChanged(true)`——期间计数回落到0则直接
  /// 取消。默认[Duration.zero]（即时）。可通过[DiomanLoadingOptions.delay]
  /// 按请求覆盖（只有该请求恰好触发这次边缘才生效）。
  final Duration delay;

  /// How long to wait after a 1→0 edge before actually calling
  /// `onChanged(false)` — canceled if a new request bumps the count back to
  /// 1 first. Defaults to [Duration.zero] (immediate). Overridable per
  /// request via [DiomanLoadingOptions.delayClose] (only takes effect if
  /// that request is the one triggering the edge).
  ///
  /// 1→0边缘后延迟多久才真正调用`onChanged(false)`——期间新请求把计数顶回1
  /// 则取消。默认[Duration.zero]（即时）。可通过
  /// [DiomanLoadingOptions.delayClose]按请求覆盖（只有该请求恰好触发这次
  /// 边缘才生效）。
  final Duration delayClose;

  /// Current in-flight count. Every request not opted out via
  /// [DiomanLoadingOptions.enabled] is counted here — this is unaffected by
  /// a per-request `onChanged` override, which only changes which callback
  /// fires at the edge, never whether the request is counted.
  ///
  /// 当前在途请求数。只要没被[DiomanLoadingOptions.enabled]排除，每个请求
  /// 都计入这里——单请求的`onChanged`覆盖只改变边缘触发时调用哪个回调，
  /// 从不影响这个请求是否被计数。
  int _count = 0;

  /// Whether `onChanged(true)` has actually fired (as opposed to merely
  /// being pending behind [_showTimer]).
  ///
  /// `onChanged(true)`是否真的已经触发（跟仅仅还在[_showTimer]里排队
  /// 等待区分开）。
  bool _shown = false;

  /// 本显示周期负责成对通知的回调。
  void Function(bool)? _cycleCallback;

  /// 延迟显示定时器。
  Timer? _showTimer;

  /// 延迟隐藏定时器。
  Timer? _hideTimer;

  /// 取消待显示任务。
  void _clearShowTimer() {
    _showTimer?.cancel();
    _showTimer = null;
  }

  /// 取消待隐藏任务。
  void _clearHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  /// Number of requests currently in-flight.
  ///
  /// 当前在途请求数。
  int get activeCount => _count;

  /// 插件的公开协议名称。
  @override
  String get name => pluginName;

  /// 顺序声明：loading在cache/share之后（命中时不遗留括号），在auth/retry之前（401或重试前清理已完成）。
  @override
  DiomanPluginOrder get ordering => const DiomanPluginOrder(
        after: {
          DiomanCache.pluginName,
          DiomanShare.pluginName,
        },
        before: {DiomanAuth.pluginName, DiomanRetry.pluginName},
      );

  /// 处理请求并完成当前请求出口。
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final override = options.extra[name];
    final o = override is DiomanLoadingOptions ? override : null;
    if (!(o?.enabled ?? enabled)) return handler.next(options);

    // 关闭延迟取本请求配置；显示回调在周期开始时固定。
    final $onChanged = o?.onChanged ?? _onChanged;
    options.extra[_kDelayClose] = o?.delayClose ?? delayClose;

    options.extra[_kBracketed] = true;
    if (_count++ == 0) {
      // 被 delayClose 打断的隐藏窗口——保持之前的显示状态，不用重新走一遍 delay。
      _clearHideTimer();
      if (!_shown && _showTimer == null) {
        _cycleCallback = $onChanged;
        final $delay = o?.delay ?? delay;
        if ($delay > Duration.zero) {
          _showTimer = Timer($delay, () {
            _showTimer = null;
            _shown = true;
            $onChanged(true);
          });
        } else {
          _shown = true;
          $onChanged(true);
        }
      }
    }
    handler.next(options);
  }

  /// 处理响应并完成当前响应出口。
  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    _decrement(response.requestOptions);
    handler.next(response);
  }

  /// 处理失败并完成当前错误出口。
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _decrement(err.requestOptions);
    handler.next(err);
  }

  // Only decrement for a request this plugin actually incremented for. An
  // earlier interceptor's onRequest can short-circuit (cache/share hit)
  // before this plugin's onRequest ever runs — if that resolve is later
  // propagated with `callFollowingResponseInterceptor: true`, this onResponse
  // still fires and, without this guard, would decrement a counter it never
  // incremented (stealing a slot from an unrelated in-flight request).
  //
  // 只对本插件真正加过计数的请求做减计数。更早的拦截器可能在onRequest阶段就
  // 短路了（cache/share命中），本插件的onRequest根本没跑到；若那次
  // resolve带着`callFollowingResponseInterceptor: true`传播，这里的onResponse
  // 仍会触发——没有这个判断就会去减一个自己从未加过的计数（顶掉了另一个真实
  // 在途请求的名额）。
  void _decrement(RequestOptions options) {
    if (options.extra.remove(_kBracketed) != true) return;
    final $onChanged = _cycleCallback ?? _onChanged;
    final $delayClose =
        options.extra.remove(_kDelayClose) as Duration? ?? delayClose;
    if (_count <= 0) return;
    if (--_count != 0) return;
    if (_showTimer != null) {
      // 还没到显示的点请求就已经全部结束了，直接取消，从不显示。
      _clearShowTimer();
      _cycleCallback = null;
      return;
    }
    if (!_shown) return;
    if ($delayClose > Duration.zero) {
      _hideTimer = Timer($delayClose, () {
        _hideTimer = null;
        _shown = false;
        _cycleCallback = null;
        $onChanged(false);
      });
    } else {
      _shown = false;
      _cycleCallback = null;
      $onChanged(false);
    }
  }

  /// 释放本插件持有的状态和资源。
  @override
  void dispose() {
    _clearShowTimer();
    _clearHideTimer();
    _count = 0;
    final callback = _cycleCallback;
    _cycleCallback = null;
    if (_shown) callback?.call(false);
    _shown = false;
  }
}
