# xlru

[English](README.md)

零依赖的 Dart / Flutter LRU 缓存（VM 和 Web，Dart 3.5+），带移除回调、pin，
以及不改变使用顺序的查询。

```yaml
dependencies:
  xlru: ^0.1.0
```

## 快速开始

```dart
import 'package:xlru/xlru.dart';

void main() {
  final cache = XlruCache<String, int>(
    maxSize: 2,
    onRemove: (key, value, cause) => print('$key=$value: ${cause.name}'),
  );
  cache.set('a', 1);
  cache.set('b', 2);
  cache.get('a'); // a 变成最近使用。
  cache.set('c', 3); // 淘汰 b（打印 "b=2: evicted"）。
  print(cache.keys.toList()); // [c, a]
  print(cache.peek('a')); // 1，不改变顺序。
}
```

`maxSize` 按条目数计。所有公开类型都以 `Xlru` 开头。

## 用 pin 保住正在使用的值

被 pin 的项不会因为腾位置被淘汰，适合“用的时候必须活着”的资源：

```dart
final feeds = XlruCache<String, Feed>(
  maxSize: 10,
  onRemove: (key, feed, cause) => feed.dispose(),
);

final feed = feeds.putIfAbsent('forest', () => Feed('forest'));
feeds.pin('forest');
// ... 使用 feed ...
feeds.unpin('forest');

// 或者一步到位；action 抛异常也一定会 unpin：
final name = feeds.usePinned('forest', (feed) => feed.name);
```

每次成功的 `pin` 都要对应一次 `unpin`。pin 只挡住淘汰：用不同的值 `set` 覆盖、
`remove`、`clear` 照样会移除被 pin 的项（并触发 `onRemove`）。剩下的项全被 pin 时，
缓存条目数可以超过 `maxSize`，直到之后的 `set`、`unpin` 或 `resize` 再收敛。

## API

### `XlruCache<K, V>`

`final class`。只在单个 isolate 内使用，每个 isolate 各持有一个实例。

#### 构造器

```dart
XlruCache({
  required int maxSize,
  XlruRemovalListener<K, V>? onRemove,
  bool Function(K, K)? equals,
  int Function(K)? hashCode,
  bool allowSelfEviction = false,
})
```

| 参数 | 说明 |
| --- | --- |
| `maxSize` | 容量（条目数），至少为 1，否则抛 `ArgumentError`。 |
| `onRemove` | 每移除一项就调用一次，见[移除回调](#移除回调)。 |
| `equals`、`hashCode` | 自定义 key 相等规则，约定同 `HashMap`：相等的 key 必须有相同且稳定的哈希。默认用 `==` 和 `hashCode`。 |
| `allowSelfEviction` | `false`（默认）：`set` / `putIfAbsent` 刚写入的项不会被同一次调用淘汰，写完可以立刻 `pin`。`true`：其余项全被 pin 时，新项可能被立刻淘汰（并回调）。 |

```dart
final cache = XlruCache<String, int>(maxSize: 100);
final caseInsensitive = XlruCache<String, int>(
  maxSize: 100,
  equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
  hashCode: (k) => k.toLowerCase().hashCode,
);
```

#### 属性

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `maxSize` | `int` | 当前容量。 |
| `length` | `int` | 条目数，含被 pin 的项。 |
| `isEmpty` | `bool` | 是否没有条目。 |
| `isNotEmpty` | `bool` | 是否至少有一个条目。 |
| `allowSelfEviction` | `bool` | 构造时传入的值。 |
| `keys` | `Iterable<K>` | 从最近到最旧的 key，不改变顺序。 |
| `values` | `Iterable<V>` | value，顺序同 `keys`。 |
| `entries` | `Iterable<MapEntry<K, V>>` | 键值对，顺序同 `keys`。 |

`keys`、`values`、`entries` 是实时视图。遍历过程中修改缓存（包括 `get`、`pin`、
`unpin`、`set`），下一步会抛 `ConcurrentModificationError`。读取用 `peek`，
或者先复制：

```dart
for (final key in cache.keys.toList()) {
  print(cache.get(key));
}
```

它们也不支持快速随机访问：`keys.length`、`keys.contains` 要遍历全部条目，
请改用 `length` 和 `containsKey`。

#### 方法

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `get(K key)` | `V?` | 返回值并标记为最近使用；不存在返回 `null`。 |
| `peek(K key)` | `V?` | 返回值，不改变顺序；不存在返回 `null`。 |
| `containsKey(K key)` | `bool` | key 是否存在，不改变顺序。 |
| `set(K key, V value)` | `void` | 插入或覆盖，并标记为最近使用，可能淘汰其他项。已存在的项保留原 key 对象和 pin。 |
| `putIfAbsent(K key, V Function() ifAbsent)` | `V` | 已存在则返回现有值（并标记为最近使用）；否则插入 `ifAbsent` 创建的值并返回。`ifAbsent` 抛异常则不插入。 |
| `remove(K key)` | `V?` | 无视 pin 移除并返回其值；不存在返回 `null`。 |
| `clear()` | `void` | 清空所有项，包括被 pin 的。 |
| `resize(int maxSize)` | `void` | 修改容量，需要时立即淘汰。小于 1 抛 `ArgumentError`，缓存保持不变。 |
| `pin(K key)` | `bool` | pin 计数 +1；key 不存在返回 `false`；不改变顺序。 |
| `unpin(K key)` | `bool` | pin 计数 -1；key 不存在或没被 pin 返回 `false`。可能立刻淘汰该项或其他项，并触发 `onRemove`。 |
| `isPinned(K key)` | `bool` | key 是否存在且至少被 pin 一次。 |
| `usePinned<R>(K key, R Function(V value) action)` | `R?` | pin 住 key，用其值执行 `action`，结束后一定 unpin；key 不存在则不执行并返回 `null`。 |
| `toMap()` | `Map<K, V>` | 独立拷贝，从最近到最旧，沿用同样的 key 相等规则。 |

`get`、`peek`、`remove`、`usePinned` 在“不存在”和“存的就是 `null`”时都返回
`null`，需要区分时用 `containsKey`。

```dart
cache.set('a', 1);
cache.get('a'); // 1
cache.peek('b'); // null
cache.putIfAbsent('b', () => 2); // 2
cache.pin('a'); // true
cache.remove('a'); // 1（pin 挡不住 remove）
cache.resize(50);
final copy = cache.toMap();
cache.clear();
```

### `XlruRemovalListener<K, V>`

```dart
typedef XlruRemovalListener<K, V> = void Function(
    K key, V value, XlruRemovalCause cause);
```

### `XlruRemovalCause`

| 值 | 触发时机 |
| --- | --- |
| `evicted` | 为保持不超过 `maxSize` 而移除了未 pin 的项（包括由 `unpin`、`resize` 触发的）。 |
| `replaced` | `set` 给已有 key 存了不同（非 `identical`）的值；`value` 是旧值，key 仍在缓存里。存同一个对象不通知。 |
| `removed` | `remove` 删除了已有的项。 |
| `cleared` | `clear` 删除了该项（从最旧开始）。 |
| `lost` | 预留给带存储后端的缓存：后端里的值丢了。纯内存的 `XlruCache` 不会产生它，但穷尽 `switch` 里要处理。 |

## 移除回调

- 回调同步执行，发生在这次操作改完缓存之后，回调里可以再调用缓存。
- 一次操作可能产生多条通知：先 `replaced`，再是各个 `evicted`。
- 回调抛异常时，同一次操作的其余回调照常执行，最后把第一个异常从触发它们的那次调用
  （`set`、`putIfAbsent`、`remove`、`clear`、`resize`、`unpin`）重新抛出，已做的修改不回滚。
- 回调里通常会释放 value，所以 `remove` 返回的值可能已被释放；同一资源存在多个 key 下时，
  释放要自己协调。

## 不包含

不提供过期、按大小加权、异步加载和统计，需要的话基于 `onRemove` 自行包一层。

## 许可证

MIT，见 [LICENSE](LICENSE)。基准测试：[benchmark/README.md](benchmark/README.md)。
