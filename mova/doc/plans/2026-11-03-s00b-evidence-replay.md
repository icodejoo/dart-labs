# S00b：原始证据收口与 r1030 离线重放

本次只修改 example/doc；未修改 lib/test。r1030 原始证据从授权目录只读复制到本树 gitignored 的 `example/tool/coverage_evidence/matrix-r1030/`，未运行旧 finalize。

重放：**PASS 61 / FAIL 9 / BLOCKED 65**（135 个 v1 编号）。

命令：`python -B example/tool/run_matrix.py --replay example/tool/coverage_evidence/matrix-r1030 --run-id r1030`。

**范围限制：尚未达到 S00“BLOCKED 只剩真缺用例/真缺环境”的目标。** 仍有现存验证场景缺完整自动对账条件；本次将其具体列出，未把局部通过冒充整项通过。`*.coverage1` 是明确待补的判据占位，不是脚本现有 CHECK。完整子项、原始记录数组下标与批次状态见同目录 `2026-11-03-matrix-replay-r1030.json`。

## 判定规则

- 每个编号按 `example/tool/matrix_rules.json` 声明必需子项；这些只定义证据选择器和数学条件，不存结论。任一明确 FAIL → FAIL；全部必需子项 PASS → PASS；缺记录、非布尔 CHECK、未执行、验证器错误 → BLOCKED。manual 始终 BLOCKED。
- JSON 仅取最后一个 BEGIN 对应命令段；UI_CHECK 的数组格式亦支持。排除旧 ledger、summary、audit、review 及故障 recent-events 快照；不读取检查点 MD 的历史结论。原始数组下标保留，不因切片改变。
- 两实现必需 CHECK 校验 basic/basic-cutover 两份来源。日志判据要求完成标记和最小样本数。原始 driver END 只证明批次执行状态，不把其 VERDICT 用作产品结论。
- 事件别名仅映射命名：Swap→Cutover、Standby→KeepAlive；直接标量与接收时 state 比较，空载荷事件要求事件戳及 state 记录存在。事件出现仅证明该事件子项，不证明其功能整项。

## FAIL 归因

| 编号 | 分类与证据 |
|---|---|
| A2、E.MovaBufferChange、E.MovaSizeChange、E.MovaQualityChange | 产品接收快照契约差异：payload 与同条记录 state 不一致。原始 `matrix-r1030-final-abr.json` / `matrix-r1030-rerun-batch21-hls-*.json` EVENT；完整差异记录见 replay JSON 的对应 subitems。只能证明快照差异，不能证明画面错误或近期回归。 |

| C16 | 原生 TLS 产品现象，责任层未定：`matrix-r1030-final-tls.json` CHECK C16.matrix 及 `matrix-r1030-final-tls-probe.json` CHECK C16.probe；正确 CA 的 IP SAN 地址仍失败。 |
| A25、C15、F6、N20 | keepAlive 原始验证器 FAIL：`matrix-r1030-keepalive-core.log` S1 九次 signal=grace（原生 decodedProp 约百毫秒），S6 无声流 forcedAdvance 为负。S1 判据拒绝 grace，与真实解码快慢不是同一指标，存在验证器过严的可能；S6 的位置倒退/无声流行为需单独复核。当前保留 FAIL，不以 decodedProp 快而覆盖原 CHECK。 |

A10 判据修正：最初把 await 后代理 state 的立即快照当成最终读回，误报 FAIL。原始 basic-cutover RATE 的 actual 滞后一拍，但对应 MovaRateChange 事件序列为正确钳制值；现按两实现实际事件序列对账，并保留 A10.persist 换源保持 CHECK。原始读数未删除，也未放宽 .25–4 的钳制要求。

## 对不上的编号/子项

- `A1.broadcast` 检查 isBroadcast，而现行 A1 要求“多订阅者收到同一序列”，不能作为产品 FAIL；现有 counts/closed 不能证明完整同序列。此子项记验证器问题并 BLOCKED。
- `rerun-batch16-{engine,cutover}.fit.* / lock / fullscreen.* / fitRebuild` 使用场景名，规则显式关联 A11/A13/A14/N14；未按编号前缀猜归属。longpress 倍速已经不是矩阵预期，不用于 C3/U6 判败；doubletap 旧断言要求 playing=true，而当前矩阵要求双击 seek；两者不是同一动作契约，因此未把该 false 当作产品失败。
- HE V1–V4、恢复 V5–V8、STANDBY S1/S2/S3/S6/S13/S17、Q13A/B/C、RFV2 V12/V12b/V13a/V13b/V14 使用脚本私有编号，通过规则关联矩阵编号。HE V4 本身包含 reps=20，只要求一条汇总，不错误要求三条。
- `HLS_RESULT`、RATE、BRIGHTNESS_NATIVE、RELOAD、LIFECYCLE、LIVE_DURATION、DVR VIDEO、原生媒体音量 txt 不使用 CHECK id，按各自字段数学关系推导。
- 其余 `*.coverage1` 对应下表明确缺口，当前脚本没有该 CHECK，不能算已完成逐子项自动化。

## 仍 BLOCKED 的全部编号

| 编号 | 原因 |
|---|---|
| A1 | 缺 CHECK A1.coverage1：四流多订阅者同序列；broadcast 标志不是现行契约；验证器旧预期：矩阵 A1 要求多订阅者同序列，不要求 isBroadcast=true |
| A5 | 缺 CHECK A5.coverage1：recovery 关闭时内核 open 抛出异常的真机用例（404 accepted 不是同步 open 异常） |
| A6 | 缺 CHECK A6.coverage1：重复 play/pause 幂等与 playOrPause 两方向独立 CHECK |
| A7 | 缺 CHECK A7.coverage1：丢 seek 重发的独立原生调用次数断言 |
| A11 | 缺 CHECK A11.coverage1：三种 fit 的画面差异自动量化 |
| A13 | 缺 CHECK A13.coverage1：锁定前后手势屏蔽的原生亮度/音量对账 |
| A14 | 缺 CHECK A14.coverage1：原生窗口方向及系统栏恢复对账 |
| A15 | 缺 CHECK A15.coverage1：MiniHost→PiP→展开的小窗可见性与状态自动对账 |
| A16 | 缺 CHECK A16.coverage1：landscape/portrait/auto 原生方向对账 |
| A18 | 缺 CHECK A18.coverage1：进入/展开/真正点 X 后原生 pinned 与 PipChange 对账 |
| A21 | 缺 CHECK A21.coverage1：show/sticky/dragging/previewAt CHECK |
| A24 | 验证器错误/批次未完成 existing-pages |
| A26 | 缺 CHECK A26.coverage1：mini 拖动/吸边/关闭/转屏钳回自动对账 |
| A29 | 缺 CHECK A29.coverage1：prefetcher 预取命中与池回收完整 CHECK |
| A30 | 缺 CHECK A30.diskHit；缺 CHECK A30.coverage1：VTT/抽帧/断网/取消/过期请求全部模式自动对账 |
| A31 | 缺真实 STT 模型/识别引擎和下载服务；失败回滚仅为子项。 |
| C1 | 缺 CHECK C1.coverage1：预览全部配置及 VTT/抽帧/断网/取消判据 |
| C2 | 缺按 behind 返回历史媒体的服务，滑动 HLS 不等于历史回看。 |
| C3 | 缺 CHECK C3.coverage1：手势双指捏合/单击/锁定/轴重映射完整 CHECK（长按倍速已非契约） |
| C4 | 缺 CHECK C4.coverage1：ABR policy 配置与真实限速降档自动对账 |
| C5 | 缺 CHECK C5.coverage1：所有 controls 配置的逐项可见性/计时 CHECK |
| C6 | 缺 CHECK C6.coverage1：弹幕显示开关与 items 滚动自动对账（无发送框是现行契约） |
| C7 | 同 A31，缺真实识别及导出完整证据。 |
| C8 | 缺 CHECK C8.coverage1：playlist 配置与 NextUp 取消/立即播放 CHECK |
| C10 | 缺 CHECK C10.coverage1：strings/theme 替换及缓冲三字段渲染量化 CHECK |
| C11 | 验证器错误/批次未完成 existing-pages |
| C12 | 缺 CHECK C12.coverage1：mini 默认关闭/吸边/转屏钳回 CHECK |
| C13 | 缺 CHECK C13.coverage1：heartbeat 默认无定时器及 qoe 开启四分结算 CHECK |
| C17 | 缺 CHECK C17.coverage1：sameAs/请求头原生读回自动对账 |
| E.MovaPreviewBlock | 缺 EVENT MovaPreviewBlock |
| E.MovaSwapChange | 验证器错误/批次未完成 existing-pages |
| E.MovaStandbyResume | 缺 EVENT MovaKeepAliveResume |
| U1 | 缺 CHECK U1.coverage1：三种 Player/View/FeedPlayer 的挂树/换源/卸载与资源对账 |
| U2 | 缺 CHECK U2.coverage1：全部皮肤组件树逐槽检查 |
| U3 | 缺 CHECK U3.coverage1：标题/方向/PiP/fit/quality/fullscreen 各按钮点击 CHECK |
| U4 | 缺 CHECK U4.coverage1：VOD/直播底栏、seek 提交/禁用/节流/预览气泡 CHECK |
| U5 | 缺 CHECK U5.coverage1：中心播放/循环倍速/各 HUD 值渲染 CHECK |
| U6 | 缺 CHECK U6.coverage1：所有手势含双指捏合/锁定/轴重映射 CHECK |
| U7 | 缺 CHECK U7.coverage1：弹幕/字幕/NextUp/广告/FeedSocial 各渲染与点击 CHECK |
| U8 | 缺 CHECK U8.coverage1：mini 拖动/吸边/甩动/转屏 CHECK |
| U9 | 缺 CHECK U9.coverage1：守卫 route/Ticker/inactive/PiP/mini 联合 CHECK |
| F4 | 验证器错误/批次未完成 existing-pages |
| F5 | 缺 CHECK F5.coverage1：真实 MiniHost 与 PiP 互斥及唤醒保活联合 CHECK |
| F7 | 缺 CHECK F7.coverage1：QoE 四分结算/TTFF/卡顿/truncated/heartbeat 逐字段 CHECK |
| F9 | 缺 CHECK F9.coverage1：audioOnly 无视频解码及真实皮肤/封面/手势 CHECK |
| F10 | 缺 CHECK F10.coverage1：预览各模式完整 CHECK |
| F11 | 验证器错误/批次未完成 existing-pages |
| F12 | 验证器错误/批次未完成 existing-pages；缺 CHECK F12.coverage1：音频会话/后台资源与耗电完整 CHECK |
| F13 | 缺 CHECK F13.coverage1：多引擎 RSS/线程/句柄有界及 dispose 超时 CHECK |
| F14 | 验证器错误/批次未完成 existing-pages；缺 CHECK F14.coverage1：原生泵创建/销毁/稳定性/错误隔离的结构化 CHECK |
| F15 | 缺可控 WHEP 服务；端口可达不证明播放。 |
| F16 | 验证器错误/批次未完成 existing-pages |
| N5 | 缺 CHECK N5.coverage1：recovery 仅订阅 END_FILE、observeRestarts 开关的原生事件对账 |
| N9 | 缺 CHECK N9.coverage1：PiP 展开与真正点 X 的原生 pinned/state 对账 |
| N10 | 验证器错误/批次未完成 existing-pages |
| N11 | 验证器错误/批次未完成 existing-pages |
| N12 | 缺 CHECK N12.coverage1：换源归零与旧 RESTART 隔离逐事件 CHECK |
| N13 | 验证器错误/批次未完成 existing-pages；缺 CHECK N13.coverage1：弱客户端资源/懒创建计数与 QoE 开关联合 CHECK |
| N15 | 缺 CHECK N15.coverage1：poster 重盖/渐隐/audioOnly/Feed 的像素与首帧联合 CHECK |
| N16 | 缺 CHECK N16.coverage1：MinimalSkin 与缓冲三字段可见性量化 CHECK |
| N17 | 缺 CHECK N17.coverage1：View 所有权/同源/null/options/销毁/异常各分支 CHECK |
| N18 | 完整 mini/guard-off 联动需专用包和复核，主包不足。 |
| N21 | 缺 CHECK N21.coverage1：Windows SnapshotGuard 专包与 stagedSourceOptions 对账 |
| N22 | 需专用 debug VM 构建及断言 marker；不能复用旧 APK。 |
| N23 | 缺 CHECK N23.coverage1：nativeRestartAvailable/truncatedBelow/error 四分与上报字段完整 CHECK |

## 逐编号证据映射

| 编号 | 必需证据（详细数学条件见 matrix_rules.json） |
|---|---|
| A1 | check:A1.closed, check:A1.progress, check:A1.coverage1（待补） |
| A2 | event:MovaBufferChange, event:MovaSizeChange, event:MovaQualityChange, event:MovaRateChange, event:MovaVolumeChange, event:MovaBrightChange, check:A2.coverage1（待补） |
| A3 | check:A3.audio, check:A3.lazyBefore, check:A3.lazyOpened, check:A3.lazyRead |
| A4 | check:A4 |
| A5 | check:A5.paused, check:N8.accept, check:N8.reject, check:N8.superseded, check:A5.coverage1（待补） |
| A6 | check:A6.pause, check:A6.coverage1（待补） |
| A7 | check:A7.seek, check:A7.negative, check:A7.live, record:SEEK_LOADING, record:SEEK_BY, record:SEEK_BEYOND, check:A7.coverage1（待补） |
| A8 | check:A8.clamp, volume:volume |
| A9 | check:A9.clamp, record:BRIGHTNESS_NATIVE |
| A10 | check:A10.persist, rate_sequence:rate_sequence |
| A11 | check:rerun-batch16-engine.fit.contain, check:rerun-batch16-cutover.fit.contain, check:rerun-batch16-engine.fit.cover, check:rerun-batch16-cutover.fit.cover, check:rerun-batch16-engine.fit.fill, check:rerun-batch16-cutover.fit.fill, check:A11.coverage1（待补） |
| A12 | record:VIDEO, record:VIDEO, record:VIDEO, record:VIDEO, record:VIDEO |
| A13 | check:rerun-batch16-engine.lock, check:rerun-batch16-cutover.lock, check:A13.coverage1（待补） |
| A14 | check:rerun-batch16-engine.fullscreen.true, check:rerun-batch16-cutover.fullscreen.true, check:rerun-batch16-engine.fullscreen.false, check:rerun-batch16-cutover.fullscreen.false, check:A14.coverage1（待补） |
| A15 | check:A15.coverage1（待补） |
| A16 | check:A16.coverage1（待补） |
| A17 | hls:hls |
| A18 | check:A18.coverage1（待补） |
| A19 | record:RELOAD |
| A20 | record:VIDEO, record:VIDEO |
| A21 | check:A21.hide, check:A21.hud, check:A21.coverage1（待补） |
| A22 | check:A22 |
| A23 | check:A23.doubleDispose, check:A23.postOpen, check:A23.120 |
| A24 | check:A24.abandon, check:A24.commit, check:A24.cutoverTo, check:A24.retired, check:A24.short, check:A24.timeout |
| A25 | check:A25.pause, log:S1 @keepalive-core.log, log:S2 @keepalive-core.log, log:S3 @keepalive-core.log, log:S6 @keepalive-core.log, log:S13 @keepalive-core.log, log:S17 @keepalive-core.log |
| A26 | check:A26.coverage1（待补） |
| A27 | check:A27.rolls, check:C9.waits |
| A28 | check:A28.start, check:A28.end, check:A28.auto |
| A29 | check:A29.dispose, check:A29.final, check:A29.coverage1（待补） |
| A30 | check:A30.diskHit, check:A30.coverage1（待补） |
| A31 |  |
| A32 | check:A32.seekVeto, check:A32.afterThrow, check:A32.onErrorIsolation, check:N8.reject, check:N8.superseded |
| A33 | check:A33 |
| C1 | check:C1.coverage1（待补） |
| C2 |  |
| C3 | check:C3.coverage1（待补） |
| C4 | check:C4.coverage1（待补） |
| C5 | check:C5.coverage1（待补） |
| C6 | check:C6.coverage1（待补） |
| C7 |  |
| C8 | check:C8.coverage1（待补） |
| C9 | check:C9.waits, check:A27.rolls |
| C10 | check:C10.coverage1（待补） |
| C11 | check:C11.off, check:A24.commit, check:A24.cutoverTo |
| C12 | check:C12.coverage1（待补） |
| C13 | check:C13.off, check:C13.coverage1（待补） |
| C14 | log:V5 @he-recovery.log, log:V6 @he-recovery.log, log:V7 @he-recovery.log, log:V8 @he-recovery.log |
| C15 | check:C15.maxDuration, log:S1 @keepalive-core.log, log:S2 @keepalive-core.log, log:S3 @keepalive-core.log, log:S6 @keepalive-core.log, log:S13 @keepalive-core.log, log:S17 @keepalive-core.log |
| C16 | check:C16.matrix, check:C16.probe |
| C17 | check:C17.pick, check:N4.applied, check:N4.restore, check:N19.failover, check:C17.coverage1（待补） |
| E.MovaReady | event:MovaReady |
| E.MovaSourceChange | event:MovaSourceChange |
| E.MovaPlay | event:MovaPlay |
| E.MovaPause | event:MovaPause |
| E.MovaDone | event:MovaDone |
| E.MovaSeek | event:MovaSeek |
| E.MovaSeeked | event:MovaSeeked |
| E.MovaBufferChange | event:MovaBufferChange |
| E.MovaDurationChange | event:MovaDurationChange |
| E.MovaFirstFrame | event:MovaFirstFrame |
| E.MovaSizeChange | event:MovaSizeChange |
| E.MovaVolumeChange | event:MovaVolumeChange |
| E.MovaBrightChange | event:MovaBrightChange |
| E.MovaRateChange | event:MovaRateChange |
| E.MovaQualityListChange | event:MovaQualityListChange |
| E.MovaQualityChange | event:MovaQualityChange |
| E.MovaAbrDownShift | event:MovaAbrDownShift |
| E.MovaFitChange | event:MovaFitChange |
| E.MovaZoomChange | event:MovaZoomChange |
| E.MovaLockChange | event:MovaLockChange |
| E.MovaFullScreenChange | event:MovaFullScreenChange |
| E.MovaOrientationChange | event:MovaOrientationChange |
| E.MovaPipChange | event:MovaPipChange |
| E.MovaMiniChange | event:MovaMiniChange |
| E.MovaTimeShiftChange | event:MovaTimeShiftChange |
| E.MovaLiveEdgeReach | event:MovaLiveEdgeReach |
| E.MovaPreviewBlock | event:MovaPreviewBlock |
| E.MovaSttBlock | event:MovaSttBlock |
| E.MovaSwapChange | event:MovaSwapChange |
| E.MovaErrorEvent | event:MovaErrorEvent |
| E.MovaPlayFailure | event:MovaPlayFailure |
| E.MovaRecovered | event:MovaRecovered |
| E.MovaFailover | event:MovaFailover |
| E.MovaStandbyChange | event:MovaStandbyChange |
| E.MovaStandbyResume | event:MovaStandbyResume |
| E1 | lifecycle:lifecycle |
| E2 | check:E2.disabled, check:C11.off, check:C13.off |
| U1 | check:U1.coverage1（待补） |
| U2 | check:U2.coverage1（待补） |
| U3 | check:U3.coverage1（待补） |
| U4 | check:U4.coverage1（待补） |
| U5 | check:U5.coverage1（待补） |
| U6 | check:U6.coverage1（待补） |
| U7 | check:U7.coverage1（待补） |
| U8 | check:U8.coverage1（待补） |
| U9 | check:U9.coverage1（待补） |
| F1 | check:F1, record:LIFECYCLE |
| F2 | record:VIDEO, record:VIDEO, duration:duration |
| F3 | check:F3.abrBackToBack, hls:hls |
| F4 | check:F4.adResume, check:A24.commit, check:A27.rolls |
| F5 | check:F5.coverage1（待补） |
| F6 | log:S1 @keepalive-core.log, log:S2 @keepalive-core.log, log:S3 @keepalive-core.log, log:S6 @keepalive-core.log, log:S13 @keepalive-core.log, log:S17 @keepalive-core.log |
| F7 | check:F7.coverage1（待补） |
| F8 | log:V5 @he-recovery.log, log:V6 @he-recovery.log, log:V7 @he-recovery.log, log:V8 @he-recovery.log |
| F9 | check:F9.coverage1（待补） |
| F10 | check:F10.coverage1（待补） |
| F11 | check:F11.ass, check:F11.movtext, check:F11.srt, check:F11.vtt |
| F12 | check:F12.coverage1（待补） |
| F13 | check:F13.coverage1（待补） |
| F14 | check:F14.coverage1（待补） |
| F15 |  |
| F16 | log:V12 @rerun-batch11-review.log, log:V12b @rerun-batch11-review.log, log:V13a @rerun-batch11-review.log, log:V13b @rerun-batch11-review.log, log:V14 @rerun-batch11-review.log |
| N1 | check:N1.network, check:N4.whepOptions |
| N2 | check:N2.derived, check:N2.watchoff |
| N3 | check:N3.defaultLive |
| N4 | check:N4.applied, check:N4.restore, check:N4.whepOptions |
| N5 | check:N5.coverage1（待补） |
| N6 | check:N6.clear, check:N6.giveup |
| N7 | duration:duration |
| N8 | check:N8.accept, check:N8.reject, check:N8.disposed, check:N8.playlistRejected, check:N8.superseded |
| N9 | check:N9.coverage1（待补） |
| N10 | log:V12 @rerun-batch11-review.log, log:V12b @rerun-batch11-review.log, log:V13a @rerun-batch11-review.log, log:V13b @rerun-batch11-review.log, log:V14 @rerun-batch11-review.log |
| N11 | log:Q13A @rerun-batch10-mute.log, log:Q13B @rerun-batch10-mute.log, log:Q13C @rerun-batch10-mute.log |
| N12 | log:V1 @he-firstframe.log, log:V2 @he-firstframe.log, log:V3 @he-firstframe.log, log:V4 @he-firstframe.log, check:N12.coverage1（待补） |
| N13 | log:V1 @he-firstframe.log, log:V2 @he-firstframe.log, log:V3 @he-firstframe.log, log:V4 @he-firstframe.log, check:N13.coverage1（待补） |
| N14 | check:rerun-batch16-engine.fitRebuild, check:rerun-batch16-cutover.fitRebuild |
| N15 | check:N15.coverage1（待补） |
| N16 | check:N16.coverage1（待补） |
| N17 | check:N17.coverage1（待补） |
| N18 |  |
| N19 | check:N19.failover, check:N6.clear, check:N6.giveup, log:V5 @he-recovery.log, log:V6 @he-recovery.log, log:V7 @he-recovery.log, log:V8 @he-recovery.log |
| N20 | log:S1 @keepalive-core.log, log:S2 @keepalive-core.log, log:S3 @keepalive-core.log, log:S6 @keepalive-core.log, log:S13 @keepalive-core.log, log:S17 @keepalive-core.log |
| N21 | check:N21.coverage1（待补） |
| N22 |  |
| N23 | check:N23.coverage1（待补） |
