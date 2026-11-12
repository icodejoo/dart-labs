import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/svg_source_sniffer.dart';

/// SVG MIME type used for precedence checks. / 优先级检查使用的 SVG 类型。
const _svgContentType = 'image/svg+xml';

/// Minimal SVG payload. / 最小 SVG 载荷。
const _svgSource = '<svg/>';

/// Converts markup to its UTF-8 payload. / 将标记转换为 UTF-8 载荷。
Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

/// Verifies byte signatures and bounded SVG detection. / 验证魔数与有界 SVG 识别。
void main() {
  final signatures = <String, List<int>>{
    'PNG': [0x89, 0x50, 0x4e, 0x47],
    'JPEG': [0xff, 0xd8, 0xff],
    'GIF87a': ascii.encode('GIF87a'),
    'GIF89a': ascii.encode('GIF89a'),
    'WebP': ascii.encode('RIFF1234WEBP'),
    'BMP': ascii.encode('BM'),
    'raw gzip/svgz': [0x1f, 0x8b],
  };
  for (final entry in signatures.entries) {
    test('${entry.key} wins over SVG content type and embedded markup', () {
      final payload = Uint8List.fromList([
        ...entry.value,
        ..._bytes(_svgSource),
      ]);
      expect(isSvgSource(payload), isFalse);
      expect(isSvgSource(payload, contentType: _svgContentType), isFalse);
    });
  }
  for (final source in [
    _svgSource,
    '\uFEFF \t\r\n<?xml version="1.0"?>$_svgSource',
    '<!-- leading comment -->\n$_svgSource',
    '<!DOCTYPE svg PUBLIC "example">$_svgSource',
  ]) {
    test('recognizes supported XML/SVG opening: $source', () {
      expect(isSvgSource(_bytes(source)), isTrue);
      expect(
        isSvgSource(_bytes(source), contentType: 'application/octet-stream'),
        isTrue,
      );
    });
  }
  test('content type containing svg is case insensitive and precedes text', () {
    expect(
      isSvgSource(_bytes('unknown'), contentType: _svgContentType),
      isTrue,
    );
    expect(
      isSvgSource(
        _bytes('unknown'),
        contentType: 'IMAGE/SVG+XML; charset=utf-8',
      ),
      isTrue,
    );
    expect(isSvgSource(_bytes(_svgSource), contentType: 'image/png'), isTrue);
  });
  for (final source in [
    '<html/>',
    '<?xml version="1.0"?><html/>',
    '<!-- comment without SVG -->',
    'arbitrary $_svgSource',
  ]) {
    test('unknown/non-SVG text stays native: $source', () {
      expect(isSvgSource(_bytes(source)), isFalse);
    });
  }
  test('empty and all short signatures remain safe', () {
    expect(isSvgSource(Uint8List(0)), isFalse);
    for (final signature in signatures.values) {
      for (var length = 1; length < signature.length; length++) {
        expect(
          isSvgSource(Uint8List.fromList(signature.take(length).toList())),
          isFalse,
        );
      }
    }
    expect(isSvgSource(Uint8List.fromList([0xff])), isFalse);
  });
  test('root marker must be wholly within the first 4096 payload bytes', () {
    const limit = 4096;
    const opening = '<!--';
    final within =
        '$opening${' ' * (limit - opening.length - _svgSource.length)}'
        '$_svgSource';
    final outside = '$opening${' ' * limit}$_svgSource';
    expect(isSvgSource(_bytes(within)), isTrue);
    expect(isSvgSource(_bytes(outside)), isFalse);
  });
}
