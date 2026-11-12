# DEV 安卓真机验证报告

本次设备为 **vivo V2417**，序列号 `10AE9K17UE0011S`；Android 16 / API 36、arm64-v8a、Qualcomm SM4450（parrot）、约 7.6GB 内存、1080×2400、系统密度 440 dpi。本报告不使用其它机型的结果。

集成验证开始时间：2026-11-10 16:28（Asia/Shanghai）。Flutter 3.47.0 stable（4cf2416426），Dart 3.13.0。副本为 `C:\ldd\luckdraw`，沿用已有副本，未重建。上次中断的运行不计有效轮，旧日志已归档至 `C:\ldd\dev_logs\attempt1\`。

## 执行约定

- 只修改夹具、基准工具及本报告；不修改产品 `lib/`、依赖或其它包，不提交版本。
- Android 串行集成测试；性能只在实体手机 profile 模式采集，每组连续三轮。每个构建前可用物理内存至少 4GiB，Gradle workers=2；允许其它会话并行构建。
- USB 供电并临时 `svc power stayon usb`；不修改系统动画、亮度、刷新率、省电等其它设置。开始时前台为开发者设置，未主动清除其它后台应用。
- 基准每轮 force-stop 自有应用、记录温度与电量，超过 42°C 等待降温。结束恢复 `svc power stayon false`。

## A：Android 集成测试（T4.5）

命令（包根）：`dart run tool/run_integration.dart --device=10AE9K17UE0011S --repeat=3`。

生命周期保持 resumed → inactive → hidden →（真实等待 10 秒，不 pump）→ inactive → resumed。

已完成：**33/33，通过率100%，累计1,595,498ms**（含逐轮内存检查、构建、安装及执行）。有效整组于2026-11-10 16:41:43开始，17:08:21结束；11个文件均恰好三轮，无失败、无超时。报告最后修改时间为2026-11-10 09:08:21 UTC，5915字节，设备序列号核对一致。

| 文件 | 第1轮 | 第2轮 | 第3轮 | 结论 |
| --- | --- | --- | --- | --- |
| capsule_flow_test.dart | 通过，61327ms | 通过，105417ms | 通过，45273ms | 3/3 |
| grid_flow_test.dart | 通过，67285ms | 通过，43183ms | 通过，42815ms | 3/3 |
| lever_flow_test.dart | 通过，44745ms | 通过，48250ms | 通过，51719ms | 3/3 |
| lifecycle_test.dart | 通过，67602ms | 通过，39198ms | 通过，40564ms | 3/3 |
| lots_flow_test.dart | 通过，31928ms | 通过，34293ms | 通过，30564ms | 3/3 |
| lotto_flow_test.dart | 通过，41908ms | 通过，37484ms | 通过，39905ms | 3/3 |
| number_wheel_flow_test.dart | 通过，38575ms | 通过，38017ms | 通过，33068ms | 3/3 |
| resize_test.dart | 通过，30014ms | 通过，32355ms | 通过，58696ms | 3/3 |
| route_test.dart | 通过，63140ms | 通过，61017ms | 通过，82098ms | 3/3 |
| slot_flow_test.dart | 通过，45266ms | 通过，32434ms | 通过，39533ms | 3/3 |
| wheel_flow_test.dart | 通过，63919ms | 通过，68461ms | 通过，35445ms | 3/3 |

原始产物：[android_integration_report.json](device/android_integration_report.json)。以下原文保持执行器输出：

```json
{
  "device": "10AE9K17UE0011S",
  "repeat": 3,
  "files": [
    "capsule_flow_test.dart",
    "grid_flow_test.dart",
    "lever_flow_test.dart",
    "lifecycle_test.dart",
    "lots_flow_test.dart",
    "lotto_flow_test.dart",
    "number_wheel_flow_test.dart",
    "resize_test.dart",
    "route_test.dart",
    "slot_flow_test.dart",
    "wheel_flow_test.dart"
  ],
  "total": 33,
  "passed": 33,
  "failed": 0,
  "passRate": 1.0,
  "elapsedMs": 1595498,
  "complete": true,
  "success": true,
  "runs": [
    {
      "file": "capsule_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 61327,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "capsule_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 105417,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "capsule_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 45273,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "grid_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 67285,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "grid_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 43183,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "grid_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 42815,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lever_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 44745,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lever_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 48250,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lever_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 51719,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lifecycle_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 67602,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lifecycle_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 39198,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lifecycle_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 40564,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lots_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 31928,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lots_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 34293,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lots_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 30564,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lotto_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 41908,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lotto_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 37484,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "lotto_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 39905,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "number_wheel_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 38575,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "number_wheel_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 38017,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "number_wheel_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 33068,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "resize_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 30014,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "resize_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 32355,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "resize_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 58696,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "route_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 63140,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "route_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 61017,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "route_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 82098,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "slot_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 45266,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "slot_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 32434,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "slot_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 39533,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "wheel_flow_test.dart",
      "attempt": 1,
      "exitCode": 0,
      "elapsedMs": 63919,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "wheel_flow_test.dart",
      "attempt": 2,
      "exitCode": 0,
      "elapsedMs": 68461,
      "timedOut": false,
      "passed": true
    },
    {
      "file": "wheel_flow_test.dart",
      "attempt": 3,
      "exitCode": 0,
      "elapsedMs": 35445,
      "timedOut": false,
      "passed": true
    }
  ]
}
```


## B：真机 profile 基准（T4.6）

第三次尝试于2026-11-10 18:06开始，19:35完成采集。全部八种玩法均已采集，另有老虎机raster、冷首帧和独立RSS：**11个报告场景各3轮，共33份有效测量**。执行器实际启动31次，27次有效（部分文件含两个报告场景），4次无效已排除；每项最多启动4次，未超过5次上限。没有重跑有效整组，也没有因波动追加轮次。

RSS唯一来源为 `metrics.dart` 的 `kRssCycles = 5`；每轮仅5次push/pop，页面和空白页各稳定2秒。页面增量上限12MiB；5次增长上限0.5MiB（524288字节，每次0.1MiB）。原数据完整保留，负增长钳零，不强制GC。旧数据归档至 `tool/bench/results/attempt2_rss20/`，未混入新采集。

命令：副本 `tool/bench` 下 `./run_device.ps1 -Task Bench`，之后按同一结果目录 `-ResultsDirectory ... -ReuseBinaries` 续跑。内部始终 `flutter drive --profile --no-pub --no-dds`，指定本机序列号、perf_driver及对应目标。后续同场景轮次可用本次已成功验证的profile APK加 `--use-application-binary`；仍force-stop、重新安装/启动应用并生成新run_id。所有实际构建前可用物理内存≥4GiB，最小4285632KiB，workers=2；复用APK时没有Gradle构建。没有单独运行flutter build。

设备电池温度28.7–30.1°C，电量50–56%，无超过42°C的轮次。每轮前后温度、电量、主机内存、命令、时间和有效状态见 [runs.json](../tool/bench/results/bench_20261110_180650/runs.json)。所有耗时场景均有非零FrameTiming与fps，报告均核对本轮生成时间、设备型号和唯一run_id。

### 帧时与RSS中位数

场景 | 有效轮 | UI p50/p90/p99 ms | Raster p50/p90/p99 ms | 合计 p50/p90/p99 ms | 掉帧率 | RSS增量/增长 MiB | GC/参照
--- | --- | --- | --- | --- | --- | --- | ---
wheel_steady | 3/3 | 0.934/1.509/1.930 | 16.440/17.536/19.181 | 17.489/18.746/20.510 | 35.5482% | 2.520/2.074 | 2.000/10.000
wheel_first_frame | 3/3 | 0.309/40.378/40.378 | 2.821/3.150/3.150 | 3.117/44.306/44.306 | 50.0000% | — | 0.000/—
grid_steady | 3/3 | 0.860/1.611/2.120 | 5.138/7.200/8.177 | 5.858/8.649/9.206 | 0.0000% | 0.281/0.281 | 0.000/10.000
slot_steady | 3/3 | 1.221/1.908/2.502 | 3.498/4.084/4.633 | 4.738/6.058/6.578 | 0.0000% | 1.402/1.363 | 2.000/10.000
slot_raster | 3/3 | 1.008/1.405/1.787 | 2.782/3.163/3.455 | 3.796/4.698/5.409 | 0.0000% | 0.473/0.000 | 0.000/2.000
capsule_mixing | 3/3 | 1.681/2.865/3.611 | 5.674/6.820/8.933 | 7.499/9.597/11.035 | 0.3311% | 1.785/1.664 | 2.000/10.000
number_wheel_spin | 3/3 | 1.082/1.780/2.302 | 7.140/8.848/16.524 | 8.319/10.496/17.557 | 1.0000% | 1.113/1.152 | 2.000/10.000
lots_shaking | 3/3 | 1.226/1.992/2.662 | 4.613/6.128/7.093 | 5.775/7.988/8.864 | 0.0000% | 1.137/1.137 | 0.000/10.000
lotto_draw | 3/3 | 2.190/3.816/5.026 | 5.876/6.439/12.156 | 8.057/10.404/14.222 | 0.1727% | 1.176/1.176 | 2.000/10.000
memory_cycles | 3/3 | —/1.744/2.529 | —/5.992/12.183 | —/—/— | — | 4.875/4.875 | 4.000/—
lever_steady | 3/3 | 1.200/2.096/2.754 | 3.732/4.217/4.779 | 4.910/6.258/6.876 | 0.0000% | 1.793/2.035 | 2.000/10.000

单位ms、MiB；RSS一列依次是页面最大增量/5次返回空白页后的增长。帧时合计分位数按同一帧的build+raster计算。冷首帧行是其短窗口诊断统计，正式首帧判据为first_frame_ui_millis，中位数40.378ms，预算4ms；不拿该窗口p50替代首帧，也不把短窗口掉帧率当稳态指标。

### 逐轮结果与耗时

| 场景文件 | 启动/有效 | 第1次 | 第2次 | 第3次 | 第4次 |
| --- | --- | --- | --- | --- | --- |
| wheel_bench_test.dart | 4/3 | 有效，186671ms | 无效，62818ms | 有效，92647ms | 有效，92646ms |
| grid_bench_test.dart | 3/3 | 有效，112418ms | 有效，102463ms | 有效，92495ms | — |
| slot_bench_test.dart | 4/3 | 有效，175097ms | 无效，166922ms | 有效，232878ms | 有效，164523ms |
| lever_bench_test.dart | 3/3 | 有效，136762ms | 有效，119827ms | 有效，86735ms | — |
| capsule_bench_test.dart | 3/3 | 有效，158131ms | 有效，140554ms | 有效，261040ms | — |
| number_wheel_bench_test.dart | 4/3 | 有效，172794ms | 有效，115195ms | 无效，13267ms | 有效，274732ms |
| lots_bench_test.dart | 4/3 | 无效，309231ms | 有效，227845ms | 有效，154797ms | 有效，73170ms |
| lotto_bench_test.dart | 3/3 | 有效，120644ms | 有效，71922ms | 有效，82274ms | — |
| memory_bench_test.dart | 3/3 | 有效，233794ms | 有效，51357ms | 有效，63531ms | — |

四个无效轮：wheel第2次为主机页面文件不足（OS1455，驱动未启动）；slot第2次为Windows进程异常退出（-1073740791，当时主机物理/提交内存不足，未获得手机采样，不判定产品缺陷）；number_wheel第3次中途锁屏，立即作废，按15秒等待解锁后补缺；lots第1次构建在5分钟检查点后被终止（记录309231ms，含检测/清理延迟）。其余没有无效轮。

两次资源门槛等待、为复用APK/移除非构建轮额外内存等待而做的安全边界续跑，均未额外启动应用，不计为测试轮次。停止执行器时先核实当前轮已完成或尚未启动，恢复USB常亮后再续跑；所有历史有效记录均沿用。

### 原目标比较与预算回填

对照首版目标共75项（含各玩法RSS），31项中位数超标，39项三轮极差/中位数大于30%；两集合有交集。`compare.dart --rss-all-scenes --input=.../comparison --budgets=.../design_budgets.json` 实际exit=1：`三次极差 > 30%，本组不稳定，不自动重跑: average_frame_rasterizer_time_millis`。按最高优先级不重跑，不把诊断中位数当稳定组通过。

仅20项三轮齐全、该指标稳定且中位数未超标的预算按实测×1.1向上取整回填，且不超过首版目标。耗时精度0.001ms，比例精度0.000001，字节/GC为整数。原目标见 [design_budgets.json](../tool/bench/results/bench_20261110_180650/design_budgets.json)，设备与日期、全部实测/极差见 [budgets.status.json](../tool/bench/budgets.status.json)。超标或不稳定项保持原目标。

| 场景 | 超标指标 | 实测中位数 | 原上限 |
| --- | --- | --- | --- |
| wheel_steady | average_frame_build_time_millis | 1.044973 | 1.000000 |
| wheel_steady | average_frame_rasterizer_time_millis | 16.449040 | 5.000000 |
| wheel_steady | 90th_percentile_frame_rasterizer_time_millis | 17.536000 | 8.000000 |
| wheel_steady | dropped_frame_ratio | 0.355482 | 0.005000 |
| wheel_steady | rss_growth_5_cycles_bytes | 2174976.000000 | 524288.000000 |
| wheel_first_frame | first_frame_ui_millis | 40.378000 | 4.000000 |
| grid_steady | average_frame_build_time_millis | 0.960349 | 0.600000 |
| grid_steady | 90th_percentile_frame_build_time_millis | 1.611000 | 1.500000 |
| grid_steady | average_frame_rasterizer_time_millis | 5.419003 | 4.000000 |
| grid_steady | 90th_percentile_frame_rasterizer_time_millis | 7.200000 | 7.000000 |
| slot_steady | average_frame_build_time_millis | 1.357413 | 1.000000 |
| slot_steady | rss_growth_5_cycles_bytes | 1429504.000000 | 524288.000000 |
| slot_raster | average_frame_build_time_millis | 1.064066 | 1.000000 |
| capsule_mixing | average_frame_build_time_millis | 1.890252 | 1.500000 |
| capsule_mixing | average_frame_rasterizer_time_millis | 6.009023 | 5.000000 |
| capsule_mixing | rss_growth_5_cycles_bytes | 1744896.000000 | 524288.000000 |
| number_wheel_spin | average_frame_build_time_millis | 1.242137 | 1.000000 |
| number_wheel_spin | average_frame_rasterizer_time_millis | 7.899330 | 5.000000 |
| number_wheel_spin | 90th_percentile_frame_rasterizer_time_millis | 8.848000 | 8.000000 |
| number_wheel_spin | dropped_frame_ratio | 0.010000 | 0.005000 |
| number_wheel_spin | rss_growth_5_cycles_bytes | 1208320.000000 | 524288.000000 |
| lots_shaking | average_frame_build_time_millis | 1.325767 | 1.000000 |
| lots_shaking | rss_growth_5_cycles_bytes | 1191936.000000 | 524288.000000 |
| lotto_draw | average_frame_build_time_millis | 2.504297 | 1.500000 |
| lotto_draw | 90th_percentile_frame_build_time_millis | 3.816000 | 3.000000 |
| lotto_draw | average_frame_rasterizer_time_millis | 6.090131 | 6.000000 |
| lotto_draw | rss_growth_5_cycles_bytes | 1232896.000000 | 524288.000000 |
| memory_cycles | rss_growth_5_cycles_bytes | 5111808.000000 | 524288.000000 |
| lever_steady | average_frame_build_time_millis | 1.399937 | 1.000000 |
| lever_steady | 90th_percentile_frame_build_time_millis | 2.096000 | 2.000000 |
| lever_steady | rss_growth_5_cycles_bytes | 2134016.000000 | 524288.000000 |

### 超标取证与原因边界

转盘首轮原始timeline中配对292段Rasterizer::DoDraw，平均16.541ms；SurfaceFrame::Encode平均14.476ms，RenderPassGLES::EncodeCommandsInReactor平均13.473ms，UI PAINT平均0.362ms。见 [timeline_evidence.json](../tool/bench/results/bench_20261110_180650/timeline_evidence.json)。启动日志先出现Vulkan、后出现OpenGLES，时间线证据明确包含GLES编码路径。耗时主要集中于渲染提交/编码，而不是UI paint；这是该轮证据，不能由它直接推断所有轮的唯一根因。

源码 `lib/src/wheel/render/wheel_painter.dart` 在旋转段对缓存Picture做CTM旋转并回放，raster缓存则走drawImageRect；Picture缓存避免重复录制，仍需要后端执行绘制。建议主会话后续专门核对该设备GLES路径、图文旋转的编码成本与缓存策略；本轮不改产品lib，也不增加对照运行。其它玩法UI平均耗时普遍越过首版目标，应结合对应timeline继续定位，不能因为手机型号而放宽目标。

独立RSS三轮的“首次返回空白页增长/后续四次净增长”分别为3.984/0.891、4.191/0.102、3.715/1.168MiB；总增长中位4.875MiB，仍完整比较0.5MiB上限。增长集中于首次解码/挂载，可能包含图片缓存和分配器驻留；仅RSS不能证实泄漏，且现有Widget没有公开解码字节诊断入口。本轮不扣除热身增长，不强制GC，不豁免该超标。

## C：Skia / Impeller 阴影对照（T2.3）

`run_device.ps1 -Task Shadow -ReuseBinaries`：两后端**各恰好3次，6/6有效，无补轮**。显式 `--no-enable-impeller` / `--enable-impeller`，驱动读取引擎 `ext.ui.window.impellerEnabled`：Skia三轮false、Impeller三轮true。每后端三张PNG的SHA256完全一致，三组定量结果也一致。原始PNG、metadata、verbose、logcat、耗时见 [阴影采集目录](../tool/bench/results/shadow_20261110_193626/)。

1080×2400，DPR2.75。逐像素差异定义为任一RGBA通道绝对差>32；MAE为RGBA均绝对误差，外扩边界取相对白底亮度衰减≥2/255。下表按阴影像素统计，三组均相同。

| 面板 | 差异阴影像素占比 | 阴影MAE | Skia左右半径(px) | Impeller左右半径(px) | 最大半径差 | 扫描线峰值亮度差(/255) |
| --- | --- | --- | --- | --- | --- | --- |
| device_1 | 1.1448% | 1.2219 | 19/19 | 20/19 | 1 | 23.7736 |
| logical_1 | 0.3847% | 0.7687 | 51/51 | 53/52 | 2 | 20.7736 |
| device_1_5 | 0.7758% | 0.9347 | 28/28 | 29/28 | 1 | 22.7736 |
| logical_1_5 | 0.2561% | 0.7010 | 77/77 | 79/78 | 2 | 20.7736 |
| grid_3x3 | 0.5637% | 2.5307 | — | — | — | — |
| slot | 不可观察 | — | — | — | — | — |

结论：两后端不是逐像素一致；独立格子外扩半径差1–2个物理像素，扫描线峰值差20.8–23.8/255。CTM1.5时两种空间的半径都约按1.5增长，缩放趋势一致。峰值含填充边缘抗锯齿过渡，不能把亮度差直接等同sigma错误；建议先拟合远离填充边缘的高斯剖面、核对颜色/抗锯齿，再决定是否补偿sigma，不能仅凭本次数据在 `core/foundation/shadow.dart` 添加后端魔数。

老虎机阴影配置确实传入，但格子填满滚轮clipRect，阴影外扩被裁剪；该面板仅有填充差异，**无法完成老虎机阴影一致性验收**。见 `slot_painter.dart` 的clipRect和_recordCell。比较器记录shadow_observable=false，未把零可见阴影当通过。本轮不追加截图；建议主会话后续调整夹具圆角/间距/视口，让阴影可见再补该项。九宫格独立样本与真实3×3样本已完成量化。

产物：[Skia](device/shadow_skia.png)、[Impeller](device/shadow_impeller.png)、[差异图（RGB×4）](device/shadow_diff.png)、[RGBA扫描线曲线](device/shadow_profiles.svg)、[三组汇总](device/shadow_summary.json)。每组CSV/JSON/SVG位于docs/device/shadow_comparison/round1–3。

## 本机门禁与证据

- 主包最终flutter analyze --no-pub：No issues found! (51.9s)。bench：No issues found! (21.9s)。
- dart format --output=none --set-exit-if-changed lib test tool：330 files (0 changed)。
- 修改相关单测：27/27，通过（初次25秒、回填后70秒）；沿用上一尝试992/992全包证据，未再次重复全包测试。
- dart run tool/check_imports.dart：PASS: 144 lib files; IMP-R1…R12。
- dart run tool/check_acceptance.dart：PASS: 1383 references resolve; 1017 registered tests all mapped。
- 亲自运行覆盖率门禁，读取上一尝试有效coverage/DEV.lcov：TOTAL 6677/6677 (100.00%)，PASS；产品lib未修改，无新增豁免。
- 性能比较exit=1，波动和超预算如上；不是代码门禁全通过就宣称性能达标。
- 真实仓库拷回后验证另行追加，结果不冒用副本输出。

## 文档矛盾、偏离和需主会话同步的事项

1. ARCHITECTURE §8.6、TEST_STRATEGY §7.1/7.3/7.4、IMPLEMENTATION_GUIDE T4.6仍保留旧RSS次数/增长预算/波动整组重跑口径；按最高优先级改为kRssCycles=5、0.5MiB、只补无效轮且累计≤5。上述设计文档未改，建议主会话统一同步新数据及失败结论。
2. 同卡测试名旧次数与最高优先级冲突：仅RSS基准名改为 `bench > rss after 5 push pop cycles`，矩阵旧引用同步；example的20次路由集成测试原名和证据均保留，不重跑。
3. 半成品拉霸机伪装slot report_key并要求替换比较集合；现独立注册lever_steady，沿用slot首版上限，避免混合六轮。
4. core无layout/record调用打点；冷首帧保守测完整FrameTiming.buildDuration≤4ms，而非用缺打点的零耗时。建议补统一可观测接口后再对齐指标。
5. 图片resolver私有，解码字节未采；不改产品lib，不伪造零数据。
6. Android resize夹具曾把280dp当成280物理像素，已按DPR换算，与Windows逻辑视口一致；测试名未改，33/33原结果已核验。
7. 阴影对照不是像素一致；老虎机样本不可观察，仍有验收缺口。保留证据，不擅自修核心sigma或修改设计。
8. 按D6状态如实登记，D8继续其余工作；D1/D2/D3/D4/D5/D7既有产品实现和门禁语义不变。本轮没有核心补丁、core_patch.diff、依赖变更、git add/commit/push。

## 拷回与清理

USB常亮已恢复false，实读stay_on_while_plugged_in=0。只清理命令行确认属于本副本的Gradle/采集进程；未关闭其它会话的Java、Dart、Node或ADB服务。拷回排除build、.dart_tool、Android缓存、local.properties、锁文件、APK及生成包装器；完整文件列表、冲突核对和真实仓库验证将在完成后补记。



## 按任务卡的交付文件清单

- T4.5：example/integration_test/resize_test.dart（Android逻辑视口按DPR换算）；docs/device/android_integration_report.json、android_integration_runs.log（沿用且核验的33/33原证据）。
- T4.6：tool/bench/metrics.dart、compare.dart、budgets.json、budgets.status.json、README.md、run_device.ps1、summarize_device.py；integration_test/bench_support.dart、memory_bench_test.dart、lever_bench_test.dart；lib/main.dart；test_driver/perf_driver.dart；test/tool/bench_metrics_test.dart、bench_compare_test.dart。相关单测27个，开发前/回填后/真实仓库各执行一次，三次均27/27。
- T2.3：tool/bench/lib/shadow_scene.dart、integration_test/shadow_capture_test.dart、test_driver/shadow_driver.dart、compare_shadow.py；docs/device/shadow_*.png、shadow_summary.json、shadow_profiles.svg、shadow_comparison/round1–3（CSV/JSON/SVG/差异图）。截图测试一个，每后端三次，共6/6。
- 共用：docs/DEVICE_REPORT.md；test/ACCEPTANCE.md追加DEV-101–126共26行，仅同步一处旧RSS测试名引用；没有覆盖其它验收行。tool/bench/results/bench_20261110_180650、shadow_20261110_193626为本次证据；attempt2_rss20为不计入的旧数据；validation为门禁和冻结源码证据。

源码文件共19项；首次拷回408个源码/报告/证据文件，随后仅补交付验证记录。完整逐文件路径和SHA256见 [copy_manifest.json](../tool/bench/results/validation/attempt3/copy_manifest.json)。没有复制build、.dart_tool、Android缓存、local.properties、pubspec.lock、临时APK或生成包装器；未改pubspec、产品lib或其它包。

## 真实仓库拷回后验证（2026-11-10 19:57）

| 命令 | 真实结果 |
| --- | --- |
| flutter analyze --no-pub（主包） | No issues found! (21.0s) |
| dart format --output=none --set-exit-if-changed tool/bench test/tool/bench_metrics_test.dart test/tool/bench_compare_test.dart example/integration_test/resize_test.dart | Formatted 20 files (0 changed)，exit0 |
| flutter test test/tool/bench_metrics_test.dart test/tool/bench_compare_test.dart --no-pub --concurrency=1 | 27/27通过，38秒，exit0 |
| dart run tool/check_imports.dart | PASS: 144 lib files; IMP-R1…R12 |
| dart run tool/check_acceptance.dart | PASS: 1442 references resolve; 1050 registered tests all mapped |
| dart run tool/coverage.dart --min=100 --lcov=tool/bench/results/validation/DEV.lcov | TOTAL: 6677/6677 (100.00%)；PASS；沿用有效采集，未重跑全包 |
| dart run tool/bench/compare.dart --input=tool/bench/results/bench_20261110_180650/comparison --budgets=tool/bench/results/bench_20261110_180650/design_budgets.json --rss-all-scenes | exit1；三次极差>30%：average_frame_rasterizer_time_millis |

144个产品Dart文件逐个SHA256与冻结副本完全相同，见 [frozen_source.json](../tool/bench/results/validation/attempt3/frozen_source.json)；真机数据对应本次拷回时产品源码。真实仓库并行增加的其它测试没有被覆盖。主包/bench依赖文件未由本批修改。

当前稳态采样均上报60Hz，使用60Hz的0.5%掉帧目标；室温没有传感器读数，未伪造环境温度，仅记录设备电池温度。所有真机轮已结束，不再追加运行。

最终按命令行检查，本批Gradle/Dart采集驱动/flutter_tester残留为0；自有低内存时闲置守护进程清理记录已保存，未杀其它会话。基准应用已force-stop；svc power stayon false后实读stay_on_while_plugged_in=0。

待主会话处理：31项原目标超标、39项三轮不稳定（有交集）；老虎机阴影可观察性；独立layout/record打点与解码字节接口；设计文档的次数/预算/测试名/实测表同步。D6按实际标记，D8保守继续；D1/D2/D3/D4/D5/D7既有实现均未改。没有核心补丁或core_patch.diff。
