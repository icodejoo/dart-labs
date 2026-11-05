import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI style reads are confined to lookup and danmaku data boundary', () {
    final errors = <String>[];
    for (final file
        in Directory('lib/src/ui')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      if (path.endsWith('/style/style.dart')) continue;
      final code = file
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (RegExp(
        r'options\.(theme|strings|gesture|controls|danmaku)\b',
      ).hasMatch(code)) {
        errors.add(path);
      }
      if (!path.endsWith('/components/danmaku.dart') &&
          code.contains('movaLegacyOptionsOf(')) {
        errors.add(path);
      }
    }
    expect(errors, isEmpty);
  });
}
