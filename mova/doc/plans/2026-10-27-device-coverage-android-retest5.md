# Android F3/A17 第五轮修复复测（rerun6，2026-10-27）

- 前置检查通过：亮屏、isKeyguardShowing=false、USB常亮7、STREAM_MUSIC 6/20；未解锁。

- 开始基线 analyze：执行 flutter analyze lib test，记录实际数字与完整输出。

- analyze 检查点：exit=0；完整日志 rerun6-analyze.log。

- 开始基线 test：执行 flutter test，记录实际数字与完整输出。

- test 检查点：exit=0；完整日志 rerun6-test.log。

- 开始重打包与安装：从本轮 Gradle APK 提取并核对原生库，zipalign 后使用既有 debug.keystore 重签；安装前后记录证书、SHA256 与 lastUpdateTime。

- 构建安装检查点：新 release 安装成功，设备拉回 APK SHA256 与重签包完全一致；lastUpdateTime/证书/源码哈希见 rerun6-build-manifest.json、rerun6-package-after.txt、rerun6-certificate.txt。

- 开始本地源与页面启动：复用已存在同一 VOD/HLS 素材，18080 提供 rerun-sources，18084 提供其 hls/high、low；设置 adb reverse 并确认新页面构建标记。

- 源/启动检查点：新页面 SERVER build=rerun6-20261027，双端口服务已启动并保存 owned PIDs；后续仅使用 rerun6 证据。

- 开始 rerun6-hls-cutover：{'group': 'new', 'case': 'hls', 'cutover': 'true', 'count': '160'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun6-hls-cutover 检查点：status=done，本轮切档 160，失败 0，脚本异常 0；证据 rerun6-hls-cutover.json/.png/.logcat.txt。

- 开始 rerun6-hls-normal：{'group': 'new', 'case': 'hls', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun6-hls-normal 检查点：status=done，本轮切档 60，失败 0，脚本异常 0；证据 rerun6-hls-normal.json/.png/.logcat.txt。

- 开始 rerun6-hls-paused：{'group': 'new', 'case': 'hls', 'paused': 'true', 'count': '60'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun6-hls-paused 检查点：status=done，本轮切档 60，失败 1，脚本异常 0；证据 rerun6-hls-paused.json/.png/.logcat.txt。

- 独立审计检查点：逐个复算目标档位门槛、eligible RESTART首个目标落点、原生continued/pause/path，与页面一致；失败、剔除上下文及重发成功完整事件已分别导出，详见rerun6-hls-summary/audit/failures/excluded/retry-successes.json。

- 开始 rerun6-weak-automatic：{'group': 'new', 'case': 'rerun6Weak', 'manual': 'false', 'count': '10'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun6-weak-automatic 检查点：status=done，本轮切档 0，失败 0，脚本异常 1；证据 rerun6-weak-automatic.json/.png/.logcat.txt。

- 开始 rerun6-weak-manual：{'group': 'new', 'case': 'rerun6Weak', 'manual': 'true', 'count': '10'}；保留真实事件、原生读回及画面，以对应判据核验。

- rerun6-weak-manual 检查点：status=done，本轮切档 0，失败 0，脚本异常 0；证据 rerun6-weak-manual.json/.png/.logcat.txt。

- 开始收尾：经现有验证页恢复媒体音量30%=6/20，USB常亮恢复7，force-stop隔离包；保留原生设置、进程与屏幕状态，再结束仅本次启动的三个源进程。

- 收尾检查点：隔离包pid为空（force-stop），USB常亮=7，媒体streamVolume=6/20；仍isKeyguardShowing=false、mScreenOnFully=true；本次三个源PID已结束，engine.dart哈希与安装时一致。证据 rerun6-final-state.json / rerun6-final-*.txt。


## 基线与 F3/A17 结果

设备 `7NQBB23606003715`，隔离 Android release 包；当前 Codex 自行执行，无转派。

- `flutter analyze lib test`：0 issues、exit 0；[rerun6-analyze.log](../../example/tool/coverage_evidence/rerun6-analyze.log)。
- `flutter test`：**1519/1519 全绿**、exit 0；[rerun6-test.log](../../example/tool/coverage_evidence/rerun6-test.log)。
- 原始 **280**，有效 **280**，通过 **279**，失败 **1**；剔除 **0**，不计成败。

| 场景 | 原始尝试 | 有效 | 通过 | 失败 | 剔除 | 其中harness-invalid |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 160 | 160 | 160 | 0 | 0 | 0 |
| 普通播放 | 60 | 60 | 60 | 0 | 0 | 0 |
| 暂停态 | 60 | 60 | 59 | 1 | 0 | 0 |
| 合计 | 280 | 280 | 279 | 1 | 0 | 0 |

| 批次 | 状态 | 已产出结果 | SCRIPT_ERROR |
|---|---|---:|---:|
| cutover | done | 160 | 0 |
| normal | done | 60 | 0 |
| paused | done | 60 | 0 |

原始批次：[rerun6-hls-cutover.json](../../example/tool/coverage_evidence/rerun6-hls-cutover.json)、[rerun6-hls-normal.json](../../example/tool/coverage_evidence/rerun6-hls-normal.json)、[rerun6-hls-paused.json](../../example/tool/coverage_evidence/rerun6-hls-paused.json)。每批仅取最后BEGIN之后，累计历史不重复计数。

三组均正常结束，未发生SCRIPT_ERROR或重启补跑。

逐次审计 [rerun6-hls-audit.json](../../example/tool/coverage_evidence/rerun6-hls-audit.json)；分批汇总 [rerun6-hls-summary.json](../../example/tool/coverage_evidence/rerun6-hls-summary.json)。

## 判据与范围

沿用rerun4验证页与40s HLS VOD、18084 high/low，交替360p/180p，真实播放器挂树；cutover enabled=true。验证页复制为rerun6专用文件，主矩阵hls()逐字一致；ABR配置仍为默认阈值3，未改500ms/250ms判据。

target为切档前mpv time-pos，>=8000ms才有效；原生位置>20s或<8s时仍seek回9s，等Player进度与原生差<=100ms。播放与暂停均先观测目标MovaQualityChange、duration>0和原生path等于目标URI，记录HLS_VARIANT_READY。原始RESTART全部保留，eligible标记门槛后且path为目标的读回；landed取首个target±500ms的合格RESTART。播放态原生time-pos比landed增加>=250ms且pause=no；暂停态保持target±500ms且pause=yes；最终path必须仍为目标档位。门槛、落点和续播各保留6s防挂死截止，不按墙钟推算播放位置。

未观察到目标档位完成、或结果早于完成时刻，按harness-invalid单列；target<8s沿用复位竞争剔除规则。其余失败即使夹ABR仍计失败，不为凑数放宽。

## 内核 seek 分布与重发

统计HLS_SWITCH至HLS_RESULT间KERNEL_SEEK_CALL，排除切档前复位。新QualityChange或ABR切分续播链；同链同目标调用间隔>=1.5s才算重发。靠重发成功指首次合格落点出现在重发后且最终通过；仅为事件顺序证据，没有关闭重发的反事实对照。

| 场景 | 0次 | 1次 | 2次 | 3次 | >3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
| cutover 代理 | 0 | 126 | 34 | 0 | 0 | 34 |
| 普通播放 | 0 | 42 | 18 | 0 | 0 | 18 |
| 暂停态 | 0 | 44 | 16 | 0 | 0 | 16 |
| 合计 | 0 | 212 | 68 | 0 | 0 | 68 |

仍失败seek分布：{1: 1}；同一续播链首发+2次重发仍失败：[]。总调用数不能直接等同同链尝试数。

靠重发成功 **68** 次，完整时间线索引 [rerun6-hls-retry-successes.json](../../example/tool/coverage_evidence/rerun6-hls-retry-successes.json)。

## 失败与剔除清单

| 场景/run(0起) | target | 全部RESTART | landed/continued/pause | seek数 | MovaAbrDownShift | 完整时间线 |
|---|---:|---|---|---:|---|---|
| paused/37 | 8303 | [8303, 23, 8303] | 8303/0/yes | 1 | False | [全部事件](../../example/tool/coverage_evidence/rerun6-failure-paused-37.json) |

失败全集 [rerun6-hls-failures.json](../../example/tool/coverage_evidence/rerun6-hls-failures.json)。

本轮无剔除。

剔除全集 [rerun6-hls-excluded.json](../../example/tool/coverage_evidence/rerun6-hls-excluded.json)。

首个有效失败：paused/37（从0计数），target=8303ms，landed=8303，continued=0ms，seek=1次，ABR夹入=False。这是首批首个观察到的失败，不能保证固定轮次复现。复现流程为启动本轮同一release包，new case=hls、paused=true、count=60；不修改阈值。

首个失败关键时间线（完整EVENT/duration/progress见失败文件）：

| ms | 事件 |
|---:|---|
| 592949 | HLS_SWITCH {'run': 37, 'cutover': False, 'paused': True, 'target': 8303, 'quality': '180p', 'uri': 'http://127.0.0.1:18084/low/index.m3u8', 'streamPosition': 8303, 'pause': 'yes'} |
| 592954 | HLS_RESTART {'run': 37, 'position': 8303, 'path': 'http://127.0.0.1:18084/high/index.m3u8', 'eligible': False, 'pause': 'yes'} |
| 593027 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 0, 'playing': False, 'intent': False, 'rendered': True} |
| 593045 | HLS_EVENT {'type': 'MovaQualityChange', 'position': 0, 'duration': 0, 'playing': False, 'intent': False, 'rendered': True, 'qualityUri': 'http://127.0.0.1:18084/low/index.m3u8'} |
| 593436 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 0, 'duration': 40000, 'playing': False, 'intent': False, 'rendered': True} |
| 593512 | HLS_VARIANT_READY {'run': 37, 'path': 'http://127.0.0.1:18084/low/index.m3u8', 'duration': 40000, 'qualitySeen': True} |
| 593521 | KERNEL_SEEK_CALL {'target': 8303} |
| 593521 | HLS_RESTART {'run': 37, 'position': 23, 'path': 'http://127.0.0.1:18084/low/index.m3u8', 'eligible': True, 'pause': 'yes'} |
| 594273 | KERNEL_SEEK_RETURN {'target': 8303} |
| 594274 | HLS_EVENT {'type': 'MovaDurationChange', 'position': 8303, 'duration': 40007, 'playing': False, 'intent': False, 'rendered': True} |
| 594275 | HLS_RESTART {'run': 37, 'position': 8303, 'path': 'http://127.0.0.1:18084/low/index.m3u8', 'eligible': True, 'pause': 'yes'} |
| 594371 | HLS_RESULT {'run': 37, 'cutover': False, 'paused': True, 'target': 8303, 'landed': 8303, 'continued': 0, 'gateMs': 593512, 'harnessInvalid': False, 'observedRestarts': [23, 8303], 'restarts': [8303, 23, 8303], 'resumed': True, 'continuedOk': False, 'pass': False, 'pause': 'yes', 'path': 'http://127.0.0.1:18084/low/index.m3u8'} |

各组最短已观察失败前缀（不是稳定复现次数）：{'paused': 38}。执行命令：`python example/tool/rerun6_run.py hls`。

残余失败为暂停态run 37：1次seek，无ABR；目标8303ms，eligible RESTART为[23,8303]，已出现正确落点，但结果continued=0且pause=yes、path仍为low，故原判据计失败。原始RESTART的首个8303属于切档前high旧path，已正确标为ineligible。与rerun5的5例只有起点RESTART且无落点不同，本轮并非“seek被丢后始终只回声起点”的同一证据形态。只能确认落点后原生读回未保持，尚不能从外部日志判定0读回是瞬态、内核行为还是其他竞争；不将其剔除或改判通过。

## ABR与新问题观察

- （a）失败未归零：1/280。
- （b）有效失败中夹MovaAbrDownShift：0例，无ABR：1例。仅统计HLS_EVENT，同一事件的EVENT副本不重复计数。全部有效样本中夹ABR 0例。
- （c）本轮续播结果与原生读回见逐次审计；仍有失败，不能宣称续播卡住等问题已消除。与rerun5的5例“1次seek、RESTART起点位置”逐项对照见失败清单；真实弱网结果见下节。

## 新包核对与前几轮对比

| 轮次 | 有效 | 通过 | 失败 | 失败率 |
|---|---:|---:|---:|---:|
| rerun2 | 177 | 165 | 12 | 6.78% |
| rerun3 | 295 | 234 | 61 | 20.68% |
| rerun4 | 283 | 245 | 38 | 13.43% |
| rerun5 | 280 | 275 | 5 | 1.79% |
| rerun6（本轮） | 280 | 279 | 1 | 0.36% |

场景数、验证页和库版本不完全相同，上表仅为描述性对比。本轮沿用rerun4验证页与判据，库修复为ad950c0（续播校验要求_pendingSeekTarget == null，确认目标回声已到才视为落地），包含cb7c3ba的_abrHold。

- 隔离包 `com.icodejoo.mova.mova_example.coverage`；安装后 `lastUpdateTime=2026-10-27 23:07:03`；SERVER build=`rerun6-20261027`，[rerun6-start.json](../../example/tool/coverage_evidence/rerun6-start.json)。
- Gradle APK SHA256：`b13018240bcb41ae20193d3e2ac0d63df367f0c2fc0ae4abee9ee1e54efcfc7f`。
- 重签包与设备拉回APK SHA256一致：`059336e1ca0c46b83fbe08ebfbe3be20be7c2a9c1d612d7dc693d168324a8319`；[rerun6-build-manifest.json](../../example/tool/coverage_evidence/rerun6-build-manifest.json)。
- engine.dart SHA256：`9d4116bde6e079f34424748373d6568db7638ad9f6dbb4c2da3f45073dfc8ffc`，构建前/安装时/收尾一致，包含_abrHold及新增_pendingSeekTarget == null && _lastPosition判据。release APK不携带Dart源文件，源码身份通过编译输入哈希、含engine.dart的编译依赖、编译AOT与Gradle合并产物一致、strip后AOT与设备包一致建立证据链；[rerun6-build-input.json](../../example/tool/coverage_evidence/rerun6-build-input.json)、[rerun6-build-provenance.json](../../example/tool/coverage_evidence/rerun6-build-provenance.json)、[rerun6-build-dependencies.txt](../../example/tool/coverage_evidence/rerun6-build-dependencies.txt)。
- 沿用coverage.init.gradle、原生库LFS SHA256核对、zipalign、既有debug证书重签和安装；[rerun6-build.log](../../example/tool/coverage_evidence/rerun6-build.log)、[rerun6-install.log](../../example/tool/coverage_evidence/rerun6-install.log)、[rerun6-certificate.txt](../../example/tool/coverage_evidence/rerun6-certificate.txt)。

## 收尾及范围

起测与收尾均isKeyguardShowing=false、mScreenOnFully=true、USB常亮7、媒体STREAM_MUSIC speaker=6/20。隔离包已force-stop、pid为空；仅本次启动的18080/18084/18085源PID已结束，端口无监听。[rerun6-final-state.json](../../example/tool/coverage_evidence/rerun6-final-state.json)、[rerun6-final-review.json](../../example/tool/coverage_evidence/rerun6-final-review.json)。

本轮独立执行，无转派；未执行git commit/stash/reset/checkout，未修改lib/、test/、packages/，保护哈希逐项一致。原验证页及既有未提交改动保持原样，另建rerun6验证页及脚本；旧脚本和旧证据原样保留，未改../dioman或其他未提交文件。

## 弱网组结果

独立18085限速源沿用真实40s high/low HLS素材。high TS每32768字节等待650ms（约50.4KB/s），low不限速，主矩阵18084静态源不变。限速的是真实HTTP分片传输，无模拟缓冲事件；默认ABR配置enabled=true、threshold=3、policy=null。

(a) 不调用手动switchQuality：直接open真实high变体，并通过现有debugSetQualities测试钩子登记由实际master解析的档位和high当前档。(b) 同样初始化后，在开启限速时手动switchQuality(high)，观察同一引擎后续降档。该初始化是为了让Mova处于可降档的固定high状态；auto档位按实现不会发MovaAbrDownShift，不能把auto的内核自适应当作此事件。没有修改库或默认ABR策略。

_abrHold只读源码为10s兜底、校验间隔1.5s，也可在续播验证结束后提早解除；记录手动换档至降档的实际间隔，不能仅凭外部事件认定一定走满10s兜底。每次最长等待150s仅为防挂死。

| 模式 | 次数 | 通过 | 失败 |
|---|---:|---:|---:|
| automatic | 10 | 10 | 0 |
| manual | 10 | 10 | 0 |

批次异常单列：[rerun6-weak-summary.json](../../example/tool/coverage_evidence/rerun6-weak-summary.json)。ABR结果通过不抵消批次UNCAUGHT。自动批次已完成10次，但驱动因保留的UNCAUGHT返回非零；随后重启同一包执行manual批次，无覆盖原始证据。原始批次：[rerun6-weak-automatic.json](../../example/tool/coverage_evidence/rerun6-weak-automatic.json)、[rerun6-weak-manual.json](../../example/tool/coverage_evidence/rerun6-weak-manual.json)。

- automatic，19288ms，UNCAUGHT：Assertion failed: "[Player] has been disposed"；发生于automatic/run 1的WEAK_RESULT之后销毁阶段；完整堆栈保留在原批次JSON及弱网汇总。

自动组开播阶段的buffering上升沿也由默认策略计数，因此限速后的两次新上升沿可能已达到累计3次；未重置或改写默认策略。初始化阶段事件已收录于逐次审计initializationEvents。手动组switchQuality会按库默认行为重置计数。降档还须等待实际缓冲上升沿，10s兜底约束的是hold解除时间，并非降档事件必须在11.5s内发生；manual/3于16.199s降档，如实保留。

事件时间均为同一页面单调时钟ms；B+ / B-为BufferChange true/false，Q为QualityChange，D为AbrDownShift。完整逐次事件见 [rerun6-weak-audit.json](../../example/tool/coverage_evidence/rerun6-weak-audit.json)。

| 模式/run | 起点ms | 手动换档ms | 降档ms | 相对延迟ms | 通过 | 事件时间线 |
|---|---:|---:|---|---:|---|---|
| automatic/0 | 3979 | None | [8689] | 4710 | True | 537:B-，551:B+，801:B-，6493:B+，8229:B-，8566:B+，8582:B-，8689:Q:180p，8689:D:360p→180p，8689:B+ |
| automatic/1 | 13518 | None | [18733] | 5215 | True | 9984:B-，10007:B+，10447:B-，16103:B+，17908:B-，18602:B+，18690:B-，18733:Q:180p，18733:D:360p→180p，18734:B+ |
| automatic/2 | 23335 | None | [28173] | 4838 | True | 19566:B-，19610:B+，20030:B-，25474:B+，27359:B-，28045:B+，28136:B-，28172:Q:180p，28173:D:360p→180p，28173:B+ |
| automatic/3 | 33208 | None | [38055] | 4847 | True | 29506:B-，29518:B+，29958:B-，35354:B+，37232:B-，37924:B+，37941:B-，38055:Q:180p，38055:D:360p→180p，38055:B+ |
| automatic/4 | 42513 | None | [47222] | 4709 | True | 38814:B-，38844:B+，39225:B-，44969:B+，46792:B-，47096:B+，47136:B-，47222:Q:180p，47222:D:360p→180p，47222:B+ |
| automatic/5 | 52481 | None | [56125] | 3644 | True | 48636:B-，48672:B+，49127:B-，54658:B+，55728:B-，55981:B+，56027:B-，56124:Q:180p，56125:D:360p→180p，56125:B+ |
| automatic/6 | 61143 | None | [64812] | 3669 | True | 57482:B-，57502:B+，57888:B-，63248:B+，64327:B-，64667:B+，64782:B-，64812:Q:180p，64812:D:360p→180p，64812:B+ |
| automatic/7 | 69739 | None | [74586] | 4847 | True | 66130:B-，66151:B+，66572:B-，72382:B+，74106:B-，74468:B+，74489:B-，74586:Q:180p，74586:D:360p→180p，74587:B+ |
| automatic/8 | 78993 | None | [83410] | 4417 | True | 75395:B-，75429:B+，75864:B-，81205:B+，82932:B-，83249:B+，83367:B-，83410:Q:180p，83410:D:360p→180p，83411:B+ |
| automatic/9 | 87991 | None | [91858] | 3867 | True | 84713:B-，84733:B+，85158:B-，90364:B+，91447:B-，91748:B+，91769:B-，91858:Q:180p，91858:D:360p→180p，91858:B+ |
| manual/0 | 3654 | 3659 | [13406] | 9747 | True | 528:B-，543:B+，723:B-，3718:Q:360p，3718:B+，7190:B-，7274:B+，10601:B-，11061:B+，11881:B-，12329:B+，13163:B-，13284:B+，13301:B-，13405:Q:180p，13406:D:360p→180p，13406:B+ |
| manual/1 | 18622 | 18634 | [28550] | 9916 | True | 14852:B-，14878:B+，15295:B-，18735:Q:360p，18735:B+，22230:B-，22304:B+，25619:B-，26072:B+，26874:B-，27143:B+，28185:B-，28412:B+，28498:B-，28549:Q:180p，28550:D:360p→180p，28551:B+ |
| manual/2 | 32851 | 32862 | [41508] | 8646 | True | 29323:B-，29354:B+，29788:B-，30207:B+，30299:B-，32966:Q:360p，32966:B+，36424:B-，36502:B+，38508:B-，38703:B+，39795:B-，40024:B+，41078:B-，41347:B+，41449:B-，41507:Q:180p，41508:D:360p→180p，41508:B+ |
| manual/3 | 46491 | 46501 | [62700] | 16199 | True | 42768:B-，42798:B+，43250:B-，46586:Q:360p，46587:B+，50110:B-，50193:B+，59453:B-，59733:B+，60739:B-，60973:B+，62048:B-，62529:B+，62543:B-，62699:Q:180p，62700:D:360p→180p，62700:B+ |
| manual/4 | 67431 | 67462 | [76501] | 9039 | True | 64135:B-，64166:B+，64571:B-，67600:Q:360p，67601:B+，71062:B-，71251:B+，73292:B-，73480:B+，74580:B-，74911:B+，75916:B-，76340:B+，76458:B-，76501:Q:180p，76501:D:360p→180p，76502:B+ |
| manual/5 | 81133 | 81143 | [91095] | 9952 | True | 77812:B-，77833:B+，78257:B-，81243:Q:360p，81243:B+，84706:B-，84776:B+，88102:B-，88554:B+，89362:B-，89602:B+，90661:B-，90956:B+，91059:B-，91095:Q:180p，91095:D:360p→180p，91095:B+ |
| manual/6 | 96188 | 96206 | [106202] | 9996 | True | 92427:B-，92446:B+，92896:B-，93339:B+，93499:B-，96337:Q:360p，96337:B+，99873:B-，99967:B+，103283:B-，103740:B+，104564:B-，104803:B+，105838:B-，106086:B+，106100:B-，106202:Q:180p，106202:D:360p→180p，106203:B+ |
| manual/7 | 111056 | 111076 | [119830] | 8754 | True | 107517:B-，107548:B+，107985:B-，111250:Q:360p，111250:B+，114733:B-，114812:B+，116836:B-，117030:B+，118083:B-，118350:B+，119389:B-，119651:B+，119790:B-，119830:Q:180p，119830:D:360p→180p，119831:B+ |
| manual/8 | 124146 | 124158 | [132682] | 8524 | True | 120558:B-，120583:B+，121417:B-，124255:Q:360p，124255:B+，127787:B-，127863:B+，129869:B-，130053:B+，131129:B-，131391:B+，132452:B-，132564:B+，132644:B-，132681:Q:180p，132682:D:360p→180p，132682:B+ |
| manual/9 | 137608 | 137618 | [147777] | 10159 | True | 134097:B-，134129:B+，134539:B-，134953:B+，135150:B-，137736:Q:360p，137737:B+，141222:B-，141295:B+，144588:B-，145050:B+，145868:B-，146077:B+，147212:B-，147647:B+，147742:B-，147776:Q:180p，147777:D:360p→180p，147777:B+ |

弱网结论：两组均观察到真实缓冲后MovaAbrDownShift至180p/low；手动high换档后ABR仍恢复并降档，未见永久屏蔽。

结论：仍有1/280有效失败，不建议F3/A17验收通过。
