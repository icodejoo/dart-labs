# @codejoo/ffuzzy

[English](README.md) | 中文

为 Web 提供的高性能排名模糊搜索 —— [ffuzzy](https://github.com/icodejoo/dart-labs/tree/main/ffuzzy) C 引擎的 WASM 移植版。

模糊搜索 + 编辑距离搜索 · TypeScript · 浏览器 + Node · ~36 KB gzip

## 安装

```sh
npm install @codejoo/ffuzzy
```

## 快速上手

WASM 模块由库内部管理——启动时调用一次 `ffuzzyInitialize()`，之后同步使用
`FuzzyCorpus`，API 与 Dart 版完全对齐（无需传模块句柄）。

```ts
import { ffuzzyInitialize, FuzzyCorpus } from '@codejoo/ffuzzy';

await ffuzzyInitialize();   // 启动时调用一次（WASM 实例化是异步的）

// 纯字符串
const corpus = FuzzyCorpus.strings(['src/main.ts', 'README.md', 'package.json']);
corpus.fuzzy('src').forEach(h => console.log(h.raw, h.score));
corpus.dispose();

// 任意对象 —— 命中携带原对象
const files = new FuzzyCorpus(myFiles, { stringOf: f => f.path });
const hit = files.fuzzy('src')[0];
hit.raw;  // 原始对象
files.dispose();
```

> 为什么要一次 `await`？浏览器禁止同步编译大于 4 KB 的 WASM 模块，所以引擎
> 必须异步初始化。初始化完成后，所有调用都是同步的。

## 搜索

`fuzzy` 是核心模式——这是 WASM 真正碾压原生 JS 的场景（比 fuse.js 快 8-55×）。
`substring` / `prefix` / `postfix`（别名 `suffix`）/ `exact` 走原生 JS 字符串操作
（不经过 WASM 边界），各带 `*Raws` 变体，跳过 `FuzzyHit` 包装、速度更快：

```ts
corpus.fuzzy('gems', { limit: 50 })     // 排名、评分、多字段
corpus.prefix('Super')
corpus.postfix('1000')                  // suffix() 是别名
corpus.exact('101024')
corpus.substring('ems')
corpus.fuzzyRaws('gems')                // T[] —— 跳过 FuzzyHit 包装
```

`fuzzy` 支持 fzf 风格操作符：`!term` 排除 · `^term` 强制前缀 ·
`'term` 强制子串 · `term$` 强制后缀。

### 编辑距离搜索 —— `approx()`

基于 Myers bit-parallel Levenshtein，容忍拼写错误、替换和换位——与 `fuzzy`
（子序列匹配）不同，它匹配与查询词编辑距离在 `maxDistance` 以内的项：

```ts
corpus.approx('iphoen')                  // "iPhone" —— maxDistance 按查询长度自动推算
corpus.approx('iphoen', 2)               // 显式指定 maxDistance
corpus.approxRaws('iphoen')              // T[]
```

`maxDistance` 省略时自动推算：≤2 字符 → 0，3–5 → 1，6+ → 2。

### 统一入口 —— `search()`

```ts
corpus.search('iphoen', { strategy: 'fuzzy' })      // 默认，等价于 fuzzy()
corpus.search('iphoen', { strategy: 'approx' })     // 等价于 approx()
corpus.search('iphoen', { strategy: 'fallback' })   // 先子序列，无结果再编辑距离
corpus.search('iphoen', { strategy: 'merge' })       // 两者都跑，子序列命中在前
corpus.searchRaws('iphoen', { strategy: 'merge' })  // T[]
```

### 双结果 —— `dual()`

单次 corpus 扫描跑两种算法，分桶返回：

```ts
const { fuzzy, approx } = corpus.dual('iphoen');
```

## 选项

```ts
import { FuzzyCorpus, FuzzyCase, FuzzyNorm, FuzzyScoring } from '@codejoo/ffuzzy';

const corpus = new FuzzyCorpus(items, {
  stringOf: item => item.name,
  options: {
    caseMatching: FuzzyCase.smart,    // 0=区分大小写 1=不区分 2=智能（默认）
    normalization: FuzzyNorm.smart,   // 0=不归一 1=智能变音符归一（默认）
    limit: 50,                        // 最多返回数（0=全部）
    highlight: false,                 // true 时填充 FuzzyHit.indices（默认 false）
    scoring: FuzzyScoring.fast,       // fast（默认）/ off（不排名）/ nucleo（高精度）
  },
  matchPaths: false,   // 将 '/' 视为路径分隔符
  preferPrefix: false, // 偏向靠前的命中加分
});
```

单次调用覆盖：

```ts
corpus.fuzzy('query', { limit: 10, highlight: true });
```

## 类型化对象搜索 —— `byKey` / `byKeys`

泛型 `T` 从 items 数组自动推断，`hit.raw` 完全类型化：

```ts
interface Game { gameId: string; gameName: string; platform: { id: string } }

// 单字段 — hit.raw 推断为 Game
const byName = FuzzyCorpus.byKey(games, 'gameName');
byName.fuzzy('gems')[0].raw.gameId;   // ✓ 类型为 string

// 多字段 — matchedKey 告诉你哪个字段命中
const corpus = FuzzyCorpus.byKeys(games, ['gameName', 'gameId']);
const hit = corpus.fuzzy('gems')[0];
hit.raw.gameName;   // ✓ Game
hit.matchedKey;     // 0 = gameName 命中，1 = gameId 命中

// 点路径访问嵌套字段（IDE 有自动补全）
const byPlatform = FuzzyCorpus.byKey(games, 'platform.id');
byPlatform.fuzzy('226')[0]?.raw.gameId;  // ✓
```

字段不存在或值为 `null`/`undefined` 时静默返回 `''`，不会报错。

## 多键搜索（拼音 / 罗马音）

```ts
import { FuzzyCorpus, FuzzyKey, FuzzyKeyKind } from '@codejoo/ffuzzy';

corpus.addKey(item, [
  FuzzyKey.kind('zhongguo', FuzzyKeyKind.pinyin),
  FuzzyKey.kind('zg',       FuzzyKeyKind.initials),
]);
```

变更：`add` / `addAll` / `addKey` / `update` / `removeAt` / `removeWhere` / `refresh` / `clear`。

## 命中高亮

搜索时传 `{ highlight: true }` 才会填充 `FuzzyHit.indices`（默认 `false` 以节省
C 端 Pass 2 开销）。

**方式 A —— `highlightHtml`**（便利函数，内置 HTML 转义，防 XSS）：

```ts
import { highlightHtml } from '@codejoo/ffuzzy';

const [hit] = corpus.fuzzy('src', { highlight: true });
element.innerHTML = highlightHtml(hit.raw, hit.indices);
// → '<mark>src</mark>/main.dart'
// 自定义标签：highlightHtml(hit.raw, hit.indices, { tag: 'b' })
```

**方式 B —— 原始码点位置**（用于 Flutter 或自定义渲染）：

```ts
import { fuzzyCodepointToUtf16 } from '@codejoo/ffuzzy';

const [hit] = corpus.fuzzy('src', { highlight: true });
const u16 = fuzzyCodepointToUtf16(hit.raw, hit.indices);
// 将 u16 偏移量应用到 DOM Range / TextSpan / Highlight API
```

## `using` 语句

```ts
using corpus = FuzzyCorpus.strings(items); // 离开作用域自动 dispose
```

## FuzzyHit 结构

```ts
interface FuzzyHit<T> {
  raw:             T;        // 命中的原始对象
  index:           number;   // 在语料中的插入序号
  score:           number;   // 匹配分（越高越好，仅同一次查询内可比）
  matchedKind:     number;   // 命中键的类型（FuzzyKeyKind）
  matchedKindCode: number;   // 原始整数 kind 值（内置 kind 与 matchedKind 相同，自定义 kind ≥ 100 时保留原值）
  matchedKey:      number;   // 命中的是该 item 的第几个键
  indices:         number[]; // 命中的码点位置 —— 仅 highlight:true 时有值
}
```

## 性能

基准测试语料：4886 条游戏名称（平均 15 字节 ASCII，`limit: 50`）。

### 与 fuzzysort、fuse.js 对比

| 数据量 | ffuzzy | fuzzysort | fuse.js | vs fuzzysort | vs fuse.js |
|------:|-------:|----------:|--------:|:------------:|:----------:|
| 4 886 条 | 120-220 µs | **19-103 µs** | 1.8-6.7 ms | 0.13-0.48× | **快 8-56×** |
| 9 772 条 | 240-415 µs | **32-193 µs** | 3.6-13 ms | 0.13-0.47× | **快 9-55×** |
| 24 430 条 | 0.6-1.1 ms | **92-695 µs** | 12-35 ms | 0.14-0.64× | **快 11-56×** |
| 48 860 条 | 1.4-2.8 ms | **238-2440 µs** | 18-75 ms | 0.14-0.88× | **快 7-57×** |

构建时间（一次性）：ffuzzy **2-9 ms** · fuse.js 2-20 ms · fuzzysort 5-27 ms

> fuzzysort 是纯 JS 库，直接操作 V8 原生字符串，无 WASM 边界开销，纯 ASCII 场景下更快。
> ffuzzy 在高命中率查询（如 `"sp"`，48k 条时：2.77 ms vs 2.44 ms）差距缩小，
> 对比 fuse.js 则在所有规模下均大幅领先。

### 功能对比

| | ffuzzy | fuzzysort | fuse.js |
|--|:------:|:---------:|:-------:|
| 速度（纯 ASCII） | ★★★ | ★★★★★ | ★ |
| 对比 fuse.js | **快 7-57×** | 约快 10× | 基准 |
| CJK / 变音符折叠 | ✅ | ❌ | △ |
| 多键搜索（拼音 / 罗马音） | ✅ `byKeys` | ❌ | ❌ |
| 类型化 `byKey<T>` / 点路径 | ✅ | ❌ | ❌ |
| Dart FFI（Flutter） | ✅ | ❌ | ❌ |
| 排名质量 | nucleo DP | 前缀偏向 | Bitap/Levenshtein |
| 编辑距离搜索 | ✅ `approx` | ❌ | △（Bitap） |
| 包体积 | ~36 KB gzip | ~8 KB | ~24 KB |

**选 ffuzzy 而不选 fuzzysort 的场景**：CJK 内容、拼音/罗马音转写、多字段搜索（`byKeys`），
或同时使用 Flutter/Dart 包。纯 ASCII 无 Unicode 需求时，fuzzysort 更轻量。

## 从源码构建

```sh
cd wasm
npm run build          # 快路：编译 src/ffuzzy-corpus.ts → dist/ffuzzy.mjs + .d.mts

# 重建 WASM 引擎（需要 Emscripten ≥3.x）：
npm run build:engine    # emcc 编译 src/*.c → src/ffz.mjs，然后自动 npm run build
npm run build:all       # 引擎 + build 一步到位
```

## 相关

- [pub.dev 上的 ffuzzy](https://pub.dev/packages/ffuzzy) —— Flutter / Dart 包
- [GitHub](https://github.com/icodejoo/dart-labs/tree/main/ffuzzy)

## 许可证

MIT
