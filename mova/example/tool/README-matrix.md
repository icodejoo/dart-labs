# Android 覆盖矩阵一键入口

在仓库根目录使用 Python 3.14，无第三方 Python 依赖：

```powershell
python example/tool/run_matrix.py --list
python example/tool/run_matrix.py --check
python example/tool/run_matrix.py --dry-run --fast
python -B -m unittest discover -s example/tool -p test_run_matrix.py -v
# 以下会实际占用设备、构建目录及本地服务；先结束其他会话的复测
python example/tool/run_matrix.py --run-id regression-01
python example/tool/run_matrix.py --fast --fail-fast
python example/tool/run_matrix.py --only native-inputs,final-hls
python example/tool/run_matrix.py --from he-recovery --run-id resume-02
python example/tool/run_matrix.py --baseline example/tool/coverage_evidence/rerun-final-ledger.json
```

`--list` / `--check` / `--dry-run` 全部离线，不启动进程、不连接设备、不写证据或 build。`--check` 检查 135 编号、覆盖、依赖顺序、引用脚本语法、argv 格式及显式 argparse 选项；不能证明运行环境已具备。`--only`、`--from` 自动补 `api-launch` 启动依赖；续跑使用新 run-id、新构建和新证据，不继承上次 PASS。`--fast` 是启动/API/最终 HLS 子集，仍包含完整 API 批次，可能耗时较长。未选编号仍输出 BLOCKED。

清单共 26 批，顺序来自 `rerun_plan.py` 与 `rerun_post_plan.py`：API → HLS/QoE → HE 首帧/恢复 → keepAlive → 既有验证页 → 组件/手势/PiP → 最终 TLS/HLS/ABR → 边界/直播/原生读回 → V6 → 安全视觉/转场/小窗/预览触摸。每批覆盖编号、超时、依赖、亮屏要求及 fast 标记在 `matrix_manifest.json`。默认序列号 `7NQBB23606003715`，可设置 `$env:MOVA_MATRIX_SERIAL`（其次 `ANDROID_SERIAL`）。SDK 设置 `ANDROID_SDK_ROOT` 或 `ANDROID_HOME`；OpenSSL 可用 `MOVA_MATRIX_OPENSSL` 覆盖，否则搜索 PATH。需要 adb、Gradle/Flutter、ffmpeg、Android build-tools 和现有 debug.keystore；LFS 指针补包需要设备上已安装的独立 coverage APK，哈希不匹配即停。源素材沿用 `coverage_sources/stall.mp4`，源工作目录、媒体夹具与 TLS 临时证书按运行隔离，避免复用过期证书。

实际运行先检查空闲端口、宿主 ≥5GiB、设备 `/data` ≥1GiB、在线且亮屏解锁，再保存 USB 常亮与媒体音量；不尝试解锁。复用 `coverage_build.py` 与严格校验 LFS 的 `coverage_repack.py`，zipalign/签名/安装后拉回 APK 比对 sha256，并确认 lastUpdateTime 更新。本地源复用 `verify_sources/start_sources.py`、`coverage_media.py`、`coverage_tls.py`，自动 reverse；服务只清理本次启动的进程树。结束恢复设置、force-stop 独立包、清理本轮映射。设备锁屏立即停，手动解锁后用新 run-id 续跑；端口冲突不自动杀其他会话。

证据：`coverage_evidence/matrix-<run-id>/matrix-<run-id>-*`。`matrix_compat.py` 在子进程内隔离旧脚本证据和 `coverage_record` 文档输出，所有历史脚本调用的 adb 均记录 argv/退出码/耗时到 `*.commands.driver.log`；主入口记录 `*driver.log`。失败保存 logcat、截图、window/audio、最近 50 条事件；验证器异常单列 HARNESS。总体输出为 `doc/plans/<日期>-matrix-run-<run-id>.md` 和 `.json`，含全编号台账、基线差异及复现批次。

**判定限制**：`rerun_finalize.py` 大多是人工复核后的硬编码，不可直接重放。本入口沿用 `coverage_record.update` 的本轮完整编号结论，并直接复用终审引用的 A4/A22 两实现完整 CHECK；目前其他编号缺完整自动判据时输出 BLOCKED，原有子项记录仍保留。不会用 exit=0、旧 PASS、旧事件快照比较来替代新矩阵口径。129 个编号有执行覆盖，6 个 manual：A31/C7 缺 STT 模型链、C2 缺历史时移服务、F15 缺 WHEP、N18 缺守卫专包、N22 缺 debug 断言专包。实际完整跑完仍会有大量 BLOCKED，需人工复核或补充完整判据；这不是 135 项全自动验收器。v2 S/P/G 扩展及设备端验证页完整 L 日志未纳入此入口。任一 FAIL/BLOCKED/HARNESS 返回 1，清单错误返回 2。

异常终止无法执行 finally 时，按本轮 `*restore.json` 手动恢复设置并检查 `*driver.log` 中自有服务 PID；不要删除基线或杀其他会话进程。正常超时会终止该批次进程树；已有证据保留，使用新 run-id 重跑。

## Gap 真机补充批次（2026-10-28；本次仅离线校验）

新增 12 批（含 `gap-skin`），均 `fast=false`、`screen_on=true`，入口为 `lib/main_coverage_gap.dart`。
`covers` 保持原 135 编号语义；`covers_ext` 独立接受 `doc/ACCEPTANCE-MATRIX.md` §10
总索引编号（去掉 `v2:`/`new:` 前缀）及 H1–H78。未知编号仍拒绝。
新驱动自身输出 L 日志和完成元数据，使用 `native_driver` 绕过历史 AST 路径改写器。
`gap-result.json` 中产品 FAIL/BLOCKED 与 HARNESS 独立；扩展子项附在汇总末尾，
不把单个子项 PASS 升级成整个矩阵编号 PASS。旧 135 编号检查与判定保持原口径。

推荐先单独调用新驱动，避免 `run_matrix` 为原有批次额外构建 suite / 启动旧服务：

```powershell
# 在 mova 子目录执行；下面是供设备排期时使用的命令，本轮未执行
$env:MOVA_MATRIX_SERIAL = '7NQBB23606003715'
python -B example/tool/coverage_gap.py prepare --run-id gap01
python -B example/tool/coverage_gap.py assumptions --run-id gap01 --iterations 5 --timeout 3600
python -B example/tool/coverage_gap.py lifecycle --run-id gap01 --timeout 1200
python -B example/tool/coverage_gap.py local --run-id gap01
python -B example/tool/coverage_gap.py formats --run-id gap01 --timeout 2400
python -B example/tool/coverage_gap.py random --run-id gap01 --seed 20261028 --actions 80 --timeout 2400
python -B example/tool/coverage_gap.py skin --run-id gap01 --timeout 2640
# 只跑部分皮肤（逗号分隔，默认五套）
python -B example/tool/coverage_gap.py skin --run-id gap02 --skins default,bilibili --timeout 1800
# 与上面独立运行二选一；每次使用新 run-id
python -B example/tool/run_matrix.py --only gap-assumptions,gap-lifecycle,gap-local,gap-formats,gap-random --run-id gap02
python -B example/tool/run_matrix.py --list
python -B example/tool/run_matrix.py --dry-run --only gap-assumptions
```

`prepare` 复用原有独立 coverage 包的 Gradle/repack/签名/安装/拉包哈希核验，
只把构建 target 改为 gap 入口。仍需已安装 coverage APK 与 LFS 哈希吻合。
它用 ffmpeg 生成 120s 长 GOP + 8s 分片双档 HLS；格式样本 48s，4K 样本 16s。
所有 seek 均在 8–31s 内，远离 EOF。生成文件和完整生成 argv 位于
`example/tool/coverage_evidence/matrix-<run>-gap-prepare/fixtures/`，不提交媒体。
单独的离线生成命令：

```powershell
python -B example/tool/coverage_gap_media.py --out "$env:TEMP/mova-gap-media" --generate-only
```

格式预期按 `../mova-libmpv/flavors-mova-slim.sh` 与 `flavors-mova-slim-n9.sh`
的 Android 清单，不用更宽的通用 `configure-ffmpeg-slim.sh` 代替：

| 预期 | 样本 / 原因 |
|---|---|
| 应支持 | MP4/MKV/WebM(VP9)/TS，MP3/AAC/FLAC/Ogg，HEVC/HEVC 10bit，AV1(libdav1d)，4K HEVC |
| 硬件条件 | H264/VP9 为 MediaCodec 路径；无对应硬解器不能假称存在软件回退 |
| 软件对照 | `gap:G3.2.hevcSoftware` 用真实源属性 `hwdec=no`，打印 `hwdec-current` |
| 应不支持且须明确错误 | VP8、AC3/EAC3，以及 AVI/MPEG4、WMV2；裁剪了相关 decoder/demuxer |

引擎均由 `createMovaEngine()` 构建；H28 默认组实际调用无参数构造，对照组才开
`preciseFirstFrame`。可见视频引擎（包括 cutover 影子）均挂 `MovaPlayer`；
H7/H33 使用 `audioOnly:true`，子类只在真实 `MovaMpvKernel.open` 外记录 CALL/RET，
并连接真实 FFI END_FILE，不替换播放结果。
事件和 states/progress 全程记录；STEP 前后有 STATE，判定有 EXPECT/ACTUAL/VERDICT。
失败握手先保留现场截图、window/audio/audioflinger 和最近 50 个事件，再继续调用或清理。
watchdog 只防挂死，不作耗时判据；H28 至少三次/组，H42 打印全部 elapsed/signal 样本和均值
（grace elapsed 是超时语义，不能当首帧延迟）。

证据按同一个 `run=` 关联：各组在 `matrix-<run>-gap-<group>/` 下输出
`gap.logcat`（应用 PID）、`*driver.log`、`gap.jsonl`（增量）、`gap.json`（完成时）、
`gap-result.json`（完成与逐 case 结论）、`harness.json`、PNG 与原生 dumps。
退出码 0=执行通过，1=产品 FAIL 或前提/人工 BLOCKED，2=HARNESS；
run_matrix 读取元数据，不把退出 1 自动算库缺陷。

系统条件批次需要单独排期：

```powershell
# 真实竞争播放器：指定会处理 VIEW 并开始出声的已安装 Activity
$env:MOVA_GAP_FOCUS_COMPONENT = 'org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity'
python -B example/tool/coverage_gap.py focus --run-id gap01
# emulator-only；物理机条件用例记 BLOCKED，不发 emu 命令
python -B example/tool/coverage_gap.py focus-gsm --run-id gap01
# 不能用 adb reverse 的 localhost 来证明 Wi-Fi/蜂窝切换；prepare 时注入公网长源
$env:MOVA_GAP_NETWORK_URL = 'https://your-test-origin.example/long.mp4'
python -B example/tool/coverage_gap.py prepare --run-id net01
python -B example/tool/coverage_gap.py network --run-id net01
# 睡眠→原生 asleep→锁屏音频采样→唤醒；安全锁必须由设备主人解锁
python -B example/tool/coverage_gap.py screen --run-id gap01
```

Wi-Fi/data/飞行模式原值在 finally 恢复；切网须人工核对原生 connectivity 路由，
音频焦点须核对 dumps 的焦点拥有者与实际听感，均有明确 BLOCKED 子项，不能以 svc/启动命令成功冒充结论。
锁屏用例明确输出 `audioContinuous`、原生位置差、audio-pts、audio-out-params 与暂停/持续结论；
声卡实际输出仍需与 audioflinger 证据核对。锁屏前提失败记 BLOCKED。
H7 如旧请求被 mpv 取消而没有迟到 END_FILE(error)，H17 如实际落点偏差未超过 500ms，
相应前提记 BLOCKED。H43 收集待机前/待机 PNG 对，黑屏/冻帧由人工判图；未判图仍 BLOCKED。
`content://` 没有 SAF provider/grant，已列独立 BLOCKED case，不伪造授权 URI。

ABI/混淆/R8 是 manual 批次（命令与判据也可独立打印，不访问设备）：

```powershell
python -B example/tool/coverage_gap.py build-variants --run-id variants01
```

在 `example/` 执行 `flutter build apk --release --target lib/main_coverage_gap.dart
--obfuscate --split-debug-info=tool/coverage_evidence/gap-symbols` 保留 Dart 符号；
随后在 `example/android/` 使用新增的 `coverage_gap_variants.init.gradle`，
显式清除工程原有 ABI 过滤并启用 R8/shrinkResources：

```powershell
.\gradlew.bat -I ../tool/coverage_gap_variants.init.gradle -Pgap-abis=arm64-v8a -Ptarget-platform=android-arm64 -Ptarget=lib/main_coverage_gap.dart -Pdart-obfuscation=true -Psplit-debug-info=../tool/coverage_evidence/gap-symbols :app:assembleRelease --info
.\gradlew.bat -I ../tool/coverage_gap_variants.init.gradle -Pgap-abis=armeabi-v7a,arm64-v8a,x86_64 -Ptarget-platform=android-arm,android-arm64,android-x64 -Ptarget=lib/main_coverage_gap.dart :app:assembleRelease --info
```

变体包名 `com.icodejoo.mova.mova_example.gapvariant`。保留 `minifyReleaseWithR8` 输出、
mapping.txt、Dart symbols、APK `lib/<abi>` 清单、设备 ABI/SDK，逐 ABI 安装后核对本地/格式、
PiP/音量/亮度 MethodChannel。独立 gap 驱动默认只操控 coverage 包，变体由人工安装/取证，
不覆盖 coverage 包。x86 AOT release 不适用，debug 模拟器单独标条件；slim 包缺 x86_64 二进制
或 Android 13+ 设备未安排时 BLOCKED。不能用强制 arm64 的旧 init.gradle 充当多 ABI 结论。

预计 prepare 3–15min，assumptions 5–20min（重试/超时可更久），lifecycle 1–5min，
local/formats 2–8min，random 3–15min；系统条件各 2–5min，加人工解锁/判图时间。

### 皮肤专项（`gap-skin`，矩阵 §3.3 S）

分组 `skin`，入口同为 `lib/main_coverage_gap.dart`（`verify_auto/coverage_gap_skin.dart`，经
`gapGroups` 注册，复用 gap 的 L 日志/`caseOf`/`verdict`）。case 名 `gap:S<n>.<皮肤>.<子点>`，
`--skins` 过滤皮肤（`default,bilibili,douyin,minimal,mini`）。每个 case 单独建引擎、挂整屏
`MovaPlayer(skin:)`、打开 HLS 母带，结束先卸舞台再销毁引擎。

| 子项 | case | 判据 |
|---|---|---|
| S1 | `S1.componentNames`、`S1.<皮肤>.tree`、`S1.minimal.variants` | 38 个组件 `componentName`==`name`==期望字面量；`components()` 树（含槽位与子节点）与硬编码期望逐项相等；挂载探针（`MovaGradBar` 数、必须出现的图标、Minimal 无图标） |
| S2 / S10 | `S2.<皮肤>.layoutShot`、`S10.<皮肤>.fullscreenShot` | 出截图，视觉判定记 BLOCKED（manual）；S10 另核对 `setFullscreen(true)` 落入 state |
| S4 | `S4.default/bilibili.tap`、`S4.douyin.tap` | 单击切 `controlsVisible`、双击左右各跳 `doubleTapStep`（`MovaSeek.target` ±2s）；Douyin 单击切播放、双击点赞且不切播放 |
| S7 | `S7.default/bilibili.lock`、`S7.douyin.lockObserve` | 点锁定按钮→`locked`+一次 `MovaLockChange`；锁定后栏/中心按钮不在树上，点原位置、空白、双击无 Play/Pause/Fit/Seek/Rate/FullScreen/Volume 事件、状态不变；解锁后恢复。Douyin 无锁定入口，只记录观察 |
| S9 | `S9.default/bilibili.buttons`、`S9.<皮肤>.errorRetry`、`S9.douyin.buttons`、`S9.mini.buttons` | 逐个按钮点击对应 state/事件：中心播放暂停、fit、方向（仅移动端）、全屏进出、倍速（Bilibili 有 / Default 无）、清晰度 sheet 列全并切换；字幕按钮无 STT 时不挂载；PiP 只核对挂载，点击记 BLOCKED（避免把应用留在系统小窗，见 `gap:A15.miniPip`）；错误层重试→新的 `MovaSourceChange`；Douyin 头像/关注/评论/分享/点赞→宿主回调恰好一次；Mini 播放暂停与关闭回调 |
| S12 | `S12.default.noop`、`S12.default.patches`、`S12.bilibili.patches` | 未匹配路径空操作且不改输入；Add/Replace/Remove/InsertAfter 在树与挂载层生效，探针组件点击可改 rate（Bilibili 含锚定到内置补丁新增节点） |
| S13 | `S13.<皮肤>.inject` | 非默认 `MovaTheme`/`MovaStrs` 落到图标色/字号/标题/fit 标签/倍速后缀/缓冲转圈（Minimal 用 2s 延迟源观察到转圈才判，否则 BLOCKED）；Mini 关闭按钮色写死白色，只记录 |
| S14 | `S14.<从>.to-<到>` | 同一 api 换 `MovaPlayer.skin`（五皮肤成环）：无重开类事件、`renderEpoch`/`path`/`playing` 不变、位置不回退且继续推进、新皮肤确已挂载 |

注入走应用内 `GestureBinding.handlePointerEvent`（与真实触摸同一命中/手势竞技场链路），
日志逐次打印逻辑坐标、命中路径前 8 个 target、等价 `adb shell input tap` 物理坐标；这是对 L 规范
第 6 条“adb 原始命令”的有意替代（坐标需随转屏重新定位，不适合宿主侧盲点）。
`matrixNA` case 把矩阵已标 N/A 的 17 格（Minimal S2–S9、Mini S3–S8、Douyin/Minimal/Mini 的 S12）连同依据写入日志，不出结论。
未做：S3 直播布局、S5/S6 拖动手势（会改系统音量/窗口亮度）、S8 长按、S11 覆盖层、S15 已知失败交叉、S16 Mini 窗口专项；
`MovaNextUpComponent`/`MovaAdOverlayComponent` 需 `MovaPlaylist`/`MovaAds`，未纳入 `componentName` 一致性对账。
预计 `skin` 全量 20–45min（42 个 case，按钮/清晰度/换皮肤较慢），含 4 张 S2、5 张 S10 截图待人工判图。
