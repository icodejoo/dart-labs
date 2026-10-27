import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';

void main() {
  group('movaAudioPresence', () {
    test('no real track at all is unknown', () {
      expect(
        movaAudioPresence(audioIds: ['auto', 'no'], videoIds: ['auto', 'no'], selectedAudio: 'auto', sampleRate: null),
        MovaAudioPresence.unknown,
      );
    });

    test('a selected audio track whose decoder outputs is present', () {
      expect(
        movaAudioPresence(audioIds: ['auto', 'no', '1'], videoIds: ['1'], selectedAudio: '1', sampleRate: 48000),
        MovaAudioPresence.present,
      );
    });

    test('an audio track without decoder output yet stays unknown', () {
      expect(
        movaAudioPresence(audioIds: ['auto', 'no', '1'], videoIds: ['1'], selectedAudio: '1', sampleRate: null),
        MovaAudioPresence.unknown,
      );
    });

    test('only a video track, or audio switched off, is absent', () {
      expect(
        movaAudioPresence(audioIds: ['auto', 'no'], videoIds: ['1'], selectedAudio: 'auto', sampleRate: null),
        MovaAudioPresence.absent,
      );
      expect(
        movaAudioPresence(audioIds: ['auto', 'no', '1'], videoIds: ['1'], selectedAudio: 'no', sampleRate: 44100),
        MovaAudioPresence.absent,
      );
    });
  });
}
