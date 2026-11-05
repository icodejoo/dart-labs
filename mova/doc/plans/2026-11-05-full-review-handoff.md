# mova：2026-11-05 全量评审遗留交接（注释规范 · generated 文件 · 9 条暂缓 P3 · 真机复验）

> 2026-11-05 · 交接文档 · 读者：**没有本次会话任何上下文的另一个 agent**，拿到就能接着做。
> 依据：`mova/CHANGELOG.md` `Unreleased` 前四条、`mova/CLAUDE.md`「剩余任务」中
> 「2026-11-05 全量评审 P3 未修项」一段、`main` 上 `649d515a`..`9f99d2ca` 共 16 个提交（均已推送 codeup 与 GitHub）。

**目标：** 把本轮「Codex 全量评审 + 主会话终审」里**没做**的条目逐项落地，或明确关闭。
**不做：** 不回头改本轮已修的条目；要动请先看 §6「别改回去」，那里列了本轮刻意定下的语义。

---

## 0. 本轮已完成（别重复做）

- **评审来源**：Codex 对 `mova/lib/src` 分 5 块（A 引擎/状态/事件/模型，B 内核/恢复/待机/守卫，
  C cutover/会话/广告/feed/小窗，D 预览/上报/STT/配置，E UI/platform_impl/testing）只读全量评审，共 69 条；
  opus 逐条对照源码终审：成立 67、误报 2（A1、A6）；定级后 P1 1 条、P2 26 条、P3 40 条。
  原始报告在会话 scratchpad（临时目录，**已不可依赖**），需要的信息都已摘进本文。
- **已修**：
  - P1/P2 全部 27 条（含 C2 唯一 P1：宿主直接 `open()` 换源后旧广告会话不再抢回）及终审附注 C1/C8/A9；
  - 首轮 `/code-review` 遗留 4 条：请求头经 media_kit 全局 URI 缓存串值、`screenshot()` 播放中过早放弃、
    同步事件交付的监听器重入、`MovaFeedPlayerController.pause()` 等待激活；
  - P3 40 条中修 22 条，9 条核实为已不成立/已被前序修复覆盖，**9 条暂缓**（见 §3）。
  - 逐条内容见 `CHANGELOG.md` `Unreleased` 前四条与各提交信息。
- **测试基线 2625 项全绿**，`flutter analyze lib test` 0 issues（本机 `main` 实跑）。
- **未做真机**：本轮全部只有单测，见 §4。

---

## 遗留总览

| # | 项 | 性质 | 优先级 | 需要用户拍板 |
|---|---|---|---|---|
| 1 | 注释规范冲突（项目要求英中双语 vs 全局只要求中文） | 约定 | 中 | **是** |
| 2 | `example/windows/flutter/` 三个 generated 文件未提交 | 杂项 | 低 | 否（按 §2 处理即可） |
| 3 | 9 条暂缓 P3 | 缺陷（窄窗口） | 低 | 部分（D15 改契约） |
| 4 | 真机复验：请求头 HLS、CP2/CP3、本轮行为变更 | 验证 | **高** | 否 |

建议顺序：§4 HLS 请求头复验 → §2 → §1 拍板 → §3。

---

## 1. 注释规范冲突（需用户拍板）

**现状**：

- `mova/CLAUDE.md`「约定」：每个类/方法/函数都要注释，**先英文后中文、空行分隔**；公开 API 带参数/返回/示例。
- 用户全局 `~/.claude/CLAUDE.md`「注释规范」：每个方法、属性、函数、类都要有**简短的中文注释**。
- 两者不矛盾到“二选一”，但评审里大量 P3 是“只有中文、缺英文段”。本轮新代码一律按英中双语写。

**存量数据**（2026-11-05 统计 `lib/**/*.dart` 的 `///` 文档块）：共 3284 块，**只有中文的 1047 块，分布在 145 个文件**。

**方案**（列给用户选，别擅自定）：

| 方案 | 做法 | 代价 |
|---|---|---|
| a | 项目约定改为只要求中文，与全局一致 | 改一行 CLAUDE.md；pub.dev 上的 dartdoc 对非中文用户不友好 |
| b | 维持双语，批量给 1047 块补英文段 | 大量机械改动，适合派 haiku/Codex 分文件批量做，每批 `flutter analyze` |
| c（推荐） | 维持双语为新代码标准，存量不追，改到哪个文件顺手补 | 零额外成本；存量长期不一致 |

拍板后把结论写回 `mova/CLAUDE.md`「约定」第二条，并删掉评审 P3 里所有“注释只有中文”的残项。

---

## 2. generated 文件（之前的结论有误，以此为准）

`git status` 一直显示三处修改：

| 文件 | 实际变化 | 处理 |
|---|---|---|
| `example/windows/flutter/generated_plugins.cmake` | 删除 `FLUTTER_FFI_PLUGIN_LIST` 里的 `sherpa_onnx_windows` | **提交**：`example/pubspec.yaml` 自 2026-10-28 起已屏蔽 `sherpa_onnx`（见其第 33 行注释），删掉才与 pubspec 一致，仓库里那份是过期的 |
| `example/windows/flutter/generated_plugin_registrant.cc` | 仅换行符（LF↔CRLF） | 还原 |
| `example/windows/flutter/generated_plugin_registrant.h` | 仅换行符 | 还原 |

```bash
cd mova
git diff --ignore-cr-at-eol -- example/windows/flutter/      # 确认只有 cmake 那一行
git checkout -- example/windows/flutter/generated_plugin_registrant.cc example/windows/flutter/generated_plugin_registrant.h
git add example/windows/flutter/generated_plugins.cmake
git commit -m "chore(mova): example Windows 插件列表同步 sherpa_onnx 屏蔽"
```

注意：本会话里此前两次说过“建议还原三个文件”，那是错的；若恢复 STT spike（取消 pubspec 屏蔽）再重新生成即可。

---

## 3. 暂缓的 9 条 P3

共同特点：触发窗口窄或需要改契约/原生身份关联，Codex 核实后判“修复风险大于收益”。行号会漂移，以函数名定位。

### 3.1 A11 小窗与全屏、系统 PiP 的互斥只实现了部分方向

- **位置**：`lib/src/core/engine.dart` 的 `setMini`、`setFullscreen`、`enterPip`。
- **现象**：`MovaState.mini` 文档声明与全屏/PiP 互斥，但 `setMini(true)` 不处理已在系统 PiP，`setFullscreen(true)` 不处理已在小窗；
  可得到 `pip && mini` 或 `fullscreen && mini`。`enterPip()` 方向已做（先 `setMini(false)`）。
- **为何暂缓**：系统 PiP 没有主动退出端口（`MovaPipPort` 只有 enter），`MovaMini` 控制器又假定 `setMini(true)` 必然成功；完整修复要联动 UI。
- **建议**：先定“窗口模式迁移”契约（PiP 中请求小窗 → 拒绝并返回 false，还是排队到 PiP 退出后），再统一在引擎里实现一张迁移表；
  `MovaMini.show` 要处理被拒。单测：PiP 中 `setMini(true)` 被拒且 `mini` 仍为 false；小窗中全屏先收起小窗。

### 3.2 B1 END_FILE 可能把旧文件失败归给新尝试

- **位置**：`lib/src/core/kernel/mpv_kernel.dart` 的 `open()`（排空 `_pump` 后设 `_eventAttempt`，再 `_player.open`）。
- **现象**：A 加载中切到 B，B 已绑定尝试号但 media_kit 尚未停掉 A；A 恰在此毫秒级窗口真实报错，`END_FILE(error)` 被记到 B 名下 → B 被误重试或误判终结。
- **为何暂缓**：loadfile 替换旧文件时 mpv 发的是 `END_FILE(STOP)` 而非 error，实际窗口极窄；可靠修复需原生文件身份。
- **建议**：弱客户端多订阅 `START_FILE`，读事件里的 `playlist_entry_id`，把 `END_FILE` 按 entry id 关联到加载尝试，而不是按“排空后的时间顺序”。
  与 B3 一起做（同一套文件身份）。

### 3.3 B3 新源格式探测可能消费旧源的轨道事件

- **位置**：`mpv_kernel.dart` 的 `open()` 里 `_formatProbePending = true` 到真正加载之间（含 `_yieldForMount` 等待渲染面）。
- **现象**：从 WHEP 切到点播，等待渲染面期间旧流刷新 track-list，探测读到旧的 `file-format=whep`，点播被套上直播缓存限制。
- **为何暂缓**：`_yieldForMount` 只在从未挂载时执行，播放中的流极少刷新轨道；同样需要文件身份。
- **建议**：以新文件的 `FILE_LOADED`（或 B1 的 entry id）武装探测，过滤旧文件事件。

### 3.4 B5 待机还原失败后丢失原值

- **位置**：`mpv_kernel.dart` 的 `_restoreKeepAlive()`（先清 `_keepAliveSaved` 再写回 `mute`/`vid`，异常吞掉）。
- **现象**：`mute=no` 写回失败时方法仍返回 true，播放器保持静音；再次退出因原值已丢失不会重试。
- **为何暂缓**：`MovaKeepAliveKernel.exitKeepAlive()` 返回 `bool` 只表达“是否重启了视频”，表达不了“还原失败”；改返回类型是内核契约变更。
  mpv 写 `mute`/`vid` 实际几乎不失败。
- **建议**：逐项确认写回成功再移除保存值；`exitKeepAlive` 改为返回结果枚举（`restartedVideo`/`noRestart`/`restoreFailed`），
  引擎对 `restoreFailed` 走现有的终结错误出口（`_terminalError`）或重试一次。

### 3.5 C6 等待中插预热时丢弃有效的正片结束事件

- **位置**：`lib/src/core/session/session.dart` 的 `_beginAd()`（等待预热时就设 `_landing = true`）与事件过滤处（`_landing` 时无条件丢 `MovaDone`）。
- **现象**：中插贴近片尾、广告还没预热完，正片先自然结束 → `MovaDone` 被吞，后贴片、`contentEnded`、取消待播中插都不执行；预热窗口内正片 fatal 也被吞。
- **为何暂缓**：要区分“正片仍在屏上等预热”和“已进入媒体落地窗口”两个状态，牵动广告事务取消与后贴片编排，局部放行可能干扰后贴片。
- **建议**：拆出 `_awaitingAdWarm` 状态，此状态下仍处理所属正片的 `MovaDone`/终结失败（并取消在途预热）；只有真正提交换指后才进 `_landing`。
  补竞态单测：中插预热中正片 `MovaDone` → 后贴片照常播、`contentEnded` 照常发。

### 3.6 D3 看门狗期限忽略按源覆盖的超时

- **位置**：`lib/src/core/options/recovery_config.dart` 的 `startTimeoutFor`/`stallTimeoutFor`、`lib/src/core/options/timeouts.dart`。
- **现象**：源级 `mpvOptions['network-timeout']=120`、全局默认时，看门狗仍约 65 秒触发恢复，打断本可等 120 秒的请求。
- **为何暂缓**：只在 recovery 开启（默认关）且源级超时大于全局时触发，后果是提前重试；修复要改 engine 调用处的入参（P3 分组时不在该组范围内）。
- **建议**：`startTimeoutFor/stallTimeoutFor` 接收最终生效的源配置（`MovaSource.mpvOptionsFor(...)` 合并后的值），显式 `startTimeout/stallTimeout` 仍最高优先级。

### 3.7 D12 卡顿时长与次数口径不一致

- **位置**：`lib/src/core/report/collector.dart` 的 `_onStallObservation`（先 `_tally.setStalled` 累计原始时长，再问 `_stallPolicy` 是否成立）。
- **现象**：`minStall=1s` 时 10 次 100ms 抖动：无 rebuffer 事件、`stallCount=0`，但 `stallMs` +1s，rebufferRate 被抬高。
- **为何暂缓**：改动会影响心跳、未结束卡顿、卡顿率的上报口径，属于上报契约变更。
- **建议**：先和用户确认口径（`stallMs` 是否只计被策略接受的卡顿），再把待判定卡顿暂存、策略接受后统一结算次数与时长；同步改 `doc/notes/2026-09-29-player-telemetry-best-practices.md`。

### 3.8 D15 亚秒桶用整秒缓存键（需改契约）

- **位置**：`lib/src/core/preview/service.dart` 的 `_keyFor`（传 `bucket.inSeconds`）、`hash.dart` 的 `defaultCacheKey`/`MovaCacheKeyBuilder`。
- **现象**：配置 `bucket: Duration(milliseconds: 500)` 时 0ms 与 500ms 两个桶同 key，第二个请求显示第一个桶的图。默认 bucket 10s 不受影响。
- **为何暂缓**：`MovaCacheKeyBuilder` 是公开 typedef，参数是整秒 `int`；改成 `Duration` 是破坏性变更。
- **建议（需用户拍板）**：① 加兼容入口（新 typedef 接 `Duration`，旧的 `@Deprecated` 保留一版）；或 ② 构造期 `assert` 桶必须是整秒并写进文档。

### 3.9 E13 音频抽取失败/取消后遗留临时 WAV

- **位置**：`lib/src/platform_impl/mpv_audio_extractor_impl.dart`（清理路径只关播放器和订阅）。
- **现象**：抽取写出部分 WAV 后超时或 `dispose()`，返回 null，宿主拿不到路径，临时文件累积。
- **为何暂缓**：取消后内部异步写入可能还没停，直接删文件有写入竞态；且该抽取器目前**没有生产调用链**（STT 未接完整 PCM 链路）。
- **建议**：操作级保存输出路径；失败/取消后先等 mpv 停止写入（`stop` + 等 `idle`），再删文件；仅成功时移交所有权。随 STT 外迁一起做也可。

---

## 3.10 收尾结果（2026-11-05 晚，非真机部分 + 真机复验）

- 已落地：§1 选方案 c；A11（PiP 中拒绝小窗、全屏先收起小窗）、B3（探测推迟武装）、B5（还原失败保留原值并重试）、C6、D3、D12、D15（亚秒毫秒键）、E13。
- **B1 未做**：尝试过 START_FILE 起始闸门（丢弃新文件 START_FILE 之前的 END_FILE/RESTART），真机 A/B：开启时 HE V9 仅 1/5 通过，关闭 5/5，已整体撤销。要做 B1 需先在真机上证明该 libmpv 向弱客户端投递 START_FILE 的时序，再按  关联。
- 真机：CP3 headers 15/15（R1/R2/R3，夹具需去掉  片段后比较）、fullscreen 10/10（R5）、feedplayer 15/15（R4）；CP2：adpaths 39/40（hls.pod.3 续播落点偏 823ms）、adpause/adbg/pod2/playlist3/bgowner/audioonly-bg/qoe 全过、rate 10/10（R6，上轮 5 FAIL）、warmmute 15/15、v9 5/5（撤闸门后）、liveedge 5/5、events 5/5、pip 4/5（run0 ，疑首次调用时 pipSupported 异步未就绪，未证实）。
- 补测（手机归还后）：R7 新增 CP2 `qoepause` 场景（卡顿进行中暂停 30 秒再恢复），5/5 通过，`stallMs` 283–946ms，不含暂停期；pip 复测 5/5，上次 run0 `enterPip=false` 未复现，按首次调用波动记录。
- B1 两种方案都被真机证伪，已撤销并关闭：① START_FILE 起始闸门（HE V9 1/5）；② 按 `playlist_entry_id` 过滤 id 严格更小的 END_FILE（失败开放，单测过，但 cp1-recovery 开启后 16 项通过即夹具超时，关闭后 20/20；cp1-errclass 15/15、he-recovery V5/V6 3/3 不受影响）。根因未查明（怀疑 `playlist/0/id` 与 END_FILE 的 id 在换档/恢复重载时关系不是单调的假设）。要重开需先在真机上打日志对照两类 id。补充事实（读 media_kit 1.2.6 `real.dart`）：`Player.open` = `stop` → `playlist-clear` → `loadlist append` → `playlist-play-index`，旧文件先被显式 stop（END_FILE 原因为 stop，不是 error）；B1 的误归属只可能发生在 `discardPending()` 到 `stop` 生效之间（首次 open 时要先等视频控制器就绪，窗口最长），后果是新尝试多一次误判重试。
- **C6 已回滚**：C6 修复（中插预热期间正片自然结束/终结失败不被吞）上机后 CP2 adpaths 三次都是 39/40（HLS 续播离群 +823/-600/-600ms），基线 2 次与「仅回退 C6」1 次均 40/40，回滚 C6 后 HEAD 再跑 40/40，确认该改动在 HLS 中插路径引入回归（机理未查明）。C6 仍是未修的窄窗口缺陷：要重做需先在真机上复现「中插预热期间正片 EOF」并保证 adpaths 不回退。
- iOS 无 Mac，无法验证。

## 4. 真机复验（未做，优先级最高）

本轮全部只有单测。以下按“行为变更对真机可观测”排序；验收方法沿用 `CLAUDE.md`「约定」最后一条：基于真实事件测量、URL 加时间戳防缓存、每项 ≥3 次。

| # | 项 | 关联提交 | 怎么测 | 通过标准 |
|---|---|---|---|---|
| R1 | **请求头缓存键在 HLS 上的表现** | `8aa236e9` | CP3 headers 夹具换成需要鉴权的 HLS 源（master + 分片都校验头），普通引擎与 cutover 影子各开同一 URL 不同 token | 服务端看到的 master/分片请求路径**不含** `#mova-load`、各自 token 正确；能正常起播 |
| R2 | CP3 headers 回归 | `8aa236e9` | 原 CP3 headers 用例全量重跑（第七轮 15/15 为基线） | 仍 15/15 |
| R3 | 暂停池截图（播放中重试） | `9a1848dd` | CP3 池预热截图用例，含 `autoPlay:true` 绑定后立即 `screenshot()` | 2 秒内拿到非空图；cutover 3 秒兜底不出现 null 抢跑 |
| R4 | feed 暂停 | `3229f0e7` | 翻页后慢网 `controller.pause()` 立即返回；激活完成后画面仍暂停 | 无异常抛出，最终暂停 |
| R5 | 退出全屏保留强制方向 | `649d515a` | `setOrientation(landscape)` → 全屏 → 退出全屏；再 `auto` 下重复 | 强制方向保留；`auto` 还原宿主方向 |
| R6 | 广告→正片换指倍速/暂停 | `467fe58a`、`9513f1f7`、`f4c8a6e7` | 广告播放中改倍速、暂停再播放，然后 skip | 转正后的引擎倍速与最后一次设置一致、播放态与最后一次命令一致 |
| R7 | QoE 暂停不计卡顿 | `04d04f22` | 限速源播放中暂停 30s 再播（`qoe:true`） | 暂停期间 `stallMs` 不增长；列表连播下一集仍能统计卡顿 |
| R8 | CP2/CP3 整体 | — | 按 `doc/plans/2026-11-03-cp1-results.md` 同一套流程 | CP1 当前 13 PASS/3 BLOCKED，CP2/CP3 待跑 |

**环境提醒**：Android 真机前确认亮屏解锁（`adb shell dumpsys window | grep isKeyguardShowing`）；adb unauthorized 时 `adb kill-server`；
Gradle 构建前查空闲内存 ≥4GB（用户机器常驻别的前端项目），`--max-workers=2`。

---

## 5. 本轮工作方式与踩坑（下一轮直接复用）

- **并发上限**：本机 32GB，但常被别的项目占到只剩 5–8GB。Codex 并发 5 个直接 `memory allocation ... failed`，4 个也崩过；**最多 2–3 个**。
- **Codex 崩溃后的孤儿进程**：会留下 `flutter test`/`flutter_tester`（本轮有一个从 14:09 挂到 16:40）。续做前用
  `Get-CimInstance Win32_Process | ? Name -match '^(codex|flutter_tester|dart|dartvm)\.exe$'` 查父进程已不在的并清掉；
  注意区分别的会话的 codex（命令行带 `--ignore-user-config`）和 sass 的 `dart.exe`，别误杀。
- **后台调度**：用 `nohup` 起的调度脚本会被系统连同子进程一起停掉；改用 harness 托管的后台任务，并配 5 分钟心跳（看日志 mtime 是否推进）。
- **续做而非重来**：Codex 中途死掉时，工作区已有半成品；prompt 写“先 git diff 核对每个编号哪些已完成，在现有改动上继续，不要 checkout/reset”。
- **混合换行**：`core.autocrlf=true`，但 `engine.dart` 等文件在 HEAD 里本身混 CRLF/LF，git 不会规范化；Codex/编辑器把整份转成 CRLF 会让提交带几千行噪音。
  提交前用下面的脚本对齐：未改动行沿用 HEAD 换行，新增行用多数换行。`git diff --stat --ignore-cr-at-eol` 看真实改动量。

```python
# eolfix.py：python eolfix.py <相对 mova/ 的文件...>（在 mova/ 下执行）
import sys, subprocess, difflib
for path in sys.argv[1:]:
    try:
        head = subprocess.run(['git','show','HEAD:mova/'+path],capture_output=True,check=True).stdout.decode('utf-8')
    except subprocess.CalledProcessError:
        continue  # 新文件
    cur = open(path,encoding='utf-8',newline='').read()
    hl = head.splitlines(keepends=True); cl = cur.splitlines(keepends=True)
    crlf = sum(l.endswith('\r\n') for l in hl)
    default = '\r\n' if crlf >= len(hl)-crlf else '\n'
    strip = lambda l: l.rstrip('\r\n')
    sm = difflib.SequenceMatcher(None,[strip(l) for l in hl],[strip(l) for l in cl],autojunk=False)
    out=[]
    for tag,i1,i2,j1,j2 in sm.get_opcodes():
        if tag=='equal': out.extend(hl[i1:i2])
        else: out.extend(strip(l)+(default if l.endswith(('\n','\r')) else '') for l in cl[j1:j2])
    open(path,'w',encoding='utf-8',newline='').write(''.join(out))
```

- **终审别照收 Codex 的修法**：本轮终审改掉/打回过 6 处（A14 降到纯音频档、D9 首帧落地过早、E2/E11 边界、
  事件重入用 `_openGen` 跨 await 误伤被拒绝的 open、D10 依赖 `MovaPlay` 到达）。每批改完都要跑全量测试，修复之间会交叉出新问题。

---

## 6. 别改回去（本轮刻意定下的语义）

- **普通引擎事件同步交付**（`broadcast(sync: true)`）保留；监听器重入的防护是：
  同步段在发事件后比对 `_openGen`（`_isCurrentOpen`）；**跨 await 一律按 `_sessionGen` 判断**，await 之后重取 `_openGen` 基准。
  这样被 `beforeOpen` 拒绝的 open 不会误伤在途的换档/恢复（`engine_final_review_test.dart` 的 `rejected host open during quality reload` 两例锚定）。
- **强制方向独立于全屏**：退出全屏只有 `MovaOrientation.auto` 才还原宿主方向（`restore_test.dart` 已按此改写）。
- **请求头**：`Media(..., httpHeaders:)` 必须保留（media_kit 卸载钩子会清 `http-header-fields` 属性，只设属性会回退 CP3）；
  网络源带头时追加 `#mova-load=N` 只为隔离 media_kit 的进程级 URI 缓存，fragment 不发往服务端。
- **QoE**：手动起播只由首帧事件或原生 RESTART 落地，不上报 TTFF；暂停期不计卡顿按 `_userPaused` 判断，**不要**改回依赖 `_playing`
  （复用引擎连播时不一定再收到 `MovaPlay`）。
- **宿主广告回调异常**：隔离后交给 `Zone.current.handleUncaughtError`，宿主会在崩溃收集里看到以前被吞的异常，这是有意的。
- **ABR 降档**：当前档有高度时只在有高度的变体里降，不会降到纯音频档。
