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
  `postfix`、`exact`，各带 `…Async` 异步孪生。
- **多线程**与**异步**扫描，大语料也不卡 UI。
- **命中高亮**，带正确的 Unicode（码点 → UTF-16）下标转换。
- **Unicode / CJK** —— 变音符 + 完整简单大小写折叠；CJK 直接逐码点匹配。
- **多键搜索** —— 挂载宿主算好的拼音 / 罗马音 / 首字母，让 CJK 项也能用拉丁键入找到。

## 安装

```yaml
dependencies:
  ffuzzy: ^0.5.0

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
    webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.7.0/dist/ffuzzy.mjs',
  );
  // 或自托管：await ffuzzyInit(webAssetsUrl: '/assets/ffuzzy.mjs');
  runApp(const MyApp());
}
```

初始化完成后，`FuzzyCorpus` 的全部 API 在各平台行为一致。

> **Web 注意** —— WASM 在主线程同步执行。`fuzzyAsync` 通过 microtask 让出事件循环，
> 但 WASM 计算本身仍在主线程（无 Web Worker）。大语料（>5 万条）建议用 `limit` 控制
> 单次返回数量，或保持语料量在合理范围内。

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

每种模式返回 `List<FuzzyHit<T>>`，均有 `…Async` 异步孪生：

```dart
fuzzy / fuzzyAsync         // fzf 风格子序列匹配，支持 ! ^ ' $ 操作符
substring / substringAsync // 连续子串匹配
prefix / prefixAsync       // 前缀匹配
postfix / postfixAsync     // 后缀匹配（suffix 是其别名）
exact / exactAsync         // 整串精确匹配
```

- 各方法均支持命名参数覆盖 `FuzzyOptions`（`caseMatching`/`limit`/`highlight`/`scoring` 等）。
- **裸对象快捷方式**：`fuzzyRaws`、`prefixRaws` 等（含 `…Async` 孪生）返回 `List<T>`，
  跳过 `FuzzyHit` 包装，速度更快，适合不需要元数据的纯过滤场景。

`…Async` 调用可安全重叠。异步搜索进行中时变更或 `dispose` 会抛 `StateError`。

### 生命周期

| 方法 | 说明 |
|---|---|
| `dispose()` | 幂等；in-flight 时等完成再释放。可在 `State.dispose()` 中调用。 |
| `disposeAndWait()` | 同上但返回 `Future`，可 `await`。 |

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
  final hits = await corpus.fuzzyAsync(q, limit: 50);
  if (gen != _gen) return;           // 被更新的按键超越，丢弃旧结果
  setState(() => _hits = hits);
}
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
供浏览器和 Node.js 项目使用。相同的 `FuzzyCorpus` API，TypeScript 优先。

```ts
import { ffuzzyInitialize, FuzzyCorpus } from '@codejoo/ffuzzy';
await ffuzzyInitialize();
const corpus = FuzzyCorpus.strings(['src/main.rs', 'README.md']);
const hits = corpus.fuzzy('src', { highlight: true });
corpus.dispose();
```

## 许可

MIT —— 详见 [LICENSE](LICENSE)。
