import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/network_error_stub.dart' as stub;
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 纯分类与显式响应格式的回归。
void main() {
  test('[DiomanResponseFactory.normalize] 条件 IO 分类保留网络精度，stub 不猜异常', () {
    final request = DiomanRequest(RequestOptions());
    for (final cause in [
      const SocketException('socket'),
      const HttpException('http'),
      const TlsException('tls'),
      StateError('bug'),
      const FormatException('parse'),
      null
    ]) {
      final result = const DiomanResponseFactory().normalize(request,
          error: DioException(
              requestOptions: request.toRequestOptions(), error: cause));
      expect(
          failureOf(result)?.kind,
          cause is FormatException
              ? DiomanFailureKind.parse
              : cause is SocketException ||
                      cause is HttpException ||
                      cause is TlsException
                  ? DiomanFailureKind.network
                  : DiomanFailureKind.internal);
      expect(stub.isDiomanNetworkError(cause), isFalse);
    }
  });
  test('[DiomanResponseFactory.expectJson] 严格 JSON 只约束 json，显式文本字节流放行', () {
    for (final type in ResponseType.values) {
      final options = RequestOptions(responseType: type);
      final result = const DiomanResponseFactory(expectJson: true).normalize(
          DiomanRequest(options),
          raw: Response<dynamic>(
              requestOptions: options, statusCode: 200, data: 'text'));
      expect(failureOf(result)?.kind,
          type == ResponseType.json ? DiomanFailureKind.parse : null);
      expect(result.ok, type != ResponseType.json);
    }
  });
}
