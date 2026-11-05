# cacheman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/cacheman.svg)](https://pub.dev/packages/cacheman)

一个轻量、类型安全的封装，包住 [`get_storage`](https://pub.dev/packages/get_storage)（持久层），对外一套统一 API：TTL 与绝对过期、滑动续期、命名空间、可插拔序列化、可选 codec 钩子、键绑定的快捷访问器。姊妹 TS 项目 `@codejoo/storage` 的 Dart/Flutter 版本。

`Cacheman` 只需 `await cache.ensureInitialized()` 一次之后全同步——原因见 `Cacheman` 的类文档。

## 安装

```yaml
dependencies:
  cacheman:
    path: ../cacheman # 或发布后改用 git/pub 依赖
```

## 快速上手

```dart
import 'package:cacheman/cacheman.dart';

final cache = Cacheman();
await cache.ensureInitialized();

cache.write('token', 'abc');       // 持久化，跨进程重启（get_storage）
cache.read<String>('token');       // 'abc' —— 同步
cache.write('session', 1, ttl: 60000); // 60 秒后过期
cache.remove('token');

cache.setNamespace('alice');        // 原地按账号隔离
```

## API

### `Cacheman({container, path, options})`

构造一个 `Cacheman`（持久层，`get_storage` 支撑），全部读写接口直接挂在上面——不再有 `.ls` 这层间接。同步——任何读写前需先调用并 `await` 一次 `ensureInitialized()`。

### `cache.ensureInitialized()`

Cacheman CRUD API 唯一的 `Future` 边界，等待本实例对应 container 的磁盘态加载完。

子类化：`Cacheman` 的构造函数和 `ensureInitialized()` 都是普通成员，不是工厂方法，子类只需把构造参数用 `super(...)` 转发即可，不需要额外的工厂样板代码：

```dart
class MyCacheman extends Cacheman {
  MyCacheman({super.container, super.path, super.options});
  int extra = 0;
}

final cache = MyCacheman();
await cache.ensureInitialized();
```

### `Cacheman` 方法

| 方法 | 说明 |
| --- | --- |
| `read<T>(key, [default])` | 读取；缺失/过期/不可解码 → `default`（或 `null`）。 |
| `write<T>(key, value, {ttl, expireAt})` | 写入。`ttl` 单位毫秒。 |
| `remove(key)` | 删除。 |
| `readAll(keys, [defaults])` / `writeAll(keys, values, {...})` / `removeAll(keys)` | 批量，按位置对应。 |
| `keys()` / `key(index)` / `length` | 枚举/统计本实例管辖的键。 |
| `purge()` | 主动删除已过期条目（平时是懒过期）。 |
| `erase()` | 清空本实例管辖的键（namespace/enckey 范围内），或整个后端。 |
| `namespace` / `setNamespace([ns])` | 当前前缀 / 原地切换。 |
| `container` | 底层 `get_storage` 的 `GetStorage` 实例——给需要拿到原始 container 的互操作场景用（比如用 `listenKey` 监听外部变更）。 |
| `storageKey(key)` | `key` 实际落盘用的 key（加了命名空间前缀，`enckey` 时还会编码）——传给 `container.listenKey(...)` 的应该是这个，而不是 `key` 本身。 |

### `CachemanOptions`

`serialize`/`deserialize`、`codeable`/`codec`/`keyCodec`、`sliding`、`namespace`、`raw`、`force`、`readonly`、`enckey`、`onError`——精确语义见 `lib/src/options.dart` 里每个字段的文档注释。

不可解码的条目在读取时被删除，并通过 `onError(storageKey, error)`（或 print）上报。
保留原始解码/反序列化异常；codec 返回 null 时使用 `FormatException`。
purge/readonly 探测不上报此类失败；raw 读取跳过解码。

**本包不内置任何 codec 实现。** `Codec` 只是一个 `encode`/`decode` 字符串接口——混淆、真加密、压缩，怎么实现随你。

### `fast<V>(cache, key)` / `lazy<V>(cache, key)` / `batchFast<V>(cache, keys)`

键绑定的快捷访问器——见 `lib/src/fast.dart`。

### GetX 响应式接入（`container` + `storageKey`）

`get_storage` 依赖 `get`，因此 `get` 是本包的传递依赖。`container`/`storageKey` 提供互操作接口，本包未内置 GetX 绑定。如果你使用 GetX，靠这两个就能自己搭一个类似 VueUse `useStorage` 的响应式封装：

```dart
import 'dart:convert';
import 'package:cacheman/cacheman.dart';
import 'package:get/get.dart';

/// Compare JSON-compatible values. / 比较可 JSON 序列化的值。
bool sameValue(Object? a, Object? b) => a == b || jsonEncode(a) == jsonEncode(b);

/// Bind with a feedback guard. / 带回写守卫的绑定。
Rx<V?> reactive<V>(Cacheman cache, String key) {
  final rx = Rx<V?>(cache.read<V>(key));

  // 同一 isolate 内对这个 container 的写入会更新 Rx。
  cache.container.listenKey(cache.storageKey(key), (dynamic _) {
    final next = cache.read<V>(key);
    if (!sameValue(rx.value, next)) rx.value = next;
  });

  // 回写前比较：反序列化出的 Map/List/对象每次都是新实例。
  ever(rx, (V? v) {
    if (sameValue(cache.read<V>(key), v)) return;
    v == null ? cache.remove(key) : cache.write<V>(key, v);
  });

  return rx;
}

final token = reactive<String>(cache, 'token');
Obx(() => Text(token.value ?? 'no token'));
token.value = 'abc123'; // 界面自动刷新，并持久化
```

比较时先用 `==`，再对集合和带 `toJson()` 的对象比较 JSON 内容。
对于 JSON 无法编码的值，按业务的值语义调整 `sameValue`。实际项目中应保留
`listenKey` 返回的取消函数和 `ever` 返回的 `Worker`，并随所属对象一起释放。

- `container.listenKey` 的回调是**同步**的；缓存写入返回前就可能重入监听器。
  上面的守卫可避免内容相同的值反复回写。
- 整容器 `erase()` 上报的变更键是 `""`，监听非空 `storageKey(key)` 收不到通知。
  需要自行处理（例如通过 container 级的 `listen` 检查 `container.changes` 并重置 Rx）。
  `cache.erase()` 在无 namespace/enckey 时走整容器清空；有作用域时逐个删除自有键并通知对应键。
- 不同 isolate 各有独立的内存 map 和监听器；另一 isolate 的写入不会更新或通知此绑定，
  跨 isolate 同步需要自行安排。

只要可能用到 `enckey`，就应该用 `cache.storageKey(key)`，而不是 `cache.namespace + key`——codec 的编码逻辑是私有可插拔的细节，`storageKey` 已经帮你处理好了。

### `debug(cache)`

某个引擎全部管辖条目的解密快照，`{ "namespace:key": value }`——见 `lib/src/debug.dart`。

### `Jsonx`

兼容 `jsonEncode`/`jsonDecode` 的序列化器，额外支持 `DateTime` / `Duration` / `Set` / `BigInt` / `Uri` / `RegExp` 的可逆往返。把 `Jsonx.encode`/`Jsonx.decode<T>`（包一层去对上 `CacheEntity <-> String` 的签名）传给 `CachemanOptions.serialize`/`deserialize`——`decode<T>` 会把结果转型成 `T`（比如 `Jsonx.decode<Map<String, dynamic>>(s)`）。设计上不可逆的：自定义 `Enum` 和 key 不是 `String` 的 `Map`——见 `lib/src/jsonx.dart` 的文档注释。

## 分层存储 / 自定义底层

推荐多个实例并行：小型高频数据用同步 `Cacheman`（默认 `get_storage`，整个 container 全量
加载进内存），大值用自定义 `AsyncCacheman` 子类按需读盘。由调用处选择实例，不自动路由或迁移。
两类都不额外缓存读取的值。cacheman 负责 namespace、TTL/绝对过期、滑动续期、信封、序列化/codec、
raw/readonly、force 和归属语义；子类只提供底层原语。`lib/` 不内置 Hive、文件、SharedPreferences
等新后端，也不增加依赖。

### 同步原语：SharedPreferencesWithCache

覆写六个 protected 钩子：`initRaw`、`getRaw`、`keysRaw`、`setRaw`、`removeRaw`、`clearRaw`。
读取/枚举同步完成；写删清空必须在**返回前完成内存态更新**，`Future<void>` 仅承载后台持久化错误。
Future 失败会上报，但不参与 `force` 重试；同步序列化/原语异常可清过期后重试一次。
写删覆写方法保持非 `async`，直接转发到底层的即时内存更新操作。

下面是应用内适配器示意（只在应用中添加 `shared_preferences`，不添加到本包）：

```dart
import 'package:cacheman/cacheman.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-owned synchronous preferences adapter. / 应用自有的同步偏好适配器。
class PreferencesCache extends Cacheman {
  /// Builds without opening a backend. / 构造时不打开后端。
  PreferencesCache({super.options});
  /// Backend initialized by ensureInitialized. / 由 ensureInitialized 初始化的后端。
  late final SharedPreferencesWithCache prefs;

  @override
  Future<void> initRaw(CacheContext ctx) async {
    prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
  }

  @override
  Object? getRaw(CacheContext ctx, String k) => prefs.get(k);
  @override
  Iterable<String> keysRaw(CacheContext ctx) => prefs.keys;
  @override
  Future<void> setRaw(CacheContext ctx, String k, String v) => prefs.setString(k, v);
  @override
  Future<void> removeRaw(CacheContext ctx, String k) => prefs.remove(k);
  @override
  Future<void> clearRaw(CacheContext ctx) => prefs.clear();
}
```

[SharedPreferencesWithCache](https://pub.dev/packages/shared_preferences) 提供带缓存的同步读取；其当前
[实现](https://github.com/flutter/packages/blob/main/packages/shared_preferences/shared_preferences/lib/src/shared_preferences_async.dart)
在返回持久化 Future 前更新缓存。使用时核对所选后端/版本的契约。
`Cacheman.container` 仍是默认 GetStorage 的互操作入口；完全自定义的子类访问它也会创建默认容器。
覆写全部原语即可完全避开默认后端。默认 `GetStorage(container, path)` 改为惰性创建，初始化或首次
访问 container 时仍携带构造参数中的 path。同名容器仍遵循 GetStorage 的首次构造 path 生效规则，
其先后现在取决于首次访问后端，而非 Cacheman 实例的构造顺序。
同步自有键集合仍只追踪本实例写删；外部变更后可用 `setNamespace` 使其重建。

### 异步原语：Hive CE LazyBox

`AsyncCacheman({options})` 是抽象类，不接受 container/path。必须实现 `getRaw`、`setRaw`、
`removeRaw`、`keysRaw`；`initRaw` 可选，用于打开后端，默认不操作。`clearRaw` 可选覆写，默认
枚举并逐个删除 `keysRaw` 返回的所有键。所有原语接收真实存储键，写入值为字符串。
[Hive CE LazyBox](https://pub.dev/documentation/hive_ce/latest/hive_ce/LazyBox-class.html) 每次按需读取值，
不会像普通 Box 一样保留全部值（键元数据仍由后端维护）。应用先配置 Hive，再初始化适配器；使用
专用、仅含字符串键的 LazyBox。只在消费应用添加 `hive_ce`。

```dart
import 'package:cacheman/cacheman.dart';
import 'package:hive_ce/hive.dart';

/// App-owned on-demand disk cache. / 应用自有的按需磁盘缓存。
class HiveCache extends AsyncCacheman {
  /// Opens the named box during initialization. / 初始化时打开指定 box。
  HiveCache(this.boxName, {super.options});
  /// Dedicated box name. / 专用 box 名称。
  final String boxName;
  /// Application owns closing this handle. / 应用负责关闭此句柄。
  late final LazyBox<String> box;

  @override
  Future<void> initRaw(CacheContext ctx) async {
    box = await Hive.openLazyBox<String>(boxName);
  }
  @override
  Future<Object?> getRaw(CacheContext ctx, String k) async => await box.get(k);
  @override
  Future<void> setRaw(CacheContext ctx, String k, String v) => box.put(k, v);
  @override
  Future<void> removeRaw(CacheContext ctx, String k) => box.delete(k);
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async => box.keys.cast<String>();
  @override
  Future<void> clearRaw(CacheContext ctx) async { await box.clear(); }
}

// First configure Hive's directory in your app: Hive.init(cacheDirectory).
// 先在应用内配置 Hive 目录：Hive.init(cacheDirectory)。
final small = Cacheman(options: const CachemanOptions(namespace: 'small'));
final large = HiveCache('large', options: const CachemanOptions(namespace: 'reports'));
await small.ensureInitialized();
await large.ensureInitialized();
small.write('report', 1000); // small summary / 小型摘要
await large.write('report', List.generate(1000, (i) => {'row': i}), ttl: 60000);
final report = await large.read<List<dynamic>>('report');
// The application owns box lifecycle: await large.box.close() when finished.
// 应用负责 box 生命周期：使用完毕后 await large.box.close()。
```

### 异步原语：纯 dart:io，每键一个文件

文件名对 **storageKey**（已加 namespace、按需经过 codec）做 UTF-8 + base64url 编码，
`report/2026` 这类逻辑键不会引入路径分隔符。

```dart
import 'dart:convert' show base64Url, utf8;
import 'dart:io';
import 'package:cacheman/cacheman.dart';

/// App-owned IO-only per-key file adapter. / 应用自有的每键文件适配器，仅限 IO 平台。
class DirectoryCache extends AsyncCacheman {
  /// Uses a dedicated directory. / 使用缓存专用目录。
  DirectoryCache(this.directory, {super.options});
  /// Backend directory. / 后端目录。
  final Directory directory;
  /// Recognized file suffix. / 可识别的文件后缀。
  static const suffix = '.cache';

  /// Maps storageKey to a safe filename. / 将 storageKey 映射为安全文件名。
  File fileFor(String k) => File(
    '${directory.path}${Platform.pathSeparator}${base64Url.encode(utf8.encode(k))}$suffix',
  );

  @override
  Future<void> initRaw(CacheContext ctx) async {
    await directory.create(recursive: true);
  }
  @override
  Future<Object?> getRaw(CacheContext ctx, String k) async {
    final file = fileFor(k);
    return await file.exists() ? await file.readAsString() : null;
  }
  @override
  Future<void> setRaw(CacheContext ctx, String k, String v) async {
    await fileFor(k).writeAsString(v, flush: true);
  }
  @override
  Future<void> removeRaw(CacheContext ctx, String k) async {
    final file = fileFor(k);
    if (await file.exists()) await file.delete();
  }
  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async {
    final keys = <String>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (!name.endsWith(suffix)) continue;
      try {
        keys.add(utf8.decode(base64Url.decode(name.substring(0, name.length - suffix.length))));
      } on FormatException { /* ignore foreign filenames / 忽略外部文件名 */ }
    }
    return keys;
  }
  // clearRaw defaults to keysRaw + removeRaw; no recursive directory deletion.
  // clearRaw 默认 keysRaw + removeRaw，不递归删除目录。
}

final large = DirectoryCache(Directory('cache-data'));
await large.ensureInitialized();
await large.write('report/2026', {'rows': 1000});
final report = await large.read<Map<String, dynamic>>('report/2026');
```

此最小 IO 示例使用专用目录，假定串行访问；仍受文件名长度限制。原子替换、锁、恢复由自定义后端
负责。仅适用于 IO 平台，不适用 web；值按需读取，不由 cacheman 保留。

### CacheContext 与异步 API 契约

`CacheContext` 携带 `key`（未加前缀/编码的逻辑键）、`namespace`（转义后的前缀，与 getter 一致）、
`op`（`CacheOp.init/read/write/remove/keys/clear`）。初始化、枚举、整库清空时 key 为 null；批量
CRUD 逐键调用原语并传对应逻辑键。内部懒删除/续期分别使用 remove/write 上下文。
可用于记录日志、按 key 前缀分 box；若跨多个 box 路由，`keysRaw` 须枚举其并集，`clearRaw` 须覆盖全部。

AsyncCacheman 的 `ensureInitialized`、`read<T>`/`readAll`、`write`/`writeAll`、`remove`/`removeAll`、
`erase`、`keys()`、`length()`、`purge()`、`setNamespace()` 全部须 await；
`namespace` 与 `storageKey()` 保持同步（不访问后端）。TTL/expireAt 和默认值与 Cacheman 一致。
本阶段不提供异步 `key(index)`、`fast`/`lazy`/`batchFast`、`debug()`。
异步枚举每次调用 `keysRaw` 并过滤归属，不缓存自有键集合。与 Cacheman 一样，过期项在读取/清理前
仍计入枚举与数量。

- 有 namespace **或 enckey** 时，`erase()` 只删除自有键；两者都没有时调用 `clearRaw`，清空整个
  后端（包括外部键）。这样也保留了 Cacheman 现有的仅 enckey 情况下的保护。
- `force` 捕获序列化以及 await `setRaw` 的失败，清过期后重试一次，最终失败走
  `onError(storageKey, error)` 或 print。续期等待持久化，但续期失败仍返回原读取值。
  这与同步类的后台 flush Future 处理方式不同。
- 解码失败先删除并上报，再返回默认值；purge/readonly 探测静默。其他后端 IO 异常向上传播；
  自定义 `onError` 回调若抛错也会向上传播。
- 切换 namespace 前先 await 进行中的操作。readonly 和 sliding 不提供事务保证；并发访问、
  后端生命周期和持久性由子类/应用负责。

## 示例

一份完整可运行的 app，把上面每个特性（持久层、ttl、滑动过期、命名空间、批量操作、
`fast`/`lazy`/`batchFast`、`debug()`、`codeable`/`enckey`、`Jsonx`、`raw`/`readonly`、同步/异步并行缓存）都走一遍，
见 [`example/`](./example/)：

```bash
flutter run example/lib/main.dart
```

## 跟 `@codejoo/storage`（TS 姊妹项目）的差异

- **同步 Cacheman**，另提供抽象 **AsyncCacheman** 供用户实现后端；不内置磁盘层、内存 `ss` 层或自动路由，多个实例可并行使用。
- **不内置 codec。** TS 版自带混淆 codec；这个包只暴露 `Codec` 接口。
- **Cacheman `force` 的重试只覆盖同步写入失败**（比如自定义 `serialize` 抛错）——`get_storage` 真正的落盘失败是异步的、从不重试；而 2.1.1 的 write Future 带不出这类错误，所以 `onError` 只保证同步失败会触发（见 `lib/src/cacheman.dart` 中 `Cacheman` 的 `_gs` 文档注释）。
- 没有 `crossTab` 的等价物（浏览器标签页概念，Flutter 没有对应场景）。

## License

MIT
