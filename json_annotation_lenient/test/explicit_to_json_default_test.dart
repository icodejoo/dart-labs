// Exercises the `explicit_to_json` default this builder fills in when a
// consuming project's build.yaml doesn't mention it at all. Imports `src/`
// directly to reach `debugResolveJsonSerializableConfig`, the test-only hook
// into the otherwise library-private config-merging step.
//
// 覆盖消费方 build.yaml 完全没写 `explicit_to_json:` 时本 builder 补上的默认值。
// 直接 import `src/` 是为了拿到 `debugResolveJsonSerializableConfig`——那个
// 通往库私有配置合并逻辑的测试专用入口。

import 'package:json_annotation_lenient/src/auto_default_builder.dart';
import 'package:test/test.dart';

void main() {
  group('explicit_to_json default', () {
    test('defaults to true when the consumer never mentions it', () {
      final resolved = debugResolveJsonSerializableConfig(const {});
      expect(resolved['explicit_to_json'], isTrue);
    });

    test('an explicit false is honored, not overridden', () {
      final resolved = debugResolveJsonSerializableConfig(const {
        'explicit_to_json': false,
      });
      expect(resolved['explicit_to_json'], isFalse);
    });

    test('an explicit true is left untouched', () {
      final resolved = debugResolveJsonSerializableConfig(const {
        'explicit_to_json': true,
      });
      expect(resolved['explicit_to_json'], isTrue);
    });

    test('still strips this builder\'s own options keys', () {
      final resolved = debugResolveJsonSerializableConfig(const {
        'run_only_if_triggered': true,
        'lenient': {
          'int': {'enabled': true},
        },
        'field_rename': 'snake',
      });

      expect(resolved.containsKey('run_only_if_triggered'), isFalse);
      expect(resolved.containsKey('lenient'), isFalse);
      expect(resolved['field_rename'], 'snake');
      expect(resolved['explicit_to_json'], isTrue);
    });
  });
}
