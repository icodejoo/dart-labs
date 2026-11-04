import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

/// 公共导出清单测试：只通过 package:countman/countman.dart 使用样式本体。
void main() {
  test('RingStyle / BarStyle 本体可直接从 countman.dart 使用，且与别名同一类型', () {
    const RingStyle ring = RingStyle(size: 80);
    const BarStyle bar = BarStyle(width: 200);
    expect(ring.size, 80);
    expect(bar.width, 200);
    // 别名与本体是同一类型，互相赋值不报错。
    const RingCounterStyle ringAlias = ring;
    const RingCountdownStyle ringAlias2 = ring;
    const BarCounterStyle barAlias = bar;
    const BarCountdownStyle barAlias2 = bar;
    expect(identical(ringAlias, ringAlias2), isTrue);
    expect(identical(barAlias, barAlias2), isTrue);
  });
}
