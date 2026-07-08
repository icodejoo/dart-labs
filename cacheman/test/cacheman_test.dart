import 'dart:convert';
import 'dart:io';

import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// `get_storage`'s io backend calls `getApplicationDocumentsDirectory()`
/// unconditionally before falling back to an explicit `path` (see
/// `get_storage`'s `StorageImpl._fileDb`), so even passing `path:` to
/// `Cacheman.create()` still needs a working path_provider platform channel
/// — absent under plain `flutter test`. This fake satisfies that call; the
/// path it returns is never actually used since our tests always pass an
/// explicit `path:`.
///
/// `get_storage` 的 io 后端在决定要不要用传入的 `path` 之前，会无条件先调一次
/// `getApplicationDocumentsDirectory()`（见 `get_storage` 的
/// `StorageImpl._fileDb`），所以就算给 `Cacheman.create()` 传了 `path:`，也
/// 还是需要一个能用的 path_provider 平台通道——纯 `flutter test` 下没有。这个
/// 假实现就是补上这一调用；返回的路径本身用不到，因为我们的测试都显式传了
/// `path:`。
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// Fake in-memory [Store], used to unit-test [Engine]'s logic directly
/// without going through a real `get_storage` container (no disk I/O, no
/// `path_provider`/platform binding needed — every TTL/sliding/namespace/
/// codec/raw/readonly/clone behavior lives in [Engine], not in the backend,
/// so this is a faithful substitute for either `ls` or `ss`'s real backend).
class FakeStore implements Store {
  final Map<String, String> _m = <String, String>{};
  bool failNext = false;

  @override
  String? get(String key) => _m[key];

  @override
  void set(String key, String value) {
    if (failNext) {
      failNext = false;
      throw StateError('injected failure');
    }
    _m[key] = value;
  }

  @override
  void remove(String key) => _m.remove(key);

  @override
  void clear() => _m.clear();

  @override
  String? key(int index) {
    if (index < 0 || index >= _m.length) return null;
    return _m.keys.elementAt(index);
  }

  @override
  List<String> keys() => _m.keys.toList(growable: false);

  @override
  int get length => _m.length;
}

/// A trivial reversible codec for tests — NOT for real use (see [Codec]'s
/// doc: this package ships no implementation on purpose). Base64-wraps the
/// value so a plaintext substring check (e.g. `isNot(contains('secret'))`)
/// is actually meaningful, not just a prefixed passthrough.
class FakeCodec implements Codec {
  FakeCodec([this.password = 'pw']);
  final String password;

  @override
  String encode(String value) => '$password:${base64Encode(utf8.encode(value))}';

  @override
  String? decode(String value) {
    final prefix = '$password:';
    if (!value.startsWith(prefix)) return null;
    try {
      return utf8.decode(base64Decode(value.substring(prefix.length)));
    } catch (_) {
      return null;
    }
  }
}

Engine engine({
  bool memoized = false,
  bool cloned = false,
  bool deepCloned = false,
  bool codeable = false,
  Codec? codec,
  bool sliding = false,
  String? namespace,
  bool raw = false,
  bool force = true,
  bool readonly = false,
  bool enckey = false,
  CachemanOnError? onError,
  Store? store,
}) =>
    Engine(
      store ?? FakeStore(),
      Memo(),
      CachemanOptions(
        memoized: memoized,
        cloned: cloned,
        deepCloned: deepCloned,
        codeable: codeable,
        codec: codec,
        sliding: sliding,
        namespace: namespace,
        raw: raw,
        force: force,
        readonly: readonly,
        enckey: enckey,
        onError: onError,
      ),
    );

void main() {
  group('basic get/set/remove', () {
    test('set then get roundtrips', () {
      final e = engine();
      e.set('a', 'hello');
      expect(e.get<String>('a'), 'hello');
    });

    test('missing key returns null, or the given default', () {
      final e = engine();
      expect(e.get<String>('missing'), isNull);
      expect(e.get<String>('missing', 'fallback'), 'fallback');
    });

    test('remove deletes the key', () {
      final e = engine();
      e.set('a', 1);
      e.remove('a');
      expect(e.get<int>('a'), isNull);
    });

    test('values round-trip through JSON (maps, lists, nested)', () {
      final e = engine();
      e.set('obj', {
        'id': 1,
        'tags': ['a', 'b'],
      });
      expect(e.get<dynamic>('obj'), {
        'id': 1,
        'tags': ['a', 'b'],
      });
    });
  });

  group('ttl / expiry', () {
    test('a positive ttl expires the entry after it elapses', () async {
      final e = engine();
      e.set('a', 'x', ttl: 30);
      expect(e.get<String>('a'), 'x');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(e.get<String>('a'), isNull);
    });

    test('ttl <= 0 is warned and ignored — value persists with no expiry', () {
      final e = engine();
      e.set('a', 'x', ttl: 0);
      expect(e.get<String>('a'), 'x');
    });

    test('expireAt in the past (no sliding) skips the write entirely', () {
      final e = engine();
      e.set('a', 'x', expireAt: DateTime.now().subtract(const Duration(seconds: 1)));
      expect(e.get<String>('a'), isNull);
    });

    test('purge() proactively deletes an expired entry', () async {
      final e = engine();
      e.set('a', 'x', ttl: 20);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      e.purge();
      expect(e.length, 0);
    });
  });

  group('sliding expiry', () {
    test('a read hit past 10% of ttl renews expireAt', () async {
      final e = engine(sliding: true);
      e.set('a', 'x', ttl: 100);
      await Future<void>.delayed(const Duration(milliseconds: 20)); // > 10% of 100ms elapsed
      expect(e.get<String>('a'), 'x'); // triggers renewal
      await Future<void>.delayed(const Duration(milliseconds: 90)); // would've expired without renewal
      expect(e.get<String>('a'), 'x');
    });

    test('without sliding, the same read pattern lets the entry expire on schedule', () async {
      final e = engine();
      e.set('a', 'x', ttl: 100);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(e.get<String>('a'), 'x');
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(e.get<String>('a'), isNull);
    });
  });

  group('namespace', () {
    test('two engines sharing a backend but different namespaces do not collide', () {
      final backend = FakeStore();
      final a = engine(namespace: 'a', store: backend);
      final b = engine(namespace: 'b', store: backend);
      a.set('x', 1);
      b.set('x', 2);
      expect(a.get<int>('x'), 1);
      expect(b.get<int>('x'), 2);
    });

    test('clear() with a namespace only removes owned keys', () {
      final backend = FakeStore();
      final a = engine(namespace: 'a', store: backend);
      final b = engine(namespace: 'b', store: backend);
      a.set('x', 1);
      b.set('y', 2);
      a.clear();
      expect(a.get<int>('x'), isNull);
      expect(b.get<int>('y'), 2);
    });

    test('keys()/length() stay accurate as entries are added and removed (owned-key cache)', () {
      final backend = FakeStore();
      final a = engine(namespace: 'a', store: backend);
      final b = engine(namespace: 'b', store: backend);
      a.set('x', 1);
      a.set('y', 2);
      b.set('z', 3);
      expect(a.keys()..sort(), ['x', 'y']);
      expect(a.length, 2);
      a.remove('x');
      expect(a.keys(), ['y']);
      expect(a.length, 1);
      b.set('w', 4);
      expect(b.keys()..sort(), ['w', 'z']);
      expect(a.length, 1); // unaffected by b's writes to a different namespace
    });

    test('setNamespace invalidates the owned-key cache so keys() reflects the new namespace', () {
      final e = engine(namespace: 'a');
      e.set('x', 1);
      expect(e.keys(), ['x']); // builds the owned-key cache under namespace 'a'
      e.setNamespace('b');
      expect(e.keys(), isEmpty); // nothing written under 'b' yet — not stale from 'a'
      e.set('y', 2);
      expect(e.keys(), ['y']);
      e.setNamespace('a');
      expect(e.keys(), ['x']); // back to 'a', cache rebuilt fresh
    });

    test('setNamespace switches the prefix in place and clears memo', () {
      final e = engine(memoized: true);
      e.set('token', 'v1');
      expect(e.get<String>('token'), 'v1');
      e.setNamespace('alice');
      expect(e.get<String>('token'), isNull); // different prefix now, nothing written there yet
      e.set('token', 'v2');
      expect(e.get<String>('token'), 'v2');
      e.setNamespace(); // back to no namespace
      expect(e.get<String>('token'), 'v1'); // original data untouched
    });
  });

  group('batch operations', () {
    test('setAll / getAll / removeAll', () {
      final e = engine();
      e.setAll(['a', 'b', 'c'], [1, 2, 3]);
      expect(e.getAll(['a', 'b', 'c']), [1, 2, 3]);
      e.removeAll(['a', 'c']);
      expect(e.getAll(['a', 'b', 'c']), [null, 2, null]);
    });

    test('getAll pairs defaults positionally, missing slots fall back to null', () {
      final e = engine();
      e.set('a', 1);
      expect(e.getAll(['a', 'b'], [0, 'x']), [1, 'x']);
      expect(e.getAll(['a', 'b']), [1, null]);
    });

    test('setAll with fewer values than keys skips the missing entries', () {
      final e = engine();
      e.setAll(['a', 'b', 'c'], [1, 2]);
      expect(e.getAll(['a', 'b', 'c']), [1, 2, null]);
    });
  });

  group('raw mode', () {
    test('a String value is stored and read back untouched, no envelope', () {
      final e = engine(raw: true);
      e.set('a', 'plain-string');
      expect(e.get<String>('a'), 'plain-string');
    });

    test('a non-String value is warned and the write is skipped', () {
      final e = engine(raw: true);
      e.set<dynamic>('a', 42);
      expect(e.get<String>('a'), isNull);
    });
  });

  group('readonly', () {
    test('writes only when the key is empty; a second write is discarded', () {
      final e = engine(readonly: true);
      e.set('a', 'first');
      e.set('a', 'second');
      expect(e.get<String>('a'), 'first');
    });

    test('writes again once the key expires', () async {
      final e = engine(readonly: true);
      e.set('a', 'first', ttl: 20);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      e.set('a', 'second');
      expect(e.get<String>('a'), 'second');
    });
  });

  group('codec / enckey', () {
    test('codeable + codec obfuscates the persisted string but reads decode transparently', () {
      final backend = FakeStore();
      final e = engine(codeable: true, codec: FakeCodec(), store: backend);
      e.set('a', 'secret');
      expect(backend.get('a'), isNot(contains('secret'))); // raw backend value doesn't show plaintext
      expect(e.get<String>('a'), 'secret');
    });

    test('a decode failure (wrong codec/corrupted data) is treated as a miss, not a throw', () {
      final backend = FakeStore();
      final withCodec = engine(codeable: true, codec: FakeCodec('right'), store: backend);
      withCodec.set('a', 'secret');
      final wrongCodec = engine(codeable: true, codec: FakeCodec('wrong'), store: backend);
      expect(wrongCodec.get<String>('a'), isNull);
    });

    test('enckey obfuscates the storage key so foreign readers cannot see it', () {
      final backend = FakeStore();
      final e = engine(enckey: true, codec: FakeCodec(), store: backend);
      e.set('token', 'abc');
      expect(backend.keys(), isNot(contains('token')));
      expect(e.get<String>('token'), 'abc');
      expect(e.keys(), ['token']); // logical keys are still plaintext to the owner
    });
  });

  group('cloned / deepCloned', () {
    test('cloned:false (default) shares the same reference as the memo cache', () {
      final e = engine(memoized: true);
      e.set('a', {'n': 1});
      final r1 = e.get<Map<String, dynamic>>('a')!;
      final r2 = e.get<Map<String, dynamic>>('a')!;
      expect(identical(r1, r2), isTrue);
    });

    test('cloned:true (shallow) returns a distinct top-level container', () {
      final e = engine(memoized: true, cloned: true);
      e.set('a', {'n': 1});
      final r1 = e.get<Map<String, dynamic>>('a')!;
      final r2 = e.get<Map<String, dynamic>>('a')!;
      expect(identical(r1, r2), isFalse);
      expect(r1, r2);
    });

    test('cloned:true (shallow) does NOT isolate a nested object', () {
      final e = engine(memoized: true, cloned: true);
      e.set('a', {
        'nested': {'n': 1},
      });
      final r1 = e.get<Map<String, dynamic>>('a')!;
      final r2 = e.get<Map<String, dynamic>>('a')!;
      expect(identical(r1['nested'], r2['nested']), isTrue); // shallow: nested still shared
    });

    test('cloned + deepCloned isolates nested objects too', () {
      final e = engine(memoized: true, cloned: true, deepCloned: true);
      e.set('a', {
        'nested': {'n': 1},
      });
      final r1 = e.get<Map<String, dynamic>>('a')!;
      final r2 = e.get<Map<String, dynamic>>('a')!;
      expect(identical(r1['nested'], r2['nested']), isFalse);
      expect(r1, r2);
    });
  });

  group('force / onError', () {
    test('a synchronous write failure is retried once, then reported via onError if it still fails', () {
      final backend = FakeStore();
      Object? reported;
      final e = engine(store: backend, onError: (key, err) => reported = err);
      backend.failNext = true;
      e.set('a', 'x');
      expect(reported, isNull); // retried once, second attempt succeeded
      expect(e.get<String>('a'), 'x');
    });
  });

  group('fast / lazy / batchFast', () {
    test('fast binds a key and forwards get/set/remove', () {
      final e = engine();
      final token = fast<String>(e, 'token');
      token.set('abc');
      expect(token.get(), 'abc');
      token.remove();
      expect(token.get(), isNull);
      expect(token.get('def'), 'def');
    });

    test('lazy only builds the accessor on first call, then reuses it', () {
      final e = engine();
      final tokenLazy = lazy<String>(e, 'token');
      final a = tokenLazy();
      final b = tokenLazy();
      expect(identical(a, b), isTrue);
    });

    test('batchFast binds several keys at once', () {
      final e = engine();
      final accessors = batchFast<String>(e, ['a', 'b']);
      accessors['a']!.set('1');
      accessors['b']!.set('2');
      expect(e.get<String>('a'), '1');
      expect(e.get<String>('b'), '2');
    });
  });

  group('debug()', () {
    test('returns every owned entry decrypted, namespace preserved', () {
      final backend = FakeStore();
      final e = engine(namespace: 'ns', enckey: true, codec: FakeCodec(), store: backend);
      e.set('a', 1);
      e.set('b', 2);
      expect(debug(e), {'ns:a': 1, 'ns:b': 2});
    });

    test('does not write anything back — keys()/length stay unaffected', () {
      final e = engine();
      e.set('a', 1);
      debug(e);
      expect(e.length, 1);
    });
  });

  group('destroy()', () {
    test('clears the memo cache but keeps persisted data readable', () {
      final backend = FakeStore();
      final e = engine(memoized: true, store: backend);
      e.set('a', 1);
      e.destroy();
      expect(e.get<int>('a'), 1); // still readable straight from the backend
    });
  });

  group('Jsonx', () {
    test('round-trips DateTime, Duration, Set, and BigInt', () {
      final now = DateTime.now();
      final value = {
        'when': now,
        'wait': const Duration(seconds: 5),
        'ids': {1, 2, 3},
        'big': BigInt.parse('123456789012345678901234567890'),
      };
      final decoded = Jsonx.decode<Map<String, dynamic>>(Jsonx.encode(value));
      expect(decoded['when'], now);
      expect(decoded['wait'], const Duration(seconds: 5));
      expect(decoded['ids'], {1, 2, 3});
      expect(decoded['big'], BigInt.parse('123456789012345678901234567890'));
    });

    test('round-trips Uri', () {
      final uri = Uri.parse('https://example.com/path?q=1&r=2#frag');
      final decoded = Jsonx.decode<Map<String, dynamic>>(Jsonx.encode({'url': uri}));
      expect(decoded['url'], uri);
    });

    test('round-trips RegExp, flags included', () {
      final re = RegExp(r'a.b', multiLine: true, caseSensitive: false, dotAll: true);
      final decoded = Jsonx.decode<Map<String, dynamic>>(Jsonx.encode({'re': re}));
      final out = decoded['re'] as RegExp;
      expect(out.pattern, re.pattern);
      expect(out.isMultiLine, re.isMultiLine);
      expect(out.isCaseSensitive, re.isCaseSensitive);
      expect(out.isDotAll, re.isDotAll);
      expect(out.hasMatch('A\nB'), isTrue); // caseSensitive:false + dotAll:true both exercised
    });
  });

  group('Memory cap capacity', () {
    test('unlimited by default — no eviction', () {
      final m = Memory();
      for (var i = 0; i < 1000; i++) {
        m.set('k$i', 'v' * 100);
      }
      expect(m.length, 1000);
    });

    test('evicts oldest first (FIFO) once over cap', () {
      final m = Memory(cap: 12); // room for ~2 entries of "kN"+"vvvvv" (2+5=7 chars each)
      m.set('k1', 'vvvvv'); // size 7
      m.set('k2', 'vvvvv'); // size 14 > 12 -> evicts k1
      expect(m.get('k1'), isNull);
      expect(m.get('k2'), 'vvvvv');
      expect(m.length, 1);
    });

    test('overwriting an existing key does not change its FIFO position', () {
      final m = Memory(cap: 21); // 3 entries of size 7 fit
      m.set('k1', 'vvvvv');
      m.set('k2', 'vvvvv');
      m.set('k3', 'vvvvv');
      m.set('k1', 'wwwww'); // overwrite, same size — k1 stays oldest
      m.set('k4', 'vvvvv'); // pushes total over cap -> evicts k1 (oldest), not k2
      expect(m.get('k1'), isNull);
      expect(m.get('k2'), 'vvvvv');
      expect(m.get('k3'), 'vvvvv');
      expect(m.get('k4'), 'vvvvv');
    });

    test('overwriting the oldest key with a bigger value can evict that very write (self-eviction)', () {
      final m = Memory(cap: 20);
      m.set('a', '12'); // size 3, position 0 (oldest)
      m.set('b', '12'); // size 3, position 1
      m.set('c', '12'); // size 3, position 2
      // Overwrite 'a' with a value that alone fits under cap (size 17 <= 20),
      // but combined total (3+3+17=23) exceeds it. Overwrite keeps 'a' at
      // position 0, so FIFO eviction removes 'a' first — the very write that
      // just happened, even though it wasn't oversized on its own.
      m.set('a', '1234567890123456');
      expect(m.get('a'), isNull);
      expect(m.get('b'), '12');
      expect(m.get('c'), '12');
    });

    test('a single entry larger than the cap is dropped entirely', () {
      final m = Memory(cap: 5);
      m.set('k1', 'this-value-is-way-too-long');
      expect(m.get('k1'), isNull);
      expect(m.length, 0);
    });

    test('removing an entry updates the tracked size so later evictions are correct', () {
      final m = Memory(cap: 14);
      m.set('k1', 'vvvvv'); // 7
      m.set('k2', 'vvvvv'); // 14
      m.remove('k1'); // size back to 7
      m.set('k3', 'vvvvv'); // 14, should NOT evict k2
      expect(m.get('k2'), 'vvvvv');
      expect(m.get('k3'), 'vvvvv');
    });
  });

  group('Cacheman.create() — real get_storage integration', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cacheman_test_');
      PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    });

    tearDown(() {
      // get_storage never closes its RandomAccessFile handle once opened, so
      // on Windows the temp dir stays locked for the rest of the process —
      // best-effort cleanup only, not a correctness assertion.
      //
      // get_storage 打开的 RandomAccessFile 句柄从不关闭，Windows 下临时目录
      // 会在整个进程生命周期内保持锁定——这里只是尽力清理，不是正确性断言。
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('ls persists via get_storage; ss is pure in-memory and independent', () async {
      final cache = await Cacheman.create(container: 'cacheman_test_ls_ss', path: tempDir.path);
      cache.ls.set('a', 'persisted');
      cache.ss.set('a', 'memory-only');
      expect(cache.ls.get<String>('a'), 'persisted');
      expect(cache.ss.get<String>('a'), 'memory-only');
      await cache.destroy();
    });

    test('cap caps ss with FIFO eviction; ls is unaffected', () async {
      // cap sized to hold a few serialized entries (each ~55-65 chars once
      // wrapped in the CacheEntity JSON envelope), not raw value length.
      final cache = await Cacheman.create(container: 'cacheman_test_ssmax', path: tempDir.path, cap: 200);
      for (var i = 0; i < 20; i++) {
        cache.ss.set('k$i', 'x' * 20, memoized: false);
        cache.ls.set('k$i', 'x' * 20);
      }
      expect(cache.ss.get<String>('k0'), isNull); // evicted long ago
      expect(cache.ss.get<String>('k19'), isNotNull); // most recent survives
      expect(cache.ls.get<String>('k0'), isNotNull); // ls has no cap
      await cache.destroy();
    });

    test('ls.key(index)/length walk get_storage directly without materializing keys()', () async {
      final cache = await Cacheman.create(container: 'cacheman_test_ls_key', path: tempDir.path);
      cache.ls.set('a', 1);
      cache.ls.set('b', 2);
      cache.ls.set('c', 3);
      expect(cache.ls.length, 3);
      expect(cache.ls.key(0), 'a');
      expect(cache.ls.key(1), 'b');
      expect(cache.ls.key(2), 'c');
      expect(cache.ls.key(3), isNull); // out of range
      cache.ls.remove('b');
      expect(cache.ls.length, 2);
      expect(cache.ls.key(1), 'c'); // 'c' shifted into 'b''s old slot
      await cache.destroy();
    });

    test('setNamespace switches both ls and ss together', () async {
      final cache = await Cacheman.create(container: 'cacheman_test_ns', path: tempDir.path);
      cache.ls.set('token', 'v1');
      cache.ss.set('token', 's1');
      cache.setNamespace('alice');
      expect(cache.ls.get<String>('token'), isNull);
      expect(cache.ss.get<String>('token'), isNull);
    });
  });
}
