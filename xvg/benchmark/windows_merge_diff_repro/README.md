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
