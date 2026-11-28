# 复合路径覆盖最小复现

`repro.dart` 用 `dart:ui` 绘制两条合成轮廓。每例都比较两次 `drawPath` 与一次复合 `drawPath` 的预乘 RGBA。窗口只负责初始化 Flutter。

在 scratchpad 里复用 `bench_app` 的安静 Windows runner，将 `repro.dart` 放到副本的 `lib/`，用 `flutter build windows --profile -t lib/repro.dart` 构建，再用 `win_quiet_launch.py` 启动 profile EXE。结果写入启动器指定的 `.report.txt`。复现只用合成坐标。

| 用例 | 几何 | Windows OpenGLESSDF 预期 |
| --- | --- | --- |
| rectangles | 两个高 0.7 像素的矩形，水平间距 6 像素 | 72 像素变化，最大通道差 42 |
| collinearCurves | 用共线二次曲线表示同一条矩形边 | 最大通道差 0 |
| clipEdgeStroke | 0.32 像素描边完全位于裁剪左侧，另一笔在裁剪内 | 3 像素变化，最大通道差 41 |

用 Windows profile 引擎开关 `enable-impeller=false` 可对照 Skia GPU。Flutter 3.50.1 的 Windows runner 支持为子进程指定 engine switches。该版本通过开关是否存在读取 SDF 设置，`impeller-use-sdfs=false` 仍会启用 SDF。本次对照把 Impeller 启用与 framebuffer 原点选项放在参数终止符 `--` 之前，把 `--impeller-use-sdfs=false` 放在其后，再用启动日志确认后端为 `OpenGLES`。矩形差归零，描边差保留。

## Skia CPU

在仓库根运行 `flutter test --no-pub benchmark/windows_merge_diff_repro/skia_test.dart`。Flutter 3.50.1 的默认测试启动器使用软件渲染和 Skia 确定性渲染参数。复现只依赖 `dart:ui` 的路径绘制与预乘 RGBA 回读。

| 用例 | 隔离变量 | 预期最大通道差 |
| --- | --- | ---: |
| `convexSeparateRows` | 两个三角形纵向错开 54 像素 | >1 |
| `concaveSameRows` | 两个凹形水平错开 70 像素，扫描行重叠 | >1 |
| `concaveSeparateRows` | 水平和像素相位不变，另纵移 54 整像素 | 0 |

整图比较用相同的 `rasterizeSvgPicture` 和 `BoxFit.contain`，在 310×450、872×1266 各回放一次。两档通过明确的 DLL 路径初始化，比较 `rawRgba`。五张正式样本从外部语料读取。

## web-481 组件采集

Windows 每个 C1 或新版进程完成正式计时后，从 310×450 的 `RepaintBoundary` 连续采集 10 次。其中同挂载稳定态 3 次，自动缓存重挂载后最早可采和稳定态各 1 次，禁用位图缓存时在离屏回放前后各 1 次，半像素平移、复位和三倍缩放各 1 次。记录每次 `(160,267)` 的预乘 RGBA、相位、帧号、缓存就绪、纹理大小和请求时间。标准图生成一张 310×184 纹理，三倍缩放仍只生成一张 930×551 纹理。实际分块的对照需要超过整图缓存的边长或字节门槛。

[本轮报告](../windows_merge_diff.md) · [像素与计时原始数据](../raster_cache_auto_windows_diff_raw.json)

## 310×184 缓存纹理原件

`cache_repro.dart` 比较组件大小的矢量快照、`Picture.toImageSync` 生成的整图纹理和最近邻贴回。报告中的 `direct`、`texel`、`pasted` 是三个独立的预乘 RGBA8 读数。Windows 探测点 `(160,267)` 对应 `(160,134)`。Flutter widget 只提供启动帧，绘制、离屏快照和贴图由 `dart:ui` 完成。

| 入口 | 输入 | Windows 观察 |
| --- | --- | --- |
| `cache_repro.dart` | 两组提取的细描边，C1 独立、B 与 H 分组 | 两组离探测点至少 39.54 px，三个读数均透明；参数扫查覆盖目标高度、原点、clip、网格比例、线宽及 2/5/23 个轮廓 |
| `cache_edge_probe.dart` | 三层圆角边、极细描边和纯色底；含合成坐标对照 | 完整局部用例的三个读数均为 `[185,185,182,255]`；删黑填充变为 `[246,246,244,255]`，删内层白变为 `[121,121,119,255]` |
| `archive_replay.dart` | 本机另行提供的 Rust 路径输出 | 完整 B 和 C1 的部分新纹理均复现 `[122,122,120,255]`，直绘为 `[184,184,182,255]` |
| `msaa_repro.dart` | 同一完整画稿或局部边缘，缓存强制 RGBA32F | Impeller 使用单样本目标，原纹素与贴回恒为 `[246,246,246,255]` |
| `context_repro.dart` | 同一完整 B 画稿，裁减末尾前的绘制操作 | 九档每档 24 次无 62 级跳变，包含保留前 5,300 条和末尾 14 条的用例 |
| `msaa_stage_probe.dart` | 同一完整 C1 画稿，七个对照档（original、legacy、clean、poison、readback、winding、float32），每档 150 张，各档按批交错 | 低值 `[122,122,120,255]`：original 21/180、legacy 34/180、clean 10/180、readback 16/180、poison 1/180、winding 0/180、float32 0/180（恒 `[246,246,246,255]`）；统计见 `msaa_stage_run.py`，结论见报告第 7 步 |

### 运行

在仓库外准备 `bench_app` 副本，复制 `benchmark/bench_app/windows/`，排除 `windows/flutter/ephemeral/`；用同一目录的 Android 宿主可跑 Vulkan。复制本目录 `cache*.dart`（排除 `*_test.dart`）和所需入口到副本的 `lib/`，运行完整画稿各入口时也复制 `archive_replay.dart`。副本的 `pubspec.yaml` 包名用 `bench_app`，依赖只需 `flutter: {sdk: flutter}`，Dart 约束 `^3.13.0`。Windows 实测 SDK 为 3.50.1，profile 引擎 `4d35714800`。

```powershell
flutter build windows --profile -t lib/cache_repro.dart
python -I <repo>/benchmark/bench_app/tool/win_quiet_launch.py --exe build/windows/x64/runner/Profile/bench_app.exe --log cache-probe.log --runs 3
```

用 `-t lib/cache_edge_probe.dart` 可运行边缘对照。启动时复用原安静 runner，日志应显示 `OpenGLESSDF`。窗口为 640×360，位于右下角底层，使用 `SW_SHOWNOACTIVATE`、`WS_EX_NOACTIVATE` 和 `WS_EX_TOOLWINDOW`。

完整回放需要在本机以归档 DLL 对画稿调用 `parseSvg`。Windows 将 `XVG_ARCHIVE` 指到保存 `ActualB-web-481.jsonl`、`C1-web-481.jsonl`、`clips-481.json` 的本机目录。Android 在临时工程把 `Final-web-481.jsonl`、`C1-web-481.jsonl`、`clips-481.json` 放进 `assets/` 并在临时 `pubspec.yaml` 声明，构建 ARM64 profile APK。使用独立包名安装，并在结束后卸载该包。实测 Android 的 `Directory.systemTemp` 对应该应用的 `code_cache/`，可用 `adb exec-out run-as <probe.package> cat code_cache/xvg-cache-repro.json` 读取报告。任何完整画稿和 APK 都保存在仓库外。

- JSONL 首行有 `commands`，每条记录为 `[kind,index,opacity]`。样本只用 `0` 绘制、`4` 压入 clip、`5` 退出 clip。后续路径行按 `index` 索引，列为 `[verbs,points,fillArgbOrNull,evenOdd,strokeArgbOrNull,strokeWidth,strokeFlagsOrNull,miterLimitOrNull]`，本机 dump 可附带空的扩展字段。
- `clips-481.json` 的 `clips` 为 `[verbs,points,evenOdd]` 数组。历史 B 和 C1 的 paths 分别为 5,954 和 12,511。在最终 native DLL 上启用 `allowPathMerge` 后，Final 为 5,942 条。

用 `-t lib/msaa_stage_probe.dart` 构建后，运行 `python -I msaa_stage_run.py --exe <bench_app.exe> --archive <含 C1-web-481.jsonl 与 clips-481.json 的目录> --out <目录> --round N`，每次只启动一个进程，已有 `audit-N.json` 的轮次拒绝重跑。它输出各档低值计数和成对 Fisher 双侧 p 值，合并 `--out` 里所有有数据的轮次。

### 上游 issue 草稿

**Title** · Impeller OpenGLES on Windows can produce two different texels from the same offscreen picture and transform

**Environment** · Flutter 3.50.1 profile, engine `4d35714800`, Windows OpenGLESSDF. At DPR 1, draw a `Picture` into 310×450, then record an integer-equivalent sample origin into a fresh 310×184 target. Read the original `Image` and the composed destination separately.

**Expected** · Repeated fresh textures of the same display list and transform agree. At matched sample origins, the point at component `(160,267)` and texture `(160,134)` agree with the vector replay.

**Observed** · The full display list produced `[184,184,182,255]` or `[122,122,120,255]` in the original texture. The pasted pixel matched the original texel, and the full-size vector replay gave the high value. We reproduced the same result after splitting the compound paths and with synchronous and asynchronous snapshots. Removing the black fill suppressed the jump in this run. Removing the inner white fill kept the 62-level jump. The synthetic rounded-edge control shows comparable coverage levels and stays stable at matched sample origins.

**MSAA stage (full display list, 180 fresh 310×184 textures per arm over two processes)** · The low value `[122,122,120,255]` appears in 21/180 plain snapshots, and only in the multisampled path. Forcing a single-sample `rgbaFloat32` target gives 0/180 (constant `[246,246,246,255]`). Replacing the black fill with a repeated same-direction contour, which keeps the non-zero result but changes the fill pipeline, gives 0/180 (Fisher two-sided p=5e-07). Inserting synchronous readbacks before and after each snapshot does not remove it (16/180, p=0.49 against 21/180), so a readback or resolve timing race is unlikely. Rendering a same-size image that writes the whole stencil right before the snapshot lowers it to 1/180 (p=6e-06), opposite to what stale-stencil residue would predict; a blank same-size image gives 10/180. The jump appears as independent per-texture events with no sticky streaks. Whether the cause is per-sample coverage, depth or stencil, or the RGBA8 versus RGBA32F attachment precision is not separable from outside the driver. A RenderDoc or ANGLE call capture of the 4× attachment before resolve is needed, and an engine option for an explicit single-sample RGBA8 target would separate sample count from precision.

**Reproducer status** · The asset-free controls run with the files in this directory. The intermittent jump still requires the local full display list in the available reproduction. Further reduction is needed before supplying a public positive reproducer. No original SVG, full path dump, or rendered artwork is included here.

**Vulkan control** · Run `cache_edge_probe.dart` on the Android profile backend and compare `synthetic/base` with `synthetic/aligned_phase`. At `(451,752)` the original component capture phase gives `[171,171,169,255]` from the vector and `[231,231,224,255]` from the texture. When both textures use the vector capture grid, the synthetic case agrees across the entire output. This outcome reproduces with every fresh texture.
