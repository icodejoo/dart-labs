# mova：Android 真机交接（HE Task 16 · standby Task 10 · Q13）

> 2026-10-24 · 交接文档 · 读者：**另一台电脑上的另一个 agent，没有本次会话的任何上下文**，拿到就能执行。
> 依据：[HE 计划 Task 16](2026-10-23-host-ergonomics.md)（下称"HE 计划"）、[standby 计划 Task 10 与 Q13](2026-10-23-standby-mode.md)（下称"standby 计划"）、
> 两份计划里新加的「Windows 桌面实测（2026-10-24）」子节（下称"Windows 子节"）、`mova/CLAUDE.md`。

**目标：** 在 Android 真机（STG AL00）上完成所有"只有 Android 能测"和"Windows 没测到"的验证点，把原始数字与判定写回两份计划，并更新 `CLAUDE.md` 的真机确认状态。
**不做：** 不改库代码（`mova/lib/**`）；验证中发现 bug 只记录证据与复现步骤，修复走 mova 的"计划 → 逐 Task 落地"流程（见 §7）。

**Windows 已经做了什么（别重复，但要对着它复核）：** 同一批验证页的脚本化模式已在 Windows 10 release 上跑过（每场景 3 次），HE 的 V1–V8、V10、V12 与 standby 的 S1–S6、S13、S14、S15、S16、S17（部分）都有数字。
**Windows 暴露了 5 个待决问题，Android 上要重点看是否同样出现**（逐条证据见 Windows 子节）：

1. **VOD 卡顿重试后从头播放**，没有续播到失败前位置（HE V6；Windows：失败前 2840ms，重试后进度从 0 线性增长）。
2. **盖一层不透明路由再弹出时进程原生崩溃**（HE V10，Windows `flutter_windows.dll` `0xC0000005`，6/6，与守卫无关，`TickerMode` 路径不崩）。
3. **B（`vid=no`+`mute`）唤醒恒走 `grace`**（standby S1/S15：18/18，不发 `PLAYBACK_RESTART` 也没有尺寸变化，`MovaStandbyResume.elapsed` 恒等于 `resumeTimeout`；真正出画面 0.45–3.7s，≤ 一个 GOP）。
4. **待机 60s 后位置在唤醒后向前跳约 2.4–3.0s**（S5；待机期间与无待机对照都无漂移）。
5. **对无声流强制 B 会 EOF + recovery 重载**（S6，比计划预期的"position 停止"更重）。

---

## 1. 前置（必须按顺序做完）

### 1.1 仓库：dart-labs 的 main 已在 2026-10-24 改写过历史

dart-labs 的 `main` 在 **2026-10-24 改写过历史**（去掉了一次把 filter-repo 之前的旧历史合并回来的坏合并）。**另一台电脑上的旧克隆必须重新 clone，
或者 `git fetch` 之后 `git reset --hard origin/main`；绝对不能从旧克隆直接 push**（会把坏合并带回远端）。不要 `git pull` / `git merge` 旧 main。

```bash
# 方案 A（推荐）：重新 clone（origin 的 fetch 地址是 codeup）
git clone let188@let188-ap-southeast-1.devops.alibabacloudcs.com:codeup/dart-labs.git dart-labs
cd dart-labs

# 方案 B：沿用旧克隆（先确认没有要保留的本地改动，有就先拷出去备份）
git fetch origin
git status
git reset --hard origin/main
```

然后（两种方案都要）：

```bash
sh ./setup-remotes.sh      # origin 从 codeup 拉；push 同时推 codeup 和 GitHub（icodejoo/dart-labs）
git lfs install
git lfs pull               # 拉下 mova/libmpv/** 与 mova/packages/** 的二进制（.so/.dll/.dylib/.a）
```

自检：`git lfs ls-files | head` 能列出 `mova/libmpv/arm64-v8a/libmpv.so` 等；`ls -l mova/libmpv/arm64-v8a/libmpv.so` 应约 6 MB（6,050,104 字节），
**如果只有一百来字节说明还是 LFS 指针，没拉成功**，不要继续构建。

### 1.2 要同步到哪个 commit

同步到 **"任务 A/B/C 提交之后的 main"**，即包含下面三个提交（从新到旧）的 `origin/main`：

```
docs(mova): Android real-device handoff for HE T16, standby T10 and Q13       <- 本文档所在提交（任务 C）
docs(mova): Windows desktop results for host-ergonomics T16 and standby T10   <- 两份计划的 Windows 子节 + CLAUDE.md 标注（任务 B）
test(mova): scripted AUTORUN mode for host-ergonomics and standby verify pages <- 验证页脚本化模式 + Q13 验收页 + 本地源脚本（任务 A）
```

`git log --oneline -4` 里能按这个顺序看到这三个标题才算对。**这三个提交写文档时在 Windows 机器的本地 main 上，是否已推到远端以主会话为准**；
拉下来看不到就停下来问人，不要自己去别处找、更不要自己重做。

### 1.3 工具链与基线自检

- Flutter **3.47.0**（stable，4cf2416426）、Dart `^3.12.2`、JDK 21、Android SDK（`adb` 在 PATH 里）。
- 电脑上要有 **Python 3** 与 **ffmpeg**（本机源用，Windows 上验证过 8.0.1，要 `libx264`/`aac`/`testsrc2`/`sine`）。
- 基线（改动前必须先自检，数字对不上先停下来）：

```bash
cd mova
flutter pub get
flutter analyze lib test        # 期望：No issues found
flutter test                    # 期望末行：+1302: All tests passed!
cd example
flutter pub get
flutter test test/auto_kit_test.dart                                   # 期望：+12: All tests passed!
flutter analyze lib/main_host_ergonomics_verify.dart lib/main_standby_verify.dart \
  lib/main_q13_mute_verify.dart lib/verify_auto test                   # 期望：No issues found
```

（`example` 整体 `flutter analyze` 有 22 条既有 info/warning，都在老的 probe 文件里，与本次无关。）

---

## 2. 设备与运行方式

**设备：** STG AL00，adb 序列号 `7NQBB23606003715`，Android 12。包名 `com.icodejoo.mova.mova_example`，Activity `.MainActivity`。

```bash
export S=7NQBB23606003715 PKG=com.icodejoo.mova.mova_example
export OUT=/storage/emulated/0/Android/data/$PKG/files     # 应用私有外部目录，写日志用，不需要权限
adb devices                                                # 应看到 $S  device
adb -s $S shell dumpsys window | grep isKeyguardShowing    # 必须是 isKeyguardShowing=false
adb -s $S shell svc power stayon usb                       # 插着 USB 时保持亮屏
```

**前置检查（CLAUDE.md 的硬规则）：手机必须亮屏且已解锁**，锁屏/熄屏时一切涉及渲染面的结果作废。手机网络曾多次断（域名解析失败，状态栏 Wi-Fi 带感叹号），
遇到图片/接口超时先 `adb -s $S shell ping -c 2 8.8.8.8` 查，别先怀疑代码。`adb shell input` 偶尔报 `INJECT_EVENTS` 被拒（锁屏或有系统弹窗），截图不受影响。

### 2.1 三个验证页

| 验证页 | 用途 | 日志前缀 | 模式 |
|---|---|---|---|
| `lib/main_host_ergonomics_verify.dart` | HE Task 16 | `[MOVA-HE]` | `--dart-define=AUTORUN=true` 脚本化；不传则是原手动页 |
| `lib/main_standby_verify.dart` | standby Task 10 | `[STANDBY]` | 同上 |
| `lib/main_q13_mute_verify.dart` | Q13（预热静音） | `[Q13]` | 只有自动模式（每个功能一个单独验收页） |

脚本化模式的公共参数（都是 `--dart-define`，Android 上没有环境变量，只能用这些）：

| 参数 | 含义 | 默认 |
|---|---|---|
| `AUTORUN=true` | 进入脚本化模式 | 关 |
| `RUNS=5` | 每个场景重复次数（计划要求每项至少 5 次） | 3 |
| `ONLY=V5,V7` | 只跑点名的场景（还能点名 opt-in 场景，见下） | 空 = 默认序列 |
| `BASE=http://127.0.0.1:18080` | 本地源服务器基地址 | `http://127.0.0.1:18080` |
| `LOG_FILE=<路径>` | 日志同时追加写入的文件 | 空（只走 logcat） |
| `AUTOEXIT=false` | 跑完不退出进程（默认跑完 `exit(0)`） | true |
| `WAIT_S=<秒>` | 靠标记驱动的场景（V9/V11/S8/S8B）等你动手的上限 | HE 90 / standby 600 |

其余专用参数：HE 有 `GOP`（默认 50）、`V4_REPS`（默认 20）、`START_TIMEOUT_S`（4）、`STALL_TIMEOUT_S`（4）、`REFUSED_URL`（默认 `http://127.0.0.1:9/x.flv`，手机上没人监听即拒连）；
standby 有 `HLS_URL`（默认 `http://127.0.0.1:18081/live.m3u8`）、`GOPS`（`25,50,100`）、`HOLDS`（`10,30`）、`S3_SECONDS`/`S4_SECONDS`/`S5_SECONDS`、`S16_DELAYS`、`S7_CYCLES`（20）。

**默认序列**：HE = V1、V2、V3、V4、V5、V6、V7、V8、V12、V10（V10 放最后，Windows 上它会崩进程）；standby = S16、S1、S2、S3、S6、S13、S17、S5、S4。
**opt-in（必须 `ONLY=` 点名才跑）**：HE 的 `V9`、`V11`、`V10A`/`V10B`/`V10C`；standby 的 `S5C`（S5 的无待机对照）、`S7`、`S8`、`S8B`、`S14`。

### 2.2 构建、安装、运行、取日志

```bash
cd mova/example
adb -s $S reverse tcp:18080 tcp:18080      # 电脑上的源服务器端口映射给手机（见 §3）
adb -s $S reverse tcp:18081 tcp:18081
adb -s $S logcat -c                         # 清旧日志

# HE 脚本化，release（--no-resident：构建、安装、启动后命令即退出，应用在手机上自己跑完）
flutter run -d $S --release --no-resident -t lib/main_host_ergonomics_verify.dart \
  --dart-define=AUTORUN=true --dart-define=RUNS=5 \
  --dart-define=BASE=http://127.0.0.1:18080 --dart-define=LOG_FILE=$OUT/he.log

# 等跑完（日志里出现 AUTORUN DONE），再取：
adb -s $S logcat -d -s flutter | grep "MOVA-HE" > he_android_release.log       # 方式一：logcat（Dart print 在 release 下也走 flutter 标签）
adb -s $S pull $OUT/he.log ./he_android_release.file.log                          # 方式二：拉应用写的文件（App 会自己建目录；Android 12 上 adb shell 通常可读，读不到就只用方式一）
```

- 想**边跑边看**：另开终端 `adb -s $S logcat -s flutter | grep --line-buffered -E "MOVA-HE|STANDBY|Q13"`。
- 想**阻塞到跑完**：`adb -s $S logcat -s flutter | grep -m1 "AUTORUN DONE"`。
- standby 页：把 `-t lib/main_standby_verify.dart`、`LOG_FILE=$OUT/standby.log`、过滤前缀 `STANDBY` 换进去，其余同上；Q13 页：`-t lib/main_q13_mute_verify.dart`（不需要 `AUTORUN`）、`LOG_FILE=$OUT/q13.log`、前缀 `Q13`。
- **debug 与 release 各跑一遍**（HE/standby 计划的前置要求：debug 下原生事件走 100ms 轮询，RESTART 精度不同）：debug 把 `--release` 换成 `--debug`，日志文件名换一个（`he_debug.log`）。**debug 的数字只用来看行为差异，不用来下性能结论。**
- 每个功能的验收页是独立的，不要把别的 spike 混进来；一次只让一个验证页在手机上跑。

---

## 3. 源：手机能访问的直播/点播源

### 3.1 推荐：电脑起服务，手机走 `adb reverse`（不需要放防火墙）

`mova/example/tool/verify_sources/` 里是 Windows 上用过的同一套脚本：

```bash
cd mova/example/tool/verify_sources
python start_sources.py --workdir /tmp/mova-verify --live-port 18080 --hls-port 18081      # Windows 把 /tmp/... 换成一个临时目录
```

它起三个进程（Ctrl-C 一起关）：`live_server.py`（多客户端 FLV 直播/挂住/卡顿/点播/广告）、一个 HLS 滑窗 `ffmpeg`、`python -m http.server`。服务器端点：

| 端点 | 含义 |
|---|---|
| `/live.flv?gop=50&audio=1&freq=440` | 每个连接起一个 `ffmpeg -re` 实时推 `testsrc2`(+`sine`)，FLV 直播；`gop` 是帧数（25fps，50 即 2s），`audio=0` 是无声流，`freq` 是音调 |
| `/hang` | 接受连接、读完请求头后不回任何数据（V5 起播超时） |
| `/stall.mp4?t=KEY` | 同一 KEY 的所有连接只发前 10% 字节就挂住，直到 `/release?t=KEY`（V6 卡顿；页面在收到 `PlayFailure` 事件时自己放行） |
| `/vod.mp4`、`/ad.mp4` | 40s / 20s 点播素材（`ad.mp4` 音调 880Hz，Q13 页当广告用，耳朵听"高音 = 广告、低音 = 正片"） |
| `http://127.0.0.1:18081/live.m3u8` | HLS 滑窗：`-g 50`、`-hls_time 2 -hls_list_size 6 -hls_flags delete_segments` |

`ffmpeg` 生成直播的命令（脚本里用的，直接沿用）：

```bash
ffmpeg -re -f lavfi -i testsrc2=size=640x360:rate=25 -f lavfi -i sine=frequency=440:sample_rate=44100 \
  -c:v libx264 -preset ultrafast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -pix_fmt yuv420p -b:v 600k \
  -c:a aac -b:a 64k -f flv -flvflags no_duration_filesize pipe:1           # 无声流去掉 -f lavfi sine 输入，并用 -an
ffmpeg -re ... -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+omit_endlist -hls_segment_filename seg%05d.ts live.m3u8
```

**GOP 要固定并写进结果**：恢复耗时取决于 GOP（Windows 用 25/50/100 帧即 1s/2s/4s）。电脑上先自检：

```bash
curl -s -m 4 "http://127.0.0.1:18080/live.flv?gop=50&audio=1" -o /tmp/p.flv && ffprobe -v error -show_entries stream=codec_name -of csv=p=0 /tmp/p.flv     # h264 + aac
curl -s http://127.0.0.1:18081/live.m3u8 | head -5                                                                                                          # #EXTM3U ...
adb -s $S shell "echo ok"                                                                                                                                    # 然后：adb -s $S reverse tcp:18080 tcp:18080 && adb -s $S reverse tcp:18081 tcp:18081
```

### 3.2 备选：手机走局域网直连（`adb reverse` 不好使时）

1. 服务器改成监听全部网卡：`python start_sources.py --bind 0.0.0.0 ...`。
2. **防火墙放行端口**（Windows，管理员 PowerShell）：`New-NetFirewallRule -DisplayName mova-verify -Direction Inbound -Protocol TCP -LocalPort 18080,18081 -Action Allow`，**验完删掉**：`Remove-NetFirewallRule -DisplayName mova-verify`。macOS/Linux 按各自防火墙放行同样两个 TCP 端口。
3. 手机与电脑在同一 Wi-Fi，`adb -s $S shell ping -c 2 <电脑IP>` 能通；跑页面时 `--dart-define=BASE=http://<电脑IP>:18080 --dart-define=HLS_URL=http://<电脑IP>:18081/live.m3u8 --dart-define=REFUSED_URL=http://<电脑IP>:9/x.flv`。

### 3.3 真实业务直播流（可选，部分验证点需要）

bingo 的 pinoy 直播卡片走 `_front_api_/channel/getVideoCardInfo`，**需要 Android 原生签名，只能在真机上的 bingo 里拿到**，电脑上用 curl 直接请求会被拒。取流地址的办法（**我没有核实 bingo 是否把响应或拉流地址打到日志里**）：

- 在真机上跑 bingo（装机命令必须带 UAT 环境，否则 `API_BASE_URL` 落到 `localhost:3000` 超时：`flutter run -d $S --no-resident --dart-define-from-file=envs/.env --dart-define-from-file=envs/.env.uat`，在 bingo 仓库里执行），进 Pinoy 页，
  `adb -s $S logcat -d -s flutter | grep -i -E "getVideoCardInfo|\.flv|\.m3u8"` 看有没有流地址。**拿不到就写"需要人工提供"，不要自己猜签名。**
- 拿到地址后可以直接喂给**手动页**：HE 手动页 `--dart-define=PRIMARY=<url> --dart-define=LIVE=true`（`ALT=` 放备选），standby 手动页 `--dart-define=FLV_AUDIO=<url>`（或 `FLV_SILENT`/`HLS`）。注意手动页每次打开都会自动追加 `?t=`，带签名的地址可能因此失效，遇到就在结果里写明"该地址不能追加参数"。
- 以下验证点**必须**有真实业务流/业务路由，本机源替代不了，拿不到就在结果里记"需要人工提供"：HE V5 的"实际离线桌台地址"、HE V10 的 `StatefulShellRoute.indexedStack` 与 `routeObservers`（需要 go_router 的真实路由结构，example 里没有）、standby S17 的 `StatefulShellRoute`。

---

## 4. 测量约定（来自 `mova/CLAUDE.md`「约定」，违反了数字作废）

- **用事件打点，不用墙钟估算**：耗时只取真实事件（`MovaFirstFrame.sinceOpen`、`MovaStandbyResume.elapsed`、事件到达的单调时间、内核属性读取）。日志里行首的墙钟时间只用来和外部采样器对齐。
- **不 seek 到临近素材 EOF**（会卡死播放器，已反复误判过）。
- **每次打开加防缓存参数**（页面已自动追加 `?t=<微秒>`）。
- **多次取平均**：每项至少 5 次，报 min/max/avg（S1/S7 各 20 次量级）。
- **每个功能一个单独的验收页**，不与其他 spike 混用。
- 手机必须亮屏已解锁；debug/release 各一遍；先确认再下结论。

---

## 5. 任务清单（逐项可勾选）

每项：做什么 / 怎么测 / 判据（引用计划原文并注明出处小节）/ Windows 已有结论（链接到 Windows 子节）。
记录规则：每次的值 + 平均值写进结果（§6），判定三选一：通过 / 不通过 / 与预期不同；关键日志摘录要带上。

### 5.0 开工前

- [ ] **P-1 仓库同步**：§1.1 全部做完，`git log --oneline -4` 看到 §1.2 的三个标题。
- [ ] **P-2 基线自检**：§1.3 的数字全对。
- [ ] **P-3 设备就绪**：`adb devices` 有 `$S`、`isKeyguardShowing=false`、网络通；`adb reverse` 两个端口已映射；§3.1 的自检命令都过。

### 5.1 HE Task 16 里**只有 Android 能测**的项

- [ ] **HE-V9 前后台续播**
  - 做什么：播放中进后台 5s 再回前台，验证守卫暂停、回前台自动续播，且"回前台需手动续播"（CLAUDE.md 旧记录）不再复现。
  - 怎么测：`ONLY=V9`，页面打印 `V9 WAIT_HOME` 时按 HOME、5s 后拉回前台。可以用脚本代劳（电脑上另开终端先运行，再启动应用）：
    ```bash
    adb -s $S logcat -s flutter | grep --line-buffered "V9 WAIT_HOME" | while read _; do
      adb -s $S shell input keyevent KEYCODE_HOME; sleep 5; adb -s $S shell am start -n $PKG/.MainActivity
    done
    ```
    再跑 `ONLY=V9 --dart-define=WAIT_S=120`；至少 5 次（`RUNS=5`）。
  - 判据（HE 计划 Task 16 表 V9）："收到守卫触发的 `MovaPause` 与回前台后的 `MovaPlay`；直播源额外有 `MovaLiveEdgeReach`；**CLAUDE.md 记的'回前台需手动续播'不再复现**"。页面日志里 `V9 lifecycle=[...]`（要看 Android 真实的 `inactive→hidden` 序列）、`play=true`、`liveEdgeReach=true`、`positionAdvanceOver3s` > 2000ms 且全程没人点播放。
  - Windows 已有：[HE 计划 Windows 子节「附：V9 的 Windows 类比」](2026-10-23-host-ergonomics.md)——最小化/还原：`hidden`（直接 `hidden`，无 `inactive→hidden`）→ `MovaPause` 313–320ms，还原后 `MovaPlay` + `MovaLiveEdgeReach`，位置 3s 推进 3040ms。**这不算 V9 完成。**
- [ ] **HE-V11 系统 PiP 不受守卫影响**
  - 做什么：播放中 `enterPip()`，不应出现守卫的 `MovaPause`。
  - 怎么测：`ONLY=V11`；页面进入 PiP 后打印 `V11 WAIT_RESTORE`，把应用从小窗拉回全屏继续（`adb -s $S shell am start -n $PKG/.MainActivity`）。`pipSupported=false` 的机器会直接记 n/a（Windows 就是这样）。
  - 判据（V11）："无 `MovaPause`（`inactive` 不暂停 + `pip` 豁免）"；日志 `V11 enterPip=true ... pauseEvents=0`。
  - Windows 已有：n/a（`pipSupported=false`）。
- [ ] **HE-V10 盖住/Tab 遮挡在 Android 上是否同样崩溃** ← **优先做**
  - 做什么：Windows 上"push 一个不透明路由后 pop"会让进程原生崩溃，先确认 Android 是否同样。
  - 怎么测：依次 `ONLY=V10B`（`TickerMode` 切走切回）、`ONLY=V10A`（路由盖住，守卫开）、`ONLY=V10C`（路由盖住，守卫关）；每个 3 次。日志里每个动作前都有一行（`... action: pop covering route`），进程若在那之后没有任何输出，说明崩了：`adb -s $S logcat -d | grep -i -E "fatal|signal|tombstone|backtrace"` 取崩溃栈，`adb -s $S shell ls /data/tombstones`（需要 root 时只记命令）。
  - 判据（V10 表）："切走即 `MovaPause`、切回即 `MovaPlay`"；路由盖住"根 navigator push 也能暂停"。**不崩**才算通过。
  - Windows 已有：[HE Windows 子节·V10 与发现 2](2026-10-23-host-ergonomics.md)——`V10B` 3/3 通过（pause 5–12ms、play 10–11ms）；`V10A`/`V10C`/`V10` 在 pop 时 `0xC0000005`，6/6。
- [ ] **HE-V1/V2/V3/V4/V5/V6/V7/V8/V12 的 Android 复测**（计划表里这些项的方法本来就写的是 `adb`/真机，Windows 只测了一遍同口径）
  - 怎么测：`AUTORUN=true`（不带 `ONLY`）`RUNS=5`，release 与 debug 各一遍；V4 默认 20 次已满足。
  - 判据：HE 计划 Task 16 表 V1–V8、V12 原文。重点对照 Windows 的差异：
    - **V1**：`precise=true` 时 `signal` 全为 `restart` 且与 QoE `ttffMs` 差 < 50ms；`false` 时 Windows 的 `buffering` 比 `restart` 早 ~0.5s，Android 看是不是 ~0.2s（CLAUDE.md 的 612 vs 809ms）。
    - **V2**：Windows 暂停态打开会收到 `restart`；Android 若是 `size`/`grace`，要在结果里注明，并说明 Task 6 的 feed opt-in 在 Android 上的精度来源。
    - **V6**：Windows 失败后**从头播放**（判据要求续播位置差 < 500ms）——Android 是否同样？日志 `V6 ... samplesAfterRetryFirstFrame=[...]` 看进度是否跳到失败前位置（`posBefore`）。
    - **V8**：Windows 拒连 ~5.07s 才有 `nativeEndError`、404 ~40ms、`open()` 不抛；Android 的真实时机是 CLAUDE.md 列的"需真机确认"项。
    - **V12**：默认参数下事件序列与 Windows 相同（只多 `MovaFirstFrame`）；"弱客户端创建数为 0"本页没有计数后端，需要时跑 `example/lib/main_observe_event_verify2.dart` 的 V9 组（Android 上有先例）。
  - Windows 已有：[HE Windows 子节·原始数据表](2026-10-23-host-ergonomics.md)。
- [ ] **HE-V3 抓帧（封面/黑帧/残帧）**
  - 做什么：换源时 B 出画面前不出现黑帧/A 的残帧（只做量级证据）。
  - 怎么测：`ONLY=V3`，同时 `adb -s $S exec-out screencap -p > v3_$(date +%s%N).png` 连续抓帧（约 250–330ms 一帧）与日志事件时间戳对齐。
  - 判据（V3）："每次换源都有新的 `MovaFirstFrame`；抓帧中 B 出画面前不出现黑帧/A 的残帧露出"。
  - Windows 已有：事件部分通过（`rendered=false` 距换源 6–17ms，每次恰 1 个新 `MovaFirstFrame`）；抓帧部分 Windows 没做。
- [ ] **HE-V5 实际离线桌台地址**（需要真实业务流，见 §3.3）：用手动页 `PRIMARY=<离线地址>` 跑，判据同 V5（`startTimeout` 失败距 `open()` 与配置差 < 300ms、恰一次 `MovaGiveUpError`）。拿不到地址就记"需要人工提供"。
- [ ] **HE-V10R `routeObservers` 与 `StatefulShellRoute`**（需要 go_router 的真实路由结构，example 没有）：在 bingo 里验证，或先出计划新建单独验收页。判据（V10）："注册 `routeObserver` 后根 navigator push 也能暂停"。拿不到条件就记"需要人工提供/需要业务路由"。

### 5.2 standby Task 10：Android 专属项与未测项

- [ ] **SB-S1/S15 B 的恢复耗时与信号分布** ← 重点
  - 做什么：B（`vid=no`+`mute`）唤醒耗时，按 GOP 与待机时长扫描；统计 `MovaStandbyResume.signal` 分布。
  - 怎么测：默认序列里的 `S1`（`ONLY=S1`），`GOPS=25,50,100`、`HOLDS=10,30`、`RUNS=5`（每个单元 5 次），release 与 debug 各一遍。日志行 `S1 gop=... resume=...ms signal=... decodedProp=...ms`；`decodedProp` 是页面用 mpv 属性 `video-out-params/w` 轮询（30ms 粒度）读到的"解码器真的吐出新帧"耗时，**独立于引擎的落地信号**，每次都有"待机期间该属性为空"的自检行。
  - 判据（standby 计划 Task 10 表 S1）："中位数随 GOP 变化、≈ 解码器初始化 + ½GOP；`signal` 以 `size` 为主。**据此校准 `resumeTimeout`**（取 4s GOP 的 max + 1s）"。S15（"切回 `vid=auto` 是否发 RESTART"）："记事实；若 RESTART 稳定先到，可把它作为首选信号"。
  - Windows 已有：[standby Windows 子节·S1/S15](2026-10-23-standby-mode.md)——18/18 `grace`，`elapsed` 恒为 5000–5003ms（超时值），`decodedProp` 0.45–3.7s（≤ 一个 GOP）。**Android 若 `signal` 变成 `size`/`restart`，`elapsed` 才是真测量值。**
- [ ] **SB-S2 HLS 能否放开 + 默认值校准 `allowHls`**
  - 做什么：`allowHls:true` 跑 HLS 直播，记 `file-format` 实际取值、恢复耗时、有无回读分片。
  - 怎么测：`ONLY=S2`，`HLS_URL` 指向 §3 的 HLS；电脑上 `hls_http.log`（`start_sources.py --workdir` 里）看待机窗口内的分片请求（按秒分辨率）。页面无法打开 mpv 的 `--msg-level=demux=v`，**看不到 `refresh seek` 日志，这点在结果里如实写"未能验证"**。
  - 判据（S2）："无回读或回读不卡、恢复耗时不劣于 FLV → `allowHls` 默认可改 true；`file-format` 取值核对 `movaSegmentedFormats`"。
  - Windows 已有：`file-format=hls`；`allowHls=true` 持有成立；无回读迹象（弱证据）；唤醒仍 `grace`、属性轮询出帧 0.9–1.0s。**D13 默认值表里 `allowHls` 的"待真机校准"仍未决。**
- [ ] **SB-S3 C（无声流 keepDecoding）恢复与开销**
  - 怎么测：`ONLY=S3`；CPU 另开终端：`adb -s $S shell top -b -n 1 -p $(adb -s $S shell pidof $PKG)` 每 5s 采样，对齐页面日志的 `PHASE S3.hold begin/end`。
  - 判据（S3）："`MovaStandbyResume.signal == null`、elapsed < 50ms；CPU 与正常播放同量级（确认'不省电'的说法）"。
  - Windows 已有：通过（`signal=null`，`elapsed` 0ms ×3，CPU 12.1% 与正常播放同量级）。
- [ ] **SB-S4 功耗/流量/CPU（A/B/C/D）+ `maxDuration` 校准**
  - 做什么：同一直播流各跑一段（页面每个模式窗口默认 30s，`S4_SECONDS=300` 对应计划的 5 分钟）。模式：`normal` 正常播放、`B`、`C`（无声流 keepDecoding）、`D`=普通 `pause()`。
  - 怎么测：`ONLY=S4`，窗口边界看日志 `PHASE S4.<模式>.run<N> begin/end`。窗口开始前后分别：`adb -s $S shell dumpsys batterystats --reset`（窗口开始时）→ 窗口结束后 `adb -s $S shell dumpsys batterystats $PKG`；流量 `adb -s $S shell dumpsys netstats detail`（按 UID）；CPU `top` 每 5s；内存 `adb -s $S shell dumpsys meminfo $PKG`。电脑上 `live_server` 日志（`BYTES` 行）也有按连接的字节数。
  - 判据（S4）："B/C 流量≈满速、A 缓冲满后≈0；量化 B 相对正常播放省多少 CPU/电。**据此校准 `maxDuration`**"。
  - Windows 已有：B 省 ~81% CPU（13.2% → 2.5%），C 几乎不省（10.7%），**网络都不省**，且直播 FLV `pause()` 也满速拉流（≈82KB/s）。**电量 Windows 测不了。**
- [ ] **SB-S5 边缘保持**
  - 怎么测：`ONLY=S5,S5C`（`S5C` 是无待机对照），`S5_SECONDS=60`；日志里 `S5 ... drift=...ms` 与位置轨迹 `trace=[...]`。
  - 判据（S5）："`|Δposition − Δ待机时长| < 1s`……与待机时长无关"。
  - Windows 已有：**不通过**：漂移 2376–2960ms（avg 2548.9），方向是位置**向前跳**，集中在唤醒后那几秒；对照组 −18…−31ms。Android 看方向与量级是否相同。
- [ ] **SB-S6 无声流判定与误判保护**
  - 怎么测：`ONLY=S6`；`inspectStandby().audio` 应为 `absent`；页面直接调内核强制 B（绕过引擎决策）观察 `position`。
  - 判据（S6）："判定为 `absent`；强制 B 时 `position` 停止推进（印证 §1.3 推断，说明 D4 的必要性）"。
  - Windows 已有：`absent` 3/3 通过；强制 B 的结果是 **mpv 直接 EOF + `MovaDone` + recovery 重载**（比预期重）。
- [ ] **SB-S7 `mediacodec-copy` 下 `vid` 切回能否出画**
  - 做什么：20 次 `vid` 关/开，确认 20/20 出画、`logcat` 无 `Could not open codec`。
  - 怎么测：`ONLY=S7`（`S7_CYCLES=20` 默认）；每个循环打印 `S7 SHOT <i>`，在出画后抓一帧：
    ```bash
    adb -s $S logcat -s flutter | grep --line-buffered "S7 SHOT" | awk '{for(i=1;i<=NF;i++) if($i=="SHOT"){print $(i+1); fflush()}}' | while read i; do adb -s $S exec-out screencap -p > s7_${i}.png; done
    adb -s $S logcat -d | grep -i "could not open codec"      # 应为空
    ```
    日志首行 `S7 hwdec=...` 必须是 `mediacodec-copy`（不是就在结果里写明实际取值）。
  - 判据（S7）："20/20 有 `MovaStandbyResume(signal: size)` 且截图有画面；logcat 无 `Could not open codec`"。
  - Windows 已有：[standby Windows 子节「附」](2026-10-23-standby-mode.md)——`d3d11va-copy` 下 20/20 视频真回来（属性），`signal` 落地 0/20；**只是旁证，不算 S7 完成**。
- [ ] **SB-S8 Android 进后台（守卫与命令式）**
  - 做什么：守卫 standby 模式下进后台 5s/60s/5min 再回前台；另测命令式 holding 时进后台。
  - 怎么测：`ONLY=S8`（守卫）与 `ONLY=S8B`（命令式），各跑 3 档时长（`WAIT_S` 要大于最长一档，默认 600）。驱动同 V9，只是 `sleep` 换成 5 / 60 / 300，标记是 `S8 WAIT_HOME`/`S8B WAIT_HOME`：
    ```bash
    adb -s $S logcat -s flutter | grep --line-buffered "WAIT_HOME" | while read _; do
      adb -s $S shell input keyevent KEYCODE_HOME; sleep 60; adb -s $S shell am start -n $PKG/.MainActivity
    done
    ```
  - 判据（S8）："守卫：后台前有 `MovaPause`、回来走 `reloadEdge`；命令式：记录 `widListener` 无条件 seek 后 `vid`/`mute`/`position` 的实际状态（不要求通过，记事实）"。日志 `S8 lifecycle=[...] events=[...]`、`S8B +0s/+3s after return: standby=... vid=... mute=... time-pos=...`。
  - Windows 已有：最小化/还原类比（away 5s）：S8 事件 `MovaPause → MovaLiveEdgeReach → MovaPlay`、位置 +3040ms/3s；S8B 回来后 `holding`/`vid=no`/`mute=yes` 保持。**不算 S8 完成。**
- [ ] **SB-S11 `mute` 时的音频会话/耗电**
  - 怎么测：在 S4 的 `B` 窗口里（`ONLY=S4`）执行 `adb -s $S shell dumpsys audio`（看 AudioTrack 是否仍在、`mute`、各流音量）与 `batterystats` 音频项。
  - 判据（S11）："记录底噪，评估 B 的音频侧成本"。
  - Windows 已有：无（Android 专属）。
- [ ] **SB-S13 B 期间 `switchQuality`/`backToLiveEdge`**
  - 怎么测：`backToLiveEdge` 部分 `ONLY=S13`；`switchQuality` 需要多码率 HLS：用 `main.dart` 里"HLS · 多清晰度"那条真实流 `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`（要求手机能上外网，`ping` 先查），在 B 里调 `switchQuality`——页面目前没有这个场景，**需要先出计划再加**（本项记"未测"也可以，但要写明）。
  - 判据（S13）："重载后仍无声、无画（截图），`state.standby` 仍 holding；唤醒正常"。
  - Windows 已有：`backToLiveEdge` 3/3 通过（`vid/mute` 为 `no/yes`、阶段 `holding`，唤醒 `signal=size` 1954–1986ms）；`switchQuality` 未测。
- [ ] **SB-S14 B 期间画面显示什么（Android 一次）**
  - 怎么测：`ONLY=S14`，页面在 `S14 SHOT normal/holding1/holding2/restored` 处等 2.5s，外部抓屏：
    ```bash
    adb -s $S logcat -s flutter | grep --line-buffered "S14 SHOT" | awk '{for(i=1;i<=NF;i++) if($i=="SHOT"){print $(i+1); fflush()}}' | while read label; do adb -s $S exec-out screencap -p > s14_${label}.png; done
    ```
    画面里烧入了 `testsrc2` 的时间码，两张 holding 截图时间码相同即"冻结最后一帧"，黑屏则是黑。
  - 判据（S14）："记录'黑 / 最后一帧'，决定封面覆盖默认是否保留"。
  - Windows 已有：**冻结最后一帧**（两张间隔 2.5s 的截图像素一致，时间码都是 `00:00:05.440`）。
- [ ] **SB-S16 `audio-params` 就绪时机**：`ONLY=S16`，判据（S16）："记录 `fallback(mediaUnknown)` 的比例与 `audio-params` 就绪的典型耗时"。Windows：0.5s/1.0s 内一律 `fallback(mediaUnknown)`，2.0s/3.0s 起 `holding`，就绪约 2.1s（该源首帧约 2s）。
- [ ] **SB-S17 守卫端到端（Android 专属部分）**
  - 做什么：`TickerMode` 与隐藏期间换源 Windows 已通过，剩下 push 半透明路由（带 `routeObservers`）、`StatefulShellRoute`、"全程无声音泄漏（人耳 + `dumpsys audio`）"。
  - 怎么测：`ONLY=S17`（先在 Android 复测 `TickerMode` 那两支）；push 路由受 HE-V10 的崩溃问题影响，先看 HE-V10 的结果；耳朵听 + `adb -s $S shell dumpsys audio` 看隐藏期间是否有 AudioTrack 在响。
  - 判据（S17）："切走即 `(holding, requested)`、切回即 `MovaStandbyResume`；隐藏期间换源后再次进入待机（Q9），全程无声音泄漏"。
  - Windows 已有：`TickerMode` 与隐藏期间换源 3/3 通过（`Standby(fallback,reloaded) → ... → Standby(holding,requested)`），切回后 `grace`。
- [ ] **SB-D 默认值校准**：把 §5.2 的数字填进 standby 计划 D13 表的"校准依据"，给出对 `maxDuration`（S4）、`resumeTimeout`（S1）、`allowHls`（S2/S5）的建议值与理由；**不改代码**，改默认值走"计划 → Task"流程。

### 5.3 Q13 真机确认（standby 计划 Q13）

Q13 的修复（commit `9442480`）：swap 预热的静音改走内核的 `mute` 能力 `MovaPlayerMute`，不再走音量端口，所以**预热时旧那一路声音和系统媒体音量都不能变**。

- [ ] **Q13-A 预热/提交的声音与系统音量**
  - 做什么：广告播放期间正片在影子引擎里预热（应只有影子被静音）；提交后新那一路正常出声；全程系统媒体音量不变。
  - 怎么测：`lib/main_q13_mute_verify.dart`，`ONLY=Q13A`，`RUNS=3`。**耳朵**：广告是 880Hz 高音、正片是 440Hz 低音，预热期间只能听到高音，提交后变成低音，中间无断音/漏音。**系统音量**：页面每一步打印 `[Q13] MARK <名>`，在 MARK 行采样：
    ```bash
    adb -s $S logcat -s flutter | grep --line-buffered "Q13\] .*MARK" | while read line; do
      echo "== $line" >> q13_volume.txt
      adb -s $S shell dumpsys audio | grep -A8 "STREAM_MUSIC" | grep -i -E "streamVolume|Current|muted|volume" >> q13_volume.txt
    done
    ```
    比较 `A-before-ad`、`A-ad-playing-shadow-warming`、`A-committed` 三处的 `STREAM_MUSIC` 音量应**完全相同**（`dumpsys audio` 的字段名各机型略有差异，以原始输出为准，贴进结果）。
  - 判据：旧那一路（广告）声音不变；系统媒体音量不变；提交后新那一路（正片）正常出声。页面自带的属性级判据：预热时 `active.mute=no`、`shadow.mute=yes`，提交后 `live.mute=no`（`VERDICT Q13A PASS`）。
  - Windows 已有：属性级 3/3 通过（预热 `k1.mute=no / k2.mute=yes`，提交后 `k2.mute=no`；影子刚加载那一刻就已是 `mute=yes pause=no`，加载→静音之间没有漏声窗口）。**系统音量与听感 Windows 测不了。**
- [ ] **Q13-B 与 standby 叠加（提交时仍在待机）**
  - 做什么：预热期间请求待机，提交时仍在待机，不漏声；唤醒后正确恢复。
  - 怎么测：`ONLY=Q13B`；耳朵听提交那一刻到唤醒之间应**无声**；MARK 点同样采样系统音量。
  - 判据（standby 计划 Q13 修复记录）："预热与 standby 共用属性队列、分别持有静音，任意退出顺序均保留另一方并最终还原原值"。页面判据：提交后 `live.mute=yes`、`live.vid=no`、`standby=holding`；唤醒后 `mute=no`（`VERDICT Q13B PASS`）。
  - Windows 已有：3/3 通过。
- [ ] **Q13-C 与 standby 叠加（提交前就唤醒）**：`ONLY=Q13C`；判据：唤醒后影子**仍然静音**（预热还在持有），提交后 `live.mute=no`。Windows：2/3 通过，第 3 次是"影子 14s 内没加载"的搭建失败（见下），不是判据失败。
- 页面的一个已知偶发情况：**广告偶尔迟迟不换上**（Windows 上 `playAdNow` 之后影子 14s 没加载 1/12；更早两个没带诊断日志的构建里 100% 出现，原因没查清）。遇到时日志是 `... the ad never became the active engine` 或 `shadow k2 never loaded within 14s`，记录后重跑，**不要当成 Q13 失败**，但要在结果里写明次数。

### 5.4 CLAUDE.md / 文档里记为"未真机验证"的 UI 与手感项

这些没有脚本化，用 `lib/main.dart`（`flutter run -d $S --release -t lib/main.dart`，首页是 demo 列表）手动走，逐项写结果（通过/不通过/与预期不同 + 一句话现象 + 必要时截图/录屏）：

- [ ] **UI-1 横竖屏按钮**（CLAUDE.md「UI 插件化」："横竖屏按钮真机仍未验证"）。入口：`VOD · mp4` 全屏播放页顶栏的 `orientationButton`（仅移动端）。判据（同节描述）：点击在 `portrait`/`landscape` 间强制切换，**独立于全屏**；`auto` 恢复按宽高比定向；连续切换不闪退、画面不被拉伸。
- [ ] **UI-2 手势手感**（CLAUDE.md「直播时移」"仍未测：手势手感"）。入口：`VOD · mp4`。判据（CLAUDE.md「约定」手势侧别）：**左半屏竖滑 = 亮度、右半屏竖滑 = 音量**（`MovaGestureConfig` 默认），横滑 = 拖进度；记录触感（跟手度、灵敏度、误触、有没有 HUD 闪烁），主观项不要求"通过/不通过"，要求写事实。
- [ ] **UI-3 直播/时移 UI 交互**（CLAUDE.md「直播时移」"仍未测：直播/时移 UI 交互"）。入口：`直播 · DVR 可拖`、`直播 · 时移换源`（都是 mux 的 HLS 测试流，要手机能上外网）。判据（该节描述）：直播底栏有 `seekBar`/`timeshift`/`backToLive`；拖离边缘后 `timeshiftBehind` 变大并出现回直播入口，点 `backToLive` 回到边缘（`MovaLiveEdgeReach`）。
- [ ] **UI-4 PiP 按钮 / 系统 PiP 的 UI 路径**（CLAUDE.md "PiP/直播/时移 UI 等仍未系统走真机"）：默认皮肤里点画中画按钮进入 PiP，拉回全屏；与 HE-V11 互相印证。

---

## 6. 回写（结果写到哪里）

1. **两份计划各加一个子节**：HE 计划 Task 16 下、standby 计划 Task 10 下，紧接各自的「Windows 桌面实测（2026-10-24）」之后新增 **「Android 真机实测（<日期>）」**。内容与 Windows 子节同构：环境（设备、系统版本、构建模式 release/debug、源参数、GOP）、逐项分类表、每项原始数字（每次的值 + 平均值）、判定（通过/不通过/与预期不同）、关键日志摘录、发现与复现步骤。Q13 的结果写在 standby 计划里（Q13 修复记录处加一段）。UI 项（§5.4）写在 HE 计划的 Android 子节末尾。
2. **`mova/CLAUDE.md` 更新状态**：「宿主易用性增强」「低功耗待机」两节的"需真机确认"清单里，已在 Android 确认的点加 ✔Android，把标题里的"Android 待真机"改成实际状态；Q13 那条"待真机确认"改成确认结论；「直播时移」「UI 插件化」两节里"仍未测/未验证"的 UI 项按结果更新。
3. **测试基线**：没有测试改动就不动数字（当前 `mova` 下 1302、`example` 下 `auto_kit_test` 12）；若因为验证需要新增/修改了测试，**提交后立刻用当次实测的 `flutter test` 输出更新 `CLAUDE.md` 与相关计划里的基线**（项目约定）。
4. **提交**：格式 `type(mova): ...`，例如 `docs(mova): Android real-device results for HE T16, standby T10 and Q13`；只 `git add` 具体路径（`mova/CLAUDE.md`、`mova/doc/plans/*.md`），**禁止 `git add -A` / `git add .`**。
5. **推送**（`setup-remotes.sh` 之后 `git push origin main` 会同时推 codeup 和 GitHub）。推送前：
   ```bash
   git status                                  # 有超出本次指令范围的已修改未提交文件，先问再推
   git fetch origin
   git ls-remote origin main                   # codeup 的 head
   git ls-remote https://github.com/icodejoo/dart-labs.git main    # GitHub 的 head
   git rev-parse origin/main                   # 本地记的 origin/main
   ```
   **两个远端的 head 必须一致，且等于本地 `origin/main`，才可以 `git push origin main`**；不一致就停下来问人，不要 `--force`。LFS 对象的坑：`git lfs push --object-id origin` 在双 push-url 下不可靠（见 CLAUDE.md 运维踩坑记录），这次只改文档，不涉及 LFS 对象。

---

## 7. 发现 bug 时

**先记录证据和复现步骤，不要在验证过程中顺手改库代码。** 每个发现写：现象、复现命令（含 `--dart-define`）、每次的数字、日志摘录、对比 Windows 是否同样、你的推测（标明"推测"）。
修复按 mova 的流程走：**Opus 拆 `doc/plans/<date>-<feature>.md`（架构决策、逐 Task、代码块、单测断言、验收标准）→ Sonnet 逐 Task 落地（每个 Task 一个 commit，`flutter analyze` 0 issues + `flutter test` 全绿）→ 真机验证单独一轮**。
崩溃类问题尽量带回：`adb logcat -d` 的 fatal/backtrace、`/data/tombstones` 的路径（没有 root 就记命令与现象）、复现概率（N/N）。

---

## 附：参考

- 验证页与脚本源码：`mova/example/lib/verify_auto/`（`auto_kit.dart`、`he_auto.dart`、`standby_auto.dart`）、`mova/example/lib/main_q13_mute_verify.dart`、`mova/example/tool/verify_sources/`。
- 两份计划里的判据原文：[HE 计划 Task 16 表（V1–V12）](2026-10-23-host-ergonomics.md)、[standby 计划 Task 10 表（S1–S17）与 D13 默认值表](2026-10-23-standby-mode.md)。
- 项目约定与历史真机数据：`mova/CLAUDE.md`（「约定」「宿主易用性增强」「低功耗待机」「直播时移」「UI 插件化」）。
