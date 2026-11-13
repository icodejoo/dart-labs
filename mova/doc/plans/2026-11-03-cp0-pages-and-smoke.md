# CP0 六场景验证页与 Android 最小冒烟（2026-11-03）

设备：STG-AL00 / `7NQBB23606003715`；release / arm64。每批运行前检查 `isKeyguardShowing=false` 与 `mScreenOnFully=true`。只跑六个新批次的最小冒烟，未跑全量矩阵；排错重跑的记录保留在 gitignored 的 `example/tool/coverage_evidence/`。

CP0 的 CHECK PASS 表示所需测量已产出。**CP0 不设产品通过线，取证完成不抵消播错源、回落或状态差异。** 完整数值与原始索引见 [数字台账](2026-11-03-cp0-smoke-numbers.json)。S00b 的独立结论与 65 项 BLOCKED 原因见 [收口报告](2026-11-03-s00b-evidence-replay.md)；本次没有把 CP0 的数字检查升级为 v1 整项通过。

## 页面、脚本、次数与结果

页面均在 `example/lib/`，各有独立 `main`；脚本均在 `example/lib/verify_auto/`。公共记录与真实挂树见 `cp0_harness.dart`。独立页使用 `--dart-define=AUTORUN=true` 开启脚本化模式，`--dart-define=RUNS=N` 指定次数。主驱动通过运行选择器传次数；独立轻量调度页是 `main_cp0_suite_verify.dart`。

| 批次 | 页面 / AUTORUN 脚本 | 正式默认次数 | 本次最小冒烟及关键数字 |
|---|---|---|---|
| cp0-p02 | `main_cp0_p02_verify.dart` / `cp0_p02_auto.dart` | 三现场各 10 | 三现场各 1，3 CHECK + END；warm/pending 最终 path=B。postLoad 在 load(B) 返回后读到上一集 A **243 次**，同一播放器原生位置跨度 **8880ms**；20s 观察上限后停在广告尾帧，未到 B。 |
| cp0-pod2 | `main_cp0_pod2_verify.dart` / `cp0_pod2_auto.dart` | 10 | 1 次，1 CHECK + END；第二条广告 epoch **0→0**，两条广告首帧事件间隔 **6514.843ms**，MovaDone 事件戳完整。**S00d 更正**：旧数据为默认 pre 不等待就绪的直接 open 分支，不能说明 cutoverTo 回落；新增 `wait.ad2`（pre:true）与 `nowait.ad2` 对照，分别记录两条广告 epoch/原生 path/time-pos/首帧戳，未上机。 |
| cp0-bgpause | `main_cp0_bgpause_verify.dart` / `cp0_bgpause_auto.dart` | 参数开/关各 5 | 各 1，2 CHECK + END；pauseUponEnteringBackgroundMode=true 时回前台仍 paused、需手动恢复 **1**；false 时继续播放、手动恢复 **0**。两组 resumeUponEnteringForegroundMode 均 false，匹配默认行为对照。 |
| cp0-pauseload | `main_cp0_pauseload_verify.dart` / `cp0_pauseload_auto.dart` | loading/Ready/FirstFrame 各 3 | 各 1，3 CHECK + END；play→FirstFrame **1035.525 / 1136.002 / −31.620ms**，加载后 playing 均为 1。A=MP4、B=WebM；B 的 sessionStart **3/3 仍报 MP4 fileFormat**。 |
| cp0-timeshift | `main_cp0_timeshift_verify.dart` / `cp0_timeshift_auto.dart` | DVR / timeshift 各 3 | 各 1，2 CHECK + END；目标 4000ms、behind=8000ms。DVR 原生 before/seek后首次/前进后/回边缘读回 **0/1640/2160/2200ms**；timeshift 为 **0/0/520/0ms**，urlBuilder 确收 behind=8000。 |
| cp0-pageview | `main_cp0_pageview_verify.dart` / `cp0_pageview_auto.dart` | 横/纵向各 3 | 各 1，2 数字 CHECK + 1 manual BLOCKED + END；横向外层 pageIndex=1、seekEvents=0；纵向 pageIndex=0、seekEvents=0。音频焦点未执行，操作见下。 |

### 数字的解释边界

- P0-2 的 `wrongEpisode` 字段只表示末次原生读回是否为 A；中途曾播放 A 要核对整个 NATIVE 轨迹。数字台账的 `p02.pathTrajectories` 从本次 CALL/RET 的数组索引划定区间，列出 A 的每一个原始记录索引及各播放器位置跨度。postLoad 的 8880ms 来自真实 time-pos 最大值减最小值，不使用墙钟。该样本复现了 source 绑定风险，未修改库。
- pod2 的旧 epochDelta=0 只证明默认不等待分支的观测，不能定性为 cutoverTo 回落。
- 暂停加载的负差表示 play 在首帧信号之后发生。取值来自同一单调时钟上的 CALL/FirstFrame 接收戳。暂停加载夹具的 B URL 保持 `/b.mp4` 身份，服务端为该身份提供真实 WebM 字节及 `video/webm`；`.fixtures.json` 保存 ffprobe 的 `matroska,webm` 与 VP8/Vorbis，因而可以区分 sessionStart 沿用 A 的 MP4 采样。B 的首帧信号附近还记录到 size=0x0，未据此声称画面已经呈现。
- 时移表中的 seek 后数字是首次真实读回，后续前进样本也保留；它们不冒充稳定落点。`#EXT-X-START` 本地 HLS 夹具用于比较 URL 重开与原生时间轴，并不提供真实商用历史时移服务，C2 manual 不解除。

## 原始证据与构建

最终引用：

- `example/tool/coverage_evidence/matrix-cp0-final5/matrix-cp0-final5-cp0-p02.json`、同目录 `*-cp0-timeshift.json`。
- `example/tool/coverage_evidence/matrix-cp0-final5-registered/matrix-cp0-final5-registered-cp0-{pod2,bgpause,pageview}.json`。这些批次实际经过 `run_matrix.Driver.preflight/batch/cleanup`，每个变体 runs=1；各 batch END kind=OK。
- `example/tool/coverage_evidence/matrix-cp0-sessionstart2/matrix-cp0-sessionstart2-cp0-pauseload.json` 及同前缀 `.fixtures.json`，使用可区分容器的最终夹具。
- 每批都有 `.commands.log`、按进程筛选的 `.log`、`.window.txt`、`.audio.txt`；JSON 保留完整 CHECK（Android logcat 的单条长消息可能截断）。
- 最终 APK 的本地与设备拉回 SHA-256 均为 `cd41221cea79a13548c1ec8c6ee4ea2c829f218bc5098407113f8d69bc8f4ad6`；元数据在 `matrix-cp0-final5/*-cp0-timeshift.build.json`，含全部 CP0 Dart 文件哈希，与提交源码逐个核对一致。
- `python tool/libmpv_hydrate.py --check` 通过。构建使用当前树已水合的 arm64 JNI；wrapper 缺失时由本机 Flutter SDK 缓存复制到本树 example。多次构建遇到宿主提交内存耗尽（JVM/PowerShell/Dart OOM），降低并发后完成；失败运行与 JVM crash 文件保留。未停止其他进程。
- 注册路径排错时父驱动曾重复移除子驱动已经恢复的 reverse 映射；最终映射与原值一致。已修正 CP0 的映射所有权并加入回归测试。媒体音量恢复为原值 0/20，USB 常亮恢复为原值 7。

## 正式运行方式

在 mova 根目录，仅运行 CP0 六批（按上表正式默认次数）：

```powershell
python -B example/tool/run_matrix.py --only cp0-p02,cp0-pod2,cp0-bgpause,cp0-pauseload,cp0-timeshift,cp0-pageview --run-id cp0-own-baseline
```

每次使用新的 run-id。仅选 CP0 时构建轻量调度页，不启动旧矩阵服务；全量运行仍走原共享调度页。主入口支持现有 list/check/dry-run/only/run-id/baseline。每个场景的宿主驱动是 `coverage_cp0.py`，可以最小补跑：

```powershell
python -B example/tool/coverage_cp0.py pod2 --run-id cp0-pod2-smoke --runs 1 --build
```

同一个已安装调度 APK 后续批次省略 `--build`。本地源复用 `verify_sources/range_server.py` 的 Range 服务并通过 adb reverse；HLS 夹具由 ffmpeg 生成。观察超时只限制等待，不是 CP0 产品通过线。原生 path/time-pos 未就绪时有界轮询，切换播放器期间重新读活动播放器，避免混用退役播放器的读数。

## 音频焦点：manual BLOCKED

缺少可自动控制的来电设备或其他 App 抢焦点源，本次未执行来电/其他 App 放音。pageview 页提供“音频焦点手工记录”按钮，持续循环本地素材，记录事件和生命周期；它不要求执行 PageView 自动脚本。

在 `example/` 目录，先启动独立本地源（另一个终端保持运行）：

```powershell
python tool/verify_sources/range_server.py --dir tool/coverage_evidence/matrix-cp0-final5-registered/matrix-cp0-final5-registered-cp0-pageview-sources --port 18190
```

随后：

```powershell
adb -s 7NQBB23606003715 reverse tcp:18190 tcp:18190
adb -s 7NQBB23606003715 forward tcp:18083 tcp:18083
flutter run --release -d 7NQBB23606003715 -t lib/main_cp0_pageview_verify.dart
```

不加 AUTORUN，点击“音频焦点手工记录”，用手机音量键设置可听音量。每类操作重复 3–5 次：

1. 播放中请求 `http://127.0.0.1:18083/snapshot` 保存 before JSON。
2. 用另一设备呼入测试机，分别记录来电响铃、接听、挂断后的快照；记录是否暂停、playing/intent、恢复是否需手动及 Pause/Play 事件戳。
3. 对“其他 App 放音”另起样本：在另一个 App 开始播放、停止播放并返回验证页，分别保存快照；记录当前音频路由和实际能否听见视频。
4. 导出最后一次 `/snapshot` 完整 records，另存 `adb shell dumpsys audio`。结束后停止验证 App 与本地服务，移除本次 forward/reverse，恢复手工调整前的媒体音量。

人工入口与实际来电/抢焦点联动尚未做真机验证，不能解除该 manual 项。

## 检查与尚未完成

Python 自测覆盖矩阵收口、完整来源、旧记录隔离、损坏证据、事件别名、CP0 CHECK 齐全性与映射所有权；最终 31 项通过，`run_matrix --check` 通过。新增 Dart 页面及公共骨架静态分析通过。未运行库全量测试或全量真机矩阵，未修改 lib/test。

**S00 的完整验收目标仍未满足**：r1030 重放为 61 PASS / 9 FAIL / 65 BLOCKED，仍有需补完整判据的编号，逐条缺口在 S00b 报告。六个新场景的自动部分均已产出可复核数字；音频焦点维持 manual BLOCKED，正式次数的完整 CP0 基线留给用户跑批。
