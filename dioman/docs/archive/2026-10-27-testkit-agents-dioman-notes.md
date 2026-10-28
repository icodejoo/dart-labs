---
title: testkit 手册里的 dioman 复核笔记（2026-10-27）
status: archived
updated: 2026-10-28
summary: 原写在 api-ws-demo/testkit/AGENTS.md 末尾的两节 dioman 专属记录（五方法复核、测试整理资源定位），2026-10-28 迁回 dioman。
superseded_by: docs/status.md
---

> 原位置：`api-ws-demo/testkit/AGENTS.md`。文中 `dioman/accept/...` 是迁移前的旧路径：执行器现在在 `test/accept/`，MATRIX-plugins 在 `docs/reports/2026-10-27-plugin-matrix.md`，`test/README.md` 现为 `docs/guides/test-layers.md`。

## 2026-10-27 · dioman 五方法复核（部分完成）


本轮入口：dioman/accept/bin/build_plugin_matrix.dart 生成 scenarios/plugins.json；
dioman/accept/bin/run_plugin_matrix.dart 执行方法清单；中文逐格矩阵在 dioman/accept/docs/MATRIX-plugins.md。
完整汇总为 dioman/accept/results/review-summary.json，收尾检查为 verification-review.json；
D16 的 audit.json 保留为历史证据，不代表本轮补齐全部缺声明组合。
新增79个方法场景和2个安全状态子场景后共409场景；校验命令保持 gen-index / validate --check-index。
历史跳过3547格复核后，70格在全部网络显式说明禁止主动注入429/503，其中56格原来缺声明；
其余3477格仍未补齐预期和真实执行。单体全部选项、全部原生边界及全部实现不变量尚未穷尽。
share重放准备异常导致跟随者悬挂的修复，真实双风格证据在 share-prepare-real.json。
不得仅因方法清单160格通过，就将整项复核报告为完成。

## 2026-10-27 · 测试整理资源定位

单体与边界场景已归入对应领域文件，plugins.json 保留配对和全量场景；五方法清单在 dioman/accept/lib/plugin_matrix_plan.json。两组等价零值边界已合并，旧 id 映射见 dioman/test/README.md。现有 18 个文件共 407 场景。原 results 证据不重写，新执行证据在 dioman/coverage/accept/。
