# S00c：自动判据补充与 r1030 FAIL 定性

> 后续状态见 [S00d 报告](2026-11-03-s00d-coverage-closure.md)：本轮 17 项接入整项规则，15 项验证器仍未补齐；本文保留 S00c 历史分布。


**本次未完成 S00c 主任务，也未达到总计划 §3.2 的 S00 完成判据。** 已补下表列出的具名判据、原生宿主取证和验证器修正；仍有 **32 个编号未补齐验证器**（含仍 FAIL 的 A2，其余 31 个 BLOCKED），逐项列在末节。不能把这些缺口称为真缺环境。

离线重放：**PASS 69 / FAIL 5 / BLOCKED 61**，共 135 个编号。完整逐子项原始定位见 [S00c 重放 JSON](2026-11-03-s00c-matrix-replay-r1030.json)。S00b 的 JSON/MD 原件保留。

验证器代码提交：`33ac0de2`（test(mova): 补充S00c判据与原生宿主取证）。

本次本人执行，无转派；未调用 adb、安装 APK、构建 APK 或使用真机。只在本 worktree 的 mova/example 与 mova/doc 写入；lib/test 未改。r1030 从授权的 dart-labs 证据目录只读复制到本树 gitignored 目录，未在其他 worktree 执行 git 或构建。

## 证据与判定约定

- **下表所有新增设备判据均为“未上机”**。当前 lib 的 analyze 与无设备用例已校验；没有验证另一个 worktree/编排分支的构建。新增 Dart 调用使用当前公开 API 和 testing.dart，无新增 visibleForTesting 调用。
- CHECK 保留 numbers 或 expected/actual；matrix_rules.json 的 assertions 重新比较这些输入，生产者写 true 不能绕过数学条件。缺字段、缺必需 CHECK、未知 dumpsys 格式均不能 PASS。
- 新公开故障注入通过真实 Mova 的公开动词/事件验证核心契约；origin=public-testing-kernel，**不能当作原生解码、FFI 或系统窗口的验证**。A29.rangeWarm 为实际 loopback HTTP 请求，origin=loopback-http。两者均未拼入 r1030 历史证据。
- 宿主 time.monotonic/Stopwatch 只限制等待、调度或记录事件戳；不把墙钟经过时间当成产品通过条件。现有 source() 的 DateTime 只生成防缓存 URL。
- gap CHECK 来自已有实际组件树/渲染属性/点击事件比较，只有该 case 有 END 且无 HARNESS ERROR 才导出；保留 originGapIndex/Case/Run，可回查原始 gap.json 的 rows 数组。没有把整个 gap 场景的 PASS 映射成整个 v1 编号 PASS。
- 当前离线测试：Python **38 项通过**；run_matrix.py --check 通过（49 batches / 135 IDs / 6 manual）；example flutter analyze **40 条既有 issue，未新增**，含 rerun6/rerun7 两条 debugSetQualities warning。flutter test --no-pub test/s00c_contract_test.dart 通过，产生 20 条公开 API/loopback CHECK。analyze 因既有 issue 返回非零，不能写成“零 issue”。

## 已接入的逐编号判据

文件简写：API=`example/lib/main_coverage_api.dart`；PUBLIC=`example/lib/verify_auto/s00c_contract.dart`；NEW=`example/lib/verify_auto/coverage_new.dart`；UI_KIT=`example/lib/verify_auto/coverage_gap_ui_kit.dart`；GAP=`example/lib/verify_auto/coverage_gap.dart`；KA=`example/lib/verify_auto/keep_alive_auto.dart`；HOST=`example/tool/coverage_s00c.py`。所有条件同时要求对应 CHECK.pass 为布尔 true。

| 编号 | CHECK / EVENT | 产出文件 | 判定条件与下次预期证据 | 状态 |
|---|---|---|---|---|
| A1 | A1.{events,states,progress,uiStates}.sequence | API basic | 四流各两个订阅者，leftCount=rightCount≥1，内存逐对象比较 equal=true，序列化 left=right；events 存 payload，其他流存字段值；basic/basic-cutover 两份来源必需，另保留 closed/progress | 未上机 |
| A5 | A5.openThrows | PUBLIC | recovery=false；公开测试内核恰有一次 open；真实播放器抛出与注入对象相同的异常。原生坏 URL 是否同步抛仍是独立 H33 观察项，不据此声称原生会抛 | 未上机；核心故障注入已离线通过 |
| A6 | A6.togglePlay/togglePause/repeatPlay/repeatPause；A6.intentIndependent/branchPlay/branchPause | API、PUBLIC | 普通/代理两实现重复 play/pause 后状态与 intent 正确；playOrPause 两方向；注入内核未确认 playing 时 intent=true、playing=false，并按 playing 精确下发 [play]/[pause] | 未上机；公开故障注入已离线通过 |
| A14 | A14.window.enter/restore | HOST | 原生 DisplayFrames、实际 InsetsSource visible；进入 fullscreen=true 且两栏隐藏，退出 fullscreen=false、rotation/status/navigation 与进入前原生基线相等；原先两实现 fullscreen CHECK 仍必需 | 未上机；原生解析器仅用合成样本校验 |
| A15 | A15.miniStable/exit；A15.miniHostToPip/pipExpanded | PUBLIC、HOST | 两实现 mini 连续 true 只发一次事件、epoch/handle/pip/orient/volume 不变，退出累计两次事件；真实 MiniHost showing=true→false、mount=host、PiP pinned=true、epoch 不变；展开后 showing/mini/pip/pinned 均 false | 未上机；前两项公开故障注入已离线通过 |
| A16 | A16.window.{landscape,portrait,auto} | HOST | 原生宽高与强制方向一致；auto 在全屏中按真实解码视频宽高比选择方向，核对实际显示宽高，不用物理转屏前的强制 portrait 猜 auto 的方向 | 未上机 |
| A18 | A18.pinned.enter/expand/close；N9.transitions | HOST | enterPip 返回 true，真实目标 app task pinned、state.pip=true 且 mini=false；展开和真正点击系统 X 后 pinned/pip=false；事件值精确为 [true,false,true,false]。系统 X 必须按 SystemUI XML 的 Close/关闭控件定位，未定位则 BLOCKED，不猜坐标 | 未上机 |
| A21 | A21.sticky/autoHide/dragging/hudCleared | PUBLIC | 实际 uiStates：sticky 保持可见、普通自动隐藏；dragging=true/previewAt=7000/hud=seek/text=s00c；随后 hud=none、text=null、dragging=false；不以计时墙钟值判 PASS | 未上机；公开用例已离线通过 |
| A25 | S6.publicFallback；keepalive_wake | KA、matrix_evidence.py | S6 走公开 setKeepAlive：audio=absent、phase=fallback、reason=silentStream、原生 vid 未关闭/mute=no；至少三轮。S1 至少九条原始 phase/signal/vid/mute/decodedProp；grace/timeout/null 保持 BLOCKED，非 grace 的原生落地信号才可通过该子项 | 未上机；S1 另有 H42 语义存疑 |
| A29 | A29.rangeWarm/poolReclaimed；修正 A29.dispose | PUBLIC、NEW | 本地真实 HTTP 收到一次 Range=bytes=0-64；原生池滑动/快速激活后沿用 final，dispose 后 movaCount=0、三个已创建播放器 open 均 false。旧 dispose 的常量 true 已移除 | 未上机；Range 请求已离线通过 |
| A30 | A30.mode.{vtt,extract,fallback,offline,blocked}；A30.clear.*；A30.cancelResult/staleResult | NEW、PUBLIC | 成功模式 observedMs=[4000,8000,12000,4000]、四份 bytes 非空、内存≤2；extract/fallback/offline 抽帧恰三次、diskHits≥1；VTT 抽帧/缓存写入均零（crop 不缓存）；blocked 无非空 thumb/抽帧；每模式 clear 后 current=null、内存=0；取消和换源后晚到结果发布数=0。旧 diskHit 必需项保留 | 未上机；并发取消/换源已离线通过 |
| C1 | 同 A30 的全部 mode/clear/cancelResult/staleResult | NEW、PUBLIC | 不以单一 VTT 成功代替所有模式。offline 先把实际视频保存为本地文件，再以 file URI 抽帧、VTT 地址不可达；这证明无缩略图网络源时的本地媒体回退，不证明系统飞行模式 | 未上机 |
| C3 | rerun-batch16-{mova,cutover}.doubletapSeek（修正） | example/tool/coverage_widgets_ui.py | 右侧双击后必须出现 MovaSeek，target=钳制(position+10000ms)，误差≤200ms；不再要求 playing=true。其余捏合/轴重映射等仍未补齐 | 未上机；部分完成 |
| C4 | C4.abrDown | NEW abr | 实际限速后 MovaAbrDownShift 的 toBandwidth<fromBandwidth、目标事件 URI=最终 state URI、policyResets≥1；无码率元数据时 BLOCKED。既有 ABR_REAL、F3 原始记录保留 | 未上机 |
| C10 | C10.theme.{default,bilibili,douyin,mini}；C10.strings.{default,bilibili}；C10.accent.douyin；C10.buffering | UI_KIT、GAP、coverage_gap.py | 实际已挂载图标/文本样式 mismatches=[]；替换文案前后均找到；点赞 accent 与注入值一致；spinner 的 color/strokeWidth/size 三字段逐值相等；Mini 中心按钮颜色/尺寸相等 | 未上机 |
| C13 | C13.defaultHeartbeat | PUBLIC | 实际 Zone.createPeriodicTimer 观察默认 heartbeat=null，创建 periodic timer 数=0；QoE 完整四分仍缺，未删除 coverage1 | 未上机；部分完成，公开用例已离线通过 |
| C15 | 同 A25 | KA、matrix_evidence.py | 去掉旁路内核强制 B 的错误 S6 判据，保留 maxDuration 及 S2/S3/S13/S17；S1/H42 仍 BLOCKED | 未上机；兼语义存疑 |
| C17 | C17.sameAs | PUBLIC | 相同源/请求头 mpv option/alternatives 为 sameAs=true；只改 http-header-fields 或备选地址为 false。请求头原生读回等其余子项仍缺 | 未上机；部分完成，公开用例已离线通过 |
| E.MovaPreviewBlock | EVENT MovaPreviewBlock + E.MovaPreviewBlock.network | PUBLIC、API observe | network=never 后实际事件 reason=network、count≥1，事件戳与接收时 state 保留 | 未上机；公开用例已离线通过 |
| E.MovaKeepAliveResume | EVENT MovaKeepAliveResume | KA | 在真实 api.events 订阅中记录 elapsed/signal/from 与接收 state，写 MATRIX_RECORD；只接收带 AUTORUN DONE 的日志，不从 S1 文本推造事件 | 未上机 |
| U2 | U2.componentNames；U2.tree.* / mounted.*；U2.patchNoop；U2.patchTree.* / patchMounted.* / patchClick.* | UI_KIT、GAP、coverage_gap.py | 五套 UI 套件逐槽 tree=expected.tree、无缺失图标、GradBar 数正确；无匹配路径补丁不改输入；Default/Bilibili 四种补丁后的树/挂载实值，以及每个新增或替换探针点击后的 rate 与 MovaRateChange 事件 | 未上机 |
| U6 | 同 C3 的 doubletapSeek 修正 | example/tool/coverage_widgets_ui.py | 删除长按倍速旧断言，只保留观察；完整所有手势判据仍未补齐 | 未上机；部分完成 |
| F5 | F5.pipWake + A15 两个宿主 CHECK | HOST | 真实直播进入 holding 后 enterPip，目标 task pinned、mini=false、phase 回 off 且有实际 MovaKeepAliveResume；与 MiniHost 互斥条件联合 | 未上机 |
| F6 | 同 A25 | KA、matrix_evidence.py | S6 公开 fallback + S1 独立原生信号；不把 5s grace 当作视频恢复耗时 | 未上机；兼语义存疑 |
| F10 | 同 A30 全部模式/clear/取消/换源 | NEW、PUBLIC | 不复用旧 finalize 的硬编码 PASS；全部 CHECK 必须齐备 | 未上机 |
| F11 | F11.{ass,vtt,movtext} MATRIX_RECORD；SUBFMT AUTORUN DONE | example/lib/main_subtitle_formats_probe.dart | 原生 sub-text 实际采样数与非空样本数，零样本为 BLOCKED，窗口结束有完成标记；原有 NEW 中 srt/ass/vtt/movtext 必需 CHECK 不删。旧探针漏完成标记已修复 | 未上机；r1030 已有其他完整命令证据可 PASS |
| N9 | 同 A18，含 N9.transitions | HOST | 原生目标 task 与实际 PipChange 四步序列对账，重复值不能重发 | 未上机 |
| N12 | N12.openReset/freshRestart | PUBLIC | 第二次 open 后 rendered=false、宽高=0；新 RESTART 后 rendered=true 且累计两个 FirstFrame。**未补原生旧 RESTART 隔离**，coverage1 仍在 | 未上机；部分完成，公开用例已离线通过 |
| N16 | N16.variants.{true,false}.{true,false} + C10.buffering + U2.mounted.minimal | UI_KIT、GAP、coverage_gap.py | 四个 showBuffering/showError 组合组件树逐值相等；Minimal 无图标/GradBar；实际 spinner 三字段与主题一致 | 未上机 |
| N20 | 同 A25 | KA、matrix_evidence.py | 与 A25/F6 同一组共享证据，不能因别名改变再发明一份结论 | 未上机；兼语义存疑 |

新增公开用例接在 coverage_new 的 s00c case，coverage_api_batches 注册 batch15-s00c。宿主新增 s00c-native 批次，放在 api-launch 之后、会锁屏的 gap-screen **之前**；本轮未执行。gap 的原始具名 CHECK 导出为本 run 目录中的 `matrix-<run>-gap-ui-kit-checks.json`，不是派生 gap-result.json。

## 验证器旧预期与批次异常修正依据

1. A1-① 明确写“不看 isBroadcast”；废弃 A1.broadcast，不再将该历史 false 或旧断言本身加成 BLOCKED。四流完整序列与两实现来源成为必需条件。
2. C3-①、U6-① 明确左右双击 seek、长按现无倍速；改右侧双击 seek 目标断言，长按只保留原始观察。
3. A29-① 的 MovaNetworkWarmFeedPrefetcher 只预热 DNS/TCP/TLS/CDN 并丢弃响应字节（feed_prefetcher.dart 文档），不承诺落盘或缓存“命中”。改测实际 Range 请求，不虚构缓存命中。
4. `matrix-r1030-existing-pages.harness-errors.jsonl` 唯一错误是 rerun-batch13-subtitles 的 completed=false。其原始日志有字幕采样但没有 AUTORUN DONE。修复页的完成标记；并将 run_matrix.py 改动限制在 make_rows 的粗粒度 gate：evidence_only 的各编号已按独立完整命令/日志必需项对账，不再由不相关子页异常一票阻塞。HARNESS 仍留在 batches 中，不抹历史错误。
5. 因第 4 点，r1030 的 **A24、C11、E.MovaCutoverChange、F4、F11、F16、N10、N11** 共 8 项 BLOCKED→PASS，使用原先就存在的原始 CHECK/日志，并非新增设备结果。A24 六项在独立 done 命令中齐备，不能因为另一个字幕子页未发完成标记而否认这些证据。

## 9 条 FAIL 定性表

证据根目录均为 `example/tool/coverage_evidence/matrix-r1030/`。JSON 下标为原始 records 数组的 **0 起始**下标，保留最后 BEGIN 之前的绝对索引；日志行索引使用 `Path(...).read_text().splitlines()` 的 0 起始索引（源日志有重复 CR，不能直接与编辑器物理行号混用）。

| 编号 | 定性 | 证据与依据 | 新重放 |
|---|---|---|---|
| A2 | 产品契约缺陷 D01；全字段判据仍未补齐 | A2-① 与 H77 明确接收时 state 对账；13 条 buffer、21 条 size、2 条 quality 差异。完整定位在重放 JSON，代表见 D01 | FAIL |
| E.MovaBufferChange | 产品契约缺陷 D01 | final-hls.json records[961]：payload.buffering=false，state.buffering=true | FAIL |
| E.MovaSizeChange | 产品契约缺陷 D01 | final-abr.json records[1208]：payload=0x360，state.size=0x0 | FAIL |
| E.MovaQualityChange | 产品契约缺陷 D01 | final-abr.json records[1193]：payload.quality=自动，state.quality=360p；不是可以忽略“自动”档的契约 | FAIL |
| C16 | 产品原生链路缺陷 D02；责任层未定 | final-tls-probe.json records[497–498] 原生 verify=yes、CA 文件 1150 字节而正确 IP SAN MP4 失败；同 CA 的 localhost 控制组 records[527–528] 成功。正确证书已做本地 CA/IP 校验 | FAIL |
| A25 | S6 验证器错测；S1/H42 存疑 | S6 绕过公开播放器决策直接强制 kernel.enterKeepAlive(muted)，不应当归为公开 API 产品失败；S1 语义在矩阵 §5.3 明确待决 | BLOCKED |
| C15 | S6 验证器错测；S1/H42 存疑 | 与 A25 同一组原始 S1/S6；不能因 maxDuration 子项通过就覆盖未知唤醒语义 | BLOCKED |
| F6 | S6 验证器错测；S1/H42 存疑 | forcedAdvance<0 同时有 EOF、Done、PlayFailure 和重开归零，是强制禁掉全部音视频通路后的现象，不能以位置绝对差<500ms 判公开 silent-stream 契约 | BLOCKED |
| N20 | S6 验证器错测；S1/H42 存疑 | 旧 `Standby*` 事件名只做别名迁移，仍按同一公开 keepAlive 决策与唤醒证据判定 | BLOCKED |

### 产品缺陷 D01：事件投递与接收快照不同步

- 复现：真实 HLS 换档/ABR/重载中同步记录事件 payload 与该同一 api 的接收时 snapshot。已确认 cutover 代理存在差异。原始证据无法区分普通播放器与代理，普通播放器是否也有差异待上机区分；S00c 原“普通播放器和代理均有差异”证据不足。
- 证据：`matrix-r1030-final-hls.json:records[961]`（mova=273633813，ms=84557，buffer false→state true）；`matrix-r1030-final-abr.json:records[1208]`（mova=888527077，ms=117577，size 0x360→state 0x0）；同文件 records[1193]（ms=108308，quality 自动→state 360p）。这是接收快照违约，不能推导画面一定错误或近期才回归。
- 已确认原因：cutover 代理的 state 与 events 走两条独立订阅链，事件可领先 state。
- 建议修法：**A28：代理把 state 与 events 合并为同一投递序列 + 普通播放器一致性单测**。本树不改 lib；A2、E.MovaBufferChange、E.MovaSizeChange、E.MovaQualityChange 保持严格 FAIL，预期 A28 后转 PASS。普通播放器新增独立对账 CHECK，未上机区分。

### 产品缺陷 D02：严格 TLS 拒绝正确 IP SAN

- 复现：tlsVerify=true、同一 CA PEM，分别打开 `https://127.0.0.1:18443/vod.mp4`、该端口 HLS 与 `https://localhost:18447/…` 控制组；每组 3 轮。
- 证据：`matrix-r1030-final-tls.json:records[64]` 合法证书 verify=true 失败；`matrix-r1030-final-tls-probe.json:records[497]` 原生属性 verify=yes、CA=coverage-ca-probe.pem、caBytes=1150，records[498] 失败；HLS 为 [511–512]；DNS 控制 [527–528]、[543–544] 成功，后两轮对应 [557–664]。留存 good.pem 的 SAN=IP:127.0.0.1，有效期 2026-10-30 至 2026-11-09；本地 `openssl verify -CAfile …/ca.pem -verify_ip 127.0.0.1 …/good.pem` 返回 OK。
- 疑似位置：`lib/src/core/kernel/mpv_kernel.dart:327` 的 TLS 属性下发、`:683` open 等待 _tlsSetup；这两处源码已有 CA→verify→open 顺序，原始 readback 也正确，故不能仅归因为 mova 没传配置。下一层是当前 libmpv/FFmpeg/mbedTLS 的 IP SAN/hostname 校验路径，责任层仍需定位。
- 建议修法/补测：给同一证书同时含 DNS/IP SAN 的同一端口做 IP/DNS 交叉打开，留存原生 TLS verbose 错误、握手时服务端实际证书指纹、客户端 CA 文件 hash 与正确/过期/错主机/自签四组对照。确认后升级或修补原生 TLS 的 IP 地址匹配；DNS 地址可作临时兼容方案，不能把 tlsVerify=false 当修复。

### 存疑 D03/H42：保活恢复恒落 grace，elapsed 恒为 resumeTimeout

- 证据：`matrix-r1030-keepalive-core.log` splitlines()[694,1090,1466,1860,2276,2672,3096,3478,3870]，九次 S1 signal=grace、elapsed=5000–5002ms，video-out-params/w 轮询恢复为正的 decodedProp=106–158ms。属性恢复本身不能证明屏幕已展示新帧，不拿它覆盖事件语义。
- 疑似位置：`lib/src/core/mova.dart:1752` 的恢复闸门、`:1795` 的 resumeTimer→grace、`:1809` 的 _armResumeGate、`:1822` 的 _finishResume，以及 `lib/src/core/render/first_frame.dart:122` 的 resume size 分支。需要核实 vid 恢复后尺寸不变时是否根本不产生新的 size/RESTART。
- 缺的证据与决策：矩阵 §5.3 第 8 条要求先决定产品面是否保留 resuming 5s/elapsed=timeout；下一轮将 wake、RESTART、size、video-out 参数变化与实际帧计数递增放在同一单调时间轴，并记录原生观察客户端是否可用。当前 keepalive_wake 对 grace 保持 BLOCKED，未将其升级为已确认产品缺陷，也未以固定等待时间判 PASS。
- 旧 S6 旁路现象位置：同日志 splitlines()[7958–7960,8276–8278,8632–8634]，forcedAdvance=-5560/-5640/-5480ms，伴随 EOF/Done/PlayFailure。`lib/src/core/keep_alive/plan.dart:126` 的现行公开决策对无声流选择 silentStream fallback（或配置为 decodeOnly），旧脚本却直接强制 muted；新 S6 改走公开 API 后需重新采证。

## 重放分布与剩余阻塞分类

重放命令（默认 legacy baseline 文件在本树不存在，因此显式选择 S00b JSON）：

```powershell
python -B example/tool/run_matrix.py --replay example/tool/coverage_evidence/matrix-r1030 --run-id r1030 --baseline doc/plans/2026-11-03-matrix-replay-r1030.json
```

run_matrix 的日期命名输出另存为 S00c JSON 后，S00b 原件已恢复。原始 r1030 文件没有添加新 CHECK。

| 分类 | 数量 | 说明 |
|---|---:|---|
| PASS | 69 | S00b 61 + 独立完成证据解除粗粒度 gate 的 8 项 |
| FAIL | 5 | A2、C16、E.MovaBufferChange、E.MovaSizeChange、E.MovaQualityChange |
| BLOCKED：已接入判据、纯待上机 | 20 | A1、A5、A6、A14、A15、A16、A18、A21、A29、A30、C1、C4、C10、E.MovaPreviewBlock、E.MovaKeepAliveResume、U2、F5、F10、N9、N16 |
| BLOCKED：已接入判据、兼 H42 语义存疑 | 4 | A25、C15、F6、N20 |
| BLOCKED：验证器仍未补齐 | 31 | 下节所列 32 项中除 A2（它仍 FAIL）之外的编号 |
| BLOCKED：manual / 真缺环境 | 6 | 下表；未把剩余验证器工作移入 manual |

### 保留的 manual / 真缺环境

| 编号 | 缺少什么 |
|---|---|
| A31 | 真实 STT 模型、识别器和下载服务；公开假识别器回滚不等于真实识别 |
| C7 | 同 A31，缺真实识别及字幕/SRT/分块导出的完整证据 |
| C2 | 能按 behind 返回历史媒体且可控卡顿的服务；滑动 HLS 不能替代历史回看 |
| F15 | 可控 publisher/WHEP 信令与 UDP/relay 服务；仅端口可达不能证明播放 |
| N18 | mini/guard-off 联动专用包及完整复核，当前主包不足 |
| N22 | 专用 debug VM 构建和 assert marker；不能拿旧 release/profile APK 代替 |

未新增其他 manual。N21 的 Windows 专包、F12 的音频/耗电测量、F13 的资源边界等目前属于**验证工作未补完**，并没有足够依据将其永久归为外部环境阻塞。

## 未完成的逐编号工作

本次保留这些 coverage1 占位，缺记录仍 BLOCKED；A2 已有明确失败所以仍 FAIL。部分编号虽新增了子项，不能据此宣称整项自动化完成。

| 编号 | 尚缺的判据/用例 |
|---|---|
| A2 | position/intent/renderEpoch/sourceIndex 等全部字段逐事件对账 |
| A7 | 丢 seek 重发的独立原生调用次数断言 |
| A11 | 三种 fit 的画面差异自动量化 |
| A13 | 锁定前后手势屏蔽的原生亮度/音量对账 |
| A26 | mini 拖动/吸边/关闭/转屏钳回自动对账 |
| C3 | 手势双指捏合/单击/锁定/轴重映射完整 CHECK（长按倍速已非契约） |
| C5 | 所有 controls 配置的逐项可见性/计时 CHECK |
| C6 | 弹幕显示开关与 items 滚动自动对账（无发送框是现行契约） |
| C8 | playlist 配置与 NextUp 取消/立即播放 CHECK |
| C12 | mini 默认关闭/吸边/转屏钳回 CHECK |
| C13 | heartbeat 默认无定时器及 qoe 开启四分结算 CHECK |
| C17 | sameAs/请求头原生读回自动对账 |
| U1 | 三种 Player/View/FeedPlayer 的挂树/换源/卸载与资源对账 |
| U3 | 标题/方向/PiP/fit/quality/fullscreen 各按钮点击 CHECK |
| U4 | VOD/直播底栏、seek 提交/禁用/节流/预览气泡 CHECK |
| U5 | 中心播放/循环倍速/各 HUD 值渲染 CHECK |
| U6 | 所有手势含双指捏合/锁定/轴重映射 CHECK |
| U7 | 弹幕/字幕/NextUp/广告/FeedSocial 各渲染与点击 CHECK |
| U8 | mini 拖动/吸边/甩动/转屏 CHECK |
| U9 | 守卫 route/Ticker/inactive/PiP/mini 联合 CHECK |
| F7 | QoE 四分结算/TTFF/卡顿/truncated/heartbeat 逐字段 CHECK |
| F9 | audioOnly 无视频解码及真实 UI 套件/封面/手势 CHECK |
| F12 | 音频会话/后台资源与耗电完整 CHECK |
| F13 | 多播放器 RSS/线程/句柄有界及 dispose 超时 CHECK |
| F14 | 原生泵创建/销毁/稳定性/错误隔离的结构化 CHECK |
| N5 | recovery 仅订阅 END_FILE、observeRestarts 开关的原生事件对账 |
| N12 | 换源归零与旧 RESTART 隔离逐事件 CHECK |
| N13 | 弱客户端资源/懒创建计数与 QoE 开关联合 CHECK |
| N15 | poster 重盖/渐隐/audioOnly/Feed 的像素与首帧联合 CHECK |
| N17 | View 所有权/同源/null/options/销毁/异常各分支 CHECK |
| N21 | Windows SnapshotGuard 专包与 stagedSourceOptions 对账 |
| N23 | nativeRestartAvailable/truncatedBelow/error 四分与上报字段完整 CHECK |

后续应先补这 32 个编号的真实生产者和逐子项规则，再用新 APK 全量取证；当前 69/5/61 不是 S00 完成证明。所有本次新增原生、UI 与设备规则均未上机，dumpsys 格式和系统 PiP Close 控件定位也需在下次跑批中实证，解析不到保持 BLOCKED。
