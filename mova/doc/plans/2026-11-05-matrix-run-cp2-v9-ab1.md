# Android matrix run cp2-v9-ab1

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

- 无。

| 编号 | 结论 | 原因与证据 | 最小复现入口 |
|---|---|---|---|
| A1 | BLOCKED | A1/check:A1.closed: 缺 CHECK A1.closed；A1/check:A1.progress: 缺 CHECK A1.progress；A1/check:A1.events.sequence: 缺 CHECK A1.events.sequence；A1/check:A1.states.sequence: 缺 CHECK A1.states.sequence；A1/check:A1.progress.sequence: 缺 CHECK A1.progress.sequence；A1/check:A1.uiStates.sequence: 缺 CHECK A1.uiStates.sequence  | `python example/tool/run_matrix.py --only api` |
| A2 | BLOCKED | A2/event:MovaBufferChange: 缺 EVENT MovaBufferChange；A2/event:MovaSizeChange: 缺 EVENT MovaSizeChange；A2/event:MovaQualityChange: 缺 EVENT MovaQualityChange；A2/event:MovaRateChange: 缺 EVENT MovaRateChange；A2/event:MovaVolumeChange: 缺 EVENT MovaVolumeChange；A2/event:MovaBrightChange: 缺 EVENT MovaBrightChange；A2/check:A2.engine.receipt: 缺 CHECK A2.engine.receipt；A2/check:A2.cutover.receipt: 缺 CHECK A2.cutover.receipt  | `python example/tool/run_matrix.py --only api` |
| A3 | BLOCKED | A3/check:A3.audio: 缺 CHECK A3.audio；A3/check:A3.lazyBefore: 缺 CHECK A3.lazyBefore；A3/check:A3.lazyOpened: 缺 CHECK A3.lazyOpened；A3/check:A3.lazyRead: 缺 CHECK A3.lazyRead  | `python example/tool/run_matrix.py --only api,widgets` |
| A4 | BLOCKED | A4/check:A4: 缺 CHECK A4  | `python example/tool/run_matrix.py --only api` |
| A5 | BLOCKED | A5/check:A5.paused: 缺 CHECK A5.paused；A5/check:N8.accept: 缺 CHECK N8.accept；A5/check:N8.reject: 缺 CHECK N8.reject；A5/check:N8.superseded: 缺 CHECK N8.superseded；A5/check:A5.openThrows: 缺 CHECK A5.openThrows；A5/check:CONTRACT.rejectedOpen: 缺 CHECK CONTRACT.rejectedOpen  | `python example/tool/run_matrix.py --only api,extras,native-inputs,s00e-offline-contract` |
| A6 | BLOCKED | A6/check:A6.pause: 缺 CHECK A6.pause；A6/check:A6.togglePlay: 缺 CHECK A6.togglePlay；A6/check:A6.togglePause: 缺 CHECK A6.togglePause；A6/check:A6.repeatPlay: 缺 CHECK A6.repeatPlay；A6/check:A6.repeatPause: 缺 CHECK A6.repeatPause；A6/check:A6.intentIndependent: 缺 CHECK A6.intentIndependent；A6/check:A6.branchPlay: 缺 CHECK A6.branchPlay；A6/check:A6.branchPause: 缺 CHECK A6.branchPause；A6/check:CONTRACT.rejectedOpen: 缺 CHECK CONTRACT.rejectedOpen  | `python example/tool/run_matrix.py --only api,s00e-offline-contract` |
| A7 | BLOCKED | A7/check:A7.seek: 缺 CHECK A7.seek；A7/check:A7.negative: 缺 CHECK A7.negative；A7/check:A7.live: 缺 CHECK A7.live；A7/record:SEEK_LOADING: SEEK_LOADING 样本=0/1 files=*; 缺事件记录；A7/record:SEEK_BY: SEEK_BY 样本=0/1 files=*; 缺事件记录；A7/record:SEEK_BEYOND: SEEK_BEYOND 样本=0/1 files=*; 缺事件记录；A7/check:A7.retry.0: 缺 CHECK A7.retry.0；A7/check:A7.retry.1: 缺 CHECK A7.retry.1；A7/check:A7.retry.2: 缺 CHECK A7.retry.2；A7/check:A7.retry.100: 缺 CHECK A7.retry.100；A7/check:A7.native.trace: 缺 CHECK A7.native.trace；A7/check:CONTRACT.rejectedOpen: 缺 CHECK CONTRACT.rejectedOpen  | `python example/tool/run_matrix.py --only api,extras,s00e-offline-contract,s00e-native` |
| A8 | BLOCKED | A8/check:A8.clamp: 缺 CHECK A8.clamp；A8/volume:1: 缺 rerun-native-engine-volume-10.native.txt; 缺 rerun-native-engine-volume0.native.txt; 缺 rerun-native-engine-volume1.native.txt; 缺 rerun-native-engine-volume30.native.txt; 缺 rerun-native-engine-volume50.native.txt; 缺 rerun-native-engine-volume100.native.txt; 缺 rerun-native-engine-volume110.native.txt; 缺 rerun-native-cutover-volume-10.native.txt; 缺 rerun-native-cutover-volume0.native.txt; 缺 rerun-native-cutover-volume1.native.txt; 缺 rerun-native-cutover-volume30.native.txt; 缺 rerun-native-cutover-volume50.native.txt; 缺 rerun-native-cutover-volume100.native.txt; 缺 rerun-native-cutover-volume110.native.txt  | `python example/tool/run_matrix.py --only api,native-inputs` |
| A9 | BLOCKED | A9/check:A9.clamp: 缺 CHECK A9.clamp；A9/record:BRIGHTNESS_NATIVE: BRIGHTNESS_NATIVE 样本=0/6 files=*; 缺事件记录  | `python example/tool/run_matrix.py --only api,widgets,extras` |
| A10 | BLOCKED | A10/check:A10.persist: 缺 CHECK A10.persist；A10/rate_sequence:1: rerun-batch15-basic.json: requested=[], clamped=[], EVENT values=[], matched=0; rerun-batch15-basic-cutover.json: requested=[], clamped=[], EVENT values=[], matched=0  | `python example/tool/run_matrix.py --only api` |
| A11 | BLOCKED | A11/check:rerun-batch16-engine.fit.contain: 缺 CHECK rerun-batch16-engine.fit.contain；A11/check:rerun-batch16-cutover.fit.contain: 缺 CHECK rerun-batch16-cutover.fit.contain；A11/check:rerun-batch16-engine.fit.cover: 缺 CHECK rerun-batch16-engine.fit.cover；A11/check:rerun-batch16-cutover.fit.cover: 缺 CHECK rerun-batch16-cutover.fit.cover；A11/check:rerun-batch16-engine.fit.fill: 缺 CHECK rerun-batch16-engine.fit.fill；A11/check:rerun-batch16-cutover.fit.fill: 缺 CHECK rerun-batch16-cutover.fit.fill；A11/check:A11.declared: 缺 CHECK A11.declared；A11/check:A11.once: 缺 CHECK A11.once；A11/check:A11.render.contain: 缺 CHECK A11.render.contain；A11/check:A11.render.cover: 缺 CHECK A11.render.cover；A11/check:A11.render.fill: 缺 CHECK A11.render.fill  | `python example/tool/run_matrix.py --only widgets,ui` |
| A12 | BLOCKED | A12/record:VIDEO: VIDEO 样本=0/1 files=rerun-batch3-05-zoom--1.json; 缺事件记录；A12/record:VIDEO: VIDEO 样本=0/1 files=rerun-batch3-06-zoom-0.json; 缺事件记录；A12/record:VIDEO: VIDEO 样本=0/1 files=rerun-batch3-07-zoom-1.json; 缺事件记录；A12/record:VIDEO: VIDEO 样本=0/1 files=rerun-batch3-08-zoom-2.json; 缺事件记录；A12/record:VIDEO: VIDEO 样本=0/1 files=rerun-batch3-09-zoom-100.json; 缺事件记录  | `python example/tool/run_matrix.py --only ui` |
| A13 | BLOCKED | A13/check:rerun-batch16-engine.lock: 缺 CHECK rerun-batch16-engine.lock；A13/check:rerun-batch16-cutover.lock: 缺 CHECK rerun-batch16-cutover.lock；A13/check:A13.unlock.false: 缺 CHECK A13.unlock.false；A13/check:A13.unlock.true: 缺 CHECK A13.unlock.true；A13/check:A13.lock.false: 缺 CHECK A13.lock.false；A13/check:A13.lock.true: 缺 CHECK A13.lock.true；A13/check:A13.native.false: 缺 CHECK A13.native.false；A13/check:A13.native.true: 缺 CHECK A13.native.true  | `python example/tool/run_matrix.py --only widgets,s00e-native` |
| A14 | BLOCKED | A14/check:rerun-batch16-engine.fullscreen.true: 缺 CHECK rerun-batch16-engine.fullscreen.true；A14/check:rerun-batch16-cutover.fullscreen.true: 缺 CHECK rerun-batch16-cutover.fullscreen.true；A14/check:rerun-batch16-engine.fullscreen.false: 缺 CHECK rerun-batch16-engine.fullscreen.false；A14/check:rerun-batch16-cutover.fullscreen.false: 缺 CHECK rerun-batch16-cutover.fullscreen.false；A14/check:A14.window.enter: 缺 CHECK A14.window.enter；A14/check:A14.window.restore: 缺 CHECK A14.window.restore  | `python example/tool/run_matrix.py --only s00c-native,widgets,ui` |
| A15 | BLOCKED | A15/check:A15.miniStable: 缺 CHECK A15.miniStable；A15/check:A15.exit: 缺 CHECK A15.exit；A15/check:A15.miniHostToPip: 缺 CHECK A15.miniHostToPip；A15/check:A15.pipExpanded: 缺 CHECK A15.pipExpanded  | `python example/tool/run_matrix.py --only s00c-native,api,widgets` |
| A16 | BLOCKED | A16/check:A16.window.landscape: 缺 CHECK A16.window.landscape；A16/check:A16.window.portrait: 缺 CHECK A16.window.portrait；A16/check:A16.window.auto: 缺 CHECK A16.window.auto  | `python example/tool/run_matrix.py --only s00c-native,widgets,ui` |
| A17 | BLOCKED | A17/hls:0: 缺 HLS_RESULT；A17/check:CONTRACT.defaults: 缺 CHECK CONTRACT.defaults；A17/check:CONTRACT.probe.true: 缺 CHECK CONTRACT.probe.true；A17/check:CONTRACT.probe.false: 缺 CHECK CONTRACT.probe.false；A17/check:CONTRACT.replay.retry: 缺 CHECK CONTRACT.replay.retry；A17/check:CONTRACT.probe.uiOff: 缺 CHECK CONTRACT.probe.uiOff  | `python example/tool/run_matrix.py --only followups,hls-native,final-hls,s00e-offline-contract` |
| A18 | BLOCKED | A18/check:A18.pinned.enter: 缺 CHECK A18.pinned.enter；A18/check:A18.pinned.expand: 缺 CHECK A18.pinned.expand；A18/check:A18.pinned.close: 缺 CHECK A18.pinned.close；A18/check:N9.transitions: 缺 CHECK N9.transitions  | `python example/tool/run_matrix.py --only s00c-native,gesture-pip` |
| A19 | BLOCKED | A19/record:RELOAD: RELOAD 样本=0/2 files=*; 缺事件记录  | `python example/tool/run_matrix.py --only api` |
| A20 | BLOCKED | A20/record:VIDEO: VIDEO 样本=0/3 files=rerun-live-*-behind.json; 缺事件记录；A20/record:VIDEO: VIDEO 样本=0/3 files=rerun-live-*-backedge.json; 缺事件记录；A20/check:CONTRACT.replay.edge: 缺 CHECK CONTRACT.replay.edge  | `python example/tool/run_matrix.py --only live-inputs,s00e-offline-contract` |
| A21 | BLOCKED | A21/check:A21.hide: 缺 CHECK A21.hide；A21/check:A21.hud: 缺 CHECK A21.hud；A21/check:A21.sticky: 缺 CHECK A21.sticky；A21/check:A21.autoHide: 缺 CHECK A21.autoHide；A21/check:A21.dragging: 缺 CHECK A21.dragging；A21/check:A21.hudCleared: 缺 CHECK A21.hudCleared  | `python example/tool/run_matrix.py --only api,widgets,touch-preview` |
| A22 | BLOCKED | A22/check:A22: 缺 CHECK A22  | `python example/tool/run_matrix.py --only api` |
| A23 | BLOCKED | A23/check:A23.doubleDispose: 缺 CHECK A23.doubleDispose；A23/check:A23.postOpen: 缺 CHECK A23.postOpen；A23/check:A23.120: 缺 CHECK A23.120  | `python example/tool/run_matrix.py --only api` |
| A24 | BLOCKED | A24/check:A24.abandon: 缺 CHECK A24.abandon；A24/check:A24.commit: 缺 CHECK A24.commit；A24/check:A24.cutoverTo: 缺 CHECK A24.cutoverTo；A24/check:A24.retired: 缺 CHECK A24.retired；A24/check:A24.short: 缺 CHECK A24.short；A24/check:A24.timeout: 缺 CHECK A24.timeout  | `python example/tool/run_matrix.py --only api,existing-pages` |
| A25 | BLOCKED | A25/check:A25.pause: 缺 CHECK A25.pause；A25/keepalive_wake:1: keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联；A25/log:S2: keepalive-core.log: 缺完成标记；A25/log:S3: keepalive-core.log: 缺完成标记；A25/check:S6.publicFallback: 缺 CHECK S6.publicFallback；A25/log:S13: keepalive-core.log: 缺完成标记；A25/log:S17: keepalive-core.log: 缺完成标记  | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| A26 | BLOCKED | A26/check:A26.persistent: 缺 CHECK A26.persistent；A26/check:A26.tap: 缺 CHECK A26.tap；A26/check:A26.page: 缺 CHECK A26.page；A26/check:A26.setRect: 缺 CHECK A26.setRect；A26/check:A26.hide: 缺 CHECK A26.hide；A26/check:A26.close: 缺 CHECK A26.close；A26/check:U8.drag: 缺 CHECK U8.drag；A26/check:U8.snap: 缺 CHECK U8.snap；A26/check:U8.fling: 缺 CHECK U8.fling；A26/check:U8.resize: 缺 CHECK U8.resize  | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| A27 | BLOCKED | A27/check:A27.rolls: 缺 CHECK A27.rolls；A27/check:C9.waits: 缺 CHECK C9.waits  | `python example/tool/run_matrix.py --only api` |
| A28 | BLOCKED | A28/check:A28.start: 缺 CHECK A28.start；A28/check:A28.end: 缺 CHECK A28.end；A28/check:A28.auto: 缺 CHECK A28.auto  | `python example/tool/run_matrix.py --only api,extras` |
| A29 | BLOCKED | A29/check:A29.dispose: 缺 CHECK A29.dispose；A29/check:A29.final: 缺 CHECK A29.final；A29/check:A29.rangeWarm: 缺 CHECK A29.rangeWarm；A29/check:A29.poolReclaimed: 缺 CHECK A29.poolReclaimed  | `python example/tool/run_matrix.py --only api,interactive` |
| A30 | BLOCKED | A30/check:A30.diskHit: 缺 CHECK A30.diskHit；A30/check:A30.mode.vtt: 缺 CHECK A30.mode.vtt；A30/check:A30.clear.vtt: 缺 CHECK A30.clear.vtt；A30/check:A30.mode.extract: 缺 CHECK A30.mode.extract；A30/check:A30.clear.extract: 缺 CHECK A30.clear.extract；A30/check:A30.mode.fallback: 缺 CHECK A30.mode.fallback；A30/check:A30.clear.fallback: 缺 CHECK A30.clear.fallback；A30/check:A30.mode.offline: 缺 CHECK A30.mode.offline；A30/check:A30.clear.offline: 缺 CHECK A30.clear.offline；A30/check:A30.mode.blocked: 缺 CHECK A30.mode.blocked；A30/check:A30.clear.blocked: 缺 CHECK A30.clear.blocked；A30/check:A30.cancelResult: 缺 CHECK A30.cancelResult；A30/check:A30.staleResult: 缺 CHECK A30.staleResult  | `python example/tool/run_matrix.py --only api,extras,safe-transition` |
| A31 | BLOCKED | 缺真实 STT 模型/识别引擎和下载服务；失败回滚仅为子项。  | `manual` |
| A32 | BLOCKED | A32/check:A32.seekVeto: 缺 CHECK A32.seekVeto；A32/check:A32.afterThrow: 缺 CHECK A32.afterThrow；A32/check:A32.onErrorIsolation: 缺 CHECK A32.onErrorIsolation；A32/check:N8.reject: 缺 CHECK N8.reject；A32/check:N8.superseded: 缺 CHECK N8.superseded；A32/check:CONTRACT.rejectedOpen: 缺 CHECK CONTRACT.rejectedOpen  | `python example/tool/run_matrix.py --only api,s00e-offline-contract` |
| A33 | BLOCKED | A33/check:A33: 缺 CHECK A33  | `python example/tool/run_matrix.py --only api` |
| C1 | BLOCKED | C1/check:A30.mode.vtt: 缺 CHECK A30.mode.vtt；C1/check:A30.clear.vtt: 缺 CHECK A30.clear.vtt；C1/check:A30.mode.extract: 缺 CHECK A30.mode.extract；C1/check:A30.clear.extract: 缺 CHECK A30.clear.extract；C1/check:A30.mode.fallback: 缺 CHECK A30.mode.fallback；C1/check:A30.clear.fallback: 缺 CHECK A30.clear.fallback；C1/check:A30.mode.offline: 缺 CHECK A30.mode.offline；C1/check:A30.clear.offline: 缺 CHECK A30.clear.offline；C1/check:A30.mode.blocked: 缺 CHECK A30.mode.blocked；C1/check:A30.clear.blocked: 缺 CHECK A30.clear.blocked；C1/check:A30.cancelResult: 缺 CHECK A30.cancelResult；C1/check:A30.staleResult: 缺 CHECK A30.staleResult  | `python example/tool/run_matrix.py --only api,extras,safe-transition` |
| C2 | BLOCKED | 缺按 behind 返回历史媒体的服务，滑动 HLS 不等于历史回看。  | `manual` |
| C3 | BLOCKED | C3/check:C3.left.false: 缺 CHECK C3.left.false；C3/check:C3.right.false: 缺 CHECK C3.right.false；C3/check:U6.tap.false: 缺 CHECK U6.tap.false；C3/check:U6.doubleRight.false: 缺 CHECK U6.doubleRight.false；C3/check:U6.doubleLeft.false: 缺 CHECK U6.doubleLeft.false；C3/check:U6.horizontal.false: 缺 CHECK U6.horizontal.false；C3/check:U6.pinch.false: 缺 CHECK U6.pinch.false；C3/check:U6.longPress.false: 缺 CHECK U6.longPress.false；C3/check:U6.region.false: 缺 CHECK U6.region.false；C3/check:C3.left.true: 缺 CHECK C3.left.true；C3/check:C3.right.true: 缺 CHECK C3.right.true；C3/check:U6.tap.true: 缺 CHECK U6.tap.true；C3/check:U6.doubleRight.true: 缺 CHECK U6.doubleRight.true；C3/check:U6.doubleLeft.true: 缺 CHECK U6.doubleLeft.true；C3/check:U6.horizontal.true: 缺 CHECK U6.horizontal.true；C3/check:U6.pinch.true: 缺 CHECK U6.pinch.true；C3/check:U6.longPress.true: 缺 CHECK U6.longPress.true；C3/check:U6.region.true: 缺 CHECK U6.region.true；C3/check:U6.map.none.false.false: 缺 CHECK U6.map.none.false.false；C3/check:U6.map.none.false.true: 缺 CHECK U6.map.none.false.true；C3/check:U6.map.none.true.false: 缺 CHECK U6.map.none.true.false；C3/check:U6.map.none.true.true: 缺 CHECK U6.map.none.true.true；C3/check:U6.map.volume.false.false: 缺 CHECK U6.map.volume.false.false；C3/check:U6.map.volume.false.true: 缺 CHECK U6.map.volume.false.true；C3/check:U6.map.volume.true.false: 缺 CHECK U6.map.volume.true.false；C3/check:U6.map.volume.true.true: 缺 CHECK U6.map.volume.true.true；C3/check:U6.map.brightness.false.false: 缺 CHECK U6.map.brightness.false.false；C3/check:U6.map.brightness.false.true: 缺 CHECK U6.map.brightness.false.true；C3/check:U6.map.brightness.true.false: 缺 CHECK U6.map.brightness.true.false；C3/check:U6.map.brightness.true.true: 缺 CHECK U6.map.brightness.true.true；C3/check:U6.map.seek.false.false: 缺 CHECK U6.map.seek.false.false；C3/check:U6.map.seek.false.true: 缺 CHECK U6.map.seek.false.true；C3/check:U6.map.seek.true.false: 缺 CHECK U6.map.seek.true.false；C3/check:U6.map.seek.true.true: 缺 CHECK U6.map.seek.true.true；C3/check:U6.douyin.tap: 缺 CHECK U6.douyin.tap；C3/check:U6.douyin.double: 缺 CHECK U6.douyin.double；C3/check:U6.douyin.drag: 缺 CHECK U6.douyin.drag；C3/check:A13.native.false: 缺 CHECK A13.native.false；C3/check:A13.native.true: 缺 CHECK A13.native.true；C3/check:U6.disabled.double.none.false.false: 缺 CHECK U6.disabled.double.none.false.false；C3/check:U6.disabled.pinch.none.false.false: 缺 CHECK U6.disabled.pinch.none.false.false；C3/check:U6.disabled.double.none.false.true: 缺 CHECK U6.disabled.double.none.false.true；C3/check:U6.disabled.pinch.none.false.true: 缺 CHECK U6.disabled.pinch.none.false.true；C3/check:U6.disabled.double.none.true.false: 缺 CHECK U6.disabled.double.none.true.false；C3/check:U6.disabled.pinch.none.true.false: 缺 CHECK U6.disabled.pinch.none.true.false；C3/check:U6.disabled.double.none.true.true: 缺 CHECK U6.disabled.double.none.true.true；C3/check:U6.disabled.pinch.none.true.true: 缺 CHECK U6.disabled.pinch.none.true.true；C3/check:U6.disabled.double.volume.false.false: 缺 CHECK U6.disabled.double.volume.false.false；C3/check:U6.disabled.pinch.volume.false.false: 缺 CHECK U6.disabled.pinch.volume.false.false；C3/check:U6.disabled.double.volume.false.true: 缺 CHECK U6.disabled.double.volume.false.true；C3/check:U6.disabled.pinch.volume.false.true: 缺 CHECK U6.disabled.pinch.volume.false.true；C3/check:U6.disabled.double.volume.true.false: 缺 CHECK U6.disabled.double.volume.true.false；C3/check:U6.disabled.pinch.volume.true.false: 缺 CHECK U6.disabled.pinch.volume.true.false；C3/check:U6.disabled.double.volume.true.true: 缺 CHECK U6.disabled.double.volume.true.true；C3/check:U6.disabled.pinch.volume.true.true: 缺 CHECK U6.disabled.pinch.volume.true.true；C3/check:U6.disabled.double.brightness.false.false: 缺 CHECK U6.disabled.double.brightness.false.false；C3/check:U6.disabled.pinch.brightness.false.false: 缺 CHECK U6.disabled.pinch.brightness.false.false；C3/check:U6.disabled.double.brightness.false.true: 缺 CHECK U6.disabled.double.brightness.false.true；C3/check:U6.disabled.pinch.brightness.false.true: 缺 CHECK U6.disabled.pinch.brightness.false.true；C3/check:U6.disabled.double.brightness.true.false: 缺 CHECK U6.disabled.double.brightness.true.false；C3/check:U6.disabled.pinch.brightness.true.false: 缺 CHECK U6.disabled.pinch.brightness.true.false；C3/check:U6.disabled.double.brightness.true.true: 缺 CHECK U6.disabled.double.brightness.true.true；C3/check:U6.disabled.pinch.brightness.true.true: 缺 CHECK U6.disabled.pinch.brightness.true.true；C3/check:U6.disabled.double.seek.false.false: 缺 CHECK U6.disabled.double.seek.false.false；C3/check:U6.disabled.pinch.seek.false.false: 缺 CHECK U6.disabled.pinch.seek.false.false；C3/check:U6.disabled.double.seek.false.true: 缺 CHECK U6.disabled.double.seek.false.true；C3/check:U6.disabled.pinch.seek.false.true: 缺 CHECK U6.disabled.pinch.seek.false.true；C3/check:U6.disabled.double.seek.true.false: 缺 CHECK U6.disabled.double.seek.true.false；C3/check:U6.disabled.pinch.seek.true.false: 缺 CHECK U6.disabled.pinch.seek.true.false；C3/check:U6.disabled.double.seek.true.true: 缺 CHECK U6.disabled.double.seek.true.true；C3/check:U6.disabled.pinch.seek.true.true: 缺 CHECK U6.disabled.pinch.seek.true.true；C3/check:U6.dvr.false: 缺 CHECK U6.dvr.false；C3/check:U6.dvr.true: 缺 CHECK U6.dvr.true  | `python example/tool/run_matrix.py --only gesture-pip,interactive,s00e-offline-widgets,s00e-native` |
| C4 | BLOCKED | C4/check:C4.abrDown: 缺 CHECK C4.abrDown；C4/check:CONTRACT.defaults: 缺 CHECK CONTRACT.defaults；C4/check:CONTRACT.probe.true: 缺 CHECK CONTRACT.probe.true；C4/check:CONTRACT.probe.false: 缺 CHECK CONTRACT.probe.false  | `python example/tool/run_matrix.py --only api,final-abr,s00e-offline-contract` |
| C5 | BLOCKED | C5/check:C5.start.true.true: 缺 CHECK C5.start.true.true；C5/check:C5.reset.true.true: 缺 CHECK C5.reset.true.true；C5/check:C5.auto.true.true: 缺 CHECK C5.auto.true.true；C5/check:C5.sticky.true.true: 缺 CHECK C5.sticky.true.true；C5/check:C5.hide.true.true: 缺 CHECK C5.hide.true.true；C5/check:C5.start.true.false: 缺 CHECK C5.start.true.false；C5/check:C5.reset.true.false: 缺 CHECK C5.reset.true.false；C5/check:C5.auto.true.false: 缺 CHECK C5.auto.true.false；C5/check:C5.sticky.true.false: 缺 CHECK C5.sticky.true.false；C5/check:C5.hide.true.false: 缺 CHECK C5.hide.true.false；C5/check:C5.start.false.true: 缺 CHECK C5.start.false.true；C5/check:C5.reset.false.true: 缺 CHECK C5.reset.false.true；C5/check:C5.auto.false.true: 缺 CHECK C5.auto.false.true；C5/check:C5.sticky.false.true: 缺 CHECK C5.sticky.false.true；C5/check:C5.hide.false.true: 缺 CHECK C5.hide.false.true；C5/check:C5.start.false.false: 缺 CHECK C5.start.false.false；C5/check:C5.reset.false.false: 缺 CHECK C5.reset.false.false；C5/check:C5.auto.false.false: 缺 CHECK C5.auto.false.false；C5/check:C5.sticky.false.false: 缺 CHECK C5.sticky.false.false；C5/check:C5.hide.false.false: 缺 CHECK C5.hide.false.false；C5/check:C5.defaults: 缺 CHECK C5.defaults；C5/check:C5.paint.true.true: 缺 CHECK C5.paint.true.true；C5/check:C5.paint.true.false: 缺 CHECK C5.paint.true.false；C5/check:C5.paint.false.true: 缺 CHECK C5.paint.false.true；C5/check:C5.paint.false.false: 缺 CHECK C5.paint.false.false  | `python example/tool/run_matrix.py --only widgets,gesture-pip,safe-visual` |
| C6 | BLOCKED | C6/check:C6.spawn.false: 缺 CHECK C6.spawn.false；C6/check:C6.spawn.true: 缺 CHECK C6.spawn.true；C6/check:C6.scroll: 缺 CHECK C6.scroll；C6/check:C6.unique: 缺 CHECK C6.unique；C6/check:C6.retired: 缺 CHECK C6.retired  | `python example/tool/run_matrix.py --only safe-visual` |
| C7 | BLOCKED | 同 A31，缺真实识别及导出完整证据。  | `manual` |
| C8 | BLOCKED | C8/check:C8.card.true: 缺 CHECK C8.card.true；C8/check:C8.cancel.true: 缺 CHECK C8.cancel.true；C8/check:C8.auto.true: 缺 CHECK C8.auto.true；C8/check:C8.card.false: 缺 CHECK C8.card.false；C8/check:C8.cancel.false: 缺 CHECK C8.cancel.false；C8/check:C8.auto.false: 缺 CHECK C8.auto.false；C8/check:C8.now: 缺 CHECK C8.now  | `python example/tool/run_matrix.py --only interactive,extras,safe-visual` |
| C9 | BLOCKED | C9/check:C9.waits: 缺 CHECK C9.waits；C9/check:A27.rolls: 缺 CHECK A27.rolls  | `python example/tool/run_matrix.py --only api` |
| C10 | BLOCKED | C10/check:C10.theme.default: 缺 CHECK C10.theme.default；C10/check:C10.theme.bilibili: 缺 CHECK C10.theme.bilibili；C10/check:C10.theme.douyin: 缺 CHECK C10.theme.douyin；C10/check:C10.strings.default: 缺 CHECK C10.strings.default；C10/check:C10.strings.bilibili: 缺 CHECK C10.strings.bilibili；C10/check:C10.accent.douyin: 缺 CHECK C10.accent.douyin；C10/check:C10.buffering: 缺 CHECK C10.buffering；C10/check:C10.theme.mini: 缺 CHECK C10.theme.mini  | `python example/tool/run_matrix.py --only widgets,safe-visual,gap-skin` |
| C11 | BLOCKED | C11/check:C11.off: 缺 CHECK C11.off；C11/check:A24.commit: 缺 CHECK A24.commit；C11/check:A24.cutoverTo: 缺 CHECK A24.cutoverTo  | `python example/tool/run_matrix.py --only api,existing-pages` |
| C12 | BLOCKED | C12/check:C12.defaultOff: 缺 CHECK C12.defaultOff；C12/check:A26.persistent: 缺 CHECK A26.persistent；C12/check:A26.tap: 缺 CHECK A26.tap；C12/check:A26.page: 缺 CHECK A26.page；C12/check:A26.setRect: 缺 CHECK A26.setRect；C12/check:A26.hide: 缺 CHECK A26.hide；C12/check:A26.close: 缺 CHECK A26.close；C12/check:U8.drag: 缺 CHECK U8.drag；C12/check:U8.snap: 缺 CHECK U8.snap；C12/check:U8.fling: 缺 CHECK U8.fling；C12/check:U8.resize: 缺 CHECK U8.resize  | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| C13 | BLOCKED | C13/check:C13.off: 缺 CHECK C13.off；C13/check:C13.defaultHeartbeat: 缺 CHECK C13.defaultHeartbeat；C13/check:F7.false.ended.endCount: 缺 CHECK F7.false.ended.endCount；C13/check:F7.false.ended.summary: 缺 CHECK F7.false.ended.summary；C13/check:F7.false.ended.truncated: 缺 CHECK F7.false.ended.truncated；C13/check:F7.false.ended.firstFrameCount: 缺 CHECK F7.false.ended.firstFrameCount；C13/check:F7.false.ended.firstFrame: 缺 CHECK F7.false.ended.firstFrame；C13/check:F7.false.stopped.endCount: 缺 CHECK F7.false.stopped.endCount；C13/check:F7.false.stopped.summary: 缺 CHECK F7.false.stopped.summary；C13/check:F7.false.stopped.truncated: 缺 CHECK F7.false.stopped.truncated；C13/check:F7.false.stopped.firstFrameCount: 缺 CHECK F7.false.stopped.firstFrameCount；C13/check:F7.false.stopped.firstFrame: 缺 CHECK F7.false.stopped.firstFrame；C13/check:F7.false.failed.endCount: 缺 CHECK F7.false.failed.endCount；C13/check:F7.false.failed.summary: 缺 CHECK F7.false.failed.summary；C13/check:F7.false.failed.truncated: 缺 CHECK F7.false.failed.truncated；C13/check:F7.false.failed.firstFrameCount: 缺 CHECK F7.false.failed.firstFrameCount；C13/check:F7.false.failed.firstFrame: 缺 CHECK F7.false.failed.firstFrame；C13/check:F7.false.abandoned.endCount: 缺 CHECK F7.false.abandoned.endCount；C13/check:F7.false.abandoned.summary: 缺 CHECK F7.false.abandoned.summary；C13/check:F7.false.abandoned.truncated: 缺 CHECK F7.false.abandoned.truncated；C13/check:F7.false.truncated.endCount: 缺 CHECK F7.false.truncated.endCount；C13/check:F7.false.truncated.summary: 缺 CHECK F7.false.truncated.summary；C13/check:F7.false.truncated.truncated: 缺 CHECK F7.false.truncated.truncated；C13/check:F7.false.truncated.firstFrameCount: 缺 CHECK F7.false.truncated.firstFrameCount；C13/check:F7.false.truncated.firstFrame: 缺 CHECK F7.false.truncated.firstFrame；C13/check:F7.false.disabled.endCount: 缺 CHECK F7.false.disabled.endCount；C13/check:F7.false.disabled.summary: 缺 CHECK F7.false.disabled.summary；C13/check:F7.false.disabled.truncated: 缺 CHECK F7.false.disabled.truncated；C13/check:F7.false.disabled.firstFrameCount: 缺 CHECK F7.false.disabled.firstFrameCount；C13/check:F7.false.disabled.firstFrame: 缺 CHECK F7.false.disabled.firstFrame；C13/check:F7.true.ended.endCount: 缺 CHECK F7.true.ended.endCount；C13/check:F7.true.ended.summary: 缺 CHECK F7.true.ended.summary；C13/check:F7.true.ended.truncated: 缺 CHECK F7.true.ended.truncated；C13/check:F7.true.ended.firstFrameCount: 缺 CHECK F7.true.ended.firstFrameCount；C13/check:F7.true.ended.firstFrame: 缺 CHECK F7.true.ended.firstFrame；C13/check:F7.true.stopped.endCount: 缺 CHECK F7.true.stopped.endCount；C13/check:F7.true.stopped.summary: 缺 CHECK F7.true.stopped.summary；C13/check:F7.true.stopped.truncated: 缺 CHECK F7.true.stopped.truncated；C13/check:F7.true.stopped.firstFrameCount: 缺 CHECK F7.true.stopped.firstFrameCount；C13/check:F7.true.stopped.firstFrame: 缺 CHECK F7.true.stopped.firstFrame；C13/check:F7.true.failed.endCount: 缺 CHECK F7.true.failed.endCount；C13/check:F7.true.failed.summary: 缺 CHECK F7.true.failed.summary；C13/check:F7.true.failed.truncated: 缺 CHECK F7.true.failed.truncated；C13/check:F7.true.failed.firstFrameCount: 缺 CHECK F7.true.failed.firstFrameCount；C13/check:F7.true.failed.firstFrame: 缺 CHECK F7.true.failed.firstFrame；C13/check:F7.true.abandoned.endCount: 缺 CHECK F7.true.abandoned.endCount；C13/check:F7.true.abandoned.summary: 缺 CHECK F7.true.abandoned.summary；C13/check:F7.true.abandoned.truncated: 缺 CHECK F7.true.abandoned.truncated；C13/check:F7.true.truncated.endCount: 缺 CHECK F7.true.truncated.endCount；C13/check:F7.true.truncated.summary: 缺 CHECK F7.true.truncated.summary；C13/check:F7.true.truncated.truncated: 缺 CHECK F7.true.truncated.truncated；C13/check:F7.true.truncated.firstFrameCount: 缺 CHECK F7.true.truncated.firstFrameCount；C13/check:F7.true.truncated.firstFrame: 缺 CHECK F7.true.truncated.firstFrame；C13/check:F7.true.disabled.endCount: 缺 CHECK F7.true.disabled.endCount；C13/check:F7.true.disabled.summary: 缺 CHECK F7.true.disabled.summary；C13/check:F7.true.disabled.truncated: 缺 CHECK F7.true.disabled.truncated；C13/check:F7.true.disabled.firstFrameCount: 缺 CHECK F7.true.disabled.firstFrameCount；C13/check:F7.true.disabled.firstFrame: 缺 CHECK F7.true.disabled.firstFrame；C13/check:F7.heartbeat: 缺 CHECK F7.heartbeat；C13/check:F7.nativeFirstFrame: 缺 CHECK F7.nativeFirstFrame；C13/check:F7.nativeSample: 缺 CHECK F7.nativeSample；C13/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-ended.json; 缺事件记录；C13/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-stopped.json; 缺事件记录；C13/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-failed.json; 缺事件记录；C13/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-abandoned.json; 缺事件记录；C13/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-truncated.json; 缺事件记录；C13/record:REPORT: REPORT 样本=0/1 files=*batch17-qoe-stall-release.json; 缺事件记录  | `python example/tool/run_matrix.py --only api,followups` |
| C14 | BLOCKED | C14/log:V5: he-recovery.log: 缺完成标记；C14/log:V6: he-recovery.log: 缺完成标记；C14/log:V7: he-recovery.log: 缺完成标记；C14/log:V8: he-recovery.log: 缺完成标记；C14/check:CONTRACT.error.overlay.nonterminal: 缺 CHECK CONTRACT.error.overlay.nonterminal；C14/check:CONTRACT.error.overlay.terminal: 缺 CHECK CONTRACT.error.overlay.terminal  | `python example/tool/run_matrix.py --only api,he-recovery,extras` |
| C15 | BLOCKED | C15/check:C15.maxDuration: 缺 CHECK C15.maxDuration；C15/keepalive_wake:1: keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联；C15/log:S2: keepalive-core.log: 缺完成标记；C15/log:S3: keepalive-core.log: 缺完成标记；C15/check:S6.publicFallback: 缺 CHECK S6.publicFallback；C15/log:S13: keepalive-core.log: 缺完成标记；C15/log:S17: keepalive-core.log: 缺完成标记  | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| C16 | BLOCKED | C16/check:C16.matrix: 缺 CHECK C16.matrix；C16/check:C16.probe: 缺 CHECK C16.probe  | `python example/tool/run_matrix.py --only followups,final-tls,final-tls-probe` |
| C17 | BLOCKED | C17/check:C17.pick: 缺 CHECK C17.pick；C17/check:N4.applied: 缺 CHECK N4.applied；C17/check:N4.restore: 缺 CHECK N4.restore；C17/check:N19.failover: 缺 CHECK N19.failover；C17/check:C17.sameAs: 缺 CHECK C17.sameAs；C17/check:C17.headers.one: 缺 CHECK C17.headers.one；C17/check:C17.headers.two: 缺 CHECK C17.headers.two  | `python example/tool/run_matrix.py --only api` |
| E.MovaReady | BLOCKED | E.MovaReady/event:MovaReady: 缺 EVENT MovaReady  | `python example/tool/run_matrix.py --only api` |
| E.MovaSourceChange | BLOCKED | E.MovaSourceChange/event:MovaSourceChange: 缺 EVENT MovaSourceChange  | `python example/tool/run_matrix.py --only api` |
| E.MovaPlay | BLOCKED | E.MovaPlay/event:MovaPlay: 缺 EVENT MovaPlay  | `python example/tool/run_matrix.py --only api` |
| E.MovaPause | BLOCKED | E.MovaPause/event:MovaPause: 缺 EVENT MovaPause  | `python example/tool/run_matrix.py --only api` |
| E.MovaDone | BLOCKED | E.MovaDone/event:MovaDone: 缺 EVENT MovaDone  | `python example/tool/run_matrix.py --only api` |
| E.MovaSeek | BLOCKED | E.MovaSeek/event:MovaSeek: 缺 EVENT MovaSeek  | `python example/tool/run_matrix.py --only api` |
| E.MovaSeeked | BLOCKED | E.MovaSeeked/event:MovaSeeked: 缺 EVENT MovaSeeked  | `python example/tool/run_matrix.py --only api` |
| E.MovaBufferChange | BLOCKED | E.MovaBufferChange/event:MovaBufferChange: 缺 EVENT MovaBufferChange  | `python example/tool/run_matrix.py --only api` |
| E.MovaDurationChange | BLOCKED | E.MovaDurationChange/event:MovaDurationChange: 缺 EVENT MovaDurationChange  | `python example/tool/run_matrix.py --only api` |
| E.MovaFirstFrame | BLOCKED | E.MovaFirstFrame/event:MovaFirstFrame: 缺 EVENT MovaFirstFrame  | `python example/tool/run_matrix.py --only he-firstframe` |
| E.MovaSizeChange | BLOCKED | E.MovaSizeChange/event:MovaSizeChange: 缺 EVENT MovaSizeChange  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaVolumeChange | BLOCKED | E.MovaVolumeChange/event:MovaVolumeChange: 缺 EVENT MovaVolumeChange  | `python example/tool/run_matrix.py --only api` |
| E.MovaBrightChange | BLOCKED | E.MovaBrightChange/event:MovaBrightChange: 缺 EVENT MovaBrightChange  | `python example/tool/run_matrix.py --only api` |
| E.MovaRateChange | BLOCKED | E.MovaRateChange/event:MovaRateChange: 缺 EVENT MovaRateChange  | `python example/tool/run_matrix.py --only api` |
| E.MovaQualityListChange | BLOCKED | E.MovaQualityListChange/event:MovaQualityListChange: 缺 EVENT MovaQualityListChange  | `python example/tool/run_matrix.py --only hls-native` |
| E.MovaQualityChange | BLOCKED | E.MovaQualityChange/event:MovaQualityChange: 缺 EVENT MovaQualityChange  | `python example/tool/run_matrix.py --only hls-native` |
| E.MovaAbrDownShift | BLOCKED | E.MovaAbrDownShift/event:MovaAbrDownShift: 缺 EVENT MovaAbrDownShift  | `python example/tool/run_matrix.py --only final-abr` |
| E.MovaFitChange | BLOCKED | E.MovaFitChange/event:MovaFitChange: 缺 EVENT MovaFitChange  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaZoomChange | BLOCKED | E.MovaZoomChange/event:MovaZoomChange: 缺 EVENT MovaZoomChange  | `python example/tool/run_matrix.py --only ui` |
| E.MovaLockChange | BLOCKED | E.MovaLockChange/event:MovaLockChange: 缺 EVENT MovaLockChange  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaFullScreenChange | BLOCKED | E.MovaFullScreenChange/event:MovaFullScreenChange: 缺 EVENT MovaFullScreenChange  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaOrientationChange | BLOCKED | E.MovaOrientationChange/event:MovaOrientationChange: 缺 EVENT MovaOrientationChange  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaPipChange | BLOCKED | E.MovaPipChange/event:MovaPipChange: 缺 EVENT MovaPipChange  | `python example/tool/run_matrix.py --only gesture-pip` |
| E.MovaMiniChange | BLOCKED | E.MovaMiniChange/event:MovaMiniChange: 缺 EVENT MovaMiniChange  | `python example/tool/run_matrix.py --only widgets` |
| E.MovaTimeShiftChange | BLOCKED | E.MovaTimeShiftChange/event:MovaTimeShiftChange: 缺 EVENT MovaTimeShiftChange  | `python example/tool/run_matrix.py --only live-inputs` |
| E.MovaLiveEdgeReach | BLOCKED | E.MovaLiveEdgeReach/event:MovaLiveEdgeReach: 缺 EVENT MovaLiveEdgeReach  | `python example/tool/run_matrix.py --only live-inputs` |
| E.MovaPreviewBlock | BLOCKED | E.MovaPreviewBlock/event:MovaPreviewBlock: 缺 EVENT MovaPreviewBlock；E.MovaPreviewBlock/check:E.MovaPreviewBlock.network: 缺 CHECK E.MovaPreviewBlock.network  | `python example/tool/run_matrix.py --only api` |
| E.MovaSttBlock | BLOCKED | E.MovaSttBlock/event:MovaSttBlock: 缺 EVENT MovaSttBlock  | `python example/tool/run_matrix.py --only api` |
| E.MovaSwapChange | BLOCKED | E.MovaSwapChange/event:MovaSwapChange: 缺 EVENT MovaCutoverChange  | `python example/tool/run_matrix.py --only existing-pages` |
| E.MovaErrorEvent | BLOCKED | E.MovaErrorEvent/event:MovaErrorEvent: 缺 EVENT MovaErrorEvent；E.MovaErrorEvent/check:CONTRACT.error.nonterminal: 缺 CHECK CONTRACT.error.nonterminal；E.MovaErrorEvent/check:CONTRACT.error.terminal: 缺 CHECK CONTRACT.error.terminal  | `python example/tool/run_matrix.py --only api,s00e-offline-contract` |
| E.MovaPlayFailure | BLOCKED | E.MovaPlayFailure/event:MovaPlayFailure: 缺 EVENT MovaPlayFailure  | `python example/tool/run_matrix.py --only he-recovery` |
| E.MovaRecovered | BLOCKED | E.MovaRecovered/event:MovaRecovered: 缺 EVENT MovaRecovered  | `python example/tool/run_matrix.py --only he-recovery` |
| E.MovaFailover | BLOCKED | E.MovaFailover/event:MovaFailover: 缺 EVENT MovaFailover  | `python example/tool/run_matrix.py --only extras` |
| E.MovaStandbyChange | BLOCKED | E.MovaStandbyChange/event:MovaStandbyChange: 缺 EVENT MovaKeepAliveChange  | `python example/tool/run_matrix.py --only keepalive-core` |
| E.MovaStandbyResume | BLOCKED | E.MovaStandbyResume/event:MovaStandbyResume: 缺 EVENT MovaKeepAliveResume  | `python example/tool/run_matrix.py --only keepalive-core` |
| E1 | BLOCKED | E1/lifecycle:0: 缺自然生命周期事件序列  | `python example/tool/run_matrix.py --only api` |
| E2 | BLOCKED | E2/check:E2.disabled: 缺 CHECK E2.disabled；E2/check:C11.off: 缺 CHECK C11.off；E2/check:C13.off: 缺 CHECK C13.off  | `python example/tool/run_matrix.py --only api` |
| U1 | BLOCKED | U1/check:U1.surface: 缺 CHECK U1.surface；U1/check:U1.borrowed: 缺 CHECK U1.borrowed；U1/check:U1.feedOwned: 缺 CHECK U1.feedOwned；U1/check:U1.feedSource: 缺 CHECK U1.feedSource；U1/check:U1.feedDispose: 缺 CHECK U1.feedDispose；U1/check:U1.native.surface: 缺 CHECK U1.native.surface；U1/check:U1.native.player.mounted: 缺 CHECK U1.native.player.mounted；U1/check:U1.native.borrowed: 缺 CHECK U1.native.borrowed；U1/check:U1.native.player.disposed: 缺 CHECK U1.native.player.disposed；U1/check:U1.native.view.lazy: 缺 CHECK U1.native.view.lazy；U1/check:U1.native.view.source: 缺 CHECK U1.native.view.source；U1/check:U1.native.view.disposed: 缺 CHECK U1.native.view.disposed；U1/check:U1.native.feed: 缺 CHECK U1.native.feed；U1/check:U9.native.ticker: 缺 CHECK U9.native.ticker；U1/check:U9.native.route: 缺 CHECK U9.native.route  | `python example/tool/run_matrix.py --only widgets,safe-visual,s00e-native` |
| U2 | BLOCKED | U2/check:U2.componentNames: 缺 CHECK U2.componentNames；U2/check:U2.tree.default: 缺 CHECK U2.tree.default；U2/check:U2.mounted.default: 缺 CHECK U2.mounted.default；U2/check:U2.tree.bilibili: 缺 CHECK U2.tree.bilibili；U2/check:U2.mounted.bilibili: 缺 CHECK U2.mounted.bilibili；U2/check:U2.tree.douyin: 缺 CHECK U2.tree.douyin；U2/check:U2.mounted.douyin: 缺 CHECK U2.mounted.douyin；U2/check:U2.tree.minimal: 缺 CHECK U2.tree.minimal；U2/check:U2.mounted.minimal: 缺 CHECK U2.mounted.minimal；U2/check:U2.tree.mini: 缺 CHECK U2.tree.mini；U2/check:U2.mounted.mini: 缺 CHECK U2.mounted.mini；U2/check:U2.patchNoop: 缺 CHECK U2.patchNoop；U2/check:U2.patchTree.default: 缺 CHECK U2.patchTree.default；U2/check:U2.patchMounted.default: 缺 CHECK U2.patchMounted.default；U2/check:U2.patchClick.default.gapAdd: 缺 CHECK U2.patchClick.default.gapAdd；U2/check:U2.patchClick.default.gapReplace: 缺 CHECK U2.patchClick.default.gapReplace；U2/check:U2.patchClick.default.gapInsert: 缺 CHECK U2.patchClick.default.gapInsert；U2/check:U2.patchTree.bilibili: 缺 CHECK U2.patchTree.bilibili；U2/check:U2.patchMounted.bilibili: 缺 CHECK U2.patchMounted.bilibili；U2/check:U2.patchClick.bilibili.gapInsert: 缺 CHECK U2.patchClick.bilibili.gapInsert；U2/check:U2.patchClick.bilibili.gapOverlay: 缺 CHECK U2.patchClick.bilibili.gapOverlay；U2/check:CONTRACT.error.overlay.nonterminal: 缺 CHECK CONTRACT.error.overlay.nonterminal；U2/check:CONTRACT.error.overlay.terminal: 缺 CHECK CONTRACT.error.overlay.terminal  | `python example/tool/run_matrix.py --only widgets,safe-visual,gap-skin,s00e-offline-contract` |
| U3 | BLOCKED | U3/check:U3.title: 缺 CHECK U3.title；U3/check:U3.pipHidden: 缺 CHECK U3.pipHidden；U3/check:U3.fit: 缺 CHECK U3.fit；U3/check:U3.fullscreenOn: 缺 CHECK U3.fullscreenOn；U3/check:U3.fullscreenOff: 缺 CHECK U3.fullscreenOff；U3/check:U3.qualityCount: 缺 CHECK U3.qualityCount；U3/check:U3.qualityMenu: 缺 CHECK U3.qualityMenu；U3/check:U3.qualitySelect: 缺 CHECK U3.qualitySelect；U3/check:U3.pipClick: 缺 CHECK U3.pipClick；U3/check:U3.directionDesktop: 缺 CHECK U3.directionDesktop；U3/check:U3.directionMobile: 缺 CHECK U3.directionMobile；U3/check:U3.direction1: 缺 CHECK U3.direction1；U3/check:U3.direction2: 缺 CHECK U3.direction2；U3/check:CONTRACT.probe.true: 缺 CHECK CONTRACT.probe.true；U3/check:CONTRACT.probe.false: 缺 CHECK CONTRACT.probe.false；U3/check:CONTRACT.probe.uiOff: 缺 CHECK CONTRACT.probe.uiOff  | `python example/tool/run_matrix.py --only safe-visual,s00e-offline-contract` |
| U4 | BLOCKED | U4/check:U4.disabled: 缺 CHECK U4.disabled；U4/check:U4.enabled: 缺 CHECK U4.enabled；U4/check:U4.drag: 缺 CHECK U4.drag；U4/check:U4.commit: 缺 CHECK U4.commit；U4/check:U4.label: 缺 CHECK U4.label；U4/check:U4.live.false.edge: 缺 CHECK U4.live.false.edge；U4/check:U4.live.true.edge: 缺 CHECK U4.live.true.edge；U4/check:U4.live.span: 缺 CHECK U4.live.span；U4/check:U4.live.behind: 缺 CHECK U4.live.behind；U4/check:U4.live.back: 缺 CHECK U4.live.back；U4/check:U4.preview.render: 缺 CHECK U4.preview.render；U4/check:U4.preview.release: 缺 CHECK U4.preview.release；U4/check:U4.throttle.window: 缺 CHECK U4.throttle.window；U4/check:U4.preview.image: 缺 CHECK U4.preview.image；U4/check:U4.preview.imageReleased: 缺 CHECK U4.preview.imageReleased  | `python example/tool/run_matrix.py --only touch-preview,s00e-offline-widgets` |
| U5 | BLOCKED | U5/check:U5.play: 缺 CHECK U5.play；U5/check:U5.pause: 缺 CHECK U5.pause；U5/check:U5.rates: 缺 CHECK U5.rates；U5/check:U5.volume: 缺 CHECK U5.volume；U5/check:U5.brightness: 缺 CHECK U5.brightness；U5/check:U5.seek: 缺 CHECK U5.seek；U5/check:U5.zoom: 缺 CHECK U5.zoom；U5/check:U5.fit.contract: 缺 CHECK U5.fit.contract；U5/check:U5.quality.contract: 缺 CHECK U5.quality.contract  | `python example/tool/run_matrix.py --only safe-visual,s00e-offline-widgets` |
| U6 | BLOCKED | U6/check:C3.left.false: 缺 CHECK C3.left.false；U6/check:C3.right.false: 缺 CHECK C3.right.false；U6/check:U6.tap.false: 缺 CHECK U6.tap.false；U6/check:U6.doubleRight.false: 缺 CHECK U6.doubleRight.false；U6/check:U6.doubleLeft.false: 缺 CHECK U6.doubleLeft.false；U6/check:U6.horizontal.false: 缺 CHECK U6.horizontal.false；U6/check:U6.pinch.false: 缺 CHECK U6.pinch.false；U6/check:U6.longPress.false: 缺 CHECK U6.longPress.false；U6/check:U6.region.false: 缺 CHECK U6.region.false；U6/check:C3.left.true: 缺 CHECK C3.left.true；U6/check:C3.right.true: 缺 CHECK C3.right.true；U6/check:U6.tap.true: 缺 CHECK U6.tap.true；U6/check:U6.doubleRight.true: 缺 CHECK U6.doubleRight.true；U6/check:U6.doubleLeft.true: 缺 CHECK U6.doubleLeft.true；U6/check:U6.horizontal.true: 缺 CHECK U6.horizontal.true；U6/check:U6.pinch.true: 缺 CHECK U6.pinch.true；U6/check:U6.longPress.true: 缺 CHECK U6.longPress.true；U6/check:U6.region.true: 缺 CHECK U6.region.true；U6/check:U6.map.none.false.false: 缺 CHECK U6.map.none.false.false；U6/check:U6.map.none.false.true: 缺 CHECK U6.map.none.false.true；U6/check:U6.map.none.true.false: 缺 CHECK U6.map.none.true.false；U6/check:U6.map.none.true.true: 缺 CHECK U6.map.none.true.true；U6/check:U6.map.volume.false.false: 缺 CHECK U6.map.volume.false.false；U6/check:U6.map.volume.false.true: 缺 CHECK U6.map.volume.false.true；U6/check:U6.map.volume.true.false: 缺 CHECK U6.map.volume.true.false；U6/check:U6.map.volume.true.true: 缺 CHECK U6.map.volume.true.true；U6/check:U6.map.brightness.false.false: 缺 CHECK U6.map.brightness.false.false；U6/check:U6.map.brightness.false.true: 缺 CHECK U6.map.brightness.false.true；U6/check:U6.map.brightness.true.false: 缺 CHECK U6.map.brightness.true.false；U6/check:U6.map.brightness.true.true: 缺 CHECK U6.map.brightness.true.true；U6/check:U6.map.seek.false.false: 缺 CHECK U6.map.seek.false.false；U6/check:U6.map.seek.false.true: 缺 CHECK U6.map.seek.false.true；U6/check:U6.map.seek.true.false: 缺 CHECK U6.map.seek.true.false；U6/check:U6.map.seek.true.true: 缺 CHECK U6.map.seek.true.true；U6/check:U6.douyin.tap: 缺 CHECK U6.douyin.tap；U6/check:U6.douyin.double: 缺 CHECK U6.douyin.double；U6/check:U6.douyin.drag: 缺 CHECK U6.douyin.drag；U6/check:A13.native.false: 缺 CHECK A13.native.false；U6/check:A13.native.true: 缺 CHECK A13.native.true；U6/check:U6.disabled.double.none.false.false: 缺 CHECK U6.disabled.double.none.false.false；U6/check:U6.disabled.pinch.none.false.false: 缺 CHECK U6.disabled.pinch.none.false.false；U6/check:U6.disabled.double.none.false.true: 缺 CHECK U6.disabled.double.none.false.true；U6/check:U6.disabled.pinch.none.false.true: 缺 CHECK U6.disabled.pinch.none.false.true；U6/check:U6.disabled.double.none.true.false: 缺 CHECK U6.disabled.double.none.true.false；U6/check:U6.disabled.pinch.none.true.false: 缺 CHECK U6.disabled.pinch.none.true.false；U6/check:U6.disabled.double.none.true.true: 缺 CHECK U6.disabled.double.none.true.true；U6/check:U6.disabled.pinch.none.true.true: 缺 CHECK U6.disabled.pinch.none.true.true；U6/check:U6.disabled.double.volume.false.false: 缺 CHECK U6.disabled.double.volume.false.false；U6/check:U6.disabled.pinch.volume.false.false: 缺 CHECK U6.disabled.pinch.volume.false.false；U6/check:U6.disabled.double.volume.false.true: 缺 CHECK U6.disabled.double.volume.false.true；U6/check:U6.disabled.pinch.volume.false.true: 缺 CHECK U6.disabled.pinch.volume.false.true；U6/check:U6.disabled.double.volume.true.false: 缺 CHECK U6.disabled.double.volume.true.false；U6/check:U6.disabled.pinch.volume.true.false: 缺 CHECK U6.disabled.pinch.volume.true.false；U6/check:U6.disabled.double.volume.true.true: 缺 CHECK U6.disabled.double.volume.true.true；U6/check:U6.disabled.pinch.volume.true.true: 缺 CHECK U6.disabled.pinch.volume.true.true；U6/check:U6.disabled.double.brightness.false.false: 缺 CHECK U6.disabled.double.brightness.false.false；U6/check:U6.disabled.pinch.brightness.false.false: 缺 CHECK U6.disabled.pinch.brightness.false.false；U6/check:U6.disabled.double.brightness.false.true: 缺 CHECK U6.disabled.double.brightness.false.true；U6/check:U6.disabled.pinch.brightness.false.true: 缺 CHECK U6.disabled.pinch.brightness.false.true；U6/check:U6.disabled.double.brightness.true.false: 缺 CHECK U6.disabled.double.brightness.true.false；U6/check:U6.disabled.pinch.brightness.true.false: 缺 CHECK U6.disabled.pinch.brightness.true.false；U6/check:U6.disabled.double.brightness.true.true: 缺 CHECK U6.disabled.double.brightness.true.true；U6/check:U6.disabled.pinch.brightness.true.true: 缺 CHECK U6.disabled.pinch.brightness.true.true；U6/check:U6.disabled.double.seek.false.false: 缺 CHECK U6.disabled.double.seek.false.false；U6/check:U6.disabled.pinch.seek.false.false: 缺 CHECK U6.disabled.pinch.seek.false.false；U6/check:U6.disabled.double.seek.false.true: 缺 CHECK U6.disabled.double.seek.false.true；U6/check:U6.disabled.pinch.seek.false.true: 缺 CHECK U6.disabled.pinch.seek.false.true；U6/check:U6.disabled.double.seek.true.false: 缺 CHECK U6.disabled.double.seek.true.false；U6/check:U6.disabled.pinch.seek.true.false: 缺 CHECK U6.disabled.pinch.seek.true.false；U6/check:U6.disabled.double.seek.true.true: 缺 CHECK U6.disabled.double.seek.true.true；U6/check:U6.disabled.pinch.seek.true.true: 缺 CHECK U6.disabled.pinch.seek.true.true；U6/check:U6.dvr.false: 缺 CHECK U6.dvr.false；U6/check:U6.dvr.true: 缺 CHECK U6.dvr.true  | `python example/tool/run_matrix.py --only gesture-pip,interactive,s00e-offline-widgets,s00e-native` |
| U7 | BLOCKED | U7/check:U7.like.render: 缺 CHECK U7.like.render；U7/check:U7.like.click: 缺 CHECK U7.like.click；U7/check:U7.comment.render: 缺 CHECK U7.comment.render；U7/check:U7.share.render: 缺 CHECK U7.share.render；U7/check:U7.social.clicks: 缺 CHECK U7.social.clicks；U7/check:U7.info: 缺 CHECK U7.info；U7/check:U7.subtitle.empty: 缺 CHECK U7.subtitle.empty；U7/check:U7.subtitle.cue: 缺 CHECK U7.subtitle.cue；U7/check:U7.subtitle.expired: 缺 CHECK U7.subtitle.expired；U7/check:U7.ad.countdown: 缺 CHECK U7.ad.countdown；U7/check:U7.ad.remaining: 缺 CHECK U7.ad.remaining；U7/check:U7.ad.click: 缺 CHECK U7.ad.click；U7/check:U7.ad.skippable: 缺 CHECK U7.ad.skippable；U7/check:U7.ad.skipped: 缺 CHECK U7.ad.skipped；U7/check:C8.now: 缺 CHECK C8.now；U7/check:U7.subtitle.start: 缺 CHECK U7.subtitle.start；U7/check:U7.subtitle.stop: 缺 CHECK U7.subtitle.stop  | `python example/tool/run_matrix.py --only safe-visual,s00e-offline-widgets` |
| U8 | BLOCKED | U8/check:U8.drag: 缺 CHECK U8.drag；U8/check:U8.snap: 缺 CHECK U8.snap；U8/check:U8.fling: 缺 CHECK U8.fling；U8/check:U8.resize: 缺 CHECK U8.resize；U8/check:A26.persistent: 缺 CHECK A26.persistent；U8/check:A26.tap: 缺 CHECK A26.tap；U8/check:A26.page: 缺 CHECK A26.page；U8/check:A26.setRect: 缺 CHECK A26.setRect；U8/check:A26.hide: 缺 CHECK A26.hide；U8/check:A26.close: 缺 CHECK A26.close  | `python example/tool/run_matrix.py --only widgets,interactive,touch-mini` |
| U9 | BLOCKED | U9/check:U9.ticker.none: 缺 CHECK U9.ticker.none；U9/check:U9.route.none: 缺 CHECK U9.route.none；U9/check:U9.inactive.none: 缺 CHECK U9.inactive.none；U9/check:U9.ticker.pip: 缺 CHECK U9.ticker.pip；U9/check:U9.route.pip: 缺 CHECK U9.route.pip；U9/check:U9.inactive.pip: 缺 CHECK U9.inactive.pip；U9/check:U9.ticker.mini: 缺 CHECK U9.ticker.mini；U9/check:U9.route.mini: 缺 CHECK U9.route.mini；U9/check:U9.inactive.mini: 缺 CHECK U9.inactive.mini；U9/check:U9.native.ticker: 缺 CHECK U9.native.ticker；U9/check:U9.native.route: 缺 CHECK U9.native.route；U9/check:U9.native.lifecycle.none: 缺 CHECK U9.native.lifecycle.none；U9/check:U9.native.lifecycle.pip: 缺 CHECK U9.native.lifecycle.pip；U9/check:U9.native.lifecycle.mini: 缺 CHECK U9.native.lifecycle.mini  | `python example/tool/run_matrix.py --only he-recovery,widgets,interactive,s00e-offline-widgets,s00e-native` |
| F1 | BLOCKED | F1/check:F1: 缺 CHECK F1；F1/record:LIFECYCLE: LIFECYCLE 样本=0/1 files=*; 缺事件记录  | `python example/tool/run_matrix.py --only api` |
| F2 | BLOCKED | F2/record:VIDEO: VIDEO 样本=0/3 files=rerun-live-*-behind.json; 缺事件记录；F2/record:VIDEO: VIDEO 样本=0/3 files=rerun-live-*-backedge.json; 缺事件记录；F2/duration:2: 缺 LIVE_DURATION step0/2000  | `python example/tool/run_matrix.py --only live-inputs` |
| F3 | BLOCKED | F3/check:F3.abrBackToBack: 缺 CHECK F3.abrBackToBack；F3/hls:1: 缺 HLS_RESULT；F3/check:CONTRACT.defaults: 缺 CHECK CONTRACT.defaults  | `python example/tool/run_matrix.py --only followups,hls-native,final-hls` |
| F4 | BLOCKED | F4/check:F4.adResume: 缺 CHECK F4.adResume；F4/check:A24.commit: 缺 CHECK A24.commit；F4/check:A27.rolls: 缺 CHECK A27.rolls；F4/check:CONTRACT.error.nonterminal: 缺 CHECK CONTRACT.error.nonterminal；F4/check:CONTRACT.error.terminal: 缺 CHECK CONTRACT.error.terminal；F4/check:CONTRACT.error.overlay.nonterminal: 缺 CHECK CONTRACT.error.overlay.nonterminal；F4/check:CONTRACT.error.overlay.terminal: 缺 CHECK CONTRACT.error.overlay.terminal  | `python example/tool/run_matrix.py --only api,existing-pages,s00e-offline-contract` |
| F5 | BLOCKED | F5/check:F5.pipWake: 缺 CHECK F5.pipWake；F5/check:A15.miniHostToPip: 缺 CHECK A15.miniHostToPip；F5/check:A15.pipExpanded: 缺 CHECK A15.pipExpanded  | `python example/tool/run_matrix.py --only s00c-native,gesture-pip` |
| F6 | BLOCKED | F6/keepalive_wake:0: keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联；F6/log:S2: keepalive-core.log: 缺完成标记；F6/log:S3: keepalive-core.log: 缺完成标记；F6/check:S6.publicFallback: 缺 CHECK S6.publicFallback；F6/log:S13: keepalive-core.log: 缺完成标记；F6/log:S17: keepalive-core.log: 缺完成标记  | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| F7 | BLOCKED | F7/check:F7.false.ended.endCount: 缺 CHECK F7.false.ended.endCount；F7/check:F7.false.ended.summary: 缺 CHECK F7.false.ended.summary；F7/check:F7.false.ended.truncated: 缺 CHECK F7.false.ended.truncated；F7/check:F7.false.ended.firstFrameCount: 缺 CHECK F7.false.ended.firstFrameCount；F7/check:F7.false.ended.firstFrame: 缺 CHECK F7.false.ended.firstFrame；F7/check:F7.false.stopped.endCount: 缺 CHECK F7.false.stopped.endCount；F7/check:F7.false.stopped.summary: 缺 CHECK F7.false.stopped.summary；F7/check:F7.false.stopped.truncated: 缺 CHECK F7.false.stopped.truncated；F7/check:F7.false.stopped.firstFrameCount: 缺 CHECK F7.false.stopped.firstFrameCount；F7/check:F7.false.stopped.firstFrame: 缺 CHECK F7.false.stopped.firstFrame；F7/check:F7.false.failed.endCount: 缺 CHECK F7.false.failed.endCount；F7/check:F7.false.failed.summary: 缺 CHECK F7.false.failed.summary；F7/check:F7.false.failed.truncated: 缺 CHECK F7.false.failed.truncated；F7/check:F7.false.failed.firstFrameCount: 缺 CHECK F7.false.failed.firstFrameCount；F7/check:F7.false.failed.firstFrame: 缺 CHECK F7.false.failed.firstFrame；F7/check:F7.false.abandoned.endCount: 缺 CHECK F7.false.abandoned.endCount；F7/check:F7.false.abandoned.summary: 缺 CHECK F7.false.abandoned.summary；F7/check:F7.false.abandoned.truncated: 缺 CHECK F7.false.abandoned.truncated；F7/check:F7.false.truncated.endCount: 缺 CHECK F7.false.truncated.endCount；F7/check:F7.false.truncated.summary: 缺 CHECK F7.false.truncated.summary；F7/check:F7.false.truncated.truncated: 缺 CHECK F7.false.truncated.truncated；F7/check:F7.false.truncated.firstFrameCount: 缺 CHECK F7.false.truncated.firstFrameCount；F7/check:F7.false.truncated.firstFrame: 缺 CHECK F7.false.truncated.firstFrame；F7/check:F7.false.disabled.endCount: 缺 CHECK F7.false.disabled.endCount；F7/check:F7.false.disabled.summary: 缺 CHECK F7.false.disabled.summary；F7/check:F7.false.disabled.truncated: 缺 CHECK F7.false.disabled.truncated；F7/check:F7.false.disabled.firstFrameCount: 缺 CHECK F7.false.disabled.firstFrameCount；F7/check:F7.false.disabled.firstFrame: 缺 CHECK F7.false.disabled.firstFrame；F7/check:F7.true.ended.endCount: 缺 CHECK F7.true.ended.endCount；F7/check:F7.true.ended.summary: 缺 CHECK F7.true.ended.summary；F7/check:F7.true.ended.truncated: 缺 CHECK F7.true.ended.truncated；F7/check:F7.true.ended.firstFrameCount: 缺 CHECK F7.true.ended.firstFrameCount；F7/check:F7.true.ended.firstFrame: 缺 CHECK F7.true.ended.firstFrame；F7/check:F7.true.stopped.endCount: 缺 CHECK F7.true.stopped.endCount；F7/check:F7.true.stopped.summary: 缺 CHECK F7.true.stopped.summary；F7/check:F7.true.stopped.truncated: 缺 CHECK F7.true.stopped.truncated；F7/check:F7.true.stopped.firstFrameCount: 缺 CHECK F7.true.stopped.firstFrameCount；F7/check:F7.true.stopped.firstFrame: 缺 CHECK F7.true.stopped.firstFrame；F7/check:F7.true.failed.endCount: 缺 CHECK F7.true.failed.endCount；F7/check:F7.true.failed.summary: 缺 CHECK F7.true.failed.summary；F7/check:F7.true.failed.truncated: 缺 CHECK F7.true.failed.truncated；F7/check:F7.true.failed.firstFrameCount: 缺 CHECK F7.true.failed.firstFrameCount；F7/check:F7.true.failed.firstFrame: 缺 CHECK F7.true.failed.firstFrame；F7/check:F7.true.abandoned.endCount: 缺 CHECK F7.true.abandoned.endCount；F7/check:F7.true.abandoned.summary: 缺 CHECK F7.true.abandoned.summary；F7/check:F7.true.abandoned.truncated: 缺 CHECK F7.true.abandoned.truncated；F7/check:F7.true.truncated.endCount: 缺 CHECK F7.true.truncated.endCount；F7/check:F7.true.truncated.summary: 缺 CHECK F7.true.truncated.summary；F7/check:F7.true.truncated.truncated: 缺 CHECK F7.true.truncated.truncated；F7/check:F7.true.truncated.firstFrameCount: 缺 CHECK F7.true.truncated.firstFrameCount；F7/check:F7.true.truncated.firstFrame: 缺 CHECK F7.true.truncated.firstFrame；F7/check:F7.true.disabled.endCount: 缺 CHECK F7.true.disabled.endCount；F7/check:F7.true.disabled.summary: 缺 CHECK F7.true.disabled.summary；F7/check:F7.true.disabled.truncated: 缺 CHECK F7.true.disabled.truncated；F7/check:F7.true.disabled.firstFrameCount: 缺 CHECK F7.true.disabled.firstFrameCount；F7/check:F7.true.disabled.firstFrame: 缺 CHECK F7.true.disabled.firstFrame；F7/check:F7.heartbeat: 缺 CHECK F7.heartbeat；F7/check:F7.nativeFirstFrame: 缺 CHECK F7.nativeFirstFrame；F7/check:F7.nativeSample: 缺 CHECK F7.nativeSample；F7/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-ended.json; 缺事件记录；F7/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-stopped.json; 缺事件记录；F7/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-failed.json; 缺事件记录；F7/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-abandoned.json; 缺事件记录；F7/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-truncated.json; 缺事件记录；F7/record:REPORT: REPORT 样本=0/1 files=*batch17-qoe-stall-release.json; 缺事件记录  | `python example/tool/run_matrix.py --only api,followups` |
| F8 | BLOCKED | F8/log:V5: he-recovery.log: 缺完成标记；F8/log:V6: he-recovery.log: 缺完成标记；F8/log:V7: he-recovery.log: 缺完成标记；F8/log:V8: he-recovery.log: 缺完成标记；F8/check:CONTRACT.replay.retry: 缺 CHECK CONTRACT.replay.retry；F8/check:CONTRACT.replay.edge: 缺 CHECK CONTRACT.replay.edge  | `python example/tool/run_matrix.py --only he-recovery,extras,he-v6-final,s00e-offline-contract` |
| F9 | BLOCKED | F9/check:F9.nativeAudio: 缺 CHECK F9.nativeAudio；F9/check:F9.native.ui: 缺 CHECK F9.native.ui；F9/check:F9.native.decoder: 缺 CHECK F9.native.decoder；F9/check:F9.native.comparison: 缺 CHECK F9.native.comparison  | `python example/tool/run_matrix.py --only api,widgets,s00e-native` |
| F10 | BLOCKED | F10/check:A30.mode.vtt: 缺 CHECK A30.mode.vtt；F10/check:A30.clear.vtt: 缺 CHECK A30.clear.vtt；F10/check:A30.mode.extract: 缺 CHECK A30.mode.extract；F10/check:A30.clear.extract: 缺 CHECK A30.clear.extract；F10/check:A30.mode.fallback: 缺 CHECK A30.mode.fallback；F10/check:A30.clear.fallback: 缺 CHECK A30.clear.fallback；F10/check:A30.mode.offline: 缺 CHECK A30.mode.offline；F10/check:A30.clear.offline: 缺 CHECK A30.clear.offline；F10/check:A30.mode.blocked: 缺 CHECK A30.mode.blocked；F10/check:A30.clear.blocked: 缺 CHECK A30.clear.blocked；F10/check:A30.cancelResult: 缺 CHECK A30.cancelResult；F10/check:A30.staleResult: 缺 CHECK A30.staleResult  | `python example/tool/run_matrix.py --only api,extras` |
| F11 | BLOCKED | F11/check:F11.ass: 缺 CHECK F11.ass；F11/check:F11.movtext: 缺 CHECK F11.movtext；F11/check:F11.srt: 缺 CHECK F11.srt；F11/check:F11.vtt: 缺 CHECK F11.vtt  | `python example/tool/run_matrix.py --only existing-pages,extras` |
| F12 | BLOCKED | F12/check:F12.audioCounters: 缺 CHECK F12.audioCounters；F12/check:F12.native.background: 缺 CHECK F12.native.background；F12/check:F12.power.external: 缺 CHECK F12.power.external  | `python example/tool/run_matrix.py --only existing-pages,s00e-native` |
| F13 | BLOCKED | F13/check:F13.resources.20: 缺 CHECK F13.resources.20；F13/check:F13.resources.40: 缺 CHECK F13.resources.40；F13/check:F13.resources.60: 缺 CHECK F13.resources.60；F13/check:F13.resources.80: 缺 CHECK F13.resources.80；F13/check:F13.resources.100: 缺 CHECK F13.resources.100；F13/check:F13.resources.disposed: 缺 CHECK F13.resources.disposed；F13/check:F13.disposeFrames: 缺 CHECK F13.disposeFrames；F13/check:A29.poolReclaimed: 缺 CHECK A29.poolReclaimed；F13/check:F13.bounded.40: 缺 CHECK F13.bounded.40；F13/check:F13.bounded.60: 缺 CHECK F13.bounded.60；F13/check:F13.bounded.80: 缺 CHECK F13.bounded.80；F13/check:F13.bounded.100: 缺 CHECK F13.bounded.100；F13/check:F13.bounded.disposed: 缺 CHECK F13.bounded.disposed；F13/check:F13.native.isolation: 缺 CHECK F13.native.isolation  | `python example/tool/run_matrix.py --only api,s00e-native` |
| F14 | BLOCKED | F14/check:F14.coverage1: 缺 CHECK F14.coverage1：原生泵创建/销毁/稳定性/错误隔离的结构化 CHECK；F14/check:F14.disposed.off: 缺 CHECK F14.disposed.off；F14/check:F14.disposed.recovery: 缺 CHECK F14.disposed.recovery；F14/check:F14.disposed.precise: 缺 CHECK F14.disposed.precise；F14/check:F14.disposed.reporterOff: 缺 CHECK F14.disposed.reporterOff；F14/check:F14.disposed.qoe: 缺 CHECK F14.disposed.qoe；F14/check:F14.native.teardown: 缺 CHECK F14.native.teardown  | `python example/tool/run_matrix.py --only existing-pages,s00e-native` |
| F15 | BLOCKED | 缺可控 WHEP 服务；端口可达不证明播放。  | `manual` |
| F16 | BLOCKED | F16/log:V12: rerun-batch11-review.log: 缺完成标记；F16/log:V12b: rerun-batch11-review.log: 缺完成标记；F16/log:V13a: rerun-batch11-review.log: 缺完成标记；F16/log:V13b: rerun-batch11-review.log: 缺完成标记；F16/log:V14: rerun-batch11-review.log: 缺完成标记  | `python example/tool/run_matrix.py --only existing-pages,gesture-pip` |
| N1 | BLOCKED | N1/check:N1.network: 缺 CHECK N1.network；N1/check:N4.whepOptions: 缺 CHECK N4.whepOptions  | `python example/tool/run_matrix.py --only api` |
| N2 | BLOCKED | N2/check:N2.derived: 缺 CHECK N2.derived；N2/check:N2.watchoff: 缺 CHECK N2.watchoff  | `python example/tool/run_matrix.py --only api` |
| N3 | BLOCKED | N3/check:N3.defaultLive: 缺 CHECK N3.defaultLive  | `python example/tool/run_matrix.py --only api` |
| N4 | BLOCKED | N4/check:N4.applied: 缺 CHECK N4.applied；N4/check:N4.restore: 缺 CHECK N4.restore；N4/check:N4.whepOptions: 缺 CHECK N4.whepOptions  | `python example/tool/run_matrix.py --only api` |
| N5 | BLOCKED | N5/check:N5.restart.off: 缺 CHECK N5.restart.off；N5/check:N5.restart.recovery: 缺 CHECK N5.restart.recovery；N5/check:N5.restart.precise: 缺 CHECK N5.restart.precise；N5/check:N5.restart.reporterOff: 缺 CHECK N5.restart.reporterOff；N5/check:N5.restart.qoe: 缺 CHECK N5.restart.qoe；N5/check:N5.endFile: 缺 CHECK N5.endFile  | `python example/tool/run_matrix.py --only api` |
| N6 | BLOCKED | N6/check:N6.clear: 缺 CHECK N6.clear；N6/check:N6.giveup: 缺 CHECK N6.giveup；N6/check:CONTRACT.error.terminal: 缺 CHECK CONTRACT.error.terminal  | `python example/tool/run_matrix.py --only api,extras,s00e-offline-contract` |
| N7 | BLOCKED | N7/duration:0: 缺 LIVE_DURATION step0/2000  | `python example/tool/run_matrix.py --only api` |
| N8 | BLOCKED | N8/check:N8.accept: 缺 CHECK N8.accept；N8/check:N8.reject: 缺 CHECK N8.reject；N8/check:N8.disposed: 缺 CHECK N8.disposed；N8/check:N8.playlistRejected: 缺 CHECK N8.playlistRejected；N8/check:N8.superseded: 缺 CHECK N8.superseded；N8/check:CONTRACT.rejectedOpen: 缺 CHECK CONTRACT.rejectedOpen  | `python example/tool/run_matrix.py --only api,extras,s00e-offline-contract` |
| N9 | BLOCKED | N9/check:A18.pinned.enter: 缺 CHECK A18.pinned.enter；N9/check:A18.pinned.expand: 缺 CHECK A18.pinned.expand；N9/check:A18.pinned.close: 缺 CHECK A18.pinned.close；N9/check:N9.transitions: 缺 CHECK N9.transitions  | `python example/tool/run_matrix.py --only s00c-native,gesture-pip` |
| N10 | BLOCKED | N10/log:V12: rerun-batch11-review.log: 缺完成标记；N10/log:V12b: rerun-batch11-review.log: 缺完成标记；N10/log:V13a: rerun-batch11-review.log: 缺完成标记；N10/log:V13b: rerun-batch11-review.log: 缺完成标记；N10/log:V14: rerun-batch11-review.log: 缺完成标记  | `python example/tool/run_matrix.py --only api,existing-pages` |
| N11 | BLOCKED | N11/log:Q13A: rerun-batch10-mute.log: 缺完成标记；N11/log:Q13B: rerun-batch10-mute.log: 缺完成标记；N11/log:Q13C: rerun-batch10-mute.log: 缺完成标记  | `python example/tool/run_matrix.py --only existing-pages` |
| N12 | BLOCKED | N12/log:V1: he-firstframe.log: 缺完成标记；N12/log:V2: he-firstframe.log: 缺完成标记；N12/log:V3: he-firstframe.log: 缺完成标记；N12/log:V4: he-firstframe.log: 缺完成标记；N12/check:N12.openReset: 缺 CHECK N12.openReset；N12/check:N12.freshRestart: 缺 CHECK N12.freshRestart；N12/check:N12.native.isolation: 缺 CHECK N12.native.isolation  | `python example/tool/run_matrix.py --only api,he-firstframe,native-inputs,s00e-native` |
| N13 | BLOCKED | N13/log:V1: he-firstframe.log: 缺完成标记；N13/log:V2: he-firstframe.log: 缺完成标记；N13/log:V3: he-firstframe.log: 缺完成标记；N13/log:V4: he-firstframe.log: 缺完成标记；N13/check:N13.clients.off: 缺 CHECK N13.clients.off；N13/check:N13.clients.recovery: 缺 CHECK N13.clients.recovery；N13/check:N13.clients.precise: 缺 CHECK N13.clients.precise；N13/check:N13.clients.reporterOff: 缺 CHECK N13.clients.reporterOff；N13/check:N13.clients.qoe: 缺 CHECK N13.clients.qoe；N13/check:N13.beforeOpen.off: 缺 CHECK N13.beforeOpen.off；N13/check:N13.beforeOpen.recovery: 缺 CHECK N13.beforeOpen.recovery；N13/check:N13.beforeOpen.precise: 缺 CHECK N13.beforeOpen.precise；N13/check:N13.beforeOpen.reporterOff: 缺 CHECK N13.beforeOpen.reporterOff；N13/check:N13.beforeOpen.qoe: 缺 CHECK N13.beforeOpen.qoe；N13/check:N13.video.false: 缺 CHECK N13.video.false；N13/check:N13.video.true: 缺 CHECK N13.video.true  | `python example/tool/run_matrix.py --only api,he-firstframe,existing-pages,s00e-native` |
| N14 | BLOCKED | N14/check:rerun-batch16-engine.fitRebuild: 缺 CHECK rerun-batch16-engine.fitRebuild；N14/check:rerun-batch16-cutover.fitRebuild: 缺 CHECK rerun-batch16-cutover.fitRebuild  | `python example/tool/run_matrix.py --only widgets` |
| N15 | BLOCKED | N15/check:N15.cover: 缺 CHECK N15.cover；N15/check:N15.fade: 缺 CHECK N15.fade；N15/check:N15.recover: 缺 CHECK N15.recover；N15/check:N15.noSize: 缺 CHECK N15.noSize；N15/check:N15.feedCover: 缺 CHECK N15.feedCover；N15/check:N15.feedFade: 缺 CHECK N15.feedFade；N15/check:N15.feedRecover: 缺 CHECK N15.feedRecover；N15/check:N15.renderFade: 缺 CHECK N15.renderFade；N15/check:N15.renderFadeDone: 缺 CHECK N15.renderFadeDone；N15/check:F7.nativeFirstFrame: 缺 CHECK F7.nativeFirstFrame  | `python example/tool/run_matrix.py --only safe-visual,safe-transition` |
| N16 | BLOCKED | N16/check:N16.variants.false.false: 缺 CHECK N16.variants.false.false；N16/check:N16.variants.false.true: 缺 CHECK N16.variants.false.true；N16/check:N16.variants.true.false: 缺 CHECK N16.variants.true.false；N16/check:N16.variants.true.true: 缺 CHECK N16.variants.true.true；N16/check:C10.buffering: 缺 CHECK C10.buffering；N16/check:U2.mounted.minimal: 缺 CHECK U2.mounted.minimal  | `python example/tool/run_matrix.py --only widgets,safe-visual,gap-skin` |
| N17 | BLOCKED | N17/check:N17.lazy: 缺 CHECK N17.lazy；N17/check:N17.owned: 缺 CHECK N17.owned；N17/check:N17.same: 缺 CHECK N17.same；N17/check:N17.alternatives: 缺 CHECK N17.alternatives；N17/check:N17.null: 缺 CHECK N17.null；N17/check:N17.options: 缺 CHECK N17.options；N17/check:N17.error: 缺 CHECK N17.error；N17/check:N17.dispose: 缺 CHECK N17.dispose  | `python example/tool/run_matrix.py --only widgets` |
| N18 | BLOCKED | 完整 mini/guard-off 联动需专用包和复核，主包不足。  | `manual` |
| N19 | BLOCKED | N19/check:N19.failover: 缺 CHECK N19.failover；N19/check:N6.clear: 缺 CHECK N6.clear；N19/check:N6.giveup: 缺 CHECK N6.giveup；N19/log:V5: he-recovery.log: 缺完成标记；N19/log:V6: he-recovery.log: 缺完成标记；N19/log:V7: he-recovery.log: 缺完成标记；N19/log:V8: he-recovery.log: 缺完成标记；N19/check:CONTRACT.replay.retry: 缺 CHECK CONTRACT.replay.retry  | `python example/tool/run_matrix.py --only api,he-recovery,extras,he-v6-final,s00e-offline-contract` |
| N20 | BLOCKED | N20/keepalive_wake:0: keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联；N20/log:S2: keepalive-core.log: 缺完成标记；N20/log:S3: keepalive-core.log: 缺完成标记；N20/check:S6.publicFallback: 缺 CHECK S6.publicFallback；N20/log:S13: keepalive-core.log: 缺完成标记；N20/log:S17: keepalive-core.log: 缺完成标记  | `python example/tool/run_matrix.py --only keepalive-core,existing-pages` |
| N21 | BLOCKED | N21/check:N21.staged: 缺 CHECK N21.staged；N21/check:N21.guard.windows: 缺 CHECK N21.guard.windows；N21/check:N21.guard.android: 缺 CHECK N21.guard.android  | `python example/tool/run_matrix.py --only api,widgets` |
| N22 | BLOCKED | 需专用 debug VM 构建及断言 marker；不能复用旧 APK。  | `manual` |
| N23 | BLOCKED | N23/check:F7.false.ended.endCount: 缺 CHECK F7.false.ended.endCount；N23/check:F7.false.ended.summary: 缺 CHECK F7.false.ended.summary；N23/check:F7.false.ended.truncated: 缺 CHECK F7.false.ended.truncated；N23/check:F7.false.ended.firstFrameCount: 缺 CHECK F7.false.ended.firstFrameCount；N23/check:F7.false.ended.firstFrame: 缺 CHECK F7.false.ended.firstFrame；N23/check:F7.false.stopped.endCount: 缺 CHECK F7.false.stopped.endCount；N23/check:F7.false.stopped.summary: 缺 CHECK F7.false.stopped.summary；N23/check:F7.false.stopped.truncated: 缺 CHECK F7.false.stopped.truncated；N23/check:F7.false.stopped.firstFrameCount: 缺 CHECK F7.false.stopped.firstFrameCount；N23/check:F7.false.stopped.firstFrame: 缺 CHECK F7.false.stopped.firstFrame；N23/check:F7.false.failed.endCount: 缺 CHECK F7.false.failed.endCount；N23/check:F7.false.failed.summary: 缺 CHECK F7.false.failed.summary；N23/check:F7.false.failed.truncated: 缺 CHECK F7.false.failed.truncated；N23/check:F7.false.failed.firstFrameCount: 缺 CHECK F7.false.failed.firstFrameCount；N23/check:F7.false.failed.firstFrame: 缺 CHECK F7.false.failed.firstFrame；N23/check:F7.false.abandoned.endCount: 缺 CHECK F7.false.abandoned.endCount；N23/check:F7.false.abandoned.summary: 缺 CHECK F7.false.abandoned.summary；N23/check:F7.false.abandoned.truncated: 缺 CHECK F7.false.abandoned.truncated；N23/check:F7.false.truncated.endCount: 缺 CHECK F7.false.truncated.endCount；N23/check:F7.false.truncated.summary: 缺 CHECK F7.false.truncated.summary；N23/check:F7.false.truncated.truncated: 缺 CHECK F7.false.truncated.truncated；N23/check:F7.false.truncated.firstFrameCount: 缺 CHECK F7.false.truncated.firstFrameCount；N23/check:F7.false.truncated.firstFrame: 缺 CHECK F7.false.truncated.firstFrame；N23/check:F7.false.disabled.endCount: 缺 CHECK F7.false.disabled.endCount；N23/check:F7.false.disabled.summary: 缺 CHECK F7.false.disabled.summary；N23/check:F7.false.disabled.truncated: 缺 CHECK F7.false.disabled.truncated；N23/check:F7.false.disabled.firstFrameCount: 缺 CHECK F7.false.disabled.firstFrameCount；N23/check:F7.false.disabled.firstFrame: 缺 CHECK F7.false.disabled.firstFrame；N23/check:F7.true.ended.endCount: 缺 CHECK F7.true.ended.endCount；N23/check:F7.true.ended.summary: 缺 CHECK F7.true.ended.summary；N23/check:F7.true.ended.truncated: 缺 CHECK F7.true.ended.truncated；N23/check:F7.true.ended.firstFrameCount: 缺 CHECK F7.true.ended.firstFrameCount；N23/check:F7.true.ended.firstFrame: 缺 CHECK F7.true.ended.firstFrame；N23/check:F7.true.stopped.endCount: 缺 CHECK F7.true.stopped.endCount；N23/check:F7.true.stopped.summary: 缺 CHECK F7.true.stopped.summary；N23/check:F7.true.stopped.truncated: 缺 CHECK F7.true.stopped.truncated；N23/check:F7.true.stopped.firstFrameCount: 缺 CHECK F7.true.stopped.firstFrameCount；N23/check:F7.true.stopped.firstFrame: 缺 CHECK F7.true.stopped.firstFrame；N23/check:F7.true.failed.endCount: 缺 CHECK F7.true.failed.endCount；N23/check:F7.true.failed.summary: 缺 CHECK F7.true.failed.summary；N23/check:F7.true.failed.truncated: 缺 CHECK F7.true.failed.truncated；N23/check:F7.true.failed.firstFrameCount: 缺 CHECK F7.true.failed.firstFrameCount；N23/check:F7.true.failed.firstFrame: 缺 CHECK F7.true.failed.firstFrame；N23/check:F7.true.abandoned.endCount: 缺 CHECK F7.true.abandoned.endCount；N23/check:F7.true.abandoned.summary: 缺 CHECK F7.true.abandoned.summary；N23/check:F7.true.abandoned.truncated: 缺 CHECK F7.true.abandoned.truncated；N23/check:F7.true.truncated.endCount: 缺 CHECK F7.true.truncated.endCount；N23/check:F7.true.truncated.summary: 缺 CHECK F7.true.truncated.summary；N23/check:F7.true.truncated.truncated: 缺 CHECK F7.true.truncated.truncated；N23/check:F7.true.truncated.firstFrameCount: 缺 CHECK F7.true.truncated.firstFrameCount；N23/check:F7.true.truncated.firstFrame: 缺 CHECK F7.true.truncated.firstFrame；N23/check:F7.true.disabled.endCount: 缺 CHECK F7.true.disabled.endCount；N23/check:F7.true.disabled.summary: 缺 CHECK F7.true.disabled.summary；N23/check:F7.true.disabled.truncated: 缺 CHECK F7.true.disabled.truncated；N23/check:F7.true.disabled.firstFrameCount: 缺 CHECK F7.true.disabled.firstFrameCount；N23/check:F7.true.disabled.firstFrame: 缺 CHECK F7.true.disabled.firstFrame；N23/check:F7.heartbeat: 缺 CHECK F7.heartbeat；N23/check:F7.nativeFirstFrame: 缺 CHECK F7.nativeFirstFrame；N23/check:F7.nativeSample: 缺 CHECK F7.nativeSample；N23/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-ended.json; 缺事件记录；N23/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-stopped.json; 缺事件记录；N23/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-failed.json; 缺事件记录；N23/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-abandoned.json; 缺事件记录；N23/record:REPORT: REPORT 样本=0/1 files=*batch15-qoe-truncated.json; 缺事件记录；N23/record:REPORT: REPORT 样本=0/1 files=*batch17-qoe-stall-release.json; 缺事件记录；N23/check:N23.policy.stream.false: 缺 CHECK N23.policy.stream.false；N23/check:N23.policy.stream.true: 缺 CHECK N23.policy.stream.true；N23/check:N23.policy.file.false: 缺 CHECK N23.policy.file.false；N23/check:N23.policy.file.true: 缺 CHECK N23.policy.file.true；N23/check:N23.policy.ffmpeg.false: 缺 CHECK N23.policy.ffmpeg.false；N23/check:N23.policy.ffmpeg.true: 缺 CHECK N23.policy.ffmpeg.true；N23/check:N23.policy.vd.false: 缺 CHECK N23.policy.vd.false；N23/check:N23.policy.vd.true: 缺 CHECK N23.policy.vd.true；N23/check:N23.policy.ad.false: 缺 CHECK N23.policy.ad.false；N23/check:N23.policy.ad.true: 缺 CHECK N23.policy.ad.true；N23/check:N23.policy.cplayer.false: 缺 CHECK N23.policy.cplayer.false；N23/check:N23.policy.cplayer.true: 缺 CHECK N23.policy.cplayer.true；N23/check:N23.policy.other.false: 缺 CHECK N23.policy.other.false；N23/check:N23.policy.other.true: 缺 CHECK N23.policy.other.true；N23/check:N23.custom: 缺 CHECK N23.custom；N23/check:N23.error.stream.false: 缺 CHECK N23.error.stream.false；N23/check:N23.error.stream.true: 缺 CHECK N23.error.stream.true；N23/check:N23.error.file.false: 缺 CHECK N23.error.file.false；N23/check:N23.error.file.true: 缺 CHECK N23.error.file.true；N23/check:N23.error.ffmpeg.false: 缺 CHECK N23.error.ffmpeg.false；N23/check:N23.error.ffmpeg.true: 缺 CHECK N23.error.ffmpeg.true；N23/check:N23.error.vd.false: 缺 CHECK N23.error.vd.false；N23/check:N23.error.vd.true: 缺 CHECK N23.error.vd.true；N23/check:N23.error.ad.false: 缺 CHECK N23.error.ad.false；N23/check:N23.error.ad.true: 缺 CHECK N23.error.ad.true；N23/check:N23.error.cplayer.false: 缺 CHECK N23.error.cplayer.false；N23/check:N23.error.cplayer.true: 缺 CHECK N23.error.cplayer.true；N23/check:N23.error.other.false: 缺 CHECK N23.error.other.false；N23/check:N23.error.other.true: 缺 CHECK N23.error.other.true；N23/check:CONTRACT.error.nonterminal: 缺 CHECK CONTRACT.error.nonterminal  | `python example/tool/run_matrix.py --only api,followups,s00e-offline-contract` |

| 子项 | 结论 | 原始证据 |
|---|---|---|
| A1/check:A1.closed | BLOCKED | 缺 CHECK A1.closed |
| A1/check:A1.progress | BLOCKED | 缺 CHECK A1.progress |
| A1/check:A1.events.sequence | BLOCKED | 缺 CHECK A1.events.sequence |
| A1/check:A1.states.sequence | BLOCKED | 缺 CHECK A1.states.sequence |
| A1/check:A1.progress.sequence | BLOCKED | 缺 CHECK A1.progress.sequence |
| A1/check:A1.uiStates.sequence | BLOCKED | 缺 CHECK A1.uiStates.sequence |
| A2/event:MovaBufferChange | BLOCKED | 缺 EVENT MovaBufferChange |
| A2/event:MovaSizeChange | BLOCKED | 缺 EVENT MovaSizeChange |
| A2/event:MovaQualityChange | BLOCKED | 缺 EVENT MovaQualityChange |
| A2/event:MovaRateChange | BLOCKED | 缺 EVENT MovaRateChange |
| A2/event:MovaVolumeChange | BLOCKED | 缺 EVENT MovaVolumeChange |
| A2/event:MovaBrightChange | BLOCKED | 缺 EVENT MovaBrightChange |
| A2/check:A2.engine.receipt | BLOCKED | 缺 CHECK A2.engine.receipt |
| A2/check:A2.cutover.receipt | BLOCKED | 缺 CHECK A2.cutover.receipt |
| A3/check:A3.audio | BLOCKED | 缺 CHECK A3.audio |
| A3/check:A3.lazyBefore | BLOCKED | 缺 CHECK A3.lazyBefore |
| A3/check:A3.lazyOpened | BLOCKED | 缺 CHECK A3.lazyOpened |
| A3/check:A3.lazyRead | BLOCKED | 缺 CHECK A3.lazyRead |
| A4/check:A4 | BLOCKED | 缺 CHECK A4 |
| A5/check:A5.paused | BLOCKED | 缺 CHECK A5.paused |
| A5/check:N8.accept | BLOCKED | 缺 CHECK N8.accept |
| A5/check:N8.reject | BLOCKED | 缺 CHECK N8.reject |
| A5/check:N8.superseded | BLOCKED | 缺 CHECK N8.superseded |
| A5/check:A5.openThrows | BLOCKED | 缺 CHECK A5.openThrows |
| A5/check:CONTRACT.rejectedOpen | BLOCKED | 缺 CHECK CONTRACT.rejectedOpen |
| A6/check:A6.pause | BLOCKED | 缺 CHECK A6.pause |
| A6/check:A6.togglePlay | BLOCKED | 缺 CHECK A6.togglePlay |
| A6/check:A6.togglePause | BLOCKED | 缺 CHECK A6.togglePause |
| A6/check:A6.repeatPlay | BLOCKED | 缺 CHECK A6.repeatPlay |
| A6/check:A6.repeatPause | BLOCKED | 缺 CHECK A6.repeatPause |
| A6/check:A6.intentIndependent | BLOCKED | 缺 CHECK A6.intentIndependent |
| A6/check:A6.branchPlay | BLOCKED | 缺 CHECK A6.branchPlay |
| A6/check:A6.branchPause | BLOCKED | 缺 CHECK A6.branchPause |
| A6/check:CONTRACT.rejectedOpen | BLOCKED | 缺 CHECK CONTRACT.rejectedOpen |
| A7/check:A7.seek | BLOCKED | 缺 CHECK A7.seek |
| A7/check:A7.negative | BLOCKED | 缺 CHECK A7.negative |
| A7/check:A7.live | BLOCKED | 缺 CHECK A7.live |
| A7/record:SEEK_LOADING | BLOCKED | SEEK_LOADING 样本=0/1 files=*; 缺事件记录 |
| A7/record:SEEK_BY | BLOCKED | SEEK_BY 样本=0/1 files=*; 缺事件记录 |
| A7/record:SEEK_BEYOND | BLOCKED | SEEK_BEYOND 样本=0/1 files=*; 缺事件记录 |
| A7/check:A7.retry.0 | BLOCKED | 缺 CHECK A7.retry.0 |
| A7/check:A7.retry.1 | BLOCKED | 缺 CHECK A7.retry.1 |
| A7/check:A7.retry.2 | BLOCKED | 缺 CHECK A7.retry.2 |
| A7/check:A7.retry.100 | BLOCKED | 缺 CHECK A7.retry.100 |
| A7/check:A7.native.trace | BLOCKED | 缺 CHECK A7.native.trace |
| A7/check:CONTRACT.rejectedOpen | BLOCKED | 缺 CHECK CONTRACT.rejectedOpen |
| A8/check:A8.clamp | BLOCKED | 缺 CHECK A8.clamp |
| A8/volume:1 | BLOCKED | 缺 rerun-native-engine-volume-10.native.txt; 缺 rerun-native-engine-volume0.native.txt; 缺 rerun-native-engine-volume1.native.txt; 缺 rerun-native-engine-volume30.native.txt; 缺 rerun-native-engine-volume50.native.txt; 缺 rerun-native-engine-volume100.native.txt; 缺 rerun-native-engine-volume110.native.txt; 缺 rerun-native-cutover-volume-10.native.txt; 缺 rerun-native-cutover-volume0.native.txt; 缺 rerun-native-cutover-volume1.native.txt; 缺 rerun-native-cutover-volume30.native.txt; 缺 rerun-native-cutover-volume50.native.txt; 缺 rerun-native-cutover-volume100.native.txt; 缺 rerun-native-cutover-volume110.native.txt |
| A9/check:A9.clamp | BLOCKED | 缺 CHECK A9.clamp |
| A9/record:BRIGHTNESS_NATIVE | BLOCKED | BRIGHTNESS_NATIVE 样本=0/6 files=*; 缺事件记录 |
| A10/check:A10.persist | BLOCKED | 缺 CHECK A10.persist |
| A10/rate_sequence:1 | BLOCKED | rerun-batch15-basic.json: requested=[], clamped=[], EVENT values=[], matched=0; rerun-batch15-basic-cutover.json: requested=[], clamped=[], EVENT values=[], matched=0 |
| A11/check:rerun-batch16-engine.fit.contain | BLOCKED | 缺 CHECK rerun-batch16-engine.fit.contain |
| A11/check:rerun-batch16-cutover.fit.contain | BLOCKED | 缺 CHECK rerun-batch16-cutover.fit.contain |
| A11/check:rerun-batch16-engine.fit.cover | BLOCKED | 缺 CHECK rerun-batch16-engine.fit.cover |
| A11/check:rerun-batch16-cutover.fit.cover | BLOCKED | 缺 CHECK rerun-batch16-cutover.fit.cover |
| A11/check:rerun-batch16-engine.fit.fill | BLOCKED | 缺 CHECK rerun-batch16-engine.fit.fill |
| A11/check:rerun-batch16-cutover.fit.fill | BLOCKED | 缺 CHECK rerun-batch16-cutover.fit.fill |
| A11/check:A11.declared | BLOCKED | 缺 CHECK A11.declared |
| A11/check:A11.once | BLOCKED | 缺 CHECK A11.once |
| A11/check:A11.render.contain | BLOCKED | 缺 CHECK A11.render.contain |
| A11/check:A11.render.cover | BLOCKED | 缺 CHECK A11.render.cover |
| A11/check:A11.render.fill | BLOCKED | 缺 CHECK A11.render.fill |
| A12/record:VIDEO | BLOCKED | VIDEO 样本=0/1 files=rerun-batch3-05-zoom--1.json; 缺事件记录 |
| A12/record:VIDEO | BLOCKED | VIDEO 样本=0/1 files=rerun-batch3-06-zoom-0.json; 缺事件记录 |
| A12/record:VIDEO | BLOCKED | VIDEO 样本=0/1 files=rerun-batch3-07-zoom-1.json; 缺事件记录 |
| A12/record:VIDEO | BLOCKED | VIDEO 样本=0/1 files=rerun-batch3-08-zoom-2.json; 缺事件记录 |
| A12/record:VIDEO | BLOCKED | VIDEO 样本=0/1 files=rerun-batch3-09-zoom-100.json; 缺事件记录 |
| A13/check:rerun-batch16-engine.lock | BLOCKED | 缺 CHECK rerun-batch16-engine.lock |
| A13/check:rerun-batch16-cutover.lock | BLOCKED | 缺 CHECK rerun-batch16-cutover.lock |
| A13/check:A13.unlock.false | BLOCKED | 缺 CHECK A13.unlock.false |
| A13/check:A13.unlock.true | BLOCKED | 缺 CHECK A13.unlock.true |
| A13/check:A13.lock.false | BLOCKED | 缺 CHECK A13.lock.false |
| A13/check:A13.lock.true | BLOCKED | 缺 CHECK A13.lock.true |
| A13/check:A13.native.false | BLOCKED | 缺 CHECK A13.native.false |
| A13/check:A13.native.true | BLOCKED | 缺 CHECK A13.native.true |
| A14/check:rerun-batch16-engine.fullscreen.true | BLOCKED | 缺 CHECK rerun-batch16-engine.fullscreen.true |
| A14/check:rerun-batch16-cutover.fullscreen.true | BLOCKED | 缺 CHECK rerun-batch16-cutover.fullscreen.true |
| A14/check:rerun-batch16-engine.fullscreen.false | BLOCKED | 缺 CHECK rerun-batch16-engine.fullscreen.false |
| A14/check:rerun-batch16-cutover.fullscreen.false | BLOCKED | 缺 CHECK rerun-batch16-cutover.fullscreen.false |
| A14/check:A14.window.enter | BLOCKED | 缺 CHECK A14.window.enter |
| A14/check:A14.window.restore | BLOCKED | 缺 CHECK A14.window.restore |
| A15/check:A15.miniStable | BLOCKED | 缺 CHECK A15.miniStable |
| A15/check:A15.exit | BLOCKED | 缺 CHECK A15.exit |
| A15/check:A15.miniHostToPip | BLOCKED | 缺 CHECK A15.miniHostToPip |
| A15/check:A15.pipExpanded | BLOCKED | 缺 CHECK A15.pipExpanded |
| A16/check:A16.window.landscape | BLOCKED | 缺 CHECK A16.window.landscape |
| A16/check:A16.window.portrait | BLOCKED | 缺 CHECK A16.window.portrait |
| A16/check:A16.window.auto | BLOCKED | 缺 CHECK A16.window.auto |
| A17/hls:0 | BLOCKED | 缺 HLS_RESULT |
| A17/check:CONTRACT.defaults | BLOCKED | 缺 CHECK CONTRACT.defaults |
| A17/check:CONTRACT.probe.true | BLOCKED | 缺 CHECK CONTRACT.probe.true |
| A17/check:CONTRACT.probe.false | BLOCKED | 缺 CHECK CONTRACT.probe.false |
| A17/check:CONTRACT.replay.retry | BLOCKED | 缺 CHECK CONTRACT.replay.retry |
| A17/check:CONTRACT.probe.uiOff | BLOCKED | 缺 CHECK CONTRACT.probe.uiOff |
| A18/check:A18.pinned.enter | BLOCKED | 缺 CHECK A18.pinned.enter |
| A18/check:A18.pinned.expand | BLOCKED | 缺 CHECK A18.pinned.expand |
| A18/check:A18.pinned.close | BLOCKED | 缺 CHECK A18.pinned.close |
| A18/check:N9.transitions | BLOCKED | 缺 CHECK N9.transitions |
| A19/record:RELOAD | BLOCKED | RELOAD 样本=0/2 files=*; 缺事件记录 |
| A20/record:VIDEO | BLOCKED | VIDEO 样本=0/3 files=rerun-live-*-behind.json; 缺事件记录 |
| A20/record:VIDEO | BLOCKED | VIDEO 样本=0/3 files=rerun-live-*-backedge.json; 缺事件记录 |
| A20/check:CONTRACT.replay.edge | BLOCKED | 缺 CHECK CONTRACT.replay.edge |
| A21/check:A21.hide | BLOCKED | 缺 CHECK A21.hide |
| A21/check:A21.hud | BLOCKED | 缺 CHECK A21.hud |
| A21/check:A21.sticky | BLOCKED | 缺 CHECK A21.sticky |
| A21/check:A21.autoHide | BLOCKED | 缺 CHECK A21.autoHide |
| A21/check:A21.dragging | BLOCKED | 缺 CHECK A21.dragging |
| A21/check:A21.hudCleared | BLOCKED | 缺 CHECK A21.hudCleared |
| A22/check:A22 | BLOCKED | 缺 CHECK A22 |
| A23/check:A23.doubleDispose | BLOCKED | 缺 CHECK A23.doubleDispose |
| A23/check:A23.postOpen | BLOCKED | 缺 CHECK A23.postOpen |
| A23/check:A23.120 | BLOCKED | 缺 CHECK A23.120 |
| A24/check:A24.abandon | BLOCKED | 缺 CHECK A24.abandon |
| A24/check:A24.commit | BLOCKED | 缺 CHECK A24.commit |
| A24/check:A24.cutoverTo | BLOCKED | 缺 CHECK A24.cutoverTo |
| A24/check:A24.retired | BLOCKED | 缺 CHECK A24.retired |
| A24/check:A24.short | BLOCKED | 缺 CHECK A24.short |
| A24/check:A24.timeout | BLOCKED | 缺 CHECK A24.timeout |
| A25/check:A25.pause | BLOCKED | 缺 CHECK A25.pause |
| A25/keepalive_wake:1 | BLOCKED | keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联 |
| A25/log:S2 | BLOCKED | keepalive-core.log: 缺完成标记 |
| A25/log:S3 | BLOCKED | keepalive-core.log: 缺完成标记 |
| A25/check:S6.publicFallback | BLOCKED | 缺 CHECK S6.publicFallback |
| A25/log:S13 | BLOCKED | keepalive-core.log: 缺完成标记 |
| A25/log:S17 | BLOCKED | keepalive-core.log: 缺完成标记 |
| A26/check:A26.persistent | BLOCKED | 缺 CHECK A26.persistent |
| A26/check:A26.tap | BLOCKED | 缺 CHECK A26.tap |
| A26/check:A26.page | BLOCKED | 缺 CHECK A26.page |
| A26/check:A26.setRect | BLOCKED | 缺 CHECK A26.setRect |
| A26/check:A26.hide | BLOCKED | 缺 CHECK A26.hide |
| A26/check:A26.close | BLOCKED | 缺 CHECK A26.close |
| A26/check:U8.drag | BLOCKED | 缺 CHECK U8.drag |
| A26/check:U8.snap | BLOCKED | 缺 CHECK U8.snap |
| A26/check:U8.fling | BLOCKED | 缺 CHECK U8.fling |
| A26/check:U8.resize | BLOCKED | 缺 CHECK U8.resize |
| A27/check:A27.rolls | BLOCKED | 缺 CHECK A27.rolls |
| A27/check:C9.waits | BLOCKED | 缺 CHECK C9.waits |
| A28/check:A28.start | BLOCKED | 缺 CHECK A28.start |
| A28/check:A28.end | BLOCKED | 缺 CHECK A28.end |
| A28/check:A28.auto | BLOCKED | 缺 CHECK A28.auto |
| A29/check:A29.dispose | BLOCKED | 缺 CHECK A29.dispose |
| A29/check:A29.final | BLOCKED | 缺 CHECK A29.final |
| A29/check:A29.rangeWarm | BLOCKED | 缺 CHECK A29.rangeWarm |
| A29/check:A29.poolReclaimed | BLOCKED | 缺 CHECK A29.poolReclaimed |
| A30/check:A30.diskHit | BLOCKED | 缺 CHECK A30.diskHit |
| A30/check:A30.mode.vtt | BLOCKED | 缺 CHECK A30.mode.vtt |
| A30/check:A30.clear.vtt | BLOCKED | 缺 CHECK A30.clear.vtt |
| A30/check:A30.mode.extract | BLOCKED | 缺 CHECK A30.mode.extract |
| A30/check:A30.clear.extract | BLOCKED | 缺 CHECK A30.clear.extract |
| A30/check:A30.mode.fallback | BLOCKED | 缺 CHECK A30.mode.fallback |
| A30/check:A30.clear.fallback | BLOCKED | 缺 CHECK A30.clear.fallback |
| A30/check:A30.mode.offline | BLOCKED | 缺 CHECK A30.mode.offline |
| A30/check:A30.clear.offline | BLOCKED | 缺 CHECK A30.clear.offline |
| A30/check:A30.mode.blocked | BLOCKED | 缺 CHECK A30.mode.blocked |
| A30/check:A30.clear.blocked | BLOCKED | 缺 CHECK A30.clear.blocked |
| A30/check:A30.cancelResult | BLOCKED | 缺 CHECK A30.cancelResult |
| A30/check:A30.staleResult | BLOCKED | 缺 CHECK A30.staleResult |
| A32/check:A32.seekVeto | BLOCKED | 缺 CHECK A32.seekVeto |
| A32/check:A32.afterThrow | BLOCKED | 缺 CHECK A32.afterThrow |
| A32/check:A32.onErrorIsolation | BLOCKED | 缺 CHECK A32.onErrorIsolation |
| A32/check:N8.reject | BLOCKED | 缺 CHECK N8.reject |
| A32/check:N8.superseded | BLOCKED | 缺 CHECK N8.superseded |
| A32/check:CONTRACT.rejectedOpen | BLOCKED | 缺 CHECK CONTRACT.rejectedOpen |
| A33/check:A33 | BLOCKED | 缺 CHECK A33 |
| C1/check:A30.mode.vtt | BLOCKED | 缺 CHECK A30.mode.vtt |
| C1/check:A30.clear.vtt | BLOCKED | 缺 CHECK A30.clear.vtt |
| C1/check:A30.mode.extract | BLOCKED | 缺 CHECK A30.mode.extract |
| C1/check:A30.clear.extract | BLOCKED | 缺 CHECK A30.clear.extract |
| C1/check:A30.mode.fallback | BLOCKED | 缺 CHECK A30.mode.fallback |
| C1/check:A30.clear.fallback | BLOCKED | 缺 CHECK A30.clear.fallback |
| C1/check:A30.mode.offline | BLOCKED | 缺 CHECK A30.mode.offline |
| C1/check:A30.clear.offline | BLOCKED | 缺 CHECK A30.clear.offline |
| C1/check:A30.mode.blocked | BLOCKED | 缺 CHECK A30.mode.blocked |
| C1/check:A30.clear.blocked | BLOCKED | 缺 CHECK A30.clear.blocked |
| C1/check:A30.cancelResult | BLOCKED | 缺 CHECK A30.cancelResult |
| C1/check:A30.staleResult | BLOCKED | 缺 CHECK A30.staleResult |
| C3/check:C3.left.false | BLOCKED | 缺 CHECK C3.left.false |
| C3/check:C3.right.false | BLOCKED | 缺 CHECK C3.right.false |
| C3/check:U6.tap.false | BLOCKED | 缺 CHECK U6.tap.false |
| C3/check:U6.doubleRight.false | BLOCKED | 缺 CHECK U6.doubleRight.false |
| C3/check:U6.doubleLeft.false | BLOCKED | 缺 CHECK U6.doubleLeft.false |
| C3/check:U6.horizontal.false | BLOCKED | 缺 CHECK U6.horizontal.false |
| C3/check:U6.pinch.false | BLOCKED | 缺 CHECK U6.pinch.false |
| C3/check:U6.longPress.false | BLOCKED | 缺 CHECK U6.longPress.false |
| C3/check:U6.region.false | BLOCKED | 缺 CHECK U6.region.false |
| C3/check:C3.left.true | BLOCKED | 缺 CHECK C3.left.true |
| C3/check:C3.right.true | BLOCKED | 缺 CHECK C3.right.true |
| C3/check:U6.tap.true | BLOCKED | 缺 CHECK U6.tap.true |
| C3/check:U6.doubleRight.true | BLOCKED | 缺 CHECK U6.doubleRight.true |
| C3/check:U6.doubleLeft.true | BLOCKED | 缺 CHECK U6.doubleLeft.true |
| C3/check:U6.horizontal.true | BLOCKED | 缺 CHECK U6.horizontal.true |
| C3/check:U6.pinch.true | BLOCKED | 缺 CHECK U6.pinch.true |
| C3/check:U6.longPress.true | BLOCKED | 缺 CHECK U6.longPress.true |
| C3/check:U6.region.true | BLOCKED | 缺 CHECK U6.region.true |
| C3/check:U6.map.none.false.false | BLOCKED | 缺 CHECK U6.map.none.false.false |
| C3/check:U6.map.none.false.true | BLOCKED | 缺 CHECK U6.map.none.false.true |
| C3/check:U6.map.none.true.false | BLOCKED | 缺 CHECK U6.map.none.true.false |
| C3/check:U6.map.none.true.true | BLOCKED | 缺 CHECK U6.map.none.true.true |
| C3/check:U6.map.volume.false.false | BLOCKED | 缺 CHECK U6.map.volume.false.false |
| C3/check:U6.map.volume.false.true | BLOCKED | 缺 CHECK U6.map.volume.false.true |
| C3/check:U6.map.volume.true.false | BLOCKED | 缺 CHECK U6.map.volume.true.false |
| C3/check:U6.map.volume.true.true | BLOCKED | 缺 CHECK U6.map.volume.true.true |
| C3/check:U6.map.brightness.false.false | BLOCKED | 缺 CHECK U6.map.brightness.false.false |
| C3/check:U6.map.brightness.false.true | BLOCKED | 缺 CHECK U6.map.brightness.false.true |
| C3/check:U6.map.brightness.true.false | BLOCKED | 缺 CHECK U6.map.brightness.true.false |
| C3/check:U6.map.brightness.true.true | BLOCKED | 缺 CHECK U6.map.brightness.true.true |
| C3/check:U6.map.seek.false.false | BLOCKED | 缺 CHECK U6.map.seek.false.false |
| C3/check:U6.map.seek.false.true | BLOCKED | 缺 CHECK U6.map.seek.false.true |
| C3/check:U6.map.seek.true.false | BLOCKED | 缺 CHECK U6.map.seek.true.false |
| C3/check:U6.map.seek.true.true | BLOCKED | 缺 CHECK U6.map.seek.true.true |
| C3/check:U6.douyin.tap | BLOCKED | 缺 CHECK U6.douyin.tap |
| C3/check:U6.douyin.double | BLOCKED | 缺 CHECK U6.douyin.double |
| C3/check:U6.douyin.drag | BLOCKED | 缺 CHECK U6.douyin.drag |
| C3/check:A13.native.false | BLOCKED | 缺 CHECK A13.native.false |
| C3/check:A13.native.true | BLOCKED | 缺 CHECK A13.native.true |
| C3/check:U6.disabled.double.none.false.false | BLOCKED | 缺 CHECK U6.disabled.double.none.false.false |
| C3/check:U6.disabled.pinch.none.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.none.false.false |
| C3/check:U6.disabled.double.none.false.true | BLOCKED | 缺 CHECK U6.disabled.double.none.false.true |
| C3/check:U6.disabled.pinch.none.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.none.false.true |
| C3/check:U6.disabled.double.none.true.false | BLOCKED | 缺 CHECK U6.disabled.double.none.true.false |
| C3/check:U6.disabled.pinch.none.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.none.true.false |
| C3/check:U6.disabled.double.none.true.true | BLOCKED | 缺 CHECK U6.disabled.double.none.true.true |
| C3/check:U6.disabled.pinch.none.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.none.true.true |
| C3/check:U6.disabled.double.volume.false.false | BLOCKED | 缺 CHECK U6.disabled.double.volume.false.false |
| C3/check:U6.disabled.pinch.volume.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.false.false |
| C3/check:U6.disabled.double.volume.false.true | BLOCKED | 缺 CHECK U6.disabled.double.volume.false.true |
| C3/check:U6.disabled.pinch.volume.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.false.true |
| C3/check:U6.disabled.double.volume.true.false | BLOCKED | 缺 CHECK U6.disabled.double.volume.true.false |
| C3/check:U6.disabled.pinch.volume.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.true.false |
| C3/check:U6.disabled.double.volume.true.true | BLOCKED | 缺 CHECK U6.disabled.double.volume.true.true |
| C3/check:U6.disabled.pinch.volume.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.true.true |
| C3/check:U6.disabled.double.brightness.false.false | BLOCKED | 缺 CHECK U6.disabled.double.brightness.false.false |
| C3/check:U6.disabled.pinch.brightness.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.false.false |
| C3/check:U6.disabled.double.brightness.false.true | BLOCKED | 缺 CHECK U6.disabled.double.brightness.false.true |
| C3/check:U6.disabled.pinch.brightness.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.false.true |
| C3/check:U6.disabled.double.brightness.true.false | BLOCKED | 缺 CHECK U6.disabled.double.brightness.true.false |
| C3/check:U6.disabled.pinch.brightness.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.true.false |
| C3/check:U6.disabled.double.brightness.true.true | BLOCKED | 缺 CHECK U6.disabled.double.brightness.true.true |
| C3/check:U6.disabled.pinch.brightness.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.true.true |
| C3/check:U6.disabled.double.seek.false.false | BLOCKED | 缺 CHECK U6.disabled.double.seek.false.false |
| C3/check:U6.disabled.pinch.seek.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.false.false |
| C3/check:U6.disabled.double.seek.false.true | BLOCKED | 缺 CHECK U6.disabled.double.seek.false.true |
| C3/check:U6.disabled.pinch.seek.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.false.true |
| C3/check:U6.disabled.double.seek.true.false | BLOCKED | 缺 CHECK U6.disabled.double.seek.true.false |
| C3/check:U6.disabled.pinch.seek.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.true.false |
| C3/check:U6.disabled.double.seek.true.true | BLOCKED | 缺 CHECK U6.disabled.double.seek.true.true |
| C3/check:U6.disabled.pinch.seek.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.true.true |
| C3/check:U6.dvr.false | BLOCKED | 缺 CHECK U6.dvr.false |
| C3/check:U6.dvr.true | BLOCKED | 缺 CHECK U6.dvr.true |
| C4/check:C4.abrDown | BLOCKED | 缺 CHECK C4.abrDown |
| C4/check:CONTRACT.defaults | BLOCKED | 缺 CHECK CONTRACT.defaults |
| C4/check:CONTRACT.probe.true | BLOCKED | 缺 CHECK CONTRACT.probe.true |
| C4/check:CONTRACT.probe.false | BLOCKED | 缺 CHECK CONTRACT.probe.false |
| C5/check:C5.start.true.true | BLOCKED | 缺 CHECK C5.start.true.true |
| C5/check:C5.reset.true.true | BLOCKED | 缺 CHECK C5.reset.true.true |
| C5/check:C5.auto.true.true | BLOCKED | 缺 CHECK C5.auto.true.true |
| C5/check:C5.sticky.true.true | BLOCKED | 缺 CHECK C5.sticky.true.true |
| C5/check:C5.hide.true.true | BLOCKED | 缺 CHECK C5.hide.true.true |
| C5/check:C5.start.true.false | BLOCKED | 缺 CHECK C5.start.true.false |
| C5/check:C5.reset.true.false | BLOCKED | 缺 CHECK C5.reset.true.false |
| C5/check:C5.auto.true.false | BLOCKED | 缺 CHECK C5.auto.true.false |
| C5/check:C5.sticky.true.false | BLOCKED | 缺 CHECK C5.sticky.true.false |
| C5/check:C5.hide.true.false | BLOCKED | 缺 CHECK C5.hide.true.false |
| C5/check:C5.start.false.true | BLOCKED | 缺 CHECK C5.start.false.true |
| C5/check:C5.reset.false.true | BLOCKED | 缺 CHECK C5.reset.false.true |
| C5/check:C5.auto.false.true | BLOCKED | 缺 CHECK C5.auto.false.true |
| C5/check:C5.sticky.false.true | BLOCKED | 缺 CHECK C5.sticky.false.true |
| C5/check:C5.hide.false.true | BLOCKED | 缺 CHECK C5.hide.false.true |
| C5/check:C5.start.false.false | BLOCKED | 缺 CHECK C5.start.false.false |
| C5/check:C5.reset.false.false | BLOCKED | 缺 CHECK C5.reset.false.false |
| C5/check:C5.auto.false.false | BLOCKED | 缺 CHECK C5.auto.false.false |
| C5/check:C5.sticky.false.false | BLOCKED | 缺 CHECK C5.sticky.false.false |
| C5/check:C5.hide.false.false | BLOCKED | 缺 CHECK C5.hide.false.false |
| C5/check:C5.defaults | BLOCKED | 缺 CHECK C5.defaults |
| C5/check:C5.paint.true.true | BLOCKED | 缺 CHECK C5.paint.true.true |
| C5/check:C5.paint.true.false | BLOCKED | 缺 CHECK C5.paint.true.false |
| C5/check:C5.paint.false.true | BLOCKED | 缺 CHECK C5.paint.false.true |
| C5/check:C5.paint.false.false | BLOCKED | 缺 CHECK C5.paint.false.false |
| C6/check:C6.spawn.false | BLOCKED | 缺 CHECK C6.spawn.false |
| C6/check:C6.spawn.true | BLOCKED | 缺 CHECK C6.spawn.true |
| C6/check:C6.scroll | BLOCKED | 缺 CHECK C6.scroll |
| C6/check:C6.unique | BLOCKED | 缺 CHECK C6.unique |
| C6/check:C6.retired | BLOCKED | 缺 CHECK C6.retired |
| C8/check:C8.card.true | BLOCKED | 缺 CHECK C8.card.true |
| C8/check:C8.cancel.true | BLOCKED | 缺 CHECK C8.cancel.true |
| C8/check:C8.auto.true | BLOCKED | 缺 CHECK C8.auto.true |
| C8/check:C8.card.false | BLOCKED | 缺 CHECK C8.card.false |
| C8/check:C8.cancel.false | BLOCKED | 缺 CHECK C8.cancel.false |
| C8/check:C8.auto.false | BLOCKED | 缺 CHECK C8.auto.false |
| C8/check:C8.now | BLOCKED | 缺 CHECK C8.now |
| C9/check:C9.waits | BLOCKED | 缺 CHECK C9.waits |
| C9/check:A27.rolls | BLOCKED | 缺 CHECK A27.rolls |
| C10/check:C10.theme.default | BLOCKED | 缺 CHECK C10.theme.default |
| C10/check:C10.theme.bilibili | BLOCKED | 缺 CHECK C10.theme.bilibili |
| C10/check:C10.theme.douyin | BLOCKED | 缺 CHECK C10.theme.douyin |
| C10/check:C10.strings.default | BLOCKED | 缺 CHECK C10.strings.default |
| C10/check:C10.strings.bilibili | BLOCKED | 缺 CHECK C10.strings.bilibili |
| C10/check:C10.accent.douyin | BLOCKED | 缺 CHECK C10.accent.douyin |
| C10/check:C10.buffering | BLOCKED | 缺 CHECK C10.buffering |
| C10/check:C10.theme.mini | BLOCKED | 缺 CHECK C10.theme.mini |
| C11/check:C11.off | BLOCKED | 缺 CHECK C11.off |
| C11/check:A24.commit | BLOCKED | 缺 CHECK A24.commit |
| C11/check:A24.cutoverTo | BLOCKED | 缺 CHECK A24.cutoverTo |
| C12/check:C12.defaultOff | BLOCKED | 缺 CHECK C12.defaultOff |
| C12/check:A26.persistent | BLOCKED | 缺 CHECK A26.persistent |
| C12/check:A26.tap | BLOCKED | 缺 CHECK A26.tap |
| C12/check:A26.page | BLOCKED | 缺 CHECK A26.page |
| C12/check:A26.setRect | BLOCKED | 缺 CHECK A26.setRect |
| C12/check:A26.hide | BLOCKED | 缺 CHECK A26.hide |
| C12/check:A26.close | BLOCKED | 缺 CHECK A26.close |
| C12/check:U8.drag | BLOCKED | 缺 CHECK U8.drag |
| C12/check:U8.snap | BLOCKED | 缺 CHECK U8.snap |
| C12/check:U8.fling | BLOCKED | 缺 CHECK U8.fling |
| C12/check:U8.resize | BLOCKED | 缺 CHECK U8.resize |
| C13/check:C13.off | BLOCKED | 缺 CHECK C13.off |
| C13/check:C13.defaultHeartbeat | BLOCKED | 缺 CHECK C13.defaultHeartbeat |
| C13/check:F7.false.ended.endCount | BLOCKED | 缺 CHECK F7.false.ended.endCount |
| C13/check:F7.false.ended.summary | BLOCKED | 缺 CHECK F7.false.ended.summary |
| C13/check:F7.false.ended.truncated | BLOCKED | 缺 CHECK F7.false.ended.truncated |
| C13/check:F7.false.ended.firstFrameCount | BLOCKED | 缺 CHECK F7.false.ended.firstFrameCount |
| C13/check:F7.false.ended.firstFrame | BLOCKED | 缺 CHECK F7.false.ended.firstFrame |
| C13/check:F7.false.stopped.endCount | BLOCKED | 缺 CHECK F7.false.stopped.endCount |
| C13/check:F7.false.stopped.summary | BLOCKED | 缺 CHECK F7.false.stopped.summary |
| C13/check:F7.false.stopped.truncated | BLOCKED | 缺 CHECK F7.false.stopped.truncated |
| C13/check:F7.false.stopped.firstFrameCount | BLOCKED | 缺 CHECK F7.false.stopped.firstFrameCount |
| C13/check:F7.false.stopped.firstFrame | BLOCKED | 缺 CHECK F7.false.stopped.firstFrame |
| C13/check:F7.false.failed.endCount | BLOCKED | 缺 CHECK F7.false.failed.endCount |
| C13/check:F7.false.failed.summary | BLOCKED | 缺 CHECK F7.false.failed.summary |
| C13/check:F7.false.failed.truncated | BLOCKED | 缺 CHECK F7.false.failed.truncated |
| C13/check:F7.false.failed.firstFrameCount | BLOCKED | 缺 CHECK F7.false.failed.firstFrameCount |
| C13/check:F7.false.failed.firstFrame | BLOCKED | 缺 CHECK F7.false.failed.firstFrame |
| C13/check:F7.false.abandoned.endCount | BLOCKED | 缺 CHECK F7.false.abandoned.endCount |
| C13/check:F7.false.abandoned.summary | BLOCKED | 缺 CHECK F7.false.abandoned.summary |
| C13/check:F7.false.abandoned.truncated | BLOCKED | 缺 CHECK F7.false.abandoned.truncated |
| C13/check:F7.false.truncated.endCount | BLOCKED | 缺 CHECK F7.false.truncated.endCount |
| C13/check:F7.false.truncated.summary | BLOCKED | 缺 CHECK F7.false.truncated.summary |
| C13/check:F7.false.truncated.truncated | BLOCKED | 缺 CHECK F7.false.truncated.truncated |
| C13/check:F7.false.truncated.firstFrameCount | BLOCKED | 缺 CHECK F7.false.truncated.firstFrameCount |
| C13/check:F7.false.truncated.firstFrame | BLOCKED | 缺 CHECK F7.false.truncated.firstFrame |
| C13/check:F7.false.disabled.endCount | BLOCKED | 缺 CHECK F7.false.disabled.endCount |
| C13/check:F7.false.disabled.summary | BLOCKED | 缺 CHECK F7.false.disabled.summary |
| C13/check:F7.false.disabled.truncated | BLOCKED | 缺 CHECK F7.false.disabled.truncated |
| C13/check:F7.false.disabled.firstFrameCount | BLOCKED | 缺 CHECK F7.false.disabled.firstFrameCount |
| C13/check:F7.false.disabled.firstFrame | BLOCKED | 缺 CHECK F7.false.disabled.firstFrame |
| C13/check:F7.true.ended.endCount | BLOCKED | 缺 CHECK F7.true.ended.endCount |
| C13/check:F7.true.ended.summary | BLOCKED | 缺 CHECK F7.true.ended.summary |
| C13/check:F7.true.ended.truncated | BLOCKED | 缺 CHECK F7.true.ended.truncated |
| C13/check:F7.true.ended.firstFrameCount | BLOCKED | 缺 CHECK F7.true.ended.firstFrameCount |
| C13/check:F7.true.ended.firstFrame | BLOCKED | 缺 CHECK F7.true.ended.firstFrame |
| C13/check:F7.true.stopped.endCount | BLOCKED | 缺 CHECK F7.true.stopped.endCount |
| C13/check:F7.true.stopped.summary | BLOCKED | 缺 CHECK F7.true.stopped.summary |
| C13/check:F7.true.stopped.truncated | BLOCKED | 缺 CHECK F7.true.stopped.truncated |
| C13/check:F7.true.stopped.firstFrameCount | BLOCKED | 缺 CHECK F7.true.stopped.firstFrameCount |
| C13/check:F7.true.stopped.firstFrame | BLOCKED | 缺 CHECK F7.true.stopped.firstFrame |
| C13/check:F7.true.failed.endCount | BLOCKED | 缺 CHECK F7.true.failed.endCount |
| C13/check:F7.true.failed.summary | BLOCKED | 缺 CHECK F7.true.failed.summary |
| C13/check:F7.true.failed.truncated | BLOCKED | 缺 CHECK F7.true.failed.truncated |
| C13/check:F7.true.failed.firstFrameCount | BLOCKED | 缺 CHECK F7.true.failed.firstFrameCount |
| C13/check:F7.true.failed.firstFrame | BLOCKED | 缺 CHECK F7.true.failed.firstFrame |
| C13/check:F7.true.abandoned.endCount | BLOCKED | 缺 CHECK F7.true.abandoned.endCount |
| C13/check:F7.true.abandoned.summary | BLOCKED | 缺 CHECK F7.true.abandoned.summary |
| C13/check:F7.true.abandoned.truncated | BLOCKED | 缺 CHECK F7.true.abandoned.truncated |
| C13/check:F7.true.truncated.endCount | BLOCKED | 缺 CHECK F7.true.truncated.endCount |
| C13/check:F7.true.truncated.summary | BLOCKED | 缺 CHECK F7.true.truncated.summary |
| C13/check:F7.true.truncated.truncated | BLOCKED | 缺 CHECK F7.true.truncated.truncated |
| C13/check:F7.true.truncated.firstFrameCount | BLOCKED | 缺 CHECK F7.true.truncated.firstFrameCount |
| C13/check:F7.true.truncated.firstFrame | BLOCKED | 缺 CHECK F7.true.truncated.firstFrame |
| C13/check:F7.true.disabled.endCount | BLOCKED | 缺 CHECK F7.true.disabled.endCount |
| C13/check:F7.true.disabled.summary | BLOCKED | 缺 CHECK F7.true.disabled.summary |
| C13/check:F7.true.disabled.truncated | BLOCKED | 缺 CHECK F7.true.disabled.truncated |
| C13/check:F7.true.disabled.firstFrameCount | BLOCKED | 缺 CHECK F7.true.disabled.firstFrameCount |
| C13/check:F7.true.disabled.firstFrame | BLOCKED | 缺 CHECK F7.true.disabled.firstFrame |
| C13/check:F7.heartbeat | BLOCKED | 缺 CHECK F7.heartbeat |
| C13/check:F7.nativeFirstFrame | BLOCKED | 缺 CHECK F7.nativeFirstFrame |
| C13/check:F7.nativeSample | BLOCKED | 缺 CHECK F7.nativeSample |
| C13/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-ended.json; 缺事件记录 |
| C13/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-stopped.json; 缺事件记录 |
| C13/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-failed.json; 缺事件记录 |
| C13/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-abandoned.json; 缺事件记录 |
| C13/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-truncated.json; 缺事件记录 |
| C13/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch17-qoe-stall-release.json; 缺事件记录 |
| C14/log:V5 | BLOCKED | he-recovery.log: 缺完成标记 |
| C14/log:V6 | BLOCKED | he-recovery.log: 缺完成标记 |
| C14/log:V7 | BLOCKED | he-recovery.log: 缺完成标记 |
| C14/log:V8 | BLOCKED | he-recovery.log: 缺完成标记 |
| C14/check:CONTRACT.error.overlay.nonterminal | BLOCKED | 缺 CHECK CONTRACT.error.overlay.nonterminal |
| C14/check:CONTRACT.error.overlay.terminal | BLOCKED | 缺 CHECK CONTRACT.error.overlay.terminal |
| C15/check:C15.maxDuration | BLOCKED | 缺 CHECK C15.maxDuration |
| C15/keepalive_wake:1 | BLOCKED | keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联 |
| C15/log:S2 | BLOCKED | keepalive-core.log: 缺完成标记 |
| C15/log:S3 | BLOCKED | keepalive-core.log: 缺完成标记 |
| C15/check:S6.publicFallback | BLOCKED | 缺 CHECK S6.publicFallback |
| C15/log:S13 | BLOCKED | keepalive-core.log: 缺完成标记 |
| C15/log:S17 | BLOCKED | keepalive-core.log: 缺完成标记 |
| C16/check:C16.matrix | BLOCKED | 缺 CHECK C16.matrix |
| C16/check:C16.probe | BLOCKED | 缺 CHECK C16.probe |
| C17/check:C17.pick | BLOCKED | 缺 CHECK C17.pick |
| C17/check:N4.applied | BLOCKED | 缺 CHECK N4.applied |
| C17/check:N4.restore | BLOCKED | 缺 CHECK N4.restore |
| C17/check:N19.failover | BLOCKED | 缺 CHECK N19.failover |
| C17/check:C17.sameAs | BLOCKED | 缺 CHECK C17.sameAs |
| C17/check:C17.headers.one | BLOCKED | 缺 CHECK C17.headers.one |
| C17/check:C17.headers.two | BLOCKED | 缺 CHECK C17.headers.two |
| E.MovaReady/event:MovaReady | BLOCKED | 缺 EVENT MovaReady |
| E.MovaSourceChange/event:MovaSourceChange | BLOCKED | 缺 EVENT MovaSourceChange |
| E.MovaPlay/event:MovaPlay | BLOCKED | 缺 EVENT MovaPlay |
| E.MovaPause/event:MovaPause | BLOCKED | 缺 EVENT MovaPause |
| E.MovaDone/event:MovaDone | BLOCKED | 缺 EVENT MovaDone |
| E.MovaSeek/event:MovaSeek | BLOCKED | 缺 EVENT MovaSeek |
| E.MovaSeeked/event:MovaSeeked | BLOCKED | 缺 EVENT MovaSeeked |
| E.MovaBufferChange/event:MovaBufferChange | BLOCKED | 缺 EVENT MovaBufferChange |
| E.MovaDurationChange/event:MovaDurationChange | BLOCKED | 缺 EVENT MovaDurationChange |
| E.MovaFirstFrame/event:MovaFirstFrame | BLOCKED | 缺 EVENT MovaFirstFrame |
| E.MovaSizeChange/event:MovaSizeChange | BLOCKED | 缺 EVENT MovaSizeChange |
| E.MovaVolumeChange/event:MovaVolumeChange | BLOCKED | 缺 EVENT MovaVolumeChange |
| E.MovaBrightChange/event:MovaBrightChange | BLOCKED | 缺 EVENT MovaBrightChange |
| E.MovaRateChange/event:MovaRateChange | BLOCKED | 缺 EVENT MovaRateChange |
| E.MovaQualityListChange/event:MovaQualityListChange | BLOCKED | 缺 EVENT MovaQualityListChange |
| E.MovaQualityChange/event:MovaQualityChange | BLOCKED | 缺 EVENT MovaQualityChange |
| E.MovaAbrDownShift/event:MovaAbrDownShift | BLOCKED | 缺 EVENT MovaAbrDownShift |
| E.MovaFitChange/event:MovaFitChange | BLOCKED | 缺 EVENT MovaFitChange |
| E.MovaZoomChange/event:MovaZoomChange | BLOCKED | 缺 EVENT MovaZoomChange |
| E.MovaLockChange/event:MovaLockChange | BLOCKED | 缺 EVENT MovaLockChange |
| E.MovaFullScreenChange/event:MovaFullScreenChange | BLOCKED | 缺 EVENT MovaFullScreenChange |
| E.MovaOrientationChange/event:MovaOrientationChange | BLOCKED | 缺 EVENT MovaOrientationChange |
| E.MovaPipChange/event:MovaPipChange | BLOCKED | 缺 EVENT MovaPipChange |
| E.MovaMiniChange/event:MovaMiniChange | BLOCKED | 缺 EVENT MovaMiniChange |
| E.MovaTimeShiftChange/event:MovaTimeShiftChange | BLOCKED | 缺 EVENT MovaTimeShiftChange |
| E.MovaLiveEdgeReach/event:MovaLiveEdgeReach | BLOCKED | 缺 EVENT MovaLiveEdgeReach |
| E.MovaPreviewBlock/event:MovaPreviewBlock | BLOCKED | 缺 EVENT MovaPreviewBlock |
| E.MovaPreviewBlock/check:E.MovaPreviewBlock.network | BLOCKED | 缺 CHECK E.MovaPreviewBlock.network |
| E.MovaSttBlock/event:MovaSttBlock | BLOCKED | 缺 EVENT MovaSttBlock |
| E.MovaSwapChange/event:MovaSwapChange | BLOCKED | 缺 EVENT MovaCutoverChange |
| E.MovaErrorEvent/event:MovaErrorEvent | BLOCKED | 缺 EVENT MovaErrorEvent |
| E.MovaErrorEvent/check:CONTRACT.error.nonterminal | BLOCKED | 缺 CHECK CONTRACT.error.nonterminal |
| E.MovaErrorEvent/check:CONTRACT.error.terminal | BLOCKED | 缺 CHECK CONTRACT.error.terminal |
| E.MovaPlayFailure/event:MovaPlayFailure | BLOCKED | 缺 EVENT MovaPlayFailure |
| E.MovaRecovered/event:MovaRecovered | BLOCKED | 缺 EVENT MovaRecovered |
| E.MovaFailover/event:MovaFailover | BLOCKED | 缺 EVENT MovaFailover |
| E.MovaStandbyChange/event:MovaStandbyChange | BLOCKED | 缺 EVENT MovaKeepAliveChange |
| E.MovaStandbyResume/event:MovaStandbyResume | BLOCKED | 缺 EVENT MovaKeepAliveResume |
| E1/lifecycle:0 | BLOCKED | 缺自然生命周期事件序列 |
| E2/check:E2.disabled | BLOCKED | 缺 CHECK E2.disabled |
| E2/check:C11.off | BLOCKED | 缺 CHECK C11.off |
| E2/check:C13.off | BLOCKED | 缺 CHECK C13.off |
| U1/check:U1.surface | BLOCKED | 缺 CHECK U1.surface |
| U1/check:U1.borrowed | BLOCKED | 缺 CHECK U1.borrowed |
| U1/check:U1.feedOwned | BLOCKED | 缺 CHECK U1.feedOwned |
| U1/check:U1.feedSource | BLOCKED | 缺 CHECK U1.feedSource |
| U1/check:U1.feedDispose | BLOCKED | 缺 CHECK U1.feedDispose |
| U1/check:U1.native.surface | BLOCKED | 缺 CHECK U1.native.surface |
| U1/check:U1.native.player.mounted | BLOCKED | 缺 CHECK U1.native.player.mounted |
| U1/check:U1.native.borrowed | BLOCKED | 缺 CHECK U1.native.borrowed |
| U1/check:U1.native.player.disposed | BLOCKED | 缺 CHECK U1.native.player.disposed |
| U1/check:U1.native.view.lazy | BLOCKED | 缺 CHECK U1.native.view.lazy |
| U1/check:U1.native.view.source | BLOCKED | 缺 CHECK U1.native.view.source |
| U1/check:U1.native.view.disposed | BLOCKED | 缺 CHECK U1.native.view.disposed |
| U1/check:U1.native.feed | BLOCKED | 缺 CHECK U1.native.feed |
| U1/check:U9.native.ticker | BLOCKED | 缺 CHECK U9.native.ticker |
| U1/check:U9.native.route | BLOCKED | 缺 CHECK U9.native.route |
| U2/check:U2.componentNames | BLOCKED | 缺 CHECK U2.componentNames |
| U2/check:U2.tree.default | BLOCKED | 缺 CHECK U2.tree.default |
| U2/check:U2.mounted.default | BLOCKED | 缺 CHECK U2.mounted.default |
| U2/check:U2.tree.bilibili | BLOCKED | 缺 CHECK U2.tree.bilibili |
| U2/check:U2.mounted.bilibili | BLOCKED | 缺 CHECK U2.mounted.bilibili |
| U2/check:U2.tree.douyin | BLOCKED | 缺 CHECK U2.tree.douyin |
| U2/check:U2.mounted.douyin | BLOCKED | 缺 CHECK U2.mounted.douyin |
| U2/check:U2.tree.minimal | BLOCKED | 缺 CHECK U2.tree.minimal |
| U2/check:U2.mounted.minimal | BLOCKED | 缺 CHECK U2.mounted.minimal |
| U2/check:U2.tree.mini | BLOCKED | 缺 CHECK U2.tree.mini |
| U2/check:U2.mounted.mini | BLOCKED | 缺 CHECK U2.mounted.mini |
| U2/check:U2.patchNoop | BLOCKED | 缺 CHECK U2.patchNoop |
| U2/check:U2.patchTree.default | BLOCKED | 缺 CHECK U2.patchTree.default |
| U2/check:U2.patchMounted.default | BLOCKED | 缺 CHECK U2.patchMounted.default |
| U2/check:U2.patchClick.default.gapAdd | BLOCKED | 缺 CHECK U2.patchClick.default.gapAdd |
| U2/check:U2.patchClick.default.gapReplace | BLOCKED | 缺 CHECK U2.patchClick.default.gapReplace |
| U2/check:U2.patchClick.default.gapInsert | BLOCKED | 缺 CHECK U2.patchClick.default.gapInsert |
| U2/check:U2.patchTree.bilibili | BLOCKED | 缺 CHECK U2.patchTree.bilibili |
| U2/check:U2.patchMounted.bilibili | BLOCKED | 缺 CHECK U2.patchMounted.bilibili |
| U2/check:U2.patchClick.bilibili.gapInsert | BLOCKED | 缺 CHECK U2.patchClick.bilibili.gapInsert |
| U2/check:U2.patchClick.bilibili.gapOverlay | BLOCKED | 缺 CHECK U2.patchClick.bilibili.gapOverlay |
| U2/check:CONTRACT.error.overlay.nonterminal | BLOCKED | 缺 CHECK CONTRACT.error.overlay.nonterminal |
| U2/check:CONTRACT.error.overlay.terminal | BLOCKED | 缺 CHECK CONTRACT.error.overlay.terminal |
| U3/check:U3.title | BLOCKED | 缺 CHECK U3.title |
| U3/check:U3.pipHidden | BLOCKED | 缺 CHECK U3.pipHidden |
| U3/check:U3.fit | BLOCKED | 缺 CHECK U3.fit |
| U3/check:U3.fullscreenOn | BLOCKED | 缺 CHECK U3.fullscreenOn |
| U3/check:U3.fullscreenOff | BLOCKED | 缺 CHECK U3.fullscreenOff |
| U3/check:U3.qualityCount | BLOCKED | 缺 CHECK U3.qualityCount |
| U3/check:U3.qualityMenu | BLOCKED | 缺 CHECK U3.qualityMenu |
| U3/check:U3.qualitySelect | BLOCKED | 缺 CHECK U3.qualitySelect |
| U3/check:U3.pipClick | BLOCKED | 缺 CHECK U3.pipClick |
| U3/check:U3.directionDesktop | BLOCKED | 缺 CHECK U3.directionDesktop |
| U3/check:U3.directionMobile | BLOCKED | 缺 CHECK U3.directionMobile |
| U3/check:U3.direction1 | BLOCKED | 缺 CHECK U3.direction1 |
| U3/check:U3.direction2 | BLOCKED | 缺 CHECK U3.direction2 |
| U3/check:CONTRACT.probe.true | BLOCKED | 缺 CHECK CONTRACT.probe.true |
| U3/check:CONTRACT.probe.false | BLOCKED | 缺 CHECK CONTRACT.probe.false |
| U3/check:CONTRACT.probe.uiOff | BLOCKED | 缺 CHECK CONTRACT.probe.uiOff |
| U4/check:U4.disabled | BLOCKED | 缺 CHECK U4.disabled |
| U4/check:U4.enabled | BLOCKED | 缺 CHECK U4.enabled |
| U4/check:U4.drag | BLOCKED | 缺 CHECK U4.drag |
| U4/check:U4.commit | BLOCKED | 缺 CHECK U4.commit |
| U4/check:U4.label | BLOCKED | 缺 CHECK U4.label |
| U4/check:U4.live.false.edge | BLOCKED | 缺 CHECK U4.live.false.edge |
| U4/check:U4.live.true.edge | BLOCKED | 缺 CHECK U4.live.true.edge |
| U4/check:U4.live.span | BLOCKED | 缺 CHECK U4.live.span |
| U4/check:U4.live.behind | BLOCKED | 缺 CHECK U4.live.behind |
| U4/check:U4.live.back | BLOCKED | 缺 CHECK U4.live.back |
| U4/check:U4.preview.render | BLOCKED | 缺 CHECK U4.preview.render |
| U4/check:U4.preview.release | BLOCKED | 缺 CHECK U4.preview.release |
| U4/check:U4.throttle.window | BLOCKED | 缺 CHECK U4.throttle.window |
| U4/check:U4.preview.image | BLOCKED | 缺 CHECK U4.preview.image |
| U4/check:U4.preview.imageReleased | BLOCKED | 缺 CHECK U4.preview.imageReleased |
| U5/check:U5.play | BLOCKED | 缺 CHECK U5.play |
| U5/check:U5.pause | BLOCKED | 缺 CHECK U5.pause |
| U5/check:U5.rates | BLOCKED | 缺 CHECK U5.rates |
| U5/check:U5.volume | BLOCKED | 缺 CHECK U5.volume |
| U5/check:U5.brightness | BLOCKED | 缺 CHECK U5.brightness |
| U5/check:U5.seek | BLOCKED | 缺 CHECK U5.seek |
| U5/check:U5.zoom | BLOCKED | 缺 CHECK U5.zoom |
| U5/check:U5.fit.contract | BLOCKED | 缺 CHECK U5.fit.contract |
| U5/check:U5.quality.contract | BLOCKED | 缺 CHECK U5.quality.contract |
| U6/check:C3.left.false | BLOCKED | 缺 CHECK C3.left.false |
| U6/check:C3.right.false | BLOCKED | 缺 CHECK C3.right.false |
| U6/check:U6.tap.false | BLOCKED | 缺 CHECK U6.tap.false |
| U6/check:U6.doubleRight.false | BLOCKED | 缺 CHECK U6.doubleRight.false |
| U6/check:U6.doubleLeft.false | BLOCKED | 缺 CHECK U6.doubleLeft.false |
| U6/check:U6.horizontal.false | BLOCKED | 缺 CHECK U6.horizontal.false |
| U6/check:U6.pinch.false | BLOCKED | 缺 CHECK U6.pinch.false |
| U6/check:U6.longPress.false | BLOCKED | 缺 CHECK U6.longPress.false |
| U6/check:U6.region.false | BLOCKED | 缺 CHECK U6.region.false |
| U6/check:C3.left.true | BLOCKED | 缺 CHECK C3.left.true |
| U6/check:C3.right.true | BLOCKED | 缺 CHECK C3.right.true |
| U6/check:U6.tap.true | BLOCKED | 缺 CHECK U6.tap.true |
| U6/check:U6.doubleRight.true | BLOCKED | 缺 CHECK U6.doubleRight.true |
| U6/check:U6.doubleLeft.true | BLOCKED | 缺 CHECK U6.doubleLeft.true |
| U6/check:U6.horizontal.true | BLOCKED | 缺 CHECK U6.horizontal.true |
| U6/check:U6.pinch.true | BLOCKED | 缺 CHECK U6.pinch.true |
| U6/check:U6.longPress.true | BLOCKED | 缺 CHECK U6.longPress.true |
| U6/check:U6.region.true | BLOCKED | 缺 CHECK U6.region.true |
| U6/check:U6.map.none.false.false | BLOCKED | 缺 CHECK U6.map.none.false.false |
| U6/check:U6.map.none.false.true | BLOCKED | 缺 CHECK U6.map.none.false.true |
| U6/check:U6.map.none.true.false | BLOCKED | 缺 CHECK U6.map.none.true.false |
| U6/check:U6.map.none.true.true | BLOCKED | 缺 CHECK U6.map.none.true.true |
| U6/check:U6.map.volume.false.false | BLOCKED | 缺 CHECK U6.map.volume.false.false |
| U6/check:U6.map.volume.false.true | BLOCKED | 缺 CHECK U6.map.volume.false.true |
| U6/check:U6.map.volume.true.false | BLOCKED | 缺 CHECK U6.map.volume.true.false |
| U6/check:U6.map.volume.true.true | BLOCKED | 缺 CHECK U6.map.volume.true.true |
| U6/check:U6.map.brightness.false.false | BLOCKED | 缺 CHECK U6.map.brightness.false.false |
| U6/check:U6.map.brightness.false.true | BLOCKED | 缺 CHECK U6.map.brightness.false.true |
| U6/check:U6.map.brightness.true.false | BLOCKED | 缺 CHECK U6.map.brightness.true.false |
| U6/check:U6.map.brightness.true.true | BLOCKED | 缺 CHECK U6.map.brightness.true.true |
| U6/check:U6.map.seek.false.false | BLOCKED | 缺 CHECK U6.map.seek.false.false |
| U6/check:U6.map.seek.false.true | BLOCKED | 缺 CHECK U6.map.seek.false.true |
| U6/check:U6.map.seek.true.false | BLOCKED | 缺 CHECK U6.map.seek.true.false |
| U6/check:U6.map.seek.true.true | BLOCKED | 缺 CHECK U6.map.seek.true.true |
| U6/check:U6.douyin.tap | BLOCKED | 缺 CHECK U6.douyin.tap |
| U6/check:U6.douyin.double | BLOCKED | 缺 CHECK U6.douyin.double |
| U6/check:U6.douyin.drag | BLOCKED | 缺 CHECK U6.douyin.drag |
| U6/check:A13.native.false | BLOCKED | 缺 CHECK A13.native.false |
| U6/check:A13.native.true | BLOCKED | 缺 CHECK A13.native.true |
| U6/check:U6.disabled.double.none.false.false | BLOCKED | 缺 CHECK U6.disabled.double.none.false.false |
| U6/check:U6.disabled.pinch.none.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.none.false.false |
| U6/check:U6.disabled.double.none.false.true | BLOCKED | 缺 CHECK U6.disabled.double.none.false.true |
| U6/check:U6.disabled.pinch.none.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.none.false.true |
| U6/check:U6.disabled.double.none.true.false | BLOCKED | 缺 CHECK U6.disabled.double.none.true.false |
| U6/check:U6.disabled.pinch.none.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.none.true.false |
| U6/check:U6.disabled.double.none.true.true | BLOCKED | 缺 CHECK U6.disabled.double.none.true.true |
| U6/check:U6.disabled.pinch.none.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.none.true.true |
| U6/check:U6.disabled.double.volume.false.false | BLOCKED | 缺 CHECK U6.disabled.double.volume.false.false |
| U6/check:U6.disabled.pinch.volume.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.false.false |
| U6/check:U6.disabled.double.volume.false.true | BLOCKED | 缺 CHECK U6.disabled.double.volume.false.true |
| U6/check:U6.disabled.pinch.volume.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.false.true |
| U6/check:U6.disabled.double.volume.true.false | BLOCKED | 缺 CHECK U6.disabled.double.volume.true.false |
| U6/check:U6.disabled.pinch.volume.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.true.false |
| U6/check:U6.disabled.double.volume.true.true | BLOCKED | 缺 CHECK U6.disabled.double.volume.true.true |
| U6/check:U6.disabled.pinch.volume.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.volume.true.true |
| U6/check:U6.disabled.double.brightness.false.false | BLOCKED | 缺 CHECK U6.disabled.double.brightness.false.false |
| U6/check:U6.disabled.pinch.brightness.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.false.false |
| U6/check:U6.disabled.double.brightness.false.true | BLOCKED | 缺 CHECK U6.disabled.double.brightness.false.true |
| U6/check:U6.disabled.pinch.brightness.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.false.true |
| U6/check:U6.disabled.double.brightness.true.false | BLOCKED | 缺 CHECK U6.disabled.double.brightness.true.false |
| U6/check:U6.disabled.pinch.brightness.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.true.false |
| U6/check:U6.disabled.double.brightness.true.true | BLOCKED | 缺 CHECK U6.disabled.double.brightness.true.true |
| U6/check:U6.disabled.pinch.brightness.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.brightness.true.true |
| U6/check:U6.disabled.double.seek.false.false | BLOCKED | 缺 CHECK U6.disabled.double.seek.false.false |
| U6/check:U6.disabled.pinch.seek.false.false | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.false.false |
| U6/check:U6.disabled.double.seek.false.true | BLOCKED | 缺 CHECK U6.disabled.double.seek.false.true |
| U6/check:U6.disabled.pinch.seek.false.true | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.false.true |
| U6/check:U6.disabled.double.seek.true.false | BLOCKED | 缺 CHECK U6.disabled.double.seek.true.false |
| U6/check:U6.disabled.pinch.seek.true.false | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.true.false |
| U6/check:U6.disabled.double.seek.true.true | BLOCKED | 缺 CHECK U6.disabled.double.seek.true.true |
| U6/check:U6.disabled.pinch.seek.true.true | BLOCKED | 缺 CHECK U6.disabled.pinch.seek.true.true |
| U6/check:U6.dvr.false | BLOCKED | 缺 CHECK U6.dvr.false |
| U6/check:U6.dvr.true | BLOCKED | 缺 CHECK U6.dvr.true |
| U7/check:U7.like.render | BLOCKED | 缺 CHECK U7.like.render |
| U7/check:U7.like.click | BLOCKED | 缺 CHECK U7.like.click |
| U7/check:U7.comment.render | BLOCKED | 缺 CHECK U7.comment.render |
| U7/check:U7.share.render | BLOCKED | 缺 CHECK U7.share.render |
| U7/check:U7.social.clicks | BLOCKED | 缺 CHECK U7.social.clicks |
| U7/check:U7.info | BLOCKED | 缺 CHECK U7.info |
| U7/check:U7.subtitle.empty | BLOCKED | 缺 CHECK U7.subtitle.empty |
| U7/check:U7.subtitle.cue | BLOCKED | 缺 CHECK U7.subtitle.cue |
| U7/check:U7.subtitle.expired | BLOCKED | 缺 CHECK U7.subtitle.expired |
| U7/check:U7.ad.countdown | BLOCKED | 缺 CHECK U7.ad.countdown |
| U7/check:U7.ad.remaining | BLOCKED | 缺 CHECK U7.ad.remaining |
| U7/check:U7.ad.click | BLOCKED | 缺 CHECK U7.ad.click |
| U7/check:U7.ad.skippable | BLOCKED | 缺 CHECK U7.ad.skippable |
| U7/check:U7.ad.skipped | BLOCKED | 缺 CHECK U7.ad.skipped |
| U7/check:C8.now | BLOCKED | 缺 CHECK C8.now |
| U7/check:U7.subtitle.start | BLOCKED | 缺 CHECK U7.subtitle.start |
| U7/check:U7.subtitle.stop | BLOCKED | 缺 CHECK U7.subtitle.stop |
| U8/check:U8.drag | BLOCKED | 缺 CHECK U8.drag |
| U8/check:U8.snap | BLOCKED | 缺 CHECK U8.snap |
| U8/check:U8.fling | BLOCKED | 缺 CHECK U8.fling |
| U8/check:U8.resize | BLOCKED | 缺 CHECK U8.resize |
| U8/check:A26.persistent | BLOCKED | 缺 CHECK A26.persistent |
| U8/check:A26.tap | BLOCKED | 缺 CHECK A26.tap |
| U8/check:A26.page | BLOCKED | 缺 CHECK A26.page |
| U8/check:A26.setRect | BLOCKED | 缺 CHECK A26.setRect |
| U8/check:A26.hide | BLOCKED | 缺 CHECK A26.hide |
| U8/check:A26.close | BLOCKED | 缺 CHECK A26.close |
| U9/check:U9.ticker.none | BLOCKED | 缺 CHECK U9.ticker.none |
| U9/check:U9.route.none | BLOCKED | 缺 CHECK U9.route.none |
| U9/check:U9.inactive.none | BLOCKED | 缺 CHECK U9.inactive.none |
| U9/check:U9.ticker.pip | BLOCKED | 缺 CHECK U9.ticker.pip |
| U9/check:U9.route.pip | BLOCKED | 缺 CHECK U9.route.pip |
| U9/check:U9.inactive.pip | BLOCKED | 缺 CHECK U9.inactive.pip |
| U9/check:U9.ticker.mini | BLOCKED | 缺 CHECK U9.ticker.mini |
| U9/check:U9.route.mini | BLOCKED | 缺 CHECK U9.route.mini |
| U9/check:U9.inactive.mini | BLOCKED | 缺 CHECK U9.inactive.mini |
| U9/check:U9.native.ticker | BLOCKED | 缺 CHECK U9.native.ticker |
| U9/check:U9.native.route | BLOCKED | 缺 CHECK U9.native.route |
| U9/check:U9.native.lifecycle.none | BLOCKED | 缺 CHECK U9.native.lifecycle.none |
| U9/check:U9.native.lifecycle.pip | BLOCKED | 缺 CHECK U9.native.lifecycle.pip |
| U9/check:U9.native.lifecycle.mini | BLOCKED | 缺 CHECK U9.native.lifecycle.mini |
| F1/check:F1 | BLOCKED | 缺 CHECK F1 |
| F1/record:LIFECYCLE | BLOCKED | LIFECYCLE 样本=0/1 files=*; 缺事件记录 |
| F2/record:VIDEO | BLOCKED | VIDEO 样本=0/3 files=rerun-live-*-behind.json; 缺事件记录 |
| F2/record:VIDEO | BLOCKED | VIDEO 样本=0/3 files=rerun-live-*-backedge.json; 缺事件记录 |
| F2/duration:2 | BLOCKED | 缺 LIVE_DURATION step0/2000 |
| F3/check:F3.abrBackToBack | BLOCKED | 缺 CHECK F3.abrBackToBack |
| F3/hls:1 | BLOCKED | 缺 HLS_RESULT |
| F3/check:CONTRACT.defaults | BLOCKED | 缺 CHECK CONTRACT.defaults |
| F4/check:F4.adResume | BLOCKED | 缺 CHECK F4.adResume |
| F4/check:A24.commit | BLOCKED | 缺 CHECK A24.commit |
| F4/check:A27.rolls | BLOCKED | 缺 CHECK A27.rolls |
| F4/check:CONTRACT.error.nonterminal | BLOCKED | 缺 CHECK CONTRACT.error.nonterminal |
| F4/check:CONTRACT.error.terminal | BLOCKED | 缺 CHECK CONTRACT.error.terminal |
| F4/check:CONTRACT.error.overlay.nonterminal | BLOCKED | 缺 CHECK CONTRACT.error.overlay.nonterminal |
| F4/check:CONTRACT.error.overlay.terminal | BLOCKED | 缺 CHECK CONTRACT.error.overlay.terminal |
| F5/check:F5.pipWake | BLOCKED | 缺 CHECK F5.pipWake |
| F5/check:A15.miniHostToPip | BLOCKED | 缺 CHECK A15.miniHostToPip |
| F5/check:A15.pipExpanded | BLOCKED | 缺 CHECK A15.pipExpanded |
| F6/keepalive_wake:0 | BLOCKED | keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联 |
| F6/log:S2 | BLOCKED | keepalive-core.log: 缺完成标记 |
| F6/log:S3 | BLOCKED | keepalive-core.log: 缺完成标记 |
| F6/check:S6.publicFallback | BLOCKED | 缺 CHECK S6.publicFallback |
| F6/log:S13 | BLOCKED | keepalive-core.log: 缺完成标记 |
| F6/log:S17 | BLOCKED | keepalive-core.log: 缺完成标记 |
| F7/check:F7.false.ended.endCount | BLOCKED | 缺 CHECK F7.false.ended.endCount |
| F7/check:F7.false.ended.summary | BLOCKED | 缺 CHECK F7.false.ended.summary |
| F7/check:F7.false.ended.truncated | BLOCKED | 缺 CHECK F7.false.ended.truncated |
| F7/check:F7.false.ended.firstFrameCount | BLOCKED | 缺 CHECK F7.false.ended.firstFrameCount |
| F7/check:F7.false.ended.firstFrame | BLOCKED | 缺 CHECK F7.false.ended.firstFrame |
| F7/check:F7.false.stopped.endCount | BLOCKED | 缺 CHECK F7.false.stopped.endCount |
| F7/check:F7.false.stopped.summary | BLOCKED | 缺 CHECK F7.false.stopped.summary |
| F7/check:F7.false.stopped.truncated | BLOCKED | 缺 CHECK F7.false.stopped.truncated |
| F7/check:F7.false.stopped.firstFrameCount | BLOCKED | 缺 CHECK F7.false.stopped.firstFrameCount |
| F7/check:F7.false.stopped.firstFrame | BLOCKED | 缺 CHECK F7.false.stopped.firstFrame |
| F7/check:F7.false.failed.endCount | BLOCKED | 缺 CHECK F7.false.failed.endCount |
| F7/check:F7.false.failed.summary | BLOCKED | 缺 CHECK F7.false.failed.summary |
| F7/check:F7.false.failed.truncated | BLOCKED | 缺 CHECK F7.false.failed.truncated |
| F7/check:F7.false.failed.firstFrameCount | BLOCKED | 缺 CHECK F7.false.failed.firstFrameCount |
| F7/check:F7.false.failed.firstFrame | BLOCKED | 缺 CHECK F7.false.failed.firstFrame |
| F7/check:F7.false.abandoned.endCount | BLOCKED | 缺 CHECK F7.false.abandoned.endCount |
| F7/check:F7.false.abandoned.summary | BLOCKED | 缺 CHECK F7.false.abandoned.summary |
| F7/check:F7.false.abandoned.truncated | BLOCKED | 缺 CHECK F7.false.abandoned.truncated |
| F7/check:F7.false.truncated.endCount | BLOCKED | 缺 CHECK F7.false.truncated.endCount |
| F7/check:F7.false.truncated.summary | BLOCKED | 缺 CHECK F7.false.truncated.summary |
| F7/check:F7.false.truncated.truncated | BLOCKED | 缺 CHECK F7.false.truncated.truncated |
| F7/check:F7.false.truncated.firstFrameCount | BLOCKED | 缺 CHECK F7.false.truncated.firstFrameCount |
| F7/check:F7.false.truncated.firstFrame | BLOCKED | 缺 CHECK F7.false.truncated.firstFrame |
| F7/check:F7.false.disabled.endCount | BLOCKED | 缺 CHECK F7.false.disabled.endCount |
| F7/check:F7.false.disabled.summary | BLOCKED | 缺 CHECK F7.false.disabled.summary |
| F7/check:F7.false.disabled.truncated | BLOCKED | 缺 CHECK F7.false.disabled.truncated |
| F7/check:F7.false.disabled.firstFrameCount | BLOCKED | 缺 CHECK F7.false.disabled.firstFrameCount |
| F7/check:F7.false.disabled.firstFrame | BLOCKED | 缺 CHECK F7.false.disabled.firstFrame |
| F7/check:F7.true.ended.endCount | BLOCKED | 缺 CHECK F7.true.ended.endCount |
| F7/check:F7.true.ended.summary | BLOCKED | 缺 CHECK F7.true.ended.summary |
| F7/check:F7.true.ended.truncated | BLOCKED | 缺 CHECK F7.true.ended.truncated |
| F7/check:F7.true.ended.firstFrameCount | BLOCKED | 缺 CHECK F7.true.ended.firstFrameCount |
| F7/check:F7.true.ended.firstFrame | BLOCKED | 缺 CHECK F7.true.ended.firstFrame |
| F7/check:F7.true.stopped.endCount | BLOCKED | 缺 CHECK F7.true.stopped.endCount |
| F7/check:F7.true.stopped.summary | BLOCKED | 缺 CHECK F7.true.stopped.summary |
| F7/check:F7.true.stopped.truncated | BLOCKED | 缺 CHECK F7.true.stopped.truncated |
| F7/check:F7.true.stopped.firstFrameCount | BLOCKED | 缺 CHECK F7.true.stopped.firstFrameCount |
| F7/check:F7.true.stopped.firstFrame | BLOCKED | 缺 CHECK F7.true.stopped.firstFrame |
| F7/check:F7.true.failed.endCount | BLOCKED | 缺 CHECK F7.true.failed.endCount |
| F7/check:F7.true.failed.summary | BLOCKED | 缺 CHECK F7.true.failed.summary |
| F7/check:F7.true.failed.truncated | BLOCKED | 缺 CHECK F7.true.failed.truncated |
| F7/check:F7.true.failed.firstFrameCount | BLOCKED | 缺 CHECK F7.true.failed.firstFrameCount |
| F7/check:F7.true.failed.firstFrame | BLOCKED | 缺 CHECK F7.true.failed.firstFrame |
| F7/check:F7.true.abandoned.endCount | BLOCKED | 缺 CHECK F7.true.abandoned.endCount |
| F7/check:F7.true.abandoned.summary | BLOCKED | 缺 CHECK F7.true.abandoned.summary |
| F7/check:F7.true.abandoned.truncated | BLOCKED | 缺 CHECK F7.true.abandoned.truncated |
| F7/check:F7.true.truncated.endCount | BLOCKED | 缺 CHECK F7.true.truncated.endCount |
| F7/check:F7.true.truncated.summary | BLOCKED | 缺 CHECK F7.true.truncated.summary |
| F7/check:F7.true.truncated.truncated | BLOCKED | 缺 CHECK F7.true.truncated.truncated |
| F7/check:F7.true.truncated.firstFrameCount | BLOCKED | 缺 CHECK F7.true.truncated.firstFrameCount |
| F7/check:F7.true.truncated.firstFrame | BLOCKED | 缺 CHECK F7.true.truncated.firstFrame |
| F7/check:F7.true.disabled.endCount | BLOCKED | 缺 CHECK F7.true.disabled.endCount |
| F7/check:F7.true.disabled.summary | BLOCKED | 缺 CHECK F7.true.disabled.summary |
| F7/check:F7.true.disabled.truncated | BLOCKED | 缺 CHECK F7.true.disabled.truncated |
| F7/check:F7.true.disabled.firstFrameCount | BLOCKED | 缺 CHECK F7.true.disabled.firstFrameCount |
| F7/check:F7.true.disabled.firstFrame | BLOCKED | 缺 CHECK F7.true.disabled.firstFrame |
| F7/check:F7.heartbeat | BLOCKED | 缺 CHECK F7.heartbeat |
| F7/check:F7.nativeFirstFrame | BLOCKED | 缺 CHECK F7.nativeFirstFrame |
| F7/check:F7.nativeSample | BLOCKED | 缺 CHECK F7.nativeSample |
| F7/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-ended.json; 缺事件记录 |
| F7/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-stopped.json; 缺事件记录 |
| F7/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-failed.json; 缺事件记录 |
| F7/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-abandoned.json; 缺事件记录 |
| F7/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-truncated.json; 缺事件记录 |
| F7/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch17-qoe-stall-release.json; 缺事件记录 |
| F8/log:V5 | BLOCKED | he-recovery.log: 缺完成标记 |
| F8/log:V6 | BLOCKED | he-recovery.log: 缺完成标记 |
| F8/log:V7 | BLOCKED | he-recovery.log: 缺完成标记 |
| F8/log:V8 | BLOCKED | he-recovery.log: 缺完成标记 |
| F8/check:CONTRACT.replay.retry | BLOCKED | 缺 CHECK CONTRACT.replay.retry |
| F8/check:CONTRACT.replay.edge | BLOCKED | 缺 CHECK CONTRACT.replay.edge |
| F9/check:F9.nativeAudio | BLOCKED | 缺 CHECK F9.nativeAudio |
| F9/check:F9.native.ui | BLOCKED | 缺 CHECK F9.native.ui |
| F9/check:F9.native.decoder | BLOCKED | 缺 CHECK F9.native.decoder |
| F9/check:F9.native.comparison | BLOCKED | 缺 CHECK F9.native.comparison |
| F10/check:A30.mode.vtt | BLOCKED | 缺 CHECK A30.mode.vtt |
| F10/check:A30.clear.vtt | BLOCKED | 缺 CHECK A30.clear.vtt |
| F10/check:A30.mode.extract | BLOCKED | 缺 CHECK A30.mode.extract |
| F10/check:A30.clear.extract | BLOCKED | 缺 CHECK A30.clear.extract |
| F10/check:A30.mode.fallback | BLOCKED | 缺 CHECK A30.mode.fallback |
| F10/check:A30.clear.fallback | BLOCKED | 缺 CHECK A30.clear.fallback |
| F10/check:A30.mode.offline | BLOCKED | 缺 CHECK A30.mode.offline |
| F10/check:A30.clear.offline | BLOCKED | 缺 CHECK A30.clear.offline |
| F10/check:A30.mode.blocked | BLOCKED | 缺 CHECK A30.mode.blocked |
| F10/check:A30.clear.blocked | BLOCKED | 缺 CHECK A30.clear.blocked |
| F10/check:A30.cancelResult | BLOCKED | 缺 CHECK A30.cancelResult |
| F10/check:A30.staleResult | BLOCKED | 缺 CHECK A30.staleResult |
| F11/check:F11.ass | BLOCKED | 缺 CHECK F11.ass |
| F11/check:F11.movtext | BLOCKED | 缺 CHECK F11.movtext |
| F11/check:F11.srt | BLOCKED | 缺 CHECK F11.srt |
| F11/check:F11.vtt | BLOCKED | 缺 CHECK F11.vtt |
| F12/check:F12.audioCounters | BLOCKED | 缺 CHECK F12.audioCounters |
| F12/check:F12.native.background | BLOCKED | 缺 CHECK F12.native.background |
| F12/check:F12.power.external | BLOCKED | 缺 CHECK F12.power.external |
| F13/check:F13.resources.20 | BLOCKED | 缺 CHECK F13.resources.20 |
| F13/check:F13.resources.40 | BLOCKED | 缺 CHECK F13.resources.40 |
| F13/check:F13.resources.60 | BLOCKED | 缺 CHECK F13.resources.60 |
| F13/check:F13.resources.80 | BLOCKED | 缺 CHECK F13.resources.80 |
| F13/check:F13.resources.100 | BLOCKED | 缺 CHECK F13.resources.100 |
| F13/check:F13.resources.disposed | BLOCKED | 缺 CHECK F13.resources.disposed |
| F13/check:F13.disposeFrames | BLOCKED | 缺 CHECK F13.disposeFrames |
| F13/check:A29.poolReclaimed | BLOCKED | 缺 CHECK A29.poolReclaimed |
| F13/check:F13.bounded.40 | BLOCKED | 缺 CHECK F13.bounded.40 |
| F13/check:F13.bounded.60 | BLOCKED | 缺 CHECK F13.bounded.60 |
| F13/check:F13.bounded.80 | BLOCKED | 缺 CHECK F13.bounded.80 |
| F13/check:F13.bounded.100 | BLOCKED | 缺 CHECK F13.bounded.100 |
| F13/check:F13.bounded.disposed | BLOCKED | 缺 CHECK F13.bounded.disposed |
| F13/check:F13.native.isolation | BLOCKED | 缺 CHECK F13.native.isolation |
| F14/check:F14.coverage1 | BLOCKED | 缺 CHECK F14.coverage1：原生泵创建/销毁/稳定性/错误隔离的结构化 CHECK |
| F14/check:F14.disposed.off | BLOCKED | 缺 CHECK F14.disposed.off |
| F14/check:F14.disposed.recovery | BLOCKED | 缺 CHECK F14.disposed.recovery |
| F14/check:F14.disposed.precise | BLOCKED | 缺 CHECK F14.disposed.precise |
| F14/check:F14.disposed.reporterOff | BLOCKED | 缺 CHECK F14.disposed.reporterOff |
| F14/check:F14.disposed.qoe | BLOCKED | 缺 CHECK F14.disposed.qoe |
| F14/check:F14.native.teardown | BLOCKED | 缺 CHECK F14.native.teardown |
| F16/log:V12 | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| F16/log:V12b | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| F16/log:V13a | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| F16/log:V13b | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| F16/log:V14 | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| N1/check:N1.network | BLOCKED | 缺 CHECK N1.network |
| N1/check:N4.whepOptions | BLOCKED | 缺 CHECK N4.whepOptions |
| N2/check:N2.derived | BLOCKED | 缺 CHECK N2.derived |
| N2/check:N2.watchoff | BLOCKED | 缺 CHECK N2.watchoff |
| N3/check:N3.defaultLive | BLOCKED | 缺 CHECK N3.defaultLive |
| N4/check:N4.applied | BLOCKED | 缺 CHECK N4.applied |
| N4/check:N4.restore | BLOCKED | 缺 CHECK N4.restore |
| N4/check:N4.whepOptions | BLOCKED | 缺 CHECK N4.whepOptions |
| N5/check:N5.restart.off | BLOCKED | 缺 CHECK N5.restart.off |
| N5/check:N5.restart.recovery | BLOCKED | 缺 CHECK N5.restart.recovery |
| N5/check:N5.restart.precise | BLOCKED | 缺 CHECK N5.restart.precise |
| N5/check:N5.restart.reporterOff | BLOCKED | 缺 CHECK N5.restart.reporterOff |
| N5/check:N5.restart.qoe | BLOCKED | 缺 CHECK N5.restart.qoe |
| N5/check:N5.endFile | BLOCKED | 缺 CHECK N5.endFile |
| N6/check:N6.clear | BLOCKED | 缺 CHECK N6.clear |
| N6/check:N6.giveup | BLOCKED | 缺 CHECK N6.giveup |
| N6/check:CONTRACT.error.terminal | BLOCKED | 缺 CHECK CONTRACT.error.terminal |
| N7/duration:0 | BLOCKED | 缺 LIVE_DURATION step0/2000 |
| N8/check:N8.accept | BLOCKED | 缺 CHECK N8.accept |
| N8/check:N8.reject | BLOCKED | 缺 CHECK N8.reject |
| N8/check:N8.disposed | BLOCKED | 缺 CHECK N8.disposed |
| N8/check:N8.playlistRejected | BLOCKED | 缺 CHECK N8.playlistRejected |
| N8/check:N8.superseded | BLOCKED | 缺 CHECK N8.superseded |
| N8/check:CONTRACT.rejectedOpen | BLOCKED | 缺 CHECK CONTRACT.rejectedOpen |
| N9/check:A18.pinned.enter | BLOCKED | 缺 CHECK A18.pinned.enter |
| N9/check:A18.pinned.expand | BLOCKED | 缺 CHECK A18.pinned.expand |
| N9/check:A18.pinned.close | BLOCKED | 缺 CHECK A18.pinned.close |
| N9/check:N9.transitions | BLOCKED | 缺 CHECK N9.transitions |
| N10/log:V12 | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| N10/log:V12b | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| N10/log:V13a | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| N10/log:V13b | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| N10/log:V14 | BLOCKED | rerun-batch11-review.log: 缺完成标记 |
| N11/log:Q13A | BLOCKED | rerun-batch10-mute.log: 缺完成标记 |
| N11/log:Q13B | BLOCKED | rerun-batch10-mute.log: 缺完成标记 |
| N11/log:Q13C | BLOCKED | rerun-batch10-mute.log: 缺完成标记 |
| N12/log:V1 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N12/log:V2 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N12/log:V3 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N12/log:V4 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N12/check:N12.openReset | BLOCKED | 缺 CHECK N12.openReset |
| N12/check:N12.freshRestart | BLOCKED | 缺 CHECK N12.freshRestart |
| N12/check:N12.native.isolation | BLOCKED | 缺 CHECK N12.native.isolation |
| N13/log:V1 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N13/log:V2 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N13/log:V3 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N13/log:V4 | BLOCKED | he-firstframe.log: 缺完成标记 |
| N13/check:N13.clients.off | BLOCKED | 缺 CHECK N13.clients.off |
| N13/check:N13.clients.recovery | BLOCKED | 缺 CHECK N13.clients.recovery |
| N13/check:N13.clients.precise | BLOCKED | 缺 CHECK N13.clients.precise |
| N13/check:N13.clients.reporterOff | BLOCKED | 缺 CHECK N13.clients.reporterOff |
| N13/check:N13.clients.qoe | BLOCKED | 缺 CHECK N13.clients.qoe |
| N13/check:N13.beforeOpen.off | BLOCKED | 缺 CHECK N13.beforeOpen.off |
| N13/check:N13.beforeOpen.recovery | BLOCKED | 缺 CHECK N13.beforeOpen.recovery |
| N13/check:N13.beforeOpen.precise | BLOCKED | 缺 CHECK N13.beforeOpen.precise |
| N13/check:N13.beforeOpen.reporterOff | BLOCKED | 缺 CHECK N13.beforeOpen.reporterOff |
| N13/check:N13.beforeOpen.qoe | BLOCKED | 缺 CHECK N13.beforeOpen.qoe |
| N13/check:N13.video.false | BLOCKED | 缺 CHECK N13.video.false |
| N13/check:N13.video.true | BLOCKED | 缺 CHECK N13.video.true |
| N14/check:rerun-batch16-engine.fitRebuild | BLOCKED | 缺 CHECK rerun-batch16-engine.fitRebuild |
| N14/check:rerun-batch16-cutover.fitRebuild | BLOCKED | 缺 CHECK rerun-batch16-cutover.fitRebuild |
| N15/check:N15.cover | BLOCKED | 缺 CHECK N15.cover |
| N15/check:N15.fade | BLOCKED | 缺 CHECK N15.fade |
| N15/check:N15.recover | BLOCKED | 缺 CHECK N15.recover |
| N15/check:N15.noSize | BLOCKED | 缺 CHECK N15.noSize |
| N15/check:N15.feedCover | BLOCKED | 缺 CHECK N15.feedCover |
| N15/check:N15.feedFade | BLOCKED | 缺 CHECK N15.feedFade |
| N15/check:N15.feedRecover | BLOCKED | 缺 CHECK N15.feedRecover |
| N15/check:N15.renderFade | BLOCKED | 缺 CHECK N15.renderFade |
| N15/check:N15.renderFadeDone | BLOCKED | 缺 CHECK N15.renderFadeDone |
| N15/check:F7.nativeFirstFrame | BLOCKED | 缺 CHECK F7.nativeFirstFrame |
| N16/check:N16.variants.false.false | BLOCKED | 缺 CHECK N16.variants.false.false |
| N16/check:N16.variants.false.true | BLOCKED | 缺 CHECK N16.variants.false.true |
| N16/check:N16.variants.true.false | BLOCKED | 缺 CHECK N16.variants.true.false |
| N16/check:N16.variants.true.true | BLOCKED | 缺 CHECK N16.variants.true.true |
| N16/check:C10.buffering | BLOCKED | 缺 CHECK C10.buffering |
| N16/check:U2.mounted.minimal | BLOCKED | 缺 CHECK U2.mounted.minimal |
| N17/check:N17.lazy | BLOCKED | 缺 CHECK N17.lazy |
| N17/check:N17.owned | BLOCKED | 缺 CHECK N17.owned |
| N17/check:N17.same | BLOCKED | 缺 CHECK N17.same |
| N17/check:N17.alternatives | BLOCKED | 缺 CHECK N17.alternatives |
| N17/check:N17.null | BLOCKED | 缺 CHECK N17.null |
| N17/check:N17.options | BLOCKED | 缺 CHECK N17.options |
| N17/check:N17.error | BLOCKED | 缺 CHECK N17.error |
| N17/check:N17.dispose | BLOCKED | 缺 CHECK N17.dispose |
| N19/check:N19.failover | BLOCKED | 缺 CHECK N19.failover |
| N19/check:N6.clear | BLOCKED | 缺 CHECK N6.clear |
| N19/check:N6.giveup | BLOCKED | 缺 CHECK N6.giveup |
| N19/log:V5 | BLOCKED | he-recovery.log: 缺完成标记 |
| N19/log:V6 | BLOCKED | he-recovery.log: 缺完成标记 |
| N19/log:V7 | BLOCKED | he-recovery.log: 缺完成标记 |
| N19/log:V8 | BLOCKED | he-recovery.log: 缺完成标记 |
| N19/check:CONTRACT.replay.retry | BLOCKED | 缺 CHECK CONTRACT.replay.retry |
| N20/keepalive_wake:0 | BLOCKED | keepalive-core.log: S1 raw=[]; H42 grace/elapsed 语义待决，需 RESTART/size 与原生解码事件关联 |
| N20/log:S2 | BLOCKED | keepalive-core.log: 缺完成标记 |
| N20/log:S3 | BLOCKED | keepalive-core.log: 缺完成标记 |
| N20/check:S6.publicFallback | BLOCKED | 缺 CHECK S6.publicFallback |
| N20/log:S13 | BLOCKED | keepalive-core.log: 缺完成标记 |
| N20/log:S17 | BLOCKED | keepalive-core.log: 缺完成标记 |
| N21/check:N21.staged | BLOCKED | 缺 CHECK N21.staged |
| N21/check:N21.guard.windows | BLOCKED | 缺 CHECK N21.guard.windows |
| N21/check:N21.guard.android | BLOCKED | 缺 CHECK N21.guard.android |
| N23/check:F7.false.ended.endCount | BLOCKED | 缺 CHECK F7.false.ended.endCount |
| N23/check:F7.false.ended.summary | BLOCKED | 缺 CHECK F7.false.ended.summary |
| N23/check:F7.false.ended.truncated | BLOCKED | 缺 CHECK F7.false.ended.truncated |
| N23/check:F7.false.ended.firstFrameCount | BLOCKED | 缺 CHECK F7.false.ended.firstFrameCount |
| N23/check:F7.false.ended.firstFrame | BLOCKED | 缺 CHECK F7.false.ended.firstFrame |
| N23/check:F7.false.stopped.endCount | BLOCKED | 缺 CHECK F7.false.stopped.endCount |
| N23/check:F7.false.stopped.summary | BLOCKED | 缺 CHECK F7.false.stopped.summary |
| N23/check:F7.false.stopped.truncated | BLOCKED | 缺 CHECK F7.false.stopped.truncated |
| N23/check:F7.false.stopped.firstFrameCount | BLOCKED | 缺 CHECK F7.false.stopped.firstFrameCount |
| N23/check:F7.false.stopped.firstFrame | BLOCKED | 缺 CHECK F7.false.stopped.firstFrame |
| N23/check:F7.false.failed.endCount | BLOCKED | 缺 CHECK F7.false.failed.endCount |
| N23/check:F7.false.failed.summary | BLOCKED | 缺 CHECK F7.false.failed.summary |
| N23/check:F7.false.failed.truncated | BLOCKED | 缺 CHECK F7.false.failed.truncated |
| N23/check:F7.false.failed.firstFrameCount | BLOCKED | 缺 CHECK F7.false.failed.firstFrameCount |
| N23/check:F7.false.failed.firstFrame | BLOCKED | 缺 CHECK F7.false.failed.firstFrame |
| N23/check:F7.false.abandoned.endCount | BLOCKED | 缺 CHECK F7.false.abandoned.endCount |
| N23/check:F7.false.abandoned.summary | BLOCKED | 缺 CHECK F7.false.abandoned.summary |
| N23/check:F7.false.abandoned.truncated | BLOCKED | 缺 CHECK F7.false.abandoned.truncated |
| N23/check:F7.false.truncated.endCount | BLOCKED | 缺 CHECK F7.false.truncated.endCount |
| N23/check:F7.false.truncated.summary | BLOCKED | 缺 CHECK F7.false.truncated.summary |
| N23/check:F7.false.truncated.truncated | BLOCKED | 缺 CHECK F7.false.truncated.truncated |
| N23/check:F7.false.truncated.firstFrameCount | BLOCKED | 缺 CHECK F7.false.truncated.firstFrameCount |
| N23/check:F7.false.truncated.firstFrame | BLOCKED | 缺 CHECK F7.false.truncated.firstFrame |
| N23/check:F7.false.disabled.endCount | BLOCKED | 缺 CHECK F7.false.disabled.endCount |
| N23/check:F7.false.disabled.summary | BLOCKED | 缺 CHECK F7.false.disabled.summary |
| N23/check:F7.false.disabled.truncated | BLOCKED | 缺 CHECK F7.false.disabled.truncated |
| N23/check:F7.false.disabled.firstFrameCount | BLOCKED | 缺 CHECK F7.false.disabled.firstFrameCount |
| N23/check:F7.false.disabled.firstFrame | BLOCKED | 缺 CHECK F7.false.disabled.firstFrame |
| N23/check:F7.true.ended.endCount | BLOCKED | 缺 CHECK F7.true.ended.endCount |
| N23/check:F7.true.ended.summary | BLOCKED | 缺 CHECK F7.true.ended.summary |
| N23/check:F7.true.ended.truncated | BLOCKED | 缺 CHECK F7.true.ended.truncated |
| N23/check:F7.true.ended.firstFrameCount | BLOCKED | 缺 CHECK F7.true.ended.firstFrameCount |
| N23/check:F7.true.ended.firstFrame | BLOCKED | 缺 CHECK F7.true.ended.firstFrame |
| N23/check:F7.true.stopped.endCount | BLOCKED | 缺 CHECK F7.true.stopped.endCount |
| N23/check:F7.true.stopped.summary | BLOCKED | 缺 CHECK F7.true.stopped.summary |
| N23/check:F7.true.stopped.truncated | BLOCKED | 缺 CHECK F7.true.stopped.truncated |
| N23/check:F7.true.stopped.firstFrameCount | BLOCKED | 缺 CHECK F7.true.stopped.firstFrameCount |
| N23/check:F7.true.stopped.firstFrame | BLOCKED | 缺 CHECK F7.true.stopped.firstFrame |
| N23/check:F7.true.failed.endCount | BLOCKED | 缺 CHECK F7.true.failed.endCount |
| N23/check:F7.true.failed.summary | BLOCKED | 缺 CHECK F7.true.failed.summary |
| N23/check:F7.true.failed.truncated | BLOCKED | 缺 CHECK F7.true.failed.truncated |
| N23/check:F7.true.failed.firstFrameCount | BLOCKED | 缺 CHECK F7.true.failed.firstFrameCount |
| N23/check:F7.true.failed.firstFrame | BLOCKED | 缺 CHECK F7.true.failed.firstFrame |
| N23/check:F7.true.abandoned.endCount | BLOCKED | 缺 CHECK F7.true.abandoned.endCount |
| N23/check:F7.true.abandoned.summary | BLOCKED | 缺 CHECK F7.true.abandoned.summary |
| N23/check:F7.true.abandoned.truncated | BLOCKED | 缺 CHECK F7.true.abandoned.truncated |
| N23/check:F7.true.truncated.endCount | BLOCKED | 缺 CHECK F7.true.truncated.endCount |
| N23/check:F7.true.truncated.summary | BLOCKED | 缺 CHECK F7.true.truncated.summary |
| N23/check:F7.true.truncated.truncated | BLOCKED | 缺 CHECK F7.true.truncated.truncated |
| N23/check:F7.true.truncated.firstFrameCount | BLOCKED | 缺 CHECK F7.true.truncated.firstFrameCount |
| N23/check:F7.true.truncated.firstFrame | BLOCKED | 缺 CHECK F7.true.truncated.firstFrame |
| N23/check:F7.true.disabled.endCount | BLOCKED | 缺 CHECK F7.true.disabled.endCount |
| N23/check:F7.true.disabled.summary | BLOCKED | 缺 CHECK F7.true.disabled.summary |
| N23/check:F7.true.disabled.truncated | BLOCKED | 缺 CHECK F7.true.disabled.truncated |
| N23/check:F7.true.disabled.firstFrameCount | BLOCKED | 缺 CHECK F7.true.disabled.firstFrameCount |
| N23/check:F7.true.disabled.firstFrame | BLOCKED | 缺 CHECK F7.true.disabled.firstFrame |
| N23/check:F7.heartbeat | BLOCKED | 缺 CHECK F7.heartbeat |
| N23/check:F7.nativeFirstFrame | BLOCKED | 缺 CHECK F7.nativeFirstFrame |
| N23/check:F7.nativeSample | BLOCKED | 缺 CHECK F7.nativeSample |
| N23/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-ended.json; 缺事件记录 |
| N23/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-stopped.json; 缺事件记录 |
| N23/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-failed.json; 缺事件记录 |
| N23/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-abandoned.json; 缺事件记录 |
| N23/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch15-qoe-truncated.json; 缺事件记录 |
| N23/record:REPORT | BLOCKED | REPORT 样本=0/1 files=*batch17-qoe-stall-release.json; 缺事件记录 |
| N23/check:N23.policy.stream.false | BLOCKED | 缺 CHECK N23.policy.stream.false |
| N23/check:N23.policy.stream.true | BLOCKED | 缺 CHECK N23.policy.stream.true |
| N23/check:N23.policy.file.false | BLOCKED | 缺 CHECK N23.policy.file.false |
| N23/check:N23.policy.file.true | BLOCKED | 缺 CHECK N23.policy.file.true |
| N23/check:N23.policy.ffmpeg.false | BLOCKED | 缺 CHECK N23.policy.ffmpeg.false |
| N23/check:N23.policy.ffmpeg.true | BLOCKED | 缺 CHECK N23.policy.ffmpeg.true |
| N23/check:N23.policy.vd.false | BLOCKED | 缺 CHECK N23.policy.vd.false |
| N23/check:N23.policy.vd.true | BLOCKED | 缺 CHECK N23.policy.vd.true |
| N23/check:N23.policy.ad.false | BLOCKED | 缺 CHECK N23.policy.ad.false |
| N23/check:N23.policy.ad.true | BLOCKED | 缺 CHECK N23.policy.ad.true |
| N23/check:N23.policy.cplayer.false | BLOCKED | 缺 CHECK N23.policy.cplayer.false |
| N23/check:N23.policy.cplayer.true | BLOCKED | 缺 CHECK N23.policy.cplayer.true |
| N23/check:N23.policy.other.false | BLOCKED | 缺 CHECK N23.policy.other.false |
| N23/check:N23.policy.other.true | BLOCKED | 缺 CHECK N23.policy.other.true |
| N23/check:N23.custom | BLOCKED | 缺 CHECK N23.custom |
| N23/check:N23.error.stream.false | BLOCKED | 缺 CHECK N23.error.stream.false |
| N23/check:N23.error.stream.true | BLOCKED | 缺 CHECK N23.error.stream.true |
| N23/check:N23.error.file.false | BLOCKED | 缺 CHECK N23.error.file.false |
| N23/check:N23.error.file.true | BLOCKED | 缺 CHECK N23.error.file.true |
| N23/check:N23.error.ffmpeg.false | BLOCKED | 缺 CHECK N23.error.ffmpeg.false |
| N23/check:N23.error.ffmpeg.true | BLOCKED | 缺 CHECK N23.error.ffmpeg.true |
| N23/check:N23.error.vd.false | BLOCKED | 缺 CHECK N23.error.vd.false |
| N23/check:N23.error.vd.true | BLOCKED | 缺 CHECK N23.error.vd.true |
| N23/check:N23.error.ad.false | BLOCKED | 缺 CHECK N23.error.ad.false |
| N23/check:N23.error.ad.true | BLOCKED | 缺 CHECK N23.error.ad.true |
| N23/check:N23.error.cplayer.false | BLOCKED | 缺 CHECK N23.error.cplayer.false |
| N23/check:N23.error.cplayer.true | BLOCKED | 缺 CHECK N23.error.cplayer.true |
| N23/check:N23.error.other.false | BLOCKED | 缺 CHECK N23.error.other.false |
| N23/check:N23.error.other.true | BLOCKED | 缺 CHECK N23.error.other.true |
| N23/check:CONTRACT.error.nonterminal | BLOCKED | 缺 CHECK CONTRACT.error.nonterminal |

Gap / CP0 扩展子项（不改变上方 v1 135 编号台账；完整数字见独立批次 JSON）：

| 批次 | case | 结论 | 原因 |
|---|---|---|---|
| cp2-v9 | CP2.v9.V9.0 | PASS |  |
| cp2-v9 | CP2.v9.V9.1 | PASS |  |
| cp2-v9 | CP2.v9.V9.2 | PASS |  |
| cp2-v9 | CP2.v9.V9.3 | PASS |  |
| cp2-v9 | CP2.v9.V9.4 | PASS |  |

范围：v1 135 编号；gap 扩展按子项独立呈现，不能推定完整编号通过。
