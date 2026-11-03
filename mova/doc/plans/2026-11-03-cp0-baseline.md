# CP0 真机基线（2026-11-03）

状态：**RUNNING**。CP0 不设产品通过线；测得故障原样保留。

Android release APK SHA-256：`f9df792f6dcc0b68d908906f23026dd5beeacd56d0c2d566c1b85d6c35ba1586`。阶段1构建一次，后续复用；安装拉回哈希一致。

基线 detached a5c317f6；只在本树 mova/example、mova/doc 修改，lib/test 不改。

cp0-pod2 按用户指示跳过：旧页默认不等待就绪，不用 epoch 0→0 推断 cutover 回落。音频焦点 manual BLOCKED；全量49批不在本轮。

## 实测台账

|阶段|项目|计划|已执行|失败|状态/关键数字|证据|
|---|---|---:|---:|---:|---|---|
|1|P1-3 限速 auto|5|5|0|MEASURED {"harness": [], "missing": [], "runs": [{"case": "CP0.autotier.limited.0", "firstObservedTier": {"tier": "1280x720", "sinceOpenUs": 7006278, "scheduledSeconds": 7}, "observedSwitchCount": 0, "switchIntervals": [], "nativeHlsBitrates": ["max"], "sampleCount": 91, "maxRebufferSeconds": 3.444609, "totalRebufferSeconds": 56.088795, "rebufferCount": 19, "finalNativeTimePos": "27.360000"}, {"case": "CP0.autotier.limited.1", "firstObservedTier": {"tier": "1280x720", "sinceOpenUs": 7189547, "scheduledSeconds": 7}, "observedSwitchCount": 0, "switchIntervals": [], "nativeHlsBitrates": ["max"], "sampleCount": 91, "maxRebufferSeconds": 7.053554, "totalRebufferSeconds": 55.963642, "rebufferCount": 18, "finalNativeTimePos": "26.840000"}, {"case": "CP0.autotier.limited.2", "firstObservedTier": {"tier": "1280x720", "sinceOpenUs": 7272813, "scheduledSeconds": 7}, "observedSwitchCount": 0, "switchIntervals": [], "nativeHlsBitrates": ["max"], "sampleCount": 91, "maxRebufferSeconds": 6.14433, "totalRebufferSeconds": 55.894429, "rebufferCount": 18, "finalNativeTimePos": "27.160000"}, {"case": "CP0.autotier.limited.3", "firstObservedTier": {"tier": "1280x720", "sinceOpenUs": 7257429, "scheduledSeconds": 7}, "observedSwitchCount": 0, "switchIntervals": [], "nativeHlsBitrates": ["max"], "sampleCount": 91, "maxRebufferSeconds": 6.116479, "totalRebufferSeconds": 54.624030000000005, "rebufferCount": 17, "finalNativeTimePos": "27.880000"}, {"case": "CP0.autotier.limited.4", "firstObservedTier": {"tier": "1280x720", "sinceOpenUs": 7357624, "scheduledSeconds": 7}, "observedSwitchCount": 0, "switchIntervals": [], "nativeHlsBitrates": ["max"], "sampleCount": 91, "maxRebufferSeconds": 3.463934, "totalRebufferSeconds": 56.208904, "rebufferCount": 19, "finalNativeTimePos": "27.200000"}]}|example/tool/coverage_evidence/matrix-cp0-autotier-formal-20261103-01/matrix-cp0-autotier-formal-20261103-01-cp0-autotier.json|
|1|P1-3 不限速对照|1|1|0|MEASURED {"harness": [], "missing": [], "runs": [{"case": "CP0.autotier.unlimited.0", "firstObservedTier": {"tier": "1280x720", "sinceOpenUs": 2213870, "scheduledSeconds": 2}, "observedSwitchCount": 0, "switchIntervals": [], "nativeHlsBitrates": ["max"], "sampleCount": 91, "maxRebufferSeconds": 0, "totalRebufferSeconds": 0, "rebufferCount": 0, "finalNativeTimePos": "88.240000"}]}|example/tool/coverage_evidence/matrix-cp0-autotier-formal-20261103-01/matrix-cp0-autotier-formal-20261103-01-cp0-autotier.json|
|2|p02.contentWarm|10|0|None|PENDING {}|None|
|2|p02.midPending|10|0|None|PENDING {}|None|
|2|p02.postLoad|10|0|None|PENDING {}|None|
|2|pod2|10|0|None|SKIPPED {}|example/tool/coverage_evidence/cp0-formal-device-preflight.json|
|2|bgpause.true|5|0|None|PENDING {}|None|
|2|bgpause.false|5|0|None|PENDING {}|None|
|2|pauseload.loading|3|0|None|PENDING {}|None|
|2|pauseload.ready|3|0|None|PENDING {}|None|
|2|pauseload.firstFrame|3|0|None|PENDING {}|None|
|2|timeshift.dvr|3|0|None|PENDING {}|None|
|2|timeshift.timeshift|3|0|None|PENDING {}|None|
|2|pageview.horizontal|3|0|None|PENDING {}|None|
|2|pageview.vertical|3|0|None|PENDING {}|None|
|3|F3/A17 precise.normal|60|0|None|PENDING {}|None|
|3|F3/A17 precise.paused|60|0|None|PENDING {}|None|
|3|F3/A17 precise.cutover|160|0|None|PENDING {}|None|
|3|H28 default.playing|30|0|None|PENDING {}|None|
|3|H28 default.paused|30|0|None|PENDING {}|None|
|3|H28 default.cutover|30|0|None|PENDING {}|None|
|3|H20.hlsSeek|30|0|None|PENDING {}|None|
|3|H50.hlsSeek|30|0|None|PENDING {}|None|
|3|H7.lateError|按现有用例次数|0|None|PENDING {}|None|
|3|H14.manualSeek|按现有用例次数|0|None|PENDING {}|None|
|3|H17.mp4|按现有用例次数|0|None|PENDING {}|None|
|3|H17.m3u8|按现有用例次数|0|None|PENDING {}|None|
|3|H33.direct.404|按现有用例次数|0|None|PENDING {}|None|
|3|H33.direct.refused|按现有用例次数|0|None|PENDING {}|None|
|3|H33.direct.dns|按现有用例次数|0|None|PENDING {}|None|
|3|H33.recovery.404|按现有用例次数|0|None|PENDING {}|None|
|3|H33.recovery.refused|按现有用例次数|0|None|PENDING {}|None|
|3|H33.recovery.dns|按现有用例次数|0|None|PENDING {}|None|
|3|H42.wake|按现有用例次数|0|None|PENDING {}|None|
|3|A15.miniPip|按现有用例次数|0|None|PENDING {}|None|
|3|H37.dispose|按现有用例次数|0|None|PENDING {}|None|
|4|Windows F3|30|0|None|PENDING {}|None|
|4|Windows A23/F13 dispose|20|0|None|PENDING {}|None|
|4|Windows HE V6|5|0|None|PENDING {}|None|
|4|Windows HE V10|20|0|None|PENDING {}|None|

## 口径与证据边界

P1-3：默认 createMovaEngine、auto、不手选；三档120秒HLS，共享900kbit/s限速。每秒原生读回档位、hls-bitrate、视频轨、缓存；切换时刻报告相邻采样区间，次数为观测下界。事件戳来自单调事件记录；卡顿结合原生 time-pos/paused-for-cache 与 MovaBufferChange，不以墙钟估算。完整逐轮数字在同名 JSON。

precise 沿用 rerun6 合格 RESTART/目标档位门槛，另算 CP0：目标与原生 time-pos 误差≤500ms 且 path 正确；<200ms 占比以已执行次数为分母。保留原续播/暂停判据与 harnessInvalid，不将缺样本算作成功。H28 默认配置不开泵。H20 使用 open 后立即seek(15s)，H50使用 cutoverTo(hls,at:12s)。

run_matrix.py 最小改动：增加 --reuse-apk，安装后拉回核对SHA256，避免阶段间重建；adb 增加断线15分钟/30秒重检。coverage1规则未改。

恢复项以 cp0-session-original.json / cp0-session-restored.json 逐值核验；原值媒体音量0、USB常亮7，gnirehtet reverse 映射保留。原始证据均位于 gitignored example/tool/coverage_evidence/。

本轮前的设备离线0样本仅为历史准备，不能代替本轮实测。上轮报告与台账可从 a5c317f6 复核。
