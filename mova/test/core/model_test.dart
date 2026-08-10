import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  group('qualitiesFromVideoTracks', () {
    test('lists auto first, then variants highest-first by height', () {
      final qs = qualitiesFromVideoTracks(const [
        MovaVideoTrack(id: 'auto'),
        MovaVideoTrack(id: '0', height: 720, width: 1280, bitrate: 1280000),
        MovaVideoTrack(id: '1', height: 1080, width: 1920, bitrate: 2560000),
        MovaVideoTrack(id: '2', height: 360, width: 640, bitrate: 640000),
      ]);
      expect(qs.first.isAuto, isTrue);
      expect(qs.first.trackId, 'auto');
      expect(qs.map((q) => q.label).toList(), ['自动', '1080p', '720p', '360p']);
      final p1080 = qs.firstWhere((q) => q.label == '1080p');
      expect(p1080.trackId, '1');
      expect(p1080.width, 1920);
      expect(p1080.height, 1080);
      expect(p1080.bandwidth, 2560000);
    });

    test('deduplicates same-height variants, keeping the first (highest-bitrate)', () {
      final qs = qualitiesFromVideoTracks(const [
        MovaVideoTrack(id: '0', height: 1080, bitrate: 3000000),
        MovaVideoTrack(id: '1', height: 1080, bitrate: 2000000),
      ]);
      final variants = qs.where((q) => !q.isAuto).toList();
      expect(variants.length, 1);
      expect(variants.single.trackId, '0');
    });

    test('falls back to a bitrate label when height is unknown', () {
      final qs = qualitiesFromVideoTracks(const [
        MovaVideoTrack(id: '0', bitrate: 1500000),
      ]);
      final variants = qs.where((q) => !q.isAuto).toList();
      expect(variants.single.label, '1500kbps');
    });

    test('returns empty for no tracks or only the auto entry', () {
      expect(qualitiesFromVideoTracks(const []), isEmpty);
      expect(qualitiesFromVideoTracks(const [MovaVideoTrack(id: 'auto')]), isEmpty);
    });
  });

  group('MovaBufferAbr', () {
    test('signals a downshift after `threshold` stalls (rising edges only)', () {
      final abr = MovaBufferAbr(threshold: 3);
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
      final abr = MovaBufferAbr(threshold: 2);
      abr.onBuffering(true);
      abr.reset();
      expect(abr.stalls, 0);
      expect(abr.onBuffering(true), isFalse); // fresh edge after reset
    });
  });

  group('MovaFit', () {
    test('cycles contain → cover → fill → contain', () {
      expect(MovaFit.contain.next, MovaFit.cover);
      expect(MovaFit.cover.next, MovaFit.fill);
      expect(MovaFit.fill.next, MovaFit.contain);
    });

    test('every mode has a non-empty labelKey', () {
      for (final f in MovaFit.values) {
        expect(f.labelKey, isNotEmpty);
      }
    });
  });

  group('MovaDanmakuItem', () {
    test('compares by value', () {
      const a = MovaDanmakuItem(text: 'hi', time: Duration(seconds: 1));
      const b = MovaDanmakuItem(text: 'hi', time: Duration(seconds: 1));
      const c = MovaDanmakuItem(text: 'bye', time: Duration(seconds: 1));
      expect(a, b);
      expect(a, isNot(c));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('MovaFeedItem', () {
    test('copyWith replaces only the like fields, keeping callbacks', () {
      var calls = 0;
      final item = MovaFeedItem(
        source: const MovaSource('https://h/0.mp4'),
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
