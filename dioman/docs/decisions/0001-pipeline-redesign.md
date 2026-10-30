---
title: dioman 洋葱管线重构的决策
status: active
updated: 2026-10-29
summary: 为什么把 dioman 从"Dio 拦截器插件"改成"以 Dio 为引擎的洋葱管线包装器"，排序、归一化、错误模型、取消、mock 怎么定，推翻了哪些旧约定
---
## TL;DR

- dioman 的定位是**以 Dio 为引擎的请求包装器**，不是 Dio 插件。dioman 自己持有调用链：插件是 `(ctx, next)` 中间件，最内层调用一次 `dio.fetch`。重试、重放就是再调一次 `next()`。
- **归一化进内核**：传输边界判定一次，产出 `DiomanResponse`；所有插件只读它的 `ok`、`kind`、逻辑 `status`。最外层落定：成功返回数据，可预期的失败抛 `DiomanResponse`（它 `implements Exception`），程序 bug 原样抛出原始异常和 stack。
- **排序用固定阶段**：内置插件位置固定，自定义插件只选阶段。cancel、key、normalize、log 降为内核能力；mock 回到 source 阶段。
- 参照 axp 0.2.0（`E:\workspaces\codejoo\apps\axp`，决策 0001、验收 2254 通过 / 0 失败），按 Dart 与 Dio 的差异做了调整，差异写在每条决策的"与 axp 的不同"里。
- 拍板：用户（jelon）授权"以 Dio 为引擎的包装器，洋葱管线价值大就引入"（2026-10-28），具体方案由主会话（Opus）定，2026-10-29。

## 背景

dioman 0.7 的复杂度和缺陷主要来自"在同序执行的 Dio 拦截器链上模拟洋葱语义"。2026-10-28 一天里修的 9 个产品问题中有 5 个属于这个模型：

| 问题 | 根因 |
|---|---|
| cache 存进 HTTP 200 的业务失败，需要 `_wireChain` 接 normalize 的判定 | 成败判定散在 normalize、retry、breaker、cache、auth、notify 6 处 |
| 验收执行器替 retry/breaker 补业务码判定；D21 时执行器要特判 401/403 | 同上 |
| retry 去恢复 mock/cache 短路的结果 | Dio 拦截器短路后仍会运行后面插件的 onResponse |
| 插拔后 retry↔breaker 不重新接线 | 插件之间靠 setter 接线 |
| 执行器必须偷偷补装 key；key 必须排在 repath/filter 之后 | key 是往 `extra` 写值的插件 |

为模拟洋葱写的机制约 1060 行（`replay_support` 318、`request_claims` 171、`plugin_order` 250、`extra_keys` 318），外加 auth/retry/share 里 48 处认领与重放调用、全库约 140 处 `extra` 字符串状态读写。

## D1 自有洋葱管线，最内层调 `dio.fetch`

**决定**：`Dioman` 客户端自己组织中间件链。入口用 `Options.compose(dio.options, …)` 合并**一次**得到有效配置，传输层调用 `dio.fetch(requestOptions)`。使用者装在 Dio 上的拦截器仍然运行，位置在传输层以内，每次尝试都会经过。

**理由**：重试、重放、短路在洋葱里分别是"再调 `next()`""不调 `next()`"，外层天然拿到最终结果。上表的重放交接、认领结算、接线、`extra` 保活全部可以删掉。

**与 axp 的不同**：axp 的入口合并加差量传输（axp D1/D2）是为了避免 axios 内部再合并一次，首版多花了 18µs。Dio 的 `fetch` 不会再合并 BaseOptions（已核对 dio 5.11.1 `dio_mixin.dart:396` 只在 `request()` 里 `compose`，`fetch` 直接使用传入的 `RequestOptions`），所以 dioman **不需要差量传输**，入口合并一次即可。

**推翻的旧约定**：`DiomanPlugin extends Interceptor`、`Dioman.install(dio, …)` 返回 `DiomanHandle`、使用者直接调用 `dio.get` 时插件生效。改为调用 `api.get`；裸调 `dio.get` 不再经过插件。dioman 还在 0.x，按破坏性变更处理，写迁移指南。

## D2 固定阶段排序

**决定**：五个阶段，外到内依次是 `outer → prepare → attempt → credential → source`。内置插件在阶段内的次序固定，使用者不用排；自定义插件选一个阶段，可加 `enforce: pre | post`（默认 post），同阶段内按传入数组的顺序。`api.inspect()` 返回解析后的完整顺序。

| 阶段 | 内置插件（外 → 内） |
|---|---|
| outer | loading → notify |
| prepare | repath → filter → timeout |
| attempt | retry → breaker |
| credential | auth |
| source | mock → share → cache → offline |

**理由**：dioman 现有的 `install` 固定顺序加 before/after 校验，本来就是"内置插件固定次序"。用户对它的评价是"按序声明挺好"，阶段保留了这一点：顺序固定、写在一张表里、看得见。真正多余的是 before/after/requires 的拓扑排序和成环、错序、缺依赖三类报错。

**推翻的旧约定**：`DiomanPluginOrder`（before/after/requires）、`Dioman.sort/validate`。

**breaker 和 offline 的位置**：axp 没有这两个插件，位置是这里定的。
- breaker 放在 retry 之内：每次尝试都经过 breaker；熔断打开时 breaker 直接返回 `kind: breaker` 的结果，retry 遇到这个类别不再重试。这样就不需要原来的 retry↔breaker 接线。
- offline 放在 source 的最内层：缓存命中不受离线影响（INV-20）；share 合并之后只排队一次。

## D3 归一化进内核，拆判定与落定

**决定**：归一化不是插件，是内核在传输边界上的固定步骤，有默认实现，只配置不安装。

| 步骤 | 位置 | 次数 |
|---|---|---|
| 判定：Dio 的 `Response` 或异常 → `DiomanResponse` | 紧贴传输层 | 每次发送一次 |
| 落定：成功返回数据，否则抛出 | 洋葱最外层 | 每个逻辑请求一次 |

**推翻的旧约定**：`DiomanNormalize` 插件及其请求级开关；`DiomanCache.shouldStore` 的 normalize 自动接线；`DiomanException`（业务失败改为 `kind: biz` 的 `DiomanResponse`）。

**对验收的影响**：testkit D21"未装 normalize 时业务码透传"在这个模型里不成立。这和 axp 碰到的情况一样，相关场景按缺能力跳过（testkit 侧加能力名，见实施计划 B7）。

## D4 `next()` 一律返回结果，不抛错

**决定**：HTTP 错误、业务失败、网络错误、超时、取消，全部变成 `DiomanResponse` 从 `next()` 返回。中间件自身抛出的异常，由内核在这一层的边界上包成 `kind: internal`（原始异常和 stack 放在 `error`、`errorStack`），保证外层的计数、注销、订阅者离场照常收尾。只有最外层落定时才 throw。

**理由**：现在每个插件都要写 onResponse 和 onError 两条路径，合并成一条。

## D5 `DiomanResponse`：字段在构造时算好，判定由工厂负责

**决定**：
- `class DiomanResponse<D> implements Exception`，字段都是 `final`：`ok`、`kind`、`status`（逻辑状态）、`httpStatus`、`code`、`message`、`data`、`reason`、`request`、`raw`、`error`、`errorStack`、`callSite`（仅 debug）。
- 判定由每个客户端一份的 `DiomanResponseFactory` 完成：信封字段名、成功码判定、逻辑状态映射都是工厂的选项；需要扩展字段时，子类化 `DiomanResponse` 并在工厂的 `create` 钩子里构造。
- 插件需要凭空造结果时走 `ctx.fail()`，保证经过工厂，扩展字段始终存在。

**与 axp 的不同**：axp 的开放点是"子类覆盖 `ok`/`status` getter"，并用"实例自有属性遮住原型 getter"保证 getter 只在收到响应时求值。Dart 没有属性遮蔽，所以改成：`ok`/`status`/`kind` 由工厂在构造时算好写进 final 字段；只有"收到了响应"这条分支会调用使用者提供的判定函数。"只在收到响应时求值"由调用位置保证，不依赖对象的形状。

## D6 可预期的失败抛 `DiomanResponse`，bug 原样抛出

**决定**：
- 可预期的失败（http、biz、network、timeout、cancel、parse、auth、breaker、offline）落定时 `throw r`。使用者用 `on DiomanResponse catch (r)` 捕获。
- 程序 bug（`kind: internal`）落定时用 `Error.throwWithStackTrace(r.error, r.errorStack)` 抛出原始异常和原始 stack。`send` 也不吞 bug。
- 提供两种返回形态：`api.get<T>(…)` 返回数据、失败抛出；`api.send<T>(…)` 返回 `DiomanResponse<T>`，可预期的失败不抛。

**与 axp 的不同**：axp 不设错误类，一个理由是 JS 的 `Error` 构造会捕获调用栈、有成本。Dart 的 `Exception` 构造不抓栈（stack 在 throw 时由 `catch (e, st)` 带出），所以 `implements Exception` 没有额外成本，还能满足 `only_throw_errors` 规则，也能使用类型化的 `on` 捕获。axp 用 `wrap`/`throws` 两个开关靠 TS 重载推断返回类型；Dart 不能按命名参数重载，所以改成 `get` 与 `send` 两组方法。

**推翻的旧约定**：可预期的失败以 `DioException` 抛出（`on DioException` 的使用方要改）。

## D7 内核能力：取消、key、debug

**决定**：
- **取消**：每个逻辑请求一个内核 `CancelToken`，和使用者传入的 token 联动；`api.cancelAll()`、`api.pending`。取消原语收口成两个：`ctx.wait(future, {timeout})`（等结果、等取消、等超时三合一，无论哪种结局都清理计时器和订阅；已取消就立即返回）和 `ctx.cancelled()`（已取消就造 cancel 结果）。**每个 await 之后必须重查**。axp 在 B3/B4 的 6 处取消缺陷都是这一类。
- **key**：内核服务 `ctx.key()`，惰性计算并按请求缓存；在 prepare 阶段之后求值，所以天然看到 repath/filter 改过的请求，不再有排序约束。请求级 `key: false/字符串`。
- **debug**：`Dioman(debug: true | DiomanLogger)`，记录调用点 stack、插件告警。线上的报文日志直接用 Dio 自带的 `LogInterceptor` 装在引擎上，dioman 不再提供 log 插件。

**推翻的旧约定**：`DiomanCancel`、`DiomanKey`、`DiomanLog` 插件，以及 `kKey` 等 `extra` 协议键。

## D8 请求不可变，跨插件状态用类型化的键

**决定**：
- 链上流转的请求是不可变的 `DiomanRequest`。内层要改请求，就调用 `next(patch)`，内核合并出新请求交给内层。同一层两次调用 `next()` 拿到同一个基准请求，所以重发天然"干净"，不需要快照。删除字段用显式的移除集合（`removeHeaders`、`removeQuery`），不靠 null。
- 跨插件状态用 `StateKey<T>`（按身份比较的泛型键）存在逻辑请求级上下文里，替代 `extra` 字符串键。插件状态建在 `setup(client)` 返回的实例里，同一个插件对象可以装进多个客户端，各自独立。

**推翻的旧约定**：`DiomanExtraKeys` 注册表、`extra[...]` 状态协议。请求级插件选项改为类型化的键（每个插件暴露自己的选项键），不再是字符串。

## D9 mock 回到 source 阶段

**决定**：`DiomanMock` 是 source 阶段最外层的插件：命中就短路；探测请求带"不走 cache、不参与 share"的标记；判定要回落时再调一次 `next()` 打真实接口。删除 `DiomanMockAdapter` 和 cache 的 `x-dioman-mock` 标记头规则。

**理由**：传输层 adapter 是在拦截器模型下为了绕开顺序问题做的折中（2026-10-28）。到了洋葱模型，source 阶段的 mock 天然不进缓存、不被合并，正好符合 testkit 的 `mock-in-chain` 语义，标记头那套补丁就不再需要。

**推翻的旧约定**：2026-10-28 刚定的"mock 在传输层"。这是在新模型下重新做的判断，不是否定当时的取舍：当时在拦截器模型里，adapter 是最优解。

## D10 不新增依赖，时间可注入

**决定**：不引入 `fake_async`、`benchmark_harness` 等新依赖。内核用可注入的 `DiomanClock`（当前时间 + 计时器工厂），测试用自己写的假时钟；bench 用 `Stopwatch` 自写（预热、多轮、取中位数）。最低 SDK 保持 `^3.5.0`，不用更高版本才有的语言特性。

**理由**：CLAUDE.md 要求引入新依赖前先征得同意；dioman 现在已经有 `now`/`clock` 注入的先例（breaker、cache）。
