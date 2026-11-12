---
title: axp 重构复盘与 dioman 参照评估
status: active
updated: 2026-10-31
summary: 对照 axp（b04d25a）的架构、落地、测试与修改记录，总结重构要点、踩过的坑和 TS/axios → Dart/Dio 映射，评估 dioman（714c1c6）现状并给出独立的重构建议，供与现有方案交叉对比。
---

# axp 重构复盘与 dioman 参照评估

## TL;DR

- axp 的骨架（洋葱管线、固定阶段、归一化响应、失败抛 R / bug 抛原异常）在 10-28 一天内定型并落地，没有推翻过；之后两天的返工集中在三处：**响应契约一天三版**、**并发与生命周期**（auth、loading、cache 异步）、**状态作用域**（按插件实例 → 按资源）。
- dioman B8（10-29 12:18）已经吸收 axp 终审的必修 1–9 和 D1（share 撤回、key 含 baseURL、旧刷新不清新会话、refreshTimeout、可取消等待、一次性体等），并且已有 I8/I9 不变量。B8 之后 axp 的 201d192、ADR 0003、4ad9182、795783e 基本没有进 dioman。
- 最该先补的是生命周期与作用域：auth 会话按客户端分（父子客户端共用 TokenManager 会并发刷新两次）、本地无 token 每请求都通知、`_Auth` 没有 `dispose`；loading 按客户端计数；`extend()` 新建 `Dio` 会丢掉拦截器、`httpClientAdapter`、`transformer`（证书固定之类会悄悄失效），比 axp 的 D3 更重。
- 契约层面不建议照搬 0002 "去掉 kind"：Dart 枚举 + 穷举 switch 是一等能力，dioman 的 `DiomanKind` 已含 breaker/offline，正好补上 axp 终审 §7 指出的扩展缺口。真正要堵的是自定义 `create` 能改写内核类别和 `ok`（`response.dart:185` 不校验）。
- 0003 的动机在 Flutter 同样成立：失败结果会被 Riverpod/Bloc/上报库长期持有，`raw.requestOptions` 里还有 Authorization。建议 Dart 化分两步：先让失败结果和内存缓存不再常驻 raw/error，再决定要不要瘦身 `request`。
- 单轮实测（本机负载约 27%）：13 个插件全装、缓存未命中 118.6µs，约为裸 Dio 的 4.4 倍；axp 9 个插件约 3.5 倍（B6 额外开销 2.51 倍 B1）。插件组合和运行时都不同，只看量级，但插件侧热点集中在 source 段这一点比较明确。key 用排序后的 `jsonEncode`、字节体整段 base64 写进 key、每次补丁全量复制 `RequestOptions` 是首批嫌疑；按 axp 的交错 A/B + 保留门槛做，别再出"试后撤回"。
- 所有建议都在 `^3.5.0` 内可做，不需要上调 SDK 下限。管线改动仍在 CHANGELOG 的 Unreleased 段，破坏性调整现在成本最低。待拍板 10 项见 §8。

## 终审更正（主会话，2026-10-31）

本报告是交叉对比的输入，正文保留原样。最终结论以 [第二轮方案](../design/pipeline-round2-plan.md) 为准。主会话逐条终审后的更正如下：

- **S2 / Q6 误报**：share 超时撤回维持 dioman 现状。dioman B8 关掉了 end/race 的 Dio 阶段计时，只按订阅预算计时，超时即调用方放弃；axp 保留了 axios 超时，两边计时模型不同。
- **K9 前半误报**：字节体 key 里的 base64 是 B8 防 32 位哈希碰撞加的无损校验，不能去掉。
- **T3 误报**：撤回矩阵已是 24 格（`test/combo/b8_share_withdrawal_test.dart`）。
- **CA3 改判**：缓存命中的 `request` 用发出那一次，是现有方案的明文口径，不是缺陷；最终仍在 R3 改。
- **Q1、Q2 已被拍板覆盖**：用户 2026-11-03 决定完全对齐 axp 0002，kind 改为内核私有失败标记，status 只表示 HTTP。本报告里"保留公开 kind、默认映射逻辑状态"的建议不再采用。
- **Q10 升级**：pub.dev 上 0.7.2 带 `platform:web`、`is:wasm-ready`，旧版 lib 不 import `dart:io`，这一项升为发版前必修。
- **口径**：§6.4 N1 的性能数字只能当量级参考（单轮、有负载，B6 门槛至今没结论）；测试数以 B8 运行时的 5588 条为准，375 是静态声明数。

## 1. 范围与依据

### 1.1 基线

| 项目 | 基线 | 说明 |
|---|---|---|
| axp | codejoo `b04d25a`（2026-10-30 13:29，`git log -1 -- apps/axp`） | `src/` 最后一次改动是 `8718f82`（10-30 11:15），之后只有 accept 执行器；工作区干净。`package.json` 版本 0.2.0，未发 npm，npm 上最新为 0.1.0 |
| dioman | dart-labs HEAD `46bcc5d`；`dioman/` 最后一次改动 `714c1c6`（B8，10-29 12:18） | `pubspec.yaml` 0.7.2、`sdk: ^3.5.0`、唯一依赖 `dio: ^5.0.0`；洋葱管线改动全部在 CHANGELOG 的 Unreleased 段 |
| 本机 | Dart 3.13.0、Node v24.11.0、Windows 10 19045 | 下文所有实测都在本机 |

两边节奏几乎一样快：axp 从方案定稿 `ced6d7c`（10-28 13:00）到 B7 收尾 `3a916c9`（10-29 00:30），之后终审修复和契约修订一直到 10-30 11:15；dioman 从方案 `a6a8d18`（10-29 00:43）、B0 `24b1571`（01:03）到 B8 `714c1c6`（12:18）。

### 1.2 读了什么

| 类别 | axp 文档 |
|---|---|
| 架构（通读） | `ARCHITECTURE.md`、ADR `0001`/`0002`/`0003`、`docs/design/core-architecture.md`、`plugin-spec.md` |
| 落地（通读） | `implementation-plan.md`、B0 基线、B1、B3、B4、B5、B6 报告、`2026-10-28-acceptance-pipeline.md` |
| 测试（通读） | `test-plan.md`、`docs/guides/test-layers.md`、`accept/mapping.md`、`e2e/README.md` |
| 修改（通读） | `2026-10-29-final-review.md`、`2026-10-27-codex-full-review.md`、`CHANGELOG.md`、`migrating-to-pipeline.md`（TL;DR、终审后变化、§9、检查清单）、`.claude/skills/codejoo-axp/SKILL.md` |
| 略读 | B2 报告（§6 取舍、§7 修复轮、方案 A1、精简轮）、`reference/pipeline-migration/README.md`（计数、删除机制、终审裁决、存疑）；大文件只 grep "存疑/撤回/误报/假通过" |
| 源码核对 | `src/pipeline.ts`、`context.ts`、`client.ts` 全文；`plugins/auth.ts`、`loading.ts`、`share.ts`、`transport.ts` 的关键段 |
| 提交 | 全部 122 个提交标题；重点看 `a47a5d9`、`4bef080`、`83ba333`、`201d192`、`28e869a`…`ebfacda`、`f3afa56`、`ce22a43`、`4ad9182`（含 transport diff）、`795783e`、`8718f82`、`b04d25a`、`4855ab1` |

dioman 只读了允许的范围：`lib/` 全部核心文件和全部插件、`test/` 结构与夹具、`benchmark/`、`example/`、`README*.md`、`CHANGELOG.md`、`docs/guides/` 三篇、`pubspec.yaml`；另看了 `714c1c6` 的 `--stat`（只看改了哪些 lib/test 文件）。

### 1.3 自己动手核实的

| 动作 | 结果 |
|---|---|
| dart2js / dart2wasm 编译一个调用 `DiomanResponseFactory().normalize` 的探针（文件和产物都在 scratchpad，借 dioman 现有 `package_config.json`） | 两者都编过；dart2js 产物在 node 下运行输出 `DiomanKind.internal 0`。即 `response.dart:1` 的 `import 'dart:io'` 在 3.13 下不阻断 Web 编译 |
| `dart run benchmark/pipeline.dart` 单轮 + `benchmark/pipeline_profile.dart` | 见 §2.6、§6.4；只写 stdout |
| axp `dist/` 用 Git Bash `gzip -9` 实测（dist 构建于 10-31 07:54，晚于 src 最后改动） | `./min` 15,341 字节；`dist/esm` 34 个 `.mjs` 逐个压缩求和 63,564 |
| axp 本地 `accept/.report/`（gitignore，只读文件） | 10-30/31 有多轮连线上 testkit 的结果，最新 2210/40/442，见 §4.6 |
| `npm view @codejoo/axp version` | 0.1.0 |
| pub.dev 查询 dioman 版本与平台标签 | 本机 curl 报 SSL 错误（exit 35），未核实 |

### 1.4 刻意没读的

dioman 的 `docs/decisions/`、`docs/design/`、`docs/reports/`、`docs/reference/`、`docs/archive/`、`docs/status.md`、`.claude/skills/dioman/`。下文对 dioman 的判断全部来自代码、测试、CHANGELOG 和 guides，没有参考现有方案。

## 2. axp 重构要点

### 2.1 骨架

一次调用就是一个逻辑请求，从外到内穿过五个阶段，最内层调用户的 axios 实例；传输边界把响应或异常判定成 `R`，链里只流转 `R`，`next()` 永不 reject；最外层落定（`ARCHITECTURE.md` §1、§3）。

| 层 | 内置插件（外→内） | 语义 |
|---|---|---|
| settle（内核） | — | `R` → data / 抛 `R` / 抛原始异常，每个逻辑请求一次；落定后清空原生槽（`client.ts:27-59`） |
| outer | loading → notify | 每个逻辑请求进出一次，看到最终 `R` |
| prepare | repath → filter | 请求整形，只跑一次 |
| attempt | retry | 重试边界，往里每次尝试都重跑；自定义插件默认阶段 |
| credential | auth | 每次尝试注入 token，401 刷新后重放 |
| source | mock → share → cache | 结果来源，可短路 |
| transport（内核） | — | `validateStatus: () => true`，响应工厂判定，打品牌和失败标记 |

envs 只有 `setup`，不进链。排序规则：阶段固定；同阶段 `pre` 自定义 → 内置 → `post` 自定义；重名抛错；只在 `createAxp`/`use`/`eject` 时编译；`inspect()` 看顺序（`ARCHITECTURE.md` §4）。

### 2.2 契约演变：0001 → 0002 → 0003 → 架构评审

| 时间 | 文档 / 提交 | 定了什么 | 为什么 | 后来被谁改 |
|---|---|---|---|---|
| 10-27 | Codex 全量 review「待优化」O5 | 建议加 `statusOf(response)`，auth/retry/notify 统一读它 | 业务码风格下插件只看 HTTP，执行器在替 axp 补适配 | 先被 0001 放大，后被 4ad9182 原样加回 |
| 10-28 13:00 | ADR 0001（`ced6d7c`）+ 核心架构 N1–N13 | 洋葱管线；具名阶段；归一化进内核，拆判定与落定；`next()` 不抛；`IAxpResponse` + 默认类；**kind 公开、内核推导逻辑状态、业务风格零适配**；不设错误类 | 旧版靠拦截器/adapter 协作，状态靠 WeakMap、Symbol 袋、字符串键三处保活 | D3/D5 被 0002 取代，D4/D6 的 `r.error` 被 0003 取代，N11 被 0003 取代 |
| 10-29 14:33 | 终审 + ADR 0002（`83ba333`、`faa80ff`） | 必需字段只留 `ok`、`status`（HTTP）、`code`、`data`；kind 改内核私有失败标记（`failureOf`，工厂返回后写入并强制 `ok=false`）；撤回逻辑状态和"零适配"；`envelope` 删除，改 `parse`/`type`/`create`；key 精简；cache store 异步 + 快照；`retryAfterMax` 60s；`refreshTimeout`；`extend({axios})` | 用户"三次拍板"：不让使用者填内部枚举；库不猜后端协议；契约要精简（0002 背景） | 可选字段、完整 request、`failureOf` 只给 type/reason 的条款被 0003 取代 |
| 10-29 15:59–17:48 | ADR 0003（`28e869a`、`38adb57`、`ada461c`、`7e476de`、`a9d90b3`、`ebfacda`） | 原生响应和异常挪进 `ctx.native` 单槽，落定清空并封闭；请求级 `raw: true` 才把 raw/error/request 不可枚举地附到副本；`R.request` 只剩 `{method,url}`；响应类回调末位加 `ctx`；notify `stringify` 必传；cache 不存 internal/cancel；Retry-After 作为私有小事实随 `R` 走 | 失败的 `R` 会被 Sentry、TanStack Query 长期引用，挂着 AxiosError 和完整请求会拖住内存；不可枚举解除不了引用（0003 背景） | — |
| 10-30 10:29 | 架构评审修复（`4ad9182`） | 加回客户端 `statusOf` 与 `ctx.statusOf`（默认等于 HTTP）；auth 会话按 TokenManager 共享、loading 按回调共享；请求选项三层合并；key 并入 `responseType`；`throws:false` 返回按 `ok` 可辨识的 `AxpResult`；断流归 network；`next()` 遇取消短路；**传输层不再克隆请求体，debug 下指纹检测**；导出插件工具；`./min` 门槛放到 15,401 | 父子客户端双刷新、双 spinner；业务风格逐项配置太繁 | — |
| 10-30 10:55 | `795783e` | loading 延迟隐藏窗口交接时转移归属 | 共享后 A 的残留占用会截断 B 的 `delayClose` 并持有回调 | — |

一句话：`statusOf` 走了一整圈——O5 提出，0001 把它泛化成"内核逻辑状态"，0002 撤回泛化，4ad9182 又把最初那个 opt-in 的 `statusOf` 加回来。

### 2.3 插件与内核服务

| 名称 | 位置 | 要点 | 默认值变化 |
|---|---|---|---|
| 归一化 | 内核 | 默认 `parse` 读 code/data/message；默认成功 = 2xx 且 code 为 0 或 `'0000'`；失败类别表（cancel/timeout/parse/network/internal/auth）由内核写（`core-architecture.md` §6） | — |
| key | 内核 | FNV 双车道流式哈希、类型标签、长度分帧；按 `buildFullPath` 并入 baseURL；含 params、有体方法含 data、含 responseType；二进制 ≤64KiB 按内容；不可哈希返回 null；只剩 `scope`（`plugin-spec.md` §1.2，`key.ts:109-111`） | 删 ignores/sample |
| 取消 | 内核 | 每个逻辑请求一个 AbortController，联动用户 signal；`cancelAll`/`pending`；`cancelIfAborted`/`waitAbortable` | 删 `axpCancel` |
| 日志 | 内核 | `debug: true \| AxpLogger`，关闭时 `NO_LOG` 空实现 | 删 `axpLogger` |
| loading | outer | 进入 +1、finally −1；按回调共享计数（`loading.ts:41`），每客户端记自己的占用；延迟隐藏窗口记归属方 | 覆盖 token 刷新等待 |
| notify | outer | `stringify(r, ctx)` 必传；内核先过滤成功、取消、silent；internal 交给使用者 | 无默认文案 |
| repath / filter | prepare | 生成新对象经 `next(patch)` 交内层；filter 装上即生效 | filter 默认生效 |
| retry | attempt | 六级判定；`statusCodes` 读 `ctx.statusOf`；Retry-After 超 `retryAfterMax` 不重试；`canReplay` | `max: 2`、指数退避、`delayMax: 10s` |
| auth | credential | 五动作；单飞刷新 + `refreshTimeout`；会话（单飞、过期标记、无 token 通知）按 TokenManager 放模块级 WeakMap，带持有者计数（`auth.ts:43`、`:159`、`:308`） | 删 `canRefresh` |
| mock | source | 探测 `next({ url, cache:false, share:false })`，`fallbackWhen` 再走真实接口 | 默认关 |
| share | source | start/end/race；end/race 里"自己 signal 引起的 cancel"才算撤回，超时照常参与（`share.ts:178`、`:201`） | 新增 `methods` |
| cache | source | 快照存储，命中经工厂重建并绑定当前请求；新鲜度屏障；异步仓等待可取消；不存 internal/cancel | 只缓存 GET/HEAD |

### 2.4 客户端 API

| 维度 | 现行写法 |
|---|---|
| 构造 | `createAxp<S, R>({ axios, plugins, response, key, reject, debug, statusOf })` |
| 调用 | `api.get(path, 方法级)(payload, 调用级)`，三层合并：方法级 < payload < 调用级 |
| 返回形态 | 默认 data；`wrap:true` → `WithData<R,D>`；`throws:false` → `AxpResult<R,D>`；`raw:true` 隐含 wrap，返回 `WithNative<WithData<R,D>>`；internal 一律抛原始异常（`ARCHITECTURE.md` §7） |
| 生命周期 | `use`、`eject`、`plugin(p)`、`inspect`、`extend(overrides, { plugins, axios })`、`cancelAll`、`pending`、`dispose` |
| 判别 | `api.isResponse(e)`、`api.isCancel(e)`、`failureOf(r)`、`nativeOf(e)` |
| 插件接口 | `{ name, stage, enforce, enable, setup \| handle \| taps }`；`setup` 返回 `{ handle, taps, api, dispose }` |

### 2.5 关键原语

| 原语 | axp 做法 | 出处 |
|---|---|---|
| 请求不可变 | 中间件不改 `ctx.request`，`next(patch)` 浅合并，`undefined` 表示删除；同层两次 `next()` 拿同一基准，重发天然干净 | `context.ts:47-55` |
| 取消 | 逻辑请求级 signal；每次 await 后 `cancelIfAborted`；`next()` 派生前已中止直接返回 cancel | `pipeline.ts:108`、`context.ts:296` |
| 超时 | 只有 axios 的阶段超时；share start 把首发的 axios timeout 置 0，交给订阅者自己的计时器；**没有逻辑请求总截止时间** | B4 §6 #3；终审 §7 |
| 重放 | `markReplayable()` 声明，`canReplay()` 检查一次性体，传输层对已发送的流兜底生成 internal | `context.ts:249-272` |
| 状态 | `stateKey<T>()` 是 Symbol；跨请求状态按资源作用域：cache/share 按客户端，auth 按 TokenManager，loading 按回调 | `ARCHITECTURE.md` §8 约定 1 |
| 原生数据 | `ctx.native` 单槽 `{for, raw, error, settled}`，`nativeFor(r)` 严格配对，落定清空并封闭，迟到写入被拒 | `context.ts:210-248` |
| 失败事实 | 不可枚举 `AXP_FAILURE`，工厂返回后写入并强制 `ok=false` | 0002 |

### 2.6 性能与体积手段

| # | 手段 | 结果 |
|---|---|---|
| P1–P3 | 链在装卸时编译；固定形状上下文、无补丁复用；key 惰性按 request 缓存 | 0/3/8 层直通中间件每层约 0.1µs（B1 §5.x） |
| P4 | 传输层零拷贝，debug 下指纹检测原地修改（4ad9182 之前是按需 `structuredClone`） | `transport.ts:11`、`:97` |
| P5–P7 | 强制放行状态码、不构造 AxiosError；失败直接抛 R；不包装 transformResponse | — |
| P8 | 缓存惰性过期 + 节流清扫，同步仓快路径 | 缓存命中最小 11.99 → 9.71µs（终审 §10.3） |
| P9 | 入口合并一次 defaults（方案 A1），差量交给 axios | 无插件固定多约 7–10µs（B6 §5.3） |
| 全插件 | — | B3 额外开销中位 4.26 → 2.51 倍，降 41%（B6 §5.3） |
| 体积 | `./min` gzip -9 门槛不大于基线 | 13,080 → 12,975 → 14,018 → 14,677 → 门槛 15,401；本次实测 15,341 |

## 3. axp 的落地方法：哪些起作用，哪些成了负担

| 方法 | 做法 | 起作用的地方 | 成了负担的地方 | 出处 | 对 dioman |
|---|---|---|---|---|---|
| 方案先行 | 10-28 13:00 一次产出 ADR、架构、插件规格、测试方案、实施计划 | 每批有对照基准，Codex 偏离能被识别（B3 擅自加的入口 `isExpired()` 被删） | 方案没回答"响应对象谁写、谁持有多久、业务码谁负责"，结果一天三版 | `implementation-plan.md` §5；0002/0003 背景 | 方案阶段加"契约四问"（§4.1 A1） |
| 小批次 + 后期并行 | B0–B7 线性；提速后 B3/B4、B5a/B5b 并行 | 每批可终审、可回退 | 跨批交互只能合并后测；并行批次让 bench 互相污染（B4 §5 疑似 B3 并行） | `implementation-plan.md` §2；B4 §5 | 共用 bench 或会清产物的批次不并行 |
| Codex 实现 + Claude 终审 | 每批 Codex 自审一轮，主会话逐条对照规格终审 | 终审期双路审查互补：Codex 没发现必修 1/2/4/6 和 D1–D3，主会话没发现 Codex 的 1–5 | Codex 三次中断（B1 容量不足、B3 沙箱进程失败、B2 终端 `CreateProcessAsUserW` 拒绝），接手要重新核对 | 终审 §5；B1 §10；B3 §1；B2 §7.4 | 保持双路；派发时写好中断交接清单 |
| 六层测试 + `[API id]` | unit/rule/boundary/combo/integration/acceptance，一个行为只在最低层测一次 | 用例可定位、可统计 | id 漂移：225 个 API id 里 120 个没有 rule、142 个没有 boundary、71 个零命中 | 终审 §6.2 | dioman 的矩阵闸门（G0–G5）和三档可信度比这个强，保持 |
| 不变量 + powerset | I1–I7；9 插件 512 子集 × 9 流程 = 4620 条 | 变异"share 离开时不摘 abort 监听"打挂 powerset 1920 条（I3） | 不变量只查账不查归属；I7 在 powerset 里基本空转（唯一 POST 不在默认方法里） | B5 §1；终审 §6.1 | dioman 已有 I1–I9 和 `bodyReplay` 流程 |
| 变异验证 | 改坏 src 确认用例会挂 | 证明新用例有牙齿（B3 §4、B5 变异表） | 手工、零散 | B3、B5 | dioman 有 `tool/pipeline_b*_mutations.py`，保持 |
| 迁移台账 | 836 处声明 = keep + change + drop，40 条存疑终审裁决 | 旧行为一条不丢 | 630KB 映射文档；部分裁决后来被推翻（"克隆失败回退原引用"） | `pipeline-migration/README.md` | 只在大迁移时做，完成即归档 |
| 覆盖率门槛 | 全局行 95/分支 90/函数 95，内核四文件分支 100%，实际全 100% | 逼着删掉不可达分支 | 给了虚假的安全感：9 项必修全部躲过 100% 覆盖和整轮验收 | 终审 TL;DR、§6.1 | 别把覆盖率写进完成定义的核心 |
| 黑盒验收矩阵 | testkit 2692 格，真实服务 + netem | 并发、网络类问题；跨语言共用场景 | 场景形状规整；执行器白名单漏登记让"跳过"被当成"缺能力"；执行器配置 bug；共享旧实例可能假通过 | 验收报告 §3.3；终审 §9、§10.2 | 跑前核对服务二进制版本和能力登记 |
| 性能门槛 + 交错 A/B | 3 轮、10% 稳定口径；机器有负载时交错旧/新各三轮 | 负载下仍能下结论 | 门槛事后改写（A1 调 B2/B6）；19 个 A/B JSON 入库 | B6 §5；终审 §7 | 门槛和保留阈值先定 |
| 体积门槛 | `./min` gzip -9 不大于基线 | 逼出精简（去掉 `#` 私有字段降级代码） | 三次放宽 | B6 §6；`test-plan.md` TL;DR | 不适用 |
| 文档同步 | B6 统一定稿；ADR 带"取代"条款 | 决策可追溯 | 文档量大（所列文档合计约 2.2MB），多处落后于 4ad9182（§4.6 F5） | — | 文档少而准，改契约时同一提交改 skill 与迁移指南 |

## 4. 要规避的问题

### 4.1 契约与决策反复

| # | 现象 | 根因 | axp 怎么修 | 教训 | 出处 |
|---|---|---|---|---|---|
| A1 | 响应契约 10-28 定稿后，10-29 14:33（0002）、15:59（0003）、10-30（4ad9182）连改三次；执行器、e2e、文档每次跟着迁，`ada461c` 带着 6 个已知类型错误提交 | 方案只从"插件要读什么"设计响应对象，没回答谁写字段、谁持有对象多久、默认对哪种后端友好 | ADR 带"取代"条款；f46d394、a91ccd9、f3afa56 三轮迁移 | 动工前对每个字段过一遍"谁写 / 谁读 / 谁持有多久 / 默认适配谁"；把内核事实与业务转换的边界先定死 | 0002 背景；0003 背景；终审 §4；`ada461c` 说明 |
| A2 | `statusOf` 提出 → 被泛化成内核逻辑状态 → 撤回 → 原样加回 | 把一个 opt-in 钩子扩成默认行为，默认值绑定了某种后端约定 | 4ad9182 加回 opt-in，`r.status` 保持 HTTP | 泛化前先问"默认值对谁不友好"；朴素方案常常是对的 | O5；0002 TL;DR 第 4 条 |
| A3 | 使用者可提供 kind，填错会影响重试、刷新和 bug 透传 | 内核事实开放给扩展点 | 0002：失败标记内核私有，工厂返回后写入并强制 `ok=false` | 内核事实只能内核写，扩展点只给业务转换 | 0002 决定 |
| A4 | 被抛出的 R 拖住 AxiosError、原始响应、完整请求 | 默认类挂原生对象；不可枚举不解除引用 | 0003：`ctx.native` 单槽，落定清空；`raw:true` 才附到副本 | 失败对象会被外部长期持有，默认要轻 | 0003 背景 |
| A5 | `extend` 语义三变：10-27 #17"不带插件" → N12 默认继承 → D3 发现丢拦截器 → F 批纠正 README"把 `api.axios` 传给 extend"的错误建议 | 派生客户端没列清"复制什么、共享什么、丢什么" | `extend(overrides, { axios })` + 警告 | 派生语义写成表，连同警告一起进 README | review #17；核心 N12；终审 D3、§9 F |
| A6 | 请求体克隆两次改口：R2-1 按需 `structuredClone`、迁移总表裁决"克隆失败回退原引用"，4ad9182 改成零拷贝 + debug 指纹 | 安全与性能的取舍没在方案阶段拍板 | 现行：约定转换器不原地改，debug 告警 | 显式拍板并写进不变量 | B3 §3；迁移总表终审裁决；4ad9182 transport diff |
| A7 | 体积门槛三次放宽：13,080 → 14,018（待定）→ 14,677 → 15,401 | "不退步"门槛 vs 终审持续加功能 | 每次由用户确认放宽 | 门槛跟功能范围绑定，范围一变先改门槛 | B6 §6；终审 §10.4；0003 代价；`test-plan.md` TL;DR |

### 4.2 并发与生命周期

| # | 现象 | 根因 | axp 怎么修 | 教训 | 出处 |
|---|---|---|---|---|---|
| B1 | 异步 `onFailure` 期间调用方取消，路由结果回来仍弹 Deny/Expired 通知 | await 之后没重查 | 等完先查 `aborted` | 每个 await 后重查取消 | B3 §9 |
| B2 | 异步 `ready` 期间 token 被替换，快照记了旧 token，401 被误路由，重放后直接判过期 | 快照取早了 | ready 前后比对 token，最多重做 3 次，记实际注入的 token | 快照取"真正用到的值" | B3 §9 |
| B3 | 刷新成功后、重放前用户登出，重放无凭证发出 | 凭证检查只在循环外 | 检查挪进循环 | 重放是新的一次发送，入口检查要重做 | B3 §9 |
| B4 | 上一轮刷新失败清掉刷新期间新登录的 token，并误发过期通知 | 失败处理不看会话是否已变 | 刷新开始记快照，失败时 token 已变就不判过期 | 失败回调先确认世界没变 | 终审必修 3 |
| B5 | `onRefresh` 经同一客户端发受保护请求，刷新排队等它自己 | 单飞刷新的重入 | README 约束 + `refreshTimeout` 30s 兜底 | 单飞类原语要有超时兜底和重入说明 | 必修 4 |
| B6 | `ready`/`onFailure` 挂起时取消无效；已取消请求还能命中缓存返回 ok | 普通 await；await 后不重查 | 可取消等待；命中前查一次 | 同 B1 | 必修 7、8 |
| B7 | dispose 之后在途刷新迟到失败仍清会话、发过期通知 | 卸载没让迟到回调失效 | 201d192；最后一个持有者卸载后迟到失败为空操作 | 卸载 = 让所有迟到回调变成空操作 | 201d192；`plugin-spec.md` §5 |
| B8 | 父子客户端、共用同一 TokenManager 的客户端各刷新一次、各通知一次 | 状态作用域按插件实例 | 4ad9182：`IAuthSession` 按 TokenManager 放模块级 WeakMap，持有者计数 | 状态跟它代表的资源走 | 4ad9182；`auth.ts:43` |
| B9 | 本地无 token 时每个受保护请求都通知一次 | 去重只覆盖 401/刷新失败那条路径 | 会话 `notified` 标记，写入新 token 后复位 | — | B3 §7 #1 → 4ad9182 |
| B10 | 父子共用一个 spinner 回调时显示、隐藏各两次 | loading 状态按客户端 | 按回调共享 + 每客户端记占用 | — | 4ad9182 |
| B11 | 共享后，A 的延迟隐藏窗口被 B 接管，卸载 A 截断 B 的窗口并一直持有回调 | 共享状态没有"归属方" | `795783e`：记窗口归属方，打断或隐藏时撤销 | 引入共享状态时同步设计交接 | 795783e |
| B12 | share end/race 中某调用方自己取消，cancel 成了别人的结果 | 撤回语义没定义 | 自己 signal 引起的 cancel 视为撤回；超时不算 | 多方共享结果要先定义撤回 | 必修 1 |
| B13 | share 首发调用内层时被同步取消，订阅时 abort 事件已错过，请求挂住 | 注册监听前没查当前状态 | 订阅计数后先查 `aborted` | 注册监听前先查当前状态 | B4 §7 |
| B14 | 异步缓存仓的等待不可取消；internal 命中后丢异常 `throw undefined` | — | 等待可取消；不缓存 internal/cancel | 缓存只存"可以重建的结果" | 201d192；0003 |

### 4.3 测试盲区

| # | 现象 | 根因 | axp 怎么修 | 教训 | 出处 |
|---|---|---|---|---|---|
| C1 | 100% 覆盖 + 整轮验收全绿，终审仍查出 9 项必修 | 不变量只查账不查归属；powerset I7 空转；testkit 只有一个 baseURL、不发 multipart 和流、share 取消只覆盖 start | 建议 I8 结果归属、I9 来源一致、带体重发流程、撤回矩阵、双 adapter 集成 | 设计"谁拿到了谁的结果"这类断言 | 终审 §6.1–6.2 |
| C2 | 写 I7 用例时去掉 `markReplayable()` 测试仍通过 | axios 的 `mergeConfig` 会浅拷贝顶层对象 | 改用嵌套数组 | 测"没被原地修改"要用深层结构 | B3 §3 |
| C3 | 精简轮后 4 条用例失败：断言依赖原型链形状；共享 `NO_LOG` 让 spy 累加 | 测试依赖内部结构和共享单例 | 删结构断言；独立日志器 | 断言行为，不断言形状 | B1 §10.1 |
| C4 | 执行器白名单没登记 `mock-in-chain`、`keep-alive`，整轮把能跑的格子当成"缺能力"跳过 | 能力名是白名单 | 补登记、补跑 8 格 | 跳过不等于通过，跑前核对能力表 | 验收报告 §3.3 |
| C5 | 3 个验收失败里 2 个是执行器把业务风格状态表写死 | 执行器配置 bug | 修执行器并补单测 | 执行器自己要有单测 | 终审 §10.2 |
| C6 | 共享 47080/47090 的 testkit 服务旧于场景，`same_as` 比较两个 undefined 可能假通过 | 服务二进制版本没核对 | 新编专用实例 | 跑前核对服务二进制与场景版本 | 终审 §9 |
| C7 | e2e 命中计数写死、filter 场景映射错位导致假通过 | — | 真实读数；`6133630` | 断言要读真实信号 | review #29；`6133630` |

### 4.4 性能与体积

| # | 现象 | 根因 | axp 怎么修 | 教训 | 出处 |
|---|---|---|---|---|---|
| D1 | 方案 A 入口 `mergeConfig` 单次约 8.5µs，无插件比裸 axios 慢一倍（+18µs） | axios 内部再按全部字段合并一次 | A1：差量交给 axios，剩约 +10µs；B2/B6 门槛事后按 A1 调 | 先测再定方案，门槛同一时间写 | B2「方案 A1」；B6 §5.3 |
| D2 | headers 合并优化试后撤回 | 保守实现只省 1.6–1.8µs，低于 2µs 保留门槛 | 撤回，回归用例保留，A/B 数据存 `bench/followups-ab.json` | 优化前先定保留门槛；撤回时留下测试 | B6 §5.3、§8；`a47a5d9`；终审 §7"不要再碰" |
| D3 | 缓存仓改异步快照后，D 批首轮命中慢约两成（最小 24.75 → 31.08µs） | 快照与 await 带来额外开销 | E 批找回，另一轮测量里比 D 之前还快约两成（最小 11.99 → 9.71µs，两组数字不是同一轮） | 异步化要保留同步快路径 | 终审 §9 D、§10.3 |
| D4 | bench 被外部负载污染（全盘 `find`、并行批次），三轮离散 40%–100% | — | 绑 P 核、交错 A/B、按同轮倍数比较 | 记录负载，只用交错数据下结论 | B1 §5；B4 §5；B6 §5.1 |
| D5 | ES2019 运行时底线被 `toSorted`、`globalThis` 破坏；新语法降级让 `./min` 超标 | 习惯用新 API | 产物 API 扫描；去掉 `#` 私有字段降级代码 | （Dart 不适用） | B6 §1.3、§6 |

### 4.5 工程流程

| # | 现象 | 教训 | 出处 |
|---|---|---|---|
| E1 | B1–B5 用裸 `vp check`（printWidth 100、无类型感知 lint），项目标准是 `npm run check`（220），最后整仓重排 | 第一批就核对项目真正的检查命令 | B5 §3；`901a336` |
| E2 | 发布产物里 `declare module "../types"` 解析不到，请求选项类型增强整体失效 | 测产物，不只测源码 | B6 §1.1 |
| E3 | 不写泛型时 `createAxp({ plugins: [axpRetry()] })` 编译失败，README 写法会踩 | README 示例要进类型测试 | B5 §3；`9324bfb` |
| E4 | Codex 三次中断，接手方要先核对完成度、修失败用例 | 派发时约定交接清单 | B1 §10；B3 §1；B2 §7.4 |
| E5 | 提交里误带 coverage 产物（`201d192` → `fba75e4`）；19 个 A/B JSON 入库 | 提交前 `git status` + diff 自查 | `201d192`；终审 §7 |
| E6 | 方案定稿到 B7 收尾约 11.5 小时，之后两天终审 + 三次契约修订 | "快"省下的时间被返工吃回去 | git log |

### 4.6 axp 留下的未解决项与文档冲突

| # | 内容 | 出处 |
|---|---|---|
| F1 | 终审 P3 建议修多数没做：#2 两种显式 key 语义不一致（cache 的显式 key 不带 scope，切账号会串）、#3 cache 卸载后旧链仍写外部 store、#4 URLSearchParams 默认参数删不掉、#5 改 method 后头掩码错配、#6 shallow clone 把 Blob 展开成 `{}`、#7 非字面量开关返回类型（仍列为已知限制）、#9 `expectJson` 对显式 `responseType:'text'` 误判 | 终审 §3、§10.5；`plugin-spec.md` §1.2；`core-architecture.md` §10 |
| F2 | 测试建议没落地：`test-plan.md` 仍只列 I1–I7；撤回矩阵、双 adapter 只做了一部分；台账 id 对齐与 `--check` 脚本没做 | 终审 §10.5；`test-plan.md` §5.1 |
| F3 | 功能缺口：逻辑请求截止时间（放开 `timeout-total`、breaker、offline 的前提）；kind 封闭集合没有"客户端主动拦下、不该重试"的类别；cache 按谓词/tag 失效；TokenManager 的 prefix/storage/跨标签页；`cancelAll(reason)` 不进 R；插件 `dispose` 只能同步 | 终审 §7 |
| F4 | 0003 和 4ad9182 之后没有入库的整轮验收。文档里最后一次本地整轮是 10-29 13:59（`report-2026-10-29T05-59-34-078Z`）的 2250/0/442，早于 0003 第一个提交（15:59）。本地 `accept/.report/` 里 10-30/31 有多轮连 `https://api-ws-demo-latest.onrender.com` 的结果，最新（10-31 08:13）2210/40/442，失败主要是"期望 network、实际 http:502"（按首条原因计 32 格）和服务端 inflight 残留，看起来是托管平台反代把断连改写成 502，但没有出报告 | 终审 §10.2；`accept/.report/`（未入库） |
| F5 | 文档落后于代码：`core-architecture.md` §7 落定表仍写 `throws:false` → `WithData`（代码和 `ARCHITECTURE.md` §7 已是 `AxpResult`）；§9 的 `AxpOptions` 没有 `statusOf`；`SKILL.md` 与迁移指南 §9 仍说 extend 后"状态不共享/各自独立"（4ad9182 后 auth、loading 按资源共享）；迁移总表"请求体克隆失败回退原引用"的裁决已被零拷贝取代；0003 正文用 B0–B6 指代自己的子批次，和管线 B0–B7 撞名 | 对应文件；`4ad9182` |
| F6 | 已知限制：`refreshTimeout` 不终止回调本身；单飞刷新的回调 ctx 属于首个请求；`isProtected` 每次尝试入口都求值；Retry-After 空串按 0 立即重发（沿用旧行为） | `plugin-spec.md` §5；B3 §7；B5 §5 |

## 5. TS/axios → Dart/Dio 映射

### 5.1 可直接迁移

| axp 概念 | Dart/Dio 落法 | dioman 现状 |
|---|---|---|
| `(ctx, next)` 中间件、每层异常边界、`next()` 不抛 | async 闭包 + try/catch | 已有，`pipeline.dart:66-90` |
| 固定阶段 + `enforce` | `enum DiomanStage` / `DiomanEnforce` | 已有，`stages.dart` |
| 请求不可变 + `next(patch)` | Dart 没有 `undefined`，用显式删除集合 + 私有哨兵 `_absent` 区分"未提供"和"显式 null" | 已有，`request.dart:5-6`、`:110-124`，比 axp 的 `undefined` 语义更清楚 |
| `stateKey<T>()` | 非 const 的 `final class StateKey<T>`，按身份隔离 | 已有，axp `context.ts:24-26` ↔ dioman `context.dart:19-25` |
| `cancelIfAborted` / `waitAbortable` | `ctx.cancelled()` / `ctx.wait(future, timeout:)` | 已有，`context.dart:126`、`:144` |
| `validateStatus: () => true` | Dio 同名选项 | 已有，`transport.dart:9`、`:38` |
| 单飞刷新、新鲜度屏障、`canReplay` | `Future<bool>?` 字段、序号屏障、白名单判定 | 已有 |
| 不变量、powerset、交错 A/B、变异验证 | `package:test` + 夹具 | 已有，且多了 I8/I9 |

### 5.2 需改造

| axp 概念 | 为什么不能照搬 | Dart 落法 |
|---|---|---|
| `WeakMap<TokenManager, Session>` | Dart 没有 WeakMap | `Expando<_AuthSession>`：弱键、按身份；键不能是数字/字符串/布尔/记录，TokenManager 实例没问题。配持有者计数做卸载 |
| `WeakMap<callback, LoadingState>` | `Expando` 按身份，而 Dart 实例方法 tear-off 只保证 `==` 不保证 `identical`；请求级传 `controller.toggle` 会被当成不同回调 | 模块级普通 `Map`（按 `==`），计数归零即删条目；强引用只在活跃期存在 |
| 不可枚举属性附 raw/error/request（0003） | Dart 没有可枚举性，序列化本来就是显式 `toJson` | 可空字段只在 `DiomanCall(raw: true)` 时填；或者返回 `DiomanRawResponse<T>` 子类 / `(DiomanResponse<T>, DiomanNative)` 记录 |
| Retry-After 私有 Symbol 小事实 | 无 Symbol 属性 | 结果上加 `Duration? retryAfter`（或库私有字段 + `part` 内扩展访问） |
| `declare module` 扩展请求选项 | 没有声明合并 | `DiomanOptionKey<T>` 类型化键（已有）；值是 `Object?`，编译期不检查，需要的话改成"键生成类型化条目"（`DiomanRetry.option.of(2)`） |
| `WithData<R, D>`（Omit + 交叉） | 没有交叉类型，也没有高阶类型 `R<T>` | `DiomanResponse<T>` 只对 data 泛型；自定义 R 时 `send<T>` 拿不回 R 的扩展字段（见 §6.4 N8） |
| `throws:false` 的 `AxpResult` 可辨识联合 | 没有联合类型 | `send` + Dart 3 对象模式：`switch (r) { DiomanResponse(ok: true, :final data) => …, DiomanResponse(ok: false, :final kind) => … }`，穷举检查对 bool 子字段有效 |
| 动词重载按 `raw/wrap/throws` 选返回类型 | 没有重载和条件类型 | 拆成不同方法：`get`/`request` 返回数据并抛失败，`send` 返回结果（dioman 已是这样） |
| `AbortController`/`AbortSignal` | Dio 用 `CancelToken`，一次性、`whenCancel` 不能退订 | `DiomanCancelLink` 可解除桥（已有，`context_state.dart:4-24`） |
| `structuredClone` | 无 | 手写 Map/List 递归复制，`FormData.clone()` |
| `vi.useFakeTimers()` | — | 注入 `DiomanClock`（已有）；`testWidgets` 的 FakeAsync 对 `Timer` 同样生效 |
| `expectTypeOf` 类型测试 | 没有 | 把编译期断言写成 fixture，用 `dart analyze` 跑的集成测试校验诊断 |

### 5.3 Dart/Dio 做得更好

| 能力 | 带来什么 | 对应 axp 的哪处成本 |
|---|---|---|
| `Exception` / `Error` 天然两类；`on DiomanResponse catch (e)` 类型化捕获 | "失败抛结果、bug 抛原异常"是语言惯例，不用解释；catch 里不是 `unknown` | axp 要 `isAxpResponse` + 品牌 Symbol |
| `Error.throwWithStackTrace` | internal 原栈重抛（`client.dart:306`） | — |
| 枚举 + Dart 3 穷举 switch | `kind` 可以公开，编译器检查分支完整；新增类别时所有 switch 报错提醒 | axp 为防"填错 kind"把它藏起来，改用 `failureOf` |
| 具化泛型 | `api.plugin<DiomanCacheApi>()` 按类型取管理 API（`client.dart:151-156`）；运行期可判 `r is DiomanResponse<User>` | axp 要传插件对象取 API |
| 非空返回类型 | 插件忘写 `return` 编译期就报错 | axp 终审 P3 #1 |
| `const` 插件配置 + `setup` 建状态 | "配置与状态分离"由语言保证 | axp 靠约定"状态别放工厂闭包" |
| Dio 的 `RequestOptions` 是合并后的完整配置，`fetch` 不二次合并 | axp 方案 A/A1 的差量、`null`/`false` 掩码、"在途改 defaults 导致 key 错位"（必修 5）在 Dio 上不存在 | B2 方案 A1、终审必修 5 |
| `part` + 未导出的扩展/库做白盒诊断 | `lib/src/diagnostics.dart` 不进公开入口 | axp 用 `@internal` + `stripInternal` |
| `Zone` / `runZonedGuarded` | 测试里断言"迟到异常已被消费、没有未处理异步错误" | axp 没有等价手段 |
| `Isolate.run` / Dio `BackgroundTransformer` | 大 body 的解码、哈希可下放，避免卡 UI 线程 | 浏览器单线程 |
| extension types（3.3） | 零成本区分 `HttpStatus` 与逻辑状态、类型化 key 字符串 | 破坏性，作为选项 |

### 5.4 不适用

| axp 项 | 理由 |
|---|---|
| `./min` gzip -9 体积门槛、ESM 子路径 `exports`、`sideEffects: false`、声明产物说明符改写 | Dart 没有发布产物，AOT 自带 tree-shaking；如真要预算，可看 example 应用的 AOT 增量，不建议做门槛 |
| ES2015/ES2019 运行时底线、`toSorted` 扫描 | 对应物是 SDK 下限，由分析器按 `sdk:` 约束把关 |
| `Symbol.for` 品牌、`./min` 与根入口互认 | Dart 包只有一份实例，`is` 可靠 |
| 声明合并、条件类型重载、`NoInfer`、联合类型四写法 | 没有对应语法；dioman 用 `Object?` + `resolveOption` 运行期判别（`options.dart:19-30`） |
| `localStorage` 默认 TokenManager | Flutter 存储是插件（shared_preferences、secure storage），不能进依赖；保持接口 |
| axios 拦截器/adapter 层的 hack（包 transformResponse、尝试钩子） | dioman 走 `dio.fetch`，没有这些历史包袱 |
| `envelope` → `parse` 子类覆盖 | Dart 没有 protected 的惯用优势；`Envelope` 字段名 + `isEnvelope`/`isSuccess`/`create` 已够 |

### 5.5 SDK 版本线

| 特性 | 最低 SDK | `^3.5.0` 可用 | 本文用途 |
|---|---|---|---|
| records、patterns、switch 表达式、sealed/final/base/interface class | 3.0 | 是 | 结果解构、穷举 |
| extension types | 3.3 | 是 | 可选：类型化状态码与 key |
| `Expando` | 早期 | 是 | 按 TokenManager 挂会话 |
| `Error.throwWithStackTrace` | 2.16 | 是 | 已在用 |
| `WeakReference` / `Finalizer` | 2.17 | 是 | 可选：泄漏诊断 |
| `Isolate.run` | 2.19 | 是 | 可选：大 body 哈希下放 |
| `Zone` / `runZonedGuarded` | 早期 | 是 | 测试 |
| digit separators `1_000` | 3.6 | **否，需上调 SDK 下限** | 纯语法糖，不建议为它上调 |
| wildcard variables `_` | 3.7 | **否，需上调 SDK 下限** | 同上 |
| null-aware elements `?x` | 3.8 | **否，需上调 SDK 下限** | 同上 |
| dot shorthands `.foo` | 3.10 | **否，需上调 SDK 下限** | 同上 |

dioman 目前几乎没用 Dart 3 的新能力：`lib/` 里 sealed、switch 表达式、`when` 守卫、`if-case`、extension type、Expando 都是零处，只有 2 处 switch 语句、1 处 `final class`、6 处 `interface class`。

## 6. 对 dioman 现状的参照评估

### 6.1 吸收情况总览

| axp 变更 | 时间 | 相对 dioman B8（10-29 12:18） | dioman 吸收程度 |
|---|---|---|---|
| 终审必修 1–9、D1、P3 #8（notify 不提示 internal） | 报告 14:33 入库，B8 之前已有草稿（B8 标题即"对照 axp 终审补修"） | 之前 | 基本全部吸收（必修 5 对 Dio 不适用） |
| 终审 D2（信封缺省值）、D3（extend）、D4（异步快照仓） | 10-29 14:33 落地 | 之后 | D4 dioman 早有 persist；D2 部分；D3 缺失 |
| 0002（kind 私有、status 只表示 HTTP、删 envelope） | 10-29 14:33 | 之后 | 未吸收；终审 §8 记录 dioman 依其 ADR 暂时保留 kind 与逻辑 status |
| 201d192（dispose 后不清会话、ready 期间登出、cache 等待可取消） | 10-29 15:28 | 之后 | ready 登出、cache 可取消已具备；dispose 缺失 |
| 0003 全套 | 10-29 15:59–17:48 | 之后 | 未吸收 |
| 4ad9182 | 10-30 10:29 | 之后 | 只有"断流归 network"天然具备；会话/loading 共享、key 含 responseType、next 短路、零拷贝都没有 |
| 795783e | 10-30 10:55 | 之后 | 前提（loading 共享）不存在 |

### 6.2 逐项对照

状态：已具备 / 部分 / 缺失 / 不适用。优先级：P1 先做（正确性、安全）、P2 本轮做、P3 顺手或可选、— 保持。

**契约与响应**

| # | axp 要点或坑 | dioman 现状 | 证据 | 建议 | 优先级 |
|---|---|---|---|---|---|
| C1 | 归一化结果、`next()` 不抛、失败抛结果、bug 原栈抛 | 已具备 | `client.dart:231`、`:306`；`pipeline.dart:72-86` | 保持 | — |
| C2 | 内核失败事实不能被扩展点改写（0002） | 部分：kind 是公开枚举，`create(init)` 的返回值不校验，自定义工厂能把 timeout 改成 `ok: true` | `response.dart:183-189` | 改造后采纳：`_finish` 之后校验内核类别（cancel/timeout/network/parse/internal/auth/breaker/offline）与 `ok`，被改写就转 internal | P2 |
| C3 | `status` 只表示 HTTP，业务码映射走 opt-in `statusOf`（0002 + 4ad9182） | 部分（口径不同）：`status` 是逻辑状态，默认把 2xx 信封里 400–599 的整数业务码映射过来，`httpStatus` 另存，`logicalStatus` 可自定义 | `response.dart:66`、`:69`、`:174`、`:326-328` | 待拍板（§8 Q2，推荐保留默认并给关闭开关） | 拍板 |
| C4 | 信封缺省：code 0、data null、message 空串 | 部分：message 空串、data null，code 缺省 null | `response.dart:50`、`:321` | 不采纳 code=0（`Object?` 的 null 更诚实），文档写明 | P3 |
| C5 | `envelope` → `parse`/`type`/`create` | 不适用 | `response.dart:156-180` | 不采纳 | — |
| C6 | 结果默认轻量，原生数据挪 `ctx.native`（0003） | 缺失：结果常驻 `raw`（Dio `Response`，含 `requestOptions` 与请求头）、`error`、完整 `DiomanRequest` | `response.dart:84`、`:87`、`:90` | 改造后采纳，分两步（§7 R3、§8 Q3） | P2 |
| C7 | Retry-After 随结果走，不依赖原生响应 | 缺失：retry 读 `r.raw?.headers` | `retry.dart:267` | 随 C6 一起改为结果上的 `retryAfter` | P2 |
| C8 | 序列化不泄漏 | 已具备：`toString` 只含标量，Dart 无隐式序列化 | `response.dart:114-116` | 保持 | — |
| C9 | debug 调用点、`reject` 适配 | 已具备 | `client.dart:270`、`:302-304`、`:231` | 保持 | — |
| C10 | `raw/wrap/throws` 三开关 | 不适用：Dart 用 `get`/`send` 两入口 | `client.dart:218-233` | 保持；文档补对象模式写法 | P3 |

**内核原语**

| # | axp 要点或坑 | dioman 现状 | 证据 | 建议 | 优先级 |
|---|---|---|---|---|---|
| K1 | 每个逻辑请求一个取消源，`cancelAll`/`pending` | 已具备（还覆盖脱离首发的共享传输） | `client.dart:169-178`、`:266-316` | 保持 | — |
| K2 | 每次 await 后重查取消 | 已具备 | `context.dart:126`、`:144` | 保持 | — |
| K3 | `next()` 遇取消短路（4ad9182） | 部分：只在传输入口查，中间层仍会继续执行 | `pipeline.dart:76-81`；`transport.dart:30-31` | 采纳（一行） | P3 |
| K4 | `cancelAll(reason)` 写进结果（axp 也缺） | 缺失 | `client.dart:174`；`context.dart:126-129` | 采纳：reason 进 `DiomanFailure.reason` 或 message | P3 |
| K5 | 一次性体不静默重放 | 已具备：白名单判定 + `consumedBodies` 兜底转 internal | `context.dart:104-123`；`transport.dart:32-35` | 保持 | — |
| K6 | 请求体克隆策略（axp 已改零拷贝 + debug 检测） | 部分（口径不同）：可重放时每次发送都深克隆 | `transport.dart:12-22`、`:56` | 待拍板（§8 Q5，推荐先测成本） | 拍板 |
| K7 | key 含 baseURL | 已具备：`_fastKey` 用完整 `uri` 的 origin + path | `key.dart:73-74` | 保持 | — |
| K8 | key 含 responseType（4ad9182） | 缺失：同一 URL 用 json 和 bytes 请求会共用缓存条目 | `key.dart:115-120` | 采纳 | P2 |
| K9 | 二进制体 ≤64KiB 按内容 | 已具备但实现重：整段 base64 写进 key（最长约 87K 字符）；Map 键统一 `'${k}'` 字符串化，`1` 与 `'1'` 会撞 | `key.dart:105`、`:89` | 改造：只留长度 + 哈希，键带类型标签 | P3 |
| K10 | key 精简（删 ignores/sample） | 不同取舍：保留 `fastMode`/`ignores`/`builder`/`namespace` | `key.dart:8` | 不采纳（都是用户可选项） | — |
| K11 | 在途改 defaults 致 key 错位（必修 5） | 不适用：入口 `Options.compose` 一次，传输 `fetch` 用完整 `RequestOptions` | `client.dart:282-287`；`transport.dart:37-39` | — | — |
| K12 | 编译期排序、`inspect` | 已具备 | `pipeline.dart:49-63`；`client.dart:159-166` | 保持 | — |
| K13 | taps 分段挂载 | 缺失 | — | 不采纳：两个插件 + `StateKey` 能达到同样效果，需求弱 | — |
| K14 | 插件忘 `return` 的报错（P3 #1） | 不适用：非空返回类型编译期检查 | `plugin.dart:35-36` | — | — |
| K15 | 插件 `dispose` 只能同步（axp 也缺） | 缺失 | `plugin.dart:39` | 采纳：`FutureOr<void> dispose()` | P3 |
| K16 | kind 封闭集合没有熔断/离线类别（axp 终审 §7） | 已具备：`breaker`、`offline` 在枚举里，retry 否决它们 | `response.dart:11-23`；`retry.dart:215` | 保持；自定义插件的新类别用 `reason` 细分 | — |

**插件**

| # | axp 要点或坑 | dioman 现状 | 证据 | 建议 | 优先级 |
|---|---|---|---|---|---|
| A1 | auth `refreshTimeout` | 已具备（30s，`DiomanClock` 计时） | `auth.dart:278` | 保持 | — |
| A2 | 旧刷新失败不清新登录 | 已具备 | `auth.dart:294` | 保持 | — |
| A3 | `ready`/`onFailure` 可取消；ready 期间登出本地拒绝 | 已具备 | `auth.dart:361-373`、`:383-384` | 保持 | — |
| A4 | dispose 后迟到刷新失败不清会话、不通知（201d192） | 缺失：`_Auth` 没有 `dispose`，客户端销毁后刷新失败仍会 `clear()` 并调 `onAccessExpired` | `auth.dart:225-415` | 采纳 | P1 |
| A5 | 会话按 TokenManager 共享（4ad9182） | 缺失：`_refreshing`、`_expiredSession` 是每客户端字段；`extend()` 出的子客户端或共用 tm 的客户端会各刷新一次。refresh token 会轮换的后端上，第二次刷新拿的是已作废的 refresh token，若它先于第一次返回失败，快照保护（`:294`）拦不住，会清 token 并触发过期通知 | `auth.dart:110`、`:236`、`:239` | 采纳：`Expando<_AuthSession>` + 持有者计数 | P1 |
| A6 | 本地无 token 每轮会话只通知一次（4ad9182） | 缺失：每个受保护请求都通知 | `auth.dart:340-343` | 采纳 | P2 |
| A7 | 同客户端刷新必须关 auth 的约束 | 已具备（README） | `README.zh-CN.md:244` | 保持 | — |
| A8 | 回调末位 `ctx`（N14） | 不适用（暂时）：回调拿到的 `result.request` 仍是完整请求 | `auth.dart:30-43` | 若做 C6 第二步再加 | — |
| L1 | loading 按回调共享 + 窗口归属交接（4ad9182、795783e） | 缺失：每客户端一张表，两个客户端共用 spinner 时，先结束的一方会把 spinner 关掉 | `loading.dart:111` | 采纳 | P2 |
| L2 | 回调键的相等性 | Dart 特有坑：`Map.identity()` 让请求级传入的实例方法 tear-off 被当成不同回调 | `loading.dart:111` | 随 L1 改为 `==` | P2 |
| N1 | notify 默认不提示 internal | 已具备 | `notify.dart:36-43` | 保持 | — |
| N2 | `stringify` 必传（0003） | 不同取舍：默认文案只用 message/kind/status，不绑协议 | `notify.dart:15`、`:36-43` | 不采纳 | — |
| R1 | `retryAfterMax` 60s，超限不重试 | 已具备 | `retry.dart:90`、`:325` | 保持 | — |
| R2 | `respectRetryAfter` 支持判定函数 | 缺失（只有布尔） | `retry.dart:63` | 可选：dioman 有逻辑状态，业务码风格不太需要 | P3 |
| R3 | 装上即生效：`max: 2`、指数退避（N6） | 部分（默认值不同）：`max: 0`、固定 3s | `retry.dart:81`、`:147-149` | 待拍板（§8 Q4） | 拍板 |
| S1 | share end/race 撤回 | 已具备 | `share.dart:321-323` | 保持 | — |
| S2 | 超时是否算撤回 | 部分（口径不同）：dioman 把订阅者超时也算撤回并取消其传输；axp 只认调用方自己的取消 | `share.dart:321`；axp `share.ts:178`、`:201` | 待拍板（§8 Q6） | 拍板 |
| S3 | 首发取消不连累跟随者；共享传输关掉阶段超时 | 已具备 | `share.dart:113-120` | 保持 | — |
| CA1 | 取消后不返回命中；异步仓等待可取消、写入串行 | 已具备 | `cache.dart:358-382` | 保持 | — |
| CA2 | 不存 internal/cancel，即使判定返回 true | 部分：默认 `r.ok` 不存，`shouldStore` 返回 true 时会存 | `cache.dart:388` | 采纳 | P3 |
| CA3 | 命中经工厂重建、`request` 属于当前调用方 | 部分：持久化恢复用当前请求；内存命中经 `derive` 沿用首个调用方的 `request` 和 `raw` | `cache.dart:317`、`:381` | 采纳（随 C6 改快照） | P2 |
| CA4 | 内存仓存快照，不存活对象 | 缺失：`_Entry` 存整个 `DiomanResponse`，连带 Dio `Response` 常驻 | `cache.dart:149-155` | 采纳（随 C6） | P2 |
| M1 | mock 探测不写缓存、不占共享 | 已具备，但标记 `sourceProbe` 写在逻辑请求共享状态里（视图级信息放在了请求级） | `mock.dart:123`、`:131` | 可选：改成补丁或派生视图上的标记 | P3 |
| M2 | 回落前 `canReplay` | 已具备 | `mock.dart:137` | 保持 | — |

**客户端 API**

| # | axp 要点或坑 | dioman 现状 | 证据 | 建议 | 优先级 |
|---|---|---|---|---|---|
| X1 | extend 默认继承插件 | 已具备 | `client.dart:184-196` | 保持 | — |
| X2 | extend 丢拦截器 + `{axios}` 参数 + 警告（D3） | 缺失且更重：`Dio(cloneDiomanOptions(dio.options))` 新建实例，拦截器、`httpClientAdapter`（含证书固定、代理）、`transformer` 全丢，没有传入实例的参数，README 也没写 | `client.dart:187` | 采纳：加 `extend(dio: …)`，README 写清复制什么、丢什么 | P1 |
| X3 | 取插件管理 API | 已具备，按类型取更顺手 | `client.dart:151-156` | 保持 | — |
| X4 | debug 下"传了选项但插件没装"告警（4ad9182） | 缺失 | — | 采纳（便宜） | P3 |
| X5 | 自定义 R 时 response 必填（axp 类型层保证） | 缺失：`Dioman<MyResponse>` 不给 `create` 时，设了 `reject` 才在 `result as R` 处抛 TypeError | `client.dart:32`、`:231` | 采纳：构造期断言 | P3 |

**测试与工程**

| # | axp 要点或坑 | dioman 现状 | 证据 | 建议 | 优先级 |
|---|---|---|---|---|---|
| T1 | I8 结果归属、I9 来源一致 | 已具备 | `test/support/invariant_harness.dart:9`、`:123-140` | 保持 | — |
| T2 | powerset 带体重发流程 | 已具备（`bodyReplay`，share 方法含 PUT） | `test/support/b5_powerset.dart:113-129`、`:181` | 保持 | — |
| T3 | 撤回矩阵 | 部分 | `test/combo/b8_share_withdrawal_test.dart` | 补齐三策略 × 角色 × 取消/超时 | P3 |
| T4 | 多客户端共享资源的用例 | 缺失（功能本身缺） | — | 随 R1 补 | P1 |
| T5 | 测试文件按主题命名 | 部分：19 个 `b2_`–`b8_` 命名的测试与夹具，和自家指南"文件名只写主题、不单独成回归文件"冲突 | `docs/guides/test-layers.md:77-79` | 采纳：按主题归并 | P3 |
| T6 | 台账/闸门 | 已具备且比 axp 强（`matrix.json` + G0–G5 + 三档可信度 + `ASSUMPTIONS.md`） | `docs/guides/test-layers.md` | 保持 | — |
| T7 | 交错 A/B bench、3 轮 10% 稳定口径 | 已具备 | `benchmark/README.md` | 保持 | — |
| T8 | 产物/平台检查 | 部分：`response.dart:1` 直接 `import 'dart:io'`；3.13 下 dart2js/dart2wasm 都能编过，但 pub.dev 的平台判定可能因此不给 Web 标签（未核实），而 example 恰好是 Flutter Web demo | `response.dart:1`；`example/pubspec.yaml` | 采纳：条件导入或去掉对 io 异常的直接依赖 | P3 |

### 6.3 dioman 独有、axp 没有的能力

| 能力 | 证据 | 价值 |
|---|---|---|
| 熔断 breaker（含 half-open 探测，结果类别 `breaker`） | `plugins/breaker.dart` | 对应 testkit `breaker` 能力，axp 168 格因此跳过 |
| 离线队列 offline（`queueFull`/`timeout`/`disposed`） | `plugins/offline.dart` | 对应 `offline` 能力 |
| 按网络档位改阶段超时 timeout | `plugins/timeout.dart` | 移动端弱网友好；不是逻辑请求总截止时间 |
| share 的 `retry` 策略 | `share.dart:26` | 对应 testkit `share-retry` |
| mock 内联路由 + mockUrl 探测 | `mock.dart:104-115` | 不起 mock 服务也能演示 |
| auth 主动刷新（`expiresAt` + `refreshLeeway`） | `auth.dart:347-358` | JWT 过期前刷新 |
| 可注入时钟 `DiomanClock` | `clock.dart` | 测试不依赖全局假时钟 |
| 持久化缓存 memo/persist/both，串行写队列，兼容 0.7 存储格式 | `cache.dart:28-37`、`:265-268` | — |
| `get`（抛失败）与 `send`（返回结果）分开 | `client.dart:218-233` | 比 `wrap/throws/raw` 三开关好懂 |

### 6.4 与 axp 无关、这次顺带发现的问题

| # | 问题 | 证据 | 建议 |
|---|---|---|---|
| N1 | 性能：单轮实测（10-31，CPU 约 27%）S1 裸 Dio 26.7µs、S2 无插件 32.6µs、S3 全插件（13 个）未命中 118.6µs、S4 缓存命中 28.3µs、S5 100 并发 share 950.6µs/组、S6 POST + retry 38.7µs。S3 约为 S1 的 4.4 倍；热点探针显示插件侧最大一段是 source（约 59.5µs，含探针开销），prepare 约 13.2µs | `benchmark/pipeline.dart`、`pipeline_profile.dart` 本机输出 | R4 先 profile 再动手；首批嫌疑见 N2–N4 |
| N2 | 每次补丁都 `copyWith` 整份 `RequestOptions` 并建三张不可修改 Map，传输前 `toRequestOptions()` 再复制一遍 | `request.dart:11-21`、`:69-73`、`:76-106` | 改成写时复制或只复制被补丁触及的容器 |
| N3 | 自动 key 对查询和 Map 体做排序后 `jsonEncode`，大 body 在 UI isolate 上构键可能掉帧 | `key.dart:115-143` | 换成流式哈希（类型标签 + 分帧），或对大 body 设上限 |
| N4 | retry 每次请求都 `methods.map(toUpperCase)` | `retry.dart:311-313` | 预计算大写集合 |
| N5 | `expectJson` 不看显式 `responseType`，plain/bytes 请求会被误判 parse（与 axp P3 #9 同类） | `response.dart:303` | 只在 `responseType == json` 时启用 |
| N6 | Retry-After 空串按 0 立即重发（两边都沿用旧行为） | `retry.dart:269` | 待确认是否保留 |
| N7 | `extend` 的 `mergeDiomanOptions` 无法区分"显式传默认值"和"省略"，不能把非默认值改回默认 | `config.dart:22-57`（注释已说明） | 文档写明，或改用显式覆盖结构 |
| N8 | 自定义 R + `send<T>`：`copy<T>()` 构造的是基类 `DiomanResponse<T>`，R 的扩展字段丢失；`DiomanNext` 也只返回基类 | `client.dart:222-223`；`response.dart:99-112`；`plugin.dart:9` | 文档写明用 `send<dynamic>` 再转型，或让 `send` 在 T 不匹配时经 `create` 重建 |
| N9 | 没有 JSON → 模型的解码钩子，`get<User>()` 遇到 Map 会在 `result.data as T` 处抛 TypeError | `client.dart:232` | 可选：`get(path, decode: User.fromJson)` |

## 7. 独立的重构建议

### 7.1 方向

1. 吸收 axp 在 B8 之后用真实问题换来的三类修正：生命周期（卸载后迟到回调失效）、资源作用域（会话按 TokenManager、loading 按回调）、轻量契约（失败结果和缓存不常驻原生对象）。
2. 契约改动做 Dart 化改造，不照搬：保留公开只读的 `kind` 枚举，收口写权限；`status`/`httpStatus` 双字段语义写死。
3. 保留 dioman 已有的优势：breaker/offline 类别、`get`/`send` 双入口、`DiomanClock`、持久化缓存、share retry、主动刷新、矩阵闸门。
4. 性能只做数据驱动的改动，沿用 axp 的交错 A/B 和保留门槛。
5. 趁管线还在 Unreleased，把破坏性调整集中在一个版本里做完。

### 7.2 分批

| 批 | 内容 | 验收标准 | 风险 |
|---|---|---|---|
| R0 契约拍板（文档） | 一份决策记录，回答 §8 的 Q1–Q6；对 `DiomanResponse` 每个字段列"谁写、谁读、谁持有多久、默认适配谁" | 每个字段都有一行；Q1–Q6 有结论 | 跳过它，就会重演 axp 的一天三版 |
| R1 生命周期与作用域（P1） | auth 会话按 TokenManager 共享（`Expando` + 持有者计数）、本地无 token 每轮会话只通知一次、`_Auth.dispose()` 让迟到的刷新失败变成空操作；loading 按回调全局共享 + 每客户端占用 + 窗口归属交接，回调按 `==` 比较；`extend(dio: …)` + README 警告 | 新用例：父子客户端共用 tm，并发 401 只刷新一次；客户端在刷新中销毁，不清 token、不通知；无 token 连发 N 个受保护请求只通知一次，登录后复位；两个客户端共用 spinner 只出现一对 true/false，先结束的一方不关 spinner；795783e 的交接场景；请求级 tear-off 计入同一回调；`extend(dio:)` 保留拦截器。I1–I9 和 powerset 全绿，新增"每个用例结束后全局会话表、loading 表为空"的不变量 | 全局状态跨用例残留，靠新不变量兜住；`Expando` 键必须是对象 |
| R2 契约收口 | `create` 之后校验内核类别与 `ok`；`expectJson` 尊重 `responseType`；cache 永不存 internal/cancel；key 并入 responseType；`cancelAll(reason)` 进结果；`next()` 遇取消短路；debug 下"选项对应插件没装"告警；`Dioman<R>` 没有 `create` 时构造期报错 | 每项一条最低层用例；testkit normal 网络 × http/business 全量 0 失败 | `create` 校验会拦下有意把超时改成成功的写法，按设计拒绝 |
| R3 原生数据与保留（破坏性） | 第一步：引入 `ctx.native` 单槽（传输写、落定清空并封闭）；retry 改读结果上的 `retryAfter`；失败结果和缓存结果默认不带 `raw`/`error`（internal 保留 error/errorStack 以便原栈重抛）；`DiomanCall(raw: true)` 时 `send` 返回带原生数据的结果；内存缓存改存快照，命中经工厂重建并绑定当前请求。第二步（待拍板）：瘦身 `result.request`，回调加 `ctx` | 落定后槽为空且拒绝写入；未开 raw 时结果 `raw == null`；缓存命中的 `result.request` 与当前请求相同；share 跟随者仍能读到 Retry-After；持久化格式不变 | 读 `result.raw` 的使用者要迁移；retry 必须先于 raw 删除改完 |
| R4 性能（数据驱动） | 先 profile S3 与 source 段，再按 §6.4 N2–N4 逐项改；每项交错 A/B 三轮 | 门槛在 profile 后定（参考值：S3/S1 从 4.4 倍降到 3.5 倍以内，即 axp 的水平）；S2、S4、S5、S6 不退步；单项收益低于预设保留阈值就撤回并保留回归用例 | 微优化反复；机器负载要记录 |
| R5 Dart 化 API（可选） | 解码钩子；类型化请求级选项条目（或只做 debug 检查）；`FutureOr<void> dispose()`；去掉 `response.dart` 对 `dart:io` 的直接依赖；文档补对象模式写法 | example 与文档示例集成测试通过 | 类型化选项改动面大，可以只做 debug 检查 |
| R6 测试与工程收尾 | `b*_` 文件按主题归并；补撤回矩阵与原生槽不变量；若 Q8 通过则做逻辑请求截止时间 | 分层指南的命名规则无例外；截止时间放开 testkit `timeout-total` | 截止时间与 timeout 插件的阶段超时语义要分清 |

顺序：R0 → R1 → R2 → R3 → R4 → R5/R6。R1、R2 改的是不同文件，但都要动 auth 与测试夹具，按 axp 的经验不并行；R4 必须排在 R3 之后，否则 profile 结果会被 R3 改掉。

### 7.3 不建议做的

| 事项 | 理由 |
|---|---|
| 照搬 0002 把 kind 改成私有失败标记 | 失去 Dart 枚举穷举的好处；breaker/offline 需要公开类别；真正的风险用 R2 的 `create` 校验就能堵住 |
| notify `stringify` 必传 | dioman 默认文案不绑协议，必传只增加样板 |
| taps | 两个插件 + `StateKey` 能达到同样效果 |
| `envelope` 改 `parse` 子类覆盖 | 配置式在 Dart 里更简单 |
| 体积门槛、产物子路径检查 | 不适用 |
| 没有 profile 就做 headers 合并类微优化 | axp 已证明这类收益低于 2µs |

## 8. 待拍板问题

| # | 问题 | 推荐默认 | 理由 |
|---|---|---|---|
| Q1 | `kind` 的写权限 | 保留公开只读枚举，`create` 之后由内核校验内核类别与 `ok` | Dart 穷举 switch 是一等能力；breaker/offline 需要公开；风险点只在扩展工厂能改写，校验即可 |
| Q2 | 默认逻辑状态（2xx 信封里 400–599 业务码映射到 `status`） | 保留默认开启，并提供一行关闭的写法（如 `logicalStatus: (r) => r.httpStatus`） | README 的卖点就是"认证、重试、缓存共用同一个业务状态"；axp 最终也加回了 `statusOf`，差别只在默认值。**这会和 axp 的口径不同**，要写进 CHANGELOG |
| Q3 | 原生数据保留策略 | 先做 R3 第一步（失败结果与缓存不带 raw/error，`call.raw` 开启），第二步瘦身 `request` 暂缓 | 第一步解决内存与 Authorization 常驻，破坏面小；第二步要给所有回调加 `ctx`，等第一步落地后再看 |
| Q4 | retry 默认值 | 对齐 axp：`max: 2`、300ms 指数退避、`delayMax: 10s`，仍只对幂等方法生效 | 装上即生效与 filter 一致；管线尚未发版。代价是升级后默认会多重试，CHANGELOG 记为 Behavior change |
| Q5 | 请求体克隆 | 保留现状（可重放时克隆），先测 S6 里克隆的实际成本，超过约 5µs 再考虑改成 debug 检测 | Dio 的 `RequestOptions.data` 是共享引用，拦截器原地改 data 在 Dart 生态并不少见；安全优先 |
| Q6 | share end/race 中订阅者超时算不算撤回 | 对齐 axp：只有调用方自己的取消算撤回，超时结果照常参与 | 撤回应该表达调用方意愿，而不是网络结果；两边共用 testkit 场景，口径一致可以少维护一套期望 |
| Q7 | `extend` 默认是否复制 Dio 的拦截器/adapter/transformer | 不复制；新增 `extend(dio: …)`，README 写清 | 共享 adapter 时一方 `close()` 会连带另一方；拦截器可能带状态。显式传入最可控 |
| Q8 | 是否做逻辑请求截止时间 | 做，作为可选的调用级/客户端级选项 | 内核已持有取消令牌和 `DiomanClock`，成本低；能放开 testkit `timeout-total`；弱网下比阶段超时更符合直觉 |
| Q9 | 请求级选项是否改成编译期类型化 | 暂缓，先加 debug 检查（值类型不对、插件没装就告警） | 收益中等、改动面大 |
| Q10 | `response.dart` 的 `dart:io` 依赖 | 去掉（条件导入），先核实 pub.dev 平台标签 | 成本低；example 是 Flutter Web demo |

## 9. 附：事实核对清单

| 项 | 值 | 出处 / 核实方式 |
|---|---|---|
| axp 基线 | `b04d25a`，2026-10-30 13:29 | `git -C E:/workspaces/codejoo log -1 -- apps/axp` |
| axp src 最后一次改动 | `8718f82`，2026-10-30 11:15 | `git log -1 -- apps/axp/src` |
| axp 版本与发布 | `package.json` 0.2.0；npm 上最新 0.1.0，0.2.0 未发布 | `apps/axp/package.json:3`；`npm view @codejoo/axp version`（2026-10-31） |
| axp src 行数 | 4655 | `wc -l src/**/*.ts` |
| axp 测试 | 117 个测试文件（本次 `find` 统计）；5,967 条、覆盖率 100%（未复跑） | `CHANGELOG.md`「本轮架构评审修复」 |
| axp `./min` 体积 | 门槛 15,401；`8718f82` 说明 15,397 → 15,328；本次实测 15,341（相差 13 字节，dist 构建于 10-31 07:54） | `test-plan.md` TL;DR；`git show 8718f82`；`gzip -9 -c dist/index.min.js \| wc -c` |
| axp `./min` 历史 | 13,080（B0）→ 12,975（B6）→ 14,018（终审）→ 14,677（0003 后接受）→ 门槛 15,401 | B0 报告 T2；B6 §6；终审 §10.4；0003 代价；`ce22a43`、`4ad9182` |
| axp `dist/esm` 逐文件 gzip -9 求和 | 78,283（B0，33 个）→ 57,466（B6）→ 59,484（终审）→ 62,043（0003 文档）→ 本次实测 63,564（34 个） | 同上 + 本次逐文件 `gzip -9` |
| axp 性能 | B3 额外开销中位 4.26 → 2.51（降 41%）；B2/B6 多约 7–10µs；缓存命中最小 11.99 → 9.71µs；key 小 params 快 47% | B6 §5.3；终审 §10.3 |
| axp B1 基线（安静复测） | 裸 axios 80,676 hz；createAxp 无插件 79,140 hz；每层直通约 0.1µs | B1 §5.x |
| axp 方案 A 开销 | `mergeConfig` 单次约 8.5µs；A1 后无插件 +10.4µs | B2「方案 A1」 |
| headers 优化撤回 | 只省 B2 1.6µs、B6 1.8µs，保留门槛 2µs | B6 §5.3、§8；`a47a5d9` |
| axp 验收 | B7 合计 2254/0/438（443 场景）；终审后 2250/0/442（testkit `50012ea`，459 场景）；本地未入库 10-31 08:13 连 onrender 2210/40/442 | 验收报告 TL;DR；终审 §10.2；`accept/.report/report-2026-10-31T00-13-02-235Z.json` |
| axp 旧测试台账 | 836 处声明、展开 1002 条；B0 346/423/67；B5 改标后 341/424/71 | B0 报告；`pipeline-migration/README.md` |
| axp powerset | 9 插件、512 子集、9 流程、4620 条 | B5 §1 |
| axp 终审 | 必修 9 项（P1 4、P2 5），建议修 9 项；Codex 初审 10 条全部成立，调整 7 条级别 | 终审 TL;DR、§5 |
| axp 10-27 review | 30 条，误报 1 条（#13） | `2026-10-27-codex-full-review.md` TL;DR |
| axp 重构时间线 | 方案 `ced6d7c` 10-28 13:00 → B7 收尾 `3a916c9` 10-29 00:30 → 源码最后改动 `8718f82` 10-30 11:15 | git log |
| dioman 版本 | 0.7.2；`sdk: ^3.5.0`；`dio: ^5.0.0`；管线改动在 Unreleased | `pubspec.yaml`；`CHANGELOG.md:3` |
| dioman 基线 | `dioman/` 最后改动 `714c1c6`（10-29 12:18）；仓库 HEAD `46bcc5d` | `git log -- dioman` |
| dioman 重构时间线 | 方案 `a6a8d18` 10-29 00:43 → B0 `24b1571` 01:03 → B8 `714c1c6` 12:18 | git log |
| dioman lib 行数 | 4821 | `wc -l lib/**/*.dart` |
| dioman 测试 | 59 个 `_test.dart`；静态 `test(` 声明约 375（未执行，powerset 等参数化展开不计） | `find test -name '*_test.dart'`；grep |
| dioman 性能（新管线，单轮） | S1 26.7、S2 32.6、S3 118.6、S4 28.3、S6 38.7µs/次；S5 950.6µs/组 | 本机 `dart run benchmark/pipeline.dart`，2026-10-31，CPU 约 27%，仅量级参考 |
| dioman 性能（旧版 B0，中位轮） | S1 38.5、S2 38.7、S3 469.3、S4 159.5、S6 50.0µs/次；S5 4435.9µs/组 | `benchmark/summary.md`（`legacy-a6a8d18`），与上一行不同时段，不可精确相减 |
| dioman 热点 | source 段约 59.5µs、prepare 约 13.2µs、传输 + 归一化约 92.4µs（插桩，含探针开销） | 本机 `dart run benchmark/pipeline_profile.dart` |
| dart:io 与 Web | Dart 3.13 下 dart2js、dart2wasm 均可编译调用 `normalize` 的探针，node 运行输出 `DiomanKind.internal 0`；`^3.5.0` 下限未验证 | scratchpad 探针 |
| pub.dev 状态 | 未核实（curl SSL 错误 exit 35） | — |
| 体积口径 | 全部用 Git Bash `gzip -9`；dioman 无对应产物，不测 | — |
