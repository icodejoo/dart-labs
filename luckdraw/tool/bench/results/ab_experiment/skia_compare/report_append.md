
## Skia 对照（AB2）

**结论：与后端无关。** Skia 也出现 Raster 平均>10ms的高档轮次，按预定规则判定“与后端无关”；本样本排除了“高档只发生在 Impeller GLES”的解释，但不能证明两后端耗时分布相同。高档的剩余原因无法由本次数据解释，不能归因于 luckdraw 或设备驱动缺陷。

### 固定项与样本

- vivo V2417 / `10AE9K17UE0011S` / Android 16；同一 profile APK，共6次启动，S/I各3次有效，按S1、I1、S2、I2、S3、I3交错；未按快慢补轮。
- 复用已构建的 `tool/bench/results/perf_after/perf.apk`，29738554 bytes；SHA-256 `ce352b375772e2a2d01d78faced91a7232bb014e1aa87f306487895645612fbe`。
- `--route=/wheel_default`选择默认auto，报告场景为`wheel_steady`；12奖品、每项128×128图片和两行文字，进入cruising后采样5秒。同一APK的参照窗口和5次RSS循环照常执行，未改设备代码。
- 旧AB使用`perf_ablation/perf.apk`及`wheel_picture`，APK/缓存配置均不同，故不复用其Impeller三轮，补测I1–I3。
- 每轮force-stop后静置完整60秒，启动前核对`isKeyguardShowing=false`、空闲内存≥2GiB和设置0/1/2；未修改亮度、USB常亮或其它手机设置。
- 本批运行中没有额外adb轮询；引擎状态由host driver一次性读取VM service。主会话看护仍在运行，按用户告知为每120秒仅查锁屏的轻量版，无法停止；这属于未独立控制的背景条件。
- 每轮驱动退出后立即按SurfaceFlinger前120行→battery顺序各读一次；随后读取window/display/logcat。时间戳及退出码见各轮`snapshot_commands.json`。

### 原始值

| 轮次 | Raster平均 ms | p90 ms | p99 ms | 掉帧率 % | UI平均 ms | 高档>10ms |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | 4.727 | 6.144 | 7.216 | 0.000 | 0.976 | 否 |
| I1 | 5.247 | 6.598 | 9.651 | 0.000 | 1.151 | 否 |
| S2 | 4.289 | 5.843 | 7.449 | 0.000 | 1.027 | 否 |
| I2 | 5.138 | 6.565 | 9.020 | 0.000 | 1.099 | 否 |
| S3 | 16.628 | 17.535 | 21.879 | 34.000 | 1.016 | 是 |
| I3 | 5.134 | 6.195 | 10.241 | 0.000 | 0.977 | 否 |

掉帧按设备实际帧周期，UI或Raster任一超时计一帧、去重；上述值来自FrameTiming样本，原始精度见JSON，不用timeline片段重估。

### 三轮中位数与极差

| 后端 | 指标 | 三轮原值 | 中位数 | 极差 max−min |
| --- | --- | --- | --- | --- |
| S | Raster平均 ms | 4.727 / 4.289 / 16.628 | 4.727 | 12.339 |
| S | Raster p90 ms | 6.144 / 5.843 / 17.535 | 6.144 | 11.692 |
| S | Raster p99 ms | 7.216 / 7.449 / 21.879 | 7.449 | 14.663 |
| S | 掉帧率 % | 0.000 / 0.000 / 34.000 | 0.000 | 34.000 |
| S | UI平均 ms | 0.976 / 1.027 / 1.016 | 1.016 | 0.050 |
| I | Raster平均 ms | 5.247 / 5.138 / 5.134 | 5.138 | 0.112 |
| I | Raster p90 ms | 6.598 / 6.565 / 6.195 | 6.565 | 0.403 |
| I | Raster p99 ms | 9.651 / 9.020 / 10.241 | 9.651 | 1.221 |
| I | 掉帧率 % | 0.000 / 0.000 / 0.000 | 0.000 | 0.000 |
| I | UI平均 ms | 1.151 / 1.099 / 0.977 | 1.099 | 0.174 |

| 后端 | 高档 Raster平均>10ms | ≤6ms轮次 |
| --- | --- | --- |
| S | 1/3 | 2/3 |
| I | 0/3 | 3/3 |

### 后端及事后设备取证

S显式`--no-enable-impeller`，I显式`--enable-impeller`。每轮`backend.json`保存`ext.ui.window.impellerEnabled`原始响应，driver断言请求后端与实际布尔值一致；逐轮启动命令、verbose与logcat均保留。

| 轮次 | 引擎enabled | 启动/引擎证据 | SF即时刷新率 | 电池温度 前→后 °C | SF开始距驱动退出 s | 空闲主机 GiB | 静置 s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | false | 启动enable-impeller=false；GLES事件0个 | 60.00 Hz | 28.3→28.5 | 0.000 | 8.058 | 60.002 |
| I1 | true | OpenGLES日志；GLES事件603个 | 60.00 Hz | 28.6→28.7 | 0.000 | 9.443 | 60.002 |
| S2 | false | 启动enable-impeller=false；GLES事件0个 | 60.00 Hz | 28.6→28.5 | 0.000 | 9.618 | 60.002 |
| I2 | true | OpenGLES日志；GLES事件603个 | 60.00 Hz | 28.6→28.6 | 0.000 | 6.405 | 60.002 |
| S3 | false | 启动enable-impeller=false；GLES事件0个 | 60.00 Hz | 28.4→28.6 | 0.000 | 6.756 | 60.002 |
| I3 | true | OpenGLES日志；GLES事件604个 | 60.00 Hz | 28.5→28.7 | 0.000 | 6.625 | 60.002 |

SF是驱动退出后的瞬时快照，应用已由flutter drive清理，不能用事后层列表推断采样窗口内应用的CLIENT/DEVICE合成方式。前120行未暴露的字段保持“未暴露”，不把引擎OpenGLES日志等同于HWC合成类型。未在采样期间查询刷新率或温度。

I启动日志可先出现Vulkan初始化，随后记录OpenGLES；以最后的OpenGLES日志、引擎enabled=true及采样timeline的GLES事件交叉确认。S以启动参数false和引擎enabled=false确认Skia，timeline无GLES事件仅作辅助。主机UTC与设备本地时钟未校准，不直接用两者绝对时间相减；静置和快照延迟均由主机同一时钟计算，logcat起点使用设备date。

### 限制、保守处理与文档建议

1. AB2明确禁止重负载验证，因此未运行flutter analyze、flutter test、pub get或build；不将既有覆盖率当成本批新采集。保留原集成测试名`perf > selected device scenario`，六轮真实通过数按驱动日志核验。
2. ARCHITECTURE §8.1保留旧picture默认，当前PERF实现/报告已将默认设为auto。遵循本批指定auto，使用已构建perf_after APK；未改设计或lib。建议统一文档默认值，并将路由、APK哈希、缓存模式列为旧数据可复用的前提。
3. 原AB结论中的“设备GLES路径固有双峰”超出亮度实验可证明范围；按仅追加要求保留历史文字，本节只按实际后端证据和预定判定规则下结论。
4. 每后端仅三次；不能据此推断高档发生概率或解释底层原因。建议真机后端实验模板强制记录引擎状态，并明确事后SF快照的解释边界。

本次结果不足以推荐切换Skia作为该双峰的已验证规避；没有修改Manifest或包代码。

最终只读实测（`2026-11-10T14:15:39.942601+00:00`）：`mode=0、brightness=1、stay_on=2`；见`final_settings_confirmation.json`。本批没有写入手机设置。

所有原值、后端响应、命令与快照：[skia_compare](../tool/bench/results/ab_experiment/skia_compare/)；汇总见`analysis.json`。

### AB2实际门禁输出

- analyze / flutter test / pub get / build：按AB2禁令未运行；真实profile集成测试为同名用例六轮，6/6有效通过。
- 使用Dart直接执行门禁，避免`dart run`潜在隐式pub；覆盖率仅复核既有`coverage/PERF.lcov`，并非AB2新采集。
- `format_apply`：exit=0； / Formatted 345 files (0 changed) in 0.96 seconds.
- `format_gate`：exit=0； / Formatted 345 files (0 changed) in 0.93 seconds.
- `imports_gate`：exit=0； / PASS: 145 lib files; IMP-R1…R12 / 依赖图与静态规则通过
- `acceptance_gate`：exit=0； / PASS: 1468 references resolve; 1069 registered tests all mapped. / 全部测试引用有效且无遗漏
- `coverage_gate_historical`：exit=0；TOTAL: 6792/6792 (100.00%) / PASS: coverage >= 100.0%
- 副本源码/配置/APK共150份哈希全部未变；真实仓库lib 145份哈希未变。副本与真实源码文本一致（3份文件仅换行字节不同），不拷回源码。

最终git log（本批未add/commit/push）：

```text
443589a3 merge: 合并 mova（链接与分支口径指向 mova 分支）
f0b64ae1 docs(mova): 链接与分支口径从 main 改为 mova 分支
```
