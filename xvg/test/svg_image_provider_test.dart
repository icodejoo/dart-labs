import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart';

void main() {
  group('SVG ImageProvider value equality', () {
    test('two StringXvg over the same source are equal', () {
      const a = StringXvg('<svg/>', width: 24, height: 24);
      const b = StringXvg('<svg/>', width: 24, height: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('StringXvg differing only in colorFilter are not equal', () {
      const a = StringXvg('<svg/>');
      const b = StringXvg(
        '<svg/>',
        colorFilter: ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcIn),
      );
      expect(a, isNot(equals(b)));
    });

    test('two AssetXvg over the same name/bundle/package are equal', () {
      const a = AssetXvg('icon.svg', package: 'pkg');
      const b = AssetXvg('icon.svg', package: 'pkg');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('AssetXvg over different names are not equal', () {
      const a = AssetXvg('a.svg');
      const b = AssetXvg('b.svg');
      expect(a, isNot(equals(b)));
    });

    test('two NetworkXvg over the same url/headers are equal', () {
      const a = NetworkXvg('https://example.com/a.svg', headers: {'x': '1'});
      const b = NetworkXvg('https://example.com/a.svg', headers: {'x': '1'});
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two FileXvg over the same path are equal', () {
      final a = FileXvg(File('icon.svg'), width: 24);
      final b = FileXvg(File('icon.svg'), width: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('FileXvg over different paths are not equal', () {
      final a = FileXvg(File('a.svg'));
      final b = FileXvg(File('b.svg'));
      expect(a, isNot(equals(b)));
    });

    test('two MemoryXvg over the same bytes instance are equal', () {
      final bytes = utf8.encode('<svg/>');
      final a = MemoryXvg(bytes, width: 24);
      final b = MemoryXvg(bytes, width: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('MemoryXvg over different bytes are not equal', () {
      final a = MemoryXvg(utf8.encode('<svg/>'));
      final b = MemoryXvg(utf8.encode('<svg></svg>'));
      expect(a, isNot(equals(b)));
    });
  });
}
