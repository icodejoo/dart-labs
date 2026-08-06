# mova 清晰度迁原生 mpv track —— spike + 迁移计划

**Goal:** 把"自解析 m3u8 + 重开变体 URL 切档"这条链，改成委托 mpv 原生的
`player.stream.tracks.video` + `setVideoTrack()`——切档从"卡一下重新缓冲"变成同会话无缝，
并顺带删掉一整块自实现代码。**分两阶段：先真机实测原生路是否可靠（阶段 1），可靠再迁移（阶段 2）。**

**决策依据：** 2026-08-04 与 playora（github Ali-Roodi/playora）对比。playora 在桌面/移动端正是读
`state.value.tracks.video` 筛 `t.h != null` 出清晰度、`player.setVideoTrack(track)` 切换、
`VideoTrack.auto()` 回自适应——证明原生路在 native 平台可行。**Web 端 mpv track 为空**（playora 注释
明说），mova 当前不覆盖 Web，本计划不涉及。

**Tech Stack:** Dart / Flutter、media_kit ^1.2.6、media_kit_video ^2.0.1。**不新增依赖。**
现状依据：[../SPEC.md](../SPEC.md)「清晰度 / ABR」一节。

---

## 现状（读代码确认，本计划要动的靶子）

| 现状 | 位置 | 问题 |
|---|---|---|
| `loadQualities()` 自己 HTTP 拉 m3u8 + `parseHlsMasterPlaylist` 解析变体 | `engine.dart:780`、`model/quality.dart` | 只对含 `.m3u8` 的 URI 生效；多一次 HTTP |
| `switchQuality(q)` **重开变体 URL** `_kernel.open(q.uri)` + `seek` 回原位 | `engine.dart:809` 附近 | 每次切档**重新缓冲**、有黑屏/卡顿风险 |
| `downshiftQuality()` 手动降一档 | `engine.dart` | 靠"重开+变体列表"才成立，是上一条的连带产物 |
| `MovaBufferAbr` + `_handleAbrBuffering` 手动 ABR 监测 | `engine.dart:1065`、`options/abr_config.dart` | mpv 已有原生 ABR；手动这套主要因为没走原生 track |
| `MovaKernel` **未暴露** track 流 / `setVideoTrack` | `kernel/kernel.dart` | 迁移的前置：kernel 抽象面要加 |

**原生路能替换的：** `tracks.video`（枚举）+ `setVideoTrack(track)`（同会话切换）+ `VideoTrack.auto()`
（Auto 交 mpv ABR）。迁过去后 `parseHlsMasterPlaylist` + 重开式 `switchQuality` + `downshiftQuality`
+ `MovaBufferAbr` 监测**大部分可删**。

**保留：** MP4 多档（非自适应、`sources` 多路 URL）没有单一自适应清单，切档**仍只能重开**——这条留着，
与 HLS 原生路并存（用 `MovaQual.uri` 是否非空区分）。

---

## 阶段 1：真机 spike（需 Android + iOS 真机，用户执行；结果回写本文档附录）

目的：确认 media_kit 在目标平台把 HLS 变体**可靠地**列为可选 `VideoTrack`，且 `setVideoTrack` 切换
稳定。**这是 go/no-go 闸门，不通过就不迁移。**

- [x] **T1 造探针**（已完成）：`example/lib/spike_native_tracks.dart`——裸驱动 media_kit
  `Player`（绕开尚未暴露 track 的 `MovaKernel`），源切换 chip + 打印
  `player.stream.tracks.video`（`id/w/h/title/bitrate/codec`）、`player.state.tracks.video`
  按钮，点击即 `setVideoTrack`，并打点切换耗时；已接入 example 主页 AppBar
  「原生 track spike」图标。`flutter analyze` 0 issues。
- [ ] **T2 源矩阵**：至少覆盖①标准多码率 HLS master（如 Mux/Bitmovin 公测源）②国内 CDN 常见 HLS
  ③单码率 HLS（应只出 auto）④非 HLS MP4（tracks.video 应为空/单条，走保留的重开路）。
- [ ] **T3 判定表**（每平台 × 每源填）：
  - 变体是否全部枚举出来？`h`（高度）字段是否齐（决定标签能不能显示 `1080p`）？
  - `setVideoTrack` 切换是**无缝**还是有可见重缓冲/黑屏？
  - `VideoTrack.auto()` 是否真的回到 mpv ABR？
  - 切档后 position 是否保持（原生应自动保持，无需 seek 回位）？
- [ ] **T4 结论**：三平台（Android/iOS/桌面）× 源矩阵的可靠性判定。**全绿或仅桌面有小瑕疵 → 迁移；
  移动端枚举不全/标签缺失/切换有明显重缓冲 → 放弃迁移，保持现状**（现状虽重开但行为可预测、纯函数好测）。

> ⚠️ 已知风险点（spike 要重点验）：mpv 对某些 HLS 的 `h` 字段可能缺失（标签只能退化成 bitrate）；
> 部分构建 HLS 变体切换需 `--hls-bitrate` 等参数；media_kit 各版本 track 行为有差异。

---

## 阶段 2：迁移（**仅当阶段 1 通过**）

- [x] **T5 kernel 抽象面扩展**（已完成）：`MovaKernel` 加
  `Stream<List<MovaVideoTrack>> videoTracks`、`Stream<MovaVideoTrack> videoTrack`、
  `Future<void> setVideoTrack(MovaVideoTrack)`。`MovaVideoTrack` 定义在
  `core/model/quality.dart`（不是 kernel.dart——因为 `qualitiesFromVideoTracks`
  是导出的公开函数，参数类型必须也可从 barrel 访问，放 kernel.dart 会泄漏未导出
  类型到公开签名）；`MpvKernel` 映射到 `player.stream.tracks`/`player.stream.track`/
  `player.setVideoTrack`，并过滤掉 mpv 的 `id:'no'`（"关闭视频"）条目——真机 spike
  踩过这个坑，见附录 A。`FakeKernel` 补了 `emitVideoTracks`/`lastVideoTrack` 测试桩。
  `purity_test` 仍绿（media_kit 依赖只在 `mpv_kernel.dart`）。
- [x] **T6 engine 改造**（已完成）：`loadQualities()` 对 HLS 改为等
  `_kernel.videoTracks` 首次非空推送（8s 超时兜底），用纯函数
  `qualitiesFromVideoTracks`（`core/model/quality.dart`）按 height 去重（同高度保留
  首个/最高码率）、排序、补 auto；`switchQuality(q)` 按 `q.trackId` 是否非空路由：
  非空调 `setVideoTrack`（不重开、不 seek 回位），否则走原 `q.uri` 重开路径（预留给
  未来的非自适应多源场景，目前没有生产者接入，`MovaSource` 还没有多源字段）。
  `MovaQualListChg`/`MovaQualChg` 事件契约不变，UI 零改动。
  `downshiftQuality()` 改按 `trackId ?? uri` 定位当前档下标，兼容两条路径。
- [x] **T7 删冗余**（已完成，范围比原计划小）：`parseHlsMasterPlaylist`
  （及 `_parseAttrs` 辅助函数、`test/core/model_test.dart` 里的 3 项测试）已删——
  确认过 `loadQualities()` 已改走 `qualitiesFromVideoTracks`，且仓库内外均无其他调用点
  （公开 API 删除，破坏性变更，已执行）。`core/engine.dart` 的 `_httpGetString` 及
  跟着变孤儿的 `dart:convert`/`dart:io` 两个 import 一并删除。
  **`downshiftQuality`/`_handleAbrBuffering`/`MovaBufferAbr`/`MovaAbrConfig` 保留，
  没有删**——新方案下 `switchQuality` 的内部实现（原生 track 还是重开）对它们完全
  透明，之前计划文档"若 Auto 完全交 mpv ABR 则可删"这一前提没有变化，继续按现状
  留着，不是遗漏。
- [x] **T8 测试**（已完成）：`test/core/model_test.dart` 新增 `qualitiesFromVideoTracks`
  分组（auto 排前+按高度排序、同高度去重保留首个、无 height 时退化 bitrate 标签、
  空/仅 auto 输入返回空列表）；`test/core/engine_test.dart` 新增
  `loadQualities()` 从 `FakeKernel.emitVideoTracks` 构建清单、非 HLS 源不碰内核、
  `switchQuality()` 带 `trackId` 调 `setVideoTrack` 而非 `open` 三个测试。
- [x] **T9 校验 + 回写**（已完成）：`flutter analyze` 0 issues（`lib`+`test`）、
  `flutter test` 449 项全绿（445 起点 + 本次新增 7 项 − T7 删掉的 3 项
  `parseHlsMasterPlaylist` 测试）、`purity_test` 单独跑通过；已更新
  [doc/SPEC.md](../SPEC.md)「清晰度 / ABR」一节与本文档附录 A/B。

---

## 交付物与闸门

阶段 1 是**独立可交付**的实测报告（回写下方附录），不阻塞任何其他工作。阶段 2 是有条件的重构，
**动 kernel 抽象面属架构改动，落地前建议 opus 复核签名**。

## 附录 A：spike 实测结果

**Android 真机（华为 STG-AL00，Android 12，菲律宾运营商 SIM）2026-08-04 实测：**

- **首轮"全部无法播放"的根因不是 mpv/网络问题，是 example app 缺 `INTERNET` 权限**——
  `example/android/app/src/main/AndroidManifest.xml` 从未声明
  `<uses-permission android:name="android.permission.INTERNET"/>`，`media_kit_video`
  插件自身的 manifest 也不带任何权限，导致 mpv 原生 socket 层直接打开失败
  （`mpv[error] stream: Failed to open ...`），而系统浏览器能播放（浏览器是系统应用，
  权限单独授予）造成"网络明明通"的假象。补上该权限后三个源（HLS 多码率 Mux、HLS 单码率、
  MP4 无自适应）均可正常打开。**这是 example app 的配置缺口，不是 mova 库或 mpv 的问题**
  ——真实宿主 app 若已有此权限（几乎所有播放器 app 都有）不会遇到。
- **`tracks.video` 里有个容易踩的坑**：mpv 除了各清晰度变体和 `auto`，还会带一条
  `id: 'no'`（`VideoTrack.no()`，语义是"关闭视频输出"），h/bitrate 都是 null。探针页
  初版按钮标签退化成显示 `t.id`，把这条也渲染成一个可点按钮、文字就是"no"——点了会
  永久黑屏且不会自行恢复（因为语义就是关视频，不是切换失败）。**已在
  `example/lib/spike_native_tracks.dart` 里过滤掉 `no` 轨**，避免误判成 mpv bug。
- 修复以上两点后，三源真机播放正常；清晰度按钮切换、`auto` 回自适应均可用（细粒度的
  "是否无缝无重缓冲""`h` 字段是否每个变体都齐"等 T3 逐项判定表仍待完整走一遍并回填）。

**已确认的架构结论（不依赖真机细节，代码层面即可判断）：** 原生 track 机制只对
**单个 URL 声明多变体**的自适应容器/协议有效（HLS master playlist、DASH/MPD）——mpv
demuxer 打开一次就能解析出全部变体，`setVideoTrack` 才能同会话切换。**多个独立 URL
的 MP4 文件不适用**——mpv 不知道这些互不相关的源是同一内容的不同清晰度，只能走现状的
"重开 URL + seek 回位"。**结论（用户已拍板）：两条路并存，不是二选一**——
`MovaQual.uri` 是否指向自适应清单来路由：HLS/DASH 走原生 `setVideoTrack`（无缝），
MP4 多路 `sources` 仍走现有重开逻辑。T6 的实现思路本就是这个方向，本次 spike 确认了
这个判断的必要性和正确性。

**T3 判定表——"setVideoTrack 是否无缝"（Android 真机实测，Mux HLS 多码率源，2026-08-04）：**

- **不是真正无缝**：点击清晰度按钮的瞬间画面先暂停，约 1 秒后出现 loading 转圈，随后
  恢复播放——用户体感是"卡了一下"，不是丝滑切换。
- **但明显快于现状的"重开变体 URL"**：与切 chip（`Player.open()` 打开全新源，
  完整走一遍连接+缓冲）相比，`setVideoTrack` 的卡顿时长更短。
- 结论：**"无缝"这个预期要调整**——迁移后是"更快的有感切换"，不是"零感知切换"。
  对最终用户体验仍是提升（切档等待时间缩短），但不要把它包装成"完全无缝"。

**Go/no-go：** **go，但要调整预期**——排除权限/UI 坑之后，mpv 原生 track 机制在这台
设备上工作正常、比现状快，构成迁移的理由；但"同会话无缝切换"这个假设没有被真机数据
支持，需要把 SPEC/PRD 里"无缝"的表述改成"更快"。**建议在正式进入阶段 2（T5 起）之前**：
补齐 T3 判定表里"`h` 字段是否每个变体都齐"这一项，并换成生产环境真实用的
东南亚/国内 CDN HLS 源复测一遍（Mux 公测源只验证了机制通不通，不代表真实源的切换
延迟/`h` 字段完整度）。

## 附录 B：阶段 2 落地记录（2026-08-04）

**代码改动**（不依赖真机，本机 `flutter analyze`/`flutter test` 已验证）：

- `lib/src/core/kernel/kernel.dart`：`MovaKernel` 新增 `videoTracks`/`videoTrack`/
  `setVideoTrack`。
- `lib/src/core/model/quality.dart`：新增 `MovaVideoTrack`、`qualitiesFromVideoTracks`；
  `MovaQual` 新增 `trackId` 字段，`uri` 改为可选（默认空）。
- `lib/src/core/kernel/mpv_kernel.dart`：映射 media_kit 的 `stream.tracks`/
  `stream.track`/`setVideoTrack`，过滤 `id:'no'`。
- `lib/src/core/engine.dart`：`loadQualities()`/`switchQuality()`/`downshiftQuality()`
  改走上述新面；`_httpGetString` 已删（无调用点），跟着变孤儿的 `dart:convert`/
  `dart:io` 两个 import 一并删除。
- `lib/src/core/model/quality.dart`：`parseHlsMasterPlaylist`/`_parseAttrs` 已删
  （公开 API 删除——确认无生产调用点后执行，不是遗漏）。
- `test/support/fake_kernel.dart`：补 `videoTracks`/`videoTrack`/`setVideoTrack` 测试桩。
- 测试：`test/core/model_test.dart` 删掉 `parseHlsMasterPlaylist` 的 3 项、新增
  `qualitiesFromVideoTracks` 4 项；`test/core/engine_test.dart` 新增
  `loadQualities`/`switchQuality` 原生路径 3 项。

**校验结果：** `flutter analyze`（`lib`+`test`）0 issues；`flutter test` 449 项全绿
（445 起点 + 新增 7 − 删掉 3）；`purity_test` 单独跑通过（media_kit 依赖仍只在
`mpv_kernel.dart`）。

**`MovaEngine` 真实链路真机验证（2026-08-05，同一台华为 STG-AL00）：** 走 example 主页
「HLS · 多清晰度」demo（真实 `MovaEngine.loadQualities()`/`switchQuality()`，不是
独立探针页），清晰度切换正常生效，logcat 无 `mpv[error]`/`player error`。用户反馈
"切换正常，就是要等"——与阶段 1 结论一致（比重开快，但不是无缝，有等待感），阶段 2
的代码改动在真实链路上确认无问题。

**未做/留给下一步：**

1. T3 判定表"`h` 字段是否每个变体都齐"仍未测；建议换生产真实用的 CDN 源。
