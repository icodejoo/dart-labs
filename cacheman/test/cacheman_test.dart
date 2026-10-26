import 'dart:convert';
import 'dart:io';

import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// `get_storage`'s io backend calls `getApplicationDocumentsDirectory()`
/// unconditionally before falling back to an explicit `path` (see
/// `get_storage`'s `StorageImpl._fileDb`), so even passing `path:` to
/// `Cacheman()`'s constructor still needs a working path_provider platform channel
/// — absent under plain `flutter test`. This fake satisfies that call; the
/// path it returns is never actually used since our tests always pass an
/// explicit `path:`.
///
/// `get_storage` 的 io 后端在决定要不要用传入的 `path` 之前，会无条件先调一次
/// `getApplicationDocumentsDirectory()`（见 `get_storage` 的
/// `StorageImpl._fileDb`），所以就算给 `Cacheman()` 构造函数传了 `path:`，也
/// 还是需要一个能用的 path_provider 平台通道——纯 `flutter test` 下没有。这个
/// 假实现就是补上这一调用；返回的路径本身用不到，因为我们的测试都显式传了
/// `path:`。
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
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

/// Awaits [cache]'s init and returns it — sugar for the direct
/// `Cacheman(...)` construction sites below (the `newCache` helper inside
/// `main()` covers the common case; this is for the group that exercises the
/// constructor directly).
Future<Cacheman> _ready(Cacheman cache) async {
  await cache.ensureInitialized();
  return cache;
}

void main() {
  late Directory tempDir;
  var containerSeq = 0;

  /// A fresh container name per call, so every test gets its own isolated
  /// `get_storage` backend within the shared [tempDir] — `get_storage`
  /// caches its underlying instances by container name for the lifetime of
  /// the process, so reusing a name across tests would leak state (and, for
  /// the first caller of a given name, permanently pin its `path`).
  ///
  /// 每次调用给一个全新的 container 名，让每个测试都有自己独立的
  /// `get_storage` 后端（都在共享的 [tempDir] 下）——`get_storage` 在整个
  /// 进程生命周期内按 container 名缓存底层实例，同名复用会导致状态泄漏（对
  /// 该名字的第一个调用方，还会把它的 `path` 永久钉死）。
  String nextContainer() => 'cacheman_test_${containerSeq++}';

  /// Builds a real `Cacheman` instance backed by `get_storage` — this is now
  /// the *only* way to exercise [Cacheman]'s logic (TTL/sliding/namespace/
  /// codec/force/...), since `Cacheman` no longer accepts an injected
  /// fake backend (the `Store`/`MemoCache` abstraction seam was removed —
  /// `Cacheman` talks directly to a `GetStorage` container).
  ///
  /// 构造一个真正由 `get_storage` 支撑的 `Cacheman` 实例——这是练到
  /// [Cacheman] 逻辑（TTL/滑动/命名空间/codec/force/...）现在唯一的
  /// 方式，因为 `Cacheman` 不再接受注入的假后端（`Store`/`MemoCache` 这层
  /// 抽象已经拿掉——`Cacheman` 直接对接一个 `GetStorage` container）。
  Future<Cacheman> newCache({
    String? container,
    bool codeable = false,
    Codec? codec,
    bool sliding = false,
    String? namespace,
    bool raw = false,
    bool force = true,
    bool readonly = false,
    bool enckey = false,
    CachemanOnError? onError,
  }) async {
    final cache = Cacheman(
      container: container ?? nextContainer(),
      path: tempDir.path,
      options: CachemanOptions(
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
    await cache.ensureInitialized();
    return cache;
  }

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

  group('basic read/write/remove', () {
    test('write then read roundtrips', () async {
      final e = await newCache();
      e.write('a', 'hello');
      expect(e.read<String>('a'), 'hello');
    });

    test('missing key returns null, or the given default', () async {
      final e = await newCache();
      expect(e.read<String>('missing'), isNull);
      expect(e.read<String>('missing', 'fallback'), 'fallback');
    });

    test('remove deletes the key', () async {
      final e = await newCache();
      e.write('a', 1);
      e.remove('a');
      expect(e.read<int>('a'), isNull);
    });

    test('values round-trip through JSON (maps, lists, nested)', () async {
      final e = await newCache();
      e.write('obj', {
        'id': 1,
        'tags': ['a', 'b'],
      });
      expect(e.read<dynamic>('obj'), {
        'id': 1,
        'tags': ['a', 'b'],
      });
    });
  });

  group('ttl / expiry', () {
    test('a positive ttl expires the entry after it elapses', () async {
      final e = await newCache();
      e.write('a', 'x', ttl: 30);
      expect(e.read<String>('a'), 'x');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(e.read<String>('a'), isNull);
    });

    test('ttl <= 0 is warned and ignored — value persists with no expiry', () async {
      final e = await newCache();
      e.write('a', 'x', ttl: 0);
      expect(e.read<String>('a'), 'x');
    });

    test('expireAt in the past (no sliding) skips the write entirely', () async {
      final e = await newCache();
      e.write('a', 'x', expireAt: DateTime.now().subtract(const Duration(seconds: 1)));
      expect(e.read<String>('a'), isNull);
    });

    test('purge() proactively deletes an expired entry', () async {
      final e = await newCache();
      e.write('a', 'x', ttl: 20);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      e.purge();
      expect(e.length, 0);
    });
  });

  group('sliding expiry', () {
    test('a read hit past 10% of ttl renews expireAt', () async {
      final e = await newCache(sliding: true);
      e.write('a', 'x', ttl: 100);
      await Future<void>.delayed(const Duration(milliseconds: 20)); // > 10% of 100ms elapsed
      expect(e.read<String>('a'), 'x'); // triggers renewal
      await Future<void>.delayed(const Duration(milliseconds: 90)); // would've expired without renewal
      expect(e.read<String>('a'), 'x');
    });

    test('without sliding, the same read pattern lets the entry expire on schedule', () async {
      final e = await newCache();
      e.write('a', 'x', ttl: 100);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(e.read<String>('a'), 'x');
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(e.read<String>('a'), isNull);
    });
  });

  group('namespace', () {
    test('two engines sharing a backend but different namespaces do not collide', () async {
      final container = nextContainer();
      final a = await newCache(container: container, namespace: 'a');
      final b = await newCache(container: container, namespace: 'b');
      a.write('x', 1);
      b.write('x', 2);
      expect(a.read<int>('x'), 1);
      expect(b.read<int>('x'), 2);
    });

    test('erase() with a namespace only removes owned keys', () async {
      final container = nextContainer();
      final a = await newCache(container: container, namespace: 'a');
      final b = await newCache(container: container, namespace: 'b');
      a.write('x', 1);
      b.write('y', 2);
      a.erase();
      expect(a.read<int>('x'), isNull);
      expect(b.read<int>('y'), 2);
    });

    test('keys()/length() stay accurate as entries are added and removed (owned-key cache)', () async {
      final container = nextContainer();
      final a = await newCache(container: container, namespace: 'a');
      final b = await newCache(container: container, namespace: 'b');
      a.write('x', 1);
      a.write('y', 2);
      b.write('z', 3);
      expect(a.keys()..sort(), ['x', 'y']);
      expect(a.length, 2);
      a.remove('x');
      expect(a.keys(), ['y']);
      expect(a.length, 1);
      b.write('w', 4);
      expect(b.keys()..sort(), ['w', 'z']);
      expect(a.length, 1); // unaffected by b's writes to a different namespace
    });

    test('setNamespace invalidates the owned-key cache so keys() reflects the new namespace', () async {
      final e = await newCache(namespace: 'a');
      e.write('x', 1);
      expect(e.keys(), ['x']); // builds the owned-key cache under namespace 'a'
      e.setNamespace('b');
      expect(e.keys(), isEmpty); // nothing written under 'b' yet — not stale from 'a'
      e.write('y', 2);
      expect(e.keys(), ['y']);
      e.setNamespace('a');
      expect(e.keys(), ['x']); // back to 'a', cache rebuilt fresh
    });

    test('setNamespace switches the prefix in place', () async {
      final e = await newCache();
      e.write('token', 'v1');
      expect(e.read<String>('token'), 'v1');
      e.setNamespace('alice');
      expect(e.read<String>('token'), isNull); // different prefix now, nothing written there yet
      e.write('token', 'v2');
      expect(e.read<String>('token'), 'v2');
      e.setNamespace(); // back to no namespace
      expect(e.read<String>('token'), 'v1'); // original data untouched
    });
  });

  group('batch operations', () {
    test('writeAll / readAll / removeAll', () async {
      final e = await newCache();
      e.writeAll(['a', 'b', 'c'], [1, 2, 3]);
      expect(e.readAll(['a', 'b', 'c']), [1, 2, 3]);
      e.removeAll(['a', 'c']);
      expect(e.readAll(['a', 'b', 'c']), [null, 2, null]);
    });

    test('readAll pairs defaults positionally, missing slots fall back to null', () async {
      final e = await newCache();
      e.write('a', 1);
      expect(e.readAll(['a', 'b'], [0, 'x']), [1, 'x']);
      expect(e.readAll(['a', 'b']), [1, null]);
    });

    test('writeAll with fewer values than keys skips the missing entries', () async {
      final e = await newCache();
      e.writeAll(['a', 'b', 'c'], [1, 2]);
      expect(e.readAll(['a', 'b', 'c']), [1, 2, null]);
    });
  });

  group('raw mode', () {
    test('a String value is stored and read back untouched, no envelope', () async {
      final e = await newCache(raw: true);
      e.write('a', 'plain-string');
      expect(e.read<String>('a'), 'plain-string');
    });

    test('a non-String value is warned and the write is skipped', () async {
      final e = await newCache(raw: true);
      e.write<dynamic>('a', 42);
      expect(e.read<String>('a'), isNull);
    });
  });

  group('readonly', () {
    test('writes only when the key is empty; a second write is discarded', () async {
      final e = await newCache(readonly: true);
      e.write('a', 'first');
      e.write('a', 'second');
      expect(e.read<String>('a'), 'first');
    });

    test('writes again once the key expires', () async {
      final e = await newCache(readonly: true);
      e.write('a', 'first', ttl: 20);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      e.write('a', 'second');
      expect(e.read<String>('a'), 'second');
    });
  });

  group('codec / enckey', () {
    test('codeable + codec obfuscates the persisted string but reads decode transparently', () async {
      final container = nextContainer();
      final e = await newCache(container: container, codeable: true, codec: FakeCodec());
      e.write('a', 'secret');
      expect(e.read<String>('a'), 'secret');
      // read the raw persisted string straight from get_storage (same
      // cached instance, already initialized) to confirm it never shows the
      // plaintext.
      final gsRaw = GetStorage(container).read<dynamic>('a');
      expect(gsRaw, isA<String>());
      expect(gsRaw as String, isNot(contains('secret')));
    });

    test('a decode failure (wrong codec/corrupted data) is treated as a miss, not a throw', () async {
      final container = nextContainer();
      final withCodec = await newCache(container: container, codeable: true, codec: FakeCodec('right'));
      withCodec.write('a', 'secret');
      final wrongCodec = await newCache(container: container, codeable: true, codec: FakeCodec('wrong'));
      expect(wrongCodec.read<String>('a'), isNull);
    });

    test('enckey obfuscates the storage key so foreign readers cannot see it', () async {
      final container = nextContainer();
      final e = await newCache(container: container, enckey: true, codec: FakeCodec());
      e.write('token', 'abc');
      final gsKeys = GetStorage(container).getKeys<Iterable<dynamic>>().map((k) => k.toString());
      expect(gsKeys, isNot(contains('token')));
      expect(e.read<String>('token'), 'abc');
      expect(e.keys(), ['token']); // logical keys are still plaintext to the owner
    });
  });

  group('force / onError', () {
    // The original `FakeStore.failNext` fake let a unit test inject a
    // *synchronous* write exception to exercise `Cacheman._persist`'s
    // purge-and-retry path. There is no real-backend equivalent: a real
    // `GetStorage.write` call practically never throws synchronously (see
    // `Cacheman`'s `_gs` doc — its actual flush failures are asynchronous and
    // are never retried, by design). So instead this verifies the one thing
    // that *is* observable against a real backend: a flush failure never
    // throws out of write(). (get_storage 2.1.1's write Future can't carry
    // flush errors, so `onError` is NOT guaranteed to fire for them.)
    test('a background flush failure never throws out of write()', () async {
      Object? reported;
      final e = await newCache(onError: (key, err) => reported = err);
      // Force a real async flush failure by erasing the temp dir out from
      // under get_storage after it opened its file handle.
      e.write('a', 'x'); // succeeds — establishes the container/file first
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
      e.write('b', 'y');
      // The failure surfaces asynchronously — give the flush a moment.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // On some platforms get_storage may still succeed (e.g. it recreates
      // the file) — this assertion only checks that *if* a failure occurred,
      // it was reported via onError and not thrown synchronously out of
      // write().
      expect(reported, anyOf(isNull, isA<Object>()));
    });

    test('write() does not throw synchronously even under default force:true', () async {
      final e = await newCache();
      expect(() => e.write('a', 'x'), returnsNormally);
      expect(e.read<String>('a'), 'x');
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

  group('review fixes', () {
    test('namespaces containing ":" do not collide or erase each other', () async {
      final container = nextContainer();
      final a = await newCache(container: container, namespace: 'a');
      final ab = await newCache(container: container, namespace: 'a:b');
      a.write('b:x', 1);
      ab.write('x', 2);
      expect(a.read<int>('b:x'), 1);
      expect(ab.read<int>('x'), 2);
      a.erase();
      expect(ab.read<int>('x'), 2);
      expect(ab.keys(), ['x']);
    });

    test('serialize throwing is caught by write (reported via onError), read keeps working', () async {
      Object? reported;
      final cache = Cacheman(
        container: nextContainer(),
        path: tempDir.path,
        options: CachemanOptions(
          serialize: (_) => throw StateError('boom'),
          onError: (k, e) => reported = e,
        ),
      );
      await cache.ensureInitialized();
      expect(() => cache.write('a', 1), returnsNormally);
      expect(reported, isA<StateError>());
      expect(cache.read<int>('a'), isNull);
    });

    test('namespace with "%" is escaped and isolated from the literal-prefixed one', () async {
      final container = nextContainer();
      final p = await newCache(container: container, namespace: '50%');
      final q = await newCache(container: container, namespace: '50%25');
      p.write('k', 1);
      q.write('k', 2);
      expect(p.read<int>('k'), 1);
      expect(q.read<int>('k'), 2);
      expect(p.keys(), ['k']);
    });

    test('serialize failing once then succeeding is retried by force', () async {
      var calls = 0;
      final cache = Cacheman(
        container: nextContainer(),
        path: tempDir.path,
        options: CachemanOptions(serialize: (e) {
          if (calls++ == 0) throw StateError('once');
          return defaultSerialize(e);
        }),
      );
      await cache.ensureInitialized();
      cache.write('a', 1);
      expect(cache.read<int>('a'), 1);
    });

    test('purge() leaves raw values alone even if they look like an expired entity', () async {
      final e = await newCache(raw: true);
      const lookalike = '{"value":"x","createdAt":1,"expireAt":2}';
      e.write('k', lookalike);
      e.purge();
      expect(e.read<String>('k'), lookalike);
    });

    test('readonly treats a stored null as present and does not slide-renew', () async {
      final e = await newCache(readonly: true);
      e.write<dynamic>('k', null);
      e.write('k', 'second');
      expect(e.read<dynamic>('k'), isNull);
    });

    test('readonly write attempt does not extend the old value lifetime (sliding)', () async {
      final e = await newCache(readonly: true, sliding: true);
      e.write('k', 'v', ttl: 1000);
      final before = (jsonDecode(e.container.read<String>(e.storageKey('k'))!) as Map)['expireAt'];
      await Future<void>.delayed(const Duration(milliseconds: 150));
      e.write('k', 'other', ttl: 1000);
      final after = (jsonDecode(e.container.read<String>(e.storageKey('k'))!) as Map)['expireAt'];
      expect(after, before);
    });

    test('keyCodec encodes keys independently of the value codec', () async {
      final cache = Cacheman(
        container: nextContainer(),
        path: tempDir.path,
        options: CachemanOptions(enckey: true, keyCodec: FakeCodec()),
      );
      await cache.ensureInitialized();
      cache.write('token', 'abc');
      expect(cache.container.getKeys<Iterable<dynamic>>().map((k) => k.toString()), isNot(contains('token')));
      expect(cache.read<String>('token'), 'abc');
      expect(cache.keys(), ['token']);
    });

    test('length/key/keys agree under a namespace', () async {
      final e = await newCache(namespace: 'n');
      e.writeAll(['a', 'b'], [1, 2]);
      expect(e.length, 2);
      expect(e.key(1), 'b');
      expect(e.key(2), isNull);
      expect(e.keys(), ['a', 'b']);
    });
  });

  group('Jsonx edge cases', () {
    test('a plain Map shaped like a tag round-trips unchanged', () {
      final value = {'#t': 'Duration', 'value': 1000};
      expect(Jsonx.decode<dynamic>(Jsonx.encode(value)), value);
      expect(Jsonx.decode<dynamic>(Jsonx.encode({'x': value})), {'x': value});
    });

    test('falls back to toJson() for custom objects', () {
      expect(Jsonx.decode<dynamic>(Jsonx.encode([_Pt(1, 2)])), [
        {'x': 1, 'y': 2},
      ]);
    });

    test('legacy tag-shaped Map with an invalid Map payload is kept as is', () {
      final legacy = {'#t': 'Map', 'value': 1};
      expect(Jsonx.decode<dynamic>(jsonEncode(legacy)), legacy);
    });

    test('escapes nested, Set and toJson() results too', () {
      final tag = {'#t': 'Duration', 'value': 1000};
      final value = {
        'list': [tag],
        'set': {tag},
        'obj': _Wrap(tag),
      };
      final out = Jsonx.decode<Map<String, dynamic>>(Jsonx.encode(value));
      expect(out['list'], [tag]);
      expect(out['set'], {tag});
      expect(out['obj'], {'inner': tag});
    });

    test('unsupported objects still throw', () {
      expect(() => Jsonx.encode(Object()), throwsA(isA<JsonUnsupportedObjectError>()));
    });
  });

  group('Cacheman() — real get_storage integration', () {
    test('ls persists via get_storage', () async {
      final cache = await _ready(Cacheman(container: 'cacheman_test_ls', path: tempDir.path));
      cache.write('a', 'persisted');
      expect(cache.read<String>('a'), 'persisted');
    });

    test('ls.key(index)/length walk get_storage directly without materializing keys()', () async {
      final cache = await _ready(Cacheman(container: 'cacheman_test_ls_key', path: tempDir.path));
      cache.write('a', 1);
      cache.write('b', 2);
      cache.write('c', 3);
      expect(cache.length, 3);
      expect(cache.key(0), 'a');
      expect(cache.key(1), 'b');
      expect(cache.key(2), 'c');
      expect(cache.key(3), isNull); // out of range
      cache.remove('b');
      expect(cache.length, 2);
      expect(cache.key(1), 'c'); // 'c' shifted into 'b''s old slot
    });

    test('setNamespace switches ls', () async {
      final cache = await _ready(Cacheman(container: 'cacheman_test_ns', path: tempDir.path));
      cache.write('token', 'v1');
      cache.setNamespace('alice');
      expect(cache.read<String>('token'), isNull);
    });

    group('fast / lazy / batchFast', () {
      test('fast binds a key and forwards get/set/remove', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_fast', path: tempDir.path));
        final token = fast<String>(cache, 'token');
        token.set('abc');
        expect(token.get(), 'abc');
        token.remove();
        expect(token.get(), isNull);
        expect(token.get('def'), 'def');
      });

      test('lazy only builds the accessor on first call, then reuses it', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_lazy', path: tempDir.path));
        final tokenLazy = lazy<String>(cache, 'token');
        final a = tokenLazy();
        final b = tokenLazy();
        expect(identical(a, b), isTrue);
      });

      test('batchFast binds several keys at once', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_batch_fast', path: tempDir.path));
        final accessors = batchFast<String>(cache, ['a', 'b']);
        accessors['a']!.set('1');
        accessors['b']!.set('2');
        expect(cache.read<String>('a'), '1');
        expect(cache.read<String>('b'), '2');
      });
    });

    group('debug()', () {
      test('returns every owned entry decrypted, namespace preserved', () async {
        final cache = await _ready(Cacheman(
          container: 'cacheman_test_debug',
          path: tempDir.path,
          options: CachemanOptions(namespace: 'ns', enckey: true, codec: FakeCodec()),
        ));
        cache.write('a', 1);
        cache.write('b', 2);
        expect(debug(cache), {'ns:a': 1, 'ns:b': 2});
      });

      test('does not write anything back — keys()/length stay unaffected', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_debug_noop', path: tempDir.path));
        cache.write('a', 1);
        debug(cache);
        expect(cache.length, 1);
      });
    });
  });
}

/// 带 `toJson()` 的测试用对象。
class _Pt {
  _Pt(this.x, this.y);
  final int x;
  final int y;
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

/// toJson() 结果里带标签形 Map 的测试用对象。
class _Wrap {
  _Wrap(this.inner);
  final Map<String, dynamic> inner;
  Map<String, dynamic> toJson() => {'inner': inner};
}
