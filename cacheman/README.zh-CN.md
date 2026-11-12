# cacheman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/cacheman.svg)](https://pub.dev/packages/cacheman)

对 [`get_storage`](https://pub.dev/packages/get_storage) 的一层类型安全的小封装，在它上面加了 TTL 和绝对过期时间、滑动续期、命名空间、自定义序列化、可选的 codec 钩子，以及绑定单个 key 的快捷访问器。它是 TypeScript 项目 `@codejoo/storage` 的 Dart/Flutter 版。

只要 `await cache.ensureInitialized()` 一次，之后 `Cacheman` 的读写全是同步的（原因见 `Cacheman` 的类文档）。
存大值或用其他存储引擎时，可以再配一个自己写的 `AsyncCacheman` 子类一起用（见[分层存储](#分层存储--自定义底层)）。

## 安装

```yaml
dependencies:
  cacheman: ^0.7.1
```

也可以用本地路径：`cacheman: {path: ../cacheman}`。0.7.0 有不兼容改动，从 0.6 升级请先看
[从 0.6 迁移到 0.7.0](#从-06-迁移到-070)。

## 快速上手

```dart
import 'package:cacheman/cacheman.dart';

final cache = Cacheman();
await cache.ensureInitialized();

cache.write('token', 'abc');       // 持久化，重启后还在（get_storage）
cache.read<String>('token');       // 'abc'（同步返回）
cache.write('session', 1, ttl: 60000); // 60 秒后过期
cache.remove('token');

cache.setNamespace('alice');        // 同一个实例切到 alice 的 key
```

## API

### `Cacheman({container, path, options})`

创建一个基于 `get_storage` 的持久化 `Cacheman`。所有读写方法都直接在实例上（没有 `.ls`）。第一次读写前，要先调用并 `await` 一次 `ensureInitialized()`。

### `Cacheman.custom({options})` / `AsyncCacheman({options})`

`Cacheman.custom` 给自己提供底层存储方法（不用 `get_storage`）的同步子类用；`AsyncCacheman` 是异步后端的抽象类（所有读写都返回 `Future`）。详见[分层存储](#分层存储--自定义底层)。

### `cache.ensureInitialized()`

`Cacheman` 读写接口里唯一返回 `Future` 的方法，等 `get_storage` 把本实例的 container 从磁盘加载完。

写子类：`Cacheman` 的构造函数和 `ensureInitialized()` 都是普通成员，不是工厂方法，子类用 `super(...)` 把构造参数传上去就行，不用写工厂代码：

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
| `readWith<T>(key, {defaultValue, adapter})` | 通过 `ValueAdapter` 读取（按类型做 JSON 转换）。 |
| `write<T>(key, value, {ttl, expireAt, adapter})` | 写入。`ttl` 单位毫秒。 |
| `remove(key)` | 删除。 |
| `readAll(keys, [defaults])` / `writeAll(keys, values, {...})` / `removeAll(keys)` | 批量，按位置对应。 |
| `keys()` / `key(index)` / `length` | 列出 / 统计本实例的 key。 |
| `purge()` | 主动删除已过期条目（平时是懒过期）。 |
| `erase()` | 清空本实例的 key（限于 namespace/enckey 范围内），没有这两项时清空整个后端。 |
| `namespace` / `setNamespace([ns])` | 当前前缀 / 原地切换。 |
| `container` | 底层的 `GetStorage` 实例。需要直接操作原始 container 时用，比如用 `listenKey` 监听外部改动。 |
| `storageKey(key)` | `key` 实际存储用的 key（加了命名空间前缀，开了 `enckey` 还会编码）。传给 `container.listenKey(...)` 的要用它，不是 `key`。 |
| `watch<T>(key, onChange, {includeOwnWrites = false})` | 监听解码后的值，返回取消函数；切换命名空间后仍然有效。 |
| `flush()` | 马上排一次保存，返回 void；出错走 `onError`。 |

### `CachemanOptions`

`serialize`/`deserialize`、`codeable`/`codec`/`keyCodec`、`sliding`、`namespace`、`raw`、`force`、`readonly`、`enckey`、`onError`、`flushDelay`、`purgeOnInit`。每个字段的准确含义见 `lib/src/options.dart` 里的文档注释。

读到解码失败的条目时会把它删掉，并通过 `onError(storageKey, error)`（没设置就 print）报告。
报告的是 `CorruptEntryError(dropped: true)`，`cause` 里是原来的解码/反序列化异常；
codec 返回 null 时，`cause` 是 `FormatException`。
purge 和 readonly 的探测不报告这类失败；raw 读取不解码。

**本包没有自带 codec。** `Codec` 只是一个 `encode`/`decode` 字符串接口，混淆、加密、压缩都可以自己实现。

### `fast<V>(cache, key)` / `lazy<V>(cache, key)` / `batchFast<V>(cache, keys)`

绑定单个 key 的快捷访问器，见 `lib/src/fast.dart`。

### 共享 Hub、`watch`、`flushDelay`、`flush` 与 `purgeOnInit`

同一个 container 上的 `Cacheman` 实例共用一个私有的 Hub 和一个底层监听器。其他实例或外部改了 container，本实例的 key 索引会自动重建；本实例自己的写入以 O(1) 更新索引。不缓存读到的值。Hub、`watch` 和延迟保存只对同步的 `Cacheman` 有效。

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

`watch` 按本实例的解码和过期规则读值，值不存在、被删或被清空时得到 null。整个 container 被 erase 时也会通知，切换 `setNamespace` 后监听仍然有效。
设 `includeOwnWrites: true` 还能收到本实例自己的写入、续期和懒删除。类型、读取和回调里的异常走 `onError`，不影响其他监听；`onError` 自己抛异常则照常向外抛。对象销毁时记得取消订阅。

`flushDelay: null` 沿用 get_storage 的默认做法：每个有写入的事件循环轮次保存一次。设成 200ms 后，
写入和续期用 `writeInMemory` 先写内存，由一个共享计时器合并保存，以最早的截止时间为准，所以连续写入不会把保存越推越晚。
程序崩溃时，这个窗口内的写入可能丢失。删除仍调用 get_storage 的 `remove` 并立即排一次保存（它没有公开的“只删内存”方法）；
erase 行为不变。`flush()` 会取消计时器并马上排一次保存；有待保存的写入时，应用进入 inactive/paused/
hidden/detached 状态也会触发保存。这些都是尽力保存，不保证磁盘已经写完；get_storage 2.1.1 仍会丢掉
真正落盘的 Future。能观察到的底层异常，交给最近一次延迟写入的实例的 `onError`；手动 `flush` 的异常交给调用它的实例。

`purgeOnInit: true` 会在初始化后用 `Timer.run` 做一次清理，不阻塞；`await` 初始化不会等清理完成，raw 模式跳过。`AsyncCacheman` 忽略这两个选项。

自己提供底层存储方法的子类必须调用 `super.custom(...)`（见 `PreferencesCache`）。这类子类默认有独立的
Hub 身份 `this`、不订阅通知，所以不会悄悄打开 GetStorage；每次列 key 都重新扫描，调用 `watch` 会抛
`UnsupportedError`。只转发构造参数的普通子类（如上面的 `MyCacheman`）沿用默认构造，get_storage 的行为都保留：
共享 Hub、`watch`、`flushDelay` 和增量 key 索引。需要共享通知时，覆写 `hubIdentity`，返回一个
稳定的底层句柄，再实现 `listenRaw(ctx, onChange)`（返回取消函数，key 为 null 表示清空）和
`syncNotificationsRaw`；共用同一身份的实例，通知和持久化的约定必须一致。通知是异步的话，仍然每次重新扫描，
`includeOwnWrites: false` 也可能收到自己的事件，需要自己比较值。要真正的延迟持久化，覆写
`setDeferredRaw`/`flushRaw`，否则它们退回到 `setRaw` 和空操作。

### GetX 响应式接入（`watch`）

`get_storage` 依赖 `get`，所以 `get` 会作为间接依赖带进来。本包没有自带 GetX 绑定，可以在应用里
用 `watch` 自己写一个，类似 VueUse 的 `useStorage`：

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

比较时先用 `==`，不相等再比较 JSON 内容（针对集合和有 `toJson()` 的对象）；JSON 编码不了的值，要按业务需要改 `sameValue`。
请保留返回的 binding，对象销毁时同时取消 `watch` 和 Worker。

- 默认通知是同步的；`watch` 忽略本实例自己的写入（包括续期和懒删除），所以每次解码都会生成新对象的 Map/List 也不会形成写回死循环。
- 原始的 `container.listenKey` 仍然收不到整个 container 的 erase（变更的 key 是 `""`）；`watch` 会把它转给所有被监听的 key。
  限定了范围的 erase 还是逐个删 key 并发通知。
- 每个 isolate 各有自己的内存 map 和监听器；跨 isolate 同步要自己处理。

直接操作 container 且开了 enckey 时，用 `storageKey(key)`，不要自己拼 `namespace + key`。

### `debug(cache)`

本实例所有条目解密后的快照，格式 `{ "namespace:key": value }`，见 `lib/src/debug.dart`。

### `Jsonx`

和 `jsonEncode`/`jsonDecode` 兼容的序列化器，另外还能编码再还原 `DateTime`、`Duration`、`Set`、`BigInt`、`Uri` 和 `RegExp`。把 `Jsonx.encode`/`Jsonx.decode<T>`（外面包一层，凑成 `CacheEntity <-> String` 的签名）传给 `CachemanOptions.serialize`/`deserialize`。`decode<T>` 会把结果转成 `T`，比如 `Jsonx.decode<Map<String, dynamic>>(s)`。枚举编码会抛 `JsonUnsupportedObjectError`，请自己写 `toJson`，或用 `ValueAdapter` 转成 `name`。key 不是 String 的 Map 编码不了。DateTime 存成 `[microsecondsSinceEpoch, isUtc]`，跨时区也能还原同一个时间点；旧的 ISO 8601 字符串仍然能读。

## 错误处理

`CachemanOnError` 的签名仍是 `(String key, Object error)`，但传进来的 `error` 现在一律是
`CachemanError`。`key` 是实际存储用的 key（针对整个后端的操作用 `*`）；`cause` 是原始异常，
`stackTrace` 是能拿到的堆栈。

| 错误 | 含义 / 处理方式 |
| --- | --- |
| `SerializeError` | adapter.toJson、serialize 或值 codec 编码失败；请修复转换逻辑，不会清理也不会重试。 |
| `WriteError` | 底层写入重试后仍失败，或 force:false 时第一次就失败。 |
| `CorruptEntryError` | 解码失败；dropped:true 表示报告前已经删掉了这个条目。换 codec 之前先看 cause。 |
| `TypeMismatchError` | 请求的类型不符，或 adapter.fromJson 失败；返回默认值，数据保留。 |
| `FlushError` | 能观察到的后台保存失败；force 不会重试。 |
| `WatchError` | watch 回调，或它读后端/key 时失败；其他 watcher 照常通知。 |

```dart
final cache = Cacheman(options: CachemanOptions(onError: (key, error) {
  if (error is CorruptEntryError && error.cause is FormatException) {
    print('已删除不可读条目：$key');
  } else if (error is CachemanError) {
    print('$key: ${error.runtimeType}: ${error.cause}');
  }
}));
```

`read` 遇到类型或适配器错误不会抛异常；后端 IO 异常和 `onError` 自己抛的异常照常向外抛。
purge 和 readonly 的探测不报告错误。get_storage 2.1.1 丢掉了真正的 flush Future，磁盘写入失败不一定能报告出来。

web 上 localStorage 的容量和配额由浏览器和后端决定，cacheman 无法扩大；只能对观察得到的写入/保存失败分类。
跨 isolate 或进程的同步要应用自己处理。

## 类型安全与 ValueAdapter

JSON 解码出来的是 `List<dynamic>` 和 `Map<String, dynamic>`，所以直接读 `List<String>` 或
`Map<String, int>` 可能类型对不上。对不上时返回默认值、报告 TypeMismatchError，数据保留。
`read<dynamic>` 和 `read<Object?>` 什么值都接受。int 和 double 不会互转：JSON 里的 `1` 是 int，
`read<double>` 会返回默认值；数字转换请用 `num` 或 ValueAdapter。

`ValueAdapter<T>` 在序列化信封（envelope）之前和之后，把业务类型和 JSON 兼容的结构互相转换。`listOf<E>()` / `mapOf<V>()`
会立刻复制并检查每个元素；自定义类需要提供 toJson/fromJson。转换失败时，写入报 SerializeError，
读取报 TypeMismatchError（`cause` 里是原异常）。raw 模式会忽略 adapter 并打印 debug 警告，
只能存 String。适配器不改变已有的信封格式，也不增加读值缓存。

Dart 不能把可选位置参数和命名参数混在一起用，所以保留了 `read(key, [default])`，
要用适配器就调用 `readWith(key, {defaultValue, adapter})`，两者走的是同一套实现。
创建访问器时可以传 adapter 和默认 ttl；`set` 没指定 ttl 就用这个默认值。
`AsyncCacheman` 的 `readWith`/`write` 也支持适配器。

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
- 原来在 `read` 外面捕获 TypeError 的写法，改用 onError 加默认值；类型化的集合和自定义类用 ValueAdapter。
  类型不符时已有数据会保留。
- force 仍然支持，默认 true，但只重试底层写入，用的是事先构造好的同一个字符串。
  序列化、值 codec 和 adapter 的失败请修复转换逻辑，别指望重试。
- 删除 CacheOptions 的构造/导入；ttl/expireAt 直接传给 write/writeAll。
- 用 `key(index)` 循环是 O(n²)，改成调一次 `keys()` 再遍历；被弃用的方法仍可调用。
- 只转发构造参数的子类不用改；自己提供底层存储方法的同步子类请用 `super.custom(...)`；异步后端继承
  新增的 `AsyncCacheman`（见分层存储）。
- 没有 namespace/enckey 时，erase 仍然清空整个后端（包括外部的 key）；有的话只清自己的 key。
  `read` 的返回类型仍是可空类型。

## 分层存储 / 自定义底层

建议同时用多个实例：小而常用的数据放同步的 `Cacheman`（默认用 `get_storage`，整个 container 会全部加载进内存），
大的值放自己写的 `AsyncCacheman` 子类，按需从磁盘读。用哪个实例由调用处决定，不会自动分流或迁移数据。
两类都不缓存读到的值。cacheman 负责 namespace、TTL 和绝对过期、滑动续期、信封、序列化和 codec、
raw/readonly、force，以及哪些 key 归当前实例管；子类只需实现底层读写方法。`lib/` 里没有 Hive、文件、SharedPreferences
这些后端，也没有额外依赖。

### 同步原语：SharedPreferencesWithCache

覆写六个 protected 钩子：`initRaw`、`getRaw`、`keysRaw`、`setRaw`、`removeRaw`、`clearRaw`。
读取和列 key 必须同步完成；写入、删除、清空必须在**返回前更新完内存**，返回的 `Future<void>` 只用来报告后台持久化的错误。
这些 Future 的失败会被报告，但不触发 `force` 重试；只有底层写入同步抛异常时，才会清理过期条目并重试一次；
序列化、适配器、值 codec 编码失败会报告 SerializeError，不清理也不重试。
写入和删除的覆写方法不要加 `async`，直接转发给后端那个立即更新内存的方法。

下面是应用里的适配器示例（`shared_preferences` 加到应用里，不要加到本包）：

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
在返回持久化 Future 前更新缓存。请核对你用的后端和版本是否也这样。
`Cacheman.container` 仍然是拿到默认 GetStorage 的入口；即使是完全自定义的子类，访问它也会创建默认的 container。
覆写全部钩子就能彻底绕开默认后端。默认的 `GetStorage(container, path)` 现在是延迟创建的，初始化或第一次
访问 container 时，仍然会用构造参数里的 path。同名 container 仍遵循 GetStorage“第一次构造时的 path 生效”的规则，
只是“第一次”现在指第一次访问后端，不再是创建 `Cacheman` 实例的先后。
同步场景下，实例自己的 key 集合靠 Hub 版本号自动恢复；没有同步通知的子类每次查询都重新扫描（比如本例的 preferences）。

### 异步原语：Hive CE LazyBox

`AsyncCacheman({options})` 是抽象类，没有 container/path 参数。必须实现 `getRaw`、`setRaw`、
`removeRaw`、`keysRaw`；`initRaw` 可选，用来打开后端，默认什么都不做。`clearRaw` 也可选，默认会
列出 `keysRaw` 返回的所有 key，再逐个删除。所有钩子拿到的都是真实存储用的 key，写入的值是字符串。
[Hive CE LazyBox](https://pub.dev/documentation/hive_ce/latest/hive_ce/LazyBox-class.html) 每次按需读取值，
不像普通 Box 那样把所有值留在内存里（key 的元数据仍由后端维护）。请先在应用里配置好 Hive，再初始化适配器；用一个
专用的、key 全是字符串的 LazyBox。`hive_ce` 只加到使用本包的应用里。

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

文件名是 **storageKey**（已加 namespace，需要时还经过 codec）的 UTF-8 小写十六进制编码，
所以 `report/2026` 这样的 key 不会带进路径分隔符。

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

这个最小的 IO 示例用一个专用目录，假定访问是串行的；文件名长度限制依然存在。原子替换、加锁、恢复要自己的后端来做。
只适用于有 `dart:io` 的平台，web 不行；值按需读取，cacheman 不保留。

### CacheContext 与异步 API 契约

`CacheContext.storageKey` 是后端实际用的 key；`key` 第一次访问时才解析并缓存，保留的是调用时的 namespace。
订阅用 key 为 null 的 init 上下文，flush 用 key 为 null 的 write 上下文，现有的 CacheOp 枚举没有改。

`CacheContext` 带有 `key`（没加前缀、没编码的逻辑 key）、`namespace`（转义后的前缀，和 getter 一致）和
`op`（`CacheOp.init/read/write/remove/keys/clear`）。初始化、列 key、清空整个后端时 key 为 null；批量
读写会对每个 key 各调用一次，传对应的逻辑 key。内部的懒删除和续期分别用 remove 和 write 上下文。
可以用来记日志，或按 key 前缀分到不同的 box；如果要在多个 box 之间分流，`keysRaw` 必须列出它们的并集，`clearRaw` 必须全部清空。

`AsyncCacheman` 的 `ensureInitialized`、`read<T>`/`readAll`、`write`/`writeAll`、`remove`/`removeAll`、
`erase`、`keys()`、`length()`、`purge()`、`setNamespace()` 都要 `await`；
`namespace` 和 `storageKey()` 仍是同步的（不访问后端）。TTL/expireAt 和默认值的行为与 `Cacheman` 一致。
0.7.0 没有异步版的 `key(index)`、`fast`/`lazy`/`batchFast` 和 `debug()`。
每次列 key 都会调用 `keysRaw`，再筛出属于本实例的 key，不缓存 key 集合。和 `Cacheman` 一样，过期的 key 在被读取或清理之前，
仍会计入列表和数量。

- 有 namespace **或 enckey** 时，`erase()` 只删本实例的 key；两者都没有时调用 `clearRaw`，清空整个
  后端（包括外部的 key）。只设了 enckey 时的保护，和 `Cacheman` 现在的行为一致。
- `force` 只捕获 `await setRaw` 时的失败，清掉过期条目后重试一次，最终失败就走
  `onError(storageKey, error)`，没设置就 print。续期会等持久化完成，但续期失败时仍返回之前读到的值。
  这和同步类对后台 flush Future 的处理不同。
- 解码失败时先删除并报告，再返回默认值；purge 和 readonly 的探测不报告。其他后端 IO 异常向上抛；
  自定义的 `onError` 回调如果抛异常，也会向上抛。
- 切换 namespace 前，先 `await` 正在进行的操作。readonly 和 sliding 不是事务；并发访问、
  后端生命周期和数据能否持久保存，由子类或应用自己负责。

## 示例

[`example/`](./example/) 是一个能直接运行的 Flutter app，每页演示的内容：基础读写、ttl/过期、批量操作与
`fast`/`lazy`/`batchFast`、命名空间、`debug()` 与 `Jsonx`、分层存储（同步 `Cacheman` + `AsyncCacheman`
子类 + `Cacheman.custom` 子类）、共享 Hub（`watch`、`flushDelay`、`flush`、`purgeOnInit`），以及
`ValueAdapter` 与 `CachemanError` 的报告。`sliding`、`codeable`/`enckey`、`raw`/`readonly` 在
`CachemanOptions` 的文档里有说明，示例里没有演示。

```bash
cd example
flutter run -d chrome   # 或其他 Flutter 设备
```

## 跟 `@codejoo/storage`（TS 姊妹项目）的差异

- **同步的 Cacheman**，另有抽象的 **AsyncCacheman**，后端由你自己实现；没有内置的磁盘层、内存 `ss` 层，也没有自动分流，多个实例可以同时使用。
- **没有自带 codec。** TS 版带了混淆用的 codec；这个包只提供 `Codec` 接口。
- **Cacheman 的 `force` 只重试同步的写入失败**（`setRaw` 同步抛异常）。`get_storage` 真正的磁盘保存失败是异步的，从不重试；2.1.1 的 write Future 也带不出这类错误，所以 `onError` 只保证在同步失败时触发（见 `lib/src/cacheman.dart` 里 `Cacheman` 的 `_gs` 文档注释）。
- 没有对应 `crossTab` 的功能（它是浏览器标签页的概念，Flutter 里没有对应场景）。

## License

MIT
