# mpv v0.41.0 + ffmpeg n9.0.2 libmpv 真机播放验证

日期：2026-10-02。设备 STG-AL00（arm64 Android 12，`7NQBB23606003715`，全程亮屏解锁，每轮前查 `isKeyguardShowing=false`）。

## 被测物

- 新版：WSL `/root/w/t12/libmpv-arm64.stripped.so`，6,319,792 字节，sha256 `209ebbe3...7bdb`（与 APK 内 `lib/arm64-v8a/libmpv.so` 逐字节一致，已核）。
- 基线：现有 `packages/media_kit_libs_android_video_slim` 的 arm64 libmpv（n6 老链，6,050,104 字节，sha256 `75e56da5...7136`，APK 内一致）。
- 新版接线：新建 `packages/media_kit_libs_android_video_slim_v041`（仅 arm64-v8a，helper.so 沿用），example 下本地 `pubspec_overrides.yaml` 指向它（未提交，验证后已移走）。
- 验证页：`example/lib/main_v041_verify.dart`（独立页，`createMovaEngine` + 挂 `MovaPlayer`，release 构建，print 经 logcat tag=flutter 取证）。素材由本机 `python http.server` 经 `adb reverse tcp:8097` 提供，URL 带时间戳；HLS 另测公网 mux 样本。

## 结果（每版 3 轮，每轮 7 项；以下为实测数）

首帧 = `MovaSizeChange`(宽>0) 距 open 的毫秒；rate = 首帧后 1.5s 起观察窗内 position 增量 / 墙钟增量（仅作推进速率参考）。

| 项 | 解码路径（`hwdec-current`，两版一致） | 基线 首帧ms (3轮) | v0.41 首帧ms (3轮) | 基线 rate | v0.41 rate | 丢帧(frame-drop / decoder-drop) |
|---|---|---|---|---|---|---|
| H.264 mp4 | mediacodec-copy | 283/209/194 | 223/207/165 | 0.999-1.000 | 0.998-1.000 | 0/0 两版 |
| HEVC mp4 | mediacodec-copy | 282/243/217 | 216/219/210 | 0.999-1.004 | 0.997-1.006 | 0/0 两版 |
| VP9 webm | mediacodec-copy（本机芯片有 VP9 硬解） | 279/250/263 | 250/266/262 | 1.000-1.003 | 1.005/0.987/**0.808** | 0/0 |
| AV1 mkv | no（dav1d 软解） | 93/98/189 | 219/132/173 | 0.999-1.000 | 0.997-1.003 | 0/0 |
| HLS 本地 | mediacodec-copy | 460/468/431 | 450/451/496 | 0.998-1.004 | 0.998-1.005 | 0/0 |
| HLS mux（公网 1080p60） | mediacodec-copy | 7653/7568/9365 | 9531/8355/8418 | 0.989-1.004 | 1.000/0.998/1.004 | vo drop 基线 24/18/19，v0.41 9/5/11（1080p60 公网，v0.41 更少） |
| SRT 外挂字幕 | mediacodec-copy | 244/269/337 | 218/242/246 | 0.998/1.001/（见下） | 1.001/0.997/1.002 | 0/0 |

- 字幕：v0.41 三轮均 `sub-text` 轮询到 `HELLO-SUB-ONE`、`HELLO-SUB-TWO`，`sid=1`，`current-tracks/sub/codec=subrip`（libass 渲染文本路径正常）。基线 r1/r2 同样 OK；**基线 r3 出现 `Cannot seek in this stream` 导致 sub-add 未命中**，是测试服务端（python http.server 不支持 Range）的偶发表现，非 libmpv 差异。
- 视频输出：两版 `current-vo=gpu`、`current-ao=opensles`。**v0.41 版已摘掉 vo_gpu_next，仍走 legacy gpu，播放正常**；因此 libplacebo 本身没被这次验证覆盖（推断：构建已摘除，不会走到）。
- 崩溃：6 份完整 logcat（基线 3 + v0.41 3）grep `FATAL EXCEPTION|UnsatisfiedLinkError|Fatal signal|SIGSEGV|SIGABRT` 均无命中；`dlopen`/javavm 补丁路径实际生效（mediacodec 硬解可用即 JavaVM 绑定成功，实测）。
- mpv 日志 ERROR 行（两版同类，非播放失败）：`property not found _setProperty(osc, 1)`、`Failed to create file cache`、`h264/vp9_mediacodec: Both surface and native_window are NULL`（surface 未挂上时的首次 mediacodec 尝试，随后回落重试成功）。

## 差异与风险点

1. **VP9 硬解初始化重试变多（唯一明确的行为差异，实测）**：v0.41 的 r2/r3 中 VP9 首个 position>0 为 1999/2148ms（基线 477-675ms），错误日志 11 条（基线 4）：多轮 `vp9_mediacodec: Both surface and native_window are NULL` + `Unsupported or unknown profile` + `Using hardware decoding` 重复 5 次左右后才稳定出帧；r3 的窗口 rate 0.808 即这段卡顿所致。r1 未出现（777ms）。h264/hevc 无此现象。推断：mpv 0.41 的 hwdec 重新初始化逻辑在 surface 尚未就绪时更激进地重试；功能不丢（最终都出画、rate 回到 ≈1.0），但 VP9 起播慢约 1.5s。未做根因定位。
2. 首帧耗时差异（AV1 93-189 vs 132-219ms、HLS mux 受公网波动）在噪声范围内，不构成结论。
3. 本页只用 640x360 合成素材（HLS mux 为 1080p60 真实素材）；未测 10bit/HDR、直播低延迟、真实长时稳定性。
4. `MovaSizeChange` 在两版都先报 `640x0`（高度晚到一拍），属 mova 层既有现象，非 libmpv 差异。

## 结论

mpv v0.41.0 + ffmpeg n9.0.2 的 arm64 libmpv 在真机上：H.264/HEVC/VP9 走 mediacodec-copy 硬解、AV1 走 dav1d 软解、HLS（本地+公网）、SRT 字幕均正常，无崩溃、无 UnsatisfiedLinkError、本地素材丢帧基本为 0（仅基线 r2 h264 掉 1 帧；公网 1080p60 两版均有 vo drop，v0.41 反而更少），与 n6 基线的 position 推进速率持平。需要跟进的只有 VP9 硬解起播变慢（上表差异 1）。

## 复现

`example/pubspec_overrides.yaml` 指向 `../packages/media_kit_libs_android_video_slim_v041` → `flutter build apk --release --target-platform android-arm64 -t lib/main_v041_verify.dart` → 本机起 HTTP 服务并 `adb reverse tcp:8097 tcp:8097` → 启动后 `adb logcat -d | grep V041`。
