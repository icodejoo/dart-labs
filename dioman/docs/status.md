---
title: dioman 当前状态与待办
status: active
updated: 2026-10-28
summary: 测试体系落地进度（P0–P3）、闸门现状、待拍板的产品问题与 P2 补测清单，只写现在。
---
## TL;DR

P0 搭账、P1 定档已完成：总账 439 行全部定档，G0/G2/G5 清零。剩余 G3 204（行无单测）、G4 20（② 行缺真实用例）是 P2 补测清单。另有 4 条源码已核实的产品问题待拍板。

## 进度

| 阶段 | 状态 | 结果 |
|---|---|---|
| P0 搭账 | 完成 | `test/accept/lib/matrix.dart` + `test/accept/bin/matrix.dart`（sync/gates/evidence/results）；默认运行带静态闸门 `test/integration/matrix_integration_test.dart` |
| P1 定档 | 完成 | 439 行：① 407、② 31、③ 1（含 26 条 INV 不变量行）；假设 H1–H8 见 `test/ASSUMPTIONS.md`；结论回填 140 行，② ③ 行 PASS 20、BLOCKED 2 |
| P2 补测 | 未开始 | 见下方清单 |
| P3 收口 | 部分完成 | 文档归入 docs/、accept 并入 test/accept/、证据汇总入库 `test/accept/evidence/`；剩 `docs/guides/test-layers.md` 补三档/总账章节 |

闸门：`dart run test/accept/bin/matrix.dart gates --lcov=coverage/local.info`（lcov 用 `dart test --coverage-path=coverage/local.info` 生成）

| G0 未定档 | G2 API | G3 无单测 | G4 真实侧 | G5 反查 |
|---:|---:|---:|---:|---:|
| 0 | 0 | 204 | 20 | 0 |

## 待拍板：源码已核实的产品问题

定档时发现，均已对照源码确认，未改代码。

1. **动态插拔不重新接线 retry↔breaker**（INV-03）。`Dioman.installPlugins` 才接线（`lib/src/dioman.dart:131-143`），`DiomanHandle.insertBefore/insertAfter/remove` 都不重连：后插入的 breaker 不生效；remove 掉 breaker 后 retry 仍持有被移除的实例并继续向它申请凭据。→ 倾向修。
2. **DiomanKey 显式 key 优先于 builder**（`lib/src/key_plugin.dart:178-181`），与 `DiomanKeyOptions.builder` 注释"优先级高于 key"相反。→ 改代码还是改注释，需要定。
3. **深模式 key 只排序顶层键**（`_encode`，`lib/src/key_plugin.dart`）：嵌套 Map 字段顺序不同会生成不同 key，相同请求可能缓存/去重不命中。→ 倾向修。
4. **DiomanCache 按 HTTP 2xx 写入，不看业务码**（`lib/src/cache_plugin.dart:394-396`）。这是 SKILL 文档写明的设计（存原始信封，命中后再经 normalize），HTTP 200 + 业务失败也会入缓存，后续命中都直接复现失败、不再打到服务端。真实用例 `cache.business-failure-not-cached` 预期不缓存，它通过是因为执行器的 transformer 先把失败转成了异常。→ 设计取舍，需要定。

## P2 清单

**真实执行器缺口**：真实侧没跑到插件自身的分支，PASS 不代表插件被验证。

- 429/503 注入场景一律跳过 → Retry-After（H6）、`DiomanRetry.statusCodes` BLOCKED。解锁：给注入场景开白名单。
- 执行器 `shouldRetry` 永不返回 null → retry 内置状态码/错误类型回落没执行。
- 执行器覆盖 breaker `shouldTrip` → 内置网络错误分类没执行（H3）。
- 执行器 EnvelopeTransformer 先于 DiomanNormalize 抛业务失败 → normalize 拒绝分支没执行。
- `share.policy` 映射缺 `retry`，`none` 被映射成关闭开关 → `DiomanSharePolicy.retry/none` 分支没执行。
- 执行器固定 `offline.maxWait = 0` → 离线排队后重放的路径没执行。
- `cancel.all` 用执行器自带 token，插件不追踪 → `DiomanCancel.cancelAll` 可能没生效。

**缺真实用例的 ② 行**（G4，10 行）：multipart 401 重放、keep-alive 重放（H4）、breaker 网络分类与半开探测取消、cancel 插件 dispose 在途、retry 网络错误类型、share retry 策略、connect/send 超时生效、INV-18 连接复用。

**缺本地单测**（G3，204 行）：多为构造参数、getter、Options 字段没有任何标题引用。先区分"有测但标题 id 没写"（补 id）与"真没测"（补用例）。INV-18（连接复用）、INV-20（缓存命中先于离线判定）本地完全没有单测。

## 已知问题

- `docs/reports/2026-10-27-*.md` 指向 `test/accept/results/…` 的是本地文件，仓库里没有；入库证据统一看 `test/accept/evidence/`。
