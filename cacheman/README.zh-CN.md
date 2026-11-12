# cacheman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/cacheman.svg)](https://pub.dev/packages/cacheman)

一个轻量、类型安全的封装，包住 [`get_storage`](https://pub.dev/packages/get_storage)（持久层），对外一套统一 API：TTL 与绝对过期、滑动续期、命名空间、可插拔序列化、可选 codec 钩子、键绑定的快捷访问器。姊妹 TS 项目 `@codejoo/storage` 的 Dart/Flutter 版本。

`Cacheman` 只需 `await cache.ensureInitialized()` 一次之后全同步——原因见 `Cacheman` 的类文档。
大值或其他存储引擎，可与自己实现的 `AsyncCacheman` 子类并行使用（见[分层存储](#分层存储--自定义底层)）。

## 安装

```yaml
dependencies:
  cacheman: ^0.7.1
```

或使用本地副本：`cacheman: {path: ../cacheman}`。0.7.0 含破坏性变更，从 0.6 升级请先看
[从 0.6 迁移到 0.7.0](#从-06-迁移到-070)。

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

### `Cacheman.custom({options})` / `AsyncCacheman({options})`

`Cacheman.custom` 供自带存储原语（不用 `get_storage`）的同步子类使用；`AsyncCacheman` 是面向
异步后端的抽象类（全部 CRUD 返回 `Future`）。二者详见[分层存储](#分层存储--自定义底层)。

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
| `readWith<T>(key, {defaultValue, adapter})` | 带类型化 JSON 适配读取。 |
| `write<T>(key, value, {ttl, expireAt, adapter})` | 写入。`ttl` 单位毫秒。 |
| `remove(key)` | 删除。 |
| `readAll(keys, [defaults])` / `writeAll(keys, values, {...})` / `removeAll(keys)` | 批量，按位置对应。 |
| `keys()` / `key(index)` / `length` | 枚举/统计本实例管辖的键。 |
| `purge()` | 主动删除已过期条目（平时是懒过期）。 |
| `erase()` | 清空本实例管辖的键（namespace/enckey 范围内），或整个后端。 |
| `namespace` / `setNamespace([ns])` | 当前前缀 / 原地切换。 |
| `container` | 底层 `get_storage` 的 `GetStorage` 实例——给需要拿到原始 container 的互操作场景用（比如用 `listenKey` 监听外部变更）。 |
| `storageKey(key)` | `key` 实际落盘用的 key（加了命名空间前缀，`enckey` 时还会编码）——传给 `container.listenKey(...)` 的应该是这个，而不是 `key` 本身。 |
| `watch<T>(key, onChange, {includeOwnWrites = false})` | 监听解码值，返回取消函数；跟随命名空间迁移。 |
| `flush()` | 立即排共享保存，返回 void；错误走 onError。 |

### `CachemanOptions`

`serialize`/`deserialize`、`codeable`/`codec`/`keyCodec`、`sliding`、`namespace`、`raw`、`force`、`readonly`、`enckey`、`onError`、`flushDelay`、`purgeOnInit`——精确语义见 `lib/src/options.dart` 里每个字段的文档注释。

不可解码的条目在读取时被删除，并通过 `onError(storageKey, error)`（或 print）上报。
错误为 `CorruptEntryError(dropped: true)`，cause 保留原始解码/反序列化异常；
codec 返回 null 时 cause 使用 `FormatException`。
purge/readonly 探测不上报此类失败；raw 读取跳过解码。

**本包不内置任何 codec 实现。** `Codec` 只是一个 `encode`/`decode` 字符串接口——混淆、真加密、压缩，怎么实现随你。

### `fast<V>(cache, key)` / `lazy<V>(cache, key)` / `batchFast<V>(cache, keys)`

键绑定的快捷访问器——见 `lib/src/fast.dart`。

### 共享 Hub、`watch`、`flushDelay`、`flush` 与 `purgeOnInit`

同 container 的 Cacheman 共用一个私有 Hub/底层监听器。自有键索引在其他实例或外部写删后自动
重建；本实例写入以 O(1) 维护新鲜索引。不新增读值缓存。Hub/watch/延迟落盘仅用于同步 Cacheman。

```dart
final cache = Cacheman(options: const CachemanOptions(
  namespace: 'account',
  flushDelay: Duration(milliseconds: 200), // opt-in / 显式启用，default null
  purgeOnInit: true,                      // opt-in / 显式启用，default false
));
await cache.ensureInitialized();
final stop = cache.watch<Map<String, dynamic>>('profile', (value) {
  print(value); // peer/external changes / 其他实例或外部变更
});
cache.write('profile', {'name': 'Ada'}); // readable now / 立即可读，自身事件被忽略
cache.flush(); // queue save now / 立即排保存，没有 Future/持久化完成确认
stop();
```

`watch` 经过本实例的解码/过期语义读取，缺失、删除或清空得到 null；支持整容器 erase，且会随
`setNamespace` 迁移。`includeOwnWrites: true` 也接收本实例写入、续期及懒删。类型/读取/回调异常
走 `onError`，不会打断其他监听；onError 自身抛错仍按原契约传播。对象释放时取消订阅。

`flushDelay: null` 保持 get_storage 默认的每个有写入的事件循环轮次落盘。显式设为 200ms 后，
写入和续期使用 `writeInMemory` 与共享计时器合并，取最早截止时间，连续写入不会不断推迟保存。
崩溃可能丢失窗口内的写入。删除仍走 get_storage `remove` 并立即排落盘（没有公开的仅内存删除）；
erase 保持原行为。`flush()` 取消计时器并立即排保存；有待保存写入时，inactive/paused/hidden/
detached 生命周期也触发保存。这是尽力排落盘，不能同步保证磁盘写完；get_storage 2.1.1 仍丢弃
实际落盘 Future。可捕获的原语异常上报给最近延迟写入者；主动 flush 的异常上报给调用实例。

`purgeOnInit: true` 在初始化后用 `Timer.run` 调度一次非阻塞清理；await 初始化不等待清理完成，
raw 模式跳过。AsyncCacheman 忽略这两个新选项。

自带存储原语的子类必须调用 `super.custom(...)`（见 `PreferencesCache`）。这类子类默认使用独立
Hub 身份 `this`、不订阅通知，因而不会隐式打开 GetStorage；每次枚举重扫，`watch` 抛
UnsupportedError。只转发构造参数的普通子类（如上面的 `MyCacheman`）沿用默认构造，完整保留
get_storage 行为：共享 Hub、`watch`、`flushDelay` 与增量键索引。需要共享通知时，覆写 `hubIdentity` 返回
稳定底层句柄，实现 `listenRaw(ctx, onChange)`（返回取消函数，null 键代表清空）和
`syncNotificationsRaw`；共享身份的实例必须采用一致的通知/持久化契约。异步通知仍每次重扫，
`includeOwnWrites: false` 可能收到自己的事件，须自行判等。真正延迟持久化需覆写
`setDeferredRaw`/`flushRaw`，否则默认退化为 `setRaw`/无操作。

### GetX 响应式接入（`watch`）

`get_storage` 依赖 `get`，因此 `get` 是本包的传递依赖。本包不内置 GetX 绑定，可在应用中
用 `watch` 搭建类似 VueUse useStorage 的封装：

```dart
import 'dart:convert';
import 'package:cacheman/cacheman.dart';
import 'package:get/get.dart';

/// Compare JSON-compatible values. / 比较可 JSON 序列化的值。
bool sameValue(Object? a, Object? b) => a == b || jsonEncode(a) == jsonEncode(b);

/// Own writes cannot feed back; dispose both subscriptions. / 忽略自身写入，释放两种订阅。
({Rx<V?> rx, void Function() dispose}) reactive<V>(Cacheman cache, String key) {
  final rx = Rx<V?>(cache.read<V>(key));
  final stop = cache.watch<V>(key, (next) {
    if (!sameValue(rx.value, next)) rx.value = next;
  }, includeOwnWrites: false);
  final worker = ever(rx, (V? value) {
    if (sameValue(cache.read<V>(key), value)) return;
    value == null ? cache.remove(key) : cache.write<V>(key, value);
  });
  return (rx: rx, dispose: () { stop(); worker.dispose(); });
}

final binding = reactive<String>(cache, 'token');
final token = binding.rx;
Obx(() => Text(token.value ?? 'no token'));
token.value = 'abc123';
// On owner disposal / 对象释放时：binding.dispose();
```

比较先用 `==`，再对集合和有 `toJson()` 的对象比较 JSON 内容；JSON 无法编码的值需按业务语义
调整 `sameValue`。保留返回的 binding，对象释放时同时取消 watch 和 Worker。

- 默认通知同步；`watch` 忽略本实例写入（含续期/懒删），对每次解码生成新身份的 Map/List 也能断环。
- 原始 `container.listenKey` 仍收不到整容器 erase（变更键 `""`）；`watch` 转给所有监听键。
  有作用域的 erase 仍逐键删除并通知。
- 不同 isolate 各有独立内存 map 和监听器；跨 isolate 同步须自行安排。

直接使用 container 互操作且启用 enckey 时，应使用 `storageKey(key)`，而非 `namespace + key`。

### `debug(cache)`

本实例全部管辖条目的解密快照，`{ "namespace:key": value }`——见 `lib/src/debug.dart`。

### `Jsonx`

兼容 `jsonEncode`/`jsonDecode` 的序列化器，额外支持 `DateTime` / `Duration` / `Set` / `BigInt` / `Uri` / `RegExp` 的可逆往返。把 `Jsonx.encode`/`Jsonx.decode<T>`（包一层去对上 `CacheEntity <-> String` 的签名）传给 `CachemanOptions.serialize`/`deserialize`——`decode<T>` 会把结果转型成 `T`（比如 `Jsonx.decode<Map<String, dynamic>>(s)`）。Enum 编码会抛 `JsonUnsupportedObjectError`，请自定义 `toJson` 或用 `ValueAdapter` 转成 `name`。key 不是 String 的 Map 无法编码。DateTime 存为 `[microsecondsSinceEpoch, isUtc]`，跨时区保留时间点；兼容旧 ISO 8601 字符串。

## 错误处理

`CachemanOnError` 保持 `(String key, Object error)` 签名，但上报对象现在全部是
`CachemanError`。key 为实际存储键（整库操作使用 `*`）；cause 保留原始异常，
stackTrace 保留可获得的堆栈。

| 错误 | 含义 / 处理方式 |
| --- | --- |
| `SerializeError` | adapter.toJson、serialize 或值 codec 编码失败；修复转换，不清理、不重试。 |
| `WriteError` | 底层写重试后仍失败，或 force:false 下首次失败。 |
| `CorruptEntryError` | 解码失败；dropped:true 表示上报前已删除。更换 codec 前检查 cause。 |
| `TypeMismatchError` | 请求类型不符或 adapter.fromJson 失败；返回默认值、保留数据。 |
| `FlushError` | 可观察的后台落盘失败；force 从不重试。 |
| `WatchError` | watch 回调或其后端/键读取失败；其他 watcher 继续分发。 |

```dart
final cache = Cacheman(options: CachemanOptions(onError: (key, error) {
  if (error is CorruptEntryError && error.cause is FormatException) {
    print('已删除不可读条目：$key');
  } else if (error is CachemanError) {
    print('$key: ${error.runtimeType}: ${error.cause}');
  }
}));
```

read 的类型/适配器错误永不抛；后端 IO 异常和 onError 自身抛出的异常仍传播。
purge/readonly 探测保持静默。get_storage 2.1.1 丢失实际 flush Future，真实磁盘失败无法保证上报。

web localStorage 容量/配额由浏览器及后端决定，cacheman 不扩容；只对可观察到的写入/落盘失败
进行分类。跨 isolate/进程同步仍由应用负责。

## 类型安全与 ValueAdapter

JSON 解码产生 `List<dynamic>` 和 `Map<String, dynamic>`；直接请求 `List<String>` 或
`Map<String, int>` 可能不匹配。类型不符返回默认值、上报 TypeMismatchError、保留数据。
`read<dynamic>` 和 `read<Object?>` 接受所有值。不做 int/double 互转：JSON 的 `1` 是 int，
`read<double>` 会返回默认值；请用 num 或 ValueAdapter 做数字转换。

`ValueAdapter<T>` 在信封序列化前后转换业务类型与 JSON 兼容结构。listOf<E>() / mapOf<V>()
立即复制并检查每个元素；自定义类提供 toJson/fromJson。转换失败在写入时为 SerializeError，
读取时为 TypeMismatchError（cause 保留原异常）。raw 模式忽略 adapter 并输出 debug 警告，
只存 String。适配器不改变已有信封格式，也不增加读值缓存。

Dart 无法混合可选位置默认值与命名参数，因此保留 `read(key, [default])`，
适配器使用 `readWith(key, {defaultValue, adapter})`，二者复用同一内核。
访问器创建时可传 adapter 和默认 ttl；set 未指定 ttl 时使用默认值。
AsyncCacheman 同样支持 readWith/write 适配器。

```dart
final names = ValueAdapter.listOf<String>();
cache.write('names', ['Ada'], adapter: names);
final list = cache.readWith<List<String>>('names', adapter: names);
final counts = cache.readWith<Map<String, int>>('counts',
  defaultValue: const {}, adapter: ValueAdapter.mapOf<int>());
final bound = fast<List<String>>(cache, 'names', adapter: names, ttl: 60000);
bound.set(['Ada']); // ttl=60000 unless set(..., ttl: ...) overrides it
final deferred = lazy<List<String>>(cache, 'names', adapter: names, ttl: 60000);
final group = batchFast<List<String>>(cache, ['names'], adapter: names, ttl: 60000);

/// Business value. / 业务值。
class Profile {
  const Profile(this.name);
  /// Display name. / 显示名称。
  final String name;
}
final profiles = ValueAdapter<Profile>(
  toJson: (p) => {'name': p.name},
  fromJson: (json) => Profile((json as Map<String, dynamic>)['name'] as String),
);
cache.write('profile', const Profile('Ada'), adapter: profiles);
final profile = cache.readWith<Profile>('profile', adapter: profiles);
// AsyncCacheman: await write / readWith with the same adapters.
// AsyncCacheman：同样的适配器，write / readWith 须 await。
```

## 从 0.6 迁移到 0.7.0

- 原 `error is FormatException` 改为
  `error is CorruptEntryError && error.cause is FormatException`；其他异常也检查 cause。
- 将 read 外的 TypeError 捕获改为 onError 与默认值；类型化集合、自定义类使用 ValueAdapter。
  类型不符时已有数据会保留。
- force 继续支持且默认 true，但只重试底层写，复用一次构造的字符串。
  序列化/值 codec/adapter 失败请修复转换，不再依赖重试。
- 删除 CacheOptions 的构造/导入；ttl/expireAt 直接传给 write/writeAll。
- key(index) 循环为 O(n²)，改为一次 keys() 后遍历；弃用方法仍可调用。
- 只转发构造参数的子类无需改动；自带存储原语的同步子类请用 `super.custom(...)`；异步后端继承
  新增的 `AsyncCacheman`（见分层存储）。
- 无 namespace/enckey 时 erase 仍清整个后端（含外部键）；有作用域则保护归属。
  read 返回类型仍为可空类型。

## 分层存储 / 自定义底层

推荐多个实例并行：小型高频数据用同步 `Cacheman`（默认 `get_storage`，整个 container 全量
加载进内存），大值用自定义 `AsyncCacheman` 子类按需读盘。由调用处选择实例，不自动路由或迁移。
两类都不额外缓存读取的值。cacheman 负责 namespace、TTL/绝对过期、滑动续期、信封、序列化/codec、
raw/readonly、force 和归属语义；子类只提供底层原语。`lib/` 不内置 Hive、文件、SharedPreferences
等新后端，也不增加依赖。

### 同步原语：SharedPreferencesWithCache

覆写六个 protected 钩子：`initRaw`、`getRaw`、`keysRaw`、`setRaw`、`removeRaw`、`clearRaw`。
读取/枚举同步完成；写删清空必须在**返回前完成内存态更新**，`Future<void>` 仅承载后台持久化错误。
Future 失败会上报，但不参与 `force` 重试；仅底层写入同步抛错时可清过期后重试一次；
序列化/适配器/值 codec 编码失败上报 SerializeError、不清理、不重试。
写删覆写方法保持非 `async`，直接转发到底层的即时内存更新操作。

下面是应用内适配器示意（只在应用中添加 `shared_preferences`，不添加到本包）：

```dart
import 'package:cacheman/cacheman.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-owned synchronous preferences adapter. / 应用自有的同步偏好适配器。
class PreferencesCache extends Cacheman {
  /// Builds without opening a backend. / 构造时不打开后端。
  PreferencesCache({super.options}) : super.custom();
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
同步自有键集合通过 Hub 版本自愈；无同步通知的子类每次查询重扫（如本例 preferences）。

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

文件名对 **storageKey**（已加 namespace、按需经过 codec）做 UTF-8 + 小写十六进制编码，
`report/2026` 这类逻辑键不会引入路径分隔符。

```dart
import 'dart:convert' show utf8;
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
  /// Hexadecimal radix. / 十六进制基数。
  static const _hexRadix = 16;
  /// Hex digits per UTF-8 byte. / 每个 UTF-8 字节的十六进制位数。
  static const _byteDigits = 2;

  /// Lowercase hex avoids base64 case collisions on case-insensitive filesystems.
  /// 小写十六进制避免 base64 在大小写不敏感文件系统上的文件名碰撞。
  static String _encodeKey(String key) => utf8.encode(key)
      .map((byte) => byte.toRadixString(_hexRadix).padLeft(_byteDigits, '0')).join();

  /// Decode only complete lowercase hex byte pairs. / 仅解码完整的小写十六进制字节对。
  static String _decodeKey(String name) {
    if (!RegExp(r'^(?:[0-9a-f]{2})*$').hasMatch(name)) {
      throw const FormatException('Invalid hex filename');
    }
    return utf8.decode([
      for (var i = 0; i < name.length; i += _byteDigits)
        int.parse(name.substring(i, i + _byteDigits), radix: _hexRadix),
    ]);
  }

  /// Maps storageKey to a safe filename. / 将 storageKey 映射为安全文件名。
  File fileFor(String k) => File(
    '${directory.path}${Platform.pathSeparator}${_encodeKey(k)}$suffix',
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
        keys.add(_decodeKey(name.substring(0, name.length - suffix.length)));
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

`CacheContext.storageKey` 为实际底层键；key 首次访问才解析并缓存，保留调用时的 namespace。
订阅使用无键 init 上下文，flush 使用无键 write 上下文，保持现有 CacheOp 枚举不变。

`CacheContext` 携带 `key`（未加前缀/编码的逻辑键）、`namespace`（转义后的前缀，与 getter 一致）、
`op`（`CacheOp.init/read/write/remove/keys/clear`）。初始化、枚举、整库清空时 key 为 null；批量
CRUD 逐键调用原语并传对应逻辑键。内部懒删除/续期分别使用 remove/write 上下文。
可用于记录日志、按 key 前缀分 box；若跨多个 box 路由，`keysRaw` 须枚举其并集，`clearRaw` 须覆盖全部。

AsyncCacheman 的 `ensureInitialized`、`read<T>`/`readAll`、`write`/`writeAll`、`remove`/`removeAll`、
`erase`、`keys()`、`length()`、`purge()`、`setNamespace()` 全部须 await；
`namespace` 与 `storageKey()` 保持同步（不访问后端）。TTL/expireAt 和默认值与 Cacheman 一致。
0.7.0 不提供异步 `key(index)`、`fast`/`lazy`/`batchFast`、`debug()`。
异步枚举每次调用 `keysRaw` 并过滤归属，不缓存自有键集合。与 Cacheman 一样，过期项在读取/清理前
仍计入枚举与数量。

- 有 namespace **或 enckey** 时，`erase()` 只删除自有键；两者都没有时调用 `clearRaw`，清空整个
  后端（包括外部键）。这样也保留了 Cacheman 现有的仅 enckey 情况下的保护。
- `force` 仅捕获 await `setRaw` 的失败，清过期后重试一次，最终失败走
  `onError(storageKey, error)` 或 print。续期等待持久化，但续期失败仍返回原读取值。
  这与同步类的后台 flush Future 处理方式不同。
- 解码失败先删除并上报，再返回默认值；purge/readonly 探测静默。其他后端 IO 异常向上传播；
  自定义 `onError` 回调若抛错也会向上传播。
- 切换 namespace 前先 await 进行中的操作。readonly 和 sliding 不提供事务保证；并发访问、
  后端生命周期和持久性由子类/应用负责。

## 示例

[`example/`](./example/) 是一个可运行的 Flutter app，各页覆盖：基础读写、ttl/过期、批量操作与
`fast`/`lazy`/`batchFast`、命名空间、`debug()` 与 `Jsonx`、分层存储（同步 `Cacheman` + `AsyncCacheman`
子类 + `Cacheman.custom` 子类）、共享 Hub（`watch`、`flushDelay`、`flush`、`purgeOnInit`），以及
`ValueAdapter` 与 `CachemanError` 上报。`sliding`、`codeable`/`enckey`、`raw`/`readonly` 在
`CachemanOptions` 中有文档，但示例未演示。

```bash
cd example
flutter run -d chrome   # 或其他 Flutter 设备
```

## 跟 `@codejoo/storage`（TS 姊妹项目）的差异

- **同步 Cacheman**，另提供抽象 **AsyncCacheman** 供用户实现后端；不内置磁盘层、内存 `ss` 层或自动路由，多个实例可并行使用。
- **不内置 codec。** TS 版自带混淆 codec；这个包只暴露 `Codec` 接口。
- **Cacheman `force` 的重试只覆盖同步写入失败**（`setRaw` 同步抛错）——`get_storage` 真正的落盘失败是异步的、从不重试；而 2.1.1 的 write Future 带不出这类错误，所以 `onError` 只保证同步失败会触发（见 `lib/src/cacheman.dart` 中 `Cacheman` 的 `_gs` 文档注释）。
- 没有 `crossTab` 的等价物（浏览器标签页概念，Flutter 没有对应场景）。

## License

MIT
