// Exercises the from-scratch, simplified `analysis_options.yaml`
// `formatter:` reader — see `_readFormatterSection` in
// `auto_default_builder.dart` for why this package can't just call into
// `dart_style`'s own (private) reader. Imports `src/` directly to reach
// `debugReadFormatterSection`.
//
// 覆盖从零实现的简化版 `analysis_options.yaml` `formatter:` 读取逻辑——
// 为什么这个包没法直接调用 `dart_style` 自己（私有）的读取逻辑，见
// `auto_default_builder.dart` 里 `_readFormatterSection` 的说明。直接
// import `src/` 是为了拿到 `debugReadFormatterSection`。

import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:json_annotation_lenient/src/auto_default_builder.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'json_annotation_lenient_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File writeYaml(String name, String content) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync(content);
    return file;
  }

  group('analysis_options.yaml formatter: reading', () {
    test('reads page_width and trailing_commas from the formatter section', () {
      final file = writeYaml('analysis_options.yaml', '''
formatter:
  page_width: 100
  trailing_commas: preserve
''');

      final result = debugReadFormatterSection(file);
      expect(result.pageWidth, 100);
      expect(result.trailingCommas, TrailingCommas.preserve);
    });

    test('automate parses to TrailingCommas.automate', () {
      final file = writeYaml('analysis_options.yaml', '''
formatter:
  trailing_commas: automate
''');

      expect(
        debugReadFormatterSection(file).trailingCommas,
        TrailingCommas.automate,
      );
    });

    test('missing formatter section yields nulls, not an error', () {
      final file = writeYaml(
        'analysis_options.yaml',
        'include: package:lints/recommended.yaml\n',
      );

      final result = debugReadFormatterSection(file);
      expect(result.pageWidth, isNull);
      expect(result.trailingCommas, isNull);
    });

    test(
      'an unrecognized trailing_commas value yields null rather than throwing',
      () {
        final file = writeYaml('analysis_options.yaml', '''
formatter:
  trailing_commas: nonsense
''');

        expect(debugReadFormatterSection(file).trailingCommas, isNull);
      },
    );

    test(
      'follows a single local include: path when the file itself lacks the key',
      () {
        writeYaml('shared.yaml', '''
formatter:
  page_width: 120
''');
        final file = writeYaml(
          'analysis_options.yaml',
          'include: shared.yaml\n',
        );

        expect(debugReadFormatterSection(file).pageWidth, 120);
      },
    );

    test(
      "does not follow a package: include (can't resolve it without a build context)",
      () {
        final file = writeYaml(
          'analysis_options.yaml',
          'include: package:lints/recommended.yaml\n',
        );

        final result = debugReadFormatterSection(file);
        expect(result.pageWidth, isNull);
        expect(result.trailingCommas, isNull);
      },
    );

    test("the file's own formatter section beats its include", () {
      writeYaml('shared.yaml', '''
formatter:
  page_width: 120
''');
      final file = writeYaml('analysis_options.yaml', '''
include: shared.yaml
formatter:
  page_width: 100
''');

      expect(debugReadFormatterSection(file).pageWidth, 100);
    });

    test('a self-referential include does not loop forever', () {
      final file = writeYaml(
        'analysis_options.yaml',
        'include: analysis_options.yaml\n',
      );

      expect(debugReadFormatterSection(file).pageWidth, isNull);
    });
  });
}
