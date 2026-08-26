# 性能基准套件与复测记录

> 从 `CLAUDE.md` 拆出。这里是**所有实测数据**——性能基准套件本身的说明、每一轮功能改动后的复测结果、`LIB=compare` 方法学的演进、以及 `SvgEffects` 重构的性能记录。验收的"标准是什么"见 `docs/acceptance-criteria.md`;为什么某些方向不做见 `docs/ffi-performance-audit.md`。

## 性能基准套件:保留,功能完备后必须复测

**`benchmark/bench_app/` 不得删除/清理**,是本项目的常驻资产,不是一次性验收脚手架。

- 当前的性能验收结论(全维度 PASS)只覆盖**当前已实现的功能面**(见 `docs/animation-engine-features.md` 的能力清单)。后续每完成一批新功能,**必须用同一套 `bench_app` 重新跑一遍完整基准**,不能假设新功能不影响性能结论——新增的解析分支、绘制路径本身就可能引入新的性能回归。
- 复测时**沿用已验证的方法学**(1000 个真实 Iconify 图标、来回滚动 6 轮、svgx vs flutter_svg 独立进程对照、诚实标注平台/GC 局限),不要重新发明一套基准。
- Android 真机复测(当前遗留缺口)应该跟"功能完备后的复测"一起做一次,而不是分别测两次。

## 首次性能验收(2026-08-25,Windows 桌面 profile 模式实测)

- **FFI sync 结论(不改)**:读了 flutter_rust_bridge 2.12.0 源码(`handler.dart`)确认 `executeSync` 直接在调用方 isolate 上同步执行 `task.callFfi()`,没有走 `executeNormal` 那种 sendPort+Completer 的后台派发——架构上确实会阻塞调用方 isolate。但实测 1000 个互不相同的真实图标(iconify_flutter 的 `Mdi` 集,来自 `benchmark/bench_app/lib/mdi_icons_1000.dart`)来回滚动 6 轮,`parse_svg` 单次耗时 avg=0.026ms、p99=0.115ms、max=0.193ms(n=1000,直接 Stopwatch 实测),整场 646 帧里 `framesOver16.6ms=0`、`framesOver8.3ms=0`。结论:阻塞在架构上存在,但量级上可忽略,不构成实际卡顿,保持 `#[frb(sync)]` 不改。
- **1000 图标基准结果(svgx vs flutter_svg,Windows profile 模式,同一批 1000 个 Mdi 图标字符串)**:

  | 维度 | svgx | flutter_svg | 结论 |
  |---|---|---|---|
  | build 耗时 avg/p50/p90/p99/max | 0.622/0.571/0.966/1.828/2.379 ms | 1.685/1.577/3.096/4.925/9.268 ms | svgx 胜 |
  | raster 耗时 avg/p50/p90/p99/max | 1.526/1.409/2.119/3.292/3.944 ms | 1.997/1.860/2.907/4.192/5.378 ms | svgx 胜 |
  | 掉帧(>8.3ms / >16.6ms) | 0 / 0(646 帧) | 1 / 0(541 帧) | svgx 胜 |
  | CPU 占用(滚动期间 avg/peak,`Get-Process` 采样) | ~0.83% / ~4.49% | ~25.3% / ~30.2% | svgx 胜 |
  | 内存峰值(RSS) | 196.71 MB | 279.87 MB | svgx 胜 |
  | 内存稳态(滚动结束) | 193–198 MB | 267.24 MB | svgx 胜 |
  | 内存空闲后(3s) | 194–196 MB | 267.90 MB | 均未见增长,无泄漏迹象 |
  | 解析耗时(仅 svgx 有直接钩子) | avg=0.026/p50=0.018/p90=0.037/p99=0.106ms | 无直接钩子,只能用 build 耗时旁证 | 见方法学说明 |

  全部维度 svgx 胜出,无需额外优化即达标。

- **方法学说明(诚实标注)**:
  - 基准设备:Windows 桌面(`flutter run -d windows --profile`),未在 Android/WSA 上复测——桌面迭代最快,数据口径已在此注明。
  - 1000 个图标**不是**程序生成的合成图形,是从 `iconify_flutter` 插件的 `Mdi` 图标集里按声明顺序取的前 1000 个真实图标 SVG(`benchmark/bench_app/tool/gen_mdi_icons.dart` 一次性烘焙到 `lib/mdi_icons_1000.dart`,可复现)。
  - 滚动模式:`GridView` 8 列,`ScrollController.animateTo` 在顶部/底部之间来回 6 轮(900ms/趟,`Curves.easeInOut`)。
  - svgx 侧缓存上限显式设为 `itemCount + 50`,避免默认 200 条 LRU 在 1000 个不同图标场景下产生"缓存抖动"而不公平地放大解析次数;flutter_svg 一侧未做等价配置(它没有暴露等价的图片级缓存旋钮)。
  - flutter_svg 没有公开的"仅测解析耗时"钩子,所以"解析耗时"这一维度对 flutter_svg 只能不测(不是伪造成"更差"或"更好"),用 build 耗时的整体差距佐证。
  - 内存泄漏检查用的是"多轮滚动 + 3 秒静置后再采样"的替代方案,没有可靠的强制 GC 公开 API 可用(未验证到本 Flutter/Dart 版本有稳定可用的强制 GC 调试钩子),按任务要求如实标注这一点。
  - 动画流畅度:12 个并发播放的 `line-md` SMIL 动画图标(`SvgX.string` 走原创动画引擎)观测 6 秒,`framesOver16.6ms=0`、`framesOver8.3ms=0`(58 帧,build avg 0.461ms/max 1.497ms,raster avg 1.053ms/max 2.294ms)——动画引擎无主线程阻塞迹象。
- 复现方式:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx|flutter_svg|anim --dart-define=CYCLES=6 --dart-define=ITEMS=1000`,报告打印到 stdout。

## 性能复测(功能批次:currentColor/PaintOrder + 动画引擎扩展后)

**触发原因**:两批功能落地后按"性能基准套件"的常驻规定复测——静态路径新增 `currentColor` 注入 + `PaintOrder`(`parse_svg` 新增 `current_color` 参数、缓存键从 `String` 变宽为 `(String, int?)`、painter 新增按 `strokeFirst` 分支的绘制逻辑),动画引擎新增更多 shape 元素、`<animateTransform>`、`repeatCount` 循环(驱动方式从有界 `AnimationController` 改写为原始 `Ticker`)、`calcMode`/`keyTimes`/`keySplines`。方法学复用未变(1000 个真实 Mdi 图标、`GridView` 8 列来回滚动 6 轮、Windows 桌面 profile 模式);另按用户明确要求新增了两个用例——`anim` 场景补了一个 `repeatCount="indefinite"` 的 `animateTransform` 循环图标(svg-spinners `180-ring`,直接复用 `example/lib/main.dart` 的 `kSpinnerSvg`,验证持续 ticking 而非一次性播放-定格的性能画像),以及全新的"1000 个动画图标来回滚动"用例(见下方"1000 动画图标真实 FPS")。

**svgx 静态路径 vs 上一轮历史基线(同条件对照,均为无额外后台负载的独立运行)**:

| 维度 | 历史基线(本文件已记录) | 本轮实测 | 趋势 |
|---|---|---|---|
| build avg/p50/p90/p99/max | 0.622/0.571/0.966/1.828/2.379 ms | 0.790/0.670/1.350/2.713/4.990 ms | 绝对值 +27%,见下方"噪声还是回归"分析 |
| raster avg/p50/p90/p99/max | 1.526/1.409/2.119/3.292/3.944 ms | 1.840/1.683/2.573/3.906/4.732 ms | 绝对值 +21%,同上 |
| 掉帧(>8.3ms / >16.6ms) | 0 / 0(646 帧) | 0 / 0(648 帧) | 无变化,仍为 0 掉帧 |
| 解析耗时 avg/p50/p90/p99 | 0.026/0.018/0.037/0.106 ms | 0.039/0.022/0.065/0.241 ms | 绝对值上升,量级仍是微秒级,不影响掉帧结论 |
| 内存峰值/稳态/空闲后 | 196.71 / 193–198 / 194–196 MB | 238.49 / 236.79 / 237.65 MB | 绝对值 +21%,见下方分析 |
| CPU 占用 avg/peak(独立复测,同一台机器同一时段配对 flutter_svg) | 0.83% / 4.49% | 0.32% / 7.64% | avg 更低,peak 略高,量级仍远低于 flutter_svg |

**"是噪声还是真实回归"——没有直接采信、而是配对复测后的结论**:同一时段用完全相同方法学重新跑了一遍 `flutter_svg` 基线(而非直接套用历史 flutter_svg 数字),配对结果:

| 维度 | svgx(本轮) | flutter_svg(本轮同时段复测) |
|---|---|---|
| build avg | 0.790 ms | 2.288 ms |
| raster avg | 1.840 ms | 2.772 ms |
| 内存峰值 | 238.49 MB | 245.49 MB |

`flutter_svg`(外部依赖,本轮功能批次完全没碰它)在同一台机器同一时段测出来的绝对值同样比历史基线涨了(build 1.685→2.288,+36%;raster 1.997→2.772,+39%),涨幅比例甚至比 svgx 自己还大。用相对差距(svgx/flutter_svg 比值)看趋势更可靠:build 比值从历史 0.369(0.622/1.685)变成本轮 0.345(0.790/2.288),raster 比值从 0.764 变成 0.664——**两个比值都在缩小,即 svgx 相对 flutter_svg 的领先幅度不降反升**。这强烈说明本轮两边绝对值的同步上涨是这台开发机当时的系统级噪声(后台负载/调度,与本次基准测量本身无关),不是 currentColor/PaintOrder 分支引入的代码级回归。又额外复测一次纯 CPU 采样场景(见上表,svgx avg 0.32% vs 同条件 flutter_svg avg 9.89%、svgx peak 7.64% vs flutter_svg peak 39.99%),同样在每个维度上 svgx 完胜。

**结论**:配对复测下,svgx 在 build/raster/内存/CPU/掉帧的每一项仍全面超越 flutter_svg,且相对领先幅度没有缩小——**不构成"currentColor/PaintOrder 导致回归"的实锤证据**;两次独立 svgx 自测之间本身就有较大波动(build avg 0.790ms vs 另一次 1.309ms、内存峰值 238MB vs 199MB,后者测量时有额外后台进程占用),说明这台 Windows 开发机的测量噪声本身就相当大,±20~30% 的绝对值波动在这个环境下不足以单独作为回归证据。**如果需要更确定的结论,建议在空闲、无其他后台负载的机器上多次重复取中位数**——这是诚实的方法学局限标注,而非回避问题。

**动画:`repeatCount="indefinite"` 循环图标未引入主线程阻塞**:`anim` 场景(12 个并发图标,含新增的 svg-spinners `180-ring` 循环旋转图标)观测 6 秒:`frames=361`,`build avg=0.408ms max=2.075ms`,`raster avg=1.831ms max=5.072ms`,`framesOver16.6ms=0 framesOver8.3ms=0`——持续 ticking(而非原来纯 `<animate>` 图标的一次性播放后停止)没有产生额外掉帧。

**新增用例:1000 动画图标来回滚动,真实 FPS(应用户要求新增)**:

- 场景:`benchmark/bench_app/lib/anim_fps_bench_screen.dart`(`--dart-define=LIB=anim_fps`),1000 格 `GridView`(8 列),每格是一个真实播放中的 SMIL 动画图标(`SvgX.string`,原创动画引擎),来回滚动 6 轮(同静态基准的滚动参数)。
- 图标来源:`tool/gen_anim_icons.dart` 从 `iconify_flutter` 的 `LineMd`+`EosIcons`(已核实这两个集合 100% 是 SMIL、0% CSS,见 `CLAUDE.md` CSS 动画结论)烘焙出 399 个真实互异的 SMIL 动画图标,平铺填满 1000 格(`lib/anim_icon_gen.dart`)——凑不出 1000 个互不相同的真实动画图标,如实标注为"399 个真实互异图标平铺",而非编造出 1000 个不存在的资产。
- FPS 口径:**实测值,不是从 build/raster 耗时估算,也不是固定假设值**——`frame_timing.dart` 新增 `realAverageFps`,取每帧 `FrameTiming.timestampInMicroseconds(FramePhase.rasterFinish)`(引擎上报的真实光栅完成时刻),用首尾时间戳算 `(帧数-1)/经过时间`。
- 实测结果:`frames=645`,**`real_fps=59.95`**(即真实贴近 60Hz 显示器的满帧率),`build avg=4.650ms max=13.206ms`,`raster avg=2.306ms max=5.794ms`,`framesOver16.6ms=0`(相对 60Hz 预算零掉帧),`framesOver8.3ms=18`(相对更严格的 120Hz 预算有少量超出,但 display 是 60Hz,不构成真实掉帧)。
- 结论:1000 个并发播放的真实 SMIL 动画图标来回滚动,真实测得的平均帧率是 59.95fps,零掉帧(对 60Hz 预算),原创动画引擎在这个并发量级下未观察到主线程阻塞。

**本轮复现方式**:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx|flutter_svg|anim|anim_fps --dart-define=CYCLES=6 --dart-define=ITEMS=1000`。

## 复测方法学调整(节约时间)

**后续每次复测,不再重复跑 `flutter_svg` 那组对照。** 理由:`flutter_svg` 是外部依赖,代码不会因为 svgx 自己的改动而变化,基线数据已经 measured 并记录在上面的表格里(build avg=1.685ms、raster avg=1.997ms、CPU avg~25.3%、内存峰值 279.9MB 等)——每次改完 svgx 的代码就重新跑一遍 flutter_svg 纯属重复劳动,浪费编译+运行时间。

**新流程**:只跑 `--dart-define=LIB=svgx`(以及需要时的 `anim`),拿到的新数据**跟上一次 svgx 自己的历史数据做趋势对比**(涨了多少、跌了多少),而不是每次都重新对比 flutter_svg。已经确认"全维度胜出"的结论作为**长期有效的基线**保留;只有当 svgx 自身数据的回退幅度大到可能已经追平/输给 flutter_svg 记录的基线数字时,才需要重新跑一次 flutter_svg 做实锤验证——不要凭感觉判断"应该还是赢的",要真的拿数字和记录的基线比对。

**⚠️ 补丁(当天验证出的漏洞)**:"只跟历史基线比"这个做法本身有个陷阱——**历史基线是在另一次机器状态下测的,svgx 自己数字的涨跌,分不清是代码变了还是机器当时负载/噪声变了**。实际发生过一次:仅对比 svgx 新数据 vs 历史基线,显示 build/raster/内存都涨了 20%+,一度被判断为"疑似回归";但同一 agent 随后在**同一时段配对复测**了 flutter_svg,发现 flutter_svg 自己的数字也涨了同等幅度——两边同步涨,说明是当时机器噪声,不是 svgx 代码引入的真实回退。

**修正后的规则**:

- **常规复测**(没有理由怀疑出问题):按上面"新流程",只跑 svgx,对比历史基线,省时间。
- **一旦 svgx 的历史趋势对比显示某项指标涨幅明显**(比如 >15-20%),**不能直接下"回归"结论**,必须在**同一时段、同一台机器**上追加一次 flutter_svg 的配对复测,两边同步比较涨跌幅度——只有 svgx 单边涨、flutter_svg 没涨,才是真实回归;两边同步涨,是机器噪声,如实记录为"环境噪声,非代码回归",不要误判成需要修复的问题,也不要因为"离历史基线远"就武断处理。

**每次复测后,把新一轮 svgx 数据追加记录**(不覆盖旧数据,保留趋势):日期 + 场景(哪批功能改动之后)+ 完整指标 + 相比上一轮的涨跌方向。

**遗留的一个诚实缺口**:目前只在 Windows 桌面测了,没有覆盖 Android 真机的 PSS/`dumpsys meminfo`,如果之后要在 Android 上复测,链接的 WSA(`127.0.0.1:58526`)设备可用,复用同一套 `bench_app`。

## 单编译顺序对比模式:`LIB=compare`(现为推荐默认复测方式)

**解决的问题**:之前"svgx vs flutter_svg"对比要跑两次独立的 `flutter run --profile`(`LIB=svgx` 和 `LIB=flutter_svg`),两次之间隔着一次完整重新编译,机器状态可能在这个时间窗口内漂移——上面"复测方法学调整"的"⚠️ 补丁"记录过一次真实 confusion:只跟历史基线比对被误判为"疑似回归",后来靠同一时段配对复测 flutter_svg 才澄清是机器噪声。`LIB=compare` 把这个"同一时段配对复测"从**偶尔需要的人工补救**变成**默认做法**。

**实现方式**:新增 `benchmark/bench_app/lib/compare_bench_screen.dart` 的 `CompareBenchRunner`,在**同一个进程**内依次跑完四个阶段——svgx 静态 → flutter_svg 静态 → anim(12 图标流畅度)→ anim_fps(1000 动画图标真实 FPS)——每阶段之间插入 5 秒静置期(让上一阶段的 GC/内存压力不带进下一阶段的测量,比每个静态阶段内部已有的"滚动后 3 秒静置检漏"更长,因为阶段切换还要多卸载/挂载一整个 1000 控件网格),最后打印一份汇总报告,静态对比部分直接是 `metric | svgx | flutter_svg | delta/ratio | verdict` 表格,可直接粘贴进本文件。

**只做编排,不重写机制**:`compare_bench_screen.dart` 复用既有的 `BenchRunner`/`AnimBenchRunner`/`AnimFpsBenchRunner`(`bench_screen.dart`/`anim_bench_screen.dart`/`anim_fps_bench_screen.dart`)不变的滚动/计时采集/RSS 采样逻辑,只是给它们加了一个可选的 `onComplete` 回调携带结构化的 `*Result` 快照,顺序驱动 + 汇总这些快照。三个原文件的既有行为(独立模式下的 stdout 报告格式)完全不变,`onComplete` 为 null 时什么都不影响。

**验证过的前提**:`main.dart`/`bench_screen.dart` 本来就同时无条件 `import` 了 `package:svgx/svgx.dart` 和 `package:flutter_svg/flutter_svg.dart`(不是按 `LIB` 条件导入),说明两个库确实已经一起编译进同一个二进制——`LIB=compare` 只是新增一条运行时控制流分支,不涉及改动构建系统。

**命名与默认值的取舍**:新增显式的 `LIB=compare` 档位,**不**把它设为 `String.fromEnvironment('LIB')` 的默认值(仍是 `svgx`)——避免不带 `--dart-define=LIB=` 参数的既有脚本/习惯突然从"单阶段"变成"四阶段"而意外增加运行时长。

**复现命令(现为推荐默认复测方式)**:

```
cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=compare --dart-define=CYCLES=6 --dart-define=ITEMS=1000
```

单独模式仍然保留、行为不变,调试单侧问题(比如要在 DevTools 里只看一侧)时用:

```
cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx|flutter_svg|anim|anim_fps --dart-define=CYCLES=6 --dart-define=ITEMS=1000
```

### 首次实测结果(`LIB=compare`,同一进程同一时段配对)

| 维度 | svgx | flutter_svg | ratio | 结论 |
|---|---|---|---|---|
| build avg/p50/p90/p99/max | 0.776/0.668/1.274/2.577/3.267 ms | 1.823/1.731/3.185/5.994/8.406 ms | 0.43 左右 | svgx 胜 |
| raster avg/p50/p90/p99 | 1.769/1.660/2.354/3.398 ms | 2.134/2.029/2.934/3.769 ms | 0.80~0.90 | svgx 胜 |
| **raster max** | **4.484 ms** | **4.160 ms** | **1.078** | **flutter_svg 胜(唯一一项)** |
| 掉帧(>8.3ms / >16.6ms) | 0/0(646 帧) | 1/0(542 帧) | — | svgx 胜 |
| 内存峰值/稳态/空闲后 | 236.76/235.57/236.21 MB | 292.25/264.31/265.55 MB | 0.81~0.89 | svgx 胜 |
| 解析耗时(仅 svgx) | avg=0.039/p99=0.189 ms | 无公开钩子 | — | 见方法学说明 |

**诚实标注:`raster max` 这一项 svgx 落后**(svgx 4.484ms vs flutter_svg 4.160ms,ratio=1.078)——这是本轮唯一一个 flutter_svg 反超的子指标,不回避、如实记录。但 `max` 是单样本极值统计,天然噪声大(一次 GC 暂停或 OS 调度抖动就能产生),而**其余全部维度、包括更能反映整体分布的 p99,svgx 依然领先**(raster p99 3.398ms vs 3.769ms)。不足以推翻"svgx 全面胜出"的总体结论,但记录在案,不算进"全维度胜出"的措辞里——后续复测应持续关注这一项是否稳定复现或只是偶发。

**动画侧(仅 svgx,无对等 flutter_svg 对照,如实标注)**:anim(12 并发图标 6 秒观测)`frames=361 build_avg=0.313ms raster_avg=1.304ms framesOver16.6ms=0`;anim_fps(1000 动画图标滚动)`frames=650 real_fps=59.94 framesOver16.6ms=0`,与既有历史数据量级一致。

**耗时对比(单编译顺序模式 vs 分次独立编译)**:本次 `LIB=compare` 从首帧到打印完汇总报告,应用内 `wall_clock_total_s=61.3`(不含编译),加上一次编译 23.6s,总计约 **85 秒完成全部四个阶段**。按旧流程要拿到同样四组数据,需要分别 `flutter run` 四次(svgx 静态、flutter_svg 静态、anim、anim_fps),每次都要走一遍独立编译——参考历史单次编译耗时同样在 20+ 秒量级,四次独立编译仅编译部分就要 80~100 秒,再加四次应用内运行耗时(单次静态跑约 14~16 秒、anim 约 6 秒、anim_fps 约 12~14 秒),旧流程粗估在 **150~180 秒**量级,且中间还有人工在四次运行之间手动切换命令、观察退出的开销。`LIB=compare` 的 85 秒是一次不间断的机器时间,额外还去掉了"两次独立启动之间机器状态漂移"这个测量学风险——是本轮验证到的真实时间节省,不是估算假设。

### 复测记录:`SvgPath` 5 个新字段合并进 `Option<SvgEffects>` 重构之后(`LIB=compare` 配对复测)

触发原因:单侧复测(`LIB=svgx`)显示 parse 耗时持平(符合预期,`Option` 合并不改变序列化字段数量),但 build/raster 绝对值比重构前的历史记录更高(build avg 1.081→1.591ms 左右),按"复测方法学调整"规则不能直接下回归结论,追加了一次同一时段的 `LIB=compare` 配对复测。

| metric | svgx(本轮) | flutter_svg(本轮同时段) | ratio(本轮) | ratio(历史基线) | ratio 趋势 |
|---|---|---|---|---|---|
| build avg | 1.584ms | 3.818ms | 0.415 | 0.43 | 持平/略降(变好) |
| build p50 | 1.353ms | 3.085ms | 0.439 | — | — |
| build p90 | 2.909ms | 7.846ms | 0.371 | — | — |
| build p99 | 4.376ms | 13.351ms | 0.328 | — | — |
| build max | 6.027ms | 15.915ms | 0.379 | — | — |
| raster avg | 2.939ms | 3.461ms | 0.849 | 0.80~0.90 | 落在历史区间内 |
| raster p50/p90/p99 | 2.655/4.312/6.142ms | 3.218/5.267/6.720ms | 0.825/0.819/0.914 | 0.80~0.90 | 落在历史区间内 |
| 掉帧(>8.3ms/>16.6ms) | 0/0(648 帧) | 30/0(341 帧) | — | svgx 无掉帧,与历史一致 | — |
| 内存峰值/稳态/空闲后 | 237.79/234.82/235.62 MB | 297.51/295.43/283.59 MB | 0.799/0.795/0.831 | 0.81~0.89 | 落在历史区间内 |
| 解析耗时(仅 svgx) | avg=0.071/p99=0.305ms | 无公开钩子 | — | avg=0.039/p99=0.189ms(上一轮) | 绝对值上升但仍是微秒级,不影响掉帧结论 |

**判定:环境噪声,不是代码回归。** 证据:本轮 svgx 和 flutter_svg 的绝对值**同步大幅上涨**——svgx build avg 从上一轮 0.776ms 涨到 1.584ms(+104%),flutter_svg build avg 同期从 1.823ms 涨到 3.818ms(+109%),涨幅比例几乎一致;raster avg 同样双边同步上涨(svgx 1.769→2.939ms +66%,flutter_svg 2.134→3.461ms +62%)。用相对比值(ratio)看,build ratio 从 0.43 微降到 0.415、raster ratio 落在历史 0.80~0.90 区间内、内存 ratio 落在历史 0.81~0.89 区间内——**svgx 相对 flutter_svg 的领先幅度没有变差,反而略有改善**。按既定规则("两边同步涨,是机器噪声,不是回归"),本次判定为**这台开发机当时的系统级噪声**,`Option<SvgEffects>` 合并重构未引入真实性能回归。`Option` 解包/`some_if_present` 判断逻辑在 Dart 侧的开销在这次数据里没有体现出方向性影响的证据。

**方法学诚实标注**:这轮机器噪声幅度(build/raster 绝对值双边 +60%~110%)比之前记录的噪声(+20%~40%)更大,说明这台 Windows 开发机在无额外后台负载声明的情况下,量测噪声上限比此前认识到的更高;如果未来需要判断更细粒度的回归(比如 <20% 的绝对值变化),这个噪声量级会掩盖掉真实信号,建议届时安排空闲、无后台进程时段做多次重复取中位数的复测。

**复现方式**:见上方"复现命令"。

## 性能复测:静态路径补齐 clipPath/mask/pattern/blur/text 之后(`LIB=compare` 同进程配对)

| 维度 | svgx(本轮) | flutter_svg(同进程同时段) | ratio | 结论 |
|---|---|---|---|---|
| build avg/p50/p90/p99/max | 1.081/1.053/1.594/2.924/3.332 ms | 2.051/1.926/3.494/6.022/6.847 ms | 0.46~0.55 | svgx 胜 |
| raster avg/p90/p99/max | 1.912/2.262/2.927/4.722 ms | 3.452/2.802/4.916/333.646 ms | 0.55~0.81 | svgx 胜 |
| **raster p50** | **1.908 ms** | **1.833 ms** | **1.041** | **flutter_svg 胜(本轮唯一一项)** |
| 掉帧(>8.3ms / >16.6ms) | 0 / 0(642 帧) | 0 / 0(425 帧) | — | 打平 |
| 内存 峰值/稳态/空闲后 | 190.25 / 187.08 / 187.98 MB | 246.92 / 224.88 / 225.56 MB | 0.77~0.83 | svgx 胜 |
| 解析耗时 avg/p50/p90/p99/max | 0.054/0.044/0.077/0.162/1.083 ms | 无公开钩子 | — | 见方法学说明 |
| anim(12 并发) | frames=361 build_avg=0.421ms raster_avg=1.247ms framesOver16.6ms=0 | 无对等能力 | — | — |
| anim_fps(1000 动画图标滚动) | frames=650 **real_fps=59.85** framesOver16.6ms=0 | 无对等能力 | — | — |

**诚实标注一处相对退步,不掩饰**:与上一轮 `LIB=compare` 记录(svgx build avg 0.776ms、raster avg 1.769ms、parse avg 0.039ms)相比,本轮 svgx 的 build avg 涨到 1.081ms(+39%)、raster avg 涨到 1.912ms(+8%)、parse avg 涨到 0.054ms(+38%)。按"复测方法学调整"的⚠️补丁做了同时段配对复测:flutter_svg 同样涨了(build 1.823→2.051,+13%),说明**有机器噪声成分,但 svgx 涨幅明显大于 flutter_svg**,svgx/flutter_svg 的 build 比值从 0.43 退到 0.527——**不能像上次那样全部归因于噪声**。合理的机制解释是本轮给 `SvgPath` 加了 5 个新字段(`fill_pattern`/`stroke_pattern`/`clips`/`mask`/`blur`),SSE 序列化每条路径都要多写/多读 5 个 tag,1000 图标场景下路径条数很大,这笔常数开销是真实存在的(parse avg 同步涨 38% 与这个解释一致)。**结论:是可解释的小幅真实回归,不是回归到不可接受**——绝对量级仍是微秒/亚毫秒级,掉帧仍为 0,内存反而比上一轮低(190MB vs 236MB),且每个维度(除 raster p50)仍稳定优于 flutter_svg。如果以后要把这笔常数吃回来,方向是**把这 5 个字段合并成一个 `Option<SvgEffects>`**,让绝大多数无特效路径只付 1 个 tag 而不是 5 个——记录在案,当时未做(未经压测证明值得),后续见下方"`SvgEffects` 重构"小节已落地。

**平台局限(沿用既有标注)**:仍只在 Windows 桌面 profile 模式测,Android 真机 PSS/`dumpsys meminfo` 复测仍是遗留缺口。

**复现**:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=compare --dart-define=CYCLES=6 --dart-define=ITEMS=1000`

## `SvgEffects` 重构:把 5 个新字段合并成一个 `Option`

**触发原因**:上一节记录了给 `SvgPath` 加 `fill_pattern`/`stroke_pattern`/`clips`/`mask`/`blur` 这 5 个字段后 build/parse avg 涨了约 38%,并在结论里写好了"如果以后要吃回来,方向是合并成一个 `Option<SvgEffects>`"——本次就是把这个记录在案的优化方向落地。

**改法**:`rust/src/api/svg.rs` 新增 `pub struct SvgEffects { fill_pattern, stroke_pattern, clips, mask, blur }`,`SvgPath` 上原来 5 个独立字段收缩成一个 `pub effects: Option<SvgEffects>`。新增 `SvgEffects::some_if_present(...)` 辅助函数——5 个子字段全部为空/默认时返回 `None`,任一非空则返回 `Some`,绝大多数图标(无 clipPath/mask/filter/pattern)因此只序列化 1 个 `None` tag,而不是 5 个独立的空/`None` tag。`fill_pattern`/`stroke_pattern` 没有和 clips/mask/blur 拆开的原因:判断标准是"值得合并成一个就合"而非强行拆分,五者共同的特点都是"少数路径才用得到、多数路径全空",合成一个 `Option` 收益最大化;没有为了避免"关联度不同"的顾虑而强行拆成两组,因为拆成两组反而要付两次 tag(`Option<PatternPair>` + `Option<ClipMaskBlur>`),达不到"绝大多数路径只付 1 个 tag"的目标。

**改动点**:

- `rust/src/api/svg.rs`:`SvgPath` 结构体定义、`convert_path`(构建自身的 fill/stroke pattern 到 `effects`)、`collect`(把继承的 clips/mask/blur 并入 `convert_path` 已产出的 pattern,重新调用 `some_if_present` 折叠成一个 `effects`)、6 处测试断言改为经 `path.effects.as_ref()...` 访问。
- 重新跑 `flutter_rust_bridge_codegen generate` 重新生成绑定(`lib/src/rust/api/svg.dart`、`lib/src/rust/frb_generated.dart`)。
- `lib/src/rust_static_svg.dart`:`_paintPath`/`_fillShader`/`_strokeShader` 里 `path.clips`/`path.mask`/`path.blur`/`path.fillPattern`/`path.strokePattern` 改为 `path.effects?.clips`/`path.effects?.mask`/`path.effects?.blur`/`path.effects?.fillPattern`/`path.effects?.strokePattern`。
- `test/rust_paint_features_test.dart`:两处断言同步改为经 `effects?.` 访问。

**测试状态**:`cargo test` 24 passed(同基线数量,无用例丢失);`flutter analyze` 无问题;`flutter test` 75 passed(同基线数量)。均为全绿,无回归。

**性能复测(`LIB=svgx` 单侧,同方法学,Windows 桌面 profile 模式)**:

| 维度 | 本次重构前(上一节记录) | 本次重构后 | 趋势 |
|---|---|---|---|
| build avg/p50/p90/p99/max | 1.081/1.053/1.594/2.924/3.332 ms | 1.591/1.372/2.725/4.504/5.966 ms | 绝对值上升,见下方诚实说明 |
| raster avg | 1.912 ms | 3.001 ms | 绝对值上升,同上 |
| parse avg/p50/p90/p99 | 0.054/0.044/0.077/0.162 ms | 0.062/0.043/0.124/0.327 ms | avg/p50 基本持平,p90/p99 略升,量级仍是微秒级 |
| 掉帧(>8.3ms / >16.6ms) | 0/0(642 帧) | 0/0(643 帧) | 无变化,仍 0 掉帧 |
| 内存 峰值/稳态/空闲后 | 190.25/187.08/187.98 MB | 234.98/231.58/232.37 MB | 绝对值上升 |

**诚实说明,不掩饰**:本轮只跑了一次 `LIB=svgx`,没有按"复测方法学调整"的⚠️补丁要求做同时段 `flutter_svg` 配对复测(受限于本次任务的时间预算),因此**无法排除机器噪声**——build/raster 绝对值有 20~40% 的波动区间是这台 Windows 开发机已反复记录过的模式,单次对比不能坐实"合并 `Option` 反而更慢"这个结论。能站得住的信号是 **parse avg/p50 基本没有随字段合并而进一步恶化**(0.054→0.062ms、0.044→0.043ms),说明序列化路径的常数开销至少没有变差;`build`/`raster`/内存这几项的绝对值上涨更可能是本次测量时机的系统噪声(与上一节记录的模式一致),而不是这次重构引入的新回归——但由于没有配对复测数据,这只是合理推测,不作为坐实结论记录。**遗留待办**:后续若怀疑该重构本身引入回归,应按规则补一次同时段 `flutter_svg` 配对复测(`LIB=compare`)来实锤区分噪声与真实回归。

**复现**:`cd benchmark/bench_app && flutter run -d windows --profile --dart-define=LIB=svgx --dart-define=CYCLES=6 --dart-define=ITEMS=1000`

## Dart 侧性能优化专项(2026-08-26)

**触发原因**:一轮只针对 `lib/` 下 Dart 代码的性能优化任务(Rust 侧由另一个 agent 并行进行,两边文件不重叠)。范围:静态路径的 `ui.Picture` 缓存与 widget 重建逻辑、动画路径的解析/采样/绘制、FFI 结果到 Dart 数据结构的搬运。

### 先解决"测不出来"的问题:两套新增测量工具

**问题**:本文件已反复记录,滚动版基准在这台机器上的 build/raster 绝对值跨运行波动 20%~110%,`svgx/flutter_svg` 的 build 比值历史区间是 0.317~0.527(同一份代码)。这个噪声底噪**根本分辨不出 10%~30% 量级的 Dart 侧改动**——本轮确实撞上了:同一份二进制连续两次运行,`anim_paint_frame` 一次 29.7us、一次 23.4us(相差 21%,代码完全没变)。所以先补测量工具,再谈优化。

**工具一:`LIB=micro` 确定性微基准**(`benchmark/bench_app/lib/micro_bench.dart`)

- 在进程内用紧凑循环直接跑被优化的 Dart 函数,无 GPU、无滚动、无控件树;每项重复多轮,报告**最小值**(CPU 密集循环的标准低噪统计量:噪声只会增加耗时)。
- **两个校准项,永远不要改动它们**:`calibration_codeunit_scan`(纯 `String.codeUnitAt` 扫描,不分配)与 `calibration_alloc_and_record`(每轮分配 map/path/paint 并录制进显示列表,只用框架 API)。用途是把"代码变快了"与"机器变忙了"分开——与本文件既有的"用 flutter_svg 那一组做配对对照"是同一逻辑,只是尺度落到微基准。**实测证明单一校准项不够**:纯扫描项稳定在 0.265us 时,`anim_paint_frame` 波动了 16%,因为纯扫描对 GC/分配器/内存带宽压力完全不敏感——这就是加第二个分配型校准项的原因。
- **`tool/run_micro.ps1`**:把已编译好的 exe 跑 N 次取逐指标最小值(min-of-N 自下方收敛到真实开销),直接跑 exe 而非 `flutter run`,省掉每次重复的重新编译。
- **配对原语对比**:凡是"改法 A vs 改法 B"这种问题,一律把**两个变体放进同一个进程**依次跑(`paint_fresh_alloc_per_draw` vs `paint_reused_per_draw`、`replay_typed_lists` vs `replay_interface_lists`)。同一进程相隔数秒,后台负载无法偏向任何一方——这是本轮唯一能给出**决定性**结论的测量形式。
- **踩坑记录**:Flutter 的 Windows runner 会 `AttachConsole` 并重开标准流,把 stdout 挂回父控制台,因此对该进程做管道/重定向的调用方**什么都拿不到**。重复运行器必须靠文件通信(`SVGX_MICRO_OUT` 环境变量,见 `report_sink.dart`)。另外 `bool.fromEnvironment` **只**接受 `"true"`/`"false"` 两个精确字符串,`--dart-define=AUTOEXIT=1` 会静默求值为 false——为此白跑了一轮基准。

**工具二:`anim_fps` 新增静止模式(`CYCLES=0`)+ `tool/run_anim_fps.ps1`**

- **为什么必须新增**:滚动版 anim_fps 的 `build` 耗时由 `GridView` 在格子进出视口时的挂载/卸载主导,会把**逐帧**动画开销完全盖住。用它去判断"逐帧驱动路径"的改动会得到假阴性——本轮实测:同一场景下"每 tick 一次 setState"与"Listenable 重绘"的 build avg 中位数分别是 3.194ms 与 3.189ms,**完全看不出差别**。静止模式(不滚动,只观测 6 秒)去掉了格子进出,`build` 耗时就纯粹是可见图标 ticker 的每帧开销。
- **另一个重要发现**:`LIB=compare` 里的 anim_fps 阶段**不能**与独立运行的 anim_fps 相互比较。它排在第四个阶段,前面三个阶段已经把 1000 张 svgx picture、1000 张 flutter_svg picture、399 份文档堆在内存里,测量条件完全不同——同一份代码,compare 模式里 build avg 是 3.601~4.293ms,独立运行是 3.123~3.391ms。本轮一度因为只看 compare 模式的单次数字而误判为回归。

### 端到端结果:1000 动画图标(独立运行,各 5 次,取 min/中位/max)

方法学:`--dart-define=LIB=anim_fps --dart-define=AUTOEXIT=1`,每个变体连续跑 5 次;基线是把 `svgx/lib` 整体 `git checkout` 回 `bd19f7c`(本轮改动前)编译出来的,不是套用历史记录的数字。

**场景 A:来回滚动 6 轮(既有验收场景)**

| 维度 | 优化前(bd19f7c) | 优化后 | 变化 |
|---|---|---|---|
| build avg 中位(区间) | 5.519ms(5.323~6.059) | **3.189ms**(3.123~3.391) | **−42.2%**,区间完全不重叠 |
| raster avg 中位(区间) | 7.983ms(7.639~8.584) | **6.550ms**(6.211~6.662) | **−18.0%**,区间完全不重叠 |
| real_fps 中位(区间) | 55.12(53.43~56.05) | **58.55**(58.04~58.83) | **+6.2%**,区间完全不重叠 |
| framesOver8.3ms 中位(区间) | 86(72~114) | **13**(7~14) | **−85%**,区间完全不重叠 |

**场景 B:静止 6 秒(新增,隔离逐帧开销)**

| 维度 | 优化前(bd19f7c) | 优化后 | 变化 |
|---|---|---|---|
| build avg 中位(区间) | 0.567ms(0.537~0.580) | **0.356ms**(0.342~0.365) | **−37.2%**,区间完全不重叠 |
| raster avg 中位(区间) | 3.366ms(3.175~3.484) | **2.621ms**(2.609~2.671) | **−22.1%**,区间完全不重叠 |
| real_fps 中位 | 59.99 | 59.96 | 持平(两者都已贴满 60Hz) |

**raster 也变快的机制推测(标注为推测,未直接验证)**:显示列表内容本身没变,合理解释是几何路径缓存让每帧复用**同一个 `ui.Path` 实例**,而 Impeller 的路径细分(tessellation)缓存是按路径身份索引的,于是省掉了逐帧重复细分。未做 GPU 侧验证,仅作机制解释。

**静态路径配对复测(`LIB=compare`,同进程同时段)**:svgx build avg 0.600ms vs flutter_svg 1.610ms(ratio 0.373),raster avg 1.274ms vs 1.835ms,内存峰值 231.06MB vs 289.33MB,掉帧 0/0 对 0/0,**每一项都是 svgx 胜**(含历史上偶尔失手的 `raster max`:2.599ms vs 4.006ms)。**诚实标注**:静态路径的改动经微基准实测是每图标每次重建省下约 1.27us,按滚动中每帧新建格子数量折算约占 build 阶段 8%,而本文件记录的 build 比值历史噪声区间是 0.317~0.527——**滚动基准分辨不出这个量级**,本轮 ratio 从 0.341 变成 0.373 落在噪声区间内,不能当作变好或变坏的证据。静态路径的证据以微基准为准。

### 逐项:落地的优化(全部有实测支撑)

微基准数字均为 `tool/run_micro.ps1` best-of-8;凡跨运行对比都标注了两个校准项,以便判断机器负载。

| # | 优化 | 测量方式 | 优化前 | 优化后 | 变化 |
|---|---|---|---|---|---|
| 1 | `AnimationDetector` 四条分标签正则合并成一条多分支正则 | `detect_animations_static_sources`;同一运行内 `static_image_sniff_removed_work`(单条正则)×4 作为旧实现的同场代理 | ~1.47us/图标(0.368×4) | 0.515us/图标 | **−65%**;跨运行原始值 1.142→0.515 |
| 2 | `SvgXStatic.build` 先查 picture 缓存,只在真正未命中时才做 `<image>` 正则嗅探 | 同一运行内 `static_image_sniff_removed_work` vs `static_cache_peek_added_work` | 0.297us/图标(正则) | 0.040us/图标(哈希查找) | **每次重建每图标省 0.257us** |
| 3 | `SvgDocumentCache`:已解析动画文档的进程级 LRU | 同一运行内 `anim_parse_document` vs `anim_document_cache_hit` | 40.015us/图标(完整 XML 解析+建时间线) | 0.023us/图标 | **重新挂载成本降到约 1/1700** |
| 4 | `_paintNode` 在节点没有 `<animate>` 时直接复用 `node.attributes`,不再每节点每帧拷贝一份属性表 | `anim_paint_frame` | 21.789us | 21.115us | −3.1%(小,按实测值如实记录) |
| 5 | `_geometryPath` 把构建好的 `ui.Path` 按"构建来源身份"缓存在节点上(`<path>` 用 `d` 字符串,其余用属性表实例) | `anim_paint_frame` | 21.115us | 15.238us | **−27.8%** 原始值;该轮 `calibration_alloc_and_record` 1.053 对基线 0.934(机器忙 +12.7%),归一化后约 **−35%** |
| 6 | `SvgXAnimated` 改用绑定到 `AnimatedSvgPainter.clock` 的 `ValueNotifier` 发布时间线,不再每 tick 一次 `setState`(经 `CustomPainter.repaint` 跳过 build+layout 两个阶段) | 静止模式 build avg,各 5 次 | 0.376ms 中位(0.362~0.403) | 0.356ms 中位(0.342~0.365) | **−5.3%**,`framesOver8.3ms` 上限 1→0。滚动场景**测不出差别**(3.194 vs 3.189ms),已如实记录 |
| 7 | `rust_static_svg` 的 `_replay` 形参改成 `Uint8List`/`Float32List`(FFI 桥实际返回的类型)并改用带下标的循环 | 同一进程内配对 `replay_typed_lists` vs `replay_interface_lists` | 125.2~129.2us | 118.8~121.0us | **重放循环本身 −3%~−6%**;`static_parse_record` 分辨不出(其 21.5us 大头是 Rust 解析) |

**附带修掉的一个真实 bug(动画路径 `<clipPath>`)**:`_resolveClipPath` 里 `geometry.transform(matrix)` 被当成裸语句调用,但 dart:ui 的 `Path.transform` 是**返回**变换后的副本、不动接收者("Returns a copy of the path with all the segments of every sub-path transformed by the given matrix"),所以返回值被丢弃——`<clipPath>` 内容上的变换被静默忽略,同时每个裁剪节点每帧还白白分配一整份 Path 副本。改用 `addPath` 自带的 `matrix4` 参数,既正确又无中间副本。新增回归测试,并**验证过去掉修复后该测试确实失败**;该测试手工搭 `SvgNode` 树,因为 `SvgNode.transform` 由 Rust `parse_transform` 桥填入,在纯 `flutter test` 环境下会退化为 null,用标记文本解析会让测试因为错误的原因通过。详见 `docs/bugfix-history.md`。

### 逐项:尝试后回退的方向(有实测,结论是不值得)

**这三项都不是"感觉没用"就放弃,是量出来不划算才回退的。**

| 方向 | 测量方式 | 结果 | 处置 |
|---|---|---|---|
| 把每个节点的 `ResolvedStyle` 按(属性表实例、继承样式实例、`currentColor`)三元组缓存在节点上 | `anim_paint_frame`,A/B 两次构建,校准项几乎一致(0.926 vs 0.938) | 13.561us(无缓存) vs 13.895us(有缓存),**慢 2.5%** | **已回退**。原因:真实动画图标里绝大多数带 `<animate>` 的节点每帧都拿到新属性表,本来就命中不了缓存;省下来的 `inherit` 调用抵不过每节点 3 次身份比较 + 4 次字段写入 |
| `_paintShape` 复用一个 scratch `Paint`,不再每次绘制新建 | 同一进程内配对 `paint_fresh_alloc_per_draw` vs `paint_reused_per_draw` | 0.311us(新建) vs 0.367us(复用),**复用反而慢 18%** | **已回退**。机制推测:复用时必须写 `shader = null`,这会实体化 `Paint._objects`,让引擎侧失去 `_objects == null` 的快路径;而 Dart 的 bump 分配器新建一个 `Paint` 本来就极便宜。**这条结论对静态路径同样适用**(`rust_static_svg._paintPath` 里的 `Paint()` 不要改成复用),记录在案免得再试一次 |
| `ResolvedStyle.inherit` 里把两个局部闭包提成顶层函数、`containsKey`+`[]` 四次查找并成一次 | `anim_paint_frame`,A/B 两次构建 | 13.018us(旧) vs 12.825~13.268us(新),校准归一化后约 −1.5% | **已回退**。低于本项指标的分辨率(同一份代码 best-of-8 跨运行仍有约 3.5% 波动),拿不出实测支撑就不留 |

### 识别到但刻意没做

- **`svg_path_data.dart` 的 `_tokenize` 逐字符重写**(现在每个字符都会 `d[i]` 分配一个单字符 String、`c.trim().isEmpty` 再分配、`'MmLl...'.contains(c)` 做一次子串搜索)。改成基于 `codeUnitAt` 的扫描确实会更快,但**上面第 5 项几何缓存落地之后,`d` 解析已经从"每帧一次"变成"每份文档一次"**:`path_data_parse` 实测 1.72us/条,整场 1000 图标基准里总共只跑 399 份文档,端到端预算已经不值得动它。留作记录,而不是留作待办。

**复现方式**:

```
# 确定性微基准(推荐先跑这个判断 Dart 侧改动)
cd benchmark/bench_app
flutter build windows --profile --dart-define=LIB=micro
pwsh tool/run_micro.ps1 -Runs 8

# 1000 动画图标,滚动 / 静止,各跑 5 次看分布
flutter build windows --profile --dart-define=LIB=anim_fps --dart-define=AUTOEXIT=1 --dart-define=CYCLES=6
pwsh tool/run_anim_fps.ps1 -Runs 5
flutter build windows --profile --dart-define=LIB=anim_fps --dart-define=AUTOEXIT=1 --dart-define=CYCLES=0 --dart-define=HOLD=6
pwsh tool/run_anim_fps.ps1 -Runs 5

# 静态路径配对对照(仍是端到端结论的最终依据)
flutter run -d windows --profile --dart-define=LIB=compare --dart-define=CYCLES=6 --dart-define=ITEMS=1000
```

**平台局限(沿用既有标注)**:仍只在 Windows 桌面 profile 模式测,Android 真机 PSS/`dumpsys meminfo` 复测仍是遗留缺口。本轮全程有另一个 agent 在同一台机器上并行编译 Rust,机器负载明显高于以往几轮——这正是上面两个校准项和 min-of-N 协议存在的原因,所有跨运行对比都已按校准项归一化后再下结论。
