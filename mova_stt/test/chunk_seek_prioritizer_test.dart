import 'package:flutter_test/flutter_test.dart';
import 'package:mova_stt/mova_stt.dart';

void main() {
  group('chunksToPrioritize', () {
    late ChunkManifest manifest;

    setUp(() {
      manifest = ChunkManifest.build(
        totalDuration: const Duration(minutes: 20),
        chunkDuration: const Duration(minutes: 4),
      );
    });

    test('returns the covering chunk plus the next one', () {
      expect(chunksToPrioritize(manifest, const Duration(minutes: 9)), [2, 3]);
    });

    test('omits the next chunk when the target is already in the last chunk', () {
      expect(chunksToPrioritize(manifest, const Duration(minutes: 19)), [4]);
    });

    test('returns nothing for an empty manifest', () {
      final empty = ChunkManifest.build(totalDuration: Duration.zero);
      expect(chunksToPrioritize(empty, Duration.zero), isEmpty);
    });
  });

  group('ChunkSeekPrioritizer', () {
    late ChunkManifest manifest;
    late ChunkScheduler scheduler;

    setUp(() {
      manifest = ChunkManifest.build(
        totalDuration: const Duration(minutes: 20),
        chunkDuration: const Duration(minutes: 4),
      );
      scheduler = ChunkScheduler()..seedLowPriority(List.generate(manifest.chunks.length, (i) => i));
    });

    test('only the settled target after a burst of seeks is prioritized', () async {
      final prioritizer = ChunkSeekPrioritizer(
        manifest: manifest,
        scheduler: scheduler,
        settleDelay: const Duration(milliseconds: 20),
      );
      prioritizer.onSeek(const Duration(minutes: 1));
      prioritizer.onSeek(const Duration(minutes: 5));
      prioritizer.onSeek(const Duration(minutes: 9)); // final, settled position

      // Nothing should be prioritized yet — still within the debounce window.
      expect(scheduler.nextTask(), 0);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Only chunk 2 (covers 9min) and 3 (lookahead) should now be high-priority.
      expect(scheduler.nextTask(), 2);
      expect(scheduler.nextTask(), 3);

      prioritizer.dispose();
    });

    test('dispose cancels a pending debounced seek', () async {
      final prioritizer = ChunkSeekPrioritizer(
        manifest: manifest,
        scheduler: scheduler,
        settleDelay: const Duration(milliseconds: 20),
      );
      prioritizer.onSeek(const Duration(minutes: 9));
      prioritizer.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Nothing was prioritized — low-priority order is untouched.
      expect(scheduler.nextTask(), 0);
    });
  });
}
