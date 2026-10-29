# Q13 直播预热判据修复的真机验证（2026-10-29）

> 设备 STG-AL00（adb 7NQBB23606003715，Android 12，release 包），全部为本轮真机实测。
> 被测改动：`lib/src/core/cutover/warm.dart`（`MovaWarmSignal.live`，`MovaBufferWarm` 对直播不再要求到达目标位置）、
> `cutover_engine.dart`（构造信号时传 `live: _warmLive`）。未提高 `readyTimeout`（仍 8s）。
> 本轮没动 lib/ 产品代码与 so/dll；只改了验证页 `example/lib/main_q13_mute_verify.dart`（见第 5 节）。

## 环境快照

| 项 | 值 |
|---|---|
| `git diff --stat -- lib` | `cutover_engine.dart | 1 +`、`warm.dart | 25 +++---`，2 files changed, 23 insertions(+), 3 deletions(-) |
| 基线提交 | `ea44d51`（工作区另有他人未提交改动，未碰） |
| APK（拉回设备比对一致） | sha256 `f21b1dfa515c8a8f31c731e6f55923abd99da1e98137b9c1f2a457a834481cb9`，包 `com.icodejoo.mova.mova_example.coverage`（`lib/main_coverage_suite.dart`，release，debug.keystore 签名） |
| APK 内 arm64 `libmpv.so` sha256 | `798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b`（旧版，未换） |
| 设备 | 机主已解锁，全程 `isKeyguardShowing=false`；`stay_on`/`screen_off_timeout` 未改动 |
| 本地源 | `verify_sources/start_sources.py`（18080/18081，adb reverse）：直播 `live.flv?gop=50&audio=1&freq=440`、广告 `ad.mp4`、点播 `vod.mp4`（40s）；URL 带时间戳防缓存 |
| 跑法 | `coverage_suite_device.py mute --only <ID> --runs 5`，每次调用 force-stop 后新进程，每轮新建 cutover 与 Player |
| 证据 | `example/tool/coverage_evidence/q13fix-{L,D,S,X,Y,V}-*.log`（含 samples/dumpsys/png）与 `q13-fix/`（`runall.sh`、`progress.txt`、各组 `.out`） |

## 1. 直播变体结果（B/C 为被测用例，A 为对照）

「就绪耗时」= 自 `playAdNow` 起到 cutover 阶段第一次变 `ready` 的时间（DIAG 每 300ms 采样，约 ±300ms；含影子创建与起播延迟）。
mute 读回：所有 PASS 轮的判据都含「预热期间影子 mute=yes、在播引擎 mute=no、提交后在播引擎 mute=no（C）/ 保活持有期 yes、唤醒后 no（B）」，全部满足；logcat 里没有 `setStreamVolume`/`adjustStreamVolume` 类系统音量写入（grep 0 条）。

| 正片先播 | 用例 | 通过/总数（swapped=true） | 进程数 | 就绪耗时 min / 中位 / max (ms) | 影子被放弃 |
|---|---|---|---|---|---|
| 500ms | B | 10/10 | 2 | 2909 / 3566 / 5908 | 0 |
| 500ms | C | 10/10 | 2 | 3011 / 3695 / 6089 | 0 |
| 500ms | A（对照） | **9/10**（1 败，见下） | 2 | 2847 / 3354 / 3656（9 轮） | 1 次（k2 从未加载成功） |
| 3s（默认） | B | 10/10 | 2 | 3085 / 3469 / 6208 | 0 |
| 3s | C | 10/10 | 2 | 3106 / 3506 / 3841 | 0 |
| 3s | A | 10/10 | 2 | 3326 / 3569 / 5485 | 0 |
| **7s** | B | **10/10**（上轮 0/5） | 2 | 3065 / 3556 / 7753 | 0 |
| **7s** | C | **10/10**（上轮 0/5） | 2 | 3131 / 3676 / 5443 | 0 |
| 7s | A | 10/10 | 2 | 3429 / 3732 / 5728 | 0 |
| **15s** | B | 5/5 | 1 | 3024 / 3197 / 3789 | 0 |
| **15s** | C | 5/5 | 1 | 3236 / 3536 / 3650 | 0 |
| 15s | A | 5/5 | 1 | 3188 / 3333 / 3929 | 0 |
| **30s** | B | 5/5 | 1 | 2959 / 3017 / 3925 | 0 |
| **30s** | C | 5/5 | 1 | 2966 / 2974 / 3440 | 0 |
| 30s | A | 5/5 | 1 | 3011 / 3801 / 4437 | 0 |

就绪耗时对照（中位）：500ms 3.4–3.7s、3s 3.5s、7s 3.6–3.7s、15s 3.2–3.5s、30s 3.0–3.8s。**不再随「正片先播多久」增长**（上轮：500ms 3.6–4.7s、3s 6.2–6.9s、7s 从未就绪）。
B+C 合计 70/70 通过，没有一次靠 `readyTimeout` 放弃；最慢一次 7753ms（该轮起播延迟本身就 7.4s 的异常慢轮），仍在 8s 内就绪。

### 唯一失败：500ms 变体 A 对照第 3 轮（Q13AS，S-1 进程）

现象：`could not reach the warming state`。日志：广告影子 k1 在 +1268ms 就绪并提交；随后给正片建的影子 k2 在 +1377ms 起，之后 5.6s 内 mpv `time-pos` 为空、`idle=yes`（媒体根本没加载上，不是位置/缓冲判据问题），+6960ms 被放弃、紧接着新建影子重试（+11008ms 就绪）；验证页的 `_waitShadowLoaded` 钉在已被销毁的 k2 上，14s 后判败。
判断：**推断**是影子 `open()` 在直播源上没拿到数据（本机 HTTP 源/连接层的一次卡住），与就绪判据无关（k2 全程没有位置读数，新旧判据对它都不会就绪）；原因未捕获，未复现（该变体其余 19 轮全过）。500ms 变体上轮只跑了 B/C、没有 A 的旧数据，不能判断这是新问题还是老问题。

## 2. 修复是否成立

- **已证实**：7s/15s/30s 变体影子在 3.0–5.7s（唯一异常轮 7.75s）内就绪并 `swapped=true`，`readyTimeout` 未改（仍 8s）；就绪耗时与正片先播时长无关。上轮 7s 变体 10/10 必败，本轮 B/C 各 10 次全过。
- **已证实**：默认 3s 与 500ms 变体不退化（B/C 20/20 + 20/20）。
- **推断**：上轮默认时序偶发的 3 次自然失败（起播抖动把就绪推过 8s 线）应一并消除——就绪耗时与正片位置无关、裕量约 4s；但本轮同样没抓到自然失败，不能直接证实。
- 取舍：直播就绪只看卡顿 + 提前缓冲，提交时不再有「影子与旧流同点」的保证（直播本就无可比性，cutover 也不 seek 直播）。

## 3. 点播（非直播）cutover 回归

仓库里没有离线可用的点播 cutover 真机用例：`coverage_new:cutover`（A24）用的是 audio-only 引擎、不测续播落点；`main_resume_accuracy_verify.dart` 依赖外网 URL。所以在验证页加了 **Q13V**：正片本地 `vod.mp4`，先播 3s，`playAdNow` 中插广告，广告起播 1s 后 `skip()`，记录「广告接管时正片最后位置」与「提交后首个位置」之差；10 次（2 进程 × 5）。

| 结果 | 数据 |
|---|---|
| 通过 | 10/10（`swapped=true`、提交后 `mute=no`、误差 <500ms） |
| 续播落点误差（ms） | 40, 40, 40, 160, 240, 280, 320, 360, 360, 360（中位约 300） |
| 与 skip→commit 的关系 | 误差 40ms 的 3 轮 skip→commit 仅约 51ms（影子已就绪）；其余 7 轮 skip→commit 935–1142ms（skip 时影子未就绪，等其就绪才提交），误差 160–360ms |

判断：
- 代码层面：改动只在 `live` 为真时放宽，点播 `live=false` 走与旧版相同的 `arrived` 判据，`cutover_engine_test` 有「点播仍须到达目标位置」的对照单测。**「点播路径无行为变化」是代码上的结论，不是真机对照**——没有用旧版 lib 重建对照，所以不能证明 160–360ms 与改动无关；只能说它出现在「skip 时影子尚未就绪」的轮次，机制上与直播判据无关。
- 与 CLAUDE.md 记载的 +42ms 比：影子先就绪的 3 轮（40ms）一致；影子后就绪的偏大。+42ms 当时的素材是外网 mp4、skip 时机也不同，**不是同条件对比**，不据此说回归或没回归。要定论需用旧 lib 构建同一页复测（约 10 分钟）。
- 误差口径：进度流约 250ms 一次，接管位置取 epoch 切换前最后一次进度，本身有 ±250ms 量级采样误差。

## 4. 没能验证 / 需要注意

- 没记录「请求待机→committed」逐轮耗时：B/C 在影子就绪后固定等 0.8s/1s 再 `skip()`，committed 时刻不是自然提交时间；表中以「`playAdNow`→就绪」代替。
- 音频：本机无采集路径，mute 只由 mpv 属性读回 + 无系统音量写入日志间接证明，没有听感/声道采集。
- 500ms 变体 A 对照 1/10 败，原因未定，样本太小。
- 点播续播误差没有同条件旧版对照。
- `ACCEPTANCE-MATRIX.md`、`CLAUDE.md` 未改（`git status` 里 ACCEPTANCE-MATRIX.md 有未提交改动，不是本轮所为）。

## 5. 本轮改动的文件

- 验证页：`example/lib/main_q13_mute_verify.dart`（新增 15s `Q13?X`、30s `Q13?Y` 变体；新增点播回归场景 `Q13V` 及进度跟踪字段；`flutter analyze` 0 issues）。
- 文档：本文件。
- 证据：`example/tool/coverage_evidence/q13fix-*`、`example/tool/coverage_evidence/q13-fix/`。
- 脚本：无改动。

## 6. 收尾

设备 force-stop（两个包均未卸载）、`adb reverse/forward` 全部移除、本机源服务已结束；临时 APK 与源工作目录已删（APK sha256 见上）。`libmpv_hydrate.py --check`：`[OK] 所有 LFS 文件均为真实内容`。
