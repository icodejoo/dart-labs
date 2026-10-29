import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

/// 文档块都是完整编译单元；只有紧邻 docs:old 标记的旧写法跳过。
/// 无隐式包裹、无按编译结果跳过；空块也计入并交给分析器。
void main() {
  test('[DiomanCall] 四份文档的 Dart 示例均能编译', () async {
    final root = Directory.current;
    final parent = await Directory('${root.path}/.dart_tool/docs-b6')
        .create(recursive: true);
    final temporary = await parent.createTemp('examples-');
    var compiled = 0;
    var skipped = 0;
    final counts = <String, Object>{};
    try {
      for (final path in [
        'README.md',
        'README.zh-CN.md',
        'docs/guides/migrating-to-pipeline.md',
        'CHANGELOG.md'
      ]) {
        final source = File(path).readAsStringSync();
        final matches = RegExp(r'```dart\r?\n([\s\S]*?)```').allMatches(source);
        var localCompiled = 0;
        var localSkipped = 0;
        for (final match in matches) {
          final before = source.substring(0, match.start).trimRight();
          if (before.endsWith('<!-- docs:old -->')) {
            skipped++;
            localSkipped++;
            continue;
          }
          compiled++;
          localCompiled++;
          File('${temporary.path}/example_$compiled.dart')
              .writeAsStringSync(match.group(1)!);
        }
        const expectedOld = <String, int>{
          'README.md': 0,
          'README.zh-CN.md': 0,
          'docs/guides/migrating-to-pipeline.md': 18,
          'CHANGELOG.md': 7,
        };
        expect(localSkipped, expectedOld[path], reason: path);
        counts[path] = {'compiled': localCompiled, 'skippedOld': localSkipped};
      }
      expect(compiled, greaterThan(0));
      expect(skipped, 25, reason: '旧代码跳过必须显式登记，不能悄悄增加');
      final result = await Process.run(Platform.resolvedExecutable,
          ['analyze', '--format=machine', temporary.path],
          workingDirectory: root.path);
      final output = '${result.stdout}\n${result.stderr}';
      final errors = const LineSplitter()
          .convert(output)
          .where((line) => line.startsWith('ERROR|'))
          .toList();
      final evidence = Directory('docs/reports/pipeline-b6-evidence')
        ..createSync(recursive: true);
      File('${evidence.path}/documentation-examples.json')
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'files': counts,
        'compiled': compiled,
        'skippedOld': skipped,
        'errors': errors,
        'exitCode': result.exitCode
      }));
      expect(errors, isEmpty, reason: output);
      expect(result.exitCode, 0, reason: output);
    } finally {
      await temporary.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
