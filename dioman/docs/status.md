---
title: dioman 当前状态
status: active
updated: 2026-11-03
summary: 洋葱管线重构 B0–B8 已完成并提交，gates 全部为 0，无遗留闸门缺口
---

# 当前状态

洋葱管线重构（B0–B8）已全部提交：B0 基线、B1–B5b 管线与切换、B6 文档与性能、B7 新实例全量真实验收、B8 对照 axp 终审补修，另有一次 lib 精简。lib/ 只有洋葱管线实现；入口使用 show 白名单，744 项公开声明见 API 台账。

2026-11-03 复核：`dart analyze`（含 example）无问题，`dart test` 5595 项全过，带 lcov 的 gates 为 G0–G5 全部为 0。线上 Render 全量验收见 [线上验收矩阵](reports/2026-11-03-online-accept-matrix.md)：29 项失败本地对照全部通过，归因线上拓扑，非库缺陷。

## 说明

- connect 超时已有真实证明：`timeout_effective_integration_test.dart` 用只监听不 accept 且队列占满的本地端点让 SYN 被丢弃，真实触发 `connectionTimeout`（不依赖 netem 与外网；平台不丢 SYN 时该用例按跳过处理）。
- 缺能力跳过属设计：dioman 始终归一化业务信封，不具备 `raw-business-code`；整体超时 `timeout-total` 同理，按 `skipped: missing <cap>` 记录，不计为通过。

## 验证入口

```sh
dart analyze
dart analyze example
dart test
dart run test/accept/bin/matrix.dart gates
```

gates 现状见上方复核结论；重跑外部验收按 [执行器手册](guides/accept-runner.md) 指定服务。

## 当前约束

- 设计与终审补充以 pipeline-architecture、pipeline-plugin-spec §8.1 与 C1–C13 为准。
- cache/share 按请求开启；auth 在 source 外层；12 个插件与 setup-only envs。
- 性能不达标或不稳定如实保留；优化由终审决定，B6 不修改 lib。
- 历史设计在 archive；不再将历史报告中的安装顺序作为当前契约。
