import 'dart:convert';
import 'dart:typed_data';

/// Maximum prefix inspected for SVG markup. / SVG 标记的最大检查前缀。
const _svgPrefixLength = 4096;

/// SVG root marker shared by prefix and content checks.
/// 前缀与内容检查共用的 SVG 根标记。
const _svgRoot = '<svg';

/// Signatures that always select native image decoding.
/// 始终选择原生图片解码的签名。
const _nativeSignatures = <List<int>>[
  [0x89, 0x50, 0x4e, 0x47], // PNG
  [0xff, 0xd8, 0xff], // JPEG
  [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], // GIF87a
  [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], // GIF89a
  [0x42, 0x4d], // BMP
  [0x1f, 0x8b], // gzip/svgz is unsupported; let the engine report the error.
];

/// Checks [bytes] for [signature] starting at [offset].
/// 检查 [bytes] 在 [offset] 处是否匹配 [signature]。
bool _hasSignature(Uint8List bytes, List<int> signature, [int offset = 0]) {
  if (bytes.length < offset + signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[offset + index] != signature[index]) return false;
  }
  return true;
}

/// Whether [bytes] should be decoded as SVG, optionally using [contentType].
/// Raster signatures and unsupported raw gzip/svgz always select native decoding.
/// Otherwise SVG content types win, or SVG markup must occur within 4096 bytes
/// after a BOM/whitespace and a supported XML/SVG/comment opening.
/// 根据 [bytes] 和可选 [contentType] 判断是否按 SVG 解码；位图魔数及不支持的
/// 原始 gzip/svgz 始终走原生。其余先识别 SVG 类型，再识别前 4096 字节内、
/// BOM/空白之后以支持的 XML/SVG/注释开头且含 SVG 根标记的文本。
bool isSvgSource(Uint8List bytes, {String? contentType}) {
  if (_nativeSignatures.any((signature) => _hasSignature(bytes, signature))) {
    return false;
  }
  if (_hasSignature(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      _hasSignature(bytes, const [0x57, 0x45, 0x42, 0x50], 8)) {
    return false;
  }
  if (contentType?.toLowerCase().contains('svg') ?? false) return true;
  final prefix = utf8
      .decode(
        Uint8List.sublistView(
          bytes,
          0,
          bytes.length < _svgPrefixLength ? bytes.length : _svgPrefixLength,
        ),
        allowMalformed: true,
      )
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .trimLeft();
  return (prefix.startsWith(_svgRoot) ||
          prefix.startsWith('<?xml') ||
          prefix.startsWith('<!DOCTYPE svg') ||
          prefix.startsWith('<!--')) &&
      prefix.contains(_svgRoot);
}
