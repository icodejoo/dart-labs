import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/quality.dart';

/// Verifies HLS sorting never compares pixel height with bandwidth.
///
/// 验证 HLS 排序不会跨单位比较像素高度与码率。
void main() {
  test(
    'A14 HLS sorts video before heightless variants and breaks ties by bandwidth',
    () {
      final qualities = parseHlsMasterPlaylist('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=128000
audio-low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080
1080-low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=9000000
heightless-high.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
1080-high.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720
720.m3u8
#EXT-X-STREAM-INF:CODECS="unknown"
unknown.m3u8
''');
      expect(qualities.first.isAuto, isTrue);
      expect(qualities.skip(1).map((q) => q.uri), [
        '1080-high.m3u8',
        '1080-low.m3u8',
        '720.m3u8',
        'heightless-high.m3u8',
        'audio-low.m3u8',
        'unknown.m3u8',
      ]);
    },
  );
}
