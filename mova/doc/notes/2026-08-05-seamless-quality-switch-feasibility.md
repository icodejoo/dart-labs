# 清晰度无缝切换（bilibili 式）——复杂度预研，不动手实现

**结论先行：可以在不换播放内核的前提下借鉴 ExoPlayer/hls.js 的思路做到，复杂度中等
（量级接近阶段 B/C），核心风险是真机上"要预缓冲多久才够"需要实测调参，不是纯代码
问题。**

## 上次的结论 vs 本次的诉求

上一轮查证（见
[2026-08-04-quality-native-tracks-spike.md](../plans/2026-08-04-quality-native-tracks-spike.md)
附录、[ROADMAP.md](../ROADMAP.md)"技术风险"）确认：mpv/media_kit（以及同门的
ijkplayer）用的 FFmpeg HLS demuxer 是懒加载模型，`setVideoTrack` 本身不会做
ExoPlayer/hls.js 那种"并行预取候选码率分段、在分段边界无感切换"。

用户澄清诉求：**不是要换掉 mpv 换 ExoPlayer/AVPlayer，是要借鉴它们"预取好了再切"的
思路，在现有 media_kit 架构上实现类似效果。**

## 可借鉴的思路：影子引擎预缓冲 + 热切换（不是分段级，是引擎级）

ExoPlayer/hls.js 的无缝切换本质是"新数据已经就位，切换只是把播放头指向新数据"。
mpv 的 Player 不暴露分段粒度的控制，但**mova 项目里已经有一个验证过的同构模式
可以复用**：`lib/src/ui/scope/`（feed 的引擎池）+
`example/lib/spike_dual_engine.dart`——feed 场景里，观众正要划到的下一页视频，
提前在**一个独立的 `MovaEngine`/`Player`**上打开、跑到首帧并停住，用户划过去时直接
展示这个"热"引擎，没有等待感。这个"第二引擎预热+按需展示"的内存代价已经在真机上用
`dumpsys meminfo` 分三阶段测过，SPEC.md 记录为"可接受"（`doc/SPEC.md` 279-284 行）。

**把同一思路搬到清晰度切换**：用户点选清晰度 Q 时，不是原地 `setVideoTrack`，而是：

1. 后台开一个"影子" kernel/Player，打开同一 master playlist，`setVideoTrack(Q)`，
   `seek` 到当前播放位置附近，`autoPlay: false`（或播放但静音，不接显示）。
2. 监听影子引擎的 `buffering`/`position` 流，等它稳定跑到目标位置且不再缓冲
   （类似"预热完成"信号——这是全新逻辑，项目里没有现成的可以直接抄，需要自己定义
   "何时算准备好"的判定，可能要留一点提前量比如 1-2 秒的 lookahead）。
3. 就位后：暂停主引擎，把 `MovaApi.renderHandle` 指向的 `VideoController`
   切换成影子引擎的，恢复播放，销毁旧的主引擎。

## 具体要动的地方（复杂度落点）

- **`MovaKernel.renderHandle`/`MovaApi.renderHandle` 目前是一次性 `late final` 属性**
  （`mpv_kernel.dart:153`、构造期绑死），不是可变/可观察的。要支持热切换，
  `renderHandle` 得能在引擎生命周期中间变更身份，并触发 UI 重建。
  好消息：`lib/src/ui/player.dart` 的 `_RenderSurface` 已经是"每次 build 都重新读
  `api.renderHandle`"（`MovaSelect` 包裹），**不需要重写渲染层**——只需要让
  `renderHandle` 变更时能触发一次现有的重建路径（比如把它纳入触发 `MovaSelect`
  重建的信号里），UI 侧改动比预想的小。
- **`MovaEngine` 需要能同时持有两个 kernel 一小段时间**（当前 kernel + 影子
  kernel），并在切换瞬间把所有转发的流（position/duration/buffer/size/tracks…）
  从"当前生效 kernel"重新指向新 kernel——这是本次改动里最大的一块，属于
  `core/engine.dart` 内部编排逻辑，不涉及公开 API 断裂（`MovaApi` 表面不变，只是
  `switchQuality()` 内部实现换了）。
- **"预热完成"判定**是全新逻辑，类似 `MovaBufferAbr` 但目的相反（判断"已经够顺"
  而非"该降档"），需要新写、新测，且**具体阈值必须真机试**（缓冲多久算够，纯靠
  经验值起步，肯定要调）。
- **资源代价**：切换瞬间有两个解码 session 并存，但只在切换的那一两秒内，比 feed
  引擎池"常驻 N 个热引擎"的稳态代价更低——feed 那次真机测过"可接受"，这次量级更小，
  预计不会是拦路虎，但仍建议真机复测确认。

## 值不值得做

- **好处**：补齐 mova 与主流 App（bilibili/抖音）观感上最后一处明显差距，且是
  真正可以做到的（不是伪需求）。
- **代价**：中等工程量，量级接近阶段 B（拖动预览，15 Task）或阶段 C（直播时移，
  9 Task）——不是小改动，但也不是要重写内核那种大工程。
- **主要风险不是"能不能做"，是"体验调参"**：预热阈值、切换瞬间是否会有一帧跳变/
  音频轻微咔哒声，都要真机反复试才能收敛，可能要来回迭代几轮。

**建议**：如果决定做，下一步是照阶段 B/C 的方式拆一份逐 Task 落地计划（先定
`MovaEngine` 双 kernel 编排的接口形状，再补"预热完成"判定，再接 UI 热切换，最后真机
调参）。这次先停在"复杂度预研"，等用户确认要不要投入再拆计划。
