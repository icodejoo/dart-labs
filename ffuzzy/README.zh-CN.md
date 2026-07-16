# ffuzzy

[English](README.md) | 中文

为 Flutter 提供的高性能模糊搜索，由紧凑的 **C** 引擎驱动。

`ffuzzy` 是 [`nucleo`](https://github.com/helix-editor/nucleo)（Helix 编辑器背后的
matcher）的纯 C 逐字节复刻：无需 Rust 工具链、无代码生成，引擎就是几个 C 源文件，
由各平台 SDK 自行编译。原生库 **strip 后约 32 KB**。

- **快** —— 媲美或超过 Rust 的 `nucleo`：所有多线程档全面更快、`substring` 全档更快，
  CJK 与单线程 `fuzzy` 持平。10 万条语料一次过滤约 1.4 ms。
- **小** —— 原生 `.so`（arm64）约 32 KB，纯 C，零第三方依赖。
- **全平台** —— Android、iOS、macOS、Linux、Windows 和 **Web**（WASM）。
- **可搜任意对象** —— `FuzzyCorpus<T>` 搜索 `List<T>`，命中携带原对象（`hit.raw`）。
- **匹配模式即方法** —— `fuzzy`（fzf 风格，支持 `! ^ ' $` 操作符）、`substring`、`prefix`、
  `postfix`、`exact`，加统一 `search()`（`SearchStrategy`：fuzzy / approx / fallback / merge）
  和 `dual()`。
- **编辑距离搜索** —— `approx()` 用 Myers bit-parallel Levenshtein，容忍拼写错误、
  替换和换位（可选编译标志）。
- **多线程**与**异步**扫描，大语料也不卡 UI。
- **命中高亮**，带正确的 Unicode（码点 → UTF-16）下标转换。
- **Unicode / CJK** —— 变音符 + 完整简单大小写折叠；CJK 直接逐码点匹配。
- **多键搜索** —— 挂载宿主算好的拼音 / 罗马音 / 首字母，让 CJK 项也能用拉丁键入找到。

## 安装

```yaml
dependencies:
  ffuzzy: ^0.6.0

environment:
  sdk: ^3.6.0
  flutter: ">=3.24.0"
```

> **无需额外平台配置** —— C 源码由各平台 SDK 在 `flutter build` 时自动编译打包，
> 使用者不需要配置 NDK、Xcode 标志等任何额外工具链。

## Web 支持

在 Web 平台，`ffuzzy` 使用同一份 C 引擎的 WASM 构建。在 `main()` 里调用一次
`ffuzzyInit`——在原生平台是空操作，可以无条件调用：

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

> **Web 注意** —— WASM 在主线程同步执行。`asyncFuzzy` 通过 microtask 让出事件循环，
> 但 WASM 计算本身仍在主线程（无 Web Worker）。大语料（>5 万条）建议用 `limit` 控制
> 单次返回数量，或保持语料量在合理范围内。

**延迟初始化（corpus 在 `ffuzzyInit` 之前创建）：** 若 `FuzzyCorpus` 在 `ffuzzyInit`
完成前构造，会进入*延迟*模式——同步搜索方法立即返回 `[]`，而 `async*` 方法
（`asyncFuzzy`、`asyncSearch`、`asyncApprox`、`asyncDual` 等）会自动等待 WASM
初始化完成后再执行并返回真实结果。`fuzzy`、`approx`、`fallback`、`merge`、`dual`
所有 strategy 在同步/异步两种形态下、WASM 就绪后表现一致。

**参数：**
- `webUrl` —— CDN 或自托管的 `ffuzzy.mjs` URL。不需要 Flutter asset。
- `webAssetsUrl` —— 本地 Flutter asset 路径（如 `/assets/ffuzzy.mjs`）。需在
  `pubspec.yaml` 的 `assets:` 中声明。支持离线。
- 两者都传时 `webAssetsUrl` 优先。

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

在 **web** 上初始化 WASM 引擎；原生平台为空操作。在构造任何 `FuzzyCorpus` 之前调用一次，幂等。

## `FuzzyCorpus<T>`

一次构建、多次搜索的语料库。

### 构造方式

```dart
FuzzyCorpus<T>(items, {required String Function(T) stringOf, FuzzyOptions options, …})

FuzzyCorpus.strings(items, {…})          // T = String
FuzzyCorpus.byKey(items, field, {…})     // T = Map，按单字段搜索
FuzzyCorpus.byKeys(items, fields, {…})   // T = Map，跨多字段；hit.matchedKey = 命中字段下标
FuzzyCorpus.buildAsync(items, {required stringOf, …})  // 后台 isolate 建库，不卡 UI
```

### 增删改

| 方法 | 说明 |
|---|---|
| `add(T item)` | 追加一条。 |
| `addAll(Iterable<T>)` | 批量追加。 |
| `addAllAsync(Iterable<T>)` | 后台 isolate（原生）/ microtask（web）批量追加，独占写。 |
| `addKey(T, List<FuzzyKey>)` | 追加并附加[多键](#多键--cjk-音译)（拼音/罗马音等）。 |
| `update(index, T)` | 替换指定位置（丢弃多键）。 |
| `removeAt(index)` | 删除指定位置。 |
| `removeWhere(test)` | 删除满足条件的所有项，返回删除数量。 |
| `refresh([source])` | 无参：以当前 items 重建；有参：替换全部数据。 |
| `clear()` | 清空所有项，语料对象保留可继续使用。 |
| `length` | 当前项目数量。 |

### 搜索模式

#### 经典模式

每种模式返回 `List<FuzzyHit<T>>`，均有 `*Raws`、`async*`、`async*Raws` 变体：

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

- 各方法均支持命名参数覆盖 `FuzzyOptions`（`caseMatching`/`limit`/`highlight`/`scoring` 等）。

#### 统一入口 `search()`

```dart
List<FuzzyHit<T>> search(String q, {
  SearchStrategy strategy = SearchStrategy.fuzzy,
  int? maxDistance,   // 用于 approx/fallback/merge；省略时自动推算
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

`maxDistance` 省略时按查询长度自动推算（≤2 字符→0，3–5→1，6+→2）。同样有
`approxRaws()` / `asyncApprox()` / `asyncApproxRaws()`。

#### 双结果 `dual()`

单次 corpus 扫描跑两种算法，分桶返回：

```dart
FuzzyDualResult<T> result = corpus.dual('iphoen');
result.fuzzy   // 子序列命中
result.approx  // 编辑距离命中
```

同样有 `asyncDual()`。

`async*` 调用可安全重叠；在 Web 上还兼作延迟初始化路径。异步搜索进行中时
变更 corpus 会抛 `StateError`。

### 生命周期

| 方法 | 说明 |
|---|---|
| `dispose()` | 幂等；in-flight 时等完成再释放。可在 `State.dispose()` 中调用。 |
| `asyncDispose()` | 同上但返回 `Future`，可 `await`。 |

## `FuzzyOptions`

| 字段 | 默认 | 说明 |
|---|---|---|
| `caseMatching` | `smart` | `respect`/`ignore`/`smart`（lowercase 查询=不区分，含大写=区分） |
| `normalization` | `smart` | `never`/`smart`（变音符折叠） |
| `parallel` | `false` | 多线程打分（仅原生） |
| `threads` | `0` | 0=自动（半核，上限 8） |
| `limit` | `0` | 最多返回数（0=全部） |
| `highlight` | `false` | `true` 时填充 `FuzzyHit.indices`（高亮用） |
| `scoring` | `fast` | `fast`（滚动DP）/ `off`（不排名）/ `nucleo`（全矩阵DP，最高精度） |

## `FuzzyHit<T>`

| 字段 | 说明 |
|---|---|
| `raw` | 命中的原始对象 |
| `index` | 插入顺序下标 |
| `score` | 匹配分（同次查询内可比较） |
| `matchedKind` | 命中的键类型（`FuzzyKeyKind` 枚举） |
| `matchedKindCode` | 原始整数 kind 值（自定义 kind ≥ 100 时用于区分） |
| `matchedKey` | 哪个键命中（0=原始键；`byKeys` 下等于 `fields` 下标） |
| `indices` | 命中字符码点下标（仅 `highlight:true` 时有值）；需经 `fuzzyCodepointToUtf16` 转换 |

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

挂载宿主算好的拼音/首字母，让中文项通过拉丁输入找到：

```dart
corpus.addKey('张三', [
  FuzzyKey.kind('zhangsan', FuzzyKeyKind.pinyin),
  FuzzyKey.kind('zs', FuzzyKeyKind.initials),
]);

final h = corpus.fuzzy('zs').first;
// h.matchedKind == FuzzyKeyKind.initials
```

## 高频搜索最佳实践

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

`approx()` 匹配与查询最佳键的 Levenshtein 编辑距离在 `maxDistance` 以内的项。
与 `fuzzy`（子序列）不同，它容忍替换字符或多余字符：

```dart
corpus.approx('iphoen')                                     // maxDistance 自动推算
corpus.approx('iphoen', maxDistance: 2)                     // 显式指定
corpus.search('iphoen', strategy: SearchStrategy.fallback)  // 先子序列，再编辑距离
corpus.search('iphoen', strategy: SearchStrategy.merge)     // 两者合并
corpus.dual('iphoen')                                       // 两者分桶
```

结果按距离升序排列。编辑距离命中的 `FuzzyHit.indices` 始终为空。

> **可选功能** —— 需要原生库（或 WASM 模块）编译时开启 `FFZ_EDIT_DISTANCE`。

## 错误处理

- **可恢复**：库/符号加载失败 → `FuzzyException`；误用（`dispose` 后使用、异步搜索
  进行中变更）→ `StateError`。
- **原生硬故障**：不可捕获——见 `FuzzyCrash`。

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

完整方法论、与 nucleo 的逐字节一致性验证（6210/6210）、Unicode 覆盖范围和引擎设计详见
[`docs/INTERNALS.md`](docs/INTERNALS.md)。

## npm / JavaScript

同一份 C 引擎发布为 [`@codejoo/ffuzzy`](https://www.npmjs.com/package/@codejoo/ffuzzy)，
供浏览器和 Node.js 项目使用，API 与 Dart 版对齐（两种算法都编入同一 bundle）。

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
