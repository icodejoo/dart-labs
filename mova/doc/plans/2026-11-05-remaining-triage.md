# CP3 剩余项离线定性

起点 `76805160`，仅在 `E:\workspaces\wt-mova-cp2fix` 自行执行。原始证据只读，未使用真机、adb、Gradle；不将离线修正当作真机 PASS。下列 run-id 的证据目录均为 `example/tool/coverage_evidence/matrix-<run-id>/`，records 下标从零开始；累计日志仅取最后一个 BEGIN 后的本命令记录。

## 1. 字幕：打包夹具缺陷，已离线修正，真机 BLOCKED 保留

- 证据：`cp3-r2-subtitles-r2-20261105-085403` 的 `cp3-r2-subtitles.json` records[9] 为 SRT 资产加载 SCRIPT_ERROR；前一尝试 `cp3-r2-subtitles-r2-20261105-085320` 同因。
- `coverage_new.dart:subtitles` 已把包内视频/字幕写入临时目录，再经原生 `sub-add` 或 MP4 内嵌 mov_text 播放；不走旧 HTTP 404 路径。SRT 文件已受 git 管理，但 pubspec 只声明 ASS/VTT 和两段视频，缺 SRT。补齐声明并移除过时的临时资产注释，无产品修改，无需引入 HTTP 服务。
- 下一次必须新 APK：逐格式取得 `F11.srt/ass/vtt/movtext` CHECK 和 `SUBTITLE_SHOT` 的 sub-text、track-list、position；四项本轮均未验收，包声明正确不能替代原生解码与人工画面复核。

## 2. headers 池预热：夹具判据错误，未证产品缺陷

- `cp3-headers-r2-20261105-085001` records[38,73,108,144,180]：pool positive/negative 都为 true；第 0 轮无 negative 回执，第 2 轮两侧回执均尚未出现。`085001` 与 `084854` 两试均 0/5。原判据在 `pool.bind` 返回即读取 ready、立刻 dispose；异步请求可迟到，甚至在真正打开前被销毁。
- `feed_pool.dart:_openBinding` 明确将 ready 定义为 open accepted；拒绝结果撤销绑定，成功接受并不代表加载/解码成功。这与公开文档一致，不能改产品 ready 含义来迎合探针。
- `IMovaHeaderedHttpFetch` 用于 Dart 辅助请求（清晰度/VTT/预取）；池走播放器 → mpv 原生媒体加载头。原回执中 authorized Referer/200、denied 无头/403 均出现，不能据 ready 双 true 认定头丢失。
- 修正：单播放器池挂载真实 surface，开启 preciseFirstFrame，等待 rendered+非零 duration/尺寸或错误；保留 accepted、decoded、状态和原生 path/time-pos/pause。再释放池、汇总两侧 HTTP 回执。负对照超时/错误不冒充成功，缺服务端回执仍 FAIL。
- 需要新 APK、原 5 轮正负对照复验。解码预热尚未获得有效设备验收。
- 补强解码判据：首帧 gate 允许 size/grace 兜底，故仅 rendered 仍不够；现在还要求暂停状态下真实 surface 的 screenshot 返回非空 JPEG，记录 imageBytes 与 firstFrameSignals，再认领 decoded=true。截图失败保留失败，不自动重试。此补强追加独立夹具提交；example analyze 仍 41→41（无新增），定向测试 3 PASS，matrix --check / Python 80 PASS。

## 3. 回执 14 条：12 条夹具判据错误，2 条普通播放器产品缺陷

证据 `cp3-r2-receipt-r2-20261105-090006`，三个独立命令只统计各自最后 BEGIN 后的 CHECK（日志含前命令累计记录，不能重复计数）：

|命令文件后缀|records|归属|差异|定性|
|---|---|---|---|---|
|cp3-r2-basic.json|39,44,49,59,64,68|普通播放器 116100005|Seeked position|独立 progress 流的最后读数 3394/5000/10000 等与事件目标 5000/10000/15000/10000/8000/0 不相等，不是 MovaState 字段差异|
|cp3-r2-basic-cutover.json|207,212,217,227,232,236|cutover 代理|Seeked position|同上；不能据此认定 H77 state/events 同序列修复失效|
|cp3-r2-abr.json|349|普通播放器 237005018|Auto 载荷 vs state 360p|产品异步投递竞态，探测已更新 Auto，但事件收到前调用方已手选 360p|
|cp3-r2-abr.json|377|同上|载荷 0×360 vs state 0×0|产品异步投递竞态；mpv 宽、高分别归零，前一次事件读到了后一次尺寸|

`mova.dart` 的尺寸回调、清晰度探测均先写 state 后 add 异步事件，API Future 续体/同步原生属性可先推进 getter。原逻辑离线回归两条变红（连续尺寸与探测后手选），并确认现有 `_loadKernel` 已抑制被取代的在途换档，不能重复修那个已正常的路径。

产品修复：状态事件同步广播，嵌套事件排队，避免重入控制器；MovaErrorEvent/MovaPlayFailure 保留异步边界，保持 open 接受结果和会话终结裁决原有顺序。未改 cutover、progress 节流、池 ready 语义。新增四条回归：两条红→绿，已存在的在途换档保护和嵌套通知另两条绿。实际回退 mova.dart 到修复前字节再次得到 2 FAIL/2 PASS，随后恢复固定版本。同步交付是可见时序变化，已记 CHANGELOG；不承诺宿主在一个事件监听器里主动改状态后其他监听器仍读旧值。

仍需新 APK 重跑 basic / basic-cutover / abr 三命令；离线回归不回写原始 208 PASS/14 FAIL，也不关闭未覆盖历史路径。

产品检查：`flutter analyze --no-pub lib test` 0 issues；最终 `flutter test --no-pub --concurrency=3 --reporter expanded` **2415/2415 PASS**（原基线 2411 + 新增 4）。回退原文件 2 FAIL/2 PASS；错误边界与新回归联合 12 PASS。最终全绿日志 `remaining-full-test-green.log`，回退日志 `remaining-receipt-rollback-red.log`，仅本地保留。

回执夹具修正：不把不属于 MovaState 的 position 加入状态相等 CHECK；Seeked 另外保留 payloadMs、lastProgressMs、未节流 progressValueMs，显式标记 landingVerified=false。原生稳定落点仍由 F3 独立验收，不能靠这次删掉错误的跨流硬相等来关闭落点验收。Size/Quality 仍严格比载荷与接收时 getter。example 定向测试 3 PASS，包含过期 progress 不误判、真实 Size/Rate 差异仍失败；analyze 41→41，归一化路径行号后诊断集合无新增；matrix --check 92 batches / 135 IDs / 6 manual，Python 三套合计 80 PASS。

## 4. 动态池资源：观测夹具缺陷及验收缺证据，未证泄漏

- `cp3-r2-pool-r2-20261105-085517` 的 `cp3-r2-s00d-resources.json` records[28,32,34,36,38,40,44] 共 7 BLOCKED。`/proc/self/fd/5`、`/163` 等动态链接消失导致 Directory listing ENOENT；handles=null，且同一个 try 后面的 stat CPU 读取被跳过。records[44] movaCount=0、created=3 证明逻辑释放，不能证明原生资源全回收。另一尝试 `cp3-r2-pool-r2-20261105-085435` 同类缺口，A29 原 6 条成功不改写为资源验收通过。
- 修夹具：task/fd 枚举 followLinks=false；线程、fd、CPU 各自捕获错误；保存单调 sampleUs、pid、processStartTicks、cpuUnit（Linux/Android 为时钟 tick，Windows 为 100ns）。CPU 不再被 fd 枚举异常抹掉；缺计数仍为未知。
- 新增 `RESOURCE_SAMPLE`：audio.before/active/disposed.1000ms；pool.before、active.20/40/60/80/100、concurrent.120、disposed.0ms/1000ms/5000ms。每点带实际进程计数、created、movaCount；保留原 CHECK。180 秒命令上限可容纳新增 6 秒释放稳定窗。
- 下一次新 APK 采样要求：同一进程/启动代际，在上述时点保留 RSS、线程、fd、CPU 与时间间隔。主机侧若用 adb，应配对采 `dumpsys meminfo <pid>` 的 TOTAL PSS/Native Heap/Graphics、`dumpsys media.codec` 与 `dumpsys SurfaceFlinger` 的该 PID 归属实例/层；必须保存设备支持的原文及命令返回码，字段不可读就标未知。也可用原生插件提供按实例的 decoder/surface create/dispose 计数，不能用 Dart created/movaCount 冒充。
- 资源/性能结论还需 CP0 与当前同源、同翻页数、同冷暖状态的多轮趋势和批准硬线；现有 sample CHECK 只检查计数完整性/合理性，不宣称无泄漏或耗电改善。电量字段均不可读时不能以 RSS/CPU 替代耗电。此类可脚本采集；阈值和异常 OEM 输出归属需要人工确认。
- 离线检查：example analyze 无新增，matrix --check 通过，Python 80 PASS。没有本轮设备资源数字，7 条原 BLOCKED 保留。

## 5. 偶发抽帧：仍待定，不能据重试通过关闭

- `cp3-headers-r2-20261105-084854` records[141] 的 extract-3：authorized HTTP 200，但 positive=false；其余 4/5 成功。`cp3-headers-r2-20261105-085001` records[38,73,108,144,180] 的抽帧对照 5/5 成功。失败不是“首次调用”必现（失败在第 4 次正对照），更不能归因鉴权 403。两次批次及其首次失败均保留。
- `MovaFrameExtractor._extractNow` 有 duration 就绪轮询（5 秒）、seek 落点轮询（seeking=no、time-pos 距目标 <300ms，5 秒）、默认 settleDelay=60ms，之后 screenshot 一次。异常/未就绪/截图 null 都返回 null。`MovaPullerThumbSource` 只透传结果，不做自动重试；成功缓存也不能解释本次新 source token 的失败。未找到能把这条样本解释为已知确定根因的证据。
- 原夹具把 null/空字节/20 秒外层超时/异常都压成 false，隐藏播放器没有按本次 token 记录 duration、seeking、time-pos、screenshot 返回码与原生日志阶段，所以无法定位是加载未就绪、seek 未落地还是截图失败；HTTP 200 不证明响应体完整或解码成功。共享播放器的 KERNEL_LOG 不能冒充隐藏抽帧器日志。
- 仅修观测：每次正负对照记录 targetMs、elapsedMs、outcome(null/empty/frame)、bytes，外层异常另记 error/type，不增加重试，不改 lib。
- 下一次需新 APK 保留这些首试诊断；若仍 null，还需按隐藏播放器实例/请求 token 关联 open、duration、seeking/time-pos、screenshot/原生错误的时间线和媒体响应体校验，再决定是否修产品。已返回 null 时 API 不暴露内部阶段，不能承诺本次夹具改动单独就足以定因。B07 原生准确落点仍未验收。
- 离线检查：example analyze 无新增，编译/回执定向测试 3 PASS，matrix --check 与 Python 80 PASS。

## 6. CP1 三条总项重新评估

已在 `2026-11-03-cp1-results.md` 追加“后续证据关闭”，保留原结论和 JSON：

|原总项|本次裁决|后续动作/人工边界|需要新 APK|
|---|---|---|---|
|终审7b / fallback|历史责任归因仍 BLOCKED；功能通过不能证明旧相对 URI 失败根因|缺旧响应/跳转正文、服务退出码与 mpv 失败时间线；可先离线补全原归档，仍需复现则安排受控设备/服务|仅离线补归档不需要；设备复现须按最终代码构建|
|B块|总行仍 BLOCKED；仅 B.bottomPatch 自动结构判据后续关闭|`cp3-cp1gap-bottom-r2-20261105-085136` records[161,275,401,519,637]，5 CHECK/60 挂载；B07 的目标帧/原生落点、OEM 亮度/显示恢复、弹幕 CP0 分布或批准硬线仍缺。画面和亮度感受需人工；性能硬线需负责人确认|底栏关闭本身不需要；B07/亮度等补测应使用新包|
|Windows|仍 BLOCKED，缺 CP0 配对基线；CP2/CP3 没有新 Windows 比较证据|安静模式下两版 F3 三模式/dispose/HE V6；既有 V10 功能 PASS 不变。Android fullscreen 成功不替代 Windows 基线|不需要 Android APK；需要 Windows 构建及运行环境|

这三条总行并没有因底栏子项关闭而变成全部 PASS。CP2 报告的额外 POD2 自动证据与视觉人工边界，也已在 CP1 追加节说明。

证据可用性限制：本 worktree 提供的 coverage_evidence 原始目录是本次 CP3 第二轮记录；旧 CP1/CP2 路径在结果文档中有引用，但相应原始文件不在此树。已直接检查可用的第二轮 JSON、driver/logcat、代码与 matrix-run；不能声称对不存在的历史原始文件完成重新审计。未到其他 worktree 查找或复制，也未用摘要补造缺失证据。

## 检查、提交与执行偏差

- 产品：analyze lib/test **0 issues**；最终全量 `flutter test --no-pub --concurrency=3` **2415 PASS**；四条新增回归中两条实际回退再次变红，另两条保护在途换档和嵌套通知。根 lib/test 在全绿后未再改行为。
- 夹具：example analyze 基线与最终均 **41 条既有诊断，新增 0**（比较时仅去除路径行列号）；`cp3_pages_test.dart` **3 PASS**。`run_matrix.py --check` **92 batches / 135 IDs / 6 manual PASS**；`test_run_matrix.py` **66**、`test_win_policy.py` **11**、`test_win_job.py` **3**，合计 **80 PASS**；最后一次池采图补强后再次检查通过。
- 全量尝试均保留本地日志：首次在 +1374 时 Dart VM OOM，未得完整结论；第二次 2414 PASS/1 FAIL，暴露失败通知的 accepted 边界变化，修复后相关 12 PASS；第三次 2401 已通过、14 项 did not complete（无断言失败，退出原因未定位），涉及三个 UI 文件单独 25/25 PASS；最终第四次 2415/2415 全绿。不将前面三次伪装成通过。
- Python 首次从 example 目录按模块执行导致 3 个 import error，改为在 example/tool 执行同一测试后 80 PASS。测试日志仅本地保留，未加入原始 coverage_evidence、matrix-run 或任何禁止添加的路径。
- 无设备/adb/Gradle、新 APK、Windows 被测应用执行；没有分派、push、切分支、stash、reset、修改 CLAUDE.md，也未操作其他 worktree。同步投递属于产品行为变化，已记 CHANGELOG；夹具行为变化也逐次记录。

|提交|类别|结果|
|---|---|---|
|bd05c3db|字幕夹具|补齐 SRT 资产声明|
|20c21861|池预热夹具|等待媒体/错误及回执|
|90dc2201|产品修复|普通播放器状态事件同步投递；2415 PASS|
|1e123f92|回执夹具|分离 Seeked 独立流诊断|
|aeede0a5|资源夹具|独立计数及释放稳定窗|
|0b548a71|抽帧夹具|保留首试空帧/异常耗时|
|2fdfd879|池预热补强|实际暂停图像及信号来源|

CP1/CP3 结果追加节及本报告收口由最后一个 `test(mova)` 提交保存，自身 hash 见最终汇报。

新 APK 设备复验清单：①字幕 SRT/ASS/WebVTT/mov_text 四 CHECK/画面；②headers 原 15 项，加 5 轮抽帧与池预热正负对照（须有授权图像/拒绝回执，首试失败保留）；③receipt basic/basic-cutover/abr 三命令；④pool/audio 全阶段原生计数与配对资源基线。抽帧偶发/B07 仍需内部阶段和目标帧证据；CP1 亮度/弹幕/7b/Windows 的额外条件如上，不能靠这一轮新包自动全部关闭。
