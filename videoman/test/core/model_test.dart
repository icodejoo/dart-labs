import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/videoman.dart';

const _master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720
720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1920x1080,CODECS="avc1.4d401f,mp4a.40.2"
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=640000,RESOLUTION=640x360
360.m3u8
''';

const _mediaPlaylist = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:9.9,
seg0.ts
#EXTINF:9.9,
seg1.ts
''';

void main() {
  group('parseHlsMasterPlaylist', () {
    test('lists auto first, then variants highest-first', () {
      final qs = parseHlsMasterPlaylist(_master, base: Uri.parse('https://h/media/master.m3u8'));
      expect(qs.first.isAuto, isTrue);
      expect(qs.map((q) => q.label).toList(), ['自动', '1080p', '720p', '360p']);
    });

    test('resolves relative variant URIs against the base', () {
      final qs = parseHlsMasterPlaylist(_master, base: Uri.parse('https://h/media/master.m3u8'));
      final p1080 = qs.firstWhere((q) => q.label == '1080p');
      expect(p1080.uri, 'https://h/media/1080/index.m3u8');
      expect(p1080.width, 1920);
      expect(p1080.height, 1080);
      expect(p1080.bandwidth, 2560000);
    });

    test('returns empty for a non-master media playlist', () {
      expect(parseHlsMasterPlaylist(_mediaPlaylist), isEmpty);
    });
  });

  group('VmBufferingAbr', () {
    test('signals a downshift after `threshold` stalls (rising edges only)', () {
      final abr = VmBufferingAbr(threshold: 3);
      // Each stall is a false→true transition; sustained true must not recount.
      expect(abr.onBuffering(true), isFalse); // stall 1
      expect(abr.onBuffering(true), isFalse); // still buffering, no new edge
      expect(abr.onBuffering(false), isFalse);
      expect(abr.onBuffering(true), isFalse); // stall 2
      expect(abr.onBuffering(false), isFalse);
      expect(abr.onBuffering(true), isTrue); // stall 3 → downshift
      expect(abr.stalls, 0); // counter reset
    });

    test('reset clears the counter and edge state', () {
      final abr = VmBufferingAbr(threshold: 2);
      abr.onBuffering(true);
      abr.reset();
      expect(abr.stalls, 0);
      expect(abr.onBuffering(true), isFalse); // fresh edge after reset
    });
  });

  group('VmFit', () {
    test('cycles contain → cover → fill → contain', () {
      expect(VmFit.contain.next, VmFit.cover);
      expect(VmFit.cover.next, VmFit.fill);
      expect(VmFit.fill.next, VmFit.contain);
    });

    test('every mode has a non-empty labelKey', () {
      for (final f in VmFit.values) {
        expect(f.labelKey, isNotEmpty);
      }
    });
  });

  group('VmDanmakuItem', () {
    test('compares by value', () {
      const a = VmDanmakuItem(text: 'hi', time: Duration(seconds: 1));
      const b = VmDanmakuItem(text: 'hi', time: Duration(seconds: 1));
      const c = VmDanmakuItem(text: 'bye', time: Duration(seconds: 1));
      expect(a, b);
      expect(a, isNot(c));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('VmFeedItem', () {
    test('copyWith replaces only the like fields, keeping callbacks', () {
      var calls = 0;
      final item = VmFeedItem(
        source: const VmSource('https://h/0.mp4'),
        authorName: 'alice',
        initialLiked: false,
        initialLikeCount: 3,
        onLikeChanged: (liked, count) => calls++,
      );
      final n = item.copyWith(initialLiked: true, initialLikeCount: 4);
      expect(n.initialLiked, isTrue);
      expect(n.initialLikeCount, 4);
      expect(n.authorName, 'alice');
      n.onLikeChanged!(true, 4);
      expect(calls, 1);
    });
  });
}
