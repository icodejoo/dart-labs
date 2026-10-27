# Android F3/A17 第四轮修复复测（2026-10-27）

- 开始基线 analyze：执行 flutter analyze lib test，记录实际数字与完整输出。

- analyze 检查点：exit=0；完整日志 rerun5-analyze.log。

- 开始基线 test：执行 flutter test，记录实际数字与完整输出。

- test 检查点：exit=0；完整日志 rerun5-test.log。

- 前置检查通过：isKeyguardShowing=false、mScreenOnFully=true、USB常亮7、媒体6/20；未解锁。
- 基线实际数字：analyze 0 issues，test 1518/1518全绿，两者exit 0。
- 仅更新验证页build标记为rerun5-20261027；判据、ABR和500ms/250ms阈值未改。

- 开始重打包与安装：从本轮 Gradle APK 提取并核对原生库，zipalign 后使用既有 debug.keystore 重签；安装前后记录证书、SHA256 与 lastUpdateTime。

- 构建安装检查点：新 release 安装成功，设备拉回 APK SHA256 与重签包完全一致；lastUpdateTime/证书/源码哈希见 rerun5-build-manifest.json、rerun5-package-after.txt、rerun5-certificate.txt。

- 开始本地源与页面启动：复用已存在同一 VOD/HLS 素材，18080 提供 rerun-sources，18084 提供其 hls/high、low；设置 adb reverse 并确认新页面构建标记。

- 源/启动检查点：新页面 SERVER build=rerun5-20261027，双端口服务已启动并保存 owned PIDs；后续仅使用 rerun5 证据。

- 开始 rerun5-hls-cutover：{'group': 'new', 'case': 'hls', 'cutover': 'true', 'count': '160'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun5-hls-cutover 检查点：status=done，本轮切档 160，失败 1，脚本异常 0；证据 rerun5-hls-cutover.json/.png/.logcat.txt。

- 开始 rerun5-hls-normal：{'group': 'new', 'case': 'hls', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun5-hls-normal 检查点：status=done，本轮切档 60，失败 2，脚本异常 0；证据 rerun5-hls-normal.json/.png/.logcat.txt。

- 开始 rerun5-hls-paused：{'group': 'new', 'case': 'hls', 'paused': 'true', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun5-hls-paused 检查点：status=done，本轮切档 60，失败 2，脚本异常 0；证据 rerun5-hls-paused.json/.png/.logcat.txt。

- 独立审计检查点：逐个复算目标档位门槛、eligible RESTART首个目标落点、原生continued/pause/path，与页面一致；失败、剔除上下文及重发成功完整事件已分别导出，详见rerun5-hls-summary/audit/failures/excluded/retry-successes.json。

- 开始收尾：经现有验证页恢复媒体音量30%=6/20，USB常亮恢复7，force-stop隔离包；保留原生设置、进程与屏幕状态，再结束仅本次启动的两个源进程。

- 收尾检查点：隔离包pid为空（force-stop），USB常亮=7，媒体streamVolume=6/20；仍isKeyguardShowing=false、mScreenOnFully=true；本次两个源PID已结束，engine.dart哈希与安装时一致。证据 rerun5-final-state.json / rerun5-final-*.txt。


## 基线与 F3/A17 结果

设备 `7NQBB23606003715`，隔离 Android release 包；当前 Codex 自行执行，无转派。

- `flutter analyze lib test`：0 issues、exit 0；[rerun5-analyze.log](../../example/tool/coverage_evidence/rerun5-analyze.log)。
- `flutter test`：**1518/1518 全绿**、exit 0；[rerun5-test.log](../../example/tool/coverage_evidence/rerun5-test.log)。
- 原始 **280**，有效 **280**，通过 **275**，失败 **5**；剔除 **0**，不计成败。

| 场景 | 原始尝试 | 有效 | 通过 | 失败 | 剔除 | 其中harness-invalid |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 160 | 160 | 159 | 1 | 0 | 0 |
| 普通播放 | 60 | 60 | 58 | 2 | 0 | 0 |
| 暂停态 | 60 | 60 | 58 | 2 | 0 | 0 |
| 合计 | 280 | 280 | 275 | 5 | 0 | 0 |

| 批次 | 状态 | 已产出结果 | SCRIPT_ERROR |
|---|---|---:|---:|
| cutover | done | 160 | 0 |
| normal | done | 60 | 0 |
| paused | done | 60 | 0 |

原始批次：[rerun5-hls-cutover.json](../../example/tool/coverage_evidence/rerun5-hls-cutover.json)、[rerun5-hls-normal.json](../../example/tool/coverage_evidence/rerun5-hls-normal.json)、[rerun5-hls-paused.json](../../example/tool/coverage_evidence/rerun5-hls-paused.json)。每批仅取最后BEGIN之后，累计历史不重复计数。

三组均正常结束，未发生SCRIPT_ERROR或重启补跑。

逐次审计 [rerun5-hls-audit.json](../../example/tool/coverage_evidence/rerun5-hls-audit.json)；分批汇总 [rerun5-hls-summary.json](../../example/tool/coverage_evidence/rerun5-hls-summary.json)。

## 判据与范围

沿用rerun4验证页与40s HLS VOD、18084 high/low，交替360p/180p，真实播放器挂树；cutover enabled=true。验证页仅更新build标记，ABR配置仍为默认阈值3，未改500ms/250ms判据。

target为切档前mpv time-pos，>=8000ms才有效；原生位置>20s或<8s时仍seek回9s，等Player进度与原生差<=100ms。播放与暂停均先观测目标MovaQualityChange、duration>0和原生path等于目标URI，记录HLS_VARIANT_READY。原始RESTART全部保留，eligible标记门槛后且path为目标的读回；landed取首个target±500ms的合格RESTART。播放态原生time-pos比landed增加>=250ms且pause=no；暂停态保持target±500ms且pause=yes；最终path必须仍为目标档位。门槛、落点和续播各保留6s防挂死截止，不按墙钟推算播放位置。

未观察到目标档位完成、或结果早于完成时刻，按harness-invalid单列；target<8s沿用复位竞争剔除规则。其余失败即使夹ABR仍计失败，不为凑数放宽。

## 内核 seek 分布与重发

统计HLS_SWITCH至HLS_RESULT间KERNEL_SEEK_CALL，排除切档前复位。新QualityChange或ABR切分续播链；同链同目标调用间隔>=1.5s才算重发。靠重发成功指首次合格落点出现在重发后且最终通过；仅为事件顺序证据，没有关闭重发的反事实对照。

| 场景 | 0次 | 1次 | 2次 | 3次 | >3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 0 | 116 | 44 | 0 | 0 | 44 |
| 普通播放 | 0 | 46 | 14 | 0 | 0 | 14 |
| 暂停态 | 0 | 48 | 12 | 0 | 0 | 12 |
| 合计 | 0 | 210 | 70 | 0 | 0 | 70 |

仍失败seek分布：{1: 5}；同一续播链首发+2次重发仍失败：[]。总调用数不能直接等同同链尝试数。

靠重发成功 **70** 次，完整时间线索引 [rerun5-hls-retry-successes.json](../../example/tool/coverage_evidence/rerun5-hls-retry-successes.json)。

## 失败与剔除清单

| 场景/run(0起) | target | 全部RESTART | landed/continued/pause | seek数 | MovaAbrDownShift | 完整时间线 |
|---|---:|---|---|---:|---|---|
| cutover/120 | 9303 | [23, 23] | -1/5343/no | 1 | False | [全部事件](../../example/tool/coverage_evidence/rerun5-failure-cutover-120.json) |
| normal/33 | 18023 | [63, 63] | -1/5463/no | 1 | False | [全部事件](../../example/tool/coverage_evidence/rerun5-failure-normal-33.json) |
| normal/55 | 16183 | [103, 103] | -1/5343/no | 1 | False | [全部事件](../../example/tool/coverage_evidence/rerun5-failure-normal-55.json) |
| paused/11 | 8223 | [23, 23] | -1/23/yes | 1 | False | [全部事件](../../example/tool/coverage_evidence/rerun5-failure-paused-11.json) |
| paused/54 | 9023 | [23, 23] | -1/23/yes | 1 | False | [全部事件](../../example/tool/coverage_evidence/rerun5-failure-paused-54.json) |

失败全集 [rerun5-hls-failures.json](../../example/tool/coverage_evidence/rerun5-hls-failures.json)。

本轮无剔除。

剔除全集 [rerun5-hls-excluded.json](../../example/tool/coverage_evidence/rerun5-hls-excluded.json)。

首个有效失败：cutover/120（从0计数），target=9303ms，landed=-1，continued=5343ms，seek=1次，ABR夹入=False。这是首批首个观察到的失败，不能保证固定轮次复现。复现流程为启动本轮同一release包，new case=hls、cutover=true、count=160；不修改阈值。

首个失败关键时间线（完整EVENT/duration/progress见失败文件）：

| ms | 事件 |
|---:|---|
| 266042 | HLS_SWITCH {'run': 120, 'cutover': True, 'paused': False, 'target': 9303, 'quality': '360p', 'uri': 'http://127.0.0.1:18084/high/index.m3u8', 'streamPosition': 9303, 'pause': 'no'} |
| 266052 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 0, 'playing': False, 'intent': True, 'rendered': True} |
| 266245 | HLS_EVENT {'type': 'MovaQualityChange', 'position': 0, 'duration': 0, 'playing': True, 'intent': True, 'rendered': True, 'qualityUri': 'http://127.0.0.1:18084/high/index.m3u8'} |
| 266722 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 40000, 'playing': True, 'intent': True, 'rendered': True} |
| 266775 | HLS_VARIANT_READY {'run': 120, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'duration': 40000, 'qualitySeen': True} |
| 266891 | KERNEL_SEEK_CALL {'target': 9303} |
| 266891 | HLS_RESTART {'run': 120, 'position': 23, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'eligible': True, 'pause': 'no'} |
| 267303 | KERNEL_SEEK_RETURN {'target': 9303} |
| 267414 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 40007, 'playing': True, 'intent': True, 'rendered': True} |
| 267414 | HLS_RESTART {'run': 120, 'position': 23, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'eligible': True, 'pause': 'no'} |
| 272784 | HLS_RESULT {'run': 120, 'cutover': True, 'paused': False, 'target': 9303, 'landed': -1, 'continued': 5343, 'gateMs': 266775, 'harnessInvalid': False, 'observedRestarts': [23, 23], 'restarts': [23, 23], 'resumed': False, 'continuedOk': False, 'pass': False, 'pause': 'no', 'path': 'http://127.0.0.1:18084/high/index.m3u8'} |

各组最短已观察失败前缀（不是稳定复现次数）：{'cutover': 121, 'normal': 34, 'paused': 12}。执行命令：`python example/tool/rerun5_run.py hls`。

该残余失败按目标门槛完成后仍未命中落点计入，不能因无ABR而忽略。若原生位置持续增长，仅能说明播放器仍在走时，不能等同已正确续播。仅靠本轮外部事件无法确认为何未重发，也无法将残余失败归因于_abrHold；不在本轮修改库代码。

## ABR与新问题观察

- （a）失败未归零：5/280。
- （b）有效失败中夹MovaAbrDownShift：0例，无ABR：5例。仅统计HLS_EVENT，同一事件的EVENT副本不重复计数。全部有效样本中夹ABR 0例。
- （c）本轮续播结果与原生读回见逐次审计；仍有失败，不能宣称续播卡住等问题已消除。与rerun4的38例全部夹ABR、最终path偏离不同，本轮需以失败清单分别判断；本轮未做可选“换档后10s内人为限速”组；现有abr用例采用GatedAbr阈值1，且现有静态源不实现throttle端点，直接调用不符合本轮同口径约束。因此没有真机证据证明真实弱网时ABR必然恢复降档，也不能把未出现ABR解释为ABR永久禁用。10s兜底与屏蔽结束reset已从当前源码只读核对，不能替代弱网实测。

## 新包核对与前几轮对比

| 轮次 | 有效 | 通过 | 失败 | 失败率 |
|---|---:|---:|---:|---:|
| rerun2 | 177 | 165 | 12 | 6.78% |
| rerun3 | 295 | 234 | 61 | 20.68% |
| rerun4 | 283 | 245 | 38 | 13.43% |
| rerun5（本轮） | 280 | 275 | 5 | 1.79% |

场景数、验证页和库版本不完全相同，上表仅为描述性对比。本轮沿用rerun4验证页与判据，库修复为cb7c3ba（续播链内屏蔽ABR）。

- 隔离包 `com.icodejoo.mova.mova_example.coverage`；安装后 `lastUpdateTime=2026-10-27 22:33:26`；SERVER build=`rerun5-20261027`，[rerun5-start.json](../../example/tool/coverage_evidence/rerun5-start.json)。
- Gradle APK SHA256：`b6f8ee11b4cf449a86b9189d4e1c3d3f36b22d07cd8580983202420419058c46`。
- 重签包与设备拉回APK SHA256一致：`da5a30b91d80cf7ee9d83cfae2cbe9becf11f4e7eb2f6a5c3421416652871508`；[rerun5-build-manifest.json](../../example/tool/coverage_evidence/rerun5-build-manifest.json)。
- engine.dart SHA256：`a0cde4d49f1ccc5f53e066be7231286cce1743eac57965f2266c7388150796d8`，构建前/安装时/收尾一致，包含_abrHold。release APK不携带Dart源文件，源码身份通过编译输入哈希、含engine.dart的编译依赖、编译AOT与Gradle合并产物一致、strip后AOT与设备包一致建立证据链；[rerun5-build-input.json](../../example/tool/coverage_evidence/rerun5-build-input.json)、[rerun5-build-provenance.json](../../example/tool/coverage_evidence/rerun5-build-provenance.json)、[rerun5-build-dependencies.txt](../../example/tool/coverage_evidence/rerun5-build-dependencies.txt)。
- 沿用coverage.init.gradle、原生库LFS SHA256核对、zipalign、既有debug证书重签和安装；[rerun5-build.log](../../example/tool/coverage_evidence/rerun5-build.log)、[rerun5-install.log](../../example/tool/coverage_evidence/rerun5-install.log)、[rerun5-certificate.txt](../../example/tool/coverage_evidence/rerun5-certificate.txt)。

## 收尾及范围

起测与收尾均isKeyguardShowing=false、mScreenOnFully=true、USB常亮7、媒体STREAM_MUSIC speaker=6/20。隔离包已force-stop、pid为空；仅本次启动的18080/18084源PID已结束，端口无监听。[rerun5-final-state.json](../../example/tool/coverage_evidence/rerun5-final-state.json)、[rerun5-final-review.json](../../example/tool/coverage_evidence/rerun5-final-review.json)。

本轮独立执行，无转派；未执行git commit/stash/reset/checkout，未修改lib/、test/、packages/，保护哈希逐项一致。保留验证页既有未提交改动，仅更新build标记；rerun4脚本与旧证据原样保留，未改../dioman或其他未提交文件。新增rerun5脚本与rerun5-证据。

结论：仍有5/280有效失败，不建议F3/A17验收通过。
