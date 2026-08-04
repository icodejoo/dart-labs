# videoman 播放列表 + 下一集卡片 + 广告 —— 实现计划

**Goal:** 补三个应用级能力——**播放列表**（顺序换集）、**下一集卡片**（临近结束提示并可自动续播）、
**广告**（前/中/后贴片，可跳过倒计时、可点击跳转）。三者都作为**可选一方插件**架在现有原语上
（overlay 槽 / 拦截链 / 事件流 / 回调），**不进 core 的必经路径**，默认关闭。

**决策依据：** 2026-08-04 与 playora 对比后，用户选定三个全做（先播放列表+下一集，再广告）。videoman
已在往"内置但可插拔"走（弹幕/点赞/feed 皆此路），这三个顺理成章。

**与 feed 引擎池是两回事：** feed（`core/feed/`）是"上滑换视频"、多引擎并行；播放列表是"顺序换集"、
单引擎顺序 `open()`。别复用 feed 的引擎池。

**Tech Stack:** Dart / Flutter、现有 media_kit 栈。**播放列表/下一集不新增依赖；广告点击跳转需
`url_launcher`——新依赖，落地前需用户正式确认**（见 Part B 的 ⚠️）。

**现有可复用原语（读代码确认）：**
- `VmSlot.overlay`（`ui/slots/slot.dart`）——不受锁定/自动隐藏门控，弹幕已用。
- `VmComponent` + `VmSelector` / `VmPlugin`（`ui/`）——出组件、按状态重建、副作用订阅。
- `VmInterceptor{beforeOpen,beforeSeek,beforePlay,onError}` + `VmInterceptorChain`（`core/interceptor/`）。
- 事件：`VmCompleted` / `VmSourceChanged` / `VmDurationChanged`（`core/events/events.dart`）；progress 流带 position。
- `VmOptions` 分节 + `copyWith`（`core/options/options.dart`）——新增配置各占一节。

---

## Part A：播放列表 + 下一集卡片（先做，风险最低）

**架构：** core 出一个纯 Dart 的 `VmPlaylistController`（无 Flutter 依赖、可单测）+ `VmPlaylistConfig`
（`VmOptions.playlist` 新节）；ui 出 `NextUpComponent`（挂 `VmSlot.overlay`，按 position/duration 阈值现身）。
换集 = 控制器调 `api.open(nextSource)`；不持有业务数据，剧集元数据由宿主给。

- [x] **A1 模型 + 配置**（2026-08-04）：`core/model/playlist.dart` 的 `VmPlaylistItem{source, title?, subtitle?,
  poster?}`（附 `displayTitle` getter）；`core/options/playlist_config.dart` 的 `VmPlaylistConfig{enabled=false,
  items=const[], initialIndex=0, autoPlayNext=true, nextUpLeadTime=Duration(seconds:10)}`。接进 `VmOptions`
  新节 + `copyWith` + `==/hashCode` + `options.dart` export/import。**`onItemChanged` 回调改为控制器的
  `indexChanges` 流**——放配置里会破坏 `==` 值语义，用流更干净。
- [x] **A2 控制器**（2026-08-04）：`core/playlist/playlist_controller.dart` 的 `VmPlaylistController`——持当前
  下标、`next()`/`previous()`/`jumpTo(i)` 调 `api.open()`，`hasNext`/`hasPrevious`/`currentItem`/`nextItem`/
  `previousItem` getter + `indexChanges` 流。纯 Dart（无 Flutter，守 `purity_test`），注入 `VmApi`。
  `playlist_controller_test.dart` 12 项：seed/clamp、next/prev 边界、jumpTo 越界、indexChanges、dispose 后不响应。
- [x] **A3 自动续播**（2026-08-04）：控制器订阅 `api.events` 的 `VmCompleted`——`autoPlayNext && hasNext` 时
  自动 `next()`。单测覆盖：自动前进、关掉不前进、末集不回绕、dispose 后不响应。
- [x] **A4 下一集卡片组件**（2026-08-04）：`ui/components/next_up.dart` 的 `NextUpComponent(controller)`
  （`VmSlot.overlay`）——`VmPlugin` mixin `bind(api.progress)`，`duration - position <= nextUpLeadTime &&
  hasNext && !dismissed` 时淡入卡片（下一集标题/副标题/封面 + "立即播放"/"取消"），点立即播放调
  `next()`、取消置本项 dismissed，`indexChanges` 切项时重新武装。文案走 `VmStrings`（新增 `nextUp`/`playNow`/
  `cancel`）。`next_up_test.dart` 5 项：禁用不渲染、远端隐藏、进窗现身、立即播放换源、取消不复现。
- [ ] **A5 皮肤挂载 + example**：默认皮肤不强制挂（已确认，保持精简）；宿主经 `VmPatch.add(VmSlot.overlay,
  NextUpComponent(controller))` 或自行组树挂载。**example 的 3 集播放列表 demo 待补**（本轮未做）。
  全量 `flutter analyze` 0 + `flutter test` 422 项已过。

## Part B：广告（后做）

**架构：** `VmAdConfig`（`VmOptions.ads` 新节）描述 pre/mid/post 贴片；一个 `VmAdController` 用
`VmInterceptor.beforePlay` 门控正片（pre-roll 未放完不让播）+ 订阅 progress 触发 mid-roll；
`AdOverlayComponent`（`VmSlot.overlay`）出倒计时/跳过/点击跳转。广告播放期间 `suspend` STT/analytics 类副作用。

- [x] **B1 模型 + 配置**（2026-08-04）：`core/model/ad.dart` 的 `VmAdBreakKind{pre,mid,post}` + `VmAdBreak
  {kind, source, offset, skippableAfter?, clickThroughUrl?}`（offset 仅 mid 有意义）+ `VmAdEventType
  {started,completed,skipped,clicked}` + `VmAdEvent{type, adBreak}`；`core/options/ad_config.dart` 的
  `VmAdConfig{enabled=false, breaks=const[], onAdEvent?}`。接进 `VmOptions` 新节。
- [x] **B2 广告控制器**（2026-08-04）：`core/ad/ad_controller.dart` 的 `VmAdController`——**改为宿主驱动的
  编排器，不做 `VmInterceptor`**（拦截器在 engine 构造期注入、拿不到 api 来切源，做编排器更顺、与
  `VmPlaylistController` 一致）。`load(content)` 起播（有 pre 先播 pre）；订阅 progress 触发 mid（保存正片
  位置，广告后 `_playContent(at:)` 续播，靠 seek 寄存落地）；`VmCompleted` 驱动 ad→content / content→post→idle
  状态机；`skip()`/`notifyClicked()`；`changes` 流 + `isShowingAd`/`currentBreak`/`canSkip`/`skipIn` getter。
  纯函数 `dueMidRoll` 抽出可单测。`ad_controller_test.dart` 11 项（含 dueMidRoll 纯函数、pre/mid/post 流程、
  mid 不重复、skip 阈值、click 上报、dispose）。
- [x] **B3 广告叠层**（2026-08-04）：`ui/components/ad_overlay.dart` 的 `AdOverlayComponent(controller)`
  （`VmSlot.overlay`）——"广告"角标、`skippableAfter` 前显倒计时秒数/到点出"跳过广告"、整屏点按上报
  click-through。**点击跳转采用零依赖方案**（用户拍板）：只经 `onAdEvent(clicked)` 回调把
  `clickThroughUrl` 交给宿主，库不引 `url_launcher`、不自行打开 URL。文案走 `VmStrings`（新增
  `adBadge`/`skipAd`）。`ad_overlay_test.dart` 4 项。
- [x] **B4 副作用抑制**（2026-08-04）：广告播放期间抑制正片侧 STT。给 `VmSttApi` 加只读 `isRunning`
  getter（`VmSttService` 转发 `_started`，`attach()` 不重置它，故 STT 会带着跑进广告——正是要治的）；
  `VmAdController._playAd` 捕获 `_sttWasRunning = api.stt.isRunning` 并 `stop()`，`_playContent` 续播后
  **仅当广告前在跑时**才 `start()`。单测覆盖：广告期间抑制、续播后恢复、广告前未开则不误开。
- [x] **B4+ 运行时任意位置插入**（2026-08-04，用户追加需求"广告要支持在任意位置插入"）：
  `VmAdController.playAdNow(VmAdBreak)`——在当前正片位置即时插播、播完回到打断处（`_lastContentPosition`
  逐 tick 跟踪，作续播点）；仅在 content 阶段生效。配置侧的多个 mid-roll 任意 offset 本就支持（`dueMidRoll`
  已处理）。单测：playAdNow 插入+恢复、非 content 阶段空操作、两个任意 offset 的 mid 各触发一次且不重复。
- [x] **B5 example**（2026-08-04）：`example/lib/main.dart` 加 `AdDemoPage`（AppBar `Icons.ad_units_rounded`
  入口）——前贴片 + 10s 中插（均 3s 可跳过）、`AdOverlayComponent` 补进 overlay 槽、"此刻插入广告"按钮演示
  `playAdNow`、`onAdEvent` 事件文本展示（含 clicked → clickThroughUrl，零 url_launcher）。
  **全量 `flutter analyze` 0 + `flutter test` 442 项已过**（含新增 20 项广告测试）。**均未上真机。**

---

## 审查修复（2026-08-04，high-effort code-review 后）

7 项发现全部处理，全量 445 测试绿、analyze 0：

1. **playlist ↔ ads 组合争抢 `VmCompleted`**：`VmAdController` 新增 `contentEnded` 流（正片+后贴片全播完才触发），两个控制器类文档写明组合契约——组合时 `autoPlayNext: false` + 由 `contentEnded` 驱动 `next()`。
2. **前/后贴片广告 pod**：`_resumeAfterAd` 对 pre/post 连播同类未播广告（`_firstOfKind` + `_played` 天然支持），不再只播第一条。mid 多档本就支持。
3. **`load()` 重置 `_lastContentPosition`**：避免复用控制器时 `playAdNow` 用到上一部正片的残留位置。
4. **seek 寄存**：补注释说明无时长源的 seek 不执行与内核原行为一致（非回归）。
5. **广告跳过倒计时**：`.inSeconds` 向下取整改 `ceil`，4.9s 显示 "5" 而非 "4"。
6. **`VmPlaylistController.jumpTo`**：先 `await open` 再提交下标/发 `indexChanges`，open 失败时下标不前移。
7. **`_Phase` 枚举逐值补双语注释**（规约）。

新增测试：pre/post pod 连播、`contentEnded`（无后贴片/后贴片 pod 两路）。

## 需要先定的公开 API 设计（属架构档，建议 opus 复核）

1. **控制器归属**：`VmPlaylistController`/`VmAdController` 是宿主 `new` 出来注入，还是 `VmApi` 暴露 getter？
   （倾向宿主构造 + 注入，与 feed/STT 一致，core 不背状态。）
2. **广告点击跳转**：内置 `url_launcher`（新依赖）还是只给 `onAdEvent` 回调（零依赖）？（默认回调。）
3. **默认皮肤是否挂 NextUp/AdOverlay**：倾向不挂、留补丁挂载，保持默认皮肤精简。

## 落地顺序

Part A（A1→A5）先行、可独立发布；Part B（B1→B5）随后。两部分互不依赖。所有新公开面上线前更新
README/CHANGELOG/SPEC。
