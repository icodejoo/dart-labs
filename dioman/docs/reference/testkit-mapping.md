---
title: testkit 与洋葱管线映射
status: active
updated: 2026-10-29
summary: 当前验收客户端的能力、结果与限制
---

# testkit 映射

当前实现以 test/accept/lib/client.dart 和 runner.dart 为准。历史字段转换见 [归档](../archive/testkit-mapping-before-pipeline.md)，其中拦截器与错误映射已失效。

| 契约 | 当前映射 |
|---|---|
| 请求 | Dioman 动词方法，query 与 DiomanCall |
| auth | DiomanAuth、DiomanTokenManager；回调接收归一化结果 |
| cache | DiomanCache；TTL 使用 Duration；执行器省略覆盖时显式开启，库默认仍 optIn |
| share | DiomanShare；省略覆盖时执行器显式开启；none 中立值映射为 false |
| retry | DiomanRetryOptions；仅注入状态重试，避免恢复非注入服务错误 |
| mock | source 阶段 DiomanMock；探测与真实回落分开 |
| normalize | DiomanResponseFactory；业务与 HTTP 共用逻辑状态 |
| key/cancel/log | DiomanKeyOptions、DiomanCall.key、cancelAll、debug；无需插件 |
| loading/notify | 最外层逻辑调用；silent 与取消按默认规则抑制通知 |
| timeout | DiomanTimeout 与 Dio 三超时；不支持 total_ms，明确拒绝该字段 |
| 失败 | DiomanResponse.kind、reason、status、httpStatus；程序错误原样抛出 |

宿主映射与库默认行为有区别：testkit 的默认 cache/share 能力由执行器开启；filter 仍按中立契约显式开关。不要把执行器的注入判定、能力名和字段转换当成公开库 API。

真实执行步骤见 [手册](../guides/accept-runner.md)。connect 超时、HTTP 日期 Retry-After 的真实环境限制保留在状态与历史证据，不扩大 PASS 范围。
