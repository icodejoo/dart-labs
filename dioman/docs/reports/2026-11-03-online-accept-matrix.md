---
title: dioman 线上全量验收矩阵 2026-11-03
status: active
updated: 2026-11-03
summary: 对 Render 线上部署（经本机 netem TLS 转发）跑全量 testkit 场景，29 项失败逐项对照本地全部通过，归因线上拓扑。
---

# 线上全量验收矩阵

## 环境

- 服务：`https://api-ws-demo-latest.onrender.com`，带 `TESTKIT_TOKEN`（`x-testkit-token`，绕过限流，不入库）。
- 代理：本机 netem（`--control 127.0.0.1:47190`，需带 `tls` 特性构建），upstream 写 `https://host`，netem 做 TLS 并改写 Host。
- 执行器：`dart run test/accept/bin/cli.dart --jobs=1`，全部网络 × 风格。执行器改动见 `test/accept/lib/common.dart`：https 上游保留 scheme、`ServiceGuardAdapter` 带 token 头。
- 原始数据：`coverage/accept/online-full.json`（本地，不入库）。

## 总览

| 通过 | 失败 | 跳过 | 合计 |
|---|---|---|---|
| 1251 | 29 | 5146 | 6426 |

跳过 5146：4708 为场景未声明该网络或风格；252 缺 raw-business-code、168 缺 timeout-total（dioman 能力缺口，单独跟踪）；其余为场景自带的"不适用"理由。跳过不计为通过。

## 失败归因（29 项）

| 类 | 场景 | 项数 | 线上现象 | 归因 |
|---|---|---|---|---|
| 断连 | faults.close-network / close-parallel / post-close-no-double-send / recovery-after-bad、retry.network-error-retried / post-network-no-retry | 14 | 预期 network，实际 http:502（retry 计数多出是 502 被重试） | Render 反向代理吞掉连接错误换成 502 |
| 并发与取消 | conc.barrier-asc / 32-peak / 64-desc-order、combo.cancel-logger-cleanup | 7 | 到达顺序错位；服务端 aborted=0 | 边缘网络下顺序与取消传播不确定 |
| 弱网与 dns | auth.expired-refresh-replay、basic.sequential-hits、cancel.single、faults.hang-timeout、faults.close-network / recovery-after-bad（weak） | 8 | timeout、network 失败、inflight=1 | 线上延迟叠加弱网档 |

## 本地对照

本机 47081 起同版本 api-ws-demo + netem（47091），同场景在 normal、weak、dns 三档重跑：48 通过 / 0 失败 / 36 跳过；29 项线上失败逐项核对，全部本地通过。结论：不是 dioman 缺陷，是线上拓扑不适合精确断言（与 testkit D6 一致）。

## 后续

- 线上只作冒烟与 normal 档参考；断连、并发顺序、取消传播类以本地为准。
- 可选：在场景里给这三类标注"线上不适用"，让线上矩阵不再出现已知失败。
- 缺口 raw-business-code、timeout-total 并入 P2 补测。
