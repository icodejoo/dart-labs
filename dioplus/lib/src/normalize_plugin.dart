import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// Thrown when [NormalizePlugin] receives a response whose [codeKey] value
/// does not satisfy [isSuccess].
class ApiException implements Exception {
  const ApiException({required this.code, required this.message, this.data});

  final dynamic code;
  final String message;
  final dynamic data;

  @override
  String toString() => 'ApiException(code: $code, message: $message)';
}

/// Unwraps a standard API envelope `{ code, data, message }`.
///
/// On a successful envelope, replaces `response.data` with the inner [dataKey]
/// value so downstream code works directly with the payload.
///
/// On a non-success code, rejects with an [ApiException] so error handling
/// is unified at the interceptor layer.
///
/// Per-request opt-out: `options.extra['normalize'] = false`.
///
/// ```dart
/// // Server response: {"code": 0, "data": {...}, "message": "ok"}
///
/// final normalize = NormalizePlugin();
/// dio.interceptors.add(normalize);
///
/// final res = await dio.get('/user/1');
/// // res.data == the inner {...} object, code/message stripped
/// ```
class NormalizePlugin extends DioPlugin {
  const NormalizePlugin({
    this.dataKey = 'data',
    this.codeKey = 'code',
    this.messageKey = 'message',
    this.isSuccess,
    this.shouldNormalize,
  });

  /// The key that holds the actual payload inside the envelope.
  final String dataKey;

  /// The key that holds the business-logic status code.
  final String codeKey;

  /// The key that holds the human-readable message.
  final String messageKey;

  /// Returns true if [code] represents success. Defaults to `code == 0`.
  final bool Function(dynamic code)? isSuccess;

  /// Additional condition for applying normalization.
  /// Defaults to responses with JSON content-type.
  final bool Function(RequestOptions options, Response<dynamic> response)?
      shouldNormalize;

  @override
  String get name => 'normalize';

  bool _isSuccess(dynamic code) =>
      isSuccess != null ? isSuccess!(code) : code == 0;

  bool _shouldNormalize(RequestOptions options, Response<dynamic> response) {
    if (options.extra['normalize'] == false) return false;
    if (shouldNormalize != null) return shouldNormalize!(options, response);
    // Default: only process JSON bodies that look like envelopes.
    return response.data is Map &&
        (response.data as Map).containsKey(codeKey);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (!_shouldNormalize(response.requestOptions, response)) {
      return handler.next(response);
    }

    final envelope = response.data as Map;
    final code = envelope[codeKey];
    final message = '${envelope[messageKey] ?? ''}';
    final data = envelope[dataKey];

    if (_isSuccess(code)) {
      // Replace data with the inner payload.
      response.data = data;
      return handler.next(response);
    }

    // Non-success: reject so error-handling code is triggered.
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: ApiException(code: code, message: message, data: data),
        message: message,
        type: DioExceptionType.badResponse,
      ),
      true,
    );
  }
}
