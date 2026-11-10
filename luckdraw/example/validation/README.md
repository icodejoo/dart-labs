# B15 Windows 实测记录（2026-11-10）

最终 [windows_integration_report.json](windows_integration_report.json)：
Windows、11 文件、每文件完整三轮，33/33 通过，100%，累计 913606ms。
这是补齐副本基线后一次完整的 run_integration 调用结果，没有拼接不同调用的通过记录。
耗时包含逐轮构建和真实桌面执行，不是纯动画耗时。

| 文件 | 通过 | 累计毫秒 |
| --- | --- | --- |
| capsule_flow_test.dart | 3/3 | 88140 |
| grid_flow_test.dart | 3/3 | 66715 |
| lever_flow_test.dart | 3/3 | 80794 |
| lifecycle_test.dart | 3/3 | 110984 |
| lots_flow_test.dart | 3/3 | 81409 |
| lotto_flow_test.dart | 3/3 | 85962 |
| number_wheel_flow_test.dart | 3/3 | 63084 |
| resize_test.dart | 3/3 | 84112 |
| route_test.dart | 3/3 | 115403 |
| slot_flow_test.dart | 3/3 | 66552 |
| wheel_flow_test.dart | 3/3 | 70451 |

正式命令，在指向同一副本的临时短入口 ld15 下串行执行：

```powershell
. C:\Users\jelon\.claude\msvc-env.ps1
dart run tool/run_integration.dart --device=windows --repeat=3
```

每个 flutter test 子进程均设五分钟超时；三十三次串行执行的总时间超过五分钟。
Windows 窗口使用 SW_SHOWNOACTIVATE、WS_EX_NOACTIVATE，测试模式跳过 SetFocus，
没有调用 SetForegroundWindow。resize 三轮均实际调整 HWND 和转盘尺寸，并断言
foreground=false。lifecycle 三轮均在 hidden 期间真实等待十秒，不 pump。
每轮 route 实际在运动中 push/pop 二十次，离开后没有活动 Ticker。

历史失败与修正记录保留，不作为最终通过报告：

- B15-integration-first.json：副本补齐前的初轮 27/33。拉霸机测试的
  SemanticsHandle 在测试体返回前未释放；生命周期从 resumed 直接跳 hidden
  触发 Flutter 状态迁移断言。各三次失败均如实保留。
- B15-lever-retry.json：取得拉杆坐标后立即释放句柄，三轮通过。
- B15-lifecycle-retry.json：往返增加 inactive，三轮通过。

之后全包验证发现副本落后于真实仓库已有 F1 修复，只在副本同步七个核心文件和
一条已在真实仓库更新的 T4.4 叠加层断言；[baseline_refresh.json](baseline_refresh.json)
记录同步前及测试版本的哈希。这八个文件没有拷回。补丁保存在副本的 ../core_patch.diff；
它描述已存在于真实仓库的基线补齐，无需重新应用。后续并行 F2 修改未并入本批固定副本。

副本单测分组实测：core/testing/tool 527 passed；wheel/grid/slot 203 passed；
其余玩法/compat/parity 182 passed、4 failed、7 skipped。四条失败均为既有老虎机
parity s01–s04 的首减速帧旧断言：D7 保留 strict/frame 零位移哨兵，断言却要求
stopScroll；该路径不属于本批，未修改测试或放宽断言。七条 skip 也为既有对照留项。
本批新增十三条工具单测全部通过，十一条集成测试名字逐字采用 T4.5。

覆盖率为 6544/6544（100.00%），由三个独立 B15 LCOV 合并后通过门禁，
没有新增豁免；沿用 COV-01 两行。check_imports：144 lib files，IMP-R1…R12 PASS；
check_acceptance：1264 references / 937 registered tests PASS。主包与 example
独立分析均 No issues found；格式检查为 311 个主包文件和 29 个 example Dart 文件，
全部 0 changed。交付文本统一 LF，完整文件清单见 [files.txt](files.txt)。

本机初始可用内存约 11GB；真实 Windows 执行期间监测始终高于 4GB。
长副本路径初次构建和加载 MSVC 后重试均报 MSB6003 / DirectoryNotFoundException
（MSBuild .tlog 长路径）；短入口解决，没有修改 SDK。没有单独执行 flutter build。
adb devices 无设备，安卓未运行，未执行 APK 或 Gradle 构建；保留 Flutter 3.47
生成的 Android 配置，最低 SDK 的平台构建兼容性留给 CI/有设备时验证。
