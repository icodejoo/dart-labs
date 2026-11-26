---
title: 233 KB 静态插画的真机光栅归因
status: active
updated: 2026-11-26
summary: 三轮真机对照拆出 Impeller 裁剪与透明图层叠加的成本，并比较裁剪外提和两种位图缓存。
---

# 233 KB 静态插画的真机光栅归因

一张 233KB 真实活动页插画（未入库）在 spinner 持续驱动下，每帧都由 Impeller 重放同一张向量 `Picture`。xvg 把两层共享裁剪逐路径展开，使它们反复进入组透明度的 `saveLayer`。默认路径的稳态 raster p50 为 **34.70 ms**，build 为 **1.33 ms**，栅格线程前还排队 **29.00 ms**。外提共享裁剪把 290 次 `clipPath` 降到 2 次，保留 28 次 `saveLayer`，raster 降至 **4.89 ms**，帧完成速率从 **28.48** 回到 **120.17 帧/秒**。

## 设备与采样

- Samsung SM-A566B，Android 17，1080 × 2340，DPR 2.8125，Flutter 上报 120 Hz。Flutter 3.50.1，engine `4d35714800b9266b6693a58e1225ecd7e9e45ed7`，profile arm64。Impeller 启动日志确认 Vulkan。Skia 用 Android `enable-impeller=false` intent，Flutter embedding 将其转换为与 `flutter run --no-enable-impeller` 相同的引擎开关，日志确认 opt-out。
- 原生代码基线 `ef45b2a5`。两次 APK 构建中的 `lib/arm64-v8a/libxvg.so` 与本地 `cargo build --release --locked --target aarch64-linux-android` 产物 SHA-256 一致，均为 `7bdc111d409fbcef87f6a9106147de4bd2bb8cc0e6ebd9a8e4979e7e7771b100`。打包后恢复了 `android/build.gradle` 的 JNI 来源。
- 页面固定显示一个 spinner。插画按 375 逻辑像素宽展示，总高 2114，384 × 832 逻辑像素的视口最多显示顶部 39.4%。完全移出视口时保留挂载。整图可见组把图缩到约 148 × 832，因此同时改变了可见内容和比例。
- 每组至少三个 `am force-stop` 后的独立冷启动。预热 spinner 后取挂载前最后 30 帧。出图早期窗口取 xvg 录制完成后的前 25 帧。稳态从请求后 800 ms 开始，持续约 1.9 秒。表内给出各轮统计量的中位数和最小至最大值。解析失败、息屏后缺报告的试跑和时间线抓取轮均另计。第二版 APK 用默认关闭的原型开关复测，默认 Impeller raster p50 同为 34.70 ms。

## 1. 帧耗时和排队

`vsyncOverhead` 从 vsync 到 build 开始，排队从 `buildFinish` 到 `rasterStart`，`rasterDuration` 从 `rasterStart` 到 `rasterFinish`。`totalSpan` 是同一帧从 vsync 到 raster 结束的墙钟时延，各列独立取中位数。这里的帧完成速率按 `rasterFinish` 首尾间隔计算。120 Hz 的单帧预算是 8.33 ms，同时保留 16.6 ms 与上一轮比较。 [Flutter `FrameTiming.totalSpan`](https://api.flutter.dev/flutter/dart-ui/FrameTiming/totalSpan.html) · [Flutter `addTimingsCallback`](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)

| Impeller 默认，三个独立进程 | vsync p50 ms | build p50 ms | 排队 p50 ms | raster p50 ms | totalSpan p50 ms | totalSpan 最大值 ms | totalSpan >16.6 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| 挂载前 30 帧 | 0.96 [0.81–1.22] | 0.65 [0.59–0.73] | 0.30 [0.27–0.35] | 1.06 [0.85–1.19] | 3.04 [2.86–3.78] | 5.24 [4.33–6.32] | 0/30 |
| 出图后前 25 帧 | 1.21 [1.13–1.25] | 1.12 [1.07–1.22] | 30.30 [30.14–30.43] | 34.76 [34.58–35.26] | 67.51 [67.45–69.11] | 106.88 [104.83–106.89] | 25/25 |
| 稳态，每轮 53–54 帧 | 1.40 [1.36–1.47] | 1.33 [1.27–1.35] | 29.00 [28.96–29.29] | 34.70 [34.59–35.07] | 67.33 [66.42–68.07] | 71.88 [70.89–77.02] | 100% |

本场景复现了持续超时，绝对值高于上一轮。出图后前 25 帧 raster 最大值为 65.21 [63.42–66.96] ms。冷路径从默认异步改为同步后，稳态 raster 仍为 34.63 [34.60–34.82] ms，`totalSpan` 为 67.05 [66.78–67.39] ms，三轮同样全部超过 16.6 ms。异步与同步首次解析加录制分别为 39.02 [38.88–41.45] 和 28.88 [23.85–30.82] ms，其中异步含 worker 往返时间。各轮只有一次冷录制，稳态排队跟着 raster 长帧出现。

### Impeller Vulkan 时间线

独立启动 profile APK，打开 `trace-skia`，用 VM Service `getVMTimeline` 抓取原始事件。下表取 `1.raster` 线程的完整 `Rasterizer::DoDraw` 切片，挂载前 40 帧，其他每组取稳态 65 帧。列为每帧中位数。`Encode` 嵌套在 `Submit` 内，`编码后提交` 由同一帧的 `Submit` 结束减 `Encode` 结束得到。

| 切片 | 仅 spinner | 原图 | 去裁剪 | 去离屏层 | 外提共享裁剪 |
|---|---:|---:|---:|---:|---:|
| `Rasterizer::DoDraw`，ms | 1.17 | 34.93 | 4.88 | 4.86 | 5.00 |
| `SurfaceFrame::Submit`，ms | 0.91 | 34.43 | 4.67 | 4.63 | 4.76 |
| `SurfaceFrame::Encode`，ms | 0.34 | 10.29 | 4.13 | 4.02 | 4.18 |
| 编码后提交，ms | — | 24.03 | 0.51 | 0.56 | 0.49 |
| `AcquireNextDrawable`，ms | 0.10 | 0.15 | 0.08 | 0.08 | 0.08 |
| `Canvas::saveLayer`，次数/帧 | 0 | 28 | 28 | 0 | 28 |
| `Canvas::saveLayer` 切片合计，ms | 0 | 0.105 | 0.049 | 0 | 0.048 |

最贵的具名切片是 `SurfaceFrame::Submit`。引擎的 `Encode` 包含 DisplayList dispatch 和 Impeller 命令录制，`BuildDisplayList` 本身约 0.005 ms，Flutter 图层的 preroll 和 paint 各约 0.04 ms。编码结束后，Android Vulkan 的提交回调调用 `surface->Present()`，原图在这段又花约 24 ms。去裁剪、去层或外提裁剪，均使编码约少 6 ms，也令编码后的提交段回到约 0.5 ms。`Canvas::saveLayer` 的切片只包住入口工作，其派生的子通道绘制、恢复合成和 GPU 提交分散在后续流程。设备 Perfetto 未列出 `gpu.renderstages`，这份 trace 能归因到编码和提交阶段，不能把 24 ms 分摊到单个 GPU pass、驱动等待或 GPU 执行。 [Flutter 3.50.1 `SurfaceFrame`](https://github.com/flutter/flutter/blob/3.50.1/engine/src/flutter/flow/surface_frame.cc) · [Flutter 3.50.1 Vulkan surface](https://github.com/flutter/flutter/blob/3.50.1/engine/src/flutter/shell/gpu/gpu_surface_vulkan_impeller.cc)

## 2. 保留图层、后端和可见区域

默认 `StaticXvg` 因裁剪风险使用 `PixelSnapBoundary`，它本身就是 `RepaintBoundary`。受控组通过 `XvgPixelSnap.never` 移除这层，再配对加普通 `RepaintBoundary`。另两组直接在布局和 `BoxFit.fill` 中复现物理像素对齐后的坐标，隔离对齐与边界的作用。Flutter paint 探针放在受控边界内。 [xvg 的像素对齐层](../lib/src/pixel_snap_layer.dart)

| 稳态场景 | raster p50 ms | raster p95 ms | totalSpan p50 ms | 帧完成/秒 |
|---|---:|---:|---:|---:|
| Impeller 默认，顶部可见 | 34.70 [34.59–35.07] | 35.60 [35.51–35.88] | 67.33 [66.42–68.07] | 28.48 [28.19–28.53] |
| Impeller 未对齐，无边界 | 196.23 [194.96–196.61] | 199.22 [198.27–207.06] | 390.48 [385.64–393.48] | 5.09 [5.04–5.09] |
| Impeller 未对齐，有边界 | 196.09 [194.38–197.91] | 199.03 [196.87–204.15] | 388.87 [388.18–392.29] | 5.11 [5.07–5.12] |
| Impeller 手动对齐，无边界 | 34.58 [34.57–34.69] | 35.83 [35.42–36.07] | 66.80 [66.64–67.14] | 28.52 [28.47–28.63] |
| Impeller 手动对齐，有边界 | 34.66 [34.47–34.71] | 35.53 [35.50–35.78] | 67.36 [66.70–67.40] | 28.51 [28.42–28.67] |
| Impeller 整图缩小至可见 | 69.29 [69.01–72.63] | 71.06 [70.86–78.07] | 137.28 [136.95–142.92] | 14.29 [13.66–14.37] |
| Impeller 完全屏外 | 1.63 [1.60–2.13] | 2.93 [2.51–3.00] | 4.54 [3.99–4.99] | 120.13 [119.48–120.27] |
| Skia 默认，顶部可见 | 2.40 [2.17–8.07] | 3.60 [3.19–10.32] | 4.55 [4.21–13.27] | 120.12 [119.61–120.13] |
| Skia 未对齐，无边界 | 3.27 [2.67–7.51] | 4.56 [4.17–10.66] | 5.65 [5.07–11.65] | 120.05 [120.04–120.17] |
| Skia 未对齐，有边界 | 7.74 [3.06–8.08] | 10.00 [4.46–10.15] | 11.77 [5.06–12.13] | 119.86 [119.83–120.23] |
| Skia 完全屏外 | 3.13 [3.04–3.13] | 4.26 [4.17–4.29] | 5.49 [5.48–5.59] | 120.22 [120.20–120.31] |

- 受控边界让插画进入 Flutter paint 的稳态次数归零。无边界时，Impeller 手动对齐组每轮记到 60 次，未对齐组 10–11 次。两组有边界时 raster 数值仍和各自的无边界组相当。录制缓存保留已有绘制命令，边界保留 Flutter 图层，后端每次仍可执行向量命令。
- Vulkan Impeller 的 `EnableRasterCache()` 返回 `false`，实测的 `pictureCacheCount` 与 `layerCacheCount` 都是 0。Skia 的可见组热态出现 1 个 Picture 栅格缓存项，约 20.83–20.85 MiB，完全屏外时为 0。Skia 冷启动前 25 帧仍约有 5 帧超过 16.6 ms，默认组 raster 最大值 96.75 [94.22–99.69] ms。 [Flutter 3.50.1 Impeller Vulkan surface](https://github.com/flutter/flutter/blob/3.50.1/engine/src/flutter/shell/gpu/gpu_surface_vulkan_impeller.cc) · [Flutter 3.50.1 Surface](https://github.com/flutter/flutter/blob/3.50.1/engine/src/flutter/flow/surface.cc)
- 默认像素对齐把严重的亚像素路径降回约 35 ms，普通边界只影响 UI paint。Impeller 源码允许接近整数边界的轴对齐矩形裁剪跳过深度写入，容差约 0.124 物理像素。这个快路径与手动对齐组的变化相符。基准尚未逐个统计哪些裁剪命中它。完全屏外接近各自的 spinner 底噪，同尺度仅显示顶部仍很贵。缩小整图会让更多路径进入可见区，其耗时包含比例变化。 [Flutter 3.50.1 `EntityPassClipStack`](https://github.com/flutter/flutter/blob/3.50.1/engine/src/flutter/impeller/entity/entity_pass_clip_stack.cc)

## 3. 录制操作与消融

`_recordScene` 实际调用 `drawPath` 184 次，`clipPath` 290 次，`saveLayer` 28 次，渐变 shader 73 次。矩形 clip API、mask `dstIn`、模糊滤镜、pattern shader 及位图 draw 均为 0。Rust 扁平列表将祖先裁剪带到路径上，145 个图元各录制同一对裁剪。透明度命令在 `_paintCommands` 中调用 `saveLayer`，因此本样本的 28 次调用全由透明度合成触发。Flutter DisplayList 也会识别形状并改写或裁剪录制操作。这里的 290 和 28 是 Canvas API 次数，实际 GPU pass 另看时间线和后端优化。 [静态录制逻辑](../lib/src/rust_static_svg.dart) · [Flutter 3.50.1 DisplayList builder](https://github.com/flutter/flutter/blob/3.50.1/engine/src/flutter/display_list/dl_builder.cc)

| Impeller 消融或原型 | raster p50 ms | raster p95 ms | totalSpan p50 ms | totalSpan >16.6 ms |
|---|---:|---:|---:|---:|
| 原图默认 | 34.70 [34.59–35.07] | 35.60 [35.51–35.88] | 67.33 [66.42–68.07] | 100% |
| 仅去裁剪 | 4.88 [4.80–4.92] | 5.46 [5.44–5.47] | 6.32 [6.30–6.32] | 0% |
| 仅去 `saveLayer` | 4.86 [4.83–4.89] | 5.33 [5.29–6.15] | 6.45 [6.36–6.45] | 0% |
| 仅去渐变 shader | 33.20 [33.15–34.90] | 34.46 [33.96–41.76] | 64.61 [63.71–68.23] | 100% |
| 外提共享裁剪，保留离屏层和渐变 | 4.89 [4.86–4.95] | 5.49 [5.47–5.88] | 6.35 [6.33–6.46] | 0% |

去裁剪或者把透明层改成普通 `save`，都会释放约 30 ms 的稳态 raster。共享裁剪外提重现了这个收益，且保留同样的 28 个透明度层、184 个 path draw 和 73 个 shader。证据指向重复裁剪与离屏合成叠加的成本。两项消融收益有重叠，不能相加。三个消融会改变视觉，只用来归因，其中去渐变保留路径和描边但用纯色 paint 替换 shader。

## 4. `flutter_svg` 对照

`bench_app` 已依赖 `flutter_svg 2.3.2`，锁定 `vector_graphics` 和 `vector_graphics_compiler 1.2.6`。同一原始输入用 `SvgPicture.string` 构建，Impeller 和 Skia 各三次均在路径数字解析时抛 `StateError`，因此原图没有可用的 `flutter_svg` raster 数字。两条路径含非法非有限坐标。`usvg 0.50.0` 的 `convert_path_data` 在错误处停止迭代并保留有效前缀。兼容组在运行时对两个库传入同一份截断输入，保留其它 SVG 内容和相同的视口、spinner 与显示尺寸。 [flutter_svg 渲染策略](https://pub.dev/packages/flutter_svg/versions/2.3.2) · [usvg `convert_path_data`](https://docs.rs/usvg/0.50.0/src/usvg/parser/shapes.rs.html)

| 兼容输入，各三个独立进程 | raster p50 ms | raster p95 ms | totalSpan p50 ms | totalSpan >16.6 ms | 帧完成/秒 |
|---|---:|---:|---:|---:|---:|
| Impeller · xvg | 34.98 [34.73–35.10] | 36.50 [35.76–36.98] | 67.57 [67.20–68.15] | 100% | 28.14 [28.10–28.43] |
| Impeller · flutter_svg Picture | 15.29 [15.26–15.48] | 15.58 [15.53–16.07] | 27.49 [27.20–27.75] | 100% | 64.71 [63.75–64.74] |
| Skia · xvg | 7.42 [2.59–7.85] | 10.30 [3.62–10.46] | 11.57 [5.08–12.25] | 0% | 119.79 [119.70–120.24] |
| Skia · flutter_svg Picture | 6.42 [6.30–6.45] | 7.42 [7.28–7.72] | 8.17 [7.80–8.18] | 0% | 120.16 [120.13–120.20] |

同一输入的两个库在 Impeller 下都超过 120 Hz 的 raster 预算，xvg 原始录制额外多约 20 ms。xvg 兼容前后所测的 2,326,320 个屏幕像素完全一致，`flutter_svg` 与 xvg 比较则有 26.15% 的像素不同，11.59% 的像素最大通道差超过 8 个 8-bit 色阶。跨库数据反映两种实际输出的成本。确定重复裁剪贡献的证据来自 xvg 自身的消融和保留内容的外提对照。

## 5. 首次成本与内存

| Impeller 方案 | 稳态 raster p50 / p95 ms | 请求至首张图 raster 完成 ms | `toImage` 回调墙钟 ms | 常驻像素预算 |
|---|---|---:|---:|---:|
| 默认向量 | 34.70 [34.59–35.07] / 35.60 [35.51–35.88] | 79.34 [75.75–82.25] | — | 无新增位图 |
| 外提共享裁剪 | 4.89 [4.86–4.95] / 5.49 [5.47–5.88] | 74.14 [72.32–77.53] | — | 无新增位图 |
| 整图 `ui.Image` | 1.93 [1.92–1.96] / 2.39 [2.37–2.51] | 571.54 [556.75–571.93] | 66.07 [65.20–66.55] | 1055 × 5946 × 4 = 25,092,120 B（23.93 MiB） |
| 只生成视口顶部的 `ui.Image` | 4.34 [4.31–4.41] / 5.42 [5.30–5.82] | 100.80 [99.74–117.53] | 38.47 [35.82–49.35] | 1055 × 2340 × 4 = 9,874,800 B（9.42 MiB） |

位图方案用 `Picture.toImage` 按显示尺寸乘 DPR 生成，再交给 `RawImage` 绘制。生成时保留已录制的向量 Picture。像素预算按 RGBA8 计算，仅覆盖最终纹理，临时附件、驱动对齐、mipmap 等额外分配不在其中。引擎列出的向量 Picture `approximateBytesUsed` 从 36,904 B 降至 26,536 B，不能用它估算 GPU 瞬时分配。

整图纹理的 Future 约 66 ms 返回，但准备期间伴随 spinner 的最长 raster 达 459.86 [450.62–464.73] ms。随后第一张位图的 build 到 raster 排队为 456.96 [448.80–461.97] ms。只生成视口时，准备期间最长 raster 降至 18.76 [17.67–21.86] ms。稳态整图/视口 `totalSpan` p50 分别为 4.39 [4.35–4.47] / 7.11 [6.95–7.11] ms，超过 16.6 ms 的比例分别为 0% / 0% [0–2.63%]。两种位图都能将稳态帧完成速率拉到约 120 帧/秒，此处的整图稳态优势只代表这组设备和负载。

单独的启动 trace 复现整图组 439.40 ms 的 raster，`SurfaceFrame::Submit` 占 439.18 ms，其中 `Encode` 仅 0.11 ms。视口组对应长帧为 18.32 ms，`Submit` 18.19 ms，`Encode` 0.10 ms。异步 `toImage` 的 Future 返回时间不足以衡量首次显示成本，等待出现在后续屏幕帧的 Vulkan 提交阶段。

同一次真机截图对照中，共享裁剪原型仅有 34 / 2,326,320 像素相差 1 色阶，整图和视口位图各有约 1.93% 像素的最大通道差超过 8，平均每通道误差约 1.46 和 1.45 色阶。位图原型的 `RawImage` 采样和摆放省略了向量路径的 `PixelSnapBoundary`，像素差统计包含这一变化。截图在内存中比较，排除了状态栏、导航栏和 spinner 区域。

## 建议与局限

1. **先验证共享裁剪外提的正式实现。** 本图稳态 raster 下降约 86%，首张图约 74 ms，无新增位图。原型只对每条路径具有完全相同裁剪链、无图像、无 mask 和 blur 的场景启用。保留顺序和透明度层。正式落地还需要覆盖不同缩放、亚像素位置、半透明重叠和嵌套裁剪，验证边缘覆盖后再决定适用范围。
2. **复杂静态内容需要位图时，优先做按区域的显式缓存。** 本图固定首屏的缓存为 9.42 MiB，首次约 101 ms，稳态 p95 raster 约 5.42 ms。滚动内容可按视口或分块生成，按显示尺寸、DPR、主题和内容裁切位置决定复用，并以像素字节数控制占用。整图位图适合能在交互前准备好的固定资产，本例 23.93 MiB 和约 0.57 秒首次显示代价值得单列。
3. **保留像素对齐和重绘隔离。** 它们分别改善亚像素裁剪和 UI paint。Skia 切换可作设备诊断，其热态收益伴随约 21 MiB 引擎缓存和明显冷帧，Android 的 opt-out 已弃用。 [Flutter Impeller 平台说明](https://docs.flutter.dev/perf/impeller)

结论覆盖一张插画、一台设备、一个固定页面和 Android Impeller Vulkan。它补上了仓库轻量图标压测缺少渐变和裁剪重叠的语料。稳态窗口约 1.9 秒，未对齐组每轮只有约 9 个稳态帧，尾部分位不稳定。设备热状态及频率波动也体现在范围中，尤其是 Skia。位图对照测量固定顶部，滚动、缩放、跨设备纹理上限和内存峰值留待正式实现验证。 [已有性能基准](../doc/performance-benchmarks.md)

## 复现

在仓库根目录用 [原生构建复现参数](async_threshold_results.md#复现) 生成 arm64 Rust 库，将 JNI 来源临时指向只含该库的 `arm64-v8a` 目录。用 Flutter 3.50.1 从 `benchmark/bench_app` 执行以下命令。打包结束后恢复 JNI 配置，并校验 APK 内 so 与本地 so 的哈希。

```powershell
flutter build apk --profile --no-pub --android-skip-build-dependency-validation `
  --target-platform android-arm64 --target lib/raster_233kb_bench.dart
adb -s R5CY2359S7D install -r build/app/outputs/flutter-apk/app-profile.apk
./tool/run_raster_233kb.ps1 -InputSvg $LocalSvg -AspectRatio (375 / 2114)
./tool/run_raster_233kb.ps1 -InputSvg $LocalSvg -AspectRatio (375 / 2114) `
  -Normalize -Cases @('impeller:xvg', 'impeller:flutter_svg', 'skia:xvg', 'skia:flutter_svg')
```

脚本只把输入放到设备临时目录和应用专属目录，以应用 UID 创建运行文件，并在退出时清理。逐帧 JSON、后端启动日志及单独抓取的 `trace_*.json` 和 `early_*.json` 在 `benchmark/bench_app/.dart_tool/raster_233kb_runs/`。原始矩阵使用 `20261126-180346-770`、`20261126-180848-632` 和 `20261126-181224-089`，原型配对使用 `20261126-181257-065`，两库兼容对照使用 `20261126-181417-474`。时间线复现时可用 `am start --ez trace-skia true` 启动，运行文件增加 `trace` 延长采样，`adb forward` 转发 APK 日志中的 VM Service 端口，再用 [现有时间线抓取工具](bench_app/tool/capture_timeline.dart) 抓取。

修改的 Dart 文件通过定向 `dart analyze`。新增 3 项基准测试通过，覆盖路径前缀兼容、裁剪外提与回退、消融视图像素。现有静态解析、加载及像素对齐 18 项测试全部通过。

## 正式实现复测

Rust 静态场景按分组输出入裁剪（4）和出裁剪（5），每个求交区域对应一对命令。Dart 进入裁剪时立即保存画布并设置裁剪，随后按命令开启和关闭透明度层。旧层内裁剪方案为了复现 HEAD，会在多笔透明度层内重设裁剪。终审弃用该方案，因为分组裁剪作用于子内容的合成结果，逐笔施加覆盖率会在抗锯齿边缘重复累积。本图最终录制 2 次 `clipPath`、28 次 `saveLayer`、184 次 `drawPath` 和 73 次渐变，保存与恢复共 30 对。 [W3C CSS Masking 合成顺序](https://www.w3.org/TR/css-masking-1/#module-interactions)

### 233 KB 插画顶部可见

SM-A566B、Flutter 3.50.1、arm64 profile、Impeller Vulkan、120 Hz。用 `run_raster_233kb.ps1` 以默认 xvg 模式冷启动三次，输入从本机运行时传入。稳态从请求后 800 ms 开始，约 1.9 秒。下表取各轮统计的中位数，时间单位为 ms。

| 稳态指标 | 改前 | 原型 | 层内裁剪方案 | 最终实现 |
|---|---:|---:|---:|---:|
| raster p50 | 34.70 | 4.89 | 8.965 | **4.905** |
| raster p95 | 35.60 | 5.49 | 9.307 | **5.426** |
| totalSpan p50 | 67.33 | 6.35 | 14.822 | **6.388** |
| totalSpan p95 | 71.133 | 7.037 | 18.587 | **7.200** |
| 帧完成速率（帧/秒） | 28.48 | 120.17 | 109.573 | **120.177** |
| `clipPath` 调用次数 | 290 | 2 | 6 | **2** |
| `saveLayer` 调用次数 | 28 | 28 | 28 | 28 |

| 最终轮次 | 稳态帧数 | raster p50 | raster p95 | totalSpan p50 | totalSpan p95 | 帧完成速率 |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 228 | 4.904 | 6.185 | 6.363 | 7.544 | 120.177 |
| 2 | 228 | 4.937 | 5.344 | 6.421 | 6.981 | 120.175 |
| 3 | 228 | 4.905 | 5.426 | 6.388 | 7.200 | 120.255 |

最终版 raster p50 比改前低 85.9%，比层内裁剪方案低 45.3%。三轮的 raster p95 和 totalSpan p95 都低于 120 Hz 的 8.33 ms 单帧预算。回放始终保持透明度层外的裁剪范围，实测回到原型的吞吐量。最终和层内裁剪方案的逐帧 JSON 与后端日志分别在本次工作区 `bench_app/.dart_tool/raster_233kb_runs/20261126-191043-713/` 和 `20261126-190012-733/`，最终三轮开始时热状态均为 0。

### 1000 图标滚动回归

同一手机及 profile 配置，`LIB=xvg ITEMS=1000 CYCLES=6`，每版三次独立冷启动。改前 APK 使用 `ef45b2a5` 的 Dart 与 Rust。每轮均有 1000 次解析和 1000 张已缓存的 Picture。超时帧按现有基准的 UI build 超过 16.6 ms 计数。

| 版本/轮次 | 采样帧数 | build avg ms | raster avg ms | build >16.6 ms | parse avg ms |
|---|---:|---:|---:|---:|---:|
| 改前 1 | 1297 | 1.728 | 4.376 | 0 | 0.117 |
| 改前 2 | 1296 | 1.720 | 4.389 | 0 | 0.109 |
| 改前 3 | 1296 | 1.700 | 4.387 | 0 | 0.111 |
| 层内裁剪 1 | 1300 | 1.635 | 4.452 | 0 | 0.096 |
| 层内裁剪 2 | 1296 | 1.664 | 4.446 | 0 | 0.113 |
| 层内裁剪 3 | 1296 | 1.683 | 4.318 | 0 | 0.107 |
| 最终 1 | 1301 | 1.575 | 3.943 | 0 | 0.098 |
| 最终 2 | 1296 | 1.693 | 4.312 | 0 | 0.117 |
| 最终 3 | 1296 | 1.703 | 4.416 | 0 | 0.115 |
| 改前中位数 | 1296 | 1.720 | 4.387 | 0 | 0.111 |
| 层内裁剪中位数 | 1296 | 1.664 | 4.446 | 0 | 0.107 |
| 最终中位数 | 1296 | 1.693 | 4.312 | 0 | 0.115 |

最终版与改前相比，build 和 raster 的平均耗时中位数分别下降 0.027 ms 和 0.075 ms，parse 上升 0.004 ms，三项的三轮范围均重叠。普通图标的显示列表在 SSE 中占 1 字节空值标记，原空命令数组占 4 字节。

| APK | `lib/arm64-v8a/libxvg.so` SHA-256 |
|---|---|
| 改前图标 | `7bdc111d409fbcef87f6a9106147de4bd2bb8cc0e6ebd9a8e4979e7e7771b100` |
| 层内裁剪方案，插画与图标 | `27293400144b16295457e7413f8d92d6b65ba35452daa6685ba1fb5e24a15fc7` |
| 最终，插画与图标 | `98a378d76d61689b71d89c577b622c5f9bee5e45feb656ec21f92577d9fd1495` |

APK 内 so 与各版本本机产物逐个核对一致。打包后恢复 JNI 来源配置。

### 像素与局限

用 Windows Flutter 3.50.1 测试引擎和真实 FFI，比对 `ef45b2a5` 的 10 个手绘 SVG、各 3 组缩放与偏移，共 30 张 96 × 96 的预乘 RGBA 图。三组变换依次是 `(1.0, 0, 0)`、`(0.8, 0.25, 0.75)`、`(1.5, 0.5, 0.125)`，每组为倍率与 x/y 偏移。阈值为非边缘像素完全一致，每张图最多 0.5% 的像素变化，最大通道差 2 个 8 位色阶。

| 夹具 | 变换 1，差异像素数 / 最大通道差 | 变换 2 | 变换 3 | 非边缘差异像素数，按变换 |
|---|---:|---:|---:|---:|
| 嵌套裁剪、未裁剪路径和相邻兄弟 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |
| 同组裁剪加透明度和半透明重叠 | 294 / 17 | 181 / 18 | 603 / 18 | 122 / 52 / 341 |
| 裁剪、最近遮罩和遮罩子列表 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |
| 裁剪和最近的模糊 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |
| 图片与几何共享裁剪 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |
| clipPath 自身引用另一个裁剪区域 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |
| 包围盒、变换与奇偶规则 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |
| 圆形与矩形裁剪下的单笔透明度层 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |
| 两笔透明度层内嵌一笔透明度层 | 1309 / 16 | 857 / 16 | 2931 / 16 | 961 / 567 / 2353 |
| 裁剪场景维持无透明度层的图片绘制顺序 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 / 0 |

严格 HEAD 对照失败，共 **6,175 / 276,480 像素**不同，最大通道差 **18**。两例的所有大于 2 色阶的差异都落在四邻域判定的边缘上，符合重叠图元从逐笔裁剪改为合成后统一裁剪的覆盖率变化。另有 **4,396 个非边缘像素**各相差 1 色阶。直接用 Canvas 在透明度层内外施加相同圆形裁剪，可在同一个平坦填充像素复现预乘 RGBA 从 `(78,18,26,116)` 到 `(79,18,26,116)` 的变化，说明该内部差异也能由 Flutter 的层重放产生。保留原基线和阈值。独立的覆盖率测试验证，两笔完全重合的不透明绘制在组裁剪和组透明度下，输出与只绘制最上层的结果相同。 [W3C CSS Masking 合成顺序](https://www.w3.org/TR/css-masking-1/#module-interactions)

`cargo test` 通过 100 项，忽略 3 项手动测试，现有 SSE 哈希断言通过。全量 `flutter test` 通过 2013 项、跳过 7 项，失败 1 项为上述严格 HEAD 对照。Windows 原生用例加载本次 release DLL，原生库加载相关跳过为 0。基准页的 3 项测试、格式化、静态分析和 native/web 绑定检查通过。`check_prebuilt` 按预期报告源码与预编译产物哈希不一致。

真机结论覆盖一台设备、一个固定的插画可见区域和本次图标语料。RGBA 对照覆盖所列手绘场景和变换。其他 GPU 后端、设备和更大的缩放范围尚未做同样的像素对照。
