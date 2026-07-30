import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Files still allowed to import `package:media_kit` while the phase A
/// refactor is in flight. `mpv_kernel.dart` is the plan's permanent
/// exception; `controller.dart` is the legacy 0.1.0 controller, deleted by
/// Task 18 (`refactor(videoman): drop legacy controls, add deprecated
/// VmController facade`) — until then it still talks to media_kit directly.
///
/// 阶段 A 重构进行期间仍允许 import `package:media_kit` 的文件。
/// `mpv_kernel.dart` 是计划里永久的例外；`controller.dart` 是 0.1.0 遗留
/// 控制器，由 Task 18 删除，删除前它仍直连 media_kit。
const _mediaKitExceptions = {
  'kernel/mpv_kernel.dart',
  'controller.dart',
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
