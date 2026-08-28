import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

void main() {
  group('SVG ImageProvider value equality', () {
    test('two StringSvgx over the same source are equal', () {
      const a = StringSvgx('<svg/>', width: 24, height: 24);
      const b = StringSvgx('<svg/>', width: 24, height: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('StringSvgx differing only in colorFilter are not equal', () {
      const a = StringSvgx('<svg/>');
      const b = StringSvgx(
        '<svg/>',
        colorFilter: ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcIn),
      );
      expect(a, isNot(equals(b)));
    });

    test('two AssetSvgx over the same name/bundle/package are equal', () {
      const a = AssetSvgx('icon.svg', package: 'pkg');
      const b = AssetSvgx('icon.svg', package: 'pkg');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('AssetSvgx over different names are not equal', () {
      const a = AssetSvgx('a.svg');
      const b = AssetSvgx('b.svg');
      expect(a, isNot(equals(b)));
    });

    test('two NetworkSvgx over the same url/headers are equal', () {
      const a = NetworkSvgx('https://example.com/a.svg', headers: {'x': '1'});
      const b = NetworkSvgx('https://example.com/a.svg', headers: {'x': '1'});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two FileSvgx over the same path are equal', () {
      final a = FileSvgx(File('icon.svg'), width: 24);
      final b = FileSvgx(File('icon.svg'), width: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('FileSvgx over different paths are not equal', () {
      final a = FileSvgx(File('a.svg'));
      final b = FileSvgx(File('b.svg'));
      expect(a, isNot(equals(b)));
    });

    test('two MemorySvgx over the same bytes instance are equal', () {
      final bytes = utf8.encode('<svg/>');
      final a = MemorySvgx(bytes, width: 24);
      final b = MemorySvgx(bytes, width: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('MemorySvgx over different bytes are not equal', () {
      final a = MemorySvgx(utf8.encode('<svg/>'));
      final b = MemorySvgx(utf8.encode('<svg></svg>'));
      expect(a, isNot(equals(b)));
    });
  });
}
