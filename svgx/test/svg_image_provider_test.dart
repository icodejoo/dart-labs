import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

void main() {
  group('SvgImageProvider value equality', () {
    test('two .string providers over the same source are equal', () {
      const a = SvgImageProvider.string('<svg/>', width: 24, height: 24);
      const b = SvgImageProvider.string('<svg/>', width: 24, height: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('.string providers differing only in colorFilter are not equal', () {
      const a = SvgImageProvider.string('<svg/>');
      const b = SvgImageProvider.string(
        '<svg/>',
        colorFilter: ColorFilter.mode(Color(0xFFFF0000), BlendMode.srcIn),
      );
      expect(a, isNot(equals(b)));
    });

    test('two .asset providers over the same name/bundle/package are equal', () {
      final a = SvgImageProvider.asset('icon.svg', package: 'pkg');
      final b = SvgImageProvider.asset('icon.svg', package: 'pkg');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('.asset providers over different names are not equal', () {
      final a = SvgImageProvider.asset('a.svg');
      final b = SvgImageProvider.asset('b.svg');
      expect(a, isNot(equals(b)));
    });

    test('.network providers over the same url/headers are equal', () {
      final a = SvgImageProvider.network(
        'https://example.com/a.svg',
        headers: const {'x': '1'},
      );
      final b = SvgImageProvider.network(
        'https://example.com/a.svg',
        headers: const {'x': '1'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two .file providers over the same path are equal', () {
      final a = SvgImageProvider.file(File('icon.svg'), width: 24);
      final b = SvgImageProvider.file(File('icon.svg'), width: 24);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('.file providers over different paths are not equal', () {
      final a = SvgImageProvider.file(File('a.svg'));
      final b = SvgImageProvider.file(File('b.svg'));
      expect(a, isNot(equals(b)));
    });

    test(
      'two .memory providers over the same decoded bytes are equal',
      () {
        final bytes = utf8.encode('<svg/>');
        final a = SvgImageProvider.memory(bytes, width: 24);
        final b = SvgImageProvider.memory(bytes, width: 24);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      },
    );

    test('.memory providers over different bytes are not equal', () {
      final a = SvgImageProvider.memory(utf8.encode('<svg/>'));
      final b = SvgImageProvider.memory(utf8.encode('<svg></svg>'));
      expect(a, isNot(equals(b)));
    });
  });
}
