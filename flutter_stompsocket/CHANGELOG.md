## 0.1.1

- **Fix: 二进制误判导致文本消息解析失败。** `stomp_dart_client` 的 parser 在
  `content-type` 为 `application/octet-stream` **或缺失**时都会把 body 归入
  `binaryBody`——而 ActiveMQ 等服务端常不写 `content-type`，导致纯 JSON 文本也
  被当成二进制、走进 `binaryDecoder`（没配就直接解析失败）。现在：显式标注
  `octet-stream` 才走二进制快路径；其余一律先做严格 UTF-8 解码探测，成功就走
  文本解析，只有结构上违反 UTF-8（压缩/真二进制数据）才落回 `binaryDecoder`。
- **Fix: 大包异步解析期间断线重连，可能对旧会话误发 ACK/NACK。** smart 模式的
  自动应答原本没有会话代次校验（manual 模式已有）：一个大包在后台 isolate 解析
  期间断线又重连，`_onConnect` 复用同一批 `_Subscription` 对象导致
  `identical()` 检查通过，`client.connected` 也变回 true，于是照常发出携带**旧
  会话** ack id 的 ACK/NACK，服务端认不出来。现在在消息到达时捕获会话代次，
  贯穿 `_dispatch`/`_sendAck`，代次变了就跳过应答。
- **Change: `resumeOnForeground` 默认值改为 `true`**（对齐 `@codejoo/stomp`）。
  移动端恰恰是回前台重连最要紧的场景（系统会挂起后台定时器），默认关闭反而
  反直觉。仍需运行在已初始化 `WidgetsBinding` 的 Flutter App 中；纯 Dart 场景
  可显式设为 `false`。
- **Fix: 自动去重键的分隔符会截断 STOMP 帧。** 不传 `id` 时用于合并订阅的确定性
  键会被当作 STOMP 的 `id` 头发上线，原来用 `\x00` 分隔——NUL 是 STOMP 帧终止
  符，出现在 header 里会把整帧从中间截断（服务端报 "malformed frame"）。改用
  `\x1f`（单元分隔符），同 `@codejoo/stomp` 的修法。

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
