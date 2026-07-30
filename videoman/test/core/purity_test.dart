import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core never imports flutter, and only mpv_kernel imports media_kit', () {
    final files = Directory('lib/src/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(src.contains("package:flutter/"), isFalse, reason: '${f.path} imports flutter');
      if (!f.path.replaceAll(r'\', '/').endsWith('kernel/mpv_kernel.dart')) {
        expect(src.contains("package:media_kit"), isFalse, reason: '${f.path} imports media_kit');
      }
    }
  });
}
