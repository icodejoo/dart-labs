import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show NetworkImageLoadException;

import 'svg_source_bytes.dart';

/// 浏览器 fetch 入口，由浏览器处理 CORS 和 HTTP 压缩。
@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, JSObject options);

/// 可中止的浏览器请求。
@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

/// fetch 响应的最小互操作契约。
extension type _Response._(JSObject _) implements JSObject {
  external int get status;
  external _Headers get headers;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// 读取响应内容类型。
extension type _Headers._(JSObject _) implements JSObject {
  external JSString? get(JSString name);
}

/// 通过 fetch 加载字节，超时中止请求；进度在完整响应到达后报告。
Future<SvgSourceBytes> loadNetworkBytes(
  String url,
  Map<String, String>? headers,
  void Function(int, int?)? onBytesReceived,
  Duration timeout,
) async {
  final uri = Uri.base.resolve(url);
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw UnsupportedError('Xvg web network requires HTTP(S): $uri');
  }
  final controller = _AbortController();
  try {
    final response = await _fetch(
      uri.toString().toJS,
      {
            'headers': headers ?? <String, String>{},
            'signal': controller.signal,
          }.jsify()
          as JSObject,
    ).toDart.timeout(timeout);
    if (response.status != 200) {
      throw NetworkImageLoadException(statusCode: response.status, uri: uri);
    }
    final buffer = await response.arrayBuffer().toDart.timeout(timeout);
    final Uint8List bytes = buffer.toDart.asUint8List();
    onBytesReceived?.call(bytes.length, bytes.length);
    return SvgSourceBytes(
      bytes,
      contentType: response.headers.get('content-type'.toJS)?.toDart,
    );
  } catch (_) {
    controller.abort();
    rethrow;
  }
}

/// 严格 UTF-8 解码与 native 保持一致。
Future<String> loadNetworkText(
  String url,
  Map<String, String>? headers,
  Duration timeout,
) async =>
    utf8.decode((await loadNetworkBytes(url, headers, null, timeout)).bytes);
