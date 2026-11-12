# luckdraw 安卓真机 profile 基准（T4.6 / B11b）

## PEND：下一次真机会话的一条命令

本批只完成离线分析和工具准备，没有执行采集分支。当前三项硬失败与lots不确定仍保留；详见[逐帧根因报告](../../docs/PERF_ROOTCAUSE_REPORT.md)。

```powershell
# PowerShell7，在 luckdraw 包根运行；约40–60分钟。
./tool/bench/run_pending_device_checks.ps1 -DeviceSerial <serial> -ApplicationBinary <新入口profile.apk>
```

前提：APK必须是包含 `integration_test/pending_bench_test.dart` 入口、开启 `LUCKDRAW_TIMELINE=true` 的已构建profile包。历史perf.apk没有新场景，不可冒充可用；本批禁构建，APK准备仍待下一次有设备使用权的会话。脚本始终 `--use-application-binary`，不调用Gradle、不隐式构建、不改手机亮度/常亮设置。请事先保持用户希望的正常亮屏未锁屏状态。实体设备必须在线、主机空闲物理内存≥4GiB；锁屏等待最长15分钟，温度未知或>42°C明确失败。

顺序：

1. `blank_first_frame`三轮：只有Scaffold+空SizedBox的冷push页面。
2. `wheel/grid/slot_first_frame`各三轮：相同MaterialApp/Scaffold外壳与FrameTiming UI计时；输出三轮中位数以及玩法减空白的有符号差。历史wheel原测法保留；旧40.378ms不能直接减新外壳的空白基线。
3. `cpu_wheel_steady/cpu_grid_steady/cpu_slot_steady/cpu_capsule_mixing/cpu_lotto_draw`各三轮：乐透CPU只测搅拌。窗口外建立localhost TCP反向转发，before/start/end握手确认窗口；前后各一次，五秒内第0/1/2/3/4秒各采一次cpuinfo+线程top，五次须在各自一秒内完成。仅这些CPU命令可在窗口内运行，本脚本没有其它adb看护轮询。
4. `slot_raster/grid_steady/lotto_draw/lots_shaking`各三轮帧时复测：沿用原稳态/完整开奖与五次RSS循环。初始39次独立进程启动；每项失败尝试也计数，最多五次，只在有效轮不足三次或成本未污染不足两次时补样，不替换坏轮。

每轮force-stop、复用相同APK并记录哈希；轮前和轮后核实亮屏/锁屏状态，窗口中途DIM或系统干扰无法由这些快照独立排除。CPU保存七组cpuinfo/top原文及解析值、进程PID、UI/Raster/其它线程、时间和跨度；原生CPU统计区间见原文，不声称每条cpuinfo都恰好覆盖同一个五秒，也不再由FrameTiming估算进程CPU。解析失败、PID改变、缺角色或采样越窗显式失败。

结果写 `tool/bench/results/pending/`，拒绝已有目录防止混样；`runs.json`保留全部尝试。`assess_pending.dart`调用唯一MET2比较器的 `--scenarios=slot_raster,grid_steady,lotto_draw,lots_shaking --rss-all-scenes` 局部模式，冻结预算不改；`REPORT.md`/`assessment.json`输出「通过/已标定/失败/不确定」。至少两个未污染窗口才评估成本，任一真实交付或未污染12/4ms余量失败优先；不稳定或样本不足仍不确定。首帧/CPU只标定实测基线，没有批准阈值时不代表性能达标。

本机离线验证（不接触设备）：`flutter test test/tool/bench_pending_test.dart --no-pub --concurrency=1`。`-PlanOnly`在任何设备/文件系统动作之前返回编排JSON，仅用于单测；它不证明采集协议已在真机通过。空白/玩法结构、Android16合成夹具、解析失败、五次采样时序、启动上限、trace配对、PowerShell语法与CLI合成收尾均有单测，登记PEND-01～16。

本工程独立于主包，`luckdraw: {path: ../..}`。直接依赖仅 Flutter SDK、
SDK 的 integration_test/flutter_driver/flutter_test 和本地 luckdraw。
不引入 pub.dev 依赖，不直接使用 vm_service，不在 Windows 桌面采集基准。

Android 壳使用 Gradle 8.14.3 / AGP 8.11.1 / Kotlin 2.2.20 / JDK 17，
按本机 Flutter 3.47 DependencyVersionChecker 的最低版本静态核对。
Dart/Flutter API 保持 3.24 可用；DEV 批在 vivo V2417、Android 16 / API 36、
Flutter 3.47.0 上执行，完整结果与限制见 ../../docs/DEVICE_REPORT.md。

**MET按保存原值修正背压污染口径：11场景4通过、6失败、首帧1信息项，性能尚未完全通过。**
测量状态保存在 [budgets.status.json](budgets.status.json)，不得把单测合成数据当实测。

## MET 当前规则与离线复现

完整证据见 [度量修正报告](../../docs/METRIC_FIX_REPORT.md) 与 [逐窗口重算](results/met/REPORT.md)。
纯离线命令（无需设备）为：

```powershell
python tool/bench/recalculate_met.py
dart run tool/bench/compare.dart --input=tool/bench/results/met/comparison --rss-all-scenes --classify-windows --output=tool/bench/results/met/assessment.json
```

以上命令从包根运行。Python只用标准库准备原始数据、画分布SVG和报告；所有正式预算判定由Dart纯函数执行。
第二条预期退出1：成本有失败，不能将完成重算写成性能全部通过。`--input`、`--budgets`、`--rss-all-scenes`原参数兼容；
分类默认开启，新增`--classify-windows`使命令自描述，`--output`保存完整证据。

污染规则：fps≥59，帧数≥0.98×elapsed_micros/1e6×60，Raster P90≥15.5ms，三者同时满足。
130个唯一稳态窗口P90间隙为8.848–16.490ms，阈值位于间隙；污染25个，参照65个中污染9个。
所有稳态窗口交付都检查，失败立即使场景失败；参照同规则仅报告。
成本仅取未污染窗口中位数，偶数取两中值平均；至少两个，否则UNCERTAIN，最多补到同配置五次启动。
极差/中位数≤30%在未污染窗口间评估；全零稳定，零中位数非全零失败。
稳定且≤目标通过；超出≤15%用中位数×1.1向上取整首版标定（ms精度0.001，比例0.000001）；
超15%或不稳定不改预算。MET保守沿用进入本批的FIN目标与更严历史校准值，原目标冻结在状态文件met.targets，避免重复放宽。
RSS仍取全部轮次、五循环、稳态1.5MiB、页面峰值5622989B、预热仅信息。P99首版无预算，仅诊断；显式配置P99上限时支持门禁。
新标定仅wheel Raster平均5.610ms、lever UI P90 2.306ms、lots UI P90 2.227ms、lotto UI P90 3.655ms。
FIN批准UI平均值保留；slot_raster虽仅超6.4%，因不稳定没有自动重标。

首帧40.378ms为INFO，预算文件`informational:true`，历史4ms不作门禁。下一次真机会话需先完成以下准备，**本批未实现、未运行**：

1. 在`lib/main.dart`添加`SCENARIO=blank_first_frame`的空白页冷push路由；
   在`integration_test/blank_first_frame_bench_test.dart`新增空白首帧采集，沿用完整UI FrameTiming，不启用动画。
   给driver/报告schema登记`blank_first_frame`信息键，保留run_id、设备与时间。
2. 独立应用进程测空白首帧三次，再同环境测wheel首帧三次；每轮保留原值。
3. 用`median(wheel_first_frame)-median(blank_first_frame)`估算增量成本，再由维护者制定正式预算；不能直接把40ms当库成本或通过。

准备完成后的未来命令（在tool/bench执行，替换真实序列号；本批禁止运行）为：

```powershell
foreach ($round in 1..3) {
  flutter drive --profile --no-pub --driver=test_driver/perf_driver.dart --target=integration_test/blank_first_frame_bench_test.dart --dart-define=SCENARIO=blank_first_frame -d <serial>
}
foreach ($round in 1..3) {
  flutter drive --profile --no-pub --driver=test_driver/perf_driver.dart --target=integration_test/wheel_bench_test.dart --dart-define=SCENARIO=wheel -d <serial>
}
```

wheel现有目标同时包含稳态和首帧测试，可保留完整输出，仅使用对应first_frame报告作差；准备时给blank目标注册独立验收编号。
设备采集脚本和历史Python校准脚本仍是旧三轮策略；不要用它们自动覆盖MET预算。补跑需显式管理同配置总启动≤5及未污染样本数。

## 场景

| reportKey | 场景 | 对应测试 |
| --- | --- | --- |
| wheel_steady | 12 奖品，每项独立 128×128 PNG + 两行文字，cruising 后 5s | wheel_bench_test.dart |
| wheel_first_frame | 空白页 push 到冷页面首帧，测完整 UI 耗时 | wheel_bench_test.dart |
| grid_steady | 3×3，外围八奖品 + 中心按钮，阴影和渐变，cruising 5s | grid_bench_test.dart |
| slot_steady | 三列、十奖品（各一图片），picture 模式 5s | slot_bench_test.dart |
| slot_raster | 同一配置，显式 raster 模式 5s | slot_bench_test.dart |
| lever_steady | 真实 LuckyLeverSlotMachine，三列十奖品，匀速 5s | lever_bench_test.dart |
| capsule_mixing | 十种奖品、每种三颗，共 30 胶囊，搅拌 5s | capsule_bench_test.dart |
| number_wheel_spin | 0–36 共 37 格，匀速盘面及小球 5s | number_wheel_bench_test.dart |
| lots_shaking | 十二支签，匀速摇签 5s；暂沿用 wheel 的保守目标 | lots_bench_test.dart |
| lotto_draw | 35+12 共 47 球，进入 cruising 后搅拌 3s，再等完整开奖结束 | lotto_bench_test.dart |
| memory_cycles | 真正 push/pop 转盘页kRssCycles 次，每个页面/空白页稳定 2s 后采 RSS | memory_bench_test.dart |
| reference_spin | 每个稳态测试同轮先录 RotationTransition 方块 5s，作为 GC 参照 | 对应场景的 _reference 报告 |

图片在采集外用 Canvas 生成 PNG，走真实 MemoryImage 解码与 luckdraw 图片解析。
无网络、无额外 assets。全部控制器使用固定随机种子，图片失败或阶段未达到都会让测试失败。
所有玩法页有一致的 320×320 逻辑像素约束；不要调整设备字号、分辨率或刷新率后混用旧报告。

RSS 次数唯一来源为 `metrics.dart` 的 `kRssCycles = 5`；设备采集、比较器和单测
直接引用，PowerShell 从该声明读取。JSON拆分为 `rss_warmup_bytes` 与 `rss_steady_growth_bytes`，
结构自检要求正值初始RSS、`rss_cycles == kRssCycles`且两个原值数组长度吻合；旧汇总键不参与计算。
稳态增长上限为1.5MiB（1572864字节）；首次预热仅信息，页面峰值增量保留现有5622989字节上限。
拉霸机独立 report_key 为 lever_steady，预算沿用 slot 的首版目标，不与老虎机混合。
每场景先采三次有效轮；MET允许未污染不足两次时补样，总启动最多五次；其它波动不能靠挑轮消除。
旧尝试在 results/attempt2_rss20 归档，不计入本次结果。

中断后可用 `run_device.ps1 -ResultsDirectory <本次目录> -ReuseBinaries` 续跑；
脚本读取已有有效轮，三轮齐全的项目直接沿用，累计启动次数仍受原上限限制。
`-ReuseBinaries` 仅缓存本次同一场景成功验证的 profile APK，后续轮使用
`--use-application-binary`，每次仍 force-stop、安装并启动独立应用进程，生成新 run_id。
源码变化后必须开新目录；不要跨快照复用 APK。临时 binaries 不随报告导出。

历史DEV工具 `summarize_device.py --input=<本次目录> [--calibrate]` 核验设备身份、时间戳、
唯一 run_id、有效轮和 RSS 原值长度；输出逐指标中位数、极差与原预算对照。
校准只接受恰好三轮且该指标稳定、未超标的数据，按实测×1.1向上取整后与目标取较严者：
耗时精度0.001ms、比例精度0.000001、字节和GC次数取整数。不稳定项保持原目标。
当前预算比较以MET的compare.dart为准；历史诊断汇总不会把不稳定组改为通过。

DEV按当前口径复核：`dart run compare.dart --input=results/bench_20261110_180650/comparison --budgets=budgets.json --rss-all-scenes`。
历史design_budgets.json保留旧键作证据，不传入新比较器；旧summarize_device/analyze_perf输出也属于原批次口径，FIN之后不要用旧--calibrate覆盖批准预算。
当前结果为失败，详见报告中的波动和超标，不会因完成采集而变成PASS；修复后组合对比见下文FIN命令。
导出时原始timeline和日志使用无损gzip（`.timeline.json.gz` / `.log.gz`），
汇总JSON不压缩，比较命令可直接读取；复查原始事件时先用gzip解压。

## 连接与运行规程（TEST_STRATEGY §7.3）

以下规程仅采集安卓真机 profile 数据，不运行桌面基准或独立 flutter build。

1. 用 USB 连接安卓真机，启用开发者模式/USB 调试，接受设备授权；
   执行 `adb -s <serial> get-state`，确认序列号对应实体手机、状态为 device。
   不使用模拟器；绑定还会拒绝非 Android 或非 profile 模式。
2. 手机连接电源，记录现有省电、后台应用、亮度、刷新率与系统字号；不擅自修改系统设置；
   记录型号、Android/Flutter 版本、屏幕刷新率、环境温度和 Git 基线。
   固定正常手动亮度、USB常亮并避免DIM；测量窗口暂停轮询看护。每轮前后采电量和温度，超过42°C等待降温；结束恢复原设置。
3. **先检查并结束自己此前启动的 Gradle/Kotlin 守护进程**，释放内存；
   跑完后同样处理。先检查命令行与 PID，并确认所有权；不要按进程名批量结束用户的 java/node：
   `Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'GradleDaemon|KotlinCompileDaemon' } | Select-Object ProcessId,ParentProcessId,CommandLine`。
   确认属于本轮后才用 `Stop-Process -Id <PID>`；不调用 Gradle 的 stop 命令。
4. 在 `tool/bench` 中 `flutter pub get --no-example`，随即恢复/核对本工程的
   analysis_options.yaml（严格规则 + build/android 排除）。
   主包若也执行 pub get，同样立即恢复其 IMPLEMENTATION_GUIDE §2.3 配置。
5. 保留/归档已有 build 下的 timeline 文件，再清空**旧采集文件**开始一组；
   不混合不同设备/刷新率/版本的记录；先三次，MET成本至少两次未污染。
6. 只用 `flutter drive --profile`，逐文件串行、先三次有效轮；失败或未污染样本不足两次时可补，总启动≤5；后续复用 `--use-application-binary`，避免每轮Gradle；
   不另跑 flutter build，不并行运行 flutter test/analyze，也不手动运行 Gradle。
   每次构建前确认可用物理内存至少 4GiB，设置 Gradle workers=2；本批允许其它会话的 Gradle 并行，
   只保证自己的构建串行。基准期间不运行自己的 analyze 或本机 flutter test。

```powershell
# 在 luckdraw/tool/bench 中执行；替换为 adb 确认的真机序列号。
$deviceSerial = '<真机序列号>'
$targets = @('wheel', 'grid', 'slot', 'lever', 'capsule', 'number_wheel', 'lots', 'lotto', 'memory')
foreach ($target in $targets) {
  foreach ($run in 1..3) {
    flutter drive --profile --no-pub --driver=test_driver/perf_driver.dart --target="integration_test/${target}_bench_test.dart" --dart-define=LUCKDRAW_TIMELINE=true --dart-define="SCENARIO=$target" -d $deviceSerial
    if ($LASTEXITCODE -ne 0) { throw "基准失败: $target 第 $run 次" }
  }
}
dart run compare.dart
```

每个文件中的两个转盘测试、两个老虎机测试各有独立 reportKey；
每次 flutter drive 都从新应用进程开始。设备测试先检查 profile/Android，README
中的实体手机确认是必要步骤（Platform.isAndroid 无法区分安卓真机和模拟器）。
单个测试/driver 超时为四分钟，超过五分钟的挂起命令应终止，检查设备后按单文件重试。

## 采集、产物与预算口径

- integration_test.traceAction 记录原始 timeline；driver 对每个 reportKey 调用
  TimelineSummary.summarize 和 writeTimelineToFile(includeSummary: true)。
- `build/<reportKey>_<唯一 run_id>.timeline.json` 保留原始 trace；
  同名 `.timeline_summary.json` 保留 SDK 标准字段，并补充实际采样字段。
  同文件内场景共享 run_id；不同 drive 使用不同 run_id，防止覆盖或伪装三轮。
- FrameTiming 记录 build/raster 微秒耗时，过滤窗口外及延迟批量回调；
  帧数为零直接失败。均值转毫秒，P90 用最近秩 ceil(N×0.9)。
  实际帧周期为 1,000,000 / refresh_rate_hz 微秒；
  UI 或 Raster 任一超过周期即计一帧，二者同时超时不重复相加。
  保留 SDK missed_* 标准字段供复核，比较使用实际刷新率的 dropped_frame_ratio，
  避免 SDK 固定 60Hz 的计数误用于 120Hz。
- budget JSON 保持设计的 reportKey → metric → 上限结构；掉帧率文件值为 60Hz 上限
  0.005。100Hz 以上按 min(文件值×2, 0.01) 比较；90Hz 保守沿用 60Hz 预算。
  单位：耗时 ms、比例 0–1、RSS bytes（此处 MB 按 MiB=1024² 字节）。
- GC 优先使用 SDK new_gen_gc_count（3.47 本地源码已确认存在）；
  缺失时按原始 trace 的 Scavenge/CollectNewGeneration 开始 B/b 或完整 X 事件统计，
  不把结束 E/e 再算一次。比较同轮场景减同轮五秒参照，负数钳零；现有预算已校准额外次数上限为0。
  大乐透完整开奖长于五秒，当前仍与五秒参照比较，属于更严格的保守口径；
  首轮实测应在文档对齐时明确是否改为按五秒归一化。
- memory_cycles 的 rss_baseline、rss_pages[kRssCycles]、rss_blank[kRssCycles] 一并保留；
  页面增量取kRssCycles 个页面的最大 RSS 相对初始空白页，预热取首次返回相对初始空白页，稳态增长取最后返回相对首次返回；
  DEV 批为每个稳态玩法追加同样的kRssCycles 次循环，所有原值保存在对应 reportKey 中；
  五秒窗口的 RSS 单独记作 rss_steady_*，循环期间不覆盖稳态 timeline。
  负增量钳零，不强制 GC、不减去全局 ImageCache、不借用 vm_service。

`compare.dart` 可以从包根或 bench 目录执行，也支持
`--input=<报告目录> --budgets=<预算文件>`。它验证场景集合、必需指标、有限非负值、
非零帧数、唯一run_id、至少三次采集，以及全部稳态窗口交付完整。成本仅在未污染窗口检查至少两个样本、中位数与极差/中位数≤30%，输出PASS、FAIL、UNSTABLE或UNCERTAIN；RSS只比较绝对上限。
全零稳定；[0,0,1]仍不稳定；未污染不足两个最多补到同配置五次启动，不整组挑轮重跑。
缺数据、损坏文件、未知场景/预算字段、超预算均 exitCode=1；
参照报告只供诊断，不作为另一个预算场景。无真机数据时 compare 应失败，而非报告 100% 通过。

DEV 批还执行 `--rss-all-scenes`：为全部稳态玩法追加kRssCycles 次循环的 RSS 比较，
页面峰值上限复用memory_cycles现有5622989B，稳态增长改为1572864B；预热不进入预算结构。
帧时额外保留 build/raster 与逐帧合计的 p50/p90/p99，合计分位数按配对帧计算，不能相加两个分位数。

## 阴影对照

`run_device.ps1 -Task Shadow` 使用实体手机 profile，Skia/Impeller 各三轮，显式传后端参数；
截图驱动保存 PNG、设备 ROI 和时间戳，verbose 与本轮 logcat 用于核实后端身份。
`compare_shadow.py` 只用 Python 标准库，支持无交错 8 位 RGB/RGBA PNG；不新增工具依赖。
例如 `python compare_shadow.py --skia=<PNG> --impeller=<PNG> --metadata=<Skia元数据> --output=<目录>`。
输出通道阈值 32 的 ROI/阴影像素差异、RGBA 均绝对误差、阈值 2 灰阶的外扩半径、
水平扫描线 CSV、RGBA 曲线 SVG 与放大四倍的差异 PNG。须先确认两轮 DPR、布局完全一致。
当前老虎机格子填满滚轮视口，外扩阴影被 clipRect 裁剪；比较器明确输出
shadow_observable=false，仅比较填充，不用零阴影误差推断阴影一致。
四个独立九宫格样本和真实九宫格的阴影仍分别量化；本轮不为这处夹具限制追加截图轮次。

## 当前文档缺口与保守处理

- core 虽然有 perf_trace.dart，却尚无 luckdraw.layout / luckdraw.record 调用。
  本批不改 lib；冷页面首帧使用 FrameTiming.buildDuration（完整 UI，包含 build/layout/paint），
  first_frame_ui_millis当前仅信息；历史4ms估算不门禁，待空白页冷首帧三轮基线。
  first_frame_source 明确记录来源；未来有打点时额外输出 layout_record_millis，
  不默默用缺失打点生成零耗时。测试注册名仍逐字保留任务卡。
- LuckyImageResolver.debugDecodedBytes 位于宿主私有 resolver 上，现有 Widget 无公开读取途径。
  TODO：后续统一设计可观测接口后补解码字节真机采样；本批不通过私有字段访问或修改 core。
- R7-11 在任务卡验收清单中出现，但 TEST_STRATEGY 的该行是运动正确性；
  本批仅将数字转盘真机场景作为补充引用，不替代原有运动单测。
- DEV 已采 vivo V2417 的全部场景三轮，数据和预算结论见 DEVICE_REPORT.md，
  budgets.status.json.measured 保留逐指标中位数、极差和原目标；存在超标与不稳定组。
  历史DEV仅回填稳定且未超标指标；FIN已同步设计正文，当前UI/RSS批准变更及逐项对比见下文。

## 本机可执行的无设备验证

```powershell
# 主包根（覆盖率输出隔离）
flutter test test/tool/bench_metrics_test.dart test/tool/bench_compare_test.dart --no-pub --concurrency=1
dart run tool/check_imports.dart
dart run tool/check_acceptance.dart
# bench 工程（禁止运行 integration_test）
cd tool/bench
flutter analyze --no-pub
```

纯逻辑单测在主包 test/tool/bench_*_test.dart，覆盖 summarize、compareToBudget、
预算结构自检、GC/打点解析、帧统计及真实 Dart CLI 的成功/失败路径。
它们只生成明确标注的临时合成报告，测试结束删除，绝不写入 build 真机采集目录。


## PERF 缓存回归与消融

默认 `wheel_steady` 使用库的 auto 策略，运动期间用位图、静止后用 Picture。
`SCENARIO=wheel_steady_picture` 保留显式 Picture 对照。`run_perf.ps1` 的运行路由
在同一个 profile APK 内选择场景，`runs.json.variant` 区分对照；报告仍复用原场景
的 report_key，不增加或放宽 budgets.json 的预算。

```powershell
# 仅授权的 vivo V2417；每项三次有效轮，消融去文字/去图片仅一次。
./run_perf.ps1 -Variants wheel_picture,wheel_raster,wheel_no_text,wheel_no_images -Results results/perf_ablation
./run_perf.ps1 -Variants wheel_default,number_wheel_spin,capsule_mixing,lotto_draw,grid_steady,wheel_capture -Results results/perf_after -Rebuild
python analyze_perf.py
```

首次通过后自动保存独立 APK，后续 `--use-application-binary` 复用；结果目录已有
规定有效轮时不重复运行。每项最多五次启动，无效轮及原因保留；锁屏最多等待
十五分钟，单条 drive 超过五分钟终止自己的进程树。构建前检查4GiB空闲内存。
`wheel_capture` 单独保存37°的 Picture/auto PNG，不混入性能窗口；对应结果见
`../../docs/PERF_REPORT.md`。GLES 仍可能出现不稳定编码长延迟，禁止将消融收益
解释为所有预算已通过。

## FIN 离线口径与 MET 更新（2026-11-10）

RSS 保持 `kRssCycles = 5`：`rss_warmup_bytes = max(0, rss_blank[0] - rss_baseline)` 仅信息，不作门禁；建议6MiB只作为文档参考。`rss_steady_growth_bytes = max(0, rss_blank[4] - rss_blank[0])` 是第2–5次循环净增长，门禁为 **1572864 B（1.5MiB）**。逐次原值完整保留，负差表示回收。三轮取中位数；RSS 不采用帧时的相对极差30%规则，粗粒度 RSS 不能证明泄漏，确定性释放保证由既有 dispose 计数类测试承担。页面峰值增量仍用现有5622989 B上限，不放宽。

MET复核：高档参照与主场景不同步，全部130稳态窗口交付完整，证据支持vsync背压。转盘未污染Raster平均中位数5.0996ms；正式11场景4通过、6失败、1首帧信息待标定，性能仍未完全通过；历史高档不能继续解释为纯绘制成本。

新UI平均预算：wheel1.0、number_wheel1.3、capsule2.0、lotto2.5、grid1.2ms；批准值与统一0.1ms取整的差异详见 [重算报告](results/fin/REPORT.md)。重算覆盖DEV全部循环场景与PERF全部有效三轮，保留有符号原始差值、来源SHA-256和中位数；最终比较选PERF五个修复场景、DEV其余场景，不冒充同一APK全量采样。

```powershell
dart run tool/bench/compare.dart --input=tool/bench/results/fin/comparison --rss-all-scenes
```

以上FIN命令现在也默认使用MET分类规则；FIN原始日志仍保留历史口径，不冒充重新采集。当前正式输入和复现命令见本页MET节，真实退出1，RSS稳态各场景中位数均通过；成本仍有FAIL/UNSTABLE，首帧仅信息。今后固定正常手动亮度、USB常亮、避免DIM，窗口内暂停轮询；先三轮、五次RSS循环，必要时补到最多五次启动，历史控制条件以原报告为准。

## MET2 当前离线政策（替代上文历史15%/六失败结论）

MET2（2026-11-10）纯离线复算：**帧交付完整（全部130个窗口约60fps，59.829927–60.176516，无真实丢帧，按timeline交付口径）；偶发窗口的Raster时间被vsync背压污染且与绘制内容无关（参照方块同样出现）；按真机实测标定了首版回归预算。** 不是性能全部达标：1项满足有效目标（memory，RSS沿用FIN口径）、5场景已标定但未达最初设计目标、3场景失败、1场景不确定、1首帧信息项。首帧与进程级CPU待下次真机会话标定；性能结论基于单台设备vivo V2417（Android 16）三轮数据，不是跨设备保证。PERF五场景与DEV其余场景沿用MET/FIN身份，并非同一APK全量重测。现有timeline不等于独立面板呈现测量；污染窗口无法测量纯绘制成本。

比例类（`dropped_frame_ratio`及同类0–1比例）稳定性采用绝对极差≤0.01（1个百分点），避免近零中位数放大相对误差；时间类中位数<0.5ms时绝对极差≤0.15ms，其余时间/字节相对极差≤30%。RSS仍只按FIN绝对上限，不做相对稳定性门禁。成本至少2个未污染窗口，偶数取中间两项平均；不足或不稳定均为「不确定，需补跑」。所有稳态窗口必须fps≥59且帧数≥期望98%，否则失败；污染判定仍追加Raster P90≥15.5ms，阈值与窗口规则不变。

显式首版标定仅用于稳定时间指标：`max(实测中位数×1.1向上取整到0.001ms, 有来源且不高于FIN/MET既有批准值的历史标定下限)`；未标定的设计估算不能充当下限，比例/GC/RSS不重标。正常`compare.dart`只比较冻结后的`budgets.json`，不得每次回归自动放宽；`--calibrate`仅输出建议。最初`design_target`来自DEV保存的设计快照，MET前目标（含FIN批准值）另存`target`，`gap_to_design=实测中位数/design_target−1`，零目标差距无定义。历史标定下限及来源在`budgets.status.json.met2`冻结，重复重算不叠加。原设计目标达成与回归门禁通过分开列示。

新增硬门禁独立检查**每一个未污染窗口**：同帧build+raster合计P99≤12.0ms（16.67ms至少预留4.5ms），且UI P99≤4ms。任一超标直接失败，优先于不确定，不能用跨窗口中位数掩盖。保存数据中grid=12.231ms、slot_raster=16.905ms、lotto=12.229ms超合计上限，lotto UI P99还达4.386ms；不调整阈值。lots的Raster均值/P90相对极差41.69%/53.75%，仍不稳定，需下次同配置调查补跑，不能挑好窗口。

| 场景 | 未污染/总窗口 | UI均值 ms | Raster均值/P90 ms | 结论 |
| --- | --- | --- | --- | --- |
| wheel_steady | 2/3 | 0.9365 | 5.0996/6.7480 | 已按实测标定（未达最初设计目标） |
| wheel_first_frame | 不适用 | — | —/— | 信息项，待标定 |
| grid_steady | 3/3 | 1.0243 | 5.4998/6.5570 | 失败 |
| slot_steady | 2/3 | 1.3576 | 3.4481/3.9580 | 已按实测标定（未达最初设计目标） |
| slot_raster | 3/3 | 1.0641 | 2.7681/3.1630 | 失败 |
| lever_steady | 3/3 | 1.3999 | 3.7137/4.2170 | 已按实测标定（未达最初设计目标） |
| capsule_mixing | 3/3 | 1.6541 | 3.8083/4.3140 | 已按实测标定（未达最初设计目标） |
| number_wheel_spin | 2/3 | 1.1357 | 2.9759/3.3465 | 已按实测标定（未达最初设计目标） |
| lots_shaking | 2/3 | 1.3782 | 3.8951/4.8300 | 不确定，需补跑 |
| lotto_draw | 2/3 | 2.2188 | 4.8241/5.4880 | 失败 |
| memory_cycles | 不适用 | — | —/— | 满足设计目标 |

| 未达最初设计目标的场景 | 指标与差距（实测中位数/最初目标−1） |
| --- | --- |
| wheel_steady | Raster均值 +1.99% |
| grid_steady | UI均值 +70.72%、UI P90 +18.67%、Raster均值 +37.49% |
| slot_steady | UI均值 +35.76% |
| slot_raster | UI均值 +6.41% |
| lever_steady | UI均值 +39.99%、UI P90 +4.80% |
| capsule_mixing | UI均值 +10.27% |
| number_wheel_spin | UI均值 +13.57% |
| lots_shaking | UI均值 +37.82%、UI P90 +1.20% |
| lotto_draw | UI均值 +47.92%、UI P90 +10.75% |

复现：包根执行`python tool/bench/recalculate_met2.py`；只读历史采集，重算输出到`results/met2/`并冻结预算，绝不运行设备命令。正常`dart run tool/bench/compare.dart --input=tool/bench/results/met2/comparison --rss-all-scenes`退出1，3硬失败、1不确定。首次标定与正常回归分离，重复重算不叠加放宽。预算、CPU示意、逐项中位数/设计目标/差距见[MET2报告](results/met2/REPORT.md)。CPU仅由帧耗时推算，未做进程CPU实测；首帧空白基线与进程CPU待下次真机会话。


## STEADY：带打点的稳态归因与 wheel CPU

在副本的 `tool/bench` 下运行 `./run_steady_device_checks.ps1`。脚本只测
slot_raster、grid_steady、lotto_draw、lots_shaking 与 cpu_wheel_steady，每项三轮，
最多五次启动；第一轮用 `flutter drive --profile` 构建，后续复用相同 APK。
构建前必须自行确认仅一个自有 Gradle、workers=2、空闲物理内存≥4GiB。
不执行独立 flutter build，不改手机设置，不 kill-server，不做窗口内额外 adb 轮询。
脚本拒绝覆盖已有 runs.json；失败尝试也占启动次数。锁屏时只唤醒并上滑，
仍有 PIN 则停止，保留结果等待用户解锁，不猜密码。

编译期开启 `LUCKDRAW_TIMELINE=true` 与 `LUCKDRAW_STEADY_ENTRY=true`。
后者只在 slot_raster 的 mount 周围增加独立 `slot_raster_entry_reference` trace，
与五秒 GC 参照和 cruising 后的稳态窗口分别保存，不把首帧混进稳态 P99。
入场事件保存的是 SlotAtlas.prepare 同步调用区间；实际 GPU 执行/上传仍须以引擎事件为证。
CPU 使用 `proc_cpu_sampler.dart`，窗口前探测 PID/权限，窗口内首尾各一次读取，
按 /proc 累计节拍与真实主机单调间隔计算；UI/platform 合并时明确报告合并角色。

离线重放：`python tool/bench/analyze_steady.py`，输出 results/steady/frames.json 和
ATTRIBUTION.md。按 frame_number 关联 UI/Raster 并核对 SDK 数组；12ms/4ms 与
MET2 污染规则不变。逐事件包含耗时不能相加，墙钟不是 CPU，缺证据写无法判定。
合成边界回归由 `flutter test test/tool/bench_steady_test.dart` 执行，真实采集结论见
[STEADY 报告](results/steady/REPORT.md)。
