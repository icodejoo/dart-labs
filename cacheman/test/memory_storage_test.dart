import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证纯 Dart 内存后端的隔离、快照和通知契约。
void main() {
  const key = 'entry';
  const value = 'value';

  test('isolated memory stores and named stores have explicit identities',
      () async {
    final a = MemoryStorage();
    final b = MemoryStorage();
    await a.write(key, value);
    expect(a.read<String>(key), value);
    expect(b.read<String>(key), isNull);
    final named = MemoryStorage.named('memory-test');
    expect(MemoryStorage.named('memory-test'), same(named));
    expect(MemoryStorage.named('other-memory-test'), isNot(same(named)));
  });

  test('raw key snapshots stay stable and null values retain presence',
      () async {
    final memory = MemoryStorage();
    await memory.write(key, null);
    final snapshot = memory.keys;
    expect(memory.hasData(key), isTrue);
    expect(memory.read<Object?>(key), isNull);
    await memory.remove(key);
    expect(memory.hasData(key), isFalse);
    expect(memory.keys, isEmpty);
    expect(snapshot, [key]);
  });

  test('empty keys stay keyed and cancelled snapshot listeners are skipped',
      () async {
    final memory = MemoryStorage();
    final events = <String?>[];
    late void Function() cancel;
    final stop = memory.listen((key) {
      events.add(key);
      cancel();
    });
    cancel = memory.listen((_) => fail('cancelled listener was called'));
    final pending = memory.write('', value);
    expect(events, ['']);
    await pending;
    await memory.erase();
    expect(events, ['', null]);
    expect(memory.keys, isEmpty);
    stop();
    await memory.write(key, value);
    expect(events, ['', null]);
  });
}
