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

## Rust 侧专项优化(2026-08-26):新增 Rust 微基准 + 三项已落地优化 + 一张 codegen 取舍表

**与本文件其余章节的关系**:上面所有记录都是**端到端 Flutter 基准**(`bench_app`,Dart 侧观测)。这一节是**第一次给 Rust 侧单独装计时**——因为 Dart 侧只能看到一个合并数字(`parse` avg 0.026~0.071ms),分不清里面 usvg 占多少、我们自己的转换代码占多少、FRB 序列化占多少,而"该优化哪里"必须先回答这个问题。两套基准互补,不替代:Rust 微基准定位瓶颈,`bench_app` 验收整体无回归。

### 新增工具:`rust/src/bench.rs`(常驻资产,勿删)

- **位置与门控**:`rust/src/bench.rs`,由 `lib.rs` 的 `#[cfg(test)] mod bench;` 引入——**只在测试期编译,不进入发布的 cdylib**(已用体积实测确认,见下方"体积影响")。
- **运行命令**:

  ```
  cd rust && cargo test --release -- --ignored --nocapture --test-threads=1
  ```

  用 `--release` 是刻意的:据 Cargo 官方 profile-selection 表,`cargo test --release` 走 `release` profile,因此 `opt-level="z"`/`lto=true`/`codegen-units=1` 与分发产物同一套 codegen(唯一例外是 `panic`——官方文档明写 "Tests, benchmarks, build scripts, and proc macros ignore the `panic` setting",测试二进制强制 unwind)。
- **零新依赖,刻意不用 criterion**:criterion 需要把本 crate 当 rlib 链接,就得给 `[lib] crate-type` 加 `"rlib"`,而 **rustc 对 rlib 目标拒绝做 LTO**——那会悄悄废掉 `docs/SIZE_OPTIMIZATION.md` 已落地第 2 项赖以生效的 `lto = true`,并已有他人实测 cdylib 因此翻倍的先例。改用 `std::time::Instant` + 一个 `#[global_allocator]` 计数器,够用。
- **语料**(优先用仓库已有真实资产,不编造):

  | 语料 | 内容 | 用途 |
  |---|---|---|
  | `mdi1000` | 直接从 `benchmark/bench_app/lib/mdi_icons_1000.dart` 读出的 1000 个真实 Iconify `Mdi` 图标 | 与上面各章节同一套语料,主基准 |
  | `effects` | 渐变 + clipPath/mask + pattern/blur 三份 | 覆盖纯图标语料碰不到的特效分支 |
  | `bigpath2000cubics` | 单条 2000 段三次贝塞尔路径 | 把"每点几何成本"从"每文档成本"里剥离 |
  | `maskfanout120x120` | 120 条路径挂在一个 120 条路径的 `<mask>` 下 | 暴露 wire 格式的 O(n×m),见下方专门小节 |

- **输出的四个指标口径**:延迟分位数(µs)、**每次解析的分配次数/字节数**(计数用全局分配器,**完全确定性**——这台机器时间指标噪声 ±10%,分配次数是唯一不受噪声影响的硬信号)、阶段拆分、以及 FRB SSE 线路字节数。
- **`bench_output_fingerprint`(几何输出指纹)**:对语料里每个 verb 字节 + 每个点的 `f32` 原始位做 FNV-1a。**存在的意义是把"几何改动没改变输出"从"测试还过"升级成"逐位一致"**——改几何代码时 stash 前后各跑一次比对即可。

### baseline 实测与阶段归因(优化前,Windows 桌面,release profile,3 次取中位数)

| 阶段 | avg | 占比 | 是谁的代码 |
|---|---|---|---|
| usvg 树构建(`Tree::from_xmltree`) | 9.249 µs | ~65% | **上游 usvg** |
| usvg XML 解析(roxmltree) | 3.108 µs | ~22% | **上游 roxmltree** |
| FRB SSE 序列化 | ~1.0 µs | ~7% | **FRB 生成代码** |
| **我们的树→显示列表转换** | **1.309 µs** | **~9%** | **`rust/src/api/svg.rs`** |
| `parse_svg` 端到端 | 14.193 µs | 100% | — |

**这张表是本轮最重要的产出**:优化前我们自己能改的代码只占 9%,理论天花板就是 9%。所有"再优化 `convert_path`"的直觉都被这个数字限死了。

### 已落地的三项优化(commit `03f33d0`)

| # | 改动 | 机制 |
|---|---|---|
| 1 | `usvg::Options` 用 `OnceLock` 进程级共享,不再每次调用 `Options::default()` | `Options::default()` 每次都堆分配默认 `font_family` String、`languages` Vec 及其中的 String(实测正好 3 次;两个 `image_href_resolver` 闭包不捕获环境是 ZST,`Box` 它们不产生分配)。usvg 把两个 resolver 闭包声明为 `Send + Sync + 'static`,`Tree::from_str` 只读 `Options`,所以共享一份是安全的 |
| 2 | `inject_current_color` 改为按值接收 `String`,三个提前返回路径原样返回;注入路径只分配 1 次 | 原来提前返回要 `data.to_string()` 全量复制,注入路径有 `format!("#{:06X}")` + `format!(" color=...")` + `with_capacity` 三次分配。现在 `with_capacity` 一次给到最终长度,十六进制位查表逐个 push |
| 3 | `append_segments` 直读 tiny-skia 的平行 `verbs()`/`points()` 切片,精确 `reserve`,并把变换形态分派提出每点循环 | tiny-skia 文档写明 `Path` 是 "compact storage, where segment types and numbers are stored separately",点数组顺序恰好就是本 wire 格式要的顺序(move 1 点/line 1 点/quad 2 点/cubic 3 点/close 0 点),因此 `segments()` 迭代器的 last-point/last-move 记账是纯开销;裸切片还能提前按精确长度 reserve,不必让两个 Vec 靠翻倍扩容长大。分派用的是 `Transform::map_points` 内部**同样的四个分支、同样顺序、同样算式**,只是对整个切片做一次而不是每点做一次(原写法每点调一次 `map_points(&mut [pt])`,在 `opt-level="z"` 下还要真付一次函数调用) |

**实测(3 次取中位数)**:

| 指标 | 优化前 | 优化后 | 变化 |
|---|---|---|---|
| convert 阶段 avg(`mdi1000`) | 1.309 µs | 0.410 µs | **−69%** |
| convert 阶段 avg(`bigpath2000cubics`) | 53.710 µs | 16.935 µs | **−68%** |
| convert 阶段 avg(`effects`) | 2.263 µs | 1.393 µs | **−38%** |
| `parse_svg` avg(`mdi1000`) | 14.193 µs | 12.600 µs | −11% |
| `parse_svg` p50(`mdi1000`) | 12.900 µs | 11.700 µs | −9% |
| `parse_svg` avg(`mdi1000` + currentColor) | 16.053 µs | 13.449 µs | −16% |
| `parse_svg` p50(`mdi1000` + currentColor) | 14.700 µs | 12.300 µs | −16% |
| **分配次数/次**(`mdi1000`) | **43.0** | **33.0** | **−10** |
| **分配次数/次**(+ currentColor) | **47.0** | **34.0** | **−13** |
| 分配字节/次(`mdi1000`) | 8996 | 8228 | −8.5% |

**噪声诚实标注**:这台 Windows 开发机的时间指标本轮实测 run-to-run 波动约 ±10%(与本文件已反复记录的模式一致),所以 `parse_svg` 端到端的 −11%/−16% 是"中位数对中位数、且三次 run 全部低于优化前中位数"的方向性结论,**不是**噪声之外可单独坐实的量。真正硬的证据是两个:①**分配次数是确定性的**(43→33、47→34,每次运行数字完全一致);②`convert` 阶段 −69% 幅度远超噪声带,且 `bigpath` 那一档优化前三次读数是 53.47/53.71/53.56(极稳),优化后 15.72/16.94/23.45,不存在解释成噪声的空间。

**几何输出逐位一致,不是"测试还过"**:`bench_output_fingerprint` 在 stash 改动前后打印完全相同的值——`mdi1000` `0x167a0958ca44c27b`、`effects` `0xf9de4655be1b408f`、`bigpath` `0x43cdd2e2268e3aee`。这是刻意做的验证,因为第 3 项改的是几何数值计算路径,单靠 24 个功能测试不足以证明没有 1-ULP 级别的漂移。

**优化后的阶段归因**(说明为什么这条线到此为止):

| 阶段 | avg | 占比 |
|---|---|---|
| usvg 树构建 | 10.142 µs | ~75% |
| usvg XML 解析 | 3.179 µs | ~23% |
| FRB SSE 序列化 | 0.894 µs | ~7% |
| **我们的转换** | **0.441 µs** | **~3%** |
| `parse_svg` 端到端 | 13.592 µs | 100% |

**结论:我们自己那半边已经没有值得做的空间了**(3%)。后续任何"继续优化 `rust/src/api/svg.rs`"的提议,先回来看这个 3%。

**体积影响(同一台机器、同一工具链、优化前后各重建一次的配对对照,不引用历史 MANIFEST 数字)**:

| slice | 优化前 | 优化后 | 变化 |
|---|---|---|---|
| android arm64-v8a | 491,400 | 491,328 | −72 |
| android armeabi-v7a | 338,856 | 338,584 | −272 |
| android x86_64 | 548,792 | 548,480 | −312 |
| android x86 | 572,968 | 572,528 | −440 |
| windows x64 | 446,464 | 446,976 | **+512** |

净效果**体积中性**(Android 四个 ABI 各小了几百字节,Windows 大了 512 字节)。也顺带确认 `bench.rs` 因为 `#[cfg(test)]` 门控确实没进发布产物——否则它那些语料字符串和格式化代码会是 KB 量级的增长。

⚠️ **数据口径提醒**:committed `MANIFEST.json` 里 windows/x64 记录的是 491,008 字节,而在本 worktree 里重建**优化前的同一份源码**只得到 446,464 字节。这 44KB 差异与本次改动无关(优化前就存在),原因未查明(可能是构建时的绝对路径长度/依赖解析状态差异),因此上表 windows 一行**刻意用当场重建的 446,464 作对照组,不用 MANIFEST 里的 491,008**。Android 四个 ABI 不存在这个问题:当场重建优化前源码得到 491,400/338,856/548,792/572,968,与 MANIFEST 记录的 491,384/338,856/548,792/572,968 几乎逐字节吻合(arm64 差 16 字节)。

### `opt-level`:实测取舍全表(**未落地,需要 owner 拍板**)

既然 93%+ 的 Rust 侧成本在 usvg/roxmltree 里,唯一能碰到它们的杠杆是 codegen 参数。`docs/SIZE_OPTIMIZATION.md` 已落地第 2 项把 `opt-level` 定为 `"z"`,当时的理由是"常规 Rust release 体积优化标准做法",**没有留下与 `"s"`/`2`/`3` 的配对实测**。本轮把这张表补齐:

| 配置 | `mdi1000` parse avg | vs `"z"` | arm64-v8a | armeabi-v7a | x86_64 | x86 | 四 ABI 合计 | vs `"z"` |
|---|---|---|---|---|---|---|---|---|
| **`opt-level = "z"`(现状)** | **12.288 µs** | — | 491,328 | 338,584 | 548,480 | 572,528 | **1,950,920** | — |
| `opt-level = "s"` | 8.188 µs | **−33.4%** | 563,984 | 400,452 | 603,888 | 620,000 | 2,188,324 | **+12.2%** |
| `opt-level = 2` | 7.409 µs | −39.7% | 651,048 | 483,252 | 738,648 | 766,416 | 2,639,364 | +35.3% |
| `opt-level = 3` | 7.088 µs | −42.3% | 683,000 | 500,148 | 751,384 | 769,744 | 2,704,276 | +38.6% |

**`"s"` 是帕累托甜点**:−33% 解析耗时只换 +12% 体积,而 `2`/`3` 再多换来的 6~9 个百分点耗时要付 23~26 个百分点体积。

**为什么本轮没有改**:三条理由,都不是"没时间"。①`opt-level="z"` 是 `docs/SIZE_OPTIMIZATION.md` 已落地的决策,本任务范围明确要求"不违反现有体积优化结论";②**收益在当前量级上没有可感价值**——`parse_svg` 现在是 0.0136ms,而本文件已记录 1000 图标滚动 `framesOver16.6ms=0`、`framesOver8.3ms=0`,省下 4µs 落不到任何用户可见指标上,而 +237KB(四 ABI 合计)是实打实要下发的字节;③按 CLAUDE.md"存在多个可行方案时给出选项而非单方面决定"。**如果以后 svgx 的定位变化让首屏解析延迟真的成为瓶颈(例如单次要解析几百个大图、或下沉动画每帧采样到 Rust),这张表就是现成的决策依据,不用重新调研。**

**方法学局限(必须一起读)**:时间列是**宿主 Windows x86_64 + stable 1.96 + 不带 build-std** 的 `cargo test --release` 实测;体积列是**Android 四 ABI + nightly-2026-06-24 + `-Z build-std` + `optimize_for_size`** 的真实产物字节数。**两列的编译配置不同**,所以"时间"这一列不能直接当成 Android 真机上的绝对值,只能当成 `opt-level` 之间的**相对**关系。`-Z build-std-features=optimize_for_size`(已落地第 7 项)对 std 内部实现也有同类的体积/速度取舍,本轮**未**测量——它需要走 build-std 产物 + Dart 侧端到端基准才能量化,记录为未覆盖缺口。

### 按包 `opt-level` 覆盖:实测是死路(已排除,不要重复调研)

既然 93% 的时间在 usvg 里,自然的想法是"只给 usvg 开高优化,别人保持 `z`",用 Cargo 的 `[profile.release.package.<pkg>] opt-level` 做定点打击(已查证:`opt-level`/`codegen-units` 可按包覆盖,`panic`/`lto`/`rpath` **不可**,所以 fat LTO 仍是全局生效)。实测结果是**每一种按包覆盖都被全局 `"s"` 在两个维度上同时压倒**:

| 配置 | `mdi1000` parse avg | vs `"z"` | 四 ABI 合计 | vs `"z"` |
|---|---|---|---|---|
| `[package.usvg] opt-level = 3` | 11.699 µs | −4.8% | 2,250,680 | +15.4% |
| usvg + tiny-skia-path + roxmltree + simplecss + svgtypes 全 `= 3` | 9.939 µs | −19.1% | 2,406,360 | +23.3% |
| `[package."*"] opt-level = 3`(所有依赖) | 7.912 µs | −35.6% | 2,532,088 | +29.8% |
| (对照)全局 `opt-level = "s"` | 8.188 µs | −33.4% | 2,188,324 | +12.2% |

只给 usvg 开 `3` 反而最难看:换来 15.4% 体积,只买到 4.8% 速度——因为 fat LTO 之后 usvg 的热代码早已被跨 crate 内联进别处,单独提高它自己那个 CGU 的优化级别买不到多少东西,却把它的代码膨胀全额付了。**结论:按包覆盖这条路排除,以后不用再试。要动就动全局 `opt-level`,用上一张表决策。**

### `maskfanout` 发现:wire 格式在"多路径 mask"下是 O(n×m)(**已量化,修法需 owner 拍板**)

跑 `maskfanout120x120` 语料(120 条路径挂在一个 120 条路径的 `<mask>` 下)时暴露出一个真实的复杂度问题:

| 指标 | 实测值 |
|---|---|
| `parse_svg` avg | **3,522 µs**(3.5 ms,单个 200×200 的 SVG) |
| 其中 我们的 convert 阶段 | **2,873 µs(82%)** |
| 其中 usvg(XML + 树构建) | 648 µs(18%) |
| FRB SSE 序列化 | 3,890 µs |
| **FRB 线路字节数** | **932,776 字节(0.93 MB)** |
| 分配次数/次 | **31,148** |

**根因在 wire 格式,不在实现**:`SvgPath.effects.mask` 是**每条路径各自拥有一份完整 `SvgMask`**(含该 mask 自己的全部 `paths`),所以 120 条被遮罩路径要深拷 120 份 120 条路径的 mask = 14,400 次路径克隆。Dart 侧同样吃这个亏:它会把同一个 mask 光栅化 120 次。

**本轮的三项优化对这个语料完全无效,如实记录**:优化前 convert 阶段 3,012.9 µs,优化后 3,007.4 µs——**没有改善**,因为这个语料 100% 由深拷主导,而不是由段转换主导。这是"尝试后确认无效"的诚实记录,不是优化成果。

**为什么没有顺手修**:唯一的修法是改 wire 格式——把 mask/clip 提成一张表 + 每条路径存索引。那既能把 O(n×m) 降成 O(n+m)、把 0.93MB 线路字节砍掉一个数量级,又能让 Dart 侧同一个 mask 只光栅化一次。但它**改的是 FFI 契约**,要同步动 `rust/src/api/svg.rs` 的结构体、重跑 FRB codegen、改 `lib/src/rust_static_svg.dart` 的绘制逻辑,并重新走一遍 `docs/animation-engine-features.md` 那 12 项像素级验证。按 CLAUDE.md 的规则(多方案/跨模块改动要先给选项),记录在案不擅自动手。

**这个形状有多现实**:真实图标资产里基本不存在(图标的 mask 通常就一两个形状)。所以这不是"必须立刻修的 bug",而是"已量化的最坏情况上界 + 现成的修法方案"。**真要修的触发条件**:出现真实用户 SVG 落进这个形状并造成可观测卡顿时。

### 测试状态与遗留待办

- `cargo test`(`rust/`):**24 passed**(与基线同数量,无用例丢失),另加 2 个 `#[ignore]` 的基准/指纹用例。
- `flutter analyze`:**No issues found**。
- `flutter test`:**109 passed**。
- ⚠️ **必须的后续动作**:本轮改了 `rust/src/**`,`prebuilt/MANIFEST.json` 的 `sourceHash` 随之变化。本机(Windows 宿主)已重建 android 四个 ABI + windows/x64;**`prebuilt/linux/x64` 与 `prebuilt/linux/arm64` 仍是旧哈希,`dart run tool/check_prebuilt.dart` 因此报 FAIL**——Linux slice 的 `requiresHost` 是 `linux`,物理上无法在 Windows 上构建。合入前必须按 `svgx-prebuilt.yml` 头部注释的既定流程走一遍:手动 dispatch "svgx prebuilt artifacts" workflow → 下载 `svgx-prebuilt` 产物 → 解压覆盖 `svgx/prebuilt/` → `dart run tool/build_prebuilt.dart --restage` → `dart run tool/check_prebuilt.dart` 必须 OK 才提交。windows/arm64 在本机同样无法构建(缺 arm64 `cl.exe` 交叉工具链),同一次 workflow 会一并产出。
- **未复跑 `bench_app` 端到端基准**:按本文件"复测方法学调整"的规则本应补一轮 `LIB=compare`。**没跑的诚实理由不是省事,而是这轮改动的信号量级低于该基准的噪声底**——Rust 侧省下的是 1.6µs(0.0016ms),而 `bench_app` 已记录的 build/raster 绝对值噪声是 ±20%~110%(即毫秒量级),配对复测也分辨不出 0.0016ms。真正能证明这轮改动有效的证据是本节的确定性分配次数与 convert 阶段 −69%。**如果要跑,目的应该是"确认没有引入回归",不是"验证提速"**,且必须用 `LIB=compare` 同进程配对模式。
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

## Dart 侧性能优化第二轮(2026-08-26,`svgx/perf-round-2`)

**范围**:只改 `lib/**` 的 Dart 代码。承接上一节,**刻意不重复**上一节已实测判定"不划算"的三条(ResolvedStyle 三元组缓存、Paint 复用、`inherit` 闭包提顶层)。

### 方法学补强:同进程配对原语成为主要证据

上一节记录的教训在本轮被放大:本机 `LIB=micro` 的**跨构建**读数,即便对**完全没改过的**基准项也会漂移 −3%~+11%,而两个校准项有时会同向移动 12%、有时与其它项脱钩(实测过一次:两个校准项各降 7%,其余十余项却持平)。**结论:校准项能识别"整机变慢",但不足以把 2%~5% 量级的改动归因。**

因此本轮凡是能配对的都配对:把改前实现原样拷进 `micro_bench.dart`(`_dashPathLegacy`、`_parseSvgHexColorLegacy`),两个变体在**同一进程**里相隔数秒跑同一批数据。这套协议自带体检:把库改动 `git stash` 掉重编译后,两条配对臂读数应当重合——实测 `dash_path_legacy_paired` 2.897 vs `dash_path_new_paired` 2.970(+2.5%)、`hexcolor_legacy_paired` 0.100 vs `hexcolor_new_paired` 0.098(−2.0%),**配对测量的噪声底噪约 ±4%**,远小于跨构建漂移。

新增诊断项 `dash_path_current` / `dash_metrics_only`:后者是 `Path.computeMetrics()` 的**不可突破下限**,两者之差才是 Dart 侧能拿回来的部分。改动前实测 2.610 vs 0.655——`dashPath` 有 75% 的余量,这是本轮找到最大金矿的入口。

### 逐项:落地的优化

微基准均为 `tool/run_micro.ps1` best-of-12(本轮把 8 提到 12,min-of-N 又向下收敛约 5%)。

| # | 优化 | 文件 | 测量方式 | 改前 | 改后 | 变化 |
|---|---|---|---|---|---|---|
| 1 | `stroke-dasharray` 解析按原串记忆(`_dasharrayMemo`,上限 256,超限整表丢弃),并把 `split(RegExp)` 换成手写扫描 | `svg_style.dart` | `anim_paint_frame`,校准项 0.974→0.951(几乎持平) | 14.115 | 13.033 | **−7.7%** 原始值,按 `calibration_alloc_and_record` 归一后约 −5.4% |
| 2 | `dashPath` 重写:去掉奇数图案的翻倍列表分配、`fold` 闭包与逐步 `%`;并集路径改为**只在出现第二段虚线时才创建**(揭示式动画每帧只产一段,直接把抽取出的路径交回) | `svg_path_data.dart` | 同进程配对 `dash_path_legacy_paired` vs `dash_path_new_paired` | 2.603 | 2.120 | **−18.6%**(稀疏图案 `[24,24]`);密集图案 `[4,4]` 4.232→3.652 **−13.7%** |
| 3 | `_paintNode` 每节点每帧的常量折叠打包:`clipPathId`/`maskId` 判空短路(省两次 map 查找)、blur 判定提成一个 bool、静态 `transform` 的 4x4 `Float64List` 缓存到节点(`SvgNode.cachedTransformMatrix`)、子节点改下标遍历(省迭代器分配)、`opacity == 1` 时跳过 `Color.withValues` | `animated_svg_painter.dart`、`svg_dom.dart` | `anim_paint_frame`,同一 micro_bench 文件下 stash/还原两次编译各 best-of-12,未改动的参照项漂移 ±2% | 12.536 | 12.273 | **−2.1%**,**刚刚越过分辨率**,如实记录 |
| 4 | `parseSvgHexColor` 改为 `codeUnitAt` 逐位取值,不再 `substring`+`int.parse`(`#RRGGBB` 省 1 次字符串分配,`#RGB` 省 7 次) | `svg_style.dart` | 同进程配对 `hexcolor_legacy_paired` vs `hexcolor_new_paired` | 0.090 | 0.058 | **−35.6%** 单次调用。**在 `anim_paint_frame` 上分辨不出**(12.273→12.404,落在参照项漂移带内),按每文档每帧约 6 次折算约合 0.2us / 1.6% |
| 5 | `AnimationDetector.hasAnimations` 按源串记忆结果(`maximumMemoSize` 默认 1024,FIFO 淘汰) | `animation_detector.dart` | `detect_animations_static_sources`、`static_route_and_lookup` | 0.389 / 0.478 | **0.008 / 0.070** | **−98% / −85%** |

**第 4 项的行为微调**:非法十六进制数字现在返回 null 而不是抛 `FormatException`——与本函数对"长度不合法"本就返回 null 的做法一致,已在注释中标明。

**第 5 项的诚实警告**:这是本轮唯一有**回归风险**的改动。工作集大于 `maximumMemoSize` 且按固定顺序循环访问时命中率为 0(某个源的记录恰好在它再次轮到前被淘汰),此时每次调用要付"扫描 + 一次失败查找",比不加缓存约慢 15%。默认 1024 远高于滚动界面同时在飞的图标数(基准的 1000 个也在其内),但这个失效形态必须记在这里,而不是藏起来。

### 端到端:头对头 best-of-12

把本轮全部 `lib/` 改动 `git stash` 后重编译作为基线,与改后二进制背靠背各跑 best-of-12。**两次运行的机器负载不相等**(基线那次校准项 `calibration_codeunit_scan` 0.261 / `calibration_alloc_and_record` 1.117,改后 0.244 / 0.994),十余个未改动参照项的中位倍率是 **1.13**,下表已据此把基线放缩后再比。

| 指标 | 基线(原始 / 放缩后) | 改后 | 变化 |
|---|---|---|---|
| `anim_paint_frame` | 18.246 / 16.15 | **13.188** | **−18.3%** |
| `detect_animations_static_sources` | 0.458 / 0.405 | **0.008** | **−98%** |
| `static_route_and_lookup` | 0.592 / 0.524 | **0.072** | **−86%** |
| `dashPath`(配对读数) | 2.603 | **2.120** | **−18.6%** |

`flutter analyze`:**No issues found**。`flutter test`:**119 passed**(基线同为 119,无新增亦无减少)。

### 识别到但**没有实测支撑**,因此没做

- **`SvgXStatic._buildFromInfo` 里的 `Directionality.maybeOf(context)`**:`alignment` 是 `Alignment`(默认 `Alignment.center`)时 `resolve()` 根本不看 `TextDirection`,这次 `dependOnInheritedWidgetOfExactType` 既白付了查找与依赖登记,还让每个静态图标白白依赖 `Directionality`。改法只有一行(`alignment is Alignment` 就直接用)。**没做的理由是测不了**:`LIB=micro` 模式没有控件树,现有微基准里没有任何一项会走 `build()`;而滚动基准分辨不出这个量级(上一节已记录)。要落地它得先给 micro 加一个真实 Element 树的探针,那是下一轮的事。
- **`_paintShape` 里每段虚线直接 `drawPath` 而不合并成一条路径**:能再省掉每段一次原生路径拷贝,但会增加显示列表里的绘制指令数,而 raster 侧成本 `LIB=micro` 测不到,不敢在没有 raster 证据的情况下动。
- **`dashPath` 在"整条轮廓都被点亮"时直接返回 `source`**:对已 freeze 的揭示动画每帧都能命中,但闭合轮廓经 `extractPath` 会退化成开放路径,直接返回 `source` 会**改变闭合路径的描边接头外观**——是往更正确的方向变,但仍是行为变化,不在本轮性能任务范围内。

**并行干扰的诚实标注**:本轮全程有另一个 agent 在同一仓库、同一台机器上编辑 `lib/src/animation/svg_document_parser.dart`、`lib/src/rust_static_svg.dart` 并反复编译 bench_app(期间有一次把 `build/` 里的产物换成了 `LIB=anim_fps` 变体,被"报告为空"抓到)。这正是本轮把主要证据从跨构建对比迁移到同进程配对的直接原因。

## 2026-08-27 一轮:真机 1000 并发动画图标,build 瓶颈归因与消除

**背景**:上一轮修掉 `saveLayer(null, ...)` 无界离屏图层的真机黑屏 bug(每帧 2450ms,见 `docs/bugfix-history.md`)之后,`LIB=anim_fps ITEMS=1000` 的瓶颈从 raster 转到了 **build**:raster avg 约 21.8ms,而 build avg 约 34ms,`real_fps` 约 21.9。本轮专门打 build。

### 方法学:真机 logcat 分布,不是单次采样

新增 `benchmark/bench_app/tool/run_android_anim_fps.ps1`。已有的 `tool/run_anim_fps.ps1` 只能跑 Windows exe(靠 `SVGX_MICRO_OUT` 文件),真机上经 `am start` 启动的 activity 设不了环境变量,所以新脚本改从 **logcat 的 `flutter` tag** 抓报告,并逐指标打印 min/median/max。设备:华为 STG-AL00(Android 12,Impeller GLES),`flutter build apk --profile`,每个变体 4–5 次运行。

本阶段噪声实测:同一份代码 4 次运行 `real_fps` 落在约 ±0.35、`build_avg` 约 ±0.6ms。下面凡是小于这个幅度的差异都当作"测不出"处理。

### 归因:第一刀就命中

诊断出的根因是 `SvgDocumentCache` 的容量,而不是绘制代码:语料有 **399** 个互异图标,而缓存上限是 **200**。滚动网格产生的是"按固定顺序循环访问一个大于缓存的工作集"——这正是 LRU 的病态输入,每个条目都恰好在再次被请求的前一步被淘汰,命中率不是偏低而是**恰好为 0**。

先用现成的 `DOCCACHE` 旋钮验证假设,**一行代码都不改**:

| 变体 | build avg | raster avg | real_fps |
|---|---|---|---|
| 基线(上限 200,低于工作集) | 33.96ms | 21.78ms | 21.86 |
| `DOCCACHE=500`(高于工作集) | 20.92ms | 22.40ms | 29.20 |

假设成立。每次未命中的代价不只是重跑 XML 解析,被丢弃的文档还会带走它已经预热好的逐节点几何缓存(`SvgNode.cachedGeometry`),于是下次挂载连图标里每一个 `d` 字符串都要重新解析。

### 逐项:落地的优化(全部为真机 A/B 中位数)

| # | 优化 | 文件 | build avg | real_fps |
|---|---|---|---|---|
| — | 基线 | — | 33.96ms | 21.86 |
| 1 | 文档缓存默认上限 200 → 1000,**且淘汰策略由 LRU 改为随机** | `svg_document_cache.dart` | **21.53ms** | **29.63** |
| 2 | `ResolvedStyle` 按(继承样式 / 属性表 / 主题)三重身份缓存到节点 | `animated_svg_painter.dart`、`svg_dom.dart` | **20.25ms** | **30.00** |
| — | 最终树 5 次运行复核 | — | 20.58ms | 29.64 |

**合计:build avg −39%(33.96 → 20.58ms),`real_fps` +36%(21.86 → 29.64)。**

第 1 项为什么不只是"把上限调大":调大上限只能救开这一套语料,任何用户在新上限处会撞上同一个悬崖。改成随机淘汰才是把悬崖本身铲掉——容量 C 的缓存循环扫描 N 份文档时,随机淘汰大约能留住 C/N,命中率是平滑退化而不是崩到零。而 LRU 的固有优势("最近用过"预测"还会再用")在这里本就没有价值,因为循环里每份文档回来的概率相同。回归防线:`test/animation/svg_document_cache_test.dart` 的 `a cyclic scan larger than the cache still hits (no LRU thrash)`,断言这种访问模式下命中数 > 0(严格 LRU 恰好为 0)。顺带把命中路径上原本为维护 recency 而做的 `remove` + 重新插入去掉了——随机淘汰不看插入顺序,那次记账已无意义。

第 2 项的量级偏小但可判定:两个变体的 build 分布**不重叠**(仅缓存修复 min=20.757ms,叠加样式缓存后 max=20.271ms)。`ResolvedStyle.inherit` 原本每节点每帧都跑一遍约十几次字符串键 map 查找 + 最多四次颜色/url/虚线解析 + 一次对象分配,而真实动画图标里动的是 `stroke-dashoffset` 或某个变换,`fill`/`stroke`/`stroke-width` 恒定不变,所以静态的大多数节点被压成三次 `identical` 比较。

**内存代价**:完整持有 399 份已解析文档而非 200 份,`rss_peak_mb` 中位数 234.79 → 240.94,约 **+5MB**。

### 测了但**没有效果**,因此回滚

- **去掉 `SvgXAnimated.build` 里的逐图标 `RepaintBoundary`**。这次是在瓶颈已经从 build 移到 raster **之后**测的——也就是"逐图标图层正是 raster 耗时元凶"这个假设最有理由成立的时机,不是沿用旧结论。结果全部落在波动内:`real_fps` 30.00 → 30.13,build 20.25 → 20.24ms,raster 21.86 → 21.98ms。**已回滚**,理由记在代码注释里:网格场景显示不出它的收益(所有图标共用一个时钟,本来就同帧全脏),但单个动画图标处在因自身原因重绘的父树里时,去掉它并不免费。这与 flutter_svg 社区的实测一致(dnfield 反复推荐 RepaintBoundary,但 #560 / #111 多人实测对"很多小图标的大列表"无效,只有 #257 的"单个大 SVG 在滚动容器里"确认有效)。

### 识别到但**本轮没做**(如实标注为未验证)

- **`_SharedAnimationClock._onTick` 每帧 `List.of(_listeners)`**:为防迭代中途 unsubscribe 而每帧拷一份约 250 元素的 List。量级估计在几十 us/帧,**低于本基准约 ±0.6ms 的分辨率**,无法用真机 A/B 判定,因此不动——不做没有实测支撑的改动。
- **`_effectiveAttributes` 的 double → String → double 往返**:采样值经 `sampled.toString()` 写进属性表,再由 `ResolvedStyle.inherit` / `_num` 用 `double.tryParse` 解回来。改成数值侧信道会与 `_geometryPath` 依赖"属性表实例身份"做失效判定的机制冲突(见该方法注释里已回滚过的那次教训),需要连带重新设计失效键,超出本轮范围。
- **同一文档多实例共享每帧录制的 `ui.Picture`**(思路来自 vector_graphics 的 `RasterKey(assetKey, width, height)`:把 dpr/尺寸折成整数物理像素进 key,而 colorFilter/opacity 不进 key、改在 paint 时作用于共享产物)。svgx 动画路径要享受它,得让同一文档的所有实例**相位锁定**到同一个 t。本基准显示不出收益(屏上约 160 格取自 399 个互异图标的连续区间,几乎不重复),**因此不实现**——但真实场景(同一个 spinner 在列表里出现几十次)收益会很大,记在这里备查。

### raster 现在是新的墙

最终树 build 20.58ms / raster 21.59ms:**瓶颈已经回到 raster**,`real_fps` 约 29.6 基本就是 raster 21.6ms 决定的。想再往上走必须打 raster 侧,首选目标是带 `<mask>` 的图标每帧仍要开的 `saveLayer`(约 140 个可见图标里约 23 个用 mask;上一轮的 `clipRect` 已经把这些图层从"全屏"收到"图标盒",但没有消掉图层本身)。这不在本轮范围内。

## 2026-08-27 二轮:timeline 归因 + "有损换流畅"的两项降级

**触发**:上一节结尾留下的问题——build 已经打到 20.58ms,raster 21.59ms 成为新的墙,`real_fps` 约 29.6。用户明确授权"为了流畅可以牺牲精度/色彩/动画细粒度",并要求**先用 timeline 摊清每帧成本再决定往哪砸**,优先级是 **绕过 > 降级 > 优化实现细节**。

### 第一步:真机 VM/引擎 timeline 归因(不再靠猜)

工具是已有的 `benchmark/bench_app/tool/capture_timeline.dart`(注意必须用 `fvm dart run`,仓库根的 SDK 语言版本高于 bench_app 允许的上限)。做法:`fvm flutter run -d 7NQBB23606003715 --profile --dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=CYCLES=40`,拿 `flutter run` 打印的 VM Service URL 抓 18s。**注意 VM timeline 是环形缓冲**,18s 只留下最近约 1s(49–51 帧),因此下面的数字是稳态窗口而不是全程累计。

每帧成本(总耗时 ÷ 帧数),按占比排序:

| 环节 | 线程 | 每帧 | 次数/帧 | 说明 |
|---|---|---|---|---|
| `GPURasterizer::Draw` | raster | 21.75ms | 1 | 与 `raster_avg` 22.3ms 吻合,是下面各项的父 slice |
| **`RenderPassGLES::EncodeCommandsInReactor`** | raster | **10.94ms** | **49.4** | 每个约 **221.3µs**,占 raster 约 **50%**,单项最大 |
| `ReactorGLES::Operation` | raster | 11.09ms | 49.4 | 就是上面那批通道的 GL 提交,同源 |
| **`PAINT`** | UI | **17.53ms** | 1 | 占 build 20.77ms 的 **84%**,build 的真正大头 |
| `COMPOSITING` | UI | 1.23ms | 1 | |
| `LAYOUT` | UI | 1.10ms | 1 | |
| `BUILD` | UI | 0.74ms | 66 | 上一轮修完缓存后 widget 层已不是瓶颈 |
| `TexImage2DInitialization` | raster | 0.087ms | 10.9 | **"每帧重复分配纹理"这条嫌疑到此排除**,量级可忽略 |
| `CollectNewGeneration` | UI | — | 4 次共 99.86ms | **单次 25ms**,是抖动尖峰来源(逐帧 Map/Path 分配压力) |

**归因坐实**:`Canvas::saveLayer` 计数 2330 ÷ 49 帧 = **每帧 47.5 次**。语料里 61/399 图标带 `<mask>`(约 140 个可见格 × 15% ≈ 23 个),每个 mask 开 2 层 = 46,加根通道 = 49——与上表的 49.4 个渲染通道完全对上。语料里 `feGaussianBlur` 与 `<clipPath>` 出现次数均为 **0**,所以这一坨渲染通道 **100% 来自 `<mask>`**。

**结论指向"绕过"而非"优化"**:221µs/通道对一个 32×32 图标来说几乎全是固定开销(GLES 下 FBO 绑定 + resolve),与绘制面积无关。**能减的只有通道的"个数",不是每个通道的成本**。同理,UI 侧 17.53ms 的 PAINT 是"每帧把 140 个图标的 display list 重录一遍",省它的唯一办法是**不重录**。

### 第二项降级前先说清:为什么"降采样"能同时打掉这两项

一个图标的 `CustomPaint` 这一帧不脏,框架就不会重录它的 picture(PAINT 直接省掉,**这是确定的**),它的 retained layer 也有机会被复用。于是新增 `SvgXAnimationQuality`(`lib/src/animation/svgx_animation_quality.dart`,已从 `lib/svgx.dart` 导出):

- **降级 1:错相位逐图标跳帧**。并发动画图标数超过 `frameSkipThreshold`(默认 24)后,每个图标每 N 帧才推进一次自己的 SMIL 时间线;普通文档 N=2(60Hz 屏上即 30Hz),需要离屏图层(`mask`/模糊)的文档 N=3(20Hz)。相位由 `_SharedAnimationClock` 连号发放,滚动网格里格子按视觉顺序挂载,于是"这一帧重绘一半、下一帧另一半"自然成立。
- **降级 2:简单 mask 改画成裁剪**。内容只有完全不透明纯黑/纯白填充的 `<mask>` 表达的是二值覆盖区域,而裁剪路径就是二值覆盖区域,于是直接画成 `clipPath`,**该 mask 的两个 saveLayer 一个都不开**。

两项都**只在超过同一个并发阈值后生效**,阈值以内渲染路径与此前完全一致(单图标/少量图标场景零影响);都可以全局 `SvgXAnimationQuality.defaultQuality = SvgXAnimationQuality.exact` 或逐控件 `SvgXAnimated.string(src, quality: SvgXAnimationQuality.exact)` 关掉。

**牺牲了什么,逐项写清**:
- 降级 1 的代价是**时间维度**的:几何/颜色/描边/渐变/mask 覆盖度全部仍然精确计算,像素与以前一致,只是采样点变少。可察觉的是快动画的运动变粗糙(0.2s 的 `stroke-dashoffset` 展开在 30Hz 下约 6 个离散步而非约 12 步)。**没有任何东西位移、变色或消失**。
- 降级 2 的代价是**mask 边界的边缘抗锯齿**:精确管线把光栅化出的覆盖度斜坡乘进内容 alpha,裁剪则对边界本身抗锯齿,Impeller 上两条斜坡略有差异——图标尺寸下是 mask 轮廓上的亚像素差异。会损失更多的 mask(带描边、任何不透明度、非二值/渐变填充、文本、嵌套 clip/mask/模糊)一律被拒,保持精确管线。另外**同时带 mask 与 blur 的节点也被拒**,这是正确性护栏不是性能护栏:裁剪装在画布上会被其下的模糊图层继承,产出 `Blur(Mask())` 而非规范要求的 `Mask(Blur())`。

### 降级 1 的真机 A/B(跨构建,5 次运行取中位数)

设备华为 STG-AL00(Android 12,Impeller GLES),`fvm flutter build apk --profile --dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1`,`tool/run_android_anim_fps.ps1 -Runs 5`。

| 变体 | real_fps | build avg | raster avg |
|---|---|---|---|
| 基线(上一节最终树) | 29.21 | 20.77ms | 22.31ms |
| + 错相位跳帧 | **34.39** | **13.89ms** | 25.66ms |

**`real_fps` +17.7%,build −33%。** build 的降幅与 timeline 的预测一致(PAINT 占 build 84%,少重录约一半图标)。

**raster 反而涨了 15%,不掩饰**:合理解释是帧率从 29.2 升到 34.4 之后单位时间内 GPU 工作量更多、设备更热,而**每帧的渲染通道个数并没有减少**——跳过重绘让 retained layer 被复用,但 Flutter 的 raster cache 的 key 含变换矩阵,滚动中每帧变换都在变,缓存必然失效,所以那 49 个通道照旧每帧重发。这正是必须再做降级 2 的原因:raster 现在是硬上限(25.7ms),而它一半是 mask 通道。

### 降级 2:确定性统计与主机侧成本实测

降级 2 的证据分两层:**确定性主机侧**的覆盖率与 UI 线程成本(本节),以及**真机三臂配对**的端到端净效果(见下方「三臂同二进制配对实测」)。先给主机侧,因为只有它能把「改动本身值多少」与「这台设备上划不划算」分开回答。

**覆盖率**——`benchmark/bench_app/test/mask_eligibility_survey_test.dart`,遍历全部 399 个真实图标:

```
corpus=399 iconsWithMaskedNodes=61 maskDefs=65 eligibleDefs=31
maskedNodeRefs=65 eligibleRefs=31 saveLayersRemovedShare=47.7%
```

**65 个被引用的 mask 里 31 个(47.7%)走裁剪快路径**。被拒的 34 个**全部**因为 mask 内容用了 `stroke` 涂料——dart:ui 没有暴露 stroke→outline 转换,无法把描边变成裁剪路径。这是这条快路径覆盖率的**硬上限,不是实现偷懒**。

**UI 线程成本**——`benchmark/bench_app/test/mask_clip_cost_bench_test.dart`,只取 61 个带 mask 的图标,逐帧推进时间线录制 60 帧,min-of-5:

| 情形 | 61 个文档合计 µs/帧 | 相对精确管线的每文档差 |
|---|---|---|
| 精确 mask 管线 | 1305.2 | — |
| 近似,mask 在动(缓存多数未命中) | 3080.9 | **+29.11µs** |
| 近似,mask 已定格(缓存 100% 命中) | 842.2 | **−7.59µs** |

两个方向都要说清:
- mask **在动**时,近似把工作从 GPU 搬到 CPU——每帧要重建裁剪路径,而重建意味着逐节点分配 4x4 矩阵、把每个形状的线段 `addPath` 复制进并集路径,都是原生开销。**这是净增的 UI 线程成本。**
- mask **定格后**(SMIL 的 `fill="freeze"` 揭示动画都会定格),近似反而**比精确管线更便宜**:一次 `clipPath` 取代了把整个 mask 子树的绘制指令重录一遍。

这个"定格后更便宜"是加了 `SvgNode.cachedMaskClip` **采样签名缓存**之后才成立的:先用一趟廉价的纯采样遍历把子树里所有动画值压成一条扁平签名(不碰属性表、不分配矩阵、不复制路径),签名与缓存路径构建时一致就直接复用。**键必须是采样值而不是时间线位置**——用时间做键会每一帧都未命中。

按 timeline 实测的每渲染通道 221.3µs 折算 raster 侧收益:约 23 个可见带 mask 图标里约 11 个合格,每个省 2 个通道 ≈ **4.9ms/帧**。而 UI 侧代价在这台手机上按主机数字乘以 CPU 差距推算是 1~2ms/帧量级。**方向指向净赚,但这是推算,不是端到端实测**——见下文"未能完成的验证"。

### 降级 2 开发过程中**由微基准抓出的一个真实 bug**(不是性能问题,是崩溃)

`mask_clip_cost_bench_test.dart` 连续扫 60 帧时抛出 `Bad state: Path.combine() failed`。只采样单个固定时刻(最初的覆盖率统计就是这么做的)**暴露不出来**——退化输入只在特定时刻出现(被动画到零尺寸的形状、采样成奇异矩阵的变换、或 `shown` 为空而 `hidden` 非空)。

两处修复:
1. **`Path.combine` 加 try/catch**,失败时退回"不做相减的并集"。理由写在代码注释里:为了一条纯属可选的快路径而让一整帧抛异常是不可接受的;退回方向是保守的(宁可多显示一点,也不要把图标擦掉)。
2. 顺带修掉一个**语义 bug**:`fill="none"` 与 `fill="#000"` 原先被合并成"无覆盖"。两者不同——黑色会在与白色重叠处**去掉**覆盖度,而 `fill="none"` 什么都不画、必须**什么都不改变**。原实现会在每一处 `fill="none"` 轮廓穿过白色区域的地方打出不该有的洞。现在用三态 `_MaskCoverage`(`shows`/`hides`/`paintsNothing`/`notBinary`)区分,回归测试见 `test/animation/mask_clip_approximation_test.dart` 的 `a fill="none" shape in the mask punches no hole` 与 `a mask shape with no fill at all hides, per SVG initial value`。

**这一条值得单独记下的方法学教训**:对"按时间采样"的渲染路径做正确性验证,**必须扫一段连续时间,不能只测一个时刻**。

### 新增的同二进制三臂配对模式(`QUALITYAB=true`)

跨构建对比在本套件里已经反复被证明不可靠(本文件多处记录过 raster_avg 在同一份代码的相邻构建间移动 15% 量级)。但 `--dart-define` 是**编译期**的,一个二进制没法带两组配置——**除非配置是运行时可切的**。而 `SvgXAnimationQuality` 恰好是:`_SharedAnimationClock` 每 tick 都重读画质配置,所以在进程中途翻转 `SvgXAnimationQuality.defaultQuality`,能在下一帧就把已经挂载好的 1000 个图标全部重新调好,**无需任何重挂载**。

于是 `anim_fps_bench_screen.dart` 新增 `--dart-define=QUALITYAB=true`:同一次启动内依次测三臂,每臂一个独立的 `FrameTimingCollector`,报告里以 `arm=<label>` 前缀输出(不带前缀的头条键位置不变,现有脚本不受影响):

| 臂 | 配置 | 隔离出什么 |
|---|---|---|
| `exact` | `SvgXAnimationQuality.exact` | 对照组,两项降级都关 |
| `skiponly` | `approximateSimpleMasksAsClip: false` | 只有跳帧,即 UI 线程 PAINT 的节省 |
| `full` | `SvgXAnimationQuality.balanced` | 出厂默认,叠加 mask 近似的 raster 节省 |

**顺序偏置是保守方向,如实标注**:三臂按 exact → skiponly → full 顺序跑,先跑的臂拿到的是最凉的设备。也就是说温度漂移**偏向对照组、不利于本轮的两项降级**——因此如果 `full` 仍然胜出,这个胜出是可信的。(`ARMFLIP=true` 可以反转顺序,本轮没用上,原因见下。)

**一个踩到的坑,记下来避免再犯**:`const bool.fromEnvironment('X')` 只认字符串 `"true"`,传 `--dart-define=X=1` 会被判为 **false**。第一次三臂运行因此静默退化成单臂(报告里根本没有 `arm=` 行)。本文件早先记录的 `NOCLEAR=1` 用法同样有这个问题,尚未修。

### 三臂同二进制配对实测(4 次干净运行,这是本轮的主证据)

设备华为 STG-AL00(Android 12,Impeller GLES),`--dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1 --dart-define=QUALITYAB=true`,`CYCLES=6`。同一进程内依次测三臂,4 次运行取中位数:

| 臂 | real_fps 中位数 | build avg 中位数 | raster avg 中位数 | 4 次 real_fps 全量 |
|---|---|---|---|---|
| `exact`(不降级,对照) | 29.54 | 20.494ms | 22.100ms | 29.46 / 29.66 / 29.52 / 29.54 |
| `skiponly`(**出厂默认**,仅跳帧) | **34.58** | **14.007ms** | 26.058ms | 34.73 / 33.74 / 34.58 / 34.05 |
| `full`(再叠加 mask 转 clip) | 33.74 | 16.555ms | **23.278ms** | 33.74 / 32.80 / 32.90 / 33.90 |

**降级 1(跳帧)= 本轮的净胜项**:`real_fps` 29.54 → 34.58(**+17.1%**),build 20.494 → 14.007ms(**−31.7%**)。两臂的 `real_fps` 与 `build` 分布**完全不重叠**(exact 最高 29.66 < skiponly 最低 33.74;exact 最低 20.448ms > skiponly 最高 14.352ms),这不是噪声。而且它与另一套独立方法学(跨构建 5+5 次运行,+17.7%)相互印证。

**降级 2(mask 转 clip)= 交易成立,但净效果为微负,因此默认关闭**:
- raster **确实变好**:26.058 → 23.278ms(**−2.78ms**),两臂分布不重叠(skiponly 最低 25.656 > full 最高 23.591)。这与 timeline 的机制预测同向:去掉了 47.7% 的 mask 渲染通道。
- build **确实变差**:14.007 → 16.555ms(**+2.55ms**),同样不重叠。这就是主机侧微基准量到的"每帧重建裁剪路径"成本,在 ARM CPU 上放大后的样子。
- `real_fps` 净效果 34.58 → 33.74(**−2.4%**),4 次里 3 次 `skiponly` 胜出、1 次持平(33.74 vs 33.74)。

**诚实标注顺序偏置**:三臂按 exact → skiponly → full 顺序跑,`full` 排最后、拿到最热的设备,因此这 −2.4% 里含有温度成分,**真实效果可能比 −2.4% 更接近持平**。但"接近持平"依然不足以支撑"默认开启一项有损渲染改动"——把 2.78ms 的 GPU 时间换成 2.55ms 的 CPU 时间,在这台设备上是一笔不赚钱的交易。

**因此的处置**:
- `SvgXAnimationQuality` 的**出厂默认 = 只跳帧**(`approximateSimpleMasksAsClip: false`)。
- mask 转 clip 保留为 **opt-in**:`SvgXAnimationQuality(approximateSimpleMasksAsClip: true)`。它在**另一类设备上可能是赚的**——判据很清楚:如果目标设备的 GPU 相对 CPU 更弱(离屏渲染通道更贵、路径构建更便宜),这笔交易就会翻转。`QUALITYAB=true` 三臂模式就是用来在新设备上重新判定它的现成工具。

### 踩到并修掉的两个测量基础设施 bug(不记下来会反复浪费时间)

1. **logcat 单条消息截断**:把三臂数据块**追加**进头条报告后,整条日志超过 logcat 单条消息上限,末尾的 `=== END ANIM FPS BENCH REPORT ===` 被静默截掉——而所有 harness 脚本都靠这一行判断"跑完了"。后果:**明明跑完并打印了数字的运行被判成超时**,我一度错误地把它归因为"手机被真人占用"(还截图看到前台是购物应用,更加确信了这个错误结论),白白浪费了十几次测量尝试。修法:三臂数据块作为**独立的一条**报告消息发出(带自己的 `=== END ANIM FPS BENCH ARMS ===` 标记),头条报告体积不变,现有脚本全部照旧可用。
2. **`bool.fromEnvironment` 只认 `"true"`**:`--dart-define=QUALITYAB=1` 静默求值为 **false**,第一次三臂运行因此退化成单臂(报告里根本没有 `arm=` 行)。`report_sink.dart` 早就为 `AUTOEXIT` 记录过同一个坑,我还是踩了。现在 `QUALITYAB`/`ARMFLIP` 都改成读 `String.fromEnvironment` 再比对 `'1'`/`'true'`,两种写法都接受。

**教训**:测量工具链本身的失败模式必须能与被测对象的失败模式区分开。"运行没产出结果"当时有两个同样合理的解释(设备被占用 / 脚本判据失效),我先信了前者,而验证后者只需要看一眼 logcat 里 `arm=` 行是否存在——**下次先怀疑自己的判据**。

### 目视验证:三臂截图对比(真机)

用 `--dart-define=QUALITYAB=true` 的三臂二进制截图,靠 AppBar 上的 `[exact]`/`[skiponly]`/`[full]` 标签确认每张图属于哪一臂。

**静止态**(`CYCLES=0 HOLD=14`,所有揭示动画都已定格,同一屏同一批图标):三张截图**肉眼完全一致**——图标形状、位置、粗细、缺口都对得上,没有变形、没有错位、没有丢图标,`[full]` 臂(mask 转 clip 生效)与 `[exact]` 臂看不出差别。这与"损失仅限 mask 边界亚像素抗锯齿"的预期一致。

**运动中**(`CYCLES=6` 滚动,大量图标正处于揭示动画中途):`[exact]` 与 `[full]` 两臂都是正常的 line-md 图标半展开形态——云朵、心形、月亮、箭头等带 mask 的图标轮廓正确,没有出现被裁掉一半、边缘锯齿化、或该显示的部分不显示的情况。滚动位置在两张图之间不同,因此这是"形态与特征一致"的判断,**不是逐像素比对**;逐像素比对由 `test/animation/mask_clip_approximation_test.dart` 在受控条件下完成(远离抗锯齿边界处要求 alpha 完全相等)。

### 测了/查了但**不做**的方向

- **纹理重复分配**:timeline 里 `TexImage2DInitialization` 每帧 10.9 次但只有 0.087ms/帧。**排除**,不是瓶颈。
- **关抗锯齿 / 降 `filterQuality` / 量化颜色插值**:**没有跑 A/B,理由是 timeline 已经说明成本不在那里**——raster 的钱花在 49 个渲染通道的固定建立开销(221µs/个)上,不在片元着色上;`filterQuality` 只对 `drawImageRect` 生效而本语料 `<image>` 数量为 0;颜色插值是 Dart 侧算术,在 17.53ms 的 PAINT 面前不可见。关抗锯齿会让每个图标的边缘都变差(全局画质代价),换来的却是 timeline 指明不存在的收益。**这是基于 trace 的推断,不是实测 A/B**,如此标注。
- **用 `Picture.toImageSync()` 自己把带 mask 的图标缓存成 `ui.Image`**:这是真正能绕开剩下那 34 个 stroke mask 的办法——我们自己按"时间线采样点"做 key,不像 Flutter raster cache 那样把变换矩阵放进 key,所以**滚动中依然有效**。每帧只 `drawImageRect`,渲染通道降到"每 N 帧一个"。**本轮没做**:需要把 devicePixelRatio 传进绘制层、在 `paint()` 里调 `toImageSync` 并管理每图标的纹理生命周期,工程量与风险都不小,而在没有端到端 A/B 窗口的情况下不适合动。**记在这里作为下一轮 raster 侧的首选目标。**
- **把 mask 的 2 个 saveLayer 压成 1 个**:推演过,不成立。精确 mask 必须先把"内容"累积成一层、再把"mask 覆盖度"累积成另一层才能做 `dstIn`;把 `luminanceToAlpha` 下放到 mask 内每个绘制指令上可以省掉内层,但多个内容绘制指令各自 `srcIn` 会互相擦除。只有"内容和 mask 都恰好是单个绘制指令"时才成立,语料里这种情况占比太低,不值得为它加一条特例分支。
- **`_SharedAnimationClock._onTick` 每帧 `List.of`**:仍然保留(上一节已记录量级低于本基准分辨率)。本轮把 `Set` 换成 `List` 后 `unsubscribe` 从 O(1) 变成 O(n),但 n 是"已挂载的动画图标数"(网格里约 150–250),每次卸载几百次指针比较,相对 20ms 帧预算可忽略——**同样没有实测支撑,只是量级判断**。

## 2026-08-27 三轮:把"mask 转 clip"升级成"几何求交,直接画最终路径"

> **状态:已否决,代码已撤销(2026-08-27)。** 不是"默认关闭、开关还留着"——`approximateSimpleMasksAsPathIntersect` 字段、`AnimatedSvgPainter` 里对应的绘制路径(`intersectMasks`/`_paintMaskedContentAsIntersection`/`_resolveIntersectedPath` 等)、`SvgNode.cachedMaskIntersect` 等缓存字段,以及专用测试 `test/animation/mask_intersect_approximation_test.dart`,均已从代码库中删除。下面的真机数据与结论**原样保留**,供以后有人想重新尝试这个方向时直接参考,不必重新测一遍——若要重新实现,基础设施(4 臂/`ARMFLIP` 配平方法学、微基准脚手架)仍在,可以参照本节复现。否决原因见"结论 4":求交在 raster 上确实比 clip 近似更省,但换来的 build 端开销更贵仍旧打不过"只跳帧"的出厂默认方案——真正的瓶颈在 UI 线程(build),不在 GPU 光栅化。
>
> `benchmark/bench_app/test/mask_clip_cost_bench_test.dart`、`benchmark/bench_app/test/mask_eligibility_survey_test.dart` 中原本共用的 intersect 相关测量代码已一并移除,只保留支撑 `approximateSimpleMasksAsClip`(仍在用)与"静态 mask 烘焙"否决结论(`bothFullyStatic=0`)的部分。

**动机(用户原话)**:"mask 不参与绘制,直接解析为最终结果直接绘制。比如一个方块被 mask 以后是五角星,能不能直接算出五角星的点阵路径后,直接绘制五角星,跳过 mask"。

上一轮的 `approximateSimpleMasksAsClip` 只是把两个 `saveLayer` 换成了一次 `canvas.clipPath`——**内容还是照常画一遍,再被裁掉一部分**,显示列表里仍有 `save`/`clipPath`/`restore` 三件套,光栅化时仍要遵守这个裁剪。本轮新增 `approximateSimpleMasksAsPathIntersect`:合格时用 `Path.combine(PathOperation.intersect, 内容几何, mask 几何)` **预先算出最终路径**,然后一次普通 `drawPath` 画出——这一帧里既没有离屏图层,**也没有裁剪**。被五角星 mask 的方块,发出去的就是五角星本身。

### 实现的关键:缓存粒度(这决定它是赚还是亏)

`Path.combine` 是原生布尔运算 + 一次新路径分配,是这条路径上唯一真正贵的一步,而它是纯函数。因此逐叶子形状缓存求交结果(`SvgNode.cachedMaskIntersect`),三个键**全部**参与比较:

| 键 | 比较方式 | 为什么这样够 |
|---|---|---|
| `maskIntersectMaskKey` | 身份(`identical`) | `_resolveMaskClipPath` 在 mask 采样签名不变时返回**同一个** `ui.Path` 实例(上一轮的 `cachedMaskClip`),所以已定格/静止的 mask 在这里只花一次指针比较 |
| `maskIntersectGeometryKey` | 身份(`identical`) | `cachedGeometry` 在形状几何属性不变时保持同一个 `ui.Path` |
| `maskIntersectMatrixKey` | 按值(6 个 double) | `<animateTransform>` 每帧产出新列表,但常常采样出**相同数值** |

上一轮 build 端 +2.55ms 的来源已经查清,**不是"没缓存好"**:主机侧微基准显示,mask 定格(签名缓存命中)时裁剪近似比精确管线**便宜** 6.66µs/图标/帧,而 mask **在动**时贵 28.53µs/图标/帧——贵的那部分是"重建 mask 并集路径"本身,缓存按定义无法消除。求交版本继承了同一条路径并在它之后再加一次布尔运算,所以本轮的预期是"raster 更省、build 更贵",实测也正是如此。

### 主机侧微基准(确定性,61 个带 mask 图标,60 帧,min-of-5)

`benchmark/bench_app/test/mask_clip_cost_bench_test.dart`,相对精确管线的每图标每帧增量:

| 场景 | 裁剪近似 | 几何求交 |
|---|---|---|
| mask 在动(每帧推进时间线) | **+28.53µs** | **+38.80µs** |
| mask 定格(签名缓存 100% 命中) | **−6.66µs** | **−0.96µs** |

即:UI 线程上求交**确实比裁剪更贵**(动态 +10µs、定格时优势从 −6.7µs 缩到 −1.0µs)。这个方向在真机 build 数字上也复现了。

### 覆盖率(确定性统计,真实 399 图标语料)

`benchmark/bench_app/test/mask_eligibility_survey_test.dart` 新增第二项统计:

```
clipEligibleRefs=31 intersectEligibleRefs=31
shapesDrawnAsIntersections=27 intersectShareOfClipEligible=100.0%
```

**裁剪合格的 31 个 mask 引用,100% 也满足求交对内容的要求**(纯色填充、无描边、无渐变)。即在这份语料上求交能完整接管裁剪近似的全部收益,不需要退回裁剪。这不是普遍规律——求交对内容多加了一层条件,所以严格更窄;只是真实图标集里被 mask 的内容恰好都很朴素。

### 真机四臂配对实测(**双向配平**,共 8 次干净运行,这是本轮主证据)

设备华为 STG-AL00(Android 12,Impeller GLES),`--dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1 --dart-define=QUALITYAB=true --dart-define=CYCLES=6`。新增第四臂 `intersect`。

**为什么这次必须配平顺序**:`full` 与 `intersect` 是相邻两臂,预期差异只有 1ms 量级,而上一轮已如实记录"后跑的臂拿到更热的设备"。因此本轮跑了两组各 4 次:正序(`exact → skiponly → full → intersect`)与反序(`ARMFLIP=true`,`intersect → full → skiponly → exact`),下表是 **8 次合并的中位数**。

| 臂 | real_fps | build avg | raster avg |
|---|---|---|---|
| `exact`(不降级,对照) | 29.14 | 21.014ms | 22.579ms |
| `skiponly`(**出厂默认**,仅跳帧) | **34.00** | **13.945ms** | 25.961ms |
| `full`(跳帧 + mask 转 clip) | 32.48 | 17.401ms | 23.191ms |
| `intersect`(跳帧 + mask 转几何求交) | 33.07 | 17.703ms | **22.080ms** |

逐次原始数据(正序 4 次 + 反序 4 次,已排序):

| 臂 | real_fps 全量 | build avg 全量 | raster avg 全量 |
|---|---|---|---|
| `full` | 31.42 / 31.75 / 32.36 / 32.38 / 32.57 / 32.71 / 33.09 / 33.30 | 16.547 / 16.838 / 17.087 / 17.337 / 17.465 / 17.644 / 17.807 / 18.452 | 22.959 / 23.070 / 23.158 / 23.185 / 23.196 / 23.201 / 23.292 / 23.495 |
| `intersect` | 31.76 / 31.83 / 32.22 / 33.04 / 33.10 / 33.40 / 33.67 / 33.83 | 16.897 / 17.113 / 17.129 / 17.495 / 17.910 / 18.006 / 18.264 / 18.361 | 21.575 / 21.644 / 21.884 / 21.990 / 22.169 / 22.406 / 22.459 / 22.597 |

**结论 1:求交在 raster 上确实赢过裁剪,而且是硬信号。** raster 23.191 → 22.080ms(**−1.11ms**),两臂 8 次的分布**完全不重叠**(`full` 最低 22.959 > `intersect` 最高 22.597),且正序、反序**两组各自内部也都不重叠**——顺序偏置无法解释它。机制上说得通:裁剪只去掉了离屏通道,求交把裁剪本身也去掉了。求交的 raster(22.080)甚至已经低于 `exact` 臂(22.579)——也就是说,跳帧引入的那部分 raster 涨幅被完全抵消掉了。

**结论 2:build 上求交比裁剪略贵,但差异落在噪声里。** 17.401 → 17.703ms(**+0.30ms**),分布**重叠**(`intersect` 最低 16.897 < `full` 最高 18.452)。方向与主机侧微基准一致(+10µs/图标/帧),量级也对得上,但这个基准分辨不出它。

**结论 3:因此"求交 vs 裁剪"这一问的答案是:求交更划算,它严格优于上一轮的裁剪近似。** real_fps 32.48 → 33.07(**+1.8%**)。诚实标注:两臂 real_fps 分布**重叠**,+1.8% 本身不是硬信号;能坐实的是 raster 的 −1.11ms(不重叠)配上 build 的 +0.30ms(重叠),即"用一笔量不出来的 CPU 开销换到一笔量得出来的 GPU 节省"。**顺序配平的作用在这里很直观**:正序里 `intersect` 排最后、拿最热的设备,读数是 fps 32.22 / build 18.264;反序里它排最前、拿最凉的设备,读数是 fps 33.67 / build 17.495——单跑正序会得出"求交比裁剪差"的相反结论,单跑反序会得出"求交大胜"的夸大结论,**两组都跑才是真相**。

**结论 4:但求交仍然打不过"只跳帧"的出厂默认,所以默认依旧关闭。** `skiponly` 的 real_fps 34.00 高于 `intersect` 的 33.07,而 `skiponly` 的 build(13.945ms)低了 3.76ms——两臂 build 分布不重叠。1000 图标场景的墙是 build,不是 raster;任何把工作从 raster 搬到 build 的做法在这台设备上都是逆风。

**处置**:
- **出厂默认不变** = 只跳帧(两项 mask 近似都关)。
- 新增 opt-in 开关 `SvgXAnimationQuality(approximateSimpleMasksAsPathIntersect: true)`。
- **要 opt-in 时,推荐用求交而不是裁剪**——同样的合格性前提下它严格更好。两者可同时打开(`approximateSimpleMasksAsClip: true` 一起给),此时求交处理它能处理的、裁剪接住其余的;在本语料上求交覆盖率已是 100%,裁剪只在内容含描边/渐变时才接得到活。
- 判据不变:**若目标设备的墙在 raster 而不是 build**(GPU 相对 CPU 更弱),这两个开关就会翻正,而求交是其中更赚的那个。四臂模式(`QUALITYAB=true`,配 `ARMFLIP=true` 做反序)就是在新设备上重新判定的现成工具。

### 又踩到一次同样的测量基础设施 bug(第三次了,这次彻底修掉)

上一轮把逐臂数据从"追加到头条报告"改成"独立的一整块消息",以躲开 logcat 单条消息截断。**加上第四臂后那一整块也顶过了上限**,截断正好落在第四臂数字中间:`arm=intersect build : ...` 之后就没了,`arm=intersect raster:` 这一行在抓到的日志里**根本不存在**。后果是整整 4 次运行的测量,恰恰在它专门要测的那一臂上拿不到 raster 数字(每次运行只抓到 18 行而不是 20 行,这是发现它的线索)。

修法:改成**逐臂一条消息**(`=== ANIM FPS BENCH ARM <label> ===`),消息大小与臂数无关,再加臂也不会复活。

**教训**:同一个失败模式已经用两种不同形态咬了三次(追加到头条 → 独立整块 → 整块也超限)。前两次的修法都只是"把当前这个块塞回上限以内",治的是症状;这次改成"让消息大小与数量解耦",治的是原因。**遇到第二次出现的同类 bug,应该直接怀疑修法的结构而不是再调一次尺寸。**

### 目视验证:四臂截图对比(真机,静止态)

`--dart-define=QUALITYAB=true --dart-define=CYCLES=0 --dart-define=HOLD=14`,一次启动内每 2 秒截一张共 28 张,靠 AppBar 上的 `[exact]`/`[skiponly]`/`[full]`/`[intersect]` 标签定位臂边界(标签区域的逐帧变化落在第 5、10、16、21 张,即四臂分别对应第 1–4、5–9、10–15、16–20 张)。四臂全程处于同一滚动位置(列表顶部),因此可以直接逐像素比较。

**量化结果**(整个内容区、不含 AppBar 的平均通道差,相对第 1 张 `exact` 帧):

| 帧属于哪一臂 | 相对首张 `exact` 帧的平均差 |
|---|---|
| `exact`(第 1–4 张,**同一臂内部**) | 0.000 / 0.800 / 1.304 / 1.659 |
| `intersect`(第 16–20 张) | 1.092 / 1.281 / 1.167 / 1.535 / 1.485 |

**结论:换臂带来的差异,没有超出同一臂内部帧与帧之间的差异。** 语料里大量 line-md 图标是无限循环动画,静止态下也一直在动,所以任意两个时刻本来就有 0.8–1.7 的平均差;`intersect` 臂的帧落在完全相同的区间内。这不是"逐像素相等"的证明(循环动画下不可能有),而是"求交近似没有引入任何超出动画自身相位差的结构性差异"。

**肉眼对比**(截取 mask 最密集的云朵/杯子那几行,`exact` 帧与 `intersect` 帧上下并排):云朵轮廓、缺口位置、线宽、杯子的开口完全对得上,没有变形、没有镂空、没有错位、没有图标消失。唯一可见的差别是云朵内部上/下箭头的长度不同——那是 SMIL 动画相位,不是 mask 产物。

逐像素严格比对由 `test/animation/mask_intersect_approximation_test.dart` 在受控条件(固定时刻、无循环动画)下完成:五角星 mask 场景要求远离抗锯齿边界的采样点 alpha 与 red **完全相等**。

### 调研并否决:"把 mask 合并交给 Rust 侧 usvg/tiny-skia 在解析期一次性算掉"

**提案**:既然方向已经是"不渲染 mask,而是把它合并进最终路径",那这个合并没必要在 Dart 里自己再写一遍/逐帧再算一遍——直接用 Rust 侧 usvg(或它内部的 `tiny_skia_path`)在解析期算出最终结果交给 Dart,Dart 只负责画路径。

这个提案有两个前提,**两个都被实测否掉了**。

**前提一(可行性):必须存在"mask 定义与被遮罩内容两侧都完全不受时间线影响"的 mask。** 否则不存在唯一的"最终路径"可以烘焙——任一侧每帧在动,预先算好就是错的。确定性统计(`benchmark/bench_app/test/mask_eligibility_survey_test.dart` 第三项,已钉成断言):

```
maskRefs=65 maskDefStatic=10 contentStatic=40 bothFullyStatic=0
```

**65 个 mask 引用里,两侧同时静态的有 0 个。** 分布也很说得通:40 个是"内容静态、mask 在动"(line-md 的揭示动画就是拿动的 mask 去擦静态图形),10 个是"mask 静态、内容在动",两者**没有交集**。机制上这不是巧合——**图标集里的 mask 之所以存在,就是因为它要动**;真要是两侧都不动,作者直接画出最终形状就好了,根本不会写 mask。

这一条已钉成 `expect(bothFullyStatic, 0)`:若哪天语料更新让它非 0,解析期烘焙就值得做,而这个测试会大声失败来通知。

**前提二(收益):必须存在"逐帧重复做、但其实可以只做一次"的合并工作。** 而逐形状求交缓存(`SvgNode.cachedMaskIntersect`,三键比较)已经把所有能合并的帧都合并掉了。同一套件第四项,时间线按 60Hz 推进 60 帧:

```
shapeFrames=1593 combinesActuallyRan=1523 cacheHitRate=4.4%
```

即**逐帧真的重跑 `Path.combine` 的比例是 95.6%,而这 95.6% 全部是"这一帧的几何确实和上一帧不同"**——不是缓存没做好,是内容真的变了。剩下 4.4% 是相邻帧恰好采样出相同数值或动画已定格,已经被缓存吃掉了。**没有任何一部分是解析期能预先算掉的。**

**另外两点澄清,避免以后再绕同一个弯**:

1. **`Path.combine` 不是"我们自己实现的算法"**。`dart:ui` 的 `Path.combine` 直接调用 Skia/Impeller 的路径布尔运算,与 usvg 内部用 `tiny_skia_path` 做的是同一类底层能力,只是换了个引擎入口。所以"用 usvg 就不用自己写一遍"这个动机本身不成立——两边都不是我们写的,区别只在**什么时候算**(解析期一次 vs 每帧),而上面两项数据已经说明"解析期一次"在动画帧上不成立。
2. **"完全静态的 SVG 用 Rust/usvg 把 mask 算掉"这件事早就在做了,而且是默认行为**。`lib/src/svgx_widget.dart` 靠 `AnimationDetector.hasAnimations(source)` 分流:源串里没有 SMIL 标记的文档**根本不会进入 Dart 动画引擎**,而是走 U(Rust usvg)解析 → 显示列表 → Dart 建 `ui.Picture` 缓存那条静态路径,mask 由 usvg 处理并烘焙进缓存好的 `Picture`,每帧零 mask 工作。也就是说提案想要的东西,在它唯一成立的场景(整份文档静态)里已经是现状;Dart 动画引擎里剩下的 mask,**定义上全是带动画的那些**——这也正是 `bothFullyStatic=0` 的结构性原因。

**结论**:方向否决,不投入 Rust 侧改动。运行时逐帧 `Path.combine`(上文 `intersect` 臂)保持为该场景的手段。**注意这不是"懒得做",而是覆盖率实测为 0 且可省工作量实测为 0**——两项都钉进了确定性测试,语料一变就会报警。

## 2026-08-27 准备中:跳帧 + clip 近似组合是否叠加收益(等待真机)

**要验证的假设**:跳帧(降低重画频率)与 mask-转-clip 近似(降低单次重画成本)在设计上正交,组合起来能否把 `skiponly` 单独开启时那个反常偏高的 raster(25.96ms,高于 `exact` 的 22.58ms)压下来,同时不吃掉 `skiponly` 在 build 上的优势。

**重要发现,先纠正一个前提**:着手准备这轮测试时发现,"跳帧 + clip 组合"其实**已经在测过了,只是没有用这个名字**——见上面"三臂/四臂"两轮的 `full` 臂。`SvgXAnimationQuality` 的构造函数里 `adaptiveFrameSkipping` 默认就是 `true`,而 `full` 臂的配置是 `SvgXAnimationQuality(approximateSimpleMasksAsClip: true)`,只覆盖了 clip 这一个字段——也就是说 `full` 从一开始就是"跳帧默认开 + clip 手动开"的组合,不是"只测 clip、不测跳帧"的隔离项。四臂轮真机数据(见上文"真机四臂配对实测"表)已经直接回答了这轮要问的问题:

| 臂 | real_fps | build | raster |
|---|---|---|---|
| `exact` | 29.14 | 21.01ms | 22.58ms |
| `skiponly`(仅跳帧) | **34.00** | **13.95ms** | 25.96ms |
| `full`(跳帧 + clip,即本轮要的"组合") | 32.48 | 17.40ms | **23.19ms** |

也就是说反常假设**部分成立、部分不成立**:组合确实把 raster 从 25.96ms 拉回到 23.19ms(比单独跳帧更接近 `exact` 的 22.58ms,方向支持"跳帧改变了重绘分布、clip 能部分修正"这个猜想),但 build 从 13.95ms 涨到 17.40ms,净 real_fps 反而比只跳帧更低(32.48 < 34.00)——1000 图标场景的瓶颈是 build 而不是 raster,这笔交易在这台设备上依旧不划算,与 `docs` 里"结论 4"的判断一致。

**代码层面的准备(已完成)**:

1. `lib/src/animation/svgx_animation_quality.dart`——**不需要新代码**。`adaptiveFrameSkipping` 与 `approximateSimpleMasksAsClip` 是两个完全独立的构造参数,`frameDivisorFor`/`approximatesMasksAt` 各自只读自己对应的字段,没有任何互斥或"二选一"的硬编码逻辑,`SvgXAnimationQuality(adaptiveFrameSkipping: true, approximateSimpleMasksAsClip: true)` 这种组合本来就能自由构造(`full` 臂事实上就是这么用的,只是没显式写出 `adaptiveFrameSkipping: true`)。
2. `benchmark/bench_app/lib/anim_fps_bench_screen.dart`——`QUALITYAB=true` 模式下新增第四臂 **`combined`**,紧跟在 `full` 之后。它的配置与 `full` 完全一致(两个字段都用 `true` 显式写出,不依赖默认值),目的不是产生新数据,而是给这个组合一个不会被误认成"只测 clip"的独立名字,并作为对 `full` 现有数据的一次同批次复测/交叉验证——如果 `combined` 与 `full` 的结果出现大且可复现的差距,那本身就是新发现(比如四臂之后设备温度漂移更严重),而不是"配置真的不同"。

**主机侧验证结果(已完成,均在开发机上跑,不涉及任何真机/adb)**:

- `fvm flutter analyze`(`svgx` 主包):干净,`No issues found!`。
- `fvm flutter analyze`(`benchmark/bench_app`):1 个错误,`test/widget_test.dart:16` 引用了不存在的 `MyApp` 类——**与本轮改动无关**,是该脚手架测试文件本来就有的历史遗留问题(未被本轮 diff 触碰,`git diff --stat` 确认)。
- `fvm flutter test`(`svgx` 主包):176 个测试全部通过(部分依赖原生 `svgx.dll` 的测试在本机被跳过,是本机没有编译好的动态库导致,与本轮改动无关)。
- `fvm flutter test test/mask_clip_cost_bench_test.dart test/mask_eligibility_survey_test.dart`(`benchmark/bench_app`,主机侧微基准,不需要设备):3 个测试全部通过,数字与既有记录一致(`saveLayersRemovedShare=47.7%`、`bothFullyStatic=0`、mask 在动时裁剪近似 +29.75µs/图标/帧、定格时 −5.69µs/图标/帧)——说明当前代码状态(跳帧默认开 + `approximateSimpleMasksAsClip` opt-in 字段都健在)没有引入逻辑冲突或数值层面的意外变化。

**真机验证还没做**。等真机可用后,直接跑(设备与参数与上面两轮四臂测试保持一致,便于横向比较):

```
--dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1 --dart-define=QUALITYAB=true --dart-define=CYCLES=6
```

即可在同一进程内背靠背跑完 `exact` → `skiponly` → `full` → `combined` 四臂,报告里每臂各有一条独立的 `=== ANIM FPS BENCH ARM <label> ===` 消息(`real_fps`/`build`/`raster` 齐全,不会被 logcat 截断)。若要做双向配平(排除臂序温度漂移),按之前四臂轮的方法再跑一组反序:

```
--dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1 --dart-define=QUALITYAB=true --dart-define=CYCLES=6 --dart-define=ARMFLIP=true
```

**预期与建议**:鉴于 `combined` 与已有 `full` 配置完全相同,预期两者数字在噪声范围内一致,这轮真机测试与其说是"验证新组合",不如说是"确认现有 `full` 结论可复现,并顺带把这个组合的名字理清楚"。若真机确认 `combined` ≈ `full`(32-33 fps 区间,raster 明显低于 `skiponly`、build 明显高于 `skiponly`),则本轮假设已有答案:组合能改善 raster 异常但改善不了净 fps,`skiponly`-only 仍是出厂默认的正确选择,不需要为这个组合专门开新的 opt-in 项。

## 2026-08-27 四轮:否决"跨图标共享 saveLayer",并由此得出一项无损优化(mask 图层按 mask 自身边界分配)

**本轮要验证的提案**(来自"221µs/通道对 32x32 图标而言几乎全是 FBO 绑定/切换/resolve 的固定成本,与面积基本无关"这个前提):网格里的图标彼此不重叠,因此可以把一帧内所有需要 mask 的图标合并进**一对**共享的离屏图层(1 个内容层 + 1 个覆盖度层),用一次 `dstIn` 合成收尾,把每帧约 46-49 次 `saveLayer` 砍到 2 次。

**结论:数学上成立,工程上否决。** 否决的第一位原因是**它赖以成立的成本模型被本仓库自己的实测数据推翻了**。

### 第一步:前提检验——离屏通道的开销是面积主导,不是固定开销主导

两个数字都来自本仓库既有的真机实测(华为 STG-AL00,Impeller GLES),分别写在 `lib/src/animation/animated_svg_painter.dart` 的 `paint` 注释与 `svgx_animation_quality.dart` 里:

| 离屏通道的尺寸 | 单通道耗时 | 来源 |
|---|---|---|
| 图标尺寸(32 逻辑像素盒) | **约 221µs** | 二轮 timeline 归因 |
| 窗口尺寸(黑屏 bug 期间,`saveLayer(null)` + 画布无裁剪导致按整窗分配) | **约 43ms** | 黑屏 bug 的现场实测(56 次 saveLayer → 57 个通道 × 约 43ms ≈ 每帧 2450ms) |

面积比约 320 倍(按屏幕约 1080×2340、dpr≈2.75、图标 32 逻辑像素估算),耗时比约 195 倍。用两点做线性拟合 `cost = fixed + k·area`:

```
k     ≈ 0.017 µs/像素²
fixed ≈ 90 µs/通道
```

也就是说图标尺寸通道的 221µs 里,**约 90µs 是固定开销,约 131µs 是面积开销**——固定开销占比约 41%,并不是"几乎全是固定成本"。据此估算合并方案的收支:

- 省下的固定开销:44 个通道 × 90µs ≈ **−3.96ms**;
- 新增的面积开销:23 个带 mask 图标散布在整个可视网格里,其格子并集≈整个视口,于是 2 个视口尺寸通道 ≈ 2 × 42.9ms = **+85.8ms**,而被它替代掉的 46 个图标尺寸通道的面积开销合计只有 46 × 131µs ≈ 6ms。

**净结果是灾难性的(约 +76ms/帧,比现状差一个数量级)**,方向与提案预期相反。合并的前提"通道数是成本主体"在这台设备上不成立;真正的杠杆是**把每个图层缩小**,而不是把图层合起来。

### 第二步:数学正确性确实成立(实测,已钉成测试)

前提被推翻不等于数学是错的。提案里"不重叠 ⇒ 合并等价"这一条是对的,而且值得留下证据。`test/animation/mask_layer_merge_semantics_test.dart`(纯 dart:ui,不涉及 svgx 代码):

- **互不重叠的 4 个格子**(每个:内容=实心块+对角描边,mask=白圆盘+黑洞+中灰横带),"逐图标各一对图层"与"合并成一对共享图层"两种画法 **100×100 像素逐位一致(0 个像素不同)**。`BlendMode.dstIn` 逐像素、无空间耦合,这一点被实测确认。
- **反向对照:重叠 50% 的 2 个格子**,两种画法 187 个像素不同、最大通道差 255——合并会让每个图标的内容额外被对方的 mask 遮罩。所以任何合并实现都必须在**运行时证明**互不重叠,不能假设。

### 第三步:架构层面的额外阻碍(即使成本模型反过来也要付的代价)

1. **引擎没有可用的图层原语**。`SceneBuilder` 能推的图层只有 offset/transform/clip/opacity/colorFilter/imageFilter/backdropFilter/shaderMask;`ShaderMaskLayer` 的 mask 必须是一个 `Shader`,而这里的 mask 是一棵每帧在动的兄弟子树。**没有"用兄弟子树做遮罩"的合成图层**,因此合并只能发生在**同一次 `Canvas` 录制**里。
2. 同一次录制 ⇒ 必须由一个 RenderObject 画完所有被合并的图标,于是:逐图标 `RepaintBoundary` 的图层保留失效;**跳帧默认值(本轮之前唯一确证有效的优化,29.14 → 34.00 fps)对被合并的图标全部作废**——它们必须每帧一起重录(除非再叠一层逐图标 `ui.Picture` 缓存,复杂度进一步上升)。
3. 协调层需要重新实现框架已经提供的东西:视口裁剪、可见性、z 序,以及图标与协调者之间任何中间图层效果(`Opacity`/`ClipRRect`/`ColorFiltered`/`FadeTransition`……)——这些效果在协调者代替子节点绘制时会被静默丢弃,对发布库是不可接受的失真风险。
4. 对外要多一个"必须把网格包起来"的公开控件(用户不包就无效,包了图标又不再自己绘制),ergonomics 明显变差。

**否决理由排序**:成本模型被实测推翻(致命)> 与跳帧默认值直接冲突 > 需要重造框架能力且会丢中间图层效果 > 公开 API 代价。

### 第四步:顺手排除的另一条路——"每个 mask 从 2 层压到 1 层"

既然"合并"不行,那能不能省掉覆盖度图层,改成在内容图层里直接 `drawPath(mask, dstIn)`?**不行,已实测**(同一测试文件第三项):`dstIn` **绘制**只在自身几何覆盖处参与混合,mask 形状之外的内容根本不会被擦掉——白色 mask 下 10000 个像素里 6998 个不同。覆盖度图层在结构上不可省:只有关闭一个 `dstIn` **图层**才会把混合施加到整个图层面积上。

因此"每个 mask 两个离屏通道"在单图标范围内是**下界**,本轮不再尝试降低通道数。

### 第五步:落地的优化——`tightMaskLayerBounds`(无损,默认开启)

成本模型既然是面积主导,能做且值得做的就是把这两个图层**按 mask 自身边界分配**,而不是 `saveLayer(null, ...)`(等于按当前裁剪区 = 整个 SVG 视口分配)。

**为什么无损**(不是"近似"):

- 内容图层:mask 边界之外的内容头上没有任何覆盖度,`dstIn` 本来就会把它擦掉;
- 覆盖度图层:mask 在自己的边界之外什么都不画。

实现在 `AnimatedSvgPainter._maskLayerBounds`:遍历 mask 子树,逐形状取几何边界并按采样后的静态/动画变换(含 `animateTransform`/`animateMotion`)累积求并。五处刻意保守——`<text>` mask 与 mask 内部任何模糊 → 放弃(回退无界);被遮罩节点自身带模糊 → 根本不进入本路径;带 `style` 或显式 `stroke-miterlimit` 的节点 → 放弃;带描边的几何按 2× 描边宽外扩(覆盖默认 miterlimit=4 的尖角);忽略 mask 子节点自身的 clip/mask(只会缩小);最后整体外扩 2 个逻辑像素吸收边缘抗锯齿溢出。另有一项**精确**的额外收益:mask 覆盖度整体落在可见裁剪区之外时(还没滑进来的揭示 mask),整个被遮罩子树直接跳过,两个离屏通道一个都不开。

**主机侧实测(全部确定性,不涉及真机)**:

- 正确性,合成用例:`test/animation/mask_layer_bounds_test.dart`,23 类 mask(静态/动画几何/dashoffset/`animateTransform` 平移与旋转/`animateMotion`/组变换/描边含继承与 miter/渐变/中灰/黑洞打洞/嵌套 mask/带 clip-path/节点自身带变换/空 mask/`fill="none"`/`<text>`/模糊/`style`)× 4 个时刻 × 2 个渲染尺度,断言"没有任何单像素变化超过光栅噪声"且"整帧总 alpha 不变"。绝大多数用例逐位一致;不一致的两处已追查到成因在离屏缓冲本身而非遮罩结果(黑洞用例洞*内部*边缘 2 个像素差 8/255,属抗锯齿舍入;渐变用例渐变*内部*散布 163 个像素差 1/255,属以缓冲原点为种子的渐变抖动)。
- 正确性,真实语料:`benchmark/bench_app/test/mask_layer_bounds_survey_test.dart`,61 个带 mask 的真实图标 × 4 个时刻 × 32/96 两个尺寸 = **488 次全帧比对,`worstChannelDelta=0`——逐位一致,一个像素都没变**。
- 收益(真实语料,32 逻辑像素渲染,65 个 mask 引用全部拿到有界图层):

```
maskedNodeRefs=65 bounded=65 skippedEntirely=0 indeterminate=0
meanOffscreenAreaShare=78.5%  medianOffscreenAreaShare=87.5%  offscreenAreaRemoved=21.5%
```

即离屏面积平均少 **21.5%**。这个数字远小于"合并"提案预期的量级,原因也很清楚:**真实图标的 mask 本来就覆盖了图标盒的大部分**(中位数 87.5%),离屏面积原本已经接近最小,没有大块面积可省——这同时也是对"合并能省一个数量级"这类直觉的第三次否定。按上面的拟合系数换算,若一帧 46 个通道全在,面积开销约 6ms 的 21.5% ≈ **−1.3ms raster**;跳帧默认开启时实际通道数更少,收益按比例缩小。
- 代价(同一套件第三项,61 个带 mask 文档、60 帧、min-of-5):

```
unbounded=1150.6µs/帧(全部文档)  tight=1398.3µs/帧  delta=+247.7µs  → +4.06µs/图标/帧
```

单独跑该文件复测一次:`delta_us_per_document=4.23`;与其它基准文件并行跑时(测试框架会并发跑多个文件、争抢 CPU)是 5.49。取 **+4.1~5.5µs/图标/帧**。作为对照,已被否决的 clip 近似同口径是 +27.6µs/图标/帧(mask 在动时),本项约是它的 **1/6**。
- 外扩量的取舍:外扩 1 逻辑像素时 `offscreenAreaRemoved=26.0%`(同样 488 次比对全部逐位一致),外扩 2 像素时 21.5%。**保留 2 像素**——多出的 4.5 个百分点不值得动用理论上刚好够用的余量(描边 miter 外扩已经正好卡在 miterlimit=4 的上界)。

**默认值决定:默认开启(`tightMaskLayerBounds: true`),并保留关闭开关。** 依据:等价性已在真实语料 488 次全帧比对上做到逐位一致(不是"看起来一样"),不存在保真度风险;UI 线程代价 +4.1~5.5µs/图标/帧;`SvgXAnimationQuality.exact` 也保持开启,因为它无损、与"精确渲染"不矛盾。开关留给渲染后端层面的意外(某个后端错误地裁剪显式指定 bounds 的图层),不是留给保真度取舍。

**真机验证还没做——净收益(raster 少的是否多于 build 多的)在真机上尚未测量。** 已在 `benchmark/bench_app/lib/anim_fps_bench_screen.dart` 加好专用两臂 A/B(与 `QUALITYAB` 分开,因为这两臂的像素逐位一致,唯一差别只有开销):

```
--dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1 --dart-define=MASKBOUNDSAB=1 --dart-define=CYCLES=6
```

同一进程内背靠背跑 `looselayers`(无界,优化前行为)→ `tightlayers`(出厂默认),报告里每臂一条 `=== ANIM FPS BENCH ARM <label> ===`。反序配平(排除臂序温度漂移):

```
--dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1 --dart-define=MASKBOUNDSAB=1 --dart-define=CYCLES=6 --dart-define=ARMFLIP=true
```

**预期数据**:`tightlayers` 的 raster 应比 `looselayers` 低 0.5-1.5ms(上限来自 −1.3ms 的拟合估算,实际因跳帧使通道数减少而更小),build 高 0.05-0.4ms(约 23 个可见带 mask 图标 × 4.1~5.5µs 主机耗时,按真机 CPU 慢 3-8 倍折算),real_fps 变化在 +0.5 到 +1.5 之间——也就是说**这是一项小幅、方向明确的优化,不是能改变量级的东西**。若真机测出 raster 无差异、或 build 涨幅超过 raster 降幅,应把默认值改回 `false` 并把数据补记到本节。

### 真机验证结果(2026-08-27,vivo V2283A,Android 15)

**注意机型变化**:这次真机验证换到了 vivo V2283A(此前所有轮次的基线数据均来自华为 STG-AL00),两台设备的 GPU 驱动/Impeller 后端表现不可直接比较,下面的数字**只做 vivo 机自身内部的 looselayers vs tightlayers 对照**,不与本文档其它章节的华为基线数字混用。

`--dart-define=MASKBOUNDSAB=1` 同进程两臂,5 次正序运行,中位数:

```
              looselayers   tightlayers   delta
raster avg     15.177ms      14.794ms     -0.38ms  (5次全部 loose > tight,两组分布完全不重叠)
raster max     26.685ms      24.693ms     -1.99ms  (两组有重叠,不是硬信号)
real_fps       56.90         56.64        基本打平,无提升
```

**结论**:raster 平均值改善是真实、稳定的信号(5 次独立运行方向一致且分布不重叠,与主机侧微基准 +4.1~5.5µs/图标/帧的预期方向吻合)。但 vivo V2283A 的 real_fps 没有被 raster 卡住(该机型性能明显强于华为 STG-AL00,~57fps 已接近该场景在此机型上的上限,瓶颈显然不在 mask saveLayer),所以 raster 端的改善没有传导到最终 fps 数字上——这与华为机上"raster 是主要瓶颈之一"的定性并不矛盾,只是不同机型的瓶颈分布不同。

早期两次单独运行(未纳入上面 5 次统计)曾观测到 looselayers 的 raster max 达到 45.3ms 和 87.1ms(远高于 tightlayers 同期的 21.9/25.7ms),一度以为是稳定的"消除卡顿尖峰"效应,但正式的 5 次连续测量未能复现如此大的峰值差距(两组 max 分布有重叠)——如实记录:那两次极端值更可能是测量噪声/设备热状态波动,不作为本项优化的确定收益宣称。

**决定:保留 `tightMaskLayerBounds` 默认开启**——它是等价性已验证(488 次全帧比对逐位一致)的无损优化,即使在这台设备上尚未在 fps 层面体现收益,也没有下行风险,维持默认值不变。

## 调研并否决:定格图标位图缓存(2026-08-27)

**假设**:399 个真实图标语料里 1458 处 `fill="freeze"` 对 58 处 `repeatCount="indefinite"`,绝大多数图标 0.2~0.5 秒播完就永久定格,之后仍每帧重跑整套矢量绘制(含 mask 的 saveLayer)——把定格后的画面一次性 `Picture.toImageSync` 成 `ui.Image`,之后 `drawImageRect` 替代,理论上能省掉这部分冗余开销。

**在独立 worktree 实现并用主机侧探针实测后,否决**:这条优化在当前动画引擎架构下是**净成本**,不是收益,原因是它想省的开销**本来就已经是零**:

- 图标一旦定格,`_stopTicking()` 让时钟不再前进,`shouldRepaint` 全部返回 `false`,`RepaintBoundary` 又隔离了祖先重绘——实测(含"父级每帧改 Opacity + 20 图标 ListView 关闭 RepaintBoundary"这种刻意制造重绘压力的场景)定格后图标的矢量绘制调用次数在 30 帧内稳定为 **0 次**。
- 而位图缓存本身的建立(录制 + `toImageSync`)有实打实的成本:主机侧微基准测得带 mask 文档、32×32 @DPR3 下 `vector_paint=26µs`、`snapshot_create=171µs`、`blit_hit=7µs`——建一次快照的成本相当于 6~7 次矢量绘制,必须被后续至少 9 次命中摊薄才回本。
- 但滚动网格场景里图标持续被卸载重挂载,每次重挂载都会从 `_elapsed = Duration.zero` 重新播放整段动画(`_parseAndStart`),重播期间不算"已定格",缓存永远等不到那 9 次命中——真机上 GridView 里的图标近乎不会稳定停留到能吃到这项优化的程度。
- 结论:**当前架构下,已定格图标每帧成本本来就是 0,给"已经免费的东西"建缓存只会倒贴一次快照成本,不会有任何运行时收益。**

**真正能吃到 1458:58 这个语料统计红利的方案**(未实现,是语义变更,需要显式决策):让"重新挂载且缓存里已有该图标定格快照"的情况**直接以定格终态起画**,跳过整段重播——这样才能命中"1000 格网格反复进出视口"这个真实成本大头(build 端的 GridView churn,不是 raster 端的 mask saveLayer)。代价是滚动划出去再划回来的图标不会重新播放揭示动画,视觉行为发生改变,不再是纯粹的"结果不变、只是变快"的优化,而是要用户明确认可的行为取舍。**本轮未实现此方案,留待后续按需评估。**

对应实现代码保留在独立 worktree(`svgx-frozen-bitmap` 分支)供参考,**未合并进主分支**——因为按当前设计,合并只会引入无收益的额外开销。

