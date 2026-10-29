import 'package:test/test.dart';
import '../support/b5_powerset.dart';

/// 位掩码、脚本 baseline 和真正的 512 × 9 不变量组合。
void main() {
  final masks = subsets(interactionNames.length);
  const title = '[DiomanPlugin powerset]';
  test('$title 子集唯一且含空集与全集', () {
    expect(masks.toSet().length, masks.length);
    expect(masks, containsAll([0, subsetCount - 1]));
  });
  test('$title 恰好九个交互插件与 512 子集', () {
    expect(interactionNames.length, 9);
    expect(masks.length, subsetCount);
  });
  test('$title 依赖缺失的子集不生成', () {
    expect(
        subsets(2, {
          1: {0}
        }),
        [0, 1, 3]);
  });
  for (final flow in PowerFlow.values) {
    test('$title baseline ${flow.name}', () async {
      final f = PowerFixture(0, flow);
      try {
        await f.run();
        expect(
            (await Future.wait(f.requests)).map((r) => r.kind), flow.baseline);
        await f.check();
      } finally {
        await f.dispose();
      }
    });
  }
  for (final mask in masks) {
    for (final flow in PowerFlow.values) {
      test('$title mask=$mask ${flow.name}', () async {
        final f = PowerFixture(mask, flow);
        try {
          await f.run();
          await f.check();
        } finally {
          await f.dispose();
        }
      });
    }
  }
}
