---
title: dioman 响应契约：HTTP 状态与内核失败事实
status: active
updated: 2026-11-03
summary: 响应契约完全对齐 axp 0002 的拍板、Dart 落法与字段归属，作为 R2a 契约对齐和 R3 原生数据瘦身的规格
---

## TL;DR

- `status` 只表示 HTTP 状态；业务风格显式配置客户端 `statusOf`，不再自动映射业务码。
- 内核私有失败标记由 `failureOf(r)` 只读访问，使用者不填内部枚举；有标记时 `ok` 必为 false。
- 协议转换统一走工厂 `parse`；字段缺省值和默认成功规则见下文。
- R2a 落地契约，R3 收口原生对象生命周期；本记录是目标规格，不表示代码已经实现。

## 背景与范围

axp 0002（`E:\workspaces\codejoo\apps\axp\docs\decisions\0002-response-contract.md`）的三条理由是：库不猜后端格式、契约要精简、不能让使用者去填内部枚举。axp 终审报告 §8（同目录 `docs\reports\2026-10-29-final-review.md`）记录了架构分歧：axp 已去掉公开 kind 和逻辑 status，dioman 依 0001 暂时保留，是否跟进由 dioman 用户决定。

用户于 2026-11-03 决定**响应契约完全对齐 axp 0002**，并确认[第二轮方案 §4.3、§4.5](../design/pipeline-round2-plan.md#4-已拍板响应契约完全对齐-axp-00022026-11-03)的默认做法。本记录只将方案 §4、§5 定稿；axp 0003 仅参照其原生槽和 internal 异常保留方式，不引入方案暂缓的第二步。

## 决定

1. `kind` 改为内核私有的失败事实，使用者不能填写；读取用 `failureOf(r)`，取消用专门的判别函数。
2. `status` 只表示 HTTP 状态，没收到响应时为 0；删除 `httpStatus`。
3. 不再把业务码映射成逻辑状态。客户端 `statusOf(r) => int` 给出有效状态，retry、auth、breaker 默认规则读 `ctx.statusOf(r)`；不配置时等于 HTTP 状态。`statusOf` 是判定类纯函数，抛错按程序 bug 处理，不改写 `r.status`。
4. 取代 0001 D3 的逻辑状态部分、D5 中 kind 公开和字段集的部分，以及插件规格 C8；0001 其余条款继续有效。D4、D6 的旧字段写法按本文解释，`next()` 不抛和 bug 原栈重抛不变。

## Dart 落法（R2a，异常字段迁移为 R3）

| 项 | 定稿 | 理由 |
|---|---|---|
| 失败标记写入 | `DiomanResponse` 的库私有 `_failure`；工厂 `create` 返回后，由 `response_internal.dart` 内部入口写入。`ok` 改为合成 getter，有标记即 false | Dart 无不可枚举属性；内核事实不能由子类或 `create` 改成成功 |
| 只读访问 | `failureOf(r)` 返回 `DiomanFailure?`；将现有同名失败输入类型改为只读失败标记，不再要求使用者构造它 | 保留项目 `Dioman` 前缀及拍板时的函数名 |
| 类别 | `DiomanFailureKind`：cancel、timeout、network、parse、auth、breaker、offline、internal；标记另有 `reason` | 封闭集合，细分用 reason；ok、http、biz 没有标记，用 ok/status/code 表达 |
| 取消判别 | 顶层 `isDiomanCancel(e)` 与实例 `api.isCancel(e)`，判定响应的失败标记是否为 cancel | 对应 axp 的两个入口，便于 catch 中使用 |
| 有效状态 | `Dioman(statusOf: …)` 与 `ctx.statusOf(r)`；删除工厂 `logicalStatus` | 与 axp 同名、同位置 |
| 插件造失败 | `ctx.fail(DiomanFailureKind kind, {reason})`，只接受封闭类别和细分原因；内核异常信息走内部入口 | 插件不构造公开响应分类，也不能增加类别 |

合成 getter 的保证覆盖正常构造、扩展 `create`、结果派生与缓存重建；不能因为使用者返回 `ok: true` 就丢掉内核失败事实。`create` 自身抛错仍回退内置 internal 结果，保留首次异常。

## 解析与缺省值（R2a）

| 项 | 契约 |
|---|---|
| 信封配置 | 删除 `Envelope`、工厂 `envelope` / `isEnvelope`，改成 `parse` 函数钩子；默认读 code/data/message，协议不同由 parse 转换 |
| 保留扩展点 | `isSuccess`、`create`、`expectJson`；parse 负责转换，create 负责扩展对象，不重新解释内核失败 |
| 缺省值 | 缺业务码为 0，缺数据为 null，缺 message 为空串 |
| 默认成功规则 | HTTP 2xx 且 code 为 0 或 `'0'` |
| 请求级 `call.envelope` | 删除。工厂已不再有信封开关；保留它会留下第二套转换入口。需要不同协议时配置 parse，不预加请求级 parse 开关 |

默认 parse 保留信封识别门槛，与 axp 默认类（`src/response.ts` 的 `parse`）和 dioman 旧规则一致：Map 同时含 `code`，并含 `data`、`message` 之一，才按信封读取这三个字段；其余 Map、List、字符串等整体作为 data，code 补 0、message 补空串。去掉门槛会让不带 `code` 的普通 JSON 接口拿到 `data == null`，所以不能去。

parse 的签名为 `parse(Object? body, Response<dynamic> raw)`，与 axp 的 `parse(body, raw)` 对应，判定类回调抛错按 bug 处理。删除 `call.envelope` 推翻的是 [插件规格 §8.1](../design/pipeline-plugin-spec.md#81-b0-终审裁决2026-10-29补规格缺口) B0 裁决中"请求级 `call.envelope: false` 替代旧 `shouldNormalize`"这一条。能力本身没有丢：需要按请求跳过信封时，用 `DiomanCall(extra: …)` 打标记，在自定义 parse 里读 `raw.requestOptions.extra` 决定。迁移指南随 R2a 写明这个写法。

## 字段归属与最终处置

“结果寿命”指插件流转后由调用方持有至释放；“上下文寿命”仅到逻辑请求落定。表内是最终目标；R2a 不提前移除 R3 才处理的诊断字段。四个协作核心字段为 ok/status/code/data，message 和诊断字段仍由默认类提供，不另增接口层。

| 字段 | 谁写 | 谁读 | 谁持有多久 | 默认适配谁 | 最终处置 | 批次 |
|---|---|---|---|---|---|---|
| `ok` | 工厂业务判定；内核标记约束 getter | 插件、落定、调用方 | 结果寿命 | 成败分流 | 改语义：有失败标记必为 false | R2a |
| `kind` | 旧工厂；目标由内核写标记 | 旧插件；目标读 failureOf | 目标随标记到结果释放 | 传输与内核失败分类 | 删除顶层字段，改为失败标记 kind | R2a |
| `status` | 传输边界 | 调用方；ctx.statusOf 默认读取 | 结果寿命 | HTTP 协议 | 改语义：纯 HTTP，无响应为 0 | R2a |
| `httpStatus` | 旧工厂 | 旧调用方、mock | 无独立持有 | 原始 HTTP 状态 | 删除，由 status 替代 | R2a |
| `code` | parse，工厂补缺省 | isSuccess、业务调用方、statusOf | 结果寿命 | 后端业务码 | 改语义：缺省 0，不映射 status | R2a |
| `message` | parse，工厂补缺省 | notify、调用方 | 结果寿命 | 默认通知文案 | 保留，缺省空串 | R2a |
| `data` | parse，工厂补缺省 | get、插件、调用方 | 结果寿命；缓存按 TTL/清理持有快照 | 业务载荷 | 保留，缺省 null | R2a |
| `reason` | 旧工厂；目标由内核或 ctx.fail 写 | 失败细分、通知、调用方 | 随标记到结果释放 | auth/offline 等细分原因 | 移入失败标记 | R2a |
| `request` | 传输或结果构造；缓存重建 | 插件、调用方 | 结果寿命；缓存快照不留旧请求 | 请求定位与回调 | 保留完整 DiomanRequest；缓存命中绑当前调用方，share 仍是实际传输那次 | R3 |
| `raw` | 传输层写 ctx 原生槽，落定按需附副本 | 诊断调用方；插件可读 ctx.native | 默认上下文寿命；显式 raw 时随副本 | Dio 原始响应诊断 | 只在 call.raw 时附带，默认 null | R3 |
| `error` | 传输层写原生槽；落定按需附副本 | 诊断调用方 | 默认上下文寿命；显式 raw 时随副本 | 原始传输异常 | 只在 call.raw 时附带；internal 原始异常另存标记 | R3 |
| `errorStack` | 内核捕获异常 | internal 落定 | internal 标记随结果，其余仅上下文寿命 | bug 原栈重抛 | 移入失败标记，删除顶层字段 | R3 |
| `callSite` | debug 入口捕获；落定派生副本 | 调用方、诊断 | 失败副本寿命；生产不记录 | 调用点定位 | 保留，仅 debug，不修改 share 共享对象 | R3（原行为保留） |
| `_failure` | 内核在 create 之后写入 | getter、failureOf、内核 | 结果寿命 | 内核失败事实 | 新增私有槽，公开只读访问 | R2a |
| `failure.kind` | 内核 | retry/auth/breaker/notify、落定、调用方 | 标记寿命 | 封闭失败类别 | 新增只读 DiomanFailureKind | R2a |
| `failure.reason` | 内核或 ctx.fail | 插件、调用方 | 标记寿命 | 细分原因及取消原因 | 接收原顶层 reason；cancelAll(reason) 写入由 R2b 补齐 | R2a；R2b 补取消原因 |
| `failure.error` | 内核，仅 internal | 落定、诊断调用方 | 标记寿命，原栈抛出后随外部引用释放 | 程序 bug | 新增；非 internal 不默认保留原始异常 | R3 |
| `failure.errorStack` | 内核，仅 internal | 落定 | 标记寿命 | Dart 原栈重抛 | 新增，承接原顶层 errorStack | R3 |
| `retryAfter` | 传输边界抽取原始头字符串 | retry 经内部入口读取；share 跟随者同样可读 | 结果寿命 | HTTP Retry-After | 新增**库私有**字段，不进公开 API（对齐 axp 0003 的"私有小事实"）；不依赖失败标记或 raw | R3 |
| `call.envelope` | 旧调用方 | 旧工厂 | 删除后不持有 | 旧信封开关 | 删除，理由见解析表 | R2a |

R3 的范围与[方案 §4.5、§5](../design/pipeline-round2-plan.md#5-分批)一致：默认结果（包括失败和缓存结果）不带 raw/error；`DiomanCall(raw: true)` 在落定时按自身原生槽附到副本，`send` 返回该结果，可预期失败抛出时也适用。缓存命中和 share 跟随者没有自身原生传输，不借用别人的 raw/error；share 仍共享结果上的 retryAfter。internal 始终原栈抛出。request 瘦身与回调新增 ctx 暂缓，完整 request 仍可能保留请求体和凭证，不宣称已经完成全部瘦身。

内存缓存 R3 起存快照，经工厂重建并绑定当前调用方 request；持久化格式不变。retry 必须先切换为读取 retryAfter，再解除 raw 依赖。

## 与 axp 的不同

| 项 | dioman | axp |
|---|---|---|
| 内核保护 | 私有字段加合成 getter | 不可枚举属性 |
| parse | 工厂函数钩子 | 子类覆盖 |
| 默认成功码 | 0 或 `'0'` | 0 或 `'0000'` |
| 失败类别 | 额外有 breaker、offline | 无这两类 |

## 影响与落地

- R2a 随代码重写两份 README 的业务风格段、迁移指南并记录 Breaking；R3 随代码补原生数据迁移。管线版尚未发布，没有已发布管线版使用者需要迁移。
- 验收执行器的 business 风格像使用者一样配置 statusOf；归类改读 failureOf、ok、status、code。这是业务配置，不算替库补能力。
- 按 B5 做法重建公开 API 台账、sync 矩阵并重新定档，闸门 G0–G5 回到全绿。
- notify 的默认行为见[插件规格 §1](../design/pipeline-plugin-spec.md#1-outer)；本记录不重复文案规则。
- R0–R3 都在首个管线版本发布前完成，批次与验收标准见[第二轮方案 §5](../design/pipeline-round2-plan.md#5-分批)。
