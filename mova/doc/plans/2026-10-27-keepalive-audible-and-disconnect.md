# 保活增强：出声保活 + 到期断流

> 2026-10-27 · 计划 · **落地前置：Codex 真机覆盖测试结束、[改名](2026-10-27-rename-controllers-keepalive.md)完成。** 本文用**改名后**的名字，旧名见括号。
> 相关：[standby 计划](2026-10-23-standby-mode.md)、`lib/src/core/standby/`（改名后 `core/keep_alive/`）、`engine.dart` 的 `_enterStandby`/`_expireStandby`/`_degradeStandby`。

## 1. 目标与不做

**目标**
1. **出声保活**：宿主内隐藏画面（滚出视口、被页面盖住、非活跃 Tab）时，不出画面但**继续出声**，让用户知道还在播。
2. **到期断流**：静音保活超过 `maxDuration` 后，真正断开网络连接（现在只是暂停，直播 FLV 暂停仍满速拉流），恢复时重开。

**不做**：切系统后台继续出声（需前台服务 + 媒体会话，另立项）；点播/HLS 的保活（沿用现有规则：点播暂停、HLS 默认暂停）。

## 2. 现状（已读代码确认）

- 保活只碰 mpv 的 `vid` 与 `mute`；`MovaStandbyMode` 目前两值：`muted`（`vid=no`+静音，音频维持时钟）、`decodeOnly`（无声流，照常解码渲染并静音）。
- `maxDuration`（默认 30s）到期走 `_degradeStandby`：`kernel.pause()` → `exitStandby()` → 阶段 `fallback`、原因 `maxDuration`。**只是暂停，连接未断。**
- 已有"暂停且唤醒时重开"的路径（原因 `failed`/`ended`），可复用做"断流后恢复"。
- 守卫进后台时把保活降级为暂停（已有，保持）。

## 3. 设计决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 出声保活的表达 | `MovaKeepAliveMode` 新增 `audible`（`vid=no`，**不**静音）；入口 `MovaHiddenMode.keepAliveAudible`（暂名） | 复用内核只碰 `vid`/`mute` 的不变量；不新增内核方法 |
| 出声保活要不要到期 | **不到期、不断流** | 要持续出声，连接必须在；省的是视频解码 CPU，不是网络 |
| 静音保活到期动作 | 配置 `MovaKeepAliveConfig.onExpire`：`pause`（现状，默认）/ `disconnect` | 默认行为不变，遵循"新功能默认关闭" |
| 断流怎么做 | 到期时停止当前流（具体用 mpv `stop`/卸载，**待 Task 1 实测选型**），阶段 `fallback`、原因 `maxDuration`，标记"唤醒时重开" | 复用现有重开路径 |
| 无声流 + `audible` | 退回普通暂停（沿用 `silentStreams` 规则的判断） | 无声流没有"声音"可保；此前对无声流强制 `vid=no` 会 EOF 重载 |
| 状态可见性 | `MovaState.keepAlivePhase` 不变；`MovaKeepAliveChange` 的 `mode` 带 `audible`，宿主据此显示"后台播放中"提示 | 零新增字段 |

## 4. Task 清单（逐 Task 一个 commit；`flutter analyze lib test` 0 issues + `flutter test` 全绿再往下）

**Task 1 · 真机预研（不改库代码）**
- 在 Android 真机量：(a) 直播 FLV 下 `stop` 与 `pause` 的网络差（`adb shell cat /proc/net/xt_qtaguid/stats` 或 `dumpsys netstats`，**用真实流量计数，不用墙钟**）；(b) `vid=no` 且**不静音**时音频会话/焦点对其他 App 的影响；(c) 无声流的行为。
- 产出写进本文「附录 A」，作为 Task 2/4 选型依据。

**Task 2 · 到期断流（`onExpire: disconnect`）**
- `MovaKeepAliveConfig` 加 `onExpire`（枚举 `MovaKeepAliveExpire{pause, disconnect}`，默认 `pause`）。
- `_degradeStandby` 按配置分支；断流分支复用"唤醒重开"标记。
- 单测：纯决策（`core/keep_alive/plan.dart` 扩）+ 引擎层用 `FakeKernel` 断言 `stop` 被调、唤醒触发重开、直播回边缘；默认配置行为与改前逐字一致（回归）。

**Task 3 · 出声保活模式**
- `MovaKeepAliveMode.audible`；`decideStandbyEntry` 增加分支（无声流 → fallback；PiP/小窗豁免沿用）。
- 内核 `enterStandby(audible)`：只设 `vid=no`，不动 `mute`；还原路径不变。
- `audible` 不启动 `maxDuration` 计时器。
- 单测：决策表（有声/无声/PiP/点播/HLS）、内核属性序列（不碰 mute）、不到期。

**Task 4 · 守卫入口与守卫降级**
- `MovaHiddenMode.keepAliveAudible`；`MovaAutoPauseGate` 的隐藏动作映射；进后台仍降级为暂停（`audible` 不例外）。
- 单测：gate 纯逻辑全分支；`MovaAutoPause` 部件测试（滚出视口 / TickerMode / 路由覆盖）。

**Task 5 · 文档与验证页**
- README「隐藏时保活」补两个新选项；CHANGELOG `Unreleased`；`doc/SPEC.md`；CLAUDE.md 基线。
- 验证页 `example/lib/main_keepalive_audible_verify.dart`（脚本化 `AUTORUN`）。

**Task 6 · Android 真机验证（基于真实事件）**
- 出声保活：隐藏期间 `playing=true`、`state.size` 不再更新、**真有声音**（`dumpsys audio` 的 `players` 状态 + 音量非静音）、唤醒后 `MovaKeepAliveResume.elapsed` 与真正出画面时间；切后台降级为暂停；10 轮进出无泄漏。
- 到期断流：`maxDuration` 后真实网络流量归零（Task 1 的计数法）；唤醒后直播回边缘、首帧时间；`onExpire: pause` 回归不变。

## 5. 测试数量推进（预计）

起点 1472（以改名完成后实跑为准）→ Task 2 +8 → Task 3 +10 → Task 4 +8 → 约 1498。落地时以实测数字回写。

## 6. 风险

- **音频焦点**：出声保活会一直占焦点，可能打断别的 App 声音（Task 1(b) 必测）。
- **断流恢复慢**：重开需握手 + 等关键帧，直播还会丢隐藏期间的内容；因此默认仍是 `pause`，由宿主显式选 `disconnect`。
- **Android 上 `vid=no` 不静音时的 `mediacodec-copy` 行为**未测（standby S7 同类问题仍待真机）。

## 附录 A：Task 1 预研结果

（待填）
