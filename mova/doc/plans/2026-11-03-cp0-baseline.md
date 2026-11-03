# CP0 正式基线尝试（2026-11-03）

**状态：BLOCKED，正式真机样本 0。未完成 CP0，不发出 `P1-3 DONE`。**

指定 STG-AL00 / `7NQBB23606003715` 在 2026-11-03T04:17:59.032370+00:00 至 2026-11-03T04:27:58.905630+00:00 连续不可见。每30秒检查 ADB 与 window，21 次检查、总计 600.2s，无一次取得解锁亮屏状态。原始错误为 `adb: device not found`，`adb devices -l` 无设备。按用户要求，等待满10分钟后停止，保留本地准备与构建结果。

## P1-3 准备及结论边界

新增独立页 `example/lib/main_cp0_autotier_verify.dart`、AUTORUN 脚本 `verify_auto/cp0_autotier_auto.dart`，在 `matrix_manifest.json` 注册 `cp0-autotier`。`run_matrix.py` 无改动；coverage1 规则无改动。通过 `main_cp0_suite_verify.dart` 调度，默认五轮限速、一轮不限速，每轮90秒；`createMovaEngine()` 默认配置，真实挂树，未手选清晰度、未开启原生事件泵。

ffmpeg 生成120秒三档 CBR HLS（无音轨）：256×144/160 kbit/s、640×360/700 kbit/s、1280×720/2400 kbit/s。共享总限速900 kbit/s，HTTP no-store，master/子列表/分片继承时间戳。每秒记录原生 path/time-pos、hls-bitrate、video-params/w/h、vid、track-list、demuxer-cache-state、paused-for-cache 及 Mova 事件和 renderEpoch。切档时刻只给相邻采样区间，次数为观测下界；缓存区间与 time-pos、事件一起复核，未把采样戳当事件戳。

本地两条并发 HTTP 请求合计实测限速 **112024.6 B/s**，不限速 **253019089.3 B/s**。这是夹具验证，不是真机播放。起播档、切档次数/时刻、卡顿、崩溃和回落均**未测**；失败数为 null，不能写成0失败。

## 各阶段次数

| 阶段 | 项目 | 计划次数 | 已执行 | 数字/失败 |
|---|---|---:|---:|---|
| 1 | P1-3 限速 auto | 5 | 0 | 未测 / null |
| 1 | P1-3 不限速对照 | 1 | 0 | 未测 / null |
| 2 | p02.contentWarm | 10 | 0 | 未测 / null |
| 2 | p02.midPending | 10 | 0 | 未测 / null |
| 2 | p02.postLoad | 10 | 0 | 未测 / null |
| 2 | pod2 | 10 | 0 | 未测 / null |
| 2 | bgpause.true | 5 | 0 | 未测 / null |
| 2 | bgpause.false | 5 | 0 | 未测 / null |
| 2 | pauseload.loading | 3 | 0 | 未测 / null |
| 2 | pauseload.ready | 3 | 0 | 未测 / null |
| 2 | pauseload.firstFrame | 3 | 0 | 未测 / null |
| 2 | timeshift.dvr | 3 | 0 | 未测 / null |
| 2 | timeshift.timeshift | 3 | 0 | 未测 / null |
| 2 | pageview.horizontal | 3 | 0 | 未测 / null |
| 2 | pageview.vertical | 3 | 0 | 未测 / null |
| 3 | F3/A17 precise.normal | 60 | 0 | 未测 / null |
| 3 | F3/A17 precise.paused | 60 | 0 | 未测 / null |
| 3 | F3/A17 precise.cutover | 160 | 0 | 未测 / null |
| 3 | H28 default.playing | 30 | 0 | 未测 / null |
| 3 | H28 default.paused | 30 | 0 | 未测 / null |
| 3 | H28 default.cutover | 30 | 0 | 未测 / null |
| 3 | H20.hlsSeek | 30 | 0 | 未测 / null |
| 3 | H50.hlsSeek | 30 | 0 | 未测 / null |
| 3 | H7.lateError | 按现有用例次数 | 0 | 未测 / null |
| 3 | H14.manualSeek | 按现有用例次数 | 0 | 未测 / null |
| 3 | H17.mp4 | 按现有用例次数 | 0 | 未测 / null |
| 3 | H17.m3u8 | 按现有用例次数 | 0 | 未测 / null |
| 3 | H33.direct.404 | 按现有用例次数 | 0 | 未测 / null |
| 3 | H33.direct.refused | 按现有用例次数 | 0 | 未测 / null |
| 3 | H33.direct.dns | 按现有用例次数 | 0 | 未测 / null |
| 3 | H33.recovery.404 | 按现有用例次数 | 0 | 未测 / null |
| 3 | H33.recovery.refused | 按现有用例次数 | 0 | 未测 / null |
| 3 | H33.recovery.dns | 按现有用例次数 | 0 | 未测 / null |
| 3 | H42.wake | 按现有用例次数 | 0 | 未测 / null |
| 3 | A15.miniPip | 按现有用例次数 | 0 | 未测 / null |
| 3 | H37.dispose | 按现有用例次数 | 0 | 未测 / null |
| 4 | Windows F3 | 30 | 0 | 未测 / null |
| 4 | Windows A23/F13 dispose | 20 | 0 | 未测 / null |
| 4 | Windows HE V6 | 5 | 0 | 未测 / null |
| 4 | Windows HE V10 | 20 | 0 | 未测 / null |

阶段2正式六批、阶段3其余Android和阶段4Windows均未启动。Windows按指定顺序依赖阶段1–3完成；未切换窗口焦点执行其他批次。音频焦点保持 manual BLOCKED；全量48批不在范围。

## 验证、构建及证据

- 新增 Dart 文件静态分析通过；矩阵离线检查通过（49批）；现有入口31个单元测试全部通过。
- release 构建：单worker、Gradle Xmx1024m；首轮因PowerShell未引用Kotlin参数拆分而失败，引用修正后构建成功。未终止其他进程。
- 本地APK SHA-256：`88fe7912ca9c9604419bac63ad04635adb5bb91419296da2f869a79aabbe8a18`。路径：`example/build/app/outputs/flutter-apk/app-release.apk`。未安装，设备APK SHA-256 为 null；本地构建不代表设备运行。
- 原始设备检查：`example/tool/coverage_evidence/cp0-formal-device-preflight.json`。
- 夹具清单/哈希及并发速率：`example/tool/coverage_evidence/cp0-autotier-fixture-preflight.json`；HTTP记录：`cp0-autotier-preflight.requests.jsonl`。
- 构建日志：`example/tool/coverage_evidence/cp0-autotier-build-attempt1.log`、`cp0-autotier-build-final.log`。
- 三档原始素材：`example/tool/verify_sources/cp0-autotier-preflight/`（忽略，不提交）；原始检查证据均在gitignored coverage_evidence。
- 数字台账：[2026-11-03-cp0-baseline.json](2026-11-03-cp0-baseline.json)。

## 恢复项

未进入设备写操作：媒体音量、USB常亮、reverse/forward映射均未修改。因设备从未可见，无法读取原值；没有声称已读取或恢复。本地夹具服务已关闭，生成器已退出，release构建已结束。只修改本树mova/example与mova/doc；lib/test未改。
