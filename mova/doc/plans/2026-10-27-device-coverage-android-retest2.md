# Android F3/A17 第二层修复复测（2026-10-27）

- 开始前置检查：已阅读上轮 F3/A17 全节及失败索引；读取锁屏、亮屏、USB常亮与媒体音量，前置条件不符立即停下，不尝试解锁。

- 前置检查点：allowed=True；USB常亮=7；音量原始证据 rerun3-preflight.audio.txt。

- 开始基线 analyze：执行 flutter analyze lib test，记录实际数字与完整输出。

- analyze 检查点：exit=0；完整日志 rerun3-analyze.log。

- 开始基线 test：执行 flutter test，记录实际数字与完整输出。

- 开始准备验证构建：仅更新验证页 SERVER 标记为 rerun3；复制上轮构建/安装/驱动/收尾脚本到 rerun3，保留判据与观测窗口，cutover 先跑160次以覆盖可能剔除，普通/暂停各60次。

- test 检查点：exit=0；完整日志 rerun3-test.log。

- 基线最终检查点：flutter analyze lib test 为0 issues、exit 0；flutter test 1517/1517全绿、exit 0；起测媒体 STREAM_MUSIC speaker=6/20。

- 开始 release 构建：沿用 coverage.init.gradle 隔离 applicationId 与 arm64 原生依赖，Gradle assembleRelease 编译最新工作区验证页与库代码，保存 rerun3-build.log。

- 构建检查点：assembleRelease exit 0，BUILD SUCCESSFUL in 44s；777 tasks，25 executed；完整日志 rerun3-build.log。

- 开始重打包与安装：从本轮 Gradle APK 提取并核对原生库，zipalign 后使用既有 debug.keystore 重签；安装前后记录证书、SHA256 与 lastUpdateTime。

- 构建安装检查点：新 release 安装成功，设备拉回 APK SHA256 与重签包完全一致；lastUpdateTime/证书/源码哈希见 rerun3-build-manifest.json、rerun3-package-after.txt、rerun3-certificate.txt。

- 开始本地源与页面启动：复用已存在同一 VOD/HLS 素材，18080 提供 rerun-sources，18084 提供其 hls/high、low；设置 adb reverse 并确认新页面构建标记。

- 源/启动检查点：新页面 SERVER build=rerun3-20261027，双端口服务已启动并保存 owned PIDs；后续仅使用 rerun3 证据。

- 开始 rerun3-hls-cutover：{'group': 'new', 'case': 'hls', 'cutover': 'true', 'count': '160'}；保留真实事件、原生读回及画面，以对应判据核验。

- cutover 中途检查点：已完成74次，页面失败3；seek次数分布{1: 73, 0: 1}；target<8s样本[67]。最终以独立审计为准。

- rerun3-hls-cutover 检查点：status=done，本轮切档 160，失败 15，脚本异常 0；证据 rerun3-hls-cutover.json/.png/.logcat.txt。

- 开始 rerun3-hls-normal：{'group': 'new', 'case': 'hls', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- cutover 初审检查点：160次中155有效、140通过/15失败，run67/111/139/155/159均target=0剔除。有效seek分布0/1/2/3次=1/153/1/0；双调用为run128，首个目标落点后夹入ABR再次切到low、最终失败，非第二层重发成功。继续普通/暂停组。

- rerun3-hls-normal 检查点：status=done，本轮切档 60，失败 15，脚本异常 0；证据 rerun3-hls-normal.json/.png/.logcat.txt。

- 开始 rerun3-hls-paused：{'group': 'new', 'case': 'hls', 'paused': 'true', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- 普通播放首批初审检查点：60原始尝试，53有效、38通过/15失败；7个target<8s沿用上轮规则剔除。暂停组完成后补跑普通，保留独立批次，不改变判据。

- rerun3-hls-paused 检查点：status=done，本轮切档 60，失败 28，脚本异常 0；证据 rerun3-hls-paused.json/.png/.logcat.txt。

- 开始 rerun3-hls-normal-extra：{'group': 'new', 'case': 'hls', 'count': '20'}；保留真实事件、原生读回及画面，以对应判据核验。

- 暂停组初审检查点：60原始尝试，58有效、31通过/27失败；run7/27的target=23ms剔除。run1确有重发成功：target8063，seek570114ms返回570547ms，572194ms再次调用/返回；RESTART序列[23,23,8063]，pause=yes且continued8063。有效seek分布0/1/2/3次=9/48/1/0；保留完整时间线供最终审计。

- rerun3-hls-normal-extra 检查点：status=done，本轮切档 20，失败 2，脚本异常 0；证据 rerun3-hls-normal-extra.json/.png/.logcat.txt。

- 开始 rerun3-hls-paused-extra：{'group': 'new', 'case': 'hls', 'count': '10', 'paused': 'true'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun3-hls-paused-extra 检查点：status=done，本轮切档 10，失败 2，脚本异常 0；证据 rerun3-hls-paused-extra.json/.png/.logcat.txt。

- 开始最终独立审计：合并原始组与补跑组，按target>=8s计算三个场景有效数；逐次复算RESTART首个落点、原生续播/暂停与目标path，统计seek调用分布、同目标重发成功，导出每个失败完整时间线并标记ABR。

- HLS独立审计检查点：逐次复算target、交替档位、完整RESTART序列、落点与原生continued判据均一致；统计 rerun3-hls-summary.json，逐次表 rerun3-hls-audit.json，失败完整时间线 rerun3-hls-failures.json。

- 开始收尾：经现有验证页恢复媒体音量30%=6/20，USB常亮恢复7，force-stop隔离包；保留原生设置、进程与屏幕状态，再结束仅本次启动的两个源进程。

- 收尾检查点：隔离包pid为空（force-stop），USB常亮=7，媒体streamVolume=6/20；仍isKeyguardShowing=false、mScreenOnFully=true；本次两个源PID已结束，engine.dart哈希与安装时一致。证据 rerun3-final-state.json / rerun3-final-*.txt。

- 开始交付核验：核对源端口已关闭、受保护源码哈希保持、61份有效失败与15份剔除上下文及2份重发成功完整时间线存在；生成最终报告和证据链接检查。


## 基线与结果

设备 `7NQBB23606003715`，Android release，自行执行，只复测 F3/A17。

- `flutter analyze lib test`：0 issues，exit 0；[rerun3-analyze.log](../../example/tool/coverage_evidence/rerun3-analyze.log)。
- `flutter test`：1517/1517 全绿，exit 0；[rerun3-test.log](../../example/tool/coverage_evidence/rerun3-test.log)。
- F3/A17：有效 **295** 次，**234 通过 / 61 失败**；剔除 15 次，不计成败。

| 场景 | 原始尝试 | 有效 | 通过 | 失败 | 剔除 | 最低有效 target |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 160 | 155 | 140 | 15 | 5 | 8103ms |
| 普通播放 | 80 | 72 | 55 | 17 | 8 | 8063ms |
| 暂停态 | 70 | 68 | 39 | 29 | 2 | 8063ms |
| 合计 | 310 | 295 | 234 | 61 | 15 | >=8000ms |

各批次有效数（补跑独立记账）：{'cutover': 155, 'normal': 53, 'paused': 58, 'normal-extra': 19, 'paused-extra': 10}。

原始整组证据：[rerun3-hls-cutover.json](../../example/tool/coverage_evidence/rerun3-hls-cutover.json)、[rerun3-hls-normal.json](../../example/tool/coverage_evidence/rerun3-hls-normal.json)、[rerun3-hls-paused.json](../../example/tool/coverage_evidence/rerun3-hls-paused.json)、[rerun3-hls-normal-extra.json](../../example/tool/coverage_evidence/rerun3-hls-normal-extra.json)、[rerun3-hls-paused-extra.json](../../example/tool/coverage_evidence/rerun3-hls-paused-extra.json)。各文件含累计历史，审计仅取最后 BEGIN 之后。独立逐次复算：[rerun3-hls-audit.json](../../example/tool/coverage_evidence/rerun3-hls-audit.json)；汇总：[rerun3-hls-summary.json](../../example/tool/coverage_evidence/rerun3-hls-summary.json)。

## 判据与 seek 次数

沿用上轮同一 40s HLS VOD、18084 high/low，交替 360p/180p；真实 MovaPlayer 挂树，代理 enabled=true，经 switchQuality 切档。target 为切档前 mpv time-pos，必须 >=8000ms；远离 EOF 的复位仍 seek 9s，并等 Player 进度与原生读回差 <=100ms。未改动验证页 HLS 实现、ABR 配置或观测截止。

landed 为完整 RESTART 序列中首个 target±500ms；播放态 continued 由 mpv time-pos 实际增加 >=250ms 且 pause=no；暂停态保持 target±500ms 且 pause=yes；通过项同时核对原生 path 为目标档位。落点/继续推进各 6s 截止仅防挂死，不按墙钟推算位置。

每次 seekCount 统计 HLS_SWITCH 到 HLS_RESULT 之间 RetestKernel 的 KERNEL_SEEK_CALL，排除切档前复位；调用与返回、EVENT、duration、NATIVE_PROGRESS、全部 RESTART 原样保留。分布仅计有效样本，0次或超过3次另外保留，不能混入1次。

| 场景 | 0次 | 1次 | 2次 | 3次 | 超过3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 1 | 153 | 1 | 0 | 0 | 0 |
| 普通播放 | 1 | 70 | 1 | 0 | 0 | 1 |
| 暂停态 | 9 | 58 | 1 | 0 | 0 | 1 |
| 合计 | 11 | 281 | 3 | 0 | 0 | 2 |

“靠重发成功”共 **2** 次：同目标再次 KERNEL_SEEK_CALL 之前未出现目标附近 RESTART，之后首次落点并满足最终续播判据。该定义描述事件顺序；没有关闭重发的对照构建，不能证明每次重发都具有反事实必要性。

本轮观察到第二层重发实际参与成功；结合仍存在的失败，结论为重发有生效样本，但尚未消除竞态。

| 场景/run（从0起） | target | seek调用(ms:target) | RESTART | 完整时间线 |
|---|---:|---|---|---|
| paused/1 | 8063 | 570114:8063, 572194:8063 | [23, 23, 8063] | [全部事件](../../example/tool/coverage_evidence/rerun3-retry-success-paused-1.json) |
| normal-extra/14 | 9000 | 806498:9000, 808411:9000 | [23, 23, 9063] | [全部事件](../../example/tool/coverage_evidence/rerun3-retry-success-normal-extra-14.json) |

多次调用但不能记为重发成功的样本：[('cutover', 128, False, True)]（依次为场景、run、pass、ABR）。例如 cutover/128 两次调用间隔735ms，首次RESTART已到10223ms；随后ABR从360p降至180p并发生第二次seek，最终low档从零推进而失败，不属于1.5s校验重发成功。

## 剔除、失败与复现

- 剔除 cutover/67：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-cutover-67.json)。
- 剔除 cutover/111：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-cutover-111.json)。
- 剔除 cutover/139：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-cutover-139.json)。
- 剔除 cutover/155：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-cutover-155.json)。
- 剔除 cutover/159：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-cutover-159.json)。
- 剔除 normal/11：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-11.json)。
- 剔除 normal/15：target=23ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-15.json)。
- 剔除 normal/17：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-17.json)。
- 剔除 normal/29：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-29.json)。
- 剔除 normal/33：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-33.json)。
- 剔除 normal/45：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-45.json)。
- 剔除 normal/49：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-49.json)。
- 剔除 paused/7：target=23ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-paused-7.json)。
- 剔除 paused/27：target=23ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-paused-27.json)。
- 剔除 normal-extra/17：target=0ms，不满足>=8s，与上轮同规则，不计通过/失败；[包含前次失败后复位的完整上下文](../../example/tool/coverage_evidence/rerun3-excluded-normal-extra-17.json)。

即使处于前次失败后的复位上下文，只要切档target>=8s，仍保留为有效样本并按原生判据计成败；例如暂停组存在RESTART短暂等于目标但最终time-pos无有效值（-1000ms）的样本，计失败。只按上轮target<8s规则剔除。

61个有效失败中：49个仅调用1次seek、11个零调用、1个双调用（ABR再切档）；51个没有目标附近RESTART，10个曾到目标附近但最终续播/暂停条件失败。失败内夹有ABR的样本为cutover/63、cutover/128、normal/57，其余58个失败时间线未出现MovaAbrDownShift。

剔除完整索引：[rerun3-hls-excluded.json](../../example/tool/coverage_evidence/rerun3-hls-excluded.json)；失败完整 EVENT/duration/RESTART/seek 调用与返回合集：[rerun3-hls-failures.json](../../example/tool/coverage_evidence/rerun3-hls-failures.json)。

各场景首次失败（均早于本组首次失败后复位）：

| 场景/run | target | RESTART | seek次数 |
|---|---:|---|---:|
| cutover/62 | 14423 | [23, 23] | 1 |
| normal/7 | 10583 | [23, 23] | 1 |
| paused/3 | 8063 | [23, 23] | 1 |

| 场景/run | 有效 | target | RESTART | landed / continued / pause | ABR夹入 | 完整时间线 |
|---|---|---:|---|---|---|---|
| cutover/62 | True | 14423 | [23, 23] | -1 / 4663 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-62.json) |
| cutover/63 | True | 9000 | [151, 23] | -1 / 4823 / no | True | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-63.json) |
| cutover/66 | True | 9583 | [23, 23] | -1 / 4383 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-66.json) |
| cutover/97 | True | 17343 | [23, 23] | -1 / 4903 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-97.json) |
| cutover/110 | True | 12423 | [23, 23] | -1 / 4863 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-110.json) |
| cutover/113 | True | 9303 | [23, 23] | -1 / 4783 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-113.json) |
| cutover/115 | True | 9343 | [23, 23] | -1 / 4743 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-115.json) |
| cutover/119 | True | 9943 | [23, 23] | -1 / 4703 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-119.json) |
| cutover/123 | True | 9983 | [23, 23] | -1 / 4663 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-123.json) |
| cutover/128 | True | 10223 | [155, 10223, 23, 23] | 10223 / 4983 / no | True | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-128.json) |
| cutover/135 | True | 10903 | [23, 23] | -1 / 4743 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-135.json) |
| cutover/138 | True | 9583 | [23, 23] | -1 / 4983 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-138.json) |
| cutover/147 | True | 11223 | [23, 23] | -1 / 4983 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-147.json) |
| cutover/154 | True | 10823 | [23, 23] | -1 / 4743 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-154.json) |
| cutover/158 | True | 9823 | [23, 23] | -1 / 4823 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-cutover-158.json) |
| normal/7 | True | 10583 | [23, 23] | -1 / 4903 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-7.json) |
| normal/10 | True | 9623 | [23, 23] | -1 / 4703 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-10.json) |
| normal/13 | True | 9303 | [23, 23] | -1 / 4863 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-13.json) |
| normal/14 | True | 9000 | [23, 23] | -1 / 4903 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-14.json) |
| normal/16 | True | 9000 | [23, 23] | -1 / 4743 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-16.json) |
| normal/27 | True | 11583 | [23, 23] | -1 / 4703 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-27.json) |
| normal/28 | True | 9000 | [23, 23] | -1 / 4743 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-28.json) |
| normal/32 | True | 9943 | [23, 63] | -1 / 4943 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-32.json) |
| normal/35 | True | 9303 | [23, 23] | -1 / 4743 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-35.json) |
| normal/44 | True | 11423 | [23, 23] | -1 / 4783 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-44.json) |
| normal/48 | True | 9663 | [23, 23] | -1 / 4743 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-48.json) |
| normal/51 | True | 9303 | [23, 23] | -1 / 4463 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-51.json) |
| normal/55 | True | 10023 | [23, 103] | -1 / 4863 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-55.json) |
| normal/56 | True | 9000 | [23, 23] | -1 / 4703 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-56.json) |
| normal/57 | True | 9000 | [23, 23] | -1 / 4823 / no | True | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-57.json) |
| paused/3 | True | 8063 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-3.json) |
| paused/4 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-4.json) |
| paused/5 | True | 9000 | [9000] | 9000 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-5.json) |
| paused/6 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-6.json) |
| paused/8 | True | 9000 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-8.json) |
| paused/9 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-9.json) |
| paused/18 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-18.json) |
| paused/20 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-20.json) |
| paused/21 | True | 9000 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-21.json) |
| paused/22 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-22.json) |
| paused/25 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-25.json) |
| paused/26 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-26.json) |
| paused/28 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-28.json) |
| paused/29 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-29.json) |
| paused/33 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-33.json) |
| paused/35 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-35.json) |
| paused/37 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-37.json) |
| paused/39 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-39.json) |
| paused/42 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-42.json) |
| paused/43 | True | 9023 | [9023] | 9023 / -1000 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-43.json) |
| paused/46 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-46.json) |
| paused/48 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-48.json) |
| paused/50 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-50.json) |
| paused/53 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-53.json) |
| paused/54 | True | 9000 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-54.json) |
| paused/56 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-56.json) |
| paused/59 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-59.json) |
| normal-extra/13 | True | 12303 | [23, 23] | -1 / 4863 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-extra-13.json) |
| normal-extra/16 | True | 9743 | [63, 63] | -1 / 4623 / no | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-normal-extra-16.json) |
| paused-extra/1 | True | 8343 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-extra-1.json) |
| paused-extra/6 | True | 9023 | [23, 23] | -1 / 23 / yes | False | [全部事件](../../example/tool/coverage_evidence/rerun3-failure-paused-extra-6.json) |

完整复测驱动：`python example/tool/rerun3_run.py hls`（依次160/60/60）；补跑命令：`python example/tool/rerun3_extra.py normal 20 extra`、`python example/tool/rerun3_extra.py paused 10 extra`。

最小功能复现：启动本轮 release 页→new case=hls（相应 cutover=true 或 paused=true）→原生进度>=8s→交替360p/180p；以上首个失败的 run 与完整时间线可定位本轮实际复现。独立暂停补跑也在run1（第2次切档）失败，target8343ms、RESTART[23,23]、continued23ms、pause=yes；此前run0通过，可用验证页new case=hls paused=true count=10重复尝试。

首个失败关键时间线（ms为应用单调事件时间；完整文件保留全部未筛选事件）：

| ms | 事件 |
|---:|---|
| 125153 | HLS_SWITCH {'run': 62, 'cutover': True, 'paused': False, 'target': 14423, 'quality': '360p', 'uri': 'http://127.0.0.1:18084/high/index.m3u8', 'streamPosition': 14343, 'pause': 'no'} |
| 125160 | MovaDurationChange {'duration': 0} |
| 125673 | MovaDurationChange {'duration': 40000} |
| 125766 | KERNEL_SEEK_CALL {'target': 14343} |
| 125766 | HLS_RESTART {'run': 62, 'position': 23, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'pause': 'no'} |
| 126293 | KERNEL_SEEK_RETURN {'target': 14343} |
| 126508 | MovaDurationChange {'duration': 40007} |
| 126542 | HLS_RESTART {'run': 62, 'position': 23, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'pause': 'no'} |
| 131241 | HLS_RESULT {'run': 62, 'cutover': True, 'paused': False, 'target': 14423, 'landed': -1, 'continued': 4663, 'restarts': [23, 23], 'resumed': False, 'continuedOk': False, 'pass': False, 'pause': 'no', 'path': 'http://127.0.0.1:18084/high/index.m3u8'} |

进度流中的短暂目标值不视为原生落点；例如首个失败可从 NATIVE_PROGRESS 核对瞬态目标值后回零，验收仍以原生 RESTART 与 time-pos 为准。未直接观测引擎私有 _pendingSeekTarget，本轮不将未重发的内部原因当作已证实根因。

ABR MovaAbrDownShift 出现于有效样本：{'cutover': [63, 128], 'normal': [57], 'paused': [], 'normal-extra': [], 'paused-extra': []}；按每次切档列出，不将 EVENT/HLS_EVENT 的同一事件重复计数。

## 新包与上轮对比

- 上轮有效177次，165通过/12失败（cutover 112/117、普通26/30、暂停27/30）；本轮 234/295，失败 61。两轮样本数量不同，只报告本轮是否再现，不能据有限样本宣称竞态绝不出现。
- 本轮重建日志 [rerun3-build.log](../../example/tool/coverage_evidence/rerun3-build.log)；隔离包 `com.icodejoo.mova.mova_example.coverage`；原生库按 LFS SHA256核对、zipalign、既有debug证书重签，apksigner v2/v3校验通过。
- 安装前 lastUpdateTime=2026-10-27 21:09:46；安装后 `lastUpdateTime=2026-10-27 21:27:08`；SERVER build=rerun3-20261027。
- Gradle APK SHA256：`5146bdaf5ab43a1b55583cd14a2bcacf99522d4b8b4be76ebaa94697f339450e`。
- 重签APK与设备拉回APK一致：`f51f3b4bd4245b3bc49c1e8c3d041aaeb38a6b00ae83c2d155d7a608e3bbafba`。
- engine.dart SHA256：`4870693f841f85e512d2ac0d649e18215cc11d9176125ac961559a383b00d68c`，与起测和收尾一致，未修改或转换CRLF。
- [rerun3-build-manifest.json](../../example/tool/coverage_evidence/rerun3-build-manifest.json)、[rerun3-package-before.txt](../../example/tool/coverage_evidence/rerun3-package-before.txt)、[rerun3-package-after.txt](../../example/tool/coverage_evidence/rerun3-package-after.txt)、[rerun3-certificate.txt](../../example/tool/coverage_evidence/rerun3-certificate.txt)、[rerun3-start.json](../../example/tool/coverage_evidence/rerun3-start.json)。

## 最终设备状态与范围

起测与收尾均 isKeyguardShowing=false、mScreenOnFully=true；未尝试解锁。USB常亮起测7，已恢复7；媒体 STREAM_MUSIC speaker 起测6/20，已恢复6/20。隔离包已 force-stop，pid为空；本次启动的18080/18084源进程已关闭，端口无监听。[rerun3-final-state.json](../../example/tool/coverage_evidence/rerun3-final-state.json)、[rerun3-final-window.txt](../../example/tool/coverage_evidence/rerun3-final-window.txt)、[rerun3-final-audio.txt](../../example/tool/coverage_evidence/rerun3-final-audio.txt)、[rerun3-final-power.txt](../../example/tool/coverage_evidence/rerun3-final-power.txt)、[rerun3-final-review.json](../../example/tool/coverage_evidence/rerun3-final-review.json)。

仅改验证页构建标记、example/tool/rerun3_*.py及本报告；证据前缀rerun3-。未改lib/、test/、packages/；原有未提交改动保留，未执行git commit/stash/reset/checkout，未触碰../dioman或另一会话的矩阵文件。受保护源码哈希在起测与收尾核对一致。

- 交付检查点：295有效样本与页面判定逐项一致，61份失败、15份剔除上下文、2份重发成功完整时间线及报告所有证据链接已核验；受保护源码哈希无变化，设备收尾状态已确认。
