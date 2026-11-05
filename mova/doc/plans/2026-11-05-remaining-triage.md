# CP3 剩余项离线定性

起点 `76805160`，仅在 `E:\workspaces\wt-mova-cp2fix` 自行执行。原始证据只读，未使用真机、adb、Gradle；不将离线修正当作真机 PASS。下列 run-id 的证据目录均为 `example/tool/coverage_evidence/matrix-<run-id>/`，records 下标从零开始；累计日志仅取最后一个 BEGIN 后的本命令记录。

## 1. 字幕：打包夹具缺陷，已离线修正，真机 BLOCKED 保留

- 证据：`cp3-r2-subtitles-r2-20261105-085403` 的 `cp3-r2-subtitles.json` records[9] 为 SRT 资产加载 SCRIPT_ERROR；前一尝试 `cp3-r2-subtitles-r2-20261105-085320` 同因。
- `coverage_new.dart:subtitles` 已把包内视频/字幕写入临时目录，再经原生 `sub-add` 或 MP4 内嵌 mov_text 播放；不走旧 HTTP 404 路径。SRT 文件已受 git 管理，但 pubspec 只声明 ASS/VTT 和两段视频，缺 SRT。补齐声明并移除过时的临时资产注释，无产品修改，无需引入 HTTP 服务。
- 下一次必须新 APK：逐格式取得 `F11.srt/ass/vtt/movtext` CHECK 和 `SUBTITLE_SHOT` 的 sub-text、track-list、position；四项本轮均未验收，包声明正确不能替代原生解码与人工画面复核。

## 2. headers 池预热：夹具判据错误，未证产品缺陷

- `cp3-headers-r2-20261105-085001` records[38,73,108,144,180]：pool positive/negative 都为 true；第 0 轮无 negative 回执，第 2 轮两侧回执均尚未出现。`085001` 与 `084854` 两试均 0/5。原判据在 `pool.bind` 返回即读取 ready、立刻 dispose；异步请求可迟到，甚至在真正打开前被销毁。
- `engine_pool.dart:_openBinding` 明确将 ready 定义为 open accepted；拒绝结果撤销绑定，成功接受并不代表加载/解码成功。这与公开文档一致，不能改产品 ready 含义来迎合探针。
- `MovaHeaderedHttpFetch` 用于 Dart 辅助请求（清晰度/VTT/预取）；池走 engine → mpv 原生媒体加载头。原回执中 authorized Referer/200、denied 无头/403 均出现，不能据 ready 双 true 认定头丢失。
- 修正：单引擎池挂载真实 surface，开启 preciseFirstFrame，等待 rendered+非零 duration/尺寸或错误；保留 accepted、decoded、状态和原生 path/time-pos/pause。再释放池、汇总两侧 HTTP 回执。负对照超时/错误不冒充成功，缺服务端回执仍 FAIL。
- 需要新 APK、原 5 轮正负对照复验。解码预热尚未获得有效设备验收。
- 补强解码判据：首帧 gate 允许 size/grace 兜底，故仅 rendered 仍不够；现在还要求暂停状态下真实 surface 的 screenshot 返回非空 JPEG，记录 imageBytes 与 firstFrameSignals，再认领 decoded=true。截图失败保留失败，不自动重试。此补强追加独立夹具提交；example analyze 仍 41→41（无新增），定向测试 3 PASS，matrix --check / Python 80 PASS。

## 3. 回执 14 条：12 条夹具判据错误，2 条普通引擎产品缺陷

证据 `cp3-r2-receipt-r2-20261105-090006`，三个独立命令只统计各自最后 BEGIN 后的 CHECK（日志含前命令累计记录，不能重复计数）：

|命令文件后缀|records|归属|差异|定性|
|---|---|---|---|---|
|cp3-r2-basic.json|39,44,49,59,64,68|普通引擎 116100005|Seeked position|独立 progress 流的最后读数 3394/5000/10000 等与事件目标 5000/10000/15000/10000/8000/0 不相等，不是 MovaState 字段差异|
|cp3-r2-basic-cutover.json|207,212,217,227,232,236|cutover 代理|Seeked position|同上；不能据此认定 H77 state/events 同序列修复失效|
|cp3-r2-abr.json|349|普通引擎 237005018|Auto 载荷 vs state 360p|产品异步投递竞态，探测已更新 Auto，但事件收到前调用方已手选 360p|
|cp3-r2-abr.json|377|同上|载荷 0×360 vs state 0×0|产品异步投递竞态；mpv 宽、高分别归零，前一次事件读到了后一次尺寸|

`engine.dart` 的尺寸回调、清晰度探测均先写 state 后 add 异步事件，API Future 续体/同步原生属性可先推进 getter。原逻辑离线回归两条变红（连续尺寸与探测后手选），并确认现有 `_loadKernel` 已抑制被取代的在途换档，不能重复修那个已正常的路径。

产品修复：状态事件同步广播，嵌套事件排队，避免重入控制器；MovaErrorEvent/MovaPlayFailure 保留异步边界，保持 open 接受结果和会话终结裁决原有顺序。未改 cutover、progress 节流、池 ready 语义。新增四条回归：两条红→绿，已存在的在途换档保护和嵌套通知另两条绿。实际回退 engine.dart 到修复前字节再次得到 2 FAIL/2 PASS，随后恢复固定版本。同步交付是可见时序变化，已记 CHANGELOG；不承诺宿主在一个事件监听器里主动改状态后其他监听器仍读旧值。

仍需新 APK 重跑 basic / basic-cutover / abr 三命令；离线回归不回写原始 208 PASS/14 FAIL，也不关闭未覆盖历史路径。

产品检查：`flutter analyze --no-pub lib test` 0 issues；最终 `flutter test --no-pub --concurrency=3 --reporter expanded` **2415/2415 PASS**（原基线 2411 + 新增 4）。回退原文件 2 FAIL/2 PASS；错误边界与新回归联合 12 PASS。最终全绿日志 `remaining-full-test-green.log`，回退日志 `remaining-receipt-rollback-red.log`，仅本地保留。

回执夹具修正：不把不属于 MovaState 的 position 加入状态相等 CHECK；Seeked 另外保留 payloadMs、lastProgressMs、未节流 progressValueMs，显式标记 landingVerified=false。原生稳定落点仍由 F3 独立验收，不能靠这次删掉错误的跨流硬相等来关闭落点验收。Size/Quality 仍严格比载荷与接收时 getter。example 定向测试 3 PASS，包含过期 progress 不误判、真实 Size/Rate 差异仍失败；analyze 41→41，归一化路径行号后诊断集合无新增；matrix --check 92 batches / 135 IDs / 6 manual，Python 三套合计 80 PASS。

## 4. 动态池资源：观测夹具缺陷及验收缺证据，未证泄漏

- `cp3-r2-pool-r2-20261105-085517` 的 `cp3-r2-s00d-resources.json` records[28,32,34,36,38,40,44] 共 7 BLOCKED。`/proc/self/fd/5`、`/163` 等动态链接消失导致 Directory listing ENOENT；handles=null，且同一个 try 后面的 stat CPU 读取被跳过。records[44] engineCount=0、created=3 证明逻辑释放，不能证明原生资源全回收。另一尝试 `cp3-r2-pool-r2-20261105-085435` 同类缺口，A29 原 6 条成功不改写为资源验收通过。
- 修夹具：task/fd 枚举 followLinks=false；线程、fd、CPU 各自捕获错误；保存单调 sampleUs、pid、processStartTicks、cpuUnit（Linux/Android 为时钟 tick，Windows 为 100ns）。CPU 不再被 fd 枚举异常抹掉；缺计数仍为未知。
- 新增 `RESOURCE_SAMPLE`：audio.before/active/disposed.1000ms；pool.before、active.20/40/60/80/100、concurrent.120、disposed.0ms/1000ms/5000ms。每点带实际进程计数、created、engineCount；保留原 CHECK。180 秒命令上限可容纳新增 6 秒释放稳定窗。
- 下一次新 APK 采样要求：同一进程/启动代际，在上述时点保留 RSS、线程、fd、CPU 与时间间隔。主机侧若用 adb，应配对采 `dumpsys meminfo <pid>` 的 TOTAL PSS/Native Heap/Graphics、`dumpsys media.codec` 与 `dumpsys SurfaceFlinger` 的该 PID 归属实例/层；必须保存设备支持的原文及命令返回码，字段不可读就标未知。也可用原生插件提供按实例的 decoder/surface create/dispose 计数，不能用 Dart created/engineCount 冒充。
- 资源/性能结论还需 CP0 与当前同源、同翻页数、同冷暖状态的多轮趋势和批准硬线；现有 sample CHECK 只检查计数完整性/合理性，不宣称无泄漏或耗电改善。电量字段均不可读时不能以 RSS/CPU 替代耗电。此类可脚本采集；阈值和异常 OEM 输出归属需要人工确认。
- 离线检查：example analyze 无新增，matrix --check 通过，Python 80 PASS。没有本轮设备资源数字，7 条原 BLOCKED 保留。

## 5. 偶发抽帧：仍待定，不能据重试通过关闭

- `cp3-headers-r2-20261105-084854` records[141] 的 extract-3：authorized HTTP 200，但 positive=false；其余 4/5 成功。`cp3-headers-r2-20261105-085001` records[38,73,108,144,180] 的抽帧对照 5/5 成功。失败不是“首次调用”必现（失败在第 4 次正对照），更不能归因鉴权 403。两次批次及其首次失败均保留。
- `MovaFrameExtractor._extractNow` 有 duration 就绪轮询（5 秒）、seek 落点轮询（seeking=no、time-pos 距目标 <300ms，5 秒）、默认 settleDelay=60ms，之后 screenshot 一次。异常/未就绪/截图 null 都返回 null。`MovaPullerThumbSource` 只透传结果，不做自动重试；成功缓存也不能解释本次新 source token 的失败。未找到能把这条样本解释为已知确定根因的证据。
- 原夹具把 null/空字节/20 秒外层超时/异常都压成 false，隐藏播放器没有按本次 token 记录 duration、seeking、time-pos、screenshot 返回码与原生日志阶段，所以无法定位是加载未就绪、seek 未落地还是截图失败；HTTP 200 不证明响应体完整或解码成功。共享播放器的 KERNEL_LOG 不能冒充隐藏抽帧器日志。
- 仅修观测：每次正负对照记录 targetMs、elapsedMs、outcome(null/empty/frame)、bytes，外层异常另记 error/type，不增加重试，不改 lib。
- 下一次需新 APK 保留这些首试诊断；若仍 null，还需按隐藏播放器实例/请求 token 关联 open、duration、seeking/time-pos、screenshot/原生错误的时间线和媒体响应体校验，再决定是否修产品。已返回 null 时 API 不暴露内部阶段，不能承诺本次夹具改动单独就足以定因。B07 原生准确落点仍未验收。
- 离线检查：example analyze 无新增，编译/回执定向测试 3 PASS，matrix --check 与 Python 80 PASS。
