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
| `read<T>(key, [default])` | 读取；缺失/过期 → `default`（或 `null`）。 |
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

`serialize`/`deserialize`、`codeable`/`codec`、`sliding`、`namespace`、`raw`、`force`、`readonly`、`enckey`、`onError`——精确语义见 `lib/src/engine.dart` 里每个字段的文档注释。

**本包不内置任何 codec 实现。** `Codec` 只是一个 `encode`/`decode` 字符串接口——混淆、真加密、压缩，怎么实现随你。

### `fast<V>(cache, key)` / `lazy<V>(cache, key)` / `batchFast<V>(cache, keys)`

键绑定的快捷访问器——见 `lib/src/fast.dart`。

### GetX 响应式接入（`container` + `storageKey`）

本包**不依赖** `get`——`container`/`storageKey` 只是留出的互操作接口，不是内置的 GetX 集成。如果你自己用 GetX，靠这两个就能自己搭一个类似 VueUse `useStorage` 的响应式封装：

```dart
Rx<V?> reactive<V>(Cacheman cache, String key) {
  final rx = Rx<V?>(cache.read<V>(key));

  // 外部写入（其他实例/隔离区）会同步更新 Rx。
  cache.container.listenKey(cache.storageKey(key), (dynamic _) => rx.value = cache.read<V>(key));

  // 本地改 Rx 会写回 cacheman（ttl/serialize 等语义仍然生效）。
  ever(rx, (V? v) => v == null ? cache.remove(key) : cache.write<V>(key, v));

  return rx;
}

final token = reactive<String>(cache, 'token');
Obx(() => Text(token.value ?? 'no token'));
token.value = 'abc123'; // 界面自动刷新，并持久化
```

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

- **`create()` 之后全同步**——`get_storage` 初始化完就是同步的，所以不像 TS 版那样需要 `ls`/`ss`（同步）之外再搞一个 `db`（异步 IndexedDB）层。
- **一层，不是三层**：只有持久层——没有内存 `ss` 层，也不需要 IndexedDB 的等价物。
- **不内置 codec。** TS 版自带混淆 codec；这个包只暴露 `Codec` 接口。
- **`force` 的重试只覆盖同步写入失败**（比如自定义 `serialize` 抛错）——`get_storage` 真正的落盘失败是异步的，走单独的 `onError` 上报，不会重试（见 `lib/src/cacheman.dart` 中 `Cacheman` 的 `_gs` 文档注释）。
- 没有 `crossTab` 的等价物（浏览器标签页概念，Flutter 没有对应场景）。

## License

MIT
