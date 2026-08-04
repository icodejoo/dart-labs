# videoman 清晰度迁原生 mpv track —— spike + 迁移计划

**Goal:** 把"自解析 m3u8 + 重开变体 URL 切档"这条链，改成委托 mpv 原生的
`player.stream.tracks.video` + `setVideoTrack()`——切档从"卡一下重新缓冲"变成同会话无缝，
并顺带删掉一整块自实现代码。**分两阶段：先真机实测原生路是否可靠（阶段 1），可靠再迁移（阶段 2）。**

**决策依据：** 2026-08-04 与 playora（github Ali-Roodi/playora）对比。playora 在桌面/移动端正是读
`state.value.tracks.video` 筛 `t.h != null` 出清晰度、`player.setVideoTrack(track)` 切换、
`VideoTrack.auto()` 回自适应——证明原生路在 native 平台可行。**Web 端 mpv track 为空**（playora 注释
明说），videoman 当前不覆盖 Web，本计划不涉及。

**Tech Stack:** Dart / Flutter、media_kit ^1.2.6、media_kit_video ^2.0.1。**不新增依赖。**
现状依据：[../SPEC.md](../SPEC.md)「清晰度 / ABR」一节。

---

## 现状（读代码确认，本计划要动的靶子）

| 现状 | 位置 | 问题 |
|---|---|---|
| `loadQualities()` 自己 HTTP 拉 m3u8 + `parseHlsMasterPlaylist` 解析变体 | `engine.dart:780`、`model/quality.dart` | 只对含 `.m3u8` 的 URI 生效；多一次 HTTP |
| `switchQuality(q)` **重开变体 URL** `_kernel.open(q.uri)` + `seek` 回原位 | `engine.dart:809` 附近 | 每次切档**重新缓冲**、有黑屏/卡顿风险 |
| `downshiftQuality()` 手动降一档 | `engine.dart` | 靠"重开+变体列表"才成立，是上一条的连带产物 |
| `VmBufferingAbr` + `_handleAbrBuffering` 手动 ABR 监测 | `engine.dart:1065`、`options/abr_config.dart` | mpv 已有原生 ABR；手动这套主要因为没走原生 track |
| `VmKernel` **未暴露** track 流 / `setVideoTrack` | `kernel/kernel.dart` | 迁移的前置：kernel 抽象面要加 |

**原生路能替换的：** `tracks.video`（枚举）+ `setVideoTrack(track)`（同会话切换）+ `VideoTrack.auto()`
（Auto 交 mpv ABR）。迁过去后 `parseHlsMasterPlaylist` + 重开式 `switchQuality` + `downshiftQuality`
+ `VmBufferingAbr` 监测**大部分可删**。

**保留：** MP4 多档（非自适应、`sources` 多路 URL）没有单一自适应清单，切档**仍只能重开**——这条留着，
与 HLS 原生路并存（用 `VmQuality.uri` 是否非空区分）。

---

## 阶段 1：真机 spike（需 Android + iOS 真机，用户执行；结果回写本文档附录）

目的：确认 media_kit 在目标平台把 HLS 变体**可靠地**列为可选 `VideoTrack`，且 `setVideoTrack` 切换
稳定。**这是 go/no-go 闸门，不通过就不迁移。**

- [ ] **T1 造探针**：`example/lib/spike_native_tracks.dart`——开一个 HLS master 源，打印
  `player.stream.tracks.video`（含 `id/w/h/title/bitrate` 有无）、`player.state.tracks.video`，
  以及 `setVideoTrack` 切换后 `stream.track.video`、画面是否无缝（有无黑屏/重缓冲）。
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

- [ ] **T5 kernel 抽象面扩展**：`VmKernel` 加 `Stream<VmTracks> tracks`、`Future<void> setVideoTrack(VmVideoTrack)`
  （用 videoman 自己的轻量 track 类型包一层，**不把 media_kit 的 `VideoTrack` 泄漏进 core**，守住
  `purity_test`）；`MpvKernel` 映射到 `player.stream.tracks` / `player.setVideoTrack`。`FakeKernel` 补桩。
- [ ] **T6 engine 改造**：`loadQualities()` 对 HLS 改为从 `tracks.video` 构建 `VmQuality` 列表（按 height
  去重、排序、补 auto——去重逻辑参考 playora `controller.dart:432`）；`switchQuality(q)` 对 HLS 改调
  `setVideoTrack`（不重开、不 seek 回位），MP4 多档仍走重开。保持 `VmQualityListChanged`/`VmQualityChanged`
  事件契约不变（UI 零改动）。
- [ ] **T7 删冗余**：确认无引用后删 `parseHlsMasterPlaylist`（及其测试）、`downshiftQuality`、
  `_handleAbrBuffering` + `VmBufferingAbr` + `VmAbrConfig.enabled/stallThreshold`（若 Auto 完全交 mpv ABR）。
  **`VmAbrPolicy` 注入点是否保留待定**——若想给宿主留自定义 ABR 口子可保留抽象、只删默认实现。
- [ ] **T8 测试**：`FakeKernel` 推 track 列表 → 断言 `qualities` 正确去重/排序；`switchQuality` 走
  `setVideoTrack` 而非 `open`；MP4 多档仍走 `open`；HLS 单码率只出 auto。
- [ ] **T9 校验 + 回写**：`flutter analyze` 0 issues、`flutter test` 全绿、`purity_test` 仍恰好只放行
  `mpv_kernel.dart`；更新 SPEC「清晰度 / ABR」一节与本文档附录。

---

## 交付物与闸门

阶段 1 是**独立可交付**的实测报告（回写下方附录），不阻塞任何其他工作。阶段 2 是有条件的重构，
**动 kernel 抽象面属架构改动，落地前建议 opus 复核签名**。

## 附录 A：spike 实测结果（待真机回填）

（Android / iOS / 桌面 × 源矩阵的判定表，T4 结论，go/no-go。）
