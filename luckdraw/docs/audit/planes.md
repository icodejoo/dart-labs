# 自定义能力盘点：分层与纹理化（plane）专项

> 只读审计原文（2026-11，Codex 逐条核对代码，含 文件:行号）。代码此后有变动，行号仅供定位；已落地项见 CHANGELOG 与 docs/E1_E2_DEVICE_REPORT.md。

可行。建议把它做成 **Canvas 渲染器的逐 plane 缓存能力，并将“合并整图”作为显式选项**。默认继续走现有分段、绘制顺序和缓存选择，才能保证兼容；不能默认把所有玩法改成整图纹理。

本报告基于只读源码审计。未修改文件、执行 Git、`pub get` 或测试，也未转派。下述调用数是代码推算，未实测。

**1. 逐玩法现状**

计数口径：一次外层 `drawPicture`、`drawImageRect` 或 `drawRawAtlas` 算一次；不展开 Picture 内部指令，不等同于 GPU draw call。省略用户 layers/hooks 的额外绘制。

| 玩法 | 每次 paint 大致调用数 | 缓存粒度及静态/动态分界 | 用户独立控制 |
|---|---:|---|---|
| wheel | 静态段数 `S`，常见约 **2～3 次**；交错旋转属性会增加 | 相邻、同旋转属性的静态操作合并 Picture；**仅旋转段**可 raster。内容静态，盘面旋转动态；按钮与指针固定 | 无逐段策略；只能全局配置或替换 renderer |
| grid | **`1+N+B+H`**。8 奖品、1 按钮无阴影拆分时 **10 次** | blocks 一张 Picture；每格普通/激活态各 Picture。只有“有背景且有阴影”的背景可 raster，内容独立 Picture。`H` 为本帧背景/内容分开回放的格数 | 无地图合并、逐格/逐层缓存策略 |
| slot | Picture：**`b+V`**；atlas：**`b+P`** | `b` 为是否存在 blocks；`V` 为实际可见有效格数；`P` 为 atlas 页数。格子内容静态，滚动位置与窗口裁剪动态。**只有显式 raster 启用 atlas，auto 仍走 Picture** | 无逐列策略 |
| lever | slot 调用数 **+3 次基本绘制**；另加赔付线层回放 | 拉杆独立 CustomPaint，每帧一条线、两个圆，无 Picture/raster 缓存；赔付线是静态 Picture 层 | slot 策略不控制拉杆缓存 |
| capsule | **`C+3+R`** | 后部、前部、旋钮、奖品卡为 Picture；胶囊按相同配色共享 Picture/raster。位置、角度、旋钮和揭卡缩放动态；`R` 为是否显示卡片 | 无逐部件缓存策略 |
| number_wheel | **3 次** | 外轨 Picture、整盘 Picture/raster、小球 Picture；盘面旋转、小球位置动态 | 无逐部件策略 |
| lots | **`K+3+R`** | 背景、筒后壁、筒前壁、无字签/有字签、卡片全部 Picture；摇晃、升签、揭卡缩放动态。`K` 为可见签数量 | 全局 cacheMode **不使它纹理化** |
| lotto | **`Q+3`** | 后部、前部、按钮 Picture；每个号码球独立 Picture/raster。球的位置、转角、进入结果槽动态；`Q` 为全部球数 | 无逐球池/部件策略 |

绘制路径依据：

- wheel：[wheel_painter.dart:164](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:164)、[wheel_painter.dart:268](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:268)、[wheel_painter.dart:296](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:296)。
- grid：[grid_painter.dart:92](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_painter.dart:92)、[grid_painter.dart:262](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_painter.dart:262)、[grid_painter.dart:288](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_painter.dart:288)。背景超限退回 Picture 时，拆分分支仍可能产生两次回放。
- slot/lever：[slot_painter.dart:58](E:/workspaces/dart-labs/luckdraw/lib/src/slot/render/slot_painter.dart:58)、[slot_painter.dart:193](E:/workspaces/dart-labs/luckdraw/lib/src/slot/render/slot_painter.dart:193)、[slot_atlas.dart:172](E:/workspaces/dart-labs/luckdraw/lib/src/slot/render/slot_atlas.dart:172)、[lever_painter.dart:38](E:/workspaces/dart-labs/luckdraw/lib/src/slot/lever/lever_painter.dart:38)。atlas 当前每页均提交一次，包含本帧未使用的页。
- 其余：[capsule_painter.dart:162](E:/workspaces/dart-labs/luckdraw/lib/src/capsule/render/capsule_painter.dart:162)、[capsule_painter.dart:306](E:/workspaces/dart-labs/luckdraw/lib/src/capsule/render/capsule_painter.dart:306)、[number_wheel_painter.dart:205](E:/workspaces/dart-labs/luckdraw/lib/src/number_wheel/render/number_wheel_painter.dart:205)、[lots_painter.dart:274](E:/workspaces/dart-labs/luckdraw/lib/src/lots/render/lots_painter.dart:274)、[lotto_painter.dart:260](E:/workspaces/dart-labs/luckdraw/lib/src/lotto/render/lotto_painter.dart:260)。

已知现状基本准确，但需补充两点：

- 全局默认是 `auto`，并非所有玩法都因此使用纹理；wheel/grid 在 `timebase.frame + auto` 下还特意保持 Picture。[options.dart:33](E:/workspaces/dart-labs/luckdraw/lib/src/core/foundation/options.dart:33)、[wheel_painter.dart:109](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:109)、[grid_painter.dart:100](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_painter.dart:100)。
- `LuckyLayer.isStatic` 通常只录 Picture，但 wheel 的静态旋转层能随合并段一起 raster；不能一概说静态自定义层绝不纹理化。[layer.dart:7](E:/workspaces/dart-labs/luckdraw/lib/src/core/render/layer.dart:7)、[wheel_painter.dart:192](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:192)。

**2. 统一抽象与 API**

建议放在 `core/render/`，由各玩法 Canvas renderer 声明 plane。现有 `LuckyRenderer` 已允许完全替换渲染后端，无需把 Canvas 缓存对象放进 model/layout/frame。[renderer.dart:12](E:/workspaces/dart-labs/luckdraw/lib/src/core/render/renderer.dart:12)

关键区分：

- **内容**：录制、栅格化、失效。
- **合成**：每帧的位置、旋转、缩放、裁剪。
- **存储**：单张纹理、多个实例纹理或 atlas。一个 plane 不承诺只有一张图片。

建议接口如下，省略常规构造器及泛型约束：

```dart
enum LuckyPlaneCache {
  inherit, none, picture, raster, auto
}

enum LuckyPlaneDependency {
  content, layout, images, text, dpr, state, manual
}

class LuckyPlaneOptions {
  const LuckyPlaneOptions({
    this.cache = LuckyPlaneCache.inherit,
    this.invalidateOn,              // null：继承 plane 声明
    this.rasterScale = 1,
    this.rebuildOnDpr = true,
    this.rebuildOnResize = true,
    this.maxRasterSide,             // null：继承 performance
    this.filterQuality,             // null：继承 performance
  });

  final LuckyPlaneCache cache;
  final Set<LuckyPlaneDependency>? invalidateOn;
  final double rasterScale;
  final bool rebuildOnDpr, rebuildOnResize;
  final int? maxRasterSide;
  final FilterQuality? filterQuality;
}

abstract class LuckyPlane<L, F> {
  LuckyPlaneId get id;              // 支持 family 和实例，例如 slot.reel/0
  LuckyPlaneAnchor get anchor;      // before/after 某内置 plane

  Rect paintBounds(LuckyPlaneContext<L, F> context);
  Object contentKey(LuckyPlaneContext<L, F> context);
  void record(Canvas canvas, LuckyPlaneContext<L, F> context);

  void compose(Canvas canvas, LuckyPlaneContext<L, F> context,
      LuckyPlanePlayback content);
}

abstract class LuckyPlaneHandle {
  void invalidate();
}
```

`LuckyRenderOptions` 提供：

- `planeOverrides: Map<LuckyPlaneId, LuckyPlaneOptions>`，实例覆盖优先于 family。
- `customPlanes: List<LuckyPlane>`，可插入、替换内置 plane。
- `maxRasterBytes: int? = null`，可选的整 surface 纹理预算。
- `prepare(...)` 在低频路径创建内容；`paint(...)` 仅合成；资源由 surface 统一释放。

使用形态：

```dart
LuckyGrid(
  config: config,
  renderer: GridCanvasRenderer(
    composition: GridComposition.mapTexture, // 默认 legacy
    render: LuckyRenderOptions(
      planeOverrides: {
        GridPlanes.map:
            LuckyPlaneOptions(cache: LuckyPlaneCache.raster),
        GridPlanes.highlight:
            LuckyPlaneOptions(cache: LuckyPlaneCache.picture),
        GridPlanes.buttons:
            LuckyPlaneOptions(cache: LuckyPlaneCache.picture),
      },
      customPlanes: [myPointerPlane],
    ),
  ),
);
```

默认值必须遵守以下契约：

1. **`inherit` 解析为原玩法、原部件的既有行为**，不能简单解析为全局 `auto`。否则 slot、lots、静态扩展层都会被悄悄改变。
2. 未传新选项时保留旧分段、旧 bounds、旧采样、旧顺序；不自动增加裁剪、离屏合成或纹理合并。
3. 显式 `auto` 才统一表示“运动 raster、静止 Picture”；显式 `none` 直接绘制，不录缓存。
4. raster 超边长或预算时回退 Picture，**不隐式降低分辨率**。
5. resize/DPR 的重建开关只控制额外触发；内容几何或有效像素尺寸已变化时，正确性失效仍不可关闭。
6. `contentKey` 不包含每帧位移；状态纹理只包含 activeIndex、按钮状态等离散变化。图片、字体、布局相关失效必须保留。

各玩法默认逻辑划分可为：

| 玩法 | 默认 plane 划分 |
|---|---|
| wheel | blocks、rotating content、pointer、buttons；允许因绘制顺序拆为多个实际段 |
| grid | blocks、cell background/content/state、buttons；地图模式额外提供 map/highlight/pointer |
| slot/lever | blocks、reel 实例、paylines、lever |
| capsule | back、capsule 实例、front、knob、drop、card |
| number_wheel | track、disc、ball |
| lots | background、cylinder back、stick 实例、cylinder front、card |
| lotto | back、ball 实例、front、button |

默认保留旧段合并；只有覆盖策略或选择合图模式时，才建立新的物理缓存边界。

**3. 九宫格四 plane 方案**

| Plane | 内容 | 更新方式 |
|---|---|---|
| 地图 | blocks、全部普通奖品格；不含开始按钮 | 静态；配置、布局、图片、文字依赖变化重建 |
| 高亮 | 当前格的完整激活视觉，必要时包含局部场景重建 patch | activeIndex 切换时选择缓存；无需每 tick 重录 |
| 指针 | 用户提供的标记、图片或绘制回调 | 图形可缓存；位置每 tick 合成 |
| 按钮 | 普通、按压、禁用等可选状态 | 图形按状态缓存，交互状态变化时重绘 |

**替换式高亮是主要难点。** 当前背景、阴影、边框、前景整体替换普通态，圆角、文字再按规则覆盖；按钮始终使用普通态。[grid_layout.dart:208](E:/workspaces/dart-labs/luckdraw/lib/src/grid/layout/grid_layout.dart:208)、[grid_painter.dart:182](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_painter.dart:182)

建议支持：

```dart
enum GridHighlightMode { replace, overlay } // 默认 replace
enum GridComposition { legacy, mapTexture } // 默认 legacy
```

`overlay` 由用户明确选择叠加效果。`replace` 的地图模式推荐采用 **地图避让区域 + 最终状态 patch**：

1. 计算普通态和激活态全部绘制范围的并集 `R`，包含阴影、文字、图片、越界绘制；向物理像素边界取整。
2. 地图纹理只绘制 `R` 外部。
3. 在 `R` 内按原顺序重建 blocks 和所有相交格子，用激活态替换目标普通态，得到透明 patch。
4. 高亮 plane 绘制 patch，再绘制指针与按钮。

这样透明激活态下不会残留普通态，也不会错误地将激活格抬到相邻格子之上。**直接用 `srcOver` 贴一张透明“底图”不能擦除已画出的普通格**；仅还原 blocks 也无法处理相邻格子的阴影或越界内容。

限制与回退：

- 自定义格子 painter 当前没有绘制范围契约，且内容未被格子边界裁剪。[grid_painter.dart:197](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_painter.dart:197)。地图模式需允许声明 `paintBounds`；无法确定时扩大到整图或回退原绘制路径。
- `belowItems` 动态层位于 blocks 和奖品之间，不能随意被整图吞并。存在这种插层时应拆段或回退；四个逻辑 plane 不保证四次物理回放。
- patch 应预备或按离散状态缓存；首次缺失时先用 Picture，不在稳态 paint 中执行 `toImageSync`。

**连续指针**可使用：

```dart
u = positiveModulo(frame.currIndex, prizeCount);
i = u.floor();
t = u - i;
position = lerp(center[i], center[(i + 1) % prizeCount], t);
```

路径按奖品列表顺序，也可由用户提供，不能默认按行扫描。`currIndex` 已连续累加，但当前 GridMotion 仅在 activeIndex 改变时发 repaint，controller 也只据此通知画面。因此需增加**可选逐 tick 通知源**，只在连续指针启用时订阅，保留原通知行为。[grid_motion.dart:18](E:/workspaces/dart-labs/luckdraw/lib/src/grid/motion/grid_motion.dart:18)、[grid_motion.dart:283](E:/workspaces/dart-labs/luckdraw/lib/src/grid/motion/grid_motion.dart:283)、[controller.dart:350](E:/workspaces/dart-labs/luckdraw/lib/src/core/control/controller.dart:350)

**按钮按压态**目前不存在：宿主只有 tap-up，没有按压生命周期。建议增加 surface 本地的 down/up/cancel 状态及可选状态 painter，默认仍画现有普通态，不修改抽奖状态机。[game_view.dart:474](E:/workspaces/dart-labs/luckdraw/lib/src/core/widgets/game_view.dart:474)

**命中测试继续解耦**：现有 hitRect 已与渲染分离，按钮优先命中；纹理化不应改为像素取样命中。[grid_game.dart:34](E:/workspaces/dart-labs/luckdraw/lib/src/grid/grid_game.dart:34)

调用数估算，无扩展层、单按钮、单图片指针：

- 无高亮：地图 + 指针 + 按钮，约 **3 次**。
- 最终状态 patch：地图 + patch + 指针 + 按钮，约 **4 次**。
- 独立底图 patch 再画激活态：约 **5 次**，仅适用于边界和重叠关系明确的场景。
- 无法安全合并时回退原路径，不能承诺固定四次。

其他玩法建议：

- **wheel**：同变换、连续绘制的盘面内容烘一张纹理，每帧旋转；固定外框、指针、按钮独立。block 图片目前允许分别旋转，所以存在交错顺序时仍需多段。按钮与指针目前同在 `_buttons` 中，拆分时应保留原操作顺序。[wheel_painter.dart:119](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:119)、[wheel_painter.dart:236](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:236)
- **slot**：每列一个逻辑 plane，可选现有单格/atlas，或整周期条带纹理。整条带环绕通常每列需要 1～2 次图片绘制，另加窗口裁剪；长条带超限时分页。逐列纹理可能比共享 atlas 占更多内存、调用更多，必须由用户选择。
- **lots**：背景、筒后壁、签、筒前壁、卡独立；筒和签共享摇晃变换，目标签再叠加升起变换。未中奖签可合组，但需保留目标签前后顺序，必要时分成两组，避免把升签统一画到最上方。卡片按结果缓存，缩放独立。

**4. 风险与取舍**

| 风险 | 建议 |
|---|---|
| 显存 | RGBA8 名义占用 `Σ ceil(W×DPR×scale) × ceil(H×DPR×scale) × 4`，另加 padding、atlas 空位、解码图片和临时资源；并非实际 GPU 总量。400×400、DPR=3 单图约 **5.49 MiB**；4096² 单图 **64 MiB**。默认边长上限确为 4096，但没有总字节预算。[constants.dart:21](E:/workspaces/dart-labs/luckdraw/lib/src/core/foundation/constants.dart:21)、[picture_cache.dart:35](E:/workspaces/dart-labs/luckdraw/lib/src/core/render/picture_cache.dart:35) |
| DPR、缩放、文字 | rasterScale 默认 1；父级放大和旋转会重采样，文字可能变软。允许用户提高倍率或保留文字 Picture；不能把当前停下恢复矢量的行为默认改掉。[cached_picture.dart:58](E:/workspaces/dart-labs/luckdraw/lib/src/core/render/cached_picture.dart:58) |
| 异步图片 | 图片到达后失效对应 plane、patch 和依赖 atlas；保持普通图加载门控及激活图回退。现有 grid 会全量重录，wheel 则只失效含图段，可统一为依赖追踪。[grid_canvas_renderer.dart:63](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_canvas_renderer.dart:63)、[wheel_painter.dart:153](E:/workspaces/dart-labs/luckdraw/lib/src/wheel/render/wheel_painter.dart:153)、[grid_painter.dart:228](E:/workspaces/dart-labs/luckdraw/lib/src/grid/render/grid_painter.dart:228) |
| resize 成本 | 配置/尺寸连变会反复录制和栅格化。合并同轮低频失效，先用新几何 Picture，纹理准备后切换；异步结果带版本，过期即释放。默认不增加延迟策略。 |
| 后端 | `toImageSync` 同步返回句柄，实际 raster 异步执行；失败可能在 draw 时才抛出，因此仅包住构建调用不足以实现可靠回退。GPU context 可用时驻留 GPU，否则走 CPU。[Flutter API](https://api.flutter.dev/flutter/dart-ui/Picture/toImageSync.html) 当前实现无后端失败处理。[picture_cache.dart:95](E:/workspaces/dart-labs/luckdraw/lib/src/core/render/picture_cache.dart:95) |
| Skia/Impeller/Web | 不应宣称某后端一律不支持。分别验证纹理创建、模糊、透明混合、采样和生命周期；Web 测 CanvasKit/Skwasm及目标浏览器。最低 Flutter 版本仍是 3.24，需同时验证最低版和当前版。[pubspec.yaml:15](E:/workspaces/dart-labs/luckdraw/pubspec.yaml:15)、[Flutter Web 文档](https://docs.flutter.dev/platform-integration/web) |
| layers/hooks | 旧四位置映射为固定锚点，保留列表顺序、旋转坐标和 `shouldRepaint`；hooks 继续每次 paint 执行。动态层、依赖目标画布的混合操作属于合图边界，不能默认录进静态纹理。[layer.dart:21](E:/workspaces/dart-labs/luckdraw/lib/src/core/render/layer.dart:21)、[hooks.dart:31](E:/workspaces/dart-labs/luckdraw/lib/src/core/control/hooks.dart:31) |

默认逐像素一致与可选纹理效果应分别验收。现有 golden 容差为通道差 32、差异像素占比 0.005、平均误差 1.5；通过它不能证明零像素变化。[golden_comparator.dart:6](E:/workspaces/dart-labs/luckdraw/test/support/golden_comparator.dart:6)

性能也不能只比较调用数。需同时观察冷建图、resize、首次激活、稳态帧时、纹理字节和释放；沿用现有基准及预算，不用新策略替换旧场景。现有基准已有失败/不确定项，不能预设合图必然改善。[tool/bench/README.md:300](E:/workspaces/dart-labs/luckdraw/tool/bench/README.md:300)

100% 是 `lib/` **行覆盖率**要求，工具默认门槛也是 100；新增代码必须补齐测试。[ARCHITECTURE.md:32](E:/workspaces/dart-labs/luckdraw/docs/ARCHITECTURE.md:32)、[coverage.dart:375](E:/workspaces/dart-labs/luckdraw/tool/coverage.dart:375) 建议提供可注入的 raster 创建接口，覆盖超限、失败、过期结果、预算回退和重复释放；另测透明高亮、重叠、越界、DPR、图片迟到及连续指针。行覆盖率不能代替这些视觉和行为断言。

**5. 实施批次**

| 批次 | 改动面 | 交付与验收 |
|---|---|---|
| ① 冻结兼容基线 | S～M | 固定字体、SDK/后端、尺寸、DPR、帧和图片状态；保存旧默认渲染结果及调用序列，不更新现有 golden |
| ② core 能力 | M～L | plane ID/实例、锚点、策略解析、依赖版本、bounds、预算、失效和释放；提供诊断信息及可测试 raster 接口 |
| ③ 接入现有缓存 | M/玩法 | 逐个将旧缓存接入统一管理，默认仍走原路径；完成 LuckyLayer 适配。接口稳定后各玩法可并行实施 |
| ④ grid 地图模式 | L | 显式 mapTexture、replace patch、透明安全裁剪、边界声明及回退；独立验证，不改变默认 |
| ⑤ 指针与按压 | M | 可选逐 tick 通知、用户路径、按钮本地状态；保留旧通知和命中测试 |
| ⑥ 其他合图策略 | M～L/玩法 | wheel 连续盘面合图、slot 条带、lots 有序签组；各自新增性能场景 |

core 必须先落地**策略继承、资源所有权、依赖失效、bounds、锚点和回退**；玩法划分留在各玩法目录，避免 core 引用具体玩法。

默认行为逐像素不变的验证办法：在同一 SDK、后端和输入下，对旧实现与新实现的默认路径解码 RGBA 做**零差异比较**，覆盖静止/运动/停止、三种 cacheMode、两种 timebase、透明背景、阴影、重叠、扩展层和图片到达前后。同时保留既有 golden、parity、缓存回放、资源释放、100% 覆盖及 import/摇树检查。已有资源测试会检查 Picture/Image 成对释放，可直接扩充。[perf_resources_test.dart:53](E:/workspaces/dart-labs/luckdraw/test/perf/perf_resources_test.dart:53)

建议第一阶段先交付“逐 plane 可控”，随后交付可选合图；整图烘焙只在用户明确选择、内容边界与合成顺序可证明时启用。
