# CP1 逐项收口

本人执行，不转派；代码改动位于 wt-mova-cp1/mova。Windows 构建曾误写外部既有安装目录，范围偏差见第 5/6 项，不能声称全部写入均在 worktree。历史报告中的原始 FAIL 不删除，以下为修正后的独立复测。

## 1. H28 落点采样

旧证据：`example/tool/coverage_evidence/matrix-cp1-android-h28-20261103-1703-cp0-h28/cp0-result.json`，verdicts[32,77]；对应 gap.json rows[8216,16944]。

- 暂停组在 09:05:23.915Z 读到 12 秒，09:05:24.005Z 再读为 0 秒；现有产品续播校验尚未结束，验证页已经报失败。进一步核对失败之后的原始记录：进度在 09:05:25.857Z 恢复至 12023ms，而下一次 seek 在 09:05:27.502Z 才发出。cutover 在 09:07:01.650Z 恢复至 12000ms，并持续推进至 14463ms，下一次 seek 为 09:07:04.170Z。因此不是“下一次 seek 抢先取消原链导致归零”；原链已经自行恢复，准确根因为过早判定。原提交说明的取消链归因在此更正。
- cutover 的继续播放判断以错误的 `landed=0` 为起点，0→343ms 也能满足旧的 `> landed+300`，没有证明目标附近继续推进。
- 新增产品复现测试覆盖“目标回声→归零→现有校验链补发收敛”，播放/暂停两条均在未改 lib 时通过。产品恢复链未显示漏判；本项修正验证页，保留 500ms 初次落点误差及暂停意图判据。
- 新采样必须 path 匹配、原生 seeking=no，持续 400ms 并等 buffering=false 后才完成。初次原生落点独立于可能迟到的 Dart buffering 标志保存。播放组验证按时钟推进，报告该稳定窗的初次落点；暂停组验证位置稳定。后续推进不得回到目标之前。
- 旧采样逻辑的隔离副本使最终 4 条采样测试全红；新采样通过。副本及原始输出放在 `example/tool/coverage_evidence/h28-red/red-tests.log`。产品复现两条无需改 lib 即绿。
- 第一轮收口复测 `cp1-close-h28-1805` 因采样错误地要求播放中的整个稳定窗均处于目标±500ms而中止；归入验证器问题，原始记录保留，不计产品结论。
- 第二轮 `cp1-close-h28-r2-1810`：30/30、30/30、29/30。cutover iteration=27 的原生序列证明原校验链实际补发并恢复：1410ms 时归零，2032ms 再次 seek，2614ms seeking=no 且 position=12463ms；2705ms Dart buffering 才清除，position=12503ms。验证器把迟到的 UI 标志错误地用作落点计时起点，导致 3ms 假超限；完整稳定采样保留。修正后不扩大误差线，记录原生 12463ms 初次落点并另等 UI 缓冲清除。
- 全量首跑 2086 PASS / 7 FAIL；7 条均为 B09 的 `.dart_tool/b09` 父目录缺失。补齐工作区本地目录后重跑，不修改产品或既有测试来绕过错误。

最终复测 `cp1-close-h28-r3-1818`：playing/paused/cutover 各 30/30 PASS，90 次零失败，最大绝对落点误差分别 463/23/463ms，harness=[]。证据：`example/tool/coverage_evidence/matrix-cp1-close-h28-r3-1818-cp0-h28/cp0-result.json` verdicts[0..89] 与同目录 gap.jsonl 的逐次原生采样；宿主完成元数据 `example/tool/coverage_evidence/cp1-close-h28-r3-1818-completion.json`。APK 拉回哈希 `979e3d9ba3f8d45beb1425634636c77fe9b6d174de36819d2c573e658c989cf4`；构建证据 `matrix-cp1-build-20261103-181605`。子驱动和外层均执行设备设置恢复，读回 USB 常亮=7、媒体音量=0。

最终验证：全量 `flutter test --concurrency=3` **2094 PASS**（`cp1-close-h28-tests-r3.log`）；相关测试 21 PASS（其中新增产品复现 2 条、采样 4 条）；采样回退 4 FAIL→4 PASS；`flutter analyze lib test` 0 issues（`cp1-close-h28-analyze-r3.log`）。上述日志均在 `example/tool/coverage_evidence/`。

## 2. UI 套件快照同步

设计核对：总计划 B14（577 行）明确锁定按钮进入组件树，落地记录（588 行）明确默认树加入 lockToggle 并同步 Bilibili 基准；C 块 `2026-11-03-c04-c06-chrome-style.md` 的 C06 文件清单仍包含默认 UI 套件锁定按钮（834 行）。这是设计内组件，不能删除来匹配旧验证页。

精确快照为 default/bilibili 完整树和 patch 树分别补上 `lockToggle@overlay`；Bilibili patch 期望改为按固定节点名映射 topBar/danmakuTrack，其余节点逐个原样保留，避免固定 sublist 截掉新组件。仍使用有序列表全量相等、真实挂树与点击判据。产品代码无修改。

`flutter test --concurrency=3 test/ui/ui_kit_test.dart test/ui/bilibili_ui_kit_test.dart test/ui/b14_test.dart`：24 PASS，证据 `example/tool/coverage_evidence/cp1-close-ui-kit-tests.log`。

真机三轮 `cp1-close-ui-kit-1825`：原 12 条快照 **12/12 PASS**。证据 `example/tool/coverage_evidence/matrix-cp1-close-ui-kit-1825-ui-kit/cp0-result.json`、`matrix-cp1-close-ui-kit-1825-1-ui-kit/cp0-result.json`、`matrix-cp1-close-ui-kit-1825-2-ui-kit/cp0-result.json`，每份 verdicts[6,8,56,61]。三轮完整 UI 套件各 68 PASS / 0 FAIL / 6 BLOCKED（人工布局/PiP/全屏视觉项），harness=[]；不把这些人工项当作 PASS。快照修正不证明 B03 专属底栏刺激已执行，底栏覆盖仍单独列项。构建拉回 SHA256=`9a9e047da9bcec323ad51ca88cd0b7097f5ec8fb54e86fc4caa70a52fe12e78c`。原 12 条 FAIL 保留在旧证据。

## 3. 独立 END_FILE 采样

旧 `matrix-cp1-errclass-20261103-1544` records[259] 已有真实核心 END_FILE 转成的 fatal=MovaEndFileReason.error，us=3990447；records[262] 在 us=4023689 CHECK（仅晚 33.242ms），records[263] 在 us=4024503 即释放。独立客户端使用 `pollInDebug:true` 的 100ms 周期泵，尚未来得及消费即被 dispose。根因为验证器释放时序，不是核心漏发。

修正：核心错误出现后，最多 5 秒等待独立客户端原始 END_FILE(reason=4)，随后才 CHECK/释放；仍要求独立数组非空，超时保持 FAIL 并保存 endFileWaitTimedOut，不用核心事件填造独立样本。

真机 `cp1-close-errclass-1832`：fatal 5/5 PASS，独立 END_FILE 各 1 条，等待超时 0/5；CHECK 位于 `example/tool/coverage_evidence/matrix-cp1-close-errclass-1832/matrix-cp1-close-errclass-1832-cp1-errclass.json` records[211,235,259,283,307]。同轮 nonfatal/poster 各 5/5 PASS，completed=true，harness=[]，run_matrix 返回 0，设备设置已恢复。APK SHA256=`2a791b777537739248bcbb4cdbe844fd6c7ed68e204048284c13faeb75ae05ed`。

事件泵回归 `flutter test --concurrency=3 test/core/kernel/mpv_event_pump_test.dart`：24 PASS（`cp1-close-errclass-tests.log`）。本项无产品修改/新增产品测试，原 records[262] FAIL 保留。

## 4. BLOCKED 夹具收口

- 7a：只给延迟替换的新源设置 network-timeout=20s，保留旧 5s wake 竞争窗口及 >6s 的闸门刺激。`cp1-close-wakecutover-1838` 10/10 PASS，原生新源首帧和地址完整，harness=[]，run_matrix=0。CHECK 在 `example/tool/coverage_evidence/matrix-cp1-close-wakecutover-1838/matrix-cp1-close-wakecutover-1838-cp1-wakecutover.json` records[269,503,740,982,1211,1429,1648,1862,2089,2290]。
- 7b/fallback：所有主/子清单及别名输出完整 HTTP URI，保留每次实际响应正文。第六次重开协议测试与 primary 前缀测试回退旧输出后 2 FAIL，修正后 2 PASS；另验证 primary 实际 404 状态与备用路径可读，及相邻帧隐私守卫。Python 新回归 5 PASS；矩阵既有回归 56 PASS。
- 恢复：开源前启用限速 400000B/s，并按源限制 demuxer-readahead-secs=1、demuxer-max-bytes=524288、cache-secs=1，防止 120 秒本地 HLS 在 arm 前读完。仍必须观察 segmentEntered、buffering、真实 stallTimeout/retry 与原生续播误差。
- 探测：备用源组的素材实际为滑动直播 HLS，声明 live，并显式 liveEndIsFailure；限制预读和网络超时，要求真实主源失败后触发 failover，再核对每地址独立探测一次。关闭组保持不主动 loadQualities。
- keepAlive：日志线程不再同步执行截图/音频 dump；有界采图队列保存标记接收/排队/截帧起止时刻，拒绝过期标记。相邻帧使用截前/截后前台守卫，切前台则两帧都丢弃。S7 依据旧 APK 的 1200ms SHOT 窗口拒绝迟帧，S14 使用 2000ms 窗口，避免将后续场景误配。基线 APK 已在本树 `matrix-cp1-build-20261103-153357/*installed-before.apk` 找到，实测 SHA256 与 CP0 报告完全一致：`f9df792f6dcc0b68d908906f23026dd5beeacd56d0c2d566c1b85d6c35ba1586`。

当前修正构建 SHA256=`e8dcfe82dfef276f4514159f190f1a49cd6b5ee7e6d08d0852e530fcf16839de`（本地/拉回一致）。相关 Flutter 恢复就绪与探测测试 23 PASS；三份改动 Dart 验证页 analyze 0 issues。

7b/fallback 真机：`cp1-close-edgepause-1843` pause 10/10、fallback 10/10 PASS，harness=[]，run_matrix=0。证据 `example/tool/coverage_evidence/matrix-cp1-close-edgepause-1843/matrix-cp1-close-edgepause-1843-cp1-edgepause.json`，pause CHECK records[274,499,730,948,1165,1370,1580,1786,1991,2183]，fallback records[2374,2564,2752,2939,3124,3312,3497,3676,3856,4036]。第六次以后亦通过；原生暂停意图检查保持原判据。协议错误在固定完整 URL 的夹具中不再出现，未改 lib。

恢复补充定位：`cp1-close-recovery-1846` 在 `am start` 后立即 pidof，尚未就绪即进入 finally 清理；logcat 仅见 Start proc 与驱动 force-stop，无 FATAL。改用 `am start -W` 后 `cp1-close-recovery-r2-1848` 已取得真正 stallTimeout/retry（records[167]）与 MovaRecovered（records[194]），但旧页错误地等待用户 MovaSeeked，导致 records[199,200] 超时。源码恢复分支 `_seekOrPark(... ready:true)` 沿用 notify=false，不应发用户 seek 事件。验证器改为直接保存原生 seeking/path/落点及相邻进度，使用第 1 项稳定窗（初次落点±500ms），不再以无此契约的事件充当恢复完成。两轮原始缺测保留，不算产品 PASS。

恢复最终复测：`cp1-close-recovery-r3-1853` resume 10/10、manual720 10/10 PASS；最大误差分别 120/280ms，20 次都具有分片阻塞、真实 stallTimeout/retry、MovaRecovered 与原生落点/地址证据。`example/tool/coverage_evidence/matrix-cp1-close-recovery-r3-1853/matrix-cp1-close-recovery-r3-1853-cp1-recovery.json` resume CHECK records[240,454,651,832,1022,1201,1384,1613,1859,2065]，manual720 records[2315,2538,2765,2991,3238,3432,3654,3873,4090,4290]。completed=true，harness=[]，run_matrix=0。最终验证包 SHA256=`bc66da9f763e25b0fdf887705a503e1c865096bccf7cc1baaa583ff616f3c7a6`；恢复验证页及 harness analyze 0 issues。

探测最终复测：`cp1-close-probe-1858` list/manual/once 各 10/10、failover/disabled 各 5/5，总计 40/40 PASS，harness=[]，run_matrix=0。备用源每轮两次独立探测（primary 与 alternate 各一次），真实主源 404 响应和清单正文均保留；关闭组探测数每轮为 0。证据 `example/tool/coverage_evidence/matrix-cp1-close-probe-1858/matrix-cp1-close-probe-1858-cp1-probe.json`：failover CHECK records[1412,1501,1585,1669,1759]，disabled records[1791,1822,1855,1889,1920]。原三组也本轮重跑通过，未用旧 PASS 补计。

keepAlive 进一步修正与基线来源：

- 原 CP0 APK 虽匹配哈希，但其 `main_cp0_suite_verify` 只含轻量 CP0 场景，收到 keepAlive selector 后在第 29 行空断言失败。`cp0-close-keepalive-1903` 未进入产品场景，保留为调度夹具 BLOCKED。
- CP0 基线报告在提交 `591e8d94` 中明确记录产品 revision 为 `a5c317f6afb55125611b64a964ce1222c63ae000`。使用 `git archive` 将该 revision 的 lib/Android 插件/pubspec 解到本 worktree 的 `.dart_tool`；只临时切换 example 的路径依赖，当前 lib 不替换、不切分支。诊断入口单独选择同一 KeepAliveAutoPage。构建后 example/pubspec.yaml 与 lock 逐字节恢复，pub get 回当前依赖。归档源码逐文件 SHA256、解析后的包路径、构建与安装哈希见 `example/tool/coverage_evidence/cp0-keepalive-build.json`。
- 重建基线的 libmpv SHA256=`daaf6b0a10c74f5c9baae13a98d0334930ea2cf37897758c889538c827041b74`，helper=`ab55b1d34665dba8fa7a451e82c466ee71b9698e7da6c9a3cb68a7c0ee7610d4`，均与原 CP0 APK 对应条目完全相同；没有拿当前产品代码冒充 CP0。
- 首次相邻帧采样实测约 3–4 秒，旧页 S7 SHOT 窗口仅 1.2 秒，`cp0-close-keepalive-r2-1909` 的过期图被拒绝，未作视觉 PASS。最终协议改为诊断页逐标记 token 握手：保持当前阶段，宿主截前/截后确认相同 token 与前台包，收到精确 ACK 后页面才进入下一阶段。原生 hold/resume 的产品调用与判据不变，额外等待只服务采样。
- `cp0-close-keepalive-r3-1917` 首轮 S7 SHOT 20 的单次 screencap 耗时 63.5 秒，超出 30 秒诊断握手，采后 token 已失效；该组保持 BLOCKED，原因是采图未完成，底层长阻塞原因未定，不据此断言产品 PASS 或产品回归。后续采图命令加 8 秒上限，只在相同 token 仍有效时允许一次传输重试，失败尝试也写入索引；视觉失败/前台拒绝不重拍。
- ACK 回显只作为握手记录，不再误计为新 SHOT。相关离线回归目前 10 PASS，覆盖协议 URL、真实 404、前台保护、过期/跨阶段 token、精确 ACK 与传输超时重试。
- 像素复核固定 ROI=(80,360,1000,820)，屏幕 1080×2376。已从原始图人工核对该矩形只包含测试视频，排除了系统栏、验证页日志和片源时间戳。工具保留原始 PNG、相邻帧差值、黑像素分类与联系表；不以 vid/no 或截图存在代替运动证据。

最终 CP0 握手诊断 APK SHA256=`e0d9f938c260b9fddb5f08b219c1cacc2cfb867e1b993c99acccb6ffa09904d2`，最终当前 APK=`a7e4ccc9954a643a4843198ccd50247ff1f357d4b3de1dbd243aa2909875dd7d`，均安装拉回逐值核验。CP0 `cp0-close-keepalive-r3-1917` 原五轮中 S14 5 轮完整，S7 第 2–5 轮完整，首轮一组缺测。显式补采 `cp0-close-keepalive-supp-1945` 一轮 24/24 组完整；工具保留所有尝试，仅允许用显式新尝试补充采图不完整的轮次，完整的原生/像素 FAIL 不能被筛掉。最终选择清单写入 visual-review.json，原缺测不改判。

CP0 S1/S13 新基线 `cp0-close-keepalive-core-1949`：S1 五轮（每轮 25/50/100 GOP、hold=3s）共 15/15 原生 PASS，S13 五轮 5/5 PASS。S1 的 grace 是允许的恢复回退信号，不冒充首帧解码时延；H42/H43 等完整矩阵结论不由本次 S 场景代替。当前 S1/S13 同样独立重跑五轮，再完成当前视觉五轮。

当前 S1/S13 独立复测 `cp1-close-keepalive-core-1955` 同样为 S1 15/15、S13 5/5 原生 PASS。两边各 5 轮、每轮子样本数严格相同，S1 各轮 GOP 集合均为 {25,50,100}；S13 均 after=no/yes、stillHolding=true。新对照证据 `example/tool/coverage_evidence/cp1-close-keepalive-core-comparison.json`，没有使用旧 CP1 PASS 补计本轮。

外层适配器补充缺陷：`cp1_closeout_batch.py` 的外层 run-id 带 `-host`，旧完成头却填写原生 run-id，导致外层在 worker exit=0 后误报 identity HARNESS（H28/UI 套件/core 的原生采样均未受影响）。已分别保存 host/native 两个 ID，并补回归验证旧头被拒、新头通过。旧完成 JSON 与外层误报日志未改写；`cp1-closeout-native-audit.json` 独立校验四份原始数据、实际 worker exit=0、原生 schema 与修正后的命名映射，确认仅身份头差异，H28 90 条与 skin 12 条目标快照及两版 core 原生数据完整。相关 Python 回归最终 11 PASS。

keepAlive 最终复核：当前 `cp1-close-keepalive-2002` 五轮各 24/24 组具有阶段 token、双向前台保护和精确 ACK。S7 为 5/5 场景 PASS、100/100 次恢复具有非黑运动相邻帧；S14 5/5 PASS，holding 两阶段与 CP0 同为黑屏，restored 重新运动。人工检查当前五份联系表及 CP0 五轮/补采联系表，无持续黑屏或卡帧。`example/tool/coverage_evidence/cp1-close-keepalive-review/visual-review.json` 保存逐帧数字、选择清单与所有缺测尝试；CP0 S7 原首轮仍 BLOCKED。原始 CHECK 的人工复核 BLOCKED 不回写，综合判定另存。S1/S13 两版各五轮原生对照 PASS；因此四场景当前 20/20，CP0 同口径有效基线齐备。

最终 Python closeout 回归 12 PASS，矩阵回归 56 PASS，diff --check 无错误。原文中的 5/10/11 指开发过程中的测试数，最终以 12 为准。协议回退的 2 红→2 绿只证明绝对 URI 输出契约，不能单独证明原始合法相对 URI 是夹具缺陷；已增加保留原始 root-relative 正文的真机对照，以免掩盖产品/原生协议问题。

原始 root-relative 对照 `cp1-close-edgepause-relative-2023`（最终当前 APK、产品 lib 未改）：pause 10/10、fallback 10/10 PASS，run_matrix=0，harness=[]；CHECK records[273, 497, 724, 932, 1143, 1355, 1565, 1759, 1966, 2158, 2347, 2537, 2725, 2910, 3099, 3282, 3472, 3655, 3838, 4018]。证据 `example/tool/coverage_evidence/matrix-cp1-close-edgepause-relative-2023/matrix-cp1-close-edgepause-relative-2023-cp1-edgepause.json`，旁边 `.requests.json` 保留实际相对 URI 正文、分片存在性/字节数及响应状态。本轮未复现旧协议错误，因此无法据绝对 URI 修正断定旧问题是夹具缺陷；原 `matrix-cp1-edgepause-20261103-1542` records[1256,1258,1281] 的无协议报错和 records[1539,1540] 的超时仍未完成服务/原生责任归因。最终功能采样两套 URI 共 40 PASS，但该历史归因独立保持 BLOCKED，CP1 总表不以功能 PASS 覆盖此阻塞。

本项最终 Flutter 恢复就绪/探测回归实测 23 PASS，日志 `example/tool/coverage_evidence/cp1-close-blocked-flutter-tests.log`；无 lib 修复，产品红绿数 0。协议输出 2 红→2 绿属于夹具契约回归，不是产品根因证明。

## 5. Windows 安静模式与三次采样

四项原生功能各3/3 PASS：F3三模式各1、dispose三轮（普通/代理各两次，共12调用）、V6三轮（误差均0ms）、V10三轮（route/TickerMode、0崩溃）。证据 `example/tool/coverage_evidence/win-cp1-close-2043/result.json`；7次有效启动全部经win_policy、640×360、NOACTIVATE/TOOLWINDOW，逐100ms观察前台违规0。完整安静记录 `2026-11-03-win-quiet-mode.md`。CP0 Windows缺数字基线，F3/dispose/V6比较仍BLOCKED；V10绝对功能线PASS。

本项 Flutter test 0；Python策略11 PASS、静态焦点闸门PASS、matrix --check PASS。构建先遇CMake/VS兼容问题，只改生成cache。首次成功构建因缓存默认prefix误写既有Program Files目录，且本树启动缺DLL失败；无用例样本。无旧备份不能安全回滚外部覆盖，已明确向用户报告，清单保留。现构建前prefix及构建后完整安装路径双重检查，随后构建/采样均限定本树。详见安静记录和 external-install-incident.json，不声称所有写入均符合原范围约束。

## 6. 报告与总计划收口

16行最终 PASS13 / FAIL0 / BLOCKED3，细分49行 PASS39 / BLOCKED10。原15条FAIL原样保留、更新行previous保留旧数字、缺测及归因不被功能PASS覆盖。7b历史协议责任未定；B块仍缺系统字段/有效抽帧/底栏刺激/性能基线；Windows缺CP0数字比较。额外POD2两行FirstFrame公共契约缺测保留，不计入16行。`cp1_closeout_results.py` 从固定原报告revision读取，验证原生CHECK数量、哈希、落点、视觉对照与原始失败数组；逐行输出证据路径及下标。

最终设备恢复 VERIFIED：音量0、常亮7、既有gnirehtet映射与原始值完全一致；当前APK拉回SHA256=a7e4ccc9954a643a4843198ccd50247ff1f357d4b3de1dbd243aa2909875dd7d。原恢复记录另存 `cp1-original-session-restored-before-closeout.json`；未遗留本次Windows应用/源服务/ffmpeg子进程。越界构建写入既有Program Files目录的偏差及不可恢复原因同时写入报告与总计划，没有隐藏。
