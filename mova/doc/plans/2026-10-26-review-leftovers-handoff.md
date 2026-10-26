# mova：全量评审遗留项交接（PiP 退出复位 · WarmPlan 方向 · V12 回落 · P3 一批）

> 2026-10-26 · 交接文档 · 读者：**没有本次会话任何上下文的另一个 agent**，拿到就能接着做。
> 依据：`mova/CHANGELOG.md` `Unreleased` 首条（本轮已修内容）、`mova/CLAUDE.md`「全量评审遗留」、
> 提交 `3c0ccb8` / `f3825b3` / `fa527d7` / `3f665bb` / `9813add`（均在 `main`，2026-10-26 已推送）。

**目标：** 把本轮「Codex 全量评审 + 人工终审」里**没做**的条目逐项落地，或明确关闭。
**不做：** 不回头改本轮已修的 P1/P2（已有回归测试 + 真机对照）；要动请先看 §5 的"已验证范围"，别把已确认的行为改回去。

---

## 0. 本轮已完成（别重复做）

- 评审来源：Codex 对 `mova/lib` 全量只读评审（29 条）→ 子代理逐条终审 → 成立的先写红测试再修；之后 Codex 又对 diff 审了 3 轮（`codex review --uncommitted`），共追出 7 条，全部修完。
- 已修清单见 `CHANGELOG.md` `Unreleased` 首条。覆盖：无缝切换（预热超时计时器、open/seek 失败清理、`swapTo` 换源、提交中途 dispose、提交迁移视图设置、`MovaHandoffRetirable`）、引擎（`beforeOpen` 后 dispose 校验、`_emitEvent`、dispose 复位方向）、内核 `open()` 竞态、广告（会话号/disposed、真首帧判据、倍速）、Feed 池重绑、QoE 清零、播放列表 `jumpTo`、预览（crop 缓存/epoch/重订阅）。
- **测试基线 1409 项全绿**，`flutter analyze lib test` 0 issues（`main` 真实检出里实跑）。
- **Android 真机（STG-AL00，release）已对照修复前基线复测**：V1–V9、V10–V15，脚本在 `example/lib/main_review_fixes_verify.dart`（V1–V9）与 `main_review_fixes_verify2.dart`（V10–V14）。

---

## 1. 遗留总览

| # | 项 | 性质 | 优先级 | 需要用户拍板 |
|---|---|---|---|---|
| A | PiP 退出后 `state.pip` 不复位（评审 #15） | **已修（2026-10-26，`MovaPipObservable` + Android 配置变化监听；`am start` 展开真机已验，点 X 关闭未测）** | 高 | 否 |
| B | `MovaWarmPlan` 缺方向字段（评审 #17 的根治） | **已做（2026-10-26）：不加方向枚举，改为 `MovaWarmPlan.rate`/`swapTo(rate:)` 直接声明继任者倍速；广告侧 `setRate` 兜底保留（回落 `open()` 路径仍需要，故不能删）** | 中 | 否 |
| C | V12：pod 第二条广告 `swapTo` 回落成普通 `open` | **已定性并修复（2026-10-26）：`abandon` 异步尾部冲掉新预热 + 广告在途时正片预热挤掉影子，两处；真机 V12/V12b 走真换指** | 中 | 否 |
| D1 | #13 模型下载校验（`sha256` 未使用） | 契约未兑现 | 低 | **是：要不要加 `crypto` 依赖** |
| D2 | #10 `play`/`seek` 钩子异步返回后不复查 | 仅宿主异步钩子触发 | 低 | 否 |
| D3 | #19 预览队列一次异常永久阻断 | 仅宿主注入缓存抛错 | 低 | 否 |
| D4 | #22 STT `start()` 失败不回滚 | **已修（2026-10-26）** | 低 | 否 |
| D5 | #24 手势动作改配后仍读原轴 | 默认配置不受影响 | 低 | 否 |
| D6 | #25 `trackCount`/`maxZoom` 缺构造期 assert | **已修（2026-10-26）** | 低 | 否 |
| D7 | #29 公开成员缺注释 | **已补（2026-10-26）** | 低 | 否 |
| E | #21 `beforeOpen` 拒绝时 `jumpTo` 仍写 `_index` | API 限制 | 低 | 否（需先设计） |

建议顺序：A → C → B → D6/D4/D7 → D2/D3/D5 → D1（等拍板）→ E。

---

## 2. A：PiP 退出后 `state.pip` 不复位（评审 #15，真机已复现）

**现象：** `enterPip()` 成功后 `state.pip=true`；用户从系统层关闭/展开 PiP 回到应用，`state.pip` 一直是 `true`，没有任何 `MovaPipChange(false)`。

**真机证据（2026-10-26，STG-AL00）：** `enterPip()=true`，收到 `MovaPipChange(true)`，`dumpsys` 为 `mWindowingMode=pinned`，Dart 窗口缩成 576x324；`am start` 把应用拉回前台（Flutter 侧 `lifecycle resumed`，窗口恢复 1080x2376）后，`state.pip` 在之后 **26 个 1 秒采样里恒为 `true`**。只测了 `am start` 退出路径，**没单独测 `KEYCODE_HOME`**。

**后果：** 皮肤因 `pip` 仍为 true 继续隐藏操作层；自动暂停守卫用 `exempt: state.pip || state.mini`，导致之后一直豁免、不再自动暂停。

**根因（已查）：**
- Dart：`MovaEngine.enterPip()` 是全库**唯一**写 `state.pip` 的地方（`copyWith(pip: ok)` + `_events.add(MovaPipChange(ok))`），没有任何订阅把它复位。
- 端口：`MovaPipPort` 现有接口只有 `Future<bool> isSupported()` 与 `Future<bool> enter({int? width, int? height})`（`lib/src/core/ports.dart`）。
- 原生：`android/.../MovaPlugin.kt` 只有 `enterPictureInPictureMode`，**没有** `onPictureInPictureModeChanged` / Activity 回调，也没有往 Dart 发退出通知的通路。

**建议方案（未做，改动跨 Dart + Kotlin）：**
1. `MovaPipPort` 加 `Stream<bool> get changes`（默认实现返回空流，`MovaNoopPipPort` 同样）。
2. Android 端：监听 Activity 的 PiP 模式变化（`onPictureInPictureModeChanged`，或 `Lifecycle` + `isInPictureInPictureMode`），经 EventChannel/MethodChannel 回调给 Dart。注意 mova 是插件，拿 Activity 的方式要沿用 `MovaPlugin.kt` 现有的 `ActivityAware` 写法，别另起。
3. `MovaEngine` 订阅 `changes`，`state.pip` 与 `MovaPipChange` 随之更新；dispose 时取消订阅。
4. 先在 `didChangeAppLifecycleState(resumed)` 里复位**不是**可靠方案（PiP 里应用本身也可能是 resumed），不要当最终方案。

**验收：**
- 单测：假端口推 `changes`，断言 `state.pip` 复位并发 `MovaPipChange(false)`；dispose 后不再订阅。
- 真机：沿用 `main_review_fixes_verify.dart` 的 V9 脚本，进 PiP → 退出（`am start` 与 `KEYCODE_HOME` **两种都测**）→ 采样 `state.pip` 应回到 false，且自动暂停守卫恢复生效。
- iOS 无 PiP 实现（返回不支持），本项不涉及。

---

## 3. B：`MovaWarmPlan` 缺方向字段（评审 #17 的根治）

**现状：** `MovaSwapEngine._commitNow` 提交时通过 `_inheritViewSettings` 把 rate/fit/zoom/音量/锁定/全屏/mini/**orientation** 迁给继任者。但 `MovaWarmPlan`（`lib/src/core/swap/plan.dart`）没有方向字段，两个方向的计划都是 `pauseWhenReady: true`，swap 层分辨不出 content→ad 还是 ad→content，所以**对所有方向一律继承，包括 rate**。

**当前兜底（在 `ad_controller.dart`）：** swap 启用时，正片在屏记 `_contentRate`；广告上屏后若 rate≠1 就 `setRate(1)`；正片续播后若 rate 与 `_contentRate` 不同就恢复。`_contentRate` 的更新在 `_resuming` 过渡期内被冻结，`playAdNow` 入口会同步快照一次。
**副作用：** content→ad 换指后到 `setRate(1)` 生效之间有几个微任务的窗口，广告引擎短暂处于用户倍速。

**建议：** 给 `MovaWarmPlan` 加方向字段（如 `MovaWarmDirection { toAd, toContent }`），swap 层按方向只对"回正片"继承 rate，之后可删掉 ad 侧的 `setRate(1)` / 恢复兜底。**删兜底前**必须保留 `test/core/ad_first_frame_test.dart` 里的倍速用例（2x、1.5x、过渡期广告 progress 三条）全绿。

**未真机验证过：** content→ad 方向广告引擎那几个微任务内的倍速（V13 只验了广告期间稳态为 1.0、返回后恢复）。

---

## 4. C：V12 现象——pod 第二条广告的 `swapTo` 回落成普通 `open`

**现象（2026-10-26 真机，`main_review_fixes_verify2.dart` V12/V12b）：** 把两条中插串成 pod、走 swap 路径，修复后第二条广告的 `swapTo` 实际回落成了主引擎上的普通 `open`，不是真换指。日志里 swap 阶段 `warming` 后约 **70ms** 就回到 `idle`。第二条广告的槽位计时本身正确（6000–6003ms，`failed=0`），所以**没坏播放，只是没走无缝路径**，"真 swap 时旧引擎 tick 抢跑"这一支没测到。

**怀疑（未确认）：** `_playAd` 的 `oneShot` 分支里 `unawaited(_swap?.abandon()); await _swap!.swapTo(b.source);`——`abandon()` 不 await，与紧随其后的 `swapTo` 抢同一个影子。**这个写法在 `dbbc785`（本轮之前的 HEAD）就有**，不是本轮引入；但本轮改过 `_startWarm`/`swapTo`（#4 失败清理、#5 换源丢弃旧影子、readyTimeout 计时器），不排除互相影响。基线对照：基线上第二条广告 `swap` 落定到 `completed` 只有 4973/5072ms（V12）和 3601/3858/2839ms（V12b）——说明基线上旧引擎 tick 让槽位时钟提前起表，不能直接断言基线走了真 swap。

**怎么查：**
1. 在验证页 V12 里给 swap 加阶段日志（`swapPhase` 变化 + `abandon`/`swapTo` 调用时间戳），看 `warming` 是被谁清回 `idle`。
2. 把 `unawaited(abandon())` 改成 `await abandon()` 再 `swapTo`，对比是否变成真 swap；注意 `abandon` 内的 dispose 是异步的，要确认没有新的竞态。
3. 若确认是本轮改动引入，补一条单测：pod 中第二条广告走 `swapTo`，断言 `renderEpoch` 递增（真换指）而不是主引擎 `open`。

**不阻塞：** 回落是优雅降级。

---

## 5. D：P3 一批（均已终审成立，未修）

行号以函数名为准（文件已因本轮改动偏移）。每项都要**先写红测试再修**。

### D1 #13 模型下载校验未兑现契约（`lib/src/core/stt/model_provider.dart`，`ensure` 附近）
- `sha256` 在 `model_spec.dart` 声明、文档描述为校验手段，**全库没有任何校验代码**。
- 新下载内容不校验 `sizeBytes`，直接 `writeAsBytes`；截断或被替换的内容本轮照样返回路径，下次启动才因大小不符重下。
- 非原子写：写一半被杀进程，在 `sizeBytes == null` 时会被当成已缓存。
- 修法：下载后先比对长度，不符抛 `MovaSttModelLoadError`；先写 `.part` 再 rename。
- **`sha256` 要么在文档里写明"暂未实现"，要么加 `crypto` 依赖。按项目约定引入新依赖前必须先问用户。建议先改文档。**

### D2 #10 `play`/`seek` 钩子异步返回后不复查（`lib/src/core/engine.dart`）
- `play()` 在 `await beforePlay()` 后直接写 `playbackIntent=true` 并 `_kernel.play()`；期间用户 `pause()` 会被覆盖。
- `seek()` 在 `await beforeSeek()` 后不校验 `_openGen`；期间切源，会对新源执行旧跳转。
- 触发条件是**宿主钩子本身异步**。修法：入口记 `gen = _openGen`，play 另记 pause 计数；返回后不一致就 return。

### D3 #19 预览队列一次异常永久阻断（`lib/src/core/preview/service.dart`，`_enqueue`/`dispose`）
- `_queue = _queue.then((_) => _resolve(...))`，`_resolve` 一旦抛错，`_queue` 为失败态，后续 `.then` 全被跳过；`dispose` 里 `await _queue` 重抛，后面 `s.dispose()` / `cache.dispose()` / `probe.dispose()` / `_thumbs.close()` 全部跳过。
- 仅宿主注入的缓存/probe 抛错时触发（内置 `MovaDiskThumbCache` 只吞 `FileSystemException`，其他异常同样会逃出）。
- 修法：`_resolve` 外包 try/catch；`dispose` 吞掉 `_queue` 的重抛，各步骤各包一层 try。

### D4 #22 STT `start()` 失败不回滚（`lib/src/core/stt/service.dart`）
- `_started = true` 在 `engine.start()` 之前；失败后 `isRunning` 一直为 true，再 `start()` 直接 return，宿主必须额外 `stop()` 才能重试。
- 修法：try/catch 里回滚 `_started=false` 再 rethrow，或改为事件上报。

### D5 #24 手势动作改配后仍读原轴（`lib/src/ui/components/gesture_layer.dart`，`_decideMode`/`_drive`）
- `_decideMode` 按轴向取动作（`|dx|>|dy|` 取 `horizontal`，否则取 `leftVertical`/`rightVertical`），但 volume/brightness 只读 `_cum.dy`、seek 只读 `_cum.dx`。
- 配 `horizontal: volume` 或 `leftVertical: seek` 时能进入该模式，但读的是另一个轴，位移近似为零。**默认配置不受影响。**
- 修法二选一：按所选轴取位移；或在 `MovaGestureConfig` 的 assert 里限制 `horizontal` 只能 seek/none、竖直只能 volume/brightness/none。

### D6 #25 构造期 assert 缺失
- `MovaDanmakuConfig`（`lib/src/core/options/danmaku_config.dart`）：`trackCount: 0` 时 `danmaku.dart` 的 `_nextTrack % trackCount` 除零；加 `assert(trackCount > 0)`。
- `MovaGestureConfig`（`lib/src/core/options/gesture_config.dart`）：`maxZoom < 1` 时 `gesture_layer.dart` 的 `clamp(1.0, maxZoom)` 抛 `ArgumentError`，且在捏合手势中途；加 `assert(maxZoom >= 1.0)`。
- 这两处 int/double 比较在 `const` 构造器初始化列表里可以写 assert（**别写 `Duration` 比较**，见 `CLAUDE.md`「约定」）。

### D7 #29 公开成员缺注释
- `lib/src/ui/slots/patch.dart`：`MovaPatch` 的 `const MovaPatch()`；`MovaPatchReplace(path, component)`、`MovaPatchRemove(path)`、`MovaPatchInsertAfter(path, component)`、`MovaPatchAdd(slot, component, {order})` 的构造器。
- `lib/mova_platform_interface.dart`：`MovaPlatform` 类本身；构造器只有英文无中文；`_token`、`_instance`；`instance` getter/setter 只有英文；`getPlatformVersion()` 完全没有；`isPipSupported`/`enterPip`/`getSystemVolume`/`setSystemVolume` 缺使用示例。
- 规范：先英文后中文、空行分隔；公共 API 含参数/返回/示例。

---

## 6. E：#21 `beforeOpen` 拒绝时 `jumpTo` 仍写 `_index`

本轮只修了"交错 `jumpTo` 丢弃过期结果"（`_jumpGen`）。**没修** `beforeOpen` 拒绝目标项的情形：`MovaApi.open()` 返回 `void`，拒绝与成功在 API 上区分不了，`playlist_controller` 仍会写 `_index`，列表与实际在播源不一致。
可选方向（需先设计，别直接改）：① 让 `open` 返回是否被接受（改公共签名，影响面大）；② 等 `MovaApi` 暴露当前 source 后用 `MovaSource.sameAs` 校验。

---

## 7. 已验证范围与未验证项（避免过度信任）

**真机已验证（对照修复前基线）：** 预热超时与回退、预热 open 真抛错、同引擎 `swapTo` 换源、提交中途 dispose、广告延迟解析过期、Feed 池重绑、内核 `open()` 竞态、dispose 复位方向、全屏 swap 方向保持、非全屏强制横屏 swap、倍速恢复（2x / 1.5x）、预热失败不跳广告。

**仅单测覆盖、未上真机：** #11 预览换源过期、#12 缩略图 crop 缓存、#14 QoE 清零、#18 气泡 swap 后重订阅、#21 `jumpTo` 交错、#23 广告首帧判据在**非 swap** 路径与 `preciseFirstFrame` 关闭时的回退判据、#17 迁移其余字段（fit/zoom/音量/锁定/mini）。

**真机上没复现 / 无效的：**
- #3「预热永久挂起」：`/hang` 源修复前后都在约 5.2s 结束，只验证了超时与回退续播可用；找不到能让影子完全无进度事件的真机场景。
- 公网断网那组无效：手机上有 Gnirehtet VPN 一直在中继，**不要去动它**，断网类实验改用本机源 `/hang`。
- 偶发 `failed:AD2` 出现过 1 次（更早构建、无时间线日志），之后同代码连跑 18 次未复现，按未复现处理。
- `[Player] has been disposed` 未捕获断言：栈在 media_kit 内部（`AndroidVideoController.widListener` 对已销毁 Player 做 seek），基线同样出现，**不是本轮回归**。

---

## 8. 环境与流程注意

- **真机：** STG-AL00，adb 序列号 `7NQBB23606003715`。实验前必须确认亮屏且未锁屏（`dumpsys window | grep isKeyguardShowing`、`dumpsys power | grep mWakefulness`），否则涉及渲染面的结果作废。用 **release** 构建（debug 下 `createMovaEngine` 走 100ms 轮询，数字不可比）。度量只用真实事件戳，不用墙钟，URL 加 timestamp，每项至少 3 次。
- **设备副作用（上轮留下）：** 设备上原有的同包名 example app 因签名不一致被卸载过，现在装的是验证页。`packages/media_kit_libs_android_video_slim_v041/` 下 4 个 `.so` 是从 GitHub 端 `git lfs fetch` 拉成真实文件的（codeup 端缺 LFS 对象），`git status` 不显示为改动；基线对照 worktree 里要用这些真实 `.so`。
- **多会话共用工作区：** 同一个 `dart-labs` 工作区里常有别的会话在改 `flutter_stompsocket/`、`ffuzzy/`、`layerman` 等并切分支。**不要 stash / 切分支 / 整目录 checkout。** 提交 mova 用独立 worktree：`GIT_LFS_SKIP_SMUDGE=1 git worktree add ../dart-labs-main-wt main`（不跳过 smudge 会因 codeup 缺 LFS 对象而失败），把改动文件拷过去提交，做完 `git worktree remove`。
- **换行符：** 仓库 `core.autocrlf=true`，工作区文件是 CRLF、入库是 LF。别用会整文件改写行尾的脚本；核对改动用 `git diff --stat` 与 `git diff --stat -w --ignore-cr-at-eol` 对比。
- **测试：** 改完必须跑**整个工程**的 `flutter test` 与 `flutter analyze lib test`，不要只跑 `test/core`——本轮曾因只跑 core 漏掉 `test/ui/ad_overlay_test.dart` 的 7 条失败。
- **Codex 评审：** `codex review --uncommitted` 会把整份 diff 再审一遍；每一轮都会在上一轮新改的代码上找到更窄的问题，建议最多 3 轮就收口，剩下交给真机复测。
- **提交约定：** `type(scope): message`，scope 用 `mova`；push 前先 `git status`；`origin` 同时推 codeup 与 GitHub。
