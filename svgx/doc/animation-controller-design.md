# 动画播放控制设计(控制器 + 回调 + 时间轴缩放)

> 状态(2026-11-05):形态已拍板为 **A+B**(自研控制器为主 + Flutter `Animation` 适配)。阶段 1~4 已实现;第 5 阶段中 `SvgImageProvider` 的调度改造已随位图回退落地。尚未完成的有三项:CSS 动画名事件;真机 `anim_fps` 无回归验证(设备被占用,待补);第 9 节大文档异步解析。
> 依据:内部引擎摸底与外部方案调研(lottie-flutter、lottie-android、Rive、SMIL DOM、Web Animations API)。行号以 2026-11-05 的 `svgx` 为准。

## 1. 现状

`SvgxAnimated.string`(`lib/src/animation/animated_svg_widget.dart:54-69`)已有:

- `playbackRate`(必须 >0,运行中修改会重设基线,时间线连续)
- `onAnimationStart` / `onAnimationComplete` / `onAnimationLoop(int)`
- `maxFps`、`quality`、`theme`

缺口:

| 缺口 | 位置 / 原因 |
|---|---|
| 顶层 `Svgx.*`(string/asset/network/file/memory)一个动画参数都不转发 | `svgx_widget.dart:60-70`、`259-267`、`_AsyncSvgx` |
| 无控制器:play / pause / seek / 片段 / 倒放 | 本地时间只有 `_virtualOffset + dt*rate` 一种映射(W:645-652) |
| 倒放 | W:69 断言 `playbackRate > 0` |
| 播完不可逆 | `_settled` 只在 `_parseAndStart` 复位(W:552、582-587) |
| 无 `onLoaded` / `onError` | `_parseAndStart` 无 try/catch,坏 XML 在 `initState` 抛出(W:546) |
| 无"到某时刻"回调、无按元素的 begin/end/repeat 事件 | 数据都在时间线上(`begin`/`duration`/`repeatCount`/`intervals`/`elementId`),缺一张事件时刻表 |
| 纯无限循环文档没有周期 | `totalDuration` 不计无限动画;只有一个 `dur=2s indefinite` 的文档 `totalDuration=0`,`onAnimationLoop` 静默不触发(D:249-287) |
| CSS 编译出的时间线没有动画名 | `css_keyframes_compiler.dart:347-361` 未传 `elementId`/name |
| 新订阅者起点偏约 1 帧(跳帧时最多 N 帧) | `_startOffset` 取上一个 tick 的 elapsed(W:588) |
| 类文档仍写"不支持 animateTransform/CSS" | W:26-30、40-43,已过时 |

## 2. 设计原则

1. **共享时钟不动**:全进程一个裸 `Ticker`、按相位错开跳帧,这是 1000 图标场景的性能基础。控制只改"本地时间 = f(全局时间)"这一层。
2. **模型层保持纯数据**:周期、事件时刻表放在 `SvgDocument` 一侧,用纯函数求值,不引入 Dart 专属类型,满足 CLAUDE.md"时间线模型将来可由 Rust 填充"的约束。
3. **不传控制器时行为不变**:每个控件内部隐式创建一个控制器(lottie 的做法),走同一条代码路径,`css_head_frame_regression_test` 的 440 帧 RGBA 必须逐帧一致。
4. **seek / 倒放是安全的**:采样是时间的纯函数;节点缓存按采样值或不可变身份做键,不按时间做键;`paint_frame_cache_test` 已锁住"共享节点树乱序时刻绘制像素一致"。唯一有状态的 `_listResolver.extend` 只前向扩展,回查走二分。

## 3. 模型层新增(纯数据,解析期计算)

### 3.1 `SvgxAnimationInfo`(对外只读视图)

```dart
/// 动画文档的时长信息(只读)。
class SvgxAnimationInfo {
  /// 有限部分结束的时刻:所有有限动画的 max(begin + 活动时长),以及所有无限动画的 begin。
  final Duration settleTime;
  /// 是否含无限循环。
  final bool loops;
  /// 稳态循环周期;无限动画周期的最小公倍数(alternate 按 2×dur 计),超过上限(暂定 60s)或无法确定时为 null。
  final Duration? loopPeriod;
  /// "自然时长":不循环时 = settleTime;循环且有周期时 = settleTime + loopPeriod;否则 null。
  Duration? get naturalDuration;
}
```

- `loopPeriod` 解决"纯无限文档没有周期"的问题。现有 `onAnimationLoop` 改用它,不再用 `totalDuration`。
- **假无限**(如 `begin="0;100s;a.end" restart="never"` 被标为无限)沿用现有判定,本期不修,在文档里注明。

### 3.2 事件时刻表

对每条有 `elementId` 的时间线,用纯函数给出区间 `(from, to]` 内的事件:`begin`、`end`、`repeat(k)`。

- 有限区间直接算;`intervals` 列表分量复用已有的惰性展开(每次预取 64s)。
- `begin="x.end"` 已由 `_ForwardBeginResolver` 求成绝对区间,直接使用。
- CSS 时间线要先把 `CssAnimation.name` 带进时间线,才能按动画名发事件(本期第 5 阶段)。
- 事件型 begin(`click`、`beginElement()`)**本期不做**:模型里没有对应的 begin 种类,要新增。

## 4. 控制器 A:`SvgxAnimationController`

**本身不持有 Ticker**,播放时作为**一个订阅者**挂到共享时钟上。时间归控制器所有,挂在它上面的控件只读它的时间。

```dart
/// svgx 动画播放控制器。
class SvgxAnimationController extends ChangeNotifier {
  SvgxAnimationController({bool autoplay = true, double playbackRate = 1.0});

  // —— 状态 ——
  ValueListenable<Duration> get time;      // 当前文档时间
  SvgxPlaybackStatus get status;           // loading / playing / paused / completed / error
  SvgxAnimationInfo? get info;             // 首个文档就绪后可用

  // —— 播放 ——
  void play();                             // 若已在片段终点(按方向),从片段起点重播(同 WAAPI)
  void pause();
  void stop();                             // = pause() + seek(片段起点)
  void seek(Duration t);                   // 立即重绘,不经跳帧除数;不触发跨越的事件
  double playbackRate;                     // 可为负(倒放);0 视同暂停;修改时重设基线,时间连续
  void reverse();                          // playbackRate = -playbackRate

  // —— 时间轴 ——
  void setRange(Duration start, Duration end, {SvgxRangeMode mode = SvgxRangeMode.once});
  void clearRange();
  void fitDuration(Duration target);       // 语法糖:playbackRate = naturalDuration / target;naturalDuration 为 null 时抛 StateError

  // —— 回调 ——
  void addCue(Duration at, VoidCallback callback);   // "到某时刻"
  void removeCue(Duration at, VoidCallback callback);
  void addEventListener(ValueChanged<SvgxAnimationEvent> listener);
  void removeEventListener(ValueChanged<SvgxAnimationEvent> listener);
}

enum SvgxRangeMode { once, loop, pingPong }
```

`SvgxAnimationEvent` 是 sealed 类,子类包括:`loaded(info)`、`started`、`completed`、`looped(iteration)`、`rangeLooped(iteration)`、`elementBegin(id)`、`elementEnd(id)`、`elementRepeat(id, k)`、`error(error, stack)`。

### 4.1 语义细则

| 规则 | 说明 |
|---|---|
| 事件触发用**区间穿越**判定 | 正放判 `(prev, cur]`,倒放判 `[cur, prev)`。跳帧会漏掉 tick,不能用相等判定;一帧内跨过多个事件时,按时间顺序全部触发 |
| `seek` 不触发跨越的事件 | 与 WAAPI 一致;只更新时间和状态 |
| 完成是**可逆**的 | 到达片段终点(按方向)后 `completed`,同时退订共享时钟;之后 `play()`、`seek()`、`reverse()` 都能恢复,替换现有 `_settled` 终态 |
| 起点精确为 0 | 控制器在**订阅后的第一个 tick** 才锚定基线,修掉"新订阅者偏约 1 帧"的问题 |
| 时间钳位 | 下限 0;上限沿用现有约 115 天钳位。向前大跳(如 600s→3600s)会触发一次区间展开,三点环约 9.5ms(主机数据),写进 API 文档 |
| 多控件共用一个控制器 | 允许,时间一致;每个控件仍各自解析自己的文档,`info` 取第一个就绪的文档 |
| 跳帧 | 控制器作为一个订阅者参与并发计数和相位跳帧:驱动 50 个控件只计 1 个并发 |
| TickerMode | 所有挂载的控件都处在 TickerMode 关闭状态时,控制器退订(进度保留);任一恢复就重新订阅 |

**附带收益**:多控件共用控制器意味着时间完全相同,性能清单 D1"同源同相位共享每帧 Picture"在这里天然成立,不需要额外引入相位锁定。

### 4.2 隐式控制器

不传 `controller` 时,控件内部 `new` 一个,参数取控件上的 `autoplay` / `playbackRate`,三个旧回调桥接到事件流。旧行为保持不变:
- 每次挂载从 0 开始;
- 有限文档播完定格并退订;
- 无限文档持续播放。

## 5. 适配 B:Flutter `Animation<double>`

lottie 风格,复用 `AnimationController` / `Tween` / `CurvedAnimation` 生态:

```dart
SvgxAnimated.string(src,
  animation: myAnimationController,   // Animation<double>,值域 0..1
  animationSpan: null,                // 映射到的文档时长;null 用 info.naturalDuration
)
```

- 文档时间 = `animation.value × span`。控件监听 `animation`,**不订阅共享时钟**(驱动方自带 vsync 和 TickerMode)。
- `span` 为 null 且 `naturalDuration` 也为 null(无限且无周期)时,在 `onError` / `FlutterError` 中报错,不静默。
- `controller` 与 `animation` 互斥(断言)。
- 事件和 cue 照样按穿越判定触发;`AnimationController.repeat(reverse: true)` 产生的倒退同样适用。
- 代价:每个使用 B 的实例都有自己的 Ticker,不参与共享时钟的并发降级。这一点写进文档,大量并发时推荐用 A。

## 6. 控件 API

`SvgxAnimated.string` 与 `Svgx.string/asset/network/file/memory` 统一增加并转发以下参数(`Svgx.*` 对静态源忽略它们):

- `controller`、`animation`、`animationSpan`
- `autoplay`(默认 true)、`playbackRate`(放开到可为负)
- `onLoaded(SvgxAnimationInfo)`、`onError(Object, StackTrace)`;解析失败时不再在 `initState` 抛出,而是按 `errorBuilder` 或空盒子渲染,与 `Image` 一致
- 保留 `onAnimationStart` / `onAnimationComplete` / `onAnimationLoop`

同时修正 W:26-43 过时的类文档。

## 7. `SvgImageProvider` 的时钟评审

> 状态(2026-11-05):7.3 的第 1、2 条已实现,与位图回退一起落地(Network/Asset/File/MemorySvgx 按字节嗅探,非 SVG 交给原生解码)。调度方式:`Timer(interval × timeDilation)` → `scheduleFrameCallback`;两帧间隔超过 4 个 interval 视为暂停,只推进 1 个 interval;有限文档发出末帧后停止。第 3 条(控制器)仍不做。问题 3"后台持续渲染"已用 binding 模拟验证,尚未在真机上测 CPU。

**结论:不用共享时钟不是 Flutter 不支持,而是当初的实现选择;现在的写法有几处实际问题,建议改为 Flutter 官方 GIF 解码器的调度方式。**

### 7.1 事实

- 现状(`svg_image_provider.dart:713-785`):`Stopwatch` 作为时间源,`Timer.periodic(1000/animationFrameRate ms)`(默认 30fps)驱动;每帧异步 `Picture.toImage`,用 `_rendering` 防重入;最后一个监听者离开时停掉 Timer 和 Stopwatch,新监听者到来时恢复。来自 commit `5d614445`,提交信息只说明了"自定帧率 30fps + 无监听者暂停",没有说明为什么不用共享时钟。
- **Flutter 并不禁止**:裸 `Ticker` 不需要 `BuildContext`,svgx 的共享时钟本身就是裸 `Ticker`。`ImageStreamCompleter` 拿不到的只有 `TickerMode`(因为没有 context),这一点是 ImageProvider 体系固有的。
- **Flutter 自己的动图实现**(`MultiFrameImageStreamCompleter`,本机 SDK `packages/flutter/lib/src/painting/image_stream.dart:1091-1153`):先 `Timer(delay * timeDilation)`,到点后 `SchedulerBinding.instance.scheduleFrameCallback(_handleAppFrame)`,用帧回调的时间戳推进。也就是"Timer 控节奏 + 帧回调对齐 vsync"。

### 7.2 现写法的问题

| # | 问题 | 证据强度 |
|---|---|---|
| 1 | **有限文档播完后永不停止**:`renderFrame` 不检查 `totalDuration`,定格后仍以 30fps 反复 `toImage` 出相同的帧,白白消耗 CPU/GPU | 代码事实(`:750-773`) |
| 2 | **不对齐 vsync**:`Timer.periodic(33ms)` 与 60/90/120Hz 刷新率拍频,出帧节奏不均匀 | 推测(机制明确,未测) |
| 3 | **应用退到后台仍在渲染**:Dart `Timer` 在后台照样触发,而帧回调在没有帧时不会触发;控件仍挂载、监听者不会离开,于是后台持续 `toImage` | 推测,需真机验证 |
| 4 | 不受 `timeDilation` 影响(调试慢动画时不同步) | 代码事实,对比官方实现 |
| 5 | 不参与共享时钟的并发降级;控制器管不到 | 代码事实 |

### 7.3 建议

1. 按 `MultiFrameImageStreamCompleter` 的方式调度:`Timer(interval × timeDilation)` → `scheduleFrameCallback` → 用帧时间戳推进时钟 → 渲染。这样修掉问题 2、3、4,且不与控件侧的共享时钟耦合。不改成订阅共享时钟,因为共享时钟的订阅、相位、并发计数都是围绕控件 State 设计的,ImageProvider 在其中没有 TickerMode 语义。
2. 有限文档到达 `settleTime` 后只出最后一帧,然后停止(修掉问题 1)。
3. 控制器支持放到后续阶段:可以给 `SvgImageProvider` 加一个可选的 `controller`;但 ImageProvider 的 key 要求值相等,控制器只能作为非 key 字段,需要单独设计。本期在文档里写明"控制器不作用于 SvgImageProvider"。
4. 验证:问题 3 用真机前后台切换加 `/proc/self/stat` 的 CPU 计数确认;问题 1 加单测(有限文档播完后不再 `setImage`)。

## 8. 实施分期

| 阶段 | 内容 | 验证 |
|---|---|---|
| 1 | 模型层:`SvgxAnimationInfo`(含 `loopPeriod`)、事件时刻表纯函数 | 单测覆盖:有限、纯无限、alternate、begin 列表、syncbase、LCM 超上限 |
| 2 | 控制器 A + 隐式控制器重构 + 可逆完成 + 起点修正 + `onLoaded` / `onError` | 现有生命周期、TickerMode、共享时钟测试全绿;**440 帧 RGBA 逐帧一致**;新增 seek/倒放/片段/cue/穿越用例;`micro` 补一个时间映射开销项 |
| 3 | 适配 B(`animation` / `animationSpan`) | 用 `AnimationController` 驱动的像素对照、repeat(reverse) 事件用例 |
| 4 | `Svgx.*` 转发全部参数、修正类文档、example 加控制演示页 | widget 测试;`anim_fps` 真机无回归(4 次同二进制配对) |
| 5 | CSS 动画名进入时间线,按名发事件;`SvgImageProvider` 调度改造(第 7 节) | CSS 样本事件用例;真机前后台 CPU 对照 |

不在本期:事件型 begin / `beginElement()`、`SvgImageProvider` 控制器、修正"假无限"判定。

## 9. 大文档首次解析移出 UI 线程(真机数据驱动,2026-11-05 新增)

`LIB=anim_parse`(`benchmark/bench_app/lib/anim_parse_bench_screen.dart`)对 55 个 SVGator CSS 样本测冷解析,每个文件 7 次取中位数:

| 指标 | Windows x64 | 华为 STG-AL00(2 次运行一致) |
|---|---|---|
| p50 | 0.42ms | 1.5ms |
| p90 | 4.4ms | 17.3ms |
| 最慢(`159.svg`,592 节点) | 16.3ms | 72ms |
| 中位数超过 16.6ms 的文件 | 0 | 6 / 55 |

结论:在低端机上,大插画首次挂载会在 UI 线程卡 2~4 帧,必须改成异步解析;普通图标(p50 1.5ms)不受影响。

做法待 spike 后定,候选:
- **后台 isolate 解析**:模型基本是纯数据,刚解析完的对象图里没有 `ui.Path` / `ui.Image`。有三个阻碍:解析中途调用 Rust FFI(`native_svg_values.dart`,失败时会静默锁死并返回 null);用到 `ui.Path.computeMetrics`;`_ForwardBeginResolver` 以对象身份为键。
- 按源码长度设阈值,超过阈值的走异步路径;复用控件已有的"占位 + 就绪后开跑"状态机(`_imagesReady`),配合 `onLoaded`。
- 提供公开的预热 API(`SvgxDocumentCache` 异步预解析)。

**后台 isolate spike 结果(2026-11-05,Windows x64,`flutter test`,副本实验,未改仓库)**:
- **`ui.Path` 在后台 isolate 无法创建**(`UI actions are only available on root isolate`,调用点 `parseSvgPathData` → `new Path()`)。凡含运动路径(`animateMotion`、CSS `offset-path`)或需要 `ui.Path` 的路径解析的文档,后台解析必然失败:55 个 SVGator 样本 7 个失败(含最慢前几名的 156、104、221),真实 SMIL 图标样本约 6/21 失败。159、109 能成功。
- **Rust FFI**:后台 isolate 不初始化时不会报错,而是**静默降级成 null**,与主 isolate 结果不一致(语料对照出现 1250 处差异);默认初始化或传绝对路径的 `RustLib.init` 在后台可用。必须在 worker 里显式初始化并断言。
- **回传**:刚解析完的文档可以用复制或 `Isolate.exit` 回传;若节点上已缓存了 `cachedGeometry`(`ui.Path`),则不可发送。成功的文档与主 isolate 解析结果逐像素、逐采样、事件均等价(1104 个像素对照、13180 个采样点、1380 个事件)。
- **成本**:159.svg 主线程同步解析 min 28ms / 中位 46ms;后台总耗时相近,但主线程只承担接收:复制约 2.4~5.7ms,`Isolate.exit` 约 1.6~4.4ms,根 isolate 定时器间隙 ≤约 3ms。每次新起 isolate 的首次冷启动总耗时约 230~250ms(初始化约 29ms,冷解析约 200ms),需要常驻 worker 摊销。
- **结论**:直接把现有解析搬进 isolate 不可行,卡在 `ui.Path`。可选路线见聊天记录/下一步决策。

同一轮的单图标稳态 ARM 补测(`LIB=one_anim`)只有 1 次有效,另 2 次因设备被占用出现 0 帧阶段,作废。这 1 次的边际成本:普通图标 UI 约 257µs、GPU 约 47µs;带 mask 的图标 UI 约 311µs、GPU 约 285µs。16 个带 mask 的图标同屏仍是 60fps,UI 和 GPU 各占约 30% 的帧预算。待补 2 次后再写入 `performance-benchmarks.md`。
