# flutter_stompsocket demo / 双语演示

[Live demo / 在线演示](https://icodejoo.github.io/dart-labs/stompsocket/) · [pub.dev](https://pub.dev/packages/flutter_stompsocket) · [Package source / 包源码](https://github.com/icodejoo/dart-labs/tree/main/flutter_stompsocket) · [README](https://github.com/icodejoo/dart-labs/blob/main/flutter_stompsocket/README.md)

Self-contained `lib/demo_kit/`, copied from the countman pilot. No new dependencies.
Version chip reads the packaged `../pubspec.yaml` asset, so it follows the package version.

完整复制 countman 试点的自包含 `lib/demo_kit/`，没有新增依赖。版本 chip 直接读取打包的包级 `../pubspec.yaml`，不维护另一份版本常量。

## Run / 运行

```sh
cd flutter_stompsocket/example
flutter pub get
flutter run -d chrome
flutter build web --release --base-href /dart-labs/stompsocket/
```

Language priority: `?lang=zh|en` → browser locale → English. Header provides language/theme controls, pub.dev, GitHub and README links. Hash routes restore the selected page; browser back/forward is supported.

语言优先级：`?lang=zh|en` → 浏览器语言 → 英语。页头支持中英切换、系统明暗主题及手动切换、三个外链；hash 恢复当前页，支持浏览器前进后退。

Examples / 示例：`?lang=zh#/pages/subscribe`、`?lang=en#/pages/send`。

## Pages & audit / 页面与审计

| Route / 路由 | Page / 页面 | Current behavior / 当前行为 |
| --- | --- | --- |
| `connection` | Connection / 连接 | Offline timed lifecycle, optional real STOMP broker, reversible stop/resume / 离线计时预览、可选真实 STOMP broker、可逆停止与恢复 |
| `subscribe` | Subscriptions / 订阅 | auto/smart/manual, callbacks, manual ACK/NACK, unsubscribe and clear / 确认模式、接收回调、手动 ACK/NACK、取消与清空 |
| `send` | Send & buffer / 发送与缓冲 | Text, JSON values, binary and no-body sends, offline buffer / 文本、JSON 值、二进制及无消息体发送、离线缓冲 |
| `config` | API reference / 配置参考 | Constructor defaults, callbacks and public methods / 构造默认值、回调与公开方法 |

All four original pages are retained and rebuilt with responsive grids. Duplicate log/code panels are consolidated into `SessionLog` and `CodeBlock`. The old custom shell and global `stomp_state.dart` are replaced by an application-owned `DemoSession`. No original benchmark or native-only page existed, so none was removed or relocated.

原有四页全部保留并重做为响应式网格；重复日志/代码区合并为 `SessionLog`、`CodeBlock`。旧自定义壳和全局 `stomp_state.dart` 改为应用管理生命周期的 `DemoSession`。原例没有压测或仅原生页面，无删除或迁移的基准入口。

Corrected against current lib, README and CHANGELOG / 对照当前 lib、README、CHANGELOG 修正：

- `resumeOnForeground` defaults to **true**, not false / 默认 **true**。
- `ParsedMessage` accepts all JSON values, including null; invalid JSON is raw text. Binary decoder results are not restricted to Map / 不再声称回调只接收 Map；非法 JSON 原样传递，二进制解码结果类型也不限 Map。
- `smart` ACKs after **all synchronous callbacks** succeed, NACKs on any throw. It does not await async work / 全部同步回调成功才 ACK，任一抛错就 NACK，不等待异步业务。
- Real disconnected sends now actually call `socket.send()`, letting the library buffer them / 修复只记录“已入队”却没有调用真实 API 的演示问题。
- Clear-all now calls `socket.clear()`; each handle cancels one registration. ACK mode is captured at registration; multiple pending manual messages retain their handles / 清空调用真实 `clear()`，句柄精确取消回调；确认模式固定在注册时，连续消息不覆盖待确认句柄。
- Stop shows `disconnected`, retains subscriptions/outbox, and can resume. Replay creates a fresh instance and drops the old outbox / 停止显示 `disconnected`，保留订阅与缓冲且可恢复；重放创建新实例并丢弃旧缓冲。
- Browser upgrade headers and WebSocket ping are unavailable; Web `compute` stays on the current event loop / 明确浏览器握手头、ping 限制及 Web 的 compute 行为。
- No historical release narrative or static performance numbers are displayed / 页面不展示历史版本说明与旧性能数字。包级 README 中旧安装版本不属于本任务可修改范围。

## Replay / 重放

Every evolving card has a Replay tooltip/button, wired through `DemoCard.onReplay` before remounting its local child:

每张状态演进卡片都有“重放/Replay”，通过 `DemoCard.onReplay` 清理外部状态后再重新挂载主体：

- Connection lifecycle and broker settings: cancel timers, stop socket, remove subscriptions, discard outbox and reset status; broker-settings replay also clears credentials / 连接与设置：取消计时、断连、清理订阅和缓冲、恢复状态；设置卡还会清空凭据。
- Subscription editor and delivery/ACK: clear all registrations; editor replay restores its form / 订阅与消息：清空全部登记，编辑器重放恢复表单。
- Send editor and offline buffer: fresh session, reset attempts and buffer; editor replay restores body type/text / 发送与缓冲：全新会话、清零请求与缓冲，编辑器恢复类型与正文。
- Session log: clear events; card information dialogs can always be reopened / 日志：清空事件；卡片详情弹层可重复打开。

Static contracts, body encoding and API reference cards have no replay button.

静态约定、编码说明及配置参考卡片不加重放。

## Preview vs broker / 预览与真实连接

Preview never opens a socket: connect takes 0.5s, reconnect takes 2s. These times illustrate state changes, not broker latency. Preview subscriptions receive messages only when “Deliver preview” is pressed. Preview queue count is illustrative; real outbox length has no public API and is not fabricated. Mode changes discard the previous session.

预览不访问网络：连接 0.5 秒、重连 2 秒，仅用于展示状态变化；点“投递预览消息”才产生模拟收件。预览待发数是示意，真实缓冲无公开计数 API，不伪造数字。切换模式会清理旧会话。

Real mode requires your own STOMP endpoint. Use `wss://` from HTTPS, configure broker Origin access, and use CONNECT login/passcode as needed. No public broker is contacted automatically. Credentials are not inserted into code or logs. Replay is needed to change an existing connection's address/credentials.

真实模式需要自己的 STOMP 端点；HTTPS 页面使用 `wss://`，broker 需允许页面 Origin，按需填写 CONNECT login/passcode。不自动访问公共 broker，不把凭据写入日志或代码；修改已有连接地址/凭据前请重放。

## Validation / 验证

```sh
cd flutter_stompsocket
flutter analyze --no-fatal-infos
flutter test
cd example
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --base-href /dart-labs/stompsocket/
```

Widget coverage includes all pages in English/Chinese at 375×667 and 1440×900; URL locale, hash/history, themes, grid spans/equal heights, code copying, native link copying, preview timers/cancellation, manual ACK/NACK, real API call recording, offline sends, JSON validation, all body types, cross-page state and replay cleanup. The real-call tests inject a recording client; they do not connect to a remote broker.

Widget 测试覆盖四页在 375×667、1440×900 的中英文布局，以及语言、hash/历史、明暗、网格跨度/等高、代码/链接复制、预览计时与取消、手动确认、真实 API 调用记录、离线发送、JSON 校验、载荷类型、跨页状态及重放清理。真实调用测试注入记录客户端，不连接远程 broker。

Verified on Flutter 3.47.0 / Dart 3.13.0: package and example analysis reported `No issues found!`; package tests: 66 passed; example tests: 38 passed, including a full-shell width sweep from 360 to 1600. Release web build passed, including the Wasm dry run.

在 Flutter 3.47.0 / Dart 3.13.0 实测：包与 example analyze 均为 `No issues found!`；包测试 66 项、example 测试 38 项全过，含完整页面 360–1600 宽度扫描；release web 构建与 Wasm dry run 成功。

`main.dart.js` measured with the same release command, gzip level 9 / 同一 release 命令构建，gzip 使用级别 9：

| Revision / 实现 | Raw bytes / 原始字节 | Gzip bytes / 压缩字节 |
| --- | ---: | ---: |
| Before migration / 迁移前 | 2,600,027 | 766,754 |
| After migration / 迁移后 | 2,667,002 | 789,383 |

Gzip increased by 22,629 bytes (+2.95%). Local ignored evidence: `build/demo_tests.log`, `build/demo_web_build.log`, `build/demo_size.json`.

gzip 增加 22,629 字节（+2.95%）。本地已忽略的验证记录位于上述三个 build 文件。

Deployment path was checked against `main:.github/workflows/deploy-stompsocket.yml`; no workflow change is needed. Chrome DevTools MCP was unavailable in this session; browser smoke testing and screenshots were not performed, and existing browser tabs were untouched.

已从 `main:.github/workflows/deploy-stompsocket.yml` 核实部署子路径，无需改 workflow。本轮 chrome-devtools MCP 不可用，未执行浏览器冒烟或截图，未操作已有标签页。

Local demo_kit changes: constrain long project names in the header, add the external-reset `onReplay` callback, and use “重放” for the Chinese tooltip. See `lib/demo_kit/README.md`.

demo_kit 本地副本修正长项目名的页头宽度约束，增加外部状态重置回调 `onReplay`，中文提示统一为“重放”，详见该目录 README。
