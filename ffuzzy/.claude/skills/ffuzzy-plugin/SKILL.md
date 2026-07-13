---
name: ffuzzy-plugin
description: Use when developing, building, testing, or publishing the ffuzzy Flutter fuzzy-search plugin. Covers project layout, Dart API (native + web), C build/test workflow, wasm/npm package (TypeScript), shared test suite, and pub.dev / npm publishing.
---

# ffuzzy 插件开发指南

## 工程结构

```
ffuzzy/                         ← pub 包根（pub 包名 ffuzzy）
├── lib/
│   ├── ffuzzy.dart             # 条件 export 入口：native → ffuzzy_ffi.dart，web → ffuzzy_web.dart
│   └── src/
│       ├── ffuzzy_types.dart   # 公共类型（FuzzyHit、FuzzyOptions、FuzzyCase…）
│       ├── ffuzzy_corpus.dart  # 共享 corpus 基类（状态管理、全部公开方法、纯 Dart 回退搜索）
│       ├── ffuzzy_ffi.dart     # native 实现：dart:ffi → libffz.so/.dll
│       ├── ffuzzy_web.dart     # web 实现：dart:js_interop → WASM
│       └── ffuzzy_web_plugin.dart  # Flutter web 插件注册 stub（空 registerWith）
├── src/*.c                     # C 引擎核心
├── ffi/ffz_ffi.c               # dart:ffi ABI 胶合层
├── include/                    # C 头文件
├── android/ ios/ macos/ linux/ windows/  # 平台目录
├── example/                    # 演示 App（web + native 均可运行）
├── test/                       # 所有测试（Dart + C 文件合并于此）
│   ├── shared/
│   │   ├── spec.json           # ★ 共享行为规格（Dart 和 JS 都读这个）
│   │   └── api_surface.json    # ★ 公开 API 表面规格（维护方法名单）
│   ├── shared_spec_test.dart   # Dart 共享规格运行器
│   ├── api_parity_test.dart    # Dart API 表面验证
│   ├── corpus_mutation_test.dart
│   ├── bench_native_test.dart
│   └── *.c                     # C 单元测试
├── docs/                       # 文档（INTERNALS.md + superpowers/）
├── scripts/                    # 工具脚本
└── wasm/                       # npm 包 @codejoo/ffuzzy（见末节）
```

## Dart Web 支持

### 初始化（必须在 web 上调用）

```dart
// 在 main() 里调用一次，native 是空操作，web 加载 WASM 引擎
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ffuzzyInit(
    webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.8.0/dist/ffuzzy-fzf.mjs',
    // 或: webAssetsUrl: '/assets/ffuzzy-fzf.mjs'（需在 pubspec.yaml 声明 assets）
  );
  runApp(const MyApp());
}
```

- `webUrl`：CDN 或远程 URL（无 Flutter asset，节省 bundle 体积）
- `webAssetsUrl`：本地 Flutter asset 路径（离线可用，需 pubspec 声明）
- 两者都传时 `webAssetsUrl` 优先；native 两参数均忽略

### 条件导出机制

`lib/ffuzzy.dart` 的条件 export 决定加载哪个实现：
- **native**：`ffuzzy_ffi.dart`（dart:ffi → C 引擎，Isolate.run 异步）
- **web**：`ffuzzy_web.dart`（dart:js_interop → WASM，同步执行）

**注意**：web 端 `fuzzy()` 等方法是**同步的**（WASM 在主线程执行）；`asyncFuzzy()` 在 web 上是带 microtask 的同步调用，不经 Web Worker，大型 corpus 可能阻塞主线程。

**延迟初始化（corpus 在 `ffuzzyInit` 之前创建）**：同步方法（`search`/`fuzzy`/`approx`/`dual` 等）在 WASM 就绪前返回 `[]`；`async*` 变体（`asyncFuzzy`/`asyncSearch`/`asyncApprox`/`asyncDual` 等）会自动 await WASM 初始化完成再执行，所有 strategy（包括 `fallback`/`merge`）均支持此行为。

## 公开 Dart API（`package:ffuzzy/ffuzzy.dart`）

### ffuzzyInit

```dart
Future<void> ffuzzyInit({String? webUrl, String? webAssetsUrl})
```
native 空操作；web 加载 WASM 引擎。

### FuzzyCorpus\<T\>

**构造**
```dart
FuzzyCorpus<T>(items, {required String Function(T) stringOf, FuzzyOptions options,
                        bool matchPaths, bool preferPrefix, String? libraryPath})
FuzzyCorpus.strings(items, {…})
FuzzyCorpus.byKey(maps, field, {…})        // T = Map<String,dynamic>，按单字段搜
FuzzyCorpus.byKeys(maps, fields, {…})      // 跨多字段；hit.matchedKey = 命中字段下标
FuzzyCorpus.buildAsync(items, stringOf:, {…})  // 后台 isolate，不卡 UI
```

**增删改**
```
add / addAll / addAllAsync
addKey(item, List<FuzzyKey>)   # 挂多种转写键（拼音/罗马音/缩写）
update / removeAt / removeWhere / refresh([source]) / clear
dispose() / asyncDispose()
```

**搜索模式**（web 的 fuzzy 走 WASM，prefix/postfix/exact/substring 走纯 Dart）

**经典搜索模式**（均有 `*Raws`、`async*`、`async*Raws` 变体）

| 方法 | 说明 |
|------|------|
| `fuzzy` | 子序列匹配，支持 fzf 算符 `!`/`^`/`'`/`$` |
| `substring` | 连续子串匹配 |
| `prefix` | 前缀匹配 |
| `postfix`/`suffix` | 后缀匹配 |
| `exact` | 整串精确匹配 |

**统一入口 `search()`**（含 `searchRaws`/`asyncSearch`/`asyncSearchRaws`）

```dart
search(q, {SearchStrategy strategy, int? maxDistance, …})
// strategy: fuzzy(默认) | approx | fallback | merge
```

**编辑距离快捷方式 `approx()`**（含 `approxRaws`/`asyncApprox`/`asyncApproxRaws`）
- `maxDistance` 未传时按词长自动推算（≤2→0, 3–5→1, 6+→2）

**双结果 `dual()`**（含 `asyncDual`）
- 单次 corpus 扫描，返回 `FuzzyDualResult(fuzzy:[…], approx:[…])`

**选项覆盖**：每个方法均可传命名参数覆盖 `FuzzyOptions`（`caseMatching`/`normalization`/`limit`/`highlight`/`scoring` 等）。

### FuzzyOptions

| 字段 | 默认 | 说明 |
|------|------|------|
| `scoring` | `FuzzyScoring.fast` | `fast`（滚动DP）/ `off`（不排名）/ `nucleo`（全矩阵DP，精度最高） |
| `caseMatching` | `smart` | `respect`/`ignore`/`smart`（lowercase 查询=不区分，含大写=区分） |
| `normalization` | `smart` | `never`/`smart` |
| `parallel` | `false` | 多线程打分（native only） |
| `threads` | `0` | 0=自动（半核，上限8） |
| `limit` | `0` | 最多返回数（0=全部） |
| `highlight` | `false` | `true` 时触发 Pass 2，填充 `FuzzyHit.indices` |

### FuzzyHit\<T\>

| 字段 | 说明 |
|------|------|
| `raw` | 命中的原始对象 |
| `index` | 插入顺序下标 |
| `score` | 匹配分（同次查询内可比较） |
| `matchedKind` | `FuzzyKeyKind` 枚举（original/pinyin/initials/romaji/custom） |
| `matchedKindCode` | 原始整数 kind 值（custom kind ≥ 100 时用此区分） |
| `matchedKey` | 哪个键命中（0=original；`byKeys` 下等于 fields 下标） |
| `indices` | 命中字符码点下标（仅 `highlight:true` 有值，传 `fuzzyCodepointToUtf16` 用于高亮） |

### FuzzyKey / FuzzyKeyKind

```dart
FuzzyKey(text, {int kind = 1})        // kind 默认 1=pinyin
FuzzyKey.kind(text, FuzzyKeyKind.xxx)
// FuzzyKeyKind: original=0, pinyin=1, initials=2, romaji=3, custom=100
```

### 高亮

```dart
final hits = corpus.fuzzy('src', highlight: true);
final u16 = fuzzyCodepointToUtf16(hits.first.raw, hits.first.indices);
// u16 = UTF-16 偏移列表，用于构建 TextSpan
```

## Dart 编译速查

**只改 Dart**：
```bash
dart analyze lib/ test/ example/lib/
flutter test test/
```

**改了 C 源**：
```bash
# Windows
build_test.bat
# 或触发 CMake：flutter build windows
```

**环境要求**：SDK `^3.6.0`、Flutter `^3.24.0`（dart:js_interop JSArray.length/toDart 需 3.6+）

## 本机环境踩坑

- **NDK**：`android/build.gradle` 钉 `ndkVersion '26.1.10909125'`
- **JDK**：`flutter config --jdk-dir "C:\sdk\jdk\openjdk-21.0.5+11"`
- **Android 网络**：gradle.properties 加 `systemProp.javax.net.ssl.trustStoreType=Windows-ROOT`（本机配置，勿提交）
- **Emscripten**：emsdk 在 `C:\sdk\emsdk`；`npm run build:engine` 自动探测路径
- **`_keepAlive()`**：dart:ffi reachabilityFence 在本机失败，改用读实例字段代替

## 发布到 pub.dev

```bash
# 推荐：带预检查的发布流程（等价于 npm 的 prepublishOnly）
make publish
# 等价于：
dart run scripts/check_api_parity.dart   # 读 api_surface.json，验证 Dart 源码方法存在
flutter test test/api_parity_test.dart   # 逐方法 smoke 调用验证
flutter pub publish

# 仅检查 API 表面（不发布）
make check
```

## Git Hooks（lefthook）

每次 `git push` 自动检查 API 一致性（含 ffuzzy 文件的推送才触发，monorepo 友好）。

```bash
# 前提：安装 lefthook（全局，一次性）
npm install -g lefthook    # 或: brew install lefthook / scoop install lefthook

# 克隆后运行一次（在 dart-labs/ 根目录）
lefthook install           # 或: make install-hooks（在 ffuzzy/ 里）
```

配置文件：`dart-labs/lefthook.yml`（提交到 git，团队共享）。
推送时自动并行运行 `dart run scripts/check_api_parity.dart` 和 `node wasm/scripts/check_api_parity.mjs`。

---

## wasm/（npm 包 @codejoo/ffuzzy）

### 目录结构

```
wasm/
├── src/
│   ├── ffz-fzf.mjs          # ★ emcc 产物（子序列，默认）
│   ├── ffz-approx.mjs       # ★ emcc 产物（编辑距离）
│   ├── ffz-full.mjs         # ★ emcc 产物（两者）
│   └── ffuzzy-corpus.ts     # ★ 手写 TypeScript corpus 实现（唯一源）
├── dist/                    # tsdown 产出（提交到 git，npm 发布用）
│   ├── ffuzzy-fzf.mjs       # 子序列（~32 KB gzip）
│   ├── ffuzzy-approx.mjs    # 编辑距离（~22 KB gzip）
│   ├── ffuzzy-full.mjs      # 两者（~33 KB gzip）
│   └── ffuzzy-fzf.d.mts     # 自动生成 TypeScript 声明
├── scripts/
│   └── check_api_parity.mjs # ★ API 表面一致性检查（CI/发布前运行）
├── test/
│   ├── smoke.test.mjs       # 功能冒烟测试
│   ├── shared_spec.test.mjs # ★ 共享行为规格运行器（读 test/shared/spec.json）
│   └── api_parity.test.mjs  # ★ JS API 表面验证
├── build-engine.sh          # emcc → src/ffz-{fzf,approx,full}.mjs（慢路径，改 C 时跑）
├── tsdown.config.ts         # tsdown 配置（src/ffuzzy-corpus.ts → dist/）
├── tsconfig.json
└── package.json
```

### 构建流程

```
build-engine.sh (需 emcc)          → src/ffz-fzf.mjs     （默认，子序列）
                                   → src/ffz-approx.mjs  （编辑距离，FFZ_SUBSEQUENCE=0 FFZ_EDIT_DISTANCE=1）
                                   → src/ffz-full.mjs    （两者，FFZ_EDIT_DISTANCE=1）
npm run build  (tsdown + terser)   → dist/ffuzzy-fzf.mjs     （提交）
                                   → dist/ffuzzy-approx.mjs  （提交）
                                   → dist/ffuzzy-full.mjs    （提交）
                                   → dist/ffuzzy-fzf.d.mts   （类型声明，提交）
```

```bash
cd wasm
npm run build          # 快路：编译 TS corpus → dist/
npm run build:engine   # 慢路：重编 C → src/ffz-{fzf,approx,full}.mjs（需 emcc）
npm run build:all      # 全链路：engine + build
npm run check          # API 表面一致性检查
npm test               # build + check + node --test（全部测试）
npm publish            # prepublishOnly = build + check
```

### TypeScript corpus API（与 Dart 对齐）

JS 端与 Dart 端方法一致，差异说明：

| 类别 | Dart | JS |
|------|------|----|
| fuzzy 搜索 | ✅ | ✅（WASM） |
| prefix/postfix/exact/substring + Raws | ✅ | ✅（原生 JS 字符串操作） |
| `search(q, {strategy, maxDistance, …})` | ✅ | ✅（strategy: fuzzy/approx/fallback/merge） |
| `approx(q, maxDistance?)` | ✅ | ✅ |
| `dual(q, {maxDistance, …})` | ✅ | ✅ |
| `searchRaws` / `approxRaws` | ✅ | ✅ |
| Async 变体（asyncFuzzy 等） | ✅ | ❌（WASM 同步） |
| buildAsync / addAllAsync | ✅ | ❌ |
| asyncDispose | ✅ | ❌ |
| FuzzyHit.matchedKindCode | ✅ | ✅（与 matchedKind 同值） |
| highlightHtml | ❌ | ✅（JS 专有） |
| ffuzzyInit(webUrl:) | ✅ | ❌ → ffuzzyInitialize() |

**JS 初始化**：
```typescript
import { ffuzzyInitialize, FuzzyCorpus } from '@codejoo/ffuzzy';
await ffuzzyInitialize();
const corpus = FuzzyCorpus.strings(['src/main.rs', 'README.md']);
const hits = corpus.fuzzy('src', { highlight: true });
// hits[0] = { raw, index, score, matchedKind, matchedKindCode, matchedKey, indices }
element.innerHTML = highlightHtml(hits[0].raw, hits[0].indices);
corpus.dispose();
```

**Flutter web 加载方式**：
```dart
// CDN（推荐，节省 bundle 体积）— 子序列默认
await ffuzzyInit(webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.8.0/dist/ffuzzy-fzf.mjs');

// 两种算法均需时用 full 变体
await ffuzzyInit(webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.8.0/dist/ffuzzy-full.mjs');

// 或本地 asset（需 pubspec.yaml assets 声明，离线可用）
await ffuzzyInit(webAssetsUrl: '/assets/ffuzzy-fzf.mjs');
```

## 测试套件维护

### 文件关系

```
test/shared/api_surface.json   ← ★ 唯一入口，维护公开方法名单
test/shared/spec.json          ← ★ 行为规格，所有测试用例（Dart + JS 共读）

Dart 侧：
  test/api_parity_test.dart    ← 读 api_surface.json，逐方法 smoke 验证
  test/shared_spec_test.dart   ← 读 spec.json，行为断言

JS 侧：
  wasm/test/api_parity.test.mjs   ← 读 api_surface.json，验证 exports + 实例方法 + FuzzyHit 字段
  wasm/test/shared_spec.test.mjs  ← 读 spec.json，行为断言
  wasm/scripts/check_api_parity.mjs ← 对比 api_surface.json vs dist/ffuzzy.d.mts（CI 用）
```

### 当 Dart API 发生变化时

| 情景 | 需要修改的文件 |
|------|--------------|
| 新增方法 | `api_surface.json`（加方法名）+ `wasm/src/ffuzzy-corpus.ts`（实现）+ `spec.json`（加测试用例）+ `api_parity_test.dart`（加 smoke call） |
| 删除方法 | `api_surface.json` 删方法名（两侧测试自动捕获缺失） |
| 改变行为 | `spec.json` 更新对应用例 |
| 忘记更新 | `npm test` 的 `check_api_parity.mjs` 在发布前报错阻止 |

### 运行测试

```bash
# JS 端（全量）
cd wasm && npm test

# JS 端（仅 API 检查）
cd wasm && npm run check

# Dart 端（需先编 native 库）
flutter test test/api_parity_test.dart
flutter test test/shared_spec_test.dart
flutter test test/                       # 全量
```

## C 引擎要点

- `ffz_ffi_filter_ex2`：带 scoring 参数的搜索（highlight 模式调此）
- `ffz_ffi_filter_raws`：跳过 Pass 2（不计算命中字符位置），速度更快
- 经典五种模式（fuzzy/substring/prefix/postfix/exact）统一走 `_filter_ex`，由 `mode` 参数区分
- `highlight:false`（默认）→ `filterRaws`；`highlight:true` → `filterEx2`
- 编辑距离（`approx`）走独立 FFI 调用（Myers bit-parallel Levenshtein），需 `FFZ_EDIT_DISTANCE=ON`
- `FFZ_SUBSEQUENCE`（默认 ON）与 `FFZ_EDIT_DISTANCE`（默认 OFF）可独立控制，两者不可同时 OFF

## 发布 npm

```bash
cd wasm
npm publish   # prepublishOnly: build + check_api_parity
```

- `dist/` 所有文件提交到 git，npm publish 无需重新 build（但 prepublishOnly 会跑一遍确保最新）
- `src/ffz-{fzf,approx,full}.mjs` 提交到 git（避免每次发布都需要 emcc）
- 改了 `src/ffuzzy-corpus.ts` 后：`npm run build` 重新生成 dist/ → 提交
- 改了 C 源后：`npm run build:all` → 提交 `src/ffz-*.mjs` + `dist/`
