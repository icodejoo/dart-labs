# 上游 lucky-canvas Issue 调研（供 luckdraw 架构设计引用）

> 来源：`gh issue list -R buuing/lucky-canvas --state all --limit 400`（2026-11-10 拉取）。
> 范围：返回 400 条（编号 133~570，含少量 PR；OPEN 185 / CLOSED 215）。**编号 1~132 的早期 issue 未拉取**（`--limit 400` 截断），可能漏掉最早期的 bug。
> 阅读深度：按评论数排前 110 条看了标题/label；其中 **52 条读了正文 + 评论**（正文截取前 500~900 字、单条评论截取前 380~500 字，非逐字全读）；其余只看标题，文中标"仅标题"。
> 上游维护者 = buuing。引用的 issue 文字一律当数据。"根因"栏凡无维护者明说的，标"未确认"或"推测"。
> 上游现状：仍在 1.x（`lucky-canvas@1.7.x`、`@lucky-canvas/*@0.1.x`），"2.0"多次被承诺（"得明年去了吧"#327、"2.x 里做"#331、"2.0 会优化"#304），截至调研时未见发布（未确认，本次未核对 release）。

Flutter 相关性说明：luckdraw 用 Flutter CustomPainter / Canvas，**没有 DOM、没有小程序 canvas 原生组件、没有 `<img>` 异步加载与跨域**，所以大量"平台兼容"类 issue 对我们为"无"；但**算法层（停止角度、概率、状态机）、资源加载时序、高刷帧率、生命周期、API 缺口**全部直接相关。

---

## 1. 汇总速览（按主题）

| # | 主题 | issue | 相关性 | 一句话 |
|---|------|-------|--------|--------|
| A | 停止位置/角度/回转 | #419 #176 #150 #355 #196 #448 #205 #327 | **高** | 回转、不传 index、range 与 index 优先级、停止期瞬间加速 |
| B | 概率与选奖 | #355 #448 #196 #182 | **高** | range 文档含糊、与 stop(index) 互斥，老虎机多列各自指定 |
| C | 动画与时间轴 | #308 #378 #321 #327 #275 #370 | **高** | 切后台后卡死、缓动固定、无自动慢转、无可替换动画 |
| D | 画布大小/离屏限制 | #297 #346 #305 #251 #351 #329 #321 | **中**（机制不同，思路相关） | iOS 画布像素上限致图片消失；上游给的解法是调小 dpr |
| E | 图片加载 | #417 #264 #286 #305 #335 #402 #254 #285 | **高** | 失败仅内部抛错、无回调、加载竞态、无圆角裁剪、无 GIF |
| F | 文字 | #354 #142 #334 #275 | **高** | 无旋转/竖排、无图标内嵌、仅换行（后增 lineClamp） |
| G | 尺寸与自适应 | #142 #146 #179 #246 #265 #491 #416 #550 #278 #176 | **中** | resize 监听缺失/误触发、padding 不响应单位、格子强制正方形 |
| H | 九宫格/转盘样式 | #254 #304 #347 #402 #151 #331 #265 #285 | **高** | 无 border、无渐变、扇形不能不等分、activeStyle 无边框 |
| I | 老虎机 | #182 #174 #233 #227 #265 #308 #321 #297 | **高** | 多列定位、order、无指示器、无音效钩子、内存/卡死 |
| J | 事件与交互 | #370 #153 #342 | **高** | play 中点按钮不触发 start、按钮不能只展示、需"纯 API"驱动 |
| K | 动态更新 prizes/配置 | #382 #550 #287 #246 #175 | **高** | 无可靠更新通道，社区用 `key` 强制重建 |
| L | 性能/泄漏/销毁 | #308 #321 #378 #146 | **高** | 离屏 canvas 泄漏、无 destroy、定时器堆积 |
| M | 框架/小程序/uni/taro | #322 #301 #283 #192 #294 #268 #313 #271 #290 #302 #328 #528 #533 #490 | **无** | 平台包装问题，结论见 §3 |

---

## 2. 条目明细

> 格式：**现象 / 根因 / 状态 / 相关性 / 建议**。

### A. 停止位置、角度、回转

**A1. 转盘有时反向回转（endDeg 为负）— [#419](https://github.com/buuing/lucky-canvas/issues/419)（open）**
- 现象：`stop(index)` 后偶尔倒转后停止。
- 根因：用户读源码定位：`carveOnGunwaleOfAMovingBoat` 里逐圈试探 `endDeg`，`quad.easeOut` 在"减速时间内当前速度无法停到目标"时，`this.endDeg` 出现负值，缓动曲线反向。维护者先称"速度为负或低于 10 会回转""理论上不会出现负值"，后让用户把 `accelerationTime/decelerationTime` 都调到 3000；用户指出这会让等待过长，建议"负值加 360 修正"，**维护者未再回复**。
- 状态：open，未修。
- 相关性：**高**。
- 建议：停止角度用解析解：给定当前角度 θ0、当前角速度 ω、期望落点 θt、减速时长 T，先算"至少多转几圈 k"使位移 ≥ 0 且末速度连续，保证单调递增；对 `endDeg<0` 加 `+360*k` 归一化；单测覆盖 (速度 × 时长 × 目标 index × 起始角度) 的网格，断言角度序列单调不减、落点误差 < 阈值。

**A2. 停止期"瞬间加速"/九宫格闪现第 0 格 — [#205](https://github.com/buuing/lucky-canvas/issues/205)（closed，1.7.19 修）**
- 现象：加速与匀速之间偶尔渲染第 0 格，speed 小时更明显。
- 根因（维护者）：为保证"停止时间毫秒级可控"，程序判断在设定时间内以当前速度停不到目标时会瞬间加速，造成视觉跳变；`currIndex=0` 的重绘是副作用。
- 相关性：**高**。
- 建议：停止规划（planner）与渲染解耦，规划结果是一条连续位移曲线；"时间可控"与"不跳变"冲突时，优先延长时间（或限定最小 decel 时长）而非突变速度，并暴露 `minDecelerationTime`。

**A3. 切标签页/窗口回来转盘整体偏移到左上角 — [#176](https://github.com/buuing/lucky-canvas/issues/176)（closed）**
- 现象：浏览器两标签页来回切，转盘中心跑到左上角（uni-app H5，v1.7.7）。
- 根因：未确认（维护者追问信息，未给结论）。同类 #278（uniapp H5 圆心被重置）维护者说是 uni-app 渲染 bug：图片 onload 后重置圆心（dcloudio/uni-app#2847），**非核心库问题**。
- 相关性：中（"变换矩阵状态被外部污染"这个类别相关，Flutter 里每帧 save/restore 即可规避）。
- 建议：每帧绘制自包含 `canvas.save()/restore()`，不依赖跨帧累积的 translate；不要像上游那样让用户用 beforeDraw/afterDraw 手动 translate 补偿（#278）。

**A4. 指针停在两奖区中间 — [#150](https://github.com/buuing/lucky-canvas/issues/150)（closed）**
- 现象：Demo 每次都停在两区交界。维护者：旧版 bug，升级 `@lucky-canvas/vue@0.0.3` 修复。
- 相关性：高（对应 `offsetDegree`、`stopRange`）。
- 建议：公开 `stopRange`（落在扇区内的随机偏移比例）、`offsetDegree`（指针起始偏移）并写清零点和方向约定（0° 在哪、顺/逆时针），文档配图；默认让停点落在扇区中心附近而非边缘。

**A5. `stop()` 不传参数 — [#355](https://github.com/buuing/lucky-canvas/issues/355)（closed）、[#196](https://github.com/buuing/lucky-canvas/issues/196)（closed）、[#174](https://github.com/buuing/lucky-canvas/issues/174)（closed）**
- 现象：不传 index，转盘/老虎机"戛然而止"或"无法停止""页面崩溃"。
- 根因（维护者）：不传 index 他不知道停哪（#174、#355）；`range` 只在**不传 index** 时生效，但 #355 用户配了 range 仍没生效，最后似乎是用户把 range 加错了层级（加在 text 下）。#196 维护者"测试没问题"，用户未再回应，**未确认**是否有崩溃。
- 相关性：**高**。
- 建议：`stop([int? index])`：index 缺省 => 用概率选；"崩溃"一类用空值安全 + 全部分支单测；停止动画与有无 index 无关，decel 曲线必须始终生效（#355 的"突然停"是 bug）。

**A6. stop 的索引与指针落点不一致 — [#448](https://github.com/buuing/lucky-canvas/issues/448)（open）**
- 现象：小程序，第二次起 stop 传的 index 与实际指针不一致。维护者回复"range 和 stop 都没有问题，除非你代码有问题"，未给证据，**未确认**。
- 相关性：高。
- 建议：end 回调携带的是"规划时目标 index"，并在 end 时用最终角度**反算** index 做 debug 断言（不一致抛 assert/日志）；连抽时每次 play 前重置旋转状态或明确"从当前角度继续"。

### B. 概率与选奖

**B1. range 语义含糊 — [#448](https://github.com/buuing/lucky-canvas/issues/448)、[#355](https://github.com/buuing/lucky-canvas/issues/355)**
- 现象：用户看不懂 range 与 stop(index) 的优先级。文档语义（#448 引用）：权重 `[10,20,30]`→概率 10/60…；`0` 表示不中；全部 `0/null/undefined` 则忽略 range；**传了 index 则 range 失效**。
- 相关性：高。
- 建议：库内提供 `PrizePicker`（权重 → index，注入 `Random` 以便单测），传 index 与权重互斥改为显式 API：`stop(index)` vs `stopByWeight()`；权重全 0 抛明确错误或回退均匀并给 warning；负数权重 assert。**中奖结果以"服务端指定 index"为主流**，别把权重当唯一入口。

**B2. 老虎机多列各停不同奖 — [#182](https://github.com/buuing/lucky-canvas/issues/182)（closed）**
- 现象：需求"三列分别停在不同奖品"（含未中奖组合）。上游后加 `stop([a,b,c])`，数组长度必须等于 slots 数；`stop(0)` 等价全列 0。
- 追问：传数组后 end 里拿到 `undefined`，维护者："说明没中奖"（语义是**三列索引相同才算中奖**，推测）。
- 相关性：高。
- 建议：end 回调给 `List<int> indices` + 派生的 `isAllSame`/自定义 `isWin(indices)` 判断函数，不把"相同才中"写死（呼应库 API 用判断函数的偏好）。

### C. 动画与时间轴

**C1. 切后台/长时间失焦后页面卡死 — [#308](https://github.com/buuing/lucky-canvas/issues/308)（open，49 条评论，最热）、[#378](https://github.com/buuing/lucky-canvas/issues/378)（open）**
- 现象：官网示例也能复现——刷新时快速切标签，或失焦几分钟/15 分钟~半小时后回来，页面整个卡死（含 Chrome、QQ 浏览器）；老虎机、大转盘、九宫格均有人报。
- 根因：**未确认**。维护者长期"无法定位"，推测"像是离屏 canvas 导致"，后用户称大转盘/九宫格也崩。推测与"页面隐藏期间 rAF/定时器暂停，回来时累计时间差巨大，追赶逻辑（逐帧补算）一次性跑大量帧"一致，但**这是我的推测，未被上游证实**。#378 另一例被归因于用户自己放了太多定时器。
- 相关性：**高**（Flutter 后台 Ticker 同样会暂停，resume 时 elapsed 跳变）。
- 建议：动画时钟用 `Ticker` 的 `elapsed` 而非累计固定步长；**单帧 dt 钳制**（如 ≤ 50ms）并在 `AppLifecycleState.paused/hidden` 暂停时钟，resume 时重置基准；加单测模拟"一帧跳 10 分钟"后状态仍有界且收敛。

**C2. 减速手感无法定制 — [#327](https://github.com/buuing/lucky-canvas/issues/327)（closed）**
- 现象：想要"明显缓慢停下"；`decelerationTime` 文档定位是"微调"，加到 10s 仍不够。
- 根因：缓动函数固定（quad easeOut），维护者说 2.0 才开放自定义。
- 相关性：高。
- 建议：`Curve` 作为参数（默认 `Curves.easeOutQuad`）；加速、减速各一条。`Duration` 类型而非毫秒 int。

**C3. 待机慢转 + 点击后快转 — [#370](https://github.com/buuing/lucky-canvas/issues/370)（closed）**
- 现象：想进页面自动慢转，点按钮才快速抽奖。
- 做法（维护者）：先 speed=1 `play()`，用户点击后 `init()` 重置再设速度 20。play 期间点中心按钮不触发 `start`（维护者故意屏蔽："已经在游戏中就没必要再触发"）。
- 相关性：高。
- 建议：显式状态机 `idle → accelerating → spinning → decelerating → stopped`，另加 `idleSpin`（待机慢转，可选）；任意状态点击按钮都上报 `onTap`，是否忽略由状态 + 回调返回值决定。

**C4. 动画拆分需求 — [#342](https://github.com/buuing/lucky-canvas/issues/342)（open）、[#275](https://github.com/buuing/lucky-canvas/issues/275)（open）**
- 现象：UI 很复杂（摩天轮、押注发射动画）的用户想"只要缓动/旋转 API，渲染自己做"。维护者表示"可以把缓动回调单独抛出来"，#275 讨论 CSS3 transform 与 canvas 两种旋转方式并存，维护者认为 css3 加减速"太刻意"。
- 相关性：高。
- 建议：把"旋转控制器"（`LuckyWheelController` 暴露 `angle`/`progress` 的 `Listenable`）与"绘制"分离，用户可自带 painter 或叠加 Widget；`ChangeNotifier`/`ValueListenable` 即可，不引入新依赖。

**C5. 高刷屏速度变化 — 未在读过的 issue 中找到专门帖子**。上游用 `FPS` 常量推导 easeOut 步数（#419 引用的源码里有 `this.FPS`），固定步长逐帧推进，**推测**高刷屏会加速/变慢，**本次未读到 issue 佐证**。建议：时间基于 elapsed 而非帧计数（同 C1）。

### D. 画布尺寸上限 / 离屏 canvas

**D1. iOS 奖品多（>4~10 张图）不显示 / 报错 — [#297](https://github.com/buuing/lucky-canvas/issues/297)（closed）、[#346](https://github.com/buuing/lucky-canvas/issues/346)（closed）、[#305](https://github.com/buuing/lucky-canvas/issues/305)（closed）、[#251](https://github.com/buuing/lucky-canvas/issues/251)、[#351](https://github.com/buuing/lucky-canvas/issues/351)、[#329](https://github.com/buuing/lucky-canvas/issues/329)（后三条仅标题）**
- 现象：iOS/部分 webview 老虎机奖品超过一定数量图片整体不显示或报错，安卓/PC 正常；#329 `order` 数组 >13 在 iOS 失效。
- 根因（维护者）：老虎机把所有奖品先画到一张**离屏 canvas**，高度 ≈ 奖品数 × 格高 × dpr，超过 iOS 画布像素上限；插槽列数越多离屏越小，所以让用户"别放那么多奖品"/"改成 2 列"；有用户折中做法：按奖品数/设备动态传入更小的 dpr，维护者采纳并给了 demo（会损失清晰度）。#305 在 webview 里无报错只是图不显示，**未确认**是否同因。
- 相关性：**中**。Flutter 不用离屏长条纹理，但若把"整列奖品"预渲染成 `ui.Image`/`Picture` 做滚动，同样会撞 GPU 纹理上限（Skia 通常 ≥4096~8192，低端更小）。
- 建议：滚动时每帧只绘制可见窗口内的格子（环形索引取模），不预拼长图；若必须缓存，用 `ui.Picture` 而非位图，或分块。预留 `maxTextureSide` 防护与单测（奖品数 50 也能渲染）。

### E. 图片

**E1. 图片加载失败只能内部抛错、无回调 — [#417](https://github.com/buuing/lucky-canvas/issues/417)（open）**
- 现象：React 包老虎机偶发 `prizes[i].imgs[i] => '...' 图片加载失败`，包装层的 `onError`/`onFinally` 不起作用（维护者：那是组件自身错误，不能捕获 lucky-canvas 内部错）；用户复现在 iPhone 14 Pro Max / iOS 16.6.1，web 与 iPhone 11/安卓正常。
- 相关性：**高**。
- 建议：图片加载抽象为 `PrizeImageProvider`（基于 Flutter `ImageProvider`），**加载失败给占位 + `onImageError(prize, img, error)` 回调**，不让一张图失败阻塞整盘渲染；`await precache()` 完成前显示 loading 状态，由 `onReady` 通知。

**E2. 远程图偶发空白（加载时机/竞态）— [#264](https://github.com/buuing/lucky-canvas/issues/264)（closed）、[#286](https://github.com/buuing/lucky-canvas/issues/286)（closed，跨域，维护者称"最新版已修"）、[#305](https://github.com/buuing/lucky-canvas/issues/305)**
- 现象：http 远程图间歇性空白，本地图正常（#264，维护者要复现环境，**无结论**）；老虎机跨域错误（#286，修了，细节未读到）。
- 相关性：高（竞态那部分）；跨域：**无**（Flutter 原生网络层无 CORS）。
- 建议：图片 Future 全部完成再首帧绘制，且用 `Future.wait` + 取消令牌防止 prizes 变更后旧加载回写（#264 疑似此类竞态，推测）；缓存以 URL 为键，失败可重试策略可配。

**E3. 图片圆角 — [#254](https://github.com/buuing/lucky-canvas/issues/254)（closed）、[#285](https://github.com/buuing/lucky-canvas/issues/285)（仅标题）**
- 现象：`borderRadius` 只对**背景**生效，图片 100% 宽高时仍是直角。上游给的方案是 `imgs[].formatter` 里用 canvas 手动裁剪，小程序用户不会用。
- 相关性：高。
- 建议：图片项直接支持 `borderRadius`/`clipShape`；这在 Flutter 里就是 `canvas.clipRRect`，零成本，一并支持图片 `shadow`（#254 评论显示图片阴影只支持十六进制颜色，rgb 格式不生效——是上游颜色解析缺陷，我们用 `Color` 类型天然规避）。

**E4. GIF 只渲染首帧 — [#335](https://github.com/buuing/lucky-canvas/issues/335)（closed）**
- 维护者：不支持 GIF，用 `<img>` 绝对定位叠加。
- 相关性：中。建议：v1 不做；但保留"覆盖层 Widget 叠加"的官方推荐写法（`Stack` + `IgnorePointer`），同时 `ImageProvider` 抽象天然可扩展到动图。

**E5. 渐变背景 — [#402](https://github.com/buuing/lucky-canvas/issues/402)（open）**
- 现象：九宫格奖品背景写渐变报错，维护者"渐变色不太好用，用图片代替"。
- 相关性：高。建议：背景用 `Paint.shader`/`Gradient`，类型直接接受 `Color` 或 `Gradient`（Flutter 原生有，不必造轮子）。

### F. 文字

**F1. 无文字旋转/竖排 — [#354](https://github.com/buuing/lucky-canvas/issues/354)（closed）、[#275](https://github.com/buuing/lucky-canvas/issues/275)（open）**
- 现象：奖品多时横排放不下，想竖排/沿半径方向；维护者：不支持，"把文字做进图片"或自己魔改。
- 相关性：**高**（TextPainter + canvas.rotate 实现很简单）。
- 建议：文字 `direction: radial | upright | tangent`、`rotation` 属性，默认沿半径方向；转盘扇区数多时自动缩放字号（`TextPainter` 测量）。

**F2. 文字溢出/换行与截断 — [#142](https://github.com/buuing/lucky-canvas/issues/142)（closed）**
- 现象：长英文只能换行；上游增加了 `lineClamp`（最多行数，超出 `...`）。
- 相关性：高。建议：`maxLines` + `overflow: ellipsis`，用 `TextPainter` 的原生能力；字体加载完成前先 `precacheFont`/等 `FontLoader`，避免首帧测量错误（上游文字字体加载时机类 issue 本次未读到，**不展开**）。

**F3. 文字里放图标 — [#334](https://github.com/buuing/lucky-canvas/issues/334)（closed）**
- 用户想在 fonts 里嵌图标，维护者："放 prizes 的 imgs"（图文分层，不能同一层内联）。
- 相关性：中。建议：先不做内联图文；若要，用 `WidgetSpan` 不适合 canvas，需自绘，标为后续版本。

### G. 尺寸、自适应、resize

**G1. resize 行为不一致 + 滚动误触发 resize 导致抽奖重置 — [#146](https://github.com/buuing/lucky-canvas/issues/146)（closed）、[#142](https://github.com/buuing/lucky-canvas/issues/142)**
- 现象：移动端 Safari/华为浏览器滚动出视口后抽奖中途停止、中奖标记消失（浏览器地址栏收起触发 resize）；仅 js 包监听 resize，其余包不监听（维护者："用户不会变屏幕"）。
- 相关性：**高**（Flutter 里对应 LayoutBuilder 尺寸变化、屏幕旋转、分屏）。
- 建议：尺寸变化只重算几何（半径、字号缓存），**不重置动画状态/当前角度/中奖标记**；单测：旋转中 resize，角度与状态不丢。

**G2. padding 不响应单位 — [#179](https://github.com/buuing/lucky-canvas/issues/179)（closed）**
- 维护者承认 `blocks.padding` 忘做 rpx 适配。相关性：低（Flutter 逻辑像素）。建议：所有长度统一为 `double` 逻辑像素 + 可选百分比类型，不搞字符串单位解析（上游的 `'10px' / '80%' / 'rem'` 字符串解析是 bug 来源）。

**G3. 格子强制正方形 — [#265](https://github.com/buuing/lucky-canvas/issues/265)（open）**
- 现象：老虎机格子必须正方形，图片同时设 width/height 会被拉伸变形；维护者："只设 height"，承诺后续支持分别设宽高；无音效钩子（因各插槽转速不同，没有合适回调点）。
- 相关性：高。建议：格子尺寸 `cellSize: Size`，图片 `fit: BoxFit`；暴露每列"经过一格"的滚动回调（`onTick(slotIndex, passedCount)`）供音效使用，上游声称"没好方案"，我们可以直接给。

**G4. 画布偏移/变形多为外部 CSS 干扰 — [#491](https://github.com/buuing/lucky-canvas/issues/491)（closed）**
- 现象：不同分辨率下变形/偏移；维护者：dpr 正常，需检查外部 CSS；用户后来确认是外层 div 样式。相关性：无（DOM 问题）。

**G5. 容器隐藏/弹窗内初始化为 0 宽高**：本次读过的 issue 里没有明确帖子，**未读到**；#550（vue3 手机模式数据不显示，描述不清，无结论）疑似相关，**未确认**。建议：`LayoutBuilder` 遇 0 尺寸直接不绘制、尺寸可用后再启动，不报错。

**G6. 负半径报错 — [#336](https://github.com/buuing/lucky-canvas/issues/336)（closed）、[#416](https://github.com/buuing/lucky-canvas/issues/416)（open）**
- 现象：`Failed to execute 'arc' ... radius provided (-13/-1.66667) is negative`，Taro vue3 / webview 横屏 + vue2。
- 根因：#336 维护者先说"没设置半径"，随后怀疑 vue3 小程序图片 bug，最终**未确认**；#416 维护者"不知道"，用户称去掉奖品后报错变少，**未确认**。**推测**是容器尺寸为 0 或接近 0（减去 padding 后为负）时没有校验，非维护者证实。
- 相关性：高（防御性）。
- 建议：所有几何计算 `max(0, …)` 钳制，半径/内径为负直接跳过绘制并 debug 日志；单测输入宽高 0、负 padding、极小尺寸。

### H. 样式限制

| 限制 | issue | 状态 | 建议 |
|------|-------|------|------|
| 扇形角度只能等分，不能按概率大小分配 | [#151](https://github.com/buuing/lucky-canvas/issues/151) [#331](https://github.com/buuing/lucky-canvas/issues/331) | closed（未实现；维护者："今年没戏，要改文字换行、图片宽度%、停止位置计算"） | 数据模型直接带 `weight/angle` 字段；停止位置求解用"扇区起止角"而非"index × 等分角"，一开始就支持不等分 |
| 中奖高亮 `activeStyle` 无边框 | [#304](https://github.com/buuing/lucky-canvas/issues/304)（维护者承认"设计不合理，2.0 优化"） | closed | `activeStyle` 与普通 `style` 同构（`border/shadow/background/radius`） |
| 九宫格无 border，需交替图片模拟；`activeStyle.background` 被图片盖住不生效 | [#347](https://github.com/buuing/lucky-canvas/issues/347) | closed | 提供 `borderColor/borderWidth/borderRadius`；图片层与背景层分层绘制，active 样式作用于背景层 |
| 九宫格合并格/按钮多个/阴影 | 本次读到的帖子中无 | - | 未读到 |

### I. 老虎机

- 中奖指示器（线/箭头）缺失，维护者建议用图片盖在 blocks 里；`order` 可打乱各列奖品顺序 — [#227](https://github.com/buuing/lucky-canvas/issues/227)（closed）。建议：提供 `indicatorBuilder` 或 `foreground` 叠加层。
- 单列老虎机配置 `slots` 只有一项，用户报"不渲染"，维护者复现在 playground 是好的，**未确认**根因（疑似其他配置） — [#233](https://github.com/buuing/lucky-canvas/issues/233)。建议：`slots.length == 1` 单测。
- 多图卡顿/页面反复白屏：每列 9 张 >10KB 图片，降到 4 张就好；react16 + iOS7/13 — [#321](https://github.com/buuing/lucky-canvas/issues/321)（open，**未确认**，维护者说中秋试，无结论）。
- 内存泄漏（用户在 Chrome devtools 看到老虎机内存增长，2025 年的评论，截图未读到具体数字）— [#308](https://github.com/buuing/lucky-canvas/issues/308)。**未证实根因**。
- 小程序基础库须 ≥ 2.17.0，否则老虎机报错 — [#181](https://github.com/buuing/lucky-canvas/issues/181)（平台，无关）。

### J. 事件与交互

- 点击中心按钮在 `play` 期间不触发 `start`（有意屏蔽）— [#370](https://github.com/buuing/lucky-canvas/issues/370)。
- 想把按钮变成纯指针展示：用户靠"不注册 onStart/onEnd 或回调内 return"，外部 DOM 按钮异步 `play()` — [#153](https://github.com/buuing/lucky-canvas/issues/153)。
- 建议：命中测试（中心按钮、格子）独立于动画状态，给 `enabled`/`onTap` 钩子；按钮可 `ignoring: true` 变纯展示；`play()` 在非 idle 状态忽略或返回 `bool`，防重复点击。

### K. 动态更新 prizes/配置

- 修改配置后重新 `new` 不生效；维护者坚持用 `init()`；社区实际用 **`key` 强制重建组件** — [#382](https://github.com/buuing/lucky-canvas/issues/382)（closed）。
- Vue3 修改 prizes 用 draw/init 都不更新，end 回调为 undefined — [#550](https://github.com/buuing/lucky-canvas/issues/550)（open，描述不清，无结论）。
- React 里 `start` 回调闭包永远是首次渲染的版本；维护者承认"现状"，用 `key` 或 `useRef` 绕开；用户看源码：`componentDidUpdate` 没监听 start/end 回调变化 — [#287](https://github.com/buuing/lucky-canvas/issues/287)（closed，**当时未修**，状态应以代码为准，未核实）。
- 组件响应式、Vue3 版"实时修改参数不同步刷新" — [#246](https://github.com/buuing/lucky-canvas/issues/246)、[#264](https://github.com/buuing/lucky-canvas/issues/264) 评论。
- 另一例"play 后只能点一次"是内部 `startTime` 没复位（`step===0` 分支提前 return）— [#175](https://github.com/buuing/lucky-canvas/issues/175)（closed，0.1.4 修）：状态机里"结束没回到 idle"的经典 bug。
- 相关性：**高**。建议：`LuckyWheel` 为受控 Widget（`didUpdateWidget` 比较 prizes/config，必要时只重算几何/重载变化的图片，**不重置动画**，进行中变化排队到 idle 后生效或立即应用但保持当前角度）；回调用最新 `widget.onXxx`（不要闭包捕获首次的）；单测：旋转中改 prizes、结束后再 play、连抽 100 次。

### L. 性能、泄漏、销毁

- 上游无显式 `destroy()` 的说法在本次读到的 issue 里没有直接帖子（**未读到**）；但 #308/#321/#378 的卡死/泄漏疑与"全量重绘 + 离屏 canvas + 失焦期间定时器"相关（推测，未被证实）。#378 用户在示例里放了多个定时器自动抽奖，维护者称是用户逻辑问题。
- 相关性：高。建议：Controller/Ticker/图片监听全部在 `dispose()` 释放；单测断言 dispose 后无活动 Ticker、无 ImageStream listener；重绘用 `RepaintBoundary` + 只在角度变化时 `markNeedsPaint`，静态层（背景/扇区/图片）缓存为 `Picture`，旋转只变换。

### M. 多端兼容（只记结论，不展开，相关性：无）

- 微信小程序 canvas 是原生组件，层级最高，会盖住弹窗，需 cover-view（#181）。开发者工具真机调试有 bug，看体验版（#181）。
- 微信改了底层 canvas 图片 API，**vue3 + 小程序渲染图片**长期有问题（#336 引用 #322，#322 仍 open，38 条评论，仅标题 + 引用）。
- uni-app / taro 相关：#301 #283（"uni-app 不支持 App 端吗"，open）#192 #294 #268 #313 #271 #290 #302（react-native 无法使用，open）#328 #528 #533 #490，均**仅标题**，未读正文。
- 打包/类型：#258 vue2 `Object(...) is not a function`（closed）、#136 `Cannot use namespace 'LuckyGrid' as a type`（仅标题，疑为 TS 类型导出问题，未读）、#137 vue2 低版本打包错、#156 vueDemi.defineComponent、#239 vite + vue 3.2 `play()` 无效（维护者让用户改用 `lucky-canvas` 核心包，推测与 vue 版本里 `this` 绑定有关）。
- 恶意/噪音：#403（网站禁止使用控制台，标 "恶意"）。

---

## 3. 汇总

### 3.1 Top 10：必须在架构里提前规避的问题（按重要性）

1. **停止角度求解不保证单调**（#419，open 未修）：用解析解 + 归一化，保证只前进不回转，网格单测。
2. **失焦/后台回来时间跳变导致卡死**（#308/#378，最热 open 帖）：时间基于 elapsed，单帧 dt 钳制，生命周期暂停/恢复。
3. **图片加载无错误通道、加载竞态**（#417/#264）：占位 + `onImageError` + 全部就绪再首帧；prizes 变更取消旧加载。
4. **动态更新靠 `key` 强制重建**（#382/#287/#550）：受控 Widget，`didUpdateWidget` 增量，回调始终取最新。
5. **状态机不严谨**（#175 结束没回 idle、#370 play 中屏蔽 start、#355 突然停）：显式状态枚举，所有转移有单测。
6. **resize/旋转时重置抽奖状态**（#146）：尺寸变化只重算几何，不丢动画和中奖标记。
7. **几何未校验导致负半径**（#336/#416）：所有尺寸钳制、0 尺寸不绘制、单测极端值。
8. **画布/纹理上限**（#297/#346/#305）：滚动只画可见窗口，不预拼超长位图。
9. **概率/选奖/落点语义含糊**（#448/#355/#182）：`stop(index)` 与权重选奖分离，end 回调带最终 index 并断言一致；多列给索引列表 + 判断函数。
10. **无销毁/泄漏**（#308/#321）：`dispose` 释放 Ticker/ImageStream，静态层缓存 `Picture`。

### 3.2 上游结构性缺陷（推断自 issue 与维护者回复，非通读源码）

- **命令式 + 全量重绘**：每次更新靠 `init()`，没有 diff；框架包装层（Vue/React/Taro）各自 hack 响应式（`key`、`useRef`、`componentDidUpdate` 监听不全）。
- **缓动曲线硬编码**（quad easeOut，2.0 才开放）、**停止"毫秒级可控"靠瞬间加速**（#205）。
- **字符串单位解析**（px/rpx/rem/vw/%）→ 各端不一致，padding 漏适配（#179）。
- **老虎机用一张离屏 canvas 拼全部奖品**（#297）→ 平台像素上限、内存与卡死疑点（#308）。
- **渲染层与业务耦合**：按钮点击直接屏蔽回调、无法只拿动画（#342、#370）。
- **样式模型不对称**：背景有圆角/渐变限制，图片无圆角，`activeStyle` 无边框，不等分扇区做不了（#151/#254/#304/#402）。
- **加载失败只抛内部错误**，无外部可捕获通道（#417）。
- **维护响应滞后 + 多个承诺的 2.0 未兑现**，用户常自行 fork 魔改（#265/#331/#402）。

### 3.3 用户最常要求但上游没有的功能 Top 10

1. 扇区不等分/自定义角度（#151、#331）
2. 文字旋转/竖排/沿半径（#354、#275）
3. 自定义缓动曲线（#327）
4. 纯 API/动画控制器，与渲染分离（#342、#275）
5. 图片圆角裁剪（#254、#285）
6. 九宫格 border / `activeStyle` 边框（#304、#347）
7. 渐变背景（#402）
8. 老虎机格子非正方形 + 滚动音效钩子（#265）
9. 待机慢转，点击后快转（#370）；以及按钮仅展示不响应（#153）
10. 老虎机中奖指示器/内置叠加层（#227）；另有"图片加载失败回调"（#417）、GIF（#335）并列

### 3.4 不确定 / 没读到

- **issue 1~132 未拉取**；#133~#570 中只读了 52 条正文，其余 ~290 条只在列表里（未看标题的更多）。
- **仅看标题未读正文**：#322 #301 #283 #192 #294 #268 #313 #271 #290 #302 #328 #528 #533 #490 #258 #136 #137 #156 #309 #251 #351 #329 #285。
- **未读到/没有专门帖子**：高刷屏速度变快变慢、字体加载时机、容器隐藏/弹窗内 0 尺寸初始化、九宫格合并格（col/row）与多按钮、事件监听泄漏、`destroy`、SSR、暂停/恢复 API。不代表上游没有这些问题，只是本次没读到证据。
- 点赞数（reactions）**没有采集**，选择依据为评论数 + label + 标题。
- 没有核对上游最新 release 是否修了 #419/#417/#308；"closed"仅按列表状态，不保证现版本无回归。
- 评论里的"链接/加微信/发 demo"等未打开，附件（zip、视频）未读。
