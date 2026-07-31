import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/bus/bus.dart';

void main() {
  test('VmBus emits current value to new listeners', () async {
    final bus = VmBus<int>(1);
    final seen = <int>[];
    final sub = bus.stream.listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1]);
    bus.emit(2);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2]);
    await sub.cancel();
    await bus.close();
  });

  test('VmBus skips duplicate values', () async {
    final bus = VmBus<int>(1);
    final seen = <int>[];
    final sub = bus.stream.listen(seen.add);
    bus.emit(1);
    bus.emit(1);
    bus.emit(2);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2]);
    await sub.cancel();
    await bus.close();
  });

  test('VmBus.select only emits when the picked field changes', () async {
    final bus = VmBus<({int a, int b})>((a: 0, b: 0));
    final seen = <int>[];
    final sub = bus.select((v) => v.a).listen(seen.add);
    bus.emit((a: 0, b: 9));
    bus.emit((a: 1, b: 9));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [0, 1]);
    await sub.cancel();
    await bus.close();
  });

  test('throttleStream keeps the first and the last value in a window', () async {
    final src = StreamController<int>();
    final seen = <int>[];
    final sub = throttleStream(src.stream, const Duration(milliseconds: 50)).listen(seen.add);
    src.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    src.add(2);
    src.add(3);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(seen, [1, 3]);
    await sub.cancel();
    await src.close();
  });

  test('throttleStream survives its listener count dropping to zero and back', () async {
    // Regression test: throttleStream's internal controller must be
    // broadcast. `VmEngine` wraps this stream in `.asBroadcastStream()` so
    // both the seek bar and the gesture layer can hold independent
    // subscriptions; if a widget rebuild ever drops the listener count to
    // zero and a new subscriber attaches afterwards, `asBroadcastStream`
    // re-`listen()`s this stream. A single-subscription controller throws on
    // a second `listen()` ("Stream has already been listened to"), which
    // would silently and permanently kill position updates until restart —
    // exactly the real-device symptom this test guards against.
    //
    // 回归测试：throttleStream 内部 controller 必须是广播型。`VmEngine` 会把
    // 这个流包一层 `.asBroadcastStream()`，让进度条与手势层各自独立订阅；
    // 若一次 widget 重建让监听数降到零、随后又有新订阅者接入，
    // `asBroadcastStream` 会对本流重新调用一次 `listen()`。单订阅
    // controller 在第二次 `listen()` 时会抛异常（"Stream has already been
    // listened to"），导致位置更新悄无声息地永久断流、直到重启——这正是本测试
    // 要防住的真机症状。
    final src = StreamController<int>.broadcast();
    final throttled = throttleStream(src.stream, const Duration(milliseconds: 20));

    final seenA = <int>[];
    final subA = throttled.listen(seenA.add);
    src.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await subA.cancel();

    final seenB = <int>[];
    final subB = throttled.listen(seenB.add);
    src.add(2);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(seenB, contains(2));

    await subB.cancel();
    await src.close();
  });
}
