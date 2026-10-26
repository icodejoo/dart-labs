import 'dart:io';

import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

// 子类不能与基类样式相等，保持所有样式的运行时类型约束一致。
class _DerivedStyle extends AnimatedCounterStyle {
  const _DerivedStyle();
}

void main() {
  test('Simplify 5: animated style equality uses the shared type contract', () {
    final base = AnimatedCounterStyle();
    final copy = base.copyWith();
    expect(base, copy);
    expect(base.hashCode, copy.hashCode);
    expect(base == const _DerivedStyle(), isFalse);
    expect(const _DerivedStyle() == base, isFalse);
  });

  // 弃用属于源码元数据，直接验证声明而不依赖运行时反射。
  test('Simplify 3-4: inert public parameters carry deprecation metadata', () {
    final odometer =
        File('lib/src/widgets/odometer_counter.dart').readAsStringSync();
    for (final field in [
      'plugin',
      'controller',
      'slideCurve',
      'onUpdate',
      'onReady',
      'onCancel',
      'letterWidth',
      'verticalOffset',
      'fadeEnabled',
      'bounceElasticity',
    ]) {
      expect(
        RegExp("@Deprecated\\('[^']+'\\)\\s+final [^;]+\\b$field;")
            .hasMatch(odometer),
        isTrue,
        reason: '$field must remain available with a migration notice',
      );
    }
    final base = File('lib/src/widgets/animated_counter/_base_counter.dart')
        .readAsStringSync();
    expect(
      RegExp("@Deprecated\\('[^']+'\\)\\s+final double bounceElasticity;")
          .hasMatch(base),
      isTrue,
    );
  });

  // 防止恒真断言与重复清理再次掩盖渲染异常或污染后续用例。
  test('Simplify 6: API tests use real assertions and one shared cleanup', () {
    final source = File('test/api_expansion_test.dart').readAsStringSync();
    expect(source, isNot(contains('testerOk')));
    expect(
        RegExp(r'tearDown\(Countman.destroy\)').allMatches(source).length, 1);
    expect(source, isNot(contains('Countman.destroy();')));
  });
}
