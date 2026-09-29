import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/error_policy.dart';

void main() {
  const policy = MovaPrefixError();

  group('MovaPrefixError — mpv prefix -> code/fatal mapping (§D4)', () {
    test('stream -> stream, fatal', () {
      final v = policy.classify('e', subsystem: 'stream', afterFirstFrame: false);
      expect(v.code, 'stream');
      expect(v.fatal, isTrue);
    });

    test('file -> file, fatal', () {
      final v = policy.classify('e', subsystem: 'file', afterFirstFrame: false);
      expect(v.code, 'file');
      expect(v.fatal, isTrue);
    });

    test('ffmpeg (network) is fatal before the first frame', () {
      final v = policy.classify('e', subsystem: 'ffmpeg', afterFirstFrame: false);
      expect(v.code, 'network');
      expect(v.fatal, isTrue);
    });

    test('ffmpeg (network) is non-fatal after the first frame', () {
      final v = policy.classify('e', subsystem: 'ffmpeg', afterFirstFrame: true);
      expect(v.code, 'network');
      expect(v.fatal, isFalse);
    });

    test('vd -> decode.video, non-fatal', () {
      final v = policy.classify('e', subsystem: 'vd', afterFirstFrame: true);
      expect(v.code, 'decode.video');
      expect(v.fatal, isFalse);
    });

    test('ad -> decode.audio, non-fatal', () {
      final v = policy.classify('e', subsystem: 'ad', afterFirstFrame: true);
      expect(v.code, 'decode.audio');
      expect(v.fatal, isFalse);
    });

    test('cplayer -> player, fatal', () {
      final v = policy.classify('e', subsystem: 'cplayer', afterFirstFrame: true);
      expect(v.code, 'player');
      expect(v.fatal, isTrue);
    });

    test('unknown/absent prefix -> unknown, non-fatal', () {
      final v = policy.classify('e', subsystem: null, afterFirstFrame: true);
      expect(v.code, 'unknown');
      expect(v.fatal, isFalse);
    });
  });
}
