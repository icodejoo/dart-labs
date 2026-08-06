import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova_stt/mova_stt.dart';

void main() {
  group('cueBelongsToChunk', () {
    late ChunkManifest manifest;

    setUp(() {
      manifest = ChunkManifest.build(
        totalDuration: const Duration(minutes: 8),
        chunkDuration: const Duration(minutes: 4),
        overlap: const Duration(seconds: 4),
      );
    });

    test('a cue fully inside the exclusive range belongs to the chunk', () {
      const cue = MovaSttCue(
        text: 'x',
        start: Duration(minutes: 1),
        end: Duration(minutes: 1, seconds: 2),
      );
      expect(cueBelongsToChunk(cue, manifest.chunks[0]), isTrue);
    });

    test('a cue whose midpoint falls in the trailing overlap belongs to the next chunk', () {
      // Chunk 0 owns [0, 4min); its trailing overlap runs to 4min4s.
      // A cue entirely within that overlap has its midpoint past 4min, so it
      // should NOT be claimed by chunk 0.
      const cue = MovaSttCue(
        text: 'x',
        start: Duration(minutes: 4, seconds: 1),
        end: Duration(minutes: 4, seconds: 3),
      );
      expect(cueBelongsToChunk(cue, manifest.chunks[0]), isFalse);
      expect(cueBelongsToChunk(cue, manifest.chunks[1]), isTrue);
    });

    test('a cue whose midpoint falls in the leading overlap belongs to the previous chunk', () {
      // Chunk 1 owns [4min, 8min); its leading overlap starts at 3min56s.
      const cue = MovaSttCue(
        text: 'x',
        start: Duration(minutes: 3, seconds: 57),
        end: Duration(minutes: 3, seconds: 59),
      );
      expect(cueBelongsToChunk(cue, manifest.chunks[1]), isFalse);
      expect(cueBelongsToChunk(cue, manifest.chunks[0]), isTrue);
    });

    test('midpoint exactly on ownEnd belongs to the next chunk (end is exclusive)', () {
      const cue = MovaSttCue(
        text: 'x',
        start: Duration(minutes: 4),
        end: Duration(minutes: 4),
      );
      expect(cueBelongsToChunk(cue, manifest.chunks[0]), isFalse);
      expect(cueBelongsToChunk(cue, manifest.chunks[1]), isTrue);
    });
  });
}
