import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/source.dart';

/// 返回去掉注释及空白后的 Dart 词元。
List<String> _tokens(String source) =>
    sourceTokens(source).map((token) => token.text).toList();

/// 删除与 README 业务方法完全一致的一段词元；缺失时断言失败。
void _removeMethod(List<String> source, List<String> method) {
  final start = List.generate(source.length - method.length + 1, (i) => i)
      .where((i) =>
          List.generate(method.length, (j) => source[i + j] == method[j])
              .every((equal) => equal))
      .firstOrNull;
  expect(start, isNotNull, reason: 'README 的业务方法必须逐词元保留');
  source.removeRange(start!, start + method.length);
}

/// 防止示例与发布说明的真实片段或公共入口发生漂移。
void main() {
  group('README snippets', () {
    test('six Dart blocks match the independently compiled example sources',
        () {
      final blocks = RegExp(r'```dart\r?\n([\s\S]*?)```')
          .allMatches(File('README.md').readAsStringSync())
          .map((match) => _tokens(match[1]!))
          .toList();
      expect(blocks, hasLength(6));
      const names = ['wheel', 'grid', 'slot', 'compat'];
      const indices = [0, 1, 2, 5];
      for (var i = 0; i < names.length; i++) {
        final source = _tokens(
            File('example/lib/snippets/readme_${names[i]}.dart')
                .readAsStringSync());
        if (i == 0) {
          _removeMethod(source, blocks[3]);
          _removeMethod(source, blocks[4]);
        }
        expect(source, orderedEquals(blocks[indices[i]]), reason: names[i]);
      }
    });
    test('every example Dart import uses the exported package API', () {
      final files = [
        Directory('example/lib'),
        Directory('example/integration_test')
      ]
          .expand((directory) =>
              directory.listSync(recursive: true).whereType<File>())
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(
            file.readAsStringSync(), isNot(contains('package:luckdraw/src/')),
            reason: file.path);
      }
    });
  });
}
