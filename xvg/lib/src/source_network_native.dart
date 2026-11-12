import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show NetworkImageLoadException;

import 'svg_source_bytes.dart';

/// Shared byte client outside override scopes; consolidate handles HTTP gzip.
/// 覆盖作用域外共享的字节客户端；HTTP gzip 由 consolidate 处理。
final HttpClient _defaultByteClient = HttpClient()..autoUncompress = false;

/// Clients shared within each HttpOverrides scope, without retaining scopes.
/// 每个 HttpOverrides 作用域内共享客户端，不强引用作用域。
final Expando<HttpClient> _overrideByteClients = Expando<HttpClient>();

/// Returns the byte client belonging to the current override scope.
/// 返回当前覆盖作用域所属的字节客户端。
HttpClient get _byteClient {
  final overrides = HttpOverrides.current;
  if (overrides == null) return _defaultByteClient;
  return _overrideByteClients[overrides] ??= HttpClient()
    ..autoUncompress = false;
}

/// 按原有 native 规则加载字节和进度。
Future<SvgSourceBytes> loadNetworkBytes(
  String url,
  Map<String, String>? headers,
  void Function(int, int?)? onBytesReceived,
  Duration timeout,
) async {
  final requestHeaders = headers == null
      ? null
      : Map<String, String>.of(headers);
  final uri = Uri.base.resolve(url);
  var connectionTimedOut = false;
  final request = await _byteClient
      .getUrl(uri)
      .then((request) {
        if (connectionTimedOut) request.abort();
        return request;
      })
      .timeout(
        timeout,
        onTimeout: () {
          connectionTimedOut = true;
          throw TimeoutException('Xvg image connection timed out', timeout);
        },
      );
  try {
    requestHeaders?.forEach(request.headers.add);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(timeout);
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: uri,
      );
    }
    final bytes = await consolidateHttpClientResponseBytes(
      response,
      onBytesReceived: onBytesReceived,
    ).timeout(timeout);
    return SvgSourceBytes(
      bytes,
      contentType: response.headers.value(HttpHeaders.contentTypeHeader),
    );
  } catch (error, stack) {
    request.abort(error, stack);
    rethrow;
  }
}

/// 按原有 native 规则加载文本并关闭客户端。
Future<String> loadNetworkText(
  String url,
  Map<String, String>? requestHeaders,
  Duration timeout,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
    requestHeaders?.forEach(request.headers.add);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Xvg.network: $url returned HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    // 先收集字节再解码，让非法 UTF-8 的异常落在当前 Future 上。
    final bytes = await response
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk))
        .timeout(timeout);
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}
