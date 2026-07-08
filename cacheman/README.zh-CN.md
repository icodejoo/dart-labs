# cacheman

> English: [README.md](./README.md)

[![pub](https://img.shields.io/pub/v/cacheman.svg)](https://pub.dev/packages/cacheman)

一个轻量、类型安全的封装，包住 [`get_storage`](https://pub.dev/packages/get_storage)（持久层）和一个纯内存存储，对外一套统一 API：TTL 与绝对过期、滑动续期、命名空间、可插拔序列化、可选 codec 钩子、键绑定的快捷访问器。姊妹 TS 项目 `@codejoo/storage` 的 Dart/Flutter 版本。

只有一次异步的 `create()` 之后全同步——原因见 `Cacheman` 的类文档。

## 安装

```yaml
dependencies:
  cacheman:
    path: ../cacheman # 或发布后改用 git/pub 依赖
```

## 快速上手

```dart
import 'package:cacheman/cacheman.dart';

final cache = await Cacheman.create();

cache.ls.set('token', 'abc');       // 持久化，跨进程重启（get_storage）
cache.ls.get<String>('token');      // 'abc' —— 同步
cache.ls.set('session', 1, ttl: 60000); // 60 秒后过期
cache.ls.remove('token');

cache.ss.set('draft', {'id': 1});   // 纯内存 —— 进程重启即丢

cache.setNamespace('alice');        // 原地按账号隔离
await cache.destroy();              // 释放资源，保留已落盘数据
```

## API

### `Cacheman.create({container, path, options, cap})`

整个 API 唯一的 `Future` 边界。返回一个 `Cacheman`，带 `.ls`（持久层，`get_storage` 支撑）和 `.ss`（纯内存）——两个 `Engine` 共用同一套 options 和方法。`cap` 只限制 `.ss`（`ls` 落盘，没有这个上限）：按全部条目 `key.length + value.length` 之和算的软上限；`null`（默认）不限制。超限后按插入顺序淘汰最旧的（FIFO）——精确语义见 `Memory.cap` 的文档注释。

### `Engine` 方法（`ls` / `ss`）

| 方法 | 说明 |
| --- | --- |
| `get<T>(key, [default])` | 读取；缺失/过期 → `default`（或 `null`）。 |
| `set<T>(key, value, {ttl, expireAt, memoized})` | 写入。`ttl` 单位毫秒。 |
| `remove(key)` | 删除。 |
| `getAll(keys, [defaults])` / `setAll(keys, values, {...})` / `removeAll(keys)` | 批量，按位置对应。 |
| `keys()` / `key(index)` / `length` | 枚举/统计本实例管辖的键。 |
| `purge()` | 主动删除已过期条目（平时是懒过期）。 |
| `clear()` | 清空本实例管辖的键（namespace/enckey 范围内），或整个后端。 |
| `namespace` / `setNamespace([ns])` | 当前前缀 / 原地切换。 |
| `destroy()` | 清空 memo 缓存。不删除已落盘数据。 |

### `CachemanOptions`

`memoized`、`cloned`（+`deepCloned`）、`serialize`/`deserialize`、`codeable`/`codec`、`sliding`、`namespace`、`raw`、`force`、`readonly`、`enckey`、`onError`——精确语义见 `lib/src/engine.dart` 里每个字段的文档注释。

**本包不内置任何 codec 实现。** `Codec` 只是一个 `encode`/`decode` 字符串接口——混淆、真加密、压缩，怎么实现随你。

### `fast<V>(engine, key)` / `lazy<V>(engine, key)` / `batchFast<V>(engine, keys)`

键绑定的快捷访问器——见 `lib/src/fast.dart`。

### `debug(engine)`

某个引擎全部管辖条目的解密快照，`{ "namespace:key": value }`——见 `lib/src/debug.dart`。

### `Jsonx`

兼容 `jsonEncode`/`jsonDecode` 的序列化器，额外支持 `DateTime` / `Duration` / `Set` / `BigInt` / `Uri` / `RegExp` 的可逆往返。把 `Jsonx.encode`/`Jsonx.decode<T>`（包一层去对上 `CacheEntity <-> String` 的签名）传给 `CachemanOptions.serialize`/`deserialize`——`decode<T>` 会把结果转型成 `T`（比如 `Jsonx.decode<Map<String, dynamic>>(s)`）。设计上不可逆的：自定义 `Enum` 和 key 不是 `String` 的 `Map`——见 `lib/src/jsonx.dart` 的文档注释。

## 示例

一份完整可运行的 app，把上面每个特性（`ls`/`ss`、ttl、滑动过期、命名空间、批量操作、
`fast`/`lazy`/`batchFast`、`debug()`、`codeable`/`enckey`、`Jsonx`、`raw`/`readonly`）都走一遍，
见 [`example/cacheman_example.dart`](./example/cacheman_example.dart)：

```bash
flutter run example/cacheman_example.dart
```

## 跟 `@codejoo/storage`（TS 姊妹项目）的差异

- **`create()` 之后全同步**——`get_storage` 初始化完就是同步的，所以不像 TS 版那样需要 `ls`/`ss`（同步）之外再搞一个 `db`（异步 IndexedDB）层。
- **两层，不是三层**：`ls`（持久）/ `ss`（内存）——不需要 IndexedDB 的等价物。
- **不内置 codec。** TS 版自带混淆 codec；这个包只暴露 `Codec` 接口。
- **`force` 的重试只覆盖同步写入失败**（比如自定义 `serialize` 抛错）——`get_storage` 真正的落盘失败是异步的，走单独的 `onError` 上报，不会重试（见 `GetStorageAdapter` 的文档注释）。
- **`cloned` 默认浅拷贝**（`Map.of`/`List.of`）；打算修改顶层以外的内容，再加上 `deepCloned: true`。
- 没有 `crossTab` 的等价物（浏览器标签页概念，Flutter 没有对应场景）。

## License

MIT
