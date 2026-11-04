# mova 统一编排总计划（2026-10-31）

> 状态：**已拍板（2026-11-03，用户授权由 Claude 决策）**：第 8 节 18 项全部采纳推荐默认值；仅第 8 项（pub.dev 实际版本）需用户本人确认，不阻塞开工，发版前补。
> **2026-10-31 审计修订**：只读审计结论是“不能原样开工”，已就地落进本文：A19 前移到 S01 之后；A20 补改写口径；A12 默认值与测试 rig；A13/A14 合成一个设计单元（拆 3 个提交，顺序固定）；`@Deprecated` 成本与 `MovaHttpFetch` 破坏性；真机验证页成本与 CP 检查行；被丢子项的承接；成本重算（66 提交，137 / 199 / 291 人天，明细见 7.3）。凡标 **[待核]** 的是本次修订没能核实的点。
> 范围：`mova/` 子工程。一条分支 `jelon/mova-orchestration`，66 个有序提交，4 个真机检查点，**只合并一次**。
> 输入：[全量评审](../notes/2026-10-30-architecture-review.md)（65 条）、Codex 复审（N1–N9、R1–R12、6 条异议）、Codex 重构调研、opus 对重构调研的终审结论（9 条，本文直接吸收，不再争论）。Codex 两份报告在会话暂存区，未入库，引用时写"Codex 复审 §x / 重构调研 §x"。
> 标注：**[已核]** = 写本文时亲自读过代码确认；**[材料]** = 来自评审或 Codex，本次没有逐行复核；**[推测]** = 静态读不出来，排了验证点。所有行号是 2026-10-31 main（`46bcc5d`）上的实际行号。

---

## 0. 一页摘要

**目标**：把散在 `MovaAds`、`MovaPlaylist`、宿主代码里的"谁来打开下一段内容"收拢到一个编排所有者 `MovaSession`；同时把评审、Codex、终审挖出的全部问题一次理清——要么排进提交，要么写明不做的理由。

**三条轨道**

| 轨道 | 内容 | 提交数 | 最可能成本 |
|---|---|---|---|
| 准备 | 修跑批判据、交错测试脚手架、替身按真实意图契约维护（A19 前移） | 3 | 5.5 人天 |
| B 独立修复 | 状态层、进度快照、底栏、亮度方向、QoE、弹幕、预览、抽取器、池、feed、守卫、小毛病、性能、桌面无障碍 | 16 | 31.5 人天 |
| A 编排收拢 | A1 引擎与切换层的时序修复（15 个行为/新增提交 + 2 个机械提交）；A2 会话层（MovaSession、广告时钟、意图、播放列表、失败仲裁） | 30 | 67.5 人天 |
| C API 与 DX | 构造说明、双重开关、MovaView、MovaChrome、全屏路由、MovaPlayerStyle、请求头、barrel 分入口、STT 撤出、所有权 | 17 | 46.5 人天 |

**提交**：66 个，每个提交 `flutter analyze` 0 issues、`flutter test` 全绿；行为变更与机械搬迁分开提交（机械 4 个、测试/工具 3 个、其余为行为、新增、API 或文档）。

**真机检查点**：4 个（CP0 补基线、CP1 引擎与切换、CP2 会话与后台、CP3 合并前全量）。CP0 有个前置问题：最近两次跑批（full-02、r1030）135 项里 133 项 BLOCKED，原因是跑批脚本缺"完整编号自动判据"，不是产品失败（[r1030](2026-10-30-matrix-run-r1030.md):5-7）——不先修脚本就没有基线。

**三档成本**（含设备时间与终审）：乐观约 **137 人天**、最可能约 **199 人天**、悲观约 **291 人天**（审计修订前 120 / 172.5 / 242，增量明细见 7.3）；其中设备时间 10.5 / 16.5 / 32 天。AI 代理落地能压缩编码的日历时间，设备时间压不了。

**待拍板**：18 项（第 8 节）。默认路径**不引入任何新第三方依赖**。最需要先拍的三件：网络探针默认接线（推翻旧决定）、判失败不依赖 recovery + 事件泵懒启动（改变"默认关"的边界）、广告时钟与后台暂停的所有权。审计后新增三项：`state.error` 只放终结错误（对默认行为是破坏性变更，待拍板 16）、`MovaHttpFetch` 加请求头（对宿主实现的破坏，待拍板 17）、`@Deprecated` 策略（待拍板 18）。

**和已拍板约束的关系**：保住"新功能默认关闭""core 不依赖 UI""`createMovaEngine` 是标准构造""feed 不进 cutover""`MovaCutover` 四个动词不加方法""广告不依赖媒体时间轴"。有 4 处会推翻旧决定，都在第 8 节单列并写明"这会推翻 X"。

---

## 1. 范围与目标

### 1.1 为什么收拢到一个控制器，以及收拢到什么程度

Codex 重构调研的结论是"四类 bug 都能在原边界局部修，完整 Session 暂缓"。这句话对修 bug 成立，但对用户这次的要求不够：

1. **按集广告（P1-8）和播放列表 + 广告（P1-7）需要同一个"条目 + 节点"概念。** 只在 `MovaAds` 里修，`MovaAds` 就得自己长出条目列表和游标，变成第二个播放列表；只在 `MovaPlaylist` 里修，它又要懂 pod 和续播点。两者合一才不重复。[已核] `MovaAds` 构造时把排期快照成 final 字段（`core/ad/ads.dart:143-147`），`MovaPlaylist.jumpTo` 直接 `_api.open`（`core/playlist/playlist.dart:147`），两边各自对 `MovaDone` 做反应（`ads.dart:1106-1129`、`playlist.dart:171`）。
2. **同一个 api 上"谁有权打开下一段内容"今天有三个写者**：`MovaAds`、`MovaPlaylist`、宿主或 `MovaView`。P0-2 的触发三（代理 `open` 不放弃影子）就是三个写者互不知情的直接后果。收拢后，内容级的打开只有会话一个写者，宿主直接 `open` 走 cutover 的操作代际兜底（A02）。
3. **广告时钟、续播意图、转场令牌、事件里的 epoch** 都需要一个唯一的纪元来源。分散在两个控制器里就要两套代际号再对齐。

但收拢有边界。这次**不**做的：

- **不把引擎内部的生命周期并进会话。** attempt、seek 校验链、recovery、keepAlive、首帧闸门仍归 `MovaEngine`；影子资源仍归 `MovaCutoverEngine`。会话只借用一个 `MovaApi`，通过公开动词驱动它。这和 Codex 的"唯一所有者在业务节点层有价值，但不能取代每播放器的 attempt/seek/native 资源所有权"一致。
- **不另造第二个所有者。** `MovaSession` 由 `MovaAds` 现有的状态机原样搬家而来（A22 机械提交），`MovaAds` 退化成转发壳；`MovaPlaylist(api, ads:)` 与 `MovaAds` 共享同一个会话实例。没有"Ads 一套、Session 一套"的并存期。
- **不做泛化命令队列**（终审 1）。`_keepAliveQueue` 留在本地，只把其中跨网络的重开挪出去（A07）。
- **不把 `MovaEngine` 拆成七个子控制器。** 评审第 8 节第 1 阶段的全拆没有 bug 驱动，F3/A17 曾经单测全绿而真机失败率 20.68%→0.36% 走了四轮（CLAUDE.md「测试基线」段），seek/首帧/ABR 每动一次都要配 280 次真机。本分支只做有 bug 驱动的最小结构：`_LoadSpec`（A09/A10）、ABR 租约（A11）、独立的恢复闸门（A08）。全拆列入暂缓，触发条件见 1.4。

#### Timeline / Cursor+Intent / Transition / Preloader / FailureArbiter 逐个裁定

| 组件 | 做不做 | 做到什么程度 | 理由 |
|---|---|---|---|
| Timeline | 做 | 条目列表 + 每条目由排期推导出的节点（pre*/content/mid pod*/post*），纯函数；`setItems` 整体替换，不做可编辑图 | P1-7、P1-8、P3-3 都需要；可编辑图没有需求 |
| Cursor | 做 | `{epoch, item, node, phase, contentResumeAt}` 不可变快照 | 事件带 nodeId/epoch、UI（NextUp、广告覆盖层）读同一个游标 |
| Intent | **不新建** | 唯一事实来源是引擎的 `MovaState.playbackIntent`；会话只在转场入口取快照 | 会话再存一份意图就会出现两份意图对不齐；终审 5 要求"意图在 `old.pause()` 之前取" |
| Transition | 做（内部） | 由前后节点推导 `MovaWarmPlan`（rate、pauseWhenReady、就绪判据）、带会话 epoch 的令牌、过期不回落 | P0-2、P2-6、P2-7、CLAUDE.md 剩余任务 ②③ |
| Preloader | 只保留现有两个方向 | 广告背后预热正片、正片背后预热广告；**不**预加载下一集 | 单影子槽会和中插预热抢位；自动预加载是新增资源消耗，按"新功能默认关闭"需要 opt-in 设计，目前没有需求证据 |
| FailureArbiter | 做（最小） | 纯函数：节点级失败归会话策略，传输失败归引擎 recovery；同一 (epoch, node, attempt) 只结算一次 | README:62 自己写着"recovery + Ads + cutover 同开时交互不在保证范围内"[已核] |

### 1.2 轨道定义

- **轨道 A：编排收拢**。A1 = 引擎与切换层的时序与加载规格（凡是"谁在什么时刻有权改状态"的问题）；A2 = 会话层。
- **轨道 B：与编排无关的 S/M 修复**。不碰 seek、首帧闸门、ABR、keepAlive，可在独立 worktree 并行开发，按阶梯位置落地。
- **轨道 C：API 面与 DX**。凡破坏公开 API 的点都给 `@Deprecated` 过渡。

两处和用户列表的归属不同，说明一下：
- **P1-14（`Video` 后台暂停）归到 A（A21）**：终审 5 要求广告时钟和它一起定，而且它决定 `playbackIntent` 是否可信，后者是 A20 续播开播的依据。
- **P1-13（自动隐藏续期）折进 C04**：`MovaChrome` 会把自动隐藏计时器从引擎搬走，先在引擎里修一遍再搬是来回折腾。

### 1.3 完整归属表

每一条都有去处。"提交"列是第 3 节的提交编号；"暂缓/不做"见 1.4。

#### P0（2 条）

| 编号 | 问题 | 轨道 | 提交 | 备注 |
|---|---|---|---|---|
| P0-1 | 控制条隐藏/锁定时缓冲与错误层一起消失 | B | B01 | [已核] `overlays.dart:35,83` 在 center 槽，center 在 `_BarVisibility` 内（`default_skin.dart`） |
| P0-2 | 影子不和源绑定，换集播成上一集 | A | A01→A02（触发三、N1）、A03（触发一/二） | 不加 `commit(expect:)`，按终审 2 用操作代际 |

#### P1（24 条）

| 编号 | 问题 | 轨道 | 提交 | 备注 |
|---|---|---|---|---|
| P1-1 | 错误模型没分级 | A | A13（内核层接线+分类）、A14（END_FILE 订阅+封面 RESTART）、A14b（`state.error` 只放终结、遮罩与文案）、A15（编排层只认终结错误） | A13/A14/A14b 是**一个设计单元**（见 3.3），顺序不可调换，否则 404 地址会出现“无终结错误”的回退窗口；`open()` 抛异常见待拍板 10；`state.error` 收窄见待拍板 16 |
| P1-2 | 内部重载不记得加载的是什么 | A | A09（机械）、A10（行为） | 终审 3：记录并重放有效规格 + 显式理由 |
| P1-3 | 清晰度/ABR 默认链路断 | A | A12（就绪后自探测）、A16（auto 档接管，默认关） | **默认值策略**：本计划对 P1-3 只承诺 A12（列表可用、手选档不被覆盖）；auto 档由 mova ABR 接管（A16）默认关，所以“默认仍可能停在 mpv 静态选档”不算本计划修复，README 如实写明；要默认开须另拍板（待拍板 11）。mpv 静态选档待 CP0 验证 |
| P1-4 | 进度没有同步快照 | B | B02 | |
| P1-5 | 广告计时不感知暂停和前后台 | A | A18（时钟）、A20（续播继承意图）、A21（后台暂停所有权） | 终审 5 |
| P1-6 | 一次性 `cutoverTo` 抛异常时广告卡死 | A | A05 | [已核] `ads.dart:832-836` 只有 try/finally |
| P1-7 | README 推荐的 ads+playlist 组合是坏的 | A | A25 | 依赖 A23 |
| P1-8 | 每条内容的数据在引擎级 `MovaOpts`；MovaView 重建陷阱 | A/C | A23（按集广告）、C03（MovaView 只比引擎节）、C06（样式挪出 MovaOpts） | 弹幕条目随内容走：暂缓（1.4） |
| P1-9 | 双重开关静默不生效 | C/A | C02（Mini.show 遵守 enabled、README 示例、cutover/STT 的 debug 提示）、A23（会话自动识别 cutover）、A25（`playlist.enabled` 在会话路径遵守） | 按 Codex 异议 2：**不**改成"构造即启用"；`playlist.enabled` 现行只挡 NextUp 组件（`ui/components/next_up.dart:52` [已核]），A25 让会话路径的 next/previous/自动连播也遵守 |
| P1-10 | `MovaFeedPlayer` 黑盒 | C | C14 | |
| P1-11 | 全屏只是转屏，退出解除宿主方向锁 | B/C | B04（还原）、C05（应用内全屏路由 + PopScope，默认关） | OS 级窗口全屏端口：暂缓 |
| P1-12 | 视图 UI 交互态放在引擎上 | C | C04 | L |
| P1-13 | 自动隐藏不感知交互 | C | C04 | 见 1.2 |
| P1-14 | media_kit `Video` 默认后台暂停 | A | A21 | CP0 先验证真机影响 |
| P1-15 | 桌面/TV/无障碍缺位 | B | B16 | 可聚焦与语义默认开，快捷键默认关 |
| P1-16 | 底栏按下标取子节点 | B | B03 | [已核] `bottom_bar.dart:68-80` |
| P1-17 | 弹幕前跳生成全部弹幕 | B | B06 | 单 CustomPainter 重写：暂缓 |
| P1-18 | 亮度不读初值不还原 | B | B04 | |
| P1-19 | 鉴权请求头无一等支持 | C | C07 | 用 `MovaSource.start` 而不是给 `open` 加参数（后者破坏 `implements MovaApi`） |
| P1-20 | QoE 数据失真 | B | B05 | |
| P1-21 | 预览 wifiOnly 名不副实 | C | C12（含 `wiring.dart:118,126` 过期 tree-shaking 注释）、C11（抽帧器默认的文档） | **推翻旧决定**，待拍板 5 |
| P1-22 | 半成品 STT 全量暴露 | C/B | C09（撤出主入口）、B10（音频抽取器泄漏）、C13（不 dispose 宿主引擎、start 不 rethrow） | 模型下载非原子写盘 + 10s 超时：**暂缓**（缺陷在迁走的代码里，C09 只撤导出、缺陷仍在，见 1.4）；audioOnly 下也不启动 STT：B10；按 Codex 异议 3 改正"必定超时"的措辞 |
| P1-23 | `MovaEngine()` 静默降级 | C | C01 | 按 Codex 异议 1：**不做**默认实现注册表，只修文档与 debug 提示 |
| P1-24 | recovery 关时坏地址无事件 | A | A14 | 待拍板 6、7 |

#### P2（33 条）

| # | 问题 | 轨道 | 提交 | 备注 |
|---|---|---|---|---|
| 1 | 连点两次换档从头播、前一次释放后一次的 ABR 屏蔽 | A | A10（位置）、A11（租约） | |
| 2 | 暂停加载期间 `play()` 被吞 | A | A06 | `_loadKernel` 只纠偏一个方向 [已核] `engine.dart:915-918` |
| 3 | 恢复重载期间用户 seek 被续播 seek 覆盖 | A | A10 | |
| 4 | ABR 判据粗、策略实例被共享 | A/C | A11（seek 引起的缓冲不计）、C13（策略工厂） | 升档/时间窗属"真 ABR"，暂缓 |
| 5 | 时移下 `timeshiftBehind` 被重算 | A | A10 + CP0 验证 | [推测] 取决于服务端时间基 |
| 6 | pod 串播旧广告事件记到下一条、一次性预热参数不对 | A | A27 | |
| 7 | 预热时机只看素材剩余时长 | A | A27 | |
| 8 | 换指窗口转发旧引擎 playing=false；影子期新源事件丢失 | A | A28 | |
| 9 | 前跳越过 N 个中插全部补播 | A | A29 | 默认保持现状（全部补播） |
| 10 | cutover 失败原因不可观测 | A | A28 | |
| 11 | feed 预取只拉 64KB、不带头、池外直播满速拉流 | B/C | B12（过期检查、错误隔离）、C07（带头） | 池外直播停流需 `stop()` 能力：暂缓；预取只拉 64KB、HLS 只拿 m3u8、force close 断连接复用：**暂缓**（见 1.4），C17 在 README 写明限制 |
| 12 | NextUp 在广告里弹出 | A | A30 | |
| 13 | 守卫不豁免全屏 | B | B13 | |
| 14 | patch 路径拼错静默、README 示例位置错、锁定按钮不在树里 | B | B14 | |
| 15 | `vSensitivity` 死配置、`allowWhenLive` 文档不符 | B | B14 | |
| 16 | 与外层 PageView 手势竞技 | — | CP0 验证 | 复现了再排修复，否则暂缓 |
| 17 | 主题文案脱离 Flutter 体系、core 写死中文 | C | C06 | |
| 18 | 锁定按钮常驻 | B | B14 | |
| 19 | 选项弹层不能滚动 | B | B14 | |
| 20 | 抽帧缩略图原分辨率、按条数限额、无 cacheWidth | B | B09 | |
| 21 | 磁盘缓存每写全扫、比较器同步 stat | B | B09 | |
| 22 | 所有引擎共用缩略图目录，dispose 清别人的缓存 | B | B09 | |
| 23 | 预览队列不丢过时请求 | B | B08 | |
| 24 | 注入对象所有权不清（含 `stallPolicy` 实例被多引擎共用） | C | C13（`policyFactory` 每引擎各取一个实例） | |
| 25 | sessionStart 媒体信息采样过早 | B | B05 | B05 文件清单补 `engine.dart` 的 `open` 调用点（采样要从 open 同步段挪到内核加载后） |
| 26 | seek 引起的缓冲算 rebuffer | B | B05 | |
| 27 | 测试内核完全被动 | C | C15 | |
| 28 | PiP 只有进出；`pipChanged` 广播给所有引擎 | B | B13（广播） | actions/autoEnter/sourceRectHint：暂缓 |
| 29 | 音频焦点、耳机拔出、AVAudioSession | — | CP0 验证 | 先确认 media_kit 自己是否处理；暂缓 |
| 30 | barrel 导出大量内部实现 | C | C08 | |
| 31 | 能力发现四种方式 | C | C10 | |
| 32 | `createMovaEngine` 参数分层不清 | C | C11 | 按 Codex 异议 4 改措辞："资源行为由注入内核决定，标记仍影响上报" |
| 33 | 文档过期 | C | C01、C17 | C17 修 `core/api.dart:368-371`（“必须且只能调用一次”，与 dispose 幂等不符）、`core/options/stt_config.dart:36,45`（引用不存在的 `createMovaEngine(stt:)`），行号均 [已核] |

#### P3（6 条）

| # | 问题 | 轨道 | 提交 | 备注 |
|---|---|---|---|---|
| 1 | core 只在形式上纯净，mpv 概念渗进公共模型 | — | 不做 | 做 HarmonyOS 第二内核时升 P2（见 [harmonyos 可行性](../notes/2026-10-28-harmonyos-next-feasibility.md)） |
| 2 | 镜像事件不去重；dispose 里 UI 计时器取消晚 | B | B15 | [已核] `engine.dart:2865-2866` 在若干 await 之后 |
| 3 | `MovaAdBreak` 按身份相等，const 同实例只播一次 | A | A24 | 节点身份取代广告位对象身份 |
| 4 | 位置标签每秒重建 5 次、MovaPlayer 重跑 components() | B | B15 | |
| 5 | VTT 一次失败永久不可用、DVR 直播触发抽帧、debug 轮询 TTFF 偏晚 | B | B08（前两项） | debug 轮询：不做（仅 debug，已有文档） |
| 6 | 改名遗留 | C | C16 | |

#### Codex 新发现 N1–N9

| 编号 | 问题 | 轨道 | 提交 |
|---|---|---|---|
| N1 | commit 与下一次 prepare 无所有权隔离 | A | A01、A02 |
| N2 | 池忽略 `open()` 的布尔结果，失败绑定不可重试 | B | B11 |
| N3 | 错误响应 body 无超时，拖住 engine.dispose | B | B07 |
| N4 | 换源不结束 STT 会话，旧字幕写进新内容 | B | B10（cue 绑定会话代际，`_started` 不变） |
| N5 | 池把同 URI 当同请求 | B | B11 |
| N6 | 迟到的清晰度探测把手选档改回 auto | A | A12 |
| N7 | feed 条目与 UI 元数据无限增长 | B | B12 |
| N8 | 抽帧 seek 未落地也截图并缓存 | B | B07 |
| N9 | QoE 异步采样跨会话写基线 | B | B05 |

N4 有个需要当心的冲突：Codex 建议"换源时 stop 旧识别"，但 `MovaAds` 依赖 `attach` 不重置 `_started` 来判断"pod 开始前 STT 是否在跑"（[已核] `stt/service.dart:121-125`、`ads.dart:787-790`）。B10 的做法是**只给 cue 加会话代际、丢弃旧源迟到的 cue，`_started` 不动**，并把"换源后识别保持开启"写进文档。

#### Codex 重合项 R1–R12

| 编号 | 对应 | 提交 |
|---|---|---|
| R1 | P0-1 | B01 |
| R2 | P0-2 | A02、A03 |
| R3 | P1-4 | B02 |
| R4 | P1-16 | B03 |
| R5 | P1-22 音频抽取器子项 | B10 |
| R6 | P1-20 心跳子项 | B05 |
| R7 | P1-23 | C01 |
| R8 | P1-9 mini 子项 | C02 |
| R9 | P2-21 | B09 |
| R10 | P2-23 | B08 |
| R11 | P1-17 | B06 |
| R12 | P1-3 自动探测时序 | A12 |

#### opus 终审新发现与终审其余条

| 编号 | 内容 | 提交 | 核对 |
|---|---|---|---|
| 终审 7a | B 模式唤醒后 5 秒内换源，恢复超时回调 reset 新源首帧闸门 | A08 | [已核] `_beginResume` 的超时回调 `if (_resumeGateArmed) _frameGate.reset()`（`engine.dart:1798-1802`）；`_armAttempt` 不清 `_resumeGateArmed`（`:946-955`）；`arm()` 先 `reset()`（`render/first_frame.dart:85-90`） |
| 终审 7b | 回直播边缘后 `if(!state.playing) await _kernel.play()` 不复查意图 | A07（keepAlive 路径）、A10（非 keepAlive 的 `backToLiveEdge`） | [已核] `engine.dart:1774-1776`；`_reopenLiveSource` 也被非 keepAlive 的 `backToLiveEdge` 调用（`engine.dart:2581,2585` [已核]），不能只按 keepAlive 改 |
| 终审 7c | 被拒的 open 推进 `_openGen`，作废在途 play/seek | A06 | [已核] `:1262` 在 hook 之前 `++_openGen`；`:1864-1867`、`:1931-1936` 比较 `_openGen` |
| 终审 7d | `_playContent` 先置 content 再 await，广告残留进度被当正片位置，误触发中插 | A04 | [已核] `ads.dart:1050` 先写 phase，`:1055` 才 await；`:1307-1330` content 相用 `p.position` 判中插 |
| 终审 7e | contentError 契约随"正片 open 失败也汇入"同步改文档与 CHANGELOG | A05（代码+dartdoc+CHANGELOG）、C17（README） | |
| 终审 1 | 不做泛化队列；`_leaveKeepAlive` 的网络重开挪出队列 | A07 | [已核] `:1771-1784` 两处 await 网络在队列内 |
| 终审 2 | 不给公开 `MovaCutover` 加 `commit(expect:)`；用操作代际 | A01、A02、A03 | [已核] SPEC.md:246-249 |
| 终审 3 | LoadSpec = 记录并重放 + 显式理由；ABR hold 改带尝试号的租约 | A09、A10、A11 | |
| 终审 4 | resume 与初始 arm 共用一个闸门，迁移不能原样搬 | A08 | 同 7a |
| 终审 5 | 广告时钟默认运行、只在 playing true→false 时暂停；意图在 `old.pause()` 前取；和 P1-14 一起定 | A18、A20、A21 | [已核] `MovaState.playbackIntent` 默认 **false**（`state/state.dart:235`），所以 A19 先修替身 |
| 终审 6 | ads 侧 33 处用 FakeCutoverCtl，commit 只回固定布尔，P0-2 看不见 | S01、A02、A03 | [已核] `test/core/ads_test.dart` 33 处；`fake_api.dart:652-655` |
| 终审 8 | 动 seek/闸门/ABR/keepAlive 必须配真机，先补基线、统一 F3 口径 | CP0、CP1 | |
| 终审 9 | 成本含设备时间 | 第 7 节 | |

#### Codex 对上一轮的 6 条异议

| # | 异议 | 本计划的处理 |
|---|---|---|
| 1 | P1-23 不应改成注册表 | 采纳：C01 只修 README 与构造说明，`createMovaEngine` 仍是标准构造 |
| 2 | P1-9"构造即开启"改变关闭态契约 | 采纳：保留开关；Mini 两个入口一致遵守 enabled；`MovaAds(api, cutover:)` 旧语义逐字不变，只有新的 `MovaSession` 自动识别 |
| 3 | 模型下载"必定超时"措辞错 | 采纳：写"低速下易失败、无流式与续传"；修复随 STT 外迁暂缓 |
| 4 | P2-32 措辞不完整 | 采纳：C11 的断言与文档用新措辞 |
| 5 | 默认接探针仍是改决策 | 采纳为待拍板 5，明写"推翻旧决定" |
| 6 | 不能所有命令一条队列 | 采纳（与终审 1 一致）：第 2.5 节三分法 |

#### CLAUDE.md「剩余任务」里的评审遗留

| 项 | 内容 | 提交 |
|---|---|---|
| ② | `MovaWarmPlan` 没有方向，content→ad 换指后几个微任务里广告继承了正片倍速 | A27（Transition 给广告方向的 plan 固定 `rate: 1.0`） |
| ③ | pod 第二条广告的 `cutoverTo` 回落成普通 `open` | CP0 复现 + A27（会话改用 prepare+commit，不再走一次性 cutoverTo）+ CP2 验证 |
| ④#10 | play/seek 钩子异步返回后校验 | 已存在；A06 把代际来源从 `_openGen` 换成已接受会话 |
| ④#13 | 模型下载 sha256 | 不做（需 `crypto` 依赖，且 STT 外迁） |
| ④#19 | 预览队列吞异常 | B08 |
| ④#22 | STT 启动失败回滚 | 回滚已存在（[已核] `stt/service.dart:100-106`）；`rethrow` 去留在 C13 |
| ④#24 | 手势轴向 | B14 |
| ④#25 | `trackCount`/`maxZoom` 构造期 assert | B14 |
| ④#29 | `patch.dart`/`mova_platform_interface.dart` 缺注释 | C17 |

#### 评审第 6 节"可以收进库内部的逻辑"对照

| 项 | 去处 |
|---|---|
| `createMovaEngine` vs `MovaEngine()` | C01（不做注册表） |
| 命令式用法清晰度列表 | A12 |
| auto 档 ABR | A16（默认关） |
| 错误黑名单 | A13、A14b |
| `MovaAds(api, cutover: api)` | A23（`MovaSession` 自动识别） |
| ads+playlist 组合 | A25 |
| 广告计时 | A18、A20 |
| audioOnly 自动关预览/STT | B08（预览服务不探 `.vtt`、不抽帧）、B10（audioOnly 下 STT 不启动） |
| wifiOnly 探针 | C12（待拍板） |
| 亮度、方向、系统栏还原 | B04 |
| 全屏路由 | C05 |
| 后台暂停 | A21 |
| 拖动时控制条续期 | C04 |
| 注入对象所有权、缩略图目录隔离 | C13、B09 |
| 有封面时精确首帧 | A14（待拍板 7） |

#### 审计修订：此前被悄悄丢掉的子项，与名义成立需改实的挂靠

| 项 | 承接 | 说明 |
|---|---|---|
| P1-9 `playlist.enabled` 只挡 NextUp；Mini `show()` 要遵守 `enabled` | A25（playlist）、C02（Mini） | 会话路径 `enabled=false` 时 next/previous/自动连播 no-op；旧直连路径行为不变（逐字） |
| P2-11 feed 预取只拉 64KB、HLS 只拿 m3u8、force close 断连接复用 | **暂缓**（1.4）+ C17 写限制 | 预取深度要新配置项与宿主取舍；B12 只修过期检查与错误隔离 |
| P2-24 `stallPolicy` 实例被多引擎共用 | C13 | `policyFactory` 每引擎各取一个实例 |
| P2-33 过期 dartdoc（`api.dart:368-371`、`stt_config.dart:36,45`） | C17 | 同 1.3 P2-33 行 |
| audioOnly 时也应关闭 STT（不止预览） | B10 | B08 只管预览；B10 本就改 `stt/service.dart` |
| P1-21 过期 tree-shaking 注释、抽帧器默认 | C12（注释）、C11（抽帧器默认文档） | `connectivity_plus` 已是硬依赖，注释已不成立 |
| README 首例 `engine.open()` 未 await 未 catch | C01 | README:106 [已核]；首例补 `await` 与 `catch` |
| Codex 异议 2：mini/cutover/STT-无引擎 的“可观测禁用状态”（目前只 Mini 的 `showInPage` 查 enabled） | C02 | 补 cutover 关闭、STT 无引擎的 debug 一次性提示；只读 getter 命名 [待核] |
| P1-22 模型下载非原子写盘 + 10s 超时（C09 只撤导出，缺陷还在） | **暂缓**（1.4） | 随 STT 迁往 mova_stt；C09 在 STT 入口 dartdoc 与 README 写明已知限制 |
| P1-3 auto 档 ABR 默认仍关 | 说明默认值策略 | 见 1.3 P1-3 行与待拍板 11 |
| P2-25 的 B05 文件清单漏 `engine.open` 调用点 | B05 | 已补进 3.2 B05 行 |
| 7a/7b 的 `_reopenLiveSource` 也被非 keepAlive 的 `backToLiveEdge` 使用 | A07（keepAlive）+ A10（非 keepAlive） | 见 1.3 终审 7b 行 |

### 1.4 不做 / 暂缓

| 项 | 结论 | 理由与触发条件 |
|---|---|---|
| `MovaEngine` 全拆七个子控制器 | 暂缓 | 无 bug 驱动；seek/首帧/ABR 每次改动都要 280 次真机。触发：跑批脚本自动化稳定（CP0 修好后连续两次全量无 HARNESS 问题）且有新需求要改这些模块 |
| 泛化命令队列 + 内部 Signal | 不做 | 终审 1、Codex 异议 6；长操作排队会让 pause/换源被网络卡住 |
| 公开 `MovaCutover.commit(expect:)` | 不做 | 终审 2；会破坏所有 `implements MovaCutover`；SPEC.md:246-249"四个动词够用" |
| 预加载下一集 | 暂缓 | 新增资源消耗，需 opt-in 设计；与中插预热抢单影子槽。触发：宿主明确需求 |
| 默认实现注册表（P1-23 原修法） | 不做 | Codex 异议 1 |
| 弹幕条目随内容走（P1-8 子项） | 暂缓 | 需要新的弹幕数据源 API；`MovaOpts.danmaku.items` 仍作默认值 |
| 弹幕单 CustomPainter 重写（P1-17 子项） | 暂缓 | B06 先把"前跳必卡"修掉；painter 重写是性能优化，等真机帧耗时数据 |
| OS 级窗口全屏端口（P1-11 子项） | 暂缓 | 桌面窗口全屏需要新平台插件代码；C05 先做应用内全屏 |
| 池外直播引擎停流（P2-11 子项） | 暂缓 | 需要 `stop()`（释放解码不销毁）能力，属第 7 节能力缺口 |
| 真 ABR（带宽估计、升档、时间窗） | 暂缓 | 能力缺口，非缺陷 |
| PiP actions/autoEnter/sourceRectHint | 暂缓 | 能力缺口；需要原生代码 |
| 音频焦点、耳机拔出（P2-29） | 暂缓 | CP0 先确认 media_kit 自身处理情况 |
| 手势竞技（P2-16） | 暂缓 | CP0 复现后再排 |
| STT 模型下载流式落盘、原子写盘（先写临时文件再 rename）、放宽 10s 超时、sha256 | 暂缓 | 随 STT 迁往 mova_stt；sha256 需 `crypto` 依赖。**C09 只撤导出，缺陷仍在**，所以在 STT 入口 dartdoc 与 README 写明已知限制（P1-22） |
| feed 预取深度（只拉 64KB、HLS 只取 m3u8）、force close 断连接复用（P2-11 子项） | 暂缓 | 需要新配置项（如 `prefetchBytes`）与宿主取舍；B12 只修过期检查与错误隔离，C17 在 README 写明限制 |
| core 去 mpv 概念（P3-1） | 不做 | 做第二内核时再升级 |
| 评审第 7 节能力缺口：音轨/字幕轨与外挂字幕、截图 API、诊断快照与 stats 浮层、进度条已缓冲、长按 2 倍速、广告追踪与 VAST/VMAP、媒体会话与通知栏、`stop()`/循环/前向缓冲配置 | 暂缓 | 都是新能力，不是这次要理清的缺陷；混进来会把一条修复分支变成功能分支。VAST 解析库、`audio_service` 若将来要做，都需要用户同意引入依赖 |
| DRM、投屏、离线下载 | 不做 | 定位不符，C17 在 README 写明不支持 |
| iOS/macOS 真机 | 不在范围 | 没有 Mac；本计划所有"通过"只指 Android STG-AL00 与 Windows |

---

## 2. 目标架构

### 2.1 模块图

```
                     ┌──────────────────────── ui/ (Flutter) ─────────────────────────┐
                     │ MovaPlayer ─ MovaChrome(每视图一份, C04) ─ 皮肤/组件/手势          │
                     │ MovaView  MovaAutoPause(守卫)  MovaMini/MovaMiniHost             │
                     │ MovaFeedPlayer  NextUp/AdOverlay(读会话游标, A30)                 │
                     └───────┬──────────────────┬─────────────────────┬────────────────┘
                             │只依赖 MovaApi     │读 MovaSession        │借用 MovaApi
                             ▼                  ▼                     ▼
┌──────────────────────────────── core/ (纯 Dart) ───────────────────────────────────────┐
│                                                                                         │
│  core/session/  MovaSession ── 唯一的内容级写者（打开哪段内容、何时切）                    │
│     timeline.dart  (纯函数：条目→节点、pod、到期判定)                                     │
│     cursor.dart    (不可变游标：epoch/item/node/phase/resumeAt)                          │
│     ad_clock.dart  (可暂停广告时钟，注入时钟)                                             │
│     transition.dart(内部：plan 推导 + epoch 令牌 + 过期不回落)                            │
│     arbiter.dart   (纯函数：节点失败 vs 传输失败、去重)                                   │
│     events.dart    (MovaSessionEvent，带 nodeId/epoch)                                   │
│        ▲                       ▲                                                        │
│  MovaAds（转发壳）      MovaPlaylist(api, ads:)（共享会话）/ MovaPlaylist(api)（旧直连）  │
│        │                                                                                │
│        └──借用──▶ MovaApi ◀── `is MovaCutover` 时用四个动词（prepare/commit/abandon/cutoverTo）
│                     │                                                                    │
│        MovaCutoverEngine（代理；操作代际 + _WarmSlot，A01/A02）                           │
│                     │ 拥有：1 个生效引擎 + ≤1 个影子                                       │
│                     ▼                                                                    │
│        MovaEngine（_LoadSpec、ABR 租约、独立恢复闸门；attempt/seek/recovery/keepAlive）    │
│                     │ 拥有                                                               │
│                     ▼                                                                    │
│        MovaKernel（mpv_kernel.dart 是唯一允许 import media_kit 的 core 文件）             │
│                                                                                         │
│  core/feed/  MovaFeed + 引擎池：不进 cutover、不进会话、不调用 commit；只复用错误分类函数    │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 依赖方向与 core 纯净性

- `core/session/` 只 import `core/api.dart`、`core/cutover/ctl.dart`、`core/cutover/plan.dart`、`core/model/*`、`core/options/*`、`core/events/*`；**不 import** `engine.dart`、`cutover_engine.dart`、任何 `ui/`。`purity_test` 现有规则（core 不 import Flutter，media_kit 例外只有 `kernel/mpv_kernel.dart`）自动覆盖新目录。
- `MovaAds`、`MovaPlaylist` → `MovaSession`；`MovaSession` 不反向依赖它们。
- `ui/` → `MovaSession`（只读游标与事件）；`MovaSession` 不知道 UI 存在。
- `MovaMini` 只借用 `MovaApi`，与会话互不依赖；SPEC.md:384-386 定的"`MovaMiniMount` 不进 core"保持。
- feed 按 SPEC.md:237-239 不进 cutover；也不进会话。feed 复用的是 A13 的**错误分类函数**（`core/model/playback_error.dart`，判终结与否），**不是** `core/session/arbiter.dart` 的仲裁函数（节点失败裁决，只给会话用）；feed 不接入 `commit`，所以没有影子与操作代际。

### 2.3 新类型与接口签名

以下签名是落地的目标，命名沿用现有前缀与风格。注释规范（中文、简短、公开 API 带参数/返回/示例）落地时补齐，这里省略。

```dart
// core/session/timeline.dart —— 纯函数；类型随 MovaSession 导出，函数不导出
enum MovaNodeKind { pre, content, mid, post }

@immutable
class MovaNodeId {                       // 取代"广告位对象身份"（修 P3-3）
  const MovaNodeId(this.item, this.kind, this.ordinal);
  final int item;                        // 条目下标
  final MovaNodeKind kind;
  final int ordinal;                     // 同条目同类型里的序号（排期原顺序）
}

class MovaTimelineNode {
  final MovaNodeId id;
  final MovaAdBreak? adBreak;            // content 节点为 null
  final Duration offset;                 // mid 的插入点；pod = offset 相同的 mid
}

List<MovaTimelineNode> movaBuildNodes(int item, List<MovaAdBreak> breaks);
MovaTimelineNode? movaDueMid(List<MovaTimelineNode> nodes, Duration position, Set<MovaNodeId> played);
// 现有公开函数 dueMidRoll(breaks, position, played) 保留为包装，签名不变（ads.dart:26）

// core/session/cursor.dart
enum MovaSessionPhase { idle, pending, ad, toContent, content }   // toContent 是 A04 新增
@immutable
class MovaCursor {
  final int epoch;                       // load/jumpTo/dispose 时递增，即现在的 MovaAds._gen
  final int item;
  final MovaNodeId? node;
  final MovaSessionPhase phase;
  final Duration contentResumeAt;        // 即现在的 _contentResumeAt
}

// core/session/ad_clock.dart
class MovaAdClock {
  MovaAdClock({DateTime Function()? now});    // 注入时钟：DateTime.now 不跟 fakeAsync（同 engine.debugClock）
  void start(Duration length, void Function() onExpire);
  void pause();                               // 观测到 playing true→false 时调用
  void resume();                              // false→true
  void cancel();
  Duration? get remaining;
  bool get running;
}

// core/session/session.dart
enum MovaLoadOutcome { accepted, rejected, superseded, disposed }

class MovaSession {
  /// [api] 借用，不 dispose；[ads] 默认取 api.options.ads；api is MovaCutover 时自动启用无缝切换
  MovaSession(MovaApi api, {MovaAdConfig? ads, List<MovaPlaylistItem> items = const [],
      int initialIndex = 0, bool autoAdvance = false});

  Future<MovaLoadOutcome> load(MovaSource content, {List<MovaAdBreak>? breaks});
  Future<MovaLoadOutcome> loadDeferred(MovaSourceResolver resolve, {List<MovaAdBreak>? breaks});
  Future<MovaLoadOutcome> jumpTo(int index);
  Future<MovaLoadOutcome> next();
  Future<MovaLoadOutcome> previous();
  Future<void> playAdNow(MovaAdBreak ad);
  void skip();
  void notifyClicked();

  MovaCursor get cursor;
  List<MovaPlaylistItem> get items;
  Stream<MovaSessionEvent> get events;
  Stream<void> get changes;
  Stream<void> get contentEnded;
  Stream<Object> get contentError;        // 解析失败 + 正片 open 抛出（A05 起）
  // 与 MovaAds 同名的只读项：isShowingAd/currentBreak/isAdPending/pendingBreak/
  // delayRemaining/adPosition/canSkip/skipIn
  Future<void> dispose();
}

// core/session/events.dart
sealed class MovaSessionEvent { int get epoch; }
final class MovaNodeStart  implements MovaSessionEvent { final MovaNodeId node; ... }
final class MovaNodeEnd    implements MovaSessionEvent { final MovaNodeId node; final MovaNodeEndReason reason; ... }
final class MovaNodeFail   implements MovaSessionEvent { final MovaNodeId node; final Object? error; final MovaNodeFailVerdict verdict; ... }
final class MovaItemChange implements MovaSessionEvent { final int index; ... }
enum MovaNodeEndReason { completed, skipped, failed, superseded }

// core/session/arbiter.dart —— 纯函数
enum MovaNodeFailVerdict { retryNode, skipNode, abandonPod, failItem, ignore }
MovaNodeFailVerdict movaArbitrate(MovaNodeFailure f, {required MovaAdConfig ads, required bool engineRecovering});

// core/model/playlist.dart —— 加可选字段，不破坏
class MovaPlaylistItem { ...; final List<MovaAdBreak>? adBreaks; }   // null = 用 api.options.ads.breaks

// core/model/playback_error.dart（A13）
enum MovaErrorKind { load, decode, network, stream, giveUp, other }
class MovaPlaybackError {
  final MovaErrorKind kind; final bool fatal; final String? code; final String? uri; final Object raw;
}
// MovaGiveUpError 改为 MovaPlaybackError 的子类（fatal=true），类名不变
// MovaErrorEvent 加只读 getter `bool get fatal`（非终结错误照发事件，保持兼容，但不写 state.error）

// core/engine/load_spec.dart（不导出，A09）
enum LoadReason { open, retry, failover, quality, timeshift, liveEdge }
@immutable
class LoadSpec { final int sourceIndex; final String uri; final MovaQuality? quality;
                 final Duration? timeshiftBehind; final Duration? resumeAt; final LoadReason reason; }
```

公开接口的小幅增量（都不破坏现有调用）：
- `MovaAds.load`/`loadDeferred` 返回类型 `Future<void>` → `Future<bool>`（A25）。`Future<bool>` 是 `Future<void>` 的子类型，现有 `await`、丢弃返回值、tear-off 都照常编译；只有继承 `MovaAds` 并覆写 `load` 的子类会受影响（极少，CHANGELOG 写明）。
- `MovaPlaylist(api, {MovaAds? ads})`（A25）。
- `MovaAbrConfig.probeVariants`（默认 true，A12）、`MovaAbrConfig.manageAuto`（默认 false，A16）。
- `MovaAdConfig.midRollSnapback`（默认 `MovaAdSnapback.all` = 现状，A29）。
- `MovaCutoverChange.reason`（可选，A28）。
- `MovaSource.headers/userAgent/start`（C07）。
- `MovaAds.session`（只读 getter，A23 公开）：A25 的 `MovaPlaylist(api, ads:)` 要从传入的 `MovaAds` 取共享会话，没有这个访问口就只能让 `MovaPlaylist` 反向依赖 `MovaAds` 内部。A22 搬迁期内部可见、不导出。
- B04 新增两个公开类型：`MovaOrientationConfig`（宿主声明一次允许方向）、可选端口能力 `MovaBrightRestore`；亮度还原带 opt-out 开关（命名落地时定 [待核]）。
- C07 的 `MovaHttpFetch` 请求头：给 `get(Uri)` 直接加 `headers` 是**对宿主实现的破坏性变更**（`implements MovaHttpFetch` 的自写 fetcher 覆写签名不匹配），见待拍板 17；推荐用可选能力接口 `MovaHeaderedHttpFetch` 旁路，原签名不动。
- 进度快照用新的可选能力接口 `MovaProgressSource { MovaProg get progressValue; }`（B02），**不**往 `MovaApi` 抽象类里加成员（那会破坏 `implements MovaApi` 的宿主）。

### 2.4 现有字段如何迁移

| 现有字段（文件:行） | 去处 | 提交 |
|---|---|---|
| `MovaAds._gen`（ads.dart:195） | `MovaCursor.epoch` | A22 搬、A24 公开 |
| `_phase`、`_current`、`_pending`（:201-202、:271） | `MovaCursor.phase/node` | A22 |
| `_played: Set<MovaAdBreak>`（:203） | `Set<MovaNodeId>` | A24（行为：修 P3-3） |
| `_contentResumeAt`、`_lastContentPosition`（:204、:235） | 游标 + 会话内部 | A22 |
| `_slotTimer`、`_delayTimer`（:247、:277） | `MovaAdClock` 两个实例 | A18 |
| `_loadTimer`（:296） | 保持墙钟 Timer（独立期限，不随暂停） | — |
| `_breaks`、`_cfg`、`_onAdEvent`、`_enabled`（:144-147，构造快照） | 会话：`_cfg` 仍构造快照；`breaks` 按条目取（条目 `adBreaks ?? cfg.breaks`） | A23 |
| `_resuming`、`_landingAd`、`_sttWasRunning`、`_contentRate`（:259、:266、:241、:229） | 原样搬进会话 | A22 |
| `MovaPlaylist._index`、`_jumpGen`（playlist.dart） | 有 `ads:` 时由会话游标承担；旧构造不变 | A25 |
| `MovaCutoverEngine._shadow/_warmSource/_warmAt/_warmPlan/_policy/_warmClock/_holding/_heldAtTarget/_warmLive/_shadowBuffering/_readyCompleter/_readyTimer/三个影子订阅`（cutover_engine.dart:96-170） | 收进一个 `_WarmSlot` 对象 | A01（机械） |
| `MovaEngine` 内各加载路径的局部 uri（`switchQuality` 的 `playUri` :2438、时移 builder 结果 :2197-2199） | `LoadSpec? _currentLoad` | A09 记录、A10 重放 |
| `_abrHold`、`_abrHoldTimer`（engine.dart:553-563） | `_AbrLease{attemptId}` | A11 |
| `_resumeGateArmed` + 共享 `_frameGate`（:197、:429） | 独立 `_resumeGate` 实例 | A08 |
| `MovaApi.showControls/hideControls/showHud/setDragging/uiStates`（api.dart:302-345） | `MovaChrome`，旧成员以 dartdoc + CHANGELOG 公告桥接一个版本（不加成员级注解） | C04 |
| `MovaOpts.theme/strings/gesture/controls/danmaku`（options.dart:62-102） | `MovaPlayerStyle`，旧字段 `@Deprecated` 兜底 | C06 |

### 2.5 命令三分法（落到具体命令）

规则：**短迁移**在一段同步代码里完成（中间没有 `await`）；**长操作**在入口取令牌，每个 `await` 之后校验，过期就只做清理、不写共享状态、不回落；**抢占**在同步前缀里改意图/标志并取消计时器，不排在任何网络操作后面。

| 所有者 | 短迁移（同步） | 长操作（带令牌） | 抢占（同步前缀） |
|---|---|---|---|
| MovaSession | 进度 tick 判中插、广告位置更新；Done/首帧/错误到达后的"下一节点"决策；pod 簿记（`_played`）；广告时钟 pause/resume；游标写入；仲裁裁决 | `api.open`、`prepare`、`commit(waitForReady)`、`cutoverTo`（若仍用）、resolver、STT start/stop；令牌 = `epoch` | `load`/`loadDeferred`/`jumpTo`/`next`/`previous`（`epoch++`、取消计时器、`unawaited(abandon())`，都在第一个 await 之前）、`skip`（相位与可跳过判定同步）、`dispose` |
| MovaCutoverEngine | 影子认领（`commit` 里的 claim）、换指（`_active =`、`_epoch++`、重挂转发）、相位迁移 | `prepare` 的影子 open/seek（令牌 = 槽对象身份）、`_commitNow`（令牌 = 操作代际 `_op`）、`cutoverTo` | `open`/`reload`（`_op++` + 同步 abandon）、`abandon`（同步清槽并唤醒等待者，已是这样：cutover_engine.dart:799-836）、`dispose`、`pause`（直通） |
| MovaEngine | open 接受后的会话/尝试推进与重置表；失败认领（`_failedAttemptId`）；seek 寄存/替换；首帧落地后的 rendered/续播决策；keepAlive 相位迁移（本地队列内，只做同步段） | beforeOpen/beforePlay/beforeSeek 钩子（令牌 = 已接受会话 + `_pauseSeq`，A06）；`_loadKernel`（会话 + 尝试）；`loadQualities`（会话 + 清晰度修订号，A12）；keepAlive 回边缘/重开（**挪出队列**，令牌 = 尝试号 + 最新意图，A07）；recovery 重载 | `pause`（同步写意图、`_pauseSeq++`、立即下发，已是这样：engine.dart:1905-1921）、`dispose`（同步置标志与取消计时器；B15 把 `_hudTimer/_autoHideTimer` 挪进同步前缀） |

不跨引擎加锁；同一个原生 player 的效果顺序仍由内核自己的串行器保证（`mpv_kernel.dart` 的属性队列不动）。

### 2.6 必须保住的隐含语义

| # | 语义 | 出处 [已核] | 守护 |
|---|---|---|---|
| 1 | `open()` 返回 true 只表示"被接受为当前源"，不是首帧、不是加载成功；recovery 接管的失败仍返回 true | engine.dart:1331-1341 | `playlist_test.dart`；A25 新增"接受≠首帧"用例 |
| 2 | 播放列表下标只在 accepted 且未被更晚的跳转取代时前进 | playlist.dart:144-164 | 现有 playlist_test；A25 在会话路径上复刻 |
| 3 | `loadDeferred`：解析器直到正片要打开或预热时才调；同一次加载只调一次、在途共享；旧会话结果丢弃 | ads.dart:484-517 | `ads_session_test.dart`（4 条）；A23 扩展到按集 |
| 4 | STT：`attach` 不停识别；pod 第一条广告采样 `isRunning` 并停 STT，回正片只恢复本来开着的 | stt/service.dart:121-125；ads.dart:787-790、1080-1083 | ads_test STT 分组；B10 不动 `_started` |
| 5 | 借用不 dispose：Ads/Playlist/Session 只释放自己的订阅；Ads dispose 会 abandon 影子 | ads.dart:1375-1386；playlist.dart dispose | A22 机械提交保持；A23 新增"会话 dispose 后 api 仍可用" |
| 6 | Mini：`hide()` 不暂停，`close()` 先 `pause()` 再 `setMini(false)` 再 `onClosed`；`showInPage` 检查 enabled | ui/mini/mini.dart:223-262、174 | mini 测试；C02 只让 `show()` 也查 enabled，不动 hide/close |
| 7 | pod：offset 不晚于续播点的 mid 才算同一 pod；串联的只走 `_playAd` 不再 `_beginDelay`；`abandonPod` 只吞同一插入点 | ads.dart:602-610、1175-1192、1020-1028 | ads_test pod 分组；A24 换节点身份后逐条保持 |
| 8 | `contentEnded` 在正片和所有后贴片之后才发；正片在 pending 期间播完则丢弃那条中插 | ads.dart:1112-1143 | ads_test；A25 用它驱动下一集 |
| 9 | `skip()` 在 pending、未到可跳过点时是空操作；slot 到期算 completed 不算 skipped | ads.dart:573-578、910-918 | ads_test |
| 10 | 重试会再次发 `started` | ads.dart:993-1001 | ads_test |
| 11 | `_resuming` 防 slot 到期、Done、skip 三路同时续播 | ads.dart:1150-1207 | ads_test；A18 时钟到期仍走同一入口 |
| 12 | 广告 delay/duration 不依赖媒体时间轴，一律 Timer | SPEC.md:290-296 | A18 时钟仍是 Timer + 剩余时长，不读 duration、不 seek |
| 13 | 是否等待就绪只在 `MovaAdConfig.waitsFor()` 一处决定，会话里不许对 kind 分支 | SPEC.md:270-288；ads.dart:634-637 | `openness_ad_test.dart`；A27 的 plan 推导不得引入 kind 判断（"后贴片不预热正片"是预热方向判断，不是等待判断，A03 写在 `_warmContentBehindAd` 里并注明） |
| 14 | 影子预热失败不冒成在屏错误 | cutover_engine.dart:523-533 | cutover 测试；A15 只认 fatal 后仍保持 |
| 15 | 广告方向预热停在第 0 帧（含零目标回绕）；正片方向 `pauseWhenReady` 防漂移 | cutover_engine.dart:172-194；ads.dart:1351-1362 | cutover_engine_test、ads_test |
| 16 | cutover 外层身份、四条流不随换指重建；`renderEpoch` 递增；旧引擎先 markRetired 再异步 dispose，不复位方向 | cutover_engine.dart:706-728 | cutover_engine_test；A02 的事务化不改这段顺序 |
| 17 | 预热静音只碰 mpv `mute`，不碰系统音量 | cutover_engine.dart:768-791（Q13） | cutover_warm_mute_test |
| 18 | 广告 1x；回正片恢复用户倍速；`_resuming` 期间不让广告倍速覆盖正片倍速 | ads.dart:873-884、1068-1076、1309-1314 | ads_test 倍速分组；A27 给广告方向 plan 固定 1.0 |
| 19 | 内部重试、换档不开新 QoE 会话；每次 `open` 只发一次 SourceChange+Ready | engine.dart:1350-1382、1482-1491 | engine_recovery_test、report 测试；A10 的 reason 表显式写出 |
| 20 | 换档不清列表、不发 SourceChange；回边缘不归零时长；公开 `reload()` 等于新的 `open` | engine.dart:2442-2457、2591-2620、2547-2554 | A09/A10 的 reason 表 + 回归 |
| 21 | open 后的 seek 一律寄存；续播校验最多 3 次、500ms 容差；4s 寄存兜底；10s ABR 屏蔽上限 | engine.dart:1290-1301、2115-2159、230、563 | engine_seek_drop_test、first_frame_engine_test；A10/A11 不改这些常量 |
| 22 | 内部换档不再发 FirstFrame | engine.dart:1055 | first_frame_engine_test |
| 23 | keepAlive：mute/vid 保存后原样还原；pause 先停后还原；请求存在时换源以暂停态加载 | engine.dart:1683-1708 | keep_alive 测试；A07/A08 不动这三段 |
| 24 | dispose 幂等；dispose 后所有公开动词静默 no-op | engine.dart:2819；CHANGELOG Unreleased | engine_dispose_race_test、engine_verbs_test |
| 25 | `playAdNow` 只在 content 相生效，同时只排一条 | ads.dart:541-562 | ads_test |
| 26 | open/cutoverTo 等待期间旧引擎的残留 tick 不能把新广告判成已出首帧 | ads.dart:851-872 | `ad_stale_first_frame_test.dart` |
| 27 | feed 双画面并存、不进 cutover | SPEC.md:237-239 | engine_pool_test；本计划不动这条 |

---

## 3. 提交阶梯

### 3.1 规则

1. 分支 `jelon/mova-orchestration` 从 main 拉出，`git push -u origin jelon/mova-orchestration`。只改 `mova/` 目录；monorepo 其他目录别人有未提交改动，不碰。
2. **每个提交**：`flutter analyze lib test` 0 issues；`flutter test` 全绿；新函数配单测；提交后把实测测试总数写进提交说明；**每个块/检查点结束并提交后，立刻用当次实测 `flutter test` 输出回写 CLAUDE.md 的测试基线与相关 `doc/plans/*.md`**（项目 CLAUDE.md 约定；不是合并前一次性回写，第 9 节 C17 只对账其余内容）。
3. **机械搬迁提交**不改任何断言、不改行为；提交说明附 `git diff --color-moved=zebra` 的统计，并逐条列出为通过编译不得不做的非搬迁改动（如私有字段改为库内可见）。
4. **行为提交**：每条行为变化都有新增或改写的测试；改写旧断言要在提交说明里逐条写"旧断言为什么错"。
5. 标 `@Deprecated` 时，同一提交里迁移包内所有调用点，或在桥接点加 `// ignore: deprecated_member_use_from_same_package` 并注明理由，否则 analyze 不是 0。**成本提醒**：`analysis_options` 继承 flutter_lints，该 lint 对包内 lib 与 test **都报**；`MovaOpts.theme/strings/gesture/controls/danmaku` 在 lib 约 61 处读取、test 约 22–24+ 处（本次 grep 近似值，落地前复核 [待核]），成员级 `@Deprecated` 会让 analyze 变红。因此 C04/C06/C08/C09 是否加成员级注解取决于待拍板 18；推荐默认“只在 CHANGELOG 与 dartdoc 公告、不加成员级注解”，export 级注解（C08/C09 的转导出）不触发包内警告。
6. 提交信息 `type(mova): message`，结尾带协作者行。子代理不得自行提交。
7. 每个块（准备 / B / A1 / A2 / C）结束后先走 Codex review（effort ≤ high），Claude 逐条终审，再进检查点。

### 3.2 总表

"类型"：机械 / 行为 / 新增（新能力，默认关或纯增量）/ 测试 / 工具 / 文档。"规模"是生产代码行数量级（不含测试）。"测试"列的 +N 是预估新增条数。

#### 准备块

| # | 提交 | 类型 | 主要文件 | 规模 | 依赖 | 测试 | 完成判据 |
|---|---|---|---|---|---|---|---|
| S00 | `chore(mova): 跑批收口改为按子项自动判据，缺判据不再整体 BLOCKED` | 工具 | `example/tool/run_matrix.py` 及 finalize 相关脚本 | 300–600（Python） | — | 脚本自测：用 r1030 的原始日志重放，得出的 PASS/FAIL/BLOCKED 与人工判读一致 | 对 r1030 证据重放，BLOCKED 只剩真缺用例的项（A31、C2、C7、F15、N18 等） |
| S01 | `test(mova): 交错时序测试脚手架` | 测试 | `test/support/fake_api.dart`、新增 `test/support/gated.dart` | 250–400（测试代码） | — | 只加能力，不改现有断言；+5 条脚手架自测 | 全量绿，现有 1752 条不改 |
| A19 | `test(mova): FakeMovaApi 按真实契约维护 playbackIntent`（原在 A2 块，前移到 S01 之后、CP0 之前；lib 未改） | 测试 | `test/support/fake_api.dart` | 30–60（测试代码） | S01 | 改写受影响断言，逐条列出 | open→意图=autoPlay，play→true，pause→false；不推 playing（保持终审 5 的前提）。注意：A20 要改写的 cutover 断言**不靠**这个替身（见 A20 行） |

S01 的内容见第 5.2 节（门控 open/play/pause/seek、可选推 playing、按源记录的 FakeCutoverCtl、可数 dispose 的引擎工厂）。

→ **CP0：补真机基线**（第 4 节）

#### 轨道 B 块（不碰 seek/首帧闸门/ABR/keepAlive）

| # | 提交 | 类型 | 主要文件 | 规模 | 依赖 | 测试 | 完成判据 |
|---|---|---|---|---|---|---|---|
| B01 | `fix(mova): 默认皮肤的缓冲与错误提示不再随控制条隐藏` | 行为 | `ui/skins/default_skin.dart`、`ui/components/overlays.dart` | 80–150 | — | +4：隐藏控制条后缓冲可见；锁定时错误层可点；pip/mini 时仍隐藏；自定义皮肤不受影响 | 不新增 `MovaSlot` 枚举值（宿主的穷举 switch 会坏）；改为 `MovaDefaultSkin.statusLayerNames`（默认 `{buffering, error}`）把这两个 center 组件挪到 `_BarVisibility`/`_HideWhen(locked)` 之外的状态层 |
| B02 | `feat(mova): 进度同步快照与订阅即重放` | 新增 | `core/state/progress.dart`（`MovaProgressSource`）、`engine.dart`、`cutover_engine.dart`、`ui/scope/selector.dart`、`bottom_bar.dart`、`gesture_layer.dart`、`testing/` | 150–250 | — | +6：暂停态重挂载显示当前位置；双击从当前位置算；cutover 换指后快照跟随新引擎 | `MovaApi` 抽象零改动 |
| B03 | `fix(mova): 底栏按组件名取子节点` | 行为 | `ui/slots/tree.dart`、`ui/components/bottom_bar.dart` | 80–150 | — | +6：remove/insertAfter 每个子节点各一条；直播布局不越界 | |
| B04 | `fix(mova): 亮度播种与离场还原，退出全屏还原宿主方向与系统栏` | 行为 | `engine.dart`（构造、`setFullscreen`、`dispose`）、`core/platform/ports.dart`（可选能力 `MovaBrightRestore`，新公开类型）、`platform_impl/brightness_impl.dart`、`orientation_impl.dart`、`MovaOrientationConfig`（新公开类型，宿主声明一次允许方向）、亮度还原 opt-out 开关 | 250–400 | — | +8 | 未声明时保持现行为（全方向），声明后还原到声明值 |
| B05 | `fix(mova): QoE 心跳先结算、恢复后清终结标记、上报重试与切换、异步采样绑定会话` | 行为 | `core/report/collector.dart`、`translator.dart`、`engine.dart`（`open` 调用点：sessionStart 采样时机，P2-25） | 150–250 | — | +10：恒速播放心跳 watchedMs 递增；404→备选救回→sessionEnd 非 failed；A 的迟到 sample 不写 B 的基线、不发 A 的心跳；seek 缓冲不计 rebuffer；sessionStart 在内核加载后采样 | [已核] 心跳直接读 `_tally`（collector.dart:208-215），sample 后只查 `_sessionOpen`（:219）；`_lastVideoBps` 无代际（:460-463） |
| B06 | `fix(mova): 弹幕前跳只移动游标、限制同屏数量、暂停与倍速跟随` | 行为 | `ui/components/danmaku.dart` | 150–250 | — | +6：从 30:00 续播活动弹幕数 ≤ 上限；暂停时位置不动 | [材料] 行号未复核 |
| B07 | `fix(mova): 预览网络请求受总期限约束且可取消，抽帧未确认落地不入缓存` | 行为 | `core/preview/fetcher.dart`、`service.dart`、`platform_impl/mpv_extractor_impl.dart` | 120–200 | — | +5：404 后 body 不结束，dispose 在期限内完成且主内核被释放；`_waitFor` 超时返回 null 不缓存 | [已核] 非 200 分支 `drain()` 无超时（fetcher.dart:66-68）；dispose 先 await `_queue`（service.dart:362）；`_waitFor` 返回值被丢（mpv_extractor_impl.dart:170） |
| B08 | `perf(mova): 预览队列最新优先、过期请求执行前丢弃，VTT 失败可重试，DVR 直播不抽帧，audioOnly 不探 VTT` | 行为 | `core/preview/service.dart`、`vtt_source.dart` | 100–180 | B07 | +6 | 含 CLAUDE.md 剩余任务④#19（队列吞异常） |
| B09 | `perf(mova): 缩略图按字节限额并限解码尺寸，磁盘缓存异步索引，缓存目录按引擎隔离` | 行为 | `core/preview/cache.dart`、`disk_cache.dart`、`platform_impl/thumb_dir_impl.dart`、`ui/components/preview.dart` | 250–400 | B08 | +8 | cutover 换指、feed 回收不再清别人的目录 |
| B10 | `fix(mova): 音频抽取器释放原生 Player，STT 字幕绑定会话代际，audioOnly 下不启动 STT` | 行为 | `platform_impl/mpv_audio_extractor_impl.dart`、`core/stt/service.dart` | 80–150 | — | +5（含 audioOnly 引擎不启动 STT）：抽取异常/超时后 Player 被 dispose；旧源迟到的 cue 不进 recent；`isRunning` 不因换源改变 | [已核] `_player` 从未赋值（:60、:71、:105） |
| B11 | `fix(mova): 引擎池尊重 open 接受结果、失败撤销绑定、按 sameAs 复用` | 行为 | `core/feed/engine_pool.dart` | 80–150 | — | +6：hook 拒绝→不置 ready、不显示旧素材；首开抛错后可重试；同 URL 换 mpvOptions 重开 | [已核] :258、:271、:274、:285 |
| B12 | `fix(mova): feed 条目与页面状态滑窗回收，预取校验过期，邻居预热错误隔离` | 行为 | `core/feed/feed.dart`、`feed_prefetcher.dart`、`ui/feed_player.dart` | 150–250 | B11 | +6：浏览 1 万条后缓存条数有界 | [材料] |
| B13 | `fix(mova): 守卫豁免全屏，PiP 回流只作用于发起进入的引擎` | 行为 | `ui/guard/auto_pause.dart`、`engine.dart`（`_pipSub`） | 60–120 | — | +4 | |
| B14 | `fix(mova): 手势与皮肤小缺陷` | 行为 | `gesture_layer.dart`、`ui/slots/tree.dart`、`default_skin.dart`、`common.dart`、`gesture_config.dart` | 150–250 | B03 | +8 | `vSensitivity` 生效；patch 路径拼错 debug 断言；锁定按钮进组件树并跟随控制条；弹层可滚动；手势轴向；`trackCount`/`maxZoom` 构造期 assert；`allowWhenLive` 文档对齐 |
| B15 | `perf(mova): 位置标签按秒重建、MovaPlayer 缓存组件树、镜像事件去重、dispose 同步取消 UI 计时器` | 行为 | `bottom_bar.dart`、`ui/player.dart`、`engine.dart`（setter 去重、dispose 前缀） | 100–200 | B03 | +6；可能改写 1–3 条"传同值也发事件"的断言 | |
| B16 | `feat(mova): 桌面与无障碍：按钮可聚焦带语义，悬停唤出控制条，快捷键（默认关）` | 新增/行为 | `ui/components/common.dart`、`ui/player.dart`、`MovaCtrlsConfig.shortcuts` | 300–500 | B14 | +10 | 可聚焦与语义属修缺陷默认开；快捷键是新能力默认关 |

#### B 块第四批落地记录（2026-11-03）

本批仅 B13 → B14 → B15 → B16，B03 依赖已满足。每个提交前执行 `flutter analyze lib test`（0 issues）和全量 `flutter test`；基线 1837。

| 提交 | flutter test 实测 | 新增 | 现有断言变化 |
|---|---:|---:|---|
| B13 | 1841 | +4 | 无 |
| B14 | 1849 | +8 | 无效 patch 路径改为 debug 断言；默认树快照加入 lockToggle（同时更新 Bilibili 增量基准）；mini 时页面锁定入口隐藏 |
| B15 | 1855 | +6 | 5 处事件断言：rate 1 处，volume/brightness 各 2 处（存在同名重复测试）；未变化的钳制值不再重复通知 |
| B16 | 1865 | +10 | 无 |

与原计划的差异：
- B14 的手势轴向、`trackCount`/`maxZoom` 构造断言及对应测试已在代码中实现，本批保留；修正文档并补充灵敏度、patch、锁定显隐和弹层回归。
- B15 改写现有断言 5 处，超过预估 1–3 处，原因是音量和亮度用例各有重复一份；保留内核和端口实际写入检查。
- B16 除主要文件外，中央播放按钮和小窗关闭按钮补齐语义/提示；持久小窗位于 Overlay 之上时不创建 Tooltip 浮层，保留语义。快捷键默认 false。
- 生产变化同步记入 CHANGELOG，README 修正 B14 顶栏追加示例并说明 B16 操作；新增回归测试文件。按用户明确要求不修改 CLAUDE.md、不 push、不转派。
- 本记录仅覆盖四个代码提交及自动化验证，不代表真机检查点或后续 A/C 块已完成。

#### 轨道 A1 块（引擎与切换层）

| # | 提交 | 类型 | 主要文件 | 规模 | 依赖 | 测试 | 完成判据 |
|---|---|---|---|---|---|---|---|
| A01 | `refactor(mova): cutover 预热状态收进 _WarmSlot` | 机械 | `core/cutover/cutover_engine.dart` | 200–300（搬） | — | 不改 | `test/core/cutover/` 现有约 108 条原样绿 |
| A02 | `fix(mova): cutover 操作代际与提交事务归属` | 行为 | `cutover_engine.dart` | 150–250 | A01、S01 | +12（真实 `MovaCutoverEngine` + 门控假引擎，见 5.3 的 1/4/5/6/7）；可能改写 0–3 条 | 见 3.3 |
| A03 | `fix(mova): 换集与后贴片不复用旧影子，广告侧各 await 校验加载代际` | 行为 | `core/ad/ads.dart` | 80–150 | A02 | +10（含 5.3 的 1/2/3/9，用真实 cutover 引擎） | 见 3.3 |
| A04 | `fix(mova): 回正片过渡期不把广告进度当正片位置` | 行为 | `ads.dart` | 60–100 | A03 | +3（5.3 的 8） | 新增内部相位 `toContent`；`isShowingAd` 为 false |
| A05 | `fix(mova): 广告侧 open 失败全部汇流，正片 open 失败进 contentError` | 行为 | `ads.dart`、`CHANGELOG.md` | 60–120 | A03 | +6：cutoverTo 抛→广告失败策略；广告 open 被 hook 拒→跳过该广告位且不重试；正片 open 抛→contentError + idle；正片被拒→不报错 | `contentError` 的 dartdoc 与 CHANGELOG 同提交更新（终审 7e）；不新增 `MovaAdFailKind` 枚举值（宿主穷举 switch 会坏） |
| A06 | `fix(mova): 被拒的 open 不再作废在途 play/seek，暂停加载期间的 play 不被吞` | 行为 | `engine.dart` | 40–80 | — | +5（5.3 的 15） | play/seek 的代际改比已接受会话 `_sessionGen`；`_loadKernel` 双向纠偏，keepAlive 请求存在时不纠 |
| A07 | `fix(mova): 唤醒回直播边缘后按最新意图开播，网络重开移出待机队列` | 行为 | `engine.dart`（`_leaveKeepAlive`） | 60–120 | — | +5（5.3 的 16）；可能改写 1–2 条"setKeepAlive(false) 返回时已重开完成"的断言 | 见 3.3；`_reopenLiveSource` 也被非 keepAlive 的 `backToLiveEdge` 调用（`engine.dart:2581,2585`），本提交只改 keepAlive 路径，非 keepAlive 路径的按意图开播由 A10 的 liveEdge 重放覆盖 |
| A08 | `fix(mova): 唤醒恢复测量改用独立闸门，换源结束恢复测量` | 行为 | `engine.dart` | 60–120 | A07 | +5（5.3 的 17） | 见 3.3 |
| A09 | `refactor(mova): 记录当前加载规格（只记录，读取方不改）` | 机械 | `engine.dart`、新 `core/engine/load_spec.dart` | 200–350 | A06、A07 | 不改；+2 条只断言"记录正确"的白盒测试 | 读取方一行不改 |
| A10 | `fix(mova): 重试与回边缘重放有效加载规格` | 行为 | `engine.dart` | 100–200 | A09 | +10（5.3 的 18、19 前半；P2-3：恢复中用户 seek 改写续播点） | reason 表见 3.3 |
| A11 | `fix(mova): ABR 屏蔽改为带尝试号的租约，用户 seek 引起的缓冲不计入` | 行为 | `engine.dart` | 80–150 | A10 | +6（5.3 的 19 后半） | 10s 上限常量不变 |
| A12 | `fix(mova): 清晰度探测不覆盖手选档，引擎就绪后自行探测` | 行为 | `engine.dart`、`core/options/abr_config.dart`、测试 rig（默认 fetcher） | 100–200 | A10 | +6（5.3 的 20；命令式 open 后列表非空；同会话只探一次；rig 默认 fetcher 换 noop 后逐个核对 `.m3u8` 用例） | `probeVariants` 默认 true 的方案二选一见待拍板 12（推荐 rig 默认 fetcher 换 noop）。原因 [已核]：测试里 `.m3u8` 出现 154 次，真实 `MovaEngine`+假内核会落到真实 `MovaIoHttpFetcher`（`engine.dart:654`），在 fakeAsync 里留 timeout 计时器，破坏 pendingTimers 断言 |
| A13 | `feat(mova): 播放错误分级：内核层接线与分类（只分类，不改 state.error 行为）` | 新增 | 新 `core/model/playback_error.dart`、`core/kernel/mpv_kernel.dart`（把 `logs` 前缀带到错误流）、`core/kernel/kernel.dart`（可选能力，`MovaKernel` 抽象零新增成员）、`core/report/error_policy.dart` | 250–400 | B01 | +10 | **为什么要有内核层接线**：`error_policy` 按 log 子系统前缀判终结，而 `MovaKernel.error` 是不带前缀的 `Stream<Object>`（`kernel.dart:140`、`mpv_kernel.dart:794` [已核]），前缀只在 `MovaStatsProbe.logs`（`stats_probe.dart:175` [已核]）。接口形态（可选能力 vs 事件里带分级）A13 开工前出设计 [待核]。本提交落地后 `state.error` 行为**不变** |
| A14 | `feat(mova): 判失败不依赖 recovery，END_FILE 订阅懒启动，有封面时打开 RESTART` | 行为 | `engine.dart`、`platform_impl/wiring.dart`、`core/kernel/mpv_kernel.dart`、`ui/view.dart` | 150–250 | A13 | +10；改写 `test/core/openness_host_test.dart:40` 的 `endFilesSubscribed isFalse` 断言（任务书记为 :30，实际核得 :40） | **推翻**"关闭时不订阅 endFiles"，待拍板 6/7。`END_FILE(error)` 转终结错误并写 `state.error`——先于 A14b 收窄，所以 404 地址在收窄前后始终有终结错误；待拍板 7 的“挂了封面就打开 RESTART”**在本提交落实**（`MovaPlayer(poster:)` 路径打开 `observeRestarts`）；“首帧判据不变”只指无封面路径 |
| A14b | `fix(mova): state.error 只放终结错误，遮罩显示 MovaStrs 文案` | 行为 | `engine.dart`、`ui/components/overlays.dart`、`MovaStrs` | 150–250 | A14 | +8；预计改写 10–25 条断言（非终结内核错误不再写 `state.error`） | **破坏性**：待拍板 16。`MovaErrorEvent` 仍对非终结错误发出（`fatal=false`），遮罩显示 `MovaStrs` 文案，原始文本只在 debug |
| A15 | `fix(mova): 广告判失败与影子放弃预热只认终结错误` | 行为 | `ads.dart`（`_onEvent`）、`cutover_engine.dart`（影子错误） | 40–80 | A14b | +4；改写 ads_test 中"任意错误判广告失败"的若干断言 | |
| A16 | `feat(mova): auto 档由 mova ABR 接管（灰度，默认关）` | 新增 | `engine.dart`、`abr_config.dart` | 80–150 | A11、A12、CP0 结论 | +5 | 默认关；CP0 若证实 mpv auto 不是静态最高档，则本提交只加开关不改默认文档措辞 |


#### A1 块第一批落地记录（2026-11-03）

本批仅 A01 → A02 → A03 → A04 → A05，基线 1865；由当前执行者亲自完成，不转派、不切分支、不 push、不使用真机。每个提交前 `flutter analyze lib test` 均为 0 issues。

| 提交 | flutter test 实测 | 新增 | 现有断言变化 |
|---|---:|---:|---|
| A01 | 1865 | +0 | 无；机械收拢预热状态及静音归属 |
| A02 | 1877 | +12 | 无；真实 cutover + S01 门控，验证操作代际与认领槽隔离 |
| A03 | 1887 | +10 | 无；真实 cutover 覆盖 P0-2 三种触发与异步加载代际 |
| A04 | 1890 | +3 | 断言不变；一处既有测试夹具先放行初始正片加载，详见下文 |
| A05 | 1896 | +6 | 无；覆盖广告 cutoverTo/prepare/commit 异常、重试、拒绝及正片失败汇流 |

验证方式与计划差异：
- A01/A02 使用单次完整 `flutter test`，分别 1865/1877 全绿。A03 验证曾遇 Dart VM OOM、线程创建失败，常规全量降低到并发 1 仍不能稳定完成，因此改为四分片完整覆盖，未删减用例、未跳过测试：A03 各片 498/489/451/449（并发 1）；A04 各片 499/490/451/450（并发 2）；A05 各片 501/491/453/451（并发 2），最终各片均全绿。A05 首次专项启动亦遇环境 OOM，随后单并发专项 6 项通过。
- A04 调整 `test/core/ad_first_frame_test.dart` 中 `ad-engine progress during the return hand-off does not overwrite the saved content rate` 的夹具：首次 load 的 commit 先 `release(false)` 落定，再触发中插并门控回正片。旧夹具在初始正片尚未接管时推正片进度，依赖提前进入 content 的旧行为；全部原断言保留。新增回归与首帧/倍速专项合计 12 项通过。
- 代码核对：原有 cutover 目录实测 109 项（表内约 108 为估算）；A04 可直接沿用现有按相位分发的进度逻辑，生产改动仅 7 行，无需新增位置缓存。A05 同时接住 prepare/commit 与正片转场 seek 异常，均按当前加载代际汇流，不新增 `MovaAdFailKind`。
- 新增回归文件、各行为提交的 CHANGELOG 及本落地记录均随相应提交说明原因；本记录随 A05 入库。公开 `MovaCutover` 不加 `commit(expect:)`，新功能开关默认值不变，未新增成员级 `@Deprecated`。
- 按用户明确要求不修改 `CLAUDE.md`；无关生成文件、doc/notes 与 matrix-run 文件未纳入提交，未触碰其他 worktree。本记录不代表 A06 之后或 CP1 真机检查已完成。

#### A1 块第二批落地记录（2026-11-03）

本批仅 A06 → A07 → A08 → A09 → A10，基线 1896；由当前执行者亲自完成，不转派、不切分支、不 push、不使用真机。每个提交前 `flutter analyze lib test` 均为 0 issues；生产代码仅改 `engine.dart` 与 A09 新增的 `core/engine/load_spec.dart`，未改 cutover_engine.dart、ads.dart、CLAUDE.md。

| 提交 | flutter test 实测 | 新增 | 现有断言变化 |
|---|---:|---:|---|
| A06（`0e0b84ca`） | 1901 | +5 | 无；已接受会话校验、加载双向意图纠偏、待机豁免 |
| A07（`c3b51c07`） | 1906 | +5 | 无；门控验证回边缘/重开不阻塞 pause、新源，dispose 后不补播 |
| A08（`7331ac15`） | 1911 | +5 | 无；独立恢复闸门、open/quality/recover 以 reloaded 结束测量 |
| A09（`e2968196`） | 1913 | +2 | 无；两条只核对加载记录的白盒测试，生产读取方未接入规格 |
| A10（随本记录提交） | 1923 | +10 | 改写 engine_test.dart 两条仅允许 open 的回边缘调用日志，详见下文 |

验证方式与计划差异：
- 各提交最终均使用单次完整 `flutter test --concurrency=6`，共新增 27 项，未删减、未跳过用例；本批未遇 OOM，未降并发、未分片、未结束其他进程。
- A10 改写 `test/core/engine_test.dart` 的 `backToLiveEdge in timeshift mode reopens the original live url`：旧断言 `['open']` 错在忽略了重开结束时播放意图为 true、替身尚未报告 playing；按 A10 的最新意图规则应为 `['open', 'play']`。实际重开原地址、清时移等原断言保留。
- A10 改写同文件的 `an explicit backToLive strategy overrides the mode-derived one`：旧 `['open']` 同样错误地排除了意图为 true 且未播放时必须补发的 play，改为 `['open', 'play']`；显式 reopen 策略仍生效。A07 原计划可能改写 1–2 条 Future 断言，实际无需改写：既有 KeepAliveRig 排空微任务，立即完成的假网络仍在断言前完成；新增门控测试明确验证 Future 在网络完成前返回 resuming。
- A06 实际 engine 差异 16 行，A08 约 49 行，A09 生产差异 115 行，A10 约 75 行，均小于预估规模；复用已有加载及喂信号入口，没有为凑规模搬迁代码。A09 `git diff --cached --color-moved=zebra --stat/--numstat` 为 3 files、+207/-4（engine +51/-4、load_spec +60/-0、测试 +96/-0），无跨段搬迁；非搬迁项为类型/import、记录字段/测试 getter、六处写入、仅用于记录的 reason 局部量、时移 builder 结果提取为只求值一次的 uri、两条白盒测试，已逐条写入提交正文。
- 以当前代码为准：普通 kernel.error 不触发 recovery，回归用已订阅的原生 END_FILE(error)；时移重试继续以 `_seekTimeshift` 使用的源地址为 builder 基地址，固定落后量取规格而非被 tick 重算的 UI 状态；任一旧 open 未返回时 `_kernelOpening` 仍屏蔽首帧，交错换档测试因此在所有加载释放后送首帧。未扩大错误模型或改变首帧屏蔽规则。
- 回退实现验证：仅临时替换 engine.dart 为对应提交前版本，A06/A07/A08/A10 的新增专项分别实测 3/4/4/8 条变红，随后逐字节还原当前实现；A09 为记录测试，不改既有断言。最终全量在还原实现后执行。
- 计划外配套文件仅各提交新增回归测试、行为提交的 CHANGELOG、A10 的两处既有测试断言及本落地记录，原因随各提交正文列出。新功能开关默认值不变，未新增成员级 @Deprecated；无关生成文件、doc/notes、matrix-run 与其他仓库文件均未纳入提交，未触碰其他 worktree。本记录不代表 A11 以后或 CP1 真机检查已完成。

#### A1 块第三批落地记录（2026-11-03）

本批仅 A11 → A12 → A13，起点为本分支现有 1981 项；上一批记录的 1923 是当批历史实测数，本次以已包含后续提交及终审拣回的当前代码为准。由当前执行者亲自完成，不转派、不切分支、不 push、不使用真机。每个提交前 `flutter analyze lib test` 为 0 issues；本批完整测试均使用 `flutter test --concurrency=6`。

| 提交 | flutter test 实测 | 新增 | 现有断言变化 |
|---|---:|---:|---|
| A11（`7b5d6caf`） | 1987 | +6 | 无；尝试号与租约身份防止旧换档收尾释放新租约，用户 seek 缓冲不计入 ABR |
| A12（`00699976`） | 1993 | +6 | 两个用例共 3 个断言，详见下文；自动探测、手选保护、同会话去重及 noop HTTP |
| A13（随本记录提交） | 2003 | +10 | 无；可选内核错误能力、分类表、事件增量及 state.error 行为不变 |

验证方式与计划差异：
- 共新增 22 项，与 +6/+6/+10 一致；未删减、未跳过用例，未降并发或按目录分片，未结束其他进程。专项覆盖后均以完整并发 6 测试作为提交闸门。
- A12 改写 `test/core/engine_load_spec_replay_test.dart` 的 public reload 用例：① `currentQuality isNull` 改为 `currentQuality.isAuto isTrue`，旧断言忽略 reload 是新会话、就绪后会从内存 master 自动重新探测；② `qualities isEmpty` 改为 `hasLength(3)`，旧断言忽略探测恢复完整列表。时长/进度归零及 SourceChange/Ready 次数断言保留。
- A12 改写 `test/ui/review_regression_test.dart` 的 #3：③ `probes == 0` 改为 `1`。旧断言把 View 跳过过期探测等同于引擎不能自主探测；延迟 open 被接受且就绪后引擎仍探一次，View 置空后的暂停意图、补发 pause 断言保留。
- A12 另外调整三处测试准备，断言不改：engine_test.dart 与 audio_only_scenarios_test.dart 的 ABR 用例先等待 noop 探测完成再种档，避免把并行探测的清空当作 ABR 行为；engine_test.dart 的显式探测失败用例关闭自动探测，确保断言的是显式那一次失败，而非要求同会话第二次 HTTP 请求。
- A12 采用已拍板的默认开启 probeVariants，未实现 A16 的 auto 接管。逐项核对全部既有 `.m3u8` 出现位置：真实 MovaEngine 夹具补默认 noop fetcher（nullable 注入也兜底），显式内存 fetcher 保留；MovaTesting 的工厂接缝亦用 noop。模型、广告 FakeMovaApi、QoE 及独立 mpv 用例不走引擎 HTTP，保持原路径。noop 不创建连接或 timeout，新增测试验证 get/close、接缝默认与 pendingTimers。
- A13 采用用户定稿的可选 `MovaClassifiedErrorKernel`，接口独立位于 core/kernel/classified_error_kernel.dart、不进主 barrel；`MovaKernel` 抽象零新增成员，因此无需修改计划列出的 kernel.dart。分类 code 直接复用 MovaPrefixError，因此 error_policy.dart 与 QoE collector 均不改。MovaErrorEvent 默认构造器签名保留，增加 classified 命名构造器；非终结错误仍写 state.error，END_FILE 的新订阅及 state 收窄仍由 A14/A14b 承接。
- A13 核对本地 media_kit 1.2.6 `real.dart:2068–2116`：stream.log 与 error 同行产生，以同一 prefix/level/text 过滤直接映射，不配对两条流。良性过滤实际在 mpv_defaults.dart，沿用原函数；已知终结文本为解码器耗尽与格式识别失败。新增表测试覆盖全部 code、首帧前后、已知终结文本及 END_FILE/error 与恢复放弃。原有 mpv_defaults_test.dart 的假 PlayerStream 补 log getter，模拟同一诊断行，全部原断言保留。
- 回退验证：A11 仅回退 engine 实现时 4 条新增专项变红；A12 同样回退时 6 条全部变红；A13 回退 engine 接线时 4 条变红，临时放宽 mpv 日志过滤时另 2 条变红。每次均以 finally 逐字节还原，最终检查在还原后执行。
- 生产差异均小于计划规模估计，复用现有首帧/seek 校验、就绪公告及 QoE code 映射，不为凑规模搬迁代码。计划外配套文件为新增回归、CHANGELOG、A12 的测试接缝与夹具、上述既有断言及 A13 的旧播放器替身、本落地记录，逐项原因写入对应提交正文。
- 用户本次明确要求不改 CLAUDE.md，优先于 §3.1 的基线回写规则，故仅追加本记录。未加成员级 @Deprecated；无关生成文件、doc/notes、matrix-run 与其他目录均未纳入提交，未触碰其他 worktree。本记录不代表 A14 以后或 CP1 真机核对已完成。


#### A1 块第四批落地记录（2026-11-03）

本批仅 A14 → A14b → A15 → A16，起点为包含 A13 及终审修复的 2011 项。由当前执行者亲自实现和提交，不转派、不切分支、不 push、不使用真机。每个提交前 `flutter analyze lib test` 均为 0 issues，完整 `flutter test --concurrency=6` 全绿。

| 提交 | flutter test 实测 | 新增 | 现有断言变化 |
|---|---:|---:|---|
| A14（`01b21d3e`） | 2022 | +11 | 两处 END_FILE 订阅预期改 true；recovery 关闭时 alternatives 用例改为 debug 拒绝、无 open |
| A14b（`af6e40c`） | 2030 | +8 | 5 个非终结状态断言改为 null；另两处用例仅改终结错误输入，原断言保留 |
| A15（`543505d`） | 2034 | +4 | 既有广告失败用例加入非终结阶段；原终结失败次数及类别断言保留 |
| A16（随本记录提交） | 2039 | +5 | 无；manageAuto 默认 false，显式开启才允许 auto 降档 |

验证方式与计划差异：
- 共新增 28 项，比计划的 27 项多 1 项：A14 额外覆盖 cutover 代理把封面 RESTART 意图传给当前/已存在/新建影子。最终检查均为单次完整并发 6，未删减、未跳过用例，未降并发或分片，未结束其他进程。
- A14 的 `openness_host_test.dart` 默认配置用例与 `recovery/engine_recovery_test.dart` disabled 用例，旧 `endFilesSubscribed == false` 都错误地把基础失败检测绑到 recovery，改 true；native/qoe false、无恢复定时器与 open 仍抛出的断言保留。`recovery/failover_test.dart` disabled 用例的旧 `openedUris == [primary]` 错在接受了无效 alternatives 配置，现断言 debug AssertionError、无 open，原 sourceIndex 与无 failover 断言保留。
- A14 的 5 个既有 mpv 事件用例仅调整夹具：验证事件泵前先 open；构造期建客户端的旧准备方式与懒启动不符，事件映射、过滤和销毁顺序的原断言保留。实际新增独立可选 `MovaRestartObserver`，由 engine/kernel 实现、player 请求、cutover 向底层传递，MovaApi/Kernel 抽象不加成员；`view.dart` 已有 poster 对应 preciseFirstFrame，无需改。提取统一终结清理，后台唤醒 open 异常避免重复上报。
- A14b 实际只改写 5 个既有状态断言，少于预估 10–25：engine_test 的 boom、interceptor_test 的 boom、playback_error_test 的 tcp: reset / 旧内核 StateError / damaged frame 均默认非终结，不能再要求写遮罩状态。事件原对象、分级、code 与钩子通知仍检查。audio_only_scenarios_test 的换源清理用例将 boom 换为已知终结格式文本；recovery_fixes_test 的恢复清理用例补该文本末尾句点，原断言不变，因为两个用例都需要先建立真正的终结状态。Breaking 与事件/恢复决策迁移指引已写 CHANGELOG、README；state/events/classifier 的契约注释同步。
- A15 代码中旧默认 `MovaErrorEvent` 构造器已由 A13 保留 `fatal=true`，所以既有终结错误断言无需反转。ads_test 的 player error 用例先发送 classified fatal=false、断言策略为空且广告继续，再发送 fatal=true，保留原一次失败及 playerError 检查；旧用例缺少非终结分支，不能证明“任意日志不应失败”。`_AdAttempt` 和 `MovaCutoverAcceptance` 不改，影子错误仍不冒为主流错误。
- A16 只新增默认关闭的实验性开关与其显式开启路径，复用探测列表和 ABR 租约：卡顿时 auto 转列表次高档，随后沿用具体档降档；不把 mpv 实际选档当作已验证的最高档。CP0 P1-3 尚无真机数据，未更改“auto 是静态最高档”等既有文档结论，未默认开启接管。新增夹具使用内存 master 和预览缓存，不触网；ABR 总开关、档位不足与用户 seek 租约均覆盖。
- 回退生产验证：A14 / A14b / A15 / A16 的新增专项分别实测 8 / 6 / 3 / 3 项变红。A14 临时撤回默认失败、懒启动和封面请求；A14b 撤回 engine/遮罩并移除新文案值比较；A15 回退两个入口；A16 回退 engine 并移除新配置比较。均以 finally 逐字节还原，再执行最终完整检查。
- 生产差异小于表内规模估计，复用既有分类、清理与降档路径，没有为凑规模搬迁。计划外文件限于上述可选能力/代理/播放器接线、契约注释、README/CHANGELOG、既有夹具与新增回归，以及本落地记录，具体原因逐条写入提交正文。
- 按用户要求不改 CLAUDE.md、不加成员级 Deprecated，不提交无关生成文件、doc/notes、matrix-run 或其他子工程文件，未触碰其他 worktree。本记录仅覆盖这四个提交及自动化验证，不代表 CP0/CP1 或后续 A/C 块完成。

#### A1 块终审修复记录（2026-11-03）

每批落地后由 Codex 初审（只读、effort high），主会话对源码逐条核实，成立的缺陷退回 Codex 在独立 worktree 修复、终审后拣回编排分支。共修复 **19 条**，新增回归 **115 项**（58 + 8 + 19 + 26 + 4），每条回退生产修复均验证变红。验证基线：A1 块全部落地后 `flutter test` **2088** 全绿、`flutter analyze lib test` 0 issues。

| 批 | 缺陷（成立） | 修复提交 |
|---|---|---|
| A01–A05 | F1 两个提交重叠都换指（P1）；F2 pod 第 2 条起同步失败被续播守卫吞掉（P1）；F3 预热保持失败打断释放与 dispose（P1）；F4 cutover 路径不识别宿主拒绝；F5 同一广告尝试结算两次；F6 `cutoverTo` 可能提交别人的槽 | `dee2cb36`、`21fd019c` |
| A06–A10 | 待机期间被补播出声（P1）；`_resumeTarget` 旧寄存值覆盖更新 seek；recovery 关闭时后台重开异常无出口；A07 时序 dartdoc 缺失 | `9aa06c1e`、`ddbe2746` |
| A11–A13 | 直播 ABR 租约被 `stop()` 的前置 `buffering=false` 提前释放；failover 后探测缓存无法重探；自建 fetcher 不随 dispose 关闭；`probeVariants:false` 关不掉默认 UI 自动探测（改为"关闭所有自动探测，显式调用不受影响"） | `dc0826e7`、`8aad4b48` |
| A14–A16 | 事件泵不可用时真实打开失败无终结状态（无泵兜底：仅匹配主文件有效地址的 stream/cplayer/ffmpeg 错误日志，字幕/音轨/HLS 分片仍是诊断）；迟到的旧文件 END_FILE 写错新源（open 前同步排空 + 通知带尝试号）；recovery 关闭时 END_FILE 绕过待机静默降级；同一次失败日志与 END_FILE 各发一次 fatal | `d3c0781d`、`0cf29b1d` |
| 交叉缺陷 | END_FILE 过滤按 `_attemptId` 会在"再次待机/seek 式唤醒"后误丢当前文件的结束通知（F-A 与 F-J 两个各自正确的修复相互作用）→ 改按 `_loadedAttemptId` | `d460e60a` |

与计划的差异与教训：① A14b 预估改写 10–25 条断言，实际 5 条，因为 A13 把内核日志默认判为非终结后，"所有内核错误都写 `state.error`"的旧断言本来就少；真正的风险不在断言数，而在"终结信号只剩 END_FILE"——无泵平台的兜底是终审补回的。② 修复之间会相互作用（末行），所以每批修复后都要整体重跑全量而不只是各自的回归。③ Codex 单次会话被系统内存耗尽杀掉一次（本机浏览器占用大），半成品改动保留在工作区、续做完成；此后要求"每个提交做完立刻落盘、全量测试 `--concurrency=3`"。

#### A2 块第一批落地记录（2026-11-03）

本批仅 A17 → A18 → A20 → A21，A19 已前置完成，起点为 A1 终审后的 2088 项。A17 已在上轮落盘，本轮审阅 A18 未提交草稿后续做；由当前执行者亲自实现、验证和逐个本地提交，不转派、不切分支、不 push、不使用真机。每个提交前 `flutter analyze lib test` 均为 0 issues；全量测试全部使用 `flutter test --concurrency=3`，未遇 OOM、未降并发、未删减或跳过用例，未与 analyze 同时运行。

| 提交 | flutter test 实测 | 新增 | 现有断言变化 |
|---|---:|---:|---|
| A17（`d6d0bfe5`） | 2093 | +5 | 无；仅排期纯逻辑提取 |
| A18（`19fcc09`） | 2105 | +12 | 3 个倒计时用例改为注入时钟驱动；断言值与无倒计时分支保留 |
| A20（`7d9fb992`） | 2113 | +8 | 11 个既有用例补齐播放意图前提，原断言全部保留；包含 1 个计划外广告重试夹具 |
| A21（随本记录提交） | 2122 | +9 | 无；既有 auto_pause_test 与 player_test 实跑通过 |

验证方式与计划差异：
- 共新增 34 项，与子计划 +5/+12/+8/+9 一致。A17 的历史验证与 color-moved 统计沿用已提交证据：3 files、+124/-35（ads +5/-35、timeline +68、测试 +51），非搬迁项为 import、私有函数改顶层名称并显式传参、三处调用适配、markPodPlayed 改为等价 addAll、跨库中文文档；原断言零改写。未重做 A17。
- A18 采用两只 MovaAdClock，注入 now，默认运行、playing 真→假暂停与假→真恢复；起表意图假时暂停。delayRemaining 与到期统一为时钟，loadTimeout 保持独立墙钟；dispose 同步取消两只时钟。未改覆盖层实现或引入 core 对 Flutter 的依赖。
- A18 三个既有用例逐条：① `delayRemaining counts down with the content ticks and stays positive until expiry`，旧断言把正片位置推进当时间流逝，seek/卡顿/倍速会令展示与 Timer 到期不一致，改注入时钟推进 2 秒；② `the countdown number decrements as content ticks arrive`，同样错误地由位置驱动时间，改 widget 时钟推进 2 秒后 tick 重建；③ `the cue carries the countdown when there is one, and nothing when there is not`，旧断言仅把正片从 30 秒推到 32 秒就要求剩余 5 秒变 3 秒，改注入时钟推进，预热 cue 与空 cue 的原期望保留。第三项按续做主会话明确授权采用总计划 ≤3 上限，已回写子计划第 6 节。
- A20 只读 playbackIntent，快照在 old.pause 之前；意图假则影子 pause，意图真才 play、迁移待机及在解静音失败后恢复旧引擎。普通广告与续播显式传 autoPlay；load 起播显式 true。保留 cutover 提交事务、MovaCutoverAcceptance 与广告 _AdAttempt，不改公开 cutoverTo 的回落（A27 后续负责）。自写 engineFactory 引擎须维护意图，意图恒假则换指后暂停，已公告 CHANGELOG 和类注释。
- A20 既有用例逐条补前提、原断言保留：① `commit() success: active becomes the shadow; old gets pause+dispose; new gets play`，旧引擎未 open/play 却要求影子开播，补意图 true；② `#17 commit migrates user view settings from the old engine onto the shadow before play`，设置顺序比较依赖无条件 play，补意图 true；③ keep_alive test 3 `a hold requested before commit puts the shadow into keepAlive before play without volume writes`，无意图却要求待机和开播，_warm 补意图；④ keep_alive test 4 `without a request the commit sequence is unchanged`，同样补影子开播前提；⑤/⑥ `warm mute true/false bypasses volume ports through prepare and commit` 两个参数化用例，旧真实引擎从未 play，prepare 前 api.play；⑦ `failed mute restoration emits an error and abandons the cutover`，旧夹具只有 emitPlaying(true)、没有用户意图却要求回退恢复，补 api.play 并保留观测；⑧ `提交影子 play 挂起时新 prepare 不被收尾释放`，旧 rig 意图假时 playGate 无法阻塞，构造补意图；⑨ `影子 play 挂起时 open B 禁止旧换指`，同样补开播前提；⑩ `同一 ready 影子只能被一个 commit 认领`，旧 rig 意图假却要求一次 play，补意图；⑪ `a retried break gets a fresh duration, counted from its new first frame`，共享替身在首次 open 抛错前不写意图，旧夹具意图恒假却要求重试广告计时到期，失败前 api.play 建立播放中重试。第⑪项为实跑发现的计划外夹具调整，已回写子计划；F1 八项交错原已 old.play，不需额外改写，keep_alive test 5 与 commit 无关、不改。
- A21 对本机 pub cache 的 media_kit_video 2.0.1 再核实两个参数名与默认 true/false，Video 均显式传 false。MovaPlayer 在 paused/detached 且有默认 Video 渲染面时经 API 暂停，不自动恢复；PiP 豁免、同一 API 守卫让位、background:false 可保留后台播放、audioOnly/自定义 surface 不动作、延迟出现的渲染句柄均有新增覆盖。按已拍板 D6，监听注册于挂载时，但是否有 Video 在事件发生时判定。
- A21 与草图的实质差异：两个视图共用 API 时，首个 pause 清了意图，内核 playing 仍可能为真，第二个视图仍满足 intent || playing；原草图实测重复 pause。增加按 API 的 Expando 同轮通知标记、微任务清除，不增公开成员；第 8 项用 playing=true 验证一次暂停。去重前后红绿证据及差异已回写子计划。
- 回退生产验证：A18 临时回退 ads 接线（只保留 debugClock 测试接缝以编译）并禁用时钟 pause，12 项中 **5 项变红**；其余 7 项为基础时钟/已有结算和清理不变量。A20 两处生产文件回退时 **6 项变红**，另把快照移到 old.pause 后、判断改回 playing 各 **1 项变红**，去重覆盖全部 8 项。A21 回退 player/auto_pause 时 **6 项变红**；分别移除守卫让位、PiP 豁免、允许 hidden 暂停各 **1 项变红**，去重覆盖全部 9 项；另单独移除去重，第 8 项变红。每轮均用 finally 逐字节还原生产文件，再执行最终检查。
- 计划外配套文件限于子计划要求的新增测试/包内辅助、行为 CHANGELOG、上述已说明的夹具调整、子计划差异记录和本总计划落地记录；生产改动少于估算，复用既有能力，没有为凑规模搬迁。未加成员级 Deprecated、未改 CLAUDE.md，未提交 example/windows 生成文件、doc/notes、matrix-run 或其他子工程文件，未触碰其他 worktree。本记录不代表 A22 以后或 CP1/CP2 真机核对已完成。


#### A2 块第二批落地记录（2026-11-03）

本批仅 A23 → A24 → A25，起点为 A22 终审后的 2130 项；由当前执行者亲自实现、验证并逐个本地提交，不转派、不切分支、不 push、不使用真机或启动应用。每个提交前 `flutter analyze lib test` 均为 0 issues，全量均使用 `flutter test --concurrency=3`。

| 提交 | flutter test 实测 | 新增 | 现有断言变化 |
|---|---:|---:|---|
| A23（`1ca3d533`） | 2145 | +15 | 无；公开会话、五态加载结果、按集广告、自动识别切换、接受后提交下标 |
| A24（`ed878a34`） | 2153 | +8 | 无；重复 const 广告、节点尝试归属、纪元事件与游标 |
| A25（随本记录提交） | 2165 | +12 | 无；共享会话连播、后贴片屏障、门控换集、开关与布尔加载结果 |

验证方式与计划差异：
- 三次全量均完整通过，未遇 OOM、未降低并发、未分片、未删减或跳过用例，未结束其他进程。既有 ads_test、playlist_test 等文件和断言均未改；A25 只给本批 A23 新增的借用测试补充 `api.disposeCount == 0`，因为替身即使销毁后仍允许 open 返回 true，原新增断言不足以验证所有权。原断言全部保留，测试总数不变。A25 最终自审另补 A24 的续播尝试号捕获：钩子同步重载同一节点时，旧 skip/Done/定时器/失败尾部必须携带发钩子前的尝试号，不能重读当前尝试。给本批新增 session_nodes_test 的跳过用例追加回调重入场景，修复前 1 项变红、修复后通过，不新增测试条数；因此新修复后重跑 analyze 与完整全量。
- A23 使用泛型加载核心原位映射结果，保留 A22 调用层级；直接构造自动识别 MovaCutover、广告适配器仍只认显式 cutover。MovaPlaylistItem.adBreaks 的 null/空列表分别表示回落配置/本集无排期；autoAdvance 默认关闭，切换仍受 cutoverEnabled 门控。按子计划 D12 增加 failed（总计划旧签名漏列），公开 API 补中文 dartdoc、参数/返回与示例，不加 Deprecated。
- A24 的身份为条目、类型、同类型排期原顺序；插播序号 -1、-2 递减。已播集、失败次数、定时器、续播改走节点和尝试，广告钩子仍带原对象，dueMidRoll 包装签名不变。会话事件独立于 MovaEvent，不含 A26 的 MovaNodeFail。参数贯穿既有调用链及完整 dartdoc 令生产改动略超行数预估；没有为凑规模搬迁。
- A25 仅 ads 路径登记借用会话并监听 contentEnded，enabled=false 时 jumpTo/next/previous/自动连播无动作，dispose 不销毁会话。字节比较确认旧直连 jumpTo 核心、next/previous、_onEvent 原样保留。门控换集使用 S01 GatedEngineFactory 与真实切换引擎，在已认领提交的 old.pause 门上换集，放行后旧广告不落地；当前代码没有真实代理 commitGate，故以该等价提交窗口定位。
- 回退生产验证均在 finally 中逐字节恢复：A23 保留编译接缝撤回新增行为后 **10 项变红**，另对关闭代理/旧广告入口、拒绝、销毁和借用语义做错误实现验证 **5 项变红**，去重覆盖 15 项。A24 回到 A23 的状态机，事件与构建函数留空编译接缝，**8 项运行时断言变红**。A25 撤回会话路径并保留布尔返回编译接缝 **9 项变红**，额外微任务回归 **1 项变红**，拒绝/旧路径开关错误实现 **2 项变红**，去重覆盖 12 项。
- 时序核对曾临时替换为 A22（1a0b3651）的 ads/session 生产文件实跑，调用方 await 返回瞬间 api.calls 快照是 `[turn:1, open, turn:2]`；A25 相同。显式增加一次 await Future.value 后快照多出 turn:3，测试变红。与子计划动机的实测差异：本机 Dart 对单纯 then 映射的传播会优化，普通成功路径测试仍绿，不能把 then 一概声称为必然增加微任务；生产仍严格采用 D13 泛型核心直接映射，转发无 async/then。
- 新增回归文件、cursor/events/registry 等包内配套、CHANGELOG 与必要 README 片段均按子计划；A25 额外触及本批 session_test 与 session_nodes_test，仅为上述所有权与回调重入断言补强，续播守卫补全 A24 节点及尝试归属。本记录随 A25 入库。不改 CLAUDE.md，未提交 Windows 插件生成文件、doc/notes、matrix-run 或其他子工程，未触碰其他 worktree。本记录不代表 A26–A30 或 CP2 已完成。


#### A2 块第三批落地记录（2026-11-03）

本批起点 2165 项，先修复 A23–A25 初审的五条缺陷，再按 A26 → A27 → A28（含 H77）→ A29 → A30 逐个实现、验证并本地提交。全程由当前执行者亲自完成，未转派；只改本 worktree 的 mova/，未切/建分支、stash、reset 或 push，未使用 adb、Gradle、真机或启动应用。每个提交前 `flutter analyze lib test` 均为 0 issues，全量测试均使用 `flutter test --concurrency=3`，未遇 OOM、未降并发、未分片、未删减或跳过用例。

| 提交 | 全量实测 | 新增 | 回退/语义突变变红（去重） |
|---|---:|---:|---|
| 初审五条修复 `5a36d64c` | 2173 | +8 | 9：8 条新增回归 + 1 条强化的既有计时测试 |
| A26 `d96c5879` | 2183 | +10 | 10：会话接线回退与纯仲裁函数保留编译接缝后的回退 |
| A27 `5ccfc132` | 2191 | +8 | 8：回退 session/cutover 接线后全部变红 |
| A28 `2426a783` | 2203 | +12 | 9 条旧代理回退变红，另 3 条 API/普通引擎对照经语义突变变红 |
| A29 `b5cb1c62` | 2208 | +5 | 3 条新策略回退变红，另 2 条默认行为对照经错误默认值变红 |
| A30（随本记录提交） | 2213 | +5 | 4 条 UI 回退变红，另 1 条旧直连对照经错误守卫变红 |

合计新增 48 项，最终 2213；去重验证 49 条可变红（含强化既有测试 1 条）。兼容性和普通引擎对照在正确的旧行为下应保持绿色，故明确区分旧代码回退与故意破坏行为的语义突变，没有把编译失败计成回归变红。临时生产文件均在 finally 中按字节恢复。A28 认领槽后首帧的生命周期守卫另做了移除验证，在补齐夹具播放意图、确保 playGate 真正挡住提交后，该用例变红；它属于上述 9 条中的同一用例，不重复计数。

五条初审缺陷及修复：

1. 旧集结束通知覆盖手动跳转：公开 `contentEnded` 类型不变，包内结束通知携带发出时 epoch；直接会话与 playlist 的两个自动推进消费者都比较当前 epoch。以节点完成监听器手动 jumpTo(2)、打开被门闩卡住验证，旧通知不能另启第 1 集。
2. 跳过加载中的前贴片让 load 提前 rejected/false：每个广告尝试记录自己的续播 Future，加载核心在同一 epoch 继续等待有效续播结算；覆盖 session.load、session.jumpTo(1)、ads.load 三个入口，G1 放行时仍未结算，G2 放行后 accepted/true 且下标正确。
3. 公开 session 导航后 playlist 下标落后：共享会话路径从 cursor 读取下标，next/previous 调会话动词，indexChanges 只由 MovaItemChange 驱动；公开跳到第 2 集后手动 next 和自然结束都不误开第 1 集。旧直连分支保留原调用行为。
4. setItems 不使在途 jumpTo 失效：增加独立列表代际，接受结果提交前核对原列表代际；旧请求返回 superseded，不写越界下标、不发 MovaItemChange。
5. 同实例广告计时测试误通过：为两条广告补首帧，取消加载超时干扰；检查 t=14.999s 第二条仍未结束、t=15s completed，结束时刻恰为 [5s,15s]。移除第二条时长计时器后该测试变红。

新增公开 API（均补中文 dartdoc、参数/返回与示例；未增加成员级 Deprecated）：

- A26：`MovaNodeFail`（node、verdict、error）与 `MovaNodeFailVerdict`。失败描述与纯仲裁函数留在包内；`contentError` 的公开注释和 CHANGELOG 明确扩展 A05 契约，加入正片终结错误，恢复开启时等 giveUp。
- A27：在现有 `core/cutover/acceptance.dart` 扩展包内 `MovaWarmOwner`、`MovaWarmTicket`、`MovaWarmCommit`，未另起平行接口、未从 barrel 导出。代理实现的 prepareOwned/commitOwned 补中文说明；公开 MovaCutover 四动词与 MovaApi 均未加成员。
- A28：`MovaCutoverEndReason` 八种结束原因，`MovaCutoverChange.reason` 可选命名字段；旧 const 调用仍有效，没有新增 MovaEvent 子类。
- A29：`MovaAdSnapback`、`MovaAdConfig.midRollSnapback`，构造、copyWith、相等与 hash 同步。默认 all 委托旧查找；单个到期插入点及同点 pod 不受多点补播策略影响。
- A30：零新增公开面；NextUp 从 A25 已登记的 Expando 获取会话，不新增 session 参数；旧直连保持原时长判据。

既有断言改写逐条说明：

1. 初审计时用例原先只看 t=15s 的结束序号 [0,1]，第二条 t=13s 加载超时也能满足，无法证明计时器有效。现补首帧，并检查未提前结束、completed 原因和准确时刻。
2. ads_test 的 pod abandon/cutoverTo 顺序改为 abandon/prepare 并检查准备源；会话不再调用 cutoverTo，原动词断言已不适用。
3. ads_test 的在途 pod 门从 cutoverToGate 移到 commitGate，断言只 prepare 第二条广告；落地本身需要 prepare，旧“没有 prepare”会错把合法落地当成正片误预热。
4. ads_test 一次性广告倍速从 lastCutoverToRate 改为 lastPlan.rate=1.0 且 pauseWhenReady；倍速及停帧参数现经 prepare 下发。
5. ads_test 的 pre:true 路由改为 prepare→commit；旧 cutoverTo 断言不再适用，无 api.open 的原断言保留。
6. ads_test 的 break.waitForReady:true 覆盖前贴片默认值同样改为 prepare→commit，原因同上。
7. ads_open_failure 的异常阶段从 cutoverTo/prepare/commit 三组改为 prepare/commit × pre/mid 四组；旧前贴片 cutoverTo 组永远不会再被经过。
8. ads_open_failure 重试改注入 prepare，检查异常已消费与一次成功 prepare；旧 cutoverTo 替身在抛出前记录调用，prepare 在抛出后才记录，不能沿用总数 2。
9. ad_stale_first_frame 的第二条广告门移到 commit；旧 cutoverTo 门不会再被经过，保留“旧 rendered 不遗留加载期限”的原不变量。
10. ads_interleaving 的 F-N 首次前贴片“没有 pause”改为 pause→seek→play；广告方向 pauseWhenReady 要求先停帧回绕再按显式意图播放，最终意图为真的断言保留。
11. ads_pod_failure F5 retry：窗口内 opens=1、策略为空，open 抛出后才 retry；旧断言把未落定的旧 ErrorEvent 先认作新广告失败，违反 D10。
12. ads_pod_failure F5 skipBreak：窗口内不裁决，放行 open 抛出后唯一失败并续播第三条；旧断言原因同上，最终单条跳过不变量保留。
13. ads_pod_failure F5 abandonPod：窗口内不裁决，放行 open 抛出后唯一失败并回正片；旧断言原因同上，最终放弃 pod 不变量保留。

A26、A28、A29、A30 没有改写其他既有断言。A28 的 F4 widget 用例仅调整驱动并增加结算断言：事件订阅提前后，取消订阅与 close 跨真实/fakeAsync 队列，原“单次 pump 后直接 await load”会挂起；改为按明确的加载结算条件推进两个队列并设上限快速报错，保留全部旧断言。曾停止属于当前 worktree 的挂起测试进程，未结束其他 worktree 的进程；修正后重新完整全量通过。共享 FakeMovaApi、普通 engine.dart 的调试/语义突变均已按字节恢复，没有最终 diff。

与子计划的差异和实现核对：

- A26 的三路同 turn 描述与代码不完全一致：loadTimeout 只在 open 接受后武装，open 尚未完成时不会同时有该期限。改为一条测试内验证错误/超时和错误/迟到 open 抛出两组交错，覆盖三入口且只裁决一次。为保持 A13 既有明确语义，实际事件流的非终结广告日志在 recovery 关闭时也继续诊断而不结算；纯函数仍单测“恢复关闭时显式失败输入交广告策略”。包内失败描述增加原始 adBreak，供现有广告策略使用。
- A27 按第 12 节拍板扩展 acceptance.dart；prepare 被 host open 取代、尚未返回槽时仍保留原 op 的空凭据，以报告 superseded，避免计划伪代码返回 null 后误当未就绪硬切。包内 prepareOwned 增加可选 play，保持 A20 首次起播与后续用户命令优先。F-N 和 F5 的计划表外断言变化已补子计划 §6。
- A28 在原 +8 上按 H77 增 +4，总数 +12。state/events 统一进带 renderEpoch 的同一队列，事件通知前发布载荷对应快照，重入通知顺延；验证 epoch 0 和换指后，普通 MovaEngine 两组对照一致。影子生命周期必须在 open 前开始记录，并延续到认领后 detach 前；换指后按固定三类顺序各补一次，放弃不补发。结束原因八种都有覆盖。
- A29 无行为偏差；按正文“多个不同 offset”边界实现，默认 all 完整保留现状。A30 增加微秒边界，保证任何正的 skipIn 都向上取整，避免剩余 1μs 时显示 0；这属于原计划倒计时正确性验证的细化。
- 按本次用户明确约束不改 CLAUDE.md（覆盖子计划要求 A30 回写它的旧指令）；基线记在本记录与子计划 §5。未提交插件生成文件、doc/notes、matrix-run 或其他子工程。

本次实现、本地分析、完整测试及回退验证已完成；CP2/真机/应用运行按本次约束未做，本记录不把本地验证当成 CP2 结论。

##### 终审修复

1. P1 落地窗口丢失 giveUp：按失败 URI / fatal 事件媒体身份识别新媒体，将终结事件缓存到 open 落定后走既有失败仲裁；缓存限定当前加载与广告尝试，正片失败回 idle 并发 contentError、MovaNodeFail。fatal 分级事件增加可选 source，真实引擎填写所属媒体。回退 session 修复后 **4 条变红**（正片返回前 giveUp + F5 retry/skipBreak/abandonPod 正常返回变体），恢复后专项 53 条通过。另用真实引擎内核首次 open 异常验证异步 giveUp 最终只失败一次。
   - F5 既有三条断言保留，扩成 eventAndThrow / giveUpReturn 两种驱动；标题改成“open 落定”。旧兜底仅靠 open 抛出结算，正常返回时不会经过，不能证明窗口正确。既有“旧 ErrorEvent 在窗口内不结算”断言没错，不能把新媒体 giveUp 也当作旧事件；本次没有删减或放宽既有断言。
   - 分析范围偏差：根目录 flutter analyze 有 49 条既有问题，分布于 example、packages、HarmonyOS 试验目录；不修改无关代码。flutter analyze lib test 为 0 issues；全量测试 --concurrency=3：**2218 条通过**。

2. P1 补发回调抢源：状态/事件队列携带 op 并在通知返回后复核；每次影子生命周期补发前后复核 op 与 active，过期停止。commitOwned 在返回 committed 前再次复核，抢源返回 superseded。晋升后过期仍退休并释放旧引擎，保留宿主正在使用的新 active；会话不把宿主源认作广告。
   - 回退 cutover 修复后 **4 条变红**（SourceChange、Ready、FirstFrame 回调抢源各一条 + 真实会话路径），恢复后通过；既有断言改写 **0**。沿用分析范围 lib test（0 issues），--concurrency=3 全量 **2222 条通过**。

3. P2 换会话后已认领旧事务仍上屏：会话跟踪自己持有的预热凭据，load/jumpTo、setItems、dispose 同步发出定向取消；prepare 尚未返回时也按 gen 与列表代际取消迟到凭据。包内 owner 增 cancelOwned，标记凭据和槽永久取消，释放自己的影子；提交等待前后、换指与返回检查均包含取消状态，不提升已释放影子，不递增全局 op 或放弃其他槽。
   - load/jumpTo/setItems/dispose 四条门控回归均验证 old.pause 未放行就释放旧影子，放行后 renderEpoch 仍为 0；B 未就绪时旧 A 不上屏，B 后续只换指一次。setItems 另验证宿主新影子保留且可提交。回退会话取消接线后 **4 条变红**；保留释放但移除提交 current() 的取消守卫，同样 **4 条变红**（相同四条用例，不累计为八条）；恢复后通过。既有断言改写 **0**。分析范围沿用 lib test（0 issues），全量 --concurrency=3：**2226 条通过**。

4. P2 宿主抢源漏节点结束：_superseded 在清空 _onScreen 前调用 _endNode(superseded)，沿用原节点与原 epoch；不发节点失败，不放弃宿主新影子。前贴片与正片各一条回归同时检查恰好一次、原身份、后续加载不重复结束，以及宿主新影子可正常提交。移除这行修复后 **2 条变红**，恢复后通过。既有断言改写 **0**；分析范围沿用 lib test（0 issues），全量 --concurrency=3：**2228 条通过**。

终审修复汇总：新增 15 条（其中真实引擎异步送达对照 1 条），四条缺陷的唯一变红用例分别 4/4/4/2，共 14 条；第 3 条的额外守卫突变重用同四条，不重复累计。既有断言没有删减、放宽或改写；F5 三条扩成两种故障驱动并改标题，原异常兜底不能覆盖正常返回的 giveUp。四次独立提交，每次 lib test 分析 0 issues、全量通过后提交。根目录分析的 49 条无关既有问题未修，列为验证范围偏差；没有把 lib test 的 0 issues 声称为根目录分析 0。未使用真机、未启动应用、未转派、未 push、未切分支、未 stash/reset，CLAUDE.md 未改写；禁止提交路径均未暂存（工作区原有三份插件生成文件修改保留）。

→ **CP1：引擎、切换与 B 块真机核对**

#### 轨道 A2 块（会话层）

| # | 提交 | 类型 | 主要文件 | 规模 | 依赖 | 测试 | 完成判据 |
|---|---|---|---|---|---|---|---|
| A17 | `refactor(mova): 广告排期纯逻辑抽到 core/session/timeline.dart` | 机械 | `ads.dart`、新 `core/session/timeline.dart` | 150–250（搬） | CP1 | 不改；`dueMidRoll` 公开签名保留 | ads_test 98 条原样绿 |
| A18 | `feat(mova): 广告位与倒计时改用可暂停时钟` | 行为 | 新 `core/session/ad_clock.dart`、`ads.dart` | 200–300 | A17 | +12（5.3 的 11）；可能改写 ≤3 条 `delayRemaining` 断言 | 时钟默认运行，只在观测到 `state.playing` true→false 时暂停；`delayRemaining` 改由时钟给（展示与到期统一口径）；`_loadTimer` 仍是独立墙钟期限 |
| A20 | `fix(mova): 回正片与回广告继承播放意图` | 行为 | `cutover_engine.dart`（`_commitNow`）、`ads.dart` | 60–120 | A18、A19 | +8（5.3 的 12、13）；**改写约 8–12 条断言（测试替身旧引擎预置意图）** | 见 3.3。原因 [已核]：影子“意图为真才开播”后，测试里旧引擎从未 `open`、`playbackIntent` 恒 false，这些“影子 `play` 被调用”的断言会变红：`test/core/cutover/cutover_engine_test.dart:373`、`cutover_keep_alive_test.dart:84,95,105`、`cutover_warm_mute_test.dart:67,202`、`cutover_engine_defects_test.dart:322`（以上 7 处已核；其余几条在 A20 开工时跑一遍确定） |
| A21 | `fix(mova): MovaPlayer 关闭 media_kit 自带的后台暂停，改走引擎路径` | 行为 | `ui/player.dart`、`ui/guard/auto_pause.dart`（作用域标记） | 120–220 | A20、CP0 结论 | +6 widget：无守卫时切后台→`api.pause()` 被调用、意图为 false；有祖先守卫时 MovaPlayer 不动作；`Video` 收到两个参数；+2：audioOnly（无 `Video` 渲染面）不注册生命周期监听 | 默认可见行为不变（切后台仍暂停），待拍板 3；**只在有 `Video` 渲染面时启用**，否则 audioOnly 会在后台被停播，CP2 加 audioOnly 后台一组 |
| A22 | `refactor(mova): 引入 MovaSession，MovaAds 状态机原样迁入，MovaAds 改为转发壳` | 机械 | 新 `core/session/session.dart`（~1200 搬）、`ads.dart`（剩 ~250） | 1200–1500（搬） | A21 | 不改；ads_test、ads_session_test、ad_first_frame_test、openness_ad_test、`ad_stale_first_frame_test` 与 `test/core/cutover/` 全部零改动绿（口径：A22 的 diff 不含 `test/`；A20 已改写的断言发生在 A22 之前，不算在内） | `MovaSession` 本提交不导出；`--color-moved` 显示几乎全是搬迁 |
| A23 | `feat(mova): 公开 MovaSession：多条目、按集广告、load 返回接受结果` | 新增 | `session.dart`、`core/model/playlist.dart`（`adBreaks`）、`lib/mova.dart` | 300–500 | A22 | +15 | 直接构造时 `api is MovaCutover` 自动启用；经 `MovaAds` 构造时仍按显式 `cutover:` 参数（旧语义） |
| A24 | `feat(mova): 会话事件带 nodeId 与 epoch，节点身份取代广告位对象身份` | 行为 | 新 `core/session/events.dart`、`timeline.dart`、`session.dart` | 150–250 | A23 | +8；含"pod 里两条 const 同参数广告各播一次" | |
| A25 | `feat(mova): MovaPlaylist(api, ads:) 走会话，MovaAds.load 返回 Future<bool>` | 行为 | `playlist.dart`、`ads.dart`、README 片段 | 120–230 | A23 | +10（5.3 的 14）；+2：`playlist.enabled=false` 时会话路径 next/previous/自动连播 no-op | 旧 `MovaPlaylist(api)` 行为逐字不变；需要 `MovaAds.session` 访问口（2.3） |
| A26 | `feat(mova): 会话失败仲裁` | 行为 | 新 `core/session/arbiter.dart`、`session.dart` | 150–250 | A25、A15 | +10（5.3 的 10；recovery 开时广告失败只由一层处理） | 见 3.3 |
| A27 | `fix(mova): pod 串播事件归属、预热参数与时机` | 行为 | `session.dart`、新 `core/session/transition.dart` | 100–200 | A26 | +8 | 会话改用 prepare+commit 替代一次性 `cutoverTo`；广告方向 plan `rate: 1.0`、`pauseWhenReady: true`、就绪期限取 `adReadyTimeout`；预热 cue 取"素材剩余、广告位剩余"的较小值 |
| A28 | `fix(mova): 换指窗口不转发旧引擎暂停态，补发影子期生命周期事件，放弃原因可观测` | 行为 | `cutover_engine.dart`、`core/events/events.dart` | 150–250 | A20 | +8 | `MovaCutoverChange.reason` 可选字段 |
| A29 | `feat(mova): 前跳越过多个中插的补播策略` | 新增 | `timeline.dart`、`ad_config.dart` | 80–150 | A24 | +5 | 默认 `all`（现状） |
| A30 | `fix(mova): NextUp 与广告覆盖层读会话节点` | 行为 | `ui/components/next_up.dart`、广告覆盖层组件 | 60–120 | A24 | +4 widget | 不传会话时保持旧判据 |

**A2 块子计划（2026-11-03，逐 Task 见 [2026-11-03-a2-session.md](2026-11-03-a2-session.md)，主会话拍板见其第 12 节）**：A17–A30 共 13 个提交，测试合计约 N0+105（总计划估 +96）。要点：A22 的 `MovaAds` 改为"同步返回内部 Future、不加 async 包装"的转发壳以保住微任务顺序；A27 的包内能力 `MovaWarmOwner` 扩展 F4 落地的 `core/cutover/acceptance.dart`（不另起平行接口）；A20 只认 `playbackIntent`（自写引擎不维护意图时换指后停在暂停，CHANGELOG 写明）；A26 正片终结错误进 `contentError` 并回 idle（改了 A05 刚定的契约，CHANGELOG 写明）。

**A28 追加范围（H77，2026-11-03 S00c 定性后并入）**：cutover 代理的 `state` 与 `events` 走两条独立订阅链，事件会领先 `state`（原始证据 `matrix-r1030-final-hls.json:records[961]`：`MovaBufferChange(false)` 到达时 `state.buffering` 仍为 true），验收矩阵 A2 与 E.MovaBufferChange/SizeChange/QualityChange 因此 FAIL。A28 把代理的 state/events 合并为同一投递序列（事件携带的载荷与同一时刻的 `state` 一致，并带 epoch），并为普通 `MovaEngine` 补一组"事件载荷与接收时 state 一致"的单测以区分普通引擎是否也有差异（现有证据区分不了，S00c 原稿"普通引擎也有差异"证据不足）；预计 +4 测试。修复后四个矩阵项应转 PASS。

→ **CP2：会话、广告与后台真机核对**

#### 轨道 C 块

| # | 提交 | 类型 | 主要文件 | 规模 | 依赖 | 测试 | 完成判据 |
|---|---|---|---|---|---|---|---|
| C01 | `docs(mova): 示例统一用 createMovaEngine，MovaEngine() 构造说明与 debug 提示` | 文档/行为（仅 debug） | `README.md`、`engine.dart` 类注释 | 50–100 | — | +1 | README 首例、时移、拦截器示例全部改；**首例 `engine.open()` 补 `await` 与 `catch`**（README:106 [已核]，现在未 await 未 catch，`open` 抛出即未处理异常）；裸构造在 debug 下打一次提示 |
| C02 | `fix(mova): MovaMini.show 遵守 enabled，修正无缝切换示例` | 行为 | `ui/mini/mini.dart`、`README.md`、`platform_impl/wiring.dart`、`core/stt/service.dart`（debug 提示） | 60–120 | — | +4 | Codex 异议 2：补 cutover 关闭、STT 无引擎的 debug 一次性提示与只读状态（getter 命名 [待核]）；[已核] `show()`（mini.dart:121）不查 enabled，`showInPage`（:174）查；README:478 的示例得到关闭的直通代理 |
| C03 | `fix(mova): MovaView 只比较引擎实际读取的配置节` | 行为 | `ui/view.dart`、`core/options/options.dart`（`engineSectionsEqual`） | 100–200 | — | +5：父组件重建、内联 `MovaOpts` 不再重建引擎；debug 下连续 N 帧 options 不等时提示 | [已核] view.dart:188 |
| C04 | `feat(mova): MovaChrome 承接每视图 UI 交互态，旧引擎接口桥接一个版本` | 新增/API | 新 `ui/chrome/`、组件、`core/api.dart`（dartdoc + CHANGELOG 公告，不加成员级注解）、`engine.dart`、`cutover_engine.dart` | 600–1000 | B01、B14、B15、B16 | 已落地 C04a–C04d；实测 +32 → 2301；拖动与按钮续期（P1-13）；多视图互不串扰 | 旧接口一个版本内保留；无视图行为不变；详见文末 C04 落地记录 |
| C05 | `feat(mova): 应用内全屏路由与返回键处理（默认关）` | 新增 | 新 `ui/fullscreen/`、`ui/player.dart` | 300–500 | C04、B04 | +8 | Windows 转场快照路径要经过 `MovaSnapshotGuard`（Flutter 3.47.0/3.47.1 #190774） |
| C06 | `feat(mova): MovaPlayerStyle，主题文案手势弹幕样式挪出 MovaOpts` | API | 新 `ui/style/`、`options.dart`（弃用公告，是否加成员级注解见待拍板 18）、组件、`core/model/quality.dart`（去写死中文） | 600–900 | C04 | +29（实测） | 2026-11-04 已落地（两提交，C06e 未裁剪）；查找顺序：widget 参数 > ThemeExtension > `api.options.*`（deprecated）> 默认；切主题不重建引擎 |
| C07 | `feat(mova): MovaSource 支持请求头、UA 与起播位置，旁路请求统一带头` | 新增 | `core/model/source.dart`、`engine.dart`（start 走寄存）、`preview/fetcher.dart`、抽帧器、`feed_prefetcher.dart` | 250–400 | B12 | +10 | `start` 放在 `MovaSource` 上，不改 `MovaApi.open` 签名；**`MovaHttpFetch.get(Uri)` 加 headers 是对宿主实现的破坏**（待拍板 17）：推荐新增可选能力接口 `MovaHeaderedHttpFetch`、原抽象签名不动，旧 fetcher 退化为不带头并 debug 提示 |
| C08 | `refactor(mova): barrel 分入口，内部实现标记即将隐藏` | API | `lib/mova.dart` 与新入口 `skin.dart/ads.dart/feed.dart/mini.dart/extend.dart` | 200–300 | C06 | +2（导出面快照测试） | 旧入口继续导出同一符号；内部 helper 用 export 级公告（不触发包内 `deprecated_member_use_from_same_package`）；成员级 `@Deprecated` 是否加见待拍板 18 |
| C09 | `refactor(mova): STT 撤出主入口` | API | `lib/mova.dart`、新 `lib/stt.dart` | 50–100 | C08 | +1 | 主入口保留一个版本的转导出（export 级公告，不触发包内警告）；`MovaApi.stt` 保留；STT 入口 dartdoc 注明模型下载为实验实现（P1-22） |
| C10 | `feat(mova): 能力发现统一入口` | 新增 | 新 `core/capability.dart` | 60–120 | — | +4 | `movaCapabilityOf<T>(api)` 穿透 cutover 代理；不改 `MovaApi` |
| C11 | `fix(mova): createMovaEngine 参数冲突的 debug 断言` | 行为（debug） | `platform_impl/wiring.dart` | 60–100 | — | +3 | 传 kernel 时忽略项提示；Android `tlsVerify` 无 CA 断言；`wiring.dart` 文档写清抽帧器默认 |
| C12 | `feat(mova): 默认接入连通性探针（按需）` | 行为 | `wiring.dart`、`engine.dart` | 40–80 | 待拍板 5 | +3 | **推翻** wiring.dart:113-134 的"不默认接线"；同提交修 `wiring.dart:118,126` 的过期 tree-shaking 注释 |
| C13 | `feat(mova): 注入对象所有权与 ABR 策略工厂` | API | `abr_config.dart`（`policyFactory`）、`preview/service.dart`、`stt/service.dart` | 150–250 | — | +6 | 引擎只销毁自建对象；STT 不 dispose 宿主引擎；`policyFactory` 每引擎各取一个实例，解决 `stallPolicy`/`policy` 实例被多引擎共用（P2-24）；`policy` 实例字段保留（不加成员级注解，待拍板 18） |
| C14 | `feat(mova): MovaFeedPlayer 暴露控制器、内置自动暂停、单页失败可见` | API | `ui/feed_player.dart` | 200–300 | B11、B12 | +6 | |
| C15 | `feat(testing): MovaTestKernel 脚本化模式` | 新增 | `lib/src/testing/` | 150–250 | — | +6 | 宿主不懂首帧判据也能写测试 |
| C16 | `refactor(mova): 改名遗留收尾` | API | `ui/mini/mini_host.dart`、广告覆盖层、工厂 typedef、`deprecated_names.dart` | 100–200 | — | +2 | 全部 `@Deprecated` 别名 |
| C17 | `docs(mova): README、SPEC、CHANGELOG、CLAUDE.md、DESIGN 对齐与版本号对账` | 文档 | 见第 9 节 | 400–800（文档） | 全部 | — | 第 9 节清单逐项勾完；顺带修过期 dartdoc：`core/api.dart:368-371`、`core/options/stt_config.dart:36,45`；README 写明 feed 预取与 STT 模型下载的已知限制 |

**C04/C06 拆分（2026-11-03，逐 Task 子计划见 [2026-11-03-c04-c06-chrome-style.md](2026-11-03-c04-c06-chrome-style.md)）**：C04 拆为 C04a–C04d，C06 拆为 C06a–C06e（C06e 可裁剪），阶梯合计 66 → **73**。C 块内顺序改为 C04 → C06 → C05（依赖不变，C05 的全屏文案与样式直接走 `MovaPlayerStyle`/`MovaStrs`，免得 C06b 二次迁移）。C03 落地时对样式节保守（样式节变化仍重建视图），到 C06d 再放宽。C04/C06 检查点失败需移出时保留 C08/C09，另起提交删掉新类型的 `show` 导出，不连带回退。测试增量 C04 +32、C06 +23（不做 C06e 为 +20），高于本表原估。

→ **CP3：合并前全量** → 合并（`--no-ff`，一次）

合计：准备 3（S00、S01、A19）+ B 16 + A1 17（含 A14b）+ A2 13 + C 17 = **66 个提交**（C04/C06 拆分后为 73，见上）。机械提交 4 个（A01、A09、A17、A22），测试/工具提交 3 个（S00、S01、A19）；C08、C09 只调整导出和加注解，归 API 类，不算机械搬迁。测试数预计从 1752 增到约 2100–2250。

### 3.3 难点提交详述

**A02 cutover 操作代际**
- 新增 `int _op`，`open()`、`reload()`、`cutoverTo()` 入口、`dispose()` 递增；`prepare()` 不递增（同源去重、异源先 abandon，现有逻辑 cutover_engine.dart:459-467 已覆盖）。
- 代理 `open/reload`：`_op++; unawaited(abandon());` 再转发。abandon 的同步前缀（:799-836）已经清槽并唤醒等待者，不需要 await。
- `commit()` 认领时取 `final op = _op` 与槽对象；`_commitNow` 在 `old.pause()`、`_holding`、keepAlive、继承设置、解静音、`shadow.play()`、`_detach` 每个 await 之后检查 `_disposed || op != _op`，过期就只 dispose 已认领的影子（恰好一次）并返回 false，不碰 `_active`、不碰新槽。
- 收尾（现在的 :710-720）只做"换指 + 本槽相关字段"，`_slot` 若已被新的 prepare 占用就不动它，相位也归新槽。
- 解静音失败分支（:693-701）现在是 `_shadow = shadow; await abandon();`，会把认领出去的影子塞回全局槽再走 abandon，可能冲掉新槽——改为直接释放认领的槽对象。
- `cutoverTo` 取自己的 op，`commit` 失败时若 op 已过期**不回落 `_active.open`**（Codex：过期不得回落抢源）。

**A03 广告侧**
- `_beginLoad` 在第一个 await 前：取消三个计时器、清 `_pending`、`unawaited(_cutover?.abandon())`。[已核] 现在只清簿记（ads.dart:452-456）。
- `_goIdleAfterContent` 加 abandon（:1136-1143 目前没有）。
- `_warmContentBehindAd` 在当前广告位是 post 时直接返回（后贴片之后没有正片可回）。注意这是"往哪个方向预热"的判断，不是"是否等待就绪"的判断，不违反 SPEC.md:280"ads.dart 里不许出现与等待相关的 kind 判断"，代码注释写明。
- `_beginAd`、`_playAd`、`_resumeAfterAd`、`_onAdFailure` 入口取 `gen`，每个 await 后过期即返回，不装计时器、不恢复 STT 与倍速。

**A07 / A08 keepAlive 两处**
- A07：`MovaKeepAliveWake.reloadEdge` 与 `reopen` 两个分支在队列内只做同步迁移（`_beginResume`、`_armAttempt`），网络重开放到队列外执行，取 `attempt = _attemptId`，回来后 `attempt != _attemptId || _disposed` 即停；开播条件改为 `_playIntent && !state.playing`。`setKeepAlive(false)` 的 Future 因此在相位进入 `resuming` 时就完成，不再等网络——这是对外时序变化，CHANGELOG 写明。
- A08：恢复测量用独立的 `MovaFirstFrameGate _resumeGate`，信号同时喂两个闸门。`_armAttempt` 加参数 `partOfResume`（reloadEdge/reopen 传 true，因为它们本来就靠尝试落地来结束恢复，:1772-1773）；open/switchQuality/recover 传 false，并结束进行中的恢复测量：相位 `resuming → off`，原因 `reloaded`，**不发** `MovaKeepAliveResume`（测量已无意义）。

**A09 / A10 加载规格**

A09 只记录：每条路径在 `_loadKernel` 之前写 `_currentLoad`，读取方一行不改。A10 才让重载读它。各理由的差异是有意保留的：

| reason | 新会话 | 清进度 | 归零时长 | 清清晰度列表 | 当前档 | 发 SourceChange/Ready | 续播 |
|---|---|---|---|---|---|---|---|
| open（含公开 `reload`） | 是 | 是 | 是 | 是 | 清 | 每会话一次 | — |
| retry | 否 | 是 | 是 | 否 | **按规格保留** | 每会话一次（已发则不发） | 首帧后续到失败点 |
| failover | 否 | 是 | 是 | 是 | 清 | 同上 | 同上 |
| quality | 否 | 是 | 是 | 否 | 设为 q | 否 | 寄存到落地 |
| timeshift | 否 | 只写 `_lastPosition` | 否 | 否 | 保留 | 否 | — |
| liveEdge（回边缘/重开） | 否 | 是 | 否 | 否 | 保留 | 否 | 退出时移 |

retry 在时移中用规格里的 `timeshiftBehind` 按当前时间重建地址（保持同样的落后量）；failover 清时移。连点两次换档时，第二次的续播点取"上一次尚未落地的续播目标"，不读被清零的 `_lastPosition`（P2-1）。恢复等待首帧期间的用户 seek 改写 `_recoveryPosition`（P2-3）。

**A13 / A14 / A14b 错误模型（一个设计单元，三个提交，顺序固定）**
- 分级复用 `report/error_policy.dart` 的前缀判据，但它吃的是带子系统前缀的 log 行，`MovaKernel.error` 不带前缀（`kernel.dart:140`）；前缀只在 `MovaStatsProbe.logs`。所以 A13 必须有**内核层接线**：在 `mpv_kernel.dart` 里用 `logs` 前缀产出带分级的错误（可选能力，`MovaKernel` 抽象零新增成员；形态 [待核]，开工前出设计）。内核日志行默认非终结；已知终结前缀（`Failed to initialize a decoder`、`Failed to recognize file format.` 等，CHANGELOG Unreleased 已列）为终结；`END_FILE(error)` 与 `MovaGiveUpError` 为终结。A13 只分类，不改 `state.error` 行为。
- **为什么 A13→A14→A14b 不能换序**：若先收窄 `state.error`（原 A13）再订阅 END_FILE（原 A14），两者之间 404 坏地址既没有终结错误、又被收窄，出现行为回退窗口。现在 A14 先让 `END_FILE(error)` 成为终结错误并写 `state.error`，A14b 最后才把非终结错误挡在 `state.error` 之外。
- A14：recovery 关时也订阅 `endFiles`（懒启动，首次 `open()`），`END_FILE(error)` 转终结错误并清缓冲标志（复用 `_giveUp` 的清理）；`alternatives` 非空而 recovery 关时 debug assert。**封面与 RESTART**：待拍板 7 的“挂了封面就打开 RESTART”在本提交落实（`MovaPlayer(poster:)` 路径经 `observeRestarts` 打开；`MovaView` 已是 `preciseFirstFrame: poster != null`）；原稿“首帧判据不变”只指无封面路径。`openness_host_test.dart:40` 的 `endFilesSubscribed isFalse` 断言要改；同文件 :38-39 的 `movaObserveFlags(...).native/.qoe isFalse` 仍成立。
- A14b：非终结——照发 `MovaErrorEvent(fatal: false)`、走钩子 `onError`，不写 `state.error`，不弹遮罩。这是对默认行为的破坏性变更，待拍板 16。
- recovery 关时 `open()` 失败：本分支**仍抛**（兼容），同时写终结 `state.error`；CHANGELOG 预告下个版本不再抛（待拍板 10）。

**A18–A21 广告时钟、意图、后台**
- 时钟默认运行。会话订阅 `api.states`，只在 phase=ad（slot）或 phase=pending（delay）时，把 `playing` 的 true→false 边沿转成 `pause()`、false→true 转成 `resume()`。FakeMovaApi 不推 playing，所以 ads_test 98 条里依赖墙钟到期的用例不受影响（终审 5）。
- A20 的意图快照：`_commitNow` 在 `await old.pause()` **之前**读 `old.state.playbackIntent`；换指后意图为真才 `shadow.play()`，否则 `shadow.pause()`（让影子意图也为假）。不能用 `wasPlaying`（:663）：广告自然播完时内核 `playing` 本来就是 false，照用会让"前贴片后正片"不起播。普通路径（无 cutover）的 `_api.open(c, autoPlay: 意图快照)` 同理，快照在 `_resumeAfterAd` 入口取。
- [已核] `MovaState.playbackIntent` 默认 false（state.dart:235），FakeMovaApi 的 open/play/pause 不维护它（fake_api.dart:328-357）。A19 只修 ads 侧的 FakeMovaApi；**A20 自己会让约 8–12 条 cutover 断言变红**（旧引擎在这些测试里从未 `open`，意图恒 false，影子不开播），这些断言由 A20 同提交改写为给测试替身旧引擎预置意图（清单见 3.2 A20 行）。
- A21：`Video(pauseUponEnteringBackgroundMode: false, resumeUponEnteringForegroundMode: false)`（参数名按评审对 media_kit_video 2.0.1 的引用 [材料]，落地前对 pub cache 里的源码核一遍）；`MovaPlayer` 自带一个最小生命周期监听，切后台时 `api.pause()`（默认开，保持今天"切后台会停"的可见行为），祖先有 `MovaAutoPause` 时让位给守卫。这样后台暂停经过钩子、写对意图，广告时钟也能从 playing 边沿看到。**监听与 `Video` 两个参数只在有 `Video` 渲染面时启用**：audioOnly 引擎没有 `Video`（`renderHandle == null`），media_kit 的后台暂停本来就不存在，自带监听反而会把音频在后台停掉；audioOnly 保持现状（后台继续播，宿主要停自己用 `MovaAutoPause`）。CP2 加 audioOnly 后台一组。

**A22 机械搬迁**

搬迁对象是 ads.dart 的整个状态机（约 1200 行）。`MovaAds` 留下构造参数、getter、方法、流的转发，以及"显式 `cutover:` 才启用"的旧语义。判据：五个广告相关测试文件（含 `ad_stale_first_frame_test`）与 `test/core/cutover/` 零改动全绿（A22 的 diff 不含 `test/`）；`--color-moved` 下非搬迁行 < 80 且逐条列出。微任务顺序是最大风险（第 6 节 R-2）：转发一律同步返回内部 Future，不加 `async` 包装。

**A26 失败仲裁的分工**
- 广告节点：失败仍走 `MovaAdFailPolicy`（宿主策略不变）。引擎 recovery 开着时，会话对广告节点的非终结错误不动作，只认 `MovaPlayFailure(giveUp)`、终结错误或广告自己的 `loadTimeout`；`loadTimeout` 先到时由会话裁决并打开下一节点（新 `open` 自然取代引擎的重试）。
- 正片节点：recovery 开时等引擎；`giveUp` 或 recovery 关时的终结错误 → `contentError` + `MovaNodeFail(failItem)`；播放列表默认不因失败自动下一集。
- 同一 (epoch, node, attempt) 只结算一次，open 抛出、playerError、loadTimeout 三路合流（5.3 的 10）。被拒或被取代**不是**失败。

---

## 4. 真机检查点

通用约束沿用矩阵 §2：基于真实事件取证（原生 path/time-pos、`renderEpoch`、`MovaDone` 事件戳），不用墙钟；URL 加时间戳防缓存；Android 实验前确认亮屏解锁（`dumpsys window | grep isKeyguardShowing`）。设备：STG-AL00（Android 12 arm64，release）+ 本机 Windows（release；profile 只用于需要切 Skia 对照的场景）。本地源走 `example/tool/verify_sources/` + `adb reverse`。

**F3/A17 判据统一**（矩阵 F3-② 写着"<200ms 与 ±500ms 待统一"，ACCEPTANCE-MATRIX.md:375）：本计划以**原生 time-pos 落点与目标差 ≤500ms 且 path 正确**为通过线，同时记录 <200ms 的占比。理由：复测各轮都用 ±500ms，500ms 也是引擎回声抑制的容差（engine.dart:499）。这一条列入待拍板 15。

### 4.0 验证页与脚本清单（CP0–CP2，约 15 个新场景）

项目 CLAUDE.md 要求验收 demo 单独建页、不与其他 spike 混用。下列 15 个场景现有 `gap-*` 与 `main_*_verify.dart` 都不覆盖，需各建一个验证页 + AUTORUN 脚本（沿用 `example/lib/verify_auto/` 模式），按每个 0.5 人天计入 7.3（共 7.5）：

| 检查点 | 新场景 |
|---|---|
| CP0 | ① P0-2 三种触发现场；② pod 第二条广告 `cutoverTo` 是否回落；③ P1-14 后台暂停来源对照（`Video` 参数开/关）；④ P2-2 暂停加载期间 play 时间窗 + P2-25 sessionStart 取值；⑤ P2-5 时移时间基；⑥ P2-16 外层 PageView 手势 + P2-29 音频焦点 |
| CP1 | ⑦ 终审 7a 唤醒后 5s 内换源；⑧ 终审 7b 回边缘途中暂停；⑨ 错误分级（非终结日志不弹遮罩、404 终结、有封面首帧信号）；⑩ A12/N6 探测与手选档；⑪ A16 `manageAuto`；⑫ B04 亮度/方向还原 + N3 预览 404 挂起 dispose；⑬ B11/B12 池重试与 feed 滑窗 |
| CP2 | ⑭ 广告中暂停/切后台 + pod/播放列表 3 集；⑮ audioOnly 后台 |

### CP0 补真机基线（S01 之后，lib 未改）

| 项 | 内容 | 次数 | 记录什么 |
|---|---|---|---|
| 跑批修复验收 | S00 后对当前 main 跑一遍全部可自动批次 | 1 轮 | 新 ledger，作为 CP1–CP3 的对照基线 |
| F3/A17 precise | 普通/暂停/cutover 三组，HLS | 280 次（沿用 rerun6 口径） | 失败数与失败特征；rerun6 是 279/280 |
| H28 默认配置 | 同上三组，`createMovaEngine()` 不开泵 | 每组 30，共 90 | 这条路径至今零真机数据（矩阵 §4.2-1） |
| H20/H50 | HLS open 后立刻 seek(15s)；`cutoverTo(hls, at: 12s)` | 各 30 | 矩阵 §4.2-2，用例已写待上机 |
| H7、H14、H17、H33、H42、A15.miniPip、H37.dispose | gap-assumptions / gap-lifecycle 已写好的用例 | 按用例 | 矩阵 §4.2-3~8 |
| P0-2 现场 | ads+cutover 开：正片预热中 / 中插 pending 中 / 后贴片后 `load(B)` | 各 10 | 是否播成上一集（原生 path 对账）；作为 A03 的修前对照 |
| CLAUDE.md ③ | pod 第二条广告 `cutoverTo` 是否回落成 open | 10 | `renderEpoch` 是否递增 |
| P1-3 | mpv auto 档在限速源下选哪一档、会不会变 | 5 | 决定 A16 文档措辞 |
| P1-14 | 无守卫切后台：暂停来源（`Video` 参数开/关两组对照）、回前台是否需手动 | 各 5 | 决定 A21 与 CLAUDE.md 小窗归因更正（待拍板 9） |
| P2-2、P2-5、P2-16、P2-25、P2-29 | 暂停加载期间 play 的时间窗；时移时间基；外层 PageView 手势；sessionStart 取值；音频焦点（来电/其他 App 放音） | 各 3–5 | 决定是否排修复 |
| Windows | F3 子集 30、A23/F13 dispose 20、HE V6 5、HE V10 20 | 按项 | Windows 基线 |

通过标准：CP0 不设通过线，只要求每项有可复核的数字。设备时间：Android 约 2.5 天，Windows 0.5 天（不含 S00 修脚本，那算在代码成本里）。

#### CP0 第一轮落地记录（2026-11-03）

在独立 worktree（lib 与 main 一致）完成，两个提交已拣回本分支：
- **S00b 原始证据收口**：r1030 离线重放 **PASS 61 / FAIL 9 / BLOCKED 65**（135 个编号）。S00 的完成判据（BLOCKED 只剩真缺用例/环境）**尚未达到**：BLOCKED 中多数是验证脚本缺 `*.coverage1` 判据，逐条见 [S00b 报告](2026-11-03-s00b-evidence-replay.md)；FAIL 归因四类（接收快照与 payload 不一致、TLS IP SAN、keepAlive grace 判据、无声流位置倒退）同在该报告。
- **CP0 六个新验证页 + Android 最小冒烟**（各 1 次，正式次数未跑），见 [CP0 报告](2026-11-03-cp0-pages-and-smoke.md)。修前现场已坐实：P0-2 在 `load(B)` 返回后仍读到上一集 A 243 次（原生位置跨度 8880ms）；pod 第二条广告 `renderEpoch` 0→0（**更正（2026-11-03 A2 子计划核实）**：该页用两条前贴片且未配等待，前贴片默认不等待就绪，按设计走直接 open、不换指，所以这个数字**不能**说明 cutoverTo 回落；pod2 页已改为等待型变体 + 不等待对照，重测前 CLAUDE.md ③ 仍无真机结论）；`Video` 后台暂停参数开时回前台需手动恢复、关时继续播放；暂停加载夹具里 B（WebM）的 sessionStart 3/3 仍报 A 的 MP4。音频焦点维持 manual BLOCKED。
- 仍欠：上表的正式次数跑批（全量可自动批次、F3/A17 280、H28 90、H20/H50 各 30、gap 用例、P1-3、Windows 组）与 S00 的判据缺口。

### CP1 引擎、切换与 B 块（A16 之后）

| 项 | 次数 | 通过标准 |
|---|---|---|
| F3/A17 precise 三组 | 280 | 失败数 ≤ max(CP0 失败数, 1)，且没有新的失败特征（尤其"从头播"）；<200ms 占比不低于 CP0 超过 5 个百分点 |
| H28 默认配置三组 | 90 | 失败数 ≤ CP0；若 CP0 本身就差，记为既有问题，不阻塞 |
| H20/H50 HLS | 各 30 | ≤ CP0 失败数 |
| P0-2 三种触发 | 各 10 | 0 次播错集 |
| keepAlive S1/S7/S13/S14 | 各 5 | 与 CP0 一致 |
| 终审 7a：B 唤醒后 5s 内换源 | 10 | 新源 `MovaFirstFrame` 10/10 |
| 终审 7b：回边缘途中用户暂停 | 10 | 保持暂停 10/10 |
| 恢复：HLS 卡死→重试续播（H35）、手选 720p→卡顿→重试仍是 720p 地址 | 各 10 | 续播误差 ≤500ms；地址对 10/10 |
| 错误分级：播放中非终结内核日志、404 坏地址（recovery 关） | 各 5 | 前者不弹遮罩；后者终结错误、转圈消失 |
| A14：挂 poster 的 `MovaPlayer` 首帧信号 | 5 | 首帧 `signal` 为 `restart`，封面不早于首帧撤掉 |
| A12/N6：命令式 `open` 后清晰度列表；探测在途时手选 720p；同会话只探一次 | 各 10 | 列表非空 10/10；手选档保持 10/10；探测请求每会话 1 次 |
| A16：`manageAuto` 开，限速源下 auto 档降档；默认关时行为不变 | 各 5 | 开：降档且不被永久屏蔽；关：与 CP0 一致 |
| B11：池 `open` 被拒/抛错后重试；B12：feed 连续浏览滑窗内存 | 各 5 / 3 | 重试成功、不显示旧素材；缓存条数有界、PSS 不单调爬升 |
| A23/F13 创建销毁 | 120 | 120/120，dispose 期间帧间隔 <100ms |
| B 块：亮度播种与还原（A9）、宿主竖屏锁下进出全屏（A14/A16）、预览 404 挂起时 dispose（N3）、抽帧（A30/F10）、底栏 patch、弹幕 5000 条跳转 | 各 3–5 | 行为符合提交判据；弹幕跳转无掉帧尖峰（记录帧耗时，不设硬线） |
| Windows：F3 子集 30、A23 20、V10 20 | 按项 | 不劣于 CP0；V10 0 崩溃 |

设备时间：首轮 Android 3 天 + Windows 0.5 天（含新增 A12/N6、A16、B11–B12 检查行）；预留一轮修复复测 2 天。

#### 2026-11-03 CP1 报告逐项收口

本人独立执行，按六项顺序提交。原报告16行 PASS7/FAIL3/BLOCKED6；本次 **PASS13 / FAIL0 / BLOCKED3，CP1仍未整体通过**。原始15条FAIL及所有中间缺测不回写，完整历史、逐行新下标与构建哈希见 `doc/plans/2026-11-03-cp1-results.md` / `.json`；过程见 `2026-11-03-cp1-closeout.md`。未改 lib，修复集中于验证器、采样时序和夹具。未列为复测的既有PASS保留原APK/证据归属。

|CP1行|实测/计划|新结论|证据路径（相对mova）|
|---|---:|---|---|
|F3/A17 precise 三组|280/280|PASS|example/tool/coverage_evidence/matrix-cp1-android-cutover-20261103-1656-precise-cutover/cp0-result.json|
|H28 默认三组|90/90|PASS|example/tool/coverage_evidence/matrix-cp1-close-h28-r3-1818-cp0-h28/cp0-result.json|
|H20/H50 HLS|60/60|PASS|example/tool/coverage_evidence/matrix-cp1-android-hls-20261103-1708-cp0-parked/cp0-result.json|
|P0-2 三种触发|30/30|PASS|example/tool/coverage_evidence/matrix-cp1-cp0-p02-20261103-1724/matrix-cp1-cp0-p02-20261103-1724-cp0-p02.json|
|keepAlive S1/S7/S13/S14|20/20|PASS|example/tool/coverage_evidence/cp1-close-keepalive-review/visual-review.json；example/tool/coverage_evidence/cp1-close-keepalive-core-comparison.json|
|终审7a|10/10|PASS|example/tool/coverage_evidence/matrix-cp1-close-wakeswap-1838/matrix-cp1-close-wakeswap-1838-cp1-wakeswap.json|
|终审7b / fallback|20/20|BLOCKED|example/tool/coverage_evidence/matrix-cp1-close-edgepause-relative-2023/matrix-cp1-close-edgepause-relative-2023-cp1-edgepause.json（旧归因见原1542批次 records[1256,1258,1281,1539,1540]）|
|H35 / 手选720p重试|20/20|PASS|example/tool/coverage_evidence/matrix-cp1-close-recovery-r3-1853/matrix-cp1-close-recovery-r3-1853-cp1-recovery.json|
|错误分级|10/10|PASS|example/tool/coverage_evidence/matrix-cp1-close-errclass-1832/matrix-cp1-close-errclass-1832-cp1-errclass.json|
|A14 poster|5/5|PASS|example/tool/coverage_evidence/matrix-cp1-close-errclass-1832/matrix-cp1-close-errclass-1832-cp1-errclass.json|
|A12/N6 探测|40/40|PASS|example/tool/coverage_evidence/matrix-cp1-close-probe-1858/matrix-cp1-close-probe-1858-cp1-probe.json|
|A16 / A11|20/20|PASS|example/tool/coverage_evidence/matrix-cp1-manageauto-20261103-1550/matrix-cp1-manageauto-20261103-1550-cp1-manageauto.json|
|B11/B12 池与feed|13/13|PASS|example/tool/coverage_evidence/matrix-cp1-pool-20261103-1601/matrix-cp1-pool-20261103-1601-cp1-pool.json|
|A23/F13 dispose120|120/120|PASS|example/tool/coverage_evidence/matrix-cp1-dispose120-20261103-1615/matrix-cp1-dispose120-20261103-1615-cp1-dispose120.json|
|B块亮度/全屏/预览/抽帧/底栏/弹幕|18/21|BLOCKED|example/tool/coverage_evidence/matrix-cp1-b-extract-20261103-1640/extract-results.json|
|Windows|12/12|BLOCKED|example/tool/coverage_evidence/win-cp1-close-2043/result.json；doc/plans/2026-11-03-win-quiet-mode.md|

- H28暂停/cutover原0秒读回是在既有链恢复前提前采样，原时序确认下一次seek前已自愈；稳定窗4红→4绿，既有链新增2条回归通过，三模式各30/30。没有产品修复红绿（lib未改）。
- B14/C06已落地lockToggle，更新完整有序快照；三轮目标12/12 PASS，另立B.skin辅助行。B03底栏专属刺激仍0/3，不拿skin代替。
- 独立404 END_FILE：原CHECK仅晚于核心fatal33.242ms，早于100ms独立泵，立即释放造成缺采；等待真实END_FILE再释放，新5/5。
- 7a延迟夹具网络超时调到20s后10/10；恢复限速/预读上限与原生稳定落点后20/20；探测真实滑动直播主源404、备用源和关闭组补齐40/40。
- 7b/fallback：绝对URI20/20、保留原始相对URI对照20/20，但旧协议错误未复现，服务/产品责任未闭合，因此整行仍BLOCKED。输出形状测试2红→2绿仅证明夹具契约，不能证明旧问题根因。
- keepAlive：CP0产品revision a5c317f6归档重建同一诊断入口，原生库与原APK哈希一致；S1/S13两版各5轮，S7/S14阶段token、双帧运动、精确ACK及人工联系表齐备。原CP0首轮采图缺失保留BLOCKED并显式补采；当前四场景20/20 PASS。
- Windows依本次用户约束每项最多3次：F3三模式各1、dispose/V6/V10各3；当前功能12/12 PASS、V10 0崩溃。7次有效启动经win_policy、640×360、NOACTIVATE/TOOLWINDOW，965次只读观察前台违规0。CP0数字基线仍PENDING，F3/dispose/V6“不劣于CP0”仍BLOCKED。本次不能替代原20/30次目标。
- B块仍缺：OEM系统亮度/Insets字段完整对账、有效抽帧前提、底栏专属刺激、弹幕同口径性能基线/判据。额外POD2公共FirstFrame契约两行仍BLOCKED，不计入本表16行。
- 检查：Flutter全量2094 PASS，皮肤24、事件泵24、恢复/探测23 PASS，均 --concurrency=3；analyze未与全量并行。Python closeout12、matrix56、Windows策略11 PASS，matrix --check PASS。设备原音量0/常亮7/既有gnirehtet映射已逐值核验恢复，最后APK拉回哈希一致。
- 执行偏差：Windows首次CMake配置失败留下Program Files默认安装prefix，后续构建误覆盖既有 `C:\Program Files\mova_example`；无旧备份无法安全恢复，已明确告知用户且未删除既有目录。之后固定本树prefix，并在构建前后核验路径。清单 `example/tool/coverage_evidence/win-cp1-close-2039/external-install-incident.json`。此处不能声称本轮所有写入均在worktree内。

前五提交：a0420953、e3879cbb、7140747b、ca071d9d、f3320979；第六提交为本报告/总计划收口，最终hash见git记录。

### CP2 会话、广告与后台（A30 之后）

| 项 | 次数 | 通过标准 |
|---|---|---|
| A24/F4 广告各路径（pre/mid/post/pod），正片含 HLS（H15/H20/H50） | 各 5 | 续播误差 ≤500ms；`renderEpoch` 按次递增 |
| 广告中暂停 10s 再续 | 10 | slot 剩余时长误差 ≤300ms；暂停期间不发 completed |
| 广告中切后台 30s（Android，无守卫与有守卫两组） | 各 10 | 后台不发 completed、不出声；回前台按守卫语义续播 |
| pod 第二条广告（CLAUDE.md ③） | 10 | 每条都走无缝切换（`renderEpoch` 递增 10/10） |
| 播放列表 + 广告 3 集自动连播 | 5 | 每集都有前贴片和中插；`contentEnded` 每集一次 |
| 倍速恢复（F16）、Q13 预热静音不碰系统音量 | 各 5 | 与 CP0 一致 |
| 后台暂停所有权：无守卫 MovaPlayer、MovaView(autoPause) V9、PiP F5/A15/A18、直播隐藏 ≥3s 回边缘 H61 | 各 5–10 | 无守卫：后台暂停且意图为假；有守卫：回前台自动续播；PiP 不暂停 |
| audioOnly 引擎无守卫切后台 30s（A21 只在有 `Video` 渲染面时启用） | 10 | 后台继续出声、`playbackIntent` 不变；同组有渲染面的引擎仍按守卫语义暂停（对照） |
| F1/F7 事件序列、QoE 会话数 | 各 5 | 内部重试与换档不产生新 QoE 会话 |
| Windows：广告基本路径 5、路由覆盖 V10 20 | 按项 | 0 崩溃 |

设备时间：Android 3 天（含 audioOnly 后台一组）+ Windows 0.5 天；预留一轮修复 1.5 天。

### CP3 合并前全量（C17 之后）

- 全部可自动批次（Android）跑一轮，与 CP0 ledger 对比：**不允许出现新的 FAIL**；BLOCKED 只能是 CP0 已有的那几项。
- F3/A17 precise 280 再跑一次（C04 搬了控制条计时、C07 的 `start` 走寄存路径），标准同 CP1。
- C05 全屏路由：Windows 进出 20 次 0 崩溃（转场快照路径）；Android 返回键先退全屏、锁定时提示解锁。
- C06：切主题与语言 10 次，位置连续、引擎不重建（`renderEpoch`、会话 id 不变）。
- C07：带 Referer 的防盗链 CDN（本地源模拟）上清晰度列表、缩略图、feed 预取都成功。
- C14：`MovaFeedPlayer` 控制器、内置自动暂停、单页失败可见各 5 次。**C14 排在 CP2 之后，所以检查行放在 CP3 而不是 CP2**。
- Windows 子集同 CP1。

设备时间：Android 2.5 天 + Windows 0.5 天。

---

## 5. 测试策略

### 5.1 会被迫改写的现有测试

| 提交 | 预计改写 | 原因 |
|---|---|---|
| A02 | 0–3 条 cutover 断言 | 若有断言依赖"提交收尾清空全局影子槽" |
| A07 | 1–2 条 keepAlive 断言 | `setKeepAlive(false)` 不再等网络重开 |
| A12 | 测试 rig 默认 fetcher 换 noop 后个别用例核对（`.m3u8` 出现 154 次） | 避免真实 fetcher 在 fakeAsync 留 timeout 计时器 |
| A14b | 10–25 条（engine_test、overlays_test 等） | 非终结错误不再写 `state.error` |
| A14 | `openness_host_test.dart:40` 的 endFiles 断言 | 推翻"recovery 关时不订阅" |
| A15 | ads_test 中"任意 MovaErrorEvent 判失败"的用例 | 改为终结错误 |
| A18 | ≤3 条 `delayRemaining` | 展示改由时钟给 |
| A19 | 视替身改动而定，逐条列出 | 替身按真实契约维护意图 |
| A20 | 约 8–12 条 cutover 断言（`cutover_engine_test`、`cutover_keep_alive_test`、`cutover_warm_mute_test`、`cutover_engine_defects_test`） | 影子“意图为真才开播”，旧引擎在测试里从未 open、意图恒 false；改写为替身旧引擎预置意图 |
| B15 | 1–3 条 | 同值不再发事件 |
| C04/C06 | UI 测试改走新接口的一部分 | 旧接口保留桥接，大部分不必改 |

A01、A09、A17、A22 四个机械提交**一条都不改**，这是它们的验收标准（A22 的口径：diff 不含 `test/`；A20 已改写的 cutover 断言发生在 A22 之前）。

### 5.2 替身增强（S01）

- **FakeMovaApi**：`openGate`/`playGate`/`pauseGate`/`seekGate`（`Completer`，可选）让测试控制每个 await 的放行时机；`emitDone()`、`emitError(fatal:)`；可选 `pushPlayingOnVerbs`（默认 false，保持终审 5 的前提）；实例编号与 `disposeCount`，用于"恰好释放一次"断言。
- **门控引擎工厂**：给 `MovaCutoverEngine(engineFactory:)` 用，记录每个影子的源、open/seek/pause/play/dispose 顺序。这样 P0-2、N1 能用**真实** `MovaCutoverEngine` 跑，而不是 `FakeCutoverCtl`。
- **FakeCutoverCtl**：记录 `prepare` 的源与 plan，`commit` 返回"当前在途预热的源是否与期望一致"的可编程结果（`commitResultFor(source)`），并给 prepare/commit 加门控。现有 33 处用法默认行为不变。
- **严格命令日志**：跨替身的全局序号，断言"实际执行顺序"。

### 5.3 必须新增的交错测试

| # | 场景 | 断言 |
|---|---|---|
| 1 | 正片影子 ready → 无前贴片 `load(B)` → commit | 打开的是 B；A 的影子恰好 dispose 一次（真实 cutover） |
| 2 | 中插倒计时 pending 中 `load(B)` | 广告影子不被当正片提交 |
| 3 | 后贴片 → idle → `load(B)` | 没有残留影子；B 全新打开 |
| 4 | commit 已认领、卡在 `old.pause()` → 代理 `open(B)` | 提交放弃，影子释放一次，生效引擎播 B |
| 5 | commit 已认领、卡在 `old.pause()` → `prepare(C)` | 提交完成后 C 仍在预热、订阅仍在；dispose 时 C 被释放 |
| 6 | 并发 `cutoverTo(X)`、`cutoverTo(Y)` | 只有 Y 换指；X 过期不回落 open |
| 7 | 提交途中 dispose | 所有等待者都有结果；影子释放一次 |
| 8 | `_playContent` 等 commit 时旧广告引擎 tick 越过某中插 offset | 不触发中插（终审 7d） |
| 9 | `_beginAd`/`_playAd` 的 await 期间 `load` 新内容或 dispose | 不装旧计时器、不恢复 STT 与倍速、相位不回写 |
| 10 | 同一广告：playerError + open 抛出 + loadTimeout 同时到 | 失败策略只调一次 |
| 11 | slot 计时中 playing true→false→true；暂停中 skip；暂停中 Done；暂停中 `load` | 剩余时长保留；三路续播只结算一次 |
| 12 | 广告自然播完（内核 playing=false，意图为真） | 正片开播（防 `wasPlaying` 误用） |
| 13 | 广告中用户暂停 | 正片以暂停态提交，影子意图为假 |
| 14 | 播放列表 + 广告：3 集自动连播；中插 pending 时手动 next；open 被拒；jumpTo 被取代 | 每集重置广告簿记；后贴片前不推进；被拒下标不动 |
| 15 | open(Y) 被 hook 拒绝时，`play()` 的钩子还挂着 | play 照常执行（终审 7c） |
| 16 | keepAlive 回边缘途中用户 pause | 网络回来后不开播（终审 7b） |
| 17 | B 模式唤醒后 5s 内 open 新源 | 新源首帧正常落地；恢复超时不 reset 新闸门（终审 7a） |
| 18 | 手选 720p → 卡顿 → 重试；时移 → 重试；failover；回边缘 | 实际 uri、当前档、时移量与规格一致 |
| 19 | 连点两次换档；第一次失败的收尾晚于第二次开始 | 第二次续播点正确；第一次不释放第二次的租约 |
| 20 | 清晰度探测在途时手选档 | 当前档保持手选（N6） |
| 21 | 播放中非终结内核错误 / 终结错误 | 前者 `state.error` 为 null、事件 `fatal=false`；后者写入 |
| 22 | 池：open 返回 false / 抛出后重试 / 同 URL 换 mpvOptions | 不置 ready、可重试、会重开 |
| 23 | 预览：404 后 body 不结束 | dispose 在期限内完成，内核被释放 |
| 24 | QoE：A 的 sample 迟于 B 的 open 返回 | 不写 B 基线、不发 A 心跳 |

### 5.4 fuzz 与 fakeAsync

- 现有 `engine_fuzz_test.dart` 的动作是逐个 await 的，覆盖不到并发。新增一个**带门控的交错 fuzz**：固定种子（每次 CI 跑 20 个种子），随机决定门的放行顺序与 load/pause/prepare/abandon/dispose 的插入点，最多 40 步；不变量只断言"影子恰好释放一次、生效引擎的源等于最后一次被接受的请求、没有挂起的 Future"。失败时打印种子。
- `DateTime.now()` 不跟 fakeAsync（CLAUDE.md 已记录），广告时钟用注入的 `now`，测试传 `() => start.add(async.elapsed)`；**不**为此引入 `package:clock`。
- 门控测试里避免 `pumpEventQueue` 式的"多跑几轮微任务碰运气"，每个断言前明确放行哪扇门。
- 计时器泄漏：沿用"widget 测试结束时不能有挂起的 Timer"约束，广告时钟 `cancel()` 必须进 dispose 的同步前缀。

---

## 6. 风险与回退

### 6.1 风险总表

| # | 风险 | 概率 | 影响 | 监测 |
|---|---|---|---|---|
| R-1 | A06–A12 动了 seek/闸门/ABR/keepAlive，真机回归（F3/A17 前科） | 中 | 高 | CP1 的 280 次 + H28 90 次 |
| R-2 | A22 搬迁改变了微任务顺序，广告行为暗变 | 中 | 高 | 四个广告测试文件零改动；`--color-moved` 审查；5.3 的交错测试在 A22 前后各跑一次结果一致 |
| R-3 | S00 修不好跑批脚本，没有基线 | 中 | 高 | S00 时间盒 3 天；超时则 CP0 改为人工跑矩阵 §4.2 列出的用例子集，并在第 7 节成本里加 3 天 |
| R-4 | A21 后台暂停改道影响宿主（尤其自建守卫的宿主） | 中 | 中 | CP2 后台三组；CHANGELOG 写明 |
| R-5 | A14b 后 `state.error` 变得"更少"，宿主依赖它判失败的逻辑漏判 | 中 | 中 | CHANGELOG + README 错误一节；`MovaErrorEvent` 仍对所有错误发出 |
| R-6 | 范围与成本超支 | 高 | 中 | 每个块结束时对比第 7 节估算，偏差 >40% 时启用 6.3 的裁剪 |
| R-7 | 长寿分支与 main 冲突（monorepo 里别人在动） | 中 | 中 | 每周 rebase 一次 main，只解决 `mova/` 内冲突；不碰其他子工程 |
| R-8 | 广告时钟改变计费口径（暂停期间不计） | 低 | 中 | CHANGELOG 明写；这是修错，不是新口径 |
| R-9 | A14 让每个引擎多一个弱客户端，FFI 销毁竞态 | 低-中 | 高（崩溃） | CP1 A23/F13 120 次、F14 |
| R-10 | C04 迁移让自定义皮肤失灵 | 中 | 中 | 旧接口桥接一个版本；皮肤专项 S 行在 CP3 跑 |
| R-11 | C05 全屏路由踩 Windows 转场快照崩溃（#190774） | 中 | 高（Windows） | CP3 Windows 20 次；路由内渲染面必须挂 `MovaSnapshotGuard` |
| R-12 | iOS/macOS 未验证 | 确定 | 未知 | 不在范围；文档只写 Android/Windows 通过 |

### 6.2 检查点失败时怎么办

- **CP1 失败**：先按矩阵编号定位到提交（B 块不碰 seek 路径，F3 类失败只在 A06–A16 里二分）。在分支上 `git revert` 出问题的提交（不 reset、不 force push），修好后作为新提交补回，再跑失败项 + F3 全量。同一失败修两轮仍不过，把该提交连同依赖它的提交移出本分支（见 6.3）。
- **CP2 失败**：A22 机械提交是关键分界。若失败能定位到 A22 之后，回退到 A21 状态逐个复测；若怀疑 A22 本身，用"A21 + 交错测试"与"A22 + 交错测试"的结果差异定位。
- **CP3 失败**：C 块多数是 API/UI，回退单个提交即可；C04/C06 失败时可整体回退这两个及其依赖（C05、C08），不影响 A/B。

### 6.3 裁剪与放弃条件（仍然只合并一次）

- **裁剪**：任一检查点在两轮修复后仍不过，就把阶梯截到上一个通过的检查点，把剩余提交留在一个归档分支里，**只合并截断后的前缀**。前缀本身是完整可用的：截在 CP1 等于"B + 引擎与切换修复"，截在 CP2 等于"再加会话层"。
- **放弃整条分支**：CP0 拿不到基线且人工子集也跑不出可复核数字（即回归无法归因），或 CP1 的 F3/A17 失败率在两轮修复后仍超过 CP0 的 2 倍。放弃时 P0-1（B01）和 P0-2（A01–A03）单独拆成小分支走常规合并，因为它们本身就有价值。

---

## 7. 成本估算

口径：S ≤ 2 人天，M = 3–5 人天，L ≥ 5 人天；含单测与提交说明，不含等设备。设备时间单列；终审含每块一次 Codex review + Claude 逐条终审。

### 7.1 按提交

| 块 | 提交与人天（最可能） | 小计 |
|---|---|---|
| 准备 | S00 3（M）· S01 1.5（S）· A19 1（前移） | 5.5 |
| B | B01 1 · B02 2 · B03 1 · B04 3 · B05 2 · B06 3 · B07 1.5 · B08 2 · B09 3 · B10 1 · B11 1 · B12 2.5 · B13 1 · B14 2 · B15 1.5 · B16 4 | 31.5 |
| A1 | A01 1 · A02 4 · A03 2.5 · A04 1 · A05 1.5 · A06 1 · A07 1.5 · A08 1.5 · A09 3 · A10 3 · A11 2 · A12 1.5 · A13 5 · A14 2.5 · A15 1 · A16 2 | 34 |
| A2 | A17 1.5 · A18 3 · A20 1.5 · A21 2 · A22 5（L，机械但量大）· A23 5 · A24 2 · A25 2.5 · A26 3 · A27 2.5 · A28 3 · A29 1.5 · A30 1 | 33.5 |
| C | C01 1 · C02 1 · C03 1.5 · C04 8（L）· C05 4 · C06 7（L）· C07 4 · C08 3 · C09 1.5 · C10 1 · C11 0.5 · C12 0.5 · C13 2.5 · C14 3 · C15 2.5 · C16 1.5 · C17 4 | 46.5 |
| **代码合计** | | **151**（审计修订不改写各提交原估，增量统一列在 7.3；A14b 原估并入 A13/A14，见 7.3 第 3 项） |

### 7.2 按轨道与三档（审计修订前口径，仅作对照；A19 前移使准备 +1、A2 −1，合计不变）

| 项 | 乐观 | 最可能 | 悲观 | 说明 |
|---|---|---|---|---|
| 准备 | 3 | 4.5 | 7 | 悲观：跑批脚本要重写判据层 |
| B | 22 | 31.5 | 43 | |
| A（A1+A2） | 48 | 68.5 | 92 | 悲观：A22 搬迁出现顺序问题要返工 |
| C | 33 | 46.5 | 62 | C04+C06 占 15 人天，是最大的不确定块 |
| 设备时间 | 10 | 15.5 | 30 | 最可能 = CP0 3 + CP1 3+2 + CP2 3+1.5 + CP3 3；悲观 = CP1 再多两轮（F3 前科是四轮）、CP2 多一轮、Windows 专项 3 天 |
| 终审与 review | 4 | 6 | 8 | |
| **合计** | **约 120** | **约 172** | **约 242** | |

### 7.3 审计修订：新增项 → 增量人天

| # | 新增项 | 乐观 | 最可能 | 悲观 | 说明 |
|---|---|---|---|---|---|
| 1 | A20 改写约 8–12 条 cutover 断言；A19 前移 | 0.3 | 0.5 | 1.0 | 测试替身旧引擎预置意图 |
| 2 | A12 默认值与测试 rig（默认 fetcher 换 noop，核对 `.m3u8` 用例） | 0.5 | 1.0 | 2.0 | 悲观：改走“推迟到 CP1 后”要二次返工 |
| 3 | A13/A14 合成一个设计单元（设计 1 + 内核层接线 1.5 + 封面 RESTART 0.5 + 改写 `openness_host_test` 0.5；拆为 A13/A14/A14b 三个提交，提交数 +1） | 2.5 | 3.5 | 6.0 | 悲观：内核接线形态试错一轮 |
| 4 | 公开 API：C07 破坏性处理（能力接口）+ export 级注解核对 | 0.5 | 1.0 | 5.0 | 悲观含待拍板 18 选“成员级注解”：lib 约 61 处、test 约 24 处要迁移或 ignore（+4） |
| 5 | 真机验证页与脚本：约 15 个新场景 × 0.5（4.0 节） | 5.0 | 7.5 | 11.0 | 乐观：大量复用现有 `verify_auto` 骨架 |
| 6 | A21 仅在有 Video 渲染面时启用 + audioOnly 测试 | 0.3 | 0.5 | 1.0 | |
| 7 | 被丢子项承接：A25 `playlist.enabled` 0.3 · C02 扩展 0.5 · B10 audioOnly 关 STT 0.3 · C01 README open 0.2 · B05 清单 0.2 · A10 非 keepAlive liveEdge 0.5 · B04 新类型与 opt-out 0.5 · A25 `ads.session` 口 0.3 | 2.0 | 2.8 | 4.5 | 乐观/悲观按 ×0.7 / ×1.6 |
| 8 | 开工前逐 Task 子计划的规划时间：A2 块 1.5、C04 1、C06 1 | 2.5 | 3.5 | 5.0 | 本文件是总计划，不是 Task 级计划 |
| 9 | 每周 rebase main（约 16 周 × 0.25） | 2.0 | 4.0 | 8.0 | monorepo 他人在动，R-7 |
| 10 | 其余新增测试改写（依赖补全、A14b 之外的零散） | 1.0 | 1.5 | 3.0 | |
| | **代码侧增量小计** | **16.6** | **25.8** | **46.5** | |
| 11 | 设备时间增量（CP1 +0.5 天、CP2 +0.5 天；悲观再加一轮新场景复测） | 0.5 | 1.0 | 2.0 | 设备时间 10.5 / 16.5 / 32 天 |

**修订后三档**（含设备时间与终审）：

| | 乐观 | 最可能 | 悲观 |
|---|---|---|---|
| 审计前（7.2） | 120 | 172.5 | 242 |
| 增量（上表） | +17.1 | +26.8 | +48.5 |
| **合计** | **约 137** | **约 199** | **约 291** |
| 其中设备时间 | 10.5 | 16.5 | 32 |
| 提交数 | 66 | 66 | 66 |

设备时间要人在场（解锁手机、看画面、换网络条件），代理只能压缩编码时间。按一人主导、代理落地估，日历上大约 3–5 个月；真正卡进度的是四个检查点。

---

## 8. 待拍板

每项给推荐默认值；不反对就按默认走。标"推翻"的会改变已定的决定。**默认路径不引入任何新第三方依赖**；下表里凡可能引入依赖的都单独标出。

| # | 事项 | 推荐默认 | 理由 |
|---|---|---|---|
| 1 | 播放列表怎么和广告组合 | `MovaPlaylist(api, ads: ads)`，内部与 `MovaAds` 共享同一个 `MovaSession`；不做通用 `opener` 回调 | opener 拿不到接受结果，也解决不了两边各自响应 `MovaDone` 的争抢；共享会话后只有 `contentEnded` 一个推进源 |
| 2 | `ads.load` 怎么表达接受结果 | `MovaAds.load/loadDeferred` 返回 `Future<bool>`（accepted）；`MovaSession` 返回 `MovaLoadOutcome` 枚举 | `Future<bool>` 是 `Future<void>` 的子类型，调用方零改动；只有覆写 `load` 的子类受影响 |
| 3 | 广告时钟与后台暂停归谁 | 广告时钟归会话，按观测到的 `playing` 边沿暂停/恢复；后台暂停归 UI 守卫层：`MovaPlayer` 关掉 media_kit 自带的后台暂停，自己经 `api.pause()` 暂停（默认开，保持今天"切后台会停"），有祖先 `MovaAutoPause` 时让位；**只在有 `Video` 渲染面时启用**，audioOnly（无渲染面）保持现状、不被后台停播 | 时钟看 playing 边沿，无论谁暂停都能感知；后台暂停经过引擎后 `playbackIntent` 才可信，A20 的续播判断依赖它 |
| 4 | STT 去向 | 从主入口撤下（`@Deprecated` 转导出一个版本），`MovaApi.stt` 保留；**引擎选型以 [2026-08-04 定案](../notes/2026-08-04-stt-engine-decision.md) 为准：sherpa-onnx Zipformer**，归 mova_stt 子工程，mova 本体不带任何识别引擎；CLAUDE.md"倾向 whisper.cpp"那段改为指向定案 | 定案晚于 CLAUDE.md 那段（08-04 vs 08-01），有实测依据。mova 本体不新增依赖；mova_stt 的依赖由那边决定（我没有读兄弟目录，"mova_stt 已用 sherpa-onnx"来自评审 §9-3 [材料]） |
| 5 | 网络探针默认接线 | 接，但按需：只有预览策略是 `wifiOnly` 且真要拉远程资源时才创建探针并查询。**这会推翻 `wiring.dart:113-134` 的"探针不默认接线"** | 原依据是 tree-shaking，但 `connectivity_plus` 已是 pubspec 硬依赖，原生插件照样注册；不接线时 `wifiOnly` 等于 always，默认策略名不副实。按需创建回应了 Codex"运行时监听有成本"的顾虑 |
| 6 | 判失败不依赖 recovery | 做：recovery 关时也订阅 `END_FILE(error)` 并转终结错误；recovery 本身仍默认关。**这会推翻"recovery 关时不订阅 endFiles"**（`openness_host_test` 锚定的那条） | 坏地址长时间转圈、没有任何事件（README:188 自己承认，[材料]）是默认配置下的硬伤；代价是每个引擎一个弱客户端 |
| 7 | 原生事件泵懒启动 | 首次 `open()` 时才建弱客户端（池里从未打开的引擎没有客户端）；挂了 poster 时额外打开 RESTART（精确首帧，**落实在 A14**；原稿 A14 写“首帧判据不变”而没有任何提交落实这条，已补）。**这会推翻 `MovaPlayer(poster:)` 路径下"精确首帧默认关"**（`MovaView` 已经是 `preciseFirstFrame: poster != null`，view.dart `_create`） | 有封面却拿不到精确首帧，封面会过早撤掉；懒启动控制了 6 带来的成本 |
| 8 | 版本号对账 | 由你在 pub.dev 确认实际已发布到哪个版本（本机访问 pub.dev 不通）。本分支所有改动记在 CHANGELOG `Unreleased`；合并后发版号按 0.x 的破坏性规则取下一个 minor | pubspec 是 `0.4.0`、CHANGELOG 有 `0.4.0` 节，CLAUDE.md 写"已发布 0.3.0"，三处对不上（[已核] pubspec.yaml:3、CHANGELOG.md:27） |
| 9 | CLAUDE.md 小窗后台暂停归因 | CP0 的 P1-14 对照实验有结论后，C17 更正为"media_kit `Video` 默认 `pauseUponEnteringBackgroundMode`"；若真机显示还叠加了 surface 回收，两者都写 | 代码证据指向 media_kit 默认参数，但需要真机分清 |
| 10 | recovery 关时 `open()` 失败是否继续抛 | 本分支继续抛（同时写终结 `state.error`），CHANGELOG 预告下一版本不再抛 | 和"运行时可恢复错误不 throw"的约束一致，但直接改会让现有 `try/catch` 宿主行为突变 |
| 11 | auto 档由 mova ABR 接管 | 加开关 `MovaAbrConfig.manageAuto`，默认关 | 新能力默认关；且 mpv auto 是否静态选档要 CP0 证实。**P1-3 的默认值策略**：本分支不把 auto 接管设为默认，P1-3 只算修到“列表可用、手选档不被覆盖”；CP0 若证实 mpv auto 在限速下确是静态最高档，再回来问是否默认开 |
| 12 | 引擎就绪后自探测清晰度 | `probeVariants` 默认开，**A12 同提交把测试 rig 的默认 fetcher 换成 noop**；备选：把默认值推迟到 CP1 之后（A12 先只加开关、默认关，P1-3“命令式 open 后列表非空”随之推迟） | 为什么要动 rig：测试里 `.m3u8` 出现 154 次，真实 `MovaEngine`+假内核会落到真实 `MovaIoHttpFetcher`，在 fakeAsync 里留 timeout 计时器，破坏 pendingTimers 断言。另外这是修缺陷：今天 `MovaPlayer.initState` 已经会探测，只是时序依赖挂载时机；同会话去重，不会多一次请求 |
| 13 | `MovaAds`/`MovaPlaylist` 是否本分支标 `@Deprecated` | 不标，作为 `MovaSession` 的薄适配器长期保留；文档推荐新代码用 `MovaSession` | 适配器很薄，保留成本低；先看宿主迁移反馈 |
| 14 | C04/C05/C06（约 19 人天）是否留在本分支 | 留 | 你要求一次理清；它们和 A/B 无代码依赖，检查点失败时可整体移出（6.3） |
| 15 | F3/A17 判据口径 | 原生 time-pos 落点 ≤500ms 且 path 正确为通过；同时记录 <200ms 占比 | 复测历轮都用 ±500ms；500ms 也是引擎回声抑制容差（engine.dart:499） |
| 16 | `state.error` 只放终结错误（A14b） | 做：非终结内核日志不再写 `state.error`、不弹遮罩，`MovaErrorEvent` 仍照发（`fatal=false`）。**对默认行为是破坏性变更**：靠 `state.error != null` 判失败的宿主会漏判一部分以前会报的错。先让 A14 的 END_FILE 终结错误落地再收窄；CHANGELOG Breaking 小节 + README 错误一节 + 迁移指引（改听 `MovaErrorEvent` / `MovaPlayFailure`）。备选（零破坏）：新增 `state.fatalError`，`state.error` 保持原样，遮罩改读新字段 | 非终结日志（如 mpv 的 cplayer 噪声）已造成误报遮罩；但直接收窄会让现有宿主的失败判断突变，所以要你明确点头 |
| 17 | C07 `MovaHttpFetch` 加请求头 | 新增可选能力接口 `MovaHeaderedHttpFetch`，**不改** `get(Uri)` 签名；旧 fetcher 退化为不带头 + debug 提示 | 直接给 `get` 加 `headers` 会让宿主自写的 `implements MovaHttpFetch` 覆写签名不匹配、编译失败（破坏性）；与本计划“不往抽象类加成员”一致 |
| 18 | `@Deprecated` 策略（C04/C06/C08/C09/C13） | 不加成员级 `@Deprecated`，只在 CHANGELOG 与 dartdoc 公告“下个版本弃用”；C08/C09 用 export 级转导出（不触发警告）；下个版本再统一加注解 | `analysis_options` 继承 flutter_lints，`deprecated_member_use_from_same_package` 对包内 lib 与 test 都报；`MovaOpts.theme/strings/gesture/controls/danmaku` lib 约 61 处读取、test 约 24 处，加注解要么迁移要么处处 ignore（约 +4 人天，已计入悲观档），否则“analyze 0 issues”不成立。备选：加成员级注解 + 同提交迁移/ignore |

可能涉及新依赖、但本计划**不做**的：VAST/VMAP 解析库、`audio_service`、`crypto`（模型 sha256）、`package:clock`。将来要做都需要你先同意。

---

## 9. 与既有文档的关系（合并时在 C17 一次更新）

| 文档 | 要改什么 |
|---|---|
| `CLAUDE.md` | 测试基线（按 3.1 规则已逐块回写，C17 只复核终值）；「当前状态」新增 MovaSession、广告时钟、错误分级、加载规格、cutover 操作代际几节；keepAlive 两处修复；小窗后台暂停归因（待拍板 9）；STT 选型指向 08-04 定案（待拍板 4）；pub.dev 版本对照（待拍板 8）；网络探针与 END_FILE 订阅的新默认（待拍板 5/6/7）；剩余任务 ②③④ 标为已处理；新增本计划链接 |
| `doc/SPEC.md` | 新增「编排会话（MovaSession）」节（模块、依赖方向、三分法、隐含语义表的精简版）；「无缝引擎切换」补操作代际与 `_WarmSlot`；「广告编排增强」补可暂停时钟（明确仍不依赖媒体时间轴）与 `contentError` 新契约；清晰度节补就绪后自探测与 `manageAuto`；新增错误分级、`MovaChrome`、`MovaPlayerStyle`、barrel 分入口；「宿主易用性」更新 endFiles 订阅规则 |
| `doc/DESIGN-0.2.0.md` | 不逐段改写；文首加一段说明：会话层、错误模型、UI 交互态的现行设计以 SPEC.md 为准 |
| `README.md` | 示例统一 `createMovaEngine`（C01 已做，C17 复核）；首屏版本说明；平台表 iOS 改为"未验证"；ads + playlist 改用 `MovaPlaylist(api, ads:)` 或 `MovaSession`；`contentError` 新契约；错误一节（`state.error` 只放终结错误）；后台行为；全屏路由；请求头；新入口文件；keepAlive 有 Windows 真机数据；把约 120 行 libmpv 构建内容挪到 mova-libmpv 文档；删掉 README:62 "交互不在保证范围内"那条，改为仲裁规则；写明不支持 DRM/投屏/离线下载 |
| `CHANGELOG.md` | `Unreleased` 下每个行为提交一条（A05 已随代码写）；Breaking/Deprecated 小节汇总 `@Deprecated` 项与 `Future<bool>` 返回类型；计费口径（广告暂停不计时）；"测试计数"挪出 CHANGELOG 正文（P2-33） |
| `doc/ACCEPTANCE-MATRIX.md` | 新增会话、广告时钟、错误分级、加载规格的行；F3 判据口径统一（待拍板 15）；§4.2 中已上机的 H 项更新结论；§7 修订记录 |
| `doc/ROADMAP.md` | 标记本计划完成的项；把 1.4 的暂缓项挂上去 |
| `doc/plans/` 本文 | 每个检查点结束后回写实测数字与偏差 |

---

## 10. 执行方式

- 按 CLAUDE.md 的"Opus 拆方案 + Sonnet 落地"走：本文是总计划，A2 块和 C04/C06 开工前各自再拆一份逐 Task 计划（落在 `doc/plans/`，规划时间计入 7.3 第 8 项）；长寿分支每周 rebase main 一次（7.3 第 9 项）。
- 档位：落地派 sonnet（low）；A22 这类大搬迁同样是 sonnet（low），机械但要守不变量，不降到 haiku。
- B 块可在独立 worktree 并行开发，按阶梯位置 rebase 进来；派 worktree 前确认基线已提交。
- 每块结束先 Codex review（`codex review --base main`，effort ≤ high），Claude 逐条终审，再进检查点。
- **实际执行（2026-11-03 起，用户指定）**：落地与跑批都交给 Codex，按阶梯每个提交由 Codex 本地提交（不 push、不改 CLAUDE.md），主会话逐批复核 analyze/测试数、组织 Codex 初审并逐条终审，再回写 CLAUDE.md 基线。上文"子代理不得自行提交"对 Codex 落地批次不适用；Claude 侧子代理仍不提交。真机跑批在独立 worktree（lib 固定在基线提交）进行，产出的 example/doc 提交拣回本分支。

---

## 附录 A：自查

- **归属表覆盖**：P0 2/2、P1 24/24、P2 33/33、P3 6/6、N 9/9、R 12/12、终审新发现 5/5、终审其余 7 条、Codex 异议 6/6、CLAUDE.md 剩余任务 ②③④（7 小项）、评审 §6 14 项、§7 能力缺口全部列入 1.4。
- **可独立提交**：每个提交只依赖阶梯上更早的提交（依赖列已写）；`@Deprecated` 的提交按 3.1 第 5 条处理 analyze。
- **行为与机械不混**：机械提交 A01、A09、A17、A22 不改断言；A19 是纯测试提交；行为提交里不夹带搬迁（A21 和 A22 刻意拆开，A20 和 A19 刻意拆开）。
- **不确定处**：A13 内核层接线的接口形态、B04 opt-out 命名、`MovaHeaderedHttpFetch` 命名、C02 只读状态 getter 命名、lib/test 的 deprecated 读取数（grep 近似值）均 [待核]；A21 的 `Video` 参数名来自评审对依赖源码的引用，落地前要在 pub cache 里核；B06、B12、B05 部分行号来自材料未复核；"mova_stt 用 sherpa-onnx"来自评审，没读兄弟目录；P2-5、P2-16、P2-29、P1-3、P1-14 的真机事实要等 CP0。


## C 块第一批落地记录（2026-11-03）

本批实际续作于 2026-11-04，在 `E:\workspaces\wt-mova-c\mova` 自行执行，无转派、无真机、无应用启动、无 push，未改 CLAUDE.md。按用户已核结果承接前五个提交，不重做：C01 `434c4baa`、C02 `98c064cc`、C03 `3f89fbb5`、C10 `a185048d`、C11 `0538c131`。基线 2234，前五项合计新增 17 项，承接测试数 2251。

续作每项均先完成回退变红验证、恢复实现，单独执行 `flutter analyze lib test`（0 issues）和 `flutter test --concurrency=2`（全量），随后立即提交；analyze 与全量测试未并行。开跑前已清理 flutter_tester 残留进程，本轮无需降并发或目录分片。

| 块 | 提交 | 全量实测通过数 | 新增测试：回退红 / 恢复绿 |
|---|---|---:|---:|
| C12 | `9bcb4856` | 2254 | 3 / 3 |
| C13 | `2e3a7977` | 2260 | 6 / 6 |
| C15 | `905e6a06` | 2266 | 6 / 6 |
| C16 | `2022caae` | 2268 | 2 / 2 |
| C12 按需边界补修 | 本提交 | 2269 | 1 / 1 |

回退验证方法：C12 把默认真实探针工厂换回恒允许探针；C13 保留公开签名，撤回策略工厂调用、借用标志、内核借用、抽帧器借用以及 STT 的保护；C15 禁用脚本执行；C16 让两个旧字段入口抛错。C12 边界补修撤回自定义来源的默认探针跳过条件，新测试 1 红，恢复后 1 绿。对应新增测试分别全部变红，恢复后分别全部变绿；没有以删除新公开符号导致的编译失败充当本轮回退验证。

**既有断言与夹具调整**：C12 原 wiring 测试只看 `options.preview.probe == null`，这只能证明配置快照未变，不能证明默认未接线；保留该断言并补查延迟包装器，修正测试名称和过期注释。C13 改写 3 条 STT 断言：启动失败从“必须 rethrow”改为完成并回滚（可选识别故障不应泄漏到播放链）；STT 服务与播放引擎各一条“销毁宿主识别器”断言改为不销毁（借用不能被当成所有权转移）。另有 5 项既有测试在新内核借用语义下暴露原隐含前提：audio_only_scenarios、cutover_warm_mute 两项、playback_error、preview/b07；只给这些夹具显式移交 `ownsKernel: true`，原释放断言保持不变。C15/C16 没有改写既有行为断言；C16 仅迁移既有测试的参数名。

**新增公开 API**（均附中文 dartdoc）：

- C12：`MovaLazyNetProbe`、`MovaEngine.previewProbeFactory` 构造参数、`MovaPreviewService.gateNetwork` 参数/字段。createMovaEngine 默认提供延迟的真实探针工厂；内置 VTT/雪碧图/抽帧到实际远程资源访问处才判断 wifiOnly。缓存、未启用来源、本地资源、VTT 失败冷却不创建或查询默认真实探针。自定义来源接口不暴露实际资源 URL，默认不创建或查询真实探针；仅宿主显式注入探针时保留入口门控。never/always 保持原策略，不改来源协议。
- C13：`MovaAbrConfig.policyFactory`（优先于旧 policy，每引擎调用一次）、`MovaEngine` 与 `createMovaEngine` 的 `ownsKernel` 参数、预览服务的 `ownsCache/ownsProbe/ownsSources` 参数/字段。旧 policy 实例字段仅在 dartdoc/CHANGELOG 公告下版弃用，不加成员级注解。注入内核、HTTP、缓存、探针、来源、抽帧器、STT 识别器均由宿主持有；默认工厂自建内核及默认预览资源仍归引擎所有；可显式移交内核。
- C15：测试入口的 `MovaTestStep`（ready/buffering/position/error/completed 构造器与 after）、`MovaTestKernel.scripted`、普通构造的可选 script 参数。默认普通内核仍完全被动；显式脚本模式自动组合首帧信号，步骤延迟相对上一步，换源和销毁取消旧步骤。
- C16：`MovaMiniHost.mini` 参数/getter、`MovaAdOverlayComponent.ads` 字段；旧 ctl 参数/getter 与 controller getter 保留带 `@Deprecated` 的兼容入口。

**代码核实与计划差异**：

1. 待拍板 5 按用户决定明确推翻“不默认接探针”：connectivity_plus 已是硬依赖，移除 wiring 的过期 tree-shaking 理由；抽帧器仍默认 null。C12 半成品“按远程预览实际请求延迟接入”与内置来源的按需条件一致，保留该实现；复查发现自定义来源可能只读内存，不能凭远程媒体 URL 默认查询连通性，故在 C16 后另补一个 C12 小提交及 1 项测试；默认跳过不透明来源，显式探针仍入口门控，原放行行为保留。
2. C13 所有权实际涉及 engine/wiring 中的内核、HTTP 与抽帧包装，不只表中列出的 abr_config、preview/service、stt/service；按“只销毁自建对象”扩大到这些实际释放点，并提供显式内核移交入口。策略接口没有 dispose，工厂只解决有状态策略的实例隔离，不发明销毁协议。
3. C15 使用 `test_kernel.dart` 的 part 文件承载步骤类型，分发细节不进入公开 API；没有改生产内核和首帧判据。
4. C16 对历史提交 `e5794345` 前后代码核实：mini/ad 组件类名和 `MovaEngineFactory` 当时就已是现名；deprecated_names 中现有类型别名也全部带 @Deprecated。故只补实际遗留成员，不虚构 Swap/Feed 工厂旧名。当前 Dart 和既有测试支持枚举经类型别名访问，修正兼容层与 CHANGELOG 中相反的旧说明。
5. 第 8 节第 17/18 项保持本批已拍板默认：不改 `get(Uri)`；成员级弃用公告策略不变，C16 明确要求的兼容别名除外。

本次续作实测新增 18 项（原预期 17 项，额外一项覆盖不透明来源边界），最终 2269 项通过；从 2234 基线累计增加 35 项。

本批指定的 C01→C02→C03→C10→C11→C12→C13→C15→C16 均已落地；其余 C 块与 C17 总文档收口不在本批。全部行为/API 变化已逐提交记入 Unreleased；未暂存或提交禁列的 generated_plugin、doc/notes、matrix-run 计划和兄弟工程文件。


### 终审修复（2026-11-04）

从 `f0b66780`、2269 项基线继续，仅修复本批终审成立的 3 条 P2 和 C01 测试清理；仍在本 worktree 自行执行，无转派、无真机、无 push，无切分支/stash/reset，未改其他 worktree 或禁列文件。

| 项 | 提交 | 修法 | 新增回归回退红 / 恢复绿 | 提交前全量通过数 |
|---|---|---|---:|---:|
| P2-1 策略拒绝误入 VTT 冷却 | `a38b379d` | 资源包装器抛专用 `PreviewPolicyBlocked`，VTT 透传且不写 `_retryAt`；服务层识别、统一报告网络拒绝并结束当前请求，不当普通获取失败兜底。真实获取失败继续保留冷却。 | 2 / 2 | 2271 |
| P2-2 异步探针后旧请求仍启动 | `ff99adda` | 服务通过 Zone 传递请求代际检查和取消信号，包装器等待探针时可被取消/销毁解除；探针返回后及实际 HTTP/抽帧前复核 `_isWanted`。VTT 透传取消且不写失败冷却；关闭包装器使待执行调用失效，不销毁宿主 HTTP/抽帧端口。 | 12 / 12 | 2283 |
| P2-3 延迟 ready 覆盖播放意图 | 本提交 | 脚本模式单独维护当前播放意图，open 初始化、play/pause 更新，ready 读取最新值；`lastPlay` 仍保留 open 原始参数。被动模式仍只记录命令、不自动发信号，既有被动模式测试增加 play/pause 无信号断言。 | 4 / 4 | 2287 |
| C01 提示测试残留静态标志 | 同上 | 在改动静态标志前登记 `addTearDown`，恢复测试前值，断言失败也执行清理。 | 无新增行为测试 | 同上 |

三条 P2 各自保留测试与类型定义，只撤回对应行为实现进行回退验证，分别实际产生 2、12、4 项断言失败，不以删除符号导致编译失败充数。恢复实现后通过；共新增 18 项，2269 → 2287。C01 属测试隔离清理，保留原提示次数断言，不另加模拟清理实现的测试。

回归范围：策略项覆盖蜂窝拒绝后 Wi-Fi 立即恢复、雪碧图拒绝到服务层结算且不继续普通失败兜底；取消项覆盖 VTT 轨/雪碧图/抽帧三条路径分别在 cancel、换源、dispose 后不启动旧资源请求，另覆盖同桶新代际无需等旧探针、两类包装器直接调用时销毁失效；播放意图项覆盖播放 open 后 pause、暂停 open 后 play、以及两种反复切换。

每笔提交前 `flutter analyze lib test` 均为 0 issues；所有 `flutter test` 使用 `--concurrency=2`，每轮开跑前执行指定 flutter_tester 清理。验证期间反复出现随机旧套件的 `Connection closed before test suite loaded` 或 `did not complete`，单独复核通过，未通过删测试、改断言或增加 skip 处理。第一笔最终单轮全量 2271 绿；第二笔改为四分片串行执行（`--total-shards=4 --shard-index=0..3`），仅重跑加载中断的失败分片，最终四片 599 + 594 + 549 + 541 = 2283 全绿；第三笔最终单轮全量 2287 绿。

CHANGELOG 已补三项行为变化。功能范围无偏差；请求身份与控制信号均在内部传递，宿主来源、HTTP 和抽帧端口签名保持原约定。执行偏差仅为测试环境加载中断造成重试及第二笔改用串行分片，未降低指定并发或遗漏全量覆盖。
## C04 落地记录（2026-11-04）

本次从 detached HEAD `f0b66780`、2269 项基线开始，由主会话亲自执行 C04a → C04b → C04c → C04d，每个 Task 验证后立即提交；只修改本 worktree 的 mova 目录。按会话要求不改 CLAUDE.md，不转派、不 push、不切分支、不 stash/reset，不启动应用、不做真机验证。

| Task | 提交 | 新增 | 回退红 / 恢复绿 | 提交前 flutter test 实测 | analyze |
|---|---|---:|---|---:|---|
| C04a | `316a2f11` | 8 | 8 / 8：移除状态机行为的兼容空壳 | 2277 | 0 issues |
| C04b | `98e1f9be` | 8 | 8 / 8：关闭连接能力 | 2285（215 文件） | 0 issues |
| C04c | `8c96f4d2` | 11 | 11 / 11：回退绑定及组件迁移；另单独移除纪元判断，换指用例 1 红 | 2296（217 文件） | 0 issues |
| C04d | 本记录同提交 | 5 | 5 / 5：拖动与续期 3 红；常显及旧路径空操作 2 红 | 2301（218 文件） | 0 issues |

**落地行为与兼容性**：MovaChrome 管理每视图控制条、HUD、拖动和预览；桥接引擎默认每个 MovaPlayer 创建一份，借入实例只绑定/解绑，宿主负责销毁。换 API 保留适用的 chrome 实例并重新播种，换 chrome 时组件按 `(api, chrome)` 重挂订阅。旧 UI 动词有视图时广播，旧读者镜像以后写者为准；无视图时继续原计时与就绪路径。非桥接 MovaApi 默认沿用旧接口，显式传入 chrome 可启用独立交互态。拖动期间强制可见并暂停自动隐藏，松手重新计时；控制栏按下和按钮指针、键盘、语义激活会续期，隐式悬停/焦点/快捷键唤出保留常显标记。

**公开 API**：新增 `kMovaHudDuration`；导出 `MovaChrome`（ValueListenable、value/uiState/uiStates、show/hide/toggle/showHud/setDragging、maybeOf/of、dispose、touch）；新增 `MovaPlayer.chrome`。新增入口和成员均有中文 dartdoc。`MovaApi` 零新增成员；MovaEngine/MovaCutoverEngine 的 `uiReady/linkUi` 实现包内 MovaUiBridge，桥及连接集合不从公开入口导出。六个旧 UI 成员只补 dartdoc 与 Unreleased 公告，不加成员级 @Deprecated；core 不导入 Flutter，purity_test 原样保留。

**既有断言改写：0**。view_test 仍保留 C03 对样式节的保守重建断言，本次不做 C06；旧核心及非桥接 UI 断言原样运行。子计划 C04d 断言 5 若把键盘聚焦也计入“按钮交互”，原有 B16 聚焦唤出就会产生一次 showControls；新增用例分别验证指针激活零新增调用、聚焦后的键盘激活不增加调用，未删除原行为。

**与子计划的差异及验证方式**：

1. 计划基于 `7275bd5c` 的行号已失效；按当前符号定位，保留第一批 engine/cutover/player/view 改动。A28 已在换指时重放影子 MovaReady，照抄“每次 Ready 都显隐”会重新显示已隐藏控制条。本次在 chrome 按 renderEpoch 跳过该次初始化，额外用独立回退确认，不改 `_commitNow`。
2. 引擎和代理共用包内纯 Dart 连接集合，统一广播、镜像、首连/末次断开及同步关闭；无视图旧路径未改。按钮可能像 B16 测试那样独立挂载，不存在 MovaScope，因此激活续期用可空的 chrome 查找；指针与语义激活也覆盖续期。
3. 初次基线 2262 绿、7 条因 `.dart_tool/b09` 父目录缺失失败；只预建忽略目录，无测试断言改写。C04a 标准单轮全量 2277 绿。此后标准长轮次随机出现“Connection closed before test suite loaded”或“did not complete”，无相应断言栈；曾观察到评审 worktree 同时有 tester，但因果未确定。VM service 试跑也有中断；实验快测模式报告忽略 concurrency 且路径解析失败，已弃用，其结果不计验证。
4. C04b 起使用完整 `rg --files test -g '*_test.dart'` 清单分批串行运行，每批都执行 `Get-Process flutter_tester -ErrorAction SilentlyContinue | Stop-Process` 后 `flutter test ... --concurrency=2 --reporter expanded`；中断批次在源码不变时重试，真实断言失败立即停止。清单核对无遗漏，汇报数量取每批成功轮的实测和，不把中断或编译错误算作功能红测。analyze 与完整清单测试串行；每提交均为 0 issues + 全部文件通过。各批日志、清单及累计结果保存在忽略的 `.dart_tool/c04*-results.json` 等本地验证产物中。
5. 同步/异步测试按实际 Stream.multi 与 widget 测试时钟推进：流关闭在真实异步区核实，代理提交和取消订阅用 pump 与真实微任务交替推进，避免假内核测试等待自己的暂停时钟；既有测试不改。

C04 实测新增 32 项，从 2269 增至 2301。C04a–C04d 代码、回归、公告及记录均落地；CP3 真机/Windows 应用验证按会话约束未做，C05/C06/C17 不在本次任务范围。锁定、缩放、fit 等 MovaState 仍共享，旧镜像多视图以后写者为准，均为计划保留的限制。未暂存或提交 generated_plugin、doc/notes、matrix-run 计划或兄弟工程文件。


## C06 落地记录（2026-11-04）

按用户要求由主会话亲自执行、不转派，合并为两次功能提交；不改 CLAUDE.md，不启动应用、不做真机验证。

### 提交 1：C06a + C06b + C06c（4f3f7410）

- 新增 MovaPlayerStyle（五节 ThemeExtension、copyWith、离散 lerp、值相等与五个 xxxOf 查找口）、MovaDanmakuStyle（五字段、fromConfig/applyTo）；MovaPlayer.style / MovaView.style；MovaStrs 新增 14 个字符串字段与 labelWithValue，新增 movaDefaultLabelWithValue。新增公开入口均附中文 dartdoc。
- 当前基线 UI 实际 59 处样式读取全部迁移（旧计划为 56 处；加 core 三处共 62 处，而非旧表 59）；保留 engine.dart 三处无视图兼容读取。内置按钮显式传入标签；旧第三方按钮仍保留图标反查回落。弹幕仅迁移样式，enabled/items 及条目引用保留。控制条在依赖更新时重读样式；只有配置真正变化才更新挂起计时，不让无关重建续期。
- 新增测试 19（类型/查找链 8、视图 5、源码守卫 1、文案 5），保留类型和测试，对查找、消费、默认值及值对象契约做行为回退/变异后实测 19 红，恢复 19 绿。比子计划的前三 Task 18 项多 1：自动隐藏和快捷键拆为独立用例。真实引擎切主题 10 次，缓冲颜色更新，open/MovaSourceChange 只有一次，renderEpoch 不变。
- flutter analyze lib test：0 issues。全量只运行一次，--concurrency=3：2331 通过、7 失败（b09_test.dart 的 .dart_tool/b09 父目录缺失，全部为 setUp 失败）；建立工作区测试目录后只重跑该文件，7/7 通过，完整清单合计 2338 项全部覆盖。没有 OOM、没有加载断连、未降并发或分片重跑全量。
- 实测总数与用户标注基线 2301 存在 18 项差额：2338 - 新增 19 = 2319；未额外运行基线，不能把 2319 记为另一次基线实测。以本次实际日志计数为准。
- 既有断言改写：0。core 清晰度兼容中文常量按会话批次划分留到提交 2；界面已改读文案。Deprecated 只做 dartdoc 与 CHANGELOG 公告，无成员级注解。

### 提交 2：C06d + C06e（本记录同提交）

- MovaOpts.engineSectionsEqual 仅比较 preview/live/abr/stt/cutover/report/recovery/keepAlive，排除五个样式节及 C03 已排除的三类宿主配置。MovaView 以最新 options 下发兼容回落，保留引擎 options 构造快照；闭包、弹幕列表更新只改视图。
- 清晰度中文提为公开常量 kMovaAutoQualityLabel / kMovaUnknownQualityLabel；值仍是“自动/未知”，UI 已走 MovaStrs，下个版本改中性值只做公告，本次不破坏宿主自绘标签。
- 新增公开 API：MovaIcons（20 个 IconData 字段、const 构造与值相等），MovaPlayerStyle.icons / iconsOf 及对应构造、copyWith 参数，MovaTheme.progressColor（int?，null 保留宿主 SliderTheme）。颜色覆盖 activeTrackColor/thumbColor。图标覆盖 chrome，feed 社交及抖音点赞动画按原定范围不在集合中，并非裁剪。
- 20 个图标字段：pip、quality、aspectRatio、rotate、enterFullscreen、exitFullscreen、lock、unlock、subtitles、subtitlesOff、speed、backToLive、play、pause、volumeOff、volumeUp、brightness、retry、check、closeMini。所有新增公开入口均有中文 dartdoc；core 未引入 Flutter，MovaApi 零新增成员。
- 新增测试 10（五个样式节各 1 + 内联闭包/弹幕列表 1、图标/进度颜色 3、清晰度兼容常量 1），保留类型和用例做行为回退/默认值变异后 10 红，恢复 10 绿；没有用删除类型造成编译失败充数。相比子计划 C06d/e 的 5 项多 5：逐节验证增加 4，常量兼容验证增加 1。
- 唯一一次全量 flutter test --concurrency=3：2348/2348 通过。全量后复核默认兼容性，给既有新增默认图标用例补了“回到直播：回到直播”原有完整提示断言，先实测 1 红再修复为显式 labelWithValue；只重跑受影响文件（icons/strings/bottom_bar 合计 11 项通过，live_bar 7 项通过）。其中一次命令误写不存在的 live_controls_test.dart，11 个实际用例均通过，纠正路径后只补跑 live_bar_test.dart；这不是随机加载断连。未再次跑全量。
- flutter analyze lib test：最终 0 issues；全量与 analyze 未并行。每次测试前清理 flutter_tester，所有测试使用 --concurrency=3；无 OOM、无随机加载断连、未降并发、未分片重复全量。

### 既有用例改写与最终差异

- 既有用例改写 1：view_test.dart 的 changed options 用例，触发配置从 theme.accentColor 改为 preview.frameWidth=99；原有“两个引擎、旧引擎已销毁、新引擎重开原 URI”三条断言逐字保留。旧触发项把主题变化当作引擎配置变化，C06 后这一前提不成立。没有削弱重建行为验证。
- 提交 1 的 MovaStrs 新增字段完整列表：play、pause、pip、aspectRatio、rotate、enterFullscreen、exitFullscreen、lock、unlock、subtitles、speed、action、closeMini、unknownQuality、labelWithValue；默认格式函数为 movaDefaultLabelWithValue。MovaPlayerStyle 最终共六节（前五节复用旧类型），MovaDanmakuStyle 仅五个展示字段。
- 累计新增 29 项，每条均有红绿证据；子计划原估 23 项，本次细拆覆盖多 6 项。完整清单从第一批 2338 到最终 2348；与会话标注 2301 基线相差的 18 项仍按第一批说明保留，不倒填基线实测。
- 偏差：真实读取为 UI 59 + core 3；清晰度 core 常量按用户分批要求放提交 2；回到直播提示兼容修正在提交 2 完成。弃用仅 dartdoc + CHANGELOG，无成员级 @Deprecated。
- 裁剪项：无。C06a–C06e 全部落地；CP3 真机/应用验证按用户约束未执行。MovaView 引擎 options 保留构造快照、弹幕 enabled/items 仍在旧配置、无桥接 API 的 chrome 行为仍走旧路径，均为兼容设计。
- 未修改 CLAUDE.md；不 push、不切分支、不 stash/reset；未暂存或提交 generated_plugin、doc/notes、matrix-run 计划与兄弟工程。
