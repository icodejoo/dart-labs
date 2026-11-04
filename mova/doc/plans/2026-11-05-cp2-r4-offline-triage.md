# CP2 第四轮离线定性与夹具交接

2026-11-05；本人执行，未转派。工作目录为 detached worktree `E:\workspaces\wt-mova-cp2fix\mova`，测试起点 2404。证据树 `E:\workspaces\wt-mova-cp2\mova` 全程只读，只读取结果报告“第四轮”和相应原始 JSON、夹具源码；不使用真机。

## pod nowait：设计即如此，夹具判据错误（选 a）

`CP2.pod2.nowait.ad2.0–9` 的 10 条 epoch0/1/2 均为 0，原生 path 已从 ad.mp4 切到 ad2.mp4，且有按源归属的独立首帧。wait 组 10/10 PASS，epoch 为 0→1→2。

依据：

- `lib/src/core/options/ad_config.dart`：MovaAdWaitByKind 前/后贴片默认 false；注释明确“不等待”回到普通打开行为。`waitsFor` 由广告位覆盖值优先、否则配置策略裁决。
- `lib/src/core/session/session.dart`：`_wantsWait` 同时检查切换能力和 `waitsFor`；`_playAd` 的 oneShot 仅等待型走 `_warm` / `_commit`，nowait 直接 `_api.open`。`_resumeAdCore` 串播下一条也经过这个判断。`ads.dart` 为共享会话薄适配器，没有另一套 pod 策略。
- `lib/src/core/cutover/cutover_engine.dart`：open 委派当前 `_active.open`；epoch 表示渲染引擎换指，普通打开不递增。
- 总计划 §CP0 第一轮落地记录已经更正：未配置等待的前贴片按设计直接 open，0→0 不能证明 cutoverTo 回落。A27 是等待型 prepare+commit 的修复；CHANGELOG“广告 pod 的每条等待型广告”及只读 CLAUDE.md 遗留③的“等待型 pod”范围一致。

本次更新总计划 CP2 行和 CHANGELOG，明确 wait/nowait 两组判据；不修改 CLAUDE.md，不改变产品实现。

交给 wt-mova-cp2 修改 `example/lib/verify_auto/cp2_pod2_auto.dart` 的 pass 条件：保留 `epoch1 >= epoch0`、两条 path 和按源首帧时序校验，将无条件 `api.state.renderEpoch > epoch1` 改为 `(!wait || api.state.renderEpoch > epoch1)`。nowait 可另报 engine 身份/epoch 是否保持，不能要求递增；wait 仍要求递增。保留原始 FAIL，修正判据后使用新 run-id 复验，不把离线定性冒充新真机 PASS。

## 暂停/后台：夹具把媒体位置当 slot 时钟

`_onAdFirstFrame` 起 slot 表（本轮配置默认 durationFromFirstFrame=true）。`_onState` 按 playing 边沿冻结/恢复；pending 倒计时使用同样规则。`MovaAdClock.pause` 在冻结瞬间求 `remaining`，取消 Timer 并清除 `_since`；resume 直接以冻结的 `_left` 重新挂 Timer，不按 pause 命令时刻追溯，也不扣暂停窗口。命令意图改变和内核观测改变是两个时间点；冻结前仍观测为 playing 的时长正常计入。

本轮 `cp2_adpause_auto.dart` 实际判据为 `lastAd.timePosMs - 6000`，`slotRemainingBefore/AfterMs` 也是 `6000 - native timePos`，并未读取产品 slot 时钟。最后一次采样早于 completed，媒体首帧/时间轴起点、恢复期媒体推进与采样间隔都会进入该差值，不能据此声称少交付 slot 时长。

只读重算：在每条 CHECK 前的本次迭代中，取该广告首次 `EVENT/MovaFirstFrame.us` 到 `AD/completed.us`，扣掉其间 `STATE.state.playing=false` 的完整区间。单位均由原始 us 转为 ms。它与产品默认起表条件一致，不使用 CALL/RET 或原生 time-pos 代替边沿。

| 正式 ID | 原媒体 slotError ms | 有效墙钟 ms | 对 6000ms 误差 | pause CALL→playing=false ms |
|---|---:|---:|---:|---:|
| CP2.adpause.pause.1 | -360 | 6000.225 | +0.225 | 1.528 |
| CP2.adpause.pause.4 | -440 | 6001.469 | +1.469 | 0.638 |
| CP2.adpause.pause.7 | -360 | 6040.074 | +40.074 | 0.633 |
| CP2.adpause.pause.9 | -520 | 6000.789 | +0.789 | 0.946 |
| CP2.adbg.guard.7 | -440 | 5999.988 | -0.012 | 守卫路径，无手动 pause CALL |

原始证据位于只读树 `example/tool/coverage_evidence/`：

- `matrix-cp2-pod2-r4-20261104-222802/*-cp2-pod2.json`
- `matrix-cp2-adpause-r4-20261104-223849/*-cp2-adpause.json`
- `matrix-cp2-adbg-r4-20261104-224213/*-cp2-adbg.json`

例如 pause.1：首帧 17073.082ms，降沿 18616.910ms，升沿 28949.985ms，completed 33406.382ms；`(18616.910-17073.082)+(33406.382-28949.985)=6000.225ms`。guard.7：`(655452.776-652250.514)+(690620.893-687823.167)=5999.988ms`。微小负误差来自观察回调先后，远低于 300ms。没有看到丢掉或重复扣除数百毫秒的证据。

新增 2 条 fakeAsync 诊断（slot/pending 各一条）：pause 命令后延迟 520ms 才观测停止，停 10s，play 后延迟 440ms 才观测恢复；验证前者计入、后者冻结，剩余精确到 1ms，恢复后足额到期。基线实现直接通过，未复现产品缺陷。它们是契约诊断，产品修复回退变红数为 **0（无产品修复）**，不把夹具缺陷虚报为产品回归。

交给 wt-mova-cp2 修改 `cp2_adpause_auto.dart`（同时覆盖 adbg）：

1. 按广告源及本次迭代绑定 FirstFrame、STATE、completed，用单调 us 累计有效播放墙钟；slotError 改为有效墙钟减 slot 长度，门槛仍为绝对值 ≤300ms。不要直接从 started 起表，本轮是首帧起表；若以后关闭 durationFromFirstFrame，必须匹配实际 open 落定起表时点。
2. 暂停窗口保留 pausedCompleted==0、原生 pause/媒体漂移和前后台守卫语义校验。用冻结前有效累计量计算 remaining；恢复期间按 playing 升沿恢复，不能把 foreground/手动 play 命令当作恢复边沿。
3. 原生媒体位置及旧 slotError 继续作为诊断字段保留，可改名 mediaPositionErrorMs，不能混入 slot 剩余判据。缺少首帧、边沿或 completed 时按缺测处理，不能默认补齐为通过。

## 验证与偏差

开跑前已按要求停止 flutter_tester，已创建 `.dart_tool/b09`。定向 ads_clock_test 10/10 通过（新增 2）；`flutter analyze lib test` 为 0 issues（14.4s）；完整 `flutter test --concurrency=3 --reporter expanded` 仅执行一次，2406/2406 全绿（2m22s），无失败、跳过、降并发或分片。日志保存在本地 `.dart_tool/cp2-{clock-test,analyze,full-test}.log`，不入库。

两类均没有证实产品缺陷，因此 lib 无行为修改，无产品修复回退实验。当前 worktree 不含 `example/lib/verify_auto/cp2_*` 源码；只在本树修正文档判据并补充时钟诊断，夹具实现由 wt-mova-cp2 按上述方案修改。本轮不改原始结果，不运行真机，不声明 CP2 整体验收通过；视觉/听音及其他既有 BLOCKED 保持原结论。
