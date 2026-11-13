import 'dart:convert';

import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';

/// Error matcher label. / 错误断言标签。
const _causeLabel = 'cause';

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

/// Counts key decoding to verify enumeration reuses logical mappings.
/// 统计键解码次数，验证枚举会复用逻辑键映射。
class _CountingCodec extends FakeCodec {
  /// Number of decode calls. / 解码调用次数。
  int decodeCalls = 0;

  /// Counts and delegates to the reversible test codec.
  /// 计数后转发到可逆的测试 codec。
  @override
  String? decode(String value) {
    decodeCalls++;
    return super.decode(value);
  }
}

/// Fails decoding with a known exception. / 用已知异常模拟解码失败。
class _ThrowingCodec extends FakeCodec {
  /// Stores the error to throw. / 保存要抛出的异常。
  _ThrowingCodec(this.error);

  /// Original error used to verify identity. / 用于验证同一性的原始异常。
  final Object error;

  /// Throws the original error unchanged. / 原样抛出原始异常。
  @override
  String? decode(String value) => throw error;
}

void main() {
  var containerSeq = 0;

  /// 每次创建独立名称，避免内存容器在测试之间共享数据。
  String nextContainer() => 'cacheman_test_${containerSeq++}';

  /// 使用默认纯 Dart 内存后端验证缓存语义。
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

  test('memory write remove erase notify synchronously before return', () async {
    final cache = await newCache();
    final events = <String?>[];
    final cancel = cache.container.listen((key) {
      events.add(key);
    });
    final write = cache.container.write('sync', 'value');
    expect(events, ['sync']);
    final remove = cache.container.remove('sync');
    expect(events, ['sync', 'sync']);
    final erase = cache.container.erase();
    expect(events, ['sync', 'sync', null]);
    cancel();
    await Future.wait([write, remove, erase]);
  });

  test('forwarding subclass keeps memory hub, watch and incremental index', () async {
    final name = nextContainer();
    final base = await newCache(container: name);
    final sub = _Forwarding(container: name);
    await sub.ensureInitialized();
    final seen = <String?>[];
    final stop = sub.watch<String>('k', seen.add);
    base.write('k', 'v');
    expect(seen, ['v']);
    expect(sub.keys(), contains('k'));
    stop();
  });

  group('basic read/write/remove', () {
    test('writes assert before initialization and succeed after awaiting it', () async {
      const key = 'guarded';
      const value = 'ready';
      for (final raw in [false, true]) {
        final cache = Cacheman(
          container: nextContainer(),
              options: CachemanOptions(raw: raw),
        );
        expect(
          () => cache.write(key, value),
          throwsA(isA<AssertionError>().having((error) => error.message, 'message', contains('await ensureInitialized()'))),
        );
        await cache.ensureInitialized();
        expect(cache.read<String>(key), isNull);
        cache.write(key, value);
        expect(cache.read<String>(key), value);
      }
    });

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
    const damagedKey = 'damaged';
    const fallback = 'fallback';
    const secret = 'secret';

    test('enckey keys()/key() reuse decoded logical keys across repeated enumeration', () async {
      const keys = ['x', 'y'];
      final codec = _CountingCodec();
      final e = await newCache(enckey: true, codec: codec, namespace: 'a');
      e.writeAll(keys, [1, 2]);
      expect(e.keys(), keys);
      final calls = codec.decodeCalls;
      expect(e.keys(), keys);
      expect(e.key(0), keys.first);
      expect(e.key(1), keys.last);
      expect(codec.decodeCalls, calls);
    });

    test('setNamespace clears enckey logical mappings before enumerating the new scope', () async {
      const firstNs = 'a';
      const firstKey = 'x';
      const secondKey = 'y';
      const fullKey = '$firstNs:$firstKey';
      final e = await newCache(enckey: true, codec: FakeCodec(), namespace: firstNs);
      e.write(firstKey, 1);
      expect(e.keys(), [firstKey]);
      e.setNamespace();
      expect(e.keys(), [fullKey]); // same storage key, different logical key
      expect(e.key(0), fullKey);
      e.setNamespace('b');
      expect(e.keys(), isEmpty);
      e.write(secondKey, 2);
      expect(e.keys(), [secondKey]);
      e.setNamespace(firstNs);
      expect(e.keys(), [firstKey]);
      expect(e.key(0), firstKey);
    });

    test('codeable + codec obfuscates the persisted string but reads decode transparently', () async {
      final container = nextContainer();
      final e = await newCache(container: container, codeable: true, codec: FakeCodec());
      e.write('a', secret);
      expect(e.read<String>('a'), secret);
      // read the raw string straight from memory (same
      // cached instance, already initialized) to confirm it never shows the
      // plaintext.
      final gsRaw = MemoryStorage.named(container).read<dynamic>('a');
      expect(gsRaw, isA<String>());
      expect(gsRaw as String, isNot(contains(secret)));
    });

    test('a null codec result is reported once, deleted and returned as the default', () async {
      const key = damagedKey;
      final container = nextContainer();
      final withCodec = await newCache(container: container, codeable: true, codec: FakeCodec('right'));
      withCodec.write(key, secret);
      final errors = <(String, Object)>[];
      final wrongCodec = await newCache(
        container: container,
        codeable: true,
        codec: FakeCodec('wrong'),
        onError: (key, error) => errors.add((key, error)),
      );
      wrongCodec.purge();
      wrongCodec.purge();
      expect(errors, isEmpty);
      expect(wrongCodec.container.hasData(key), isTrue);
      expect(wrongCodec.read<String>(key, fallback), fallback);
      expect(errors, hasLength(1));
      expect(errors.single.$1, key);
      expect(errors.single.$2, isA<CorruptEntryError>().having((e) => e.cause, _causeLabel, isA<FormatException>()).having((e) => e.dropped, 'dropped', isTrue));
      expect(wrongCodec.container.hasData(key), isFalse);
      expect(wrongCodec.read<String>(key, fallback), fallback);
      expect(errors, hasLength(1));
    });

    test('a throwing replacement codec reports the original exception once and deletes the entry', () async {
      const key = damagedKey;
      final container = nextContainer();
      final writer = await newCache(container: container, codeable: true, codec: FakeCodec());
      writer.write(key, secret);
      final failure = StateError('decode failed');
      final errors = <(String, Object)>[];
      final reader = await newCache(
        container: container,
        codeable: true,
        codec: _ThrowingCodec(failure),
        onError: (key, error) => errors.add((key, error)),
      );
      expect(reader.read<String>(key, fallback), fallback);
      expect(errors, hasLength(1));
      expect(errors.single.$1, key);
      expect(errors.single.$2, isA<CorruptEntryError>().having((e) => e.cause, _causeLabel, same(failure)));
      expect(reader.container.hasData(key), isFalse);
      expect(reader.read<String>(key, fallback), fallback);
      expect(errors, hasLength(1));
    });

    test('a throwing replacement deserialize reports once after deleting the entry', () async {
      const key = damagedKey;
      final container = nextContainer();
      final writer = await newCache(container: container);
      writer.write(key, secret);
      final failure = FormatException('deserialize failed');
      final errors = <(String, Object)>[];
      final reader = await _ready(Cacheman(
        container: container,
          options: CachemanOptions(
          deserialize: (_) => throw failure,
          onError: (key, error) {
            expect(writer.container.hasData(key), isFalse);
            errors.add((key, error));
          },
        ),
      ));
      expect(reader.read<String>(key, fallback), fallback);
      expect(errors, hasLength(1));
      expect(errors.single.$1, key);
      expect(errors.single.$2, isA<CorruptEntryError>().having((e) => e.cause, _causeLabel, same(failure)));
      expect(reader.container.hasData(key), isFalse);
      expect(reader.read<String>(key, fallback), fallback);
      expect(errors, hasLength(1));
    });

    test('raw reads bypass throwing codecs/deserializers and do not report decode errors', () async {
      const key = 'raw';
      const value = 'untouched';
      final errors = <Object>[];
      final cache = await _ready(Cacheman(
        container: nextContainer(),
          options: CachemanOptions(
          raw: true,
          codeable: true,
          codec: _ThrowingCodec(StateError('must not decode')),
          deserialize: (_) => throw StateError('must not deserialize'),
          onError: (_, error) => errors.add(error),
        ),
      ));
      cache.write(key, value);
      expect(cache.read<String>(key), value);
      expect(cache.container.hasData(key), isTrue);
      expect(errors, isEmpty);
    });

    test('enckey obfuscates the storage key so foreign readers cannot see it', () async {
      final container = nextContainer();
      final e = await newCache(container: container, enckey: true, codec: FakeCodec());
      e.write('token', 'abc');
      final gsKeys = MemoryStorage.named(container).keys.map((k) => k.toString());
      expect(gsKeys, isNot(contains('token')));
      expect(e.read<String>('token'), 'abc');
      expect(e.keys(), ['token']); // logical keys are still plaintext to the owner
    });
  });

  group('force / onError', () {
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
          options: CachemanOptions(
          serialize: (_) => throw StateError('boom'),
          onError: (k, e) => reported = e,
        ),
      );
      await cache.ensureInitialized();
      expect(() => cache.write('a', 1), returnsNormally);
      expect(reported, isA<SerializeError>().having((e) => e.cause, _causeLabel, isA<StateError>()));
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

    test('serialize failing once is not retried by force', () async {
      var calls = 0;
      final cache = Cacheman(
        container: nextContainer(),
          options: CachemanOptions(serialize: (e) {
          if (calls++ == 0) throw StateError('once');
          return defaultSerialize(e);
        }),
      );
      await cache.ensureInitialized();
      cache.write('a', 1);
      expect(calls, 1);
      expect(cache.read<int>('a'), isNull);
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
          options: CachemanOptions(enckey: true, keyCodec: FakeCodec()),
      );
      await cache.ensureInitialized();
      cache.write('token', 'abc');
      expect(cache.container.keys.map((k) => k.toString()), isNot(contains('token')));
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

  group('Cacheman() — default memory integration', () {
    test('ls shares data via named memory', () async {
      final cache = await _ready(Cacheman(container: 'cacheman_test_ls'));
      cache.write('a', 'persisted');
      expect(cache.read<String>('a'), 'persisted');
    });

    test('ls.key(index)/length walk memory directly without materializing keys()', () async {
      final cache = await _ready(Cacheman(container: 'cacheman_test_ls_key'));
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
      final cache = await _ready(Cacheman(container: 'cacheman_test_ns'));
      cache.write('token', 'v1');
      cache.setNamespace('alice');
      expect(cache.read<String>('token'), isNull);
    });

    group('fast / lazy / batchFast', () {
      test('fast binds a key and forwards get/set/remove', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_fast'));
        final token = fast<String>(cache, 'token');
        token.set('abc');
        expect(token.get(), 'abc');
        token.remove();
        expect(token.get(), isNull);
        expect(token.get('def'), 'def');
      });

      test('lazy only builds the accessor on first call, then reuses it', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_lazy'));
        final tokenLazy = lazy<String>(cache, 'token');
        final a = tokenLazy();
        final b = tokenLazy();
        expect(identical(a, b), isTrue);
      });

      test('batchFast binds several keys at once', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_batch_fast'));
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
              options: CachemanOptions(namespace: 'ns', enckey: true, codec: FakeCodec()),
        ));
        cache.write('a', 1);
        cache.write('b', 2);
        expect(debug(cache), {'ns:a': 1, 'ns:b': 2});
      });

      test('does not write anything back — keys()/length stay unaffected', () async {
        final cache = await _ready(Cacheman(container: 'cacheman_test_debug_noop'));
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

/// Plain forwarding subclass: no overridden primitives, so it must keep the
/// default memory behavior (shared hub, watch, incremental index).
/// 只转发构造参数的子类：未覆写原语，必须保留默认内存行为。
class _Forwarding extends Cacheman {
  _Forwarding({super.container});
}
