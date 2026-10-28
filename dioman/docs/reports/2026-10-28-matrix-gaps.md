---
title: 测试总账矩阵缺口报告
status: active
updated: 2026-10-28
summary: 总账五道闸门的当前缺口清单与按插件分布，是补测的基线。
---

G1 已检查 lcov。

| 闸门 | 缺口数 |
|---|---:|
| G0 | 0 |
| G1 | 0 |
| G2 | 0 |
| G3 | 0 |
| G4 | 21 |
| G5 | 0 |

## 按插件汇总

| 插件 | G2 | G3 | G0 |
|---|---:|---:|---:|

## 完整缺口

<details>
<summary>G0（0）</summary>


</details>

<details>
<summary>G1（0）</summary>


</details>

<details>
<summary>G2（0）</summary>


</details>

<details>
<summary>G3（0）</summary>


</details>

<details>
<summary>G4（21）</summary>

- `G4:DiomanAuth.dio#transport-reuse:no-real`
- `G4:DiomanAuth.dio#transport-reuse:no-result`
- `G4:DiomanAuth.onError#multipart-replay:no-real`
- `G4:DiomanAuth.onError#multipart-replay:no-result`
- `G4:DiomanBreaker.onError#cancel-probe:no-real`
- `G4:DiomanBreaker.onError#cancel-probe:no-result`
- `G4:DiomanBreaker.onError#network-classification:no-real`
- `G4:DiomanBreaker.onError#network-classification:no-result`
- `G4:DiomanCancel.dispose#inflight:no-real`
- `G4:DiomanCancel.dispose#inflight:no-result`
- `G4:DiomanRetry.statusCodes#network-type:no-real`
- `G4:DiomanRetry.statusCodes#network-type:no-result`
- `G4:DiomanSharePolicy.retry:no-real`
- `G4:DiomanSharePolicy.retry:no-result`
- `G4:DiomanTimeouts.connect#effective:no-real`
- `G4:DiomanTimeouts.connect#effective:no-result`
- `G4:DiomanTimeouts.send#effective:no-real`
- `G4:DiomanTimeouts.send#effective:no-result`
- `G4:INV-11:fail`
- `G4:INV-18:no-real`
- `G4:INV-18:no-result`

</details>

<details>
<summary>G5（0）</summary>


</details>

