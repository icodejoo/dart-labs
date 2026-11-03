---
title: dioman 洋葱管线第二轮方案（对照 axp 新版）
status: active
updated: 2026-11-03
summary: 现有方案（0001 + pipeline-* + B0–B8）与 axp 复盘报告交叉对比、主会话终审后的最终方案：终审结论、响应契约对齐 axp 0002（已拍板）、R0–R6 分批、要推翻的旧约定
---

## TL;DR

- **骨架不动**。洋葱管线、五个固定阶段、归一化进内核、`next()` 不抛、`get`/`send` 两个入口，两份文档结论一致，axp 落地后也没推翻过。
- **本轮补三类修正**，都是 axp 在 dioman B8 之后拿真实问题换来的：生命周期（客户端卸载后，迟到的回调要失效）、资源作用域（会话按 TokenManager 共享、loading 按回调共享）、轻量契约（结果默认不再常驻原生对象）。另有一项**发版前必修**：去掉 `response.dart` 对 `dart:io` 的直接依赖，不然新版会丢掉 pub.dev 上的 web/wasm 标签。
- **响应契约已拍板（2026-11-03）：完全对齐 axp 0002**。`kind` 改成内核私有的失败标记，通过 `failureOf(r)` 只读访问；`status` 只表示 HTTP；删掉 `httpStatus`；业务风格走客户端 `statusOf`。Dart 上怎么落、0002 其余条款的默认做法，见 §4。
- **参照评估报告逐条终审**：8 处误报或改判，1 处升级。最关键的一处：share 超时算不算撤回，维持 dioman 现状，不照搬 axp，因为两边计时模型不一样，见 §2.2。报告里"保留公开 kind、默认映射逻辑状态"的建议已被这次拍板覆盖。
- **分批**：R0 契约定稿 → R1 生命周期与作用域 → R2a 契约对齐 0002 → R2b 收口和发版前必修 → R3 原生数据瘦身 → R4 性能（先补 B6 欠下的复测）→ R5/R6 可选。R0–R3 都是破坏性改动，要在**首个管线版本发布前**一次做完（pub.dev 上现在仍是旧版 0.7.2）。
- **本轮会推翻现有方案的 9 条约定**，逐条列在 §6。落地时，0001、架构、规格、SKILL、迁移指南在同一个提交里改。

## 1. 输入与口径

| 输入 | 内容 | 基线 |
|---|---|---|
| 现有方案 | [决策 0001](../decisions/0001-pipeline-redesign.md)（D1–D10）、[核心架构](pipeline-architecture.md)、[插件规格](pipeline-plugin-spec.md)（C1–C18）、[测试方案](pipeline-test-plan.md)（I1–I9）、[实施计划](pipeline-implementation-plan.md)（B0–B8）及 B7/B8 报告 | dioman `714c1c6` |
| 参照评估 | [axp 重构复盘与 dioman 参照评估](../reports/2026-10-31-axp-refactor-lessons.md)，opus 子代理独立推导，写的时候没读现有方案 | axp `b04d25a` |
| 终审 | 主会话逐条对照 dioman 代码、axp 源码和提交说明、pub.dev | 2026-10-31 |
| 拍板 | 响应契约完全对齐 axp 0002 | 用户，2026-11-03 |

两份输入的来源有重叠：现有方案本来就是参照 axp 0.2.0 写的。所以对比看两处：0.2.0 之后 axp 又改了什么（0002、0003、`201d192`、`4ad9182`、`795783e`），以及 dioman 自己落地后暴露了什么问题。

## 2. 终审结论

### 2.1 成立

| 报告编号 | 问题 | 主会话核对 | 最终优先级 |
|---|---|---|---|
| A4 | `_Auth` 没有 `dispose` | `auth.dart` 里没有 `dispose`。刷新窗口不随调用方取消（`auth.dart:236`）。客户端 `dispose()` 会先 `cancelAll()`，但刷新照样继续跑，迟到的失败还是会走 `_expire`，清掉 token 并发过期通知 | P1 |
| A5 | 会话按客户端分 | `_refreshing`、`_expiredSession` 是实例字段（`auth.dart:236`、`:239`），`extend()` 会重新 `setup`（`client.dart:184-196`），所以父子客户端共用一个 TokenManager 时会各刷新一次。后端如果轮换 refresh token，后发的那次刷新先失败时，快照保护（`auth.dart:294`）拦不住，用户会被登出 | P1。读代码推出来的，R1 先写复现用例 |
| X2 | `extend()` 丢 Dio 配置 | `client.dart:187` 是 `Dio(cloneDiomanOptions(dio.options))`，拦截器、`httpClientAdapter`（证书固定、代理）、`transformer` 全丢，README 也没提 | P1 |
| Q10 | `dart:io` 直接依赖 | `response.dart:1`。pub.dev 上 0.7.2 带 `platform:web`、`is:wasm-ready`；对 `a6a8d18` 跑 git grep 为空，说明旧版 lib 里没有 import `dart:io`。按 pana 的规则，直接 import 会丢 web 标签 | **报告里是 P3，升为发版前必修** |
| A6 | 无 token 时每个请求都通知 | `auth.dart:340-343` | P2 |
| L1/L2 | loading 按客户端计数，回调按身份比较 | `loading.dart:111` 用 `Map.identity()`。L2 是 Dart 特有的坑：实例方法 tear-off 只保证 `==` 相等，不保证 `identical`，请求级传入的 `controller.toggle` 每次都会被当成新回调 | P2 |
| C2 | `create` 的返回值不校验 | `response.dart:183-189` 直接返回 `create!(init)` | P2，由 §4 的失败标记一并解决 |
| C6/C7/CA4 | 结果常驻原生对象 | `response.dart:84-90`（`request`/`raw`/`error`）；retry 读 `r.raw?.headers`（`retry.dart:267`）；内存缓存存整个响应（`cache.dart:149-155`） | P2（R3） |
| K8 | key 不含 `responseType` | `key.dart:115-120` | P2 |
| K9 后半 | Map 键一律转成字符串，`1` 和 `'1'` 会撞 | `key.dart:89` 的 `'${e.key}'` | P3 |
| K3、K4、K15、CA2、N5、X4、X5、T5 | 依次是：`next()` 遇取消短路；`cancelAll(reason)` 写进结果；`dispose` 支持异步；缓存永不存 internal/cancel；`expectJson` 看 `responseType`；debug 告警；构造期断言；测试文件按主题命名 | 抽查与报告一致 | P3 |

### 2.2 误报或改判

| 报告编号 | 原建议 | 终审 | 理由 |
|---|---|---|---|
| S2 / Q6 | share end/race 中订阅者超时不算撤回，对齐 axp | **误报，维持现状** | 两边计时模型不同。axp 的 end/race 给每个请求保留 axios 自己的超时（`share.ts:155` 只在 start 策略清零），超时是网络结果，理应参与竞争。dioman B8 关掉了竞争传输的 Dio 阶段计时，只按订阅预算计时，预算一到就取消自己的传输（B8 报告第 1 项），这时超时是调用方自己放弃，等同于自取消。照搬 axp 等于推翻 B8 的计时设计。testkit 以后加 end/race 参与者超时场景时，这一格要标为实现相关 |
| K9 前半 | 字节体 key 只留长度 + 哈希 | **误报** | 整段 base64 是 B8 专门加的无损校验，防 32 位 FNV 碰撞（B8 报告第 2 项，回归用例里固化了两组 8 字节碰撞向量） |
| T3 | 撤回矩阵只做了一部分 | **误报** | `test/combo/b8_share_withdrawal_test.dart` 已是 3 策略 × 4 角色 × 取消/超时 = 24 格 |
| CA3 | 缓存命中沿用首个调用方的 `request`，判为"部分具备" | **改判为口径差异** | 现有方案明文规定 `request` 是"实际发出的请求，share/cache 时是发出那一次的"（架构 §5）。终审仍建议在 R3 里改：缓存命中可能跨会话，比如 A 登出、B 登录后命中，B 的结果里就带着 A 的 Authorization。share 跟随者共用同一次传输，保持现状 |
| N7 | `extend` 合并时没法把值重置回默认 | **已知限制，不动** | B2 终审已裁决，并写进了 `extend` 的契约（`client.dart:182`） |
| Q1/Q2 | 保留公开 `kind`，默认映射逻辑状态 | **被拍板覆盖** | 你在 axp 上拍板的方向相反，axp 终审 §8 记录 dioman 只是"暂时保留"。2026-11-03 已定：完全对齐 0002 |
| N1 | S3 约为裸 Dio 的 4.4 倍 | **降为参考** | 只跑了一轮，负载约 27%。而且 B6 两组 A/B 的极差全部 ≥10%，测试方案 §6 的五项门槛一项都没下结论，之后也没复测。**新管线至今没有稳定的性能基线** |
| 测试数 | 约 375 条 | **口径更正** | 那是静态 `test(` 声明数。B8 运行时是 5588 条，其中 powerset 动态展开 5120 条 |

### 2.3 主会话核实的事实

| 项 | 结果 |
|---|---|
| 发布状态 | pub.dev 最新为 0.7.2（旧拦截器版），管线版没发布 |
| pub.dev 标签（0.7.2） | `sdk:dart`、`sdk:flutter`、六个平台（含 web）、`is:wasm-ready`、`is:dart3-compatible` |
| retry 默认值来源 | 沿用 0.7：`_defaultDelay = 3000ms`，`max` 可空（`a6a8d18` 的 `retry_plugin.dart:147`、`:477`） |
| axp `4ad9182`、`795783e`、`201d192` | 提交说明与报告的描述一致 |
| axp 终审 §8 | 明确记着 kind 和逻辑 status 的架构分歧，"是否跟进由 dioman 的用户决定" |
| Dart 3 特性 | lib 里 `sealed` 0 处，switch 语句 2 处（`auth.dart:387`、`response.dart:253`） |
| SDK 版本线 | digit separators 3.6、wildcard 3.7、null-aware elements 3.8、dot shorthands 3.10；本轮建议全部在 `^3.5.0` 内可做 |

## 3. 交叉对比

| # | 议题 | 现有方案 | axp 现行 | 参照评估 | 最终 |
|---|---|---|---|---|---|
| 1 | 骨架 | D1/D2/D4 | 相同 | 保持 | 保持 |
| 2 | `kind` | D5：公开枚举，使用者在 `create` 里构造 | 0002：内核私有标记，`failureOf` 只读 | 公开只读，`create` 后校验 | **对齐 0002**（已拍板） |
| 3 | `status` | D3/D5：2xx 信封里 400–599 的整数业务码默认映射成 `status`，另存 `httpStatus` | `status` 只表示 HTTP，业务风格配 `statusOf` | 保留默认映射 | **对齐 0002**（已拍板） |
| 4 | 原生数据 | D5：`raw`/`error`/`request` 常驻结果 | 0003：`ctx.native` 单槽，`raw: true` 才附上 | 分两步 | 采纳第一步（R3），第二步暂缓 |
| 5 | 状态作用域 | 架构 §7/§8：状态建在 `setup` 实例里，extend 后不共享 | 按资源：会话按 TokenManager，loading 按回调 | 采纳 | **采纳**，推翻"状态不共享" |
| 6 | 卸载 | 逆序调实例 `dispose`；auth 没实现 | `201d192`：卸载后迟到回调变空操作 | 采纳 | 采纳 |
| 7 | extend 的引擎 | 克隆 BaseOptions，新建 Dio | `extend(overrides, { axios })`，附警告 | `extend(dio:)`，附警告 | 采纳 |
| 8 | share 撤回 | B8：自取消或自身订阅超时 | 只认自取消 | 对齐 axp | **维持 dioman**（计时模型不同） |
| 9 | 缓存命中的 `request` | 首个调用方实际发出的那次 | 绑定当前调用方 | 采纳 | 采纳（R3），share 不变 |
| 10 | 请求体克隆 | P4：`markReplayable` 时克隆 | 零拷贝，debug 下做指纹检测 | 保留，先测 | 保留，R4 测成本 |
| 11 | retry 默认值 | 沿用 0.7：`max: 0`、固定 3s | `max: 2`、指数退避、`delayMax: 10s` | 对齐 | 对齐（非阻塞默认，记为 Behavior change） |
| 12 | key | 0.7 算法 + B8 无损字节校验 | 流式哈希，并入 `responseType` | 并入 `responseType`；字节只留哈希 | 并入 `responseType`，Map 键带类型；**字节校验保持** |
| 13 | notify `stringify` | 有默认值 | 必传（0003） | 不采纳 | 不采纳；默认文案改读 `failureOf` 和 `status` |
| 14 | 逻辑请求截止时间 | 没有（testkit `timeout-total` 168 格缺能力） | 没有，axp 终审列为头号功能建议 | 做，可选 | 可选，放 R6 |
| 15 | 平台 | 没考虑 web 标签 | — | P3，去掉 `dart:io` | **发版前必修**（R2b） |
| 16 | 性能门槛 | S1–S6 门槛已定，B6 没下结论 | 交错 A/B + 保留门槛 | 先 profile | 先补 B6 的复测，再决定优化什么 |

## 4. 已拍板：响应契约完全对齐 axp 0002（2026-11-03）

### 4.1 决定

1. `kind` 改为内核私有的失败事实，使用者不能填写；读取用 `failureOf(r)`，判断取消用专门的判别函数。
2. `status` 只表示 HTTP 状态，没收到响应时为 0；删除 `httpStatus`。
3. 不再把业务码映射成逻辑状态。业务风格由客户端选项 `statusOf(r) => int` 给出"有效状态"，retry、auth、breaker 的默认规则读 `ctx.statusOf(r)`；不配置时，有效状态就是 HTTP 状态。
4. 被推翻的是 0001 的 D3、D5 和规格 C8。0001 的其余决定继续有效。

### 4.2 Dart 落法（R0 写进 `decisions/0002`）

| 项 | 做法 | 为什么这样落 |
|---|---|---|
| 失败标记的写入 | `DiomanResponse` 上加一个库私有的 `_failure`，内核在工厂 `create` 返回**之后**，通过内部入口写入（沿用现有 `response_internal.dart` 的做法）；`ok` 改成 getter，只要有失败标记就是 `false` | Dart 没有不可枚举属性；字段是 final，"强制 `ok=false`"只能靠合成 getter。使用者的子类和 `create` 都改不了内核事实 |
| 读取 | `failureOf(r)` 返回 `DiomanFailure?`：`kind` 是新的只读枚举 `DiomanFailureKind`（cancel、timeout、network、parse、auth、breaker、offline、internal），另有 `reason`；HTTP 失败和业务失败没有标记，用 `ok`/`status`/`code` 判断 | 穷举 switch 仍可以写在 `failureOf(r)?.kind` 上，`null` 分支表示没有失败标记。breaker、offline 照样是一等类别，补上了 axp 自己承认缺的那块（axp 终审 §7） |
| 取消判断 | 提供 `isDiomanCancel(e)` 和 `api.isCancel(e)`，对应 axp 的 `isAxpCancel` / `api.isCancel`，具体命名 R0 定 | catch 里常用，值得单独给一个 |
| 有效状态 | `Dioman(statusOf: …)`，插件读 `ctx.statusOf(r)`；删掉工厂上的 `logicalStatus` | 和 axp 同名同位置，跨库读代码不用切换 |
| 插件造失败 | `ctx.fail(...)` 只接受 `DiomanFailureKind` 加 `reason`；自定义插件不能新增类别，细分用 `reason` | 和 axp 的封闭集合一致 |

### 4.3 0002 其余条款（已确认，2026-11-03）

| 条款 | 默认 | 说明 |
|---|---|---|
| `reason` | 并进失败标记，删掉顶层 `reason` | 对齐 0002 |
| 信封配置 | 删掉 `envelope`/`isEnvelope`，改成工厂的 `parse` 函数钩子，默认读 code/data/message；保留 `isSuccess`、`create`、`expectJson` | Dart 用函数钩子代替 axp 的子类覆盖 `parse`；请求级 `call.envelope` 的去留在 R0 字段表里定 |
| 缺省值 | 缺业务码为 0，缺数据为 null，缺 message 为空串 | 对齐 0002。参照评估 C4 主张 code 保持 null，不采纳 |
| 默认成功规则 | 2xx 且 code 为 0 或 `'0'` | 沿用 dioman。axp 是 0 或 `'0000'`，属于各自后端的约定，不强行对齐 |

### 4.4 影响

- README 两份的"业务风格"一节要重写，迁移指南要补上，CHANGELOG 记为 Breaking。管线版还没发布，所以没有存量使用者要迁。
- 验收执行器的 business 风格改成像使用者那样配置 `statusOf`；归类改读 `failureOf`、`ok`、`status`、`code`。这属于使用者本来就要做的配置，不算替库补能力。
- 公开 API 台账和总账矩阵会大面积变化：按 B5 的做法重建台账、`sync` 矩阵、重新定档，闸门 G0–G5 必须回到全绿。
- notify 的默认文案改读 `failureOf` 和 `status`，internal 仍然不提示。

### 4.5 其余默认（已确认，2026-11-03）

| 事项 | 默认 |
|---|---|
| R3 原生数据 | 只做第一步：所有结果（成功、失败、缓存命中）默认都不带原生对象，`DiomanCall(raw: true)` 才开启，与 axp 0003 一致；代价是成功时要读响应头也得开 `call.raw`。（R0 终审统一口径，原先这里只写了失败和缓存结果，与 §5 R3 的验收"没开 raw 时 `raw == null`"矛盾）第二步（瘦身 `request`、回调加 `ctx`）等第一步落地后再议 |
| retry 默认值 | 对齐 axp：`max: 2`、300ms 起指数退避、`delayMax: 10s`，仍然只对幂等方法生效 |
| extend | 默认不复制 Dio 的拦截器、adapter、transformer；新增 `extend(dio: …)` 参数，README 写清楚 |
| 逻辑请求截止时间 | 放 R6，可选 |
| 请求体克隆 | 保留现状，R4 先测成本 |

## 5. 分批

| 批 | 内容 | 完成标准 | 风险 |
|---|---|---|---|
| R0 契约定稿（文档） | 写 `decisions/0002`，记录 §4 的拍板与 Dart 落法；给 `DiomanResponse` 每个字段（含 `raw`、`error`、`request`、`callSite`）过一遍四个问题：谁写、谁读、谁持有多久、默认适配谁；同一个提交里给 0001 D3/D5 加"已取代"链接，并修订架构 §4–§8、规格、测试方案（I10、I11）和 SKILL，写成本轮的目标状态。迁移指南和 README 跟 R2a、R3 的代码提交一起改（§8 第 1 条） | 字段表每一行都有结论；0001 相关条款都带取代链接；设计文档和 0002 没有矛盾 | 跳过这一步，就会重演 axp 契约一天改三版（参照评估 §4.1 A1） |
| R1 生命周期与作用域（P1） | **auth**：会话状态（单飞刷新、过期标记、无 token 通知去重）按 TokenManager 共享，用 `Expando<_AuthSession>`，带持有者计数；最后一个持有者卸载后，迟到的刷新失败变成空操作（还有持有者时按会话规则只处理一次）；无 token 时每轮会话只通知一次，写入新 token 后复位。**loading**：按回调全局共享（模块级 `Map`，用 `==` 比较，计数归零就删条目），每个客户端记自己的占用，延迟隐藏窗口要记归属方（对应 axp `795783e`）。**extend**：新增 `dio` 参数，README 用一张表说清楚复制什么、共享什么、丢什么 | 先写复现用例，先红后绿：父子客户端共用 TokenManager，假后端会轮换 refresh token，后发的刷新先失败。另外要覆盖：刷新中途销毁客户端，不清 token、不发通知；无 token 时连发 N 个请求只通知一次；两个客户端共用一个 spinner，只出现一对 true/false；请求级 tear-off 计入同一个回调；`extend(dio:)` 保留拦截器。新增不变量 **I10**：每个用例结束后，全局会话表和 loading 表都为空。I1–I10 和 powerset 全绿，行/分支覆盖维持 100%，变异验证覆盖会话共享和 dispose 后的空操作 | 全局状态跨用例残留，由 I10 兜住；`Expando` 的键必须是对象（TokenManager 实例没问题） |
| R2a 契约对齐 0002 | 按 §4 落地：失败标记（`_failure`、`failureOf`、合成的 `ok`）、`DiomanFailureKind`、取消判别函数；`status` 只表示 HTTP，删掉 `httpStatus` 和 `logicalStatus`；新增 `statusOf` 与 `ctx.statusOf`；retry/auth/breaker 默认规则改读有效状态；`parse` 钩子与缺省值；notify 默认文案；执行器的 business 风格改为配 `statusOf`；重建 API 台账、`sync` 矩阵、重新定档 | 每项至少一条最低层用例；"自定义 `create` 无法把内核失败改成成功"要有回归和变异验证；闸门 G0–G5 全绿；testkit normal 网络 × http/business 全量 0 失败 | 改动面最大的一批，会碰到所有读 `kind`/`status` 的插件和测试；按插件分组终审，不要一口气交 |
| R2b 收口与发版前必修 | **去掉 `dart:io` 直接依赖**：用条件导入 stub，或改用 Dio 的异常类型判定，先确认哪种不损失分类精度；发版前本地跑 pana，确认 `platform:web`、`is:wasm-ready` 还在。其余各项：key 并入 `responseType`，Map 键带类型标签；缓存永不存 internal/cancel；`expectJson` 尊重显式 `responseType`；`next()` 遇取消短路；`cancelAll(reason)` 写进失败标记的 `reason`；debug 下对"传了选项但插件没装"告警；`Dioman<R>` 没给 `create` 时构造期报错；retry 默认值（按 §4.5） | 每项一条最低层用例；key 的每处变化逐项断言，不改 B8 的 `key_parity` 基准文件（沿用 B8 做法） | 条件导入要在 VM、dart2js、dart2wasm 三处都验证分类结果一致 |
| R3 原生数据瘦身（破坏性，第一步） | 引入 ctx 原生槽：传输层写入，落定时清空并封闭；retry 改读结果上的 `retryAfter`（必须先改这个，再删 `raw`）；所有结果默认不带 `raw`/`error`，internal 的原始异常和栈放进失败标记（对齐 0003 对失败标记的扩展），保证还能原栈重抛；`DiomanCall(raw: true)` 时 `send` 返回带原生数据的结果；内存缓存改存快照，命中时经工厂重建，并绑定当前调用方的 `request`；share 跟随者不变；持久化格式不变 | 落定后原生槽为空且拒绝写入（不变量 I11）；没开 raw 时 `raw == null`；缓存命中结果的 `request` 等于当前请求；share 跟随者仍能读到 Retry-After | 读 `result.raw` 的使用者要迁移，写进迁移指南 |
| R4 性能（数据驱动） | 先补 B6 欠下的复测：在安静的机器上重跑 S1–S6；机器有负载就用交错 A/B 并记录负载，对照测试方案 §6 逐项下结论。然后 profile S2（B6 观察到无插件时新版吞吐比旧版低 20–30%）和 S3 的 source 段，首批嫌疑：每次打补丁都全量 `copyWith` 一份 `RequestOptions`、key 排序后再 `jsonEncode`、retry 每个请求都做 `toUpperCase`。每项优化做三轮交错 A/B，保留阈值动手前写定（参考 axp 的 2µs），收益低于阈值就撤回，回归用例留下。顺带测请求体克隆的成本 | 测试方案 §6 的五项门槛都有结论：达标，或经你批准调整（原文保留） | 微优化反复横跳；机器负载要记下来 |
| R5 Dart 化 API（可选） | 解码钩子 `get(path, decode: User.fromJson)`；`FutureOr<void> dispose()`；文档补上 `switch (failureOf(r)?.kind)` 的穷举写法；类型化的请求级选项只做 debug 检查 | example 和文档示例的集成测试通过 | 类型化选项改动面大，所以只做检查 |
| R6 测试与工程收尾（可选） | `b2_`–`b8_` 前缀的测试和夹具按主题归并（对齐 `docs/guides/test-layers.md` 的命名规则）；逻辑请求截止时间（可选，能放开 testkit `timeout-total` 的 168 格） | 命名规则没有例外；截止时间和 timeout 插件的阶段超时，语义分开写清楚 | 截止时间和阶段超时容易混 |

- **线性推进，不并行**：R1、R2a、R2b、R3 都要动 auth、cache 和测试夹具；R4 必须排在 R3 后面，否则 profile 结果会被 R3 改掉。
- **发版节点**：R0–R3 全部完成后再发首个管线版本，免得使用者经历两次破坏性升级。R4–R6 可以在后续小版本里跟进。

## 6. 要推翻或修订的现有约定

| 现有约定 | 出处 | 改成 | 批次 |
|---|---|---|---|
| extend 后各自 setup，状态不共享 | 架构 §8；`client.dart:180` 的注释 | auth 会话按 TokenManager 共享，loading 按回调共享 | R1 |
| 插件状态一律建在 `setup` 实例里 | 架构 §7 约定 | 加一条例外：代表外部资源的状态（会话、spinner）跟着资源走 | R1 |
| loading 按回调身份分开计数 | 规格 §1 loading；§8.1 B0 裁决 | 按 `==` 比较，跨客户端共享 | R1 |
| extend 克隆 BaseOptions 新建 Dio | 架构 §8 | 可传入 `dio`；默认行为不变，但写清楚会丢什么 | R1 |
| `kind` 是公开枚举，由使用者在 `create` 里构造；默认把业务码映射成逻辑状态；`httpStatus`、顶层 `reason`、`envelope` | D3、D5；架构 §5；规格 C8 | 对齐 0002：内核私有失败标记 + `failureOf`；`status` 只表示 HTTP；业务风格走 `statusOf`；`reason` 并进标记；`parse` 钩子；缺业务码为 0 | R0/R2a |
| key 算法沿用 0.7 | 规格 §7 | 并入 `responseType`，Map 键带类型；字节体的无损校验保持 | R2b |
| retry 沿用 0.7 的默认值 | 规格 §3 retry | `max: 2`、指数退避、`delayMax: 10s` | R2b |
| `raw`/`error` 常驻结果 | D5；架构 §5 | 所有结果默认不带，`call.raw` 才开启；internal 的异常放进失败标记 | R3 |
| `request` 是实际发出的那次（含缓存命中） | 架构 §5 | 缓存命中绑定当前调用方，share 不变 | R3 |

## 7. 不做的

| 事项 | 理由 |
|---|---|
| share 超时撤回改用 axp 的口径 | 计时模型不同，见 §2.2 |
| 去掉字节体 key 的无损校验 | 那是 B8 防碰撞的修复，见 §2.2 |
| notify `stringify` 改成必传 | 默认文案不绑定协议，必传只会多一份样板代码 |
| taps 分段挂载 | 两个插件加 `StateKey` 就能实现 |
| `parse` 走 axp 的子类覆盖写法 | Dart 里用函数钩子更直接，见 §4.3 |
| 体积门槛、产物子路径检查 | Dart 没有对应的发布产物 |
| 没 profile 就做 headers 合并之类的微优化 | axp 已经证明这类收益不到 2µs（`a47a5d9`） |

## 8. 工作方式

沿用 B 系列的做法：每批由 Codex 实现并自审，主会话终审；不新增依赖；SDK 保持 `^3.5.0`；全量 `dart test` 和真实验收串行跑；批次报告结构不变。再从 axp 的教训里补四条：

1. 改契约的同一个提交里，同步改 SKILL、迁移指南和两份 README（axp 就吃过文档落后于代码的亏，见参照评估 §4.6 F5）。
2. 性能门槛和保留阈值在动手前写定；机器有负载时，只用交错 A/B 的数据下结论（参照评估 §4.4 D2、D4）。
3. 引入共享状态的那一批，同时把交接和卸载设计好；每张共享表都配一条"用例结束时为空"的不变量（参照评估 §4.2 B11）。
4. 跑验收前，先核对 testkit 服务的二进制、场景版本和能力登记（参照评估 §4.3 C4、C6）。
