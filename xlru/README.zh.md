# xlru

[English](README.md)

零依赖、纯 Dart 的 LRU 缓存，提供带移除原因的回调、引用计数 pin，
以及不改变使用顺序的查询。支持 Dart 3.5+、VM、Web 和 Flutter。

它是小而同步的进程内缓存：容量按条目数计（不是字节），pin 住的项可让缓存暂时超容量；
不含过期、权重、异步加载和统计，需要的话基于 `onRemove` 自行包一层。
所有公开类型都带 `Xlru` 前缀，避免命名冲突。

## 安装和使用

```yaml
dependencies:
  xlru: ^0.1.0
```

```dart
import 'package:xlru/xlru.dart';

void main() {
  final cache = XlruCache<String, int>(
    maxSize: 2,
    onRemove: (key, value, cause) => print('$key=$value: ${cause.name}'),
  );
  cache.set('a', 1);
  cache.set('b', 2);
  cache.get('a'); // 提升为最近使用。
  cache.set('c', 3); // 淘汰 b。
  print(cache.keys.toList()); // [c, a]
  cache.peek('a'); // 不提升。
}
```

## API

| API | 行为 |
| --- | --- |
| 构造器 | `maxSize` 必须 ≥ 1；可传入 `onRemove`、`equals`、`hashCode`、`allowSelfEviction`（默认 false，见下文 pin 一节）。 |
| `maxSize` / `resize(n)` | 查询或调整容量；缩容立即淘汰未 pin 的项。非法容量抛 `ArgumentError`，状态不变。 |
| `length` / `isEmpty` / `isNotEmpty` | 统计包含 pinned 项的当前内容。 |
| `get(key)` | 命中提升并返回值；不存在返回 null。 |
| `peek(key)` / `containsKey(key)` | 查询但不提升。 |
| `set(key, value)` | 插入或覆盖并提升；保留原始 key 对象和 pin 计数。 |
| `putIfAbsent(key, creator)` | 已存在则提升并返回，否则创建、插入并返回。 |
| `remove(key)` | 无视 pin 移除，返回旧值；不存在返回 null。 |
| `clear()` | 无视 pin 清空；按最旧到最新通知。 |
| `pin(key)` / `unpin(key)` | 引用计数 +1/-1，不提升；不存在或未 pin 时 unpin 返回 false。`unpin` 可能触发淘汰和回调。 |
| `usePinned(key, action)` | pin 后执行 `action(value)`，`finally` 里一定 unpin；不存在返回 null。 |
| `isPinned(key)` | 是否存在且 pin 计数大于零，不提升。 |
| `keys` / `values` / `entries` | 最近到最旧的实时可迭代对象，含 pinned，不提升。 |
| `toMap()` | 同顺序的独立拷贝，保留自定义 key 相等规则；value 仍是原对象引用。 |

允许 null 值，用 `containsKey` 区分 null 与不存在。`putIfAbsent` 创建器抛异常时，
该方法不插入；创建器内部自行修改缓存的效果保留。创建器重入插入相同 key 时，
最终返回值会覆盖它。默认情况下，方法返回时创建的值一定还在缓存里。

自定义相等规则遵循 `HashMap` 约定：相等的 key 哈希相同且稳定；
存储期间不要修改 key 的相等或哈希行为，比较和哈希函数本身不应修改缓存。

## pin 与资源生命周期

典型场景是游戏场景 feed 注册表：移除时调用 `dispose()`，抽屉使用期间 pin，
关闭后 unpin。完整纯 Dart 示例见 [example](example/xlru_example.dart)。

每次成功 pin 都需要对应一次 unpin。pin 不改变使用顺序，所有项仍在同一条
LRU 链表中；覆盖 pinned 项保留 pin 计数，但旧值仍触发 replaced 回调。
淘汰从最旧端跳过 pinned 项，选第一个未 pin 的项。

全部剩余项都 pinned 时允许超容量（例如缩容后）；后续 `set`、成功 `unpin`、
`resize` 会再次收敛。`remove` 和 `clear` 无视 pin。

`set` 或 `putIfAbsent` 刚写入的项不会被同一次调用淘汰，所以"先取再 pin"的写法
在其余项全被 pin 住时也安全：缓存暂时超容量，等下次写入、`unpin` 或 `resize`
再收敛。传 `allowSelfEviction: true` 则按纯 LRU 顺序淘汰：其余项全 pinned 时，新写入
的项会立刻被淘汰并回调，`putIfAbsent` 返回的值已不在缓存中。

### 资源归属

pin 只防**容量淘汰**。`set` 覆盖、`remove`、`clear` 仍会移除 pinned 项，回调通常会
`dispose()` 它。因此：

- `remove` 返回的值（或开启 `allowSelfEviction` 时 `putIfAbsent` 返回的值）可能已被回调释放。
- 同一资源挂在多个 key 下时，回调里逐项 `dispose()` 需要你自己协调（比如自己计数）。
- 推荐用 `usePinned`，或把 `pin`/`unpin` 放进 `try`/`finally`。

## 回调与异常

- `evicted`：容量淘汰。
- `replaced`：非 identical 值覆盖，传入旧值；相同对象覆盖不回调，但仍提升。
- `removed`：显式移除存在的项。
- `cleared`：清空，按最旧到最新。

每次操作先完成所有结构修改，再依次回调；覆盖通知先于容量淘汰通知。
回调同步执行，允许重入。嵌套操作先完成自己的回调，再返回外层回调。
某个回调抛异常，同批其余回调照常执行，最后通过 `Error.throwWithStackTrace`
重新抛出第一个异常并保留原始堆栈（异常从触发这批回调的那次调用抛出，包括 `unpin`、`resize`）；已完成的修改不会回滚。
回调能看到此前回调产生的修改；clear 回调中新插入的项不会被原 clear 删除。

## 复杂度与迭代

条目存放在并列的槽位数组里，而不是每项一个对象：线性探测哈希表把 key
映射到槽位，最近使用顺序是一条用 typed int 数组串起来的槽位双向链表。
满容量插入直接复用被淘汰项的槽位，没有 `onRemove` 时稳态写入不分配对象（有回调时每次移除会分配一个小记录和列表）；热路径在 dart2js、
dart2wasm 和 VM 上都没有运行时类型检查。
查询和更新顺序平均 O(1)，空间 O(n)；每次淘汰为
**O(1 + 链表最旧端连续 pinned 项数量)**，收敛可能需要多次淘汰；
全部 pinned 时扫描 O(n)。`clear` 和 `toMap` 为 O(n)。

迭代器创建后发生修改（包括覆盖值、提升顺序、调整容量、修改 pin 计数），
后续 `moveNext` 抛 `ConcurrentModificationError`。不提升的查询，以及
读取已处于最新端的项，不使迭代器失效。

遍历 `keys` 时不要调 `get`，改用 `peek` 或先 `keys.toList()`。这些可迭代对象不支持随机访问，
`keys.length`、`keys.contains` 是 O(n)，请用 `length` 和 `containsKey`。

单 isolate 使用，不加锁；所有操作同步，不会在 `await` 之间交错；每个 isolate 各持有一个实例，不能跨 isolate 共享。

## 验证和基准

测试、分析、格式化、发布预检命令见英文 README。
[基准说明和实测结果](benchmark/README.md) 对比 xlru、朴素 `LinkedHashMap` LRU、
quiver `LruMap`，覆盖 JIT、AOT、JavaScript（dart2js `-O4` 与 `-O1`）和 WebAssembly。
基准依赖仅属于 dev_dependencies。

MIT 协议，见 [LICENSE](LICENSE)。
