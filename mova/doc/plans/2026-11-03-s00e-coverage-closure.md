# S00e：新增原生/组件判据、契约对账与剩余 F14 缺口

**本轮没有达到“15 个验证器缺口清零”的完成要求：仍有 F14 一项未补齐。** 其余 14 项接入新增生产者/规则，其中 F12 仅物理耗电子项需要人工仪表。新增原生判据全部**未上机**，没有新增设备 PASS。F14 的底层异常注入属于验证器实现缺口，未转 manual，也未称为环境阻塞。

只修改本 worktree 的 `mova/example/` 和 `mova/doc/`。本人执行，未转派；未修改 lib/test，未运行 adb、Gradle、APK 构建/安装；未在其他 worktree 执行 Git、构建或写文件。无分支切换、stash 或 push。每个实现逻辑块已单独提交，提交列表见文末。

## 生产者和规则

| 缩写 | 文件 | 用途 |
|---|---|---|
| W | [s00e_widgets_test.dart](../../example/test/s00e_widgets_test.dart) | 真实组件树、指针、点击、PNG 解码和守卫组合；使用公开 API/testing.dart |
| N | [s00e_native.dart](../../example/lib/verify_auto/s00e_native.dart) | 默认原生工厂、实际挂树、native 属性/日志、宿主采样握手 |
| T | [s00e_trace.dart](../../example/lib/verify_auto/s00e_trace.dart) | 透明 BinaryMessenger 转发，记录真实 VideoOutputManager.Create/Dispose 调用与成功回包；不替换插件处理器 |
| H | [coverage_s00e.py](../../example/tool/coverage_s00e.py) | 将来的显式设备跑批入口；读取 settings/dumpsys/proc/IPC，保存原始文本，解析不到保留未知 |
| C | [s00e_contract.dart](../../example/lib/verify_auto/s00e_contract.dart)、[s00e_contract_test.dart](../../example/test/s00e_contract_test.dart) | 新契约公开测试内核生产者、真实默认 UI 探档/错误遮罩 |
| R | [matrix_rules.json](../../example/tool/matrix_rules.json) | 每条新增必需 CHECK 的 assertions；重新比较原始输入，不能只凭 pass 单值通过 |
| I | [s00e_rules_inventory.json](../../example/tool/s00e_rules_inventory.json) | 15 个编号逐条 CHECK → 文件 → assertions 索引，包含共享的新契约要求 |

`main_coverage_api.dart` 增加宿主 ack 和可挂真实组件的 probeTree；`main_coverage_suite.dart` 提前安装一次透明 binding，API 入口复用现有 binding。默认页面行为不变。`coverage_new.dart` 注册 s00eNative/s00eContract。manifest 仅在原末尾锁屏批次前集中追加三个批次：两个单文件离线入口与一个宿主入口；**run_matrix.py 未修改**，既有 CP0/CP1 批次未调整。

## 15 个编号逐项结果

表中的“接入”表示生产者和必需规则存在；不表示设备验收通过。**每项新增判据均未上机**。详细具名 CHECK 和完整断言以 I/R 为准，未删除既有必需子项。

| 编号 | 新增 CHECK / 文件 | 判定条件及预期证据形态 | 结果 |
|---|---|---|---|
| A7 | `A7.native.trace` / N；保留原 `A7.retry.*` | mpv 自己写的日志中解析 `Run command: seek` 目标参数，目标 12 秒调用须为 2–3 次；独立 native seek=0 故障注入至少一次；seeking=no 且原生落点 <1 秒至少一次；最终 seeking=no、落点 12±0.5 秒。R 从日志重新数目标调用，并从原始序列重数偏离读回，不采信伪造 count。另需新 `CONTRACT.rejectedOpen` | 已接入，**未上机**。这是原生落点置换后的真实重发实验，**不是自然丢 seek 复现**，也不是替身调用次数；自然偶发失落仍需后续设备记录 |
| A13 | `A13.native.{false,true}` / N/H；保留原锁定组件测试 | 未锁→锁定→解锁三个阶段，每次真实两侧竖滑前后读 `settings screen_brightness`、目标窗口 screenBrightness、STREAM_MUSIC 当前输出设备音量。锁定后三者不变；未锁/解锁后窗口亮度和音量实际增加，全局设置不变。false 至少两份证据 | 已接入，**未上机**。系统设置与应用窗口亮度分别保留，不混淆作用域 |
| C3 | `U6.map.*`、`U6.disabled.*`、`U6.dvr.*`、`U6.douyin.*` / W；共享 A13 native | 水平映射 none/volume/brightness/seek × VOD/live × allowWhenLive；真实禁用双击/双指，DVR 可拖与禁拖；已有左右交换、锁定和 maxZoom 保留。预期值和调用/状态前后值均在 CHECK。allowWhenLive 只限制 seek，亮度/音量仍可用 | 已接入，**未上机**；离线组合通过 |
| U1 | `U1.native.{surface,player.mounted,borrowed,player.disposed,view.lazy,view.source,view.disposed,feed}`，共享 `U9.native.{ticker,route}` / N/T | Player 自定义 surface 无原生视频分配；默认 surface 真 Texture；卸载借用 API 后仍可 open；显式 dispose 才释放。View null 不建，换源只一个引擎/纹理且 path 等于新地址，卸载后 open=false。Feed poolSize=1 真 PageView 换源复用并随卸载释放。每份保留真实插件调用和回包，R 从 calls 重数创建/释放，核对卸载后无 Texture | 已接入，**未上机**。真实路由、Ticker 自动暂停与 path 不变联合对账 |
| U4 | `U4.live.*`、`U4.throttle.window`、`U4.preview.{render,release,image,imageReleased}` / W | 不可拖直播无 Slider；DVR 量程 300000，回看显示时移/-01:05，点击回边缘 seek=300000。节流窗口保留 11 秒首值/窗口内仍 11/尾值 13。预览实际解码 PNG，RawImage=1×1，显示宽160和00:25；释放后 RawImage=0。原 seek 松手提交判据保留 | 已接入，**未上机**；不是只有占位气泡，实际 PNG 渲染用例通过 |
| U5 | `U5.{fit,quality}.contract` / W；保留其余 HUD/播放倍速 | 默认 HudLayer 在 fit/quality 时 Text 列表为空，符合现行“不显示这两类徽标”契约；保留 volume/brightness/seek/zoom 和六档倍速。R 同比 actual/expected 并钉住 expected，不能一起改造假 | 已接入，**未上机**；无人工项 |
| U6 | 与 C3 共享完整新组合；`U6.douyin.{tap,double,drag}` / W；A13 native | Douyin 单击暂停，双击点赞/计数/真实心形，横竖拖不下发内核动作；通用与 Douyin 独立挂树，不复用同一结论。禁用双击/捏合及 DVR 组合由实际指针驱动 | 已接入，**未上机** |
| U7 | `U7.subtitle.{empty,cue,expired,start,stop}`、`U7.ad.{countdown,remaining,click,skippable,skipped}`、`U7.{like,comment,share,social,info}.*` / W；共享既有 C8.now | 字幕真实文本出现/过期，菜单启停实际 service 与图标；广告按媒体 position 从5到3，再到跳过按钮，点击回调与跳过后 content URI 对账；点赞数/图标和评论、分享、头像、关注回调逐值记录；已有弹幕/NextUp 必需证据保留 | 已接入，**未上机**。这些结构/行为均可自动验证，**未把整项转 manual**；未以 STT 替身证明识别模型质量 |
| U9 | `U9.{ticker,route,inactive}.{none,pip,mini}` / W；`U9.native.{ticker,route,lifecycle.*}` / N/H | 测试内核下 routeObserver/Ticker/inactive 快照与三种豁免组合；原生 View 真路由覆盖/Ticker 暂停后恢复且 path 不变；宿主 HOME/返回触发真实生命周期。PiP 必须 native pinned=true 且 enter 成功；mini 必须实际 host showing；后台暂停属性与播放状态符合豁免 | 已接入，**未上机**。无 PiP/未知窗口格式时对应 CHECK 未知，不推断 PASS |
| F9 | `F9.native.{ui,decoder,comparison}` / N/H | audioOnly 默认工厂，真实皮肤图标/手势音量/常驻封面，handle=null、size=0、Texture=0。通过公开 source mpvOptions 启用 mpv IPC，宿主读 vid=no/false、video-dec-params=property unavailable；保留原始 JSON 回复。CPU 从原始 /proc ticks 和 native time-pos 重算（媒体跨度≥2秒），audio≤video×1.1；RSS audio≤video | 已接入，**未上机**。不为读音频属性偷偷创建 VideoController；IPC 未编译/不可读时保持 BLOCKED |
| F12 | `F12.native.background` / N/H；保留 audioCounters；`F12.power.external` 人工子项 | 默认音频在真实后台继续产生媒体进度；目标 pid 的音频 session=started，保留 RSS/线程/句柄/PSS/CPU 与原始 audio/window/meminfo/batterystats/proc 文本。CPU 单调、媒体进度前进；仅物理能量另需仪表编号、相同控制条件、≥120秒媒体、audioJ≤videoJ | 自动部分接入，**未上机**。**仅功率测量子项 manual**，自动部分未移走，缺任一仍不能整项 PASS |
| F13 | `F13.bounded.{40,60,80,100,disposed}`、`F13.native.isolation` / N/H；保留 F13.disposeFrames | 真三引擎池 100 次切换；预热20后各采样 RSS 增量≤32MiB/线程≤2/句柄≤8，池/创建数≤3；dispose 后池0，较基线 RSS≤64MiB/线程≤4/句柄≤16。R 直接算读数差，不信生产者 ceilings。另三个真实挂树引擎，一路404其他两路错误0、继续播放。既有原生 FrameTiming 覆盖销毁区间且相邻 vsync<100ms | 已接入，**未上机**。这些是明确验收预算，非声称已测得的分布；设备实测可能严格 FAIL |
| F14 | `F14.native.teardown` / N/T；保留五组 disposed；共享既有客户端数据 | 三个真视频输出创建/释放均为3，原始调用成功回包重数，dispose 后三个 open=false；多引擎播放失败隔离已有 F13 证据 | **仍未补齐**，**未上机**。保留 `F14.coverage1`，不把普通播放失败当成 backend.poll 等异常 |
| N12 | `N12.native.isolation`（12份）/ N | 先确认旧404在真实默认引擎产生错误/失败事件，立刻 open 健康源；新 open accepted，10个原生样本 path 全等健康地址、error全null、playing全true，新窗口无失败事件；保留 native time-pos 原值。旧样例只靠替身 restart 的归零项仍保留，但不能替代此组 | 已接入，**未上机**。不会先取消旧请求再把“根本没发生旧失败”的空场景算隔离成功 |
| N13 | `N13.beforeOpen.*` / s00d_native；`N13.video.{true,false}` / N/T；修改 `N13.clients.*` | 五组首次 open 前客户端0，之后统一1，由 client-list 名称重新计数。真实插件 VideoOutput 分配：挂树前0，视频挂树后1，音频0，销毁成功回包与分配相等；原始 calls 必须重新重数 | 已接入，**未上机**。这是原生视频输出分配/释放计数，不伪称 Dart 堆分配器报告 |

## F14 尚缺的实现及限制

现有 `test/core/kernel/mpv_event_pump_test.dart` 的 I0–I11 包括 ready 未完成时销毁、restrict/arm 期间重入 dispose、先注销通知再 destroy 的顺序、wake 排空/风暴、回调抛出后继续排空、poll 抛出后停止、createClient/ready/arm/destroy 抛出容错、SHUTDOWN 停止及枚举 reason 0/2/3/4/5。此次真实工厂观测只覆盖其中的外部资源/稳定性/多引擎子集。

这些底层对象与 backendFactory 没有从 `package:mova/mova.dart` 或 `package:mova/testing.dart` 暴露可注入工厂。遵守“不改 lib/test、验证页只用公开 API、不用 visibleForTesting”的限制下，本轮没有写出它们的完整注入生产者。**这不是缺 adb、设备或仪表，不能转 manual。** 目前也没有用源码扫描、替代泵、无效 native command 或普通404伪装成对真实泵内部异常路径的验证。尚需可用的公开 backend 测试端口，或另行允许在 example 单文件测试中直接测试已有内部泵；本轮没有擅自扩展权限。

## 真缺环境的人工子项

F12 耗电缺少受控外置功率计/经过校准的电荷或能量计，以及相同屏幕、网络、媒体时长条件下的音视频物理能量对照。batterystats 是系统估算，进程 CPU/RSS 不是设备能量，不能替代。R 仍要求 `F12.power.external`，CHECK 应带 meterSerial、audioJ/videoJ、mediaSeconds、sameControls；本轮没有伪造此 CHECK，也没有将 F12 整项加入 manifest.manual。

原六个 manual A31/C7（真实识别模型/服务及导出）、C2（历史媒体服务）、F15（可控 WHEP）、N22（专用 debug VM/assert marker）、N18（mini/guard-off 专包复核）保持原样。U7 没有新增人工项：此任务的渲染属性/点击要求已有自动生产者。

## 契约变更对账表

设计代号 A12/A16 与矩阵 setZoom/setOrientation 编号不同。依据为本仓库对象库中的编排提交；没有去其他 worktree 执行 Git。

| 编号/子项 | 旧判据 | 新判据/验证入口 | 依据提交 |
|---|---|---|---|
| F14、N13、N5；F7/E.MovaFirstFrame、N12、N23；C13/E2 的观察成本 | qoe:false/reporterOff=0客户端；依赖 recovery/QoE 启动 | 首次 open 前0，之后基础 END_FILE 共用1；未开池引擎0。poster/precise/QoE 才观察 RESTART（共用该客户端）。修改 N13 assertions/生产者，保留 N5 分流 | `01b21d3e`；尝试隔离补充 `d3c0781d`、`d460e60a` |
| A2.error、A5、A19、A28、A32、C14、E.MovaErrorEvent/PlayFailure、F4/F8、N6/N19/N23、皮肤错误遮罩 U2 | 任意内核 error 写 state.error/直接显示错误对象 | 只有终结错误写 state.error；普通日志仍发 fatal:false/钩子；遮罩用 MovaStrs.playbackError。`CONTRACT.error.{nonterminal,terminal,overlay.*}` | `af6e40c3`、`543505d4`、`0cf29b1d` |
| A17、C4、U3、F3、E.MovaQualityListChange/QualityChange | 默认 UI 单独探测；只看显式 loadQualities | probeVariants 默认true，就绪后引擎自探测；false关引擎和默认UI自动探测，显式加载有效。`CONTRACT.defaults/probe.{true,false,uiOff}` | `00699976`、`8aad4b48` |
| A5/A6/A7/A17/A19/A20/A28/A32、F3/F8、N8/N19、E.MovaRecovered/Failover | 以原 source 重播；被拒 open 也使 play/seek 失效 | 按实际有效加载地址/headers/options/意图重放；被拒 open 保留在途 play/seek。`CONTRACT.replay.{retry,edge}`、`CONTRACT.rejectedOpen`；既有广告/恢复观测继续必需 | `e2968196`、`7416b960`、`0e0b84ca` |
| A17、C4、F3 自动档 | 期望 mpv auto 在限速夹具自己降档 | manageAuto 默认false；显式开启才由 mova 接管。`CONTRACT.defaults` 钉住默认值；保留手选档位 ABR 规则，不据 CP0 的 auto 停最高档报缺陷 | `3daa36aa` |

`doc/ACCEPTANCE-MATRIX.md` 已直接修订 A5/A17/A20/C4/F8/N6/F12 相关行、F14/N5 的旧客户端文字、H72 的历史零客户端表述及 U5 fit/quality 契约；文末增加“契约变更记录”。S00d reporterOff 存疑段落已明确澄清作废旧0客户端口径。对未在当前快照运行到的新实现分支，必须在合并后重跑；此次不能用旧快照来宣称新设计 PASS/FAIL。

## 离线校验与 r1030 重放

- `python -B example/tool/test_run_matrix.py`：49 项通过；覆盖合成音量/窗口/proc/IPC 样本、未知字段、原生调用重数、资源/CPU 重算、缺 CHECK/只给 pass=true 不通过。
- `python -B example/tool/run_matrix.py --check`：52 batches / 135 IDs / 6 整项 manual，通过；无设备操作。
- `example` 下 `flutter test test/s00e_widgets_test.dart --concurrency=2 --no-pub`：11项通过、90条 CHECK。真实原始记录另见 [s00e-widgets-checks.jsonl](../../example/tool/testdata/s00e-widgets-checks.jsonl)。
- `example` 下 S00e contract 单文件：2项通过，**11条 CHECK 为未知**。本快照缺 probeVariants/manageAuto，新契约路径没有实际运行到；通过的是旧 API 缺失时的保守分支，不是产品验收。
- S00d 单文件回归：widgets 13项通过，contract 1项通过。所有 Flutter 测试均逐个单文件运行、concurrency=2，没有和 analyze 同跑。
- example `flutter analyze --no-pub`：最终40条，与基线一致，新增0；原 rerun6/rerun7 的 visibleForTesting warning 保留。

使用原始 `example/tool/coverage_evidence/matrix-r1030` 运行 `run_matrix.py --replay ... --run-id r1030 --baseline doc/plans/2026-11-03-matrix-replay-r1030.json`。原基线/原报告字节保留，结果另存 [S00e JSON](2026-11-03-s00e-matrix-replay-r1030.json) 与 [完整逐项 Markdown](2026-11-03-s00e-matrix-replay-r1030.md)。离线新 CHECK 没有混进 r1030。

| 分类 | 数量 | 说明 |
|---|---:|---|
| PASS | 58 | 旧原始证据仍满足全部新要求的项目；没有新增设备 PASS |
| FAIL | 5 | A2、C16、E.MovaBufferChange、E.MovaSizeChange、E.MovaQualityChange |
| BLOCKED：已接入判据待上机/合并新契约后重跑 | 64 | 包含旧数据没有的新增原生/组件 CHECK；A25/C15/F6/N20 的 H42 定性不变 |
| BLOCKED：验证器仍未补齐 | **1** | **F14，目标0未达成** |
| BLOCKED：manual 真缺环境 | 7 | 原6项，加 F12 的物理耗电子项；F12 自动 CHECK 仍为必需且 r1030 同样缺这些读数 |

相比 S00d 的69/5/61，A17、A20、A32、C14、E.MovaErrorEvent、F3、F4、F8、N6、N8、N19 这11项由 PASS 转 BLOCKED，原因是新增契约必需 CHECK 缺失，**没有新增产品 FAIL**。A2 与三项事件一致性保持严格 FAIL，预期 A28 修复后复测；C16（严格 TLS 拒绝正确 IP SAN）和 D03/H42 保持原定性。

## 提交

| hash | 逻辑块 |
|---|---|
| `79bff01` | 客户端规则与五项新契约对账 |
| `f1bb3a0` | 组件树/手势/字幕广告/守卫基础 |
| `4d6745e` | 宿主解析、透明纹理调用、原生锁定/旧文件观测 |
| `d76fb85` | 原生所有权、生命周期、池资源边界/隔离 |
| `d1a513d` | 真实预览图片解码、禁用/DVR/字幕菜单组合 |
| `ddf1fd1e` | 音频 IPC、后台会话/资源、音视频开销对照 |
| `f3f4777a` | 独立 mpv 日志与原生落点偏离后的真实重发 |
| `9336cfeb` | 新契约公开测试内核及默认 UI 验证入口 |
| `c2f5c3cd` | 集中注册批次、逐 CHECK 索引、矩阵/S00d 文档修订 |
| `64c48a10` | 将契约测试平台端口隔离为无设备默认端口 |
| `d76a113b` | 畸形数组证据保守 BLOCKED 与回归 |

本报告及重放结果另作一次文档提交。F14 剩余实现原因见上文；本报告不将该任务标为完成。
