import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/source.dart';

/// README 中需要逐词元核验的 Dart 代码块总数。
const _readmeDartBlockCount = 13;

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
    test('all README Dart blocks match the compiled snippets and wheel methods',
        () {
      final blocks = RegExp(r'```dart\r?\n([\s\S]*?)```')
          .allMatches(File('README.md').readAsStringSync())
          .map((match) => _tokens(match[1]!))
          .toList();
      expect(blocks, hasLength(_readmeDartBlockCount));
      // 当前没有仅展示而排除的 Dart 块；安装示例是 YAML，不在此匹配范围。
      const snippetBlocks = {
        'wheel': 0,
        'grid': 1,
        'slot': 2,
        'lever': 3,
        'capsule': 4,
        'number_wheel': 5,
        'lots': 6,
        'lotto': 7,
        'compat': 10,
        'extend': 11,
        'testing': 12,
      };
      // 这两块是 wheel 类内的方法，先核验并移除，再比较完整组件。
      const wheelMethodBlocks = {
        'drawFromServer': 8,
        'observePhases': 9,
      };
      expect([...snippetBlocks.values, ...wheelMethodBlocks.values]..sort(),
          orderedEquals(List.generate(_readmeDartBlockCount, (i) => i)),
          reason: '每个 Dart 块必须恰好映射一次');
      for (final entry in snippetBlocks.entries) {
        final source = _tokens(
            File('example/lib/snippets/readme_${entry.key}.dart')
                .readAsStringSync());
        if (entry.key == 'wheel') {
          for (final index in wheelMethodBlocks.values) {
            _removeMethod(source, blocks[index]);
          }
        }
        expect(source, orderedEquals(blocks[entry.value]), reason: entry.key);
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
