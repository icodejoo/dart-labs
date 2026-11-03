import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/session/ad_clock.dart';

void main() {
  test('起表后按时长到期', () => fakeAsync((a) {
    var count = 0;
    final clock = MovaAdClock(now: () => DateTime.utc(2026).add(a.elapsed));
    clock.start(const Duration(seconds: 10), () => count++);
    expect(clock.running, isTrue);
    a.elapse(const Duration(milliseconds: 9900));
    expect(count, 0);
    a.elapse(const Duration(milliseconds: 100));
    expect(count, 1);
    expect(clock.remaining, isNull);
    expect(clock.running, isFalse);
    a.elapse(const Duration(seconds: 20));
    expect(count, 1);
  }));
  test('暂停后不到期、恢复后补足剩余', () => fakeAsync((a) {
    var count = 0;
    final clock = MovaAdClock(now: () => DateTime.utc(2026).add(a.elapsed));
    clock.start(const Duration(seconds: 10), () => count++);
    a.elapse(const Duration(seconds: 4));
    clock.pause();
    a.elapse(const Duration(seconds: 30));
    expect(clock.remaining, const Duration(seconds: 6));
    expect(clock.running, isFalse);
    expect(count, 0);
    clock.resume();
    a.elapse(const Duration(seconds: 6));
    expect(count, 1);
  }));
  test('取消后永不到期且剩余为 null', () => fakeAsync((a) {
    var count = 0;
    final clock = MovaAdClock(now: () => DateTime.utc(2026).add(a.elapsed));
    for (final paused in [false, true]) {
      clock.start(const Duration(seconds: 10), () => count++);
      if (paused) clock.pause();
      clock.cancel();
      clock.resume();
      a.elapse(const Duration(seconds: 20));
      expect(clock.remaining, isNull);
      expect(clock.running, isFalse);
    }
    expect(count, 0);
  }));
  test('重复暂停/恢复幂等', () => fakeAsync((a) {
    var count = 0;
    final clock = MovaAdClock(now: () => DateTime.utc(2026).add(a.elapsed));
    clock.start(const Duration(seconds: 10), () => count++);
    a.elapse(const Duration(seconds: 4));
    clock.pause();
    a.elapse(const Duration(seconds: 1));
    clock.pause();
    expect(clock.remaining, const Duration(seconds: 6));
    clock.resume();
    a.elapse(const Duration(seconds: 1));
    clock.resume();
    a.elapse(const Duration(seconds: 5));
    expect(count, 1);
  }));
}
