# INSTR 第五轮：冷首帧归因与 /proc CPU

仅 vivo V2417 / Android16 / `10AE9K17UE0011S`，全部在 `C:/ldq/luckdraw` 副本执行。两个 APK 均启用 `LUCKDRAW_TIMELINE=true`。不升级依赖、不改 parity/golden 基线、不 add/commit/push。库候选修复位于副本；共享核心和各玩法的禁止覆盖规则优先，lib 以 `C:/ldq/core_patch.diff`、`C:/ldq/gameplay_patch.diff` 交主会话合并。真实仓库工具和文档落盘不表示库补丁已经合并。

构建：`flutter build apk --profile --no-pub --target=integration_test/pending_bench_test.dart --dart-define=LUCKDRAW_TIMELINE=true`。Windows 根证书库、workers=2、单个活动构建；两次 Gradle 实测均32.5s。构建前 FreePhysicalMemory=11992920/9638392 KiB，均≥4GiB；临时 Gradle 属性已恢复。两个 APK SHA-256：

- before：`35EEE3DEED78E8A4F777C1FA3262E5BE8C827B10ABF5F0F405539A99D4C797C5`。
- after/CPU：`1FF4EACB243B3947AA0A829B1D61CE11A545ACFBC667DEDA57EA5C63FA8EC142`。

可审核补丁：[core_patch.diff](validation/core_patch.diff)、[gameplay_patch.diff](validation/gameplay_patch.diff)、[核心矩阵与豁免追加](validation/core_acceptance_append.md)。主会话合并后需重跑真实仓库全量门禁。

## 打点与数据完整性

| 事件名 | 位置/边界 |
| --- | --- |
| `luckdraw.{wheel,grid,slot,capsule,number_wheel,lots,lotto}.layout` | 各 `lib/src/<game>/layout/<game>_layout.dart` 的 compute…Layout 函数，包含全部布局 |
| `luckdraw.{上述七玩法}.record` | 各 painter 的构造/prepare/rebuildSegments 静态准备；Picture 缓存细分见公共 record |
| `luckdraw.{上述七玩法}.paint` | 各 painter.paint，每次绘制成对；首帧内第一次即首次 paint，无默认构建的额外布尔状态 |
| `luckdraw.text.layout` / `luckdraw.text.split` | core/text/text_line.dart、split_text.dart，总耗时；嵌套不重复相加 |
| `luckdraw.text.painter.layout` | 所有直接 TextPainter.layout 调用；arguments.layouts=1，测量器、paint_helpers、lots/number_wheel/lotto |
| `luckdraw.image.update` | LuckyImageResolver.update 的同步部分，不冒充异步解码总时长 |
| `luckdraw.picture.record` | LuckyPictureCache.picture，缓存命中也有事件；实际录制见子调用与缓存计数 |
| `luckdraw.raster.build` / `luckdraw.raster.prepare` / `luckdraw.raster.atlas` | picture_cache.raster 含 toImageSync；cached_picture 的回放参数准备；SlotAtlas.prepare |

所有同步片段 try/finally 成对。包装函数保持 bool.fromEnvironment 编译期守卫、vm:prefer-inline；默认关闭不创建事件 arguments Map。没有新增可变全局状态或导出入口。COV-01 原调用/结束两行保留；参数 Map 格式化为独立行14，新增 COV-02仅豁免该行并逐行登记。默认渲染等价由全量测试和未更改的 parity/golden 复验；未额外构建关闭打点 APK 作二进制差异验证。

driver 先保存完整 response，再保存全部原始 timeline，然后做汇总。只容忍冷首帧已测到正 buildDuration 且 SDK 精确报 “The TimelineSummary had no events to summarize.”；其它错误继续抛出。缺 Raster 不填零，保存 sdk_summary_status/error。CPU 路由显式记录没有独立 GC 参照，不伪造 GC 回归结论。

## 冷首帧归因

FrameTiming.buildDuration 是首帧结果指标；下表各阶段与占比的共同分母为**包含首次玩法 layout 的 Dart Frame b/e 墙钟区间**，两种边界不同。为避免各列独立中位数不能相加，每行选三轮中 FrameTiming 为中位数的那一轮。布局剔除文字；录制剔除文字/位图；文字包括录制期整形；其它是未打点区间（含框架），无法进一步归因。

| 阶段/玩法 | FrameTiming / Dart Frame ms | 布局去文字 ms/% | 文字 ms/% | 录制去文字位图 ms/% | 位图 ms/% | 图片更新 ms/% | paint ms/% | 其它 ms/% |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before/wheel | 38.412 / 39.341 | 0.825 / 2.10% | 32.138 / 81.69% | 1.755 / 4.46% | 0.122 / 0.31% | 0.651 / 1.65% | 0.035 / 0.09% | 3.815 / 9.70% |
| before/grid | 24.214 / 25.894 | 0.320 / 1.24% | 16.345 / 63.12% | 4.408 / 17.02% | 1.217 / 4.70% | 0.025 / 0.10% | 0.062 / 0.24% | 3.517 / 13.58% |
| after/wheel | 27.075 / 30.349 | 0.998 / 3.29% | 15.709 / 51.76% | 4.478 / 14.76% | 0.337 / 1.11% | 1.851 / 6.10% | 0.080 / 0.26% | 6.896 / 22.72% |
| after/grid | 12.993 / 14.292 | 0.245 / 1.71% | 4.774 / 33.40% | 4.578 / 32.03% | 1.316 / 9.21% | 0.054 / 0.38% | 0.087 / 0.61% | 3.238 / 22.66% |

全部12个有效冷窗口的每个 luckdraw 事件（含每次文字测量）绝对 start_us/end_us、相对起止、arguments、未配对事件及阶段原值见 [attribution.json](attribution.json)。各首帧内 luckdraw 事件均完整配对；窗口外裁断事件单独列示。可用 `python tool/bench/analyze_instr.py` 离线重算。以下为每轮原始统计：

| 阶段/玩法/轮 | FrameTiming ms | Dart Frame起止 μs | layout/record含子事件 ms | TextPainter次数 / 总ms / 每次均ms |
| --- | --- | --- | --- | --- |
| before/wheel/1 | 38.412 | 71231378045–71231417386 | 30.363 / 4.477 | 276 / 25.051 / 0.090764 |
| before/wheel/2 | 46.689 | 71251744685–71251792696 | 37.131 / 5.652 | 276 / 28.405 / 0.102917 |
| before/wheel/3 | 25.178 | 71272077746–71272103829 | 19.496 / 3.750 | 276 / 15.205 / 0.055091 |
| before/grid/1 | 20.660 | 71305211196–71305233228 | 11.768 / 6.932 | 128 / 10.720 / 0.083750 |
| before/grid/2 | 28.587 | 71324478327–71324508950 | 15.771 / 10.327 | 128 / 14.389 / 0.112414 |
| before/grid/3 | 24.214 | 71343277973–71343303867 | 14.200 / 8.090 | 128 / 12.718 / 0.099359 |
| after/wheel/1 | 28.309 | 71559761606–71559791361 | 11.544 / 11.022 | 63 / 14.204 / 0.225460 |
| after/wheel/2 | 10.715 | 71579011106–71579022975 | 3.982 / 4.609 | 63 / 5.104 / 0.081016 |
| after/wheel/3 | 27.075 | 71597978290–71598008639 | 10.297 / 11.225 | 63 / 12.763 / 0.202587 |
| after/grid/1 | 8.585 | 71720027104–71720036789 | 2.009 / 5.372 | 22 / 2.906 / 0.132091 |
| after/grid/2 | 21.166 | 71739761028–71739783725 | 5.918 / 11.761 | 22 / 6.810 / 0.309545 |
| after/grid/3 | 12.993 | 71758843927–71758858219 | 2.711 / 8.202 | 22 / 4.114 / 0.187000 |

## 修复、复测和标定

已定位的库内工作：相同样式和文本被反复完整整形。保持 splitLuckyText 的逐码点比较、回调顺序、负宽、超宽首字和 lineClamp 规则，未改成无法证明等价的二分或逐字宽相加；TextPainterMeasurer 只增加最多256项的精确宽度缓存，实例方向/缩放固定，dispose/样式缓存释放时清空。wheel 276→63次，grid128→22次。随机280组（70×方向2×缩放2）、多语言/组合字符/emoji、6种lineClamp 与旧完整整形逐位相同；另测缓存上限、命中避免 layout 和释放后重测。

| 玩法 | before三轮ms / 中位数 | after三轮ms / 中位数 | 观测改善 | 减空白增量ms | ×1.1向上取整预算ms | 比原4ms多ms |
| --- | --- | --- | --- | --- | --- | --- |
| wheel | 38.412 / 46.689 / 25.178 / **38.412** | 28.309 / 10.715 / 27.075 / **27.075** | 29.51% | 24.192 | 26.612 | 20.192 |
| grid | 20.660 / 28.587 / 24.214 / **24.214** | 8.585 / 21.166 / 12.993 / **12.993** | 46.34% | 10.110 | 11.121 | 6.110 |

空白使用用户指定 DEVFIN 历史中位数2.883ms，本批遵照仅测wheel/grid未新增空白启动，故不是同期空白重测。两玩法修复后均观测到改善，保留候选缓存；三轮极差仍大（wheel17.594ms，grid12.581ms），不是稳定性或跨设备保证。已标定不等于达到4ms目标；预算冻结到 budgets.status.json.instr，既有绝对信息 schema 与稳态12ms/4ms、GC、RSS阈值不变。

wheel/grid before 各3/3，after wheel3/3、grid3/4；grid after首轮结束检查非亮屏未锁，标无效且原文保留，不按耗时挑轮。无独立采样栈的其它/异步解码/引擎与驱动成本仍无法判定，不据此继续修改渲染算法。

## /proc CPU 原值与同轮帧时

每窗口前 pidof 重新取PID；窗口外探测 shell/run-as/su，窗口内仅开始/结束各一次 adb。进程 stat 是进程合计，task/tid/stat 是单线程；读取 comm 保留空格/括号。差值÷主机两次读取开始的单调时刻差÷CLK_TCK×100，单核100%，不裁剪多核总值。请求稳定等待5秒；读取和握手开销使实际间隔更长，逐轮真实秒数和读取耗时如下，不伪称恰好5秒。

实际 shell 可读；没有采用 dumpsys/top 百分比代替本轮CPU。grid第3次历史降级源于 CRLF 解析缺陷，原 permission 文案不准确，已修正解析并补LF/CRLF实机夹具；该轮无可信增量，从有效CPU统计剔除。快照读取由逐线程cat/逐字节read改为三次缓冲cat，仍是同一个 adb 调用。解析失败显式抛错，不再冒充权限问题或填零。

当前 Flutter3.47 Android 默认 UI/platform 合并，/proc主线程名为 .luckdraw_bench（tid=pid），Raster名1.raster。下表 UI+platform 不是纯Dart UI CPU；依据 [Flutter官方架构说明](https://docs.flutter.dev/resources/architectural-overview) 与本轮线程原文，不能将两者拆开。CPU路由 lotto_draw 延续已有 helper 的搅拌阶段，未覆盖完整开奖过程，完整开奖CPU仍无法判定。

| 场景 | 正式有效/启动 | 进程三轮% / 中位数 | UI+platform三轮% / 中位数 | Raster三轮% / 中位数 |
| --- | --- | --- | --- | --- |
| wheel_steady | 2/5 | 41.448 / 40.484 / 缺测 / **不足三轮不计算** | 14.176 / 14.081 / 缺测 / **不足三轮不计算** | 19.981 / 19.091 / 缺测 / **不足三轮不计算** |
| grid_steady | 3/4 | 43.802 / 43.242 / 46.291 / **43.802** | 13.570 / 13.827 / 14.505 / **13.827** | 23.244 / 21.147 / 23.146 / **23.146** |
| slot_steady | 3/3 | 47.271 / 46.067 / 49.315 / **47.271** | 16.894 / 16.084 / 15.973 / **16.084** | 22.783 / 22.955 / 24.192 / **22.955** |
| capsule_mixing | 3/4 | 54.381 / 52.591 / 49.705 / **52.591** | 19.888 / 18.407 / 17.652 / **18.407** | 26.569 / 24.749 / 24.620 / **24.749** |
| lotto_draw | 3/3 | 55.199 / 56.591 / 60.515 / **56.591** | 20.002 / 19.123 / 21.513 / **20.002** | 28.685 / 31.716 / 30.799 / **30.799** |

| 场景/尝试 | CPU真实秒数 | 首/尾读取ms | 同轮FrameTiming窗口秒数 / 帧数 / fps | UI均ms / Raster均ms |
| --- | --- | --- | --- | --- |
| wheel_steady/3 | 7.406917 | 未分记/未分记 | 9.841390 / 591 / 60.052 | 1.015303 / 4.848484 |
| wheel_steady/4 | 7.385593 | 未分记/未分记 | 9.784676 / 587 / 59.992 | 1.024135 / 4.885072 |
| grid_steady/1 | 7.442656 | 2415.725/2578.447 | 10.045536 / 603 / 60.027 | 0.982055 / 3.261604 |
| grid_steady/2 | 7.377036 | 2363.680/2315.844 | 9.713713 / 583 / 60.018 | 0.977820 / 5.379700 |
| grid_steady/4 | 6.480719 | 1465.692/1460.848 | 7.963782 / 478 / 60.022 | 1.045245 / 4.922864 |
| slot_steady/1 | 6.452103 | 1434.261/1504.833 | 7.973744 / 478 / 59.947 | 1.338213 / 3.339814 |
| slot_steady/2 | 6.403774 | 1375.753/1458.097 | 7.880537 / 472 / 59.894 | 1.277739 / 16.765898 |
| slot_steady/3 | 6.448292 | 1433.175/1412.217 | 7.885605 / 473 / 59.983 | 1.283550 / 3.437199 |
| capsule_mixing/1 | 6.436089 | 1425.031/1577.936 | 8.041933 / 483 / 60.060 | 1.679505 / 3.722360 |
| capsule_mixing/3 | 6.464950 | 1450.526/1584.025 | 8.068038 / 484 / 59.990 | 1.579653 / 3.641320 |
| capsule_mixing/4 | 6.458051 | 1440.806/1583.039 | 8.063008 / 484 / 60.027 | 1.551928 / 4.493746 |
| lotto_draw/1 | 6.449412 | 1419.493/1543.118 | 8.014712 / 481 / 60.015 | 1.925328 / 10.285967 |
| lotto_draw/2 | 6.432151 | 1403.528/1606.437 | 8.068664 / 484 / 59.985 | 1.798847 / 4.337372 |
| lotto_draw/3 | 6.461195 | 1437.307/1637.702 | 8.128372 / 488 / 60.037 | 1.988889 / 4.402123 |

转盘第1/2次原始 CPU 可读但 driver 因缺GC参照失败，第5次 VM Service连接前卡住，四分钟采样器超时、五分钟终止自有drive进程树；正式仅第3/4次成功，2/5，未超上限补第六次。原始附加值如下，只作为失败产物证据，不混入三轮正式中位数：

| 场景/尝试 | 进程 / UI+platform / Raster % | CPU秒数 |
| --- | --- | --- |
| wheel_steady/1（driver失败） | 38.985911 / 13.337285 / 16.825498 | 9.747111 |
| wheel_steady/2（driver失败） | 32.831724 / 10.576663 / 16.636209 | 9.076587 |

全部线程、线程新建/退出、身份、命令失败和同轮FrameTiming见 [audit.json](audit.json) 与各 cpu_*/cpu_*/cpu/ 的 before/after/cpu.json。新建/退出线程单列，不填0；进程合计包含它们。线程采集非原子，统计边界的小偏差保留，不能把线程和与进程总值强行调成相等。

## 本机门禁

| 命令 | 实际输出摘要 |
| --- | --- |
| analyze | exit=0，6.305s；Analyzing luckdraw...                                            / No issues found! (ran in 4.2s) |
| bench_analyze | exit=0，5.594s；Analyzing bench...                                               / No issues found! (ran in 3.6s) |
| format | exit=0，2.123s；Formatted 360 files (0 changed) in 0.89 seconds. |
| format_check | exit=0，2.179s；Formatted 360 files (0 changed) in 0.94 seconds. |
| tools | exit=0，45.017s；真实JSON日志及test_summary.json，未使用登记数代替执行数 |
| instr-a | exit=0，84.367s；真实JSON日志及test_summary.json，未使用登记数代替执行数 |
| instr-b | exit=0，44.992s；真实JSON日志及test_summary.json，未使用登记数代替执行数 |
| instr-c | exit=0，88.069s；真实JSON日志及test_summary.json，未使用登记数代替执行数 |
| instr-d | exit=0，11.332s；真实JSON日志及test_summary.json，未使用登记数代替执行数 |
| coverage | exit=0，1.662s；TOTAL: 6878/6878 (100.00%) / PASS: coverage >= 100.0% |
| imports | exit=0，2.005s；PASS: 145 lib files; IMP-R1…R12 / 依赖图与静态规则通过 |
| acceptance | exit=0，1.714s；PASS: 1554 references resolve; 1133 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| acceptance_json | exit=0，1.638s；PASS: 1554 references resolve; 1133 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| parity | exit=0，11.913s；PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified |
| publish | exit=0，4.822s； / Package has 0 warnings. |

四组唯一执行计数：`{"instr-a": {"passed": 554, "skipped": 0, "failed": 0, "files": 63, "sha256": "7fd2bbbb602cff84c6b84590f25cee9d62c95518b16e54cf8159eeb73232d597"}, "instr-b": {"passed": 130, "skipped": 0, "failed": 0, "files": 31, "sha256": "8ddc30d1061c55c940d5221f98045b9cb4dafe39c42707e01f632f89c83daec9"}, "instr-c": {"passed": 401, "skipped": 0, "failed": 0, "files": 46, "sha256": "f8845e1db0dc0f31d62abc62e87f4fea543e2add36a8d446479325a8d100419a"}, "instr-d": {"passed": 23, "skipped": 0, "failed": 0, "files": 4, "sha256": "6c4e2a4b89f68543d4922e9d7e330582f167c84baebffbb49b908f7bf1b2752e"}, "total": {"passed": 1108, "files": 144, "skipped": 0, "failed": 0}}`。新增19条（工具17、文字等价2）；矩阵采用INSTR编号，D6代码行已落地，设备不足项单列。

## 偏离、冲突与建议

- 路径协议与打点要求冲突：任务要求七玩法/core打点，但副本协议禁止覆盖核心和其它玩法且未提供独占玩法路径。副本完成并验证全部lib改动，核心8文件与文字等价测试保存core_patch.diff；玩法15文件保存gameplay_patch.diff；真实仓库仅回拷工具、工具测试及共享文档定点追加。应用两补丁及核心矩阵追加后主会话需重跑门禁，不冒充已经合并。
- 旧driver要求完整Raster/GC参照会误伤本批冷窗口和CPU窗口；现先保存原始response，仅对真实已测首帧的指定SDK错误降级，CPU明确未采GC参照。
- 建议 ARCHITECTURE §8.3 的文字测量器缓存表补充“同一布局实例最多256项(text, style)精确宽度，dispose清空”。splitLuckyText 对n个码点调用约O(n)次前缀layout，总整形工作可近O(n²)，不应写成O(n²)次layout；本批没有改变换行公式、回调顺序或采用单字宽相加。
- 首帧schema只支持旧wheel绝对信息，保持兼容，将有效增量与新预算追加instr字段；建议后续增加空白来源、增量/绝对指标类型，避免把26.612ms增量直接比到绝对首帧。
- 不能从 Timeline 的1.ui标签推导Linux tid；当前UI/platform合并，按主线程原始stat归类。建议以后采样元数据显式记录线程角色与合并状态。
- CPU窗口请求5秒，真实时长含首读开销，按真实主机间隔计算；同轮FrameTiming覆盖完整握手区间，不把两者边界说成完全相等。lotto本次仅搅拌阶段，完整开奖CPU未测。
- 手机接手实测stay_on=2，中途实测变为0，来源未定位；本批未执行设置写入命令，已异步请求操作者恢复。最终值见device_final.json；若仍0则收尾目标未满足，不写成已恢复2。卸载命令返回DELETE_FAILED_INTERNAL_ERROR，但随后package列表与pm path均空，不把失败退出码写成0。
- 原始DEVFIN/MET2报告与所有失败标记保留，不能把本轮首帧改善外推为稳态硬门禁已通过；未重测原slot_raster/lots等未通过项。

### 修改的库文件（仅副本与补丁）

- `lib/src/capsule/layout/capsule_layout.dart`（gameplay）。
- `lib/src/capsule/render/capsule_painter.dart`（gameplay）。
- `lib/src/core/image/image_resolver.dart`（core）。
- `lib/src/core/render/cached_picture.dart`（core）。
- `lib/src/core/render/paint_helpers.dart`（core）。
- `lib/src/core/render/perf_trace.dart`（core）。
- `lib/src/core/render/picture_cache.dart`（core）。
- `lib/src/core/text/split_text.dart`（core）。
- `lib/src/core/text/text_line.dart`（core）。
- `lib/src/core/text/text_measurer.dart`（core）。
- `lib/src/grid/layout/grid_layout.dart`（gameplay）。
- `lib/src/grid/render/grid_painter.dart`（gameplay）。
- `lib/src/lots/layout/lots_layout.dart`（gameplay）。
- `lib/src/lots/render/lots_painter.dart`（gameplay）。
- `lib/src/lotto/layout/lotto_layout.dart`（gameplay）。
- `lib/src/lotto/render/lotto_painter.dart`（gameplay）。
- `lib/src/number_wheel/layout/number_wheel_layout.dart`（gameplay）。
- `lib/src/number_wheel/render/number_wheel_painter.dart`（gameplay）。
- `lib/src/slot/layout/slot_layout.dart`（gameplay）。
- `lib/src/slot/render/slot_atlas.dart`（gameplay）。
- `lib/src/slot/render/slot_painter.dart`（gameplay）。
- `lib/src/wheel/layout/wheel_layout.dart`（gameplay）。
- `lib/src/wheel/render/wheel_painter.dart`（gameplay）。

## INSTR 真实仓库回拷复验

共享路径重读后定点追加；真实lib未覆盖。23个库候选文件（核心8、玩法15）和核心等价测试以两份diff交付，两补丁在快照上git apply --check --ignore-space-change均exit0；核心矩阵2行/COV-02见core_acceptance_append.md。真实仓库格式检查7个自有Dart路径exit0；flutter test test/tool为223/223、0失败/跳过（45.310s）；check_imports为145 lib PASS；check_acceptance为1552 references/1131 registered tests PASS。副本四组全量1108/1108（144文件，554/130/401/23），行覆盖6878/6878=100%，主包/bench分析均0 issue，format360文件0改动；矩阵静态与from-json均1554/1133，parity16例/96产物未变，publish --dry-run压缩包248KB、Package has 0 warnings。登记与主包执行计数差25是独立example/bench注册，不冒充全部设备运行。

最终实测 2026-11-10T18:20:04.5409880Z：屏幕ON=True、Awake=True、未锁=True，stay_on=0（要求2，未通过）、亮度模式=0、亮度=1；当前用户bench包列表及pm path为空。卸载命令exit1/DELETE_FAILED_INTERNAL_ERROR，未冒充退出0。常亮变化来源未定位，本批没有执行任何设置写入命令。

进程末检没有自有dart/flutter_tester；两次single-use Gradle已退出，接手前Kotlin PID7968保留，没有按java.exe批杀。首尾git log仍443589a3/f0b64ae1，未add/commit/push。完整路径和共享文件变更见validation/copy_manifest.json，真实复验日志见validation/real_*。CPU完整链路wheel仅2/5，其余四项各三轮；lotto仅搅拌阶段，任务完成状态为PARTIAL。
