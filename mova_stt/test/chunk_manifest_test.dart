import 'package:flutter_test/flutter_test.dart';
import 'package:mova_stt/mova_stt.dart';

void main() {
  group('ChunkManifest.build', () {
    test('splits an exact multiple of chunkDuration with no short tail', () {
      final manifest = ChunkManifest.build(
        totalDuration: const Duration(minutes: 12),
        chunkDuration: const Duration(minutes: 4),
        overlap: const Duration(seconds: 4),
      );
      expect(manifest.chunks, hasLength(3));
      expect(manifest.chunks[0].ownStart, Duration.zero);
      expect(manifest.chunks[0].ownEnd, const Duration(minutes: 4));
      expect(manifest.chunks[2].ownEnd, const Duration(minutes: 12));
    });

    test('leaves a short tail chunk when duration is not an exact multiple', () {
      final manifest = ChunkManifest.build(
        totalDuration: const Duration(minutes: 9, seconds: 30),
        chunkDuration: const Duration(minutes: 4),
      );
      expect(manifest.chunks, hasLength(3));
      expect(manifest.chunks.last.ownStart, const Duration(minutes: 8));
      expect(manifest.chunks.last.ownEnd, const Duration(minutes: 9, seconds: 30));
    });

    test('overlap extends start/end but never past the source bounds', () {
      final manifest = ChunkManifest.build(
        totalDuration: const Duration(minutes: 8),
        chunkDuration: const Duration(minutes: 4),
        overlap: const Duration(seconds: 4),
      );
      // First chunk: leading overlap clamped to zero, not negative.
      expect(manifest.chunks[0].start, Duration.zero);
      expect(manifest.chunks[0].end, const Duration(minutes: 4, seconds: 4));
      // Last chunk: trailing overlap clamped to totalDuration.
      expect(manifest.chunks[1].start, const Duration(minutes: 3, seconds: 56));
      expect(manifest.chunks[1].end, const Duration(minutes: 8));
    });

    test('empty source produces an empty manifest', () {
      final manifest = ChunkManifest.build(totalDuration: Duration.zero);
      expect(manifest.chunks, isEmpty);
    });

    test('all chunks start pending', () {
      final manifest = ChunkManifest.build(totalDuration: const Duration(minutes: 10));
      expect(manifest.chunks.every((c) => c.state == SttChunkState.pending), isTrue);
    });
  });

  group('ChunkManifest.chunkIndexAt', () {
    late ChunkManifest manifest;

    setUp(() {
      manifest = ChunkManifest.build(
        totalDuration: const Duration(minutes: 20),
        chunkDuration: const Duration(minutes: 4),
      );
    });

    test('maps a mid-chunk position to its owning chunk', () {
      expect(manifest.chunkIndexAt(const Duration(minutes: 9)), 2);
    });

    test('clamps positions before the start to chunk 0', () {
      expect(manifest.chunkIndexAt(Duration.zero), 0);
    });

    test('clamps positions at or past the end to the last chunk', () {
      expect(manifest.chunkIndexAt(const Duration(minutes: 20)), 4);
      expect(manifest.chunkIndexAt(const Duration(minutes: 999)), 4);
    });

    test('returns 0 for an empty manifest', () {
      final empty = ChunkManifest.build(totalDuration: Duration.zero);
      expect(empty.chunkIndexAt(const Duration(minutes: 1)), 0);
    });
  });
}
