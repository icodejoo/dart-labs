import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 设计文档要求齐全的五份文档（相对包根）。
const List<String> _requiredDocs = [
  'docs/ARCHITECTURE.md',
  'docs/FIDELITY.md',
  'docs/IMPLEMENTATION_GUIDE.md',
  'docs/TEST_STRATEGY.md',
  'docs/README.md',
];

/// 布局与运动层不得出现的绘制类型，3D 等其它渲染后端才能复用这些层。
final RegExp _drawingTypes = RegExp(r'\b(Canvas|Picture|PictureRecorder)\b');

/// 匹配 Markdown 行内链接的目标，例如 `[文本](FIDELITY.md#anchor)`。
final RegExp _markdownLink = RegExp(r'\]\(([^)\s]+)\)');

/// 去掉 Dart 注释，避免文档注释里提到 Canvas 被误判。
String _stripComments(String source) =>
    source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').split('\n').map((line) {
      final index = line.indexOf('//');
      return index < 0 ? line : line.substring(0, index);
    }).join('\n');

/// 收集需要保持"与渲染后端无关"的源文件。
List<File> _backendNeutralFiles() {
  final files = <File>[
    File('lib/src/core/game/layout.dart'),
    File('lib/src/core/game/frame.dart'),
  ];
  for (final entity in Directory('lib/src').listSync()) {
    if (entity is! Directory) continue;
    for (final sub in const ['layout', 'motion']) {
      final dir = Directory('${entity.path}/$sub');
      if (!dir.existsSync()) continue;
      files.addAll(dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')));
    }
  }
  return files;
}

/// 设计不变量中原本只能人工评审的两项，改为可执行检查。
void main() {
  group('design invariants', () {
    test(
        'layout and frame types contain no Canvas or Picture so other backends can reuse them',
        () {
      final files = _backendNeutralFiles();
      expect(files, isNotEmpty);
      final offenders = <String>[];
      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: file.path);
        if (_drawingTypes.hasMatch(_stripComments(file.readAsStringSync()))) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '布局/运动/帧层不得依赖 Canvas、Picture：$offenders');
    });

    test('the five design documents exist and every relative link resolves',
        () {
      for (final doc in _requiredDocs) {
        expect(File(doc).existsSync(), isTrue, reason: doc);
      }
      final broken = <String>[];
      for (final doc in _requiredDocs) {
        final dir = File(doc).parent.path;
        for (final match
            in _markdownLink.allMatches(File(doc).readAsStringSync())) {
          final target = match.group(1)!;
          if (target.startsWith('http') ||
              target.startsWith('#') ||
              target.startsWith('mailto:')) {
            continue;
          }
          final path = target.split('#').first;
          if (path.isEmpty) continue;
          if (!File('$dir/$path').existsSync() &&
              !Directory('$dir/$path').existsSync()) {
            broken.add('$doc -> $target');
          }
        }
      }
      expect(broken, isEmpty, reason: '文档内相对链接失效：$broken');
    });
  });
}
