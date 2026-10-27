# Android F3/A17 第三轮修复复测（2026-10-27）

- 开始前置检查：先读取设备锁屏、亮屏、USB常亮和媒体音量；不满足条件立即停止，不尝试解锁。

- 前置检查点：allowed=True；USB常亮=7；媒体原始证据 rerun4-preflight.audio.txt。

- 开始基线 analyze：执行 flutter analyze lib test，记录实际数字与完整输出。

- analyze 检查点：exit=0；完整日志 rerun4-analyze.log。

- 开始基线 test：执行 flutter test，记录实际数字与完整输出。

- 开始修验证页：切档后等待目标 MovaQualityChange、新档位正时长与目标path后才开始落点/续播窗口；门槛及各观测仍以6s防挂死；保留旧RESTART但不用于落点，提前结果标 harness-invalid。复制rerun3流程为rerun4，未改判据与ABR。

- test 检查点：exit=0；完整日志 rerun4-test.log。

- 验证页检查点：dart analyze example/lib/verify_auto/coverage_new.dart 无问题；已记录 HLS_VARIANT_READY、逐个RESTART的eligible及HLS_RESULT.gateMs/harnessInvalid，原始RESTART不丢弃。

- 基线最终检查点：flutter analyze lib test 0 issues、exit 0；flutter test 1517/1517全绿、exit 0；起测媒体 STREAM_MUSIC speaker=6/20。

- 开始 release 构建：沿用coverage.init.gradle隔离applicationId及arm64依赖，用最新工作区和修复后的验证页执行assembleRelease，完整日志rerun4-build.log。

- 构建检查点：assembleRelease exit 0；完整日志rerun4-build.log。下一步沿用原生库哈希核对、zipalign和debug证书重签、安装流程。

- 开始重打包与安装：从本轮 Gradle APK 提取并核对原生库，zipalign 后使用既有 debug.keystore 重签；安装前后记录证书、SHA256 与 lastUpdateTime。

- 构建安装检查点：新 release 安装成功，设备拉回 APK SHA256 与重签包完全一致；lastUpdateTime/证书/源码哈希见 rerun4-build-manifest.json、rerun4-package-after.txt、rerun4-certificate.txt。

- 开始本地源与页面启动：复用已存在同一 VOD/HLS 素材，18080 提供 rerun-sources，18084 提供其 hls/high、low；设置 adb reverse 并确认新页面构建标记。

- 源/启动检查点：新页面 SERVER build=rerun4-20261027，双端口服务已启动并保存 owned PIDs；后续仅使用 rerun4 证据。

- 开始 rerun4-hls-cutover：{'group': 'new', 'case': 'hls', 'cutover': 'true', 'count': '160'}；保留真实事件、原生读回及画面，以对应判据核验。

- cutover中途检查点：前10次2个页面失败，首个run2 target8623ms，high门槛已完成但ABR夹入后path变low，计失败；已保存rerun4-first-failure-live.json。已观察到1.5s后再次内核seek，审计按QualityChange/ABR分割链以免把ABR额外调用算成重发。

- rerun4-hls-cutover 检查点：status=error，本轮切档 76，失败 15，脚本异常 1；证据 rerun4-hls-cutover.json/.png/.logcat.txt。

- 停止检查点：RuntimeError(('rerun4-hls-cutover', [{'ms': 259716, 'kind': 'SCRIPT_ERROR', 'group': 'new', 'error': 'TimeoutException: native condition', 'stack': '#0      nativeUntil (package:mova_example/verify_auto/coverage_new.dart:531)\n<asynchronous suspension>\n#1      hls (package:mova_example/verify_auto/coverage_new.dart:627)\n<asynchronous suspension>\n#2      runNew (package:mova_example/verify_auto/coverage_new.dart:28)\n<asynchronous suspension>\n#3      _CoverageHomeState.run (package:mova_example/main_coverage_api.dart:179)\n<asynchronous suspension>\n'}]))；若为锁屏立即停止，不解锁、不继续交互。

- 开始中断恢复：首批cutover已产出76个结果，run75目标流打开失败且无门槛，后续复位20s超时；保留原始批次与SCRIPT_ERROR，核对屏幕后重启同一隔离包，独立补跑cutover90、normal60、paused60，不覆盖旧证据。

- 恢复检查点：同一rerun4包已启动，继续独立补跑批次；首批SCRIPT_ERROR不隐去。

- 开始 rerun4-hls-cutover-extra：{'group': 'new', 'case': 'hls', 'cutover': 'true', 'count': '90'}；保留真实事件、原生读回及画面，以对应判据核验。

- 中断复核检查点：首批cutover 76个结果中75有效、61通过/14失败，run75无门槛且MovaErrorEvent=Failed to open low/index.m3u8；该剔除并不宣称原生打开失败由harness导致，异常另见rerun4-interrupted-session.json。旧9例均有旧path RESTART、无新档位正duration，见rerun4-prior-harness-review.json。受保护源码哈希仍一致；engine.dart为CRLF且无裸LF。

- rerun4-hls-cutover-extra 检查点：status=done，本轮切档 90，失败 12，脚本异常 0；证据 rerun4-hls-cutover-extra.json/.png/.logcat.txt。

- 开始 rerun4-hls-normal：{'group': 'new', 'case': 'hls', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun4-hls-normal 检查点：status=done，本轮切档 60，失败 12，脚本异常 0；证据 rerun4-hls-normal.json/.png/.logcat.txt。

- 开始 rerun4-hls-paused：{'group': 'new', 'case': 'hls', 'paused': 'true', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun4-hls-paused 检查点：status=done，本轮切档 60，失败 0，脚本异常 0；证据 rerun4-hls-paused.json/.png/.logcat.txt。

- 开始最终独立审计：暂停态60次已全通过；合并cutover首批及补跑、普通与暂停，逐次复算切档完成门槛、首个合格RESTART、原生continued/pause/path；分割ABR链统计真实重发、失败seek分布及3次尝试仍失败，完整保存失败与剔除上下文。

- 独立审计检查点：逐个复算目标档位门槛、eligible RESTART首个目标落点、原生continued/pause/path，与页面一致；失败、剔除上下文及重发成功完整事件已分别导出，详见rerun4-hls-summary/audit/failures/excluded/retry-successes.json。

- 开始收尾：经现有验证页恢复媒体音量30%=6/20，USB常亮恢复7，force-stop隔离包；保留原生设置、进程与屏幕状态，再结束仅本次启动的两个源进程。

- 收尾检查点：隔离包pid为空（force-stop），USB常亮=7，媒体streamVolume=6/20；仍isKeyguardShowing=false、mScreenOnFully=true；本次两个源PID已结束，engine.dart哈希与安装时一致。证据 rerun4-final-state.json / rerun4-final-*.txt。

- 开始交付核验：设备与源已收尾；将门槛前旧path候选与门槛后ABR降档读回分开，避免混称旧档位提前采样；重新导出审计并据此生成报告，校验所有证据链接、保护目录哈希与端口关闭状态。

- 独立审计检查点：逐个复算目标档位门槛、eligible RESTART首个目标落点、原生continued/pause/path，与页面一致；失败、剔除上下文及重发成功完整事件已分别导出，详见rerun4-hls-summary/audit/failures/excluded/retry-successes.json。


## 基线与 F3/A17 结果

设备 `7NQBB23606003715`，隔离 Android release 包；由当前 Codex 自行执行，无转派。

- `flutter analyze lib test`：0 issues、exit 0；[rerun4-analyze.log](../../example/tool/coverage_evidence/rerun4-analyze.log)。
- `flutter test`：**1517/1517 全绿**、exit 0；[rerun4-test.log](../../example/tool/coverage_evidence/rerun4-test.log)。
- 有效 **283**，通过 **245**，失败 **38**；剔除 3，不计成败。

| 场景 | 原始尝试 | 有效 | 通过 | 失败 | 剔除 | 其中harness-invalid |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 166 | 163 | 137 | 26 | 3 | 1 |
| 普通播放 | 60 | 60 | 48 | 12 | 0 | 0 |
| 暂停态 | 60 | 60 | 60 | 0 | 0 | 0 |
| 合计 | 286 | 283 | 245 | 38 | 3 | 1 |

| 批次 | 状态 | 已产出结果 | SCRIPT_ERROR |
|---|---|---:|---:|
| cutover | error | 76 | 1 |
| cutover-extra | done | 90 | 0 |
| normal | done | 60 | 0 |
| paused | done | 60 | 0 |

首批cutover/75目标流打开失败、无切档门槛，归harness-invalid；下一轮尚未发生HLS_SWITCH的9秒复位等待20秒后超时，仅记会话中断，不虚造一次切档样本。其余批次正常结束；此前已完成样本全部保留。

中断完整上下文：[rerun4-interrupted-session.json](../../example/tool/coverage_evidence/rerun4-interrupted-session.json)；原生打开失败是保留的异常事实，按未过门槛规则剔除不代表认定其由harness造成。

原始批次：[rerun4-hls-cutover.json](../../example/tool/coverage_evidence/rerun4-hls-cutover.json)、[rerun4-hls-cutover-extra.json](../../example/tool/coverage_evidence/rerun4-hls-cutover-extra.json)、[rerun4-hls-normal.json](../../example/tool/coverage_evidence/rerun4-hls-normal.json)、[rerun4-hls-paused.json](../../example/tool/coverage_evidence/rerun4-hls-paused.json)。每份取最后BEGIN之后，累计历史不重复计数。逐次表 [rerun4-hls-audit.json](../../example/tool/coverage_evidence/rerun4-hls-audit.json)；分批汇总 [rerun4-hls-summary.json](../../example/tool/coverage_evidence/rerun4-hls-summary.json)。

## 判据及验证页修正

沿用同一40s HLS VOD与18084 high/low，交替360p/180p，真实播放器挂树；cutover enabled=true，经switchQuality切档。target为切档前mpv time-pos，>=8000ms才有效；原生位置>20s或<8s时仍seek回9s，并等Player进度与原生差<=100ms。ABR配置未改。

播放与暂停统一先观测目标MovaQualityChange、duration>0且原生path等于目标URI，记录HLS_VARIANT_READY；随后开始观测。原始RESTART全部保留，eligible标记已过门槛且path为目标的读回。landed取这些RESTART中首个target±500ms；播放态mpv time-pos实际比landed增加>=250ms且pause=no；暂停态保持target±500ms且pause=yes；最终path还须为目标档位。门槛、落点和续播各保留6s防挂死截止，没有放宽500ms/250ms判据，也不按墙钟推算位置。

任何未观察到目标档位完成、或结果早于该时刻的样本均harness-invalid单列；target<8s沿用上轮复位竞争规则剔除。其余失败即使处在复位上下文或夹有ABR仍计失败，不为凑数改判据。

修验证页前后分开记账：rerun3有9个有效暂停失败为0次seek，其中9个曾将旧档位RESTART当成目标落点，符合上轮复盘的提前采样类型；本轮有效样本中同类型0个，结果早于切档完成/无门槛的harness-invalid共1个（已排除）。本轮抑制了3个样本中的旧path目标附近RESTART候选。两轮同时更改了库与验证页，不把全部改善归因于验证页，也未重跑旧验证页构建。

旧9例逐次延迟、错误RESTART path与duration复核：[rerun4-prior-harness-review.json](../../example/tool/coverage_evidence/rerun4-prior-harness-review.json)。

| 类型 | rerun3有效失败 | rerun4有效失败 |
|---|---:|---:|
| 仅1次seek且无目标落点 | 49 | 0 |
| 0次seek | 11 | 0 |
| 曾有目标落点但最终失败 | 10 | 2 |

## 内核 seek 分布与重发

每次统计HLS_SWITCH至HLS_RESULT间RetestKernel的KERNEL_SEEK_CALL，排除切档前复位；0次及>3次单列。靠重发成功：同一QualityChange/ABR分段内、同目标、调用间隔>=1.5s，首次合格落点发生在重发之后且最终通过。新QualityChange或ABR分割续播链，避免把ABR切档seek误当重发；该定义为事件顺序证据，没有关闭重发的反事实对照。

| 场景 | 0次 | 1次 | 2次 | 3次 | >3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 0 | 116 | 23 | 24 | 0 | 21 |
| 普通播放 | 0 | 42 | 6 | 10 | 2 | 6 |
| 暂停态 | 0 | 51 | 9 | 0 | 0 | 9 |
| 合计 | 0 | 209 | 38 | 34 | 2 | 36 |

本轮36个成功样本在重发之前没有合格RESTART，重发之后才落点并通过；不能把这些成功全部归于第一层。暂停态旧档位提前采样的9例类型未再现。全部38个有效失败均夹有ABR并最终path偏离请求档位；未再现无ABR的单次seek后一直停在23ms失败形态。整体仍未达到全通过验收，不能把ABR夹入失败忽略。

仍失败样本seek次数分布：{2: 2, 3: 34, 4: 2}。

| 仍失败场景 | 0次 | 1次 | 2次 | 3次 | >3次 |
|---|---:|---:|---:|---:|---:|
| cutover 代理 | 0 | 0 | 2 | 24 | 0 |
| 普通播放 | 0 | 0 | 0 | 10 | 2 |
| 暂停态 | 0 | 0 | 0 | 0 | 0 |

有效失败中，共36个样本切档窗口含>=3次调用；其中确认同一续播链共尝试3次（首发+2次重发）仍失败为0个：[]。总调用数可能含ABR二次切档，不能直接等同校验链3次。

靠重发成功 **36** 次，逐次完整时间线索引 [rerun4-hls-retry-successes.json](../../example/tool/coverage_evidence/rerun4-hls-retry-successes.json)；具体文件：[cutover/1](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-1.json)、[cutover/7](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-7.json)、[cutover/17](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-17.json)、[cutover/29](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-29.json)、[cutover/33](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-33.json)、[cutover/35](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-35.json)、[cutover/37](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-37.json)、[cutover/49](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-49.json)、[cutover/51](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-51.json)、[cutover/53](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-53.json)、[cutover/61](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-61.json)、[cutover-extra/19](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-19.json)、[cutover-extra/49](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-49.json)、[cutover-extra/51](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-51.json)、[cutover-extra/57](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-57.json)、[cutover-extra/59](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-59.json)、[cutover-extra/69](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-69.json)、[cutover-extra/71](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-71.json)、[cutover-extra/75](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-75.json)、[cutover-extra/79](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-79.json)、[cutover-extra/89](../../example/tool/coverage_evidence/rerun4-retry-success-cutover-extra-89.json)、[normal/1](../../example/tool/coverage_evidence/rerun4-retry-success-normal-1.json)、[normal/5](../../example/tool/coverage_evidence/rerun4-retry-success-normal-5.json)、[normal/7](../../example/tool/coverage_evidence/rerun4-retry-success-normal-7.json)、[normal/11](../../example/tool/coverage_evidence/rerun4-retry-success-normal-11.json)、[normal/13](../../example/tool/coverage_evidence/rerun4-retry-success-normal-13.json)、[normal/17](../../example/tool/coverage_evidence/rerun4-retry-success-normal-17.json)、[paused/16](../../example/tool/coverage_evidence/rerun4-retry-success-paused-16.json)、[paused/28](../../example/tool/coverage_evidence/rerun4-retry-success-paused-28.json)、[paused/34](../../example/tool/coverage_evidence/rerun4-retry-success-paused-34.json)、[paused/36](../../example/tool/coverage_evidence/rerun4-retry-success-paused-36.json)、[paused/37](../../example/tool/coverage_evidence/rerun4-retry-success-paused-37.json)、[paused/38](../../example/tool/coverage_evidence/rerun4-retry-success-paused-38.json)、[paused/44](../../example/tool/coverage_evidence/rerun4-retry-success-paused-44.json)、[paused/51](../../example/tool/coverage_evidence/rerun4-retry-success-paused-51.json)、[paused/57](../../example/tool/coverage_evidence/rerun4-retry-success-paused-57.json)。

## 剔除、失败与完整时间线

- cutover/75，target=12223ms：harness-invalid：结果早于目标档位切换完成或未观测到切换完成；[完整上下文](../../example/tool/coverage_evidence/rerun4-excluded-cutover-75.json)。
- cutover-extra/17，target=0ms：target<8000ms：沿用前次失败后复位竞争剔除规则；[完整上下文](../../example/tool/coverage_evidence/rerun4-excluded-cutover-extra-17.json)。
- cutover-extra/39，target=0ms：target<8000ms：沿用前次失败后复位竞争剔除规则；[完整上下文](../../example/tool/coverage_evidence/rerun4-excluded-cutover-extra-39.json)。

剔除全集 [rerun4-hls-excluded.json](../../example/tool/coverage_evidence/rerun4-hls-excluded.json)；失败EVENT、duration、全部RESTART、原生progress及seek调用/返回全集 [rerun4-hls-failures.json](../../example/tool/coverage_evidence/rerun4-hls-failures.json)。

| 场景/run(0起) | target | 全部RESTART | landed/continued/pause | seek数 | ABR夹入 | 完整时间线 |
|---|---:|---|---|---:|---|---|
| cutover/2 | 8623 | [23, 23, 23, 8623] | -1/10943/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-2.json) |
| cutover/8 | 12343 | [23, 23, 23, 12303] | -1/15503/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-8.json) |
| cutover/14 | 16863 | [23, 23, 23, 16863] | -1/20263/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-14.json) |
| cutover/18 | 9863 | [23, 23, 23, 9863] | -1/12103/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-18.json) |
| cutover/22 | 12903 | [23, 23, 12903, 12903] | -1/15183/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-22.json) |
| cutover/26 | 16063 | [23, 23, 164, 16023] | -1/18823/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-26.json) |
| cutover/30 | 19703 | [23, 23, 23, 19703] | -1/22583/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-30.json) |
| cutover/42 | 12063 | [23, 23, 23, 12063] | -1/14703/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-42.json) |
| cutover/44 | 14983 | [23, 23, 23, 14983] | -1/17343/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-44.json) |
| cutover/46 | 17623 | [23, 23, 23, 17623] | -1/20543/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-46.json) |
| cutover/64 | 13863 | [23, 23, 23, 13863] | -1/16783/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-64.json) |
| cutover/66 | 17063 | [23, 23, 89, 17063] | -1/19343/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-66.json) |
| cutover/72 | 9663 | [23, 23, 23, 9583] | -1/11943/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-72.json) |
| cutover/74 | 12223 | [23, 23, 23] | -1/12223/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-74.json) |
| cutover-extra/2 | 8663 | [23, 23, 23, 8663] | -1/11303/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-2.json) |
| cutover-extra/4 | 11583 | [23, 23, 23, 11583] | -1/14503/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-4.json) |
| cutover-extra/6 | 14823 | [23, 23, 23, 14783] | -1/17463/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-6.json) |
| cutover-extra/26 | 11223 | [23, 23, 23, 11143] | -1/14023/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-26.json) |
| cutover-extra/28 | 14303 | [0, 14303, 14303, 14303] | 14303/14583/no | 2 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-28.json) |
| cutover-extra/36 | 16503 | [23, 23, 23, 16503] | -1/19623/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-36.json) |
| cutover-extra/46 | 10783 | [23, 23, 23, 10703] | -1/13783/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-46.json) |
| cutover-extra/62 | 18103 | [23, 23, 23, 18103] | -1/21183/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-62.json) |
| cutover-extra/64 | 9463 | [23, 23, 23, 9423] | -1/11943/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-64.json) |
| cutover-extra/76 | 15223 | [23, 23, 23, 15223] | -1/18223/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-76.json) |
| cutover-extra/82 | 19623 | [23, 23, 151, 19623] | -1/22383/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-82.json) |
| cutover-extra/86 | 10023 | [83, 10023, 23, 10023] | 10023/10303/no | 2 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-cutover-extra-86.json) |
| normal/2 | 8623 | [23, 23, 23, 8623] | -1/11143/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-2.json) |
| normal/8 | 12743 | [23, 23, 23, 23, 12703] | -1/14703/no | 4 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-8.json) |
| normal/22 | 18812 | [23, 23, 218, 18823] | -1/21303/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-22.json) |
| normal/24 | 9263 | [23, 23, 23, 9263] | -1/12823/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-24.json) |
| normal/30 | 14303 | [23, 23, 23, 14303] | -1/17903/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-30.json) |
| normal/34 | 18863 | [23, 23, 242, 18863] | -1/21783/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-34.json) |
| normal/38 | 9863 | [23, 23, 219, 9863] | -1/12703/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-38.json) |
| normal/42 | 13543 | [23, 23, 243, 13543] | -1/16303/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-42.json) |
| normal/48 | 17903 | [271, 23, 23, 23, 17903] | -1/21463/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-48.json) |
| normal/50 | 9303 | [23, 23, 23, 9303] | -1/12103/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-50.json) |
| normal/54 | 12943 | [23, 23, 23, 23, 12943] | -1/15383/no | 4 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-54.json) |
| normal/58 | 16503 | [23, 23, 23, 16503] | -1/20263/no | 3 | True | [全部事件](../../example/tool/coverage_evidence/rerun4-failure-normal-58.json) |

本轮最小已观察复现：启动本轮release页，new case=hls，按场景设置cutover=true或paused=true；等原生位置>=8s，交替360p/180p。首个有效失败为cutover/2（第3次），target=8623ms，RESTART=[23, 23, 23, 8623]，最终path=http://127.0.0.1:18084/low/index.m3u8；ABR夹入=True。这是本轮观察到的最短失败前缀，不保证每次固定轮次触发。

首个失败关键时间线（完整文件保留全部EVENT/duration/progress）：

| ms | 事件 |
|---:|---|
| 18226 | HLS_SWITCH {'run': 2, 'cutover': True, 'paused': False, 'target': 8623, 'quality': '360p', 'uri': 'http://127.0.0.1:18084/high/index.m3u8', 'streamPosition': 8623, 'pause': 'no'} |
| 18239 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 0, 'playing': False, 'intent': True, 'rendered': True} |
| 18350 | HLS_EVENT {'type': 'MovaQualityChange', 'position': 0, 'duration': 0, 'playing': True, 'intent': True, 'rendered': True, 'qualityUri': 'http://127.0.0.1:18084/high/index.m3u8'} |
| 18763 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 40000, 'playing': True, 'intent': True, 'rendered': True} |
| 18823 | HLS_VARIANT_READY {'run': 2, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'duration': 40000, 'qualitySeen': True} |
| 18840 | KERNEL_SEEK_CALL {'target': 8623} |
| 18857 | HLS_RESTART {'run': 2, 'position': 23, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'eligible': True, 'pause': 'no'} |
| 19457 | KERNEL_SEEK_RETURN {'target': 8623} |
| 19636 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 8623, 'duration': 40007, 'playing': True, 'intent': True, 'rendered': True} |
| 19784 | HLS_RESTART {'run': 2, 'position': 23, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'eligible': True, 'pause': 'no'} |
| 20960 | KERNEL_SEEK_CALL {'target': 8623} |
| 20962 | KERNEL_SEEK_RETURN {'target': 8623} |
| 21066 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 0, 'playing': False, 'intent': True, 'rendered': True} |
| 21118 | HLS_EVENT {'type': 'MovaQualityChange', 'position': 0, 'duration': 0, 'playing': True, 'intent': True, 'rendered': True, 'qualityUri': 'http://127.0.0.1:18084/low/index.m3u8'} |
| 21119 | HLS_EVENT {'type': 'MovaAbrDownShift', 'position': 0, 'duration': 0, 'playing': True, 'intent': True, 'rendered': True} |
| 21506 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 40000, 'playing': True, 'intent': True, 'rendered': True} |
| 22191 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 40007, 'playing': True, 'intent': True, 'rendered': True} |
| 22272 | KERNEL_SEEK_CALL {'target': 8623} |
| 22313 | HLS_RESTART {'run': 2, 'position': 23, 'path': 'http://127.0.0.1:18084/low/index.m3u8', 'eligible': False, 'pause': 'no'} |
| 22313 | KERNEL_SEEK_RETURN {'target': 8623} |
| 22373 | HLS_RESTART {'run': 2, 'position': 8623, 'path': 'http://127.0.0.1:18084/low/index.m3u8', 'eligible': False, 'pause': 'no'} |
| 24832 | HLS_RESULT {'run': 2, 'cutover': True, 'paused': False, 'target': 8623, 'landed': -1, 'continued': 10943, 'gateMs': 18823, 'harnessInvalid': False, 'observedRestarts': [23, 23], 'restarts': [23, 23, 23, 8623], 'resumed': False, 'continuedOk': False, 'pass': False, 'pause': 'no', 'path': 'http://127.0.0.1:18084/low/index.m3u8'} |

失败中夹有MovaAbrDownShift：[('cutover', 2), ('cutover', 8), ('cutover', 14), ('cutover', 18), ('cutover', 22), ('cutover', 26), ('cutover', 30), ('cutover', 42), ('cutover', 44), ('cutover', 46), ('cutover', 64), ('cutover', 66), ('cutover', 72), ('cutover', 74), ('cutover-extra', 2), ('cutover-extra', 4), ('cutover-extra', 6), ('cutover-extra', 26), ('cutover-extra', 28), ('cutover-extra', 36), ('cutover-extra', 46), ('cutover-extra', 62), ('cutover-extra', 64), ('cutover-extra', 76), ('cutover-extra', 82), ('cutover-extra', 86), ('normal', 2), ('normal', 8), ('normal', 22), ('normal', 24), ('normal', 30), ('normal', 34), ('normal', 38), ('normal', 42), ('normal', 48), ('normal', 50), ('normal', 54), ('normal', 58)]；其余失败未观察到该事件。仅以HLS_EVENT计数，同一事件的EVENT副本不重复计数。

有效失败中夹ABR 38例、无ABR 0例；最终path不等于目标 38例。仍以本轮实际事件描述残余形态，不将总seek数直接解释成同一重发链。

复测命令：`python example/tool/rerun4_run.py hls`（160/60/60），补跑使用`python example/tool/rerun4_extra.py <cutover|normal|paused> <count> extra`，每批独立记录。本轮首批中断后实际使用`python example/tool/rerun4_continue.py`，重启同一包后依次独立补跑cutover90、normal60、paused60。

## 新包核对与前两轮对比

- rerun2：165/177通过、12/177失败（6.78%）；rerun3：234/295通过、61/295失败（20.68%）；本轮：245/283通过、38/283失败（13.43%）。场景数、验证页和库版本不同，比例是描述性对比，不能作为单独因果推断。
- 构建沿用Gradle初始化脚本、LFS原生库SHA256核对、zipalign与既有debug证书重签；[rerun4-build.log](../../example/tool/coverage_evidence/rerun4-build.log)、[rerun4-certificate.txt](../../example/tool/coverage_evidence/rerun4-certificate.txt)。
- 独立包 `com.icodejoo.mova.mova_example.coverage`；安装前`lastUpdateTime=2026-10-27 21:27:08`，安装后`lastUpdateTime=2026-10-27 21:50:14`；SERVER build=`rerun4-20261027`，[rerun4-start.json](../../example/tool/coverage_evidence/rerun4-start.json)。
- Gradle APK SHA256：`6fc54fe25f7e9d884cc1d2dd5a228c4991d0221ef3045ba5bf107d5106248a64`。
- 重签APK及设备拉回APK SHA256相同：`8d4b6ccc2a8aec7d18dca78242f913a0a1fecabc65a40603f19a97198db8707e`；[rerun4-build-manifest.json](../../example/tool/coverage_evidence/rerun4-build-manifest.json)。
- engine.dart SHA256：`546f9ba38657278c04fca2ececfcc071c8fd57da725149fbbbae2308e1a9a9fe`，起测/安装/收尾一致。受保护lib/test/packages文件与起测哈希逐项一致，未改库代码、未转换engine.dart的CRLF。

## 收尾及范围

起测：isKeyguardShowing=false、mScreenOnFully=true；USB常亮7；STREAM_MUSIC speaker=6/20。收尾：隔离包force-stop、pid为空；USB常亮恢复7、媒体音量恢复6/20；屏幕仍完全亮起且无锁屏。没有尝试解锁。本次启动的18080/18084本地源已结束，端口无监听。[rerun4-final-state.json](../../example/tool/coverage_evidence/rerun4-final-state.json)、[rerun4-final-window.txt](../../example/tool/coverage_evidence/rerun4-final-window.txt)、[rerun4-final-audio.txt](../../example/tool/coverage_evidence/rerun4-final-audio.txt)、[rerun4-final-review.json](../../example/tool/coverage_evidence/rerun4-final-review.json)。

本轮仅修改example/lib验证页、example/tool的rerun4脚本与证据及本新文档；不触碰另一会话的四个矩阵文件和../dioman，未执行git commit/stash/reset/checkout。证据前缀rerun4-。

结论：本轮仍有38/283有效失败，重发有成功证据但尚未消除F3/A17换档续播失败。

- 交付检查点：有效样本最低数、逐次判据、全部失败/剔除/重发证据、报告链接及受保护源码哈希已核验；设备与源已收尾。
