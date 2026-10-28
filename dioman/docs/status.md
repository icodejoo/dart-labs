---
title: dioman 当前状态与待办
status: active
updated: 2026-10-28
summary: 测试体系落地进度（P0–P3）、闸门现状、待拍板的产品问题与 P2 补测清单，只写现在。
---
## TL;DR

P0 搭账、P1 定档已完成，定档时发现的 4 条产品问题已修复。总账 443 行全部定档，G0/G1/G2 清零。剩余 G3 199（行无单测）、G4 20（② 行缺真实用例）、G5 28（外部 testkit 新增场景未归行）是 P2 清单。

## 进度

| 阶段 | 状态 | 结果 |
|---|---|---|
| P0 搭账 | 完成 | `test/accept/lib/matrix.dart` + `test/accept/bin/matrix.dart`（sync/gates/evidence/results）；默认运行带静态闸门 `test/integration/matrix_integration_test.dart` |
| P1 定档 | 完成 | 443 行：① 411、② 30、③ 2（含 26 条 INV 不变量行）；假设 H1–H8 见 `test/ASSUMPTIONS.md`；结论回填 140 行，② ③ 行 PASS 20、BLOCKED 2 |
| P2 补测 | 未开始 | 见下方清单 |
| P3 收口 | 部分完成 | 文档归入 docs/、accept 并入 test/accept/、证据汇总入库 `test/accept/evidence/`；剩 `docs/guides/test-layers.md` 补三档/总账章节 |

闸门：`dart run test/accept/bin/matrix.dart gates --lcov=coverage/local.info`（lcov 用 `dart test --coverage-path=coverage/local.info` 生成）

| G0 未定档 | G2 API | G3 无单测 | G4 真实侧 | G5 反查 |
|---:|---:|---:|---:|---:|
| 0 | 0 | 199 | 20 | 28 |

## 已修复：定档时发现的产品问题（2026-10-28，见 CHANGELOG Unreleased）

1. **动态插拔不重新接线 retry↔breaker** → 接线集中到 `_wireChain`/`_unwire`（`lib/src/dioman.dart`），安装与每次插拔都重算；移除只清指向被移除实例的引用，手动接的外部 breaker 保留。`DiomanRetry.breaker` 改为可读字段。
2. **DiomanKey 显式 key 优先于 builder** → 按注释改为 请求级 builder > 请求级 key > 插件级 builder > 计算。
3. **深模式 key 只排序顶层键** → 递归排序 Map、List 保序。含嵌套 Map 的请求 key 会变，已持久化缓存会失效一次。
4. **DiomanCache 缓存 HTTP 200 业务失败** → 新增 `shouldStore`（插件级 + 请求级）；同一 Dio 装了 normalize 时自动接入 normalize 自己的拒绝判定（与其 onResponse 共用 `_resolveEnvelope`）。

顺带修了台账工具：`test/accept/bin/inventory.dart` 现在按 barrel 的 `show`/`hide` 取公共 API（之前 `hide` 掉的内部胶水函数会被误收）。

## P2 清单

**外部 testkit 新增 28 个场景未归行**（G5 real-orphan）：2026-10-28 发现 `api-ws-demo/testkit/scenarios` 新增了 `*.single-*`、`combo.cache-mock-*` 等场景，基线已显式放行一次（`--allow-grow`），需逐个挂到矩阵行。

**真实执行器缺口**：真实侧没跑到插件自身的分支，PASS 不代表插件被验证。

- 429/503 注入场景一律跳过 → Retry-After（H6）、`DiomanRetry.statusCodes` BLOCKED。解锁：给注入场景开白名单。
- 执行器 `shouldRetry` 永不返回 null → retry 内置状态码/错误类型回落没执行。
- 执行器覆盖 breaker `shouldTrip` → 内置网络错误分类没执行（H3）。
- 执行器 EnvelopeTransformer 先于 DiomanNormalize 抛业务失败 → normalize 拒绝分支没执行。
- `share.policy` 映射缺 `retry`，`none` 被映射成关闭开关 → `DiomanSharePolicy.retry/none` 分支没执行。
- 执行器固定 `offline.maxWait = 0` → 离线排队后重放的路径没执行。
- `cancel.all` 用执行器自带 token，插件不追踪 → `DiomanCancel.cancelAll` 可能没生效。

**缺真实用例的 ② 行**（G4，10 行）：multipart 401 重放、keep-alive 重放（H4）、breaker 网络分类与半开探测取消、cancel 插件 dispose 在途、retry 网络错误类型、share retry 策略、connect/send 超时生效、INV-18 连接复用。

**缺本地单测**（G3，199 行）：多为构造参数、getter、Options 字段没有任何标题引用。先区分"有测但标题 id 没写"（补 id）与"真没测"（补用例）。INV-18（连接复用）、INV-20（缓存命中先于离线判定）本地完全没有单测。

## 已知问题

- `docs/reports/2026-10-27-*.md` 指向 `test/accept/results/…` 的是本地文件，仓库里没有；入库证据统一看 `test/accept/evidence/`。
