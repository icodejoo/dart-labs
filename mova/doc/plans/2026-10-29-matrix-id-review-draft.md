# full-01 “缺完整编号自动判据”54 项复核草表

> **这是模型整理的草表，不是自动判据，需主会话复核。** 数据全部来自 `example/tool/coverage_evidence/matrix-full-01/`（已被 .gitignore）。
> 原则：只有“本轮有明确 CHECK/VERDICT 为 PASS 且无 FAIL”才写倾向 PASS；多数 UI/手势类批次只产出截图与 window dump（0 个 CHECK），一律写“需人工”。
> 本轮的 `api`、`existing-pages` 批次因夹具缺失被判 HARNESS（见 doc/plans/2026-10-29-... 汇报），其覆盖编号的数据不完整；这里没有把它们当通过。
> 注意：矩阵里叫 `E.MovaStandby*` 的事件，代码里已改名 `MovaKeepAlive*`（2026-10-27 改名），按新名统计。

## 一、本轮有明确子项 FAIL 的编号

| 编号 | 子项证据（批次:子项） | 建议结论 | 说明 |
|---|---|---|---|
| C16 | followups/final-tls/final-tls-probe：C16.matrix 5/40 FAIL（合法 IP SAN + verify=true 拒绝）；C16.probe 9 条 FAIL，含 `localhost:18447 vod.mp4` | FAIL（IP SAN 部分，与上轮同） | IP SAN 被拒是上轮已记录的原生 TLS 缺陷（ACCEPTANCE-MATRIX C16/H66，已证伪“mbedtls 不接受 IP SAN”的推断，责任层未定）。**但 `localhost vod.mp4` 的 3 条本轮失败是夹具缺失造成**（隔离的 `coverage_media` 里没有 vod.mp4，已修），上轮 DNS 证书 6/6 通过，需重跑确认 |
| F11 | extras：F11.srt/ass/vtt 的 `native sub-text=` 为空（3/3 FAIL） | 需人工（倾向验证器缺陷） | 隔离媒体目录没有 test_subtitle.*，`18084/test_subtitle.*` 返回 404，已修；重跑前不能判产品 |
| A1 | api：`A1.broadcast` FAIL（cutover=true/false 各一次） | 旧预期未更新 | A1-① 明确“不看 isBroadcast”，且 `states`/`uiStates` 本就是 `_MultiStream`；这个检查沿用的是旧口径，上轮同样 FAIL |
| F6/N20（本表 E.MovaStandby*） | keepalive-core：S1 FAIL ×9（signal=grace，decodedProp 59–100ms）、S6 FAIL ×3（audio=absent，forcedAdvance≈-5.6s） | 需人工 | 上轮结论：S1 的 grace≈5s 是允许的超时兜底，不算功能 FAIL；S6 对无声流强制 B 属已知（Windows 同样）。本轮重现，与上轮一致 |
| U9/F8 | he-recovery：V9 FAIL（`needs no manual play tap`，advance=0ms） | 需人工（疑似已知系统行为） | CLAUDE.md 记录“Android 切后台后 libmpv 因 surface 丢失自动暂停”，需主会话确认 V9 的预期是否仍成立 |
| N14/N15 一类（review V10/V10x/V11） | existing-pages：RFV2 V10/V10x/V11 共 8 次 `restoredPortrait=false`，其余字段全 true | 旧预期未更新 | 上轮已记：原生为 FULL_USER，自动旋转开时“恢复竖屏”是验证器假设（rerun.md 245 行），不是产品缺陷 |
| Q13（不在 54 项内，仅提示） | existing-pages：Q13B 4/5 PASS，1/5 `swapped=false committed.mute=gone`；Q13C 同样 1 次 | 需调查 | 上轮 5/5。出现一次 shadow 被丢弃，疑似间歇性时序问题，见汇报 |

## 二、其余 54 项逐条

“OK”指该批次进程正常完成，不代表编号通过。

| 编号 | 覆盖批次（本轮状态） | 子项证据 | 建议结论 |
|---|---|---|---|
| A11 | widgets OK, ui OK | 截图/dump，0 CHECK | 需人工 |
| A12 | ui OK | 同上（setZoom 下限） | 需人工 |
| A13 | widgets OK | 同上 | 需人工 |
| A14 | widgets OK, ui OK | 同上 | 需人工 |
| A15 | widgets OK | 同上（小窗跟随 PiP） | 需人工 |
| A16 | widgets OK, ui OK | 同上 | 需人工 |
| A17 | followups/hls-native/final-hls OK | HLS 批次 CHECK 通过，仅 C16 相关失败；落点误差未逐项核对 | 需人工（倾向 PASS，须核落点误差 ≤500ms） |
| A18 | gesture-pip OK | MovaPipChange 出现于 33 个证据文件；PiP 复位依赖人工看图 | 需人工 |
| A20 | live-inputs OK | MovaTimeShiftChange/LiveEdgeReach 事件已观测，live 0/1/2 轮 CHECK 无新增 FAIL | 需人工（倾向 PASS） |
| A26 | widgets/interactive/touch-mini OK | 截图 | 需人工 |
| C3 | gesture-pip/interactive OK | 截图/触摸 | 需人工 |
| C5 | widgets/gesture-pip/safe-visual OK | 截图 | 需人工 |
| C6 | safe-visual OK | 截图 | 需人工 |
| C8 | interactive/extras/safe-visual OK | extras 里只有 F11 字幕假失败 | 需人工 |
| C10 | widgets/safe-visual OK | 截图 | 需人工 |
| C12 | widgets/interactive/touch-mini OK | 截图 | 需人工 |
| C16 | 见上表 | 见上表 | FAIL（IP SAN），DNS 部分待复跑 |
| E.MovaFirstFrame | he-firstframe OK | 事件在 283 个证据文件出现；首帧 signal 逐条未核 | 需人工（倾向 PASS） |
| E.MovaSizeChange | widgets OK | 事件在 283 个文件出现 | 需人工（倾向 PASS） |
| E.MovaQualityListChange | hls-native OK | 70 个文件出现 | 需人工（倾向 PASS） |
| E.MovaQualityChange | hls-native OK | 70 个文件出现 | 需人工（倾向 PASS） |
| E.MovaAbrDownShift | final-abr OK | 65 个文件出现；final-abr 的 CHECK 失败均为 C16 重复累计 | 需人工（倾向 PASS） |
| E.MovaFitChange | widgets OK | 130 个文件出现 | 需人工（倾向 PASS） |
| E.MovaZoomChange | ui OK | 71 个文件出现 | 需人工（倾向 PASS） |
| E.MovaLockChange | widgets OK | 80 个文件出现 | 需人工（倾向 PASS） |
| E.MovaFullScreenChange | widgets OK | 105 个文件出现 | 需人工（倾向 PASS） |
| E.MovaOrientationChange | widgets OK | 168 个文件出现 | 需人工（倾向 PASS） |
| E.MovaPipChange | gesture-pip OK | 33 个文件出现 | 需人工（倾向 PASS） |
| E.MovaMiniChange | widgets OK | 135 个文件出现 | 需人工（倾向 PASS） |
| E.MovaTimeShiftChange | live-inputs OK | 122 个文件出现 | 需人工（倾向 PASS） |
| E.MovaLiveEdgeReach | live-inputs OK | 153 个文件出现 | 需人工（倾向 PASS） |
| E.MovaPlayFailure | he-recovery OK | 99 个文件出现；同批次 V9 FAIL 见上 | 需人工 |
| E.MovaRecovered | he-recovery OK | 54 个文件出现 | 需人工（倾向 PASS） |
| E.MovaFailover | extras OK | 95 个文件出现；extras 仅 F11 假失败 | 需人工（倾向 PASS） |
| E.MovaStandbyChange | keepalive-core OK | 代码已改名 MovaKeepAliveChange，79 个文件出现；S1/S6 子项 FAIL 见上 | 需人工（须先把编号改名） |
| E.MovaStandbyResume | keepalive-core OK | 同上，MovaKeepAliveResume 76 个文件；elapsed 恒为 grace≈5s | 需人工（同 F6，grace 是允许兜底） |
| U1 | widgets/safe-visual OK | 截图 | 需人工 |
| U2 | widgets/safe-visual OK | 截图 | 需人工 |
| U3 | safe-visual OK | 截图 | 需人工 |
| U4 | touch-preview OK | 触摸 + 截图（预览气泡） | 需人工 |
| U5 | safe-visual OK | 截图 | 需人工 |
| U6 | gesture-pip/interactive OK | 触摸/截图 | 需人工 |
| U7 | safe-visual OK | 截图 | 需人工 |
| U8 | widgets/interactive/touch-mini OK | 截图 | 需人工 |
| U9 | he-recovery/widgets/interactive OK | he-recovery 内 V9 FAIL（见上） | 需人工 |
| F2 | live-inputs OK | live 三轮 CHECK 无新增 FAIL | 需人工（倾向 PASS） |
| F3 | followups/hls-native/final-hls OK | `F3.*` CHECK 2 条全 PASS、0 FAIL；批次 15 里 HLS CHECK 通过 | 需人工（倾向 PASS，需核落点与二次切档） |
| F5 | gesture-pip OK | 截图 | 需人工 |
| F8 | he-recovery/extras/he-v6-final OK | he-recovery 有 V9 FAIL；V6 未见 FAIL 行 | 需人工 |
| N9 | gesture-pip OK | PiP 退出后 state.pip 复位，需看 MovaPipChange 序列 + 截图 | 需人工 |
| N14 | widgets OK | 截图 | 需人工 |
| N15 | safe-visual/safe-transition OK | 截图 | 需人工 |
| N16 | widgets/safe-visual OK | 截图 | 需人工 |
| N17 | widgets OK | 截图 | 需人工 |

## 三、6 个人工/专用环境编号（本轮同上轮，仍 BLOCKED）

A31、C7（缺真实 STT 模型）、C2（缺 behind 历史媒体服务）、F15（缺可控 WHEP 服务）、N18（需 guard-off 专用包）、N22（需 debug VM 断言专用包）。
