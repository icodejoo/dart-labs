# GPU 工作量 A/B（2026-11-11）

vivo V2417，profile，60Hz，每变体 3 轮；原始数据 `tool/bench/results/gpu_ab/`。
变体入口：`run_perf.ps1 -Variants grid_steady,grid_picture,grid_noshadow,grid_flat,slot_raster,slot_noimg`
（`benchVariant` 见 `tool/bench/lib/main.dart`）。每轮同进程先录 `reference_spin`（只转一个方块）作参照。

Raster 均值 ms（3 轮）/ >12ms 帧数：

| 变体 | 场景 | 参照方块 |
| --- | --- | --- |
| grid_steady（默认 auto） | 7.50 / 16.75 / 5.81；55 / 288 / 0 | 4.43 / 4.13 / 4.67 |
| grid_picture（强制矢量，每帧重做 9 个模糊） | 12.49 / 3.71 / 7.58；181 / 0 / 48 | 16.74 / 4.90 / 4.88 |
| grid_noshadow | 3.73 / 3.58 / 5.51；0 / 0 / 2 | 4.86 / 4.53 / 4.60 |
| grid_flat（无阴影、纯色） | 5.59 / 3.27 / 5.34；0 / 0 / 4 | 4.93 / 16.72 / 4.76 |
| slot_raster | 2.88 / 5.58 / 4.87；0 / 2 / 0 | 4.70 / 4.60 / 2.90 |
| slot_noimg | 7.72 / 2.75 / 2.88；59 / 0 / 0 | 2.56 / 2.70 / 5.01 |

## 结论

1. **参照方块本身也双峰。** 同一个旋转方块，Raster 均值在 2.6~5ms 与 16.7ms 之间跳（grid_picture 第 1 轮、grid_flat 第 2 轮参照
   各有 290 帧 >12ms）。设备状态（疑似 GPU 调频/帧调度，logcat 有 vivo `/proc/fas/render` 的 avc 拒绝）是第一变量，
   内容差异（去阴影、去渐变、去图片）在 n=3 下被 ±2ms 的轮间噪声淹没，没有测出可区分的收益。
2. **唯一有方向性证据的是 grid 强制 Picture**：两个坏轮 worst 26/24ms、181/48 个尖峰帧，说明每帧重做模糊确实贵；
   但第 2 轮同配置仅 3.71ms、0 尖峰，同样落在“好状态”里。auto（运动期位图缓存阴影背景）已经避开这条路径。
3. slot_raster 稳态每帧只有少量 drawPicture + 每页一次 drawRawAtlas，本身没有可再砍的大项；slot_noimg 的一次 7.72 是坏状态，不是内容。
4. 没做的：逐帧 GPU 计数器（无 root 读不到 kgsl）、lotto、Skia 后端对照。

## 定论（用户拍板）

手机本身存在问题，不是 luckdraw 问题：空跑参照方块同样出现帧超 12ms。12ms 门禁不重定义；内容消融无可测收益，库绘制代码不改。
