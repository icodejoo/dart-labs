# WHEP：https 信令 + 无重传丢包基线（2026-10-02）

范围：补测两项此前没验证的内容，全部在 WSL（Linux x86_64，OpenSSL 3.5.5），服务端 MediaMTX v1.21.1。
不改 `patches/ffmpeg-whep/` 下任何补丁，只动 `tools/whep-flavor/` 与 README 的验证小节。
下面标"实测"的是跑出来的数字，标"推断"的是按 trace 推算的，没当实测写。

## 0. 环境与一个踩坑

- 被测：n9.0.2 + `0001`–`0006` 补丁，另起干净树 `/root/w/ffb-src`（`git clone --shared` t11/ffmpeg 后 checkout `n9.0.2`，逐个 `git apply`），
  构建三份：`/root/w/ffb-plain`（普通）、`/root/w/ffb-asan`（`--toolchain=gcc-asan`）、`/root/w/ffb-plain2`（普通 + `showinfo` 滤镜，丢包测试用）。
  configure 参数与 `t11/bplain` 相同（`--enable-demuxer=whep --enable-openssl --enable-protocol=http,https,tcp,tls,udp,file,pipe` 等）。
- **踩坑（实测）**：`/root/w/t11/{bprobe,bplain,basan}` 里的现成 ffmpeg 是旧构建，offer 的 `o=` 会话 ID 还是十六进制，
  MediaMTX 回 `400 failed to unmarshal SDP: syntax error`（commit 931d673 之前的行为）。别用它们测，上面三份是按当前补丁重新构建的。
- 独立的 MediaMTX 实例 `/root/w/whep-target-b`（复制二进制和 yml，另一个任务在用默认端口 8889/8189/8554，没碰）：
  WebRTC 信令 18889/tcp、ICE 18189/udp、RTSP 18554、RTP/RTCP 18000/18001，rtmp/hls/srt/moq 关闭；
  `start-b.sh` / `stop-b.sh` 只按 `mtx.pid`/`push.pid` 停，没 `pkill`。推流同 `whep-target`（testsrc2 640x360@25 + 440Hz，h264 baseline 400k g=50 + opus 32k）。
  https 测试时 `webrtcEncryption: true`，自签证书 `server.crt/key`（`openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1,DNS:localhost`），
  丢包测试时改回 `false`（信令走 http，因为 `whep_tamper_proxy.py` 用 urllib 转发）。
- 结束后 `stop-b.sh` 停掉自己的实例；测试期间和结束后另一实例（pid 50218，8889）一直在监听，未受影响。

## 1. whep+https

URL：`whep+https://127.0.0.1:18889/test/whep`，命令基线：
`ffmpeg -hide_banner -nostats -v verbose -f whep [-tls_verify N] [-ca_file F] -i URL -t 10 -f null -`

| # | 场景 | 结果（实测） |
|---|---|---|
| ① | `tls_verify=0`（默认） | 成功。普通构建 2 次：音频 505 包 / 482,880 采样（≈10.06s）/ 0 解码错误；视频 218、248 包，207、237 帧解码，0 解码错误；auth_fail=late=lost=0，STUN 6/4，结束 DELETE 成功 |
| ② | `tls_verify=1`，无 `ca_file` | 干净失败：`[tls] error:0A000086:SSL routines::certificate verify failed` → `WHEP POST ... failed: Input/output error`，退出码 251，不进入媒体阶段 |
| ③ | `tls_verify=1` + `-ca_file server.crt` | 成功。音频同基线（505 包 / 482,880 采样），视频 228 包 / 217 帧，0 解码错误，auth_fail=0 |
| ③b | `tls_verify=1` + 另一张无关自签证书当 CA | 干净失败（同 ②，退出码 251） |
| ⑤ | ASan 构建（含 LeakSanitizer）重复 ①②③③b | 行为同上（①两次 505 音频包、视频 249/228 包、0 错误；③ 视频 258 包 247 帧），日志里无 `Sanitizer`/`ERROR: ` |

视频帧数每次不同是因为起播要等 IDR（`before_keyframe` 9–49 帧不等），与 http 时一致。

④ 跨 host Location / https→http 降级：`tools/whep-flavor/whep_origin_regress.py` 新增 `--https --cert --key`。
evil 与转发代理都起 TLS，另起一个纯 TCP 明文监听器；统计的是 **TCP accept 次数**（比"收到请求"更严：握手失败、没发请求的连接也算），
并在明文监听器收到的字节里搜 token。

```
python3 tools/whep-flavor/whep_origin_regress.py --ffprobe /root/w/ffb-plain/ffprobe \
    --upstream https://127.0.0.1:18889 --https --cert server.crt --key server.key
```

| 场景 | 含义 | evil 连接 | 明文监听器连接 | 代理额外连接 | 代理 DELETE | 结果 |
|---|---|---|---|---|---|---|
| same | Location 同源 https（对照组） | 0 | 0 | 1 | 1（带 `Bearer`） | PASS |
| host | Location 指向 evil 的另一个 https 端口 | 0 | 0 | 0 | 0 | PASS |
| redir | 307 跳 evil https | 0 | 0 | 0 | 0 | PASS |
| downgrade | Location 改成同 host:port 的 `http://` | 0 | 0 | 0 | 0 | PASS |
| dg_other | Location 指向另一个纯 http 明文端口 | 0 | 0 | 0 | 0 | PASS |
| redir_http | 307 跳到明文 `http://` | 0 | 0 | 0 | 0 | PASS |

普通与 ASan 构建都是 6/6 PASS，`token_in_plain=False`。http 模式（3 个场景）也回归过，3/3 PASS。
对照组 same 证明测试链路有效（DELETE 确实到了代理且带 token）；降级场景下客户端在 POST 之后没有再建任何连接，token 没外泄。

## 2. 无重传（NACK/PLI 未实现）丢包基线，供 T1.5 对比

### 做法

`whep_tamper_proxy.py` 的 lossy 模式：UDP 中继放在客户端与 MediaMTX 的 ICE 端口之间，只对服务端→客户端的 RTP 注入故障。
本次给它加了环境变量 `UP_URL / MEDIA_PORT / RELAY_PORT / SILENT_PORT / SEED / TRACE`（默认值保持旧行为），`TRACE` 每个 RTP 写一行
`序号,相对秒,seq,rtp时间戳,pt,marker,动作,长度`，SIGTERM 时打印 `relay FINAL {...}`。
批量跑用新脚本 `tools/whep-flavor/whep_loss_baseline.py`（标准库，LF）：每次起一个 proxy、拉 30s、收集客户端日志 / 解码器日志 / 两路 `-c copy` 的 framecrc。

```
python3 tools/whep-flavor/whep_loss_baseline.py --ffmpeg /root/w/ffb-plain2/ffmpeg \
    --proxy tools/whep-flavor/whep_tamper_proxy.py --up-url http://127.0.0.1:18889 --media-port 18189 \
    --duration 30 --rates 0,0.5,2,5,mix --runs 3 --out /root/w/whep-target-b/lossy-run
python3 tools/whep-flavor/whep_loss_baseline.py --summarize --out /root/w/whep-target-b/lossy-run   # 出下面的表
```

- 档位：0%（对照，1 次）、0.5% / 2% / 5%（**纯丢包**，SWAP=DUP=CORRUPT=0，各 3 次）、`mix`（2% 丢 + 2% 相邻交换 + 1% 重复 + 1% 翻转载荷，3 次，用来验证各计数器一一对应）。
- 种子（每次不同，已写进 `result.json`）：0%：1007；0.5%：6007/6014/6021；2%：21007/21014/21021；5%：51007/51014/51021；mix：1784/1791/1798。
- 原始产物（trace、客户端日志、框 CRC、result.json、all.json）：`/root/w/whep-target-b/lossy-run/`（7.5MB，不入库）。
- 实际丢包率：0.5% 档注入视频 10.7 / 1971 ≈ 0.54%；2% 档 41.7 / 2006 ≈ 2.1%；5% 档 104.7 / 1959 ≈ 5.3%。
- 每次 30s 窗口里视频约 1970 包 / 770 帧（≈25.2fps），音频约 1550 包；GOP=50 帧（2s），IDR 约 10 个 RTP 包。

### 计数是否一一对应（实测）

纯丢包档：

| 档位 | 注入丢（视频/音频，均值） | 客户端 `lost`（视频/音频） | auth_fail | late/dup |
|---|---|---|---|---|
| 0.5% | 10.7 / 7.7 | 10.7 / 7.7 | 0 | 0 |
| 2% | 41.7 / 30.0 | 41.7 / 30.0 | 0 | 0 |
| 5% | 104.7 / 75.7 | 104.3 / 75.0 | 0 | 0 |

`lost` 与注入数逐次相等；仅 5% 档有 3 个差 1（音频 72→71、86→85 和视频 103→102），都是 `-t 30` 结束瞬间飞行中的包，不是漏计。
混合档（每次逐项对）：

| 次 | 视频 注入 corrupt → `auth_fail` | 视频 注入 dup → `late/dup` | 视频 注入 drop+corrupt → `lost` | 音频 corrupt → auth_fail | 音频 dup → late | 音频 drop+corrupt → lost |
|---|---|---|---|---|---|---|
| 1 | 27 → 27 | 15 → 15 | 34+27=61 → 61 | 16 → 16 | 17 → 18 | 32+16=48 → 48 |
| 2 | 19 → 19 | 14 → 14 | 30+19=49 → 49 | 13 → 13 | 15 → 15 | 24+13=37 → 37 |
| 3 | 22 → 22 | 25 → 25 | 36+22=58 → 58 | 20 → 20 | 16 → 16 | 34+20=54 → 53 |

交换（视频 28/31/51，音频 34/32/35 次）全部被重排队列救回，没有计入 lost。两处差 1：音频 dup 17→18（多一个 late，推断是一个被扣下的包在缺口超时后才到）、音频 lost 54→53（结束瞬间）。

### 解码与画面（每档 3 次均值，0% 为 1 次；30s 窗口）

| 档位 | 丢弃不完整帧 `dropped_frames` | 有丢包的视频帧（trace） | ffmpeg "decode errors" | `corrupt decoded frame` 行 | `concealing … errors` 行 | 解码帧数 |
|---|---|---|---|---|---|---|
| 0% | 0 | 0 | 0 | 0 | 0 | 752 |
| 0.5% | 7.7 | 10.7 | **0** | 3.0 | 3.0 | 741 |
| 2% | 22.7 | 41.3 | **0** | 18.0 | 18.7 | 721 |
| 5% | 57.7 | 99.3 | **0** | 35.7 | 39.0 | 664 |
| mix | 32.7 | 54.3 | 0 | 18.7 | 20.7 | 707 |

- **ffmpeg 的 "N decode errors" 计数全程是 0**：解码器把缺失当成可隐藏的错误，不上报。要看到损伤只能数 `corrupt decoded frame` / `concealing N DC, N AC, N MV errors in P frame` 这两类日志行（二者几乎 1:1）。
- **`dropped_frames` 低估损伤**：它只数"缺口发生时 AU 正开着、或 FU-A 起始片丢了"的帧。若丢的是某帧**开头**的包而后续是完整 NAL，该帧会不完整地被交给解码器（不计入 `dropped_frames`）。
  证据（实测）：`有丢包帧 − dropped_frames` = 3.0 / 18.7 / 41.7（0.5% / 2% / 5%）≈ `concealing` 行 3.0 / 18.7 / 39.0。
  即被计数器漏掉的那部分基本都以"带缺失的帧"进了解码器并触发隐藏。T1.5 若按丢包重传，这个口径要一并修（缺口位于 AU 起点时也应置 `au_bad`）。
- 整帧丢光（所有包都丢，无法被任何计数器发现）很少：5% 档平均 2 帧。

### 花屏持续时间（**推断**，非解码器实测）

载荷是 SRTP 加密的，中继看不到 NAL 类型，用"帧字节数 > 3 倍中位数"识别 IDR（0% 对照：16 个 IDR，与 30s/2s≈15 一致，`showinfo` 看到 15 个关键帧；
起播丢帧模型值 14.0 与客户端 `before_keyframe` 14 吻合，说明识别可用）。客户端起播后**不再等 IDR**（只有 `seen_key` 之前才丢 P 帧），
所以任何受损帧（含被漏计的）之后，后续 P 帧都参考错位，直到下一个**完整**的 IDR 才恢复。窗口 = 受损帧 → 下一个完整 IDR；窗口内再丢包不新开窗口，IDR 本身受损则窗口延长。

| 档位 | 花屏事件数 | 花屏累计秒（占 30s） | 单次平均 s | 单次最长 s | 带损 IDR / 总 IDR | 起播丢帧（model / 客户端 before_keyframe） |
|---|---|---|---|---|---|---|
| 0% | 0 | 0 | – | – | 0 / 16 | 14.0 / 14.0 |
| 0.5% | 7.3 | 9.27（≈31%） | 1.28 | 4.00 | 1.0 / 16 | 5.7 / 5.7 |
| 2% | 11.7 | 21.48（≈72%） | 1.85 | 5.52 | 3.0 / 16.3 | 22.7 / 21.7 |
| 5% | 7.3 | 27.84（≈93%） | 4.04 | 11.96 | 7.7 / 16 | 4.7 / 4.3 |
| mix | 11.3 | 22.67 | 2.06 | 9.48 | 3.0 / 16 | 17.0 / 16.0 |

读法：IDR 约 10 个包，丢包率 p 时单个 IDR 带损概率 ≈ 1-(1-p)^10（0.5%≈5%、2%≈18%、5%≈40%；实测 1/16、3/16、7.7/16）。
IDR 一旦受损，花屏要多拖一个 GOP（2s），所以 5% 档单次最长到 11.96s，几乎全程花屏。
2% 的丢包就让约 72% 的时间处在"某处参考已错位"状态，这是没有 NACK/PLI 时的基线。**注意这个窗口是推断**；解码器侧能直接看到的只有上表 `corrupt`/`concealing` 行（只覆盖"带缺失进解码器"的帧，不含被客户端丢弃的帧造成的后续漂移）。

### 画面停顿与音频连续性（实测，`-c copy` framecrc 的 pts 空洞）

| 档位 | 视频 pts 空洞数 / 累计缺失 s / 最长 s | 音频 pts 空洞数 / 累计缺失 s / 最长 s | 音频采样数 |
|---|---|---|---|
| 0% | 0 / 0 / 0 | 0 / 0 / 0 | 1,442,880 |
| 0.5% | 7.0 / 0.28 / 0.04 | 7.3 / 0.15 / 0.02 | 1,435,840 |
| 2% | 20.7 / 0.83 / 0.04 | 29.0 / 0.59 / 0.04 | 1,414,720 |
| 5% | 52.7 / 2.29 / 0.08 | 70.0 / 1.44 / 0.04 | 1,374,080 |
| mix | 29.7 / 1.28 / 0.08 | 43.3 / 0.89 / 0.04 | 1,400,000 |

- 音频：每个丢失的 Opus 包就是时间轴上一个 20ms 洞（2% 档：29 个洞 ≈ 0.59s = 29×20ms），没有丢包隐藏（PLC）也没有补静音，解码器直接把相邻包接上；
  最长连续缺 2 个包（40ms）。**不连续**——只是每个洞很短（听感上是咔哒声），不是长静音。
- 视频：被丢掉的不完整帧在时间轴上是 40ms 的洞；解码帧数随丢包率降低（752 → 741 → 721 → 664）。

### ASan 下的丢包

`ffb-asan`（无 showinfo，脚本加 `--no-showinfo`），5% 与 mix 各 2 次、每次 20s，退出码 0，日志无 `Sanitizer` / `ERROR: ` / leak 报告；
注入数与 `lost`/`auth_fail`/`late` 计数同普通构建的对应关系一致（如 5%：72→72、75→75；mix：corrupt 15→auth_fail 15）。

## 3. 局限与未验证

- 仅回环（127.0.0.1）上的随机独立丢包，没有突发丢包、没有延迟/抖动；真实网络的丢包常成簇，窗口数字会不同。
- 花屏窗口是按 trace 推断的，没有用像素比对做逐帧真值；IDR 靠帧大小识别，对照组验证过但没覆盖场景切换产生的额外 IDR。
- 每档 3 次，不同次之间波动大（如 5% 档视频 IDR 带损 5/9/9 个），均值仅作量级参考；`mix` 档的丢包比例不是纯丢包，不要拿它和纯丢包档比花屏。
- 只测 MediaMTX v1.21.1 一种服务端；Windows(SChannel) / Android(mbedTLS) 后端没有在这里重测 https 与丢包。
- `-t 30` 为输入时长，注入侧 trace 覆盖整个中继生命周期（含起播前、关闭后的少量包），个别计数有 ±1 边界差，已在上文标出。
