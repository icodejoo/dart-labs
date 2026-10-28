# Windows 桌面矩阵实跑（2026-10-29）

只记本轮实测事实。未改 lib/、未改 mova-libmpv、未换 dll；验证页只改了 `example/lib/main_videocontroller_verify.dart`（见文末）。

## 环境快照

- 提交：`3aed20d`（工作区另有他人未提交改动，未触碰）
- libmpv：`libmpv/windows-x64/libmpv-2.dll` sha256 `601c7eb2c02aa9f55df7ed90ac2a31a71e861fc198488ca38d2b1bbe2275d67a`（10,997,248 字节，带 VP8 软解），`libmpv_hydrate.py --check` 输出 `[OK] 所有 LFS 文件均为真实内容`；release 目录内 dll 哈希一致
- Flutter 3.47.0（stable，engine 5f77625673）；Windows 10 Pro 10.0.19045；i5-13500 + Intel UHD 770
- 全部 release；HE/keepAlive 每场景 3 次（`--dart-define=RUNS=3`，该值优先于环境变量 `MOVA_RUNS`）
- 噪声：本机同时有其他会话占 CPU（采样期间系统负载约 35%），CPU 数字仅作量级参考
- 证据：`example/tool/coverage_evidence/win-matrix/`（已被 .gitignore）

## 总览

| 项 | 脚本/页面 | 次数 | 通过 | 失败 | 备注 |
|---|---|---|---|---|---|
| HE V1（precise 开/关） | main_host_ergonomics_verify AUTORUN | 3+3 | 6 | 0 | precise=true：`signal=restart`，与 QoE ttff 差 0ms；false：`buffering` 兜底 |
| HE V2 暂停态首帧 | 同上 | 3 | 3 | 0 | 3/3 `restart`，约 2.25s |
| HE V3 换源复位 | 同上 | 3 | 3 | 0 | `rendered=false` 在换源后 11–18ms，每次恰 1 个 `MovaFirstFrame` |
| HE V4 过期 RESTART 竞态 | 同上 | 1 场景 x 20 reps | 1 | 0 | 20 次无过早首帧、无遗漏，min 2205ms |
| HE V5 起播超时 | 同上 | 3 | 3 | 0 | 偏差 47/50/62ms |
| HE V6 卡顿重试续播 | 同上 | 3 | 3 | 0 | 续播误差 posDiff=0ms（旧「从头播」结论不再复现，与 H35 判断一致：验证脚本缺陷） |
| HE V7 切换/放弃 | 同上 | 3 | 3 | 0 | |
| HE V8 坏地址秒判 | 同上 | 3+3 | 6 | 0 | 404 约 40–48ms；拒连 `nativeEndError` 5422–5428ms |
| HE V12 关闭态回归 | 同上 | 3 | 3 | 0 | 无多余事件 |
| HE V10 盖不透明路由+TickerMode | 同上 | 3+3 | 6 | 0 | guard 开，进程不崩 |
| HE V10A / V10B | ONLY 复跑 | 3+3 | 6 | 0 | 路由覆盖 / TickerMode 各自暂停与恢复正常 |
| HE V10C（守卫关，对照） | ONLY 复跑 | 3 | 0 | 3（预期） | 守卫关则不暂停，页面判据写成「应暂停」，所以记 FAIL；进程未崩 |
| keepAlive S1（B 唤醒） | main_keep_alive_verify AUTORUN | 18（gop 25/50/100 x hold 10/30 x 3） | 0 | 18 | 全部 `signal=grace`，elapsed 恒 5000–5010ms（已知待决 H42） |
| S2 allowHls 开/关 | 同上 | 3+3 | 6 | 0 | |
| S3 decodeOnly 唤醒 | 同上 | 3 | 3 | 0 | resume 0ms |
| S4 记录类（normal/B/C/D） | 同上 | 12 | 12（仅记录） | 0 | 无自动判据，需外部 CPU/流量，未做外部采样，不算功耗结论 |
| S5 60s 待机漂移 | 同上 | 3 | 3 | 0 | 终值漂移 −38/43/−86ms；见下「观察」 |
| S5C 对照（无待机） | 同上 | 3 | 3（仅记录） | 0 | |
| S6 无声流强制 B | 同上 | 3 | 0 | 3 | forced B 后 EOF→`MovaDone→PlayFailure` 并重载，位置回 0（已知 H44，旧判据未更新） |
| S13 / S16 / S17 | 同上 | 3 each (S16 4 档) | 全 | 0 | S16：0.5/1s 一律 fallback(mediaUnknown)，2/3s holding |
| 懒创建 VideoController dispose（E6，createMovaEngine 不挂界面） | main_videocontroller_verify（MOVA_EXP=E6） | 3 进程 x 5 轮 | 15 | 0 | dispose 1–6ms |
| E7 先播后挂界面 | 同上 | 3 x 3 | 9 | 0 | 挂载前 0x0、挂载后 640x360、dispose 38–218ms |
| E8 无缝切换回归 | 同上 | 3 | 3 | 0 | renderEpoch 0→1，cutover 849–1330ms，640x360 在播 |
| E5 预览抽帧器 extract | 同上 | 3 x 5 | 15 | 0 | 249–558ms，5 个位置的校验和互异，3 进程之间逐位置完全一致 |
| E12 抽帧 seek 落地轮询 | 同上 | 3 x 7 | 21 | 0 | 落地 32–44ms，校验和随位置变化，3 进程一致 |
| dispose 卡死（audioOnly，无 VideoController） | main_dispose_hang_verify | 3 进程 x 6 轮 | 18 | 0 | dispose 0–1ms |
| dispose 卡死（默认非懒创建内核，无界面） | 同上 | 3 x 6 | 0 | 18（8s 超时） | 与 media_kit 已知行为一致，见分类 |
| VP8 软解（新 dll） | main_vp8_dll_verify | 3 | 3 | 0 | 首帧 799–1317ms，640x360，`hwdec-current=no`，推进 5936ms/6s，MovaErrorEvent 0 |
| H.264 d3d11va 硬解回归 | 同上 | 3 | 3 | 0 | 首帧 388–416ms，`hwdec-current=d3d11va-copy`，推进 5466–5533ms，错误 0 |
| PF10 vod-hw / vod-sw / live（130s） | main_coverage_perf + coverage_perf.py --platform windows | 3 x 3 | 见下 | 0 崩溃 | 无 Windows 基线，判定 BLOCKED(no-baseline) |
| PF7 soak-live（480s） | 同上 | 1 | 见下 | | 无泄漏 |

## PF10 数据（Get-Process，CPU 为单核百分比，t≥25s 的中位数）

| 场景 | CPU 中位（3 次） | RSS 首/末（MiB） | 丢帧 |
|---|---|---|---|
| vod-hw（1080p H.264，d3d11va） | 44.3 / 44.9 / 42.9 | 430→439、441→442、456→451 | 0 |
| vod-sw（软解） | 67.9 / 66.9 / 51.5 | 418→418、422→421、430→428 | 0 |
| live（HLS 1080p） | 39.1 / 42.0 / 56.9 | 448→494、456→505、465→501 | 0 |

- CPU 离散较大（vod-sw 51–68%），因本机同时有别的会话在跑，不做回归结论；没有同机历史基线可对。
- live 的 130s 窗口里 `leak:rss_kb` 判 FAIL（3/3），原因是窗口只有 130s，live 缓存还在填。480s soak-live：RSS 482→498→500→…→502MiB，60s 后基本平台，handles 1284–1290、threads 55–56 不增，判 BLOCKED(no-baseline) 而非泄漏。结论：130s 窗口的 leak 判定是窗口太短的误报，不是产品泄漏。
- 判 BLOCKED 的原因另含 `insufficient-steady-data`（130s、warmup 25s 的稳态样本不足 README 要求的 120s 跨度）。

## 失败/异常分类

| 现象 | 分类 | 证据 | 判断（强度） |
|---|---|---|---|
| S1 18/18 FAIL，`signal=grace`，elapsed≈5000ms | 已知待决（H42，B 唤醒无 RESTART/尺寸变化）；页面判据仍按旧预期 | ka.log VERDICT S1 x18，`decodedProp` 281–3658ms | 已证实，和 CLAUDE.md 记录一致，本轮没有改变 |
| S6 3/3 FAIL，forcedAdvance=−6000ms | 旧预期未更新（H44 已核对：对无声流强制 B 会 EOF+recovery 重载，靠 `audio=absent` 拦截）；页面判据仍是「position 不动」 | ka.log S6 trace：6000→0 | 已证实 |
| V10C 3/3 FAIL | 验证脚本判据语义（对照组，守卫关本来就不会暂停）；非产品问题 | he_V10C.log：pause=false，进程未崩 | 已证实 |
| 默认（非懒创建）内核无界面 dispose 18/18 超时 8s | 已知 media_kit 行为（创建了 VideoController 却不挂界面），不是 mova 引入；产品默认路径（createMovaEngine/MovaEngine 默认内核 lazyVideo）已用 E6/E7/E8 证明正常 | dh_*.log；E6 15/15 | 已证实 |
| 待机 60s 后位置前跳（旧记 2.4–3.0s） | 本轮终值**未复现**（S5 3/3，漂移 −86…43ms，位置 2783→69863/69983） | ka.log S5 | 终值层面已证；**但** trace 里 +61s 一个采样点 3/3 瞬时偏 +1552/+1654/+1686ms，+66s 回到 78–167ms，说明唤醒瞬间位置读数有一次约 1.6s 的瞬时前冲，随后回落。原因未查（推断：唤醒时读数与 seek 回拉的时序，未证实）；是否算已知待决由你判 |
| E5/E12 首次跑全是空图、extract 5.2s、校验和相同 | 环境/验证脚本问题：我用的 `python -m http.server` 不支持 Range，mp4 seek 落不了地；换带 Range 的服务后全部正常（见上表） | 首轮日志已弃 | 已证实（换服务器即好）。注意这条是给后续跑 E5/E7/E8/E12 的人的坑：源必须支持 Range |
| live 130s `leak:rss_kb` | 验证判据窗口过短（误报） | PF7 480s 平台 | 已证实 |

未发现新的产品 bug。

## 未执行/阻塞项

- **HE V9/V11**（后台前台、系统 PiP）：Android 专属，Windows `pipSupported=false`，不跑。
- **keepAlive S7/S8/S8B、S11 音频会话/耗电、S4 电量与流量**：Android 项；Windows 的 S4 只产出了 PHASE 标记，没做外部 CPU/流量采样，所以没有功耗结论。
- **main_win_retest（A23/A12/F3 三模式 x 34）**：2026-10-27 已有 Windows 结果（`2026-10-27-device-coverage-windows-retest.md`），本轮没重跑，状态不变。
- **MovaMini / 转场 / 手势 / 小窗人工项**：需要人工鼠标操作，未执行，不算通过。
- **ABR 等需弱网整形的项**：本轮未做。
- **Windows PF10 同场景对照基线**：仓库无 Windows 基线，我没有 `--record-baseline`（会写入仓库 `perf_baseline/`，不在本轮范围）。
- **iOS/macOS/Linux**：不适用。

## 本轮改动的验证页/脚本

- `example/lib/main_videocontroller_verify.dart`：实验编号支持环境变量 `MOVA_EXP`，`_out` 同时追加到 `MOVA_LOG`，`MOVA_EXIT=1` 时跑完 `exit(0)`，用于 release 桌面落盘。仅验证页，行为在不传环境变量时不变。
- 其余脚本为临时文件（Range 服务器、runexp/rundh/runvp 的 ps1），放在 scratchpad 旁的临时目录，未入仓库。
