# 自动位图缓存阈值第二轮真机测量

> 原始 JSON 体积较大（1–5 MB），未入库：由本目录脚本生成在 `benchmark/` 下，备份在仓库外。

**修复后推荐**。内容在框内、可见内容非空、（点数 ≥ 15,000 或 路径数 ≥ 100）、预计单图纹理 ≤ 12 MiB。由库在内部判断候选是否符合已有的网格稳定、预算和重绘条件。
留出组 47 个命中、0 个误开、1 个微利启用、18 个漏开，图标启用 0 个。下文主表记录修复前的第二轮结果，当前依据见末尾「异常修复与重拟合」。

上机计划 200 个网上 SVG 和 38 个第一轮样本，至少一个有效尺寸的文件分别为 199、38 个，全部尺寸有效的文件分别为 199、38 个。真机总耗时 1 小时 15 分 12 秒，含推送、启动、冷却和清理。

## 方法

- Samsung SM-A566B，序列号 `R5CY2359S7D`，Android 17，1080 × 2340 px，DPR 2.8125，120 Hz。Flutter 3.50.1，engine `4d35714800b9266b6693a58e1225ecd7e9e45ed7`，arm64 profile，Impeller Vulkan。
- APK 内 `lib/arm64-v8a/libxvg.so` SHA-256 为 `86463a7be4004ef0c6aed40a910663eb0355bb43d718080fd441f685d2fc41bd`。使用 `XVG_BENCH_JNI_DIR` 在构建时替换插件 JNI 输入目录。
- PC 显式加载同一工作区 Windows release DLL，SHA-256 为 `ccd69c4d0bc679f839c4673db69dc6d03435a994e2c86ab2904e02034942d1c6`。逐文件解析 SVG 并记录实际场景。唯一声明 ISO-8859-1 的输入按其 XML 声明解码。原 SVG 均经运行时输入，公开语料沿用随附清单的来源和许可证。
- 固定视口内左上对齐、等比缩放，图静止，独立 spinner 持续出帧。网上语料测 48dp、200dp、满宽，第一轮样本另测 16dp。每批一个 spinner 基线。每场景在首帧或分块齐备后预热 300ms，采样至少 650ms 且至少 18 帧，校验窗口内块持续就绪。模式和尺寸顺序用固定种子打散。
- 每轮取 raster p50，三轮组合分别取向量、缓存 p50 的中位数。净收益 = 向量 − 缓存，减去同一批基线后差值相同。主列表点数包含曲线控制点，图案计数按实际填充／描边引用，透明度、裁剪用显示列表入栈计数，遮罩、模糊计路径和图片实例。内容面积是保守包围盒面积，面积比分母为固有插画框。
- 按清单类别 × 体积（<4、4–<32、32–<256、≥256 KiB）× 主要特性分层，种子 `20261127`。特性优先级为位图、模糊、遮罩、图案、文字、密集路径、其他画笔效果、普通。密集路径为原生路径 ≥1,000 或点数 ≥10,000。先覆盖可抽取的层，再按剩余比例加样。计时前整张文件划分，同一图的尺寸始终在同一组。
- 十图试跑 0 小时 01 分 22 秒，平均 8.2s/图。按 200 图、每组合都测三轮的上界估计 1.72 小时，保留 200 个。
- 全部网上样本先测一次。以拟合组筛选轮定候选阈值，再对 [0.3, 3]ms 或离候选阈值约 20% 的 237 个网上尺寸组合各补两轮。第一轮样本的四档各测三轮。全程登记 1530 个尺寸轮次（含跳过）。
- 每约 2 秒读取系统热状态。出现 >0 就停应用，丢弃上次确认热状态为 0 后才完成的窗口。共 0 次停测，冷却等待 0 小时 00 分 00 秒，丢弃 0 条记录。热状态、轮次和基线均可在原始数据复算。
- 真机进程异常退出 6 次，`UNKNOWN` 1 次、`LOW_MEMORY` 5 次。已落盘且符合温控的组合继续使用，卡点以独立进程重试。
- 试跑样本编号 `web-269 web-583 web-330 web-629 web-403 web-018 web-296 web-126 web-518 web-384`。拟合和留出分别有 140、60 个文件，最终计分尺寸组合 417、180 个。

## 规则和命中

筛选轮候选为 **内容在框内，在屏内容面积 ≥ 524,288 px²，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB**。确认后仅用拟合计时重选，最终候选为 **内容在框内，在屏内容面积 ≥ 524,288 px²，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB**。候选要求内容边界已知且在框内，使用实际裁剪与内容交集的物理面积，预估 512px 分块、64px 预取和 RGBA8 采样边的纹理占用。有 ColorFilter 或几何／网格不稳定时走向量。路径、命令和图片特征每张 Picture 线性遍历一次，几何判定为常数时间。

拟合排除任何图标启用、净收益 ≤0 或任一重复轮变慢的候选。每个命中计 +1，每个微利启用计 −2，其后按命中数、微利数、内存上限、是否省去模糊项和收益总和比较。图标对照包括 MDI 和清单的 small、emoji、logo。组别固定，留出结果仅评价。

| 组 | 组合 | 启用 | 命中 >1ms | 误开 ≤0 | 微利 (0,1]ms | 漏开 >1ms | 其余关闭 | 图标启用 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 拟合 | 417 | 27 | 26 | 0 | 1 | 151 | 239 | 0 |
| 留出 | 180 | 8 | 6 | 0 | 2 | 57 | 115 | 0 |

首次筛选在 `web-442/200` 遇到 Android `LOW_MEMORY`。当批有 18 个已落盘组合，温控日志未落盘，整批从冻结名单重测。首次会话耗时计入真机总耗时。

| 规则族 | 组 | 独立拟合的门槛 | 启用 | 命中 >1ms | 误开 ≤0 | 微利 (0,1]ms | 漏开 >1ms | 其余关闭 | 图标启用 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 限制满宽 | 拟合 | 内容在框内，在屏内容面积 > 0，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB | 32 | 31 | 0 | 1 | 146 | 239 | 0 |
| 限制满宽 | 留出 | 内容在框内，在屏内容面积 > 0，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB | 8 | 6 | 0 | 2 | 57 | 115 | 0 |
| 双轴兜底 | 拟合 | 内容在框内，在屏内容面积 ≥ 524,288 px²，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB | 27 | 26 | 0 | 1 | 151 | 239 | 0 |
| 双轴兜底 | 留出 | 内容在框内，在屏内容面积 ≥ 524,288 px²，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB | 8 | 6 | 0 | 2 | 57 | 115 | 0 |
| 取消面积下限 | 拟合 | 保持向量 | 0 | 0 | 0 | 0 | 177 | 240 | 0 |
| 取消面积下限 | 留出 | 保持向量 | 0 | 0 | 0 | 0 | 63 | 117 | 0 |
| 仅点数 | 拟合 | 内容在框内，在屏内容面积 ≥ 524,288 px²，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB | 27 | 26 | 0 | 1 | 151 | 239 | 0 |
| 仅点数 | 留出 | 内容在框内，在屏内容面积 ≥ 524,288 px²，点数 ≥ 10,000，预计单图纹理 ≤ 8 MiB | 8 | 6 | 0 | 2 | 57 | 115 | 0 |

“限制满宽”仍使用内容在框内的快路径，但只允许横向铺满。“双轴兜底”额外允许边界溢出／未知且插画框覆盖整个裁剪的旧快路径。保守规则可删除第一轮的仅横轴覆盖分支。满宽版本在拟合组多命中的组合未带来额外留出命中，双轴兜底也未增加命中。内容溢出且仅横轴覆盖的个别大图仍有收益，现阶段统一拒绝这类自动启用。

## 内容边界、面积和内存

| 样本集 | 文件 | 溢出 | 占比 | 框内 | 未知 |
| --- | --- | --- | --- | --- | --- |
| PC 全集 | 714 | 325 | 45.5% | 389 | 0 |
| 上机网上样本 | 200 | 95 | 47.5% | 105 | 0 |
| 第一轮复测 | 38 | 24 | 63.2% | 14 | 0 |

PC DLL 与 Android so 对 199 个有有效计时的文件分别提取特征，其中 0 个存在字段差异。规则拟合使用 Android 的实际原生场景特征。

| 组 | 组合 | >1ms | ≤0ms | 缓存驻留中位 MiB | 齐备中位 ms |
| --- | --- | --- | --- | --- | --- |
| 框内 | 358 | 201 | 42 | 1.02 | 34.542 |
| 溢出或未知 | 239 | 39 | 116 | 1.23 | 44.823 |

纹理估算与设备账本完全一致 488/597 个组合，绝对误差中位 0 B，最大 8,768 B。运行时应在分块预留前执行硬上限。全局账本维持 32 MiB 上限，单图上限只计算当前视口及预取需要的块。

候选单图上限为 8 MiB。启用组合实际最高 7.05 MiB。
框内且未铺满横轴的网上尺寸有拟合 101、留出 31 个收益超过 1ms，最终规则启用了其中 0、0 个。内容在框内的稳态路径只需覆盖内容与裁剪的交集，本轮门槛对较小尺寸仍留有明显收益空间。
拟合和留出分别覆盖 36、18 个图标对照组合。外溢、未知或颜色滤镜仍走旧覆盖逻辑，自动条件统一关闭。
留出组启用覆盖 8 个不同文件。拟合和留出启用组合中，至少一轮净收益 ≤0 的分别为 0、0 个。
保留候选面积下限 524,288 px²。去掉面积下限重新拟合时，留出命中 0、误开 0、漏开 63。

拟合三轮子集有 167 个尺寸组合，命中 14、误开 0、微利启用 1、漏开 92。补测按收益区间和候选边界选取，统计代表该子集。

留出三轮子集有 70 个尺寸组合，命中 2、误开 0、微利启用 2、漏开 35。补测按收益区间和候选边界选取，统计代表该子集。

各尺寸需完成安排的全部轮次才参与计分。以下为设备跳过记录。

| 样本 | 尺寸 | 轮 | 阶段 | 原因 |
| --- | --- | --- | --- | --- |
| web-442 | 200 | 1 | render | isolated_process_exit:LOW_MEMORY |
| web-442 | 48 | 1 | render | isolated_process_exit:LOW_MEMORY |
| web-442 | full | 1 | render | isolated_process_exit:LOW_MEMORY |

用 PC 场景几何检查了跳过的公开组合，候选会启用其中 0 个。这些组合缺少收益标签，独立于命中表。

## 第一轮同样本同尺寸对比

共有 120/120 个主矩阵组合可按相同尺寸配对。以下差值按组合计算后取中位数，缓存时间为新减旧，净收益为新减旧。

| 分组 | 配对 | 缓存时间 Δms | 收益 Δms | 上一轮 >1ms | 本轮 >1ms |
| --- | --- | --- | --- | --- | --- |
| 全部 | 120 | -0.158 | 0.047 | 11 | 11 |
| 框内，图未铺满整个裁剪 | 42 | -0.211 | 0.280 | 2 | 6 |
| 溢出或未知 | 76 | -0.103 | -0.025 | 7 | 3 |
| 上一轮规则启用 | 5 | 0.019 | -0.490 | 5 | 5 |

- `aurora` 200dp 的缓存耗时从 13.273 降到 1.805ms，净收益从 1.109 到 12.177ms。
- `legacy-014` 48dp 的缓存耗时从 4.208 降到 1.847ms，净收益从 -0.145 到 3.028ms。

| 样本 | 尺寸 | 边界 | 向量旧/新 ms | 缓存旧/新 ms | 收益旧/新 ms | 纹理旧/新 B |
| --- | --- | --- | --- | --- | --- | --- |
| legacy-014 | 16 | 框内 | 4.800 / 4.820 | 4.861 / 2.145 | -0.061 / 2.675 | 56,592 / 56,592 |
| legacy-014 | 48 | 框内 | 4.063 / 4.875 | 4.208 / 1.847 | -0.145 / 3.028 | 445,824 / 445,824 |
| legacy-014 | 200 | 框内 | 4.103 / 4.094 | 2.251 / 2.095 | 1.852 / 1.999 | 5,948,928 / 5,948,928 |
| legacy-014 | full | 框内 | 5.823 / 8.126 | 2.027 / 1.871 | 3.796 / 6.255 | 11,319,488 / 11,319,488 |
| aurora | 16 | 框内 | 6.220 / 6.090 | 6.174 / 2.059 | 0.046 / 4.031 | 40,608 / 40,608 |
| aurora | 48 | 框内 | 6.448 / 6.182 | 6.507 / 2.145 | -0.059 / 4.037 | 317,952 / 317,952 |
| aurora | 200 | 框内 | 14.382 / 13.982 | 13.273 / 1.805 | 1.109 / 12.177 | 5,239,296 / 5,239,296 |
| aurora | full | 框内 | 24.738 / 23.682 | 2.004 / 2.031 | 22.734 / 21.651 | 11,319,488 / 11,319,488 |
| complex-1 | 48 | 框内 | 2.476 / 2.367 | 2.731 / 1.929 | -0.255 / 0.438 | 82,944 / 82,944 |
| complex-1 | 200 | 框内 | 2.389 / 2.255 | 2.809 / 2.156 | -0.420 / 0.099 | 1,327,104 / 1,327,104 |
| complex-1 | full | 框内 | 2.148 / 2.264 | 2.538 / 2.133 | -0.390 / 0.131 | 4,804,864 / 4,804,864 |
| complex-2 | 48 | 框内 | 2.483 / 2.459 | 2.499 / 1.986 | -0.016 / 0.473 | 82,944 / 82,944 |
| complex-2 | 200 | 框内 | 2.247 / 2.356 | 2.227 / 2.000 | 0.020 / 0.356 | 1,327,104 / 1,327,104 |
| complex-2 | full | 框内 | 2.158 / 2.498 | 2.188 / 2.017 | -0.030 / 0.481 | 4,804,864 / 4,276,624 |
| complex-3 | 48 | 框内 | 2.091 / 1.954 | 2.084 / 2.069 | 0.007 / -0.115 | 82,944 / 82,944 |
| complex-3 | 200 | 框内 | 2.111 / 2.022 | 2.083 / 2.132 | 0.028 / -0.110 | 1,327,104 / 1,073,296 |
| complex-3 | full | 框内 | 2.097 / 1.920 | 2.109 / 1.761 | -0.012 / 0.159 | 4,804,864 / 4,276,624 |
| complex-4 | 48 | 框内 | 2.342 / 2.266 | 2.301 / 2.064 | 0.041 / 0.202 | 82,944 / 82,944 |
| complex-4 | 200 | 框内 | 2.120 / 2.695 | 2.139 / 2.250 | -0.019 / 0.445 | 1,327,104 / 1,327,104 |
| complex-4 | full | 框内 | 2.066 / 3.232 | 3.145 / 2.932 | -1.079 / 0.300 | 4,804,864 / 4,276,624 |
| complex-5 | 48 | 框内 | 2.293 / 2.337 | 2.312 / 2.068 | -0.019 / 0.269 | 82,944 / 82,944 |
| complex-5 | 200 | 框内 | 2.690 / 2.193 | 2.865 / 2.057 | -0.175 / 0.136 | 1,327,104 / 1,073,296 |
| complex-5 | full | 框内 | 2.036 / 2.037 | 1.962 / 2.398 | 0.074 / -0.361 | 4,804,864 / 4,276,624 |
| complex-6 | 48 | 框内 | 2.170 / 2.326 | 2.053 / 1.923 | 0.117 / 0.403 | 82,944 / 82,944 |
| complex-6 | 200 | 框内 | 2.116 / 1.869 | 2.096 / 2.285 | 0.020 / -0.416 | 1,327,104 / 1,193,472 |
| complex-6 | full | 框内 | 2.182 / 2.102 | 2.029 / 1.927 | 0.153 / 0.175 | 4,804,864 / 4,533,056 |
| mdi-0 | 48 | 框内 | 2.074 / 2.126 | 2.252 / 2.063 | -0.178 / 0.063 | 82,944 / 82,944 |
| mdi-0 | 200 | 框内 | 1.931 / 1.879 | 2.167 / 1.927 | -0.236 / -0.048 | 1,327,104 / 1,193,472 |
| mdi-0 | full | 框内 | 1.872 / 2.105 | 2.108 / 1.944 | -0.236 / 0.161 | 4,804,864 / 4,276,624 |
| mdi-12 | 48 | 框内 | 2.044 / 2.055 | 2.258 / 1.934 | -0.214 / 0.121 | 82,944 / 82,944 |
| mdi-12 | 200 | 框内 | 1.988 / 1.890 | 2.057 / 1.706 | -0.069 / 0.184 | 1,327,104 / 1,327,104 |
| mdi-12 | full | 框内 | 2.020 / 2.088 | 2.089 / 2.150 | -0.069 / -0.062 | 4,804,864 / 4,276,624 |
| mdi-236 | 48 | 框内 | 2.125 / 2.248 | 2.369 / 2.313 | -0.244 / -0.065 | 82,944 / 82,944 |
| mdi-236 | 200 | 框内 | 2.048 / 2.019 | 2.244 / 2.115 | -0.196 / -0.096 | 1,327,104 / 1,327,104 |
| mdi-236 | full | 框内 | 2.119 / 2.097 | 2.074 / 2.045 | 0.045 / 0.052 | 4,804,864 / 4,276,624 |
| mdi-500 | 48 | 框内 | 2.165 / 2.148 | 2.074 / 1.941 | 0.091 / 0.207 | 82,944 / 82,944 |
| mdi-500 | 200 | 框内 | 2.071 / 2.323 | 2.262 / 2.171 | -0.191 / 0.152 | 1,327,104 / 1,193,472 |
| mdi-500 | full | 框内 | 2.266 / 2.654 | 2.028 / 2.622 | 0.238 / 0.032 | 4,804,864 / 4,533,056 |
| mdi-789 | 48 | 框内 | 2.153 / 1.981 | 2.310 / 2.022 | -0.157 / -0.041 | 82,944 / 82,944 |
| mdi-789 | 200 | 框内 | 2.222 / 2.138 | 2.415 / 2.058 | -0.193 / 0.080 | 1,327,104 / 1,327,104 |
| mdi-789 | full | 框内 | 2.153 / 2.109 | 2.294 / 2.084 | -0.141 / 0.025 | 4,804,864 / 4,276,624 |
| mdi-999 | 48 | 框内 | 2.166 / 2.125 | 2.384 / 2.109 | -0.218 / 0.016 | 82,944 / 82,944 |
| mdi-999 | 200 | 框内 | 2.161 / 2.326 | 2.262 / 2.089 | -0.101 / 0.237 | 1,327,104 / 1,327,104 |
| mdi-999 | full | 框内 | 2.144 / 2.979 | 2.202 / 2.440 | -0.058 / 0.539 | 4,804,864 / 4,533,056 |
| synthetic-1000-blur-grad | 48 | 兜底 | 6.232 / 6.004 | 6.009 / 5.851 | 0.223 / 0.153 | 82,944 / 82,944 |
| synthetic-1000-blur-grad | 200 | 兜底 | 5.781 / 6.540 | 5.964 / 6.525 | -0.183 / 0.015 | 1,327,104 / 1,327,104 |
| synthetic-1000-blur-grad | full | 兜底 | 9.146 / 8.972 | 9.396 / 9.154 | -0.250 / -0.182 | 4,804,864 / 4,804,864 |
| synthetic-1000-blur-layers | 48 | 兜底 | 6.086 / 6.398 | 6.425 / 6.393 | -0.339 / 0.005 | 82,944 / 82,944 |
| synthetic-1000-blur-layers | 200 | 兜底 | 5.844 / 6.416 | 6.479 / 6.304 | -0.635 / 0.112 | 1,327,104 / 1,327,104 |
| synthetic-1000-blur-layers | full | 兜底 | 12.903 / 12.525 | 12.749 / 12.344 | 0.154 / 0.181 | 4,804,864 / 4,804,864 |
| synthetic-1000-layers-grad | 48 | 兜底 | 6.464 / 5.907 | 6.386 / 6.321 | 0.078 / -0.414 | 82,944 / 82,944 |
| synthetic-1000-layers-grad | 200 | 兜底 | 5.894 / 6.094 | 5.628 / 5.808 | 0.266 / 0.286 | 1,327,104 / 1,327,104 |
| synthetic-1000-layers-grad | full | 兜底 | 10.543 / 10.300 | 10.921 / 10.666 | -0.378 / -0.366 | 4,804,864 / 4,804,864 |
| synthetic-1000-plain | 48 | 兜底 | 5.698 / 5.590 | 5.795 / 5.635 | -0.097 / -0.045 | 82,944 / 82,944 |
| synthetic-1000-plain | 200 | 兜底 | 5.769 / 5.526 | 5.842 / 5.684 | -0.073 / -0.158 | 1,327,104 / 1,327,104 |
| synthetic-1000-plain | full | 兜底 | 4.828 / 5.617 | 5.847 / 5.621 | -1.019 / -0.004 | 4,804,864 / 4,804,864 |
| synthetic-200-blur | 48 | 兜底 | 4.693 / 4.524 | 4.593 / 4.425 | 0.100 / 0.099 | 82,944 / 82,944 |
| synthetic-200-blur | 200 | 兜底 | 4.702 / 4.458 | 4.660 / 4.580 | 0.042 / -0.122 | 1,327,104 / 1,327,104 |
| synthetic-200-blur | full | 兜底 | 3.729 / 3.613 | 3.525 / 3.528 | 0.204 / 0.085 | 4,804,864 / 4,804,864 |
| synthetic-200-blur-grad | 48 | 兜底 | 4.626 / 3.904 | 4.595 / 3.771 | 0.031 / 0.133 | 82,944 / 82,944 |
| synthetic-200-blur-grad | 200 | 兜底 | 4.763 / 3.981 | 4.726 / 4.630 | 0.037 / -0.649 | 1,327,104 / 1,327,104 |
| synthetic-200-blur-grad | full | 兜底 | 3.825 / 4.469 | 3.681 / 3.853 | 0.144 / 0.616 | 4,804,864 / 4,804,864 |
| synthetic-200-blur-layers | 48 | 兜底 | 4.686 / 4.692 | 4.228 / 4.862 | 0.458 / -0.170 | 82,944 / 82,944 |
| synthetic-200-blur-layers | 200 | 兜底 | 4.060 / 3.972 | 3.900 / 3.792 | 0.160 / 0.180 | 1,327,104 / 1,327,104 |
| synthetic-200-blur-layers | full | 兜底 | 11.704 / 11.330 | 10.961 / 10.586 | 0.743 / 0.744 | 4,804,864 / 4,804,864 |
| synthetic-200-blur-layers-grad | 48 | 兜底 | 4.137 / 4.177 | 4.258 / 4.829 | -0.121 / -0.652 | 82,944 / 82,944 |
| synthetic-200-blur-layers-grad | 200 | 兜底 | 4.195 / 4.813 | 4.099 / 4.864 | 0.096 / -0.051 | 1,327,104 / 1,327,104 |
| synthetic-200-blur-layers-grad | full | 兜底 | 11.869 / 11.524 | 11.309 / 10.951 | 0.560 / 0.573 | 4,804,864 / 4,804,864 |
| synthetic-200-grad | 48 | 兜底 | 3.243 / 3.476 | 3.101 / 3.761 | 0.142 / -0.285 | 82,944 / 82,944 |
| synthetic-200-grad | 200 | 兜底 | 3.929 / 3.130 | 3.792 / 3.566 | 0.137 / -0.436 | 1,327,104 / 1,327,104 |
| synthetic-200-grad | full | 兜底 | 4.119 / 4.020 | 3.058 / 3.582 | 1.061 / 0.438 | 4,804,864 / 4,804,864 |
| synthetic-200-layers | 48 | 兜底 | 3.439 / 3.216 | 4.016 / 4.046 | -0.577 / -0.830 | 82,944 / 82,944 |
| synthetic-200-layers | 200 | 兜底 | 3.838 / 3.201 | 4.390 / 3.800 | -0.552 / -0.599 | 1,327,104 / 1,327,104 |
| synthetic-200-layers | full | 兜底 | 3.990 / 3.344 | 3.484 / 3.054 | 0.506 / 0.290 | 4,804,864 / 4,804,864 |
| synthetic-200-layers-grad | 48 | 兜底 | 3.528 / 4.360 | 3.527 / 4.470 | 0.001 / -0.110 | 82,944 / 82,944 |
| synthetic-200-layers-grad | 200 | 兜底 | 3.537 / 4.530 | 3.530 / 4.463 | 0.007 / 0.067 | 1,327,104 / 1,327,104 |
| synthetic-200-layers-grad | full | 兜底 | 8.168 / 3.957 | 3.845 / 4.425 | 4.323 / -0.468 | 4,804,864 / 4,804,864 |
| synthetic-200-plain | 48 | 兜底 | 3.508 / 2.973 | 3.027 / 2.853 | 0.481 / 0.120 | 82,944 / 82,944 |
| synthetic-200-plain | 200 | 兜底 | 2.921 / 3.604 | 3.017 / 3.710 | -0.096 / -0.106 | 1,327,104 / 1,327,104 |
| synthetic-200-plain | full | 兜底 | 3.978 / 3.987 | 2.944 / 4.180 | 1.034 / -0.193 | 4,804,864 / 4,804,864 |
| synthetic-20000-blur-grad | 16 | 兜底 | 58.628 / 57.771 | 59.097 / 58.238 | -0.469 / -0.467 | 11,664 / 11,664 |
| synthetic-20000-blur-grad | 48 | 兜底 | 59.048 / 58.136 | 59.538 / 58.866 | -0.490 / -0.730 | 82,944 / 82,944 |
| synthetic-20000-blur-grad | 200 | 兜底 | 59.779 / 58.879 | 60.196 / 59.582 | -0.417 / -0.703 | 1,327,104 / 1,327,104 |
| synthetic-20000-blur-grad | full | 兜底 | 59.384 / 58.872 | 59.543 / 59.260 | -0.159 / -0.388 | 4,804,864 / 4,804,864 |
| synthetic-20000-blur-layers | 16 | 兜底 | 51.247 / 51.292 | 51.513 / 51.574 | -0.266 / -0.282 | 11,664 / 11,664 |
| synthetic-20000-blur-layers | 48 | 兜底 | 51.451 / 51.684 | 51.819 / 51.721 | -0.368 / -0.037 | 82,944 / 82,944 |
| synthetic-20000-blur-layers | 200 | 兜底 | 52.033 / 52.080 | 52.329 / 52.543 | -0.296 / -0.463 | 1,327,104 / 1,327,104 |
| synthetic-20000-blur-layers | full | 兜底 | 51.700 / 51.229 | 1.954 / 1.973 | 49.746 / 49.256 | 4,804,864 / 4,804,864 |
| synthetic-20000-layers-grad | 16 | 兜底 | 58.483 / 57.627 | 58.791 / 57.884 | -0.308 / -0.257 | 11,664 / 11,664 |
| synthetic-20000-layers-grad | 48 | 兜底 | 58.571 / 57.932 | 58.902 / 58.243 | -0.331 / -0.311 | 82,944 / 82,944 |
| synthetic-20000-layers-grad | 200 | 兜底 | 59.939 / 58.910 | 60.158 / 58.807 | -0.219 / 0.103 | 1,327,104 / 1,327,104 |
| synthetic-20000-layers-grad | full | 兜底 | 59.066 / 58.421 | 1.935 / 1.471 | 57.131 / 56.950 | 4,804,864 / 4,804,864 |
| synthetic-20000-plain | 16 | 兜底 | 50.043 / 49.470 | 50.157 / 49.439 | -0.114 / 0.031 | 11,664 / 11,664 |
| synthetic-20000-plain | 48 | 兜底 | 50.135 / 49.814 | 50.427 / 49.728 | -0.292 / 0.086 | 82,944 / 82,944 |
| synthetic-20000-plain | 200 | 兜底 | 50.776 / 49.898 | 50.868 / 50.721 | -0.092 / -0.823 | 1,327,104 / 1,327,104 |
| synthetic-20000-plain | full | 兜底 | 50.299 / 49.009 | 1.795 / 1.857 | 48.504 / 47.152 | 4,804,864 / 4,804,864 |
| synthetic-50-blur-grad | 48 | 兜底 | 4.097 / 3.965 | 4.022 / 4.091 | 0.075 / -0.126 | 82,944 / 82,944 |
| synthetic-50-blur-grad | 200 | 兜底 | 4.094 / 4.020 | 4.059 / 3.493 | 0.035 / 0.527 | 1,327,104 / 1,327,104 |
| synthetic-50-blur-grad | full | 兜底 | 3.319 / 3.094 | 2.974 / 2.889 | 0.345 / 0.205 | 4,804,864 / 4,804,864 |
| synthetic-50-blur-layers | 48 | 兜底 | 4.295 / 3.728 | 4.420 / 4.562 | -0.125 / -0.834 | 82,944 / 82,944 |
| synthetic-50-blur-layers | 200 | 兜底 | 3.583 / 3.680 | 4.342 / 3.443 | -0.759 / 0.237 | 1,327,104 / 1,327,104 |
| synthetic-50-blur-layers | full | 兜底 | 11.435 / 11.140 | 10.758 / 10.311 | 0.677 / 0.829 | 4,804,864 / 4,804,864 |
| synthetic-50-layers-grad | 48 | 兜底 | 2.909 / 2.887 | 2.965 / 3.007 | -0.056 / -0.120 | 82,944 / 82,944 |
| synthetic-50-layers-grad | 200 | 兜底 | 2.832 / 2.859 | 2.403 / 3.301 | 0.429 / -0.442 | 1,327,104 / 1,327,104 |
| synthetic-50-layers-grad | full | 兜底 | 3.955 / 3.080 | 2.593 / 2.618 | 1.362 / 0.462 | 4,804,864 / 4,804,864 |
| synthetic-50-plain | 48 | 兜底 | 2.266 / 2.713 | 2.389 / 2.309 | -0.123 / 0.404 | 82,944 / 82,944 |
| synthetic-50-plain | 200 | 兜底 | 2.357 / 2.386 | 2.448 / 2.428 | -0.091 / -0.042 | 1,327,104 / 1,327,104 |
| synthetic-50-plain | full | 兜底 | 2.373 / 2.024 | 2.501 / 2.328 | -0.128 / -0.304 | 4,804,864 / 4,804,864 |
| synthetic-5000-blur-grad | 48 | 兜底 | 15.933 / 15.769 | 16.013 / 15.803 | -0.080 / -0.034 | 82,944 / 82,944 |
| synthetic-5000-blur-grad | 200 | 兜底 | 15.942 / 15.836 | 15.990 / 15.919 | -0.048 / -0.083 | 1,327,104 / 1,327,104 |
| synthetic-5000-blur-grad | full | 兜底 | 16.238 / 15.990 | 16.292 / 15.978 | -0.054 / 0.012 | 4,804,864 / 4,804,864 |
| synthetic-5000-blur-layers | 48 | 兜底 | 14.230 / 13.977 | 14.304 / 14.003 | -0.074 / -0.026 | 82,944 / 82,944 |
| synthetic-5000-blur-layers | 200 | 兜底 | 14.195 / 13.801 | 14.393 / 13.919 | -0.198 / -0.118 | 1,327,104 / 1,327,104 |
| synthetic-5000-blur-layers | full | 兜底 | 14.638 / 14.161 | 14.572 / 14.080 | 0.066 / 0.081 | 4,804,864 / 4,804,864 |
| synthetic-5000-layers-grad | 48 | 兜底 | 15.288 / 15.654 | 15.848 / 15.726 | -0.560 / -0.072 | 82,944 / 82,944 |
| synthetic-5000-layers-grad | 200 | 兜底 | 15.570 / 15.681 | 15.699 / 15.719 | -0.129 / -0.038 | 1,327,104 / 1,327,104 |
| synthetic-5000-layers-grad | full | 兜底 | 16.192 / 16.068 | 16.000 / 16.057 | 0.192 / 0.011 | 4,804,864 / 4,804,864 |
| synthetic-5000-plain | 48 | 兜底 | 13.459 / 13.388 | 13.525 / 13.501 | -0.066 / -0.113 | 82,944 / 82,944 |
| synthetic-5000-plain | 200 | 兜底 | 13.338 / 13.196 | 13.362 / 13.322 | -0.024 / -0.126 | 1,327,104 / 1,327,104 |
| synthetic-5000-plain | full | 兜底 | 13.435 / 13.433 | 13.457 / 13.365 | -0.022 / 0.068 | 4,804,864 / 4,804,864 |

### 补充的第一轮样本尺寸

| 样本 | 尺寸 | 缓存 ms | 收益 ms | 纹理 B |
| --- | --- | --- | --- | --- |
| complex-1 | 16 | 2.066 | 0.374 | 11,664 |
| complex-2 | 16 | 1.954 | 0.476 | 11,664 |
| complex-3 | 16 | 1.805 | 0.383 | 11,664 |
| complex-4 | 16 | 1.937 | 0.300 | 11,664 |
| complex-5 | 16 | 2.117 | 0.138 | 11,664 |
| complex-6 | 16 | 2.176 | -0.070 | 11,664 |
| mdi-0 | 16 | 2.113 | 0.033 | 11,664 |
| mdi-12 | 16 | 2.158 | -0.154 | 11,664 |
| mdi-236 | 16 | 2.117 | -0.153 | 11,664 |
| mdi-500 | 16 | 2.034 | 0.108 | 11,664 |
| mdi-789 | 16 | 1.973 | 0.166 | 11,664 |
| mdi-999 | 16 | 2.122 | -0.089 | 11,664 |
| synthetic-1000-blur-grad | 16 | 6.409 | 0.050 | 11,664 |
| synthetic-1000-blur-layers | 16 | 6.313 | -0.076 | 11,664 |
| synthetic-1000-layers-grad | 16 | 5.724 | -0.134 | 11,664 |
| synthetic-1000-plain | 16 | 5.641 | -0.111 | 11,664 |
| synthetic-200-blur | 16 | 4.471 | 0.100 | 11,664 |
| synthetic-200-blur-grad | 16 | 4.035 | -0.058 | 11,664 |
| synthetic-200-blur-layers | 16 | 4.472 | -0.060 | 11,664 |
| synthetic-200-blur-layers-grad | 16 | 4.863 | -0.024 | 11,664 |
| synthetic-200-grad | 16 | 3.743 | 0.198 | 11,664 |
| synthetic-200-layers | 16 | 4.291 | 0.002 | 11,664 |
| synthetic-200-layers-grad | 16 | 4.298 | 0.070 | 11,664 |
| synthetic-200-plain | 16 | 2.917 | 0.131 | 11,664 |
| synthetic-50-blur-grad | 16 | 3.832 | 0.366 | 11,664 |
| synthetic-50-blur-layers | 16 | 3.348 | 0.242 | 11,664 |
| synthetic-50-layers-grad | 16 | 3.761 | -0.204 | 11,664 |
| synthetic-50-plain | 16 | 2.483 | -0.013 | 11,664 |
| synthetic-5000-blur-grad | 16 | 15.863 | -0.073 | 11,664 |
| synthetic-5000-blur-layers | 16 | 13.961 | -0.093 | 11,664 |
| synthetic-5000-layers-grad | 16 | 15.665 | -0.100 | 11,664 |
| synthetic-5000-plain | 16 | 13.446 | -0.032 | 11,664 |

## 分层抽样清单

覆盖 20 个类别、160 个分层。抽到的原生场景中，遮罩 11、模糊 14、图案 7、内嵌位图 12 张。单文件最多 94,501 条原生路径，最多 279 个源文字节点。

| 类别 | 全集 | 拟合 | 留出 |
| --- | --- | --- | --- |
| arms | 22 | 7 | 3 |
| chart | 21 | 8 | 2 |
| clipart | 182 | 25 | 13 |
| diagram | 22 | 8 | 2 |
| effect | 28 | 5 | 6 |
| emoji | 14 | 3 | 1 |
| featured | 32 | 8 | 4 |
| flag | 25 | 5 | 1 |
| game | 32 | 4 | 2 |
| humaaans | 15 | 4 | 1 |
| illustration | 42 | 9 | 5 |
| logo | 15 | 4 | 2 |
| map | 59 | 9 | 4 |
| mid | 26 | 5 | 1 |
| pattern | 67 | 14 | 6 |
| peeps | 10 | 2 | 0 |
| small | 29 | 6 | 3 |
| tech | 16 | 4 | 0 |
| text | 22 | 6 | 1 |
| undraw | 35 | 4 | 3 |

| 编号 | 划分 | 类别 | 体积档 | 主要特性 | 文件 | 来源 / 许可证 |
| --- | --- | --- | --- | --- | --- | --- |
| web-002 | 留出 | arms | ≥256KiB | dense | arms__Bexhill-coat-of-arms.svg | [来源](https://commons.wikimedia.org/wiki/File:Bexhill_coat_of_arms.svg) / CC0 |
| web-004 | 拟合 | arms | ≥256KiB | text | arms__COA-Gavriil-Ivanovich-Golovkin-White-Eag.svg | [来源](https://commons.wikimedia.org/wiki/File:COA_Gavriil_Ivanovich_Golovkin_White_Eagle_Order_shield.svg) / CC BY-SA 4.0 |
| web-005 | 拟合 | arms | ≥256KiB | blur | arms__COA-Holstein-Gottorp-Romanov-chivalric.svg | [来源](https://commons.wikimedia.org/wiki/File:COA_Holstein-Gottorp-Romanov_chivalric.svg) / CC BY-SA 4.0 |
| web-007 | 拟合 | arms | ≥256KiB | pattern | arms__Coat-of-Arms-of-Brooksbank-baronets.svg | [来源](https://commons.wikimedia.org/wiki/File:Coat_of_Arms_of_Brooksbank_baronets.svg) / CC BY-SA 4.0 |
| web-010 | 拟合 | arms | ≥256KiB | mask | arms__Coat-of-arms-of-Edmund-Hillary.svg | [来源](https://commons.wikimedia.org/wiki/File:Coat_of_arms_of_Edmund_Hillary.svg) / CC BY-SA 4.0 |
| web-013 | 留出 | arms | 32–<256KiB | dense | arms__Coat-of-arms-of-house-Holstein-Gottorp-R.svg | [来源](https://commons.wikimedia.org/wiki/File:Coat_of_arms_of_house_Holstein-Gottorp-Romanov.svg) / CC BY-SA 4.0 |
| web-016 | 留出 | arms | 32–<256KiB | plain | arms__EBBreslauCOA.svg | [来源](https://commons.wikimedia.org/wiki/File:EBBreslauCOA.svg) / CC BY-SA 4.0 |
| web-017 | 拟合 | arms | ≥256KiB | bitmap | arms__Finale-Pia-Stemma.svg | [来源](https://commons.wikimedia.org/wiki/File:Finale_Pia-Stemma.svg) / CC BY-SA 4.0 |
| web-018 | 拟合 | arms | 32–<256KiB | text | arms__Friedrich-von-Schreiber-Wappen.svg | [来源](https://commons.wikimedia.org/wiki/File:Friedrich_von_Schreiber_Wappen.svg) / CC BY-SA 4.0 |
| web-022 | 拟合 | arms | 32–<256KiB | paint | arms__Roning.svg | [来源](https://commons.wikimedia.org/wiki/File:Roning.svg) / CC0 |
| web-025 | 拟合 | chart | 32–<256KiB | paint | chart__Cycle-shapes-in-neighbor-graph-positive-.svg | [来源](https://commons.wikimedia.org/wiki/File:Cycle_shapes_in_neighbor_graph;_positive;_Baghdad_6.svg) / CC BY 4.0 |
| web-027 | 拟合 | chart | ≥256KiB | text | chart__DJIA-historical-graph-sr.svg | [来源](https://commons.wikimedia.org/wiki/File:DJIA_historical_graph_sr.svg) / CC BY-SA 3.0 |
| web-028 | 拟合 | chart | 32–<256KiB | bitmap | chart__Force-graph-tactile-Cherry-ML.svg | [来源](https://commons.wikimedia.org/wiki/File:Force_graph--tactile--Cherry_ML.svg) / Public domain |
| web-029 | 拟合 | chart | ≥256KiB | dense | chart__Metzenseifen-Timeline.svg | [来源](https://commons.wikimedia.org/wiki/File:Metzenseifen_Timeline.svg) / CC BY-SA 3.0 |
| web-030 | 拟合 | chart | 32–<256KiB | dense | chart__NUMBER-OF-PEOPLE-UNDERNOURISHED-BY-REGIO.svg | [来源](https://commons.wikimedia.org/wiki/File:NUMBER_OF_PEOPLE_UNDERNOURISHED_BY_REGION.svg) / CC BY-SA 3.0 igo |
| web-031 | 拟合 | chart | 32–<256KiB | plain | chart__Nonisomorphic-medial-graph-example.svg | [来源](https://commons.wikimedia.org/wiki/File:Nonisomorphic_medial_graph_example.svg) / CC0 |
| web-034 | 拟合 | chart | ≥256KiB | paint | chart__Symmetric-group-4-Cayley-graph-1-2-6-3D.svg | [来源](https://commons.wikimedia.org/wiki/File:Symmetric_group_4;_Cayley_graph_1,2,6_(3D).svg) / Public domain |
| web-036 | 留出 | chart | ≥256KiB | blur | chart__Symmetric-group-4-cycle-graph-16x16.svg | [来源](https://commons.wikimedia.org/wiki/File:Symmetric_group_4;_cycle_graph;_16x16.svg) / CC BY 3.0 |
| web-039 | 拟合 | chart | 32–<256KiB | pattern | chart__Timeline-of-daily-new-confirmed-COVID-19.svg | [来源](https://commons.wikimedia.org/wiki/File:Timeline_of_daily_new_confirmed_COVID-19_deaths_worldwide.svg) / CC BY 4.0 |
| web-040 | 留出 | chart | 32–<256KiB | text | chart__Timeline-of-the-main-schisms-from-the-Se.svg | [来源](https://commons.wikimedia.org/wiki/File:Timeline_of_the_main_schisms_from_the_Serbian_Orthodox_Church_(second_quarter_of_the_19th_century_to_2022).svg) / CC BY-SA 4.0 |
| web-046 | 拟合 | clipart | 32–<256KiB | mask | clipart__2017-cloud-technology.svg | [来源](https://freesvg.org/2017-cloud-technology) / CC0/Public Domain (freesvg.org) |
| web-048 | 拟合 | clipart | 32–<256KiB | plain | clipart__a-young-man-from-ancient-times.svg | [来源](https://freesvg.org/a-young-man-from-ancient-times) / CC0/Public Domain (freesvg.org) |
| web-050 | 拟合 | clipart | ≥256KiB | bitmap | clipart__arduino-generic-uno-r3-microcontroller.svg | [来源](https://freesvg.org/arduino-generic-uno-r3-microcontroller) / CC0/Public Domain (freesvg.org) |
| web-052 | 拟合 | clipart | ≥256KiB | dense | clipart__arms-of-sir-dafydd-gam.svg | [来源](https://freesvg.org/arms-of-sir-dafydd-gam) / CC0/Public Domain (freesvg.org) |
| web-053 | 拟合 | clipart | ≥256KiB | dense | clipart__australian-wildlife-engraving-with-kanga.svg | [来源](https://freesvg.org/australian-wildlife-engraving-with-kangaroo) / CC0/Public Domain (freesvg.org) |
| web-061 | 留出 | clipart | 32–<256KiB | plain | clipart__black-and-white-silhouette-of-a-nanny-pu.svg | [来源](https://freesvg.org/black-and-white-silhouette-of-a-nanny-pushing-a-baby-carriage) / CC0/Public Domain (freesvg.org) |
| web-062 | 拟合 | clipart | 32–<256KiB | plain | clipart__black-car-1637798726.svg | [来源](https://freesvg.org/black-car-1637798726) / CC0/Public Domain (freesvg.org) |
| web-063 | 留出 | clipart | 32–<256KiB | paint | clipart__blonde-man-ii.svg | [来源](https://freesvg.org/blonde-man-ii) / CC0/Public Domain (freesvg.org) |
| web-065 | 留出 | clipart | 32–<256KiB | plain | clipart__boat-24d.svg | [来源](https://freesvg.org/boat-24d) / CC0/Public Domain (freesvg.org) |
| web-068 | 拟合 | clipart | 32–<256KiB | dense | clipart__boys-white-block-letters-on-black-square.svg | [来源](https://freesvg.org/boys-white-block-letters-on-black-square) / CC0/Public Domain (freesvg.org) |
| web-070 | 拟合 | clipart | 32–<256KiB | plain | clipart__cartoon-animal-numbers-set.svg | [来源](https://freesvg.org/cartoon-animal-numbers-set) / CC0/Public Domain (freesvg.org) |
| web-071 | 留出 | clipart | 32–<256KiB | dense | clipart__cartoon-crocodile-with-open-mouth.svg | [来源](https://freesvg.org/cartoon-crocodile-with-open-mouth) / CC0/Public Domain (freesvg.org) |
| web-078 | 拟合 | clipart | ≥256KiB | text | clipart__city-frame.svg | [来源](https://freesvg.org/city-frame) / CC0/Public Domain (freesvg.org) |
| web-079 | 拟合 | clipart | ≥256KiB | mask | clipart__clip-art-free-vector-pack.svg | [来源](https://freesvg.org/clip-art-free-vector-pack) / CC0/Public Domain (freesvg.org) |
| web-082 | 留出 | clipart | ≥256KiB | dense | clipart__coat-of-arms-of-liberia.svg | [来源](https://freesvg.org/coat-of-arms-of-liberia) / CC0/Public Domain (freesvg.org) |
| web-085 | 留出 | clipart | ≥256KiB | dense | clipart__cockatrice-mythological-creature.svg | [来源](https://freesvg.org/cockatrice-mythological-creature) / CC0/Public Domain (freesvg.org) |
| web-086 | 拟合 | clipart | <4KiB | plain | clipart__computer-screen-and-smartphone.svg | [来源](https://freesvg.org/computer-screen-and-smartphone) / CC0/Public Domain (freesvg.org) |
| web-087 | 拟合 | clipart | <4KiB | text | clipart__cork-sign-irish.svg | [来源](https://freesvg.org/cork-sign-irish) / CC0/Public Domain (freesvg.org) |
| web-100 | 拟合 | clipart | ≥256KiB | paint | clipart__escudo-nacional-de-costa-rica-costa-rica.svg | [来源](https://freesvg.org/escudo-nacional-de-costa-rica-costa-rican-national-coat-of-arms) / CC0/Public Domain (freesvg.org) |
| web-101 | 留出 | clipart | ≥256KiB | blur | clipart__esp32-devkitc.svg | [来源](https://freesvg.org/esp32-devkitc) / CC0/Public Domain (freesvg.org) |
| web-106 | 留出 | clipart | 4–<32KiB | paint | clipart__flying-green-dragon-1685518084.svg | [来源](https://freesvg.org/flying-green-dragon-1685518084) / CC0/Public Domain (freesvg.org) |
| web-117 | 拟合 | clipart | 32–<256KiB | plain | clipart__halved-orange-fruit-cross-section.svg | [来源](https://freesvg.org/halved-orange-fruit-cross-section) / CC0/Public Domain (freesvg.org) |
| web-122 | 拟合 | clipart | <4KiB | blur | clipart__home-price-vector-graphics.svg | [来源](https://freesvg.org/home-price-vector-graphics) / CC0/Public Domain (freesvg.org) |
| web-123 | 留出 | clipart | 32–<256KiB | blur | clipart__honey-jar-with-two-red-apples.svg | [来源](https://freesvg.org/honey-jar-with-two-red-apples) / CC0/Public Domain (freesvg.org) |
| web-126 | 留出 | clipart | 32–<256KiB | pattern | clipart__house-icon-silhouette-1791192408.svg | [来源](https://freesvg.org/house-icon-silhouette-1791192408) / CC0/Public Domain (freesvg.org) |
| web-150 | 拟合 | clipart | ≥256KiB | dense | clipart__old-stone-church-with-bell-tower-engravi.svg | [来源](https://freesvg.org/old-stone-church-with-bell-tower-engraving) / CC0/Public Domain (freesvg.org) |
| web-154 | 拟合 | clipart | 32–<256KiB | plain | clipart__pear-on-a-branch-silhouette.svg | [来源](https://freesvg.org/pear-on-a-branch-silhouette) / CC0/Public Domain (freesvg.org) |
| web-167 | 拟合 | clipart | ≥256KiB | dense | clipart__sailboat-on-the-sea.svg | [来源](https://freesvg.org/sailboat-on-the-sea) / CC0/Public Domain (freesvg.org) |
| web-176 | 留出 | clipart | 32–<256KiB | text | clipart__smartphone-keyboard.svg | [来源](https://freesvg.org/smartphone-keyboard) / CC0/Public Domain (freesvg.org) |
| web-178 | 拟合 | clipart | 32–<256KiB | plain | clipart__standing-rooster-with-curved-tail-outlin.svg | [来源](https://freesvg.org/standing-rooster-with-curved-tail-outline) / CC0/Public Domain (freesvg.org) |
| web-184 | 拟合 | clipart | 4–<32KiB | plain | clipart__stopwatch-silhouette.svg | [来源](https://freesvg.org/stopwatch-silhouette) / CC0/Public Domain (freesvg.org) |
| web-197 | 拟合 | clipart | 32–<256KiB | dense | clipart__tree41.svg | [来源](https://freesvg.org/tree41) / CC0/Public Domain (freesvg.org) |
| web-199 | 拟合 | clipart | 32–<256KiB | dense | clipart__tree65.svg | [来源](https://freesvg.org/tree65) / CC0/Public Domain (freesvg.org) |
| web-202 | 拟合 | clipart | ≥256KiB | dense | clipart__tree72.svg | [来源](https://freesvg.org/tree72) / CC0/Public Domain (freesvg.org) |
| web-206 | 拟合 | clipart | ≥256KiB | dense | clipart__vintage-caricature-of-a-man-in-a-suit.svg | [来源](https://freesvg.org/vintage-caricature-of-a-man-in-a-suit) / CC0/Public Domain (freesvg.org) |
| web-207 | 拟合 | clipart | ≥256KiB | dense | clipart__vintage-engraving-of-men-by-the-sea.svg | [来源](https://freesvg.org/vintage-engraving-of-men-by-the-sea) / CC0/Public Domain (freesvg.org) |
| web-223 | 留出 | clipart | 32–<256KiB | plain | clipart__young-man-face-with-parted-hair-line-art.svg | [来源](https://freesvg.org/young-man-face-with-parted-hair-line-art) / CC0/Public Domain (freesvg.org) |
| web-225 | 留出 | clipart | ≥256KiB | dense | clipart__young-shepherd-with-staff-and-sheep-engr.svg | [来源](https://freesvg.org/young-shepherd-with-staff-and-sheep-engraving) / CC0/Public Domain (freesvg.org) |
| web-226 | 拟合 | diagram | ≥256KiB | bitmap | diagram__ALADI-Diagram-pt.svg | [来源](https://commons.wikimedia.org/wiki/File:ALADI_Diagram-pt.svg) / CC BY-SA 3.0 |
| web-227 | 拟合 | diagram | 32–<256KiB | plain | diagram__Blueprint-Barnstar.svg | [来源](https://commons.wikimedia.org/wiki/File:Blueprint_Barnstar.svg) / CC BY-SA 4.0 |
| web-229 | 拟合 | diagram | 32–<256KiB | text | diagram__DART-UML-DART-2011-2013-RAW.svg | [来源](https://commons.wikimedia.org/wiki/File:DART_UML_DART_2011_2013_RAW.svg) / CC BY 3.0 |
| web-233 | 拟合 | diagram | 32–<256KiB | paint | diagram__Felt-Strip-for-Master-CU-Architecture.svg | [来源](https://commons.wikimedia.org/wiki/File:Felt_Strip_for_Master_CU_(Architecture).svg) / Public domain |
| web-234 | 拟合 | diagram | ≥256KiB | text | diagram__Haber-Bosch-En.svg | [来源](https://commons.wikimedia.org/wiki/File:Haber-Bosch-En.svg) / CC BY-SA 4.0 |
| web-237 | 留出 | diagram | ≥256KiB | dense | diagram__Platform-tomb.svg | [来源](https://commons.wikimedia.org/wiki/File:Platform_tomb.svg) / CC0 |
| web-238 | 留出 | diagram | 32–<256KiB | dense | diagram__Reactor-Pattern-UML-2-Component-Diagram.svg | [来源](https://commons.wikimedia.org/wiki/File:Reactor_Pattern_-_UML_2_Component_Diagram.svg) / CC BY-SA 4.0 |
| web-241 | 拟合 | diagram | ≥256KiB | blur | diagram__Schematic-diagram-of-the-human-eye-tr.svg | [来源](https://commons.wikimedia.org/wiki/File:Schematic_diagram_of_the_human_eye_tr.svg) / CC BY-SA 3.0 |
| web-242 | 拟合 | diagram | ≥256KiB | pattern | diagram__Schematic-of-the-composting-chamberCS.svg | [来源](https://commons.wikimedia.org/wiki/File:Schematic_of_the_composting_chamberCS.svg) / CC BY-SA 4.0 |
| web-246 | 拟合 | diagram | 32–<256KiB | bitmap | diagram__Wikimedia-evolving-architecture-expanded.svg | [来源](https://commons.wikimedia.org/wiki/File:Wikimedia_evolving_architecture_expanded_components.svg) / CC BY-SA 4.0 |
| web-248 | 留出 | effect | 32–<256KiB | bitmap | effect__2021-Uzbek-presidential-election-logo.svg | [来源](https://commons.wikimedia.org/wiki/File:2021_Uzbek_presidential_election_logo.svg) / Public domain |
| web-250 | 拟合 | effect | 32–<256KiB | paint | effect__4a-PubChemLiteEXPOSOMICS-slight-blue-gra.svg | [来源](https://commons.wikimedia.org/wiki/File:4a_PubChemLiteEXPOSOMICS_slight_blue_gradient_grass_logo.svg) / Public domain |
| web-251 | 留出 | effect | ≥256KiB | bitmap | effect__Bremen-in-Germany-relief-shade.svg | [来源](https://commons.wikimedia.org/wiki/File:Bremen_in_Germany_(relief)_(shade).svg) / CC BY-SA 3.0 |
| web-253 | 留出 | effect | ≥256KiB | dense | effect__DC-Shadow-House-2024.svg | [来源](https://commons.wikimedia.org/wiki/File:DC_Shadow_House_2024.svg) / CC BY-SA 4.0 |
| web-255 | 留出 | effect | 32–<256KiB | dense | effect__DC-Shadow-Senator-Map-2012.svg | [来源](https://commons.wikimedia.org/wiki/File:DC_Shadow_Senator_Map_2012.svg) / CC BY-SA 4.0 |
| web-260 | 拟合 | effect | ≥256KiB | blur | effect__Inkscape-0-48-2-with-Red-Gallardo.svg | [来源](https://commons.wikimedia.org/wiki/File:Inkscape_0.48.2_with_Red_Gallardo.svg) / GPL |
| web-264 | 拟合 | effect | 32–<256KiB | blur | effect__Oxygen480-apps-kformula.svg | [来源](https://commons.wikimedia.org/wiki/File:Oxygen480-apps-kformula.svg) / LGPL |
| web-267 | 拟合 | effect | ≥256KiB | text | effect__Serial-endosymbiosis.svg | [来源](https://commons.wikimedia.org/wiki/File:Serial_endosymbiosis.svg) / CC BY-SA 3.0 |
| web-269 | 留出 | effect | 32–<256KiB | mask | effect__Shadow-logo.svg | [来源](https://commons.wikimedia.org/wiki/File:Shadow-logo.svg) / Public domain |
| web-271 | 留出 | effect | 32–<256KiB | plain | effect__Star-Wars-Rise-of-the-Resistance-logo.svg | [来源](https://commons.wikimedia.org/wiki/File:Star_Wars_%E2%80%93_Rise_of_the_Resistance_logo.svg) / Public domain |
| web-274 | 拟合 | effect | 32–<256KiB | text | effect__Window-function-and-frequency-response-C.svg | [来源](https://commons.wikimedia.org/wiki/File:Window_function_and_frequency_response_-_Confined_Gaussian_(sigma_t_%3D_0.1N).svg) / CC0 |
| web-277 | 拟合 | emoji | 4–<32KiB | paint | emoji__noto-emoji-2D-svg-emoji-u1f469-200d-2708.svg | [来源](https://github.com/googlefonts/noto-emoji/blob/main/2D/svg/emoji_u1f469_200d_2708.svg) / OFL-1.1/Apache-2.0 |
| web-281 | 留出 | emoji | 32–<256KiB | paint | emoji__noto-emoji-2D-svg-emoji-u23ed.svg | [来源](https://github.com/googlefonts/noto-emoji/blob/main/2D/svg/emoji_u23ed.svg) / OFL-1.1/Apache-2.0 |
| web-282 | 拟合 | emoji | 4–<32KiB | plain | emoji__openmoji-black-svg-1F468-1F3FD-200D-1F69.svg | [来源](https://github.com/hfg-gmuend/openmoji/blob/master/black/svg/1F468-1F3FD-200D-1F692.svg) / CC-BY-SA-4.0 |
| web-288 | 拟合 | emoji | 32–<256KiB | plain | emoji__openmoji-src-extras-openmoji-healthcare-.svg | [来源](https://github.com/hfg-gmuend/openmoji/blob/master/src/extras-openmoji/healthcare/E315.svg) / CC-BY-SA-4.0 |
| web-293 | 留出 | featured | 32–<256KiB | bitmap | featured__Climate-change-numbered.svg | [来源](https://commons.wikimedia.org/wiki/File:Climate_change_numbered.svg) / CC BY-SA 4.0 |
| web-296 | 拟合 | featured | ≥256KiB | bitmap | featured__Corfu-topographic-map-en.svg | [来源](https://commons.wikimedia.org/wiki/File:Corfu_topographic_map-en.svg) / CC BY-SA 3.0 |
| web-299 | 拟合 | featured | 32–<256KiB | plain | featured__Escut-de-Siurana.svg | [来源](https://commons.wikimedia.org/wiki/File:Escut_de_Siurana.svg) / CC BY-SA 3.0 |
| web-300 | 拟合 | featured | 32–<256KiB | pattern | featured__Fortepian-mechanizm-wiede-ski.svg | [来源](https://commons.wikimedia.org/wiki/File:Fortepian_-_mechanizm_wiede%C5%84ski.svg) / CC BY-SA 3.0 |
| web-302 | 拟合 | featured | 32–<256KiB | blur | featured__HMS-Belfast-Boiler-diagram.svg | [来源](https://commons.wikimedia.org/wiki/File:HMS_Belfast_-_Boiler_diagram.svg) / CC BY-SA 4.0 |
| web-304 | 拟合 | featured | 32–<256KiB | paint | featured__Human-skull-side-bones.svg | [来源](https://commons.wikimedia.org/wiki/File:Human_skull_side_bones.svg) / Public domain |
| web-307 | 留出 | featured | ≥256KiB | blur | featured__Jupiter-diagram.svg | [来源](https://commons.wikimedia.org/wiki/File:Jupiter_diagram.svg) / CC BY-SA 3.0 |
| web-309 | 留出 | featured | ≥256KiB | text | featured__Marine-sextant.svg | [来源](https://commons.wikimedia.org/wiki/File:Marine_sextant.svg) / CC BY 2.5 |
| web-310 | 拟合 | featured | ≥256KiB | dense | featured__Mountain-systems-of-Turkey.svg | [来源](https://commons.wikimedia.org/wiki/File:Mountain_systems_of_Turkey.svg) / CC BY-SA 4.0 |
| web-316 | 拟合 | featured | ≥256KiB | paint | featured__Rotring-Rapidograph-0-35-mm-Technical-Pe.svg | [来源](https://commons.wikimedia.org/wiki/File:Rotring_Rapidograph_0.35_mm_Technical_Pen.svg) / CC BY-SA 3.0 |
| web-318 | 留出 | featured | 32–<256KiB | text | featured__Scorpena-class-SSK-Kalvari-variant.svg | [来源](https://commons.wikimedia.org/wiki/File:Scorpena_class_SSK_Kalvari_variant.svg) / CC BY-SA 4.0 |
| web-321 | 拟合 | featured | 32–<256KiB | mask | featured__ZenFone-6-Mockup.svg | [来源](https://commons.wikimedia.org/wiki/File:ZenFone_6_Mockup.svg) / CC BY-SA 4.0 |
| web-325 | 拟合 | flag | 32–<256KiB | paint | flag__flag-icons-flags-1x1-bz.svg | [来源](https://github.com/lipis/flag-icons/blob/main/flags/1x1/bz.svg) / MIT |
| web-330 | 拟合 | flag | 4–<32KiB | paint | flag__flag-icons-flags-1x1-gt.svg | [来源](https://github.com/lipis/flag-icons/blob/main/flags/1x1/gt.svg) / MIT |
| web-334 | 拟合 | flag | 4–<32KiB | plain | flag__flag-icons-flags-1x1-sh-ta.svg | [来源](https://github.com/lipis/flag-icons/blob/main/flags/1x1/sh-ta.svg) / MIT |
| web-338 | 拟合 | flag | 32–<256KiB | plain | flag__flag-icons-flags-4x3-es.svg | [来源](https://github.com/lipis/flag-icons/blob/main/flags/4x3/es.svg) / MIT |
| web-341 | 拟合 | flag | 32–<256KiB | dense | flag__flag-icons-flags-4x3-rs.svg | [来源](https://github.com/lipis/flag-icons/blob/main/flags/4x3/rs.svg) / MIT |
| web-344 | 留出 | flag | 4–<32KiB | plain | flag__flag-icons-flags-4x3-sh-ta.svg | [来源](https://github.com/lipis/flag-icons/blob/main/flags/4x3/sh-ta.svg) / MIT |
| web-347 | 拟合 | game | 32–<256KiB | dense | game__Chamfer-triangular-tiling.svg | [来源](https://commons.wikimedia.org/wiki/File:Chamfer_triangular_tiling.svg) / CC BY-SA 4.0 |
| web-357 | 拟合 | game | 32–<256KiB | bitmap | game__WEP-Portugal-tile-logo.svg | [来源](https://commons.wikimedia.org/wiki/File:WEP_Portugal_tile_logo.svg) / CC BY-SA 4.0 |
| web-361 | 拟合 | game | 32–<256KiB | plain | game__kenney-Art-5190-files-Boardgame-pack-480-2.svg | [来源](https://github.com/iwenzhou/kenney/blob/master/Art (5190 files)/Boardgame pack (480 assets)/Vector/piecesBlue.svg) / CC0-1.0 |
| web-362 | 留出 | game | 32–<256KiB | plain | game__kenney-Art-5190-files-Boardgame-pack-480-3.svg | [来源](https://github.com/iwenzhou/kenney/blob/master/Art (5190 files)/Boardgame pack (480 assets)/Vector/piecesPurple.svg) / CC0-1.0 |
| web-366 | 留出 | game | 32–<256KiB | paint | game__kenney-Art-5190-files-Hexagon-assets-170.svg | [来源](https://github.com/iwenzhou/kenney/blob/master/Art (5190 files)/Hexagon assets (170 assets)/Base pack (90 assets)/Vector/hexagonTiles_vector.svg) / CC0-1.0 |
| web-377 | 拟合 | game | ≥256KiB | dense | game__kenney-Art-5190-files-RPG-pack-230-asset.svg | [来源](https://github.com/iwenzhou/kenney/blob/master/Art (5190 files)/RPG pack (230 assets)/Vector/RPGpack_vector.svg) / CC0-1.0 |
| web-382 | 拟合 | humaaans | 4–<32KiB | plain | humaaans__humaaans-Flat-Assets-Humaaans-standing-1.svg | [来源](https://github.com/Calinou/humaaans/blob/master/Flat Assets/Humaaans/standing-10.svg) / CC-BY-4.0 |
| web-384 | 留出 | humaaans | 4–<32KiB | plain | humaaans__humaaans-Flat-Assets-Humaaans-standing-1-3.svg | [来源](https://github.com/Calinou/humaaans/blob/master/Flat Assets/Humaaans/standing-14.svg) / CC-BY-4.0 |
| web-389 | 拟合 | humaaans | 4–<32KiB | mask | humaaans__humaaans-Flat-Assets-Humaaans-standing-7.svg | [来源](https://github.com/Calinou/humaaans/blob/master/Flat Assets/Humaaans/standing-7.svg) / CC-BY-4.0 |
| web-392 | 拟合 | humaaans | 4–<32KiB | paint | humaaans__humaaans-Flat-Assets-Single-Pieces-Scene.svg | [来源](https://github.com/Calinou/humaaans/blob/master/Flat Assets/Single Pieces/Scene/Home.svg) / CC-BY-4.0 |
| web-393 | 拟合 | humaaans | 32–<256KiB | paint | humaaans__humaaans-Flat-Assets-Single-Pieces-Scene-2.svg | [来源](https://github.com/Calinou/humaaans/blob/master/Flat Assets/Single Pieces/Scene/Whiteboard.svg) / CC-BY-4.0 |
| web-394 | 拟合 | illustration | 32–<256KiB | bitmap | illustration__A-illustration-of-Dancheong.svg | [来源](https://commons.wikimedia.org/wiki/File:A_illustration_of_Dancheong.svg) / CC BY-SA 4.0 |
| web-399 | 拟合 | illustration | 32–<256KiB | pattern | illustration__Blason-Ch-teau-Arnoux-Saint-Auban.svg | [来源](https://commons.wikimedia.org/wiki/File:Blason_Ch%C3%A2teau-Arnoux-Saint-Auban.svg) / CC BY-SA 3.0 |
| web-401 | 留出 | illustration | 32–<256KiB | paint | illustration__Chess-history-illustration-HY.svg | [来源](https://commons.wikimedia.org/wiki/File:Chess_history_illustration_(HY).svg) / CC BY-SA 4.0 |
| web-402 | 拟合 | illustration | 32–<256KiB | dense | illustration__City-NIH-BioArt-825-795638.svg | [来源](https://commons.wikimedia.org/wiki/File:City_(NIH_BioArt_825_-_795638).svg) / Public domain |
| web-403 | 留出 | illustration | ≥256KiB | blur | illustration__City-after-earthquake.svg | [来源](https://commons.wikimedia.org/wiki/File:City_after_earthquake.svg) / CC0 |
| web-405 | 拟合 | illustration | ≥256KiB | dense | illustration__Coa-Illustration-Elements-Animal-Pelican.svg | [来源](https://commons.wikimedia.org/wiki/File:Coa_Illustration_Elements_Animal_Pelican_in_her_Piety.svg) / Public domain |
| web-406 | 拟合 | illustration | 32–<256KiB | blur | illustration__DC-10-30-seat-configuration-chart.svg | [来源](https://commons.wikimedia.org/wiki/File:DC-10-30_seat_configuration_chart.svg) / CC BY-SA 4.0 |
| web-419 | 留出 | illustration | 32–<256KiB | plain | illustration__Kern-County-California-Incorporated-and-.svg | [来源](https://commons.wikimedia.org/wiki/File:Kern_County_California_Incorporated_and_Unincorporated_areas_Pine_Mountain_Club_Highlighted.svg) / CC BY-SA 3.0 |
| web-423 | 留出 | illustration | ≥256KiB | dense | illustration__Northern-California-Coastal-Forests-map.svg | [来源](https://commons.wikimedia.org/wiki/File:Northern_California_Coastal_Forests_map.svg) / CC BY-SA 3.0 |
| web-424 | 拟合 | illustration | 32–<256KiB | text | illustration__Pine-needle-plaiting.svg | [来源](https://commons.wikimedia.org/wiki/File:Pine_needle_plaiting.svg) / CC BY-SA 4.0 |
| web-430 | 拟合 | illustration | ≥256KiB | text | illustration__VIIC-uboat-shaded.svg | [来源](https://commons.wikimedia.org/wiki/File:VIIC_uboat_shaded.svg) / CC BY-SA 4.0 |
| web-432 | 拟合 | illustration | ≥256KiB | bitmap | illustration__Welwyn-Garden-City-rail-crash-1935-illus.svg | [来源](https://commons.wikimedia.org/wiki/File:Welwyn_Garden_City_rail_crash_1935_%E2%80%93_illustration_1.svg) / Public domain |
| web-434 | 拟合 | illustration | ≥256KiB | plain | illustration__Wikipe-tan-in-navy-uniform.svg | [来源](https://commons.wikimedia.org/wiki/File:Wikipe-tan_in_navy_uniform.svg) / LGPL |
| web-435 | 留出 | illustration | ≥256KiB | pattern | illustration__World-Trade-Center-Building-Design-with-.svg | [来源](https://commons.wikimedia.org/wiki/File:World_Trade_Center_Building_Design_with_Floor_and_Elevator_Arrangement_m.svg) / Public domain |
| web-436 | 拟合 | logo | 32–<256KiB | plain | logo__logos-logos-chalk.svg | [来源](https://github.com/gilbarbara/logos/blob/main/logos/chalk.svg) / CC0-1.0 |
| web-437 | 留出 | logo | 4–<32KiB | plain | logo__logos-logos-cloudacademy.svg | [来源](https://github.com/gilbarbara/logos/blob/main/logos/cloudacademy.svg) / CC0-1.0 |
| web-438 | 拟合 | logo | 32–<256KiB | paint | logo__logos-logos-ember-tomster.svg | [来源](https://github.com/gilbarbara/logos/blob/main/logos/ember-tomster.svg) / CC0-1.0 |
| web-442 | 拟合 | logo | ≥256KiB | mask | logo__logos-logos-kimi-icon.svg | [来源](https://github.com/gilbarbara/logos/blob/main/logos/kimi-icon.svg) / CC0-1.0 |
| web-447 | 拟合 | logo | 4–<32KiB | paint | logo__logos-logos-redux-observable.svg | [来源](https://github.com/gilbarbara/logos/blob/main/logos/redux-observable.svg) / CC0-1.0 |
| web-448 | 留出 | logo | 32–<256KiB | blur | logo__logos-logos-safari.svg | [来源](https://github.com/gilbarbara/logos/blob/main/logos/safari.svg) / CC0-1.0 |
| web-455 | 拟合 | map | ≥256KiB | dense | map__Bari-Quartiere-San-Paolo-locator-map.svg | [来源](https://commons.wikimedia.org/wiki/File:Bari_Quartiere_San_Paolo_locator_map.svg) / CC BY-SA 4.0 |
| web-460 | 拟合 | map | ≥256KiB | dense | map__Derbyshire-UK-parish-map-highlighting-Oc.svg | [来源](https://commons.wikimedia.org/wiki/File:Derbyshire_UK_parish_map_highlighting_Ockbrook_and_Borrowash.svg) / CC BY-SA 3.0 |
| web-462 | 拟合 | map | 32–<256KiB | dense | map__EPCI-Pays-de-Spincourt.svg | [来源](https://commons.wikimedia.org/wiki/File:EPCI_Pays_de_Spincourt.svg) / CC BY-SA 3.0 |
| web-469 | 拟合 | map | ≥256KiB | pattern | map__International-recognition-of-the-State-o.svg | [来源](https://commons.wikimedia.org/wiki/File:International_recognition_of_the_State_of_Palestine.svg) / Public domain |
| web-473 | 留出 | map | 32–<256KiB | plain | map__Malta-and-Pantelleria-highlighted-in-the.svg | [来源](https://commons.wikimedia.org/wiki/File:Malta_and_Pantelleria_highlighted_in_the_Mediterranean.svg) / CC0 |
| web-476 | 拟合 | map | ≥256KiB | text | map__Map-of-Fern-n-N-ez-in-the-province.svg | [来源](https://commons.wikimedia.org/wiki/File:Map_of_Fern%C3%A1n_N%C3%BA%C3%B1ez_in_the_province.svg) / CC BY-SA 3.0 |
| web-480 | 留出 | map | ≥256KiB | dense | map__Map-of-the-proposed-Sunni-Region.svg | [来源](https://commons.wikimedia.org/wiki/File:Map_of_the_proposed_Sunni_Region.svg) / CC BY-SA 4.0 |
| web-489 | 拟合 | map | ≥256KiB | bitmap | map__Topographic-map-of-the-Messenia-Peloponn.svg | [来源](https://commons.wikimedia.org/wiki/File:Topographic_map_of_the_Messenia,_Peloponnese.svg) / CC BY-SA 4.0 |
| web-502 | 拟合 | map | 32–<256KiB | bitmap | map__sligo-map-sign.svg | [来源](https://freesvg.org/sligo-map-sign) / CC0/Public Domain (freesvg.org) |
| web-503 | 留出 | map | 32–<256KiB | paint | map__south-america-map-color.svg | [来源](https://freesvg.org/south-america-map-color) / CC0/Public Domain (freesvg.org) |
| web-504 | 拟合 | map | 32–<256KiB | text | map__taipei-outline-map.svg | [来源](https://freesvg.org/taipei-outline-map) / CC0/Public Domain (freesvg.org) |
| web-506 | 拟合 | map | ≥256KiB | dense | map__us-map-with-crh-network-dots-and-visn-06.svg | [来源](https://freesvg.org/us-map-with-crh-network-dots-and-visn-06-badge) / CC0/Public Domain (freesvg.org) |
| web-508 | 留出 | map | ≥256KiB | dense | map__visn-19-crh-united-states-network-map.svg | [来源](https://freesvg.org/visn-19-crh-united-states-network-map) / CC0/Public Domain (freesvg.org) |
| web-516 | 拟合 | mid | 32–<256KiB | plain | mid__Flag-of-the-American-Nazi-Party-1960s-20.svg | [来源](https://commons.wikimedia.org/wiki/File:Flag_of_the_American_Nazi_Party_(1960s-2015).svg) / Public domain |
| web-518 | 拟合 | mid | 4–<32KiB | paint | mid__Google-Camera-Icon-November-2014-2017.svg | [来源](https://commons.wikimedia.org/wiki/File:Google_Camera_Icon_(November_2014-2017).svg) / Public domain |
| web-524 | 留出 | mid | 4–<32KiB | plain | mid__LGBT-flag-map-of-Mauritania.svg | [来源](https://commons.wikimedia.org/wiki/File:LGBT_flag_map_of_Mauritania.svg) / CC BY-SA 3.0 |
| web-527 | 拟合 | mid | 4–<32KiB | blur | mid__NATO-Map-Symbol-NATO-IFOR.svg | [来源](https://commons.wikimedia.org/wiki/File:NATO_Map_Symbol_-_NATO_-_IFOR.svg) / CC BY-SA 4.0 |
| web-529 | 拟合 | mid | 4–<32KiB | plain | mid__OnStar-2D-logo-2016.svg | [来源](https://commons.wikimedia.org/wiki/File:OnStar_2D_logo_2016.svg) / Public domain |
| web-531 | 拟合 | mid | 4–<32KiB | plain | mid__Star-Wars-Jedi-Fallen-Order-logo-PL.svg | [来源](https://commons.wikimedia.org/wiki/File:Star_Wars_Jedi_Fallen_Order_logo_PL.svg) / Public domain |
| web-538 | 拟合 | pattern | ≥256KiB | blur | pattern__Chimmie-Xenia-the-Linux-Vixen-space-wall.svg | [来源](https://commons.wikimedia.org/wiki/File:Chimmie_-_Xenia_the_Linux_Vixen_-_space_wallpaper_(dark).svg) / CC0 |
| web-539 | 留出 | pattern | ≥256KiB | plain | pattern__Dmharvey-wallpaper-test-6-pattern.svg | [来源](https://commons.wikimedia.org/wiki/File:Dmharvey-wallpaper-test-6-pattern.svg) / Public domain |
| web-543 | 留出 | pattern | ≥256KiB | dense | pattern__Elementary-cellular-automaton-193.svg | [来源](https://commons.wikimedia.org/wiki/File:Elementary_cellular_automaton_193.svg) / CC BY-SA 4.0 |
| web-544 | 拟合 | pattern | ≥256KiB | dense | pattern__Elementary-cellular-automaton-230.svg | [来源](https://commons.wikimedia.org/wiki/File:Elementary_cellular_automaton_230.svg) / CC BY-SA 4.0 |
| web-545 | 留出 | pattern | ≥256KiB | dense | pattern__Elementary-cellular-automaton-60.svg | [来源](https://commons.wikimedia.org/wiki/File:Elementary_cellular_automaton_60.svg) / CC BY-SA 4.0 |
| web-547 | 留出 | pattern | 32–<256KiB | paint | pattern__Hadiya-Traditional-Clothing-Pattern.svg | [来源](https://commons.wikimedia.org/wiki/File:Hadiya_Traditional_Clothing_Pattern.svg) / CC BY 4.0 |
| web-551 | 拟合 | pattern | 32–<256KiB | text | pattern__Triangle-texture-soil.svg | [来源](https://commons.wikimedia.org/wiki/File:Triangle_texture_soil.svg) / CC BY-SA 4.0 |
| web-552 | 拟合 | pattern | ≥256KiB | bitmap | pattern__Tsuno-Asanoha-Kumiko-Pattern.svg | [来源](https://commons.wikimedia.org/wiki/File:Tsuno_Asanoha_Kumiko_Pattern.svg) / CC BY-SA 4.0 |
| web-555 | 留出 | pattern | ≥256KiB | text | pattern__USDA-Soil-Texture.svg | [来源](https://commons.wikimedia.org/wiki/File:USDA_Soil_Texture.svg) / CC BY-SA 4.0 |
| web-556 | 拟合 | pattern | 32–<256KiB | mask | pattern__WD10-landscape-background-10-shape-dark.svg | [来源](https://commons.wikimedia.org/wiki/File:WD10_-_landscape_background_-_10_shape_-_dark.svg) / CC BY-SA 4.0 |
| web-558 | 拟合 | pattern | ≥256KiB | pattern | pattern__Wikimania-2024-Background-pattern-orange.svg | [来源](https://commons.wikimedia.org/wiki/File:Wikimania_2024_Background_pattern_-_orange.svg) / CC0 |
| web-560 | 拟合 | pattern | 32–<256KiB | blur | pattern__abstract-colorful-face.svg | [来源](https://freesvg.org/abstract-colorful-face) / CC0/Public Domain (freesvg.org) |
| web-564 | 拟合 | pattern | 32–<256KiB | dense | pattern__antique-ornament-frame-6.svg | [来源](https://freesvg.org/antique-ornament-frame-6) / CC0/Public Domain (freesvg.org) |
| web-565 | 拟合 | pattern | <4KiB | plain | pattern__celtic-knotwork-border.svg | [来源](https://freesvg.org/celtic-knotwork-border) / CC0/Public Domain (freesvg.org) |
| web-570 | 拟合 | pattern | 4–<32KiB | plain | pattern__decorative-design-in-books-iv.svg | [来源](https://freesvg.org/decorative-design-in-books-iv) / CC0/Public Domain (freesvg.org) |
| web-580 | 拟合 | pattern | 4–<32KiB | paint | pattern__golden-wedding-ring-1695193395.svg | [来源](https://freesvg.org/golden-wedding-ring-1695193395) / CC0/Public Domain (freesvg.org) |
| web-583 | 拟合 | pattern | ≥256KiB | dense | pattern__lady-sunflowers-frame.svg | [来源](https://freesvg.org/lady-sunflowers-frame) / CC0/Public Domain (freesvg.org) |
| web-586 | 拟合 | pattern | ≥256KiB | dense | pattern__peach-tree-frame-monochrome-illustration.svg | [来源](https://freesvg.org/peach-tree-frame-monochrome-illustration) / CC0/Public Domain (freesvg.org) |
| web-591 | 拟合 | pattern | 32–<256KiB | plain | pattern__symmetrical-folk-floral-ornament-outline.svg | [来源](https://freesvg.org/symmetrical-folk-floral-ornament-outline) / CC0/Public Domain (freesvg.org) |
| web-601 | 留出 | pattern | <4KiB | paint | pattern__wave600.svg | [来源](https://freesvg.org/wave600) / CC0/Public Domain (freesvg.org) |
| web-605 | 拟合 | peeps | 4–<32KiB | plain | peeps__open-peeps-packages-open-peeps-assets-at-3.svg | [来源](https://github.com/jenshor/open-peeps/blob/main/packages/open_peeps/assets/atoms/body/Tee 1.svg) / MIT repo / Open Peeps CC0 |
| web-611 | 拟合 | peeps | 32–<256KiB | plain | peeps__open-peeps-packages-open-peeps-assets-at-9.svg | [来源](https://github.com/jenshor/open-peeps/blob/main/packages/open_peeps/assets/atoms/pose/sitting/bike.svg) / MIT repo / Open Peeps CC0 |
| web-614 | 留出 | small | 4–<32KiB | mask | small__Computer-Science-House-logo-icon-square-.svg | [来源](https://commons.wikimedia.org/wiki/File:Computer_Science_House_logo_icon_square_pride.svg) / Public domain |
| web-615 | 拟合 | small | 4–<32KiB | text | small__Emblem-of-the-SKH.svg | [来源](https://commons.wikimedia.org/wiki/File:Emblem_of_the_SKH.svg) / CC BY-SA 4.0 |
| web-616 | 拟合 | small | <4KiB | blur | small__Github-desktop-logo-symbol.svg | [来源](https://commons.wikimedia.org/wiki/File:Github-desktop-logo-symbol.svg) / Public domain |
| web-617 | 拟合 | small | <4KiB | paint | small__Google-Icon-2010-2015.svg | [来源](https://commons.wikimedia.org/wiki/File:Google_Icon_(2010-2015).svg) / Public domain |
| web-626 | 留出 | small | 4–<32KiB | plain | small__R-dt-logo-bokm-l.svg | [来源](https://commons.wikimedia.org/wiki/File:R%C3%B8dt_logo_(bokm%C3%A5l).svg) / Public domain |
| web-629 | 留出 | small | <4KiB | plain | small__Transwa-icon-v2.svg | [来源](https://commons.wikimedia.org/wiki/File:Transwa_icon_v2.svg) / Public domain |
| web-631 | 拟合 | small | <4KiB | plain | small__icons-delapouite-socks.svg | [来源](https://github.com/game-icons/icons/blob/master/delapouite/socks.svg) / CC-BY-3.0 |
| web-634 | 拟合 | small | <4KiB | plain | small__icons-icons-person-rolodex.svg | [来源](https://github.com/twbs/icons/blob/main/icons/person-rolodex.svg) / MIT |
| web-635 | 拟合 | small | <4KiB | plain | small__icons-icons-type-h2.svg | [来源](https://github.com/twbs/icons/blob/main/icons/type-h2.svg) / MIT |
| web-649 | 拟合 | tech | ≥256KiB | text | tech__Human-Neuroaxis-bn.svg | [来源](https://commons.wikimedia.org/wiki/File:Human_Neuroaxis-bn.svg) / CC BY-SA 4.0 |
| web-650 | 拟合 | tech | 32–<256KiB | plain | tech__MRI-Machine-NIH-BioArt-689-782372.svg | [来源](https://commons.wikimedia.org/wiki/File:MRI_Machine_(NIH_BioArt_689_-_782372).svg) / Public domain |
| web-654 | 拟合 | tech | 32–<256KiB | text | tech__Scheme-snail-anatomy-fr.svg | [来源](https://commons.wikimedia.org/wiki/File:Scheme_snail_anatomy-fr.svg) / CC BY 3.0 |
| web-655 | 拟合 | tech | ≥256KiB | bitmap | tech__Switched-reluctance-motor-6-4.svg | [来源](https://commons.wikimedia.org/wiki/File:Switched_reluctance_motor_6-4.svg) / Public domain |
| web-659 | 拟合 | text | ≥256KiB | blur | text__Australian-Census-2011-demographic-map-N.svg | [来源](https://commons.wikimedia.org/wiki/File:Australian_Census_2011_demographic_map_-_New_South_Wales_by_POA_-_BCP_field_5776_Females_Certificate_Level_Certificate_Level_nfd_Total.svg) / CC BY-SA 3.0 au |
| web-662 | 拟合 | text | 32–<256KiB | paint | text__Goncharov-film-poster.svg | [来源](https://commons.wikimedia.org/wiki/File:Goncharov_film_poster.svg) / CC BY-SA 4.0 |
| web-663 | 拟合 | text | 32–<256KiB | text | text__HU-Keyboard-Layout-V2-EN-Legend.svg | [来源](https://commons.wikimedia.org/wiki/File:HU_Keyboard_Layout_V2_EN_Legend.svg) / CC BY-SA 4.0 |
| web-664 | 拟合 | text | ≥256KiB | text | text__HrW-poster-Clubture-Forum-2024-updated.svg | [来源](https://commons.wikimedia.org/wiki/File:HrW_poster_Clubture_Forum_2024_(updated).svg) / CC BY 4.0 |
| web-668 | 拟合 | text | ≥256KiB | dense | text__KB-Bengali-Bijoy.svg | [来源](https://commons.wikimedia.org/wiki/File:KB-Bengali-Bijoy.svg) / CC BY-SA 4.0 |
| web-671 | 拟合 | text | 32–<256KiB | blur | text__Oxygen480-actions-view-calendar-upcoming.svg | [来源](https://commons.wikimedia.org/wiki/File:Oxygen480-actions-view-calendar-upcoming-days.svg) / LGPL |
| web-672 | 留出 | text | ≥256KiB | bitmap | text__POSTER-WMISLM-COMPANIONS-2024.svg | [来源](https://commons.wikimedia.org/wiki/File:POSTER-WMISLM-COMPANIONS-2024.svg) / CC BY-SA 4.0 |
| web-683 | 拟合 | undraw | 4–<32KiB | plain | undraw__undraw-svg-collection-svgs-contract.svg | [来源](https://github.com/balazser/undraw-svg-collection/blob/main/svgs/contract.svg) / MIT repo / unDraw License (free use) |
| web-685 | 拟合 | undraw | 32–<256KiB | dense | undraw__undraw-svg-collection-svgs-fall-is-comin.svg | [来源](https://github.com/balazser/undraw-svg-collection/blob/main/svgs/fall-is-coming.svg) / MIT repo / unDraw License (free use) |
| web-690 | 留出 | undraw | 4–<32KiB | paint | undraw__undraw-svg-collection-svgs-live-collabor.svg | [来源](https://github.com/balazser/undraw-svg-collection/blob/main/svgs/live-collaboration.svg) / MIT repo / unDraw License (free use) |
| web-692 | 留出 | undraw | 4–<32KiB | plain | undraw__undraw-svg-collection-svgs-my-password.svg | [来源](https://github.com/balazser/undraw-svg-collection/blob/main/svgs/my-password.svg) / MIT repo / unDraw License (free use) |
| web-704 | 留出 | undraw | 32–<256KiB | paint | undraw__undraw-svg-collection-svgs-young-and-hap.svg | [来源](https://github.com/balazser/undraw-svg-collection/blob/main/svgs/young-and-happy.svg) / MIT repo / unDraw License (free use) |
| web-710 | 拟合 | undraw | 4–<32KiB | paint | undraw__undraw-svg-svgs-laravel-and-vue.svg | [来源](https://github.com/evo-mark/undraw-svg/blob/main/svgs/laravel-and-vue.svg) / MIT repo / unDraw License (free use) |
| web-711 | 拟合 | undraw | 4–<32KiB | plain | undraw__undraw-svg-svgs-love-is-in-the-air.svg | [来源](https://github.com/evo-mark/undraw-svg/blob/main/svgs/love-is-in-the-air.svg) / MIT repo / unDraw License (free use) |

## PC 全集特征表

解析状态。 `ok` 714。复杂度预算拒绝 0 个。

| 编号 | 公开文件 | 类别 | 源字节 | 原生状态 | P/V/点/描/渐/透/裁/遮/糊/图/案 | 固有框 W×H | 保守内容框 L/T/R/B | 面积 px² | 占比 | 溢出 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| web-001 | arms__Arms-of-Powys-County-Council.svg | arms | 275378 | ok | 295/5683/12650/102/0/0/0/0/0/0/0 | 728.11 × 1238.45 | -65.98/-158.76/794.09/1342.49 | 1,291,184.27 | 1.43190 | 是 |
| web-002 | arms__Bexhill-coat-of-arms.svg | arms | 816685 | ok | 1725/48573/119711/0/0/0/0/0/0/0/0 | 809.00 × 1000.00 | 14.14/23.18/797.82/966.71 | 739,423.41 | 0.91400 | 否 |
| web-003 | arms__COA-B-thory.svg | arms | 954204 | ok | 4325/27084/48766/86/0/0/0/0/0/0/0 | 800.00 × 880.00 | -6040.88/-5207.40/6630.65/5853.28 | 140,155,630.85 | 199.08470 | 是 |
| web-004 | arms__COA-Gavriil-Ivanovich-Golovkin-White-Eag.svg | arms | 4308773 | ok | 22744/128333/216698/331/0/13/0/0/0/0/0 | 773.44 × 1200.12 | -7781.96/-4794.89/7607.27/6270.06 | 170,281,073.40 | 183.44871 | 是 |
| web-005 | arms__COA-Holstein-Gottorp-Romanov-chivalric.svg | arms | 1885370 | ok | 4069/45021/96696/964/0/43/0/0/0/0/0 | 800.00 × 880.00 | -743.76/-1202.89/2966.65/1457.46 | 9,870,969.90 | 14.02126 | 是 |
| web-006 | arms__COA-Jagiellon.svg | arms | 223988 | ok | 200/4122/10206/57/0/0/0/0/0/0/0 | 709.00 × 675.00 | -79.48/-79.53/786.75/754.74 | 722,668.26 | 1.51004 | 是 |
| web-007 | arms__Coat-of-Arms-of-Brooksbank-baronets.svg | arms | 344559 | ok | 371/5203/12411/113/0/0/0/0/0/0/0 | 566.10 × 889.37 | -1.62/-24.58/567.71/980.06 | 571,966.12 | 1.13605 | 是 |
| web-008 | arms__Coat-of-Arms-of-Sokolovsky.svg | arms | 419816 | ok | 377/6396/16852/307/0/0/0/0/0/0/0 | 1007.29 × 1005.72 | -50.67/-1.10/1041.30/1008.97 | 1,102,958.90 | 1.08875 | 是 |
| web-009 | arms__Coat-of-Arms-of-the-Corporation-of-the-C.svg | arms | 1234077 | ok | 846/19940/51052/180/0/0/0/0/0/0/0 | 1811.23 × 1823.92 | -163.88/0.24/2228.77/1865.36 | 4,462,583.45 | 1.35085 | 是 |
| web-010 | arms__Coat-of-arms-of-Edmund-Hillary.svg | arms | 755266 | ok | 812/16035/35654/434/0/83/14/0/0/0/0 | 1132.62 × 1096.61 | -0.22/-132.84/1432.73/1098.18 | 1,764,009.56 | 1.42025 | 是 |
| web-011 | arms__Coat-of-arms-of-Saint-Vincent-and-the-Gr.svg | arms | 171239 | ok | 90/4819/12926/0/0/0/0/0/0/0/0 | 371.39 × 545.82 | 0.00/0.00/371.39/545.82 | 202,709.61 | 1.00000 | 否 |
| web-012 | arms__Coat-of-arms-of-South-Vietnam-1963-1975.svg | arms | 425471 | ok | 574/6371/15689/182/0/0/1/0/6/0/0 | 1052.33 × 638.56 | -24.87/-2.02/1077.20/666.24 | 736,469.19 | 1.09597 | 是 |
| web-013 | arms__Coat-of-arms-of-house-Holstein-Gottorp-R.svg | arms | 208345 | ok | 688/8899/20615/602/0/0/1/0/0/0/0 | 276.00 × 519.00 | 0.60/-1.58/275.80/518.90 | 143,237.25 | 0.99995 | 是 |
| web-014 | arms__Coat-of-arms-of-the-Polish-Lithuanian-Co.svg | arms | 5399357 | ok | 7135/93031/183857/4355/1/0/0/0/0/0/0 | 1193.84 × 1180.77 | -4.70/0.00/1198.54/1183.39 | 1,423,907.50 | 1.01011 | 是 |
| web-015 | arms__Diocese-of-Lincoln-arms.svg | arms | 298300 | ok | 504/7024/17639/325/0/0/0/0/0/0/0 | 499.32 × 675.13 | -1.32/0.00/500.65/675.13 | 338,894.04 | 1.00529 | 是 |
| web-016 | arms__EBBreslauCOA.svg | arms | 120625 | ok | 161/1587/3577/157/0/0/0/0/0/0/0 | 640.90 × 920.04 | 0.03/-0.09/640.90/920.04 | 589,687.14 | 1.00005 | 是 |
| web-017 | arms__Finale-Pia-Stemma.svg | arms | 2549893 | ok | 589/9893/24032/299/30/0/1/0/0/0/0 | 390.14 × 500.22 | -1.41/0.23/398.06/501.41 | 200,206.66 | 1.02588 | 是 |
| web-018 | arms__Friedrich-von-Schreiber-Wappen.svg | arms | 131975 | ok | 775/3220/6750/774/0/4/0/0/0/0/0 | 1150.32 × 1226.47 | 2.67/0.62/1147.66/1223.80 | 1,400,531.94 | 0.99269 | 否 |
| web-019 | arms__Grosseto-Stemma.svg | arms | 264709 | ok | 861/7379/16178/560/0/0/0/0/0/0/0 | 220.46 × 376.49 | -1.20/0.01/221.64/377.09 | 84,027.19 | 1.01236 | 是 |
| web-020 | arms__Marcello-Acquaviva-stemma.svg | arms | 271857 | ok | 860/5162/11651/848/0/0/0/0/0/0/0 | 1150.32 × 1226.47 | 2.67/0.62/1147.66/1223.80 | 1,400,531.94 | 0.99269 | 否 |
| web-021 | arms__RU-CoA-Miklashevsky-7.svg | arms | 138152 | ok | 158/1979/4766/150/4/0/0/0/0/0/0 | 1028.25 × 979.17 | -0.00/-3.61/1028.25/979.17 | 1,010,534.95 | 1.00368 | 是 |
| web-022 | arms__Roning.svg | arms | 245905 | ok | 216/3792/9598/45/0/0/3/0/0/0/0 | 450.00 × 541.38 | -637.66/0.00/450.00/682.83 | 742,688.12 | 3.04857 | 是 |
| web-023 | chart__3-ary-Boolean-functions-in-octeract-grap.svg | chart | 174495 | ok | 3328/17680/37424/1280/0/0/0/0/0/0/0 | 2100.00 × 2100.00 | 34.75/34.75/2065.25/2065.25 | 4,122,930.25 | 0.93490 | 否 |
| web-024 | chart__Cycle-shapes-in-neighbor-graph-negative-.svg | chart | 110630 | ok | 264/1274/2101/251/0/0/0/0/0/0/0 | 3605.30 × 2263.03 | 37.19/48.03/3571.26/2224.24 | 7,690,845.12 | 0.94263 | 否 |
| web-025 | chart__Cycle-shapes-in-neighbor-graph-positive-.svg | chart | 112253 | ok | 273/1324/2168/260/0/9/0/0/0/0/0 | 3605.30 × 2263.03 | 37.24/48.03/3571.29/2224.24 | 7,690,829.09 | 0.94263 | 否 |
| web-026 | chart__Cycle-shapes-in-neighbor-graph-positive--2.svg | chart | 112251 | ok | 273/1322/2162/260/0/9/0/0/0/0/0 | 3605.30 × 2263.03 | 37.24/48.03/3571.29/2224.24 | 7,690,829.09 | 0.94263 | 否 |
| web-027 | chart__DJIA-historical-graph-sr.svg | chart | 671892 | ok | 31/26941/26939/29/0/1/0/0/0/0/0 | 800.00 × 400.00 | 0.00/0.00/1122.81/551.72 | 619,479.71 | 1.93587 | 是 |
| web-028 | chart__Force-graph-tactile-Cherry-ML.svg | chart | 143993 | ok | 28/97/147/28/0/7/0/0/0/0/0 | 652.00 × 432.00 | 50.50/38.00/588.75/395.50 | 192,424.38 | 0.68317 | 否 |
| web-029 | chart__Metzenseifen-Timeline.svg | chart | 540558 | ok | 423/13231/34025/17/0/0/0/0/0/0/0 | 290.00 × 210.00 | 6.20/2.40/281.18/207.52 | 56,406.09 | 0.92621 | 否 |
| web-030 | chart__NUMBER-OF-PEOPLE-UNDERNOURISHED-BY-REGIO.svg | chart | 157240 | ok | 557/7730/12548/29/0/0/114/0/0/0/0 | 311.81 × 269.29 | 11.57/12.05/294.98/259.27 | 70,064.27 | 0.83442 | 否 |
| web-031 | chart__Nonisomorphic-medial-graph-example.svg | chart | 56286 | ok | 156/732/1368/108/0/0/0/0/0/0/0 | 745.33 × 637.33 | 9.17/-0.52/746.95/638.75 | 471,636.03 | 0.99286 | 是 |
| web-032 | chart__Presocratic-graph-EL.svg | chart | 77682 | ok | 173/954/1243/93/0/0/0/0/0/0/0 | 2176.88 × 1132.50 | 9.38/-10.59/2169.38/1136.91 | 2,478,600.26 | 1.00539 | 是 |
| web-033 | chart__Spreading-homo-sapiens-la.svg | chart | 798644 | ok | 2256/63044/60714/18/0/0/0/0/0/0/0 | 1692.00 × 791.00 | -2.87/0.00/1702.25/799.68 | 1,363,553.56 | 1.01882 | 是 |
| web-034 | chart__Symmetric-group-4-Cayley-graph-1-2-6-3D.svg | chart | 282040 | ok | 228/4110/7752/0/0/120/0/0/0/0/0 | 744.09 × 744.09 | 33.22/29.48/698.27/723.22 | 461,374.92 | 0.83329 | 否 |
| web-035 | chart__Symmetric-group-4-Cayley-graph-1-5-21-Na.svg | chart | 103334 | ok | 134/1604/3114/43/0/20/0/0/0/0/0 | 511.00 × 442.00 | 5.41/3.50/508.24/439.50 | 219,233.45 | 0.97065 | 否 |
| web-036 | chart__Symmetric-group-4-cycle-graph-16x16.svg | chart | 681536 | ok | 3663/46709/96927/1385/0/1356/0/0/13/0/0 | 3090.21 × 4578.37 | -3040.29/-164.31/3115.39/4713.87 | 30,028,548.16 | 2.12244 | 是 |
| web-037 | chart__Symmetric-group-4-cycle-graph-inversions.svg | chart | 746588 | ok | 797/12873/27033/174/0/65/0/0/0/0/0 | 470.00 × 520.00 | 1.72/1.47/468.82/516.29 | 240,469.78 | 0.98392 | 否 |
| web-038 | chart__TOTAL-RENEWABLE-WATER-RESOURCES-PER-CAPI.svg | chart | 3906053 | ok | 7214/245094/249468/598/0/0/6440/0/0/0/0 | 481.89 × 260.79 | 0.00/0.00/481.89/260.79 | 125,670.65 | 1.00000 | 否 |
| web-039 | chart__Timeline-of-daily-new-confirmed-COVID-19.svg | chart | 70874 | ok | 23/4851/6205/17/0/0/3/0/0/0/0 | 850.00 × 600.00 | 0.00/0.00/899.90/600.50 | 540,387.55 | 1.05958 | 是 |
| web-040 | chart__Timeline-of-the-main-schisms-from-the-Se.svg | chart | 84227 | ok | 49/832/1735/48/0/0/0/0/0/0/0 | 1972.10 × 569.85 | -1.50/-1.50/1976.05/571.35 | 1,132,836.63 | 1.00804 | 是 |
| web-041 | chart__US-timeline-Prescription-opioid-pain-rel.svg | chart | 118225 | ok | 23/2762/7262/7/0/0/65/0/0/0/0 | 785.48 × 516.84 | -2.65/-25.24/813.32/558.75 | 476,513.78 | 1.17377 | 是 |
| web-042 | chart__WORLD-CAPTURE-FISHERIES-AND-AQUACULTURE-.svg | chart | 197102 | ok | 682/9861/16334/3/0/0/92/0/0/0/0 | 311.81 × 277.80 | 11.23/12.05/293.75/266.47 | 71,879.90 | 0.82983 | 否 |
| web-043 | chart__WORLD-GREENHOUSE-GAS-EMISSIONS-FROM-AGRI.svg | chart | 152269 | ok | 609/7573/12201/84/0/0/1/0/0/0/0 | 510.24 × 311.81 | 11.23/12.05/486.64/302.87 | 138,260.09 | 0.86903 | 否 |
| web-044 | clipart__1910s-woman-portrait-on-black-background.svg | clipart | 1063659 | ok | 1/26368/63051/0/0/0/0/0/0/0/0 | 277.60 × 389.12 | 0.00/0.00/277.60/389.12 | 108,019.71 | 1.00000 | 否 |
| web-045 | clipart__2015-calendar-poster-with-dark-olive-bac.svg | clipart | 571349 | ok | 1134/16766/34303/1/0/0/0/0/0/0/0 | 720.00 × 1025.00 | 12.14/12.01/707.86/1012.99 | 696,403.12 | 0.94364 | 否 |
| web-046 | clipart__2017-cloud-technology.svg | clipart | 139056 | ok | 98/2820/4802/90/3/0/95/1/0/0/0 | 1066.67 × 1066.67 | 0.00/0.00/1066.67/1066.67 | 1,137,777.69 | 1.00000 | 否 |
| web-047 | clipart__a-north-american-brig.svg | clipart | 4165796 | ok | 1/121725/284067/0/0/0/0/0/0/0/0 | 3266.67 × 4252.00 | 90.04/71.86/3218.82/4194.55 | 12,899,003.24 | 0.92866 | 否 |
| web-048 | clipart__a-young-man-from-ancient-times.svg | clipart | 58013 | ok | 1/1299/3172/0/0/0/0/0/0/0/0 | 208.00 × 544.00 | 12.00/14.96/184.13/524.65 | 87,736.79 | 0.77539 | 否 |
| web-049 | clipart__a-young-woman-throws-pieces-of-gold.svg | clipart | 215309 | ok | 11/3605/8040/0/0/0/0/0/0/0/0 | 642.58 × 946.29 | 46.12/31.89/589.44/884.30 | 463,132.84 | 0.76165 | 否 |
| web-050 | clipart__arduino-generic-uno-r3-microcontroller.svg | clipart | 610570 | ok | 241/2291/4087/43/0/0/0/0/0/1/0 | 602.00 × 428.00 | 0.00/0.00/602.00/428.00 | 257,656.00 | 1.00000 | 否 |
| web-051 | clipart__arms-of-chester-city-02759.svg | clipart | 2611767 | ok | 15/91341/218196/0/0/0/0/0/0/0/0 | 190.80 × 176.25 | 29.62/16.21/165.63/163.81 | 20,073.91 | 0.59693 | 否 |
| web-052 | clipart__arms-of-sir-dafydd-gam.svg | clipart | 1001448 | ok | 15/33656/84005/0/0/0/0/0/0/0/0 | 150.00 × 165.00 | 11.23/9.89/140.70/159.60 | 19,383.24 | 0.78316 | 否 |
| web-053 | clipart__australian-wildlife-engraving-with-kanga.svg | clipart | 1033420 | ok | 1/23150/59810/0/0/0/0/0/0/0/0 | 730.60 × 518.43 | 0.00/0.00/730.60/518.43 | 378,765.87 | 1.00000 | 否 |
| web-054 | clipart__autumn-colors.svg | clipart | 22394 | ok | 29/282/599/0/2/0/27/0/0/0/0 | 880.00 × 880.00 | 0.00/0.00/880.00/880.00 | 774,397.58 | 1.00000 | 否 |
| web-055 | clipart__basicgrandfatherclock.svg | clipart | 193410 | ok | 1/5210/12455/0/0/0/0/0/0/0/0 | 268.87 × 911.77 | 0.00/0.00/268.87/911.77 | 245,152.31 | 1.00000 | 否 |
| web-056 | clipart__beach-scene.svg | clipart | 92691 | ok | 222/2446/6180/222/0/0/0/0/0/0/0 | 1920.00 × 1703.00 | -0.05/-0.05/1920.05/1703.05 | 3,270,100.13 | 1.00010 | 是 |
| web-057 | clipart__big-window-on-a-house.svg | clipart | 53391 | ok | 32/1250/2854/0/0/0/32/0/0/0/0 | 880.00 × 880.00 | 1.24/2.04/880.00/880.00 | 771,523.03 | 0.99628 | 否 |
| web-058 | clipart__black-and-white-cartoon-dog-silhouette.svg | clipart | 107989 | ok | 4/587/1576/0/0/0/0/0/0/0/0 | 600.00 × 600.00 | 153.95/14.83/464.75/573.08 | 173,510.63 | 0.48197 | 否 |
| web-059 | clipart__black-and-white-dragon-ornament.svg | clipart | 67650 | ok | 1/1690/4095/0/0/0/0/0/0/0/0 | 293.33 × 298.39 | 0.00/0.00/293.33/298.39 | 87,525.26 | 1.00000 | 否 |
| web-060 | clipart__black-and-white-dragon-vector-illustrati.svg | clipart | 68331 | ok | 6/2036/5353/0/0/0/0/0/0/0/0 | 313.01 × 171.24 | -0.00/-0.00/313.01/171.23 | 53,598.45 | 1.00000 | 是 |
| web-061 | clipart__black-and-white-silhouette-of-a-nanny-pu.svg | clipart | 85110 | ok | 1/1825/5056/0/0/0/0/0/0/0/0 | 353.24 × 366.19 | 0.00/0.00/353.24/366.19 | 129,350.19 | 1.00000 | 否 |
| web-062 | clipart__black-car-1637798726.svg | clipart | 140493 | ok | 1/2773/6720/0/0/0/0/0/0/0/0 | 4251.00 × 1127.00 | 0.22/0.67/4251.18/1126.79 | 4,787,095.34 | 0.99921 | 是 |
| web-063 | clipart__blonde-man-ii.svg | clipart | 104168 | ok | 67/1177/2217/60/0/7/0/0/0/0/0 | 519.68 × 667.20 | 18.81/48.85/469.76/575.99 | 237,710.83 | 0.68558 | 否 |
| web-064 | clipart__blue-rose-engraving-on-black-background.svg | clipart | 216477 | ok | 2/4988/12491/0/0/0/0/0/0/0/0 | 352.28 × 304.56 | 0.00/0.00/352.28/304.56 | 107,292.54 | 1.00000 | 否 |
| web-065 | clipart__boat-24d.svg | clipart | 55720 | ok | 3/1251/2926/0/0/0/0/0/0/0/0 | 1375.99 × 977.07 | 0.00/0.00/1375.99/977.07 | 1,344,431.78 | 1.00000 | 是 |
| web-066 | clipart__boat-83.svg | clipart | 3577594 | ok | 1/125996/233766/0/0/0/0/0/0/0/0 | 685.12 × 477.12 | 0.04/0.64/683.20/474.83 | 323,944.82 | 0.99101 | 否 |
| web-067 | clipart__bowl-of-apples.svg | clipart | 76456 | ok | 53/479/1113/51/0/0/0/0/0/0/0 | 394.19 × 391.86 | 5.07/3.21/390.69/391.11 | 149,575.62 | 0.96834 | 否 |
| web-068 | clipart__boys-white-block-letters-on-black-square.svg | clipart | 139379 | ok | 1728/10555/9411/0/0/0/0/0/0/0/0 | 1562.00 × 1563.00 | -0.60/0.00/1562.00/1563.00 | 2,442,345.43 | 1.00038 | 是 |
| web-069 | clipart__brooding-man-with-dark-hair-wrapped-in-c.svg | clipart | 126714 | ok | 4/2831/6989/0/0/0/0/0/0/0/0 | 1148.00 × 821.33 | 87.63/54.74/1024.99/764.00 | 664,829.77 | 0.70510 | 否 |
| web-070 | clipart__cartoon-animal-numbers-set.svg | clipart | 62219 | ok | 273/1667/3405/134/0/0/0/0/0/0/0 | 425.06 × 196.79 | 0.00/0.00/425.06/196.83 | 83,665.75 | 1.00021 | 是 |
| web-071 | clipart__cartoon-crocodile-with-open-mouth.svg | clipart | 132399 | ok | 11/3953/10353/1/0/0/0/0/0/0/0 | 2482.67 × 2130.67 | 11.85/11.49/2468.00/2120.53 | 5,180,130.28 | 0.97928 | 否 |
| web-072 | clipart__cartoon-orca-whale-vector.svg | clipart | 4703 | ok | 9/53/126/8/0/0/0/0/0/0/0 | 433.21 × 303.85 | -3.01/-3.00/436.21/306.85 | 136,095.29 | 1.03389 | 是 |
| web-073 | clipart__castleforbes.svg | clipart | 6311343 | ok | 11893/120426/291025/11893/0/0/0/0/0/0/0 | 3242.67 × 2386.67 | -324.40/-238.67/3566.96/2625.33 | 11,144,861.59 | 1.44006 | 是 |
| web-074 | clipart__christian-owl.svg | clipart | 256945 | ok | 1/5719/15846/0/0/0/0/0/0/0/0 | 1324.57 × 1509.55 | 26.24/-46.65/1286.13/1635.52 | 2,119,342.18 | 1.05993 | 是 |
| web-075 | clipart__christmas-decoration-in-the-window.svg | clipart | 93389 | ok | 336/2230/2503/0/0/0/0/0/0/0/0 | 880.00 × 880.00 | 0.00/1.76/880.00/880.00 | 772,855.42 | 0.99801 | 否 |
| web-076 | clipart__cigcardhancock.svg | clipart | 5258328 | ok | 22335/205750/485515/0/0/0/0/0/0/0/0 | 1752.00 × 3026.67 | -0.33/-0.42/1752.41/3026.90 | 5,306,124.23 | 1.00064 | 是 |
| web-077 | clipart__city-building-skyline.svg | clipart | 17662 | ok | 37/1083/963/0/0/0/1/0/0/0/0 | 880.00 × 880.00 | 0.00/0.00/880.00/880.00 | 774,399.89 | 1.00000 | 否 |
| web-078 | clipart__city-frame.svg | clipart | 1949842 | ok | 13/49886/117182/1/0/0/0/0/0/0/0 | 1116.86 × 1604.09 | 0.00/0.00/1116.86/1604.09 | 1,791,546.87 | 1.00000 | 否 |
| web-079 | clipart__clip-art-free-vector-pack.svg | clipart | 285575 | ok | 102/8809/19858/0/2/0/3/2/0/0/0 | 816.00 × 816.00 | 25.46/17.23/794.66/683.32 | 512,357.89 | 0.76947 | 否 |
| web-080 | clipart__clojure-is-infectious.svg | clipart | 60473 | ok | 55/961/1769/12/0/0/0/0/13/0/0 | 974.65 × 1192.26 | 0.00/0.00/974.65/1192.26 | 1,162,037.34 | 1.00000 | 否 |
| web-081 | clipart__clown-in-black-hat-and-blue-striped-shir.svg | clipart | 51231 | ok | 7/1101/2818/0/0/0/0/0/0/0/0 | 293.47 × 300.84 | -0.00/-0.00/293.47/300.84 | 88,288.19 | 1.00000 | 是 |
| web-082 | clipart__coat-of-arms-of-liberia.svg | clipart | 662479 | ok | 793/10177/22899/215/0/0/0/0/0/0/0 | 698.21 × 736.64 | -13.18/-13.18/711.39/749.83 | 552,845.87 | 1.07489 | 是 |
| web-083 | clipart__coat-of-arms-of-the-norwegian-municipali.svg | clipart | 8007 | ok | 8/202/327/0/0/0/0/0/0/0/0 | 856.00 × 1038.67 | 31.06/14.67/804.45/1021.78 | 778,891.25 | 0.87605 | 否 |
| web-084 | clipart__coat-of-arms-with-the-text-wise-as-a-ser.svg | clipart | 74787 | ok | 5/1889/4573/0/0/0/0/0/0/0/0 | 448.00 × 445.00 | 7.94/7.11/441.76/439.65 | 187,646.38 | 0.94124 | 否 |
| web-085 | clipart__cockatrice-mythological-creature.svg | clipart | 412703 | ok | 1/9649/23666/0/0/0/0/0/0/0/0 | 361.25 × 409.40 | 0.00/0.00/361.25/409.40 | 147,894.40 | 1.00000 | 否 |
| web-086 | clipart__computer-screen-and-smartphone.svg | clipart | 2050 | ok | 5/39/61/0/0/0/0/0/0/0/0 | 800.00 × 800.00 | 156.30/64.53/674.08/674.56 | 315,865.95 | 0.49354 | 否 |
| web-087 | clipart__cork-sign-irish.svg | clipart | 776 | ok | 2/20/34/2/0/0/0/0/0/0/0 | 640.00 × 480.00 | 75.50/96.50/537.50/370.50 | 126,588.00 | 0.41207 | 否 |
| web-088 | clipart__costume-ball.svg | clipart | 128892 | ok | 1/2977/7446/0/0/0/0/0/0/0/0 | 706.06 × 1718.18 | 81.22/97.70/602.89/1610.03 | 788,924.60 | 0.65032 | 否 |
| web-089 | clipart__creepy-mugshot.svg | clipart | 720891 | ok | 8/16633/41642/0/0/0/0/0/0/0/0 | 793.70 × 1122.52 | -5.14/11.66/782.29/1116.23 | 869,770.92 | 0.97623 | 是 |
| web-090 | clipart__crouching-tiger-vintage-engraving.svg | clipart | 4475014 | ok | 1/130191/290214/0/0/0/0/0/0/0/0 | 5371.43 × 2392.86 | 137.44/168.59/5164.75/2241.05 | 10,418,876.24 | 0.81061 | 否 |
| web-091 | clipart__curved-leaping-fish-black-and-white-wood.svg | clipart | 51703 | ok | 1/1158/2916/0/0/0/0/0/0/0/0 | 380.68 × 422.73 | 28.76/19.36/351.92/403.36 | 124,091.72 | 0.77112 | 否 |
| web-092 | clipart__daily-things-vortex.svg | clipart | 60054 | ok | 78/1404/2459/62/0/0/0/0/0/0/0 | 2180.00 × 2187.00 | 247.96/90.27/1848.61/1966.28 | 3,002,843.72 | 0.62984 | 否 |
| web-093 | clipart__dark-fantasy-scene-with-armored-figure-i.svg | clipart | 246626 | ok | 73/2140/5838/6/1/0/0/0/0/0/0 | 2645.67 × 1511.81 | -352.78/-365.47/2779.71/1760.95 | 6,660,984.18 | 1.66535 | 是 |
| web-094 | clipart__dragon-design.svg | clipart | 407075 | ok | 9/30157/27472/0/0/0/0/0/0/0/0 | 1104.37 × 966.53 | -3.41/-144.47/1107.78/928.74 | 1,192,535.28 | 1.11723 | 是 |
| web-095 | clipart__dream-i.svg | clipart | 156915 | ok | 14/4366/8775/0/0/0/0/0/0/0/0 | 1083.22 × 1409.32 | 0.00/0.00/1083.22/1409.32 | 1,526,604.48 | 1.00000 | 否 |
| web-096 | clipart__dusseldorf-coat-of-arms.svg | clipart | 50029 | ok | 44/2337/6560/23/0/0/0/0/0/0/0 | 1449.00 × 1737.00 | 0.00/0.00/1449.00/1736.00 | 2,515,464.00 | 0.99942 | 否 |
| web-097 | clipart__elephants-camels-horses-donkeys-and-peop.svg | clipart | 346262 | ok | 1/8123/20900/0/0/0/0/0/0/0/0 | 2706.67 × 794.67 | 8.13/19.65/2685.07/789.50 | 2,060,843.27 | 0.95813 | 否 |
| web-098 | clipart__engraved-portrait-of-bearded-older-man.svg | clipart | 1964434 | ok | 1/57504/135023/0/0/0/0/0/0/0/0 | 2453.00 × 3135.00 | 194.06/94.44/2177.41/2978.46 | 5,720,023.28 | 0.74381 | 否 |
| web-099 | clipart__engraving-style-snail-vector.svg | clipart | 79904 | ok | 28/1519/4217/0/0/0/0/0/0/0/0 | 600.00 × 600.00 | 41.00/73.44/559.51/378.94 | 158,403.39 | 0.44001 | 否 |
| web-100 | clipart__escudo-nacional-de-costa-rica-costa-rica.svg | clipart | 320298 | ok | 318/3021/5892/223/191/0/0/0/0/0/0 | 772.16 × 830.30 | 56.59/56.69/715.57/773.63 | 472,453.31 | 0.73692 | 否 |
| web-101 | clipart__esp32-devkitc.svg | clipart | 388382 | ok | 1061/6070/7395/118/114/42/0/0/135/0/0 | 2973.83 × 1465.18 | 0.00/0.00/2973.83/1465.18 | 4,357,203.33 | 1.00000 | 否 |
| web-102 | clipart__fiery-sunset-over-rocky-sea-coast.svg | clipart | 8583103 | ok | 18263/207338/521417/0/0/0/0/0/0/0/0 | 3648.00 × 2496.00 | 2.00/2.00/3650.00/2498.00 | 9,105,419.33 | 1.00000 | 是 |
| web-103 | clipart__flag-of-andorra.svg | clipart | 53709 | ok | 116/1217/2410/58/0/0/0/0/0/0/0 | 708.66 × 496.06 | 0.00/0.00/708.66/496.06 | 351,538.00 | 1.00000 | 是 |
| web-104 | clipart__flowers-53.svg | clipart | 50113 | ok | 15/534/1286/7/0/0/0/0/0/0/0 | 351.65 × 580.38 | 55.71/36.17/283.32/539.04 | 114,460.75 | 0.56083 | 否 |
| web-105 | clipart__flying-eagle-silhouette-1794684106.svg | clipart | 122320 | ok | 48/2633/7069/0/0/0/0/0/0/0/0 | 660.00 × 660.00 | 89.38/45.44/575.86/613.28 | 276,243.51 | 0.63417 | 否 |
| web-106 | clipart__flying-green-dragon-1685518084.svg | clipart | 11050 | ok | 18/146/375/0/0/0/1/0/0/0/0 | 880.00 × 880.00 | 10.43/102.31/858.76/735.28 | 536,968.66 | 0.69340 | 否 |
| web-107 | clipart__flyingbird2.svg | clipart | 76768 | ok | 128/2252/5831/0/0/0/0/0/0/0/0 | 2553.33 × 1188.00 | -0.03/0.00/2553.37/1188.00 | 3,033,442.94 | 1.00003 | 是 |
| web-108 | clipart__galileo-galilei-2.svg | clipart | 2240469 | ok | 1/59006/140207/0/0/0/0/0/0/0/0 | 683.49 × 873.57 | 35.15/23.72/650.26/850.33 | 508,462.79 | 0.85159 | 否 |
| web-109 | clipart__galleon-with-yellow-sails-and-red-pennan.svg | clipart | 89648 | ok | 117/1919/3807/0/0/0/0/0/0/0/0 | 1127.11 × 1844.67 | 0.00/-0.00/1127.11/1844.67 | 2,079,149.21 | 1.00000 | 是 |
| web-110 | clipart__giantscauseway2.svg | clipart | 4939779 | ok | 20281/193607/460738/0/0/0/0/0/0/0/0 | 2674.67 × 1817.33 | -0.50/-0.00/2674.79/1817.39 | 4,862,036.91 | 1.00026 | 是 |
| web-111 | clipart__glitchsimplifiedhobbithouse.svg | clipart | 1256011 | ok | 1566/21504/52561/1/29/32/0/0/0/0/0 | 452.73 × 385.28 | 0.00/0.00/452.73/385.28 | 174,428.64 | 1.00000 | 是 |
| web-112 | clipart__goggles.svg | clipart | 379507 | ok | 587/8160/19607/1/1/0/0/0/0/0/0 | 400.00 × 584.00 | -0.27/-1.40/402.12/585.88 | 236,316.48 | 1.01163 | 是 |
| web-113 | clipart__green-dragon-with-coiled-tail.svg | clipart | 84649 | ok | 7/4466/9608/0/0/0/0/0/0/0/0 | 847.35 × 809.24 | 0.00/-0.00/847.35/809.23 | 685,703.47 | 1.00000 | 是 |
| web-114 | clipart__green-hummingbird-with-blue-head-in-flig.svg | clipart | 644378 | ok | 8/16906/39575/0/0/0/0/0/0/0/0 | 1667.00 × 1463.48 | 142.21/106.74/1422.07/1355.53 | 1,598,260.56 | 0.65513 | 否 |
| web-115 | clipart__green-tree-ecology-symbol.svg | clipart | 104813 | ok | 146/1305/2868/0/0/0/146/0/0/0/0 | 800.00 × 800.00 | 212.20/14.58/611.39/704.49 | 275,401.93 | 0.43032 | 否 |
| web-116 | clipart__green-winged-dragon-standing.svg | clipart | 167077 | ok | 4/8053/20335/0/0/0/0/0/0/0/0 | 1444.01 × 1041.00 | 0.06/0.00/1443.41/1040.73 | 1,502,134.97 | 0.99929 | 否 |
| web-117 | clipart__halved-orange-fruit-cross-section.svg | clipart | 50814 | ok | 20/494/1406/16/0/0/0/0/0/0/0 | 1280.00 × 1280.00 | 88.61/154.04/1228.07/1137.80 | 1,120,963.02 | 0.68418 | 否 |
| web-118 | clipart__harbourscene.svg | clipart | 4743390 | ok | 16986/189144/462318/0/0/0/0/0/0/0/0 | 2960.00 × 3520.00 | -0.00/-0.00/2960.00/3520.01 | 10,419,239.75 | 1.00000 | 是 |
| web-119 | clipart__heraldic-rearing-stag-with-olive-green-a.svg | clipart | 56843 | ok | 5/1320/3334/0/0/0/0/0/0/0/0 | 1727.18 × 2097.25 | 0.00/0.00/1727.18/2097.25 | 3,622,318.04 | 1.00000 | 否 |
| web-120 | clipart__heraldic-winged-dragon-outline-line-art.svg | clipart | 64939 | ok | 1/1406/3704/0/0/0/0/0/0/0/0 | 1117.52 × 704.00 | 0.00/0.00/1117.52/704.00 | 786,728.58 | 1.00000 | 否 |
| web-121 | clipart__heraldic-wolf-headed-green-dragon.svg | clipart | 115758 | ok | 7/2344/6157/0/0/0/0/0/0/0/0 | 812.97 × 1006.34 | -0.00/-0.00/812.97/1006.34 | 818,119.25 | 1.00000 | 是 |
| web-122 | clipart__home-price-vector-graphics.svg | clipart | 3016 | ok | 3/44/61/1/1/1/0/0/1/0/0 | 64.00 × 64.00 | -1.86/-2.70/260.00/67.98 | 18,508.24 | 4.51861 | 是 |
| web-123 | clipart__honey-jar-with-two-red-apples.svg | clipart | 206451 | ok | 366/3886/9433/18/28/19/0/0/295/0/0 | 2423.49 × 1964.64 | 7.58/347.55/2387.78/1910.15 | 3,719,300.30 | 0.78116 | 否 |
| web-124 | clipart__honeycomb-3d-icon.svg | clipart | 51119 | ok | 106/996/1611/0/0/0/0/0/0/0/0 | 880.00 × 880.00 | 43.46/47.78/844.64/749.90 | 562,518.66 | 0.72639 | 否 |
| web-125 | clipart__hourglass-detailed.svg | clipart | 673233 | ok | 533/5284/13615/3/61/40/13/2/433/0/0 | 793.70 × 1122.52 | 218.93/165.71/574.77/956.81 | 281,497.57 | 0.31595 | 否 |
| web-126 | clipart__house-icon-silhouette-1791192408.svg | clipart | 93542 | ok | 16/230/605/0/0/0/0/0/0/0/0 | 600.00 × 600.00 | 48.92/76.68/544.92/491.42 | 205,713.34 | 0.57143 | 否 |
| web-127 | clipart__human-skull-three-quarter-view-engraving.svg | clipart | 349270 | ok | 1/8217/21150/0/0/0/0/0/0/0/0 | 1349.33 × 1602.67 | 21.71/87.40/1266.59/1499.66 | 1,758,098.73 | 0.81298 | 否 |
| web-128 | clipart__iceberg-floating-in-blue-arctic-sea.svg | clipart | 166654 | ok | 4/8825/22304/0/0/0/0/0/0/0/0 | 822.50 × 457.21 | -0.83/-0.04/822.50/458.15 | 377,243.82 | 1.00316 | 是 |
| web-129 | clipart__illustration-from-books-ii.svg | clipart | 205935 | ok | 1/5123/12072/0/0/0/0/0/0/0/0 | 534.67 × 781.33 | 11.72/12.07/525.10/772.67 | 390,478.87 | 0.93471 | 否 |
| web-130 | clipart__ilmenskiefantasyscene.svg | clipart | 330053 | ok | 171/2639/6729/0/75/44/0/0/0/0/0 | 517.49 × 380.51 | 0.00/0.00/517.49/489.68 | 253,407.15 | 1.28690 | 是 |
| web-131 | clipart__island-life-retro-sunset-with-palm-trees.svg | clipart | 1142565 | ok | 57/33442/63691/0/2/0/0/0/0/0/0 | 1409.40 × 1039.37 | 3.77/16.57/1409.40/994.05 | 1,373,982.26 | 0.93794 | 是 |
| web-132 | clipart__julie-de-graag-two-owls.svg | clipart | 325473 | ok | 2/7374/20131/0/0/0/0/0/0/0/0 | 727.39 × 1006.73 | 0.00/0.00/727.39/1006.73 | 732,281.20 | 1.00000 | 否 |
| web-133 | clipart__jumping-hound-silhouette.svg | clipart | 55052 | ok | 19/980/2720/0/0/0/0/0/0/0/0 | 600.00 × 600.00 | 92.79/102.62/498.49/497.15 | 160,060.99 | 0.44461 | 否 |
| web-134 | clipart__kestrel-perched-on-green-branch.svg | clipart | 52424 | ok | 8/1108/2638/0/0/0/0/0/0/0/0 | 481.51 × 607.51 | 10.76/15.76/464.19/588.69 | 259,787.78 | 0.88809 | 否 |
| web-135 | clipart__keyboard-and-mouse-with-russian-layout.svg | clipart | 138267 | ok | 94/815/1361/88/2/2/0/0/1/0/0 | 1365.69 × 486.02 | -1.35/-10.28/1367.38/488.68 | 682,943.66 | 1.02891 | 是 |
| web-136 | clipart__keyboard-vector-image-1635276518.svg | clipart | 324066 | ok | 395/4503/7906/108/314/0/0/0/106/0/0 | 700.00 × 250.00 | 20.00/15.12/680.51/236.00 | 145,893.45 | 0.83368 | 否 |
| web-137 | clipart__knight-in-front-of-the-castle.svg | clipart | 380678 | ok | 1/10266/26314/0/0/0/0/0/0/0/0 | 719.70 × 957.80 | -0.00/0.00/719.70/957.80 | 689,333.20 | 1.00000 | 是 |
| web-138 | clipart__krajna-polana-coat-of-arms-with-rider-on.svg | clipart | 51274 | ok | 6/2432/5102/0/0/0/0/0/0/0/0 | 1086.50 × 1165.76 | 0.04/0.04/1086.46/1165.72 | 1,266,426.32 | 0.99987 | 否 |
| web-139 | clipart__man-with-gun-and-man-in-chair.svg | clipart | 526733 | ok | 1/14473/37442/0/0/0/0/0/0/0/0 | 2713.70 × 1662.99 | 0.00/21.96/2707.00/1662.99 | 4,442,281.81 | 0.98436 | 是 |
| web-140 | clipart__masquerade-ball.svg | clipart | 207126 | ok | 1/5285/12492/0/0/0/0/0/0/0/0 | 804.26 × 1346.81 | 44.45/23.73/758.43/1243.13 | 870,633.94 | 0.80378 | 否 |
| web-141 | clipart__medieval-castle-door.svg | clipart | 15506 | ok | 27/454/497/0/0/0/0/0/0/0/0 | 880.00 × 880.00 | 153.62/12.88/732.67/771.14 | 439,068.34 | 0.56698 | 否 |
| web-142 | clipart__moon-viewing-scene.svg | clipart | 83393 | ok | 144/1248/3095/0/0/0/0/0/0/0/0 | 380.24 × 381.28 | 29.87/16.59/353.51/377.23 | 116,717.59 | 0.80507 | 否 |
| web-143 | clipart__night-descends-on-the-forsaken-city.svg | clipart | 2111330 | ok | 3293/51855/137686/0/0/0/0/0/0/0/0 | 1920.00 × 1022.00 | 0.96/0.92/1921.21/1023.00 | 1,962,657.50 | 1.00021 | 是 |
| web-144 | clipart__night-forest-landscape-with-full-moon.svg | clipart | 23542 | ok | 21/688/926/0/0/0/0/0/0/0/0 | 880.00 × 880.00 | 0.94/0.00/882.88/881.94 | 777,823.01 | 1.00442 | 是 |
| web-145 | clipart__no-smart-glasses-prohibition-sign.svg | clipart | 87499 | ok | 93/1253/3058/48/12/17/7/0/13/0/0 | 1057.07 × 1349.85 | 32.34/49.52/999.60/1315.53 | 1,224,563.22 | 0.85821 | 否 |
| web-146 | clipart__nuclear-explosion-1751369045.svg | clipart | 50881 | ok | 39/920/2531/1/1/0/38/0/0/0/0 | 880.00 × 880.00 | -0.31/-0.31/878.98/878.98 | 773,140.25 | 0.99837 | 是 |
| web-147 | clipart__old-building.svg | clipart | 1193410 | ok | 1/31762/79814/0/0/0/0/0/0/0/0 | 2030.39 × 2248.82 | 0.00/38.08/2030.39/2248.82 | 4,488,657.08 | 0.98307 | 否 |
| web-148 | clipart__old-man-and-monkey-illustration.svg | clipart | 368214 | ok | 1/8181/21424/0/0/0/0/0/0/0/0 | 206.96 × 385.99 | 0.00/0.00/206.96/385.99 | 79,885.40 | 1.00000 | 是 |
| web-149 | clipart__old-man-with-glasses-and-long-beard-port.svg | clipart | 103619 | ok | 1/2439/5715/0/0/0/0/0/0/0/0 | 360.36 × 524.03 | 0.00/-0.00/360.36/524.03 | 188,837.10 | 1.00000 | 是 |
| web-150 | clipart__old-stone-church-with-bell-tower-engravi.svg | clipart | 8748679 | ok | 1/217889/529130/0/0/0/0/0/0/0/0 | 639.37 × 692.56 | 0.00/0.00/639.37/692.56 | 442,805.71 | 1.00000 | 否 |
| web-151 | clipart__orange-carrot-with-black-outline.svg | clipart | 71445 | ok | 2/1497/3966/0/0/0/0/0/0/0/0 | 40.17 × 179.33 | 0.00/0.00/40.17/179.33 | 7,203.18 | 1.00000 | 否 |
| web-152 | clipart__orangu-bird.svg | clipart | 67902 | ok | 23/1213/3298/0/0/0/0/0/0/0/0 | 646.25 × 1106.92 | -0.00/0.00/646.25/1106.92 | 715,355.01 | 1.00000 | 是 |
| web-153 | clipart__peacock-walking-right-with-trailing-tail.svg | clipart | 233674 | ok | 1/5836/14168/0/0/0/0/0/0/0/0 | 512.00 × 265.92 | 9.53/8.36/499.73/258.30 | 122,521.43 | 0.89989 | 否 |
| web-154 | clipart__pear-on-a-branch-silhouette.svg | clipart | 100072 | ok | 32/3146/7741/0/0/0/0/0/0/0/0 | 120.82 × 139.79 | 0.00/-0.00/120.82/139.79 | 16,888.24 | 0.99998 | 是 |
| web-155 | clipart__perched-falcon-line-art.svg | clipart | 58312 | ok | 30/352/996/30/0/0/0/0/0/0/0 | 382.85 × 439.56 | 13.07/-6.37/366.58/431.19 | 154,680.15 | 0.91916 | 是 |
| web-156 | clipart__pierce-arrow-car.svg | clipart | 3266459 | ok | 9/96426/236521/0/0/0/0/0/0/0/0 | 2706.14 × 975.12 | 8.53/6.96/2696.19/975.12 | 2,602,076.49 | 0.98608 | 否 |
| web-157 | clipart__pop-art-woman-with-curly-blonde-hair.svg | clipart | 50649 | ok | 5/1036/2282/0/0/0/0/0/0/0/0 | 689.66 × 698.66 | 42.39/29.35/623.91/665.22 | 369,771.57 | 0.76742 | 否 |
| web-158 | clipart__portrait-of-elise-kobke.svg | clipart | 537849 | ok | 1/13542/33197/0/0/0/0/0/0/0/0 | 1091.00 × 1100.00 | 13.00/20.57/1083.57/1082.38 | 1,136,739.56 | 0.94720 | 否 |
| web-159 | clipart__primordial-incandescence-lone-tree-islan.svg | clipart | 6663770 | ok | 14303/162214/408331/0/0/0/0/0/0/0/0 | 3000.00 × 2000.00 | 2.00/2.00/3002.00/2002.00 | 6,000,002.02 | 1.00000 | 是 |
| web-160 | clipart__profile-vector-of-jesus-christ-silhouett.svg | clipart | 119780 | ok | 19/2563/7039/0/0/0/0/0/0/0/0 | 600.00 × 600.00 | 58.70/50.09/538.27/533.60 | 231,878.07 | 0.64411 | 否 |
| web-161 | clipart__programmers-working.svg | clipart | 57650 | ok | 101/644/1089/0/0/0/99/0/0/0/0 | 880.00 × 880.00 | 0.00/0.00/880.00/880.00 | 774,400.00 | 1.00000 | 否 |
| web-162 | clipart__rampant-lion-holding-a-golden-cross.svg | clipart | 57023 | ok | 7/1116/2968/0/0/0/0/0/0/0/0 | 815.72 × 876.05 | 0.00/0.00/815.72/876.05 | 714,611.49 | 1.00000 | 是 |
| web-163 | clipart__red-anchor.svg | clipart | 280514 | ok | 151/7113/16942/0/0/1/2/0/0/0/0 | 1600.00 × 1600.00 | 75.76/78.22/1528.72/1521.78 | 2,097,444.07 | 0.81931 | 否 |
| web-164 | clipart__red-heraldic-dragon-breathing-yellow-fir.svg | clipart | 78668 | ok | 7/1435/3791/0/0/0/0/0/0/0/0 | 1117.52 × 704.00 | 0.00/-0.00/1117.52/704.00 | 786,728.82 | 1.00000 | 是 |
| web-165 | clipart__red-letter-l-with-foliate-background.svg | clipart | 83832 | ok | 2/1623/4561/0/0/0/0/0/0/0/0 | 238.25 × 264.95 | 0.00/0.00/238.25/264.95 | 63,123.50 | 1.00000 | 否 |
| web-166 | clipart__red-sky-sunset-over-brown-grass-field.svg | clipart | 372702 | ok | 8/9814/23698/0/0/0/0/0/0/0/0 | 1122.52 × 793.70 | 8.72/103.67/1115.80/654.90 | 610,253.13 | 0.68495 | 否 |
| web-167 | clipart__sailboat-on-the-sea.svg | clipart | 621061 | ok | 1/15609/39613/0/0/0/0/0/0/0/0 | 1962.69 × 1573.84 | 0.00/0.00/1962.69/1573.84 | 3,088,957.68 | 1.00000 | 是 |
| web-168 | clipart__salamander-3.svg | clipart | 144502 | ok | 60/1403/3884/56/0/0/0/0/0/0/0 | 1301.00 × 728.00 | 92.11/47.47/1166.78/658.86 | 657,038.53 | 0.69372 | 否 |
| web-169 | clipart__sax.svg | clipart | 290533 | ok | 31/6982/16937/1/5/5/0/0/0/0/0 | 793.70 × 1122.52 | -6.43/-7.27/802.16/1131.48 | 920,777.71 | 1.03348 | 是 |
| web-170 | clipart__scary-dragon-from-fairy-tales-for-boys-a.svg | clipart | 167324 | ok | 1/4048/10100/0/0/0/0/0/0/0/0 | 1820.00 × 975.56 | 54.85/80.89/1767.23/905.86 | 1,412,668.92 | 0.79564 | 否 |
| web-171 | clipart__semi-nude-woman-seated-drawing-by-ananda.svg | clipart | 220269 | ok | 1/4854/13589/0/0/0/0/0/0/0/0 | 816.00 × 1088.00 | 109.44/219.02/667.08/820.36 | 335,333.40 | 0.37771 | 否 |
| web-172 | clipart__shouting-monday-monster-cartoon.svg | clipart | 56172 | ok | 12/949/2628/2/0/0/0/0/0/0/0 | 551.47 × 1109.63 | 0.00/-0.00/551.47/1109.63 | 611,932.07 | 1.00000 | 是 |
| web-173 | clipart__sicily-triskelion.svg | clipart | 57102 | ok | 123/941/1876/122/0/0/0/0/0/0/0 | 700.00 × 700.00 | 25.00/6.28/677.16/689.02 | 445,258.06 | 0.90869 | 否 |
| web-174 | clipart__sleighride.svg | clipart | 300726 | ok | 1/9314/22936/0/0/0/0/0/0/0/0 | 998.00 × 712.00 | -0.07/-0.03/998.01/712.21 | 710,864.56 | 1.00041 | 是 |
| web-175 | clipart__slender-silver-fish-vintage-engraving.svg | clipart | 610328 | ok | 1/15529/37443/0/0/0/0/0/0/0/0 | 3165.33 × 908.00 | 160.97/96.35/3013.16/858.48 | 2,173,758.85 | 0.75632 | 否 |
| web-176 | clipart__smartphone-keyboard.svg | clipart | 50850 | ok | 42/437/813/41/0/0/0/0/0/0/0 | 640.00 × 341.97 | 0.00/0.00/640.00/341.97 | 218,859.39 | 1.00000 | 否 |
| web-177 | clipart__spainflag.svg | clipart | 226393 | ok | 628/6467/13022/378/0/0/0/0/0/0/0 | 800.00 × 533.33 | 0.00/0.00/800.00/533.33 | 426,666.73 | 1.00000 | 是 |
| web-178 | clipart__standing-rooster-with-curved-tail-outlin.svg | clipart | 97606 | ok | 59/605/1687/59/0/0/0/0/0/0/0 | 4459.56 × 5691.89 | 454.13/210.49/4039.95/5294.39 | 18,229,957.89 | 0.71819 | 否 |
| web-179 | clipart__starzinger-the-great-king-planet-version.svg | clipart | 83890 | ok | 314/4685/8316/1/0/0/0/23/0/0/0 | 793.70 × 1122.52 | -0.04/159.53/793.85/962.99 | 637,852.32 | 0.71593 | 是 |
| web-180 | clipart__steam-yacht-with-masts-at-sea-engraving.svg | clipart | 915764 | ok | 1/24967/57059/0/0/0/0/0/0/0/0 | 750.76 × 473.83 | 9.99/9.99/738.71/461.83 | 329,266.00 | 0.92560 | 否 |
| web-181 | clipart__steamboat-in-a-storm.svg | clipart | 1179778 | ok | 1/31450/73792/0/0/0/0/0/0/0/0 | 1748.00 × 1134.67 | -0.67/0.00/1748.23/1134.80 | 1,984,654.02 | 1.00063 | 是 |
| web-182 | clipart__stern-old-man-with-long-hair-line-art-po.svg | clipart | 104719 | ok | 1/2236/5856/0/0/0/0/0/0/0/0 | 742.67 × 749.33 | 33.33/23.77/712.00/721.77 | 473,710.66 | 0.85122 | 否 |
| web-183 | clipart__stop-racism-poster.svg | clipart | 98034 | ok | 22/2398/5747/0/0/0/0/0/0/0/0 | 793.70 × 1122.52 | 67.13/32.20/740.87/1042.75 | 680,853.12 | 0.76419 | 否 |
| web-184 | clipart__stopwatch-silhouette.svg | clipart | 7614 | ok | 3/241/630/0/0/0/0/0/0/0/0 | 2010.67 × 2584.00 | 8.85/12.69/1999.50/2571.11 | 5,092,915.21 | 0.98024 | 否 |
| web-185 | clipart__sturgeon-fish-vintage-engraving.svg | clipart | 3020494 | ok | 1/84565/204515/0/0/0/0/0/0/0/0 | 7126.67 × 2456.00 | 261.50/238.48/6865.16/2217.52 | 13,068,873.28 | 0.74666 | 否 |
| web-186 | clipart__sundial-outside-1646656037.svg | clipart | 897303 | ok | 1/26645/63747/0/0/0/0/0/0/0/0 | 1165.73 × 2173.23 | 0.00/35.64/1165.73/2173.23 | 2,491,842.06 | 0.98360 | 是 |
| web-187 | clipart__sunsetscene.svg | clipart | 875463 | ok | 3012/31596/75688/0/0/0/0/0/0/0/0 | 1333.33 × 933.33 | 0.00/0.00/1333.33/933.37 | 1,244,496.25 | 1.00004 | 是 |
| web-188 | clipart__suv-car.svg | clipart | 196529 | ok | 164/1621/3165/1/89/0/195/0/0/0/0 | 800.00 × 800.00 | 18.19/264.78/796.97/665.43 | 312,023.92 | 0.48754 | 否 |
| web-189 | clipart__take-out-garbage.svg | clipart | 1786576 | ok | 95/55275/143681/0/0/0/2/0/0/0/0 | 1066.67 × 800.00 | 0.00/0.00/1066.67/800.00 | 853,333.24 | 1.00000 | 否 |
| web-190 | clipart__the-girl-and-the-dog.svg | clipart | 112683 | ok | 1/2474/6488/0/0/0/0/0/0/0/0 | 507.52 × 296.32 | 12.05/6.97/495.98/285.23 | 134,657.89 | 0.89540 | 否 |
| web-191 | clipart__the-ship-sails-through-a-stormy-night.svg | clipart | 702435 | ok | 2/17261/40530/0/0/0/0/0/0/0/0 | 538.41 × 509.67 | 0.00/0.00/538.41/509.67 | 274,410.25 | 1.00000 | 否 |
| web-192 | clipart__three-headed-dragon-1.svg | clipart | 83057 | ok | 48/823/1655/44/0/38/0/0/0/0/0 | 454.87 × 338.79 | -0.29/-0.29/455.17/339.21 | 154,626.58 | 1.00339 | 是 |
| web-193 | clipart__tiny-living.svg | clipart | 56738 | ok | 18/1067/2759/0/0/0/0/0/0/0/0 | 603.58 × 1113.15 | 0.00/0.00/603.58/1113.15 | 671,869.37 | 1.00000 | 是 |
| web-194 | clipart__tour-de-marbault-medieval-tower-engravin.svg | clipart | 984921 | ok | 1/26667/61233/0/0/0/0/0/0/0/0 | 629.06 × 1206.56 | 0.00/0.04/629.06/1206.54 | 758,970.07 | 0.99996 | 是 |
| web-195 | clipart__tree38.svg | clipart | 205373 | ok | 432/7090/18898/0/0/0/0/0/0/0/0 | 2337.33 × 2509.33 | -0.00/0.00/2337.37/2509.33 | 5,865,248.52 | 1.00002 | 是 |
| web-196 | clipart__tree39.svg | clipart | 185679 | ok | 378/6450/17004/0/0/0/0/0/0/0/0 | 1638.67 × 2496.00 | -0.00/0.00/1638.67/2496.00 | 4,090,111.70 | 1.00000 | 是 |
| web-197 | clipart__tree41.svg | clipart | 172581 | ok | 370/5994/15964/0/0/0/0/0/0/0/0 | 2397.33 × 2509.33 | -0.00/0.00/2397.33/2509.33 | 6,015,708.05 | 1.00000 | 是 |
| web-198 | clipart__tree54.svg | clipart | 154475 | ok | 254/5388/14514/0/0/0/0/0/0/0/0 | 2084.00 × 2536.00 | -0.00/-0.00/2084.00/2536.00 | 5,285,024.00 | 1.00000 | 是 |
| web-199 | clipart__tree65.svg | clipart | 140133 | ok | 174/4796/13374/0/0/0/0/0/0/0/0 | 2508.00 × 2098.67 | -0.00/0.00/2508.00/2098.67 | 5,263,456.20 | 1.00000 | 是 |
| web-200 | clipart__tree70.svg | clipart | 202191 | ok | 368/6990/18598/0/0/0/0/0/0/0/0 | 2533.33 × 2026.67 | 0.00/0.00/2533.33/2026.67 | 5,134,221.49 | 1.00000 | 否 |
| web-201 | clipart__tree71.svg | clipart | 207473 | ok | 582/7032/17886/0/0/0/0/0/0/0/0 | 1648.00 × 2534.67 | -0.03/0.00/1647.97/2534.67 | 4,177,130.94 | 1.00000 | 是 |
| web-202 | clipart__tree72.svg | clipart | 271343 | ok | 360/9224/25456/0/0/0/0/0/0/0/0 | 2113.33 × 2530.67 | 0.00/0.00/2113.33/2530.67 | 5,348,141.41 | 1.00000 | 否 |
| web-203 | clipart__trippyjesus.svg | clipart | 3700859 | ok | 2/112057/251534/0/0/0/0/0/0/0/0 | 1209.90 × 1846.86 | 0.00/0.00/1209.90/1846.86 | 2,234,521.56 | 1.00000 | 是 |
| web-204 | clipart__vase-30.svg | clipart | 790314 | ok | 1/22924/51115/0/0/0/0/0/0/0/0 | 434.56 × 635.84 | 74.27/45.12/355.57/577.41 | 149,736.71 | 0.54191 | 否 |
| web-205 | clipart__vintage-car-race.svg | clipart | 159974 | ok | 1/4219/10041/0/0/0/0/0/0/0/0 | 874.54 × 344.30 | 0.00/-0.00/874.54/344.30 | 301,104.06 | 1.00000 | 是 |
| web-206 | clipart__vintage-caricature-of-a-man-in-a-suit.svg | clipart | 698309 | ok | 1/16545/42624/0/0/0/0/0/0/0/0 | 1550.00 × 2490.91 | 104.77/102.03/1459.31/2411.95 | 3,128,875.31 | 0.81040 | 否 |
| web-207 | clipart__vintage-engraving-of-men-by-the-sea.svg | clipart | 2966166 | ok | 1157/105701/259702/0/0/0/0/0/0/0/0 | 2379.00 × 1766.00 | -0.04/-0.03/2379.20/1766.00 | 4,201,804.36 | 1.00012 | 是 |
| web-208 | clipart__vintage-illustration-of-a-standing-cat.svg | clipart | 274528 | ok | 1/5978/15061/0/0/0/0/0/0/0/0 | 169.79 × 230.94 | 0.00/0.00/169.79/230.94 | 39,212.74 | 1.00000 | 是 |
| web-209 | clipart__vintage-poster-with-rosie-the-riveter.svg | clipart | 9728390 | ok | 22421/242497/596858/0/0/0/0/0/0/0/0 | 2318.00 × 3000.00 | 1.81/2.00/2320.00/3002.07 | 6,954,711.08 | 1.00010 | 是 |
| web-210 | clipart__vintage-sleigh-ride-with-horse-and-cupid.svg | clipart | 225816 | ok | 1/4888/12466/0/0/0/0/0/0/0/0 | 375.18 × 198.25 | 0.00/0.00/375.18/198.25 | 74,381.44 | 1.00000 | 否 |
| web-211 | clipart__walking-horse-with-raised-foreleg-engrav.svg | clipart | 569431 | ok | 1/14422/37245/0/0/0/0/0/0/0/0 | 3833.33 × 3746.67 | 104.80/88.69/3670.93/3611.66 | 12,563,377.01 | 0.87475 | 否 |
| web-212 | clipart__water-buffalo-on-hill-landscape-poster-l.svg | clipart | 223302 | ok | 216/6386/16537/26/63/123/0/0/0/0/0 | 2433.60 × 2957.50 | -22.19/-3.37/2433.58/2957.45 | 7,271,088.67 | 1.01024 | 是 |
| web-213 | clipart__waterfall-splash.svg | clipart | 8894 | ok | 18/177/284/0/0/0/0/0/0/0/0 | 880.00 × 880.00 | 0.64/0.34/880.30/880.00 | 773,804.28 | 0.99923 | 是 |
| web-214 | clipart__white-fairy-tale-castle-with-towers-and-.svg | clipart | 1125770 | ok | 1050/44077/93342/821/55/18/0/0/9/0/0 | 464.23 × 372.21 | 0.00/-0.01/463.73/373.08 | 173,010.21 | 1.00127 | 是 |
| web-215 | clipart__white-minibus-van-top-view.svg | clipart | 51888 | ok | 40/220/316/39/11/0/0/0/0/0/0 | 230.00 × 472.43 | -7.50/-7.83/239.00/479.93 | 120,232.84 | 1.10651 | 是 |
| web-216 | clipart__white-stork-in-flight-side-view.svg | clipart | 112302 | ok | 6/2670/5988/0/0/0/0/0/0/0/0 | 874.74 × 231.58 | 26.36/44.07/859.54/194.60 | 125,413.90 | 0.61911 | 否 |
| web-217 | clipart__whole-watermelon-and-slices.svg | clipart | 4409117 | ok | 9884/122701/254187/2/0/2/0/0/2/0/0 | 1800.00 × 1800.00 | -16.65/-24.42/1808.34/1779.32 | 3,291,799.01 | 1.01599 | 是 |
| web-218 | clipart__wild-rose-branch-with-bud-engraving.svg | clipart | 955281 | ok | 1/26341/63769/0/0/0/0/0/0/0/0 | 2860.00 × 3747.00 | 143.99/210.58/2544.45/3447.63 | 7,770,396.46 | 0.72509 | 否 |
| web-219 | clipart__woman-with-a-jug-on-her-head-at-a-city-g.svg | clipart | 1809615 | ok | 1/42943/111211/0/0/0/0/0/0/0/0 | 736.32 × 577.60 | 4.13/6.48/731.20/571.10 | 410,518.02 | 0.96525 | 否 |
| web-220 | clipart__woman-with-long-flowing-golden-hair-pane.svg | clipart | 94466 | ok | 6/2040/5064/0/0/0/0/0/0/0/0 | 265.62 × 778.49 | 0.00/0.00/265.62/778.49 | 206,785.95 | 1.00000 | 否 |
| web-221 | clipart__woman-xxxvi.svg | clipart | 4621459 | ok | 1/126670/284485/0/0/0/0/0/0/0/0 | 411.52 × 543.36 | -0.16/-0.07/411.59/543.36 | 223,755.46 | 1.00068 | 是 |
| web-222 | clipart__work-clown.svg | clipart | 247987 | ok | 115/4376/11690/0/2/0/0/0/0/0/0 | 684.03 × 1106.12 | 0.00/0.00/684.03/1106.12 | 756,626.31 | 1.00000 | 否 |
| web-223 | clipart__young-man-face-with-parted-hair-line-art.svg | clipart | 56843 | ok | 32/257/701/32/0/0/0/0/0/0/0 | 325.76 × 463.04 | 23.09/38.68/311.29/426.17 | 111,675.32 | 0.74036 | 否 |
| web-224 | clipart__young-person-with-wavy-hair-profile-line.svg | clipart | 88680 | ok | 66/497/1353/66/0/0/0/0/0/0/0 | 463.04 × 514.56 | 88.05/62.59/385.90/477.48 | 123,576.51 | 0.51866 | 否 |
| web-225 | clipart__young-shepherd-with-staff-and-sheep-engr.svg | clipart | 1822785 | ok | 1/47372/113994/0/0/0/0/0/0/0/0 | 487.83 × 555.23 | 0.00/0.00/487.83/555.23 | 270,857.94 | 1.00000 | 是 |
| web-226 | diagram__ALADI-Diagram-pt.svg | diagram | 1978612 | ok | 3375/28309/60463/910/34/241/1159/0/0/1/0 | 1413.59 × 925.35 | -41.75/-36.75/1455.34/967.10 | 1,502,853.63 | 1.14891 | 是 |
| web-227 | diagram__Blueprint-Barnstar.svg | diagram | 79013 | ok | 196/982/848/196/0/0/0/0/0/0/0 | 630.00 × 585.19 | -28.97/-69.07/717.72/696.95 | 571,983.05 | 1.55148 | 是 |
| web-228 | diagram__Coradir-TITO-selection-flowchart-es.svg | diagram | 99093 | ok | 126/611/694/64/0/0/0/0/0/0/0 | 793.70 × 1122.52 | 0.00/0.00/793.70/1122.52 | 890,942.56 | 1.00000 | 否 |
| web-229 | diagram__DART-UML-DART-2011-2013-RAW.svg | diagram | 125562 | ok | 193/1081/1116/101/0/0/0/0/0/0/0 | 18822.05 × 9524.41 | 91.06/2478.63/18593.74/9379.41 | 127,683,039.70 | 0.71224 | 否 |
| web-230 | diagram__Earth-cutaway-schematic-green-fr.svg | diagram | 58566 | ok | 83/457/920/35/1/1/0/0/0/0/0 | 1401.65 × 936.81 | 49.49/20.08/1101.89/872.71 | 897,307.76 | 0.68336 | 否 |
| web-231 | diagram__Earth-cutaway-schematic-eu.svg | diagram | 54378 | ok | 83/457/920/35/1/0/0/0/0/0/0 | 1280.00 × 900.00 | 59.75/48.37/1046.37/847.71 | 788,648.75 | 0.68459 | 否 |
| web-232 | diagram__Endomembrane-system-diagram-pt.svg | diagram | 292696 | ok | 315/6705/16332/10/83/3/0/0/0/0/0 | 612.00 × 485.98 | 0.00/0.00/612.00/485.98 | 297,419.74 | 1.00000 | 是 |
| web-233 | diagram__Felt-Strip-for-Master-CU-Architecture.svg | diagram | 185950 | ok | 387/1527/2356/380/195/0/0/0/0/0/0 | 284.46 × 567.93 | 0.00/0.00/284.46/567.93 | 161,553.36 | 1.00000 | 否 |
| web-234 | diagram__Haber-Bosch-En.svg | diagram | 901670 | ok | 201/52050/52199/26/15/16/2/0/0/0/0 | 3000.00 × 900.00 | 22.79/38.00/2965.66/864.43 | 2,432,071.92 | 0.90077 | 否 |
| web-235 | diagram__Network-in-Network-architecture-vs-VGG-a.svg | diagram | 327074 | ok | 389/6134/12479/101/0/0/12/0/0/0/0 | 682.67 × 620.00 | -1.33/9.45/683.50/620.32 | 418,338.56 | 0.98839 | 是 |
| web-236 | diagram__P-architecture-green.svg | diagram | 791797 | ok | 2/26749/64103/0/1/0/0/0/0/0/0 | 400.00 × 360.00 | -41.48/-49.04/441.48/409.03 | 221,227.92 | 1.53631 | 是 |
| web-237 | diagram__Platform-tomb.svg | diagram | 1624306 | ok | 957/44626/114740/956/0/0/0/0/0/0/0 | 900.00 × 1872.00 | 100.30/79.74/760.98/1829.77 | 1,156,218.84 | 0.68626 | 否 |
| web-238 | diagram__Reactor-Pattern-UML-2-Component-Diagram.svg | diagram | 154550 | ok | 365/7237/14183/39/0/0/13/0/0/0/0 | 697.28 × 514.56 | 8.00/1.00/694.87/512.25 | 351,157.21 | 0.97872 | 否 |
| web-239 | diagram__Schematic-diagram-of-the-human-eye-pl.svg | diagram | 318280 | ok | 368/1637/3541/287/11/14/0/0/0/0/0 | 447.85 × 423.47 | -30.95/-69.66/462.85/443.22 | 253,256.34 | 1.33538 | 是 |
| web-240 | diagram__Schematic-diagram-of-the-human-eye-ru.svg | diagram | 271072 | ok | 368/1637/3541/287/11/14/0/0/0/0/0 | 448.57 × 423.47 | -35.39/-68.41/458.40/444.47 | 253,256.32 | 1.33323 | 是 |
| web-241 | diagram__Schematic-diagram-of-the-human-eye-tr.svg | diagram | 319717 | ok | 368/1637/3547/287/11/14/0/0/0/0/0 | 416.16 × 423.47 | -39.00/-68.41/454.80/444.47 | 253,256.33 | 1.43705 | 是 |
| web-242 | diagram__Schematic-of-the-composting-chamberCS.svg | diagram | 1409465 | ok | 2237/14835/13756/272/1/2/767/0/0/0/1 | 1200.00 × 627.77 | -5.23/0.00/1201.00/627.77 | 757,241.63 | 1.00520 | 是 |
| web-243 | diagram__SchematicAquiferXsection-pt.svg | diagram | 90817 | ok | 139/1263/2101/44/0/4/0/0/0/0/0 | 401.58 × 322.77 | -0.00/48.25/401.59/319.45 | 108,912.49 | 0.84025 | 是 |
| web-244 | diagram__Simple-blueprints.svg | diagram | 1819653 | ok | 5/46620/106254/0/0/0/0/0/0/0/0 | 2536.00 × 1670.67 | 0.00/0.00/2536.00/1670.67 | 4,236,810.81 | 1.00000 | 否 |
| web-245 | diagram__Wikidata-Architecture-Overview-Dumps.svg | diagram | 54669 | ok | 33/2138/3325/11/0/0/1/0/0/0/0 | 960.00 × 540.00 | 0.00/0.00/960.00/540.00 | 518,400.00 | 1.00000 | 否 |
| web-246 | diagram__Wikimedia-evolving-architecture-expanded.svg | diagram | 203697 | ok | 625/13329/27086/76/0/0/0/0/0/0/3 | 1756.52 × 1327.89 | 16.07/-30.57/1776.07/1329.43 | 2,393,600.03 | 1.02621 | 是 |
| web-247 | diagram__x.svg | diagram | 322443 | ok | 368/1637/3547/287/11/14/0/0/0/0/0 | 416.16 × 423.47 | -39.00/-68.37/454.80/444.50 | 253,256.35 | 1.43705 | 是 |
| web-248 | effect__2021-Uzbek-presidential-election-logo.svg | effect | 85888 | ok | 5/667/1163/1/0/0/4/0/0/2/0 | 347.71 × 150.36 | 0.00/0.00/347.71/150.35 | 52,278.64 | 0.99998 | 否 |
| web-249 | effect__2025-Germany-AfD-gradient.svg | effect | 113797 | ok | 17/8663/8626/16/1/0/0/0/0/0/0 | 591.50 × 800.50 | 0.00/-0.00/591.50/800.51 | 473,502.61 | 1.00000 | 是 |
| web-250 | effect__4a-PubChemLiteEXPOSOMICS-slight-blue-gra.svg | effect | 93089 | ok | 136/2200/5392/1/8/0/0/0/0/0/0 | 1089.06 × 263.95 | 1.00/-17.00/1088.06/262.95 | 304,318.77 | 1.05867 | 是 |
| web-251 | effect__Bremen-in-Germany-relief-shade.svg | effect | 6841608 | ok | 862/54256/61123/237/0/2/0/0/0/1/0 | 1073.38 × 1271.95 | -6.00/-3.00/1079.38/1277.95 | 1,390,322.03 | 1.01833 | 是 |
| web-252 | effect__Csv-2d-gaussian-multivarate-distribution.svg | effect | 1867541 | ok | 5079/21182/22366/5010/0/0/5/0/0/0/0 | 681.33 × 498.67 | 6.64/6.72/673.37/491.38 | 323,133.48 | 0.95107 | 否 |
| web-253 | effect__DC-Shadow-House-2024.svg | effect | 741428 | ok | 154/60368/60367/0/0/0/0/0/0/0/0 | 635.17 × 744.59 | -242.95/-26.12/880.61/768.88 | 893,229.75 | 1.88867 | 是 |
| web-254 | effect__DC-Shadow-Representative-Map-2018-fixed.svg | effect | 349156 | ok | 17/20960/20951/15/0/0/0/0/0/0/0 | 635.17 × 744.59 | -242.95/-26.12/880.61/768.88 | 893,229.75 | 1.88867 | 是 |
| web-255 | effect__DC-Shadow-Senator-Map-2012.svg | effect | 247512 | ok | 17/20052/20051/15/0/0/0/0/0/0/0 | 635.88 × 745.26 | -242.58/-25.78/880.98/769.22 | 893,229.81 | 1.88488 | 是 |
| web-256 | effect__EKT-plot.svg | effect | 85384 | ok | 132/3298/3296/130/0/0/20/0/0/0/0 | 740.71 × 484.20 | -0.36/-0.00/743.67/520.77 | 387,469.84 | 1.08035 | 是 |
| web-257 | effect__Exuma-and-Cays-in-Bahamas-zoom-glow.svg | effect | 824597 | ok | 1902/35903/54374/813/0/3/0/0/0/0/0 | 1559.07 × 1124.34 | -3.52/-7.40/1559.07/1127.85 | 1,773,939.41 | 1.01199 | 是 |
| web-258 | effect__Gauss-prime-numbers.svg | effect | 106793 | ok | 147/2365/3398/76/0/0/0/0/0/0/0 | 229.00 × 259.00 | -4.00/-4.00/233.04/263.09 | 63,310.05 | 1.06743 | 是 |
| web-259 | effect__Home-usage-of-Taiwanese-by-district-in-T.svg | effect | 1466301 | ok | 713/111370/110659/713/0/0/0/0/0/0/0 | 960.00 × 1300.00 | 0.00/-77.90/952.30/1251.00 | 1,265,511.46 | 1.01403 | 是 |
| web-260 | effect__Inkscape-0-48-2-with-Red-Gallardo.svg | effect | 467597 | ok | 706/4079/5554/426/229/22/7/0/2/0/9 | 3784.00 × 2424.00 | 0.00/0.00/3784.00/2497.41 | 9,450,210.19 | 1.03029 | 是 |
| web-261 | effect__Internet-Access-by-Country-2017.svg | effect | 3478372 | ok | 240/94424/92903/235/1/0/0/0/0/0/0 | 816.00 × 510.00 | 0.00/0.00/816.00/510.00 | 416,160.00 | 1.00000 | 否 |
| web-262 | effect__Late-Harappan-sites-near-Haryana.svg | effect | 2062294 | ok | 2107/15969/30949/1118/0/0/4/0/0/1/0 | 695.19 × 675.23 | -67.00/-77.54/762.92/752.38 | 688,764.98 | 1.46728 | 是 |
| web-263 | effect__Meat-consumption-rate-kg-per-capita-by-c.svg | effect | 3479021 | ok | 5113/101429/97187/5085/0/0/0/0/0/0/0 | 1706.67 × 853.33 | -1.50/-1.50/1708.17/853.33 | 1,461,479.67 | 1.00352 | 是 |
| web-264 | effect__Oxygen480-apps-kformula.svg | effect | 58293 | ok | 54/2028/4611/0/44/10/0/33/35/0/0 | 128.00 × 128.00 | -2.94/-3.64/142.83/137.85 | 20,624.57 | 1.25882 | 是 |
| web-265 | effect__Portuguese-Native-Language-Gradient-2.svg | effect | 1255966 | ok | 2289/31586/89218/2224/0/0/0/0/0/0/0 | 2754.00 × 1398.00 | 1.32/0.78/2753.20/1396.81 | 3,841,725.93 | 0.99783 | 否 |
| web-266 | effect__Rennell-and-Bellona-Province-in-Solomon-.svg | effect | 221423 | ok | 379/7098/15855/200/0/1/0/0/0/0/0 | 1889.76 × 1086.58 | 0.00/0.00/1889.76/1086.76 | 2,053,718.29 | 1.00016 | 是 |
| web-267 | effect__Serial-endosymbiosis.svg | effect | 2185880 | ok | 3616/44073/76963/2084/2059/12/7/0/0/0/0 | 1080.00 × 1560.00 | -230.00/-70.40/2229.54/1538.06 | 3,956,061.56 | 2.34809 | 是 |
| web-268 | effect__Shadow-picture-of-Miyagino-ku-Sendai-cit.svg | effect | 62638 | ok | 5/3650/3645/0/0/0/0/0/0/0/0 | 597.57 × 452.64 | 0.00/0.00/597.57/452.64 | 270,484.97 | 1.00000 | 是 |
| web-269 | effect__Shadow-logo.svg | effect | 66468 | ok | 9/2703/3653/0/9/0/0/1/0/0/0 | 80.00 × 18.00 | -1.00/-1.23/81.33/20.78 | 1,812.21 | 1.25848 | 是 |
| web-270 | effect__Snam-Logo.svg | effect | 54231 | ok | 3/164/371/0/0/0/5/0/0/0/1 | 768.00 × 768.00 | 21.73/21.81/746.27/746.19 | 524,837.32 | 0.88982 | 否 |
| web-271 | effect__Star-Wars-Rise-of-the-Resistance-logo.svg | effect | 83929 | ok | 12/1784/4428/0/0/0/0/0/0/0/0 | 1636.98 × 315.65 | 0.00/0.00/1636.98/315.65 | 516,708.10 | 1.00000 | 否 |
| web-272 | effect__Wiki-slope-in-2d.svg | effect | 51941 | ok | 44/1280/3373/12/0/0/0/0/0/0/0 | 280.80 × 302.70 | 4.00/3.76/276.97/298.70 | 80,507.32 | 0.94717 | 否 |
| web-273 | effect__Wikipedia-chat-favicon.svg | effect | 213666 | ok | 8/59/91/0/0/0/0/0/0/3/0 | 415.00 × 415.00 | -37.00/-20.00/452.00/451.00 | 230,319.00 | 1.33731 | 是 |
| web-274 | effect__Window-function-and-frequency-response-C.svg | effect | 164304 | ok | 105/8484/8480/101/0/43/0/0/0/0/0 | 1200.00 × 600.00 | 0.00/0.00/1200.00/600.00 | 720,000.00 | 1.00000 | 否 |
| web-275 | effect__Window-function-and-frequency-response-G.svg | effect | 161344 | ok | 97/8472/8468/93/0/39/0/0/0/0/0 | 1200.00 × 600.00 | 0.00/0.00/1200.00/600.00 | 720,000.00 | 1.00000 | 否 |
| web-276 | emoji__noto-emoji-2D-svg-emoji-u1f469-1f3ff-200.svg | emoji | 4536 | ok | 13/127/272/0/3/0/0/0/0/0/0 | 128.00 × 128.00 | 12.53/2.87/115.46/124.03 | 12,471.00 | 0.76117 | 否 |
| web-277 | emoji__noto-emoji-2D-svg-emoji-u1f469-200d-2708.svg | emoji | 11218 | ok | 38/351/705/0/5/1/1/0/0/0/0 | 128.00 × 128.00 | 11.49/3.92/116.52/123.96 | 12,607.80 | 0.76952 | 否 |
| web-278 | emoji__noto-emoji-2D-svg-emoji-u1f477-1f3fb-200.svg | emoji | 8587 | ok | 23/178/359/0/8/2/2/0/0/0/0 | 128.00 × 128.00 | 12.00/4.18/116.00/124.14 | 12,475.84 | 0.76146 | 否 |
| web-279 | emoji__noto-emoji-2D-svg-emoji-u1f5ff.svg | emoji | 6279 | ok | 21/219/524/0/0/0/0/0/0/0/0 | 128.00 × 128.00 | 20.19/3.95/106.37/124.45 | 10,385.28 | 0.63387 | 否 |
| web-280 | emoji__noto-emoji-2D-svg-emoji-u1f9d6-1f3fd.svg | emoji | 14592 | ok | 34/323/699/0/17/4/0/0/0/0/0 | 128.00 × 128.00 | 4.00/3.91/124.00/123.92 | 14,401.20 | 0.87898 | 否 |
| web-281 | emoji__noto-emoji-2D-svg-emoji-u23ed.svg | emoji | 49960 | ok | 4/59/111/0/0/1/0/0/0/0/0 | 128.00 × 128.00 | 4.00/4.00/124.00/124.00 | 14,400.00 | 0.87891 | 否 |
| web-282 | emoji__openmoji-black-svg-1F468-1F3FD-200D-1F69.svg | emoji | 8675 | ok | 16/283/641/0/0/0/0/0/0/0/0 | 72.00 × 72.00 | 15.79/6.20/66.22/58.92 | 2,658.23 | 0.51278 | 否 |
| web-283 | emoji__openmoji-color-svg-1F3DD.svg | emoji | 9159 | ok | 34/174/361/30/0/0/0/0/0/0/0 | 72.00 × 72.00 | 1.50/6.00/70.00/59.06 | 3,634.57 | 0.70111 | 否 |
| web-284 | emoji__openmoji-color-svg-1F468-1F3FD-200D-1F3A.svg | emoji | 11498 | ok | 33/329/728/9/0/0/0/0/0/0/0 | 72.00 × 72.00 | 9.75/5.22/66.94/64.75 | 3,404.84 | 0.65680 | 否 |
| web-285 | emoji__openmoji-color-svg-1F468-1F3FE-200D-2708.svg | emoji | 9493 | ok | 33/321/685/0/0/0/0/0/0/0/0 | 72.00 × 72.00 | 15.73/7.99/55.86/58.94 | 2,044.19 | 0.39433 | 否 |
| web-286 | emoji__openmoji-color-svg-1F469-1F3FD-200D-1F3A.svg | emoji | 10833 | ok | 35/319/687/9/0/0/0/0/0/0/0 | 72.00 × 72.00 | 9.75/5.28/66.94/64.66 | 3,395.89 | 0.65507 | 否 |
| web-287 | emoji__openmoji-color-svg-1F469-200D-1F37C.svg | emoji | 10118 | ok | 22/256/622/12/0/0/0/0/0/0/0 | 72.00 × 72.00 | 14.08/3.31/59.51/69.89 | 3,025.33 | 0.58359 | 否 |
| web-288 | emoji__openmoji-src-extras-openmoji-healthcare-.svg | emoji | 35441 | ok | 19/1293/3463/4/0/0/0/0/0/0/0 | 72.00 × 72.00 | 0.00/0.00/72.00/72.00 | 5,184.00 | 1.00000 | 否 |
| web-289 | emoji__openmoji-src-people-body-person-role-1F4.svg | emoji | 8393 | ok | 41/376/740/15/0/0/0/0/0/0/0 | 72.00 × 72.00 | 0.00/0.00/72.00/72.00 | 5,184.00 | 1.00000 | 否 |
| web-290 | featured__AUT-Radmer-COA.svg | featured | 85089 | ok | 184/569/581/184/0/0/0/0/0/0/0 | 284.59 × 321.03 | -0.11/-0.11/284.70/321.14 | 91,496.60 | 1.00146 | 是 |
| web-291 | featured__Atmosphere-composition-diagram-en.svg | featured | 302184 | ok | 7292/70568/147901/980/50/106/0/0/0/0/0 | 2494.00 × 2189.00 | -50.90/0.00/2494.03/2189.10 | 5,571,106.36 | 1.02047 | 是 |
| web-292 | featured__Ceriale-Stemma.svg | featured | 1005701 | ok | 828/14075/34038/332/30/0/4/0/0/0/0 | 390.14 × 500.22 | -1.41/5.64/398.06/501.41 | 198,046.26 | 1.01481 | 是 |
| web-293 | featured__Climate-change-numbered.svg | featured | 243136 | ok | 285/18329/26499/102/1/0/0/0/0/1/0 | 600.00 × 582.00 | 0.00/0.00/600.00/582.00 | 349,200.00 | 1.00000 | 否 |
| web-294 | featured__Coat-of-arms-of-Konotop-Raion.svg | featured | 892661 | ok | 665/33764/69947/110/0/5/1/0/0/0/0 | 1203.00 × 1474.40 | 0.00/0.00/1203.00/1474.40 | 1,773,705.32 | 1.00000 | 是 |
| web-295 | featured__Coat-of-arms-of-Mgr-Fran-ois-Touvet.svg | featured | 139388 | ok | 493/1956/3925/474/0/0/0/0/0/0/0 | 1221.28 × 1295.44 | 0.00/-4.62/1221.28/1299.41 | 1,592,579.50 | 1.00663 | 是 |
| web-296 | featured__Corfu-topographic-map-en.svg | featured | 2296324 | ok | 348/19676/54456/309/0/0/0/0/0/1/0 | 2096.00 × 2341.00 | -30.50/-16.68/2114.72/2377.42 | 5,135,856.72 | 1.04670 | 是 |
| web-297 | featured__Delta-IV-class-SSBN.svg | featured | 966564 | ok | 1505/9673/17056/1141/135/0/0/0/0/0/0 | 1676.00 × 253.18 | 0.70/1.00/1675.00/252.18 | 420,547.17 | 0.99109 | 否 |
| web-298 | featured__Dolphin-class-submarine.svg | featured | 3866498 | ok | 4449/26572/56858/4449/0/1/0/0/0/0/0 | 576.77 × 196.93 | 1.21/1.34/575.24/195.57 | 111,491.52 | 0.98159 | 否 |
| web-299 | featured__Escut-de-Siurana.svg | featured | 244221 | ok | 574/1963/2614/574/0/0/0/0/0/0/0 | 603.24 × 836.28 | -3.88/-1.50/607.12/840.16 | 514,252.64 | 1.01937 | 是 |
| web-300 | featured__Fortepian-mechanizm-wiede-ski.svg | featured | 250740 | ok | 437/2042/3406/381/30/0/0/0/0/0/0 | 800.00 × 625.00 | 32.49/10.00/790.00/597.00 | 444,660.91 | 0.88932 | 否 |
| web-301 | featured__Grassy-grass-plant.svg | featured | 299033 | ok | 448/8416/13802/27/0/0/11/0/0/0/0 | 600.00 × 950.00 | -119.00/-58.02/563.59/933.22 | 676,609.41 | 1.18703 | 是 |
| web-302 | featured__HMS-Belfast-Boiler-diagram.svg | featured | 202438 | ok | 445/2381/4197/432/1/0/0/0/7/0/0 | 2276.88 × 1859.79 | 72.04/-5.21/2256.09/1860.52 | 4,074,842.50 | 0.96229 | 是 |
| web-303 | featured__Horse-anatomy.svg | featured | 150738 | ok | 272/3533/8040/265/77/43/0/0/104/0/0 | 2073.40 × 1629.40 | 69.48/32.13/1963.00/1530.69 | 2,837,553.95 | 0.83991 | 否 |
| web-304 | featured__Human-skull-side-bones.svg | featured | 126921 | ok | 232/4041/9291/43/3/65/0/0/0/0/0 | 552.25 × 377.78 | 0.00/0.00/552.25/377.78 | 208,630.66 | 1.00000 | 否 |
| web-305 | featured__Iran-provinces-and-counties-1956-English.svg | featured | 365578 | ok | 142/22708/24278/3/0/0/0/0/0/0/0 | 2212.76 × 2195.83 | 3.04/0.50/2209.72/2195.32 | 4,843,258.04 | 0.99679 | 否 |
| web-306 | featured__Isoglosas-gasc-n-oc-principales-ciudades.svg | featured | 268708 | ok | 104/6149/11462/41/0/0/0/0/0/0/0 | 402.00 × 548.00 | -2.00/-2.00/404.50/549.61 | 224,234.16 | 1.01788 | 是 |
| web-307 | featured__Jupiter-diagram.svg | featured | 1335503 | ok | 177/46276/113813/15/29/3/4/0/116/0/0 | 5000.00 × 2500.00 | -12742.67/-2237.10/16941.73/7888.45 | 300,570,895.03 | 24.04567 | 是 |
| web-308 | featured__Mamiya-645-Super-system.svg | featured | 554203 | ok | 28/164/266/22/0/0/0/0/0/1/0 | 1900.00 × 1300.00 | 0.00/0.00/1900.00/1300.00 | 2,470,000.00 | 1.00000 | 否 |
| web-309 | featured__Marine-sextant.svg | featured | 286547 | ok | 227/4781/12073/202/14/0/0/0/0/0/0 | 1201.55 × 1311.49 | -13.62/-10.57/1243.04/1341.38 | 1,698,942.96 | 1.07813 | 是 |
| web-310 | featured__Mountain-systems-of-Turkey.svg | featured | 669932 | ok | 1048/15836/39996/549/0/2/1/0/0/0/0 | 6257.95 × 2816.13 | -6257.95/-2816.13/6257.95/2816.13 | 70,492,725.81 | 4.00000 | 是 |
| web-311 | featured__Nautilus-diagram-en.svg | featured | 7186690 | ok | 20088/380831/1069691/18223/1111/431/647/806/359/64/2 | 2880.10 × 2117.60 | -304.30/-4600.10/3834.70/2117.60 | 27,804,560.70 | 4.55895 | 是 |
| web-312 | featured__Nervous-system-diagram-numbered.svg | featured | 488355 | ok | 584/2272/5085/577/7/0/0/0/0/0/0 | 300.50 × 605.50 | 17.15/4.18/271.71/591.20 | 149,428.99 | 0.82125 | 否 |
| web-313 | featured__Ospedaletti-Stemma.svg | featured | 986488 | ok | 1055/14403/33468/420/0/13/1/0/0/0/0 | 388.58 × 494.61 | -1.73/6.98/393.64/518.73 | 202,330.50 | 1.05275 | 是 |
| web-314 | featured__Phone.svg | featured | 189130 | ok | 120/4893/10678/7/30/3/27/0/60/0/0 | 685.30 × 1380.90 | -5.56/-2.25/723.58/1411.13 | 1,030,551.28 | 1.08900 | 是 |
| web-315 | featured__Rail-transport-infrastructure-map-DE-Ham.svg | featured | 1514056 | ok | 617/49151/92179/404/0/0/46/0/0/0/0 | 1209.33 × 1133.33 | -2.61/-13.04/1209.28/1173.73 | 1,438,233.44 | 1.04936 | 是 |
| web-316 | featured__Rotring-Rapidograph-0-35-mm-Technical-Pe.svg | featured | 294336 | ok | 120/1279/2306/109/26/0/0/0/0/0/0 | 637.80 × 124.02 | 35.74/37.03/602.23/86.81 | 28,199.15 | 0.35652 | 否 |
| web-317 | featured__SSBN598.svg | featured | 356740 | ok | 878/6708/14642/877/0/0/0/0/0/0/0 | 1444.15 × 338.67 | 0.67/0.75/1443.15/337.67 | 485,996.63 | 0.99368 | 否 |
| web-318 | featured__Scorpena-class-SSK-Kalvari-variant.svg | featured | 215758 | ok | 347/1970/3370/346/2/4/0/0/0/0/0 | 678.65 × 206.33 | 1.40/1.64/679.04/204.56 | 137,508.06 | 0.98201 | 是 |
| web-319 | featured__Titan-s-atmosphere.svg | featured | 1173018 | ok | 754/24107/55515/10/309/45/4/0/311/0/0 | 440.00 × 680.00 | -143.00/-4.00/429.41/670.18 | 385,905.66 | 1.28979 | 是 |
| web-320 | featured__Tourelle-pour-une-arme-mixte-et-un-morti.svg | featured | 255963 | ok | 389/2625/3686/387/0/8/0/0/0/0/0 | 423.53 × 679.05 | 10.00/10.00/413.53/669.05 | 265,947.71 | 0.92472 | 否 |
| web-321 | featured__ZenFone-6-Mockup.svg | featured | 71487 | ok | 128/2646/4878/0/83/6/0/1/0/0/0 | 896.38 × 2060.71 | 0.00/0.00/896.38/2060.71 | 1,847,184.75 | 1.00000 | 否 |
| web-322 | flag__flag-icons-flags-1x1-ad.svg | flag | 29142 | ok | 129/2387/4384/106/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-323 | flag__flag-icons-flags-1x1-bo.svg | flag | 104728 | ok | 672/6450/11103/433/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-324 | flag__flag-icons-flags-1x1-bt.svg | flag | 24503 | ok | 77/1400/3016/74/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-325 | flag__flag-icons-flags-1x1-bz.svg | flag | 42677 | ok | 99/3182/6294/85/4/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-326 | flag__flag-icons-flags-1x1-do.svg | flag | 41255 | ok | 106/4958/7041/45/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-327 | flag__flag-icons-flags-1x1-fj.svg | flag | 24137 | ok | 101/1957/3463/47/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-328 | flag__flag-icons-flags-1x1-fk.svg | flag | 28489 | ok | 65/1684/3132/52/10/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/515.79/512.00 | 264,082.62 | 1.00740 | 是 |
| web-329 | flag__flag-icons-flags-1x1-gs.svg | flag | 31922 | ok | 111/2222/3872/96/6/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-330 | flag__flag-icons-flags-1x1-gt.svg | flag | 31352 | ok | 139/2557/4421/102/11/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-331 | flag__flag-icons-flags-1x1-hr.svg | flag | 31280 | ok | 56/4813/9690/1/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-332 | flag__flag-icons-flags-1x1-me.svg | flag | 56953 | ok | 116/3976/9284/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-333 | flag__flag-icons-flags-1x1-sh-hl.svg | flag | 34779 | ok | 130/2287/4615/76/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-334 | flag__flag-icons-flags-1x1-sh-ta.svg | flag | 28290 | ok | 74/1946/4165/19/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-335 | flag__flag-icons-flags-1x1-sv.svg | flag | 77716 | ok | 884/7007/12679/824/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-336 | flag__flag-icons-flags-4x3-as.svg | flag | 30449 | ok | 70/1746/4697/0/0/0/0/0/0/0/0 | 640.00 × 480.00 | -0.60/0.00/640.20/480.00 | 307,584.36 | 1.00125 | 是 |
| web-337 | flag__flag-icons-flags-4x3-bt.svg | flag | 24784 | ok | 77/1401/3017/74/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.10/0.00/640.20/480.00 | 307,248.01 | 1.00016 | 是 |
| web-338 | flag__flag-icons-flags-4x3-es.svg | flag | 80958 | ok | 542/6317/9995/298/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-339 | flag__flag-icons-flags-4x3-hr.svg | flag | 30727 | ok | 56/4766/9591/1/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-340 | flag__flag-icons-flags-4x3-mx.svg | flag | 84753 | ok | 371/6945/12327/76/3/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-341 | flag__flag-icons-flags-4x3-rs.svg | flag | 181634 | ok | 461/54590/56730/43/0/0/1/0/0/0/0 | 640.00 × 480.00 | -0.00/0.00/640.00/480.00 | 307,196.19 | 0.99999 | 是 |
| web-342 | flag__flag-icons-flags-4x3-sh-ac.svg | flag | 74812 | ok | 466/5095/8389/0/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-343 | flag__flag-icons-flags-4x3-sh-hl.svg | flag | 35427 | ok | 130/2293/4710/76/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-344 | flag__flag-icons-flags-4x3-sh-ta.svg | flag | 28775 | ok | 74/1959/4212/19/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-345 | flag__flag-icons-flags-4x3-tm.svg | flag | 38349 | ok | 162/5629/5354/0/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-346 | flag__flag-icons-flags-4x3-va.svg | flag | 28720 | ok | 190/2183/4673/188/0/0/0/0/0/0/0 | 640.00 × 480.00 | 0.00/0.00/640.00/480.00 | 307,200.00 | 1.00000 | 否 |
| web-347 | game__Chamfer-triangular-tiling.svg | game | 206060 | ok | 2133/11250/10000/2133/0/0/0/0/0/0/0 | 1000.00 × 987.91 | 21.81/21.79/978.19/965.39 | 902,437.39 | 0.91348 | 否 |
| web-348 | game__Order-7-triakis-triangular-tiling.svg | game | 1241335 | ok | 8/268075/428929/0/0/0/0/0/0/0/0 | 2000.00 × 2000.00 | -165.75/-110.54/2100.96/2162.50 | 5,152,336.34 | 1.28808 | 是 |
| web-349 | game__S2-tiling-4color.svg | game | 54889 | ok | 256/3328/3072/256/0/0/0/0/0/0/0 | 1000.00 × 1000.00 | 23.12/23.12/976.88/976.88 | 909,670.03 | 0.90967 | 否 |
| web-350 | game__Snub-triheptagonal-tiling.svg | game | 1085674 | ok | 23/202557/393195/0/0/0/0/0/0/0/0 | 2000.00 × 2000.00 | -165.18/-110.11/2100.21/2161.83 | 5,146,850.01 | 1.28671 | 是 |
| web-351 | game__Square-radial-elongated-triangular-tilin.svg | game | 166777 | ok | 2207/9547/7340/2207/0/0/0/0/0/0/0 | 1000.00 × 952.44 | 23.31/21.68/976.69/930.76 | 866,703.42 | 0.90998 | 否 |
| web-352 | game__Tiling-3-6-dual-small.svg | game | 96403 | ok | 155/972/1613/88/0/0/0/0/0/0/0 | 584.66 × 584.66 | -397.99/-634.16/982.64/956.96 | 2,196,748.54 | 6.42654 | 是 |
| web-353 | game__Tiling-3-6-small.svg | game | 61490 | ok | 122/937/1805/39/0/0/0/0/0/0/0 | 584.66 × 584.66 | -511.37/-634.16/1096.03/956.96 | 2,557,568.99 | 7.48211 | 是 |
| web-354 | game__Tiling-great-rhombi-4-4-dual-simple.svg | game | 112791 | ok | 300/2599/3725/298/0/0/0/0/0/0/0 | 1039.37 × 1039.37 | -336.33/-336.33/1281.22/1281.22 | 2,616,465.15 | 2.42200 | 是 |
| web-355 | game__Tiling-small-rhombi-3-6.svg | game | 79165 | ok | 308/2090/3982/142/0/0/0/0/0/0/0 | 976.49 × 976.49 | -580.29/-207.16/1038.14/1153.06 | 2,201,439.46 | 2.30874 | 是 |
| web-356 | game__WEP-Nigeria-tile-logo.svg | game | 69302 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 1600.00 × 153.00 | 0.00/0.00/1600.00/153.00 | 244,800.00 | 1.00000 | 否 |
| web-357 | game__WEP-Portugal-tile-logo.svg | game | 96199 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 2600.00 × 240.00 | 0.00/0.00/2600.00/240.00 | 624,000.00 | 1.00000 | 否 |
| web-358 | game__WEP-Romania-tile-logo.svg | game | 69593 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 1700.00 × 153.00 | 0.00/0.00/1700.00/153.00 | 260,100.00 | 1.00000 | 否 |
| web-359 | game__kenney-Art-5190-files-Archive-500-assets.svg | game | 91935 | ok | 210/4204/4904/0/0/0/0/0/0/0/0 | 800.00 × 600.00 | 0.00/-155.90/800.00/600.00 | 604,720.00 | 1.25983 | 是 |
| web-360 | game__kenney-Art-5190-files-Boardgame-pack-480.svg | game | 71699 | ok | 158/3703/5275/0/0/0/0/0/0/0/0 | 1202.00 × 188.00 | 16.99/8.00/1202.00/188.00 | 213,302.06 | 0.94391 | 否 |
| web-361 | game__kenney-Art-5190-files-Boardgame-pack-480-2.svg | game | 71697 | ok | 158/3703/5275/0/0/0/0/0/0/0/0 | 1202.00 × 188.00 | 16.99/8.00/1202.00/188.00 | 213,302.06 | 0.94391 | 否 |
| web-362 | game__kenney-Art-5190-files-Boardgame-pack-480-3.svg | game | 71691 | ok | 158/3703/5275/0/0/0/0/0/0/0/0 | 1202.00 × 188.00 | 16.99/8.00/1202.00/188.00 | 213,302.06 | 0.94391 | 否 |
| web-363 | game__kenney-Art-5190-files-Boardgame-pack-480-4.svg | game | 71706 | ok | 158/3703/5275/0/0/0/0/0/0/0/0 | 1202.00 × 188.00 | 16.99/8.00/1202.00/188.00 | 213,302.06 | 0.94391 | 否 |
| web-364 | game__kenney-Art-5190-files-Boardgame-pack-480-5.svg | game | 388407 | ok | 7/19663/30703/0/0/0/0/0/0/0/0 | 1944.00 × 794.00 | 4.00/4.00/1944.00/794.00 | 1,532,600.00 | 0.99291 | 否 |
| web-365 | game__kenney-Art-5190-files-Boardgame-pack-480-6.svg | game | 86005 | ok | 39/4302/6751/0/0/0/0/0/0/0/0 | 1340.00 × 190.00 | 0.00/0.00/1340.00/190.00 | 254,600.00 | 1.00000 | 否 |
| web-366 | game__kenney-Art-5190-files-Hexagon-assets-170.svg | game | 99506 | ok | 400/4148/5415/0/40/0/0/0/0/0/0 | 825.00 × 639.00 | 10.00/10.00/825.00/639.00 | 512,635.00 | 0.97242 | 否 |
| web-367 | game__kenney-Art-5190-files-Hexagon-assets-170-2.svg | game | 80737 | ok | 537/3768/4190/0/0/0/0/0/0/0/0 | 1040.05 × 587.80 | 0.00/0.00/1040.05/587.80 | 611,341.41 | 1.00000 | 否 |
| web-368 | game__kenney-Art-5190-files-Medals-30-assets-V.svg | game | 50220 | ok | 163/2450/3290/0/0/0/0/0/0/0/0 | 540.45 × 329.50 | 20.80/156.75/540.45/329.50 | 89,769.54 | 0.50410 | 否 |
| web-369 | game__kenney-Art-5190-files-Onscreen-controls-.svg | game | 64159 | ok | 3/3681/5601/0/0/0/0/0/0/0/0 | 920.00 × 600.00 | 20.00/8.00/920.00/600.00 | 532,800.00 | 0.96522 | 否 |
| web-370 | game__kenney-Art-5190-files-Platformer-assets-.svg | game | 83248 | ok | 157/3053/7017/0/0/51/0/0/0/0/0 | 600.00 × 400.00 | 57.35/48.80/530.35/343.11 | 139,210.87 | 0.58005 | 否 |
| web-371 | game__kenney-Art-5190-files-Platformer-assets--2.svg | game | 108873 | ok | 418/6139/7534/0/4/0/0/0/0/0/0 | 1110.00 × 550.05 | 0.00/0.00/1110.00/550.05 | 610,555.49 | 1.00000 | 否 |
| web-372 | game__kenney-Art-5190-files-Platformer-assets--3.svg | game | 222733 | ok | 430/8972/15660/0/0/0/0/0/0/0/0 | 1103.00 × 560.02 | 40.00/40.20/1103.00/560.02 | 552,571.73 | 0.89456 | 否 |
| web-373 | game__kenney-Art-5190-files-Platformer-assets--4.svg | game | 165595 | ok | 382/7245/11663/0/0/0/0/0/0/0/0 | 1101.30 × 600.20 | -0.02/0.00/1101.30/600.20 | 661,015.62 | 1.00002 | 是 |
| web-374 | game__kenney-Art-5190-files-Platformer-assets--5.svg | game | 168700 | ok | 418/9448/12960/4/0/0/0/0/0/0/0 | 1110.00 × 550.25 | 0.00/3.00/1110.00/550.25 | 607,447.50 | 0.99455 | 否 |
| web-375 | game__kenney-Art-5190-files-Platformer-assets--6.svg | game | 268929 | ok | 192/19982/21672/0/0/0/0/0/0/0/0 | 1460.00 × 980.00 | 30.00/30.00/1460.00/980.00 | 1,358,500.00 | 0.94947 | 否 |
| web-376 | game__kenney-Art-5190-files-Puzzle-assets-80-a.svg | game | 123630 | ok | 371/4464/5631/0/26/4/0/0/0/0/0 | 800.00 × 480.00 | 0.00/0.00/800.00/480.00 | 384,000.00 | 1.00000 | 否 |
| web-377 | game__kenney-Art-5190-files-RPG-pack-230-asset.svg | game | 1080064 | ok | 1309/59393/78049/0/211/0/0/0/0/0/0 | 1277.00 × 832.00 | 0.00/0.00/1277.00/832.00 | 1,062,464.00 | 1.00000 | 否 |
| web-378 | game__kenney-Art-5190-files-Tappy-Plane-80-ass.svg | game | 456674 | ok | 492/24228/33356/0/3/0/0/0/0/0/0 | 1456.85 × 1543.95 | 15.05/20.05/1456.85/1543.95 | 2,197,158.91 | 0.97682 | 否 |
| web-379 | humaaans__humaaans-Flat-Assets-Humaaans-sitting-1.svg | humaaans | 9851 | ok | 12/163/363/0/0/0/0/0/0/0/0 | 380.00 × 400.00 | 18.00/17.00/327.00/385.00 | 113,712.00 | 0.74811 | 否 |
| web-380 | humaaans__humaaans-Flat-Assets-Humaaans-sitting-5.svg | humaaans | 11695 | ok | 14/193/411/0/0/0/0/0/0/0/0 | 380.00 × 400.00 | 39.00/52.74/295.84/377.00 | 83,281.87 | 0.54791 | 否 |
| web-381 | humaaans__humaaans-Flat-Assets-Humaaans-sitting-8.svg | humaaans | 8935 | ok | 14/155/311/0/0/0/0/0/0/0/0 | 380.00 × 400.00 | 9.00/48.00/303.00/383.00 | 98,490.00 | 0.64796 | 否 |
| web-382 | humaaans__humaaans-Flat-Assets-Humaaans-standing-1.svg | humaaans | 9222 | ok | 11/147/329/0/0/0/0/0/0/0/0 | 380.00 × 480.00 | 39.68/31.00/349.00/453.00 | 130,532.52 | 0.71564 | 否 |
| web-383 | humaaans__humaaans-Flat-Assets-Humaaans-standing-1-2.svg | humaaans | 6076 | ok | 10/110/207/0/0/0/0/0/0/0/0 | 380.00 × 480.00 | 66.56/56.02/304.75/453.00 | 94,555.26 | 0.51840 | 否 |
| web-384 | humaaans__humaaans-Flat-Assets-Humaaans-standing-1-3.svg | humaaans | 11467 | ok | 14/189/399/0/0/0/0/0/0/0/0 | 380.00 × 480.00 | 25.65/42.79/360.72/480.15 | 146,541.63 | 0.80341 | 是 |
| web-385 | humaaans__humaaans-Flat-Assets-Humaaans-standing-1-4.svg | humaaans | 8636 | ok | 13/138/282/0/0/0/0/0/0/0/0 | 380.00 × 480.00 | 46.59/43.11/331.30/478.49 | 123,959.34 | 0.67960 | 否 |
| web-386 | humaaans__humaaans-Flat-Assets-Humaaans-standing-2.svg | humaaans | 12444 | ok | 11/199/469/0/0/0/0/0/0/0/0 | 380.00 × 480.00 | 56.50/32.60/314.54/462.02 | 110,805.99 | 0.60749 | 否 |
| web-387 | humaaans__humaaans-Flat-Assets-Humaaans-standing-5.svg | humaaans | 7554 | ok | 11/123/247/0/0/0/0/0/0/0/0 | 380.00 × 480.00 | 51.96/42.54/321.53/462.25 | 113,143.99 | 0.62031 | 否 |
| web-388 | humaaans__humaaans-Flat-Assets-Humaaans-standing-6.svg | humaaans | 10086 | ok | 13/155/338/0/0/0/0/0/0/0/0 | 380.00 × 480.00 | 55.08/33.61/341.22/478.49 | 127,296.89 | 0.69790 | 否 |
| web-389 | humaaans__humaaans-Flat-Assets-Humaaans-standing-7.svg | humaaans | 8042 | ok | 12/123/253/0/0/0/0/1/0/0/0 | 380.00 × 480.00 | 27.65/34.72/362.72/470.48 | 146,007.08 | 0.80048 | 否 |
| web-390 | humaaans__humaaans-Flat-Assets-Single-Pieces-Botto.svg | humaaans | 4385 | ok | 6/75/162/0/0/0/0/0/0/0/0 | 300.00 × 239.00 | 49.00/-0.00/322.00/174.00 | 47,502.00 | 0.66251 | 是 |
| web-391 | humaaans__humaaans-Flat-Assets-Single-Pieces-Head-.svg | humaaans | 4792 | ok | 4/80/181/0/0/0/0/0/0/0/0 | 136.00 × 104.00 | 36.53/28.74/96.00/104.00 | 4,475.30 | 0.31641 | 否 |
| web-392 | humaaans__humaaans-Flat-Assets-Single-Pieces-Scene.svg | humaaans | 24632 | ok | 43/479/1125/1/0/2/0/0/0/0/0 | 740.00 × 680.00 | 16.00/0.00/707.00/610.00 | 421,510.00 | 0.83766 | 否 |
| web-393 | humaaans__humaaans-Flat-Assets-Single-Pieces-Scene-2.svg | humaaans | 87219 | ok | 117/1323/3575/0/0/9/0/0/0/0/0 | 740.00 × 680.00 | 44.54/64.30/696.00/617.00 | 360,062.92 | 0.71555 | 否 |
| web-394 | illustration__A-illustration-of-Dancheong.svg | illustration | 109830 | ok | 170/1276/2130/4/17/0/0/0/2/0/0 | 326.00 × 158.00 | 1.22/2.19/324.95/156.56 | 49,973.73 | 0.97021 | 否 |
| web-395 | illustration__Australian-Cattle-Dog-Origins-Diagram.svg | illustration | 1752954 | ok | 97/530/601/82/0/29/6/0/0/15/0 | 1131.00 × 1807.00 | 109.50/0.00/1015.50/1807.00 | 1,637,142.00 | 0.80106 | 否 |
| web-396 | illustration__Blank-Worksheets-for-Chinese-Character-C.svg | illustration | 1127451 | ok | 2574/5850/5616/2574/0/0/0/0/0/0/0 | 793.70 × 1122.52 | 32.92/36.17/766.67/1081.72 | 767,179.53 | 0.86109 | 否 |
| web-397 | illustration__Blank-Worksheets-for-Chinese-Character-C-2.svg | illustration | 1578917 | ok | 3465/7875/7560/3465/0/0/0/0/0/0/0 | 793.70 × 1122.52 | 52.82/60.51/751.73/1073.84 | 708,235.28 | 0.79493 | 否 |
| web-398 | illustration__BlankMap-USA-states-Canada-provinces-HI-.svg | illustration | 106027 | ok | 136/4404/11573/10/0/0/0/0/0/0/0 | 1730.00 × 1730.00 | 0.00/12.25/1721.64/1720.00 | 2,940,142.78 | 0.98237 | 否 |
| web-399 | illustration__Blason-Ch-teau-Arnoux-Saint-Auban.svg | illustration | 169398 | ok | 86/1651/3395/69/1/0/0/0/0/0/0 | 600.00 × 660.00 | -0.36/-0.98/600.00/660.10 | 396,883.21 | 1.00223 | 是 |
| web-400 | illustration__Cartoon-Woman-Dealing-With-Money-Excelle.svg | illustration | 185518 | ok | 104/4865/12715/4/0/1/5/0/0/0/0 | 816.00 × 1056.00 | 0.00/0.00/816.00/1056.00 | 861,695.84 | 1.00000 | 否 |
| web-401 | illustration__Chess-history-illustration-HY.svg | illustration | 107530 | ok | 711/5084/9711/82/0/42/0/0/0/0/0 | 1920.00 × 1080.00 | 90.29/75.96/1826.25/1004.04 | 1,611,109.80 | 0.77696 | 否 |
| web-402 | illustration__City-NIH-BioArt-825-795638.svg | illustration | 133894 | ok | 1/5919/12837/0/0/0/0/0/0/0/0 | 500.00 × 500.00 | 74.16/122.36/436.90/398.71 | 100,242.64 | 0.40097 | 否 |
| web-403 | illustration__City-after-earthquake.svg | illustration | 291281 | ok | 301/5631/12023/80/72/30/0/0/5/0/0 | 1064.78 × 891.13 | -6.76/-6.76/1045.88/872.23 | 925,255.59 | 0.97513 | 是 |
| web-404 | illustration__Coa-Illustration-Elements-Animal-Greyhou.svg | illustration | 128910 | ok | 83/2203/5959/0/0/0/1/0/0/0/0 | 301.50 × 227.43 | 4.50/2.65/297.00/224.78 | 64,973.34 | 0.94756 | 否 |
| web-405 | illustration__Coa-Illustration-Elements-Animal-Pelican.svg | illustration | 681378 | ok | 2/14532/41686/0/0/0/0/0/0/0/0 | 400.00 × 407.97 | 12.15/5.90/391.65/403.21 | 150,779.37 | 0.92397 | 否 |
| web-406 | illustration__DC-10-30-seat-configuration-chart.svg | illustration | 193755 | ok | 797/7424/12498/787/0/0/0/0/0/0/0 | 754.35 × 226.05 | 5.13/94.52/750.10/206.84 | 83,670.95 | 0.49068 | 否 |
| web-407 | illustration__DEU-Kienberg-COA.svg | illustration | 151659 | ok | 20/2701/7447/11/0/0/0/0/0/0/0 | 1007.39 × 1066.41 | 0.02/-0.00/1007.38/1066.39 | 1,074,239.84 | 0.99995 | 是 |
| web-408 | illustration__Denbigh-Castle-plan-labelled.svg | illustration | 383387 | ok | 654/2814/3822/484/0/0/0/0/3/0/0 | 889.70 × 979.28 | 0.00/-1061.73/2019.94/1040.79 | 4,246,958.17 | 4.87447 | 是 |
| web-409 | illustration__Dermatomes-unlabeled-male-back-3d-shaded.svg | illustration | 738197 | ok | 339/13523/38257/116/266/116/0/0/0/0/0 | 1814.00 × 785.03 | 6.02/5.92/1808.04/779.02 | 1,393,152.05 | 0.97831 | 否 |
| web-410 | illustration__Escudo-de-Cabanillas-del-Monte.svg | illustration | 2466805 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 733.33 × 1276.00 | 0.00/0.00/733.33/1276.00 | 935,734.34 | 1.00000 | 是 |
| web-411 | illustration__Falls-Church-Location.svg | illustration | 371060 | ok | 194/22708/22514/193/0/0/0/0/0/0/0 | 792.00 × 344.00 | 15.89/2.80/786.84/337.50 | 258,037.44 | 0.94711 | 否 |
| web-412 | illustration__Flag-of-Zeeland.svg | illustration | 128314 | ok | 32/2820/7199/21/0/0/0/0/0/0/0 | 600.18 × 399.58 | -0.00/-0.00/600.18/399.58 | 239,823.18 | 1.00000 | 是 |
| web-413 | illustration__Flag-of-the-Kingdom-of-Naples-1808-type-.svg | illustration | 504395 | ok | 677/19356/32646/268/0/35/0/0/0/0/0 | 900.00 × 600.00 | 0.00/0.00/900.00/600.00 | 540,000.00 | 1.00000 | 否 |
| web-414 | illustration__Gasparinisaura-Scale.svg | illustration | 140577 | ok | 226/1342/2925/199/0/196/0/0/0/0/0 | 1335.79 × 852.64 | -7469.45/-4205.32/6136.06/1067.20 | 71,735,305.01 | 62.98409 | 是 |
| web-415 | illustration__Hyrule-Compendium-for-Tears-of-the-Kingd.svg | illustration | 7772282 | ok | 9622/34079/34079/0/0/0/6/0/0/153/0 | 10240.20 × 15684.99 | 0.00/0.00/9468.90/15655.71 | 148,242,367.41 | 0.92295 | 否 |
| web-416 | illustration__Illex-argentinus-illustration-by-Mariana.svg | illustration | 126280 | ok | 9/30/34/5/0/0/0/0/0/1/0 | 793.70 × 1122.52 | 107.58/467.43/695.58/760.76 | 172,480.02 | 0.19359 | 否 |
| web-417 | illustration__Illustration-of-block-universe.svg | illustration | 256666 | ok | 474/2827/5556/419/0/4/0/0/0/0/0 | 458.63 × 559.25 | -0.00/0.00/458.63/559.25 | 256,486.44 | 1.00000 | 是 |
| web-418 | illustration__Iris-prismatica-illustration-1.svg | illustration | 264647 | ok | 80/13374/37834/0/0/0/0/0/0/0/0 | 3141.33 × 3893.33 | 69.27/18.78/3071.59/3834.67 | 11,456,516.66 | 0.93674 | 否 |
| web-419 | illustration__Kern-County-California-Incorporated-and-.svg | illustration | 220355 | ok | 119/6782/8574/119/0/0/0/0/0/0/0 | 2250.00 × 1050.00 | 16.92/27.05/2223.49/1027.56 | 2,207,696.86 | 0.93447 | 否 |
| web-420 | illustration__Map-Province-of-Teramo.svg | illustration | 1001295 | ok | 171/16251/47462/156/0/0/0/0/0/0/0 | 1200.00 × 1500.00 | 46.35/48.67/1133.40/1459.58 | 1,533,737.49 | 0.85208 | 否 |
| web-421 | illustration__Meda-Italia-Stemma.svg | illustration | 745032 | ok | 1097/13735/32275/678/595/288/0/0/0/0/0 | 419.00 × 502.00 | 0.49/-0.03/418.53/501.50 | 209,654.79 | 0.99675 | 是 |
| web-422 | illustration__Nej-ast-j-tahov-cesty-esk-ho-ptactva-do-.svg | illustration | 326568 | ok | 11/13871/37058/2/0/0/0/0/0/0/0 | 1880.80 × 1373.40 | -5212.68/-787.70/6826.59/5308.20 | 73,390,149.92 | 28.41176 | 是 |
| web-423 | illustration__Northern-California-Coastal-Forests-map.svg | illustration | 344867 | ok | 188/6198/16720/5/0/0/0/0/0/0/0 | 1711.67 × 1992.10 | 0.00/0.00/1711.67/2009.60 | 3,439,770.06 | 1.00878 | 是 |
| web-424 | illustration__Pine-needle-plaiting.svg | illustration | 137734 | ok | 88/4221/8129/0/0/0/0/0/0/0/0 | 724.73 × 420.12 | 1.99/-9.71/722.73/418.12 | 308,358.55 | 1.01276 | 是 |
| web-425 | illustration__Santa-Clara-County-California-Incorporat.svg | illustration | 329908 | ok | 172/11289/13028/172/0/0/0/0/0/0/0 | 1000.00 × 600.00 | 20.61/31.74/960.91/564.18 | 500,661.73 | 0.83444 | 否 |
| web-426 | illustration__Seagull-rising-with-fish.svg | illustration | 139156 | ok | 127/908/1942/42/10/0/0/0/0/0/0 | 666.67 × 613.33 | 0.00/0.00/654.52/612.48 | 400,876.83 | 0.98041 | 否 |
| web-427 | illustration__South-Australia-coat-of-arms-proposal-19.svg | illustration | 250401 | ok | 934/10495/23382/373/0/0/0/0/0/0/0 | 1097.63 × 1095.35 | 50.00/35.51/1047.64/1045.36 | 1,007,467.21 | 0.83796 | 否 |
| web-428 | illustration__Sutton-upon-Derwent-church-plan.svg | illustration | 130411 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 768.00 × 528.00 | 0.00/0.00/768.00/528.00 | 405,504.00 | 1.00000 | 否 |
| web-429 | illustration__Swift1-PSF.svg | illustration | 130287 | ok | 117/8939/23913/0/0/0/0/0/0/0/0 | 310.67 × 288.00 | 0.00/0.47/310.56/285.28 | 88,451.96 | 0.98860 | 否 |
| web-430 | illustration__VIIC-uboat-shaded.svg | illustration | 635665 | ok | 1838/15680/25642/1678/265/154/0/0/0/0/0 | 1763.00 × 928.00 | 2.00/2.00/1760.99/925.98 | 1,625,275.35 | 0.99341 | 否 |
| web-431 | illustration__Victor-Ion-Popa-Fedor-Mihailovici-Dostoi.svg | illustration | 132586 | ok | 2/2929/7957/0/0/0/0/0/0/0/0 | 400.00 × 547.22 | 0.00/0.00/400.00/547.20 | 218,880.00 | 0.99996 | 否 |
| web-432 | illustration__Welwyn-Garden-City-rail-crash-1935-illus.svg | illustration | 605256 | ok | 1/5/4/0/0/0/0/1/0/2/0 | 11754.00 × 3961.00 | 96.00/95.99/11728.00/3919.99 | 44,480,768.00 | 0.95539 | 否 |
| web-433 | illustration__White-stork-sketch.svg | illustration | 105311 | ok | 1/1927/4884/0/0/0/0/0/0/0/0 | 415.76 × 691.52 | 24.63/40.96/391.14/650.56 | 223,422.99 | 0.77710 | 否 |
| web-434 | illustration__Wikipe-tan-in-navy-uniform.svg | illustration | 276845 | ok | 304/3750/9327/137/0/0/0/0/0/0/0 | 830.00 × 2525.00 | 9.23/14.11/803.24/2520.74 | 1,990,281.64 | 0.94968 | 否 |
| web-435 | illustration__World-Trade-Center-Building-Design-with-.svg | illustration | 314849 | ok | 621/2672/2705/577/1/1/0/0/0/0/4 | 1306.00 × 980.00 | -3.00/-3.00/1309.01/983.00 | 1,293,648.90 | 1.01076 | 是 |
| web-436 | logo__logos-logos-chalk.svg | logo | 192767 | ok | 6/9448/8968/0/0/0/0/0/0/0/0 | 256.00 × 118.00 | 0.00/0.00/255.96/117.80 | 30,152.29 | 0.99816 | 否 |
| web-437 | logo__logos-logos-cloudacademy.svg | logo | 27960 | ok | 2/558/1244/0/0/0/0/0/0/0/0 | 512.00 × 75.00 | 0.00/-0.00/512.00/74.62 | 38,207.06 | 0.99498 | 是 |
| web-438 | logo__logos-logos-ember-tomster.svg | logo | 55595 | ok | 98/1677/4346/7/0/29/42/0/0/0/0 | 256.00 × 245.00 | 0.10/0.25/256.00/245.19 | 62,679.78 | 0.99936 | 是 |
| web-439 | logo__logos-logos-hadoop.svg | logo | 38535 | ok | 33/690/1672/0/0/0/0/0/0/0/0 | 256.00 × 192.00 | 0.95/0.07/255.95/191.12 | 48,720.35 | 0.99122 | 否 |
| web-440 | logo__logos-logos-haml.svg | logo | 22438 | ok | 3/415/995/0/0/0/0/0/0/0/0 | 256.00 × 316.00 | -0.00/0.00/255.09/315.76 | 80,548.55 | 0.99570 | 是 |
| web-441 | logo__logos-logos-homebrew.svg | logo | 24070 | ok | 7/590/1093/0/0/0/0/0/0/0/0 | 164.00 × 256.00 | 0.00/0.00/163.41/254.97 | 41,664.80 | 0.99240 | 否 |
| web-442 | logo__logos-logos-kimi-icon.svg | logo | 1154280 | ok | 2691/29526/65283/0/0/0/0/2691/0/0/0 | 256.00 × 256.00 | -7.26/0.00/258.16/256.06 | 67,963.40 | 1.03704 | 是 |
| web-443 | logo__logos-logos-leankit.svg | logo | 33717 | ok | 3/698/1500/0/0/0/0/0/0/0/0 | 512.00 × 158.00 | 0.00/0.00/511.89/157.27 | 80,503.02 | 0.99514 | 否 |
| web-444 | logo__logos-logos-model-context-protocol.svg | logo | 25808 | ok | 2/514/1143/0/0/0/0/0/0/0/0 | 512.00 × 69.00 | 0.00/0.00/512.00/68.67 | 35,159.02 | 0.99522 | 否 |
| web-445 | logo__logos-logos-postman.svg | logo | 21010 | ok | 22/453/876/0/0/0/0/0/0/0/0 | 512.00 × 156.00 | 0.00/0.00/512.00/155.36 | 79,546.12 | 0.99592 | 否 |
| web-446 | logo__logos-logos-processwire.svg | logo | 21790 | ok | 3/389/959/0/0/0/0/0/0/0/0 | 512.00 × 101.00 | -0.00/0.00/512.00/100.16 | 51,279.68 | 0.99164 | 是 |
| web-447 | logo__logos-logos-redux-observable.svg | logo | 30490 | ok | 24/357/852/0/24/0/0/0/0/0/0 | 256.00 × 250.00 | 0.00/-0.02/255.97/249.87 | 63,964.80 | 0.99945 | 是 |
| web-448 | logo__logos-logos-safari.svg | logo | 70316 | ok | 136/1776/3137/0/3/0/0/0/0/0/0 | 256.00 × 256.00 | -120.00/-122.00/376.00/374.00 | 246,016.00 | 3.75391 | 是 |
| web-449 | logo__logos-logos-travis-ci.svg | logo | 48129 | ok | 43/876/2100/0/0/0/0/0/0/0/0 | 256.00 × 254.00 | 0.00/0.48/255.27/253.69 | 64,635.81 | 0.99403 | 否 |
| web-450 | logo__logos-logos-wildfly.svg | logo | 85550 | ok | 13/1587/3816/0/0/6/0/0/0/0/0 | 512.00 × 152.00 | 0.00/0.00/511.36/151.29 | 77,363.89 | 0.99409 | 否 |
| web-451 | map__1998-Arizona-State-House-election.svg | map | 706244 | ok | 113/63725/63950/113/0/0/0/0/0/0/0 | 1406.23 × 966.00 | 18.52/0.00/1406.23/948.20 | 1,315,827.71 | 0.96865 | 否 |
| web-452 | map__2024-Indonesian-presidential-election-re.svg | map | 293913 | ok | 237/21123/20887/82/2/0/0/0/0/0/0 | 1600.00 × 980.00 | 24.80/24.80/1706.20/958.11 | 1,569,261.41 | 1.00080 | 是 |
| web-453 | map__Azerbaijan-SSR-in-Soviet-Union.svg | map | 259838 | ok | 370/8369/8350/368/0/0/0/0/0/0/0 | 591.99 × 376.06 | -19.38/-7.79/601.46/429.04 | 271,203.93 | 1.21821 | 是 |
| web-454 | map__Bari-Quartiere-Carbonara-di-Bari-locator.svg | map | 2372948 | ok | 597/192119/191511/303/0/0/0/0/0/0/0 | 1597.22 × 996.04 | 0.00/0.00/1597.22/996.04 | 1,590,899.06 | 1.00000 | 否 |
| web-455 | map__Bari-Quartiere-San-Paolo-locator-map.svg | map | 2372907 | ok | 597/192119/191511/303/0/0/0/0/0/0/0 | 1597.22 × 996.04 | 0.00/0.00/1597.22/996.04 | 1,590,899.06 | 1.00000 | 否 |
| web-456 | map__Blank-Map-Pacific-World.svg | map | 182119 | ok | 337/14634/17056/337/0/0/0/0/0/0/0 | 1576.00 × 1102.00 | 0.00/-0.00/1576.26/1102.40 | 1,737,671.07 | 1.00053 | 是 |
| web-457 | map__Botswana-National-Assembly-Tswapong-Sout.svg | map | 1105131 | ok | 73/70003/69939/73/0/1/0/0/0/0/0 | 1727.85 × 1727.85 | 103.00/32.84/1677.92/1712.35 | 2,645,102.32 | 0.88599 | 否 |
| web-458 | map__California-State-Route-56.svg | map | 517334 | ok | 798/15337/19287/342/0/0/0/0/0/0/0 | 1096.00 × 649.92 | -130.33/-183.15/1184.45/754.54 | 1,232,843.45 | 1.73076 | 是 |
| web-459 | map__Carreteras-de-Navarra-EU.svg | map | 2511023 | ok | 1929/272147/277347/1514/0/1/0/0/0/0/0 | 2318.12 × 2500.00 | -687.61/-692.61/2941.39/3356.65 | 14,694,809.89 | 2.53564 | 是 |
| web-460 | map__Derbyshire-UK-parish-map-highlighting-Oc.svg | map | 2458644 | ok | 299/188739/188141/290/0/0/2/0/0/0/0 | 888.42 × 1307.50 | -0.00/-7.82/896.24/1307.50 | 1,178,836.94 | 1.01483 | 是 |
| web-461 | map__Dionysia-lurorum-relief.svg | map | 4899371 | ok | 3156/100961/99479/1694/0/2/0/0/0/1/0 | 1560.00 × 946.00 | -443.52/-172.52/1964.52/1690.52 | 4,486,274.91 | 3.03998 | 是 |
| web-462 | map__EPCI-Pays-de-Spincourt.svg | map | 237831 | ok | 290/5754/12032/22/0/23/0/0/0/0/0 | 321.70 × 336.31 | 5.00/4.95/316.70/331.31 | 101,728.72 | 0.94026 | 否 |
| web-463 | map__England-and-Wales.svg | map | 1453749 | ok | 712/74377/76418/360/0/0/0/0/0/0/0 | 510.00 × 672.00 | -349.00/-590.79/537.40/778.64 | 1,213,858.17 | 3.54184 | 是 |
| web-464 | map__Erythrodiplax-berenice-map.svg | map | 842344 | ok | 883/43902/47253/882/0/0/0/0/0/0/0 | 1300.00 × 1100.00 | -0.50/-254.07/1300.47/1101.54 | 1,763,613.18 | 1.23330 | 是 |
| web-465 | map__European-countries-by-GDP-nominal-2020.svg | map | 636480 | ok | 70/14297/39807/68/0/0/1/0/0/0/0 | 680.00 × 520.00 | -221.58/-64.84/690.17/520.50 | 533,681.12 | 1.50928 | 是 |
| web-466 | map__Exeter-UK-local-election-2019-map.svg | map | 260528 | ok | 22/11884/15931/21/0/0/1/0/0/0/0 | 934.00 × 1187.00 | -50.81/-63.46/985.47/1250.03 | 1,361,130.02 | 1.22773 | 是 |
| web-467 | map__Flintshire-UK-community-map-blank.svg | map | 702820 | ok | 48/48448/50797/44/0/0/2/0/0/0/0 | 1177.00 × 1305.00 | 0.00/-2.50/1179.50/1305.00 | 1,542,196.25 | 1.00404 | 是 |
| web-468 | map__Intercommunalit-s-des-Vosges.svg | map | 766013 | ok | 1047/20854/34056/545/0/0/0/0/0/0/0 | 1015.78 × 597.74 | 4.86/4.86/1010.78/592.73 | 591,349.63 | 0.97395 | 否 |
| web-469 | map__International-recognition-of-the-State-o.svg | map | 1140214 | ok | 2278/29884/84454/2278/0/0/0/0/0/0/35 | 2754.00 × 1398.00 | 25.61/23.83/2738.04/1396.45 | 3,723,127.01 | 0.96702 | 否 |
| web-470 | map__Italia-mappa-autostrada-A29.svg | map | 881882 | ok | 595/48212/51165/369/0/0/0/0/0/0/0 | 1031.85 × 1297.56 | -4.77/-4.76/1036.63/1302.33 | 1,361,209.25 | 1.01666 | 是 |
| web-471 | map__Kokem-ki-parish-location-2022.svg | map | 1087946 | ok | 728/62800/100628/369/0/0/726/0/0/0/65 | 1750.00 × 2950.00 | -0.30/0.00/1749.70/2950.00 | 5,162,499.86 | 1.00000 | 是 |
| web-472 | map__Lianyungang-locator-map-in-Jiangsu.svg | map | 369479 | ok | 82/9885/28828/66/0/0/0/0/0/0/0 | 783.84 × 755.83 | -9.74/-62.82/790.67/763.19 | 661,145.48 | 1.11595 | 是 |
| web-473 | map__Malta-and-Pantelleria-highlighted-in-the.svg | map | 131225 | ok | 14/3965/7076/13/0/0/0/0/0/0/0 | 990.00 × 545.46 | -2.00/-8.00/990.51/548.46 | 552,292.28 | 1.02275 | 是 |
| web-474 | map__Map-Province-of-Reggio-Emilia.svg | map | 1034838 | ok | 177/16819/49024/162/0/0/0/0/0/0/0 | 1200.00 × 1500.00 | 46.35/48.67/1133.40/1459.58 | 1,533,737.49 | 0.85208 | 否 |
| web-475 | map__Map-of-A-ora-in-the-province.svg | map | 349562 | ok | 165/13909/13819/165/0/0/165/0/0/0/0 | 304.15 × 378.62 | -240.95/-18.32/546.25/398.55 | 328,165.09 | 2.84971 | 是 |
| web-476 | map__Map-of-Fern-n-N-ez-in-the-province.svg | map | 349268 | ok | 165/13909/13819/165/0/0/165/0/0/0/0 | 304.15 × 378.62 | -240.95/-18.32/546.25/398.55 | 328,165.09 | 2.84971 | 是 |
| web-477 | map__Map-of-Theatres-of-PLA-en.svg | map | 2423279 | ok | 2057/255915/260332/780/5/0/20/0/0/0/0 | 1181.00 × 940.00 | 0.00/0.00/1181.00/940.00 | 1,110,140.00 | 1.00000 | 否 |
| web-478 | map__Map-of-Tremezzina-Province-of-Como-regio.svg | map | 1896666 | ok | 281/105476/105465/264/0/0/0/0/0/0/0 | 1333.33 × 1333.33 | -154.05/-154.59/1486.91/1488.03 | 2,695,457.96 | 1.51619 | 是 |
| web-479 | map__Map-of-comune-of-Issime-region-Aosta-Val.svg | map | 141556 | ok | 75/7330/7255/75/0/0/0/0/0/0/0 | 522.00 × 342.57 | -1.00/-1.00/523.00/343.57 | 180,555.05 | 1.00969 | 是 |
| web-480 | map__Map-of-the-proposed-Sunni-Region.svg | map | 338779 | ok | 98/15677/36202/59/0/1/0/0/0/0/0 | 1241.00 × 1265.00 | -5.55/-5.16/1241.44/1265.00 | 1,583,876.90 | 1.00893 | 是 |
| web-481 | map__Massachusetts-Route-137-Map.svg | map | 5430929 | ok | 12530/219745/225456/11397/0/0/4/0/0/0/0 | 1027.50 × 608.75 | 0.00/0.00/1027.50/609.30 | 626,055.74 | 1.00090 | 是 |
| web-482 | map__ND-Williams-County-Epping.svg | map | 439936 | ok | 67/20616/20559/66/0/0/66/0/0/0/0 | 1056.00 × 816.00 | 1.28/0.00/1056.00/816.00 | 860,651.53 | 0.99879 | 否 |
| web-483 | map__NagoyaProtocol.svg | map | 1102627 | ok | 2287/30102/85057/2287/0/0/0/0/0/0/0 | 2754.00 × 1398.00 | 1.32/0.78/2753.20/1396.81 | 3,841,725.93 | 0.99783 | 否 |
| web-484 | map__Nem-ka-pomladna-ofenziva-1918.svg | map | 3837765 | ok | 1581/137848/273369/874/32/10/0/0/0/0/5 | 1592.60 × 986.01 | -2.02/-4.05/1592.10/988.31 | 1,581,940.48 | 1.00740 | 是 |
| web-485 | map__Roma-Municipio-VI-2001-2013-locator-map.svg | map | 496926 | ok | 21/32138/32314/21/0/0/0/0/0/0/0 | 1199.69 × 1249.04 | -2.93/-3.38/1203.06/1252.42 | 1,514,473.72 | 1.01069 | 是 |
| web-486 | map__Rome-subdivisions-locator-map-S-VIII-Gia.svg | map | 744592 | ok | 117/46850/46738/117/0/0/0/0/0/0/0 | 799.00 × 832.19 | -1.50/-1.50/800.50/833.69 | 669,823.04 | 1.00737 | 是 |
| web-487 | map__Tanintharyi-Region-in-Myanmar-2010.svg | map | 1008317 | ok | 155/29977/84017/139/0/0/0/0/0/0/0 | 1228.35 × 2003.17 | -60.33/-179.32/1316.85/2020.45 | 3,029,488.23 | 1.23120 | 是 |
| web-488 | map__Tarn-Cantons-Before-2014.svg | map | 310346 | ok | 374/8034/7669/374/0/0/0/0/0/0/0 | 1000.00 × 809.00 | -0.72/-0.79/1000.71/810.18 | 812,132.49 | 1.00387 | 是 |
| web-489 | map__Topographic-map-of-the-Messenia-Peloponn.svg | map | 5457634 | ok | 310/126300/124731/299/0/1/0/0/0/1/0 | 68525.75 × 101890.00 | -0.25/-137.05/68662.80/101890.00 | 7,005,489,051.21 | 1.00335 | 是 |
| web-490 | map__Wales-Bridgend-Community-Laleston-map.svg | map | 333456 | ok | 33/25933/28282/29/0/0/0/0/0/0/0 | 1273.00 × 1266.00 | -11.36/-6.50/1279.05/1273.09 | 1,651,190.75 | 1.02455 | 是 |
| web-491 | map__crh-visn-04-network-map-of-the-united-st.svg | map | 813563 | ok | 5/19206/50912/0/0/0/0/0/0/0/0 | 400.00 × 211.03 | 0.00/0.00/400.00/211.08 | 84,432.61 | 1.00024 | 是 |
| web-492 | map__crh-visn-17-map-of-united-states-with-ne.svg | map | 807325 | ok | 5/19051/50539/0/0/0/0/0/0/0/0 | 400.00 × 211.03 | 0.00/0.00/400.00/211.09 | 84,437.57 | 1.00030 | 是 |
| web-493 | map__down-map-sign.svg | map | 139794 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 27.46/71.40/451.21/554.60 | 204,758.42 | 0.66653 | 否 |
| web-494 | map__fermanagh-map-sign.svg | map | 57152 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 27.76/89.92/451.57/567.41 | 202,366.82 | 0.65875 | 否 |
| web-495 | map__hollow-planet-earth.svg | map | 2989348 | ok | 2/80433/193455/0/0/0/0/0/0/0/0 | 1587.40 × 1587.40 | 155.46/22.23/1442.32/1531.44 | 1,942,141.42 | 0.77074 | 否 |
| web-496 | map__kerry-map-sign.svg | map | 168124 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 14.84/69.08/467.51/552.26 | 218,720.09 | 0.71198 | 否 |
| web-497 | map__leitrim-map-sign.svg | map | 169890 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 10.87/64.98/468.48/567.34 | 229,883.95 | 0.74832 | 否 |
| web-498 | map__longford-map-sign.svg | map | 197145 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 13.85/65.99/466.50/558.35 | 222,865.80 | 0.72547 | 否 |
| web-499 | map__map-of-dublin-county.svg | map | 388124 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 567.00 × 911.00 | 0.00/0.00/567.00/911.00 | 516,537.00 | 1.00000 | 否 |
| web-500 | map__map-of-munster.svg | map | 324058 | ok | 0/0/0/0/0/0/1/0/0/1/0 | 640.00 × 800.00 | 71.31/69.67/489.37/581.81 | 214,105.70 | 0.41818 | 否 |
| web-501 | map__roscommon-map-sign.svg | map | 170280 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 11.84/63.97/468.50/568.37 | 230,339.12 | 0.74980 | 否 |
| web-502 | map__sligo-map-sign.svg | map | 213915 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 16.83/65.04/464.51/564.29 | 223,499.56 | 0.72754 | 否 |
| web-503 | map__south-america-map-color.svg | map | 72466 | ok | 60/1725/4465/0/0/0/1/0/0/0/0 | 800.00 × 800.00 | 217.12/84.47/583.28/721.45 | 233,235.74 | 0.36443 | 否 |
| web-504 | map__taipei-outline-map.svg | map | 216282 | ok | 34/4004/11477/32/0/3/1/0/0/0/0 | 793.70 × 1122.52 | 51.62/37.94/756.63/1054.12 | 716,418.49 | 0.80411 | 否 |
| web-505 | map__tipperary-map-sign.svg | map | 163601 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 14.85/83.93/465.49/568.41 | 218,327.87 | 0.71070 | 否 |
| web-506 | map__us-map-with-crh-network-dots-and-visn-06.svg | map | 811385 | ok | 5/19117/50765/0/0/0/0/0/0/0/0 | 400.00 × 211.03 | 0.00/0.00/400.00/211.09 | 84,434.59 | 1.00026 | 是 |
| web-507 | map__visn-15-crh-united-states-network-map.svg | map | 797580 | ok | 5/18807/49909/0/0/0/0/0/0/0/0 | 400.00 × 211.03 | 0.00/0.00/400.00/211.09 | 84,434.59 | 1.00026 | 是 |
| web-508 | map__visn-19-crh-united-states-network-map.svg | map | 798190 | ok | 5/18835/49971/0/0/0/0/0/0/0/0 | 400.00 × 211.03 | 0.00/0.00/400.00/211.09 | 84,434.59 | 1.00026 | 是 |
| web-509 | map__westmeath-map-sign.svg | map | 133484 | ok | 0/0/0/0/0/0/2/0/0/2/0 | 480.00 × 640.00 | 13.84/67.97/467.49/566.36 | 226,092.92 | 0.73598 | 否 |
| web-510 | mid__Atlantic-Records-fan-logo.svg | mid | 6005 | ok | 21/218/319/0/0/0/0/0/0/0/0 | 187.09 × 119.39 | 0.00/0.00/187.09/119.39 | 22,336.76 | 1.00000 | 否 |
| web-511 | mid__Badoo-2017-Logo-2.svg | mid | 8015 | ok | 2/142/353/0/0/0/0/0/0/0/0 | 1000.00 × 388.54 | 129.51/129.51/870.49/259.02 | 95,965.12 | 0.24699 | 否 |
| web-512 | mid__Bataysk-Flag-2025.svg | mid | 35585 | ok | 78/1605/2195/0/0/0/0/0/0/0/0 | 1200.00 × 800.00 | -0.00/0.00/1200.00/800.00 | 960,001.58 | 1.00000 | 是 |
| web-513 | mid__Flag-map-of-Hyogo-Prefecture.svg | mid | 11340 | ok | 4/525/637/0/0/0/0/0/0/0/0 | 23.88 × 35.03 | -0.00/0.00/23.87/35.03 | 836.37 | 1.00000 | 是 |
| web-514 | mid__Flag-map-of-Saga-Prefecture.svg | mid | 11785 | ok | 3/477/745/0/0/0/0/0/0/0/0 | 373.00 × 371.00 | 0.00/0.00/373.00/371.00 | 138,382.98 | 1.00000 | 否 |
| web-515 | mid__Flag-of-Soeda-Fukuoka.svg | mid | 6268 | ok | 69/297/551/64/0/0/0/0/0/0/0 | 300.00 × 200.00 | 0.00/0.00/300.00/200.00 | 60,000.00 | 1.00000 | 否 |
| web-516 | mid__Flag-of-the-American-Nazi-Party-1960s-20.svg | mid | 36878 | ok | 4/999/2179/0/0/0/0/0/0/0/0 | 400.00 × 240.00 | 0.00/0.00/400.00/240.00 | 96,000.00 | 1.00000 | 否 |
| web-517 | mid__Flag-map-of-New-Mexico.svg | mid | 6156 | ok | 4/27/33/3/0/0/1/0/0/0/0 | 1002.30 × 1114.50 | -0.01/-0.00/1002.29/1114.46 | 1,117,026.36 | 0.99997 | 是 |
| web-518 | mid__Google-Camera-Icon-November-2014-2017.svg | mid | 10260 | ok | 13/92/158/1/5/0/0/0/0/0/0 | 300.00 × 300.00 | -2.98/20.00/302.98/266.98 | 75,568.88 | 0.83965 | 是 |
| web-519 | mid__Google-Keep-icon-2015-2020.svg | mid | 5578 | ok | 12/206/296/0/2/2/0/0/0/0/0 | 6596.06 × 6592.51 | -41138.60/-41116.44/325463.56/325288.28 | 134,324,761,385.19 | 3089.02028 | 是 |
| web-520 | mid__International-Criminal-Court-logo.svg | mid | 41148 | ok | 33/783/1800/0/0/0/0/0/0/0/0 | 673.23 × 581.10 | 17.72/17.69/655.51/563.42 | 348,062.94 | 0.88970 | 否 |
| web-521 | mid__LGBT-flag-map-of-Kosovo.svg | mid | 6505 | ok | 6/296/293/0/0/0/0/0/0/0/0 | 738.62 × 818.62 | 0.00/0.00/738.62/818.62 | 604,656.89 | 1.00000 | 否 |
| web-522 | mid__LGBT-flag-map-of-Lebanon.svg | mid | 44106 | ok | 6/961/2714/0/0/0/0/0/0/0/0 | 790.61 × 971.78 | -0.00/-0.00/790.61/971.78 | 768,304.23 | 1.00000 | 是 |
| web-523 | mid__LGBT-flag-map-of-Lesotho.svg | mid | 13110 | ok | 6/735/727/0/0/0/0/0/0/0/0 | 654.41 × 561.00 | 0.00/0.00/654.41/561.00 | 367,121.94 | 1.00000 | 是 |
| web-524 | mid__LGBT-flag-map-of-Mauritania.svg | mid | 6707 | ok | 6/130/284/0/0/0/0/0/0/0/0 | 326.15 × 359.85 | 0.00/-0.00/326.15/359.85 | 117,364.03 | 1.00000 | 是 |
| web-525 | mid__LGBT-flag-map-of-Trinidad-and-Tobago.svg | mid | 9773 | ok | 6/517/511/0/0/0/0/0/0/0/0 | 634.44 × 586.59 | 0.00/0.00/634.44/586.59 | 372,157.07 | 1.00000 | 否 |
| web-526 | mid__Logo-of-the-Communist-Party-of-the-Russi.svg | mid | 24155 | ok | 6/1233/2437/1/0/0/0/0/0/0/0 | 290.91 × 325.61 | -0.04/-0.00/290.91/325.63 | 94,743.17 | 1.00021 | 是 |
| web-527 | mid__NATO-Map-Symbol-NATO-IFOR.svg | mid | 14688 | ok | 27/175/212/14/0/1/1/0/25/0/0 | 591.02 × 372.11 | -35.99/-19.88/627.01/391.99 | 273,072.54 | 1.24167 | 是 |
| web-528 | mid__NATO-Map-Symbol-NATO-Reaction-Force.svg | mid | 14695 | ok | 27/175/212/14/0/1/1/0/25/0/0 | 591.02 × 372.11 | -35.99/-19.88/627.01/391.99 | 273,072.54 | 1.24167 | 是 |
| web-529 | mid__OnStar-2D-logo-2016.svg | mid | 10208 | ok | 14/224/414/0/0/0/0/0/0/0/0 | 300.00 × 134.31 | 0.00/0.00/300.00/134.31 | 40,293.97 | 1.00000 | 是 |
| web-530 | mid__Star-Trek-TNG-logo.svg | mid | 11819 | ok | 25/461/809/0/0/0/0/0/0/0/0 | 591.00 × 227.00 | -25.03/-6.77/617.17/218.99 | 144,981.78 | 1.08069 | 是 |
| web-531 | mid__Star-Wars-Jedi-Fallen-Order-logo-PL.svg | mid | 15365 | ok | 2/771/1622/0/0/0/0/0/0/0/0 | 478.70 × 334.64 | 0.18/0.00/477.82/304.00 | 145,203.47 | 0.90644 | 否 |
| web-532 | mid__Tercera-Via-Andorra-Logo-Icon.svg | mid | 8251 | ok | 12/112/204/0/0/0/0/0/0/0/0 | 229.04 × 236.14 | 0.00/0.00/229.04/236.14 | 54,085.48 | 1.00000 | 是 |
| web-533 | mid__US-Airways-Logo-2011.svg | mid | 5672 | ok | 3/279/405/0/0/0/0/0/0/0/0 | 1643.92 × 223.49 | 0.00/0.00/1643.92/223.49 | 367,397.58 | 1.00000 | 否 |
| web-534 | mid__Western-Star-Trucks-logo.svg | mid | 7258 | ok | 14/337/423/0/0/0/0/0/0/0/0 | 136.32 × 59.13 | -0.02/0.18/135.63/59.01 | 7,980.51 | 0.99003 | 是 |
| web-535 | mid__YouTube-light-logo-2017.svg | mid | 5546 | ok | 8/173/337/0/0/0/0/0/0/0/0 | 380.90 × 85.00 | 0.00/0.00/381.00/85.00 | 32,385.00 | 1.00026 | 是 |
| web-536 | pattern__3d-green-background.svg | pattern | 631664 | ok | 1223/49943/49942/1222/0/0/0/0/0/0/0 | 486.00 × 486.00 | 0.00/0.00/486.00/486.00 | 236,196.00 | 1.00000 | 否 |
| web-537 | pattern__Bookman-Ornament-7242-bookshelf.svg | pattern | 70165 | ok | 1/1892/4194/0/0/0/0/0/0/0/0 | 607.26 × 295.16 | 0.00/0.00/607.26/295.16 | 179,239.20 | 1.00000 | 否 |
| web-538 | pattern__Chimmie-Xenia-the-Linux-Vixen-space-wall.svg | pattern | 1630000 | ok | 247/44971/107551/0/1/4/1/0/119/0/0 | 1920.00 × 1080.00 | -252.89/-204.35/2172.89/1323.35 | 3,705,870.61 | 1.78717 | 是 |
| web-539 | pattern__Dmharvey-wallpaper-test-6-pattern.svg | pattern | 264994 | ok | 263/2133/4829/39/0/0/0/0/0/0/0 | 333.33 × 466.67 | -479.81/-473.95/512.95/911.45 | 1,375,365.94 | 8.84164 | 是 |
| web-540 | pattern__Elementary-cellular-automaton-111.svg | pattern | 92111 | ok | 1501/7505/6004/0/0/0/0/0/0/0/0 | 6000.00 × 6000.00 | 0.00/0.00/6000.00/6000.00 | 36,000,000.00 | 1.00000 | 否 |
| web-541 | pattern__Elementary-cellular-automaton-129.svg | pattern | 1163295 | ok | 18761/93805/75044/0/0/0/0/0/0/0/0 | 6000.00 × 6000.00 | 0.00/0.00/6000.00/6000.00 | 36,000,000.00 | 1.00000 | 否 |
| web-542 | pattern__Elementary-cellular-automaton-155.svg | pattern | 92428 | ok | 1501/7505/6004/0/0/0/0/0/0/0/0 | 6000.00 × 6000.00 | 0.00/0.00/6000.00/6000.00 | 36,000,000.00 | 1.00000 | 否 |
| web-543 | pattern__Elementary-cellular-automaton-193.svg | pattern | 5058696 | ok | 82181/410905/328724/0/0/0/0/0/0/0/0 | 6000.00 × 6000.00 | 0.00/0.00/6000.00/6000.00 | 36,000,000.00 | 1.00000 | 否 |
| web-544 | pattern__Elementary-cellular-automaton-230.svg | pattern | 5827256 | ok | 94501/472505/378004/0/0/0/0/0/0/0/0 | 6000.00 × 6000.00 | 0.00/0.00/6000.00/6000.00 | 36,000,000.00 | 1.00000 | 否 |
| web-545 | pattern__Elementary-cellular-automaton-60.svg | pattern | 1099752 | ok | 17951/89755/71804/0/0/0/0/0/0/0/0 | 6000.00 × 6000.00 | 0.00/0.00/6000.00/6000.00 | 36,000,000.00 | 1.00000 | 否 |
| web-546 | pattern__Elementary-cellular-automaton-83.svg | pattern | 92334 | ok | 1501/7505/6004/0/0/0/0/0/0/0/0 | 6000.00 × 6000.00 | 0.00/0.00/6000.00/6000.00 | 36,000,000.00 | 1.00000 | 否 |
| web-547 | pattern__Hadiya-Traditional-Clothing-Pattern.svg | pattern | 96090 | ok | 934/4670/3736/0/0/0/1/0/0/0/0 | 1280.00 × 826.50 | 0.00/0.00/1280.00/826.50 | 1,057,921.72 | 1.00000 | 否 |
| web-548 | pattern__Ragam-Hias-Minangkabau-Kuciang-Lalok.svg | pattern | 404808 | ok | 1/10528/26717/0/0/0/0/0/0/0/0 | 651.16 × 317.37 | 0.00/0.00/651.16/317.37 | 206,655.69 | 1.00000 | 否 |
| web-549 | pattern__Sutton-Hoo-helmet-fig4.svg | pattern | 195365 | ok | 569/5340/12286/568/0/0/0/0/0/0/0 | 545.31 × 402.67 | 6.48/4.90/538.43/398.62 | 209,438.81 | 0.95381 | 否 |
| web-550 | pattern__Triangle-soil-texture-Jamagne-1977-and-a.svg | pattern | 58893 | ok | 44/103/103/44/0/0/0/0/0/0/0 | 755.61 × 710.14 | 0.00/-5.87/761.48/702.78 | 539,619.16 | 1.00565 | 是 |
| web-551 | pattern__Triangle-texture-soil.svg | pattern | 61287 | ok | 46/110/110/46/0/0/0/0/0/0/0 | 732.95 × 721.98 | -4.04/-5.87/738.82/693.15 | 519,266.16 | 0.98127 | 是 |
| web-552 | pattern__Tsuno-Asanoha-Kumiko-Pattern.svg | pattern | 371328 | ok | 3/1475/1285/0/0/1/0/0/0/1/0 | 3005.29 × 2899.59 | -3044.71/-2.32/6065.87/8798.77 | 80,183,030.95 | 9.20152 | 是 |
| web-553 | pattern__Twentieth-Century-Ornament-80-fasces-wit.svg | pattern | 63158 | ok | 1/1444/3704/0/0/0/0/0/0/0/0 | 291.72 × 779.97 | 0.00/0.00/291.72/779.97 | 227,531.85 | 1.00000 | 否 |
| web-554 | pattern__TwistedPlanarTexture.svg | pattern | 79237 | ok | 319/1915/4109/314/0/0/0/0/0/0/0 | 377.95 × 151.18 | 12.91/25.11/365.04/126.07 | 35,549.24 | 0.62215 | 否 |
| web-555 | pattern__USDA-Soil-Texture.svg | pattern | 538398 | ok | 482/1825/1409/446/0/0/0/0/0/0/0 | 2368.00 × 2272.00 | -25.00/18.30/2340.20/2263.10 | 5,309,401.08 | 0.98686 | 是 |
| web-556 | pattern__WD10-landscape-background-10-shape-dark.svg | pattern | 239303 | ok | 210/1246/2326/79/0/0/244/7/0/0/0 | 1920.00 × 1080.00 | 0.00/0.00/1920.00/1080.00 | 2,073,600.00 | 1.00000 | 否 |
| web-557 | pattern__Wikimania-2024-Background-pattern-aquama.svg | pattern | 2410716 | ok | 2/10/8/0/0/0/0/0/0/0/1 | 1920.00 × 1080.00 | -5.74/0.62/1920.00/1081.41 | 2,081,320.60 | 1.00372 | 是 |
| web-558 | pattern__Wikimania-2024-Background-pattern-orange.svg | pattern | 965805 | ok | 2/10/8/0/0/0/0/0/0/0/1 | 1920.00 × 1080.00 | -30.09/-9.70/1935.24/1085.63 | 2,152,684.91 | 1.03814 | 是 |
| web-559 | pattern__a-set-of-tiles-that-can-be-used-in-the-k.svg | pattern | 1418354 | ok | 20/32004/78624/4/0/0/0/0/0/0/0 | 3508.72 × 3498.91 | -4.90/-4.90/3513.62/3503.82 | 12,345,522.31 | 1.00561 | 是 |
| web-560 | pattern__abstract-colorful-face.svg | pattern | 190599 | ok | 188/2368/5778/78/49/20/15/0/20/0/0 | 709.09 × 801.89 | -60.20/0.00/746.82/801.89 | 647,144.49 | 1.13812 | 是 |
| web-561 | pattern__antique-frame-floral-branches.svg | pattern | 1579238 | ok | 1/45917/115866/0/0/0/0/0/0/0/0 | 3968.56 × 5000.00 | -0.00/0.04/3968.56/5000.04 | 19,842,830.26 | 1.00000 | 是 |
| web-562 | pattern__antique-frame-floral-decorations.svg | pattern | 2690561 | ok | 1/117080/299759/0/0/0/0/0/0/0/0 | 4188.40 × 5700.30 | -0.01/0.20/4188.53/5700.26 | 23,874,956.86 | 0.99999 | 是 |
| web-563 | pattern__antique-frame-with-floral-decorations.svg | pattern | 2620535 | ok | 1/81908/189871/0/0/0/0/0/0/0/0 | 5000.00 × 4525.67 | 0.00/0.00/5000.00/4525.67 | 22,628,342.44 | 1.00000 | 是 |
| web-564 | pattern__antique-ornament-frame-6.svg | pattern | 200393 | ok | 1/4356/12078/0/0/0/0/0/0/0/0 | 1152.00 × 787.84 | 44.25/30.56/1109.24/758.36 | 775,105.53 | 0.85402 | 否 |
| web-565 | pattern__celtic-knotwork-border.svg | pattern | 3134 | ok | 6/138/254/6/0/0/0/0/0/0/0 | 800.00 × 400.00 | -43.73/-41.40/843.69/440.00 | 427,213.60 | 1.33504 | 是 |
| web-566 | pattern__colorful-trippy-background.svg | pattern | 2822174 | ok | 40405/242863/526558/40404/0/0/0/0/0/0/0 | 400.00 × 400.00 | -1.15/-1.48/401.48/401.48 | 162,246.49 | 1.01404 | 是 |
| web-567 | pattern__curving-stem-with-small-hanging-fruit-li.svg | pattern | 66279 | ok | 35/366/1022/35/0/0/0/0/0/0/0 | 2759.34 × 3287.11 | 188.64/-23.57/2381.07/3118.57 | 6,888,919.22 | 0.75951 | 是 |
| web-568 | pattern__cyan-tiles-with-red-and-blue-shark-patte.svg | pattern | 580660 | ok | 5/14224/34944/1/0/0/0/0/0/0/0 | 4968.44 × 4968.44 | -4.67/-4.67/4973.11/4973.11 | 24,778,270.09 | 1.00376 | 是 |
| web-569 | pattern__decorative-bookplate.svg | pattern | 3512633 | ok | 5/99594/248190/0/0/0/0/0/0/0/0 | 1400.00 × 1895.00 | -11.84/-4.30/1413.88/1900.43 | 2,715,616.37 | 1.02360 | 是 |
| web-570 | pattern__decorative-design-in-books-iv.svg | pattern | 5421 | ok | 4/202/268/0/0/0/0/0/0/0/0 | 1710.00 × 500.00 | 25.33/21.33/1686.26/465.43 | 737,618.71 | 0.86271 | 否 |
| web-571 | pattern__decorative-divider-with-two-birds-and-go.svg | pattern | 152057 | ok | 9/2726/6974/0/0/0/0/0/0/0/0 | 858.00 × 224.00 | 0.00/0.00/858.00/224.00 | 192,192.00 | 1.00000 | 否 |
| web-572 | pattern__doodle-divider-frame.svg | pattern | 236512 | ok | 1/5280/13790/0/0/0/0/0/0/0/0 | 884.42 × 3606.58 | 0.00/0.00/884.42/3606.58 | 3,189,744.01 | 1.00000 | 是 |
| web-573 | pattern__egypt-frame.svg | pattern | 131011 | ok | 1/3082/7586/0/0/0/0/0/0/0/0 | 1125.00 × 819.94 | -0.00/0.00/1125.00/819.94 | 922,436.59 | 1.00000 | 是 |
| web-574 | pattern__film-strip-1b.svg | pattern | 5823 | ok | 15/174/327/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 120.00/70.00/420.00/400.00 | 99,000.00 | 0.37766 | 否 |
| web-575 | pattern__floral-vine-border-graphic.svg | pattern | 89406 | ok | 1/1918/4943/0/0/0/0/0/0/0/0 | 477.54 × 154.90 | 0.00/0.00/477.54/154.90 | 73,971.20 | 1.00000 | 是 |
| web-576 | pattern__flower-four-frame-thing.svg | pattern | 1812759 | ok | 4/48994/120041/0/0/0/0/0/0/0/0 | 1133.86 × 1700.79 | 52.70/31.87/1089.37/1679.42 | 1,707,975.54 | 0.88567 | 否 |
| web-577 | pattern__foliage-leaves-and-branches.svg | pattern | 584833 | ok | 920/4361/11035/10/13/0/26/0/0/0/0 | 880.00 × 880.00 | -88.00/-88.00/1005.46/1035.19 | 1,228,170.34 | 1.58596 | 是 |
| web-578 | pattern__foliage-pattern-on-green-background.svg | pattern | 348180 | ok | 652/4418/9217/351/0/0/0/0/0/0/0 | 880.00 × 880.00 | -88.00/-88.00/968.00/968.00 | 1,115,136.00 | 1.44000 | 是 |
| web-579 | pattern__globe-banner-frame-1709068091.svg | pattern | 300256 | ok | 1/6363/17449/0/0/0/0/0/0/0/0 | 6013.93 × 1237.38 | 0.00/0.00/6013.93/1237.38 | 7,441,514.10 | 1.00000 | 否 |
| web-580 | pattern__golden-wedding-ring-1695193395.svg | pattern | 11223 | ok | 20/145/376/0/0/0/1/0/0/0/0 | 800.00 × 800.00 | 0.00/0.00/800.00/799.24 | 639,388.72 | 0.99904 | 否 |
| web-581 | pattern__green-leaves-pattern.svg | pattern | 576791 | ok | 1387/3239/4470/1232/0/0/0/0/0/0/0 | 880.00 × 880.00 | -88.00/-88.00/968.00/968.00 | 1,115,136.00 | 1.44000 | 是 |
| web-582 | pattern__keffiyah-patterns.svg | pattern | 326728 | ok | 4/8111/18674/0/0/0/0/0/0/0/0 | 1183.00 × 1986.04 | -2004.96/-0.00/1183.00/1986.04 | 6,331,419.18 | 2.69481 | 是 |
| web-583 | pattern__lady-sunflowers-frame.svg | pattern | 869933 | ok | 1/23179/59282/0/0/0/0/0/0/0/0 | 2055.00 × 3170.00 | 21.06/34.11/2039.23/3143.00 | 6,274,266.46 | 0.96315 | 否 |
| web-584 | pattern__owl-perched-on-skull-and-book-vintage-en.svg | pattern | 357039 | ok | 1/7249/17257/0/0/0/0/0/0/0/0 | 621.10 × 635.95 | 28.67/35.73/586.67/593.91 | 311,466.33 | 0.78855 | 否 |
| web-585 | pattern__peach-tree-frame-colored-version.svg | pattern | 3322474 | ok | 16/86623/226959/0/0/1/0/0/0/0/0 | 4131.63 × 6161.83 | 0.00/0.00/4131.63/6161.83 | 25,458,416.65 | 1.00000 | 是 |
| web-586 | pattern__peach-tree-frame-monochrome-illustration.svg | pattern | 2877771 | ok | 1/76890/200759/0/0/0/0/0/0/0/0 | 4130.75 × 6161.81 | 0.00/0.00/4130.75/6161.81 | 25,452,901.26 | 1.00000 | 是 |
| web-587 | pattern__plastic-childrens-umbrella.svg | pattern | 74813 | ok | 47/1625/4240/0/0/0/0/0/0/0/0 | 1403.50 × 1461.07 | 0.00/0.00/1403.50/1461.07 | 2,050,612.43 | 1.00000 | 否 |
| web-588 | pattern__river-nature.svg | pattern | 20120 | ok | 21/400/1053/0/0/0/1/0/0/0/0 | 880.00 × 880.00 | 4.51/0.00/880.00/877.40 | 768,161.24 | 0.99194 | 否 |
| web-589 | pattern__sailing-ship-on-rough-sea-in-ornate-dolp.svg | pattern | 3647505 | ok | 1/89440/213816/0/0/0/0/0/0/0/0 | 634.69 × 682.65 | 9.18/11.22/624.18/673.16 | 407,087.84 | 0.93956 | 否 |
| web-590 | pattern__swirl-sun-rays-pattern.svg | pattern | 13703 | ok | 22/205/485/0/0/0/1/0/0/0/0 | 800.00 × 800.00 | 0.00/2.67/798.67/800.00 | 636,803.94 | 0.99501 | 否 |
| web-591 | pattern__symmetrical-folk-floral-ornament-outline.svg | pattern | 102255 | ok | 46/803/2278/46/0/0/0/0/0/0/0 | 621.59 × 842.42 | 29.69/52.40/600.60/801.45 | 427,643.89 | 0.81667 | 否 |
| web-592 | pattern__tiled-pattern.svg | pattern | 47495 | ok | 90/909/1561/0/0/0/0/0/0/0/0 | 880.00 × 880.00 | 6.15/4.05/872.77/879.05 | 758,294.28 | 0.97920 | 否 |
| web-593 | pattern__trees-frame.svg | pattern | 1042458 | ok | 1/23120/65344/0/0/0/0/0/0/0/0 | 1887.17 × 2631.58 | -0.00/0.00/1887.17/2631.58 | 4,966,244.53 | 1.00000 | 是 |
| web-594 | pattern__two-peacocks-perched-on-fountain-bowl.svg | pattern | 247421 | ok | 1/5937/14647/0/0/0/0/0/0/0/0 | 533.33 × 431.31 | 11.12/16.16/525.40/421.49 | 208,453.59 | 0.90619 | 否 |
| web-595 | pattern__unicorn-on-red-and-white-croatian-checke.svg | pattern | 114751 | ok | 539/4127/6532/0/0/0/0/0/0/0/0 | 2560.00 × 1600.00 | 0.00/0.00/2562.32/1601.96 | 4,104,732.67 | 1.00213 | 是 |
| web-596 | pattern__vignette-10.svg | pattern | 221666 | ok | 1/5048/13382/0/0/0/0/0/0/0/0 | 721.53 × 459.06 | 0.00/0.00/721.53/459.06 | 331,224.82 | 1.00000 | 否 |
| web-597 | pattern__vignette-3.svg | pattern | 293325 | ok | 1/6286/17168/0/0/0/0/0/0/0/0 | 1798.18 × 990.91 | 32.54/48.33/1758.42/954.96 | 1,564,736.04 | 0.87816 | 否 |
| web-598 | pattern__vignette-4.svg | pattern | 1246357 | ok | 1/31200/72826/0/0/0/0/0/0/0/0 | 1029.56 × 566.79 | 0.00/0.00/1029.56/566.79 | 583,544.57 | 1.00000 | 否 |
| web-599 | pattern__vintage-decorative-frame-with-intricate-.svg | pattern | 2728653 | ok | 654/80217/206774/0/0/0/0/0/0/0/0 | 3589.85 × 6000.00 | 0.02/-0.02/3589.85/5999.98 | 21,538,940.84 | 0.99999 | 是 |
| web-600 | pattern__vintage-divider-decoration-136.svg | pattern | 19032 | ok | 1/466/1264/0/0/0/0/0/0/0/0 | 5000.00 × 2553.61 | 0.00/0.00/5000.00/2553.61 | 12,768,039.95 | 1.00000 | 是 |
| web-601 | pattern__wave600.svg | pattern | 3293 | ok | 10/80/110/0/10/10/0/0/0/0/0 | 600.00 × 200.00 | 0.00/0.00/600.00/188.90 | 113,338.88 | 0.94449 | 否 |
| web-602 | pattern__young-woman-with-flower-in-hair-holds-ma.svg | pattern | 318624 | ok | 1/7801/19288/0/0/0/0/0/0/0/0 | 1000.00 × 749.00 | 63.37/61.51/918.70/673.99 | 523,875.39 | 0.69943 | 否 |
| web-603 | peeps__open-peeps-packages-open-peeps-assets-at.svg | peeps | 19090 | ok | 2/410/981/0/0/0/0/0/0/0/0 | 818.00 × 733.00 | 24.00/-31.55/815.98/732.25 | 604,917.30 | 1.00888 | 是 |
| web-604 | peeps__open-peeps-packages-open-peeps-assets-at-2.svg | peeps | 22770 | ok | 2/489/1202/0/0/0/0/0/0/0/0 | 818.00 × 733.00 | 24.00/-16.00/807.82/700.93 | 561,943.21 | 0.93721 | 是 |
| web-605 | peeps__open-peeps-packages-open-peeps-assets-at-3.svg | peeps | 10833 | ok | 2/203/542/0/0/0/0/0/0/0/0 | 818.00 × 733.00 | 19.00/-32.00/802.17/706.38 | 578,276.13 | 0.96445 | 是 |
| web-606 | peeps__open-peeps-packages-open-peeps-assets-at-4.svg | peeps | 4183 | ok | 1/83/197/0/0/0/0/0/0/0/0 | 289.00 × 293.00 | 53.00/56.00/236.36/259.81 | 37,370.52 | 0.44133 | 否 |
| web-607 | peeps__open-peeps-packages-open-peeps-assets-at-5.svg | peeps | 13818 | ok | 2/283/731/0/0/0/0/0/0/0/0 | 473.00 × 567.00 | -24.00/28.00/432.10/605.88 | 263,569.87 | 0.98277 | 是 |
| web-608 | peeps__open-peeps-packages-open-peeps-assets-at-6.svg | peeps | 5389 | ok | 2/100/255/0/0/0/0/0/0/0/0 | 473.00 × 567.00 | -76.00/62.00/468.98/538.48 | 259,675.76 | 0.96825 | 是 |
| web-609 | peeps__open-peeps-packages-open-peeps-assets-at-7.svg | peeps | 8063 | ok | 2/153/401/0/0/0/0/0/0/0/0 | 473.00 × 567.00 | 47.00/45.00/425.90/502.18 | 173,229.18 | 0.64592 | 否 |
| web-610 | peeps__open-peeps-packages-open-peeps-assets-at-8.svg | peeps | 6646 | ok | 2/126/317/0/0/0/0/0/0/0/0 | 473.00 × 567.00 | 51.00/62.00/421.08/505.15 | 164,000.39 | 0.61151 | 否 |
| web-611 | peeps__open-peeps-packages-open-peeps-assets-at-9.svg | peeps | 61311 | ok | 2/1116/2993/0/0/0/0/0/0/0/0 | 1534.00 × 1856.00 | -857.00/-39.00/2463.27/2729.00 | 9,190,502.99 | 3.22802 | 是 |
| web-612 | peeps__open-peeps-packages-open-peeps-assets-at-10.svg | peeps | 27224 | ok | 2/464/1342/0/0/0/0/0/0/0/0 | 1645.00 × 2500.00 | 130.00/-19.00/1479.96/2509.08 | 3,412,805.82 | 0.82986 | 是 |
| web-613 | small__CJB-logo-small.svg | small | 1748 | ok | 7/103/110/0/0/0/0/0/0/0/0 | 318.70 × 303.30 | 0.00/0.00/318.70/303.20 | 96,629.85 | 0.99967 | 否 |
| web-614 | small__Computer-Science-House-logo-icon-square-.svg | small | 4522 | ok | 21/133/112/0/0/0/0/18/0/0/0 | 618.00 × 600.00 | -22.00/0.00/640.00/601.00 | 397,862.00 | 1.07298 | 是 |
| web-615 | small__Emblem-of-the-SKH.svg | small | 4266 | ok | 4/42/46/0/0/0/0/0/0/0/0 | 72.53 × 75.13 | 0.00/0.00/72.53/68.99 | 5,003.86 | 0.91823 | 是 |
| web-616 | small__Github-desktop-logo-symbol.svg | small | 3487 | ok | 7/104/271/1/2/0/0/0/0/0/0 | 128.00 × 128.00 | 0.00/0.00/128.06/129.97 | 16,644.22 | 1.01588 | 是 |
| web-617 | small__Google-Icon-2010-2015.svg | small | 2037 | ok | 2/57/131/0/1/0/0/0/0/0/0 | 341.60 × 341.60 | 0.00/0.00/341.70/341.70 | 116,758.90 | 1.00059 | 是 |
| web-618 | small__Google-Translate-logo.svg | small | 2091 | ok | 8/95/151/0/2/0/0/0/0/0/0 | 998.10 × 998.30 | 0.00/0.00/998.10/998.30 | 996,403.19 | 1.00000 | 否 |
| web-619 | small__Konami-logo-icon.svg | small | 2164 | ok | 1/24/65/0/0/0/0/0/0/0/0 | 48.95 × 43.08 | 0.00/0.00/48.95/43.08 | 2,108.84 | 0.99996 | 否 |
| web-620 | small__Laboratory-for-Laser-Energetics-logo-blu.svg | small | 3086 | ok | 5/143/182/0/0/0/0/0/0/0/0 | 72.88 × 30.05 | -0.00/-0.00/72.88/30.05 | 2,190.17 | 1.00000 | 是 |
| web-621 | small__Logo-Central-Kladno.svg | small | 1381 | ok | 7/43/68/0/0/0/0/0/0/0/0 | 800.00 × 600.00 | 129.06/51.06/626.94/548.94 | 247,886.49 | 0.51643 | 否 |
| web-622 | small__Logo-Tramway-Bordeaux-ligne-A.svg | small | 2690 | ok | 2/23/33/0/0/0/0/0/0/0/0 | 48.14 × 48.14 | -0.00/0.00/48.14/48.14 | 2,317.64 | 1.00000 | 是 |
| web-623 | small__Logo-Willer-Trains.svg | small | 2771 | ok | 2/175/242/0/0/0/0/0/0/0/0 | 584.73 × 148.29 | 1.00/2.02/582.71/147.29 | 84,505.08 | 0.97455 | 否 |
| web-624 | small__Outlook-com-icon-2012-2019.svg | small | 3202 | ok | 4/43/80/0/0/0/0/0/0/0/0 | 103.17 × 104.31 | -0.00/0.00/103.17/104.31 | 10,762.34 | 1.00000 | 是 |
| web-625 | small__Rockstar-London-Logo.svg | small | 3938 | ok | 5/130/222/0/0/0/0/0/0/0/0 | 216.00 × 198.80 | 0.00/0.00/216.00/198.90 | 42,962.40 | 1.00050 | 是 |
| web-626 | small__R-dt-logo-bokm-l.svg | small | 4664 | ok | 10/101/195/0/0/0/0/0/0/0/0 | 680.20 × 735.55 | 0.00/0.00/680.20/735.55 | 500,318.81 | 1.00000 | 是 |
| web-627 | small__Swedru-All-Blacks-F-C-logo.svg | small | 1869 | ok | 5/38/69/0/0/0/0/0/0/0/0 | 90.67 × 90.67 | 0.00/0.00/90.67/90.67 | 8,220.44 | 1.00000 | 否 |
| web-628 | small__Transfeminism-logo-black.svg | small | 3548 | ok | 6/153/344/0/0/0/0/0/0/0/0 | 128.20 × 141.70 | 0.00/0.00/128.20/141.70 | 18,165.94 | 1.00000 | 否 |
| web-629 | small__Transwa-icon-v2.svg | small | 1646 | ok | 1/28/70/0/0/0/0/0/0/0/0 | 100.00 × 100.00 | -0.00/-0.08/99.95/99.91 | 9,993.81 | 0.99938 | 是 |
| web-630 | small__Wittenburg-Tigers-logo-arched-wordmark-w.svg | small | 3889 | ok | 2/137/154/0/0/0/0/0/0/0/0 | 437.19 × 232.92 | 0.00/0.00/437.19/232.92 | 101,831.77 | 1.00000 | 是 |
| web-631 | small__icons-delapouite-socks.svg | small | 2438 | ok | 2/84/183/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-632 | small__icons-icons-cloud-arrow-up.svg | small | 765 | ok | 2/38/80/0/0/0/0/0/0/0/0 | 16.00 × 16.00 | 0.00/2.00/16.00/13.00 | 176.00 | 0.68750 | 否 |
| web-633 | small__icons-icons-flower1.svg | small | 2977 | ok | 1/194/446/0/0/0/0/0/0/0/0 | 16.00 × 16.00 | -0.00/-0.00/16.00/16.00 | 256.01 | 1.00002 | 是 |
| web-634 | small__icons-icons-person-rolodex.svg | small | 567 | ok | 2/42/88/0/0/0/0/0/0/0/0 | 16.00 × 16.00 | 0.00/1.00/16.00/14.00 | 208.00 | 0.81250 | 否 |
| web-635 | small__icons-icons-type-h2.svg | small | 460 | ok | 1/30/40/0/0/0/0/0/0/0/0 | 16.00 × 16.00 | 0.00/3.00/15.75/13.00 | 157.51 | 0.61527 | 否 |
| web-636 | small__icons-icons-usb-mini-fill.svg | small | 368 | ok | 1/24/43/0/0/0/0/0/0/0/0 | 16.00 × 16.00 | 0.00/3.00/16.00/13.00 | 160.00 | 0.62500 | 否 |
| web-637 | small__icons-lorc-burning-meteor.svg | small | 1071 | ok | 2/37/78/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-638 | small__icons-lorc-cubeforce.svg | small | 1804 | ok | 2/128/147/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-639 | small__icons-lorc-curling-vines.svg | small | 4997 | ok | 2/153/411/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-640 | small__icons-lorc-sword-hilt.svg | small | 1421 | ok | 2/58/108/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-641 | small__icons-sbed-telefrag.svg | small | 737 | ok | 2/57/93/0/0/0/0/0/0/0/0 | 512.00 × 512.00 | 0.00/0.00/512.00/512.00 | 262,144.00 | 1.00000 | 否 |
| web-642 | tech__Diagram-of-the-human-heart-cropped-bs.svg | tech | 219143 | ok | 340/5284/8629/98/17/32/0/0/0/0/0 | 672.88 × 641.26 | 17.76/14.54/655.12/617.49 | 384,298.89 | 0.89063 | 否 |
| web-643 | tech__Diagram-of-the-human-heart-multilingual-.svg | tech | 122573 | ok | 195/1228/2512/151/17/34/0/0/0/0/0 | 692.50 × 652.50 | 19.80/41.41/670.13/629.07 | 382,182.15 | 0.84580 | 否 |
| web-644 | tech__Diagram-of-the-human-heart-uk.svg | tech | 458397 | ok | 368/11312/28820/96/17/32/0/0/0/0/0 | 691.40 × 644.90 | 16.54/18.36/674.07/631.75 | 403,327.12 | 0.90454 | 否 |
| web-645 | tech__Electric-Motor-with-Slip-Rings.svg | tech | 54412 | ok | 198/808/1147/147/18/0/0/0/0/0/0 | 1700.00 × 1190.00 | 115.00/40.00/1585.00/1151.98 | 1,634,610.39 | 0.80801 | 否 |
| web-646 | tech__Engine-papin.svg | tech | 353159 | ok | 64/243/347/53/5/0/0/0/0/0/0 | 617.00 × 365.47 | 0.00/-1.71/590.21/365.46 | 216,709.20 | 0.96104 | 是 |
| web-647 | tech__Gray-696-es.svg | tech | 63007 | ok | 78/650/1491/64/0/1/0/0/0/0/0 | 339.85 × 629.50 | 40.34/-0.02/339.80/629.50 | 188,513.47 | 0.88116 | 是 |
| web-648 | tech__Human-Neuroaxis-as.svg | tech | 337519 | ok | 118/7868/16860/9/30/9/0/0/0/0/0 | 2500.00 × 2007.00 | 7.83/138.52/2496.00/1990.57 | 4,608,223.71 | 0.91843 | 否 |
| web-649 | tech__Human-Neuroaxis-bn.svg | tech | 337519 | ok | 118/7868/16860/9/30/9/0/0/0/0/0 | 2500.00 × 2007.00 | 7.83/138.52/2496.00/1990.57 | 4,608,223.71 | 0.91843 | 否 |
| web-650 | tech__MRI-Machine-NIH-BioArt-689-782372.svg | tech | 131844 | ok | 265/4589/9228/0/0/0/0/0/0/0/0 | 500.00 × 500.00 | 32.94/24.22/454.14/491.54 | 196,837.97 | 0.78735 | 否 |
| web-651 | tech__Penis-and-testes-anatomy-unlabeled.svg | tech | 3875348 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 2560.00 × 1440.00 | 0.00/0.00/2560.00/1440.00 | 3,686,400.00 | 1.00000 | 否 |
| web-652 | tech__Polychaeta-anatomy-de.svg | tech | 229555 | ok | 258/14051/14473/68/0/0/1/0/0/0/0 | 2665.32 × 1582.68 | 0.00/-0.00/2665.32/1582.68 | 4,218,346.23 | 1.00000 | 是 |
| web-653 | tech__Scheme-ant-worker-anatomy-ar.svg | tech | 502638 | ok | 151/1763/4597/143/0/0/0/0/0/0/0 | 880.00 × 780.00 | 9.32/14.25/790.25/765.81 | 586,915.14 | 0.85506 | 否 |
| web-654 | tech__Scheme-snail-anatomy-fr.svg | tech | 222588 | ok | 600/5184/12078/547/0/25/0/0/0/0/0 | 742.09 × 356.01 | 59.06/16.72/673.55/349.63 | 204,569.84 | 0.77433 | 否 |
| web-655 | tech__Switched-reluctance-motor-6-4.svg | tech | 553822 | ok | 7/156/244/4/0/0/0/0/0/0/1 | 1000.00 × 1000.00 | -60.00/-38.66/1000.26/1000.06 | 1,101,306.30 | 1.10131 | 是 |
| web-656 | tech__Thyroid-gland-thyroid-cartilage.svg | tech | 537108 | ok | 0/0/0/0/0/0/0/0/0/1/0 | 496.00 × 464.00 | 0.00/0.00/496.00/464.00 | 230,144.00 | 1.00000 | 否 |
| web-657 | tech__Torque-motor.svg | tech | 1242615 | ok | 422/30009/70497/324/0/0/0/0/0/0/0 | 1400.00 × 1200.00 | 53.77/-881.00/2165.00/1130.50 | 4,246,734.34 | 2.52782 | 是 |
| web-658 | text__Australian-Census-2011-demographic-map-I.svg | text | 3066848 | ok | 150/148436/142393/20/1/2/0/0/0/0/0 | 2000.00 × 1471.24 | -100000.01/-73562.12/100000.01/73562.12 | 29,424,849,173.82 | 10000.00101 | 是 |
| web-659 | text__Australian-Census-2011-demographic-map-N.svg | text | 5826913 | ok | 1320/289966/275465/29/1/3/0/0/0/0/0 | 2000.00 × 1316.53 | -10000.00/-6582.63/10000.00/6582.63 | 263,305,292.97 | 100.00000 | 是 |
| web-660 | text__Australian-Census-2011-demographic-map-V.svg | text | 4132602 | ok | 1160/224131/209459/29/1/3/0/0/0/0/0 | 2000.00 × 1147.57 | -10000.00/-5737.85/10000.00/5737.85 | 229,513,906.25 | 100.00001 | 是 |
| web-661 | text__Chaos-Evolutions-poster.svg | text | 5732349 | ok | 1/5/4/0/0/0/0/0/0/1/0 | 491.20 × 699.20 | 0.00/0.00/492.00/699.20 | 344,006.40 | 1.00163 | 是 |
| web-662 | text__Goncharov-film-poster.svg | text | 107794 | ok | 228/2481/3747/73/1/0/1/0/0/0/0 | 596.67 × 848.00 | 0.00/0.00/596.67/848.00 | 505,975.54 | 1.00000 | 否 |
| web-663 | text__HU-Keyboard-Layout-V2-EN-Legend.svg | text | 55105 | ok | 146/1328/2116/0/0/0/0/0/0/0/0 | 799.00 × 385.00 | 8.99/16.72/785.02/365.28 | 270,495.47 | 0.87933 | 否 |
| web-664 | text__HrW-poster-Clubture-Forum-2024-updated.svg | text | 279158 | ok | 613/8096/16378/3/0/0/1/0/0/0/0 | 2245.04 × 1587.40 | 107.80/32.96/2146.06/1515.32 | 3,021,418.46 | 0.84781 | 否 |
| web-665 | text__Inscript-ml.svg | text | 207152 | ok | 188/2594/3940/10/0/0/0/0/0/0/0 | 600.00 × 279.56 | 0.00/0.00/600.00/279.56 | 167,733.31 | 1.00000 | 否 |
| web-666 | text__KB-US-Colemak.svg | text | 146916 | ok | 133/2712/5036/70/0/0/0/0/0/0/0 | 900.00 × 300.00 | -0.50/-0.50/900.50/300.50 | 271,201.00 | 1.00445 | 是 |
| web-667 | text__KB-United-States-Dvorak.svg | text | 136304 | ok | 131/2502/4500/69/0/0/0/0/0/0/0 | 900.00 × 300.00 | -0.50/-0.50/900.50/300.50 | 271,201.00 | 1.00445 | 是 |
| web-668 | text__KB-Bengali-Bijoy.svg | text | 326330 | ok | 283/6421/10461/37/0/13/13/0/0/0/0 | 900.00 × 300.67 | 0.00/0.00/900.00/300.67 | 270,599.25 | 1.00000 | 否 |
| web-669 | text__Keyboard-layout-blank-text-keycodes-and-.svg | text | 83959 | ok | 7/1215/1080/0/0/0/0/0/0/0/0 | 3060.00 × 1020.00 | 0.00/0.00/3060.00/1020.00 | 3,121,200.00 | 1.00000 | 否 |
| web-670 | text__Oxygen480-actions-view-calendar-list.svg | text | 80422 | ok | 87/651/1366/62/12/68/3/0/4/0/0 | 128.00 × 128.00 | -32.00/-16.00/160.00/137.92 | 29,552.64 | 1.80375 | 是 |
| web-671 | text__Oxygen480-actions-view-calendar-upcoming.svg | text | 75626 | ok | 119/811/1494/62/15/71/3/0/4/0/0 | 128.00 × 128.00 | -32.00/-16.00/160.00/137.92 | 29,552.64 | 1.80375 | 是 |
| web-672 | text__POSTER-WMISLM-COMPANIONS-2024.svg | text | 4014951 | ok | 264/5282/8751/0/0/0/18/9/0/9/0 | 2245.00 × 1587.00 | 0.54/0.00/2244.12/1586.00 | 3,558,323.17 | 0.99874 | 否 |
| web-673 | text__Polish-keyboard-PN97.svg | text | 129348 | ok | 110/1658/2804/69/0/0/0/0/0/0/0 | 960.00 × 320.00 | -0.53/-0.53/960.53/320.53 | 308,566.46 | 1.00445 | 是 |
| web-674 | text__Progression-dominante-renverse-parfait-d.svg | text | 108345 | ok | 20/236/530/13/0/0/0/0/0/0/0 | 104.77 × 104.73 | -0.00/-0.01/104.78/104.73 | 10,976.06 | 1.00028 | 是 |
| web-675 | text__Romanian-Legacy-Keyboard.svg | text | 115664 | ok | 129/4396/4274/70/0/0/1/0/0/0/0 | 800.00 × 600.00 | 90.21/192.78/702.88/395.04 | 123,921.98 | 0.25817 | 否 |
| web-676 | text__Scales-and-keyboard.svg | text | 203617 | ok | 332/3660/5758/230/0/0/0/0/0/0/0 | 1000.00 × 290.00 | 0.00/-0.00/1000.00/290.00 | 289,999.97 | 1.00000 | 是 |
| web-677 | text__Tamil-Wiki-Internship-Certificate-Model-.svg | text | 1723935 | ok | 371/2127/2399/9/0/2/1/0/0/9/0 | 1122.52 × 793.70 | -101.91/-0.13/1122.52/1303.63 | 1,596,359.53 | 1.79176 | 是 |
| web-678 | text__Tamil-Wiki-Internship-Certificate-Model--2.svg | text | 1723931 | ok | 371/2127/2399/9/0/2/1/0/0/9/0 | 1122.52 × 793.70 | -101.91/-0.13/1122.52/1303.63 | 1,596,359.53 | 1.79176 | 是 |
| web-679 | text__Tupyakov-annual-calendar-10.svg | text | 501478 | ok | 867/18538/41104/37/1/0/0/0/0/0/0 | 440.00 × 549.39 | 0.40/0.00/439.14/547.45 | 240,185.47 | 0.99360 | 否 |
| web-680 | undraw__undraw-svg-collection-svgs-chatting.svg | undraw | 9105 | ok | 27/355/776/0/0/0/0/0/0/0/0 | 891.29 × 745.19 | 0.00/0.00/891.29/745.19 | 664,187.93 | 1.00000 | 否 |
| web-681 | undraw__undraw-svg-collection-svgs-checklist.svg | undraw | 8225 | ok | 23/288/596/0/0/0/0/0/0/0/0 | 800.12 × 541.45 | 0.00/0.00/800.12/541.45 | 433,222.29 | 1.00000 | 否 |
| web-682 | undraw__undraw-svg-collection-svgs-co-workers.svg | undraw | 18502 | ok | 72/800/1306/0/0/0/0/0/0/0/0 | 715.30 × 604.17 | 0.00/-0.00/715.30/604.17 | 432,160.37 | 1.00000 | 是 |
| web-683 | undraw__undraw-svg-collection-svgs-contract.svg | undraw | 14965 | ok | 39/566/1119/0/0/0/0/0/0/0/0 | 405.95 × 611.97 | -0.04/0.00/405.95/611.97 | 248,452.47 | 1.00010 | 是 |
| web-684 | undraw__undraw-svg-collection-svgs-destinations.svg | undraw | 17083 | ok | 44/542/1160/0/0/0/0/0/0/0/0 | 568.19 × 559.32 | 0.00/0.00/568.19/559.32 | 317,799.89 | 1.00000 | 是 |
| web-685 | undraw__undraw-svg-collection-svgs-fall-is-comin.svg | undraw | 205966 | ok | 569/6087/13644/38/4/237/0/0/0/0/0 | 1063.45 × 795.60 | -0.01/0.00/1063.45/795.60 | 846,086.42 | 1.00001 | 是 |
| web-686 | undraw__undraw-svg-collection-svgs-file-manager.svg | undraw | 14085 | ok | 46/465/911/0/0/3/0/0/0/0/0 | 735.16 × 684.29 | 0.00/-0.00/735.16/684.29 | 503,063.20 | 1.00000 | 是 |
| web-687 | undraw__undraw-svg-collection-svgs-for-sale.svg | undraw | 6726 | ok | 31/283/491/0/0/0/0/0/0/0/0 | 997.18 × 465.46 | 0.00/0.00/997.18/465.46 | 464,144.69 | 1.00000 | 否 |
| web-688 | undraw__undraw-svg-collection-svgs-forming-ideas.svg | undraw | 12614 | ok | 41/431/918/0/0/0/0/0/0/0/0 | 768.18 × 692.31 | 0.00/0.00/768.18/692.31 | 531,818.80 | 1.00000 | 是 |
| web-689 | undraw__undraw-svg-collection-svgs-inbox-cleanup.svg | undraw | 10584 | ok | 37/433/782/0/0/0/0/0/0/0/0 | 844.04 × 546.23 | -0.00/0.00/844.04/546.23 | 461,040.35 | 1.00000 | 是 |
| web-690 | undraw__undraw-svg-collection-svgs-live-collabor.svg | undraw | 10179 | ok | 28/350/711/0/0/1/0/0/0/0/0 | 748.76 × 544.00 | 0.00/-0.01/748.76/544.00 | 407,329.54 | 1.00002 | 是 |
| web-691 | undraw__undraw-svg-collection-svgs-mobile-feed.svg | undraw | 6067 | ok | 23/235/378/0/0/0/0/0/0/0/0 | 768.00 × 728.86 | 0.00/0.00/768.00/728.86 | 559,762.97 | 1.00000 | 是 |
| web-692 | undraw__undraw-svg-collection-svgs-my-password.svg | undraw | 9582 | ok | 28/359/720/0/0/0/0/0/0/0/0 | 493.46 × 480.85 | 0.00/0.00/493.45/480.85 | 237,274.79 | 0.99998 | 是 |
| web-693 | undraw__undraw-svg-collection-svgs-not-found.svg | undraw | 7791 | ok | 23/262/504/0/0/1/0/0/0/0/0 | 656.00 × 458.69 | 0.00/-0.00/656.00/458.69 | 300,898.30 | 1.00000 | 是 |
| web-694 | undraw__undraw-svg-collection-svgs-online-shoppi.svg | undraw | 11857 | ok | 35/463/947/0/0/0/0/0/0/0/0 | 847.69 × 656.00 | 0.00/0.00/847.69/656.00 | 556,086.52 | 1.00000 | 否 |
| web-695 | undraw__undraw-svg-collection-svgs-organized-con.svg | undraw | 8711 | ok | 34/354/680/0/0/0/0/0/0/0/0 | 766.80 × 566.46 | 0.00/0.00/766.80/566.46 | 434,364.79 | 1.00000 | 否 |
| web-696 | undraw__undraw-svg-collection-svgs-personal-info.svg | undraw | 7286 | ok | 21/224/416/0/0/0/0/0/0/0/0 | 1050.86 × 704.35 | 0.00/0.00/1050.86/704.35 | 740,177.66 | 1.00000 | 是 |
| web-697 | undraw__undraw-svg-collection-svgs-real-time-col.svg | undraw | 26724 | ok | 77/770/1560/0/0/6/0/0/0/0/0 | 883.93 × 713.75 | 0.00/0.66/883.47/713.75 | 629,984.10 | 0.99855 | 是 |
| web-698 | undraw__undraw-svg-collection-svgs-solution-mind.svg | undraw | 11218 | ok | 34/394/750/0/0/0/0/0/0/0/0 | 552.94 × 367.92 | 0.00/0.00/552.94/367.92 | 203,438.28 | 1.00000 | 否 |
| web-699 | undraw__undraw-svg-collection-svgs-successful-pu.svg | undraw | 5093 | ok | 26/212/332/0/0/0/0/0/0/0/0 | 652.00 × 570.13 | 0.00/-0.00/652.00/570.12 | 371,721.52 | 1.00000 | 是 |
| web-700 | undraw__undraw-svg-collection-svgs-to-the-moon.svg | undraw | 13386 | ok | 52/538/1185/0/0/1/0/0/0/0/0 | 693.00 × 616.00 | 0.00/0.00/693.00/616.00 | 426,888.00 | 1.00000 | 否 |
| web-701 | undraw__undraw-svg-collection-svgs-visualization.svg | undraw | 15844 | ok | 42/528/1038/0/0/2/0/0/0/0/0 | 569.91 × 687.10 | -0.00/0.00/569.91/687.10 | 391,589.78 | 1.00000 | 是 |
| web-702 | undraw__undraw-svg-collection-svgs-walk-in-the-c.svg | undraw | 22963 | ok | 93/840/1488/0/0/0/0/0/0/0/0 | 649.68 × 618.62 | 0.00/0.00/649.67/618.62 | 401,895.18 | 0.99999 | 否 |
| web-703 | undraw__undraw-svg-collection-svgs-working.svg | undraw | 20536 | ok | 72/738/1336/0/0/0/0/0/0/0/0 | 809.68 × 462.58 | 0.00/0.00/809.68/462.58 | 374,536.03 | 1.00000 | 是 |
| web-704 | undraw__undraw-svg-collection-svgs-young-and-hap.svg | undraw | 34034 | ok | 118/1312/3014/7/1/45/0/0/0/0/0 | 1040.82 × 799.22 | 0.04/-0.00/1040.79/799.23 | 831,802.43 | 0.99995 | 是 |
| web-705 | undraw__undraw-svg-svgs-animating.svg | undraw | 22318 | ok | 39/722/1489/0/0/0/0/0/0/0/0 | 581.43 × 453.25 | 0.00/-0.00/581.43/453.25 | 263,530.96 | 1.00000 | 是 |
| web-706 | undraw__undraw-svg-svgs-by-the-road.svg | undraw | 8897 | ok | 21/344/576/0/0/1/0/0/0/0/0 | 888.00 × 623.13 | 0.00/0.00/888.00/623.13 | 553,338.01 | 1.00000 | 否 |
| web-707 | undraw__undraw-svg-svgs-collection.svg | undraw | 6653 | ok | 28/292/519/0/0/1/0/0/0/0/0 | 765.87 × 589.41 | 0.00/0.00/765.87/589.41 | 451,408.69 | 1.00000 | 否 |
| web-708 | undraw__undraw-svg-svgs-fall-is-coming.svg | undraw | 203879 | ok | 569/6087/13644/38/4/237/0/0/0/0/0 | 1063.45 × 795.60 | -0.01/0.00/1063.45/795.60 | 846,086.42 | 1.00001 | 是 |
| web-709 | undraw__undraw-svg-svgs-grandma.svg | undraw | 7815 | ok | 17/247/493/0/0/1/0/0/0/0/0 | 667.19 × 648.10 | 0.00/0.00/667.19/648.10 | 432,404.55 | 1.00000 | 否 |
| web-710 | undraw__undraw-svg-svgs-laravel-and-vue.svg | undraw | 11839 | ok | 54/469/770/0/0/17/0/0/0/0/0 | 863.00 × 826.71 | -0.00/0.00/863.00/826.71 | 713,454.39 | 1.00000 | 是 |
| web-711 | undraw__undraw-svg-svgs-love-is-in-the-air.svg | undraw | 10146 | ok | 34/386/634/0/0/0/0/0/0/0/0 | 731.67 × 404.49 | 0.00/-0.00/731.67/404.49 | 295,951.18 | 1.00000 | 是 |
| web-712 | undraw__undraw-svg-svgs-markdown-file.svg | undraw | 5373 | ok | 19/350/437/0/0/0/0/0/0/0/0 | 645.62 × 800.00 | 0.00/0.00/645.62/800.00 | 516,495.39 | 1.00000 | 是 |
| web-713 | undraw__undraw-svg-svgs-outer-space.svg | undraw | 13721 | ok | 45/417/770/0/0/1/0/0/0/0/0 | 902.42 × 826.21 | 0.00/-0.00/902.42/826.21 | 745,584.33 | 1.00000 | 是 |
| web-714 | undraw__undraw-svg-svgs-speech-to-text.svg | undraw | 16444 | ok | 47/570/1164/0/0/0/0/0/0/0/0 | 833.72 × 554.00 | -0.00/0.00/833.72/554.00 | 461,882.74 | 1.00000 | 是 |

## 局限与复算

- 数据来自单台、单后端、连续出帧的静态单图场景。没有测滚动、多个图同时争预算、低刷新率设备和不触发重放的页面。新阈值的输入还需满足库已有的缓存条件。来源里存在相近图形，文件级留出仍可能弱化跨来源验证。
- 位图纹理字节按库的 RGBA8 账本计算，GPU 驱动分配、上传峰值和 SVG 原有图片占用另外计算。齐备时间使短驻留场景的收益偏低。系统热状态 0 期间仍可能发生频率变化。
- 文字、图案和复杂滤镜在清单里按 SVG 源码分类，计分采用实际解析出来的原生场景。字体、复杂滤镜和图案的支持程度会影响源 SVG 与实际绘制成本的对应关系。
- 采样前冻结的候选文件、原始逐帧数组、基线、温控、各组合估计、评价和失败原因见 [原始 JSON](raster_cache_auto_r2_raw.json)。
- 复算入口见 [报告脚本](bench_app/tool/report_raster_cache_auto_r2.py)。推送与采集见 [真机脚本](bench_app/tool/run_raster_cache_auto_r2.py)。

在 `benchmark/bench_app` 运行。先将指定工作区 so 暂存到构建覆盖目录的 `arm64-v8a/libxvg.so`，将 `XVG_BENCH_JNI_DIR` 指向该目录。用本机变量 `$LegacySvg` 指定运行时匿名输入。

```powershell
flutter build apk --profile --no-pub --android-skip-build-dependency-validation --target-platform android-arm64 -t lib/raster_cache_auto_r2_main.dart
python tool/run_raster_cache_auto_r2.py verify-apk
python tool/run_raster_cache_auto_r2.py inputs
$Scratch = '.dart_tool/raster_cache_auto_r2'
dart --packages=.dart_tool/package_config.json tool/raster_cache_auto_r2_features.dart `
  ../../rust/target/x86_64-pc-windows-msvc/release/xvg.dll `
  "$Scratch/windows_inputs.json" "$Scratch/windows_features.jsonl"
python tool/run_raster_cache_auto_r2.py plan
python tool/run_raster_cache_auto_r2.py measure --legacy-svg $LegacySvg
python tool/report_raster_cache_auto_r2.py
```

## 异常修复与重拟合

### 根因与修复

四个样本的原生 f32 内容边界映射到物理坐标后，超出插画框 0.000016–0.000335px，超过网格的 `1e-7` 容差，令 `_containedContent` 返回 null。块虽已就绪，`_addTiles` 仍以整屏裁剪要求覆盖，每帧在差集裁剪之后提交原始向量。

两个正常对照的覆盖目标为可见内容，稳态 0 帧提交向量。异常样本满宽也提交了向量，但诊断轮缓存 raster 与基线差值为 -0.508 到 -0.045ms，满宽差集裁剪下未观察到小尺寸的同等开销。渲染器在满宽下的具体跳过位置未追踪。

坐标为左、上、右、下。此轮分块原点均为屏幕 (0, 0)，因此网格覆盖矩形可直接与物理内容矩形相比。

| 样本 | 宽 dp | 插画框 px | 内容 px | contained | covered | requiredCoverage | 向量提交/帧 | 生成/重生成 | motion 帧 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| web-586 | 48 | (0, 0, 135, 201) | (0.000025, 0.000008, 135.000016, 200.999984) | null | (-2, -2, 138, 204) | (0, 0, 1080, 2340) | 78/78 | 1/0 | 0 |
| web-586 | 200 | (0, 0, 563, 839) | (0.000104, 0.000033, 563.000067, 838.999934) | null | (-2, -2, 566, 842) | (0, 0, 1080, 2340) | 78/78 | 4/0 | 0 |
| web-586 | full | (0, 0, 1080, 1611) | (0.0002, 0.000064, 1080.000128, 1610.999872) | null | (-2, -2, 1082, 1614) | (0, 0, 1080, 2340) | 78/78 | 12/0 | 0 |
| web-225 | 48 | (0, 0, 135, 154) | (0, 0, 135, 154.000017) | null | (-2, -2, 138, 156) | (0, 0, 1080, 2340) | 78/78 | 1/0 | 0 |
| web-225 | 200 | (0, 0, 563, 640) | (0, 0, 563, 640.00007) | null | (-2, -2, 566, 642) | (0, 0, 1080, 2340) | 78/78 | 4/0 | 0 |
| web-225 | full | (0, 0, 1080, 1229) | (0, 0, 1080, 1229.000135) | null | (-2, -2, 1082, 1232) | (0, 0, 1080, 2340) | 78/78 | 9/0 | 0 |
| web-341 | 48 | (0, 0, 135, 101) | (-0.000042, 0, 134.999125, 100.999371) | null | (-2, -2, 138, 104) | (0, 0, 1080, 2340) | 78/78 | 1/0 | 0 |
| web-341 | 200 | (0, 0, 563, 422) | (-0.000174, 0, 562.996349, 421.997371) | null | (-2, -2, 566, 424) | (0, 0, 1080, 2340) | 78/78 | 2/0 | 0 |
| web-341 | full | (0, 0, 1080, 810) | (-0.000335, 0, 1079.992996, 809.994953) | null | (-2, -2, 1082, 812) | (0, 0, 1080, 2340) | 78/78 | 6/0 | 0 |
| web-167 | 48 | (0, 0, 135, 108) | (0, 0, 135.000017, 108) | null | (-2, -2, 138, 110) | (0, 0, 1080, 2340) | 78/78 | 1/0 | 0 |
| web-167 | 200 | (0, 0, 563, 451) | (0, 0, 563.00007, 451) | null | (-2, -2, 566, 454) | (0, 0, 1080, 2340) | 78/78 | 2/0 | 0 |
| web-167 | full | (0, 0, 1080, 866) | (0, 0, 1080.000134, 866) | null | (-2, -2, 1082, 868) | (0, 0, 1080, 2340) | 78/78 | 6/0 | 0 |
| web-150 | 48 | (0, 0, 135, 146) | (0.000002, 0, 135, 146) | (0.000002, 0, 135, 146) | (-2, -2, 138, 148) | (0.000002, 0, 135, 146) | 0/78 | 1/0 | 0 |
| web-150 | 200 | (0, 0, 563, 609) | (0.000007, 0, 563, 609) | (0.000007, 0, 563, 609) | (-2, -2, 566, 612) | (0.000007, 0, 563, 609) | 0/78 | 4/0 | 0 |
| web-150 | full | (0, 0, 1080, 1170) | (0.000013, 0, 1080, 1170) | (0.000013, 0, 1080, 1170) | (-2, -2, 1082, 1172) | (0.000013, 0, 1080, 1170) | 0/78 | 9/0 | 0 |
| web-053 | 48 | (0, 0, 135, 96) | (0, 0, 135, 96) | (0, 0, 135, 96) | (-2, -2, 138, 98) | (0, 0, 135, 96) | 0/78 | 1/0 | 0 |
| web-053 | 200 | (0, 0, 563, 399) | (0, 0, 563, 399) | (0, 0, 563, 399) | (-2, -2, 566, 402) | (0, 0, 563, 399) | 0/78 | 2/0 | 0 |
| web-053 | full | (0, 0, 1080, 766) | (0, 0, 1080, 766) | (0, 0, 1080, 766) | (-2, -2, 1082, 768) | (0, 0, 1080, 766) | 0/78 | 6/0 | 0 |

Dart 缓存层将边界误差容差设为 0.001 物理像素，并用分块已有的边缘留量覆盖这段外扩。分块枚举限制在插画框内，省略向量前用实际可见内容检查覆盖。更大的溢出、未知边界、颜色滤镜和缺块仍走回退。回归测试 `tile padding covers subpixel overflow without vector replay` 在修复前录到 `drawPicture` 而失败，修复后只录到一块位图且与向量结果逐像素相同。

### 真机复测

同一台 SM-A566B、Flutter 3.50.1、profile、Impeller Vulkan。APK arm64 so SHA-256 为 `86463a7be4004ef0c6aed40a910663eb0355bb43d718080fd441f685d2fc41bd`。关闭探针后，每批使用 spinner 基线，每模式预热 300ms，采样至少 650ms 和 18 帧。每组合三轮，以模式 p50 的三轮中位数相减。共 72 条有效组合轮次，轮询热状态最高 0。表中额外耗时为相应模式减去同批基线，两条时间序列各取三轮中位数。

| 样本 | 宽 dp | 新基线 ms | 向量额外 ms | 旧缓存额外 ms | 新缓存额外 ms | 净收益 ms | 三轮配对净收益 ms | 块数 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| web-586 | 48 | 1.959 | 4.709 | 4.522 | 0.188 | 4.521 | 4.447/4.520/4.521 | 1 |
| web-586 | 200 | 1.959 | 4.744 | 4.565 | -0.024 | 4.768 | 4.368/5.067/4.792 | 4 |
| web-586 | full | 1.959 | 8.995 | -0.212 | -0.097 | 9.092 | 9.093/9.128/9.074 | 12 |
| web-225 | 48 | 1.959 | 4.220 | 4.333 | -0.210 | 4.430 | 3.925/4.539/4.410 | 1 |
| web-225 | 200 | 1.959 | 3.703 | 3.649 | -0.232 | 3.935 | 3.869/4.684/3.499 | 4 |
| web-225 | full | 1.959 | 8.073 | 0.034 | -0.176 | 8.249 | 8.090/8.262/8.488 | 9 |
| web-341 | 48 | 1.959 | 4.413 | 4.623 | 0.228 | 4.185 | 3.615/4.173/4.227 | 1 |
| web-341 | 200 | 1.959 | 3.969 | 3.830 | 0.160 | 3.809 | 3.658/4.355/3.744 | 2 |
| web-341 | full | 1.959 | 4.117 | 0.420 | -0.118 | 4.235 | 4.329/4.117/4.613 | 6 |
| web-167 | 48 | 2.075 | 1.794 | 2.521 | -0.013 | 1.807 | 1.917/2.422/1.590 | 1 |
| web-167 | 200 | 2.075 | 2.315 | 1.587 | -0.165 | 2.480 | 1.597/2.870/2.388 | 2 |
| web-167 | full | 2.075 | 1.689 | 0.110 | -0.080 | 1.769 | 1.769/1.283/2.537 | 6 |
| web-150 | 48 | 2.075 | 12.661 | 0.274 | -0.375 | 13.036 | 13.263/13.049/12.656 | 1 |
| web-150 | 200 | 2.075 | 15.396 | -0.213 | -0.070 | 15.466 | 15.718/15.466/15.315 | 4 |
| web-150 | full | 2.075 | 15.965 | -0.439 | -0.026 | 15.991 | 16.254/16.450/15.991 | 9 |
| web-053 | 48 | 2.075 | 2.227 | 0.075 | 0.118 | 2.109 | 2.344/2.278/2.109 | 1 |
| web-053 | 200 | 2.075 | 2.757 | 0.077 | 0.161 | 2.596 | 2.577/1.922/2.596 | 2 |
| web-053 | full | 2.075 | 2.117 | -0.283 | -0.214 | 2.331 | 2.867/2.333/2.062 | 6 |
| web-543 | 48 | 1.920 | 111.909 | -0.484 | -0.318 | 112.227 | 113.199/112.227/111.743 | 1 |
| web-469 | 48 | 1.920 | 17.833 | -0.085 | 0.171 | 17.662 | 17.412/17.662/17.729 | 1 |
| web-583 | 48 | 1.920 | 2.792 | 0.129 | -0.033 | 2.825 | 2.656/2.869/2.870 | 1 |
| web-583 | 200 | 1.920 | 2.160 | 0.162 | 0.275 | 1.885 | 2.764/1.849/1.912 | 4 |
| web-206 | 48 | 1.920 | 2.498 | 0.129 | 0.116 | 2.382 | 2.146/1.271/2.382 | 1 |
| web-206 | 200 | 1.920 | 1.497 | -0.038 | 0.063 | 1.434 | 1.542/1.434/1.489 | 4 |

8 个异常尺寸组合的缓存额外耗时降到 -0.232 至 0.228ms。另抽的 6 个正常组合缓存额外耗时为 -0.318 至 0.275ms，三轮均为正收益，驻留块数与第二轮一致。

### 新规则与命中

**内容在框内、可见内容非空、（点数 ≥ 15,000 或 路径数 ≥ 100）、预计单图纹理 ≤ 12 MiB。** 继续应用原有网格稳定、颜色滤镜和全局预算条件。可见内容非空用于排除无绘制工作，无正数面积门槛。

只替换四个异常样本的 48/200dp 共 8 个组合，沿用原组别和其他计分数据。搜索原 9 个点数阈值，路径数门槛取关闭、100、250、500、1,000，模糊项取关闭或任意模糊，纹理上限取 4、6、8、12 MiB。各成本条件取或。候选须在拟合组图标启用为 0、无非正中位收益且无单轮非正收益，再按第二轮的命中减两倍微利计分。平分先比较命中、微利、单图上限，再优先省去成本条件，最后比较收益总和。留出仅用于评价。

| 规则 | 组 | 组合 | 启用 | 命中 >1ms | 误开 ≤0 | 微利 (0,1]ms | 漏开 >1ms | 其余关闭 | 图标启用 | 启用且有重复轮 ≤0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 原规则 / 原数据 | 拟合 | 417 | 27 | 26 | 0 | 1 | 151 | 239 | 0 | 0 |
| 原规则 / 原数据 | 留出 | 180 | 8 | 6 | 0 | 2 | 57 | 115 | 0 | 0 |
| 原规则 / 替换后 | 拟合 | 417 | 27 | 26 | 0 | 1 | 157 | 233 | 0 | 0 |
| 原规则 / 替换后 | 留出 | 180 | 8 | 6 | 0 | 2 | 59 | 113 | 0 | 0 |
| 新规则 / 替换后 | 拟合 | 417 | 153 | 145 | 0 | 8 | 38 | 226 | 0 | 0 |
| 新规则 / 替换后 | 留出 | 180 | 48 | 47 | 0 | 1 | 18 | 114 | 0 | 0 |

点数 ≥ 10,000 或有模糊的粗算规则会启用拟合组 web-564/48dp，其三轮配对收益为 632、−35、953µs，点数 12,078 且只有 1 条路径，故被新规则排除。若只把新规则上限调回 8 MiB，拟合命中 142，留出命中 46。按新规则启用的网上样本，设备实测纹理最高 10.80 MiB。

第一轮样本作为独立检查，命中 8、误开 0、微利启用 0、图标启用 0、启用且有重复轮 ≤0 的组合 0。原始逐帧数据、诊断事件、拟合参数及分组统计见原始 JSON 的 `anomaly_fix_refit`。

复算时，按 `replaced_case_keys` 用 `retest_cases` 对应项覆盖原 `cases`，以 `fit(..., fixed_area=0, allow_blur=False, path_grid=PATH_GRID, allow_any_blur=True)` 选规则，再对各组调用 `evaluate`。
