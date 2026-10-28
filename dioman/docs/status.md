---
title: dioman 当前状态与待办
status: active
updated: 2026-10-28
summary: 测试体系落地进度（P0–P3）、闸门现状、已修复问题与剩余待办，只写现在。
---
## TL;DR

P0、P1 完成，P2 的单测部分完成：G0/G1/G2/G3/G5 全部清零，基线只剩 G4 的 20 项（10 行 ② 档缺真实用例）。剩下的都在真实侧：补 10 行真实用例、修 7 处执行器缺口、testkit 场景里对 429/503 的显式 skip（外部仓库）。

## 进度

| 阶段 | 状态 | 结果 |
|---|---|---|
| P0 搭账 | 完成 | `test/accept/lib/matrix.dart` + `test/accept/bin/matrix.dart`（sync/gates/evidence/results）；默认运行带静态闸门 `test/integration/matrix_integration_test.dart` |
| P1 定档 | 完成 | 443 行：① 411、② 30、③ 2（含 26 条 INV 不变量行）；假设 H1–H8 见 `test/ASSUMPTIONS.md`；结论回填 140 行，② ③ 行 PASS 20、BLOCKED 2 |
| P2 补测 | 单测完成，真实侧进行中 | G3 199→0（补 id 约 30 行、新写用例约 170 行，测试 390→524 条）；G5 外部新增 31 个场景已归行；执行器放行注入的 429/503、映射请求级 filter（testkit D19）；H6 经 413 注入部分核对 |
| P3 收口 | 完成 | 文档归入 docs/、accept 并入 test/accept/、证据汇总入库 `test/accept/evidence/`、test-layers 补三档/总账章节 |

闸门：`dart run test/accept/bin/matrix.dart gates --lcov=coverage/local.info`（lcov 用 `dart test --coverage-path=coverage/local.info` 生成）

| G0 未定档 | G2 API | G3 无单测 | G4 真实侧 | G5 反查 |
|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 20 | 0 |

## 已修复：定档时发现的产品问题（2026-10-28，见 CHANGELOG Unreleased）

1. **动态插拔不重新接线 retry↔breaker** → 接线集中到 `_wireChain`/`_unwire`（`lib/src/dioman.dart`），安装与每次插拔都重算；移除只清指向被移除实例的引用，手动接的外部 breaker 保留。`DiomanRetry.breaker` 改为可读字段。
2. **DiomanKey 显式 key 优先于 builder** → 按注释改为 请求级 builder > 请求级 key > 插件级 builder > 计算。
3. **深模式 key 只排序顶层键** → 递归排序 Map、List 保序。含嵌套 Map 的请求 key 会变，已持久化缓存会失效一次。
4. **DiomanCache 缓存 HTTP 200 业务失败** → 新增 `shouldStore`（插件级 + 请求级）；同一 Dio 装了 normalize 时自动接入 normalize 自己的拒绝判定（与其 onResponse 共用 `_resolveEnvelope`）。

顺带修了台账工具：`test/accept/bin/inventory.dart` 现在按 barrel 的 `show`/`hide` 取公共 API（之前 `hide` 掉的内部胶水函数会被误收）。

## P2 清单

**真实执行器缺口**：真实侧没跑到插件自身的分支，PASS 不代表插件被验证。

- ~~429/503 注入场景一律跳过~~ → 2026-10-28 执行器已放行（按响应体 `reason: injected` 区分，真实过载仍整轮停止）。但 testkit 的 `retry.429-retried`、`retry.503-retry-after`、`retry.respects-retry-after-over-delay` 在**场景 JSON 里显式写了 skip**（外部仓库 `api-ws-demo/testkit/scenarios/retry.json`，另有 faults.json、basic.json），需要那边去掉。
- 执行器 `shouldRetry` 永不返回 null → retry 内置状态码/错误类型回落没执行。
- 执行器覆盖 breaker `shouldTrip` → 内置网络错误分类没执行（H3）。
- 执行器 EnvelopeTransformer 先于 DiomanNormalize 抛业务失败 → normalize 拒绝分支没执行。
- `share.policy` 映射缺 `retry`，`none` 被映射成关闭开关 → `DiomanSharePolicy.retry/none` 分支没执行。
- 执行器固定 `offline.maxWait = 0` → 离线排队后重放的路径没执行。
- `cancel.all` 用执行器自带 token，插件不追踪 → `DiomanCancel.cancelAll` 可能没生效。

**缺真实用例的 ② 行**（G4，10 行）：multipart 401 重放、keep-alive 重放（H4）、breaker 网络分类与半开探测取消、cancel 插件 dispose 在途、retry 网络错误类型、share retry 策略、connect/send 超时生效、INV-18 连接复用。

**闸门的已知弱点**：拆出来的 `#子点` 行与原行共用 api id，原行的单测会让子行也过 G3。例如 `DiomanTimeouts.connect#effective` 只有"配置写入"的单测，没有"超时真的生效"的测试。`TestServer` 是真实回环 HTTP，receive/send 超时可以在本地真测（H5 的一部分）。

**库行为建议**（未改）：testkit 中立语义要求 filter 剔除 NaN，`DiomanFilter` 默认不剔除；而 `jsonEncode(double.nan)` 会抛错，默认剔除 NaN 更安全。

## 文档与源码不一致（P2 补测时发现，未改代码）

- `lib/src/auth_plugin.dart:101` 注释称自定义 `ready` 不暂存裸 token，但第 592 行无条件暂存 → 注释过时。
- `.claude/skills/dioman/SKILL.md:93` 仍描述旧的 `_replayDio`、重放响应绕过后续链；现行 `replay_support.dart` 复用宿主传输并手动执行后续响应处理 → 技能说明过时。
- `lib/src/envs_plugin.dart:95-99` `apply` 注释称由管理器调用，但 `installPlugins` 不调用 `envs.apply` → 注释与安装入口不一致。
- `lib/src/mock_plugin.dart:17-21` `defaultFallback` 只传 error 时对所有非取消错误返回 true（含 500 badResponse），说明里写的"网络层错误"比实际窄。

## 已知问题

- `docs/reports/2026-10-27-*.md` 指向 `test/accept/results/…` 的是本地文件，仓库里没有；入库证据统一看 `test/accept/evidence/`。
