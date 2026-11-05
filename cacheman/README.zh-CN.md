# cacheman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/cacheman.svg)](https://pub.dev/packages/cacheman)

一个轻量、类型安全的封装，包住 [`get_storage`](https://pub.dev/packages/get_storage)（持久层），对外一套统一 API：TTL 与绝对过期、滑动续期、命名空间、可插拔序列化、可选 codec 钩子、键绑定的快捷访问器。姊妹 TS 项目 `@codejoo/storage` 的 Dart/Flutter 版本。

只需 `await cache.ensureInitialized()` 一次之后全同步——原因见 `Cacheman` 的类文档。

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

整个 API 唯一的 `Future` 边界，等待本实例对应 container 的磁盘态加载完。

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

## 示例

一份完整可运行的 app，把上面每个特性（持久层、ttl、滑动过期、命名空间、批量操作、
`fast`/`lazy`/`batchFast`、`debug()`、`codeable`/`enckey`、`Jsonx`、`raw`/`readonly`）都走一遍，
见 [`example/`](./example/)：

```bash
flutter run example/lib/main.dart
```

## 跟 `@codejoo/storage`（TS 姊妹项目）的差异

- **`await cache.ensureInitialized()` 之后全同步**——`get_storage` 初始化完就是同步的，所以不像 TS 版那样需要 `ls`/`ss`（同步）之外再搞一个 `db`（异步 IndexedDB）层。
- **一层，不是三层**：只有持久层——没有内存 `ss` 层，也不需要 IndexedDB 的等价物。
- **不内置 codec。** TS 版自带混淆 codec；这个包只暴露 `Codec` 接口。
- **`force` 的重试只覆盖同步写入失败**（比如自定义 `serialize` 抛错）——`get_storage` 真正的落盘失败是异步的、从不重试；而 2.1.1 的 write Future 带不出这类错误，所以 `onError` 只保证同步失败会触发（见 `lib/src/cacheman.dart` 中 `Cacheman` 的 `_gs` 文档注释）。
- 没有 `crossTab` 的等价物（浏览器标签页概念，Flutter 没有对应场景）。

## License

MIT
