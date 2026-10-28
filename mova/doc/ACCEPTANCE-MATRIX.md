# mova 验收矩阵

> 最后更新：2026-10-28（回填本轮单测与真机用例） · 范围：`mova` 子工程（Flutter 视频播放插件，基于 media_kit/libmpv）。
> **用途**：一份文档回答「每项能力怎么验、现在验到哪、还缺什么」。取代 2026-10-27 的三份矩阵（v1 `test-matrix`、v2 `matrix-v2`、`ledger`，已改成指针页，最后一版见 git `dbf95f6`）。
> **读者**：没有任何会话上下文的 AI 或人。只读本文 + 文中链接就能接着做。
> **事实口径**：每个「最近结论」都带出处；盘点里没有结论的写「未跑/待确认」，不脑补。单测基线 **1738 项全绿**（2026-10-28 回填后，主会话实跑完整 `flutter test` 得 `+1738: All tests passed!`、0 skip，`flutter analyze lib test` 0 issues；矩阵初稿成稿时的基线是 1519）。真机列只有历史结论；**本轮新增的真机用例都只做了离线校验（`run_matrix.py --check`、unittest），没有上机**，其「最近结论」一律保持「未跑」。

## 0. 三档定义与判定流程

| 档 | 一句话 | 谁给结论 | 验收动作 |
|---|---|---|---|
| ① 纯单测 | 结论只由 mova 自己的代码决定，不依赖 mpv/系统行为 | 单测 | `flutter test` 全绿即验收；不上真机 |
| ② 单测 + 真机核对 | 逻辑能单测，但输入/时机来自 mpv 或系统 | 单测穷举分支 + 真机跑代表路径核对「假设」 | 单测绿 **且** 对应 H 假设在真机核对过；假设被证伪要回头改假内核或产品 |
| ③ 只能真机 | 渲染/画面、手势手感、PiP 窗口、格式裁剪面、ABI/混淆、音频焦点、息屏、网络切换、浸泡等 | 真机 | 只有真机用例，没有单测面（或单测只承载其中的纯逻辑子点，那部分归 ①） |

**判定流程**（对每个能力/子点逐条问）：

1. 把它依赖的真实组件（mpv 内核、Android 系统、GPU）全换成假的，结论还成立吗？成立 → **①**。
2. 不成立，但能用假实现喂各种输入把分支穷举出来？→ **②**，并写出「假设」（假内核默认做了什么、真实 mpv 是否真这样做），挂 H 编号。
3. 假实现喂不出来（没有可替换的接口，或结论本身就是「画面/手感/系统行为」）→ **③**。

同一个编号常常跨档：逻辑分支是 ①，输入来自 mpv 的部分是 ②，纯画面/系统是 ③。跨档的编号拆成多行（`A8-①`、`A8-②`…），每行只写这一档负责的子点。

**文档导航**：§1 编号规则 · §2 通用约束与日志规范 · §3 三档矩阵（3.1 ① / 3.2 ② / 3.3 ③）· §4 假设清单 · §5 缺口清单 · §6 待拍板记录（已全部决定） · §7 修订记录 · §8 附录：公开类型台账 · §9 计数汇总 · §10 编号总索引。

**出处缩写**（均在 `doc/plans/` 下，前缀 `2026-10-27-device-coverage-`）：`rerun.md` = `…-rerun.md`（复跑总表）；`retest.md`/`retest2…6.md` = `…-android-retest*.md`（Android 复测各轮，retest6 实为 rerun7）；`results.md` = `…-results.md`（首轮）；`windows-retest.md`。其余：`unit-trace`/`device-trace`/`assumptions` 指本次合并用的三份只读盘点（2026-10-28，草稿存于会话暂存区，结论已并入本文，不入库）。

## 1. 编号规则

- **沿用原编号**：`A`（公开 API）、`C`（配置对象）、`E`（事件）、`U`（UI 组件）、`F`（功能场景）、`N`（新增 API）、`S`（皮肤专项）、`P`（公开类型家族）、`G`（覆盖缺口）。`example/tool/matrix_manifest.json`、`run_matrix.py` 和历次结果文档都引用这些编号，**不重新编号**。
- **行编号 = 原编号 + 档位后缀**：`A8-①`、`A8-②`。一个编号只落在一档时也带后缀（`A1-①`），这样每行自描述所在档，也不会和 §10 的总索引混淆。
- **E 组的键是事件类名**：写成 `E.MovaReady-②`。三个事件改过名，**manifest 与 `run_matrix.py` 仍用旧名当键**：`MovaCutoverChange`（旧 `MovaSwapChange`）、`MovaKeepAliveChange`（旧 `MovaStandbyChange`）、`MovaKeepAliveResume`（旧 `MovaStandbyResume`）。`E1`（完整事件序列）、`E2`（关闭态零事件）是普通编号。
- **S 编号**按「检查项 × 五套皮肤」展开成矩阵，放在 ③ 档（§3.3.S）；其中纯逻辑可单测的 `S1/S12/S13/S14` 在 ① 档各有一行。
- **编号命名空间冲突**：`keep_alive_auto.dart` 的 `S1…S17`（保活场景）、`main_videocontroller_verify.dart` 的 `E1…E12`、`he_auto.dart` 的 `V1…V11`、`main_review_fixes_verify*.dart` 的 `V*`，**与矩阵编号无关**。引用这些用例一律写 `suite:case`，如 `keep_alive_auto:S14`、`he_auto:V6`。
- **用例位置写法**：manifest 批次 id（`api`、`hls-native`…）+ 验证页 `文件:函数/case`；`example/lib/` 下，已去掉 rerun6/rerun7 副本后缀。
- **新增编号**接在各组末尾，并注明原因（下表）。新增的七个编号都来自盘点发现的「矩阵漏收」，不是新需求：

| 新增编号 | 内容 | 新增原因 |
|---|---|---|
| A34-① | 架构守卫：`core/` 不得 import flutter（`purity_test.dart`） | 旧矩阵无架构约束编号，该测试对不上任何编号 |
| A35-①/② | `MovaMpvKernel` 按格式限制 mpv 后向缓冲并还原（`mpv_kernel_live_cache_test.dart` 25 项） | 整块能力旧矩阵完全没收，仅在 F15/G3.3 挂边 |
| C18-① | `MovaReportConfig.heartbeat` 周期上报 | C13 只提 `qoe` 开关，该字段矩阵未列 |
| N24-① | 开放性对账（默认关闭 + 配置可注入 + 无副作用，`openness_*_test` 9 个文件） | 旧矩阵没有这一类要求 |
| F17-② | 保活出声 / 到期断流（计划未落地） | 计划 `2026-10-27-keepalive-audible-and-disconnect.md` 存在、代码未实现，需有编号承接，状态记「未实现」 |
| P20-① | 29 个顶层纯函数/常量 | 旧矩阵与台账只列类型不列函数 |
| P21-① | 公开成员级覆盖 | 「285 个类型」不等于成员级验收 |

## 2. 通用约束与日志规范

### 2.1 通用约束（真机用例通用）

- **设备**：`adb devices` 里的 `7NQBB23606003715`（STG-AL00，arm64，Android 12）。测前确认**亮屏且已解锁**（`adb shell dumpsys window | grep isKeyguardShowing`），锁屏时所有涉及渲染面的结果作废（2026-10-27 某轮因锁屏全部 BLOCKED）。
- **构造引擎一律 `createMovaEngine()`**（`lib/src/platform_impl/wiring.dart`），不要裸 `MovaEngine()`（平台端口默认 noop）。无界面的引擎用 `audioOnly: true`——创建了 `VideoController` 却不挂界面会让 media_kit 卡死。`createMovaEngine()` 在 debug 下走 100ms 轮询、release 才走原生回调（`pollInDebug: kDebugMode`），**真机结论一律用 release**。
- **默认配置没有原生事件泵**：F3/A17 的全部真机复测都开了 `createMovaEngine(preciseFirstFrame: true)`；默认 `createMovaEngine()` 下档位落地走 `buffering` 下降沿，这条路径零真机数据（H28）。
- **判据只用真实事件/状态**（`events`/`states`/`renderEpoch`/`MovaDone` 时间戳、mpv 原生属性读回），不用墙钟猜、不用临近 EOF 的 seek；URL 加时间戳防缓存；时间类数字至少 3 次取均值并列全部样本。
- **验证页**放 `example/lib/verify_auto/` 与 `example/lib/main_coverage_*.dart`；**验证阶段不改 `lib/**`**，发现 bug 只记录复现步骤与证据。
- **本地源**：`example/tool/verify_sources/` 有本地 HTTP 源，经 `adb reverse` 映射；联网多码率 HLS 可用 `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`。
- **起点干净**：先 `flutter test`（基线 **1738** 项全绿）与 `flutter analyze lib test`（0 issues），再上真机。
- **新名**：`MovaCutover*`（旧 `MovaSwap*`）、`MovaKeepAlive*`（旧 `MovaStandby*`）、`MovaAds`/`MovaFeed`/`MovaPlaylist`/`MovaMini`（旧 `*Controller`）。旧名只保留类型位置与构造器的别名；`setStandby`/`swapTo`/`MovaOpts(swap:/standby:)` **无别名**。
- **一键入口**：`python example/tool/run_matrix.py --list|--check|--dry-run`（38 批〔含本轮 12 个 `gap-*` 批次〕、135 个 v1 编号、6 个 manual；`--check` 离线校验编号/覆盖/依赖/脚本语法）。入口说明见 `example/tool/README-matrix.md`。入口只覆盖 v1 的 135 个编号，S/P/G 与设备端完整 L 日志不在其中。
- **真机 gap 用例的触摸注入（2026-10-28，有意偏离 L 规范第 6 条）**：`gap-skin` 等批次的触摸经应用内 `GestureBinding.handlePointerEvent` 注入（与真实触摸同一命中路径与手势竞技场），**没有**用 `adb shell input`——转屏/全屏后宿主侧坐标要重新定位，盲点不可靠。每次注入仍打印逻辑坐标、命中路径前 8 个 target 与等价的 `adb shell input tap` 物理坐标，便于对照。用例位置：`example/lib/main_coverage_gap.dart` + `example/lib/verify_auto/coverage_gap.dart`、`coverage_gap_skin.dart`，宿主驱动 `example/tool/coverage_gap.py`，批次见 §5.2.5。

### 2.2 L 日志规范（所有验证页与脚本强制遵守；原文保留）

目的：任何一条 FAIL 不用重跑就能定位。**日志不够详细本身算验证页缺陷。**

1. **统一前缀与格式**：每行 `[MOVA-COV] <ISO时间ms> <run=运行ID> <case=编号> <kind> <内容>`。`kind` 取 `BEGIN/STEP/CALL/RET/EVENT/STATE/EXPECT/ACTUAL/VERDICT/SHOT/ERROR/END`。
2. **每个 API 调用都打 `CALL`（方法名 + 实参）与 `RET`（返回值或抛出的异常类型+消息+栈）**，包括预期会抛的调用。不允许吞异常。
3. **每个判定必须成对输出 `EXPECT` 与 `ACTUAL`**（含数值、单位、容差），再输出 `VERDICT PASS|FAIL|BLOCKED`；FAIL 行要带差值。
4. **事件与状态**：用例期间订阅 `events`/`states`，把每个事件按到达顺序打 `EVENT`（类型名 + 全部字段 + 当时 `engine.state` 关键字段）；每个 STEP 前后各打一次 `STATE` 快照（position/duration/playing/buffering/rendered/size/volume/rate/fit/zoom/locked/fullscreen/pip/mini/keepAlivePhase/renderEpoch/sourceIndex/playbackIntent）。
5. **FAIL 现场**：FAIL 时自动补打最近 50 条事件、`dumpsys window`（亮屏/方向/焦点）、`dumpsys audio`（音量类）、一张 `screencap`，路径写进 `SHOT` 行。
6. **皮肤用例额外打**：当前皮肤类名、`components()` 的 `name` 列表、各 `MovaSlot` 实际挂载组件、触摸注入坐标与手势类型（`adb shell input` 的原始命令）。
7. **分层落盘**：设备端 logcat 全量（`--pid`）→ `coverage_evidence/rerun2-<run>.logcat`；宿主端脚本自身日志（含每次 adb 命令、退出码、耗时）→ `rerun2-<run>.driver.log`；逐用例 JSON 汇总 → `rerun2-<run>.json`。三份用 `run=` 关联。
8. **脚本自身错误**必须与产品 FAIL 区分：验证页/脚本异常一律打 `ERROR kind=HARNESS`，在报告里单列「验证器问题」，不得算作库缺陷。
9. **时间**：判据用事件时间戳差，不用墙钟；每个计时类数字至少 3 次取均值并打印全部样本。
10. 日志不得含密钥/账号；本地源 URL 带时间戳防缓存，打印完整 URL。
11. **（2026-10-28 补）现有验证页与 L 规范的差距**：`run_matrix.py` 有宿主 driver 日志与异常补证，但现有验证页用的是私有前缀（`CHECK`/`VIDEO`、`HE`、`KeepAlive`），未见全部 API 的 `CALL`/`RET`、`EXPECT`/`ACTUAL` 与 L 规范逐项对应；**完整日志规范的合规率待确认，不能把脚本退出码 0 算 PASS**。设备端完整 L 日志（上面第 1、2、3、5 条）仍未实现。出处：`example/lib/main_coverage_api.dart:42`、`example/tool/README-matrix.md:26`。

## 3. 三档矩阵

**列说明**：
- `编号`：原编号 + 档位后缀（§1）。E 组的键是事件类名。
- `单测位置`：`文件:行号 名称`，路径相对 `test/`（行号取自盘点，可能有小偏差，引用前对一下）；`⟨缺：…⟩` 是该编号单测还没覆盖的子点；同编号后续行写「同 X-①」；`缺` = 没有对应单测。
- `真机用例`：manifest 批次 id + 验证页 `文件:函数{case…}`（`example/lib/` 下，已合并 rerun6/rerun7 副本）；`—` = 本档不上真机；`缺` = 没有已定位用例。
- `依赖假设`（仅 ②）：该行单测依赖的假内核/假端口假设，H 编号见 §4；③ 档写「参见 Hxx」（只是关联，不是单测依赖）。
- `最近结论`：① 档写单测覆盖口径（全 / 部分 / 缺，来自盘点；基线 1738 全绿，2026-10-28 回填）+ 历史真机结论；② ③ 档写真机结论 + 出处（`rerun.md:行号` 等，缩写见文首）。**结论是整个编号的历史结论，不一定对这一档的子点逐条有证据**；FAIL 若属旧预期会明说。v2 的 S/P/G 没有独立结论，统一写「未跑」。
- `缺口`：`P0-01…` 是 §5.1.1 的单测缺口编号；`真机缺` = 该档没有已定位真机用例。

**行数**：① 158 行 · ② 79 行 · ③ 54 行（另有 S 矩阵 80 格）。

### 3.1 ① 纯单测

结论只由 mova 自己的代码决定，不依赖 mpv/系统行为。验收 = 相关单测绿 + 无未解释的缺口。真机列一律写「—」；个别历史真机结论附在「最近结论」里，仅供参考，不是本档判据。

#### A 公开 API（35 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| A1-① | `events`/`states`/`progress`/`uiStates` 四条流：多订阅者都收到同一序列（不看 `isBroadcast`）；`dispose` 后四条流关闭；`progress` 单调推进 | `core/bus_test.dart` :7 emits current value to new listeners / :20 skips duplicates / :33 select / :45,:59 throttleStream；`core/engine_test.dart` :72 position is exposed on the throttled progress stream, not states；`core/cutover/cutover_engine_test.dart` :49,:64 states/progress/events/uiStates forward / :125 dispose closes own streams（仅代理）；`core/api_test.dart` :7 FakeMovaApi replays current state（夹具自测）；`core/engine_streams_test.dart` :61 A1 多订阅者（:62 events / :82 states / :108 uiStates / :122 progress 各两个订阅者收到同一序列且位置依次到达 / :96 迟到订阅者从当前值起 / :143 取消订阅不影响其他人）；同文件 :161 A23 dispose 后四条流都结束（:162）、dispose 后才订阅的得到 done（:182） | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:173） | — （已补：P0-05, P0-07） |
| A2-① | `state` 各字段与对应事件载荷逐字段对账（position/duration/buffering/playing/size/volume/rate/fit/zoom/locked/fullscreen/pip/mini/rendered/sourceIndex/playbackIntent/keepAlivePhase/renderEpoch） | `core/state_test.dart` :9 copyWith / :18 == / :25 defaults / :37 rendered / :60 pipSupported / :67-80 renderEpoch / :86-111 mini / :115 keepAlivePhase；`core/engine_test.dart` :61 kernel state is reduced into MovaState / :1555-1605 volume/brightness state=event；`core/engine_rate_test.dart` :34 rate 的 state = 事件载荷；`core/engine_verbs_test.dart` :200 locked / :323 fit / :330 zoom / :353 size 的事件载荷 ⟨缺：无“逐字段 state ↔ 事件载荷”全量对照（position/duration/buffering/volume/pip/mini 等其余字段仍是各自散点）⟩ | — | 单测 部分；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:174） | — |
| A3-① | `renderHandle`：普通引擎非空、`audioOnly` 为 null、首次读取才建 VideoController（懒创建）、普通引擎 `renderEpoch` 恒 0、handle 变化重建 | `core/kernel_contract_test.dart` :29,:41,:47,:58 null/non-null handle 透传；`core/audio_only_test.dart` :14 audio-only kernel no render handle / :44 VideoController attached in exactly two guarded places；`core/kernel/mpv_kernel_video_test.dart` :92-187 lazy 创建时序（读取前不建、只建一次、audioOnly 不碰）；`core/engine_test.dart` :1684 renderEpoch stays 0 on a plain MovaEngine；`ui/player_test.dart` :116 null renderHandle 占位 / :75,:92 handle 变化重建 | — | 单测 全；历史真机 PASS（rerun.md:35） | — |
| A4-① | `pipSupported`：端口应答后翻转、端口抛错保持 false、与 `state.pipSupported` 一致、PiP 按钮显隐 | `core/engine_test.dart` :1468 pipSupported starts false and flips once port answers / :1504 stays false when port throws；`core/state_test.dart` :60 pipSupported defaults false；`ui/top_bar_test.dart` :26,:33 pip 按钮显隐；`core/audio_only_scenarios_test.dart` :426 audio-only no pip support | — | 单测 全；历史真机 PASS（rerun.md:36） | — |
| A5-① | `open(source, autoPlay)`：autoPlay 真/假；返回 `Future<bool>`（见 N8）；换源清残留 position/duration/rendered；`MovaSource.sameAs`；recovery 关时 open 失败照旧抛、开时走恢复 | `core/engine_test.dart` :35 open emits SourceChange then forwards / :156,:473,:490 换源清残留 / :538 open() reports accepted / :638 showOnStart；`core/first_frame_engine_test.dart` :34 open() zeroes rendered and previous frame size / :154 second open resets / :171 observations dropped while open in flight / :137 paused open；`core/recovery/engine_recovery_test.dart` :78 #1 recovery 关：open() 仍抛、无 Timer / :236 #8 开：open 抛→openThrew→重试；`core/recovery/review_regression_test.dart` :187 #8 rejected open preserves accepted session；`core/model_test.dart` :227-243 MovaSource.sameAs；`core/engine_dispose_race_test.dart` :77 open 挂在 beforeOpen 时 dispose | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:175） | — |
| A6-① | `play`/`pause`/`playOrPause`：`MovaPlay`/`MovaPause` 事件、`playbackIntent` 独立于内核 playing、重复调用幂等、`playOrPause` 按 `state.playing` 分流 | `core/engine_test.dart` :504 pause() during async beforePlay not overridden / :554 beforePlay can veto / :611,:625 play() after completion；`core/keep_alive/engine_keep_alive_rules_test.dart` :26 pause() out of a hold / :44 pause on non-hold = 单次 kernel pause / :56 play() while holding；`core/audio_only_scenarios_test.dart` :48,:114 playOrPause 无渲染面；`ui/audio_only_interaction_test.dart` :54 centre play 序列；`core/engine_verbs_test.dart` :120 A6 play/pause/playOrPause（:121 内核 playing 边沿 → MovaPlay/MovaPause 与 state.playing / :134 completed=true → 恰一个 MovaDone / :147 play()/pause() 驱动 playbackIntent 且独立于内核 playing / :161,:168 重复调用幂等 / :175 playOrPause 按 state.playing 分流 / :187 内核侧暂停（如音频焦点丢失）不改 intent） | — | 单测 全；历史真机 PASS（rerun.md:38） | — （已补：P0-01, P2-09） |
| A7-① | `seek`/`seekBy`：越界钳制（负数/超时长）、直播被拦、`MovaSeek`/`MovaSeeked` 载荷、加载中寄存后兑现、乐观更新 + 回声抑制、续播 seek 重发 | `core/engine_test.dart` :84 live ignored when seekMode off / :94 dvr clamp / :114 beforeSeek cancel / :124,:144 VOD seek parked & clamped / :473 seekBy after open / :518 stale beforeSeek / :1294 live clamp / :1513 optimistic + 回声抑制 / :261,:292 续播 seek 重发；`core/first_frame_engine_test.dart` :223,:236,:249 switchQuality 续播 seek 落地时序；`core/engine_verbs_test.dart` :210 A7 seek/seekBy（:211,:217 时长已知：负值钳到 0、超长钳到时长 / :223,:233 MovaSeek → MovaSeeked，载荷为钳后值 / :241 seekBy / :255,:270 时长未知：先寄存只发 MovaSeek，兑现时按真实时长钳 / :278 直播 seekMode 关闭不发任何事件 / :290,:305,:313 负向 seek 寄存前钳到 0）；`core/engine_seek_drop_test.dart` :92 H19 / :179 H18 / :210 点播 seek 被内核丢弃（校验 + 重发最多 3 次、新 seek 作废旧链、暂停态同样收敛、直播不起校验链） | — | 单测 全（DVR 直播 seek 未接校验链，见 P2-15）；历史真机 PASS（rerun.md:39） | — （已补：P0-04；DVR 直播 seek 未接校验链，见 P2-15） |
| A8-① | `setVolume`：0–100 钳制（单位是百分比不是 0–1）、`MovaVolumeChange`、经 `MovaVolumePort` 下发、预热静音不写音量端口 | `core/engine_test.dart` :1555 routes to kernel without port / :1561,:1605 clamp 0–100 state+event / :1633 routes to volume port / :1657 seeds baseline / :1670 MovaCallbackVolumePort；`method_channel_test.dart` :27,:40,:46 setSystemVolume/getSystemVolume 通道；`core/cutover/cutover_warm_mute_test.dart` :31,:86 预热静音不写音量端口 | — | 单测 全；历史真机 PASS（rerun.md:176） | P1-12 |
| A9-① | `setBrightness`：0–1 钳制、`MovaBrightChange`、经亮度端口 | `core/engine_test.dart` :1590,:1617 clamp 0–1 in port/state/event；`core/ports_test.dart` :5 fallback brightness port | — | 单测 全；历史真机 PASS（rerun.md:177） | — |
| A10-① | `setRate`：kernel 下发、`state.rate`、`MovaRateChange`、广告 1x 并回正片恢复；入口钳到 0.25–4.0、NaN 当 1.0（`kMovaMinRate`/`kMovaMaxRate`/`kMovaNormalRate`、`movaClampRate`；§6 已决定并落地） | `core/cutover/cutover_engine_defects_test.dart` :269 MovaWarmPlan.rate overrides inherited rate；`core/ad_first_frame_test.dart` :137,:161,:191 ad rate handling on cutover path；`core/ads_test.dart` :664 ad rate is declared in the cutover plan；`ui/speed_button_test.dart` :9,:30 循环倍速（FakeApi）；`core/engine_dispose_race_test.dart` :90 setRate resuming after dispose；`core/engine_rate_test.dart` :33 MovaEngine.setRate（:34 范围内：内核/state/单次 MovaRateChange / :42,:49 钳到 0.25–4.0 / :58 NaN→1.0 / :66 边界值原样保留） ⟨缺：换源后倍速保持/复位（契约未定，无断言）⟩ | — | 单测 部分；历史真机 PASS（rerun.md:42） | — （已补：P0-02；换源后倍速待定契约） |
| A11-① | `setFit`：全部 `MovaFit` 取值、`state.fit` + `MovaFitChange`、构造期种子不发事件、声明式 fit 只应用一次 | `core/engine_test.dart` :46 fit defaults to contain / :50 constructor fit seeds state without MovaFitChange；`ui/player_fit_test.dart` :22-55 MovaPlayer fit 声明式（FakeApi）；`ui/top_bar_test.dart` :15 fit 按钮循环；`core/model_test.dart` :67 MovaFit 循环；`ui/format_test.dart` :7 movaBoxFit；`ui/video_rect_test.dart` :8-81 computeVideoContentRect；`core/engine_verbs_test.dart` :323 setFit 存模式并发恰一个 MovaFitChange（A11/A12/A14 group :322） | — | 单测 全；历史真机 PASS（rerun.md:43） | — （已补：P1-01） |
| A12-① | `setZoom`：低于 1.0 或 NaN 钳到 1.0、上限 API 不限制（`maxZoom` 只约束捏合手势）、`MovaZoomChange`；手势层 maxZoom 钳制与 pinchZoom 开关 | `core/engine_test.dart` :1573 setZoom clamps <1.0 and NaN to 1.0, no upper bound；`core/options_test.dart` :23 MovaGestureConfig rejects maxZoom<1；`core/engine_verbs_test.dart` :330 setZoom 的 MovaZoomChange 载荷为钳后值；`ui/gesture_test.dart` :192 pinch zoom（:214 张开超过 maxZoom 钳到 maxZoom / :223 自定义 maxZoom 为上限 / :233 小幅张开按当前缩放计且不低于 1.0 / :253 pinchZoom:false 忽略双指） | — | 单测 全；历史真机 PASS（retest.md:137，仅专项子项） | — （已补：P1-01） |
| A13-① | `setLocked`：`state.locked` + `MovaLockChange`；锁定后 DefaultSkin 隐藏手势层与栏、锁定遮罩可解锁 | `core/audio_only_scenarios_test.dart` :408 lock verbs stay callable and do not throw（仅冒烟，state.locked 只断言 false）；`ui/overlays_test.dart` :21,:31 lock mask 吞点击/不渲染（FakeApi 推 locked）；`core/engine_verbs_test.dart` :199 A13 setLocked（:200 翻转 state.locked，每次调用一个 MovaLockChange）；`ui/skin_test.dart` :203 MovaDefaultSkin while locked（:221 未锁：栏在、开关为“锁定” / :232 锁定后上/中/下栏消失但解锁钮仍在 / :248 锁定后手势不向 api 下发任何调用 / :263 解锁后栏恢复） | —；相关（非本档判据）：批次 gap-skin；coverage_gap_skin:S7.{default,bilibili}.lock | 单测 全；历史真机 PASS（rerun.md:45） | — （已补：P0-03） |
| A14-① | `setFullscreen`：进/出全屏状态与事件、方向端口 apply/reset、尺寸晚到时重新应用方向、换指不复位方向、与小窗事件顺序 | `core/engine_test.dart` :787 re-applies orientation when size arrives later / :812 size changes while not fullscreen / :1819 mini↔fullscreen 事件顺序 / :1837 setMini(false) never re-sets fullscreen；`core/engine_dispose_race_test.dart` :101,:112,:135 dispose 时方向复位；`core/cutover/cutover_engine_defects_test.dart` :357,:386 全屏换指不复位方向；`core/engine_verbs_test.dart` :338 setFullscreen(true) 再 (false)：状态回落并重新应用方向端口；`ui/top_bar_test.dart` :129 fullscreen button（:130 窗口态点击进全屏 / :142 全屏态显示退出图标并点击退出） | — | 单测 全；历史真机 PASS（rerun.md:46） | — （已补：P1-01） |
| A15-① | `setMini`：state/单次事件/幂等/事件顺序、不碰 pip/orientation/volume、不改 `renderEpoch` 与渲染面 | `core/engine_test.dart` :1792 setMini group（flips state+单次事件 / :1805 幂等 / :1819 顺序 / :1844 不碰 pip/orientation/volume / :1862 dispose assert）；`core/state_test.dart` :86-111 mini；`ui/player_test.dart` :206,:222 mini 不改 renderEpoch/渲染面；`core/cutover/cutover_engine_test.dart` :296 setMini 转发到新引擎 | — | 单测 全；历史真机 PASS（retest.md:134，仅专项子项） | — |
| A16-① | `setOrientation`：`auto`/`portrait`/`landscape` 映射、`MovaOrientationChange`、强制方向带进全屏 | `core/engine_test.dart` :827 forces orientation/state/event / :849 forced orientation carried into fullscreen；`ui/orientation_test.dart` :9-59 preferredOrientationsFor/resolveOrientations；`core/orientation_model_test.dart` :6-14 toggled；`ui/top_bar_test.dart` :42,:65 方向按钮仅移动端；`core/engine_dispose_race_test.dart` :120 | — | 单测 全；历史真机 PASS（rerun.md:48） | P1-12 |
| A17-① | `loadQualities`/`switchQuality`：master 解析、`MovaQualityListChange`/`MovaQualityChange`、寄存续播、ABR 屏蔽（`_abrHold`）、过期响应丢弃 | `core/model_test.dart` :24-40 parseHlsMasterPlaylist；`core/engine_test.dart` :1693,:1714 loadQualities / :178-448 switchQuality 寄存续播、ABR 屏蔽、tally 清零 / :319 announces new variant；`core/first_frame_engine_test.dart` :191,:223,:236,:249；`core/recovery/failover_test.dart` :62,:91；`core/recovery/review_regression_test.dart` :221 #11 stale quality response discarded；`core/cutover/cutover_engine_test.dart` :552 Task 8 cutoverTo ↔ 换档语义；`core/engine_verbs_test.dart` :369 A17 loadQualities（:370 成功路径恰发一个 MovaQualityListChange 且与 state.qualities 一致，随后发当前档 / :391 非 m3u8 源清空列表且不发事件）；`ui/top_bar_test.dart` :154 quality button（:168 弹层列出每个档位且只勾选当前档 / :185 选中项先关弹层再 switchQuality / :199 当前为自动档时勾选自动）；`core/engine_seek_drop_test.dart` :92,:179 档位续播 seek 被丢后的校验重发 | — | 单测 全；历史真机 FAIL（最近完整三组 retest5.md:209，1/280）；暂停态补跑 PASS 60/60（retest6.md:54-60）；判据口径 <200ms 与 ±500ms 待统一 | — （已补：P1-05） |
| A18-① | `enterPip`：返回值、`state.pip` 跟随端口变化（含点 X 关闭的注入路径）、重复值不重发、进 PiP 唤醒保活 | `core/engine_test.dart` :1468 supported/flip / :1478 state.pip follows port changes（含点 X 关闭路径，注入 _ObservablePip）/ :1504；`core/keep_alive/engine_keep_alive_rules_test.dart` :143 entering PiP wakes hold；`ui/mini/mini_mount_test.dart` :39 enterPip 使小窗下线；`ui/top_bar_test.dart` :33；`core/audio_only_scenarios_test.dart` :426；`method_channel_test.dart` :53 PiP over the channel（通道层，同 N9-①） | — | 单测 全；历史真机 PASS（rerun.md:50） | — （已补：P0-06） |
| A19-① | `reload`：以当前 playIntent 重开当前源、无源时空操作、事件序列 | `core/keep_alive/engine_keep_alive_rules_test.dart` :122 reload 在 fallback/hold 下；`core/openness_keep_alive_test.dart` :38；`core/cutover/cutover_engine_test.dart` :95 转发；`core/engine_verbs_test.dart` :401 A19 reload（:402 以当前播放意图重开当前源 / :410 pause() 后以暂停态重开 / :417 无源时空操作） | —；相关（非本档判据）：批次 gap-skin；coverage_gap_skin:S9.{default,bilibili}.errorRetry | 单测 全；历史真机 PASS（rerun.md:51） | — （已补：P1-07） |
| A20-① | `backToLiveEdge`：dvr 窗口末端 seek / timeshift 重开原直播地址 / 显式 backToLive 策略 / 点播 no-op / `autoBackToLiveOnStall` | `core/engine_test.dart` :1339 dvr 模式 seek 窗口末端 / :1364 timeshift 模式重开原直播地址 / :1396 显式 backToLive 策略 / :1420 VOD no-op / :1428 autoBackToLiveOnStall；`ui/live_bar_test.dart` :73 按钮调 backToLiveEdge 而非 reload；`core/keep_alive/engine_keep_alive_rules_test.dart` :155,:187；`ui/auto_pause_test.dart` :231 | — | 单测 全；历史真机 PASS（rerun.md:52） | — |
| A21-① | `showControls`/`hideControls`/`showHud`/`setDragging`：`uiStates`、sticky、HUD 类型与文本、800ms 自动清除 | `core/engine_test.dart` :572 showHud/hideControls drive MovaUiState / :580 showHud text regression / :588 showHud without text clears / :595 open() arms auto-hide / :648 setDragging 载荷与释放；`ui/hud_test.dart` :11-71 HUD 渲染；`core/engine_verbs_test.dart` :424 A21 controls and HUD timers（:440 showControls 在 autoHideDelay 后隐藏 / :452,:461 sticky 不起计时并取消先前计时 / :471 重复调用重置倒计时 / :483 autoHide:false 常显 / :491 hideControls 取消待隐藏并立即隐藏 / :502 showHud 800ms 后清 hud 与 hudText / :514 再次 showHud 重置窗口） | — | 单测 全；历史真机 PASS（rerun.md:53） | — （已补：P1-08） |
| A22-① | `report(name, params)`：内置名与 `MovaReportName.custom`、参数透传、`==`/`hashCode` 按 value | `core/report/report_engine_test.dart` :56 report() forwards a MovaReportKind.action event / :10,:23,:42,:71；`core/report/report_cutover_test.dart` :8 代理转发；`core/report/name_test.dart` :6-37 内置名/custom/==/hashCode/Map key | — | 单测 全；历史真机 PASS（rerun.md:54） | — |
| A23-① | `dispose`：幂等、播放中/加载中/换源中/保活中/重试延迟中 dispose、方向复位、dispose 后四流关闭；契约：dispose 后全部公开动词 no-op，`open`/`enterPip`/`setWarmMute` 返回 false（2026-10-28 落地） | `core/engine_dispose_race_test.dart` :77,:90,:101,:112,:120,:128,:135；`core/engine_test.dart` :1584 dispose idempotent / :1862 dispose while mini asserts / :1872；`core/keep_alive/engine_keep_alive_enter_test.dart` :192 dispose while holding；`core/recovery/engine_recovery_test.dart` :374 dispose during retry delay；`core/first_frame_engine_test.dart` :262；`core/cutover/cutover_engine_test.dart` :532；`core/kernel/mpv_kernel_events_test.dart` :261,:294；`core/engine_streams_test.dart` :161 A23（:162 四条流都结束 / :182 dispose 后才订阅得到 done / :190 每个动词 dispose 后可调用且不抛 / :202 不产生事件 / :215 不再向内核 open / :228,:245 不触达已销毁内核 / :255 加载在途的 switchQuality 在 dispose 后不再下发 / :275 排在保活请求后的 play() 不越过 dispose）；`core/engine_fuzz_test.dart` :340 固定种子随机序列与 :354 连点 100 次，dispose 为终态；`core/cutover/cutover_engine_test.dart` :601 MovaCutoverEngine 销毁后动词全部 no-op（:615 / :648 prepare、cutoverTo、commit 不再新建影子引擎） | — | 单测 全；历史真机 PASS（retest.md:136，仅专项子项） | — （已补：P0-05, P0-07） |
| A24-① | `MovaCutoverEngine`：关闭态纯直通、开启预热 → 原子提交、短窗口降级、超时兜底、影子引擎 dispose、`MovaWarmPlan.rate`、触发/就绪策略 | `core/cutover/cutover_engine_test.dart` :32 disabled 直通 / :167 enabled 预热→原子提交 / :552 Task 8 / :619 0.5.0 Task 1；`core/cutover/cutover_engine_defects_test.dart` :191-473；`core/cutover/cutover_keep_alive_test.dart` :46-99；`core/cutover/cutover_warm_mute_test.dart` :31,:86,:117,:168；`core/cutover/plan_test.dart` :8-32；`core/cutover/trigger_test.dart` :8-54；`core/cutover/warm_test.dart` :21-145；`core/openness_cutover_test.dart` :13-100 | — | 单测 全；历史真机 PASS（rerun.md:56） | P1-06 |
| A25-① | `setKeepAlive`/`MovaKeepAlive`：off/holding/fallback/resuming 状态机、决策纯函数、`pause()` 结束待机、hold 期间看门狗/ABR/回边缘静默、守卫降级、`maxDuration` 计时 | `core/keep_alive/engine_keep_alive_enter_test.dart` :12-:192；`core/keep_alive/engine_keep_alive_rules_test.dart` :26-:304；`core/keep_alive/engine_keep_alive_wake_test.dart` :21-:196；`core/keep_alive/plan_test.dart` decideKeepAliveEntry/Wake；`core/keep_alive/config_test.dart` :6-45；`core/kernel/mpv_kernel_keep_alive_test.dart` :75-246；`core/kernel/audio_presence_test.dart` :6-27；`core/openness_keep_alive_test.dart` :12,:18,:56；`core/cutover/cutover_keep_alive_test.dart` :46-99 | — | 单测 全；历史真机 PASS（rerun.md:57） | — |
| A26-① | `MovaMini`：`show`/`showInPage`/`hide`/`close`/`isShowing`/`setRect`、`onClosed`/`onTapContent`、方式 A/B 互斥、转屏 `remapProportionally` | `ui/mini/mini_test.dart` :20-150；`ui/mini/mini_mount_test.dart` :17-356 方式 A/B/等价/互斥；`ui/mini/mini_window_test.dart` :48-216；`ui/mini/mini_skin_test.dart` :11-49；`core/openness_mini_test.dart` :16-52 | — | 单测 全；历史真机 PASS（rerun.md:58） | — |
| A27-① | `MovaAds`：`load`/`loadDeferred`/`playAdNow`/`skip`/`notifyClicked`；前贴/中插/后贴、pod 串联、失败策略、`waitsFor` 三层覆盖、delay/duration 与素材时间轴解耦 | `core/ads_test.dart` 98 项：前贴/中插/后贴/pod/playAdNow/skip/notifyClicked/loadDeferred/delay/duration/等待策略/失败兜底；`core/ads_session_test.dart` :29-77；`core/ad_first_frame_test.dart` :53-191；`core/ad_stale_first_frame_test.dart` :113-167；`core/ad/fail_test.dart` :21-63；`core/openness_ad_test.dart` :38-211；`ui/ad_overlay_test.dart` :37-243 | — | 单测 全；历史真机 PASS（rerun.md:59） | — |
| A28-① | `MovaPlaylist`：`next`/`previous`/`jumpTo`/`hasNext`、自动连播、边界不越界、`open` 被拒不前进下标、dispose | `core/playlist_test.dart` :44-170 next/previous/jumpTo/hasNext/自动连播/边界/dispose/乱序 jump；`ui/next_up_test.dart` :50-86 | — | 单测 全；历史真机 PASS（rerun.md:60） | — |
| A29-① | `MovaFeed`/`MovaFeedEnginePool`/`MovaFeedPrefetcher`：`ensure`/`activate`、邻居预热窗口、快速滑动取消与最终一致、池回收 | `core/feed_test.dart` :46-295；`core/engine_pool_test.dart` :33-231；`core/feed_prefetcher_test.dart` :7-31；`ui/feed_player_test.dart` :70-258 | — | 单测 全；历史真机 PASS（rerun.md:61） | — |
| A30-① | `MovaPreviewApi`：`requestAt`/`cancel`/`clear`、VTT 源、抽帧兜底源链、两级缓存、网络策略、断源链、crop 不入缓存、换源丢弃旧结果 | `core/preview/service_test.dart` 21 项 requestAt/cancel/clear/去抖/串行/网络策略/断源链；`core/preview/vtt_test.dart` :11-110；`core/preview/vtt_source_test.dart` :74-207；`core/preview/extractor_test.dart` :67-112；`core/preview/cache_test.dart` :12-79；`core/preview/disk_cache_test.dart` :29-115；`core/preview/two_level_cache_test.dart` :65-104；`core/preview/net_probe_test.dart` :44-76；`core/preview/hash_test.dart` :5-32；`core/preview/models_test.dart` :17-59；`platform_impl/net_probe_impl_test.dart` :6-23；`ui/preview_test.dart` :58-136；`core/openness_preview_test.dart` :84-215 | — | 单测 全；历史真机 PASS（rerun.md:62） | — |
| A31-① | `MovaSttApi`：`start`/`stop`、noEngine/noSource/disabled 阻塞、失败回滚可重试、cue → 字幕 → SRT → 分块存储（用脚本化假引擎） | `core/stt_test.dart` :25-100 MovaSttCue/Noop/Service 失败回滚/Config；`core/engine_test.dart` :942-1094 stt 面/noEngine/noSource/disabled 阻塞/cues 转发/current/dispose；`core/srt_test.dart` :7-69 formatSrt/parseSrt；`core/stt_subtitle_store_test.dart` :19-76；`core/stt_chunk_subtitle_store_test.dart` :19-81；`core/stt_model_provider_test.dart` :53-148；`ui/subtitle_test.dart` :12-95；`core/audio_only_scenarios_test.dart` :375；`core/stt_test.dart` :121 MovaSttService lifecycle（:133 start 带最新位置 / :141 重复 start 空操作 / :148 stop 只停引擎一次 / :159 stop 后可再 start / :168 cue 转发给所有订阅者 / :181 current 取覆盖播放头的 cue 并随 updatePosition / :194 重叠取最新 / :203 只保留最近 50 条 / :217 attach 清空 cue 并重置位置 / :231 阻塞原因各报一次 / :249 languages / :254 dispose 关流并释放引擎） | — | 单测 部分（组件级各有断言；`MovaSttService` 未串起字幕存储/模型/音频抽取，cue→存储→SRT 管线无集成用例；管线未集成，不算 FAIL）；历史真机 BLOCKED（rerun.md:181）：已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试 | — （已补：P1-13；管线未集成，见 §6 第 3 项） |
| A32-① | `MovaHook`：`play`/`seek`/`open` 放行/拒绝/改写、异步返回后复查、`onError` 转发与隔离、异常不拖垮引擎 | `core/interceptor_test.dart` :50 empty chain / :57 deny beforeOpen / :62 beforeSeek rewrite / :67 null cancels；`core/engine_test.dart` :114,:504,:518,:554；`ui/review_regression_test.dart` :128 #3 source null invalidates delayed beforeOpen；`core/interceptor_test.dart` :154 MovaHookChain.beforePlay（:155 全放行 / :162 首个 false 否决且后续钩子不再被问 / :169 链后段否决）/ :177 onError 链（:178 每个钩子都收到错误与栈 / :187 抛异常的钩子不挡后面的）/ :196 engine → hooks.onError（:197 内核错误到达所有钩子且仍写入 state / :210 恢复耗尽发 MovaGiveUpError）/ :236 钩子在 before* 里抛（:243 play 抛给调用方且 playbackIntent 不变 / :253 seek 抛且不触内核 / :261 open 抛且不加载源）；`core/report/report_engine_test.dart` :81 宿主上报回调抛异常只通知钩子 | — | 单测 全；历史真机 PASS（rerun.md:64） | — （已补：P1-02） |
| A33-① | `package:mova/testing.dart`：`MovaTestKernel`/`MovaTesting` 安装后平台端口空实现、显式 kernel 优先、reset、`stagedSourceOptions` | `testing/testing_test.dart` :40 零参 createMovaEngine / :49 端口空实现 / :58 显式 kernel 优先 / :64 reset / :74 / :96 MovaView / :127 stagedSourceOptions / :144 barrel 不导出 / :164,:178 keepAlive | — | 单测 全；历史真机 PASS（rerun.md:65） | P2-06 |
| A34-① | 架构守卫：`core/` 不得 import flutter，仅声明的例外可 import media_kit（`test/core/purity_test.dart`） ⟨新增：旧矩阵无架构约束编号，该测试对不上任何编号（unit-trace §2.1）⟩ | `core/purity_test.dart` 1 项：core 不得 import flutter、仅声明例外可 import media_kit | — | 单测 全 | — |
| A35-① | `MovaMpvKernel` 按真实格式（mp4/hls/whep/ts/rtsp）限制 mpv 后向缓冲，并在切源/失败/dispose 时还原（`mpv_kernel_live_cache_test.dart` 25 项） ⟨新增：整块能力旧矩阵完全没收（unit-trace §2.1），仅在 F15/G3.3 里挂了边⟩ | `core/kernel/mpv_kernel_live_cache_test.dart` 25 项（按格式限制缓冲，切源/失败/dispose 还原） | — | 单测 全 | — |

#### C 配置对象（18 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| C1-① | `preview`/`MovaPreviewConfig`：开关、来源顺序、缓存上限 | `core/options_test.dart` :62-125；`core/openness_preview_test.dart` :84-215 | — | 单测 全；历史真机 PASS（rerun.md:66） | — |
| C2-① | `live`/`MovaLiveConfig`：`urlBuilder`/`backToLive`/`autoBackToLiveOnStall`/`windowResolver`/`durationStep`；`resolveWindow`/`behindOf`/`atLiveEdge` | `core/options_test.dart` :125-172；`core/openness_live_test.dart` :8-87；`core/live/timeshift_test.dart` :13-62；`core/live/duration_throttle_test.dart` :35-89；`core/engine_test.dart` :1106-1428；`ui/live_bar_test.dart` :31-94 | — | 单测 全；历史真机 BLOCKED（rerun.md:182）：已测真实FLV/HLS durationStep、12s本地DVR、behind/回边缘三轮；未提供按behind URL返回历史且可控卡顿服务 | — |
| C3-① | `gesture`/`MovaGestureConfig`：默认左亮度/右音量、侧别 → 动作映射改配、水平拖动 seek、轴向、双击左右 ±10s、直播、`maxZoom` assert；长按现无实现（记录现状） | `core/options_test.dart` :18-29 默认映射/maxZoom assert；`ui/gesture_test.dart` :13-164 左右竖滑/改配/水平拖动/轴向/直播/双击；`ui/douyin_skin_test.dart` :71 单击播放暂停、双击点赞；`ui/gesture_test.dart` :192 pinch zoom（:214–:253 捏合钳制/开关）/ :264 single tap（:265,:278 单击切换控件显隐） | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:183） | P2-01（MovaGestureConfig copyWith/==，未做）；已补：P1-09 |
| C4-① | `abr`/`MovaAbrConfig`：`MovaBufferAbr` 触发与 reset、`MovaAbrDownShift`、hold 期间不喂 ABR；默认值/copyWith/== | `core/engine_test.dart` :656,:701 ABR downshift；`core/model_test.dart` :45,:58 MovaBufferAbr；`core/keep_alive/engine_keep_alive_rules_test.dart` :221 hold 期间不喂 ABR ⟨缺：MovaAbrConfig 默认值/copyWith/==（abr_config.dart:97，仅 1 个测试文件构造过它）⟩ | — | 单测 部分；历史真机 PASS（rerun.md:69） | P2-01 |
| C5-① | `controls`/`MovaCtrlsConfig`：`showOnStart`/`autoHideDelay`/sticky；默认值/copyWith/== | `core/engine_test.dart` :595 auto-hide per showOnStart/autoHideDelay；`core/audio_only_scenarios_test.dart` :394；`core/engine_verbs_test.dart` :452,:483 sticky 与 autoHide:false 组合 ⟨缺：默认值/copyWith/==（controls_config.dart:4）⟩ | — | 单测 部分；历史真机 PASS（rerun.md:70） | P2-01；已补：P1-08 |
| C6-① | `danmaku`/`MovaDanmakuConfig`：到点生成、过期回收、不重复；设计上仅展示宿主固定 items，无发送 API/输入框；轨道分配/密度/速度（缺） | `core/options_test.dart` :18,:173-195；`ui/danmaku_test.dart` :11,:18,:42；`ui/bilibili_skin_test.dart` :12-28 ⟨缺：轨道分配/密度/滚动速度未断言（仅“到点生成、过期回收、不重复”）⟩ | — | 单测 部分；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:184） | P2-13 |
| C7-① | `stt`/`MovaSttConfig`：同 A31 | `core/stt_test.dart` :67-100 | — | 单测 全；历史真机 BLOCKED（rerun.md:185）：已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试 | — |
| C8-① | `playlist`/`MovaPlaylistConfig`：自动连播、NextUp 卡片（取消/立即播放；无数字倒计时） | `core/playlist_test.dart` :44,:118,:126,:134；`ui/next_up_test.dart` :50-86 | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:186） | P2-01 |
| C9-① | `ads`/`MovaAdConfig`：默认关；排期；`waitsFor` 三层覆盖 | `core/options_test.dart` :253-349；`core/openness_ad_test.dart` :38-211 | — | 单测 全；历史真机 PASS（rerun.md:74） | — |
| C10-① | `strings`/`MovaStrs`、`theme`/`MovaTheme`：文案与主题替换、缓冲三字段、默认外观不变 | `core/options_test.dart` :41 fitLabel / :49 MovaStrs 整体替换；`ui/top_bar_test.dart` :85；`ui/live_bar_test.dart` :84；`ui/minimal_skin_test.dart` :53,:72,:86 MovaTheme 缓冲三字段 ⟨缺：MovaTheme 其余字段的 copyWith/==/默认外观不变（theme.dart:12）；MovaStrs copyWith（strings.dart:14）⟩ | — | 单测 部分；历史真机 PASS（rerun.md:75） | P2-01 |
| C11-① | `cutover`/`MovaCutoverConfig`（旧 `swap`/`MovaSwapConfig`）：默认关闭与开启 | `core/options_test.dart` :203-253；`core/openness_cutover_test.dart` :13-100 | — | 单测 全；历史真机 PASS（rerun.md:76） | — |
| C12-① | `mini`/`MovaMiniConfig`：默认关闭、吸边、`remapProportionally` 转屏不走位 | `core/options_test.dart` :349-394；`core/mini/placement_test.dart` :9-196 含 remapProportionally；`core/openness_mini_test.dart` :16-52 | — | 单测 全；历史真机 PASS（rerun.md:77） | — |
| C13-① | `report`/`MovaReportConfig`：`qoe:false` 零 QoE 事件、`heartbeat` 默认无 Timer；`qoe:true` 见 F7 | `core/report/config_test.dart` :8-88；`core/openness_report_test.dart` :50-142；`core/report/collector_test.dart` :42-82 qoe:false 零 QoE；`core/report/heartbeat_test.dart` :13-97 heartbeat 默认无 Timer | — | 单测 全；历史真机 PASS（rerun.md:78） | — |
| C14-① | `recovery`/`MovaRecoveryConfig`、`MovaTimeouts`：默认关、超时/重试/切换、按源 mpv 选项 | `core/recovery/config_test.dart` :9-103；`core/recovery/timeouts_test.dart` :10-59；`core/engine_source_options_test.dart` :48；`core/openness_host_test.dart` :23-68 | — | 单测 全；历史真机 PASS（rerun.md:79） | — |
| C15-① | `keepAlive`/`MovaKeepAliveConfig`（旧 `standby`/`MovaStandbyConfig`）：`maxDuration`/`resumeTimeout`/`allowHls` 默认值（保守） | `core/keep_alive/config_test.dart` :6 defaults are conservative / :15-45；`core/openness_keep_alive_test.dart` :12 | — | 单测 全；历史真机 PASS（rerun.md:80） | — |
| C16-① | TLS `tlsVerify`/`tlsCaFile`：默认不下发、CA 无 verify 不下发、开启先于 open、顺序 CA → verify → open；`createMovaEngine` 透传（缺） | `core/kernel/mpv_kernel_tls_test.dart` :48 默认不下发 / :55 CA 无 verify 不下发 / :62 开启先于 open / :69 CA→verify→open ⟨缺：createMovaEngine(tlsVerify/tlsCaFile) 透传到内核（wiring.dart:164-165,216-217，wiring_test 零引用 tls）⟩ | — | 单测 部分；历史真机 FAIL（原生 TLS：IP SAN 合法证书 5/5 被拒，H66；rerun.md:187） | P1-14 |
| C17-① | `MovaSource`：`alternatives`/`uris`/`pick`/`sameAs`、`sourceIndex`、请求头、按源 mpv 选项 | `core/model_test.dart` :227-273 sameAs/alternatives/uris/pick；`core/source_options_test.dart` :8-67；`core/engine_source_options_test.dart` :32-122；`core/kernel/mpv_kernel_source_options_test.dart` :129-233；`core/recovery/failover_test.dart` :47-128 | — | 单测 全；历史真机 PASS（rerun.md:82） | — |
| C18-① | `MovaReportConfig.heartbeat` 周期上报（`heartbeat_test.dart`） ⟨新增：旧 C13 只提 `qoe` 开关，heartbeat 字段矩阵未列（unit-trace §2.1）⟩ | `core/report/heartbeat_test.dart` :13-97 heartbeat 默认无 Timer / 周期上报 | — | 单测 全 | — |

#### E 事件（21 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| E1-① | 点播完整事件序列：Play → SourceChange → Ready → DurationChange → SizeChange → FirstFrame → … → Done（真实内核在 open() 内就先翻 playing，故 Play 排最前，且先于 Ready） | `core/first_frame_engine_test.dart` :48 restart 落地一次 MovaFirstFrame；`core/recovery/engine_recovery_test.dart` :236-254 Ready/SourceChange 顺序（恢复路径）；`core/first_frame_engine_test.dart` :34 E1 整段序列（Play、SourceChange、Ready、DurationChange、SizeChange、FirstFrame、Done 依序；用 openGate 复现“内核在 open() 内先翻 playing”） | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:190） | — （已补：P1-04） |
| E2-① | 各默认关闭功能的事件数为 0（开放性对账、`qoe:false` 零 QoE、cutover 关闭直通） | `core/openness_host_test.dart` :23 everything defaults to off, no timer no stream；`core/openness_keep_alive_test.dart` :18 zero-change anchor；`core/openness_report_test.dart` :119 qoe 默认 false 事件流与旧翻译器一致；`core/ads_test.dart` :70 disabled: no ad；`core/cutover/cutover_engine_test.dart` :32 disabled 直通；`core/report/collector_test.dart` :82 | — | 单测 全；历史真机 PASS（rerun.md:119） | — |
| E.MovaSourceChange-① | `MovaSourceChange`：`open` 发出（载荷 uri）；换档 `switchQuality` 不发 | `core/engine_test.dart` :35 open emits MovaSourceChange / :347 换档不发；`core/recovery/engine_recovery_test.dart` :254 | — | 单测 全；历史真机 PASS（rerun.md:84） | — |
| E.MovaSeek-① | `MovaSeek`：seek 请求发出（载荷 target），寄存路径也发 | `core/engine_verbs_test.dart` :223 MovaSeek → MovaSeeked 载荷为钳后值 / :233 / :255 寄存路径只发 MovaSeek（`core/report/translator_test.dart` 另有翻译断言） | — | 单测 全；历史真机 PASS（rerun.md:88） | — （已补：P0-04） |
| E.MovaVolumeChange-① | `MovaVolumeChange`：音量变化（钳制后的值） | `core/engine_test.dart` :1561,:1605,:1633 | — | 单测 全；历史真机 PASS（rerun.md:94） | — |
| E.MovaBrightChange-① | `MovaBrightChange`：亮度变化（钳制后的值） | `core/engine_test.dart` :1590,:1617 | — | 单测 全；历史真机 PASS（rerun.md:95） | — |
| E.MovaRateChange-① | `MovaRateChange`：倍速变化 | `core/engine_rate_test.dart` :34 单次事件 / :42,:49 钳后值 / :58 NaN→1.0 / :66 边界值 | — | 单测 全；历史真机 PASS（rerun.md:96） | — （已补：P0-02） |
| E.MovaQualityListChange-① | `MovaQualityListChange`：档位列表加载成功（过期响应被丢弃） | `core/recovery/review_regression_test.dart` :221-229 过期响应被丢弃；`core/engine_verbs_test.dart` :370 成功路径恰一个事件且载荷与 state.qualities 一致 | — | 单测 全；历史真机 PASS（rerun.md:97） | — （已补：P1-05） |
| E.MovaQualityChange-① | `MovaQualityChange`：档位变化（含「自动」） | `core/engine_test.dart` :319,:342 single.quality；`core/report/bitrate_test.dart` :19-98 | — | 单测 全；历史真机 FAIL（对账差异 1/10；rerun.md:209） | — |
| E.MovaFitChange-① | `MovaFitChange`：fit 变化；构造期种子不发 | `core/engine_test.dart` :50 仅断言构造期不发；`core/engine_verbs_test.dart` :323 正向发射恰一个 MovaFitChange | — | 单测 全；历史真机 PASS（rerun.md:100） | — （已补：P1-01） |
| E.MovaZoomChange-① | `MovaZoomChange`：缩放变化（钳制值） | `core/engine_verbs_test.dart` :330 事件载荷为钳后值 | — | 单测 全；历史真机 PASS（rerun.md:101） | — （已补：P1-01） |
| E.MovaLockChange-① | `MovaLockChange`：锁定变化 | `core/engine_verbs_test.dart` :200 每次调用一个 MovaLockChange | — | 单测 全；历史真机 PASS（rerun.md:102） | — （已补：P0-03） |
| E.MovaFullScreenChange-① | `MovaFullScreenChange`：全屏变化（含 false 载荷） | `core/engine_test.dart` :1819-1831 mini 与全屏的事件顺序(值=true)；`core/engine_verbs_test.dart` :338 setFullscreen(true) 再 (false)，含 false 载荷 | — | 单测 全；历史真机 PASS（rerun.md:103） | — （已补：P1-01） |
| E.MovaOrientationChange-① | `MovaOrientationChange`：强制方向变化 | `core/engine_test.dart` :827-849 | — | 单测 全；历史真机 PASS（rerun.md:104） | — |
| E.MovaMiniChange-① | `MovaMiniChange`：小窗变化 | `core/engine_test.dart` :1793-1831 | — | 单测 全；历史真机 PASS（rerun.md:106） | — |
| E.MovaTimeShiftChange-① | `MovaTimeShiftChange`：时移落后量变化（仅整秒变化才发） | `core/engine_test.dart` :1162 仅整秒变化才发 | — | 单测 全；历史真机 PASS（rerun.md:107） | — |
| E.MovaPreviewBlock-① | `MovaPreviewBlock`：预览被阻断（network 等原因） | `core/engine_test.dart` :884,:911；`core/preview/service_test.dart` :283-331 | — | 单测 全；历史真机 PASS（rerun.md:109） | — |
| E.MovaSttBlock-① | `MovaSttBlock`：STT 被阻断（disabled/noEngine/noSource） | `core/engine_test.dart` :949,:970,:992,:1012 | — | 单测 全；历史真机 PASS（rerun.md:110） | — |
| E.MovaCutoverChange-① | `MovaCutoverChange`（旧 MovaSwapChange）：cutover 阶段变化（载荷 phase） | `core/cutover/cutover_engine_test.dart` :159 disabled 不发 / :291 events 流依次带 warming、ready、回 idle / :307 与 cutoverPhases 一一对应 | — | 单测 全；历史真机 PASS（rerun.md:111） | — （已补：P1-06） |
| E.MovaFailover-① | `MovaFailover`：多地址切换（from/to/uri） | `core/recovery/failover_test.dart` :47,:124；`core/recovery/resume_readiness_test.dart` :74 | — | 单测 全；历史真机 PASS（rerun.md:115） | — |
| E.MovaKeepAliveChange-① | `MovaKeepAliveChange`（旧 MovaStandbyChange）：保活阶段变化（phase/reason/mode） | `core/keep_alive/engine_keep_alive_wake_test.dart` :16-17；`core/openness_keep_alive_test.dart` :49 | — | 单测 全；历史真机 PASS（rerun.md:116） | — |

#### U UI 组件（9 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| U1-① | `MovaPlayer`/`MovaView`/`MovaFeedPlayer`：挂载/卸载、`poster`/`posterUntilFirstFrame`、`surface`、`MovaView.autoPause` + `routeObservers`、null renderHandle 占位、`MovaSnapshotGuard` | `ui/player_test.dart` :23-221；`ui/view_test.dart` :56-145；`ui/feed_player_test.dart` :70-258；`ui/poster_test.dart` :56-151；`ui/player_fit_test.dart` :22-55；`ui/auto_pause_test.dart` :84-368 含 routeObservers/TickerMode；`ui/snapshot_guard_test.dart` :57-150 | — | 单测 全；历史真机 PASS（rerun.md:120） | — |
| U2-① | 皮肤/`MovaPatch`/`components()`：组件树合成、`applyPatches`、各皮肤名单（见 S1/S12） | `ui/skin_test.dart` :43-171；`ui/tree_test.dart` :49-93；`ui/bilibili_skin_test.dart` :12-28；`ui/douyin_skin_test.dart` :37,:71,:131；`ui/minimal_skin_test.dart` :22-99；`ui/mini/mini_skin_test.dart` :11-49；`ui/plugin_test.dart` :38,:62；`ui/component_tree_test.dart` :110 S1 componentName == 实例 name（:148 全部无参组件 name == componentName == 公布字符串 / :155 组件名唯一）/ :161 五套皮肤的组件树与槽位（:162 Default / :166 Bilibili = Default + speedButton + danmakuTrack / :177 Minimal / :187 Mini / :196 Douyin）/ :222 S12 四种补丁（见 S12-①） | — | 单测 全；历史真机 PASS（rerun.md:121） | — |
| U3-① | 顶栏 `TopBar`：标题、方向按钮（仅移动端）、PiP 按钮（不支持时隐藏）、fit 按钮；不含返回按钮，返回走系统 BACK；清晰度按钮选择与全屏按钮点击（缺） | `ui/top_bar_test.dart` :15 fit / :26,:33 pip / :42,:65 方向按钮 / :77 quality 隐藏 / :85 strings / :92,:113 title；`ui/top_bar_test.dart` :129 fullscreen button（:130,:142）/ :154 quality button（:159 档位标签 / :168 弹层 / :185 选择切档 / :199 自动档勾选） | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:191） | — （已补：P1-05, P1-10） |
| U4-① | 底栏 `BottomBar`：VOD/直播自适应（seekBar/timeshift/backToLive）、seek 松手提交、duration=0 禁用、position 标签节流、预览气泡 `PreviewComponent` | `ui/bottom_bar_test.dart` :11 seek bar 松手提交 / :21 duration=0 禁用 / :28 position label 节流；`ui/live_bar_test.dart` :31-94；`ui/preview_test.dart` :58-136 预览气泡 | — | 单测 全；历史真机 PASS（rerun.md:123） | — |
| U5-① | `CenterPlay`、`SpeedButton`（点击循环倍速，非菜单）、`HudLayer`（音量/亮度/seek）；`MovaZoomHudComponent` 与 HUD zoom/fit/quality 值（缺） | `ui/speed_button_test.dart` :9,:30；`ui/hud_test.dart` :11-71 音量/亮度/seek HUD；`ui/audio_only_interaction_test.dart` :54,:87 中心播放按钮；`ui/hud_test.dart` :81 zoom HUD 显示一位小数缩放与后缀 / :91 跟随替换后的 zoomSuffix / :101 其他 HUD 类型时不出现 / :116 fit、quality 等 HUD 现不渲染任何内容（记录现状） | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:192） | — （已补：P1-10） |
| U6-① | `GestureLayer`/`DouyinGestureLayer`：单击/双击 seek/竖滑/水平拖动、锁定态屏蔽；长按现无倍速；双指捏合与单击显隐控件（缺） | `ui/gesture_test.dart` :13-164；`ui/douyin_skin_test.dart` :71,:131；`ui/audio_only_interaction_test.dart` :191-243；`ui/gesture_test.dart` :192 pinch zoom / :264 single tap（单击显隐控件）；`ui/skin_test.dart` :248 锁定后手势不向 api 下发任何调用 | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:193） | — （已补：P1-09） |
| U7-① | `Danmaku`、`Subtitle`、`NextUp`（取消/立即播放，无数字倒计时）、`AdOverlay`（倒计时与跳过）、`FeedSocial`：渲染与点击 | `ui/danmaku_test.dart` :11-42；`ui/subtitle_test.dart` :12-95；`ui/next_up_test.dart` :50-86；`ui/ad_overlay_test.dart` :37-243；`ui/feed_social_test.dart` :13-98 | —；相关（非本档判据）：批次 gap-skin；coverage_gap_skin:S9.douyin.buttons（点赞/评论/分享/关注/头像回调） | 单测 全；历史真机 PASS（rerun.md:194） | — |
| U8-① | `MovaMiniWindow`：拖动、吸边、甩动不误关、转屏钳回（`remapProportionally`） | `ui/mini/mini_window_test.dart` :48-216；`core/mini/placement_test.dart` :9-196 | — | 单测 全；历史真机 PASS（rerun.md:127） | — |
| U9-① | `MovaAutoPause`：gate 纯逻辑、`TickerMode`、`routeObservers`、inactive 快照意图、PiP/小窗不暂停 | `ui/auto_pause_test.dart` :84-368；`core/guard/auto_pause_gate_test.dart` :23-205；`ui/review_regression_test.dart` :77-216 | — | 单测 全；历史真机 PASS（rerun.md:128） | — |

#### F 功能场景（14 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| F1-① | 点播完整生命周期（open → 播 → seek → 倍速 → 全屏 → 换源 → 播完 → dispose）：现为分散用例，缺单条串联 | `core/engine_test.dart` 分散的 open/seek/switch/dispose 用例；`core/audio_only_scenarios_test.dart` :47-426 无界面连播/换源 ⟨缺：无单条“open→播→seek→倍速→全屏→换源→播完→dispose”串联用例（倍速/全屏缺引擎侧断言）⟩ | — | 单测 部分；历史真机 PASS（rerun.md:129） | P2-12 |
| F2-① | 直播与时移：时移回退/回边缘、`timeshiftBehind` 随动、`durationStep` 节流 | `core/engine_test.dart` :1106-1428；`core/live/timeshift_test.dart` :13-62；`core/live/duration_throttle_test.dart` :35-89；`ui/live_bar_test.dart` :31-94 | — | 单测 全；历史真机 PASS（rerun.md:130） | — |
| F3-① | HLS 清晰度切换与 ABR：续播落点命中、ABR 限速降档、换档与 ABR 背靠背不丢 seek | `core/engine_test.dart` :178-448,:656,:701；`core/first_frame_engine_test.dart` :191-249；`core/model_test.dart` :24-58 | — | 单测 全；历史真机 FAIL（最近完整三组 retest5.md:209，1/280）；暂停态补跑 PASS 60/60（retest6.md:54-60）；判据口径 <200ms 与 ±500ms 待统一 | — |
| F4-① | 无缝引擎切换 + 广告编排：广告 → 正片 `renderEpoch` 递增、续播、失败降级、关闭态零事件 | `core/cutover/*` A24；`core/ads_test.dart` A27；`core/openness_cutover_test.dart` :13-100 | — | 单测 全；历史真机 PASS（rerun.md:132） | — |
| F5-① | 小窗 + PiP：小窗/PiP 互斥与唤醒保活（见 A15/A18） | `ui/mini/mini_mount_test.dart` :39 enterPip 使小窗下线；`core/keep_alive/engine_keep_alive_rules_test.dart` :131,:143；`core/engine_test.dart` :1468-1512,:1792-1872 | — | 单测 部分；历史真机 PASS（retest.md:135，仅专项子项） | — |
| F6-① | 低功耗待机：状态机迁移、位置、守卫降级进后台、封面瞬间盖上（见 A25） | `core/keep_alive/*` A25；`ui/auto_pause_test.dart` :288-368；`ui/poster_test.dart` :128-151 | — | 单测 全；历史真机 PASS（rerun.md:134） | — |
| F7-① | QoE 上报：TTFF、卡顿次数/时长、`ended`/`stopped`/`failed`/`abandoned` 四分、`truncatedBelow`、heartbeat、error 策略的纯逻辑 | `core/report/ttff_test.dart` :8-104；`core/report/stall_test.dart` :8-52；`core/report/session_test.dart` :7-166；`core/report/truncation_test.dart` :72-155；`core/report/stats_probe_test.dart` :15-162；`core/report/collector_test.dart` :42-170；`core/report/error_policy_test.dart` :8-50；`core/report/translator_test.dart` :14-124；`core/report/bitrate_test.dart` :19-98；`core/report/heartbeat_test.dart` :13-97 | — | 单测 全；历史真机 PASS（rerun.md:135） | — |
| F8-① | 超时与恢复：重试/切换/看门狗/直播持续重连/续播就绪/按源选项 | `core/recovery/engine_recovery_test.dart` :78-374；`core/recovery/failover_test.dart` :47-128；`core/recovery/resume_readiness_test.dart` :74-198 HE V6；`core/recovery/watchdog_test.dart` :19-113；`core/recovery/policy_test.dart` :16-52；`core/recovery/live_reconnect_test.dart` :23-171；`core/recovery/recovery_fixes_test.dart` :51-149；`core/recovery/review_regression_test.dart` :69-221 | — | 单测 全；历史真机 PASS（rerun.md:196） | — |
| F9-① | 仅音频 `audioOnly`：无渲染面、size 0x0、连播/换源、交互 | `core/audio_only_test.dart` :14-83；`core/audio_only_scenarios_test.dart` :47-426；`core/openness_audio_test.dart` :39-73；`ui/audio_only_interaction_test.dart` :54-272；`core/engine_test.dart` :1745,:1776 | — | 单测 全；历史真机 PASS（rerun.md:137） | — |
| F10-① | 预览缩略图：VTT 与抽帧两路、缓存命中、网络策略（见 A30） | `core/preview/*` A30；`ui/preview_test.dart` :58-136 | — | 单测 全；历史真机 PASS（rerun.md:138） | — |
| F13-① | 多引擎并存与资源：feed 引擎池滑动 100 次的池不变量（可用 FakeKernel 压） | `core/engine_pool_test.dart` :49-231；`core/feed_test.dart` :104-189；`core/kernel/mpv_event_pump_test.dart` :326 I9 多引擎并存；`core/cutover/cutover_engine_test.dart` :167-532 ⟨缺：滑动 100 次的池不变量（可用 FakeKernel 压）；dispose 期间帧间隔属真机⟩ | — | 单测 部分；历史真机 PASS（rerun.md:141） | P2-11 |
| F14-① | 原生事件泵（FFI 弱客户端）：I0–I11 不变量、`movaObserveFlags`、`qoe:false` 建客户端数 0 | `core/kernel/mpv_event_pump_test.dart` 24 项 I0–I11；`core/kernel/mpv_kernel_events_test.dart` :111-318；`platform_impl/mpv_event_backend_ffi_test.dart` :7,:40,:66；`platform_impl/wiring_test.dart` :213,:220 movaObserveFlags；`support/fake_mpv_event_backend.dart` 夹具 | — | 单测 部分；历史真机 PASS（rerun.md:142） | — |
| F15-① | WHEP 纯逻辑：dtls 白名单、benign 错误过滤、超时换算 | `core/kernel/mpv_defaults_test.dart` :36-65 dtls 白名单/benign 错误；`core/recovery/timeouts_test.dart` :17,:52 WHEP 超时换算；`core/source_options_test.dart` :26,:33；`core/kernel/mpv_kernel_live_cache_test.dart` :152-220 whep 后向缓冲限制 | — | 单测 部分；历史真机 BLOCKED（rerun.md:197）：WHEP端点38889/test/whep拒连，相关端口探测不可用；缺publisher/信令/UDP38189及relay38190服务 | — |
| F16-① | 已知遗留缺陷的现行回归：PiP 退出复位、`MovaWarmPlan.rate`、pod 第二条广告真换指 | `core/engine_test.dart` :1478 PiP 退出复位（已修）；`core/cutover/cutover_engine_defects_test.dart` :269 WarmPlan.rate；`core/ads_test.dart` :631-664 pod 第二条广告换指/ad rate | — | 单测 部分；历史真机 PASS（rerun.md:144） | — |

#### N 新增 API（24 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| N1-① | `MovaTimeouts`/`kMovaWatchdogMargin`：派生与下发到 mpv（`network-timeout` 整秒、WHEP 项微秒）、默认全 null 不动 mpv、源级显式优先 | `core/recovery/timeouts_test.dart` :10-59；`core/engine_source_options_test.dart` :48；`core/source_options_test.dart` :26-47；`core/recovery/config_test.dart` :9-47 | — | 单测 全；历史真机 PASS（rerun.md:145） | — |
| N2-① | `startTimeout`/`stallTimeout`/`stallWatchdog`/`copyWith(clearStallTimeout)`：派生（非 WHEP 65s/WHEP 85s/卡顿 10s）、显式优先、看门狗关闭 | `core/recovery/config_test.dart` :9-103；`core/recovery/watchdog_test.dart` :19-113；`core/recovery/engine_recovery_test.dart` :112,:191 | — | 单测 全；历史真机 PASS（rerun.md:146） | — |
| N3-① | `MovaLiveReconnect`/`MovaDefaultRecovery`/`liveReconnect`：退避 1,2,4,8,15,15…、`maxAttempts`/`retriesPerAddress`、`liveReconnect:false` 回旧行为、点播默认不变 | `core/recovery/live_reconnect_test.dart` :22-171 | — | 单测 全；历史真机 PASS（rerun.md:147） | — |
| N4-① | `MovaSource.mpvOptions`/`demuxerOptions`/`mpvOptionsFor`：open 前下发、下一源还原不泄漏、非法项整项跳过且不进 `state.error`、解析器 `parseMpvKeyValueList`/`lookupMpvKeyValue` | `core/source_options_test.dart` :8-67；`core/engine_source_options_test.dart` :32-122；`core/kernel/mpv_kernel_source_options_test.dart` :129-233；`core/kernel/mpv_keyvalue_test.dart` :9-51 解析/lookup | — | 单测 全；历史真机 PASS（rerun.md:148） | — |
| N5-① | recovery 自动订阅 END_FILE、`observeRestarts`、`movaObserveFlags(recovery:)`：只要 END_FILE、不转发 RESTART | `core/recovery/engine_recovery_test.dart` :298；`core/recovery/recovery_fixes_test.dart` :109-149；`platform_impl/wiring_test.dart` :213,:220；`core/kernel/mpv_kernel_events_test.dart` :168,:195 | — | 单测 全；历史真机 PASS（rerun.md:149） | — |
| N6-① | 恢复后清错误、放弃后清 buffering 并补发 `MovaBufferChange(false)`、加载在途收到的 END_FILE 在 open 返回后处理 | `core/recovery/recovery_fixes_test.dart` :51-149 | — | 单测 全；历史真机 PASS（rerun.md:150） | — |
| N7-① | `MovaLiveConfig.durationStep`：直播 `MovaDurationChange` 节流、0 关闭、首个非零/回落 0/重新 open 放行、点播不变 | `core/live/duration_throttle_test.dart` :35-89 | — | 单测 全；历史真机 PASS（rerun.md:151） | — |
| N8-① | `open()` 返回 `Future<bool>`：true=接受；`beforeOpen` 拒绝/被取代/已销毁为 false；失败不算 false；`jumpTo` 被拒不前进 | `core/engine_test.dart` :538；`core/playlist_test.dart` :92 jumpTo 被拒不前进下标；`core/engine_dispose_race_test.dart` :77；`core/recovery/review_regression_test.dart` :187 | — | 单测 全；历史真机 PASS（rerun.md:152） | — |
| N9-① | `MovaPipObservable.changes`：PiP 展开/点 X 关闭后 `state.pip` 复位并发 `MovaPipChange`、重复值不重发、dispose 取消订阅 | `core/engine_test.dart` :1478 state.pip follows PiP changes + 重复值 + dispose 取消订阅（含“点 X”注入路径）；`method_channel_test.dart` :53 PiP over the channel（:80 pipChanged 推送按序变成 bool / :91 非 bool 参数被忽略 / :103 其他方法名被忽略 / :113 多个监听者收到同一推送 / :127 isPipSupported 返回原生答复 / :134 null、PlatformException、MissingPluginException 降级 false / :143 enterPip 带 width/height / :154 无比例发显式 null / :164 enterPip 异常降级 false） | — | 单测 全；历史真机 PASS（rerun.md:153） | — （已补：P0-06） |
| N10-① | `MovaWarmPlan.rate`/`cutoverTo(rate:)`/`MovaHandoffRetirable`：广告 1x、回正片恢复倍速、换指后无短暂跑用户倍速窗口、退役引擎 dispose 不复位全局方向、pod 第二条广告真换指 | `core/cutover/plan_test.dart` :8-32；`core/cutover/cutover_engine_defects_test.dart` :269,:336,:348,:357,:386；`core/ads_test.dart` :631,:664；`core/ad_first_frame_test.dart` :137-191 | — | 单测 全；历史真机 PASS（rerun.md:154） | — |
| N11-① | `MovaPlayerMute` 能力：预热/待机静音只改 mpv `mute`、不写系统音量、两方叠加任意退出顺序还原 | `core/cutover/cutover_warm_mute_test.dart` :31,:86,:117,:168；`core/kernel/mpv_kernel_keep_alive_test.dart` :75-155；`core/cutover/cutover_engine_test.dart` :210 | — | 单测 全；历史真机 PASS（rerun.md:155） | — |
| N12-① | `MovaState.rendered`、`MovaFirstFrame(sinceOpen, signal)`、`MovaFirstFrameGate`：每次 open 重置并重发、内部重载不重置、open 后宽高异步归零 | `core/first_frame_engine_test.dart` :34-262；`core/render/first_frame_test.dart` :8-135；`core/state_test.dart` :37 | — | 单测 全；历史真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:198） | — |
| N13-① | `createMovaEngine(preciseFirstFrame:)`、`MovaMpvKernel(observeNativeEvents:/observeRestarts:/lazyVideo:)`：开关对应的弱客户端数、懒创建 VideoController | `platform_impl/wiring_test.dart` :213,:220；`core/kernel/mpv_kernel_events_test.dart` :111-261；`core/kernel/mpv_kernel_video_test.dart` :92-187 | — | 单测 全；历史真机 PASS（rerun.md:157） | — |
| N14-① | `fit` 初值参数、`MovaPlayer(fit:)`：挂载应用一次，用户按钮改的值不被重建覆盖 | `ui/player_fit_test.dart` :22-55；`core/engine_test.dart` :50；`platform_impl/wiring_test.dart` :235 | — | 单测 全；历史真机 PASS（rerun.md:158） | — |
| N15-① | `MovaPlayer(poster:, posterFade:)`、`MovaFeedPlayer(posterUntilFirstFrame:)`：首帧后淡出、换源重盖、仅音频常驻 | `ui/poster_test.dart` :56-151；`ui/feed_player_test.dart` :193-236 | — | 单测 全；历史真机 PASS（rerun.md:159） | — |
| N16-① | `MovaMinimalSkin`、`MovaTheme.bufferingSize/StrokeWidth/Color`：无手势层无栏、转圈/错误层可选、默认外观不变 | `ui/minimal_skin_test.dart` :22-99 | —；相关（非本档判据）：批次 gap-skin；coverage_gap_skin:S1.minimal.variants、S13.minimal.inject | 单测 全；历史真机 PASS（rerun.md:160） | — |
| N17-① | `MovaView`、`MovaSource.sameAs`：自建/复用/`options` 变化重建/销毁、source 为 null 暂停、`onOpenError`、`alternatives` 参与 sameAs | `ui/view_test.dart` :56-145；`core/model_test.dart` :227-273 | — | 单测 全；历史真机 PASS（rerun.md:161） | — |
| N18-① | `MovaAutoPause`/`MovaAutoPauseGate`/`MovaAutoPauseConfig`、`MovaHideReason`/`MovaLiveResume`/`MovaGuardAction`：滚出视口、`TickerMode`、路由覆盖、进后台、inactive 快照意图、PiP/小窗不暂停、直播隐藏 ≥3s 回边缘 | `core/guard/auto_pause_gate_test.dart` :23-205；`ui/auto_pause_test.dart` :84-368；`ui/review_regression_test.dart` :77-216 | — | 单测 全；历史真机 BLOCKED（rerun.md:162）：已测HE前后台/route/Ticker/PiP各3轮，inactive意图及直播隐藏>=3s回边缘LiveEdgeReach、真实Feed滚动和View RouteObserve | — |
| N19-① | `MovaFailover`/`MovaPlayFailure`/`MovaRecovered`/`MovaRecoveryPolicy`/`MovaFailoverOnly`/`MovaRetryThenFailover`：重试/切换事件序列、备选只在 recovery 开启时使用 | `core/recovery/failover_test.dart` :47-128；`core/recovery/policy_test.dart` :16-52；`core/recovery/engine_recovery_test.dart` :112-354 | — | 单测 全；历史真机 PASS（rerun.md:199） | — |
| N20-① | standby → keepAlive 家族：`MovaHiddenMode.keepAlive`、`MovaKeepAlive`、`MovaKeepAliveConfig`、`MovaKeepAliveKernel`、`MovaState.keepAlivePhase`（见 A25/F6） | `core/keep_alive/*` A25；`core/guard/auto_pause_gate_test.dart` :135-205 | — | 单测 全；历史真机 PASS（rerun.md:164） | — |
| N21-① | `MovaSnapshotGuard`（仅 Windows）、`testing.dart` 的 `stagedSourceOptions`：其他平台行为不变 | `ui/snapshot_guard_test.dart` :57-150 含“其他平台行为不变”；`testing/testing_test.dart` :127 7b | — | 单测 全；历史真机 PASS（rerun.md:165） | — |
| N22-① | 0.3.1 小修：异步 `beforePlay/beforeSeek` 返回后复查、手势改配轴向、`trackCount>0`/`maxZoom>=1` assert、STT `start()` 失败回滚可重试、预览带 crop 不入缓存与换源丢弃旧结果 | `core/engine_test.dart` :504,:518 异步 beforePlay/Seek 复查；`ui/gesture_test.dart` :75,:88 改配轴向；`core/options_test.dart` :18,:23 trackCount/maxZoom assert；`core/stt_test.dart` :55 start 失败回滚；`core/preview/service_test.dart` :425,:435,:449 crop 不入缓存/换源丢弃旧结果 | — | 单测 全；历史真机 PASS（rerun.md:200） | — |
| N23-① | 统一上报 QoE 新增：`MovaStatsProbe.nativeRestartAvailable`、`truncatedBelow`、`MovaReportName.custom` | `core/report/stats_probe_test.dart` :115-162；`core/report/truncation_test.dart` :71-155；`core/report/name_test.dart` :6-37 | — | 单测 全；历史真机 PASS（rerun.md:167） | — |
| N24-① | 开放性对账：各功能默认关闭 + 配置项可注入 + 无副作用（`openness_*_test.dart` 共 9 个文件，按 C 项挂靠） ⟨新增：旧矩阵没有这一类要求（unit-trace §2.1）⟩ | `core/openness_{ad,audio,cutover,host,keep_alive,live,mini,preview,report}_test.dart` 共 9 个 | — | 单测 全 | — |

#### S 皮肤专项（4 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| S1-① | 组件树：`components()` 名单与 `MovaSlot` 分布；`componentName` 常量与 `name` getter 一致（逐个读取） | `ui/component_tree_test.dart` :110 S1 componentName 一致性 + :161 五套皮肤组件树与槽位（Default/Bilibili/Minimal/Mini/Douyin 逐项对账） | — | 单测 全 | — （已补：P1-11 的 S1 部分） |
| S12-① | `MovaPatch` 四种补丁：对 DefaultSkin/BilibiliSkin（唯一经 `applyPatches` 的皮肤）做 Add/Replace/Remove/InsertAfter；其余三套皮肤 `components()` 不经 `applyPatches` | `ui/component_tree_test.dart` :222 S12（:233 remove 删节点及子树 / :241 replace 原位替换 / :252 insertAfter 紧跟锚点 / :259 add 把新顶层节点放进指定槽 / :266 补丁按序叠加 / :281 Bilibili 在内置补丁上叠加用户补丁）；`ui/tree_test.dart` :49-93 applyPatches 合成树 | — | 单测 全 | — （已补：P1-11 的 S12 部分） |
| S13-① | 主题与文案：`MovaTheme` 颜色/尺寸字段在各皮肤落地；默认外观不变的快照式断言 | `core/options_test.dart` :41,:49；`ui/top_bar_test.dart` :85；`ui/live_bar_test.dart` :84；`ui/minimal_skin_test.dart` :53,:72,:86 ⟨缺：MovaTheme 颜色/尺寸字段在各皮肤落地；默认外观不变的快照式断言⟩ | — | 单测 部分 | — |
| S14-① | 皮肤切换：运行中换 skin（同一 api 不重开、kernel.calls 不增、事件不重复） | `ui/player_test.dart` :242 S14 换皮肤（:243 同一 api 不被碰：无 open/play/seek/reload，也无任何新调用 / :257 渲染面不变：同 handle key、不重挂 / :268 外壳确实换了：Default 有全屏钮、Minimal 没有 / :282 api 事件流保持安静、不重复） | — | 单测 全 | — （已补：P1-11 的 S14 部分） |

#### P 公开类型家族（20 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| P1-① | 引擎与状态：`MovaApi`/`MovaEngine`/`MovaCutoverEngine` 成员、`MovaState` 字段、`MovaProg`/`MovaSelect`/`MovaUiSelect`/`MovaUiState`、枚举取值（`MovaStreamType`/`MovaPlatformKind`/`MovaFirstFrameSignal`/`MovaEndFileReason`） | `core/state_test.dart` :9-115；`core/bus_test.dart` :7-59；`ui/selector_test.dart` :10 MovaSelect；`core/kernel/mpv_kernel_events_test.dart` :318 MovaEndFileReason 映射；`core/preview/extractor_test.dart` :112 MovaPlatformKind ⟨缺：`MovaUiSelect`/`MovaProgSelect` 零引用（selector.dart:51,92）；MovaApi/MovaEngine 成员级缺口见 A6/A10/A11/A13/A19/A21⟩ | — | 单测 部分 | P2-02, P2-07 |
| P2-① | 事件：每个事件类的引擎侧断言（35 类里 25 类有、10 类无，见 E 组）；`MovaLogLine`、`MovaStatsSnapshot` | `core/report/translator_test.dart` :14-124；`core/report/stats_probe_test.dart` :15-162 MovaStatsSnapshot ⟨缺：35 个事件类里 25 个有引擎侧断言，10 个无（见 E 节）⟩ | — | 单测 部分 | — |
| P3-① | 配置：`MovaOpts` 每个字段与子配置对象每个字段的默认值读回 + 改值后行为变化（或「仅构造期」） | `core/options_test.dart` :17-394；`core/recovery/config_test.dart` :9-103；`core/report/config_test.dart` :8-88；`core/keep_alive/config_test.dart` :6-45；`core/stt_test.dart` :67-100 ⟨缺：MovaAbrConfig/MovaCtrlsConfig/MovaGestureConfig/MovaPlaylistConfig/MovaStrs/MovaTheme 默认值与 copyWith/==（见第 3 节 P2 项）⟩ | — | 单测 部分 | P2-01 |
| P4-① | 广告：`MovaAds`/`MovaAdBreak`/`MovaAdBreakKind`/`MovaAdEvent`/`MovaAdFail*`/`MovaAdRetrySkip`/`MovaAdAbandonPod`/`MovaAdOverlayComponent`；等待策略 pre/mid/post | `core/ads_test.dart` 98 项；`core/ad/fail_test.dart` :21-63；`ui/ad_overlay_test.dart` :37-243；`core/model_test.dart` :111-211 MovaAdBreak；`core/openness_ad_test.dart` :38-211 | — | 单测 全 | — |
| P5-① | 无缝切换：`MovaCutover`/`MovaCutoverChange`/`MovaCutoverPhase`/`MovaWarmTrigger`（`MovaLeadWarm`/`MovaEagerWarm`）/`MovaWarmPolicy`/`MovaBufferWarm`/`MovaWarmCue`/`MovaWarmSignal`/`MovaWarmVerdict`；关闭态直通（真实预热见 A24） | `core/cutover/*` A24；`core/options_test.dart` :203-253 | — | 单测 全 | — |
| P6-① | 保活：`MovaKeepAlive`/`MovaKeepAliveMode/Phase/Reason/Change/Resume`/`MovaSilentKeepAlive`；`setKeepAlive` 与 `MovaHiddenMode.keepAlive` 两个入口（真实属性见 A25） | `core/keep_alive/*` A25；`core/guard/auto_pause_gate_test.dart` :135-205 | — | 单测 全 | — |
| P7-① | 恢复：`MovaRecovery*`/`MovaPlayFail*`/`MovaRetry*`/`MovaGiveUpError`/`MovaPrefixError`/`MovaErrorPolicy/Verdict`/`MovaStallPolicy`/`MovaEdgeStall`/`MovaStall` | `core/recovery/*` F8；`core/report/error_policy_test.dart` :8-50 MovaPrefixError；`core/report/stall_test.dart` :8-52 MovaEdgeStall | — | 单测 全 | — |
| P8-① | 上报：`MovaReporter`/`MovaCallbackReporter`/`MovaReportEvent/Kind/Priority`/`MovaSessionEnd`/`MovaSessionTally`/`MovaSessionIdFactory`；`qoe` 开关与自定义名 | `core/report/*` F7；`core/report/session_id_test.dart` :5-15；`core/report/report_engine_test.dart` :10-71 | — | 单测 全 | — |
| P9-① | 预览缩略图：`MovaPreviewService`、三类缩略图源、三类缓存、`MovaThumbCrop/Cue/Index`、`MovaNetProbe`、`MovaVttUrlSolver`、`MovaCacheKeyBuilder`；三个 Temp 目录提供者与 `MovaIoHttpFetcher` 零引用 | `core/preview/*` A30；`platform_impl/net_probe_impl_test.dart` :6-23 ⟨缺：MovaIoHttpFetcher（fetcher.dart:42）、MovaTempThumbDirProvider（thumb_dir_impl.dart:18）零引用；MovaFrameExtractor 只能真机（依赖 libmpv）⟩ | — | 单测 部分 | P2-04 |
| P10-① | STT：`MovaSttService`、`MovaSttEngine`/`MovaNoopSttEngine`、三种字幕仓库、模型加载/提供者/目录提供者、`MovaSttCue`；`MovaAudioExtractor`/`MovaSttModelFiles` 零引用 | `core/stt_test.dart` :25-100；`core/stt_subtitle_store_test.dart` :19-76；`core/stt_chunk_subtitle_store_test.dart` :19-81；`core/stt_model_provider_test.dart` :53-148 ⟨缺：MovaTempSttModelDirProvider/MovaTempSttSubtitleDirProvider（platform_impl/stt_*_dir_impl.dart:28）、MovaAudioExtractor/MovaAudioPuller（audio_extractor.dart:26）、MovaSttModelFile.sha256（model_spec.dart:33，lib 内从未校验）⟩ | — | 单测 部分 | P1-13, P2-04, P2-14 |
| P11-① | Feed 与 Playlist：`MovaFeedEnginePool`/`MovaFeedItem/Slot/Loader/HolderBuilder`/`MovaFeedLikeChange`/`MovaNetworkWarmFeedPrefetcher`、`MovaPlaylist*`、`MovaPlaylistItem` | `core/feed_test.dart` :46-295；`core/engine_pool_test.dart` :33-231；`core/feed_prefetcher_test.dart` :7-31；`core/playlist_test.dart` :44-170 | — | 单测 全 | P2-07 |
| P13-① | 拦截与守卫：`MovaHook`/`MovaHookChain` 各钩子点、`MovaAutoPause*`、路由观察器、`TickerMode` 路径 | `core/interceptor_test.dart` :50-67；`core/guard/auto_pause_gate_test.dart` :23-205；`ui/auto_pause_test.dart` :84-368；`core/interceptor_test.dart` :154 beforePlay 链 / :177 onError 链 / :196 engine → hooks.onError / :236 before* 钩子抛异常（同 A32-①） | — | 单测 全 | — （已补：P1-02） |
| P14-① | 小窗：`MovaMini*`（`Rect`/`Insets`/`Placement`/`Mount`/`Host`）、`MovaCornerSnap`（见 S16） | `core/mini/placement_test.dart` :9-196；`ui/mini/*` S16 | — | 单测 全 | P2-07 |
| P15-① | UI 组件逐个：每个 `*Component`（含 `MovaIconButton`/`MovaGradBar`/`MovaSheetItem`/`MovaSlotBundle`/`MovaPlugin`/`MovaScope`/`MovaSelect`）的 `componentName` 与 WidgetTester 渲染/交互；约 25 个无直接类型引用 | `ui/*` 各组件 widget 测试，见第 4 节组件表；`ui/component_tree_test.dart` :148 全部无参组件 componentName 逐个读取、:155 唯一；`ui/top_bar_test.dart` :129,:154（全屏/清晰度弹层，含 `MovaSheetItem` 渲染与勾选）；`ui/hud_test.dart` :81（`MovaZoomHudComponent`） ⟨缺：仍有部分 `*Component` 在 test/ 中无直接类型引用（多数经父组件间接覆盖）；`MovaProgSelect`/`MovaUiSelect` 无覆盖（P2-07）⟩ | — | 单测 部分 | P2-07；已补：P1-11 |
| P16-① | `MovaHud` 各类型（音量/亮度/Seek/缩放/fit/quality）的渲染 | `ui/hud_test.dart` :11-71；`ui/hud_test.dart` :81,:91,:101（zoom）/ :116（fit、quality 现不渲染） | — | 单测 全 | — （已补：P1-10） |
| P17-① | `@Deprecated` 旧名兼容：typedef 只覆盖类型位置与构造器；`MovaState.standby`/`MovaOpts.standby`/`swap` 旧 getter 保留；**`setStandby`/`swapTo`/`MovaOpts(swap:/standby:)` 无别名**，旧枚举静态成员不可经别名访问；17 个别名只 4 个被测 | `deprecated_names_test.dart` :7 别名同类型(4 个) / :19 旧成员转发(4 个) ⟨缺：17 个 `@Deprecated` typedef 仅 4 个被引用（MovaCutoverConfig/MovaKeepAliveConfig/MovaKeepAlivePhase/MovaKeepAliveMode）；其余 13 个零引用（deprecated_names.dart:22-86）⟩ | — | 单测 部分 | P2-03 |
| P18-① | 测试替身：`MovaTestKernel`/`MovaTesting` 安装后 `createMovaEngine()` 行为、与真内核互不污染；`emit*`/`exitKeepAlive`/`lastSeek`/`lastPlay` 零引用 | `testing/testing_test.dart` :40-178 ⟨缺：MovaTestKernel 的 emitCompleted/Position/Duration/Buffer/Error/EndFile/Stalling、exitKeepAlive、lastSeek/lastPlay 在 testing_test 中零引用（test_kernel.dart:244-290）⟩ | — | 单测 部分 | P2-06 |
| P19-① | 顶层函数：`createMovaEngine`（`audioOnly`/`preciseFirstFrame`/`pollInDebug`/tls/recovery 透传）、`movaObserveFlags`、`movaProtocolWhitelist`（含 dtls；未从主 barrel 导出） | `platform_impl/wiring_test.dart` :101-241 createMovaEngine/movaObserveFlags；`core/kernel/mpv_defaults_test.dart` :36-65 movaProtocolWhitelist ⟨缺：createMovaEngine 的 tlsVerify/tlsCaFile/pollInDebug/recovery 参数透传无断言（wiring.dart:164-165,216-217）⟩ | — | 单测 部分 | P1-14 |
| P20-① | 29 个顶层纯函数/常量的直接断言：`dueMidRoll`/`movaFeedWindow`/`resolveWindow`/`behindOf`/`atLiveEdge`/`clampToBounds`/`remapProportionally`/`rectForCorner`/`parseHlsMasterPlaylist`/`fnv1a64`/`defaultCacheKey`/`previewAllowedOn`/`parseVttThumbs`/`defaultVttUrl`/`resolveSessionEnd(Native)`/`newMovaSessionId`/`parseSrt`/`formatSrt`/`movaBoxFit`/`formatDuration`/`applyPatches`/`buildSlots`/`preferredOrientationsFor`/`resolveOrientations`（仅 `showMovaOptionSheet` 零引用） ⟨新增：旧矩阵与台账只列类型不列函数（device-trace §3、unit-trace §4.5）⟩ | 28/29 个顶层函数有测试引用（见 unit-trace §4.5 清单）；`showMovaOptionSheet` 零引用 | — | 单测 部分 | — |
| P21-① | 公开成员级覆盖：811 个公开成员名在矩阵与台账零出现（device-trace §3），其中零测试引用的真成员见 §5.1（如 `MovaEngine.setRate/setLocked/reload/showControls`、`MovaHook.onError`、`MovaErrorEvent.stack`、`MovaPlaylist.currentItem`、`MovaAds.adPosition` 等） ⟨新增：「285 个类型」不等于成员级验收（device-trace §4）⟩ | 缺：811 个成员名矩阵零出现，零测试引用的真成员见 §5.1.3 | — | 单测 无 | — |

#### G 覆盖缺口（13 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 最近结论 | 缺口 |
|---|---|---|---|---|---|
| G2.1-① | 音频焦点：外部暂停（kernel playing=false）不清 `playbackIntent` 的引擎断言（inactive 时系统暂停不丢恢复意图已有） | `ui/auto_pause_test.dart` :207 inactive 时系统暂停不丢恢复意图；`core/guard/auto_pause_gate_test.dart` :83；`core/engine_verbs_test.dart` :187 内核侧暂停（如音频焦点丢失）不清 playbackIntent | — | 单测 全 | — （已补：P2-09） |
| G2.2-① | 播放中网络变化的恢复逻辑（recovery/live reconnect/`net_probe` 的纯逻辑） | `core/recovery/engine_recovery_test.dart` :112-:354；`core/recovery/live_reconnect_test.dart` :121；`platform_impl/net_probe_impl_test.dart` :6-23 | — | 单测 部分 | — |
| G2.3-① | 息屏/锁屏的守卫逻辑（inactive/hidden 序列、`AutoPauseGate`） | `ui/auto_pause_test.dart` :197,:208,:314；`core/guard/auto_pause_gate_test.dart` :83-100 | — | 单测 部分 | — |
| G2.8-① | WidgetTester 可测的 RTL/`textScaleFactor`/Semantics（全库无专项用例） | 缺：WidgetTester 可测 RTL/textScaleFactor/Semantics；全库无专项用例（`Directionality` 只是 snapshot_guard_test 的测试外壳） | — | 单测 无 | P2-08 |
| G2.9-① | 磁盘/目录不可写时预览磁盘缓存与 STT 模型目录的降级：save 失败不抛（load 降级已测） | `core/preview/disk_cache_test.dart` :115 unusable directory degrades；`core/stt_subtitle_store_test.dart` :76 load degrades to null ⟨缺：save 失败路径（写失败不抛）⟩ | — | 单测 部分 | P2-10 |
| G3.3-① | 协议白名单（含 dtls）、按格式限制缓冲、HLS master 解析 | `core/kernel/mpv_defaults_test.dart` :36-47 白名单；`core/kernel/mpv_kernel_live_cache_test.dart` :140-335 按格式限制缓冲；`core/model_test.dart` :24-40 HLS master 解析 | — | 单测 部分 | — |
| G3.4-① | 服务端异常的纯逻辑：prefetcher 吞连接失败、VTT 缺失降级 | `core/feed_prefetcher_test.dart` :31 swallows connection failures；`core/preview/vtt_source_test.dart` :109 缺失 vtt | — | 单测 部分 | — |
| G3.5-① | 点播↔直播同引擎互换：live → VOD → live 的 type/liveSeekable/seekableWindow/timeshiftBehind 整体复位（缺） | `core/engine_test.dart` :156,:473 换源清时长/位置；`core/live/duration_throttle_test.dart` :89；`core/audio_only_scenarios_test.dart` :204,:224；`core/engine_verbs_test.dart` :527 G3.5（:528 直播(可 seek、有时移)→点播清掉全部直播专属字段 / :552 点播→直播以空时长基线起步） | — | 单测 全 | — （已补：P1-15） |
| G3.6-① | 时长 0/未知/突变的寄存与完播判定；时长未到寄存 seek | `core/engine_test.dart` :124,:144 时长未到寄存 seek；`core/report/truncation_test.dart` :126 unknown duration→ended；`core/live/timeshift_test.dart` :33；`core/live/duration_throttle_test.dart` :65 | — | 单测 部分 | — |
| G4.1-① | 随机序列/压力：固定种子随机动作序列（含连点 100 次）+ 不变量断言（FakeKernel）——全库无 fuzz | `core/engine_fuzz_test.dart` :340 固定种子 + FakeKernel：不变量成立、无未捕获异常、dispose 为终态（:342）/ :354 连点 100 次 seek、换源、全屏后仍一致 | — | 单测 全 | — （已补：P0-07） |
| G4.3-① | 运行中热切换：`MovaView` 换 skin/strings/theme 不重建引擎（options 变化重建已测） | `ui/view_test.dart` :101 changed options dispose old engine and reopen ⟨缺：MovaView 换 skin/strings/theme 不重建引擎⟩ | — | 单测 部分 | — |
| G4.4-① | 多实例/组合：feed 池 + 小窗 + cutover 叠加（单项已有） | `core/engine_pool_test.dart` :49-231；`core/feed_test.dart` :104-189；`core/kernel/mpv_event_pump_test.dart` :326 ⟨缺：feed+小窗+cutover 叠加⟩ | — | 单测 部分 | P2-11 |
| G4.5-① | 上报回调抛异常时不拖垮播放（已隔离：异常只交给钩子 `onError`，见 §6 第 2 项）；事件洪泛背压未测 | `core/report/report_engine_test.dart` :81 宿主上报回调抛异常（:82 collector 路径播放不断、后续上报照到、钩子被通知 / :110 report() 路径不抛也不挡下一条 / :129 永远抛的 reporter 不死循环、不拖垮播放）；§6 已决定：隔离，只通知 `MovaHook.onError`，不发 `MovaErrorEvent`、不写 `state.error` | — | 单测 全 | — （已补：P1-03；事件洪泛背压未测） |

### 3.2 ② 单测 + 真机核对

逻辑能单测，但输入/时机来自 mpv 或系统。**单测穷举分支、真机跑代表路径核对假设**。每行「依赖假设」指向 §4 的 H 条目；假设被证伪（如 H18/H19/H26/H42）意味着单测全绿也要回头看假内核是否贴近真实。

#### A 公开 API（20 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| A2-② | 真实内核下事件载荷与「接收这一刻的 state」的差异：size 宽高半更新、duration 微调、cutover 代理分两条订阅转发；事件异步交付，不判 FAIL | 同 A2-① | 批次 api；main_coverage_api:observe | H11, H12, H77 | 真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:174）；单测 部分 | — |
| A4-② | Android 真实 Activity 下为 true，与 `state.pipSupported` 一致 | 同 A4-① | 批次 api；main_coverage_api:basic{A4} | H55 | 真机 PASS（rerun.md:36）；单测 全 | — |
| A5-② | 真实内核 open：内核先发的归零事件序列、坏地址 open 是否抛与 END_FILE 秒判时机；open 后宽高/duration 在 `beforeOpen` 之后、内核加载前异步归零，不要求同步可读 | 同 A5-① | 批次 api,extras,native-inputs；main_coverage_api:basic{A5.paused}；批次 gap-assumptions；coverage_gap:H7.lateError、coverage_gap:H33.*（H33 为记录型） | H1, H8, H33 | 真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:175）；单测 全 | — |
| A6-② | 真实内核：play/pause 同步发 playing 事件、pause 不引发 buffering、命令按序串行、播完后 `play()` 先 seek(0) 再 play | 同 A6-① | 批次 api；main_coverage_api:basic{A6.pause} | H13, H14, H23, H25 | 真机 PASS（rerun.md:38）；单测 全 | — |
| A7-② | 真实 mpv：落点误差（超 500ms 回声被永久抑制）、seek 回声/被丢弃、duration 到即接受（已证伪）、HLS 首次 open 后寄存 seek、加载中直发会卡死所以必须寄存、`MovaSeeked` 不等于落地 | 同 A7-① | 批次 api,extras；main_coverage_api:basic{A7.seek,A7.negative}；coverage_new:live{A7.live}；批次 gap-assumptions；coverage_gap:H20.hlsSeek、coverage_gap:H50.hlsSeek、coverage_gap:H14.manualSeek、coverage_gap:H17.{mp4,m3u8} | H14, H16, H17, H18, H20, H21, H22, H23, H32 | 真机 PASS（rerun.md:39）；单测 全 | — |
| A8-② | 真实系统音量端口：get/set 往返、系统离散级量化（1% 落到系统级）、仅 Android 注入音量端口；`dumpsys audio` 对账 | 同 A8-① | 批次 api,native-inputs；main_coverage_api:basic{A8.clamp} | H53, H58 | 真机 PASS（rerun.md:176）；单测 全 | — |
| A9-② | 真实窗口亮度读回（输入 -1/0/.25/.75/1/2 → 0/0/.25/.75/1/1） | 同 A9-① | 批次 api,widgets,extras；main_coverage_api:basic{A9.clamp} | H54 | 真机 PASS（rerun.md:177）；单测 全 | — |
| A10-② | 真实 media_kit：0.5/1/1.5/2 生效；-1/0 抛 `Invalid argument(rate)`，抛出后 `state.rate` 不变（这是引擎入口钳制前的真机结论：现入口已钳 0.25–4.0、NaN→1.0，-1/0 不再抵达 media_kit，待复测） | 同 A10-① | 批次 api；main_coverage_api:basic{A10.persist}；批次 gap-skin；coverage_gap_skin:S9.bilibili.buttons（Bilibili 倍速 1.0→1.25，皮肤按钮路径） | H76 | 真机 PASS（rerun.md:42）；单测 部分 | — |
| A14-② | 真实转屏：方向端口 `apply()` 返回时方向已生效；size 半更新时按 state 宽高选方向会短暂选错 | 同 A14-① | 批次 widgets,ui；main_coverage_api:video；批次 gap-skin；coverage_gap_skin:S10.<皮肤>.fullscreenShot（5 套皮肤，全屏截图人工判，BLOCKED） | H12, H57 | 真机 PASS（rerun.md:46）；单测 全 | — |
| A15-② | 与系统 PiP 互斥（小窗态触发 `enterPip` 先 `setMini(false)`）；不重新解码（position 连续） | 同 A15-① | 批次 widgets；main_coverage_api:video；批次 gap-lifecycle；coverage_gap:A15.miniPip | H56 | 真机 PASS（retest.md:134，仅专项子项）；单测 全 | — |
| A16-② | 真实转屏（`dumpsys` 或截图宽高）；端口 apply 即时生效 | 同 A16-① | 批次 widgets,ui；main_coverage_api:video；批次 gap-skin；coverage_gap_skin:S9.{default,bilibili}.buttons（方向按钮仅移动端） | H12, H57 | 真机 PASS（rerun.md:48）；单测 全 | — |
| A17-② | 真实 HLS 档位切换：续播落点、RESTART 个数、seek 回声与丢弃、ABR 误降档、默认（无原生泵）配置下的落地信号、档位列表解析、档位切换是重开 URL 而非切轨 | 同 A17-① | 批次 followups,hls-native,final-hls；coverage_new:hls；批次 gap-assumptions；coverage_gap:H28.{default,precise}.{playing,paused,cutover}、coverage_gap:H14.manualSeek；批次 gap-skin；coverage_gap_skin:S9.{default,bilibili}.buttons（清晰度 sheet 切档） | H5, H16, H17, H18, H19, H24, H26, H27, H28, H29, H30 | 真机 FAIL（最近完整三组 retest5.md:209，1/280）；暂停态补跑 PASS 60/60（retest6.md:54-60）；判据口径 <200ms 与 ±500ms 待统一；单测 全 | — |
| A18-② | 通道层：`pipChanged` 方法调用 → `pipChanges` 流；`isPipSupported`/`enterPip` 的 PlatformException/MissingPluginException → false | 同 A18-① | 批次 gesture-pip；main_coverage_api:video；批次 gap-lifecycle；coverage_gap:A15.miniPip（含 enterPip） | H55 | 真机 PASS（rerun.md:50）；单测 全 | — |
| A20-② | 真实直播流：隐藏 ≥3s 后回边缘的恢复效果、DVR 窗口与 `timeshiftBehind` | 同 A20-① | 批次 live-inputs；coverage_new:live | H61, H78 | 真机 PASS（rerun.md:52）；单测 全 | — |
| A23-② | 真实内核：任意时刻 dispose 不卡死、内核层二次 dispose 会抛（已证伪，引擎层已防）、open 挂起时命令串行、FFI destroy 与 media_kit 竞态 | 同 A23-① | 批次 api；main_coverage_api:basic{A23.doubleDispose,A23.postOpen}；main_coverage_api:disposeStress{A23.120}；批次 gap-lifecycle；coverage_gap:H37.dispose、coverage_gap:A15.miniPip（二次 dispose） | H23, H36, H37, H38 | 真机 PASS（retest.md:136，仅专项子项）；单测 全 | — |
| A24-② | 真实预热：就绪判据、影子 buffer 语义（HLS/直播）、open 后立即 seek(at)、预热期间 pause/seek、读取 `renderHandle` 才建 VideoController、预热静音只改 mpv `mute` | 同 A24-① | 批次 api,existing-pages；coverage_new:cutover{A24.cutoverTo,A24.short,A24.timeout,A24.commit…} | H15, H20, H47, H49, H50, H51, H52 | 真机 PASS（rerun.md:56）；单测 全 | — |
| A25-② | 真实内核属性：`file-format` 取值、`audio-params` 就绪时机、`vid`/`mute` 保存改写还原、`vid` 切回无 RESTART（已证伪）、无声流强制 B 会 EOF、待机画面（Android 纯黑/Windows 冻帧）、位置漂移、`maxDuration` 到期、EOF 后 track-list | 同 A25-① | 批次 keepalive-core,existing-pages；keep_alive_auto:_s1；keep_alive_auto:_s2；keep_alive_auto:_s17；批次 gap-lifecycle；coverage_gap:H42.wake | H10, H39, H40, H41, H42, H43, H44, H45, H46 | 真机 PASS（rerun.md:57）；单测 全 | — |
| A28-② | 真实自然完播（keep-open 下不发 END_FILE(eof)，靠 `completed`）；播完后 `play()` 重播 | 同 A28-① | 批次 api,extras；main_coverage_api:playlist{A28.auto,A28.end,A28.start} | H9, H25 | 真机 PASS（rerun.md:60）；单测 全 | — |
| A30-② | 真实 libmpv 抽帧（`MovaFrameExtractor`；假内核的 `screenshot()` 只返回测试给的字节） | 同 A30-① | 批次 api,extras,safe-transition；coverage_new:preview{A30.diskHit} | H75 | 真机 PASS（rerun.md:62）；单测 全 | — |
| A35-② | 真实 mpv 属性（`demuxer-max-back-bytes` 等）按格式生效与还原的读回 ⟨新增：同上⟩ | 同 A35-① | 缺（`gap-formats` 的 G3.2 用例顺带读回 `file-format`/`seekable`/`demuxer-max-back-bytes`，可作 H63 旁证，但没有“按格式生效与还原”的判据，不计该编号用例） | H39, H63 | 真机 未跑（无用例）；单测 全 | 真机缺 |

#### C 配置对象（9 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| C1-② | 预览来源链里的抽帧兜底依赖真实 libmpv 抽帧（假内核 `screenshot()` 只返回测试给的字节） | 同 C1-① | 批次 api,extras,safe-transition；coverage_new:preview | H75 | 真机 PASS（rerun.md:66）；单测 全 | — |
| C2-② | 真实直播流：实时流判定（WHEP/FLV 的 `file-format`）、`getProperty` 对不可用属性返回空串或抛异常、DVR 窗口；按 behind 返回历史的时移服务缺失（BLOCKED） | 同 C2-① | manifest 无批次；coverage_new:live；manual 登记 缺按 behind 返回历史媒体的服务，滑动 HLS 不等于历史回看。 | H63, H64, H78 | 真机 BLOCKED（rerun.md:182）：已测真实FLV/HLS durationStep、12s本地DVR、behind/回边缘三轮；未提供按behind URL返回历史且可控卡顿服务；单测 全 | — |
| C4-② | 真实限速降档与误降档：pause/seek 的 buffering 边沿被当卡顿、续播自身缓冲被计入（已证伪，已修）、`_abrHold` 解除 | 同 C4-① | 批次 api,final-abr；coverage_new:abr | H14, H26, H27 | 真机 PASS（rerun.md:69）；单测 部分 | — |
| C11-② | 开启后真实预热就绪判据 | 同 C11-① | 批次 api,existing-pages；coverage_new:cutover{C11.off} | H49 | 真机 PASS（rerun.md:76）；单测 全 | — |
| C13-② | 真机 QoE 信号：mpv error 日志 prefix 分类、`paused-for-cache` 是真卡顿、静默断流以 EOF 结束、`sample()` 各属性可用性 | 同 C13-① | 批次 api,followups；main_coverage_api:basic{C13.off} | H31, H71, H73, H74 | 真机 PASS（rerun.md:78）；单测 全 | — |
| C14-② | 真实超时：404/拒连秒判、hang 源由 mpv `network-timeout` 先于 Dart 兜底、按源 mpv 选项读回 | 同 C14-① | 批次 api,he-recovery,extras；coverage_new:recovery | H8, H65 | 真机 PASS（rerun.md:79）；单测 全 | — |
| C15-② | 默认值校准：`file-format` 取值、待机后位置漂移、`maxDuration` 到期行为；出声与到期断流（计划未落地，见 F17） | 同 C15-① | 批次 keepalive-core,existing-pages；keep_alive_auto:_s2；keep_alive_auto:_s17 | H39, H45, H46 | 真机 PASS（rerun.md:80）；单测 全 | — |
| C16-② | 真实证书矩阵：合法/非法证书；IP SAN 证书被 Android mbedtls 拒（已证伪） | 同 C16-① | 批次 followups,final-tls,final-tls-probe；coverage_new:tls{C16.matrix}；coverage_new:tlsProbe{C16.probe} | H66 | 真机 FAIL（原生 TLS：IP SAN 合法证书 5/5 被拒，H66；rerun.md:187）；单测 部分 | — |
| C17-② | 数值属性读回与写入一致、`demuxer-lavf-o` 按键增删不冲掉默认 `protocol_whitelist` | 同 C17-① | 批次 api；coverage_new:read{C17.pick}；批次 gap-formats；coverage_gap:G3.2.hevcSoftware（`MovaSource.mpvOptions={'hwdec':'no'}`） | H29, H65, H67 | 真机 PASS（rerun.md:82）；单测 全 | — |

#### E 事件（17 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| E1-② | 真实内核下的事件序列与顺序（open 清理 Pause/Duration(0)/Size(0) → Play → SourceChange → Ready → Duration/Size → FirstFrame(restart)） | 同 E1-① | 批次 api；coverage_new:lifecycle | H1, H13 | 真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:190）；单测 全 | — |
| E.MovaReady-② | `MovaReady`：open 成功后发一次，无载荷（恢复路径 announces ready once） | `core/recovery/engine_recovery_test.dart` :236,:249-253 #8 恢复路径 announces ready once；`core/engine_verbs_test.dart` :362 正常 open 恰一个 MovaReady | 批次 api；main_coverage_api:basic | H1, H13 | 真机 PASS（rerun.md:83）；单测 全 | — （已补：P1-01） |
| E.MovaPlay-② | `MovaPlay`：内核 playing → true 边沿；Play 是意图事件，早于 Ready/FirstFrame | `core/report/collector_test.dart` :30 手工推入 collector（非引擎）；`core/engine_verbs_test.dart` :121 内核 playing 边沿 → MovaPlay，state.playing 同步 | 批次 api；main_coverage_api:basic | H13 | 真机 PASS（rerun.md:85）；单测 全 | — （已补：P0-01） |
| E.MovaPause-② | `MovaPause`：内核 playing → false 边沿 | `core/report/collector_test.dart` :31 手工推入；`core/engine_verbs_test.dart` :121 内核 playing 边沿 → MovaPause | 批次 api；main_coverage_api:basic | H13 | 真机 PASS（rerun.md:86）；单测 全 | — （已补：P0-01） |
| E.MovaDone-② | `MovaDone`：点播自然完播（`completed`；keep-open 下无 END_FILE(eof)）；直播结束在 hold 时单次 | `core/keep_alive/engine_keep_alive_rules_test.dart` :292-299 live 结束在 hold 时单次 MovaDone；`core/engine_verbs_test.dart` :134 completed=true → 恰一个 MovaDone 且 state.completed | 批次 api；coverage_new:lifecycle | H9 | 真机 PASS（rerun.md:87）；单测 全 | — （已补：P0-01） |
| E.MovaSeeked-② | `MovaSeeked`：seek 命令返回后发（载荷 position），不代表落地 | `core/engine_verbs_test.dart` :223,:233 MovaSeeked 载荷为钳后值 / :270 寄存的 seek 兑现后报钳后值 | 批次 api；main_coverage_api:basic | H22 | 真机 PASS（rerun.md:89）；单测 全 | — （已补：P0-04） |
| E.MovaBufferChange-② | `MovaBufferChange`：buffering 边沿（载荷 buffering）；放弃恢复后补发 false；cutover 代理下与 state 差一拍 | `core/recovery/recovery_fixes_test.dart` :77,:92 放弃后补发 BufferChange(false)；`core/report/stats_probe_test.dart` :100 ⟨缺：常规缓冲边沿载荷⟩ | 批次 api；main_coverage_api:basic | H14, H77 | 真机 FAIL（快照语义：state 与载荷差一拍，H77；rerun.md:188）；单测 部分 | — |
| E.MovaDurationChange-② | `MovaDurationChange`：时长变化（点播会微调 40000→40007；直播按 `durationStep` 节流） | `core/live/duration_throttle_test.dart` :44-89 | 批次 api；main_coverage_api:basic | H11 | 真机 PASS（rerun.md:91）；单测 全 | — |
| E.MovaFirstFrame-② | `MovaFirstFrame`：`sinceOpen` + `signal`（restart/buffering/size/grace）；每次 open 重置并重发 | `core/first_frame_engine_test.dart` :48,:154,:191；`core/render/first_frame_test.dart` :8-135；`core/report/stats_probe_test.dart` :148 signal=restart | 批次 he-firstframe；main_coverage_api:basic | H1, H3, H4, H5, H6, H72 | 真机 PASS（rerun.md:92）；单测 全 | — |
| E.MovaSizeChange-② | `MovaSizeChange`：宽高变化；真机出现半更新（640×0） | `core/engine_test.dart` :61 仅断言 state.size；`core/engine_verbs_test.dart` :353 内核尺寸上报变成恰一个 MovaSizeChange 并更新 state | 批次 widgets；coverage_new:lazy | H12 | 真机 FAIL（真实半更新 640×0，H12；rerun.md:189）；单测 全 | — （已补：P1-01） |
| E.MovaAbrDownShift-② | `MovaAbrDownShift`：ABR 降档（载荷 from/to） | `core/engine_test.dart` :656,:701；`core/keep_alive/engine_keep_alive_rules_test.dart` :221-:232 | 批次 final-abr；coverage_new:abr | H26, H27 | 真机 PASS（rerun.md:99）；单测 全 | — |
| E.MovaPipChange-② | `MovaPipChange`：PiP 变化（展开/点 X 关闭后复位为 false，重复值不重发） | `core/engine_test.dart` :1478 [true,false] 且重复值不重发 | 批次 gesture-pip；main_coverage_api:video | H55 | 真机 PASS（rerun.md:105）；单测 全 | — |
| E.MovaLiveEdgeReach-② | `MovaLiveEdgeReach`：直播回到边缘 | `core/engine_test.dart` :1135,:1266；`core/keep_alive/engine_keep_alive_wake_test.dart` :109,:146 | 批次 live-inputs；coverage_new:live | H61, H78 | 真机 PASS（rerun.md:108）；单测 全 | — |
| E.MovaErrorEvent-② | `MovaErrorEvent`：错误文本；过滤 mpv 自己打的两行 "Cannot seek"（benign） | `core/engine_test.dart` :562；`core/recovery/engine_recovery_test.dart` :132；`core/cutover/cutover_engine_defects_test.dart` :209,:419 | 批次 api；coverage_new:hooks | H31, H32 | 真机 PASS（rerun.md:112）；单测 全 | — |
| E.MovaPlayFailure-② | `MovaPlayFailure`：一次播放失败尝试（kind/action/attempt/isLive/sourceIndex） | `core/recovery/engine_recovery_test.dart` :112-:354；`core/recovery/failover_test.dart` :47；`core/recovery/live_reconnect_test.dart` :121 | 批次 he-recovery；coverage_new:recovery | H7, H8, H33 | 真机 PASS（rerun.md:113）；单测 全 | — |
| E.MovaRecovered-② | `MovaRecovered`：恢复成功（attempts）；之后 `state.error` 清空 | `core/recovery/engine_recovery_test.dart` :332；`core/recovery/live_reconnect_test.dart` :121；`core/recovery/recovery_fixes_test.dart` :51 | 批次 he-recovery；coverage_new:recovery | H35 | 真机 PASS（rerun.md:114）；单测 全 | — |
| E.MovaKeepAliveResume-② | `MovaKeepAliveResume`（旧 MovaStandbyResume）：唤醒完成（elapsed/signal）；真机恒走 grace、elapsed 恒等于 resumeTimeout | `core/keep_alive/engine_keep_alive_wake_test.dart` :21-87 elapsed/signal；`core/keep_alive/engine_keep_alive_silent_wake_test.dart` :39 H42 无任何唤醒信号则 resuming 持续到 resumeTimeout，以 grace 收尾 / :61 elapsed 随自定义 resumeTimeout / :78 静默唤醒不重发首帧也不丢 rendered / :93 超时后迟到的 size 不产生第二次 resume / :107 内核推 size 的重开路径在超时前落地 / :122 原生 RESTART 落地为 restart | 批次 keepalive-core；keep_alive_auto:_s1（现名 KeepAlive） | H42 | 真机 PASS（rerun.md:117）；单测 全 | — |

#### U UI 组件（1 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| U9-② | 真实生命周期：切后台序列 `inactive → hidden`、libmpv 回收渲染面自暂停的时序、直播隐藏 ≥3s 回边缘、路由覆盖/`TickerMode`/RouteObserver 路径 | 同 U9-① | 批次 he-recovery,widgets,interactive；main_coverage_api:video | H55, H59, H60, H61, H62 | 真机 PASS（rerun.md:128）；单测 全 | — |

#### F 功能场景（14 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| F1-② | 真实事件序列与无异常：open 清理 → Play → SourceChange → Ready → Duration/Size → FirstFrame → Done | 同 F1-① | 批次 api；coverage_new:lifecycle{F1} | H1, H13 | 真机 PASS（rerun.md:129）；单测 部分 | — |
| F2-② | 真实直播流（本地滑动 HLS DVR / FLV）：实时流判定、DVR 窗口 | 同 F2-① | 批次 live-inputs；coverage_new:live | H63, H78 | 真机 PASS（rerun.md:130）；单测 全 | — |
| F3-② | 真机续播误差与误降档（原矩阵口径 <200ms，复测口径 ±500ms，需统一）；默认无泵路径零数据 | 同 F3-① | 批次 followups,hls-native,final-hls；coverage_new:throttle{F3.abrBackToBack}；批次 gap-assumptions；coverage_gap:H28.{default,precise}.{playing,paused,cutover}、coverage_gap:H14.manualSeek | H5, H16, H18, H19, H24, H26, H27, H28 | 真机 FAIL（最近完整三组 retest5.md:209，1/280）；暂停态补跑 PASS 60/60（retest6.md:54-60）；判据口径 <200ms 与 ±500ms 待统一；单测 全 | — |
| F4-② | 真实预热/影子 seek/静音；HLS 内容做 cutover 无样本 | 同 F4-① | 批次 api,existing-pages；coverage_new:adResume{F4.adResume}；批次 gap-assumptions；coverage_gap:H20.hlsSeek、coverage_gap:H50.hlsSeek | H15, H20, H21, H47, H49, H50, H51, H52 | 真机 PASS（rerun.md:132）；单测 全 | — |
| F5-② | PiP 真实进入/展开/关闭后 state 复位；小窗与 PiP 互斥；回前台后暂停是系统级行为（渲染面被回收），非小窗特有 | 同 F5-① | 批次 gesture-pip；main_coverage_api:video；he_auto:_v11；批次 gap-lifecycle；coverage_gap:A15.miniPip | H55, H56, H60 | 真机 PASS（retest.md:135，仅专项子项）；单测 部分 | — |
| F6-② | 真实属性与时序：`vid` 切回、位置漂移、`maxDuration` 到期、`audio-params` 就绪时机 | 同 F6-① | 批次 keepalive-core,existing-pages；keep_alive_auto:_s1；keep_alive_auto:_s7；keep_alive_auto:_s8；批次 gap-lifecycle；coverage_gap:H42.wake | H10, H39, H40, H41, H42, H43, H44, H45, H46, H48 | 真机 PASS（rerun.md:134）；单测 全 | — |
| F7-② | 真机信号：首帧（restart 信号）、真卡顿、静默断流 EOF、`sample()` 属性可用性 | 同 F7-① | 批次 api,followups；coverage_new:qoe | H2, H3, H4, H6, H9, H31, H64, H69, H71, H72, H73, H74 | 真机 PASS（rerun.md:135）；单测 全 | — |
| F8-② | 真实：旧文件迟到的 END_FILE、坏地址秒判、`open` 抛不抛、真卡顿期间 buffering、续播 seek | 同 F8-① | 批次 he-recovery,extras,he-v6-final；he_auto:_v6；he_auto:_v7；coverage_new:recovery | H7, H8, H20, H33, H34, H35 | 真机 PASS（rerun.md:196）；单测 全 | — |
| F10-② | 真实抽帧与断网降级 | 同 F10-① | 批次 api,extras；coverage_new:preview | H75 | 真机 PASS（rerun.md:138）；单测 全 | — |
| F13-② | 真实多引擎：dispose 竞态与 FFI destroy、三引擎并存事件互不串扰；dispose 期间帧间隔 <100ms | 同 F13-① | 批次 api；main_observe_event_verify2:_v6；main_observe_event_verify2:_v7 ；性能参见 PF4、PF5、PF9（并存/池化/掉帧；<100ms 仍需原专项） | H36, H38, H70 | 真机 PASS（rerun.md:141）；单测 部分 | — |
| F14-② | 真机：release 下 RESTART/END_FILE 到达、RESTART 个数、destroy 与 media_kit 共存、END_FILE reason 枚举 | 同 F14-① | 批次 existing-pages；main_observe_event_verify2:_v9 | H5, H38, H68, H69, H72 | 真机 PASS（rerun.md:142）；单测 部分 | — |
| F15-② | 真实：默认白名单放行 dtls、"Cannot seek" 来源 | 同 F15-① | manifest 无批次；main_whep_verify:_run；manual 登记 缺可控 WHEP 服务 端口可达不证明播放。 | H32, H67 | 真机 BLOCKED（rerun.md:197）：WHEP端点38889/test/whep拒连，相关端口探测不可用；缺publisher/信令/UDP38189及relay38190服务；单测 部分 | — |
| F16-② | 真机复现与复核：PiP 展开/点 X 复位、广告方向与倍速恢复 | 同 F16-① | 批次 existing-pages,gesture-pip；main_review_fixes_verify2:_v10；main_review_fixes_verify:_v9 | H55 | 真机 PASS（rerun.md:144）；单测 部分 | — |
| F17-② | 保活出声（`MovaKeepAliveMode.audible`）与到期断流（`onExpire`/`MovaKeepAliveExpire`、`MovaHiddenMode.keepAliveAudible`）——计划 `2026-10-27-keepalive-audible-and-disconnect.md` **未落地**，标「未实现」，不计 FAIL ⟨新增：计划存在但代码未实现（device-trace §3 核对）；实现后需单测 + 真机核对⟩ | 缺：功能未实现，无单测 | 缺 | H46, H48 | 未实现（计划未落地，不计 FAIL；device-trace §3） | 真机缺 |

#### N 新增 API（16 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| N1-② | 真实黑洞主机判失败耗时（设 `network` 后 vs 默认 5.27s；65s 是 Dart 兜底） | 同 N1-① | 批次 api；coverage_new:read{N1.network} | H8 | 真机 PASS（rerun.md:145）；单测 全 | — |
| N2-② | 真实卡顿/看门狗：pause 不引发 buffering、真卡顿期间 buffering 持续为 true，stall 计时据此运转 | 同 N2-① | 批次 api；coverage_new:watchoff{N2.watchoff}；coverage_new:read{N2.derived} | H14, H34 | 真机 PASS（rerun.md:146）；单测 全 | — |
| N4-② | 真实读回：数值属性形态、`demuxer-lavf-o` 按键增删不冲掉默认白名单 | 同 N4-① | 批次 api；coverage_new:read{N4.applied,N4.whepOptions,N4.restore} | H65, H67 | 真机 PASS（rerun.md:148）；单测 全 | — |
| N5-② | 真实：404 秒判（几十 ms）与拒连时间（Android 毫秒级/Windows 约 5s）、END_FILE reason | 同 N5-① | 批次 api；coverage_new:recovery | H7, H8, H69 | 真机 PASS（rerun.md:149）；单测 全 | — |
| N6-② | 真实加载在途收到的 END_FILE 归属：旧文件迟到的 END_FILE 不应算到新 open 头上 | 同 N6-① | 批次 api,extras；coverage_new:recovery{N6.clear,N6.giveup} | H7 | 真机 PASS（rerun.md:150）；单测 全 | — |
| N7-② | 真实直播流 duration 变化形态（durationStep 节流的输入）与 DVR 窗口 | 同 N7-① | 批次 api；coverage_new:live | H78 | 真机 PASS（rerun.md:151）；单测 全 | — |
| N8-② | 真实坏地址下 `kernel.open` 抛不抛（记录矛盾：CLAUDE 称 openThrew，HE/R 实测不抛） | 同 N8-① | 批次 api,extras；coverage_new:hooks{N8.accept,N8.disposed,N8.reject,N8.playlistRejected…} | H33 | 真机 PASS（rerun.md:152）；单测 全 | — |
| N9-② | Dart 通道层 `pipChanged` → 流、异常 → false；Kotlin 侧展开/关闭回调 | 同 N9-① | 批次 gesture-pip；main_coverage_api:video | H55, H70 | 真机 PASS（rerun.md:153）；单测 全 | — |
| N10-② | 真机倍速窗口与预热静音 | 同 N10-① | 批次 api,existing-pages；coverage_new:adResume | H47 | 真机 PASS（rerun.md:154）；单测 全 | — |
| N11-② | 真实 `mute` 保存改写还原；`dumpsys audio` 对账媒体音量恒定 | 同 N11-① | 批次 existing-pages；main_q13_mute_verify:_scenarioPlain；main_q13_mute_verify:_scenarioKeepAlive | H41, H47, H53 | 真机 PASS（rerun.md:155）；单测 全 | — |
| N12-② | 真实首帧信号：初始 buffering=false 不是首帧、暂停态 open 也有 RESTART、一次加载多个 RESTART、迟到 RESTART 不算新源首帧 | 同 N12-① | 批次 api,he-firstframe,native-inputs；he_auto:_v1；he_auto:_v3；he_auto:_v4 | H1, H2, H3, H4, H5, H6, H28 | 真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:198）；单测 全 | — |
| N13-② | 真机：弱客户端数、懒创建、release 原生回调 | 同 N13-① | 批次 api,he-firstframe,existing-pages；he_auto:_v1；coverage_new:lazy | H36, H38, H52, H68 | 真机 PASS（rerun.md:157）；单测 全 | — |
| N18-② | 真实生命周期时序与小窗连续播放的守卫豁免（新增补测 APK 已构建，因锁屏未跑完） | 同 N18-① | manifest 无批次；he_auto:_v10；he_auto:_v9；he_auto:_v11；keep_alive_auto:_s17；manual 登记 完整 mini/guard-off 联动需专用包和复核，主包不足。 | H59, H60, H61, H62 | 真机 BLOCKED（rerun.md:162）：已测HE前后台/route/Ticker/PiP各3轮，inactive意图及直播隐藏>=3s回边缘LiveEdgeReach、真实Feed滚动和View RouteObserve；单测 全 | — |
| N19-② | 真机：真卡顿期间 buffering、恢复后续播到失败前位置 | 同 N19-① | 批次 api,he-recovery,extras,he-v6-final；coverage_new:recovery{N19.failover} | H34, H35 | 真机 PASS（rerun.md:199）；单测 全 | — |
| N20-② | 真实内核属性与时序（见 A25-②） | 同 N20-① | 批次 keepalive-core,existing-pages；keep_alive_auto:_s1；批次 gap-lifecycle；coverage_gap:H42.wake | H40, H41, H42, H43, H44, H45, H46 | 真机 PASS（rerun.md:164）；单测 全 | — |
| N23-② | 真机：首帧 signal 全为 restart、静默断流 EOF、卡顿信号 | 同 N23-① | 批次 api,followups；coverage_new:qoe | H2, H3, H71, H72, H73 | 真机 PASS（rerun.md:167）；单测 全 | — |

#### P 公开类型家族（2 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| P9-② | `MovaFrameExtractor`/`MovaFramePuller` 依赖真实 libmpv 抽帧 | 同 P9-① | manifest 无批次；coverage_new:preview{A30.diskHit}；仅相关子项，未发现该编号专用完整验收器 | H75 | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | — |
| P12-② | 平台端口：`MovaSystemVolumePort`/`MovaScreenBrightnessPort`/`MovaChannelPipPort`/`MovaSystemChromeOrientationPort`、`MovaFallback*`/`MovaCallback*`/`MovaNoop*`；单测只有「类型是它」断言，原生读回要真机 | `core/ports_test.dart` :5 MovaFallbackBrightnessPort, :12 MovaNoopPipPort；`core/engine_test.dart` :1670 MovaCallbackVolumePort；`platform_impl/wiring_test.dart` :102-123 仅类型断言；`method_channel_test.dart` :27-46；`platform_impl/ports_impl_test.dart` :59 MovaSystemChromeOrientationPort（:79 全屏+沉浸+横屏视频→横屏与 immersiveSticky / :97 竖屏视频→竖屏 / :108 强制方向优先于视频比例 / :120 窗口态 auto 放行全方向并保留系统栏 / :132 reset 还原全方向与 edgeToEdge / :141 先设方向再设 UI 模式）/ :154 MovaSystemVolumePort（:166 get 返回平台音量 / :171 平台无原生实现回落 100 / :176 set 原样转发 / :181 set 越界先钳到 0–100）；`method_channel_test.dart` :173 系统音量通道 PlatformException 降级 ⟨缺：MovaFallbackVolumePort（ports.dart:155，P2-05）零引用；MovaScreenBrightnessPort 只有“类型是它”的断言⟩ | manifest 无批次；main_coverage_api:basic{A8.clamp,A9.clamp}；main_coverage_api:video；仅相关子项，未发现该编号专用完整验收器 | H53, H54, H55, H57 | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | P2-05；已补：P1-12 |

### 3.3 ③ 只能真机

渲染/画面、手势手感、PiP 窗口、格式裁剪面、ABI/混淆、音频焦点、息屏、网络切换、浸泡等。单测只能承载其中的纯逻辑子点（那部分已在 ① 行里）。S 皮肤专项按「检查项 × 五套皮肤」做成矩阵。

#### A 公开 API（10 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 相关假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| A3-③ | Android 上真实 VideoController 创建、挂树出画、宽高 640x360 | — | 批次 api,widgets；main_coverage_api:basic{A3.audio}；coverage_new:lazy{A3.lazyOpened,A3.lazyRead,A3.lazyBefore} | — | 真机 PASS（rerun.md:35） | — |
| A11-③ | 画面真实变化（contain/cover/fill 截图对比） | — | 批次 widgets,ui；main_coverage_api:video；批次 gap-skin；coverage_gap_skin:S9.{default,bilibili}.buttons（fit 按钮：`fit.next` +1 个 MovaFitChange） | — | 真机 PASS（rerun.md:43） | — |
| A12-③ | 缩放后手势平移与真实画面 | — | 批次 ui；main_coverage_api:video | — | 真机 PASS（retest.md:137，仅专项子项） | — |
| A14-③ | 系统栏隐藏/恢复、刘海/安全区、退出后原生恢复 FULL_USER | — | 同 A14-② | — | 真机 PASS（rerun.md:46） | — |
| A18-③ | 真实 PiP 窗口：`dumpsys activity` 见 `mIsInPictureInPictureMode=true`/pinned；展开与点 X 关闭后 `state.pip` 复位 | — | 同 A18-② | — | 真机 PASS（rerun.md:50） | — |
| A23-③ | 120 轮创建销毁的 PSS 趋势（泄漏） | — | 同 A23-② ；性能参见 PF8（长场景泄漏斜率；不替代原 120 轮销毁专项） | — | 真机 PASS（retest.md:136，仅专项子项） | — |
| A24-③ | 帧级无缝：广告↔正片切换无黑屏帧/撕裂（screencap 序列对齐 logcat 事件） | — | 同 A24-② | — | 真机 PASS（rerun.md:56） | — |
| A26-③ | 拖拽跟手、吸边、甩动不误关（手感） | — | 批次 widgets,interactive,touch-mini；main_coverage_api:video | — | 真机 PASS（rerun.md:58） | — |
| A29-③ | 真实视频滑动 100 次 + 20 次并发：原生池 3 引擎、回收完成 | — | 批次 api,interactive；coverage_new:feed{A29.dispose,A29.final} | — | 真机 PASS（rerun.md:61） | — |
| A31-③ | 真实识别（模型下载、转写）：需真实引擎与模型服务 | — | manifest 无批次；coverage_new:stt；manual 登记 缺真实 STT 模型/识别引擎和下载服务 失败回滚仅为子项。 | — | 真机 BLOCKED（rerun.md:181）：已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试 | — |

#### C 配置对象（4 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 相关假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| C3-③ | 手势手感（主观项）、Douyin 手势层真实触摸 | — | 批次 gesture-pip,interactive；main_coverage_api:video | — | 真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:183） | — |
| C6-③ | 弹幕滚动/密度/轨道真实渲染 | — | 批次 safe-visual；main_coverage_api:video | — | 真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:184） | — |
| C7-③ | 真实识别（同 A31-③） | — | manifest 无批次；coverage_new:stt；manual 登记 同 A31，缺真实识别及导出完整证据。 | — | 真机 BLOCKED（rerun.md:185）：已测disabled/noEngine阻断、注入引擎首启失败回滚/二次重试 | — |
| C10-③ | 真实外观（截图：文案、60/8/红色 spinner、错误层） | — | 批次 widgets,safe-visual；main_coverage_api:video；批次 gap-skin；coverage_gap_skin:S13.{default,bilibili,douyin,minimal,mini}.inject | — | 真机 PASS（rerun.md:75） | — |

#### U UI 组件（5 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 相关假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| U1-③ | Impeller 下真实渲染面出画；View route/ticker 路径与 Feed 真实挂卸 | — | 批次 widgets,safe-visual；main_coverage_api:video | 参见 H52 | 真机 PASS（rerun.md:120） | — |
| U2-③ | 五套皮肤（Default/Bilibili/Douyin/Minimal/Mini）真实截图 | — | 批次 widgets,safe-visual；main_coverage_api:video；批次 gap-skin；coverage_gap_skin:S1.*（组件树 + 挂载探针）、S2.<皮肤>.layoutShot（4 套，截图人工判） | — | 真机 PASS（rerun.md:121） | — |
| U4-③ | 进度条真实拖动与悬停预览气泡（手感） | — | 批次 touch-preview；main_coverage_api:video | — | 真机 PASS（rerun.md:123） | — |
| U6-③ | 手感（主观项） | — | 批次 gesture-pip,interactive；main_coverage_api:video；批次 gap-skin；coverage_gap_skin:S4.{default,bilibili,douyin}.tap、S7.{default,bilibili}.lock、S7.douyin.lockObserve | 参见 H54 | 真机 FAIL（旧预期；矩阵预期已改，未按新预期复跑；rerun.md:193） | — |
| U8-③ | 拖动跟手、甩动手感 | — | 批次 widgets,interactive,touch-mini；main_coverage_api:video | 参见 H57 | 真机 PASS（rerun.md:127） | — |

#### F 功能场景（5 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 相关假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| F4-③ | 帧级无缝与续播误差 <100ms（screencap 序列） | — | 同 F4-② | — | 真机 PASS（rerun.md:132） | — |
| F9-③ | 出声不出画；内存/CPU 对比（真机） | — | 批次 api,widgets；main_coverage_api:basic ；性能参见 PF11（audioOnly 对照） | — | 真机 PASS（rerun.md:137） | — |
| F11-③ | 字幕：SRT/ASS/WebVTT 外挂 + mov_text 内封的 libass 合成渲染（libmpv 依赖，无单测面） | 相关（不承载结论）：`core/srt_test.dart` 仅 STT 产出的 SRT 序列化，非播放字幕渲染；`ui/subtitle_test.dart` 仅 STT 字幕叠层 | 批次 existing-pages,extras；coverage_new:subtitles{F11.$format} | — | 真机 PASS（rerun.md:139） | — |
| F12-③ | 音频会话与耗电：待机/音频模式的 CPU、`dumpsys batterystats` | — | 批次 existing-pages；keep_alive_auto:_s4 ；性能参见 PF11、PF8（资源趋势；耗电仍需原专项） | 参见 H46, H48, H74 | 真机 PASS（rerun.md:140） | — |
| F15-③ | 播 15s `MovaErrorEvent` 0 次（需可达 WHEP 服务；端口可达不证明播放） | — | 同 F15-② | — | 真机 BLOCKED（rerun.md:197）：WHEP端点38889/test/whep拒连，相关端口探测不可用；缺publisher/信令/UDP38189及relay38190服务 | — |

#### N 新增 API（2 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 相关假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| N15-③ | 封面真实淡出、Feed 首帧前封面 → 视频的画面过渡 | — | 批次 safe-visual,safe-transition；main_coverage_api:video | 参见 H43 | 真机 PASS（rerun.md:159） | — |
| N21-③ | Android 真机确认为空操作无副作用 | — | 批次 api,widgets；main_coverage_api:testing | — | 真机 PASS（rerun.md:165） | — |

#### S 皮肤专项（检查项 × 五套皮肤）

| 编号 | 检查项 | 单测承接 | Default | Bilibili | Douyin | Minimal | Mini |
|---|---|---|---|---|---|---|---|
| S1 | 组件树 | 全（S1-①） | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 |
| S2 | 点播布局 | 部分 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | N/A¹；已有负向子项证据 | 未跑·用例已写 |
| S3 | 直播布局 | 全 | 未跑 | 未跑 | 未跑 | N/A¹ | N/A² |
| S4 | 手势：单击/双击 | 全 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | N/A¹；已有负向子项证据 | N/A² |
| S5 | 手势：水平拖动 | 全 | 未跑 | 未跑·有子项证据 | 未跑 | N/A¹ | N/A² |
| S6 | 手势：竖滑 | 全 | 未跑 | 未跑 | 未跑 | N/A¹ | N/A² |
| S7 | 手势：捏合/锁定 | 全 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | N/A¹ | N/A² |
| S8 | 手势：长按/其他 | 部分 | 未跑 | 未跑 | 未跑·有子项证据 | N/A¹ | N/A² |
| S9 | 按钮逐个点击 | 全 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | N/A¹ | 未跑·用例已写 |
| S10 | 全屏与转屏 | 部分 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 |
| S11 | 覆盖层 | 全 | 未跑 | 未跑·有子项证据 | 未跑 | 未跑·有子项证据 | 未跑 |
| S12 | `MovaPatch` 四种补丁 | 全（S12-①） | 未跑·用例已写 | 未跑·用例已写 | N/A³ | N/A³ | N/A³ |
| S13 | 主题与文案 | 部分（S13-①） | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 |
| S14 | 皮肤切换 | 全（S14-①） | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 | 未跑·用例已写 |
| S15 | 已知失败项交叉（U3/U5/U6/U7） | 缺 | 未跑 | 未跑·有子项证据 | 未跑 | 未跑 | 未跑 |
| S16 | Mini 专项 | 全 | 未跑 | 未跑 | 未跑 | 未跑 | 未跑·有子项证据 |

**图例**：`未跑` = 该「检查项 × 皮肤」没有独立结论（device-trace 对 80 格逐格核对，**整项 PASS 为 0**，v1 的共享截图/组件树不能替代专项）；`未跑·有子项证据` = 有部分子项的验证代码/截图，但不能升级为该格 PASS；`未跑·用例已写` = `gap-skin` 批次里有对应 case（2026-10-28 新写，只做了离线校验，**未上机**），仍无结论，且不覆盖「历史子项证据」；`N/A` = 皮肤本身不支持该能力，依据如下。

- **N/A¹ Minimal**：`MovaMinimalSkin.components()` 只返回缓冲层与错误层（`lib/src/ui/skins/minimal_skin.dart:49`），没有手势层、顶/底栏、中心播放、HUD、锁定遮罩。
- **N/A² Mini**：`MovaMiniSkin.components()` 只有中心播放、缓冲、关闭按钮（`lib/src/ui/mini/mini_skin.dart:42`），没有手势层与顶/底栏。
- **N/A³ 补丁**：全库只有 `MovaDefaultSkin.components()` 调用 `applyPatches`（`default_skin.dart:62`，`MovaBilibiliSkin` 继承它）；Douyin（`douyin_skin.dart:71`）、Minimal、Mini 的 `components()` 不经补丁。
- 上述 N/A 只在「读 `components()` 即可确定」的格子里标注；Douyin 的 S3/S5/S7 等是否适用没有从源码得出结论，仍记「未跑」。已标 N/A 的格子，若要翻案需先改皮肤再改本表。
- 计数（2026-10-28 回填后）：80 格里 N/A 17、`未跑·用例已写` 36（其中 15 格此前另有历史子项证据）、`未跑·有子项证据`（尚无新用例）6、`未跑`（无任何证据）21；整项 PASS 仍为 0。回填前是 N/A 17 / 有子项证据 21 / 无证据 42。

**子项证据明细**（device-trace §1，按证据文本归并）：
- S1×Default, S1×Bilibili, S1×Minimal, S1×Mini, S2×Default, S2×Bilibili, S2×Minimal, S2×Mini, S14×Default, S14×Bilibili, S14×Minimal, S14×Mini：manifest ui；example/tool/coverage_ui.py:18–25 逐皮肤 skin 命令/截图；main_coverage_api.dart:336–354 video/skin，components 字符串与状态
- S4×Minimal：manifest interactive；example/tool/coverage_interactive.py:26 minimal-no-gesture；main_coverage_api.dart:336 skin；不支持手势的负向子项
- S5×Bilibili, S9×Bilibili, S11×Bilibili, S15×Bilibili：manifest safe-visual；example/tool/rerun_visual_safe.py 包装 coverage_visual_final.py:28–36；video/skin(bilibili) 后逐动作 preview/speed/center/danmaku；main_coverage_api.dart:281 video
- S8×Douyin, S9×Douyin：manifest interactive（仅Feed相关，缺独立全屏页）；example/tool/coverage_interactive.py:36–40 feed-double-like/social/single-pause；verify_auto/coverage_widgets.dart:40,65–68
- S11×Minimal, S13×Minimal：manifest safe-visual；example/tool/coverage_visual_final.py:37–40，video/skin(minimal/Empty/Error) + open(hang/404)，自定义 spinner/error 显隐
- S12×Default：manifest widgets；main_coverage_api.dart:347 video/skin(patch) 仅 MovaPatch.add；其余 Replace/Remove/InsertAfter 未覆盖
- S16×Mini：manifest touch-mini,interactive,widgets；example/tool/rerun_manual_inputs.py:44–49 mini 实触；main_coverage_api.dart:328–333 miniPage/Host/Hide/Close/Rect/Info；A/B互斥与转屏

**特别要求**（沿用 v2）：Douyin 必须有**独立的全屏播放页**用例，不能只在 Feed 里看；皮肤用例按 L 规范第 6 条额外打当前皮肤类名、`components()` 名单、各 `MovaSlot` 挂载组件、触摸注入的原始命令。

**`gap-skin` 批次（2026-10-28，未上机）**：42 个 case，覆盖 S1/S2/S4/S7/S9/S10/S12/S13/S14（共 36 格），详见 §5.2.5；其中 S2/S10 的截图只出图，视觉判定仍是人工项（BLOCKED，不是 FAIL）。N/A 格由 `gap:S0.matrixNA` 一次性写日志，不出结论。

#### P 公开类型家族（3 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 相关假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| P10-③ | 真实识别引擎、音频抽取（BLOCKED，无真引擎） | — | manifest 无批次；coverage_new:stt；仅相关子项，未发现该编号专用完整验收器 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | — |
| P15-③ | 至少一套皮肤里真实挂载并交互 | — | manifest 无批次；main_coverage_api:video；仅相关子项，未发现该编号专用完整验收器 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | — |
| P16-③ | HUD 真实触发并截图 | — | manifest 无批次；main_coverage_api:basic{A21.hud,A21.hide}；仅相关子项，未发现该编号专用完整验收器 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | — |

#### G 覆盖缺口（25 行）

| 编号 | 能力 / 子点 | 单测位置（`test/` 下） | 真机用例 | 相关假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| G1.1-③ | 多 ABI（armeabi-v7a/x86/x86_64）与 Android 13+ 真机；现只测 STG-AL00 arm64-v8a / Android 12 | — | 批次 gap-build-variants；coverage_gap:G1.1.build（manual，打印构建命令与判据，BLOCKED） | 参见 H66 | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | 用例已写，待上机 |
| G1.2-③ | release 混淆/R8 minify 下的 JNI、MethodChannel、反射路径（PiP 通道、音量/亮度端口）；历史构建全程 `-Pdart-obfuscation=false` | — | 批次 gap-build-variants；coverage_gap:G1.2.build（manual，打印构建命令与判据，BLOCKED） | — | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | 用例已写，待上机 |
| G1.3-③ | 以 pub.dev 依赖方式接入（0.3.0 发布版 vs Unreleased、官方非 slim libs 包路径） | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G1.3b-③ | iOS/macOS/Linux/Windows 桌面通用功能矩阵（Windows 仅零散；iOS/macOS 受无 Mac 限制 BLOCKED）；**Web 为 N/A**（库依赖 `dart:io`，§6 已决定） | 相关（不承载结论）：`ui/snapshot_guard_test.dart` :109-150 Windows 限定守卫的平台分支 | manifest 无批次；main_win_retest:main；仅相关子项，未发现该编号专用完整验收器 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | — |
| G1.4-③ | Android 上 Skia 后端对照（`--no-enable-impeller`）、不同 Flutter 版本（只有 3.47.0） | 相关（不承载结论）：`ui/snapshot_guard_test.dart` :57-150 | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G1.5-③ | 折叠屏/平板/分屏/多窗口/刘海/手势导航（单测只覆盖小窗约束收缩与 video rect 计算） | 相关（不承载结论）：`ui/mini/mini_window_test.dart` :162,:172 约束收缩/以外层约束为边界；`ui/video_rect_test.dart` :8-81 | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G2.1-③ | 真实音频焦点事件：来电、闹钟、其他 App 抢焦点、耳机拔出/蓝牙断开后的暂停与恢复 | — | 批次 gap-focus；coverage_gap:G2.1.focus（焦点归属与听感需人工，BLOCKED）；批次 gap-focus-gsm；coverage_gap:G2.1.emulatorCall（仅模拟器，真机 BLOCKED） | — | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | 用例已写，待上机 |
| G2.2-③ | 真实切网：Wi-Fi↔蜂窝、飞行模式开关、网络恢复后续播 | — | 批次 gap-network；coverage_gap:G2.2.network（需 `GAP_NETWORK_URL`；路由变化须人工核对）；原：manifest 无批次；main_error_prefix_verify:_run；仅相关子项，未发现该编号专用完整验收器 | — | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | — |
| G2.3-③ | 真实灭屏/锁屏/解锁：灭屏后播放、熄屏自动暂停与亮屏恢复；锁屏下音频是否持续 | — | 批次 gap-screen；coverage_gap:G2.3.screen（安全锁需人工解锁） | 参见 H60 | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | 用例已写，待上机 |
| G2.4-③ | 低内存 `onTrimMemory`、进程回收后重建、旋转/不保留活动导致 Activity 重建 | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G2.5-③ | 物理音量键/系统音量被外部改动：`state.volume` 是否同步（lib 内 `MovaVolumePort` 只有 get/set，是否监听外部变化待确认） | — | 缺 | 参见 H53 | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G2.6-③ | 系统亮度被外部改动、退出播放/全屏后窗口亮度是否还原 | — | 缺 | 参见 H54 | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G2.7-③ | 系统手势冲突（边缘返回、状态栏下拉）与垂直手势区域 | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G2.8-③ | 深色模式、字体缩放、系统语言切换、TalkBack 真实表现 | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G2.9-③ | 真实磁盘满/无存储权限 | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G3.1-③ | 本地来源：`file://`、`content://`（SAF/相册）、Flutter asset、沙盒路径 | — | 批次 gap-local；coverage_gap:G3.1.{file,asset,sandbox}；G3.1.content 为 BLOCKED（无 SAF provider/grant） | — | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | 用例已写，待上机 |
| G3.2-③ | 容器/编码裁剪面：mkv/webm/ts/mp3/aac/flac/ogg、H.265/AV1/10bit/VP9/杜比、4K/高码率硬解回退软解；不支持的要给明确错误而非挂起 | — | 批次 gap-formats；coverage_gap:G3.2.<13 个保留格式>、G3.2.hevcSoftware、G3.2.<5 个排除格式>；原：manifest 无批次；main_v041_verify:_runCase；仅相关子项，未发现该编号专用完整验收器 | 参见 H31, H39, H63 | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | — |
| G3.3-③ | 真实协议：RTMP/RTSP/DASH/AES-128 HLS/fMP4/多音轨/多字幕轨 | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G3.4-③ | 真实 HTTP 故障：302 链、无 Range/Content-Length、chunked、间歇 5xx、慢速抖动、HTTP/2、IPv6、代理 | — | manifest 无批次；main_error_prefix_verify:_run；仅相关子项，未发现该编号专用完整验收器 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | — |
| G3.5-③ | 真机同一 engine 先直播后点播再直播 | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G3.6-③ | 超长/超大文件、损坏文件、截断文件：不挂死且有 `MovaPlayFailure` | — | 缺 | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G4.1-③ | 真实内核下的随机序列与快速连点 | — | 批次 gap-random；coverage_gap:G4.1.seed（固定种子 80 步） | — | 真机 未跑（用例已写，待上机；无独立结论；相关旧用例不等于整项通过） | 用例已写，待上机 |
| G4.2-③ | 长时间浸泡：点播/直播 1–2h 的内存/发热/掉帧/句柄 | — | 缺 ；性能参见 PF6、PF7、PF8、PF9（浸泡时长由用户有意缩短为 480 秒，1–2h 不在计划内） | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |
| G4.3-③ | 真机热切换 `MovaOpts`/`MovaStrs`/`MovaTheme` | — | manifest 无批次；coverage_widgets:command(options) | — | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | — |
| G4.4-③ | 真机同屏两个 `MovaPlayer`、Feed 滑动 + 小窗 + 广告 cutover 叠加；多引擎事件互不串扰参见 H70 | — | 缺 | 参见 H70 | 真机 未跑（无独立结论；相关旧用例不等于整项通过） | 真机缺 |

#### PF 性能（③ 档）

| 编号 | 能力 / 子点 | 单测位置（判据） | 真机用例 | 依赖假设 | 最近结论 | 缺口 |
|---|---|---|---|---|---|---|
| PF1-③ | 点播硬解 H.264 1080p | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：vod-hw，10 分钟 | 真实硬解可用；读回 hwdec-current | 未跑 | 用例已写；待真实基线与上机；批次待合入 |
| PF2-③ | 点播软解 hwdec=no 对照 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：vod-sw，10 分钟 | 同源同设备 | 未跑 | 用例已写；待真实基线与上机；批次待合入。注（2026-10-28）：对当前自建 libmpv，`hwdec=no` 读回为 no 但仍走 MediaCodec（H.264 软解已在 flavor 中删除，见 mova-libmpv/flavors-mova-slim-n9.sh 注释），PF2 不是真软解对照，别当软解基线 |
| PF3-③ | 直播稳态资源 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：live，10 分钟 | 滑动 HLS 或已验证在线直播 | 未跑 | 用例已写；待真实基线与上机；批次待合入 |
| PF4-③ | cutover 预热双引擎并存 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：cutover，10 分钟 | 真实 MovaPlayer；两个 native 实例 | 未跑 | 用例已写；待真实基线与上机；批次待合入 |
| PF5-③ | feed 引擎池连续滑动 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：feed，10 分钟、5 秒切页 | 三引擎池；全部挂真实画面 | 未跑 | 用例已写；待真实基线与上机；批次待合入 |
| PF6-③ | 点播循环 60 分钟浸泡 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：soak-vod，**480 秒（用户有意缩短，维持此值）**，斜率只是短窗口外推 | H.264 本地源 loop-file=inf | 2026-10-28 基线已录（`perf_baseline/7NQBB23606003715.json`，判据 BLOCKED(no-baseline)；PSS 均值 234,097 KiB、线程 35.8、fd 210，未见越界增长） | 用例已写；待真实基线与上机；批次待合入 |
| PF7-③ | 直播 60 分钟浸泡 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：soak-live，**480 秒（用户有意缩短，维持此值）** | 实时滑动 HLS；不覆盖跨天 | 2026-10-28 基线已录（PSS 均值 286,168 KiB、线程 35.9、fd 213） | 用例已写；待真实基线与上机；批次待合入 |
| PF8-③ | 长场景泄漏最小二乘斜率 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：所有场景 PSS/Native Heap/fd/线程趋势 | 去预热；R²≥0.7 且斜率和绝对增量均超阈值 | 未跑 | 用例已写；待真实基线与上机；批次待合入 |
| PF9-③ | 视频掉帧与 Flutter jank | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：所有视频场景 mpv drop / gfxinfo | 掉帧率分母为 time-pos 增量×estimated-vf-fps；gfxinfo 每场 reset | 未跑 | 用例已写；待真实基线与上机；批次待合入 |
| PF10-③ | Windows release CPU/RSS 补充 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：同场景 --platform windows | Get-Process；同机基线；无 gfxinfo | 未跑 | 用例已写；待真实基线与上机；批次待合入 |
| PF11-③ | 可选 audioOnly CPU/内存对照 | `example/tool/test_perf_judge.py` | `coverage_perf.py` → `main_coverage_perf.dart` / `coverage_perf.dart`：audio，**180 秒（预热 30 秒，用户有意缩短）**；与 PF1 报告对照 | createMovaEngine(audioOnly:true)；耗电未覆盖 | 未跑 | 用例已写；待真实基线与上机；批次待合入 |

## 4. 假设清单（第 ② 档的依赖：测试替身 vs 真实 mpv / Android）

② 档的单测全部跑在假内核（`test/support/fake_kernel.dart` 的 `FakeKernel`、`lib/src/testing/test_kernel.dart` 的 `MovaTestKernel`、各测试内联假体）与假端口上；它们**默认做了什么**，就是一条条「假设」。假设错了，单测全绿也不代表真机正确。本节列全部 78 条，每条标状态、证据出处，并反指回 §3.2 的矩阵行。

**状态词**：`已核对`（有真机数字，括号内写平台）／`部分核对`（主路径核对过，写明缺哪一块）／`未核对`／`已证伪`（历史上被真机推翻，写明现行处理）。**文档缩写**：R=`results.md`；RT3…RT6=`retest3…6.md`（RT6 实为 rerun7）；RR=`rerun.md`；WR=`windows-retest.md`；HE=`2026-10-23-host-ergonomics.md`；SB=`2026-10-23-standby-mode.md`；HO=`2026-10-24-android-real-device-handoff.md`（均在 `doc/plans/`）。

**两个先决事实**（影响很多行的解读）：
1. F3/A17 的全部真机复测（RT3–RT6）都用 `createMovaEngine(preciseFirstFrame: true, …)`（`example/lib/verify_auto/coverage_new.dart:563`），即**原生 RESTART 泵开启**；默认 `createMovaEngine()` 无泵，首帧/档位落地走 `buffering` 下降沿（`MovaMpvKernel.nativeRestartAvailable=false`），这条路径没被真机量过（H28）。
2. 假内核是「事件由测试手推」的模型：`open()/play()/pause()/seek()` 只记录调用、**不产生任何内核事件**；`kernel_contract_test.dart` 只是测假体自己，**仓库里没有「同一套契约跑在 FakeKernel 和 MovaMpvKernel 上」的用例**。

**计数**：共 78 条——已核对 30、部分核对 24、未核对 13、已证伪 11。
- 已核对（30）：H1 H4 H8 H9 H13 H16 H21 H24 H27 H30 H32 H34 H36 H38 H40 H41 H44 H47 H49 H51 H55 H57 H59 H61 H67 H70 H72 H73 H75 H76
- 部分核对（24）：H3 H6 H11 H15 H17 H22 H29 H31 H35 H39 H45 H50 H52 H53 H54 H60 H62 H63 H65 H68 H69 H71 H74 H78
- 未核对（13）：H7 H10 H14 H20 H23 H25 H28 H33 H46 H48 H56 H58 H64
- 已证伪（11）：H2 H5 H12 H18 H19 H26 H37 H42 H43 H66 H77

### 4.1 已证伪（11 条）：历史上被真机推翻，现行单测里仍能找到旧影子

| 被推翻的假设 | 真机结论（出处） | 现在单测里仍沿用旧假设的位置 | 风险判断 |
|---|---|---|---|
| H2 open 后第一个 `buffering=false` 当首帧 | 假 TTFF（失败源 75ms 就报首帧）；已改下降沿 + 位置兜底（Android 2026-09-30） | 已有反例测试 `first_frame_engine_test.dart:110`、`ttff_test.dart:36`；但 `FakeKernel` 本身仍不发初始 false，新写测试容易漏掉 | 低（已有守卫）；应让假内核 `open()` 默认发一次 `buffering=false` 以逼近真实 |
| H18 点播 `duration` 一到 seek 就会被接受 | HLS 档位重载修前每组 1/5 丢 seek（Android）；Windows 不丢（平台/硬解相关） | `engine_test.dart:~150-176`（普通 open 后 `emitDuration` 立刻断言 `lastSeek`）；`cutover_engine_test.dart:185`（影子 open 后 seek）：普通 open/cutover 路径没有 `_variantLanded` 保护；**已补贴合真机的单测**：`engine_seek_drop_test.dart` :179 H18（丢弃 + 校验重发），旧用例保留 | **高**：HLS 首次 open 续播与 HLS cutover 未真机核对（H20、H50） |
| H19 RESTART（≈23ms）一到 seek 就被接受 | RT5 仍 5/280 失败；加回声校验 + 重发后 RT6 279/280 | `resume_readiness_test.dart:29-46`（`_LoadingKernel.land()` 之后 seek 必成功）、`first_frame_engine_test.dart:223-262`；已补：`engine_seek_drop_test.dart` :92 H19（落地后仍被丢），旧 `_LoadingKernel` 用例保留 | 中：重发兜底已覆盖，但 `_LoadingKernel` 过于乐观，丢不到「落地后仍丢」 |
| H16/H19 seek 被丢后内核仍会回声目标位置 | 被丢弃时只回声旧位置（23ms），位置监听抑制它，`_lastPosition` 停在自己写的目标，误判已落地（ad950c0 修） | 修复后补了回归 `engine_test.dart:292`；其余 `emitPosition` 编排仍默认「目标先回声」；已补：`engine_seek_drop_test.dart` :382（乐观目标不被旧回声盖掉），旧用例保留 | 低 |
| H26 续播自身造成的缓冲不会被 ABR 当成卡顿 | RT3 38/38 失败样本夹 `MovaAbrDownShift`；cb7c3ba 加 `_abrHold` | `engine_test.dart:352,407` 已补；**用户 seek 引起的缓冲**仍只靠「没人 emit buffering」成立 | 中（H26 后半未核对） |
| H42 B 唤醒靠 size/RESTART 落地 | Android 15/15、Windows 18/18 走 `grace`，`elapsed` 恒等于 `resumeTimeout` | `engine_keep_alive_wake_test.dart:21-34`（`emitSize` 落地）、`:44-53`、`:69-79`；`fake_kernel.dart:410,435`（`exitRestartsVideo` 默认 true）；已补：`engine_keep_alive_silent_wake_test.dart`（`wakeSignal` 默认 `none` 的静默唤醒 6 条），旧 `emitSize`/`emitRestart` 用例保留 | **高（对外数据）**：单测全绿但 `MovaKeepAliveResume.elapsed/signal` 在真机上不可信；产品语义未改（单测侧已补贴合真机的用例；`elapsed/signal` 的对外语义仍待产品决策） |
| H43 待机期间冻结最后一帧 | Android 纯黑；Windows 冻结 | UI 封面测试按「冻帧盖封面」设计 | 低 |
| H12 `size` 成对原子上报 | 真机出现 `640×0` 半更新 | `fake_kernel.dart:242 emitSize` 原子；`engine_test.dart:787` | 中：全屏方向短暂选错的影响未核对 |
| H37 二次 dispose 安全（假内核幂等） | 真实 `Player.dispose` 第二次抛 | `fake_kernel.dart:170-180`（关已关 controller 不抛）；`engine_test.dart:1584` 已补引擎层；已补：`engine_streams_test.dart` :190,:245 + FakeKernel `throwWhenDisposed` | 低（引擎已防），内核层仍非幂等 |
| H5 一次加载一个 RESTART | HLS 切档 2–4 个，位置≈23ms 重复 | `resume_readiness_test.dart:41-45`、`first_frame_engine_test.dart:80` | 低（闸门只认第一个） |
| H77 事件与 state 同步一致 | cutover 代理分两条订阅转发，载荷与 state 可相差一拍 | `cutover_engine_test.dart:49,64`（`FakeMovaApi` 同步） | 低（P3） |
| H66 合法证书都能通过校验 | IP SAN 证书被 Android mbedtls 拒（5/5、6/6） | `mpv_kernel_tls_test.dart` 只验证属性写入，没有证书语义 | 低（README 待写限制）；根因归到 mbedtls 3.4 是 results 终审凭记忆、未核源码，待确认 |
| （文档类）旧版「PiP 退出后 `state.pip` 不复位」 | 现行 Android 展开/点 X 均复位（已修） | `CLAUDE.md「剩余任务」①` | 已修正（2026-10-28 CLAUDE.md「剩余任务」① 已改写为已修复） |
| （验证脚本类）V6「VOD 卡顿重试后从头播放」 | Android 为验证脚本缺陷（`log.indexOf` 用对象恒 −1），修后 5/5；Windows 10-24 的同一结论很可能同源，未复测 | `resume_readiness_test.dart`（其数据源自 Windows 旧结论） | 中：Windows 需复跑 V6（H35） |
**2026-10-28 补记**：H16/H18/H19/H37/H42 已补贴合真机的单测（FakeKernel 新增可选行为，默认值与旧用例不变），上表“旧影子”保留作历史；真机侧这些假设的状态本轮没变（用例见各行与 §5.2.5，未上机）。


### 4.2 存疑 / 未核对（按风险排序，建议优先补测）

1. **H28 默认配置（无 RESTART 泵）下的档位落地信号**：F3/A17 的 280 次真机复测全是 `preciseFirstFrame:true`；宿主默认用 `createMovaEngine()`，走 `buffering` 下降沿 + 4s 兜底，**这条路径零真机数据**，而单测（`engine_test.dart:178-292`、`first_frame_engine_test.dart:223-262`）恰好全是这个模型。 **用例已写，待上机**：gap-assumptions `H28.{default,precise}.*`。
2. **H20/H50 HLS 首次 open 后的寄存 seek（含 cutover 影子 `seek(at)`）**：A7/F4 都用 mp4；HLS 没有 `_variantLanded` 保护，只靠 duration 到达 + 最多 3 次重发。 **用例已写，待上机**：gap-assumptions `H20.hlsSeek`、`H50.hlsSeek`。
3. **H7 旧文件迟到的 END_FILE(error)** 会不会算到新 open 头上：V4 只测了 RESTART。 **用例已写，待上机**：gap-assumptions `H7.lateError`。
4. **H14/H26 用户 seek / 暂停态 seek 的 `buffering` 边沿**：media_kit 的 `buffering` 含 `core-idle`，seek 时会翻转；ABR 无时间窗、默认开启、阈值 3；手选非自动档后连续 seek 可能误降档。 **用例已写，待上机**：gap-assumptions `H14.manualSeek`。
5. **H17 落点偏差 >500ms 时位置回声被永久抑制**（进度冻结）：长 GOP/片段边界没测。 **用例已写，待上机**：gap-assumptions `H17.{mp4,m3u8}`（偏差未超则 BLOCKED）。
6. **H33 `kernel.open()` 对坏地址是否抛**：CLAUDE「广告编排」称走 openThrew，HE/R 实测「404/拒连 `open()` 不抛」，两处记录矛盾。 **用例已写，待上机**：gap-assumptions `H33.*`（记录型）。
7. **H42 的产品面**：`resuming` 阶段 5s、`MovaKeepAliveResume.elapsed` 恒等超时值，属于「测试替身与真机语义分叉但仍绿」。 单测侧已补静默唤醒用例（`engine_keep_alive_silent_wake_test.dart`）；真机 gap-lifecycle `H42.wake`（待上机）。
8. **H12 半更新尺寸 → 全屏方向抖动**、**H53/H54 外部改音量/亮度不同步**、**H56 A15/F5 修后复测只覆盖专项**（retest.md:134–135 仅 MiniHost→PiP 衔接流程 PASS，整项其余子条件未重跑）、**H37 修后复测只覆盖专项**（retest.md:136 仅重复 dispose 4/4）。 H56/H37 修后复测的用例已写：gap-lifecycle `A15.miniPip`、`H37.dispose`（待上机）。
9. **文档与代码不一致（2026-10-28 已处理）**：`doc/SPEC.md` 清晰度节已按代码（按档位 URL 重开）改写（H30）；`CLAUDE.md` 的「PiP 退出不复位」段已改为已修复；`plans/*retest*` 的 RT6 实为 rerun7 仍如旧。

### 4.3 假内核「默认就做了、但真实 mpv 不一定做」的隐含行为

| 隐含行为 | 假内核 | 真实 | H |
|---|---|---|---|
| `open()` 后无任何自发事件 | 是 | 先发 playing/completed/position0/duration0/buffering/buffer 归零，再 START_FILE 后 buffering=true、playing=true | H1 |
| `play()/pause()` 不发 `playing` | 是（靠 `emitPlaying`） | 调用时同步发 | H13 |
| `seek()` 必被接受、不回声、立即返回 | 是（现可选开 `echoSeeks`/`dropNextSeeks`/`staleEcho` 复现回声与丢弃，默认仍不回声） | 可被静默丢弃（HLS 重载初始化期、加载中）；挂起期间回声目标位置；返回 17–600ms 且不代表落地；所有命令串行（lock） | H16/H18/H19/H22/H23 |
| `duration` 一次发出、不再变 | 是 | 先 0 后实值，seek/重载后微调（40000→40007） | H11 |
| `size` 宽高成对 | 是 | 两路独立，半更新 `640×0` | H12 |
| `pause()` 不引发 buffering | 无 buffering 概念 | 靠一次性标志吞 core-idle；seek 无此保护 | H14 |
| `exitKeepAlive(muted)` 必带「重新出画」信号 | 默认 `exitRestartsVideo=true`；`wakeSignal` 默认 `none`＝真机行为（`exitRestartsVideo` 旧路径保留） | 恒 `grace` | H42 |
| `inspectKeepAlive()` 立即返回、默认 `present` | `KeepAliveKernelStub` 默认 `present/flv`；`MovaTestKernel` 默认 `unknown` | 首帧后约 2.1–2.4s 才 `present`；EOF 后 tracks 清空 → `unknown` | H10/H40 |
| `dispose()` 幂等、立即完成 | 是（可选 `throwWhenDisposed` 复现二次抛，`callsAfterDispose` 记录销毁后调用） | 二次抛；未挂 `VideoController` 可卡；5s 后才真正销毁 | H36/H37/H38 |
| `renderHandle` 恒为固定对象 | 是 | 首次读取才创建 `VideoController`（带 `vid=auto` 副作用） | H52 |
| `nativeRestartAvailable` 默认 false | 是（两假体一致） | release 且开泵时为 true；debug 走 100ms 轮询 | H3/H28/H68 |
| `sample()` 返回 null / 手设快照 | 是 | 7 个属性各自可能不可用 | H74 |
| `error` 流原样透传 | 是 | 过滤两行 "Cannot seek"；`stream.error` 丢 prefix（所以另走 `logs`） | H31/H32 |
| 平台端口：PiP 永远 true / 音量亮度原样记录 | `YesPip`/`_RecordingVolumePort`/`_RecordingBrightPort` | 离散量化、异常兜底 1.0、配置变更后延迟翻转 | H53/H54/H55 |

### 4.4 结构性建议：补「同一套契约跑在两个内核上」的用例

现状：`kernel_contract_test.dart` 测的是假体自己，不是对真实内核的契约测试；② 档的绝大多数 H 条目（事件时序、seek 回声、属性读回、dispose）本质上是「假内核与 `MovaMpvKernel` 行为分叉」。建议加一组**契约用例**，同一份断言同时跑在 `FakeKernel` 与 `MovaMpvKernel`（真机/桌面 libmpv）上，至少覆盖：`open` 后的归零事件序列（H1）、`play/pause` 同步发 `playing`（H13）、`seek` 的回声与丢弃（H16/H19）、`dispose` 幂等（H37）、`size` 成对上报（H12）、`sample()` 属性可用性（H74）。分叉处要么改假内核贴近真实（如让假内核 `open()` 默认发一次 `buffering=false`、让 `exitKeepAlive` 默认走 `grace`），要么在契约用例里显式标注「已知分叉」。建议落点：`test/core/kernel_contract_test.dart` 扩成参数化契约 + `example/lib/verify_auto/` 里一个跑真内核的入口（新页，不与其他 spike 混用）。 **进展（2026-10-28）**：FakeKernel 已加可选行为（`echoSeeks`/`dropNextSeeks`/`staleEcho`、`KeepAliveKernelStub.wakeSignal`、`throwWhenDisposed`），H16/H18/H19/H37/H42 的单测已贴合真机；参数化契约用例（同一份断言同时跑 FakeKernel 与 `MovaMpvKernel`）仍未做。

### 4.5 完整清单 H1–H78（按类别）

#### 事件序列（H1 H2 H3 H4 H5 H6 H7 H8 H9 H10 H11 H12 H13 H14 H15）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H1 | `open()` 之后内核不会自发推任何事件，状态归零全由引擎自己做 | 已核对 | （Android）：R E1/F1 真实序列 `open 清理 Pause/Duration(0)/Size(0) → Play → SourceChange → Ready → Duration/Size → FirstFrame(restart)`；A5/N12 实测 open 后 state 为异步归零 | 订阅 events+states，对同一 `open` 记录事件到达序与每条事件时刻的 `engine.state`（CALL/EVENT/STATE 三联日志），N≥5，release | 假体：`test/support/fake_kernel.dart:126-135`、`lib/src/testing/test_kernel.dart:138-144`：open 只记 `calls`/`lastUri`。真实 media_kit 在 `open()` 内部先发 playing/completed/position 0/duration 0/buffering false/buffer 0（`real.dart:254-312`），START_FILE 后再发 playing true+buffering true（`real.dart:1470-1485`）｜单测：`first_frame_engine_test.dart:34` open() zeroes rendered…；`engine_test.dart:~160` opening a new source forgets the previous media duration｜产品：`engine.dart:1291-1305`（open 同步归零 duration/rendered/size）、`engine.dart:1287` `_forgetMediaProgress` | A5-②、E.MovaReady-②、E.MovaFirstFrame-②、E1-②、F1-②、N12-② |
| H2 | open 后内核先发的那次 `buffering=false` 不是首帧 | **已证伪** | （旧假设，Android 2026-09-30）：旧 TTFF 在失败源 75ms 就报首帧；已改为下降沿 + `onProgress` 连续两个递增样本兜底。现行逻辑 HE V1 precise=false 5/5 `signal=buffering`（R 批次 4） | 回归即可：precise=false 下 open 一个 404 源，断言 `rendered` 保持 false、无 `MovaFirstFrame` | 假体：`FakeKernel` 不发这个初始 false；旧实现把"首个 false"当首帧。现有测试显式补了这条反例｜单测：`first_frame_engine_test.dart:110` only an initial buffering=false does not render；`report/ttff_test.dart:36`｜产品：`render/first_frame.dart:100-109`（只认 true→false 下降沿）、`report/ttff.dart` | F7-②、N12-②、N23-② |
| H3 | `buffering` 下降沿比原生 RESTART 早约 200ms，可作为"首帧已出画"的兜底落地信号 | 部分核对 | ：Windows buffering 比 restart 早 0.46–0.52s（HE V1）；CLAUDE 2026-09-30 称早约 200ms（612 vs 809ms）；**Android release V1 并不支持"更早"**：precise=false 的 sinceOpen=[2894,2528,6258,2529,2752] vs precise=true=[2097,2552,2681,2861,2608]（R 批次 4，各为独立 open，量级相当，有一次晚 3.5s）。结论只能是"同量级、不保证先后" | 同一次 open 同时记录 `buffering` 下降沿时刻与（独立弱客户端或 precise=true 的）RESTART 时刻，两者差值取 N≥20，Android release；分别 mp4 / HLS | 假体：`MovaTestKernel`/`FakeKernel` 默认 `nativeRestartAvailable=false`，测试里 `emitBuffering(true)`→`emitBuffering(false)` 即落地：`keep_alive_rig.dart:123-127 land()`｜单测：`first_frame_engine_test.dart:97` plain kernel: buffering true to false lands as buffering；`engine_test.dart:178`/`230`（用 buffering 沿当"档位落地"）｜产品：`first_frame.dart:100-109,163-169`、`engine.dart:683-690,950-960` | E.MovaFirstFrame-②、F7-②、N12-②、N23-②；he_auto:V1 |
| H4 | 暂停态（`autoPlay:false`）open 也会收到 RESTART，所以暂停态不必靠尺寸兜底 | 已核对 | （Android+Windows）：V2 Android 5/5 `signal=restart`（2403–2654ms）；Windows 3/3。尺寸兜底分支在真机从未被走到 | 无需新增；可在 HLS 暂停态 open 补 N≥5 确认 | 假体：假体按需 `emitRestart`；测试里暂停态用 `emitSize` 落地｜单测：`first_frame_engine_test.dart:137` size lands only for a paused open｜产品：`first_frame.dart:126-134`、`engine.dart:917-929` | E.MovaFirstFrame-②、F7-②、N12-② |
| H5 | 一次加载只对应一个 RESTART（open 1 个，每次 seek 再 +1 个） | **已证伪** | （Android，HLS 切档）：同一次档位重载观察到 2–4 个 RESTART 且位置重复为 23ms（RT3/RT4 失败时间线 `[23,23,23,8623]`）。debug 下 open=1、open+seek=2 已核对（CLAUDE） | 对 HLS 切档记录 RESTART 序列（时刻、位置、path），统计"首个 RESTART 之后是否还有位置≈0 的 RESTART" | 假体：`FakeStatsKernel.emitRestart()`、`_LoadingKernel.land()`（`resume_readiness_test.dart:41-45`）：一次 land 一个 RESTART｜单测：`first_frame_engine_test.dart:80` restart within the grace window wins；`resume_readiness_test.dart:74`｜产品：`mpv_event_pump.dart:175-178`（每个 RESTART 都转发）、`engine.dart:762-768` | A17-②、E.MovaFirstFrame-②、F3-②、F14-②、N12-② |
| H6 | 旧文件在 `open(B)` 之后迟到的 RESTART 不会被当成 B 的首帧 | 部分核对 | ：HE V4 Android 20/20（seek→open 间隔 10–50ms，B.sinceOpen 最小 2105ms，tooEarly=0）。只覆盖播放态、间隔≤50ms；暂停态/HLS/更大间隔窗口未测 | 暂停态与 HLS 各 N≥20，open(A) 后 seek，再以 0–300ms 间隔 open(B)，断言 B 首帧 sinceOpen 不小于其加载最短耗时 | 假体：假体无此竞态；靠 `_kernelOpening` 计数忽略 open 在途期间的观测｜单测：`first_frame_engine_test.dart:171` observations are dropped while the kernel open() is in flight；`ad_stale_first_frame_test.dart`｜产品：`engine.dart:950-960 _feedGate`、`engine.dart:871-931` | E.MovaFirstFrame-②、F7-②、N12-② |
| H7 | 旧文件的 END_FILE(error) 不会在 `open(B)` 之后迟到并被算成 B 这次尝试的失败 | **未核对** | （V4 只测了 RESTART，没测 END_FILE）：mpv 的 END_FILE 事件不带文件身份，只有 `_kernelOpening`/`_attemptId` 在 Dart 侧去重 | A=404/拒连源，紧接 `open(B=好源)`，间隔 0/20/50/100/200ms，N≥20；断言 B 无 `MovaPlayFailure`；另做 A=hang 被 B 替换，记录 END_FILE reason（期望 `stop` 而非 `error`）。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H7.lateError（旧请求被取消、无迟到错误则 BLOCKED） | 假体：`FakeStatsKernel.emitEndFile()` 的时机完全由测试决定，不含"事件无文件标识"的竞态｜单测：`recovery_fixes_test.dart:109,131,149`（加载在途收到 END_FILE 的归属）｜产品：`engine.dart:770-775`、`engine.dart:899-904`、`engine.dart:1379-1409,1409` | E.MovaPlayFailure-②、F8-②、N5-②、N6-② |
| H8 | 坏地址由 mpv 以 END_FILE(error) 秒判（404≈几十 ms、拒连≈几 ms），Dart 看门狗只是兜底 | 已核对 | （Android+Windows，**平台不同**）：Android 404≈97–120ms、拒连≈79–111ms（V8 5/5）；Windows 404≈40ms、拒连≈5.07s；hang 源由 mpv `network-timeout` 在 ≈5.27s（均值 5270.7ms）先于 Dart 65s 兜底结束（N1）。把"拒连秒判"当通用结论会在 Windows 上错 | Android 已足；新增机型/Android 13+ 时复跑 V8（拒连/404/hang 各 N≥5）即可 | 假体：`FakeStatsKernel.emitEndFile(error)` 想发就发；`engine_recovery_test.dart` 以 `emitEndFile` 即时触发｜单测：`engine_recovery_test.dart:77~`（nativeEndError 路径）；`recovery_fixes_test.dart:109`｜产品：`engine.dart:770-775`、`recovery/watchdog.dart`（兜底） | A5-②、C14-②、E.MovaPlayFailure-②、F8-②、N1-②、N5-②；he_auto:V8 |
| H9 | `--keep-open=yes` 下自然 EOF 不发 END_FILE(eof)，完播只靠 `completed=true`（同时 `playing=false`、`buffering=false`） | 已核对 | （Android）：batch1-playlist 自然 MovaDone 1 次；QoE ended/truncated 通过（R E.MovaDone、F7） | 已够；补一次"EOF 后 `play()` 重播"见 H25 | 假体：`FakeKernel.emitCompleted(true)` 只置 completed；`MovaEndFileReason` 无 eof（`stats_probe.dart:84-119`）；真实见 `real.dart:1943-1975`（eof-reached 属性驱动）｜单测：`playlist_test.dart`（自然完播连播）；`report/truncation_test.dart:72-79`｜产品：`engine.dart:691-703`、`collector.dart:590-595` | A28-②、E.MovaDone-②、F7-② |
| H10 | EOF 之后 track-list/`audio-params` 仍可读，依赖轨道表的判断（保活音频判定、`_onTracks` 格式探测）不受影响 | **未核对** | （源码推断，无真机数据）：直播 FLV 到 EOF 后请求保活会得到 `unknown`→`fallback(mediaUnknown)`，符合保守设计，但没有被观察过 | 直播流播到服务端断流（EOF），读 `inspectKeepAlive()` 与 `track-list`，再 `setKeepAlive(true)`，记录阶段/原因 | 假体：`KeepAliveKernelStub.media` 恒返回 `present/flv`（`fake_kernel.dart:400,417-421`）；真实 media_kit 在 `eof-reached` 时把 `tracks`/`track` 重置为空（`real.dart:1957-1971`）｜单测：`engine_keep_alive_enter_test.dart:24,53`（audio present / unknown 编排）｜产品：`mpv_kernel.dart:979-993 inspectKeepAlive`、`keep_alive_kernel.dart:84-96`（tracks 空→unknown） | A25-②、F6-② |
| H11 | VOD `duration` 先 0 后一个稳定实值，之后不再变化 | 部分核对 | （Android）：真机时间线里 duration 40000→40007（seek/重载后微调，RT3/RT5 失败时间线 `MovaDurationChange 40007`）；VOD 微调会多发 `MovaDurationChange` 与 state，下游（进度条/续播钳位）容忍度没有专项核对 | 点播 mp4/HLS 各 N≥10：记录 duration 序列（含 seek 后），检查 `_applyParkedSeek` 钳位与进度条总长是否闪动 | 假体：`FakeKernel.emitDuration` 只发测试给的值，一次一值｜单测：`engine_test.dart:~150`（duration 到达补发 seek）；`first_frame_engine_test.dart:236`｜产品：`engine.dart:733-740 _durationSub`、`engine.dart:853-858 _isDurationJitter`（只节流直播） | A2-②、E.MovaDurationChange-② |
| H12 | `size` 事件宽高成对原子上报 | **已证伪** | （Android）：真机出现半更新 `MovaSizeChange{width:640,height:0}`（R E.MovaSizeChange：batch15-abr 7 次中 1 次与 state 不符；终审指向 `mpv_kernel.dart:169-178`）。对全屏方向（`preferredOrientationsFor(0,h)` 会选竖屏）的实际影响**未核对** | 全屏态下切换到另一分辨率的源，记录 `MovaSizeChange` 序列与 `OrientationPort.apply` 入参、`dumpsys window` 方向抖动，N≥10 | 假体：`FakeKernel.emitSize(w,h)`（`fake_kernel.dart:242`）原子；真实 `MovaMpvKernel` 由 width/height 两路独立流合成（`mpv_kernel.dart:169-176,605-608`），只保证"两路都见过一次之后"才发｜单测：`engine_test.dart:787` setFullscreen re-applies orientation when size arrives later；`first_frame_engine_test.dart:137`｜产品：`engine.dart:741-756`、`engine.dart:2246-2254`（全屏下按 state 宽高选方向）、`render/first_frame.dart:129-134`（要求两者>0，不受影响） | A2-②、A14-②、A16-②、E.MovaSizeChange-② |
| H13 | `play()/pause()` 由内核在调用时同步发 `playing` 事件；`MovaPlay` 早于 Ready/FirstFrame | 已核对 | （Android）：E1 真实序列 Play 在 Ready/FirstFrame 之前；矩阵已按此修订。`MovaState.playing` 在文件未加载时已为 true 的窗口，守卫/保活读的是 `playbackIntent` 而非它 | 已核对；若要核"内核 pause 属性 vs state.playing 不一致窗口"，在 `open→立即 pause` 竞态里读 `pause` 属性与 state 对账，N≥20 | 假体：`FakeKernel.play()/pause()` 不发 `playing`（`fake_kernel.dart:138-145`），测试靠 `emitPlaying`；真实 media_kit 在 `play()/pause()` 一进来就同步 `state.playing` 并推流（`real.dart:355-377,395-410`）｜单测：`engine_recovery_test.dart:219`（暂停停表）；`keep_alive_rig.dart:100 playLive` 手推 `emitPlaying(true)`｜产品：`engine.dart:679-682`、`engine.dart:1828-1880` | A6-②、E.MovaReady-②、E.MovaPlay-②、E.MovaPause-②、E1-②、F1-② |
| H14 | `pause()` 不引发 `buffering(true)`；暂停态 seek 的 core-idle 抖动也不会被当成卡顿 | **未核对** | （只有间接：QoE 限速流真 rebuffer 3 次；暂停态 60/60 续播通过）。没有"播放中 pause/resume ×N、暂停态 seek ×N 时 buffering 事件数"的直接记录 | 播放中 `pause()`/`play()` 交替 50 次、暂停态 `seek` 20 次，记录 `buffering` 与原生 `core-idle`/`paused-for-cache` 序列；期望用户操作不产生 `paused-for-cache=yes`。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H14.manualSeek（手选非自动档后连续 6 次 seek，播放/暂停各一；buffering 上升沿 <3 记 BLOCKED） | 假体：`FakeKernel` 的 buffering 只按测试发；真实 `buffering` 是 `core-idle` 与 `paused-for-cache` 的合并，`pause()` 靠 `isBufferingStateChangeAllowed=false` 吞掉**一次** core-idle（`real.dart:1517-1535,2682-2685`），seek 没有这层保护｜单测：`engine_recovery_test.dart:219` 7. pausing during a stall stops the stall clock；`engine_keep_alive_rules_test.dart:211`｜产品：`engine.dart:683-690`（buffering 同时喂 ABR/看门狗/首帧闸门）、`recovery/watchdog.dart:125-129` | A6-②、A7-②、C4-②、E.MovaBufferChange-②、N2-② |
| H15 | `buffer`（demuxer-cache-time）语义对各类源一致，`buffer - position` 可直接当 lookahead | 部分核对 | （Android）：F4 adResume 5/5 影子预热命中就绪（mp4 内容）；弱网下 8s 内不满足→giveUp 兜底 PASS。HLS/直播源的 `buffer` 语义与点播是否同形未核对 | HLS 内容做"广告→正片"cutover，记录影子 `progress.buffer/position` 序列与 `ready` 时刻，N≥5 | 假体：`FakeMovaApi.pushProgress(MovaProg(position:…, buffer:…))`（cutover 测试里任意给值）｜单测：`cutover_engine_test.dart:262,277`；`cutover/warm_test.dart`｜产品：`cutover/warm.dart:163-182`、`cutover_engine.dart:546-588` | A24-②、F4-② |

#### seek（H16 H17 H18 H19 H20 H21 H22 H23 H24 H25）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H16 | seek 后内核先回声若干旧位置再追上；且挂起期间 mpv 会把目标值当 `time-pos` 回声 | 已核对 | （Android）：seek 精度 5 次 0ms（A7）；RT3 时间线证实"被丢弃时内核只回声起点附近 23ms"，曾因此被位置监听抑制而误判落地，ad950c0 已修（RT6 279/280） | 已够；回归用 HLS 档位切换（见 H19）即可 | 假体：`FakeKernel.seek` 不回声（`fake_kernel.dart:148-151`）；回声全靠测试 `emitPosition` 手编，如 `engine_test.dart:279-283`（先目标后 100ms）、`:311-314`（只回 23/63ms）｜单测：`engine_test.dart:261,292`（resume seek 重发）；`resume_readiness_test.dart:74`｜产品：`engine.dart:704-728`（`_pendingSeekTarget`+500ms 容差）、`engine.dart:2051-2086`｜单测（2026-10-28 补）：`engine_seek_drop_test.dart` :382（乐观目标留在屏幕上、旧位置回声被隐藏直到校验链动作；FakeKernel 新增 `echoSeeks`/`dropNextSeeks`/`staleEcho`，贴合真机的回声与丢弃） | A7-②、A17-②、F3-② |
| H17 | seek 落点与目标差 ≤ 500ms，否则位置回声被永久抑制、进度冻结 | 部分核对 | ：测试源（40s mp4/HLS，短 GOP）落点误差 0–166ms；长 GOP、HLS 片段边界、接近 EOF 的 seek 落点未测 | 造一条 GOP=10s 的点播与 6s 分片 HLS，各在 GOP 中间 seek 10 次，读回原生 `time-pos` 与 `state` 进度；判据：进度不冻结、`progress` 在 1s 内更新。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H17.{mp4,m3u8}（落点偏差未超 500ms 则 BLOCKED，长 GOP 样本需另造） | 假体：假体回声恰在目标±500ms 内（`engine_test.dart:279-283`）；"落点偏离"从未被编排｜单测：`engine_test.dart:261`｜产品：`engine.dart:498,717-721`（超出容差直接 `return`，直到下一次 seek 才解除）｜单测（2026-10-28 补）：`engine_seek_drop_test.dart` :242（被丢弃的 seek 不会让进度永久冻结）、:150（最多重发 3 次，放弃后解除回声抑制）、:352（暂停态始终被丢则放弃并跟随真实位置） | A7-②、A17-② |
| H18 | 点播 `duration` 一到，seek 就会被 mpv 接受 | **已证伪** | （Android，HLS 档位重载）：修前每组 1/5 失败，RESTART=[23,23]（R 终审 F3）；修后 15/15 落点误差 0ms。**Windows 同场景未修版 102/102 也不丢（WR）→ 平台/硬解相关**。mp4 加载中 seek（寄存→duration 到达补发）A7 7s→6999ms 已核对 | HLS 档位切换/单源重载，对比"duration 到达即发"与"等落地再发"，Android 与 Windows 各 N≥30（沿用 rerun 判据：原生 time-pos、path、pause） | 假体：`FakeKernel.seek` 无条件记录；`engine_test.dart:~150-176` 只断言"duration 到达即补发"；旧测试一度用 duration 到达即发 seek 当落地｜单测：`engine_test.dart:~150`（seek parks until duration）、`:230`（duration 先到仍须等落地）｜产品：`engine.dart:1963-1967`（`park = duration<=0 \\|\\| forcePark`）、`engine.dart:2307-2378`（`forcePark: !_variantLanded`）｜单测（2026-10-28 补）：`engine_seek_drop_test.dart` :179 H18（duration 到达时补发的寄存 seek 被丢，由校验链重发后收敛，:180） | A7-②、A17-②、F3-② |
| H19 | RESTART（位置≈23ms）一到，此刻下发的 seek 就一定被接受 | **已证伪** | （Android）：RT5 280 次中 5 次失败，失败时 RESTART=[23,23]，seek 下发在 RESTART 之后仍被丢；加"等目标回声才算落地+重发"后 RT6 279/280（暂停态补跑 60/60），唯一失败 paused/37（1 次 seek，落点后 96ms 读回 0，**原因待证**）。落地信号只是必要条件，产品靠校验重发兜底 | 对 paused/37 型失败做定向复现：暂停态 HLS 切档 N≥300，记录失败时 `seeking`/`time-pos`/`core-idle` 原生读回（+300/+1000ms 后读回，RT6 已加） | 假体：`_LoadingKernel.land()` 先 `ready=true` 再 `emitRestart()`，此后 seek 必被接受（`resume_readiness_test.dart:29-46`）；`engine_test.dart:220-227` 用 buffering 沿落地后直接断言 `lastSeek`｜单测：`first_frame_engine_test.dart:223`；`engine_test.dart:178`；`resume_readiness_test.dart:74`｜产品：`engine.dart:1006-1011 _onAttemptLanded`→`_releaseParkHold`、`engine.dart:2051-2086`（校验+最多 3 次重发）｜单测（2026-10-28 补）：`engine_seek_drop_test.dart` :92 H19（档位落地后立刻发的 seek 被丢：重发一次后收敛 :93、迟到的旧回声不进 progress :116、连丢两次第三次收敛 :132、始终丢则有限重试 :150、首次被接受则不重发 :165） | A17-②、F3-② |
| H20 | HLS 首次 open 后，在 duration 到达瞬间补发的寄存 seek 被接受（续播位置/resume 位置） | **未核对** | ：A7 的加载中寄存用 mp4（18080/vod.mp4）；F4 内容也是 mp4。HLS 初次 open 后 resume 位置没有真机样本，且与 H18 是同类风险（这条路径**没有** `_variantLanded` 保护） | HLS 源 `open` 后立刻 `seek(15s)`，N≥30；沿 RT 判据（原生 time-pos 落点±500ms、path 正确）；再做 `cutoverTo(hlsSource, at: 12s)`、`MovaFeed` 续播各 N≥10。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H20.hlsSeek | 假体：`FakeKernel.seek` 无条件接受；`_applyParkedSeek` 只在测试里 `emitDuration` 后断言 `lastSeek`｜单测：`engine_test.dart:~150`；`cutover_engine_test.dart:185`（影子 open 后 seek(at)）｜产品：`engine.dart:739,2013-2031`（`!_holdParkForLanding` 时 duration 一到就发，随后 `_armResumeVerify` 兜底）、`cutover_engine.dart:503` | A7-②、A24-②、F4-②、F8-② |
| H21 | 加载未完成时直发 seek 会让 mpv 卡死（position 永不离 0，连 dispose 也挂住），所以必须寄存 | 已核对 | （Android，历史 2026-09 STG-AL00，CLAUDE 无缝切换 Task 11）。**防回归的反向实验（解除寄存）从未复做**——危险，不建议常规做 | 不做常规回归；若要重核，只在一次性隔离设备上做，且先设 dispose 超时保护 | 假体：单测只断言"没到达内核"（`engine_test.dart:172` expect(k.calls, isEmpty)）；卡死本身无法假造｜单测：`engine_test.dart:~160-176`；`engine_test.dart:178`｜产品：`engine.dart:1276-1287,1963-1976` | A7-②、F4-② |
| H22 | `seek()` 返回只表示请求已发出；`MovaSeeked` 在命令返回后即发，并不代表落地 | 部分核对 | （Android）：KERNEL_SEEK_CALL→RETURN 实测 17ms 到 ≈600ms（RT3/RT5 时间线），且返回不等于落地（H19）。`MovaSeeked` 时刻与真实落地时刻的差没有量化；宿主若把 `MovaSeeked` 当"已到位"会受影响 | 记录 `MovaSeeked` 时刻与原生 `time-pos` 首次≈目标的时刻，差值 N≥30（mp4/HLS 各一） | 假体：`MovaKernel.seek` 契约"请求已发出"（`kernel.dart:50-57`）；`FakeKernel.seek` 立即返回｜单测：`engine_test.dart:~150`；`openness_*` 事件序列断言｜产品：`engine.dart:1977-1978,2029` | A7-②、E.MovaSeeked-② |
| H23 | 命令按序串行执行（后到的 pause/seek 排在 open 之后） | **未核对** | （源码推断；仅 dispose 挂起有真机旧证据，已由懒创建规避） | 在 `open` 慢源（黑洞/限速）尚未返回时依次调用 `pause()`、`seek()`、`dispose()`，用原生属性读回确认实际执行顺序与最终状态，N≥10 | 假体：`FakeKernel` 每个动词立即完成，`openGate` 只能让 open 挂起但不会阻塞其它动词（`fake_kernel.dart:112,131-132`）；真实 media_kit 所有命令在同一把 `lock.synchronized` 里（`real.dart:704-727`），并 `await waitForVideoControllerInitializationIfAttached`｜单测：`engine_dispose_race_test.dart:77`；`engine_test.dart:231`（`openGate` 编排）｜产品：`mpv_kernel.dart:679-724`、`engine.dart:871-931`（`_loadKernel` 后补 `pause()`） | A6-②、A7-②、A23-② |
| H24 | 暂停态 seek 被接受且保持 `pause=yes`、位置保持 | 已核对 | （Android+Windows）：RT6 暂停态 60/60（剔除 0，复读 +300/+1000ms 全部 pause=yes、位置在±500ms 内）；Windows 34/34。RT5 暂停态曾 2/60 失败（修前），RT6 的 paused/37 一例原因待证（见 H19） | 已核对；paused/37 见 H19 | 假体：`FakeKernel` 无 pause 属性概念｜单测：`first_frame_engine_test.dart:137`；`resume_readiness_test.dart`｜产品：`engine.dart:1963-1976`、`engine.dart:2362-2374` | A17-②、F3-② |
| H25 | 点播播完后 `play()`：引擎先 `seek(0)` 再 `play()`，与 media_kit 自带的"completed 时 seek(0)+playlist-pos 0"不冲突 | **未核对** | （矩阵无"播完再播"的真机用例；playlist 连播是换源不是同源重播） | 点播 mp4 播到 EOF（离 EOF 前不 seek，用自然播完）→ `play()`，记录 `completed`/`position`/RESTART 序列与最终画面，N≥5 | 假体：`FakeKernel.emitCompleted(true)` 之后 `play()` 只记 `play` 一次；真实 `Player.play()` 在 `state.completed` 时会再 seek(0) 并改 `playlist-pos`（`real.dart:373-378`），而 `seek` 返回后会把 `completed` 置 false（`real.dart:716-720`）｜单测：`engine_test.dart`（completed 后 play 断言 `seek` 在 `play` 之前）｜产品：`engine.dart:1866-1868` | A6-②、A28-② |

#### 档位/ABR（H26 H27 H28 H29 H30）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H26 | 重载/续播 seek 引起的 `buffering` 上升沿不会被 ABR 当成网络卡顿；用户 seek 同理 | **已证伪** | （Android，续播链内）：RT3 38/38 失败样本全部夹 `MovaAbrDownShift`，根因是续播自身造成的缓冲被 ABR 计成卡顿，cb7c3ba 加 `_abrHold` 后 RT5 1.79%、RT6 0.36%。**用户手动 seek 引起的缓冲仍走同一计数，未核对**（media_kit 的 `buffering` 含 `core-idle`，seek 时会翻转） | 手选 360p（非自动档）后在 VOD 上连续用户 seek 10 次（不换档），记录 `buffering` 上升沿数与是否出现 `MovaAbrDownShift`；再 HLS 本地限速组确认仍能降档（H27）。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H14.manualSeek（manifest covers_ext 含 H26） | 假体：`engine_test.dart:352,407` 用 `emitBuffering` 手编"重载自己的缓冲"；`FakeKernel.seek` 从不制造 buffering｜单测：`engine_test.dart:352` switchQuality clears the ABR stall tally；`:407` switchQuality mutes ABR…；`:656` ABR downshifts after the configured number of stalls｜产品：`engine.dart:2753-2772`、`options/abr_config.dart:46-70`（无时间窗的上升沿计数，默认 `enabled=true`、阈值 3，仅非自动档会降）、`engine.dart:962-980 _abrHold` | A17-②、C4-②、E.MovaAbrDownShift-②、F3-② |
| H27 | `_abrHold` 在续播校验结束/10s 兜底后解除，真实弱网下仍能降档（没有被永久屏蔽） | 已核对 | （Android）：RT6 弱网组两项各 10/10 成功降档（自动档 3.6–5.2s；手动换档后 8.5–16.2s，未见被永久屏蔽）。遗留：自动弱网组销毁期 `[Player] has been disposed` UNCAUGHT（堆栈在 media_kit，未深查） | 已够；UNCAUGHT 另查 | 假体：`engine_test.dart:352` 用 `emitBuffering` 手编"攒够 3 次后降档"｜单测：`engine_test.dart:352,656`｜产品：`engine.dart:962-980,2051-2086` | A17-②、C4-②、E.MovaAbrDownShift-②、F3-② |
| H28 | **默认配置（无原生泵）下**，档位重载的"落地"信号 = `buffering` 下降沿，足以保证随后的续播 seek 被接受 | **未核对** | ：F3/A17 的所有真机复测都开了 `preciseFirstFrame:true`（先决事实 1）。默认配置下 buffering 下降沿相对 mpv 真正可 seek 的时刻谁先谁后，没有数据；它与 H19 同类，且还多一重"4s 兜底" | 同一 HLS、同一判据（RT 页），把引擎换成默认 `createMovaEngine()`（不开泵），Android release 切档 N≥100（normal/paused 各半），旁路原生 RESTART/time-pos 读回做对账。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H28.{default,precise}.{playing,paused,cutover}（默认/精确首帧两组，逐次打印全部样本） | 假体：`engine_test.dart:178-259` 与 `first_frame_engine_test.dart:223-262` 全用 plain `FakeKernel` + `emitBuffering(true/false)` 当落地；`MovaTestKernel` 默认同（`test_kernel.dart:35`）｜单测：`engine_test.dart:178,230,261,292`；`first_frame_engine_test.dart:223,236,249`｜产品：`first_frame.dart:100-109,163-169`、`engine.dart:1006-1011`、`wiring.dart:206-221`（`preciseFirstFrame=false`、无 reporter/recovery 时不建泵） | A17-②、F3-②、N12-② |
| H29 | Dart 侧拉取并解析的 master.m3u8 档位列表与 mpv 实际使用的变体一致 | 部分核对 | （Android）：QualityListChange `自动/360p/180p`（R E.MovaQualityListChange）；自动档下 mpv 原生 ABR 实际选了哪档与 `state.currentQuality` 的一致性、带自定义请求头的源 Dart 拉取是否 403 未核对 | 带 Referer/Token 头的 HLS 源：对比 Dart 拉取结果与 mpv `current-tracks/video` 实际变体；自动档下读原生 `video-params` 对账 | 假体：`FakeHttpFetch` 返回固定 m3u8 文本（`engine_test.dart` 内 `_FakeHttpFetch`）｜单测：`review_regression_test.dart:221` stale quality response is discarded；`engine_test.dart`（loadQualities）｜产品：`engine.dart:2257-2291`（Dart 自己 `GET master`，不带 mpv 的请求头/按源选项） | A17-②、C17-② |
| H30 | `switchQuality` = 重开变体 URL，而非 media_kit 同会话 track 切换 | 已核对 | （Android，事实）：F3 时间线显示重载 `duration 0→40000→40007`、`QualityChange` 在 open 命令发出后即发。**文档问题**：SPEC 清晰度节与代码不符，应改 | 无需真机；改 SPEC | 假体：SPEC `doc/SPEC.md:158-170` 写的是 `MovaKernel.videoTracks/setVideoTrack` 同会话切换（代码里已无这两个成员，`grep` 无命中）｜单测：—｜产品：`engine.dart:2307-2378`（`_loadKernel(playUri)`） | A17-② |

#### 错误/恢复（H31 H32 H33 H34 H35）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H31 | mpv error 级日志的 prefix 取值落在 `stream/file/ffmpeg/vd/ad/cplayer`，分类表据此判定致命性 | 部分核对 | （Android）：失败源 `failed`（`error` fatal、`code: stream`）已核（2026-09-30）；`ffmpeg`（首帧后网络错误是否可恢复）、`vd`/`ad`（解码失败）的真机 prefix 样例**未核对**（SPEC 569 明写"仍未验"） | 造 3 类故障：中途断流（ffmpeg）、不支持编码（vd/ad，瘦身 libmpv 裁剪面）、损坏片段，记录原始 `logs` prefix/level/text 与分类结果。**用例已写，待上机（部分覆盖）**：批次 gap-formats；coverage_gap:G3.2.<5 个排除格式>（prefix 只出现在 EVENT 行的错误文本里，未单独订阅 `logs`） | 假体：`FakeStatsKernel.emitLog(MovaLogLine(prefix:…))` 任意构造｜单测：`report/error_policy_test.dart`；`report/collector_test.dart`｜产品：`report/error_policy.dart:48-70`、`mpv_kernel.dart:826-828`、`collector.dart:629-660` | C13-②、E.MovaErrorEvent-②、F7-②、G3.2-③ |
| H32 | 只有"Cannot seek in this stream"与"You can force it with '--force-seekable"两行属于无害日志 | 已核对 | （Android，历史 2026-10-02，WHEP 15s `MovaErrorEvent` 0 次）；2026-10-27 覆盖 F15 因服务不可达为 BLOCKED，**未复测**。副作用：不可 seek 流上用户主动 seek 的同样提示也被吞（CLAUDE 已声明） | WHEP/裸 TS 直播各 15s + 用户 seek 一次，记录 error 流 | 假体：`mpv_defaults_test.dart` 用 `_FakePlayer` 构造日志文本｜单测：`kernel/mpv_defaults_test.dart`｜产品：`mpv_defaults.dart:53-62`、`mpv_kernel.dart:794` | A7-②、E.MovaErrorEvent-②、F15-② |
| H33 | `kernel.open()` 对坏地址是否抛异常：不确定 | **未核对** | **未核对（存疑，两处记录矛盾）**：CLAUDE「广告编排」Task 12 称"真机上坏 URL 走 openThrew（`open()` 直接失败）"；HE V8/V12、R A5/N8 实测"404/拒连 `open()` 不抛（openErrors=0），靠 END_FILE" | 分 5 类坏地址：404、拒连、DNS 失败、非法 scheme、空串/畸形 URL；各 N≥5 记录 `kernel.open` 是否抛、抛什么、END_FILE 时刻。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H33.{direct,recovery}.{404,refused,dns}（记录型，无对错判据） | 假体：`FakeKernel.openError` 想抛就抛（`fake_kernel.dart:118,133-134`），恢复单测的 `openThrew` 路径靠它；而 `FakeKernel` 默认不抛｜单测：`engine_recovery_test.dart`（openThrew）；`resume_readiness_test.dart:99-107`（`k.openError`）｜产品：`engine.dart:871-898`（`openThrew`）、`mpv_kernel.dart:709-714` | A5-②、E.MovaPlayFailure-②、F8-②、N8-② |
| H34 | 真卡顿期间 `buffering` 持续为 true，stallTimeout 能按时判定（偏差在个位 ms） | 已核对 | （Android+Windows）：V6 stallTimeout 偏差 1–13ms（Android）/0–2ms（Windows）；限速流 3 次真 rebuffer 4.8–5.3s | 已够 | 假体：`FakeKernel.emitBuffering(true)` 然后 `elapse(stallTimeout)`｜单测：`engine_recovery_test.dart:219`、`recovery/watchdog_test.dart`｜产品：`recovery/watchdog.dart:125-163`、`engine.dart:683-690` | F8-②、N19-②、N2-②；he_auto:V6 |
| H35 | 恢复（重试/切换）后，新尝试首帧落地时发出的续播 seek 被接受 | 部分核对 | ：Android V6（mp4 stall）修正验证脚本后 **5/5**，续播误差 0–40ms（R 终审；Windows 10-24 的"从头播"很可能是同一脚本假象，**Windows 未复测**）；HLS/直播恢复续播（`ready:true` 直发无校验重发）未测 | HLS 点播源注入"卡死→重试"，N≥10；原生 time-pos 对账；Windows 复跑 V6 N≥5 | 假体：`_LoadingKernel`：就绪前丢弃、就绪后接受（`resume_readiness_test.dart:30-36`）｜单测：`resume_readiness_test.dart:74`（8 条 HE V6 变体）｜产品：`engine.dart:1006-1031`（`_recoveryAwaitingFrame`→`_seekOrPark(ready:true)`） | E.MovaRecovered-②、F8-②、N19-②；he_auto:V6 |

#### dispose（H36 H37 H38）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H36 | 任意时刻（加载中/换源中/预热中）dispose 都能返回；未挂到界面的 `VideoController` 会让 `Player.dispose()` 一直等渲染面 | 已核对 | （Android+Windows）：懒创建后 E6 不挂界面 dispose 15–27ms（原 8s 超时）、E7 先播后挂 55–70ms；dispose120 120/120。**自建/注入 `VideoController` 而不挂 UI 的内核仍会卡**（README 已注明） | 已够 | 假体：`FakeKernel.dispose` 关流后立刻完成（`fake_kernel.dart:170-180`），不存在"等渲染面"；真实 `Player.dispose` 还要 `await waitForVideoControllerInitializationIfAttached`（`real.dart:89-110`）｜单测：`engine_dispose_race_test.dart:77-135`；`kernel/mpv_kernel_video_test.dart:178`｜产品：`mpv_kernel.dart:750-770`、`mpv_kernel.dart:797-800`（懒创建）、`wiring.dart:212-216`（`lazyVideo:true`） | A23-②、F13-②、N13-② |
| H37 | 二次 `dispose()` 是安全的（`FakeKernel` 幂等） | **已证伪** | （Android，旧假设）：RR/R A23 两实现第二次均抛；引擎层已加早退，**修后 Windows 4/4 通过（WR），Android 修后未复测**；内核层二次 dispose 仍抛 | Android 复跑 batch15-basic 的 A23.doubleDispose（普通+cutover 各 N≥5）；另直接对 `MovaMpvKernel` 二次 dispose。**用例已写，待上机**：批次 gap-lifecycle；coverage_gap:H37.dispose（二次 dispose 无异常） | 假体：`FakeKernel.dispose` 重复调用无害（关已关的 controller 不抛）；真实 `Player.dispose` 第二次抛 `AssertionError('[Player] has been disposed')`（`real.dart:90-93`）｜单测：`engine_test.dart:1584` dispose is idempotent…（修后补的）｜产品：`engine.dart:2638`（`_disposed` 早退）、`mpv_kernel.dart:750-770`（内核本身仍非幂等）｜单测（2026-10-28 补）：`engine_streams_test.dart` :190,:245（dispose 后全部动词可调用且不触达已销毁内核；FakeKernel 新增 `throwWhenDisposed`/`callsAfterDispose` 复现“二次抛”）、`cutover_engine_test.dart` :601 | A23-② |
| H38 | FFI 弱客户端的 destroy 与 media_kit 5 秒后才 `mpv_terminate_destroy` 之间无竞态；dispose 期间主线程不被拖死 | 已核对 | （Android release）：V7 dispose 期间最大帧间隔 62ms（<100）、120 轮创建销毁 120/120、V5 `created=14 destroyed=14` | 已够；新机型补一轮 V5/V7 | 假体：`FakeMpvEventBackend.destroy` 同步记两步日志（`fake_mpv_event_backend.dart:105-113`）｜单测：`kernel/mpv_event_pump_test.dart:175,196,525`；`mpv_kernel_events_test.dart:261` immediate dispose race loop｜产品：`mpv_event_pump.dart:127-151`、`mpv_event_backend_ffi.dart:202-229`、`mpv_kernel.dart:750-770` | A23-②、F13-②、F14-②、N13-② |

#### 属性/保活（H39 H40 H41 H42 H43 H44 H45 H46 H47 H48）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H39 | mpv `file-format` 取值：FLV=`flv`、HLS=`hls`、WHEP=`whep`；`dash` 在分片集合里 | 部分核对 | ：`flv`/`hls`（Android+Windows）、`whep`（Android 历史）已读回；`dash`、`mpegts`、`rtmp` 取值未核对（`mpegts` 点播也命中，故刻意不收进实时集合） | 对 DASH、TS 点播/直播、RTMP（若裁剪面支持）各读一次 `file-format`，记入常量表。**用例已写，待上机**：批次 gap-formats；coverage_gap:G3.2.<可支持格式>（读回 `file-format`） | 假体：`KeepAliveKernelStub.media.format='flv'`、`MovaTestKernel.fileFormat='flv'`；`plan.dart:7-11` 注释自己写"实际取值待真机确认"｜单测：`engine_keep_alive_enter_test.dart:63` hls falls back by default；`mpv_kernel_live_cache_test.dart:152-176`｜产品：`keep_alive/plan.dart:11,114-122`、`mpv_defaults.dart:70-79` | A25-②、A35-②、C15-②、F6-②、G3.2-③ |
| H40 | `audio-params` 要到首帧之后约 2.1–2.4s 才就绪，之前请求保活一律 `fallback(mediaUnknown)` | 已核对 | （Android+Windows）：S16 Android 20/20（0.5/1.0s 一律 fallback，audioPresent 距 open 2056–2456ms）；Windows 2093.7ms | 已够；注意宿主测试若用 `MovaTestKernel` 要显式 `hasAudio=true` | 假体：`KeepAliveKernelStub.media` 默认直接 `present`（`fake_kernel.dart:400`）、`inspectKeepAlive` 立即返回；`MovaTestKernel.hasAudio` 默认 null→unknown（`test_kernel.dart:77,90-99`），两个假体默认值**相反**｜单测：`engine_keep_alive_enter_test.dart:24,53`｜产品：`keep_alive_kernel.dart:84-96`、`mpv_kernel.dart:979-993` | A25-②、F6-②、N20-②；keep_alive_auto:S16 |
| H41 | `vid`/`mute` 保存→改写→原样还原；`mediacodec-copy` 下 `vid` 切回能出画且无 `Could not open codec` | 已核对 | （Android+Windows）：S7 Android `hwdec=mediacodec-copy` 20/20 视频真回来、无 codec 错误；Windows `d3d11va-copy` 20/20；`vid`/`mute` 还原 18/18、S13 5/5 | 已够 | 假体：`mpv_kernel_keep_alive_test.dart:14-60` 的 `_FakeNative.getProperty/setProperty` 读回=写入；`KeepAliveKernelStub.exit` 返回 `was==muted && exitRestartsVideo`｜单测：`kernel/mpv_kernel_keep_alive_test.dart:173,180,203`｜产品：`mpv_kernel.dart:996-1057`、`mpv_kernel.dart:537-551`（`_prepareVideo`：运行期读到 no 时先写 no 再写 auto） | A25-②、F6-②、N11-②、N20-②；keep_alive_auto:S7 |
| H42 | B 模式唤醒（`vid` 切回）后会出现 RESTART 或尺寸变化，resume 闸门能据此落地 | **已证伪** | （Android+Windows）：Android 15/15 `grace`、0/15 `size`/`restart`，`MovaKeepAliveResume.elapsed`≈5000ms 恒等于 `resumeTimeout`；Windows 18/18 同。真实出画（属性轮询）Android 99–199ms、Windows 0.45–3.7s。仅"重载路径"（S13）`size` 落地 204–247ms | 已定论；若要改产品：试 `video-out-params/w`/`video-reconfig`/新帧计数作为真实信号，在 Android 对账 N≥20。**用例已写，待上机**：批次 gap-lifecycle；coverage_gap:H42.wake（打印全部 signal/elapsed 样本与均值） | 假体：`engine_keep_alive_wake_test.dart:21-34` 用 `emitSize(1280,720)` 落地、`:69-79` 用 `emitRestart` 落地；`KeepAliveKernelStub.exitRestartsVideo` 默认 true（`fake_kernel.dart:410`）｜单测：`engine_keep_alive_wake_test.dart:21,44,69,87`；`engine_keep_alive_rules_test.dart:107,124`｜产品：`engine.dart:1767-1811`、`first_frame.dart:129-134`｜单测（2026-10-28 补）：`engine_keep_alive_silent_wake_test.dart` :39,:61,:78,:93,:107,:122（`KeepAliveKernelStub.wakeSignal` 默认 `none`＝真机恒 grace；`size`/`restart` 为另两条路径） | A25-②、E.MovaKeepAliveResume-②、F6-②、N20-②；计划 standby-mode.md、keep_alive_auto:S1 |
| H43 | `vid=no` 的待机期间画面保持冻结最后一帧 | **已证伪** | （Android）：S14 Android 截图 holding 两张均为**纯黑**，Windows 才是冻结帧（R 批次 8/9）。封面覆盖在 Android 上是"黑→封面"而非"冻帧→封面" | 已定论；UI 层封面淡入淡出时序在 Android 上目测一次。**用例已写，待上机**：批次 gap-lifecycle；coverage_gap:H42.wake（待机前/待机 PNG 对出图，黑屏/冻帧人工判，未判图 BLOCKED） | 假体：`FakeKernel` 无画面概念；封面"瞬间盖上"逻辑（`MovaPlayer`）按 Windows 观察设计｜单测：`ui/player_test.dart`（待机封面覆盖）｜产品：`ui/player.dart`（待机封面）、`mpv_kernel.dart:1010-1011` | A25-②、F6-②、N15-③、N20-②；keep_alive_auto:S14 |
| H44 | 对无声流强制 B（`vid=no`）会 EOF 并触发 recovery 重载，所以必须靠 `audio=absent` 拦截 | 已核对 | （Android+Windows）：S6 Android 5/5、Windows 3/3：强制 B 后 position 回 0、`MovaDone→PlayFailure(liveEnded)→重载`；`audio=absent` 判定与 decodeOnly 路径 5/5 | 已够 | 假体：`KeepAliveStub.enterResult` 永远成功；`MovaTestKernel.enterKeepAlive` 永远 true（`test_kernel.dart:102-106`）｜单测：`engine_keep_alive_enter_test.dart:39` no audio holds decodeOnly｜产品：`keep_alive/plan.dart:123-128`、`mpv_kernel.dart:996-1018` | A25-②、F6-②、N20-②；keep_alive_auto:S6 |
| H45 | 待机一段时间后唤醒，位置漂移 <1s（贴边缘） | 部分核对 | ：Android 持有 **20s** 漂移 137/681/410ms（均值 409.3，无待机对照 −10/10/16ms）；Windows **60s** 漂移 2376–2960ms 向前跳（未通过）。Android 60s 与 Windows 20s 都没测，R 明写"不能据此宣称已修复" | Android 持有 60s、Windows 持有 20s 各 N≥5，对账原生 `time-pos` 与持有时长 | 假体：假体无时钟概念；`debugClock` 跟随 fakeAsync（`keep_alive_rig.dart:50-51`）｜单测：`engine_keep_alive_wake_test.dart:109`（reloadEdge）｜产品：`engine.dart:1744-1753` | A25-②、C15-②、F6-②、N20-②；keep_alive_auto:S5 |
| H46 | `maxDuration` 到期仅 `pause()`，直播 FLV 暂停仍满速拉流（流量不省） | **未核对** | （Android）：Windows 实测暂停仍 ≈82KB/s；Android 流量/电量（S4 电量部分）未测；`keepalive-audible-and-disconnect.md` Task 1 预研"（待填）" | Android 用 `dumpsys netstats detail`/`/proc/net` 的真实流量计数（非墙钟）对 normal/B/C/pause 各 30s×3 | 假体：假体无网络层｜单测：`engine_keep_alive_enter_test.dart:135`（到期 pause 并 fallback）｜产品：`engine.dart:1606-1625` | A25-②、C15-②、F6-②、F12-③、F17-②、N20-②；keep_alive_auto:S4 |
| H47 | 预热静音与待机静音只改 mpv `mute`，不写系统 STREAM_MUSIC，任意叠加顺序都能还原 | 已核对 | （Android，属性级+系统音量）：Q13A/B/C 各 5/5，40 个 MARK 处 `STREAM_MUSIC` 恒为 6/20。**人耳听感/漏音未测**（无音频采集路径） | 属性级已够；漏音需外接录音或 `dumpsys audio` 的 `players` 状态连续采样 | 假体：`FakeWarmMuteKernel` 记录 `warmMute:on`（`warm_mute_kernel.dart:8-34`）；`_FakeNative` 读回=写入｜单测：`cutover/cutover_warm_mute_test.dart`；`mpv_kernel_keep_alive_test.dart:76-153`｜产品：`mpv_kernel.dart:937-976`、`player_mute.dart` | A24-②、F4-②、N10-②、N11-② |
| H48 | `mute` 状态下音频会话仍在（AudioTrack 存活），耗电底噪可忽略 | **未核对** | （S11 `dumpsys audio`/`batterystats` 项 Android 专属，handoff 里列为未做；R F12 只给 CPU 单核百分比，且 USB 供电不能下电量结论） | B 窗口内采 `dumpsys audio`（AudioTrack/focus）与 `batterystats --reset` 前后对比，拔 USB | 假体：假体无音频会话｜单测：—｜产品：`mpv_kernel.dart:996-1018` | F6-②、F12-③、F17-②；keep_alive_auto:S11 |

#### cutover（H49 H50 H51 H52）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H49 | 预热影子的就绪判据（position≥target−0.8s、buffer−position≥1s、连续 2 次、8s 超时）在真实源上可达 | 已核对 | （Android）：F4 adResume 5/5，首个原生 time-pos 对比误差 0ms；断网预热超时（readyTimeout=5s）与短广告降级 PASS | 已够；HLS 内容见 H15/H20 | 假体：`FakeMovaApi.pushProgress` 任意构造；`warm_test.dart` 纯函数｜单测：`cutover_engine_test.dart:262,277,429,450`；`cutover/warm_test.dart`｜产品：`cutover/warm.dart:113-189`、`cutover_engine.dart:546-588` | A24-②、C11-②、F4-② |
| H50 | 影子 `open()` 后立刻 `seek(at)`（at>0）不会被丢弃 | 部分核对 | （Android）：mp4 内容广告→正片 5/5、+42ms；**HLS 内容未测**（同 H20） | 同 H20 的 HLS cutover 组。**用例已写，待上机**：批次 gap-assumptions；coverage_gap:H50.hlsSeek | 假体：`FakeMovaApi.seek` 立即记录｜单测：`cutover_engine_test.dart:185,566`｜产品：`cutover_engine.dart:488-503`（影子是 `MovaEngine`，走寄存+重发） | A24-②、F4-② |
| H51 | 影子已缓冲时 `pause()` 后 `seek(_warmAt)` 回绕立即生效（含 `at=0`） | 已核对 | （Android）：2026-09-24 修后 +42ms；F4 5/5 误差 0ms（读取延迟 0–14ms） | 已够 | 假体：`FakeMovaApi` 同步｜单测：`cutover_engine_test.dart`（pauseWhenReady）｜产品：`cutover_engine.dart:190-194,571-574` | A24-②、F4-② |
| H52 | 读取 `renderHandle` 才创建 `VideoController`（懒创建），影子提前读一次即有画面管线；换指后画面不黑、不撕裂 | 部分核对 | （Android）：懒创建 0/0/1 与 E8 `renderEpoch 0→1`、cutover 941ms 已核对；"无黑屏/无撕裂"用 250–330ms 连拍证明（2026-09-25），**逐 ms 穷尽与音频跳变未证** | 现有手段已到顶（无 screenrecord）；可加 `adb exec-out screencap` 更高频连拍或外接采集卡 | 假体：`FakeKernel.renderHandle` 是固定 `Object`（`fake_kernel.dart:67,207`），`MovaPlayer` 单测只画占位｜单测：`kernel/mpv_kernel_video_test.dart:92-187`；`cutover_engine_test.dart:198`｜产品：`mpv_kernel.dart:797-800`、`cutover_engine.dart:451-453` | A24-②、U1-③、F4-②、N13-② |

#### 端口（H53 H54 H55 H56 H57 H58）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H53 | 系统音量端口 get/set 往返无损，`state.volume` 镜像 set 值，且不会被外部（物理音量键/其它 App）改动打乱 | 部分核对 | （Android）：0/50/100/30→系统 0/10/20/6（max=20，1% 受量化）；A8 越界已钳。**外部改动是否同步 `state.volume`（物理音量键/系统面板）未核对**（引擎只在构造期读一次种子，无监听） | `adb shell input keyevent KEYCODE_VOLUME_UP/DOWN` 后读 `state.volume` 与原生读回；设置面板改音量同测，N≥5 | 假体：`_RecordingVolumePort.get/set`（`engine_test.dart:1998-2020`）原样记录；`MovaPlugin.kt:75-95` 真实走 `round(percent/100*max)` 离散量化｜单测：`engine_test.dart:1555` setVolume routes…；volume port 种子｜产品：`engine.dart:826-837,2159-2177`、`volume_impl.dart:19-30` | A8-②、N11-②、P12-②、G2.5-③ |
| H54 | 亮度端口：`application` 读写与窗口亮度一致；`state.brightness` 默认 1.0 且不从系统/窗口亮度播种；退出播放后窗口亮度可还原 | 部分核对 | （Android）：A9 原生 `sbrt` 0/.25/.75/1 与 state 逐项一致、手势窗口 sbrt=.753；**手势基线与当前真实亮度不一致**（state 恒从 1.0 起算）与"退出后窗口亮度是否还原"未核对 | 系统亮度设 0.2 后进入播放页、竖滑一次，读 `state.brightness` 与 `settings get system screen_brightness`；退出页面后读窗口亮度 | 假体：`_RecordingBrightPort`（`engine_test.dart:2106~`）；`state.dart:248` 默认 1.0；引擎只种 `volume` 不种 `brightness`｜单测：`engine_test.dart`（brightness 手势基线）；`wiring_test.dart:38`｜产品：`engine.dart:2180-2188`、`brightness_impl.dart:11-31`（异常兜底 1.0） | A9-②、U6-③、P12-②、G2.6-③ |
| H55 | `enterPip()` 返回 true 即真进入 PiP；`state.pip` 由 `pipChanges` 回流复位（展开与点 X 两条路径）；进入 PiP 前小窗/保活先收起 | 已核对 | （Android）：`mode=pinned`、展开与点 X 均收到 `PipChange(false)`，`state.pip` 复位；X 会暂停、展开继续播（R A18/N9）。旧缺陷"退出不复位"**已证伪并修复**。同一次原生转换在 3 个存活 engine 各收 1 条，同一 engine 无重复 | 已够；多引擎并存时 PiP 归属见 H70 | 假体：`YesPip`（`keep_alive_rig.dart:9-15`）永远 true；`_ObservablePip.push(bool)`（`engine_test.dart:~1955-1985`）手推回流｜单测：`engine_test.dart:1478` state.pip follows PiP changes pushed by the port；`keep_alive_rules_test.dart:131,143`｜产品：`engine.dart:806-819,2394-2407`、`MovaPlugin.kt:43-53,104-111,121-138`（配置变更后 50/150/400/1000ms 复查 `isInPictureInPictureMode`） | A4-②、A18-②、E.MovaPipChange-②、U9-②、F5-②、F16-②、N9-②、P12-② |
| H56 | App 内小窗与系统 PiP 互斥，进入 PiP 时小窗被收起且 controller 不再 showing | **未核对** | **未核对（修后）**：RR 复跑 A15/F5 FAIL（`mini=false` 但 controller 仍 showing=true）；CLAUDE 称 2026-10-27 已修，之后只复测了 F3/A17，**A15/F5 没有 Android 修后记录** | 真实 MiniHost → `enterPip()` → 展开，读 `controller.isShowing`、`state.mini/pip`、截图，N≥5。**用例已写，待上机**：批次 gap-lifecycle；coverage_gap:A15.miniPip | 假体：`FakeMovaApi.setMini/enterPip`（`fake_api.dart:411-451`）只记调用｜单测：`engine_test.dart:1844`（setMini 不碰端口）；`keep_alive_rules_test.dart:143`｜产品：`engine.dart:2394-2407`、`ui/mini/*` | A15-②、F5-② |
| H57 | 方向端口 `apply()` 返回时方向已生效，窗口尺寸/`topPadding` 可读回；桌面端无效果 | 已核对 | （Android）：A14/A16 横屏 2266×1080/2376×1080、竖屏 1080×2376，全屏 `topPadding` 110→0→恢复；读回用 PNG IHDR 与 `dumpsys`（JSON 里 `window/padding` 只输出 `Instance of`，不能当证据）。Windows 无真全屏（SPEC 已声明） | 已够；半更新尺寸对方向的影响见 H12 | 假体：`_SpyOrientationPort` 只记入参（`engine_test.dart:1886-1920`），`_CountingOrientationPort`、`_GatedOrientationPort` 同｜单测：`engine_test.dart:787`；`engine_dispose_race_test.dart:112-135`｜产品：`orientation_impl.dart:74-96`、`engine.dart:2234-2254` | A14-②、A16-②、U8-③、P12-② |
| H58 | `createMovaEngine()` 仅在 Android 装配系统音量端口；其余平台走 `mpv volume` | **未核对** | （Windows）：Windows 上 `Player.setVolume` 的 0–100 语义/越界行为、HUD 与实际响度一致性未测（A8 全在 Android） | Windows release：`setVolume(0/50/100/150)`，读 mpv `volume` 属性与系统混音器会话音量 | 假体：`FakeKernel.setVolume` 只记调用；`wiring_test.dart` 注入假端口｜单测：`engine_test.dart:1555`（无端口时走内核）｜产品：`wiring.dart:227`（`volume ?? _defaultVolumePort()`）、`volume_impl.dart:1-18` | A8-② |

#### 生命周期（H59 H60 H61 H62）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H59 | Android 切后台序列为 `inactive→hidden→paused→hidden→inactive→resumed`，单测里用 `inactive→hidden` / `inactive→resumed` 足以代表 | 已核对 | （Android+Windows）：V9 Android 5/5 序列 `[inactive,hidden,paused,hidden,inactive,resumed]`；Windows 直接 `hidden`（无 `inactive`）。同分支，缺口无害 | 已够 | 假体：`ui/auto_pause_test.dart:47-48`（`_toBackground`/`_toForeground` 缺 `paused` 与回程 `hidden`）；`:211-215`｜单测：`ui/auto_pause_test.dart:197,211`；`core/guard/auto_pause_gate_test.dart`｜产品：`ui/guard/auto_pause.dart:373-393`（hidden/paused/detached 同一分支） | U9-②、N18-②；he_auto:V9 |
| H60 | Android 回收渲染面时 libmpv 在 `inactive` 之后、`hidden` 之前自行暂停，守卫靠 `inactive` 快照意图 | 部分核对 | （Android）：V9 5/5 回前台自动续播、位置 3s 推进 2800–3000ms、`liveEdgeReach=true`，说明守卫链路成立；"`hidden` 到达前 `playing` 已为 false"究竟发生的比例未量化（可能快照从未被用到） | 在 V9 里同时记录 `inactive`/`hidden` 到达时刻的 `state.playing` 与原生 `pause` 属性，N≥10，另做 5min/60s 长时后台。**用例已写，待上机**：批次 gap-screen；coverage_gap:G2.3.screen（安全锁需人工解锁） | 假体：`auto_pause_test.dart:211-215` 手推 `playing:false`；`FakeKernel` 不会自暂停｜单测：`ui/auto_pause_test.dart:211` 7. the system pausing during inactive does not lose the intent to resume｜产品：`core/guard/auto_pause.dart:295-303,413-420` | U9-②、F5-②、N18-②、G2.3-③ |
| H61 | 直播隐藏 ≥3s 后 `backToLiveEdge()` 真能回到边缘并续播；PiP/小窗不暂停 | 已核对 | （Android）：V9 `liveEdgeReach=true` 5/5；V11 PiP 豁免 5/5 无 `MovaPause`；V10A/B 路由覆盖 5/5 | 已够 | 假体：`FakeMovaApi.push(playing:false)`（`auto_pause_test.dart:221-230`）｜单测：`ui/auto_pause_test.dart:224`（grace 后回边缘）｜产品：`core/guard/auto_pause.dart:437-455`、`engine.dart:2416-2443` | A20-②、E.MovaLiveEdgeReach-②、U9-②、N18-②；he_auto:V9、he_auto:V11 |
| H62 | 不透明路由覆盖/`TickerMode`/`RouteObserver` 触发暂停的时延在几十 ms；`go_router` 的 `StatefulShellRoute` 与根 navigator 半透明路由同样成立 | 部分核对 | ：Android V10A/B 各 5/5，pause 14–53ms、play 15–58ms，未复现 Windows 崩溃；Windows 崩溃已用 `MovaSnapshotGuard` 规避（V10A 20/20）。`StatefulShellRoute.indexedStack`/`routeObservers` 的 go_router 真实结构**未测**（需业务路由） | 在 go_router 示例里复现 shell 分支切换，N≥5 | 假体：测试里 `TickerMode(enabled:)` 切换（`auto_pause_test.dart:224~`），无真实 navigator 栈｜单测：`ui/auto_pause_test.dart`（TickerMode/route 用例）｜产品：`ui/guard/auto_pause.dart` | U9-②、N18-②；he_auto:V10 |

#### 网络/源（H63 H64 H65 H66 H67）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H63 | 实时流判定：WHEP（`file-format=whep`）直接限制后向缓冲；裸 TS 直播（`seekable=no` 且时长递增/无时长）经兜底探测识别，点播 TS（`seekable=yes`）、恒定时长无 Range 点播、HLS 不被误限 | 部分核对 | ：`whep` 命中（Android 历史 2026-10-02）已核；**兜底（裸 TS 直播、seekable/duration 真实读数序列）没有任何真机样本**（rtsp/sdp 在瘦身 libmpv 里无 demuxer，根本打不开，故未收录） | 本地起裸 TS 直播（ffmpeg `-f mpegts` HTTP chunked）与点播 TS，Android 读 `seekable`/`duration` 序列与是否触发限制；同时核对 `demuxer-max-back-bytes` 前后读回。**用例已写，待上机**：批次 gap-formats；coverage_gap:G3.2.<可支持格式>（读回 `seekable`/`demuxer-max-back-bytes`） | 假体：`_FakeNative.seekable/duration` 序列由 `_Seq` 编排，`duration` 空串表示不可用（`mpv_kernel_live_cache_test.dart:56-110`）｜单测：`mpv_kernel_live_cache_test.dart:139-335`（~25 条）｜产品：`mpv_kernel.dart:255-320`、`mpv_defaults.dart:76-106`（间隔 1.5s、增长比 0.5） | A35-②、C2-②、F2-②、G3.2-③ |
| H64 | `getProperty` 对"不可用属性"返回空串或抛异常，两者都被 `_readNativeProperty` 归为 null | **未核对** | ：真实 media_kit `NativePlayer.getProperty` 对 unavailable 属性是抛、返回空还是返回字符串，没有读回记录；兜底探测的 `da==db==null` 分支依赖它 | 对直播源读 `duration`、对无视频源读 `video-bitrate/frame-drop-count`，记录返回值/异常类型 | 假体：`_FakeNative.getProperty`：`failRead` 抛 `StateError`，`duration` 空串（`mpv_kernel_live_cache_test.dart:73-78`）｜单测：`mpv_kernel_live_cache_test.dart:187`、`:257`、`:277`｜产品：`mpv_kernel.dart:869-878` | C2-②、F7-② |
| H65 | 按源 mpv 选项：数值属性读回形态与写入一致；`demuxer-lavf-o` 键值列表的读回/`change-list add/remove` 可逆；读不到原值时能还原 | 部分核对 | （Android）：C17/N4 network 7→2、cache no→yes、analyzeduration 增删、`protocol_whitelist` 保留、WHEP first_frame/media/handshake 微秒项，再开 HTTP 全部还原（读回为准；旧 CHECK 把 `7.000000` 与 `7` 比错是验证器问题）。**属性读不到→原值 `''`→还原时写 `''` 被 mpv 拒绝而选项残留**的分支无真机样本 | 对一个"读回会抛"的属性（如无视频源上的视频选项）设按源选项，切下一源后读回对账 | 假体：`_FakeNative` 读回=写入原串（`mpv_kernel_source_options_test.dart:27-108`）；真实 `network-timeout` 读回 `"7.000000"`、与写入 `"7"` 不同｜单测：`mpv_kernel_source_options_test.dart:133-233`（~12 条）；`engine_source_options_test.dart`｜产品：`mpv_kernel.dart:610-715`、`mpv_keyvalue.dart` | C14-②、C17-②、N4-② |
| H66 | `tls-verify=yes`+`tls-ca-file` 能正确放行合法证书、拒绝过期/域名不符/自签；IP SAN 合法证书也应放行 | **已证伪** | （Android，IP SAN 一项）：40 格矩阵 35 符合；verify=true 时拒绝 expired/wrong/self 正确，`localhost`（DNS SAN）6/6 通过，**合法 IP SAN 证书 5/5、6/6 被拒**（openssl verify 通过）；终审推测 mbedtls 3.4 不支持 IP 类 SAN 主机名校验（凭记忆，未核对源码）。README「已知限制」待写 | 对 mbedtls 源码/发行说明核对 IP SAN 支持；Android 13+ 与 x86_64 各复跑 IP/DNS 两组 | 假体：`mpv_kernel_tls_test.dart:47-80` 只断言属性写入顺序（`_FakeNative`），证书校验本身无法假造｜单测：`kernel/mpv_kernel_tls_test.dart:62,69`｜产品：`mpv_kernel.dart:322-338` | C16-②、G1.1-③ |
| H67 | 默认 media_kit 白名单缺 `dtls`，补上后 WHEP 能播 15s 且无 `MovaErrorEvent` | 已核对 | （Android，历史 2026-10-02）；2026-10-27 F15 因 `127.0.0.1:38889/test/whep` 不可达 BLOCKED，**未复测** | 本地起 WHEP 服务（需先征得依赖同意）跑 15s | 假体：`mpv_defaults_test.dart` 只验证列表｜单测：`kernel/mpv_defaults_test.dart`｜产品：`mpv_defaults.dart:7-38`、`mpv_kernel.dart:160` | C17-②、F15-②、N4-② |

#### 事件泵（H68 H69 H70）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H68 | release 下原生唤醒回调（`NativeCallable.listener`）可靠投递；debug 的 100ms 轮询与之行为一致但精度不同；事件风暴不丢事件 | 部分核对 | （Android release）：V3/V6/V7/V9 通过；debug 轮询首个 RESTART 307–677ms（不可与 release 数字比）。**`MPV_EVENT_QUEUE_OVERFLOW`**（事件队列满时 mpv 丢事件）与"一次 wake 内事件极多"未测 | 在 release 用 `observe` 之外制造高频 seek/切换风暴（每秒 20 次 seek ×30s），统计 RESTART 数与 seek 数对账 | 假体：`FakeMpvEventBackend.wake()` 同步调用（`fake_mpv_event_backend.dart:87-89`），`pump` 一次 wake 排空多个事件且全同步；无队列溢出建模｜单测：`kernel/mpv_event_pump_test.dart:72` I6；`:196` 事件风暴中途 dispose｜产品：`mpv_event_backend_ffi.dart:166-200`、`wiring.dart:221`（`pollInDebug: kDebugMode`）、`mpv_event_pump.dart:154-187` | F14-②、N13-② |
| H69 | END_FILE `reason` 枚举：stop=2、quit=3、error=4、redirect=5；`eof` 不可达 | 部分核对 | （Android）：`error`（404/拒连）、`stop/quit`（QoE stopped/abandoned）见过；`redirect` 未触发；`loadfile replace` 在换源时旧文件的 END_FILE reason 是否恒为 `stop`（H7 的前提）未核对 | 对换源/中途 stop/dispose/断流各读一次 END_FILE reason，记入表 | 假体：`mpv_event_pump_test.dart:417` 手工给 0/2/3/4/5；`mpv_kernel_events_test.dart:318` reason mappings｜单测：`kernel/mpv_event_pump_test.dart:417`；`mpv_kernel_events_test.dart:318`｜产品：`mpv_kernel.dart:437-450`、`mpv_event_backend_ffi.dart:69-82` | F7-②、F14-②、N5-② |
| H70 | 多引擎并存时事件互不串扰，PiP/小窗等全局原生回调按"各 engine 一份"分发 | 已核对 | （Android）：V6 三引擎 restart=[1,1,1]→[2,1,2] 互不串扰；PiP 同一次转换在 3 个存活 engine 各收 1 条（R E.MovaPipChange）。**哪个 engine 才"拥有"PiP 画面、其余是否应忽略**是语义问题，未定 | 多 `MovaPlayer` 同屏时进入 PiP，核对谁收到 `PipChange`、是否仍有引擎误暂停 | 假体：`FakeMpvEventBackend` 每实例独立；`_ObservablePip` 单引擎｜单测：`mpv_event_pump_test.dart:326` I9 多引擎并存｜产品：`MovaPlugin.kt:104-111`（单一 `pipChanged` 推给所有订阅者） | F13-②、N9-②、G4.4-③ |

#### QoE（H71 H72 H73 H74）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H71 | `paused-for-cache` 是真卡顿；属性通知被合并时一对边沿可能丢失，聚合器容忍 | 部分核对 | （Android）：限速流 3 次真 rebuffer（`signal: cache`，各 4.8–5.3s，`stallMs` 15691≈15145+尾部）；完整卡顿释放 stallCount=1/stallMs=5468。**边沿被合并丢失的容忍**无真机样本（SPEC 约束 2 只是文字） | 在抖动网络（20–200ms 间歇卡）下记录原生 `paused-for-cache` 通知序列与聚合 stall 次数/时长对账 | 假体：`FakeStatsKernel.emitStalling(true/false)` 严格成对（`fake_kernel.dart:368`）｜单测：`report/stall_test.dart`；`report/collector_test.dart`｜产品：`collector.dart:595-628`、`mpv_kernel.dart:198-206` | C13-②、F7-②、N23-② |
| H72 | TTFF = open→RESTART；`nativeRestartAvailable` 在弱客户端异步注册完成前为 false，按落地时刻判断 | 已核对 | （Android）：真机首帧 `signal` 全为 `restart`，视频 311–348ms、音频 143–226ms；`qoe:false` 零 QoE 事件、弱客户端 0 个 | 已够 | 假体：`FakeStatsKernel.nativeRestartAvailable` 手动置位（`fake_kernel.dart:279`）｜单测：`report/ttff_test.dart:77,87`；`report/stats_probe_test.dart`｜产品：`mpv_kernel.dart:820`、`collector.dart:559` | E.MovaFirstFrame-②、F7-②、F14-②、N23-② |
| H73 | 服务端静默断流时 mpv 以 EOF 结束（`eof-reached`），`truncatedBelow` 可把"完播率低于阈值"记为 failed+truncated | 已核对 | （Android，CLAUDE 2026-09-30 中途断流、R batch15-qoe-truncated） | 已够 | 假体：`truncation_test.dart:72-79` 纯判定函数；`FakeKernel.emitCompleted(true)`｜单测：`report/truncation_test.dart:72-79`；`report/collector_test.dart`｜产品：`report/truncation.dart`、`collector.dart:293-316,491` | C13-②、F7-②、N23-② |
| H74 | `sample()` 的各 mpv 属性（`video-bitrate`、`cache-speed`、`frame-drop-count`、`decoder-frame-drop-count`、`hwdec-current`、`demuxer-via-network`）能读到可解析的 int/yes-no | 部分核对 | ：`cache-speed`（standby 验证页读 `inputBps`）、`hwdec-current`（读回 `mediacodec-copy`/`d3d11va-copy`）、`file-format` 见过；`video-bitrate`/`frame-drop-count`/`decoder-frame-drop-count`/`demuxer-via-network` 在真机的返回形态没有记录 | 对 mp4/HLS/直播各调用 `sample()` 一次，记录 7 个字段的原始读回 | 假体：`FakeStatsKernel.sampleResult` 手设；`MovaTestKernel.sample()` 恒 null（`test_kernel.dart:232`）｜单测：`report/stats_probe_test.dart`；`report/bitrate_test.dart`｜产品：`mpv_kernel.dart:831-900` | C13-②、F7-②、F12-③ |

#### 假内核默认（H75 H76 H77）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H75 | `screenshot()` 返回测试给的字节；真实内核需 `VideoController`，audioOnly/未创建返回 null；预览抽帧不依赖 `VideoController`（手动 `vid=auto`+`vo=null`，轮询 `seeking=='no'` 且 `time-pos` 差<0.3s） | 已核对 | （Android+Windows）：Android 5/5 成功 360–480ms、Windows 5/5 186–273ms，两平台 5 张图校验和逐一相同；`MovaFrameExtractor` 依赖真 libmpv 无法单测 | 已够 | 假体：`FakeKernel.screenshot`（`fake_kernel.dart:164-167`）；抽帧用 `_FakeExtractor`（`extractor_test.dart:11`）｜单测：`core/preview/extractor_test.dart`；`preview/service_test.dart`｜产品：`mpv_kernel.dart:746-747`、`platform_impl/mpv_extractor_impl.dart` | A30-②、F10-②、P9-②、C1-② |
| H76 | `setRate` 接受任意值 | 已核对 | （Android）：A10 0.5/1/1.5/2 生效，`-1/0` 抛 `Invalid argument(rate)`；抛出后 `state.rate` 未变（调用方需自己接异常） | 已够 | 假体：`FakeKernel.setRate` 只记录（`fake_kernel.dart:159-161`）｜单测：`engine_test.dart`（rate 相关）｜产品：`engine.dart:2190-2195`（无入口校验）、media_kit `setRate` 对 ≤0 抛｜单测（2026-10-28 补）：2026-10-28 起引擎入口钳 0.25–4.0、NaN→1.0（`movaClampRate`，`engine_rate_test.dart`），本假设只对 media_kit 层成立，旧真机结论是钳制前的行为 | A10-② |
| H77 | 事件载荷与"接收这一刻"的 `engine.state` 同步一致 | **已证伪** | （Android，cutover 代理）：R A2/E.BufferChange 7 次中 3 次载荷≠接收时 state；终审认定普通引擎一致、仅代理分两条订阅有延后，降级 P3 未改 | 若要保证一致：代理合并为一条订阅，真机再对账 `BufferChange`/`SizeChange` N≥50 | 假体：`FakeKernel` 同步 emit + `flushMicrotasks`；`FakeMovaApi` 直接 push｜单测：`engine_test.dart`（事件/state 对账类）；`cutover_engine_test.dart:49`｜产品：`cutover_engine.dart:207-210`（代理分两条订阅转发 state/events）、`engine.dart:679-690` | A2-②、E.MovaBufferChange-② |

#### 直播（H78）

| H | 假设（可证伪的一句话） | 状态 | 核对结论与证据出处 | 建议的真机核对方法 | 假体出处 · 依赖单测 · 产品代码 | 反指矩阵行 |
|---|---|---|---|---|---|---|
| H78 | DVR 窗口、`timeshiftBehind`、`backToLiveEdge`（seek 到窗口末端）与 `durationStep` 节流，在真实滑动窗口 HLS 上成立；`urlBuilder` 历史回看服务按 `behind` 返回历史段 | 部分核对 | （Android）：滑动窗口 12s、seek 3s、`backEdge` 回到 12000ms+`LiveEdgeReach`、durationStep 0/2s 对比通过（F2/N7）；**`urlBuilder` 历史语义、`windowResolver`、`autoBackToLiveOnStall` 联动没有服务可测**（C2 BLOCKED） | 写按 `behind` 参数返回历史段、可控卡顿的 Python 服务（G5 已列），再复测 C2 | 假体：直播单测用静态 `emitDuration`（`engine_test.dart`/`openness_live_test.dart`）；`urlBuilder` 只测"传入参数"｜单测：`core/live/timeshift_test.dart`；`openness_live_test.dart`｜产品：`engine.dart:2703-2743`、`engine.dart:2089-2138 _seekTimeshift` | A20-②、C2-②、E.MovaLiveEdgeReach-②、F2-②、N7-② |

## 5. 缺口清单

优先级口径：**P0** 发版前应补；**P1** 建议补；**P2** 有条件再做。单测缺口沿用盘点口径（P0 = 主 API 成员/事件完全没有断言且修起来成本低或有 bug 就用户可见；P1 = 契约子点缺失或有明确行为分支没人走；P2 = 配置/辅助类默认值、getter、旧名、夹具自测）。

> **回填说明（2026-10-28）**：本文初稿按已提交状态（HEAD `ddf1cd8`，基线 1519）成稿，当时工作区的在途改动看起来在补 §5.1.1 的 P0 缺口，并同时实现 §6 的前两项。现已核对并计入：完整 `flutter test` 为 `+1738`（0 skip）。已补的落点：P0-01→`engine_verbs_test` A6 group；P0-02→`engine_rate_test`；P0-03→`engine_verbs_test` A13 + `skin_test` 锁定组；P0-04→`engine_verbs_test` A7 group；P0-05→`engine_streams_test`；P0-06→`method_channel_test` PiP 组；P0-07→`engine_fuzz_test`；P1-01→`engine_verbs_test` :322 起；P1-02→`interceptor_test` :154 起；P1-03→`report_engine_test` :81 起；P1-04→`first_frame_engine_test` :34；P1-05→`engine_verbs_test` :369 + `top_bar_test` :154；P1-06→`cutover_engine_test` :159/:291/:307；P1-07→`engine_verbs_test` :401；P1-08→`engine_verbs_test` :424；P1-09→`gesture_test` :192/:264；P1-10→`top_bar_test` :129 + `hud_test` :81；P1-11→`component_tree_test` + `player_test` :242；P1-12→`platform_impl/ports_impl_test`；P1-13→`stt_test` :121；P1-15→`engine_verbs_test` :527；P2-09→`engine_verbs_test` :187。**未做**：P1-14（默认内核在 `createMovaEngine` 内部直接构造真 `MovaMpvKernel`，单测没有注入点，需 lib 加 `@visibleForTesting` 内核工厂才能测）与 P2 的其余 13 条。

### 5.1 单测缺口

#### 5.1.1 可单测但缺单测（36 条：P0 7 / P1 15 / P2 14；2026-10-28 回填后已补 22 条〔P0 7 + P1 14 + P2 1〕，未补 14 条，另新增 P2-15）

只列「纯逻辑 / FakeKernel 或 `MovaTestKernel` / 假端口 / WidgetTester 能覆盖」的子点；依赖真实 libmpv、系统事件、GPU 的不在此列（那些在 §3.2/§3.3）。

**P0（7 条）**

| 编号 | 关联矩阵编号 | 缺的断言 | 建议落点文件 | 源码位置 |
|---|---|---|---|---|
| P0-01（已补） | A6 / E.MovaPlay / E.MovaPause / E.MovaDone | 给定已 open 的 MovaEngine(FakeKernel) 且订阅 events，当 `k.emitPlaying(true)` 再 `emitPlaying(false)`，则 events 依次含 MovaPlay、MovaPause 且 state.playing 同步；当 `k.emitCompleted(true)`，则 events 恰含 1 个 MovaDone 且 state.completed==true；当 `e.play()` 后 `e.pause()`，则 state.playbackIntent 依次为 true、false（与 kernel.playing 无关）；连续两次 `pause()` 不抛；`playOrPause()` 在 state.playing=true 时走 pause、false 时走 play。 | test/core/engine_test.dart（新 group “playback events & intent”） | lib/src/core/engine.dart:681（MovaPlay/MovaPause）、:693（MovaDone）、:1828（play）、:1872（pause）、:1887（playOrPause） |
| P0-02（已补） | A10 / E.MovaRateChange | 给定已 open 的 MovaEngine，当 `setRate(1.5)`，则 kernel 收到 setRate(1.5)、state.rate==1.5、events 恰含一个 MovaRateChange(1.5)；当再 `open()` 新源，则 rate 的保持/复位按契约成立（先定契约）；当 `setRate(0)`/`-1`/`NaN`，现实现无钳制直接下发 kernel——需先拍板（钳制还是透传），再补断言。 | test/core/engine_test.dart（新 group “setRate”） | lib/src/core/engine.dart:2191-2195（setRate，零引用 MovaRateChange） |
| P0-03（已补） | A13 / E.MovaLockChange / S7 | 给定 MovaEngine，当 `setLocked(true)`，则 state.locked==true 且 events 恰含 MovaLockChange(true)，再 `setLocked(false)` 同理；给定 MovaPlayer+MovaDefaultSkin 且 FakeApi 推 `MovaState(locked:true)`，则顶栏/底栏/手势层不渲染、锁定遮罩可见（现仅有 MovaMiniSkin 的 lock 断言）。 | test/core/engine_test.dart + test/ui/skin_test.dart | lib/src/core/engine.dart:2212-2215；lib/src/ui/skins/default_skin.dart:128（selector s.locked）；lib/src/ui/components/overlays.dart:146 |
| P0-04（已补） | A7 / E.MovaSeek / E.MovaSeeked | 给定 duration=10min 已知的 VOD，当 `seek(-5s)` 则落点钳到 0，当 `seek(20min)` 则钳到 10min，kernel.lastSeek 为钳后值；当 `seek(120s)`，则 events 依次含 MovaSeek(120s)、MovaSeeked(120s)（notify:true 路径），而 `seekBy` 同样；寄存路径（duration 未到）只发 MovaSeek 不发 MovaSeeked，duration 到达后兑现。 | test/core/engine_test.dart | lib/src/core/engine.dart:1899-1913（clamp）、:1975/:1978（_seekOrPark 事件）、:2122/:2137、:2141（seekBy） |
| P0-05（已补） | A1 / A23 | 给定 MovaEngine，当两个订阅者各自 listen `events`/`states`/`uiStates`/`progress`，则二者都收到同一序列（不依赖 isBroadcast）；当 `dispose()`，则四条流都触发 onDone（`expectLater(stream, emitsDone)`）；当 dispose 后再调 `play()/seek()/setVolume()`，则不抛且不再产生事件（先定“dispose 后调用”的契约）。 | test/core/engine_dispose_race_test.dart（或 engine_test.dart 新 group “streams lifecycle”） | lib/src/core/engine.dart:2623（dispose）；全库 `onDone\|emitsDone` 仅出现在 kernel/preview/stt 相关测试 |
| P0-06（已补） | N9 / A18 | 给定 `MethodChannelMova`（mock `mova` 通道），当订阅 `pipChanges` 后平台下发 `pipChanged(false)`，则流收到 false；下发非 bool 参数或其他方法名则被忽略；当 `isPipSupported`/`enterPip` 的 handler 抛 PlatformException 或不注册（MissingPluginException），则分别返回 false；`enterPip(width:16,height:9)` 的实参为 `{width:16,height:9}`。这是“PiP 退出后 state.pip 复位”修复在 Dart 侧唯一的通道层，现只有引擎侧注入式用例。 | test/method_channel_test.dart | lib/mova_method_channel.dart:22-38（pipChanges）、:41-62（isPipSupported/enterPip）；lib/src/platform_impl/pip_impl.dart:8-17 |
| P0-07（已补） | G4.1 / A23 / A1 | 给定固定种子的随机动作序列（open/play/pause/seek/seekBy/setRate/setVolume/setFit/setZoom/setLocked/setFullscreen/setMini/setOrientation/switchQuality/reload/dispose 交叉，含连点 100 次 seek/换源/全屏），在 `runZonedGuarded` 内对 MovaEngine(FakeKernel) 执行：则无未捕获异常；state.volume∈[0,100]、zoom≥1、brightness∈[0,1]；state.playing 与最后一次 kernel.emitPlaying 一致；dispose 之后任何调用不抛、四条流已关闭；失败时打印种子可复现。矩阵标 P0 且现全库无 fuzz（grep `Random\|fuzz` 无命中）。 | 新文件 test/core/engine_fuzz_test.dart（用 test/support/fake_kernel.dart；`MovaTestKernel` 亦可） | lib/src/core/engine.dart（全部动词）；参考 test/support/fake_kernel.dart |

**P1（15 条）**

| 编号 | 关联矩阵编号 | 缺的断言 | 建议落点文件 | 源码位置 |
|---|---|---|---|---|
| P1-01（已补） | A11 / A12 / A14 / E.MovaFitChange / MovaZoomChange / MovaFullScreenChange / MovaSizeChange / MovaReady | 给定 MovaEngine：`setFit(cover)` → state.fit==cover 且恰一个 MovaFitChange(cover)；`setZoom(2.5)` → 恰一个 MovaZoomChange(2.5)（钳制值 1.0 同理）；`setFullscreen(true)` 再 `setFullscreen(false)` → state.fullscreen 回 false、events 含 MovaFullScreenChange(false)、orientation 端口 reset/apply 被调；`k.emitSize(1920,1080)` → 恰一个 MovaSizeChange(1920,1080)；常规 `open()` 完成 → 恰一个 MovaReady。 | test/core/engine_test.dart | lib/src/core/engine.dart:743（SizeChange）、:1367（Ready）、:2198-2224（setFit/setZoom/setFullscreen） |
| P1-02（已补） | A32 / P13 | 给定带两个 MovaHook 的引擎，当 kernel 报错（`k.emitError`）或恢复耗尽，则每个钩子的 `onError` 都收到且其中一个抛异常不影响另一个；`MovaHookChain.beforePlay`：任一钩子返回 false 即否决、后续钩子不再调用；钩子 `beforePlay/beforeSeek` 抛异常时 `play()/seek()` 的行为（拒绝 or 透传）先定契约再断言。 | test/core/interceptor_test.dart | lib/src/core/interceptor/interceptor.dart:30、:74、:86-90；lib/src/core/engine.dart:760、:1527（调用 onError） |
| P1-03（已补） | G4.5 | 给定 `MovaCallbackReporter` 回调抛 StateError，当引擎播放/暂停/换源并触发上报，则引擎事件与 state 继续更新、无未捕获异步错误；当事件洪泛（同一帧内 5000 个 report），则不丢最终 sessionEnd（先确认设计：collector 当前直接调用 `_reporter.onReport` 无 try/catch，抛异常会冒到订阅回调——待确认是否应隔离）。 | test/core/report/report_engine_test.dart | lib/src/core/report/collector.dart:684；lib/src/core/engine.dart:2603-2606；lib/src/core/report/report.dart:297-328 |
| P1-04（已补） | E1 | 给定 MovaEngine(FakeKernel)，当 `open → emitPlaying(true) → emitDuration → emitSize → emitRestart/首帧 → emitCompleted(true)`，则 events 的类型序列依次含 MovaSourceChange、MovaPlay、MovaReady、MovaSizeChange、MovaFirstFrame、MovaDone，且 Play 先于 Ready（矩阵修订后的现行顺序）。 | test/core/first_frame_engine_test.dart（复用其 rig） | lib/src/core/engine.dart:681、:693、:743、:1049、:1367 |
| P1-05（已补） | A17 / U3 / S9 / E.MovaQualityListChange | 给定 fetcher 返回 master 列表，当 `loadQualities()` 成功，则 events 恰含一个 MovaQualityListChange 且载荷与 state.qualities 一致；给定 FakeApi 有 3 档，当点击顶栏清晰度按钮并选第二项，则 api.calls 含 `switchQuality`（实参为该档）且弹层关闭；`MovaSheetItem.checked` 标记当前档。 | test/core/engine_test.dart + test/ui/top_bar_test.dart | lib/src/core/engine.dart:2285-2286；lib/src/ui/components/top_bar.dart:184（MovaQualityButtonComponent）；lib/src/ui/components/common.dart:136（MovaSheetItem） |
| P1-06（已补） | E.MovaCutoverChange / A24 | 给定启用的 MovaCutoverEngine，当 prepare→ready→commit，则 `events` 流依次含 MovaCutoverChange(warming)、(ready)、(idle)（与 cutoverPhases 一致）；disabled 时零个。 | test/core/cutover/cutover_engine_test.dart | lib/src/core/cutover/cutover_engine.dart:870（`_events.add(MovaCutoverChange(phase))`） |
| P1-07（已补） | A19 | 给定已 open（autoPlay:true）的引擎，当 `reload()`，则 kernel 以同一 uri 重开且 play=true；`pause()` 后 `reload()` 以 play=false 重开（_playIntent）；未 open 时 `reload()` 空操作不抛。 | test/core/engine_test.dart | lib/src/core/engine.dart:2410-2413 |
| P1-08（已补） | A21 / C5 | 给定 `autoHide:true, autoHideDelay:3s`（fakeAsync），当 `showControls()`，则 3s 后 controlsVisible 回 false；`showControls(sticky:true)` 不启动计时、永不自动隐藏；连续 `showControls()` 重置计时；`showHud(volume)` 800ms 后 hud 回 none 且 hudText 清空。 | test/core/engine_test.dart | lib/src/core/engine.dart:2504-2511（showControls，全库零引用）、:2521-2530（showHud 计时） |
| P1-09（已补） | S7 / C3 / U6 / S4 | 给定 MovaGestureLayerComponent（pinchZoom:true,maxZoom:3），当双指张开 scale=5，则 api.calls 的 setZoom 值被钳到 3；pinchZoom:false 时双指不触发 setZoom；给定 locked 状态，手势不下发任何 api 调用；单击切换控件显隐（controlsVisible 取反）。 | test/ui/gesture_test.dart | lib/src/ui/components/gesture_layer.dart:225（_onTap）、:246-275（_onScaleUpdate/_applyZoom） |
| P1-10（已补） | S9 / U3 / U5 / P16 | 给定 FakeApi，当点击顶栏全屏按钮，则 api.calls 含 `setFullscreen(true)`，已全屏时点击为 `setFullscreen(false)`；给定 `MovaUiState(hud: MovaHud.zoom)` 与 state.zoom=2.0，则 HUD 层显示缩放文案；`MovaHud.fit/quality` 枚举值的渲染（或明确“不渲染”）。 | test/ui/top_bar_test.dart + test/ui/hud_test.dart | lib/src/ui/components/top_bar.dart:347（MovaFullscreenButtonComponent）；lib/src/ui/components/hud_layer.dart:174（MovaZoomHudComponent）；lib/src/core/state/ui_state.dart:4-38 |
| P1-11（已补） | S1 / S12 / S14 / P15 | S1：遍历所有 `*Component` 断言 `X.componentName == X(...).name`，并对 Default/Bilibili/Douyin/Minimal/Mini 五皮肤断言 `components()` 的 name 列表与 slot 分布（现仅 minimal_skin_test:23 读过 2 个常量）；S12：对每个皮肤依次应用 Add/Replace/Remove/InsertAfter，断言组件树变化（现仅 DefaultSkin 一例，skin_test:64）；S14：给定 MovaPlayer 把 `skin:` 从 Default 换成 Bilibili，则同一 api 不重开（kernel.calls 不增）、events 无重复。 | test/ui/skin_test.dart、test/ui/tree_test.dart、test/ui/player_test.dart | lib/src/ui/skins/*.dart；lib/src/ui/slots/patch.dart:31-133；lib/src/ui/player.dart |
| P1-12（已补） | P12 / A8 / A16 | 给定 mock `SystemChannels.platform`，当 `MovaSystemChromeOrientationPort.apply(fullscreen:true, immersive:true, …)`，则收到 setPreferredOrientations（按 resolveOrientations）与 immersiveSticky 的 setEnabledSystemUIMode；`reset()` 恢复全方向 + edgeToEdge。给定 fake `MovaPlatform`，`MovaSystemVolumePort.get()` 在平台返回 null 时回 100，`set(150)` 实参被钳到 100。 | 新文件 test/platform_impl/ports_impl_test.dart | lib/src/platform_impl/orientation_impl.dart:76-94；lib/src/platform_impl/volume_impl.dart:19-30 |
| P1-13（已补） | A31 / P10 | 给定 MovaSttService(config:enabled, engine:假引擎)：`attach` 换源后 `current` 清空且 `isRunning` 保持/复位按契约；`updatePosition` 命中 cue 区间时 `current` 取该 cue；`stop()` 后 `isRunning==false` 且 cues 流不再转发；`dispose` 后再 `start()` 不抛。另需确认设计：service 目前不引用 MovaSttSubtitleStore/ChunkStore/ModelProvider/AudioPuller（grep 核实），“cue→存储→SRT”管线是否应有集成用例待定。 | test/core/stt_test.dart | lib/src/core/stt/service.dart:91-146（start/stop/attach/updatePosition/dispose） |
| P1-14（未做：缺内核工厂注入点） | C16 / P19 | 给定 `createMovaEngine(tlsVerify:true, tlsCaFile:"/ca.pem")`（注入 FakeKernel 工厂或 spy player），则内核构造参数收到 tlsVerify/tlsCaFile；默认不传时为 false/null；`pollInDebug`、`recovery` 参数同样透传。 | test/platform_impl/wiring_test.dart | lib/src/platform_impl/wiring.dart:164-165、:216-217 |
| P1-15（已补） | G3.5 | 给定同一引擎先 open 直播（liveSeekable/seekableWindow/timeshiftBehind 有值）再 open 点播，则 type=vod、liveSeekable=false、seekableWindow=0、timeshiftBehind=null、duration 基线清零；再 open 直播同理。 | test/core/engine_test.dart | lib/src/core/engine.dart:1239-1370（open 的归零段） |

**P2（14 条）**

| 编号 | 关联矩阵编号 | 缺的断言 | 建议落点文件 | 源码位置 |
|---|---|---|---|---|
| P2-01 | C4 / C5 / C3 / C8 / C10 / P3 | 给定 MovaAbrConfig/MovaCtrlsConfig/MovaGestureConfig/MovaPlaylistConfig/MovaStrs/MovaTheme：默认值读回、`copyWith` 只改一个字段、`==/hashCode` 按字段、`MovaOpts.copyWith(abr:/controls:/gesture:/playlist:/strings:/theme:)` 只换对应段。 | test/core/options_test.dart | lib/src/core/options/abr_config.dart:97；controls_config.dart:4；gesture_config.dart:47；playlist_config.dart:15；strings.dart:14；theme.dart:12；options.dart:187 |
| P2-02 | P1 | `MovaState.copyWith(clearError/clearQuality/clearTimeshift:true)` 分别只清对应字段；`MovaUiState.copyWith(clearHudText/clearPreview:true)` 同理。 | test/core/state_test.dart | lib/src/core/state/state.dart:268-315；lib/src/core/state/ui_state.dart:91 |
| P2-03 | P17 | 对 13 个未被引用的 `@Deprecated` typedef（MovaAdController/MovaFeedController/MovaPlaylistController/MovaMiniController/MovaSwapEngine/MovaSwapController/MovaSwapChange/MovaSwapPhase/MovaStandbyController/MovaStandbyReason/MovaStandbyChange/MovaStandbyResume/MovaSilentStandby）各加一行 `expect(const X(...) / X is Type …)` 同类型断言。 | test/deprecated_names_test.dart | lib/src/deprecated_names.dart:22-86 |
| P2-04 | P9 / P10 | 给定 fake `PathProviderPlatform`（写法见 testing_test.dart:26），`MovaTempThumbDirProvider/MovaTempSttModelDirProvider/MovaTempSttSubtitleDirProvider.resolve()` 返回临时目录下对应子目录且可写；`MovaIoHttpFetcher`：本地 `HttpServer` 返回 200/404/Range 时，bytes/空/部分内容的行为与超时。 | 新文件 test/platform_impl/dir_providers_test.dart、test/core/preview/fetcher_test.dart | lib/src/platform_impl/thumb_dir_impl.dart:18；stt_model_dir_impl.dart:28；stt_subtitle_dir_impl.dart:28；lib/src/core/preview/fetcher.dart:42 |
| P2-05 | P12 | `MovaFallbackVolumePort` 与 `MovaFallbackBrightnessPort` 并列断言：get 回固定值、set 被忽略。 | test/core/ports_test.dart | lib/src/core/platform/ports.dart:155 |
| P2-06 | P18 / A33 | `MovaTestKernel` 的 emitCompleted/Position/Duration/Buffer/Error/EndFile/Stalling 经 `createMovaEngine()` 驱动引擎后 state/events 对应变化；`exitKeepAlive/inspectKeepAlive`、`lastSeek/lastPlay` 记录值。 | test/testing/testing_test.dart | lib/src/testing/test_kernel.dart:154-290 |
| P2-07 | P1 / P11 / P14 | `MovaPlaylist.currentItem` 随 next/jumpTo 变化；`MovaPlaylistItem.displayTitle` 优先 title 否则 source.title；`MovaErrorEvent.stack` 透传；`MovaAds.adPosition` 随广告 tick；`MovaFeedPlayer(poolSize: n)` 引擎数不超 n；`MovaAutoPauseConfig(tickerMode:false)` 时 TickerMode 隐藏不暂停；`MovaProgSelect/MovaUiSelect` 仅在选中字段变化时重建（对标 selector_test:10）。 | playlist_test.dart / model_test.dart / engine_test.dart / ads_test.dart / feed_player_test.dart / auto_pause_gate_test.dart / selector_test.dart | playlist.dart:86；model/playlist.dart:55；events.dart:473；ads.dart:346；feed_player.dart:72；auto_pause.dart:96,:160；scope/selector.dart:51,:92 |
| P2-08 | G2.8 | 给定 RTL `Directionality` 与 `textScaler: 2.0` 下挂载 MovaPlayer(MovaDefaultSkin)，则无 overflow 异常；关键按钮带 Semantics label（播放/暂停/全屏）。 | test/ui/skin_test.dart | lib/src/ui/components/*.dart |
| P2-09（已补） | G2.1 / A6 | 给定 playbackIntent=true，当 kernel 单方面 `emitPlaying(false)`（模拟音频焦点丢失），则 state.playing=false、MovaPause 发出，playbackIntent 仍为 true（可被守卫/恢复使用）。 | test/core/engine_test.dart | lib/src/core/engine.dart:679-682、:1828-1884 |
| P2-10 | G2.9 | 给定 `MovaFileSttSubtitleStore` 目录只读/不可写，则 `save` 不抛、返回后 `load` 为 null；分块存储同理。 | test/core/stt_subtitle_store_test.dart、test/core/stt_chunk_subtitle_store_test.dart | lib/src/core/stt/subtitle_store.dart:87；chunk_subtitle_store.dart:100 |
| P2-11 | F13 / G4.4 | 给定 MovaFeedEnginePool(size:3, FakeKernel 工厂)，对随机 index 连续 bind/retain/focus 100 次，则任意时刻存活引擎数≤3、仅一个 playing、dispose 后全部 disposed 且 bind 为空操作。 | test/core/engine_pool_test.dart | lib/src/core/feed/engine_pool.dart |
| P2-12 | F1 | 给定 MovaEngine(FakeKernel)，串联 open→play→seek→setRate→setFullscreen→open(新源)→completed→dispose，断言事件序列整体合理、无异常（承接 P0 补齐后的各动词）。 | test/core/engine_test.dart | lib/src/core/engine.dart |
| P2-13 | C6 | 给定 trackCount=3 的弹幕配置与同一时刻 10 条弹幕，则同屏轨道不超过 3 且同轨不重叠（现仅“到点生成/过期回收/不重复”）。 | test/ui/danmaku_test.dart | lib/src/ui/components/danmaku.dart；lib/src/core/options/danmaku_config.dart |
| P2-14 | P10（待确认） | `MovaSttModelFile.sha256` 在 lib 内从未被校验（CLAUDE.md #13 也记了）；补测需先实现校验，且需 `crypto` 依赖——按项目规则先征得同意，不属于“现有逻辑缺测”，仅登记。 | — | lib/src/core/stt/model_spec.dart:33 |
| P2-15 | A7 / A20 / F2 | **DVR 直播 seek 未接“校验 + 重发”链**（2026-10-28 点播 seek 已接）：`seekMode: dvr` 窗口内的 seek 被 mpv 丢弃后，回声抑制仍有理论冻结风险（未在真机复现）；补测前先决定是否把 DVR seek 并入校验链，再写“被丢弃后收敛/放弃”的断言 | test/core/engine_seek_drop_test.dart | lib/src/core/engine.dart（DVR 分支 `_seekTimeshift`） |

#### 5.1.2 公开类型在已提交的测试里既无直接也无间接引用（真缺口）

方法：对 `test/` 全部已跟踪 `.dart` 做 `\bName\b` 计数；零引用者逐个找间接证据，找不到的算真缺口。附录 §8 每个类型都有对应行。

| 类型 | 位置 | 说明 | 建议落点 |
|---|---|---|---|
| `MovaFallbackVolumePort` | `lib/src/core/platform/ports.dart:155` | 同族 `MovaFallbackBrightnessPort` 有测（`ports_test:5`），这个漏了 | test/core/ports_test.dart |
| `MovaIoHttpFetcher` | `lib/src/core/preview/fetcher.dart:42` | 预览/清晰度默认 HTTP 取数实现，无用例（可用本地 `HttpServer`） | test/core/preview/fetcher_test.dart（新） |
| `MovaTempThumbDirProvider` | `lib/src/platform_impl/thumb_dir_impl.dart:18` | 三个 Temp 目录提供者均零引用（`MovaFixed*` 版本被测） | test/platform_impl/dir_providers_test.dart（新） |
| `MovaTempSttModelDirProvider` | `lib/src/platform_impl/stt_model_dir_impl.dart:28` | 同上 | 同上 |
| `MovaTempSttSubtitleDirProvider` | `lib/src/platform_impl/stt_subtitle_dir_impl.dart:28` | 同上 | 同上 |
| `MovaAudioExtractor` | `lib/src/platform_impl/mpv_audio_extractor_impl.dart:54` | 依赖 libmpv 属真机；参数/路径拼装可抽纯函数单测（待确认） | 待确认后再定 |
| `MovaSttModelFiles` | `lib/src/core/stt/model_spec.dart:72` | 模型文件集合值对象，`stt_model_provider_test` 只用 `MovaSttModelFile/Spec` | test/core/stt_model_provider_test.dart |
| `MovaProgSelect` | `lib/src/ui/scope/selector.dart:51` | `selector_test` 只测 `MovaSelect` | test/ui/selector_test.dart |
| `MovaUiSelect` | `lib/src/ui/scope/selector.dart:92` | 同上 | 同上 |

**已补并移出（2026-10-28）**：`MovaRateChange`（`engine_rate_test`）、`MovaLockChange`（`engine_verbs_test` :200）、`MovaSystemVolumePort`（`platform_impl/ports_impl_test` :154）、`MovaZoomHudComponent`/`MovaQualityButtonComponent`/`MovaFullscreenButtonComponent`（`component_tree_test` 按名引用，行为见 `hud_test`/`top_bar_test`）、`MovaSheetItem`（经清晰度弹层间接覆盖）。真缺类型由 16 个降到 **9 个**。

另外 13 个 `@Deprecated` typedef 零引用（见 §8.2）；5 个台账漏列的类型零引用（见 §8.3）。其余零引用类型都有间接证据，附录标「间接」。

#### 5.1.3 公开成员零引用（脚本 + 人工核实，只列真成员）

| 成员 | 位置 | 备注 |
|---|---|---|
| `MovaEngine.setRate / setLocked / setFit(正向) / reload / showControls` | `lib/src/core/engine.dart:2191 / :2212 / :2198 / :2410 / :2504` | **已补（2026-10-28）**：`engine_rate_test`/`engine_verbs_test` 直接调用 |
| `MovaHook.onError / MovaHookChain.onError` | `lib/src/core/interceptor/interceptor.dart:30 / :86` | **已补（2026-10-28）**：`interceptor_test` :177,:196 |
| `MovaErrorEvent.stack` | `lib/src/core/events/events.dart:473` | 字段无断言 |
| `MovaState.copyWith` 的 `clearError/clearQuality/clearTimeshift` | `lib/src/core/state/state.dart:268-315` | 只被引擎内部使用，`state_test` 未覆盖 |
| `MovaUiState.copyWith(clearHudText)` | `lib/src/core/state/ui_state.dart:91` | 间接经 engine_test:588，无直接断言 |
| `MovaPlaylist.currentItem` | `lib/src/core/playlist/playlist.dart:86` | 测试用 `items`/下标，不读该 getter |
| `MovaPlaylistItem.displayTitle` | `lib/src/core/model/playlist.dart:55` | 无 |
| `MovaAds.adPosition`（及相关公开 getter） | `lib/src/core/ad/ads.dart:346` | 无 |
| `MovaAutoPauseConfig.tickerMode / watches()` | `lib/src/core/guard/auto_pause.dart:96 / :158` | `tickerMode:false` 分支无用例 |
| `MovaFeedPlayer.poolSize` | `lib/src/ui/feed_player.dart:72` | `feed_player_test` 全用默认 3 |
| `MovaFrameExtractor.settleDelay / pollInterval` | `lib/src/platform_impl/mpv_extractor_impl.dart:45` | 依赖真实 libmpv，只能真机 |
| `MovaSttModelFile.sha256` | `lib/src/core/stt/model_spec.dart:33` | 字段存在但 lib 内从未校验（需 `crypto` 依赖，须先征得同意；已在 20382c4 文档标注「仅供参考」） |
| `MovaTestKernel.emitCompleted/emitPosition/emitDuration/emitBuffer/emitError/emitEndFile/emitStalling`、`exitKeepAlive`、`lastSeek/lastPlay` | `lib/src/testing/test_kernel.dart:139-290` | 仅 `testing_test.dart` 引用；其余测试用的是 `test/support/fake_kernel.dart` 的同名方法，**不算覆盖 `MovaTestKernel`** |

顶层函数 29 个里只有 `showMovaOptionSheet`（`ui/components/common.dart:176`）零引用。`movaProtocolWhitelist`（`kernel/mpv_defaults.dart`）与 `movaAudioPresence`（`kernel/keep_alive_kernel.dart:84`）**未从 `lib/mova.dart` 导出**，测试经 `package:mova/src/...` 直引，是否应公开待确认。

### 5.2 真机用例缺口

#### 5.2.1 真机用例缺口编号（27 个：8 个用例已写待上机、19 个仍无用例）

v1 的 135 个编号全部有用例（其中 6 个在 manifest 里是 manual）；v2 独立编号 61 个（S16 + P19 + G26）里 35 个有「相关子项」、26 个原先完全没有。**2026-10-28 本轮为其中 8 个写了用例（S7、S10、G1.1、G1.2、G2.1、G2.3、G3.1、G4.1，均未上机），仍完全没有的剩 18 个**（再加元条目 G5）。下表 8 个标「用例已写，待上机」，其余没有用例：

| 编号 | 主题 | 优先级 | 备注 |
|---|---|---|---|
| S3 | 皮肤专项：直播布局（五套皮肤均无证据） | — | 见 §3.3.S；gap-skin 未做：没有可控 live 夹具（见 §5.2.5） |
| S6 | 皮肤专项：手势：竖滑（五套皮肤均无证据） | — | 见 §3.3.S；gap-skin 未做：竖滑会改系统音量/窗口亮度，没有恢复机制不自动跑（见 §5.2.5） |
| S7 | 皮肤专项：手势：捏合/锁定（五套皮肤均无证据） | — | **用例已写，待上机**：gap-skin（锁定；捏合未做） |
| S10 | 皮肤专项：全屏与转屏（五套皮肤均无证据） | — | **用例已写，待上机**：gap-skin（`fullscreenShot`，截图人工判，BLOCKED） |
| G1.1 | 只测了 STG-AL00（华为）arm64-v8a。四架构 libmpv 里 armeabi-v7a/x86/x86_64 完全没跑过；Android 版本只有 | P0 | **用例已写（manual 登记），待上机**；BLOCKED：需构建变体与多设备 |
| G1.2 | release 构建全程 -Pdart-obfuscation=false（见 coverage_build.py），混淆/R8 minify 下的 JNI、M | P0 | **用例已写（manual 登记），待上机**；BLOCKED：需 R8 构建变体 |
| G1.3 | 以 pub.dev 依赖方式接入没测：验证全程走 path 依赖；0.3.0 发布版与当前 Unreleased 行为差异、media_kit_libs_ 官方 | P1 | — |
| G1.4 | 仅 Impeller（Vulkan/OpenGLES）；Android 上 Skia 后端、不同 Flutter 版本（只有 3.47.0）未覆盖 | P2 | — |
| G1.5 | 折叠屏/平板/分屏/多窗口/画中画与分屏并存、刘海与手势导航模式 | P1 | — |
| G2.1 | 音频焦点：来电、闹钟、其他 App 抢焦点、耳机拔出/蓝牙断开后的暂停与恢复 | P0 | **用例已写，待上机**：gap-focus / gap-focus-gsm（焦点归属与听感需人工；模拟器 `adb emu gsm call` 仅模拟器） |
| G2.3 | 息屏/锁屏/解锁：灭屏后播放、熄屏自动暂停与亮屏恢复（只测过切后台） | P0 | **用例已写，待上机**：gap-screen（安全锁需人工解锁） |
| G2.4 | 低内存/onTrimMemory、进程被系统回收后的重建、旋转导致 Activity 重建 | P1 | — |
| G2.5 | 物理音量键 / 系统音量被外部改动：state.volume 是否同步（现在只测了 App→系统） | P1 | — |
| G2.6 | 系统亮度被外部改动、退出播放/全屏后窗口亮度是否还原 | P1 | — |
| G2.7 | 系统手势冲突（边缘返回、状态栏下拉）与垂直手势区域 | P2 | — |
| G2.8 | 深色模式、字体缩放、系统语言切换（MovaStrs）、RTL、TalkBack/Semantics | P2 | — |
| G2.9 | 磁盘满/缓存目录不可写/无存储权限时预览磁盘缓存、STT 模型目录的降级 | P2 | — |
| G3.1 | 本地来源：file://、content://（SAF/相册）、Flutter asset、应用沙盒路径 | P0 | **用例已写，待上机**：gap-local（`content://` 无 SAF provider/grant，BLOCKED） |
| G3.3 | 协议：RTMP/RTSP/DASH/HLS 加密（AES-128）/fMP4 HLS/多音轨/多字幕轨切换 | P1 | — |
| G3.5 | 点播↔直播同引擎互换（type 切换时 UI、时移、seekable 状态机） | P1 | — |
| G3.6 | 超长/超大文件、时长为 0/未知、时长突变、损坏文件、截断文件 | P1 | — |
| G4.1 | 随机序列/压力测试：随机 API 调用序列（open/play/pause/seek/switchQuality/setFullscreen/setMini/d | P0 | **用例已写，待上机**：gap-random（固定种子 80 步） |
| G4.2 | 长时间浸泡：点播/直播连续 1–2h，监控内存/发热/掉帧/句柄，直播跨天时间戳 | P1 | — |
| G4.4 | 多实例：同屏两个 MovaPlayer、Feed 滑动 100 次 + 同时小窗 + 广告 cutover 叠加 | P1 | — |
| G4.5 | 上报回调抛异常/阻塞时不拖垮播放；事件洪泛的背压 | P2 | — |
| P17 | 旧名兼容：类型位置与构造器可用；成员/参数级旧名无别名（见 P17-①） | — | — |
| G5 | 矩阵自身问题（元条目，见 §7） | 先做 | 一键入口 `run_matrix.py` 已存在；设备端完整 L 日志未实现 |

另：P1–P16、P18、P19 与 G1.3b/G2.2/G3.2/G3.4/G4.3 只有相关子项（`main_coverage_api`/`coverage_new` 等页里的片段），**没有该编号的独立结论**，不能升级为通过。其中 G2.2（`gap-network`）、G3.2（`gap-formats`）本轮补了专用 gap 用例，待上机。

#### 5.2.2 BLOCKED 项与解锁条件

| 编号 | 缺什么 | 解锁办法 | 出处 |
|---|---|---|---|
| A31-③ / C7-③ | 真实识别引擎、模型与下载服务；设备旧 seed 目录不存在 | 先用**脚本化假引擎**验证 cue → 字幕 → SRT 导出 → 分块存储管线（归 A31-①，不要再把「没有真引擎」当整项阻塞）；真实识别另列 BLOCKED。STT 引擎方向（whisper.cpp）仍待用户确认依赖 | rerun.md:181,185；v2 G5 |
| C2-② | 按 behind 参数返回历史媒体且可控卡顿的时移服务（滑动 HLS ≠ 历史回看） | 本地写一个按 behind URL 返回历史段的时移服务（Python 即可） | rerun.md:182；v2 G5 |
| F15-③ | 可控 WHEP 服务（publisher/信令/UDP 38189/relay 38190）；端口可达不证明播放 | 本地起 mediamtx 类 WHEP 服务（**需先征得依赖同意**） | rerun.md:197；rerun-external-prerequisites.json |
| N18-② | 小窗连续播放对守卫豁免的专包补测（V11M/V10C 补测 APK 已构建；起测前 `isKeyguardShowing=true`，驱动按约束停止） | 亮屏解锁后用新 run-id 重跑 | rerun.md:162 |
| F17-② | 功能**未实现**（不是阻塞，不计 FAIL） | 先实现 `MovaKeepAliveMode.audible` / `onExpire` 等，见 §5.2.4 | device-trace §3 |
| （manifest 滞后）N22 | manifest 里仍写「缺 debug VM」，但 rerun 已有 debug 断言通过、整项 PASS | 同步 manifest 的 manual 理由（需改 `matrix_manifest.json`，本次未动逻辑） | matrix_manifest.json:1024；rerun.md:200 |
| G1.1 / G1.2 / G2.1 / G2.2 / G2.3 / G3.1 / H43 / S2·S10（gap 批次内的 BLOCKED 子项） | 构建变体与多 ABI 为 manual；焦点归属与听感需人工；路由变化须人工核对 connectivity dumps；锁屏需人工解锁；`content://` 无 SAF provider/grant；待机黑屏/冻帧与皮肤布局/全屏截图需人工判图 | 上机时按用例日志里的 BLOCKED 提示逐项人工配合（BLOCKED 不是 FAIL） | 2026-10-28 真机用例交付说明（暂存区，不入库） |

#### 5.2.3 矩阵与台账从未出现的公开 API（device-trace §3 盘点）

导出闭包以 `lib/mova.dart` 与 `lib/testing.dart` 递归 export 为准（137 个文件、320 个类型含 extension）。

**① 类型（16 个，名称都没出现过；均经 `options.dart` 再导出，台账漏列，见 §8.3）**：`MovaAbrPolicy`、`MovaAdWaitPolicy`、`MovaAdNotReady`、`MovaCutoverConfig`、`MovaGestureAction`、`MovaSilentKeepAlive`、`MovaKeepAliveConfig`、`MovaLiveSeekMode`、`MovaTimeShiftBuilder`、`MovaLiveWindowSolver`、`MovaBackToLive`、`MovaMiniCorner`、`MovaPreviewBlockReason`、`MovaPreviewBlockCb`、`MovaSttBlockReason`、`MovaSttBlockCb`

**② 顶层函数/常量（29 个，已并入 P20-①）**：`dueMidRoll`、`movaFeedWindow`、`clampToBounds`、`rectForCorner`、`parseHlsMasterPlaylist`、`movaDefaultAdStartingIn`、`kMpvDefaultNetworkTimeout`、`kFfmpegReconnectWindow`、`kWhepDefaultHandshake`、`kWhepDefaultFirstFrame`、`kWhepDefaultMedia`、`fnv1a64`、`defaultCacheKey`、`previewAllowedOn`、`currentPlatformKind`、`parseVttThumbs`、`defaultVttUrl`、`resolveSessionEnd`、`resolveSessionEndNative`、`newMovaSessionId`、`parseSrt`、`formatSrt`、`preferredOrientationsFor`、`resolveOrientations`、`showMovaOptionSheet`、`movaBoxFit`、`formatDuration`、`applyPatches`、`buildSlots`

**③ 公开成员（811 个成员名在矩阵与台账零出现，分布在 253 个类上，已并入 P21-①）**。成员数最多的类：`MovaTestKernel` 24、`MovaPreviewConfig` 19、`MovaReportName` 17、`MovaTheme` 14、`MovaKeepAliveReason` 13、`MovaSessionTally` 13、`MovaFeedItem` 12、`MovaAdConfig` 12、`MovaStrs` 12、`MovaAds` 10、`MovaEngine` 10、`MovaAutoPauseConfig` 10、`MovaPreviewService` 10、`MovaFeed` 9、`MovaCutoverConfig` 9、`MovaMiniConfig` 9、`MovaFirstFrameGate` 9、`MovaState` 9、`MovaMiniRect` 8、`MovaReportConfig` 8、`MovaSttService` 8、`MovaSlot` 8、`MovaFeedEnginePool` 7、`MovaAutoPauseGate` 7、`MovaGestureConfig` 7。完整列表见 device-trace §3（暂存区草稿，不入库）；落地时由 P21 的负责人用脚本重新生成。

**④ 改名后的成员级迁移对照**：`deprecated_names.dart` 只保证类型位置与构造器；`swapTo→cutoverTo`、`setStandby→setKeepAlive`、`swapEnabled/Phase/Phases→cutoverEnabled/Phase/Phases`（`ctl.dart:35`）、`MovaOpts(swap:/standby:)` 与 `copyWith` 旧参数、`MovaGuardAction.standby→keepAlive`、`standbyCapable→keepAliveCapable` 等**没有别名**；`MovaOpts.swap/standby`、`MovaState.standby`、`MovaHiddenMode.standby` 旧 getter/常量保留。矩阵与台账没建立成员级迁移对照（P17-① 已写明限制）。

#### 5.2.4 保活「出声 / 到期断流」计划：**未落地**

已落地的只是旧待机能力的改名。下表是 device-trace 对计划 `2026-10-27-keepalive-audible-and-disconnect.md` 的逐条核对，相关编号标「未实现」（F17-②），**不是 FAIL**：

| 计划内容 | 代码/验证证据 | 状态 |
|---|---|---|
| `MovaKeepAliveMode.audible` | `keep_alive/keep_alive.dart:32–42` 只有 muted/decodeOnly；`plan.dart:123–128` 有声流固定 muted | 未落地 |
| `MovaKeepAliveConfig.onExpire` / `MovaKeepAliveExpire` | `options/keep_alive_config.dart:39–45、50–70` 仅 maxDuration/silentStreams/allowHls/resumeTimeout/liveResumeGrace | 未落地 |
| 到期 stop/卸载并唤醒重开 | `engine.dart:1593` 所有 holding 均起 Timer；`:1617–1624` 仅 pause → exitKeepAlive → fallback；`plan.dart:195–199` 仅 failed/ended 走 reopen，maxDuration 走 reloadEdge | 未落地；暂停不能证明网络断开 |
| audible 不碰 mute、不设到期计时 | `kernel/mpv_kernel.dart:996` 的 enterKeepAlive；`engine.dart:1593` | 未落地；当前模式仍静音/统一计时 |
| `MovaHiddenMode.keepAliveAudible` | `guard/auto_pause.dart:47–65` 仅 pause/keepAlive（standby 兼容静态常量） | 未落地 |
| Task 1 真流量/音频焦点预研 | 计划附录仍「待填」 | 未找到产出；不把 `keep_alive_auto:S4` 的 CPU/流量窗口当该任务已验收 |
| `main_keepalive_audible_verify.dart` 与 Task 6 | example/lib 下未找到该文件；现有 `main_keep_alive_verify.dart:13–17` 明确「不出画面不出声」 | 未找到专项用例；真声音/真实断流均待测 |

#### 5.2.5 `gap-*` 批次：2026-10-28 补写的真机用例（**全部未上机**）

来源：本轮对 §4.2 存疑假设、§5.2 真机缺口、§3.3.S 皮肤专项补写的用例。入口 `python example/tool/coverage_gap.py <group>`，批次登记在 `example/tool/matrix_manifest.json`。离线校验：`python example/tool/run_matrix.py --check` 通过（38 批 / 135 编号 / 6 manual），`test_run_matrix.py` 20 项通过，`flutter analyze` 对 `main_coverage_gap.dart`、`verify_auto/coverage_gap*.dart` 0 issue。**这些只证明代码能编译、清单自洽，不证明判据在真机上成立**；真机出现 FAIL 时先分清是产品问题还是期望表过期。推荐上机顺序与耗时见交付说明（总计约 1.5–2 小时，不含人工判图）。

| 批次 | covers_ext | 内容 | 状态 |
|---|---|---|---|
| gap-prepare | — | 生成 ffmpeg 夹具、构建安装 | 未跑 |
| gap-assumptions | F3 A17 A7 F4 A5 H28 H20 H50 H7 H14 H26 H17 H33 | H28 默认/精确首帧两组换档、H20/H50 HLS 首次 open 与 cutover 影子 seek、H7 迟到 END_FILE、H14 手选档后连续 seek、H17 落点偏差、H33 坏地址（记录型） | 未跑 |
| gap-lifecycle | A15 A18 F5 A23 A25 F6 N20 H56 H37 H42 H43 | 小窗→PiP 互斥、二次 dispose、保活唤醒样本与待机出图 | 未跑 |
| gap-local | G3.1 | file/asset/sandbox 三种本地来源；`content://` BLOCKED | 未跑 |
| gap-formats | G3.2 C17 H31 H39 H63 | 13 个保留格式能解码、HEVC 软解、5 个排除格式给明确错误 | 未跑 |
| gap-random | G4.1 | 固定种子 80 步随机动作 + 状态/事件一致性 | 未跑 |
| gap-focus / gap-focus-gsm | G2.1 | 抢焦点取证（听感人工）；模拟器来电 | 未跑 |
| gap-network | G2.2 | 断网恢复（需 `GAP_NETWORK_URL`） | 未跑 |
| gap-screen | G2.3 H60 | 灭屏/锁屏期间音频时间线 | 未跑 |
| gap-build-variants | G1.1 G1.2 | manual：打印构建命令与判据 | BLOCKED |
| gap-skin | S1 S2 S4 S7 S9 S10 S12 S13 S14 U2 U6 U7 A10 A11 A13 A14 A16 A17 A19 C10 N16 | 5 套皮肤 42 个 case：组件树、点击/双击、锁定、按钮、全屏截图、补丁、主题注入、皮肤切换 | 未跑 |

**没做的条目与原因**（保留为缺口，不算 FAIL）：

- **S3 直播布局、S11 覆盖层、S15 已知失败交叉、S16 Mini 窗口专项、S8 长按**：本轮范围只要求 S1/S7/S9/S12/S13/S14（及 S2/S4/S10），且可控 live 夹具与 `MovaMiniWindow` 挂载不在现有 gap 服务器里。
- **S5/S6 拖动手势**：会真改系统音量与窗口亮度，没有恢复机制时不自动跑；单测侧是“全”。
- **S9 的个别按钮**：PiP 点击（会把应用留在系统小窗，已由 `gap:A15.miniPip` 覆盖）、`backToLive`（需直播源）、字幕按钮点击（需 STT 引擎，只核对“未挂载”）、Mini 窗口内的关闭链路（S16）。
- **`MovaNextUpComponent`/`MovaAdOverlayComponent`**：需 `MovaPlaylist`/`MovaAds`，没纳入 `componentName` 对账（日志里有 `notCovered` 行）。
- **人工项（BLOCKED，非 FAIL）**：H43 黑屏/冻帧判图、S2/S10 视觉判定、`G3.1.content`、G2.1 焦点归属与听感、G2.2 路由确认、G1.1/G1.2 构建变体。
- **上一轮清单之外的矩阵缺口**（G2.4–G2.9、G3.3–G3.6、G4.2–G4.4 等）本轮未要求。

**记录型 verdict 提醒**：`S7.douyin.lockObserve`、`H33.*` 的 verdict 总是 PASS，只表示“已记录”，结论看 ACTUAL 字段，不要当成对产品的通过结论。

### 5.3 假设待核对（按优先级，每条给建议落点）

| 优先 | 假设 | 现状 | 建议做法 | 建议落点文件 |
|---|---|---|---|---|
| 1 | H28 默认（无 RESTART 泵）路径的档位落地信号 | 未核对；F3/A17 280 次真机复测全带 `preciseFirstFrame:true`，默认配置零数据 **用例已写，待上机**：gap-assumptions `H28.{default,precise}.*`。 | 同一 HLS、同一判据（RT 页），引擎换成默认 `createMovaEngine()`，release 切档 N≥100（normal/paused 各半），旁路原生 RESTART/time-pos 读回对账 | `example/lib/verify_auto/coverage_new.dart`（hls case 参数化 `preciseFirstFrame:false`）；批次入 `matrix_manifest.json` |
| 2 | H20/H50 HLS 首次 open 后寄存 seek、cutover 影子 `seek(at)` | 未核对/部分核对；A7/F4 都用 mp4，HLS 路径无 `_variantLanded` 保护 **用例已写，待上机**：gap-assumptions `H20.hlsSeek`、`H50.hlsSeek`。 | HLS 源 `open` 后立刻 `seek(15s)` N≥30；再 `cutoverTo(hlsSource, at:12s)`、`MovaFeed` 续播各 N≥10；判据沿用 RT（原生 time-pos ±500ms、path） | `coverage_new.dart` 新增 `hlsOpenSeek` case；`cutover` case 的内容源换 HLS |
| 3 | H7 旧文件迟到的 END_FILE | 未核对；V4 只测 RESTART **用例已写，待上机**：gap-assumptions `H7.lateError`。 | A=404/拒连源紧接 `open(B=好源)`，间隔 0/20/50/100/200ms，N≥20，断言 B 无 `MovaPlayFailure`；A=hang 被 B 替换时记 END_FILE reason（期望 stop） | `coverage_new.dart` 的 `recovery` case 加 `lateEndFile` 变体 |
| 4 | H14/H26 用户 seek/暂停态 seek 的 buffering 边沿误降档 | 未核对；ABR 无时间窗、默认阈值 3 **用例已写，待上机**：gap-assumptions `H14.manualSeek`。 | 手选 360p 后 VOD 上连续用户 seek 10 次（不换档），记 `buffering` 上升沿数与 `MovaAbrDownShift`；播放中 pause/play ×50、暂停态 seek ×20 记 `paused-for-cache` | `coverage_new.dart` 的 `abr` case 加「用户 seek 不换档」变体 |
| 5 | H17 落点偏差 >500ms 时回声被永久抑制 | 部分核对；只测过短 GOP 40s 样本 **用例已写，待上机**：gap-assumptions `H17.{mp4,m3u8}`（偏差未超则 BLOCKED，长 GOP 样本需另造）。 | 造 GOP=10s 点播与 6s 分片 HLS，各在 GOP 中间 seek 10 次，判据：进度不冻结、`progress` 1s 内更新 | `example/tool/verify_sources/`（新增长 GOP 样本）+ `coverage_new.dart` 新 case |
| 6 | H33 `kernel.open()` 对坏地址是否抛 | 未核对；CLAUDE 与 HE/R 记录矛盾 **用例已写，待上机**：gap-assumptions `H33.*`（记录型）。 | 分 5 类坏地址（404/拒连/DNS 失败/非法 scheme/空串）各 N≥5，记 `kernel.open` 是否抛、抛什么、END_FILE 时刻 | `main_coverage_api.dart` 的 `basic`（A5 子 case） |
| 7 | A15/F5（H56）与 H37 修后复测 | 只有专项：retest.md:134–135 仅 MiniHost→PiP 衔接流程 PASS；retest.md:136 仅重复 dispose 4/4。整项其余子条件未重跑 **用例已写，待上机**：gap-lifecycle `A15.miniPip`、`H37.dispose`。 | 小窗态触发 `enterPip` 全路径 + position 连续；Android 二次 `dispose` 整项 | `main_coverage_api.dart` 的 `video` 组（miniPage→enterPip）与 `basic` 的 A23.doubleDispose |
| 8 | H42 `MovaKeepAliveResume.elapsed/signal` 真机不可信 | 已证伪（恒 grace）；产品语义未改 单测侧已补静默唤醒用例；**真机用例已写，待上机**：gap-lifecycle `H42.wake`（打印 signal/elapsed 样本）。 | 先决策产品面（是否保留 `resuming` 5s 与恒等于 `resumeTimeout` 的 elapsed），再决定改产品还是改假内核默认 | `test/support/fake_kernel.dart:410,435`（`exitRestartsVideo` 默认值）；`example/lib/verify_auto/keep_alive_auto.dart` |
| 9 | H12 半更新尺寸 → 全屏方向抖动；H53/H54 外部改音量/亮度不同步 | H12 已证伪（影响未核）；H53/H54 部分核对 | 全屏态切换到另一分辨率源，记 `MovaSizeChange` 序列与方向端口入参、`dumpsys window` 方向；`input keyevent KEYCODE_VOLUME_UP` 后读 `state.volume` | `main_coverage_api.dart` 的 `video` 组 |

落点说明：验证页都放 `example/lib/verify_auto/` 或 `example/lib/main_coverage_*.dart`，**新建 case/页，不与其他 spike 混用**；`coverage_new.dart` 与 `main_coverage_api.dart` 当前有他人未提交修改，动之前先对齐；新批次要同步 `example/tool/matrix_manifest.json`（`run_matrix.py --check` 校验）。 上表 1–8 的真机用例实际落在新页 `example/lib/main_coverage_gap.dart` 与 `verify_auto/coverage_gap*.dart`（没有改 `coverage_new.dart`），见 §5.2.5。

## 6. 待拍板记录（4 项均已决定，2026-10-28）

| # | 问题 | 现状与证据 | 选项 | 涉及文件 |
|---|---|---|---|---|
| 1 | **已决定 + 落地**：`setRate` 入口钳到 0.25–4.0，NaN 当 1.0 | 用户拍板：钳制。`movaClampRate`（`lib/src/core/model/rate.dart`，常量 `kMovaMinRate`/`kMovaMaxRate`/`kMovaNormalRate`，已从 barrel 导出），`engine.dart` 的 `setRate` 先钳再下发；`engine_rate_test.dart` 5 项。真机 H76 的“-1/0 抛 `Invalid argument(rate)`”是钳制前的行为，待复测。换源后倍速保持/复位仍无契约（A10-① 的剩余缺口）。 | —（已选 (a)） | `lib/src/core/engine.dart`（`setRate`）；`lib/src/core/model/rate.dart`；`test/core/engine_rate_test.dart`；A10-①/②、E.MovaRateChange |
| 2 | **已决定 + 落地**：上报回调抛异常被隔离 | 用户拍板：隔离。`report()` 与 `collector.dart` 的 `_emit` 加 try/catch，异常只交给钩子 `MovaHook.onError`，**不发** `MovaErrorEvent`、不写 `state.error`（避免回流 reporter 与 UI 误弹错误遮罩）；`report_engine_test.dart` :81 起三条。事件洪泛背压未测。 | —（已选 (a)） | `lib/src/core/report/collector.dart`；`lib/src/core/engine.dart`；`lib/src/core/report/report.dart:297-328` |
| 3 | **已决定**：`MovaSttService` 管线未集成，不算 FAIL | 用户拍板：矩阵标“管线未集成”，各组件（service/字幕仓库/模型提供者/音频抽取）分别验证，不要求“cue → 字幕 → SRT → 分块存储”整条集成用例，由宿主拼装。A31-① 已按此判定（组件级“全”）；真实识别仍是 A31-③ BLOCKED。 | —（已选 (a)） | `lib/src/core/stt/service.dart:91-146`；A31-①/③、C7、P10 |
| 4 | **已决定**：G1.3b 的 Web 标 N/A | 用户拍板：库依赖 `dart:io`，只做 libmpv，Web 不在验收范围。README 是否写明另行处理。 | —（已选 (a)） | `lib/src/core/preview/platform_kind.dart`；G1.3b-③ |

## 7. 矩阵修订记录（本次合并修掉的问题）

| # | 主题 | 内容 |
|---|---|---|
| 1 | 结构 | 三份旧文档（v1 `test-matrix`、v2 `matrix-v2`、`ledger`）合并为本文；原编号全部保留，按三档拆行，新增 7 个编号（见 §1）。旧文档改成指针页，历史内容见 git `dbf95f6`。 |
| 2 | 新名统一 | 全文统一 `MovaCutover*`/`MovaKeepAlive*`/`MovaAds`/`MovaFeed`/`MovaPlaylist`/`MovaMini`。**旧名别名只覆盖类型位置与构造器**；`setStandby`/`swapTo`/`MovaOpts(swap:/standby:)` 无别名。据此修正 P17 预期：旧版写「每个 `@Deprecated` typedef 可构造/可调用，行为与新名一致」，现改为「类型位置与构造器可用；静态成员不可经别名访问；成员/参数级旧名无别名」。 |
| 3 | A8 单位 | 旧 A8 写「0/中间/1」；现行引擎与真机读取用 **0–100 百分比**，`1` 是 1% 而不是满音量，系统再量化为音量级。已按 0–100 重写，并建议统一 API 单位、原生级数与事件值的描述。 |
| 4 | A18 / F16 文字过期 | 旧 A18 仍称「PiP 展开不复位」是已知缺陷、F16 要复现 `MovaWarmPlan` 方向缺失/pod 第二条广告回落。N9/N10 已引入修复覆盖；A15/F5 的 MiniHost→PiP 衔接后续也 PASS（retest.md:134–135，仅专项）。已把「旧缺陷回归」与「当前期望」拆开（A18-①/②/③、F16-①/②）。 |
| 5 | A12 / A23 改判 | fca8945 已修复 A12 下限（<1.0/NaN 钳到 1.0）与 A23 二次 dispose 幂等，retest.md:136–137 专项 PASS（A12 子项 4/4、A23 重复 dispose 4/4）。results.md 终审对这两项仍写「未改/可选」，不能再当当前结论；注意专项 PASS 不等于整项重跑。 |
| 6 | N22 manifest 理由过期 | manifest 里 N22 的 manual 理由仍是「缺 debug VM 构建」，但 rerun 已有 debug 断言通过、整项 PASS（rerun.md:200）。区分「重跑入口尚不能自动复现」与「历史从未跑过」；manifest 本次未同步。 |
| 7 | G5 过时 | G5 建议新增 `run_matrix.py`，该入口已存在（26 批次，覆盖 129 个编号 + 6 个 manual，`--check` 校验 135 编号）。G5 同时说「N22 具备 debug 路径」而 manifest 仍阻塞。G5 应改为「现有入口的判据缺口」；v2 L 规范的设备端完整日志仍未实现。 |
| 8 | F3 容差口径漂移 | 旧 F3 要求续播误差 <200ms；retest/rerun7 的 landed/paused continued 用 ±500ms 并新增读回延迟，同一个「PASS」不能直接比较。最新暂停态 60/60 没有重跑普通播放/cutover/弱网；最近完整三组仍 1/280 失败（retest5.md:209）。**需统一口径**，在统一前不把 F3/A17 写成整项 PASS。 |
| 9 | keepAlive 出声 / 到期断流 | 计划未落地（§5.2.4）。相关子点标「未实现」（F17-②、C15-② 注），不计 FAIL。 |
| 10 | 编号命名空间冲突 | `keep_alive_auto` 的 S1–S17、`main_videocontroller_verify` 的 E1–E12、`he_auto` 与 `main_review_fixes_verify*` 的 V 标签与矩阵编号无关；引用用例一律写 `suite:case`（§1）。H 表里原来的 `S4/S14/V6` 等已改成 `keep_alive_auto:S4`、`he_auto:V6`。 |
| 11 | 旧预期造成的假 FAIL | v1 修订已把 A1/A2/A5/A12/A23/C3/C6/C8/U3/U5/U6/U7/E1/N12 的预期改成现行产品行为，但 rerun 仍按旧预期写 broadcast 标志、长按倍速、弹幕发送、NextUp 数字倒计时、顶栏返回/倍速菜单等 FAIL。本文对 A1/A2/A5/C3/C6/C8/U3/U5/U6/E1/N12 的「最近结论」标「FAIL（旧预期，未按新预期复跑）」；U7/F8/N19/N22 在 rerun 差异表已 PASS。**这些不能继续按旧能力假设判产品 FAIL，也不能不经新判据实测直接改成 PASS。** |
| 12 | E 组真失败 | `E.MovaBufferChange`（快照语义，cutover 代理分两条订阅，H77）、`E.MovaSizeChange`（真实半更新 640×0，H12）、`E.MovaQualityChange`（对账差异 1/10）三个 FAIL 是真实现象，不是旧预期；其中 H12 的下游（全屏方向抖动）影响未核。 |
| 13 | C16 TLS | IP SAN 合法证书在 Android 5/5 被拒是观察到的事实；results 终审把原因归到 mbedtls 3.4，但自注凭记忆、未核源码。责任层待确认，**不能删掉合法 IP 场景来消除失败**。 |
| 14 | 台账不等于验收 | 台账的 285 行不等于 285 个类型已验收（覆盖编号/结论列大量空白）；而且**台账漏列了 33 个导出类型**（`options.dart` 再导出的各子配置：`MovaCutoverConfig`、`MovaKeepAliveConfig`、`MovaLiveConfig`、`MovaTheme`、`MovaStrs`……，盘点先发现 16 个从未被矩阵提及，传递导出闭包核对为 33 个，见 §8.3）。extension/顶层函数/`testing.dart` 导出与成员级覆盖不能由类型数代替（P20/P21）。 |
| 15 | 能力多处重复 | N20↔A25/F6/C15；C7↔A31；A17↔F3；A24↔F4/C11/N10；F7↔C13/N23；F8↔C14/N19；A26↔C12/U8/S16/P14；N18↔U9/P13；N15↔U1；N16↔U2/C10；E 表对同样事件逐型记账。共享用例可复用，但每个编号的剩余子条件要单独记录——本文用拆行解决：同一用例可挂多行，结论只在对应子点有证据时才写。 |
| 16 | manifest 与历史实跑不一致 | N18 在 manifest 仍缺 mini/guard-off 完整联动，但 he/keepAlive 子项存在。「重跑入口尚不能自动复现」≠「历史从未跑过」。 |
| 17 | 跨平台证据 | Windows 专用的 `main_win*`、route_cover 等只能支撑 G1.3b 的部分子项，**不能提高 Android 的 S/P/G 覆盖数**；有验证代码也不证明当前设备实际跑过。 |
| 18 | L 日志 | 现有验证页用 `CHECK`/`HE`/`KeepAlive` 私有前缀，与 L 规范的差距见 §2.2 第 11 条。 |
| 19 | 单测基线 | 旧 §0 写 1472；现行 1519（CLAUDE.md，2026-10-27 第四轮）。本次**没有重跑**。**2026-10-28 回填后：完整 `flutter test` `+1738: All tests passed!`（0 skip），`flutter analyze lib test` 0 issues（主会话实跑）。** |
| 20 | CLAUDE.md / SPEC 提醒（2026-10-28 已处理） | 原先这两处过期留给用户决定：`CLAUDE.md「剩余任务」①`（PiP 退出不复位）已改为已修复；`doc/SPEC.md` 清晰度节已按代码（按档位 URL 重开，而非 `videoTracks/setVideoTrack`）改写，同节 ABR 条目里的 `trackId ?? uri` 一并改为 `uri`。 |
| 21 | 单测回填（2026-10-28） | 基线 1519 → **1738**（1519→1694 +175，另有 3 项 skip；→1738 +41 新增，3 项 skip 转正）。新增 8 个测试文件：`core/engine_rate_test`、`engine_verbs_test`、`engine_streams_test`、`engine_fuzz_test`、`engine_seek_drop_test`、`core/keep_alive/engine_keep_alive_silent_wake_test`、`ui/component_tree_test`、`platform_impl/ports_impl_test`；追加用例的 11 个文件：`report_engine_test`、`method_channel_test`、`interceptor_test`、`first_frame_engine_test`、`cutover_engine_test`、`stt_test`、`ui/top_bar_test`、`hud_test`、`gesture_test`、`skin_test`、`player_test`。§5.1.1 的 P0 7 条与 P1 15 条里**只有 P1-14 未做**，P2 只有 P2-09 已补；§3 各行“单测位置/最近结论/缺口”与 §9 计数随之重算。 |
| 22 | lib 修复落地（均见 CHANGELOG `Unreleased`） | ① `setRate` 入口钳 0.25–4.0、NaN→1.0（§6 第 1 项）；② 宿主上报回调抛异常被隔离，只通知钩子 `onError`、不发 `MovaErrorEvent`（§6 第 2 项）；③ 时长未知时负向 seek 寄存前钳到 0、兑现时上下界都钳；④ dispose 后 `MovaEngine`/`MovaCutoverEngine` 全部公开动词 no-op（`open`/`enterPip`/`setWarmMute` 返回 false，异步动词 await 后复查；`MovaCutoverEngine` 销毁后不再新建影子引擎，顺带修掉一个泄漏点）；⑤ 所有点播 seek 都走“校验 + 重发”链（最多 3 次，放弃后解除回声抑制，重发中来新 seek 以新目标为准）。**DVR 直播 seek 未接校验链**，记为 P2-15。③④⑤ 是单测挖出的三条 bug。 |
| 23 | 假内核新能力 | `test/support/fake_kernel.dart` 新增 `echoSeeks`/`dropNextSeeks`/`staleEcho`/`droppedSeeks`/`honoredSeeks`（H16/H17/H18/H19）、`KeepAliveKernelStub.wakeSignal`（`none`/`size`/`restart`，默认 `none`＝真机恒 grace，H42）、`throwWhenDisposed`/`callsAfterDispose`（H37）。§4 对应行的“依赖单测”已补新测试，§4.1 的“旧影子”改为“已补贴合真机的单测，旧用例保留”。H 的真机状态本轮没变。 |
| 24 | 真机 gap 用例（未上机） | 新增 12 个 `gap-*` 批次（manifest 现 38 批 / 135 编号 / 6 manual），5 套皮肤 42 个 case。只做了离线校验，所有「最近结论」保持「未跑」。编号映射核对时改正了 7 处错配（如 `G3.2.<可支持格式>` 误挂 H31、`H42.wake` 漏挂 A25/F6）。皮肤触摸注入走 `GestureBinding.handlePointerEvent`，有意偏离 L 规范第 6 条（§2.1）。S 矩阵 80 格里 36 格标“未跑·用例已写”。 |
| 25 | §6 全部拍板 | 四项均已决定：setRate 钳制（落地）、上报回调隔离（落地）、STT 管线未集成不算 FAIL、Web 标 N/A。 |
| 26 | 文档同步 | `CLAUDE.md` 测试基线改 1738 并在最前加本轮段落、「剩余任务」① 改为已修复；`doc/SPEC.md` 清晰度节改为按档位 URL 重开。矩阵 §10 总索引格式未动（`run_matrix.py` 解析它）。 |

**更早的修订（2026-10-27 复跑后，已并入各行预期）**：A1/A2/A5/A12/A23/C3/C6/C8/U3/U5/U6/U7/E1/N12 的预期按现行产品行为修订（原预期与设计不一致，长期记 FAIL 会掩盖真回归）；A12/A23 已在库里修复，其余是契约/能力假设差异，若要改产品行为请另开决策，不在矩阵里挂 FAIL。

## 8. 附录：公开类型台账

台账 = 旧 `ledger.md` 的 285 行 + `package:mova/testing.dart` 的 `MovaTestKernel`/`MovaTesting` 2 行 = **287 行**（§8.1 的 270 行 + §8.2 的 17 行），另有 §8.3 的 33 个台账漏列类型。

**列说明**：`档位` = 该类型的验收落在哪几档（家族规则：纯数据/策略/配置 ①；事件与内核/系统交互的 ①②；渲染/手势 ①③；平台端口 ②）。`单测` = 已跟踪测试里按名字的引用（`有`＝列出前两个文件；`间接：…`＝零直接引用但有间接证据；`缺：…`＝真缺口，说明在 §5.1.2）；引用统计只证明「按名字出现过」，不证明断言充分。`真机用例` = ②/③ 档对应的矩阵行与其最近结论；① 档写「—」。`族` = 所属家族/能力编号。

### 8.1 按台账分组（270 行）

#### core/ad（7）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaAds` | class | ads.dart | ① | `core/ads_session_test.dart`；`core/ads_test.dart` 等 7 个文件 | — | P4/A27 |
| `MovaAdFailKind` | enum | fail.dart | ① | `core/ads_test.dart`；`core/ad_first_frame_test.dart` 等 4 个文件 | — | P4/A27 |
| `MovaAdFail` | class | fail.dart | ① | `core/ads_test.dart`；`core/ad_first_frame_test.dart` 等 6 个文件 | — | P4/A27 |
| `MovaAdFailAction` | enum | fail.dart | ① | `core/ads_test.dart`；`core/ad_first_frame_test.dart` 等 6 个文件 | — | P4/A27 |
| `MovaAdFailPolicy` | class | fail.dart | ① | `core/ads_test.dart`；`core/ad_first_frame_test.dart` 等 5 个文件 | — | P4/A27 |
| `MovaAdRetrySkip` | class | fail.dart | ① | `core/ads_test.dart`；`core/openness_ad_test.dart` 等 4 个文件 | — | P4/A27 |
| `MovaAdAbandonPod` | class | fail.dart | ① | `core/ads_test.dart`；`core/openness_ad_test.dart` 等 4 个文件 | — | P4/A27 |

#### core（2）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaApi` | class | api.dart | ①②③ | `core/engine_test.dart`；`core/openness_cutover_test.dart` 等 11 个文件 | A2-②（FAIL）、A5-②（FAIL）、A6-②（PASS）、A7-②（PASS）、A23-②（PASS） | P1 |
| `MovaEngine` | class | engine.dart | ①②③ | `core/audio_only_scenarios_test.dart`；`core/bus_test.dart` 等 23 个文件 | A2-②（FAIL）、A5-②（FAIL）、A6-②（PASS）、A7-②（PASS）、A23-②（PASS） | P1 |

#### core/events（36）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaEvent` | class | events.dart | ① | `core/audio_only_scenarios_test.dart`；`core/engine_test.dart` 等 17 个文件 | — | P2/E |
| `MovaReady` | class | events.dart | ② | `core/recovery/engine_recovery_test.dart`；`core/report/translator_test.dart`；`core/engine_verbs_test.dart` | E.MovaReady-②（PASS） | E.MovaReady |
| `MovaSourceChange` | class | events.dart | ① | `core/engine_test.dart`；`core/openness_report_test.dart` 等 5 个文件 | — | E.MovaSourceChange |
| `MovaPlay` | class | events.dart | ② | `core/cutover/cutover_engine_test.dart`；`core/report/collector_test.dart` 等 5 个文件；`core/engine_verbs_test.dart` | E.MovaPlay-②（PASS） | E.MovaPlay |
| `MovaPause` | class | events.dart | ② | `core/report/collector_test.dart`；`core/report/translator_test.dart`；`core/engine_verbs_test.dart` | E.MovaPause-②（PASS） | E.MovaPause |
| `MovaDone` | class | events.dart | ② | `core/ads_test.dart`；`core/ad_first_frame_test.dart` 等 9 个文件；`core/engine_verbs_test.dart` | E.MovaDone-②（PASS） | E.MovaDone |
| `MovaSeek` | class | events.dart | ① | `core/report/translator_test.dart`；`core/engine_verbs_test.dart` | — | E.MovaSeek |
| `MovaSeeked` | class | events.dart | ② | `core/report/translator_test.dart`；`core/engine_verbs_test.dart` | E.MovaSeeked-②（PASS） | E.MovaSeeked |
| `MovaBufferChange` | class | events.dart | ② | `core/recovery/recovery_fixes_test.dart`；`core/report/stats_probe_test.dart` 等 4 个文件 | E.MovaBufferChange-②（FAIL） | E.MovaBufferChange |
| `MovaDurationChange` | class | events.dart | ② | `core/live/duration_throttle_test.dart`；`core/report/translator_test.dart` 等 3 个文件 | E.MovaDurationChange-②（PASS） | E.MovaDurationChange |
| `MovaFirstFrame` | class | events.dart | ② | `core/ad_first_frame_test.dart`；`core/ad_stale_first_frame_test.dart` 等 5 个文件 | E.MovaFirstFrame-②（PASS） | E.MovaFirstFrame |
| `MovaSizeChange` | class | events.dart | ② | `core/report/translator_test.dart`；`core/engine_verbs_test.dart` | E.MovaSizeChange-②（FAIL） | E.MovaSizeChange |
| `MovaVolumeChange` | class | events.dart | ① | `core/engine_test.dart`；`core/report/translator_test.dart` | — | E.MovaVolumeChange |
| `MovaBrightChange` | class | events.dart | ① | `core/engine_test.dart`；`core/report/translator_test.dart` | — | E.MovaBrightChange |
| `MovaRateChange` | class | events.dart | ① | `core/engine_rate_test.dart`；`core/engine_fuzz_test.dart` | — | E.MovaRateChange |
| `MovaQualityListChange` | class | events.dart | ① | `core/recovery/review_regression_test.dart` | — | E.MovaQualityListChange |
| `MovaQualityChange` | class | events.dart | ① | `core/engine_test.dart`；`core/report/bitrate_test.dart` 等 3 个文件 | — | E.MovaQualityChange |
| `MovaAbrDownShift` | class | events.dart | ② | `core/audio_only_scenarios_test.dart`；`core/engine_test.dart` 等 5 个文件 | E.MovaAbrDownShift-②（PASS） | E.MovaAbrDownShift |
| `MovaFitChange` | class | events.dart | ① | `core/engine_test.dart`；`core/engine_verbs_test.dart` | — | E.MovaFitChange |
| `MovaZoomChange` | class | events.dart | ① | `core/report/translator_test.dart`；`core/engine_verbs_test.dart` | — | E.MovaZoomChange |
| `MovaLockChange` | class | events.dart | ① | `core/engine_verbs_test.dart` | — | E.MovaLockChange |
| `MovaFullScreenChange` | class | events.dart | ① | `core/engine_test.dart`；`core/report/translator_test.dart` | — | E.MovaFullScreenChange |
| `MovaOrientationChange` | class | events.dart | ① | `core/engine_test.dart` | — | E.MovaOrientationChange |
| `MovaPipChange` | class | events.dart | ② | `core/engine_test.dart`；`core/report/translator_test.dart` | E.MovaPipChange-②（PASS） | E.MovaPipChange |
| `MovaMiniChange` | class | events.dart | ① | `core/engine_test.dart`；`core/report/translator_test.dart` | — | E.MovaMiniChange |
| `MovaTimeShiftChange` | class | events.dart | ① | `core/engine_test.dart`；`core/report/translator_test.dart` | — | E.MovaTimeShiftChange |
| `MovaLiveEdgeReach` | class | events.dart | ② | `core/engine_test.dart`；`core/keep_alive/engine_keep_alive_wake_test.dart` 等 3 个文件 | E.MovaLiveEdgeReach-②（PASS） | E.MovaLiveEdgeReach |
| `MovaPreviewBlock` | class | events.dart | ① | `core/engine_test.dart` | — | E.MovaPreviewBlock |
| `MovaSttBlock` | class | events.dart | ① | `core/audio_only_scenarios_test.dart`；`core/engine_test.dart` | — | E.MovaSttBlock |
| `MovaCutoverChange` | class | events.dart | ① | `core/report/translator_test.dart`；`core/cutover/cutover_engine_test.dart` | — | E.MovaCutoverChange |
| `MovaErrorEvent` | class | events.dart | ② | `core/ads_test.dart`；`core/engine_test.dart` 等 9 个文件 | E.MovaErrorEvent-②（PASS） | E.MovaErrorEvent |
| `MovaPlayFailure` | class | events.dart | ② | `core/keep_alive/engine_keep_alive_rules_test.dart`；`core/keep_alive/engine_keep_alive_wake_test.dart` 等 8 个文件 | E.MovaPlayFailure-②（PASS） | E.MovaPlayFailure |
| `MovaRecovered` | class | events.dart | ② | `core/recovery/engine_recovery_test.dart`；`core/recovery/live_reconnect_test.dart` 等 4 个文件 | E.MovaRecovered-②（PASS） | E.MovaRecovered |
| `MovaFailover` | class | events.dart | ① | `core/recovery/failover_test.dart` | — | E.MovaFailover |
| `MovaKeepAliveChange` | class | events.dart | ① | `core/openness_keep_alive_test.dart`；`core/cutover/cutover_keep_alive_test.dart` 等 3 个文件 | — | E.MovaKeepAliveChange |
| `MovaKeepAliveResume` | class | events.dart | ② | `core/openness_keep_alive_test.dart`；`core/keep_alive/engine_keep_alive_wake_test.dart` | E.MovaKeepAliveResume-②（PASS） | E.MovaKeepAliveResume |

#### core/feed（7）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaEngineFactory` | typedef | engine_pool.dart | ①③ | `core/engine_pool_test.dart`；`core/feed_test.dart` | A29-③（PASS） | P11/A29 |
| `MovaFeedSlot` | class | engine_pool.dart | ①③ | 间接：engine_pool_test:75-79 `pool.slotFor(i)?.ready` | A29-③（PASS） | P11/A29 |
| `MovaFeedEnginePool` | class | engine_pool.dart | ①③ | `core/engine_pool_test.dart`；`core/feed_test.dart` 等 4 个文件 | A29-③（PASS） | P11/A29 |
| `MovaFeedLoader` | typedef | feed.dart | ①③ | `core/feed_test.dart` | A29-③（PASS） | P11/A29 |
| `MovaFeed` | class | feed.dart | ①③ | `core/feed_test.dart`；`ui/douyin_skin_test.dart` 等 3 个文件 | A29-③（PASS） | P11/A29 |
| `MovaFeedPrefetcher` | class | feed_prefetcher.dart | ①③ | `core/feed_test.dart` | A29-③（PASS） | P11/A29 |
| `MovaNetworkWarmFeedPrefetcher` | class | feed_prefetcher.dart | ①③ | `core/feed_prefetcher_test.dart` | A29-③（PASS） | P11/A29 |

#### core/guard（6）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaHideReason` | enum | auto_pause.dart | ①② | `core/guard/auto_pause_gate_test.dart`；`ui/review_regression_test.dart` | U9-②（PASS） | P13/N18 |
| `MovaLiveResume` | enum | auto_pause.dart | ①② | `core/guard/auto_pause_gate_test.dart` | U9-②（PASS） | P13/N18 |
| `MovaHiddenMode` | enum | auto_pause.dart | ①② | `deprecated_names_test.dart`；`core/openness_keep_alive_test.dart` 等 5 个文件 | U9-②（PASS） | P13/N18 |
| `MovaAutoPauseConfig` | class | auto_pause.dart | ①② | `core/openness_keep_alive_test.dart`；`core/guard/auto_pause_gate_test.dart` 等 5 个文件 | U9-②（PASS） | P13/N18 |
| `MovaGuardAction` | enum | auto_pause.dart | ①② | `core/guard/auto_pause_gate_test.dart`；`ui/review_regression_test.dart` | U9-②（PASS） | P13/N18 |
| `MovaAutoPauseGate` | class | auto_pause.dart | ①② | `core/guard/auto_pause_gate_test.dart`；`ui/review_regression_test.dart` | U9-②（PASS） | P13/N18 |

#### core/interceptor（2）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaHook` | class | interceptor.dart | ① | `core/engine_dispose_race_test.dart`；`core/engine_test.dart` 等 6 个文件 | — | P13/A32 |
| `MovaHookChain` | class | interceptor.dart | ① | `core/interceptor_test.dart` | — | P13/A32 |

#### core/mini（4）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaMiniRect` | class | placement.dart | ① | `core/openness_mini_test.dart`；`core/mini/placement_test.dart` 等 4 个文件 | — | P14/A26 |
| `MovaMiniInsets` | class | placement.dart | ① | `core/openness_mini_test.dart`；`core/mini/placement_test.dart` 等 3 个文件 | — | P14/A26 |
| `MovaMiniPlacement` | class | placement.dart | ① | `core/openness_mini_test.dart`；`ui/mini/mini_window_test.dart` | — | P14/A26 |
| `MovaCornerSnap` | class | placement.dart | ① | `core/openness_mini_test.dart`；`core/options_test.dart` 等 3 个文件 | — | P14/A26 |

#### core/model（14）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaAdBreakKind` | enum | ad.dart | ① | `core/ads_session_test.dart`；`core/ads_test.dart` 等 10 个文件 | — | P1 |
| `MovaAdBreak` | class | ad.dart | ① | `core/ads_session_test.dart`；`core/ads_test.dart` 等 10 个文件 | — | P1 |
| `MovaAdEventType` | enum | ad.dart | ① | `core/ads_test.dart`；`ui/ad_overlay_test.dart` | — | P1 |
| `MovaAdEvent` | class | ad.dart | ① | `core/ads_test.dart`；`ui/ad_overlay_test.dart` | — | P1 |
| `MovaDanmakuItem` | class | danmaku.dart | ①③ | `core/model_test.dart`；`core/options_test.dart` 等 3 个文件 | C6-③（FAIL） | P1 |
| `MovaFeedLikeChange` | typedef | feed_item.dart | ① | 间接：feed_test:275 toggleLike fires onLikeChanged；feed_social_test:13 | — | P1 |
| `MovaFeedItem` | class | feed_item.dart | ① | `core/feed_test.dart`；`core/model_test.dart` 等 5 个文件 | — | P1 |
| `MovaFit` | enum | fit.dart | ①③ | `core/audio_only_scenarios_test.dart`；`core/engine_pool_test.dart` 等 15 个文件 | A11-③（PASS） | P1 |
| `MovaOrientation` | enum | orientation.dart | ①② | `core/engine_dispose_race_test.dart`；`core/engine_test.dart` 等 6 个文件 | A16-②（PASS） | P1 |
| `MovaPlaylistItem` | class | playlist.dart | ① | `core/playlist_test.dart`；`ui/next_up_test.dart` | — | P1 |
| `MovaQuality` | class | quality.dart | ①② | `core/audio_only_scenarios_test.dart`；`core/engine_test.dart` 等 10 个文件 | A17-②（FAIL） | P1 |
| `MovaStreamType` | enum | source.dart | ① | `core/engine_source_options_test.dart`；`core/engine_test.dart` 等 25 个文件 | — | P1 |
| `MovaSource` | class | source.dart | ①② | `core/ads_session_test.dart`；`core/ads_test.dart` 等 58 个文件 | C17-②（PASS） | P1 |
| `MovaSourceResolver` | typedef | source.dart | ①② | `core/openness_ad_test.dart` | C17-②（PASS） | P1 |

#### core/options（1）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaOpts` | class | options.dart | ① | `deprecated_names_test.dart`；`core/ads_session_test.dart` 等 49 个文件 | — | P3/C |

#### core/platform（10）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaBrightPort` | class | ports.dart | ② | `core/engine_test.dart`；`platform_impl/wiring_test.dart` | A9-②（PASS） | P12 |
| `MovaVolumePort` | class | ports.dart | ② | `core/engine_test.dart` | A8-②（PASS） | P12 |
| `MovaPipPort` | class | ports.dart | ② | `core/engine_test.dart` | A18-②（PASS） | P12 |
| `MovaPipObservable` | class | ports.dart | ② | `core/engine_test.dart` | A18-②（PASS） | P12 |
| `MovaOrientationPort` | class | ports.dart | ② | `core/engine_dispose_race_test.dart`；`core/engine_test.dart` 等 3 个文件 | A16-②（PASS） | P12 |
| `MovaFallbackBrightnessPort` | class | ports.dart | ① | `core/ports_test.dart`；`platform_impl/wiring_test.dart` 等 3 个文件 | — | P12 |
| `MovaFallbackVolumePort` | class | ports.dart | ① | 缺：同族的 `MovaFallbackBrightnessPort` 有测（ports_test:5），这个漏了 | — | P12 |
| `MovaCallbackVolumePort` | class | ports.dart | ① | `core/engine_test.dart`；`core/cutover/cutover_warm_mute_test.dart` | — | P12 |
| `MovaNoopPipPort` | class | ports.dart | ① | `core/ports_test.dart`；`platform_impl/wiring_test.dart` 等 3 个文件 | — | P12 |
| `MovaNoopOrientationPort` | class | ports.dart | ① | `platform_impl/wiring_test.dart`；`testing/testing_test.dart` | — | P12 |

#### core/playlist（1）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaPlaylist` | class | playlist.dart | ①② | `core/playlist_test.dart`；`ui/next_up_test.dart` | A28-②（PASS） | P11/A28 |

#### core/preview（24）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaPreviewApi` | class | api.dart | ① | 间接：抽象；经实现类 `MovaPreviewService`：core/preview/service_test.dart 21 项 | — | P9/A30 |
| `MovaThumbCache` | class | cache.dart | ① | `core/openness_preview_test.dart`；`core/preview/two_level_cache_test.dart` | — | P9/A30 |
| `MovaMemoryThumbCache` | class | cache.dart | ① | `core/preview/cache_test.dart`；`core/preview/service_test.dart` 等 3 个文件 | — | P9/A30 |
| `MovaThumbDirProvider` | class | dir_provider.dart | ① | `core/openness_preview_test.dart` | — | P9/A30 |
| `MovaFixedThumbDirProvider` | class | dir_provider.dart | ① | `core/openness_preview_test.dart`；`core/preview/disk_cache_test.dart` | — | P9/A30 |
| `MovaDiskThumbCache` | class | disk_cache.dart | ① | `core/preview/disk_cache_test.dart` | — | P9/A30 |
| `MovaFramePuller` | class | extractor.dart | ①② | `core/openness_preview_test.dart`；`core/preview/extractor_test.dart` 等 3 个文件 | A30-②（PASS） | P9/A30 |
| `MovaPullerThumbSource` | class | extractor.dart | ①② | `core/preview/extractor_test.dart` | A30-②（PASS） | P9/A30 |
| `MovaHttpFetch` | class | fetcher.dart | ① | `core/engine_test.dart`；`core/stt_model_provider_test.dart` 等 4 个文件 | — | P9/A30 |
| `MovaIoHttpFetcher` | class | fetcher.dart | ① | 缺：预览/清晰度所用的默认 HTTP 取数实现，没有任何用例（可用本地 `HttpServer`） | — | P9/A30 |
| `MovaCacheKeyBuilder` | typedef | hash.dart | ① | 间接：service_test:387 custom cacheKeyBuilder | — | P9/A30 |
| `MovaThumbCrop` | class | models.dart | ① | `core/preview/models_test.dart`；`core/preview/service_test.dart` 等 5 个文件 | — | P9/A30 |
| `MovaThumb` | class | models.dart | ① | `core/openness_preview_test.dart`；`core/preview/models_test.dart` 等 4 个文件 | — | P9/A30 |
| `MovaThumbCue` | class | models.dart | ① | `core/preview/models_test.dart` | — | P9/A30 |
| `MovaThumbIndex` | class | models.dart | ① | `core/preview/models_test.dart` | — | P9/A30 |
| `MovaPreviewNet` | enum | net_probe.dart | ① | `core/engine_test.dart`；`core/openness_preview_test.dart` 等 5 个文件 | — | P9/A30 |
| `MovaNetProbe` | class | net_probe.dart | ① | `core/openness_preview_test.dart`；`core/options_test.dart` 等 5 个文件 | — | P9/A30 |
| `MovaAlwaysAllowNetProbe` | class | net_probe.dart | ① | `core/openness_preview_test.dart`；`core/options_test.dart` 等 5 个文件 | — | P9/A30 |
| `MovaPlatformKind` | enum | platform_kind.dart | ① | `core/openness_preview_test.dart`；`core/options_test.dart` 等 3 个文件 | — | P9/A30 |
| `MovaPreviewService` | class | service.dart | ① | `core/preview/service_test.dart` | — | P9/A30 |
| `MovaThumbSource` | class | source.dart | ① | `core/openness_preview_test.dart`；`core/preview/service_test.dart` | — | P9/A30 |
| `MovaTwoLevelCache` | class | two_level_cache.dart | ① | `core/preview/two_level_cache_test.dart` | — | P9/A30 |
| `MovaVttUrlSolver` | typedef | vtt_source.dart | ① | 间接：vtt_source_test:134,:146 custom resolver | — | P9/A30 |
| `MovaVttThumbSource` | class | vtt_source.dart | ① | `core/preview/vtt_source_test.dart` | — | P9/A30 |

#### core/recovery（10）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaPlayFailKind` | enum | fail.dart | ①② | `core/keep_alive/engine_keep_alive_wake_test.dart`；`core/recovery/engine_recovery_test.dart` 等 8 个文件 | F8-②（PASS） | P7/F8 |
| `MovaPlayFail` | class | fail.dart | ①② | `core/openness_host_test.dart`；`core/recovery/engine_recovery_test.dart` 等 4 个文件 | F8-②（PASS） | P7/F8 |
| `MovaRecoveryAction` | enum | fail.dart | ①② | `core/recovery/engine_recovery_test.dart`；`core/recovery/failover_test.dart` 等 4 个文件 | F8-②（PASS） | P7/F8 |
| `MovaRecoveryDecision` | class | fail.dart | ①② | `core/openness_host_test.dart`；`core/recovery/engine_recovery_test.dart` | F8-②（PASS） | P7/F8 |
| `MovaRecoveryPolicy` | class | fail.dart | ①② | `core/openness_host_test.dart`；`core/recovery/engine_recovery_test.dart` 等 3 个文件 | F8-②（PASS） | P7/F8 |
| `MovaRetryThenFailover` | class | fail.dart | ①② | `core/recovery/config_test.dart`；`core/recovery/live_reconnect_test.dart` 等 6 个文件 | F8-②（PASS） | P7/F8 |
| `MovaLiveReconnect` | class | fail.dart | ①② | `core/recovery/live_reconnect_test.dart` | F8-②（PASS） | P7/F8 |
| `MovaDefaultRecovery` | class | fail.dart | ①② | `core/openness_host_test.dart`；`core/recovery/config_test.dart` 等 3 个文件 | F8-②（PASS） | P7/F8 |
| `MovaFailoverOnly` | class | fail.dart | ①② | `core/engine_source_options_test.dart`；`core/recovery/config_test.dart` 等 8 个文件 | F8-②（PASS） | P7/F8 |
| `MovaGiveUpError` | class | fail.dart | ①② | `core/interceptor_test.dart`；`core/openness_host_test.dart` 等 7 个文件 | F8-②（PASS） | P7/F8 |

#### core/render（2）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaFirstFrameSignal` | enum | first_frame.dart | ①② | `core/ad_first_frame_test.dart`；`core/ad_stale_first_frame_test.dart` 等 5 个文件 | N12-②（FAIL） | P1/N12 |
| `MovaFirstFrameGate` | class | first_frame.dart | ①② | `core/render/first_frame_test.dart` | N12-②（FAIL） | P1/N12 |

#### core/report（19）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaErrorVerdict` | class | error_policy.dart | ① | `core/openness_report_test.dart`；`core/report/config_test.dart` | — | P8/F7 |
| `MovaErrorPolicy` | class | error_policy.dart | ① | `core/openness_report_test.dart`；`core/report/config_test.dart` | — | P8/F7 |
| `MovaPrefixError` | class | error_policy.dart | ① | `core/openness_report_test.dart`；`core/report/config_test.dart` 等 3 个文件 | — | P8/F7 |
| `MovaReportKind` | enum | report.dart | ① | `core/report/report_engine_test.dart`；`core/report/translator_test.dart` | — | P8/F7 |
| `MovaReportPriority` | enum | report.dart | ① | `core/report/report_engine_test.dart`；`core/report/translator_test.dart` | — | P8/F7 |
| `MovaReportName` | class | report.dart | ① | `core/report/bitrate_test.dart`；`core/report/collector_test.dart` 等 9 个文件 | — | P8/F7 |
| `MovaReportEvent` | class | report.dart | ① | `core/openness_report_test.dart`；`core/report/bitrate_test.dart` 等 7 个文件 | — | P8/F7 |
| `MovaReporter` | class | report.dart | ① | 间接：经 `MovaCallbackReporter` 被 report_engine_test:10-71、collector_test 使用 | — | P8/F7 |
| `MovaCallbackReporter` | class | report.dart | ① | `core/openness_report_test.dart`；`core/report/bitrate_test.dart` 等 7 个文件 | — | P8/F7 |
| `MovaSessionEnd` | enum | session.dart | ① | `core/report/session_test.dart` | — | P8/F7 |
| `MovaSessionTally` | class | session.dart | ① | `core/report/session_test.dart` | — | P8/F7 |
| `MovaSessionIdFactory` | typedef | session_id.dart | ① | `core/report/session_id_test.dart` | — | P8/F7 |
| `MovaStall` | class | stall.dart | ①② | `core/openness_report_test.dart` | F7-②（PASS） | P8/F7 |
| `MovaStallPolicy` | class | stall.dart | ①② | `core/openness_report_test.dart` | F7-②（PASS） | P8/F7 |
| `MovaEdgeStall` | class | stall.dart | ①② | `core/openness_report_test.dart`；`core/report/config_test.dart` 等 3 个文件 | F7-②（PASS） | P8/F7 |
| `MovaLogLine` | class | stats_probe.dart | ①② | `core/report/stats_probe_test.dart`；`core/report/truncation_test.dart` | F7-②（PASS） | P8/F7 |
| `MovaStatsSnapshot` | class | stats_probe.dart | ①② | `core/report/bitrate_test.dart`；`core/report/stats_probe_test.dart` | F7-②（PASS） | P8/F7 |
| `MovaEndFileReason` | enum | stats_probe.dart | ①② | `core/keep_alive/engine_keep_alive_rules_test.dart`；`core/kernel/mpv_kernel_events_test.dart` 等 7 个文件 | F7-②（PASS） | P8/F7 |
| `MovaStatsProbe` | class | stats_probe.dart | ①② | `core/report/stats_probe_test.dart` | F7-②（PASS） | P8/F7 |

#### core/keep_alive（4）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaKeepAlivePhase` | enum | keep_alive.dart | ①② | `deprecated_names_test.dart`；`core/openness_keep_alive_test.dart` 等 11 个文件 | A25-②（PASS） | P6/A25 |
| `MovaKeepAliveMode` | enum | keep_alive.dart | ①② | `deprecated_names_test.dart`；`core/cutover/cutover_keep_alive_test.dart` 等 7 个文件 | A25-②（PASS） | P6/A25 |
| `MovaKeepAliveReason` | enum | keep_alive.dart | ①② | `core/cutover/cutover_keep_alive_test.dart`；`core/keep_alive/engine_keep_alive_enter_test.dart` 等 3 个文件 | A25-②（PASS） | P6/A25 |
| `MovaKeepAlive` | class | keep_alive.dart | ①② | `core/cutover/cutover_keep_alive_test.dart` | A25-②（PASS） | P6/A25 |

#### core/state（4）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaProg` | class | progress.dart | ①② | `core/ads_session_test.dart`；`core/ads_test.dart` 等 17 个文件 | A2-②（FAIL） | P1/A2 |
| `MovaState` | class | state.dart | ①② | `deprecated_names_test.dart`；`core/api_test.dart` 等 26 个文件 | A2-②（FAIL） | P1/A2 |
| `MovaHud` | enum | ui_state.dart | ①③ | `core/engine_test.dart`；`core/state_test.dart` 等 5 个文件 | P16-③（未跑） | P1/A2 |
| `MovaUiState` | class | ui_state.dart | ① | `core/engine_test.dart`；`core/state_test.dart` 等 5 个文件 | — | P1/A2 |

#### core/stt（21）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaSttApi` | class | api.dart | ① | 间接：抽象；经 `MovaEngine` 的 stt 面：core/engine_test.dart :942-1094 | — | P10/A31 |
| `MovaAudioPuller` | class | audio_extractor.dart | ①③ | 间接：仅 `MovaAudioExtractor` 实现它，后者无测（见 4.1）——**抽象本身无可测** | A31-③（BLOCKED） | P10/A31 |
| `MovaSttCue` | class | cue.dart | ① | `core/engine_test.dart`；`core/srt_test.dart` 等 6 个文件 | — | P10/A31 |
| `MovaSttModelDirProvider` | class | model_dir_provider.dart | ① | 间接：经 `MovaFixedStt*DirProvider` 在 stt_subtitle_store_test:20、stt_model_provider_test:58 使用 | — | P10/A31 |
| `MovaFixedSttModelDirProvider` | class | model_dir_provider.dart | ① | `core/stt_model_provider_test.dart` | — | P10/A31 |
| `MovaSttModelProg` | class | model_provider.dart | ① | `core/stt_model_provider_test.dart` | — | P10/A31 |
| `MovaSttModelLoadError` | class | model_provider.dart | ① | `core/stt_model_provider_test.dart` | — | P10/A31 |
| `MovaSttModelProvider` | class | model_provider.dart | ① | 间接：经 `MovaSttModelLoader` 在 stt_model_provider_test:53-148 使用 | — | P10/A31 |
| `MovaSttModelLoader` | class | model_provider.dart | ① | `core/stt_model_provider_test.dart` | — | P10/A31 |
| `MovaSttModelFile` | class | model_spec.dart | ① | `core/stt_model_provider_test.dart` | — | P10/A31 |
| `MovaSttModelSpec` | class | model_spec.dart | ① | `core/stt_model_provider_test.dart` | — | P10/A31 |
| `MovaSttModelFiles` | class | model_spec.dart | ① | 缺：模型文件集合值对象，stt_model_provider_test 只用 MovaSttModelFile/Spec | — | P10/A31 |
| `MovaSttEngine` | class | port.dart | ① | `core/engine_test.dart` | — | P10/A31 |
| `MovaNoopSttEngine` | class | port.dart | ① | `core/stt_test.dart` | — | P10/A31 |
| `MovaSttChunkSubtitleStore` | class | chunk_subtitle_store.dart | ① | 间接：经 `MovaFileSttSubtitleStore` 等实现：stt_subtitle_store_test:19-76、stt_chunk_subtitle_store_test:19-81 | — | P10/A31 |
| `MovaFileSttChunkSubtitleStore` | class | chunk_subtitle_store.dart | ① | `core/stt_chunk_subtitle_store_test.dart` | — | P10/A31 |
| `MovaSttService` | class | service.dart | ① | `core/stt_test.dart` | — | P10/A31 |
| `MovaSttSubtitleDirProvider` | class | subtitle_dir_provider.dart | ① | 间接：经 `MovaFixedStt*DirProvider` 在 stt_subtitle_store_test:20、stt_model_provider_test:58 使用 | — | P10/A31 |
| `MovaFixedSttSubtitleDirProvider` | class | subtitle_dir_provider.dart | ① | `core/stt_chunk_subtitle_store_test.dart`；`core/stt_subtitle_store_test.dart` | — | P10/A31 |
| `MovaSttSubtitleStore` | class | subtitle_store.dart | ① | 间接：经 `MovaFileSttSubtitleStore` 等实现：stt_subtitle_store_test:19-76、stt_chunk_subtitle_store_test:19-81 | — | P10/A31 |
| `MovaFileSttSubtitleStore` | class | subtitle_store.dart | ① | `core/stt_subtitle_store_test.dart` | — | P10/A31 |

#### core/cutover（12）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaCutoverPhase` | enum | ctl.dart | ①② | `core/cutover/cutover_engine_defects_test.dart`；`core/cutover/cutover_engine_test.dart` 等 4 个文件 | A24-②（PASS） | P5/A24 |
| `MovaCutover` | class | ctl.dart | ①② | `core/ads_test.dart` | A24-②（PASS） | P5/A24 |
| `MovaWarmPlan` | class | plan.dart | ①② | `core/openness_ad_test.dart`；`core/options_test.dart` 等 6 个文件 | A24-②（PASS） | P5/A24 |
| `MovaCutoverEngine` | class | cutover_engine.dart | ①② | `core/openness_cutover_test.dart`；`core/cutover/cutover_engine_defects_test.dart` 等 8 个文件 | A24-②（PASS） | P5/A24 |
| `MovaWarmCue` | class | trigger.dart | ①② | `core/openness_cutover_test.dart`；`core/cutover/cutover_engine_defects_test.dart` 等 5 个文件 | A24-②（PASS） | P5/A24 |
| `MovaWarmTrigger` | class | trigger.dart | ①② | `core/openness_cutover_test.dart`；`core/cutover/cutover_engine_test.dart` | A24-②（PASS） | P5/A24 |
| `MovaLeadWarm` | class | trigger.dart | ①② | `core/openness_ad_test.dart`；`core/options_test.dart` 等 4 个文件 | A24-②（PASS） | P5/A24 |
| `MovaEagerWarm` | class | trigger.dart | ①② | `core/ads_test.dart`；`core/openness_ad_test.dart` 等 7 个文件 | A24-②（PASS） | P5/A24 |
| `MovaWarmSignal` | class | warm.dart | ①② | `core/openness_cutover_test.dart`；`core/cutover/cutover_engine_test.dart` 等 3 个文件 | A24-②（PASS） | P5/A24 |
| `MovaWarmVerdict` | enum | warm.dart | ①② | `core/openness_cutover_test.dart`；`core/cutover/cutover_engine_test.dart` 等 3 个文件 | A24-②（PASS） | P5/A24 |
| `MovaWarmPolicy` | class | warm.dart | ①② | `core/openness_cutover_test.dart`；`core/cutover/cutover_engine_test.dart` | A24-②（PASS） | P5/A24 |
| `MovaBufferWarm` | class | warm.dart | ①② | `core/openness_ad_test.dart`；`core/openness_cutover_test.dart` 等 6 个文件 | A24-②（PASS） | P5/A24 |

#### platform_impl（10）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaAudioExtractor` | class | mpv_audio_extractor_impl.dart | ①③ | 缺：依赖 libmpv，属真机；但参数/路径拼装可抽纯函数单测（待确认） | A31-③（BLOCKED） | P12 |
| `MovaFrameExtractor` | class | mpv_extractor_impl.dart | ①② | `core/openness_audio_test.dart`；`platform_impl/wiring_test.dart` | A30-②（PASS） | P12 |
| `MovaConnectivityNetProbe` | class | net_probe_impl.dart | ①② | `platform_impl/net_probe_impl_test.dart`；`platform_impl/wiring_test.dart` | A30-②（PASS） | P12 |
| `MovaTempSttModelDirProvider` | class | stt_model_dir_impl.dart | ① | 缺：同上 | — | P12 |
| `MovaTempSttSubtitleDirProvider` | class | stt_subtitle_dir_impl.dart | ① | 缺：同上 | — | P12 |
| `MovaTempThumbDirProvider` | class | thumb_dir_impl.dart | ① | 缺：三个 Temp 目录提供者均零引用（`MovaFixed*` 版本被测） | — | P12 |
| `MovaScreenBrightnessPort` | class | brightness_impl.dart | ② | `platform_impl/wiring_test.dart` | A9-②（PASS） | P12 |
| `MovaSystemChromeOrientationPort` | class | orientation_impl.dart | ② | `platform_impl/wiring_test.dart` | A16-②（PASS） | P12 |
| `MovaChannelPipPort` | class | pip_impl.dart | ② | `platform_impl/wiring_test.dart` | A18-②（PASS） | P12 |
| `MovaSystemVolumePort` | class | volume_impl.dart | ② | `platform_impl/ports_impl_test.dart` | A8-②（PASS） | P12 |

#### ui/components（42）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaAdOverlayComponent` | class | ad_overlay.dart | ①③ | `ui/ad_overlay_test.dart` | P15-③（未跑） | P15 |
| `MovaBottomBarComponent` | class | bottom_bar.dart | ①③ | `ui/bottom_bar_test.dart`；`ui/live_bar_test.dart` | P15-③（未跑） | P15 |
| `MovaPositionLabelComponent` | class | bottom_bar.dart | ①③ | 间接：bottom_bar_test:28 position label follows progress（经 MovaBottomBarComponent） | P15-③（未跑） | P15 |
| `MovaDurationLabelComponent` | class | bottom_bar.dart | ①③ | 间接：bottom_bar_test:21（duration=0 禁用，经 BottomBar）——**文案本身未直接断言** | P15-③（未跑） | P15 |
| `MovaSeekBarComponent` | class | bottom_bar.dart | ①③ | 间接：bottom_bar_test:11、live_bar_test:94 | P15-③（未跑） | P15 |
| `MovaLiveBadgeComponent` | class | bottom_bar.dart | ①③ | 间接：live_bar_test:31,:48,:61,:73 | P15-③（未跑） | P15 |
| `MovaTimeshiftLabelComponent` | class | bottom_bar.dart | ①③ | 间接：live_bar_test:31,:48,:61,:73 | P15-③（未跑） | P15 |
| `MovaBackToLiveComponent` | class | bottom_bar.dart | ①③ | 间接：live_bar_test:31,:48,:61,:73 | P15-③（未跑） | P15 |
| `MovaCenterPlayComponent` | class | center_play.dart | ①③ | 间接：audio_only_interaction_test:54,:87；mini_skin_test:11 名单含 centerPlay（PlayPause 的直接证据待确认） | P15-③（未跑） | P15 |
| `MovaPlayPauseComponent` | class | center_play.dart | ①③ | 间接：audio_only_interaction_test:54,:87；mini_skin_test:11 名单含 centerPlay（PlayPause 的直接证据待确认） | P15-③（未跑） | P15 |
| `MovaIconButton` | class | common.dart | ①③ | 间接：所有顶/底栏按钮的底座，经 top_bar_test、bottom_bar_test 间接渲染 | P15-③（未跑） | P15 |
| `MovaGradBar` | class | common.dart | ①③ | 间接：所有顶/底栏按钮的底座，经 top_bar_test、bottom_bar_test 间接渲染 | P15-③（未跑） | P15 |
| `MovaSheetItem` | class | common.dart | ①③ | 间接：`ui/top_bar_test.dart` :154 清晰度弹层（选项经它渲染与勾选） | P15-③（未跑） | P15 |
| `MovaDanmakuTrackComponent` | class | danmaku.dart | ①③ | `ui/danmaku_test.dart` | P15-③（未跑） | P15 |
| `MovaDouyinGestureLayerComponent` | class | douyin_gesture_layer.dart | ①③ | 间接：douyin_skin_test:71（单击播放暂停/双击点赞）、:131（components 名单） | P15-③（未跑） | P15 |
| `MovaSocialRailComponent` | class | feed_social.dart | ①③ | 间接：feed_social_test:13-77 | P15-③（未跑） | P15 |
| `MovaAvatarComponent` | class | feed_social.dart | ①③ | `ui/feed_social_test.dart` | P15-③（未跑） | P15 |
| `MovaLikeButtonComponent` | class | feed_social.dart | ①③ | `ui/feed_social_test.dart` | P15-③（未跑） | P15 |
| `MovaCommentButtonComponent` | class | feed_social.dart | ①③ | `ui/feed_social_test.dart` | P15-③（未跑） | P15 |
| `MovaShareButtonComponent` | class | feed_social.dart | ①③ | `ui/feed_social_test.dart` | P15-③（未跑） | P15 |
| `MovaFeedInfoComponent` | class | feed_social.dart | ①③ | `ui/feed_social_test.dart` | P15-③（未跑） | P15 |
| `MovaGestureLayerComponent` | class | gesture_layer.dart | ①③ | `ui/audio_only_interaction_test.dart`；`ui/gesture_test.dart` | P15-③（未跑） | P15 |
| `MovaHudLayerComponent` | class | hud_layer.dart | ①③ | `ui/hud_test.dart` | P15-③（未跑） | P15 |
| `MovaVolumeHudComponent` | class | hud_layer.dart | ①③ | 间接：hud_test:11-62（经 MovaHudLayerComponent） | P15-③（未跑） | P15 |
| `MovaBrightnessHudComponent` | class | hud_layer.dart | ①③ | 间接：hud_test:11-62（经 MovaHudLayerComponent） | P15-③（未跑） | P15 |
| `MovaSeekHudComponent` | class | hud_layer.dart | ①③ | 间接：hud_test:11-62（经 MovaHudLayerComponent） | P15-③（未跑） | P15 |
| `MovaZoomHudComponent` | class | hud_layer.dart | ①③ | `ui/component_tree_test.dart`（按名；行为见 `ui/hud_test.dart`） | P15-③（未跑） | P15 |
| `MovaNextUpComponent` | class | next_up.dart | ①③ | `ui/next_up_test.dart` | P15-③（未跑） | P15 |
| `MovaBufferingComponent` | class | overlays.dart | ①③ | `ui/minimal_skin_test.dart`；`ui/overlays_test.dart` | P15-③（未跑） | P15 |
| `MovaErrorComponent` | class | overlays.dart | ①③ | `ui/minimal_skin_test.dart`；`ui/overlays_test.dart` | P15-③（未跑） | P15 |
| `MovaLockMaskComponent` | class | overlays.dart | ①③ | `ui/overlays_test.dart` | P15-③（未跑） | P15 |
| `MovaPreviewComponent` | class | preview.dart | ①③ | `core/openness_preview_test.dart`；`ui/preview_test.dart` | P15-③（未跑） | P15 |
| `MovaSpeedButtonComponent` | class | speed_button.dart | ①③ | `ui/audio_only_interaction_test.dart`；`ui/speed_button_test.dart` | P15-③（未跑） | P15 |
| `MovaSubtitleOverlayComponent` | class | subtitle.dart | ①③ | `ui/subtitle_test.dart` | P15-③（未跑） | P15 |
| `MovaSubtitleButtonComponent` | class | subtitle.dart | ①③ | `ui/subtitle_test.dart` | P15-③（未跑） | P15 |
| `MovaTopBarComponent` | class | top_bar.dart | ①③ | `ui/top_bar_test.dart` | P15-③（未跑） | P15 |
| `MovaTitleComponent` | class | top_bar.dart | ①③ | 间接：top_bar_test:92,:113 / :26,:33 / :15 / :42,:65 | P15-③（未跑） | P15 |
| `MovaPipButtonComponent` | class | top_bar.dart | ①③ | 间接：top_bar_test:92,:113 / :26,:33 / :15 / :42,:65 | P15-③（未跑） | P15 |
| `MovaQualityButtonComponent` | class | top_bar.dart | ①③ | `ui/component_tree_test.dart`（按名；行为见 `ui/top_bar_test.dart`） | P15-③（未跑） | P15 |
| `MovaFitButtonComponent` | class | top_bar.dart | ①③ | 间接：top_bar_test:92,:113 / :26,:33 / :15 / :42,:65 | P15-③（未跑） | P15 |
| `MovaOrientationButtonComponent` | class | top_bar.dart | ①③ | 间接：top_bar_test:92,:113 / :26,:33 / :15 / :42,:65 | P15-③（未跑） | P15 |
| `MovaFullscreenButtonComponent` | class | top_bar.dart | ①③ | `ui/component_tree_test.dart`（按名；行为见 `ui/top_bar_test.dart`） | P15-③（未跑） | P15 |

#### ui（5）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaFeedHolderBuilder` | typedef | feed_player.dart | ① | 间接：feed_player_test:158,:246 占位页（待确认是否经该参数） | — | U1 |
| `MovaFeedPlayer` | class | feed_player.dart | ①③ | `ui/feed_player_test.dart` | U1-③（PASS） | U1 |
| `MovaPlayer` | class | player.dart | ①③ | `core/audio_only_scenarios_test.dart`；`core/kernel/mpv_kernel_video_test.dart` 等 11 个文件 | U1-③（PASS） | U1 |
| `MovaViewEngineFactory` | typedef | view.dart | ① | 间接：view_test:63-112 注入引擎工厂 | — | U1 |
| `MovaView` | class | view.dart | ①③ | `testing/testing_test.dart`；`ui/auto_pause_test.dart` 等 4 个文件 | U1-③（PASS） | U1 |

#### ui/guard（1）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaAutoPause` | class | auto_pause.dart | ①② | `ui/auto_pause_test.dart`；`ui/review_regression_test.dart` | U9-②（PASS） | N18/U9 |

#### ui/mini（6）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaMiniMount` | enum | mini.dart | ①③ | `core/openness_mini_test.dart`；`ui/mini/mini_mount_test.dart` 等 3 个文件 | U8-③（PASS） | P14/S16 |
| `MovaMini` | class | mini.dart | ①③ | `core/openness_mini_test.dart`；`ui/player_test.dart` 等 5 个文件 | U8-③（PASS） | P14/S16 |
| `MovaMiniHost` | class | mini_host.dart | ①③ | `ui/mini/mini_mount_test.dart` | U8-③（PASS） | P14/S16 |
| `MovaMiniSkin` | class | mini_skin.dart | ①③ | `core/openness_mini_test.dart`；`ui/mini/mini_skin_test.dart` 等 3 个文件 | U8-③（PASS） | P14/S16 |
| `MovaMiniCloseComponent` | class | mini_skin.dart | ①③ | 间接：mini_skin_test:11,:26 | U8-③（PASS） | P14/S16 |
| `MovaMiniWindow` | class | mini_window.dart | ①③ | `ui/mini/mini_mount_test.dart`；`ui/mini/mini_test.dart` 等 3 个文件 | U8-③（PASS） | P14/S16 |

#### ui/scope（5）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaPlugin` | mixin | plugin.dart | ① | `ui/plugin_test.dart` | — | P15 |
| `MovaScope` | class | scope.dart | ① | `ui/bilibili_skin_test.dart`；`ui/douyin_skin_test.dart` 等 6 个文件 | — | P15 |
| `MovaSelect` | class | selector.dart | ① | `ui/player_test.dart`；`ui/selector_test.dart` | — | P15 |
| `MovaProgSelect` | class | selector.dart | ① | 缺：selector_test 只测 `MovaSelect` | — | P15 |
| `MovaUiSelect` | class | selector.dart | ① | 缺：同上 | — | P15 |

#### ui/skins（5）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaBilibiliSkin` | class | bilibili_skin.dart | ①③ | `ui/audio_only_interaction_test.dart`；`ui/bilibili_skin_test.dart` | U2-③（PASS） | S |
| `MovaDefaultSkin` | class | default_skin.dart | ①③ | `core/openness_preview_test.dart`；`ui/audio_only_interaction_test.dart` 等 6 个文件 | U2-③（PASS） | S |
| `MovaDouyinSkin` | class | douyin_skin.dart | ①③ | `ui/douyin_skin_test.dart` | U2-③（PASS） | S |
| `MovaMinimalSkin` | class | minimal_skin.dart | ①③ | `ui/minimal_skin_test.dart`；`ui/review_regression_test.dart` | U2-③（PASS） | S |
| `MovaSkin` | class | skin.dart | ①③ | `core/openness_mini_test.dart`；`ui/poster_test.dart` | U2-③（PASS） | S |

#### ui/slots（8）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaComponent` | class | component.dart | ① | `core/openness_mini_test.dart`；`ui/poster_test.dart` 等 4 个文件 | — | P15/S12 |
| `MovaPatch` | class | patch.dart | ① | `core/openness_preview_test.dart`；`ui/skin_test.dart` 等 3 个文件 | — | P15/S12 |
| `MovaPatchReplace` | class | patch.dart | ① | 间接：tree_test:50-89 经 `MovaPatch.replace/remove/insertAfter/add` 工厂 | — | P15/S12 |
| `MovaPatchRemove` | class | patch.dart | ① | 间接：tree_test:50-89 经 `MovaPatch.replace/remove/insertAfter/add` 工厂 | — | P15/S12 |
| `MovaPatchInsertAfter` | class | patch.dart | ① | 间接：tree_test:50-89 经 `MovaPatch.replace/remove/insertAfter/add` 工厂 | — | P15/S12 |
| `MovaPatchAdd` | class | patch.dart | ① | 间接：tree_test:50-89 经 `MovaPatch.replace/remove/insertAfter/add` 工厂 | — | P15/S12 |
| `MovaSlot` | enum | slot.dart | ① | `ui/bilibili_skin_test.dart`；`ui/skin_test.dart` 等 3 个文件 | — | P15/S12 |
| `MovaSlotBundle` | class | tree.dart | ① | `core/openness_mini_test.dart`；`ui/poster_test.dart` 等 4 个文件 | — | P15/S12 |

#### testing（2）

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaTestKernel` | class | test_kernel.dart | ① | `testing/testing_test.dart` | — | P18/A33 |
| `MovaTesting` | class | testing.dart | ① | `testing/testing_test.dart` | — | P18/A33 |

### 8.2 `@Deprecated` typedef（17 行，均在 `lib/src/deprecated_names.dart`）

**兼容范围**：别名只覆盖**类型位置与构造器**；静态成员不可经别名访问；`setStandby`/`swapTo`/`swapEnabled/Phase/Phases`、`MovaOpts(swap:/standby:)` 与 `copyWith` 旧参数、`MovaGuardAction.standby`、`standbyCapable` **无别名**；`MovaOpts.swap/standby`、`MovaState.standby`、`MovaHiddenMode.standby` 旧 getter/常量保留。已被测试引用的只有 4 个：`MovaSwapConfig`/`MovaStandbyConfig`/`MovaStandbyPhase`/`MovaStandbyMode`（`deprecated_names_test.dart:7`），旧成员转发在 `:19`。家族 P17。

| 旧名 | 现名 | 种类 | 单测 | 真机用例 |
|---|---|---|---|---|
| `MovaAdController` | `MovaAds` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaFeedController` | `MovaFeed` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaPlaylistController` | `MovaPlaylist` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaMiniController` | `MovaMini` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaSwapEngine` | `MovaCutoverEngine` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaSwapController` | `MovaCutover` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaSwapConfig` | `MovaCutoverConfig` | typedef | `deprecated_names_test.dart` | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaSwapChange` | `MovaCutoverChange` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaSwapPhase` | `MovaCutoverPhase` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaStandbyController` | `MovaKeepAlive` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaStandbyConfig` | `MovaKeepAliveConfig` | typedef | `deprecated_names_test.dart` | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaStandbyPhase` | `MovaKeepAlivePhase` | typedef | `deprecated_names_test.dart` | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaStandbyMode` | `MovaKeepAliveMode` | typedef | `deprecated_names_test.dart` | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaStandbyReason` | `MovaKeepAliveReason` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaStandbyChange` | `MovaKeepAliveChange` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaStandbyResume` | `MovaKeepAliveResume` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |
| `MovaSilentStandby` | `MovaSilentKeepAlive` | typedef | 缺（旧名别名，零引用） | —（P17-① 无真机用例，device-trace 记「无已定位用例」） |

### 8.3 台账漏列的导出类型（33 行）

旧台账由 `lib/mova.dart` 直接 `export` 的文件生成，漏掉了经 `options.dart` 再导出的 `lib/src/core/options/*` 里的类型。用传递导出闭包核对：`lib/mova.dart` + `lib/testing.dart` 共导出 137 个文件、**320 个**类型/extension，即 287 + 33。这 33 个应补进台账；档位与族按 C 组各配置对应的行。

| 类型 | 种类 | 来源文件 | 档位 | 单测 | 真机用例 | 族 |
|---|---|---|---|---|---|---|
| `MovaTimeouts` | class | timeouts.dart | ①② | `core/engine_source_options_test.dart`；`core/recovery/config_test.dart` 等 3 个文件 | N1-②（PASS） | N1 |
| `MovaTheme` | class | theme.dart | ①③ | `core/openness_host_test.dart`；`core/openness_live_test.dart` 等 4 个文件 | C10-③（PASS） | C10 |
| `MovaCutoverConfig` | class | cutover_config.dart | ①② | `deprecated_names_test.dart`；`core/openness_cutover_test.dart` 等 7 个文件 | C11-②（PASS） | C11 |
| `MovaStrs` | class | strings.dart | ①③ | `core/openness_live_test.dart`；`core/options_test.dart` 等 4 个文件 | C10-③（PASS） | C10 |
| `MovaSttBlockReason` | enum | stt_config.dart | ①③ | `core/engine_test.dart` | C7-③（BLOCKED） | C7 |
| `MovaSttBlockCb` | typedef | stt_config.dart | ①③ | 缺（零引用；函数类型别名，经配置字段使用，待确认） | C7-③（BLOCKED） | C7 |
| `MovaSttConfig` | class | stt_config.dart | ①③ | `core/engine_test.dart`；`core/stt_test.dart` | C7-③（BLOCKED） | C7 |
| `MovaSilentKeepAlive` | enum | keep_alive_config.dart | ①② | `core/keep_alive/config_test.dart`；`core/keep_alive/engine_keep_alive_enter_test.dart` 等 4 个文件 | C15-②（PASS） | C15 |
| `MovaKeepAliveConfig` | class | keep_alive_config.dart | ①② | `deprecated_names_test.dart`；`core/openness_keep_alive_test.dart` 等 6 个文件 | C15-②（PASS） | C15 |
| `MovaReportConfig` | class | report_config.dart | ①② | `core/openness_host_test.dart`；`core/openness_report_test.dart` 等 8 个文件 | C13-②（PASS） | C13 |
| `MovaRecoveryConfig` | class | recovery_config.dart | ①② | `core/engine_source_options_test.dart`；`core/interceptor_test.dart` 等 15 个文件 | C14-②（PASS） | C14 |
| `MovaPreviewBlockReason` | enum | preview_config.dart | ①② | `core/engine_test.dart`；`core/openness_preview_test.dart` 等 3 个文件 | C1-②（PASS） | C1 |
| `MovaPreviewBlockCb` | typedef | preview_config.dart | ①② | 缺（零引用；函数类型别名，经配置字段使用，待确认） | C1-②（PASS） | C1 |
| `MovaPreviewConfig` | class | preview_config.dart | ①② | `core/engine_test.dart`；`core/openness_preview_test.dart` 等 4 个文件 | C1-②（PASS） | C1 |
| `MovaPlaylistConfig` | class | playlist_config.dart | ① | `core/playlist_test.dart`；`ui/next_up_test.dart` | — | C8 |
| `MovaMiniCorner` | enum | mini_config.dart | ① | `core/openness_mini_test.dart`；`core/options_test.dart` 等 4 个文件 | — | C12 |
| `MovaMiniConfig` | class | mini_config.dart | ① | `core/openness_host_test.dart`；`core/openness_mini_test.dart` 等 7 个文件 | — | C12 |
| `MovaLiveSeekMode` | enum | live_config.dart | ①② | `core/engine_test.dart`；`core/openness_live_test.dart` 等 4 个文件 | C2-②（BLOCKED） | C2 |
| `MovaTimeShiftBuilder` | typedef | live_config.dart | ①② | 缺（零引用；函数类型别名，经配置字段使用，待确认） | C2-②（BLOCKED） | C2 |
| `MovaLiveWindowSolver` | typedef | live_config.dart | ①② | 缺（零引用；函数类型别名，经配置字段使用，待确认） | C2-②（BLOCKED） | C2 |
| `MovaBackToLive` | enum | live_config.dart | ①② | `core/engine_test.dart`；`core/openness_live_test.dart` 等 5 个文件 | C2-②（BLOCKED） | C2 |
| `MovaLiveConfig` | class | live_config.dart | ①② | `core/engine_test.dart`；`core/openness_live_test.dart` 等 7 个文件 | C2-②（BLOCKED） | C2 |
| `MovaGestureAction` | enum | gesture_config.dart | ①③ | `core/options_test.dart`；`ui/gesture_test.dart` | C3-③（FAIL） | C3 |
| `MovaGestureConfig` | class | gesture_config.dart | ①③ | `core/options_test.dart`；`ui/gesture_test.dart` | C3-③（FAIL） | C3 |
| `MovaDanmakuConfig` | class | danmaku_config.dart | ①③ | `core/audio_only_scenarios_test.dart`；`core/options_test.dart` 等 4 个文件 | C6-③（FAIL） | C6 |
| `MovaCtrlsConfig` | class | controls_config.dart | ① | `core/audio_only_scenarios_test.dart`；`core/engine_source_options_test.dart` 等 15 个文件 | — | C5 |
| `MovaAdWaitPolicy` | class | ad_config.dart | ① | `core/ads_test.dart`；`core/openness_ad_test.dart` 等 4 个文件 | — | C9 |
| `MovaAdWaitByKind` | class | ad_config.dart | ① | `core/ads_test.dart`；`core/ad_first_frame_test.dart` 等 7 个文件 | — | C9 |
| `MovaAdNotReady` | enum | ad_config.dart | ① | `core/ads_test.dart`；`core/openness_ad_test.dart` 等 3 个文件 | — | C9 |
| `MovaAdConfig` | class | ad_config.dart | ① | `core/ads_session_test.dart`；`core/ads_test.dart` 等 8 个文件 | — | C9 |
| `MovaAbrPolicy` | class | abr_config.dart | ①② | 缺（零引用；抽象类，经 `MovaBufferAbr` 实现使用，待确认） | C4-②（PASS） | C4 |
| `MovaBufferAbr` | class | abr_config.dart | ①② | `core/model_test.dart` | C4-②（PASS） | C4 |
| `MovaAbrConfig` | class | abr_config.dart | ①② | `core/keep_alive/engine_keep_alive_rules_test.dart` | C4-②（PASS） | C4 |

## 9. 计数汇总

### 9.1 编号数与分档

（2026-10-28 回填后编号数与分档**不变**；变的是 §9.2 的单测覆盖与 §9.3 的真机用例有无。）

| 口径 | 编号数 | 备注 |
|---|---|---|
| v1（A33 / C17 / E37 / U9 / F16 / N23） | 135 | E 含 35 个事件类 + E1/E2；与 manifest 的 135 个 id 一致 |
| v2 独立编号（S16 / P19 / G26） | 61 | G5/G6 是元条目不计；S 按「检查项」计，不乘皮肤（五皮肤展开为 80 格） |
| 本次新增（A34 A35 C18 N24 F17 P20 P21） | 7 | 见 §1 |
| **合计** | **203** | |

| 档 | 含该档的编号数 | 本文该档行数 |
|---|---|---|
| ① | 158 | 158 |
| ② | 79 | 79 |
| ③ | 70 | 54（另有 S 矩阵 80 格） |

**编号的档位组合**：① 60 个；①② 55 个；①③ 37 个；③ 27 个；② 18 个；①②③ 6 个。

### 9.2 单测覆盖（按编号；口径：全 = 矩阵该编号的逻辑层测试点都有断言；2026-10-28 回填后重算）

| 组 | 全 | 部分 | 缺 | 合计 |
|---|---|---|---|---|
| A | 32 | 3 | 0 | 35 |
| C | 13 | 5 | 0 | 18 |
| E | 36 | 1 | 0 | 37 |
| U | 9 | 0 | 0 | 9 |
| F | 8 | 6 | 3 | 17 |
| N | 24 | 0 | 0 | 24 |
| S | 11 | 4 | 1 | 16 |
| P | 9 | 11 | 1 | 21 |
| G | 4 | 9 | 13 | 26 |
| **合计** | **146** | **39** | **18** | **203** |

其中旧 196 个编号（v1 135 + v2 61）为 全 142 / 部分 38 / 缺 16；本次新增 7 个：全 4（A34/A35/C18/N24）、部分 1（P20）、缺 2（P21/F17），回填前后都是这个分布。回填前（基线 1519）为 全 101 / 部分 71 / 缺 31（旧 196 个：全 97 / 部分 70 / 缺 29）。**升为“全”的 45 个编号**：A1 A6 A7 A11 A12 A13 A14 A17 A19 A21 A23 A32、C3、E1 与 E.MovaSeek/Seeked/RateChange/QualityListChange/FitChange/ZoomChange/LockChange/FullScreenChange/CutoverChange/Ready/Done/Play/Pause/SizeChange、U2 U3 U5 U6、N9、S1 S4 S7 S9 S12 S14、P13 P16、G2.1 G3.5 G4.1 G4.5（S 的“全”以 §3.3.S 的「单测承接」列为准）。**仍“部分”的要点**：A2（缺逐字段 state↔事件载荷全量对照）、A10（换源后倍速保持/复位契约未定）、A31（组件级全，管线未集成，主会话终审降级）、C4/C5/C6/C10/C16（P2-01、P2-13、P1-14）、`E.MovaBufferChange`（常规缓冲载荷）、F1/F5/F13/F14/F15/F16、P1/P2/P3/P9/P10/P12/P15/P17/P18/P19/P20、S2/S8/S10/S13、G 的 9 项。单测缺口清单：36 条里已补 22 条（P0 7 / P1 14 / P2 1），未补 14 条（P1-14 + P2 13），另新增 P2-15。测试基线 **1738 项全绿**（2026-10-28，主会话实跑完整 `flutter test`，0 skip）。

### 9.3 真机用例（Android，STG-AL00）

- ②/③ 档涉及的编号 127 个（S 的 16 个由矩阵另计），其中**有已定位真机用例 111、缺 16**（2026-10-28 回填后；回填前是 105/22）。缺的：A35、F17、G1.3、G1.4、G1.5、G2.4、G2.5、G2.6、G2.7、G2.8、G2.9、G3.3、G3.5、G3.6、G4.2、G4.4；本轮新增用例的 6 个编号（G1.1、G1.2、G2.1、G2.3、G3.1、G4.1）计入“有”，**但这些用例全部未上机**，其中 G1.1/G1.2 是 manual 登记（BLOCKED）。A35 的 `gap-formats` 只读回属性、没有按格式生效与还原的判据，仍计缺。
- **v1 的 135 个编号全部有真机用例**（部分只覆盖子项）；manifest 自报 129 个有 `covers`、6 个 manual（A31/C7 缺 STT 模型链、C2 缺历史时移服务、F15 缺 WHEP、N18 缺守卫专包、N22 缺 debug 断言专包），38 批（含本轮 12 个 `gap-*` 批次）。
- **v2 独立编号 61 个**：回填后 43 个有「相关子项」或本轮新用例（S 14 个、P 18 个、G 11 个）、**18 个完全无用例**（S 2 个：S3/S6；P17；G 15 个：G1.3、G1.4、G1.5、G2.4–G2.9、G3.3、G3.5、G3.6、G4.2、G4.4、G4.5）；回填前是 35 / 26。没有一个有独立整项结论。S 的 80 格：整项 PASS 仍为 0，其中 36 格标“未跑·用例已写”（§3.3.S）。
- **v1 最近真机结论**（135 项）：PASS 113 / FAIL 17 / BLOCKED 5。FAIL 里属「旧预期」的 11 个（A1/A2/A5/C3/C6/C8/U3/U5/U6/E1/N12，矩阵预期已改、未按新预期复跑），真实现象的 6 个（`E.MovaBufferChange`/`E.MovaSizeChange`/`E.MovaQualityChange`/C16/F3/A17）。BLOCKED 5 个：A31、C7、C2、F15、N18。 **本轮 gap 用例没有产生任何新的真机结论。**
- **自动判据**：完整自动 **2**（A4、A22；manifest `automatic_full_ids`）；另有 49 行带显式子项 CHECK，但整项仍依赖人工终审，不算完整自动。

### 9.4 假设（§4）

共 78：已核对 30、部分核对 24、未核对 13、已证伪 11。（2026-10-28 回填：H 的真机状态**本轮没变**；单测侧 H16/H17/H18/H19/H37/H42 已补贴合真机的用例，16 条假设已有待上机的 gap 用例，见 §4.5 与 §5.2.5。）

### 9.5 台账（§8）与缺口（§5）

- 台账 287 行（§8.1 270 + §8.2 17）：单测 有 225 / 间接 40 / 缺 22（回填前 219 / 39 / 29）。另 §8.3 漏列 33 个：有 28 / 缺 5。
- 单测缺口 36 条里已补 22（P0 7 / P1 14 / P2 1），未补 14（P1-14 + P2 13），另新增 P2-15（DVR 直播 seek 校验链）；真缺类型 9 个（§5.1.2，回填前 16）+ 旧名 typedef 13 个；真机用例缺口编号 27 个（含 G5）里 8 个用例已写待上机、19 个仍无用例；BLOCKED 5 个编号（A31/C7/C2/F15/N18，§5.2.2 合并为 4 行，另加一行 gap 批次内 BLOCKED 子项）+ 未实现 1 项（F17）；假设待核对 9 组（§5.3，其中 1–8 已有待上机用例）。

## 10. 编号总索引

每个**原编号**一行（共 135 个 v1 编号 + 61 个 v2 编号 + 7 个新增），给出该编号落在哪几档、对应 §3 的哪些行。本节的表格格式**刻意保持原样**：`example/tool/run_matrix.py` 的 `matrix_ids()` 会读 `matrix_manifest.json` 的 `matrix` 字段指向的文档，按「行首 `| 原编号 |`」抽取 v1 编号，并读 E 小节标题与 U 小节标题之间的反引号事件类名（manifest 键沿用旧事件名）。**改这里的格式前先跑 `python example/tool/run_matrix.py --check`**；E 小节里除事件键之外不要再出现反引号包起来的 `Mova…` 名字。

### A 组索引（33）

| 编号 | 档位 | 对象 |
|---|---|---|
| A1 | ① | events/states/progress/uiStates |
| A2 | ①② | state |
| A3 | ①③ | renderHandle |
| A4 | ①② | pipSupported |
| A5 | ①② | open(source, autoPlay) |
| A6 | ①② | play/pause/playOrPause |
| A7 | ①② | seek/seekBy |
| A8 | ①② | setVolume |
| A9 | ①② | setBrightness |
| A10 | ①② | setRate |
| A11 | ①③ | setFit |
| A12 | ①③ | setZoom |
| A13 | ① | setLocked |
| A14 | ①②③ | setFullscreen |
| A15 | ①② | setMini |
| A16 | ①② | setOrientation |
| A17 | ①② | loadQualities/switchQuality |
| A18 | ①②③ | enterPip |
| A19 | ① | reload |
| A20 | ①② | backToLiveEdge |
| A21 | ① | showControls/hideControls/showHud/setDragging |
| A22 | ① | report(name, params) |
| A23 | ①②③ | dispose |
| A24 | ①②③ | MovaCutoverEngine（cutoverTo/prepare/commit/abandon） |
| A25 | ①② | MovaKeepAlive.setKeepAlive |
| A26 | ①③ | MovaMini |
| A27 | ① | MovaAds |
| A28 | ①② | MovaPlaylist |
| A29 | ①③ | MovaFeed/MovaEnginePool/MovaFeedPrefetcher |
| A30 | ①② | 预览 MovaPreviewApi |
| A31 | ①③ | STT MovaSttApi |
| A32 | ① | 拦截点 MovaHook |
| A33 | ① | package:mova/testing.dart |

### C 组索引（17）

| 编号 | 档位 | 对象 |
|---|---|---|
| C1 | ①② | preview/MovaPreviewConfig |
| C2 | ①② | live/MovaLiveConfig |
| C3 | ①③ | gesture/MovaGestureConfig |
| C4 | ①② | abr/MovaAbrConfig |
| C5 | ① | controls/MovaCtrlsConfig |
| C6 | ①③ | danmaku/MovaDanmakuConfig |
| C7 | ①③ | stt/MovaSttConfig |
| C8 | ① | playlist/MovaPlaylistConfig |
| C9 | ① | ads/MovaAdConfig |
| C10 | ①③ | strings/MovaStrs、theme/MovaTheme |
| C11 | ①② | cutover/MovaCutoverConfig |
| C12 | ① | mini/MovaMiniConfig |
| C13 | ①② | report/MovaReportConfig |
| C14 | ①② | recovery/MovaRecoveryConfig |
| C15 | ①② | keepAlive/MovaKeepAliveConfig |
| C16 | ①② | TLS：tlsVerify/tlsCaFile |
| C17 | ①② | MovaSource |

### E. 事件索引（35 个事件类 + E1/E2）

| 事件键 | 档位 | 现名 |
|---|---|---|
| `MovaReady` | ② | 同键 |
| `MovaSourceChange` | ① | 同键 |
| `MovaPlay` | ② | 同键 |
| `MovaPause` | ② | 同键 |
| `MovaDone` | ② | 同键 |
| `MovaSeek` | ① | 同键 |
| `MovaSeeked` | ② | 同键 |
| `MovaBufferChange` | ② | 同键 |
| `MovaDurationChange` | ② | 同键 |
| `MovaFirstFrame` | ② | 同键 |
| `MovaSizeChange` | ② | 同键 |
| `MovaVolumeChange` | ① | 同键 |
| `MovaBrightChange` | ① | 同键 |
| `MovaRateChange` | ① | 同键 |
| `MovaQualityListChange` | ① | 同键 |
| `MovaQualityChange` | ① | 同键 |
| `MovaAbrDownShift` | ② | 同键 |
| `MovaFitChange` | ① | 同键 |
| `MovaZoomChange` | ① | 同键 |
| `MovaLockChange` | ① | 同键 |
| `MovaFullScreenChange` | ① | 同键 |
| `MovaOrientationChange` | ① | 同键 |
| `MovaPipChange` | ② | 同键 |
| `MovaMiniChange` | ① | 同键 |
| `MovaTimeShiftChange` | ① | 同键 |
| `MovaLiveEdgeReach` | ② | 同键 |
| `MovaPreviewBlock` | ① | 同键 |
| `MovaSttBlock` | ① | 同键 |
| `MovaSwapChange` | ① | MovaCutoverChange |
| `MovaErrorEvent` | ② | 同键 |
| `MovaPlayFailure` | ② | 同键 |
| `MovaRecovered` | ② | 同键 |
| `MovaFailover` | ① | 同键 |
| `MovaStandbyChange` | ① | MovaKeepAliveChange |
| `MovaStandbyResume` | ② | MovaKeepAliveResume |
| E1 | ①② | 点播完整事件序列 |
| E2 | ① | 关闭态事件数为 0 |

### U. UI 索引（9）

| 编号 | 档位 | 对象 |
|---|---|---|
| U1 | ①③ | MovaPlayer/MovaView/MovaFeedPlayer |
| U2 | ①③ | 皮肤 |
| U3 | ① | 顶栏 TopBar |
| U4 | ①③ | 底栏 BottomBar |
| U5 | ① | CenterPlay、SpeedButton、HudLayer |
| U6 | ①③ | GestureLayer/DouyinGestureLayer |
| U7 | ① | Danmaku、Subtitle、NextUp、AdOverlay、FeedSocial |
| U8 | ①③ | MovaMiniWindow |
| U9 | ①② | MovaAutoPause |

### F 组索引（16）

| 编号 | 档位 | 对象 |
|---|---|---|
| F1 | ①② | 点播完整生命周期 |
| F2 | ①② | 直播与时移 |
| F3 | ①② | HLS 清晰度切换与 ABR |
| F4 | ①②③ | 无缝引擎切换 + 广告编排 |
| F5 | ①② | 小窗 + PiP |
| F6 | ①② | 低功耗待机 |
| F7 | ①② | QoE 上报 |
| F8 | ①② | 超时与恢复 |
| F9 | ①③ | 仅音频 audioOnly |
| F10 | ①② | 预览缩略图 |
| F11 | ③ | 字幕 |
| F12 | ③ | 音频会话与耗电 |
| F13 | ①② | 多引擎并存与资源 |
| F14 | ①② | 原生事件泵（FFI 弱客户端） |
| F15 | ①②③ | WHEP |
| F16 | ①② | 已知遗留缺陷复现 |

### N 组索引（23）

| 编号 | 档位 | 对象 |
|---|---|---|
| N1 | ①② | MovaTimeouts（MovaRecoveryConfig.timeouts）：network/whepHandsh |
| N2 | ①② | MovaRecoveryConfig.startTimeout/stallTimeout（Duration?）、stal |
| N3 | ① | MovaLiveReconnect、MovaDefaultRecovery、MovaRecoveryConfig.liv |
| N4 | ①② | MovaSource.mpvOptions/demuxerOptions/whepMediaTimeout/mpvOpt |
| N5 | ①② | recovery 自动订阅 END_FILE；observeRestarts；movaObserveFlags(reco |
| N6 | ①② | 恢复后清错误/放弃后清 buffering |
| N7 | ①② | MovaLiveConfig.durationStep（默认 2s） |
| N8 | ①② | MovaApi.open() 返回 Future<bool> |
| N9 | ①② | MovaPipObservable.changes |
| N10 | ①② | MovaWarmPlan.rate、cutoverTo(rate:)、MovaHandoffRetirable |
| N11 | ①② | MovaPlayerMute 能力 |
| N12 | ①② | MovaState.rendered、MovaFirstFrame(sinceOpen, signal)、MovaFir |
| N13 | ①② | createMovaEngine(preciseFirstFrame:)、MovaMpvKernel(observeNa |
| N14 | ① | fit 初值参数、MovaPlayer(fit:) |
| N15 | ①③ | MovaPlayer(poster:, posterFade:)、MovaFeedPlayer(posterUntilF |
| N16 | ① | MovaMinimalSkin、MovaTheme.bufferingSize/StrokeWidth/Color |
| N17 | ① | MovaView、MovaSource.sameAs |
| N18 | ①② | MovaAutoPause/MovaAutoPauseGate/MovaAutoPauseConfig、MovaView |
| N19 | ①② | MovaFailover、MovaPlayFailure、MovaRecovered、MovaSource.altern |
| N20 | ①② | standby：MovaHiddenMode.keepAlive、MovaKeepAlive、MovaKeepAlive |
| N21 | ①③ | MovaSnapshotGuard（仅 Windows）、testing.dart 的 stagedSourceOpti |
| N22 | ① | 0.3.1 小修 |
| N23 | ①② | 统一上报 QoE 新增：MovaStatsProbe.nativeRestartAvailable、truncatedB |

### v2 编号索引（S16 / P19 / G26；不被 `matrix_ids()` 解析，行首用「v2:」前缀）

| 编号 | 档位 | 主题 |
|---|---|---|
| v2:S1 | ①③ | 组件树 |
| v2:S2 | ③ | 点播布局 |
| v2:S3 | ③ | 直播布局 |
| v2:S4 | ③ | 手势：单击/双击 |
| v2:S5 | ③ | 手势：水平拖动 |
| v2:S6 | ③ | 手势：竖滑 |
| v2:S7 | ③ | 手势：捏合/锁定 |
| v2:S8 | ③ | 手势：长按/其他 |
| v2:S9 | ③ | 按钮逐个点击 |
| v2:S10 | ③ | 全屏与转屏 |
| v2:S11 | ③ | 覆盖层 |
| v2:S12 | ①③ | MovaPatch |
| v2:S13 | ①③ | 主题与文案 |
| v2:S14 | ①③ | 皮肤切换 |
| v2:S15 | ③ | 已知失败项交叉 |
| v2:S16 | ③ | Mini 专项 |
| v2:P1 | ① | 引擎与状态 |
| v2:P2 | ① | 事件 |
| v2:P3 | ① | 配置 |
| v2:P4 | ① | 广告 |
| v2:P5 | ① | 无缝切换 |
| v2:P6 | ① | 保活 |
| v2:P7 | ① | 恢复 |
| v2:P8 | ① | 上报 |
| v2:P9 | ①② | 预览缩略图 |
| v2:P10 | ①③ | STT |
| v2:P11 | ① | Feed 与 Playlist |
| v2:P12 | ② | 平台端口 |
| v2:P13 | ① | 拦截与守卫 |
| v2:P14 | ① | 小窗 |
| v2:P15 | ①③ | UI 组件逐个 |
| v2:P16 | ①③ | HUD |
| v2:P17 | ① | 旧名兼容 |
| v2:P18 | ① | 测试替身 |
| v2:P19 | ① | 顶层函数 |
| v2:G4.1 | ①③ | 随机序列/压力测试：随机 API 调用序列（open/play/pause/seek/switchQuality/set |
| v2:G1.1 | ③ | 只测了 STG-AL00（华为）arm64-v8a。四架构 libmpv 里 armeabi-v7a/x86/x86_6 |
| v2:G1.2 | ③ | release 构建全程 `-Pdart-obfuscation=false`（见 `coverage_build.py |
| v2:G1.3 | ③ | 以 pub.dev 依赖方式接入没测：验证全程走 path 依赖；0.3.0 发布版与当前 Unreleased 行为差 |
| v2:G1.3b | ③ | iOS/macOS/Linux/Web 无任何通用功能矩阵（Windows 仅零散） |
| v2:G1.4 | ③ | 仅 Impeller（Vulkan/OpenGLES）；Android 上 Skia 后端、不同 Flutter 版本（ |
| v2:G1.5 | ③ | 折叠屏/平板/分屏/多窗口/画中画与分屏并存、刘海与手势导航模式 |
| v2:G2.1 | ①③ | 音频焦点：来电、闹钟、其他 App 抢焦点、耳机拔出/蓝牙断开后的暂停与恢复 |
| v2:G2.2 | ①③ | 网络变化：播放中 Wi-Fi↔蜂窝、飞行模式开关、网络恢复后的续播（只测过断网预热/预览降级） |
| v2:G2.3 | ①③ | 息屏/锁屏/解锁：灭屏后播放、熄屏自动暂停与亮屏恢复（只测过切后台） |
| v2:G2.4 | ③ | 低内存/`onTrimMemory`、进程被系统回收后的重建、旋转导致 Activity 重建 |
| v2:G2.5 | ③ | 物理音量键 / 系统音量被外部改动：`state.volume` 是否同步（现在只测了 App→系统） |
| v2:G2.6 | ③ | 系统亮度被外部改动、退出播放/全屏后窗口亮度是否还原 |
| v2:G2.7 | ③ | 系统手势冲突（边缘返回、状态栏下拉）与垂直手势区域 |
| v2:G2.8 | ①③ | 深色模式、字体缩放、系统语言切换（`MovaStrs`）、RTL、TalkBack/Semantics |
| v2:G2.9 | ①③ | 磁盘满/缓存目录不可写/无存储权限时预览磁盘缓存、STT 模型目录的降级 |
| v2:G3.1 | ③ | 本地来源：`file://`、`content://`（SAF/相册）、Flutter asset、应用沙盒路径 |
| v2:G3.2 | ③ | 容器/编码：mkv、webm、ts、mp3/aac/flac/ogg（纯音频）、H.265、AV1、10bit、VP9、 |
| v2:G3.3 | ①③ | 协议：RTMP/RTSP/DASH/HLS 加密（AES-128）/fMP4 HLS/多音轨/多字幕轨切换 |
| v2:G3.4 | ①③ | 服务端异常：302 重定向链、不支持 Range、缺 Content-Length、chunked、间歇性 5xx、慢速 |
| v2:G3.5 | ①③ | 点播↔直播同引擎互换（type 切换时 UI、时移、seekable 状态机） |
| v2:G3.6 | ①③ | 超长/超大文件、时长为 0/未知、时长突变、损坏文件、截断文件 |
| v2:G4.2 | ③ | 长时间浸泡：点播/直播连续 1–2h，监控内存/发热/掉帧/句柄，直播跨天时间戳 |
| v2:G4.3 | ①③ | 运行中热切换：换皮肤、换 `MovaOpts`、改 `MovaStrs/Theme`（v2 S14 仅皮肤） |
| v2:G4.4 | ①③ | 多实例：同屏两个 `MovaPlayer`、Feed 滑动 100 次 + 同时小窗 + 广告 cutover 叠加 |
| v2:G4.5 | ① | 上报回调抛异常/阻塞时不拖垮播放；事件洪泛的背压 |

### 新增编号索引

| 编号 | 档位 | 主题 |
|---|---|---|
| new:A34 | ① | 架构守卫 |
| new:A35 | ①② | 按格式限制缓冲 |
| new:C18 | ① | heartbeat |
| new:N24 | ① | 开放性对账 |
| new:F17 | ② | 保活出声/到期断流（未实现） |
| new:P20 | ① | 顶层纯函数 |
| new:P21 | ① | 公开成员级覆盖 |

### PF 性能索引

| 编号 | 档位 | 主题 |
|---|---|---|
| PF1 | ③ | 点播硬解 H.264 1080p |
| PF2 | ③ | 点播软解 hwdec=no 对照 |
| PF3 | ③ | 直播稳态资源 |
| PF4 | ③ | cutover 预热双引擎并存 |
| PF5 | ③ | feed 引擎池连续滑动 |
| PF6 | ③ | 点播循环 60 分钟浸泡 |
| PF7 | ③ | 直播 60 分钟浸泡 |
| PF8 | ③ | 长场景泄漏最小二乘斜率 |
| PF9 | ③ | 视频掉帧与 Flutter jank |
| PF10 | ③ | Windows release CPU/RSS 补充 |
| PF11 | ③ | 可选 audioOnly CPU/内存对照 |

## 附：性能基线首录（2026-10-28，STG-AL00）

- 8 个场景基线已写入 `example/tool/perf_baseline/7NQBB23606003715.json`；判据状态均为 BLOCKED(no-baseline)（首录不比较）。完整数字见会话报告 round2-results。
- CPU p50 在点播/直播/cutover 约 91–97%（100%=1 核），audioOnly 约 8%，原因未查；
- feed 线程数两次运行均呈增长（约每 10 分钟 +5~6），一次 FAIL(leak:threads)、一次 R² 差一点未过；窗口较短，结论仅供参考；
- 3 路 1080p 同时硬解时 AVC 解码器报 `configureCodec -12`、主线程卡死，改 720p 才正常；
- 构建性能入口必须用 `example/tool/coverage_build.py`（`flutter build apk` 会打出 LFS 指针 `libmpv.so`，App 启动即报错）。`coverage_gap.py` 里 G1.2 的混淆构建命令同样需要先确认 `libmpv.so` 不是指针。
