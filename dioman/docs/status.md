---
title: dioman 当前状态
status: active
updated: 2026-11-03
summary: B0–B8 已合入 main；第二轮（对照 axp 新版）在 jelon/dioman-round2 推进，R0–R3 完成，下一批 R4
---

# 当前状态

洋葱管线 B0–B8 已合入 main（`5e883c8`），尚未发布：pub.dev 上仍是旧拦截器版 0.7.2。

第二轮在分支 `jelon/dioman-round2` 上推进，工作区是 `E:\workspaces\dart-labs-dioman`（sparse worktree，只含 dioman）。依据：[第二轮方案](design/pipeline-round2-plan.md)、[决策 0002](decisions/0002-response-contract.md)。

| 批 | 内容 | 状态 |
|---|---|---|
| R0 | 契约定稿：0002、设计文档改成目标状态 | 完成 |
| R1 | 生命周期与作用域（auth 会话、loading 共享、extend(dio:)） | 完成，见 [R1 报告](reports/2026-11-03-round2-r1.md) |
| R2a | 契约对齐 axp 0002 | 完成，见 [R2a 报告](reports/2026-11-03-round2-r2a.md) |
| R2b | 收口与发版前必修（去掉 dart:io 直接依赖等） | 完成，见 [R2b 报告](reports/2026-11-03-round2-r2b.md) |
| R3 | 原生数据瘦身 | 完成，见 [R3 报告](reports/2026-11-03-round2-r3.md) |
| R4 | 性能（先补 B6 欠下的复测） | 下一批 |
| R5、R6 | Dart 化 API、测试与工程收尾 | 未开始 |

## 验证入口

```sh
dart analyze
dart analyze example
dart test
dart run test/accept/bin/matrix.dart gates
```

闸门 G0/G1/G2/G3/G5 必须保持通过；G4 唯一缺口仍是 connect 握手超时（外部环境限制）。真实验收按[执行器手册](guides/accept-runner.md)起独立实例，不动 47080/47090。

## 当前约束

- 设计文档（架构、插件规格、测试方案）已写成第二轮目标状态，并标注了批次；尚未落地的批次以现有代码为准。
- 改 `lib/src/` 前必读 `.claude/skills/dioman/SKILL.md`。
- 代码由 Codex 落地，主会话逐批终审后提交；不新增依赖，SDK 保持 `^3.5.0`。
