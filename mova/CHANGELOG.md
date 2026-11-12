## 0.4.1

- 全量评审暂缓 P3 收口（非真机部分）：小窗与全屏/系统 PiP 双向互斥（PiP 中 `setMini(true)` 被拒、`MovaMini.show` 随之撤销交接；进入全屏先收起小窗）；格式探测推迟到真正 open 前武装（END_FILE 起始闸门方案经真机 A/B 证明会让 HE V9 前后台续播 5 次只过 1 次，已撤销，B1 仍待原生文件身份）；待机还原失败保留原值并在下次重试；中插预热期间正片真正播到片尾时不再吞结束事件（换指副产物的结束事件仍被吞）；看门狗期限尊重源级 `network-timeout`；`stallMs` 只计策略接受的卡顿（抖动归还观看时长）；亚秒预览桶用毫秒缓存键；音频抽取失败/取消后删除残留 WAV。测试基线以当次 `flutter test` 为准。

- 全量评审 P3 修复（40 条中修复 22 条，9 条已不成立，9 条暂缓）：异步 beforeSeek 乱序返回不再覆盖新 seek；DVR 回直播边缘不残留旧 seek 过滤；内部补发 seek 失败按非终结错误上报并解除过滤；迟到的初始音量不覆盖用户设置；cutover dispose 立即释放已认领影子，换指前补齐最新倍速；已销毁的 MovaPlaylist 导航不换源；内核按源选项事务串行化，dispose 等待原生准备有上限；隐藏期间改守卫配置即时生效；QoE 用户暂停期间不计卡顿、注入卡顿策略按会话重置；STT 模型与字幕缓存原子写入并校验下载尺寸；预览缓存 key 区分请求头（无请求头时不变）、关闭预览时缓存不绕过开关、VTT 非法裁剪降级整图；拖动 seek 预览与提交共用起点；字幕按钮按实际运行状态显示；小窗换引擎时重算几何。

- 请求头与事件交付修复：同一 URL 被两个引擎（正片与 cutover 影子、feed 池）或重试以不同请求头打开时不再串用对方的头（每次加载使用独立的 media_kit 缓存键，fragment 不发往服务端）；`http-header-fields` 解析失败时不再静默清空请求头，改为经诊断流报告；同步事件监听器在 `MovaDone`/`MovaSourceChange` 等回调中换源后，旧源的直播结束、待机降级、Ready、清晰度探测等后续逻辑不再执行，被 `beforeOpen` 拒绝的 open 不影响在途换档与恢复；`screenshot()` 播放中也在 2 秒总预算内重试，cutover 外层兜底 3 秒；`MovaFeedPlayerController.pause()` 不再等待激活完成，也不再抛出激活错误。

- 终审附注修复：cutover 提交窗口内后到的 `play()` 也会下发给即将转正的影子，转正后状态与最新播放意图一致；宿主广告回调抛出的异常除日志外交给当前 Zone 的 `handleUncaughtError`，可进入宿主崩溃收集，且不中断广告与续播；URL 时移在暂停期间落后量随时间增长，恢复播放后保留、回直播边缘清零，`seekBy` 与重试按包含暂停时长的落后量计算。

- 全量源码评审修复（P1/P2 共 27 条）：宿主直接 `open()` 换源时旧广告会话让位、不再抢回原源；事件流有暂停订阅时 `dispose()` 不再卡住；换档加载期间的新 seek 不被覆盖；重播/待机等待后尊重期间的暂停；终结错误取消排期中的恢复重试；退出全屏保留强制方向（仅 `auto` 还原宿主方向）；HLS 档位视频优先排序，ABR 不降到纯音频档；cutover 换指前复查播放意图、影子 fatal 不转正；feed 激活失败不阻塞最新页、预取按字节预算截断；QoE 尊重引擎 `fatal/code`，手动起播只由首帧落地且不上报 TTFF；STT 模型 id/文件名路径校验；小窗、全屏路由、抽帧器生命周期竞态，组件补丁按名取子节点，进度条跟随实际被接受的 seek，小窗甩出按轴判定。

- 修正 CP3 headers 总判据：开启 `CP3_HEADERS_READY` 时以普通/cutover 有界截图验收，旧原生 `pool` 截图保留为诊断；清晰度保存完整档位及选档原生 path，要求 auto 与 360p 变体、地址和拒绝对照均正确。须构建新 APK 复验，旧 FAIL 不回写。

- headers 夹具新增 `CP3_HEADERS_READY`：独立普通/cutover 暂停池实例在 bind 返回后立即使用有界截图能力，统计授权截图 null 与实际图片解码成功次数，保留拒绝鉴权及原始截图对照。须构建新 APK 复验。

- 修正第五轮暂停池截图等待不足：`MovaFrameCapture.screenshot()` 普通与 cutover 的总预算统一为 2 秒（含原生截图及编码），不再以 rendered 门控截图；空结果按 50ms 起、递增至 250ms 的间隔重新调用内核，实际非空图片才算成功。超时/失败仍返回 null；`CP3_HEADERS_READY` 的 null=0/30、解码成功=30/30 判据保持不变，须新 APK 复验。

- 新增可选 `MovaFrameCapture.screenshot()`，普通与 cutover 引擎均支持；暂停预热在总计 2 秒内等到非空截图才完成，超时/失败返回 null，切源、销毁或切换后的旧结果丢弃。不播放、不 seek，MovaApi 不增加成员，池 bind/ready 与原首帧事件保持原语义。

- 预览抽帧首次 seek 落地等待超时后自动重发一次 seek 并重新确认落点；再次超时仍返回 null，不截取未确认帧。duration 就绪超时和截图失败保持返回 null。

- 池预热探针增加暂停画面的非空截图证据及首帧信号来源，避免把 size/grace 兜底当成实际解码成功。

- headers 抽帧夹具保留首次空帧/字节数/耗时与异常分类，保留正负鉴权归属，不用自动重试覆盖偶发失败。

- 资源夹具不再跟随动态 fd 链接，独立读取线程/fd/CPU 并记录错误；补充并发翻页及释放后 0/1/5 秒的阶段采样，不将逻辑池归零当作原生资源回收证明。

- 回执夹具不再将 Seeked 载荷与独立节流 progress 流硬相等，单独保存三种位置读数并明确不代表原生落点验收；Size/Quality 状态一致性判据保留。

- 普通 MovaEngine 在更新状态后同步交付状态事件，修复连续尺寸通知、清晰度探测后立即手选时事件载荷与接收时 state 不一致；嵌套事件排队交付，错误与恢复失败通知保留异步边界。

- headers 池预热夹具改为挂载真实画面并等待精确首帧/媒体元数据或错误，保留 accepted 与解码结果及原生读回，正负对照均完成后再取 HTTP 回执。

- 补齐 example 的 SRT 资产声明，四格式字幕夹具均使用包内素材；须重新构建 APK 复验。

- 修复播放媒体在 media_kit 加载钩子中丢失源请求头的问题，切源后清除上一源的头。
- 修复 feed 翻页激活收尾重新播放、覆盖宿主控制器暂停的问题。
- 修正矩阵证据门禁：无关命令错误不再污染每一行，但整轮完整性错误仍阻止通过；区分旧 BLOCKED 首次失败与 PASS 回退。
- 修正倍速同值去重及引擎池实际数量的验收判据。
- 修复 CP3 字幕资产、feed 池数量、底栏直播/DVR 挂载前提及无声流暂停策略、STT 启动前提及事件相关字段回执夹具；需新 APK 复验。

- 澄清 CP2 验收契约（无产品行为变化）：pod 仅等待型广告要求换指、renderEpoch 递增；nowait 在当前引擎直接 open。广告位计时按首帧后的有效墙钟及 playing 边沿冻结，不能用最后一次媒体位置代替剩余时长；依据和夹具修法见 [离线定性](doc/plans/2026-11-05-cp2-r4-offline-triage.md)。
- 修复等待型中插预热期间丢弃仍在播放的正片进度，导致广告后重复播放预热等待时段；MP4/HLS 续播点持续跟随正片到换指前。
- 修复刚完成 setRate 就即时插播时代理快照滞后，导致广告后丢失用户倍速；广告期间仍为 1x。
- Feed 打开失败时保留当前页和重试入口；宿主在内置守卫暂停期间显式 pause 会取消自动恢复，后续 play 仍按可见性策略处理。
- 点播首帧前失败的自动重试和同内容备用地址保留 source.start；出画后仍使用失败续播点。
- fullscreenRoute 开启时内联侧在路由挂载期间让出子树，避免宿主 surface/poster 的 GlobalKey 重复挂载；默认关闭路径不变。

以下为仓库 0.4.0 之后的行为与迁移记录；尚未以新版本发布。按功能归并保留最终契约，
逐提交测试数字见统一编排总计划与 CLAUDE.md，不在此累计。

### Breaking / Deprecated 迁移摘要

- `state.error` 只含终结错误；完整诊断改监听 `MovaErrorEvent.fatal/code`，恢复决策看 `MovaPlayFailure`。
- `MovaAds.load/loadDeferred` 返回 `Future<bool>`；只 await 的调用不变，覆写者同步签名；完成微任务时序不变，Future<bool> 可用于原 Future<void> 调用点。
  `MovaApi.open` 已在 0.3.1 改为 `Future<bool>`，自定义 API 也需同步；false 是拒绝/过期/销毁，不能当播放失败。
- 旧命名 typedef 及 `MovaMiniHost.ctl`、`MovaAdOverlayComponent.controller` 保留带 @Deprecated 别名；
  没有别名的动词/具名参数须按下方改名表迁移。
- 下版弃用公告（本版不加成员级注解）：旧 UI 动词/镜像改 MovaChrome，旧样式字段改 MovaPlayerStyle，
  MovaAbrConfig.policy 改 policyFactory。STT 主入口仅保留一个版本的转导出，改 import stt.dart；
  导出级内部 helper 下版隐藏，MovaApi.stt 保留。

### 会话、广告与换指

- 新增 movaCapabilityOf<T>(api) 能力查询入口，优先保留代理自身能力，否则穿透多层 cutover 查询当前生效引擎，不修改 MovaApi。

- 宿主抢源导致会话让位时，为已开始的原节点补发一次 MovaNodeEnd(superseded)，保持原 epoch，不报告节点失败，也不放弃宿主新影子。

- 会话重新 load、jumpTo、setItems 或销毁时取消自己持有的预热凭据，连已认领、等待旧引擎暂停的事务也释放影子并禁止换指；宿主的新影子不受影响。

- 影子换指补发生命周期事件时，宿主回调抢源立即停止旧补发，凭据提交返回 superseded，会话让位；旧引擎仍正常释放。

- 会话落地窗口按媒体归属缓存终结失败；即使 recovery giveUp 后 open 正常返回，仍结算广告失败或正片 contentError、MovaNodeFail 并回 idle。

- MovaPlaylist(ads:) 的 NextUp 仅在正片会话节点显示，进出广告及转场时立即隐藏旧卡片；旧直连播放列表保持原判据。广告覆盖层直接读取控制器 canSkip/skipIn，避免 pod 落地窗口的旧进度提前显示跳过按钮；倒计时按微秒精度向上取整。

- 新增 MovaAdConfig.midRollSnapback：同一进度 tick 跨过多个不同中插点时，可全部补播（默认 all）、仅补播最后插入点的完整 pod（last），或全部略过并记为已播（none）；单个到期插入点及同点 pod 保持正常播放。

- 切换代理在换指窗口保留旧引擎播放观测，抑制内部暂停事件；换指后依次补发影子期 SourceChange、Ready、FirstFrame，放弃时补回真实状态。MovaCutoverChange 新增可选 reason。代理状态与事件通过带渲染 epoch 的同一队列投递，事件接收时 state 与载荷一致，修复 H77 的缓冲状态滞后。

- 广告 pod 的每条等待型广告改走 prepare + 凭据提交，统一采用广告方向计划（默认 1x、就绪后停首帧、adReadyTimeout）；被宿主新 open 取代时会话让位，槽被替换时只按未就绪回落。落地窗口丢弃旧媒体的结束、错误与进度，正片预热同时考虑广告位和素材剩余时长。公开 cutoverTo 保留。

- 会话对同一 epoch、节点和尝试的失败只裁决一次：广告仍由广告失败策略处理，recovery 开启时非终结诊断交给引擎；正片终结错误（恢复开启时等待 giveUp）发出 MovaNodeFail(failItem)、contentError 并回 idle，不自动换集。contentError 同时包含解析失败、正片 open/切换异常和终结失败。
  Fix：广告的 cutoverTo、prepare、commit 抛出与直接 open 异常统一进入广告失败策略；直接广告 open 被宿主拒绝时跳过且不重试。正片打开/切换异常经 `MovaAds.contentError` 上报并回到 idle，宿主拒绝与过期加载不报错，不发 contentEnded。

- 会话自动连播消费结束通知时校验 epoch，手动换集不再被旧通知覆盖；替换列表使在途跳转失效，广告共享列表下标及 indexChanges 跟随会话导航。跳过加载中的前贴片时，加载结果等待同一 epoch 的续播请求结算。

- `MovaPlaylist(api, ads:)` 共享会话，换集携带按集广告，自动连播等待全部后贴片；此路径遵守 `playlist.enabled`，旧直连构造保持原行为。

- 会话新增带纪元与节点身份的事件；按节点独立记录广告，修复 pod 中同参数 const 广告被合并的问题。广告钩子同步重载同一节点时，旧结束入口不再误续播新尝试。

- 新增 `MovaSession` 多条目、按集广告与加载结果，直接构造自动识别已启用的切换能力；`MovaPlaylistItem.adBreaks` 可覆盖排期，`MovaAds.session` 提供共享访问口。

- 修复被后继切换取代的内部暂停污染播放意图；等待型广告通过包内能力传递显式起播意图。广告首次打开在钩子中失败后，重试保留本次加载意图，并让位于之后的用户播放或暂停命令。

- 换指及广告续播继承用户播放意图，暂停后跳过广告不会自动开播；自定义 engineFactory 引擎须维护 playbackIntent，意图恒假时换指后保持暂停。

- 广告位与中插倒计时改用可暂停时钟：观测到播放暂停后不计入广告时长；`delayRemaining` 按同一时钟计算，加载首帧期限仍使用独立墙钟。

- 广告失败策略和影子放弃预热仅响应 `MovaErrorEvent.fatal == true`；非终结内核日志不再中断广告或预热，原有尝试去重及 cutover 接受结果契约不变。

- Fix：引擎就绪后默认自行探测 HLS 清晰度（`MovaAbrConfig.probeVariants: true`）。同一会话的自动与显式探测共用一次请求，迟到结果更新列表但不覆盖手选档；可关闭自动探测，由宿主显式调用。auto ABR 接管仍未开启。

- Fix：广告 pod 内后续广告失败继续推进。续播与失败按每次尝试去重，Timer 与素材结束不会重复推进；cutover 通过包内可选能力区分宿主拒绝，影子被拒立即释放，广告被拒跳过且不进入重试，也不再把旧正片画面当广告首帧。

- Fix：cutover 提交事务独占换指权。并发提交排队后重新校验槽，`cutoverTo` 只提交自身预热的槽；目标帧保持失败不阻断提交与释放，槽清理异常也保证释放生效引擎并关闭流。

- Fix：回正片期间使用独立过渡相位，旧广告进度、结束事件及即时插播不再误触发正片排期或改写续播位置。

- Fix：cutover 用内部操作代际隔离换源、重载与并发切换；提交只释放已认领的预热槽，保留较新 prepare 的资源与相位，过期切换不再回落抢源。

- Fix：直播影子预热不再要求追上正片位置，正片播得越久越容易降级成非无缝切换的问题。直播影子从直播边缘起播且从不 seek，位置从 0 开始，而 `MovaBufferWarm` 要求影子位置 ≥ 目标位置 − 容差，所以就绪时间≈起播延迟+正片已播位置；正片先播 7s 的变体 10/10 在 8s `readyTimeout` 处放弃预热（真机 STG-AL00 实测）。现在 `MovaWarmSignal` 新增 `live`（默认 false，自定义判据不受影响），`MovaBufferWarm` 对直播视为已到达，仍要求无卡顿 + 提前缓冲 ≥ `lookahead` + 连续 `stableTicks` 次；点播与未带 `live` 的信号行为不变。真机：正片先播 500ms/3s/7s/15s/30s 全部通过（B/C 各 5–10 次），影子就绪耗时稳定在约 3–4s、不再随正片位置增长，`readyTimeout` 仍是 8s；详见 doc/plans/2026-10-29-q13-live-warm-fix-verification.md。

- Fix：`dispose()` 之后各动词不再转发给已销毁的内核。此前 `pause`/`setVolume`/`setRate`/`switchQuality` 等在销毁后仍会调内核，真实 media_kit 会抛 `AssertionError('has been disposed')`（真机复测日志里的 `[Player] has been disposed` 未捕获异常可能同源）。现在 `MovaEngine`/`MovaCutoverEngine` 的所有公开动词在已销毁时静默返回（不抛、不发事件、不碰内核与端口），异步动词在 await 回来后也会复查；`MovaCutoverEngine` 销毁后的 `prepare`/`cutoverTo` 也不再新建影子引擎。

- Docs/验证页：HE V6 验证脚本修正续播窗口锚点（旧写法恒匹配会话最初首帧，曾把"V6 续播失败"误判为库缺陷）；Android 真机 V6 复测 5/5 通过，续播误差 0–40ms。覆盖测试结果见 `doc/plans/2026-10-27-device-coverage-results.md`。

### 视图、样式与宿主组件

- MovaPlayer 新增 fullscreenRoute（默认 false）：开启后由应用根路由展示全屏，返回键先退出全屏，锁定时用 MovaStrs.unlock 提示解锁。路由借用同一 API、自建独立 chrome、不重复探测清晰度，退出唤出内联控制条；样式继承 MovaPlayerStyle 与旧配置回落，方向还原和 PiP/mini 仍由引擎管理。全屏路由携带后台守卫归属，自有遮挡不触发暂停；Windows 内联及路由的自定义 surface 也经过 MovaSnapshotGuard。关闭时保留原有播放器树与行为。

- MovaView 仅在引擎实际消费的配置节变化时重建；主题、文案、手势、控制条及弹幕节变化通过视图更新，保留引擎、打开次数和播放状态。最新 options 作为兼容回落值下发，内联文案闭包与弹幕列表不再触发重建。
  MovaView 通过 MovaOpts.engineSectionsEqual 比较构造配置，忽略宿主 ads/playlist/mini 节变化；UI 样式节从 C06 起通过视图更新；debug 下连续 10 帧实际配置不等时每视图提示一次。

- 新增 MovaIcons 与 MovaPlayerStyle.icons/iconsOf，可按视图或主题扩展替换 20 个控制界面图标（不含 feed 社交按钮）；无障碍标签继续由文案明确提供。MovaTheme.progressColor 可配置进度高亮与滑块颜色，默认 null 沿用宿主 SliderTheme，默认图标保持不变。
  清晰度自动/未知兼容标签提为 kMovaAutoQualityLabel/kMovaUnknownQualityLabel，保持旧值并公告下个版本改为中性值。
  新增 MovaPlayerStyle（ThemeExtension）与 MovaDanmakuStyle，MovaPlayer/MovaView 支持 style。主题、文案、手势、控制条行为与弹幕样式按节依次查找：视图参数 > 主题扩展 > 旧 options > 默认。切换主题更新缓存皮肤及控制条配置，不重建引擎；弹幕开关与条目仍来自 options。
  按钮无障碍名称、提示及清晰度“自动/未知”展示改读 MovaStrs，新增可替换的动作文案与 labelWithValue 格式函数；内置按钮显式传标签，默认文案不变。MovaQuality 的旧中文标签本版本保留，下个版本计划改为中性值。

- Deprecated（公告，下个版本加注解）：MovaOpts.theme/strings/gesture/controls 及 danmaku 的样式字段计划弃用，改用 MovaPlayerStyle；旧字段本版本继续作为回落值，不添加成员级 @Deprecated。

- Deprecated（公告，下个版本加注解）：MovaApi.showControls/hideControls/showHud/setDragging/uiState/uiStates 计划下个版本弃用，改用 MovaChrome；旧动词向所有挂载视图广播，旧镜像取最后变化的视图。锁定、缩放、fit 等 MovaState 仍由引擎共享。

- 改名收尾：`MovaMiniHost.mini` 替代旧 `ctl` 参数/字段，`MovaAdOverlayComponent.ads` 替代旧 `controller` 字段；旧入口均保留带 `@Deprecated` 的别名，构造与渲染行为不变。包内调用和示例迁移为现名。核实工厂早已共用 `MovaEngineFactory`，已有类型别名均已标注弃用；修正文档中“枚举值不能经 typedef 访问”的过期说明。

- 修复嵌套不同 API 的 MovaAutoPause 遮住外层守卫的问题；MovaPlayer 按 API 查找完整祖先链，尊重外层配置的后台继续播放。

- MovaPlayer 的视频后台暂停改经引擎执行，钩子、播放意图与广告时钟均可观测，命令式 keepAlive 也由引擎结束待机；默认切后台仍暂停、回前台不自动续播。无渲染面的 audioOnly 不受影响；要后台续播，可用同一 API 的 MovaAutoPause(config: MovaAutoPauseConfig(background: false)) 包裹播放器。

- Fix：`probeVariants: false` 关闭引擎和默认 MovaPlayer / MovaView 的所有自动探测。UI 自动入口须同时满足 `autoLoadQualities && api.options.abr.probeVariants`；`autoLoadQualities: false` 仅关闭该 UI 入口，显式 `api.loadQualities()` 不受两者影响。

- Feat/Fix：按钮默认可聚焦并带语义、tooltip 和聚焦提示；鼠标悬停唤出控制条。`MovaCtrlsConfig.shortcuts` 默认 false，启用后聚焦播放器可用空格播放/暂停、左右键跳转十秒、上下键调音量、F/Esc 全屏操作；锁定、PiP/mini 和文本输入不处理播放器快捷键。

- Perf：位置标签按秒更新，MovaPlayer 缓存静态组件及构建子树；重复的标量状态镜像不再发事件，dispose 在首个 await 前取消 HUD 和控制条计时器。

- Fix：竖滑灵敏度生效，patch 路径错误在 debug 下断言；锁定按钮进入组件树并跟随控制条显隐（锁定时保留解锁入口），选项弹层支持滚动。

- Fix：自动暂停守卫豁免全屏；系统 PiP 状态广播仅回流到发起进入的引擎，失败后撤销接收资格。

- Breaking（命名）：去掉 `*Controller` 后缀，standby 改名 keepAlive，swap 改名 cutover（纯改名，行为不变）。
  * 类：`MovaAdController`→`MovaAds`、`MovaFeedController`→`MovaFeed`、`MovaPlaylistController`→`MovaPlaylist`、`MovaMiniController`→`MovaMini`、`MovaSwapController`→`MovaCutover`、`MovaStandbyController`→`MovaKeepAlive`。
  * `Swap*`→`Cutover*`（`MovaSwapEngine`/`Config`/`Change`/`Phase` 等），`Standby*`→`KeepAlive*`（`MovaStandbyConfig`/`Phase`/`Mode`/`Reason`/`Change`/`Resume`、`MovaSilentStandby` 等）。
  * 成员：`MovaState.standby`→`keepAlivePhase`（类型 `MovaKeepAlivePhase`）、`MovaOpts.standby`→`keepAlive`、`MovaOpts.swap`→`cutover`、`MovaHiddenMode.standby`→`keepAlive`、`setStandby`→`setKeepAlive`、`swapTo`→`cutoverTo`、`MovaAdController(swap:)`→`MovaAds(cutover:)`。
  * 文件/目录：`core/standby/`→`core/keep_alive/`、`core/swap/`→`core/cutover/`、`ad_controller.dart`→`ads.dart` 等（只影响直接 import `package:mova/src/...` 的代码；经 `package:mova/mova.dart` 导入不受影响）。
  * 兼容层：旧类名以 `@Deprecated` typedef 保留一个版本（`lib/src/deprecated_names.dart`），`MovaState.standby`、`MovaOpts.standby`/`swap`、`MovaHiddenMode.standby` 也保留 `@Deprecated` 别名。没有别名的：改名的方法/具名参数（`setStandby`、`swapTo`、`MovaOpts(swap:/standby:)`、`copyWith(swap:/standby:)`、`MovaAdController(swap:)`）——这些需要按上面的对照改。
  * 上报 payload 的键 `swapEnabled`（QoE 会话字段）保持原样，未改名。

- Fix：进系统 PiP 后 App 内小窗不收起（真机覆盖复跑 A15/F5）。`enterPip()` 会把 `MovaState.mini` 置回 false，但 `MovaMini` 控制器不知情，小窗仍挂在界面上。现在 `MovaMini` 监听被借用 api 的状态，api 自行退出小窗态时同步撤掉小窗。

### 预览、Feed 与资源归属

- 新增 skin.dart、ads.dart、feed.dart、mini.dart、extend.dart 分入口及独立 stt.dart；mova.dart 本版继续导出原有全部符号。STT 主入口转导出仅保留一个版本，MovaApi.stt 保留；模型下载仍为实验实现。内部 helper 在导出级公告下版隐藏，本版不新增成员级 @Deprecated，运行行为不变。

- MovaFeedPlayer 新增宿主持有的 MovaFeedPlayerController，可查询 feed/当前索引/当前引擎、跳页和播放暂停，换控制器及卸载时解除绑定；引擎仍由组件释放。内置整条 feed 的 MovaAutoPause，可配置 autoPause（null 禁用守卫）和 routeObservers，翻页互斥仍由池负责。
  Feed 单页 loader 抛错、open 拒绝/抛错及播放中终结错误改为可见失败界面，默认使用主题错误/重试文案，可通过 errorBuilder 自定义；失败不会因普通重建无限重试，显式重试只处理该页。当前页加载失败停止上一页声音，其他页仍可继续浏览；loader 返回 null 的结束占位保持原样。

- MovaSource 新增 headers/userAgent/start：播放选项、清晰度探测、VTT/雪碧图、抽帧和 feed 预取共用源请求头，显式 UA 优先；点播起播位置通过既有 seek 寄存链下发，直播忽略。MovaApi.open 与 MovaHttpFetch.get(Uri) 签名保持不变；新增 MovaHeaderedHttpFetch 可选能力，旧 fetcher 无头退化且每实例仅 debug 提示一次；抽帧同样通过可选 MovaHeaderedFramePuller 兼容旧端口。

- 预览资源门控传递请求代际和取消信号，在异步网络探针返回后、HTTP/抽帧启动前复核；取消、换源和销毁使旧调用失效，销毁不等待探针，包装器仍不销毁宿主端口。
  预览网络策略拒绝通过专用信号透传 VTT 和服务层，不再计入 VTT 获取失败冷却，也不继续普通失败兜底；切回 Wi-Fi 可立即重试。
  收严 C12 的按需边界：自定义预览来源可能只读内存，未显式注入探针时不再根据远程媒体地址查询默认连通性；内置来源仍只在实际远程资源请求处查询，显式注入探针的自定义来源继续入口门控，never/always 策略保持。
  推翻旧的网络探针不默认接线决定：createMovaEngine 为 wifiOnly 预览按需创建连通性探针；仅实际请求远程 VTT、雪碧图或抽帧时查询，缓存、VTT 冷却、禁用来源和本地资源不查询。测试接缝继续不接平台插件。

- 最后一个视图解绑后，将尚未到期的 HUD/控制条计时责任交还引擎或旧镜像，保留剩余期限与常显状态，清理拖动和预览；普通引擎及 cutover 代理均适用。HUD 在同步通知监听器前登记计时器，重入和随后销毁不再留下旧计时器。

- 内置预览服务为每个视图建立独立会话，共享缓存与串行来源解析，各视图只接收自己的结果、取消自己的请求。自定义预览可实现 MovaPreviewSessions 提供同等隔离。底栏或横滑拖动因锁定而卸载时释放自身拖动状态，清空预览并恢复自动隐藏。

- 拖动进度条或横滑 seek 时，视图控制条与预览保持可见，松手后重新开始自动隐藏计时；控制条按下、按钮指针/键盘/语义激活会续期，常显状态保留。适用于支持桥接或显式传入 chrome 的视图，非桥接旧路径保持原行为。

- 每个支持桥接的 MovaPlayer 视图各自持有 MovaChrome（可由宿主传入），控制条、HUD、拖动和预览互不串扰；cutover 换指及影子 Ready 重放保持视图交互态与计时。无视图时旧行为不变；自定义 MovaApi 默认沿用旧接口，可显式传入 chrome 启用独立交互态。有视图时就绪显隐由视图处理，普通引擎的旧读者在 MovaReady 后晚一个微任务看到镜像。

- 测试入口新增 `MovaTestKernel.scripted` 和 `MovaTestStep`：可脚本化就绪、缓冲、进度、失败与结束；就绪自动组合首帧信号，换源和销毁取消旧步骤。普通构造继续默认被动，不自动播放或发出信号。

- 注入的内核、预览缓存/探针/来源/抽帧器、HTTP 与 STT 识别器由宿主销毁；自建资源仍随引擎释放。需要移交内核时用 `ownsKernel: true`，默认工厂创建的内核自动归引擎所有。STT 启动失败仅回滚，不再向播放链抛出。新增 `MovaAbrConfig.policyFactory`，每引擎创建独立策略，优先于旧 `policy`；旧实例字段下个版本弃用，本版只公告。

- MovaMini.show 与 showInPage 一致遵守 mini.enabled；关闭的 cutover 预热与缺少识别器的 STT start 在 debug 下每实例提示一次，可分别读取 cutoverEnabled 与 options.stt.hasEngine。

- Fix：清晰度探测按会话与有效源地址下标去重。故障切换后可显式探测新 master，旧地址迟到结果仍丢弃，同地址换档和重试继续共用请求。引擎销毁时关闭自建 fetcher，即使禁用 VTT 或自定义预览来源也取消在途探测；宿主注入的 fetcher（含默认 VTT 借用）由宿主关闭。

- Fix：广告换集同步取消旧计时与影子，后贴片不再预热已结束的正片；广告异步操作按加载代际丢弃迟到结果，避免旧广告恢复计时、倍速或 STT。

### 错误、恢复、加载与平台

- 脚本测试内核的延迟 ready 使用最新播放意图，保留 ready 前 pause/play 的最后决定；普通被动内核继续只记录命令、不自动发信号。

- createMovaEngine 在 debug 下提示注入 kernel 时被忽略的默认内核参数；Android 使用默认内核并开启 tlsVerify 时断言必须提供非空 tlsCaFile。抽帧器继续默认 null，文档明确需显式注入。

- README 应用示例统一使用 createMovaEngine，首例等待并捕获打开失败；裸 MovaEngine 缺省平台端口时在 debug 下一次性提示。

- 补回无 END_FILE 事件泵时的主文件打开失败终结状态：在错误到达时确认泵不可用，且 stream/cplayer/ffmpeg 错误文本包含当前主文件地址才启用兜底；外挂字幕、外部音轨和 HLS 分片错误保持诊断，泵可用时仍以 END_FILE 为准。

- 修复 END_FILE 归属与终结处理：每次实际加载前同步排空旧弱客户端队列，结束通知携带尝试编号；统一终结入口，单次尝试仅一次 fatal，重复日志保留诊断。待机失败静默降级并在唤醒时重开，open 期间的通知在返回后处理。

- `state.error` 只表示终结播放的错误。非终结内核日志不再写此字段，也不弹默认错误遮罩；`MovaErrorEvent(fatal: false)` 与 `MovaHook.onError` 仍照常通知。需要诊断所有错误的宿主请改监听 `api.events` 中的 `MovaErrorEvent`，按 `fatal` 决定是否显示失败；需要跟踪恢复决策的宿主监听 `MovaPlayFailure`。END_FILE(error)、恢复放弃、已知终结文本和 open 抛出仍写入状态；无泵时补回包含主文件地址的打开错误兜底，沿用恢复或终结裁决。

- 错误遮罩使用 `MovaStrs.playbackError` / `retry` 文案（默认“播放失败，请重试”/“重试”）；原始错误仅在 debug 模式显示。

- 新增实验性 `MovaAbrConfig.manageAuto`（默认 false）：显式开启后，auto 卡顿时由 mova 降到列表次高档，再沿用具体档位降档逻辑；遵守 ABR 总开关与 seek/换档租约。CP0 真机实测（STG-AL00、默认配置、限速夹具、90 秒窗口）：mpv 的 auto 档停留最高档、未自动降档，限速下反复缓冲；开启本开关由 mova 的 ABR 接管降档。仍为实验性，默认关。

- 判失败不依赖 recovery：首次 open 懒启动 END_FILE 弱客户端；终结错误清缓冲并暂停，有封面时启用 RESTART。alternatives 需启用 recovery（debug 断言）。

- recovery 关闭时 open 失败仍抛出，同时写终结 state.error；预告下一版本不再抛出，请迁移到错误事件处理。

- 新增：播放错误事件分级。`MovaErrorEvent.classified` 携带 `fatal/code`，旧构造器签名与默认语义保留。mpv 通过可选错误能力从日志保留子系统，引擎优先订阅该入口，旧内核仍可使用 error 流。日志默认非终结；`Failed to initialize a decoder`、`Failed to recognize file format.`、恢复放弃为终结，code 与 QoE 映射一致。只有终结错误写入 `state.error`；END_FILE 已接线，QoE 结算口径不变。

- Fix：直播换档与时移 seek 的 ABR 租约等待本次缓冲 true → false 后释放。忽略 open 内部 stop 的前置 false，避免加载自身被计为卡顿；无缓冲信号时仍在 10 秒后释放，点播续播校验与换源/销毁清理保持不变。
  Fix：ABR 屏蔽改为带加载尝试号的租约。旧换档的迟到收尾不能释放新换档或 seek 的屏蔽；用户 seek 引起的缓冲不计入 ABR 卡顿，10 秒兜底上限保持不变。

- Fix：新的用户 seek 清除被取代的旧寄存/待结算目标；时长已知但首档尚未落地时再次换档，沿用最新 seek（含 0 秒），目标回声结算后也不回退到旧加载规格。时长未知时仍寄存并在就绪后补发。

- Fix：待机唤醒与回边缘重开补播遵守当前待机相位；再次待机立即作废在途唤醒，不发旧恢复事件。recovery 关闭时，后台唤醒重开失败经 state.error、MovaErrorEvent 和 hook.onError 上报，并结束恢复测量，不再超时误报恢复成功。

- Fix：内部重试重放有效加载规格，保留手选清晰度；时移重试按原固定落后量和当前时间重建地址，故障切换清时移与旧档列表。回边缘保留当前档与时长，重开后按最新播放意图开播。连续换档继承尚未落地的续播目标，恢复等待首帧期间的用户 seek 取代旧失败点。

- Fix：待机唤醒测量使用独立首帧闸门；换源、换档或恢复重载会以 reloaded 结束旧测量，不发送 MovaKeepAliveResume，旧恢复超时不再干扰新源首帧。

- Fix/时序变化：待机唤醒的回边缘及重开不再占用待机队列；`setKeepAlive(false)` 在进入 resuming 时完成，不等待网络重开或首帧。网络返回后仅当前尝试按最新播放意图开播，期间 pause 不被覆盖。

- Fix：被宿主拒绝的 open 不再作废在途 play/seek；暂停加载期间的播放意图在加载完成后补发，待机请求仍保持暂停加载。

- Fix：硬解失败后成功回落软解不再误报播放错误。精确过滤 mpv 的 `Could not open codec.` 尝试日志，保留解码器耗尽与格式识别失败的终结错误，默认关闭 recovery 时仍能报出真失败。

- Fix：时长未知时的负向 `seek`/`seekBy` 不再下界漏钳。时长未到时 `seek(-5s)` 被原样寄存，进度先上报负数，时长到达后还把 -5s 下发内核（已知时长的路径本来会钳到 0）。现在入口先把下界钳到 0，补发时再按时长上界钳一次。

- Fix：用户主动 `seek` 被 mpv 丢弃后进度条永久冻结（H17）。此前只有换档续播的 seek 有“校验 + 重发”链，普通 seek 被丢弃后 `_pendingSeekTarget` 一直布防，之后所有真实位置都被当陈旧回声吞掉，直到下一次 seek。现在点播 seek 复用同一条校验重发链（最多 3 次），放弃后解除回声抑制、进度重新跟随真实位置；重发期间来了新 seek 则旧链作废，直播不 seek 的规则不变，暂停态同样成立。

- Fix：换档（`switchQuality`/ABR 降档）续播位置丢失。HLS 手动连续切档时，续播 seek 在新档位报告时长的瞬间就下发，而此刻 mpv 尚未完成播放初始化，seek 被静默丢弃，播放从头开始（Android 真机本地 HLS 5 次切档仅 1 次续播成功）。现在寄存的续播 seek 等新档位落地（首帧/原生 RESTART）后再补发；4s 内始终没落地则兜底照旧补发，落地早于时长则等时长到达再发。Android 真机（STG-AL00）普通/swap 代理/暂停态各 5 次共 15/15 落点误差 0ms。

- Fix：`setRate` 入口钳制。倍速钳到 0.25–4.0（`kMovaMinRate`/`kMovaMaxRate`，NaN 当 1.0），内核、state、`MovaRateChange` 看到同一个值（此前 0/负数/NaN 直接下发内核，state 与事件照抄）。

- Fix：宿主上报回调抛异常不再打断引擎。`MovaReporter.onReport`（含 `MovaApi.report` 与 QoE collector 两处调用点）抛出的异常被隔离，只通知各钩子的 `MovaHook.onError`，播放状态与后续上报不受影响（此前异常冒进事件订阅回调，变成未捕获异步错误）。

- Fix：`setVolume`/`setBrightness` 越界值。入口先钳到 0–100 / 0–1，state、事件与端口看到同一个值（此前 state 写入越界值，系统音量被端口钳制、亮度被平台插件以 `RangeError` 拒绝后吞掉，HUD 与设备实际对不上）。

- Fix：重复 `dispose()` 抛异常（A23）。`MovaEngine`/`MovaCutoverEngine` 的 `dispose()` 改为幂等，第二次调用直接返回。

- Fix：`setZoom` 低值让画面塌缩（A12）。小于 1.0 或 NaN 按 1.0 处理；上限仍不限制（`maxZoom` 只约束捏合手势）。

## 0.4.0

* **新增：统一超时配置 `MovaTimeouts`**（`MovaRecoveryConfig.timeouts`，随 `package:mova/mova.dart` 导出）。字段 `network`（→mpv `network-timeout`，整秒）、`whepHandshake`/`whepFirstFrame`/`whepMedia`（→`handshake_timeout`/`first_frame_timeout`/`media_timeout`，微秒，仅 `whep…`），每次 open 前经现有源选项机制下发 mpv；默认全 `null`（不动 mpv 默认值）；`MovaSource.mpvOptions`/`demuxerOptions`/`whepMediaTimeout` 的显式设置优先。`MovaSource.mpvOptionsFor` 新增可选参数 `timeouts`；新增公开常量 `kMovaWatchdogMargin`（5s）等。
* **行为变化：Dart 看门狗降级为兜底，期限改为从 mpv 窗口派生**（只在 `recovery.enabled` 时可见）。重连以 mpv 的 `END_FILE(error)`/错误事件为主路径；`startTimeout`/`stallTimeout` 默认值由固定 10s 改为 `null`（派生 = mpv 最长窗口 + 5s）：未配置 `timeouts` 时非 WHEP 起播/卡顿均为 65s，WHEP 起播 85s、卡顿 10s；显式设置仍以用户值为准。**未配置时黑洞主机的判失败会比之前（10s）慢很多**，建议同时设置 `timeouts.network`。
* **行为变化（API）：** `MovaRecoveryConfig.startTimeout`/`stallTimeout` 类型改为 `Duration?`；原 `stallTimeout: null`（关闭卡顿看门狗）改用新字段 `stallWatchdog: false`，`null` 现在表示“派生”；`copyWith(clearStallTimeout: true)` 现在是“重置为派生”。新增 `startTimeoutFor(uri)`/`stallTimeoutFor(uri)`。
* **行为变化：`MovaLiveReconnect.maxDelay` 默认 30s 改为 15s**（退避序列 1、2、4、8、15、15…）。
* **Docs：** README 恢复一节补“重连分工”（直播不开 `reconnect_streamed`、点播保留 mpv 默认重连、mpv 主路径/Dart 兜底）与 `MovaTimeouts` 用法。

## 0.3.2

* **Fix：恢复层真机复测的两处问题**。
  * **默认配置下 404 等确定性失败仍等满 `startTimeout` 才重试**：原生 `END_FILE` 订阅只在有 reporter 或 `preciseFirstFrame: true` 时才打开，`recovery.enabled` 不会打开它，README 写的"坏地址秒判"对不上。现在 `createMovaEngine` 在 `recovery.enabled` 时自动订阅 `END_FILE`；`MovaMpvKernel` 新增 `observeRestarts`（默认 `true`），恢复机制只开 END_FILE、不转发 `PLAYBACK_RESTART`，首帧判据与未开 recovery 时一致（不转发 RESTART 时 `nativeRestartAvailable` 为 `false`，首帧闸门不会白等宽限）。`movaObserveFlags` 新增 `recovery` 参数与 `restart` 字段。
  * **`whepMediaTimeout`/`demuxerOptions` 整体覆盖 `demuxer-lavf-o`，还原又失败**：此前整串 set，media_kit 默认的 `seg_max_retry`/`allowed_extensions`/`protocol_whitelist` 等被冲掉；还原时把读出的串原样写回，而 `protocol_whitelist` 的值带逗号没法再解析，mpv 报 `Expected '=' and a value.`，错误进 `state.error` 并发 `MovaErrorEvent`，之后的点播源还带着 `media_timeout`。现改为 `change-list add` 只并入本源的键，还原时 `remove` 这些键、被同名键顶掉的原值用 `append` 补回，不再读回整串；写入失败或语法不合法的项整项跳过。`MovaMpvKernel` 对 `demuxer-lavf-o`/`stream-lavf-o` 这类键值列表走此路径，其余 `mpvOptions` 仍是整值写入、还原为读到的原值。

* **Fix：恢复层（`MovaOpts.recovery`）六处问题**（来自 Android 真机拉 WebRTC/WHEP 直播、推流端掉线再恢复的场景）：
  * **恢复成功后 `state.error` 不清**：`MovaRecovered` 发出时同步清掉失败期间遗留的内核错误（此前只有 `open()` 会清，画面正常了仍带着旧的 "Failed to recognize file format"）。
  * **放弃后 `state.buffering` 一直为 true**：`giveUp` 时把 `buffering` 置回 false，并补发一次 `MovaBufferChange(false)`（本来就不在缓冲则不多发），转圈不再永远挂着。
  * **重试失败要等满 `startTimeout` 才发下一次**：根因是加载在途（`_kernelOpening`）时到达的 `END_FILE(error)`（如 404）被直接丢弃，只能靠 10s 起播超时兜底。现在先记下，`open()` 返回后立刻按策略处理；被更新的 `open()` 取代的会话则丢弃。
  * **直播默认只重试 1 次**：新增 `MovaLiveReconnect`（指数退避，默认 1s 起、×2、封顶 30s，永不放弃，`maxAttempts` 可设上限；多地址时前面的地址各重试 `retriesPerAddress` 次再切，最后一个持续重连）与 `MovaDefaultRecovery`（点播 `MovaRetryThenFailover`、直播 `MovaLiveReconnect`），`MovaRecoveryConfig.policy` 为 `null` 时生效；新增开关 `MovaRecoveryConfig.liveReconnect`（默认 `true`，设 `false` 直播回到旧的重试 1 次）；`MovaPlayFail` 新增 `isLive`。**行为变化**：直播源在 recovery 开启且没传自定义 `policy` 时不再在第二次失败后放弃；点播默认行为不变。`MovaRecoveryConfig.effectivePolicy` 的默认类型由 `MovaRetryThenFailover` 变为 `MovaDefaultRecovery`。
  * **公开 API 无法传源级 libmpv/ffmpeg 选项**：`MovaSource` 新增 `mpvOptions`（任意 mpv 选项）、`demuxerOptions`（合成 `demuxer-lavf-o`）、`whepMediaTimeout`（WHEP `media_timeout`，自动换算微秒、只对 `whep…` 地址生效）与 `mpvOptionsFor(address)`；`MovaSource.pick`/`sameAs` 同步支持。内核侧新增可选能力 `MovaSourceOptionsKernel`（`MovaMpvKernel` 与 `MovaTestKernel` 实现）：引擎在每次内核 `open` 前暂存该地址的选项，内核在 open 前下发，下一次 open 先还原原值，不泄漏到下一个源。`MovaTestKernel.stagedSourceOptions` 供宿主测试断言。
  * **直播 `MovaDurationChange` 过于频繁**：新增 `MovaLiveConfig.durationStep`（默认 2s），直播源时长变化不足一个步长不上报（state 与事件都跳过；首个非零值、回落到 0、重新 open/重载后的第一个值一律放行），`Duration.zero` 关闭节流；点播不变。
  * 新增 48 项回归（`recovery_fixes_test`/`live_reconnect_test`/`duration_throttle_test`/`source_options_test`/`engine_source_options_test`/`mpv_kernel_source_options_test` 等），全量 1472 项通过。

## 0.3.1

* **Breaking（公开签名）：`MovaApi.open()` 由 `Future<void>` 改为 `Future<bool>`**，`true` 表示该源已被接受为当前源；`beforeOpen` 钩子拒绝、被更晚的 `open()` 取代、引擎已销毁时为 `false`。加载失败不算 `false`（照旧经事件/恢复上报，未处理的仍抛出）。只 `await`/`unawaited` 调用的代码无需改动；自己实现 `MovaApi` 的类（含测试替身）须把 `open` 的返回类型改成 `Future<bool>`。`MovaPlaylistController.jumpTo` 据此在 `open` 被拒绝时不再前进下标，列表与实际在播源不再错位。
* **Fix：宿主异步钩子、预览队列与手势改配的三处边界**。① `play()`/`seek()` 在宿主异步 `beforePlay`/`beforeSeek` 返回后复查：期间用户 `pause()` 或换源，晚到的 play/seek 不再覆盖（此前会把暂停改回播放，或对新源执行旧跳转）。② 预览服务队列单次解析抛错不再让后续请求全被跳过，`dispose` 各步骤相互隔离（宿主注入的缓存/探针抛错不再拖垮销毁）。③ 手势动作改配后按选中该模式的那根轴取位移：`horizontal: volume/brightness` 向右为增，`leftVertical/rightVertical: seek` 向上为快进（此前读错轴，位移约为 0）；默认配置行为不变。
* **Fix：三处小问题**。`MovaDanmakuConfig` 加 `assert(trackCount > 0)`（原先为 0 时弹幕取模除零）；`MovaGestureConfig` 加 `assert(maxZoom >= 1)`（原先小于 1 会在捏合中途让 `clamp` 抛 `ArgumentError`）；`MovaSttService.start()` 在引擎 `start` 失败时回滚 `isRunning`，失败后可直接重试，不必先 `stop()`。另补全 `MovaPatch*` 与 `MovaPlatform` 的公开成员注释。
* **Refactor：无缝切换的倍速改由预热计划声明**。`MovaWarmPlan` 新增 `rate`（null 继承旧引擎，行为不变），`MovaSwapController.swapTo` 新增可选 `rate`；广告方向（内置 `effectiveWarmPlan` 与 pod 的 `swapTo`）声明 1x，回正片方向声明广告前的倍速，换指时直接写到继任者上，不再有"换指后到复位生效之间广告短暂跑用户倍速"的窗口。广告控制器里原有的 `setRate` 复位保留为兜底，只服务回落成普通 `open()`、或宿主自定义 `adWarmPlan` 没带 `rate` 的路径。Android 真机 V12/V13a(2x)/V13b(1.5x) 通过。
* **Fix：广告 pod 里第二条广告的 `swapTo` 被悄悄降级成普通 `open()`**。两处竞态：① `MovaSwapEngine.abandon()` 在第一个 `await` 之后才复位 `_warmPlan`/订阅、把阶段置回 `idle`、唤醒就绪 completer，`unawaited(abandon())` 后紧跟 `swapTo` 时会冲掉新预热，现改为共享状态在 `await` 之前同步复位；② `MovaAdController` 在 `swapTo` 等待期间，旧引擎的进度 tick 会触发"广告背后预热正片"，把 `swapTo` 正在等的广告影子挤掉，现 `swapTo` 在途时不预热正片。Android 真机（STG-AL00）V12/V12b：第二条广告走真换指（`renderEpoch` 递增），槽位时长 5970–5999ms（配置 6000ms）。
* **Fix：系统 PiP 被用户展开/关闭后 `state.pip` 不复位**。新增可选端口能力 `MovaPipObservable.changes`（引擎用 `is` 探测，既有 `MovaPipPort` 实现无需改动），Android 插件监听 Activity 配置变化并推送 `pipChanged`（退出时 PiP 标志晚于配置变化翻转，故延迟复查并去重）；引擎据此更新 `state.pip` 并发 `MovaPipChange`。Android 真机（STG-AL00）`am start` 展开路径已验证 `true→false`；点 X 关闭路径未能注入点击，未测。
* **Fix：全量评审（Codex + 人工终审）修复一批异步过期/资源所有权问题**，新增约 45 项回归，Android 真机（STG-AL00）逐项对照修复前基线复测：
  * **无缝切换**：预热超时改由独立计时器兜底，不再依赖进度事件（`readyTimeout` 此前在影子完全无进度时不生效）；影子 `open`/`seek` 失败会清理并回退为普通打开，且不再往主事件流发 `MovaErrorEvent`（否则会把健康的在播广告误判失败）；已有影子时 `swapTo` 换了源会先丢弃再预热，不再提交旧影子；提交中途 `dispose` 会销毁影子；提交时把 rate/fit/zoom/音量/锁定/全屏/小窗/方向迁给继任者，旧引擎经 `MovaHandoffRetirable` 标记退役，退役引擎 `dispose` 不再复位全局方向。
  * **引擎**：`beforeOpen` 之后校验 `dispose`；`dispose` 后不再向已关闭的事件流 `add`；全屏/强制方向下 `dispose` 会复位设备方向与沉浸模式；`MovaMpvKernel.open()` 在异步恢复后复查序号，旧请求不再覆盖新源；`MovaVolumeChange.value` 注释订正为 0–100。
  * **广告**：加会话号与销毁标志，延迟解析的旧结果不再重开旧正片；广告加载超时与槽位计时改以真正的首帧（`rendered`/`MovaFirstFrame`，回退为连续两次递增的非零位置）为准，不再被零位置/残留进度提前取消；swap 路径下广告期间复位 1x、返回后恢复用户倍速。
  * **其余**：Feed 池同索引换源先释放旧引擎；QoE 会话累计器每次 `open()` 清零；播放列表 `jumpTo` 交错时丢弃过期结果；预览缩略图带 crop 时不入缓存（否则命中后显示整张雪碧图）、换源后丢弃旧请求结果、swap 提交后气泡随 `renderEpoch` 重订阅。
  * 已知未修见 `CLAUDE.md`「全量评审遗留」（PiP 退出状态不复位等）。

* **Fix：Windows 上 push 不透明路由时进程原生崩溃（HE V10）**：根因不在 mova，而是 Flutter 3.47.0/3.47.1 引擎的 bug——Windows + Impeller 下，`MaterialPageRoute` 默认的 `ZoomPageTransitionsBuilder` 会给页面拍快照（`SnapshotWidget`），快照里带外部 GPU 纹理（media_kit 的 DXGI 共享句柄纹理）时，引擎 `LayerTree::Flatten` 里解引用空上下文，进程在 `flutter_windows.dll` 以 `0xC0000005` 退出（flutter/flutter#190774，Flutter 3.47.2 已修）。纯 media_kit `Video` 不带 mova 同样复现。mova 侧规避：`MovaPlayer` 的渲染面在 Windows 上套一层 `MovaSnapshotGuard`（加一个 `supportsRasterization()==false` 的图层，宽松快照据此退回普通绘制），其他平台行为不变。release 实测：修复前 6/6 崩溃、探针 2 轮内必崩；修复后验证页 V10A 20/20、V10 10/10、探针 20/20/20/30 轮不崩。**根治办法是宿主升级到 Flutter ≥ 3.47.2**；也可在主题里对转场关快照（`ZoomPageTransitionsBuilder(allowSnapshotting: false)`）。新增 8 项回归（`test/ui/snapshot_guard_test.dart`）。详见计划文档 `doc/plans/2026-10-23-host-ergonomics.md` V10 小节。

* **Fix：点播恢复重试丢失续播位置（HE V6）**：卡顿超时、`open()` 异常后的重试及原生 `END_FILE(error)` 恢复，改为等本次尝试首帧落地后再发送续播 seek，避免加载命令已返回但文件未就绪时 seek 被丢弃。同内容备选地址沿用续播点，跨失败继续保留；直播不 seek。代码回归已通过，待 Windows/Android 复测。

* **Fix：无缝切换预热误改系统音量（standby 计划 Q13）**：`muteWhileWarm` 改走可选的播放器静音能力，mpv 仅保存、改写、还原自身 `mute`；预热和提交均不写系统音量端口。不支持能力的内核不静音；与 standby 静音叠加时按各自所有权精确还原。恢复静音失败走放弃切换策略并发出错误事件。代码回归已通过，待真机音频确认。

* **宿主易用性增强（第一批，对应 `doc/plans/2026-10-23-host-ergonomics.md` Task 1–8）**——全部默认关闭或与旧行为一致：
  * **"已出画面"信号**：新增 `MovaState.rendered`（当前源已呈现首帧/首段音频，每次 `open()` 重置）与
    `MovaFirstFrame(sinceOpen, signal)` 事件（每次 `open()` 一次，可重复）；判据纯逻辑在 `MovaFirstFrameGate`/
    `MovaFirstFrameSignal`（原生 RESTART 为权威，兜底为 buffering 下降沿/连续递增位置/暂停态首个尺寸，原生在工作时
    兜底信号先到则最多等 1.5s 宽限）。内部重载（换档、回直播边缘、时移）不重置 `rendered`。
    **行为微调**：`open()` 现在会同步把 `state.width/height` 归零（此前要等内核异步发 null），换源后旧画面比例不再漏进新源。
  * **原生事件订阅与 QoE 解耦**：`MovaMpvKernel(observeNativeEvents:)`（默认跟随 `observeQoeSignals`，既有调用点不变）；
    `createMovaEngine(preciseFirstFrame:)`（默认 `false`；`true` 时即使没有 reporter 也订阅原生 RESTART，首帧更准，
    代价是每引擎一个 mpv 弱客户端）。
  * **填充模式可声明**：`MovaEngine`/`createMovaEngine` 新增 `fit` 初值参数；`MovaPlayer(fit:)` 挂载时应用一次，
    之后仅在该值变化（或换了 `api`）时再应用，用户用 fit 按钮选的值不会被无关重建覆盖。
  * **内置封面**：`MovaPlayer(poster:, posterFade:)`，封面放在交给皮肤的 `video` 里（缓冲转圈/错误层/控制条画在其上），
    `rendered` 且画面尺寸已知后淡出，换源瞬间重新盖上；仅音频源常驻。`MovaFeedPlayer(posterUntilFirstFrame:)`
    （默认 `false`）把 placeholder 当封面盖到首帧。
  * **极简皮肤** `MovaMinimalSkin(showBuffering:, showError:)`：只有画面与可选转圈/错误层，无手势层与任何栏；
    `MovaTheme` 新增可空的 `bufferingSize`/`bufferingStrokeWidth`/`bufferingColor`（默认 `null` = 与旧外观一致）。
  * **声明式组件** `MovaView`：传 `source` 即可，自己创建/复用/重建（`options` 变化）/销毁引擎，源变 `null` 时暂停，
    打开失败走 `onOpenError`（缺省交给 `FlutterError.reportError`）；有 `poster` 时默认开启原生首帧订阅。
    新增 `MovaSource.sameAs()`（比较 uri 与 type，忽略 title）；`MovaSource` 刻意不重写 `==`。
  * **破坏性变更（编译期）**：`MovaEvent` 是 `sealed`，新增子类 `MovaFirstFrame` 会让宿主里**没有 `default` 分支的
    穷尽 `switch`** 编译报错，补一个分支或 `default` 即可；mova 自己的事件翻译已有 `default`，不受影响。
* **宿主易用性增强（第二批，对应同一计划 Task 9–15）**——全部默认关闭：
  * **起播/卡顿超时与恢复** `MovaOpts.recovery`（`MovaRecoveryConfig`，默认 `enabled: false`）：起播超时（默认 10s）、
    卡顿超时（默认 10s，`null` 关闭）、`open()` 抛异常、原生 `END_FILE(error)`、直播走到结尾（`liveEndIsFailure`）。
    决策由可注入的 `MovaRecoveryPolicy` 给出（默认 `MovaRetryThenFailover`：每地址 1s 后重试 1 次再切备选，用尽放弃；
    另有 `MovaFailoverOnly`），产出 `MovaRecoveryDecision.retry/failover/giveUp`。新事件 `MovaPlayFailure(fail, action)`、
    `MovaRecovered(attempts)`；放弃时写 `state.error = MovaGiveUpError` 并发 `MovaErrorEvent`，同时暂停内核。
    重试/切换是内核重载而非新会话（不过拦截器、不发 `MovaSourceChange`、不动 QoE 会话）。**关闭时不创建任何 Timer、
    不订阅任何新流，`open()` 失败仍照旧抛给调用方**（`MovaAdController` 依赖它区分 `openThrew`）。
  * **多地址兜底**：`MovaSource(alternatives:)`、`MovaSource.uris`、`MovaSource.pick()`（清洗并去重保序）、
    `MovaState.sourceIndex`、`MovaFailover(from, to, uri)` 事件。`sameAs()` 现在也比较备选地址（含顺序）。
    **仅在 `recovery.enabled` 时才会用到备选**，关闭时被忽略。mova 不提供排序/过滤钩子，由宿主排好序。
  * **自动暂停守卫** `MovaAutoPause` 与纯逻辑 `MovaAutoPauseGate`/`MovaAutoPauseConfig`（`MovaHideReason`/`MovaLiveResume`/
    `MovaGuardAction`）；`MovaView(autoPause:, routeObservers:)`。覆盖滚出视口、非活跃 Tab（`TickerMode`）、被路由盖住、进后台；
    `inactive` 不暂停但先快照播放意图；画中画/小窗里不暂停；直播隐藏 ≥ 3s 回边缘再播。只用 Flutter SDK，无新依赖。
    **注意**：`routeObservers` 是**列表**，每个 navigator 一个观察者——`NavigatorObserver` 不能同时挂到两个 navigator 上。
  * **宿主测试替身** `package:mova/testing.dart`：`MovaTestKernel`、`MovaTesting.useTestKernels()/reset()/lastKernel`；
    安装后 `createMovaEngine()` 改用可编程内核、平台端口全部空实现，widget 测试不再需要 `MediaKit.ensureInitialized`。
    不在主 barrel 里。
  * **破坏性变更（编译期）**：`MovaEvent` 再新增三个子类 `MovaPlayFailure`、`MovaRecovered`、`MovaFailover`
    （连同上一批的 `MovaFirstFrame` 共 4 个），宿主里没有 `default` 分支的穷尽 `switch` 需要补分支。
    `MovaOpts` 新增 `recovery` 节（有默认值，既有调用点不受影响）。
  * 验证页：`example/lib/main_host_ergonomics_verify.dart`（真机验证用，尚未上机）。
* **评审修复（11 条）**：`MovaState.playbackIntent` 独立于内核 `playing`，内部重载与看门狗遵循最新播放意图；恢复绑定已接受会话与失败尝试，跨失败保留续播点；自动暂停守卫订阅状态并重绑引擎、保留配置更新前的隐藏周期；直播恢复、视图加载、档位请求均校验异步过期。逐条说明见 `doc/plans/2026-10-23-host-ergonomics.md`「评审修复」。

* **低功耗待机（standby，对应 `doc/plans/2026-10-23-standby-mode.md` Task 1–9）**——默认关闭，不调用就一行代码都不会走到：
  * **入口**：`MovaAutoPauseConfig(hiddenMode: MovaHiddenMode.standby)`（守卫自动处理，默认 `pause`）与命令式的 `MovaStandbyController.setStandby(bool)`
    （`MovaEngine`/`MovaSwapEngine` 实现；`MovaApi`、`MovaKernel` 零新增成员，用 `is` 探测）。调参 `MovaOpts.standby`（`MovaStandbyConfig`：`maxDuration` 默认 30s、
    `silentStreams`、`allowHls` 默认 false、`resumeTimeout` 默认 5s、`liveResumeGrace` 默认 3s）。
  * **机制**：有音频的直播 → 关视频解码并静音（`mute`/`vid`，保存后原样还原，绝不碰 `volume`/`vo`/`wid`/`VideoController`）；无音频 → 继续解码只静音；
    点播、进后台、媒体信息未知、HLS（默认）→ 普通暂停；到 `maxDuration` 自动退回暂停。**网络不省，省的是解码/渲染/电。**
  * **状态与事件**：`MovaState.standby`（`MovaStandbyPhase`：`off`/`holding`/`fallback`/`resuming`）、`MovaStandbyChange(phase, reason, mode)`、
    `MovaStandbyResume(elapsed, signal, from)`；`MovaStandbyMode`/`MovaStandbyReason`/`MovaSilentStandby` 随之公开。
  * **恢复计时**：`MovaFirstFrameGate.arm(resume: true)` 只认原生 RESTART 与非零尺寸、立即落地；`rendered` 全程不动，不发 `MovaFirstFrame`。
  * **与既有能力的交互**：待机期间看门狗不计时、ABR 与自动回边缘不触发、失败延到唤醒时强制重开；待机请求期间 `open()` 换源以暂停态加载，首帧落地后再尝试待机；
    `setMini(true)`/`enterPip()` 先唤醒；`MovaSwapEngine` 透传并在提交时把待机施加到新引擎；封面在待机与恢复期间瞬间盖上；`MovaTestKernel` 支持待机（`hasAudio`/`fileFormat`）。
  * **破坏性变更（编译期）**：`MovaEvent` 再新增 `MovaStandbyChange`、`MovaStandbyResume`，`MovaGuardAction` 新增 `standby`/`wake`，宿主里没有 `default` 分支的穷尽 `switch` 需要补分支。
  * 验证页：`example/lib/main_standby_verify.dart`（真机验证用，尚未上机）。

## 0.3.0

* 埋点上报增强：`MovaReporter` 补齐 TTFF 首帧耗时、卡顿次数与时长、播放失败
  fatal/非 fatal 区分、会话开始/结束（含四分结束原因）四大 QoE 指标；新增
  `MovaReportConfig`（`MovaOpts.report`，默认 `qoe: false`，关闭态事件流与之前
  逐字节相同）。信号优先取 libmpv 原生能力（`paused-for-cache`/`video-bitrate`/
  `cache-speed`/丢帧计数/日志 prefix 错误分类），并顺带修了 `MovaEngine.open()`
  的会话边界时序竞态与 `MovaMpvKernel.dispose()` 的原生资源竞态两个真实 bug。
  * **破坏性变更**：
    1. `MovaReportName` 从 `enum` 改为 const 值类——不再有
       `MovaReportName.values.byName()`；`.index` 消失；在名称上 `switch` 的调用点
       须改为对 `.value`（`String`）做 switch，Dart 不允许对重写了 `==` 的类型使用
       常量模式。`==`/`hashCode` 按 `.value` 计算，`Map`/`Set` 键用法与
       `MovaApi.report(name, ...)` 签名不变，普通比较调用点零改动。
    2. `MovaErrorEvent` 的产出从 `translator.dart` 移到 `MovaQoeCollector`，
       `qoe: true` 时 `params` 从 `{'error'}` 增补为 `{'error', 'fatal', 'code'}`
       且非 fatal 错误降级为 `batched`（`qoe: false` 时旧行为不变）。
  * 原生 mpv 事件（`PLAYBACK_RESTART` 精确首帧、`END_FILE` 会话结束原因）由自建的
    `dart:ffi` 弱客户端订阅（`mpv_create_weak_client`），`media_kit` 依赖保持 pub.dev
    的 `^1.2.6`，**不再依赖 git 提交，可正常发布**。debug 模式下走 100ms 轮询，release
    走原生回调。Android 与 Windows 已验证；iOS/macOS 未验证（订阅失败时静默退化）。
  * QoE 修复（Android 真机跑通后发现）：首帧不再把 open 后 `buffering` 的初始 `false`
    当成首帧（需要 `true→false` 下降沿，外加"连续两个递增位置样本"兜底）；
    `sessionEnd.stallMs` 不再重复累计（此前是真实值的 2 倍）；首帧落地前不计
    `watchedMs`。原生 RESTART 订阅在工作时（新增 `MovaStatsProbe.nativeRestartAvailable`），
    首帧只认 RESTART，忽略更早但更粗的 buffering/位置兜底。
* **`VideoController` 改为懒创建**：`MovaMpvKernel` 新增 `lazyVideo`（默认 `false`）；
  `createMovaEngine()` 与默认 `MovaEngine` 内核使用 `lazyVideo: true`，在第一次读取
  `renderHandle`（`MovaPlayer` 挂上树）时才创建 `VideoController`。创建了却从未挂到界面
  的控制器会让 media_kit 的 `Player.dispose()` 一直等待（真机 Windows 3/6、Android 4/5 次
  撞 8 秒超时），懒创建后"创建 engine 却不展示"的销毁只需十几毫秒。无缝切换的影子引擎
  创建后会主动读一次 `renderHandle`，预热期间仍有画面管线。**若调用方自己创建并注入
  `VideoController`，需自行保证它挂到 UI 后再销毁**（见 README「已知限制」）。
* **截断结束判定**：`qoe: true` 时，点播会话以 EOF 结束但完播率低于 `MovaReportConfig.truncatedBelow`（默认 `0.9`，`<=0` 关闭）
  不再记 `ended`，改为先发 fatal 的 `MovaErrorEvent`（`code: truncated`）、再记 `failed`；直播无 duration，
  仅在 `MovaDone` 前 5 秒内有 ffmpeg 错误日志时才判截断。修正首帧后断网/服务端中途断流被误记 `ended` 的问题
  （Android 真机中途断流复测通过）。
* **TLS 严格校验开关**：`createMovaEngine()`/`MovaMpvKernel` 新增 `tlsVerify`（默认 `false`，行为不变）与
  `tlsCaFile`。开启后证书过期/自签/域名不符的 HTTPS 流被拒绝（stream 错误，会话 `failed`），HLS 分片与
  AES key 同样受校验。**Android 瘦身 libmpv 用 mbedtls、无系统信任库，开启时必须同时传 `tlsCaFile`（PEM），
  否则所有 HTTPS 都会失败**；`tlsCaFile` 里放自签证书即可信任该证书。IP 直连（如 `127.0.0.1`）不比对证书主机名。
  Android 真机本机 HTTPS 矩阵 144 次全部符合预期；iOS/macOS 未验证。
* **预览抽帧器修复**：`MovaFrameExtractor` 不再创建 `VideoController`（无界面下它的初始化
  永远完不成，Android 上 `extract` 曾 5/5 超时），改为 `vid=auto` + `vo=null` 解码；首次
  seek 前等待时长就绪，并轮询 `seeking`/`time-pos` 判定 seek 落地再截图。
  * **行为变化**：`settleDelay` 的含义从"seek 之后固定等待"变为"seek **落地之后**的额外
    等待"，默认值从 250ms 降为 60ms；若你显式传入了自己的值，请按新含义重新评估。

## 0.2.0

* 瘦身版 libmpv 接入支持：提供轻量二进制替换方案（覆盖 Android / Windows / iOS / macOS），体积缩减约 50%。
* Feed 沉浸式流播放器增强：包含短视频滑动、预加载与抖音风格皮肤定制。
* 修复 `MovaFeedPlayer` 中 `ensure()` 异步回调类型推断警告。
* 完善文档与接入范式。

## 0.1.0

首次发布 / First release.

基于 media_kit（libmpv/ffmpeg）的 Flutter 视频播放器插件，自研手势与控制层，支持
点播 / 直播，可作为独立 UI 使用，也可按 Plugin / Component / Skin 三层契约深度定制。

### 核心播放能力

* 播放内核封装：`MovaApi`（能力面抽象）+ `MovaEngine`（生产实现）+ `MovaKernel`
  （内核抽象，唯一依赖 media_kit 的实现细节收在 `MovaMpvKernel`）。
* 构造引擎请使用 `createMovaEngine()`（`lib/src/platform_impl/wiring.dart`），
  它会接入亮度 / 画中画 / 方向等平台适配器的真实实现；裸构造 `MovaEngine()` 的平台端口
  默认是 noop，仅用于单测注入假端口。
* 清晰度：HLS master 解析、手动切换（保位续播）、缓冲卡顿自动降档（ABR）。
* 观看模式 `contain` / `cover` / `fill`；锁定/解锁防误触 + 沉浸式；全屏按视频宽高比
  自动横/竖屏，也可用 `MovaApi.setOrientation` 强制横竖屏（独立于全屏）。
* 仅音频模式（`audioOnly`）：`createMovaEngine(audioOnly: true)` 完全跳过视频解码
  管线（不建 `VideoController`、不注册 GPU 纹理），`renderHandle`/`size` 相应变为
  `null`/`0x0`，UI 层无需改动（封面/歌词等自定义画面用 `MovaPlayer.surface` 传入）。
  实测省内存约 2–2.7 倍（视场景而异）。

### 手势与 UI

* 手势层：横滑进度 / 双击快进退 / 双指缩放，带 HUD；左右侧竖滑默认分别对应
  亮度 / 音量（对齐 bilibili 等主流），可经 `MovaGestureConfig` 的侧别→动作映射
  （`MovaGestureAction`）任意重映射或用 `MovaGestureAction.none` 禁用某侧。
* 组件树 / 皮肤 / 补丁三层契约：`MovaComponent` 组件树由 `MovaSkin`（默认实现
  `MovaDefaultSkin`）依据 `MovaState` 出树，通过 `MovaPatch`（`replace`/`remove`/
  `insertAfter`/`add`）做结构级定制，无需派生子类；`MovaDefaultSkin.assemble` 也可按
  `buildPlaybackLayer`/`buildOperableLayer`/`buildPersistentLayer` 三层半覆写。
* `MovaPlugin` 能力 mixin：为有状态组件提供 `api`（稳定句柄）与 `bind()`
  （订阅并在 `dispose` 自动回收）。
* 文案与主题：`MovaStrs`（默认简体中文文案）与 `MovaTheme`（默认配色/尺寸）经
  `MovaOpts` 注入，可整体替换。
* 系统音量端口 `MovaVolumePort`：右滑音量可驱动系统媒体音量而非仅播放器音量，
  Android 默认接原生 `MovaSystemVolumePort`，其余平台可传
  `MovaCallbackVolumePort` 自行接管。
* 渲染性能：播放层 / 操作层 / 常驻层各自 `RepaintBoundary` 隔离，互不牵连重绘。

### 直播特性

* 点播 / 直播两套控制条自适应合并为 `MovaBottomBarComponent`。
* 直播时移：`MovaLiveSeekMode.dvr` / `.timeshift` 两种可拖模式，
  `MovaLiveConfig.urlBuilder`/`backToLive`/`autoBackToLiveOnStall`/`windowResolver`
  可配置；`MovaState.timeshiftBehind` 配合 `MovaTimeShiftChange`/`MovaLiveEdgeReach`
  事件，`MovaApi.backToLiveEdge()` 按策略执行。
* `MovaApi.pipSupported`/`MovaState.pipSupported`：PiP 按钮在不支持的平台自动隐藏。

### 画中画 / App 内小窗

* Android 系统级画中画（`MovaApi.enterPip()`）；iOS/桌面暂不支持
  （libmpv 纹理渲染方式下系统级 PiP 依赖 AVPlayer 路径，未实现，`pipSupported`
  返回 `false`）。
* App 内小窗 `MovaMini`：不依赖任何系统 PiP API，让画面从页面里"缩"成一个可拖拽
  的悬浮小窗，不重新解码、不黑屏。默认 **关闭**（`MovaMiniConfig.enabled` 为
  `false` 时全链路零行为变化）。两种挂载方式并存：`MovaMiniController.showInPage`
  （页内悬浮）与 `MovaMiniController.show` + `MovaMiniHost`（跨路由持久）。支持吸边/
  钳制/安全区避让、惯性拖拽甩出关闭。与系统 PiP 互斥（进入小窗会先退出系统 PiP，
  反之亦然）。

### 拖动预览缩略图

* 拖动进度条或横滑手势时，在进度条上方显示目标时刻的缩略图气泡
  （`MovaPreviewComponent`）。
* 缩略图来源按序：服务端 WebVTT 雪碧图（`<video-url>.vtt`，支持 `#xywh` 裁剪）→
  libmpv 隐藏 `Player` 抽帧兜底，来源链可经 `MovaPreviewConfig.sources` 整体替换。
* 内存 + 磁盘两级缓存；网络策略默认 `wifiOnly`（`connectivity_plus` 探针判定，
  未知连接与桌面一律放行），被拦时静默不请求并发出 `MovaPreviewBlock` 事件。
* `createMovaEngine()` 的 `extractor`/`probe` 默认值为 `null`（不默认引入
  `media_kit_video`/`connectivity_plus` 的静态可达依赖，便于 tree-shake）。要启用
  抽帧兜底与 `wifiOnly` 网络策略，需显式传入
  `extractor: MovaFrameExtractor()`/`probe: MovaConnectivityNetProbe()`；不传
  `probe` 时内核兜底为纯 Dart 的 `MovaAlwaysAllowNetProbe()`，`wifiOnly` 策略不会
  被强制执行（其余网络策略不受影响）。

### 广告编排

* `MovaAdController` 支持按真实业务时序播广告：正片源可延迟解析
  （`loadDeferred(MovaSourceResolver)`），广告位 `duration`/`delay` 与素材时间轴
  解耦（统一 `Timer` 驱动，不查询/依赖 `state.duration`，不做尾部 seek）。
* 按广告位类型决定是否等待就绪（`MovaAdWaitPolicy`，内置 `MovaAdWaitByKind`
  默认 `pre` 否 / `mid` 是 / `post` 否），三层覆盖收在 `MovaAdConfig.waitsFor()`。
* 广告加载失败兜底：`MovaAdFailPolicy`（内置 `MovaAdRetrySkip`/`MovaAdAbandonPod`）
  统一处理打开失败、播放器报错、无首帧超时、预热未就绪四类场景。
* 等待/无缝切换需要宿主同时接入下节的 `MovaSwapEngine` 并开启
  `MovaSwapConfig.enabled`，否则退化为传统"到点直接切"的行为。

### 无缝引擎切换（可选）

* `MovaSwapEngine`：本身实现 `MovaApi` 的代理层，持有生效引擎与预热中的影子引擎，
  就绪后原子换指，把"广告播完回正片"从黑屏/loading 变成逐帧无缝。默认
  `MovaSwapConfig.enabled: false`，关闭时是纯直通代理，行为与不接入时一致。
  `MovaState.renderEpoch` 在切换后递增，用于触发渲染面重新读取 `renderHandle`。
* 预热触发策略（`MovaWarmTrigger`：`MovaLeadWarm`/`MovaEagerWarm`）与就绪判据
  （`MovaWarmPolicy`：`MovaBufferWarm`）两层可插拔；`MovaWarmPlan` 可按预热方向
  分别配置。
* **已知限制**：清晰度切换（`switchQuality`）与 feed 场景的引擎池未接入无缝切换——
  前者已走安全的寄存续播路径但未经过无缝切换本身的验证，后者结构性不适用
  （双画面并存需求）。

### 依赖

* `media_kit` / `media_kit_video` / `media_kit_libs_video`：播放内核。
* `path_provider`：拖动预览磁盘缓存目录。
* `connectivity_plus`：拖动预览的 `wifiOnly` 网络策略探针。
* `screen_brightness`：亮度手势的系统亮度端口。

### 已知限制

* iOS 系统级画中画未实现（见上文）。
* `switchQuality` 尚未接入无缝引擎切换（见上文"无缝引擎切换"小节）。
* `MovaAudioSkin`（封面/歌词/波形专用皮肤）未提供，仅音频场景请用
  `MovaPlayer.surface` 自行传入占位画面。

## 0.0.1

* 初始脚手架 / Initial scaffold.
