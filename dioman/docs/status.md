---
title: dioman 当前状态
status: active
updated: 2026-10-29
summary: B0–B5b 已提交，B6 文档与性能验证，B7 待终审
---

# 当前状态

B0–B5b 已终审提交，当前 HEAD 为 cb0cd2f。lib/ 只有洋葱管线实现；入口使用 show 白名单，744 项公开声明、成员与参数见 API 台账。

B6 更新使用文档、迁移指南、Flutter/命令行示例、文档编译测试及交错性能证据。验证和实测结论见 [B6 报告](reports/2026-10-29-pipeline-b6.md)，本批不修改库代码、版本号，也不提交或发布。B7 终审尚未进行。

## 验证入口

```sh
dart analyze
dart analyze example
dart test
dart run test/accept/bin/matrix.dart gates
```

G0/G1/G2/G3/G5 沿用 B5b 基线。本批 gates 的 G4 为 190 项既存真实侧缺口，B6 不执行外部验收；其中 connect 超时仍受可控网络环境限制，不把本地 fake 或连接拒绝当作超时证明。重跑外部验收按 [执行器手册](guides/accept-runner.md) 指定服务。

## 当前约束

- 设计与终审补充以 pipeline-architecture、pipeline-plugin-spec §8.1 与 C1–C13 为准。
- cache/share 按请求开启；auth 在 source 外层；12 个插件与 setup-only envs。
- 性能不达标或不稳定如实保留；优化由终审决定，B6 不修改 lib。
- 历史设计在 archive；不再将历史报告中的安装顺序作为当前契约。
