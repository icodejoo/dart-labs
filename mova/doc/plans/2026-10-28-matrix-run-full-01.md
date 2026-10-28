# Android matrix run full-01

基线：`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\rerun-final-ledger.json`。仅本轮证据入账；BLOCKED 不表示产品 FAIL。

| 总数 | PASS | FAIL | BLOCKED |
|---|---|---|---|
| 135 | 0 | 0 | 135 |

| 对比 | 编号 |
|---|---|
| 新增失败 | 无 |
| 已修复 | 无 |
| 仍失败 | 无 |
| 仍阻塞 | A31, C2, C7, F15, N18 |
| 新增阻塞 | A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16, A17, A18, A19, A20, A21, A22, A23, A24, A25, A26, A27, A28, A29, A30, A32, A33, C1, C3, C4, C5, C6, C8, C9, C10, C11, C12, C13, C14, C15, C16, C17, E.MovaReady, E.MovaSourceChange, E.MovaPlay, E.MovaPause, E.MovaDone, E.MovaSeek, E.MovaSeeked, E.MovaBufferChange, E.MovaDurationChange, E.MovaFirstFrame, E.MovaSizeChange, E.MovaVolumeChange, E.MovaBrightChange, E.MovaRateChange, E.MovaQualityListChange, E.MovaQualityChange, E.MovaAbrDownShift, E.MovaFitChange, E.MovaZoomChange, E.MovaLockChange, E.MovaFullScreenChange, E.MovaOrientationChange, E.MovaPipChange, E.MovaMiniChange, E.MovaTimeShiftChange, E.MovaLiveEdgeReach, E.MovaPreviewBlock, E.MovaSttBlock, E.MovaSwapChange, E.MovaErrorEvent, E.MovaPlayFailure, E.MovaRecovered, E.MovaFailover, E.MovaStandbyChange, E.MovaStandbyResume, E1, E2, U1, U2, U3, U4, U5, U6, U7, U8, U9, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, F16, N1, N2, N3, N4, N5, N6, N7, N8, N9, N10, N11, N12, N13, N14, N15, N16, N17, N19, N20, N21, N22, N23 |
| 已解除阻塞 | 无 |

验证器问题（HARNESS；与产品缺陷分开）：

- api: 子命令失败/缺完成标记；`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log`
- existing-pages: 子命令失败/缺完成标记；`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log`
- gap-focus: ；`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gap-focus.driver.log`
- gap-screen: ；`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gap-screen.driver.log`
- driver: 设备必须已解锁且亮屏：要求 isKeyguardShowing=false、mScreenOnFully=true；不会尝试解锁。；`E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-driver.log`

| 编号 | 结论 | 原因与证据 | 最小复现入口 |
|---|---|---|---|
| A1 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A2 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A3 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only api,widgets` |
| A4 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A5 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-native-inputs.driver.log | `python example/tool/run_matrix.py --only api,extras,native-inputs` |
| A6 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A7 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| A8 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-native-inputs.driver.log | `python example/tool/run_matrix.py --only api,native-inputs` |
| A9 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only api,widgets,extras` |
| A10 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A11 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-ui.driver.log | `python example/tool/run_matrix.py --only widgets,ui` |
| A12 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-ui.driver.log | `python example/tool/run_matrix.py --only ui` |
| A13 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| A14 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-ui.driver.log | `python example/tool/run_matrix.py --only widgets,ui` |
| A15 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| A16 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-ui.driver.log | `python example/tool/run_matrix.py --only widgets,ui` |
| A17 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-followups.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-hls-native.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-final-hls.driver.log | `python example/tool/run_matrix.py --only followups,hls-native,final-hls` |
| A18 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log | `python example/tool/run_matrix.py --only gesture-pip` |
| A19 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A20 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-live-inputs.driver.log | `python example/tool/run_matrix.py --only live-inputs` |
| A21 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-touch-preview.driver.log | `python example/tool/run_matrix.py --only api,widgets,touch-preview` |
| A22 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A23 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A24 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| A25 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-keepalive-core.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| A26 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-touch-mini.driver.log | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| A27 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A28 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| A29 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log | `python example/tool/run_matrix.py --only api,interactive` |
| A30 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-transition.driver.log | `python example/tool/run_matrix.py --only api,extras,safe-transition` |
| A31 | BLOCKED | 缺真实 STT 模型/识别引擎和下载服务；失败回滚仅为子项。  | `manual` |
| A32 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| A33 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| C1 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-transition.driver.log | `python example/tool/run_matrix.py --only api,extras,safe-transition` |
| C2 | BLOCKED | 缺按 behind 返回历史媒体的服务，滑动 HLS 不等于历史回看。  | `manual` |
| C3 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log | `python example/tool/run_matrix.py --only gesture-pip,interactive` |
| C4 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-final-abr.driver.log | `python example/tool/run_matrix.py --only api,final-abr` |
| C5 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only widgets,gesture-pip,safe-visual` |
| C6 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only safe-visual` |
| C7 | BLOCKED | 同 A31，缺真实识别及导出完整证据。  | `manual` |
| C8 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only interactive,extras,safe-visual` |
| C9 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| C10 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| C11 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| C12 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-touch-mini.driver.log | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| C13 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-followups.driver.log | `python example/tool/run_matrix.py --only api,followups` |
| C14 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-recovery.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only api,he-recovery,extras` |
| C15 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-keepalive-core.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| C16 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-followups.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-final-tls.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-final-tls-probe.driver.log | `python example/tool/run_matrix.py --only followups,final-tls,final-tls-probe` |
| C17 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaReady | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSourceChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaPlay | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaPause | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaDone | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSeek | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSeeked | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaBufferChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaDurationChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaFirstFrame | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-firstframe.driver.log | `python example/tool/run_matrix.py --only he-firstframe` |
| E.MovaSizeChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| E.MovaVolumeChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaBrightChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaRateChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaQualityListChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-hls-native.driver.log | `python example/tool/run_matrix.py --only hls-native` |
| E.MovaQualityChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-hls-native.driver.log | `python example/tool/run_matrix.py --only hls-native` |
| E.MovaAbrDownShift | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-final-abr.driver.log | `python example/tool/run_matrix.py --only final-abr` |
| E.MovaFitChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| E.MovaZoomChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-ui.driver.log | `python example/tool/run_matrix.py --only ui` |
| E.MovaLockChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| E.MovaFullScreenChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| E.MovaOrientationChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| E.MovaPipChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log | `python example/tool/run_matrix.py --only gesture-pip` |
| E.MovaMiniChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| E.MovaTimeShiftChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-live-inputs.driver.log | `python example/tool/run_matrix.py --only live-inputs` |
| E.MovaLiveEdgeReach | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-live-inputs.driver.log | `python example/tool/run_matrix.py --only live-inputs` |
| E.MovaPreviewBlock | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSttBlock | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaSwapChange | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| E.MovaErrorEvent | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E.MovaPlayFailure | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-recovery.driver.log | `python example/tool/run_matrix.py --only he-recovery` |
| E.MovaRecovered | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-recovery.driver.log | `python example/tool/run_matrix.py --only he-recovery` |
| E.MovaFailover | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only extras` |
| E.MovaStandbyChange | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-keepalive-core.driver.log | `python example/tool/run_matrix.py --only keepalive-core` |
| E.MovaStandbyResume | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-keepalive-core.driver.log | `python example/tool/run_matrix.py --only keepalive-core` |
| E1 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| E2 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| U1 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| U2 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| U3 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only safe-visual` |
| U4 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-touch-preview.driver.log | `python example/tool/run_matrix.py --only touch-preview` |
| U5 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only safe-visual` |
| U6 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log | `python example/tool/run_matrix.py --only gesture-pip,interactive` |
| U7 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only safe-visual` |
| U8 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-touch-mini.driver.log | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| U9 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-recovery.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-interactive.driver.log | `python example/tool/run_matrix.py --only he-recovery,widgets,interactive` |
| F1 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| F2 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-live-inputs.driver.log | `python example/tool/run_matrix.py --only live-inputs` |
| F3 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-followups.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-hls-native.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-final-hls.driver.log | `python example/tool/run_matrix.py --only followups,hls-native,final-hls` |
| F4 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| F5 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log | `python example/tool/run_matrix.py --only gesture-pip` |
| F6 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-keepalive-core.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| F7 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-followups.driver.log | `python example/tool/run_matrix.py --only api,followups` |
| F8 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-recovery.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-v6-final.driver.log | `python example/tool/run_matrix.py --only he-recovery,extras,he-v6-final` |
| F9 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only api,widgets` |
| F10 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| F11 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only existing-pages,extras` |
| F12 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| F13 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| F14 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| F15 | BLOCKED | 缺可控 WHEP 服务；端口可达不证明播放。  | `manual` |
| F16 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log | `python example/tool/run_matrix.py --only existing-pages,gesture-pip` |
| N1 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N2 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N3 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N4 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N5 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N6 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| N7 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log | `python example/tool/run_matrix.py --only api` |
| N8 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log | `python example/tool/run_matrix.py --only api,extras` |
| N9 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-gesture-pip.driver.log | `python example/tool/run_matrix.py --only gesture-pip` |
| N10 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,existing-pages` |
| N11 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only existing-pages` |
| N12 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-firstframe.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-native-inputs.driver.log | `python example/tool/run_matrix.py --only api,he-firstframe,native-inputs` |
| N13 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-firstframe.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only api,he-firstframe,existing-pages` |
| N14 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| N15 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-transition.driver.log | `python example/tool/run_matrix.py --only safe-visual,safe-transition` |
| N16 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-safe-visual.driver.log | `python example/tool/run_matrix.py --only widgets,safe-visual` |
| N17 | BLOCKED | 缺少完整编号自动判据；现有子项结果需复核，不能复用旧 finalize 硬编码结论。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only widgets` |
| N18 | BLOCKED | 完整 mini/guard-off 联动需专用包和复核，主包不足。  | `manual` |
| N19 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-recovery.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-extras.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-he-v6-final.driver.log | `python example/tool/run_matrix.py --only api,he-recovery,extras,he-v6-final` |
| N20 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-keepalive-core.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-existing-pages.driver.log | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| N21 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-widgets.driver.log | `python example/tool/run_matrix.py --only api,widgets` |
| N22 | BLOCKED | 需专用 debug VM 构建及断言 marker；不能复用旧 APK。  | `manual` |
| N23 | BLOCKED | 覆盖批次未全部成功执行（未选择/未执行/验证器错误），不得推断产品失败。 E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-api.driver.log E:\workspaces\dart-labs\mova\example\tool\coverage_evidence\matrix-full-01\matrix-full-01-followups.driver.log | `python example/tool/run_matrix.py --only api,followups` |

Gap 扩展子项（不改变上方 v1 135 编号台账；完整证据见独立 gap.json）：

| 批次 | case | 结论 | 原因 |
|---|---|---|---|
| gap-assumptions | gap:H28.default.playing | PASS |  |
| gap-assumptions | gap:H28.default.playing | PASS |  |
| gap-assumptions | gap:H28.default.playing | PASS |  |
| gap-assumptions | gap:H28.default.paused | PASS |  |
| gap-assumptions | gap:H28.default.paused | PASS |  |
| gap-assumptions | gap:H28.default.paused | PASS |  |
| gap-assumptions | gap:H28.default.cutover | PASS |  |
| gap-assumptions | gap:H28.default.cutover | PASS |  |
| gap-assumptions | gap:H28.default.cutover | PASS |  |
| gap-assumptions | gap:H28.precise.playing | PASS |  |
| gap-assumptions | gap:H28.precise.playing | PASS |  |
| gap-assumptions | gap:H28.precise.playing | PASS |  |
| gap-assumptions | gap:H28.precise.paused | PASS |  |
| gap-assumptions | gap:H28.precise.paused | PASS |  |
| gap-assumptions | gap:H28.precise.paused | PASS |  |
| gap-assumptions | gap:H28.precise.cutover | PASS |  |
| gap-assumptions | gap:H28.precise.cutover | PASS |  |
| gap-assumptions | gap:H28.precise.cutover | PASS |  |
| gap-assumptions | gap:H20.hlsSeek | PASS |  |
| gap-assumptions | gap:H20.hlsSeek | PASS |  |
| gap-assumptions | gap:H50.hlsSeek | PASS |  |
| gap-assumptions | gap:H50.hlsSeek | PASS |  |
| gap-assumptions | gap:H7.lateError | BLOCKED | old HTTP request cancelled before late response; no error race |
| gap-assumptions | gap:H14.manualSeek | PASS |  |
| gap-assumptions | gap:H14.manualSeek | BLOCKED | seek buffering threshold not reached; ABR stress precondition absent |
| gap-assumptions | gap:H14.manualSeek | PASS |  |
| gap-assumptions | gap:H14.manualSeek | BLOCKED | seek buffering threshold not reached; ABR stress precondition absent |
| gap-assumptions | gap:H17.mp4 | PASS |  |
| gap-assumptions | gap:H17.mp4 | BLOCKED | decoder did not produce coarse landing; H17 branch unexercised |
| gap-assumptions | gap:H17.mp4 | PASS |  |
| gap-assumptions | gap:H17.mp4 | BLOCKED | decoder did not produce coarse landing; H17 branch unexercised |
| gap-assumptions | gap:H17.mp4 | PASS |  |
| gap-assumptions | gap:H17.mp4 | BLOCKED | decoder did not produce coarse landing; H17 branch unexercised |
| gap-assumptions | gap:H17.m3u8 | PASS |  |
| gap-assumptions | gap:H17.m3u8 | BLOCKED | decoder did not produce coarse landing; H17 branch unexercised |
| gap-assumptions | gap:H17.m3u8 | PASS |  |
| gap-assumptions | gap:H17.m3u8 | BLOCKED | decoder did not produce coarse landing; H17 branch unexercised |
| gap-assumptions | gap:H17.m3u8 | PASS |  |
| gap-assumptions | gap:H17.m3u8 | BLOCKED | decoder did not produce coarse landing; H17 branch unexercised |
| gap-assumptions | gap:H33.direct.404 | PASS |  |
| gap-assumptions | gap:H33.direct.refused | PASS |  |
| gap-assumptions | gap:H33.direct.dns | PASS |  |
| gap-assumptions | gap:H33.recovery.404 | PASS |  |
| gap-assumptions | gap:H33.recovery.refused | PASS |  |
| gap-assumptions | gap:H33.recovery.dns | PASS |  |
| gap-lifecycle | gap:H37.dispose | PASS |  |
| gap-lifecycle | gap:H42.wake | PASS |  |
| gap-lifecycle | gap:H42.wake | BLOCKED | manual screenshot comparison required |
| gap-lifecycle | gap:A15.miniPip | PASS |  |
| gap-lifecycle | gap:A15.miniPip | PASS |  |
| gap-local | gap:G3.1.file | PASS |  |
| gap-local | gap:G3.1.asset | PASS |  |
| gap-local | gap:G3.1.sandbox | PASS |  |
| gap-local | gap:G3.1.content | BLOCKED | requires SAF URI grant and provider; no Android provider edits permitted |
| gap-formats | gap:G3.2.decoders | PASS |  |
| gap-formats | gap:G3.2.hevcSoftware | PASS |  |
| gap-formats | gap:G3.2.long.mp4 | PASS |  |
| gap-formats | gap:G3.2.sample.mkv | PASS |  |
| gap-formats | gap:G3.2.sample.webm | PASS |  |
| gap-formats | gap:G3.2.sample.ts | PASS |  |
| gap-formats | gap:G3.2.sample.mp3 | PASS |  |
| gap-formats | gap:G3.2.sample.aac | PASS |  |
| gap-formats | gap:G3.2.sample.flac | PASS |  |
| gap-formats | gap:G3.2.sample.ogg | PASS |  |
| gap-formats | gap:G3.2.hevc.mp4 | PASS |  |
| gap-formats | gap:G3.2.tenbit.mkv | PASS |  |
| gap-formats | gap:G3.2.vp9.webm | PASS |  |
| gap-formats | gap:G3.2.av1.mkv | PASS |  |
| gap-formats | gap:G3.2.uhd.mp4 | PASS |  |
| gap-formats | gap:G3.2.excluded.avi | PASS |  |
| gap-formats | gap:G3.2.excluded.wmv | PASS |  |
| gap-formats | gap:G3.2.vp8.webm | PASS |  |
| gap-formats | gap:G3.2.sample.ac3 | PASS |  |
| gap-formats | gap:G3.2.sample.eac3 | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-random | gap:G4.1.seed | PASS |  |
| gap-focus | gap:focus.prerequisite | BLOCKED | set MOVA_GAP_FOCUS_COMPONENT to an installed player activity that starts audible playback |
| gap-network | gap:G2.2.network | BLOCKED | GAP_NETWORK_URL required; adb reverse cannot test network switching |
| gap-screen | gap:screen.prerequisite | BLOCKED | screen awake but locked: owner must unlock and rerun |

范围：v1 135 编号；gap 扩展按子项独立呈现，不能推定完整编号通过。
