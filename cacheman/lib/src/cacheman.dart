import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:get_storage/get_storage.dart';

import 'engine.dart';
import 'get_storage_adapter.dart';
import 'memo.dart';

/// Unified, type-safe wrapper over `get_storage` (persistent): TTL & absolute
/// expiry, sliding renewal, namespaces, pluggable serialization, an optional
/// codec hook, and batch ops. All of `Engine`'s CRUD surface is exposed
/// directly on this class — there is no `.ls` indirection.
///
/// **Design note — why this is fully synchronous (unlike the sibling
/// `@codejoo/storage` TS project, whose `db`/IndexedDB tier returns
/// Promises)**: `get_storage`'s `read`/`write`/`remove` are synchronous
/// against its in-memory map once `init()` has completed — disk flush
/// happens in the background, debounced, and never blocks a read. There's no
/// second, genuinely-async persistent backend to justify a sync/async dual
/// API the way the TS version's `ls` (sync) vs `db` (async IndexedDB) split
/// does. So `Cacheman.create()` is the only `Future` boundary; every method
/// on [Cacheman] after that is synchronous.
///
/// 统一、类型安全地封装 `get_storage`（持久层）：TTL/绝对过期、滑动续期、
/// 命名空间、可插拔序列化、可选 codec 钩子、批量操作。`Engine` 的全部读写
/// 接口都直接挂在本类上——不再有 `.ls` 这层间接。
///
/// **设计说明——为什么这里全同步（不像姊妹 TS 项目 `@codejoo/storage`的
/// `db`/IndexedDB 层要返回 Promise）**：`get_storage` 的
/// `read`/`write`/`remove` 在 `init()` 完成之后，对它自己的内存态就是同步
/// 的——落盘是后台防抖做的，从不阻塞读。这里没有第二个真正异步的持久后端，
/// 犯不着像 TS 版 `ls`（同步）vs `db`（异步 IndexedDB）那样搞一套同步/异步
/// 二态 API。所以 `Cacheman.create()` 是唯一的 `Future` 边界，之后 [Cacheman]
/// 上的每个方法都是同步的。
///
/// ```dart
/// final cache = await Cacheman.create();
/// cache.write('token', 'abc');         // persists across restarts
/// cache.read<String>('token');         // 'abc' — synchronous
/// cache.setNamespace('alice');         // per-account isolation
/// await cache.destroy();
/// ```
class Cacheman {
  Cacheman._(this._engine);

  /// Internal engine instance, backed by a `get_storage` container. Survives
  /// process restarts.
  ///
  /// 内部引擎实例，`get_storage` container 支撑。进程重启后仍在。
  final Engine _engine;

  /// Creates and initializes a [Cacheman] instance. Must be awaited before
  /// first use — this is the only `Future` boundary in the whole API (see
  /// the class doc).
  ///
  /// [container]/[path] are forwarded to `GetStorage` (same container name ⇒
  /// same underlying data across `create()` calls — `get_storage` caches
  /// instances per container internally). [options] apply to this instance.
  ///
  /// 创建并初始化一个 [Cacheman] 实例。首次使用前必须 await——这是整个 API
  /// 里唯一的 `Future` 边界（见类文档）。
  ///
  /// [container]/[path] 透传给 `GetStorage`（同一个 container 名 ⇒
  /// `create()` 多次调用间是同一份底层数据——`get_storage` 内部按 container
  /// 名缓存实例）。[options] 作用于本实例。
  static Future<Cacheman> create({
    String container = 'cacheman',
    String? path,
    CachemanOptions options = const CachemanOptions(),
  }) async {
    // 不走 GetStorage.init(container)——它内部固定用 GetStorage(container)（不带
    // path）去建/取缓存实例，一旦先跑过一次就把这个 container 名永久钉死成
    // path=null，我们后面再传 path 也没用（factory 按 container 名读缓存，
    // 命中就直接返回旧实例，构造参数被无视）。这里改成自己先用带 path 的调用
    // 建好实例，再自己 await 它的 initStorage——WidgetsFlutterBinding 也要
    // 自己确保初始化（原来是 init() 内部帮着调的）。
    //
    // Not going through GetStorage.init(container) — it internally always
    // calls GetStorage(container) (no path) to create/fetch the cached
    // instance; once that's run once for this container name, `path` is
    // permanently baked in as null and any `path` we pass later is ignored
    // (the factory caches by container name — a cache hit just returns the
    // old instance, constructor args and all). Instead, construct the
    // instance ourselves WITH `path` first, then await its own
    // `initStorage` — and ensure `WidgetsFlutterBinding` ourselves (`init()`
    // used to do that for us).
    WidgetsFlutterBinding.ensureInitialized();
    final gs = GetStorage(container, path);
    await gs.initStorage;
    final engine = Engine(GetStorageAdapter(gs, onError: options.onError), Memo(), options);
    return Cacheman._(engine);
  }

  /// Reads a key. Returns [defaultValue] if absent/expired.
  ///
  /// 读取一个键。不存在/已过期时返回 [defaultValue]。
  T? read<T>(String key, [T? defaultValue]) => _engine.read<T>(key, defaultValue);

  /// Batch read: returns a same-length list, positionally paired with
  /// [defaults] (missing slots fall back to `null`).
  ///
  /// 批量读取：返回等长 list，跟 [defaults] 逐位对应（缺位为 `null`）。
  List<dynamic> readAll(List<String> keys, [List<dynamic>? defaults]) => _engine.readAll(keys, defaults);

  /// Writes a key, with optional per-call [ttl]/[expireAt]/[memoized].
  ///
  /// 写入一个键，可选 per-call 的 [ttl]/[expireAt]/[memoized]。
  void write<T>(String key, T value, {int? ttl, Object? expireAt, bool? memoized}) => _engine.write<T>(key, value, ttl: ttl, expireAt: expireAt, memoized: memoized);

  /// Batch write: [values] pairs positionally with [keys]; [ttl]/[expireAt]/
  /// [memoized] apply to every key. If [values] is shorter, missing slots are
  /// skipped (warned).
  ///
  /// 批量写入：[values] 跟 [keys] 逐位对应；[ttl]/[expireAt]/[memoized] 对
  /// 全部键生效。[values] 短于 [keys] 时，缺位的键跳过（警告）。
  void writeAll(List<String> keys, List<dynamic> values, {int? ttl, Object? expireAt, bool? memoized}) => _engine.writeAll(keys, values, ttl: ttl, expireAt: expireAt, memoized: memoized);

  /// Removes a key.
  ///
  /// 删除一个键。
  void remove(String key) => _engine.remove(key);

  /// Removes several keys at once.
  ///
  /// 一次删除多个键。
  void removeAll(List<String> keys) => _engine.removeAll(keys);

  /// With `namespace` or `enckey`: removes only this instance's keys.
  /// Otherwise erases the whole backend.
  ///
  /// 带 `namespace` 或 `enckey` 时：只删本实例管辖的键。否则整个后端清空。
  void erase() => _engine.erase();

  /// The `index`-th logical key (decrypted, namespace-stripped).
  ///
  /// 第 `index` 个逻辑键（已解密、去命名空间前缀）。
  String? key(int index) => _engine.key(index);

  /// All logical keys owned by this instance (decrypted, namespace-stripped).
  ///
  /// 本实例管辖的全部逻辑键（已解密、去命名空间前缀）。
  List<String> keys() => _engine.keys();

  /// Proactively deletes expired entries (owned, written by this library).
  /// Expiry is otherwise lazy.
  ///
  /// 主动清理已过期条目（本实例管辖、本库写入的）。平时是懒过期。
  void purge() => _engine.purge();

  /// Current namespace prefix (`''` if none set).
  ///
  /// 当前命名空间前缀（未设置时为 `''`）。
  String get namespace => _engine.namespace;

  /// Entry count. With `namespace`/`enckey`, counts only owned keys;
  /// otherwise the backend's global count.
  ///
  /// 条目数。带 `namespace`/`enckey` 时只数本实例管辖的键；否则是后端的
  /// 全局条目数。
  int get length => _engine.length;

  /// Switches the namespace prefix **in place** (great for per-account
  /// isolation on login/logout) — handles you already hold keep working; it
  /// only isolates, it does not erase the previous namespace's persisted
  /// data. Clears the memo cache.
  ///
  /// 原地切换命名空间前缀（很适合登入/登出时按账号隔离）——已经持有
  /// 的引用继续生效；只做隔离，不清除上个命名空间的落盘数据。清空 memo
  /// 缓存。
  void setNamespace([String? namespace]) {
    _engine.setNamespace(namespace);
  }

  /// Releases resources held by this instance: clears the memo read cache.
  /// Does **not** delete persisted data.
  ///
  /// 释放本实例占用的资源：清空 memo 读缓存。**不删除**已落盘数据。
  Future<void> destroy() async {
    _engine.destroy();
  }
}
