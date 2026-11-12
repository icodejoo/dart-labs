# ffuzzy

[English](README.md) | 中文

Flutter 的模糊搜索库，底层是一个很小的 **C** 引擎。

`ffuzzy` 是 [`nucleo`](https://github.com/helix-editor/nucleo)（Helix 编辑器用的
matcher）的 C 语言逐字节移植。不需要 Rust 工具链，也不用代码生成：引擎就是几个 C
源文件，由各平台的 SDK 自己编译。原生库 strip 后约 **32 KB**。

- **快**：和 Rust 的 `nucleo` 一样快或更快。所有多线程配置和 `substring` 都更快，
  CJK 与单线程 `fuzzy` 持平。10 万条语料过滤一次约 1.4 ms。
- **小**：原生 `.so`（arm64）约 32 KB，纯 C，没有第三方依赖。
- **全平台**：Android、iOS、macOS、Linux、Windows 和 **Web**（WASM）。
- **能搜任意对象**：`FuzzyCorpus<T>` 搜 `List<T>`，命中结果带着原对象（`hit.raw`）。
- **一种匹配模式一个方法**：`fuzzy`（fzf 风格，支持 `! ^ ' $` 操作符）、`substring`、
  `prefix`、`postfix`、`exact`。`search()` 通过 `SearchStrategy`（fuzzy / approx /
  fallback / merge）选算法，`dual()` 一次返回两种结果。
- **编辑距离搜索**：`approx()` 用 Myers bit-parallel Levenshtein，能容忍拼写错误、
  替换和换位。
- **多线程**和**异步**扫描，大语料也不卡 UI。
- **命中高亮**：提供码点到 UTF-16 的下标转换。
- **Unicode / CJK**：折叠变音符和简单大小写；CJK 直接按码点匹配。
- **多键搜索**：挂上你自己算好的拼音 / 罗马音 / 首字母，CJK 条目也能用拉丁字母搜到。

## 安装

```yaml
dependencies:
  ffuzzy: ^0.6.2

environment:
  sdk: ^3.6.0
  flutter: ">=3.24.0"
```

> **无需额外平台配置**：C 源码由各平台 SDK 在 `flutter build` 时自动编译并打包，
> 不用自己配 NDK、Xcode 标志之类的工具链。

## Web 支持

在 Web 上，`ffuzzy` 用的是同一份 C 引擎的 WASM 构建。在 `main()` 里调用一次
`ffuzzyInit`。它在原生平台什么都不做，所以可以无条件调用：

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 从 npm 发布的包加载 WASM 引擎：
  await ffuzzyInit(
    webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.8.1/dist/ffuzzy.mjs',
  );
  // 或自托管：await ffuzzyInit(webAssetsUrl: '/assets/ffuzzy.mjs');
  runApp(const MyApp());
}
```

初始化完成后，`FuzzyCorpus` 的全部 API 在各平台行为一致。

> **Web 注意**：WASM 在主线程同步执行。`asyncFuzzy` 只是通过 microtask 让出事件循环，
> WASM 计算本身仍会占用主线程（没有 Web Worker）。大语料建议控制在 5 万条以内，
> 或者同步调用 `fuzzy` 并设置 `limit`，让单次搜索不超出一帧的时间。

**延迟初始化（corpus 在 `ffuzzyInit` 之前创建）：** 如果 `FuzzyCorpus` 在 `ffuzzyInit`
完成前就创建了，它会进入*延迟*模式。同步搜索方法立即返回 `[]`；`async*` 方法
（`asyncFuzzy`、`asyncSearch`、`asyncApprox`、`asyncDual` 等）会先等 WASM 初始化完，
再执行并返回真实结果。WASM 就绪后，`fuzzy`、`approx`、`fallback`、`merge`、`dual`
这几种 strategy 在同步和异步下表现一致。

**参数：**
- `webUrl`：`ffuzzy.mjs` 的 CDN 或自托管地址。不需要 Flutter asset。
- `webAssetsUrl`：本地 Flutter asset 路径（如 `/assets/ffuzzy.mjs`）。要在
  `pubspec.yaml` 的 `assets:` 里声明这个文件。可离线使用。
- 两个都传时，`webAssetsUrl` 优先。

## 快速上手

```dart
import 'package:ffuzzy/ffuzzy.dart';

// 纯字符串：
final corpus = FuzzyCorpus.strings(['src/main.dart', 'lib/widget.dart', '中文搜索']);
for (final h in corpus.fuzzy('srcmn', parallel: true, limit: 50)) {
  print('${h.raw}  score=${h.score}');   // h.raw 就是命中的字符串
}
corpus.dispose();                          // 或交给 NativeFinalizer 回收

// 任意对象 —— 给一个 stringOf 提取器；命中携带原对象：
final files = FuzzyCorpus<File>(myFiles, stringOf: (f) => f.path);
final hit = files.prefix('lib/').firstOrNull;   // hit.raw 是 File
```

---

# API

所有导出都来自 `package:ffuzzy/ffuzzy.dart`。

## `ffuzzyInit`

```dart
Future<void> ffuzzyInit({String? webUrl, String? webAssetsUrl})
```

在 **web** 上初始化 WASM 引擎，原生平台什么都不做。在创建任何 `FuzzyCorpus` 之前调用一次；重复调用没有副作用。

## `FuzzyCorpus<T>`

把 `T` 类型的条目放在内存里。建一次，可以搜很多次。

### 构造方式

```dart
FuzzyCorpus<T>(items, {required String Function(T) stringOf, FuzzyOptions options, …})

FuzzyCorpus.strings(items, {…})          // T = String
FuzzyCorpus.byKey(items, field, {…})     // T = Map，按单个字段搜索
FuzzyCorpus.byKeys(items, fields, {…})   // T = Map，跨多个字段；hit.matchedKey = 命中字段的下标
FuzzyCorpus.buildAsync(items, {required stringOf, …})  // 在后台 isolate 建库，不卡 UI
```

### 增删改

| 方法 | 说明 |
|---|---|
| `add(T item)` | 追加一条。 |
| `addAll(Iterable<T>)` | 批量追加。 |
| `addAllAsync(Iterable<T>)` | 批量追加：原生在后台 isolate，web 用 microtask。运行期间独占语料。 |
| `addKey(T, List<FuzzyKey>)` | 追加并附加[多键](#多键--cjk-音译)（拼音/罗马音等）。 |
| `update(index, T)` | 替换指定位置（丢弃多键）。 |
| `removeAt(index)` | 删除指定位置。 |
| `removeWhere(test)` | 删除满足条件的所有项，返回删除数量。 |
| `refresh([source])` | 不传参数：用当前 items 重建；传了：替换全部数据。 |
| `clear()` | 清空所有项，语料对象还能继续用。 |
| `length` | 当前条目数。 |

### 搜索模式

#### 经典模式

每种模式都返回 `List<FuzzyHit<T>>`，并且都有 `*Raws`、`async*`、`async*Raws` 变体：

```dart
fuzzy / asyncFuzzy         // fzf 风格子序列匹配，支持 ! ^ ' $ 操作符
substring / asyncSubstring // 连续子串匹配
prefix / asyncPrefix       // 前缀匹配
postfix / asyncPostfix     // 后缀匹配（suffix 是其别名）
exact / asyncExact         // 整串精确匹配

corpus.asyncFuzzy(q)       // Future<List<FuzzyHit<T>>> —— 原生走 Isolate.run
corpus.fuzzyRaws(q)        // List<T> —— 跳过 FuzzyHit 包装，更快
corpus.asyncFuzzyRaws(q)   // Future<List<T>>
```

- 每个方法都可以用命名参数覆盖 `FuzzyOptions`（`caseMatching`/`limit`/`highlight`/`scoring` 等），只对这一次调用生效。

#### 统一入口 `search()`

```dart
List<FuzzyHit<T>> search(String q, {
  SearchStrategy strategy = SearchStrategy.fuzzy,
  int? maxDistance,   // 用于 approx/fallback/merge；省略时按查询长度自动选
  …
})
```

| `strategy` | 行为 |
|---|---|
| `SearchStrategy.fuzzy` | fzf 子序列（默认，等价 `fuzzy()`） |
| `SearchStrategy.approx` | 编辑距离（等价 `approx()`） |
| `SearchStrategy.fallback` | 先子序列，无结果再走编辑距离 |
| `SearchStrategy.merge` | 两种算法都跑，子序列命中在前 |

同样有 `searchRaws()` / `asyncSearch()` / `asyncSearchRaws()`。

#### 编辑距离快捷方式 `approx()`

```dart
List<FuzzyHit<T>> approx(String q, {int? maxDistance, …})
```

`maxDistance` 省略时按查询长度自动选（≤2 字符→0，3–5→1，6+→2）。同样有
`approxRaws()` / `asyncApprox()` / `asyncApproxRaws()`。

#### 双结果 `dual()`

一次扫描语料就跑完两种算法，分成两组返回：

```dart
FuzzyDualResult<T> result = corpus.dual('iphoen');
result.fuzzy   // 子序列命中
result.approx  // 编辑距离命中
```

同样有 `asyncDual()`。

`async*` 调用可以同时进行。在 Web 上，`ffuzzyInit` 完成前发起的调用会先等 WASM
就绪，再返回结果。异步搜索进行时修改语料会抛 `StateError`。

### 生命周期

| 方法 | 说明 |
|---|---|
| `dispose()` | 可重复调用；会等进行中的异步任务结束再释放。可以放进 `State.dispose()`。 |
| `asyncDispose()` | 同上，但返回 `Future`，可以 `await`。 |

## `FuzzyOptions`

| 字段 | 默认 | 说明 |
|---|---|---|
| `caseMatching` | `smart` | `respect`/`ignore`/`smart`（`smart`：查询全小写时不区分大小写，含大写时区分） |
| `normalization` | `smart` | `never`/`smart`（变音符折叠） |
| `parallel` | `false` | 多线程打分（仅原生） |
| `threads` | `0` | 0=自动（半核，上限 8） |
| `limit` | `0` | 最多返回数（0=全部） |
| `highlight` | `false` | `true` 时填充 `FuzzyHit.indices`（高亮用） |
| `scoring` | `fast` | `fast`（滚动 DP）/ `off`（不排名）/ `nucleo`（全矩阵 DP，精度最高） |

## `FuzzyHit<T>`

| 字段 | 说明 |
|---|---|
| `raw` | 命中的原始对象 |
| `index` | 插入顺序下标 |
| `score` | 匹配分（同次查询内可比较） |
| `matchedKind` | 命中的键类型（`FuzzyKeyKind` 枚举） |
| `matchedKindCode` | 原始整数 kind 值（自定义 kind ≥ 100 时用于区分） |
| `matchedKey` | 哪个键命中（0=原始键；`byKeys` 下等于 `fields` 下标） |
| `indices` | 命中字符的码点下标（仅 `highlight:true` 时有值），要用 `fuzzyCodepointToUtf16` 转换 |

## 高亮

```dart
final hit = corpus.fuzzy('src', highlight: true).first;
final marks = fuzzyCodepointToUtf16(hit.raw, hit.indices).toSet();
final spans = [
  for (var i = 0; i < hit.raw.length; i++)
    TextSpan(text: hit.raw[i], style: marks.contains(i) ? boldStyle : null),
];
```

## 多键 / CJK 音译

挂上你自己算好的拼音 / 首字母，让中文条目能用拉丁字母搜到：

```dart
corpus.addKey('张三', [
  FuzzyKey.kind('zhangsan', FuzzyKeyKind.pinyin),
  FuzzyKey.kind('zs', FuzzyKeyKind.initials),
]);

final h = corpus.fuzzy('zs').first;
// h.matchedKind == FuzzyKeyKind.initials
```

## 高频搜索最佳实践

边输入边搜时，只保留最新一次查询的结果：

```dart
int _gen = 0;
Future<void> onQueryChanged(String q) async {
  final gen = ++_gen;
  final hits = await corpus.asyncFuzzy(q, limit: 50);
  if (gen != _gen) return;           // 被更新的按键超越，丢弃旧结果
  setState(() => _hits = hits);
}
```

## 编辑距离搜索（容忍拼写错误）

`approx()` 会匹配这样的条目：最接近查询的那个键，与查询的 Levenshtein 编辑距离不超过
`maxDistance`。和 `fuzzy`（子序列）不同，它能容忍被替换的字符和多出来的字符：

```dart
corpus.approx('iphoen')                                     // maxDistance 自动推算
corpus.approx('iphoen', maxDistance: 2)                     // 显式指定
corpus.search('iphoen', strategy: SearchStrategy.fallback)  // 先子序列，再编辑距离
corpus.search('iphoen', strategy: SearchStrategy.merge)     // 两者合并
corpus.dual('iphoen')                                       // 两者分桶
```

结果按距离升序排列。编辑距离命中的 `FuzzyHit.indices` 始终为空。

> 两种算法（子序列和编辑距离）始终都编译在内。0.6.2 之前，编辑距离要用 `FFZ_EDIT_DISTANCE` 编译标志开启；现在只有一种构建。

## 错误处理

- **可恢复**：库或符号加载失败抛 `FuzzyException`；用法错误（`dispose` 后继续用、
  异步搜索进行中修改语料）抛 `StateError`。
- **原生硬故障**：捕获不了，见 `FuzzyCrash`。

```dart
final report = FuzzyCrash.lastReport();
if (report != null) log('ffuzzy 上次崩溃：\n$report');
FuzzyCrash.install(breadcrumbPath: '${dir.path}/ffuzzy_crash.log');
```

## 各平台对比

| 平台 | 引擎 | 异步搜索 |
|---|---|---|
| Android / iOS / macOS / Linux / Windows | C via `dart:ffi` | `Isolate.run`（真正后台线程） |
| Web | C via WASM（`dart:js_interop`） | Microtask 让出（主线程） |

## 性能

真机测试（Flutter Windows，profile 模式，10 万条）：

| | C (ffuzzy) | Rust (nucleo) |
|---|---|---|
| 语料常驻内存 | 15.25 MB | 16.54 MB |
| 过滤（fuzzy，top-50） | 1.36 ms | 1.65 ms |

方法论、与 nucleo 的逐字节一致性验证（6210/6210）、Unicode 覆盖范围和引擎设计，
详见 [`docs/INTERNALS.md`](docs/INTERNALS.md)。

## npm / JavaScript

同一份 C 引擎也发布成了 [`@codejoo/ffuzzy`](https://www.npmjs.com/package/@codejoo/ffuzzy)，
可用在浏览器和 Node.js 里，API 和 Dart 版对齐。两种算法都在同一个 bundle 里。

```ts
import { ffuzzyInitialize, FuzzyCorpus } from '@codejoo/ffuzzy';
await ffuzzyInitialize();
const corpus = FuzzyCorpus.strings(['src/main.rs', 'README.md']);
corpus.fuzzy('src', { highlight: true });
corpus.approx('srcc');                  // 编辑距离，maxDistance 自动推算
corpus.search('src', { strategy: 'fallback' });
corpus.dual('src');                     // { fuzzy: [...], approx: [...] }
corpus.dispose();
```

## 许可

MIT —— 详见 [LICENSE](LICENSE)。
