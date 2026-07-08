// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';

/// Toy XOR+Base64 [Codec] — NOT for real use (see [Codec]'s doc: this
/// package ships no implementation on purpose, bring your own). Good enough
/// here to demonstrate `codeable` (value obfuscation) and `enckey` (key
/// obfuscation).
class XorCodec implements Codec {
  XorCodec(this.key);
  final String key;

  @override
  String encode(String value) => base64Encode(_xor(utf8.encode(value)));

  @override
  String? decode(String value) {
    try {
      return utf8.decode(_xor(base64Decode(value)));
    } catch (_) {
      return null;
    }
  }

  List<int> _xor(List<int> bytes) => [
        for (var i = 0; i < bytes.length; i++) bytes[i] ^ key.codeUnitAt(i % key.length),
      ];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Plain instance — ls (persistent, get_storage-backed) / ss (pure
  // in-memory), memoized reads, shallow clones, sliding TTL renewal.
  final cache = await Cacheman.create(
    container: 'cacheman_example',
    options: const CachemanOptions(memoized: true, cloned: true, sliding: true),
  );

  // A second instance with a codec — demonstrates `codeable` (values
  // obfuscated at rest) and `enckey` (keys obfuscated too).
  final secure = await Cacheman.create(
    container: 'cacheman_example_secure',
    options: CachemanOptions(codeable: true, enckey: true, codec: XorCodec('demo-key')),
  );

  // A Jsonx-backed instance — round-trips DateTime/Duration/Set/BigInt/Uri/
  // RegExp, which plain jsonEncode/jsonDecode can't.
  final jsonxCache = await Cacheman.create(
    container: 'cacheman_example_jsonx',
    options: CachemanOptions(
      serialize: (e) => Jsonx.encode(e.toJson()),
      deserialize: (s) => CacheEntity.fromJson(Jsonx.decode<Map<String, dynamic>>(s)),
    ),
  );

  runApp(CachemanExampleApp(cache: cache, secure: secure, jsonxCache: jsonxCache));
}

class CachemanExampleApp extends StatelessWidget {
  const CachemanExampleApp({super.key, required this.cache, required this.secure, required this.jsonxCache});

  final Cacheman cache;
  final Cacheman secure;
  final Cacheman jsonxCache;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'cacheman example',
        home: DemoPage(cache: cache, secure: secure, jsonxCache: jsonxCache),
      );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, required this.cache, required this.secure, required this.jsonxCache});

  final Cacheman cache;
  final Cacheman secure;
  final Cacheman jsonxCache;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _log = <String>[];

  // Key-bound shortcut accessor (see `fast`/`lazy`/`batchFast`) — stops the
  // key from being repeated at every call site.
  late final _fastToken = fast<String>(widget.cache.ls, 'fast-token');

  void _add(String line) {
    print(line);
    setState(() => _log.insert(0, line));
  }

  Future<void> _runAll() async {
    _log.clear();
    final cache = widget.cache;

    // ── basic get/set/remove, ls vs ss ────────────────────────────────────
    cache.ls.set('token', 'abc'); // persists across restarts (get_storage)
    cache.ss.set('draft', {'id': 1}); // pure in-memory, gone on next launch
    _add('ls.get<String>("token") -> ${cache.ls.get<String>('token')}');
    _add('ss.get("draft") -> ${cache.ss.get<Map<String, dynamic>>('draft')}');

    // ── fast accessor ──────────────────────────────────────────────────────
    _fastToken.set('via-fast');
    _add('fast(ls, "fast-token").get() -> ${_fastToken.get()}');

    // ── batchFast ────────────────────────────────────────────────────────
    final ids = batchFast<int>(cache.ss, ['id-a', 'id-b']);
    ids['id-a']!.set(1);
    ids['id-b']!.set(2);
    _add('batchFast -> id-a=${ids['id-a']!.get()}, id-b=${ids['id-b']!.get()}');

    // ── ttl / expiry ─────────────────────────────────────────────────────
    cache.ss.set('short-lived', 'x', ttl: 200);
    _add('ss "short-lived" right after set -> ${cache.ss.get<String>('short-lived')}');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _add('ss "short-lived" after 250ms -> ${cache.ss.get<String>('short-lived')} (expired)');

    // ── sliding renewal (this instance was created with sliding: true) ────
    cache.ss.set('session', 'alive', ttl: 5000);
    cache.ss.get<String>('session'); // a read past 10% of ttl renews expireAt
    _add('ss "session" read once -> sliding renewal keeps it alive on repeat reads');

    // ── namespace: per-account isolation, in place ─────────────────────────
    cache.setNamespace('alice');
    cache.ls.set('ns-token', 'alice-token');
    _add('after setNamespace("alice"), ls.get("ns-token") -> ${cache.ls.get<String>('ns-token')}');
    cache.setNamespace(); // back to global — isolates, does not erase 'alice' data
    _add('after setNamespace(), ls.get("ns-token") -> ${cache.ls.get<String>('ns-token')} (nothing here globally)');

    // ── batch ops ────────────────────────────────────────────────────────
    cache.ls.setAll(['a', 'b', 'c'], [1, 2, 3]);
    _add('getAll(["a","b","c"]) -> ${cache.ls.getAll([
          'a',
          'b',
          'c',
        ])}');
    cache.ls.removeAll(['a', 'c']);
    _add('after removeAll(["a","c"]) -> ${cache.ls.getAll([
          'a',
          'b',
          'c',
        ])}');

    // ── debug() snapshot ─────────────────────────────────────────────────
    _add('debug(ls) -> ${debug(cache.ls)}');

    // ── codec / enckey (secure instance) ────────────────────────────────
    final secure = widget.secure;
    secure.ls.set('secret', 'top secret value');
    _add('secure.ls.get("secret") -> ${secure.ls.get<String>('secret')} (value + key obfuscated at rest)');

    // ── Jsonx round-trip (jsonxCache instance) ────────────────────────────
    final jsonxCache = widget.jsonxCache;
    jsonxCache.ls.set('meta', {
      'when': DateTime.now(),
      'wait': const Duration(minutes: 5),
      'ids': {1, 2, 3},
    });
    _add('jsonxCache.ls.get("meta") -> ${jsonxCache.ls.get<Map<String, dynamic>>('meta')}');

    // ── raw / readonly (standalone Engine, no get_storage needed) ─────────
    final raw = Engine(Memory(), Memo(), const CachemanOptions(raw: true));
    raw.set('plain', 'no-envelope');
    _add('raw engine "plain" -> ${raw.get<String>('plain')}');

    final readonly = Engine(Memory(), Memo(), const CachemanOptions(readonly: true));
    readonly.set('once', 'first');
    readonly.set('once', 'second'); // discarded — key already has a value
    _add('readonly engine "once" -> ${readonly.get<String>('once')} (second write discarded)');

    // ── cleanup ──────────────────────────────────────────────────────────
    await cache.destroy();
    await secure.destroy();
    await jsonxCache.destroy();
    _add('destroy()ed all three — memo caches cleared, persisted data kept');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('cacheman example')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton(
                onPressed: _runAll,
                child: const Text('Run all demos'),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text(_log[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
            ),
          ],
        ),
      );
}
