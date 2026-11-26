import 'package:bench_app/async_threshold_bench.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证校准输入满足准确分档、内容互异和可绘制的要求。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('calibration SVGs have exact lengths and different geometry', () async {
    for (final sizeKiB in asyncThresholdSizesKiB) {
      final first = makeAsyncThresholdSvg(sizeKiB, 100);
      final second = makeAsyncThresholdSvg(sizeKiB, 200);
      expect(first.length, sizeKiB * 1024);
      expect(second.length, first.length);
      expect(first, isNot(second));
      expect(first, contains('<path '));
      final info = await vg.loadPicture(SvgStringLoader(first), null);
      try {
        expect(info.size.width, greaterThan(0));
        expect(info.size.height, greaterThan(0));
        expect(info.picture.approximateBytesUsed, greaterThan(256));
      } finally {
        info.picture.dispose();
      }
    }
  });
}
