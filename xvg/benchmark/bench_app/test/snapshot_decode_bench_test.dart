import 'dart:ui';

import 'package:bench_app/snapshot_decode_bench.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证快照尺寸预算和首帧探针的匹配边界。
void main() {
  test('trims a full-width illustration to the physical viewport', () {
    expect(
      snapshotGeometry(
        logicalWidth: 375,
        dpr: 2.8125,
        intrinsic: const Size(375, 2114),
        viewportHeight: 2340,
      ),
      (width: 1055, fullHeight: 5946, viewHeight: 2340),
    );
  });

  test('preserves the full physical height of a 48 px icon', () {
    expect(
      snapshotGeometry(
        logicalWidth: 48,
        dpr: 2.8125,
        intrinsic: const Size.square(24),
        viewportHeight: 2340,
      ),
      (width: 135, fullHeight: 135, viewHeight: 135),
    );
  });

  test('only matches paint timestamps inside the frame build interval', () {
    expect(snapshotPaintInFrame(15, 10, 20), isTrue);
    expect(snapshotPaintInFrame(9, 10, 20), isFalse);
    expect(snapshotPaintInFrame(21, 10, 20), isFalse);
  });
}
