import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// Signature for a custom log sink.
typedef LogWriter = void Function(String message, {Object? error});

/// Logs HTTP requests, responses, and errors to the console.
///
/// Zero dependencies — uses plain [print] by default; inject [writer] to
/// route output to any logging framework.
///
/// Per-request opt-out: `options.extra['log'] = false`.
///
/// ```dart
/// final log = LogPlugin(logHeaders: true, maxBodyLength: 500);
/// dio.interceptors.add(log);
/// ```
class LogPlugin extends DioPlugin {
  const LogPlugin({
    this.logRequest = true,
    this.logResponse = true,
    this.logError = true,
    this.logHeaders = false,
    this.logBody = true,
    this.maxBodyLength = 1000,
    this.writer,
  });

  final bool logRequest;
  final bool logResponse;
  final bool logError;
  final bool logHeaders;
  final bool logBody;

  /// Truncates body output to this many characters. Use -1 for unlimited.
  final int maxBodyLength;

  /// Custom log sink. Defaults to [print].
  final LogWriter? writer;

  @override
  String get name => 'log';

  void _log(String msg, {Object? error}) {
    if (writer != null) {
      writer!(msg, error: error);
    } else {
      // ignore: avoid_print
      print(msg);
    }
  }

  String _tag(String label) => '[$name] $label';

  String _truncate(dynamic body) {
    final s = body?.toString() ?? '';
    if (maxBodyLength < 0 || s.length <= maxBodyLength) return s;
    return '${s.substring(0, maxBodyLength)}… (+${s.length - maxBodyLength} chars)';
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (logRequest && options.extra['log'] != false) {
      final buf = StringBuffer()
        ..writeln(_tag('→ ${options.method.toUpperCase()} ${options.uri}'));
      if (logHeaders && options.headers.isNotEmpty) {
        buf.writeln('  Headers: ${options.headers}');
      }
      if (logBody && options.data != null) {
        buf.write('  Body: ${_truncate(options.data)}');
      }
      _log(buf.toString().trimRight());
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (logResponse && response.requestOptions.extra['log'] != false) {
      final buf = StringBuffer()
        ..writeln(_tag(
            '← ${response.statusCode} ${response.requestOptions.method.toUpperCase()} ${response.requestOptions.uri}'));
      if (logHeaders && response.headers.map.isNotEmpty) {
        buf.writeln('  Headers: ${response.headers.map}');
      }
      if (logBody && response.data != null) {
        buf.write('  Body: ${_truncate(response.data)}');
      }
      _log(buf.toString().trimRight());
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (logError && err.requestOptions.extra['log'] != false) {
      final status = err.response?.statusCode;
      final label = status != null
          ? '✗ $status ${err.requestOptions.method.toUpperCase()} ${err.requestOptions.uri}'
          : '✗ ${err.type.name} ${err.requestOptions.method.toUpperCase()} ${err.requestOptions.uri}';
      _log(_tag(label), error: err.error ?? err.message);
      if (logBody && err.response?.data != null) {
        _log('  Error body: ${_truncate(err.response!.data)}');
      }
    }
    handler.next(err);
  }
}
