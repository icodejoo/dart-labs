# Android 暂停态补跑（rerun7，2026-10-27）

- 前置检查通过：亮屏未锁屏、USB常亮7、媒体音量6/20；未解锁，自行执行，无转派。

- 开始基线 analyze：执行 flutter analyze lib test，记录实际数字与完整输出。

- analyze 检查点：exit=0；完整日志 rerun7-analyze.log。

- 开始基线 test：执行 flutter test，记录实际数字与完整输出。

- test 检查点：exit=0；完整日志 rerun7-test.log。

- 开始重打包与安装：从本轮 Gradle APK 提取并核对原生库，zipalign 后使用既有 debug.keystore 重签；安装前后记录证书、SHA256 与 lastUpdateTime。

- 构建安装检查点：新 release 安装成功，设备拉回 APK SHA256 与重签包完全一致；lastUpdateTime/证书/源码哈希见 rerun7-build-manifest.json、rerun7-package-after.txt、rerun7-certificate.txt。

- 开始本地源与页面启动：复用已存在同一 VOD/HLS 素材，18080 提供 rerun-sources，18084 提供其 hls/high、low；设置 adb reverse 并确认新页面构建标记。

- 源/启动检查点：新页面 SERVER build=rerun7-20261027，双端口服务已启动并保存 owned PIDs；后续仅使用 rerun7 证据。

- 开始 rerun7-hls-paused：{'group': 'new', 'case': 'hls', 'cutover': 'false', 'paused': 'true', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun7-hls-paused 检查点：status=done，本轮切档 60，失败 0，脚本异常 0；证据 rerun7-hls-paused.json/.png/.logcat.txt。

- 独立审计检查点：逐个复算目标档位门槛、eligible RESTART首个目标落点、原生continued/pause/path，与页面一致；失败、剔除上下文及重发成功完整事件已分别导出，详见rerun7-hls-summary/audit/failures/excluded/retry-successes.json。

- 开始收尾：经现有验证页恢复媒体音量30%=6/20，USB常亮恢复7，force-stop隔离包；保留原生设置、进程与屏幕状态，再结束仅本次启动的两个源进程。

- 收尾检查点：隔离包pid为空（force-stop），USB常亮=7，媒体streamVolume=6/20；仍isKeyguardShowing=false、mScreenOnFully=true；本次两个源PID已结束，engine.dart哈希与安装时一致。证据 rerun7-final-state.json / rerun7-final-*.txt。


## 基线与暂停态结果

设备 `7NQBB23606003715`，隔离 Android release 包；自行执行，无转派。

- `flutter analyze lib test`：0 issues、exit 0；[rerun7-analyze.log](../../example/tool/coverage_evidence/rerun7-analyze.log)。
- `flutter test`：**1519/1519 全绿**、exit 0；[rerun7-test.log](../../example/tool/coverage_evidence/rerun7-test.log)。
- 原始 **60**，有效 **60**，通过 **60**，失败 **0**；剔除 **0**。

| 场景 | 原始结果 | 有效 | 通过 | 失败 | 剔除 |
|---|---:|---:|---:|---:|---:|
| 暂停态（cutover=false、paused=true） | 60 | 60 | 60 | 0 | 0 |

| 批次 | 状态 | 已产出结果 | SCRIPT_ERROR/UNCAUGHT |
|---|---|---:|---:|
| paused | done | 60 | 0 |

原始批次：[rerun7-hls-paused.json](../../example/tool/coverage_evidence/rerun7-hls-paused.json)。每批只取最后 BEGIN 之后，不重复计数。本轮单批正常结束，无中断、重启补跑或 SCRIPT_ERROR。

逐次独立审计：[rerun7-hls-audit.json](../../example/tool/coverage_evidence/rerun7-hls-audit.json)；[rerun7-hls-summary.json](../../example/tool/coverage_evidence/rerun7-hls-summary.json)。原始批次和脚本异常保留，未覆盖。复跑命令：`python example/tool/rerun7_run.py hls`（使用本轮同一已安装release包）。

## 判据与范围

复制 rerun6 专用验证页与脚本为 rerun7；仅跑暂停态 60 次，未跑普通播放、cutover 或弱网场景。沿用同一 40s HLS VOD、18080/18084 源、交替 360p/180p、真实播放器挂树。默认 ABR 阈值及库代码不改。

target 为切档前原生 time-pos，>=8000ms 才有效；位置 >20s 或 <8s 时仍 seek 回9s，并等 Player 进度与原生差<=100ms。先观测目标 MovaQualityChange、duration>0、原生 path=目标 URI，形成 HLS_VARIANT_READY 门槛；eligible RESTART 必须在门槛后且为目标 path。首个 target±500ms 的合格 RESTART 为 landed；播放态续播>=250ms 的原判据保留；暂停态 continued 必须保持 target±500ms 且 pause=yes，最终 path 必须为目标档位。各阶段6s防挂死截止不变。

target<8s、未观察到目标档位完成或提前结果按原规则剔除；其余失败照计，不因延迟读回恢复而改判通过。

唯一诊断增强是在暂停态 HLS_RESULT 后相对 +300ms、+1000ms 各读取一次原生 time-pos/pause/path，记 HLS_POST_READ，完成前不发起下一次切档；不重试、不 seek、不改变 HLS_RESULT。实际采样时刻与 raw time-pos 均保留。它增加轮间等待，可能改变后续竞争出现频率，不能当作完全相同调度的反事实对照。[验证页差异](../../example/tool/coverage_evidence/rerun7-harness.diff)。

## 内核 seek 分布与重发

只统计 HLS_SWITCH 至 HLS_RESULT 间 KERNEL_SEEK_CALL；新 QualityChange/ABR 切分续播链，同链同目标间隔>=1.5s 才算重发。首次合格落点位于重发后且最终通过记靠重发成功。

| 批次 | 0次 | 1次 | 2次 | 3次 | >3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
| paused | 0 | 51 | 9 | 0 | 0 | 9 |

失败 seek 分布：{}；完整重发时间线：[rerun7-hls-retry-successes.json](../../example/tool/coverage_evidence/rerun7-hls-retry-successes.json)。

## 失败与剔除清单

本轮无有效失败，失败逐项审计清单为空。

失败全集：[rerun7-hls-failures.json](../../example/tool/coverage_evidence/rerun7-hls-failures.json)；剔除全集：[rerun7-hls-excluded.json](../../example/tool/coverage_evidence/rerun7-hls-excluded.json)。

本轮无剔除。

## run 37 型复现与新问题观察

- （a）有目标落点且 continued=0 的有效失败：**0** 例。
- （b）其中 +300ms/+1000ms 均回到目标并保持 pause/path 正确：**0** 例；两次仍为0：**0** 例。共记录 **120** 条后读回，其中位置偏离 target±500ms **0** 条。120条后读回全部保持 pause=yes、path=目标档位；+300ms实际采样范围为302–365ms，+1000ms为1002–1053ms。本轮无失败样本可用于区分“瞬态0后恢复”与“持续为0”。
- （c）其他形态有效失败：**0** 例；有效样本夹 ABR **0** 例，失败夹 ABR **0** 例。

本轮未复现 rerun6 run 37 型失败，无法用本轮后读回证明旧样本的 0 为瞬态。不建议据此将旧 run 37 判为验证页瞬态读数问题；保留原失败，原因待证。

本轮仍按原 HLS_RESULT 判定，诊断恢复不会抹去失败；未观察到的现象不宣称已消除。

## 新包核对与前轮对比

| 轮次 | 场景 | 有效 | 通过 | 失败 |
|---|---|---:|---:|---:|
| rerun6 | 暂停态 | 60 | 59 | 1 |
| rerun7 | 暂停态，追加延迟读回 | 60 | 60 | 0 |

上述仅为描述性对比。库含 cb7c3ba（续播链内屏蔽ABR）与 ad950c0（等待目标回声），未修改库。

- 隔离包 `com.icodejoo.mova.mova_example.coverage`，lastUpdateTime=2026-10-27 23:31:27，build=`rerun7-20261027`；[rerun7-start.json](../../example/tool/coverage_evidence/rerun7-start.json)。
- Gradle APK SHA256：`9ee819bd4d9b436c7b65339a0d32af31fe2a2893a9a506c23893426d78a8292c`。
- 重签包与设备拉回 APK SHA256：`9ffd31ad0d0afd8307c32ae4151136eb19ba54e8f79aa4d57cc134e623fa6831`，完全一致；[rerun7-build-manifest.json](../../example/tool/coverage_evidence/rerun7-build-manifest.json)。
- engine.dart SHA256：`9d4116bde6e079f34424748373d6568db7638ad9f6dbb4c2da3f45073dfc8ffc`，构建前、安装时、收尾一致。release 不含Dart源码；通过编译输入哈希、包含 engine.dart 的编译依赖、编译AOT=Gradle合并产物、strip后AOT=设备包建立身份链；[rerun7-build-input.json](../../example/tool/coverage_evidence/rerun7-build-input.json)、[rerun7-build-provenance.json](../../example/tool/coverage_evidence/rerun7-build-provenance.json)、[rerun7-build-dependencies.txt](../../example/tool/coverage_evidence/rerun7-build-dependencies.txt)。
- 沿用 coverage.init.gradle、原生库LFS哈希核对、zipalign、既有debug证书重签；[rerun7-build.log](../../example/tool/coverage_evidence/rerun7-build.log)、[rerun7-install.log](../../example/tool/coverage_evidence/rerun7-install.log)、[rerun7-certificate.txt](../../example/tool/coverage_evidence/rerun7-certificate.txt)。

## 收尾及范围

经验证页恢复媒体音量30%=6/20；USB常亮恢复7；已 force-stop 隔离包，pid为空。仅结束本次两个源进程，移除本次 adb 映射，18080/18083/18084 无监听；[rerun7-final-state.json](../../example/tool/coverage_evidence/rerun7-final-state.json)。

lib/、test/、packages/ 共380个受保护文件及原验证页、rerun6文件哈希均未变；未触碰 ../dioman，无 commit/stash/reset/checkout。仅新增 rerun7 验证页、脚本、证据和本报告。最终核对：[rerun7-final-review.json](../../example/tool/coverage_evidence/rerun7-final-review.json)。
