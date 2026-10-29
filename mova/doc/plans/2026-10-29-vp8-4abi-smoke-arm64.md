# 新 libmpv（含 VP8 `vp8_mediacodec`）冒烟：arm64 真机（2026-10-29）

> 设备 STG-AL00（7NQBB23606003715，Android 12，骁龙 662），release 包，亮屏已解锁。页面 `example/lib/main_vp8_4abi_smoke.dart`，样本 `rerun-sources/codec/`，由 `range_server.py`（18090）提供。
> **只验了 arm64-v8a**；armeabi-v7a/x86/x86_64 没有设备也没有 AVD，数据不足。本轮没改 `lib/`。

## 先踩的坑：`coverage_build.py` 默认打的是旧 so

`tool/coverage.init.gradle` 把 `media_kit_libs_android_video` 的 jniLibs 指到 `example/tool/coverage_native/`（未跟踪的固定旧副本，arm64 sha256 `798cde9e…`），盖掉了 slim 包里 `9a9321a` 合并的新 so（`27cad80e68e1f7bacfee5a1c71842e3ae6056cdd9285bef50577f0d5e5063fb0`，6,360,608 字节）。第一轮结果因此作废，仅作旧版对照。
本轮用 `tool/smoke_native.init.gradle`（排在 coverage 之后）改指 slim 包自带 so，并核对 APK 内 so 的 sha256 与仓库一致。之后凡用 `coverage_build.py` 验新 so，都要先确认 APK 里的 sha256。

## 结果（新 so，证据 `example/tool/coverage_evidence/vp8-4abi/arm64-new.log`；旧 so 对照 `arm64.log`）

| 用例 | 次数 | 结果 |
|---|---|---|
| `vp8_default`（不加属性） | 3 | 3/3 失败：`Failed to initialize a decoder for codec 'vp8'.`，`size=0x0`，无 `hwdec-current`，与旧 so 相同 |
| `vp8_ndk`（`vd-lavc-o=ndk_codec=1`） | 5 | 0–2 次：出画面 640x360，`hwdec-current=mediacodec-copy`，位置推进 ~4.4s，ttff 210–344ms，errors 0；**第 3、4 次：`rendered=true` 但位置始终 0，进程 CPU 飙高（Thread 60%+、主线程 ~49%、`NDK MediaCodec_` 33%），心跳最大间隔 458–621ms**，卡死状态 |
| `h264_fs`（播到结尾） | 2 | 2/2 `completed`，errors 0，`mediacodec-copy` |
| `vp9`（播到结尾） | 2 | 2/2 `completed`，errors 0，`mediacodec-copy` |

## 判断

- 新 so 的 VP8 MediaCodec 路径**不是默认开启**：必须显式 `ndk_codec=1`，默认仍报解码器初始化失败。
- 显式开启后前 3 次可用，**同进程第 4 次起卡住**（位置不推进、CPU 打满），像是解码器实例没释放干净或初始化后死循环；n=5、单设备，不能定性，也没有 mpv 日志（未转发到 logcat）。与前文「预览抽帧同进程第 3 次起撞硬解码器上限」的现象类似，但本页没用抽帧器，未证实同根因。
- h264/vp9 无回归。

## 待办（数据不足）

1. 复现 `vp8_ndk` 第 4 次卡住：看是否随「前几次的 Player 未真正释放」出现，并抓 mpv 日志。
2. 其余三个 ABI：需要设备或 x86_64 模拟器。
3. `vp8_default` 为何不走 `vp8_mediacodec`：需确认 CI 里该解码器的注册与默认优先级。

## 补：`vp8_ndk` 卡死抓日志（同日，同设备同 so，8 次连续）

证据：`example/tool/coverage_evidence/vp8-4abi/arm64-hang.log`（页面改为只跑 `vp8_ndk`×8，并把 mpv 解码相关日志每轮最多 400 行打到 logcat；这是临时改动，页面未提交）。

**复现**：8 次里 4 次卡住（第 2、3、4、7 次：位置 0、CPU 打满），第 1 次 `hwdec-current=no`（没走 MediaCodec，位置仍推进），其余 3 次正常。卡住的间隔不规则，不是「第 4 次起」，上一轮的说法要改成「约一半概率」。

**卡住时 mpv/系统日志**
- mpv：`vd: Selected decoder: vp8_mediacodec` 和 `Using hardware decoding (mediacodec-copy)` 都已成功，随后循环刷 `vp8_mediacodec: Failed to dequeue output buffer (status=-10000)` + `Error while decoding frame!`。每轮日志上限 400 行，卡住轮 decodeErr 为 155/341/154/341（后两个触顶），正常轮 3–5 次。
- 系统：`NdkMediaCodec: sf error code: -38` 全程 74764 次刷屏（约每毫秒级）。这就是 CPU 打满的来源：解码器空转重试，没有退避。
- 卡住轮（及部分正常轮）开头有 `vp8_mediacodec: Both surface and native_window are NULL`、`Failed to getCodecNameByType`，随后 `MediaCodec started successfully: codec = c2.android.vp8.decoder`——即落到 Android 的 Codec2 软件 VP8 解码器，而不是高通硬件解码器。
- 这组特征不是严格一一对应：第 0、6 次也有同样的开头日志却正常（dequeue 失败仅 5 次），第 3、7 次触顶被截断看不到开头。**能说的只是：卡住轮都出现大量 dequeue 失败 + -38 空转；开头那几行是否是诱因，证据不足。**

**初步指向（推断，未验证）**：`vp8_mediacodec` 在 mpv 里走 ffmpeg 的 `mediacodec` 包装时没拿到 surface（`mediacodec-copy` 本应无 surface，`Both surface and native_window are NULL` 对 copy 路径可能是正常提示），输出缓冲 dequeue 返回 -10000 后 ffmpeg 没有等待/退避地反复调用。需要看新 so 里 ffmpeg 补丁（VP8 的 `vp8_mediacodec` 注册）对 `ndk_codec` 与 dequeue 超时的处理，属 mova-libmpv 那边的改动，不是 mova Dart 侧能修。

**未做**：没抓到 Codec2 与硬件解码器之间的选择依据（`MediaCodecList` 枚举）；没试 `ndk_codec=0`、没试 `hwdec=mediacodec`（零拷贝）；其它三个 ABI 未验。

## 补：补丁 0009 验证（arm64，CI 构建产物）

so：CI run 40838203263（分支 `jelon/vp8-dequeue-spin`，提交 `c29d638`，`commit_artifact=false`），sha256 `37c1b43f70d4d9aa461e5cf20dca247a825a0a2e6decdc3257a7b962ec61b4cc`，6,360,912 字节（旧 6,360,608，+304）；经 `-PsmokeJni` 指向临时 jniLibs 构建，APK 内 so 的 sha256 已核对一致。证据 `coverage_evidence/vp8-4abi/arm64-0009-b.log`（解锁亮屏，开跑前后 `isKeyguardShowing=false`；同日先跑的 `arm64-0009.log` 开跑前锁屏，作废）。

`vp8_ndk`×8：4 次正常出画面（`mediacodec-copy`，1 次 `no`），4 次触发 dequeue 失败并在 30 次连续错误后走 `giving up` 停止解码（第 0、3、5、6 次）。
- **卡死 0/8**（此前 4/8）。触发失败的 4 次，主线程 CPU 2–5%（此前 50% 以上），音频位置推进到约 4.4s，主线程心跳最大间隔 248–377ms（此前卡死轮 458–621ms）。
- `NdkMediaCodec sf error -38`：228 行（此前 74764 行）。
- **失败触发率仍是 4/8，没有变化**：0009 只让失败停得下来，不降低 dequeue 出错的概率；停下后该次视频无画面，只有音频，宿主侧表现为 `MovaErrorEvent`（`Decoder vp8_mediacodec keeps failing after fallback, giving up.`）。
- 局限：n=8、单设备；失败的真正触发原因仍未查清（见上一节）；其余三个 ABI 未验；0009 为草稿，30 次的上限无依据。

## 补：调度链路核对与两个假设的验证（arm64，旧 so `27cad80e`，无 0009）

**调度链路（源码：ffmpeg n9.0.2 `mediacodecdec*.c`/`mediacodec_wrapper.c`，mpv v0.41.0 `vd_lavc.c`，已对照日志）**
- ffmpeg 无原生 VP8 软解，mpv 解码器候选只有 `vp8_mediacodec`；`hwdec-codecs` 含 vp8，`auto-safe` 选 `vp8_mediacodec-mediacodec-copy`。
- `ndk_codec` 默认 -1：有 JavaVM（0002 补丁设置）走 JNI。JNI 枚举 `getCodecNameByType` 跳过 `isSoftwareOnly`/`OMX.google` 等软件解码器，本机只有 `c2.android.vp8.decoder`，枚举为空 → 默认路径初始化失败（**根因已确认**）。
- `ndk_codec=1`：枚举仍为空，随后按 MIME `createDecoderByType`，由系统选中 `c2.android.vp8.decoder`（系统软解），`hwdec-current=mediacodec-copy` 有误导性。
- mpv 回退：硬解连续失败 3 次 → `force_fallback` → “软解”候选仍是同一个 `vp8_mediacodec`；回退后 `handle_err` 不再计数（0009 针对此处）。
- mova 代码里没有任何地方设置 `ndk_codec=1`，设计文档 `restore-vp8` §1.1 “MediaCodec 带软解兜底”对 JNI 默认路径不成立。

**每轮都有 3 次 `Opening decoder`，且 8/8 轮都发生 1 次硬解失败回退**：第一帧后约 0.35s，真正的 GPU VO 接上（`dropping frame due to pin disconnect`），解码器在 4ms 内被连续重开两次，新实例随即连续报错并触发回退。

**验证（`arm64-vo.log`、`arm64-cool.log`，均解锁亮屏）**
| 实验 | 结果 |
|---|---|
| h264、vp9 对照各 4 次 | 同样 3 次 `Opening decoder`，但 **0 回退、0 错误、0 卡死** → 重开本身对硬件解码器无害，问题限于 VP8 的 Codec2 软件实例 |
| `vp8_ndk` 基线 | 一批 7/10 卡死（`arm64-vo.log`），另一批 **0/10**（`arm64-cool.log`），此前 4/8 → 同样条件下批次间 0–70%，**非平稳** |
| 开文件前等 5s（我以为是等 VO，实际 `vo` 选项 5s 内始终 `null`，等于纯延时） | 1/10（第一批）、5/10（第二批）→ 结论反复，**无效** |
| 创建 Player 前冷却 5s（让上一轮解码器释放） | 6/10 → **无效** |
- 因此以下假设都**不成立**：“VO 晚于解码器接上导致重建而出错”（延时后重建次数不变、仍 10/10 回退）、“上一轮解码器没释放干净”（冷却无改善）。
- 卡死呈**连续成簇**（如 `HHH...HHH.`），更像设备/媒体服务的某种持续状态而非每轮独立随机；设备 logcat 无 swcodec 崩溃、`binderDied` 等迹象（本轮 120 个 `c2.android.vp8.decoder` 组件均正常创建）。
- **触发 dequeue `-10000` 的根因仍未查到。**

## 补：原生 media_kit 对照（排除 mova 层）

页面 `example/lib/main_vp8_pure_media_kit.dart`：同一进程内 mova（`createMovaEngine`+`MovaPlayer`）与原生 media_kit（`Player`+`VideoController`+`Video`，不引入 mova）交替各 12 轮，同一旧 so（`27cad80e`）、同一 `vp8.webm`、同样 `vd-lavc-o=ndk_codec=1`，解锁亮屏。证据 `coverage_evidence/vp8-4abi/arm64-pure-vs-mova.log`。

| 内核 | 卡死 | 回退 | 解码器打开次数 |
|---|---|---|---|
| mova | 6/12（`H.H.HH.H.H..`） | 12/12 | 恒为 3 |
| 原生 media_kit | **9/12**（`HH..HH.HHHHH`） | 12/12 | 恒为 3 |

- **结论：与 mova 无关。** 完全不经过 mova 的原生 media_kit 同样卡死，且不比 mova 少；每轮 3 次重开与 1 次回退也一样，所以前一节的“重建”也不是 mova 引入的。
- 原生组卡死轮里 `Failed to dequeue output buffer` 计数为 0，而 `Error while decoding frame` 高达 15162，与 mova 组（dequeueFail 18582）的错误文本分布不同；没有进一步看原生组具体是什么错误，留作待查。
- 因此问题落在 libmpv 内部（mpv 调度 + ffmpeg `vp8_mediacodec` + 系统 `c2.android.vp8.decoder`）。

## 补：原生 media_kit 卡死轮的完整 mpv 日志

证据：`coverage_evidence/vp8-4abi/arm64-pure-only.log`（原生 media_kit 单独占一个进程，12 轮，旧 so，解锁亮屏）：卡死 9/12（`H.HHHHHH.H.H`）。

**更正前一节**：“原生组 `Failed to dequeue` 为 0、错误文本分布不同”是**采集假象**——ffmpeg 日志是进程级回调，同一进程里交替创建多个 Player 时会被归到某个实例，原生组拿不到；单独占进程后原生组同样有 `Failed to dequeue output buffer (status=-10000)`。另外 Dart 侧给日志行打的是**接收时间**，mpv 日志按批送到 Dart，毫秒级的先后间隔**不可信**（此前“4ms 内重开两次”等说法只能当先后顺序用）。

**卡死轮与正常轮完全相同的前半段**（原生，第 2 轮卡死 / 第 8 轮正常）：
1. 实例 #1：`Failed to getCodecNameByType` → `MediaCodec started successfully: codec = c2.android.vp8.decoder` → `Output MediaFormat changed` → `Using hardware decoding (mediacodec-copy)`，正常出帧。
2. 首帧之后 mpv 重开解码器得到实例 #2：同样 `started successfully`，**随后立刻** `Failed to dequeue output buffer (status=-10000)` ×3 → `Failed to flush codec` → 触发回退（12/12 轮都发生）。
3. 回退得到实例 #3：
   - **正常轮**：`started successfully` 后出现 `Output MediaFormat changed`，恢复出帧。
   - **卡死轮**：`started successfully` 后又是 `dequeue -10000`、`Failed to flush codec`，此后每个包都失败（`Error while decoding frame` 上万次）。
- 因此“失败在启动后”是共同点，区别只在 #3 能否恢复。每次失败的实例都是**刚成功 start、尚未收到任何输出就 dequeue 报错**。
- NDK 侧 `sf error code: -38`（stagefright `INVALID_OPERATION`，对应 codec 不在 STARTED/FLUSHED 状态）：表明失败的实例在 `start()` 返回之后已处于异常状态，并持续保持。

**据此能说的**：问题发生在 `c2.android.vp8.decoder`（系统 Codec2 软件 VP8 解码器）被 mpv 重开出的新实例上，与 mova 无关、与调度顺序无关；实例刚 start 完就进入错误状态的原因，需要 Codec2/`media.swcodec` 侧的日志才能看到（`CCodec`、`MediaCodec`、`Codec2Client`、`C2SoftVpxDec` 等标签），应用层日志已到头。

## 结论：VP8 卡死的根因（已查实）

**一句话**：mpv 在播放开始后重开解码器，新实例收到的**第一个包不是关键帧**；系统的 `c2.android.vp8.decoder`（libvpx）对此返回 `UNSUP_BITSTREAM`，并把整个 codec 打进不可恢复的错误状态；mpv 的回退又把同一批包重放一遍，再失败一次，是否恢复取决于之后有没有出现第 4 个实例。

**证据链（每一环都有日志）**
1. mpv 每轮都在首帧后重开解码器（`Opening decoder` ×3，`dropping frame due to pin disconnect`）。h264/vp9 同样重开但**无害**——硬件解码器会自己跳过关键帧之前的包。
2. 系统侧 `media.swcodec`（pid 1690）：`C2SoftVpxDec: on2 decoder failed to decode frame. err: 5`。`err 5` = libvpx `VPX_CODEC_UNSUP_BITSTREAM`，`vp8_decode` 的明确行为：解码器未初始化且首帧非关键帧时返回该值（[libvpx `vp8_dx_iface.c`](https://achurch.org/SIL/current/external/libvpx/vp8/vp8_dx_iface.c)；WebRTC 的 VP8 封装因此要求先收关键帧）。
3. 紧接着 `CCodecBufferChannel: work failed to complete: 14` → `MediaCodec: Codec reported err 0xe, actionCode 0, while in state 6/STARTED`：该实例进入错误状态，此后 NDK `dequeueOutputBuffer` 返回 `-10000`、`sf error code: -38`，`flush` 失败（`Failed to flush codec`），全部与应用层日志吻合。
4. mpv 回退（`Attempting next decoding method`）把已发送的包重放给实例 #3，**同样以非关键帧开头**，#3 也失败。每轮 libvpx 失败恒为 2 次。
5. 区别只在后面：**正常轮出现第 4 个实例并成功**（`rCsrCsFErCsFErCs`，之后 `Output MediaFormat changed`）；**卡死轮没有第 4 个实例**（`...CsFErCsFE`止于此），错误实例一直留着，每个包都失败，就是 0009 要截断的空转。
6. **反证实验**（原生 media_kit，同进程交替各 12 轮）：

| 样本 | 卡死 | libvpx 失败/轮 | 回退 |
|---|---|---|---|
| 原样本 `vp8.webm`（约每 100 帧一个关键帧） | 7/12 | 恒为 2 | 12/12 |
| 全关键帧样本 `vp8_allkey.webm`（`-g 1`） | **0/12** | **0** | **0/12** |

   两者解码器重开次数相同（3 次）→ 重开无害，**“首包非关键帧”才是触发条件**。

**为什么概率是 50% 且成簇**：第 4 个实例由哪条路径触发（回退之后的 `hr-seek`/重置）与时序有关；这条恢复路径是否被走到才是随机的，与媒体服务状态无关。（之前的“冷却/延时/VO 切换”假设都因此不成立。）

**与 mova 无关**：原生 media_kit 卡死 7–9/12，与 mova 相同。

**问题归属与修法**
- 缺陷在 ffmpeg 的 `mediacodec` 包装：它没有像软解那样“丢掉关键帧之前的包”，直接把任意包塞给系统解码器；mpv 重开解码器时又没有从关键帧重新开始。
- **补丁 0016（已起草，`mova-libmpv/patches/ffmpeg-whep/0016-avcodec-mediacodecdec-vp8-drop-leading-non-key-packets.patch`）**：只对 `vp8_mediacodec`，解码器初始化与 flush 之后置 `need_keyframe`，丢弃非关键帧直到第一个关键帧。对原版 n9.0.2 `git apply --check` 通过；**未编译、未真机验证、未接入构建脚本**。
- 补丁 0009（mpv，已在 CI 构建验证能截断空转）保留作兜底。
- 依赖假设：mpv 送给解码器的包带 `AV_PKT_FLAG_KEY`（mpv `mp_set_av_packet` 按 demux 的 keyframe 标志设置，mkv 路径可用；WHEP 路径取决于 0015 解包器是否设该标志，**未验证**）。
- 验证 0016 需要重编 arm64 so（用户要求用本地环境，不依赖云端 CI；WSL 评估环境已不存在，尚未重建）。

## 补丁 0016 真机验证（本地环境构建）

构建：WSL Ubuntu 24.04 + NDK r25c，`e2e-arm64.sh`（`WHEP=1 ARCH=arm64`，与 CI 同脚本）。先做不加 0016 的基线构建：6,360,848 字节，与 CI 产物（6,360,912 字节）相差 64 字节，原因是产物内嵌 3 处构建目录路径（本地 `/root/work-base` 比 CI 的 `/home/runner/work/_temp/whep-android` 短 21 字符×3），代码一致，非逐字节比对。0016 版：6,361,248 字节，sha256 `4ee4fd5b8a8a6d3e0a79e99ee63dbbfb421e7398c56c56e109d737f9f318103b`，3 个导出符号齐全，含 `Dropping non-key VP8` 字符串。构建中途因补丁字符串转义错误（C 字符串里带真实换行）编译失败一次，已修正，补丁文件为修正版。

真机（STG-AL00，解锁亮屏，APK 内 so 的 sha256 核对一致）：原生 media_kit，原样本与全关键帧样本交替各 12 轮，证据 `coverage_evidence/vp8-4abi/arm64-0016.log`。

| 样本 | 卡死 | libvpx 失败/轮 | 回退 | 解码器打开次数 | `hwdec-current` |
|---|---|---|---|---|---|
| 原样本（旧 so：7/12、2、12/12） | **0/12** | **0** | **0/12** | 3 | `mediacodec-copy` |
| 全关键帧样本 | 0/12 | 0 | 0/12 | 3 | `mediacodec-copy` |

- 重开仍是 3 次，但新实例不再收到非关键帧开头的包，不再触发 `UNSUP_BITSTREAM`；根因判断得到修复侧的验证。
- 局限：n=12、单设备、单个 ABI；只验了原生 media_kit 页面（mova 路径与它同一个 libmpv，预期一致，未单独跑）；未做 seek/长时间播放/WHEP 的回归；其余三个 ABI 未构建。
- 复现全关键帧样本：`ffmpeg -t 12 -i vp8.webm -c:v libvpx -g 1 -b:v 2M -crf 10 -c:a copy vp8_allkey.webm`。
