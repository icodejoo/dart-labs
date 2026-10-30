# 零拷贝硬解兼容矩阵 + 点播 cutover 续播新旧对照 + 500ms 变体影子卡住对照（2026-10-29）

> 设备 STG-AL00（adb 7NQBB23606003715，骁龙 662，Android 12，release 包）。数字全部来自本轮证据；读不出来的写「数据不足」。
> 本轮没改 `lib/` 产品代码（任务 B/C 为建旧版基线临时回退两个文件，已 `git checkout HEAD --` 恢复，`git diff --stat -- lib` 为空）、没换 so、没改默认值。

## 环境快照

| 项 | 值 |
|---|---|
| 基线提交 | `d804a09`（工作区另有他人未提交改动，未碰） |
| arm64 `libmpv.so` sha256 | `798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b`（旧版，新旧两包均核对一致） |
| A 的包 | `com.icodejoo.mova.mova_example.coverage`（`main_coverage_suite.dart` 的 `hwdec` 组，页面 `main_hwdec_matrix_verify.dart`） |
| B/C 新 lib 包 | `...coverage.abnew`，签名 apk sha256 `1781774476691813de081324562097f9e44d90fc96b43975692c3f6c392db4e1`（HEAD，`da88564` 之后） |
| B/C 旧 lib 包 | `...coverage.abold`，sha256 `d99415cc6e3262eba9b8cab505aed617b34cd943f58fd7963197cbb7198d19fd`（`warm.dart`/`cutover_engine.dart` 取 `da88564~1`；两版 lib 仅此两文件有差，`git diff da88564~1 HEAD -- lib` 已核对） |
| 构建 | `tool/coverage_build.py lib/main_coverage_suite.dart -I tool/ab_id.init.gradle -PabId=<id>`；zipalign + debug.keystore 签名；两包 applicationId 不同，可并存，B/C 新旧**交错**跑（每进程 5 轮，新-旧-新-旧…各 8 进程）抵消设备漂移 |
| 设备 | 机主已解锁亮屏，`isKeyguardShowing=false`，USB 供电；`stay_on`=7、`screen_off_timeout`=2147483647 未改动 |
| 本机源 | `live_server.py`（18080：`live.flv`/`vod.mp4`/`ad.mp4`）；A 的样本用 `range_server.py`（18090，206 已核实）。注意：B/C 的 `vod.mp4` 由 `live_server` 提供，它只对「起点 >0 的开放式 Range」回 206，`bytes=0-N` 回 200；本轮 server.log 里没有出现起点 >0 的请求（mpv 一次顺序读完 1.7MB），所以 B 没有真正用到 Range seek。新旧两版用同一服务，对比公平，但这不是「seek 走 Range」的验证 |
| 证据 | A：`example/tool/coverage_evidence/zero-copy/`；B/C：`.../zero-copy-ab/{b-vod,c-as}/`（每进程一份 flutter 日志）+ `b-vod.out`/`c-as.out` |
| 本机 CPU | 同时有别的进程占 CPU（top 里整机忙度 330–400%/800%），CPU 数字只算量级 |

---

## A. 零拷贝 `hwdec=mediacodec` 与默认 `mediacodec-copy` 兼容矩阵

跑法：6 个样本 × 2 配置 × 3 次，顺序 copy-1、zero-1、copy-2、zero-2、copy-3、zero-3，同一进程内连续。汇总脚本 `tool/zero_copy_report.py`。样本播放窗口 6s（`posAdvanced`），全部 `eof=true`。

### A1 codec 矩阵（A-codec，36 行齐全，`AUTORUN DONE`）

「真走零拷贝」= 请求 `mediacodec` 且 `hwdec-current` 读回 `mediacodec`；「回落」= 读回 `mediacodec-copy`。

| 样本 | 解码器 | copy：`hwdec-current` | zero：真零拷贝 / 回落 | 首帧 ttff（ms，copy / zero） | posAdvanced | errors | 截图非黑 |
|---|---|---|---|---|---|---|---|
| h264_720 | OMX.qcom.video.decoder.avc | 3/3 `mediacodec-copy` | **2/3**（zero-3 回落） | 163–531 / 207–552 | 全部推进 ~6s | 0 | 是（luma 126.5–127.7） |
| h264_fs（640 宽，40s） | 同上 | 3/3 copy | **3/3** | 176–280 / 232–258 | 推进 | 0 | 是 |
| hevc8 | OMX.qcom.video.decoder.hevc | 3/3 copy | **2/3**（zero-3 回落） | 233–256 / 128–242 | 推进 | 0 | 是 |
| hevc10 | **无**（`yuv420p10` 软解） | `hwdec-current=no` ×3 | **0/3**，读回均为 `no`（不是回落到 copy，是没有硬解） | 188–206 / 119–200 | 推进 | 0 | 是 |
| vp9 | OMX.qcom.video.decoder.vp9 | 3/3 copy | **1/3**（zero-1、zero-2 回落） | 198–239 / 251–287 | 推进 | 0 | 是 |
| vp8 | 无硬解，`hwdec-current` 空 | 空 | 空（两配置一致） | 76–100 / 100–109 | 位置推进但**无画面**：`kernelShot=null`、截图 luma 0、`errors=1`（`MovaErrorEvent`） | 1 | **否（黑屏，两配置同样）** |

结论：所有 H.264/HEVC8/VP9 样本在两种配置下都出画面、位置推进、无 `MovaErrorEvent`。VP8 在**两种配置下都**黑屏（该设备没有 VP8 硬解、瘦身 libmpv 也没有软解），与零拷贝无关，是已知的「去 VP8/VP9 软解」瘦身取舍的体现；VP9 能出画面是靠 MediaCodec 硬解。

### A2 现象一：请求零拷贝却静默回落

A-codec 里 12 次可硬解的 zero 请求，**4 次回落**（h264_720 zero-3、hevc8 zero-3、vp9 zero-1/2）。把各场景（每个场景一个独立进程）里所有「请求 `mediacodec`」的轮次合并（cutover 除外）：

| 场景 | 真零拷贝 / 次数 | 序列（Z=真零拷贝，C=回落） |
|---|---|---|
| codec（4 个可硬解样本） | 8/12 | h264_720 ZZC，h264_fs ZZZ，hevc8 ZZC，vp9 CCZ |
| shot | 2/6 | h264_720 ZCZ，hevc8 CCC |
| rate | 1/3 | CCZ |
| mini | 1/3 | CCZ |
| pip | 2/3 | ZZC |
| bg | 2/3 | ZZC |
| **合计（非 cutover）** | **16/30（回落 14 次，47%）** | |
| cutover（h264_720、hevc8，广告与正片两个引擎） | **6/6，无一回落** | ZZZ，ZZZ |

与「上一次运行 / 进程复用 / 解码器实例数」的关系（只读证据得出，不做因果断言）：

- **与运行序号无关**：同为第 3 轮，h264_fs zero-3 是真零拷贝，h264_720/hevc8 zero-3 回落；vp9 却是第 1、2 轮回落、第 3 轮真零拷贝。
- **与解码器实例数无关**：`media.resource_manager` 快照里回落与非回落轮都只有 1 个 client（h264_fs zero-3 甚至有 2 个 client，仍是真零拷贝）。注意 rm.txt 文件名按 id 复用，被后面的场景覆盖，只能当旁证。
- **同一样本在不同进程里结果不同**：hevc8 在 codec 场景 zero-1/2 真零拷贝，在 shot 场景三次全回落——说明是**非确定性**，不由样本决定。
- 日志（`MediaCodec`/`ACodec`）里回落轮与非回落轮都只创建同名 OMX 解码器，没有可区分的报错行；mpv 日志未转发到 logcat，**没有回落原因的直接证据**。
- 一个**仅作假设、未验证**的线索：cutover 场景 6/6 零回落，而该场景影子引擎创建后主动读 `renderHandle`（急切建 `VideoController`），其余场景走懒创建；回落可能与「解码器初始化时渲染面是否已就绪」有关。需要对 `lazyVideo=false` 做对照才能下结论。

含义：**请求零拷贝并不保证拿到零拷贝**，宿主若依赖「零拷贝才有的行为」必须读回 `hwdec-current` 校验。

### A3 现象二：hevc10 两种配置都是 `hwdec-current=no`

- 读回：6/6 `no`，像素格式 `yuv420p10`，`rm.txt` 里没有任何 media 解码器 client；A-codec 日志里该样本段 **`MediaCodec init` 0 次**（其他硬解样本每段 3 次），即根本没有向 MediaCodec 发起过创建。
- 设备能力：`/vendor/etc/media_codecs*.xml` 只声明 `OMX.qcom.video.decoder.hevc`（及 `.secure`、`c2.android.hevc.decoder`），**没有按 profile 列出 Main10**；本设备 `dumpsys media.codec` 不存在（`Can't find service`）。因此**无法从证据区分**「硬件不支持 10bit HEVC」与「mpv/ffmpeg 在到达 MediaCodec 之前就拒绝了 `yuv420p10`」。该样本的结论只能是：在这台设备 + 这版瘦身 libmpv 上，10bit HEVC 走软解，零拷贝配置不改变这一点。数据不足的部分：MediaCodecList 的 Main10 能力（需要在 app 内枚举）。
- CPU：app 进程 top %CPU 中位 copy 102、zero 105（99–105 范围，约 1 个核满载以上），对比 8bit HEVC 的 53；画面、播放推进正常、无错误。

### A4 CPU 节省（量级，非精确）

top 的 `%CPU` 是按单核计的进程占比，播放中取 3 次采样中位；整机忙度 275–511%（含他进程），所以只比同一样本内的相对差。

| 样本 | app 进程：copy（3 次） | app 进程：真零拷贝 | media.codec 进程：copy | media.codec 进程：真零拷贝 |
|---|---|---|---|---|
| h264_720 | 47/50/50（中位 50） | 42/45（n=2） | 11/10/11 | 5/5 |
| h264_fs | 47/43/44（44） | 45/44/46（45） | 8/7/7 | 4/5（另 1 次无读数） |
| hevc8 | 51/53/54（53） | 46/47（n=2） | 10/10/11 | 5/5 |
| vp9 | 53/50/52（52） | 46（n=1） | 11/10.5/10 | 无读数 |
| 回落轮（对照） | — | h264_720 53、hevc8 53、vp9 39/50 | — | 10–11（与 copy 同） |

量级：真零拷贝时 media.codec 进程约降 5–6 个百分点（~10→~5），app 进程约降 0–7 个百分点（h264_fs 几乎无差，该样本只有 640 宽），合计约 **5–12 个百分点（单核）**，约占播放期总占用（app+codec 约 55–65）的 10–20%；整机忙度的差异（约 10–20）被他进程噪声淹没。回落轮的 CPU 与 copy 同级，印证回落后确实走了 copy 路径。样本量小（n=1–3/格），**只能说「量级上有降、没有数量级差异」**。vp8（3–4%）因无画面不具参考价值。

### A5 功能路径逐项对照

说明：场景截图 png 以 `hwm-<id>-<tag>.png` 命名，各场景同 id 互相覆盖，汇总脚本里非 codec 场景的整屏截图亮度**不可靠**；这里只用页面内的内核截图（`kernelShot` luma/colorful）与位置/事件读回。

| 项 | 零拷贝 vs 默认 | 分类 |
|---|---|---|
| 截图 shot（A-shot） | h264_720 与 hevc8 各 3 次：`kernelShot` 18 次全部非黑（luma 127.6–127.7，colorful ≥0.99），`bytes` 在 zero 与 copy 间同量级（23.0–24.1 万）；errors 0。注意其中真零拷贝只有 2 次（h264_720 zero-1/3），其余回落，所以「**真零拷贝时 mpv screenshot 可用」只有 2 个样本**；`hwdec-current=mediacodec` 时 `bytes` 227–231k 与 copy 的 230–232k 无差 | 同样通过（样本少） |
| 预览抽帧 extract（A-extract） | 首次跑：copy-1/zero-1/copy-2 出图（帧 268420 字节、luma 127.5，耗时 1887/2199/2553ms）；**zero-2 起进入 `MediaCodec configureCodec returning error -12` 重试循环，10501 次，持续约 8 分钟直到 runner 超时，页面未完成（无 `AUTORUN DONE`）**。重跑（A-extract-rerun，3 轮）未再卡死，但**第 2 次起抽帧失败**（`frame=null`，耗时 270–345ms）：copy-1/zero-1/copy-2 成功，zero-2、copy-3、zero-3 失败，每个失败轮各 1 条 `-12`（zero-2、copy-3）/`-1`（zero-3）。即**同一进程第 3 次抽帧开始失败，copy 配置也同样失败**，不是零拷贝独有；首次那次 8 分钟重试循环是迄今唯一一次，出现在 zero 配置 | **缺口（两配置都有问题，零拷贝多一次卡死，n 太小不能说零拷贝更差）**：抽帧器在同进程反复使用后撞上硬解码器实例上限（`-12`=ENOMEM），属 `MovaFrameExtractor` 的资源占用问题 |
| cutover（A-cutover，h264_720、hevc8 各 3 次） | 12/12 `swappedBack=true`、`epoch=2`、errors 0，广告与正片的 `hwdec-current` 在 zero 配置下 6/6 为 `mediacodec`（全库最稳的零拷贝场景）；`swappedToAd` 618–1107ms（copy 618–988，zero 629–1107，同量级）；`skipToCommit` 50–59ms，内核截图均非黑；续播误差 `resumeErrMs` copy −1200…−1867、zero −1167…−1734（该字段口径是页面自己的，两配置同量级） | 同样通过（且零拷贝更稳） |
| 小窗 mini（A-mini，h264_720 ×3） | 页内与跨路由位置连续推进到 17s，`miniFlag=true`，errors 0；zero-1/2 回落（见 A2），zero-3 真零拷贝并通过。真零拷贝只有 1 次 | 同样通过（真零拷贝样本仅 1 次） |
| PiP（A-pip，h264_720 ×3） | `enterPip=true`，`pipChange` 进入 51–54ms 都成功，errors 0，PiP 内 `hwdec-current` 与进入前一致；退出后内核截图非黑。zero-1/2 真零拷贝通过；zero-2 与 copy-2/3 的 `pipChangeOutMs=null`（本轮未记到退出事件，copy 同样 null，非零拷贝特有） | 同样通过（退出事件读数不足） |
| 切后台 bg（A-bg，h264_720 ×3） | 生命周期序列 6/6 一致（`inactive>hidden>paused>…>resumed`），`pauseProp=yes`、`autoResumed=false`（回前台不自动续播，是已知的 Android 行为），手动 play 后 `afterManualPlay` 推进 ~3s；`hwdec-current` 回前台前后不变；errors 0 | 同样通过 |
| 倍速 rate（A-rate，h264_720 ×3） | 0.5×/2×/1× 的 `speed` 读回与实测比 0.50/2.00–2.01/1.00–1.01，zero 与 copy 一致；`drops` 18–27（zero 偶尔略多：18–27 vs copy 18–20，量级相同）；errors 0 | 同样通过 |
| 换档 quality（A-quality） | **全部失败，数据不足**：6/6 `qualities=0`、`ttff=null`、`errors≥1`，两配置同样。原因：页面用外网 HLS `test-streams.mux.dev`，设备解析不了该域名（`ping` 报 `unknown host`），与零拷贝无关。未改页面用本地 HLS 重跑（本地 `rerun-sources/hls` 有 master.m3u8，需改页面常量并重建，不在本轮范围） | **缺口** |

### A6 结论与建议

- 零拷贝在 H.264/HEVC8/VP9 上功能路径（截图、cutover、小窗、PiP、切后台、倍速）与默认配置**同样通过**，没有出现零拷贝独有的黑屏/错误。
- 收益是量级上的 CPU 下降（约 5–12 个百分点单核），**回落率约 47%（非 cutover 场景）且非确定**，所以收益不稳定。
- 预览抽帧在同进程里反复使用会撞硬解码器上限，零拷贝配置还出现过一次 8 分钟重试循环；这是需要宿主知晓的限制。
- hevc10/vp8 在这台设备上都没有硬解，零拷贝不起作用（vp8 黑屏与零拷贝无关）。
- **建议**：文档里把零拷贝写成「可选、已知限制如下」：① 请求不保证拿到，需读回 `hwdec-current` 校验（本轮约一半会静默回落）；② 抽帧器与硬解并用时可能耗尽解码器实例（`-12`）；③ 10bit HEVC、VP8 无硬解；④ 收益是 CPU 量级下降而非功能差异。**不改默认值、不改产品代码**，是否采纳由你拍板。

---

## B. 点播 cutover 续播落点：新 lib vs 旧 lib 同条件 A/B

页面 `main_q13_mute_verify.dart` 的 `Q13V`：本地 `vod.mp4`，正片先播 3s，`playAdNow` 中插广告，广告起播 1s 后 `skip()`；误差 = 提交后首个位置 − 广告接管时正片位置（进度流约 250ms 一次，误差口径含 ±250ms 采样量级）。新旧各 **40 次**（8 进程 × 5 轮，交错），全部 `swapped=true`、提交后 `mute=no`。统计脚本 `tool/ab_stats_b.py`。

| 组 | n | 中位 | 平均 | 最大 | 最小 | 通过 |
|---|---|---|---|---|---|---|
| 新 lib | 40 | 280ms | 254 | 440 | 40 | 40/40 |
| 旧 lib（`da88564~1`） | 40 | 280ms | 266 | 440 | 0 | 40/40 |

按 skip 时影子是否已就绪分层（`skipToCommit` <300ms = 影子已就绪，立刻提交；≥300ms = 等影子就绪才提交）：

| 层 | 新 lib | 旧 lib |
|---|---|---|
| 影子已就绪 | n=13，中位 40，最大 240（11 次 40、1 次 80、1 次 240） | n=8，中位 40，最大 40（0、40×7） |
| 影子未就绪（等就绪） | n=27，中位 360，最大 440，最小 240 | n=32，中位 320，最大 440，最小 200 |

判断：**点播续播落点没有回归**。整体分布、最大值一致，中位两侧都是 280ms；两层的数值区间一致，影子未就绪时误差更大（200–440ms）的现象在旧版里同样存在，所以那是「等影子就绪」带来的固有行为，不是 `da88564` 引入。新版「影子已就绪」比例略高（13/40 vs 8/40，差异在随机波动内，不据此下结论），其中一次 240ms 的离群值出现在新版就绪层（旧版同层最大 40），n=1 不能定性。与 CLAUDE.md 的 +42ms 记录相比：影子先就绪的这层与之相符；影子后就绪的偏大是该机制本身。

局限：见环境快照里 Range 说明（B 实际没有走 Range seek）；误差口径含采样误差。

---

## C. 500ms 变体 A 的「影子 open 卡住」新旧对照

页面 `Q13AS`（直播正片先播 500ms，广告 VOD，影子预热正片）。新旧各 **40 次**（8 进程 × 5 轮，交错）。判定「卡住」：影子在 4s 之后仍没有任何 `time-pos>0`，或 verdict FAIL。统计脚本 `tool/ab_stats_c.py`。

| 组 | 通过/总数 | FAIL | 影子卡住（4s+ 无位置） | 影子加载耗时（`loaded Nms`，中位 / 最大） |
|---|---|---|---|---|
| 新 lib | 40/40 | 0 | **0/40** | 1814 / 2062ms |
| 旧 lib | 40/40 | 0 | **0/40** | 1800 / 2101ms |

- **本轮没有复现**：新旧各 0/40，加载耗时分布完全重合（最大 ~2.1s，远低于上轮卡住时的 >5.6s）。
- 合并上轮：新 lib 累计 1/50（上轮 1/10 + 本轮 0/40），旧 lib 0/40。**频率约 2%（1/50），事件数太少，统计上无法区分「新引入」和「老问题」**：旧版 40 次没出现，不能证明旧版没有；新版 1/50 的置信区间（粗略 0.05%–11%）与旧版 0/40（上限约 9%）大幅重叠。
- 上轮那次的证据（来自 `q13fix-S-1.log`，非本轮）：广告影子 k1 +1268ms 就绪并提交 → 正片影子 k2 +1344ms 创建 → 之后每 300ms 的 DIAG 读到 `pos=` 空、`cache=` 空、`idle=yes`，持续到 +6783ms，+6960ms 被放弃重建，重试后 +11008ms 就绪；页面的 `_waitShadowLoaded` 钉在已销毁的 k2 上，14s 后判败。正常轮里 k2 也会先有 ~2s 的 `pos=` 空 + `idle=yes`，之后才加载（本轮 80 次加载耗时 1.7–2.1s），所以「卡住」就是这段空窗没结束。本轮没捕到新的卡住样本，所以**没有新旧两侧的 `open()` 返回与 `idle`/`time-pos` 序列对照可给**。不要求定位根因，未定位。

---

## 分类汇总

| 项 | 分类 |
|---|---|
| A：H.264/HEVC8/VP9 的 codec 矩阵、截图、cutover、小窗、PiP、切后台、倍速 | 同样通过 |
| A：cutover 内零拷贝 6/6 不回落 | 零拷贝更好（更稳；原因为假设） |
| A：CPU | 零拷贝更好（量级 5–12 个百分点单核，仅量级） |
| A：非 cutover 场景请求零拷贝 47% 回落 | 零拷贝更差（不确定性；读回校验） |
| A：预览抽帧同进程第 3 次起失败（两配置）、zero 曾卡死 8 分钟 | 缺口 / 需关注 |
| A：hevc10、vp8 无硬解 | 零拷贝无效（非回归） |
| A：换档 quality | 缺口（设备无外网） |
| B：点播续播落点 | 无回归 |
| C：影子卡住 | 本轮 0/80，新旧无法区分 |

## 没能验证的部分

- 回落的直接原因（mpv 日志未转发到 logcat）；`lazyVideo=false` 对照未做。
- 10bit HEVC 在该设备的硬件能力（需 app 内枚举 MediaCodecList）。
- 换档（quality）：设备无外网，未用本地 HLS 重跑。
- B 没有走 Range seek（`live_server` 对 `bytes=0-N` 回 200，且无起点>0 的请求）。
- C 的卡住没有复现，所以没有 `open()` 返回序列证据。
- 音频、听感未测；iOS/macOS 未测。

## 本轮改动的文件

- 验证页：`example/lib/main_hwdec_matrix_verify.dart`（上一个子代理新增、未提交，本轮未改）。
- 脚本：`example/tool/ab_run.py`（新旧交错跑）、`ab_stats_b.py`、`ab_stats_c.py`、`ab_id.init.gradle`（只覆盖 applicationId）；`zero_copy_run.py`/`zero_copy_report.py`/`verify_sources/range_server.py` 为上轮新增、本轮未改。
- 文档：本文件。
- 证据：`coverage_evidence/zero-copy/`（含本轮补跑的 `A-extract-rerun.log`）、`coverage_evidence/zero-copy-ab/`。

## 收尾

设备：两个临时包 `...coverage.abnew`/`abold` 已卸载；`coverage` 与 `mova_example` 均 force-stop、未卸载；`adb reverse/forward` 已清空；设备上 `/sdcard`、`/data/local/tmp` 没有本轮产生的文件（`/sdcard/*.png` 是 10-26 的旧文件，非本轮）。本机 18080/18081/18090 服务已停（只剩 TIME_WAIT）。`stay_on`/`screen_off_timeout` 未动。`python tool/libmpv_hydrate.py --check`：`[OK] 所有 LFS 文件均为真实内容`。`git diff --stat -- lib` 为空。
