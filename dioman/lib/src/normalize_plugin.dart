import 'package:dio/dio.dart';
import 'dioman_plugin.dart';
import 'auth_plugin.dart';
import 'breaker_plugin.dart';
import 'cache_plugin.dart';
import 'cancel_plugin.dart';
import 'envs_plugin.dart';
import 'filter_plugin.dart';
import 'key_plugin.dart';
import 'loading_plugin.dart';
import 'log_plugin.dart';
import 'offline_plugin.dart';
import 'repath_plugin.dart';
import 'retry_plugin.dart';
import 'share_plugin.dart';
import 'timeout_plugin.dart';
import 'plugin_order.dart';

/// Per-request override for [DiomanNormalize], read from `extra['dioman:normalize']`.
///
/// [DiomanNormalize]的单请求覆盖，从`extra['dioman:normalize']`读取。
class DiomanNormalizeOptions {
  const DiomanNormalizeOptions({
    this.enabled,
    this.dataKey,
    this.codeKey,
    this.messageKey,
    this.isSuccess,
    this.shouldNormalize,
  });

  /// `false` skips envelope unwrapping for this request. `null` (default)
  /// inherits [DiomanNormalize.enabled].
  ///
  /// `false`表示本次请求跳过拆信封。`null`（默认）沿用[DiomanNormalize.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default `dataKey` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`dataKey`。
  final String? dataKey;

  /// Overrides the plugin's default `codeKey` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`codeKey`。
  final String? codeKey;

  /// Overrides the plugin's default `messageKey` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`messageKey`。
  final String? messageKey;

  /// Overrides the plugin's default `isSuccess` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`isSuccess`判定函数。
  final bool Function(dynamic code)? isSuccess;

  /// Overrides the plugin's default `shouldNormalize` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`shouldNormalize`判定函数。
  final bool Function(RequestOptions options, Response<dynamic> response)? shouldNormalize;
}

/// Thrown when [DiomanNormalize] receives a response whose [codeKey] value
/// does not satisfy [isSuccess].
///
/// [DiomanNormalize]收到一个[codeKey]值不满足[isSuccess]的响应时抛出。
class DiomanException implements Exception {
  const DiomanException({required this.code, required this.message, this.data});

  /// The business-logic status code from the envelope.
  ///
  /// 信封里的业务状态码。
  final dynamic code;

  /// The human-readable message from the envelope.
  ///
  /// 信封里的人类可读消息。
  final String message;

  /// The raw payload from the envelope (may be null).
  ///
  /// 信封里的原始负载（可能为null）。
  final dynamic data;

  @override
  String toString() => 'DiomanException(code: $code, message: $message)';
}

/// Unwraps a standard API envelope `{ code, data, message }`.
///
/// 拆开标准API信封`{ code, data, message }`。
///
/// On a successful envelope, replaces `response.data` with the inner [dataKey]
/// value so downstream code works directly with the payload.
///
/// 信封成功时，把`response.data`替换成内层的[dataKey]值，方便下游代码直接
/// 处理payload。
///
/// On a non-success code, rejects with an [DiomanException] so error handling
/// is unified at the interceptor layer.
///
/// 非成功code时，以[DiomanException] reject，让错误处理统一在拦截器层完成。
///
/// ## Optional, business-specific — install LAST
///
/// Unlike every other dioman plugin, this one isn't a transport concern —
/// it's a convenience for ONE specific envelope convention, and not every
/// API uses one. Use it if it fits; skip it entirely if your backend
/// doesn't wrap responses, or wraps them differently and you'd rather
/// unwrap by hand.
///
/// If you do use it, install it LAST — after `log`, at the very end of the
/// chain (this is also where [Dioman.install] places it when you pass
/// `normalize:`). That way every OTHER plugin (cache, share,
/// DiomanRetry's `shouldRetry`, DiomanLog's dump, ...) sees the
/// response exactly as it came off the wire, not already unwrapped —
/// consistent regardless of which of them happen to be installed.
///
/// ## 可选、跟业务相关——装在最后
///
/// 跟dioman其它插件不一样，这个不是传输层的事——它只是针对**某一种**信封
/// 约定的便利转换，不是每个API都这么包。适合就用，不适合（后端不封装，
/// 或者封装方式不一样、想自己手动拆）就完全不装。
///
/// 如果要用，装在最后——排在`log`后面，整条链的最末尾（这也是
/// [Dioman.install]传入`normalize:`时放置的位置）。这样其它所有插件
/// （cache、share、DiomanRetry的`shouldRetry`、DiomanLog的
/// dump……）看到的都是响应在线路上原本的样子，不是已经被解包过的——不管
/// 装了哪些插件，行为都一致。
///
/// Per-request opt-out: `options.extra['dioman:normalize'] = const DiomanNormalizeOptions(enabled: false)`.
///
/// ```dart
/// // Server response: {"code": 0, "data": {...}, "message": "ok"}
///
/// dio.interceptors.addAll([
///   // ... cache, share, auth, retry, log, whatever else you use ...
///   const DiomanNormalize(), // last
/// ]);
///
/// final res = await dio.get('/user/1');
/// // res.data == the inner {...} object, code/message stripped
/// ```
class DiomanNormalize extends DiomanPlugin {
  const DiomanNormalize({
    this.dataKey = 'data',
    this.codeKey = 'code',
    this.messageKey = 'message',
    this.enabled = true,
    this.isSuccess,
    this.shouldNormalize,
  });

  /// The key that holds the actual payload inside the envelope.
  /// Overridable per request via [DiomanNormalizeOptions.dataKey].
  ///
  /// 信封里存放实际payload的键名。可通过[DiomanNormalizeOptions.dataKey]按请求覆盖。
  final String dataKey;

  /// The key that holds the business-logic status code.
  /// Overridable per request via [DiomanNormalizeOptions.codeKey].
  ///
  /// 信封里存放业务状态码的键名。可通过[DiomanNormalizeOptions.codeKey]按请求覆盖。
  final String codeKey;

  /// The key that holds the human-readable message.
  /// Overridable per request via [DiomanNormalizeOptions.messageKey].
  ///
  /// 信封里存放人类可读消息的键名。可通过[DiomanNormalizeOptions.messageKey]按请求覆盖。
  final String messageKey;

  /// `false` disables the plugin entirely — every envelope stays wrapped.
  ///
  /// `false`时插件整体失效——所有信封都不拆包。
  final bool enabled;

  /// Returns true if `code` represents success. Defaults to `code == 0`.
  /// Overridable per request via [DiomanNormalizeOptions.isSuccess].
  ///
  /// 返回true表示该`code`代表成功，默认`code == 0`。可通过
  /// [DiomanNormalizeOptions.isSuccess]按请求覆盖。
  final bool Function(dynamic code)? isSuccess;

  /// Additional condition for applying normalization.
  /// Defaults to responses with JSON content-type. Overridable per request
  /// via [DiomanNormalizeOptions.shouldNormalize].
  ///
  /// 是否要走拆包逻辑的附加条件，默认针对JSON内容类型的响应。可通过
  /// [DiomanNormalizeOptions.shouldNormalize]按请求覆盖。
  final bool Function(RequestOptions options, Response<dynamic> response)?
      shouldNormalize;

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:normalize';

  @override
  String get name => pluginName;

  /// 顺序声明：normalize排在所有内置插件之后：其余插件看到的都是线上原始响应。
  @override
  DiomanPluginOrder get ordering => const DiomanPluginOrder(
        after: {
          DiomanEnvs.pluginName,
          DiomanTimeout.pluginName,
          DiomanRepath.pluginName,
          DiomanFilter.pluginName,
          DiomanKey.pluginName,
          DiomanCache.pluginName,
          DiomanOffline.pluginName,
          DiomanShare.pluginName,
          DiomanCancel.pluginName,
          DiomanLoading.pluginName,
          DiomanAuth.pluginName,
          DiomanRetry.pluginName,
          DiomanBreaker.pluginName,
          DiomanLog.pluginName,
        },
      );

  /// 业务码是否算成功：优先用 [$isSuccess]，缺省为 `code == 0`。
  bool _isSuccess(dynamic code, bool Function(dynamic)? $isSuccess) =>
      $isSuccess != null ? $isSuccess(code) : code == 0;

  /// 判断 [response] 是否该走拆包逻辑（enabled / shouldNormalize / 信封形状）。
  bool _shouldNormalize(
    RequestOptions options,
    Response<dynamic> response,
    bool $enabled,
    String $dataKey,
    String $codeKey,
    String $messageKey,
    bool Function(RequestOptions, Response<dynamic>)? $shouldNormalize,
  ) {
    if (!$enabled) return false;
    if ($shouldNormalize != null) return $shouldNormalize(options, response);
    // Default: only process JSON bodies that look like an envelope. Require
    // BOTH the status [codeKey] AND either the payload [dataKey] or the
    // [messageKey] — a plain resource that merely happens to carry a `code`
    // field (e.g. a country/error code as data) would otherwise be mistaken
    // for an envelope and wrongly rejected as an DiomanException.
    //
    // 默认：只处理看起来像信封的JSON body。要求同时含状态[codeKey]，且含
    // [dataKey]或[messageKey]之一——避免把碰巧带`code`字段的普通资源
    // （比如国家码/错误码当数据）误判成信封而错误地以DiomanException拒绝。
    final data = response.data;
    if (data is! Map) return false;
    return data.containsKey($codeKey) &&
        (data.containsKey($dataKey) || data.containsKey($messageKey));
  }

  /// 把插件级配置与请求级 [DiomanNormalizeOptions] 合并，判定 [response] 是否
  /// 会被拆包；会则返回合并后的键名与成功判定，不会则返回 `null`（原样透传）。
  ///
  /// [onResponse] 与 [_isBusinessFailure] 共用它，保证"拒不拒绝"只有一份逻辑。
  ({
    String dataKey,
    String codeKey,
    String messageKey,
    bool Function(dynamic)? isSuccess,
  })? _resolveEnvelope(Response<dynamic> response) {
    final options = response.requestOptions;
    final override = options.extra[name];
    final o = override is DiomanNormalizeOptions ? override : null;

    final $enabled = o?.enabled ?? enabled;
    final $dataKey = o?.dataKey ?? dataKey;
    final $codeKey = o?.codeKey ?? codeKey;
    final $messageKey = o?.messageKey ?? messageKey;
    final $shouldNormalize = o?.shouldNormalize ?? shouldNormalize;

    if (!_shouldNormalize(
      options,
      response,
      $enabled,
      $dataKey,
      $codeKey,
      $messageKey,
      $shouldNormalize,
    )) {
      return null;
    }
    return (
      dataKey: $dataKey,
      codeKey: $codeKey,
      messageKey: $messageKey,
      isSuccess: o?.isSuccess ?? isSuccess,
    );
  }

  /// [response] 经本插件处理后是否会被判为业务失败（即 [onResponse] 会 reject）。
  ///
  /// 与 [onResponse] 完全同源；未拆包（关闭、非信封、`shouldNormalize` 为 false）
  /// 一律返回 false。仅供 [Dioman] 把判定接给 [DiomanCache]，不属公共 API。
  bool _isBusinessFailure(Response<dynamic> response) {
    final env = _resolveEnvelope(response);
    if (env == null) return false;
    final code = (response.data as Map)[env.codeKey];
    return !_isSuccess(code, env.isSuccess);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final env = _resolveEnvelope(response);
    if (env == null) return handler.next(response);

    final envelope = response.data as Map;
    final code = envelope[env.codeKey];
    final message = '${envelope[env.messageKey] ?? ''}';
    final data = envelope[env.dataKey];

    if (_isSuccess(code, env.isSuccess)) {
      // Replace data with the inner payload.
      response.data = data;
      return handler.next(response);
    }

    // Non-success: reject so error-handling code is triggered.
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: DiomanException(code: code, message: message, data: data),
        message: message,
        type: DioExceptionType.badResponse,
      ),
      true,
    );
  }
}

/// 取 [normalize] 的"业务失败"判定，供 [Dioman] 接给 [DiomanCache]。
///
/// 库内可见：`lib/dioman.dart` 用 `hide` 不导出，不属公共 API。
bool Function(Response<dynamic>) diomanNormalizeFailureProbe(
        DiomanNormalize normalize) =>
    normalize._isBusinessFailure;
