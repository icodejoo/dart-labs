# luckdraw 示例与集成测试

入口菜单包含转盘、九宫格、老虎机、拉霸机、扭蛋机、数字转盘、抽签、大乐透，
以及 compat 迁移、动画 Widget 奖品叠加层和 README 片段页。
点击开始区域或「开始」，再点击「服务端返回」模拟异步业务结果。
所有控制器随页面释放；示例只 import 本包公共入口。

直接依赖为本地 luckdraw、Flutter SDK 和 SDK 自带的测试包，没有新增 pub.dev 依赖。
「官方示例对照」页把官方站（100px.net）的基础示例（大转盘 19、九宫格 25、老虎机 17）和完整示例（15）
1:1 复刻，每项左侧是官方截图、右侧是 luckdraw 实时渲染；配置在 lib/official/，
素材在 assets/（仅供示例对照，勿商用，见包根 NOTICE），详见 docs/OFFICIAL_PARITY_REPORT.md。
README 片段保存在 lib/snippets/，由 lib/readme_snippets.dart 组合展示；
与包 README 的 Dart 代码一致（转盘、九宫格、老虎机、拉霸机、扭蛋机、数字转盘、抽签、大乐透、compat、扩展、测试），只补充中文注释和宿主页面。

在 example 内执行：

```powershell
flutter pub get
flutter analyze --no-pub
flutter run -d windows
```

pub get 后立即核对 analysis_options.yaml；此工程显式配置 lint 规则，
不依赖主包的 flutter_lints。资源、平台配置都留在 example/。
Android 使用 Flutter 3.47 模板生成的 Gradle 配置；目前没有安卓设备，
所以没有执行 APK/Gradle 构建。最低 SDK 版本的设备构建，等有 CI 或设备时再验证。

在包根运行集成测试：

```powershell
dart run tool/run_integration.dart --device=windows --repeat=3
dart run tool/run_integration.dart --device=windows --repeat=3 --file=wheel_flow_test.dart
# 接入实体安卓设备并确认 adb devices 后，用 serial 替换设备标识：
# dart run tool/run_integration.dart --device=<serial> --repeat=3
```

脚本逐文件串行运行，每个文件三轮；任一失败返回非零。
build/integration_report.json 在每轮完成后落盘，保存退出码、耗时与通过率。
每轮超时五分钟只结束本轮启动的进程树。

Windows 脚本设置 LUCKDRAW_TEST_WINDOW=1。runner 使用 480×720 小窗口、
SW_SHOWNOACTIVATE、WS_EX_NOACTIVATE，测试模式不转移输入焦点。
仅测试模式启用 luckdraw/test_window 通道，resize 测试调整真实 HWND，
并断言窗口没有成为前台窗口。正常运行不会暴露该通道。

本机上，过长的工作副本路径会触发 MSBuild 的 MSB6003/tlog 路径错误。用一个指向同一副本的
临时短路径运行就能解决，不用改 SDK。若 MSVC 环境缺失，先在当前
PowerShell dot-source C:\Users\jelon\.claude\msvc-env.ps1 再调用脚本。

生命周期测试使用 resumed → inactive → hidden，真实等待十秒且不 pump，
再 hidden → inactive → resumed 后恢复 pump；中间 inactive 是 Flutter
AppLifecycleListener 状态机的要求，Windows 与安卓共用。

源码目录：

- lib/main.dart、lib/demo_shell.dart、lib/readme_snippets.dart。
- lib/pages/：wheel_page.dart、grid_page.dart、slot_page.dart、lever_page.dart、
  capsule_page.dart、number_wheel_page.dart、lots_page.dart、lotto_page.dart、
  compat_page.dart、overlay_page.dart。
- lib/snippets/：readme_wheel.dart、readme_grid.dart、readme_slot.dart、readme_compat.dart。
- integration_test/：八个 *_flow_test.dart，加 lifecycle_test.dart、resize_test.dart、
  route_test.dart，以及 support/flows.dart。
- windows/ 和 android/：从仓库外临时工程生成的平台壳。
