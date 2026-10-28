# Windows release 复测（2026-10-27）

## 执行记录

- 开始：阅读 CLAUDE.md、Android 复跑脚本与原生事件采集方式；沿用本地 HLS，Windows 直接访问 127.0.0.1。仅自行执行，不转派。
- 已确认：Windows slim libmpv override；release 不以 FLUTTER_ENGINE_SWITCHES 假装切换后端；真实视频挂 MovaPlayer 自动使用 MovaSnapshotGuard，无界面验证使用 audioOnly。
- 开始基线：运行 flutter analyze lib test 与 flutter test，保存完整日志并记录实际数量；不采用文档预期值。
analyze exit=0
test exit=0
- 基线检查点：flutter analyze lib test：0 issues，exit 0；flutter test：1516 passed，exit 0。完整日志：example/tool/coverage_evidence/win-analyze.log、win-test.log。
- 开始验证页准备与release构建：单独HTTP命令端口18093、源端口18094，避开已有ADB端口映射18083。A23使用audioOnly；A12/F3均挂真实MovaPlayer，F3采用原生RESTART + time-pos（±500ms），推进判据为原生位置增加250ms；暂停态验证位置保持及原生pause=yes。
- 源路径核查：现有rerun-sources/hls只有滑动直播（live.m3u8），high/low实际在coverage_media（Android页面也用18084/master.m3u8）。复用这些相同VOD分片复制到rerun-sources/hls/high、low并添加master，按要求从rerun-sources提供，不重启生成直播。
- 脚本检查点：首次准备命令因工作目录为example而使用了根目录相对路径，文档追加/素材复制报错且未产生改动；已在根目录补齐。构建日志单独保留。
- 构建检查点：首次release编译到链接阶段失败，LNK1107；libmpv/windows-x86_64-whep 的 libmpv.dll.a（130字节）与DLL（133字节）都是LFS指针，不是真实产物。
- 开始补齐构建环境：只将匹配SHA256的LFS对象放入example/tool/coverage_evidence/win-libmpv-*和生成构建目录；不修改packages、libmpv源文件。重新执行flutter release构建。
- release构建检查点：win_build.py fixed 成功（exit 0）；LFS下载真实对象，构建时仅修复生成目录的导入库，构建完成后生成目录DLL与LFS哈希核对一致；源指针未改。证据 win-build-fixed-complete.log、win-libmpv-hashes.json。
- 开始A23/A12：前者逐次保存两次dispose返回/异常；后者暂停真实画面逐个setZoom(-1/0/NaN/100/2.5)，保存state读回与窗口矩形截图，检查双屏截图边界。

- 开始 fixed release 进程：启动本机桌面exe；只记录和收尾自己启动的PID。

- fixed 启动检查点：桌面exe PID=23368，本地源 PID=33804，HTTP读回build=fixed。

- 开始 a23：参数 {'case': 'dispose'}；保存完整真实事件，超时仅防挂死。

- a23 检查点：status=done，累计HLS结果=0，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-a23.json。

- 开始 a12--1：参数 {'case': 'zoom', 'value': '-1'}；保存完整真实事件，超时仅防挂死。

- a12--1 检查点：status=done，累计HLS结果=0，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-a12--1.json。

- 开始 a12-0：参数 {'case': 'zoom', 'value': '0'}；保存完整真实事件，超时仅防挂死。

- a12-0 检查点：status=done，累计HLS结果=0，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-a12-0.json。

- 开始 a12-NaN：参数 {'case': 'zoom', 'value': 'NaN'}；保存完整真实事件，超时仅防挂死。

- a12-NaN 检查点：status=done，累计HLS结果=0，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-a12-NaN.json。

- 开始 a12-100：参数 {'case': 'zoom', 'value': '100'}；保存完整真实事件，超时仅防挂死。

- a12-100 检查点：status=done，累计HLS结果=0，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-a12-100.json。

- 开始 a12-2.5：参数 {'case': 'zoom', 'value': '2.5'}；保存完整真实事件，超时仅防挂死。

- a12-2.5 检查点：status=done，累计HLS结果=0，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-a12-2.5.json。

- 开始 a12-clear：参数 {'case': 'clear'}；保存完整真实事件，超时仅防挂死。

- a12-clear 检查点：status=done，累计HLS结果=0，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-a12-clear.json。

- 开始 f3-fixed-normal：参数 {'case': 'hls', 'mode': 'normal', 'count': 34}；保存完整真实事件，超时仅防挂死。
- A23检查点（PASS）：普通引擎与cutover enabled代理各open本地点播成功（duration=40000ms，audioOnly=true），两者第1/第2次dispose均void completed、exception=null，共4次调用，第二次异常0。证据win-a23.json（seq1–10）。
- A12检查点（PASS）：5次输入读回依次 -1→1.0、0→1.0、NaN→1.0、100→100.0、2.5→2.5；rendered=true、640×360、VideoController真实画面。已直接查看win-a12--1.png与win-a12-0.png，彩条画面正常铺满播放区域、未塌缩。其余截图同前缀保存。
- 截图边界检查点：Windows枚举2块2560×1440显示器（X=0/2560）；按自启PID的GetWindowRect抓取（10,10,1280,720），非整双屏。元数据win-a12-0-window.json。
- 开始F3修复版：normal/cutover/paused各34次（共102），真实视频挂树，每次target原生读回>=8000ms；远离40s素材EOF（>20s时重新seek到9s并等原生到位）。暂停态continuedOk代表位置保持且pause=yes，非时间推进。

- f3-fixed-normal 检查点：status=done，累计HLS结果=34，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-f3-fixed-normal.json。

- 开始 f3-fixed-cutover：参数 {'case': 'hls', 'mode': 'cutover', 'count': 34}；保存完整真实事件，超时仅防挂死。

- f3-fixed-cutover 检查点：status=done，累计HLS结果=68，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-f3-fixed-cutover.json。

- 开始 f3-fixed-paused：参数 {'case': 'hls', 'mode': 'paused', 'count': 34}；保存完整真实事件，超时仅防挂死。

- f3-fixed-paused 检查点：status=done，累计HLS结果=102，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-f3-fixed-paused.json。
- F3修复版检查点：normal 34/34、cutover 34/34、paused 34/34，合计102次、续播/继续播放（暂停态位置保持）失败0、脚本异常0；完整累计时间线win-f3-fixed-paused.json，分组前缀win-f3-fixed-*。窗口旁证win-f3-fixed-desktop.png。

- 开始F3未修复对照：先归档原始SHA256=8e8c99c87cacb2319c5eaa4c9d51301c40b3e9151a5a061f5908e1cc2476812c及git diff，唯一临时改动为forcePark: !_variantLanded→false；结束后finally原字节还原并核对哈希。

- 开始关闭自启exe PID=23368，为下一次构建释放文件。

- exe关闭检查点：taskkill PID=23368 成功。

- 临时改动检查点：只替换唯一一行、保留原文件所有其他字节；未修复SHA256=be1544de7457f236b6a53804296f598a42247fb42a16e5ff955e48a93379c916。开始同页同素材同次数release重构建。

- 未修复release构建检查点：exit 0；开始与修复版相同normal/cutover/paused各34次。

- 开始 unfixed release 进程：启动本机桌面exe；只记录和收尾自己启动的PID。

- unfixed 启动检查点：桌面exe PID=34008，本地源 PID=33804，HTTP读回build=unfixed。

- 开始 f3-unfixed-normal：参数 {'case': 'hls', 'mode': 'normal', 'count': 34}；保存完整真实事件，超时仅防挂死。

- f3-unfixed-normal 检查点：status=done，累计HLS结果=34，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-f3-unfixed-normal.json。

- 开始 f3-unfixed-cutover：参数 {'case': 'hls', 'mode': 'cutover', 'count': 34}；保存完整真实事件，超时仅防挂死。

- f3-unfixed-cutover 检查点：status=done，累计HLS结果=68，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-f3-unfixed-cutover.json。

- 开始 f3-unfixed-paused：参数 {'case': 'hls', 'mode': 'paused', 'count': 34}；保存完整真实事件，超时仅防挂死。

- f3-unfixed-paused 检查点：status=done，累计HLS结果=102，失败=0，脚本/未捕获异常=0；证据 example/tool/coverage_evidence/win-f3-unfixed-paused.json。

- 还原检查点：engine.dart 已恢复原字节，SHA256=8e8c99c87cacb2319c5eaa4c9d51301c40b3e9151a5a061f5908e1cc2476812c，与开始一致=True。

- 开始收尾审核：从两份最终完整原生时间线重新分组计数，核对每次target/RESTART/continued；核对库文件还原哈希，再关闭自启进程并检查残留。

- 事件审计检查点：两版本各102次（每组34），target均>=8s，RESTART±500ms及原生continued判据逐条复算一致；win-f3-summary.json保存统计，win-f3-failures.json保存所有失败完整时间线。还原后的git diff也与归档win-f3-fix.patch逐字节一致。

- 生成文件检查点：flutter自动写入的3个Windows生成文件与HEAD内容一致，仅恢复CRLF，消除验证范围外的换行改动；未改packages/test或他人源码。

- 清理检查点：已关闭自启exe与本地源；owned PIDs=[23368, 33804, 34008]，进程残留0，18093/18094监听0；此前ADB等其他进程未关闭。证据win-cleanup.json、win-residual-ports.json。

## 最终结论

- 基线：`flutter analyze lib test` **0 issues**，`flutter test` **1516/1516 PASS**；两条命令exit 0。
- A23 **PASS**：普通/audioOnly、启用cutover代理/audioOnly各连续dispose两次，4/4 void completed，异常0；第二次均正常。逐调用证据：`example/tool/coverage_evidence/win-a23.json`。
- A12 **PASS**：真实挂树画面，5/5读回符合预期（-1/0/NaN→1.0，100→100.0，2.5→2.5）；-1/0窗口截图已目视确认不塌缩。证据：`win-a12--1.png`、`win-a12-0.png`、`win-a12-NaN.json`、`win-a12-100.json`、`win-a12-2.5.json`，均位于`example/tool/coverage_evidence/`。
- F3/A17 **未能复现：Windows 上未能复现该竞态，修复无回归，F3 仍待 Android 复测。不得据此标记修复验证通过。**

### 修复前后对比

| 场景 | 修复版 成功/总数 | 修复版失败 | 未修复版 成功/总数 | 未修复版失败 |
|---|---:|---:|---:|---:|
| normal | 34/34 | 0 | 34/34 | 0 |
| cutover | 34/34 | 0 | 34/34 | 0 |
| paused | 34/34 | 0 | 34/34 | 0 |
| 合计 | 102/102 | 0 | 102/102 | 0 |

- 原生判据：每次target取切档前mpv `time-pos`且>=8s；交替360p/180p；全部RESTART位置记录于`HLS_RESTART`/`HLS_RESULT.restarts`，任一落在target±500ms即landed；播放态continued必须原生增加至少250ms，暂停态必须保持target±500ms且原生`pause=yes`。时钟仅作为日志序号时间线与防挂死截止，不推算成功。
- 三组分别为普通引擎播放、`MovaCutoverEngine`且`MovaCutoverConfig(enabled:true)`播放、普通引擎暂停；两版本均真实MovaPlayer挂树，Windows自动启用MovaSnapshotGuard。切档本身仍经代理转发switchQuality；没有额外调用cutoverTo。
- 完整事件证据：`example/tool/coverage_evidence/win-f3-fixed-paused.json`与`win-f3-unfixed-paused.json`（均累计含该版本三组全部事件）；各模式独立检查点文件为`win-f3-{fixed,unfixed}-{normal,cutover,paused}.json`。统计`win-f3-summary.json`，失败及完整时间线`win-f3-failures.json`。
- 源为Android同一套40s HLS VOD，high/low分片复制到`example/tool/rerun-sources/hls/`，Windows直接127.0.0.1:18094访问；未用Android设备或adb发命令。源服务日志`win-source.log`。

### 还原核对

| 状态 | engine.dart SHA256 |
|---|---|
| 临时改动前 | `8e8c99c87cacb2319c5eaa4c9d51301c40b3e9151a5a061f5908e1cc2476812c` |
| forcePark:false对照 | `be1544de7457f236b6a53804296f598a42247fb42a16e5ff955e48a93379c916` |
| 已还原 | `8e8c99c87cacb2319c5eaa4c9d51301c40b3e9151a5a061f5908e1cc2476812c` |

- **哈希完全一致**；只临时替换指定一行，使用保存的原字节恢复，保留原工作区未提交改动。补丁归档`win-f3-fix.patch`，还原后补丁`win-f3-restored.patch`逐字节一致；哈希证据`win-engine-hashes.json`，原字节备份`win-engine-fixed.bytes`。没有commit/stash/reset/checkout。

### 残留进程检查

- 本次PID：修复版exe 23368、未修复版exe 34008、源 33804；均已退出。清理后相关进程**0**，18093/18094监听**0**。详见`win-processes.json`、`win-cleanup.json`、`win-residual-ports.json`。未关闭其他窗口/进程。

- 最终范围核查检查点：Windows生成文件已无工作区改动；engine.dart SHA256再次独立用Get-FileHash核对一致；HLS high/low 42个文件逐一与Android原素材SHA256相同（win-fixture-hashes.json）。dioman并行变化未触碰，既有test/core/engine_test.dart改动保留。
