import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

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

  group('MovaAdBreak — 0.5.0 delay / duration / waitForReady', () {
    const adSource = MovaSource('https://host/ad.mp4');

    test('the three new fields default to zero / null / null', () {
      const b = MovaAdBreak(kind: MovaAdBreakKind.mid, source: adSource);
      expect(b.delay, Duration.zero);
      expect(b.duration, isNull);
      expect(b.waitForReady, isNull);
    });

    test('the three new fields can be set and read back', () {
      const b = MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: adSource,
        delay: Duration(seconds: 3),
        duration: Duration(seconds: 15),
        waitForReady: true,
      );
      expect(b.delay, const Duration(seconds: 3));
      expect(b.duration, const Duration(seconds: 15));
      expect(b.waitForReady, isTrue);
    });

    test('assertValid passes when duration outlasts skippableAfter', () {
      const b = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: adSource,
        duration: Duration(seconds: 15),
        skippableAfter: Duration(seconds: 5),
      );
      expect(b.assertValid, returnsNormally);
    });

    test('assertValid rejects duration equal to skippableAfter: the skip control never appears', () {
      const b = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: adSource,
        duration: Duration(seconds: 5),
        skippableAfter: Duration(seconds: 5),
      );
      expect(b.assertValid, throwsA(isA<AssertionError>()));
    });

    test('assertValid rejects duration shorter than skippableAfter', () {
      const b = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: adSource,
        duration: Duration(seconds: 3),
        skippableAfter: Duration(seconds: 5),
      );
      expect(b.assertValid, throwsA(isA<AssertionError>()));
    });

    test('assertValid accepts a null duration alongside a non-null skippableAfter', () {
      const b = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: adSource,
        skippableAfter: Duration(seconds: 5),
      );
      expect(b.duration, isNull);
      expect(b.assertValid, returnsNormally);
    });

    test('assertValid rejects a non-zero delay on a pre-roll or a post-roll', () {
      const pre = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: adSource,
        delay: Duration(seconds: 3),
      );
      const post = MovaAdBreak(
        kind: MovaAdBreakKind.post,
        source: adSource,
        delay: Duration(seconds: 3),
      );
      expect(pre.assertValid, throwsA(isA<AssertionError>()));
      expect(post.assertValid, throwsA(isA<AssertionError>()));
    });

    test('assertValid accepts a non-zero delay on a mid-roll', () {
      const b = MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: adSource,
        offset: Duration(seconds: 30),
        delay: Duration(seconds: 3),
      );
      expect(b.delay, const Duration(seconds: 3));
      expect(b.assertValid, returnsNormally);
    });

    test('waitForReady can be forced either way on every kind, including pre and post', () {
      for (final kind in MovaAdBreakKind.values) {
        final on = MovaAdBreak(kind: kind, source: adSource, waitForReady: true);
        final off = MovaAdBreak(kind: kind, source: adSource, waitForReady: false);
        expect(on.waitForReady, isTrue);
        expect(off.waitForReady, isFalse);
        expect(on.assertValid, returnsNormally, reason: 'the model must not second-guess the host');
        expect(off.assertValid, returnsNormally);
      }
    });

    test('waitForReady true coexists with a zero delay — the default mid-roll shape', () {
      const b = MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: adSource,
        waitForReady: true,
      );
      expect(b.waitForReady, isTrue);
      expect(b.delay, Duration.zero);
    });
  });

  /// Builds a non-const source so two calls give distinct instances.
  ///
  /// 构造一个非 const 的源，使两次调用得到不同实例。
  MovaSource mk(String uri, {String? title}) => MovaSource(uri, title: title);

  group('MovaSource.sameAs', () {
    test('same uri and type with a different title is the same media', () {
      expect(mk('https://a/x.flv', title: 'a').sameAs(mk('https://a/x.flv', title: 'b')), isTrue);
    });

    test('a different uri is different media', () {
      expect(mk('https://a/x.flv').sameAs(mk('https://a/y.flv')), isFalse);
    });

    test('a different type is different media', () {
      expect(
        const MovaSource('https://a/x', type: MovaStreamType.live).sameAs(const MovaSource('https://a/x')),
        isFalse,
      );
    });
  });

  group('MovaSource alternatives', () {
    test('alternatives default to empty and uris keeps the given order', () {
      expect(const MovaSource('https://a').alternatives, isEmpty);
      expect(const MovaSource('https://a').uris, ['https://a']);
      expect(const MovaSource('https://a', alternatives: ['https://b', 'https://c']).uris, ['https://a', 'https://b', 'https://c']);
    });

    test('pick trims, drops empty/null/duplicates and keeps order; the first becomes uri', () {
      final s = MovaSource.pick(['', ' https://a ', null, 'https://b', 'https://a'], type: MovaStreamType.live, title: 't');
      expect(s, isNotNull);
      expect(s!.uri, 'https://a');
      expect(s.alternatives, ['https://b']);
      expect(s.type, MovaStreamType.live);
      expect(s.title, 't');
    });

    test('pick returns null when nothing usable is left', () {
      expect(MovaSource.pick(const []), isNull);
      expect(MovaSource.pick(['', '  ', null]), isNull);
    });

    test('sameAs compares alternatives, order included', () {
      const a = MovaSource('https://a', alternatives: ['https://b', 'https://c']);
      expect(a.sameAs(const MovaSource('https://a', alternatives: ['https://b', 'https://c'], title: 'x')), isTrue);
      expect(a.sameAs(const MovaSource('https://a', alternatives: ['https://c', 'https://b'])), isFalse);
      expect(a.sameAs(const MovaSource('https://a', alternatives: ['https://b'])), isFalse);
      expect(a.sameAs(const MovaSource('https://a')), isFalse);
    });

    test('the primary constructor stays const', () {
      const a = MovaSource('https://a');
      const b = MovaSource('https://a');
      expect(identical(a, b), isTrue);
    });
  });
}
