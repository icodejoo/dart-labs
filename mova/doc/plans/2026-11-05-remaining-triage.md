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
