# 验收条件(测试通过标准)

> 从 `CLAUDE.md` 拆出。这里只放**标准本身**(要达到什么才算过)和**是否已达标的结论性记录**;具体测量数字、每一轮性能复测的详细数据见 `docs/performance-benchmarks.md`,FFI sync/DCO 相关的专项审计见 `docs/ffi-performance-audit.md`。

## 功能验收条件

能够渲染 line-md 的动画对勾并**正常播放描边动画**:

```dart
// 参考用法（iconify 的 Iconify 用 flutter_svg 渲染，不跑 SMIL；
// 本库需能渲染同一段 SVG 字符串并让动画动起来）
import 'package:iconify_flutter/icons/line_md.dart';
// 目标：本库的 Widget 渲染 LineMd.confirm_circle 的 SVG，圆环+对勾描边动画正常播放
```

- 判定:圆环沿描边绘制(约 0.5s)→ 对勾描边绘制(约 0.2s),`fill=freeze` 定格。
- 已知坑:`confirm_circle` 原串组上是 `fill="currentColor"`,会把圆盘填满盖住描边动画,需按 `fill:none` 处理(F fork 里已用 `replaceAll` 修正,可参考)。
- 对照基准:静态渲染性能需追平 `flutter_svg`(F fork 已通过:build/帧 0.68ms、PSS 更低);动画需在真机流畅播放。

**功能验收状态:PASS**。

- **2026-08-25,spike 阶段**:当时是把 F 整包 vendor 进来的临时方案,未做资产分流,见 git 历史。
- **架构正式落地(第一版)PASS,但随后被打回重做**:第一版按资产分流做了:静态走 `rust/src/api/svg.rs` 的 `parse_svg`(usvg 0.44)→ FRB → `lib/src/rust_static_svg.dart` 的 `SvgxStatic`;动画路径当时**直接 vendor 了整份 F 到 `lib/src/fvendor/` 并从 `lib/svgx.dart` 导出**——这违反了 `CLAUDE.md`"硬规则:`lib/` 禁止 vendor 第三方引擎代码",**已被否决**。
- **原创动画引擎重写:PASS**:
  1. `lib/src/fvendor/` 已移出 `lib/`,搬到 `benchmark/baseline_f/full_svg_flutter_lib/`(仅作未来性能对比基准,`analysis_options.yaml` 已排除 `benchmark/**`),`lib/svgx.dart` 不再导出它。
  2. `lib/src/animation/` 下是原创 SMIL 引擎,接入 `svgx_widget.dart` 的 `Svgx.string` 分发,替换掉了 vendor 的 `AnimatedSvgPicture`。
  3. F 已重新定位为 `benchmark/baseline_f/` 下的对比基准,不进 `lib/`。
  4. 功能验收已用原创引擎重新跑过,截图(`benchmark/acceptance_screenshot.png`)确认圆环+对勾正确渲染,`fill="none"` 修正依然生效。

**解析边界(接口缝隙)已验证满足架构决策第 4 条**:唯一解析入口 `SvgDocument parseAnimatedSvgDocument(String source)`(`lib/src/animation/svg_document_parser.dart`),返回纯数据模型(`SvgDocument`/`SvgNode`/`SmilAnimation`,`attributes` 是 `Map<String,String>`),`package:xml` 类型只存在于这一个文件内;`svgx_widget.dart`/`animated_svg_widget.dart`/`animated_svg_painter.dart`/`smil_animation.dart` 都只依赖这个函数的返回值。将来要换 Rust 一次性解析,只需替换这一个函数的内部实现——这是自然设计出来的结构,不是事后补的。

当前引擎具体支持/不支持哪些标签与语法,见 `docs/animation-engine-features.md`(能力清单,以最新状态为准)。

## 性能验收条件(正式落地的硬指标)

在功能验收(动画能播放)之上,追加以下**性能门槛**,任一不满足都不算真正验收通过:

1. **静态渲染必须全面超越 `flutter_svg`**——不是"追平",是每个统计维度都要赢(见下方维度)。只要有一项持平或更差,判定不通过,需要继续优化。
2. **动画性能必须流畅、不得阻塞主线程(UI/Dart isolate)**。
   - **已知架构隐患**:`rust/src/api/svg.rs` 的 `parse_svg` 标了 `#[flutter_rust_bridge::frb(sync)]`——这类 sync FRB 调用会在**调用方的 Dart isolate 上同步阻塞执行**直到 Rust 返回。1000 个互不相同的图标场景下,每个都要走一次真实解析(无法被"相同 source 缓存"抵消),如果解析走的是 UI isolate 的同步调用,极可能就是"阻塞主线程"这条红线的直接触发点。
   - **要求**:`parse_svg` 的 FFI 调用必须验证不阻塞 UI 线程——要么改成 FRB 的异步模式(在独立线程/worker isolate 执行,通过 Future 返回),要么显式把解析派发到 Dart 的 `Isolate.run`/后台 isolate 再桥接 FFI。这是本轮必须验证并按需修正的一点,不能默认当前实现"因为能跑就没问题"。
3. **测试场景**:**1000 个互不相同的图标**,做**来回滚动**(不是同一图标复制 400 份那种能被 Picture 缓存"作弊"的场景——之前 bingo 项目的基准用的是相同图标,这次必须是不同图标,才能压出真实的解析+建 Picture 成本)。
4. **统计维度**(每个维度都要有 svgx vs flutter_svg 的对照数据):
   - CPU 占用
   - 内存占用(峰值 + 稳态)
   - 解析耗时(单图标 + 批量场景下的分布:avg/p50/p90/p99)
   - 渲染耗时(即每帧 build/raster,同上分布)
   - **有无内存泄漏**:反复滚动多轮后强制 GC,内存是否回落到基线,而不是单调增长
   - **GC 是否及时**:GC 暂停频率/时长是否影响帧率,是否有"迟迟不回收导致内存堆积"的现象

**方法学要求**:复用 bingo 项目已验证的基准方法(`SchedulerBinding.addTimingsCallback` 采 build/raster、`top`/`dumpsys meminfo` 采 CPU/内存、profile 模式、force-stop 隔离进程),但样本必须换成 1000 个不同 SVG,且要新增"多轮滚动 + 强制 GC 后测内存"的泄漏检测环节(之前的基准没有这一步)。

5. **新增用例:1000 个动画图标来回滚动,统计真实 FPS**——和"1000 个静态图标"、以及既有的"12 个并发动画"平滑度检查都不是一回事,是单独的重压测场景:
   - **场景**:1000 个**互不相同的、正在播放动画**的图标(不是静态图标,不是同一个动画图标复制 1000 份),放进滚动列表来回滚动,滚动过程中屏幕内可见的图标始终在**并发播放动画**(不是滚到才开始播、滚走就停——除非这本身就是引擎的可见性优化策略,那也要如实说明这一策略生效与否)。
   - **图标来源**:优先用真实的 Iconify 动画图标集(`line-md`/`svg-spinners`/`eos-icons` 等,前面已确认都是纯 SMIL)。如果单一集合凑不够 1000 个不同的,可以合并多个动画集合;如果合并后仍然不够 1000,**如实说明实际拿到多少个真实动画图标**,不要为了凑数字用同一图标改色/改尺寸这种"伪造成不同"的手法——诚实标注比硬凑 1000 更重要。
   - **统计指标:真实 FPS,不是模拟/推算的**。也就是不能用"1000 / 平均帧耗时"这种从均值反推的近似值当结果,必须是**按真实墙钟时间窗口,统计实际渲染完成的帧数**——具体做法:用 `SchedulerBinding.addTimingsCallback` 拿到的每一帧真实时间戳,按 1 秒为一个窗口分桶,数每个窗口里真实落地了多少帧,这才是"真实 FPS"。同时报告 FPS 的分布(avg/min/p1 这种低分位,因为 FPS 的"最差时刻"比平均值更能反映卡顿)。
   - **判定**:这个场景下 svgx 的动画引擎必须能撑住合理的 FPS(不掉到明显卡顿的区间),且要跟 flutter_svg 侧的等价动画渲染方式做对比(如果 flutter_svg 没有直接可比的动画能力,如实说明"无等价对照",不要硬凑一个不对等的对比)。

**性能验收状态:PASS(Windows 桌面 profile 模式实测)**。全部测量数据、每一轮功能改动后的复测记录、方法学演进(`LIB=compare` 单进程配对模式等)见 `docs/performance-benchmarks.md`。FFI sync 阻塞风险的专项结论见 `docs/ffi-performance-audit.md`。
