import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI 的旧交互接口访问只允许集中在 chrome 回落口', () {
    final access = RegExp(
      r'\b(?:_?api|widget\.api)\.(showControls|hideControls|showHud|setDragging|uiStates?)\b',
    );
    final violations = <String>[];
    for (final file in Directory(
      'lib/src/ui',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.replaceAll(r'\', '/').endsWith('/chrome/chrome.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trimLeft().startsWith('//') && access.hasMatch(lines[i])) {
          violations.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(violations, isEmpty);
  });
}
