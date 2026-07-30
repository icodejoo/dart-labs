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
}
