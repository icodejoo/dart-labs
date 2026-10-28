# Android 真机修复复测（2026-10-27）

- 开始：阅读 CLAUDE.md 与上一轮复跑/Windows复测记录，复用隔离包和真实原生事件判据；仅自行执行，不转派，不修改库与测试源码。
- 开始设备前置检查：读取指定设备 window、USB常亮与媒体音量；必须明确 isKeyguardShowing=false 且 mScreenOnFully=true 才继续，锁屏立即停止。
- 前置检查点：isKeyguardShowing=false、mScreenOnFully=true；USB常亮=7；STREAM_MUSIC speaker=6/20。证据 rerun2-preflight.window.txt / .audio.txt。
- 开始基线：运行 flutter analyze lib test 与 flutter test，保存完整日志并以实际输出计数。
- analyze 检查点：exit=0；完整日志 rerun2-analyze.log。
- test 检查点：exit=0；完整日志 rerun2-test.log。
- 开始验证页扩展与构建：复用同一 HLS 场景，增加 count 长循环、原生播放/暂停判据、内核 seek 观测子类，避免修改 lib；MiniInfo 补 controller apiNull，A23单独覆盖两种 audioOnly 引擎。

- 基线最终检查点：analyze 0 issues；flutter test 1516/1516，全绿，两命令 exit 0。

- 开始重打包与安装：从本轮 Gradle APK 提取并核对原生库，zipalign 后使用既有 debug.keystore 重签；安装前后记录证书、SHA256 与 lastUpdateTime。

- 构建安装检查点：新 release 安装成功，设备拉回 APK SHA256 与重签包完全一致；lastUpdateTime/证书/源码哈希见 rerun2-build-manifest.json、rerun2-package-after.txt、rerun2-certificate.txt。

- 开始本地源与页面启动：复用已存在同一 VOD/HLS 素材，18080 提供 rerun-sources，18084 提供其 hls/high、low；设置 adb reverse 并确认新页面构建标记。

- 源/启动检查点：新页面 SERVER build=rerun2-20261027，双端口服务已启动并保存 owned PIDs；后续仅使用 rerun2 证据。

- 开始 rerun2-hls-cutover：{'group': 'new', 'case': 'hls', 'cutover': 'true', 'count': '100'}；保留真实事件、原生读回及画面，以对应判据核验。

- 中途失败检查点：cutover 完成52次时已观察2次未续播；本项已判 FAIL，继续累计至100次并保留全部失败的EVENT/RESTART/duration/实际seek调用时间线，现场快照 rerun2-hls-failure-live-snapshot.json。

- 失败形态检查点：cutover run42（第43次）target=19783ms，duration先40000ms，实际KERNEL_SEEK_CALL(19783)后RESTART仍[23,23]，continued=4423ms；run43无换档续播seek调用、RESTART[23]；至83次累计失败4次。该观察不能据此宣称根因已定位。

- rerun2-hls-cutover 检查点：status=done，本轮切档 100，失败 5，脚本异常 0；证据 rerun2-hls-cutover.json/.png/.logcat.txt。

- 开始 rerun2-hls-normal：{'group': 'new', 'case': 'hls', 'count': '30'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-hls-normal 检查点：status=done，本轮切档 30，失败 4，脚本异常 0；证据 rerun2-hls-normal.json/.png/.logcat.txt。

- 开始 rerun2-hls-paused：{'group': 'new', 'case': 'hls', 'paused': 'true', 'count': '30'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-hls-paused 检查点：status=done，本轮切档 30，失败 3，脚本异常 0；证据 rerun2-hls-paused.json/.png/.logcat.txt。

- 开始 rerun2-a23：{'group': 'new', 'case': 'retestDispose'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a23 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a23.json/.png/.logcat.txt。

- 开始 rerun2-a12-start：{'group': 'video'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12-start 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12-start.json/.png/.logcat.txt。

- 开始 rerun2-a12-pause：{'group': 'video', 'action': 'pause'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12-pause 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12-pause.json/.png/.logcat.txt。

- 开始 rerun2-a12--1：{'group': 'video', 'action': 'zoom', 'value': '-1'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12--1 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12--1.json/.png/.logcat.txt。

- 开始 rerun2-a12-0：{'group': 'video', 'action': 'zoom', 'value': '0'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12-0 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12-0.json/.png/.logcat.txt。

- 开始 rerun2-a12-NaN：{'group': 'video', 'action': 'zoom', 'value': 'NaN'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12-NaN 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12-NaN.json/.png/.logcat.txt。

- 开始 rerun2-a12-100：{'group': 'video', 'action': 'zoom', 'value': '100'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12-100 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12-100.json/.png/.logcat.txt。

- 开始 rerun2-a12-reset：{'group': 'video', 'action': 'zoom', 'value': '1'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12-reset 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12-reset.json/.png/.logcat.txt。

- 开始 rerun2-a12-end：{'group': 'video', 'action': 'dispose'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-a12-end 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-a12-end.json/.png/.logcat.txt。

- HLS独立审计检查点：逐次复算target、交替档位、完整RESTART序列、落点与原生continued判据均一致；统计 rerun2-hls-summary.json，逐次表 rerun2-hls-audit.json，失败完整时间线 rerun2-hls-failures.json。

- 开始 rerun2-mini-pip-repro-start：{'group': 'video'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-mini-pip-repro-start 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-mini-pip-repro-start.json/.png/.logcat.txt。

- 开始 rerun2-mini-pip-repro-show：{'group': 'video', 'action': 'miniHost'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-mini-pip-repro-show 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-mini-pip-repro-show.json/.png/.logcat.txt。

- 开始 rerun2-mini-pip-repro-show-info：{'group': 'video', 'action': 'miniInfo'}；保留真实事件、原生读回及画面，以对应判据核验。

- 审计纠正检查点：首批cutover中run55/67/97在失败后的原生seek复位竞争中target读回0，虽页面pass=true但不满足>=8s入组条件，剔除这3次，不能计入有效通过；首批有效cutover为92/97（失败5）。普通/暂停各30次全部target>=8s。将在其他项目完成后补跑cutover，确保有效切档至少100次。

- rerun2-mini-pip-repro-show-info 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-mini-pip-repro-show-info.json/.png/.logcat.txt。

- 开始 rerun2-mini-pip-repro-enter：{'group': 'video', 'action': 'pip'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-mini-pip-repro-enter 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-mini-pip-repro-enter.json/.png/.logcat.txt。

- 开始 rerun2-mini-pip-repro-holding：{'group': 'video', 'action': 'miniInfo'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-mini-pip-repro-holding 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-mini-pip-repro-holding.json/.png/.logcat.txt。

- 开始 PiP 展开：通过原生 am start 恢复同一Activity，检查展开后 controller api 与可视小窗。

- 开始 rerun2-mini-pip-repro-expanded：{'group': 'video', 'action': 'miniInfo'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-mini-pip-repro-expanded 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-mini-pip-repro-expanded.json/.png/.logcat.txt。

- 开始 rerun2-extra-prepare：{'group': 'video', 'action': 'dispose'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun2-extra-prepare 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun2-extra-prepare.json/.png/.logcat.txt。

- 开始 rerun2-hls-cutover-extra：{'group': 'new', 'case': 'hls', 'cutover': 'true', 'count': '20'}；保留真实事件、原生读回及画面，以对应判据核验。

- A23最终检查点 PASS：普通与enabled cutover代理均audioOnly、duration=40000ms；连续dispose两次共4/4正常，第二次异常0，逐次结果 rerun2-a23.json。
- A12最终检查点 PASS：-1/0/NaN读回1.0、100读回100.0，4/4；真实rendered=true、640×360、VideoController挂树。已直接目视检查rerun2-a12--1.png与rerun2-a12-0.png，彩条正常显示且不塌缩。
- A15/F5最终检查点 PASS：全新进程MiniHost显示时apiNull=false/showing=true/persistent；enterPip返回true且原生pinned；holding与展开后均apiNull=true/showing=false/mount=none/mini=false，展开pip=false；已直接目视检查show/holding/expanded截图，无残留App内小窗。证据rerun2-mini-pip-repro-*.json/.png/.activity.txt。
- 开始最终独立审计：合并首批与补跑，以target>=8000ms筛选有效次数，逐条核对原生path、RESTART、landed、continued与pause；每个失败单独保存完整EVENT/duration/seek/RESTART时间线，再生成对比结论。

- rerun2-hls-cutover-extra 检查点：status=done，本轮切档 20，失败 0，脚本异常 0；证据 rerun2-hls-cutover-extra.json/.png/.logcat.txt。

- HLS独立审计检查点：逐次复算target、交替档位、完整RESTART序列、落点与原生continued判据均一致；统计 rerun2-hls-summary.json，逐次表 rerun2-hls-audit.json，失败完整时间线 rerun2-hls-failures.json。

- 开始收尾：经现有验证页恢复媒体音量30%=6/20，USB常亮恢复7，force-stop隔离包；保留原生设置、进程与屏幕状态，再结束仅本次启动的两个源进程。

- 收尾检查点：隔离包pid为空（force-stop），USB常亮=7，媒体streamVolume=6/20；仍isKeyguardShowing=false、mScreenOnFully=true；本次两个源PID已结束，engine.dart哈希与安装时一致。证据 rerun2-final-state.json / rerun2-final-*.txt。


## 最终结论与基线

本轮按五项列出 F3/A17、A15、F5、A23、A12；A15/F5 共用一次完整小窗/PiP流程，不重复计算样本。全部为设备 `7NQBB23606003715` 的 Android release 实测，自行执行。

- `flutter analyze lib test`：**0 issues，exit 0**。
- `flutter test`：**1516/1516 PASS，exit 0**。
- 基线完整日志：[rerun2-analyze.log](../../example/tool/coverage_evidence/rerun2-analyze.log)、[rerun2-test.log](../../example/tool/coverage_evidence/rerun2-test.log)。

| 项目 | 结论 | 本轮次数与观察 | 证据 |
|---|---|---|---|
| F3/A17 换档续播 | **FAIL** | 有效177次，165通过/12失败；cutover 112/117、普通播放26/30、普通暂停27/30 | [rerun2-hls-summary.json](../../example/tool/coverage_evidence/rerun2-hls-summary.json)、[rerun2-hls-audit.json](../../example/tool/coverage_evidence/rerun2-hls-audit.json)、[rerun2-hls-failures.json](../../example/tool/coverage_evidence/rerun2-hls-failures.json) |
| A15 小窗随api收起 | **PASS** | 1条完整MiniHost→enterPip→展开；mini=false时controller api=null、showing=false、mount=none，界面无残留小窗 | [rerun2-mini-pip-repro-holding.json](../../example/tool/coverage_evidence/rerun2-mini-pip-repro-holding.json)、[rerun2-mini-pip-repro-expanded.png](../../example/tool/coverage_evidence/rerun2-mini-pip-repro-expanded.png) |
| F5 小窗/PiP衔接 | **PASS** | 同一条流程；enterPip=true，原生pinned，展开pip=false，小窗仍收起 | [rerun2-mini-pip-repro-enter.activity.txt](../../example/tool/coverage_evidence/rerun2-mini-pip-repro-enter.activity.txt)、[rerun2-mini-pip-repro-expanded.json](../../example/tool/coverage_evidence/rerun2-mini-pip-repro-expanded.json) |
| A23 重复dispose | **PASS** | 普通/cutover enabled代理各audioOnly打开40s源并连续dispose两次，4/4正常；两个第二次调用异常均0 | [rerun2-a23.json](../../example/tool/coverage_evidence/rerun2-a23.json) |
| A12 缩放下限 | **PASS** | 4/4：-1/0/NaN→1.0、100→100.0；真实挂树640×360；-1/0截图已目视确认不塌缩 | [rerun2-a12--1.png](../../example/tool/coverage_evidence/rerun2-a12--1.png)、[rerun2-a12-0.png](../../example/tool/coverage_evidence/rerun2-a12-0.png)、[rerun2-a12-NaN.json](../../example/tool/coverage_evidence/rerun2-a12-NaN.json)、[rerun2-a12-100.json](../../example/tool/coverage_evidence/rerun2-a12-100.json) |

## 新构建与设备安装一致性

- Gradle从当前工作区重新构建 `lib/main_coverage_api.dart`，`assembleRelease`成功（1m1s、777 tasks，33 executed）；日志 [rerun2-build.log](../../example/tool/coverage_evidence/rerun2-build.log)。
- 隔离applicationId：`com.icodejoo.mova.mova_example.coverage`。未替换原示例包。
- 复用上一轮严格LFS哈希核对重打包代码；zipalign后以既有 `C:/Users/jelon/.android/debug.keystore` 重签，apksigner v2/v3校验通过；`adb install -r`成功。
- 证书SHA256：`c0f7b57aa2f5478d9a5977b2ae18fa15a3ec13a620004429a9f67ffc3638c2e3`。
- 安装前lastUpdateTime为`2026-10-27 19:12:43`，本轮为`2026-10-27 21:09:46`；运行页SERVER返回`build=rerun2-20261027`。
- 原始Gradle APK SHA256：`88843bec4ef300e5be4e8a9a17a165079b592c94770ded55b92ce0c1d755861d`。
- 重签APK与设备安装后拉回的base.apk SHA256完全相同：`27c99f74496bf246a79a0b16ff93d649c1657ceebd612292a229607aa536096a`。
- 运行时库来源engine.dart SHA256：`0074902d03ec873ace9e91d8e77757c172892e0eea8f874aecf9ea83805fe6ce`；收尾一致，本轮未临时改动库文件。
- 清单与安装证据：[rerun2-build-manifest.json](../../example/tool/coverage_evidence/rerun2-build-manifest.json)、[rerun2-install.log](../../example/tool/coverage_evidence/rerun2-install.log)、[rerun2-certificate.txt](../../example/tool/coverage_evidence/rerun2-certificate.txt)、[rerun2-package-after.txt](../../example/tool/coverage_evidence/rerun2-package-after.txt)、[rerun2-start.json](../../example/tool/coverage_evidence/rerun2-start.json)。

## F3/A17 计数、判据与复现

| 场景 | 原始尝试 | 不满足>=8s而剔除 | 有效次数 | 通过 | 失败 | 最低有效target |
|---|---:|---:|---:|---:|---:|---:|
| cutover长进程首批 | 100 | 3 | 97 | 92 | 5 | 8103ms |
| cutover补跑 | 20 | 0 | 20 | 20 | 0 | 8103ms |
| 普通引擎播放 | 30 | 0 | 30 | 26 | 4 | 8023ms |
| 普通引擎暂停 | 30 | 0 | 30 | 27 | 3 | 8063ms |
| 合计 | 180 | 3 | **177** | **165** | **12** | >=8000ms |

- 首批cutover的run55/67/97在前次失败后的seek复位竞争中target读回0；页面原始pass=true被审计否决，三次仅保留原始证据，不计有效成功/失败，也不计要求次数。补跑20次全有效且全通过，cutover累计有效117次，满足至少100次；普通/暂停各30次满足要求。早期执行检查点中的148/160是原始计数，以本节有效数为准。
- 同一40s本地HLS VOD，18084提供`example/tool/rerun-sources/hls/master.m3u8`及high/low；交替360p/180p，真实MovaPlayer挂树。代理`MovaCutoverConfig(enabled:true)`；切档经代理switchQuality，未用cutoverTo代替。
- target使用切档前mpv `time-pos`，有效样本必须>=8s；原生位置>20s或失败后<8s时seek回9s，避开EOF。同步等待Player进度与原生读回相差<=100ms。三次入组竞争已明确剔除。
- 每次保存target、档位、path、全部原生RESTART序列、landed、continued、pause，以及EVENT/duration、Player原生progress、实际内核seek调用/返回。`RetestKernel`只在验证页继承并观测原实现，没有改动lib。
- landed取RESTART序列中首个target±500ms读数；播放态continued必须由mpv time-pos实际增加>=250ms且pause=no，暂停态须保持target±500ms且pause=yes。所有通过项另核对原生path为目标档位。原生落点等待/继续推进各6s截止只防挂死，未用墙钟推算播放进度。
- 全部原始尝试：[rerun2-hls-cutover.json](../../example/tool/coverage_evidence/rerun2-hls-cutover.json)、[rerun2-hls-normal.json](../../example/tool/coverage_evidence/rerun2-hls-normal.json)、[rerun2-hls-paused.json](../../example/tool/coverage_evidence/rerun2-hls-paused.json)、[rerun2-hls-cutover-extra.json](../../example/tool/coverage_evidence/rerun2-hls-cutover-extra.json)；各自包含本进程累计历史，审计按最后BEGIN划分本组。
- 逐次审计：[rerun2-hls-audit.json](../../example/tool/coverage_evidence/rerun2-hls-audit.json)；12次失败完整EVENT时间线合集：[rerun2-hls-failures.json](../../example/tool/coverage_evidence/rerun2-hls-failures.json)。每次失败还独立保存下表链接中的完整未筛选时间线。

最小功能复现：启动本轮release页→`new case=hls cutover=true count=100`→等原生进度>=8s→交替360p/180p。首个失败为首批cutover run42（第43次），此前没有失败后的复位：target19783ms，duration已40000ms，真实seek调用19783ms后RESTART仍[23,23]，continued4423ms。普通引擎和暂停态也能复现，无需PiP、小窗或其他UI动作。完整驱动：`python example/tool/rerun2_run.py hls`（会依次跑100/30/30）；同入口可用`coverage_device.py new --arg case=hls --arg cutover=true --arg count=100`。

首个失败关键时间线（ms为该app进程单调事件时间）：

| 事件时间ms | 实际事件/原生读回 |
|---:|---|
| 95086 | switch→360p，target=19783，streamPosition=19783，pause=no |
| 95187 | MovaDurationChange(0) |
| 95200 | MovaQualityChange(360p) |
| 95551 | MovaDurationChange(40000) |
| 95693 | MovaSizeChange(640×360) |
| 95746 | KERNEL_SEEK_CALL(19783)；首个RESTART读回23ms |
| 96247 | KERNEL_SEEK_RETURN(19783) |
| 96349 | MovaDurationChange(40007) |
| 96764 | 第二个RESTART仍23ms |
| 101217 | landed=-1，continued=4423，pause=no，FAIL |

这证实修复后仍有“seek确实调用，但RESTART仍停23ms并从头推进”的残余路径。另有一次未观察到换档续播seek，一次先到目标又回到23ms。上述为事件观察，不能据此断言新的根因已经定位。normal run10处于前次失败后的复位竞争，原生最终path仍low而目标为high，且continued不足，明确计失败，不把早期9023ms的RESTART误记为通过。

### 所有失败与完整时间线索引

run为从0起的轮次；target/RESTART/landed/continued单位均ms；`landed=-1`表示没有目标附近RESTART。每个JSON包含该次从HLS_SWITCH到HLS_RESULT之间所有EVENT、duration、progress、seek调用/返回和RESTART；原始整组文件保留前后上下文。

| 场景/run | target | 全部RESTART | landed | continued / pause | 实际seek目标 | 完整时间线 |
|---|---:|---|---:|---|---|---|
| cutover/42 | 19783 | [23, 23] | -1 | 4423 / no | 19783 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-cutover-42.json) |
| cutover/43 | 9000 | [23] | -1 | 4943 / no | 未观察到调用 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-cutover-43.json) |
| cutover/54 | 11863 | [23, 23] | -1 | 4543 / no | 11863 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-cutover-54.json) |
| cutover/66 | 11743 | [23, 23] | -1 | 4543 / no | 11743 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-cutover-66.json) |
| cutover/96 | 17103 | [23, 23] | -1 | 4663 / no | 17103 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-cutover-96.json) |
| normal/9 | 10743 | [23, 23] | -1 | 4943 / no | 10743 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-normal-9.json) |
| normal/10 | 9023 | [9023, 23, 23, 23] | 9023 | 3623 / no | 9000, 9000 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-normal-10.json) |
| normal/17 | 10903 | [23, 23] | -1 | 4823 / no | 10903 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-normal-17.json) |
| normal/23 | 10783 | [23, 23] | -1 | 4863 / no | 10783 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-normal-23.json) |
| paused/7 | 8063 | [23, 23] | -1 | 23 / yes | 8063 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-paused-7.json) |
| paused/18 | 9023 | [23, 23] | -1 | 23 / yes | 9023 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-paused-18.json) |
| paused/20 | 9023 | [23, 23] | -1 | 23 / yes | 9023 | [全部事件](../../example/tool/coverage_evidence/rerun2-failure-paused-20.json) |

## 与上一轮对比

| 项目 | 上一轮Android | 本轮Android | 对比结论 |
|---|---|---|---|
| F3/A17 | 39/40，1次FAIL；target10183→RESTART[23,23] | 165/177有效通过，12次FAIL；仍有[23,23]、无seek、到目标后回零等形态 | **仍未修复到可验收**；两轮样本量/组别与观测截止不同，不能把比例直接当性能退化结论 |
| A15 | mini=false但controller showing=true/persistent，展开残留 | 进入PiP即api=null/showing=false/none，展开保持 | FAIL→PASS |
| F5 | MiniHost/PiP互斥衔接失败 | enterPip返回true、原生pinned、展开复位，无App小窗残留 | FAIL→PASS |
| A23 | 两种引擎二次dispose抛[Player] has been disposed | 两种引擎二次均正常，4/4调用无异常 | FAIL→PASS |
| A12 | -1/0原值保留，画面可塌缩；100接受 | -1/0/NaN均1.0且正常显示；100保持100 | 下限保护FAIL→PASS，100行为保持 |

上一轮依据：`doc/plans/2026-10-27-device-coverage-rerun.md`及其rerun-*原始证据。Windows复测1516全绿、A23/A12 PASS与本轮一致；Windows无法复现F3竞态，本轮Android已实际复现，不能用Windows结果覆盖本轮FAIL。本轮不改库、不做forcePark=false对照构建。

## 最终设备状态与工作区范围

- 起测与收尾都确认`isKeyguardShowing=false`、`mScreenOnFully=true`；未解锁设备、未锁屏硬跑。
- 隔离测试包已`am force-stop`，`pidof`为空；USB常亮已恢复**7**，媒体音量speaker/streamVolume为**6/20**。
- 本次自启18080/18084两个HTTP源进程已结束，收尾检查这两个端口无监听；未停止原有adb转发及其他应用/进程。
- 完整最终设备状态：[rerun2-final-state.json](../../example/tool/coverage_evidence/rerun2-final-state.json)、[rerun2-final-window.txt](../../example/tool/coverage_evidence/rerun2-final-window.txt)、[rerun2-final-audio.txt](../../example/tool/coverage_evidence/rerun2-final-audio.txt)、[rerun2-final-power.txt](../../example/tool/coverage_evidence/rerun2-final-power.txt)、[rerun2-final-pid.txt](../../example/tool/coverage_evidence/rerun2-final-pid.txt)。
- 修改仅为本报告、`example/lib/main_coverage_api.dart`、`example/lib/verify_auto/coverage_new.dart`及`example/tool/rerun2_*.py`验证脚本；证据均`example/tool/coverage_evidence/rerun2-*`。未执行git commit/stash/reset/checkout，未触碰../dioman。
- `engine.dart`、`test/core/engine_test.dart`、`mini.dart`的本轮观测哈希与收尾逐项一致，原工作区改动保留。[rerun2-source-hashes.json](../../example/tool/coverage_evidence/rerun2-source-hashes.json)；本轮没有临时修改或换行转换库文件。

- 最终报告检查点：已从原始事件独立复算177个有效样本，12个失败各自完整时间线已保存；A15/F5、A23、A12逐值/逐阶段审计与截图检查完毕，设备收尾状态已确认。

- 交付检查点：报告全部证据链接存在、12份失败独立时间线齐全，engine哈希再次一致，18080/18084监听0；范围核查归档 rerun2-final-review.json。
