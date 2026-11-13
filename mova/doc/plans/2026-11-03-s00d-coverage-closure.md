# S00d：新增判据、pod2 更正与未完成项

**本轮未完成全部 32 项，也不满足 S00 完成判据。** 17 项已移除 `coverage1`，接入整项必需规则；其余 15 项仍保留占位，不能改称环境阻塞。新增原生判据全部**未上机**。离线用例通过不代表原生/设备验收通过。

本轮只修改当前 detached worktree 的 `mova/example/`、`mova/doc/`。未修改 `lib/`、`test/`，未转派，未执行 adb、APK 构建/安装或 Gradle。未在其他 worktree 执行 Git 命令、构建或修改工作树文件。

实现提交：`aaec590`（`test(mova): 增补验收观测并修正双广告等待对照`）。

## 文件与证据入口

| 缩写 | 文件 | 用途 |
|---|---|---|
| R | [s00d_receipt.dart](../../example/lib/verify_auto/s00d_receipt.dart) | 每个实际 api 独立订阅 states/progress/events；接收时对账 |
| P | [s00d_contract.dart](../../example/lib/verify_auto/s00d_contract.dart) | 公开测试内核的 seek 丢弃、QoE 四分、阈值、错误上报 |
| W | [s00d_widgets_test.dart](../../example/test/s00d_widgets_test.dart) | 真实组件挂树、点击/指针、渲染属性与所有权 |
| N | [s00d_native.dart](../../example/lib/verify_auto/s00d_native.dart) | 默认 createMova + 实际挂树的 MovaPlayer；原生属性读回 |
| S | [s00d_resources.dart](../../example/lib/verify_auto/s00d_resources.dart) | 进程计数、audioOnly、实际 Flutter FrameTiming |
| APP | [coverage_new.dart](../../example/lib/verify_auto/coverage_new.dart) | 注册 s00d/s00dNative/s00dResources；保留原 qoe/stallRelease/feed 入口 |
| RULE | [matrix_rules.json](../../example/tool/matrix_rules.json) | 重新比较 expected/actual、numbers 和原始 REPORT；不采信 pass 单值 |

**完整的“编号 → 每个 CHECK id → 生产者文件”索引见 [s00d_rules_inventory.json](../../example/tool/s00d_rules_inventory.json)。** 下表用族名压缩展示；RULE 中每个必需 CHECK 均有 assertions。已有的具名 CHECK、原始事件与日志判据保留。

`main_coverage_api.dart` 的 `observe()` 接 R；`coverage_api_batches.py` 注册三个新增 API case。没有修改 `matrix_manifest.json` 或 `main_cp0_suite_verify.dart`。离线组件入口为 [coverage_s00d_offline.py](../../example/tool/coverage_s00d_offline.py)，每次只运行一个 example 单文件测试，固定 `--concurrency=2 --no-pub`。只有测试进程成功退出才发布 `status=done`；失败不打印虚假的 DONE。

## 32 项逐编号清单

“整项接入”只表示必需规则和生产者已连接，缺任一证据仍 BLOCKED。所有下述新增设备判据均未上机；缺口列明确保留真正未完成的验证器工作。

| 编号 | 新增 CHECK / 文件 | 条件与预期证据形态 | 状态与缺口 |
|---|---|---|---|
| A2 | `A2.mova.receipt`、`A2.cutover.receipt` / R | 每个 EVENT 留 expected/actual 两份完整快照：30 个 MovaState 字段及独立 progress.position，共 31 项；载荷字段覆盖相应 expected。quality/qualities 留 label、URI、带宽、宽高、isAuto，缺 key 不通过。Seeked.position 严格对接收时 progress。无单独事件载荷的 intent/epoch 等对最新接收 states 序列；不把 playing 当 intent | 整项接入；**未上机**；仍 FAIL，预期 A28 后转 PASS。普通原生播放器待上机区分 |
| A7 | `A7.retry.{0,1,2,100}` / P | 控制丢弃次数，排空 Zone Timer 队列，保留 targets、calls、progress、settled；调用序列应分别为 1/2/3/3 次 12000ms | **未补齐**；离线通过，未上机。仍缺独立原生 seek 调用/重发 trace；不能以替身次数替代 |
| A11 | `A11.declared`、`A11.once` / W；`A11.render.{contain,cover,fill}` / N | 声明式 fit 只应用一次；真实 Video.widget.fit、state.fit、解码尺寸、实际 viewport、applyBoxFit 源/目标尺寸逐值核对。contain 不裁源，cover/fill 填满 viewport，fill 保留完整源 | 整项接入；离线部分通过；**未上机**。画面判据使用实际挂树 Video 的渲染参数与几何，不伪称新截图结果 |
| A13 | `A13.lock.{false,true}`、`A13.unlock.{false,true}` / W | 实际 DefaultUiKit 锁定后，亮度/音量不变，内核调用增量 0；解锁状态恢复 | **未补齐**；离线通过，未上机。尚缺锁定前后原生系统亮度/音量读回 |
| A26 | `A26.{persistent,page,setRect,tap,hide,close}` + `U8.*` / W | A/B 挂载互斥、仅一个窗口；拖动中坐标移动；松手吸边；甩动不误关；转屏矩形等于 remap + clamp；hide 不触发 close，close 恰一次回调且 mini=false | 整项接入；离线通过；**未上机** |
| C3 | `C3.{left,right}.{false,true}` + `U6.*` / W | 默认及左右交换后的亮度/音量、单击、双击 ±10s、横向 seek、双指 maxZoom、锁定与长按现状 | **未补齐**；离线通过，未上机。仍缺水平轴动作重映射、直播/禁用组合和 Douyin 独立手势整组 |
| C5 | `C5.{start,reset,auto,sticky,hide,paint}.{true,false}.{true,false}`、`C5.defaults` / W | 四种 showOnStart/autoHide 组合；重置自动隐藏窗口、sticky 与显式 hide；实际 AnimatedOpacity 的 duration=140ms、隐藏 opacity=0；默认值逐值核对 | 整项接入；离线通过；**未上机**。调度推进不是判据，判据是状态与组件属性 |
| C6 | `C6.spawn.{false,true}`、`C6.{scroll,unique,retired}` / W | 固定 items 到点各生成一次，无 TextField；同批不同轨；实际文字 x 递减、轨道 y 分离，保留原坐标供 assertions 比较；动画结束移除 | 整项接入；离线通过；**未上机** |
| C8 | `C8.{card,cancel,auto}.{true,false}`、`C8.now` / W | 真 NextUp 可见/取消；两种 autoPlayNext 的 Done 分流；立即播放后 index 与 kernel URI 都指向第二集 | 整项接入；离线通过；**未上机** |
| C12 | `C12.defaultOff` + `A26.*`、`U8.*` / W | 默认无窗口；同一组实际挂树拖动、吸边、甩动、转屏矩形与关闭读回，不复制另一份结论 | 整项接入；离线通过；**未上机** |
| C13 | 保留 `C13.off/defaultHeartbeat`；新增整组 `F7.*` 及原生 REPORT / P、N、APP | qoe:false 零 QoE、默认零 periodic timer；qoe:true 四分结算、TTFF/卡顿/阈值/heartbeat；原生 sample 属性与首帧 restart；每种原生终态必须有完整 REPORT/priority | 整项接入；公开用例通过；**未上机** |
| C17 | `C17.headers.{one,two}` / N；保留 `C17.sameAs/pick`、N4/N19 | loopback 代理记录每次真实 X-S00D 请求头，必须全部相等；原生 http-header-fields 读回；lavf 仍含 probesize 与 protocol_whitelist；缺请求或属性不能通过 | 整项接入；**未上机** |
| U1 | `U1.{surface,borrowed,feedOwned,feedSource,feedDispose}` / W；并保留 N17 分支观测 | Player 自定义 surface、借用不销毁；Feed 一个池播放器换源并随卸载销毁；View 自建/换源/卸载数据见 N17 | **未补齐**；离线通过，未上机。尚缺三种组件的真实纹理挂卸及 route/autoPause 联合原生资源对账 |
| U3 | `U3.{title,pipHidden,fit,fullscreenOn,fullscreenOff,qualityCount,qualityMenu,qualitySelect,pipClick,directionDesktop,directionMobile,direction1,direction2}` / W | 实际按钮点击；公开 fetcher 提供 master，不用 debugSetQualities；菜单三档可见、选中后 state/kernel URI 一致；方向仅移动端，PiP 支持态经公开端口进入 | 整项接入；离线通过；**未上机** |
| U4 | `U4.{disabled,enabled,drag,commit,label}` / W | duration=0 时 Slider 禁用；拖动只改 previewAt/dragging，不 seek；松手提交 35000ms；实际位置文本更新 | **未补齐**；离线通过，未上机。直播底栏、节流窗口与真实预览气泡渲染仍缺 |
| U5 | `U5.{play,pause,rates,volume,brightness,seek,zoom}` / W | 实际中心按钮、六档循环；四种 HUD 的真实文本值 | **未补齐**；离线通过，未上机。fit/quality HUD 的整项显示契约与 CHECK 未落实；没有据现有枚举假造显示结论 |
| U6 | `U6.{tap,doubleRight,doubleLeft,horizontal,pinch,longPress,region}.{false,true}` + C3/A13 / W | 指针双击 ±10s、拖动、双指封顶 2、单击显隐；锁定经实际 UI 套件屏蔽；长按保持当前未实现倍速的现状 | **未补齐**；离线通过，未上机。与 C3 相同的禁用/直播/水平动作重映射/Douyin 组合仍未实现 |
| U7 | 本轮未新增 | 仍需字幕、广告倒计时/跳过、FeedSocial 渲染/点击全套；C6/C8 子证据不能替代整项 | **未补齐**；属于实现工作，不是环境阻塞 |
| U8 | `U8.{drag,snap,fling,resize}` + A26 / W | 真实指针保持按下时测坐标，再松手测边界；甩动不关闭；尺寸变化后与 remapProportionally/clamp 输出一致 | 整项接入；离线通过；**未上机** |
| U9 | 本轮未新增整组 CHECK | 尚需 route/Ticker/inactive 快照与 PiP/mini 豁免联合生产者及原生生命周期序列；N21 的无自动暂停路由往返不能替代 | **未补齐**；属于验证器工作，不是“待上机” |
| F7 | `F7.{false,true}.{ended,stopped,failed,abandoned,truncated,disabled}.*`、`F7.heartbeat` / P；`F7.nativeFirstFrame/nativeSample` / N；REPORT / APP | 逐终态 endCount=1、reason、stallCount/毫秒/观看量/比例；首帧仅一次、native=true 时 fallback 不能抢先；truncatedBelow=0 对照；原生 ended/stopped/failed/abandoned/truncated 及 rebuffer 报告都必须齐备 | 整项接入；公开用例通过；**未上机** |
| F9 | `F9.nativeAudio` / S | 默认 createMova(audioOnly:true)，十个以上实际 progress 样本；playing=true、handle=null、size=0x0、原生会话 audioOnly=true | **未补齐**；**未上机**。仍缺原生无视频解码读回、真实 UI 套件/手势/封面与视频模式 CPU/内存完整对照 |
| F12 | `F12.audioCounters`、`S00D_POWER` / S | Windows Get-Process 或 Linux/Android /proc 读 RSS/CPU/线程/句柄；CPU 单调；电荷/能量/电流/电压原值或 null 留存 | **未补齐**；**未上机**。音频焦点抢占反应的生产者未写；硬件耗电缺受控电荷/能量计或外置功率计及对照，不以 RSS/CPU 代替耗电 |
| F13 | `F13.resources.{20,40,60,80,100,disposed}`、`F13.disposeFrames`、复用 `A29.poolReclaimed` / S、APP | 真实 audioOnly 三播放器池 100 次 + 快速激活；创建/池数量≤3；保留 RSS/CPU/线程/句柄；销毁后池=0、所有 open=false；有起止覆盖的原生 FrameTiming，相邻 vsync 间隔严格 <100000µs | **未补齐**；**未上机**。尚未制定并实现基于这些读数的 RSS/线程/句柄收敛判据，三播放器原生事件串扰 CHECK 仍缺；不是缺采集工具 |
| F14 | `F14.disposed.{off,recovery,precise,reporterOff,qoe}` / N；N13 客户端读数可交叉查看 | 默认工厂、实际挂树、每个配置销毁后 open=false；没有无界面反复创建 VideoController | **未补齐**；**未上机**。I0–I11、原始 RESTART 个数/END_FILE 枚举、销毁稳定性和 backend 错误隔离仍缺完整生产者 |
| N5 | `N5.restart.{off,recovery,precise,reporterOff,qoe}`、`N5.endFile` / N | 暂停 open 的 FirstFrame 信号分别对账，recovery-only 不走 restart；真实 404 的 MovaPlayFailure.kind=nativeEndError。没有调用 movaObserveFlags 或其他 @visibleForTesting 方法 | 整项接入；**未上机** |
| N12 | 本轮无新增；保留 `N12.openReset/freshRestart` | 保留旧归零/新 RESTART 子项；仍缺真实旧 RESTART 在新 open 中被隔离的事件生产者 | **未补齐**；不是缺环境，不把替身 freshRestart 当成旧事件隔离 |
| N13 | `N13.clients.{off,recovery,precise,reporterOff,qoe}` / N | 原生 client-list 原文、解析名称与 mova_qoe_ 前缀数量；规则从名称重新计数，伪造 count 不能通过；JSON/纯文本列表外格式保留 unknown | **未补齐**；**未上机**。尚缺 VideoController 懒创建的独立分配计数与 release 回调/销毁计数整组，client-list 不能证明懒创建 |
| N15 | `N15.{cover,fade,renderFade,renderFadeDone,recover,noSize,feedCover,feedFade,feedRecover}` / W；另需 `F7.nativeFirstFrame` / N | 首帧前 opacity=1；首帧后 target=0/duration=300，真实 RenderAnimatedOpacity 中间值严格在 (0,1)，结束=0；换源立即重盖；无视频尺寸常驻；Feed 换源同样重盖 | 整项接入；离线通过；**未上机** |
| N17 | `N17.{lazy,owned,same,alternatives,null,options,error,dispose}` / W | null 不建播放器；sameAs 不重开，备选变化重开；null 暂停；options 新建并销毁旧内核；异常回调一次且无未处理异常；两个内核各销毁一次 | 整项接入；离线通过；**未上机** |
| N21 | `N21.staged` / W；`N21.guard.{windows,android}` / N | 按源选项一次暂存、下一源恢复空值；真实 Video 上的 SnapshotGuard 属性 Windows=true、Android=false；各 20 次真实路由往返，epoch 与原生 path 不变，原生崩溃/中途退出不能产出完整 CHECK | 整项接入；**未上机**。Windows 当前 API 验证页可承载该专门场景；两平台缺任一证据均 BLOCKED，不另列 manual |
| N23 | 复用 F7 整组；`N23.custom`、`N23.policy.*`、`N23.error.{stream,file,ffmpeg,vd,ad,cplayer,other}.{false,true}` / P | nativeRestartAvailable 分支、truncated 开关、四分；真实 reporter 的 error/fatal/code/kind/priority/sessionId 完整原值；致命 immediate、非致命 batched；custom 参数=17 | 整项接入；公开用例通过；**未上机** |

## A2 / D01 与 D02、D03

A2 和 `E.MovaBufferChange`、`E.MovaSizeChange`、`E.MovaQualityChange` 继续严格 FAIL。原始代表仍是 `final-hls.json:records[961]`，BufferChange(false) 到达时 state.buffering=true。已确认 cutover 的 state/events 双订阅链有投递顺序缺陷。**预期 A28 后转 PASS**；建议修法是“A28：代理把 state 与 events 合并为同一投递序列 + 普通播放器一致性单测”。本树不改产品代码。

旧 r1030 的 player hash 无法区分两种实现，不能据此声称普通原生播放器也有同样缺陷。R 新增两组具名 CHECK 作为后续区分入口。S00c 的公开替身用例可以制造异步接收差异，但这不构成普通原生播放器的设备证据。S00c 单文件回归只检查它自己生产的 public-testing-kernel/loopback-http CHECK；A2 审计仍原样保留、仍进入矩阵，不因该回归通过而抹去 FAIL。

D02 保持“严格 TLS 拒绝正确 IP SAN，原生层待定位”；D03/H42 保持“存疑待产品面决策，矩阵 §5.3 第 8 条”。本轮没有使用属性恢复或资源计数覆盖其未知语义。

S00e 契约澄清（2026-11-03）：上述 reporterOff 存疑已由编排 A14 新设计消除（01b21d3e）。首次 open 前 0 个弱客户端，open 后基础 END_FILE 共用 1 个，qoe:false/reporterOff 也一样；RESTART 只在 poster/precise/QoE 时额外观察。原“reporterOff 组要求 0”口径作废，不据此定性产品缺陷。S00e 已修改生产者和 assertions；新判据未上机。

## pod2 更正

[cp0_pod2_auto.dart](../../example/lib/verify_auto/cp0_pod2_auto.dart) 现在先跑显式 `MovaAdWaitByKind(pre:true)`，再跑默认 `pre:false` 对照。CHECK 分别为 `CP0.pod2.wait.ad2.<run>` / `CP0.pod2.nowait.ad2.<run>`。每条广告分别留 epoch、native path/time-pos、MovaFirstFrame 原始记录与 µs 事件戳，另留第一条广告相对初始 epoch 的变化。取 FirstFrame 时限制当前 epoch，第二条必须晚于第一条；不从上一轮累计日志选事件。

`coverage_cp0.py` 仅修改 pod2 的两个变体和必需字段行，便于与 a5c317f6 合并；主 suite、manifest 均未改。原 cp0 报告已经追加更正：旧 0→0 是默认不等待分支的观测，不能说明 cutoverTo 回落。新增两变体**未上机**，没有新 CP0 基线数字。

## 校验与重放

- `python -B example/tool/test_run_matrix.py`：43 项通过。覆盖新规则缺 CHECK/缺字段/输入篡改、原始客户端重新计数、请求头全量比较、FrameTiming 100ms 边界与真实离线 CHECK 夹具。
- `python -B example/tool/run_matrix.py --check`：49 batches / 135 IDs / 6 manual，通过；没有设备操作。
- example 单文件 `s00d_widgets_test.dart`：13 项通过，120 CHECK；`s00d_contract_test.dart`：1 项通过，173 CHECK；S00c 旧单文件回归 1 项通过。每次 concurrency=2，没有跑 lib/test 或全套 Flutter 测试。
- example `flutter analyze --no-pub`：40 条，与原基线相同，没有新增 issue；含原有 rerun6/rerun7 的 debugSetQualities warning。
- 离线证据另存在 `example/tool/coverage_evidence/s00d-offline/`；[testdata/s00d-offline-checks.jsonl](../../example/tool/testdata/s00d-offline-checks.jsonl) 保存成功运行的原始 CHECK 夹具。未把这些记录复制进 r1030。

重放命令：

```powershell
python -B example/tool/run_matrix.py --replay example/tool/coverage_evidence/matrix-r1030 --run-id r1030 --baseline doc/plans/2026-11-03-matrix-replay-r1030.json
```

另存结果为 [S00d replay JSON](2026-11-03-s00d-matrix-replay-r1030.json)，保留原 S00b 基线文件。新规则缺新设备 CHECK，因此不会凭离线用例把旧 r1030 提升为 PASS。

| 分类 | 数量 | 说明 |
|---|---:|---|
| PASS | 69 | 使用旧原始完整证据；没有新设备 PASS |
| FAIL | 5 | A2、C16、E.MovaBufferChange、E.MovaSizeChange、E.MovaQualityChange |
| BLOCKED：已接入判据待上机 | 40 | 包含原 24 项及本轮新增 16 项；其中 A25/C15/F6/N20 兼 H42 产品语义未决 |
| BLOCKED：验证器仍未补齐 | **15** | A7、A13、C3、U1、U4、U5、U6、U7、U9、F9、F12、F13、F14、N12、N13；上表明确列出剩余工作 |
| BLOCKED：manual 真缺环境 | 6 | 下表；未新增其他整项 manual |

## 保留的六个 manual

| 编号 | 具体缺少什么 |
|---|---|
| A31 | 真实 STT 模型、识别播放器及模型下载服务 |
| C7 | 同上，并需真实字幕/SRT/分块导出证据 |
| C2 | 按 behind 返回历史媒体且可控卡顿的服务 |
| F15 | 可控 publisher、WHEP 信令及媒体网络 |
| N22 | debug VM 构建与 assert marker |
| N18 | mini/guard-off 联动专包及完整复核 |

F12 已能自动读进程与可读的硬件计数，但没有受控耗电/音频焦点整组；F13 已能采集资源与销毁帧耗时，但不能把“采到数”当成“资源有界”。这些剩余实现继续列在 15 项验证器缺口中，**没有以笼统的“待上机”替代，也没有达到用户要求的缺口 0**。
