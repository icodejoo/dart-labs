import 'package:flutter_test/flutter_test.dart';
import 'package:mova_stt/mova_stt.dart';

void main() {
  group('ChunkScheduler', () {
    test('drains low-priority queue in seeded order when nothing is high-priority', () {
      final scheduler = ChunkScheduler()..seedLowPriority([0, 1, 2, 3]);
      expect(scheduler.nextTask(), 0);
      expect(scheduler.nextTask(), 1);
      expect(scheduler.nextTask(), 2);
      expect(scheduler.nextTask(), 3);
      expect(scheduler.nextTask(), isNull);
    });

    test('high-priority chunk is served before any low-priority chunk', () {
      final scheduler = ChunkScheduler()..seedLowPriority([0, 1, 2, 3]);
      scheduler.enqueueHigh(3);
      expect(scheduler.nextTask(), 3);
      expect(scheduler.nextTask(), 0); // falls back to low-priority order
    });

    test('enqueueHigh removes the chunk from low-priority so it is never duplicated', () {
      final scheduler = ChunkScheduler()..seedLowPriority([0, 1, 2]);
      scheduler.enqueueHigh(1);
      expect(scheduler.nextTask(), 1);
      expect(scheduler.nextTask(), 0);
      expect(scheduler.nextTask(), 2);
      expect(scheduler.nextTask(), isNull);
    });

    test('re-prioritizing an already-high chunk moves it to the front, not duplicates it', () {
      final scheduler = ChunkScheduler();
      scheduler.enqueueHigh(5);
      scheduler.enqueueHigh(9); // e.g. user seeks again before 5 finishes
      scheduler.enqueueHigh(5); // seeks back — 5 should jump to the front again
      expect(scheduler.nextTask(), 5);
      expect(scheduler.nextTask(), 9);
      expect(scheduler.nextTask(), isNull);
    });

    test('hasPendingWork reflects both queues', () {
      final scheduler = ChunkScheduler();
      expect(scheduler.hasPendingWork, isFalse);
      scheduler.seedLowPriority([0]);
      expect(scheduler.hasPendingWork, isTrue);
      scheduler.nextTask();
      expect(scheduler.hasPendingWork, isFalse);
    });
  });
}
