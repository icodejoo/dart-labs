## 0.1.0

- 首次发布。对 `stomp_dart_client` 的二次封装，提供：
  - 函数队列共享解析（相同 id 的多回调共用一份解析数据）
  - 三种取消：句柄 `unsubscribe()` / 按 id / 按 destination / `clear()`
  - 断线自动重连（库）+ 重连后自动重新订阅（本封装）
  - `send()` + 未连接离线缓冲
  - `AckMode { auto, smart, manual }`：不应答 / 自动应答 / 手动应答（`AckControl`）
  - 可注入的二进制解码器 `binaryDecoder`
  - `beforeConnect` 连接前刷新 token
  - 连接状态 `ValueListenable` + `onStateChanged`
  - `resumeOnForeground`：回前台强制重连
  - `copyWith` 与 `stomp_dart_client` 原生参数透传
