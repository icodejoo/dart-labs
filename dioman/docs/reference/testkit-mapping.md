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
| 请求 | 场景使用 Dioman.send，query 与 DiomanCall；动词方法另有真实回环核对 |
| auth | DiomanAuth、DiomanTokenManager；auth:true 映射强制保护选项；刷新回调缺凭证时直接失败 |
| cache | DiomanCache；TTL 使用 Duration；执行器省略覆盖时显式开启，库默认仍 optIn |
| share | DiomanShare；省略覆盖时执行器显式开启；none 中立值映射为 false |
| retry | DiomanRetryOptions；仅注入状态重试，避免恢复非注入服务错误 |
| mock | source 阶段 DiomanMock；探测与真实回落分开 |
| normalize | DiomanResponseFactory；业务与 HTTP 共用逻辑状态 |
| key/cancel/log | DiomanKeyOptions、DiomanCall.key、cancelAll、debug；无需插件；中立 key 开关安装后按请求显式启用 |
| loading/notify | 最外层逻辑调用；silent 与取消按默认规则抑制通知 |
| timeout | DiomanTimeout 与 Dio 三超时；不支持 total_ms，装配前按缺 timeout-total 跳过 |
| offline | 旁路探测，原生 maxWait=Duration.zero，探测失败立即以 offline 结束 |
| 可选能力 | 不声明 raw-business-code、timeout-total；缺能力在发请求前跳过 |
| 失败 | DiomanResponse.kind、reason、status、httpStatus；程序错误原样抛出 |

宿主映射与库默认行为有区别：testkit 的默认 cache/share 能力由执行器开启；filter 仍按中立契约显式开关。不要把执行器的注入判定、能力名和字段转换当成公开库 API。

真实执行步骤见 [手册](../guides/accept-runner.md)。connect 超时、HTTP 日期 Retry-After 的真实环境限制保留在状态与历史证据，不扩大 PASS 范围。

B8 裁决后，biz 的 error 比较直接读取 `business:${r.code}`；不由执行器判定业务码。Dio unknown 的解码 FormatException 归 parse；执行器显式使用 expectJson=true，HTML 归 parse（库默认工厂仍接受 HTML 文本）；share 单一预算场景声明 timeout-total 后按缺能力跳过。只保留旧链路排除 offline 通知的计数差异为“不适用”，既有两格对账见 [B7 报告](../reports/2026-10-29-pipeline-b7.md)，本次重跑见 [B8 报告](../reports/2026-10-29-pipeline-b8.md)。