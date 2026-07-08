import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:get_storage/get_storage.dart';

import 'engine.dart';
import 'get_storage_adapter.dart';
import 'memo.dart';
import 'memory.dart';

/// Unified, type-safe wrapper over `get_storage` (persistent) and an
/// in-memory store: TTL & absolute expiry, sliding renewal, namespaces,
/// pluggable serialization, an optional codec hook, and batch ops.
///
/// **Design note — why this is fully synchronous (unlike the sibling
/// `@codejoo/storage` TS project, whose `db`/IndexedDB tier returns
/// Promises)**: `get_storage`'s `read`/`write`/`remove` are synchronous
/// against its in-memory map once `init()` has completed — disk flush
/// happens in the background, debounced, and never blocks a read. There's no
/// second, genuinely-async persistent backend to justify a sync/async dual
/// API the way the TS version's `ls`/`ss` (sync) vs `db` (async IndexedDB)
/// split does. So `Cacheman.create()` is the only `Future` boundary; every
/// method on [ls]/[ss] after that is synchronous.
///
/// 统一、类型安全地封装 `get_storage`（持久层）和一个纯内存存储：TTL/绝对
/// 过期、滑动续期、命名空间、可插拔序列化、可选 codec 钩子、批量操作。
///
/// **设计说明——为什么这里全同步（不像姊妹 TS 项目 `@codejoo/storage`的
/// `db`/IndexedDB 层要返回 Promise）**：`get_storage` 的
/// `read`/`write`/`remove` 在 `init()` 完成之后，对它自己的内存态就是同步
/// 的——落盘是后台防抖做的，从不阻塞读。这里没有第二个真正异步的持久后端，
/// 犯不着像 TS 版 `ls`/`ss`（同步）vs `db`（异步 IndexedDB）那样搞一套
/// 同步/异步二态 API。所以 `Cacheman.create()` 是唯一的 `Future` 边界，之后
/// [ls]/[ss] 上的每个方法都是同步的。
///
/// ```dart
/// final cache = await Cacheman.create();
/// cache.ls.set('token', 'abc');           // persists across restarts
/// cache.ls.get<String>('token');          // 'abc' — synchronous
/// cache.ss.set('draft', {'id': 1}, ttl: 60000); // gone on next process start
/// cache.setNamespace('alice');            // per-account isolation
/// await cache.destroy();
/// ```
class Cacheman {
  Cacheman._(this.ls, this.ss);

  /// Persistent tier, backed by a `get_storage` container. Survives process
  /// restarts.
  ///
  /// 持久层，`get_storage` container 支撑。进程重启后仍在。
  final Engine ls;

  /// Pure in-memory tier. Cleared on process restart — the natural Dart
  /// analogue of the TS version's `sessionStorage`-backed `ss` (gone once the
  /// "session" — here, the process — ends).
  ///
  /// 纯内存层。进程重启即丢——对应 TS 版基于 sessionStorage 的 `ss`
  /// 的自然 Dart 类比（"会话"结束——这里是进程结束——数据就没了）。
  final Engine ss;

  /// Creates and initializes a [Cacheman] instance. Must be awaited before
  /// first use — this is the only `Future` boundary in the whole API (see
  /// the class doc).
  ///
  /// [container]/[path] are forwarded to `GetStorage` (same container name ⇒
  /// same underlying data across `create()` calls — `get_storage` caches
  /// instances per container internally). [options] apply to both [ls] and
  /// [ss]. [cap] limits [ss] only (see [Memory.cap]) — `null` (default)
  /// means unlimited; [ls] is disk-backed and has no such cap.
  ///
  /// 创建并初始化一个 [Cacheman] 实例。首次使用前必须 await——这是整个 API
  /// 里唯一的 `Future` 边界（见类文档）。
  ///
  /// [container]/[path] 透传给 `GetStorage`（同一个 container 名 ⇒
  /// `create()` 多次调用间是同一份底层数据——`get_storage` 内部按 container
  /// 名缓存实例）。[options] 同时作用于 [ls] 和 [ss]。[cap] 只限制 [ss]
  /// （见 [Memory.cap]）——`null`（默认）不限制；[ls] 落盘，没有这个上限。
  static Future<Cacheman> create({
    String container = 'cacheman',
    String? path,
    CachemanOptions options = const CachemanOptions(),
    int? cap,
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
    final ls = Engine(GetStorageAdapter(gs, onError: options.onError), Memo(), options);
    final ss = Engine(Memory(cap: cap), Memo(), options);
    return Cacheman._(ls, ss);
  }

  /// Switches the namespace prefix of both [ls] and [ss] **in place** (great
  /// for per-account isolation on login/logout) — handles you already hold
  /// keep working; it only isolates, it does not erase the previous
  /// namespace's persisted data. Clears both memo caches.
  ///
  /// 原地切换 [ls] 和 [ss] 的命名空间前缀（很适合登入/登出时按账号隔离）——
  /// 已经持有的引用继续生效；只做隔离，不清除上个命名空间的落盘数据。清空
  /// 两边的 memo 缓存。
  void setNamespace([String? namespace]) {
    ls.setNamespace(namespace);
    ss.setNamespace(namespace);
  }

  /// Releases resources held by this instance: clears both memo read caches.
  /// Does **not** delete persisted data.
  ///
  /// 释放本实例占用的资源：清空两边的 memo 读缓存。**不删除**已落盘数据。
  Future<void> destroy() async {
    ls.destroy();
    ss.destroy();
  }
}
