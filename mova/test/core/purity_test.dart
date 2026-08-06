import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Files still allowed to import `package:media_kit`. `mpv_kernel.dart` is
/// the plan's permanent exception — every other file in `lib/src/core/**`
/// must stay media_kit-free.
///
/// 仍允许 import `package:media_kit` 的文件。`mpv_kernel.dart` 是计划里
/// 永久的例外——`lib/src/core/**` 下其余文件都必须不含 media_kit 依赖。
const _mediaKitExceptions = {
  'kernel/mpv_kernel.dart',
};

/// The `import`/`export` lines of [source], ignoring comments and any other
/// prose that merely mentions a package name.
///
/// [source] 中真正的 `import`/`export` 行，忽略注释里单纯提及包名的说明文字。
Iterable<String> _importLines(String source) => source
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('import ') || l.startsWith('export '));

void main() {
  test('core never imports flutter, and only the declared exceptions import media_kit', () {
    final files = Directory('lib/src/core')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final imports = _importLines(f.readAsStringSync()).toList();
      final flutterImport = imports.where((l) => l.contains('package:flutter/'));
      expect(flutterImport, isEmpty, reason: '${f.path} imports flutter: $flutterImport');
      final normalized = f.path.replaceAll(r'\', '/');
      final isException = _mediaKitExceptions.any(normalized.endsWith);
      if (!isException) {
        final mediaKitImport = imports.where((l) => l.contains('package:media_kit'));
        expect(mediaKitImport, isEmpty, reason: '${f.path} imports media_kit: $mediaKitImport');
      }
    }
  });
}
