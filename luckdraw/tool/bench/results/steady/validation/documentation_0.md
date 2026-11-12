

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
