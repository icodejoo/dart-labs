# Cacheman 架构文档

cacheman 是 Flutter 包，直接封装 `get_storage` 的单个持久化 container。
`Cacheman` 本身不带类型参数，类型由 `read<T>` / `write<T>` 等方法指定。
入口 `lib/cacheman.dart` 导出公共 API，完整用法见两个 README。

## 模块

| 文件 | 职责 |
| --- | --- |
| `lib/src/cacheman.dart` | 同步构造与初始化、键处理、读写、过期/续期、命名空间、批量操作和错误上报。直接持有 `GetStorage`。 |
| `lib/src/options.dart` | 实例配置 `CachemanOptions`；已弃用且无方法接受的 `CacheOptions`。 |
| `lib/src/entity.dart` | `CacheEntity` 信封（`value` / `createdAt` / `expireAt` / `ttl`），默认 JSON 序列化与反序列化。 |
| `lib/src/interface.dart` | 可插拔字符串 `Codec` 接口与 `CachemanOnError` 回调类型；不内置 codec 实现。 |
| `lib/src/fast.dart` | `FastAccessor<V>` 和 `fast` / `lazy` / `batchFast`，转发到同一个 `Cacheman`。 |
| `lib/src/debug.dart` | 通过普通读取组装解密快照；保留懒过期/滑动续期的副作用，不回写快照。 |
| `lib/src/jsonx.dart` | 可选扩展 JSON 工具，支持日期、时长、集合等类型并转义与标签形状相同的普通 Map。 |

## 初始化与同步 API

```dart
final cache = Cacheman(options: const CachemanOptions(namespace: 'app'));
await cache.ensureInitialized();
cache.write('token', 'abc', ttl: 60000); // ttl 单位：毫秒
final token = cache.read<String>('token');
```

构造函数同步创建 `GetStorage(container, path)`，便于子类通过 `super(...)` 转发参数。
`ensureInitialized()` 初始化 Flutter binding 并等待该实例的 `initStorage`，是
`Cacheman` 唯一的 Future 边界；任何读写前都须 await 它。

初始化后，`get_storage` 的读写直接操作其内存 map，落盘在后台合并调度。因此
`Cacheman` 的其余方法保持同步；`write` 返回不代表数据已经持久落盘。这里没有第二个
异步后端，也没有额外的进程内值缓存。`get_storage` 自身依赖 `get`，本包未内置 GetX 绑定。

## 写入与读取数据流

写入 `write(key, value, {ttl, expireAt})`：

1. 转义命名空间中的 `%` / `:`，拼接前缀；启用 `enckey` 时通过确定性的
   `keyCodec ?? codec` 编码实际存储键。
2. `readonly` 检查未过期条目的真实存在性（存储的 null 也算存在），不触发续期。
3. 普通模式生成 `CacheEntity`，调用 `serialize`，启用 `codeable` 时再用值 codec 编码。
   `raw` 模式仅接受字符串，跳过信封、值 codec 与过期逻辑。
4. `_persist` 同步写入 `GetStorage` 并维护自有键集合。同步序列化/编码/写入失败时，
   `force` 可清理过期条目后重试一次；最终失败通过 `onError` 或 print 上报。

读取 `read<T>(key, [defaultValue])`：

1. 生成实际存储键，每次直接从 `GetStorage` 取原始字符串；缺失或外部非字符串数据返回默认值。
2. `raw` 直接返回字符串；普通模式先按需解码，再 `deserialize` 成信封。
3. 解码/反序列化失败时删除条目、上报原始异常（codec 返回 null 则使用格式异常），返回默认值。
   `purge` 遍历不上报这类失败，避免反复扫描刷屏。
4. 有 `createdAt` 标记且已过期的条目被删除；否则按需续期并返回 `value`。
   `readAll`、快捷访问器和 `debug` 复用该路径。

## 关键不变量与边界

- 不调用 `GetStorage.init`：它按 container 名缓存实例，可能先把 `path` 固定为 null。
  直接构造也仍受同名 container 首次 `path` 生效的限制。
- 不增加进程内读值缓存。仅缓存键的编码/逻辑键映射和本实例自有键集合；两个方向的
  键映射各最多 1024 项，溢出整体清空，切换命名空间时清空。
- 自有键集合首次扫描、随后随本实例写删维护；`setNamespace` 使其失效，但不删除旧数据。
  同 container、同 namespace 的不同实例可能因外部写删导致集合过时；本阶段保留该限制。
- TTL 是整数毫秒，绝对过期接受 `DateTime` 或毫秒时间戳。`createdAt` 是本库条目标记，
  不能移除；`purge` 只删除可识别且过期的自有条目，raw 模式跳过清理。
- 滑动续期要求 `expireAt - now <= ttl * 0.9`，即已过去至少 10% TTL（剩余最多 90%）才续期。
  剩余超过 90% 时不回写，抑制高频读取导致的写放大。
- `enckey` 要求 `keyCodec` 或 `codec`；`codeable` 要求值 `codec`，缺失时警告并降级。
- 调试模式在持久写入入口断言初始化已完成；release 行为不变。
- `get_storage` 2.1.1 的写入 Future 只覆盖 flush 调度，带不出真实落盘错误。
  `.catchError` 仅尽力处理；`force` 不重试异步落盘失败。
- `container` / `storageKey(key)` 提供外部互操作。监听回调时序、整容器清空及 isolate
  隔离的限制见 README 的 GetX 示例。

验证入口：在包根目录执行 `flutter analyze` 和 `flutter test`；示例有独立 pubspec，
另执行 `flutter analyze example`。
