# Android matrix run full-02

基线：`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\rerun-final-ledger.json`。仅本轮证据入账；BLOCKED 不表示产品 FAIL。

| 总数 | PASS | FAIL | BLOCKED |
|---|---|---|---|
| 135 | 2 | 0 | 133 |

| 对比 | 编号 |
|---|---|
| 新增失败 | 无 |
| 已修复 | 无 |
| 仍失败 | 无 |
| 仍阻塞 | A31, C2, C7, F15, N18 |
| 新增阻塞 | A1, A2, A3, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16, A17, A18, A19, A20, A21, A23, A24, A25, A26, A27, A28, A29, A30, A32, A33, C1, C3, C4, C5, C6, C8, C9, C10, C11, C12, C13, C14, C15, C16, C17, E.MovaReady, E.MovaSourceChange, E.MovaPlay, E.MovaPause, E.MovaDone, E.MovaSeek, E.MovaSeeked, E.MovaBufferChange, E.MovaDurationChange, E.MovaFirstFrame, E.MovaSizeChange, E.MovaVolumeChange, E.MovaBrightChange, E.MovaRateChange, E.MovaQualityListChange, E.MovaQualityChange, E.MovaAbrDownShift, E.MovaFitChange, E.MovaZoomChange, E.MovaLockChange, E.MovaFullScreenChange, E.MovaOrientationChange, E.MovaPipChange, E.MovaMiniChange, E.MovaTimeShiftChange, E.MovaLiveEdgeReach, E.MovaPreviewBlock, E.MovaSttBlock, E.MovaSwapChange, E.MovaErrorEvent, E.MovaPlayFailure, E.MovaRecovered, E.MovaFailover, E.MovaStandbyChange, E.MovaStandbyResume, E1, E2, U1, U2, U3, U4, U5, U6, U7, U8, U9, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, F16, N1, N2, N3, N4, N5, N6, N7, N8, N9, N10, N11, N12, N13, N14, N15, N16, N17, N19, N20, N21, N22, N23 |
| 已解除阻塞 | 无 |

验证器问题（HARNESS；与产品缺陷分开）：

- existing-pages: 子命令失败/缺完成标记；`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log`

| 编号 | 结论 | 原因与证据 | 最小复现入口 |
|---|---|---|---|
| A1 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A2 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A3 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,widgets` |
| A4 | PASS | 复用 rerun_finalize 引用的两实现完整编号 CHECK：matrix-full-02-rerun-batch15-basic.json: {'ms': 6798, 'kind': 'CHECK', 'id': 'A4', 'pass': True, 'detail': 'supported=true'}; matrix-full-02-rerun-batch15-basic-cutover.json: {'ms': 17775, 'kind': 'CHECK', 'id': 'A4', 'pass': True, 'detail': 'supported=true'} E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A5 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras,native-inputs` |
| A6 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A7 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| A8 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,native-inputs` |
| A9 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,widgets,extras` |
| A10 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A11 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,ui` |
| A12 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only ui` |
| A13 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| A14 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,ui` |
| A15 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| A16 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,ui` |
| A17 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only followups,hls-native,final-hls` |
| A18 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only gesture-pip` |
| A19 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A20 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only live-inputs` |
| A21 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,widgets,touch-preview` |
| A22 | PASS | 复用 rerun_finalize 引用的两实现完整编号 CHECK：matrix-full-02-rerun-batch15-basic.json: {'ms': 10577, 'kind': 'CHECK', 'id': 'A22', 'pass': True, 'detail': '[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793237805837999}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 8000}, seeked:{positionMs: 8000}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]'}; matrix-full-02-rerun-batch15-basic-cutover.json: {'ms': 21565, 'kind': 'CHECK', 'id': 'A22', 'pass': True, 'detail': '[pause:{}, sourceChange:{uri: http://127.0.0.1:18080/vod.mp4?t=1793237816806376}, play:{}, pause:{}, play:{}, pause:{}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 15000}, seeked:{positionMs: 15000}, seek:{targetMs: 5000}, seeked:{positionMs: 5000}, seek:{targetMs: 10000}, seeked:{positionMs: 10000}, seek:{targetMs: 8000}, seeked:{positionMs: 8000}, seek:{targetMs: 0}, seeked:{positionMs: 0}, coverage:{probe: 42}, play:{probe: 43}]'} E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A23 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A24 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| A25 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| A26 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| A27 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A28 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| A29 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,interactive` |
| A30 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras,safe-transition` |
| A31 | BLOCKED | 缺真实 STT 模型/识别引擎和下载服务；失败回滚仅为子项。  | `manual` |
| A32 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A33 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| C1 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras,safe-transition` |
| C2 | BLOCKED | 缺按 behind 返回历史媒体的服务，滑动 HLS 不等于历史回看。  | `manual` |
| C3 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only gesture-pip,interactive` |
| C4 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,final-abr` |
| C5 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,gesture-pip,safe-visual` |
| C6 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only safe-visual` |
| C7 | BLOCKED | 同 A31，缺真实识别及导出完整证据。  | `manual` |
| C8 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only interactive,extras,safe-visual` |
| C9 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| C10 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| C11 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| C12 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| C13 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,followups` |
| C14 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,he-recovery,extras` |
| C15 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| C16 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only followups,final-tls,final-tls-probe` |
| C17 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaReady | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSourceChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaPlay | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaPause | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaDone | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSeek | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSeeked | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaBufferChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaDurationChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaFirstFrame | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only he-firstframe` |
| E.MovaSizeChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaVolumeChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaBrightChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaRateChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaQualityListChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only hls-native` |
| E.MovaQualityChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only hls-native` |
| E.MovaAbrDownShift | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only final-abr` |
| E.MovaFitChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaZoomChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only ui` |
| E.MovaLockChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaFullScreenChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaOrientationChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaPipChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only gesture-pip` |
| E.MovaMiniChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaTimeShiftChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only live-inputs` |
| E.MovaLiveEdgeReach | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only live-inputs` |
| E.MovaPreviewBlock | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSttBlock | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSwapChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| E.MovaErrorEvent | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaPlayFailure | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only he-recovery` |
| E.MovaRecovered | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only he-recovery` |
| E.MovaFailover | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only extras` |
| E.MovaStandbyChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only keepalive-core` |
| E.MovaStandbyResume | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only keepalive-core` |
| E1 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E2 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| U1 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| U2 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| U3 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only safe-visual` |
| U4 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only touch-preview` |
| U5 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only safe-visual` |
| U6 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only gesture-pip,interactive` |
| U7 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only safe-visual` |
| U8 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| U9 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only he-recovery,widgets,interactive` |
| F1 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| F2 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only live-inputs` |
| F3 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only followups,hls-native,final-hls` |
| F4 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| F5 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only gesture-pip` |
| F6 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| F7 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,followups` |
| F8 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only he-recovery,extras,he-v6-final` |
| F9 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,widgets` |
| F10 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| F11 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages,extras` |
| F12 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| F13 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| F14 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| F15 | BLOCKED | 缺可控 WHEP 服务；端口可达不证明播放。  | `manual` |
| F16 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages,gesture-pip` |
| N1 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N2 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N3 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N4 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N5 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N6 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| N7 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N8 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| N9 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only gesture-pip` |
| N10 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| N11 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| N12 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,he-firstframe,native-inputs` |
| N13 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,he-firstframe,existing-pages` |
| N14 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| N15 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only safe-visual,safe-transition` |
| N16 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| N17 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。  | `python example/tool/run_matrix.py --only widgets` |
| N18 | BLOCKED | 完整 mini/guard-off 联动需专用包和复核，主包不足。  | `manual` |
| N19 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,he-recovery,extras,he-v6-final` |
| N20 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| N21 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,widgets` |
| N22 | BLOCKED | 需专用 debug VM 构建及断言 marker；不能复用旧 APK。  | `manual` |
| N23 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-02\matrix-full-02-api.driver.log | `python example/tool/run_matrix.py --only api,followups` |

范围：v1 135 编号；gap 扩展按子项独立呈现，不能推定完整编号通过。
