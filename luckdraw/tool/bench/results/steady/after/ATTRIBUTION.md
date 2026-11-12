# STEADY 带打点逐帧证据

按引擎 frame_number 配对并逐项校验 SDK 时长数组；仅未污染窗口参与归因。
尖峰为 trace 同帧 UI+Raster>12ms 或 UI>4ms，硬门禁另用 FrameTiming P99。
包含耗时/占比可嵌套，不能相加；墙钟不能直接当 CPU。普通帧包含零次该事件的帧。

| 场景/run_id | 帧数 | 尖峰/首5帧 | 每秒尖峰桶 |
| --- | --- | --- | --- |
| lotto_draw/1794337270240589 | 270 | 16/0 | {0: 4, 2: 7, 3: 4, 4: 1} |
| lotto_draw/1794337338194759 | 269 | 24/2 | {0: 9, 1: 2, 2: 7, 3: 3, 4: 3} |
| lotto_draw/1794337406032735 | 269 | 7/0 | {0: 1, 2: 3, 3: 3} |

| 场景/run_id | UI/Raster均值ms | paint均值ms | Encode/Submit均值ms | layout/record/text事件次数 |
| --- | --- | --- | --- | --- |
| lotto_draw/1794337270240589 | 2.581/4.798 | 1.182 | 2.645/4.453 | [0, 0, 0] |
| lotto_draw/1794337338194759 | 2.645/4.708 | 1.206 | 2.552/4.359 | [0, 0, 0] |
| lotto_draw/1794337406032735 | 1.777/5.056 | 0.762 | 2.955/4.722 | [0, 0, 0] |

## slot_raster

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| — | 无尖峰 | — | — | — |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |

## grid_steady

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| — | 无尖峰 | — | — | — |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |

## lotto_draw

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| 1794337270240589/37/1195 | 600.716 | 4.433/4.716/9.149 | 2.291/51.68% | luckdraw.lotto.paint 2.291 |
| 1794337270240589/39/1197 | 634.564 | 4.166/4.868/9.034 | 1.816/43.59% | luckdraw.lotto.paint 1.816 |
| 1794337270240589/40/1198 | 651.327 | 4.204/4.742/8.946 | 1.941/46.17% | luckdraw.lotto.paint 1.941 |
| 1794337270240589/53/1211 | 867.354 | 4.380/4.827/9.207 | 2.059/47.01% | luckdraw.lotto.paint 2.059 |
| 1794337270240589/136/1294 | 2250.665 | 4.173/4.751/8.924 | 1.710/40.98% | luckdraw.lotto.paint 1.710 |
| 1794337270240589/145/1303 | 2401.154 | 4.015/4.950/8.965 | 1.474/36.71% | luckdraw.lotto.paint 1.474 |
| 1794337270240589/153/1311 | 2534.753 | 4.567/4.661/9.228 | 2.420/52.99% | luckdraw.lotto.paint 2.420 |
| 1794337270240589/161/1319 | 2667.893 | 4.267/4.666/8.933 | 1.862/43.64% | luckdraw.lotto.paint 1.862 |
| 1794337270240589/165/1323 | 2734.458 | 4.181/4.765/8.946 | 1.487/35.57% | luckdraw.lotto.paint 1.487 |
| 1794337270240589/171/1329 | 2834.818 | 4.476/4.752/9.228 | 2.590/57.86% | luckdraw.lotto.paint 2.590 |
| 1794337270240589/173/1331 | 2868.109 | 4.566/4.832/9.398 | 2.278/49.89% | luckdraw.lotto.paint 2.278 |
| 1794337270240589/185/1343 | 3067.544 | 4.076/4.841/8.917 | 2.476/60.75% | luckdraw.lotto.paint 2.476 |
| 1794337270240589/234/1392 | 3884.594 | 4.373/4.874/9.247 | 1.816/41.53% | luckdraw.lotto.paint 1.816 |
| 1794337270240589/237/1395 | 3934.098 | 4.704/4.918/9.622 | 1.441/30.63% | luckdraw.lotto.paint 1.441 |
| 1794337270240589/239/1397 | 3967.310 | 2.832/12.949/15.781 | 1.267/44.74% | luckdraw.lotto.paint 1.267 |
| 1794337270240589/269/1427 | 4467.455 | 5.184/7.257/12.441 | 1.966/37.92% | luckdraw.lotto.paint 1.966 |
| 1794337338194759/1/1161 | 0.000 | 4.142/5.421/9.563 | 1.710/41.28% | luckdraw.lotto.paint 1.710 |
| 1794337338194759/3/1163 | 33.630 | 4.244/5.228/9.472 | 2.425/57.14% | luckdraw.lotto.paint 2.425 |
| 1794337338194759/8/1168 | 116.650 | 4.671/5.102/9.773 | 1.587/33.98% | luckdraw.lotto.paint 1.587 |
| 1794337338194759/20/1180 | 317.120 | 4.459/4.925/9.384 | 1.568/35.16% | luckdraw.lotto.paint 1.568 |
| 1794337338194759/22/1182 | 350.124 | 4.120/5.329/9.449 | 2.552/61.94% | luckdraw.lotto.paint 2.552 |
| 1794337338194759/33/1193 | 533.645 | 4.601/5.425/10.026 | 1.638/35.60% | luckdraw.lotto.paint 1.638 |
| 1794337338194759/36/1196 | 583.234 | 4.152/5.346/9.498 | 2.091/50.36% | luckdraw.lotto.paint 2.091 |
| 1794337338194759/37/1197 | 600.056 | 5.548/5.171/10.719 | 1.347/24.28% | luckdraw.lotto.paint 1.347 |
| 1794337338194759/38/1198 | 616.539 | 5.123/5.128/10.251 | 1.601/31.25% | luckdraw.lotto.paint 1.601 |
| 1794337338194759/114/1274 | 1883.684 | 4.115/5.077/9.192 | 2.268/55.12% | luckdraw.lotto.paint 2.268 |
| 1794337338194759/119/1279 | 1966.383 | 4.910/4.807/9.717 | 1.215/24.75% | luckdraw.lotto.paint 1.215 |
| 1794337338194759/125/1285 | 2066.979 | 6.248/4.935/11.183 | 3.847/61.57% | luckdraw.lotto.paint 3.847 |
| 1794337338194759/139/1299 | 2300.914 | 4.241/4.826/9.067 | 1.892/44.61% | luckdraw.lotto.paint 1.892 |
| 1794337338194759/147/1307 | 2433.482 | 4.109/5.146/9.255 | 1.659/40.37% | luckdraw.lotto.paint 1.659 |
| 1794337338194759/148/1308 | 2450.468 | 4.703/4.889/9.592 | 3.154/67.06% | luckdraw.lotto.paint 3.154 |
| 1794337338194759/149/1309 | 2466.803 | 4.579/5.481/10.060 | 1.936/42.28% | luckdraw.lotto.paint 1.936 |
| 1794337338194759/152/1312 | 2516.902 | 4.462/4.902/9.364 | 2.212/49.57% | luckdraw.lotto.paint 2.212 |
| 1794337338194759/168/1328 | 2783.197 | 4.058/5.558/9.616 | 1.724/42.48% | luckdraw.lotto.paint 1.724 |
| 1794337338194759/230/1390 | 3816.940 | 4.118/5.219/9.337 | 1.489/36.16% | luckdraw.lotto.paint 1.489 |
| 1794337338194759/231/1391 | 3833.393 | 4.610/5.243/9.853 | 2.098/45.51% | luckdraw.lotto.paint 2.098 |
| 1794337338194759/239/1399 | 3967.045 | 4.799/5.657/10.456 | 2.434/50.72% | luckdraw.lotto.paint 2.434 |
| 1794337338194759/243/1403 | 4033.466 | 4.054/5.048/9.102 | 1.479/36.48% | luckdraw.lotto.paint 1.479 |
| 1794337338194759/247/1407 | 4100.941 | 4.483/5.032/9.515 | 1.471/32.81% | luckdraw.lotto.paint 1.471 |
| 1794337338194759/257/1417 | 4266.737 | 4.138/5.005/9.143 | 2.282/55.15% | luckdraw.lotto.paint 2.282 |
| 1794337406032735/26/1185 | 417.317 | 4.851/4.623/9.474 | 3.564/73.47% | luckdraw.lotto.paint 3.564 |
| 1794337406032735/131/1290 | 2167.304 | 6.905/4.796/11.701 | 1.409/20.41% | luckdraw.lotto.paint 1.409 |
| 1794337406032735/137/1296 | 2267.673 | 4.064/6.413/10.477 | 1.497/36.84% | luckdraw.lotto.paint 1.497 |
| 1794337406032735/140/1299 | 2317.325 | 4.499/4.839/9.338 | 1.727/38.39% | luckdraw.lotto.paint 1.727 |
| 1794337406032735/212/1371 | 3517.347 | 4.642/5.527/10.169 | 2.183/47.03% | luckdraw.lotto.paint 2.183 |
| 1794337406032735/219/1378 | 3634.199 | 5.216/6.566/11.782 | 1.492/28.60% | luckdraw.lotto.paint 1.492 |
| 1794337406032735/236/1395 | 3916.681 | 1.459/10.699/12.158 | 0.574/39.34% | luckdraw.lotto.paint 0.574 |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |
| Animate | 23.452 / 0.499 / 5.06% | 221.706 / 0.291 / 4.15% |
| BUILD | 0.245 / 0.005 / 0.05% | 0.294 / 0.000 / 0.01% |
| COMPOSITING | 39.512 / 0.841 / 8.52% | 284.276 / 0.374 / 5.32% |
| CreateGlyphAtlas | 1.745 / 0.037 / 0.38% | 13.676 / 0.018 / 0.26% |
| Dart_InvokeClosure | 0.028 / 0.001 / 0.01% | 0.035 / 0.000 / 0.00% |
| LAYOUT | 1.060 / 0.023 / 0.23% | 5.571 / 0.007 / 0.10% |
| LayerTree::Paint | 1.935 / 0.041 / 0.42% | 30.478 / 0.040 / 0.57% |
| PAINT | 110.672 / 2.355 / 23.87% | 941.947 / 1.238 / 17.62% |
| Rasterizer::DoDraw | 253.107 / 5.385 / 54.59% | 3647.040 / 4.792 / 68.21% |
| Rasterizer::DrawToSurfaces | 251.941 / 5.360 / 54.34% | 3631.928 / 4.773 / 67.92% |
| RenderPassGLES::EncodeCommandsInReactor | 102.350 / 2.178 / 22.07% | 1399.572 / 1.839 / 26.17% |
| SEMANTICS | 6.551 / 0.139 / 1.41% | 29.766 / 0.039 / 0.56% |
| SurfaceFrame::Encode | 146.549 / 3.118 / 31.61% | 2048.959 / 2.692 / 38.32% |
| SurfaceFrame::Submit | 237.314 / 5.049 / 51.18% | 3408.004 / 4.478 / 63.73% |
| luckdraw.lotto.paint | 91.019 / 1.937 / 19.63% | 757.434 / 0.995 / 14.17% |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |
| 1794337270240589/37 | Animate 0.396/4.33%；COMPOSITING 0.591/6.46%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.009/0.10%；LayerTree::Paint 0.039/0.43%；PAINT 2.720/29.73%；Rasterizer::DoDraw 4.697/51.34%；Rasterizer::DrawToSurfaces 4.681/51.16%；RenderPassGLES::EncodeCommandsInReactor 1.738/19.00%；SEMANTICS 0.042/0.46%；SurfaceFrame::Encode 2.560/27.98%；SurfaceFrame::Submit 4.409/48.19% |
| 1794337270240589/39 | Animate 0.987/10.93%；COMPOSITING 0.458/5.07%；CreateGlyphAtlas 0.015/0.17%；LAYOUT 0.010/0.11%；LayerTree::Paint 0.037/0.41%；PAINT 2.129/23.57%；Rasterizer::DoDraw 4.847/53.65%；Rasterizer::DrawToSurfaces 4.834/53.51%；RenderPassGLES::EncodeCommandsInReactor 1.799/19.91%；SEMANTICS 0.180/1.99%；SurfaceFrame::Encode 2.757/30.52%；SurfaceFrame::Submit 4.574/50.63% |
| 1794337270240589/40 | Animate 0.509/5.69%；COMPOSITING 0.979/10.94%；CreateGlyphAtlas 0.014/0.16%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.036/0.40%；PAINT 2.259/25.25%；Rasterizer::DoDraw 4.722/52.78%；Rasterizer::DrawToSurfaces 4.709/52.64%；RenderPassGLES::EncodeCommandsInReactor 1.797/20.09%；SEMANTICS 0.146/1.63%；SurfaceFrame::Encode 2.663/29.77%；SurfaceFrame::Submit 4.440/49.63% |
| 1794337270240589/53 | Animate 0.513/5.57%；COMPOSITING 0.466/5.06%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.035/0.38%；PAINT 2.372/25.76%；Rasterizer::DoDraw 4.709/51.15%；Rasterizer::DrawToSurfaces 4.695/50.99%；RenderPassGLES::EncodeCommandsInReactor 1.792/19.46%；SEMANTICS 0.102/1.11%；SurfaceFrame::Encode 2.619/28.45%；SurfaceFrame::Submit 4.426/48.07% |
| 1794337270240589/136 | Animate 0.530/5.94%；COMPOSITING 0.415/4.65%；CreateGlyphAtlas 0.013/0.15%；LAYOUT 0.007/0.08%；LayerTree::Paint 0.040/0.45%；PAINT 2.337/26.19%；Rasterizer::DoDraw 4.729/52.99%；Rasterizer::DrawToSurfaces 4.714/52.82%；RenderPassGLES::EncodeCommandsInReactor 1.804/20.22%；SEMANTICS 0.270/3.03%；SurfaceFrame::Encode 2.634/29.52%；SurfaceFrame::Submit 4.434/49.69% |
| 1794337270240589/145 | Animate 0.702/7.83%；COMPOSITING 0.467/5.21%；CreateGlyphAtlas 0.013/0.15%；LAYOUT 0.011/0.12%；LayerTree::Paint 0.045/0.50%；PAINT 1.889/21.07%；Rasterizer::DoDraw 4.928/54.97%；Rasterizer::DrawToSurfaces 4.877/54.40%；RenderPassGLES::EncodeCommandsInReactor 1.690/18.85%；SEMANTICS 0.223/2.49%；SurfaceFrame::Encode 2.528/28.20%；SurfaceFrame::Submit 4.469/49.85% |
| 1794337270240589/153 | Animate 0.405/4.39%；COMPOSITING 0.915/9.92%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.039/0.42%；PAINT 2.730/29.58%；Rasterizer::DoDraw 4.640/50.28%；Rasterizer::DrawToSurfaces 4.625/50.12%；RenderPassGLES::EncodeCommandsInReactor 1.705/18.48%；SEMANTICS 0.119/1.29%；SurfaceFrame::Encode 2.539/27.51%；SurfaceFrame::Submit 4.348/47.12% |
| 1794337270240589/161 | Animate 0.839/9.39%；COMPOSITING 0.701/7.85%；CreateGlyphAtlas 0.016/0.18%；LAYOUT 0.012/0.13%；LayerTree::Paint 0.036/0.40%；PAINT 2.185/24.46%；Rasterizer::DoDraw 4.646/52.01%；Rasterizer::DrawToSurfaces 4.631/51.84%；RenderPassGLES::EncodeCommandsInReactor 1.663/18.62%；SEMANTICS 0.043/0.48%；SurfaceFrame::Encode 2.576/28.84%；SurfaceFrame::Submit 4.364/48.85% |
| 1794337270240589/165 | Animate 0.408/4.56%；COMPOSITING 0.775/8.66%；CreateGlyphAtlas 0.014/0.16%；LAYOUT 0.007/0.08%；LayerTree::Paint 0.039/0.44%；PAINT 2.641/29.52%；Rasterizer::DoDraw 4.744/53.03%；Rasterizer::DrawToSurfaces 4.730/52.87%；RenderPassGLES::EncodeCommandsInReactor 1.801/20.13%；SEMANTICS 0.043/0.48%；SurfaceFrame::Encode 2.632/29.42%；SurfaceFrame::Submit 4.451/49.75% |
| 1794337270240589/171 | Animate 0.400/4.33%；COMPOSITING 0.595/6.45%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.095/1.03%；LayerTree::Paint 0.038/0.41%；PAINT 3.038/32.92%；Rasterizer::DoDraw 4.733/51.29%；Rasterizer::DrawToSurfaces 4.718/51.13%；RenderPassGLES::EncodeCommandsInReactor 1.775/19.23%；SEMANTICS 0.043/0.47%；SurfaceFrame::Encode 2.596/28.13%；SurfaceFrame::Submit 4.420/47.90% |
| 1794337270240589/173 | Animate 0.404/4.30%；COMPOSITING 0.595/6.33%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.009/0.10%；LayerTree::Paint 0.037/0.39%；PAINT 2.598/27.64%；Rasterizer::DoDraw 4.811/51.19%；Rasterizer::DrawToSurfaces 4.798/51.05%；RenderPassGLES::EncodeCommandsInReactor 1.673/17.80%；SEMANTICS 0.114/1.21%；SurfaceFrame::Encode 2.571/27.36%；SurfaceFrame::Submit 4.456/47.41% |
| 1794337270240589/185 | Animate 0.396/4.44%；COMPOSITING 0.546/6.12%；CreateGlyphAtlas 0.014/0.16%；LAYOUT 0.009/0.10%；LayerTree::Paint 0.038/0.43%；PAINT 2.783/31.21%；Rasterizer::DoDraw 4.816/54.01%；Rasterizer::DrawToSurfaces 4.691/52.61%；RenderPassGLES::EncodeCommandsInReactor 1.751/19.64%；SEMANTICS 0.045/0.50%；SurfaceFrame::Encode 2.606/29.23%；SurfaceFrame::Submit 4.423/49.60% |
| 1794337270240589/234 | Animate 0.518/5.60%；COMPOSITING 0.827/8.94%；CreateGlyphAtlas 0.013/0.14%；LAYOUT 0.007/0.08%；LayerTree::Paint 0.038/0.41%；PAINT 2.146/23.21%；Rasterizer::DoDraw 4.853/52.48%；Rasterizer::DrawToSurfaces 4.838/52.32%；RenderPassGLES::EncodeCommandsInReactor 1.677/18.14%；SEMANTICS 0.043/0.47%；SurfaceFrame::Encode 2.504/27.08%；SurfaceFrame::Submit 4.474/48.38% |
| 1794337270240589/237 | Animate 0.461/4.79%；COMPOSITING 1.247/12.96%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.365/3.79%；LayerTree::Paint 0.040/0.42%；PAINT 1.792/18.62%；Rasterizer::DoDraw 4.896/50.88%；Rasterizer::DrawToSurfaces 4.883/50.75%；RenderPassGLES::EncodeCommandsInReactor 1.948/20.25%；SEMANTICS 0.046/0.48%；SurfaceFrame::Encode 2.774/28.83%；SurfaceFrame::Submit 4.605/47.86% |
| 1794337270240589/239 | Animate 0.348/2.21%；COMPOSITING 0.471/2.98%；CreateGlyphAtlas 0.015/0.10%；LAYOUT 0.008/0.05%；LayerTree::Paint 0.039/0.25%；PAINT 1.530/9.70%；Rasterizer::DoDraw 12.929/81.93%；Rasterizer::DrawToSurfaces 12.878/81.60%；RenderPassGLES::EncodeCommandsInReactor 10.005/63.40%；SEMANTICS 0.103/0.65%；SurfaceFrame::Encode 10.840/68.69%；SurfaceFrame::Submit 12.598/79.83% |
| 1794337270240589/269 | Animate 0.677/5.44%；BUILD 0.245/1.97%；COMPOSITING 0.957/7.69%；CreateGlyphAtlas 0.997/8.01%；Dart_InvokeClosure 0.028/0.23%；LAYOUT 0.243/1.95%；LayerTree::Paint 0.039/0.31%；PAINT 2.288/18.39%；Rasterizer::DoDraw 7.195/57.83%；Rasterizer::DrawToSurfaces 7.178/57.70%；RenderPassGLES::EncodeCommandsInReactor 2.561/20.59%；SEMANTICS 0.553/4.44%；SurfaceFrame::Encode 5.050/40.59%；SurfaceFrame::Submit 6.830/54.90% |
| 1794337338194759/1 | Animate 0.398/4.16%；COMPOSITING 0.456/4.77%；CreateGlyphAtlas 0.018/0.19%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.040/0.42%；PAINT 2.139/22.37%；Rasterizer::DoDraw 5.396/56.43%；Rasterizer::DrawToSurfaces 5.357/56.02%；RenderPassGLES::EncodeCommandsInReactor 1.855/19.40%；SEMANTICS 0.143/1.50%；SurfaceFrame::Encode 2.942/30.76%；SurfaceFrame::Submit 5.061/52.92% |
| 1794337338194759/3 | Animate 0.600/6.33%；COMPOSITING 0.558/5.89%；CreateGlyphAtlas 0.016/0.17%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.044/0.46%；PAINT 2.729/28.81%；Rasterizer::DoDraw 5.206/54.96%；Rasterizer::DrawToSurfaces 5.191/54.80%；RenderPassGLES::EncodeCommandsInReactor 2.117/22.35%；SEMANTICS 0.044/0.46%；SurfaceFrame::Encode 3.013/31.81%；SurfaceFrame::Submit 4.884/51.56% |
| 1794337338194759/8 | Animate 0.400/4.09%；COMPOSITING 1.198/12.26%；CreateGlyphAtlas 0.017/0.17%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.046/0.47%；PAINT 1.881/19.25%；Rasterizer::DoDraw 5.078/51.96%；Rasterizer::DrawToSurfaces 5.031/51.48%；RenderPassGLES::EncodeCommandsInReactor 1.753/17.94%；SEMANTICS 0.052/0.53%；SurfaceFrame::Encode 2.636/26.97%；SurfaceFrame::Submit 4.638/47.46% |
| 1794337338194759/20 | Animate 0.518/5.52%；COMPOSITING 0.484/5.16%；CreateGlyphAtlas 0.015/0.16%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.041/0.44%；PAINT 1.877/20.00%；Rasterizer::DoDraw 4.899/52.21%；Rasterizer::DrawToSurfaces 4.883/52.04%；RenderPassGLES::EncodeCommandsInReactor 1.742/18.56%；SEMANTICS 0.679/7.24%；SurfaceFrame::Encode 2.638/28.11%；SurfaceFrame::Submit 4.577/48.77% |
| 1794337338194759/22 | Animate 0.399/4.22%；COMPOSITING 0.429/4.54%；CreateGlyphAtlas 0.017/0.18%；LAYOUT 0.014/0.15%；LayerTree::Paint 0.042/0.44%；PAINT 2.953/31.25%；Rasterizer::DoDraw 5.305/56.14%；Rasterizer::DrawToSurfaces 5.222/55.27%；RenderPassGLES::EncodeCommandsInReactor 2.083/22.04%；SEMANTICS 0.038/0.40%；SurfaceFrame::Encode 2.975/31.48%；SurfaceFrame::Submit 4.918/52.05% |
| 1794337338194759/33 | Animate 0.400/3.99%；COMPOSITING 1.887/18.82%；CreateGlyphAtlas 0.016/0.16%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.047/0.47%；PAINT 1.940/19.35%；Rasterizer::DoDraw 5.399/53.85%；Rasterizer::DrawToSurfaces 5.384/53.70%；RenderPassGLES::EncodeCommandsInReactor 1.992/19.87%；SEMANTICS 0.044/0.44%；SurfaceFrame::Encode 2.862/28.55%；SurfaceFrame::Submit 5.010/49.97% |
| 1794337338194759/36 | Animate 0.470/4.95%；COMPOSITING 0.754/7.94%；CreateGlyphAtlas 0.016/0.17%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.045/0.47%；PAINT 2.383/25.09%；Rasterizer::DoDraw 5.320/56.01%；Rasterizer::DrawToSurfaces 5.271/55.50%；RenderPassGLES::EncodeCommandsInReactor 1.883/19.83%；SEMANTICS 0.043/0.45%；SurfaceFrame::Encode 2.896/30.49%；SurfaceFrame::Submit 4.944/52.05% |
| 1794337338194759/37 | Animate 0.449/4.19%；COMPOSITING 1.683/15.70%；CreateGlyphAtlas 0.017/0.16%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.044/0.41%；PAINT 1.927/17.98%；Rasterizer::DoDraw 5.145/48.00%；Rasterizer::DrawToSurfaces 5.128/47.84%；RenderPassGLES::EncodeCommandsInReactor 1.882/17.56%；SEMANTICS 1.146/10.69%；SurfaceFrame::Encode 2.780/25.94%；SurfaceFrame::Submit 4.810/44.87% |
| 1794337338194759/38 | Animate 0.546/5.33%；COMPOSITING 0.681/6.64%；CreateGlyphAtlas 0.014/0.14%；LAYOUT 0.011/0.11%；LayerTree::Paint 0.044/0.43%；PAINT 3.013/29.39%；Rasterizer::DoDraw 5.103/49.78%；Rasterizer::DrawToSurfaces 5.089/49.64%；RenderPassGLES::EncodeCommandsInReactor 1.818/17.73%；SEMANTICS 0.129/1.26%；SurfaceFrame::Encode 2.670/26.05%；SurfaceFrame::Submit 4.778/46.61% |
| 1794337338194759/114 | Animate 0.505/5.49%；COMPOSITING 0.476/5.18%；CreateGlyphAtlas 0.019/0.21%；LAYOUT 0.009/0.10%；LayerTree::Paint 0.042/0.46%；PAINT 2.582/28.09%；Rasterizer::DoDraw 5.054/54.98%；Rasterizer::DrawToSurfaces 5.040/54.83%；RenderPassGLES::EncodeCommandsInReactor 1.749/19.03%；SEMANTICS 0.241/2.62%；SurfaceFrame::Encode 2.782/30.27%；SurfaceFrame::Submit 4.733/51.49% |
| 1794337338194759/119 | Animate 0.407/4.19%；COMPOSITING 2.646/27.23%；CreateGlyphAtlas 0.014/0.14%；LAYOUT 0.006/0.06%；LayerTree::Paint 0.042/0.43%；PAINT 1.472/15.15%；Rasterizer::DoDraw 4.779/49.18%；Rasterizer::DrawToSurfaces 4.763/49.02%；RenderPassGLES::EncodeCommandsInReactor 1.810/18.63%；SEMANTICS 0.038/0.39%；SurfaceFrame::Encode 2.649/27.26%；SurfaceFrame::Submit 4.475/46.05% |
| 1794337338194759/125 | Animate 0.386/3.45%；COMPOSITING 0.616/5.51%；CreateGlyphAtlas 0.014/0.13%；LAYOUT 0.008/0.07%；LayerTree::Paint 0.040/0.36%；PAINT 4.483/40.09%；Rasterizer::DoDraw 4.914/43.94%；Rasterizer::DrawToSurfaces 4.899/43.81%；RenderPassGLES::EncodeCommandsInReactor 1.725/15.43%；SEMANTICS 0.046/0.41%；SurfaceFrame::Encode 2.548/22.78%；SurfaceFrame::Submit 4.604/41.17% |
| 1794337338194759/139 | Animate 0.519/5.72%；COMPOSITING 0.959/10.58%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.007/0.08%；LayerTree::Paint 0.041/0.45%；PAINT 2.438/26.89%；Rasterizer::DoDraw 4.805/52.99%；Rasterizer::DrawToSurfaces 4.790/52.83%；RenderPassGLES::EncodeCommandsInReactor 1.719/18.96%；SEMANTICS 0.031/0.34%；SurfaceFrame::Encode 2.546/28.08%；SurfaceFrame::Submit 4.487/49.49% |
| 1794337338194759/147 | Animate 0.861/9.30%；COMPOSITING 0.776/8.38%；CreateGlyphAtlas 0.060/0.65%；LAYOUT 0.010/0.11%；LayerTree::Paint 0.042/0.45%；PAINT 2.071/22.38%；Rasterizer::DoDraw 5.124/55.36%；Rasterizer::DrawToSurfaces 5.110/55.21%；RenderPassGLES::EncodeCommandsInReactor 1.818/19.64%；SEMANTICS 0.044/0.48%；SurfaceFrame::Encode 2.735/29.55%；SurfaceFrame::Submit 4.790/51.76% |
| 1794337338194759/148 | Animate 0.462/4.82%；COMPOSITING 0.428/4.46%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.041/0.43%；PAINT 3.477/36.25%；Rasterizer::DoDraw 4.866/50.73%；Rasterizer::DrawToSurfaces 4.819/50.24%；RenderPassGLES::EncodeCommandsInReactor 1.748/18.22%；SEMANTICS 0.043/0.45%；SurfaceFrame::Encode 2.671/27.85%；SurfaceFrame::Submit 4.526/47.19% |
| 1794337338194759/149 | Animate 0.482/4.79%；COMPOSITING 1.474/14.65%；CreateGlyphAtlas 0.015/0.15%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.048/0.48%；PAINT 2.242/22.29%；Rasterizer::DoDraw 5.458/54.25%；Rasterizer::DrawToSurfaces 5.442/54.10%；RenderPassGLES::EncodeCommandsInReactor 1.753/17.43%；SEMANTICS 0.045/0.45%；SurfaceFrame::Encode 2.873/28.56%；SurfaceFrame::Submit 4.928/48.99% |
| 1794337338194759/152 | Animate 0.394/4.21%；COMPOSITING 0.476/5.08%；CreateGlyphAtlas 0.015/0.16%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.041/0.44%；PAINT 2.519/26.90%；Rasterizer::DoDraw 4.880/52.11%；Rasterizer::DrawToSurfaces 4.866/51.96%；RenderPassGLES::EncodeCommandsInReactor 1.749/18.68%；SEMANTICS 0.737/7.87%；SurfaceFrame::Encode 2.615/27.93%；SurfaceFrame::Submit 4.562/48.72% |
| 1794337338194759/168 | Animate 0.366/3.81%；COMPOSITING 0.582/6.05%；CreateGlyphAtlas 0.017/0.18%；LAYOUT 0.009/0.09%；LayerTree::Paint 0.043/0.45%；PAINT 2.090/21.73%；Rasterizer::DoDraw 5.534/57.55%；Rasterizer::DrawToSurfaces 5.517/57.37%；RenderPassGLES::EncodeCommandsInReactor 1.918/19.95%；SEMANTICS 0.145/1.51%；SurfaceFrame::Encode 2.807/29.19%；SurfaceFrame::Submit 5.140/53.45% |
| 1794337338194759/230 | Animate 0.569/6.09%；COMPOSITING 0.639/6.84%；CreateGlyphAtlas 0.017/0.18%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.044/0.47%；PAINT 2.460/26.35%；Rasterizer::DoDraw 5.196/55.65%；Rasterizer::DrawToSurfaces 5.180/55.48%；RenderPassGLES::EncodeCommandsInReactor 1.887/20.21%；SEMANTICS 0.043/0.46%；SurfaceFrame::Encode 2.787/29.85%；SurfaceFrame::Submit 4.876/52.22% |
| 1794337338194759/231 | Animate 0.468/4.75%；COMPOSITING 1.364/13.84%；CreateGlyphAtlas 0.015/0.15%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.044/0.45%；PAINT 2.411/24.47%；Rasterizer::DoDraw 5.220/52.98%；Rasterizer::DrawToSurfaces 5.205/52.83%；RenderPassGLES::EncodeCommandsInReactor 2.094/21.25%；SEMANTICS 0.043/0.44%；SurfaceFrame::Encode 2.989/30.34%；SurfaceFrame::Submit 4.905/49.78% |
| 1794337338194759/239 | Animate 0.391/3.74%；COMPOSITING 1.096/10.48%；CreateGlyphAtlas 0.016/0.15%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.044/0.42%；PAINT 2.753/26.33%；Rasterizer::DoDraw 5.503/52.63%；Rasterizer::DrawToSurfaces 5.456/52.18%；RenderPassGLES::EncodeCommandsInReactor 1.830/17.50%；SEMANTICS 0.217/2.08%；SurfaceFrame::Encode 2.797/26.75%；SurfaceFrame::Submit 5.129/49.05% |
| 1794337338194759/243 | Animate 0.387/4.25%；COMPOSITING 0.794/8.72%；CreateGlyphAtlas 0.015/0.16%；LAYOUT 0.010/0.11%；LayerTree::Paint 0.046/0.51%；PAINT 2.435/26.75%；Rasterizer::DoDraw 5.026/55.22%；Rasterizer::DrawToSurfaces 5.012/55.06%；RenderPassGLES::EncodeCommandsInReactor 1.971/21.65%；SEMANTICS 0.043/0.47%；SurfaceFrame::Encode 2.829/31.08%；SurfaceFrame::Submit 4.706/51.70% |
| 1794337338194759/247 | Animate 0.599/6.30%；COMPOSITING 1.658/17.43%；CreateGlyphAtlas 0.014/0.15%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.041/0.43%；PAINT 1.783/18.74%；Rasterizer::DoDraw 5.010/52.65%；Rasterizer::DrawToSurfaces 4.994/52.49%；RenderPassGLES::EncodeCommandsInReactor 1.721/18.09%；SEMANTICS 0.041/0.43%；SurfaceFrame::Encode 2.639/27.74%；SurfaceFrame::Submit 4.688/49.27% |
| 1794337338194759/257 | Animate 0.514/5.62%；COMPOSITING 0.477/5.22%；CreateGlyphAtlas 0.015/0.16%；LAYOUT 0.008/0.09%；LayerTree::Paint 0.043/0.47%；PAINT 2.606/28.50%；Rasterizer::DoDraw 4.983/54.50%；Rasterizer::DrawToSurfaces 4.969/54.35%；RenderPassGLES::EncodeCommandsInReactor 1.966/21.50%；SEMANTICS 0.046/0.50%；SurfaceFrame::Encode 2.819/30.83%；SurfaceFrame::Submit 4.661/50.98% |
| 1794337406032735/26 | Animate 0.348/3.67%；COMPOSITING 0.339/3.58%；CreateGlyphAtlas 0.013/0.14%；LAYOUT 0.006/0.06%；LayerTree::Paint 0.041/0.43%；PAINT 3.811/40.23%；Rasterizer::DoDraw 4.601/48.56%；Rasterizer::DrawToSurfaces 4.585/48.40%；RenderPassGLES::EncodeCommandsInReactor 1.620/17.10%；SEMANTICS 0.028/0.30%；SurfaceFrame::Encode 2.483/26.21%；SurfaceFrame::Submit 4.298/45.37% |
| 1794337406032735/131 | Animate 0.815/6.97%；COMPOSITING 2.113/18.06%；CreateGlyphAtlas 0.014/0.12%；LAYOUT 0.007/0.06%；LayerTree::Paint 0.041/0.35%；PAINT 1.699/14.52%；Rasterizer::DoDraw 4.771/40.77%；Rasterizer::DrawToSurfaces 4.758/40.66%；RenderPassGLES::EncodeCommandsInReactor 1.685/14.40%；SEMANTICS 0.077/0.66%；SurfaceFrame::Encode 2.698/23.06%；SurfaceFrame::Submit 4.469/38.19% |
| 1794337406032735/137 | Animate 0.409/3.90%；COMPOSITING 0.563/5.37%；CreateGlyphAtlas 0.018/0.17%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.042/0.40%；PAINT 1.796/17.14%；Rasterizer::DoDraw 6.255/59.70%；Rasterizer::DrawToSurfaces 6.236/59.52%；RenderPassGLES::EncodeCommandsInReactor 3.015/28.78%；SEMANTICS 0.044/0.42%；SurfaceFrame::Encode 3.935/37.56%；SurfaceFrame::Submit 5.910/56.41% |
| 1794337406032735/140 | Animate 0.377/4.04%；COMPOSITING 1.325/14.19%；CreateGlyphAtlas 0.019/0.20%；LAYOUT 0.007/0.07%；LayerTree::Paint 0.042/0.45%；PAINT 1.987/21.28%；Rasterizer::DoDraw 4.814/51.55%；Rasterizer::DrawToSurfaces 4.799/51.39%；RenderPassGLES::EncodeCommandsInReactor 1.690/18.10%；SEMANTICS 0.028/0.30%；SurfaceFrame::Encode 2.641/28.28%；SurfaceFrame::Submit 4.504/48.23% |
| 1794337406032735/212 | Animate 0.890/8.75%；COMPOSITING 0.871/8.57%；CreateGlyphAtlas 0.017/0.17%；LAYOUT 0.008/0.08%；LayerTree::Paint 0.044/0.43%；PAINT 2.505/24.63%；Rasterizer::DoDraw 5.351/52.62%；Rasterizer::DrawToSurfaces 5.304/52.16%；RenderPassGLES::EncodeCommandsInReactor 1.832/18.02%；SEMANTICS 0.046/0.45%；SurfaceFrame::Encode 2.847/28.00%；SurfaceFrame::Submit 4.974/48.91% |
| 1794337406032735/219 | Animate 0.427/3.62%；COMPOSITING 0.472/4.01%；CreateGlyphAtlas 0.021/0.18%；LAYOUT 0.008/0.07%；LayerTree::Paint 0.037/0.31%；PAINT 1.964/16.67%；Rasterizer::DoDraw 6.541/55.52%；Rasterizer::DrawToSurfaces 6.499/55.16%；RenderPassGLES::EncodeCommandsInReactor 2.913/24.72%；SEMANTICS 0.030/0.25%；SurfaceFrame::Encode 4.330/36.75%；SurfaceFrame::Submit 6.216/52.76% |
| 1794337406032735/236 | Animate 0.203/1.67%；COMPOSITING 0.233/1.92%；CreateGlyphAtlas 0.015/0.12%；LAYOUT 0.003/0.02%；LayerTree::Paint 0.038/0.31%；PAINT 0.809/6.65%；Rasterizer::DoDraw 10.676/87.81%；Rasterizer::DrawToSurfaces 10.662/87.70%；RenderPassGLES::EncodeCommandsInReactor 7.833/64.43%；SEMANTICS 0.062/0.51%；SurfaceFrame::Encode 8.668/71.29%；SurfaceFrame::Submit 10.392/85.47% |

## lots_shaking

| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |
| --- | --- | --- | --- | --- |
| — | 无尖峰 | — | — | — |

| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |
| --- | --- | --- |

所有尖峰的框架事件与毫秒占比（父子不可累加）：

| run_id/帧 | 框架事件 ms / %合计 |
| --- | --- |

## slot 入场 atlas 调用（稳态前独立窗口）

| 来源 | UI帧/引擎帧号 | atlas ms | UI帧ms | UI线程 |
| --- | --- | --- | --- | --- |

## GC（含 UI 帧外事件）

| 场景/run_id | 事件/线程 | 位置ms/耗时ms | 与UI帧重叠序号 |
| --- | --- | --- | --- |
| lotto_draw/1794337270240589 | CollectNewGeneration/511453528208 | 487.092/1.818 | [] |
| lotto_draw/1794337270240589 | Scavenge/511453528208 | 487.250/1.363 | [] |
| lotto_draw/1794337270240589 | Scavenge/496784388992 | 487.323/1.289 | [] |
| lotto_draw/1794337338194759 | CollectNewGeneration/511453528208 | 2902.449/2.036 | [] |
| lotto_draw/1794337338194759 | Scavenge/511453528208 | 2902.906/1.265 | [] |
| lotto_draw/1794337338194759 | Scavenge/496995386240 | 2903.169/1.008 | [] |
| lotto_draw/1794337406032735 | CollectNewGeneration/511453528208 | 1485.498/1.443 | [] |
| lotto_draw/1794337406032735 | Scavenge/511453528208 | 1485.570/1.089 | [] |
| lotto_draw/1794337406032735 | Scavenge/496959918976 | 1485.749/0.910 | [] |
