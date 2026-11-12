import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  test(
    'quality compatibility constants retain Chinese labels for one release',
    () {
      expect(kMovaAutoQualityLabel, '自动');
      expect(kMovaUnknownQualityLabel, '未知');
      expect(MovaQuality.auto().label, kMovaAutoQualityLabel);
      final qualities = parseHlsMasterPlaylist(
        '#EXTM3U\n#EXT-X-STREAM-INF:CODECS="avc1"\na.m3u8',
      );
      expect(qualities.last.label, kMovaUnknownQualityLabel);
    },
  );
}
