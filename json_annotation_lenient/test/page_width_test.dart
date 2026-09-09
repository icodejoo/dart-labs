// Exercises `options.page_width` — the builder's own workaround for
// `dart_style`'s public `DartFormatter` API not reading a project's
// `analysis_options.yaml` `formatter: page_width:` setting at all (that
// logic is private to `dart_style`'s own CLI). Imports `src/` directly to
// reach `debugReadPageWidth` / `debugResolveJsonSerializableConfig`.
//
// 覆盖 `options.page_width`——针对 `dart_style` 公开的 `DartFormatter` API
// 完全不读项目 `analysis_options.yaml` 里 `formatter: page_width:` 配置这件事
// （那段读取逻辑是 `dart_style` 自己 CLI 私有的）做的绕行方案。直接
// import `src/` 是为了拿到 `debugReadPageWidth`/`debugResolveJsonSerializableConfig`。

import 'package:json_annotation_lenient/src/auto_default_builder.dart';
import 'package:test/test.dart';

void main() {
  group('options.page_width', () {
    test(
      'absent yields null (DartFormatter falls back to its own default)',
      () {
        expect(debugReadPageWidth(const {}), isNull);
      },
    );

    test('a configured int is read through', () {
      expect(debugReadPageWidth(const {'page_width': 100}), 100);
    });

    test('a mistyped value is ignored rather than thrown', () {
      expect(debugReadPageWidth(const {'page_width': '100'}), isNull);
    });

    test('is stripped out of the JsonSerializableGenerator config', () {
      final resolved = debugResolveJsonSerializableConfig(const {
        'page_width': 100,
      });
      expect(resolved.containsKey('page_width'), isFalse);
    });
  });
}
