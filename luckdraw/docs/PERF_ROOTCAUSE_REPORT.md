# PEND 离线逐帧根因分析

仅分析保存的原始 timeline，没有连接手机、adb、Gradle、build 或 drive。

## 方法与边界

从 MET 全量130窗口索引选择四场景全部未污染窗口；按 report_key/run_id 去重，保留旧 DEV 与正式 PERF 身份。不混合它们计算当前实现的预算。B/E 用同线程栈配对，b/e 按进程/分类/名称/id 配对，X 直接读 dur。按 Animator::BeginFrame 与 Rasterizer::DoDraw 的 frame_number 关联异步 Frame 和 GPURasterizer::Draw；逐项核对重建 UI/Raster 时长数组与 SDK summary 完全相等，拒绝按时间最近或独立分位数相加。

尖峰定义：同帧 UI Frame + GPURasterizer::Draw >12ms，或 UI Frame >4ms。位置从窗口首个完整 Frame 起算，序号从1开始。这里是 SDK trace 区间；保存的硬门禁来自 FrameTiming，二者采集边界可能不同，原 MET2 FrameTiming P99 仍为门禁依据。表内事件为包含时长（inclusive），父子嵌套不能相加；墙钟时间不等于 CPU 执行时间。普通帧指上述条件都不触发的帧。未闭合的边界事件记录到 JSON，不伪造耗时。

所有逐帧原始统计、事件时长、帧号、来源与 SHA-256：[frames.json](../tool/bench/results/pend_offline/frames.json)。离线重放：`python tool/bench/analyze_frames.py`。

## 每窗口汇总

| 场景 / run_id | 身份 | 帧数 | 合计>12 / UI>4 / 并集 | 尖峰位置 ms | UI/Raster均值 ms |
| --- | --- | --- | --- | --- | --- |
| grid_steady / 1794305776155025 | 历史DEV | 297 | 0 / 0 / 0 | 无 | 1.121/5.887 |
| grid_steady / 1794305881436541 | 历史DEV | 298 | 1 / 1 / 2 | 1883.4–3883.7 | 0.864/5.478 |
| grid_steady / 1794305983682447 | 历史DEV | 298 | 0 / 0 / 0 | 无 | 0.994/3.615 |
| lots_shaking / 1794308933597372 | MET2正式 | 301 | 0 / 0 / 0 | 无 | 1.512/4.760 |
| lots_shaking / 1794309094772711 | MET2正式 | 301 | 0 / 0 / 0 | 无 | 1.327/3.139 |
| lotto_draw / 1794309329997426 | 历史DEV | 273 | 4 / 50 / 52 | 82.9–4366.3 | 2.878/6.111 |
| lotto_draw / 1794309404767165 | 历史DEV | 274 | 4 / 40 / 42 | 317.7–4551.8 | 2.732/5.726 |
| lotto_draw / 1794309488538708 | 历史DEV | 274 | 8 / 50 / 53 | 866.9–4550.8 | 2.564/5.938 |
| slot_raster / 1794306159431550 | MET2正式 | 301 | 0 / 0 / 0 | 无 | 1.171/2.823 |
| slot_raster / 1794306659957714 | MET2正式 | 301 | 0 / 0 / 0 | 无 | 0.752/2.786 |
| slot_raster / 1794306825736505 | MET2正式 | 300 | 5 / 0 / 5 | 1050.3–4083.7 | 1.132/5.926 |
| grid_steady / 1794314642091899 | MET2正式 | 298 | 5 / 0 / 5 | 3183.6–4901.0 | 1.034/5.562 |
| grid_steady / 1794314716054046 | MET2正式 | 298 | 0 / 0 / 0 | 无 | 1.146/3.491 |
| grid_steady / 1794314791537683 | MET2正式 | 297 | 2 / 1 / 3 | 1616.9–2151.3 | 1.047/5.864 |
| lotto_draw / 1794314421829493 | MET2正式 | 275 | 4 / 12 / 16 | 449.5–4549.9 | 2.438/5.248 |
| lotto_draw / 1794314571366953 | MET2正式 | 275 | 2 / 8 / 8 | 717.2–4550.8 | 2.234/4.696 |

## slot_raster 尖峰帧完整清单

| run_id | 帧序号 / 引擎帧号 | 位置 ms | UI / Raster / 合计 ms | 最长三个内层事件 ms（含嵌套） | UI最长事件 ms |
| --- | --- | --- | --- | --- | --- |
| 1794306825736505 | 64 / 3989 | 1050.342 | 1.423 / 15.769 / 17.192 | Rasterizer::DrawToSurfaces 15.628；SurfaceFrame::Submit 15.346；SurfaceFrame::Encode 13.592 | COMPOSITING 0.518；PAINT (root) 0.343 |
| 1794306825736505 | 65 / 3990 | 1067.022 | 1.724 / 12.995 / 14.719 | Rasterizer::DrawToSurfaces 12.962；SurfaceFrame::Submit 12.679；SurfaceFrame::Encode 10.899 | COMPOSITING 0.608；PAINT (root) 0.346 |
| 1794306825736505 | 114 / 4039 | 1883.044 | 0.943 / 11.543 / 12.486 | Rasterizer::DrawToSurfaces 11.434；SurfaceFrame::Submit 11.111；SurfaceFrame::Encode 9.523 | COMPOSITING 0.267；PAINT (root) 0.241 |
| 1794306825736505 | 245 / 4170 | 4066.778 | 1.572 / 16.104 / 17.676 | Rasterizer::DrawToSurfaces 16.023；SurfaceFrame::Submit 15.740；SurfaceFrame::Encode 13.889 | PAINT (root) 0.522；PAINT 0.503 |
| 1794306825736505 | 246 / 4171 | 4083.720 | 1.648 / 15.622 / 17.270 | Rasterizer::DrawToSurfaces 15.569；SurfaceFrame::Submit 15.273；SurfaceFrame::Encode 13.370 | COMPOSITING 0.583；PAINT (root) 0.514 |

位置统计（每秒分桶；首5帧单列；仅说明分布，不推断随机性）：

| run_id | 首5帧尖峰数 | 秒桶 [0,1,2,3,4] | 无配对UI / Raster | 无配对UI>4ms |
| --- | --- | --- | --- | --- |
| 1794306159431550 | 0 | [0, 0, 0, 0, 0] | 0 / 0 | 0 |
| 1794306659957714 | 0 | [0, 0, 0, 0, 0] | 0 / 0 | 0 |
| 1794306825736505 | 0 | [0, 3, 0, 0, 2] | 1 / 0 | 0 |

### 事件归因与普通帧对照

| 身份 / 事件 | 尖峰累计 ms / 每帧均值 ms | 普通累计 ms / 每帧均值 ms |
| --- | --- | --- |
| 正式 / Animate | 1.093 / 0.219 | 135.447 / 0.151 |
| 正式 / BUILD | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / CollectNewGeneration | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / CreateGlyphAtlas | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / Dart_InvokeClosure | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / LAYOUT | 0.037 / 0.007 | 5.520 / 0.006 |
| 正式 / LayerTree::Paint | 0.210 / 0.042 | 34.868 / 0.039 |
| 正式 / PAINT | 1.879 / 0.376 | 235.687 / 0.263 |
| 正式 / Rasterizer::DrawToSurfaces | 71.616 / 14.323 | 3358.802 / 3.744 |
| 正式 / ReactorGLES::React | 60.463 / 12.093 | 1384.562 / 1.544 |
| 正式 / RenderPassGLES::EncodeCommandsInReactor | 60.209 / 12.042 | 1341.550 / 1.496 |
| 正式 / SEMANTICS | 0.213 / 0.043 | 32.861 / 0.037 |
| 正式 / Scavenge | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / SurfaceFrame::Encode | 61.273 / 12.255 | 1520.130 / 1.695 |
| 正式 / SurfaceFrame::Submit | 70.149 / 14.030 | 3108.868 / 3.466 |

各窗口普通帧事件均值（ms，框架事件包含时长）：

| run_id | 普通帧数 | Encode | GLES Encode | PAINT | Animate | COMPOSITING |
| --- | --- | --- | --- | --- | --- | --- |
| 1794306159431550 | 301 | 0.691 | 0.492 | 0.300 | 0.165 | 0.393 |
| 1794306659957714 | 301 | 0.684 | 0.492 | 0.203 | 0.124 | 0.238 |
| 1794306825736505 | 295 | 3.750 | 3.544 | 0.285 | 0.164 | 0.371 |

## grid_steady 尖峰帧完整清单

| run_id | 帧序号 / 引擎帧号 | 位置 ms | UI / Raster / 合计 ms | 最长三个内层事件 ms（含嵌套） | UI最长事件 ms |
| --- | --- | --- | --- | --- | --- |
| 1794305881436541 | 114 / 1070 | 1883.352 | 0.821 / 11.249 / 12.070 | Rasterizer::DrawToSurfaces 11.222；SurfaceFrame::Submit 10.975；SurfaceFrame::Encode 9.294 | PAINT (root) 0.305；PAINT 0.296 |
| 1794305881436541 | 234 / 1190 | 3883.656 | 4.020 / 3.646 / 7.666 | Rasterizer::DrawToSurfaces 3.583；PAINT (root) 3.415；PAINT 3.399 | PAINT (root) 3.415；PAINT 3.399 |
| 1794314642091899 | 192 / 1147 | 3183.644 | 1.231 / 13.587 / 14.818 | Rasterizer::DrawToSurfaces 13.533；SurfaceFrame::Submit 13.274；SurfaceFrame::Encode 11.543 | PAINT (root) 0.462；PAINT 0.451 |
| 1794314642091899 | 193 / 1148 | 3200.520 | 0.766 / 13.004 / 13.770 | Rasterizer::DrawToSurfaces 12.975；SurfaceFrame::Submit 12.731；SurfaceFrame::Encode 11.098 | COMPOSITING 0.317；Animate 0.138 |
| 1794314642091899 | 293 / 1248 | 4867.174 | 0.611 / 11.666 / 12.277 | Rasterizer::DrawToSurfaces 11.632；SurfaceFrame::Submit 11.375；SurfaceFrame::Encode 9.656 | COMPOSITING 0.280；Animate 0.126 |
| 1794314642091899 | 294 / 1249 | 4883.663 | 1.155 / 14.757 / 15.912 | Rasterizer::DrawToSurfaces 14.708；SurfaceFrame::Submit 14.426；SurfaceFrame::Encode 12.143 | PAINT (root) 0.461；PAINT 0.450 |
| 1794314642091899 | 295 / 1250 | 4901.030 | 1.376 / 10.634 / 12.010 | Rasterizer::DrawToSurfaces 10.598；SurfaceFrame::Submit 10.044；SurfaceFrame::Encode 8.239 | COMPOSITING 0.644；SEMANTICS (root) 0.329 |
| 1794314791537683 | 98 / 1056 | 1616.897 | 1.592 / 14.483 / 16.075 | Rasterizer::DrawToSurfaces 14.436；SurfaceFrame::Submit 14.156；SurfaceFrame::Encode 12.353 | COMPOSITING 0.587；PAINT (root) 0.567 |
| 1794314791537683 | 99 / 1057 | 1633.683 | 1.048 / 14.676 / 15.724 | Rasterizer::DrawToSurfaces 14.622；SurfaceFrame::Submit 14.357；SurfaceFrame::Encode 12.523 | COMPOSITING 0.354；Animate 0.267 |
| 1794314791537683 | 130 / 1088 | 2151.255 | 4.296 / 3.640 / 7.936 | Rasterizer::DrawToSurfaces 3.602；SurfaceFrame::Submit 3.301；COMPOSITING 2.550 | COMPOSITING 2.550；PAINT (root) 1.082 |

位置统计（每秒分桶；首5帧单列；仅说明分布，不推断随机性）：

| run_id | 首5帧尖峰数 | 秒桶 [0,1,2,3,4] | 无配对UI / Raster | 无配对UI>4ms |
| --- | --- | --- | --- | --- |
| 1794305776155025 | 0 | [0, 0, 0, 0, 0] | 1 / 0 | 0 |
| 1794305881436541 | 0 | [0, 1, 0, 1, 0] | 0 / 0 | 0 |
| 1794305983682447 | 0 | [0, 0, 0, 0, 0] | 0 / 0 | 0 |
| 1794314642091899 | 0 | [0, 0, 0, 2, 3] | 0 / 0 | 0 |
| 1794314716054046 | 0 | [0, 0, 0, 0, 0] | 0 / 0 | 0 |
| 1794314791537683 | 0 | [0, 2, 1, 0, 0] | 1 / 0 | 0 |

### 事件归因与普通帧对照

| 身份 / 事件 | 尖峰累计 ms / 每帧均值 ms | 普通累计 ms / 每帧均值 ms |
| --- | --- | --- |
| 正式 / Animate | 1.370 / 0.171 | 135.720 / 0.153 |
| 正式 / BUILD | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / COMPOSITING | 5.239 / 0.655 | 313.101 / 0.354 |
| 正式 / CollectNewGeneration | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / CreateGlyphAtlas | 0.233 / 0.029 | 25.760 / 0.029 |
| 正式 / Dart_InvokeClosure | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / LAYOUT | 0.050 / 0.006 | 5.232 / 0.006 |
| 正式 / LayerTree::Paint | 0.319 / 0.040 | 34.490 / 0.039 |
| 正式 / PAINT | 2.539 / 0.317 | 248.399 / 0.281 |
| 正式 / Rasterizer::DrawToSurfaces | 96.106 / 12.013 | 4308.115 / 4.868 |
| 正式 / ReactorGLES::React | 75.760 / 9.470 | 2165.472 / 2.447 |
| 正式 / RenderPassGLES::EncodeCommandsInReactor | 75.344 / 9.418 | 2117.947 / 2.393 |
| 正式 / SEMANTICS | 0.570 / 0.071 | 33.408 / 0.038 |
| 正式 / Scavenge | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / SurfaceFrame::Encode | 79.015 / 9.877 | 2517.632 / 2.845 |
| 正式 / SurfaceFrame::Submit | 93.664 / 11.708 | 4068.237 / 4.597 |
| 历史 / Animate | 0.225 / 0.113 | 137.506 / 0.154 |
| 历史 / BUILD | 0.000 / 0.000 | 0.000 / 0.000 |
| 历史 / CollectNewGeneration | 0.000 / 0.000 | 0.000 / 0.000 |
| 历史 / CreateGlyphAtlas | 0.058 / 0.029 | 26.080 / 0.029 |
| 历史 / Dart_InvokeClosure | 0.000 / 0.000 | 0.000 / 0.000 |
| 历史 / LAYOUT | 0.008 / 0.004 | 4.970 / 0.006 |
| 历史 / LayerTree::Paint | 0.072 / 0.036 | 35.356 / 0.040 |
| 历史 / PAINT | 3.695 / 1.847 | 184.541 / 0.207 |
| 历史 / PAINT (root) | 3.720 / 1.860 | 195.538 / 0.219 |
| 历史 / Rasterizer::DrawToSurfaces | 14.805 / 7.402 | 4408.485 / 4.948 |
| 历史 / ReactorGLES::React | 9.692 / 4.846 | 2156.392 / 2.420 |
| 历史 / RenderPassGLES::EncodeCommandsInReactor | 9.592 / 4.796 | 2107.876 / 2.366 |
| 历史 / SEMANTICS | 0.043 / 0.021 | 30.806 / 0.035 |
| 历史 / Scavenge | 0.000 / 0.000 | 0.000 / 0.000 |
| 历史 / SurfaceFrame::Encode | 10.903 / 5.452 | 2606.040 / 2.925 |
| 历史 / SurfaceFrame::Submit | 14.292 / 7.146 | 4165.653 / 4.675 |

各窗口普通帧事件均值（ms，框架事件包含时长）：

| run_id | 普通帧数 | Encode | GLES Encode | PAINT | Animate | COMPOSITING |
| --- | --- | --- | --- | --- | --- | --- |
| 1794305776155025 | 297 | 3.804 | 3.220 | 0.235 | 0.180 | 0.407 |
| 1794305881436541 | 296 | 3.480 | 2.927 | 0.179 | 0.135 | 0.313 |
| 1794305983682447 | 298 | 1.498 | 0.956 | 0.207 | 0.148 | 0.370 |
| 1794314642091899 | 293 | 3.474 | 3.043 | 0.268 | 0.147 | 0.340 |
| 1794314716054046 | 298 | 1.357 | 0.903 | 0.297 | 0.159 | 0.381 |
| 1794314791537683 | 294 | 3.726 | 3.256 | 0.276 | 0.154 | 0.339 |

## lotto_draw 尖峰帧完整清单

| run_id | 帧序号 / 引擎帧号 | 位置 ms | UI / Raster / 合计 ms | 最长三个内层事件 ms（含嵌套） | UI最长事件 ms |
| --- | --- | --- | --- | --- | --- |
| 1794309329997426 | 6 / 1161 | 82.916 | 4.046 / 7.126 / 11.172 | Rasterizer::DrawToSurfaces 7.086；SurfaceFrame::Submit 6.784；SurfaceFrame::Encode 4.992 | PAINT (root) 2.450；PAINT 2.427 |
| 1794309329997426 | 9 / 1164 | 133.842 | 5.212 / 6.481 / 11.693 | Rasterizer::DrawToSurfaces 6.266；SurfaceFrame::Submit 5.955；SurfaceFrame::Encode 4.025 | PAINT (root) 2.501；PAINT 2.480 |
| 1794309329997426 | 19 / 1174 | 299.587 | 4.821 / 6.300 / 11.121 | Rasterizer::DrawToSurfaces 6.257；SurfaceFrame::Submit 5.897；SurfaceFrame::Encode 4.126 | PAINT (root) 2.616；PAINT 2.593 |
| 1794309329997426 | 23 / 1178 | 366.518 | 4.671 / 6.336 / 11.007 | Rasterizer::DrawToSurfaces 6.296；SurfaceFrame::Submit 5.997；SurfaceFrame::Encode 4.137 | PAINT (root) 2.287；PAINT 2.266 |
| 1794309329997426 | 25 / 1180 | 400.431 | 5.764 / 6.701 / 12.465 | Rasterizer::DrawToSurfaces 6.661；SurfaceFrame::Submit 6.366；SurfaceFrame::Encode 4.165 | PAINT (root) 2.990；PAINT 2.965 |
| 1794309329997426 | 28 / 1183 | 449.821 | 4.846 / 6.514 / 11.360 | Rasterizer::DrawToSurfaces 6.443；SurfaceFrame::Submit 6.130；SurfaceFrame::Encode 4.114 | PAINT (root) 2.770；PAINT 2.746 |
| 1794309329997426 | 31 / 1186 | 500.807 | 4.165 / 6.164 / 10.329 | Rasterizer::DrawToSurfaces 6.124；SurfaceFrame::Submit 5.784；SurfaceFrame::Encode 4.006 | PAINT (root) 2.273；PAINT 2.252 |
| 1794309329997426 | 36 / 1191 | 583.347 | 5.130 / 6.108 / 11.238 | Rasterizer::DrawToSurfaces 6.070；SurfaceFrame::Submit 5.779；SurfaceFrame::Encode 4.001 | PAINT (root) 3.028；PAINT 3.006 |
| 1794309329997426 | 37 / 1192 | 600.215 | 4.127 / 6.330 / 10.457 | Rasterizer::DrawToSurfaces 6.289；SurfaceFrame::Submit 5.996；SurfaceFrame::Encode 4.200 | PAINT (root) 2.266；PAINT 2.246 |
| 1794309329997426 | 38 / 1193 | 616.677 | 5.243 / 6.470 / 11.713 | Rasterizer::DrawToSurfaces 6.430；SurfaceFrame::Submit 6.118；SurfaceFrame::Encode 4.091 | PAINT (root) 3.561；PAINT 3.540 |
| 1794309329997426 | 39 / 1194 | 633.476 | 4.256 / 6.631 / 10.887 | Rasterizer::DrawToSurfaces 6.558；SurfaceFrame::Submit 6.235；SurfaceFrame::Encode 4.129 | PAINT (root) 2.606；PAINT 2.494 |
| 1794309329997426 | 78 / 1233 | 1282.943 | 4.349 / 6.327 / 10.676 | Rasterizer::DrawToSurfaces 6.289；SurfaceFrame::Submit 5.988；SurfaceFrame::Encode 4.101 | PAINT (root) 2.282；PAINT 2.258 |
| 1794309329997426 | 79 / 1234 | 1300.468 | 4.578 / 6.155 / 10.733 | Rasterizer::DrawToSurfaces 6.115；SurfaceFrame::Submit 5.816；SurfaceFrame::Encode 4.043 | PAINT (root) 3.241；PAINT 3.218 |
| 1794309329997426 | 82 / 1237 | 1349.691 | 4.632 / 6.057 / 10.689 | Rasterizer::DrawToSurfaces 6.018；SurfaceFrame::Submit 5.735；SurfaceFrame::Encode 3.876 | PAINT (root) 2.354；PAINT 2.333 |
| 1794309329997426 | 83 / 1238 | 1366.377 | 4.368 / 6.354 / 10.722 | Rasterizer::DrawToSurfaces 6.317；SurfaceFrame::Submit 6.000；SurfaceFrame::Encode 4.209 | PAINT (root) 2.224；PAINT 2.202 |
| 1794309329997426 | 87 / 1242 | 1433.411 | 4.323 / 6.447 / 10.770 | Rasterizer::DrawToSurfaces 6.408；SurfaceFrame::Submit 6.099；SurfaceFrame::Encode 4.155 | PAINT (root) 2.978；PAINT 2.952 |
| 1794309329997426 | 91 / 1246 | 1499.634 | 4.681 / 6.002 / 10.683 | Rasterizer::DrawToSurfaces 5.896；SurfaceFrame::Submit 5.608；SurfaceFrame::Encode 3.768 | PAINT (root) 2.043；PAINT 2.025 |
| 1794309329997426 | 95 / 1250 | 1566.746 | 4.270 / 6.225 / 10.495 | Rasterizer::DrawToSurfaces 6.187；SurfaceFrame::Submit 5.888；SurfaceFrame::Encode 4.068 | PAINT (root) 2.481；PAINT 2.460 |
| 1794309329997426 | 96 / 1251 | 1583.487 | 4.070 / 6.150 / 10.220 | Rasterizer::DrawToSurfaces 6.103；SurfaceFrame::Submit 5.810；SurfaceFrame::Encode 4.027 | PAINT (root) 2.199；PAINT 2.178 |
| 1794309329997426 | 97 / 1252 | 1600.156 | 5.124 / 6.284 / 11.408 | Rasterizer::DrawToSurfaces 6.248；SurfaceFrame::Submit 5.792；SurfaceFrame::Encode 4.023 | PAINT (root) 2.750；PAINT 2.727 |
| 1794309329997426 | 104 / 1259 | 1717.252 | 4.020 / 6.112 / 10.132 | Rasterizer::DrawToSurfaces 6.074；SurfaceFrame::Submit 5.779；SurfaceFrame::Encode 3.987 | PAINT (root) 2.259；PAINT 2.236 |
| 1794309329997426 | 105 / 1260 | 1733.256 | 4.687 / 6.714 / 11.401 | Rasterizer::DrawToSurfaces 6.277；SurfaceFrame::Submit 5.958；SurfaceFrame::Encode 4.135 | PAINT (root) 2.410；PAINT 2.389 |
| 1794309329997426 | 112 / 1267 | 1849.862 | 4.262 / 6.721 / 10.983 | Rasterizer::DrawToSurfaces 6.650；SurfaceFrame::Submit 6.343；SurfaceFrame::Encode 4.351 | PAINT (root) 2.418；PAINT 2.398 |
| 1794309329997426 | 114 / 1269 | 1883.376 | 4.170 / 6.450 / 10.620 | Rasterizer::DrawToSurfaces 6.408；SurfaceFrame::Submit 6.100；SurfaceFrame::Encode 4.327 | PAINT (root) 2.309；PAINT 2.286 |
| 1794309329997426 | 116 / 1271 | 1916.701 | 4.228 / 6.151 / 10.379 | Rasterizer::DrawToSurfaces 6.112；SurfaceFrame::Submit 5.647；SurfaceFrame::Encode 3.904 | PAINT (root) 2.068；PAINT 2.046 |
| 1794309329997426 | 117 / 1272 | 1933.898 | 3.638 / 14.253 / 17.891 | Rasterizer::DrawToSurfaces 14.199；SurfaceFrame::Submit 13.899；SurfaceFrame::Encode 12.019 | PAINT (root) 2.343；PAINT 2.316 |
| 1794309329997426 | 118 / 1273 | 1949.712 | 2.931 / 13.315 / 16.246 | Rasterizer::DrawToSurfaces 13.268；SurfaceFrame::Submit 12.975；SurfaceFrame::Encode 10.273 | PAINT (root) 1.989；PAINT 1.971 |
| 1794309329997426 | 121 / 1276 | 2000.640 | 4.322 / 6.497 / 10.819 | Rasterizer::DrawToSurfaces 6.455；SurfaceFrame::Submit 5.961；SurfaceFrame::Encode 4.084 | PAINT (root) 2.089；PAINT 2.069 |
| 1794309329997426 | 122 / 1277 | 2016.674 | 4.642 / 6.479 / 11.121 | Rasterizer::DrawToSurfaces 6.439；SurfaceFrame::Submit 6.131；SurfaceFrame::Encode 4.195 | PAINT (root) 2.273；PAINT 2.254 |
| 1794309329997426 | 123 / 1278 | 2033.274 | 4.701 / 6.206 / 10.907 | Rasterizer::DrawToSurfaces 6.168；SurfaceFrame::Submit 5.881；SurfaceFrame::Encode 3.912 | PAINT (root) 3.047；PAINT 3.025 |
| 1794309329997426 | 126 / 1281 | 2083.058 | 4.210 / 6.874 / 11.084 | Rasterizer::DrawToSurfaces 6.804；SurfaceFrame::Submit 6.195；SurfaceFrame::Encode 4.304 | PAINT (root) 2.433；PAINT 2.410 |
| 1794309329997426 | 207 / 1362 | 3433.472 | 4.156 / 6.522 / 10.678 | Rasterizer::DrawToSurfaces 6.478；SurfaceFrame::Submit 6.164；SurfaceFrame::Encode 3.974 | PAINT (root) 2.780；PAINT 2.757 |
| 1794309329997426 | 208 / 1363 | 3449.910 | 4.395 / 6.508 / 10.903 | Rasterizer::DrawToSurfaces 6.464；SurfaceFrame::Submit 6.138；SurfaceFrame::Encode 4.096 | PAINT (root) 2.973；PAINT 2.952 |
| 1794309329997426 | 209 / 1364 | 3466.787 | 4.574 / 6.440 / 11.014 | Rasterizer::DrawToSurfaces 6.399；SurfaceFrame::Submit 6.034；SurfaceFrame::Encode 4.144 | PAINT (root) 3.316；PAINT 3.292 |
| 1794309329997426 | 214 / 1369 | 3549.942 | 4.660 / 6.132 / 10.792 | Rasterizer::DrawToSurfaces 6.095；SurfaceFrame::Submit 5.793；SurfaceFrame::Encode 3.950 | PAINT (root) 2.944；PAINT 2.922 |
| 1794309329997426 | 215 / 1370 | 3566.898 | 4.539 / 5.936 / 10.475 | Rasterizer::DrawToSurfaces 5.897；SurfaceFrame::Submit 5.593；SurfaceFrame::Encode 3.810 | PAINT (root) 2.733；PAINT 2.711 |
| 1794309329997426 | 217 / 1372 | 3600.109 | 4.222 / 6.165 / 10.387 | Rasterizer::DrawToSurfaces 6.072；SurfaceFrame::Submit 5.766；SurfaceFrame::Encode 3.983 | PAINT (root) 2.135；PAINT 2.116 |
| 1794309329997426 | 219 / 1374 | 3633.679 | 4.149 / 6.601 / 10.750 | Rasterizer::DrawToSurfaces 6.561；SurfaceFrame::Submit 6.258；SurfaceFrame::Encode 4.160 | PAINT (root) 2.763；PAINT 2.742 |
| 1794309329997426 | 223 / 1378 | 3700.107 | 4.267 / 6.263 / 10.530 | Rasterizer::DrawToSurfaces 6.223；SurfaceFrame::Submit 5.884；SurfaceFrame::Encode 4.087 | PAINT (root) 2.087；PAINT 2.065 |
| 1794309329997426 | 225 / 1380 | 3733.384 | 4.522 / 6.422 / 10.944 | Rasterizer::DrawToSurfaces 6.380；SurfaceFrame::Submit 6.069；SurfaceFrame::Encode 4.225 | PAINT (root) 2.294；PAINT 2.273 |
| 1794309329997426 | 227 / 1382 | 3766.900 | 4.424 / 6.037 / 10.461 | Rasterizer::DrawToSurfaces 5.997；SurfaceFrame::Submit 5.698；SurfaceFrame::Encode 3.915 | PAINT (root) 2.935；PAINT 2.914 |
| 1794309329997426 | 231 / 1386 | 3833.423 | 6.076 / 6.555 / 12.631 | Rasterizer::DrawToSurfaces 6.489；SurfaceFrame::Submit 6.195；PAINT (root) 4.752 | PAINT (root) 4.752；PAINT 4.727 |
| 1794309329997426 | 234 / 1389 | 3882.916 | 4.152 / 6.424 / 10.576 | Rasterizer::DrawToSurfaces 6.386；SurfaceFrame::Submit 6.088；SurfaceFrame::Encode 4.316 | PAINT (root) 3.047；PAINT 2.935 |
| 1794309329997426 | 235 / 1390 | 3900.181 | 4.879 / 6.349 / 11.228 | Rasterizer::DrawToSurfaces 6.310；SurfaceFrame::Submit 5.971；SurfaceFrame::Encode 4.193 | PAINT (root) 2.754；PAINT 2.643 |
| 1794309329997426 | 239 / 1394 | 3966.688 | 5.140 / 6.038 / 11.178 | Rasterizer::DrawToSurfaces 6.000；SurfaceFrame::Submit 5.715；SurfaceFrame::Encode 3.914 | PAINT (root) 3.017；PAINT 2.820 |
| 1794309329997426 | 242 / 1397 | 4016.814 | 4.194 / 6.336 / 10.530 | Rasterizer::DrawToSurfaces 6.295；SurfaceFrame::Submit 5.804；SurfaceFrame::Encode 3.863 | PAINT (root) 2.559；PAINT 2.538 |
| 1794309329997426 | 248 / 1403 | 4116.466 | 5.024 / 2.813 / 7.837 | PAINT (root) 3.289；PAINT 3.272；Rasterizer::DrawToSurfaces 2.792 | PAINT (root) 3.289；PAINT 3.272 |
| 1794309329997426 | 255 / 1410 | 4233.396 | 4.527 / 6.097 / 10.624 | Rasterizer::DrawToSurfaces 5.960；SurfaceFrame::Submit 5.577；SurfaceFrame::Encode 3.749 | PAINT (root) 2.455；PAINT 2.435 |
| 1794309329997426 | 257 / 1412 | 4266.821 | 4.150 / 5.879 / 10.029 | Rasterizer::DrawToSurfaces 5.844；SurfaceFrame::Submit 5.577；SurfaceFrame::Encode 3.794 | PAINT (root) 2.579；PAINT 2.556 |
| 1794309329997426 | 261 / 1416 | 4333.858 | 4.352 / 5.941 / 10.293 | Rasterizer::DrawToSurfaces 5.904；SurfaceFrame::Submit 5.528；SurfaceFrame::Encode 3.762 | PAINT (root) 2.295；PAINT 2.272 |
| 1794309329997426 | 262 / 1417 | 4349.484 | 4.836 / 6.145 / 10.981 | Rasterizer::DrawToSurfaces 6.099；SurfaceFrame::Submit 5.674；SurfaceFrame::Encode 3.881 | PAINT (root) 3.128；PAINT 3.104 |
| 1794309329997426 | 263 / 1418 | 4366.280 | 4.571 / 6.397 / 10.968 | Rasterizer::DrawToSurfaces 6.361；SurfaceFrame::Submit 6.084；SurfaceFrame::Encode 4.091 | PAINT (root) 3.272；PAINT 3.251 |
| 1794309404767165 | 20 / 1173 | 317.688 | 4.312 / 2.779 / 7.091 | Rasterizer::DrawToSurfaces 2.741；PAINT (root) 2.714；PAINT 2.688 | PAINT (root) 2.714；PAINT 2.688 |
| 1794309404767165 | 21 / 1174 | 334.585 | 5.278 / 2.240 / 7.518 | PAINT (root) 3.499；PAINT 3.355；Rasterizer::DrawToSurfaces 2.221 | PAINT (root) 3.499；PAINT 3.355 |
| 1794309404767165 | 25 / 1178 | 401.011 | 4.624 / 6.214 / 10.838 | Rasterizer::DrawToSurfaces 6.173；SurfaceFrame::Submit 5.862；SurfaceFrame::Encode 3.950 | PAINT (root) 2.815；PAINT 2.791 |
| 1794309404767165 | 26 / 1179 | 417.782 | 5.219 / 6.001 / 11.220 | Rasterizer::DrawToSurfaces 5.959；SurfaceFrame::Submit 5.651；SurfaceFrame::Encode 3.847 | PAINT (root) 3.270；PAINT 3.246 |
| 1794309404767165 | 28 / 1181 | 451.608 | 5.610 / 6.271 / 11.881 | Rasterizer::DrawToSurfaces 6.232；SurfaceFrame::Submit 5.930；PAINT (root) 4.147 | PAINT (root) 4.147；PAINT 4.125 |
| 1794309404767165 | 31 / 1184 | 501.020 | 4.571 / 6.617 / 11.188 | Rasterizer::DrawToSurfaces 6.577；SurfaceFrame::Submit 6.228；SurfaceFrame::Encode 4.057 | PAINT (root) 2.894；PAINT 2.873 |
| 1794309404767165 | 32 / 1185 | 517.432 | 4.023 / 6.518 / 10.541 | Rasterizer::DrawToSurfaces 6.476；SurfaceFrame::Submit 6.167；SurfaceFrame::Encode 4.272 | PAINT (root) 2.421；PAINT 2.400 |
| 1794309404767165 | 34 / 1187 | 550.653 | 4.264 / 6.430 / 10.694 | Rasterizer::DrawToSurfaces 6.361；SurfaceFrame::Submit 6.061；SurfaceFrame::Encode 4.289 | PAINT (root) 2.254；PAINT 2.232 |
| 1794309404767165 | 36 / 1189 | 584.803 | 5.061 / 6.271 / 11.332 | Rasterizer::DrawToSurfaces 6.223；SurfaceFrame::Submit 5.925；SurfaceFrame::Encode 4.041 | PAINT (root) 3.653；PAINT 3.522 |
| 1794309404767165 | 38 / 1191 | 617.881 | 6.642 / 5.839 / 12.481 | Rasterizer::DrawToSurfaces 5.804；SurfaceFrame::Submit 5.483；PAINT (root) 5.272 | PAINT (root) 5.272；PAINT 5.191 |
| 1794309404767165 | 47 / 1200 | 767.596 | 4.848 / 6.398 / 11.246 | Rasterizer::DrawToSurfaces 6.358；SurfaceFrame::Submit 6.061；SurfaceFrame::Encode 4.263 | PAINT (root) 2.329；PAINT 2.217 |
| 1794309404767165 | 55 / 1208 | 900.974 | 4.696 / 6.706 / 11.402 | Rasterizer::DrawToSurfaces 6.630；SurfaceFrame::Submit 6.321；SurfaceFrame::Encode 4.250 | PAINT (root) 2.783；PAINT 2.761 |
| 1794309404767165 | 61 / 1214 | 1000.975 | 4.239 / 6.337 / 10.576 | Rasterizer::DrawToSurfaces 6.296；SurfaceFrame::Submit 6.005；SurfaceFrame::Encode 4.176 | PAINT (root) 2.529；PAINT 2.508 |
| 1794309404767165 | 62 / 1215 | 1017.542 | 4.447 / 6.366 / 10.813 | Rasterizer::DrawToSurfaces 6.300；SurfaceFrame::Submit 5.749；SurfaceFrame::Encode 3.974 | PAINT (root) 3.101；PAINT 3.078 |
| 1794309404767165 | 63 / 1216 | 1034.379 | 4.618 / 6.132 / 10.750 | Rasterizer::DrawToSurfaces 6.089；SurfaceFrame::Submit 5.781；SurfaceFrame::Encode 3.976 | PAINT (root) 2.393；PAINT 2.372 |
| 1794309404767165 | 64 / 1217 | 1051.240 | 4.398 / 6.081 / 10.479 | Rasterizer::DrawToSurfaces 6.039；SurfaceFrame::Submit 5.714；SurfaceFrame::Encode 3.937 | PAINT (root) 2.246；PAINT 2.226 |
| 1794309404767165 | 69 / 1222 | 1134.223 | 4.266 / 6.666 / 10.932 | Rasterizer::DrawToSurfaces 6.592；SurfaceFrame::Submit 6.280；SurfaceFrame::Encode 4.480 | PAINT (root) 2.528；PAINT 2.484 |
| 1794309404767165 | 73 / 1226 | 1200.895 | 4.752 / 6.034 / 10.786 | Rasterizer::DrawToSurfaces 5.941；SurfaceFrame::Submit 5.654；SurfaceFrame::Encode 3.929 | PAINT (root) 2.178；PAINT 2.158 |
| 1794309404767165 | 119 / 1272 | 1968.100 | 5.452 / 6.160 / 11.612 | Rasterizer::DrawToSurfaces 6.119；SurfaceFrame::Submit 5.819；PAINT (root) 4.033 | PAINT (root) 4.033；PAINT 4.010 |
| 1794309404767165 | 123 / 1276 | 2034.210 | 4.074 / 6.093 / 10.167 | Rasterizer::DrawToSurfaces 6.052；SurfaceFrame::Submit 5.748；SurfaceFrame::Encode 3.981 | PAINT (root) 2.009；PAINT 1.993 |
| 1794309404767165 | 124 / 1277 | 2050.998 | 5.426 / 6.633 / 12.059 | Rasterizer::DrawToSurfaces 6.592；SurfaceFrame::Submit 6.071；SurfaceFrame::Encode 4.166 | PAINT (root) 3.007；PAINT 2.985 |
| 1794309404767165 | 126 / 1279 | 2084.883 | 4.489 / 6.712 / 11.201 | Rasterizer::DrawToSurfaces 6.671；SurfaceFrame::Submit 6.350；SurfaceFrame::Encode 4.299 | PAINT (root) 2.729；PAINT 2.708 |
| 1794309404767165 | 127 / 1280 | 2101.236 | 4.904 / 6.722 / 11.626 | Rasterizer::DrawToSurfaces 6.680；SurfaceFrame::Submit 6.194；SurfaceFrame::Encode 4.167 | PAINT (root) 2.672；PAINT 2.647 |
| 1794309404767165 | 128 / 1281 | 2117.600 | 4.727 / 5.964 / 10.691 | Rasterizer::DrawToSurfaces 5.926；SurfaceFrame::Submit 5.597；SurfaceFrame::Encode 3.898 | PAINT (root) 3.516；PAINT 2.805 |
| 1794309404767165 | 142 / 1295 | 2350.451 | 4.191 / 6.220 / 10.411 | Rasterizer::DrawToSurfaces 6.182；SurfaceFrame::Submit 5.882；SurfaceFrame::Encode 4.163 | PAINT (root) 2.481；PAINT 2.453 |
| 1794309404767165 | 144 / 1297 | 2385.158 | 4.856 / 6.216 / 11.072 | Rasterizer::DrawToSurfaces 6.178；SurfaceFrame::Submit 5.878；SurfaceFrame::Encode 3.923 | PAINT (root) 3.124；PAINT 3.100 |
| 1794309404767165 | 150 / 1303 | 2484.758 | 5.580 / 6.000 / 11.580 | Rasterizer::DrawToSurfaces 5.966；SurfaceFrame::Submit 5.667；PAINT (root) 4.242 | PAINT (root) 4.242；PAINT 4.220 |
| 1794309404767165 | 154 / 1307 | 2551.288 | 4.699 / 6.152 / 10.851 | Rasterizer::DrawToSurfaces 6.111；SurfaceFrame::Submit 5.798；SurfaceFrame::Encode 4.013 | PAINT (root) 3.057；PAINT 3.035 |
| 1794309404767165 | 155 / 1308 | 2567.695 | 4.137 / 6.211 / 10.348 | Rasterizer::DrawToSurfaces 6.173；SurfaceFrame::Submit 5.836；SurfaceFrame::Encode 4.061 | PAINT (root) 2.181；PAINT 2.162 |
| 1794309404767165 | 156 / 1309 | 2584.910 | 4.414 / 6.108 / 10.522 | Rasterizer::DrawToSurfaces 6.068；SurfaceFrame::Submit 5.755；SurfaceFrame::Encode 3.936 | PAINT (root) 2.711；PAINT 2.690 |
| 1794309404767165 | 160 / 1313 | 2651.885 | 4.717 / 6.350 / 11.067 | Rasterizer::DrawToSurfaces 6.281；SurfaceFrame::Submit 5.972；SurfaceFrame::Encode 4.029 | PAINT (root) 2.927；PAINT 2.902 |
| 1794309404767165 | 161 / 1314 | 2667.665 | 4.072 / 5.763 / 9.835 | Rasterizer::DrawToSurfaces 5.716；SurfaceFrame::Submit 5.440；SurfaceFrame::Encode 3.779 | PAINT (root) 2.103；PAINT 2.083 |
| 1794309404767165 | 162 / 1315 | 2684.640 | 4.387 / 6.134 / 10.521 | Rasterizer::DrawToSurfaces 6.096；SurfaceFrame::Submit 5.801；SurfaceFrame::Encode 3.891 | PAINT (root) 2.827；PAINT 2.805 |
| 1794309404767165 | 245 / 1398 | 4068.234 | 4.262 / 6.439 / 10.701 | Rasterizer::DrawToSurfaces 6.396；SurfaceFrame::Submit 6.078；SurfaceFrame::Encode 4.062 | PAINT (root) 2.602；PAINT 2.580 |
| 1794309404767165 | 248 / 1401 | 4118.204 | 4.109 / 6.417 / 10.526 | Rasterizer::DrawToSurfaces 6.376；SurfaceFrame::Submit 6.067；SurfaceFrame::Encode 4.274 | PAINT (root) 2.351；PAINT 2.331 |
| 1794309404767165 | 249 / 1402 | 4134.669 | 4.798 / 6.247 / 11.045 | Rasterizer::DrawToSurfaces 6.205；SurfaceFrame::Submit 5.671；SurfaceFrame::Encode 3.899 | PAINT (root) 2.132；PAINT 2.112 |
| 1794309404767165 | 252 / 1405 | 4184.319 | 4.131 / 5.989 / 10.120 | Rasterizer::DrawToSurfaces 5.950；SurfaceFrame::Submit 5.597；SurfaceFrame::Encode 3.876 | PAINT (root) 2.901；PAINT 2.880 |
| 1794309404767165 | 255 / 1408 | 4233.981 | 2.463 / 13.157 / 15.620 | Rasterizer::DrawToSurfaces 13.103；SurfaceFrame::Submit 12.803；SurfaceFrame::Encode 11.032 | PAINT (root) 1.519；PAINT 1.503 |
| 1794309404767165 | 256 / 1409 | 4250.619 | 3.029 / 14.075 / 17.104 | Rasterizer::DrawToSurfaces 14.027；SurfaceFrame::Submit 13.515；SurfaceFrame::Encode 11.583 | PAINT (root) 1.644；PAINT 1.628 |
| 1794309404767165 | 259 / 1412 | 4300.992 | 4.112 / 6.503 / 10.615 | Rasterizer::DrawToSurfaces 6.460；SurfaceFrame::Submit 6.151；SurfaceFrame::Encode 4.233 | PAINT (root) 2.840；PAINT 2.816 |
| 1794309404767165 | 260 / 1413 | 4318.126 | 4.076 / 6.147 / 10.223 | Rasterizer::DrawToSurfaces 6.109；SurfaceFrame::Submit 5.822；SurfaceFrame::Encode 3.942 | PAINT (root) 2.301；PAINT 2.279 |
| 1794309404767165 | 274 / 1427 | 4551.797 | 4.270 / 6.165 / 10.435 | Rasterizer::DrawToSurfaces 6.125；SurfaceFrame::Submit 5.818；SurfaceFrame::Encode 4.054 | PAINT (root) 1.852；PAINT 1.836 |
| 1794309488538708 | 53 / 1210 | 866.884 | 4.723 / 5.374 / 10.097 | Rasterizer::DrawToSurfaces 5.341；SurfaceFrame::Submit 4.998；SurfaceFrame::Encode 3.022 | COMPOSITING 1.965；PAINT (root) 1.858 |
| 1794309488538708 | 59 / 1216 | 966.410 | 1.375 / 10.838 / 12.213 | Rasterizer::DrawToSurfaces 10.810；SurfaceFrame::Submit 10.462；SurfaceFrame::Encode 8.628 | PAINT (root) 0.846；PAINT 0.836 |
| 1794309488538708 | 106 / 1263 | 1751.065 | 4.206 / 6.223 / 10.429 | Rasterizer::DrawToSurfaces 6.186；SurfaceFrame::Submit 5.895；SurfaceFrame::Encode 4.126 | PAINT (root) 2.351；PAINT 2.330 |
| 1794309488538708 | 107 / 1264 | 1767.360 | 4.445 / 6.451 / 10.896 | Rasterizer::DrawToSurfaces 6.414；SurfaceFrame::Submit 6.069；SurfaceFrame::Encode 4.096 | PAINT (root) 3.136；PAINT 3.114 |
| 1794309488538708 | 108 / 1265 | 1783.783 | 5.510 / 6.755 / 12.265 | Rasterizer::DrawToSurfaces 6.722；SurfaceFrame::Submit 6.046；SurfaceFrame::Encode 4.139 | PAINT (root) 3.092；PAINT 3.069 |
| 1794309488538708 | 111 / 1268 | 1833.677 | 4.206 / 6.639 / 10.845 | Rasterizer::DrawToSurfaces 6.604；SurfaceFrame::Submit 6.328；SurfaceFrame::Encode 4.554 | PAINT (root) 2.192；PAINT 2.172 |
| 1794309488538708 | 112 / 1269 | 1850.464 | 4.540 / 6.662 / 11.202 | Rasterizer::DrawToSurfaces 6.598；SurfaceFrame::Submit 6.299；SurfaceFrame::Encode 4.447 | PAINT (root) 2.312；PAINT 2.294 |
| 1794309488538708 | 113 / 1270 | 1867.205 | 4.907 / 6.221 / 11.128 | Rasterizer::DrawToSurfaces 6.184；SurfaceFrame::Submit 5.891；SurfaceFrame::Encode 4.040 | PAINT (root) 2.977；PAINT 2.957 |
| 1794309488538708 | 114 / 1271 | 1884.197 | 4.205 / 6.114 / 10.319 | Rasterizer::DrawToSurfaces 6.078；SurfaceFrame::Submit 5.795；SurfaceFrame::Encode 4.063 | PAINT (root) 2.462；PAINT 2.442 |
| 1794309488538708 | 115 / 1272 | 1900.442 | 4.061 / 6.921 / 10.982 | Rasterizer::DrawToSurfaces 6.849；SurfaceFrame::Submit 6.408；SurfaceFrame::Encode 4.638 | PAINT (root) 2.676；PAINT 2.654 |
| 1794309488538708 | 116 / 1273 | 1917.170 | 5.009 / 6.313 / 11.322 | Rasterizer::DrawToSurfaces 6.280；SurfaceFrame::Submit 5.748；SurfaceFrame::Encode 4.036 | PAINT (root) 2.676；PAINT 2.653 |
| 1794309488538708 | 117 / 1274 | 1934.065 | 4.219 / 6.337 / 10.556 | Rasterizer::DrawToSurfaces 6.299；SurfaceFrame::Submit 5.999；SurfaceFrame::Encode 4.180 | PAINT (root) 2.209；PAINT 2.189 |
| 1794309488538708 | 118 / 1275 | 1950.619 | 4.419 / 6.280 / 10.699 | Rasterizer::DrawToSurfaces 6.245；SurfaceFrame::Submit 5.948；SurfaceFrame::Encode 4.171 | PAINT (root) 2.320；PAINT 2.299 |
| 1794309488538708 | 119 / 1276 | 1967.418 | 5.033 / 6.757 / 11.790 | Rasterizer::DrawToSurfaces 6.690；SurfaceFrame::Submit 6.086；SurfaceFrame::Encode 4.156 | PAINT (root) 3.541；PAINT 3.515 |
| 1794309488538708 | 120 / 1277 | 1983.768 | 5.114 / 6.437 / 11.551 | Rasterizer::DrawToSurfaces 6.402；SurfaceFrame::Submit 6.090；SurfaceFrame::Encode 4.165 | PAINT (root) 2.921；PAINT 2.898 |
| 1794309488538708 | 121 / 1278 | 2000.551 | 5.642 / 6.792 / 12.434 | Rasterizer::DrawToSurfaces 6.756；SurfaceFrame::Submit 6.268；SurfaceFrame::Encode 4.483 | PAINT (root) 2.894；PAINT 2.872 |
| 1794309488538708 | 122 / 1279 | 2017.202 | 4.069 / 6.679 / 10.748 | Rasterizer::DrawToSurfaces 6.641；SurfaceFrame::Submit 6.318；SurfaceFrame::Encode 4.514 | PAINT (root) 2.269；PAINT 2.248 |
| 1794309488538708 | 123 / 1280 | 2033.492 | 4.453 / 6.770 / 11.223 | Rasterizer::DrawToSurfaces 6.735；SurfaceFrame::Submit 6.455；SurfaceFrame::Encode 4.732 | PAINT (root) 2.190；PAINT 2.171 |
| 1794309488538708 | 124 / 1281 | 2050.734 | 4.071 / 6.367 / 10.438 | Rasterizer::DrawToSurfaces 6.330；SurfaceFrame::Submit 6.047；SurfaceFrame::Encode 4.319 | PAINT (root) 2.288；PAINT 2.268 |
| 1794309488538708 | 132 / 1289 | 2183.854 | 4.236 / 6.729 / 10.965 | Rasterizer::DrawToSurfaces 6.694；SurfaceFrame::Submit 6.404；SurfaceFrame::Encode 4.397 | PAINT (root) 2.922；PAINT 2.901 |
| 1794309488538708 | 133 / 1290 | 2200.485 | 4.989 / 6.647 / 11.636 | Rasterizer::DrawToSurfaces 6.578；SurfaceFrame::Submit 6.261；SurfaceFrame::Encode 4.456 | PAINT (root) 2.969；PAINT 2.948 |
| 1794309488538708 | 134 / 1291 | 2217.279 | 4.600 / 7.642 / 12.242 | Rasterizer::DrawToSurfaces 7.597；SurfaceFrame::Submit 6.134；SurfaceFrame::Encode 4.238 | PAINT (root) 2.193；PAINT 2.173 |
| 1794309488538708 | 136 / 1293 | 2250.654 | 4.047 / 6.204 / 10.251 | Rasterizer::DrawToSurfaces 6.171；SurfaceFrame::Submit 5.891；SurfaceFrame::Encode 4.168 | PAINT (root) 2.326；PAINT 2.308 |
| 1794309488538708 | 137 / 1294 | 2267.347 | 4.394 / 6.128 / 10.522 | Rasterizer::DrawToSurfaces 6.095；SurfaceFrame::Submit 5.810；SurfaceFrame::Encode 4.016 | PAINT (root) 2.399；PAINT 2.380 |
| 1794309488538708 | 138 / 1295 | 2283.776 | 5.183 / 6.259 / 11.442 | Rasterizer::DrawToSurfaces 6.224；SurfaceFrame::Submit 5.815；SurfaceFrame::Encode 4.034 | PAINT (root) 3.220；PAINT 3.196 |
| 1794309488538708 | 139 / 1296 | 2300.734 | 4.301 / 6.083 / 10.384 | Rasterizer::DrawToSurfaces 6.050；SurfaceFrame::Submit 5.780；SurfaceFrame::Encode 4.025 | PAINT (root) 2.521；PAINT 2.500 |
| 1794309488538708 | 140 / 1297 | 2317.055 | 4.288 / 6.373 / 10.661 | Rasterizer::DrawToSurfaces 6.311；SurfaceFrame::Submit 5.876；SurfaceFrame::Encode 4.074 | PAINT (root) 2.459；PAINT 2.438 |
| 1794309488538708 | 142 / 1299 | 2350.506 | 5.075 / 7.141 / 12.216 | Rasterizer::DrawToSurfaces 7.103；SurfaceFrame::Submit 6.798；SurfaceFrame::Encode 4.884 | PAINT (root) 2.327；PAINT 2.305 |
| 1794309488538708 | 143 / 1300 | 2367.359 | 4.663 / 6.032 / 10.695 | Rasterizer::DrawToSurfaces 5.999；SurfaceFrame::Submit 5.666；SurfaceFrame::Encode 3.934 | PAINT (root) 3.504；PAINT 3.482 |
| 1794309488538708 | 144 / 1301 | 2383.740 | 4.686 / 6.423 / 11.109 | Rasterizer::DrawToSurfaces 6.390；SurfaceFrame::Submit 6.112；SurfaceFrame::Encode 4.172 | PAINT (root) 3.411；PAINT 3.389 |
| 1794309488538708 | 145 / 1302 | 2400.191 | 4.498 / 6.728 / 11.226 | Rasterizer::DrawToSurfaces 6.690；SurfaceFrame::Submit 6.145；SurfaceFrame::Encode 4.166 | PAINT (root) 2.685；PAINT 2.663 |
| 1794309488538708 | 146 / 1303 | 2416.873 | 4.228 / 6.361 / 10.589 | Rasterizer::DrawToSurfaces 6.324；SurfaceFrame::Submit 6.026；SurfaceFrame::Encode 4.016 | PAINT (root) 2.443；PAINT 2.423 |
| 1794309488538708 | 147 / 1304 | 2434.096 | 5.770 / 6.521 / 12.291 | Rasterizer::DrawToSurfaces 6.455；SurfaceFrame::Submit 5.931；SurfaceFrame::Encode 4.091 | PAINT (root) 3.521；PAINT 3.495 |
| 1794309488538708 | 149 / 1306 | 2467.453 | 4.265 / 6.114 / 10.379 | Rasterizer::DrawToSurfaces 6.079；SurfaceFrame::Submit 5.785；SurfaceFrame::Encode 4.070 | PAINT (root) 2.424；PAINT 2.404 |
| 1794309488538708 | 167 / 1324 | 2766.899 | 4.321 / 2.309 / 6.630 | PAINT (root) 3.031；PAINT 3.006；Rasterizer::DrawToSurfaces 2.293 | PAINT (root) 3.031；PAINT 3.006 |
| 1794309488538708 | 197 / 1354 | 3266.781 | 4.418 / 5.905 / 10.323 | Rasterizer::DrawToSurfaces 5.874；SurfaceFrame::Submit 5.519；SurfaceFrame::Encode 3.785 | PAINT (root) 3.490；PAINT 3.475 |
| 1794309488538708 | 233 / 1390 | 3867.287 | 4.043 / 6.724 / 10.767 | Rasterizer::DrawToSurfaces 6.687；SurfaceFrame::Submit 6.402；SurfaceFrame::Encode 4.682 | PAINT (root) 2.849；PAINT 2.826 |
| 1794309488538708 | 234 / 1391 | 3883.827 | 4.573 / 7.155 / 11.728 | Rasterizer::DrawToSurfaces 7.122；SurfaceFrame::Submit 6.309；SurfaceFrame::Encode 4.566 | PAINT (root) 2.461；PAINT 2.441 |
| 1794309488538708 | 235 / 1392 | 3900.578 | 4.134 / 7.149 / 11.283 | Rasterizer::DrawToSurfaces 7.114；SurfaceFrame::Submit 6.379；SurfaceFrame::Encode 4.544 | PAINT (root) 2.351；PAINT 2.330 |
| 1794309488538708 | 238 / 1395 | 3950.103 | 4.058 / 6.446 / 10.504 | Rasterizer::DrawToSurfaces 6.384；SurfaceFrame::Submit 5.435；SurfaceFrame::Encode 3.711 | PAINT (root) 1.453；PAINT 1.439 |
| 1794309488538708 | 240 / 1397 | 3983.517 | 2.348 / 13.277 / 15.625 | Rasterizer::DrawToSurfaces 13.226；SurfaceFrame::Submit 12.941；SurfaceFrame::Encode 11.203 | PAINT (root) 1.387；PAINT 1.375 |
| 1794309488538708 | 241 / 1398 | 3999.845 | 2.453 / 12.079 / 14.532 | Rasterizer::DrawToSurfaces 12.047；SurfaceFrame::Submit 11.648；SurfaceFrame::Encode 9.929 | PAINT (root) 1.335；PAINT 1.324 |
| 1794309488538708 | 244 / 1401 | 4050.601 | 4.058 / 6.522 / 10.580 | Rasterizer::DrawToSurfaces 6.484；SurfaceFrame::Submit 6.198；SurfaceFrame::Encode 4.504 | PAINT (root) 2.197；PAINT 2.176 |
| 1794309488538708 | 249 / 1406 | 4133.866 | 4.564 / 6.063 / 10.627 | Rasterizer::DrawToSurfaces 6.026；SurfaceFrame::Submit 5.533；SurfaceFrame::Encode 3.853 | PAINT (root) 2.551；PAINT 2.528 |
| 1794309488538708 | 252 / 1409 | 4183.972 | 4.321 / 6.655 / 10.976 | Rasterizer::DrawToSurfaces 6.586；SurfaceFrame::Submit 6.120；SurfaceFrame::Encode 4.163 | PAINT (root) 2.366；PAINT 2.346 |
| 1794309488538708 | 260 / 1417 | 4317.160 | 4.026 / 6.183 / 10.209 | Rasterizer::DrawToSurfaces 6.144；SurfaceFrame::Submit 5.847；SurfaceFrame::Encode 3.919 | PAINT (root) 2.333；PAINT 2.313 |
| 1794309488538708 | 261 / 1418 | 4334.041 | 4.225 / 6.673 / 10.898 | Rasterizer::DrawToSurfaces 6.635；SurfaceFrame::Submit 6.132；SurfaceFrame::Encode 4.349 | PAINT (root) 2.267；PAINT 2.246 |
| 1794309488538708 | 264 / 1421 | 4383.678 | 4.495 / 6.159 / 10.654 | Rasterizer::DrawToSurfaces 6.124；SurfaceFrame::Submit 5.855；SurfaceFrame::Encode 4.142 | PAINT (root) 2.535；PAINT 2.514 |
| 1794309488538708 | 265 / 1422 | 4400.438 | 4.315 / 6.096 / 10.411 | Rasterizer::DrawToSurfaces 6.061；SurfaceFrame::Submit 5.779；SurfaceFrame::Encode 4.010 | PAINT (root) 3.310；PAINT 3.290 |
| 1794309488538708 | 268 / 1425 | 4450.318 | 4.432 / 6.392 / 10.824 | Rasterizer::DrawToSurfaces 6.355；SurfaceFrame::Submit 5.871；SurfaceFrame::Encode 4.168 | PAINT (root) 2.719；PAINT 2.699 |
| 1794309488538708 | 269 / 1426 | 4467.471 | 4.210 / 6.167 / 10.377 | Rasterizer::DrawToSurfaces 6.127；SurfaceFrame::Submit 5.820；SurfaceFrame::Encode 4.081 | PAINT (root) 2.402；PAINT 2.379 |
| 1794309488538708 | 271 / 1428 | 4500.464 | 4.355 / 6.515 / 10.870 | Rasterizer::DrawToSurfaces 6.480；SurfaceFrame::Submit 6.199；SurfaceFrame::Encode 4.448 | PAINT (root) 2.478；PAINT 2.457 |
| 1794309488538708 | 274 / 1431 | 4550.777 | 5.308 / 6.653 / 11.961 | Rasterizer::DrawToSurfaces 6.614；SurfaceFrame::Submit 6.155；SurfaceFrame::Encode 4.337 | PAINT (root) 2.459；PAINT 2.438 |
| 1794314421829493 | 28 / 1183 | 449.484 | 1.743 / 13.272 / 15.015 | Rasterizer::DrawToSurfaces 13.191；SurfaceFrame::Submit 12.850；SurfaceFrame::Encode 11.172 | PAINT (root) 0.989；PAINT 0.979 |
| 1794314421829493 | 29 / 1184 | 466.051 | 2.693 / 13.896 / 16.589 | Rasterizer::DrawToSurfaces 13.789；SurfaceFrame::Submit 13.420；SurfaceFrame::Encode 11.535 | PAINT (root) 1.408；PAINT 1.393 |
| 1794314421829493 | 35 / 1190 | 567.131 | 4.021 / 4.990 / 9.011 | Rasterizer::DrawToSurfaces 4.923；SurfaceFrame::Submit 4.487；SurfaceFrame::Encode 2.638 | PAINT (root) 2.079；PAINT 2.062 |
| 1794314421829493 | 58 / 1213 | 950.800 | 4.074 / 5.207 / 9.281 | Rasterizer::DrawToSurfaces 5.168；SurfaceFrame::Submit 4.871；SurfaceFrame::Encode 2.907 | PAINT (root) 2.052；PAINT 2.032 |
| 1794314421829493 | 60 / 1215 | 983.333 | 5.709 / 5.034 / 10.743 | Rasterizer::DrawToSurfaces 4.995；SurfaceFrame::Submit 4.672；SurfaceFrame::Encode 2.776 | PAINT (root) 2.008；PAINT 1.980 |
| 1794314421829493 | 65 / 1220 | 1066.984 | 4.113 / 5.292 / 9.405 | Rasterizer::DrawToSurfaces 5.252；SurfaceFrame::Submit 4.948；SurfaceFrame::Encode 3.050 | PAINT (root) 1.968；PAINT 1.946 |
| 1794314421829493 | 120 / 1275 | 1984.294 | 4.109 / 5.123 / 9.232 | Rasterizer::DrawToSurfaces 5.084；SurfaceFrame::Submit 4.782；SurfaceFrame::Encode 2.865 | PAINT (root) 2.816；PAINT 2.772 |
| 1794314421829493 | 145 / 1300 | 2400.912 | 4.059 / 5.129 / 9.188 | Rasterizer::DrawToSurfaces 5.090；SurfaceFrame::Submit 4.786；SurfaceFrame::Encode 2.868 | PAINT (root) 2.177；PAINT 2.154 |
| 1794314421829493 | 149 / 1304 | 2466.736 | 5.531 / 5.143 / 10.674 | Rasterizer::DrawToSurfaces 4.979；SurfaceFrame::Submit 4.673；PAINT (root) 3.802 | PAINT (root) 3.802；PAINT 3.775 |
| 1794314421829493 | 151 / 1306 | 2500.832 | 4.661 / 5.058 / 9.719 | Rasterizer::DrawToSurfaces 5.020；SurfaceFrame::Submit 4.729；SurfaceFrame::Encode 2.796 | PAINT (root) 2.657；PAINT 2.634 |
| 1794314421829493 | 156 / 1311 | 2584.441 | 5.260 / 5.235 / 10.495 | Rasterizer::DrawToSurfaces 5.196；SurfaceFrame::Submit 4.912；PAINT (root) 3.466 | PAINT (root) 3.466；PAINT 3.443 |
| 1794314421829493 | 157 / 1312 | 2600.703 | 4.407 / 5.330 / 9.737 | Rasterizer::DrawToSurfaces 5.290；SurfaceFrame::Submit 4.981；SurfaceFrame::Encode 2.905 | PAINT (root) 2.804；PAINT 2.681 |
| 1794314421829493 | 166 / 1321 | 2750.609 | 3.268 / 13.485 / 16.753 | Rasterizer::DrawToSurfaces 13.433；SurfaceFrame::Submit 13.134；SurfaceFrame::Encode 11.248 | PAINT (root) 2.057；PAINT 2.036 |
| 1794314421829493 | 167 / 1322 | 2766.148 | 2.233 / 11.635 / 13.868 | Rasterizer::DrawToSurfaces 11.604；SurfaceFrame::Submit 11.199；SurfaceFrame::Encode 9.429 | PAINT (root) 1.241；PAINT 1.226 |
| 1794314421829493 | 264 / 1419 | 4383.150 | 4.008 / 3.666 / 7.674 | Rasterizer::DrawToSurfaces 3.528；SurfaceFrame::Submit 3.281；PAINT (root) 2.156 | PAINT (root) 2.156；PAINT 2.135 |
| 1794314421829493 | 274 / 1429 | 4549.945 | 4.450 / 2.889 / 7.339 | Rasterizer::DrawToSurfaces 2.870；SurfaceFrame::Submit 2.695；PAINT (root) 2.114 | PAINT (root) 2.114；PAINT 2.095 |
| 1794314571366953 | 44 / 1197 | 717.206 | 4.001 / 4.988 / 8.989 | Rasterizer::DrawToSurfaces 4.952；SurfaceFrame::Submit 4.664；SurfaceFrame::Encode 2.683 | PAINT (root) 1.939；PAINT 1.917 |
| 1794314571366953 | 50 / 1203 | 817.698 | 4.017 / 5.299 / 9.316 | Rasterizer::DrawToSurfaces 5.262；SurfaceFrame::Submit 4.845；SurfaceFrame::Encode 2.711 | PAINT (root) 2.015；PAINT 1.992 |
| 1794314571366953 | 73 / 1226 | 1200.926 | 4.514 / 4.889 / 9.403 | Rasterizer::DrawToSurfaces 4.852；SurfaceFrame::Submit 4.473；SurfaceFrame::Encode 2.585 | COMPOSITING 1.966；PAINT (root) 1.711 |
| 1794314571366953 | 128 / 1281 | 2117.517 | 4.242 / 5.093 / 9.335 | Rasterizer::DrawToSurfaces 5.057；SurfaceFrame::Submit 4.791；SurfaceFrame::Encode 2.611 | PAINT (root) 1.717；PAINT 1.698 |
| 1794314571366953 | 163 / 1316 | 2701.523 | 5.314 / 6.963 / 12.277 | Rasterizer::DrawToSurfaces 5.475；SurfaceFrame::Submit 4.971；SurfaceFrame::Encode 3.051 | SEMANTICS (root) 2.460；PAINT (root) 1.687 |
| 1794314571366953 | 164 / 1317 | 2717.502 | 4.084 / 4.936 / 9.020 | Rasterizer::DrawToSurfaces 4.900；SurfaceFrame::Submit 4.607；SurfaceFrame::Encode 2.621 | PAINT (root) 1.894；PAINT 1.870 |
| 1794314571366953 | 265 / 1418 | 4400.763 | 4.151 / 5.140 / 9.291 | Rasterizer::DrawToSurfaces 5.102；SurfaceFrame::Submit 4.754；SurfaceFrame::Encode 2.691 | PAINT (root) 2.400；PAINT 2.377 |
| 1794314571366953 | 274 / 1427 | 4550.752 | 5.756 / 7.599 / 13.355 | Rasterizer::DrawToSurfaces 7.563；SurfaceFrame::Submit 7.275；SurfaceFrame::Encode 5.465 | PAINT (root) 2.268；PAINT 2.248 |

位置统计（每秒分桶；首5帧单列；仅说明分布，不推断随机性）：

| run_id | 首5帧尖峰数 | 秒桶 [0,1,2,3,4] | 无配对UI / Raster | 无配对UI>4ms |
| --- | --- | --- | --- | --- |
| 1794309329997426 | 0 | [11, 16, 4, 14, 7] | 2 / 0 | 0 |
| 1794309404767165 | 0 | [12, 7, 14, 0, 9] | 1 / 0 | 0 |
| 1794309488538708 | 0 | [2, 13, 20, 7, 11] | 1 / 0 | 0 |
| 1794314421829493 | 0 | [5, 2, 7, 0, 2] | 0 / 0 | 0 |
| 1794314571366953 | 0 | [2, 1, 3, 0, 2] | 0 / 0 | 0 |

### 事件归因与普通帧对照

| 身份 / 事件 | 尖峰累计 ms / 每帧均值 ms | 普通累计 ms / 每帧均值 ms |
| --- | --- | --- |
| 正式 / Animate | 10.687 / 0.445 | 152.270 / 0.289 |
| 正式 / BUILD | 0.838 / 0.035 | 0.000 / 0.000 |
| 正式 / COMPOSITING | 18.176 / 0.757 | 207.140 / 0.394 |
| 正式 / CollectNewGeneration | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / CreateGlyphAtlas | 1.988 / 0.083 | 8.456 / 0.016 |
| 正式 / Dart_InvokeClosure | 0.053 / 0.002 | 0.000 / 0.000 |
| 正式 / LAYOUT | 0.993 / 0.041 | 2.854 / 0.005 |
| 正式 / LayerTree::Paint | 0.954 / 0.040 | 20.478 / 0.039 |
| 正式 / PAINT | 50.802 / 2.117 | 651.583 / 1.239 |
| 正式 / PAINT (root) | 51.425 / 2.143 | 662.677 / 1.260 |
| 正式 / Rasterizer::DrawToSurfaces | 152.575 / 6.357 | 2553.546 / 4.855 |
| 正式 / ReactorGLES::React | 79.405 / 3.309 | 1062.997 / 2.021 |
| 正式 / RenderPassGLES::EncodeCommandsInReactor | 77.023 / 3.209 | 1027.907 / 1.954 |
| 正式 / SEMANTICS | 3.696 / 0.154 | 22.617 / 0.043 |
| 正式 / SEMANTICS (root) | 11.935 / 0.497 | 65.208 / 0.124 |
| 正式 / Scavenge | 0.000 / 0.000 | 0.000 / 0.000 |
| 正式 / SurfaceFrame::Encode | 100.369 / 4.182 | 1473.060 / 2.800 |
| 正式 / SurfaceFrame::Submit | 144.800 / 6.033 | 2397.557 / 4.558 |
| 历史 / Animate | 64.944 / 0.442 | 186.047 / 0.276 |
| 历史 / BUILD | 0.580 / 0.004 | 0.000 / 0.000 |
| 历史 / CollectNewGeneration | 0.000 / 0.000 | 0.000 / 0.000 |
| 历史 / CreateGlyphAtlas | 12.986 / 0.088 | 53.627 / 0.080 |
| 历史 / Dart_InvokeClosure | 0.055 / 0.000 | 0.000 / 0.000 |
| 历史 / LAYOUT | 1.739 / 0.012 | 3.773 / 0.006 |
| 历史 / LayerTree::Paint | 6.726 / 0.046 | 27.043 / 0.040 |
| 历史 / PAINT | 384.268 / 2.614 | 925.156 / 1.373 |
| 历史 / PAINT (root) | 388.940 / 2.646 | 937.088 / 1.390 |
| 历史 / Rasterizer::DrawToSurfaces | 959.802 / 6.529 | 3867.240 / 5.738 |
| 历史 / ReactorGLES::React | 426.216 / 2.899 | 1650.595 / 2.449 |
| 历史 / RenderPassGLES::EncodeCommandsInReactor | 415.505 / 2.827 | 1604.015 / 2.380 |
| 历史 / SEMANTICS | 15.109 / 0.103 | 33.323 / 0.049 |
| 历史 / Scavenge | 0.000 / 0.000 | 0.000 / 0.000 |
| 历史 / SurfaceFrame::Encode | 640.092 / 4.354 | 2545.800 / 3.777 |
| 历史 / SurfaceFrame::Submit | 907.464 / 6.173 | 3672.594 / 5.449 |

各窗口普通帧事件均值（ms，框架事件包含时长）：

| run_id | 普通帧数 | Encode | GLES Encode | PAINT | Animate | COMPOSITING |
| --- | --- | --- | --- | --- | --- | --- |
| 1794309329997426 | 221 | 3.897 | 2.442 | 1.474 | 0.290 | 0.403 |
| 1794309404767165 | 232 | 3.614 | 2.260 | 1.402 | 0.282 | 0.402 |
| 1794309488538708 | 221 | 3.829 | 2.443 | 1.240 | 0.256 | 0.337 |
| 1794314421829493 | 259 | 3.050 | 2.206 | 1.293 | 0.300 | 0.418 |
| 1794314571366953 | 267 | 2.558 | 1.710 | 1.186 | 0.279 | 0.371 |

## lots_shaking 尖峰帧完整清单

| run_id | 帧序号 / 引擎帧号 | 位置 ms | UI / Raster / 合计 ms | 最长三个内层事件 ms（含嵌套） | UI最长事件 ms |
| --- | --- | --- | --- | --- | --- |
| — | 无尖峰 | — | — | — | — |

位置统计（每秒分桶；首5帧单列；仅说明分布，不推断随机性）：

| run_id | 首5帧尖峰数 | 秒桶 [0,1,2,3,4] | 无配对UI / Raster | 无配对UI>4ms |
| --- | --- | --- | --- | --- |
| 1794308933597372 | 0 | [0, 0, 0, 0, 0] | 1 / 0 | 0 |
| 1794309094772711 | 0 | [0, 0, 0, 0, 0] | 0 / 0 | 0 |

### 事件归因与普通帧对照

| 身份 / 事件 | 尖峰累计 ms / 每帧均值 ms | 普通累计 ms / 每帧均值 ms |
| --- | --- | --- |
| 正式 / Animate | —（无帧） | 98.366 / 0.163 |
| 正式 / BUILD | —（无帧） | 0.000 / 0.000 |
| 正式 / CollectNewGeneration | —（无帧） | 0.000 / 0.000 |
| 正式 / CreateGlyphAtlas | —（无帧） | 0.000 / 0.000 |
| 正式 / Dart_InvokeClosure | —（无帧） | 0.000 / 0.000 |
| 正式 / LAYOUT | —（无帧） | 4.188 / 0.007 |
| 正式 / LayerTree::Paint | —（无帧） | 23.659 / 0.039 |
| 正式 / PAINT | —（无帧） | 346.544 / 0.576 |
| 正式 / RenderPassGLES::EncodeCommandsInReactor | —（无帧） | 866.579 / 1.440 |
| 正式 / SEMANTICS | —（无帧） | 21.864 / 0.036 |
| 正式 / Scavenge | —（无帧） | 0.000 / 0.000 |
| 正式 / SurfaceFrame::Encode | —（无帧） | 1074.167 / 1.784 |
| 正式 / SurfaceFrame::Submit | —（无帧） | 2181.784 / 3.624 |

各窗口普通帧事件均值（ms，框架事件包含时长）：

| run_id | 普通帧数 | Encode | GLES Encode | PAINT | Animate | COMPOSITING |
| --- | --- | --- | --- | --- | --- | --- |
| 1794308933597372 | 301 | 2.585 | 2.227 | 0.606 | 0.180 | 0.422 |
| 1794309094772711 | 301 | 0.983 | 0.652 | 0.545 | 0.147 | 0.356 |

## GC 完整区间表（含UI空闲区间）

| 场景 / run_id | 事件 | 线程ID | 位置 ms | 耗时 ms | 与UI Frame重叠序号 |
| --- | --- | --- | --- | --- | --- |
| lots_shaking / 1794308933597372 | CollectNewGeneration | 511453528208 | 1436.916 | 4.762 | [] |
| lots_shaking / 1794308933597372 | Scavenge | 511453528208 | 1437.376 | 3.904 | [] |
| lots_shaking / 1794308933597372 | Scavenge | 497037304704 | 1438.024 | 1.490 | [] |
| lotto_draw / 1794309329997426 | CollectNewGeneration | 511453528208 | 2368.716 | 2.424 | [] |
| lotto_draw / 1794309329997426 | Scavenge | 511453528208 | 2369.474 | 1.276 | [] |
| lotto_draw / 1794309329997426 | Scavenge | 496697934720 | 2370.036 | 0.713 | [] |
| lotto_draw / 1794309404767165 | CollectNewGeneration | 511453528208 | 3837.461 | 2.134 | [] |
| lotto_draw / 1794309404767165 | Scavenge | 511453528208 | 3837.795 | 1.473 | [] |
| lotto_draw / 1794309404767165 | Scavenge | 496670651264 | 3838.104 | 1.177 | [] |
| lotto_draw / 1794309488538708 | CollectNewGeneration | 511453528208 | 85.265 | 1.499 | [] |
| lotto_draw / 1794309488538708 | Scavenge | 511453528208 | 85.355 | 1.223 | [] |
| lotto_draw / 1794309488538708 | CollectNewGeneration | 511453528208 | 4220.442 | 1.844 | [] |
| lotto_draw / 1794309488538708 | Scavenge | 511453528208 | 4220.550 | 1.405 | [] |
| lotto_draw / 1794309488538708 | Scavenge | 496993661824 | 4220.742 | 1.225 | [] |
| slot_raster / 1794306825736505 | CollectNewGeneration | 511453528208 | 1671.725 | 6.857 | [] |
| slot_raster / 1794306825736505 | Scavenge | 511453528208 | 1672.316 | 3.145 | [] |
| slot_raster / 1794306825736505 | Scavenge | 497281094528 | 1672.854 | 5.260 | [] |
| lotto_draw / 1794314421829493 | CollectNewGeneration | 511453528208 | 1089.160 | 2.552 | [] |
| lotto_draw / 1794314421829493 | Scavenge | 511453528208 | 1089.304 | 2.033 | [] |
| lotto_draw / 1794314421829493 | Scavenge | 496977888128 | 1089.434 | 1.886 | [] |
| lotto_draw / 1794314571366953 | CollectNewGeneration | 511453528208 | 2556.623 | 3.117 | [] |
| lotto_draw / 1794314571366953 | Scavenge | 511453528208 | 2557.514 | 1.801 | [] |
| lotto_draw / 1794314571366953 | Scavenge | 496765985664 | 2557.928 | 1.364 | [] |

CollectNewGeneration/Scavenge 是嵌套的区间，不能累加为独立停顿。本批列出的GC与UI Frame均无时间重叠；slot的6.857ms收集在1.672秒，并非1.050/1.883/4.067秒的尖峰。分配来源和GC是否影响窗口外响应无法由这些事件判定。

## 分布与根因结论表

| 场景 | 全部未污染 / 正式尖峰数 | 位置 | 事件层定位 | 代码根因结论 |
| --- | --- | --- | --- | --- |
| slot_raster | 5 / 5 | 第64/65/114/245/246帧，1.050–4.084秒；成对突发，非开头几帧 | Encode累计61.273ms；GLES Encode60.209ms，普通帧Encode均值1.695ms | 框架/驱动路径长墙钟；无法判定库或设备根因 |
| grid_steady | 10 / 8 | 正式1.617–4.901秒，连续2–3帧突发及单次UI；历史另2帧 | 正式Encode尖峰与GLES嵌套；UI单次COMPOSITING2.550ms，未见重复BUILD | 无法判定；现有缓存实现未证明有可避免重复工作 |
| lotto_draw | 171 / 24 | 正式0.450–4.551秒，散布搅拌及开奖；不是只在开头，无固定周期证据 | Raster编码/提交及UI PAINT/COMPOSITING；见逐帧UI列 | 无函数采样栈，无法判定可避免分配/布局 |
| lots_shaking | 0 / 0 | 未污染两窗口均无12/4ms尖峰 | 普通帧Raster均值4.760/3.139ms；逐窗口Encode/GLES成本有差异 | 无法判定；窗口不稳定仍待复测 |

保存 trace 无 ImageDecode/Picture.toImage/实际分配栈可用于以上尖峰归因；CreateGlyphAtlas 在有文字的场景是反复出现的引擎区间，累计表并不等同于新建整张图集。未配对帧只出现在采集边界，已列出而不补零；本批这些帧均未触发UI>4ms。

## slot 图集构建与结论限制

`SlotPainter` 构造时调用 `SlotAtlas.prepare`，后者在布局/图片身份改变时同步调用 `Picture.toImageSync`；稳态 paint 仅回放图集。`runSteadyBench` 在 mount、图片 ready、稳定等待、play 与 cruising 后才打开 traceAction。所有保存的 slot_raster trace 中没有 toImage/图集构建打点，不能给出进入 raster 模式那一帧的帧号、耗时或实际线程。源代码表明调用发起于布局所在 UI isolate，但位图真正执行/上传的线程、耗时及是否影响进入首帧无法从本次 trace 判定。不能把稳态 SurfaceFrame::Encode 尖峰冒充图集构建；不据此搬动构建时机。

## 根因判定与待真机复测

事件层定位与代码根因判定分开：SurfaceFrame::Encode、GLES Reactor、CreateGlyphAtlas 等是框架/引擎事件，它们的长墙钟区间可以包含驱动等待与线程抢占，不能仅凭名称断言设备故障或库工作过多。UI 的 Animate/PAINT/SEMANTICS 也没有 luckdraw 函数级采样栈，无法由其时长证明重复分配/布局。本批没有证据支持某个可避免的 luckdraw 热路径工作，四场景的代码根因均为「无法判定」，不改产品 lib。lots 窗口级 Raster 差异仍不稳定，普通帧事件表仅描述差异，不证明非确定性代码成本。

三项硬失败、lots 不确定、14项原设计目标差距继续保留；没有已修复或已达标声明。下一次使用同一新 APK 完成空白/玩法冷首帧、进程与线程CPU及四场景三轮复测，详见[发布检查清单](RELEASE_CHECKLIST.md)。

## DEVFIN 新证据与仍无法判定的代码根因

DEVFIN（2026-11-11）本次仅单台 vivo V2417 / Android 16：grid_steady：失败；slot_raster：失败；lots_shaking：不确定；lotto_draw：失败。冷push首帧增量wheel/grid/slot为38.087/10.520/0.245ms，新标定增量预算41.896/11.572/0.270ms；wheel/grid未达原4ms估算目标。CPU五项目各五次均0有效，不能提供可信百分比；wheel/grid冷帧主机汇总仅2/5、1/5成功，数值来自原始driver响应，失败标记保留。真机采集链路未通过，不把已标定写成达到设计目标。

| 场景 | 本次未污染/全部 | 未污染合计/UI P99最大ms | 结论 |
| --- | --- | --- | --- |
| grid_steady | 2/3 | 14.039/2.222 | 失败 |
| slot_raster | 3/3 | 5.397/2.093 | 失败 |
| lots_shaking | 3/3 | 10.919/2.682 | 不确定 |
| lotto_draw | 3/3 | 12.331/4.57 | 失败 |

本次CPU五个项目各5次均在before阶段失败，原生cpuinfo统计区间不对应新启动进程，匹配不到当前PID或命中旧PID；top可出现0线程及S[%CPU]等列头。例如cpu_wheel_steady_1的cpuinfo区间为00:38:23.396–00:40:58.935，并非本次五秒窗口；cpu_capsule_mixing_1返回的区间结束于采样前216647ms。完整原文和错误见results/pending/cpu_*/cpu/与audit.json。这些是采样链路故障，不是CPU=0，不是luckdraw代码性能证据。

冷首帧设备端测试成功且FrameTiming响应完整，但主机TimelineSummary在部分冷窗口没有闭合Raster事件，因此wheel/grid只有2/5、1/5次driver成功。恢复数据保留原始response及时间关联，不改runs.json失败状态。

本次逐帧归因文件见[frames.json](../tool/bench/results/pending/frames.json)。硬余量失败的代码根因仍为「无法判定」：缺少可靠原生线程CPU及luckdraw函数采样栈，不能将GLES/Encode墙钟等待等同可避免的库内工作；本轮未改lib、parity或golden。本次仍有硬失败时按原值保留，不放宽12ms/4ms门禁。

DEVFIN逐帧复核：11个未污染新窗口均成功按引擎帧号配对，尖峰（trace同帧合计>12ms或UI>4ms）计数为{'grid_steady': 5, 'slot_raster': 0, 'lots_shaking': 2, 'lotto_draw': 37}。grid和lots的代表长区间位于SurfaceFrame::Submit/DrawToSurfaces；lotto含UI尖峰。该trace计数与FrameTiming P99采集边界不同，不能拿它替换硬门禁；CPU采样未成功，代码根因仍无法判定。

补充：冻结成本与波动（不能只看硬余量）

| 场景 | UI均值中位数ms | Raster均值/P90中位数ms | 未通过指标 |
| --- | --- | --- | --- |
| grid_steady | 1.062244 | 5.752400/7.333000 | average_frame_rasterizer_time_millis: 5.752400332225915 / 上限4.0, 状态FAIL, 极差比0.07572340883265483；90th_percentile_frame_rasterizer_time_millis: 7.333 / 上限7.0, 状态FAIL, 极差比0.0684576571662348 |
| slot_raster | 1.090628 | 2.896249/3.295000 | average_frame_build_time_millis: 1.0906279069767444 / 上限1.0, 状态FAIL, 极差比0.03513779437612421 |
| lots_shaking | 1.232439 | 3.059010/3.478000 | average_frame_rasterizer_time_millis: 3.0590099667774124 / 上限5.0, 状态UNCERTAIN, 极差比0.5805018017685337；90th_percentile_frame_rasterizer_time_millis: 3.478 / 上限8.0, 状态UNCERTAIN, 极差比0.6403105232892466 |
| lotto_draw | 2.208983 | 5.225883/5.945000 | 成本指标通过，硬余量另验 |

slot_raster旧硬余量失败本轮未重现，但UI均值1.090627907ms>冻结1.0ms，仍失败。grid的Raster均值5.752400332ms>4ms、P90 7.333ms>7ms；lotto硬余量最大12.331ms/UI4.570ms；lots均值/P90相对极差58.050%/64.031%，保持不确定。

## 冷首帧归因（INSTR，第五轮）

INSTR（2026-11-11，副本候选实现）：wheel/grid带打点冷首帧中位数38.412→27.075ms、24.214→12.993ms，精确文字宽度缓存将首帧TextPainter.layout次数276→63、128→22；随机/多语言/emoji/lineClamp等价。减DEVFIN历史空白2.883ms后的增量24.192/10.110ms，新预算26.612/11.121ms，仍未达到原4ms目标，三轮波动大。CPU采用/proc累计节拍差，UI与平台合并标为UI+platform；wheel完整链路仅2/5，不能给三轮中位数；其余场景逐轮数值和有效性见本轮报告，lotto仅搅拌阶段。库改动以补丁交付，未覆盖并行共享lib，待主会话合并。

以上逐阶段去重表、每个事件起止、三轮原值、CPU与限制见[第五轮完整归因报告](../tool/bench/results/pending2/REPORT.md)及[attribution.json](../tool/bench/results/pending2/attribution.json)。首帧中位数代表轮中，wheel文字32.138→15.709ms（Dart Frame占81.69%→51.76%），grid文字16.345→4.774ms（63.12%→33.40%）；布局/文字/录制为嵌套片段，不直接相加。已定位重复整形、已在副本修复并观测改善；未打点区间及异步图片解码仍无法判定。

### INSTR 冷首帧阶段原值与占比


FrameTiming.buildDuration 是首帧结果指标；下表各阶段与占比的共同分母为**包含首次玩法 layout 的 Dart Frame b/e 墙钟区间**，两种边界不同。为避免各列独立中位数不能相加，每行选三轮中 FrameTiming 为中位数的那一轮。布局剔除文字；录制剔除文字/位图；文字包括录制期整形；其它是未打点区间（含框架），无法进一步归因。

| 阶段/玩法 | FrameTiming / Dart Frame ms | 布局去文字 ms/% | 文字 ms/% | 录制去文字位图 ms/% | 位图 ms/% | 图片更新 ms/% | paint ms/% | 其它 ms/% |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before/wheel | 38.412 / 39.341 | 0.825 / 2.10% | 32.138 / 81.69% | 1.755 / 4.46% | 0.122 / 0.31% | 0.651 / 1.65% | 0.035 / 0.09% | 3.815 / 9.70% |
| before/grid | 24.214 / 25.894 | 0.320 / 1.24% | 16.345 / 63.12% | 4.408 / 17.02% | 1.217 / 4.70% | 0.025 / 0.10% | 0.062 / 0.24% | 3.517 / 13.58% |
| after/wheel | 27.075 / 30.349 | 0.998 / 3.29% | 15.709 / 51.76% | 4.478 / 14.76% | 0.337 / 1.11% | 1.851 / 6.10% | 0.080 / 0.26% | 6.896 / 22.72% |
| after/grid | 12.993 / 14.292 | 0.245 / 1.71% | 4.774 / 33.40% | 4.578 / 32.03% | 1.316 / 9.21% | 0.054 / 0.38% | 0.087 / 0.61% | 3.238 / 22.66% |

全部12个有效冷窗口的每个 luckdraw 事件（含每次文字测量）绝对 start_us/end_us、相对起止、arguments、未配对事件及阶段原值见 [attribution.json](../tool/bench/results/pending2/attribution.json)。各首帧内 luckdraw 事件均完整配对；窗口外裁断事件单独列示。可用 `python tool/bench/analyze_instr.py` 离线重算。以下为每轮原始统计：

| 阶段/玩法/轮 | FrameTiming ms | Dart Frame起止 μs | layout/record含子事件 ms | TextPainter次数 / 总ms / 每次均ms |
| --- | --- | --- | --- | --- |
| before/wheel/1 | 38.412 | 71231378045–71231417386 | 30.363 / 4.477 | 276 / 25.051 / 0.090764 |
| before/wheel/2 | 46.689 | 71251744685–71251792696 | 37.131 / 5.652 | 276 / 28.405 / 0.102917 |
| before/wheel/3 | 25.178 | 71272077746–71272103829 | 19.496 / 3.750 | 276 / 15.205 / 0.055091 |
| before/grid/1 | 20.660 | 71305211196–71305233228 | 11.768 / 6.932 | 128 / 10.720 / 0.083750 |
| before/grid/2 | 28.587 | 71324478327–71324508950 | 15.771 / 10.327 | 128 / 14.389 / 0.112414 |
| before/grid/3 | 24.214 | 71343277973–71343303867 | 14.200 / 8.090 | 128 / 12.718 / 0.099359 |
| after/wheel/1 | 28.309 | 71559761606–71559791361 | 11.544 / 11.022 | 63 / 14.204 / 0.225460 |
| after/wheel/2 | 10.715 | 71579011106–71579022975 | 3.982 / 4.609 | 63 / 5.104 / 0.081016 |
| after/wheel/3 | 27.075 | 71597978290–71598008639 | 10.297 / 11.225 | 63 / 12.763 / 0.202587 |
| after/grid/1 | 8.585 | 71720027104–71720036789 | 2.009 / 5.372 | 22 / 2.906 / 0.132091 |
| after/grid/2 | 21.166 | 71739761028–71739783725 | 5.918 / 11.761 | 22 / 6.810 / 0.309545 |
| after/grid/3 | 12.993 | 71758843927–71758858219 | 2.711 / 8.202 | 22 / 4.114 / 0.187000 |



## 稳态尖峰归因（带打点，STEADY 第六轮）

STEADY（2026-11-11）仅单台 vivo V2417 / Android16：四场景带luckdraw打点，slot/grid/lots各3/3，lotto4/5（2个污染、1个安装后VM连接超时，未污染2）。轮前后核对未锁，窗口内无额外adb轮询。按引擎帧号配对并校验SDK数组，trace尖峰与FrameTiming P99独立，12ms/4ms和MET2规则均未放宽。

slot/grid尖峰主要在框架编码/提交；lotto结算重复准备已定位，但复用painter候选三轮没有稳定净收益，已回滚。lots本轮三轮稳定且通过，不能解释历史不稳定。wheel /proc CPU已补齐3/3；仅标定，不外推跨设备。

| 场景 | 成功/启动/未污染 | 尖峰各轮（仅未污染） | 位置 | 事件累计ms / %同帧合计 | 结论三选一 |
| --- | --- | --- | --- | --- | --- |
| slot_raster | 3/3/3 | 0/2/2 | 2.566–2.583s、4.534–4.550s，成对；首5帧0 | paint 0.377/0.67%；Encode 43.418/77.47%；Submit 50.742/90.54% | 框架或设备（有证据：长区间在编码/提交，具体GPU/驱动/调度原因无法判定） |
| grid_steady | 3/3/3 | 0/2/2 | 2.867–2.884s、4.700–4.718s，成对；首5帧0 | paint 0.902/1.36%；Encode 52.004/78.58%；Submit 59.596/90.05%；CreateGlyphAtlas 0.119/0.18% | 框架或设备（有证据：编码/提交；不是已证明的设备缺陷） |
| lotto_draw | 4/5/2 | 10/9 | 0.134–4.434s，搅拌/开奖散布；含结算最后帧，首5帧0 | paint 38.181/19.90%；record 5.956/3.10%；Encode 55.164/28.75%；COMPOSITING 15.508/8.08% | 库内成本（已定位：结算重复准备；其它UI尖峰仍无法判定可避免性） |
| lots_shaking | 3/3/3 | 0/1/1 | 2.367s与3.583s的孤立UI尖峰，首5帧0 | paint 1.123/7.05%；COMPOSITING 4.597/28.86%；Encode 2.149/13.49% | 无法判定（历史Raster不稳定未重现；本轮UI长区间多在框架） |

打点启用 `luckdraw.{slot,grid,lotto,lots,wheel}.{layout,record,paint}` 与 text.layout/split/painter.layout、image.update、picture.record、raster.build/prepare/atlas。库区间按并集去重；包含事件不可相加，墙钟不是CPU。稳态slot/grid无重复layout/record/text；lotto结算1次record包含50次缓存查询、47次回放参数准备，不能说是重录50张Picture。分配采样栈缺失，无法判定每帧分配数量。

slot入场首帧引擎号802/797/799，UI线程atlas同步调用0.388/0.285/0.473ms；后续图片更新还有准备调用，完整11次见下表。没有GPU实际位图执行/上传的独立子事件，完整GPU构建耗时与线程仍无法判定，不能用SurfaceFrame::Encode尖峰冒充图集构建。

### wheel CPU最新三轮

| 轮 | 进程% | UI+platform% | Raster% | 实际秒数 | 首/尾读取ms |
| --- | --- | --- | --- | --- | --- |
| 1 | 40.039608 | 15.014853 | 18.299352 | 6.393669 | 1381.079/1536.642 |
| 2 | 35.523078 | 12.675636 | 18.152762 | 6.390212 | 1375.282/1530.990 |
| 3 | 39.291465 | 14.930757 | 18.545571 | 6.362705 | 1336.095/1515.638 |
| 中位数 | 39.291465 | 14.930757 | 18.299352 | — | — |

主线程为UI+platform合并；实际窗口6.394/6.390/6.363秒，首尾读取各一次adb，按/proc累计节拍差和真实间隔计算。旧缺轮第1/2次为driver错误要求GC参照（INSTR已修），第5次未连接采样器超时；不把旧失败改为成功，不重采其余四个玩法CPU。

### lotto候选实验已回滚

结算帧UI11.485ms，record5.956ms占51.86%。候选确实将record次数1/1降至0/0/0，但场景净收益不稳定，按要求回滚，原库文件逐字节恢复；拒绝补丁不是待合并修复。

| 指标（未污染） | 原始实现2窗口 | 候选3窗口 | 结论 |
| --- | --- | --- | --- |
| trace尖峰/帧数/比例 | 19/534/3.56% | 47/808/5.82% | 没有下降；轮数不同不只比较总数 |
| 合计P99各轮ms / 最大 | 9.620/9.169 / 9.620 | 9.098/9.788/10.593 / 10.593 | 均≤12，但候选最大更高 |
| UI P99各轮ms / 最大 | 4.725/4.226 / 4.725 | 4.120/4.565/3.376 / 4.565 | 仍有窗口>4，失败 |
| UI均值中位数ms / 极差比 | 2.233893 / 8.22% | 2.391984 / 36.05% | 候选均值更高且不稳定 |
| Raster均值中位数ms / 极差比 | 4.731389 / 1.49% | 4.839185 / 9.43% | 未观测净改善 |
| Raster P90中位数ms | 5.141 | 5.283 | 候选更高 |
| record次数 | 1/1 | 0/0/0 | 结构性工作消除不等于场景收益 |
| MET2最终状态 | FAIL | FAIL | 两者UI硬门禁失败；未放宽预算 |

新增工具回归与全部命令输出见[STEADY完整报告](../tool/bench/results/steady/REPORT.md)。预算与MANIFEST/基线不改；没有最终保留的库优化。普通帧/每个尖峰事件/GC/边界信息如下，原始数据见[frames.json](../tool/bench/results/steady/frames.json)。

### 完整逐帧清单

STEADY逐帧证据

按引擎 frame_number 配对并逐项校验 SDK 时长数组；仅未污染窗口参与归因。
尖峰为 trace 同帧 UI+Raster>12ms 或 UI>4ms，硬门禁另用 FrameTiming P99。
包含耗时/占比可嵌套，不能相加；墙钟不能直接当 CPU。普通帧包含零次该事件的帧。

| 场景/run_id | 帧数 | 尖峰/首5帧 | 每秒尖峰桶 |
| --- | --- | --- | --- |
| slot_raster/1794335894537151 | 297 | 0/0 | {} |
| slot_raster/1794335965641572 | 297 | 2/0 | {2: 2} |
| slot_raster/1794336036358822 | 297 | 2/0 | {4: 2} |
| grid_steady/1794336102072654 | 294 | 0/0 | {} |
| grid_steady/1794336169263247 | 295 | 2/0 | {4: 2} |
| grid_steady/1794336234640396 | 294 | 2/0 | {2: 2} |
| lotto_draw/1794336740704716 | 267 | 10/0 | {0: 3, 1: 1, 2: 1, 4: 5} |
| lotto_draw/1794336808482013 | 267 | 9/0 | {0: 3, 1: 2, 2: 1, 4: 3} |
| lots_shaking/1794336871606953 | 298 | 0/0 | {} |
| lots_shaking/1794336934144721 | 298 | 1/0 | {3: 1} |
| lots_shaking/1794336996368281 | 297 | 1/0 | {2: 1} |

| 场景/run_id | UI/Raster均值ms | paint均值ms | Encode/Submit均值ms | layout/record/text事件次数 |
| --- | --- | --- | --- | --- |
| slot_raster/1794335894537151 | 1.219/2.948 | 0.126 | 0.737/2.609 | [0, 0, 0] |
| slot_raster/1794335965641572 | 1.285/5.246 | 0.125 | 3.041/4.911 | [0, 0, 0] |
| slot_raster/1794336036358822 | 1.246/5.634 | 0.119 | 3.463/5.298 | [0, 0, 0] |
| grid_steady/1794336102072654 | 1.168/3.384 | 0.203 | 1.294/3.074 | [0, 0, 0] |
| grid_steady/1794336169263247 | 1.235/3.822 | 0.231 | 1.621/3.496 | [0, 0, 0] |
| grid_steady/1794336234640396 | 1.126/6.016 | 0.196 | 3.926/5.691 | [0, 0, 0] |
| lotto_draw/1794336740704716 | 2.424/4.916 | 1.101 | 2.697/4.564 | [0, 51, 0] |
| lotto_draw/1794336808482013 | 2.587/4.728 | 1.178 | 2.570/4.391 | [0, 51, 0] |
| lots_shaking/1794336871606953 | 1.285/3.099 | 0.346 | 0.979/2.782 | [0, 0, 0] |
| lots_shaking/1794336934144721 | 1.350/3.082 | 0.375 | 0.972/2.766 | [0, 0, 0] |
| lots_shaking/1794336996368281 | 1.472/3.101 | 0.398 | 0.977/2.790 | [0, 0, 0] |

#### slot_raster

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| 1794335965641572/155/1354 | 2566.402 | 0.805/12.361/13.166 | 0.081/10.06% | luckdraw.slot.paint 0.081 |
| 1794335965641572/156/1355 | 2583.356 | 1.372/13.478/14.850 | 0.101/7.36% | luckdraw.slot.paint 0.101 |
| 1794336036358822/273/1474 | 4533.508 | 0.854/13.073/13.927 | 0.097/11.36% | luckdraw.slot.paint 0.097 |
| 1794336036358822/274/1475 | 4550.420 | 0.963/13.140/14.103 | 0.098/10.18% | luckdraw.slot.paint 0.098 |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |
| Animate | 0.518 / 0.130 / 0.92% | 157.706 / 0.178 / 3.05% |
| COMPOSITING | 1.221 / 0.305 / 2.18% | 362.305 / 0.408 / 7.01% |
| LAYOUT | 0.021 / 0.005 / 0.04% | 5.854 / 0.007 / 0.11% |
| LayerTree::Paint | 0.152 / 0.038 / 0.27% | 37.715 / 0.043 / 0.73% |
| PAINT | 1.169 / 0.292 / 2.09% | 317.683 / 0.358 / 6.15% |
| Rasterizer::DoDraw | 51.969 / 12.992 / 92.73% | 4035.891 / 4.550 / 78.13% |
| Rasterizer::DrawToSurfaces | 51.883 / 12.971 / 92.57% | 4018.250 / 4.530 / 77.78% |
| RenderPassGLES::EncodeCommandsInReactor | 42.552 / 10.638 / 75.92% | 1918.011 / 2.162 / 37.13% |
| SEMANTICS | 0.119 / 0.030 / 0.21% | 35.901 / 0.040 / 0.69% |
| SurfaceFrame::Encode | 43.418 / 10.854 / 77.47% | 2107.149 / 2.376 / 40.79% |
| SurfaceFrame::Submit | 50.742 / 12.685 / 90.54% | 3756.550 / 4.235 / 72.72% |
| luckdraw.slot.paint | 0.377 / 0.094 / 0.67% | 109.328 / 0.123 / 2.12% |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |
| 1794335965641572/155 | Animate 0.110/0.84%；COMPOSITING 0.226/1.72%；LAYOUT 0.004/0.03%；LayerTree::Paint 0.040/0.30%；PAINT 0.230/1.75%；Rasterizer::DoDraw 12.340/93.73%；Rasterizer::DrawToSurfaces 12.325/93.61%；RenderPassGLES::EncodeCommandsInReactor 9.969/75.72%；SEMANTICS 0.021/0.16%；SurfaceFrame::Encode 10.166/77.21%；SurfaceFrame::Submit 11.993/91.09% |
| 1794335965641572/156 | Animate 0.146/0.98%；COMPOSITING 0.459/3.09%；LAYOUT 0.006/0.04%；LayerTree::Paint 0.039/0.26%；PAINT 0.384/2.59%；Rasterizer::DoDraw 13.457/90.62%；Rasterizer::DrawToSurfaces 13.414/90.33%；RenderPassGLES::EncodeCommandsInReactor 11.014/74.17%；SEMANTICS 0.038/0.26%；SurfaceFrame::Encode 11.220/75.56%；SurfaceFrame::Submit 13.132/88.43% |
| 1794336036358822/273 | Animate 0.121/0.87%；COMPOSITING 0.258/1.85%；LAYOUT 0.005/0.04%；LayerTree::Paint 0.038/0.27%；PAINT 0.265/1.90%；Rasterizer::DoDraw 13.050/93.70%；Rasterizer::DrawToSurfaces 13.036/93.60%；RenderPassGLES::EncodeCommandsInReactor 10.784/77.43%；SEMANTICS 0.026/0.19%；SurfaceFrame::Encode 10.983/78.86%；SurfaceFrame::Submit 12.773/91.71% |
| 1794336036358822/274 | Animate 0.141/1.00%；COMPOSITING 0.278/1.97%；LAYOUT 0.006/0.04%；LayerTree::Paint 0.035/0.25%；PAINT 0.290/2.06%；Rasterizer::DoDraw 13.122/93.04%；Rasterizer::DrawToSurfaces 13.108/92.94%；RenderPassGLES::EncodeCommandsInReactor 10.785/76.47%；SEMANTICS 0.034/0.24%；SurfaceFrame::Encode 11.049/78.35%；SurfaceFrame::Submit 12.844/91.07% |

#### grid_steady

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| 1794336169263247/283/1242 | 4700.149 | 1.208/14.571/15.779 | 0.358/29.64% | luckdraw.grid.paint 0.358 |
| 1794336169263247/284/1243 | 4717.864 | 0.933/16.021/16.954 | 0.000/0.00% | 无 |
| 1794336234640396/173/1129 | 2867.303 | 1.067/15.539/16.606 | 0.000/0.00% | 无 |
| 1794336234640396/174/1130 | 2883.695 | 1.952/14.889/16.841 | 0.544/27.87% | luckdraw.grid.paint 0.544 |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |
| Animate | 0.745 / 0.186 / 1.13% | 140.995 / 0.160 / 2.90% |
| COMPOSITING | 1.470 / 0.367 / 2.22% | 333.129 / 0.379 / 6.85% |
| CreateGlyphAtlas | 0.119 / 0.030 / 0.18% | 26.135 / 0.030 / 0.54% |
| LAYOUT | 0.032 / 0.008 / 0.05% | 5.831 / 0.007 / 0.12% |
| LayerTree::Paint | 0.167 / 0.042 / 0.25% | 35.606 / 0.041 / 0.73% |
| PAINT | 1.347 / 0.337 / 2.04% | 297.496 / 0.338 / 6.12% |
| Rasterizer::DoDraw | 60.945 / 15.236 / 92.09% | 3812.424 / 4.337 / 78.37% |
| Rasterizer::DrawToSurfaces | 60.837 / 15.209 / 91.93% | 3795.969 / 4.319 / 78.03% |
| RenderPassGLES::EncodeCommandsInReactor | 50.107 / 12.527 / 75.71% | 1557.480 / 1.772 / 32.02% |
| SEMANTICS | 0.157 / 0.039 / 0.24% | 35.017 / 0.040 / 0.72% |
| SurfaceFrame::Encode | 52.004 / 13.001 / 78.58% | 1961.006 / 2.231 / 40.31% |
| SurfaceFrame::Submit | 59.596 / 14.899 / 90.05% | 3548.475 / 4.037 / 72.95% |
| luckdraw.grid.paint | 0.902 / 0.226 / 1.36% | 184.792 / 0.210 / 3.80% |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |
| 1794336169263247/283 | Animate 0.121/0.77%；COMPOSITING 0.326/2.07%；CreateGlyphAtlas 0.031/0.20%；LAYOUT 0.005/0.03%；LayerTree::Paint 0.042/0.27%；PAINT 0.538/3.41%；Rasterizer::DoDraw 14.551/92.22%；Rasterizer::DrawToSurfaces 14.523/92.04%；RenderPassGLES::EncodeCommandsInReactor 11.933/75.63%；SEMANTICS 0.027/0.17%；SurfaceFrame::Encode 12.405/78.62%；SurfaceFrame::Submit 14.238/90.23% |
| 1794336169263247/284 | Animate 0.194/1.14%；COMPOSITING 0.403/2.38%；CreateGlyphAtlas 0.031/0.18%；LAYOUT 0.008/0.05%；LayerTree::Paint 0.042/0.25%；PAINT 0.006/0.04%；Rasterizer::DoDraw 16.003/94.39%；Rasterizer::DrawToSurfaces 15.977/94.24%；RenderPassGLES::EncodeCommandsInReactor 13.228/78.02%；SEMANTICS 0.046/0.27%；SurfaceFrame::Encode 13.711/80.87%；SurfaceFrame::Submit 15.711/92.67% |
| 1794336234640396/173 | Animate 0.165/0.99%；COMPOSITING 0.388/2.34%；CreateGlyphAtlas 0.030/0.18%；LAYOUT 0.009/0.05%；LayerTree::Paint 0.047/0.28%；PAINT 0.005/0.03%；Rasterizer::DoDraw 15.520/93.46%；Rasterizer::DrawToSurfaces 15.495/93.31%；RenderPassGLES::EncodeCommandsInReactor 12.968/78.09%；SEMANTICS 0.040/0.24%；SurfaceFrame::Encode 13.457/81.04%；SurfaceFrame::Submit 15.105/90.96% |
| 1794336234640396/174 | Animate 0.265/1.57%；COMPOSITING 0.353/2.10%；CreateGlyphAtlas 0.027/0.16%；LAYOUT 0.010/0.06%；LayerTree::Paint 0.036/0.21%；PAINT 0.798/4.74%；Rasterizer::DoDraw 14.871/88.30%；Rasterizer::DrawToSurfaces 14.842/88.13%；RenderPassGLES::EncodeCommandsInReactor 11.978/71.12%；SEMANTICS 0.044/0.26%；SurfaceFrame::Encode 12.431/73.81%；SurfaceFrame::Submit 14.542/86.35% |

#### lotto_draw

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| 1794336740704716/36/1198 | 583.907 | 4.026/5.517/9.543 | 1.727/42.90% | luckdraw.lotto.paint 1.727 |
| 1794336740704716/41/1203 | 668.047 | 4.588/5.249/9.837 | 1.577/34.37% | luckdraw.lotto.paint 1.577 |
| 1794336740704716/50/1212 | 818.009 | 4.022/5.371/9.393 | 1.619/40.25% | luckdraw.lotto.paint 1.619 |
| 1794336740704716/69/1231 | 1134.089 | 4.771/4.970/9.741 | 2.360/49.47% | luckdraw.lotto.paint 2.360 |
| 1794336740704716/141/1303 | 2333.811 | 4.853/3.985/8.838 | 2.738/56.42% | luckdraw.lotto.paint 2.738 |
| 1794336740704716/255/1417 | 4234.257 | 4.758/5.094/9.852 | 2.304/48.42% | luckdraw.lotto.paint 2.304 |
| 1794336740704716/261/1423 | 4334.375 | 4.094/5.175/9.269 | 2.095/51.17% | luckdraw.lotto.paint 2.095 |
| 1794336740704716/262/1424 | 4350.752 | 4.551/4.926/9.477 | 2.344/51.51% | luckdraw.lotto.paint 2.344 |
| 1794336740704716/266/1428 | 4417.364 | 4.198/5.299/9.497 | 1.609/38.33% | luckdraw.lotto.paint 1.609 |
| 1794336740704716/267/1429 | 4434.105 | 11.485/7.508/18.993 | 7.729/67.30% | luckdraw.lotto.record 5.956；luckdraw.picture.record 0.009；luckdraw.picture.record 0.006；luckdraw.picture.record 0.008；luckdraw.picture.record 0.007；luckdraw.raster.build 0.011；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.012；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.005；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.005；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.007；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.007；luckdraw.raster.build 0.008；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.015；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.008；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.005；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.007；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.343；luckdraw.raster.build 0.014；luckdraw.raster.prepare 0.008；luckdraw.picture.record 0.007；luckdraw.raster.build 0.012；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.005；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.007；luckdraw.raster.build 0.009；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.007；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.007；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.007；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.005；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.005；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.005；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.007；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.006；luckdraw.picture.record 0.006；luckdraw.raster.build 0.008；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.006；luckdraw.raster.build 0.007；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.006；luckdraw.raster.build 0.008；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.005；luckdraw.raster.build 0.008；luckdraw.raster.prepare 0.007；luckdraw.picture.record 0.007；luckdraw.raster.build 0.008；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.005；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.picture.record 0.005；luckdraw.raster.build 0.006；luckdraw.raster.prepare 0.005；luckdraw.lotto.paint 1.773 |
| 1794336808482013/9/1169 | 133.729 | 5.480/4.904/10.384 | 1.529/27.90% | luckdraw.lotto.paint 1.529 |
| 1794336808482013/13/1173 | 200.034 | 4.136/4.505/8.641 | 2.393/57.86% | luckdraw.lotto.paint 2.393 |
| 1794336808482013/21/1181 | 333.094 | 4.836/4.739/9.575 | 1.585/32.78% | luckdraw.lotto.paint 1.585 |
| 1794336808482013/91/1251 | 1499.839 | 4.840/4.797/9.637 | 2.032/41.98% | luckdraw.lotto.paint 2.032 |
| 1794336808482013/95/1255 | 1566.924 | 4.010/5.091/9.101 | 2.398/59.80% | luckdraw.lotto.paint 2.398 |
| 1794336808482013/123/1283 | 2033.149 | 5.254/5.643/10.897 | 1.507/28.68% | luckdraw.lotto.paint 1.507 |
| 1794336808482013/241/1401 | 4000.518 | 5.207/5.146/10.353 | 2.406/46.21% | luckdraw.lotto.paint 2.406 |
| 1794336808482013/247/1407 | 4100.325 | 4.213/5.133/9.346 | 2.223/52.77% | luckdraw.lotto.paint 2.223 |
| 1794336808482013/264/1424 | 4383.511 | 4.394/5.122/9.516 | 1.962/44.65% | luckdraw.lotto.paint 1.962 |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |
| Animate | 8.599 / 0.453 / 4.48% | 159.194 / 0.309 / 4.28% |
| BUILD | 6.481 / 0.341 / 3.38% | 0.000 / 0.000 / 0.00% |
| COMPOSITING | 15.508 / 0.816 / 8.08% | 213.092 / 0.414 / 5.73% |
| CreateGlyphAtlas | 1.177 / 0.062 / 0.61% | 8.371 / 0.016 / 0.22% |
| Dart_InvokeClosure | 0.026 / 0.001 / 0.01% | 0.000 / 0.000 / 0.00% |
| LAYOUT | 6.650 / 0.350 / 3.47% | 3.344 / 0.006 / 0.09% |
| LayerTree::Paint | 0.807 / 0.042 / 0.42% | 20.848 / 0.040 / 0.56% |
| PAINT | 48.179 / 2.536 / 25.11% | 702.441 / 1.364 / 18.88% |
| Rasterizer::DoDraw | 97.272 / 5.120 / 50.69% | 2462.548 / 4.782 / 66.17% |
| Rasterizer::DrawToSurfaces | 96.884 / 5.099 / 50.49% | 2452.251 / 4.762 / 65.89% |
| RenderPassGLES::EncodeCommandsInReactor | 36.573 / 1.925 / 19.06% | 903.990 / 1.755 / 24.29% |
| SEMANTICS | 4.311 / 0.227 / 2.25% | 23.103 / 0.045 / 0.62% |
| SurfaceFrame::Encode | 55.164 / 2.903 / 28.75% | 1351.090 / 2.623 / 36.31% |
| SurfaceFrame::Submit | 90.747 / 4.776 / 47.29% | 2300.148 / 4.466 / 61.81% |
| luckdraw.lotto.paint | 38.181 / 2.010 / 19.90% | 570.279 / 1.107 / 15.32% |
| luckdraw.lotto.record | 5.956 / 0.313 / 3.10% | 0.000 / 0.000 / 0.00% |
| luckdraw.picture.record | 0.645 / 0.034 / 0.34% | 0.000 / 0.000 / 0.00% |
| luckdraw.raster.build | 0.344 / 0.018 / 0.18% | 0.000 / 0.000 / 0.00% |
| luckdraw.raster.prepare | 0.274 / 0.014 / 0.14% | 0.000 / 0.000 / 0.00% |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |
| 1794336740704716/36 | Animate 0.389/4.08%；COMPOSITING 0.490/5.13%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.068/0.71%；PAINT 2.787/29.20%；Rasterizer::DoDraw 5.493/57.56%；Rasterizer::DrawToSurfaces 5.478/57.40%；RenderPassGLES::EncodeCommandsInReactor 1.776/18.61%；SEMANTICS 0.052/0.54%；SurfaceFrame::Encode 2.890/30.28%；SurfaceFrame::Submit 4.877/51.11% |
| 1794336740704716/41 | Animate 0.406/4.13%；COMPOSITING 0.507/5.15%；CreateGlyphAtlas 0.015/0.15%；LAYOUT 0.011/0.11%；LayerTree::Paint 0.044/0.45%；PAINT 3.188/32.41%；Rasterizer::DoDraw 5.225/53.12%；Rasterizer::DrawToSurfaces 5.176/52.62%；RenderPassGLES::EncodeCommandsInReactor 1.885/19.16%；SEMANTICS 0.044/0.45%；SurfaceFrame::Encode 2.770/28.16%；SurfaceFrame::Submit 4.874/49.55% |
| 1794336740704716/50 | Animate 0.389/4.14%；COMPOSITING 1.317/14.02%；CreateGlyphAtlas 0.018/0.19%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.044/0.47%；PAINT 1.920/20.44%；Rasterizer::DoDraw 5.349/56.95%；Rasterizer::DrawToSurfaces 5.332/56.77%；RenderPassGLES::EncodeCommandsInReactor 2.065/21.98%；SEMANTICS 0.046/0.49%；SurfaceFrame::Encode 3.007/32.01%；SurfaceFrame::Submit 5.029/53.54% |
| 1794336740704716/69 | Animate 0.549/5.64%；COMPOSITING 0.469/4.81%；CreateGlyphAtlas 0.015/0.15%；LAYOUT 0.011/0.11%；LayerTree::Paint 0.037/0.38%；PAINT 3.398/34.88%；Rasterizer::DoDraw 4.950/50.82%；Rasterizer::DrawToSurfaces 4.939/50.70%；RenderPassGLES::EncodeCommandsInReactor 2.114/21.70%；SEMANTICS 0.047/0.48%；SurfaceFrame::Encode 2.985/30.64%；SurfaceFrame::Submit 4.677/48.01% |
| 1794336740704716/141 | Animate 0.475/5.37%；COMPOSITING 1.029/11.64%；CreateGlyphAtlas 0.012/0.14%；LAYOUT 0.007/0.08%；LayerTree::Paint 0.031/0.35%；PAINT 3.011/34.07%；Rasterizer::DoDraw 3.966/44.87%；Rasterizer::DrawToSurfaces 3.955/44.75%；RenderPassGLES::EncodeCommandsInReactor 1.703/19.27%；SEMANTICS 0.045/0.51%；SurfaceFrame::Encode 2.381/26.94%；SurfaceFrame::Submit 3.720/42.09% |
| 1794336740704716/255 | Animate 0.399/4.05%；COMPOSITING 0.450/4.57%；CreateGlyphAtlas 0.014/0.14%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.047/0.48%；PAINT 2.620/26.59%；Rasterizer::DoDraw 5.072/51.48%；Rasterizer::DrawToSurfaces 5.058/51.34%；RenderPassGLES::EncodeCommandsInReactor 1.884/19.12%；SEMANTICS 0.700/7.11%；SurfaceFrame::Encode 2.748/27.89%；SurfaceFrame::Submit 4.576/46.45% |
| 1794336740704716/261 | Animate 0.404/4.36%；COMPOSITING 0.675/7.28%；CreateGlyphAtlas 0.015/0.16%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.044/0.47%；PAINT 2.442/26.35%；Rasterizer::DoDraw 5.151/55.57%；Rasterizer::DrawToSurfaces 5.136/55.41%；RenderPassGLES::EncodeCommandsInReactor 2.142/23.11%；SEMANTICS 0.064/0.69%；SurfaceFrame::Encode 3.024/32.62%；SurfaceFrame::Submit 4.840/52.22% |
| 1794336740704716/262 | Animate 0.384/4.05%；COMPOSITING 0.676/7.13%；CreateGlyphAtlas 0.016/0.17%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.042/0.44%；PAINT 2.660/28.07%；Rasterizer::DoDraw 4.903/51.74%；Rasterizer::DrawToSurfaces 4.888/51.58%；RenderPassGLES::EncodeCommandsInReactor 1.930/20.37%；SEMANTICS 0.251/2.65%；SurfaceFrame::Encode 2.809/29.64%；SurfaceFrame::Submit 4.588/48.41% |
| 1794336740704716/266 | Animate 0.517/5.44%；COMPOSITING 1.295/13.64%；CreateGlyphAtlas 0.018/0.19%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.042/0.44%；PAINT 1.917/20.19%；Rasterizer::DoDraw 5.273/55.52%；Rasterizer::DrawToSurfaces 5.226/55.03%；RenderPassGLES::EncodeCommandsInReactor 1.965/20.69%；SEMANTICS 0.047/0.49%；SurfaceFrame::Encode 2.879/30.31%；SurfaceFrame::Submit 4.909/51.69% |
| 1794336740704716/267 | Animate 0.682/3.59%；BUILD 6.481/34.12%；COMPOSITING 0.464/2.44%；CreateGlyphAtlas 0.892/4.70%；Dart_InvokeClosure 0.026/0.14%；LAYOUT 6.501/34.23%；LayerTree::Paint 0.038/0.20%；PAINT 2.292/12.07%；Rasterizer::DoDraw 7.485/39.41%；Rasterizer::DrawToSurfaces 7.447/39.21%；RenderPassGLES::EncodeCommandsInReactor 2.844/14.97%；SEMANTICS 0.894/4.71%；SurfaceFrame::Encode 5.260/27.69%；SurfaceFrame::Submit 7.161/37.70% |
| 1794336808482013/9 | Animate 0.402/3.87%；COMPOSITING 2.140/20.61%；CreateGlyphAtlas 0.014/0.13%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.041/0.39%；PAINT 2.560/24.65%；Rasterizer::DoDraw 4.844/46.65%；Rasterizer::DrawToSurfaces 4.830/46.51%；RenderPassGLES::EncodeCommandsInReactor 1.886/18.16%；SEMANTICS 0.042/0.40%；SurfaceFrame::Encode 2.717/26.17%；SurfaceFrame::Submit 4.550/43.82% |
| 1794336808482013/13 | Animate 0.394/4.56%；COMPOSITING 0.570/6.60%；CreateGlyphAtlas 0.015/0.17%；LAYOUT 0.007/0.08%；LayerTree::Paint 0.036/0.42%；PAINT 2.810/32.52%；Rasterizer::DoDraw 4.483/51.88%；Rasterizer::DrawToSurfaces 4.448/51.48%；RenderPassGLES::EncodeCommandsInReactor 1.599/18.50%；SEMANTICS 0.046/0.53%；SurfaceFrame::Encode 2.488/28.79%；SurfaceFrame::Submit 4.194/48.54% |
| 1794336808482013/21 | Animate 0.436/4.55%；COMPOSITING 1.469/15.34%；CreateGlyphAtlas 0.015/0.16%；LAYOUT 0.009/0.09%；LayerTree::Paint 0.038/0.40%；PAINT 2.049/21.40%；Rasterizer::DoDraw 4.717/49.26%；Rasterizer::DrawToSurfaces 4.702/49.11%；RenderPassGLES::EncodeCommandsInReactor 1.670/17.44%；SEMANTICS 0.051/0.53%；SurfaceFrame::Encode 2.505/26.16%；SurfaceFrame::Submit 4.417/46.13% |
| 1794336808482013/91 | Animate 0.575/5.97%；COMPOSITING 0.605/6.28%；CreateGlyphAtlas 0.015/0.16%；LAYOUT 0.009/0.09%；LayerTree::Paint 0.039/0.40%；PAINT 2.309/23.96%；Rasterizer::DoDraw 4.774/49.54%；Rasterizer::DrawToSurfaces 4.761/49.40%；RenderPassGLES::EncodeCommandsInReactor 1.767/18.34%；SEMANTICS 0.050/0.52%；SurfaceFrame::Encode 2.625/27.24%；SurfaceFrame::Submit 4.477/46.46% |
| 1794336808482013/95 | Animate 0.391/4.30%；COMPOSITING 0.559/6.14%；CreateGlyphAtlas 0.018/0.20%；LAYOUT 0.007/0.08%；LayerTree::Paint 0.043/0.47%；PAINT 2.708/29.75%；Rasterizer::DoDraw 5.070/55.71%；Rasterizer::DrawToSurfaces 5.053/55.52%；RenderPassGLES::EncodeCommandsInReactor 1.952/21.45%；SEMANTICS 0.042/0.46%；SurfaceFrame::Encode 2.863/31.46%；SurfaceFrame::Submit 4.756/52.26% |
| 1794336808482013/123 | Animate 0.640/5.87%；COMPOSITING 0.557/5.11%；CreateGlyphAtlas 0.018/0.17%；LAYOUT 0.012/0.11%；LayerTree::Paint 0.050/0.46%；PAINT 1.979/18.16%；Rasterizer::DoDraw 5.192/47.65%；Rasterizer::DrawToSurfaces 5.175/47.49%；RenderPassGLES::EncodeCommandsInReactor 1.830/16.79%；SEMANTICS 0.065/0.60%；SurfaceFrame::Encode 2.743/25.17%；SurfaceFrame::Submit 4.732/43.42% |
| 1794336808482013/241 | Animate 0.387/3.74%；COMPOSITING 0.736/7.11%；CreateGlyphAtlas 0.018/0.17%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.043/0.42%；PAINT 2.730/26.37%；Rasterizer::DoDraw 5.120/49.45%；Rasterizer::DrawToSurfaces 5.104/49.30%；RenderPassGLES::EncodeCommandsInReactor 1.848/17.85%；SEMANTICS 1.016/9.81%；SurfaceFrame::Encode 2.748/26.54%；SurfaceFrame::Submit 4.797/46.33% |
| 1794336808482013/247 | Animate 0.395/4.23%；COMPOSITING 0.834/8.92%；CreateGlyphAtlas 0.017/0.18%；LAYOUT 0.009/0.10%；LayerTree::Paint 0.039/0.42%；PAINT 2.540/27.18%；Rasterizer::DoDraw 5.108/54.65%；Rasterizer::DrawToSurfaces 5.094/54.50%；RenderPassGLES::EncodeCommandsInReactor 1.731/18.52%；SEMANTICS 0.045/0.48%；SurfaceFrame::Encode 2.851/30.51%；SurfaceFrame::Submit 4.803/51.39% |
| 1794336808482013/264 | Animate 0.385/4.05%；COMPOSITING 0.666/7.00%；CreateGlyphAtlas 0.018/0.19%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.041/0.43%；PAINT 2.259/23.74%；Rasterizer::DoDraw 5.097/53.56%；Rasterizer::DrawToSurfaces 5.082/53.40%；RenderPassGLES::EncodeCommandsInReactor 1.982/20.83%；SEMANTICS 0.764/8.03%；SurfaceFrame::Encode 2.871/30.17%；SurfaceFrame::Submit 4.770/50.13% |

#### lots_shaking

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| 1794336934144721/216/1057 | 3583.270 | 4.058/3.486/7.544 | 0.649/15.99% | luckdraw.lots.paint 0.649 |
| 1794336996368281/143/984 | 2366.614 | 5.089/3.294/8.383 | 0.474/9.31% | luckdraw.lots.paint 0.474 |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |
| Animate | 0.401 / 0.201 / 2.52% | 129.660 / 0.146 / 3.27% |
| COMPOSITING | 4.597 / 2.299 / 28.86% | 312.920 / 0.351 / 7.88% |
| LAYOUT | 0.014 / 0.007 / 0.09% | 4.880 / 0.005 / 0.12% |
| LayerTree::Paint | 0.080 / 0.040 / 0.50% | 33.653 / 0.038 / 0.85% |
| PAINT | 1.933 / 0.967 / 12.14% | 533.087 / 0.598 / 13.43% |
| Rasterizer::DoDraw | 6.729 / 3.365 / 42.25% | 2736.861 / 3.072 / 68.96% |
| Rasterizer::DrawToSurfaces | 6.670 / 3.335 / 41.88% | 2720.356 / 3.053 / 68.54% |
| RenderPassGLES::EncodeCommandsInReactor | 1.351 / 0.675 / 8.48% | 574.123 / 0.644 / 14.47% |
| SEMANTICS | 1.160 / 0.580 / 7.28% | 30.134 / 0.034 / 0.76% |
| SurfaceFrame::Encode | 2.149 / 1.075 / 13.49% | 869.226 / 0.976 / 21.90% |
| SurfaceFrame::Submit | 6.084 / 3.042 / 38.20% | 2475.644 / 2.779 / 62.37% |
| luckdraw.lots.paint | 1.123 / 0.561 / 7.05% | 331.865 / 0.372 / 8.36% |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |
| 1794336934144721/216 | Animate 0.222/2.94%；COMPOSITING 0.677/8.97%；LAYOUT 0.008/0.11%；LayerTree::Paint 0.040/0.53%；PAINT 1.244/16.49%；Rasterizer::DoDraw 3.461/45.88%；Rasterizer::DrawToSurfaces 3.446/45.68%；RenderPassGLES::EncodeCommandsInReactor 0.673/8.92%；SEMANTICS 1.116/14.79%；SurfaceFrame::Encode 1.016/13.47%；SurfaceFrame::Submit 3.153/41.79% |
| 1794336996368281/143 | Animate 0.179/2.14%；COMPOSITING 3.920/46.76%；LAYOUT 0.006/0.07%；LayerTree::Paint 0.040/0.48%；PAINT 0.689/8.22%；Rasterizer::DoDraw 3.268/38.98%；Rasterizer::DrawToSurfaces 3.224/38.46%；RenderPassGLES::EncodeCommandsInReactor 0.678/8.09%；SEMANTICS 0.044/0.52%；SurfaceFrame::Encode 1.133/13.52%；SurfaceFrame::Submit 2.931/34.96% |

#### slot 入场 atlas 调用（稳态前独立窗口）

| 来源 | UI帧/引擎帧号 | atlas ms | UI帧ms | UI线程 |
| --- | --- | --- | --- | --- |
| tool/bench/results/steady/slot_raster_1/slot_raster_entry_reference_1794335894537151.timeline.json.gz | 1/802 | 0.388 | 6.436 | True |
| tool/bench/results/steady/slot_raster_1/slot_raster_entry_reference_1794335894537151.timeline.json.gz | 2/803 | 0.297 | 1.762 | True |
| tool/bench/results/steady/slot_raster_1/slot_raster_entry_reference_1794335894537151.timeline.json.gz | 3/804 | 0.281 | 2.178 | True |
| tool/bench/results/steady/slot_raster_2/slot_raster_entry_reference_1794335965641572.timeline.json.gz | 1/797 | 0.285 | 6.965 | True |
| tool/bench/results/steady/slot_raster_2/slot_raster_entry_reference_1794335965641572.timeline.json.gz | 2/798 | 0.351 | 2.585 | True |
| tool/bench/results/steady/slot_raster_2/slot_raster_entry_reference_1794335965641572.timeline.json.gz | 3/799 | 0.193 | 1.19 | True |
| tool/bench/results/steady/slot_raster_2/slot_raster_entry_reference_1794335965641572.timeline.json.gz | 4/800 | 0.224 | 1.772 | True |
| tool/bench/results/steady/slot_raster_3/slot_raster_entry_reference_1794336036358822.timeline.json.gz | 1/799 | 0.473 | 8.794 | True |
| tool/bench/results/steady/slot_raster_3/slot_raster_entry_reference_1794336036358822.timeline.json.gz | 2/800 | 0.334 | 2.313 | True |
| tool/bench/results/steady/slot_raster_3/slot_raster_entry_reference_1794336036358822.timeline.json.gz | 3/801 | 0.289 | 1.974 | True |
| tool/bench/results/steady/slot_raster_3/slot_raster_entry_reference_1794336036358822.timeline.json.gz | 4/802 | 0.309 | 2.342 | True |

#### GC（含 UI 帧外事件）

| 场景/run_id | 事件/线程 | 位置ms/耗时ms | 与UI帧重叠序号 |
| --- | --- | --- | --- |
| slot_raster/1794335894537151 | CollectNewGeneration/511453528208 | 4067.932/2.003 | [] |
| slot_raster/1794335894537151 | Scavenge/511453528208 | 4068.273/1.464 | [] |
| slot_raster/1794335894537151 | Scavenge/496977830784 | 4068.507/1.226 | [] |
| slot_raster/1794335965641572 | CollectNewGeneration/511453528208 | 3402.787/3.365 | [] |
| slot_raster/1794335965641572 | Scavenge/511453528208 | 3403.489/2.271 | [] |
| slot_raster/1794335965641572 | Scavenge/496963916672 | 3404.103/1.662 | [] |
| slot_raster/1794336036358822 | CollectNewGeneration/511453528208 | 1885.545/3.324 | [] |
| slot_raster/1794336036358822 | Scavenge/511453528208 | 1885.969/2.583 | [] |
| slot_raster/1794336036358822 | Scavenge/496901677952 | 1886.340/2.211 | [] |
| grid_steady/1794336102072654 | CollectNewGeneration/511453528208 | 822.922/5.250 | [] |
| grid_steady/1794336102072654 | Scavenge/511453528208 | 823.917/2.531 | [] |
| grid_steady/1794336102072654 | Scavenge/497023882112 | 824.225/3.531 | [] |
| lotto_draw/1794336740704716 | CollectNewGeneration/511453528208 | 906.023/2.603 | [] |
| lotto_draw/1794336740704716 | Scavenge/511453528208 | 906.256/1.938 | [] |
| lotto_draw/1794336740704716 | Scavenge/496945136512 | 906.391/1.785 | [] |
| lotto_draw/1794336808482013 | CollectNewGeneration/511453528208 | 1371.854/3.460 | [] |
| lotto_draw/1794336808482013 | Scavenge/511453528208 | 1372.127/2.688 | [] |
| lotto_draw/1794336808482013 | Scavenge/496973702016 | 1372.534/1.921 | [] |
| lots_shaking/1794336996368281 | CollectNewGeneration/511453528208 | 4401.511/4.209 | [] |
| lots_shaking/1794336996368281 | Scavenge/511453528208 | 4402.283/2.967 | [] |
| lots_shaking/1794336996368281 | Scavenge/496918877056 | 4402.601/2.742 | [] |
