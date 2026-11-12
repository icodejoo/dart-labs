import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 验证有效时间与分别暂停的语义。
void main() {
  group('LuckyTimeline', () {
    test('first tick after start has zero delta', () {
      final timeline = LuckyTimeline();
      timeline.advance(const Duration(seconds: 10));
      expect(timeline.nowMs, 0);
      expect(timeline.lastDeltaMs, 0);
      timeline.advance(const Duration(milliseconds: 10016));
      expect(timeline.nowMs, 16);
      timeline.rebase();
      timeline.advance(const Duration(seconds: 20));
      expect(timeline.nowMs, 16);
      expect(timeline.lastDeltaMs, 0);
    });
    test('raw delta above maxFrameDelta is clamped', () {
      final timeline =
          LuckyTimeline(maxFrameDelta: const Duration(milliseconds: 25));
      timeline.advance(Duration.zero);
      timeline.advance(const Duration(seconds: 1));
      expect(timeline.nowMs, 25);
      expect(timeline.lastDeltaMs, 25);
      timeline.maxFrameDelta = const Duration(milliseconds: 30);
      timeline.advance(const Duration(seconds: 2));
      expect(timeline.nowMs, 55);
    });
    test(
        'a single 10 minute jump advances effective time by at most maxFrameDelta',
        () {
      final timeline = LuckyTimeline();
      timeline.advance(Duration.zero);
      timeline.advance(const Duration(minutes: 10));
      expect(timeline.nowMs, 100);
      expect(timeline.lastDeltaMs, 100);
    });
    test('paused timeline does not advance and resumes without a jump', () {
      final timeline = LuckyTimeline();
      timeline.advance(Duration.zero);
      timeline.advance(const Duration(milliseconds: 16));
      timeline.pauseUser();
      timeline.advance(const Duration(seconds: 1));
      expect(timeline.nowMs, 16);
      expect(timeline.lastDeltaMs, 0);
      timeline.resumeUser();
      timeline.advance(const Duration(minutes: 10));
      expect(timeline.nowMs, 16);
      timeline.advance(const Duration(minutes: 10, milliseconds: 16));
      expect(timeline.nowMs, 32);
      timeline.pauseLifecycle();
      timeline.resumeLifecycle();
      timeline.advance(const Duration(minutes: 20));
      expect(timeline.nowMs, 32);
    });
    test('user pause and lifecycle pause are tracked separately', () {
      final timeline = LuckyTimeline();
      timeline.advance(Duration.zero);
      timeline.pauseUser();
      timeline.pauseLifecycle();
      timeline.resumeLifecycle();
      expect(timeline.isPaused, isTrue);
      timeline.advance(const Duration(seconds: 1));
      timeline.advance(const Duration(seconds: 2));
      expect(timeline.nowMs, 0);
      timeline.resumeUser();
      expect(timeline.isPaused, isFalse);
      timeline.advance(const Duration(seconds: 3));
      timeline.advance(const Duration(milliseconds: 3016));
      expect(timeline.nowMs, 16);
      timeline.pauseLifecycle();
      timeline.pauseUser();
      timeline.resumeUser();
      expect(timeline.isPaused, isTrue);
      timeline.resumeLifecycle();
      expect(timeline.isPaused, isFalse);
    });
    test('negative raw delta is treated as zero', () {
      final timeline = LuckyTimeline();
      timeline.advance(const Duration(seconds: 1));
      timeline.advance(Duration.zero);
      expect(timeline.nowMs, 0);
      expect(timeline.lastDeltaMs, 0);
      timeline.advance(const Duration(milliseconds: 16));
      expect(timeline.nowMs, 16);
    });
  });
}
