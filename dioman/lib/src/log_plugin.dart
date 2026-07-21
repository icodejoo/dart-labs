import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// Signature for a custom log sink.
///
/// 自定义日志输出函数的签名。
typedef LogWriter = void Function(String message, {Object? error});

/// Per-request override for [DiomanLog], read from `extra['dioman:log']`.
///
/// [DiomanLog]的单请求覆盖，从`extra['dioman:log']`读取。
class DiomanLogOptions {
  const DiomanLogOptions({
    this.enabled,
    this.logRequest,
    this.logResponse,
    this.logError,
    this.logHeaders,
    this.logBody,
    this.maxBodyLength,
    this.writer,
  });

  /// `false` skips logging for this request. `null` (default) inherits
  /// [DiomanLog.enabled].
  ///
  /// `false`表示本次请求跳过日志。`null`（默认）沿用[DiomanLog.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default `logRequest` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`logRequest`。
  final bool? logRequest;

  /// Overrides the plugin's default `logResponse` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`logResponse`。
  final bool? logResponse;

  /// Overrides the plugin's default `logError` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`logError`。
  final bool? logError;

  /// Overrides the plugin's default `logHeaders` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`logHeaders`。
  final bool? logHeaders;

  /// Overrides the plugin's default `logBody` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`logBody`。
  final bool? logBody;

  /// Overrides the plugin's default `maxBodyLength` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`maxBodyLength`。
  final int? maxBodyLength;

  /// Overrides the plugin's default `writer` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`writer`。
  final LogWriter? writer;
}

/// Logs HTTP requests, responses, and errors to the console.
///
/// 把HTTP请求、响应、错误打印到控制台。
///
/// Zero dependencies — uses plain [print] by default; inject [writer] to
/// route output to any logging framework.
///
/// 零依赖——默认用[print]，注入[writer]可转发到任意日志框架。
///
/// Per-request opt-out: `options.extra['dioman:log'] = const DiomanLogOptions(enabled: false)`.
///
/// ```dart
/// final log = DiomanLog(logHeaders: true, maxBodyLength: 500);
/// dio.interceptors.add(log);
/// ```
class DiomanLog extends DiomanPlugin {
  const DiomanLog({
    this.logRequest = true,
    this.logResponse = true,
    this.logError = true,
    this.logHeaders = false,
    this.logBody = true,
    this.maxBodyLength = 1000,
    this.enabled = true,
    this.writer,
  });

  /// Whether to log outgoing requests. Overridable per request via
  /// [DiomanLogOptions.logRequest].
  ///
  /// 是否记录发出的请求。可通过[DiomanLogOptions.logRequest]按请求覆盖。
  final bool logRequest;

  /// Whether to log successful responses. Overridable per request via
  /// [DiomanLogOptions.logResponse].
  ///
  /// 是否记录成功的响应。可通过[DiomanLogOptions.logResponse]按请求覆盖。
  final bool logResponse;

  /// Whether to log errors. Overridable per request via
  /// [DiomanLogOptions.logError].
  ///
  /// 是否记录错误。可通过[DiomanLogOptions.logError]按请求覆盖。
  final bool logError;

  /// Whether to include headers in the log output. Overridable per request
  /// via [DiomanLogOptions.logHeaders].
  ///
  /// 日志里是否包含头部信息。可通过[DiomanLogOptions.logHeaders]按请求覆盖。
  final bool logHeaders;

  /// Whether to include the body in the log output. Overridable per request
  /// via [DiomanLogOptions.logBody].
  ///
  /// 日志里是否包含body。可通过[DiomanLogOptions.logBody]按请求覆盖。
  final bool logBody;

  /// `false` disables the plugin entirely — nothing is ever logged.
  ///
  /// `false`时插件整体失效——永不记录日志。
  final bool enabled;

  /// Truncates body output to this many characters. Use -1 for unlimited.
  /// Overridable per request via [DiomanLogOptions.maxBodyLength].
  ///
  /// body输出截断到这么多字符，用-1表示不限制。可通过
  /// [DiomanLogOptions.maxBodyLength]按请求覆盖。
  final int maxBodyLength;

  /// Custom log sink. Defaults to [print]. Overridable per request via
  /// [DiomanLogOptions.writer].
  ///
  /// 自定义日志输出函数，默认[print]。可通过[DiomanLogOptions.writer]按请求覆盖。
  final LogWriter? writer;

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:log';

  @override
  String get name => pluginName;

  /// Merges the per-request override with the plugin's own defaults.
  ///
  /// 把单请求覆盖跟插件自身默认值合并。
  ({
    bool enabled,
    bool logRequest,
    bool logResponse,
    bool logError,
    bool logHeaders,
    bool logBody,
    int maxBodyLength,
    LogWriter? writer,
  }) _resolve(RequestOptions options) {
    final override = options.extra[name];
    final o = override is DiomanLogOptions ? override : null;
    return (
      enabled: o?.enabled ?? enabled,
      logRequest: o?.logRequest ?? logRequest,
      logResponse: o?.logResponse ?? logResponse,
      logError: o?.logError ?? logError,
      logHeaders: o?.logHeaders ?? logHeaders,
      logBody: o?.logBody ?? logBody,
      maxBodyLength: o?.maxBodyLength ?? maxBodyLength,
      writer: o?.writer ?? writer,
    );
  }

  void _log(LogWriter? $writer, String msg, {Object? error}) {
    if ($writer != null) {
      $writer(msg, error: error);
    } else {
      // ignore: avoid_print
      print(msg);
    }
  }

  String _tag(String label) => '[$name] $label';

  String _truncate(dynamic body, int maxBodyLength) {
    final s = body?.toString() ?? '';
    if (maxBodyLength < 0 || s.length <= maxBodyLength) return s;
    return '${s.substring(0, maxBodyLength)}… (+${s.length - maxBodyLength} chars)';
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final $r = _resolve(options);
    if ($r.enabled && $r.logRequest) {
      final buf = StringBuffer()
        ..writeln(_tag('→ ${options.method.toUpperCase()} ${options.uri}'));
      if ($r.logHeaders && options.headers.isNotEmpty) {
        buf.writeln('  Headers: ${options.headers}');
      }
      if ($r.logBody && options.data != null) {
        buf.write('  Body: ${_truncate(options.data, $r.maxBodyLength)}');
      }
      _log($r.writer, buf.toString().trimRight());
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final $r = _resolve(response.requestOptions);
    if ($r.enabled && $r.logResponse) {
      final buf = StringBuffer()
        ..writeln(_tag(
            '← ${response.statusCode} ${response.requestOptions.method.toUpperCase()} ${response.requestOptions.uri}'));
      if ($r.logHeaders && response.headers.map.isNotEmpty) {
        buf.writeln('  Headers: ${response.headers.map}');
      }
      if ($r.logBody && response.data != null) {
        buf.write('  Body: ${_truncate(response.data, $r.maxBodyLength)}');
      }
      _log($r.writer, buf.toString().trimRight());
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final $r = _resolve(err.requestOptions);
    if ($r.enabled && $r.logError) {
      final status = err.response?.statusCode;
      final label = status != null
          ? '✗ $status ${err.requestOptions.method.toUpperCase()} ${err.requestOptions.uri}'
          : '✗ ${err.type.name} ${err.requestOptions.method.toUpperCase()} ${err.requestOptions.uri}';
      _log($r.writer, _tag(label), error: err.error ?? err.message);
      if ($r.logBody && err.response?.data != null) {
        _log($r.writer, '  Error body: ${_truncate(err.response!.data, $r.maxBodyLength)}');
      }
    }
    handler.next(err);
  }
}
