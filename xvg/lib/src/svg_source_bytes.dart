import 'dart:typed_data';

/// Original network image bytes and the optional HTTP content type.
/// 网络图片的原始字节及可选 HTTP 内容类型。
class SvgSourceBytes {
  /// Wraps [bytes] and optional [contentType] without decoding them.
  /// 包装 [bytes] 与可选 [contentType]，不进行解码。
  const SvgSourceBytes(this.bytes, {this.contentType});

  /// Original image payload. / 原始图片载荷。
  final Uint8List bytes;

  /// HTTP content type, or null when absent. / HTTP 内容类型，缺失时为 null。
  final String? contentType;
}
